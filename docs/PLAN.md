# Plan

Four goals, in the order they should be done:

1. **Refactor** for modularity and single-point-of-control
2. **Add extract-all to the Pal Disassembly Conveyor**
3. **Update README.md and CLAUDE.md**
4. **Publish to the Steam Workshop**

**Done since this plan was written** (2026-09-19): the one-time development scaffolding is gone --
`lp/diagnostics.lua`, the `verbose`/`diag` log channel and its six one-shot DIAG blocks, the
`blocked_passives` deny-list, `variant_label`, the legacy-journal migration, and the whole
`data/*.tsv` -> `tools/generate.py` -> `tools/verify.py` pipeline. The JSON under
`PalSchemaMods/LootablePassives/` and `Scripts/passive_items.lua` are now hand-maintained and are
the source of truth. Nothing below should assume any of those exist.

## Refactor

Ordered.

**`lp/hooks.lua` — one bounded hook registrar. HALF DONE.** The module exists and is the single
implementation of the pattern: attempt counter, 12-attempt bound, warn-once, per-map retry-budget
reset, callback built once at load. `main.lua`'s `RegisterLoadMapPostHook` calls
`hooks.rearm_on_map_load()`, and the conveyor registers through it — so the third copy the plan
warned about was never written.

**Still to do:** move `register_button_guard` and `register_passive_update_hook` onto it. They were
left alone deliberately. That pattern is load-bearing — unbounded retries and per-call closures are
both traced to the `0xffffffffffffffff` crash — and those two are tested and working, so they move
only in a session where all three hooks can be exercised in game together. Coalescing is theirs
alone and did not go into `hooks.lua`; add it as an option when they move, not before.

**One resolver loop.** `resolve_record` in `transaction.lua` forks on
`record.snapshots == nil` and rebuilds the resolved-record literal three times in ~60 lines, so
adding a field means editing three places. The fork also hides an asymmetry: the targeted path
requires `removed == record.passive_id`, the snapshot path accepts any `removed`. Fix by having
`capture_targeted_record` return a one-element `snapshots` list with the expected `passive_id`
attached, leaving one loop and making the asymmetry an explicit field. The snapshot path is the
dedicated-server one — least tested, and the one that diverged.

**`OPERATIONS[id] = { mode, target }`.** `ids.EXTRACTION_MODES` answers two
questions with one 56-entry table — *is this id ours* and *which of three operations is it* — which
shows up as membership scans, a mode re-derived by string compare in the Edit gate, and the target
read from a second table. `is_ours(id)` plus one record per id says it once; ~a dozen mechanical
call sites. **Treat as load-bearing:** `ids.lua`'s own header records that conflating markers with
aliases in this set was once a near-miss for stripping real passives off Pals.

**Resolve on the event, not the poll.** `finalize_extraction` polls
`resolve_record` 12× at 250 ms while `OnPassiveUpdate` — the engine's own "the passive list
changed" event — is already hooked and used only to repaint. Make the event lead and demote the
timer to the fallback it already is. **The timer must survive:** `snapshot_server_parameters` has no
widget and therefore no event, and the hook demonstrably fails to register on splash, login and
title maps. Same area, same trip: `finish()` arms three mechanisms to repaint one panel (event,
500 ms, plus an unconditional 1600 ms `refresh_surgery_ui(true, false)` for extractions), and
`refresh_surgery_ui` still calls three functions its own comment records as having not repainted
anything. Delete them or label them insurance at the call site.

**Cheap and safe, just not done yet.**

- `extract_additional` writes the journal twice and `clear_journal()`s per passive, so extract-all
  deletes a file the next iteration immediately recreates. Keep one handle across the sweep — and do
  it with the grant-first ordering in front of you; the churn is safe to drop because
  `write_journal` opens `"w"`, the ordering is not negotiable.
