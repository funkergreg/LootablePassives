# Changelog

Changelog moved here as of `1.3.0` to reduce length of mod description copy-pasted into the mod's Steam Workshop setup directly; already covered by mod uploader and separate tab anyway.

## 1.3.0

- **A clean uninstall, tested and documented.** Uninstalling now has step-by-step procedures for a dedicated server and for single player or co-op. Both start with the new **Remove all mod items** setting, which clears this mod's Disposable Implants from the world. It is required before uninstalling: once the mod is gone, a player still carrying its implants crashes a dedicated server as they join.
- **Better client-server interaction and safety.**
- The host tells each player whether it runs this mod and with which settings. A player's game hides the operations the host would refuse, so no gold is spent on them.
- Implants owed to a player (a rare edge case) are delivered when they join, and an interrupted operation is repaired when the server starts.
- Fixed a passive being lost without its implant when two players used the Pal Surgery Table at the same time.
- A player's own UE4SS.log records the implants the host delivered to them on joining, and, in debug mode, every implant the host grants them.
- **Tested on a Windows dedicated server,** with install steps in this description.
- **Better Mod Manager support:** this mod's settings appear on its Mods tab and take effect while the game runs.
- New setting, **Surgery extraction**: the host can turn off every operation this mod adds to the Pal Surgery Table, for every player.
- More reliable implant delivery from the Pal Disassembly Conveyor.
- Much quieter UE4SS.log outside debug mode, with the detail moved into debug mode.

## 1.2.0

- Fixed a likely cause of a crash when leaving a world, such as exiting to the title screen: the mod's delayed work now always runs on the game thread.
- Fixed passives appearing twice in the Palbox search and sort list.
- The Surgery Table's passive list now shows each passive's own description for the disposable-implant entries, instead of placeholder text.
- Added runtime checking and safety for settings, and an explicit debug mode setting.
- Miscellaneous fixes, mostly for possible lost item grants.

## 1.1.0

- Initial public release.
