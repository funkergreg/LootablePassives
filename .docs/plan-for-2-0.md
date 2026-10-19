# Plan for 2.0

This doument is a planning base document for 2.0 features.

We started the previous mod versions by hacking at an eisting mod, and we ended up with bad paradigms as a result; for 2.0 we need to take a fresh perspective driven from official and near-official mod development guidance and re-asses many aspects of the mod and the development setup to build for stability and iteration of the mod, supporting best practices and building for mod stability and applicability in all cases.

It has been reported that dedicated server setup fails.  This was not previously intended to be covered by the mod, but the Steam community has left negative reviews based on dedicated server support being missing (and was only called out as not tested in the original docs, not as NOT WORKING).

For version 2.0 we want the mod to support specific cases:

- Co-op multiplayer where the hosts computer acts as the server
  - host and client perspectives for the mod.  It has been determined that host MUST have it for the mod to be operational since the mod grants items -- there cannot be a client-only option.  As such, we need need capability for checking in the client casse that the host has the mod installed, and disabling mod features if the host does not have it (so that if joining someone else's game Lootable Passives mod users don't need to unsubscribe from the mod in the Steam workshop NOR remember to manually turn off the Lootable Passives mod in the mod options --> this might be related to the `IsServer` option below, which will be confirmed in research).
- Dedicated server
  - Dual-requirement: f a player tries to join without matching the server's mod list, they will face errors or be blocked from connecting
  - In modern Palworld mod ecosystems, server-compatible mods must contain an explicit "IsServer": true flag inside their Info.json file. If this flag is missing, the dedicated server application will entirely ignore the mod, even if it works perfectly fine in a local co-op game.
  - It is OK if we call out Windows support only as this is a UE4SS/Lua mod which is traditionally Windows-only (would likely need a .pak mod via Unreal to support all environments)

## Scope decision, round 3 (2026-10-18): 1.3.0 first

