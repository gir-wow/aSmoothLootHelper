# aSmoothLootHelper

**Automatically roll on loot based on rules, history, BiS lists, and stat weights.**

A World of Warcraft addon for **Classic Era**, **TBC Classic**, **Cataclysm Classic**, and **MoP Classic** that reduces loot roll clicking to near-zero. Configure your rules once and the addon handles Need, Greed, and Pass decisions for you — intelligently.

## Features

### Play Mode Presets
Quick-switch between profiles via minimap icon or `/slh mode`:

| Mode | Behavior |
|---|---|
| **Raiding** | BiS auto-need, tier tokens, armor filter, downgrade greed — leave upgrades for manual decision |
| **Greed All** | Greed everything, no exceptions — all filters and BiS checks disabled |
| **Pass All** | Pass everything — for carrying/boosting someone |
| **Custom** | Configure each setting individually |

### BiS Auto-Need
Integrates with **BisTooltip**, **FrogBiS**, and **AtlasLoot** to automatically Need on uncollected BiS items. Collected items are auto-greeded instead.

- Checks all lists (templates, custom sets, named sets, phase variants)
- Full FrogBiS variant support (e.g. P5 - BIS (Balanced), P5 - Prog (Survival))
- Difficulty hierarchy: **Heroic > Normal > Celestial/LFR** — owning normal won't block needing on heroic
- Difficulty upgrades bypass Pawn/outgear guards entirely
- Hard safety gates: blocks auto-need on wrong armor type or wrong primary stat regardless of settings
- Cross-provider check: if ANY provider says the item is already collected, it greeds
- On-screen notification when a BiS item is auto-needed

### BiS Preview Window
Scrollable list of all your BiS items organized by slot (`/slh bis`):
- Shows predicted roll action (NEED/GREED/PASS) with reason
- Difficulty variants auto-generated (Normal/Heroic/Celestial)
- Filter buttons: All / Need only / No Pass
- Greyed-out items for outgeared/collected
- Shift-click to link items to chat

### Tier Token Auto-Need
Automatically needs tier tokens for your class (Protector/Conqueror/Vanquisher) and passes wrong-class tokens. Skips if you already carry the token or have significantly outgeared the slot.

### Transmog Auto-Need
Auto-needs items whose appearance you haven't collected yet via `C_TransmogCollection`.

### Armor Type Filter
Auto-greed or pass on armor that isn't your class type. Also detects wrong primary stat (STR/AGI/INT mismatch). Weapons, rings, trinkets, and cloaks are not affected.

### Downgrade Greed
Compares drops to your equipped gear using a 3-tier system:
1. **Pawn** (if installed) — full stat weight analysis
2. **Built-in stat weights** — paste a Pawn import string from Wowhead/Icy Veins/wowsims
3. **Item level comparison** — fallback if no stat weights configured

Items scored worse than your gear are auto-greeded. Potential upgrades are left for manual decision.

### Auto-Greed on History
Items you've greeded before are automatically greeded again. Tracked account-wide so your alts benefit too.

### Session Memory
Remembers your manual roll choices during a play session. If the same item drops again, repeats your last choice. Clears on logout.

### Quality Auto-Roll
Auto-roll on items at or below a quality threshold (Uncommon or Rare).

### Item Level Threshold
Auto-greed any item at or below a configurable item level. Per-character.

### Lockbox Handling
Configure auto-roll behavior for lockboxes separately (off/pass/greed/need).

### Minimap Icon
- Left-click: toggle addon on/off
- Right-click: play mode selection menu
- Draggable, saves position per character

### Debug Log
Built-in log viewer (`/slh debuglog`) with selectable, copyable text. Shows exactly what the addon decided for each roll and why.

## Slash Commands

| Command | Description |
|---|---|
| `/slh` | Open options panel |
| `/slh on` / `off` | Enable / disable addon |
| `/slh mode <raiding\|greedall\|passall\|custom>` | Switch play mode preset |
| `/slh mode <off\|pass\|greed\|need>` | Legacy auto-roll override (resets on logout) |
| `/slh bis` | Open BiS Preview window |
| `/slh session` | Toggle session memory |
| `/slh session clear` | Clear session memory |
| `/slh armor <greed\|pass\|off>` | Configure off-armor handling |
| `/slh quality <pass\|greed\|need\|off> <green\|rare>` | Quality auto-roll |
| `/slh ilvl <N\|off>` | Set iLvl threshold |
| `/slh history` | Show greed history |
| `/slh reset` | Clear greed history |
| `/slh debuglog` | Open debug log viewer |
| `/slh status` | Show all current settings |

## Optional Dependencies

| Addon | What it provides |
|---|---|
| [BisTooltip](https://www.curseforge.com/wow/addons/bistooltip) | Phase-aware BiS item database for auto-need |
| [FrogBiS](https://www.curseforge.com/wow/addons/frogbis) | BiS templates and custom named sets with variant support |
| [AtlasLoot](https://www.curseforge.com/wow/addons/atlaslootclassic) | Favourites list as BiS source |
| [Pawn](https://www.curseforge.com/wow/addons/pawn) | Stat weight scoring for upgrade detection |

None are required — each feature degrades gracefully when the dependency isn't installed. Providers can be enabled/disabled individually per character.

## Priority Order

When multiple rules could apply, the addon evaluates in this order and stops at the first match:

1. **Tier token auto-need** — need matching class tokens, pass wrong-class tokens
2. **Transmog auto-need** — need uncollected appearances
3. **Lockbox handling** — per-character lockbox roll mode
4. **Armor type filter** — off-type armor greeded/passed
5. **Quality auto-roll** — items at/below quality threshold
6. **BiS auto-need** — uncollected BiS needed; collected/outgeared BiS greeded
7. **Auto-roll mode** — blanket pass/greed/need override
8. **Session memory** — repeat last manual roll
9. **History greed** — previously greeded items
10. **iLvl threshold** — items below configured ilvl
11. **Downgrade greed** — Pawn/stat weights/ilvl says equipped is better
12. **Manual roll** — nothing matched, player decides

## Installation

Extract the `aSmoothLootHelper` folder into:
```
World of Warcraft/_classic_/Interface/AddOns/
```

## Configuration

All settings are available in the in-game options panel or via `/slh`. Per-character settings (play mode, armor filter, iLvl threshold, BiS spec, stat weights) are stored separately per character. Greed history is shared account-wide.
