# aSmoothLootHelper

**Automatically roll on loot based on rules, history, BiS lists, and stat weights.**

A World of Warcraft **MoP Classic** addon that reduces loot roll clicking to near-zero. Configure your rules once and the addon handles Need, Greed, and Pass decisions for you — intelligently.

## Features

### Auto-Greed on History
Items you've greeded before are automatically greeded again. Tracked account-wide so your alts benefit too.

### Auto-Roll Mode
Set your character to auto-Pass, auto-Greed, or auto-Need on everything. Perfect for:
- **Pass** — boosting someone through a dungeon
- **Greed** — farming on a geared main
- **Need** — soloing old raids

Resets to Off when you log out so you never accidentally leave it on.

### Armor Type Filter
Automatically greed or pass on armor that isn't your class type (e.g. Cloth/Leather/Mail dropping for a Plate wearer). Weapons, rings, trinkets, and cloaks are not affected.

### Quality Auto-Roll
Auto-roll on items at or below a quality threshold. Set it to Greed + Uncommon to auto-greed all greens and whites.

### BiS Auto-Need
Integrates with **BisTooltip** and **FrogBiS** to automatically Need on items that are on your BiS or Pre-Raid list and you haven't collected yet. Checks **all** lists (templates, custom sets, named sets), not just the active one. Items you've already collected are auto-greeded instead.

A prominent on-screen notification appears when a BiS item is auto-needed so you don't miss it.

### Auto-Greed Downgrades
Compares drops to your equipped gear using a 3-tier system:
1. **Pawn** (if installed) — full stat weight analysis
2. **Built-in stat weights** — paste a Pawn import string from Wowhead/Icy Veins/wowsims
3. **Item level comparison** — fallback if no stat weights configured

Items scored worse than your gear are auto-greeded. Potential upgrades (including same-ilvl sidegrades) are left for manual decision.

### Session Memory
Remembers what you manually rolled on each item during a play session. If the same item drops again, repeats your last choice automatically. Clears on logout.

### Item Level Threshold
Auto-greed any item at or below a configurable item level. Per-character.

### Confirm Bypass
Automatically dismisses the "Are you sure?" popup on all loot rolls — both auto-rolls and manual ones.

### Debug Log
Built-in debug log viewer (BugSack-style) with selectable, copyable text. Shows exactly what the addon decided for each roll and why.

## Slash Commands

| Command | Description |
|---|---|
| `/slh` | Open options panel |
| `/slh on` / `off` | Enable / disable addon |
| `/slh mode <off\|pass\|greed\|need>` | Set auto-roll mode (resets on logout) |
| `/slh session` | Toggle session memory |
| `/slh session clear` | Clear session memory |
| `/slh armor <greed\|pass>` | Auto-roll off-armor-type items |
| `/slh armor off` | Disable armor filter |
| `/slh quality <pass\|greed\|need\|off> <green\|rare>` | Quality auto-roll |
| `/slh ilvl <N>` | Set iLvl threshold |
| `/slh ilvl off` | Disable iLvl greed |
| `/slh history` | Show greed history |
| `/slh reset` | Clear greed history |
| `/slh debuglog` | Open debug log viewer |
| `/slh status` | Show all current settings |

## Optional Dependencies

| Addon | What it provides |
|---|---|
| [BisTooltip](https://www.curseforge.com/wow/addons/bistooltip) | BiS item database for auto-need |
| [FrogBiS](https://www.curseforge.com/wow/addons/frogbis) | BiS templates and custom sets for auto-need |
| [Pawn](https://www.curseforge.com/wow/addons/pawn) | Stat weight scoring for upgrade detection |

None are required — each feature degrades gracefully when the dependency isn't installed.

## Priority Order

When multiple rules could apply, the addon uses this priority (highest first):

1. **Armor type filter** — off-type armor greeded/passed immediately
2. **Quality auto-roll** — items at/below quality threshold
3. **BiS auto-need** — uncollected BiS items needed; collected BiS greeded
4. **Auto-roll mode** — blanket pass/greed/need override
5. **Session memory** — repeat last manual roll
6. **History greed** — previously greeded items
7. **iLvl threshold** — items below configured ilvl
8. **Downgrade greed** — Pawn/stat weights/ilvl says equipped is better
9. **Manual roll** — nothing matched, player decides

## Installation

Extract the `aSmoothLootHelper` folder into:
```
World of Warcraft/_classic_/Interface/AddOns/
```

## Configuration

All settings are available in the in-game options panel (**Interface → AddOns → aSmoothLootHelper**) or via `/slh`.

Per-character settings (auto-roll mode, armor filter, iLvl threshold, BiS, stat weights) are stored separately per character. Greed history is shared account-wide.
