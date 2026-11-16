# Session 06 — Proximity voice, radios and theft

Milestone: **M3**. First choice: **Codex GPT-6.1 Sol / high**. Alternative: **Claude Opus / high**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: [Voice](reference/architecture.md#voice); LastMage reuse table in [foundations](reference/foundations.md); voice cases in [verification](reference/verification.md).
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Prerequisite: The acceptance checks for [05-networked-combat-destruction.md](./05-networked-combat-destruction.md) must pass; use PROJECT.md for results rather than rereading that session.

## Work and acceptance

1. Adapt capture/ADPCM/packet buffering and relevant tests. Add microphone selection, loopback/meter, sensible gain, persistent hard mute and clear capture status. Test denied/missing devices.
2. Use open proximity voice as intended, with nearby enemies hearing speech. Keep microphone permission explicit and support non-speaking players. Team-radio transmit uses a separate held action; nearby listeners also hear the speaker.
3. Start with one channel per team. On death, drop a nonphysics radio pickup. Enemies may recover it to receive the original team's channel. Stolen radios cannot transmit/impersonate in the first version. Host owns pickup and eligibility.
4. Experiment with quiet positional handset leakage while receiving versus only the speaker leaking. Retain the more readable rule after testing; do not commit to elaborate channel controls.
5. Separate dead-player speech from living-player communication; no enemy-follow spectator camera. Check theft, death, disconnect and side-swap routing. Add basic nonverbal status/objective pings.

**Done:** six people can locate nearby speech; distant unauthorized peers receive no audio packets. Stolen radios receive only the authorized channel; mute stops capture/transmission. No doubled speech or feedback loops, bounded queues, intelligible voice during combat, graceful mic-denial behavior. Test Mac/Windows host swaps. Measure host egress with six simultaneous talkers and mouth-to-ear latency; begin with a <=250 ms goal under the measured envelope.

**Gate:** isolate capture → codec → transport → recipient policy → playback when diagnosing. Keep one channel and receive-only stolen radios. Add a new codec/plugin only after measuring the existing limitation. If overhearing creates frustration rather than useful tension, revise the rule before content expansion.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, set the active/next session in PROJECT.md to [07-round-loop.md](07-round-loop.md). If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
