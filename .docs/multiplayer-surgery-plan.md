# Multiplayer Surgery Table plan

Working plan for the Surgery Table extraction path when the player who clicks Edit is a multiplayer client rather than the host. Investigation dated 2026-10-04, against version 1.0.3 as staged. Item 7 of `.docs/simplify-backlog.md` is settled by the design below and should be removed from that file when this lands.

Function names are used instead of line numbers. Read the named function before acting on anything here, and treat code comments as unverified, as `CLAUDE.md` requires.

## Symptom

With both machines on the same build, every extraction a client performs is completed correctly by the host: the module lands in the client's inventory and the marker comes off the Pal. The client's Surgery panel, however, is left in a stale state after the exchange. The host's own panel is fine.

## How the path runs today, per peer

The engine splits one surgery into a request on the clicking peer and an execution on the server. From `CXXHeaderDump/Pal.hpp`:

- `UPalMapObjectOperatingTableModel::RequestChangePassiveSkill(targetHandle, skillIndex, PassiveSkill)` runs on the peer that clicked. The screen calls it from `BndEvt__..._6_RequestChangePassiveSkill__DelegateSignature`.
- `UPalNetworkMapObjectComponent::RequestConcreteModel_Server_FPalNetArchive(ConcreteModelInstanceId, FunctionName, Value)` carries it to the server.
- `UPalMapObjectOperatingTableModel::RequestRequestChangePassiveSkill_ServerInternal(RequestPlayerId, Archive)` runs on the server only. This is the function `main.lua` hooks as `SERVER_REQUEST`.
- `APalPlayerState::NotifyOperatingPassiveComplete_ToClient(IsSuccess)` is how the server tells the requesting peer the vanilla operation finished. The screen's `OnOperatingPassiveNotifyied(Success)` hangs off the matching `OnOperatingPassiveComplete` delegate.
- `UPalIndividualCharacterParameter::OnPassiveSkillUpdateDelegate(PassiveIds)` fires on a peer that holds the Pal when its passive list changes. The screen's `OnPassiveUpdate(PassiveIds)` is bound to it, and `main.lua` hooks it as `PASSIVE_UPDATED`. Whether it also fires for this mod's own `RemovePassiveSkill` calls is not established; see the last screenshot below.

What each peer's copy of this mod does with one extraction:

| Step | Host, own request | Host, client's request | Client, own request |
| --- | --- | --- | --- |
| `SERVER_REQUEST` pre-hook | fires; `capture_record` reads the tab page (`targeted UI`) | fires; `is_remote_request` is true, so `snapshot_server_parameters` snapshots the requester's Pals (`owner snapshot`) and sets `remote = true` | never fires: the function is server-side |
| Vanilla swap | passive replaced by marker | passive replaced by marker, replicated to the client | sees the marker arrive; `OnOperatingPassiveNotifyied` runs; vanilla reflects the marker as the new passive |
| `finalize_extraction` | grants module, removes marker | grants module into the client's inventory, removes marker | nothing |
| `finish` | logs; `on_transaction_complete(mode)` arms the panel reset | logs; skips the panel reset because `record.remote` | nothing |
| `PASSIVE_UPDATED` hook | fires; `refresh_pending()` may be true | fires for the client's Pal only if the host's screen is bound to it | fires with the marker gone; `refresh_pending()` is false, so nothing happens |
| Panel repair | `refresh_surgery_ui` at 500 ms and 1600 ms | none, correctly: not the host's panel | none |

The last row is the defect. Panel repair is only ever started from `finish`, `finish` only runs where the server hook fires, and `finish` correctly refuses to touch the host's panel for a client's exchange. No peer repairs the client's panel.

## What the client is left looking at

