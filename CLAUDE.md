# CLAUDE.md

Guidance for Claude Code working in this repository.

---

## The Surgery Table Design

### Three ways a passive gets listed in implants list

1. **Default list** — As in vanilla Palworld, the Surgery Table comes with recipe-like options which are **not consumed**; The mod changes *only* the price, to 5,000.  In the surgery Table's passives list when inserting on a pal, these show a grey outline icon, no quantity, and a flavor line of dashes.
2. **Reusable recipes** — bought with bounty or arena tokens, these are items that live in **Key Items**, are **not consumed** on use. The mod changes *only* the price, to 5,000. In the list these show a green chip icon, no quantity, and the flavour line `Implant: X` — which is vanilla's naming and must never be reused for our mod's items.

The mechanics anove are not otherwise changed in this mod!

3. **Disposable modules** — single-use items in the regular inventory, **consumed** on use. Vanilla Palworld has only a few types of passives as disposable modules.  Adding ALL PASSIVES as disposable modules is the mod's core feature: expanding the set of sctractable/insertable passives to all 115 passives.   At the surgery table, insert one, extract one, or extract all each charge a flat 1,000 gold. Extraction produces items sent to the player's inventory; extracted passives are represented in the inventory and the surgery table list as a purple chip icon, a quantity, and the flavour line `Disposable Implant: X`; max stack is 9999.

### Three Operations

**Three operations** are added to the Passive Skill Selection list:

- **Extract Passive** — removes the selected passive, returns one matching module.
- **Extract All Passives** — removes every extractable passive, returns a module for each. One flat
  1,000 gold for the whole operation.
- **`<passive name>`** — one entry per passive, spending a disposable module.
- NOTE: the game has a an over-write behavior that is also unchanged by this mod; overwritten passives are GONE and do not render items

The Surgery screen stays open after extracting, so you can work through a Pal without reopening the interface.

The bounty-token economy stays meaningful: extracting a recipe-generated passive gives you a
single-use module, never a permanent Key Item recipe.

In the list the routes stay visually distinct, following the game's own conventions — a green chip
with no quantity and the line `Implant: X` is a reusable recipe; a purple chip with a quantity and
`Disposable Implant: X` is a single-use module.

## The Pal Disassembly Conveyor Design

> **Status: not implemented yet.** `Scripts/lp/conveyor.lua` is an *observation pass* — it watches a
> conveyor consume a Pal and logs the modules it would hand over, with `DRY_RUN = true`. It creates
> nothing. The design below is the target, not the current behaviour. The remaining work, and the
> questions that can only be answered by playing, are in that file's header and in `docs/PLAN.md`.

### Automatic Extract All

