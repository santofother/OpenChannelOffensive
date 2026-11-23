extends Node
## Headless bot match on Lightwell: `-- --match-host --bot-test --no-steam --port=N`.
## The host fills both teams with bots, readies, gives comms orders, then lets the bots play rounds with
## shortened timers. Checks: fill/hand-over, navigation, prep reinforcement, buying, fighting, bomb
## recovery/plant/defuse, comms orders + acknowledgement, empty hands and the wheel layout.
var g: Node3D
var net: NetMatch
var fails := 0


func start(scene: Node3D) -> void:
	g = scene
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("  PASS " if ok else "  FAIL ") + label + (" " + detail if detail != "" else ""))
	if not ok:
		fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _bots() -> Array:
	return net.slots.values().filter(func(s: NetMatch.Slot) -> bool: return s.bot)


func _run() -> void:
	await _wait(0.5)
	net = g.net
	check("host has a bot director", net != null and net.bots != null)
	if net == null or net.bots == null:
		_finish()
		return
	for i in 60:
		if net.bots.nav.ready:
			break
		await _wait(0.1)
	var counts := [0, 0]
	for s: NetMatch.Slot in net.slots.values():
		counts[s.team] += 1
	check("bots fill both teams to three", net.slots.size() == 6 and counts == [3, 3] and _bots().size() == 5, str(counts))
	check("navigation mesh baked", net.bots.nav.ready)
	var a_site: Vector3 = net.loop.rules.tuning.sites[0]
	var b_site: Vector3 = net.loop.rules.tuning.sites[1]
	for zone in g.attack_zone_count():
		var reachable := true
		for i in 3:
			for site: Vector3 in [a_site, b_site]:
				var route := net.bots.nav.path(g.spawn_at(i, zone)[0], site)
				reachable = reachable and route.size() > 2 and route[-1].distance_to(site) < 0.8
		check("bot navigation reaches both sites from zone %d" % zone, reachable)
	var route := net.bots.nav.path(g.spawn_at(3)[0], a_site)
	check("navigation reaches site A from the defend spawn", route.size() > 1 and route[route.size() - 1].distance_to(a_site) < 0.8)

	# A person joining takes a bot's slot; leaving gives it back.
	net.bots.make_room()
	check("a joining person frees one bot slot", net.slots.size() == 5)
	net.bots.fill()
	check("an empty slot is refilled by a bot", net.slots.size() == 6 and _bots().size() == 5)

	# Comms wheel geometry and comms orders.
	var wheel := net.voice.wheel
	check("wheel: straight up picks the first slice, centre picks nothing", wheel._slice_at(Vector2(0, -120)) == 0 and wheel._slice_at(Vector2(4, 4)) == -1)
	check("wheel has radio and hand-signal slices", "radio" in Comms.WHEEL and "signals" in Comms.WHEEL)
	check("comms wheel defaults to the middle mouse button", Keys.key("comm_wheel") == "MMB")

	# Lobby: bots are ready; host readies and the round starts.
	var rules := net.loop.rules
	rules.tuning.prep = 12.0
	rules.tuning.live = 75.0
	rules.tuning.fuse = 20.0
	rules.tuning.resolution = 2.0
	await _wait(0.3)
	check("bots ready themselves in the lobby", _bots().all(func(s: NetMatch.Slot) -> bool: return rules.ready.get(s.id, false)))
	net.loop.request("ready")
	for i in 40:
		if rules.phase == RoundRules.Phase.PREP:
			break
		await _wait(0.1)
	check("round starts with bots", rules.phase == RoundRules.Phase.PREP)
	await _wait(0.6)
	var bought := _bots().filter(func(s: NetMatch.Slot) -> bool: return s.lo.armor > 0 or s.lo.primary != "")
	check("bots buy equipment in prep", bought.size() >= 3, "%d bought" % bought.size())

	# Empty hands: selecting a tool with none left shows only the arms.
	var lo: Loadout = g.loadout
	lo.charges[Loadout.Tool.HEAVY_CHARGE] = 0
	lo.select(Loadout.Tool.HEAVY_CHARGE)
	check("a tool with none left shows empty hands", lo.viewmodel.item_key() == Viewmodel.EMPTY_HANDS)
	lo.select(Loadout.Tool.RIFLE)

	# Host (an attacker) orders its teammate bots.
	var mates := _bots().filter(func(s: NetMatch.Slot) -> bool: return s.team == net.slots[1].team)
	net.voice._ping_at.clear()
	net.voice._action_host(1, net.round_id, Comms.Kind.GO_B)
	var ordered := mates.all(func(s: NetMatch.Slot) -> bool:
		var b: BotBrain = net.bots.brains[s.id]
		return b.has_order() and String(b.order.kind) == "move" and Vector3(b.order.pos).distance_to(b_site) < 1.0)
	check("'Go to B' orders every teammate bot to site B", ordered)
	check("'Go to B' sets the team's attack site", net.bots.attack_site(net.slots[1].team).distance_to(b_site) < 0.01)
	await _wait(0.9)
	check("a bot acknowledges on the team feed", net.voice._feed_lines.any(func(e: Array) -> bool: return "Affirmative" in String(e[1])))
	net.voice._ping_at.clear()
	net.voice._action_host(1, net.round_id, Comms.Kind.ON_ME)
	check("'Regroup on me' makes bots follow the caller", mates.all(func(s: NetMatch.Slot) -> bool:
		return String((net.bots.brains[s.id] as BotBrain).order.get("kind", "")) == "follow"))
	net.voice._ping_at.clear()
	net.voice._action_host(1, net.round_id, Comms.Kind.AS_YOU_WERE)
	check("'As you were' clears bot orders", mates.all(func(s: NetMatch.Slot) -> bool: return not (net.bots.brains[s.id] as BotBrain).has_order()))

	# Let the bots play. The host steps out (down) and drops the bomb so a bot must carry it.
	var start_pos := {}
	for s: NetMatch.Slot in _bots():
		start_pos[s.id] = net.spawn_for(s)[0]
	var defenders := 1 - rules.attack_team
	for i in 160:
		if rules.phase == RoundRules.Phase.LIVE:
			break
		await _wait(0.1)
	check("defender bots reinforce walls during prep", net.loop.econ.reinforced[defenders] > 0 or _any_reinforced(), "team panels %d" % net.loop.econ.reinforced[defenders])
	check("round goes live", rules.phase == RoundRules.Phase.LIVE)
	_test_stealth_and_chatter()
	_test_site_comms()
	await _test_solid_open_door()
	var shots := 0
	var carried_by_bot := false
	var planted := false
	var kills := false
	var resolved := 0
	var t0 := Time.get_ticks_msec()
	var far := {}
	var reason := ""
	var last_round := rules.round_number
	while Time.get_ticks_msec() - t0 < 150000 and resolved < 2:
		await _wait(0.25)
		if rules.phase == RoundRules.Phase.LIVE and net.slots[1].alive:
			net._on_player_hit(1, 1000.0, 1) # the host stays out; the bomb drops where it stood
		for s: NetMatch.Slot in _bots():
			shots = maxi(shots, s.lo.shots_fired)
			if s.alive and start_pos.has(s.id) and rules.phase in [RoundRules.Phase.LIVE, RoundRules.Phase.PLANTED]:
				far[s.id] = maxf(float(far.get(s.id, 0.0)), _flat(s.node.global_position, start_pos[s.id]))
		if rules.phase == RoundRules.Phase.RESOLUTION and reason == "":
			reason = rules.reason
			print("  round over: %s (%.0f s)" % [reason, (Time.get_ticks_msec() - t0) / 1000.0])
		if rules.carrier != 0 and net.slots.has(rules.carrier) and net.slots[rules.carrier].bot:
			carried_by_bot = true
		if rules.phase == RoundRules.Phase.PLANTED:
			planted = true
		if _bots().any(func(s: NetMatch.Slot) -> bool: return not s.alive):
			kills = true
		if rules.round_number != last_round:
			last_round = rules.round_number
			resolved += 1
			reason = ""
			for s: NetMatch.Slot in _bots():
				start_pos[s.id] = net.spawn_for(s)[0]
	var moved := far.values().filter(func(d: float) -> bool: return d > 6.0).size()
	check("bots travel the map", moved >= 4, "%d bots went >6 m from spawn: %s" % [moved, far.values()])
	check("a bot recovers and carries the dropped bomb", carried_by_bot)
	check("bots fire at enemies", shots > 0, "max shots %d" % shots)
	check("bots eliminate each other", kills)
	check("bots finish rounds on their own", resolved >= 1, "resolved %d, planted=%s" % [resolved, planted])
	print("  bomb planted during the run: %s" % planted)
	await _plant_scenario(rules)
	_finish()


