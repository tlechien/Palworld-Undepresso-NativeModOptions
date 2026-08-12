-- Keeps a mod-supplied caption on a WBP_OptionSettings_ListContent_C row.
--
-- The frame resolves its own caption from SettingNameMsgId, an empty FDataTableRowHandle for a row
-- this mod builds, which resolves to "None". It does so in Construct, which fires when the row joins
-- the live widget tree -- after the builder has finished -- so the label must also be re-applied
-- from a class-level Construct hook, matched by frame address.
local AddressRegistry = require("address_registry")
local HookParam = require("hook_param")

local MOD_TAG = "[NativeModOptions]"
local FRAME_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContent"
local FRAME_PATH = FRAME_ASSET .. ".WBP_OptionSettings_ListContent_C"

local RowLabel = {}

local labels = {}   -- [frame address] = label
local hookInstalled = false

local function applyText(frame, label)
    -- FText() is required; a raw Lua string is rejected.
    pcall(function() frame.BP_PalTextBlock_Name:SetText(FText(label)) end)
end

local function installConstructHook()
    if hookInstalled then
        return
    end
    hookInstalled = true
    local ok, err = pcall(function()
        RegisterHook(FRAME_PATH .. ":Construct", function(Context)
            local frame = HookParam.read(Context)
            local label = labels[AddressRegistry.addressOf(frame)]
            if label ~= nil then
                applyText(frame, label)
            end
        end)
    end)
    if not ok then
        print(MOD_TAG .. " Failed to hook ListContent Construct: " .. tostring(err))
    end
end

-- Applies `label` now and re-applies it on every Construct of this frame.
function RowLabel.set(frame, label)
    if frame == nil or not frame:IsValid() or type(label) ~= "string" then
        return
    end
    installConstructHook()
    local address = AddressRegistry.addressOf(frame)
    if address ~= nil then
        labels[address] = label
    end
    applyText(frame, label)
end

-- Panels are rebuilt on every open; without this the table grows by one entry per row per open.
function RowLabel.clear(frame)
    local address = AddressRegistry.addressOf(frame)
    if address ~= nil then
        labels[address] = nil
    end
end

return RowLabel
