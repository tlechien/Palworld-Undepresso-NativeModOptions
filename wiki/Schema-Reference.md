# Schema Reference

A schema is a plain Lua table. It is validated when registered; a schema that fails validation is
rejected whole, with the reason logged.

```lua
local SCHEMA = {
    id = "YourMod",
    title = "Your Mod",
    options = { ... },
}
```

| Field | Type | Notes |
|---|---|---|
| `id` | string | **Required.** Unique across all installed mods, `^[A-Za-z0-9_.-]+$`. Also the config filename. |
| `title` | string | **Required.** The tab caption. |
| `options` | array | **Required.** Entries in display order. |

## Option types

| `type` | Renders as | Carries a value |
|---|---|---|
| `boolean` | the native ON/OFF switch | yes |
| `number` | the native slider | yes |
| `enum` | the native left/right selector | yes |
| `keybind` | the native key-config control, with the key drawn in the key glyph | yes |
| `section` | a group heading | no |
| `warning` | an amber caution line with the warning icon | no |
| `image` | a picture at a given size | no |

Display-only types (`section`, `warning`, `image`) are laid out but never staged, applied, persisted
or broadcast, and get no entry in `client.values` - so nothing downstream has to special-case a key
with no state. They still need a unique `key`.

There is no `text` type: the options UI has no native row widget for free text entry.

## Option fields

| Field | Applies to | Notes |
|---|---|---|
| `key` | all | **Required.** Unique within your schema. `^[A-Za-z0-9_.-]+$`. |
| `type` | all | **Required.** One of the types above. |
| `label` | all | Row title. For `section` and `warning` it is the displayed text and is **required**. |
| `description` | value types | One short line under the label. Long strings clip. |
| `default` | value types | Type-matched. |
| `min`, `max` | `number` | **Required.** The native slider has no unbounded mode. |
| `choices` | `enum` | **Required**, non-empty array of `{ value, label }`. `value` is what your code sees. |
| `texture` | `image` | **Required.** Full object path - see below. |
| `width`, `height` | `image` | Displayed size in pixels. |
| `warning` | value types | `true` draws the row's native warning highlight. |
| `disabled` | value types | `true` shows the value but blocks interaction. |
| `style` | `section`, `warning` | Optional `CommonTextStyle` class path. Omit to match vanilla, which applies none. |
| `modifiers` | `keybind` | **Discouraged** - see [Keybinds](Keybinds). |

## Examples per type

```lua
-- boolean
{ key = "Enabled", type = "boolean", label = "Enable the thing", default = true },

-- number: min and max are required
{ key = "Strength", type = "number", label = "Strength", default = 0.5, min = 0, max = 1 },

-- enum: default must equal one of the choice values
{ key = "Mode", type = "enum", label = "Mode",
  choices = {
      { value = "off",      label = "Off" },
      { value = "balanced", label = "Balanced" },
      { value = "max",      label = "Max" },
  },
  default = "balanced" },

-- keybind: the stored value may be a bare key or a chord
{ key = "ToggleKey", type = "keybind", label = "Toggle key", default = "Ctrl+I" },

-- section: a heading
{ key = "sec_extras", type = "section", label = "Extras" },

-- warning: wraps automatically, \n forces a break
{ key = "warn_extras", type = "warning",
  label = "An amber caution line.\nThis sentence follows an explicit break." },

-- image: full OBJECT path, asset name repeated after a dot
{ key = "pic_extras", type = "image",
  texture = "/Game/Pal/Texture/UI/Something/T_Thing.T_Thing",
  width = 128, height = 128 },
```

### Row modifiers

`warning` and `disabled` apply to any value row and are native calls on the row frame, so they look
exactly like the game's own:

```lua
{ key = "Risky", type = "boolean", label = "Risky option", default = false, warning = true },
{ key = "NotYet", type = "boolean", label = "Not implemented", default = true, disabled = true },
```

Prefer `disabled = true` over hiding a feature you have not finished - a visibly unavailable setting
reads as deliberate, a toggle that silently does nothing does not.

### Texture paths

`texture` takes a full **object** path: the package path with the asset name repeated after a dot.

```
correct    /Game/Pal/Texture/UI/Something/T_Thing.T_Thing
wrong      /Game/Pal/Texture/UI/Something/T_Thing
```

The package-path form does not load, and a not-yet-loaded texture then looks identical to a bad path.

## Validation

The whole schema is rejected if any of these fail, and the reason is logged with the `[NativeModOptions]`
tag:

- `id` missing or not matching `^[A-Za-z0-9_.-]+$`
- `title` missing or empty
- `options` missing
- an option `key` missing, malformed, or duplicated within the schema
- an unsupported `type`
- `section` or `warning` without a `label`
- `image` without a `texture`
- `number` without numeric `min` and `max`
- `enum` without a non-empty `choices` array, a choice missing `value`/`label`, or a `default` that
  matches no choice value
- `keybind` `modifiers` that is not an array of strings

A rejected schema produces no tab at all. If yours does not appear, check the log first.
