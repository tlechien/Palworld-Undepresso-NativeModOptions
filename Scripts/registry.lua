-- Schema bookkeeping and in-process event fan-out. No UObject code lives here.
--
-- One schema per mod id. `values[id]` is the last committed snapshot; `pending[id]` is the working
-- copy an open panel edits before Apply. This mirrors vanilla's own cache-then-commit pattern.
local Persistence = require("persistence")
local Shared = require("shared")
local json = require("json")

local MOD_TAG = "[NativeModOptions]"
local KEY_PATTERN = "^[A-Za-z0-9_.-]+$"
local VALID_TYPES = { boolean = true, number = true, enum = true, keybind = true,
    section = true, image = true, warning = true }
-- Types that do NOT carry a value. A section is a label between rows: never staged, applied,
-- persisted or broadcast, and given no entry in `values`, so nothing downstream has to special-case
-- a key that has no meaningful state.
local DISPLAY_ONLY_TYPES = { section = true, image = true, warning = true }

local Registry = {
    schemas = {},      -- [id] = schema
    order = {},         -- [1..n] = id, in registration order -- panel_build.lua's layout order
    values = {},          -- [id][key] = committed value
    pending = {},           -- [id][key] = value currently being edited in an open panel, or nil
    subscribers = {},        -- [id] = { fn, fn, ... }
}

-- Display-only types carry no value; callers use this instead of testing for "section" by name.
function Registry.isDisplayOnly(optionType)
    return DISPLAY_ONLY_TYPES[optionType] == true
end

local function log(message)
    print(MOD_TAG .. " " .. message)
end

local function validateOption(option, seenKeys)
    if type(option.key) ~= "string" or not option.key:match(KEY_PATTERN) then
        return "option key invalid or missing: " .. tostring(option.key)
    end
    if seenKeys[option.key] then
        return "duplicate option key: " .. option.key
    end
    if not VALID_TYPES[option.type] then
        return "unsupported option type '" .. tostring(option.type) .. "' for key " .. option.key
            .. " (boolean/number/enum/keybind/section/image/warning only -- see the wiki)"
    end
    if DISPLAY_ONLY_TYPES[option.type] then
        -- Display-only entries need a key to stay unique but carry no value, default or range.
        if (option.type == "section" or option.type == "warning")
            and (type(option.label) ~= "string" or option.label == "") then
            return option.type .. " '" .. option.key .. "' requires a label"
        end
        if option.type == "image" and (type(option.texture) ~= "string" or option.texture == "") then
            return "image '" .. option.key .. "' requires a texture object path"
        end
        seenKeys[option.key] = true
        return nil
    end
    if option.type == "number" then
        if type(option.min) ~= "number" or type(option.max) ~= "number" then
            return "number option '" .. option.key .. "' requires numeric min and max"
        end
    end
    if option.type == "keybind" and option.modifiers ~= nil then
        -- Optional. Declares that the shortcut also requires these modifiers, which is what keeps a
        -- Ctrl+<key> binding from being reported as conflicting with the game's bare-key actions.
        if type(option.modifiers) ~= "table" then
            return "keybind option '" .. option.key .. "' modifiers must be an array of strings"
        end
        for _, modifier in ipairs(option.modifiers) do
            if type(modifier) ~= "string" or modifier == "" then
                return "keybind option '" .. option.key .. "' has a non-string modifier"
            end
        end
    end
    if option.type == "enum" then
        if type(option.choices) ~= "table" or #option.choices == 0 then
            return "enum option '" .. option.key .. "' requires a non-empty choices array"
        end
        local foundDefault = false
        for _, choice in ipairs(option.choices) do
            if type(choice.value) ~= "string" or type(choice.label) ~= "string" then
                return "enum option '" .. option.key .. "' has a choice missing value/label"
            end
            if choice.value == option.default then
                foundDefault = true
            end
        end
        if not foundDefault then
            return "enum option '" .. option.key .. "' default does not match any choice value"
        end
    end
    seenKeys[option.key] = true
    return nil
end

