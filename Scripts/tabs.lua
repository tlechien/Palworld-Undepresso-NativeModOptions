-- Drives WBP_OptionSettings_Tab, the header the Controls tab uses for its Keyboard/Controller-Pad
-- selector, to give the Mod Options page one tab per registered mod.
--
-- The header is a designer widget on WBP_OptionSettings_C, shared with vanilla, so everything here is
-- set up when our page is shown and undone when it is hidden. Vanilla reconfigures it on its own tab
-- switch, so nothing needs restoring beyond our address bookkeeping.
--
-- The buttons are driven directly rather than through the header's SetupTabs(), which takes
-- FDataTableRowHandles and so can only name vanilla's own localised entries. TabButton:SetName takes
-- an FText and can carry a mod's title.
--
-- The designer tree has exactly three tab buttons. They are treated as a sliding WINDOW onto the
-- registered mods rather than one button per mod, so the header stays a constant size however many
-- mods are installed -- appending buttons instead splits the same fixed-width box until captions
-- truncate. Paging rides the screen's own PreTab/NextTab actions, the Q/E keys the header already
-- draws guide icons for.
local AddressRegistry = require("address_registry")
local HookParam = require("hook_param")

local MOD_TAG = "[NativeModOptions]"
local TAB_BUTTON_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_TabButton"
local TAB_BUTTON_CLASS = TAB_BUTTON_ASSET .. ".WBP_OptionSettings_TabButton_C"
-- The tab button's own click handler. Context is the TabButton itself, which is what makes an address
-- lookup enough to identify which button was pressed.
local TAB_CLICK_EVENT =
    "BndEvt__WBP_OptionSettings_TabButton_WBP_PalCommonButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature"
local DESIGNER_TAB_FIELDS = {
    "WBP_OptionSettings_TabButton",
    "WBP_OptionSettings_TabButton_1",
    "WBP_OptionSettings_TabButton_2",
}
local COLLAPSED = 1
local VISIBLE = 4

local Tabs = {}

local addressOf = AddressRegistry.addressOf
-- [tab button address] = { slot, state }. The click hook is class-level and fires for vanilla's own
-- tabs too; an address that is not in here is not ours.
local tabOwner = {}
local hookInstalled = false

local function setVisibility(widget, visibility)
    if widget == nil or not widget:IsValid() then
        return
    end
    pcall(function() widget:SetVisibility(visibility) end)
end

local function designerButton(header, index)
    local field = DESIGNER_TAB_FIELDS[index]
    if field == nil then
        return nil
    end
    local button = nil
    pcall(function() button = header[field] end)
    return (button ~= nil and button:IsValid()) and button or nil
end

-- Shows the selected section's rows and collapses every other section's.
local function applyRows(state)
    for sectionIndex, section in ipairs(state.sections) do
        local visible = sectionIndex == state.current
        for _, widget in ipairs(section.widgets) do
            -- Restored to the visibility the row was BORN with, recorded at creation. This runs again
            -- on every tab change, by which point inactive rows are already Collapsed, so reading
            -- current state would make "show" mean "stay collapsed".
            setVisibility(widget, visible and (section.visibleVisibility[widget] or VISIBLE) or COLLAPSED)
        end
    end
end

-- Paints the designer buttons as a window onto state.sections starting at state.windowStart. Slots
-- past the last section are collapsed.
local function applyWindow(state)
    -- With more mods than slots, the off-window tabs are simply not on screen, and the Q/E guide icons
    -- are drawn whether or not paging does anything. A position counter on the active tab reports both
    -- that more exist and how far through them you are. Shown only when the tabs actually overflow.
    local overflowing = #state.sections > #DESIGNER_TAB_FIELDS

    for slot = 1, #DESIGNER_TAB_FIELDS do
        local button = state.buttons[slot]
        if button ~= nil and button:IsValid() then
            local sectionIndex = state.windowStart + slot - 1
            local section = state.sections[sectionIndex]
            if section == nil then
                setVisibility(button, COLLAPSED)
            else
                local active = sectionIndex == state.current
                local caption = section.title
                if overflowing and active then
                    caption = caption .. "  (" .. sectionIndex .. "/" .. #state.sections .. ")"
                end
                -- The index handed to SetName is what the button reports through its own SwitchTabTo
                -- delegate, so it is the position in the header, not in state.sections.
                pcall(function() button:SetName(FText(caption), slot - 1) end)
                pcall(function() button:SetTabActive(active) end)
                setVisibility(button, VISIBLE)
            end
        end
    end
