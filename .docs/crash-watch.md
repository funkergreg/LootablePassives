# Crash watch: Lua VM access violation

## Status

**Open, watching.** A candidate fix shipped in dev build 1.1.1. Nobody is trying to reproduce the crash on purpose. The watch runs across normal play sessions, and the work resumes only if the crash comes back.

## The crash

On 2026-10-17, build 1.1.0 crashed on the host at 17:18:05. The game had just left the world for the title screen. It was the session's first world→title transition, after about 6.5 hours of play, and the mod had last logged at 16:45.

- **Crash report:** `EXCEPTION_ACCESS_VIOLATION reading address 0xffffffffffffffff`, with a call stack made up of `UE4SS` and `Palworld_Win64_Shipping` frames and no symbols.
- **Faulting instruction:** `UE4SS.dll+0xc23502`, which is `mov edi, dword ptr [r10]`. This is Lua's VM fetching its next bytecode instruction, with `r10` as the program counter. `r10` held `0x000436f099727300`, which is not a valid address, and Windows reports a read from such an address as `0xffffffffffffffff`. In plain terms, UE4SS called a Lua function whose closure had already been freed or overwritten.
- **Entry path:** game → UE4SS hook dispatch (`UE4SS.dll+0x420b8e`) → code next to the `FURL` copy constructor (`+0x2786cf`, `+0x2dddab`; `FURL` is the argument type of `UEngine::LoadMap`) → `LuaMod` (`+0x2caef9`, `+0x2cae13`) → `LuaMadeSimple::Lua::call_function` (`+0xb48635`) → `luaD_call` (`+0xc1a369`) → `luaV_execute` (`+0xc233c0`, faulting at `+0xc23502`). This is UE4SS running a Lua `RegisterLoadMapPostHook` callback.
- **Whose callback:** two Lua mods register a `LoadMap` post-hook, BPModLoaderMod and LootablePassives. BPModLoaderMod starts first and logged its last line (`Actor: ModActor_C ...PL_Title...`) just before the crash, so its callback had finished. That leaves ours. This rests on registration order, not on a named frame, because UE4SS ships without a PDB.

### Root-cause theory

Before 1.1.1, every delay in the mod went through `ExecuteWithDelay`. UE4SS's documentation says `ExecuteWithDelay` "asynchronously executes" its callback. The callback therefore ran on UE4SS's async thread, against the same Lua state that the mod's game-thread hooks run in, and Lua is not thread-safe. While the Surgery tab is open, `Update Button State` fires at frame rate and scheduled the Edit-button gate through it each time. Damage done that way does not crash where it happens. A callback that runs only at map load would not trip over it until the next map load, which fits a crash at the first world→title transition after hours of play.

### What 1.1.1 changed

- **Delays:** every one now goes through `ExecuteInGameThreadWithDelay`, which the UE4SS docs say runs on the game thread: `util.run_later`, `util.coalescer`, the hook retry in `lp/hooks.lua`, and the two panel timers in `lp/ui.lua`.
- **Guard:** `.luacheckrc` and `.luarc.json` no longer declare `ExecuteWithDelay`, `ExecuteAsync` or `LoopAsync`, so a call to any of them reads as an undefined global.
- **Logging:** `util.log` now ends each line with `\n`. Before this, every `[LootablePassives]` line ran into the next entry in `UE4SS.log`.

## Earlier crashes on this machine

All the dumps in `%LOCALAPPDATA%\Pal\Saved\Crashes\` come from the same UE4SS build: `v3.0.1 Beta #0 - Git SHA #2281fa31`, `UE4SS.dll` timestamp `0x6a92fe50`. Their offsets therefore compare directly. Every one crashed on the game's main thread: each stack bottoms out at `Palworld-Win64-Shipping.exe+0x6556272` and `+0x9fd7310`.

| Date | Fault | Reading | Family |
| --- | --- | --- | --- |
| 2026-10-17 17:18 | `UE4SS.dll+0xc23502` | `0xffffffffffffffff` | Lua VM, `LoadMap` callback path, described above |
| 2026-09-20 19:36 | `UE4SS.dll+0xc20480` | `0x0000686374617340` | Lua VM, deep inside running Lua code |
| 2026-09-19 14:25 | `Palworld-Win64-Shipping.exe+0x32daeda` | `0x2a8` | Engine; the `StaticConstructObject` probe recorded in CLAUDE.md |
| 2026-09-15 23:10 | `UE4SS.dll+0xc21759` | `0xffffffffffffffff` | Lua VM, entered through `+0x2be970`/`+0x2beb19`/`+0x2bf7b8` |
| 2026-09-14 05:10 | `UE4SS.dll+0xc13008` | `0xffffffffffffffff` | Lua VM, entered through the same `+0x2be970` path |
| 2026-09-14 01:07–01:22 (5) | `Palworld-Win64-Shipping.exe+0x314f64c` | `0x478` | Engine null read, all five identical |

The Lua VM crashes from September predate 1.1.1 and so are consistent with the same cause, but their entry path (`+0x2be970` family) is a different UE4SS caller from the October one, and it has not been identified.

## Watch log

