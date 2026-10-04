# Simplify backlog

Findings from a whole-codebase `/simplify` review that were deliberately not applied, because each one changes behaviour, needs in-game verification, or both. Every other finding from that review has been applied. Each item below is self-contained: what the code does now, why it is a problem, the proposed change, the risk, and how to verify it.

Function names are used instead of line numbers, which drift. Read the named function before acting on any description here, and treat code comments as unverified, as `CLAUDE.md` requires.

## Ground rules for working these items

Read `CLAUDE.md` in full first. The points that bear directly on this list:

- **Per-frame paths must not allocate closures.** `pcall(function() ... end)` or a fresh callback per firing on a hook that fires at frame rate crashes UE4SS (`Ref was not function`, then `EXCEPTION_ACCESS_VIOLATION`). Use argument-form `pcall` against module-level helpers, and build every hook callback once, at load.
- **`pcall` does not catch native access violations.** A wrong-arity UFunction call or a call on a bad object takes the game down. Check arity against the header dumps (`Pal.hpp`, `WBP_*.hpp`, `CommonUI.hpp`, `Engine.hpp`) before adding any engine call.
- **Log immediately before each new engine call** when probing, so the last line of `UE4SS.log` names the call if the game dies.
- **The dev loop** is: edit in the repo, `node tools\luacheck.js`, `luacheck Scripts` (baseline 0 warnings / 0 errors), `lua tools\ledger_test.lua` after any `lp/ledger.lua` edit, `.\tools\stage.ps1` (dev build: patch + 1, DebugMode on; `-Publish` for a release: minor + 1, patch 0, DebugMode off), Upload To Steam, restart Palworld on the host and the subscribed second machine, read `UE4SS.log` filtered on `[LootablePassives]`. Hot reload is off.
- **Startup must still read** `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.` plus the `All N hooks installed: ...` line. Item 1 changes N.

The per-frame hooks, for judging whether a change touches a hot path:

| Hook | Registered in | Fires | Runs |
| --- | --- | --- | --- |
| `WBP_OperatingTable_TabPage_C:Update Button State` | `main.lua` | every frame while the Surgery tab is open | `on_update_button_state`, then the coalesced `ui.enforce_extraction_gate` |
| `PalBuildObjectConvertCharacterToItem:OnProceedConvertProcess_ServerInternal` | `lp/conveyor.lua` | every frame while a conveyor is converting | `conveyor.pass` |
| `PalMapObjectConvertCharacterToItemModel:OnUpdateCharacterContainer_ServerInternal` | `lp/conveyor.lua` | when a Pal arrives or leaves | `conveyor.pass` |
| `WBP_OperatingTable_C:OnPassiveUpdate` | `main.lua` | after any passive change | cheap unless a refresh is armed |
| `PalMapObjectOperatingTableModel:RequestRequestChangePassiveSkill_ServerInternal` | `main.lua`, bare `RegisterHook` | once per surgery request, vanilla included | `transaction.capture_record`, then `transaction.schedule_finalize` |

## Suggested order

1. Item 7 first. It is a decision rather than code, and it settles behaviour that already shipped in the working tree.
2. Then items 1, 3 and 6, which are contained and have clear verification.
3. Then item 2, which is mechanical but broad.
4. Items 4 and 5 last. Both are micro-optimisations that need engine facts confirmed first.

## 1. Register `SERVER_REQUEST` through `hooks.register`

### Now

`main.lua` calls `RegisterHook(SERVER_REQUEST, pre, post)` directly, at the top level, before any other registration. `lp/hooks.lua`'s `register` takes only one callback, so this hook cannot use it. As a result, `SERVER_REQUEST`:

- gets no bounded retry and no re-arm in `hooks.rearm_on_map_load`;
- is missing from the `All N hooks installed: ...` line;
- would stop `main.lua` outright if `RegisterHook` raised: the widget hooks, conveyor, recovery and the startup counts line would never load.

### Change

- Give the registration entry an optional `post_callback`.
- In `hooks.attempt`, call `pcall(RegisterHook, entry.path, entry.callback, entry.post_callback)` when it is set and the existing two-argument form when it is not. Branching avoids passing an explicit `nil` third argument, whose handling by UE4SS has not been checked.
- Extend `register`'s signature, for example with a trailing `post` parameter or an options table. Keep the callbacks built once, at load, by the caller.
- Move `main.lua`'s two inline callbacks to module-level locals and register through `hooks.register` with a label such as `"the Surgery Table request watcher"`.
- Update the header comment in `lp/hooks.lua`, which currently says `SERVER_REQUEST` bypasses it.

### Risk

Low to moderate. The hook targets a `/Script/` native function, so it should still register on the first attempt at load, as it does now. The visible change is the startup line: one more hook is listed. The `announce_if_complete` count rises from 4 to 5, or from 3 to 4 with `conveyor_extraction = false`.

