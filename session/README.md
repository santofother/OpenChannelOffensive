# Session index

[PROJECT.md](../PROJECT.md) contains the current active session and all progress. Agents read it first, then **only the named session file and relevant code**. This index is navigation, not another status board. Session files hold their own model/effort, prerequisites, tasks and acceptance criteria.

| Session | Task | Milestone | First-choice model / effort |
| --- | --- | --- | --- |
| 01 | [Steam foundation and exports](01-steam-foundation.md) | M0 | Codex GPT-6.1 Sol / medium |
| 02 | [FPS controller and graybox](02-controller-graybox.md) | M1, part 1 | Codex GPT-6.1 Sol / medium |
| 03 | [Rifle and breach interactions](03-shooting-breaches.md) | M1, part 2 | Codex GPT-6.1 Sol / medium |
| 04 | [Lighting, materials and slice validation](04-visual-slice.md) | M1, part 3 | Current builder / medium |
| 05 | [Networked combat and destruction](05-networked-combat-destruction.md) | M2 | Codex GPT-6.1 Sol / high |
| 06 | [Proximity voice, radios and theft](06-voice-radios.md) | M3 | Codex GPT-6.1 Sol / high |
| 07 | [Complete 3v3 round loop](07-round-loop.md) | M4 | Codex GPT-6.1 Sol / high |
| 08 | [Economy and reinforcement](08-economy-reinforcement.md) | M5 | Codex GPT-6.1 Sol / medium |
| 09 | [Representative polish and one complete map](09-polish-map.md) | M6 | Current builder / medium; GPT-6.1 Terra / medium for visual critique |
| 09.5 | [Lightwell: detailed two-site map plan](09.5-lightwell-map.md) | M6 extension | Current builder / medium; Sol / high for network/wall-state changes |
| 09.75 | [Gear functionality and reference-quality models](09.75-gear-and-models.md) | M5/M6 extension | Opus / medium; Sol or Opus / high for replication |
| 10 | [Private release candidate](10-private-release.md) | M7 | Codex GPT-6.1 Sol / medium |

The first four files preserve the agreed first-session sequence; M2–M7 each have a focused file. A session may span several work periods. Combine straightforward changes only when they remain reviewable and acceptance checks pass. Do not start the next session automatically just because code was generated; verify the current gate.

Start with: “Read PROJECT.md and its active session file. Implement the next complete increment, run relevant checks, update project memory and give me short playtest steps.”

Questions and bug reports belong in the current chat. Say “question only” for explanation without edits. For bugs, provide build/platform, steps, expected/actual behavior and a useful log or clip when available. Fix blocking bugs in the active session; record deferred issues briefly in PROJECT.md. Keep one editing agent at a time; no subagents unless requested.

## Optional references

Read a reference only when the active task needs it: [scope](reference/product.md), [engine/Steam reuse](reference/foundations.md), [architecture](reference/architecture.md), [model priorities](reference/models.md), [verification/performance](reference/verification.md), [timing/risks](reference/risks.md). These carry the shared details moved from the original plan; they do not own status.

Model recommendations were researched November 14, 2026; use available client versions/settings. M0 retains the user's 10–20 minute agent-work target, with manual testing separate. Later timing is calibrated from actual sessions.
