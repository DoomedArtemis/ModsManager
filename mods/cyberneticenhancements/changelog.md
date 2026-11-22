# Cybernetic Enhancements changelog

## 0.4b

## Added

### Lifepaths

- Pick a lifepath when you first join a world: **Nomad**, **Corporate** or **Street Kid**. The choice comes before anything else, on a fullscreen screen with artwork for each path. Esc opens the pause menu over it.
- Every lifepath comes with its own perks, extra cyberware capacity and a few permanent skill ranks.
- Each lifepath has its own article in the Neural Archive.

### Skills

- A new **Skills** tab in the Neural Archive with 15 skills in four groups:
  - Social: Charisma, Intimidation, Streetwise, Deception.
  - Cyberware: Chrome Tolerance, Maintenance, Neural Resistance, Ripperdoc Rapport.
  - Technical: Fabrication, Scavenging, Engineering.
  - Survival: Resilience, Athletics, Street Medicine, Evasion.
- Every Street Cred level gives you one skill point. A rank costs one point, and each skill goes up to rank 10.
- Skills work on their own, with nothing to activate: better prices, higher contract pay, more cyberware capacity, slower wear and cyberpsychosis, faster crafting, more recycling yield, more health, less fall damage and so on.
- The tab shows your points, how far each skill is filled, what you get now and at the next rank, and everything your skills add up to. Hovering a greyed-out "+" tells you why you cannot spend on it.
- Fixers and Ripperdocs offer extra answers when a skill is high enough. Locked answers show the rank they need. Passing one earns a little trust and never gets in the way of a contract.
- You can reset all your skills for 25 eddies per rank you bought, after a confirmation. Ranks from your lifepath stay.
- A new **Skills** section in the Archive wiki explains how it all works and has an article for every skill.
- Servers can lower the maximum rank, switch resetting off or turn skills off completely.

### Street Cred

- Your name in the city now counts. Street Cred has levels from 1 to 100 with a rank title, shows on the HUD when it changes, has a leaderboard and a new **Reputation** tab in the Archive.
- You earn it from contracts, putting down cyberpsychos, defeating Max-Tac, hacking relic caches, learning schematics, archiving tarot cards and finding big chromium deposits. It is never lost, not even when you die.
- A higher name means better contract pay, faster trust, cheaper shops and access to dangerous contracts, and it changes how street gangs treat you.
- The wiki explains how to earn it and what it is worth.

### Map and minimap

- A full map in the Neural Archive (new **Map** tab), also opened directly with **M**.
- A minimap on your HUD, toggled with **Shift+M**. Size, range, opacity, corner, frame, markers, north lock, smoothing and caves can all be set in the map settings, along with waypoints and radar.
- The HUD visibility options have a new Minimap entry.
- When you die, a red marker shows where on the compass and map. It disappears after 30 minutes.

### World and quests

- **Shipping containers** wash up in the world with cargo inside. They come with a crate block and a Sealed Cargo item.
- **Salvage contracts:** bring back sealed cargo from a shipping container, whether you found it yourself or a contact lost it.
- A separate **Quests** creative tab holds the quest items and blocks.
- **Shakedown tribute:** a gang that respects your name may ask for tribute instead of a toll. You can also turn gangs away.
- Every Night City now has a **Fast Travel Terminal** where the village bell would be.

### Fast travel

- The **Fast Travel Terminal** lets you jump between terminals. Use or place one to add it to your map, then right-click any terminal to pick a destination from a fullscreen map. A trip costs 100 eddies and is refunded if the destination is gone.
- You dissolve into a hologram with a cyan scan over the screen and appear at the other end the same way. Activating, opening, departing, arriving and being turned away each have their own sound.
- The price can be changed, or terminals switched off, in the server settings.
- A city terminal has to be activated once before you can travel to it.

### Building blocks

