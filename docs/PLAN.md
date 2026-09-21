# Plan

Goals, listed below in the order they should be addressed:

---

## Improvements

### Confirmed in game, 2026-09-20

#### Module sort order in the inventory -- confirmed in game

`SortID` on the 94 `LP_Implant_*` items was two alphabetical-by-id runs from two rounds of authoring (`95001`+ and `96001`+), which is why rarity scattered in `docs/sort-order.png`.

Now one contiguous block, `95001`-`95094`: **rarity descending, then English display name ascending**. Orange first, so Legend, Lucky and the other prizes head the block and the white negatives tail it. Values only -- the file stays alphabetical by item id, which is what makes it maintainable by hand.

The 21 vanilla `PalPassiveSkillChange_Consumable_*` modules keep vanilla's own `SortID` and will still sort apart from these 94. Deliberate: their `Rarity` is not readable from this machine, so any block chosen for them could put an orange module in the purple run, and patching `Rarity` to force agreement would be the first time this mod changed how a vanilla item looks.

Verified 2026-09-20: sorted correctly in two base containers, and still correct after moving modules between the containers and re-sorting. Nothing further to do here.

#### BUG: conveyor modules went to the host rather than to the Pal's owner -- fixed, single-player confirmed

Confirmed by reading it: `delivery_candidates` sorted `local_player` ahead of everything, so on a listen server the host collected the modules for every Pal, whoever owned it. Distance was only ever a tiebreak among the rest.

The premise in the original note needed a correction, and it matters for how the fix is written: a host **without** the mod cannot receive modules, because the mod is not running there. Nothing on an unmodded peer creates items, and the one peer that does create them gates on `HasAuthority()`. What the ordering actually produced was a modded host collecting a guest's modules -- the wrong player, not an unmodded one.

What changed:

- `Pal.hpp`'s `FPalIndividualCharacterSaveParameter.OwnerPlayerUId` is snapshotted with the passives, in the same pass, because that is the last moment the Pal exists to be asked. Property reads only.
- The pending ledger is keyed by owner and item, `LPL2`. An `LPL1` file is still read, as unowned rows, rather than discarded -- the debt is the same, one column short.
- A row with a known owner goes to that owner **and to nobody else**. If they are not online it is held on disk and retried on every map load and every later disassembly. A guest can queue ten Pals and log off while the machine is still eating them; a preference with a fallback would hand all ten to the host, which is the behaviour being removed.
- One fallback, for the comparison not running rather than not matching: if no candidate yields a readable `PlayerUId` at all, the fault is ours, so it pays out in the old order and says so loudly once.

"Deliver only to a player who has the mod" is **not implementable as stated** and the plan should stop asking for it. UE4SS Lua has no custom network channel and nothing exposes a peer's loaded DataTables, so no peer can be asked. Owner-first is the closest approximation. The cost is deliberate and is now documented in `README.md`: a guest without the mod who feeds the conveyor gets modules their game cannot resolve, which the multiplayer test already showed rendering as blank chest entries and crashing nothing. That is a better outcome than the host silently taking them.

To confirm, in single-player first: the summary line for a disassembly must read as it always did, with neither a `held for the player who owned the Pal` clause nor a `No owner UId could be read from the consumed Pal` line. Those two are opposite ends of one question and both are said once per session. `held` means the owner match is running and rejecting -- `OwnerPlayerUId` on the Pal not equalling `PlayerUId` on `APalPlayerState` -- so modules would be withheld rather than delivered until that is fixed. That is the one regression risk in this change; it is loud, and the debt survives it. The `No owner UId` line means the read is not running at all, which fails open: single-player carries on working and the multiplayer rule is quietly inert.

Verified 2026-09-20, in single-player, across twenty-five disassemblies: every one delivered, and **neither** of the two lines that would report the owner match failing appeared -- no ` held for the player who owned the Pal` and no `No owner UId could be read from the consumed Pal`. So `OwnerPlayerUId` on the Pal does read, and it does equal `PlayerUId` on `APalPlayerState`. That was the one regression risk in the change and it is answered. The multiplayer half -- a guest's Pal going to the guest, and a debt held while they are offline -- is still untested and needs two machines.