func _test_stealth_and_chatter() -> void:
	var player: NetMatch.Slot = net.slots[1]
	var enemies := _bots().filter(func(s: NetMatch.Slot) -> bool: return s.team != player.team)
	var scout: NetMatch.Slot = enemies[0]
	var brain: BotBrain = net.bots.brains[scout.id]
	var player_pos := player.node.global_position
	var player_yaw := player.node.rotation.y
	var scout_pos := scout.node.global_position
	var scout_yaw := scout.node.rotation.y
	var mates := _bots().filter(func(s: NetMatch.Slot) -> bool: return s.team == player.team)
	for s: NetMatch.Slot in mates:
		s.alive = false
	brain.new_round()
	var bounds: Array = g.layout.data.bounds
	var position: Vector3 = g.layout.world(bounds[0] + 2.0, bounds[1] + 12.0, .05)
	scout.node.teleport(position, 0.0)
	player.node.teleport(position + Vector3(0, 0, 2.4), 0.0)
	brain._perceive(scout)
	check("silent player behind a bot at close range stays undetected", brain.target_id() == 0 and brain._heard_step == Vector3.INF)
	var step := player.node.global_position + Vector3.UP * 0.18
	net.bots.on_footstep(1, step, ProcAudio.Gait.CROUCH, false)
	check("crouch is inaudible at slow-walk distance", brain._heard_step == Vector3.INF)
	net.bots.on_footstep(1, step, ProcAudio.Gait.SLOW, false)
	check("slow walk at close range alerts hearing without granting a target", brain._heard_step == step and brain.target_id() == 0)
	brain.new_round()
	player.node.teleport(position + Vector3(0, 0, 6.0), 0.0)
	step = player.node.global_position + Vector3.UP * 0.18
	net.bots.on_footstep(1, step, ProcAudio.Gait.SLOW, false)
	check("slow walk is inaudible at normal walking distance", brain._heard_step == Vector3.INF)
	net.bots.on_footstep(1, step, ProcAudio.Gait.WALK, false)
	check("normal walking alerts a bot behind its view cone", brain._heard_step == step and brain.target_id() == 0)
	brain.set_order({"kind": "move", "pos": position + Vector3(0, 0, -4)})
	var alert_cmd := brain.make_cmd(scout)
	check("a heard step turns the bot without stopping movement", alert_cmd.move.length() > 0.8 and absf(alert_cmd.yaw) > 0.01)
	scout.node.set_look(180.0, 0.0)
	brain._perceive(scout)
	var cmd := NetCmd.new()
	brain._fight(scout, cmd)
	check("visual contact starts a shorter reaction delay without instant fire",
		brain.target_id() == 1 and brain._react > 0.30 and brain._react < 0.52 and not cmd.fire)
	var remaining := brain._react
	scout.node.set_look(0.0, 0.0)
	brain._perceive(scout)
	brain._react = 0.0
	cmd = NetCmd.new()
	brain._fight(scout, cmd)
	check("a lost target cannot trigger blind fire", not cmd.fire)
	brain._react = remaining
	brain._target_seen = net.tick - 8
	scout.node.set_look(180.0, 0.0)
	brain._perceive(scout)
	check("a brief visual interruption preserves the reaction already underway", brain._visible and brain._react == remaining)
	player.node.teleport(player_pos, rad_to_deg(player_yaw))
	scout.node.teleport(scout_pos, rad_to_deg(scout_yaw))
	for s: NetMatch.Slot in mates:
		s.alive = true
	net.bots._new_round()
	var room: String = g.radio_room(net.loop.rules.tuning.sites[0])
	check("radio names both actual Lightwell sites", room == "a" and g.radio_room(net.loop.rules.tuning.sites[1]) == "b")
	for key: String in BotRadio.ROOMS:
		check("radio contact and reply clips for " + key, ProcAudio.get_sound(BotRadio.cue(BotRadio.Kind.CONTACT, key)) != null
			and ProcAudio.get_sound(BotRadio.cue(BotRadio.Kind.RESPONDING, key)) != null)


