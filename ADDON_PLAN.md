# aSmoothLootHelper — Implementation Plan

## Overview

A World of Warcraft MoP Classic addon that intelligently automates loot rolls based on roll history, item level thresholds, and (in a future phase) BiS list integration from third-party addons.

---

## Feature Summary

| Feature | Phase | Scope |
|---|---|---|
| Auto-greed on previously greeded items | 1 | Account-wide or per-character |
| iLvl threshold auto-greed | 2 | Per-character, configurable |
| BiS/Pre-BiS auto-need integration | 3 | Per-character, dependency on external addon |

---

## Phase 1 — Auto-Greed History

### Goal
When a loot roll begins for an item the player has previously chosen **Greed** on, automatically roll Greed again without prompting.

### Key WoW API

| API | Purpose |
|---|---|
| `START_LOOT_ROLL` event | Fires when a group roll starts. Provides `rollID`. |
| `GetLootRollItemLink(rollID)` | Returns the item link for the roll. |
| `GetItemInfo(itemLink)` | Returns `name, link, quality, ilvl, minLevel, type, subType, ...` |
| `RollOnLoot(rollID, rollType)` | Executes the roll. `0`=Pass, `1`=Need, `2`=Greed, `3`=Disenchant |
| `LOOT_HISTORY_ROLL_CHANGED` event | Can supplement tracking of what the player actually rolled. |
| `LOOT_ROLLS_COMPLETE` event | Fires when a roll window closes. |

> **Note:** In MoP Classic `RollOnLoot` must be called within a `START_LOOT_ROLL` handler or via a secure button. Test whether taint applies. If it does, a `SecureActionButton` approach may be needed (see Phase 1 → Taint Notes).

### Data Model

Stored in `SavedVariables` (account-wide, so alts benefit from the same history):

```lua
-- SavedVariables: aSmoothLootHelperDB
aSmoothLootHelperDB = {
  greedHistory = {
    -- key: itemID (number)
    -- value: { count = N, lastSeen = timestamp }
    [12345] = { count = 3, lastSeen = 1712000000 },
  },
  settings = {
    autoGreedEnabled   = true,
    autoGreedOnHistory = true,
    ilvlGreedEnabled   = false,   -- Phase 2
    ilvlGreedThreshold = 0,       -- Phase 2
    bisNeedEnabled     = false,   -- Phase 3
  }
}
```

Character-specific overrides (per-character SavedVariables):

```lua
-- SavedVariablesPerCharacter: aSmoothLootHelperCharDB
aSmoothLootHelperCharDB = {
  ilvlGreedThreshold = 346,   -- Phase 2: override per character
  bisNeedEnabled     = false, -- Phase 3
  collectedItems     = {},    -- Phase 3: set of collected itemIDs
}
```

### File Structure

```
aSmoothLootHelper/
  aSmoothLootHelper.toc
  aSmoothLootHelper.lua       -- Entry point, init, slash commands
  Core/
    RollManager.lua           -- START_LOOT_ROLL handler, roll decision engine
    History.lua               -- Greed history read/write helpers
    ItemUtil.lua              -- Item link parsing, itemID extraction, ilvl helpers
  UI/
    Options.lua               -- AceConfig / standalone options frame
  Compat/
    MoPAPI.lua                -- Any version shims if needed
  Libs/                       -- (optional) embedded LibStub, AceAddon, AceDB, etc.
```

### TOC File (MoP Classic)

```
## Interface: 50400
## Title: aSmoothLootHelper
## Notes: Automatically rolls greed on previously greeded items.
## Author: <you>
## Version: 0.1.0
## SavedVariables: aSmoothLootHelperDB
## SavedVariablesPerCharacter: aSmoothLootHelperCharDB

Libs\LibStub\LibStub.lua
Libs\AceAddon-3.0\AceAddon-3.0.lua
Libs\AceDB-3.0\AceDB-3.0.lua
Libs\AceConfig-3.0\AceConfig-3.0.lua
Libs\AceConfigDialog-3.0\AceConfigDialog-3.0.lua

Core\ItemUtil.lua
Core\History.lua
Core\RollManager.lua
UI\Options.lua
aSmoothLootHelper.lua
```

