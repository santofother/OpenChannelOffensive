# Checks, performance and playtesting

Optional reference: read only when the active session needs it. [Current project memory](../../PROJECT.md) owns status and the active-session pointer.

Provisional target: **1080p / 60 FPS** at recorded settings on this M1 Pro and an explicitly selected Windows baseline. Choose that machine by M0. The development Mac is not an announced minimum; a universal build does not prove Intel Mac performance.

Measure median/p95/p99 frame times and stalls over the same warmed-up 60-second path, before/after breaches. Aim initially for p95 <=16.7 ms; investigate repeated >33 ms spikes. Record driver, quality, scaling, VSync, build type, power/thermal state and initial-loading behavior. Measure host separately because it renders and simulates. Track memory and entity/queue counts across resets; they must remain bounded. Change budgets only from evidence and record the new target.

| Check | Add when | Consequential cases |
| --- | --- | --- |
| Import/boot | M0 | Parse/import errors, missing resources, explicit exit/failure |
| Rules/data | As added | Damage/penetration limits, transitions, cooldowns, reward math |
| Session integration | M2 | Identity/build rejection, cleanup, snapshots, stale/duplicate actions |
| Voice logic/codec | M3 | Recipient matrix, theft/death, malformed/lost/reordered packets, bounded queues |
| Objective/economy | M4–M5 | Timer ties, outcome priority, interrupted actions, duplicate buys/rewards, reset |
| Real OS/Steam tests | Every export milestone | Native loading, microphones, host swaps, six humans, visual quality and remote feel |

Use a small headless runner and focused integration scripts with nonzero exit on failure. Headless success does not verify rendering, microphone capture, Steam connectivity, controls or fun. Avoid tests that just mirror property assignments; add regressions for reproduced consequential bugs.

For each playtest record only build/machines/settings/player count, three major observations, one measurement and the next decision. Ask whether controls felt immediate, speech gave useful information, breaches offered choices, enemies stayed visible and outcomes were understood. No analytics backend or separate status bureaucracy.
