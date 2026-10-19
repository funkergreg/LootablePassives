# Lootable Passives

This is the Lootable Passives Palworld mod's development repository. General users NOT doing development will install the mod from the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3805554239); see [Mod Development](#mod-development) for working from source in this repo, which reaches the game through the mod's Workshop item folder, the same way a subscriber's copy does.

## Mod description

The mod description is uploaded manually to Steam from [workshop-description.txt](workshop-description.txt) as the Steam Workshop Description; all user-facing mod description is maintained there (not in this README.md) for single-point-of-change (shall not be copied into this README.md or any other document).

## Mod Development

This repository is the mod's source, not the shipped mod. The mod is distributed through the Steam Workshop as a subset of these files, marked in the layout below; this README is not part of the shipped file set.

### Dev Prerequisites

- Windows with PowerShell 7
- Palworld from Steam, at the default location or anywhere you pass with `-GameRoot`
- The two dependencies, [UE4SS Experimental (Palworld)](https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587) and [PalSchema](https://steamcommunity.com/sharedfiles/filedetails/?id=3625280368), subscribed on the Workshop and enabled under **Options → Mod Management**
- **Palworld Mod Uploader**, a free tool in your Steam library, and the mod's Workshop item folder, which its **Create New Mod** makes (see [Starting a mod](#starting-a-mod))
- Node.js, plus `npm install` in the repository root for the `luaparse` package the parse check needs; `package.json` declares it
- Lua 5.5 and luacheck 1.2 on `PATH`; Scoop installs both into your user profile without admin rights
- Python 3 as `python` on `PATH`, with Pillow (`python -m pip install --user pillow`), for the release thumbnail that `stage.ps1 -Minor` and `-Major` draw

### Repository layout

| Path | Purpose | Ships to the Workshop |
| --- | --- | --- |
| `Scripts\` | Lua runtime: `main.lua`, `settings.lua`, `lp\*.lua` | yes |
| `PalSchemaMods\LootablePassives\` | JSON data patches: items, DataTable rows, English strings | yes |
| `Info.json` | Workshop package manifest | yes |
| `LICENSE`, `thumbnail.png` | Package metadata | yes |
| `assets\thumbnail-base.png` | The thumbnail without a version label; `thumbnail.png` is this with the release version drawn under the title | no |
| `README.md` | This page: the development repo's documentation | no |
| `.docs\workshop-description.txt` | The Steam Workshop page text, in Steam's BBCode | no |
| `.docs\crash-watch.md` | The working notes document: the open crash watch, its evidence, and how to triage a recurrence | no |
| `tools\` | `stage.ps1`, `test_staging.ps1`, `draw_thumbnail.py`, `luacheck.js`, `ledger_test.lua` | no |
| `package.json` | Declares `luaparse` for `tools\luacheck.js` | no |
| `.luacheckrc`, `.luarc.json` | Declare UE4SS's injected globals for luacheck and the Lua language server | no |

What ships is decided by `Info.json`, not by a list in the tools: `stage.ps1` stages `Info.json`, the `Thumbnail` file, `LICENSE`, and every `InstallRule` target, and nothing else.

Screenshots, crash-dialog text and logs dropped into `.docs\` while testing are ignored by git; `.gitignore` lists the patterns.

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

There is no build step. The repository is the working copy. A plain `stage.ps1`, with no flag, is a local test build: it raises the patch number (`1.1.1` → `1.1.2`), sets `DebugMode` true, and ships nothing; the host machine installs it at its next launch. The patch bump is what makes the loader install it, as described below the version table. A multiplayer test also uploads that stage, so that a second, subscribed machine joining the host runs the same version. Only `stage.ps1 -Minor` and `stage.ps1 -Major` make a shipping release. `-Minor` raises the minor number and resets the patch to 0 (`1.1.2` → `1.2.0`). `-Major` raises the major number and resets the minor and patch to 0 (`1.2.3` → `2.0.0`). Apart from the version they behave the same, and a patch of 0 is the version form of a shipped release.

```powershell
# edit the JSON under PalSchemaMods\ or the Lua under Scripts\, then:
node tools\luacheck.js          # Lua parse check
luacheck Scripts                # static analysis; the baseline is 0 warnings / 0 errors
lua tools\ledger_test.lua       # after any change to Scripts\lp\ledger.lua
.\tools\test_staging.ps1          # after any change to tools\stage.ps1
.\tools\stage.ps1               # local test build: patch + 1, DebugMode on; add -DryRun to preview
.\tools\stage.ps1 -Minor        # minor release: minor + 1, patch 0, DebugMode off; redraws the thumbnail; deletes stale files
.\tools\stage.ps1 -Major        # major release: major + 1, minor 0, patch 0; otherwise the same as -Minor
# for a multiplayer test or a release: Upload To Steam from Palworld Mod Uploader
# restart Palworld (on both machines for a multiplayer test), check the version, test, read the log
```

`stage.ps1` writes `Version` and `DebugMode` into the repository's `Info.json` and then stages that file unchanged, so the repository always matches what was last staged. It writes the same `DebugMode` value onto every staged line tagged `stage:DebugMode`, which in this mod is the `debug` line in `Scripts\settings.lua`:

| Run | `Version` | `DebugMode` and `debug` | Example |
| --- | --- | --- | --- |
| `.\tools\stage.ps1` | patch + 1 | `true` | `1.1.0` → `1.1.1` |
| `.\tools\stage.ps1 -Minor` | minor + 1, patch `0` | `false` | `1.1.3` → `1.2.0` |
| `.\tools\stage.ps1 -Major` | major + 1, minor `0`, patch `0` | `false` | `1.2.3` → `2.0.0` |

Only a release has patch `0`. Giving `-Minor` and `-Major` together stops the run with nothing written.

The default run, with no flag, is an explicit patch update, and the patch bump is not optional, even for a stage that is only tested locally and never uploaded. At launch the loader reinstalls a mod when the item folder's `Version` differs from the installed copy's (see [How a staged build reaches the game](#how-a-staged-build-reaches-the-game)). Without a new version, a changed build can sit in the item folder while the game keeps running the old one. A subscribed machine relies on that version change alone. On the host, the dev build's `DebugMode` true also makes the loader reinstall at every launch, but the patch bump is still what gives each test build a version of its own, which you can check under **Options → Mod Management** to confirm which build the game loaded.

1. Preview the stage if you want: add `-DryRun` to any of the three commands. It prints the next version and changes nothing.
2. Stage a dev build with `.\tools\stage.ps1`, or a release with `.\tools\stage.ps1 -Minor` or `.\tools\stage.ps1 -Major`. A release also redraws `thumbnail.png` with its version first (see [The release thumbnail](#the-release-thumbnail)). Commit the rewritten `Info.json` and `Scripts\settings.lua`, and for a release `thumbnail.png`, with the change they carry.
3. For a release, or a multiplayer test, upload from **Palworld Mod Uploader**, which is software run from Steam. A local test build needs no upload. A dev build that is uploaded goes out with `DebugMode` on, which makes every subscriber's loader reinstall the mod at each launch until the next release.
4. Restart Palworld. The host reinstalls from the item folder at launch. A subscribed machine reinstalls once Steam has downloaded the upload; for a multiplayer test, check the version under **Options → Mod Management** on both machines before testing together.
5. If the player-facing description changed, paste `.docs\workshop-description.txt` into the Workshop page's description by hand. The uploader does not carry it, and the stage does not include it.

UE4SS hot reload is disabled, and the loader installs only at launch, so a running game does not pick up a change until it restarts.

The mod must be enabled under **Options → Mod Management** for the loader to install it. `stage.ps1` warns when it, or one of its `Dependencies`, is not.

### The release thumbnail

The shipped `thumbnail.png` is `assets\thumbnail-base.png` with the release version drawn under the title as `vMAJOR.MINOR`, for example `v1.2`. The patch number is left off because a release always has patch `0`. Always draw from the base and never edit the base itself; it is the title art with no version on it.

#### Label parameters

These were measured from the base image's title text (512 × 512 px), so that the label matches it:

| Parameter | Value | Where it comes from |
| --- | --- | --- |
| Font | Arial Black, `C:\Windows\Fonts\ariblk.ttf` | The closest installed match; the title's font is not an installed font |
| Size | 58 pt | The smallest size whose digit `1` is 43 px tall, the title's letter height |
| Fill | RGB `253, 237, 8` | The median colour of the title's yellow pixels |
| Top of the digits | y = 284 px | The bottom of "PASSIVES" (253) plus the 31 px gap between the two title lines |
| Horizontal centre | x = 258 px | The centre of both title lines |
| Outline | Black, about 3 px | The text mask under a 7 px max filter |
| Shadow | Black at 85 % opacity, offset 3 px right and 4 px down, Gaussian blur radius 2 | The outline widened 1 px further, then offset and blurred |

Layers are drawn shadow first, then the outline, then the yellow fill.

These values are the constants at the top of `tools\draw_thumbnail.py`.

#### How it is drawn

Both release runs draw it, `stage.ps1 -Minor` and `stage.ps1 -Major`. The stage works out the release version before anything else, and when `tools\draw_thumbnail.py` exists beside it, runs that script first in the write step:

```powershell
python tools\draw_thumbnail.py <repo>\thumbnail.png v1.3
```

The label is the release version without its patch number: `v1.3` from `-Minor` on `1.2.x`, and `v2.0` from `-Major`. The output path is the `Thumbnail` that `Info.json` names. The script always reads `assets\thumbnail-base.png`, never writes it, and refuses an output path equal to it. Then the stage writes `Info.json` and copies the new thumbnail with everything else.

- `-Minor -DryRun` or `-Major -DryRun` prints the `draw` line with the label it would draw, and draws nothing.
- A dev build (`stage.ps1` with neither flag) never draws, so `thumbnail.png` keeps the last release's label.
- If the script exits nonzero, for example because Pillow is missing, the run stops with nothing written. If `python` is not on `PATH`, the run's checks stop it before that.
- A repository with no `tools\draw_thumbnail.py` stages its thumbnail as it is, which is what keeps `stage.ps1` free of anything specific to this mod.

To preview a label without staging, draw it somewhere outside the repository:

```powershell
python tools\draw_thumbnail.py $env:TEMP\preview.png v1.3
```

After a release, open `thumbnail.png`, check the label sits centred under "PASSIVES", and commit it with `Info.json`. `git status` should list `thumbnail.png` as modified and never `assets\thumbnail-base.png`.

The measurements above hold only for this base image. If the title art is replaced, measure the new title again and update the table and the script's constants.

### How a staged build reaches the game

```text
repo  --stage.ps1-->  <Workshop content>\1623730\<item id>\  --loader, at launch-->  <Palworld>\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\
                                                                                     <Palworld>\Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\{items,raw,translations}\
```

- **Finding the item folder.** `stage.ps1` uses the one folder under the Workshop content directory whose `Info.json` has this repository's `PackageName`, and stops if there is none or more than one.
- **What it stages.** `Info.json`, the `Thumbnail` file, `LICENSE`, and every `InstallRule` target, and nothing else. It refuses an `Info.json` the uploader would accept but the game would not install, warns about a target missing from the repository, and prints where each rule installs. It overwrites the item folder's `Info.json` with the repository's, and never touches the uploader's `.workshop.json`.
- **A mirror.** Before copying anything, it compares the item folder with the files about to be staged. A file the stage does not have stops the run with nothing changed. After you delete a file from the repository, run the next stage with `-Force`, which deletes those files and any folder left empty. `-Minor` and `-Major` do the same deletion without `-Force`, so a release is always an exact mirror of the repository. At the next reinstall the file is in the old manifest and not in the new install; check the game folder the first time you rely on that.
- **When the loader reinstalls.** At launch it compares `Version` in the item folder's `Info.json` with the installed copy in `<Palworld>\Mods\ManagedMods\LootablePassives\`, as plain strings. When they differ, or when `DebugMode` is true, it removes what its `InstallManifest.json` lists and copies the `InstallRule` targets in again. A subscribed machine does the same after Steam downloads an upload. Every stage raises the version, so the first launch after each stage installs it. `stage.ps1` warns if the new version equals the last upload, which a subscribed machine would not reinstall.
- **The host installs whatever is staged.** Its next launch installs the staged copy whether or not it was uploaded. That is what makes a plain stage a local test build; for a multiplayer test, upload it too, or the subscribed machine is on an older version than the host.
- **Only the loader writes the game folders.** For a `Lua` rule it also adds the `<PackageName> : 1` line to UE4SS's `mods.txt`, which is what starts the Lua half.
- **Turning the mod off.** Use **Options → Mod Management**, which removes both halves. Setting `LootablePassives : 0` in `mods.txt` stops only the Lua half, and the Surgery Table operations stay listed with nothing behind them.

### Reading the log

The log is `UE4SS.log` in the game's UE4SS folder. Filter it on:

- `[LootablePassives]` for the mod's own messages
- `PalSchema` for the data half loading
- `error` and `warning` for anything failing outright

A healthy start logs `Loaded 115 extractable passives, 2 extraction operations, 54 insert routes.` That line counts only the Lua tables, and it prints even when the JSON loaded nothing. The data half is confirmed by PalSchema's own lines: `DT_OperatingTablePassiveSkillDataTable: 54 rows updated, 117 rows added, 0 rows deleted, 0 errors` and `DT_PassiveSkill_Main_Common: 0 rows updated, 56 rows added`.

After a crash, look in `%LOCALAPPDATA%\Pal\Saved\Crashes\`.

### Probing the game with debug keys

A question about the engine is easier to answer in a running game than in a log read after quitting, so this repo uses a throwaway probe module driven by key presses. You press a key in game, the probe does one thing, and you read the result in the UE4SS console or `UE4SS.log` with the game still running. The 1.3.0 probes answered the net-mode, handshake, join, conveyor-timing, container-reach and Surgery-list questions this way, and were then deleted. Write a new one when a new question comes up, and delete it once the answer is recorded.

How a probe is built:

- **One module, loaded only in a debug build.** `main.lua` does `if debug_on() then require("lp.probe").install(hooks, MOD_ROOT) end`. A release build never loads it, and deleting the file and that line removes it completely.
- **One key per action, with a modifier.** `RegisterKeyBind(Key.F12, { ModifierKey.CONTROL }, callback)`. Ctrl+F9 to Ctrl+F12 were free. The installed Keybinds mod already uses Ctrl+Numpad6, Ctrl+J and Ctrl+H for its dumpers. `Key` and `ModifierKey` are declared in `.luacheckrc` and `.luarc.json`.
- **The key callback only schedules.** A keybind callback is not a game-thread hook, so it hands its work to the game thread. Wrap the work once, at load, with `util.coalescer(work, 0)`, and register that function. Repeated presses then queue at most one pass, and no closure is built per press.
- **A toggle keeps its state in the module.** One key that flips something on and flips it back on the next press, such as collapsing the mod's entries in the Surgery list, is the quickest way to compare the two states side by side.
- **Every line carries a prefix,** for example `PROBE`, so the results can be filtered out of the log in one search.
- **Log immediately before each engine call** (`PROBE list: calling SetVisibility on entry 4`), so a crash names the call that caused it.
- **Automatic probes ride on existing events.** Report something 5 s after `RegisterLoadMapPostHook` fires, or when a server-side join hook fires, so a dedicated server, which has no keyboard input for the mod, reports too.
- **Copy each probe session's logs into `.docs\`** as `probe-<machine>-<what>-<version>.log` before restarting anything; the next launch overwrites `UE4SS.log`. `.gitignore`'s `*.log` keeps them out of commits. A dedicated server keeps its own log at `PalServer\Mods\NativeMods\UE4SS\UE4SS.log`.
- **Stage it as a dev build** (`.\tools\stage.ps1`) and restart, like any other change.

### The data half

The JSON under `PalSchemaMods\LootablePassives\` is edited by hand and is the source of truth; nothing generates or validates it, and PalSchema skips a malformed file without an error a player would see.

| File | Holds |
| --- | --- |
| `items\LootablePassivesImplants.json` | The 94 mod-defined disposable implants, `LP_Implant_<passive>` |
| `raw\LootablePassivesOperation.json` | The two extraction markers, `LP_ExtractOne` and `LP_ExtractAll`, and their Surgery Table rows |
| `raw\LootablePassivesOperatingTable.json` | 61 insertion routes for passives vanilla has no Surgery Table row for |
| `raw\LootablePassivesVanillaPrices.json` | `Price` only, on vanilla's 54 routes: 5000 for a recipe, 1000 for one that consumes a vanilla implant |
| `raw\LootablePassivesInsertRoutes.json` | 54 `LP_Insert_<passive>` alias passives and their routes, for the passives whose one Surgery Table row vanilla already uses for a recipe |
| `translations\en\LootablePassivesOperation.json` | English names and descriptions for the markers and the aliases |

Each alias is swapped for its real passive by `Scripts\lp\ids.lua`'s `IMPLANT_TARGET` as soon as it is implanted, so every alias row needs a key there and every key needs a row. The aliases and markers have `Category` `SortNotDisplayable`, which keeps them out of the Palbox search and sort list; with `SortDisplayable` each alias showed there as a duplicate of its real passive.

An alias's description is a static English copy of the text the game builds for the real passive (`BP_PalUIFunctionLibrary`'s `BuildPassiveSkillDescText`), color tags included. If a game update changes a passive's numbers, its alias keeps the old text until it is copied again.

### Settings

`Scripts\settings.lua` holds the switches that are safe to change. Each is documented in the file.

- `debug`: debug mode. `stage.ps1` sets it `true` for a dev build and `false` for a release. On, it adds `DEBUG:` trace lines to `UE4SS.log` and arms `debug_faults`.
- `conveyor_extraction`: the Pal Disassembly Conveyor's implants. `false` registers none of its hooks; implants already owed from an earlier session are still delivered.
- `surgery_ui_gate`: the Edit-button gate on the Surgery screen, which refuses a click that cannot succeed. It is a kill switch for the one part of the mod that writes to a widget while the screen is open; with it off, the transaction still checks every rule and unwinds, but the operation's gold is not refunded.
- `debug_faults`: injected failures for testing the crash-recovery paths: a failed journal write, a stop as if the game had crashed after a given journal row, a failed implant refund, and an exchange that cannot be resolved. It is a list of scenarios, each naming the kind of Surgery exchange it waits for (Extract One, Extract All or implant); the next exchange of that kind takes the first unused one, so a single game launch can run every scenario, in any order across kinds. Each is used once per launch. Ignored unless `debug` is `true`.

`Scripts\lp\config.lua` is the only reader of the file. It reads each value at the moment it is used, so a value changed while the game runs takes effect: the gate at its next frame, the conveyor at its next firing (turned on after load, its hooks are registered at the next map load), debug at its next log line. A value of the wrong type is logged once and its default used; if the file fails to load, every switch takes its default.

The file is installed with the rest of `Scripts\`, so the loader overwrites an edit made in the game folder at its next reinstall.

### The tools

| Command | What it does |
| --- | --- |
| `node tools\luacheck.js` | Parses every Lua file under `Scripts\`. Syntax only. |
| `luacheck Scripts` | Static analysis: undefined globals, unused variables, shadowing. Uses `.luacheckrc`. |
| `lua tools\ledger_test.lua` | Test of the mod: the pending-delivery ledger's file format and who it delivers to, with the engine stubbed out. |
| `.\tools\stage.ps1` | Checks `Info.json`, sets its version and `DebugMode` (dev build by default, minor release with `-Minor`, major release with `-Major`), writes `DebugMode` onto every `stage:DebugMode` line, and on a release redraws the thumbnail, then mirrors what `Info.json` names into the Workshop item folder, ready to upload. Takes `-Minor`, `-Major`, `-DryRun`, `-Force`, `-GameRoot` and `-WorkshopRoot`. |
| `.\tools\test_staging.ps1` | Test of `stage.ps1`: runs a copy against throwaway repo, Workshop and game folders in `%TEMP%` and checks versions, checks, item-folder detection, the stale stop, `-Force`, both release runs and their stale deletion and thumbnail draw, the refusal of `-Minor` with `-Major`, and `-DryRun`. Never touches the real game or Workshop folders. `-Keep` leaves the temp folders for inspection. |
| `python tools\draw_thumbnail.py <output> <label>` | Draws `<label>` under the title of `assets\thumbnail-base.png` and writes it to `<output>`. `stage.ps1 -Minor` and `-Major` run it; run it by hand only to preview a label. |
