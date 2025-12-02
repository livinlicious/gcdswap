# GCDSwap

Event-driven weapon swap addon for Turtle WoW (1.12 client).

## Overview

GCDSwap allows you to swap weapons during the Global Cooldown (GCD) window with a simple manual trigger system. Unlike macro-based "cast + equip" solutions, GCDSwap uses an event-driven queue to avoid race conditions and timing failures.

## How It Works

1. **Arm**: Press `/gcdswap <preset>` to queue a weapon swap
2. **Trigger**: Cast any instant-cast ability (Sunder Armor, Mortal Strike, Hamstring, etc.)
3. **Swap**: The addon detects `SPELLCAST_STOP` and swaps weapons during the GCD
4. **Auto-disarm**: The swap completes and the addon automatically disarms

The addon intelligently detects which weapon is currently equipped and swaps to the other one, allowing you to toggle between two weapons repeatedly.

## Installation

1. Download or clone this repository
2. Place the `gcdswap` folder in your `Interface/AddOns/` directory
3. Restart WoW or reload UI (`/reload`)

## Usage

### Save a Preset

```
/gcdswap save <name> [Weapon1] [Weapon2]
```

**Weapon1**: Your normal/main weapon (what you return to)
**Weapon2**: Your GCD swap weapon (what you swap to during GCD)

**Example:**
```
/gcdswap save abc [Aurastone Hammer] [Mace of Unending Life]
```

You can shift-click items from your bags or character sheet to insert them into the command.

### Arm the Swap

```
/gcdswap <preset>
```

**Example:**
```
/gcdswap abc
```

This arms the addon to swap weapons on your next instant-cast ability.

### Toggle Between Weapons

```
/gcdswap abc          → Arms (will swap to Weapon2)
<cast ability>        → Swaps to Weapon2
/gcdswap abc          → Arms (will swap to Weapon1)
<cast ability>        → Swaps back to Weapon1
```

The addon automatically detects which weapon is equipped and swaps to the other one.

## Commands

| Command | Description |
|---------|-------------|
| `/gcdswap <preset>` | Arm swap with the specified preset |
| `/gcdswap save <name> [W1] [W2]` | Save a new preset |
| `/gcdswap list` | List all saved presets |
| `/gcdswap delete <name>` | Delete a preset |
| `/gcdswap status` | Show current status |
| `/gcdswap debug` | Toggle debug messages |
| `/gcdswap sound` | Toggle sound effects |
| `/gcdswap help` | Show help |

## Use Cases

- **Proc weapon swapping**: Equip a slow weapon with procs during GCD, then swap back
- **Stat optimization**: Briefly equip weapons with different stats during ability casts
- **Weapon specialization**: Leverage different weapon types for different abilities

## Why Event-Driven?

Traditional "cast + equip in one macro" approaches suffer from race conditions where the client attempts to swap before the server confirms the GCD has started. This causes:
- Failed swaps
- Lag spikes
- Inconsistent behavior

GCDSwap solves this by waiting for `SPELLCAST_STOP` to fire, which occurs **after** the client knows the spell has cast and the GCD has started, providing a safe window for equipment changes.

## Settings

All settings are saved per-character in `SavedVariables`.

- **Presets**: Weapon pairs are saved and persist between sessions
- **Debug Mode**: Toggle verbose logging for troubleshooting
- **Sound**: Enable/disable audio feedback for arming and swapping

## Limitations

- Only works with abilities that trigger GCD
- Weapons must be in your bags to be swapped
- Brief screen freeze (~50ms) may occur during swap due to WoW 1.12 client limitations

## License

Free to use and modify.
