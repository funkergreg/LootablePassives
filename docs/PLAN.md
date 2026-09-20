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

## Refactor — status

**DONE: `lp/hooks.lua` is the single hook registrar.** Both widget registrations in `main.lua`
moved onto it, along with the conveyor's two. `main.lua` went 370 -> 289 lines. The coalescing
flags stayed in `main.lua` because they are specific to those two callbacks; the retry bound,
warn-once and per-map re-arm are shared. Fixed on the way: `hooks.lua` re-armed its *warning* on
every map load, the same defect found in `main.lua`, so a startup said the same thing three or
four times.

**DONE (earlier session): one resolver loop.** `resolve_record` already iterates a single
`snapshots` list whatever produced it, with `expect_passive_id` carried per snapshot — exactly the
fix this plan proposed. The item was stale.

**NOT DONE, AND RECOMMENDED AGAINST BEFORE RELEASE:**

- **`extract_additional` journal churn.** The `clear_journal()` per passive is redundant against
  the next iteration's `write_journal`, which opens `"w"`. But the final clear is NOT redundant: it
  is what stops recovery replaying a completed sweep, so the change is "skip between iterations,
  clear once at the end" — a restructure of crash-recovery ordering to save a handful of file
  deletes per extract-all. Wrong trade immediately before publishing.
- **`find_visible_tab_page` caching.** This plan already measured the call rate at 1.4/second and
  called it low priority. It still is.

Both are safe to do after release, with a test cycle to spend on them.

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

### FINDING (2026-09-19): there is no way to create an item outside a player inventory

Five mechanisms were tried. All reduce to one wall, and it is worth writing down so it is not
re-litigated:

**`UPalPlayerInventoryData::AddItem_ServerInternal` is the only item-creation function in the
entire reflected API.** An exhaustive sweep for `Add*Item*` / `Set*` / `Put*` / `Insert*` /
`Store*` / `Give*` / `Fill*` / `Transfer*` across `Pal.hpp` returns nothing else that writes an
item; the rest is logging, durability and textures. It needs a player, and it fails with
`FailedContainerOverflowSlotNum = 4` when the bag is full, creating nothing.

| Mechanism | Outcome |
| --- | --- |
| `PalStatusCollectItem` / `PalIncidentBase` `DropItem(...)` | Right signature, **zero live instances** in four sessions |
| Constructing one via `StaticConstructObject` | **Crashed the game** — `EXCEPTION_ACCESS_VIOLATION reading 0x2a8`. Do not retry |
| Adding to any non-player container | No such function exists |
| Base-camp quick-stack (`RequestMoveInventoryItemToBaseCamp`) | Real, but entry is still the player inventory, so it fails identically when full |
| Spawning `CommonDropItem3D` via `RequestSpawnMapObject_Server` | Spawns, but a drop's contents live in a 1-slot `UPalItemContainer` (measured: `ItemId.StaticId=Egg`, `container holding [Egg x1]`). Empty bag, unfillable |

The only untried avenue is writing `UPalItemSlot.ItemId` / `.StackCount` as raw properties on a
spawned drop. That bypasses `UpdateItem_ServerInternal`'s dirty-marking and replication, so it is
single-player-only at best and a save-integrity risk at worst. **Not recommended.**

### Consequences for the feature

The conveyor's ceiling is a deferred ledger: journal what a consumed Pal owed, grant it when the
player next has room. Nothing is lost, but nothing appears while the bag is full, and:

- **54 slots, 115 module types.** `Common` is 54 slots (measured; `GetInventoryTypeFromStaticItemID`
  returns 0 for a module and that container's free count is what moves). A varied mass disassembly
  cannot fit even with 9999 stacks.
- **Multiplayer has no answer.** `find_inventory(nil)` resolves a player only when exactly one
  exists, and a base-camp machine has no requesting player. Which player receives the modules is
  undefined.

### Multiplayer test result (2026-09-19)

Run on real hardware, two machines: **host has the mod, joining client does not.**

- Game stable for both players; no crash on either side.
- Extraction and disassembly worked normally for the host.
- Items the client's game cannot resolve render as **blank entries** in a shared chest.
  Confirms the prior assumption. Viewing them does not crash the client.

So asymmetric installs are survivable, and the Workshop description can say so. What this does
**not** establish, and must not be written as if it did: the client had no mod at all, so **no
non-authoritative peer has ever run this code**. The `HasAuthority()` false branch remains
unexercised. Also still untested: a client that *has* the mod, and dedicated-server hosting.

### Remaining work — BLOCKED PENDING A DECISION

**SETTLED: the conveyor ships, with the ledger and the documented at-your-feet limitation.** The
grant path is built, tested to a 54-Pal stress run with zero failures, and its limitations are
written up in `README.md`. The alternatives considered and rejected were shipping the Surgery
Table alone, and shelving the conveyor.

Unchanged from the original design: **no gold** (the Pal is the price), and `passive_items.lua` and
`is_extractable` are reused **as-is** — a module from the conveyor must be the same item as a module
from the Surgery Table, with no conveyor-specific rarity or naming.

---

## Cleanup stage — agreed work

### Documentation restructure — DONE

`CLAUDE.md` is to hold **only true findings about engine usage and mod construction** that a future
agent needs after release. The sketch design and intent have served their purpose and become
context noise now that the thing is built. Specifically:

- **Remove** from `CLAUDE.md`: "The Surgery Table Design" and "The Pal Disassembly Conveyor Design".
- **Add** to `README.md`: a "What this mod does" section describing **actual** behaviour including
  its known flaws and limitations — not the original sketch. Notably: modules go to the player's
  inventory and overflow to the ground **at the player's feet**, not behind the machine. The engine
  spills them; we do not choose where.
- **Keep** in `CLAUDE.md`: "Reading the engine from Lua", "The JSON is the source of truth", "Mod
  registration, and why there is no off switch", repo layout, naming, and the release material.

### One change-once variable

**Conveyor extraction on/off.** A single constant gating `conveyor.install()`. Deliberately a
variable and not a settings UI: UI integration is a later decision and this is the cheap pre-step.

### Cost configuration is SCRAPPED — remove its references

Not deferred, dropped. Prices live in 171 JSON rows across four files, PalSchema has no templating,
and the generator that could have derived them is deleted and not coming back. The remaining
options were to mutate DataTable rows PalSchema owns from Lua at load, or to call a four-file
search-and-replace a "variable". Neither is worth it.

Cleanup work is therefore to **remove any text implying the cost is configurable**, so nobody picks
this up again expecting a knob. Prices are fixed data: 1000 for the mod's operations, 5000 for the
repriced vanilla rows, 10 for an implant's own item value. Sweep `CLAUDE.md`, `README.md`, the JSON
`_comment` fields and this file.

## 4. Documentation

- rewrite **Install** once the mod is a Workshop item, keeping `install.ps1` as the dev/manual path.
- `CLAUDE.md` — **done**, except `tools/stage.ps1`, which is added to the commands table and repo
  layout when it is written in the publishing phase. The three-route design table moved to
  `README.md`; `CLAUDE.md` is findings-only. **Done:** the mod-registration section, which claimed
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
