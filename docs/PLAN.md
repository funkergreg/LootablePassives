# Plan

Goals, listed below in the order they should be addressed:

---

## Improvements

### Fixed in the repo, not yet confirmed in game

Nothing below has been through a game session yet. `luacheck` is green and `lua tools\ledger_test.lua` passes, which is the whole of what can be checked without the engine. Each entry says what to look for.

#### BUG: the Surgery Table panel goes blank after several transactions

Seen twice, late in a session, after several successful operations in a row: the Pal Operating Table opens with its title and description and nothing else. Screenshot `docs\double-trouble.png`.

Cause, as far as the code shows: `refresh_surgery_ui` wrote to every `WBP_OperatingTable_TabPage_C` and `WBP_OperatingTable_C` instance `FindAllOf` returned, open or not. `finish()` schedules that ladder at 500 ms and 1600 ms after an operation, so closing the screen within a second and a half of confirming one -- which is what you do when you are finished -- ran the whole reset against a closed panel. Every call in it is a reset-to-empty, and the widget is reused on the next open, so a reset applied while it was closed is one the player cannot undo from the UI. `SetupPassiveChangeItem()` is the worst of them: it destroys and rebuilds all 118 entries from the screen's selected Pal, and with no Pal selected it has nothing to build them from.

What changed, in `Scripts/lp/ui.lua`:

- Nothing is written to a panel that is not open. `is_open` demands a positive `IsVisible`, which is the opposite bias from the gate's `find_visible_tab_page` -- that one still counts a FAILED `IsVisible` as visible, because the worst it can do is grey a button. The two biases are now stated side by side.
- `SetupPassiveChangeItem()` additionally requires the screen to have a Pal selected (`CurrentHandle` valid).
- `find_visible_tab_page` prefers a page that positively reports itself visible over one whose `IsVisible` call merely failed. Before, `FindAllOf` order decided, so one stale page early in the list could take every gate pass for the rest of the session and the real panel would never be gated -- a second way the mod can appear to switch itself off mid-session.

To confirm: run several operations, close the screen immediately after one, reopen it, and keep going for as long as the original sessions ran. Two new lines exist for this. `The Surgery panel was already closed when a refresh came due` is informational and says the guard did its job; a `WARNING: found N open Surgery panel(s) and M open screen(s)` means more than one of either is live at once, which is the remaining suspicion and is worth reporting with the log.

This is a diagnosis from the code, not a reproduction. If the panel still blanks with those lines absent from the log, the cause is elsewhere and the next place to look is vanilla's own `Setup`/`SwitchTab` path.

#### BUG: conveyor modules went to the host rather than to the Pal's owner

Confirmed by reading it: `delivery_candidates` sorted `local_player` ahead of everything, so on a listen server the host collected the modules for every Pal, whoever owned it. Distance was only ever a tiebreak among the rest.

The premise in the original note needed a correction, and it matters for how the fix is written: a host **without** the mod cannot receive modules, because the mod is not running there. Nothing on an unmodded peer creates items, and the one peer that does create them gates on `HasAuthority()`. What the ordering actually produced was a modded host collecting a guest's modules -- the wrong player, not an unmodded one.

What changed:

- `Pal.hpp`'s `FPalIndividualCharacterSaveParameter.OwnerPlayerUId` is snapshotted with the passives, in the same pass, because that is the last moment the Pal exists to be asked. Property reads only.
- The pending ledger is keyed by owner and item, `LPL2`. An `LPL1` file is still read, as unowned rows, rather than discarded -- the debt is the same, one column short.
- A row with a known owner goes to that owner **and to nobody else**. If they are not online it is held on disk and retried on every map load and every later disassembly. A guest can queue ten Pals and log off while the machine is still eating them; a preference with a fallback would hand all ten to the host, which is the behaviour being removed.
- One fallback, for the comparison not running rather than not matching: if no candidate yields a readable `PlayerUId` at all, the fault is ours, so it pays out in the old order and says so loudly once.

"Deliver only to a player who has the mod" is **not implementable as stated** and the plan should stop asking for it. UE4SS Lua has no custom network channel and nothing exposes a peer's loaded DataTables, so no peer can be asked. Owner-first is the closest approximation. The cost is deliberate and is now documented in `README.md`: a guest without the mod who feeds the conveyor gets modules their game cannot resolve, which the multiplayer test already showed rendering as blank chest entries and crashing nothing. That is a better outcome than the host silently taking them.

