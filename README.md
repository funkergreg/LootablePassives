# Lootable Passives

This is the Lootable Passives Palworld mod's development repository. General users NOT doing development will install the mod from the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3805554239); see [Mod Development](#mod-development) for working from source in this repo, which reaches the game through the mod's Workshop item folder, the same way a subscriber's copy does.

## Mod Development

This repository is the mod's source, not the shipped mod. The mod is distributed through the Steam Workshop as a subset of these files, marked in the layout below; this README is not part of it.

### Dev Prerequisites

- Windows with PowerShell 7
- Palworld from Steam, at the default location or anywhere you pass with `-GameRoot`
- The two dependencies, [UE4SS Experimental (Palworld)](https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587) and [PalSchema](https://steamcommunity.com/sharedfiles/filedetails/?id=3625280368), subscribed on the Workshop and enabled under **Options → Mod Management**
- **Palworld Mod Uploader**, a free tool in your Steam library, and the mod's Workshop item folder, which its **Create New Mod** makes (see [Starting a mod](#starting-a-mod))
- Node.js, plus `npm install` in the repository root for the `luaparse` package the parse check needs; `package.json` declares it
- Lua 5.5 and luacheck 1.2 on `PATH`; Scoop installs both into your user profile without admin rights

### Repository layout

| Path | Purpose | Ships to the Workshop |
| --- | --- | --- |
| `Scripts\` | Lua runtime: `main.lua`, `settings.lua`, `lp\*.lua` | yes |
| `PalSchemaMods\LootablePassives\` | JSON data patches: items, DataTable rows, English strings | yes |
| `Info.json` | Workshop package manifest | yes |
| `LICENSE`, `thumbnail.png` | Package metadata | yes |
| `README.md` | This page: the development repo's documentation | no |
| `.docs\workshop-description.txt` | The Steam Workshop page text, in Steam's BBCode | no |
| `tools\` | `stage.ps1`, `test_staging.ps1`, `luacheck.js`, `ledger_test.lua` | no |
| `package.json` | Declares `luaparse` for `tools\luacheck.js` | no |
| `.luacheckrc`, `.luarc.json` | Declare UE4SS's injected globals for luacheck and the Lua language server | no |

What ships is decided by `Info.json`, not by a list in the tools: `stage.ps1` stages `Info.json`, the `Thumbnail` file, `LICENSE`, and every `InstallRule` target, and nothing else.

### Starting a mod

The Workshop item folder comes first, and the repository second. Palworld only installs a Workshop mod from a folder under the Workshop content directory, and only Palworld Mod Uploader can make one that can be uploaded. Everything else in this README assumes the folder exists.

1. Subscribe to the dependencies on the machine you will develop on, start Palworld once, and enable them under **Options → Mod Management**. That also writes `<Palworld>\Mods\PalModSettings.ini`, whose `WorkshopRootDir` is the Workshop content directory, usually `C:\Program Files (x86)\Steam\steamapps\workshop\content\1623730`.
2. Start **Palworld Mod Uploader** from your Steam library, and check that **Workshop Content Directory** at the top shows that same directory.
3. Click **Create New Mod** and tick the types the mod uses: **Lua**, **Paks**, **LogicMods**, **PalSchema**. The uploader registers an empty item on the Workshop straight away, makes a folder named with that item's id, and opens it. The folder holds:
   - `Info.json`, a template: `ModName` and `PackageName` both `MyAwesomeMod`, `Version` `1.0.0`, `DebugMode` `false`, a `MinRevision`, `Author` set to your Steam name, empty `Tags` and `Dependencies`, and one `InstallRule` per ticked type.
   - `thumbnail.png`.
   - One folder per ticked type: `Scripts\` (with an example `main.lua`), `Paks\`, `LogicMods\`, `PalSchema\`.
   - `.workshop.json`, the uploader's own file: the Published ID and the last uploaded `Version`.
4. In the uploader, select the folder and set **Package Name**, letters and digits only, then **Save Info.json**. The **Mod Name**, **Package Name**, **Version**, **MinRevision** and **Author** fields are the item folder's `Info.json`; nothing else stores them.
5. Copy that `Info.json` into the repository, together with `tools\stage.ps1` and `tools\test_staging.ps1` from this repository; neither holds anything specific to this mod. Treat the repository's `Info.json` as the only one from then on. `stage.ps1` overwrites the item folder's `Info.json` on every run, so an edit made in the uploader afterwards is lost unless it is made in the repository too. Once `InstallRule` has been edited by hand, as this mod's has, the uploader shows the install types as read-only.
6. Fill in the rest of `Info.json` in the repository:
   - `Dependencies`: the `PackageName` of each mod this one needs, read from that mod's own `Info.json` in its numbered Workshop folder. For this mod they are `UE4SSExperimentalPW` and `PalSchema`.
   - `Tags`: only `PalSchema`, `UE4SS`, `Model Replacement`, `Utilities`, `Gameplay`, `User Interface`.
   - `MinRevision`: the lowest game build the mod supports. The uploader's documentation defines it as the last five digits of the version Palworld shows in its title; use the build you test on.
   - `InstallRule`: see [How InstallRule targets install](#how-installrule-targets-install). Its `Targets` are also what ships: a folder no target names stays in the repository. Add a copy of each rule with `"IsServer": true` if a dedicated server should install it as well.
7. Preview with `.\tools\stage.ps1 -DryRun`, then stage with `.\tools\stage.ps1`. It finds the item folder by `PackageName`, so step 4 must be done first. The first stage meets the template's files in the item folder:
   - A template file the repository also has, such as `Scripts\main.lua`, is overwritten.
   - A template file the repository does not have stops the stage as stale; `-Force` deletes it.
   - Empty template folders are removed.

   Then enable the mod under **Options → Mod Management** and restart Palworld so the loader installs it.
8. Upload with **Upload To Steam** in the uploader. It asks for change notes. Set visibility (private, friends only, or public), the description and any extra images on the Workshop page itself.

Shift-clicking **Create New Mod** makes a local-only folder with no Published ID. It installs like any other, but it can never be uploaded; to publish, its contents have to move to a folder made by a normal **Create New Mod**. A folder made by a normal **Create New Mod** is a Workshop item from that moment, even before its first upload, and is deleted from its Workshop page.

#### Pitfalls this mod hit

- **Copying files straight into the game folders.** The loader writes the same folders at launch whenever it reinstalls, so a second writer is silently overwritten, or silently wins until the next version change. Nothing but the loader should write them; the repository reaches the game through the item folder.
- **A `Targets` path ending in the package name.** Under `Lua` and `PalSchema` the loader adds a package-name folder itself, so the name appears twice and PalSchema loads an empty folder without an error.
- **Reading the type table in `04-Tech.md` as complete.** It shows the package-name folder for `Lua` only. `PalSchema` gets one too, and `UE4SS` and `LogicMods` do not.
- **Editing `Info.json` in the uploader.** The next stage overwrites it.
- **Subscribing to your own mod on the machine that stages.** Steam downloads it into the same numbered folder, over the staged files, and the uploader makes a subscribed item view-only. Only the second test machine subscribes.
- **Two folders with the same `PackageName`** under the Workshop content directory. The loader enables one of them, and which one is not defined.

### How InstallRule targets install

Each `InstallRule` names a `Type` and a list of `Targets`, paths inside the item folder. Where the files land is recorded in `<Palworld>\Mods\ManagedMods\<PackageName>\InstallManifest.json`, which the loader writes on every install; it is the place to check a layout.

| `Type` | Game directory | Package-name folder added |
| --- | --- | --- |
| `Lua` | `Mods\NativeMods\UE4SS\Mods\` | yes |
| `PalSchema` | `Mods\NativeMods\UE4SS\Mods\PalSchema\mods\` | yes |
| `UE4SS` | `Mods\NativeMods\UE4SS\` | no |
| `LogicMods` | `Pal\Content\Paks\LogicMods\` | no |
| `Paks` | `Pal\Content\Paks\~WorkshopMods\` | not yet recorded |

How a target is copied depends on its last character:

| Target | Copies | Example from an installed mod |
| --- | --- | --- |
| No trailing `/`, as `./Scripts` | the folder, under its own name | `Lua` + `./Scripts` → `Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\` |
| Trailing `/`, as `./LogicMods/` | the folder's contents | `LogicMods` + `./LogicMods/` → `Pal\Content\Paks\LogicMods\YetAnotherMinimap.pak` |
| `.` | the whole item folder's contents | `UE4SS` + `.` → `Mods\NativeMods\UE4SS\UE4SS.dll` |

This mod names the three PalSchema folders individually, without a trailing `/`, so `./PalSchemaMods/LootablePassives/raw` lands at `Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\raw\`. The uploader's template uses `PalSchema\` and `./PalSchema/`, which by the trailing-slash rule copies `items\`, `raw\` and `translations\` straight into `PalSchema\mods\<PackageName>\`. That form is simpler, but no installed mod here has recorded it for the `PalSchema` type yet. Check the manifest after the first install if you use it.

### The edit, check, release loop

There is no build step, and there is no local-only test build. The repository is the working copy, and every change that is tested is uploaded: staged with a new version, uploaded to the Workshop, and played on the host machine and on a second, subscribed machine that joins it in multiplayer. Both machines then run the same version.

```powershell
# edit the JSON under PalSchemaMods\ or the Lua under Scripts\, then:
node tools\luacheck.js          # Lua parse check
luacheck Scripts                # static analysis; the baseline is 0 warnings / 0 errors
lua tools\ledger_test.lua       # after any change to Scripts\lp\ledger.lua
.\tools\test_staging.ps1          # after any change to tools\stage.ps1
.\tools\stage.ps1               # dev build: patch + 1, DebugMode on; add -DryRun to preview
.\tools\stage.ps1 -Publish      # release: minor + 1, patch 0, DebugMode off
# Upload To Steam from Palworld Mod Uploader
# restart Palworld on both machines, check both are on the new version, test, read the log
```

`stage.ps1` writes `Version` and `DebugMode` into the repository's `Info.json` and then stages that file unchanged, so the repository always matches what was last staged:

| Run | `Version` | `DebugMode` | Example |
| --- | --- | --- | --- |
| `.\tools\stage.ps1` | patch + 1 | `true` | `1.1.0` → `1.1.1` |
| `.\tools\stage.ps1 -Publish` | minor + 1, patch `0` | `false` | `1.1.3` → `1.2.0` |

Only a release has patch `0`. Raise the major version by editing `Info.json` by hand; the next stage counts on from there.

1. Preview the stage if you want: add `-DryRun` to either command. It prints the next version and changes nothing.
2. Stage a dev build with `.\tools\stage.ps1`, or a release with `.\tools\stage.ps1 -Publish`. Commit the rewritten `Info.json` with the change it carries.
3. Upload from **Palworld Mod Uploader**, which is software run from Steam. A dev build is uploaded too, so the second machine can download it; it goes out with `DebugMode` on, which makes every subscriber's loader reinstall the mod at each launch until the next release.
4. Restart Palworld on both machines. The host reinstalls from the item folder at launch. The subscribed machine reinstalls once Steam has downloaded the upload. Check the version under **Options → Mod Management** on both before testing together.
5. If the player-facing description changed, paste `.docs\workshop-description.txt` into the Workshop page's description by hand. The uploader does not carry it, and the stage does not include it.

UE4SS hot reload is disabled, and the loader installs only at launch, so a running game does not pick up a change until it restarts.

The mod must be enabled under **Options → Mod Management** for the loader to install it. `stage.ps1` warns when it, or one of its `Dependencies`, is not.

### How a staged build reaches the game

```text
repo  --stage.ps1-->  <Workshop content>\1623730\<item id>\  --loader, at launch-->  <Palworld>\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\
                                                                                     <Palworld>\Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\{items,raw,translations}\
```

- **Finding the item folder.** `stage.ps1` uses the one folder under the Workshop content directory whose `Info.json` has this repository's `PackageName`, and stops if there is none or more than one.
- **What it stages.** `Info.json`, the `Thumbnail` file, `LICENSE`, and every `InstallRule` target, and nothing else. It refuses an `Info.json` the uploader would accept but the game would not install, warns about a target missing from the repository, and prints where each rule installs. It overwrites the item folder's `Info.json` with the repository's, and never touches the uploader's `.workshop.json`.
- **A mirror.** Before copying anything, it compares the item folder with the files about to be staged. A file the stage does not have stops the run with nothing changed. After you delete a file from the repository, run the next stage with `-Force`, which deletes those files and any folder left empty. At the next reinstall the file is in the old manifest and not in the new install; check the game folder the first time you rely on that.
- **When the loader reinstalls.** At launch it compares `Version` in the item folder's `Info.json` with the installed copy in `<Palworld>\Mods\ManagedMods\LootablePassives\`, as plain strings. When they differ, or when `DebugMode` is true, it removes what its `InstallManifest.json` lists and copies the `InstallRule` targets in again. A subscribed machine does the same after Steam downloads an upload. Every stage raises the version, so the first launch after each stage installs it. `stage.ps1` warns if the new version equals the last upload, which a subscribed machine would not reinstall.
- **Stage only when you are going to upload.** The host's next launch installs the staged copy whether or not it was uploaded, and a subscribed machine is then on an older version than the host.
- **Only the loader writes the game folders.** For a `Lua` rule it also adds the `<PackageName> : 1` line to UE4SS's `mods.txt`, which is what starts the Lua half.
- **Turning the mod off.** Use **Options → Mod Management**, which removes both halves. Setting `LootablePassives : 0` in `mods.txt` stops only the Lua half, and the Surgery Table operations stay listed with nothing behind them.

### Reading the log

The log is `UE4SS.log` in the game's UE4SS folder. Filter it on:

- `[LootablePassives]` for the mod's own messages
- `PalSchema` for the data half loading
- `error` and `warning` for anything failing outright

A healthy start logs `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.` That line counts only the Lua tables, and it prints even when the JSON loaded nothing. The data half is confirmed by PalSchema's own lines: `DT_OperatingTablePassiveSkillDataTable: 54 rows updated, 117 rows added, 0 rows deleted, 0 errors` and `DT_PassiveSkill_Main_Common: 0 rows updated, 56 rows added`.

After a crash, look in `%LOCALAPPDATA%\Pal\Saved\Crashes\`.

### The tools

| Command | What it does |
| --- | --- |
| `node tools\luacheck.js` | Parses every Lua file under `Scripts\`. Syntax only. |
| `luacheck Scripts` | Static analysis: undefined globals, unused variables, shadowing. Uses `.luacheckrc`. |
| `lua tools\ledger_test.lua` | Test of the mod: the pending-delivery ledger's file format and who it delivers to, with the engine stubbed out. |
| `.\tools\stage.ps1` | Checks `Info.json`, sets its version and `DebugMode` (dev build by default, release with `-Publish`), then mirrors what `Info.json` names into the Workshop item folder, ready to upload. Takes `-Publish`, `-DryRun`, `-Force`, `-GameRoot` and `-WorkshopRoot`. |
| `.\tools\test_staging.ps1` | Test of `stage.ps1`: runs a copy against throwaway repo, Workshop and game folders in `%TEMP%` and checks versions, checks, item-folder detection, the stale stop, `-Force` and `-DryRun`. Never touches the real game or Workshop folders. `-Keep` leaves the temp folders for inspection. |

The player-facing sections at the top of this README and `.docs\workshop-description.txt` describe the same mod for two audiences, so a change to how the mod plays goes into both.

## Mod description - As in Steam Workshop Description

Pull a passive off a Pal and receive a disposable implant.

Vanilla has disposable implants for a handful of passives. This mod defines disposable implants for **all 115** passives, and gives you two ways to get them.

### Benefit

One of the main criticisms of the game is that late-game breeding to get the pal you want is too slow.  This takes getting the exact passives you want out of the equation and will speed up the process of getting the ultimate Pal!

### At the Surgery Table

Three new operations appear in the passive list, each costing 1000 gold:

- **Extract Passive** — removes the passive you selected and returns one matching disposable implant.
- **Extract All Passives** — removes every passive on the Pal and returns an implant for each; selecting any yields the same result.
- **The passive itself** — one entry per passive for which you have a disposable implant; the operation costs a disposable implant and the 1000 gold operation price.

### At the Pal Disassembly Conveyor

Queue a Pal as you normally would. In addition to the usual loot, you get a disposable implant sent to your inventory for every passive on the Pal — an automatic extract-all, at no gold cost.  Implants that exceed inventory space will drop at the character's feet like world item drops.

### What it does not change

- Extracting a passive that came from a purchased recipe gives you a **single-use implant, never the recipe**. The token economy stays intact.
- Overwriting a passive with any other still destroys the original and yields nothing. That is vanilla's behavior and this mod leaves it in place.
- A Pal still cannot be given a passive it already has; duplication prevention like in vanilla.
- The Surgery Table's existing options are untouched apart from price. Price now follows the operation method: a reusable recipe operation costs 5,000 to implant a passive, inserting a passive via disposable implant is 1,000 — including the disposable implants from vanilla.

### Requirements

- Palworld 1.0, build revision **102999** or newer
- [UE4SS Experimental (Palworld)](https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587) — Workshop id 3625223587
- [PalSchema](https://steamcommunity.com/sharedfiles/filedetails/?id=3625280368) — Workshop id 3625280368

Subscribe to both dependencies as well and enable all three under **Options → Mod Management**.

### Multiplayer

Install it on every player for full functionality. A player without it cannot use the implants, and show as blank entries in shared storage. Tested on two machines with the host modded and the client not: result was stable for both players, extraction and disassembly normal for the host who had the mod.  Has NOT been tested on a client where the host does not have the mod.

Not tested: dedicated-server hosting.

### Known Issues

The Edit button's coloring in the surgery table is wonky after some transactions - specifically for clients; exiting the menu and coming back solves the issues with a UI redraw.

### Mod Install

Subscribe on the Steam Workshop to this mod and to both dependencies above, then start Palworld and enable all three under **Options → Mod Management**. The official loader copies the files in and records what it copied, so the mod manager is also how you turn it off again.

### Uninstalling the Mod

Disable it under **Options → Mod Management** and the loader removes what it installed.

What this mod leaves behind is ordinary: passives already implanted are real passives and stay on the Pal, and disposable implants still in an inventory refer to items that no longer exist.

Two things worth knowing first, both general to Palworld modding rather than specific to this mod. Pocketpair's guidance is that turning a mod off is not always enough and that files left in the game folder can still be loaded — if you have ever installed mods by hand, delete those with File Explorer and verify your game files through Steam. And a save that has been loaded with mods enabled can keep showing problems afterwards, so back up a save you care about before experimenting.

## Credits

- Thanks to the authors of **UE4SS** and **PalSchema**, without which none of this is possible.
- Inspired by *Surgery Table Passive Extractor - Lucky & Legend* (Workshop id `3786582350`), which showed an outline of extracting passives through the Surgery Table.
- Not affiliated with or endorsed by Pocketpair. See [LICENSE](LICENSE).