`refresh_surgery_ui` writes back the fields vanilla leaves behind after the marker is removed under it: `CachedPassiveSlotIndex` to -1, `UpdateCurrentConsumeItem(None)`, `Set Passive Empty Item`, `ReflectPassiveChange`, `RefreshCurrentPassiveItem`, the screen's `CachedConsumeItemId`, `SetupPassiveChangeItem` and `RefreshItemDisplay`. On the client none of these are written. The screenshots below show that vanilla itself clears part of this on a successful operation, so what the client is actually left with has to be confirmed with client screenshots; the candidates are the right-hand Pal detail still listing the marker and the swept passives, a stale module count in the operation list, and the Edit button state. Closing and reopening the screen rebuilds everything, which matches the Known limitation already in `README.md`.

A stale panel can also send a second request. A re-click with `CurrentPassiveId` still set to a marker sends another `RequestChangePassiveSkill`, which the server charges 1000 gold for if it accepts it.

## Evidence from the host log, 2026-10-04 17:26 to 17:40

Player 259 is the host, player 260 the client. Lines tagged `[LootablePassives]`:

- 17:28:40 `Extracted 2 passive(s) from this Pal for player 259 (targeted UI): MoveSpeed_up_2 plus 1 more.`
- 17:36:52 `Extracted 3 passive(s) from this Pal for player 260 (owner snapshot): SwimSpeed_up_1 plus 2 more.`
- 17:37:47 `Extracted PAL_Sanity_Down_2 into LP_Implant_PAL_Sanity_Down_2 for player 260 (owner snapshot).`
- 17:38:02 and 17:38:08 `No marker appeared, so this was not one of our operations; nothing was changed.`

The two `No marker appeared` lines are remote requests: a vanilla operation by the host itself logs nothing, because `capture_record` returns nil when the tab page is present and holds no operation of ours. Each means a request from the client whose owner snapshot saw no passive list change within 3 seconds. Two causes fit, and the log cannot tell them apart:

1. A request sent from the stale panel that the server refused, for example a slot index past the end of the list after the extract-all.
2. A request on a Pal the client does not own. See the owner filter section.

The client's own `UE4SS.log` was not available to this investigation. It is on the other machine.

## Evidence from the click-by-click screenshots

`.docs/Screenshot (240).png` through `(253).png`, in filename order. They were cropped after the session, so their file times mean nothing; only the numbering is the sequence. The Pal carries Runner and Swift and two Disposable Implant toasts arrive at the end, which matches the 17:28:40 host line above (MoveSpeed_up_2 is Runner, and the one more is Swift), so this set documents the host's own extract-all, not the client's.

| Shot | What the player sees | Engine step, from the widget headers | What this mod does here |
| --- | --- | --- | --- |
| 240 | Surgical Table Menu prompt | none | nothing |
| 241 | Pal Operating Table opens; the list holds the three party Pals and nothing else | `Setup`, `OnSetup`; the tab page is constructed | `Update Button State` starts firing; `note_live_page` records the tab page |
| 242 | first Pal selected; the right-hand Pal detail opens showing Runner and Swift | `On Click Pal List(Handle)` sets `CurrentHandle` and `BindedCharacterParam`; the detail's `BindFromHandle` | nothing |
| 243, 244 | Transfer Passive tab; empty chip; Edit grey | `SwitchPanel(true)`; `CurrentPassiveId` is None; vanilla's `EnabledButton` is false | gate pass finds no operation pending and releases |
| 245, 246 | Passive Skill Selection list; vanilla recipe rows read `Implant: X`, this mod's rows read `Disposable Implant: X` with a count, rows with no item read `--------` on a grey chip; `Extract All Passives` and `Extract Passive` sit at the bottom with the grey chip and this mod's tooltip | `SetupPassiveChangeItem` builds one `WBP_OperatingTable_ItemList_C` per row through `Setup(PassiveId, IsValid)` | nothing; the grey chip and `--------` are what vanilla draws for `RequireItemId: None` |
| 247 | chip shows Extract All Passives; `Change which passive?` row appears with Runner, Swift and an empty slot; Required Gold 1,000; Edit grey | `OnSelectItem(PassiveId, ConsumeItemId)` on the row, `On Select Passive Change` on the screen, `Set Passive Has Item` and `UpdateCurrentConsumeItem` on the tab page; `CurrentPassiveId` is now `LP_ExtractAll` | gate sees an extract mode with no slot and blocks the click; vanilla already has the button grey |
| 248, 249 | Runner slot hovered, then selected; Edit turns blue | `OnSelectPassiveSlot`; `CachedPassiveSlotIndex` becomes 0; `Update Button State` sets `EnabledButton` | gate finds Runner extractable and releases. Everything a request record needs is on the tab page now: `CurrentPassiveId`, `CachedPassiveSlotIndex`, `CachedCharacter`. On the host `capture_targeted_record` reads exactly these, but only when the server hook fires |
| 250 to 252 | Edit focused; vanilla's confirm dialog `Grant this Pal Extract All Passives?`; Yes | `ConfirmPassiveOperate(true)`, the tab page's `RequestChangePassiveSkill(PassiveId, SlotIndex)` delegate, the screen's bound event, then the model's `RequestChangePassiveSkill(CurrentHandle, skillIndex, PassiveSkill)` and the network request | nothing on the clicking peer. The server hook fires next, on the host only |
| 253 | three things in one frame, listed below | vanilla swap done, `OnOperatingPassiveNotifyied(true)` received, `OnPassiveUpdate` received with the marker in the list | `finalize_extraction` has run: the two toasts are its grants |

