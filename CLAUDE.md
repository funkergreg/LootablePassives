# CLAUDE.md

Guidance for Claude Code working in this repository.

---

## What the repository is

This repo contains a Palworld mod made to be published to the Steam workshop.  Behaviour and the design rationale, live in `README.md` under **What this mod does**, which is the user-facing description, and it is kept accurate; read it once before changing anything and change it if altering the mod behaviors. This file is primarily findings and repo setup; things that will help an agent as default context that are not stated directly in code.

### Repository layout

```text
Scripts/                         Lua runtime (main.lua, settings.lua, lp/*.lua); ships
PalSchemaMods/LootablePassives/  JSON data patches: items, DataTable rows, English strings; ships
tools/                           install.ps1, capture.ps1, luacheck.js, ledger_test.lua; these do not ship
docs/PLAN.md                     the working plan; does not ship
CLAUDE.md                        Agent guidance
README.md / LICENSE              the user-facing docs; these ship
Info.json                        Steam Workshop package manifest
thumbnail.png                    Workshop thumbnail; ships
```

**Why the PalSchema payload is nested two deep.** A Workshop `InstallRule` copies each `Targets` folder *with its name preserved* into the destination for its `Type`, and a PalSchema mod's folder name IS its mod id. A flat `PalSchema/` with `"Targets": ["./PalSchema"]` therefore installed as `PalSchema\mods\PalSchema` — silently renaming this mod's whole data half, and colliding with any other package that made the same mistake. `PalSchemaMods/LootablePassives/` is what makes the installed folder name come out right.

#### `PalSchemaMods/LootablePassives/`

- `items/` — the 94 mod-defined implant modules.
- `raw/` — DataTable patches. Four files, and the split matters:
  - `LootablePassivesOperation.json` — the two marker passives and their operations.
  - `LootablePassivesOperatingTable.json` — 61 module routes for passives with no vanilla row.
  - `LootablePassivesVanillaPrices.json` — reprices the 54 vanilla routes to 5000. **`Price` only.** Naming `RequireItemId` here would overwrite and thereby destroy the recipe gate.
  - `LootablePassivesInsertRoutes.json` — the 54 alias routes, plus the 54 inert alias passives that let those rows render. Every row needs a matching key in `lp/ids.lua`'s `IMPLANT_TARGET`; the two are maintained together by hand. A row with no key installs an inert alias and leaves it on the Pal; a key with no row is a dead list entry.
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

---

## Development

### Development Process

There is no build step, but there is a deploy step. **This repo is the working copy.** Edit here, run the checks, deploy to the game, restart, read the log.

```powershell
# ... edit in the repo: the JSON under PalSchemaMods\, the Lua under Scripts\ ...
node tools\luacheck.js            # Lua parse check
.\tools\install.ps1               # repo -> game install
# ... restart Palworld, read the log ...
```

Deploying is not optional and it is not automatic: the game loads only what is under `<Palworld>\Mods\NativeMods\UE4SS\Mods`, so an untested repo edit is just an untested repo edit. `install.ps1 -DryRun` first if you want to see what moves.

**`install.ps1` copies; it never deletes.** A file deleted from the repo goes on living in the game folder, and the game goes on loading it — so the thing you just "removed" keeps working, and the repo you are testing is not the thing under test. When you delete a runtime file here, delete it from the install too.

### Install

This is not a Workshop item yet, so the in-game mod manager cannot install it. Clone and run the
script:

```powershell
git clone https://github.com/funkergreg/LootablePassives.git && cd LootablePassives
.\tools\install.ps1
```

Then **restart Palworld** — UE4SS hot reload is disabled, so a running game will not pick it up.

If Palworld is somewhere other than the default Steam path:

```powershell
.\tools\install.ps1 -GameRoot "C:\path-to-games\Palworld"
```

Writing under `Program Files` may need an elevated shell.

#### What it copies, and where

```test
Scripts\                         ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\
PalSchemaMods\LootablePassives\  ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\
```

The script also adds `LootablePassives : 1` to UE4SS's `mods.txt`, which is what actually starts the
Lua half. PalSchema needs no registration — it loads any folder under its `mods/` directory.

Nothing is deleted, and files the mod writes at runtime are left alone.

### Uninstall

Delete **both** destination folders, then remove the `mods.txt` line. Modules already in a save
become unknown items; passives already implanted are real passives and stay put.

