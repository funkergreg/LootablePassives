# Plan

Below are planning goals; this document is a living document intended to catch ephemeral knowledge subject to change on any edit.  Keep this planning document iself updated to:

- align this document to code as code is changed
- point to WHERE something happens in code; DO NOT replicate the content of the code (since this may become stale on successive edits)
- incorporate new design elements, consistent with other items remaining in the plan (check for conflicts on adding to this document)

---

## Invariants worth preserving in design

- **Extraction must never hand back a reusable recipe.** Extracting a recipe-generated passive yields a single-use disposable implant.
- **Grant before remove.** The disposable implant is created *before* the passive is removed, and the recovery journal replays an interrupted exchange on the next load. Given a choice the mod duplicates an item rather than destroying a passive.
- **Vanilla's overwrite behaviour is untouched.** An overwritten passive is gone and yields no item. Do not "fix" this; it is the game's rule.
- **Multiplayer is a first-class case, not a later port.** `find_inventory(nil)` resolves a player only when `state_count == 1`, so it returns nil with two players connected. Any base-camp feature needs a stated rule for *which* player receives something, or a mechanism that does not need one. Gating is `AActor::HasAuthority()` (0-arg) for server/client, `APawn::IsLocallyControlled()` to identify the host.
  - **Tested, on real hardware: host has the mod, client does not.** Extraction and disassembly worked for the host, the game was stable for both, and items the client could not resolve rendered as blank entries in a shared chest rather than crashing anything. Asymmetric installs are therefore survivable, which is what the Workshop description promises.  Other configurations, including dedicated server, are untested.

---

## Improvements (TODOs)

### Simplification Finds

Worked through; nothing in this section is open. The changes that were applied are described by the code's own comments — what is kept here is the reasoning for the three that were **not** made, so they are not proposed again.

Applied:

- **Dead path in `recovery.lua`.** The marker was read as `journal.lock ~= "" and journal.lock or marked[1].lock`, but `read_journal` produces no `lock` column, so only the third branch was ever taken. Simplified to the behaviour it already had. If the journal's recorded marker was meant to be authoritative that is a real bug and a `/code-review` matter, not a cleanup.
- **UI policy left `finish()`.** `finish` in `lp/transaction.lua` now logs and calls `ui.on_transaction_complete(mode)`; the arming and both timers moved into `lp/ui.lua` unchanged. The 500 ms / 1600 ms ladder is not restructured — the worry that stopped this before was about redesigning it, and a move is not a redesign. The three timer callbacks are now built once at load rather than per transaction, and `arm_refresh` and `refresh_surgery_ui` are no longer exported, because nothing outside `ui.lua` calls them.
- **`extract_additional`'s journal churn**, which turned out to be covering a hole. Its own section below.

Closed without changing code:

- **Bounding the conveyor's snapshot-miss re-walk.** The retry is already bounded by the queue: a key is re-walked only while it is still in `ConvertProcessArray`, which is the few seconds that Pal spends converting. Giving up after N frames would drop that Pal's debt and pay out nothing, against the mod's own grant-before-remove bias. Not worth a behaviour change.
- **Caching `before_counts` on snapshots.** The lists being counted are passive lists: four slots plus a marker, so `counts()` builds a five-entry table. The saving is a few tiny allocations per snapshot per attempt, on a path that runs twelve times at 250 ms apart, and the price is a new signature on `detect_replaced_passive` and `detect_added_lock` — the two predicates that decide whether a transaction was ours at all. Wrong trade.
- **`recovery.schedule_recovery`'s per-call closures.** Two closures, twice a session. The rule in DEV Tips is about per-frame paths.

### CTD: access violation in a Lua callback, Surgery screen open, conveyor running -- CLOSED, unreproduced

**Closed on 2026-09-21, one occurrence, never reproduced.** The suspect with by far the highest exposure -- a `FindAllOf` widget scan running 1.4 times a second for as long as the Surgery screen was open -- was deleted, and sessions since have run the conveyor and the Surgery screen together without incident. The save this was seen on cannot produce the conditions again on demand, so there is nothing further to run. The account below is kept because it is the only record of it.

