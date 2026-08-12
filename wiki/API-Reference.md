# API Reference

Everything a consumer mod touches lives in `mod_options_client.lua`. There are four calls and one
table.

## `ModOptionsClient.new(schema)`

Creates a client. Returns the client; never fails and never errors, whether or not the framework is
installed.

```lua
local client = ModOptionsClient.new(SCHEMA)
```

By the time it returns, `client.values` is fully populated: schema defaults first, then the player's
persisted values layered on top if a config file exists. **This happens synchronously**, so your
values are correct on the next line - before any menu has been opened, and regardless of `mods.txt`
order.

## `client.values`

A plain table of `key -> value`, always current. Read it directly:

```lua
if client.values.Enabled then
    doTheThing(client.values.Strength)
end
```

Read it at the point of use rather than caching a copy at boot. The framework mutates this same table
in place when the player applies a change, so anything holding the table reference stays current, but
a copied scalar does not.

Display-only options (`section`, `warning`, `image`) have no entry here.

## `client:register()`

Publishes the schema so it gets a tab. Returns `true`, or `false` if the schema could not be encoded.

```lua
client:register()   -- safe no-op if the framework is not installed
```

Call once at boot. The framework picks the registration up the next time its panel is built, so a
mod that loads after it is still fine.

## `client:subscribe(callback)`

Registers a change callback. Safe to call more than once; each callback is added independently.

```lua
client:subscribe(function(key, value, source)
    -- key    the option key that changed
    -- value  its new value, already written to client.values
    -- source "apply" or "api"
    applySettings()
end)
```

| `source` | Meaning |
|---|---|
| `"apply"` | The player changed it in the panel and pressed Apply. Fires **once per changed key**. |
| `"api"` | Your own code called `client:set()`. |

There is no `"disk"` source. Persisted values are already in `client.values` before you could
register a callback, so a boot-time event would always arrive too late to be useful - read
`client.values` at boot instead.

`subscribe` is also what installs the hooks that keep `client.values` current, so call it even if you
read values at press time rather than reacting to changes.

An error thrown inside your callback is caught and logged; it will not break other subscribers or the
panel.

## `client:set(key, value)`

Changes a value from your own code, without the player opening the panel.

```lua
client:set("Enabled", false)
```

Updates `client.values` and fires your subscribers with `source = "api"`. Does nothing if the value
is unchanged.

**It does not persist.** The framework owns the config file, and a consumer writing it directly would
race the framework's own save on Apply. Use this for runtime state you want your own subscribers to
react to, not as a way to save settings.

## Why changes are batched to Apply

This mirrors vanilla. Palworld's own settings pages cache pending values and commit them on Apply,
with a confirmation step - so your callback fires once per changed key at Apply, not on every click
of a switch or every pixel of a slider drag.

Leaving the screen behaves the same way as it does for the game's own settings: changing one of your
options raises the screen's changed flag, so pressing Escape or Tab brings up the "apply changed
settings?" prompt rather than closing silently. Answering yes commits and fires your callbacks;
answering no discards. Reopening the panel always reseeds from the last committed values.

If a feature genuinely needs to react to every intermediate value during a drag, this framework is
not the right fit for that one option.

## Where values are stored

```
<UE4SS Mods folder>/NativeModOptions/<your id>.ini
```

One `key=json_value` line per option, sorted. Deleting the file resets that mod to its schema
defaults.

The file lives in the framework's **mod root**, deliberately not inside its `Scripts/` folder: UE4SS
watches `Scripts` directories and hot-reloads a mod when anything there is written, so saving into it
would restart the framework after every Apply.

## Threading

Your callback runs on the game thread, so UObject calls from it are safe.

If you register a UE4SS keybind of your own, note that `RegisterKeyBind` callbacks run on UE4SS's
thread, **not** the game thread - queue UObject work with `ExecuteInGameThread` from there. See
[Keybinds](Keybinds).
