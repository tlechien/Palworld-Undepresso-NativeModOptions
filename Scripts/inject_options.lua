-- Adds a "Mod Options" category to WBP_OptionSettings_C and shows this mod's rows when it is
-- clicked. That class serves both the ESC menu and the title menu, so one hook covers both.
--
-- Tab model: vanilla keeps its five category pages as permanent children of one shared ScrollBox and
-- switches tabs by toggling their Visibility. This mod adds its page as a sixth permanent child and
-- uses the same mechanism.
--
-- Visibility alone is not enough. The content area is not laid out until vanilla's tab-switch handler
-- has run once for that screen instance; before it does, every page in the ScrollBox reports a zero
-- desired size, vanilla's own included. showOurs therefore invokes the Control tab's bound event and
-- swaps our page in for the one it activated.
local AddressRegistry = require("address_registry")
local Dev = require("dev")
local HookParam = require("hook_param")
local KeyConfig = require("key_config")
local PanelBuild = require("panel_build")
local Registry = require("registry")
local Tabs = require("tabs")
local Widgets = require("widgets")

local MOD_TAG = "[NativeModOptions]"
local OPTION_SETTINGS_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings"
local OPTION_SETTINGS_CLASS = OPTION_SETTINGS_ASSET .. ".WBP_OptionSettings_C"
local MENU_BUTTON_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/Option/WBP_OptionSettings_MenuButton"
local MENU_BUTTON_CLASS = MENU_BUTTON_ASSET .. ".WBP_OptionSettings_MenuButton_C"
-- The list component vanilla hosts its category pages in, each a direct child of its ScrollBox_0.
local SCROLL_LIST_ASSET = "/Game/Pal/Blueprint/UI/CommonWidget/CommonScrollList/WBP_PalCommonScrollList"
local SCROLL_LIST_CLASS = SCROLL_LIST_ASSET .. ".WBP_PalCommonScrollList_C"
-- Clicks land on the button's invisible child, not on MenuButton_C, which has no OnClicked UFunction.
local BUTTON_BASE_ASSET = "/Game/Pal/Blueprint/UI/System/Style/WBP_PalCommonButtonBase"
local BUTTON_BASE_CLASS = BUTTON_BASE_ASSET .. ".WBP_PalCommonButtonBase_C"
local LABEL = "Mod Options"
local REAL_BUTTON_FIELDS = { "Graphic", "Sound", "Game", "Key", "Other" }
local REAL_PAGE_FIELDS = { "GraphicSettings", "AudioSettings", "KeySettings", "GameSettings", "OtherSettings" }
-- ESlateVisibility values vanilla uses for its own pages: SelfHitTestInvisible for the active page,
-- so its children still receive input, and Collapsed for inactive ones, which removes them from
-- layout entirely.
local PAGE_ACTIVE_VIS = 4
local PAGE_INACTIVE_VIS = 1
-- EHorizontalAlignment::HAlign_Left. Fill (0) is the slot default.
local HALIGN_LEFT = 1
-- Size overrides for the SizeBox wrapping our list. Without an explicit width the SizeBox collapses
-- to roughly 30px, inheriting the near-zero desired width of its CanvasPanel-rooted content.
-- LIST_WIDTH matches the 704-786 vanilla's own pages report; LIST_HEIGHT is not measured against one.
local LIST_HEIGHT = 900
local LIST_WIDTH = 786
-- Vanilla decides whether to prompt "apply changed settings?" on the way out from its own pages'
-- SomethingChanged flags, and a mod-only edit leaves all five false, so the screen would close
-- silently and ApplySettings would never run. Raising one flag routes a mod edit through the same
-- prompt instead of inventing a second one.
--
-- GameSettings is the page raised, for having the most inert apply: it writes back numeric gameplay
-- preferences nobody touched. Graphic can re-apply resolution and quality, Key rewrites bindings from
-- a cache, and Sound/Other reach audio devices and language.
local DIRTY_PAGE_FIELD = "GameSettings"
-- The Control tab button's bound-event handler. Invoking it is equivalent to clicking Controls, the
-- tab used because switching to the already-selected one early-outs and a freshly opened screen
-- shows Graphic. SwitchTabTo activates nothing when called directly, at any index.
local CONTROL_TAB_EVENT =
    "BndEvt__WBP_OptionSettings_WBP_OptionSettings_MenuButton_Control_K2Node_ComponentBoundEvent_2_OnClicked__DelegateSignature"