**Reopen if it recurs**, and these are the first three moves: set `surgery_ui_gate = false`, which removes every read the gate makes while leaving transactions working; run with only this mod and PalSchema loaded, since five Lua mods were live and the dump could not be attributed to any of them; and set `FullMemoryDump = 1` in `UE4SS-settings.ini` before trying, because the dump that exists is minimal. Note also that `bUseUObjectArrayCache` is already `false` on this install, so a stale UE4SS object cache is not available as an explanation -- whatever `FindAllOf` returned was in the live object array.

Three object-pool scans remain, and they are where to look: `find_player_state` and `delivery_candidates` in `lp/inventory.lua`, and `snapshot_all` in `lp/passives.lua`. Only `delivery_candidates` runs on the conveyor path.

Session of 2026-09-20 19:32-19:36. Sort order verified in two base containers, including after moving modules between them and re-sorting. Twenty-five Pals disassembled over about thirty seconds. Player left the disassembly menu with Pals still on the conveyor, opened the Surgery Table, and the game went down with `EXCEPTION_ACCESS_VIOLATION reading address 0x0000686374617340` with no further interaction.

What the crash dump says: thirty-seven consecutive `UE4SS` frames below `Palworld_Win64_Shipping` frames that are the engine invoking a hooked function. That is an engine hook dispatching into Lua, and the fault is inside UE4SS's own object machinery. The address is not a pointer that went slightly wrong -- its bytes are ASCII (`40 73 61 74 63 68`) -- which is what reading a freed object looks like once something else has reused the memory for text. Five Lua mods were loaded, so the dump does not by itself say the callback was ours.

What the mod's own log says, and this is the part that narrows it: **no surgery transaction ran in the entire session.** No `Extracted`, no `Implanted`, and none of the refresh diagnostics. So while the Surgery screen was open the only code of ours that ran was the Edit-button gate on the `Update Button State` hook, and the conveyor watchers. The last line in the log is a completed disassembly at 19:36:48.4, with consumptions arriving every 1.7 seconds before it -- so the next one was due about when the process died.

Two candidate sites, both ours, neither proven:

- The gate scanned the object pool with `FindAllOf("WBP_OperatingTable_TabPage_C")` and called `IsVisible()` on the results, at a measured 1.4 passes a second for as long as the screen was open. `FindAllOf` returns instances from earlier openings of the screen that nothing is using any more.
- Delivery walks `FindAllOf("PalPlayerCharacter")` and calls `GetPalPlayerController()` on each result, once per consumed Pal. Same shape, lower frequency -- and it had just succeeded twenty-five times.

Both are guarded with `is_valid`, which is UE4SS's own bookkeeping and is supposed to answer for exactly this. If it is reliable neither should fault; if it is not, both can.

**What changed: the widget scan is gone.** Every hook this mod owns is a method on the object it wants, so UE4SS hands that object to the callback as the context argument, live by construction. `Update Button State` gives us the tab page; `OnPassiveUpdate` gives us the screen. Both are recorded, validated with `is_valid` before use, and dropped on map load. Nothing in `lp/ui.lua` calls `FindAllOf` any more -- the gate, the targeted capture and the panel refresh all read what the engine handed us. This removes our highest-frequency touch of a possibly-dead object, it removes reliance on `is_valid` for objects we never got from the engine, and it retires the `find_visible_tab_page` caching item below by deleting the thing that would have needed caching.

The player scan in `delivery_candidates` stays: removing it would break multiplayer, which needs every player, and it is not the frequent one.

**Two things to make the next crash attributable**, because the last log line named a completed operation and therefore said nothing about what was running:

- `settings.lua` gains `surgery_ui_gate`. Set it to `false` and the mod stops touching the Surgery widget entirely while still recording it, so extraction, insertion and the repaint all work and only the courtesy greying of the Edit button is lost -- every rule it enforces is enforced again at the transaction. If the crash survives that, it is not the gate.
- The conveyor logged one line *before* delivering as well as after, so that a line with no summary after it would localise a crash to the delivery. Removed on closing, as that entry said it should be.