Shot 253 in detail:

1. The centre panel is back to the empty chip, the `Change which passive?` row is gone, and Edit is grey. The toasts are still sliding in from the left edge, which puts this frame close to the grant and before the 500 ms refresh could have run, so this reset is most likely vanilla's own post-operation handling and not this mod's. If that holds, `reset_panel`'s writes repeat vanilla on the success path, and what this mod uniquely adds on the host is the list rebuild and whatever restores the Edit button.
2. The right-hand Pal detail lists `Extract All Passives` in the first slot and `Swift` in the second. That is the list immediately after the vanilla swap. The grants in the toasts come from the same `finalize_extraction` call that removed Swift and then the marker, so the Pal's list was already shorter when this frame was drawn, and the detail had not caught up. Either the detail is a frame behind, or `RemovePassiveSkill` does not fire `OnPassiveSkillUpdateDelegate` and nothing re-renders the detail for this mod's removals. `refresh_surgery_ui` does not touch `WBP_IngameMenu_PalBox_PalDetail`; on the host the detail evidently catches up by some path, since the host reports no odd state, but nothing in this mod makes it.
3. Two `Disposable Implant` toasts: the Runner module and the Swift module, granted in that order by `finalize_extraction` and `extract_all_remaining`.

The one frame cannot separate "a frame behind" from "never updated". A timed run settles it: see Verification.

## Second gap: the owner filter on the remote snapshot

For a remote request, `snapshot_server_parameters` passes the requester's `PlayerUId` to `passives.snapshot_all`, which keeps only Pals whose `OwnerPlayerUId` matches. Shot 241 shows the Surgery Table lists the player's party only, so the exposure is a party Pal whose `OwnerPlayerUId` is another player's, such as one caught by a guild-mate and taken from the shared Palbox. Whether `OwnerPlayerUId` follows a Pal into another player's party or stays with the catcher has not been checked. For such a Pal:

- the vanilla swap puts the marker on it and charges the client;
- no snapshot covers it, so `resolve_record` finds nothing for 12 attempts;
- `stranded_marker` searches `record.snapshots` only, so it finds nothing either, writes no journal row, and logs `No marker appeared`;
- the marker stays on the Pal, nothing is granted, and `lp/recovery.lua` never acts on it, because it acts only on a journal row.

The host's targeted path has no such filter: it reads `CachedCharacter` off the page, whoever owns it. The filter exists so that two players' simultaneous requests cannot grant one player's module to the other. `resolve_record` already refuses when more than one snapshot shows a marker swap, so an unfiltered snapshot is protected against that crossing by the single-candidate rule.