### Verify

The startup log lists the new label in `All N hooks installed`. Run one extraction and one vanilla surgery and confirm both resolve as before.

## 2. Drop `unwrap` from `util.is_valid`

### Now

`util.is_valid(object)` starts with `object = unwrap(object)`. Since `util.field` and `util.method` unwrap their own results, nearly every value reaching `is_valid` is already unwrapped. The extra `unwrap` costs a `pcall` and a failed `.get` member lookup per call, and `is_valid` runs several times per frame on both hot paths.

### Change

- Remove the `unwrap` from `is_valid` and document that it takes an unwrapped value.
- Before doing so, audit every `is_valid(` call site (`Grep` for `is_valid\(` under `Scripts/`) and confirm each argument is one of:
  - a `field`/`method` result;
  - a `find_all`/`find_first` result;
  - an explicitly unwrapped value: hook contexts (`main.lua` unwraps before `note_live_page` and `note_live_screen`, `conveyor.pass_if_valid` unwraps `model_param`) and array elements (`conveyor` unwraps `array[index]` and the `container:Get` result);
  - a value stored from one of the above, such as `snapshot.parameter`, `live_page`, `live_screen`, `record.parameter`.
- `util.find_first` calls `is_valid` on a raw `FindFirstOf` result. That is a UObject with no `.get`, so it is unaffected.

### Risk

Moderate, and silent. A wrapped value that slips through reads as invalid, and the feature behind it switches off with no error: the gate stops blocking, a capture returns nil, or the conveyor skips a model. Only a game test shows it.

### Verify

In game:

- the Edit button blocks on an empty slot with an extract operation selected;
- an extraction and an implant both resolve;
- a conveyor run logs `Disassembly yielded ...`.

## 3. Conveyor: an unreadable queued Pal re-walks the container every frame

### Now

In `conveyor.pass`, a key present in `rates` but absent from `bucket` triggers `read_queued_passives(model)`. If that walk cannot produce a snapshot for the key, because the slot, handle or parameter does not read, nothing is stored in `bucket`. The next frame takes the same branch, so the full container walk repeats every frame until the Pal leaves the queue. Each walk calls, per slot:

- `container:Get`, `GetHandle` and `TryGetIndividualParameter`;
- a GUID format;
- `get_skill_ids` and `owner_key`.

### Change

- Keep a per-bucket set of keys whose snapshot failed, for example `bucket_unreadable[key] = true`, or a sentinel entry in `bucket` with no `passives`, that suppresses the walk.
- Retry those keys on a cheaper trigger: only from the container hook, which fires on arrival and departure, or every N frames.
- Clear the mark when the key leaves `rates`.
- The resolution loop at the end of `pass` iterates `bucket` and reads `entry.rate`. A sentinel stored in `bucket` must therefore not be treated as a consumed Pal: give it no passives, or keep the unreadable set separate.

### Risk

Moderate. It changes when an unreadable Pal is retried. A Pal that becomes readable only between container-hook firings would be read later, or never if it is consumed before the next retry. Today it is retried every frame, which is the one thing this item removes.

### Verify

There is no known way to force an unreadable slot in normal play. At minimum, confirm a normal conveyor run still logs `Disassembly yielded ...` with the right module count. A temporary probe that forces `read_queued_passives` to return `{}` for one key confirms the walk stops repeating.

## 4. Conveyor: per-frame allocation and GUID formatting

### Now

Every firing of the proceed hook, which fires every frame while converting, does the following in `conveyor.pass` and its helpers:

- builds a fresh `rates` table in `read_process_rates`;
- formats one GUID string per queued Pal through `passives.instance_key`, then `util.guid_key`, then `string.format`;
- formats the model's own GUID in `bucket_for` to pick its bucket in `tracked`.

### Change

- **Reuse the table.** Reuse one module-level `rates` table, cleared at the start of each pass, instead of allocating one. This is safe as long as nothing holds a reference to `rates` past the pass. `pass` only reads it within the pass.
- **Key buckets more cheaply.** Key `tracked` by something cheaper than a formatted GUID. `model:GetAddress()` is the usual UE4SS idiom, but whether the address is stable for the model's lifetime, and whether two models can reuse an address across a level change, has not been verified. `ui.forget_live_widgets` on map load is the existing reset point; `tracked` has no equivalent and would need one if keyed by address.
- **Do not throttle `pass`.** The last rate seen before a Pal leaves decides consumed versus withdrawn (`COMPLETE_RATE`).

### Risk

The table reuse is low risk. Re-keying by address is moderate: a reused address could hand one conveyor's bucket to another, which `pass` would then resolve as departures.

