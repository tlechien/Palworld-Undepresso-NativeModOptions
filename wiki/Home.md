# Native Mod Options

A settings screen for your Palworld UE4SS mod, built from **Palworld's own options widgets** - not a
hand-drawn UI. Your mod declares a schema; players find it under **Options → Mod Options**, on both
the title menu and the in-game ESC menu.

```lua
local ModOptionsClient = require("mod_options_client")

local client = ModOptionsClient.new({
    id = "YourMod",
    title = "Your Mod",
    options = {
        { key = "Enabled", type = "boolean", label = "Enable the thing", default = true },
    },
})
client:register()
client:subscribe(function(key, value) print(key, value) end)
```

That is the whole integration. No polling loop, no UI code, no dependency to declare.

## Start here

| Page | What it covers |
|---|---|
| **[Quick Start](Quick-Start)** | Working settings in five minutes |
| **[Schema Reference](Schema-Reference)** | Every option type and field |
| **[API Reference](API-Reference)** | `ModOptionsClient` methods and the change callback |
| **[Keybinds](Keybinds)** | Chord format, registering the shortcut, conflict reporting |
| **[Troubleshooting](Troubleshooting)** | It didn't appear / didn't save / didn't fire |

## What you get

- **The game's real widgets**, so your settings look and behave like the game's own.
- **Its own tab** per registered mod, paged with the same Q/E keys the Controls page uses.
- **Vanilla Apply semantics**, including the confirmation prompt on leaving with unsaved changes.
- **Persistence handled for you**, correct from your mod's first frame.
- **No timers, no polling.** Delivered by event, once per changed key.

## What it will not do

Up front, so you can rule it out early rather than halfway through.

- **No free text entry.** There is no native row widget for it, so no `text` type.
- **No reacting to a slider mid-drag.** Values commit on Apply. If one option needs every
  intermediate value, handle that one yourself.
- **Keybinds: `A` to `Z`, `F1` to `F12`, Ctrl or Alt.** No Shift. Every offered key becomes a
  permanent global bind UE4SS cannot remove.
- **Registering the shortcut is your job.** The framework stores the key; the bind belongs to the
  mod that acts on it.
- **A mod that registers late appears next time the panel opens.**

## It is an optional dependency

Without it installed, `client.values` holds your schema defaults, `register()` and `subscribe()`
no-op, and nothing errors. So do not gate features on it, and pick defaults that stand on their own,
because persistence is the one thing lost.

Declare it with **Add Required Item** on your Workshop page, not in `Info.json`'s `Dependencies`,
which does not propagate.

Load order does not matter: the client finds its config directory from its own path.

## Mods already using it

Worth reading if you want a real integration rather than a snippet.

- **Palbox IVs**, a chord keybind default with a rebind handled live.
- **Smooth Boss Battles**, the simplest case: booleans, sections, and a warning row.
- **Bulk Storage**, a keybind plus a boolean that changes behaviour.

`examples/Demo` shows every option type at once, with a comment on each saying what it renders as.
