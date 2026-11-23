# Auras

Watched auras for World of Warcraft 1.12.1, a light WeakAuras: pick your buffs
and your target's debuffs, and each gets its own icon with the time left.

## Features

- **Your list:** add a buff of yours or a debuff on your target by name or spell
  ID. Each shows as its own icon with the time left and its stacks.
- **Groups:** sort your list into groups you name (Rogue, PvP, Consumes, Raid...)
  and rename at any time. The
  list shows one group at a time, and each group shows Everywhere, only in
  Raids, Dungeons, Battlegrounds or the Open world, or is Off. Where a group is
  not shown, its auras stay in the game's own buffs as if they were not listed.
- **Only mine:** a debuff counts only when you cast it.
- **Cooldown after it ends:** a buff of yours that ends shows its spell's
  cooldown, greyed, until it is ready (only for spells that have one).
- **Loss of control alert:** while you are stunned, feared, silenced, disarmed or
  school-locked, one alert near the center shows the effect's icon, its name and
  the time left (the strongest effect when there are several). On by default;
  turn it off on the Auras page if another addon does this. Ctrl+Shift moves it.
- **Grey when missing:** keeps an aura that is not active on screen as a greyed
  icon, handy for consumables.
- **Glow, warning, size, bar:** click an aura's name in the list to give its
  icon a coloured glow while it is active, a pulse when it is about to run out
  (3 s to 1 min), a size, and a bar of the time left.
- **Place them anywhere:** the Place icons button (or hold Ctrl+Shift) shows
  every icon, also those of groups that are off here; drag them. Spots are
  saved in the addon's own settings.
- **With UnitFrames:** a watched aura leaves the game's buffs at the top
  right and the rows under the frames, unless you tick Top or Row.

`/auras` opens the list; it is also on the Auras page in AddOn Options.

## Requirements

WoW 1.12.1 (build 5875) with **[ClassicAPI](https://github.com/brues-code/ClassicAPI)** loaded. It uses ClassicAPI's aura
reads (`C_UnitAuras.GetAuraSlots`, `UnitAuraBySlot`, `UNIT_AURA_DELTA`), its
native Cooldown countdown, animation groups, `C_DurationUtil` with a StatusBar's
`SetTimerDuration`, `C_Timer`, `GetSpellBaseCooldown` and `C_LossOfControl`.
[UnitFrames](https://github.com/Fostercare5988/UnitFrames) is
optional.

## Installation

Download `Auras.zip` from the
[latest release](https://github.com/Fostercare5988/Auras/releases/latest),
extract it into `Interface/AddOns` and enable it in the game's AddOns list. The
folder must contain `Interface/AddOns/Auras/Auras.toc`. It replaces the
watched auras of UnitFrames 1.0.0.
