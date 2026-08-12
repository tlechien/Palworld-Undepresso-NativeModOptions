-- Native Mod Options -- entry point.
--
-- Adds a "Mod Options" category to the game's own WBP_OptionSettings_C screen, which serves both the
-- title menu and the in-game ESC menu. Consumer mods register a schema; see the wiki.
--
-- This mod registers no schema of its own.
local InjectOptions = require("inject_options")

local MOD_TAG = "[NativeModOptions]"

InjectOptions.install()

print(MOD_TAG .. " loaded -- Options -> Mod Options")
