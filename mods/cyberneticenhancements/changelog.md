# Cybernetic Enhancements changelog

## 0.3b

## Added

- **Redesigned player HUD:** a quieter look for the whole overlay, with a health bar that fills smoothly when you heal. Show, hide, and restyle elements from the Neural Archive's HUD tab.
- **Quests in the Nether and the End:** contracts can now send you to other dimensions. Harder trips pay more, **+25% for the Nether and +35% for the End**.
- **Neural Link calls:** talk to contacts while you play. Use **K** for quick-call contacts and **Alt + number** to call, accept contracts, or arrange meetings. Contacts can also call you.
- **Player voice calls** through Neural Link, with optional **Simple Voice Chat** support.
- **Remote hand-in:** complete ready quests by calling the issuer from the HUD, and request replacements for lost delivery packages at a reduced reward.
- **Med-techs and Trauma Team coverage:** buy emergency rescue and revival for when you go down.
- **NPC dispositions:** NPCs track trust, mood, and aggression toward each player, and heal themselves in combat.
- **Personal journal:** browse a persistent event log from the main menu with search, filters, and sorting. Server history is saved locally and readable offline.
- **Compass HUD** with quest markers, turn-in markers, and named banner landmarks, plus personal markers (**Alt+M**) managed in the Neural Archive's new **Compass** tab.
- **Compact quest panels** for collection, elimination, survey, and travel progress.
- **Dropoff Point** and **Iron Quest Crate** for delivery contracts.
- **Chromium:** new ore, large veins, and ingots, with survey contracts to find it.
- **Tarot cards** to discover and scan in the world, with a collection browser.
- **Cyberpsycho encounters** with aftermath, plus **MaxTac** response squads, MaxTec guards, and street ripperdocs.
- **World encounters**, starting with **Med Tec AV**: a guarded medical outpost with its own crew, loot, and quest. A holographic barrier at its door shows whether the crew still deal with you or have turned hostile.
- **Sound design** for the interface, calls, contracts, NPCs, and encounters.
- **Join animation, launch intro, title slideshow, loading screen, and Flatlined death screen**, with restyled vanilla menus. All can be disabled in the config.
- **Interactive tutorial world** and **psychosis presentation** with intro, blindness, and recovery.
- **Jade tooltips** for NPCs, stations, crates, and caches.
- **Server-enforced client settings** for server owners, documented in `CONFIG.md`.
- **Compatibility defaults** when **FancyMenu**, **Drippy Loading Screen**, **PackMenu**, or **Custom Main Menu** is detected.
- **Banking history** with daily transactions and a player directory for transfers.
- **Debug commands** for encounters, dropoffs, holograms, and calls.

## Changed

- **Reworked crafting stations:** new layouts, a vertical implant status gauge, smoother progress animation, hopper and pipe **automation**, and correct GUI scaling.
- Expanded **JEI integration** to repair, upgrades, and recycling, with recipe transfer into stations.
- **Neural Archive** gains the Compass tab and journal access, and its tabs are reorderable.
- Updated the wiki and documentation.

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
