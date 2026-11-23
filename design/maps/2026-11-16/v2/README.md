# Two-site map research and concepts

Updated November 17, 2026: **Lightwell revision 2** adds interior site rooms and close-quarters partitions. The canonical JSON and Lightwell SVG/PNG are current; the original concept image and comparisons below describe revision 1. New movement has no sprint: primary 2.8 / secondary 3.15 / empty hands 3.4 m/s. The checked 56.7 m illustrated rotation takes a theoretical 20.25 s with a primary, excluding acceleration, doors and combat. Physical shot/melee wall openings and breakable cover are implemented; human balance remains open.

November 16, 2026. Switchboard and Twin Wing remain proposals. Lightwell now has a first playable engine graybox; balance and human acceptance remain open. The initial comparison recommended Twin Wing; the user subsequently chose **Lightwell for detailed planning**. The current map direction is [Session 09.5 — Lightwell](../../../../session/09.5-lightwell-map.md). The comparisons below preserve the reasoning and tradeoffs of the original study.

## Confirmed requirements

- 3v3; grounded industrial office at night; close-range rifle combat, sound-based stealth, attack/defend bomb rounds.
- Two alternative plant sites: attackers can plant at **either A or B**.
- **Every wall can be destroyed and every wall can be reinforced**, including exterior walls. There are no permanent wall chokepoints, designated-only breach panels, or inaccessible wall-enclosed cores in these proposals.

The one-floor layout, dimensions, site rooms, props, staging positions and detailed round/equipment rules remain proposals. Any wall being eligible does not establish an unlimited supply of reinforcements or explosives; quantities, price, placement timing, damage fidelity and prop durability are undecided. Floors/ceilings are outside this wall-specific clarification, not declared indestructible here. Reinforced walls remain destructible; exact counter-tool behavior needs design/testing.

## What the research means for this game

**Start with a specific tactical question.** Riot explains that its maps are built around particular experiences. Split's early central tower pulled too much combat away from the sites; a later version had too many connections. For this game, the question is whether three defenders can protect two sites while attackers change the connections. A central room must help rotations without becoming a position that controls the whole round. [Riot: The Creation of Split](https://playvalorant.com/en-gb/news/dev/the-creation-of-split/)

**Treat the intact plan as only one state.** Ordinary FPS advice about chokepoints is insufficient when any wall can open. My application here: compare intact rooms, several attacker-created openings, defender-created rotation holes, reinforced layouts, and a fully opened stress case. Use angled entrances and distributed positions rather than making one permanent wall solve the map. A more open state is not automatically better; it can erase useful territory and expose a plant from too far away. This is a design inference for our rules, not a proven formula from another game.

**Sightlines and room scale need first-person testing.** Riot's Ascent process explicitly iterates sightlines, encounter distances and opening widths in graybox. It also uses a visually clean player-height zone and memorable landmarks. Here, keep clutter sparse around heads and bodies, distinguish the two site rooms, and use the current 4.0 m/s walk and 5.8 m/s sprint to evaluate routes. The drawings are proposed metres, not evidence of FPS feel. [Riot: The Birth of Ascent](https://playvalorant.com/en-gb/news/dev/the-birth-of-ascent/)

**Provide approach space for a breacher.** Ubisoft's Consulate rework added cover at its garage entry and shortened long exterior sightlines. Our adaptation is a playable perimeter so arbitrary exterior walls are actually reachable. Staging and cover remain unvalidated: once walls are gone, they cannot be assumed spawn-safe. [Ubisoft: Consulate rework](https://news.ubisoft.com/en-us/article/3AIL3u5FXfuNCRTsmMpAhb)

