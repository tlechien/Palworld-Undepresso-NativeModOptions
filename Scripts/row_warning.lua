-- Display-only caution line, matching the amber note vanilla shows under the Language row.
--
-- Vanilla's own is CautionText, a designer-built Overlay on that page, so there is nothing to
-- instantiate and reuse; WBP_CommonWarning_C's only entry point takes a USTRUCT parameter, which
-- cannot be built from Lua. This assembles the same shape -- icon then wrapping text in a
-- HorizontalBox -- from the game's own text widget and the live icon's own texture.
--
-- Every step degrades rather than fails: without the icon the text still shows, and without the
-- copied colour it falls back to an approximate amber.
local Dev = require("dev")
local NativeStyle = require("native_style")
local Widgets = require("widgets")

local MOD_TAG = "[NativeModOptions]"
local TEXT_ASSET = "/Game/Pal/Blueprint/UI/PalTextBlock/BP_PalTextBlock"
local TEXT_PATH = TEXT_ASSET .. ".BP_PalTextBlock_C"
-- Used only when the live caution icon pins neither axis. Matches the game's own icon size.
local ICON_SIZE = 36
-- EVerticalAlignment::VAlign_Center. Fill (0) is the slot default.
local VALIGN_CENTER = 2
-- ESlateSizeRule::Fill.
local SIZE_RULE_FILL = 1
-- ColorUseRule 0 is FSlateColor's UseColor_Specified. Approximate, and used only if copying the live
-- colour fails, so the line still reads as a warning rather than as ordinary text.
local FALLBACK_CAUTION_COLOR = {
    SpecifiedColor = { R = 1.0, G = 0.78, B = 0.20, A = 1.0 },
    ColorUseRule = 0,
}

local RowWarning = {}

-- Returns the icon's texture and square size, or nil when the live reference cannot be read.
--
-- The size comes from the reference rather than a constant, and whichever axis it pins is applied to
-- both: reading one override while leaving the other at its default renders a stretched triangle.
local function readIconStyle(screen)
    local referenceBox = NativeStyle.cautionIconReference(screen)
    if referenceBox == nil then
        return nil
    end
    local referenceIcon = nil
    pcall(function() referenceIcon = referenceBox:GetContent() end)
    if referenceIcon == nil or not referenceIcon:IsValid() then
        return nil
    end
    local texture = nil
    pcall(function() texture = referenceIcon.Brush.ResourceObject end)
    if texture == nil or not texture:IsValid() then
        return nil
    end
    local size = ICON_SIZE
    pcall(function()
        local width = referenceBox.bOverride_WidthOverride and referenceBox.WidthOverride or nil
        local height = referenceBox.bOverride_HeightOverride and referenceBox.HeightOverride or nil
        size = width or height or ICON_SIZE
    end)
    return { texture = texture, size = size, icon = referenceIcon }
end

-- Returns the assembled row, or the bare text widget when the icon could not be built. Raw UMG, like
-- the section header -- see panelState.rawWidgets.
function RowWarning.create(outer, label, stylePath, screen)
    if StaticFindObject(TEXT_PATH) == nil then
        pcall(function() LoadAsset(TEXT_ASSET) end)
    end
    local text = Widgets.construct(TEXT_PATH, outer)
    if text == nil then
        print(MOD_TAG .. " warning row: could not construct BP_PalTextBlock_C")
        return nil
    end
    pcall(function() text:SetText(FText(label)) end)
    -- A caveat worth a warning is usually longer than one line. A literal newline also breaks.
    pcall(function() text:SetAutoWrapText(true) end)
    if stylePath ~= nil then
        NativeStyle.applyStyle(text, stylePath, "warning row")
    end

    -- Font and colour both come from the live caution line. The size lives in the instance's
    -- FSlateFontInfo, not in a style class, so it has to be copied rather than named.
    local reference = NativeStyle.cautionReference(screen)
    NativeStyle.copyFont(text, reference, "warning row")
    if not NativeStyle.copyColor(text, reference, "warning row") then
        local tinted = pcall(function() text:SetColorAndOpacity(FALLBACK_CAUTION_COLOR) end)
        print(MOD_TAG .. " warning row: could not copy the live caution colour, "
            .. "using the fallback amber")
        Dev.log("warning row: reference=" .. tostring(reference ~= nil)
            .. " fallbackApplied=" .. tostring(tinted))
    end

    local iconStyle = readIconStyle(screen)
    if iconStyle == nil then
        print(MOD_TAG .. " warning row: no caution icon texture, showing text only")
        return text
    end

    local row = Widgets.construct("/Script/UMG.HorizontalBox", outer)
    local iconImage = Widgets.construct("/Script/UMG.Image", outer)
    local iconBox = Widgets.construct("/Script/UMG.SizeBox", outer)
    if row == nil or iconImage == nil or iconBox == nil then
        print(MOD_TAG .. " warning row: could not build the icon row, showing text only")
        return text
    end
    local built = pcall(function()
        -- bMatchSize=true: with false, a freshly built image keeps ImageSize at 0x0 and Slate draws
        -- nothing.
        iconImage:SetBrushFromTexture(iconStyle.texture, true)
        iconBox:SetWidthOverride(iconStyle.size)
        iconBox:SetHeightOverride(iconStyle.size)
        iconBox:SetContent(iconImage)
        local iconSlot = row:AddChildToHorizontalBox(iconBox)
        -- Centred against the whole block: Fill stretches the icon down the full height, and Top
        -- leaves it in a corner once the note wraps.
        if iconSlot ~= nil and iconSlot:IsValid() then
            iconSlot:SetVerticalAlignment(VALIGN_CENTER)
        end
        row:AddChildToHorizontalBox(text)
    end)
    pcall(function() iconImage:SetColorAndOpacity(iconStyle.icon.ColorAndOpacity) end)
    -- Fill, so the text has a bounded width to wrap against. Isolated: SetSize takes an
    -- FSlateChildSize, and a struct passed from Lua must not be able to take the row down with it.
    pcall(function()
        local textSlot = text.Slot
        if textSlot ~= nil and textSlot:IsValid() then
            textSlot:SetSize({ SizeRule = SIZE_RULE_FILL })
        end
    end)
    if not built then
        print(MOD_TAG .. " warning row: icon row assembly failed, showing text only")
        return text
    end
    return row
end

-- `bookkeepingOnly`: skip RemoveFromParent when the whole tree is already being torn down.
function RowWarning.destroy(widget, bookkeepingOnly)
    if widget == nil or bookkeepingOnly then
        return
    end
    pcall(function() widget:RemoveFromParent() end)
end

return RowWarning