-- The page swap is applied immediately and re-asserted on these delays: the switch drives an
-- animation whose completion callbacks land later and can re-show the page it activated.
local SWITCH_REASSERT_MS = { 100, 300, 600 }

local InjectOptions = {}

local injected = {}     -- [screen address] = true
local screens = {}      -- [screen address] = screenState
-- Two kinds of address share this table -- a MenuButton_C's own, used by the relabel hook, and its
-- invisible child's, used by the click hook. Distinct live objects never share an address.
local buttonOwner = {}
local epochs = {}
local hooksInstalled = false
local inject -- forward-declared: installHooks needs it, and it is defined below.

local addressOf = AddressRegistry.addressOf

local function invisibleChildOf(menuButton)
    local child = nil
    pcall(function() child = menuButton.WBP_PalInvisibleButton end)
    return child
end

local function relabel(button)
    pcall(function() button.BP_PalTextBlock_Name:SetText(FText(LABEL)) end)
end

local function detach(widget)
    if widget == nil then
        return
    end
    local ok, err = pcall(function() widget:RemoveFromParent() end)
    if not ok then
        print(MOD_TAG .. " detach() RemoveFromParent threw: " .. tostring(err))
    end
end

-- Tells the screen it has an unapplied change, so Escape and Tab route through vanilla's prompt.
local function markVanillaDirty(instance)
    local ok = pcall(function() instance[DIRTY_PAGE_FIELD].SomethingChanged = true end)
    if not ok then
        print(MOD_TAG .. " could not raise " .. DIRTY_PAGE_FIELD .. ".SomethingChanged -- leaving the "
            .. "options screen will not prompt to apply mod changes")
    end
    return ok
end

local function setPageVisible(page, active)
    if page == nil or not page:IsValid() then
        return
    end
    pcall(function() page:SetVisibility(active and PAGE_ACTIVE_VIS or PAGE_INACTIVE_VIS) end)
end

-- Hides all five real pages rather than detecting the active one: on the first click of a session
-- none is marked active, so a scan finds nothing to hide and leaves vanilla's default page painting
-- over the same ScrollBox. At most one page is ever visible, so hiding all five is equivalent.
local function hideAllRealPages(instance)
    for _, field in ipairs(REAL_PAGE_FIELDS) do
        local ok, page = pcall(function() return instance[field] end)
        if ok and page ~= nil and page:IsValid() then
            setPageVisible(page, false)
        end
    end
end

-- Swaps our page in for whichever real page the tab switch activated, then holds it there.
local function activateOurPage(screenState)
    if screenState.torndown or screenState.showing ~= "switching" then
        return
    end
    hideAllRealPages(screenState.instance)
    setPageVisible(screenState.ourPage, true)
    -- The tab header is shared with vanilla and is only ours while our page is visible, so it is
    -- built here rather than at page-build time.
    if screenState.tabState == nil and screenState.panelState ~= nil then
        screenState.tabState = Tabs.build(screenState.instance, screenState.panelState.sections)
    end
    screenState.showing = "ours"
    for _, delay in ipairs(SWITCH_REASSERT_MS) do
        ExecuteInGameThreadWithDelay(delay, function()
            if screenState.torndown or screenState.showing ~= "ours" then
                return
            end
            hideAllRealPages(screenState.instance)
            setPageVisible(screenState.ourPage, true)
            -- The same late overwrite that re-shows vanilla's page also restores its tab captions.
            Tabs.refresh(screenState.tabState)
        end)
    end
end

-- Runs vanilla's tab-switch handler, then swaps our page in for the one it activated.
local function showOurs(screenState)
    if screenState.showing == "ours" or screenState.showing == "switching" then
        return
    end
    screenState.showing = "switching"
    local switchOk = pcall(function()
        screenState.instance[CONTROL_TAB_EVENT](screenState.instance)
    end)
    if not switchOk then
        print(MOD_TAG .. " showOurs(): Control tab handler unavailable -- content may not render")
    end
    -- Applied in the same frame: any delay is a visible flash of the page vanilla activated.
    activateOurPage(screenState)
end

local function showVanilla(screenState)
    if screenState.showing == "vanilla" then
        return
    end
    setPageVisible(screenState.ourPage, false)
    -- Hands the shared tab header back before vanilla's page takes over.
    Tabs.destroy(screenState.tabState)
    screenState.tabState = nil
    screenState.showing = "vanilla"
end