**That first claim now has a caveat, and it is not ours.** Unknown items are survivable because PalSchema strips them on load. On the 2026-09-20 build, PalSchema 0.6.7's signature scan for that cleanup fails and it says so: *"PalSchema will be unable to clean up invalid items and worlds with invalid items will crash on load."* Upstream 0.6.71 fixes it and has not reached the Workshop. Until it does, or until someone tests an uninstall with modules in a throwaway save, do not write anywhere player-facing that uninstalling is clean. See `docs/PLAN.md`.

> **Do not disable this mod by setting `LootablePassives : 0` in `mods.txt`.** That line controls
> only the Lua half. The PalSchema half has no such switch — it loads whenever its folder is on
> disk — so the mod's operations stay in the Surgery Table list with nothing behind them. Using one
> in that state costs you the gold and the module and leaves an inert placeholder passive on your
> Pal, in place of the passive you selected. Removing the folders is the only safe way off.

### Commands

```powershell
node tools\luacheck.js       # Lua syntax check. Run after ANY Lua edit.
luacheck Scripts             # The real static analyzer. Baseline is 0 errors.
lua tools\ledger_test.lua    # The one automated test. Run after ANY lp/ledger.lua edit.
.\tools\install.ps1          # repo -> game install. The normal direction; run before every test.
.\tools\capture.ps1          # game install -> repo. Rescue only, for edits made in the game folder.
```

`ledger_test.lua` is a behaviour test for one module, not a data verifier: it stubs `lp.inventory` and asserts the ledger's TSV round-trip and which candidate a row is delivered to. It exists because that logic is the only part of the mod with no engine call in it. There is still no data generator and no data verifier for the JSON; see **The JSON is the source of truth** above before reaching for one.

### CLI Development Tools

...via Scoop, installed to your user profile, no admin needed

- Lua 5.5 (lua, luac on PATH) — for quick local sanity checks
- luacheck 1.2.0 — a real static analyzer (undefined globals, unused vars, shadowing), stronger than this repo's tools/luacheck.js, which by its own comment is parse-only
- .luacheckrc — declares UE4SS's injected globals (RegisterHook, ExecuteInGameThread, FindAllOf, etc.) so luacheck stops flagging the mod's own API as "undefined"
- .luarc.json — same global list for LuaLS, so the in-editor LSP and the CLI checker agree `luacheck Scripts` from the repo root, alongside `node tools\luacheck.js`, in the normal edit/check/install loop. Without `.luacheckrc` it reports ~53 false positives from the unrecognised UE4SS globals; with it, only real findings.

The baseline is **0 errors** and a small number of cosmetic warnings (currently an unused hook argument that the callback signature requires, and one over-long line). Treat any new *error*, or a warning you did not just introduce, as something to fix rather than to note. Deliberately not recording an exact warning count here: the last one went stale within a day and then read as a verified fact.

### The JSON is the source of truth

The mod's data half is the JSON under `PalSchemaMods/LootablePassives/` and `Scripts/passive_items.lua`. Those are hand-maintained. **Edit them directly.**

What that costs, stated plainly: nothing validates the data at build time. PalSchema fails **silently** — a malformed file simply does not load, and a mismatch between the files that define the alias routes produces a dead list entry with no error anywhere a player would see it. Two things stand in for it now, and neither is as good:

- The **startup counts** line, which should read exactly: `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.` 115 = the 94 `LP_Implant_*` items plus the 21 vanilla PalPassiveSkillChange_Consumable_*` ones. A number that reads low means a half that did not load.
- Reading `UE4SS.log`, filtered on `[LootablePassives]` and on `PalSchema`.

The saving grace is that these tables are finished. Nothing in normal work should touch them.

### Reading the engine from Lua

Hard-won, each one from a crash or a wrong conclusion in this repo. Read before adding any engine call.

**`FName` needs `util.name_to_string()`, never `tostring()`.** `tostring` on an FName yields `FNameUserdata: 000001DF50F0E428`, which looks like output and carries nothing. A whole test run was wasted logging three ids that way.

**Measure, and know what the number is.** `invSlots=308` was quoted as inventory headroom and used to justify a design; it was the sum across all six `EPalPlayerInventoryType` containers, including key items and equipment. The real figure was 54 (`Common`, confirmed by `GetInventoryTypeFromStaticItemID` returning 0 and by watching which container's free count moved). Log the breakdown, not the aggregate, and name what is being summed. Never quote a count read by eye off a log — compute it.

**`pcall` does not catch a native access violation.** It catches Lua errors. A wrong-arity UFunction call, or engine code that dereferences null, takes the process down regardless. `StaticConstructObject` on `UPalIncidentBase` crashed the game with `EXCEPTION_ACCESS_VIOLATION reading 0x2a8` after being described as unable to crash because it "only constructs and inspects" — **construction runs engine code. It is not inspection.**

**Log immediately before each engine call in a probe.** One log line per call, so that if the game dies, the last line in `UE4SS.log` names the call. A probe that makes three engine calls between two log lines cannot be diagnosed after the fact, and the crash above could not be attributed to either of its two candidate calls.

**Take a widget from the hook context. Never go looking for one.** Every widget hook this mod owns is a method on the widget it wants, so UE4SS hands that object to the callback as its first argument, live by construction — `Update Button State` gives the tab page, `OnPassiveUpdate` gives the screen. `lp/ui.lua` records both and calls `FindAllOf` nowhere.

What that replaced: `FindAllOf("WBP_OperatingTable_TabPage_C")` followed by `IsVisible()` on each result, driven by the gate at a measured 1.4 passes a second for as long as the Surgery screen was open. `FindAllOf` returns every instance the object pool still holds, including pages from earlier openings that nothing is using, and calling a native method on one of those is the crash `pcall` cannot catch. The 2026-09-20 session went down with `EXCEPTION_ACCESS_VIOLATION reading 0x0000686374617340` — ASCII bytes, so freed memory reused for text — inside a Lua callback dispatched from an engine hook, with the Surgery screen open and no transaction having run. Not proven to be that scan. It was the largest exposure of that shape, it ran at frame rate, and it was removable. `delivery_candidates` still walks `FindAllOf("PalPlayerCharacter")`, because multiplayer needs every player; that is the remaining instance of the pattern and it is the other candidate for that crash.

**Never write to a widget that is not open.** The Surgery panel's whole refresh ladder is reset-to-empty calls, the widget instance is reused across openings, and `SetupPassiveChangeItem()` destroys and rebuilds all 118 entries from the screen's selected Pal. Applied to a closed panel — which `finish()`'s 500 ms and 1600 ms timers will do if the player shuts the screen after confirming — the result is sticky and the player cannot undo it from the UI. This is **not** the cause of the blank panel in `docs/double-trouble.png`: that panel appeared in a session where no transaction ran, so the ladder was never called. See `docs/PLAN.md`; the leading explanation there is that the Pal list was empty, which is vanilla behaviour. The rule stands on its own anyway.

Hence the two deliberately opposite biases in `lp/ui.lua`: the Edit gate and the targeted capture count a FAILED `IsVisible` as visible, because an unanswerable question must not veto a transaction path (the worst case is a button that is not greyed); the repair path demands a positive `IsVisible`, because it writes.

**A closure per call is a crash, not an inefficiency.** `pcall(function() ... end)` allocates a fresh Lua closure and a UE4SS registry ref every time it runs. On a hook that fires at frame rate that churn produced `Error: [Lua::Registry::get_function_ref] Ref was not function` followed by `EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff`, with a call stack entirely inside UE4SS. Everything on a per-frame path therefore uses argument-form `pcall` against a module-level accessor — `util.field`, `util.method`, and the `_call_`/`_index_` helpers — and every hook callback is built once, at load, and passed by reference. `main.lua`'s `coalescer()` and `hooks.lua`'s per-registration `entry.retry` exist for the same reason: a flag alone is not enough, because `ExecuteWithDelay(0, ...)` completes within the tick and the next firing would allocate again.

**`restore_replaced_passive` removes the marker before adding the passive, and the order is load-bearing.** `AddPassiveSkill(AddSkill, OverrideSkill)` does not reliably honour the override: it appended the passive and left the marker attached, which is how a Pal ended up carrying Infinite Stamina twice. It is also how the overwrite case crashed — a Pal whose four slots were full gained a fifth entry, and the passive panel has only four cards to index, which is why inserting into an *empty* slot never crashed. Removing first keeps the list from growing past what the UI can address. The trade is that a failed add leaves the Pal with neither, so every caller checks the result and the implant callers refund the module.

**Check arity against the header dumps, and not just `Pal.hpp`.** Widget functions live in `CXXHeaderDump/WBP_*.hpp`, CommonUI in `CommonUI.hpp`, engine in `Engine.hpp`. Prefer no-argument getters; avoid out-parameter overloads (`TryGetContainer(Out&)`) when a by-value equivalent exists (`GetContainer()`).

**"It is already in the codebase" is not evidence.** Much of this repo was written by agents and never executed. `GetPlayerCharacterByPlayerIndex` sat in `inventory.lua` looking established, on a branch that only runs in multiplayer and had almost certainly never run at all.

**Multiplayer is a first-class case, not a later port.** See *Multiplayer* above.

### Verifying behaviour

- **Verification Note:** Nothing that touches the engine has a unit test. The loop is: edit in the repo, run the checks, `install.ps1`, restart Palworld, read the log — filtering `UE4SS.log` on `[LootablePassives]`, and `%LOCALAPPDATA%/Pal/Saved/Crashes/` when it goes worse than that.
- **No hot reload.** `EnableHotReloadSystem = 0`; every Lua change needs a full restart. JSON does not hot-reload.

---

## Data constraints that shaped the design

These are properties of the game's tables, not choices this mod made. Breaking one produces a dead route with no error anywhere a player would see it.

- **A passive can own only ONE row in `DT_OperatingTablePassiveSkillDataTable`.** For the 54 passives whose row is already the vanilla recipe one, an extracted module had nowhere to be spent. That single constraint is the entire reason the `LP_Insert_*` alias routes exist; they are not a stylistic choice and cannot be flattened away.
- **Marker rows carry `RequireItemId: "None"`, so nothing gates them.** Vanilla will happily run the swap and leave the marker sitting on the Pal. Every protection against that is in the Lua half — see *Mod registration* below for what happens when only the data half loads.
- **Naming `RequireItemId` in the vanilla reprice file would destroy the recipe gate.** That file sets `Price` and nothing else, on purpose.
- **Module rarity tracks passive tier** — white for negatives, green/blue/purple ascending, orange for Diamond and World Tree. A convention, but an established one; match it.
- **`SortID` on the 94 modules is one contiguous block, `95001`-`95094`, ordered by rarity descending then English display name ascending.** Orange first. It is derived, so adding a module means recomputing the whole block rather than appending to it — the two alphabetical-by-id runs that came from appending are exactly why rarity used to scatter in the inventory. The 21 vanilla `PalPassiveSkillChange_Consumable_*` items keep vanilla's own `SortID`: their `Rarity` is not readable from the repo, so any block chosen for them risks putting an orange module in the purple run.

### Invariants worth preserving

Each of these is load-bearing for either the economy or crash-safety.

- **Extraction never hands back a reusable recipe.** Extracting a recipe-generated passive yields a single-use module, never a permanent Key Item, or the bounty-token economy collapses.
- **Grant before remove.** The module is created *before* the passive is removed, and the recovery journal replays an interrupted exchange on the next load. Given a choice the mod duplicates an item rather than destroying a passive.
- **Vanilla's overwrite behaviour is untouched.** An overwritten passive is gone and yields no item. Do not "fix" this; it is the game's rule.

### The conveyor, and the two things that are not obvious

`Scripts/lp/conveyor.lua` is implemented and tested. Its header carries the detail; these are the parts that look like dead weight and are not.

- **Both hooks are required, and the pass must not be throttled.** The progress watcher and the arrival/departure watcher each miss cases the other catches.
- **Progress rate is the consumed-versus-withdrawn test, and must not be replaced with an existence test.** Measured: a Pal that was consumed reports 1.000–1.014; a Pal withdrawn by the player reports 0.217–0.383. An existence test cannot tell those apart, and getting it wrong pays out modules for Pals the player took back.

### Item creation: the engine spills, and that is the answer

`AddItem_ServerInternal` is the only item-creation call in the reflected API. Five other mechanisms for placing an item in the world were tried and all are dead ends; `docs/PLAN.md` lists them so they are not retried.

The important discovery is that **a full bag is not a failure case**. `AddItem_ServerInternal` returns Success and the engine drops the item on the ground. So:

- **Success means created.** Treating a ground-spill as a failure is what caused a real duplication bug: the debt stayed owed, was retried, and paid out extra copies.
- Degradation is per-item, not all-or-nothing. With zero free slots a module that stacks onto one already held still fits, while a new type spills. Observed interleaved in a 54-Pal run.

### Edge Cases and Limitations

- Matching the machine's own output position was not achievable with the interfaces the game exposes to mods through UE4SS or PalSchema (may be possible with Unreal Engine modding).
- **A full bag does not stop extraction.** Modules that cannot fit drop on the ground, at your feet, which means they are subject to the usual world-item despawn timer or others picking these up. A module that stacks onto one you already hold still fits.
- **Modules owed when you quit are paid on your next load.** If the game closes mid-disassembly the debt is recorded to disk and delivered when you load back in, usually before you touch anything.  A hard crash at the wrong instant can still lose an in-flight module.

### Multiplayer

**Multiplayer is a first-class case, not a later port.** `find_inventory(nil)` resolves a player only when `state_count == 1`, so it returns nil with two players connected. Any base-camp feature needs a stated rule for *which* player receives something, or a mechanism that does not need one.

Gating is `AActor::HasAuthority()` (0-arg) for server/client, `APawn::IsLocallyControlled()` to identify the host.

**The conveyor's rule is the Pal's owner, and it holds rather than substituting.** `FPalIndividualCharacterSaveParameter.OwnerPlayerUId` is snapshotted with the passives — the last moment the Pal exists to be asked — and compared against `PlayerUId` on `APalPlayerState`. The pending ledger (`LPL2`) is keyed by owner and item for that reason: a row with a known owner goes to that owner and to nobody else, and waits on disk when they are offline. Ranking `IsLocallyControlled()` first instead, which is what it used to do, meant a modded host collected a guest's modules for every Pal the guest queued.

**"Only deliver to a player who has the mod" is not implementable.** UE4SS Lua has no custom network channel and nothing exposes a peer's loaded DataTables, so no peer can be asked. Do not write code, comments or docs that imply otherwise. Owner-first is the approximation, and its cost — a modless owner receiving items their game renders blank — is accepted and documented in `README.md`.

**An unmodded host cannot receive modules at all**, so that failure mode does not need designing around: the mod is not running there, and the one peer that creates items gates on `HasAuthority()`.

**Tested, on real hardware: host has the mod, client does not.** Extraction and disassembly worked for the host, the game was stable for both, and items the client could not resolve rendered as blank entries in a shared chest rather than crashing anything. Asymmetric installs are therefore survivable, which is what the Workshop description promises.

**Still untested, and do not write as if it were:**

- **The authority gate's negative case.** The client in that test had no mod at all, so no non-authoritative peer has ever *run* this code. The `HasAuthority()` false branch is unexercised.
- **A client that has the mod installed.**
- **Dedicated-server operation.**

---

## Rules for code comments

The comments in `Scripts/` were rewritten in one pass on 2026-09-20 to follow these rules, after an agent read a comment as authority over the instructions it had been given in `docs/PLAN.md` and made the wrong change. Several of the claims it trusted were also simply untrue — one asserted that `EnabledButton = false` produced the game's greyed-out look, which was never verified and which the widget's own header contradicts.

So a comment in this repo describes the code. It does not vouch for the game.

- **Say what the code does**: what it reads, writes, calls, returns, in what order, and what it returns instead on failure.
- **API facts are allowed where a header dump backs them** — arity, out-parameters, property versus call, a `WBP_*.hpp` line number. Those are checkable without launching anything.
- **No claims about in-game behaviour.** Not "the player sees", not "vanilla will", not "this works". If behaviour has been observed, it is a finding and belongs in this file or in `docs/PLAN.md`, with its provenance attached.
- **No evidence in comments.** No log timestamps, session references, screenshot numbers, or "measured". Those aged badly and read as proof of things nobody had checked.
- **No design intent or future plans.** That is `docs/PLAN.md`'s job, and a comment that disagrees with the plan must not be able to win.

The order of authority is: the prompt, then `docs/PLAN.md`, then this file, then comments. A comment is the weakest of the four and should never be the only place a fact lives.

When editing comments only, prove it: parse the file before and after and compare the syntax trees. `node_modules/luaparse` is already present for `tools/luacheck.js`, and 15 files were verified that way in the pass above.

## Rules for Markdown

- Follow markdown list standard formatting rules: spaces before and after test blocks.
- Use headings instead of bolding sections to give the document correct depth and ordering
- DO NOT cut lines with newline characters for pages -- let normal word wrap handle appropriate display length; this best keeps markdown files view and platform-independent
