# Better Mod Manager: file mode also runs for a mod registered through `modconfig.lua`

A report for Better Mod Manager's author from the developer of Lootable Passives, a Palworld Workshop mod. It records what was observed while integrating the mod with Better Mod Manager's settings library. Everything below was seen on one Windows machine on 2026-10-19; the code references are to the installed copy of Better Mod Manager named under "Versions".

## Summary

Lootable Passives registers its settings through `BetterModManager/Scripts/modconfig.lua`, and its page works as documented. Better Mod Manager's file mode also runs over the same mod at every game start, because the mod is listed in `mods.txt` and has a `Scripts/config.lua`. File mode keeps its own store for the mod and can rewrite that `config.lua`, which then disagrees with the value the registered page saved. Each rewrite also leaves a `config.lua.bak` in the mod's installed `Scripts` folder.

The registered page itself behaved correctly throughout. The issue is only the second, file-mode path running alongside it.

## Versions

| Component | Version |
| --- | --- |
| Better Mod Manager | 0.2.11 (Workshop 3803996980) |
| UE4SS Experimental (Palworld) | the Workshop release current on 2026-10-19 (Workshop 3625223587) |
| PalSchema | 0.6.7 |
| Lootable Passives | dev builds 1.2.10 to 1.2.14, ahead of release 1.3.0 |

## How Lootable Passives integrates

- **Load and register.** At load, before reading any setting, the mod calls `loadfile` on `BetterModManager/Scripts/modconfig.lua` and, when it loads, `register` with: `id = "LootablePassives"`, `name`, `description`, `folder` (the mod's folder, the parent of `Scripts`), `options`, and `onChange`. There is no `enabledKey`, so no mod-list checkbox, and no `config` table.
- **Options.** Six `toggle` options, each with an explicit `default`, plus `header` rows. One option uses `dependsOn`.
- **Changes in both directions.** `onChange` applies a change and writes that one value into the mod's own installed `Scripts/config.lua`, replacing only the value on that key's line, so the file always shows the current settings. A change the mod makes itself goes through the handle's `set`.
- **Startup reconciliation.** After registering, the mod compares the two sources. A value in `handle.values` that differs from its registered default wins and is written into `config.lua`. Otherwise a `config.lua` value that differs from the default is handed to `set`.
- **Why the file exists at all.** `Scripts/config.lua` is the mod's only settings source when Better Mod Manager is not installed, and on dedicated servers, where nothing has a UI. It is a plain `return { key = true, ... }` table with one comment per line.

## What was observed

### 1. File mode runs for the registered mod at every start

`menu.lua`'s `findExternalMods` (line 309) lists every mod named in `mods.txt` that has a `Scripts/main.lua`, registered or not. `filemods.repair` (`filemods.lua` line 903) then calls `locate` (line 400) on each. `locate` finds `Scripts/config.lua`, the first entry of `LUA_FILES` (line 3), and `reconcile` (line 514) compares it with the store `%LOCALAPPDATA%\Pal\Saved\Config\ModConfig.file.LootablePassives.lua`. When the two differ in the way `reconcile` acts on, it rewrites the file through `core.writeAtomic`.

Better Mod Manager also created `BetterModManager.profile.LootablePassives.lua` for the mod, the per-mod override listing it writes for file mods. Its header says it was "built from its file Scripts/settings.lua", the file name an earlier version of the mod used.

### 2. A rewrite overrode the value the registered page had saved

The mod's debug option is registered with the build's own value as its default: `true` in a development build, `false` in a release. During testing:

1. On the registered page, debug was turned off. Better Mod Manager saved `{["debug"]=false}` in `ModConfig.LootablePassives.lua`, and the mod wrote `debug = false` into `config.lua`.
2. At the next game start (a development build, so the mod's files were reinstalled with `debug = true`), the mod's own reconciliation wrote `debug = false` back into `config.lua`, since the saved value wins.
3. In the same start, file mode's store held `values = { debug = "true", ... }`, recorded from earlier development builds, with `defaults = { debug = "false" }`. `reconcile` took the branch where the file's value equals the stored default and the stored value differs, and wrote `debug = true` into `config.lua`. The previous file, with `debug = false`, was left as `config.lua.bak`.

After that start, `config.lua` said `true` while the setting in effect, and the registered page, said `false`.

### 3. On a version update, file mode restores its stored values into the new `config.lua`

`reconcile` treats a changed `Info.json` version as an update and restores the stored values into the freshly installed file. For a player this mostly agrees with the registered page, since both keep the player's own changes. On a machine that has run development builds, though, the store holds `debug = "true"`, and the first release install gets `debug = true` written into its `config.lua`. Better Mod Manager is the only writer of that value there.

### 4. `.bak` files are left in the mod's installed folder

`core.writeAtomic` keeps the previous file as `<path>.bak`. For a mod installed by Palworld's official mod loader, that is a file in the mod's install folder that is not in the loader's `InstallManifest.json`. The loader's reinstall and uninstall only remove what the manifest lists, so these files stay behind indefinitely. Seen: `Scripts/config.lua.bak`, and `Scripts/settings.lua.bak` from the earlier file name, still present after many reinstalls.

### 5. A disabled mod is shown as inactive, and file mode still manages its file

After the mod was disabled under Options → Mod Management, Better Mod Manager listed it as inactive, which is right. Its `config.lua` was still rewritten while the game ran, with a new `.bak`, and the file-mode store was recreated. That is reasonable for a mod that is not running. It is listed here only because it shows the same file is managed whichever path is active.

## Steps to reproduce

1. Install a Lua mod that registers through `modconfig.lua` and also ships a plain-table `Scripts/config.lua` with the same keys.
2. Start the game once so file mode creates its store, then change a value on the registered page.
3. Change the same key's line in `config.lua` back by hand, or reinstall the mod, then restart.
4. Compare `config.lua`, `config.lua.bak`, `ModConfig.<id>.lua` and `ModConfig.file.<id>.lua`.

## Possible fixes

Any one of these would remove the overlap for mods that register:

- **Skip file mode for registered ids.** `ModConfig.register` could record the id, and `filemods.repair` and the file pages could skip it. Load order may put `repair` before the mod's own `register` call, so the check might need to happen later, or on the next start.
- **A documented opt-out.** `locate` already returns nil when `Scripts/shared.hash` exists. A documented marker, or a registration field such as `fileMode = false`, would let a mod opt out explicitly. Lootable Passives has not used `shared.hash`, since its meaning is undocumented.
- **No `.bak` beside another mod's files.** Keeping the backup in Better Mod Manager's own config folder would leave nothing outside the loader's manifest.

## What Lootable Passives does meanwhile

Nothing in the mod works around this. On the development machine, the file-mode store, the profile and the two `.bak` files were deleted by hand. The mod's release checklist includes checking that a release install starts with debug off.

Thank you for Better Mod Manager. The registered-page integration was straightforward, and the explicit `default` and `set` behavior is documented well enough to build a two-way sync on.
