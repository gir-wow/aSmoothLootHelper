# BiS Preview Window

## Overview
A scrollable window showing all BiS items from registered providers, organized by equipment slot.
Users can preview what SLH would roll (Need/Greed/Pass) on each item before it drops.
Accessible from the minimap right-click menu and `/slh bis` slash command.

## Layout

```
┌─ aSmoothLootHelper — BiS Preview ──────────────────────────┐
│  [Refresh]                                          [Close] │
│─────────────────────────────────────────────────────────────│
│  ▸ Head                                                     │
│    [icon] Helmet of the Crackling Protector   NEED  (token) │
│    [icon] Crown of Kingly Blah               NEED          │
│    [icon] Headguard of Whatever         GREED (outgeared)   │
│                                                             │
│  ▸ Neck                                                     │
│    [icon] Necklace of Stuff                   NEED          │
│                                                             │
│  ▸ Shoulder                                                 │
│    ...                                                      │
│                                                             │
│  (scrollable)                                               │
└─────────────────────────────────────────────────────────────┘
```

## Slot Order
Head (1), Neck (2), Shoulder (3), Back (15), Chest (5), Wrist (9),
Hands (10), Waist (6), Legs (7), Feet (8), Finger (11,12),
Trinket (13,14), Main Hand (16), Off Hand (17), Tier Tokens.

## Per-Item Row
- 34×34 item icon (with quality border color)
- Item name (colored by quality: epic=purple, rare=blue, etc.)
- Source provider tag: `[BisTooltip]`, `[FrogBiS]`, `[AtlasLoot]`
- Predicted roll badge: `NEED` (green), `GREED` (yellow), `PASS` (red)
- Reason text in grey: `(outgeared)`, `(collected)`, `(off-armor)`, `(wrong stat)`, `(tier token)`

## Outgeared / Greyed-Out Items
- Items the player has outgeared or already collected: icon desaturated, name text dimmed to 50% alpha
- Still fully interactive: hovering shows the game tooltip via `GameTooltip:SetHyperlink(itemLink)`
- Clicking an item link-posts it to chat (shift-click)

## Data Gathering
1. Query each registered BiS provider for all item IDs it considers BiS
   - **FrogBiS**: iterate `FrogBiS_Templates[specKey].items` + `FrogBiSDB.sets[specKey][*].items` → `{slot, id}` pairs
   - **BisTooltip**: iterate `Bistooltip_wh_bislists[class][spec][phase]` → slot entries with item IDs at keys 1-6
   - **AtlasLoot**: iterate all favourites lists → flat `{[itemID]=true}` tables (no slot info — derive from GetItemInfo equipLoc)
2. For each item ID, generate all difficulty variants using DIFFICULTY_OFFSETS: `{0, 137, -137, 543, -543, 747, -747, 680, -680, 884, -884}`
3. Group items by equipment slot (derived from GetItemInfo → equipLoc → EQUIP_LOC_TO_SLOTS)
4. Tier tokens: detected via name suffix (Protector/Conqueror/Vanquisher), slot derived from TOKEN_SLOT_KEYWORDS, grouped under a special "Tier Tokens" section

## Roll Prediction Logic
For each item, simulate what EvaluateRoll would decide (without actually rolling):

1. **Tier token for wrong class** → PASS
2. **Tier token for player class** → check outgear guard → NEED or GREED (outgeared)
3. **Off-armor type** (if armorFilterEnabled) → PASS or GREED per armorFilterAction
4. **Wrong primary stat** (if armorFilterEnabled) → PASS or GREED
5. **BiS + not collected + not outgeared** → NEED
6. **BiS + collected or outgeared** → GREED
7. **Downgrade check** (Pawn / StatWeights / ilvl) → GREED if downgrade

Simplified: since all items shown ARE BiS (from providers), the main differentiators are:
- Is it collected? → GREED
- Is it outgeared (Pawn or ilvl)? → GREED
- Is it off-armor/wrong-stat? → PASS/GREED
- Otherwise → NEED

## Item Caching
- GetItemInfo may return nil for uncached items
- On first open, fire off GetItemInfo for all IDs to request server data
- Use a C_Timer.After(0.5) retry loop (up to 3 retries) to populate rows as data arrives
- Show "Loading..." placeholder for uncached items

## Minimap Integration
- Add "BiS Preview" entry to the right-click dropdown menu (in MinimapIcon.lua BuildMenu)
- Calls `SLH.BisPreview:Toggle()`

## Slash Command
- `/slh bis` — toggles the preview window

## Files Changed
| File | Change |
|------|--------|
| `UI/BisPreview.lua` | New file — the entire preview window |
| `UI/MinimapIcon.lua` | Add menu entry for "BiS Preview" |
| `aSmoothLootHelper.lua` | Add `/slh bis` command, init call |
| `aSmoothLootHelper.toc` | Add `UI\BisPreview.lua` to load order |

## Difficulty Variant Display
Each base BiS item can appear in multiple versions. Group by base item name, show sub-rows:
- **Celestial** (lowest ilvl variant, typically base ID or LFR offset)
- **Normal** (base or +137 offset)
- **Heroic** (+543 offset)
- **Warforged** variants (+747 from normal, etc.)

Rather than showing every offset permutation, show up to 3 tiers per item name:
1. Look up the base item ID from the provider
2. Generate Normal ID = base, Heroic ID = base + 543, Celestial/LFR ID = base - 137
3. For each variant that exists (GetItemInfo returns non-nil), show a row
4. De-duplicate: if two providers list the same base item, show it once with both provider tags

## Frame Details
- Size: 500×600, movable, resizable via drag handle
- Uses `BasicFrameTemplateWithInset` for standard Blizzard look
- ScrollFrame with dynamic content height
- Strata: DIALOG (above game UI, below popups)
- ESC closes the window (added to UISpecialFrames)
- Position saved in aSmoothLootHelperCharDB.bisPreviewPos
