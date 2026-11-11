# Cybernetic Enhancements changelog

## 0.2b

## Added

- **Schematic-based fabrication:** discover schematics in relic caches and contract rewards, right-click to learn them, then manufacture equipment in the new **Cyberware Fabricator**.
- **Schematic collection:** browse your discoveries in the Neural Archive, including where and when you learned them. Undiscovered entries display encrypted names and hidden icons.
- **Dedicated Upgrade Station:** improve supported implants through upgrade levels while keeping their existing model.
- **David-inspired Militech Experimental Sandevistan**, alongside local time dilation that slows eligible enemies and projectiles.
- **Sandevistan holographic afterimages**, activation effects and configurable visual and audio settings.
- **Ripper Station holograms** with body-slot highlights.
- **Relic-cache leads:** ask a Fixer or Netrunner about nearby caches to receive coordinates and a tuned compass. The compass disappears when you interact with its cache.
- **Configurable beta welcome message** with automatic update notifications.
- **Optional Neural Archive opening animation**, configurable through the in-game config screen.
- **Datapack customization** for cyberware upgrades, repair costs, fabrication and recycling, with documentation in `DATAPACKS.md`.

## Changed

- Replaced direct crafting recipes for fabrication equipment with schematic progression. Locked fabrication recipes remain hidden until learned, including in the wiki and JEI.
- Reworked the **Tech Station into the Repair Station**, separating repair, upgrading and recycling.
- Repair costs now scale with damage. Upgrading improves performance without repairing wear or changing the implant model.
- Reworked recycling around exact salvage previews and a clear **Recycle 1** action. Recovered materials reflect the item’s purpose and condition.
- Expanded Sandevistan behavior with model-specific slowdown, condition-dependent performance, repeated-use strain, overload penalties and recovery.
- Made higher-tier relic-cache puzzles more demanding through tighter timers, limited buffers and longer overlapping sequences.
- Updated relic-cache rewards to support fabrication and schematic discovery.
- Existing structures can now receive caches when loaded, provided eligible loot containers remain unopened.
- Refreshed station screens and the Neural Archive with more consistent controls, spacing, scrolling and scaling.
- Simplified Body Overview to emphasize core stats and relevant changes.
- Updated the wiki and added JEI fabrication integration.

## Fixed

- Relic caches failing to appear in desert pyramid and jungle temple treasure rooms.
- Relic Scanner missing tiered caches; caches now take priority over ordinary containers.
- Crashes caused by chunk processing during cache placement and NPC spawning.
- Cyberware HUD elements moving away from the hotbar at maximum GUI scale.
- Incorrect hand-slot hover highlights in the Ripper Station.
