# Examples

Runnable reference mods, **for developers only**. Nothing here reaches a player: `InstallRule`
installs `Scripts/` and nothing else, and each example is a separate mod needing its own `mods.txt`
entry.

## Demo

A consumer mod whose schema is a live catalogue: every option type and row modifier exactly once,
each commented with what it renders as. The fastest way to see what is available.

### Running it

1. Copy `Demo/` into your UE4SS `Mods` folder. The folder name is yours.
2. Copy `mod_options_client.lua` and `json.lua` from `NativeModOptions/Scripts/` into its
   `Scripts/`. UE4SS mods cannot `require()` each other's files, so both are vendored per mod. Your
   own mod does the same.
3. Add `Demo : 1` to `mods.txt`, above the `Keybinds` line, which must stay last.
4. Launch, then Options, Mod Options.

It deliberately has no `Info.json`, so the Palworld Mod Uploader cannot publish it by accident.

### Writing your own

Copy `main.lua`, change `id` and `title`, replace the options. `id` must be unique across every
installed mod: it is also the config filename. See the wiki for the full schema reference.

### What it also verifies

Some rows collide on purpose, so the Keybinds section reports one of each conflict kind: a bare key
the game uses, a chord that must *not* report that clash, a chord shared with another mod, and a
free key. Running it also exercises what a single in-process schema cannot: registration crossing
the Lua VM boundary, values correct at the consumer's own boot, and `subscribe()` firing once per
changed key on Apply.
