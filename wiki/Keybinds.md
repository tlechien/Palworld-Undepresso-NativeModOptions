# Keybinds

A `keybind` row lets the player click it and press a key. The framework stores what they pressed;
**registering the shortcut is your job**, because UE4SS keybinds belong to the mod that uses them.

## The stored value

```lua
"I"        -- a bare key
"Ctrl+I"   -- a chord
"Alt+N"
```

`client.values.YourKey` is that string. Parse it before handing anything to `RegisterKeyBind`:
`Key["Ctrl+I"]` is `nil`.

## Registering it

Copy this into your mod. Both shipped consumer mods use exactly this shape.

```lua
-- "Ctrl+I" -> "I", { ModifierKey.CONTROL }.  A bare "I" -> "I", {}.
-- The framework's modifier names differ from UE4SS's, hence the mapping.
local MODIFIER_NAMES = { CTRL = "CONTROL", ALT = "ALT", SHIFT = "SHIFT" }

local function parseBinding(value)
    local parts = {}
    for part in tostring(value):gmatch("[^+]+") do
        parts[#parts + 1] = part
    end
    local baseKey = table.remove(parts)
    local modifiers = {}
    for _, name in ipairs(parts) do
        local const = ModifierKey ~= nil and ModifierKey[MODIFIER_NAMES[name:upper()] or ""] or nil
        if const == nil then
            return nil, nil, name        -- a modifier UE4SS does not expose
        end
        modifiers[#modifiers + 1] = const
    end
    return baseKey, modifiers, nil
end

-- UE4SS has no UnregisterKeyBind, so a binding cannot be replaced. Register lazily and gate on the
-- current value: a rebind adds one registration and the previous one stays resident but inert.
local registeredBindings = {}

local function ensureBindingRegistered()
    local binding = client.values.ToggleKey
    if type(binding) ~= "string" or binding == "" or registeredBindings[binding] then
        return
    end
    local baseKey, modifiers, unknownModifier = parseBinding(binding)
    if unknownModifier ~= nil then
        print("[YourMod] '" .. binding .. "' uses an unsupported modifier: " .. unknownModifier)
        return
    end
    local keyConst = Key[baseKey]
    if not keyConst then
        print("[YourMod] '" .. tostring(baseKey) .. "' is not a key UE4SS recognises")
        return
    end
    local handler = function()
        -- Re-read at press time so a rebind takes effect and the superseded bind does nothing.
        if client.values.ToggleKey ~= binding then
            return
        end
        -- This runs on UE4SS's thread, not the game thread. Queue any UObject work.
        ExecuteInGameThread(function() doTheThing() end)
    end
    -- Two-argument form for a bare key, three-argument for a chord. An empty modifier table is not
    -- the same as passing none.
    local ok
    if #modifiers > 0 then
        ok = pcall(RegisterKeyBind, keyConst, modifiers, handler)
    else
        ok = pcall(RegisterKeyBind, keyConst, handler)
    end
    if ok then
        registeredBindings[binding] = true
    end
end

ensureBindingRegistered()

client:subscribe(function(key)
    if key == "ToggleKey" then
        ensureBindingRegistered()   -- a rebind needs its own registration
    end
end)
```

## What the player can pick

- **Keys:** `A` to `Z` and `F1` to `F12`. Deliberately not the whole keyboard, because every offered
  key becomes a permanent global bind and UE4SS cannot remove one.
- **Modifiers:** `Ctrl` and `Alt`. Shift is not offered. A modifier cannot be observed on its own, so
  capture registers each key bare, with Ctrl and with Alt, and which callback fires is the only
  signal of what was held.

## Conflict reporting

The row checks the chosen key and tells the player what it collides with:

- **Against the game's own bindings**, with the readable action name - "conflicts with Inventory".
  Bare keys only. The game's binding tables hold unmodified keys, so there is no modifier to compare
  a chord against and the check has nothing to say about one.
- **Against every other registered mod**, chord included. Two mods both claiming `Ctrl+I` is
  something no amount of reading the game's key config would reveal.

The row lights up vanilla's own warning highlight and names the clash in its caption.

### A chord is not one key

The engine does not treat a combination as one thing, and keybinds do **not** consume the keypress.
`Ctrl+R` fires both `R` and `Ctrl+R`. Fine in a lot of cases, conflicting in some others.

A chord still keeps two mods off the same shortcut, and the row will report that clash. It has
nothing to say about the game's own binding on the base key.

## Do not use `modifiers`

The schema has a `modifiers` field that pins a modifier and reduces the picker to choosing a base key:

```lua
{ key = "ToggleKey", type = "keybind", default = "I", modifiers = { "Ctrl" } },   -- avoid
```

It does two unhelpful things. The picker **silently discards** the modifier the player pressed, so
choosing `Alt+N` stores `"N"` and leaves the shortcut on `Ctrl+N`. And it suppresses the conflict
check against the game's bindings, which a player choosing a bare key needs.

Put the full chord in `default` instead and parse the whole value:

```lua
{ key = "ToggleKey", type = "keybind", default = "Ctrl+I" },                       -- prefer
```

## Rebinds apply immediately

A keybind change fires your `subscribe` callback like any other option, so re-registering from there
is enough - no restart required. The framework re-reads the committed value from its config file for
this one type, because a keybind row has no native setter that carries the value as an argument.

## Rebinding leaves the old registration resident

UE4SS exposes no `UnregisterKeyBind`. The gate above handles it: the superseded bind stays loaded but
returns immediately, and registrations grow by one per distinct binding chosen in a session. That is
why you should not pre-register every possible key.
