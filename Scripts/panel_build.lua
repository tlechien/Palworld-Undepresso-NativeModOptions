-- Constructs one widget per registered option and returns the state the panel is operated through.
--
-- Attaches nothing: the caller owns a private WBP_PalCommonScrollList_C and adds the returned widgets
-- to it. The screen's own scroll list is shared with vanilla and must never be mutated.
--
-- Apply and Restore-to-Default are not built here either. They ride WBP_OptionSettings_C's own
-- ApplySettings/SetDefault actions, hooked in inject_options.lua, so the screen's existing
-- "F Restore to Default" / "Esc Back" key guide drives this panel as it drives vanilla's.
local AddressRegistry = require("address_registry")
local Registry = require("registry")
local RowImage = require("row_image")
local RowKeybind = require("row_keybind")
local RowLR = require("row_lr")
local RowSection = require("row_section")
local RowSlider = require("row_slider")
local RowSwitch = require("row_switch")
local RowWarning = require("row_warning")

local PanelBuild = {}

-- Pushes a committed value back onto a row. Also the cross-mod "committed" signal -- see
-- row_switch.lua.
local function reaffirmRow(row, value)
    if row.type == "boolean" then
        RowSwitch.reaffirm(row.frame, value)
    elseif row.type == "number" then
        RowSlider.reaffirm(row.frame, value, row.option.min, row.option.max)
    elseif row.type == "enum" then
        RowLR.reaffirm(row.frame, value, row.option.choices)
    elseif row.type == "keybind" then
        RowKeybind.reaffirm(row.frame, value)
    end
end

-- Builds one option. Returns the row frame, the widget to lay out, and whether that widget is raw
-- UMG rather than a UserWidget. The two differ only when a builder wraps its row in a container of
-- its own; everything else -- row modifiers, panelState.rows, reaffirm, destroy -- uses the frame.
local function buildOption(worldContext, id, option, value)
    if option.type == "section" then
        local widget = RowSection.create(worldContext, option.label, option.style, worldContext)
        return widget, widget, widget ~= nil
    elseif option.type == "warning" then
        local widget = RowWarning.create(worldContext, option.label, option.style, worldContext)
        return widget, widget, widget ~= nil
    elseif option.type == "image" then
        local widget = RowImage.create(worldContext, option.texture, option.width, option.height)
        return widget, widget, widget ~= nil
    elseif option.type == "boolean" then
        local frame = RowSwitch.create(worldContext, id, option.key, option.label, value)
        return frame, frame, false
    elseif option.type == "number" then
        local frame = RowSlider.create(worldContext, id, option.key, option.label, value,
            option.min, option.max)
        return frame, frame, false
    elseif option.type == "enum" then
        local frame = RowLR.create(worldContext, id, option.key, option.label, value, option.choices)
        return frame, frame, false
    elseif option.type == "keybind" then
        local frame, layout = RowKeybind.create(worldContext, id, option.key, option.label, value,
            option.modifiers)
        return frame, layout or frame, false
    end
    return nil, nil, false
end

