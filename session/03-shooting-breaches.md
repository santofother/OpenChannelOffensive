# Session 03 — Rifle and breach interactions

Milestone: **M1, part 2**. First choice: **Codex GPT-6.1 Sol / medium**. Alternative: **Claude Sonnet / medium**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: [Destruction](reference/architecture.md#destruction); raise the current builder to high only for a reproduced state/collision bug.
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Prerequisite: The acceptance checks for [02-controller-graybox.md](./02-controller-graybox.md) must pass; use PROJECT.md for results rather than rereading that session.

## Work and acceptance

1. Add primitive rifle, aim, hitscan, reload, targets and restrained feedback. Combine aim ray with muzzle obstruction checks so nearby cover blocks shots appropriately.
2. Implement ordinary/heavy test charge actions, placement validity, warnings/countdown, authored breached states, collision changes, capped debris/dust and placeholder sound. Supported penetration need not create a walkable hole.

**Done:** aim/shoot/reload and target feedback work; nearby cover blocks muzzle shots. Correct tools open their corresponding panels, wrong tools are rejected, openings are traversable, damage meshes and collision agree, effects are bounded and restarting restores initial state. Add consequential damage/state tests. Final reference lighting is Session 04; the full M1 gate remains pending.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, set the active/next session in PROJECT.md to [04-visual-slice.md](04-visual-slice.md). If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