### Core Logic — RollManager.lua

```lua
-- Pseudocode outline
local function OnStartLootRoll(rollID, rollTime)
  local itemLink = GetLootRollItemLink(rollID)
  if not itemLink then return end

  local itemID = ItemUtil:GetItemID(itemLink)
  local _, _, quality, ilvl = GetItemInfo(itemLink)

  -- Phase 1: history-based auto-greed
  if settings.autoGreedOnHistory and History:HasGreeded(itemID) then
    RollOnLoot(rollID, 2)  -- 2 = Greed
    History:RecordGreed(itemID)
    return
  end

  -- Phase 2: ilvl threshold (see below)
  -- Phase 3: BiS need (see below)
end
```

### Taint Notes

In MoP Classic `RollOnLoot` is a protected function if called outside of a trusted event. `START_LOOT_ROLL` is a **hardware-equivalent trusted event** in classic clients, which means calling `RollOnLoot` directly inside the handler should be safe. Verify this during initial testing — if taint errors appear, the fallback is creating a hidden `SecureActionButton` that fires the roll via a click triggered from inside the handler.

---

## Phase 2 — iLvl Threshold Auto-Greed

### Goal
If enabled (per character), automatically roll Greed on any item whose item level is **at or below** a configured threshold for that character.

### Configuration
- Threshold is stored in `aSmoothLootHelperCharDB.ilvlGreedThreshold`.
- Enabled flag is `aSmoothLootHelperCharDB.ilvlGreedEnabled` (or falls back to account default).
- Configurable via `/slh` options panel or slash command: `/slh ilvl 346`.

### Logic Addition to RollManager

```lua
  -- Phase 2: ilvl threshold auto-greed
  if settings.ilvlGreedEnabled and ilvl <= settings.ilvlGreedThreshold then
    RollOnLoot(rollID, 2)
    History:RecordGreed(itemID)
    return
  end
```

### Priority Order (both Phase 1 + 2 active)

1. **Phase 3 BiS need** (highest priority — need beats greed)
2. **Phase 1 history greed**
3. **Phase 2 ilvl threshold greed**
4. No automatic action — player rolls manually

---

## Phase 3 — BiS / Pre-BiS Auto-Need Integration

### Goal
Automatically roll **Need** on an item when:
- The item (or a lower-quality version of it) appears on the character's **BiS or Pre-BiS list**, **and**
- The character has **not yet collected** that item (or its upgrade path).

### Dependency Model

Rather than hardcoding a single BiS addon, expose a **registration API** so any addon (RCLootCouncil BiS lists, AtlasLoot saved wishlists, a custom list, etc.) can register its data.

```lua
-- Public API: other addons call this to register a provider
-- aSmoothLootHelper:RegisterBiSProvider(providerName, providerTable)
--
-- providerTable must implement:
--   providerTable:IsBiS(itemID, characterName, realm) -> boolean
--   providerTable:IsCollected(itemID, characterName, realm) -> boolean
--   providerTable:IsNormalVersionOfBiS(itemID, characterName, realm) -> boolean
```

This keeps aSmoothLootHelper decoupled. The external addon registers itself on `ADDON_LOADED`.

### Built-in Fallback Provider (Optional)

A simple built-in provider that reads a hand-maintained Lua table (per character, edited by the player or importable via a string):

```lua
aSmoothLootHelperCharDB.bisList = {
  [itemID_heroic] = { normalVersion = itemID_normal, collected = false },
  ...
}
```

### Logic Addition to RollManager

```lua
  -- Phase 3: BiS need check
  if settings.bisNeedEnabled then
    for _, provider in ipairs(BiSProviders) do
      local isBiS      = provider:IsBiS(itemID, playerName, realm)
      local isCollected = provider:IsCollected(itemID, playerName, realm)
      local isNormal    = provider:IsNormalVersionOfBiS(itemID, playerName, realm)

      if (isBiS or isNormal) and not isCollected then
        RollOnLoot(rollID, 1)  -- 1 = Need
        -- do NOT record as greed history
        return
      end
    end
  end
```