Check before changing anything: look through the party and Palbox for a Pal carrying `LP_ExtractOne` or `LP_ExtractAll`. One present means this happened in the last test.

## Dedicated server

`inventory.local_player_id` returns nil on a dedicated server, so `is_remote_request` is false for every request, `capture_targeted_record` finds no page, and the snapshot record carries `remote = nil`. `finish` then arms a panel reset on a machine with no panel, and `refresh_surgery_ui` logs once that the panel was closed. Harmless, but misleading, and the design below removes it.

## Design: panel repair as a local observation

Make the Surgery panel repair something each peer decides from what its own screen sees, and take it out of the transaction entirely. The transaction keeps capturing, granting, removing and journalling on the server. The UI module learns that an exchange was asked for, that vanilla's half landed, and that the server's half finished, from events that fire on the clicking peer whether that peer is host or client. The screenshots fix where each of those events sits in the click path.

### Request side: shots 250 to 252

Hook `/Script/Pal.PalMapObjectOperatingTableModel:RequestChangePassiveSkill`. It is native, so it registers at load like `SERVER_REQUEST`, and it runs on the peer that clicked. Its parameters are the handle, the slot index and the passive id. When the passive id is a key of `EXTRACTION_MODES`:

- record in `lp/ui.lua` one local pending exchange: the mode, the passive list of the page's `CachedCharacter` at that moment, and the time;
- log one line naming the operation and that the peer is waiting for the exchange to finish;
- arm one bounded timeout, for example 5 s, through one prebuilt callback. A click is not a per-frame path, but keep the callback module-level all the same.

A vanilla passive id records nothing. That is what settles backlog item 7: a vanilla surgery can no longer arm a panel reset on any peer.

Two Blueprint alternatives carry the same facts: the tab page's `ConfirmPassiveOperate(OK)`, which is the Yes click itself, and its `RequestChangePassiveSkill(PassiveId, SlotIndex)` delegate. Both need `hooks.register`'s retry machinery, since the widget does not exist at load. Prefer the native one.

### Vanilla completion: the first half of shot 253

`WBP_OperatingTable_C:OnOperatingPassiveNotifyied(Success)` runs on the requesting peer when the server's `NotifyOperatingPassiveComplete_ToClient` arrives, host or client alike. It is the moment vanilla's half is over: the gold is charged, the marker is on the Pal, and vanilla has reset the centre panel. This mod does not hook it today. Hooking it, through `hooks.register` like the other two widget hooks, gives two things:

- `Success` false means the server refused the request, so the local pending exchange is dropped and nothing waits for a marker that will never come;
- `Success` true marks the pending exchange as past the vanilla phase, so the completion check below can start, and the log on the client can say that the host accepted the request.

This is optional for the first cut: the completion check below works without it. It is the cleanest place to learn about a refusal.

### Completion side: the second half of shot 253

The completion check is a direct read, not an event: while a local exchange is pending, read `passives.get_skill_ids` on the page's `CachedCharacter` and call the exchange finished when the list holds no `EXTRACTION_MODES` id and differs from the list recorded at the request. Then call `on_transaction_complete(mode)` and clear the pending exchange. Reading directly is what makes the check independent of whether `OnPassiveSkillUpdateDelegate` fires for this mod's removals, which shot 253 leaves open.

The read is triggered by whichever of these arrives, each of which may or may not fire on a given peer:

- `OnPassiveUpdate` on the screen, through the existing `PASSIVE_UPDATED` hook. Extend `main.lua`'s `on_passive_update` to call into `lp/ui.lua`; the `PassiveIds` argument can be read with `util.unwrap`, `util.array_count` and `util.name_to_string` for the log, but the check itself reads the Pal.
- `On Update Local Player Inventory` on the tab page, a zero-argument event that fires when the local player's inventory changes. On the client that is the module arriving from the host, which for an extraction is a strong sign the server's half has run; the removals happen in the same server tick and replicate with it or shortly after. Register through `hooks.register`. It is not a completion signal for an implant, where the inventory changes in the vanilla phase, so it only triggers the read.
- A bounded poll as the fallback, for example every 250 ms up to the timeout, so a peer where neither event fires still finishes. One prebuilt callback and a module-level record, as `main.lua`'s `coalescer` does, rather than `util.run_later`, which allocates per call.

