# CLAUDE.md

Guidance for Claude Code working in this repository.

- This `CLAUDE.md` file is **durable** repo setup and development processes, plus things that will help an agent. DO NOT add ephemeral details of planning or findings based on the current repo state to this document.
- Two documents describe the mod, for two different readers, and neither is duplicated here:
  - `README.md` is the GitHub page for this **development repo**. It describes the mod and how to set it up, develop, stage and publish it from source. It does **not** ship. Update it whenever you change user-facing game functionality, the dev tools, or the publishing cycle.
  - `.docs/workshop-description.txt` is the Steam Workshop page text, in Steam's BBCode. It does **not** ship either: it is pasted into the Workshop page by hand at publish time, and that step is not automatable. Update it whenever you change user-facing game functionality, and keep its player-facing content in step with `README.md`'s.
- DO NOT TRUST COMMENTS IN CODE -- TREAT THESE AS GUESSES OR HOPES; COMMENTS MAY ALSO BE OUTDATED LEFTOVER FROM PREVIOUS CODE WHICH CAN LEAD ASTRAY IF NOT VERIFIED.

---

## What the repository is

This repo contains a Palworld mod.

### Repository layout

| Directory | Purpose | Deployability |
| --- | --- | --- |
| Scripts/ | Lua runtime (main.lua, settings.lua, lp/*.lua) | ships |
| PalSchemaMods/LootablePassives/ | JSON data patches: items, DataTable rows, English strings | ships |
| tools/ | stage.ps1, stage_test.ps1, luacheck.js, ledger_test.lua | dev only-do not ship |
| package.json | declares luaparse for tools/luacheck.js | dev only-do not ship |
| CLAUDE.md | Agent guidance | dev only-do not ship |
| README.md | GitHub page for the development repo | dev only-do not ship |
| .docs/workshop-description.txt | Steam Workshop page text, pasted by hand | dev only-do not ship |
| LICENSE | license | ships |
| Info.json | Steam Workshop package manifest | ships |
| thumbnail.png | Workshop thumbnail | ships |

- **What ships is decided by `Info.json`.** `stage.ps1` stages `Info.json`, the `Thumbnail` file, `LICENSE` when present, and every `InstallRule` `Targets` path, and nothing else. A new shipped folder is added by adding it to `Targets`; there is no list in the tools.

- **How `InstallRule.Targets` installs.** The authority is `Mods\ManagedMods\<PackageName>\InstallManifest.json`, which the loader writes on every install and which lists every file and directory it placed. Read it rather than inferring a layout. The manifests on the dev machine record these rules:
  - **Type directory and package-name folder.** `Lua` → `Mods\NativeMods\UE4SS\Mods\<PackageName>\`, and `PalSchema` → `Mods\NativeMods\UE4SS\Mods\PalSchema\mods\<PackageName>\`; both add the package-name folder. `UE4SS` → `Mods\NativeMods\UE4SS\` and `LogicMods` → `Pal\Content\Paks\LogicMods\` do **not**. `Paks` → `Pal\Content\Paks\~WorkshopMods\` is not yet recorded. `04-Tech.md`'s table shows `{PackageName}` for `Lua` only, and its prose ("the Package Name is used as the folder name") does not hold for `UE4SS` or `LogicMods`.
  - **Trailing slash.** A target with no trailing `/` (`./Scripts`) is copied as a folder under its own leaf name. A target ending in `/` (`./LogicMods/`), or `.`, has its **contents** copied. The uploader's template uses the trailing-slash form (`./PalSchema/`, `./Paks/`, `./LogicMods/`) and the folder form for `./Scripts`.
  - **A folder target whose leaf equals the `PackageName` is a bug under `Lua` or `PalSchema`**: the name doubles, as `PalSchema\mods\LootablePassives\LootablePassives\`, and PalSchema loads an empty folder without an error. `tools/stage.ps1` refuses that shape and prints the computed install path for every rule.
  - This repo names its three PalSchema folders individually, without a trailing slash, so the `PalSchemaMods/LootablePassives/` wrapper is a container and not load-bearing. A fourth kind of PalSchema data must be added to `Targets` too, or it neither ships nor installs.
- **DO NOT** Reference dev-only artifacts on things that ship as this creates a broken reference in shipped items. `README.md` and `.docs/` are dev-only for this purpose, so shipped Lua must not point at them either.

### `PalSchemaMods/LootablePassives/`

- `items/` — the 94 mod-defined disposable implants.
- `raw/` — DataTable patches. Four files, and the split matters:
  - `LootablePassivesOperation.json` — the two marker passives and their operations.
  - `LootablePassivesOperatingTable.json` — 61 routes for passives with no vanilla row.
  - `LootablePassivesVanillaPrices.json` — reprices the 54 vanilla routes. **`Price` only.** Naming `RequireItemId` here would overwrite and thereby destroy the recipe gate. The price follows whether the route **consumes** what it requires, not whether the row is vanilla: 33 recipe routes at 5000, and the 21 that spend one of vanilla's own `PalPassiveSkillChange_Consumable_*` implants at 1000, matching every route this mod adds. Those 21 are exactly the rows that gate on a consumable in `LootablePassivesInsertRoutes.json`; derive the list from that file rather than retyping it.
  - `LootablePassivesInsertRoutes.json` — the 54 alias routes, plus the 54 inert alias passives that let those rows render. Every row needs a matching key in `lp/ids.lua`'s `IMPLANT_TARGET`; the two are maintained together in current implementation. A row with no key installs an inert alias and leaves it on the Pal; a key with no row is a dead list entry.
- `translations/en/` — display strings by text id.

### Naming

`LP` is the self-reference prefix for **Lootable Passives** throughout this mod and repo:

| Kind | Scheme | Example |
| --- | --- | --- |
| Package / mod folder | `LootablePassives` | `PalSchemaMods/LootablePassives/` |
| Disposable Implant items | `LP_Implant_<passive>` | `LP_Implant_Stamina_Up_1` |
| Insertion route passives | `LP_Insert_<passive>` | `LP_Insert_Stamina_Up_1` |
| Extraction markers | `LP_ExtractOne`, `LP_ExtractAll` | — |
| Text ids | `PASSIVE_LP_*` | `PASSIVE_LP_INSERT_STAMINA_UP_1_NAME` |

- Items and routes are kept distinct on purpose: a route's `RequireItemId` names an item, and giving both the same string would make logs and data impossible to read.
  - **One deliberate exception.** The 21 vanilla `PalPassiveSkillChange_Consumable_*` ids are *not* renamed. Those are the game's own disposable implants, and our routes point at them so an implant found in the world is still spendable. Minting parallel `LP_` items for them would silently break that.

---

## Development

### Where the mod lives

Three places, and only the loader writes the game:

| Place | Path | Written by |
| --- | --- | --- |
| Repo (working copy, source of truth) | this folder | edits, and `stage.ps1` (`Info.json` `Version`/`DebugMode`) |
| Workshop item folder | `<WorkshopRootDir>\<item id>\` | `stage.ps1`; the uploader writes `.workshop.json`, and `Info.json` on **Save Info.json** |
| Game install | `<Palworld>\Mods\NativeMods\UE4SS\...`, plus `Mods\ManagedMods\<PackageName>\` | the official mod loader, at launch |

- **The item folder comes first.** It is made by Palworld Mod Uploader's **Create New Mod**, which registers a Workshop item at once and names the folder with its id. Its template `Info.json` has `PackageName` `MyAwesomeMod`, one `InstallRule` per type ticked (Lua, Paks, LogicMods, PalSchema), and one folder per type. The full first-time setup is `README.md`'s `Starting a mod` section; keep it current.
- **The repo's `Info.json` is the only one to edit.** The uploader's fields (Mod Name, Package Name, Version, MinRevision, Author, and the others) read and write the item folder's `Info.json`, and every stage overwrites that file with the repo's.
- **Never write the game folders directly**, by script or by hand. The loader reinstalls them at launch, which overwrites a second writer's files, and its uninstall works from its manifest, which does not list them.

### Development Process

There is no build step and no local-only test build. **Every tested change is uploaded.** `stage.ps1` sets a new version and `DebugMode`, then copies the repo into the mod's Workshop item folder. The user uploads that folder to the Workshop, then tests it on two machines in multiplayer: the host, which installs from the item folder at launch, and a second machine subscribed to the mod, which installs the upload once Steam downloads it. Both must run the same version. **This repo is the working copy.** The general process is: edit here, run the checks, stage, upload, restart the game on both machines, run through actions in it, read the log.

The human-facing version of this process, including publishing, is the `Development` section of `README.md`. Change the tools or the loop and update both.

```powershell
# ... edit in the repo: the JSON under PalSchemaMods\, the Lua under Scripts\ ...
node tools\luacheck.js            # Lua parse check
luacheck Scripts                  # static analysis
lua tools\ledger_test.lua         # after any lp/ledger.lua edit
.\tools\stage_test.ps1            # after any tools/stage.ps1 edit
.\tools\stage.ps1                 # dev build: patch + 1, DebugMode true
.\tools\stage.ps1 -Publish        # release: minor + 1, patch 0, DebugMode false
# ... Upload To Steam, restart Palworld on both machines, read the log ...
```

- Staging is not optional and it is not automatic: the game loads only what the loader copied out of the item folder, so an unstaged repo edit is just an untested repo edit. `stage.ps1 -DryRun` first if you want to see what moves and the next version.
- **Uploading is the user's step, done by hand in Palworld Mod Uploader.** An agent stages; it does not upload or claim a stage has been uploaded.
- **A file the stage does not have stops the run.** The stage is a mirror, and the check that makes it one runs before anything is copied: a file in the item folder with no counterpart in the staged set is listed, and the run exits 1 with nothing changed (exit 0 under `-DryRun`). `-Force` deletes those files, and any directory left empty, instead of stopping. Delete a Lua module or a JSON patch from the repo and the next stage is `-Force`.
- Read `UE4SS.log` filtered on:
  - `[LootablePassives]` for the mod's own messages, which trace the code paths reached
  - `PalSchema` for confirmation that the JSON loaded
  - errors and warnings, for anything failing outright
- After a crash, read, search or filter `%LOCALAPPDATA%/Pal/Saved/Crashes/`.
- **NOTE:** UE4SS hot reload is disabled, and the loader installs only at launch, so a running game will not pick up changes without a restart.

### Dev Commands

- node tools\luacheck.js is a Lua syntax check. Run after ANY Lua edit.
- luacheck Scripts is the real static analyzer. Baseline is 0 warnings / 0 errors.
- lua tools\ledger_test.lua tests the mod. Run after ANY lp/ledger.lua edit.
  - `ledger_test.lua` is a behaviour test for one insertion, not a data verifier: it stubs `lp.inventory` and asserts the ledger's TSV round-trip and which candidate a row is delivered to. It exists because that logic is the only part of the mod with no engine call in it.
- .\tools\stage_test.ps1 tests the stage script. Run after ANY tools/stage.ps1 edit, and add a case for any behaviour you add. It runs a copy of `stage.ps1` against throwaway folders in `%TEMP%` and never touches the real game or Workshop folders.
- .\tools\stage.ps1 is the only repo -> game path. Run it before every functional runtime test, and only when the result is going to be uploaded. Its header documents every check and option; the rules an agent must keep:
  - Every run that stages rewrites `Version` and `DebugMode` **in the repo's `Info.json`**: no flag is a dev build (patch + 1, `DebugMode` true); `-Publish` is a release (minor + 1, patch 0, `DebugMode` false). Commit the rewritten `Info.json` with the change it carries.
  - **Patch 0 means a release.** A nonzero patch with `DebugMode` true is a dev build.
  - `-DryRun`, a failed check, and a stop on stale files all write nothing.
  - It holds nothing specific to this mod, so it can be copied unchanged into another mod's repo. Keep it that way: mod-specific facts belong in `Info.json`.
  - The Workshop page description is not part of the stage. After uploading, paste `.docs/workshop-description.txt` into the Workshop page by hand if it changed.

#### Local tooling

Lua and luacheck are installed with Scoop, into the user profile, with no admin rights. luaparse comes from `npm install` in the repo root.

- Lua 5.5 (lua, luac on PATH) — for quick local sanity checks
- luacheck 1.2.0 — a real static analyzer (undefined globals, unused vars, shadowing), stronger than this repo's tools/luacheck.js, which is parse-only
- luaparse — the parser `tools/luacheck.js` uses, declared in `package.json`
- .luacheckrc — declares UE4SS's injected globals (RegisterHook, ExecuteInGameThread, FindAllOf, etc.) so luacheck stops flagging the mod's own API as "undefined". Without it `luacheck Scripts` reports dozens of false positives; with it, only real findings.
- .luarc.json — the same global list for LuaLS, so the in-editor language server and the CLI checker agree.

### How a staged build reaches the game

```text
repo --stage.ps1--> <Workshop content>\1623730\<item id>\ --loader, at launch--> Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\
                                                                                 Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\{items,raw,translations}\
```

- At launch, the loader enables each `ActiveModList` entry in `Mods\PalModSettings.ini` by finding the folder under `WorkshopRootDir` whose `Info.json` has that PackageName. It compares that `Info.json`'s `Version` with the installed copy in `Mods\ManagedMods\<PackageName>\Info.json`, as plain strings. When they differ, or `DebugMode` is true, it removes what `Mods\ManagedMods\<PackageName>\InstallManifest.json` lists and copies the `InstallRule` targets in again. Otherwise it changes nothing. On the host the item folder is the one `stage.ps1` writes; on a subscribed machine it is Steam's download of the upload. That is why every stage raises the version: the version change is what makes both machines reinstall.
- **Stage only what will be uploaded.** The host's next launch installs whatever is staged, uploaded or not, which leaves a subscribed machine behind the host.
- **Nothing but the loader writes the two game folders.** A second writer would be overwritten by the next reinstall, and a file it added is not in the loader's manifest, so the loader's uninstall does not account for it.
- **For a `Lua`-type rule the loader writes UE4SS's `mods.txt` entry** (`<PackageName> : 1`), which is what starts the Lua half. PalSchema needs no registration; it loads any folder under its `mods/` directory.
- **Do not disable this mod by setting `LootablePassives : 0` in `mods.txt`.** That line controls only the Lua half. The PalSchema half has no such switch, because it loads whenever its folder is on disk, so the mod's operations stay in the Surgery Table list with nothing behind them. Disable it under **Options → Mod Management**, which uninstalls both halves.
- **Keep one folder per PackageName under `WorkshopRootDir`.** With several, the loader enables one of them, and which one is not defined.
- **Do not subscribe to this mod on the host machine** — the one that stages. Steam downloads a subscribed item into the same numbered folder, over the staged files, and the uploader makes subscribed items view-only.

### Errors and warnings

The baseline is **0 warnings / 0 errors**. Treat any error or warning as something to fix rather than to note.

### The JSON is the source of truth

The mod's data half is the JSON under `PalSchemaMods/LootablePassives/` and `Scripts/passive_items.lua`. **Edit these directly to make changes.**  What that costs, stated plainly: nothing validates the data at build time. PalSchema fails **silently** — a malformed file simply does not load, and a mismatch between the files that define the alias routes produces a dead list entry with no error anywhere a player would see it. As a half-measure applied to trace, the **startup counts** line should read exactly: `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.` 115 = the 94 `LP_Implant_*` items plus the 21 vanilla PalPassiveSkillChange_Consumable_*` ones. A number that reads low means a Lua table is short.

- **That line does NOT verify the data half, and must not be trusted as if it did.** It counts entries in `Scripts/passive_items.lua` and `lp/ids.lua`, which are Lua and load with the Lua half. A package whose PalSchema payload installed to the wrong path printed this line in full while PalSchema loaded **zero** rows. The check that actually covers the data half is PalSchema's own log lines: `DT_OperatingTablePassiveSkillDataTable: 54 rows updated, 117 rows added, 0 rows deleted, 0 errors` and `DT_PassiveSkill_Main_Common: 0 rows updated, 56 rows added`. `[PalSchema] Loading mod: LootablePassives` on its own means only that a folder of that name exists — it is printed even when the folder holds nothing PalSchema can read.  The saving grace is that these tables are finished. Nothing in normal work should touch them from this point forward except a major refactor of disposable implant item setup.

### Uninstall Note

Disable the mod under **Options → Mod Management** and the loader removes what it installed. Disposable implant items defined by the mod already in a save become unknown items; passives already implanted are real passives and stay put.

---

## Rules for Commenting Code

- **Say what the code does**: what it reads, writes, calls, returns, in what order, and what it returns instead on failure.
- **API facts are allowed where a header dump backs them** --> arity, out-parameters, property versus call, a `WBP_*.hpp` line number. Those are checkable without launching anything.
- **No evidence in comments.** No log timestamps, session references, screenshot numbers, or "measured". Those age badly and since agents may change code and not comments, this means leftover comments may derive from code that may has changed since a comment was written, which is misleading or destructive.
- **No design intent or future plans.** Create or update a single planing document as markdown while working on features or other goals.  Do not create separate or alternate working documents-- keep all edits to a single working plan document.

---

## Rules for Writing and Editing Markdown

- Follow markdownlist's standard formatting rules such as spaces before and after test blocks; VS Code's linting must read clean in IDE
- Use headings with proper depth instead of bolding to give the document correct depth and ordering
- DO NOT cut lines with newline characters for pages -- let normal word wrap handle appropriate display length; this best keeps markdown files view and platform-independent

---

## Data constraints that shaped the design

These are properties of the game's tables, not choices this mod made. Breaking one produces a dead route with no error anywhere a player would see it.

- **A passive can own only ONE row in `DT_OperatingTablePassiveSkillDataTable`.** For the 54 passives whose row is already a vanilla recipe, an extracted module could be tied to a recipe in key items creating a duplicate; the `LP_Insert_*` alias routes exist to prevent that.
- **Marker rows carry `RequireItemId: "None"`, so nothing gates them.** Vanilla will happily run the swap and leave the marker sitting on the Pal.
- **Naming `RequireItemId` in the vanilla reprice file would destroy the recipe gate.** That file sets `Price` and nothing else, on purpose.
- **Module rarity tracks passive tier** — white for negatives, green/blue/purple ascending, orange for Diamond and World Tree. A convention, but an established one; match it.
- **`SortID` on the 94 modules is one contiguous block, `95001`-`95094`, ordered by rarity descending then English display name ascending.** Orange first. It is derived, so adding a module means recomputing the whole block rather than appending to it — the two alphabetical-by-id runs that came from appending are exactly why rarity used to scatter in the inventory. The 21 vanilla `PalPassiveSkillChange_Consumable_*` items keep vanilla's own `SortID`: their `Rarity` is not readable from the repo, so any block chosen for them risks putting an orange module in the purple run.

### DEV Tips

Each item below caused a crash or a wrong conclusion in this repo.  These indicate known problem areas where extra care must be taken, though these may not remain relevant to later designs.

- **`FName` needs `util.name_to_string()`, never `tostring()`.** `tostring` on an FName yields `FNameUserdata: 000001DF50F0E428`, which looks like output and carries nothing. A whole test run was wasted logging three ids that way.
- **`pcall` does not catch a native access violation.** It catches Lua errors. A wrong-arity UFunction call, or engine code that dereferences null, takes the process down regardless. `StaticConstructObject` on `UPalIncidentBase` crashed the game with `EXCEPTION_ACCESS_VIOLATION reading 0x2a8` after being described as unable to crash because it "only constructs and inspects" — **construction runs engine code. It is not inspection.**
- **Log immediately before each engine call in a probe.** One log line per call, so that if the game dies, the last line in `UE4SS.log` names the call. A probe that makes three engine calls between two log lines cannot be diagnosed after the fact, and the crash above could not be attributed to either of its two candidate calls.
- **Take a widget from the hook context. Never go looking for one.** Every widget hook this mod owns is a method on the widget it wants, so UE4SS hands that object to the callback as its first argument, live by construction — `Update Button State` gives the tab page, `OnPassiveUpdate` gives the screen. `lp/ui.lua` records both and calls `FindAllOf` nowhere.
- **A closure per call is a crash, not an inefficiency.** `pcall(function() ... end)` allocates a fresh Lua closure and a UE4SS registry ref every time it runs. On a hook that fires at frame rate that churn produced `Error: [Lua::Registry::get_function_ref] Ref was not function` followed by `EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff`, with a call stack entirely inside UE4SS. Everything on a per-frame path therefore uses argument-form `pcall` against a module-level accessor — `util.field`, `util.method`, and the `_call_`/`_index_` helpers — and every hook callback is built once, at load, and passed by reference. `main.lua`'s `coalescer()` and `hooks.lua`'s per-registration `entry.retry` exist for the same reason: a flag alone is not enough, because `ExecuteWithDelay(0, ...)` completes within the tick and the next firing would allocate again.
- **`restore_replaced_passive` removes the marker before adding the passive, and the order is load-bearing.** `AddPassiveSkill(AddSkill, OverrideSkill)` does not reliably honour the override: it appended the passive and left the marker attached, which is how a Pal ended up carrying Infinite Stamina twice. It is also how the overwrite case crashed — a Pal whose four slots were full gained a fifth entry, and the passive panel has only four cards to index, which is why inserting into an *empty* slot never crashed. Removing first keeps the list from growing past what the UI can address. The trade is that a failed add leaves the Pal with neither, so every caller checks the result and the implant callers refund the module.
- **Check arity against the header dumps, and not just `Pal.hpp`.** Widget functions live in `CXXHeaderDump/WBP_*.hpp`, CommonUI in `CommonUI.hpp`, engine in `Engine.hpp`. Prefer no-argument getters; avoid out-parameter overloads (`TryGetContainer(Out&)`) when a by-value equivalent exists (`GetContainer()`).