Add a row after each session that counts. What matters is how long the session ran with the Surgery Table in use, and how many world→title transitions it included, since that is where the October crash happened.

| Date | Build | Length | Surgery requests | Disassemblies | World→title | Result |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-10-17 | 1.1.0 | ~6.5 h | 31 or more | many | 1 | **Crashed** at the transition |
| 2026-10-18 | 1.1.1 | ~23 min | 10 (9 Extract All, 1 implant) | 54 | 1 | Clean; no LP warnings |

The 2026-10-17 counts are a lower bound. That log has since been overwritten, and the count comes from lines read before the newline fix, when other entries were glued onto them.

### When to close this

Proposed: three sessions of three hours or more each, each with steady Surgery Table use and each ending in at least one world→title transition, all without the crash. The October crash needed hours of play before it showed, so short sessions add little evidence. Adjust the bar as you see fit.

## If it happens again

### Collect first

UE4SS rewrites `UE4SS.log` at every launch, so copy it **before starting the game again**.

1. **Log:** copy `C:\Program Files (x86)\Steam\steamapps\common\Palworld\Mods\NativeMods\UE4SS\UE4SS.log` into `.docs\`.
2. **Crash folder:** note the newest `UECC-Windows-*` folder in `%LOCALAPPDATA%\Pal\Saved\Crashes\`. It holds `UEMinidump.dmp`, which is the one source that names the faulting address. The crash dialog text alone does not.
3. **Context:** write down what was happening: host or client, the action at the moment (leaving to title, loading a world, using the Surgery Table, idle), roughly how long the session had run, and the mod version on both machines.
4. **Client:** if the client crashed, collect the same files from that machine.

### Then triage

1. **Same UE4SS build?** Check the second line of `UE4SS.log` for `Git SHA #2281fa31`. If UE4SS has been updated, none of the offsets in this document apply, and the dump has to be read from scratch.
2. **Same signature?** Look for the faulting offset `UE4SS.dll+0xc23502`, or any offset between `+0xc10000` and `+0xc30000` (the Lua VM), reading `0xffffffffffffffff` or another wild address.
3. **Same entry path?** Find the UE4SS frames between `call_function` (`+0xb48635`) and the game frames:
   - `+0x2cae13`, `+0x2caef9`, `+0x2dddab`, `+0x2786cf` mean a `LoadMap` callback, as in October.
   - `+0x2be970`, `+0x2beb19`, `+0x2bf7b8` mean the September path.
   - Anything else is a new path.
4. **Read the log:**
   - **Last lines:** what the game was doing in the last lines before the crash.
   - **Errors:** search for `Ref was not function` or any other `[Lua::Registry]` error. That error preceded the earlier crash recorded in CLAUDE.md.
   - **The mod's state:** filter on `[LootablePassives]` and check whether an exchange was pending (`Requested ...` with no matching `... exchange finished`) or a warning was logged.
5. **Engine-side crash?** A crash inside `Palworld-Win64-Shipping.exe` reading a small address (like `0x478` or `0x2a8`) is a null pointer in engine code, a different family from this one. Treat it as a new problem.

### What each outcome would mean

- **Same signature and `LoadMap` path, on 1.1.1 or later:** the async-thread theory does not explain it on its own. The next suspects:
  - **Per-call allocations that remain:** `util.run_later` builds one closure per call. Each `ExecuteInGameThreadWithDelay` call also takes a registry ref inside UE4SS, even for a closure built at load.
  - **A UE4SS fault in its `LoadMap` callback dispatch,** independent of what the callback does.
  - **To narrow it down:** turn off `conveyor_extraction` and `surgery_ui_gate` in `settings.lua` for a session, or play a session with the mod disabled under **Options → Mod Management**, and see whether the crash follows.
- **Lua VM crash on the September path:** that caller is still unidentified. Identifying it is the first step.
- **No crash through the close-out criterion:** mark this document closed and record the outcome.

## Reading a minidump without a debugger

This machine has no WinDbg or `cdb`, and UE4SS ships without a PDB. The October crash was read like this, with Python and the `capstone` disassembler (`python -m pip install --user capstone`):

1. **Parse the dump's streams:**
   - **Exception stream (6):** the faulting address, the address it read, and the thread context, including `RIP` and `RSP`.
   - **Module list (4):** each module's base address, so an address converts to `module+offset`.
   - **Memory lists (5 and 9):** the captured stack memory.
2. **Scan the stack:** walk from `RSP` and keep every 8-byte value that falls inside a loaded module. Those are return-address candidates, in rough call order. The scan is a heuristic: it also picks up stale values, so read the frames as a likely path, not an exact one.
3. **Name the frames:** map each `UE4SS.dll` offset to the nearest exported symbol below it in the DLL's export table. UE4SS exports about 4,180 C++ symbols. The nearest export gives a neighbourhood, not the function name.
4. **Disassemble the faulting instruction:** convert the offset to a file position through the section table and disassemble around it with capstone.

The scripts used are `parse_dump.py`, `exports.py` and `disasm.py` in `%TEMP%\lp_dump\`. They live outside the repo, so Windows' temp cleanup may delete them, and they may need writing again.