On timeout with the exchange still pending, log that the server did not finish it, run the same reset, and clear.

An abort that restores the passive, a stray marker on an empty slot, and an implant whose alias is replaced by its target all end with a list holding no marker, so all of them finish. The host's screen reads the removals as they happen, so the host finishes at the same moment it does today.

### What the repair must also cover: the Pal detail

`refresh_surgery_ui` repairs the tab page and the operation list and nothing else. Shot 253 shows the right-hand `WBP_IngameMenu_PalBox_PalDetail` still listing the marker after the removals. If the timed run shows the detail does not catch up on its own, the repair has to drive it. From `WBP_IngameMenu_PalBox_PalDetail.hpp` and `WBP_OperatingTable.hpp`, in order of preference:

1. The screen's `On Click Pal List(Handle)` with the screen's own `CurrentHandle`. One pointer argument. It re-selects the Pal and rebinds the tab page and the detail from the Pal's current state, which is what reopening the screen does by hand.
2. The detail's `BindFromHandle(targetHandle)` with the same handle. One pointer argument; rebinds the detail alone.
3. Not `SetPassiveSkill(TArray<FName>&)`: the array is passed by reference, which is the out-parameter shape `CLAUDE.md` says to avoid.

Either call takes an argument, so it is written out at its call site with a prebuilt `_call_` helper, not through `util.method`, and the first in-game attempt is preceded by a log line naming the call.

`on_transaction_complete` keeps its 500 ms and 1600 ms timers. `reset_panel` can stay for the abort paths, where vanilla's own reset may not run; whether it is still needed on the success path is a question for the timed run.

### Transaction side

`transaction.finish` becomes log-only on every peer. Remove the `record.remote` branch and the `ui.on_transaction_complete` call from it. `capture_record`, `is_remote_request` and the snapshot fallback stay: they decide what the server resolves, not what any panel shows. `remote` may then be dropped from the record if nothing else reads it.

### Owner filter

Decide between:

1. Drop the filter for remote requests and snapshot every Pal, relying on the single-candidate refusal in `resolve_record`. Costs one `GetPassiveSkillList` per Pal in the world per remote request instead of per owned Pal.
2. Keep the filter and widen to an unfiltered snapshot only when the owner snapshot has resolved nothing by the last attempt. More code, same worst case.

Either way `stranded_marker` then covers the Pal, so a stranded marker gets its journal row and recovery can remove it.

## Decisions taken, 2026-10-04

Implemented in the working tree on 2026-10-04, unstaged and untested at the time of writing. The client is a console, so client-side screenshots are not practical; the client's evidence will be its `UE4SS.log` and the host's observations.

- Owner filter: option 1. `snapshot_server_parameters` snapshots every Pal and `passives.snapshot_all` has no owner parameter. `inventory.player_uid` is gone with it. The record's `mode_source` for this path reads `server snapshot`.
- Timeout: 20 polls at 250 ms, 5 s. On timeout the panel is reset anyway and a WARNING names the marker state, so a stranded marker is visible in the log.
- `OnOperatingPassiveNotifyied` is hooked in this cut, as `the Surgery result watcher`. `Success` false drops the pending exchange with a log line; true marks it accepted and re-checks.
- `remote` is gone from the record. `is_remote_request` still decides whether the targeted capture is tried.
- Pal detail repair uses `BindFromHandle(CurrentHandle)` on the detail widget, and only when the detail reads as stale: it lists a marker, or a different set of ids than the Pal. Both readings are logged every time, so the first run shows whether the detail catches up on its own. The screen's `On Click Pal List` remains the escalation if `BindFromHandle` proves insufficient.
- `transaction.finish` is gone. Every outcome in `lp/transaction.lua` is a plain `log` call.
- `passives.first_marker` and `passives.name_list` are the shared helpers; `lp/recovery.lua` and `lp/ui.lua` both use `first_marker`.

