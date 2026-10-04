# CLAUDE.md

Guidance for Claude Code working in this repository.

- This `CLAUDE.md` file is **durable** repo setup and development processes, plus things that will help an agent.  DO NOT add ephemeral details of planning or findings based on the current repo state to this document.
- Two documents describe the mod, for two different readers, and neither is duplicated here:
  - `README.md` is the GitHub page for this **development repo**. It describes the mod and how to develop, install and publish it from source. It does **not** ship. Update it whenever you change user-facing game functionality, the dev tools, or the publishing cycle.
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
| tools/ | install.ps1, stage.ps1, mirror.ps1, luacheck.js, ledger_test.lua | dev only-do not ship |
| CLAUDE.md | Agent guidance | dev only-do not ship |
| README.md | GitHub page for the development repo | dev only-do not ship |
| .docs/workshop-description.txt | Steam Workshop page text, pasted by hand | dev only-do not ship |
| LICENSE | license | ships |
| Info.json | Steam Workshop package manifest | ships |
| thumbnail.png | Workshop thumbnail | ships |

- **How `InstallRule.Targets` actually installs, observed from an `InstallManifest.json` the official loader wrote.** The loader appends **`{PackageName}`** to the directory for the `Type`, and *then* copies each `Targets` folder in under its own leaf name. So `Lua` + `./Scripts` lands at `Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts`, and `PalSchema` + `./PalSchemaMods/LootablePassives/raw` lands at `Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\raw`. `04-Tech.md` states the package-name level in prose — "the Package Name is used as the folder name" — and omits it from its per-type table, which is how it got read the wrong way round.
  - **A `Targets` leaf equal to the `PackageName` is therefore a bug**, not the way to control the installed name: it doubles, as `PalSchema\mods\LootablePassives\LootablePassives\`, and PalSchema then loads the folder and finds nothing. `tools/stage.ps1` refuses that shape and prints the computed install path for every rule.
  - The repo's `PalSchemaMods/LootablePassives/` wrapper is consequently just a container, not load-bearing; `Info.json` names the three folders **inside** it. Add a fourth kind of PalSchema data and it must be added to `Targets` too — `stage.ps1` fails the stage if anything shipped is not covered by some `Targets` path.
- **DO NOT** Reference dev-only artifacts on things that ship as this creates a broken reference in shipped items. `README.md` and `.docs/` are dev-only for this purpose, so shipped Lua must not point at them either.

### `PalSchemaMods/LootablePassives/`

- `items/` — the 94 mod-defined disposable implants.
- `raw/` — DataTable patches. Four files, and the split matters:
  - `LootablePassivesOperation.json` — the two marker passives and their operations.
  - `LootablePassivesOperatingTable.json` — 61 routes for passives with no vanilla row.
  - `LootablePassivesVanillaPrices.json` — reprices the 54 vanilla routes. **`Price` only.** Naming `RequireItemId` here would overwrite and thereby destroy the recipe gate. The price follows whether the route **consumes** what it requires, not whether the row is vanilla: 33 recipe routes at 5000, and the 21 that spend one of vanilla's own `PalPassiveSkillChange_Consumable_*` implants at 1000, matching every route this mod adds. Those 21 are exactly the rows that gate on a consumable in `LootablePassivesInsertRoutes.json`; derive the list from that file rather than retyping it.
  - `LootablePassivesInsertRoutes.json` — the 54 alias routes, plus the 54 inert alias passives that let those rows render. Every row needs a matching key in `lp/ids.lua`'s `IMPLANT_TARGET`; the two are maintained together in current implementation. A row with no key installs an inert alias and leaves it on the Pal; a key with no row is a dead list entry.
- `translations/en/` — display strings by text id.

### Naming and Publishing

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

### Development Process

There is no build step in development mode, but there is an install step to move files from the repo directories to the game directories. **This repo is the working copy.** The general development process is : edit here, run the checks, deploy to the game, restart and run through actions in the game, read the log. (Note that none of this applies for a mod downloaded from the Steam Workshop -- the production flow.)

The human-facing version of this process, including publishing, is the `Development` section of `README.md`. Change the tools or the loop and update both.

```powershell
# ... edit in the repo: the JSON under PalSchemaMods\, the Lua under Scripts\ ...
node tools\luacheck.js            # Lua parse check
luacheck Scripts                  # static analysis
lua tools\ledger_test.lua         # after any lp/ledger.lua edit
.\tools\install.ps1               # repo -> game install
# ... restart Palworld, read the log ...
```

- Deploying is not optional and it is not automatic: the game loads only what is under `<Palworld>\Mods\NativeMods\UE4SS\Mods`, so an untested repo edit is just an untested repo edit. `install.ps1 -DryRun` first if you want to see what moves.
- **A file the repo does not have stops the install.** The install is a mirror, and the check that makes it one runs before anything is copied: a file in either destination with no counterpart in the repo is listed and the run exits 1 with nothing changed. That file would still be loaded by the game, so a run that ignored it would be testing something other than the repo. `-Force` deletes those files, and any directory left empty, instead of stopping. Delete a Lua module or a JSON patch from the repo and the next install is `-Force`.
- Log reading filters reads of `UE4SS.log` on...
  - `[LootablePassives]` gives mod-specific log messages, helps trace code paths reached
  - `PalSchema` gives verification on item loads from JSON
  - errors and warnings to find things explicitly failing
- In the event of chrashes, read/seach/filter: `%LOCALAPPDATA%/Pal/Saved/Crashes/`
- **NOTE:** UE4SS hot reload is disabled, so a running game will not pick up chanes without a restart.
- **NOTE:** A dev install made by `install.ps1` is not managed by the in-game mod manager; only a Workshop install is.

### Dev Commands

- node tools\luacheck.js is a Lua syntax check. Run after ANY Lua edit.
- luacheck Scripts are the real static analyzer. Baseline is 0 errors.
- lua tools\ledger_test.lua is the one automated test. Run after ANY lp/ledger.lua edit.
  - `ledger_test.lua` is a behaviour test for one insertion, not a data verifier: it stubs `lp.inventory` and asserts the ledger's TSV round-trip and which candidate a row is delivered to. It exists because that logic is the only part of the mod with no engine call in it.
- .\tools\install.ps1 is the repo -> game install. The normal direction; run before every functional runtime test. Takes `-DryRun`, and `-Force` to delete files the repo no longer has.
- .\tools\stage.ps1 is the repo -> Workshop item-folder copy, for publishing only. An allowlist (`Info.json`, `thumbnail.png`, `LICENSE`, `Scripts\`, `PalSchemaMods\LootablePassives\` — not `README.md`), the same mirror rule and `-DryRun`/`-Force` as install.ps1, plus four checks on `Info.json` that the uploader itself does not make. It never touches `.workshop.json`, which holds the Published ID.
  - Usage: `.\tools\stage.ps1 -ItemId <numbered item folder> -DryRun`, then again without `-DryRun`; `-Destination` takes the full item folder instead of `-ItemId`.
  - The Workshop page description is not part of the stage. After uploading, paste `.docs/workshop-description.txt` into the Workshop page by hand if it changed.
- tools\mirror.ps1 holds the mirror rule both scripts share: `Get-RelativePaths`, `Stop-OnStale` and `Remove-EmptyDirectories`. It is dot-sourced, never run. A change to how either script mirrors goes here, not into one script.
  - `Stop-OnStale` ends the calling script itself (`exit 0` under `-DryRun`, `exit 1` otherwise), so nothing after the call runs when files are stale.

...via Scoop, installed to user profile, no admin needed

- Lua 5.5 (lua, luac on PATH) — for quick local sanity checks
- luacheck 1.2.0 — a real static analyzer (undefined globals, unused vars, shadowing), stronger than this repo's tools/luacheck.js, which by its own comment is parse-only
- .luacheckrc — declares UE4SS's injected globals (RegisterHook, ExecuteInGameThread, FindAllOf, etc.) so luacheck stops flagging the mod's own API as "undefined"
- .luarc.json — same global list for LuaLS, so the in-editor LSP and the CLI checker agree `luacheck Scripts` from the repo root, alongside `node tools\luacheck.js`, in the normal edit/check/install loop. Without `.luacheckrc` it reports ~53 false positives from the unrecognised UE4SS globals; with it, only real findings.

#### What `install.ps1` mirrors, and where

```test
Scripts\                         ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\
PalSchemaMods\LootablePassives\  ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\
```

- Those two destinations are the only thing the stale check examines, and the only thing `-Force` deletes from. Files the game folder holds elsewhere are not touched — including `LootablePassives\enabled.txt`, which is not ours and which UE4SS reads as a second way to start a Lua mod.
- The script also adds `LootablePassives : 1` to UE4SS's `mods.txt`, which is what actually starts the
Lua half. PalSchema needs no registration — it loads any folder under its `mods/` directory.  This split control CAN lead to unexpected states.
- **Do not disable this mod by setting `LootablePassives : 0` in `mods.txt`.** That line controls only the Lua half. The PalSchema half has no such switch — it loads whenever its folder is on disk — so the mod's operations stay in the Surgery Table list with nothing behind them. Removing the folders is the only safe way off.

### Errors and warnings

The baseline is **0 errors**. Treat any *error* or warning as something to fix rather than to note.

### The JSON is the source of truth

The mod's data half is the JSON under `PalSchemaMods/LootablePassives/` and `Scripts/passive_items.lua`. **Edit these directly to make changes.**  What that costs, stated plainly: nothing validates the data at build time. PalSchema fails **silently** — a malformed file simply does not load, and a mismatch between the files that define the alias routes produces a dead list entry with no error anywhere a player would see it. As a half-measure applied to trace, the **startup counts** line should read exactly: `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.` 115 = the 94 `LP_Implant_*` items plus the 21 vanilla PalPassiveSkillChange_Consumable_*` ones. A number that reads low means a Lua table is short.

- **That line does NOT verify the data half, and must not be trusted as if it did.** It counts entries in `Scripts/passive_items.lua` and `lp/ids.lua`, which are Lua and load with the Lua half. A package whose PalSchema payload installed to the wrong path printed this line in full while PalSchema loaded **zero** rows. The check that actually covers the data half is PalSchema's own log lines: `DT_OperatingTablePassiveSkillDataTable: 54 rows updated, 117 rows added, 0 rows deleted, 0 errors` and `DT_PassiveSkill_Main_Common: 0 rows updated, 56 rows added`. `[PalSchema] Loading mod: LootablePassives` on its own means only that a folder of that name exists — it is printed even when the folder holds nothing PalSchema can read.  The saving grace is that these tables are finished. Nothing in normal work should touch them from this point forward except a major refactor of disposable implant item setup.

### Uninstall Note

Uninstall is not needed during DEV; may be needed if transitioning to Steam Workshop installs.  Delete **both** destination folders, then remove the `mods.txt` line. Disposable implant items defined by the mod already in a save become unknown items; passives already implanted are real passives and stay put.

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
