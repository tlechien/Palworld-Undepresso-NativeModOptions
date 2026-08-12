-- One <id>.ini file per registered mod, `key=json_value` per line.
--
-- Loaded once per schema at Registry.register(), so values are correct from boot rather than
-- discovered the first time a panel is opened.
local json = require("json")
local Shared = require("shared")

local MOD_TAG = "[NativeModOptions]"

-- debug.getinfo(1, "S").source is "@<absolute path to this file>".
local function scriptDirectory()
    local source = debug.getinfo(1, "S").source or ""
    source = source:sub(1, 1) == "@" and source:sub(2) or source
    return source:match("^(.*)[/\\][^/\\]+$") or "."
end

local SCRIPT_DIRECTORY = scriptDirectory()

-- Config is written to the MOD ROOT, not into Scripts/.
--
-- UE4SS's EnableAutoReloadingLuaMods watches the Scripts directory and reloads the mod when any file
-- there is written. Saving into Scripts/config therefore reloaded this mod one second after every
-- Apply: its state tables were reset, the injected category button was orphaned, and Mod Options
-- vanished from the screen on the next open. The mod root is not watched, and it always exists --
-- it is the folder Scripts/ lives in -- so nothing has to create a directory that InstallRule
-- (which ships Scripts/ only) would never produce on a player's install.
local CONFIG_DIRECTORY = SCRIPT_DIRECTORY:match("^(.*)[/\\][^/\\]+$") or SCRIPT_DIRECTORY
-- Where saves used to go. Read as a fallback so an existing install keeps its settings.
local LEGACY_CONFIG_DIRECTORY = SCRIPT_DIRECTORY .. "\\config"

-- Published at load so a consumer mod can read its persisted values at its own boot, without waiting
-- for Registry.discoverPending() to have processed its registration.
Shared.set(Shared.PREFIX .. "ConfigDirectory", CONFIG_DIRECTORY)

local function configPath(id)
    return CONFIG_DIRECTORY .. "\\" .. id .. ".ini"
end

local Persistence = {}

-- Returns a key->value table, or nil when no file exists yet or it cannot be read. The legacy
-- location is tried second, so settings saved before the move are picked up once and then rewritten
-- to the new path on the next Apply.
function Persistence.load(id)
    local file = io.open(configPath(id), "r")
    if not file then
        file = io.open(LEGACY_CONFIG_DIRECTORY .. "\\" .. id .. ".ini", "r")
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

function Persistence.save(id, values)
    local file, err = io.open(configPath(id), "w")
    if not file then
        print(MOD_TAG .. " Failed to save config for '" .. id .. "': " .. tostring(err))
        return false
    end
    -- Sorted for deterministic file contents.
    local keys = {}
    for key in pairs(values) do
        table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local ok, encoded = pcall(json.encode, values[key])
        if ok then
            file:write(key .. "=" .. encoded .. "\n")
        end
    end
    file:close()
    return true
end

return Persistence
