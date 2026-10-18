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
