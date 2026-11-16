# Architecture and data

Optional reference: read only when the active session needs it. [Current project memory](../../PROJECT.md) owns status and the active-session pointer.

Create folders only when needed:

```text
game/
  project.godot
  scenes/          # bootstrap/menu, player, slice, office
  scripts/
    session/       # Steam adapter, lifecycle, compatibility
    player/        # input, controller, camera, interaction
    combat/        # rifle, health, hit validation, penetration
    destruction/   # wall state, breach, reinforcement
    match/         # phases, teams, objective, economy
    audio/         # sound and voice capture/transport/routing
    ui/            # lobby, HUD, shop, settings
  data/            # Godot Resources for tuning
  assets/          # meshes/materials/audio and ASSET_LICENSES.md
  addons/          # pinned GodotSteam and export helper
tools/             # checks, focused network tests, exports
tests/             # consequential rules and integration cases
build/             # ignored export output
references/        # existing concept images
```

Prefer scenes, nodes, Resources and signals. Begin with a session service and match owner; add no service framework, ECS, custom editor or generalized ability system. Put shared movement, weapons, wall materials, tools and match tuning in Resources. Keep costs/rewards outside UI code.

## Authority

clients send input/action requests; host checks sender, phase, life state, team, ownership, distance, line of sight where relevant, cooldown and ammo. Only host commits damage, death, objective progress, credits and wall transitions. Prototype fixed-step input processing, local movement prediction/correction and remote interpolation in M2. Start measuring at 60 Hz simulation / 20 Hz snapshots; these are provisional. Keep offline actions on the same gameplay methods. Do not assume Steam integration supplies FPS prediction or hit validation.

## Replication

use stable entity/wall IDs and round IDs. Movement snapshots can tolerate loss; purchases and state transitions require reliable ordering, action IDs and duplicate/stale rejection. Separate voice from reliable gameplay traffic. Send a complete current state to joining clients; during matches, joins wait until the next round. Reject incompatible builds with a visible reason. A listen host remains trusted and can cheat; no anti-cheat product is in scope.

## Destruction

each module stores material, damage state, reinforcement and revision. Define valid transitions and replicate the resulting state. Change visual mesh, collision and penetration state together. Use a few authored openings; decorative bullet marks do not create collision holes. Bound penetration queries by supported materials/thickness, maximum surfaces and decreasing damage. Keep debris local, capped and nonblocking. Test corner shots, openings and back-to-back walls.

## Lighting

try direct practical lights with simple ambient/fill before expensive GI. Compare one bounded alternative if needed, using the [GI overview](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/introduction_to_global_illumination.html). Excluding a destructible wall from baking alone does not fix baked shadows/indirect light on surrounding geometry. Verify intact and breached states; choose a dynamic/mixed solution only from measurements. Visibility beats darkness, fog and expensive effects.

## Voice

separate capture/codec/packets from eligibility and playback. Reuse the working LastMage path selectively; avoid new native dependencies without a measured need. Host computes eligible recipients using alive/dead state, proximity, team and stolen-radio ownership. Do not distribute unauthorized audio to everyone and merely turn it down locally. Deduplicate radio/proximity playback; purge queues on death, reset and disconnect. Start with simple obstruction checks. [Microphone documentation](https://docs.godotengine.org/en/stable/tutorials/audio/recording_with_microphone.html) is background; actual capture/permissions need both-platform tests.

## Assets/settings

use glTF meshes with editable source and a small coherent material palette. Record source URL, author, license text, attribution and modifications before importing free assets. Prefer simple self-made geometry over lengthy searches. AI concept images do not supply rigged/UV-mapped production assets. Settings include sensitivity, FOV, rebinds, resolution/quality, microphone device, hard mute, and separate effects/voice volume; persist locally.
