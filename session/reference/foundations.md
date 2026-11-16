# Engine, Steam and reuse

Optional reference: read only when the active session needs it. [Current project memory](../../PROJECT.md) owns status and the active-session pointer.

Use **Godot 4.7.2 stable, standard build, typed GDScript**. The local binary reports `4.7.2.stable.official.ed1daf0bf`, matching the [official stable release](https://godotengine.org/download/archive/4.7.2-stable/). Pin engine, export templates, physics settings and addon version. Upgrade to fix a demonstrated issue rather than by habit.

Binary: `/Users/santofothergill/Downloads/Godot.app/Contents/MacOS/Godot`.
Development machine: MacBook Pro, M1 Pro, 10 CPU / 16 GPU cores, 16 GB RAM, macOS 26.7.1. Windows hardware and minimum supported specification are still unknown.

Start with Forward+ for the desktop visual evaluation; record the actual driver on each platform. The [renderer overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) describes the backend options. Measure rather than assuming Mac and Windows will perform alike. Reconsider Godot only if the small visual/network experiments show a concrete blocker; do not maintain a second engine implementation.

Reuse selected pieces from `/Users/santofothergill/PersonalProjects/LastMage/the-last-fire-mage/` after checking dependencies and license notices. Keep LastMage read-only and the new project's files independent.

| Existing source | Reuse | Adaptation needed |
| --- | --- | --- |
| `addons/godotsteam/` | Candidate pinned GodotSteam 4.23.2 with SteamMultiplayerPeer | Verify Mac universal / Windows x64 native libraries and export packaging |
| `core/steam_manager.gd` | Steam init, lobby list/join, invites | Unique FPS lobby key, six slots, test access and build/protocol validation |
| `core/network_manager.gd` | Session lifecycle and version-check patterns | New FPS simulation authority; source currently allows 10 players despite older six-player documentation |
| `core/voice_manager.gd`, `core/voice/` | Candidate capture, ADPCM, jitter/sequence handling, diagnostics | New hearing policy, routing, gain, radio logic and tests |
| `export_presets.cfg`, `addons/lastmage_export/` | Export/library packaging and build stamping | New identity, output paths, Mac signing and microphone settings |
| `docs/STEAM_EXPORT_AND_TESTING.md` | Outline for tester instructions | Rewrite against actual new builds; some voice instructions are stale |

LastMage's client-authoritative movement is unsuitable unchanged for this FPS. Its current voice code uses Godot microphone capture plus ADPCM; it does not use Steam's voice capture despite older guide text. Its agent-management workflow and automatic release-publishing rules are project-specific and do not transfer.

**Steam testing:** LastMage uses **app ID 480 / Spacewar**, not a dedicated game app ID. Continue that development approach, using a unique FPS game-key filter and build/protocol identity; verify them when accepting joins. [Valve's example](https://partner.steamgames.com/doc/sdk/api/example) documents Spacewar; [Steam lobbies](https://partner.steamgames.com/doc/features/multiplayer/matchmaking) handle discovery/invites while networking carries gameplay. Never reuse LastMage's lobby identity or publish under its app.

The player's computer hosts the authoritative simulation; Steam supplies the lobby/connection layer. Verify actual Internet/relay connectivity rather than assuming it. Export complete Mac/Windows folders and share them through the user's chosen existing channel. Steam must run on each test machine with separate player accounts. For shared-ID testing, start this game before inviting; provide filtered lobby discovery if overlay invites fail. Cold-launch invites under 480 are not a promised feature. Steam-enabled exports are distinct from Steam store/depot uploads; no upload or paid server is planned.
