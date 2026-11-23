extends SceneTree
var fails := 0
var now := 0
var r: RoundRules
var people := {}

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("  %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1

func setup() -> void:
	now = 0
	r = RoundRules.new()
	r.tuning = MatchTuning.new()
	r.tuning.prep = 0.05
	r.tuning.live = 1.0
	r.tuning.plant = 0.05
	r.tuning.defuse = 0.05
	r.tuning.fuse = 0.2
	r.tuning.resolution = 0.05
	people = {1: person(0), 2: person(1)}

func person(team: int) -> Dictionary:
	return {"team": team, "alive": true, "pos": Vector3(5, 0, -5), "hold": false, "site": -1,
		"near_bomb": false, "damaged": false}

func step(n: int = 1) -> void:
	for i in n:
		now += 1
		r.step(now, people)

func live() -> void:
	r.ready = {1: true, 2: true}
	step()
	step(3)

func plant(site: int = 0) -> void:
	people[1].hold = true
	people[1].site = site
	step(3)

func _run() -> void:
	setup()
	step()
	check("lobby waits for readiness", r.phase == RoundRules.Phase.LOBBY)
	r.ready[1] = true
	step()
	check("one ready peer cannot start", r.phase == RoundRules.Phase.LOBBY)
	people.erase(2)
	step()
	check("both teams are required", r.phase == RoundRules.Phase.LOBBY)
	people[2] = person(1)
	r.ready[2] = true
	step()
	check("everyone ready starts prep and assigns bomb", r.phase == RoundRules.Phase.PREP and r.carrier == 1)
	step(3)
	check("prep host deadline unlocks live", r.phase == RoundRules.Phase.LIVE)
	for site in 2:
		setup()
		live()
		plant(site)
		check("plant at site %s" % ["A", "B"][site], r.phase == RoundRules.Phase.PLANTED and r.site == site and r.carrier == 0)
		people[1].alive = false
		step()
		check("planted bomb survives attacker elimination", r.phase == RoundRules.Phase.PLANTED)
		people[2].alive = false
		step()
		check("planted bomb survives defender elimination until it explodes or is defused", r.phase == RoundRules.Phase.PLANTED)
		people[2].alive = true
		people[2].hold = true
		people[2].near_bomb = true
		step(5)
		check("without a kit, defuse requires double the base time", r.action_ticks == 6 and r.progress == 5)
		step()
		check("defuse wins and awards exactly once", r.phase == RoundRules.Phase.RESOLUTION and r.winner == 1 and r.awards == 1)
		r.resolve(0, "duplicate", now)
		check("duplicate outcome cannot award again", r.scores == [0, 1] and r.awards == 1)
	setup()
	live()
	plant()
	people[2].hold = true
	people[2].near_bomb = true
	people[2].kit = true
	step()
	check("kit uses 80 percent of base defuse time", r.action_ticks == 2 and r.progress == 1)
	step()
	check("kit finishes earlier than the base time", r.reason == "Bomb defused")
	setup()
	live()
	people[1].hold = true
	people[1].site = 0
	step(2)
	people[1].hold = false
	step()
	check("release interrupts plant", r.progress == 0 and r.actor == 0)
	people[1].hold = true
	step(2)
	people[1].damaged = true
	step()
	check("damage interrupts plant", r.progress == 0)
	people[1].damaged = false
	step(2)
	people[1].site = 1
	step()
	check("changing sites restarts progress", r.progress == 1 and r.action_site == 1)
	r.drop(1, Vector3(2, 0, -3))
	people[1].near_bomb = false
	step()
	check("bomb drops at host position and cannot be remotely recovered", r.carrier == 0 and r.bomb_pos == Vector3(2, 0, -3))
	people[2].hold = true
	people[2].near_bomb = true
	step()
	check("defenders cannot recover unplanted bomb", r.carrier == 0)
	people[1].near_bomb = true
	step()
	check("living attacker recovers bomb", r.carrier == 1 and r.progress == 0)
	setup()
	live()
	people[1].alive = false
	people[2].alive = false
	step()
	check("preplant simultaneous last deaths favor defenders", r.winner == 1)
	setup()
	live()
	people[2].alive = false
	step()
	check("defender elimination favors attackers", r.winner == 0)
	setup()
	live()
	plant()
	people[1].alive = false
	people[2].alive = false
	step()
	check("postplant simultaneous last deaths wait for the fuse", r.phase == RoundRules.Phase.PLANTED)
	step(r.deadline - now)
	check("the unattended bomb then explodes for attackers", r.winner == 0 and r.reason == "Bomb exploded")
	setup()
	live()
	r.deadline = now + 3
	plant()
	check("plant finishing at live deadline loses to timeout", r.winner == 1 and r.reason == "Time expired")
	setup()
	live()
	r.deadline = now + 4
	plant()
	check("plant finishing one tick before deadline extends play", r.phase == RoundRules.Phase.PLANTED)
	r.deadline = now + 6
	people[2].hold = true
	people[2].near_bomb = true
	step(6)
	check("defuse exact deadline tie explodes", r.winner == 0 and r.reason == "Bomb exploded")
	setup()
	live()
	plant()
	people[2].hold = true
	people[2].near_bomb = true
	step(2)
	people[2].hold = false
	step()
	check("release interrupts defuse", r.progress == 0 and r.phase == RoundRules.Phase.PLANTED)
	people.erase(1)
	step()
	check("attacker disconnect after plant still requires defuse", r.phase == RoundRules.Phase.PLANTED)
	people.erase(2)
	step()
	check("defender disconnect after plant leaves the bomb ticking", r.phase == RoundRules.Phase.PLANTED)
	step(r.deadline - now)
	check("the bomb resolves the round once", r.winner == 0 and r.awards == 1)
	setup()
	live()
	r.drop(1, people[1].pos)
	people.erase(1)
	step()
	check("carrier disconnect before plant gives defenders elimination", r.winner == 1 and r.carrier == 0)
	setup()
	live()
	for i in 13:
		check("round %d attack role" % (i + 1), r.attack_team == (1 if i >= 6 else 0))
		r.resolve(i % 2, "test outcome", now)
		step(3)
		if i == 11:
			check("6:6 starts the deciding round", r.phase == RoundRules.Phase.PREP and r.scores == [6, 6])
		if i < 12:
			step(3)
	check("first to seven ends 7:6", r.phase == RoundRules.Phase.RESULT and r.scores == [7, 6] and r.winner == 0 and r.awards == 13)
	step(100)
	check("result cannot start extra rounds", r.round_number == 13 and r.awards == 13)
	r.rematch()
	check("rematch clears scores, readiness and objective", r.phase == RoundRules.Phase.LOBBY and r.scores == [0, 0] and r.ready.is_empty() and r.carrier == 0 and r.awards == 0)
	for configured in [1, 2, 5, 6, 8, 12]:
		setup()
		r.tuning.rounds = configured
		live()
		var target: int = configured / 2 + 1
		for i in target:
			r.resolve(0, "sweep", now)
			step(3)
			if i < target - 1:
				check("cannot clinch early at %d wins" % (i + 1), r.phase == RoundRules.Phase.PREP)
				step(3)
		check("%d-round setting clinches at %d" % [configured, target], r.phase == RoundRules.Phase.RESULT and r.scores == [target, 0] and r.round_number == target)
	var ledger := RoundPerformance.new()
	var names := {1:{"team":0,"name":"One"}, 2:{"team":0,"name":"Two"}, 3:{"team":1,"name":"Enemy"}}
	ledger.record(1, 100, true)
	ledger.record(2, 100, true, true)
	ledger.record(3, 500, true)
	check("MVP chooses winning team and objective tie break", ledger.mvp(0, names).id == 2)
	ledger.record(1, 100, true)
	check("MVP rewards more kills", ledger.mvp(0, names).id == 1)
	ledger.reset()
	check("MVP resets each round with stable ties", ledger.stats.is_empty() and ledger.mvp(0, names).id == 1)
	_economy()
	var match_points := RoundPerformance.new()
	match_points.tuning = MatchTuning.new()
	match_points.enemy_hit(1, 3, 25.0, false)
	match_points.enemy_hit(2, 3, 75.0, true)
	match_points.death(3, 2)
	match_points.award(1, match_points.tuning.points_reinforced)
	check("match scores track team assists, kills, deaths and action points",
		match_points.score(1) == {"kills": 0, "assists": 1, "deaths": 0, "points": 100}
		and match_points.score(2) == {"kills": 1, "assists": 0, "deaths": 0, "points": 175}
		and match_points.score(3).deaths == 1)
	match_points.reset()
	check("round reset clears MVP but keeps cumulative points", match_points.stats.is_empty() and match_points.score(2).points == 175)
	match_points.reset_match()
	check("rematch clears cumulative points", match_points.score(2).points == 0)
	var kit_shop := Economy.new()
	check("attackers cannot buy the defender kit", not kit_shop.buy(1, true, "defuse_kit", 1, 0, true, true).ok)
	check("defenders can buy the kit", kit_shop.buy(2, false, "defuse_kit", 1, 0, true, true).ok)
	check("armor choices exclude standalone helmets", "vest" in ShopCatalog.buyable(true)
		and "armor_helmet" in ShopCatalog.buyable(true) and "helmet" not in ShopCatalog.buyable(true))
	print("SMOKE_%s rounds (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _economy() -> void:
	var e := Economy.new(MatchTuning.new())
	var t := e.tuning
	check("new wallet starts at the placeholder credits", e.wallet(1) == t.start_credits)
	var r1 := e.buy(1, true, "heavy", 1, 0, true, true)
	check("attacker buys heavy charge once", r1.ok and e.wallet(1) == t.start_credits - t.price_heavy)
	var r2 := e.buy(1, true, "heavy", 1, 1, true, true)
	check("replayed request id is answered, never charged twice", r2.ok and r2.get("duplicate", false) and e.wallet(1) == t.start_credits - t.price_heavy)
	check("older request id is rejected", not e.buy(1, true, "ordinary", 0, 0, true, true).ok)
	check("shop closed outside prep", not e.buy(1, true, "ordinary", 2, 0, false, true).ok)
	check("downed players cannot buy", not e.buy(1, true, "ordinary", 3, 0, true, false).ok)
	check("defender kit is not an attacker item", not e.buy(1, true, "kit", 4, 0, true, true).ok)
	check("attackers' tools are not defender items", not e.buy(2, false, "heavy", 1, 0, true, true).ok and e.wallet(2) == t.start_credits)
	check("unknown item ids fail safely", not e.buy(2, false, "bogus", 2, 0, true, true).ok and not e.buy(2, false, "", 3, 0, true, true).ok)
	check("inventory limit blocks purchase and keeps credits", not e.buy(2, false, "ordinary", 4, ShopCatalog.UTILITY_LIMIT, true, true).ok and e.wallet(2) == t.start_credits)
	check("reinforcement kits have no carry limit", e.buy(2, false, "kit", 5, 40, true, true).ok and e.wallet(2) == t.start_credits - t.price_reinforce)
	var kit_lo := Loadout.new()
	kit_lo.charges[Loadout.Tool.REINFORCE] = 0
	ShopCatalog.grant(kit_lo, "kit")
	check("one kit holds five reinforcements", kit_lo.charges[Loadout.Tool.REINFORCE] == 5 and t.reinforce_per_kit == 5)
	kit_lo.free()
	e.credits[3] = t.price_ordinary - 1
	check("insufficient credits never go negative", not e.buy(3, true, "ordinary", 1, 0, true, true).ok and e.wallet(3) == t.price_ordinary - 1)
	e.credits[3] = t.price_ordinary
	check("exact credits buy to zero", e.buy(3, true, "ordinary", 2, 0, true, true).ok and e.wallet(3) == 0)
	check("zero credits cannot overspend", not e.buy(3, true, "ordinary", 3, 0, true, true).ok and e.wallet(3) == 0)
	# Income: win, loss streak bonus (capped), plant bonus, wallet cap, once per round.
	e = Economy.new(MatchTuning.new())
	var members := {1: 0, 2: 1}
	check("round awards once", e.award_round(1, 0, 0, false, members) and not e.award_round(1, 0, 0, false, members))
	check("winner paid, loser gets base reward", e.wallet(1) == t.start_credits + 1200 and e.wallet(2) == t.start_credits + 560)
	e.award_round(2, 0, 0, true, members)
	check("loss streak and plant bonus apply", e.wallet(2) == t.start_credits + 560 + 760 and e.wallet(1) == t.start_credits + 1200 + 1320)
	var rich := Economy.new(MatchTuning.new())
	rich.tuning.credit_cap = 100000
	for n in 5:
		rich.new_round()
		rich.award_round(n + 1, 0, 0, false, members)
	check("loss bonus caps at the streak maximum", int(rich.income[2]) == 1360)
	e.credits[1] = t.credit_cap - 1
	e.award_round(3, 0, 0, false, members)
	e.award_round(4, 0, 0, false, members)
	check("wallet never exceeds the cap", e.wallet(1) == t.credit_cap and e.wallet(2) <= t.credit_cap)
	e.new_round()
	e.credits[1] = 0
	e.award_round(5, 1, 0, true, members) # attackers (team 0) lose but planted
	check("planting attackers earn the bonus when they lose", int(e.income[1]) == 680 and e.losses[0] == 1 and e.losses[1] == 0)
	# In-round income: kills/damage/reinforcing add to the wallet and this round's income; survivors get a bonus.
	var inc := Economy.new(MatchTuning.new())
	inc.new_round()
	check("in-round earnings add to the wallet", inc.earn(1, t.kill_reward) == 120 and inc.wallet(1) == t.start_credits + 120 and int(inc.income[1]) == 120)
	inc.award_round(1, 0, 0, false, members, [1])
	check("survivors get the survival bonus on top of the win", inc.wallet(1) == t.start_credits + 120 + 1200 + 80 and inc.wallet(2) == t.start_credits + 560)
	check("a draw still pays both teams", inc.award_round(2, -1, 0, false, members) and inc.wallet(2) == t.start_credits + 560 + 760)
	check("fractional combat earnings accumulate", inc.earn(3, 1) == 0 and inc.earn(3, 1) == 0 and inc.earn(3, 1) == 1)
	inc.credits[1] = t.credit_cap - 10
	check("earnings respect the wallet cap", inc.earn(1, 500) == 10 and inc.wallet(1) == t.credit_cap)
	e.reset_all()
	check("side swap/new match resets credits and streaks", e.wallet(1) == t.start_credits and e.wallet(2) == t.start_credits and e.losses == [0, 0])
	check("a stale round number can award again after a reset", e.award_round(1, 1, 0, false, members))
	e.leave(2)
	check("leaving removes the wallet", not e.credits.has(2))
	check("baseline: attackers keep a breaching tool, defenders a kit", e.baseline(true) == [t.base_ordinary, 0, 0] and e.baseline(false) == [0, 0, t.base_reinforce * t.reinforce_per_kit])
	check("losing team can afford a heavy charge plus a spare", t.start_credits + t.loss_base * 2 / 5 >= t.price_heavy + t.price_ordinary)
	# CS-style catalog: weapons, armor, medkit, not-yet-built items.
	e = Economy.new(MatchTuning.new())
	e.credits[1] = 5000
	check("rifle purchase deducts its price", e.buy(1, true, "service_rifle", 1, 0, true, true).ok and e.wallet(1) == 5000 - 2700)
	check("an owned weapon can't be bought twice", not e.buy(1, true, "service_rifle", 2, 1, true, true).ok and e.wallet(1) == 2300)
	check("armor and medkit are role-free", e.buy(1, true, "vest", 3, 0, true, true).ok and e.buy(2, false, "medkit", 1, 0, true, true).ok)
	check("grenades and attachments are buyable", "flash" in ShopCatalog.buyable(true) and "nvg" in ShopCatalog.buyable(false))
	check("weapon table: every catalog weapon has stats", ShopCatalog.ITEMS.filter(func(i: Dictionary) -> bool: return i.get("weapon", false)).all(func(i: Dictionary) -> bool: return Weapons.DEFS.has(i.id)))
	check("pistol is the free starting gun and tiers rise in price", Weapons.DEFS[Weapons.DEFAULT_SIDEARM].price == 0
		and Weapons.DEFS["smg"].price < Weapons.DEFS["service_rifle"].price and Weapons.DEFS["revolver"].price < Weapons.DEFS["smg"].price)
	e.reinforced = [500, 0]
	check("team reinforcement has no per-round cap by default", t.reinforce_allowance == 0 and e.can_reinforce(0) == "")
	e.tuning.reinforce_allowance = 4
	e.reinforced = [4, 0]
	check("an optional team allowance still caps per round", e.can_reinforce(0) != "" and e.can_reinforce(1) == "")
	e.new_round()
	check("allowance resets each round", e.can_reinforce(0) == "")