Hooks after the change, in the `All 7 hooks installed` line: the Surgery request watcher, the Edit-button eligibility gate, the passive-update trigger, the Surgery result watcher, the inventory-update trigger, the conveyor progress watcher, the conveyor arrival/departure watcher.

## First host run, 2026-10-04 19:39, version 1.0.4

One extract-all on Foxcicle with Diet Lover, Coldblooded and Pacifist, slot 0 selected. Screenshots in `.docs/new/`, untouched since capture, so their times line up with the log.

What the log settled:

- The request hook fires on the host. `Requested LP_ExtractAll on slot 0 ...` at 49.198, so the screen does reach the model's `RequestChangePassiveSkill` through its UFunction.
- The vanilla swap landed 44 ms later: `OnPassiveUpdate: [LP_ExtractAll, ...]`, the marker line, then the server-accepted line 2 ms after that. Passive update before result notify, on the host.
- The transaction resolved at 49.397 and the exchange finished on the first poll at 49.455, 58 ms later. No event finished it: the inventory update fires at the grant, which precedes the removals, and no further `OnPassiveUpdate` arrived.
- **The parameter's delegate does not fire for this mod's `RemovePassiveSkill` calls.** Exactly one `OnPassiveUpdate` line per extraction. The poll is therefore the only completion path on the host, and the design's refusal to depend on events is what made this work.
- The screenshot at 50.727 shows the correct end state: empty chip, slot row gone, Edit grey, Pal detail with no passives, three module toasts.
- The detail read was wrong. The log said the detail still showed all three names after `BindFromHandle`, while the screenshot shows it empty. An emptied card keeps its last `BindedPassiveSkillName` and is hidden, so reading names alone reports stale cards that are not visible. `BindFromHandle` may well have done nothing; the read could not tell.
- `All 1 hooks installed` fired at load. The announce reports as soon as every registration made so far has taken, and the native request hook was registered first, alone. Ordering fault, not a missing hook.

Changes made after this run:

- `detail_passives` counts only cards whose `IsVisible()` reads true, and returns the hidden names separately so the log shows both.
- The detail is read and logged at the moment the exchange finishes, before any write of this module's, under the prefix `at finish`. The 500 ms and 1600 ms passes log under their own prefixes. Three readings in a row show who repaints the detail and when.
- Every event-driven check of a pending exchange logs the Pal's list with the trigger's name, so the inventory-update and result hooks can be seen firing.
- The native request hook is registered last in `main.lua`, after the widget hooks, so the hooks line waits for the world. `lp/hooks.lua`'s comment on `announce_if_complete` now states the ordering rule.

Still open after this run: whether vanilla or this module reset the centre panel, and whether vanilla or `BindFromHandle` emptied the detail. The `at finish` reading answers the second; the first needs a run with `surgery_ui_gate` left on and the timers' log lines compared against a screenshot taken between 49.5 and 50.1.

## Second host run, 2026-10-04 19:50 to 19:52, version 1.0.5

One extract-one on Broncherry, Waterproof in slot 1, then one extract-all on the same Pal. Screenshots in `.docs/new-2/`, untouched since capture. Their clock reads about 2 s behind the log's: the Yes dialog shot of the first exchange is stamped 19:51:58 and the request is logged at 19:52:01.2.

What the log settled:

- `All 7 hooks installed` once the world existed. The ordering fix holds.
- Both exchanges finished on the first poll, 58 and 42 ms after the transaction line. Request to finish was 265 and 255 ms.
- One `OnPassiveUpdate` per exchange, for the swap, as in the first run.
- **The Pal detail is stale at finish and at 500 ms, with the marker on a visible card, and `BindFromHandle` repaints it.** Both exchanges. Vanilla does not repaint the detail after this mod's removals, so the repair is load-bearing. After the rebind the emptied cards keep their old names and read as hidden, which is what the first run's name-only read tripped over.
- The inventory-update hook logged no check during either exchange. On the host, `On Update Local Player Inventory` does not fire for the mod's `AddItem_ServerInternal`. It stays registered for the client, where the replicated inventory may drive it.
- The screenshots at the end of each exchange show the correct state: empty chip, grey Edit, detail with the remaining passives, module toasts.

