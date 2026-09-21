# CLAUDE.md

Guidance for Claude Code working in this repository.

- This `CLAUDE.md` file is **durable** repo setup and development processes, plus things that will help an agent.  DO NOT add ephemeral details of planning or findings based on the current repo state to this document.
- Mod description and use lives in `README.md` and should be maintained there without being duplicated here.  Update the README.md whenever you change the user-facing game functionality or Steam Workshop management cycle.
- The planning file at `docs/PLAN.md` takes prescedence for intent and implementation work; prefer it to comments in all other docs for direction of edits.
- DO NOT TRUST COMMENTS IN CODE -- TREAT THESE AS GUESSES OR HOPES; COMMENTS MAY ALSO BE OUTDATED LEFTOVER FROM PREVIOUS CODE WHICH CAN LEAD ASTRAY IF NOT VERIFIED.

---

## What the repository is

This repo contains a Palworld mod.

### Repository layout

| Directory | Purpose | Deployability |
| --- | --- | --- |
| Scripts/ | Lua runtime (main.lua, settings.lua, lp/*.lua) | ships |
| PalSchemaMods/LootablePassives/ | JSON data patches: items, DataTable rows, English strings | ships |
| tools/ | install.ps1, capture.ps1, luacheck.js, ledger_test.lua | dev only-do not ship |
| docs/PLAN.md | the working plan | dev only-do not ship |
| CLAUDE.md | Agent guidance | dev only-do not ship |
| README.md / LICENSE | the user-facing docs | ships |
| Info.json | Steam Workshop package manifest | ships |
| thumbnail.png | Workshop thumbnail | ships |

- **Why the PalSchema payload is nested two deep.** A Workshop `InstallRule` copies each `Targets` folder *with its name preserved* into the destination for its `Type`, and a PalSchema mod's folder name IS its mod id. A flat `PalSchema/` with `"Targets": ["./PalSchema"]` therefore installed as `PalSchema\mods\PalSchema` — silently renaming this mod's whole data half, and colliding with any other package that made the same mistake. `PalSchemaMods/LootablePassives/` is what makes the installed folder name come out right.
- **DO NOT** Rederence dev-only artifacts on things that ship as this creates a broken reference in shipped items

### `PalSchemaMods/LootablePassives/`

- `items/` — the 94 mod-defined implant modules.
- `raw/` — DataTable patches. Four files, and the split matters:
  - `LootablePassivesOperation.json` — the two marker passives and their operations.
  - `LootablePassivesOperatingTable.json` — 61 module routes for passives with no vanilla row.
  - `LootablePassivesVanillaPrices.json` — reprices the 54 vanilla routes to 5000. **`Price` only.** Naming `RequireItemId` here would overwrite and thereby destroy the recipe gate.
  - `LootablePassivesInsertRoutes.json` — the 54 alias routes, plus the 54 inert alias passives that let those rows render. Every row needs a matching key in `lp/ids.lua`'s `IMPLANT_TARGET`; the two are maintained together in current implementation. A row with no key installs an inert alias and leaves it on the Pal; a key with no row is a dead list entry.
- `translations/en/` — display strings by text id.

### Naming and Publishing

`LP` is the self-reference prefix for **Lootable Passives** throughout this mod and repo:

| Kind | Scheme | Example |
| --- | --- | --- |
| Package / mod folder | `LootablePassives` | `PalSchemaMods/LootablePassives/` |
| Implant module items | `LP_Implant_<passive>` | `LP_Implant_Stamina_Up_1` |
| Insertion route passives | `LP_Insert_<passive>` | `LP_Insert_Stamina_Up_1` |
| Extraction markers | `LP_ExtractOne`, `LP_ExtractAll` | — |
| Text ids | `PASSIVE_LP_*` | `PASSIVE_LP_INSERT_STAMINA_UP_1_NAME` |

- Items and routes are kept distinct on purpose: a route's `RequireItemId` names an item, and giving both the same string would make logs and data impossible to read.
  - **One deliberate exception.** The 21 vanilla `PalPassiveSkillChange_Consumable_*` ids are *not* renamed. Those are the game's own disposable implants, and our routes point at them so an implant found in the world is still spendable. Minting parallel `LP_` items for them would silently break that.

---

## Development

### Development Process

There is no build step in development mode, but there is an install step to move files from the repo directories to the game directories. **This repo is the working copy.** The general development process is : edit here, run the checks, deploy to the game, restart and run through actions in the game, read the log. (Note that none of this applies for a mod downloaded from the Steam Workshop -- the production flow.)

```powershell
# ... edit in the repo: the JSON under PalSchemaMods\, the Lua under Scripts\ ...
node tools\luacheck.js            # Lua parse check
.\tools\install.ps1               # repo -> game install
# ... restart Palworld, read the log ...
```

- Deploying is not optional and it is not automatic: the game loads only what is under `<Palworld>\Mods\NativeMods\UE4SS\Mods`, so an untested repo edit is just an untested repo edit. `install.ps1 -DryRun` first if you want to see what moves.
- Log reading filters reads of `UE4SS.log` on...
  - `[LootablePassives]` gives mod-specific log messages, helps trace code paths reached
  - `PalSchema` gives verification on item loads from JSON
  - errors and warnings to find things explicitly failing
- In the event of chrashes, read/seach/filter: `%LOCALAPPDATA%/Pal/Saved/Crashes/`
- **NOTE:** UE4SS hot reload is disabled, so a running game will not pick up chanes without a restart.
- **NOTE:** This is not a Workshop item yet, so the in-game mod manager cannot install/manage it.

### Dev Commands

- node tools\luacheck.js       # Lua syntax check. Run after ANY Lua edit.
- luacheck Scripts             # The real static analyzer. Baseline is 0 errors.
- lua tools\ledger_test.lua    # The one automated test. Run after ANY lp/ledger.lua edit.
- .\tools\install.ps1          # repo -> game install. The normal direction; run before every test.
- `ledger_test.lua` is a behaviour test for one module, not a data verifier: it stubs `lp.inventory` and asserts the ledger's TSV round-trip and which candidate a row is delivered to. It exists because that logic is the only part of the mod with no engine call in it.

### What `install.ps1` copies, and where

```test
Scripts\                         ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\
PalSchemaMods\LootablePassives\  ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\
```

- The script also adds `LootablePassives : 1` to UE4SS's `mods.txt`, which is what actually starts the
Lua half. PalSchema needs no registration — it loads any folder under its `mods/` directory.  This split control CAN lead to unexpected states.
- **Do not disable this mod by setting `LootablePassives : 0` in `mods.txt`.** That line controls only the Lua half. The PalSchema half has no such switch — it loads whenever its folder is on disk — so the mod's operations stay in the Surgery Table list with nothing behind them. Removing the folders is the only safe way off.

### Uninstall

Delete **both** destination folders, then remove the `mods.txt` line. Modules already in a save become unknown items; passives already implanted are real passives and stay put.



### CLI Development Tools

...via Scoop, installed to user profile, no admin needed

- Lua 5.5 (lua, luac on PATH) — for quick local sanity checks
- luacheck 1.2.0 — a real static analyzer (undefined globals, unused vars, shadowing), stronger than this repo's tools/luacheck.js, which by its own comment is parse-only
- .luacheckrc — declares UE4SS's injected globals (RegisterHook, ExecuteInGameThread, FindAllOf, etc.) so luacheck stops flagging the mod's own API as "undefined"
- .luarc.json — same global list for LuaLS, so the in-editor LSP and the CLI checker agree `luacheck Scripts` from the repo root, alongside `node tools\luacheck.js`, in the normal edit/check/install loop. Without `.luacheckrc` it reports ~53 false positives from the unrecognised UE4SS globals; with it, only real findings.

### Errors and warnings

The baseline is **0 errors**. Treat any *error* or warning as something to fix rather than to note.

### The JSON is the source of truth

The mod's data half is the JSON under `PalSchemaMods/LootablePassives/` and `Scripts/passive_items.lua`. **Edit these directly to make changes.**  What that costs, stated plainly: nothing validates the data at build time. PalSchema fails **silently** — a malformed file simply does not load, and a mismatch between the files that define the alias routes produces a dead list entry with no error anywhere a player would see it. As a half-measure applied to trace, the **startup counts** line should read exactly: `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.` 115 = the 94 `LP_Implant_*` items plus the 21 vanilla PalPassiveSkillChange_Consumable_*` ones. A number that reads low means something did not load.  The saving grace is that these tables are finished. Nothing in normal work should touch them from this point forward except a major refactor of disposable implant item setup.

---

## Rules for Commenting Code

- **Say what the code does**: what it reads, writes, calls, returns, in what order, and what it returns instead on failure.
- **API facts are allowed where a header dump backs them** --> arity, out-parameters, property versus call, a `WBP_*.hpp` line number. Those are checkable without launching anything.
- **No evidence in comments.** No log timestamps, session references, screenshot numbers, or "measured". Those age badly and since agents may change code and not comments, this means leftover comments may derive from code that may has changed since a comment was written, which is misleading or destructive.
- **No design intent or future plans.** That is `docs/PLAN.md`'s job, and a comment that disagrees with the plan is noise at best and causes alternate implementation or wasted effort at worst.

---

## Rules for Writing and Editing Markdown

- Follow markdownlist's standard formatting rules such as spaces before and after test blocks; VS Code's linting must read clean in IDE
- Use headings with proper depth instead of bolding to give the document correct depth and ordering
- DO NOT cut lines with newline characters for pages -- let normal word wrap handle appropriate display length; this best keeps markdown files view and platform-independent
