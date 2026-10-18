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
- **The Workshop description file is at the repo root.** `workshop-description.txt` is tracked there, not at `.docs/workshop-description.txt` as `CLAUDE.md` says. Fix one or the other during 2.0.

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

A LogicMods `.pak` with a `ModActor` can give Lua callable Blueprint functions ([blueprints-with-lua](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/blueprints-with-lua)). It costs the Modding Kit and a cooking pipeline. The wiki says nothing about replication, and a locally spawned ModActor is not an owned, replicated actor, so it gives **no client-server channel** [INFERENCE]. **Not worth it for 2.0.**

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
- **Recommendation: BMM only for 2.0.**

### Current architecture: facts that matter for 2.0

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

## Draft plan for 2.0

This draft is for iteration and is not approved. The order is the proposed execution order. Each workstream is meant to be stageable and testable by itself.

### W0. Test rig and probes, first

1. **Bring up the local dedicated server.**
   - Launch PalServer once.
   - Point `WorkshopRootDir` at the Workshop content folder.
   - Add the three `ActiveModList` lines.
   - Confirm in the server's `UE4SS.log` that today's 1.2.x build loads, both PalSchema and Lua halves. This reproduces or rules out Kamigouki's report as a setup problem.
2. **Add debug-only console commands to the mod:** `lp.netmode`, `lp.passives`, `lp.ledger`, `lp.journal`, `lp.flush`. Use the GUI console on the client; the server console needs checking.
3. **Probe in one session, on the listen host, a client and the dedicated server:**
   - the return values of the net-mode calls, including the `GetNetMode` strings;
   - whether `/Script/` post-callbacks give the conveyor's post-tick state;
   - whether Blueprint callbacks run after the function;
   - whether `SendLog_ToClient` from server Lua reaches the client's hook.

### W1. Role detection and module split

- **Add an `lp/role.lua`** that computes `standalone`, `listen_host`, `dedicated` or `client` from a world-context `IsServer`/`IsDedicatedServer`, not from a player character. Expose `is_authority()` and `has_ui()`.
- **`main.lua` registers only what the role needs.**
  - The server half (H1, the conveyor, recovery, the ledger) registers on any authority.
  - The UI half (the gate, panel repair, the local-exchange poll) registers on any machine with UI.
  - A listen host gets both, a dedicated server only the first, a client only the second.
- **Break the `transaction` → `ui` dependency.** The listen host's own-click capture becomes something the UI half hands over, not something the server half reaches for.
- **Replace the `PalPlayerCharacter` authority probe** in recovery and the ledger flush.

### W2. Hook mechanics

- **Post-callbacks for the conveyor hooks.** Then remove the rate projection if the probe confirms it is no longer needed.
- **`NotifyOnNewObject` arming for the widget hooks,** replacing the 90 × 1 s polling.
- **Keep the hook ids,** and unregister the conveyor hooks when the setting turns off.
- **Fix `name_to_string` and `operation_result_code`.**

### W3. Exchange correctness under concurrency, the "lost implant" bug

- **Per-request records keyed by `RequestPlayerId`,** not one `pending_record`.
- **Journal rows keyed per exchange (owner UID and Pal `IndividualId`),** not one global row. Recovery then targets a known Pal instead of "the only Pal carrying the marker".
- **A resolve that diffs only Pals carrying the marker,** so another player's unrelated change does not refuse this one.
- **Replace `snapshot_all` with a `NotifyOnNewObject` parameter registry,** or a marker-scoped search, if the probe shows the walk is costly.
- **Re-read Awfulhorrid's symptom against this list.** If a cause is found, a fix may be worth a 1.2.x patch ahead of 2.0.

### W4. Ledger delivery

- **Flush when a player joins:** `K2_PostLogin`, or the PlayerState world-partition-complete server function.
- **Conveyor debts stay owed to the original catcher** (decision 4). Verify that `OwnerPlayerUId` and the PlayerState `PlayerUId` agree on a dedicated server, where player ids may be keyed differently. Keep one ledger format for co-op and dedicated server.

### W5. Host-has-mod handshake (client)

- **The server half sends the sentinel to each player on join.** The client half records "host confirmed".
- **Until the host is confirmed, the client's gate refuses LP operations.** The refusal reads as a message, not a silent no-op.
- **Depends on the W0 probe.** If no RPC route works, fall back to messaging only: the gate shows "this host may not have Lootable Passives" for LP rows on a client.
- **The handshake also carries the host's authoritative settings** (decision 2): at least `surgery_extraction` and `conveyor_extraction`. The client's gate follows the host's `surgery_extraction`. If the sentinel is an FName `TextId`, encode those values as distinct sentinels.

### W6. Settings restructure and BMM

As in the "Proposed restructure" subsection above: `Scripts/config.lua`, a renamed internal accessor, `debug_faults` moved, `passive_items.lua` moved to `lp/`, BMM registration with short text, and no `enabledKey`.