If it reproduces: the log plus `%LOCALAPPDATA%/Pal/Saved/Crashes/` is what to send, and `surgery_ui_gate = false` is the first thing to try.

**Background worth knowing before blaming this mod.** Five Lua mods were live, and PalSchema 0.6.7 failed two signature scans on this game build -- see the entry below, which has a fix. Neither explains an access violation while a menu opens, and the signature failures are about loading a world rather than about running one, but both belong in a bug report.

### PalSchema 0.6.7 fails two signature scans on this build -- fixed upstream in 0.6.71, not yet on the Workshop

From the 19:36 log:

```text
[PalSchema] [error] Failed to find signature for CraftItemCount_ApplyDataMapReturn.
[PalSchema] [error] Failed to find signature for FPalPlayerRecordDataRepInfoArrayThreadSafe_IntVal::ApplyDataMap.
[PalSchema] [error] Signature for FPalPlayerRecordDataRepInfoArrayThreadSafe_IntVal::ApplyDataMap could not be found.
                    PalSchema will be unable to clean up invalid items and worlds with invalid items will crash on load.
```

Nothing to do with other mods, and disabling them cannot help. A signature scan is a byte-pattern search for a function inside `Palworld-Win64-Shipping.exe`; a game patch recompiles that code and the pattern stops matching. It is PalSchema versus the game build, and only PalSchema can fix it.

**It already has.** PalSchema `0.6.71`, released 2026-09-09, whose entire changelog is `Fixes - Updated signatures`, and which is built for UE4SS `2281fa31` -- the commit already installed here, so nothing else has to move. The installed and subscribed copy is `0.6.7` (2026-09-04). The Steam Workshop item's own changelog ends at `Sep 4`, so the author has not pushed 0.6.71 there; this is not a sync failure on one machine, and every Workshop subscriber is in the same position.

Routes, in order of preference: wait for 0.6.71 to reach the Workshop; ask the author to push it; or drop the 0.6.71 `main.dll` over `Mods\NativeMods\UE4SS\Mods\PalSchema\dlls\main.dll` by hand, which works until the mod manager reinstalls the package and is fine for a test. It is available from GitHub releases and from Nexus.

**Why this mod cares, beyond tidiness.** Invalid-item cleanup is what makes an item id that no longer exists survivable in a save, and this mod's whole uninstall story rests on it: pull the mod and every `LP_Implant_*` in the save becomes exactly that. `CLAUDE.md` and the Workshop description both say those simply become unknown items. On 0.6.7 against this build, PalSchema says the cleanup is off and such a world crashes on load instead. That claim is untested either way here, and testing it means deliberately orphaning modules in a throwaway save. Until it is tested or 0.6.71 lands, do not publish a description that promises a clean uninstall.

This is also the likeliest reading of the multiplayer test, where the guest without the mod saw blank chest entries and did not crash: those items were in the host's world, not in the guest's own save.

#### Panel repaint: dead ends, so they are not retried

`lp/ui.lua` resets the panel rather than repainting the passive cards. Four approaches were tried first and none of them works; the file points here rather than carrying the list.

- `ReflectPassiveChange`, `RefreshCurrentPassiveItem` and `RefreshItemDisplay`, called on the page and the screen, do not repaint the slots on their own. They are still called as part of the reset, where they are cheap and harmless.
- `On Click Pal List` with the screen's own `CurrentHandle` executes -- it reported `reselect=true` -- and the stale label stays. Re-selecting the Pal that is already selected is evidently a no-op inside the Blueprint, which is why clicking to a *different* Pal and back is what works by hand.
- Writing the cards directly with `SetPassiveSkill` / `Clear` is worse. The calls succeed (`cleared=4 failed=0`) but `Clear()` leaves a card blank instead of showing the empty `+` slot, and the cards are reused across Pal selections, so every Pal afterwards showed an empty panel. The empty state is its own visual -- the card has an `Anm_EmptySlot_HideToShow` animation -- and `Clear()` does not reach it.
- Diagnosing staleness from `BindedPassiveSkillName` does not work either: it was correct while `Text_SkillName` was stale, so the card data agreed with reality the whole time and only the paint was wrong.

