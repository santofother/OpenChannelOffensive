class_name RoundPerformance
extends RefCounted
## Host-only round contribution ledger. MVP comes from the winning team: kills, objective actions,
## damage, then stable player ID. Enemy damage only; round resets clear the ledger.
var tuning: MatchTuning
var stats := {}
var totals := {}
var contributors := {}
var died_this_round := {}


func reset() -> void:
	stats.clear()
	contributors.clear()
	died_this_round.clear()

func reset_match() -> void:
	reset()
	totals.clear()

func score(id: int) -> Dictionary:
	return totals.get(id, {"kills": 0, "assists": 0, "deaths": 0, "points": 0}).duplicate()

func award(id: int, points: int) -> void:
	if id <= 0:
		return
	var row := score(id)
	row.points += points
	totals[id] = row

func leave(id: int) -> void:
	totals.erase(id)
	stats.erase(id)
	died_this_round.erase(id)
	contributors.erase(id)
	for attackers: Dictionary in contributors.values():
		attackers.erase(id)

func enemy_hit(attacker: int, target: int, damage: float, killed: bool) -> void:
	record(attacker, damage, killed)
	var before := float(stats[attacker].damage) - damage
	award(attacker, roundi(float(stats[attacker].damage) * tuning.points_per_damage)
		- roundi(before * tuning.points_per_damage))
	if not contributors.has(target):
		contributors[target] = {}
	var attackers: Dictionary = contributors[target]
	attackers[attacker] = float(attackers.get(attacker, 0.0)) + damage

func death(id: int, killer: int) -> void:
	died_this_round[id] = true
	var victim := score(id)
	victim.deaths += 1
	totals[id] = victim
	if killer > 0:
		var row := score(killer)
		row.kills += 1
		row.points += tuning.points_kill
		totals[killer] = row
		var attackers: Dictionary = contributors.get(id, {})
		for attacker: int in attackers:
			if attacker != killer and float(attackers[attacker]) >= tuning.assist_min_damage:
				var assist := score(attacker)
				assist.assists += 1
				assist.points += tuning.points_assist
				totals[attacker] = assist
	contributors.erase(id)

func record(id: int, damage: float = 0.0, kill: bool = false, objective: bool = false) -> void:
	if id <= 0:
		return
	var row: Dictionary = stats.get(id, {"kills":0, "damage":0.0, "objectives":0})
	row.kills += int(kill)
	row.damage += maxf(0.0, damage)
	row.objectives += int(objective)
	stats[id] = row

func mvp(winner: int, roster: Dictionary) -> Dictionary:
	var ids: Array = roster.keys()
	ids.sort()
	var best := {}
	var best_key := Vector3(-1, -1, -1)
	for id: int in ids:
		if int(roster[id].team) != winner:
			continue
		var row: Dictionary = stats.get(id, {"kills":0, "damage":0.0, "objectives":0})
		var key := Vector3(row.kills, row.objectives, row.damage)
		if best.is_empty() or key.x > best_key.x or (key.x == best_key.x and key.y > best_key.y) or (key.x == best_key.x and key.y == best_key.y and key.z > best_key.z):
			best_key = key
			best = row.duplicate()
			best.id = id
			best.name = str(roster[id].name)
	return best