-- Finds the shared ScrollBox by walking up from any real page; all five report it as their parent.
-- Used instead of GetScrollBox(), which returns invalid on this install across repeated retries.
local function findRealScrollBox(instance)
    for _, field in ipairs(REAL_PAGE_FIELDS) do
        local ok, page = pcall(function() return instance[field] end)
        if ok and page ~= nil and page:IsValid() then
            local parent = nil
            local parentOk = pcall(function() parent = page:GetParent() end)
            if parentOk and parent ~= nil and parent:IsValid() then
                return parent
            end
        end
    end
    return nil
end

-- Builds the row content and adds it as a sixth permanent child of the shared ScrollBox.
--
-- Called from buildScreenState, after inject()'s readiness checks pass: calling these native
-- functions earlier can crash rather than return an invalid object, so retries defer back here.
local function tryBuildOurPage(screenState, attempt)
    attempt = attempt or 0
    local scrollBox = findRealScrollBox(screenState.instance)
    if scrollBox == nil or not scrollBox:IsValid() then
        if attempt < 3 then
            ExecuteInGameThreadWithDelay(300, function() tryBuildOurPage(screenState, attempt + 1) end)
        else
            print(MOD_TAG .. " tryBuildOurPage(): could not find the real ScrollBox after "
                .. (attempt + 1) .. " attempts -- Mod Options tab will show no content")
        end
        return
    end

    screenState.panelState = PanelBuild.build(screenState.instance)
    screenState.ourList = Widgets.createUserWidget(screenState.instance, SCROLL_LIST_CLASS, SCROLL_LIST_ASSET)
    if screenState.ourList == nil then
        print(MOD_TAG .. " tryBuildOurPage(): failed to construct our own page container -- "
            .. "Mod Options tab will show no content")
        return
    end
    -- One VerticalBox inside the ScrollBox with every widget as a direct child, as vanilla composes
    -- its own pages. A ScrollBox slot fills its width and stretches a fixed-size child across the
    -- panel; a VerticalBox slot takes the child's own size, which is what makes the rows sit
    -- correctly. It accepts any UWidget, so rows and raw widgets attach the same way.
    local list = Widgets.construct("/Script/UMG.VerticalBox", screenState.ourList)
    if list == nil then
        print(MOD_TAG .. " tryBuildOurPage(): failed to construct the list container -- "
            .. "Mod Options tab will show no content")
        return
    end
    pcall(function() screenState.ourList.ScrollBox_0:AddChild(list) end)
    for _, widget in ipairs(screenState.panelState.widgets) do
        pcall(function()
            local slot = list:AddChildToVerticalBox(widget)
            -- Raw widgets carry their own footprint, so left-aligning lets that decide the width
            -- instead of being stretched. Rows keep the slot default and span the list.
            if screenState.panelState.rawWidgets[widget] and slot ~= nil and slot:IsValid() then
                slot:SetHorizontalAlignment(HALIGN_LEFT)
            end
        end)
    end
    -- ourList is rooted in a CanvasPanel, so added through a generic AddChild it inherits none of the
    -- explicit size a designer-placed slot gives vanilla's pages and reports zero desired height.
    -- Wrapping it in a sized SizeBox fixes that. Visibility is toggled on the WRAPPER: Collapsed
    -- removes a widget from layout regardless of any size override, so collapsing the content alone
    -- would not free the space.
    screenState.ourPage = Widgets.construct("/Script/UMG.SizeBox", scrollBox)
    if screenState.ourPage ~= nil then
        local wrapped = pcall(function()
            screenState.ourPage:SetHeightOverride(LIST_HEIGHT)
            screenState.ourPage:SetWidthOverride(LIST_WIDTH)
            screenState.ourPage:SetContent(screenState.ourList)
        end)
        if not wrapped then
            screenState.ourPage = screenState.ourList
        end
    else
        screenState.ourPage = screenState.ourList
    end
    -- Attached immediately: a widget must never be left unparented, or the engine's GC can reclaim it.
    pcall(function() scrollBox:AddChild(screenState.ourPage) end)
    setPageVisible(screenState.ourPage, false)
end