### The Edit button stays lit on a refused operation -- CLOSED, a documented limitation

The gate refuses the click and that is all it does. `SetIsInteractionEnabled(false)` on the inner `CommonButtonBase` is never touched by the Blueprint, so it holds for as long as the block lasts: the click does nothing and no gold is charged. This is the part that protects the player and it works in every case.

`EnabledButton` is not written, and **reintroducing that write is a regression.** The property belongs to the Blueprint. `Update Button State` recomputes it from scratch on a hook that fires for as long as the screen is open, and this module can only write it after that has run. Where the game's own verdict agreed the button should be off the write stood and the button greyed; where the game judged the selection usable -- an empty slot with an extract route, since vanilla has no notion of extraction -- the two writes alternated and the button flickered at hook rate. Flickering is worse than lit, and the greying that was lost with the write only ever worked where the game was going to refuse anyway.

Three variants were tried and measured in play, and none of them is worth retrying:

- writing it only when it read enabled: greyed the uncontested cases, flickered the contested ones
- writing it on every blocked pass: flickered the contested ones *and* cost the uncontested ones their grey
- writing it until the game had overridden it a set number of times: restored the uncontested grey, did not stop the flicker

What the probe established along the way, so it is not re-derived: of sixteen properties read across the button, its label and the panel's three warning widgets, **not one** differs between the game's allow and refuse states except `EnabledButton` itself. `Text_Warning` stays collapsed in both -- it was the standing first guess and it is wrong. `bIsEnabled` reads true on both buttons in both states, which rules out `SetIsEnabled` and CommonUI's `DisabledStyle`. `Text_Main.RenderOpacity` reads 1.0, 0.7, 0.5 and values in between as the button animates, and tracks the route and the animation rather than any verdict.

The limitation is in `README.md` under Surgery Table, and in `block_edit`'s comment. `describe_button_state` and `sample_button_paint` are deleted.

### `extract_additional` journal churn -- done, and it was covering a hole

The per-passive `clear_journal()` was redundant against the next iteration's `write_journal`, which opens `"w"`. Taking it out exposed what the *last* one had been doing: on any Pal with something to sweep, it wiped the outer `granted/marker` row before phase three tried to remove the marker. So the failure message there -- "the journal is kept so the marker is cleaned up on the next map load" -- was false, and a crash in that window left an inert marker on the Pal with nothing recorded that would remove it.

As it stands now: `extract_additional` clears nothing; `finalize_extraction` writes the outer `granted/marker` row back when the sweep returns; and `lp/recovery.lua`'s `loop`/`granted` branch no longer fails when the passive it names is already gone, because that row now stands for the whole gap between passives and the marker's removal is what decides the outcome. Reasoned from the call order in `lp/transaction.lua` and the count-based return of `inventory.remove_skill`; it is not reachable by an in-game test that does not crash the process at an exact instant.

### Publish to the Steam Workshop (DO NOT START UNTIL TESTING IS GOOD, CODE CLEANED, AND DOCS UPDATED)

#### Facts established (uploader docs + installed packages on disk)

- `InstallRule.Targets` copies each named folder **with its name** into the destination for its `Type`. `Lua` → `Mods\NativeMods\UE4SS\Mods\<PackageName>`; `PalSchema` → `Mods\NativeMods\UE4SS\Mods\PalSchema\mods`; also `UE4SS`, `LogicMods`, `Paks`. This is why the payload is `PalSchemaMods/LootablePassives/`.
- `Info.json` is correct as it stands: `PackageName` `LootablePassives`, `DebugMode: false`, four `InstallRule`s (client + `IsServer` for both types), Tags all legal, and `Dependencies` `["UE4SSExperimentalPW", "PalSchema"]` — **both verified against the installed packages' own `Info.json`** at `steamapps\workshop\content\1623730\3625223587` and `…\3625280368`.
  Nothing asserts this automatically any more; it is checked by reading it.
