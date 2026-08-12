-- Reads the player's real key bindings, so a mod keybind can be checked against the game's controls.
--
-- Read-only throughout. The bindings live on UPalOptionSubsystem as FPalKeyConfigSettings:
--   MouseAndKeyboardActionMappings  : TMap<FName, FPalKeyConfigKeys>  -- gameplay actions
--   MouseAndKeyboardUIInputMappings : TMap<FName, FKey>               -- UI actions
--
-- Comparison is by FKey.KeyName as a string. An FKey cannot be constructed from Lua, but an existing
-- one can be read, so conflict detection needs no construction. KeyConfigSettings is read as a
-- property rather than through its getter, because a USTRUCT returned by value does not survive
-- marshalling back into Lua.
local Dev = require("dev")

local MOD_TAG = "[NativeModOptions]"

local KeyConfig = {}

local function optionSubsystem()
    local subsystem = nil
    pcall(function() subsystem = FindFirstOf("PalOptionSubsystem") end)
    if subsystem ~= nil and subsystem:IsValid() then
        return subsystem
    end
    return nil
end

local function collectKeys(keys, out, actionName)
    for _, field in ipairs({ "MainKey", "SecondaryKey" }) do
        local name = nil
        pcall(function() name = keys[field].KeyName:ToString() end)
        if name ~= nil and name ~= "" and name ~= "None" then
            out[#out + 1] = { key = name, action = actionName }
        end
    end
end

-- Every (key, action) pair currently bound, plus whether the read succeeded. Callers must treat a
-- failed read as "unknown", never as "no conflicts".
function KeyConfig.allBindings()
    local subsystem = optionSubsystem()
    if subsystem == nil then
        return {}, false
    end

    local bindings, ok = {}, false
    pcall(function()
        local settings = subsystem.KeyConfigSettings

        settings.MouseAndKeyboardActionMappings:ForEach(function(actionName, keys)
            collectKeys(keys:get(), bindings, tostring(actionName:get():ToString()))
        end)
        ok = true

        settings.MouseAndKeyboardUIInputMappings:ForEach(function(actionName, key)
            local name = nil
            pcall(function() name = key:get().KeyName:ToString() end)
            if name ~= nil and name ~= "" and name ~= "None" then
                bindings[#bindings + 1] = { key = name, action = tostring(actionName:get():ToString()) }
            end
        end)
    end)
    return bindings, ok
end

-- Action names bound to `keyName`, plus whether the lookup could be performed. Reporting a key as
-- free when the bindings were unreadable would hand the player a silently broken shortcut.
function KeyConfig.actionsUsingKey(keyName)
    if type(keyName) ~= "string" or keyName == "" then
        return {}, false
    end
    local bindings, ok = KeyConfig.allBindings()
    if not ok then
        return {}, false
    end
    local conflicts = {}
    for _, binding in ipairs(bindings) do
        if binding.key == keyName then
            conflicts[#conflicts + 1] = binding.action
        end
    end
    return conflicts, true
end

-- The binding tables hold internal action names. The Controls page already displays a readable name
-- for each, so the mapping is read from there rather than rebuilt. Both keyboard maps are needed:
-- InputActionsMap_KM holds gameplay actions, UIActionsMap_KM the UI ones, and a conflict can land in
-- either. Each map is FName -> row, and each row's BP_PalTextBlock_Name holds the caption.
local KEY_ACTION_MAPS = { "InputActionsMap_KM", "UIActionsMap_KM" }

-- The two sides key the same action differently: the binding tables prefix UI actions, while the
-- Controls page keys the same rows bare. Gameplay actions carry no prefix and match as-is.
--   binding table    Legacy_DT_UIInputAction_OpenCHaracterMenu_Another
--   UIActionsMap_KM  OpenCHaracterMenu_Another  = "Inventory"
local LEGACY_UI_PREFIX = "Legacy_DT_UIInputAction_"

-- Built on demand -- only a row that reports a conflict needs it -- and dropped with the screen it
-- was read from (see forgetDisplayNames).
local displayNames = nil

local function buildDisplayNames(screen)
    local names, found = {}, false
    for _, field in ipairs(KEY_ACTION_MAPS) do
        local entries, captioned = 0, 0
        local ok = pcall(function()
            screen.KeySettings[field]:ForEach(function(actionName, listContent)
                entries = entries + 1
                local key = tostring(actionName:get():ToString())
                local row = listContent:get()
                local caption = nil
                pcall(function() caption = row.BP_PalTextBlock_Name:GetText():ToString() end)
                if caption ~= nil and caption ~= "" and caption ~= "None" then
                    names[key] = caption
                    captioned = captioned + 1
                    found = true
                end
            end)
        end)
        -- Reported only on failure: a map that reads but yields no captions means the Controls page
        -- changed shape, which on screen is indistinguishable from a key that has no conflict.
        if not ok or captioned == 0 then
            print(MOD_TAG .. " " .. field .. ": no readable action captions -- conflicts will show "
                .. "raw action ids")
            Dev.log(field .. ": readable=" .. tostring(ok) .. " entries=" .. entries
                .. " captioned=" .. captioned)
        end
    end
    return names, found
end

-- The player-facing name for `actionName`, or the raw name when none is known.
function KeyConfig.displayNameFor(screen, actionName)
    if screen == nil then
        return actionName
    end
    if displayNames == nil then
        -- Cached only once it resolved something: the Controls page may not have populated its maps
        -- yet, and caching an empty table would make the fallback permanent.
        local names, found = buildDisplayNames(screen)
        if not found then
            return actionName
        end
        displayNames = names
    end
    if displayNames[actionName] ~= nil then
        return displayNames[actionName]
    end
    if actionName:sub(1, #LEGACY_UI_PREFIX) == LEGACY_UI_PREFIX then
        local bare = actionName:sub(#LEGACY_UI_PREFIX + 1)
        if displayNames[bare] ~= nil then
            return displayNames[bare]
        end
    end
    return actionName
end

-- Called when the options screen closes: the captions belong to that screen's Controls page, and
-- holding them would survive a language change.
function KeyConfig.forgetDisplayNames()
    displayNames = nil
end

return KeyConfig