### Verify

- Two conveyors converting at once each log their own `Disassembly yielded ...` lines.
- A withdrawn Pal (removed below `COMPLETE_RATE`) logs nothing and grants nothing.

## 5. Owner filter in `passives.snapshot_all` formats a GUID per world object

### Now

`snapshot_all(owner)` runs on the `SERVER_REQUEST` pre-callback, on the game thread, whenever the transaction falls back to the owner snapshot: remote requests, dedicated servers, or no recorded tab page. It calls `owner_key(parameter)` for every `PalIndividualCharacterParameter` in the world, wild Pals included. Each call is two property reads, a `pcall`, and a `string.format`, compared against the requester's key string.

### Change

Read the requester's four GUID ints once, then compare `A`/`B`/`C`/`D` numerically per Pal, building no strings. This needs a second form of `util.guid_key` that returns the four parts, or a comparison helper. Keep the null-GUID rule: a GUID that reads all zero must never match.

### Risk

Low to moderate. It touches the owner matching that decides whose Pal a request may act on; a wrong match grants a module to the wrong player. The saving is only noticeable in large worlds.

### Verify

On the snapshot path, which is easiest to reach by closing the Surgery screen between confirming and resolving, an extraction resolves to the right Pal. A vanilla surgery logs the no-marker line.

## 6. Finalize retries allocate two closures per attempt

### Now

`transaction.schedule_finalize` calls `util.run_later`, which builds one closure for `ExecuteWithDelay` and one for `ExecuteInGameThread` on every call. `finalize_extraction` reschedules itself up to `RESOLVE_ATTEMPTS` (12) times, at `RESOLVE_INTERVAL_MS` (250 ms), while no list has changed. That is up to 24 UE4SS callback refs per request. Requests are not per-frame, so this is registry churn, not the crash pattern, but it is the same kind of allocation `CLAUDE.md` warns about.

The vanilla early exit in `finalize_extraction`, which stops at the first attempt that sees a list change with no marker, already removes most of it. What remains is a request whose lists never change, such as a refused operation.

### Change

- Build the two scheduler callbacks once, at load, and have them pop `{ record, attempt }` work items from a module-level FIFO.
- Every enqueue uses the same delay, so callbacks fire in enqueue order and the FIFO stays aligned with them. The first attempt currently uses 100 ms (`main.lua`) and retries use 250 ms. Either unify them, or keep one FIFO and prebuilt callback pair per delay.

### Risk

Moderate. It changes scheduling order if two requests overlap. Keep `schedule_finalize`'s signature, so `main.lua` is unchanged.

### Verify

- An extraction and an implant resolve as before.
- Two quick surgeries in a row both log their outcome.
- A refused vanilla operation, such as one with too little gold, logs `No marker appeared ...` after about 3 s.

## 7. Decide: panel refresh after the vanilla early exit

### Now

When `finalize_extraction` sees a vanilla operation, through the second return of `resolve_record`, it calls `finish`. Since the record has no `mode`, `ui.on_transaction_complete(nil)` arms a full panel reset: `reset_panel = true` clears the operation chip and consume-item count, and the operation list is rebuilt. That runs at about 0.6 s, plus the unconditional reset at 1.6 s.

Before the early exit existed, the same reset ran after all 12 attempts, at about 3.3 s. The behaviour is unchanged; only the timing moved closer to vanilla's own repaint.

### Decide

Whether a vanilla operation should trigger this mod's panel reset at all. The panel repair exists to repaint after this mod's own swaps; for a vanilla operation, the selection being cleared is not this mod's.

### If no

Log without the refresh on both no-marker paths: the early exit and the out-of-attempts `No marker appeared` branch. For example, add a `log_only` variant of `finish`, or have those two branches call `log` directly. `finish` already skips the refresh for remote records, so the panel logic itself needs no change.

### Verify

After a vanilla surgery, the Surgery panel shows vanilla's state with no flicker or cleared selection.

## Considered and not worth doing

Recorded so a later review does not re-raise them:

- `main.lua` repeats util's script-directory computation. It must run before `require` works, because it sets `package.path`. The same applies in `tools/ledger_test.lua`.
- `tools/ledger_test.lua` uses raw `io` rather than util's file helpers. This is on purpose: it checks the file the ledger wrote without going through the code that wrote it.
- The bucket get-or-create pattern in `conveyor.bucket_for` and `ledger.bucket_for`, `ui.current_page` against `ui.current_screen`, and the two `find_first("PalPlayerCharacter")` calls in `main.lua` and `lp/hooks.lua` are each too small for a shared helper.
- In `tools/stage.ps1`, the `$stale +=` accumulation is quadratic and `Copy-Item` copies the whole payload on every run. It runs over about a hundred files, so neither is worth changing.