- The uploader validates three things only: the JSON parses, `PackageName` is non-empty alphanumeric, and ≥1 `InstallRule` has `Type` and `Targets`. An illegal `Type`, a missing `Targets` path, an illegal `Tag`, an unresolvable `Dependency` — all upload cleanly and then fail to install silently. Nothing validates this now -- step 6 below, installing from the Workshop into a clean game folder, is the only thing that catches it.
- `MinRevision` is "the last 5 digits of the version shown in the title". It is not readable from the exe or the manifests on disk (checked) — read it off the title screen of the build actually tested. Currently `82182`, which matches both dependencies.
- `Version` is compared as a plain string; any change makes the loader uninstall and reinstall the mod folder. This is why the recovery journal lives at the UE4SS root, outside the managed tree.
- The uploader is GUI-only — no CLI — so the upload click cannot be scripted. **Do not subscribe to your own item:** subscribed packages are view-only and can no longer be updated from that machine.
- rewrite **Install** once the mod is a Workshop item, keeping `install.ps1` as the dev/manual path.

#### `tools/stage.ps1` -- written

The repo cannot be uploaded in place: Steam UGC uploads the item folder recursively, so without a staging step every subscriber downloads `.git/`, `tools/` and `docs/`. `tools/stage.ps1` copies an allowlist -- `Info.json`, `thumbnail.png`, `README.md`, `LICENSE`, `Scripts/`, `PalSchemaMods/LootablePassives/` -- into the numbered item folder, and nothing else, so a new top-level folder in the repo cannot leak by default.

It takes `-ItemId` (resolved against the path the uploader recorded in its own `workshop_path.txt`) or `-Destination`, plus `-DryRun` and `-Force`. It mirrors, on the same rule as `install.ps1`: a file in the item folder that the package does not have stops the run before anything is copied, because that file would be uploaded to every subscriber. `.workshop.json` is the uploader's and is never written, deleted, or counted as stale.

Four checks run before it copies, all of them for failures the uploader lets through and that then produce nothing at all: `Info.json` parses; `PackageName` is non-empty and alphanumeric; every `Tag` is one of the six the platform defines; every `InstallRule` `Type` is one of the five the loader knows and every `Targets` path, plus `Thumbnail`, resolves inside the staged set rather than merely inside the repo. It also refuses a folder already holding a different `PackageName` unless forced, and warns when `Version` matches the last upload recorded in `.workshop.json`.

Tested against a simulated item folder: the stale check caught a planted file, `-Force` removed it, `.workshop.json` survived, and the staged `Scripts/` and `PalSchemaMods/LootablePassives/` came out identical to the repo with nothing else present.

#### Pocketpair's mod guideline -- read, and it is not a gate

The guideline is not the HTML page the EULA site appears to serve. `eula.pocketpair.jp/palworld-mod-guideline` redirects to `guideline.palworldgame.com`, a JavaScript app whose only content is a PDF per language at `/guideline-pdf/palworld/mod_20260708_<lang>.pdf` -- `mod_20260708_en.pdf` for English. Anyone re-reading it later should fetch the PDF directly rather than the page.

It is short and it is permissive. There is **nothing about monetisation, nothing requiring an "unofficial" label, and no list of prohibited mod types**. Nothing in it touches what this mod does. The three things it does ask of an author: follow the distribution platform's own terms, do not infringe third-party rights -- it names characters, models, textures, audio, fonts, logos and illustrations *from other works* -- and accept that a game update may break the mod. This mod ships no assets at all, only JSON and Lua, so the middle one is satisfied by construction.

Two things in it changed the docs rather than the code:

