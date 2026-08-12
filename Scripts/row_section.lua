-- Display-only section header.
--
-- Uses BP_PalTextBlock_C, the same widget vanilla's settings pages use to head their groups. It
-- derives from UTextBlock, so it is a raw UWidget rather than a UserWidget -- built with
-- StaticConstructObject and attached as a raw widget (see panelState.rawWidgets).
--
-- Carries no value: never staged, applied, persisted or broadcast, and absent from panelState.rows.
local Widgets = require("widgets")
local NativeStyle = require("native_style")

local MOD_TAG = "[NativeModOptions]"
local TEXT_ASSET = "/Game/Pal/Blueprint/UI/PalTextBlock/BP_PalTextBlock"
local TEXT_PATH = TEXT_ASSET .. ".BP_PalTextBlock_C"

local RowSection = {}

-- Returns the header widget, or nil on failure.
function RowSection.create(outer, label, stylePath, screen)
    if StaticFindObject(TEXT_PATH) == nil then
        pcall(function() LoadAsset(TEXT_ASSET) end)
    end
    local text = Widgets.construct(TEXT_PATH, outer)
    if text == nil then
        print(MOD_TAG .. " section header: could not construct BP_PalTextBlock_C")
        return nil
    end
    -- FText() is required; a raw Lua string is rejected.
    pcall(function() text:SetText(FText(label)) end)
    if stylePath ~= nil then
        NativeStyle.applyStyle(text, stylePath, "section header")
    else
        NativeStyle.copyFont(text, NativeStyle.headingReference(screen), "section header")
    end
    return text
end

-- `bookkeepingOnly`: skip RemoveFromParent when the whole tree is already being torn down.
function RowSection.destroy(widget, bookkeepingOnly)
    if widget == nil or bookkeepingOnly then
        return
    end
    pcall(function() widget:RemoveFromParent() end)
end

return RowSection
