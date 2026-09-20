# Lootable Passives

A Palworld mod. Passives become items you can take off one Pal and put onto another.

Vanilla has a handful of passives available as single-use implant modules. This mod makes that true
of **all 115**, and gives you two ways to obtain them: extract one deliberately at the Surgery
Table, or let the Pal Disassembly Conveyor recover them automatically from every Pal it consumes.

## What this mod does

### At the Surgery Table

Three operations appear in the passive selection list:

- **Extract Passive** — removes the selected passive and returns one matching module.
- **Extract All Passives** — removes every extractable passive and returns a module for each, for
  one flat 1,000 gold.
- ***passive name*** — one entry per passive, spending a disposable module you hold.

The screen stays open after extracting, so you can work through a Pal without reopening it. As in
vanilla, a Pal cannot be given a passive it already has.

Extracted modules show in your inventory and in the Surgery list as a purple chip with a quantity
and the line `Disposable Implant: X`, which keeps them visually distinct from vanilla's reusable
recipes (a green chip, no quantity, `Implant: X`). Max stack is 9,999.

### At the Pal Disassembly Conveyor

Feed a Pal to the conveyor and, alongside its normal loot, you get a module for every extractable
passive it had — an automatic extract-all, at no gold cost. Expect 0–4 modules per Pal. You do not
have to do anything differently; put Pals in as you always did.

Pals you insert and then take back out again are not charged and yield nothing, which is deliberate
rather than incidental: the mod distinguishes a consumed Pal from a withdrawn one by how far the
machine actually got, not by whether the Pal is still there.

### Known limitations

Honest ones, all observed in play rather than theorised:

- **Conveyor modules arrive at your feet, not out the back of the machine.** They are delivered to
  your inventory, and when your inventory is full they drop where you are standing. Vanilla's loot
  still ejects from the machine normally. Matching the machine's own output position was not
  achievable with the interfaces the game exposes to mods.
- **A full bag does not stop extraction.** Modules that cannot fit drop on the ground at your feet,
  which means they are subject to the usual world-item despawn timer. A module that stacks onto one
  you already hold still fits, so a full bag degrades item by item rather than all at once.
- **In multiplayer, the host receives the modules — not whoever fed the conveyor.** Delivery
  prefers the local player outright, and falls back to the nearest player only among remote ones.
  On a listen-server host that means the host collects everything the conveyor recovers, wherever
  they happen to be standing. Sort it out between yourselves; the game gives a mod no reliable way
  to know who loaded the machine.
- **Modules owed when you quit are paid on your next load.** If the game closes mid-disassembly the
  debt is recorded to disk and delivered when you load back in, usually before you touch anything.
  A hard crash at the wrong instant can still lose an in-flight module.
- **Overwriting a passive destroys it.** This is vanilla's behaviour and the mod does not change it
  — an overwritten passive yields no module.
- **Prices are fixed** at 1,000 gold for a disposable module and 5,000 for the two vanilla routes,
  and are not configurable. They live in 171 rows across four data files with no templating.

## Multiplayer

**Tested:** host has the mod, joining client does not. The game was stable for both players and
extraction and disassembly worked normally for the host. Modules the client's game does not know
about appear as blank entries — in a shared chest, for instance — but looking at them does not
crash anything.

**Install it on every player for full functionality.** Without it, a player simply cannot see or
use the modules; nothing breaks.

**Not yet tested:** a client that *has* the mod installed, and dedicated-server hosting. Both are
expected to work — the mod only creates items on the authoritative peer — but neither has been run,
and reports are welcome.

## What it does not change

Palworld already has three ways a passive gets onto a Pal. This mod expands the third and leaves
the other two alone apart from price. Notably, extracting a passive that came from a bounty-token
recipe gives you a single-use module, never the permanent recipe — the token economy stays intact.

| Route | Where the item lives | Consumed? | Cost | What this mod does |
| --- | --- | --- | --- | --- |
| Default Surgery Table options | Provided by the workstation | no | 5,000 | price only |
| Reusable recipes, bought with bounty tokens | Key Items | no | 5,000 | price only |
| Disposable implant modules | Inventory | **yes** | 1,000 | **expanded to all 115 passives** |

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