-- Records our button's addresses and every real category button's, so the click hook can tell "the
-- player left our tab" from "the player is still on it".
local function buildScreenState(instance, ourButton)
    local screenState = {
        instance = instance,
        ourButton = ourButton,
        ourButtonAddress = addressOf(ourButton),
        ourInvisibleAddress = addressOf(invisibleChildOf(ourButton)),
        showing = "vanilla",
    }

    tryBuildOurPage(screenState)

    -- Fired by Registry.stage only when a value diverges from what is committed. Nothing polls, and
    -- an edit the player reverts by hand raises no flag.
    Registry.onChanged = function(id, key, value)
        if screenState.torndown then
            return
        end
        markVanillaDirty(instance)
    end

    buttonOwner[screenState.ourButtonAddress] = screenState
    if screenState.ourInvisibleAddress ~= nil then
        buttonOwner[screenState.ourInvisibleAddress] = screenState
    end
    for _, field in ipairs(REAL_BUTTON_FIELDS) do
        local ok, button = pcall(function() return instance["WBP_OptionSettings_MenuButton_" .. field] end)
        if ok then
            local address = addressOf(button)
            if address ~= nil then
                buttonOwner[address] = screenState
            end
            local invisibleAddress = addressOf(invisibleChildOf(button))
            if invisibleAddress ~= nil then
                buttonOwner[invisibleAddress] = screenState
            end
        end
    end

    return screenState
end

