# Multiplayer validation: fixes 6 and 7

## Status

**Open, scheduled after the 1.2.0 release.** Both fixes ship in 1.2.0. They were verified by code review and single-player runs only, because each one changes behaviour only when a second machine is connected. Anything this validation finds goes into 1.3.0 or later.

Every other fix from the same code review was verified in game on dev builds 1.1.6–1.1.8, and is not tracked here.

## Setup

- **Two machines on the same version.** The host stages and uploads; the client subscribes and checks the version under **Options → Mod Management** before joining. The host must not be subscribed to the mod.
- **Choose the build.** A 1.2.0 release has `debug = false`, so no `DEBUG:` trace lines are printed and only the ordinary lines below are available. For the fuller trace, stage a dev build (`.\tools\stage.ps1`, which sets `debug = true`), upload it, and have both machines run that instead. `debug_faults` stays empty either way.
- **Collect both logs.** Copy `UE4SS.log` from both machines after the session and before either game is started again. It is at `<Palworld>\Mods\NativeMods\UE4SS\UE4SS.log`.

## Fix 6: recovery runs only on a peer with authority

### What changed

`recover_interrupted_extraction` in `Scripts/lp/recovery.lua` now does nothing unless `util.has_authority` returns true for a `PalPlayerCharacter`. This is the same check the conveyor and the ledger delivery use. Without authority, the journal row is left on disk and this line is logged:

```text
Recovery journal left on disk after <reason>: this peer has no authority over the world, or no player is loaded yet.
```

### The risk it addresses

Without the check, a machine that once hosted and was left with a journal row would replay that row as a **client** in someone else's world. That means calling `RemovePassiveSkill` and `AddPassiveSkill` on replicated state the client has no authority over, then deleting the journal. The host's own recovery would be lost, and the client's view could drift out of sync with the server.

### Single-player evidence so far

On 1.1.8 the title-screen map load had no player loaded. Recovery logged the line above and kept the row. The world load that followed recovered it. So the check is known to fail closed when no player is loaded, but it has not yet been seen on a client.

### Test

1. On the **client** machine, with the game closed, create `<Palworld>\Mods\NativeMods\UE4SS\LootablePassives_journal.tsv` holding this single line, with the fields separated by tab characters:

   ```text
   LPJ1	prepared	marker	Legend	LP_Implant_Legend	LP_ExtractOne
   ```

2. Start the client and join the host's world. Wait at least 10 s after the world loads.
3. Leave the world and delete the file from step 1.

### Pass

- The client log shows `Recovery journal left on disk after map load: this peer has no authority …` after the world load.
- The client log shows no `Recovered interrupted extraction` line.
- No Pal on the host or client changes.

### Fail

- The client log shows `Recovered interrupted extraction`, or any `WARNING: recovery journal found …` line. Either means recovery got past the check on a client.

## Fix 7: a request whose requester cannot be identified uses the server snapshot

### What changed

`capture_record` in `Scripts/lp/transaction.lua` now uses the host's recorded Surgery tab page only when the requester's `PlayerId` and the local player's `PlayerId` **both read and are equal**. Every other request goes to the server snapshot of all Pals. That includes a client's request, and a request whose `PlayerId` does not read. Before this change, an unreadable requester id was treated as the host's own request.

### The risk it addresses

On a listen server, suppose the host had the Surgery tab open while a client's request arrived, and the client's id did not read. The mod would then capture the **host's** selected Pal, find nothing change on it, and never track the client's exchange. The client would be charged gold, and their marker would be left on their Pal with no journal row, so nothing could recover it.

### Test

1. On the **host**, open the Surgery Table and leave the Transfer Passive tab open with one of the host's own Pals selected.
2. On the **client**, at a Surgery Table in the host's world, run **Extract One** on a filled slot of one of the client's Pals.
3. On the client, run **Extract All** on another Pal, and then an **implant**.
4. On the host, close the Surgery Table, then repeat one client extraction with the host's table closed.

### Pass

- For each client operation, the host log shows the finished line naming the **client's** player id and `(server snapshot)`, for example `Extracted <passive> into <item> for player <client id> (server snapshot).`
- The client receives each module, and the passives leave the client's Pals with no marker left behind.
- The host's selected Pal is unchanged.
- In a dev build, the host log also shows `DEBUG: capture: requester=<client id> local=<host id> is_local=false` followed by `DEBUG: capture: server snapshot of N Pals`.

### Fail

- A client operation produces no finished line on the host.
- A finished line says `(targeted UI)` for a client's request.
- A marker is left on a client's Pal.

### Not covered by this test

The path the fix actually changed, an unreadable requester `PlayerId`, cannot be forced in normal play. This test confirms that client requests go through the snapshot and that the host's open tab page does not capture them. Exercising the unreadable-id branch itself would need a new `debug_faults` entry.

## Results

| Date | Build | Fix | Result | Notes |
| --- | --- | --- | --- | --- |
| | | 6 | | |
| | | 7 | | |