func _test_site_comms() -> void:
	var rules := net.loop.rules
	var s: NetMatch.Slot = _bots().filter(func(slot: NetMatch.Slot) -> bool: return slot.team != rules.attack_team)[0]
	var old_pos := s.node.global_position
	var old_yaw := s.node.rotation.y
	var old_bomb := rules.bomb_pos
	var old_carrier := rules.carrier
	var others: Array = _bots().filter(func(slot: NetMatch.Slot) -> bool: return slot.team == s.team and slot.id != s.id)
	for mate: NetMatch.Slot in others:
		mate.alive = false
	net.slots[1].slow_walk = true
	var friendly: NetMatch.Slot = _bots().filter(func(slot: NetMatch.Slot) -> bool: return slot.team == net.slots[1].team)[0]
	check("friendly bots mirror the human's slow walk", net.bots.make_cmd(friendly).slow_walk)
	net.slots[1].slow_walk = false
	net.slots[1].crouching = true
	var mirrored := net.bots.make_cmd(friendly)
	check("friendly bots keep a quiet gait while the human crouches", mirrored.crouch and mirrored.slow_walk)
	net.slots[1].crouching = false
	net.voice.stolen[1] = s.team
	s.node.teleport(rules.tuning.sites[0], 0.0)
	net.bots._objective_comms()
	check("a bot announces its secured site", _said("Site A secured."))
	rules.phase = RoundRules.Phase.PLANTED
	rules.carrier = 0
	rules.site = 1
	rules.bomb_pos = rules.tuning.sites[1]
	check("defender bots start the search without the bomb's position", net.bots.bomb_location() == Vector3.INF)
	net.bots._objective_comms()
	check("a bot inspecting the empty site reports no bomb there", _said("No bomb at Site A.") and net.bots.bomb_location() == Vector3.INF)
	s.node.teleport(rules.tuning.sites[1], 0.0)
	net.bots._objective_comms()
	check("a bot reports a bomb reached on the upper floor", _said("Found the bomb at Site B.") and net.bots.bomb_location() == rules.bomb_pos)
	# A 1v1 retake: noises and a lost target must not keep the last defender off the bomb.
	var brain: BotBrain = net.bots.brains[s.id]
	s.node.teleport(rules.tuning.sites[0], 0.0)
	brain.investigate = rules.tuning.sites[0] + Vector3(4, 0, 0)
	brain.investigate_until = net.tick + 600
	brain.support(rules.tuning.sites[0] + Vector3(-4, 0, 0))
	rules.deadline = net.tick + 40 * NetMatch.TICK_RATE
	net.bots.make_cmd(s)
	check("the last defender heads for the known bomb over noises and backup calls",
		brain._path_goal != Vector3.INF and brain._path_goal.distance_to(rules.bomb_pos) < 0.5, str(brain._path_goal))
	brain.investigate = Vector3.INF
	brain.support_pos = Vector3.INF
	for site in ["a", "b"]:
		for kind in [BotRadio.Kind.NO_BOMB, BotRadio.Kind.SECURED, BotRadio.Kind.BOMB_HERE]:
			check("both rendered voices are available for " + BotRadio.text(kind, site),
				ProcAudio.get_sound(BotRadio.cue(kind, site)) != null and ProcAudio.get_sound(BotRadio.cue(kind, site, true)) != null)
	net.voice.stolen.erase(1)
	s.node.teleport(old_pos, rad_to_deg(old_yaw))
	for mate: NetMatch.Slot in others:
		mate.alive = true
	rules.phase = RoundRules.Phase.LIVE
	rules.site = -1
	rules.bomb_pos = old_bomb
	rules.carrier = old_carrier
	net.bots._new_round()