- **Add `surgery_extraction`** (decision 2). It is honoured on the authoritative side. It also has to work when `surgery_ui_gate` is off: the server-side refusal is then the only control, and it costs the player the gold.
- **Mark the host-controlled settings in their BMM descriptions** ("Host only", or "Set by the host in multiplayer"), so a client player isn't misled by a toggle that changes nothing on their machine.

### W7. Docs and packaging

- **`README.md` and the Workshop text get the following:**
  - A dedicated-server install section: the server needs UE4SSExperimentalPW, PalSchema and LootablePassives in its own `Mods\Workshop\` (or `WorkshopRootDir`) plus `ActiveModList`.
  - What clients need.
  - Windows only.
  - `bAllowClientMod` must be true.
- **Remove "reported NOT TO WORK ON DEDICATED SERVER HOSTING"** once it is tested.
- **Fix the `workshop-description.txt` path** in `CLAUDE.md`, or move the file.
- **Use the paldeck terminology** ("Pal Surgery Table", "Disposable Implant").

### W8. Optional dev tooling

- The FModel-export read-only data verifier.
- The `+ModsFolderPaths` Lua override, approved as a dev-only exception (decision 3). Move it into W0 if the `UE4SS_ROOT` fix is cheap, since it speeds up every later workstream.
- Generated Lua types.

### Test matrix

Every cell needs both the host's and the client's log.

| Case | Surgery: Extract One / Extract All / implant | Conveyor | Ledger delivery | Client gating |
| --- | --- | --- | --- | --- |
| Single player | ✔ | ✔ | ✔ | n/a |
| Listen host with mod, client with mod | host and client both operate | ✔ | the client gets the items | confirmed |
| Listen host without mod, client with mod | client blocked, with a message | n/a | n/a | unconfirmed |
| Listen host with mod, client without mod | host ✔ | ✔ | blank items for the client | n/a |
| Dedicated server with mod, client with mod | ✔ | ✔ | delivered on join | confirmed |
| Dedicated server without mod, client with mod | client blocked, with a message | n/a | n/a | unconfirmed |
| Two players operating at once (listen and dedicated) | both get the right implant | ✔ | ✔ | — |

## Open questions

### Decisions from the developer, round 1 (2026-10-18)

1. **Sequencing.** Everything goes into 2.0: the server install docs, the lost-implant fix, and the rest. There is no 1.2.x hotfix. W0 confirms both diagnoses first.
2. **Surgery toggle: yes, decided on the authoritative side.** Add a `surgery_extraction` setting.
   - **Where it counts.** It is meaningful only where the world is authoritative: single player, the listen host, or the dedicated server. Off there means the server grants nothing for LP operations **and** refuses to let clients perform them.
   - **On a client the local value has no purpose.** The mod may still be live on the server. The client follows the host's value, which reaches it with the W5 handshake.
   - **Grants are never blocked on the receiving side.** An item the server delivers (for example a ledger debt from an earlier session) is accepted whatever the client's settings say. An unwanted item can be discarded.
   - **Settings that differ between client and host are handled gracefully.** At minimum, a log warning names the setting and both values when a blocked operation is attempted. The client's gate should refuse beforehand, so no gold is spent on an operation the server will undo.
   - **Open design point.** A server-side refusal happens after vanilla has charged the gold and swapped the marker in, so the server has to restore the passive. Refunding the gold is not possible today. That makes the client-side pre-block the real user-facing control, and the server-side refusal the backstop.
3. **Dev loop.** The `+ModsFolderPaths` override in `UE4SS-settings.ini` is allowed as a documented dev-only exception to the "only the loader writes game folders" rule. Fix the `UE4SS_ROOT` fallback in `lp/util.lua` first, and record the exception in `CLAUDE.md` when it is adopted.
4. **Conveyor recipient.** Keep the original catcher (`OwnerPlayerUId`). In co-op the world belongs to the host, so this is stable. Check that the same keying holds on a dedicated server: player ids may need rewiring once that is supported explicitly. **Constraint: one code path and one ledger serve both co-op and dedicated server.** Two product baselines to test after every change is not acceptable.

### Technical, answered by the W0 probes

1. Does the server's loader write `mods.txt` for Lua packages? Where is the server's `UE4SS.log`?
2. Does `WorkshopRootDir` on the server load every `IsServer` mod in that folder, or only the `ActiveModList` ones?
3. What strings does `UPalUtility::GetNetMode` return? What does `IsClientDedicatedServer` return?
4. Does server Lua calling `SendLog_ToClient` reach a client-side hook? Does the sentinel produce a visible log line?
5. What does a vanilla host do when a modded client requests an LP operation: refuse, install the marker, or something else?
6. How does `MinRevision` interact with the server's build revision?
7. Do the post-callbacks on the conveyor `_ServerInternal` hooks show the post-tick queue?
