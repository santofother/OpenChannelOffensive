# Open Channel Offensive — project memory

Updated: November 16, 2026. Status: Sessions 01–03 accepted; Session 04 visual slice implemented and measured on Mac, Windows run + human visual/playtest pending.
Session index: [session/README.md](session/README.md). Read only the active session below and relevant code; shared references are optional.

## Brief, pillars and loop

Solo developer, beginner in engine programming with multiple LLM-assisted games already built, 20+ hours/week; **3v3, Mac and Windows**, keyboard/mouse. **$0 asset budget**. First finish line: polished private Steam-hosted matches with friends.

- Responsive, deliberate close-quarters movement and readable combat.
- Stealth through sound: nearby enemies hear proximity speech; team radios can be stolen.
- Breaching changes routes and sightlines; reinforcement and stronger tools provide counterplay.
- Repeatable attack/defend bomb rounds with between-round equipment spending.
- Grounded industrial office at night: warm lamps/cool exterior; visibility takes priority.

Loop: buy/equip → prepare/infiltrate → listen/communicate → breach/fight → plant/defuse or eliminate → resolve/reward → next round and side swap.
References: [quiet approach](references/quiet-approach.png), [reinforced breach](references/reinforced-breach.png). Illustrations are targets, not proof of engine quality/performance.

## Scope and exclusions

Confirmed: 3v3, Mac/Windows, Steam multiplayer testing modeled on LastMage. Intended direction includes ordinary/reinforced destruction, penetration, physical voice/radios, bomb rounds and economy.
Proposed finishable scope: one single-floor office map/site, one shared rifle, two breach tools, one reinforcement tool, simple economy and private six-player sessions.
Still provisional: one site, exact rules, inventory persistence, radio leakage, and bounded modular destruction instead of the original all-walls ambition. Revisit that reduction explicitly after the destruction prototype.
Defer extra maps, operators, bots/campaign, progression, procedural buildings, arbitrary runtime fracture, structural collapse, ranked matchmaking, host migration and public backend services.

## Engine, architecture and decisions

- Godot **4.7.2 stable**, standard build, typed GDScript; version verified locally. Start Forward+; measure before expanding art. Match engine/export templates and pin addon/physics settings.
- Binary: `/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot`.
- Development machine: MacBook Pro, M1 Pro, 10 CPU / 16 GPU cores, 16 GB RAM, macOS 26.7.1. Windows baseline and Intel Mac support remain unverified.
- Reuse selected LastMage GodotSteam **4.23.2 / SteamMultiplayerPeer** and export patterns after compatibility checks. Inspected source uses **480 / Spacewar**, not a dedicated game app ID. New FPS lobby key, build/protocol identity and six-player cap are required.
- Steam connects players; a player host runs the authoritative match. Share exported builds for tests; Steam store/depot upload is separate future work. No paid server assumed.
- Host validates movement/actions and owns outcomes. Prototype local prediction/correction and remote interpolation before final animation work. LastMage client-authoritative movement is unsuitable unchanged.
- Stable wall IDs/revisions, authored damage states, matching collision and bounded penetration. Cosmetic debris is local. Test lighting before/after breaches; excluding a wall from baking alone may not fix surrounding baked light/shadows.
- Keep voice capture/codec/transport separate from host-authorized recipient policy and spatial playback. Candidate LastMage capture uses Godot input + ADPCM; replace its hearing rules and defaults for this game.
- Use scenes/signals/Resources, simple modules, exposed tuning and a tiny license-audited asset palette. Add no generalized framework or paid dependencies.
- LastMage reference: `/Users/santofothergill/PersonalProjects/LastMage`. Keep read-only; selectively copy independent pieces. Do not inherit its agent workflow or automatic publishing rules. Its older Steam guide differs from current voice code and player cap.

## Model, effort and timing defaults