### Open

#### CTD: access violation in a Lua callback, Surgery screen open, conveyor running

Session of 2026-09-20 19:32-19:36. Sort order verified in two base containers, including after moving modules between them and re-sorting. Twenty-five Pals disassembled over about thirty seconds. Player left the disassembly menu with Pals still on the conveyor, opened the Surgery Table, saw the bugged panel, and the game went down with `EXCEPTION_ACCESS_VIOLATION reading address 0x0000686374617340` with no further interaction.

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
- The conveyor logs one line *before* delivering, not only after. A `Disassembly consumed a Pal owing N module(s); delivering.` with no summary line after it means the process died inside delivery. Take it out once this is settled.

If it reproduces: the log plus `%LOCALAPPDATA%/Pal/Saved/Crashes/` is what to send, and `surgery_ui_gate = false` is the first thing to try.

**Background worth knowing before blaming this mod.** Five Lua mods were live, and PalSchema 0.6.7 failed two signature scans on this game build -- see the entry below, which has a fix. Neither explains an access violation while a menu opens, and the signature failures are about loading a world rather than about running one, but both belong in a bug report.

#### PalSchema 0.6.7 fails two signature scans on this build -- fixed upstream in 0.6.71, not yet on the Workshop

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

#### The Edit button refuses the click but never greys out

Reported from the 2026-09-20 build: the gate blocks correctly, and the button goes on looking pressable. Recorded here because the wrong half was in a code comment presented as settled -- `set_edit_interactable` claimed that "EnabledButton = false is what the game itself uses to show the greyed look", which was never verified and is probably false. `WBP_CommonButton.hpp` declares no disabled state for that widget at all: the animations are `Anm_Normal`, `Anm_NormalToFocus`, `Anm_OpenFocus` and `Anm_DefaultToRed`, and there is no enabled/disabled setter on it.

The mechanism, as far as the code shows: `EnabledButton` is an input the Blueprint reads inside `Update Button State`, not a bound property the paint follows. The gate writes it one frame after that function ran -- deliberately, because writing earlier lets the game's own verdict overwrite ours -- so the paint has already happened from the game's value, and the next pass recomputes `EnabledButton` from scratch. `SetIsInteractionEnabled` on the inner `CommonButtonBase` is the part that sticks, because nothing in the Blueprint touches it. Blocked, and looking pressable.

Deliberately NOT guessing a replacement. `SetIsEnabled(false)` on the outer button was already tried and gives a white cut-out. Dimming `RenderOpacity` ourselves would be inventing a look the game does not use, and it would have to be undone on release or the button stays dim.

Instead, `lp/ui.lua` now has a one-shot probe: `describe_button_state` logs `page.EnabledButton`, the button's `bIsEnabled`, `RenderOpacity` and `Visibility`, the inner button's `bIsEnabled` and `IsInteractionEnabled()`, and the `Visibility` of `Text_Warning` and `Image_NoItem`. It fires at most three times a session, all reads: once before we block, once after we block, and once when **vanilla** disables the button on its own -- select a route you cannot afford, or one whose module you do not hold, to produce that third line. Diff the vanilla line against ours and the property carrying the look falls out. Then write it into the comment and delete the probe.

`Text_Warning` is the first candidate. A text field named that, on a panel with `Image_NoItem` and `Canvas_RequireMoney` beside it, is how a widget with no disabled style usually says no.

#### The blank Surgery panel: the earlier diagnosis is wrong

Recorded because it cost a test cycle. The panel was blamed on `refresh_surgery_ui` writing to a closed screen, and that entry read as settled. The 19:36 session disproves it: the panel came up bugged -- gender change only, no Pal selectable, no `+` to pick a module -- in a session where **no transaction ran at all**, so `refresh_surgery_ui` was never called once. It cannot be the cause, and the guard cannot be the fix.

The guard stays anyway, on its own merit: writing reset-to-empty calls into a panel nobody has open is wrong whether or not it caused this, and it now costs nothing because it acts on one recorded widget rather than on everything `FindAllOf` returned.