To confirm, in single-player first: the summary line for a disassembly must read as it always did, with neither a ` held for the player who owned the Pal` clause nor a `No owner UId could be read from the consumed Pal` line. Those two are opposite ends of one question and both are said once per session. `held` means the owner match is running and rejecting -- `OwnerPlayerUId` on the Pal not equalling `PlayerUId` on `APalPlayerState` -- so modules would be withheld rather than delivered until that is fixed. That is the one regression risk in this change; it is loud, and the debt survives it. The `No owner UId` line means the read is not running at all, which fails open: single-player carries on working and the multiplayer rule is quietly inert.

#### Module sort order in the inventory

`SortID` on the 94 `LP_Implant_*` items was two alphabetical-by-id runs from two rounds of authoring (`95001`+ and `96001`+), which is why rarity scattered in `docs/sort-order.png`.

Now one contiguous block, `95001`-`95094`: **rarity descending, then English display name ascending**. Orange first, so Legend, Lucky and the other prizes head the block and the white negatives tail it. Values only -- the file stays alphabetical by item id, which is what makes it maintainable by hand.

The 21 vanilla `PalPassiveSkillChange_Consumable_*` modules keep vanilla's own `SortID` and will still sort apart from these 94. Deliberate: their `Rarity` is not readable from this machine, so any block chosen for them could put an orange module in the purple run, and patching `Rarity` to force agreement would be the first time this mod changed how a vanilla item looks.

### Open

#### IMPROVEMENT: PalSchema JSON to Lua -- do not do this; take the schemas instead

Asked as: could the JSON item definitions become Lua, for configurable values and for verification. Both halves have an answer, and neither is the conversion.

**PalSchema has no Lua API.** Its `dlls/main.dll` carries no Lua bindings -- the only Lua symbols in it are the inherited `CppUserModBase::on_lua_start`/`on_lua_stop` vtable entries -- and the mod-content strings in the binary are the folder names it scans (`items`, `raw`, `blueprints`, `appearance`, `buildings`, `skins`, `translations`, `mods`) plus `.json` and `.jsonc`. So there is no Lua form of a PalSchema mod to convert to. The data half would instead have to be rebuilt through UE4SS Lua against the live tables, which means reimplementing what PalSchema does natively: adding rows to `DT_ItemDataTable` and entries to `DA_StaticItemDataAsset`, neither of which UE4SS Lua exposes. Not a refactor; a rewrite of the part that already works.

**Verification: PalSchema will generate JSON Schemas from the live game tables.** `main.dll` contains `JsonSchemaGenerator::GenerateRawSchemas`, `GenerateEnumSchema`, a `Generate JSON Schema Files` button under `Generators` in its UE4SS debugging-tools tab, a `schemas` output folder, and the `raw/{}.schema.json`, `enums.schema.json`, `utility.schema.json` names it writes. That is a stronger check than anything hand-written could be, because it is generated from the same reflected properties PalSchema patches through -- it catches a misspelled column or an illegal enum value, which is most of what fails silently today.

How to wire it up, once generated: map the schemas by path glob in `.vscode/settings.json` under `json.schemas`, and run the same schemas in a pre-commit or CI step with any validator (`npx ajv-cli`, for instance). Do **not** add an inline `$schema` key to `items/*.json`: the top level there is a map of item id to definition, so an extra key would read as a 95th item.

Unestablished, and it is one in-game click each: whether the generator covers `items/` as well as `raw/`, and where the `schemas` folder lands.

**Configurable pricing is a different problem and the JSON is not what blocks it.** The charge is server-side, from `Price` in `DT_OperatingTablePassiveSkillDataTable`; the widget's `CurrentRequireMoney` is display only. Writing a DataTable row at runtime is the same capability UE4SS Lua does not expose, so a setting cannot simply override the value. What *is* reachable: money in Palworld is an inventory item, so the Lua half could rebate the difference after a transaction by granting `Money`. That makes a setting able to discount the JSON price but never to raise it, since taking items back needs a container walk this mod has never done. A sketch, not a plan -- nothing here has been tried.

#### `extract_additional` journal churn

Unchanged and still deliberate. The `clear_journal()` per passive is redundant against the next iteration's `write_journal`, which opens `"w"`. The final clear is NOT redundant: it is what stops recovery replaying a completed sweep. So the change is "skip between iterations, clear once at the end" -- a restructure of crash-recovery ordering to save a handful of file deletes per extract-all. Wrong trade immediately before publishing.

#### `find_visible_tab_page` caching

Still low priority, and the measured 1.4 calls a second still stands. Note that the scan now makes two passes over the `FindAllOf` result in the worst case -- see the blank-panel fix above -- so if this is ever cached, the pass order is part of what has to be preserved.

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
2. Re-derive `MinRevision` from that build's title screen; bump `Version`; confirm `DebugMode: false`.
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
