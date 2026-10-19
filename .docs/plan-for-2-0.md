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

### Decisions, rounds 4 to 6 (2026-10-18)

1. **Conveyor post-callbacks are in,** with a probe first and an in-game check (1.3-B).
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

### 1.3-B. Hook mechanics and small fixes

1. **`hooks.register` takes an optional post-callback.** It keeps the `PreId`/`PostId` that `RegisterHook` returns, and gets an `unregister`.
2. **Conveyor post-callbacks.** Both conveyor `/Script/` hooks are registered with a no-op pre-callback and the real callback as post.
   - **Remove the `STEP_MARGIN` projection only once the probe shows** that the post-callback sees the finished entry, or its removal.
   - **Verify:** one Pal and a queue of three, in single player and on the dedicated server. Count the "Disassembly yielded" lines against the Pals fed in: no misses, no doubles.
3. **`conveyor_extraction` turned off unregisters the conveyor hooks.** Turned on, it installs them at once (needed by 1.3-F).
4. **Arm the widget hooks with `NotifyOnNewObject`** on the widget classes, in place of 90 × 1 s polling per map load. Follow the wiki's caution on Blueprint classes: register it after the player controller is up, for example on `ClientRestart`. Merge the handlers per class, since UE4SS allows one registration per class.
5. **Small correctness fixes:**
   - `util.name_to_string` returns nil instead of falling back to `tostring()` (`lp/util.lua:130`).
   - `operation_result_code` no longer parses userdata with `tostring` (`lp/inventory.lua:144`).
   - The `main.lua:90-94` comment on Blueprint hook timing is corrected to what the probe shows.
   - **The two LuaLS diagnostics open in the editor,** which `luacheck` does not report: `param-type-mismatch` (a `table|nil` passed as `table`) at `lp/ui.lua:447`, and an unused local `_handle` at `main.lua:121`. Fix them, or annotate them if they are false positives.

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

### 1.3-D. Ledger delivery

1. **Flush when a player joins,** using the trigger the probe picked, on the server half.
2. **Conveyor debts stay owed to the original catcher** (round 1, decision 4). Verify on the dedicated server that the Pal's `OwnerPlayerUId` and the PlayerState's `PlayerUId` agree, using the already-swapped world.
3. **Keep one ledger format** for co-op and dedicated server.
4. **Verify:** a debt owed to a player who is offline is delivered when they join, with no conveyor activity needed.

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
2. **Drop the "hidden cards" field, or reword it.**
3. **Measure:** one Extract One on a release build logs one line on the server and one on the client. Count the lines in the log.

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

### 1.3-G. Host-has-mod handshake and the client pre-block

1. **The server half sends a sentinel to each player on join,** by the route the probe confirms. The leading candidate is `SendLog_ToClient` with a reserved `TextId`.
   - **The payload carries the host's authoritative settings** (`surgery_extraction`, `conveyor_extraction`). With an FName `TextId`, encode the combinations as distinct sentinels.
   - **It is sent again when a setting changes at runtime** through BMM on the host.
2. **The client half records "host confirmed"** and the host's settings. They are reset on each map load, which is when the client joins or leaves a world.
3. **Until the host is confirmed, or while the host's `surgery_extraction` is off, the client stops the covered operations before they start.**
   - **Preferred:** the LP operations are left out of the Surgery list (the `WBP_OperatingTable_ItemList_C` / `SetupPassiveChangeItem` lead in "Hiding LP operations from the list").
   - **Fallback:** the Edit button is blocked by the existing gate.
   - **Either way, the player sees why,** as a message, not a silent no-op.
4. **On single player and the listen host,** the role is authoritative and the gate reads the local value directly. No handshake is needed.
5. **No fallback is planned** (decision 7). If the probe finds no route from server Lua to a client hook, stop and replan with the developer before any other 1.3-G work.
6. **Verify:** a modded client on a vanilla listen host, and on a dedicated server without the mod, sees no usable LP operations and gets the message. A modded client on a modded host whose `surgery_extraction` is off is blocked the same way. It is unblocked live when the host turns the setting back on.

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

### 1.3-J. Optional dev tooling

- The FModel-export read-only data verifier.
- Generated Lua types (`Mods\shared\types`) for `.luarc.json`.

### 1.3-K. Release

1. **Checks:**
   - `node tools\luacheck.js`
   - `luacheck Scripts`, with 0 warnings
   - `lua tools\ledger_test.lua`
   - a dev stage with `-Force`, because files are moved and deleted.
2. **The test matrix below,** with the logs of both machines for every cell.
3. **`.\tools\stage.ps1 -Minor` produces 1.3.0** and redraws the thumbnail. Upload by hand, and paste the Workshop text.
4. **Delete this plan file before publishing.**

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