**The leading explanation now is that the panel is not corrupted at all: there were no Pals to list.** Twenty-five Pals had just gone through the disassembler, and Pals still on the conveyor are in the machine's container rather than in the box. With nothing to select, there is no Pal, so there is no passive panel and no `+`, and what is left showing is the gender side. That fits the 19:36 sighting exactly, and it fits "toward the very end" of the two earlier sessions. Note also that the first screenshot, `docs/double-trouble.png`, shows an empty framed area rather than a broken one, which is what `WBP_NoData` looks like.

That is a ten-second test and it should be the next thing done: open the Surgery Table with Pals in the box page, then with the box page emptied into the conveyor, and see whether the panel differs. If it is the Pal list, this is vanilla behaviour and the entry closes as not-a-bug -- possibly worth a line in the README instead. If the panel is bugged with Pals available, the next place to look is vanilla's own `Setup` / `SwitchTab` / `SwitchPanel` path, and the question becomes whether 117 added rows in `DT_OperatingTablePassiveSkillDataTable` can make the list build abort.

#### IMPROVEMENT: PalSchema JSON to Lua -- do not do this; take the schemas instead

Asked as: could the JSON item definitions become Lua, for configurable values and for verification. Both halves have an answer, and neither is the conversion.

**PalSchema has no Lua API.** Its `dlls/main.dll` carries no Lua bindings -- the only Lua symbols in it are the inherited `CppUserModBase::on_lua_start`/`on_lua_stop` vtable entries -- and the mod-content strings in the binary are the folder names it scans (`items`, `raw`, `blueprints`, `appearance`, `buildings`, `skins`, `translations`, `mods`) plus `.json` and `.jsonc`. So there is no Lua form of a PalSchema mod to convert to. The data half would instead have to be rebuilt through UE4SS Lua against the live tables, which means reimplementing what PalSchema does natively: adding rows to `DT_ItemDataTable` and entries to `DA_StaticItemDataAsset`, neither of which UE4SS Lua exposes. Not a refactor; a rewrite of the part that already works.

**Verification: PalSchema will generate JSON Schemas from the live game tables.** `main.dll` contains `JsonSchemaGenerator::GenerateRawSchemas`, `GenerateEnumSchema`, a `Generate JSON Schema Files` button under `Generators` in its UE4SS debugging-tools tab, a `schemas` output folder, and the `raw/{}.schema.json`, `enums.schema.json`, `utility.schema.json` names it writes. That is a stronger check than anything hand-written could be, because it is generated from the same reflected properties PalSchema patches through -- it catches a misspelled column or an illegal enum value, which is most of what fails silently today.

How to wire it up, once generated: map the schemas by path glob in `.vscode/settings.json` under `json.schemas`, and run the same schemas in a pre-commit or CI step with any validator (`npx ajv-cli`, for instance). Do **not** add an inline `$schema` key to `items/*.json`: the top level there is a map of item id to definition, so an extra key would read as a 95th item.

Unestablished, and it is one in-game click each: whether the generator covers `items/` as well as `raw/`, and where the `schemas` folder lands.

**Configurable pricing is a different problem and the JSON is not what blocks it.** The charge is server-side, from `Price` in `DT_OperatingTablePassiveSkillDataTable`; the widget's `CurrentRequireMoney` is display only. Writing a DataTable row at runtime is the same capability UE4SS Lua does not expose, so a setting cannot simply override the value. What *is* reachable: money in Palworld is an inventory item, so the Lua half could rebate the difference after a transaction by granting `Money`. That makes a setting able to discount the JSON price but never to raise it, since taking items back needs a container walk this mod has never done. A sketch, not a plan -- nothing here has been tried.

#### Panel repaint: dead ends, so they are not retried

`lp/ui.lua` resets the panel rather than repainting the passive cards. Four approaches were tried first and none of them works; the file points here rather than carrying the list.