func _said(phrase: String) -> bool:
	return net.voice._feed_lines.any(func(entry: Array) -> bool: return phrase in String(entry[1]))


## At the Meter doorway, entering Cable and turning toward Pump Room can put a
## solid, open leaf across the route calculated on the static navigation mesh.
func _test_solid_open_door() -> void:
	var door: DoorSystem.Door
	for entry: Dictionary in g.layout.doors():
		if entry.level == 0 and g.layout.data.walls[entry.run].rooms == ["cable", "meter"]:
			for existing: DoorSystem.Door in g.doors.doors:
				if existing.header == entry.header:
					door = existing
					break
	if door == null:
		check("Meter door exists for the upstairs detour", false)
		return
	var slot: NetMatch.Slot = _bots().filter(func(bot: NetMatch.Slot) -> bool: return bot.team == net.loop.rules.attack_team)[0]
	var brain: BotBrain = net.bots.brains[slot.id]
	var old_pos := slot.node.global_position
	var old_yaw := slot.node.rotation.y
	var old_angle := door.angle
	var old_target := door.target
	door.target = g.doors._away(door, door.center(0.0) + Vector3.BACK) * DoorSystem.OPEN_ANGLE
	g.doors._pose(door, true)
	var leaf := door.body.global_basis.x
	var across := leaf.cross(Vector3.UP)
	var start := door.hinge + leaf * 0.74 + across * 0.53 + Vector3.UP * 0.05
	var goal := door.hinge + leaf * 0.90 - across * 0.8 + Vector3.UP * 0.05
	slot.bot = false
	slot.node.teleport(start, 0.0)
	for i in 2:
		await get_tree().physics_frame
	var blocked: bool = GameAudio.blocked(g.get_world_3d(), start + Vector3.UP, goal + Vector3.UP)
	var detoured := false
	brain.new_round()
	brain._yaw = slot.node.rotation.y
	for i in 200:
		var cmd := NetCmd.new()
		var direction := brain._door_direction(slot, goal - slot.node.global_position)
		direction.y = 0.0
		brain._set_move(cmd, direction.normalized())
		brain._finish(cmd)
		slot.node.simulate(cmd, NetMatch.DT)
		detoured = detoured or not brain._door_path.is_empty()
		if slot.node.global_position.distance_to(goal) < 0.25:
			break
	check("bot walks around the solid door leaf on the way into Cable Room",
		blocked and detoured and slot.node.global_position.distance_to(goal) < 0.35,
		"blocked=%s detoured=%s distance=%.2f" % [blocked, detoured, slot.node.global_position.distance_to(goal)])
	slot.node.teleport(old_pos, rad_to_deg(old_yaw))
	slot.bot = true
	door.target = old_target
	door.angle = old_angle
	g.doors._pose(door, false)
	brain.new_round()