- Routine build: **Codex GPT-6.1 Sol / medium** first, **Claude Sonnet / medium** second, **Claude Opus / medium** third; keep the current builder when productive.
- Network/voice/round-rule implementation: Sol / high. Ambiguous architecture or a stuck diagnosis: Opus / high first, GPT-6 Astra / high alternative. Visual screenshot critique: GPT-6.1 Terra / medium, Opus / medium alternative.
- Simple questions/edits: current builder / low or medium. No default xhigh/max or mandatory second-model reviews. After two failed fixes, summarize evidence and diagnose before switching.
- Choose settings in the client; recommendations do not change actual settings. Each session lists its model/effort choices; the [full model reference](session/reference/models.md) is optional.
- M0 initial agent implementation/check/export target: **10–20 minutes**, based on user experience/reuse, possibly under 10; not measured yet. Cross-machine manual checks are separate. Old manual-development hour/month estimates are withdrawn. Calibrate later tasks from the first three sessions, not an assumed beginner coding pace.

## Run/build/check commands

From the repository root (`game/` is the Godot project; `tools/check.sh` verified passing):

```sh
GODOT_BIN=/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot
"$GODOT_BIN" --path game --editor
"$GODOT_BIN" --path game
./tools/check.sh   # import/parse, offline smoke, 2-process ENet host/join, build-mismatch rejection
mkdir -p build/windows build/macos
"$GODOT_BIN" --headless --path game --export-debug "Windows Desktop" ../build/windows/OpenChannelOffensive.exe
"$GODOT_BIN" --headless --path game --export-debug "macOS" ../build/macos/OpenChannelOffensive.app
```

Export templates 4.7.2 are installed (macOS + Windows). Smoke flags after `--`: `--capture[=dir]`, `--bench[=secs]` (windowed), `--smoke-offline`, `--smoke-host`, `--smoke-join=<ip>`, `--no-steam`, `--build-id=X`, `--port=N`, `--name=X`. Actual OS/Steam/microphone tests remain necessary after headless checks.

## Current milestone, known issues and next task

Current milestone: **M1 part 3 in progress** — Session 04 built and Mac-measured; M1 gate needs the human checks below.
Active session: [Session 04 — visual slice](session/04-visual-slice.md). Read this file next, not the entire session folder.
Sessions 01–03 accepted by the user's reports.

