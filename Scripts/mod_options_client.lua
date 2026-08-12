-- Client library for Native Mod Options. Copy this file and json.lua into your own mod's Scripts/
-- folder; see the wiki for the schema reference and a worked example.
--
-- Self-contained by design: UE4SS mods cannot require() each other's files, so the shared-variable
-- and hook-parameter helpers below are duplicated here rather than shared with the framework.
--
-- Protocol:
--   Registration -- append your schema id to NativeModOptions.V1.PendingRegistry (newline
--     separated) and write the JSON schema to NativeModOptions.V1.PendingManifest.<id>. The
--     framework picks it up the next time its options panel is built.
--   Boot values -- read directly from NativeModOptions.V1.ConfigDirectory (<dir>\<id>.ini, one
--     `key=json_value` per line), so they are correct from the first frame whether or not
--     registration has been processed.
--   Live changes -- no polling. subscribe() hooks the same native row functions the framework calls
--     once per row immediately after it commits a change, filtered to this schema's rows by object
--     address.
local json = require("json")

local PREFIX = "NativeModOptions.V1."
-- The framework's own Mods folder name, used to locate its config directory without depending on
-- mods.txt load order. See derivedConfigDirectory.
local FRAMEWORK_MOD_NAME = "NativeModOptions"
local SWITCH_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContentSwitch.WBP_OptionSettings_ListContentSwitch_C"
local SLIDER_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContentSlider.WBP_OptionSettings_ListContentSlider_C"
local LR_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContentLR.WBP_OptionSettings_ListContentLR_C"
local LIST_CONTENT_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContent.WBP_OptionSettings_ListContent_C"

local function sharedGet(key)
    if ModRef == nil then
        return nil
    end
    local ok, value = pcall(function() return ModRef:GetSharedVariable(key) end)
    return ok and value or nil
end

local function sharedSet(key, value)
    if ModRef == nil then
        return false
    end
    return pcall(function() ModRef:SetSharedVariable(key, value) end)
end

-- UE4SS passes hook arguments wrapped; other values arrive as-is.
local function readParam(param)
    if param == nil or type(param) ~= "userdata" then
        return param
    end
    local ok, unrealType = pcall(function() return param:type() end)
    if not ok or (unrealType ~= "RemoteUnrealParam" and unrealType ~= "LocalUnrealParam") then
        return param
    end
    -- A boolean false must survive: `readOk and value or nil` collapses it to nil, which notify()
    -- then discards as unreadable.
    local readOk, value = pcall(function() return param:get() end)
    if not readOk then
        return nil
    end
    return value
end

local function addressOf(object)
    if object == nil then
        return nil
    end
    local ok, address = pcall(function() return object:GetAddress() end)
    if ok and address ~= nil and address ~= 0 then
        return address
    end
    return nil
end

local function scriptDirectory()
    local source = debug.getinfo(1, "S").source or ""
    source = source:sub(1, 1) == "@" and source:sub(2) or source
    return source:match("^(.*)[/\\][^/\\]+$")
end

-- The framework's config directory, worked out from this file's own location:
--   <Mods>/<ThisMod>/Scripts  ->  <Mods>/NativeModOptions
--
-- The framework publishes that path as a shared variable when it loads, and mods.txt order decides
-- who loads first: a consumer listed above it would read nothing and fall back to schema defaults,
-- losing the player's saved settings for the session.
--
-- The mod root, not Scripts/config: UE4SS reloads a mod whenever a file in its Scripts directory is
-- written, so the framework must not save there. Both directories are read, newest layout first, so
-- an install still on the old layout keeps its settings.
local function derivedConfigDirectories()
    local scripts = scriptDirectory()
    if scripts == nil then
        return {}
    end
    local modDirectory = scripts:match("^(.*)[/\\][^/\\]+$")
    if modDirectory == nil then
        return {}
    end
    local modsDirectory = modDirectory:match("^(.*)[/\\][^/\\]+$")
    if modsDirectory == nil then
        return {}
    end
    local frameworkRoot = modsDirectory .. "\\" .. FRAMEWORK_MOD_NAME
    return { frameworkRoot, frameworkRoot .. "\\Scripts\\config" }
end