- `ReflectPassiveChange`, `RefreshCurrentPassiveItem` and `RefreshItemDisplay`, called on the page and the screen, do not repaint the slots on their own. They are still called as part of the reset, where they are cheap and harmless.
- `On Click Pal List` with the screen's own `CurrentHandle` executes -- it reported `reselect=true` -- and the stale label stays. Re-selecting the Pal that is already selected is evidently a no-op inside the Blueprint, which is why clicking to a *different* Pal and back is what works by hand.
- Writing the cards directly with `SetPassiveSkill` / `Clear` is worse. The calls succeed (`cleared=4 failed=0`) but `Clear()` leaves a card blank instead of showing the empty `+` slot, and the cards are reused across Pal selections, so every Pal afterwards showed an empty panel. The empty state is its own visual -- the card has an `Anm_EmptySlot_HideToShow` animation -- and `Clear()` does not reach it.
- Diagnosing staleness from `BindedPassiveSkillName` does not work either: it was correct while `Text_SkillName` was stale, so the card data agreed with reality the whole time and only the paint was wrong.

#### `extract_additional` journal churn

Unchanged and still deliberate. The `clear_journal()` per passive is redundant against the next iteration's `write_journal`, which opens `"w"`. The final clear is NOT redundant: it is what stops recovery replaying a completed sweep. So the change is "skip between iterations, clear once at the end" -- a restructure of crash-recovery ordering to save a handful of file deletes per extract-all. Wrong trade immediately before publishing.

#### `find_visible_tab_page` caching -- closed

Nothing to cache: the function is gone. The page is taken from the hook context and read back as a validated local, so the 1.4 scans a second it was measured at are now zero engine calls. See the CTD entry above.

---

## Simplification Finds

Below are simplification findings worth a pass.

### Dead path

`recovery.lua:70` read `journal.lock ~= "" and journal.lock or marked[1].lock`, but `read_journal` produces no `lock` column — the marker it records is `passive_name`. The first two terms were dead and it always took the third branch. I simplified to the behaviour it already had and left a comment; if the journal's recorded marker was meant to be authoritative, that's a real bug and a /code-review matter, not a cleanup.

### Larger Issues

- **`finish()`'s UI policy → `ui.on_transaction_complete(mode)`** (altitude). Correct in principle, but it restructures the 500ms/1600ms refresh ladder — the least testable code in the mod and the suspected cause of `docs/double-trouble.png`. Not without an in-game session.
- **Bounding the conveyor's snapshot-miss re-walk**. Changes behaviour (stops retrying a snapshot after N frames).
- **Caching `before_counts` on snapshots** to stop `counts()` being rebuilt per resolve attempt. Real waste on the ~500-parameter fallback path, but it means new signatures for the mod's most safety-critical predicates.
- **`recovery.schedule_recovery`'s per-call closures**. A one-slot fix would coalesce the startup and map-load recoveries into one when they overlap. Cold path; not worth the behaviour change.

Two notes: `ledger.owe`'s signature changed to `owe(owner, item_ids)`, and I updated `tools/ledger_test.lua` to match. You were editing ui.lua concurrently (a probe around `set_edit_interactable` using the new `util.method`) — I left that alone and the checks above ran against your current state.

I have not run `install.ps1`; nothing here is verified in game yet.

---

## Publish to the Steam Workshop

### Facts established (uploader docs + installed packages on disk)

- `InstallRule.Targets` copies each named folder **with its name** into the destination for its `Type`. `Lua` → `Mods\NativeMods\UE4SS\Mods\<PackageName>`; `PalSchema` → `Mods\NativeMods\UE4SS\Mods\PalSchema\mods`; also `UE4SS`, `LogicMods`, `Paks`. This is why the payload is `PalSchemaMods/LootablePassives/`.
- `Info.json` is correct as it stands: `PackageName` `LootablePassives`, `DebugMode: false`, four `InstallRule`s (client + `IsServer` for both types), Tags all legal, and `Dependencies` `["UE4SSExperimentalPW", "PalSchema"]` — **both verified against the installed packages' own `Info.json`** at `steamapps\workshop\content\1623730\3625223587` and `…\3625280368`.
  Nothing asserts this automatically any more; it is checked by reading it.