- **Mods on official servers are prohibited outright**, with account suspension named as a possible consequence, and disruptive mod use on unofficial servers may also be acted on. Nothing in this repo said so. `README.md`'s Multiplayer section now opens with it, and the Workshop description must carry it too.
- **Its own uninstall guidance is more cautious than this repo's was.** Pocketpair say that turning a mod off is not always enough, that files left in the game folder may still load, and that a save loaded with mods can keep showing problems afterwards. That is the vendor's position on all mods, and it sits more comfortably with the PalSchema `0.6.7` cleanup question than any promise of a clean uninstall would. `README.md` now has an Uninstall section that states the vendor's guidance and then says plainly what this mod leaves behind: implanted passives are real passives and stay, and disposable implants in an inventory refer to items that no longer exist.

There is no acceptance step and no submission -- reading it is the whole of the obligation.

#### Release checklist

0. **CLEAN CODE** -- done as far as reading finds anything. The two Surgery probes, the conveyor's pre-delivery trace line and the `TODO` markers are gone; `settings.lua` holds two switches, `conveyor_extraction` and `surgery_ui_gate`, both of which are player-facing controls rather than dev leftovers. Re-read before uploading rather than trusting this line.
1. `node tools\luacheck.js` and `luacheck Scripts` green, `lua tools\ledger_test.lua` passing; `install.ps1`; restart; confirm the startup counts line reads `115 extractable passives, 2 extraction operations, 54 insert routes`; exercise Extract One, Extract All, an insert, a duplicate-blocked insert, and the conveyor. This is the one deliberate pass, not an incidental one during some other test.
2. DONE. `MinRevision` is `102999` and `Version` is `1.0.0`; `DebugMode` was already `false`. The floor is the build the mod has actually been tested on rather than the `82182` the dependencies declare, which asserts a compatibility nobody has checked, and a first publication to Steam reaches nobody who is on an older build. `README.md`'s Requirements line matches. Bump `Version` on every later upload -- the loader compares it as a plain string, so an unchanged one is not seen as an update at all.
3. DONE. See the guideline section above.
4. Write the Workshop description. It must carry: both dependencies with their Workshop ids (`3625223587`, `3625280368`); the dedicated-server `WorkshopRootDir` and `ActiveModList=LootablePassives` note from `Mods\PalModSettings.ini`; **the prohibition on mods on official servers**, which the guideline requires and which `README.md` now leads its Multiplayer section with; and an uninstall note no stronger than `README.md`'s, which describes what this mod leaves behind without promising more than Pocketpair's own guidance does.
5. `Create New Mod` (Lua) in the uploader to mint the folder and its Published ID, `tools\stage.ps1 -ItemId <id> -DryRun` and then for real, upload **private**.
6. Verify by installing from the Workshop into a clean game folder -- not the dev install, which already has the files. Then make it public.

#### Notes on Mod activation

**IMPORTANT:** This Section must be deleted once workshop publishing is complete as information would be OBE

**This section used to be wrong, in a way that matters. Read it before touching `mods.txt`.**

The two halves are registered by different mechanisms, and **only one of them has a switch**:

- The **Lua** half is gated by a line in UE4SS's `mods.txt` (`LootablePassives : 1`). A missing
  line means the same thing as `: 0` — deleting it does not help.
- …but `mods.txt` is not the only Lua path. UE4SS also starts any mod folder containing an `enabled.txt`, as a second pass, and says so in the log: `Starting mods (from enabled.txt (…\UE4SS\Mods), no defined load order)...`. `MapCollectablesNative` is registered that way. We do not ship one, so `mods.txt` governs us — but an `enabled.txt` dropped into the mod folder would start the Lua half regardless of the `mods.txt` line.
- The **PalSchema** half is gated by *nothing at all*. PalSchema loads every folder under its `mods/` directory. There is no registration to add and no flag to clear — if the folder is on disk, the data is live.

So setting `LootablePassives : 0` does **not** disable this mod. It disables half of it. Both statements appear in the same `UE4SS.log`, seconds apart:

```text
[PalSchema] Loading mod: LootablePassives      <- the data half loaded anyway
Mod 'LootablePassives' disabled in mods.txt.   <- the Lua half did not
```