**Dedicated-server support already works in 1.2.0** once the server has its own install. This was verified on a local PalServer; see 1.3-0. The next release is therefore a **minor** one, **1.3.0**, and it is planned in [Plan for 1.3.0](#plan-for-130) below. Round 5 put every item into 1.3.0, the handshake, concurrency and the module split included; nothing waits for a 2.0.

## Pre-requisite Research to be used in Planning

1. Research dedicated server hosting AND installing mods on a dedicated server AND developing mods for a dedicated server.
    - Deploy a dedicated server: <https://docs.palworldgame.com/getting-started/deploy-dedicated-server/>
    - Installing Mods on a server: <https://docs.palworldgame.com/settings-and-operation/mod>
    - See also this description of what actually works on a dedicated server mod: <https://connecthosting.net/blog/palworld-server-mods-what-works>
    - Mod Packaging, especially the dedicated server section: <https://pwmodding.wiki/docs/developers/mod-publishing/workshop/packaging#dedicated-server-support>
    - Differences in hosting options: <https://www.survivalservers.com/wiki/How_to_Mod_your_Palworld_Server_Guide>
    - Configuration parameters --> it is unlikely these will help or influence the plan, but there are things like player list and IP addresses that might help if the server config or client/host state cannot be determined via other means: <https://docs.palworldgame.com/settings-and-operation/configuration/>
2. Research additional tools and paradigms to assist in development and verification activities:
    - FModel is a useful open-source software for data-mining games made in Unreal Engine: <https://pwmodding.wiki/docs/developers/useful-tools/fmodel>
      - See also: <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/datatables>
    - A database containing everything about Palworld, including IDs for Items, Pals and more: <https://paldeck.cc> (NOTE: a full read not required, but get an overview of what is available for the existing vanilla disposable implants and mod recipes and update language about these, if possible)
    - Lua Modding Tools: <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/lua-modding-tools>
      - NOTE: has a slightly different dev path than our current which relies on an installed version of UE4SS which may be more reliable, PLUS it explains some of the variable usage (which we may be using incorrectly)
    - UE4SS Function Overview: <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/ue4ss-functions>
    - Our paradigm for granting implants may be incorrect for general usage on both multiplayer and dedicated server hosting options
      - Registering for object creation: <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/hooking-functions#registering-for-object-creation>
      - Subscribing to component creation: <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/hooking-functions#subscribing-to-component-creation>
    - Digging, including LIVE dump options! may speed our dev turnaround time and provide better verification of behaviors in-game versus our current play-close-readLogs cycle:
      - <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/digging-101>
      - <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/more-digging>
    - Config files (we have a settings.lua and a config.lua -- see if this is bad split paradigm): <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/config-files>
    - Using Blueprints with Lua: <https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/blueprints-with-lua>
3. Research options for being able to change mod settings in the UI should help dramatically with:
    - debug during dev: turn a feature on or off and see behavior with it each way.
    - as well as release options: enable surgery table and pal disassembly conveyor grants to be turned on and off so users can customize their experience.
    - Looking at building out support for existing options like (possibly dual support since these are related):
      - Better Mod Manager: <https://steamcommunity.com/sharedfiles/filedetails/?id=3803996980>
        - Great description on this page of how to mod and how to integrate
          - See template at: `C:\Program Files (x86)\Steam\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\BetterModManager\Scripts\template\MyMod`
          - Seems to pull `config.lua` up to peer of `main.lua`; look at restructuring between settings.lua and config.lua, deciding what to expose to apps like Better Mod Manager that assume a `config.lua` at top level (might need to rename our current `config.lua` as an under-the-hood settings, and create a top level `config.lua` as a peer of `main.lua`)
          - Related mod organizational structure, and possibly independendt: Is is cleaner to have `Scripts\passive_items.lua` fall back to `Scripts\lp` folder alongside other mod lua scripts? Is it cleaner to leave only main and settings/config at the top level?
        - Installed this one as a test.  I think this is the one that has the best support, so aim for this
        - last game run has initial setup logs: scan these for issues of setup (if there are warnings, we might run away).
          - Better Mod Manager's own config-in game: `.docs\Screenshot (291).png`
          - A third-party mod I use: `.docs\Screenshot (293).png`
        - At present my game is not officailly supported but it DID find my settings and presented them; See screenshot: `.docs\Screenshot (292).png`
          - We will need to make the desriptions of the Lootable Passives options MUCH shorter for UI display
      - Darn Menu: <https://steamcommunity.com/sharedfiles/filedetails/?id=3769456391>
4. Plan out the mod updates
    - Plan to support all cases of multiplayer: hosted with clients and dedicated server with clients.
      - Will likely require setting up a dedicated server and testing locally.  Downloaded the dedicated server hosting from Steam, but have not run it.  Location on-disk: `C:\Program Files (x86)\Steam\steamapps\common\PalServer`
    - Ensure the mod behaves correctly in all cases up to and including disabling itself it the host does not have it.
    - We might need to split some things into server and host/client execution rather than the current setup.  The current setup is heavily reliant on the journal, which might be too focused on the multiplayer host scenarios.
    - The journal at present does some things to determine 'ownership' which may not be lin line with modding best practices.  Re-assess after research the best means of storing transactions and granting items.

---

## Research findings

Round 1 research, 2026-10-18. Every claim carries a source tag:

- **[OFFICIAL]** comes from Pocketpair's docs or Pocketpair's uploader repo.
- **[LOCAL]** was verified on the dev machine: header dumps in `<Palworld>\Mods\NativeMods\UE4SS\CXXHeaderDump\`, exe strings, installed `Info.json` files, or `UE4SS.log`.
- **[COMMUNITY]** comes from wikis, hosting blogs, GitHub issues or Steam comments.
- **[INFERENCE]** is reasoning that has not been tested.

Line numbers into `Pal.hpp` and `Engine.hpp` refer to the CXX header dump on the dev machine and move with game updates.

### Corrections to the brief above

- **`IsServer` is already shipped.** 1.2.0's `Info.json` already has an `IsServer: true` copy of both the `Lua` rule and the `PalSchema` rule. That is exactly Pocketpair's documented pattern ([04-Tech.md](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/04-Tech.md)). `IsServer` is a per-`InstallRule` boolean, not a top-level key. The loader's struct is `FPalModInstallRuleStruct { Type; bool IsServer; TArray<FString> Targets; }` (`PalModLoader.hpp`). There is no `IsClient`: a rule without `IsServer` is a client rule. **The dedicated-server failure is therefore not a packaging defect.** [OFFICIAL] [LOCAL]
- **There is no mod-list matching on join.** The only official join gate is the server's `bAllowClientMod` world setting. When it is false, a client with mods enabled is refused with `"Mods are not allowed on this server. Please disable all mods and try again."` That string is in both the client and server exes. No replicated mod list exists in `Pal.hpp`, and `UPalModLoaderLibrary` is local-only. Hosting blogs that say "every player needs the same mods or gets connection timed out" cite nothing, and the binary shows no list check. **A client with this mod can join a host without it, and nothing tells either side.** [OFFICIAL] [LOCAL]
- **A listen-server host installs the client rules.** `IsServer` rules matter only to `PalServer.exe`. Co-op hosting therefore already works from the ordinary client install. [INFERENCE, consistent with pwmodding's wording]
- **The Workshop description file is at the repo root.** `workshop-description.txt` is tracked there, not at `.docs/workshop-description.txt` as `CLAUDE.md` said. **Resolved by the developer:** it stays at the root, and the `CLAUDE.md` and `README.md` references were fixed.

### What the Steam reports actually say

Source: [the Workshop comments](https://steamcommunity.com/sharedfiles/filedetails/comments/3805554239), read 2026-10-18. [COMMUNITY]

- **Kamigouki (dedicated server, v1.0.5.102999).** They installed by subscribing and enabling the mod in the game's options, and run a dedicated server on the same PC. The Surgery Table lists both extraction operations, but "when used, nothing happens". On the conveyor, "the Pal is lost and the base items are extracted, but no passive modules are given".
  - **Diagnosis [INFERENCE]:** this is the signature of a server running **none** of this mod. The client's own PalSchema adds the operations to its list. The server either has no matching rows and refuses the request, or has no Lua and grants nothing. Subscribing in the game client installs nothing on `PalServer.exe`: the server needs its own `Mods\Workshop\` copy (or `WorkshopRootDir`) and its own `ActiveModList` entries for UE4SSExperimentalPW, PalSchema and LootablePassives.
  - **The fix is part documentation, part runtime.** First, the server install steps. Then a client that detects a host without the mod and says so, instead of silently doing nothing (see the host-has-mod detection section below).
- **Awfulhorrid.** "About half the time it doesn't extract anything, resulting in the trait disappearing from the Pal with no resulting implant." This is a loss bug independent of server type. Candidate causes, all to be checked in the code:
  - The pre-callback timing on native hooks (see the hook-timing mismatch below).
  - The 12 × 250 ms resolve window.
  - The single-slot `pending_record`.
- **Zalakiaa.** Taking off "Jormuntide's specific passive" crashes the game. That means a species-unique passive. Check whether such passives are in the extractable list at all, and what extraction does to them.
- **b0b.** Running alongside "Surgery Trait Extractor" corrupted their saves. The description already warns about this.

### 1. Dedicated server and co-op

#### Installing mods on a dedicated server

Sources: [OFFICIAL] [docs.palworldgame.com/settings-and-operation/mod](https://docs.palworldgame.com/settings-and-operation/mod), [04-Tech.md](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/04-Tech.md).

- **Windows only.** "At this time, server-side mods work only on the dedicated server with Windows edition."
- **The loader is built into the server exe.** `PalServer-Win64-Shipping-Cmd.exe` carries the same loader strings as the client: `PalModSettings`, `WorkshopRootDir`, `ActiveModList`, `IsServer`, `-NoMods`, `bAllowClientMod`. No UE4SS DLL ships with the server. It arrives through the UE4SSExperimentalPW package, whose `UE4SS` rule has an `IsServer` copy. [LOCAL]
- **Where the server looks for mods.** By default it reads `.\Mods\Workshop\<any folder>\Info.json` next to `PalServer.exe`. `WorkshopRootDir=<abs path>` in `Mods\PalModSettings.ini`, or the `-workshopdir="<abs path>"` launch option, points it elsewhere. The ini is created on first launch. Per the docs, "all compatible mods found under the Workshop directory will be loaded"; whether that means every mod there or only the `ActiveModList` ones is an open question.
- **`PalModSettings.ini` format:** `[PalModSettings]`, `bGlobalEnableMod=true`, and one `ActiveModList=<PackageName>` line per mod. The connecthosting article's `ActiveModList=("a","b")` form is wrong.
- **Same install layout as the client,** under the PalServer root: `Mods\NativeMods\UE4SS\Mods\<PackageName>\` for Lua, `...\PalSchema\mods\<PackageName>\` for PalSchema, and `Mods\ManagedMods\<PackageName>\InstallManifest.json`.
- **Updates.** A changed `Version` redeploys on the next server restart, the same trigger the client uses.
- **No official steamcmd Workshop download step exists.** Mod folders are copied in by hand, or `WorkshopRootDir` is pointed at a client's `steamapps\workshop\content\1623730`.
- **The local PalServer has never been launched.** `C:\Program Files (x86)\Steam\steamapps\common\PalServer` has no `Mods\` and no `Pal\Saved\` yet. [LOCAL]
- **Not read:** [survivalservers.com](https://www.survivalservers.com/wiki/How_to_Mod_your_Palworld_Server_Guide) is behind a Cloudflare challenge and could not be fetched by any route. The configuration page contributed only `bAllowClientMod`. Its player list and IP settings are not needed, because the mod can detect net mode directly (next section).

#### What runs on the server

- **PalSchema works on Windows dedicated servers.** The author confirmed it in [PalSchema #59](https://github.com/Okaetsu/PalSchema/issues/59): "there are some inconsistencies with editing of certain assets, but it does work on servers". Server crashes and connection breakage were fixed in 0.6.0 ([#90](https://github.com/Okaetsu/PalSchema/issues/90), [#93](https://github.com/Okaetsu/PalSchema/issues/93)). PalSchema 0.6.7 is pinned to UE4SS `2281fa31`, which is the installed version. [COMMUNITY]
- **DataTables are not replicated, so both sides need the rows.** [INFERENCE]
  - The **server** needs the operating-table rows to validate and price operations, the passive rows for the markers and aliases, and the item rows so it can grant `LP_Implant_*`.
  - The **client** needs the rows to list the operations, render the implants and show the text.
  - A client without the mod sees blank items. This matches the existing Workshop text.
- **UE4SS Lua runs on PalServer.** An installed mod, GuildFeedBox, ships an `IsServer` Lua rule and gates on `HasAuthority`. [OFFICIAL] [LOCAL]
- **No widget classes are loaded on a dedicated server.** No `WBP_*` and no local player [INFERENCE]. `RegisterHook` on a UFunction that is not in memory fails ([UE4SS docs](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html)).

#### Net-mode detection: header-verified candidates

| Call | Location | Note |
| --- | --- | --- |
| `UKismetSystemLibrary::IsServer(WorldContext)` | `Engine.hpp:14936` | |
| `UKismetSystemLibrary::IsDedicatedServer(WorldContext)` | `Engine.hpp:14942` | |
| `UKismetSystemLibrary::IsStandalone(WorldContext)` | `Engine.hpp:14934` | |
| `UPalUtility::IsServer` | `Pal.hpp:37754` | |
| `UPalUtility::IsDedicatedServer` | `Pal.hpp:37822` | |
| `UPalUtility::IsClientDedicatedServer` | near `Pal.hpp:37825` | |
| `UPalUtility::IsMultiplayer` | `Pal.hpp:37780` | |
| `UPalUtility::GetNetMode` | `Pal.hpp:37990` | returns an **FString**; values unknown |
| `APalGameStateInGame.bIsDedicatedServer` | `Pal.hpp:11171` | replicated property; tells a client whether its host is dedicated |
| `UPalPlayerPlatformInfoObject.IsListenServerHost` | `Pal.hpp:31969` | |
| `AActor::HasAuthority` | `Engine.hpp:8008` | current use |
| `UPalUtility::IsExternalModEnabled()` | `Pal.hpp:37802` | local only; no use found |

`AActor::GetNetMode` is not a UFunction, so Lua cannot call it.

**The current authority probe has a defect.** `util.has_authority(find_first("PalPlayerCharacter"))` is nil while no player exists. That is the normal state at dedicated-server boot, so recovery and the map-load ledger flush silently defer until the next map load, which on a dedicated server means a restart. Use a world-context `IsServer` instead. [LOCAL]

#### Host-has-mod detection

There is no official mechanism and no published Palworld pattern [LOCAL] [COMMUNITY]. The signal has to come from the host's copy of the mod. The candidates, all untested:

1. **A server-to-client RPC carrying a sentinel, sent by the server's Lua and hooked by the client's Lua.** The leading candidate is `APalPlayerController::SendLog_ToClient(EPalLogPriority, EPalLocalizeTextCategory, FName TextId, FPalLogAdditionalData)` (`Pal.hpp:12890`) with a `TextId` such as `PASSIVE_LP_HANDSHAKE`. The server sends it when a player joins, using `AGameModeBase::K2_PostLogin` (`Engine.hpp:8489`) or `APalPlayerState::OnCompleteLoadWorldPartitionAndAdjustCharacter_InServer` (`Pal.hpp:13303`). Unknowns:
   - Does a client RPC called from server Lua route to the client?
   - Does the client's hook fire?
   - Does the sentinel show a log line?
2. **Inference from the response.** The client attempts an LP operation and watches whether the host acted. This detects too late: gold may already be spent, or a marker left on the Pal.
3. **Chat or server notice broadcast:** visible to everyone, rejected. **A field in a replicated options struct:** fragile, rejected.

Whatever the mechanism, the client defaults to "host unconfirmed", and the UI gate blocks LP operations until the host is confirmed. In standalone play or on the listen host, `IsServer` is true locally, so no handshake is needed. Lua cannot unload the client's PalSchema rows, so "disabling" on a client means **gating and messaging**, not removing the operations from the list.

#### Granting items

- **`UPalPlayerInventoryData::AddItem_ServerInternal(FName, int32, bool, float, bool)` (`Pal.hpp:31882`) is the server-authoritative grant, and it is what the mod already uses.** It runs only from the server-only hooks, and the item replicates to the owning client. The granting paradigm is **correct**; what needs work is around it: finding the player, timing, and concurrency. [LOCAL] [INFERENCE]
- **Do not use `RequestAddItem_ToServer` or `RequestAddItem_ForDebug`.** Both are client-to-server debug paths.
- **`NotifyOnNewObject` does not fit granting.** Grants are driven by events (a swap confirmed, a Pal consumed), not by objects being created ([hooking-functions](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/hooking-functions)).
- **`NotifySurgiResult_ToClient` is a dead end.** It belongs to the Pal "Doctor" feature (`RequestDoctorSurgi_ToServer`, `Pal.hpp:30135-30142`), not the Surgery Table.
- **`UPalMapObjectOperatingTableModel` exposes no reflected properties** (`Pal.hpp:28437`). The target Pal travels inside the `FPalNetArchive`, which Lua cannot read. The server therefore cannot ask the table model "which Pal is on you?", and the passive-list diff (`snapshot_all`) remains the server-side way to find the Pal.

### 2. Tools and paradigms

#### Dev loop

- **The wiki assumes you edit the installed mod folder in place** and press **Restart All Mods** in the UE4SS GUI, or use `EnableHotReloadSystem`/`EnableAutoReloadingLuaMods` ([lua-modding-tools](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/lua-modding-tools), [UE4SS-settings.ini](https://raw.githubusercontent.com/UE4SS-RE/RE-UE4SS/main/assets/UE4SS-settings.ini)). That conflicts with the rule that only the loader writes the game folders.
- **Installed state** [LOCAL]:
  - UE4SS v3.0.1 Beta `2281fa31`.
  - `GuiConsoleEnabled=1` and `GuiConsoleVisible=1`, so the GUI with Live View is already running (see `Screenshot (292).png`).
  - `EnableHotReloadSystem=0`, `bUseUObjectArrayCache=false`.
  - The ini documents `+ModsFolderPaths`.
  - `CXXHeaderDump\` and `UE4SS_ObjectDump.txt` exist. Lua types (`Mods\shared\types`) have never been generated.
- **Options, by cost to the rules:**
  1. **Console commands and keybinds (no rule cost).** Add `RegisterConsoleCommandHandler` probes to the mod, compiled in only when `debug` is on: print the net mode, dump a Pal's passives, flush the ledger, show the journal, run recovery. These turn most restart-and-read-the-log loops into typed commands, read in the GUI Console tab.
  2. **Live View (no rule cost).** It inspects live objects, edits properties and **calls UFunctions on a selected object without code** ([live-view](https://docs.ue4ss.com/dev/feature-overview/live-view.html)). That suits trying `RemovePassiveSkill`/`AddPassiveSkill`, reading `CachedPassiveSlotIndex`, and watching the conveyor's `ConvertProgressRate` before writing code. The wiki wants `bUseUObjectArrayCache=true`; try without it first.
  3. **A `+ModsFolderPaths` override of the Lua half (one hand edit of `UE4SS-settings.ini`).**
     - How: a dev folder holding `LootablePassives\Scripts`, junctioned to the repo, wins over the loader-installed copy ("the last one found will be loaded"). `EnableAutoReloadingLuaMods` then applies Lua edits without a relaunch. PalSchema JSON still needs stage and restart.
     - Gotcha: `util.lua:27`'s `UE4SS_ROOT` fallback would write the journal and ledger into the repo.
     - Hot reload breaks exchanges in flight and callbacks already queued, so use it for UI work only.
     - Needs a one-launch check that the override replaces the installed copy rather than running beside it.
     - The ini is loader-managed UE4SS territory: a UE4SS reinstall reverts it, which fails safe.
  4. **A differently named dev package: rejected.** Disabling the shipped copy would need `mods.txt` edits or Mod Management.
- **Local dedicated server for testing.**
  - Launch PalServer once so it creates its folders.
  - Set `WorkshopRootDir` in `PalServer\Mods\PalModSettings.ini` to the client's `...\workshop\content\1623730`, and add `ActiveModList` lines for UE4SSExperimentalPW, PalSchema and LootablePassives.
  - `stage.ps1` then feeds the server through the same item folder, and a version bump redeploys it on server restart. The game client connects to `127.0.0.1:8211`.
  - The server's log should be at `PalServer\Mods\NativeMods\UE4SS\UE4SS.log`; unverified.

#### UE4SS API usage: mismatches in the current code

The first two were checked against the docs during this research.

1. **A single callback on a `/Script/` path runs BEFORE the function** ([RegisterHook](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html): "If UFunction path starts with `/Script/`: Callback to execute before the UFunction is executed. Otherwise: Callback to execute after"). `hooks.register` passes one callback (`lp/hooks.lua:79`), so both conveyor hooks (`lp/conveyor.lua:335-336`) read the queue **before** each tick. The `STEP_MARGIN` projection in `conveyor.lua` exists to guess the outcome that a post-callback would simply read. **Fix:** let `hooks.register` take a post-callback.
2. **Blueprint hook callbacks run AFTER the function, per the same docs.** `main.lua:90-94` claims the opposite, and the code's model of the widget hooks rests on that claim. Verify in game.
3. **Hook ids are discarded and `UnregisterHook` is never called** (`main.lua:81`, `lp/hooks.lua:79`). Turning `conveyor_extraction` off leaves a per-frame hook installed for the session.
4. **Blueprint hooks are armed by polling 90 × 1 s on every map load** (`lp/hooks.lua:23-28`, `64-94`). The documented pattern is `NotifyOnNewObject` on the widget class, registering inside the callback ([NotifyOnNewObject](https://docs.ue4ss.com/dev/lua-api/global-functions/notifyonnewobject.html)). On a dedicated server the widget hooks should not be armed at all.
5. **`util.name_to_string` falls back to `tostring()`** (`lp/util.lua:130`). That produces the `FNameUserdata: 0x…` output the dev tips forbid. Return nil instead.
6. **`operation_result_code` parses the enum through `tostring`** (`lp/inventory.lua:144`). If userdata comes back, a successful grant reads as a failure.
7. **Settings do not change at runtime the way `settings.lua` claims.** `lp/config.lua` reads `package.loaded["settings"]`, which is cached by one `require`. Editing the file mid-game changes nothing. The getters only see in-process mutation of the table, which is exactly what a BMM `onChange` would provide.
8. **`util.unwrap` probes `.get` on every value** (`lp/util.lua:67-79`). The docs require `:get()` only on hook-callback arguments. Optional tidy-up.

**Where the repo is right and the wiki is not:** the wiki uses `ExecuteWithDelay`, `LoopAsync` and `ExecuteAsync` freely, including in its Blueprint example. Keep the game-thread-only rule. `ExecuteInGameThread` (no delay) exists and could replace `ExecuteInGameThreadWithDelay(0, …)` at `lp/ui.lua:641`.

#### NotifyOnNewObject

- It fires on construction of a class or a subclass. The callback gets the object, with no `:get()`, and returns `true` to unsubscribe. Properties are often not yet initialized at that point.
- **Two uses here:**
  - Arming the widget hooks (mismatch 4 above).
  - A registry of `PalIndividualCharacterParameter` objects, which could replace `snapshot_all`'s `FindAllOf` walk. That walk runs on every remote request and over every Pal loaded on a server. On a populated dedicated server its cost matters.

#### FModel and a read-only data verifier

- **FModel needs `GAME_UE5_1` and a current `.usmap`.** Generate the `.usmap` with UE4SS DumpUSMAP (Ctrl+Numpad6, bound in the installed Keybinds mod). Export with "Save Folder's Packages Properties (.json)" on `Pal/Content/Pal/DataTable` ([fmodel](https://pwmodding.wiki/docs/developers/useful-tools/fmodel), [datatables](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/datatables)).
- **A verifier, not a generator:** a dev-only script that reads the exported vanilla JSON and the repo JSON, and reports. Its checks:
  - The 54 vanilla routes exist.
  - The reprice file names only `Price`.
  - The 21 consumable gates match vanilla's `RequireItemId`s.
  - Every passive id referenced exists in vanilla.
  - No route row collides with a vanilla row.
  - The alias `_DESC` numbers are still current.

  This is the check most worth running after a game patch. CUE4Parse is a library, not a CLI, so the export step stays manual.

#### Terminology from paldeck.cc (game 1.0.3)

- **The building is the "Pal Surgery Table".**
- **Reusable implants** (`PalPassiveSkillChange_<x>`) are named "Implant: \<Passive>". They are Key Items.
- **Single-use implants** (`PalPassiveSkillChange_Consumable_*`) are named **"Disposable Implant: \<Name>"**. They are consumables, rarity 4, sort ids 6241-6265. The repo's 21 match paldeck's 21 legal-in-game disposables exactly. paldeck also lists unobtainable ones (Salvation, Rare, Legend, Witch, EternalFlame, Invader, Nushi).
- **Item names differ from passive names for three World Tree implants:**

  | Item name | Passive name |
  | --- | --- |
  | Double-Edged Holy Sword | Twin-Edged Holy Blade |
  | Demonic Grasp | Demon's Hand |
  | Hermit | Hermit Sage |

  Docs must not assume an item name equals its passive's name.
- **paldeck has no drop sources and no surgery recipe or price data.** It is an item and stat database only.

#### Blueprints with Lua

A LogicMods `.pak` with a `ModActor` can give Lua callable Blueprint functions ([blueprints-with-lua](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/blueprints-with-lua)). It costs the Modding Kit and a cooking pipeline. The wiki says nothing about replication, and a locally spawned ModActor is not an owned, replicated actor, so it gives **no client-server channel** [INFERENCE]. **Not worth it for 1.3.0.**

### 3. In-game settings UI

#### Better Mod Manager (BMM), v0.2.11 installed

Sources: [the Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3803996980), the installed `BetterModManager\Scripts\` folder, and the template at `Scripts\template\MyMod\`.

- **Two modes.**
  - **Supported:** the mod calls `register()`.
  - **Auto:** BMM scrapes `Scripts/config.txt`, `config.txt`, `Scripts/settings.ini`, `settings.ini`, `Scripts/config.lua`, `config.lua` or `Scripts/settings.lua`. **Lootable Passives is in Auto mode today, through `Scripts/settings.lua`.**
- **How Supported mode works.**
  - The mod does `loadfile("<mod>/../../BetterModManager/Scripts/modconfig.lua")`.
  - If BMM is absent this returns nil and the mod runs on its own config file. That makes BMM a soft dependency with no `Dependencies` entry.
  - `register{ id, name, description, folder, config, options, onChange }` returns `{ values, apply, set, stop }`.
  - `onChange(key, value)` runs on the game thread through a 250 ms poll that reuses one closure.
- **Option types:** `toggle`, `slider`, `select`/`dropdown`, `text`, `color`, `hotkey`, `header`, `note`, `preview`.
- **Values persist in `%LOCALAPPDATA%\Pal\Saved\Config\ModConfig.<id>.lua`.** Only non-default values are stored. Supported mode writes nothing inside the mod.
- **No length limit is enforced.** Descriptions wrap in a 260-unit column at 12 pt, and the row grows.
- **Pass `folder` explicitly when registering from `Scripts/lp/`.** Otherwise the folder button points at the wrong place.
- **There is no server awareness anywhere in BMM.** It is per machine, and useless on a dedicated server.
- **BMM's own log is clean** [LOCAL].
- **Unrelated: PalSchema logs two failed signature scans.** `CraftItemCount_ApplyDataMapReturn` and `...ApplyDataMap` are not found, and PalSchema says it "will be unable to clean up invalid items and worlds with invalid items will crash on load". That bears on the uninstall note in `CLAUDE.md`.

#### Problems with the current Auto mode

1. **Labels and descriptions are raw keys and source comments,** including `tools/stage.ps1`, `Info.json` and `stage:DebugMode`. That is dev-only text reaching players, and it fills the screen (see `Screenshot (292).png`).
2. **Auto mode rewrites the installed `settings.lua` inside the game folder** and re-applies overrides after every loader reinstall. That makes BMM a second writer to a loader-owned folder.
3. **Auto-mode changes need a restart.** That wastes the live getters.
4. **The Auto-mode checkbox can write `LootablePassives : 0` to `mods.txt`.** That disables only the Lua half, which is the trap `CLAUDE.md` warns about.

#### Proposed restructure

- **`Scripts/config.lua` becomes the player-facing data file.** It follows BMM's template convention and holds three scalars with one-line comments:

  ```lua
  return {
      debug = false, -- stage:DebugMode
      conveyor_extraction = true,
      surgery_ui_gate = true,
  }
  ```

  `stage.ps1` keys off the tag, not the filename, so it needs no change. It is also the only control on a dedicated server.
- **`debug_faults` moves out of the player file,** to `Scripts/lp/faults.lua` or similar. BMM cannot render it and players should not see it.
- **The internal accessor `lp/config.lua` is renamed,** to `lp/settings.lua` or `lp/options.lua`. It stays the only reader. It does the BMM registration **before** `main.lua`'s load-time `conveyor_on()` check, and `onChange` writes into the live table the getters already read.
- **Leave out `enabledKey`, which removes BMM's mod-list checkbox.** Disabling stays under Options → Mod Management.
- **`passive_items.lua` moves to `Scripts/lp/`.** `Scripts/` would then hold only `main.lua` and `config.lua`.
- **Stage with `-Force` after the move.** Update `README.md`, the Workshop text and `CLAUDE.md`.

#### Draft UI text (character counts measured)

| Key | Label | Description |
| --- | --- | --- |
| `conveyor_extraction` | Conveyor extraction (19) | Pals fed to the Disassembly Conveyor also yield implants of their passives. Host only. (≈85) |
| `surgery_ui_gate` | Surgery button check (20) | Blocks the Edit button when the operation cannot work. Turn off if the Surgery screen misbehaves. (97) |
| `debug` | Debug logging (13) | Adds DEBUG trace lines to UE4SS.log. Leave off unless reporting a bug. (70) |

Section headers: "Extraction" and "Troubleshooting". Keep descriptions at or under about 110 characters.

#### Which settings can change at runtime, and who decides

| Setting | Changes at runtime? | Whose value counts |
| --- | --- | --- |
| `debug` | Yes, from the next log line. | Per machine. |
| `surgery_ui_gate` | Yes, from the next `Update Button State`. | Per machine; it is client UI. |
| `conveyor_extraction` → off | Yes, but Pals already tracked are forgotten and not paid for. | The host or server. On a client it is inert because of `has_authority`. |
| `conveyor_extraction` → on | Only partly: the hooks register at the next map load. Calling `conveyor.install()` from `onChange` is untested. | The host or server. |

No settings replication is needed. A dedicated server's settings come from its own `config.lua`.

#### Darn Menu

- **Not installed.**
- **It registers through a schema file in the shared `Mods\NativeMods\UE4SS\Mods\shared\` folder, plus a line appended to a shared index file that other mods also write.** The loader cannot install a shared file, so the mod would have to write the game folder at runtime, which the rules forbid.
- **BMM already reads Darn Menu schemas; the reverse does not hold.** So BMM support covers BMM users and costs Darn Menu users nothing extra to lose.
- **Recommendation: BMM only for 1.3.0.**

### Current architecture: facts that matter for 1.3.0

All verified against the code.

- **The mutations are already server-side.**
  - `RequestRequestChangePassiveSkill_ServerInternal` (H1) and the two conveyor `_ServerInternal` hooks fire only where the world is authoritative.
  - `AddItem_ServerInternal`, `RemovePassiveSkill` and `AddPassiveSkill` run only from those hooks.
  - `IsLocallyControlled` returns nil on a dedicated server, so every request takes the `snapshot_all` path, which is the right one there.
- **The widget hooks would be dead weight on a dedicated server.**
  - The four widget hooks (H2-H5) and the client-request hook (H6) would retry 90 times per map load and warn once a player joins.
  - `hooks.announce_if_complete` would never print.
- **Server logic is coupled to the widget module.** `transaction.lua` requires `ui.lua` for the listen host's own-click capture (`current_page`, `selected_parameter`). Harmless on a server, but it blocks a clean split.
- **Concurrency.**
  - `main.lua:74`'s single `pending_record` loses the first of two requests that land between H1's pre and post callbacks.
  - The journal holds one row globally, so two players' exchanges overwrite each other.
  - `settle_before_exchange` can replay another player's exchange in the middle of it.
  - `resolve_record` refuses an exchange when two Pals change at once.

  On a busy server each of these can strand a marker, or take the passive with no implant given. That matches the Awfulhorrid report.
- **The journal carries no owner.** Recovery finds "its" Pal as the only Pal in the world carrying the marker.
- **The ledger is keyed by player UID.**
  - Conveyor rows use the consumed Pal's `OwnerPlayerUId`, which may be an offline guild member.
  - Delivery is retried on map load (12 × 5 s) and after each conveyor consumption. **Nothing retries when a player joins.**
  - On a dedicated server a held debt therefore waits until another Pal is consumed or the server restarts.

---

## Plan for 1.3.0

This is a draft for iteration and is not approved.

**Scope, from round 5:** everything found in research and testing ships in 1.3.0, and nothing is deferred to a 2.0.

- Only one change is new to players: **official Better Mod Manager support** (runtime settings, and a host-only cleanup action).
- Everything else is polish. It makes extraction and implantation work, and gate, correctly in situations the mod already claims to cover: co-op from both the host's and the client's side, dedicated servers, and several players at once.
- A player without BMM sees no difference in the core gameplay.

The sections are in the proposed execution order. Each is meant to be stageable and testable by itself.

### Session handoff (updated 2026-10-19, acceptance complete, before the release)

Read this first when resuming.

- **Where things stand.**
  - **Acceptance is complete.** The dedicated-server list and the self-hosted list passed; the two-player tests are skipped for 1.3.0 (developer, 2026-10-19), who will test two players informally after the release.
  - **Next: the developer's separate code-quality analysis, then 1.3-K together,** including checking that a release install comes up with `debug = false` despite BMM's file-mode store (see `.docs/better-mod-manager-file-mode-report.md`).
  - **Not yet run in game:** the DEBUG line for a direct-route implant (added after the last stage, 1.2.14). The next stage carries it; check it during 1.3-K's stage or a last dev stage.
  - **Code:** 1.3-A to 1.3-I are coded (see each status section), with every offline check passing.
  - **Acceptance session 1 is done** (its results sections, under 1.3-H): 1.3-G's handshake, hiding and on-screen notice, and 1.3-H's cleanup all pass on the dedicated server, after two crash fixes (1.2.6, 1.2.7) and the host notices (1.2.8).
  - **Acceptance session 2 is done** (dev 1.2.9 to 1.2.11): conveyor queue, delivery on join, snapshot timing, the server backstop and recovery at boot pass. It added the client grant reports.
  - **No planned code is left.** What remains is the acceptance listed under "Remaining work" below, any fixes it finds, the docs cleanup, and the release (1.3-K). 1.3-J is not started and not needed.
- **Decided (round 10):**
  - Runtime testing is acceptance testing, run once the code is complete.
  - 1.3-B step 4 is dropped.
  - The "tested on a dedicated server" wording waited for general testing; it was written once the dedicated-server acceptance finished (2026-10-19, developer's call), with the uninstall steps.
- **Repo state:** the last commit is `65d31ee`, the 1.3 code through acceptance session 1. Session 2's changes (the grant reports, the snapshot timing line, the docs and this plan) are uncommitted. `Info.json` and `Scripts/config.lua` are at a dev version with `DebugMode`/`debug` true; the release stage resets them.
- **The last staged build is dev 1.2.14,** with `faults.lua` empty. The server's installed `config.lua` was left at `debug = false` and the client's BMM has `debug = false` saved; a server restart restores the server's `true`, and the client's needs BMM. The next stage needs no `-Force` unless a file is deleted.
- **The dev rig.**
  - `PalServer\Mods\PalModSettings.ini` points `WorkshopRootDir` at the client's Workshop content folder, with the three `ActiveModList` lines, so `stage.ps1` feeds both machines.
  - The server runs the developer's world `9F2509B44E9A564ACFF601A9DB9A81EC`, with the host's UID swapped to `EFC7480B…`. **That world is now a test world** (developer, 2026-10-18): it was kept after the cleanup rather than restored. The developer plays on their self-hosted world.
  - **Backups** in `C:\Users\greg_\PalworldBackups\`: `2026-10-18-pre-server-move`, `2026-10-18-server-pre-uid-swap`, and `2026-10-18-server-pre-cleanup-test` (the server world before any cleanup, 622 LP implants in place), each with a `MANIFEST.md5`.
  - **Changing a server setting while it runs:** edit `PalServer\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\config.lua`. A debug build applies the edit within 5 s (`options.watch_file`), and a restart resets the file to the staged one.
  - The client's `UE4SS-settings.ini` has `bUseUObjectArrayCache = false`.
- **Logs** in `.docs\` (gitignored): the probe logs `probe-*.log`, acceptance session 1's `accept1-*.log`, crash reports included, and session 2's `accept2-*.log`.
- **The probe code is deleted.** The approach is in `README.md`, "Probing the game with debug keys"; the calls it proved are below.

#### Remaining work

**Code:** none planned. Fixes only as acceptance finds them.

**Acceptance on the dedicated server** (the rig is ready; one player is enough):

Done in session 2 (see "Acceptance session 2" under 1.3-H): conveyor timing, delivery on join, the `snapshot_all` measurement, the server backstop for all three route kinds, recovery at boot, release logging, the setting-change relay, and the grant reports for the conveyor, Extract One, Extract All and debug off. Also done:

- **1.3-G navigation** (developer): keyboard and controller navigation over the collapsed list both work.
- **The owed-delivery client line: dropped** (developer): overtaken by events. The grant reports were seen working throughout session 2, and the owed kind shares their sending path.

Also done in session 2: the 1.3-G unconfirmed path, and the uninstall procedure (cleanup first). **The dedicated-server acceptance list is complete.** To put the rig back: restore `ActiveModList=LootablePassives` in the server's `PalModSettings.ini`, restore the world from the backup if wanted, and restart.

**Acceptance on the self-hosted world** (single player or listen host):

1. **1.3-F with Better Mod Manager: done (2026-10-19, co-op host, dev 1.2.14),** with one finding.
   - The page shows Debug logging ON in the dev build; toggles of debug, Conveyor extraction and Surgery extraction applied at once with a `DEBUG: Setting … is now …` line each; the installed `config.lua` kept its comments and the `stage:DebugMode` tag; `ModConfig.LootablePassives.lua` returned to `return {}` once every value was back at its default.
   - **Finding: BMM's file mode still co-manages `config.lua`.** At every start, `filemods.repair` runs over every Lua mod listed in `mods.txt` (`findExternalMods` in BMM's `menu.lua`), registered or not. `locate` finds `Scripts/config.lua` (BMM's `LUA_FILES` also lists `config.lua` and `Scripts/settings.lua`), and `reconcile` compares it with BMM's store `ModConfig.file.LootablePassives.lua` and may rewrite it through `writeAtomic`, which leaves `config.lua.bak` beside it. At the 01:24 launch it wrote `debug = true` back over the registered page's saved `false`. It does not write `mods.txt` for this mod.
   - **Effect:** for players its store holds release values only, and on an update it restores the player's earlier values, as the registered page does. On a machine that ran dev builds, the store holds `debug = "true"` and restores it into a release's `config.lua` on the update. BMM's only opt-out in code is a `Scripts/shared.hash` marker file, undocumented; not used. Worth reporting to BMM's author: file mode should skip a mod that registered through `modconfig.lua`.
   - **Cleaned on the dev machine:** `ModConfig.file.LootablePassives.lua` (and `.bak`), `BetterModManager.profile.LootablePassives.lua` (built from the old `settings.lua`), and the installed `Scripts\config.lua.bak` and `Scripts\settings.lua.bak`, which are outside the loader's manifest. BMM recreates its store at the next start with that build's values; at the release stage, check a release install comes up with `debug = false`.
2. **`surgery_extraction` off locally: done (2026-10-19, co-op host `9F2509B4…`, dev 1.2.14).**
   - Off in BMM: the host logged "Surgery extraction is off in this mod's settings, so its Surgery operations are hidden." and the list hid them. Back on: two Extract Ones, an Extract All, and four implants on the emptied Pal (a vanilla consumable, a recipe, the direct route `Deffence_up2`, the alias `Stamina_Up_2`) all worked, with normal gold.
   - **The backstop with the gate off is not reachable on a host:** opening the menu to reach BMM drops the Surgery screen's selection, so no click can follow the setting change. Passed on the strength of the dedicated-server run in session 2, which covered all three route kinds (developer's call).
   - **Observability gap, open:** a direct-route implant on the host's own game logs nothing; `on_local_request` treats it as a vanilla passive id. Only marker and alias exchanges log a `Surgery … finished` line.
3. **The cleanup through BMM on a listen host, as the Workshop text's "Single player, or hosting co-op from your game" uninstall procedure: pass (2026-10-19, `9F2509B4…`, dev 1.2.14).**
   - Backed up first to `PalworldBackups\2026-10-19-local-pre-uninstall-test\` (67 files, `MANIFEST.md5`), and restored from it afterwards, verified 67 of 67.
   - Turned on in BMM: found 631 implants (14 in inventories, 617 in chests, 0 in guild chests; 80 stacks) in 5,185 loaded containers, removed all in 29 s, cleared `remove_mod_items` itself, showed the message. The game autosaved 78 s later.
   - Disabled under **Options → Mod Management**, restarted, entered the world: loaded normally, inventory held only vanilla implants, vanilla operations at vanilla prices (consumables free, the table's recipes 10,000, the arena and bounty recipes 50,000), and a conveyor run gave no implants. BMM listed the mod as inactive.
   - **What the client's disable leaves:** the loader deleted the data half (an empty `translations` folder remains, and PalSchema printed `Loading mod: LootablePassives` with no rows) and set `LootablePassives : 0` in `mods.txt`, but kept the Lua files and the `ManagedMods` record.
   - **BMM's file mode wrote the disabled mod's `config.lua`** (`surgery_ui_gate` false to true, with a new `.bak`) and recreated its store; with the mod not running, BMM treats it as a plain file mod. Harmless while the mod is off.
   - Not covered: an implant in a guild chest (none was there), and a ledger debt (needs a fault; the server run covered the ledger).

**Needs a second player: skipped for 1.3.0** (developer, 2026-10-19). The client-server relationship was tested extensively on the dedicated server; the developer will test two players informally after the release.

1. **1.3-C step 7:** two Extract Ones at the same moment on different Pals, and an Extract All during another player's conveyor run.
2. **The test matrix's listen-host rows,** including a client without the mod.

**Done after the acceptance (2026-10-19, not yet staged):**

- **Direct-route implants are logged under debug** (developer's request, closing the gap found in self-hosted test 2). `finalize_extraction`'s vanilla branch asks `direct_route_change` and, when one Pal gained a direct-route passive, logs `Implanted <passive> through its direct route for player <id> (<source>); the game spent its module.` instead of the "not one of our operations" line; this covers a dedicated server and a host's own click. On the clicking game, `begin_local_exchange` logs `Requested the direct-route implant <passive> on slot <n>; the game completes it, so the panel is not tracked.`
- **`.docs/better-mod-manager-file-mode-report.md`:** a detailed report of BMM's file mode co-managing `config.lua`, for its author, to be linked from a private message if he follows up on the developer's general post.
- **1.3-K's checks so far:** `faults.lua` is `return {}`; `README.md` and `CLAUDE.md` re-read (three stale `settings.lua` references, the probe how-to's `main.lua` line, and the host test's description fixed); `luacheck.js`, `luacheck Scripts` (0/0), the five Lua tests and `test_staging.ps1` all pass.

**Then 1.3-K,** after the developer's code-quality analysis: rerun the checks if code changed, confirm `Scripts/lp/faults.lua` is `return {}` (it ships), the `-Minor` stage, a release install checked for `debug = false` on the developer's machine (BMM's file-mode store may restore `true`), and the commit, by the developer's call.

**Docs written from session 2 (2026-10-19):** the Workshop text's Multiplayer section now states what was tested on a dedicated server, replacing "reported NOT TO WORK ON DEDICATED SERVER HOSTING"; its Uninstalling section has two procedures, both starting with the item removal (dedicated server through `config.lua` and `ActiveModList`, tested; single player or co-op host through Better Mod Manager or `config.lua`, not yet tested); the Known Issues have the price mismatch on an unmodded host; the changelog says so. `README.md` has the loader's `ActiveModList` behaviour and the join crash; `CLAUDE.md`'s uninstall note has the crash.

#### Engine calls proven by the probes (use these in 1.3-A to 1.3-H)

Each was run in game on 2026-10-18, game v1.0.5.102999, UE4SS `2281fa31`.

- **Static library calls through the class default object,** with a world context:

  ```lua
  local function _call_one(object, name, argument) return object[name](object, argument) end
  local utility = StaticFindObject("/Script/Pal.Default__PalUtility")   -- validate with IsValid
  local context = FindFirstOf("PalGameStateInGame")                     -- nil at the title screen
  local ok, is_dedicated = pcall(_call_one, utility, "IsDedicatedServer", context)
  ```

  - `IsServer`, `IsDedicatedServer`, `IsClientDedicatedServer`, `IsMultiplayer` and `GetNetMode` all answer.
  - `GetNetMode` returns an FString; read it with `:ToString()`. The values are `Standalone`, `ListenServer`, `DedicatedServer` and `Client`.
  - `/Script/Engine.Default__KismetSystemLibrary` gives the same answers.
  - The `GameInstance` (`FindFirstOf("PalGameInstance")`) also works as a context and exists at the title screen. There it reads `Standalone`, so don't decide a role there.
  - `PalGameStateInGame.bIsDedicatedServer` is a readable, replicated bool.
- **The server-to-client handshake:** `pcall(_call_one, controller, "Debug_ReceiveCheatCommand_ToClient", text)` on an `APalPlayerController`, with a plain Lua string for the FString.
  - **To receive it,** the client registers `RegisterHook("/Script/Pal.PalPlayerController:Debug_ReceiveCheatCommand_ToClient", fn)` at load. The text arrives as the second callback argument; unwrap it, then `:ToString()`.
  - **It is invisible to the player.**
  - **It arrived about 2.6 s after the send,** which was itself 3 s after the join trigger.
- **The join trigger is `RegisterHook("/Script/Pal.PalPlayerState:OnCompleteLoadWorldPartitionAndAdjustCharacter_InServer", fn)`.** Its context is the joining `BP_PalPlayerState_C`, whose `PlayerUId` field reads with `util.guid_key`. It fires **twice** per join and must be debounced. It does not fire for a listen host's own entry.
- **Hiding a Surgery list entry:** `pcall(_call_one, entry, "SetVisibility", 1)`, where `ESlateVisibility.Collapsed` is 1 and `Visible` is 0 (`UMG_enums.hpp:48`).
  - **What an entry is:** a `WBP_OperatingTable_ItemList_C` whose `GetParent()` is the list's `ScrollBox`.
  - **What to read from it:** its `PassiveId` and `ConsumeItemId` NameProperties, through `util.name_to_string(util.field(entry, "PassiveId"))`.
- **Reading item containers:** a `PalItemContainer`'s `ItemSlotArray` → each `UPalItemSlot`'s `ItemId.StaticId` (FName) and `StackCount`. Also `bIsGuildChestContainer` and `OwnerMapObjectInstanceId`. Walking all of them in one frame blocks for 2.5-3.2 s, so slice it.
- **Writing the installed `Scripts\` folder works on both machines** (`util.is_writable` on a temporary file there).
- **Key binds work on the client:** `RegisterKeyBind(Key.F12, { ModifierKey.CONTROL }, fn)`, with `fn` a `util.coalescer` built at load.

### Decisions, rounds 4 to 9 (2026-10-18)

1. **Conveyor: keep the pre-callbacks and remove the projection** (round 8, replacing round 4's post-callbacks). The probe showed that post-callbacks see only the removal (1.3-B step 2).
2. **Layout:** `lp/config.lua` becomes `lp/options.lua`, and `passive_items.lua` moves to `lp/`.
3. **Nothing is deferred.** The handshake, concurrency, the module split and ledger delivery are all 1.3.0 work.
4. **What `surgery_extraction` covers.** "Off" stops every Surgery operation this mod adds (round 6):
   - Extract One and Extract All;
   - the 54 `LP_Insert_*` alias implants;
   - the 61 direct routes in `LootablePassivesOperatingTable.json`, which spend an `LP_Implant_*`.

   Vanilla's own 54 rows (recipes and vanilla disposable implants) are untouched.
5. **Nothing already created is removed implicitly.** Pals keep the passives they have. Modules stay in the world until someone runs the cleanup (1.3-H).
6. **The cleanup action is two settings** (round 6). It runs wherever the world is authoritative, a dedicated server included, through `config.lua`.
   - **"Enable experimental features (like mod item removal)"** is the arm switch.
   - **"Remove ALL items created by this mod from the game world?"** is the request. It depends on the first, and only the mod clears it, and only on success.
7. **Handshake first, no fallback planned** (round 6). The handshake has to be solved before any fallback is considered. If it works, it delivers what the client needs to block before the gold charge, so nothing past it is planned. If the 1.3-0 probe finds no route, stop and replan with the developer.
8. **The mod saves runtime setting changes into its installed `config.lua`** (round 7). The "only the loader writes the game folders" rule is this repo's, and it governs deployment, not the mod's own config and runtime files; `CLAUDE.md` was updated to say so. A reinstall, which every version update causes, resets settings to the shipped defaults. That is accepted, and documented for players as known behaviour.
9. **Probing approach kept, probe code deleted** (round 9). The debug-key probe approach is documented in `README.md`, "Probing the game with debug keys", and in `CLAUDE.md`. `Scripts/lp/probe.lua` was deleted.
10. **Round 10 (2026-10-18):** runtime testing is acceptance testing, run once the code is complete; 1.3-B step 4 (`NotifyOnNewObject`) is dropped; the "tested on a dedicated server" wording is a docs-cleanup step after general testing (1.3-K step 1); 1.3-G and 1.3-H are tested first, on the dedicated-server rig.

### 1.3-0. Test rig and probes

#### Local dedicated server rig (done 2026-10-18)

- **Server setup.**
  - The server was launched once. That created `PalServer\Mods\PalModSettings.ini`, with `bGlobalEnableMod=False` and an empty `WorkshopRootDir`, and an empty `Pal\Saved\Config\WindowsServer\PalWorldSettings.ini`, so the defaults apply, including `bAllowClientMod=True`.
  - The ini was then set to `bGlobalEnableMod=True` and `WorkshopRootDir=C:\Program Files (x86)\Steam\steamapps\workshop\content\1623730`, with `ActiveModList` lines for `UE4SSExperimentalPW`, `PalSchema` and `LootablePassives`. It shares the client's Workshop folder, so `stage.ps1` feeds both.
- **Install results, game v1.0.5.102999, mod 1.2.0.**
  - **Only the listed mods install.** `PalServer\Mods\ManagedMods\` holds exactly `UE4SSExperimentalPW`, `PalSchema` and `LootablePassives`. GuildFeedBox, which has an `IsServer` rule and sits in the same folder, was **not** installed. `ActiveModList` is the filter.
  - **The loader writes `mods.txt` on the server too:** `LootablePassives : 1` and `PalSchema : 1`. The layout is the same as the client's.
  - **The server log is `PalServer\Mods\NativeMods\UE4SS\UE4SS.log`.** UE4SS on the server has the GUI console off.
  - **Both halves load,** with the same counts lines as the client.
  - **Native hooks register at once:** H1, H6 and both conveyor hooks. The widget hooks H2-H5 sit in the retry loop.
- **The developer's co-op world is on the server.**
  - **Backups:**
    - `C:\Users\greg_\PalworldBackups\2026-10-18-pre-server-move\`, taken before the move;
    - `...\2026-10-18-server-pre-uid-swap\`, taken after the first join and before the UID swap.

    Each has a `MANIFEST.md5`.
  - **The move:** the world was copied to `PalServer\Pal\Saved\SaveGames\0\9F2509B44E9A564ACFF601A9DB9A81EC\`, without `WorldOption.sav`, and `DedicatedServerName` was set to match.
  - **The first join** made `Players\EFC7480B000000000000000000000000.sav` (`steam_76561198007709498`).
  - **The UID swap:** Palworld Save Pal v1.4.3 swapped `…0001` into that player. Level, inventory, guild and base all came through intact.
- **Functional run on 1.2.0 release:** Extract One, Extract All (including Lord of the Sea), a direct-route implant and a conveyor consumption all worked. No ledger or journal file was left. **Kamigouki's report was a server-setup problem.** Details:

  | Operation | Server log | Client log | Result |
  | --- | --- | --- | --- |
  | Extract One | `Extracted ElementBoost_Earth_1_PAL … for player 256 (server snapshot)` | request, accepted, marker seen, finished, panel repaired, Edit released | ✔ |
  | Extract All | `Extracted 2 passive(s) … (server snapshot): ElementBoost_Aqua_1_PAL plus 1 more` | the same sequence | ✔ |
  | Implant `ElementResist_Thunder_1_PAL` (direct route) | `A passive list changed with no marker … nothing was changed` | `OnPassiveUpdate` only | ✔ |
  | Conveyor | `Disassembly yielded 1 module(s): ElementResist_Thunder_1_PAL` | none | ✔. The debt was delivered at once to the swapped owner. |

- **Irregularities seen:**
  - The widget hooks warn on the server ("… not installed yet. Expected before a world is loaded …"); handled in 1.3-A.
  - Release builds log Surgery panel internals; handled in 1.3-I.
  - The stale "hidden cards" names; handled in 1.3-I.
  - `[PS] Failed to find ConsoleManagerSingleton` comes from UE4SS or PalSchema and is not ours.

#### Probes before the code that depends on them

**Built 2026-10-18 as `Scripts/lp/probe.lua`, and deleted once its answers were recorded.** `main.lua` loads it only when `debug` is true. Every line it writes is prefixed `PROBE`. It was first staged as dev build 1.2.1.

- **What it does at load:**
  - logs whether the mod's `Scripts\` folder is writable;
  - registers pre and post hooks on both conveyor hooks, on the two join candidates, and on the two handshake RPCs;
  - registers a Blueprint-timing hook on `WBP_OperatingTable_C:On Select Passive Change`.
- **When it reports net mode:** 5 s after each map load, and 3 s after each join. A join also sends the handshake text and runs a container scan.
- **Keys, on the client:** Ctrl+F9 reports net mode, Ctrl+F10 scans containers, Ctrl+F11 sends the handshake (only where this machine is the server).
- **Handshake carriers tried:** `APalPlayerController::Debug_ReceiveCheatCommand_ToClient(FString)` and `UPalNetworkMapObjectComponent::Dev_ReceiveDismantleMapObjectResult_ToClient(FString)`. Both are client RPCs with a free-text payload, so no struct needs building, unlike `SendLog_ToClient`. Whether either shows anything on screen is part of the probe.
- **Not yet built:** the debug console commands from the list below. The in-game console is off (`ConsoleEnablerMod : 0`), so keybinds replaced them for now.
- **Found while staging:** `tools/stage.ps1`'s closing message still says `.docs\workshop-description.txt`. Fix it with 1.3-I.

**Run order:**

1. **Single player:** load the world, wait 10 s, open the Surgery Table, and click two different passives in the list. Run a conveyor with one Pal, then a queue of three. Press Ctrl+F9 and Ctrl+F10.
2. **Dedicated server:** start PalServer, join, wait 10 s, then run one conveyor Pal and press Ctrl+F9 and Ctrl+F10 on the client. Note anything shown on screen when joining.
3. **Collect** both `UE4SS.log` files before restarting anything.

#### Probe results: single player and self-hosted, dev build 1.2.1 (2026-10-18)

The log is copied to `C:\Users\greg_\PalworldBackups\probe-logs\client-singleplayer-1.2.1.log`.

- **Net mode: answered, and both world contexts work.** The GameState and the GameInstance gave the same answers:

  | Where | PalUtility | Kismet | `bIsDedicatedServer` |
  | --- | --- | --- | --- |
  | Title screen | `IsServer=true IsMultiplayer=false GetNetMode=Standalone` | `IsStandalone=true` | no `PalGameStateInGame` yet |
  | The developer's world (multiplayer-enabled, playing alone) | `IsServer=true IsDedicatedServer=false IsMultiplayer=true GetNetMode=ListenServer` | `IsServer=true IsStandalone=false` | `false` |

  - **The title screen reads as a server.** So `role.lua` must not decide anything before a `PalGameStateInGame` exists, and must re-evaluate on each map load.
  - **A world opened for multiplayer is a listen server even with nobody else in it,** so "single player" and "listen host" are the same role for the mod.
  - **`GetNetMode` returns the plain strings `Standalone` and `ListenServer`.** `DedicatedServer` and `Client` are still to be seen.
- **Blueprint hook timing: the callback runs after the function body,** as the UE4SS docs say. Evidence: selecting `PAL_ALLAttack_up3` after `PAL_ALLAttack_up1` logged the argument `ConsumeItemId=PalPassiveSkillChange_Consumable_PAL_ALLAttack_up3`, with the screen's `CachedConsumeItemId` already equal to it. The next selection back to `None` showed `None` in both. The `main.lua:90-94` comment is wrong and gets corrected in 1.3-B.
- **Conveyor timing: post-callbacks are not the fix. Removing the projection is.** One Pal, then a queue of four, gave five consumptions, all detected correctly.
  - **In every firing of `OnProceedConvertProcess`, the pre and post callbacks see the same rates.** That hook's body does not advance the rate in a way the callbacks can see.
  - **The completing rate is visible in the `OnUpdateCharacterContainer` pre-callback,** at 1.0016, 1.0027, 1.0027, 1.0001 and 1.0028, with the Pal still in the queue. The removal then happens inside that function's body, which also calls `OnProceedConvertProcess` while it runs. The existing pre-callback sees the Pal gone in that inner call, and decides "consumed" from the ≥ 1.0 rate it stored a moment earlier.
  - **A post-callback would see only the removal,** and would have to guess the rate from the last proceed firing (≤ 0.9993). That is the guess the projection exists for.
  - **Approved for 1.3-B (round 8):** keep the pre-callbacks, and remove the `STEP_MARGIN` projection, since the container pre-callback always carries the ≥ 1.0 rate. Keep a fallback log line for any Pal that leaves below 0.999 after having passed 0.97, so a missed completion shows in the log instead of being silently treated as a withdrawal.
- **Container reach: the scan works, but it is too slow for one frame.**
  - **The first scan found 5359 `PalItemContainer` objects, the second 5312.** Containers stream in and out with world partition, so a container far away may not be loaded.
  - **A full scan blocked the game thread for about 3.2 s.** The cleanup in 1.3-H must therefore walk the containers in slices across frames.
  - **LP items were in 4 containers:** two with no owner map object, holding 8 and 11 (probably the player's inventory containers), and two chests holding 312 and 291. That makes 622 items in 83 stacks. One guild chest exists; it held no LP items.
  - **For 1.3-H:** `UPalItemContainerManager.ItemContainerMap_InServer` (Pal.hpp) may be the complete list on the server. Probe it on the dedicated server before relying on `FindAllOf`.
- **Join triggers: neither fired for the host's own entry into the world.** That is expected if both are about *remote* players joining; the dedicated-server run decides it. The handshake was not sent (Ctrl+F11 was not pressed, and on a listen host it would reach only the host itself).
- **An Extract All "failure" reported by the developer was not confirmed.** The developer ran an Extract All straight after two Extract Ones, without closing the Surgery screen in between, and saw neither modules arrive nor passives leave the Pal.
  - **The log shows that exchange succeeding.** At 20:28:45 it extracted all three passives and left the Pal with `[]`.
  - **What the panel did.** It still drew the old passives plus the marker when the exchange finished. The mod's refresh re-bound the detail, logging `[]`, and the panel was closed about 1.5 s later.
  - **Three later Extract Alls (20:37-20:38) also succeeded.**
  - **Counted as unverified.** If it recurs, check the Pal in the Palbox and the inventory before closing the table, and keep the log. If it is a display problem, it belongs with the "Edit button coloring" known issue and 1.3-E's panel work.
- **Write access: the client's installed `Scripts\` folder is writable** (`...\Palworld\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\`). The server is still to be checked.

#### Probe results: dedicated server and its client, dev build 1.2.1 (2026-10-18)

The logs are `.docs/probe-server-dedicated-1.2.1.log` and `.docs/probe-client-dedicated-1.2.1.log`. Both are gitignored through `*.log`.

- **Net mode: all four roles are now identified.**

  | Machine | PalUtility | Kismet | `bIsDedicatedServer` |
  | --- | --- | --- | --- |
  | Dedicated server, at boot (no players) and after a join | `IsServer=true IsDedicatedServer=true IsMultiplayer=true GetNetMode=DedicatedServer` | `IsServer=true IsDedicatedServer=true` | `true` |
  | Client of the dedicated server | `IsServer=false IsClientDedicatedServer=true IsMultiplayer=true GetNetMode=Client` | `IsServer=false` | `true` |

  - **The GameState context is available at dedicated-server boot,** 8 s after load and before anyone joins. `role.lua` can therefore decide at boot.
  - **A client can tell whether its host is dedicated** (`IsClientDedicatedServer`, `bIsDedicatedServer`).
- **The join trigger is `APalPlayerState::OnCompleteLoadWorldPartitionAndAdjustCharacter_InServer`.** It fired on the server for the joining player, **twice** about 0.17 s apart, on the same PlayerState. Its `PlayerUId` read as `-272152565-0-0-0`, which is `EFC7480B…` as signed int32, the swapped player. Debounce it per PlayerUId.
  - `AGameModeBase::K2_PostLogin` did **not** fire. Drop it.
- **The handshake works, and the player sees nothing.**
  - **Both routes delivered.** The server called `Debug_ReceiveCheatCommand_ToClient` on the one `PalPlayerController`. The client's hook logged `handshake RECEIVED via cheat RPC on BP_PalPlayerController_C …: LP_HANDSHAKE_PROBE surgery=1 conveyor=1 via=cheat n=1`, 2.6 s after the send.
  - **The dismantle route also arrived,** on component 2, while component 1 ran locally on the server.
  - **Nothing appeared on the client's screen** (developer's observation).
  - **Choice for 1.3-G: `APalPlayerController::Debug_ReceiveCheatCommand_ToClient(FString)`.** There is one controller per player, so it targets that player exactly, it carries free text for the host's settings, and it is invisible.
  - **Sending:** debounce the join trigger, wait about 3 s, then call it on that player's controller, found through the PlayerState's owner or by matching `PlayerUId`. Re-send to every controller when the host changes a setting at runtime.
- **Container reach on the server: offline players' inventories appear to be loaded.**
  - **The server holds about 4,700-4,800 `PalItemContainer` objects; the client holds 380.** A full scan took 2.5 s on the server.
  - **The joined player's inventory is identified.** The server's container with no owner map object went from 4 to 7 LP items across a conveyor run that yielded 3. The client sees the same container as `BP_PalPlayerState_C…PalItemContainer_…` holding 7.
  - **A second container with no owner map object holds 11 LP items** on the server, in this session and the single-player one. It is not replicated to the joined client. **Most likely it is the offline co-op friend's inventory** (`7A1DBAC5…`), which would mean offline inventories are loaded on the authoritative machine. Confirm in 1.3-H by reading the container's `BelongInfo`, or the owning player state, before relying on it.
  - **Both chests (312 and 290) match the single-player numbers.** The server sees 2 guild chests.
- **Write access: the server's installed `Scripts\` folder is writable** (`C:\Program Files (x86)\Steam\steamapps\common\PalServer\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\`). The `config.lua` write-back in 1.3-F works on both machines.
- **Conveyor on the server:** one Pal was consumed at rate 1.0007 and yielded 3 modules, delivered to the joined player. The same pattern as single player.
- **Item messages are server-side on a dedicated server.** The client's UE4SS console shows none of the "Extracted…" or "Disassembly yielded…" lines, because those run on the server; read the server log for them. This matters for 1.3-E: the client should log a short outcome line of its own, so a player on a dedicated server has something in their log to report.
- **The widget hooks' "not installed yet" warnings appeared on the server again** (five lines, including the probe's own). Fixed by 1.3-A.

#### Probe result: hiding Surgery list entries, dev build 1.2.2 (2026-10-18)

The log is `.docs/probe-client-list-1.2.2.log`. The screenshots are `.docs/Screenshot (301).png` to `(303).png`.

- **Collapsing works, and the list closes the gap.** Ctrl+F12 called `SetVisibility(Collapsed)` on 56 `LP_`-prefixed entries.
  - **The list ended at the last vanilla passive** (Screenshot 301).
  - **Pressing it again restored them** (303). The list jumped to a mid-scroll position as the layout grew back (302), which is cosmetic.
  - **Hiding is therefore the 1.3-G method,** and the Edit-button block remains the backstop.
- **The entries are rebuilt, not reused.**
  - **The first press** found 108 live entries in the list's `ScrollBox`, plus older instances with `parent=nil`: leftovers of earlier list builds awaiting garbage collection.
  - **The second press** found a different set, and restored only 39.
  - **So the hide must be applied every time the list is built,** not once. Hook `WBP_OperatingTable_C:SetupPassiveChangeItem`, whose Blueprint callback runs after the body as the timing probe showed. Take the list from the hook's context, the screen's `WBP_PalCommonScrollList_Item` → its `ScrollBox` children, rather than `FindAllOf`, per the dev tips. Skip entries whose parent is nil.
- **The list's entries carry the mod's operations in two forms:**
  - **By `PassiveId`:** `LP_ExtractOne`, `LP_ExtractAll` and the `LP_Insert_*` aliases.
  - **By `ConsumeItemId` only:** the 61 direct routes have a vanilla `PassiveId` and an `LP_Implant_*` `ConsumeItemId` (`WBP_OperatingTable_ItemList.hpp` line 21).

  The probe matched only the `LP_` prefix. The real filter must match either field, so it covers everything `surgery_extraction` covers.
- **Not checked yet:** keyboard and controller navigation, and whether the hide survives picking another Pal or reopening the table. Both are verified against the real hook-driven version in 1.3-G.

**Still open from the probe list:**

- **Live View needs `bUseUObjectArrayCache = true`.** On 2026-10-18 the client's `Palworld\Mods\NativeMods\UE4SS\UE4SS-settings.ini` was changed by hand from `false` (the setting UE4SSExperimentalPW ships) to `true`. Its own comment says `false` "can help if you're experiencing a crash on startup". It is a dev-machine-only change, and a UE4SS reinstall reverts it. The game started fine with it on. Live View then showed the class's property definitions rather than instance values, which was hard to use for this check. So the check moved into the probe instead (Ctrl+F12, dev build 1.2.2), and the setting was set back to `false` the same day.
- **Hiding Surgery list entries.** This is a Live View check, done by hand on the client.
- **`UPalItemContainerManager.ItemContainerMap_InServer` as the complete container list,** to be checked when 1.3-H is built.

**The probe list, as planned:**

1. **Debug-only console commands** (`lp.netmode`, `lp.passives`, `lp.ledger`, `lp.journal`, `lp.flush`). They are registered only when `debug` is true. Use the GUI console on the client; the server console needs checking.
2. **One probe session on a dev build,** covering single player, the listen host, a client and the dedicated server:
   - **Net-mode calls:** the return values of `UPalUtility::IsServer`, `IsDedicatedServer`, `IsClientDedicatedServer` and `GetNetMode` (strings), the Kismet equivalents, and `GameState.bIsDedicatedServer`. Which world-context object works at server boot, before anyone joins? Feeds 1.3-A.
   - **Conveyor timing:** `ConvertProgressRate` in pre- and post-callbacks over one Pal's run. Feeds 1.3-B.
   - **Blueprint timing:** whether a Blueprint hook callback runs after the function. Feeds 1.3-B.
   - **The handshake route:** whether `APalPlayerController::SendLog_ToClient` called from server Lua reaches a client-side hook, and whether a sentinel `TextId` shows anything to the player. Feeds 1.3-G.
   - **Hiding list entries:** in Live View on the client, collapse one `WBP_OperatingTable_ItemList_C` entry in the Surgery list, then check scrolling and focus. Feeds 1.3-G.
   - **A join trigger:** whether `AGameModeBase::K2_PostLogin` or `APalPlayerState::OnCompleteLoadWorldPartitionAndAdjustCharacter_InServer` fires on the server once per join, with the player's state readable. Feeds 1.3-D and 1.3-G.
   - **Cleanup reach:** which `PalItemContainer` objects exist in memory on a listen host — players' inventories, base chests, the guild chest, dropped items — and whether offline players' inventories are loaded. Feeds 1.3-H.
3. **(Optional) The `+ModsFolderPaths` Lua override** for faster UI iteration, approved as a dev-only exception (round 1, decision 3). First fix the `UE4SS_ROOT` fallback in `lp/util.lua:27`, so the journal and ledger are never written into the repo.

### 1.3-A. Role detection and module split

1. **Add `lp/role.lua`.** It computes `standalone`, `listen_host`, `dedicated` or `client` from the world-context call the probe picks, never from a player character. It exposes `is_authority()`, `has_ui()` and `is_dedicated()`.
   - **It is re-evaluated on each map load.** The title screen is standalone; a world can be any of the four.
2. **`main.lua` registers only what the role needs.**
   - **The server half** (H1, the conveyor, recovery, the ledger, the join trigger, the handshake sender) runs where `is_authority()`.
   - **The UI half** (the gate, panel repair, the local-exchange poll, H6, the handshake receiver) runs where `has_ui()`.
   - **What each role gets:**
     - a listen host and single player get both halves;
     - a dedicated server gets the server half only, so no widget retries and no "not installed yet" lines;
     - a client gets the UI half only.
   - **Hooks are registered at load, not per role.** The role is not known at load, since the title screen comes first. Hooks whose half the current role does not run return at once; the gate is on the role, read on each firing. This is the cheap form of the split. Widget hooks are still never *armed* on a dedicated server: skip them when `is_dedicated()` becomes true on the first map load, and leave them disarmed.
3. **Break the `transaction` → `ui` dependency.** The listen host's own-click capture becomes something the UI half hands to the server half through a small shared table. The server half no longer requires `ui.lua`.
4. **Replace the `has_authority(find_first("PalPlayerCharacter"))` probe** in `lp/recovery.lua` and the `main.lua` ledger flush with `role.is_authority()`. Recovery and the boot flush then run at dedicated-server boot.
5. **`hooks.announce_if_complete` counts only this role's hooks,** so "All N hooks installed" prints on a dedicated server too.
6. **The "not installed yet" warning stops claiming "Expected before a world is loaded"** once a world is loaded.

#### 1.3-A status: code done, not yet run in game

- **`lp/role.lua`** reads `IsServer`, `IsDedicatedServer` and `IsMultiplayer` (bools, so no FString handling) on `Default__PalUtility` with `PalGameStateInGame` as context. `forget()` on each map load starts 120 × 1 s reads; the getters also resolve lazily. The read that finds the role logs `This machine is the <role> in this world.` and schedules the `on_known` listeners on the game thread, so no listener runs inside a hook callback.
- **`lp/hooks.lua`**: `register(path, callback, half, label, note)`, with `half` `"ui"` or `"server"`. A `/Script/` path is attempted at load; a `/Game/` path only from `hooks.arm(has_ui, is_authority)`, which `main.lua` calls from `role.on_known`, so a dedicated server never attempts the widget hooks. The installed line counts only the active halves. `rearm_on_map_load` and `in_world` are gone; the give-up warning now reads "… is not installed after 90 attempts; it is retried on the next map load."
- **`main.lua`**: H1's pre-callback captures only where `is_authority()`; H6 runs only where `has_ui()`. Recovery and the ledger flush moved from the map-load hook and the "mod startup" call to `role.on_known`, where authoritative.
- **`lp/conveyor.lua`**: `may_create_items` and the `GetActor` read are gone; the pass returns where `is_authority()` is false, logging once with the role.
- **`lp/recovery.lua`**: gated on `is_authority()`. **`util.has_authority`** is deleted, having no callers left.
- **`transaction` → `ui` broken** through `lp/local_click.lua`, a table holding `capture`. `ui.lua` now owns `capture_local_click` (moved from `transaction.capture_targeted_record`) and sets it at load; `capture` returns the record, or nil and whether a tab page is recorded.
- **Checks:** parse check, `luacheck` 0/0 over 17 files, `ledger_test.lua` all pass.
- **To verify in game** (with 1.3-B's stage): the role line on each machine (single player, listen host, client, dedicated server); no widget-hook warnings on the server; "All N hooks installed" on the server; a recovery and flush at dedicated-server boot.

### 1.3-B. Hook mechanics and small fixes

1. **`hooks.register` takes an optional post-callback.** It keeps the `PreId`/`PostId` that `RegisterHook` returns, and gets an `unregister`.
2. **Conveyor: remove the `STEP_MARGIN` projection, and keep the pre-callbacks** (round 8). The probe showed that the `OnUpdateCharacterContainer` pre-callback always carries the completing rate (≥ 1.0) before the Pal is removed, while a post-callback would see only the removal.
   - **Consumed** means the last rate seen is at least `COMPLETE_RATE`.
   - **Log a warning for any Pal that leaves below `COMPLETE_RATE` after passing 0.97,** a possible missed completion, so it shows in the log instead of passing silently as a withdrawal.
   - **Verify:** one Pal and a queue of three, in single player and on the dedicated server. Count the "Disassembly yielded" lines against the Pals fed in: no misses, no doubles.
3. **`conveyor_extraction` turned off unregisters the conveyor hooks.** Turned on, it installs them at once (needed by 1.3-F).
4. **Arm the widget hooks with `NotifyOnNewObject`** on the widget classes, in place of 90 × 1 s polling per map load. Follow the wiki's caution on Blueprint classes: register it after the player controller is up, for example on `ClientRestart`. Merge the handlers per class, since UE4SS allows one registration per class.
5. **Small correctness fixes:**
   - `util.name_to_string` returns nil instead of falling back to `tostring()` (`lp/util.lua:130`).
   - `operation_result_code` no longer parses userdata with `tostring` (`lp/inventory.lua:144`).
   - The `main.lua:90-94` comment on Blueprint hook timing is corrected to what the probe shows.
   - **The two LuaLS diagnostics open in the editor,** which `luacheck` does not report: `param-type-mismatch` (a `table|nil` passed as `table`) at `lp/ui.lua:447`, and an unused local `_handle` at `main.lua:121`. Fix them, or annotate them if they are false positives.

#### 1.3-B status: code done except step 4, not yet run in game

- **Step 1.** `hooks.register` takes a spec table (`path`, `callback`, optional `post`, `half`, `label`, `note`) and returns the registration. It keeps RegisterHook's `PreId`/`PostId`; `hooks.set_enabled(registration, bool)` calls `UnregisterHook` or re-registers. H1 now registers through it (`half = "server"`, label "the Surgery exchange handler"), so it is counted in the installed line.
- **Step 2.** `STEP_MARGIN` and the per-entry `step` are gone; consumed means the last rate ≥ `COMPLETE_RATE`. A Pal leaving at ≥ `NEAR_COMPLETE_RATE` (0.97) but below that logs a release `WARNING` naming its passives.
- **Step 3.** `conveyor.apply()` replaces `install`/`is_installed`: it registers both hooks the first time `conveyor_on()` is true, and otherwise enables or disables them. It runs at load and on each map load; a hook firing with the switch off schedules it (never unregisters from inside the hook). 1.3-F's `onChange` calls it.
- **Step 4: dropped (round 10).** Measured in the probe logs: the polling registers the widget hooks 26 s (single player) and 40 s (dedicated client) after load, one `pcall` per hook per second until then, and since 1.3-A it never runs on a dedicated server. `NotifyOnNewObject` on a Blueprint class needs that class loaded when it is called, which is the same wait, and the wiki warns about it on Blueprint classes. The gain is small and the risk is a native crash. The developer agreed to drop it.
- **Step 5.** `name_to_string` returns a Lua string as it is, `ToString()`'s string, or nil, never `tostring()`. `operation_result_code` parses only numbers and strings, and the failure detail names the returned type. The `main.lua` Blueprint-timing comment says the callback runs after the body. The `ui.lua` diagnostic went with the "hidden cards" field (1.3-E step 2, done early); `_handle` is `_`.
- **Checks:** parse check and `luacheck` 0/0 over 17 files; the editor shows no LuaLS diagnostics in `Scripts/`.

### 1.3-C. Exchange correctness under concurrency: the "lost implant" bug

1. **Per-request records keyed by `RequestPlayerId`** replace the single `pending_record` in `main.lua:74`. Two requests between one pre and post no longer overwrite each other.
2. **The journal holds one row per exchange,** keyed by the owner's UID and the Pal's `IndividualId`, instead of one global row.
   - Recovery targets a known Pal instead of "the only Pal in the world carrying the marker".
   - `settle_before_exchange` settles only rows for the same Pal.
   - **Format change.** Old `LPJ1` single rows are read once and migrated.
3. **`resolve_record` diffs only Pals carrying this exchange's marker.** Another player's unrelated passive change no longer refuses this one.
4. **Measure `snapshot_all` on the dedicated server with the full world loaded.** Only if the cost shows, replace it with a `NotifyOnNewObject` registry of `PalIndividualCharacterParameter`, or a marker-scoped search.
5. **Re-read Awfulhorrid's symptom** ("about half the time … the trait disappearing … with no resulting implant") against this list, and try to reproduce it on a dev build with fault injection and with two players.
6. **`ledger_test.lua` gains cases for the new journal and record keying.** A test for the journal goes beside it if the journal logic moves into a testable module.
7. **Verify on the dedicated server:** two players, each running Extract One at the same moment on different Pals, and an Extract All during another player's conveyor run. Each gets exactly their own module.

#### 1.3-C status: code done, unit-tested, not yet run in game

- **Step 1, as built: a stack, not a key.** H1's pre-callback pushes its record (or `false`) and the post-callback pops it. Pre and post of one call nest on the game thread, so last-in-first-out pairs each post with its own pre without reading the post-callback's arguments, which nothing here has verified.
- **What the server can know at capture.** `RequestRequestChangePassiveSkill_ServerInternal(int32 RequestPlayerId, const FPalNetArchive& Archive)` (`Pal.hpp:28442`): the requested passive is inside a serialized archive, so the server snapshot cannot be filtered to "Pals carrying this exchange's marker" at capture.
- **Step 3, as built: claims, plus an owner tie-break.** A record that resolves to a Pal claims its `pal_key` for 5 s, and every other record's resolve and `stranded_marker` skip a Pal another record has claimed. Of several candidates, the one whose `OwnerPlayerUId` is the requester's is taken when exactly one is. Two players' simultaneous exchanges therefore separate: the later capture sees only its own swap and claims it first, and the earlier one resolves on its next retry.
- **The vanilla early exit is unchanged.** Every exchange in the 1.2.1 probe logs resolved on attempt 1 (100 ms after the request), so the marker is on the Pal when the request returns, and "no candidate, a list changed, no marker rose" really is a vanilla operation.
- **Step 2: the journal is one row per Pal** (`LPJ2`: version, `pal_key`, state, phase, passive, item, marker). Every journal call names the Pal's key; a Pal whose key does not read gets no row, so its exchange aborts with the passive restored. The file is written to `.tmp` and renamed into place (`util.replace_file`, also for 1.3-F), so a failed write no longer truncates other Pals' rows. An `LPJ1` file is read once as a `legacy` row and rewritten; recovery replays it against the one Pal carrying its marker that has no row of its own.
- **Recovery** replays each row against the Pal with its key, keeps the row when that Pal is not loaded, and discards it when the Pal no longer carries the marker. **`settle_before_exchange`** reads only the same Pal's row, never replays, and always lets the new exchange proceed: it discards a row whose marker is gone, and replaces one whose marker is still on the Pal with a warning.
- **The owner's UID is not a journal column.** `IndividualId` is unique per Pal, and nothing in recovery grants to a player.
- **Step 4 is acceptance work:** measure `snapshot_all` on the dedicated server with the full world loaded. No code change unless it costs.
- **Step 5, Awfulhorrid's symptom read against the old code.** Two routes lost a passive with no module, both on a server with more than one player: (a) two exchanges within the resolve window made both ambiguous, so each ran out of attempts and journalled a stranded row; the restore waited for the next map load, which on a dedicated server is a restart, and before 1.3-A recovery did not even run at boot. (b) The second exchange's `settle_before_exchange` could not tell the first's row apart and replaced it, so the first was never recovered. Claims fix (a); per-Pal rows fix (b); 1.3-A runs recovery at boot. The fault-injection repro is acceptance work.
- **Step 6:** `tools/journal_test.lua` (32 checks) and `tools/exchange_test.lua` (17 checks: one exchange, two with one owner resolving through the claim, two with different owners through the tie-break, two unowned refused, a vanilla change next to an exchange, vanilla alone, claim release). Both pass, as does `ledger_test.lua`. `CLAUDE.md` and `README.md` list them.

### 1.3-D. Ledger delivery

1. **Flush when a player joins,** using the trigger the probe picked, on the server half.
2. **Conveyor debts stay owed to the original catcher** (round 1, decision 4). Verify on the dedicated server that the Pal's `OwnerPlayerUId` and the PlayerState's `PlayerUId` agree, using the already-swapped world.
3. **Keep one ledger format** for co-op and dedicated server.
4. **Verify:** a debt owed to a player who is offline is delivered when they join, with no conveyor activity needed.

#### 1.3-D status: code done, not yet run in game

- **`lp/joins.lua`** registers the join hook (`half = "server"`, so it counts in a server's installed line). A firing is ignored while the same `PlayerUId`'s join is pending, which absorbs the second firing; listeners run 3 s after the first, only while the player state is valid and `is_authority()` holds. 1.3-G's handshake sender is its second listener.
- **`main.lua`** registers a listener that runs `ledger.flush()` when anything is owed, logging what was delivered. The boot flush's give-up line now says owed modules are delivered when a player joins.
- **Steps 2 to 4 are acceptance work:** the 1.2.0 server run already delivered a conveyor debt to the swapped owner; the join delivery needs a debt owed to an offline player.

### 1.3-E. Logging behind the debug switch

This comes before the settings work: logging touches the same files as 1.3-A to 1.3-D, and settles faster here.

1. **Sort every `util.log` call by audience.**
   - **Kept in release:**
     - the startup counts line;
     - the one-line outcome of each exchange;
     - each refusal or unwind a player would notice;
     - each warning that needs action.
   - **Moved to `options.debug_log`:**
     - per-poll and per-firing traces;
     - Surgery panel internals (`at finish`, `refresh on finish`, `reset at 1600 ms`, `Edit blocked/released`, `OnPassiveUpdate: […]`, `Checked the … exchange`, `Marker … is on the Pal`, "Panel refresh armed").
2. **Drop the "hidden cards" field, or reword it.** Done with 1.3-B: dropped.
3. **Measure:** one Extract One on a release build logs one line on the server and one on the client. Count the lines in the log.

#### 1.3-E status: code done, not yet run in game

- **Moved to `debug_log` in `ui.lua`:** every Edit-button, Pal-detail, `BindFromHandle`, `UpdateNum`, "reset at 1600 ms", "Panel refresh armed", "Checked the … exchange", "Marker … is on the Pal", "Requested …", "server accepted", "replaced by this request" and "panel already closed" line. `ui.lua` now requires `lp.config` (no cycle: config requires only util).
- **Moved to `debug_log` elsewhere:** `main.lua`'s `OnPassiveUpdate: […]`, and `transaction.lua`'s two "not one of our operations" lines, which fired on every vanilla surgery.
- **The client's own outcome line (release):** `Surgery <marker> finished; the Pal now has […].` The trigger and poll count went to a debug line. So a player on a dedicated server has a line of their own to report, as the 1.2.1 probe asked for.
- **Kept in release:** the startup counts line, the role line once per world, the installed-hooks line, every outcome line in `transaction.lua` and `conveyor.lua`, every refusal (`The server refused …`), and every `WARNING`/`ERROR`.
- **Expected count for one Extract One, by reading the code:** a dedicated server logs one line (`Extracted … for player …`), its client one (`Surgery LP_ExtractOne finished …`), and a listen host or single player both, so two. Acceptance counts them.

### 1.3-F. Settings restructure and Better Mod Manager registration

The detail is in [Proposed restructure](#proposed-restructure) and [Draft UI text](#draft-ui-text-character-counts-measured).

1. **Add `Scripts/config.lua`.** It holds `debug` (with its `stage:DebugMode` tag), `conveyor_extraction`, `surgery_extraction`, `surgery_ui_gate`, `experimental_features` and `remove_mod_items`, each with a one-line player-facing comment and no dev file names.
2. **Move `debug_faults` to a dev data file under `Scripts/lp/`.** It is inert unless `debug` is true.
3. **Rename `lp/config.lua` to `lp/options.lua`.** It stays the only reader, keeps the same getters, and adds `surgery_on()`.
4. **Move `Scripts/passive_items.lua` to `Scripts/lp/passive_items.lua`.**
5. **Delete `Scripts/settings.lua`.** The next dev stage is `-Force`.
6. **Register with BMM** from `main.lua` (or pass `folder` explicitly), through `loadfile` of `BetterModManager/Scripts/modconfig.lua`, as a soft dependency.
   - Give no `enabledKey`.
   - Use the sections "Extraction" and "Troubleshooting", and add "Host tools" for 1.3-H.
   - `onChange` writes into the live table. Register before `main.lua` reads `conveyor_on()` at load.
   - Without BMM, `config.lua` alone controls the mod; that is what a dedicated server uses.
   - **Mark host-controlled settings in their descriptions** ("Set by the host in multiplayer"): `conveyor_extraction` and `surgery_extraction`.
7. **`surgery_extraction` behaviour.** Covered: Extract One, Extract All, the 54 `LP_Insert_*` alias implants, and the 61 direct routes. In short, every operating-table row this mod adds.
   - **Every gate recognises a covered operation the same way:** an extraction marker, an `LP_Insert_*` alias, or an operation whose `ConsumeItemId` is an `LP_Implant_*`. The panel already reads `CachedConsumeItemId`.
   - **The backstop for direct routes is new server work.** Today a direct route leaves no marker and the server logs "not one of our operations". The server half needs to recognise a passive added by a direct route (the resolve diff shows a passive added with no marker, and the routes table maps that passive to an `LP_Implant_*`). With the setting off, it removes that passive and refunds the module.
   - **The host's value is authoritative.** A client's own value is ignored; the client follows the host's value, received by the handshake (1.3-G).
   - **The authoritative machine's own gate blocks the covered operations before the gold charge,** for single player and the listen host's own clicks.
   - **Remote clients' gates block before the gold charge too,** once the handshake has delivered the host's value.
   - **The server-side refusal is only a backstop,** for a client without the gate (`surgery_ui_gate` off, or an older version). It restores the passive, or undoes the swap and refunds the module, and logs a warning naming the setting and both machines' values.
   - **Grants are never blocked on the receiving side.** Ledger debts are still delivered.
8. **Runtime write-back to `config.lua`** (round 7). Every runtime change, from BMM's `onChange` or the mod's own clearing of `remove_mod_items`, is saved into the **installed** `config.lua`, so settings persist on that machine with or without BMM.
   - **Rewrite only the value of each changed key,** line by line. Keep comments, order, and the `stage:DebugMode` tag. Write atomically: a temporary file in the same folder, then a rename. Leave the file untouched when nothing changed.
   - **The write runs on the game thread,** like every other file write in the mod. On failure, log one warning; the live value still applies for the session.
   - **Precedence:** `config.lua` supplies the defaults, then BMM's saved values (`ModConfig.LootablePassives.lua`) override them. Because both are written on each change, they agree. After a reinstall, `config.lua` returns to the shipped defaults. A BMM user's saved values re-apply, and are written back into the fresh `config.lua` once at startup if they differ. A player without BMM is back on the defaults.
   - **Reinstall resets settings: accepted and documented** (round 7). Settings persist within a version. A version update reinstalls and resets `config.lua`. On a dev build, `DebugMode` true makes the loader reinstall at **every** launch, so dev-build settings do not survive a restart unless BMM holds them.
   - **Check before building on this:** that the dedicated server process can write its own mod folder under `C:\Program Files (x86)\Steam\steamapps\common\PalServer\`. It already writes `UE4SS.log` in the UE4SS root, but test the mod's own folder.
   - **The rule:** `CLAUDE.md` now says the "never write the game folders" rule governs deployment, and that the mod's config and runtime data files are its own to write.
9. **Verify:**
   - BMM shows a "Supported" page with short text, and changes apply live.
   - A BMM change is reflected in the installed `config.lua` within a second, with the `stage:DebugMode` tag and comments intact.
   - Without BMM, an offline edit to `config.lua` takes effect at the next start.
   - `ModConfig.LootablePassives.lua` holds the non-default values.
   - BMM no longer writes the installed `Scripts\` or `mods.txt`.
   - Without BMM, `config.lua` works.
   - Clean up the dev machine's leftover Auto-mode files (`ModConfig.file.LootablePassives.lua`, `BetterModManager.profile.LootablePassives.lua`) if BMM keeps re-applying them.

#### 1.3-F status: code done except the client gate (moved into 1.3-G), unit-tested, not yet run in game

- **Files.** `Scripts/config.lua` (new, six settings, the stage tag on `debug` only); `Scripts/lp/faults.lua` (new, `return {}` plus the scenario documentation); `lp/config.lua` → `lp/options.lua` and `passive_items.lua` → `lp/passive_items.lua` (`git mv`); `Scripts/settings.lua` deleted. `stage.ps1 -DryRun` lists the three stale item-folder files, so the next stage is `-Force`.
- **BMM facts read from the installed `modconfig.lua` that shaped this:** `set()` saves and publishes but does not call `onChange`; saved values are those that differ from each option's `default`; an option with no `default` takes it from the passed `config`. Taking defaults from a written-back `config.lua` would make a changed value its own default, drop it from BMM's file, and lose it at the next reinstall. **So every option carries an explicit shipped default,** and no `config` table is passed.
- **Startup reconciliation** (`options.reconcile`): a BMM-saved value (one differing from the shipped default) wins and is written into `config.lua`; otherwise a `config.lua` value differing from the shipped default is handed to BMM with `set`, except `debug`, whose file value is the build's stage tag and is not saved for later builds.
- **Runtime changes.** BMM's `onChange` and the mod's `options.set` both go through `change()`: live table, one-line write-back through `util.replace_file`, then `options.on_changed` listeners; `set` also calls BMM's `set`. `main.lua`'s listener runs `conveyor.apply()` for `conveyor_extraction`. 1.3-G adds the handshake resend, 1.3-H the removal.
- **Text.** Labels and descriptions as drafted, plus "Surgery extraction" and the two host-tool toggles; the removal's description was cut from 130 to 96 characters. Headers: Extraction, Troubleshooting, Host tools.
- **Step 7, server backstop: done.** With `surgery_extraction` off on the authoritative machine, `transaction.lua` refuses an extraction (passive restored), unwinds an alias implant (alias undone, module refunded) and undoes a direct route (`refuse_direct_route`: the one Pal whose list gained a direct-route passive replacing at most one other; that passive is undone and its module refunded). Each logs a `WARNING` naming the setting; the gold stays spent. The 61 direct-route passives are derived in `passives.lua` as the `LP_Implant_*` passives no alias targets; that set was compared with `LootablePassivesOperatingTable.json`'s 61 rows and is identical.
- **Step 7, the gates before the gold charge:** done with 1.3-G, since the client's gate needs the host's value from the handshake and the authoritative gate shares the same code.
- **Tests.** `tools/options_test.lua` (34 checks): write-back of one line with comments and the stage tag kept, no notification for an unchanged value, unknown or wrong-typed values ignored, a restart reading the written value, a broken file and a wrong type, and against a stand-in `modconfig.lua`: the id, no `enabledKey`, the mod folder, the saved value winning and written back, a file edit handed over, debug not handed over, every default, `dependsOn`, descriptions ≤ 110, `onChange` written back, `set` handed over. `exchange_test.lua` gained 7 direct-route checks. All four tests pass; `CLAUDE.md` (settings section, layout, tests) and `README.md` (settings section, tests) are updated.

### 1.3-G. Host-has-mod handshake and the client pre-block

1. **The server half sends a sentinel to each player on join,** by the route the probe confirms. The leading candidate is `SendLog_ToClient` with a reserved `TextId`.
   - **The payload carries the host's authoritative settings** (`surgery_extraction`, `conveyor_extraction`). With an FName `TextId`, encode the combinations as distinct sentinels.
   - **It is sent again when a setting changes at runtime** through BMM on the host.
2. **The client half records "host confirmed"** and the host's settings. They are reset on each map load, which is when the client joins or leaves a world.
3. **Until the host is confirmed, or while the host's `surgery_extraction` is off, the client stops the covered operations before they start.**
   - **Chosen (confirmed by probe on 1.2.2):** the mod's operations are left out of the Surgery list. After each `SetupPassiveChangeItem`, collapse every entry whose `PassiveId` starts with `LP_` or whose `ConsumeItemId` starts with `LP_Implant_`.
   - **Fallback:** the Edit button is blocked by the existing gate.
   - **Either way, the player sees why,** as a message, not a silent no-op.
4. **On single player and the listen host,** the role is authoritative and the gate reads the local value directly. No handshake is needed.
5. **No fallback is planned** (decision 7). If the probe finds no route from server Lua to a client hook, stop and replan with the developer before any other 1.3-G work.
6. **Verify:** a modded client on a vanilla listen host, and on a dedicated server without the mod, sees no usable LP operations and gets the message. A modded client on a modded host whose `surgery_extraction` is off is blocked the same way. It is unblocked live when the host turns the setting back on.

#### 1.3-G status: code done, unit-tested, not yet run in game

- **`lp/host.lua`.** The text is `LootablePassives host v1 surgery=<0|1> conveyor=<0|1>`, sent with `Debug_ReceiveCheatCommand_ToClient` as the probe proved (not `SendLog_ToClient`, the step-1 candidate). It goes to the joining player's controller, matched by `PlayerState.PlayerUId`, as `lp/joins.lua`'s second listener, and to every remote controller when the host changes `surgery_extraction` or `conveyor_extraction`. A controller whose `IsLocalController()` (`Engine.hpp:8290`) is true is skipped, so a listen host never runs the cheat RPC on itself. The receiver is a `/Script/` hook, `half = "ui"`, ignored where `is_authority()`; it logs one release line when the host's values arrive or change. `forget()` on map load.
- **One answer for every gate:** `host.surgery_allowed()`. The local setting decides where the world is held; on a client, only a host that sent the text with `surgery=1`. `host.refusal()` says why not: `off_here`, `off_host` or `unconfirmed`.
- **What counts as covered: `passives.is_covered(passive_id)`.** That covers an extraction marker, an alias, or a direct-route passive. Because a passive owns at most one operating-table row, the `PassiveId` alone decides, and `ConsumeItemId` is not read. 117 ids are covered, the same count as PalSchema's `117 rows added`.
- **Edit-button gate** (1.3-F step 7 too): blocks while a slot is selected, a covered operation is pending, and `surgery_allowed()` is false. Single player and the listen host block on their own setting, clients on the host's.
- **List hiding.** A Blueprint hook on `WBP_OperatingTable_C:SetupPassiveChangeItem` (`half = "ui"`) records the screen and, while refused, schedules a pass one frame later. (The live rebuild described at the end of this bullet was removed after it crashed in acceptance session 1.) The pass collapses (`SetVisibility(1)`) every child of the screen's `WBP_PalCommonScrollList_Item.ScrollBox_0` whose `PassiveId` is covered. It reads the children with `GetChildrenCount`/`GetChildAt` (`UMG.hpp:1082-1084`), from the hook's context rather than `FindAllOf`. When the host's values arrive or change, and when the local `surgery_extraction` changes, an open screen with a Pal selected rebuilds its list, so unhiding needs no reopen.
- **The player sees why: `lp/notice.lua`,** once per world per reason. It logs the message, then calls `UPalLogManager::AddLog(Important, FText(text), {})` on `UPalUtility::GetLogManager(PalGameStateInGame)` (`Pal.hpp:26236`, `:38009`). **This call is the one engine call in 1.3.0 no probe has run:** building an `FText` from Lua and passing an empty table for `FPalLogAdditionalData` are unverified. It is called once per world per reason, logged before the call under debug. If it misbehaves at acceptance, cut it back to the log line.
- **`FText` added to `.luacheckrc` and `.luarc.json`.**
- **Tests.** `tools/host_test.lua` (24 checks): the text round-trips for all four combinations, foreign texts are rejected, a later version still reads, and the covered set's composition and total. Listed in `CLAUDE.md` and `README.md`.
- **Acceptance:** this step's verify list, plus keyboard and controller navigation over the collapsed list, and the hide surviving another Pal selection and a reopen.

### 1.3-H. Cleanup action: remove the mod's items from the world

1. **What it removes.** Every `LP_Implant_*` item in the item containers loaded on the authoritative machine. It also clears the ledger.
   - **Containers:** online players' inventories, base and guild chests, and dropped items, as far as the 1.3-0 probe shows they are reachable.
   - **Untouched:**
     - Pals' passives (decision 5).
     - The 21 vanilla `PalPassiveSkillChange_Consumable_*` items, even those the mod granted. They are vanilla items, indistinguishable from found ones, and stay valid after uninstall.
     - Anything not loaded, notably **offline players' inventories**, unless the probe shows them in memory. The result line names what was not reachable.
   - **Purpose.** A clean uninstall. PalSchema 0.6.7 logs that it "will be unable to clean up invalid items" on this game build, so modules left in a save after uninstalling become unknown items.
2. **The two settings** (round 6). BMM has no button type, so the action is built from two `toggle` options in a "Host tools" section:

   | Key (draft) | Label | Default |
   | --- | --- | --- |
   | `experimental_features` | Enable experimental features (like mod item removal) | false |
   | `remove_mod_items` | Remove ALL items created by this mod from the game world? | false |

   - `remove_mod_items` has `dependsOn = "experimental_features"`, so it is disabled while the first is off.
   - **The removal runs only while both are true.**
3. **When it runs (event-driven).**
   - **Immediately,** when `remove_mod_items` turns true through BMM's `onChange` and the machine is in a world with authority.
   - **On entering a world,** when both values are already true at that point, whatever the reason: an edit to `config.lua` made offline, BMM values saved earlier, or an earlier run that was interrupted. This also covers a **dedicated server**, through its `config.lua`. It runs on the first map load where `role.is_authority()` holds and the world is loaded. Delay it until the containers are populated; the probe decides the signal.
   - **On a client it never runs.** The option shows a message saying the host must run it, or is disabled once the role reads `client`.
4. **Unchecking (event-driven, on success only).** `remove_mod_items` is cleared **only after the removal completes successfully**. On failure or interruption it stays checked, so the next world entry runs it again. `experimental_features` is left as the user set it. No other edge case is handled, such as a player quitting part-way (round 6).
   - **Clearing goes through the same write-back as every runtime setting change** (1.3-F step 8, round 7): the mod sets `remove_mod_items = false` in the live table and in the installed `config.lua`, and, with BMM, through `settings.set`. The completion-marker and run-every-time options were dropped.
5. **Logging and result.** One release line before acting, with counts of the items found per container type. One release line after, with counts of what was removed, and what was not reachable. On a machine with UI, show the outcome to the player too.
6. **Verify:**
   - **On a listen host:**
     - Put modules in an inventory, a chest and the guild chest, and leave a ledger debt.
     - Run the cleanup through BMM, then check that each place is empty, that Pals keep their passives, and that the request unchecked itself.
     - Save and reload, and check that no `LP_Implant_*` items are in reach.
   - **On the dedicated server:** set both values in `config.lua` with the server stopped, start it, and check the result lines and that the removal does not repeat on the next start.
   - **Interrupted run:** inject a failure (a new `debug_faults` entry) and check that the request stays checked and runs at the next world entry.

#### 1.3-H status: code done, ledger part unit-tested; the removal call is unverified

- **The removal call is the one runtime unknown that decides this stage.** `Pal.hpp` has no server-side removal to match `AddItem_ServerInternal`: `UPalItemContainer` and `UPalItemSlot` expose no removal function, and the container manager only looks containers up. **The candidate used is `UPalNetworkItemComponent::RequestDispose_ToServer(const FGuid& RequestID, const FPalItemSlotIdAndNum& SlotInfo)`** (`Pal.hpp:30273`; the struct is `{ SlotId = { ContainerId = { ID = FGuid }, SlotIndex }, Num }`, `Pal.hpp:4489-4501`, `:1919`). It is called on the first `PalNetworkItemComponent` in memory, with both structs as Lua tables.
  - **Unknowns:** whether a `_ToServer` RPC called on the server runs its implementation; whether that implementation refuses containers its component's player has no permission for (another player's inventory, another guild's chest); and whether tables convert to these structs.
  - **The design survives a refusal:** a verify pass counts what remains, and the request stays checked unless nothing does.
  - **Other candidates if it fails:** `RequestMove_ToServer`/`RequestDrop_ToServer` on the same component, and `UPalIncidentBase::RequestConsumeInventoryItem` (`Pal.hpp:24349`, player inventory only; constructing an incident crashed the game before, see `CLAUDE.md`).
  - **First acceptance item, on a backed-up world:** one LP module in the host's inventory, one in a chest, then the cleanup through `config.lua`. If the call crashes or does nothing, the next step is a debug-key probe of the candidates.
- **`lp/cleanup.lua`.** Where `is_authority()` and `removal_requested()` hold, a run takes `FindAllOf("PalItemContainer")` once and walks it three times, 100 containers per frame.
  - **The passes:** count (one release line with counts by inventory, chest and guild chest, by `bIsGuildChestContainer` and `OwnerMapObjectInstanceId`), remove (dispose of every `LP_Implant_*` stack whole), verify (count again).
  - **Then the ledger:** `ledger.forget_items` drops `LP_Implant_*` debts and keeps vanilla-consumable debts, since those are valid after uninstall.
  - **Clearing:** only with nothing remaining and the ledger written does it `options.set("remove_mod_items", false)` (saved to `config.lua` and BMM) and log the result, naming what was not reached (unloaded containers, items on the ground). Otherwise one `WARNING`, and the request stays.
- **Triggers** (`main.lua`): either setting turning on; 10 s after the role is known on an authoritative world entry; every player join. With no `PalNetworkItemComponent` (a dedicated server with nobody online) it logs that it waits for a join. A map load cancels a run in progress. **On a client** it never runs, and tells the player once that the host runs it.
- **Not built:** a fault-injection hook for an interrupted run. Faults are scoped to Surgery exchanges. A map load or quitting mid-run interrupts it for acceptance instead.
- **Tests.** `ledger_test.lua` gained 5 `forget_items` checks. The container walk is engine work and is acceptance-tested.

#### Acceptance session 1: 1.3-G and 1.3-H on the dedicated server (dev build 1.2.5)

**Prep, done 2026-10-18:**

- **Backup:** the server world is at `C:\Users\greg_\PalworldBackups\2026-10-18-server-pre-cleanup-test\9F2509B44E9A564ACFF601A9DB9A81EC\` (45 files, `MANIFEST.md5` verified against the source). It was taken with the server and game stopped; no journal or ledger file existed on the server.
- **Debug-build `config.lua` watch (`options.watch_file`):** while `debug` is true, `config.lua` is read every 5 s and an edited value goes through the same path as a BMM change. It exists because a `DebugMode` build is reinstalled with the shipped `config.lua` at every launch, and the server has no BMM, so a server setting can only be changed while it runs. `options_test.lua` gained 7 checks for it.
- **Extra debug lines:**
  - `cleanup:` the component used, every stack in the remove and verify passes (item, count, kind, container), and what each slot holds right after its dispose call;
  - `handshake:` the controllers found per join or change, and each text received (the host's or not).
- **Staged as dev 1.2.5** (`DebugMode` true; `debug = true` in the staged `config.lua`).

**The server's installed settings file** is `C:\Program Files (x86)\Steam\steamapps\common\PalServer\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\config.lua`. Edit it while the server runs; the edit applies within 5 s (`DEBUG: config.lua was edited: …` in the server log). A restart resets it.

**Steps:**

1. **Start the server, then the game, and join.** Both logs:
   - `Loaded 115 … Debug mode on`;
   - the role line (`dedicated server` and `client`);
   - `All N hooks installed`, with no "not installed" warnings on the server.

   Client: `The host runs Lootable Passives: Surgery extraction on, conveyor extraction on.` about 6 s after joining. Server: `handshake: player … joined; 1 remote controller(s)`.
2. **G, allowed:** open the Pal Surgery Table; the mod's operations are listed, and one Extract One works.
3. **G, host off:** on the server, set `surgery_extraction = false`.
   - **Server:** `Setting surgery_extraction is now false.` and `handshake: a setting changed; sending to 1 …`.
   - **Client:** `… Surgery extraction off …`.
   - **In game:** reopen (or keep open) the Surgery Table. The mod's operations are hidden, vanilla's are not, and the on-screen message appears once. **Watch for a crash at the message: it is the `AddLog` call.** Try keyboard and controller navigation over the shortened list, and select another Pal.
4. **G, host on again:** set it back to `true`. The operations return without reopening, if the screen is open with a Pal selected.
5. **H, cleanup:** note what LP implants you hold, and what is in one chest. On the server, set `experimental_features = true`, then `remove_mod_items = true`.
   - **Expected server log:** `Removing this mod's implants from the world: found …`, then `cleanup: calling RequestDispose_ToServer …`, then a `cleanup remove:` / `cleanup: dispose …` line per stack, then either `Removed this mod's implants …` with `remove_mod_items` set back to `false` in the file, or a `WARNING … did not finish` with `cleanup verify:` lines naming what is left.
   - **In game:** the LP implants are gone from the inventory and the chest, the vanilla implants are still there, and Pals keep their passives.
   - **If the game or server crashes,** the last `cleanup:` line names the call.
6. **Collect both `UE4SS.log` files into `.docs\`** before restarting anything.
7. **Restore:** with the server stopped, copy the backup over `PalServer\Pal\Saved\SaveGames\0\9F2509B44E9A564ACFF601A9DB9A81EC\`.

#### Acceptance session 1, results so far (2026-10-18)

- **Steps 1 and 2: pass.** Server: the role line, `All 4 hooks installed`, no widget warnings, the handshake sent at the join, and an Extract One handled through the server snapshot. Client: `All 7 hooks installed`, the handshake received about 6 s after joining, and its own `Surgery LP_ExtractOne finished` line.
- **Step 3: the client crashed** (`EXCEPTION_ACCESS_VIOLATION reading 0xffffffff00000051`). The edit to the server's `config.lua` applied within 5 s, the server sent `surgery=0`, and the client logged `Surgery extraction off`, then died.
  - **The crashing stack:** engine tick → net receive → UE4SS hook → Lua. The receiver ran the `on_heard` listener synchronously, and `ui.rebuild_operation_list` reached for the Surgery screen recorded in the earlier session, which had been closed for about two minutes. Its debug line before `SetupPassiveChangeItem` never printed, so the crash was in the checks on the stale widget.
  - **The first handshake** did the same, harmlessly, because no screen had been recorded yet.
  - **Logs:** `.docs/accept1-client-crash-1.2.5.log`, `.docs/accept1-client-crash-1.2.5-context.log` (the crash report), and `.docs/accept1-server-1.2.5.log`.
- **Fix (dev 1.2.6):**
  - `ui.rebuild_operation_list` and `host.on_heard` are deleted, and the receiver only records and logs.
  - The list follows a change at its next build (another Pal selected, or a reopen). The Edit-button gate follows at once, since it reads `host.surgery_allowed()` at every firing.
  - 1.3-G step 6's "unblocked live" therefore holds for the button, not for the list.
  - `CLAUDE.md` dev tips gained two rules: recorded widgets only from their own screen's hooks, and nothing but recording inside an RPC hook.
- **The `AddLog` notice was not reached** before the crash, so it is still untested.
- **Step 3 on dev 1.2.6 (client): pass.**
  - The client heard `surgery=0` at the join.
  - Every list build logged `operation list: 75 entries hidden (off_host)`, and only vanilla operations showed.
  - The message line was logged.
  - **The on-screen part did not run:** `notice.lua` returned silently because `FText` is not a plain function in this UE4SS. Fixed in the repo, not yet staged: it now logs what `FText` is (`notice: FText is a …`, or that there is none) and tries a callable table or userdata too.
- **Step 4: the change arrived without a crash.** The server applied `surgery_extraction = true` and sent `surgery=1`; the client logged it. List and button behaviour: see the developer's report.
- **Step 4 in game: pass.** Extract One and Extract All both worked again after the host turned `surgery_extraction` back on.
- **Step 5, cleanup on dev 1.2.5 (server): removal works; the run then crashed the server.**
  - **The count pass** found `13 in inventories, 609 in chests, 0 in guild chests (82 stacks) in 4794 loaded container(s)`, the same 622 the 1.2.1 probe counted.
  - **The removal call works.** `RequestDispose_ToServer`, called on the server on `PalNetworkItemComponent …PalNetworkTransmitter_2147479529.Item` with both structs as Lua tables, returned for all 82 stacks, and every slot read `None x0` immediately after. So it runs synchronously on the server, the tables convert, and no permission check refused a chest.
  - **About 1 s later the server died** with `EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff`; the stack ran engine tick → UE4SS game-thread scheduler → Lua. **Cause:** the run held the 4,794 container objects of one `FindAllOf` across frames, and the garbage collector freed some between slices (the probes saw the count move between scans, 5,359 vs 5,312).
  - **Logs:** `.docs/accept1-server-cleanup-crash-1.2.5.log`, `.docs/accept1-server-cleanup-crash-1.2.5-context.log`, `.docs/accept1-client-1.2.6.log`.
- **Fix (dev 1.2.7):**
  - **No engine object is held across frames.** The run reads every container's `ID` (`UPalContainerBase`, `FPalContainerId`) into plain numbers in its first frame. Each slice looks the manager and the component up with `FindFirstOf`, and each container by id through `UPalItemContainerManager::GetContainer` (`Pal.hpp:25350`), in that frame. A container gone by then is skipped; a missing manager or component stops the run with a warning, and the request stays.
  - **`CLAUDE.md`** gained the general rule: never hold an engine object from one frame to the next unless it lives as long as the world.
  - **1.2.7 also carries the `notice.lua` diagnosis** (what `FText` is).
- **The server world was restored** from the backup after the crash (manifest-verified), so the rerun starts from the same state.
- **Developer's observation of the 1.2.5 run:** Lucky and Legend left the player's inventory in game before the server crashed, so the removal reached a live player's inventory. The chests were not checked. The client's log showed nothing, because the cleanup runs only on the server.
- **Added in dev 1.2.8, kept for release (developer's request): host notices.**
  - `host.broadcast(message)` shows a message on the host where it has a UI (`notice.once`). It also sends it to every remote controller as `LootablePassives notice <message>`, through the same RPC as the settings text.
  - **A client** recognises the prefix (`host.parse_notice`) and only queues the message in the RPC hook. On the next game-thread tick it logs it as a release line and shows it on screen, once per world per distinct message.
  - **The cleanup sends three:** "…the host is removing this mod's implants from the world." when a run starts (the server also logs a release `… has started (after <trigger>).`); "…the host removed N of this mod's implants from the world." on success; "…did not finish; the host will try again." on failure.
  - `host_test.lua` gained 5 notice checks.
- **Step 5 rerun on dev 1.2.8: pass on the server, no crash.**
  - **Setup:** the world was restored from the backup. The developer's three inventory implants came back this time from a Disassembly Conveyor run of the same Pal, and the two chests hold a slightly different mix.
  - **The run:** `found 13 in inventories, 609 in chests, 0 in guild chests (81 stacks) in 4745 loaded container(s)`. All 81 dispose calls returned with the slot reading `None` right after; the verify pass found nothing; 0 ledger debts. Then `Setting remove_mod_items is now false.`, and the installed `config.lua` reads `remove_mod_items = false`.
  - **Notices:** the server sent "…is removing…" and "…removed 622…". The client logged both as release lines.
  - **The on-screen call:** `FText` is a userdata in this UE4SS, so the 1.2.6 check had skipped `AddLog`. On 1.2.8 the client called it twice without an error. Whether the message showed on screen is the developer's report.
  - **In game (developer):** both messages showed on screen (blue text), so `AddLog` works. The inventory kept only Demon God, which is `PAL_ALLAttack_up3`, a vanilla consumable. One crate kept only vanilla Disposable Implants (all orange), and the other is empty. Pals edited in the past kept their passives. **1.3-H and the 1.3-G notice: pass.**
  - **Logs:** `.docs/accept1-server-cleanup-1.2.8.log`, `.docs/accept1-client-cleanup-1.2.8.log`.
  - **After the cleanup (developer):** a conveyor run, an Extract One and an Extract All each produced new implants. A finished cleanup does not block anything.
  - **The world was kept** in its cleaned state (developer's choice), and the pre-cleanup backup stays in `PalworldBackups`.
- **Resumed at step 3** on dev 1.2.6: the client restarts and rejoins; the server keeps running 1.2.5, whose server code is unchanged, with `surgery_extraction = false` still in its file. On joining, the client should hear `surgery=0` and the list should hide.

#### Acceptance session 2: faults and timing on the dedicated server (dev build 1.2.9, 2026-10-18/19)

Setup: `faults.lua` armed with `{ on = "implant", fail_refund = true }` and two `{ on = "one", halt_after_journal = "granted/marker" }`, plus a debug timing line on the server snapshot. Logs: `.docsccept2-*.log`.

- **1.3-B conveyor timing, queue of three: pass.** Three `consumed` lines at rates 1.0031, 1.0016 and 1.0012, about 1.7 s apart, and one `Disassembly yielded` line per Pal: 4 + 3 + 4 = 11 modules, all in the player's inventory. No "close to complete" warning. A single Pal was seen in session 1.
- **1.3-C step 4, `snapshot_all` on the server: measured.** 1,760 Pals in 94 ms, then 1,730 Pals in 60 ms and 61 ms, once per remote Surgery request. Tolerable; no registry needed for 1.3.0.
- **The game itself refuses a duplicate passive,** even through an alias route: with `surgery_ui_gate` off, Edit stayed disabled for an implant of a passive the Pal already had, and the client logged no `Edit blocked` line. The server's duplicate check in `finalize_implant` is a second line that a player cannot reach this way.
- **The server backstop on a dedicated server: pass for both route kinds.** The client's list was built while the host had `surgery_extraction` on; it was then turned off with the screen open and `surgery_ui_gate` off, so Edit stayed lit.
  - **Direct route (Legend):** `refused implanting Legend … Undone=true, module refunded`. The Pal was left without Legend and the module was back after reopening the screen.
  - **Vanilla consumable route (Demon God, `PAL_ALLAttack_up3`):** `A passive list changed with no marker, so this was not one of our operations`. Correct: the game's own implants are outside `surgery_extraction`, and their entries are not hidden.
  - **Alias route (Ace Swimmer, `SwimSpeed_up_2`):** claimed fault scenario 1, `DEBUG FAULT: direct refund … skipped`, `recorded it as owed`, `refused implanting SwimSpeed_up_2 … Alias undone=true, module owed`. The ledger file held one row for the player.
  - **UI wrinkle:** after the server undid an implant, the open Surgery screen still showed the passive on the Pal. The client logged one `OnPassiveUpdate` (the add) and none for the undo. Reopening the screen shows the true state. Matches the known Edit-button redraw issue in the Workshop text's known issues; not fixed.
  - Reopening the screen with the host off hid 15 entries (`off_host`) and showed the on-screen notice.
- **1.3-D delivery on join: pass.** Leaving to the title and rejoining: `Delivered 1 owed module(s) when a player joined; 0 still owed.` 3 s after the join, the in-game item notification, the module count back at 2, and the ledger file deleted.
- **Finding: the client's log recorded none of the grants.** Grants happen on the server, so a player on a dedicated server has nothing in their own log. **Added in 1.2.10 (developer's request):** grant reports from the host.
  - `host.tell_grants(kind, deliveries)` sends `LootablePassives grant <kind> <item id>x<count> …` through the same RPC to the remote player each delivery went to. The host's own player is skipped; they read the host's log.
  - Kind `owed`, from both ledger flushes in `main.lua` (world entry and join): the client always logs `The host delivered N module(s) owed to you from earlier: …`.
  - Kind `now`, from the conveyor's flush and from every exchange's grants and refunds (`note_granted` and `report_granted` in `lp/transaction.lua`, sent after each `run_finalize`): the client logs `The host granted you N module(s): …` only when its own `debug` is true.
  - `ledger.flush` returns the deliveries as a fifth value. `host_test` checks the text's round trip.
- **The grant reports, in game:**
  - **Conveyor (1.2.10): pass.** `The host granted you 4 module(s): …` on the client 0.02 s after the disassembly.
  - **Extract One: missed in 1.2.10, fixed in 1.2.11.** `finalize_extraction` replaces its capture record with the resolved one (`record = resolved`), so the grant was noted on a table `run_finalize` did not report. Both now share one `granted` list. In 1.2.11 an Extract One logged `The host granted you 1 module(s): LP_Implant_SwimSpeed_up_1 x1.` on the client, even with the exchange halted by a fault.
  - Not yet seen: an owed delivery logging `The host delivered …` on the client, and the `debug` off case.
- **1.3-G unconfirmed path and the uninstall: pass, after a finding.**
  - **Taking the mod out of the server's `ActiveModList`** made the loader set `LootablePassives : 0` in `mods.txt` and delete the data files, leaving empty folders. PalSchema then printed `Loading mod: LootablePassives` with no rows after it, which was first misread as the data half still loading.
  - **The server crashed on every join without the mod,** both with that loader removal and with the mod's installed folders deleted by hand: `EXCEPTION_ACCESS_VIOLATION reading 0x68` on the game thread, the same stack each time, about 6 s after the client entered the world. The world itself loaded. No Lua of this mod ran on the server, and the client sends the server nothing at join. Cause: the joining player's save held `LP_Implant_*` items unknown to a server without the mod's data. PalSchema warns at every start that it cannot find `FPalPlayerRecordDataRepInfoArrayThreadSafe_IntVal::ApplyDataMap` and so cannot clean invalid items from player data. Logs: `.docs\accept2-server-e-datahalf-crash.log`, `accept2-server-f-nomod-crash.log`, `accept2-crash-datahalf.log`.
  - **Control:** with the mod back on the server, the same join worked.
  - **The cleanup, then the uninstall:** the cleanup removed 20 implants (17 in inventories, 3 in chests, 12 stacks) in about 22 s and cleared itself; the server autosaved after it. With the mod then removed from the server, the same player joined without a crash. **The uninstall needs the cleanup first;** the Workshop text's Uninstalling section now says so, and asks for every player holding implants to be online during the removal (whether an offline player's inventory is reached was not tested).
  - **The client on an unmodded host:** no host message; on opening the Surgery list, 7 entries hidden (`unconfirmed`) and the notice "this world's host has not confirmed it runs this mod (1.3.0 or later), so its Surgery operations are hidden." The game's own operations worked as vanilla: the consumable implants were free to insert, and the server log stayed clean.
  - **Known issue, added to the Workshop text:** the client lists the mod's repriced vanilla operations, but the unmodded host charges the game's prices: Ferocious's recipe operation was listed at 5,000 and cost 50,000.
  - **The test world is now unmodded on the server** and cleaned of the mod's implants; the developer plans to restore from the backup.
- **1.3-A recovery at boot: pass.** Two Extract Ones halted at `granted/marker`, Pal A kept in the party and Pal B moved to the base as a worker. The server restart (with 1.2.11 installed over the journal) logged `Recovered interrupted exchange of … (marker/granted) after entering the world.` for both, 5 s after the world loaded and before anyone joined, and deleted the journal. On joining, both Pals had an empty slot and no marker, and the modules were in the inventory. **A dedicated server loads offline players' party Pals with the world,** so recovery at world entry reaches them and no join-time pass is needed.
- **Left on the test world:** one Pal with an `LP_ExtractOne` marker and a `granted/marker` row, from the 1.2.11 grant check; the next server start recovers it.
- `faults.lua` is back to `return {}` from 1.2.12.
- **Extract All grant report: pass.** One `grant now` text listing all four modules, logged on the client as `The host granted you 4 module(s): …`.
- **Finding: Better Mod Manager showed Debug logging OFF in a dev build running with `debug = true`.** `debug` was registered with the shipped default (false) and left out of the startup hand-off, so BMM showed its default. **Fixed in 1.2.13:** `debug` is registered with the build's own `config.lua` value as its default (`registered_defaults` in `lp/options.lua`), so BMM shows a dev build's debug as on and a release's as off, and saves only a change the player makes; `reconcile` no longer special-cases it. `options_test` checks the registered default and that a saved `debug = false` wins over a dev build's `true`.
- **Added in 1.2.14 (developer's request): setting changes as DEBUG lines, relayed from the host.**
  - `options.change` logs `DEBUG: Setting <name> is now <value>.` only when `debug` is on before or after the change; it was an info line on every machine.
  - `host.tell_setting(name, value)`, an `on_changed` listener in `main.lua`, sends `LootablePassives setting <name>=<value>` to every remote controller while the host's `debug` is on. A client logs `DEBUG: The host's setting <name> is now <value>.` only when its own `debug` is on. So a client sees the host's changes only with both on, and its own changes with its own on.
  - `host_test` checks the text's round trip.
- **1.2.14 run, both machines restarted: pass.**
  - The server start recovered the 1.2.11 grant-check Pal (`Recovered interrupted exchange of SwimSpeed_up_1`).
  - BMM showed Debug logging ON in the dev build.
  - **Host change, both debug on:** server `DEBUG: Setting surgery_ui_gate is now false.`, client `DEBUG: The host's setting surgery_ui_gate is now false.`
  - **Client changes in BMM:** `DEBUG:` lines for Surgery button check off and on, and for `debug` off. `ModConfig.LootablePassives.lua` then held only `{["debug"]=false}`, and the installed `config.lua` read `debug = false`.
  - **Host change, client debug off:** sent by the server, nothing logged on the client.
  - **Host debug off:** logged on the server and not relayed, since the host's debug is off once it applies.
- **1.3-E release logging: pass.** With `debug` off on both machines, one Extract One logged exactly one line on each: server `Extracted PAL_sadist into LP_Implant_PAL_sadist for player 256 (server snapshot).`, client `Surgery LP_ExtractOne finished; the Pal now has [].` No grant report line on the client.

### 1.3-I. Docs: Workshop text, README and CLAUDE.md

1. **`workshop-description.txt`:**
   - Replace "reported NOT TO WORK ON DEDICATED SERVER HOSTING" with "tested and working on a Windows dedicated server", naming the game build.
   - Add the dedicated-server steps (draft below).
   - Describe the BMM settings, including the host-only cleanup and what `surgery_extraction` off does and does not cover.
   - Remove the "Edit button coloring is wonky for clients" known issue if 1.3-G or 1.3-E fixes it; otherwise keep it.
   - Use the paldeck terminology: "Pal Surgery Table", "Disposable Implant".
2. **`README.md`:** the same server steps in Markdown, the new settings files, BMM support, the cleanup action, and a dev section on the local PalServer rig (shared `WorkshopRootDir`, server log path, world move and UID swap).
3. **`CLAUDE.md`:**
   - Update the settings paths (`config.lua`, `lp/options.lua`) and the `passive_items.lua` path.
   - Add the server log path to "Read `UE4SS.log`".
   - Note that the shared `WorkshopRootDir` makes `stage.ps1` feed the local server.
   - Record the `+ModsFolderPaths` exception if it is adopted.
   - Update the startup-counts paragraph, which names `Scripts/passive_items.lua`.
4. **Changelog entry for 1.3.0.**

#### Draft: dedicated-server steps for the Workshop text

To be turned into BBCode at execution. Every step was verified on the dev rig on 2026-10-18.

1. **Install the server.** Windows only: in Steam, open Library → Tools → **Palworld Dedicated Server** and install it.
2. **Get the three mods.** Subscribe to UE4SS Experimental (Palworld), PalSchema and Lootable Passives in Steam, so Steam downloads them to `...\steamapps\workshop\content\1623730\`.
3. **Start the server once,** then stop it. This creates `PalServer\Mods\PalModSettings.ini`.
4. **Edit `PalServer\Mods\PalModSettings.ini`** with the server stopped:

   ```ini
   [PalModSettings]
   bGlobalEnableMod=True
   WorkshopRootDir=C:\Program Files (x86)\Steam\steamapps\workshop\content\1623730
   ActiveModList=UE4SSExperimentalPW
   ActiveModList=PalSchema
   ActiveModList=LootablePassives
   ```

   - **Write one `ActiveModList` line per mod,** using these exact names.
   - **`WorkshopRootDir` is the folder where Steam put the subscriptions.** As an alternative, copy the three numbered mod folders into `PalServer\Mods\Workshop\` and leave `WorkshopRootDir` empty.
5. **Restart the server.** It installs the mods at launch. Check that `PalServer\Mods\ManagedMods\` holds `UE4SSExperimentalPW`, `PalSchema` and `LootablePassives`, and that `PalServer\Mods\NativeMods\UE4SS\UE4SS.log` contains `Loaded 115 extractable passives`.
6. **Keep `bAllowClientMod` on** in the server's world settings. It is on by default. Players install Lootable Passives and its two requirements in their own game.
7. **After a mod update,** restart the server so it installs the new version.
8. **Settings without Better Mod Manager, including on a dedicated server.** Document every setting, and the manual removal of the mod's items, as edits to `config.lua` (round 6):
   - The file is `...\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\config.lua`, under the game folder or the `PalServer` folder.
   - Edit it with the game or server stopped, then start it.
   - **Manual removal:** set `experimental_features = true` and `remove_mod_items = true`, then enter the world, or start the server. The mod removes its items and logs the result.
   - **A mod update reinstalls `config.lua` and restores the defaults.** Re-apply any edits after updating. State this plainly in the Workshop text and the README as a known behaviour: settings persist within a version and reset on update. With Better Mod Manager, its saved values carry over.
   - **Changes made in Better Mod Manager are saved into the same `config.lua`,** so the file always shows the current settings.

#### 1.3-I status: done, pending acceptance

- **`workshop-description.txt`:**
  - Added "every player should run the same version", the client hiding and join delivery. "Reported NOT TO WORK ON DEDICATED SERVER HOSTING" stayed until the dedicated-server acceptance finished, and was then replaced (2026-10-19).
  - New sections: the dedicated-server install steps (as drafted, BBCode); "Settings" (every setting, BMM or `config.lua`, the reset on update stated plainly); "Removing this mod's items from the world (experimental, host only)", including the manual `config.lua` route.
  - BMM is listed as optional; "Pal Surgery Table" and "Disposable Implant" are used throughout; the 1.3.0 changelog is added.
- **The Edit-button coloring known issue is kept:** nothing in 1.3.0 is verified to fix it.
- **`README.md`:** player-facing text stays only in the Workshop file (its stated single point of change, round 2), so the server steps are not copied. Added:
  - "Testing on a local dedicated server": the shared `WorkshopRootDir`, `ActiveModList` filtering, the server log, the world move and UID swap;
  - the role line and the release log's contents in "Reading the log";
  - the runtime-write exception in "How a staged build reaches the game";
  - the settings section and the test listings (1.3-F, 1.3-G).
- **`CLAUDE.md`:**
  - a new "Roles and the two halves" section;
  - the shared-`WorkshopRootDir` bullet;
  - the settings section, the layout and tests, and the `passive_items.lua` paths (1.3-F);
  - the stale `.docs/workshop-description.txt` paths fixed.

  The `+ModsFolderPaths` exception was not adopted, so it is not recorded.
- **`tools/stage.ps1`'s closing message** names `workshop-description.txt` at the root. `test_staging.ps1`: all pass.
- **The changelog entry** is in the Workshop text.

### 1.3-J. Optional dev tooling

- The FModel-export read-only data verifier.
- Generated Lua types (`Mods\shared\types`) for `.luarc.json`.

Not started; neither is needed for 1.3.0. The offline tests added in 1.3-C to 1.3-H cover the Lua that has no engine call: `journal_test`, `exchange_test`, `options_test`, `host_test`, and `ledger_test`'s new cases.

### 1.3-K. Release

1. **Docs cleanup, after the code is complete and general testing has run** (round 10), so rework found in testing does not churn the docs:
   - In `workshop-description.txt`, replace "It is reported NOT TO WORK ON DEDICATED SERVER HOSTING" with "Tested and working on a Windows dedicated server (game version …)", and the changelog's "Added the dedicated-server install steps" with "Tested and working on a Windows dedicated server; added the install steps".
   - Re-read the Workshop text, `README.md` and `CLAUDE.md` against what testing changed.
2. **Checks:**
   - `node tools\luacheck.js`
   - `luacheck Scripts`, with 0 warnings
   - `lua tools\ledger_test.lua`
   - a dev stage with `-Force`, because files are moved and deleted.
3. **The test matrix below,** with the logs of both machines for every cell.
4. **`.\tools\stage.ps1 -Minor` produces 1.3.0** and redraws the thumbnail. Upload by hand, and paste the Workshop text.
5. **Delete this plan file before publishing.** The probe module is already deleted.

### Test matrix

| Case | Extract One / Extract All / alias implant / direct implant | Conveyor | Ledger delivery | Client gating | BMM |
| --- | --- | --- | --- | --- | --- |
| Single player | ✔ | ✔ | ✔ | n/a | live toggles, cleanup through BMM and through `config.lua` |
| Listen host with mod, client with mod | both operate | ✔ | the client gets the items | confirmed | host cleanup; the client's cleanup is disabled |
| Listen host without mod, client with mod | client blocked before the charge, with a message | n/a | n/a | unconfirmed | — |
| Listen host with mod, client without mod | host ✔ | ✔ | blank items for the client | n/a | — |
| Host `surgery_extraction` off | every mod-added operation (extract, alias, direct) is blocked on both; vanilla operations still work | ✔ | ✔ | follows the host | toggled live on the host |
| Dedicated server with mod, client with mod | ✔ | ✔ | delivered on join | confirmed | cleanup through the server's `config.lua` |
| Dedicated server without mod, client with mod | client blocked before the charge, with a message | n/a | n/a | unconfirmed | — |
| Two players operating at once (listen and dedicated) | each gets the right implant | ✔ | ✔ | — | — |

## Open questions

### Decisions from the developer, round 1 (2026-10-18)

1. **Sequencing.** Everything goes into the next release, which is now 1.3.0 (rounds 3 and 5): the server install docs, the lost-implant fix, and the rest. There is no 1.2.x hotfix. 1.3-0 confirms both diagnoses first.
2. **Surgery toggle: yes, decided on the authoritative side.** Add a `surgery_extraction` setting.
   - **Where it counts.** It is meaningful only where the world is authoritative: single player, the listen host, or the dedicated server. Off there means the server grants nothing for LP operations **and** refuses to let clients perform them.
   - **On a client the local value has no purpose.** The mod may still be live on the server. The client follows the host's value, which reaches it with the handshake (1.3-G).
   - **Grants are never blocked on the receiving side.** An item the server delivers (for example a ledger debt from an earlier session) is accepted whatever the client's settings say. An unwanted item can be discarded.
   - **Settings that differ between client and host are handled gracefully.** At minimum, a log warning names the setting and both values when a blocked operation is attempted. The client's gate should refuse beforehand, so no gold is spent on an operation the server will undo.
   - **Open design point.** A server-side refusal happens after vanilla has charged the gold and swapped the marker in, so the server has to restore the passive. Refunding the gold is not possible today. That makes the client-side pre-block the real user-facing control, and the server-side refusal the backstop.
3. **Dev loop.** The `+ModsFolderPaths` override in `UE4SS-settings.ini` is allowed as a documented dev-only exception to the "only the loader writes game folders" rule. Fix the `UE4SS_ROOT` fallback in `lp/util.lua` first, and record the exception in `CLAUDE.md` when it is adopted.
4. **Conveyor recipient.** Keep the original catcher (`OwnerPlayerUId`). In co-op the world belongs to the host, so this is stable. Check that the same keying holds on a dedicated server: player ids may need rewiring once that is supported explicitly. **Constraint: one code path and one ledger serve both co-op and dedicated server.** Two product baselines to test after every change is not acceptable.

### Decisions from the developer, round 2 (2026-10-18)

1. **`workshop-description.txt` lives at the repo root.** It is the single point of change, and `README.md` links to it there. The developer fixed the stale references in `CLAUDE.md` and `README.md`.
2. **Compatibility is checked before the operation, never at or after it.** "Refuse on the server and restore the passive" is the wrong place for a client/server compatibility check, because vanilla has already charged the gold.
   - **The client learns at runtime whether the server accepts LP operations:** the host has the mod, and its `surgery_extraction` is on.
   - **When it does not, the client stops the operation from starting.** In order of preference:
     - (a) The LP operations are left out of the Surgery passive list.
     - (b) The Edit button cannot be pressed.
   - **The server-side refusal stays only as a backstop** for a client without the gate, for example `surgery_ui_gate` off or an old version. It is not a feature.
3. **The Jormuntide crash is in scope,** provided it can be reproduced. The developer has several Jormuntides.

#### Hiding LP operations from the list (lead for 1.3-G, unverified)

`CXXHeaderDump\WBP_OperatingTable_ItemList.hpp` and `WBP_OperatingTable.hpp` show these points:

- **`UWBP_OperatingTable_ItemList_C::Setup(FName PassiveId, bool& IsValid)`.** It sets up one list entry and reports whether it is valid through an out-parameter. Two candidates follow from it:
  - A Blueprint hook that runs after the function and writes `IsValid = false` for LP ids, if vanilla skips entries reported invalid. Writing an out-parameter from a hook is unverified.
  - After `Setup`, collapse the entry widget with `SetVisibility`.
- **`UWBP_OperatingTable_C::SetupPassiveChangeItem()`.** It builds the list. After it runs, walk `WBP_PalCommonScrollList_Item` and collapse each entry whose `PassiveId` is an LP id.
- **The fallback is option (b), the existing Edit-button gate.** That mechanism already exists (`lp/ui.lua`), and the change is to also block when the host is unconfirmed.
- **Probe in 1.3-0 with Live View** before writing code: collapse one entry by hand and see whether scrolling and focus stay correct.

#### Jormuntide crash repro

The report, from Zalakiaa on 2026-10-06, predates 1.2.0, so it may already be fixed.

- **The passive is "Lord of the Sea"** (Water attack damage +30%), exclusive to Jormuntide. It is `ElementBoost_Aqua_2_PAL`, which the mod supports by design: its module is `LP_Implant_ElementBoost_Aqua_2_PAL` in `items/LootablePassivesImplants.json`.
- **Closed 2026-10-18: not reproducible on 1.2.0.** On the developer's hosted world, a release build:
  - "Lord of the Sea" was extracted from a Jormuntide and implanted into a Mimog.
  - The game was fully closed and relaunched, and the passive was still on the Mimog.
- **Evidence:**
  - No crash folder in `%LOCALAPPDATA%\Pal\Saved\Crashes\` is newer than 2026-09-20.
  - The relaunch's `UE4SS.log` is clean apart from the known PalSchema signature errors.
  - The log of the extraction session itself was overwritten by the relaunch, and a release build logs no per-exchange lines anyway.
- **Treat it as fixed or not repeatable.** Reopen only on a new report with a log.

### Technical, answered by the 1.3-0 probes

1. Does the server's loader write `mods.txt` for Lua packages? Where is the server's `UE4SS.log`?
2. Does `WorkshopRootDir` on the server load every `IsServer` mod in that folder, or only the `ActiveModList` ones?
3. What strings does `UPalUtility::GetNetMode` return? What does `IsClientDedicatedServer` return?
4. Does server Lua calling `SendLog_ToClient` reach a client-side hook? Does the sentinel produce a visible log line?
5. What does a vanilla host do when a modded client requests an LP operation: refuse, install the marker, or something else?
6. How does `MinRevision` interact with the server's build revision?
7. Do the post-callbacks on the conveyor `_ServerInternal` hooks show the post-tick queue?
