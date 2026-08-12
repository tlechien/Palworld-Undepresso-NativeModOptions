-- Key rebinding row, built on the game's own key-config row.
--
-- WBP_OptionSettings_ListContent_C already carries what the Controls tab uses for rebinding:
-- SetConfigButton shows the key-config control, and the row's Button child reports the click.
--
-- Vanilla's key rows are bound to real entries in the game's input-action registry and write back
-- through PalKeyConfig. A mod's key is not a game input action, so the value cannot round-trip that
-- way; the row is driven directly instead -- a click enters capture mode, and the next key press
-- becomes the new value.
--
-- Capture uses RegisterKeyBind, the only key-press signal UE4SS exposes. Binds are global and cannot
-- be removed once registered, so they are installed lazily -- only when a schema declares a keybind
-- option -- and the callback does nothing unless a row is currently capturing.
local AddressRegistry = require("address_registry")
local Dev = require("dev")
local HookParam = require("hook_param")
local KeyConfig = require("key_config")
local NativeStyle = require("native_style")
local Registry = require("registry")
local RowLabel = require("row_label")
local Widgets = require("widgets")

local MOD_TAG = "[NativeModOptions]"
local FRAME_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_ListContent"
local FRAME_PATH = FRAME_ASSET .. ".WBP_OptionSettings_ListContent_C"
local TEXT_ASSET = "/Game/Pal/Blueprint/UI/PalTextBlock/BP_PalTextBlock"
local TEXT_PATH = TEXT_ASSET .. ".BP_PalTextBlock_C"
-- The row delegates its click to this child. OnKeyConfigClicked looks like the obvious signal but is
-- a delegate property, not a callable UFunction, so it cannot be hooked.
local BUTTON_BASE_CLASS = "/Game/Pal/Blueprint/UI/System/Style/WBP_PalCommonButtonBase.WBP_PalCommonButtonBase_C"
-- ECommonInputType::MouseAndKeyboard and EPalKeyConfigAxisFilterType's default: byte enums whose
-- zero member is what a keyboard row wants.
local INPUT_TYPE_KEYBOARD = 0
local AXIS_FILTER_NONE = 0
-- ESlateVisibility. SelfHitTestInvisible is what vanilla's rows carry; Collapsed removes the widget
-- from layout, which is how the unused content children are hidden.
local VIS_VISIBLE = 4
local VIS_COLLAPSED = 1

-- Keys offered for capture. Not the whole keyboard: each entry becomes a permanent global bind, and
-- modifier and system keys are not usable as mod shortcuts.
local CAPTURE_KEYS = {
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
}

-- Each key is registered bare and with each modifier, because a modifier cannot be observed on its
-- own: UE4SS's Key table has no Control/Alt entries, they exist only as ModifierKey values, so which
-- callback fires is the only signal of what was held. A bare bind does not fire on a chord, so no
-- most-specific-match tie-breaking is needed, and binds do not consume the press.
local CAPTURE_VARIANTS = {
    { name = nil,    modifiers = nil },
    { name = "Ctrl", modifiers = { "CONTROL" } },
    { name = "Alt",  modifiers = { "ALT" } },
}
-- Separator in a stored binding, e.g. "Ctrl+I". A bare binding is just the key name.
local MODIFIER_SEPARATOR = "+"
local MODIFIER_SUFFIX = " +"
-- Used only when the modifier label could not be built: the modifier trails the caption instead.
local MODIFIER_GAP = "   "
-- EHorizontalAlignment / EVerticalAlignment. Fill is the slot default; Right pins to the right edge.
local HALIGN_FILL = 0
local HALIGN_RIGHT = 3
local VALIGN_FILL = 0
local VALIGN_CENTER = 2
-- ETextJustify::Left.
local JUSTIFY_LEFT = 0
-- Where the modifier text starts, measured from the row's right edge. The key button occupies the
-- rightmost ~240px, so this clears it. Left justification within a block of this minimum width fixes
-- the START rather than the end, so a longer modifier grows leftwards instead of under the glyph.
local MODIFIER_RIGHT_INSET = 310
-- How many conflicting actions to name before summarising the rest as "+N". One: the caption shares
-- the row with the key glyph, and naming two runs the text underneath it.
local CONFLICTS_NAMED = 1
-- Cap on the named part, so a long action name cannot overflow the row.
local CONFLICT_NAME_MAX = 40
-- Key glyph textures, read off a live Controls row rather than guessed. /Game/Others/KeyboardIcons is
-- a similar-looking but unrelated family whose textures load and render nothing.
local KEY_ICON_FOLDER = "/Game/Pal/Texture/UI/KeyGuide/keyboard/"
local KEY_ICON_PREFIX = "T_KeyGuide_Keyboard_"
-- Vanilla's Image_Key brush reads back 36x36 regardless of the texture's own resolution.
local KEY_ICON_SIZE = 36

