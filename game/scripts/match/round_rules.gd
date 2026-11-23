class_name RoundRules
extends RefCounted
## Pure host state machine. Integer deadlines; one resolution after all combat in a simulation step.
## Team identities stay stable. Roles/spawns swap, so scores and radio channels stay with each squad.
enum Phase { LOBBY, PREP, LIVE, PLANTED, RESOLUTION, RESULT }
const HZ := 60
var tuning: MatchTuning
var phase := Phase.LOBBY
var deadline := 0
var round_number := 0
var attack_team := 0
var scores := [0, 0]
var winner := -1
var reason := ""
var awards := 0 # exactly one score award per resolved round
var serial := 0
var carrier := 0
var bomb_pos := Vector3.ZERO
var site := -1
var actor := 0
var progress := 0
var action_ticks := 0
var action_site := -1
var ready := {}
var spotted: Array = [] ## defender ids revealed to attackers for staying outside too long

func _init(config: MatchTuning = null) -> void:
	tuning = config if config else MatchTuning.new()

func wins_needed() -> int:
	return maxi(1, tuning.rounds / 2 + 1)

func ticks(seconds: float) -> int:
	return maxi(1, int(roundf(seconds * HZ)))

func rematch() -> void:
	phase = Phase.LOBBY
	deadline = 0
	round_number = 0
	attack_team = 0
	scores = [0, 0]
	winner = -1
	reason = ""
	awards = 0
	ready.clear()
	_clear_bomb()
	serial += 1

func _clear_bomb() -> void:
	carrier = 0
	bomb_pos = Vector3.ZERO
	site = -1
	interrupt()

func interrupt() -> void:
	actor = 0
	progress = 0
	action_ticks = 0
	action_site = -1

func can_start(roster: Dictionary) -> bool:
	var teams := [0, 0]
	for id: int in roster:
		teams[int(roster[id].team)] += 1
		if not ready.get(id, false):
			return false
	return teams[0] > 0 and teams[1] > 0

func begin_round(now: int, roster: Dictionary) -> void:
	round_number += 1
	attack_team = 1 if round_number > tuning.swap_after else 0
	_clear_bomb()
	winner = -1
	reason = ""
	spotted = []
	phase = Phase.PREP
	deadline = now + ticks(tuning.prep)
	var ids := roster.keys()
	ids.sort()
	for id: int in ids:
		if int(roster[id].team) == attack_team:
			carrier = id
			break
	serial += 1

func drop(id: int, pos: Vector3) -> void:
	if carrier == id and phase in [Phase.PREP, Phase.LIVE]:
		carrier = 0
		bomb_pos = pos
		interrupt()
		serial += 1

func resolve(team: int, why: String, now: int) -> void:
	if phase not in [Phase.LIVE, Phase.PLANTED]:
		return
	winner = team
	reason = why
	scores[team] += 1
	awards += 1
	phase = Phase.RESOLUTION
	deadline = now + ticks(tuning.resolution)
	interrupt()
	serial += 1

## roster is authoritative, contains team/alive/pos/hold/site/near_bomb/damaged.
## The adapter checks LOS, fresh input, stationary movement, tool use, and round identity.
func step(now: int, roster: Dictionary) -> void:
	if phase == Phase.LOBBY:
		if can_start(roster):
			begin_round(now, roster)
		return
	if phase == Phase.RESOLUTION:
		if now >= deadline:
			if maxi(scores[0], scores[1]) >= wins_needed():
				phase = Phase.RESULT
				winner = 0 if scores[0] > scores[1] else 1
				serial += 1
			else:
				begin_round(now, roster)
		return
	if phase == Phase.RESULT:
		return
	if carrier != 0:
		if not roster.has(carrier) or not roster[carrier].alive:
			drop(carrier, bomb_pos)
		else:
			bomb_pos = roster[carrier].pos
	if phase == Phase.PREP:
		if now >= deadline:
			phase = Phase.LIVE
			deadline = now + ticks(tuning.live)
			serial += 1
		return
	# Deadlines win exact ties. Plant cannot extend an expired live phase.
	if now >= deadline:
		resolve(attack_team if phase == Phase.PLANTED else 1 - attack_team,
			"Bomb exploded" if phase == Phase.PLANTED else "Time expired", now)
		return
	var counts := [0, 0]
	for p: Dictionary in roster.values():
		if p.alive:
			counts[int(p.team)] += 1
	# Preplant double elimination favors defenders. Once planted, only a defuse or
	# the explosion ends the round, whichever team is still standing.
	if phase == Phase.LIVE and counts[attack_team] == 0:
		resolve(1 - attack_team, "Attackers eliminated", now)
		return
	if phase == Phase.LIVE and counts[1 - attack_team] == 0:
		resolve(attack_team, "Defenders eliminated", now)
		return
	var candidates := roster.keys()
	candidates.sort() # simultaneous recovery/defuse has deterministic ownership
	if phase == Phase.LIVE and carrier == 0:
		for id: int in candidates:
			var p: Dictionary = roster[id]
			if p.alive and int(p.team) == attack_team and p.hold and p.near_bomb:
				carrier = id
				serial += 1
				return # recovery takes one step; planting starts next step
	var next_actor := 0
	var next_site := -1
	for id: int in candidates:
		var p: Dictionary = roster[id]
		if not p.alive or not p.hold or p.damaged:
			continue
		if phase == Phase.LIVE and id == carrier and int(p.site) >= 0:
			next_actor = id
			next_site = int(p.site)
			break
		if phase == Phase.PLANTED and int(p.team) != attack_team and p.near_bomb:
			next_actor = id
			next_site = site
			break
	if next_actor == 0:
		interrupt()
		return
	if actor != next_actor or action_site != next_site:
		progress = 0
	actor = next_actor
	action_site = next_site
	action_ticks = ticks(tuning.plant if phase == Phase.LIVE else tuning.defuse *
		(tuning.defuse_with_kit if roster[actor].get("kit", false) else tuning.defuse_without_kit))
	progress += 1
	if phase == Phase.LIVE and progress >= action_ticks:
		site = action_site
		bomb_pos = roster[actor].pos
		carrier = 0
		phase = Phase.PLANTED
		deadline = now + ticks(tuning.fuse)
		interrupt()
		serial += 1
	elif phase == Phase.PLANTED and progress >= action_ticks:
		resolve(1 - attack_team, "Bomb defused", now)

func state() -> Dictionary:
	return {"phase": phase, "deadline": deadline, "round_number": round_number, "attack_team": attack_team,
		"scores": scores.duplicate(), "winner": winner, "reason": reason, "awards": awards, "serial": serial,
		"carrier": carrier, "bomb_pos": bomb_pos, "site": site, "actor": actor, "progress": progress,
		"action_ticks": action_ticks, "action_site": action_site, "ready": ready.duplicate(), "spotted": spotted.duplicate()}

func apply(d: Dictionary) -> void:
	for key: String in d:
		set(key, d[key])