- `find_visible_tab_page` ([ui.lua:74](../Scripts/lp/ui.lua#L74)) runs a full `FindAllOf` on every
  gate pass for a widget that does not change between passes. Cache and re-scan on `is_valid`
  failure. Low priority: the measured 1.4 calls/second makes this cheaper than it looks.

---

## Pal Disassembly Conveyor — extract-all on consumption

### Status: two observation sessions run (2026-09-19)

`lp/conveyor.lua` is wired into `main.lua` and still `DRY_RUN = true` — it logs what it would hand
over and creates nothing. The verified engine surface and the checked arities live in that file's
header. What the sessions settled:

- **The machine has no output container.** `containerSlots=10 queueCapacity=3 processTime=5.0
  itemContainerModule=none`. The produced items really are world drops. The grant path is therefore
  either a world drop (temp container plus a `DropItem` map object, via
  `UPalMapObjectModelInitializeExtraParameterDropItem`) or the player's inventory via
  `inventory.lua`. **Still undecided** — see Remaining work. `SpawnDropItem` is unusable; it belongs
  to `APalRandomIncidentMapObjectSpawner`.
- **Two hooks are required.** `OnProceedConvertProcess` fires per frame *while converting*
  (~14–33/s) and goes silent when the queue empties, so departures went unnoticed until the next
  insertion — and consuming the last Pal in a queue would never have granted at all.
  `UPalMapObjectConvertCharacterToItemModel:OnUpdateCharacterContainer_ServerInternal` (no
  arguments, context is the model) fires on every slot change, ~11 times in the same span. With
  both, re-inserting the same Pal now logs every time.
- **`ConvertProgressRate` is the consumed-versus-withdrawn test**, and the first session's apparent
  refutation of it was a measurement bug. An `os.clock()` throttle left the held rate stale by up to
  a second, producing the misleading 0.913 / 0.303. Unthrottled, the separation is total: consumed
  at 1.002 / 1.004 / 1.002 / 1.003, withdrawn at 0.293 / 0.238. `COMPLETE_RATE = 0.999`. **Do not
  reintroduce a throttle** — it breaks this silently.
- **Do not use an existence test.** Asking whether the individual is still findable after departure
  reported "still exists" for all four consumed Pals — a `UPalIndividualCharacterParameter` outlives
  its Pal — and cost 240–330 ms per departure walking 1,776 objects.
- **The container walk is sound.** Across both sessions, zero unresolvable slots, zero missing
  parameters, and passive lists read correctly (including a Pal with genuinely none).

### Remaining work

1. **Confirm the corrected discriminator.** One run: `CONSUMED` for a completed disassembly,
   `WITHDRAWN` for a hand-withdrawal. Nothing has yet produced a `CONSUMED` line in game.
2. **Decide the output.** The deciding question is whether conveyors run with no player nearby — if
   they do, an inventory grant has no recipient and the world drop wins by default.
3. **Write the grant path. Journal first.** Grant-first ordering is impossible here: the game
   destroys the Pal on its own schedule. The journal becomes the primary safety net rather than the
   exception path — rows written at first sighting (state `pending`, phase `conveyor`), replayed by
   `recovery.lua`. A failed grant has no refund path, so it needs a retry that survives a restart,
   not a skipped line.
4. **Delete the scaffolding**: `DRY_RUN`, the survey, the `HOOK CALLS` counter, and the whole
   `trace()` block, in the session they stop earning their place.
5. Confirm the structure's in-game name really is the Disassembly Conveyor before writing it into
   the README. Still circumstantial: an `AKE_Build_Disassembly` audio key, and no "conveyor" or
   "disassembly" string in any class name.

Unchanged from the original design: **no gold** (the Pal is the price), and `passive_items.lua` and
`is_extractable` are reused **as-is** — a module from the conveyor must be the same item as a module
from the Surgery Table, with no conveyor-specific rarity or naming.

---

## 4. Documentation

- rewrite **Install** once the mod is a Workshop item, keeping `install.ps1` as the dev/manual path.
- `CLAUDE.md` — the three-route design table stays accurate; add the conveyor as a fourth route
  once it exists (no gold, no new items, reuses `passive_items.lua`), add `tools/stage.ps1` to the
  commands table and the repo layout. **Done:** the mod-registration section, which claimed
  `mods.txt` controlled the mod. It controls the Lua half only; the PalSchema half has no switch at
  all, and the resulting half-off state actively destroys passives. See that section.
- engine surface (class names, hook paths, the slot → parameter chain) belongs in a comment
  header on the conveyor module itself, next to the code that depends on it — not in a separate
  notes file, and not in `CLAUDE.md`, which is loaded into context on every edit.

---

## 5. Publish to the Steam Workshop

### Facts established (uploader docs + installed packages on disk)

- `InstallRule.Targets` copies each named folder **with its name** into the destination for its
  `Type`. `Lua` → `Mods\NativeMods\UE4SS\Mods\<PackageName>`; `PalSchema` →
  `Mods\NativeMods\UE4SS\Mods\PalSchema\mods`; also `UE4SS`, `LogicMods`, `Paks`. This is why the
  payload is `PalSchemaMods/LootablePassives/`.
- `Info.json` is correct as it stands: `PackageName` `LootablePassives`, `DebugMode: false`, four
  `InstallRule`s (client + `IsServer` for both types), Tags all legal, and `Dependencies`
  `["UE4SSExperimentalPW", "PalSchema"]` — **both verified against the installed packages'
  own `Info.json`** at `steamapps\workshop\content\1623730\3625223587` and `…\3625280368`.
  Nothing asserts this automatically any more; it is checked by reading it.
- The uploader validates three things only: the JSON parses, `PackageName` is non-empty
  alphanumeric, and ≥1 `InstallRule` has `Type` and `Targets`. An illegal `Type`, a missing
  `Targets` path, an illegal `Tag`, an unresolvable `Dependency` — all upload cleanly and then fail
  to install silently. Nothing validates this now -- step 6 below, installing from the Workshop
  into a clean game folder, is the only thing that catches it.
- `MinRevision` is "the last 5 digits of the version shown in the title". It is not readable from
  the exe or the manifests on disk (checked) — read it off the title screen of the build actually
  tested. Currently `82182`, which matches both dependencies.
- `Version` is compared as a plain string; any change makes the loader uninstall and reinstall the
  mod folder. This is why the recovery journal lives at the UE4SS root, outside the managed tree.
- The uploader is GUI-only — no CLI — so the upload click cannot be scripted. **Do not subscribe to
  your own item:** subscribed packages are view-only and can no longer be updated from that machine.

### `tools/stage.ps1`

The repo cannot be uploaded in place: Steam UGC uploads the item folder recursively, so without a
staging step every subscriber downloads `.git/`, `tools/`, `data/` and `docs/`. Copy **only**
`Info.json`, `thumbnail.png`, `Scripts/`, `PalSchemaMods/LootablePassives/`, `README.md` and
`LICENSE` into the uploader's numbered folder under
`C:\Program Files (x86)\Steam\steamapps\workshop\content\1623730\<id>\`.

Requirements, modelled on `install.ps1`: `-DryRun`; an **allowlist**, never an exclude list, so a
new top-level folder in the repo cannot leak by default; and leave `.workshop.json` in the
destination untouched — it holds the `PublishedFileId`. It should run its own two self-contained
checks rather than call out to anything: `Info.json` parses, and every `InstallRule.Targets` path
plus `Thumbnail` exists in the staged set. Keep those inside `stage.ps1`; do not grow a second
verifier tool.

### Release checklist

1. `luacheck.js` green; `install.ps1`; restart; confirm the startup counts line reads
   `115 extractable passives, 2 extraction operations, 54 insert routes`; exercise Extract One, Extract
   All, an insert, a duplicate-blocked insert, and (once §3 lands) the conveyor.
2. Re-derive `MinRevision` from that build's title screen; bump `Version`; confirm
   `DebugMode: false`.
3. Read <https://eula.pocketpair.jp/palworld-mod-guideline> — the only content gate, and not
   reproduced in the uploader docs.
4. Write the Workshop description: both dependencies with their Workshop ids (`3625223587`,
   `3625280368`), and the dedicated-server `WorkshopRootDir` + `ActiveModList=LootablePassives`
   note from `Mods\PalModSettings.ini`.
5. `Create New Mod` (Lua) in the uploader to mint the folder and `PublishedFileId`, `stage.ps1` into
   it, upload **private**.
6. Verify by installing from the Workshop into a clean game folder — not the dev install, which
   already has the files. Then make it public.
