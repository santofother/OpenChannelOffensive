# Session 05 — Networked combat and destruction

Milestone: **M2**. First choice: **Codex GPT-6.1 Sol / high**. Alternative: **Claude Opus / high**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: Authority, Replication and Destruction in [architecture](reference/architecture.md); session/performance cases in [verification](reference/verification.md).
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Prerequisite: The acceptance checks for [04-visual-slice.md](./04-visual-slice.md) must pass; use PROJECT.md for results rather than rereading that session.

## Work and acceptance

1. Start with two peers: authoritative input processing, local prediction/reconciliation, remote interpolation, spawn/cleanup and aim/fire/reload. Keep simulation independent from Steam APIs.
2. Add validated hits, health/death, material penetration and interaction timing. Measure host-time hit testing at intended latency. Add bounded lag compensation only if justified; define how wall-state revisions interact with rewound shots first.
3. Replicate wall IDs/revisions, reinforcement, charge ownership/placement/countdown and breaches. Join snapshots must reproduce current openings. Add map reset and round IDs.
4. Test simultaneous actions, repeated requests, delayed events and disconnects. Expand from two to **six peers**, then mixed-platform Internet sessions with each OS hosting.
5. Measure host simulation time, movement correction, bandwidth and state consistency with moving/shooting/breaching players. Exercise latency/jitter/loss, initially around 100 ms RTT and 1–2% loss; log actual conditions.

**Done:** six-player tests agree on health, ammo, deaths, openings and collision; clients cannot commit unchecked actions. Snapshots restore current state; stale/duplicate actions cannot reapply. Host departure returns players to menu. Repeated resets leave no accumulating players/charges/debris. Non-host controls remain usable under measured network conditions.

**Gate:** no full-map art before remote feel and replicated destruction pass. Simplify movement/interactions if needed; do not judge networking solely from the host view. Six local processes do not prove six-person Internet play.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, set the active/next session in PROJECT.md to [06-voice-radios.md](06-voice-radios.md). If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