-- Every hook here is class-level and fires for widgets this mod does not own, so each callback
-- resolves its Context through buttonOwner or screens and no-ops when it finds nothing.
local function installHooks()
    if hooksInstalled then
        return
    end
    hooksInstalled = true

    local ok, err = pcall(function()
        RegisterHook(MENU_BUTTON_CLASS .. ":Construct", function(Context)
            local button = HookParam.read(Context)
            local address = addressOf(button)
            local screenState = address ~= nil and buttonOwner[address] or nil
            if screenState ~= nil and address == screenState.ourButtonAddress then
                relabel(button)
            end
        end)
    end)
    if not ok then
        print(MOD_TAG .. " Failed to hook MenuButton Construct: " .. tostring(err))
    end

    -- MenuButton_C delegates input to its WBP_PalInvisibleButton child, an empty subclass of
    -- WBP_PalCommonButtonBase_C, which is where BP_OnClicked is reflected. MenuButton_C's own BndEvt
    -- wrappers are ambiguous with hover.
    local clickOk, clickErr = pcall(function()
        RegisterHook(BUTTON_BASE_CLASS .. ":BP_OnClicked", function(Context)
            local address = addressOf(HookParam.read(Context))
            local screenState = address ~= nil and buttonOwner[address] or nil
            if screenState == nil then
                return
            end
            if address == screenState.ourInvisibleAddress then
                relabel(screenState.ourButton)
                ExecuteInGameThreadWithDelay(0, function() showOurs(screenState) end)
            else
                ExecuteInGameThreadWithDelay(0, function() showVanilla(screenState) end)
            end
        end)
    end)
    if not clickOk then
        print(MOD_TAG .. " Failed to hook WBP_PalCommonButtonBase_C:BP_OnClicked: " .. tostring(clickErr))
    end

    -- Q/E paging. PreTab/NextTab are the screen's own actions behind the key guide icons the header
    -- already draws. Gated on our page being visible, since they also drive vanilla's own switch.
    for _, tab in ipairs({ { name = "PreTab", delta = -1 }, { name = "NextTab", delta = 1 } }) do
        local tabOk, tabErr = pcall(function()
            RegisterHook(OPTION_SETTINGS_CLASS .. ":" .. tab.name, function(Context)
                local screenState = screens[addressOf(HookParam.read(Context))]
                if screenState == nil or screenState.showing ~= "ours" then
                    return
                end
                ExecuteInGameThreadWithDelay(0, function()
                    if screenState.torndown then
                        return
                    end
                    Tabs.step(screenState.tabState, tab.delta)
                end)
            end)
        end)
        if not tabOk then
            print(MOD_TAG .. " Failed to hook OptionSettings " .. tab.name .. ": " .. tostring(tabErr))
        end
    end

    -- Apply and Restore-to-Default ride the screen's own actions rather than mod-built buttons, so the
    -- existing "F Restore to Default" / "Esc Back" key guide drives this tab as it drives vanilla's.
    --
    -- Confirmed is the player's answer to the confirmation prompt: true commits, false discards.
    local applyOk, applyErr = pcall(function()
        RegisterHook(OPTION_SETTINGS_CLASS .. ":ApplySettings", function(Context, Confirmed)
            local instance = HookParam.read(Context)
            if HookParam.read(Confirmed) ~= true then
                PanelBuild.discardAll()
                return
            end
            -- Deliberately not gated on the screen still being registered or on a live panelState:
            -- the prompt is answered while the screen is already closing, and requiring either is what
            -- dropped confirmed changes.
            local screenState = screens[addressOf(instance)]
            PanelBuild.applyAll(screenState ~= nil and screenState.panelState or nil)
        end)
    end)
    if not applyOk then
        print(MOD_TAG .. " Failed to hook OptionSettings ApplySettings: " .. tostring(applyErr))
    end

    -- Restore-to-Default rides SetDefaultAction, the screen's own F action. Like vanilla's, this only
    -- STAGES the defaults; Apply still commits them.
    local actionOk, actionErr = pcall(function()
        RegisterHook(OPTION_SETTINGS_CLASS .. ":SetDefaultAction", function(Context)
            local screenState = screens[addressOf(HookParam.read(Context))]
            if screenState == nil or screenState.panelState == nil then
                return
            end
            if screenState.showing ~= "ours" then
                return
            end
            PanelBuild.resetAll(screenState.panelState)
        end)
    end)
    if not actionOk then
        print(MOD_TAG .. " Failed to hook OptionSettings SetDefaultAction: " .. tostring(actionErr))
    end

    -- SetDefault(bool) is the confirmation half of the same F action, kept as a second entry point.
    -- Traced on a live screen it never fired while our page was showing -- vanilla routes the answer
    -- to the active page's own no-arg SetDefault, which ours is not -- so SetDefaultAction above is
    -- what actually drives this tab. Harmless if both fire: resetAll stages the same defaults twice.
    --
    -- Gated on our page being visible: vanilla resets the tab the player is looking at, so pressing F
    -- on the Graphics tab must not wipe a mod's settings.
    local defaultOk, defaultErr = pcall(function()
        RegisterHook(OPTION_SETTINGS_CLASS .. ":SetDefault", function(Context, Confirmed)
            local screenState = screens[addressOf(HookParam.read(Context))]
            if screenState == nil or screenState.panelState == nil then
                return
            end
            if HookParam.read(Confirmed) ~= true or screenState.showing ~= "ours" then
                return
            end
            PanelBuild.resetAll(screenState.panelState)
        end)
    end)
    if not defaultOk then
        print(MOD_TAG .. " Failed to hook OptionSettings SetDefault: " .. tostring(defaultErr))
    end

    -- OnSetup/OpenPanel fire when the screen is set up or opened, which NotifyOnNewObject cannot
    -- provide on a reopened screen where the instance is reused. inject() is idempotent, so multiple
    -- trigger points are safe.
    for _, functionName in ipairs({ "OnSetup", "OpenPanel" }) do
        local setupOk, setupErr = pcall(function()
            RegisterHook(OPTION_SETTINGS_CLASS .. ":" .. functionName, function(Context)
                local instance = HookParam.read(Context)
                if instance ~= nil then
                    inject(instance)
                end
            end)
        end)
        if not setupOk then
            print(MOD_TAG .. " Failed to hook OptionSettings " .. functionName .. ": " .. tostring(setupErr))
        end
    end

    -- Teardown runs in ClosePanel, which fires before the screen's native teardown, with Destruct as a
    -- fallback. bookkeepingOnly=false is required: every widget this mod constructs is outered to the
    -- world, not to the screen's WidgetTree, so nothing else detaches them.
    --
    -- NOT BackAction. That is Escape's action, not the close: when something has changed it opens the
    -- apply prompt and returns, and ApplySettings only arrives once the player has answered. Tearing
    -- down there discarded pending edits before that answer.
    local function teardown(screenState)
        if screenState.torndown then
            return
        end
        screenState.torndown = true
        Registry.onChanged = nil
        -- The conflict captions were read off this screen's Controls page, so they go with it.
        KeyConfig.forgetDisplayNames()
        local okAll, errAll = pcall(function()
            showVanilla(screenState)
            Tabs.destroy(screenState.tabState)
            screenState.tabState = nil
            detach(screenState.ourPage)
            PanelBuild.destroy(screenState.panelState, false)
            detach(screenState.ourButton)
            buttonOwner[screenState.ourButtonAddress] = nil
            buttonOwner[screenState.ourInvisibleAddress] = nil
            for _, field in ipairs(REAL_BUTTON_FIELDS) do
                local fieldOk, button = pcall(function()
                    return screenState.instance["WBP_OptionSettings_MenuButton_" .. field]
                end)
                if fieldOk then
                    local buttonAddress = addressOf(button)
                    if buttonAddress ~= nil then
                        buttonOwner[buttonAddress] = nil
                    end
                    local invisibleAddress = addressOf(invisibleChildOf(button))
                    if invisibleAddress ~= nil then
                        buttonOwner[invisibleAddress] = nil
                    end
                end
            end
        end)
        if not okAll then
            print(MOD_TAG .. " teardown() threw: " .. tostring(errAll))
        end
    end

    local function teardownIfKnown(Context)
        local address = addressOf(HookParam.read(Context))
        local screenState = address ~= nil and screens[address] or nil
        if screenState ~= nil then
            teardown(screenState)
            screens[address] = nil
            injected[address] = nil
        end
    end

    -- ClosePanel only hides our page. It must NOT tear down: it fires BEFORE ApplySettings, and
    -- teardown destroys the row widgets whose native setters are the only way a committed value
    -- reaches a consumer mod's own Lua VM. Tearing down here left every consumer un-notified until
    -- its next boot -- a rebound key kept firing the old shortcut for the rest of the session.
    local closeOk, closeErr = pcall(function()
        RegisterHook(OPTION_SETTINGS_CLASS .. ":ClosePanel", function(Context)
            local screenState = screens[addressOf(HookParam.read(Context))]
            if screenState ~= nil then
                showVanilla(screenState)
            end
        end)
    end)
    if not closeOk then
        print(MOD_TAG .. " Failed to hook OptionSettings ClosePanel: " .. tostring(closeErr))
    end

    -- Destruct is where teardown actually happens, by which point Apply has been answered.
    local destructOk, destructErr = pcall(function()
        RegisterHook(OPTION_SETTINGS_CLASS .. ":Destruct", teardownIfKnown)
    end)
    if not destructOk then
        print(MOD_TAG .. " Failed to hook OptionSettings Destruct: " .. tostring(destructErr))
    end
