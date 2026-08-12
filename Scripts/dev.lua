-- Developer logging switch.
--
-- Ships false. Flip it to true while working on the framework: UE4SS's EnableAutoReloadingLuaMods
-- watches this directory, so saving the file is enough to reload the mod with dev logging on.
--
-- What belongs behind Dev.log: success chatter, internal accounting, and anything that prints a
-- variable's value to answer "did this path run". What does NOT: a failure that leaves the player
-- looking at a broken panel. Those print unconditionally -- a bug report is worth nothing if the
-- line explaining it was gated off.
--
-- Deliberately not Info.json's DebugMode. That flag belongs to the Palworld Mod Uploader, and
-- neither InstallRule nor tools/deploy-to-game.ps1 puts Info.json anywhere Lua could read it: both
-- ship Scripts/ and nothing else.
local Dev = {}

Dev.enabled = false

local MOD_TAG = "[NativeModOptions]"

function Dev.log(message)
    if Dev.enabled then
        print(MOD_TAG .. " DEV " .. message)
    end
end

return Dev
