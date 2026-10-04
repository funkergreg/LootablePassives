# Lootable Passives

This is the Lootable Passives Palworld mod's development repository. General users NOT doing development will install the mod from the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3805554239); see [Mod Development](#mod-development) for working from source from this repo, including installing the mod with local commands.

## Mod Development

This repo is development and source, not the shipped product -- the mod itself -- which is distributed via Steam Workshop. The Workshop package is staged and shipped as a subset of this repo's files, as marked in the layout below, and this README is not part of that package.

### Dev Prerequisites

- Windows with PowerShell 7
- Palworld with UE4SS Experimental and PalSchema already installed, either at the default Steam location or anywhere you pass with `-GameRoot`
- Node.js, plus `npm install` in the repository root for the `luaparse` package the parse check needs
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
| `tools\` | `install.ps1`, `stage.ps1`, `mirror.ps1`, `luacheck.js`, `ledger_test.lua` | no |
| `.luacheckrc`, `.luarc.json` | Declare UE4SS's injected globals for luacheck and the Lua language server | no |

### The edit, check, install loop

There is no build step. The repository is the working copy, and the game only loads what is under `<Palworld>\Mods\NativeMods\UE4SS\Mods`, so every change is deployed before it is tested.

```powershell
# edit the JSON under PalSchemaMods\ or the Lua under Scripts\, then:
node tools\luacheck.js          # Lua parse check
luacheck Scripts                # static analysis; the baseline is 0 warnings
lua tools\ledger_test.lua       # after any change to Scripts\lp\ledger.lua
.\tools\install.ps1             # repo -> game; add -DryRun to preview
# restart Palworld, exercise the change, then read the log
```

UE4SS hot reload is disabled, so a running game does not pick up a change until it restarts.

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
| `lua tools\ledger_test.lua` | The one automated test: the pending-delivery ledger's file format and who it delivers to, with the engine stubbed out. |
| `.\tools\install.ps1` | Mirrors the repo into the game and enables the Lua half in UE4SS's `mods.txt`. Takes `-DryRun`, `-Force` and `-GameRoot`. |
| `.\tools\stage.ps1` | Mirrors the shippable files into a Workshop item folder and checks `Info.json` first. Takes `-ItemId` or `-Destination`, `-DryRun` and `-Force`. |
| `tools\mirror.ps1` | Helpers shared by `install.ps1` and `stage.ps1`. Dot-sourced, not run directly. |

### How the install mirrors

`install.ps1` copies two folders:

```text
Scripts\                         ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\
PalSchemaMods\LootablePassives\  ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\
```

- Before copying anything, it compares both destinations with the repository. A destination file the repository does not have stops the run with nothing changed, because the game would still load it. After you delete a file from the repository, run the next install with `-Force`, which deletes those files and any folder left empty.
- Nothing outside those two destinations is examined or deleted.
- It adds `LootablePassives : 1` to `mods.txt`, which is what starts the Lua half. PalSchema needs no registration; it loads any folder under its `mods\` directory.
- Do not disable a dev install by setting `LootablePassives : 0`. That stops only the Lua half, and the Surgery Table operations stay listed with nothing behind them. To remove a dev install, delete both destination folders and then remove the `mods.txt` line.

### Publishing to the Workshop

1. Bump `Version` in `Info.json`. The loader compares it as a plain string, so an unchanged version is not seen as an update.
2. Preview the stage: `.\tools\stage.ps1 -ItemId <item id> -DryRun`. The item id is the numbered folder Palworld Mod Uploader's **Create New Mod** made under the Workshop content directory.
3. Stage it: `.\tools\stage.ps1 -ItemId <item id>`. It copies an allowlist and nothing else, refuses an `Info.json` the uploader would accept but the game would not install, prints where each rule installs, and never touches the uploader's `.workshop.json`.
4. Upload from **Palworld Mod Uploader** which is software run from Steam.
5. If the player-facing description changed, paste `.docs\workshop-description.txt` into the Workshop page's description by hand. The uploader does not carry it, and the stage does not include it.

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

### Known limitation

The Edit button's coloring in the surgery table is wonky on some transactions; exiting the menu and coming back solves the issues with a UI redraw.

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
