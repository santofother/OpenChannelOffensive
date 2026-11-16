# Session 08 — Economy and reinforcement

Milestone: **M5**. First choice: **Codex GPT-6.1 Sol / medium**. Alternative: **Claude Sonnet / medium; high for transaction/reset regressions**. These are recommendations, not changed client settings; retain a productive current builder.

Read [PROJECT.md](../PROJECT.md) first, then this file and relevant code. Read only these shared details when needed: Replication and Destruction in [architecture](reference/architecture.md); economy cases in [verification](reference/verification.md).
Do not read the full roadmap, every reference or future session. This file can span multiple work periods; it is not a promised duration.

Prerequisite: The acceptance checks for [07-round-loop.md](./07-round-loop.md) must pass; use PROJECT.md for results rather than rereading that session.

## Work and acceptance

1. Add host-owned credits, role-appropriate shop, buy timing, inventory limits and atomic purchases with request IDs. Give everyone the baseline rifle; spending differentiates tactical tools first.
2. Try capped starting credits, round income and a small loss bonus. Prices/income are placeholders in one Resource; do not tune them as final without playtests.
3. Limit reinforcement to valid intact panels and a per-team/round allowance. Ordinary charges open ordinary panels; reinforced panels require a dearer heavy tool, more warning and exposure. Define reinforced bullet penetration explicitly.
4. Start with equipment reset each round and credit carryover, reset at side swap. Full CS-style weapon retention/recovery is deferred; radio theft remains independent.

**Done:** no negative credits/double-spending; repeated, late and invalid requests fail safely. Rewards/caps/resets are tested. Losing teams can field a viable loadout, defenders cannot seal every approach without tradeoffs, and observed matches include meaningful buy/breach/route decisions.

## Finish the session

Run relevant available checks; clearly separate verified results from checks requiring human playtesting. Update PROJECT.md with current state, known issues and the next task. After acceptance passes, set the active/next session in PROJECT.md to [09-polish-map.md](09-polish-map.md). If blocked or manual checks are pending, keep this session active and record exactly what remains. No separate status board or handoff document.
