# Lootable Passives

## What this mod does

Passives can be transformed into disposable implants through the Surgery Table or Pal Dissector Conveyor.  The Surgery table contains means for using disposable implants as one-use items to grant a passive to a Pal.

Vanilla has a handful of passives available as single-use disposable implant items. This mod makes item definitions for **all 115**, and gives you two ways to obtain them: extract one or all at the Surgery Table, or let the Pal Disassembly Conveyor recover them from a Pal it consumes.

### Surgery Table

- Three new operation types appear in the passive selection list, all costing 1000 gold each:
  - **Extract Passive** — removes the selected passive and returns one matching disposable implant.
  - **Extract All Passives** — removes every extractable passive and returns a disposable implant for each.
  - ***passive name*** — one entry per passive, spending a disposable implant you hold (only for items in your personal or base-accessible inventtory).
- The screen stays open after extracting, so you can continue operating on a Pal without reopening the UI.
- Default mechanics like the surgery table's innate recipes and the recipes purchasable from bounties or the arena have not been changed except to standardize the price at 5000 gold per oprtation.
- As in vanilla, a Pal cannot be given a passive it already has.
- Extracted disposable implants show in your inventory and in the Surgery list as a purple chip with a quantity
and the line `Disposable Implant: X`, which keeps them visually distinct from vanilla's reusable
recipes (a green chip, no quantity, `Implant: X`). Max stack is 9,999.
- Disposable implants sort as one block, highest rarity first and then by name, so the prizes sit together at the top rather than scattered through your bag. The 21 implants/modules vanilla already defined keep vanilla's own place in the sort.
- **Surgery Table's prices to Edit a Pal are fixed** and are not configurable (in current design)

### Pal Disassembly Conveyor

- Queue a Pal at the conveyor and on disassembly, alongside its normal loot, you get a disposable implant for every extractable passive it had — an automatic extract-all, at no gold cost.
- Disposable implants extracted by the disassembler conveyor go to inventory, and if that is full arrive at your feet; these do not sipt out the back of the machine.  Vanilla's loot still ejects from the machine normally.
- You do not have to do anything differently; put simply Pals in the disassembly queue as in vanilla.
- Expect 0–4 disposable implants given per disassembled Pal; exactly the passives they had on them at time of disassembly.
- Pals you insert and then take back out again are not charged and yield nothing, which is deliberate rather than incidental: the mod distinguishes a consumed Pal from a withdrawn one by how far the machine actually got, not by whether the Pal is still there.
- **The disposable implants go to the player who owns the Pal**, not to whoever is standing nearest and not to the host. If that player is not online they are held and delivered the next time they play, so a machine left running while you are away does not hand your disposable implants to someone else.

### What the mod does not change

Palworld already has three ways a passive can be put onto a Pal. This mod expands one path and leaves
the other two alone apart from price. Notably, extracting a passive that came from a recipe gained via purchase of bounty or arena tokens gives you a single-use disposable implant, never the permanent recipe - the token economy stays intact and you don't get un-removable quantities of key item recipes.

| Route | Where the item lives | Consumed? | Cost | What this mod does |
| --- | --- | --- | --- | --- |
| Default Surgery Table options | Provided by the workstation | no | 5,000 | price only |
| Reusable recipe, bought with tokens | Key Items | no | 5,000 | price only |
| Disposable implant | Inventory | **yes** | 1,000 | **expanded to all 115 passives** |

- **Overwriting a passive destroys it.** This is vanilla's behaviour and the mod does not change it — an overwritten passive yields no disposable implant.

## Requirements

- Palworld 1.0, build revision **82182** or newer
- [UE4SS Experimental (Palworld)](https://steamcommunity.com/sharedfiles/filedetails/?id=3625223587) — Workshop id `3625223587`
- [PalSchema](https://steamcommunity.com/sharedfiles/filedetails/?id=3625280368) — Workshop id `3625280368`

Subscribe to both in the Workshop first and let the in-game mod manager install them. UE4SS has to
initialise before this mod's Lua runs, and PalSchema has to apply its data patches before that Lua
can reference the item ids they create.

## Multiplayer

**Install it on every player for full functionality.** Without it, a player simply cannot use the disposable implants and they appear as undefined objects in shared inventory; nothing causes catastrophic crashes.

Disposable implants from the Pal Disassembly Conveyor go to the player who owned the Pal. The mod cannot ask another player's game whether it has the mod installed — nothing in the modding interfaces exposes that — so if a player without the mod disassembles their own Pal, the disposable implants are created for them and their game shows them as blank entries. That is the deliberate trade: the alternative was the host quietly collecting everyone's disposable implants.

The mod only ever creates items on the host or server, never on a joining player's machine.

**Tested:** host has the mod, joining client does not. The game was stable for both players and
extraction and disassembly worked normally for the host. Items the client's game does not know
about appear as blank entries in a shared base chest.

**Not yet tested:** a client that *has* the mod installed, and dedicated-server hosting. Both are
expected to work — the mod only creates items on the authoritative peer — but neither has been run,
and reports are welcome.

## Install

TODO: Rewrite once Steam workshop install is possible

## Credits

- Thanks to the authors of **UE4SS** and **PalSchema**, without which none of this is possible.
- Inspired by *Surgery Table Passive Extractor - Lucky & Legend* (Workshop id `3786582350`), which
  showed an outline of extracting passives through the Surgery Table.
- Not affiliated with or endorsed by Pocketpair. See [LICENSE](LICENSE).