end

function inject(instance)
    local address = addressOf(instance)
    if address == nil or injected[address] then
        return true
    end
    installHooks()

    local anchorButton = nil
    pcall(function() anchorButton = instance.WBP_OptionSettings_MenuButton_Graphic end)
    if anchorButton == nil or not anchorButton:IsValid() then
        return false
    end

    local buttonContainer = nil
    pcall(function() buttonContainer = anchorButton:GetParent() end)
    if buttonContainer == nil or not buttonContainer:IsValid() then
        return false
    end

    local realList = nil
    pcall(function() realList = instance.WBP_PalCommonScrollList end)
    if realList == nil or not realList:IsValid() then
        return false
    end

    local ourButton = Widgets.createUserWidget(instance, MENU_BUTTON_CLASS, MENU_BUTTON_ASSET)
    if ourButton == nil then
        return false
    end
    relabel(ourButton)

    local addedVia = nil
    if pcall(function() buttonContainer:AddChildToHorizontalBox(ourButton) end) then
        addedVia = "AddChildToHorizontalBox"
    elseif pcall(function() buttonContainer:AddChildToVerticalBox(ourButton) end) then
        addedVia = "AddChildToVerticalBox"
    elseif pcall(function() buttonContainer:AddChild(ourButton) end) then
        addedVia = "AddChild (generic fallback)"
    end
    if addedVia == nil then
        pcall(function() ourButton:RemoveFromParent() end)
        return false
    end
    relabel(ourButton)   -- again, in case attaching to the live tree triggered a resync

    screens[address] = buildScreenState(instance, ourButton)
    injected[address] = true
    Dev.log("injected the Mod Options category button via " .. addedVia)
    return true
end

local function queueInjection(instance, attempt)
    local address = addressOf(instance)
    if address == nil then
        return
    end
    attempt = attempt or 0
    local epoch = (epochs[address] or 0) + 1
    epochs[address] = epoch
    ExecuteInGameThreadWithDelay(attempt == 0 and 50 or 200, function()
        if epochs[address] ~= epoch then
            return
        end
        if addressOf(instance) == nil then
            return
        end
        if not inject(instance) and attempt < 4 then
            queueInjection(instance, attempt + 1)
        end
    end)
end

function InjectOptions.install()
    pcall(function()
        NotifyOnNewObject(OPTION_SETTINGS_CLASS, function(instance)
            -- Hooks are registered synchronously here, not only inside the delayed inject() below: an
            -- instance has just been constructed so the class is definitely loaded, and registering
            -- now puts the OnSetup/OpenPanel hooks in place in time to catch this same instance's own
            -- firing. queueInjection's retries remain as a fallback.
            installHooks()
            queueInjection(instance)
            return false
        end)
    end)
end

return InjectOptions
