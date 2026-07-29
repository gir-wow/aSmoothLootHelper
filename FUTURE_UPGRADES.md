# aSmoothLootHelper Future Upgrades

## Goals

- Improve roll decision quality and transparency.
- Expand provider ecosystem without destabilizing core roll logic.
- Add compatibility tracks for older Classic versions where practical.

## High Priority

1. Decision explainability panel
- Add a compact "Why this roll?" breakdown for each loot decision.
- Show rule order, matched rule, and key inputs (provider match, ilvl check, token class check, transmog state).

2. Tier token intelligence expansion
- Add token-to-piece mapping tables per raid tier.
- Check owned/collected status for all generated tier outcomes before auto-need.

3. Provider resiliency
- Add per-provider timeout budget and soft-failure handling to avoid blocking roll decisions.
- Add startup diagnostics listing provider health and last sync state.

## Medium Priority

1. Bank item cache for IsCollected checks
- Scan bank contents on BANKFRAME_OPENED and cache item IDs in saved variables.
- Use cached bank data in IsCollected so items stored in bank count as owned.
- WoW API only allows bank queries while bank frame is open, so cache must persist across sessions.

2. Rule simulator mode
- Build a test panel where users can paste item links and preview roll outcomes without live loot.

2. Smarter session behavior
- Add optional per-instance session memory (reset on dungeon/raid change).
- Add confidence tagging to repeated actions (manual override history and frequency).

3. Better debug tooling
- Add one-click "Copy last 100 debug lines" button.
- Add structured debug sections by subsystem (providers, thresholds, token checks, transmog checks).

## Older Classic Version Adaptation

## Version strategy

- Keep a stable core engine and route API differences through compatibility wrappers.
- Prefer feature flags that disable unsupported systems gracefully.

## Cataclysm Classic support target

1. Provider compatibility pass
- Validate BisTooltip/FrogBiS/AtlasLoot API usage against Cataclysm addon ecosystems.
- Add provider capability flags (supports normal-version matching, supports collected-state checks).

2. Token and tier logic
- Add Cataclysm token dictionaries and class mappings.
- Keep token downgrade guard active with expansion-specific ilvl references.

3. UI compatibility
- Confirm options panel and minimap integration for Cataclysm UI templates.

## Wrath Classic support target (optional)

1. Reduced feature profile
- Disable transmog need logic and any MoP-only assumptions.
- Keep core auto-greed threshold, armor filter, and token class matching.

2. Provider baseline pack
- Offer a minimal built-in provider or static table fallback when external addons are unavailable.

## Nice-to-Have Ideas

- Group loot profile presets (raid main run, alt run, transmog run, farm run).
- Optional whisper summary when auto-need triggers (for transparency with group leaders).
- Character gear snapshot caching for faster repeated checks in long raids.

## Suggested Delivery Plan

1. Trust and transparency cycle
- Decision explainability panel and better debug copy tools.

2. Data intelligence cycle
- Tier token outcome tables and stronger provider resiliency.

3. Expansion adaptation cycle
- Cataclysm support pass, then optional Wrath reduced-profile mode.