**The half-off state is worse than either on or off.** It is not a mod that does less; it is a mod that does harm, because every route the data half publishes is still in the Surgery list and the runtime that gives those routes their meaning is gone:

| Route | With Lua | Lua disabled, data live |
| --- | --- | --- |
| 61 module routes | module → the real passive | unchanged; vanilla handles these alone |
| 54 alias routes | module → alias → swapped to the real passive | **module and 1,000g spent; the Pal gets the inert `LP_Insert_*` alias and keeps it** |
| `LP_ExtractOne` / `LP_ExtractAll` | passive removed, module granted | **1,000g spent; the selected passive is replaced by an inert marker and no module is granted** |
| vanilla reprice to 5,000 | — | still applied; harmless |

The marker rows carry `RequireItemId: "None"`, so nothing gates them — vanilla will run the swap and simply leave the marker sitting on the Pal. That is the one outcome the whole design exists to prevent. Deriving from the data files, not observed in game; do not test it on a Pal you care about.

**Turning the mod off means removing files, not clearing a flag.** For a manual dev install, delete both destinations (`install.ps1` lists them). Do not ship a build that relies on `mods.txt` as the player-facing switch.

**This is the strongest argument for publishing to the Workshop**, and the reason it should happen before the mod is shared any further. A Workshop package is installed by the official loader, which records every file it copied in `Mods\ManagedMods\<PackageName>\InstallManifest.json` and removes exactly that set when the mod is deactivated. Because both halves are declared in one `Info.json`, they are installed and removed as one unit, and the in-game mod manager becomes a real off switch for the whole mod. Nothing in the repo can reproduce that: a manual `install.ps1` install has no `ManagedMods` entry at all, so the in-game manager cannot see it, and `PalModSettings.ini`'s `ActiveModList` never mentions it.

---

## Data constraints that shaped the design

These are properties of the game's tables, not choices this mod made. Breaking one produces a dead route with no error anywhere a player would see it.

- **A passive can own only ONE row in `DT_OperatingTablePassiveSkillDataTable`.** For the 54 passives whose row is already a vanilla recipe, an extracted module could be tied to a recipe in key items creating a duplicate; the `LP_Insert_*` alias routes exist to prevent that.
- **Marker rows carry `RequireItemId: "None"`, so nothing gates them.** Vanilla will happily run the swap and leave the marker sitting on the Pal.
- **Naming `RequireItemId` in the vanilla reprice file would destroy the recipe gate.** That file sets `Price` and nothing else, on purpose.
- **Module rarity tracks passive tier** — white for negatives, green/blue/purple ascending, orange for Diamond and World Tree. A convention, but an established one; match it.
- **`SortID` on the 94 modules is one contiguous block, `95001`-`95094`, ordered by rarity descending then English display name ascending.** Orange first. It is derived, so adding a module means recomputing the whole block rather than appending to it — the two alphabetical-by-id runs that came from appending are exactly why rarity used to scatter in the inventory. The 21 vanilla `PalPassiveSkillChange_Consumable_*` items keep vanilla's own `SortID`: their `Rarity` is not readable from the repo, so any block chosen for them risks putting an orange module in the purple run.

---

## Item creation: the engine spills, and that is the answer

`AddItem_ServerInternal` is the only item-creation call in the reflected API. Five other mechanisms for placing an item in the world were tried and all are dead ends.  The important discovery is that **a full bag is not a failure case**. `AddItem_ServerInternal` returns Success and the engine drops the item on the ground. So:

- **Success means created.** Treating a ground-spill as a failure is what caused a real duplication bug: the debt stayed owed, was retried, and paid out extra copies.
- Degradation is per-item, not all-or-nothing. With zero free slots a module that stacks onto one already held still fits, while a new type spills. Observed interleaved in a 54-Pal run.
- **Modules owed when you quit are paid on your next load.** If the game closes mid-disassembly the debt is recorded to disk and delivered when you load back in, usually before you touch anything.  A hard crash at the wrong instant can still lose an in-flight module.
- Matching the machine's own output position was not achievable with the interfaces the game exposes to mods through UE4SS or PalSchema (may be possible with Unreal Engine modding).

