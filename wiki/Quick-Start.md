# Quick Start

Working settings in five minutes.

## 1. Vendor the two files

Copy these from Native Mod Options' `Scripts/` folder into your own mod's `Scripts/`:

```
mod_options_client.lua
json.lua
```

UE4SS mods each run in their own Lua VM and cannot `require()` another mod's files, so both are
copied per mod rather than shared. This is the same thing you already do with `json.lua` between
projects.

## 2. Declare a schema and register it

In your `main.lua`:

```lua
local ModOptionsClient = require("mod_options_client")

local SCHEMA = {
    id = "YourMod",            -- unique across every installed mod; also your config filename
    title = "Your Mod",        -- the tab caption players see
    options = {
        { key = "sec_main", type = "section", label = "General" },

        {
            key = "Enabled",
            type = "boolean",
            label = "Enable the thing",
            description = "One short line, shown under the label.",
            default = true,
        },
        {
            key = "Strength",
            type = "number",
            label = "Strength",
            default = 0.5,
            min = 0,           -- required for number
            max = 1,
        },
    },
}

local client = ModOptionsClient.new(SCHEMA)
client:register()
```

## 3. Read values, and react to changes

```lua
-- Correct from your first frame, including the player's saved values. Read it anywhere.
if client.values.Enabled then
    doTheThing(client.values.Strength)
end

-- Fires once per changed key when the player presses Apply.
client:subscribe(function(key, value, source)
    applySettings()
end)
```

`client.values` is the single source of truth. Read it at press time rather than caching a copy, and
a rebind or a toggle takes effect without any extra plumbing.

## 4. Test it

1. Deploy your mod and Native Mod Options into the UE4SS `Mods` folder, both enabled in `mods.txt`.
2. Launch, open **Options → Mod Options**, and find your tab.
3. Change something, press **Escape**, and confirm the prompt. Reopen to see it stuck.

`UE4SS.log` should contain a line like:

```
[NativeModOptions] Registered 'YourMod' (3 options)
```

If it does not, your schema was rejected - see [Troubleshooting](Troubleshooting).

## A complete working example

[`examples/Demo`](https://github.com/tlechien/Palworld-Undepresso-NativeModOptions/tree/main/examples/Demo) is a runnable
mod whose schema uses every option type and modifier, one of each, with a comment on each saying what
it renders as. Copy it, change the `id` and `title`, and replace the options.

## Rules worth knowing up front

- **`id` must be unique** across all installed mods. It is also the name of the file your values are
  persisted to, so changing it later orphans the old file and resets everyone's settings.
- **`key` must be unique within your schema**, including display-only entries. Both `id` and `key`
  must match `^[A-Za-z0-9_.-]+$`.
- **Keep `description` to one short line.** Long strings clip in the native row layout.
- **Nothing commits until Apply.** See [API Reference](API-Reference) for why that is deliberate.
