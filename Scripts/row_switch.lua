-- Boolean option row.
--
-- Built from WBP_OptionSettings_ListContent_C, the native row frame. The frame carries all four
-- content types as permanent children and its SetSwitcher shows this one while hiding the rest;
-- configuring the switch child directly leaves every other control visible. Using the frame also
-- gets native label, focus and hover behaviour without reimplementing it.
--
-- A click only STAGES the value. Nothing is committed, persisted or broadcast until Apply runs
-- Registry.apply, matching vanilla's cache-then-commit behaviour.
--
-- reaffirm() is also this mod's cross-mod "committed" signal: a consumer mod hooks the same
-- class-level Setup, reads the value straight off the hook argument, and resolves the owning
-- (modId, key) through AddressRegistry. See the wiki.
local AddressRegistry = require("address_registry")
local HookParam = require("hook_param")
local Registry = require("registry")
local RowLabel = require("row_label")
local Widgets = require("widgets")

local MOD_TAG = "[NativeModOptions]"
local FRAME_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContent"
local FRAME_PATH = FRAME_ASSET .. ".WBP_OptionSettings_ListContent_C"
local SWITCH_CLASS_PATH = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContentSwitch.WBP_OptionSettings_ListContentSwitch_C"

local RowSwitch = {}

local hookInstalled = false

-- Every entry point a value change can arrive through. SWITCH() alone is not enough: it is only the
-- gamepad/keyboard path, so hooking it left mouse clicks staging nothing -- corroborated by every
-- persisted config file, where only sliders and keybinds had ever moved off their defaults. A mouse
-- click arrives through the ON/OFF buttons' bound-event handlers instead.
--
-- Each stages the widget's OWN CurrentIsOn rather than a value inferred from which handler fired.
-- That matters because these handlers also fire when a row is configured or re-shown, not only on a
-- click: asserting "the OFF handler ran, so the value is false" turned one click into three changed
-- settings. Reading the real state makes a spurious fire stage what is already committed, which
-- Registry.stage treats as no change.
--
-- Registered with the single-callback form. For a Blueprint (/Game/) function that callback already
-- runs AFTER the original, so CurrentIsOn is the settled value; passing a second, genuinely-post
-- callback instead means it never fires at all.
local SWITCH_CHANGE_EVENTS = {
    "SWITCH",
    "BndEvt__WBP_OptionSettings_ListContentSwitch_WBP_PalCommonButton_OFF_K2Node_ComponentBoundEvent_2_CommonButtonBaseClicked__DelegateSignature",
    "BndEvt__WBP_OptionSettings_ListContentSwitch_WBP_PalCommonButton_OFF_K2Node_ComponentBoundEvent_7_CommonButtonBaseClicked__DelegateSignature",
    "BndEvt__WBP_OptionSettings_ListContentSwitch_WBP_PalCommonButton_OFF_K2Node_ComponentBoundEvent_8_CommonButtonBaseClicked__DelegateSignature",
    "BndEvt__WBP_OptionSettings_ListContentSwitch_WBP_PalCommonButton_ON_K2Node_ComponentBoundEvent_9_CommonButtonBaseClicked__DelegateSignature",
    "BndEvt__WBP_OptionSettings_ListContentSwitch_WBP_PalCommonButton_ON_K2Node_ComponentBoundEvent_10_CommonButtonBaseClicked__DelegateSignature",
    "BndEvt__WBP_OptionSettings_ListContentSwitch_WBP_PalCommonButton_ON_K2Node_ComponentBoundEvent_11_CommonButtonBaseClicked__DelegateSignature",
}

-- Hooked once at class level, so they fire for vanilla's rows too; AddressRegistry filters them down
-- to this mod's.
local function installSwitchHook()
    if hookInstalled then
        return
    end
    hookInstalled = true

    for _, event in ipairs(SWITCH_CHANGE_EVENTS) do
        local ok, err = pcall(function()
            RegisterHook(SWITCH_CLASS_PATH .. ":" .. event, function(Context)
                local instance = HookParam.read(Context)
                local owner = AddressRegistry.resolve(instance)
                if owner == nil then
                    return
                end
                local isOn = nil
                pcall(function() isOn = instance.CurrentIsOn end)
                if isOn == nil then
                    return
                end
                Registry.stage(owner.modId, owner.key, isOn and true or false)
            end)
        end)
        if not ok then
            print(MOD_TAG .. " Failed to hook ListContentSwitch change event: " .. tostring(err))
        end
    end
end

-- Returns the frame, which the caller lays out and later destroys, or nil on failure. The SWITCH
-- CHILD is what gets tracked -- that is what the interaction hook's Context resolves to.
function RowSwitch.create(outer, modId, key, label, value)
    installSwitchHook()
    local frame = Widgets.createUserWidget(outer, FRAME_PATH, FRAME_ASSET)
    if frame == nil then
        return nil
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentSwitch end)
    if child == nil or not child:IsValid() then
        pcall(function() frame:RemoveFromParent() end)
        return nil
    end
    pcall(function() frame:SetSwitcher(value and true or false) end)
    RowLabel.set(frame, label)
    AddressRegistry.track(child, modId, key)
    return frame
end

-- Called once per row after Registry.apply commits. See the file header: this is a signal, not only
-- a visual sync.
function RowSwitch.reaffirm(frame, value)
    if frame == nil or not frame:IsValid() then
        return
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentSwitch end)
    if child ~= nil and child:IsValid() then
        pcall(function() child:Setup(value and true or false, true) end)
    end
end

-- `bookkeepingOnly`: skip RemoveFromParent when the caller knows the whole tree is already being
-- torn down, where touching a mid-teardown widget risks a native crash.
function RowSwitch.destroy(frame, bookkeepingOnly)
    if frame == nil then
        return
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentSwitch end)
    if child ~= nil then
        AddressRegistry.untrack(child)
    end
    RowLabel.clear(frame)
    if not bookkeepingOnly then
        pcall(function() frame:RemoveFromParent() end)
    end
end

return RowSwitch
