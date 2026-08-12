-- Display-only image entry.
--
-- The options UI has no reusable image row, so this builds raw UMG the way vanilla's own pages place
-- plain images among their rows. Raw UWidgets, not UserWidgets -- see panelState.rawWidgets for how
-- the caller attaches them.
--
-- SetBrushFromTexture and SizeBox are preferred over SetBrush and SetDesiredSizeOverride because
-- they take an object pointer and two numbers; the alternatives need FSlateBrush and FVector2D,
-- which cannot be constructed from Lua.
local Widgets = require("widgets")

local MOD_TAG = "[NativeModOptions]"
local DEFAULT_WIDTH = 320
local DEFAULT_HEIGHT = 180

local RowImage = {}

-- `outer` must be a live widget. `texturePath` is a full object path -- the asset name repeated
-- after a dot, e.g. "/Game/Pal/Texture/UI/CharaCre/Icon_Equip.Icon_Equip"; the package-path form
-- does not resolve. Returns the SizeBox wrapper, the bare image if the wrapper fails, or nil.
function RowImage.create(outer, texturePath, width, height)
    local image = Widgets.construct("/Script/UMG.Image", outer)
    if image == nil then
        return nil
    end

    local texture = StaticFindObject(texturePath)
    if texture == nil or not texture:IsValid() then
        pcall(function() LoadAsset(texturePath) end)
        texture = StaticFindObject(texturePath)
    end
    if texture == nil or not texture:IsValid() then
        print(MOD_TAG .. " image row: texture not found '" .. tostring(texturePath)
            .. "' -- expected \"/Game/...\" with the asset name repeated after a dot")
        return nil
    end

    -- bMatchSize=false: the SizeBox decides the footprint, not the source texture.
    pcall(function() image:SetBrushFromTexture(texture, false) end)

    local box = Widgets.construct("/Script/UMG.SizeBox", outer)
    if box == nil then
        return image
    end
    local ok = pcall(function()
        box:SetWidthOverride(width or DEFAULT_WIDTH)
        box:SetHeightOverride(height or DEFAULT_HEIGHT)
        box:SetContent(image)
    end)
    return ok and box or image
end

-- `bookkeepingOnly`: skip RemoveFromParent when the whole tree is already being torn down.
function RowImage.destroy(widget, bookkeepingOnly)
    if widget == nil or bookkeepingOnly then
        return
    end
    pcall(function() widget:RemoveFromParent() end)
end

return RowImage
