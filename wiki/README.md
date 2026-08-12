# wiki/

Source for the GitHub wiki at <https://github.com/tlechien/Palworld-Undepresso-NativeModOptions/wiki>.

The wiki is a separate git repository from the code, so these pages are kept here and pushed to it.
Filenames map to page titles with hyphens becoming spaces: `Quick-Start.md` is the page **Quick
Start**, and links between pages use the filename without the extension - `[Quick Start](Quick-Start)`.
`Home.md` is the landing page and `_Sidebar.md` renders on every page.

## Publishing

The wiki repo exists once you have created the first page through the GitHub UI. After that:

```bash
git clone https://github.com/tlechien/Palworld-Undepresso-NativeModOptions.wiki.git
cp NativeModOptions/wiki/*.md NativeModOptions.wiki/
cd NativeModOptions.wiki && git add . && git commit -m "Update wiki" && git push
```

## Keeping it honest

These pages document behaviour, not intent. When the code changes, the pages that describe it are:

| Page | Depends on |
|---|---|
| Schema Reference | `registry.lua` validation rules, the row modules' supported types |
| API Reference | `mod_options_client.lua` public surface, `persistence.lua` file location |
| Keybinds | `row_keybind.lua` capture set and modifiers, `key_config.lua` conflict rules |
| Troubleshooting | the log messages the framework actually prints |

These pages are the only schema and API reference. There used to be a second copy in
`docs/INTEGRATION.md`; it was deleted rather than kept in sync.