-- Returns a key->value table, or nil when unavailable -- framework not installed, first run, and so
-- on. The caller keeps its schema defaults in that case.
--
-- The published path is preferred because it stays correct if the framework's folder is renamed; the
-- derived one is the fallback for when the framework has not loaded yet.
local function readPersistedValues(id)
    -- ipairs stops at the first nil, and the published path is nil in exactly the case the derived
    -- one covers, so these are appended rather than written as a literal.
    local candidates = {}
    local published = sharedGet(PREFIX .. "ConfigDirectory")
    if type(published) == "string" and published ~= "" then
        candidates[#candidates + 1] = published
    end
    for _, derived in ipairs(derivedConfigDirectories()) do
        candidates[#candidates + 1] = derived
    end

    local file = nil
    for _, directory in ipairs(candidates) do
        file = io.open(directory .. "\\" .. id .. ".ini", "r")
        if file then
            break
        end
    end
    if not file then
        return nil
    end
    local values = {}
    for line in file:lines() do
        local key, encoded = line:match("^%s*([%w_.-]+)%s*=%s*(.-)%s*$")
        if key and encoded then
            local ok, decoded = pcall(json.decode, encoded)
            if ok then
                values[key] = decoded
            end
        end
    end
    file:close()
    return values
end

local ModOptionsClient = {}
ModOptionsClient.__index = ModOptionsClient

function ModOptionsClient.new(schema)
    local self = setmetatable({}, ModOptionsClient)
    self.schema = schema
    self.id = schema.id
    self.values = {}
    for _, option in ipairs(schema.options) do
        self.values[option.key] = option.default
    end
    local persisted = readPersistedValues(schema.id)
    if persisted then
        for _, option in ipairs(schema.options) do
            if persisted[option.key] ~= nil then
                self.values[option.key] = persisted[option.key]
            end
        end
    end
    self.callbacks = {}
    return self
end

function ModOptionsClient:register()
    local ok, encoded = pcall(json.encode, self.schema)
    if not ok then
        print("[ModOptionsClient] Failed to encode schema for " .. tostring(self.id) .. ": "
            .. tostring(encoded))
        return false
    end
    local registry = sharedGet(PREFIX .. "PendingRegistry")
    registry = type(registry) == "string" and registry or ""
    local already = false
    for id in registry:gmatch("[^\r\n]+") do
        if id == self.id then
            already = true
            break
        end
    end
    if not already then
        registry = registry .. (registry == "" and "" or "\n") .. self.id
        sharedSet(PREFIX .. "PendingRegistry", registry)
    end
    sharedSet(PREFIX .. "PendingManifest." .. self.id, encoded)
    return true
end

-- Hooks are installed once per mod VM but must serve every client in it, so they close over this
-- list rather than over a single client. A mod declaring two schemas gets events for both.
local hookedClasses = {}
local clients = {}

local function notify(client, option, newValue)
    if newValue == nil or client.values[option.key] == newValue then
        return
    end
    client.values[option.key] = newValue
    for _, callback in ipairs(client.callbacks) do
        local ok, err = pcall(callback, option.key, newValue, "apply")
        if not ok then
            print("[ModOptionsClient] subscriber error for " .. client.id .. "." .. option.key
                .. ": " .. tostring(err))
        end
    end
end

-- address -> { client, option }, rebuilt only when the framework reports a new row epoch.
--
-- The hooks below are class-level: they fire for every settings row in the game, so most calls are
-- not ours. One epoch read plus a table lookup resolves them; reading a shared variable per option
-- per fire would put a pcall into the engine on the hot path of every slider drag.
local rowIndex, rowIndexEpoch = nil, nil

local function rebuildRowIndex(epoch)
    local index = {}
    for _, client in ipairs(clients) do
        for _, option in ipairs(client.schema.options) do
            local address = sharedGet(PREFIX .. "RowAddress." .. client.id .. "." .. option.key)
            if address ~= nil then
                index[tostring(address)] = { client = client, option = option }
            end
        end
    end
    rowIndex, rowIndexEpoch = index, epoch
end

-- RegisterHook throws while the target Blueprint class's package is not loaded, and subscribe() runs
-- at mod boot, before the options-menu widgets exist. NotifyOnNewObject accepts an unloaded class and
-- fires on the first construction, at which point RegisterHook succeeds. No retry timer, no polling.
--
-- hookedClasses is set only on success, so a failed early attempt retries rather than marking the
-- class done; pendingHooks stops a second subscribe() in the same VM stacking another watcher.
local pendingHooks = {}

local function registerWhenLoaded(classPath, hookKey, handler)
    if hookedClasses[hookKey] then
        return
    end
    if pcall(RegisterHook, hookKey, handler) then
        hookedClasses[hookKey] = true
        return
    end
    if pendingHooks[hookKey] then
        return
    end
    -- Marked pending only once the watcher is installed: setting it beforehand strands the hook
    -- permanently if NotifyOnNewObject itself fails.
    local watching = pcall(NotifyOnNewObject, classPath, function()
        if hookedClasses[hookKey] then
            return
        end
        if pcall(RegisterHook, hookKey, handler) then
            hookedClasses[hookKey] = true
        end
    end)
    if watching then
        pendingHooks[hookKey] = true
    end
end

local function installRowHook(classPath, functionName, readNewValue)
    local hookKey = classPath .. ":" .. functionName
    registerWhenLoaded(classPath, hookKey, function(Context, ...)
        local address = addressOf(readParam(Context))
        if address == nil then
            return
        end
        local epoch = sharedGet(PREFIX .. "RowEpoch")
        if rowIndex == nil or epoch ~= rowIndexEpoch then
            rebuildRowIndex(epoch)
        end
        local entry = rowIndex[tostring(address)]
        if entry ~= nil then
            notify(entry.client, entry.option, readNewValue(entry.option, ...))
        end
    end)
end

-- Keybind rows have no native setter carrying their value: the key lives in a brush on an image and
-- nothing hookable takes it as an argument. The committed value is re-read from the framework's
-- config file, written before the rows are re-affirmed and so already current here.
--
-- SetKeyWarning is the hook: the framework calls it on every keybind refresh. Extra fires are
-- harmless, notify() dropping anything equal to what the client holds.
local function installKeybindHook()
    local hookKey = LIST_CONTENT_CLASS .. ":SetKeyWarning"
    registerWhenLoaded(LIST_CONTENT_CLASS, hookKey, function(Context)
        local address = addressOf(readParam(Context))
        if address == nil then
            return
        end
        local epoch = sharedGet(PREFIX .. "RowEpoch")
        if rowIndex == nil or epoch ~= rowIndexEpoch then
            rebuildRowIndex(epoch)
        end
        local entry = rowIndex[tostring(address)]
        if entry == nil or entry.option.type ~= "keybind" then
            return
        end
        local persisted = readPersistedValues(entry.client.id)
        if persisted == nil then
            return
        end
        notify(entry.client, entry.option, persisted[entry.option.key])
    end)
end

-- Subscribes to committed changes. Safe to call more than once; each callback is added
-- independently. The first call for any schema in this VM installs the row hooks.
function ModOptionsClient:subscribe(callback)
    if type(callback) ~= "function" then
        return
    end
    table.insert(self.callbacks, callback)

    local registered = false
    for _, client in ipairs(clients) do
        if client == self then
            registered = true
            break
        end
    end
    if not registered then
        table.insert(clients, self)
        -- The cached index is keyed by epoch and adding a client does not change the epoch, so it has
        -- to be dropped here or this client's rows stay unresolvable until the next panel rebuild.
        rowIndex, rowIndexEpoch = nil, nil
    end

    installRowHook(SWITCH_CLASS, "Setup", function(option, isOn)
        if option.type ~= "boolean" then
            return nil
        end
        local value = readParam(isOn)
        if value == nil then
            return nil
        end
        -- Returned directly: `... or nil` would turn false back into nil.
        return value and true or false
    end)
    installRowHook(SLIDER_CLASS, "SetValue", function(option, value)
        if option.type ~= "number" then
            return nil
        end
        return tonumber(readParam(value))
    end)
    installRowHook(LR_CLASS, "SelectByIndex", function(option, index)
        if option.type ~= "enum" then
            return nil
        end
        local position = tonumber(readParam(index))
        if position == nil then
            return nil
        end
        local choice = option.choices[position + 1]   -- the native index is 0-based
        return choice ~= nil and choice.value or nil
    end)
    installKeybindHook()
end

-- Programmatic set from the owning mod's own code, without the panel being open. Updates the local
-- value and fires this client's subscribers with source="api". Persists nothing: the framework owns
-- the config file, and writing it here would race the framework's own save on Apply.
function ModOptionsClient:set(key, value)
    if self.values[key] == value then
        return
    end
    self.values[key] = value
    for _, callback in ipairs(self.callbacks) do
        local ok, err = pcall(callback, key, value, "api")
        if not ok then
            print("[ModOptionsClient] subscriber error for " .. self.id .. "." .. key .. ": "
                .. tostring(err))
        end
    end
end

return ModOptionsClient