-- Validates and stores a schema, seeding values[id] from defaults if this is the first
-- registration this session. Returns true on success, false (and logs why) on a bad schema.
function Registry.register(schema)
    if type(schema) ~= "table" or type(schema.id) ~= "string" or not schema.id:match(KEY_PATTERN) then
        log("Rejected schema: id invalid or missing")
        return false
    end
    if type(schema.title) ~= "string" or schema.title == "" then
        log("Rejected schema '" .. tostring(schema.id) .. "': title missing")
        return false
    end
    if type(schema.options) ~= "table" then
        log("Rejected schema '" .. schema.id .. "': options missing")
        return false
    end
    local seenKeys = {}
    for _, option in ipairs(schema.options) do
        local err = validateOption(option, seenKeys)
        if err then
            log("Rejected schema '" .. schema.id .. "': " .. err)
            return false
        end
    end

    if Registry.schemas[schema.id] == nil then
        table.insert(Registry.order, schema.id)
    end
    Registry.schemas[schema.id] = schema
    Registry.subscribers[schema.id] = Registry.subscribers[schema.id] or {}

    local values = Registry.values[schema.id] or {}
    local persisted = Persistence.load(schema.id)
    for _, option in ipairs(schema.options) do
        if DISPLAY_ONLY_TYPES[option.type] then
            values[option.key] = nil
        elseif persisted and persisted[option.key] ~= nil then
            values[option.key] = persisted[option.key]
        elseif values[option.key] == nil then
            values[option.key] = option.default
        end
    end
    Registry.values[schema.id] = values
    Registry.pending[schema.id] = nil

    log("Registered '" .. schema.id .. "' (" .. #schema.options .. " option"
        .. (#schema.options == 1 and "" or "s") .. ")")
    return true
end

-- Processes pending registrations from other mods, which run in their own Lua VM and can only hand
-- over a schema through shared variables.
--
-- Called on every panel build. Deferring to that point only affects when a schema gets a visible
-- row: a consumer's values are correct from its own first frame regardless, since it reads the
-- persisted config directly. Already-registered ids are skipped, so repeat calls are cheap.
function Registry.discoverPending()
    local pendingIds = Shared.get(Shared.PREFIX .. "PendingRegistry")
    if type(pendingIds) ~= "string" or pendingIds == "" then
        return
    end
    for id in pendingIds:gmatch("[^\r\n]+") do
        if Registry.schemas[id] == nil then
            local encoded = Shared.get(Shared.PREFIX .. "PendingManifest." .. id)
            if type(encoded) == "string" then
                local ok, schema = pcall(json.decode, encoded)
                if ok and type(schema) == "table" then
                    Registry.register(schema)
                else
                    log("Failed to decode pending manifest for '" .. id .. "'")
                end
            end
        end
    end
end

-- Every registered keybind with the binding it would use, so a row can report a chord another mod
-- has already claimed. The game's own key config cannot reveal that: a mod's shortcut is not a game
-- input action. Pending values win over committed ones, so a clash shows while still editing.
function Registry.keybindings()
    local bindings = {}
    for _, id in ipairs(Registry.order) do
        local schema = Registry.schemas[id]
        local pending = Registry.pending[id]
        local values = Registry.values[id] or {}
        for _, option in ipairs(schema.options) do
            if option.type == "keybind" then
                local value = values[option.key]
                if pending ~= nil and pending[option.key] ~= nil then
                    value = pending[option.key]
                end
                if type(value) == "string" and value ~= "" then
                    bindings[#bindings + 1] = {
                        modId = id,
                        title = schema.title,
                        key = option.key,
                        label = option.label,
                        value = value,
                        modifiers = option.modifiers,
                    }
                end
            end
        end
    end
    return bindings
end

function Registry.subscribe(id, callback)
    if type(callback) ~= "function" then
        return
    end
    Registry.subscribers[id] = Registry.subscribers[id] or {}
    table.insert(Registry.subscribers[id], callback)
end

-- Starts (or resets) a pending edit buffer for an open panel -- a copy of the committed values,
-- so row widgets can be seeded and the player can cancel out without side effects.
function Registry.beginEdit(id)
    local values = Registry.values[id]
    if not values then
        return {}
    end
    local pending = {}
    for key, value in pairs(values) do
        pending[key] = value
    end
    Registry.pending[id] = pending
    return pending
end

-- Notified when a staged value first diverges from what is committed. Set by whoever owns the open
-- screen, which uses it to raise vanilla's "something changed" flag -- the flag that makes the screen
-- prompt to apply on the way out.
--
-- Fired only on a real divergence: returning a value to where it started is not a change.
Registry.onChanged = nil

-- Called by a row on every native change-delegate fire. Updates the pending buffer only: no
-- persistence and no fan-out until Registry.apply.
function Registry.stage(id, key, value)
    Registry.pending[id] = Registry.pending[id] or {}
    Registry.pending[id][key] = value
    local values = Registry.values[id]
    if Registry.onChanged ~= nil and values ~= nil and values[key] ~= value then
        local ok, err = pcall(Registry.onChanged, id, key, value)
        if not ok then
            log("onChanged listener error for '" .. id .. "." .. key .. "': " .. tostring(err))
        end
    end
end

-- Commits every staged value for one mod: persists, updates the committed snapshot, and fires
-- subscribers once per key that actually changed. The only place apply semantics live.
function Registry.apply(id)
    local pending = Registry.pending[id]
    if not pending then
        return
    end
    local values = Registry.values[id] or {}
    local changed = {}
    for key, newValue in pairs(pending) do
        if values[key] ~= newValue then
            values[key] = newValue
            table.insert(changed, key)
        end
    end
    Registry.values[id] = values
    Registry.pending[id] = nil
    if #changed > 0 then
        Persistence.save(id, values)
        for _, key in ipairs(changed) do
            for _, callback in ipairs(Registry.subscribers[id] or {}) do
                local ok, err = pcall(callback, key, values[key], "apply")
                if not ok then
                    log("Subscriber error for '" .. id .. "." .. key .. "': " .. tostring(err))
                end
            end
        end
    end
    return changed
end

function Registry.discardEdit(id)
    Registry.pending[id] = nil
end

-- Programmatic set (source = "api"), for a mod changing one of its own values without the panel being
-- open. Bypasses the pending/Apply flow and persists immediately: there is no pending state for a
-- non-UI change.
function Registry.set(id, key, value)
    local values = Registry.values[id]
    if not values or values[key] == value then
        return
    end
    values[key] = value
    Persistence.save(id, values)
    for _, callback in ipairs(Registry.subscribers[id] or {}) do
        local ok, err = pcall(callback, key, value, "api")
        if not ok then
            log("Subscriber error for '" .. id .. "." .. key .. "': " .. tostring(err))
        end
    end
end

return Registry
