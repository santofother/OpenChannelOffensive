# November 17 feedback evidence

Protocol 13 / Lightwell revision 2. Human acceptance remains open.

- `check.log`: final regression suite; added localized destruction and round MVP checks.
- `geometry.log` / `geometry.json`: 31 doors both directions, six spawn slots, 66 legal plant samples, all 229 wall/cover modules, ten resets. These geometric checks remain valid; `destruction.log` adds localized-cut behavior.
- `destruction.log`: actual gunfire and authoritative melee cut the aimed wall; rays pass the opening but surrounding collision remains; geometry replication, bounded sustained damage, reinforcement resistance and reset; reinforcement retains existing holes.
- `lightwell_6peers.*`: five starting peers plus a late joiner; 50 ms one-way latency ±10 ms jitter / 2% loss, local ENet. Includes partial bullet-hole replication/late join, real gunfire breaking cover, plant/defuse at both sites, role swaps, deciding 4–3 result and rematch.
- `radio_4peers.*`: real voice packets, receive-only theft, intercepted-radio mute/unmute, death/channel isolation and resets under simulated latency/loss.
- `controls.log`, `rounds.log`: movement, no sprint boost, holster, zoom over three base FOVs, listening reset/default bindings; majority clinch/decider, MVP selection/reset and economy.
- `visual.log` and PNGs: 1280×900 captured review of armor/shop, B closing/reopening, bomb marker, WON/LOST/MVP, 4× scope, localized wall openings and revision 2 top-down. The staged MVP text is a visual fixture; MVP authority is tested separately.
- `packaged_mac*.log`: packaged Mac startup and localized destruction smoke without source override. Windows exports build; Windows execution and real Steam/microphone tests remain open.

The earlier inferred tactical map and radial explosive splash were removed after the user's clarification. Audio production is a plan in `design/audio/improvement-plan.md`; this evidence does not claim that plan is implemented or that real voice latency is measured.
