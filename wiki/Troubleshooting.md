# Troubleshooting

Almost everything here is answered by `UE4SS.log`. Search it for `[NativeModOptions]` and for your
own mod's tag.

## My tab does not appear

**Check the log for a registration line:**

```
[NativeModOptions] Registered 'YourMod' (5 options)
```

If instead you see `Rejected schema 'YourMod': ...`, the message names the exact problem - a
duplicate key, a `number` without `min`/`max`, an `enum` whose `default` matches no choice, and so
on. A schema is rejected whole, so one bad option removes the entire tab. See
[Schema Reference](Schema-Reference#validation).

If there is **no line at all**, your `register()` never ran. Check that your mod loaded (its own boot
print), that `mods.txt` has it enabled, and that `mod_options_client.lua` and `json.lua` are both in
your `Scripts/` folder.

**If no "Mod Options" category appears at all**, the framework itself is not loading. Look for
`[NativeModOptions] loaded` and `Injected Mod Options category button`.

## Mod Options vanished after I saved

You are on an old build. Saving used to write into the framework's `Scripts/` folder, which UE4SS
watches - the write hot-reloaded the framework, orphaning the injected button. Fixed by moving the
config to the mod root. Update Native Mod Options.

## My settings do not persist

Check the file:

```
<UE4SS Mods folder>/NativeModOptions/<your id>.ini
```

- **File missing entirely** - nothing was ever committed. Changes only save when you press Apply, or
  answer yes to the prompt on leaving.
- **File exists but your key is absent** - display-only types (`section`, `warning`, `image`) are
  never persisted, and neither is anything set with `client:set()`.
- **Values reset every launch** - Native Mod Options is not installed. That is by design: without it
  your schema defaults apply. It is an optional dependency.

Never write to that file yourself; the framework owns it and will overwrite you on the next Apply.

## My callback never fires

- `subscribe` must be called for the hooks to be installed at all. Call it even if you read
  `client.values` at press time.
- It fires on **Apply**, not on each click. Change something and press Apply or confirm the prompt on
  the way out.
- It fires **once per changed key**. Setting a value to what it already was is not a change.
- Errors inside your callback are caught and logged with your mod id and key - search the log for
  `subscriber error`.

## My values are wrong at boot

They should not be: `ModOptionsClient.new()` fills `client.values` from defaults and then the config
file synchronously, before it returns, and it locates the config from its own file path so `mods.txt`
order does not matter.

If you are seeing defaults where saved values should be, confirm your `id` matches the `.ini`
filename exactly - it is case-sensitive, and changing `id` orphans the old file.

## My keybind does nothing

- **`Key[value]` is nil** - the stored value may be a chord like `"Ctrl+I"`. Parse it; see
  [Keybinds](Keybinds).
- **The modifier you pressed was ignored** - your schema declares `modifiers`, which pins the
  modifier and keeps only the base key. Remove it and put the full chord in `default`.
- **It fires but nothing happens** - `RegisterKeyBind` callbacks run on UE4SS's thread, not the game
  thread. Wrap UObject work in `ExecuteInGameThread`.
- **It fires twice, or the old key still works** - UE4SS cannot unregister a bind. Gate the handler
  on the current value, and restart the game to clear stale registrations.

## Something worked, then broke after I edited a file

UE4SS auto-reloads a mod when any file in its `Scripts/` folder changes. A reload resets that mod's
Lua state while previously-registered hooks stay resident pointing at the old closures - so behaviour
gets strange in ways that do not look like a reload. **Restart the game** rather than trusting a
hot reload when you are diagnosing anything.

## The panel looks wrong

- **Descriptions clipping or overlapping** - keep them to one short line.
- **A row shows `None`** - its label never applied. For an `enum`, it usually means the choice list
  did not survive as an array of `{ value, label }` tables.
- **An image does not render** - `texture` needs a full object path with the asset name repeated
  after a dot (`/Game/.../T_Thing.T_Thing`). The package-path form does not load.

## Reporting a bug

Include the `[NativeModOptions]` lines from `UE4SS.log`, your schema, and which of the two entry
points you used (title menu or in-game ESC menu). Issues:
<https://github.com/tlechien/Palworld-Undepresso-NativeModOptions/issues>