- Passives are to be extracted (extract-all) on the Pal Disassembly Conveyor along with normal Pal Disassembly
- Disassembly UX is placing a pal in a slot (not new or changed)
  - The Pal is automatically disassembled in a queue-like process
  - The process costs no currencies, but the pal is removed from the world
  - The items produced by the pal spit out the back of the machine and look like world drops (the machine's own meahcnics).  In our mod passives are to be added to this drop or dropped in a similar fashion to the same output locaion.
  - With the mod functioning properly, Pal disassembly is expected to yield 0-4 passives per pal plus the normal loot

### Mod Dev notes

- A passive can own only **one** row in `DT_OperatingTablePassiveSkillDataTable`. For the 54 passives whose row is the vanilla recipe one, that left extracted modules with nowhere to be spent — hence the alias routes.
- **Extraction never hands back a reusable recipe.** Extracting a recipe-generated-passive gives a single-use module, not a permanent Key Item, so the bounty-token economy stays meaningful.
- **Duplicates are blocked**, matching vanilla. The Edit button greys out or inactive if the Pal already has the passive, and the transaction refuses and refunds the module even if the click gets through.
- **Crash-safe by ordering.** The module is granted *before* the passive is removed, and a recovery journal replays an interrupted exchange on the next load. If anything goes wrong mid-transaction the mod would rather duplicate an item than destroy a passive.
- **Module rarity tracks passive tier** — white for negatives, green/blue/purple as you go up, orange for Diamond and World Tree.

---

## Development

**CLI Development Tools:**

...via Scoop, installed to your user profile, no admin needed

- Lua 5.5 (lua, luac on PATH) — for quick local sanity checks
- luacheck 1.2.0 — a real static analyzer (undefined globals, unused vars, shadowing), stronger than this repo's tools/luacheck.js, which by its own comment is parse-only
- .luacheckrc — declares UE4SS's injected globals (RegisterHook, ExecuteInGameThread, FindAllOf, etc.) so luacheck stops flagging the mod's own API as "undefined"
- .luarc.json — same global list for LuaLS, so the in-editor LSP and the CLI checker agree
`luacheck Scripts` from the repo root, alongside `node tools\luacheck.js`, in the normal
edit/check/install loop. Without `.luacheckrc` it reports ~53 false positives from the
unrecognised UE4SS globals; with it, only real findings.

The baseline is **0 errors** and a small number of cosmetic warnings (currently an unused
hook argument that the callback signature requires, and one over-long line). Treat any new
*error*, or a warning you did not just introduce, as something to fix rather than to note.
Deliberately not recording an exact warning count here: the last one went stale within a
day and then read as a verified fact.

**Mod Development:**

There is no build step, but there is a deploy step. **This repo is the working copy.** Edit here,
run the checks, deploy to the game, restart, read the log.

```powershell
# ... edit in the repo: the JSON under PalSchemaMods\, the Lua under Scripts\ ...
node tools\luacheck.js            # Lua parse check
.\tools\install.ps1               # repo -> game install
# ... restart Palworld, read the log ...
```

Deploying is not optional and it is not automatic: the game loads only what is under
`<Palworld>\Mods\NativeMods\UE4SS\Mods`, so an untested repo edit is just an untested repo edit.
`install.ps1 -DryRun` first if you want to see what moves.

**`install.ps1` copies; it never deletes.** A file deleted from the repo goes on living in the game
folder, and the game goes on loading it — so the thing you just "removed" keeps working, and the
repo you are testing is not the thing under test. When you delete a runtime file here, delete it
from the install too.

### The JSON is the source of truth

The mod's data half is the JSON under `PalSchemaMods/LootablePassives/` and `Scripts/passive_items.lua`.
Those are hand-maintained. **Edit them directly.**

There was a `data/*.tsv` → `tools/generate.py` pipeline that derived them, and a `tools/verify.py`
that checked the result. All of it is deleted. The one-time job it existed for — populating all 115
of the game's passives — is done, and a generator for a table that has stopped changing is a
liability: it makes the derived file look untouchable and the input file look authoritative when it
is neither. Do not reintroduce it, and do not write a new checker against a TSV that no longer
exists. If a similar bulk job ever comes up, write something throwaway for that job and delete it
when the job is done.

What that costs, stated plainly: nothing validates the data at build time any more. PalSchema fails
**silently** — a malformed file simply does not load, and a mismatch between the files that define
the alias routes produces a dead list entry with no error anywhere a player would see it. Two things
stand in for it now, and neither is as good:

- The **startup counts** line, which should read exactly:
  `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.`
  115 = the 94 `LP_Implant_*` items plus the 21 vanilla `PalPassiveSkillChange_Consumable_*` ones.
  A number that reads low means a half that did not load.
- Reading `UE4SS.log`, filtered on `[LootablePassives]` and on `PalSchema`.

The saving grace is that these tables are finished. Nothing in normal work should touch them.

### Reading the engine from Lua

Hard-won, each one from a crash or a wrong conclusion in this repo. Read before
adding any engine call.

**`FName` needs `util.name_to_string()`, never `tostring()`.** `tostring` on an
FName yields `FNameUserdata: 000001DF50F0E428`, which looks like output and
carries nothing. A whole test run was wasted logging three ids that way.

**Measure, and know what the number is.** `invSlots=308` was quoted as inventory
headroom and used to justify a design; it was the sum across all six
`EPalPlayerInventoryType` containers, including key items and equipment. The
real figure was 54 (`Common`, confirmed by `GetInventoryTypeFromStaticItemID`
returning 0 and by watching which container's free count moved). Log the
breakdown, not the aggregate, and name what is being summed. Never quote a
count read by eye off a log — compute it.

**`pcall` does not catch a native access violation.** It catches Lua errors. A
wrong-arity UFunction call, or engine code that dereferences null, takes the
process down regardless. `StaticConstructObject` on `UPalIncidentBase` crashed
the game with `EXCEPTION_ACCESS_VIOLATION reading 0x2a8` after being described
as unable to crash because it "only constructs and inspects" — **construction
runs engine code. It is not inspection.**

**Log immediately before each engine call in a probe.** One log line per call,
so that if the game dies, the last line in `UE4SS.log` names the call. A probe
that makes three engine calls between two log lines cannot be diagnosed after
the fact, and the crash above could not be attributed to either of its two
candidate calls.

**Check arity against the header dumps, and not just `Pal.hpp`.** Widget
functions live in `CXXHeaderDump/WBP_*.hpp`, CommonUI in `CommonUI.hpp`, engine
in `Engine.hpp`. Prefer no-argument getters; avoid out-parameter overloads
(`TryGetContainer(Out&)`) when a by-value equivalent exists (`GetContainer()`).

**"It is already in the codebase" is not evidence.** Much of this repo was
written by agents and never executed. `GetPlayerCharacterByPlayerIndex` sat in
`inventory.lua` looking established, on a branch that only runs in multiplayer
and had almost certainly never run at all.

**Multiplayer is a first-class case, not a later port.** `find_inventory(nil)`
resolves a player only when `state_count == 1`, so it returns nil with two
players connected. Any base-camp feature needs a stated rule for *which* player
receives something, or a mechanism that does not need one.

### Verifying behaviour

- **Verification Note:** Nothing that touches the engine has a unit test. The loop is: edit in the repo, run the checks, `install.ps1`, restart Palworld, read the log — filtering `UE4SS.log` on `[LootablePassives]`, and `%LOCALAPPDATA%/Pal/Saved/Crashes/` when it goes worse than that.
- **No hot reload.** `EnableHotReloadSystem = 0`; every Lua change needs a full restart. JSON does not hot-reload.

### Repository layout

```
Scripts/                         Lua runtime (main.lua, settings.lua, lp/*.lua); ships
PalSchemaMods/LootablePassives/  JSON data patches: items, DataTable rows, English strings; ships
tools/                           install.ps1, capture.ps1, luacheck.js; these do not ship
docs/PLAN.md                     the working plan; does not ship
CLAUDE.md                        Agent guidance
README.md / LICENSE              the user-facing docs; these ship
Info.json                        Steam Workshop package manifest
thumbnail.png                    Workshop thumbnail; ships
```

**Why the PalSchema payload is nested two deep.** A Workshop `InstallRule` copies each `Targets`
folder *with its name preserved* into the destination for its `Type`, and a PalSchema mod's folder
name IS its mod id. A flat `PalSchema/` with `"Targets": ["./PalSchema"]` therefore installed as
`PalSchema\mods\PalSchema` — silently renaming this mod's whole data half, and colliding with any
other package that made the same mistake. `PalSchemaMods/LootablePassives/` is what makes the
installed folder name come out right.

#### `PalSchemaMods/LootablePassives/`

- `items/` — the 94 mod-defined implant modules.
- `raw/` — DataTable patches. Four files, and the split matters:
  - `LootablePassivesOperation.json` — the two marker passives and their operations.
  - `LootablePassivesOperatingTable.json` — 61 module routes for passives with no vanilla row.
  - `LootablePassivesVanillaPrices.json` — reprices the 54 vanilla routes to 5000. **`Price`
    only.** Naming `RequireItemId` here would overwrite and thereby destroy the recipe gate.
  - `LootablePassivesInsertRoutes.json` — the 54 alias routes, plus the 54 inert alias passives
    that let those rows render. Every row needs a matching key in `settings.lua`'s
    `implant_aliases`; the two are maintained together by hand.
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

Items and routes are kept distinct on purpose: a route's `RequireItemId` names an item, and giving both the same string would make logs and data impossible to read.

**One deliberate exception.** The 21 vanilla `PalPassiveSkillChange_Consumable_*` ids are *not* renamed. Those are the game's own disposable implants, and our routes point at them so an implant found in the world is still spendable. Minting parallel `LP_` items for them would silently break that.

### Mod registration, and why there is no off switch

**This section used to be wrong, in a way that matters. Read it before touching `mods.txt`.**

The two halves are registered by different mechanisms, and **only one of them has a switch**:

- The **Lua** half is gated by a line in UE4SS's `mods.txt` (`LootablePassives : 1`). A missing
  line means the same thing as `: 0` — deleting it does not help.
- …but `mods.txt` is not the only Lua path. UE4SS also starts any mod folder containing an
  `enabled.txt`, as a second pass, and says so in the log:
  `Starting mods (from enabled.txt (…\UE4SS\Mods), no defined load order)...`. `MapCollectablesNative`
  is registered that way. We do not ship one, so `mods.txt` governs us — but an `enabled.txt`
  dropped into the mod folder would start the Lua half regardless of the `mods.txt` line.
- The **PalSchema** half is gated by *nothing at all*. PalSchema loads every folder under its
  `mods/` directory. There is no registration to add and no flag to clear — if the folder is on
  disk, the data is live.

So setting `LootablePassives : 0` does **not** disable this mod. It disables half of it. Both
statements appear in the same `UE4SS.log`, seconds apart:

```text
[PalSchema] Loading mod: LootablePassives      <- the data half loaded anyway
Mod 'LootablePassives' disabled in mods.txt.   <- the Lua half did not
```

**The half-off state is worse than either on or off.** It is not a mod that does less; it is a mod
that does harm, because every route the data half publishes is still in the Surgery list and the
runtime that gives those routes their meaning is gone:

| Route | With Lua | Lua disabled, data live |
| --- | --- | --- |
| 61 module routes | module → the real passive | unchanged; vanilla handles these alone |
| 54 alias routes | module → alias → swapped to the real passive | **module and 1,000g spent; the Pal gets the inert `LP_Insert_*` alias and keeps it** |
| `LP_ExtractOne` / `LP_ExtractAll` | passive removed, module granted | **1,000g spent; the selected passive is replaced by an inert marker and no module is granted** |
| vanilla reprice to 5,000 | — | still applied; harmless |

The marker rows carry `RequireItemId: "None"`, so nothing gates them — vanilla will run the swap and
simply leave the marker sitting on the Pal. That is the one outcome the whole design exists to
prevent. Deriving from the data files, not observed in game; do not test it on a Pal you care about.

**Turning the mod off means removing files, not clearing a flag.** For a manual dev install, delete
both destinations (`install.ps1` lists them). Do not ship a build that relies on `mods.txt` as the
player-facing switch.

**This is the strongest argument for publishing to the Workshop**, and the reason it should happen
before the mod is shared any further. A Workshop package is installed by the official loader, which
records every file it copied in `Mods\ManagedMods\<PackageName>\InstallManifest.json` and removes
exactly that set when the mod is deactivated. Because both halves are declared in one `Info.json`,
they are installed and removed as one unit, and the in-game mod manager becomes a real off switch
for the whole mod. Nothing in the repo can reproduce that: a manual `install.ps1` install has no
`ManagedMods` entry at all, so the in-game manager cannot see it, and `PalModSettings.ini`'s
`ActiveModList` never mentions it.

## Commands

```powershell
node tools\luacheck.js       # Lua syntax check. Run after ANY Lua edit.
.\tools\install.ps1          # repo -> game install. The normal direction; run before every test.
.\tools\capture.ps1          # game install -> repo. Rescue only, for edits made in the game folder.
```

There is no data generator and no data verifier; see **The JSON is the source of truth** above
before reaching for one.