### Collected Item Tracking

- Hook `LOOT_HISTORY_ROLL_CHANGED` or `BAG_UPDATE` + item scan to detect when the player receives an item and mark it collected in `aSmoothLootHelperCharDB.collectedItems[itemID] = true`.
- Alternatively, query `GetItemCount(itemID)` on login to seed the collected set.

---

## UI & Options

### Slash Command

```
/slh           → open options panel
/slh on|off    → toggle addon
/slh ilvl 346  → set ilvl threshold for current character
/slh ilvl off  → disable ilvl greed
/slh history   → print greed history summary
/slh reset     → clear greed history (with confirmation prompt)
```

### Options Panel (AceConfigDialog or custom frame)

- **General**
  - [ ] Enable aSmoothLootHelper
  - [ ] Auto-greed on history
- **iLvl Greed** (per character)
  - [ ] Enable iLvl auto-greed
  - iLvl threshold: [____] (numeric input)
- **BiS Need** (per character, Phase 3)
  - [ ] Enable BiS auto-need
  - List configured providers
  - Manual BiS list editor (import/export string)

---

## Event Flow Diagram

```
START_LOOT_ROLL fires
        │
        ▼
  GetLootRollItemLink(rollID)
        │
        ▼
  GetItemInfo → itemID, ilvl, quality
        │
        ▼
  [Phase 3] BiS need check ──► RollOnLoot(rollID, 1=Need) ──► RETURN
        │
        ▼
  [Phase 1] History check  ──► RollOnLoot(rollID, 2=Greed) ──► RETURN
        │
        ▼
  [Phase 2] iLvl check     ──► RollOnLoot(rollID, 2=Greed) ──► RETURN
        │
        ▼
  No action (player rolls manually)
```

---

## Implementation Milestones

### Milestone 1 — Skeleton & History Greed
- [ ] Create TOC, entry point, AceDB setup
- [ ] `ItemUtil.lua`: extract itemID from link
- [ ] `History.lua`: HasGreeded, RecordGreed, GetHistory
- [ ] `RollManager.lua`: hook `START_LOOT_ROLL`, implement Phase 1 logic
- [ ] Verify `RollOnLoot` taint behavior in MoP Classic
- [ ] `/slh` slash commands: on/off, history, reset

### Milestone 2 — iLvl Greed
- [ ] Extend settings with per-character ilvl threshold
- [ ] Add Phase 2 check to RollManager
- [ ] Options UI: iLvl toggle + threshold input
- [ ] `/slh ilvl N` slash command

### Milestone 3 — BiS Integration API
- [ ] Define and document provider interface
- [ ] Implement `RegisterBiSProvider` public API
- [ ] Implement collected-item tracking
- [ ] Built-in manual BiS list editor (import/export)
- [ ] Add Phase 3 check to RollManager
- [ ] Options UI: BiS section
- [ ] Write sample provider stub for future BiS addon authors

---

## Known Risks & Notes

| Risk | Mitigation |
|---|---|
| `RollOnLoot` taint in MoP Classic | Test early in Milestone 1; fallback to SecureButton if needed |
| Multiple rolls auto-fired before player can intervene | Add a `/slh pause` toggle; show a brief chat message for every auto-roll taken |
| Item link format changes between patches | Abstract all link parsing in `ItemUtil.lua` |
| BiS provider API breakage across addon updates | Version-stamp the provider interface; validate on registration |
| Player accidentally needs on a greed-only item (quality guard) | Before Phase 3 need: check `CanNeedOnItem(rollID)` return value |

---

## Recommended Libraries

| Library | Purpose |
|---|---|
| **AceAddon-3.0** | Addon object, module system |
| **AceDB-3.0** | SavedVariables with profile/character scoping |
| **AceConfig-3.0 + AceConfigDialog-3.0** | Options panel |
| **AceEvent-3.0** | Clean event registration |
| **AceConsole-3.0** | Slash command registration |

All available via [CurseForge Ace3](https://www.curseforge.com/wow/addons/ace3) or embeddable directly in the `Libs/` folder.
