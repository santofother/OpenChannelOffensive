# Session 01 — Steam foundation and exports

Milestone: **M0**. First choice: **Codex GPT-6.1 Sol / medium**. Alternative: **Claude Sonnet / medium**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: [Steam/export reuse](reference/foundations.md)
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Prerequisite: None; begin from the existing brief and read-only LastMage reference.

## Work and acceptance

**Agent-work target: 10–20 minutes for the initial implementation/check/export pass**, based on the user's prior LLM-assisted builds and reusable LastMage setup; under 10 minutes may be possible. This is a working target, not a measured result or guarantee. Actual cross-machine Steam host/join is a separate manual acceptance check. If imports, missing templates or native packaging slow the pass, identify the specific blocker and continue focused work; do not expand the task into a framework.

1. Initialize local Git, `game/project.godot`, input map and bootstrap. Ignore `.godot/`, builds and credentials; defer large-file tooling until needed.
2. Pin engine/templates and candidate addon. Adapt only required LastMage session/export code with a new game name, lobby key, build identity and six-player cap.
3. Make a plain room, capsules, minimal host/join/leave UI, useful error messages and offline launch. Retain a cheap ENet local-test path if useful; Steam remains the human multiplayer path.
4. Set Mac universal and Windows x64 debug export presets. Preserve the working native-library paths and Apple's ad-hoc signing approach from LastMage. Configure new microphone description/entitlements. Verify templates are installed rather than assuming so.
5. Add `tools/check.sh` for import/parse, deterministic smoke launch and failure reporting. Record Windows test hardware and arrange testers.

**Done:** exported builds run on actual Mac and Windows without Godot installed. Mac-host/Windows-join and reverse connect, leave and reconnect over Steam. Missing Steam, full lobby and incompatible build fail clearly. Record versions/settings. Two players are enough for this gate only; no FPS networking claim yet.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, set the active/next session in PROJECT.md to [02-controller-graybox.md](02-controller-graybox.md). If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
