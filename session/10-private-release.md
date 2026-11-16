# Session 10 — Private release candidate

Milestone: **M7**. First choice: **Codex GPT-6.1 Sol / medium**. Alternative: **Claude Sonnet / medium; Sol or Opus / high for reproduced blockers**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: [Export foundations](reference/foundations.md) and [verification](reference/verification.md); do not reread unrelated design references.
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Prerequisite: The acceptance checks for [09-polish-map.md](./09-polish-map.md) must pass; use PROJECT.md for results rather than rereading that session.

## Work and acceptance

1. Freeze features. Fix crashes, desync, broken joins, stuck rounds, unfair sightlines and unintelligible voice before cosmetics.
2. Export matching stamped Mac/Windows builds. Check libraries, asset-license inventory and complete-folder packaging. Provide short startup/Steam/mic instructions, controls, known limitations and log locations.
3. Validate transferred/downloaded builds on machines without Godot. Test both host OS directions, separate Internet connections, denied microphones, mute, leave/rejoin, version mismatch and host quit.
4. Complete three full six-player matches and a 60-minute soak. Observe frame times, host load, memory/queue/entity growth and state agreement.
5. Version packages consistently, retain one known-good previous build, and use the user's chosen sharing channel. No automatic public release/depot upload. Keep deferred ideas separate from release blockers.

**Done:** six friends can obtain the same version, host/join through Steam, finish/replay 3v3 and recover clearly from departures. No known reproducible crash, round blocker or state divergence remains in the tested envelope. Remaining limits are documented. A public Steam product, dedicated app registration and broader support are a separate future budget/scope decision.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, record the private release result and next useful maintenance task in PROJECT.md; do not add features automatically. If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