**Make hearing changes understandable.** Ubisoft describes sound routing between connected spaces and explains that destruction changes those paths, creating both useful information and difficult-to-diagnose behavior. For this game, wall damage/reinforcement should produce a consistent, learnable hearing result. These concepts do not assume that an intact wall is soundproof or that a reinforcement silences voice. Test local speech and stolen-radio playback separately as their rules develop. [Ubisoft: Siege sound status report](https://www.ubisoft.com/en-au/game/rainbow-six/siege/news-updates/HyDyYTuRkWtyYQ3WDFeEL/rainbow-six-siege-status-report)

**Night atmosphere must preserve target visibility.** Ubisoft's map lighting team describes reducing visual noise and balancing shadow cost against visibility. Keep warm practicals and cool exterior light, but inspect silhouettes in the actual combat positions before adding decoration. All-walls destruction also means lighting and sound must remain consistent through many simultaneous holes. [Ubisoft Toronto: Modernizing Maps](https://toronto.ubisoft.com/behind-the-wall-modernizing-maps-in-rainbow-six-siege-x/)

## Twin Wing — initial recommendation before Lightwell selection

[Wireframe](wireframes/c-twin-wing.png) · [Editable SVG](wireframes/c-twin-wing.svg) · [Concept image](concepts/c-twin-wing.png)

28 × 24 m building. A is Records in the northwest, B Electrical in the northeast. A shared Server room separates the sites. Below are two approach wings, a Cross Hall, a normal playable Utility room, and a broad Loading Lobby. Exterior approaches run around the building. Attackers stage south.

**Pros:** The most compact of the three; near-symmetric approaches make initial timing easier to tune. A defender can help the other site without a long lap around the building. The sites have distinct room identities while the middle supports a third player who listens, rotates and responds. Universal destruction creates short rotations and unconventional entries without requiring an extensive room network.

**Cons:** Several openings between the sites and Server could make the sites feel like one large arena. The shared room may become too influential, allowing one player to delay both attacks. Similar wings can become predictable. Exterior breaches on both sides can produce too many simultaneous angles for three defenders.

**First playtest question:** Does opening the shared room create interesting retakes, or let a player effectively control both plant pockets? Test a fast three-player site rush and a two-plus-one split, then repeat with different reinforcement placements. Break the middle walls deliberately; do not rely on the server prop being a permanent barrier.

## Switchboard — more room-to-room maneuver

[Wireframe](wireframes/a-switchboard.png) · [Editable SVG](wireframes/a-switchboard.svg) · [Concept image](concepts/a-switchboard.png)

30 × 24 m building. A Server is northeast; B Workshop is southwest. A broad Connector links Office/Electrical and the Meeting/Archive routes. Attackers stage southeast to make approaches toward the two diagonal sites less one-sided than a southwest spawn.

**Pros:** Distinct sites and several short room transitions suit listening, feints and rotations. Reinforcing the Connector changes the value of the surrounding rooms; breaching adjacent rooms offers alternate routes. The diagonal site arrangement makes a site switch consequential and gives the third defender a meaningful supporting role.

**Cons:** More room boundaries and wall faces to monitor. The central connector can dominate movement if its approaches are too readable to a holder. Long cuts across aligned partitions may expose several rooms at once. A wrong rotation costs more time than in Twin Wing; southeast staging still needs actual A/B approach timing and spawn-exposure checks.

**First playtest question:** Can a defender leave one site to support the other and still make a useful decision, or does the first feint decide the round? Open consecutive Office/Connector/Electrical walls and check whether one firing lane controls too much space.

## Lightwell — strongest landmark, highest complexity

[Wireframe](wireframes/b-lightwell.png) · [Editable SVG](wireframes/b-lightwell.svg) · [Concept image](concepts/b-lightwell.png)

32 × 28 m building. A Server is northeast, B Loading southwest. A walkable courtyard has normal north/south doors, surrounded by an interior ring. Every courtyard wall can also be breached and reinforced. Attackers stage southeast.

**Pros:** A strong visual landmark helps orientation and callouts. Players can use the ring, cross the courtyard or open new courtyard connections. Opposite-corner sites give feints and site changes a clear purpose. The courtyard naturally supports the project's warm interior/cool exterior lighting contrast.

**Cons:** Largest floor and longest illustrated rotation; with six players, some rooms may become empty travel. Open courtyard walls can expose the whole center from multiple directions. More visual and acoustic connections increase clearing and implementation complexity. Exterior plus courtyard wall faces increase the number of possible threats to both sites.

**First playtest question:** Does the courtyard support useful decisions, or become a dangerous shortcut everyone avoids? Test it with all courtyard walls opened, and compare defenders' ability to retake B after an A feint. Likely the first candidate to shrink if six-player tests feel sparse.

## Route estimates and verification

Each wireframe draws **one example intact A↔B route**, not the shortest route in every state. Distances use the drawn centerline, without acceleration, peeking, combat or stopping. The estimates are not round timers or proof of balance.

| Layout | Drawn route | Walk at 4.0 m/s | Sprint at 5.8 m/s |
|---|---:|---:|---:|
| Twin Wing | 27.5 m | 6.9 s | 4.7 s |
| Switchboard | 37.0 m | 9.3 s | 6.4 s |
| Lightwell | 49.9 m | 12.5 s | 8.6 s |

`check_geometry.py` verifies exactly two site zones; every wall marked destructible and reinforceable; complete non-overlapping floor coverage; and clearance for the illustrated intact route against the diagram's walls/props. Route sampling uses a 0.35 m body radius with 0.10 m wall half-thickness. Example reinforcement/cut lines must sit on real solid walls. Results are in [geometry-check.json](geometry-check.json). This validates diagram consistency, not the Godot implementation, tactical sightlines, acoustics, performance or spawn fairness.

The SVG/PNG wireframes are the layout reference. Concept images were made using the **built-in image_gen tool**, with the exact saved [prompt set](concept-prompts.json). They illustrate atmosphere and site identity; generated furnishings and door details can differ. In particular, Twin Wing's concept adds a central exterior lobby door and does not reproduce every Utility doorway correctly. Use its wireframe for door geometry. Concept perimeter fences are decoration, not an exemption from the every-wall rule or a decided map-boundary mechanic.

The interactive comparison's three layouts, example breach state, reinforcement overlay and complete wall removal passed browser runtime checks at 736 px and 320 px, with no horizontal overflow: [comparison-check.json](comparison-check.json). This checks controls and diagram rendering, not gameplay.

Regenerate/check:

```sh
python3 design/maps/2026-11-16/v2/build_maps.py
python3 design/maps/2026-11-16/v2/check_geometry.py
```

The PNGs are rendered from the SVGs; changing geometry requires re-rendering those previews. The interactive comparison is conversation content with the same layout data; its example holes and reinforcements are illustrative choices, never exclusive allowed surfaces. Its all-walls-removed state is a visibility stress case, not a claim that one round's equipment can remove every wall.

## Suggested next step

Follow the detailed [Lightwell Session 09.5 plan](../../../../session/09.5-lightwell-map.md) when that session becomes active. The first graybox and universal bounded-cell wall interaction are now implemented. This study preserves revision 3 of Lightwell in `layouts.json`. The game reads the current revision from `game/data/maps/lightwell.json`. Run the tactical graybox tests before evaluating balance or final art. Start with one defender near each site and one flexible position, then let players change that setup.

Try both teams on each side, a fast rush, a split, a fake/site switch, defensive rotation holes, attacker exterior breaches, and several reinforcement patterns. Record first-contact position, plant/retake outcomes, actual site-switch time, whether a holder can cover both sites, and which direction players think speech comes from. Repeat key rounds with multiple connected wall breaches. Check broad destruction for target visibility, sound consistency and frame-time spikes. A small private test can find problems; it cannot establish a reliable 50/50 balance statistic.
