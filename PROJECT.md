# Open Channel Offensive — project memory

Updated: November 15, 2026. Status: M0 implemented and exportable; cross-machine Steam acceptance pending.
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

Export templates 4.7.2 are installed (macOS + Windows). Smoke flags after `--`: `--smoke-offline`, `--smoke-host`, `--smoke-join=<ip>`, `--no-steam`, `--build-id=X`, `--port=N`, `--name=X`. Actual OS/Steam/microphone tests remain necessary after headless checks.

## Current milestone, known issues and next task

Current milestone: **M0 setup/export/Steam compatibility** — implementation done, manual cross-machine acceptance pending.
Active session: [Session 01 — Steam foundation and exports](session/01-steam-foundation.md). Read this file next, not the entire session folder.
After its acceptance checks pass: [Session 02 — FPS controller and graybox](session/02-controller-graybox.md).

Built (Session 01): local Git repo (committed as 5e3da1a; build id `0.1.0-p1+5e3da1a`; re-commit and re-export together so host/clients match); `game/project.godot` (Jolt, input map, ETC2/ASTC on for Mac export); autoloads `NetworkManager` (6-player cap, `build_id` = version-protocol+commit, host rejects mismatched build or full match with clear messages) and `SteamManager` (app 480, lobby key `openchanneloffensive_m0`, lobby build check, graceful failure when Steam is missing); `scenes/main.tscn` room + capsule roster + host/join/leave UI (Steam and ENet local test); `addons/fps_export` (commit stamp, steam_appid copy); GodotSteam 4.23.2 osx+win64 libs only; export presets Mac universal (ad-hoc signed, mic description, bundle `com.santofother.openchanneloffensive`) and Windows x64.

Verified here: check.sh passes; Windows and Mac debug exports build; exported Mac app launches headless and initialises Steam as the logged-in user.
Not verified: exported Windows build running; Steam host/join between Mac and Windows (either direction), leave/reconnect, Steam full-lobby message (cap is passed to Steam createLobby; message mapped for code 4, untested); microphone prompt on Mac; Windows hardware/testers not chosen; first Mac launch may need Gatekeeper right-click Open for ad-hoc builds. Only the Mac libs for debug template were bundled in the Mac export; release export not tried.
Exports rebuilt from commit 5e3da1a (Mac build reports that id; `build/windows.zip`, 34 MB, ready to send). Next task: send the Windows zip to a tester, run Mac-host/Windows-join and reverse over Steam, record results/hardware here, then mark Session 01 done and move to Session 02.

## Working agreement

Read this file first, then only the linked active session and relevant code. Consult only the shared reference sections that task requires. Update the active-session link when its acceptance checks pass; keep it active if checks are pending. One editing agent at a time; no subagents unless requested. State goal and observable acceptance criteria before implementation. Make small complete changes, test consequential logic, and distinguish verified results from manual/unverified checks. After two failed fixes without progress, summarize evidence and choose a diagnostic step. Keep this memory current; do not append conversation history or create a second status board. End with changes, verification, playtest steps and the next task.
