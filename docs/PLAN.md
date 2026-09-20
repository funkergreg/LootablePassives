# Plan

Goals, in the order they should be done:

- Misc. Improvements
- Publish to the Steam Workshop

---

## Misc. Improvements

- Look at feasability of transforming these to lua as item definitions in native mod formats.  Advantages:
  - We can better swap out fixed values with variables, such as for pricing being controled by a configurable setting.
  - As stated in the CLAUDE.md, the JSON item definitions have no verification phase and PalSchema can fail silently; making them lua opens up cleaner verification routes than hand-maintained JSON.
- **`extract_additional` journal churn.** The `clear_journal()` per passive is redundant against the next iteration's `write_journal`, which opens `"w"`. But the final clear is NOT redundant: it is what stops recovery replaying a completed sweep, so the change is "skip between iterations, clear once at the end" — a restructure of crash-recovery ordering to save a handful of file deletes per extract-all. Wrong trade immediately before publishing.
- **`find_visible_tab_page` caching.** This plan already measured the call rate at 1.4/second and called it low priority. It still is.

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


## Multiplayer test result (2026-09-19)

Run on real hardware, two machines: **host has the mod, joining client does not.**

- Game stable for both players; no crash on either side.
- Extraction and disassembly worked normally for the host.
- Items the client's game cannot resolve render as **blank entries** in a shared chest.  Confirms the prior assumption. Viewing them does not crash the client.

This proves asymmetric installs are survivable, and the Workshop description can say so. What this does **not** establish, and must not be written as if it did: the client had no mod at all, so **no non-authoritative peer has ever run this code**. The `HasAuthority()` false branch remains unexercised. Also still untested: a client that *has* the mod, and dedicated-server hosting.  This can only come after publishing to the steam workshop due to resource constraints in testing; the mod will be testes on a Steam Machine console which can download and activate the mod from the workshop.

## Notes on Mod activation

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
