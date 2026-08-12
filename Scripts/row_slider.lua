-- Numeric option row. See row_switch.lua for the shared frame-based construction, the staging model
-- and the commit signal; only the class and function names differ here.
local AddressRegistry = require("address_registry")
local HookParam = require("hook_param")
local Registry = require("registry")
local RowLabel = require("row_label")
local Widgets = require("widgets")

local MOD_TAG = "[NativeModOptions]"
local FRAME_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContent"
local FRAME_PATH = FRAME_ASSET .. ".WBP_OptionSettings_ListContent_C"
local SLIDER_CLASS_PATH = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContentSlider.WBP_OptionSettings_ListContentSlider_C"
local VALUE_CHANGED_EVENT =
    "BndEvt__WBP_OptionSettings_ListContentSlider_Slider_K2Node_ComponentBoundEvent_0_OnFloatValueChangedEvent__DelegateSignature"

local RowSlider = {}

local hookInstalled = false

-- Fires on every value change during a drag, not only on release. That is fine: staging is cheap and
-- nothing is persisted or broadcast until Apply.
local function installValueChangedHook()
    if hookInstalled then
        return
    end
    hookInstalled = true
    local ok, err = pcall(function()
        RegisterHook(SLIDER_CLASS_PATH .. ":" .. VALUE_CHANGED_EVENT, function(Context, Value)
            local instance = HookParam.read(Context)
            local owner = AddressRegistry.resolve(instance)
            if owner == nil then
                return
            end
            local numeric = tonumber(HookParam.read(Value))
            if numeric ~= nil then
                Registry.stage(owner.modId, owner.key, numeric)
            end
        end)
    end)
    if not ok then
        print(MOD_TAG .. " Failed to hook ListContentSlider's value-changed event: " .. tostring(err))
    end
end

function RowSlider.create(outer, modId, key, label, value, min, max)
    installValueChangedHook()
    local frame = Widgets.createUserWidget(outer, FRAME_PATH, FRAME_ASSET)
    if frame == nil then
        return nil
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentSlider end)
    if child == nil or not child:IsValid() then
        pcall(function() frame:RemoveFromParent() end)
        return nil
    end
    -- SetSlider(CurrentValue, Min, Max, FixedChangeValue, UseFixedValue). The last two drive stepped
    -- movement, which vanilla uses for discrete sliders; these are continuous.
    pcall(function() frame:SetSlider(value, min, max, 0.0, false) end)
    RowLabel.set(frame, label)
    AddressRegistry.track(child, modId, key)
    return frame
end

function RowSlider.reaffirm(frame, value, min, max)
    if frame == nil or not frame:IsValid() then
        return
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentSlider end)
    if child ~= nil and child:IsValid() then
        pcall(function() child:SetValue(value, min, max) end)
    end
end

-- See row_switch.destroy for what bookkeepingOnly means.
function RowSlider.destroy(frame, bookkeepingOnly)
    if frame == nil then
        return
    end
    local child = nil
    pcall(function() child = frame.WBP_OptionSettings_ListContentSlider end)
    if child ~= nil then
        AddressRegistry.untrack(child)
    end
    RowLabel.clear(frame)
    if not bookkeepingOnly then
        pcall(function() frame:RemoveFromParent() end)
    end
end

return RowSlider