-- `worldContext` must be an already-live widget, typically the options screen instance:
-- WidgetBlueprintLibrary:Create silently returns an invalid widget when given a freshly constructed
-- one, so it cannot be a container built here.
--
-- Returns panelState, whose `widgets` array is every constructed widget in display order.
function PanelBuild.build(worldContext)
    local panelState = { rows = {}, widgets = {}, sections = {}, displayOnly = {}, rawWidgets = {} }
    -- Consumer mods can only hand over a schema through shared variables, so this is where a
    -- published one becomes a visible row. Repeated on every build because a mod may load or register
    -- at any later point; already-registered ids are skipped.
    Registry.discoverPending()

    -- One section per registered mod, in registration order. Rows still go into the single flat
    -- `widgets` list; sections only record which rows belong to which mod, so the tab header can show
    -- one mod at a time by toggling visibility rather than rebuilding the list.
    for _, id in ipairs(Registry.order) do
        local schema = Registry.schemas[id]
        local pending = Registry.beginEdit(id)
        -- The visibility each widget is BORN with, captured here. The tab header collapses inactive
        -- rows, so reading a row's current visibility later would record Collapsed as its shown state
        -- and never be able to reveal it again.
        local section = { id = id, title = schema.title, widgets = {}, visibleVisibility = {} }
        for _, option in ipairs(schema.options) do
            local frame, layout, raw = buildOption(worldContext, id, option, pending[option.key])
            if frame ~= nil then
                -- Native calls on the row frame, so a warned or disabled row looks exactly like
                -- vanilla's. Display-only entries have no frame to configure.
                if not Registry.isDisplayOnly(option.type) then
                    if option.warning then
                        pcall(function() frame:SetKeyWarning(true) end)
                    end
                    if option.disabled then
                        pcall(function() frame:SetInteractable(false) end)
                    end
                end
                if raw then
                    panelState.rawWidgets[layout] = true
                end
                table.insert(panelState.widgets, layout)
                table.insert(section.widgets, layout)
                local bornVisibility = nil
                pcall(function() bornVisibility = layout.Visibility end)
                section.visibleVisibility[layout] = bornVisibility
                -- Display-only entries are laid out but never tracked as rows, which keeps them out
                -- of the value handling in applyAll/resetAll/destroy.
                if Registry.isDisplayOnly(option.type) then
                    table.insert(panelState.displayOnly, frame)
                else
                    panelState.rows[id .. "." .. option.key] =
                        { frame = frame, type = option.type, modId = id, option = option }
                end
            end
        end
        -- A schema whose options are all unbuildable would otherwise get an empty tab.
        if #section.widgets > 0 then
            table.insert(panelState.sections, section)
        end
    end

    -- Last, once every row has published its address: tells consumer mods their cached
    -- address->option mapping is stale.
    AddressRegistry.publishEpoch()

    return panelState
end

-- Commits every mod's pending edits, then pushes the confirmed values back onto the rows.
--
-- `panelState` may be nil: vanilla's confirmation prompt is answered while the screen is already
-- closing, so committing the values is what matters and re-syncing doomed rows is not.
function PanelBuild.applyAll(panelState)
    for _, id in ipairs(Registry.order) do
        Registry.apply(id)
    end
    if panelState == nil then
        return
    end
    for _, row in pairs(panelState.rows) do
        reaffirmRow(row, Registry.values[row.modId][row.option.key])
    end
end

-- Resets every row to its schema default in the pending buffer only, mirroring vanilla's SetDefault:
-- a staged change that still requires Apply to commit.
function PanelBuild.resetAll(panelState)
    for _, id in ipairs(Registry.order) do
        for _, option in ipairs(Registry.schemas[id].options) do
            if not Registry.isDisplayOnly(option.type) then
                Registry.stage(id, option.key, option.default)
            end
        end
    end
    for _, row in pairs(panelState.rows) do
        reaffirmRow(row, row.option.default)
    end
end

-- The player declined the apply prompt. ApplySettings(false) is the only trustworthy decline signal,
-- which is why discarding lives here rather than in destroy(): the close runs before that answer
-- arrives. Leaving pending in place until then is safe, since reopening the panel calls
-- Registry.beginEdit, which reseeds it from the committed values.
function PanelBuild.discardAll()
    for _, id in ipairs(Registry.order) do
        Registry.discardEdit(id)
    end
end

-- `bookkeepingOnly`: pass true when the whole widget tree is already being torn down elsewhere, where
-- RemoveFromParent would be redundant and risks touching a mid-teardown widget.
function PanelBuild.destroy(panelState, bookkeepingOnly)
    if panelState == nil then
        return
    end
    for _, widget in ipairs(panelState.displayOnly or {}) do
        -- Every display-only builder detaches the same way.
        RowSection.destroy(widget, bookkeepingOnly)
    end
    for _, row in pairs(panelState.rows) do
        if row.type == "boolean" then
            RowSwitch.destroy(row.frame, bookkeepingOnly)
        elseif row.type == "number" then
            RowSlider.destroy(row.frame, bookkeepingOnly)
        elseif row.type == "enum" then
            RowLR.destroy(row.frame, bookkeepingOnly)
        elseif row.type == "keybind" then
            RowKeybind.destroy(row.frame, bookkeepingOnly)
        end
    end
end

return PanelBuild
