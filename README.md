# Lootable Passives

A Palworld mod. It turns all of the game's 115 passives into items in a few ways:

1) the Pal Surgery Table is a two-way device:
    - Extracted passives become inventory items
    - Passives which are inventory items are single-use items that can be inserted onto a Pal at the surgery table
2) The Pal Disassembly Conveyor will produce passive items when consuming a Pal as if all passives were extracted from that Pal

## What it adds

Three operations appear in the Surgery Table's passive selection list:

- **Extract Passive** — removes the selected passive and returns one matching module.
- **Extract All Passives** — removes every extractable passive and returns a module for each, for
  one flat 1,000 gold.
- ***passive name*** — one entry per passive, spending a disposable module you hold.

## What it does not change

Palworld already has three ways a passive gets onto a Pal. This mod expands the third and leaves
the other two alone apart from price.

| Route | Where the item lives | Consumed? | Cost | What this mod does |
| --- | --- | --- | --- | --- |
| Default Surgery Table options | Provided by the workstation | no | 5,000 | price only |
| Reusable recipes, bought with bounty tokens | Key Items | no | 5,000 | price only |
| Disposable implant modules | Inventory | **yes** | 1,000 | **expanded to all 115 passives** |

Vanilla's overwrite behaviour is also unchanged: a passive you overwrite is gone and does not
produce an item.

## Requirements

- Palworld 1.0, build revision **82182** or newer
- [UE4SS Experimental (Palworld)](https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587) — Workshop id `3625223587`
- [PalSchema](https://steamcommunity.com/sharedfiles/filedetails/?id=3625280368) — Workshop id `3625280368`

Subscribe to both in the Workshop first and let the in-game mod manager install them. UE4SS has to
initialise before this mod's Lua runs, and PalSchema has to apply its data patches before that Lua
can reference the item ids they create.

## Install

This is not a Workshop item yet, so the in-game mod manager cannot install it. Clone and run the
script:

```powershell
git clone https://github.com/funkergreg/LootablePassives.git && cd LootablePassives
.\tools\install.ps1
```

Then **restart Palworld** — UE4SS hot reload is disabled, so a running game will not pick it up.

If Palworld is somewhere other than the default Steam path:

```powershell
.\tools\install.ps1 -GameRoot "C:\path-to-games\Palworld"
```

Writing under `Program Files` may need an elevated shell.

### What it copies, and where

```
Scripts\                         ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\LootablePassives\Scripts\
PalSchemaMods\LootablePassives\  ->  <Palworld>\Mods\NativeMods\UE4SS\Mods\PalSchema\mods\LootablePassives\
```

The script also adds `LootablePassives : 1` to UE4SS's `mods.txt`, which is what actually starts the
Lua half. PalSchema needs no registration — it loads any folder under its `mods/` directory.

Nothing is deleted, and files the mod writes at runtime are left alone.

### Uninstall

Delete **both** destination folders, then remove the `mods.txt` line. Modules already in a save
become unknown items; passives already implanted are real passives and stay put.

> **Do not disable this mod by setting `LootablePassives : 0` in `mods.txt`.** That line controls
> only the Lua half. The PalSchema half has no such switch — it loads whenever its folder is on
> disk — so the mod's operations stay in the Surgery Table list with nothing behind them. Using one
> in that state costs you the gold and the module and leaves an inert placeholder passive on your
> Pal, in place of the passive you selected. Removing the folders is the only safe way off.

## Credits

- Thanks to the authors of **UE4SS** and **PalSchema**, without which none of this is possible.
- Inspired by *Surgery Table Passive Extractor - Lucky & Legend* (Workshop id `3786582350`), which
  showed an outline of extracting passives through the Surgery Table.
- Not affiliated with or endorsed by Pocketpair. See [LICENSE](LICENSE).