---

## Multiplayer test result (2026-09-19)

Run on real hardware, two machines: **host has the mod, joining client does not.**

- Game stable for both players; no crash on either side.
- Extraction and disassembly worked normally for the host.
- Items the client's game cannot resolve render as **blank entries** in a shared chest.  Confirms the prior assumption. Viewing them does not crash the client.

This proves asymmetric installs are survivable, and the Workshop description can say so. What this does **not** establish, and must not be written as if it did: the client had no mod at all, so **no non-authoritative peer has ever run this code**. The `HasAuthority()` false branch remains unexercised. Also still untested: a client that *has* the mod, and dedicated-server hosting.  This can only come after publishing to the steam workshop due to resource constraints in testing; the mod will be testes on a Steam Machine console which can download and activate the mod from the workshop.

---

### DEV Tips

Each item below caused a crash or a wrong conclusion in this repo.  These indicate known problem areas where extra care must be taken, though these may not remain relevant to later designs.

- **`FName` needs `util.name_to_string()`, never `tostring()`.** `tostring` on an FName yields `FNameUserdata: 000001DF50F0E428`, which looks like output and carries nothing. A whole test run was wasted logging three ids that way.
- **`pcall` does not catch a native access violation.** It catches Lua errors. A wrong-arity UFunction call, or engine code that dereferences null, takes the process down regardless. `StaticConstructObject` on `UPalIncidentBase` crashed the game with `EXCEPTION_ACCESS_VIOLATION reading 0x2a8` after being described as unable to crash because it "only constructs and inspects" — **construction runs engine code. It is not inspection.**
- **Log immediately before each engine call in a probe.** One log line per call, so that if the game dies, the last line in `UE4SS.log` names the call. A probe that makes three engine calls between two log lines cannot be diagnosed after the fact, and the crash above could not be attributed to either of its two candidate calls.
- **Take a widget from the hook context. Never go looking for one.** Every widget hook this mod owns is a method on the widget it wants, so UE4SS hands that object to the callback as its first argument, live by construction — `Update Button State` gives the tab page, `OnPassiveUpdate` gives the screen. `lp/ui.lua` records both and calls `FindAllOf` nowhere.
- **A closure per call is a crash, not an inefficiency.** `pcall(function() ... end)` allocates a fresh Lua closure and a UE4SS registry ref every time it runs. On a hook that fires at frame rate that churn produced `Error: [Lua::Registry::get_function_ref] Ref was not function` followed by `EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff`, with a call stack entirely inside UE4SS. Everything on a per-frame path therefore uses argument-form `pcall` against a module-level accessor — `util.field`, `util.method`, and the `_call_`/`_index_` helpers — and every hook callback is built once, at load, and passed by reference. `main.lua`'s `coalescer()` and `hooks.lua`'s per-registration `entry.retry` exist for the same reason: a flag alone is not enough, because `ExecuteWithDelay(0, ...)` completes within the tick and the next firing would allocate again.
- **`restore_replaced_passive` removes the marker before adding the passive, and the order is load-bearing.** `AddPassiveSkill(AddSkill, OverrideSkill)` does not reliably honour the override: it appended the passive and left the marker attached, which is how a Pal ended up carrying Infinite Stamina twice. It is also how the overwrite case crashed — a Pal whose four slots were full gained a fifth entry, and the passive panel has only four cards to index, which is why inserting into an *empty* slot never crashed. Removing first keeps the list from growing past what the UI can address. The trade is that a failed add leaves the Pal with neither, so every caller checks the result and the implant callers refund the module.
- **Check arity against the header dumps, and not just `Pal.hpp`.** Widget functions live in `CXXHeaderDump/WBP_*.hpp`, CommonUI in `CommonUI.hpp`, engine in `Engine.hpp`. Prefer no-argument getters; avoid out-parameter overloads (`TryGetContainer(Out&)`) when a by-value equivalent exists (`GetContainer()`).
