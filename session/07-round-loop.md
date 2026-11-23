# Session 07 — Complete 3v3 round loop

Milestone: **M4**. First choice: **Codex GPT-6.1 Sol / high**. Alternative: **Claude Opus / high**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: Authority and Replication in [architecture](reference/architecture.md); objective cases in [verification](reference/verification.md).
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Sequencing override (user, November 16): execute S7 while S6 human acceptance is still pending. This does not mark S6 accepted; PROJECT.md owns the remaining checks.

## Work and acceptance

1. Graybox **two alternative bomb sites A/B** (confirmed user requirement, supersedes the earlier one-site proposal) and two viable approaches using proven modules. Test route times, defensive coverage and breach alternatives with six people.
2. Add host-owned phases: lobby → equipment/prep → live → planted if applicable → resolution → next round/side swap → match result. Store deadlines on host; clients display remaining time.
3. Add team assignment/readiness, safe loading/spawns, dropped/recoverable bomb, hold-to-plant/defuse and interruptions, objective/elimination wins, teammate-only death camera and next-round joins.
4. Reset health/ammo, walls, tools, charges, radio ownership, pickups and timers. Dead players must not relay tactical speech to living players or receive enemy positions for spectator UI.
5. Add phase/objective HUD, score, round-end reason, audio cues, rematch/leave and development-only test shortcuts.

**Provisional defaults:** 30 s prep, 150 s live, 5 s plant, 7 s defuse, 40 s fuse. Six regulation rounds; swap after three. Most round wins wins; permit a 3–3 draw initially. Reset economy at side swap. Store all values in one match Resource and revise through playtests.

**Outcome ordering:** one host resolution per simulation step. A plant must finish before the live deadline to extend play. Once planted, attacker elimination alone does not end the round; defenders still defuse. Defender elimination awards attackers the round. Defuse must finish before explosion; an exact deadline tie explodes. Preplant timeout favors defenders. Explicitly test simultaneous last deaths, interruptions, bomb drops and disconnects; initial preplant double elimination favors defenders. These rules are proposed, not final balance decisions.

**Done:** six humans complete a full match and rematch without the editor. Every win/timeout/tie/reset path is deterministic in tests; resolution rewards occur once. Host quit and client disconnect recover clearly. Late events cannot change a new round. Blind testers understand side, objective, time and outcome.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, set the active/next session in PROJECT.md to [08-economy-reinforcement.md](08-economy-reinforcement.md). If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