end

-- Selects a section by absolute index, scrolling the window the minimum distance needed to bring it
-- into view. Selection and window position are tracked separately so paging past an edge advances by
-- one rather than jumping a whole page.
function Tabs.select(state, index)
    if state == nil or #state.sections == 0 then
        return
    end
    if index < 1 then
        index = #state.sections
    end
    if index > #state.sections then
        index = 1
    end
    state.current = index

    local windowSize = #DESIGNER_TAB_FIELDS
    local maxStart = math.max(1, #state.sections - windowSize + 1)
    if index < state.windowStart then
        state.windowStart = index
    elseif index > state.windowStart + windowSize - 1 then
        state.windowStart = index - windowSize + 1
    end
    if state.windowStart > maxStart then
        state.windowStart = maxStart
    end
    if state.windowStart < 1 then
        state.windowStart = 1
    end

    applyWindow(state)
    applyRows(state)
end

-- Moves the selection by `delta`, wrapping at either end.
function Tabs.step(state, delta)
    if state == nil or #state.sections == 0 then
        return
    end
    Tabs.select(state, state.current + delta)
end

-- Re-applies the header without rebuilding, keeping the current selection.
--
-- Showing our page invokes vanilla's Control tab handler, which reconfigures this same shared header
-- with its own captions and finishes asynchronously, so a build in that frame is overwritten a few
-- frames later. Called from the same re-assert schedule that holds our page in place.
function Tabs.refresh(state)
    if state == nil or state.header == nil or not state.header:IsValid() then
        return
    end
    setVisibility(state.header, VISIBLE)
    Tabs.select(state, state.current > 0 and state.current or 1)
end

local function installClickHook()
    if hookInstalled then
        return
    end
    hookInstalled = true
    local ok, err = pcall(function()
        RegisterHook(TAB_BUTTON_CLASS .. ":" .. TAB_CLICK_EVENT, function(Context)
            local owner = tabOwner[addressOf(HookParam.read(Context))]
            if owner == nil then
                return
            end
            -- owner.slot is a position in the header; which section it points at depends on where the
            -- window currently sits. Deferred a tick so vanilla's own click handling finishes first.
            ExecuteInGameThreadWithDelay(0, function()
                Tabs.select(owner.state, owner.state.windowStart + owner.slot - 1)
            end)
        end)
    end)
    if not ok then
        print(MOD_TAG .. " Failed to hook TabButton click: " .. tostring(err))
    end
end

-- Configures the header for `sections` and selects the first. Returns a state handle for
-- Tabs.destroy, or nil when there is nothing to show.
function Tabs.build(instance, sections)
    local header = nil
    pcall(function() header = instance.WBP_OptionSettings_Tab end)
    if header == nil or not header:IsValid() or sections == nil or #sections == 0 then
        return nil
    end
    installClickHook()

    local state = {
        header = header,
        sections = sections,
        buttons = {},
        windowStart = 1,
        current = 0,
    }
    for slot = 1, #DESIGNER_TAB_FIELDS do
        local button = designerButton(header, slot)
        if button ~= nil then
            state.buttons[slot] = button
            local address = addressOf(button)
            if address ~= nil then
                tabOwner[address] = { slot = slot, state = state }
            end
        end
    end

    setVisibility(header, VISIBLE)
    Tabs.select(state, 1)
    return state
end

-- Undoes Tabs.build. The designer buttons are left in place for vanilla, which renames and re-shows
-- them on its own tab switch; only our address bookkeeping is dropped.
function Tabs.destroy(state)
    if state == nil then
        return
    end
    for _, button in pairs(state.buttons) do
        local address = addressOf(button)
        if address ~= nil then
            tabOwner[address] = nil
        end
    end
    setVisibility(state.header, COLLAPSED)
    state.buttons = {}
end

return Tabs
