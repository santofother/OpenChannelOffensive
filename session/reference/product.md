# Product and scope

Optional reference: read only when the active session needs it. [Current project memory](../../PROJECT.md) owns status and the active-session pointer.

Build a polished private multiplayer game that six friends can obtain, host through Steam, play to completion and replay. The core loop is buy/equip → prepare defenses or infiltrate → listen/communicate → breach/fight → plant/defuse or eliminate → resolve/reward → next round and side swap.

Pillars: responsive deliberate movement; readable combat; exploitable physical communication; breaching that changes tactical options; cohesive nighttime office atmosphere. References combine Rainbow Six Siege attack/defend rounds, Splinter Cell tension and CS-style spending. Match those qualities at a small scale before expanding content.

| Area | Proposed first finished version | Deferred |
| --- | --- | --- |
| Players | Confirmed 3 attackers vs 3 defenders, Steam player-hosted sessions | Dedicated servers, ranked play, host migration |
| Map | One compact single-floor office, one bomb site, two viable approaches | Extra maps, floors, second site |
| Combat | One shared rifle, aim/reload, health; armor only if useful | Gun roster, attachments, detailed body simulation |
| Tools | Ordinary charge, heavy charge, reinforcement kit | Specialized operators and gadget roster |
| Destruction | Modular wall states, bounded penetration, ordinary/reinforced differences | Arbitrary runtime fracture, collapse, physics rubble |
| Voice | Open proximity voice, team radio, stolen receive-only radio | Channel switching and acoustic simulation |
| Match | Short rounds, no round respawn, side swap, rematch | Competitive seasons, progression |
| Economy | Small shop, capped credits, tactical tool choices | Full persistent weapon/inventory economy |
| Presentation | Coherent industrial office at night, clear HUD and sound | Large character/animation production pipeline |

Confirmed requirements are the platforms, 3v3, Steam testing workflow and budget, alongside the established game direction. One site, exact rules and bounded destruction are **proposed scope choices**, not settled requirements. The original ambition is all walls breachable and shoot-through. Prototype two panels first, then extend proven modules across ordinary interior partitions. Proposed exclusions are floors, ceilings, structural supports and exterior boundaries. Make supported surfaces readable. If literally every wall is mandatory, reopen scope after M2 rather than treating an authored-panel prototype as proof.

Exclude campaign, bots, parkour, prone, advanced leaning, crafting, progression, procedural buildings, public backend services and mobile/console support. Add none just because a reference game includes it.