The odd frame at 19:51:09: Extract Passive just chosen, no slot selected, Edit grey, and the gamepad focus ring drawn around the whole slot group rather than one card. Not seen on the second pass, where the player moved onto a card first. The reading: `GetFocusTarget` on the tab page sends focus to Edit after the list closes; vanilla has already set `EnabledButton` false there, and the gate had also set the button's interaction off, which makes a CommonButtonBase unfocusable; focus fell back to the slot group container. The gate gains nothing in the no-slot state, since vanilla disables Edit there itself.

Changes made after this run:

- `enforce_extraction_gate` acts only while `CachedPassiveSlotIndex` is 0 or more. With no slot selected it releases, whatever operation is pending. The empty-slot block and the duplicate-implant block are unchanged.
- `log_detail_state` also prints the tab page's `CurrentPassiveId` and `CachedPassiveSlotIndex`, so the `at finish` line shows whether vanilla has already cleared the centre panel before the 500 ms refresh writes it.

Still open: who clears the centre panel on success. The `at finish` line now answers it. If vanilla does, `reset_panel`'s writes on the success path are redundant and could be dropped for extractions, leaving them for the abort and timeout paths.

## Third host run, 2026-10-04 20:13 to 20:14, version 1.0.6

One extract-one on Digtoise, slot 2, then one extract-all. Screenshots in `.docs/new-3/`. Uneventful: both exchanges finished on the first poll, the detail repair ran both times, and the hooks line read seven.

What the log settled:

- **Vanilla does not clear the centre panel on success.** The `at finish` line read `panel operation=LP_ExtractAll slot=0` with the marker still painted in the slot; the `refresh` line 700 ms later read `slot=-1`, which is this module's write. `reset_panel` is load-bearing and stays. `CurrentPassiveId` is never cleared by either side and stays at the marker id until the next selection; nothing reads it after the exchange, so that is left alone.
- The frame at 20:14:18 shows the marker painted in the selected slot and in the Pal detail, with the module toasts arriving. It sits in the window between the vanilla swap landing and this module's refresh: 250 ms of poll interval plus 500 ms of refresh delay, about 0.9 s in total. The marker cannot be kept off the screen entirely, since vanilla paints the swap result before the server half of the exchange has run and the swap is the mechanism; the window can only be shortened.

Changes made after this run:

- The exchange poll runs at 100 ms, 50 polls to the same 5 s timeout.
- The refresh runs on the tick after finish rather than 500 ms later, logged as `refresh on finish`. The 1600 ms reset stays as the late backstop for any repaint the game makes after the first refresh.
- Expected window after the change: about 100 to 150 ms on the host. If the game does repaint the marker after the early refresh, the `reset at 1600 ms` line will show the slot back at 0 and the detail stale again, and the 500 ms delay goes back in.

## Fourth host run, 2026-10-04 20:31 to 20:32, version 1.0.7

One extract-one and one extract-all on Mossanda, with an off-script step between them: the empty second slot was selected while Extract All was pending. Screenshots in `.docs/new-4/`.

What the log settled:

- The shortened window holds. Swap landed at 22.494, exchange finished at 22.687 on the second 100 ms poll, `refresh on finish` wrote at 22.869. About 375 ms from marker painted to marker gone, down from about 900. The `reset at 1600 ms` line read `slot=-1` with a clean detail both times, so the game does not repaint after the early refresh.
- The log has no line from the empty-slot moment. The gate runs on a per-frame hook and did not log, so a block left no trace.

