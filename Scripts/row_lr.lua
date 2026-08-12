-- Enum option row. See row_switch.lua for the shared frame-based construction, the staging model and
-- the commit signal.
--
-- The native selector works in strings and a 0-based index; this wrapper maps that to and from the
-- schema's { value, label } choice list, so consumer mods deal in stable value strings rather than
-- positions. See the wiki.
local AddressRegistry = require("address_registry")
local HookParam = require("hook_param")
local Registry = require("registry")
local RowLabel = require("row_label")
local Widgets = require("widgets")

local MOD_TAG = "[NativeModOptions]"
local FRAME_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContent"
local FRAME_PATH = FRAME_ASSET .. ".WBP_OptionSettings_ListContent_C"
local SELECTOR_CLASS_PATH = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContentLR.WBP_OptionSettings_ListContentLR_C"

local RowLR = {}

local moveHookInstalled = false
local constructHookInstalled = false

local function indexOfValue(choices, value)
    for index, choice in ipairs(choices) do
        if choice.value == value then
            return index - 1   -- the native index is 0-based
        end
    end
    return 0
end

-- How many strings the selector holds. Both readings are attempted because a UE4SS TArray does not
-- reliably answer to `#`.
local function selectionCount(child)
    local count = nil
    pcall(function() count = #child.Selections end)
    if count == nil then
        pcall(function() count = child.Selections:GetArrayNum() end)
    end
    return tonumber(count) or 0
end

-- Fills the selector's string list, verifying by reading it back so a silent no-op cannot pass for
-- success. Passing a Lua table as TArray<FString> is the uncertain step -- it can reach the widget
-- and still arrive empty, leaving the row reading "None". Returns the path that worked, or nil.
--
-- None of these paints the active bar; see selectIndex.
local function populateSelections(frame, child, labels, index)
    pcall(function() frame:SetSelecter_String(labels, index) end)
    if selectionCount(child) > 0 then
        return "SetSelecter_String"
    end

    pcall(function() child:SetupSelections(labels, index) end)
    if selectionCount(child) > 0 then
        return "SetupSelections"
    end

    pcall(function() child.Selections = labels end)
    if selectionCount(child) > 0 then
        return "Selections property"
    end

    return nil
end

-- Highlights the chosen bar and records the index, which the Construct hook restores.
--
-- Populating sets the string list and Current but leaves every bar neutral; SelectByIndex is what
-- recolours them, which is why an untouched row showed no highlight until the player moved it.
local function selectIndex(child, index)
    local owner = AddressRegistry.resolve(child)
    if owner ~= nil then
        owner.index = index
    end
    pcall(function() child:SelectByIndex(index) end)
end

-- Every entry point a selection change can arrive through. An arrow CLICK reaches neither MoveLeft/
-- MoveRight nor SelectByIndex -- both were hooked here and never fired -- it goes through the arrow
-- buttons' own bound events, the same way the switch row's clicks do.
--
-- Each reads the widget's settled Current rather than trusting an argument or the direction, so a
-- handler that fires without a real change stages the committed value and Registry.stage ignores it.
-- Single-callback form: for a Blueprint (/Game/) function it already runs after the original.
local SELECTION_CHANGE_EVENTS = {
    "BndEvt__WBP_OptionSettings_ListContentLR_WBP_OptionSettings_ListContentLArrow_K2Node_ComponentBoundEvent_0_OnClicked__DelegateSignature",
    "BndEvt__WBP_OptionSettings_ListContentLR_WBP_OptionSettings_ListContentRArrow_K2Node_ComponentBoundEvent_1_OnClicked__DelegateSignature",
    "MoveLeft",
    "MoveRight",
    "SelectByIndex",
}

local function installMoveHooks()
    if moveHookInstalled then
        return
    end
    moveHookInstalled = true
    for _, event in ipairs(SELECTION_CHANGE_EVENTS) do
        local ok, err = pcall(function()
            RegisterHook(SELECTOR_CLASS_PATH .. ":" .. event, function(Context)
                local instance = HookParam.read(Context)
                local owner = AddressRegistry.resolve(instance)
                if owner == nil or owner.choices == nil then
                    return
                end
                local index = nil
                pcall(function() index = instance.Current end)
                index = tonumber(index)
                if index == nil then
                    return
                end
                owner.index = index
                local choice = owner.choices[index + 1]   -- back to 1-based Lua indexing
                if choice ~= nil then
                    Registry.stage(owner.modId, owner.key, choice.value)
                end
            end)
        end)
        if not ok then
            print(MOD_TAG .. " Failed to hook ListContentLR:" .. event .. ": " .. tostring(err))
        end
    end
end

-- The frame re-runs its own setup in Construct, after this builder has finished, which drops the
-- highlight. Re-applied here, as the caption and key glyph are in their own modules. The hook is
-- class-level, so non-enum rows fall out on the child lookup.
local function installConstructHook()
    if constructHookInstalled then
        return
    end
    constructHookInstalled = true
    local ok, err = pcall(function()
        RegisterHook(FRAME_PATH .. ":Construct", function(Context)
            local frame = HookParam.read(Context)
            local child = nil
            pcall(function() child = frame.WBP_OptionSettings_ListContentLR end)
            if child == nil or not child:IsValid() then
                return
            end
            local owner = AddressRegistry.resolve(child)
            if owner == nil or owner.index == nil then
                return
            end
            pcall(function() child:SelectByIndex(owner.index) end)
        end)
    end)
    if not ok then
        print(MOD_TAG .. " Failed to hook ListContent Construct for enum rows: " .. tostring(err))
    end
end

-- `choices` is the schema option's array of { value, label }, in display order.
function RowLR.create(outer, modId, key, label, value, choices)
    installMoveHooks()
    installConstructHook()
    local frame = Widgets.createUserWidget(outer, FRAME_PATH, FRAME_ASSET)
    if frame == nil then
        return nil
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentLR end)
    if child == nil or not child:IsValid() then
        pcall(function() frame:RemoveFromParent() end)
        return nil
    end
    -- SetSelecter_String, not SetSelecter: the latter takes FDataTableRowHandles, which can only name
    -- vanilla's own localised entries and cannot express a mod's arbitrary labels.
    local labels = {}
    for _, choice in ipairs(choices) do
        table.insert(labels, choice.label)
    end
    local index = indexOfValue(choices, value)
    local populatedVia = populateSelections(frame, child, labels, index)
    if populatedVia == nil then
        print(MOD_TAG .. " enum row '" .. key .. "': could not populate the native selector -- "
            .. "the choice list did not survive as a TArray<FString>, row will read 'None'")
    end
    RowLabel.set(frame, label)
    -- Tracked before selecting: selectIndex records the index on the owner entry.
    AddressRegistry.track(child, modId, key, { choices = choices })
    selectIndex(child, index)
    return frame
end

function RowLR.reaffirm(frame, value, choices)
    if frame == nil or not frame:IsValid() then
        return
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentLR end)
    if child ~= nil and child:IsValid() then
        selectIndex(child, indexOfValue(choices, value))
    end
end

-- See row_switch.destroy for what bookkeepingOnly means.
function RowLR.destroy(frame, bookkeepingOnly)
    if frame == nil then
        return
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentLR end)
    if child ~= nil then
        AddressRegistry.untrack(child)
    end
    RowLabel.clear(frame)
    if not bookkeepingOnly then
        pcall(function() frame:RemoveFromParent() end)
    end
end

return RowLR
