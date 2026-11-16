# Session 02 — FPS controller and graybox

Milestone: **M1, part 1**. First choice: **Codex GPT-6.1 Sol / medium**. Alternative: **Claude Sonnet / medium**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: The player/scene layout in [architecture](reference/architecture.md); no unrelated sections.
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Prerequisite: The acceptance checks for [01-steam-foundation.md](./01-steam-foundation.md) must pass; use PROJECT.md for results rather than rereading that session.

## Work and acceptance

1. Graybox one corridor and adjacent room at human scale, doorway/window, ordinary and reinforced wall sections, and fixed comparison cameras.
2. Add CharacterBody3D walk/crouch/look, mouse capture/release, sensitivity/FOV, collision and reset. Expose movement/camera tuning. Test crouch clearance; defer jump/lean unless routes require them.

**Done:** corridor and room are walkable at plausible scale; mouse capture/release, adjustable look, walking, crouching and reset work. Intact-wall collision holds; standing is blocked under low ceilings. Run import/boot checks and playtest responsiveness, scale and collision snagging. Do not claim the full M1 gate passes yet.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, set the active/next session in PROJECT.md to [03-shooting-breaches.md](03-shooting-breaches.md). If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
