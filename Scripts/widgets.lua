-- widgets.lua -- the two UMG construction calls this mod needs, and nothing else.
--
-- Which one to use is decided by the class, not by preference: StaticConstructObject for a raw
-- UWidget, WidgetBlueprintLibrary:Create for a UserWidget-derived Blueprint (it also runs the
-- widget's own Construct/PreConstruct graph, which buttons and rows depend on for their visual
-- state). Create() rejects a non-UserWidget class outright, so the two are not interchangeable.
local Widgets = {}

-- Constructs a raw (non-UserWidget) UMG object, e.g. "/Script/UMG.CanvasPanel" or
-- "/Script/UMG.VerticalBox", under `outer` (typically a WidgetTree).
function Widgets.construct(classPath, outer)
    local class = StaticFindObject(classPath)
    if not class or not class:IsValid() or outer == nil or not outer:IsValid() then
        return nil
    end
    local ok, widget = pcall(function()
        return StaticConstructObject(class, outer, 0, 0, 0, nil, false, false, nil)
    end)
    return ok and widget and widget:IsValid() and widget or nil
end

-- Constructs a UserWidget-derived widget (a Blueprint asset, e.g. a menu button class) via
-- WidgetBlueprintLibrary:Create, which, unlike raw StaticConstructObject, also runs the
-- widget's own Construct()/PreConstruct() Blueprint logic, needed for anything with visual state
-- set up in its own graph (buttons, rows). `worldContext` is typically the parent menu/panel
-- widget instance itself.
function Widgets.createUserWidget(worldContext, classPath, assetPath)
    local library = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local class = StaticFindObject(classPath)
    if (not class or not class:IsValid()) and assetPath ~= nil then
        pcall(function() LoadAsset(assetPath) end)
        class = StaticFindObject(classPath)
    end
    if not library or not library:IsValid() then
        print("[NativeModOptions] createUserWidget(" .. classPath .. "): WidgetBlueprintLibrary invalid")
        return nil
    end
    if not class or not class:IsValid() then
        print("[NativeModOptions] createUserWidget(" .. classPath .. "): class not found/invalid")
        return nil
    end
    if worldContext == nil or not worldContext:IsValid() then
        print("[NativeModOptions] createUserWidget(" .. classPath .. "): worldContext invalid")
        return nil
    end
    local owner = nil
    local ownerOk, ownerErr = pcall(function() owner = worldContext:GetOwningPlayer() end)
    if not ownerOk then
        print("[NativeModOptions] createUserWidget(" .. classPath .. "): GetOwningPlayer failed (non-fatal): " .. tostring(ownerErr))
    end
    local ok, widget = pcall(function()
        return library:Create(worldContext, class, owner)
    end)
    if not ok then
        print("[NativeModOptions] createUserWidget(" .. classPath .. "): library:Create threw: " .. tostring(widget))
        return nil
    end
    if not widget or not widget:IsValid() then
        print("[NativeModOptions] createUserWidget(" .. classPath .. "): library:Create returned invalid widget")
        return nil
    end
    return widget
end

return Widgets
