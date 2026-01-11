# GCDSwap

Event-driven equipment swap addon for Turtle WoW (1.12 client).

## Overview

GCDSwap allows you to swap equipment during the Global Cooldown (GCD) window with a simple manual trigger system. Unlike macro-based "cast + equip" solutions, GCDSwap uses an event-driven queue to avoid race conditions and timing failures.

**Supports:** Weapons (main/offhand), Shields, Totems (Shaman), Idols (Druid), Librams (Paladin)

## How It Works

1. **Arm**: Press `/gcdswap <preset>` to queue an equipment swap
2. **Trigger**: Cast any instant-cast ability (Sunder Armor, Mortal Strike, Earth Shock, etc.)
3. **Swap**: The addon detects `SPELLCAST_STOP` and swaps equipment during the GCD
4. **Auto-disarm**: The swap completes and the addon automatically disarms

The addon intelligently detects which item is currently equipped and in which slot (mainhand, offhand, or ranged/relic), then swaps to the other item in the same slot. This allows you to toggle between two items repeatedly.

## Installation

1. Download or clone this repository
2. Place the `gcdswap` folder in your `Interface/AddOns/` directory
3. Restart WoW or reload UI (`/reload`)

## Usage

### Save a Preset

```
/gcdswap save <name> [Item1] [Item2]
```

**Item1**: Your normal/main item (what you return to)
**Item2**: Your GCD swap item (what you swap to during GCD)

**Examples:**
```
/gcdswap save weps [Aurastone Hammer] [Mace of Unending Life]
/gcdswap save totems [Totem of Sustaining] [Totem of Rage]
/gcdswap save idols [Idol of Ferocity] [Idol of Brutality]
/gcdswap save shields [Aegis of the Blood God] [Draconian Deflector]
```

You can shift-click items from your bags or character sheet to insert them into the command. The addon automatically detects which slot your items belong to.

### Arm the Swap

```
/gcdswap <preset>
```

**Examples:**
```
/gcdswap weps
/gcdswap totems
```

This arms the addon to swap equipment on your next instant-cast ability.

### Toggle Between Items

```
/gcdswap totems       → Arms (will swap to Item2)
<cast ability>        → Swaps to Item2
/gcdswap totems       → Arms (will swap to Item1)
<cast ability>        → Swaps back to Item1
```

The addon automatically detects which item is equipped and in which slot (mainhand, offhand, or ranged/relic), then swaps to the other item.

## Commands

| Command | Description |
|---------|-------------|
| `/gcdswap <preset>` | Arm swap with the specified preset |
| `/gcdswap save <name> [Item1] [Item2]` | Save a new preset (works with weapons, shields, totems, idols, librams) |
| `/gcdswap list` | List all saved presets |
| `/gcdswap delete <name>` | Delete a preset |
| `/gcdswap status` | Show current status and equipped items |
| `/gcdswap debug` | Toggle debug messages |
| `/gcdswap sound` | Toggle sound effects |
| `/gcdswap help` | Show help |

## Use Cases

### Warriors/Rogues
- **Proc weapon swapping**: Equip a slow weapon with procs during GCD, then swap back
- **Stat optimization**: Briefly equip weapons with different stats during ability casts
- **Weapon specialization**: Leverage different weapon types for different abilities

### Shamans
- **Totem swapping**: Swap between spell power totems and healing totems mid-combat
- **PvP totem optimization**: Switch between different stat totems for different situations

### Druids
- **Idol swapping**: Switch between healing idols and damage idols during combat
- **Role flexibility**: Change idols when switching between healing and DPS during a fight

### Paladins
- **Libram swapping**: Optimize librams for different abilities or situations
- **Seal twisting enhancement**: Use different librams for different seals

### All Classes
- **Shield swapping**: Swap to a high-armor shield when taking damage, back to DPS offhand when safe

## Why Event-Driven?

Traditional "cast + equip in one macro" approaches suffer from race conditions where the client attempts to swap before the server confirms the GCD has started. This causes:
- Failed swaps
- Lag spikes
- Inconsistent behavior

GCDSwap solves this by waiting for `SPELLCAST_STOP` to fire, which occurs **after** the client knows the spell has cast and the GCD has started, providing a safe window for equipment changes.

## Settings

All settings are saved per-character in `SavedVariables`.

- **Presets**: Equipment pairs are saved and persist between sessions
- **Debug Mode**: Toggle verbose logging for troubleshooting (shows which slot is being swapped)
- **Sound**: Enable/disable audio feedback for arming and swapping

## Limitations

- Only works with abilities that trigger GCD
- Items must be in your bags to be swapped (not in bank)
- Brief screen freeze (~50ms) may occur during swap due to WoW 1.12 client limitations
- Cannot swap items that are not equippable in combat (rings, trinkets, etc.)

## License

Free to use and modify.