Built (Session 04, pending acceptance): `scripts/world/surfaces.gd` (`Surfaces`: cached code-generated PBR palette — plaster, carpet, ceiling tile, metal plate, trim, glass, wood, etc.; world triplanar, no imported textures); `office_set.gd` (`OfficeSet`: AgX tonemap, SSAO, light glow, night sky; warm practicals = 2 corridor + room + desk-lamp **shadowed spots**, unshadowed fills, duct bulkhead lamp; cool shadowed moon through a new 3-pane exterior window (glass is solid); restrained dressing — frames, baseboards on non-breachable runs, notice board, plants, 2 desks/chairs/monitors, cabinets, whiteboard, blinds; exterior yard, fence, warehouse, street light, van); `standin.gd` (`StandIn` operator silhouettes, red/blue team arm bands; practice targets now use them, collider 0.5x1.75x0.3); `scripts/player/viewmodel.gd` (procedural rifle/gloves/held charge with hip↔ADS, bob, recoil, reload dip + mag drop, tool lower/raise; uses 4.7 material `fov_override` + `z_clip_scale` so it doesn't clip into walls; cosmetic only); `WallModule` takes a material and adds cosmetic `BreachDecor` (scorch decal + floor rubble, no collision, outside the part-matched mesh/shape set). All lighting is dynamic — no baking — so breached states light/shadow correctly by construction. Menu button renamed "Office visual slice (offline)" = the restartable demo (T restart).
Evidence tools (windowed, also in exported builds via main.gd): `-- --capture[=dir]` saves 4 reference views + F1–F3, intact and breached; `-- --bench[=secs] [--bench-out=path] [--vsync]` drives a fixed walk → ordinary breach → room → doorway → heavy breach → shoot loop after 5 s warm-up. Code: `scripts/tools/slice_bench.gd`.
Evidence in `session/evidence/04/`: 14 captures (`A_quiet_approach`, `B_reinforced_breach`, `C_room_to_corridor`, `D_room_exterior`, F1–F3; `_intact`/`_breached`) and `bench_mac_m1pro_1080p.json`.
Measured (exported **debug** Mac build, M1 Pro, macOS 26.7.1, Metal 4.0 Forward+, 1920x1080 window at screen scale 2, VSync off, plugged-in state not recorded, 60 s): median 4.9 ms, p95 5.9, p99 6.8, max 29 ms, 0 frames >33 ms (~204 fps). Pre-breach p95 6.0 / post-breach p95 5.9 — breaching costs nothing measurable. ~290 draw calls avg (919 max), ~55k primitives, 272 MB VRAM, nodes 486→539 (bounded: marks capped, decor per breach). An earlier run whose first breach fell in warm-up showed one unexplained 583 ms hitch (likely first-use pipeline compile); not reproduced in the recorded run — watch for it.
Verified here: `./tools/check.sh` all pass (smoke tests unchanged); Mac + Windows debug exports build; `build/windows.zip` (36 MB) ready. Lighting/material target judged only by me from captures.
Not verified / remaining for acceptance: Windows run + same bench (`OpenChannelOffensive.exe --resolution 1920x1080 -- --bench=60 --no-steam --bench-out=C:\path\bench.json`) on a chosen Windows baseline; a second person running the demo; human judgement of look/readability (optional screenshot critique by GPT-6.1 Terra); viewmodel feel; mouse ADS with the viewmodel; whether the room is too dark near the back wall. Known: viewmodel/weapons are primitive placeholders; no real weapon assets yet (see [asset candidates](session/reference/asset-candidates.md) — no free modern rifle+arms+animation set exists; best plan is CC0 static guns animated in code); procedural sounds unchanged; glass blocks shots (no penetration yet).
Next task: run the Windows bench and a second-person playtest, record results here, then accept Session 04 and move to [Session 05](session/05-networked-combat-destruction.md).

Built (Session 03, accepted): keys 1/2/3 rifle / ordinary charge / heavy charge, LMB fire or place, RMB aim, **R reload, T full round restart** (swapped from the first build at the user's request; Session 02's old "R reset" is now T). `scripts/player/loadout.gd` (rifle, ammo 30/90, reload, charges 3 ordinary + 2 heavy, HUD: crosshair, ammo, placement ring green/red, armed-charge warning/"BACK AWAY", hit marker, capped 24 bullet marks); `scripts/player/ballistics.gd` (aim ray from camera, real shot from the off-axis muzzle; cover between eye and muzzle, or hit before the aim point, blocks the shot); `scripts/world/wall_module.gd` (`WallModule`: INTACT→BREACHED only, revision, mesh+collision rebuilt from one authored part list = 1.2 x 2.1 doorway-style opening with jambs + lintel; ordinary panel needs ordinary charge, reinforced needs heavy, wrong tool rejected with a message); `charge.gd` (countdown 3 s / 4 s, beeps); `fx/breach_effects.gd` (cosmetic dust+chunks, max 3 bursts, nonblocking); `fx/proc_audio.gd` (placeholder sounds synthesised in code); `practice_target.gd` (layer 3, 100 hp, rifle 20 dmg). Tuning: `data/weapon_tuning.tres`. Graybox breachable panels: Divider_B (reinforced), Divider_C and Divider_D1 (ordinary), all into the room; three targets.
`./tools/check.sh` runs import, offline, graybox, `--smoke-combat` (shooting, reload, cover/muzzle block, rejections, charge fuse, state transitions, mesh/collision match, walkable openings, effect cap, restart) and ENet checks — all pass after the keybind swap.
Known/not done: no bullet penetration, charges don't hurt players, offline only (no replication until Session 05), breach opening fixed at panel centre, lighting after breach handled in Session 04. Run: `"$GODOT_BIN" --path game`, menu button "Office visual slice (offline)".

Built (Session 02, accepted): `scenes/graybox.tscn/.gd` (code-built level, 1 unit = 1 m: corridor 2.9 m wide x 13 m, room, doorway 1.0x2.1, window sill 1.0 / head 2.0, reinforced wall sections (dark, thicker), 1.5 m low-ceiling duct, scale figure/crate, omni lights, fixed cameras F1–F3, F4 back to player); `scenes/player.tscn` + `scripts/player/player.gd` (CharacterBody3D walk/sprint/hold-crouch, no jump/lean, mouse capture on start, Esc releases / click recaptures, T reset, sensitivity + FOV sliders persisted to `user://settings.cfg`; crouch release is blocked while the standing capsule would hit a ceiling); tuning in `data/player_tuning.tres` (`PlayerTuning`). Menu button "Graybox movement test (offline)" opens it; "Back to menu" returns. `./tools/check.sh` now includes a headless graybox smoke (walls hold east/west, standing blocked at duct, crouch passes, no standing up under duct, doorway passable, reinforced wall and window sill block, reset, eye height) — all pass.
Playtest passed; originally unverified: feel/responsiveness of acceleration and speeds (walk 4.0, sprint 5.8, crouch 2.0 m/s), mouse look feel and sensitivity range, scale impression, snagging on door/window frames, mouse capture/release on Mac and Windows, the pause panel layout, how the three fixed cameras look. Lighting is unjudged. Run: `"$GODOT_BIN" --path game`, then the menu button. Walls are plain colliders; stable wall IDs/damage states come in Session 03.

Built (Session 01): local Git repo (committed as 5e3da1a; build id `0.1.0-p1+5e3da1a`; re-commit and re-export together so host/clients match); `game/project.godot` (Jolt, input map, ETC2/ASTC on for Mac export); autoloads `NetworkManager` (6-player cap, `build_id` = version-protocol+commit, host rejects mismatched build or full match with clear messages) and `SteamManager` (app 480, lobby key `openchanneloffensive_m0`, lobby build check, graceful failure when Steam is missing); `scenes/main.tscn` room + capsule roster + host/join/leave UI (Steam and ENet local test); `addons/fps_export` (commit stamp, steam_appid copy); GodotSteam 4.23.2 osx+win64 libs only; export presets Mac universal (ad-hoc signed, mic description, bundle `com.santofother.openchanneloffensive`) and Windows x64.

Verified here: check.sh passes; Windows and Mac debug exports build; exported Mac app launches headless and initialises Steam as the logged-in user.
Not verified: exported Windows build running; Steam host/join between Mac and Windows (either direction), leave/reconnect, Steam full-lobby message (cap is passed to Steam createLobby; message mapped for code 4, untested); microphone prompt on Mac; Windows hardware/testers not chosen; first Mac launch may need Gatekeeper right-click Open for ad-hoc builds. Only the Mac libs for debug template were bundled in the Mac export; release export not tried.
(Session 01 history) Exports rebuilt from commit 5e3da1a (Mac build reports that id; `build/windows.zip`, 34 MB, ready to send). Next task: send the Windows zip to a tester, run Mac-host/Windows-join and reverse over Steam, record results/hardware here, then mark Session 01 done and move to Session 02.

## Working agreement

Read this file first, then only the linked active session and relevant code. Consult only the shared reference sections that task requires. Update the active-session link when its acceptance checks pass; keep it active if checks are pending. One editing agent at a time; no subagents unless requested. State goal and observable acceptance criteria before implementation. Make small complete changes, test consequential logic, and distinguish verified results from manual/unverified checks. After two failed fixes without progress, summarize evidence and choose a diagnostic step. Keep this memory current; do not append conversation history or create a second status board. End with changes, verification, playtest steps and the next task.
