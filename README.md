# Lootable Passives

Pull a passive off a Pal and receive a disposable implant.

Vanilla has disposable implants for a handful of passives. This mod defines disposable implants for **all 115** passives, and gives you two ways to get them.

## Benefit

One of the main criticisms of the game is that late-game breeding to get the pal you want is too slow.  This takes getting the exact passives you want out of the equation and will speed up the process of getting the ultimate Pal!

## At the Surgery Table

Three new operations appear in the passive list, each costing 1000 gold:

- **Extract Passive** — removes the passive you selected and returns one matching disposable implant.
- **Extract All Passives** — removes every passive on the Pal and returns an implant for each; selecting any yields the same result.
- **The passive itself** — one entry per passive for which you have a disposable implant; the operation costs a disposable implant and the 1000 gold operation price.

## At the Pal Disassembly Conveyor

Queue a Pal as you normally would. In addition to the usual loot, you get a disposable implant sent to your inventory for every passive on the Pal — an automatic extract-all, at no gold cost.  Implants that exceed inventory space will drop at the character's feet like world item drops.

## What it does not change

- Extracting a passive that came from a purchased recipe gives you a **single-use implant, never the recipe**. The token economy stays intact.
- Overwriting a passive with any other still destroys the original and yields nothing. That is vanilla's behavior and this mod leaves it in place.
- A Pal still cannot be given a passive it already has; duplication prevention like in vanilla.
- The Surgery Table's existing options are untouched apart from price. Price now follows the operation method: a reusable recipe operation costs 5,000 to implant a passive, inserting a passive via disposable implant is 1,000 — including the disposable implants from vanilla.

## Requirements

- Palworld 1.0, build revision **102999** or newer
- [UE4SS Experimental (Palworld)](https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587) — Workshop id 3625223587
- [PalSchema](https://steamcommunity.com/sharedfiles/filedetails/?id=3625280368) — Workshop id 3625280368

Subscribe to both dependencies as well and enable all three under **Options → Mod Management**.

## Multiplayer

Install it on every player for full functionality. A player without it cannot use the implants, and show as blank entries in shared storage. Tested on two machines with the host modded and the client not: result was stable for both players, extraction and disassembly normal for the host who had the mod.  Has NOT been tested on a client where the host does not have the mod.

Not tested: dedicated-server hosting.

## Known limitation

The Edit button's coloring in the surgery table is wonky on some transactions; exiting the menu and coming back solves the issues with a UI redraw.

## Install

Subscribe on the Steam Workshop to this mod and to both dependencies above, then start Palworld and enable all three under **Options → Mod Management**. The official loader copies the files in and records what it copied, so the mod manager is also how you turn it off again.

## Uninstalling

Disable it under **Options → Mod Management** and the loader removes what it installed.

What this mod leaves behind is ordinary: passives already implanted are real passives and stay on the Pal, and disposable implants still in an inventory refer to items that no longer exist.

Two things worth knowing first, both general to Palworld modding rather than specific to this mod. Pocketpair's guidance is that turning a mod off is not always enough and that files left in the game folder can still be loaded — if you have ever installed mods by hand, delete those with File Explorer and verify your game files through Steam. And a save that has been loaded with mods enabled can keep showing problems afterwards, so back up a save you care about before experimenting.

## Credits

- Thanks to the authors of **UE4SS** and **PalSchema**, without which none of this is possible.
- Inspired by *Surgery Table Passive Extractor - Lucky & Legend* (Workshop id `3786582350`), which showed an outline of extracting passives through the Surgery Table.
- Not affiliated with or endorsed by Pocketpair. See [LICENSE](LICENSE).
