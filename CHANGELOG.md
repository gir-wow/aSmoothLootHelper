# aSmoothLootHelper Changelog

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
