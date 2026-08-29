# aSmoothLootHelper Changelog

## v1.5.0

### New Features
- Added Boss Loot Overlay: draggable in-game wanted-drop frame for current boss
- Added `/slh bossloot` toggle command
- Added `/slh bossloot test <boss> [normal|heroic|celestial|combined]` preview command
- Added `/slh bossloot clear` to exit preview mode
- Boss Loot Overlay combines LootReserve favorites and active BiS tracker items
- Boss Loot Overlay supports LootReserve and AtlasLootClassic MoP dungeon/raid loot data
- Boss Loot Overlay supports Normal, Heroic, Celestial, Combined, and Auto difficulty modes
- Added Boss Loot Overlay settings for enable/disable, difficulty mode, and background opacity
- Boss Loot Overlay rows are hoverable and show item tooltips
- Added LootReserve personal-reserve auto-roll support
- Added configurable LootReserve Main Spec and Off Spec reserve actions
- Added heirloom priority option to auto-greed matching-slot drops while a valid heirloom is equipped

### Bug Fixes
- Fixed FrogBiS saved sets not appearing in dropdown due to empty-items filter
- Fixed Pawn scale dropdown showing wrong or no scales by using `PawnGetAllScalesEx`
- Fixed startup loaded message version so it matches the packaged release
- Fixed AtlasLoot token reward matching when LootReserve data is not loaded
- Removed broad BisTooltip same-name fallback to avoid cross-difficulty/duplicate-name false positives outside known variant matching

### Improvements
- Delayed native loot roll submission slightly to avoid MoP roll-frame initialization misses
- Added AtlasLootClassic token-list expansion so tier-token bosses can match wanted tier rewards
- Added token reward matching through both LootReserve and AtlasLootClassic
- Deduplicated Boss Loot Overlay rows when the same item is found from multiple sources
- Merged duplicate item source labels, e.g. `Favorite, BiS`
- Refreshes Boss Loot Overlay when target, encounter, item cache, or instance difficulty changes
- Added support for FrogBiS active saved set item IDs in boss loot matching
- BiS Preview now exposes active configured item IDs for reuse by the boss loot overlay
- Debug Log loot history now keeps clickable item links with hover tooltips
- Pawn scale dropdown now prefers visible character scales from `PawnGetAllScalesEx`
- FrogBiS dropdown includes lazy-loaded/empty saved sets and scans class-matching saved sets

## v1.4.0

### Bug Fixes
- Fixed BisTooltip spec matching when using FrogBiS-style spec keys (e.g. "Blood Death Knight (P5 - BIS (Offensive))" now correctly maps to BisTooltip's "Blood tank")

### Improvements
- Renamed play modes: Farming → **Greed All**, Carry → **Pass All**; added `/slh mode greedall` and `passall` aliases
- Name-based IsCollected fallback — catches same-named items across difficulty tiers even when ID offsets don't match
- Expanded roll debug log: shows owned variants (by ID and name), difficulty upgrade detection

### Debug Log Overhaul
- BugSack-style WoW tab interface (CharacterFrameTabButtonTemplate) with native select/deselect styling
- Multi-session storage: up to 10 sessions persisted across reloads (each /reload starts a new session)
- **All Sessions** tab with `< Previous` / `Next >` navigation to browse individual sessions
- **Current Session** and **Previous Session** quick-access tabs
- **Loot History** tab — persistent color-coded log of all auto-rolled items with date, action, and reason
- Date separators and mode change markers in loot history
- Clear / Select All buttons work per-tab

## v1.3.1

### Bug Fixes
- Fixed FrogBiS dropdown only showing the base spec template, missing all phase/variant sets (e.g. P5 - BIS (Balanced), P5 - Prog (Survival))

## v1.3.0

### Bug Fixes
- Fixed BiS auto-need firing before checking all providers — if ANY provider says the item is already collected, it now correctly greeds instead of needing
- Fixed IsCollected treating lower-difficulty versions as "collected" — owning Normal no longer blocks needing on Heroic

### Improvements
- IsCollected now respects difficulty hierarchy: Heroic > Normal > Celestial/LFR (upgrade level irrelevant)
- Difficulty upgrades (e.g. have Normal, HC drops) bypass Pawn and outgear guards entirely — higher tier always wins
- Armor type and wrong-stat safety gates still apply regardless

## v1.2.3

### Bug Fixes
- Added a hard BiS auto-need safety gate: blocks auto-need on off-armor and wrong-primary-stat items even if armor filter is disabled

## v1.2.2

### Bug Fixes
- Fixed ItemUtil crash in tier-token downgrade checks (`attempt to call a nil value`) by adding a safe local debug helper

## v1.2.1

### Bug Fixes
- BiS Preview: switched to a private tooltip frame to avoid Pawn-related GameTooltip hook errors
- Updated startup version text to match packaged release version

## v1.2.0

### New Features
- BiS Preview window — scrollable list of all BiS items organized by slot
- Shows predicted roll action (NEED/GREED/PASS) with reason for each item
- Difficulty variants (Normal/Heroic/Celestial) generated automatically
- Filter buttons: All / Need only / No Pass
- Greyed-out items for outgeared/collected (still hoverable for tooltips)
- Shift-click to link items to chat
- Accessible via minimap right-click menu or `/slh bis`
- Async item loading via Item:ContinueOnItemLoad with 8s timeout fallback

### Improvements
- Always enforces armor type and primary stat checks in preview
- Name-based tier token detection fallback for MoP Classic compatibility
- Tier tokens correctly show PASS for wrong-class tokens

## v1.1.2

- Updated changelog format

## v1.1.1

### New Features
- Full Options UI redesign with split General/Advanced panels
- Minimap icon (left-click toggle, right-click mode menu)
- BisTooltip bislists integration with phase selection (PR/P5)
- FrogBiS named custom sets in dropdown selectors
- Per-provider enable/disable checkboxes
- Mode presets: Raiding, Farming, Carry, Custom
- Per-character greed history

### Bug Fixes
- Tier token false positive fix
- History no longer auto-greeds upgrades
- Cross-difficulty BiS matching via name fallback
- iLvl threshold slider textbox display fix
- Minimap icon circular mask

## v1.0.1

- AtlasLoot Favourites BiS provider
- Publishing format update

## v1.0.0

- Phase-aware BiS auto-need (BisTooltip + FrogBiS)
- Primary stat armor filter (pass/greed off-type)
- Tier token auto-need with class group detection
- Transmog auto-need for uncollected appearances
- Editable iLvl threshold slider
- Minimap icon settings
- BiS outgear guard (skip need when Pawn says no or ilvl gap >30)
- Options layout fixes, lockbox roll setting, default values display