- A new **Building Blocks** creative tab for decorative blocks.
- **Copper Cable:** a bare copper wire that sticks to any side of a block, like glow lichen. Wires join up by themselves along surfaces and round corners, and can be waterlogged.
- **Hanging Wire:** a dark iron wire you string between two blocks. Click one block face, then another, and the wire sags between them. Hang banners, lanterns and hanging signs from it, even in the middle. Hung lanterns give light, hung signs can be written on both sides, and everything sways in the wind, more so in rain and storms. Hitting the bare wire breaks it and drops everything hung on it.
- **Water Pipe:** a decorative iron pipe that connects to the pipes around it, in every direction.
- **Shutoff Valve:** a red handwheel valve that goes into the middle of a water pipe.
- **HVAC Duct:** a square sheet-metal duct that joins the ducts and vents around it.
- **HVAC Vent:** a slatted grille that sits on the side of a block, and ducts can connect to its back.
- **Building Gadget:** a tool that changes how building blocks connect. Use it to cut or mend the connection between wires, pipes and ducts, to take down a hanging wire, or to turn or remove a valve.

### Dialogue and calls

- **Face-to-face dialogue:** talk to NPCs right where they stand, with no window. Choose answers with the arrow keys and Enter, and open Shop, Services, Contracts and Customize with Z, X, R and N. All of these can be rebound.
- NPCs turn to face you and listen while you talk.
- A contact can now have up to three active contracts for you, each with its own card and hand-in and abandon buttons.
- You can abandon a contract over the phone, after a confirmation.
- You can talk to the leaders of world encounters the same way, and hand over quest items in the conversation.

### Title screen

- A **What's New** window opens on the title screen the first time you start 0.4. You can scroll it, and Done closes it. It fades in and out, and a "What's new in 0.4" link at the bottom left opens it again whenever you like.
- Don't want it? Turn off **Show Changelog Popup** in the client config. The link stays.

### Sounds

- New Sandevistan start and end sounds.

### Credits

- The shipping container models are by DreamWanderer, credited in the notices.

## Changed

### Dialogue

- The Fixer and NPC dialogue is rebuilt around face-to-face talking. The old transcript and answer lists are gone, and the shop, services and contract windows have new layouts.
- Many phone lines were rewritten to sound more natural and in-world, and "contract" and "job" often became "gig".
- A call about a failed contract now always ends with the answer, and calling about a changed contract now works when you have several.
- The pool of NPC names is much bigger, with several hundred names from Cyberpunk 2077, including Morgan Blackhand, Rache Bartmoss, Spider Murphy, Lizzy Wizzy and Meredith Stout.

### Gangs and encounters

- Shakedowns are now a conversation with the gang boss, not clickable Pay and Refuse links in chat.
- How often gangs pick on you, how many come, how hard they hit and how much they ask all depend on your Street Cred.
- A gang that kills the player it came to rob now takes the toll that was asked for.
- Med-Tec AV sites now sit on grass, or on whatever the biome has instead (sand, terracotta and so on), with the local flowers, ferns, bushes, cacti and snow put back, so there are no bare patches. They can now also appear in cherry groves.
- The Med-Tec AV lockout lasts 15 minutes again, and only triggers when you break the blocks of the build itself, not the ground around it.

### Quests

- Urgent contracts show their remaining time on every compass marker, not just in the title.
- Salvage contracts pay out, show up on the compass and can be recovered if lost. Rewards, trust gains and discoveries have been balanced.

### Interface

- The Archive has a new tab order that includes Map.
- The player inventory has a new look, with a dark grey "Inventory" label so it stays readable.
- Mod HUD elements such as quests, compass, contacts and tarot stay hidden until you have chosen a lifepath.
- Quest progress hides while the Street Cred display is showing.
- Joining a world without a lifepath no longer plays the join animation after you choose. You go from the choice straight into the game, and the beta welcome notice waits for you and arrives quietly.
- The Disclaimers and notices screen fades in and out.
- Falling bodies are cheaper to draw, which should help most with shader packs.

## Fixed

- Handing in a quest item on a failed patient contract no longer leaves the call open.
- Digging dirt under a Med-Tec AV no longer triggers its lockout.

## Removed

- The old branching dialogue trees, the Fixer's Transcript and Responses sections and its "Cache intel" option.
- The Pay and Refuse chat links on shakedowns.
- Quest items and blocks in the main creative tab. They moved to the Quests tab.

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
