# Session 09 — Representative polish and one complete map

Milestone: **M6**. First choice: **Current builder / medium; GPT-6.1 Terra / medium for visual critique**. Alternative: **Claude Opus / medium; Sol or Opus / high for measured performance diagnosis**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: Lighting and Assets/settings in [architecture](reference/architecture.md); [performance checks](reference/verification.md).
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Prerequisite: The acceptance checks for [08-economy-reinforcement.md](./08-economy-reinforcement.md) must pass; use PROJECT.md for results rather than rereading that session.

## Work and acceptance

1. Polish the actual networked corridor first: movement, aim/recoil, step timing, hit/death feedback, breach warnings and voice/effects mix. Fix readability before decorating.
2. Lock a small material/free-prop palette, simple player body and basic movement/crouch/death poses. If no cohesive free rifle/hands fits, use a simple self-made viewmodel and convincing motion/feedback rather than starting a large art pipeline.
3. Finish representative ordinary/reinforced breaches: exposed edges/studs, material response, decals, controlled dust, transient audio and lighting. Cap decals, debris, particles and lights in data.
4. Apply that treatment across the existing graybox without expanding its footprint. Recheck route timing, collision snags, sightlines, spawn safety and sound obstruction after each art pass.
5. Finish lobby/menu/shop/HUD/help and persistent settings. Test small windows/common aspect ratios, non-color-only status, view-bob/shake controls and separate voice/effects volume.
6. Profile six moving players, simultaneous talk, multiple openings, charges and dust on both OSes. Reduce costly lights, overdraw and redundant queries before changing the resolution baseline.

**Done:** one coherent map, critical cues complete, no missing assets or navigation-blocking clutter. Effects convey danger while opponents remain readable. New players complete a match using in-game help. Meet the [measured budgets](reference/verification.md) or explicitly record the reduced target setting and remaining limits.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, set the active/next session in PROJECT.md to [10-private-release.md](10-private-release.md). If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
