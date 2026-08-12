-- Borrows text appearance from the game's own widgets.
--
-- Vanilla's headings and its caution line carry no CommonTextStyle: both read back style=none, and
-- their size and weight come from each instance's Font. An FSlateFontInfo cannot be constructed from
-- Lua, but one can be read off a live widget and handed straight back to SetFont, which is what
-- these references are for.
--
-- Every reference below is a widget on the options screen this mod is already attached to, so there
-- is nothing to load. All are READ-ONLY: they belong to the real screen, and writing through one
-- would change what the game itself displays.
--
-- Access is deliberately shallow -- named properties and one level of children on containers a live
-- read has confirmed. A recursive walk of these pages crashes the game natively, uncatchably.
local MOD_TAG = "[NativeModOptions]"

local NativeStyle = {}

-- The reference containers hold a handful of children; this guards against an unexpected tree only.
local MAX_CHILDREN = 8

local function firstTextChild(panel)
    local count = nil
    pcall(function() count = panel:GetChildrenCount() end)
    if count == nil then
        return nil
    end
    for index = 0, math.min(count, MAX_CHILDREN) - 1 do
        local child = nil
        pcall(function() child = panel:GetChildAt(index) end)
        if child ~= nil and child:IsValid() then
            local class = nil
            pcall(function() class = child:GetClass():GetFName():ToString() end)
            if class == "BP_PalTextBlock_C" then
                return child
            end
        end
    end
    return nil
end

-- A live section header from the Controls page. `screen` is the WBP_OptionSettings_C instance.
function NativeStyle.headingReference(screen)
    if screen == nil then
        return nil
    end
    local box = nil
    pcall(function() box = screen.KeySettings.VerticalBox_KM end)
    if box == nil or not box:IsValid() then
        return nil
    end
    return firstTextChild(box)
end

-- The amber caution line from the Graphics page.
function NativeStyle.cautionReference(screen)
    if screen == nil then
        return nil
    end
    local caution = nil
    pcall(function() caution = screen.GraphicSettings.CautionText end)
    if caution == nil or not caution:IsValid() then
        return nil
    end
    return firstTextChild(caution)
end

-- The caution block's icon wrapper. CautionText is an Overlay holding a SizeBox and the text; the
-- SizeBox is the warning triangle. The BOX is returned rather than the image so its explicit size
-- overrides can be read too -- the icon has to match the text, and a hardcoded size does not.
function NativeStyle.cautionIconReference(screen)
    if screen == nil then
        return nil
    end
    local caution = nil
    pcall(function() caution = screen.GraphicSettings.CautionText end)
    if caution == nil or not caution:IsValid() then
        return nil
    end
    local count = nil
    pcall(function() count = caution:GetChildrenCount() end)
    for index = 0, math.min(count or 0, MAX_CHILDREN) - 1 do
        local child = nil
        pcall(function() child = caution:GetChildAt(index) end)
        if child ~= nil and child:IsValid() then
            local class = nil
            pcall(function() class = child:GetClass():GetFName():ToString() end)
            if class == "SizeBox" then
                return child
            end
        end
    end
    return nil
end

-- Vanilla's own key image, from the first row in the Controls page's action map. Its Brush is a live
-- FSlateBrush -- the only way to obtain one, since the struct cannot be built from Lua and the row
-- button's SetIcon takes exactly that type.
function NativeStyle.keyImageReference(screen)
    if screen == nil then
        return nil
    end
    local row = nil
    pcall(function()
        screen.KeySettings.InputActionsMap_KM:ForEach(function(_, listContent)
            if row ~= nil then
                return
            end
            row = listContent:get()
        end)
    end)
    if row == nil or not row:IsValid() then
        return nil
    end
    local image = nil
    pcall(function() image = row.WBP_OptionSettings_ListContentButton.Image_Key end)
    if image ~= nil and image:IsValid() then
        return image
    end
    return nil
end

-- Applies one of the game's CommonTextStyle classes, named by a schema's `style` field. SetStyle
-- takes a class, which marshals cleanly, unlike SetFont's FSlateFontInfo.
--
-- Not applied by default: vanilla's own headers and caution lines read back style=none, and their
-- appearance is copied from a live widget instead. `stylePath` is a full object path; the
-- package-path form does not load.
function NativeStyle.applyStyle(target, stylePath, what)
    local styleClass = StaticFindObject(stylePath)
    if styleClass == nil or not styleClass:IsValid() then
        pcall(function() LoadAsset(stylePath) end)
        styleClass = StaticFindObject(stylePath)
    end
    -- Reported rather than silent: a missing class and a rejected one look identical on screen.
    if styleClass == nil or not styleClass:IsValid() then
        print(MOD_TAG .. " " .. what .. ": style class not found '" .. stylePath
            .. "' -- text keeps its default styling")
        return false
    end
    local applied = pcall(function() target:SetStyle(styleClass) end)
    if not applied then
        print(MOD_TAG .. " " .. what .. ": SetStyle rejected '" .. stylePath .. "'")
    end
    return applied
end

-- Copies `reference`'s font onto `target`. The two failure cases are reported separately: both leave
-- default-sized text on screen, which looks like a styling choice rather than a failure.
function NativeStyle.copyFont(target, reference, what)
    if target == nil then
        return false
    end
    if reference == nil then
        print(MOD_TAG .. " " .. what .. ": no live reference widget, text keeps its default size")
        return false
    end
    local copied = pcall(function() target:SetFont(reference.Font) end)
    if not copied then
        print(MOD_TAG .. " " .. what .. ": SetFont rejected the reference font")
    end
    return copied
end

-- Copies `reference`'s colour onto `target`. A missing reference is the caller's to report, since it
-- applies its own fallback colour.
function NativeStyle.copyColor(target, reference, what)
    if target == nil or reference == nil then
        return false
    end
    local copied = pcall(function() target:SetColorAndOpacity(reference.ColorAndOpacity) end)
    if not copied then
        print(MOD_TAG .. " " .. what .. ": could not copy the reference colour")
    end
    return copied
end

return NativeStyle