The empty-slot moment, from the screenshots: vanilla painted Edit blue, since an empty slot is a valid target for a vanilla implant; the gate switched the button's interaction off, since an extract into an empty slot would put a stray marker on the Pal for 1000 gold; a CommonButtonBase with interaction off cannot take gamepad focus, so the cursor could not reach Edit; Cancel cleared the slot and the gate released. This is the blocked-and-lit behaviour `block_edit`'s comment describes, working as intended. It is a different case from the whole-block focus ring of the second run, where no slot was selected.

Change made after this run: `block_edit` and `release_edit` log on the transition, with the pending operation, slot index and the slot's passive. Never on the per-frame pass.

## Verification

### What to read in the next host log

One extract-all on the host, in the order the lines should appear. Every line carries the `[LootablePassives]` tag.

1. `Requested LP_ExtractAll on slot N of a Pal with [...]; waiting for the exchange to finish.` from the request hook. Missing means the screen does not call the model's `RequestChangePassiveSkill` through its UFunction, and the request side has to move to the tab page's `ConfirmPassiveOperate` or its `RequestChangePassiveSkill` delegate.
2. `OnPassiveUpdate: [..., LP_ExtractAll, ...]` as the vanilla swap lands, then `Marker LP_ExtractAll is on the Pal (...)`.
3. `The server accepted the LP_ExtractAll request; the vanilla half is done.` from the result watcher. Its position relative to line 2 shows the order the two vanilla events arrive in.
4. `Extracted N passive(s) from this Pal for player 259 (targeted UI): ...` from the transaction, unchanged.
5. Zero, one or two more `OnPassiveUpdate:` lines for the mod's own removals. Two means the parameter's delegate fires for `RemovePassiveSkill` and the Pal detail re-renders on its own; zero means neither, and the detail repair below is load-bearing.
6. `The LP_ExtractAll exchange finished (<trigger>, poll K): the Pal now has [...]. Repairing the panel.` The trigger names which event got there first: `OnPassiveUpdate`, `inventory update`, `operation notify`, or `poll`.
7. About 500 ms later, `Pal detail shows [...]; the Pal has [...]; ...` and, if stale, `Calling BindFromHandle on the Pal detail.` then `BindFromHandle returned; the Pal detail now shows [...]`. The same check repeats at about 1600 ms.

A vanilla surgery should produce only `OnPassiveUpdate:` lines and no request, exchange or detail line. A refused request should produce `The server refused ...` and nothing after it.

Screenshots to take on the host, with their timestamps intact: the frame right after Yes, one about 3 s later and one about 10 s later with the screen open, and one after reopening the screen on the same Pal. Each lines up with the log by time.

### After the change, on both machines

- Client extract-one and extract-all: the client log shows the request line, then the finished line, and the panel clears its slot and chip, the Pal detail shows the remaining passives, and the list rebuilds with the new module count. The host log shows the `owner snapshot` extraction as before and no panel line.
- Host extract-one and extract-all: unchanged behaviour, with the request and finished lines now in the host log too.
- A vanilla surgery on either peer: no `[LootablePassives]` line for it, and the panel keeps vanilla's state with no flicker.
- Implant insertion on the client: the alias name appears briefly, the target passive replaces it, and the operation list rebuilds with one fewer module.
- A client operation on a party Pal another player caught: resolves and grants to the client, or at least journals the marker so the next map load removes it.
- Startup still reads `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.` and the hooks line gains the request watcher and any new widget hooks.

## Rules that bind this work

From `CLAUDE.md`: every hook callback is built once at load and captures no per-call state; `pcall` is argument-form against module-level helpers on anything that fires often; arity of every new engine call is checked against the header dumps, and the functions named above take the arguments shown in `Pal.hpp`, `WBP_OperatingTable.hpp`, `WBP_OperatingTable_TabPage.hpp` and `WBP_IngameMenu_PalBox_PalDetail.hpp`; log immediately before any new engine call while probing. Update `README.md` and `.docs/workshop-description.txt` when the Multiplayer and Known limitation text stops being true.