local RowKeybind = {}

local clickHookInstalled = false
local captureInstalled = false
local constructHookInstalled = false
-- The row waiting for a key press, or nil. Only one row captures at a time, matching the interaction.
local capturing = nil
local rows = {}          -- [frame address] = entry
local buttonOwners = {}  -- [row's Button child address] = entry

-- Splits a stored binding into its base key and modifier list.
local function parseBinding(value)
    if type(value) ~= "string" or value == "" then
        return value, {}
    end
    local modifiers = {}
    local remainder = value
    while true do
        local separator = remainder:find(MODIFIER_SEPARATOR, 1, true)
        if separator == nil then
            break
        end
        modifiers[#modifiers + 1] = remainder:sub(1, separator - 1)
        remainder = remainder:sub(separator + 1)
    end
    return remainder, modifiers
end

local function formatBinding(baseKey, modifierName)
    if modifierName == nil then
        return baseKey
    end
    return modifierName .. MODIFIER_SEPARATOR .. baseKey
end

-- Canonical form of a shortcut, for comparing two of them. The same chord arrives two ways -- captured
-- as "Ctrl+I", or a stored "I" against a schema's modifiers = { "Ctrl" } -- and both must compare
-- equal. Modifiers are upper-cased and sorted so order and case cannot split one chord into two.
local function normalizedChord(value, declaredModifiers)
    local baseKey, capturedModifiers = parseBinding(value)
    local modifiers = #capturedModifiers > 0 and capturedModifiers or (declaredModifiers or {})
    local names = {}
    for index, modifier in ipairs(modifiers) do
        names[index] = modifier:upper()
    end
    table.sort(names)
    return table.concat(names, MODIFIER_SEPARATOR) .. "|" .. tostring(baseKey):upper()
end

-- Wraps the row in an Overlay this mod owns, with a text widget pinned a fixed distance from the
-- row's right edge, and returns both. The modifier cannot go in the caption -- positioning it there
-- needs the caption's rendered width, which is not obtainable -- nor inside the row, whose canvas
-- refuses runtime children. Slots from containers built here behave normally.
local function wrapWithModifierLabel(outer, frame)
    local overlay = Widgets.construct("/Script/UMG.Overlay", outer)
    local label = Widgets.construct(TEXT_PATH, outer)
    if overlay == nil or label == nil then
        return nil, nil
    end
    local built = pcall(function()
        local rowSlot = overlay:AddChildToOverlay(frame)
        rowSlot:SetHorizontalAlignment(HALIGN_FILL)
        rowSlot:SetVerticalAlignment(VALIGN_FILL)
        local labelSlot = overlay:AddChildToOverlay(label)
        labelSlot:SetHorizontalAlignment(HALIGN_RIGHT)
        labelSlot:SetVerticalAlignment(VALIGN_CENTER)
        label:SetMinDesiredWidth(MODIFIER_RIGHT_INSET)
        label:SetJustification(JUSTIFY_LEFT)
        -- SelfHitTestInvisible on both, so neither intercepts the click that starts key capture.
        overlay:SetVisibility(VIS_VISIBLE)
        label:SetVisibility(VIS_VISIBLE)
    end)
    if not built then
        return nil, nil
    end
    -- Matched to the row's own caption rather than restating a font and colour.
    local caption = nil
    pcall(function() caption = frame.BP_PalTextBlock_Name end)
    NativeStyle.copyFont(label, caption, "keybind modifier label")
    NativeStyle.copyColor(label, caption, "keybind modifier label")
    return overlay, label
end

-- Other mods' keybinds claiming the same chord. Unlike the game-binding check this one includes
-- modifiers: two mods can both register Ctrl+I, and the game's key config cannot reveal it.
local function modConflicts(entry)
    local mine = normalizedChord(entry.current, entry.modifiers)
    local names = {}
    for _, binding in ipairs(Registry.keybindings()) do
        local isSelf = binding.modId == entry.modId and binding.key == entry.key
        if not isSelf and normalizedChord(binding.value, binding.modifiers) == mine then
            names[#names + 1] = binding.title .. ": " .. binding.label
        end
    end
    return names
end

-- Lights vanilla's own conflict indicator and returns the text to append to the caption.
--
-- "Could not read the bindings" is not treated as "no conflict".
local function conflictSuffix(entry)
    local names = {}
    -- A chord is not checked against the game because there is nothing to check it against:
    -- FPalKeyConfigKeys holds two bare FKeys and no modifier flags. The chord still reaches the
    -- game's binding: the engine does not treat a combination as one key and binds do not consume
    -- the press, so Ctrl+R fires both R and Ctrl+R. Not reported, because there is no modifier in
    -- the game's tables to compare against.
    local baseKey, capturedModifiers = parseBinding(entry.current)
    local declaredModifiers = entry.modifiers ~= nil and #entry.modifiers or 0
    if declaredModifiers == 0 and #capturedModifiers == 0 then
        local conflicts, checked = KeyConfig.actionsUsingKey(baseKey)
        if checked then
            for _, action in ipairs(conflicts) do
                names[#names + 1] = KeyConfig.displayNameFor(entry.screen, action)
            end
        elseif not entry.reportedUncheckable then
            -- Reported once per row: an unreadable binding table and a free key look identical on
            -- screen.
            entry.reportedUncheckable = true
            print(MOD_TAG .. " keybind '" .. entry.key
                .. "': could not read the game's key bindings, conflicts not checked")
        end
    end
    for _, name in ipairs(modConflicts(entry)) do
        names[#names + 1] = name
    end

    pcall(function() entry.frame:SetKeyWarning(#names > 0) end)
    if #names == 0 then
        return ""
    end
    local named = {}
    for index = 1, math.min(#names, CONFLICTS_NAMED) do
        local name = names[index]
        if #name > CONFLICT_NAME_MAX then
            name = name:sub(1, CONFLICT_NAME_MAX - 1) .. "\u{2026}"
        end
        named[index] = name
    end
    local summary = table.concat(named, ", ")
    if #names > CONFLICTS_NAMED then
        summary = summary .. " +" .. (#names - CONFLICTS_NAMED)
    end
    if entry.reportedConflictFor ~= entry.current then
        entry.reportedConflictFor = entry.current
        print(MOD_TAG .. " keybind '" .. entry.key .. "': '" .. tostring(entry.current)
            .. "' is already bound to " .. summary)
    end
    return "  (conflicts with " .. summary .. ")"
end

-- Full object path: the asset name repeated after a dot. LoadAsset does not resolve the package form.
local function keyTexture(keyName)
    if type(keyName) ~= "string" or keyName == "" then
        return nil
    end
    local asset = KEY_ICON_PREFIX .. keyName
    local path = KEY_ICON_FOLDER .. asset .. "." .. asset
    local texture = StaticFindObject(path)
    if texture == nil or not texture:IsValid() then
        pcall(function() LoadAsset(path) end)
        texture = StaticFindObject(path)
    end
    if texture ~= nil and texture:IsValid() then
        return texture
    end
    return nil
end

-- Draws the bound key through the button's own setter, the way vanilla does. Writing Image_Key's
-- brush directly does not paint, even when every readable property matches a working vanilla row.
--
-- SetIcon takes an FSlateBrush, which cannot be constructed from Lua, so the brush is READ off a live
-- Controls row and passed through unmodified. That struct belongs to the real Controls page and is
-- never written to.
local function applyIconViaButton(entry)
    local button = nil
    pcall(function() button = entry.frame.WBP_OptionSettings_ListContentButton end)
    if button == nil or not button:IsValid() then
        return false
    end
    local reference = NativeStyle.keyImageReference(entry.screen)
    if reference == nil then
        if not entry.reportedNoBrush then
            entry.reportedNoBrush = true
            print(MOD_TAG .. " keybind '" .. entry.key
                .. "': no live key row to borrow an FSlateBrush from")
        end
        return false
    end
    local applied = pcall(function() button:SetIcon(reference.Brush) end)
    if not applied then
        if not entry.reportedSetIconFailed then
            entry.reportedSetIconFailed = true
            print(MOD_TAG .. " keybind '" .. entry.key .. "': SetIcon rejected the borrowed brush")
        end
        return false
    end

    -- The borrowed brush carries the key of whichever row it came from, so this row's own texture is
    -- swapped in afterwards, on OUR image. SetBrushResourceObject, not SetBrushFromTexture: it
    -- replaces only the texture and leaves the rest of the brush as SetIcon configured it.
    local texture = keyTexture((parseBinding(entry.current)))
    if texture == nil then
        if not entry.reportedNoIcon then
            entry.reportedNoIcon = true
            print(MOD_TAG .. " keybind '" .. entry.key .. "': no key texture for '"
                .. tostring(entry.current) .. "' in " .. KEY_ICON_FOLDER .. ", showing the borrowed key")
        end
        return true
    end
    local swapped = pcall(function() button.Image_Key:SetBrushResourceObject(texture) end)
    if not swapped and not entry.reportedSwapFailed then
        entry.reportedSwapFailed = true
        print(MOD_TAG .. " keybind '" .. entry.key
            .. "': SetBrushResourceObject refused the key texture, showing the borrowed key")
    end
    return true
end

-- Returns whether a glyph is showing, so the caller knows whether the caption must name the key.
-- Every failure is reported separately: they all look like the same blank row on screen.
local function applyKeyIcon(entry)
    if applyIconViaButton(entry) then
        return true
    end
    local image = nil
    pcall(function() image = entry.frame.WBP_OptionSettings_ListContentButton.Image_Key end)
    if image == nil or not image:IsValid() then
        if not entry.reportedNoImage then
            entry.reportedNoImage = true
            print(MOD_TAG .. " keybind '" .. entry.key
                .. "': ListContentButton.Image_Key could not be resolved")
        end
        return false
    end
    local texture = keyTexture((parseBinding(entry.current)))
    if texture == nil then
        if not entry.reportedNoIcon then
            entry.reportedNoIcon = true
            print(MOD_TAG .. " keybind '" .. entry.key .. "': no key texture for '"
                .. tostring(entry.current) .. "' in " .. KEY_ICON_FOLDER .. ", showing key as text")
        end
        return false
    end
    -- bMatchSize=true is required: with false, a freshly built brush keeps ImageSize at 0x0 and Slate
    -- draws nothing even though the texture and visibility are correct.
    local applied = pcall(function() image:SetBrushFromTexture(texture, true) end)
    -- Writing the struct members individually avoids constructing an FVector2D. If the write does not
    -- take, the glyph still renders at texture size rather than not at all.
    pcall(function()
        image.Brush.ImageSize.X = KEY_ICON_SIZE
        image.Brush.ImageSize.Y = KEY_ICON_SIZE
    end)
    if not applied and not entry.reportedSetFailed then
        entry.reportedSetFailed = true
        print(MOD_TAG .. " keybind '" .. entry.key .. "': SetBrushFromTexture rejected the texture")
    end
    return applied
end

-- The caption is the feature name; the bound key belongs on the right in the row's key image, the way
-- the Controls tab lists action-then-key. The key falls back into the caption only when no glyph
-- could be drawn.
local function refreshCaption(entry)
    if entry == nil then
        return
    end
    if capturing == entry then
        RowLabel.set(entry.frame, entry.label .. "   [press a key]")
        return
    end

    local shown = applyKeyIcon(entry)
    local suffix = conflictSuffix(entry)
    -- The glyph can only show the base key: vanilla has no artwork for a chord. Modifiers therefore
    -- go in their own label, whether the player captured them or the schema declared them.
    local _, capturedModifiers = parseBinding(entry.current)
    local modifiers = #capturedModifiers > 0 and capturedModifiers or entry.modifiers
    local prefix = ""
    if modifiers ~= nil and #modifiers > 0 then
        local modifierText = table.concat(modifiers, " + ") .. MODIFIER_SUFFIX
        if entry.modifierLabel ~= nil then
            pcall(function()
                entry.modifierLabel:SetText(FText(modifierText))
                entry.modifierLabel:SetVisibility(VIS_VISIBLE)
            end)
        else
            prefix = MODIFIER_GAP .. modifierText
        end
    elseif entry.modifierLabel ~= nil then
        pcall(function() entry.modifierLabel:SetVisibility(VIS_COLLAPSED) end)
    end
    if shown then
        RowLabel.set(entry.frame, entry.label .. prefix .. suffix)
    else
        RowLabel.set(entry.frame, entry.label .. prefix
            .. "   [" .. tostring(entry.current) .. "]" .. suffix)
    end
end

-- The frame re-runs its own setup in Construct, after the builder has finished, which clears the key
-- image as well as the caption. Re-applied here, matched by frame address.
local function installConstructHook()
    if constructHookInstalled then
        return
    end
    constructHookInstalled = true
    local ok, err = pcall(function()
        RegisterHook(FRAME_PATH .. ":Construct", function(Context)
            local entry = rows[AddressRegistry.addressOf(HookParam.read(Context))]
            if entry == nil then
                return
            end
            applyKeyIcon(entry)
        end)
    end)
    if not ok then
        print(MOD_TAG .. " Failed to hook ListContent Construct for key rows: " .. tostring(err))
    end
end

-- `baseKey` is the key pressed, `modifierName` the modifier held, or nil.
--
-- A schema that declares `modifiers` supplies them itself and expects a bare key back, so for those
-- rows the modifier is dropped rather than the press rejected: pressing Ctrl+K on a row that already
-- forces Ctrl should bind K, not fail silently.
local function stopCapture(entry, baseKey, modifierName)
    if entry == nil then
        return
    end
    if baseKey ~= nil then
        local declaresModifiers = entry.modifiers ~= nil and #entry.modifiers > 0
        local newValue = declaresModifiers and baseKey or formatBinding(baseKey, modifierName)
        entry.current = newValue
        -- Per binding, not per row: a new binding gets to report its own missing glyph.
        entry.reportedNoIcon = nil
        Registry.stage(entry.modId, entry.key, newValue)
    end
    capturing = nil
    refreshCaption(entry)
end

local function installCaptureBinds()
    if captureInstalled then
        return
    end
    captureInstalled = true
    if Key == nil then
        print(MOD_TAG .. " keybind rows: UE4SS Key table unavailable, capture disabled")
        return
    end
    local registered, skipped = 0, 0
    for _, name in ipairs(CAPTURE_KEYS) do
        local keyConst = Key[name]
        if keyConst ~= nil then
            for _, variant in ipairs(CAPTURE_VARIANTS) do
                local modifierConsts = nil
                if variant.modifiers ~= nil then
                    modifierConsts = {}
                    for index, modifier in ipairs(variant.modifiers) do
                        modifierConsts[index] = ModifierKey ~= nil and ModifierKey[modifier] or nil
                    end
                    -- A modifier UE4SS does not expose cannot be registered; the remaining variants
                    -- still are, so the picker degrades rather than failing outright.
                    if modifierConsts[1] == nil then
                        modifierConsts = false
                    end
                end
                if modifierConsts == false then
                    skipped = skipped + 1
                else
                    local ok = pcall(function()
                        local handler = function()
                            -- No row is capturing: the press belongs to the game.
                            if capturing == nil then
                                return
                            end
                            local entry = capturing
                            -- The press arrives on UE4SS's thread; touching UObjects must be deferred
                            -- to the game thread.
                            ExecuteInGameThreadWithDelay(0, function()
                                stopCapture(entry, name, variant.name)
                            end)
                        end
                        if modifierConsts == nil then
                            RegisterKeyBind(keyConst, handler)
                        else
                            RegisterKeyBind(keyConst, modifierConsts, handler)
                        end
                    end)
                    if ok then
                        registered = registered + 1
                    end
                end
            end
        end
    end
    Dev.log("keybind rows: registered " .. registered .. " capture binds ("
        .. #CAPTURE_KEYS .. " keys x " .. #CAPTURE_VARIANTS .. " variants"
        .. (skipped > 0 and (", " .. skipped .. " unavailable") or "") .. ")")
end

local function installClickHook()
    if clickHookInstalled then
        return
    end
    clickHookInstalled = true
    local ok, err = pcall(function()
        RegisterHook(BUTTON_BASE_CLASS .. ":BP_OnClicked", function(Context)
            local entry = buttonOwners[AddressRegistry.addressOf(HookParam.read(Context))]
            if entry == nil then
                return
            end
            -- Clicking the row already capturing cancels.
            if capturing == entry then
                stopCapture(entry, nil)
            else
                local previous = capturing
                capturing = entry
                refreshCaption(previous)
                refreshCaption(entry)
            end
        end)
    end)
    if not ok then
        print(MOD_TAG .. " Failed to hook ListContent OnKeyConfigClicked: " .. tostring(err))
    end
end

-- `value` is the stored binding, e.g. "I" or "Ctrl+I". `modifiers` is the schema's optional list of
-- modifiers the shortcut also requires; capture and the glyph both deal in bare keys.
--
-- Returns the row frame and the widget to lay out. They differ because the row is wrapped: everything
-- else -- SetKeyWarning, SetInteractable, reaffirm, destroy -- operates on the frame.
function RowKeybind.create(outer, modId, key, label, value, modifiers)
    installClickHook()
    installCaptureBinds()
    installConstructHook()

    local frame = Widgets.createUserWidget(outer, FRAME_PATH, FRAME_ASSET)
    if frame == nil then
        return nil
    end
    -- Shows the key-config control. The action name is this mod's own, so nothing in PalKeyConfig
    -- resolves it; the control is used for its appearance and its click signal only.
    local configured = pcall(function()
        frame:SetConfigButton(FName("NMO_" .. modId .. "_" .. key), INPUT_TYPE_KEYBOARD, AXIS_FILTER_NONE)
    end)
    if not configured then
        print(MOD_TAG .. " keybind row '" .. key .. "': SetConfigButton failed")
    end
    -- Matches a real Controls key row: the button visible, every other content child collapsed.
    -- SetConfigButton normally arranges this, but only for an action name it can resolve.
    for field, visibility in pairs({
        WBP_OptionSettings_ListContentButton = VIS_VISIBLE,
        WBP_OptionSettings_ClickableButton = VIS_COLLAPSED,
        WBP_OptionSettings_ListContentSwitch = VIS_COLLAPSED,
        WBP_OptionSettings_ListContentSlider = VIS_COLLAPSED,
        WBP_OptionSettings_ListContentLR = VIS_COLLAPSED,
    }) do
        pcall(function() frame[field]:SetVisibility(visibility) end)
    end
    -- Inside the button, a reference row shows Image_Key and collapses the gamepad key guide.
    pcall(function()
        local button = frame.WBP_OptionSettings_ListContentButton
        button.Image_Key:SetVisibility(VIS_VISIBLE)
        button.WBP_PalKeyGuideIcon:SetVisibility(VIS_COLLAPSED)
    end)

    local address = AddressRegistry.addressOf(frame)
    if address == nil then
        pcall(function() frame:RemoveFromParent() end)
        return nil
    end
    -- `outer` is the options screen instance, which is what reaching a live Controls row for the
    -- borrowed FSlateBrush needs.
    local entry = { frame = frame, modId = modId, key = key, label = label, current = value,
                    screen = outer, modifiers = modifiers }
    -- Wrapped unconditionally, not only for schemas declaring modifiers: the player can capture a
    -- chord on any keybind row, and the label has to exist by then.
    local wrapper, modifierLabel = wrapWithModifierLabel(outer, frame)
    if wrapper == nil then
        print(MOD_TAG .. " keybind row '" .. key .. "': could not build the modifier label wrapper, "
            .. "any modifier will be named after the caption instead")
    end
    entry.wrapper = wrapper
    entry.modifierLabel = modifierLabel
    rows[address] = entry
    -- Publishes the row's address so a consumer mod can resolve this frame back to (modId, key) from
    -- its own Lua VM. Keybind rows have no native setter that carries their value, so the consumer
    -- re-reads the committed value from the config file when this row is re-affirmed.
    AddressRegistry.track(frame, modId, key)

    local button = nil
    pcall(function() button = frame.Button end)
    local buttonAddress = AddressRegistry.addressOf(button)
    if buttonAddress ~= nil then
        buttonOwners[buttonAddress] = entry
    else
        print(MOD_TAG .. " keybind row '" .. key .. "': no Button child, row will not respond to clicks")
    end
    refreshCaption(entry)
    return frame, wrapper or frame
end

function RowKeybind.reaffirm(frame, value)
    local entry = rows[AddressRegistry.addressOf(frame)]
    if entry ~= nil then
        entry.current = value
        refreshCaption(entry)
    end
end

-- See row_switch.destroy for what bookkeepingOnly means.
function RowKeybind.destroy(frame, bookkeepingOnly)
    if frame == nil then
        return
    end
    local address = AddressRegistry.addressOf(frame)
    local wrapper = nil
    if address ~= nil then
        local entry = rows[address]
        if entry ~= nil then
            wrapper = entry.wrapper
            if capturing == entry then
                capturing = nil
            end
        end
        rows[address] = nil
    end
    AddressRegistry.untrack(frame)
    local button = nil
    pcall(function() button = frame.Button end)
    local buttonAddress = AddressRegistry.addressOf(button)
    if buttonAddress ~= nil then
        buttonOwners[buttonAddress] = nil
    end
    RowLabel.clear(frame)
    if not bookkeepingOnly then
        -- The wrapper is what the list holds; detaching it takes the row and label with it. Widgets
        -- built here are outered to the world, so nothing detaches them on the screen's teardown.
        pcall(function() frame:RemoveFromParent() end)
        if wrapper ~= nil then
            pcall(function() wrapper:RemoveFromParent() end)
        end
    end
end

return RowKeybind