## Remove the defenders at LIVE: attacker bots must recover the dropped bomb, carry it to a site and plant.
func _plant_scenario(rules: RoundRules) -> void:
	for i in 300:
		if rules.phase == RoundRules.Phase.LIVE:
			break
		await _wait(0.1)
	# One defender stays "alive" (stops thinking, parked off the map, can't be hurt) so the round continues.
	var parked := false
	for s: NetMatch.Slot in net.slots.values():
		if s.team == rules.attack_team:
			if s.id == 1:
				net._on_player_hit(1, 1000.0, 1)
		elif not parked and s.alive:
			parked = true
			s.bot = false
			net.test_teleport(s.id, g.spawn_at(3)[0] + Vector3(0, 0, 100), 0.0)
		else:
			net._on_player_hit(s.id, 1000.0, s.id)
	net.test_godmode = true
	net.bots._attack_site[rules.attack_team] = 1
	rules.deadline = net.tick + rules.ticks(110.0)
	var planted := false
	for i in 550:
		await _wait(0.2)
		if rules.phase == RoundRules.Phase.PLANTED:
			planted = rules.site == 1
			break
		if rules.phase != RoundRules.Phase.LIVE:
			break
	check("attacker bots carry the bomb upstairs and plant at B", planted,
		"phase=%d site=%d reason=%s" % [rules.phase, rules.site, rules.reason])


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _any_reinforced() -> bool:
	for m: WallModule in g.modules:
		if m.material == WallModule.Mat.REINFORCED:
			return true
	return false


func _finish() -> void:
	print("SMOKE_%s bots fails=%d" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
