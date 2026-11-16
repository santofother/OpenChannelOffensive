# Model and effort reference

Optional reference: read only when the active session needs it. [Current project memory](../../PROJECT.md) owns status and the active-session pointer.

These are **project recommendations**, not a measured head-to-head ranking or a promise about subscription usage. Start with one builder; use alternatives when the task needs them, the preferred model is unavailable, or one subscription is constrained. Do not run the same task through several models routinely.

Default priority for ordinary implementation: **1. Codex GPT-6.1 Sol / medium → 2. Claude Sonnet / medium → 3. Claude Opus / medium**. Keep the current builder when it is making progress; switching tools just to follow the ranking wastes context. Opus is a Claude model; the useful comparison is Codex versus Claude Sonnet versus Claude Opus.

For ambiguous architecture, desync or voice-recipient reasoning, prefer **Claude Opus / high** for the focused design/diagnostic task, with **Codex GPT-6 Astra / high** as the alternative. For a well-defined implementation of those systems, use **GPT-6.1 Sol / high**. Do not require an extra planning/reviewer handoff if the current builder can finish the task.

| Milestone/task | First choice | Second choice | When to escalate/change |
| --- | --- | --- | --- |
| M0 setup, selective reuse, exports | Codex GPT-6.1 Sol / medium | Claude Sonnet / medium | Native-loading or Steam issue remains unexplained after two failed fixes: Opus / high for diagnosis |
| M1 controller, shooting, authored breaches | Codex GPT-6.1 Sol / medium | Claude Sonnet / medium | Raise current builder to high for collision/state bugs with a repro |
| M1 lighting/composition review | Codex GPT-6.1 Terra / medium | Claude Opus / medium | Review actual screenshots; current builder can implement the identified changes |
| M2 movement/authority/destruction implementation | Codex GPT-6.1 Sol / high | Claude Opus / high | Ambiguous design/desync diagnosis: Opus / high first, Astra / high alternative |
| M3 voice capture/transport/radio rules | Codex GPT-6.1 Sol / high | Claude Opus / high | Recipient-policy ambiguity or persistent timing bug: focused Opus / high diagnosis |
| M4 objective/round state machine | Codex GPT-6.1 Sol / high | Claude Opus / high | Use medium for straightforward HUD wiring once rules/tests are settled |
| M5 shop/economy/UI | Codex GPT-6.1 Sol / medium | Claude Sonnet / medium | High for duplicate transactions, rewards or round-reset regressions |
| M6 visual polish | Current builder / medium; Terra / medium for screenshot critique | Claude Opus / medium | Sol or Opus / high for a measured rendering/performance diagnosis |
| M7 packaging and regression fixes | Codex GPT-6.1 Sol / medium | Claude Sonnet / medium | Sol or Opus / high for reproducible cross-platform/desync blockers |
| Simple question, documented tuning change, small bug | Current builder / low or medium | Sonnet / low or medium | High only when evidence shows a deeper dependency/problem |
| Focused milestone review, when useful | Claude Opus / high | Codex GPT-6.1 Sol / high | Read-only review of acceptance criteria and relevant changes; no automatic extra review session |

Use **medium by default**, **high for consequential multi-system reasoning**, and **low for simple questions/edits**. Reserve xhigh/max for a specific unresolved problem where the gain is worth the latency/usage; they are not milestone defaults. After two failed fixes without progress, first produce a repro, logs, attempted fixes and the failing layer. A stronger model receives that compact evidence rather than restarting the whole investigation. Return to the normal builder/effort after resolving it.

**Selecting models:** choose the listed model/effort in the client before the session. A prompt naming a model is not evidence that the client switched it. Use the closest available model in that family; do not assume every subscription exposes every version/control. In current official Anthropic docs, Sonnet/Opus are 5.5; use the installed client's available versions. Claude Code supports `/model sonnet` or `/model opus` and `/effort medium` or `/effort high` where supported. This plan changes no application settings and requires no API purchases.

Sources checked November 14, 2026: [OpenAI model/effort guidance](https://learn.chatgpt.com/docs/models), [OpenAI reasoning effort](https://developers.openai.com/api/docs/guides/reasoning), [Claude Code model/effort configuration](https://code.claude.com/docs/en/model-config), [Claude model catalog](https://platform.claude.com/docs/en/models/overview). The priority order above is our workflow recommendation; the sources establish model families and controls, not comparative performance on this game.