- The uploader validates three things only: the JSON parses, `PackageName` is non-empty alphanumeric, and ≥1 `InstallRule` has `Type` and `Targets`. An illegal `Type`, a missing `Targets` path, an illegal `Tag`, an unresolvable `Dependency` — all upload cleanly and then fail to install silently. Nothing validates this now -- step 6 below, installing from the Workshop into a clean game folder, is the only thing that catches it.
- `MinRevision` is "the last 5 digits of the version shown in the title". It is not readable from the exe or the manifests on disk (checked) — read it off the title screen of the build actually tested. Currently `82182`, which matches both dependencies.
- `Version` is compared as a plain string; any change makes the loader uninstall and reinstall the mod folder. This is why the recovery journal lives at the UE4SS root, outside the managed tree.
- The uploader is GUI-only — no CLI — so the upload click cannot be scripted. **Do not subscribe to your own item:** subscribed packages are view-only and can no longer be updated from that machine.
- rewrite **Install** once the mod is a Workshop item, keeping `install.ps1` as the dev/manual path.

### `tools/stage.ps1`

The repo cannot be uploaded in place: Steam UGC uploads the item folder recursively, so without a staging step every subscriber downloads `.git/`, `tools/`, `data/` and `docs/`. Copy **only** `Info.json`, `thumbnail.png`, `Scripts/`, `PalSchemaMods/LootablePassives/`, `README.md` and `LICENSE` into the uploader's numbered folder under `C:\Program Files (x86)\Steam\steamapps\workshop\content\1623730\<id>\`.

Requirements, modelled on `install.ps1`: `-DryRun`; an **allowlist**, never an exclude list, so a new top-level folder in the repo cannot leak by default; and leave `.workshop.json` in the destination untouched — it holds the `PublishedFileId`. It should run its own two self-contained checks rather than call out to anything: `Info.json` parses, and every `InstallRule.Targets` path plus `Thumbnail` exists in the staged set. Keep those inside `stage.ps1`; do not grow a second verifier tool.

### Release checklist

1. `luacheck.js` green; `install.ps1`; restart; confirm the startup counts line reads `115 extractable passives, 2 extraction operations, 54 insert routes`; exercise Extract One, Extract All, an insert, a duplicate-blocked insert, and (once §3 lands) the conveyor.
2. Re-derive `MinRevision` from that build's title screen; bump `Version`; confirm `DebugMode: false`. `MinRevision` is a FLOOR, not the build you happen to be on, so 82182 is not automatically stale -- UE4SS, PalSchema and every other package on this machine still declare it. The real question is which floor we can honestly claim: testing has only ever happened on `v1.0.5.102999`, so 82182 asserts a compatibility nobody has checked, while 102999 locks out anyone on an older build. Decide it deliberately rather than by leaving the number alone.
3. Read <https://eula.pocketpair.jp/palworld-mod-guideline> — the only content gate, and not reproduced in the uploader docs.
4. Write the Workshop description: both dependencies with their Workshop ids (`3625223587`, `3625280368`), and the dedicated-server `WorkshopRootDir` + ActiveModList=LootablePassives` note from `Mods\PalModSettings.ini`.
5. `Create New Mod` (Lua) in the uploader to mint the folder and `PublishedFileId`, `stage.ps1` into it, upload **private**.
6. Verify by installing from the Workshop into a clean game folder — not the dev install, which already has the files. Then make it public.

### Multiplayer test result (2026-09-19)

Run on real hardware, two machines: **host has the mod, joining client does not.**

- Game stable for both players; no crash on either side.
- Extraction and disassembly worked normally for the host.
- Items the client's game cannot resolve render as **blank entries** in a shared chest.  Confirms the prior assumption. Viewing them does not crash the client.

This proves asymmetric installs are survivable, and the Workshop description can say so. What this does **not** establish, and must not be written as if it did: the client had no mod at all, so **no non-authoritative peer has ever run this code**. The `HasAuthority()` false branch remains unexercised. Also still untested: a client that *has* the mod, and dedicated-server hosting.  This can only come after publishing to the steam workshop due to resource constraints in testing; the mod will be testes on a Steam Machine console which can download and activate the mod from the workshop.

### Notes on Mod activation

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
