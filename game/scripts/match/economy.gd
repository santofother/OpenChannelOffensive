class_name Economy
extends RefCounted
## Pure host-side credits and shop rules. Equipment resets every round; only credits carry over (reset at
## the start of a match and at the side swap). Purchases are atomic and idempotent per (player, request id).
var tuning: MatchTuning
var credits := {}
var losses := [0, 0] ## consecutive losses per team before the current round
var reinforced := [0, 0] ## panels reinforced this round, per team
var encrypted := [false, false] ## team bought the encrypted radio this round (one per team per round)
var income := {} ## id -> credits earned this round so far (kills, damage, reinforcing, round award)
var _income_fifths := {} ## earned fractions carry forward, including between rounds
var _last_req := {}
var _last_res := {}
var _awarded := 0

func _init(config: MatchTuning = null) -> void:
	tuning = config if config else MatchTuning.new()

func wallet(id: int) -> int:
	if not credits.has(id):
		credits[id] = tuning.start_credits
	return credits[id]

func leave(id: int) -> void:
	credits.erase(id)
	income.erase(id)
	_income_fifths.erase(id)
	_last_req.erase(id)
	_last_res.erase(id)

func reset_all() -> void:
	for id: int in credits.keys():
		credits[id] = tuning.start_credits
	losses = [0, 0]
	income.clear()
	_income_fifths.clear()
	_awarded = 0

func new_round() -> void:
	reinforced = [0, 0]
	encrypted = [false, false]
	income.clear()

## In-round earnings (kills, damage, reinforcing). Returns the amount actually added under the cap.
func earn(id: int, amount: int) -> int:
	if amount <= 0:
		return 0
	var before := wallet(id)
	var fifths := amount * 2 + int(_income_fifths.get(id, 0))
	_income_fifths[id] = fifths % 5
	credits[id] = mini(tuning.credit_cap, before + fifths / 5)
	var got: int = credits[id] - before
	income[id] = int(income.get(id, 0)) + got
	return got

func price(item: String) -> int:
	return ShopCatalog.price(tuning, item)

func limit(item: String) -> int:
	return ShopCatalog.limit(tuning, item)

## Free equipment at round start: [ordinary, heavy, reinforcements] (each free kit holds reinforce_per_kit).
func baseline(attacker: bool) -> Array:
	return [tuning.base_ordinary, 0, 0] if attacker else [0, 0, tuning.base_reinforce * tuning.reinforce_per_kit]

## `owned` is the host's current count of that item. Returns {ok, reason, item, credits, request}.
func buy(id: int, attacker: bool, item: String, request: int, owned: int, buy_phase: bool, alive: bool, unavailable := "") -> Dictionary:
	if request <= int(_last_req.get(id, 0)):
		if request == int(_last_req.get(id, 0)) and _last_res.has(id):
			var again: Dictionary = (_last_res[id] as Dictionary).duplicate()
			again["duplicate"] = true # replayed request: answered again, never charged again
			return again
		return {"ok": false, "reason": "Stale request", "item": item, "credits": wallet(id), "request": request}
	_last_req[id] = request
	var res := {"ok": false, "reason": "", "item": item, "credits": wallet(id), "request": request}
	if item not in ShopCatalog.buyable(attacker):
		res.reason = "Not available to your role"
	elif not buy_phase:
		res.reason = "Shop is closed"
	elif not alive:
		res.reason = "Not while down"
	elif not unavailable.is_empty():
		res.reason = unavailable
	elif owned >= limit(item):
		res.reason = "%s: already at limit" % ShopCatalog.find(item).name
	elif wallet(id) < price(item):
		res.reason = "Need $%d" % price(item)
	else:
		credits[id] = wallet(id) - price(item)
		res.ok = true
		res.credits = credits[id]
	_last_res[id] = res
	return res

func can_reinforce(team: int) -> String:
	if tuning.reinforce_allowance > 0 and reinforced[team] >= tuning.reinforce_allowance:
		return "Team reinforcement limit reached (%d)" % tuning.reinforce_allowance
	return ""

## Once per resolved round. `members` maps id -> team; `alive` lists ids still alive at resolution.
## A draw pays both teams the loss amount. Returns false if this round was already awarded.
func award_round(round_number: int, winner: int, attack_team: int, planted: bool, members: Dictionary, alive: Array = []) -> bool:
	if round_number <= _awarded:
		return false
	_awarded = round_number
	for id: int in members:
		var team := int(members[id])
		var amount: int
		if team == winner:
			amount = tuning.win_reward
		else:
			amount = tuning.loss_base + tuning.loss_bonus * mini(losses[team], tuning.loss_streak_max)
		if team == attack_team and planted:
			amount += tuning.plant_bonus
		if id in alive:
			amount += tuning.survive_bonus
		earn(id, amount)
	if winner >= 0:
		losses[winner] = 0
		losses[1 - winner] += 1
	return true
