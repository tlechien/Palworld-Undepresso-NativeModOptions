-- Demo -- a complete, runnable example of a mod that registers options with Native Mod Options.
-- Copy this folder, rename it, and replace the schema with your own.
--
-- The schema below is a live catalogue: every option type and every row modifier the framework
-- supports appears exactly once, with a comment saying what it renders as. Reading it top to bottom
-- is the fastest way to see what is available; running it shows you.
--
-- To run it as-is:
--   1. Copy this folder into your UE4SS Mods folder.
--   2. Copy mod_options_client.lua and json.lua from NativeModOptions/Scripts/ into its Scripts/.
--      UE4SS mods cannot require() each other's files, so both are vendored per mod.
--   3. Add "Demo : 1" to mods.txt, above the Keybinds line.
--   4. Launch, then open Options -> Mod Options.
--
-- It also serves as the framework's own end-to-end check, which is why some rows are deliberately
-- set up to collide: registration crosses the Lua VM boundary, every row type renders with the
-- game's own widgets, values are correct at this mod's boot before any menu has been opened, and
-- subscribe() fires once per changed key on Apply with no polling anywhere.
--
-- See the wiki for the full schema reference.
local ModOptionsClient = require("mod_options_client")

local MOD_TAG = "[Demo]"

local SCHEMA = {
    -- `id` is also the name of the config file the framework persists to, so it must be unique
    -- across every installed mod. Changing it later orphans the old file and resets the values.
    id = "Demo",
    title = "UndepressedDemo",
    options = {
        -- type "warning": a display-only caution line, like the amber note vanilla shows under the
        -- Language row. Wrapping is automatic; a literal newline forces a break.
        --
        -- First in the list on purpose: a multi-line block at the top is where a wrapping or
        -- row-height mistake shows up most clearly, because everything below it shifts.
        { key = "warn_multiline", type = "warning",
          label = "This caution line is three lines long: the first runs on far enough to show "
              .. "that wrapping is automatic.\n"
              .. "The second follows an explicit line break.\n"
              .. "So does the third, which is there to bring it to 3 lines and show the centered "
              .. "cute little warning." },

        -- type "section": a display-only header, using the same text widget vanilla heads its own
        -- groups with.
        { key = "sec_controls", type = "section", label = "Value rows" },

        { key = "EnableThing", type = "boolean", label = "Boolean (switch)",
          description = "Renders as the native ON/OFF switch.", default = false },

        { key = "Strength", type = "number", label = "Number (slider)",
          description = "Renders as the native slider.", default = 0.5, min = 0, max = 1 },

        { key = "Mode", type = "enum", label = "Enum (left/right selector)",
          description = "Renders as the native left/right selector.",
          choices = {
              { value = "off", label = "Off" },
              { value = "balanced", label = "Balanced" },
              { value = "max", label = "Max" },
          },
          default = "balanced" },

        -- Modifiers, valid on any value row. Both are native calls on the row frame, so they look
        -- exactly like vanilla's own.
        { key = "sec_modifiers", type = "section", label = "Row modifiers" },

        { key = "WarnedToggle", type = "boolean", label = "Boolean with warning",
          description = "warning = true -- draws the row's native warning state.",
          default = true, warning = true },

        { key = "DisabledToggle", type = "boolean", label = "Boolean, disabled",
          description = "disabled = true -- the row shows its value but cannot be changed.",
          default = true, disabled = true },

        { key = "DisabledSlider", type = "number", label = "Number, disabled",
          description = "disabled = true on a slider.",
          default = 0.25, min = 0, max = 1, disabled = true },

        -- The single-line case, for comparison with the wrapped block at the top.
        { key = "warn_demo", type = "warning",
          label = "This is a warning line. Use it for caveats that need to stand out." },

        -- type "keybind": click the row, then press a key. Uses the row's own key-config control,
        -- with the bound key drawn in the native key icon. A modifier cannot be drawn in that icon --
        -- the game has no artwork for a chord -- so it is named beside it instead.
        { key = "sec_keybind", type = "section", label = "Keybinds" },

        -- Five rows, each on a different branch of the conflict check, so one look at this section
        -- says whether conflict reporting still works rather than only whether a key binds.
        --
        -- A bare key the GAME already uses: "I" is Inventory, so this row names it.
        { key = "HotKey", type = "keybind", label = "Hotkey",
          description = "Click the row, then press a key.", default = "I" },

        -- The same base key WITH a modifier, which must NOT report the clash above: the game's
        -- binding tables hold bare keys only. It reports Palbox IVs instead, which also uses Ctrl+I.
        { key = "HotKeyCtrl", type = "keybind", label = "Hotkey with Ctrl",
          description = "Shares Ctrl+I with Palbox IVs, so it should report that mod.",
          default = "I", modifiers = { "Ctrl" } },

        -- Alt rather than Ctrl, on a key nothing claims: the quiet case, no warning at all.
        { key = "HotKeyAlt", type = "keybind", label = "Hotkey with Alt",
          description = "Alt + a free key -- expect no conflict.",
          default = "K", modifiers = { "Alt" } },

        -- A second bare key the game uses, to show the caption naming a different action.
        { key = "HotKeyGameClash", type = "keybind", label = "Hotkey clashing with the game",
          description = "Q is Throw Pal Sphere.", default = "Q" },

        -- Two rows in the SAME schema can collide too: conflict detection is per option, not per mod,
        -- so rebinding this to Alt+K makes it and the Alt row above name each other.
        { key = "HotKeyFree", type = "keybind", label = "Hotkey on a free key",
          description = "F9 is unbound; rebind it to Alt+K to see a same-mod conflict.",
          default = "F9" },

        -- type "image": a display-only picture.
        { key = "sec_image", type = "section", label = "Image" },

        -- A full OBJECT path: "Pal/Content/..." is "/Game/...", with the asset name repeated after a
        -- dot to name the object inside the package. The package-path form does not load.
        { key = "DemoImage", type = "image",
          texture = "/Game/Pal/Texture/PalIcon/SKin/T_NegativeKoala_Skin001_icon_normal.T_NegativeKoala_Skin001_icon_normal",
          width = 128, height = 128 },
    },
}

local client = ModOptionsClient.new(SCHEMA)
client:register()

client:subscribe(function(key, value, source)
    print(MOD_TAG .. " changed: " .. key .. " = " .. tostring(value) .. " (source=" .. source .. ")")
end)

-- Printed at boot, before any menu has been opened: these already reflect whatever was last applied
-- and persisted, not the schema defaults.
print(MOD_TAG .. " boot values: EnableThing=" .. tostring(client.values.EnableThing)
    .. " Strength=" .. tostring(client.values.Strength)
    .. " Mode=" .. tostring(client.values.Mode))
print(MOD_TAG .. " loaded -- open Options -> Mod Options")
