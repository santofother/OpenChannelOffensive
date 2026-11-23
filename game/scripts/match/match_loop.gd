class_name MatchLoop
extends Node
## Match adapter: validates inputs and world queries, then advances the pure round rules once per tick.
var net: NetMatch
var rules := RoundRules.new()
var econ := Economy.new()
var performance := RoundPerformance.new()
var round_mvp := {}
var credits := 0 ## client: own wallet as last synced by the host (private per recipient)
var income := 0
var reinforce_used := 0
var team_encrypted := false ## client: own team's radio is encrypted this round
var debug_money := false ## host opt-in; clients receive this flag with the round state
var _buy_seq := 0
var menu: ShopMenu
var teammate_shop := {}
var _team_shop := [{}, {}]
var enabled := true
var inputs := {} # id -> {tick, hold, valid}; no client-reported positions or progress
var damaged := {}
var roster := {}
var _last_serial := -1
var _hud: Label
var _bomb: MeshInstance3D
var _camera: Camera3D
var _watch := 0
var watched_id := 0
var _request_at := {}
var _beep_slot := -1
var _defuse_beat := -1
var _heard_objective := {}
var script_hold := false
var outside_ticks := {} ## host: id -> consecutive ticks a defender has spent outside the building
var _barriers_on := false
var script_drop := false

func start(owner_match: NetMatch) -> void:
	net = owner_match
	name = "RoundLoop"
	rules.tuning = net.g.match_tuning()
	econ.tuning = rules.tuning
	performance.tuning = rules.tuning
	debug_money = net.is_host and NetworkManager.args.has("debug-money") and debug_tools_available()
	enabled = not NetworkManager.args.has("net-test") or NetworkManager.args.has("round-test")
	if not enabled:
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12, 168)
	_hud.add_theme_font_size_override("font_size", 19)
	_hud.size.x = 780
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 2)
	_hud.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_hud)
	var overlay := MatchOverlay.new()
	overlay.loop = self
	layer.add_child(overlay)
	menu = ShopMenu.new()
	menu.loop = self
	add_child(menu)
	_camera = Camera3D.new()
	_camera.name = "TeammateCamera"
	add_child(_camera)
	_bomb = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.18, 0.25)
	_bomb.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.04)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bomb.material_override = mat
	add_child(_bomb)
	for i in rules.tuning.sites.size():
		if i < rules.tuning.site_areas.size():
			continue
		var pos := rules.tuning.sites[i]
		var ring := MeshInstance3D.new()
		var mesh := TorusMesh.new()
		mesh.inner_radius = rules.tuning.site_radius - 0.04
		mesh.outer_radius = rules.tuning.site_radius + 0.04
		mesh.rings = 24
		ring.mesh = mesh
		ring.material_override = mat
		ring.position = pos
		add_child(ring)
		var label := Label3D.new()
		label.text = "SITE %s" % ["A", "B"][i]
		label.position = pos + Vector3(0, 0.18, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 64
		add_child(label)
	if net.is_host:
		sync()

func fill_cmd(c: NetCmd) -> void:
	if not enabled:
		return
	if net.g.player.scripted:
		c.interact = script_hold
		c.drop_bomb = script_drop
	elif net.g.player.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		c.interact = Input.is_action_pressed("interact")
		c.drop_bomb = Input.is_action_pressed("drop_bomb")

func accepts_combat() -> bool:
	return not enabled or rules.phase in [RoundRules.Phase.LIVE, RoundRules.Phase.PLANTED]

## Both authority and local prediction use the same role/phase gate.
func constrain(c: NetCmd, alive: bool, team: int) -> void:
	if not enabled:
		return
	var defender_prep := rules.phase == RoundRules.Phase.PREP and team != rules.attack_team and alive
	if not alive or (not accepts_combat() and not defender_prep):
		c.move = Vector2.ZERO
		c.slow_walk = false
		c.crouch = false
		c.lean = 0
		c.vault = false
	if not accepts_combat() or not alive:
		c.fire = c.fire and defender_prep and c.tool == Loadout.Tool.REINFORCE
		c.reload = false
	if c.interact:
		c.fire = false
		c.reload = false

func command(s: NetMatch.Slot, c: NetCmd) -> void:
	if not enabled:
		return
	# The carrier plants by holding fire with the bomb (slot 5) selected; F stays free for doors.
	var carrier := s.id == rules.carrier
	var planting := carrier and c.fire and c.tool == Loadout.Tool.BOMB
	inputs[s.id] = {"tick": net.tick, "hold": planting if carrier else c.interact,
		"valid": c.move.length() < 0.01 and (planting or not c.fire) and not c.reload and not c.drop_bomb}
	if c.drop_bomb and s.alive:
		rules.drop(s.id, s.node.global_position)

func blocked(from: Vector3, to: Vector3) -> bool:
	return not net.g.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()

## Shared F key: objective use takes priority over stealing a nearby radio. Host checks current
## phase, role, ownership, range and obstruction, rather than trusting a client-selected target.
func objective_available(id: int) -> bool:
	if not enabled:
		return false
	var s: NetMatch.Slot = net.slots.get(id)
	if s == null and (net.is_host or id != net.my_id or not net.my_alive):
		return false
	if s != null and not s.alive:
		return false
	var p: Player = s.node if s != null else net.g.player
	var team := s.team if s != null else net.local_team()
	if rules.phase == RoundRules.Phase.LIVE:
		if rules.carrier == id:
			return false # planting uses the slot-5 bomb, not F
		elif rules.carrier == 0 and team == rules.attack_team:
			return _near_bomb(p)
	elif rules.phase == RoundRules.Phase.PLANTED and team != rules.attack_team:
		return _near_bomb(p)
	return false

func _near_bomb(p: Player) -> bool:
	return (net.is_host or rules.bomb_pos != Vector3.ZERO) and p.global_position.distance_to(rules.bomb_pos) <= rules.tuning.interact_range \
		and not blocked(p.camera.global_position, rules.bomb_pos + Vector3(0, 0.15, 0))

func _host_roster() -> Dictionary:
	var out := {}
	for s: NetMatch.Slot in net.slots.values():
		var pos := s.node.global_position
		var site := rules.tuning.site_at(pos)
		var input: Dictionary = inputs.get(s.id, {})
		var hold := bool(input.get("hold", false)) and bool(input.get("valid", false)) \
			and net.tick - int(input.get("tick", -100)) <= 12 and s.node.velocity.length() < 0.2
		out[s.id] = {"team": s.team, "alive": s.alive, "pos": pos, "site": site,
			"hold": hold, "damaged": damaged.has(s.id),
			"near_bomb": _near_bomb(s.node), "kit": s.lo.defuse_kit}
	return out

func host_tick() -> void:
	if not enabled:
		return
	var before := rules.round_number
	var old_phase := rules.phase
	var previous_actor := rules.actor
	var previous_carrier := rules.carrier
	if old_phase == RoundRules.Phase.PLANTED and net.tick >= rules.deadline:
		for s: NetMatch.Slot in net.slots.values():
			if s.alive and s.node.global_position.distance_to(rules.bomb_pos) <= rules.tuning.bomb_blast_radius:
				net._on_player_hit(s.id, 1000.0, 0)
	rules.step(net.tick, _host_roster())
	damaged.clear()
	for s: NetMatch.Slot in net.slots.values():
		_bomb_slot(s.lo, s.team, s.id)
	_track_outside()
	_prep_barriers()
	if rules.phase == RoundRules.Phase.PLANTED and old_phase == RoundRules.Phase.LIVE:
		performance.record(previous_carrier, 0, false, true)
		performance.award(previous_carrier, rules.tuning.points_planted)
	if rules.phase == RoundRules.Phase.RESOLUTION and old_phase != RoundRules.Phase.RESOLUTION:
		if rules.reason == "Bomb defused":
			performance.record(previous_actor, 0, false, true)
			performance.award(previous_actor, rules.tuning.points_defused)
			if net.slots.has(previous_actor):
				(net.slots[previous_actor] as NetMatch.Slot).lo.defuse_kit = false # a kit is spent on a defuse
		var members := {}
		var alive: Array = []
		for s: NetMatch.Slot in net.slots.values():
			members[s.id] = s.team
			if s.alive:
				alive.append(s.id)
				if not performance.died_this_round.has(s.id):
					performance.award(s.id, rules.tuning.points_survived)
		var names := {}
		for s: NetMatch.Slot in net.slots.values():
			names[s.id] = {"team":s.team, "name":s.pname}
		round_mvp = performance.mvp(rules.winner, names)
		econ.award_round(rules.round_number, rules.winner, rules.attack_team, rules.site >= 0, members, alive)
		sync()
	if rules.round_number != before:
		performance.reset()
		round_mvp.clear()
		inputs.clear()
		# Credits carry between rounds; a new match and the side swap both start everyone fresh.
		var fresh := rules.round_number == 1 or rules.round_number == rules.tuning.swap_after + 1
		if fresh:
			econ.reset_all()
		econ.new_round()
		_capture_carry(not fresh)
		net.rotate_attack_zone()
		net.assign_spawns(rules.attack_team)
		net.restart_round()
	if rules.phase != old_phase and rules.phase in [RoundRules.Phase.RESOLUTION, RoundRules.Phase.RESULT]:
		# Fuses stop at resolution; no late destruction may mutate a settled round.
		for c: Node in get_tree().get_nodes_in_group("charges"):
			if c is Charge and c.module:
				c.module.charge = null
			c.free()
	if rules.serial != _last_serial or rules.actor != previous_actor or net.tick % 6 == 0:
		sync()

func sync() -> void:
	if not enabled or not net.is_host:
		return
	roster.clear()
	_team_shop = [{}, {}]
	for s: NetMatch.Slot in net.slots.values():
		roster[s.id] = {"team": s.team, "name": s.pname, "alive": s.alive, "bot": s.bot, "stats": performance.score(s.id)}
		if rules.phase == RoundRules.Phase.PREP and s.alive:
			var owned := {}
			for item: String in ShopCatalog.buyable(s.team == rules.attack_team):
				owned[item] = ShopCatalog.owned(s.lo, item)
			_team_shop[s.team][s.id] = {"owned": owned, "armor": s.lo.armor, "helmet": s.lo.helmet,
				"defuse_kit": s.lo.defuse_kit}
	_last_serial = rules.serial
	if net.slots.has(net.my_id):
		_apply_mine(state(net.my_id).mine) # the host is never one of its own ready_peers
	for id: int in net.ready_peers:
		net._send(id, net._rel(NetMatch.Msg.EVENT, [NetMatch.Ev.LOOP, net.round_id, state(id)]), true)

## Free equipment each round: sidearm plus the role's starter tool. Survivors keep guns/armor (carry);
## the dead, side swaps and new matches start from the default pistol.
var _carry := {}


func _capture_carry(keep: bool) -> void:
	_carry.clear()
	if not keep:
		return
	for s: NetMatch.Slot in net.slots.values():
		if s.alive:
			_carry[s.id] = {"primary": s.lo.primary, "secondary": s.lo.secondary, "armor": s.lo.armor, "helmet": s.lo.helmet,
				"defuse_kit": s.lo.defuse_kit and s.team != rules.attack_team}

func apply_baseline(s: NetMatch.Slot) -> void:
	if not enabled:
		return
	var b := econ.baseline(s.team == rules.attack_team)
	s.lo.charges[Loadout.Tool.ORDINARY_CHARGE] = b[0]
	s.lo.charges[Loadout.Tool.HEAVY_CHARGE] = b[1]
	s.lo.charges[Loadout.Tool.REINFORCE] = b[2]
	var c: Dictionary = _carry.get(s.id, {"primary": "", "secondary": Weapons.DEFAULT_SIDEARM, "armor": 0, "helmet": false})
	s.lo.set_gear(c.primary, c.secondary)
	s.lo.armor = c.armor
	s.lo.helmet = c.helmet
	# An unused kit stays with a surviving defender (the side swap starts fresh anyway).
	s.lo.defuse_kit = bool(c.get("defuse_kit", false)) and s.team != rules.attack_team

func reinforce_gate(id: int) -> String:
	if not net.slots.has(id):
		return "Not available"
	var s: NetMatch.Slot = net.slots[id]
	if enabled:
		if not s.alive or s.team == rules.attack_team:
			return "Only living defenders can reinforce"
		if rules.phase not in [RoundRules.Phase.PREP, RoundRules.Phase.LIVE, RoundRules.Phase.PLANTED]:
			return "Reinforcement is unavailable in this phase"
	return econ.can_reinforce(s.team)

func note_reinforced(id: int) -> void:
	if net.slots.has(id):
		econ.reinforced[(net.slots[id] as NetMatch.Slot).team] += 1
		reward(id, econ.tuning.reinforce_reward, "reinforcement")
		performance.award(id, rules.tuning.points_reinforced)
		sync()

func _planted_position_for(listener: NetMatch.Slot) -> Vector3:
	if listener.team == rules.attack_team:
		return rules.bomb_pos
	if listener.alive and listener.node.global_position.distance_to(rules.bomb_pos) <= rules.tuning.bomb_beep_range:
		return rules.bomb_pos
	return Vector3.ZERO

func state(for_id: int = 0) -> Dictionary:
	var d := rules.state()
	# Carried-bomb coordinates would otherwise leak an enemy's position to a dead listener.
	if for_id != 0 and rules.carrier != 0 and not net.can_observe(for_id, rules.carrier):
		d.bomb_pos = Vector3.ZERO
	var mine := {"credits": 0, "income": 0, "reinforced": 0}
	if for_id != 0 and net.slots.has(for_id):
		var listener: NetMatch.Slot = net.slots[for_id]
		if listener.team != rules.attack_team:
			d.action_site = -1
		if rules.phase == RoundRules.Phase.PLANTED and listener.team != rules.attack_team:
			d.site = -1
			d.bomb_pos = _planted_position_for(listener)
			if d.bomb_pos == Vector3.ZERO:
				d.actor = 0
				d.progress = 0
				d.action_ticks = 0
		mine = {"credits": econ.wallet(for_id), "income": int(econ.income.get(for_id, 0)),
			"reinforced": econ.reinforced[(net.slots[for_id] as NetMatch.Slot).team],
			"encrypted": econ.encrypted[listener.team], "shop": _team_shop[listener.team]}
	return {"rules": d, "roster": roster.duplicate(true), "mine": mine, "debug_money": debug_money, "mvp": round_mvp.duplicate(true)}

func receive(d: Dictionary, initial := false) -> void:
	if not enabled:
		return
	# Reliable messages from host only. Serial also protects manually injected stale same-round state.
	if int(d.rules.serial) < rules.serial:
		return
	var prior_offense := rules.attack_team
	rules.apply(d.rules)
	if prior_offense != rules.attack_team:
		net.refresh_remote_colors()
	roster = d.roster
	round_mvp = d.get("mvp", {})
	debug_money = bool(d.get("debug_money", false))
	_apply_mine(d.get("mine", {}))
	if initial:
		_heard_objective = _objective_audio_state()
		_beep_slot = -1
	if rules.phase in [RoundRules.Phase.RESOLUTION, RoundRules.Phase.RESULT]:
		for c: Node in get_tree().get_nodes_in_group("charges"):
			if c is Charge and c.module:
				c.module.charge = null
			c.free()

func _apply_mine(mine: Dictionary) -> void:
	credits = int(mine.get("credits", credits))
	income = int(mine.get("income", 0))
	reinforce_used = int(mine.get("reinforced", 0))
	team_encrypted = bool(mine.get("encrypted", false))
	teammate_shop = mine.get("shop", {})

## Host: pay in-round income and show it to the earner.
func reward(id: int, amount: int, why: String) -> void:
	if not enabled or not net.is_host or rules.phase not in [RoundRules.Phase.PREP, RoundRules.Phase.LIVE, RoundRules.Phase.PLANTED]:
		return
	var got := econ.earn(id, amount)
	if got > 0 and id == net.my_id and why != "":
		net.g.loadout.say("+$%d %s" % [got, why])

func departed(id: int, pos: Vector3) -> void:
	rules.drop(id, pos)
	rules.ready.erase(id)
	inputs.erase(id)
	damaged.erase(id)
	_request_at.erase(id)
	econ.leave(id)
	performance.leave(id)

## Ask the host to buy a catalog item (id string). Host applies directly; clients send a request ID.
func request_buy(item: String, recipient := 0) -> void:
	if not enabled:
		return
	_buy_seq += 1
	if net.is_host:
		_buy_host(net.my_id, net.round_id, _buy_seq, item, recipient)
	else:
		_buy.rpc_id(1, net.round_id, _buy_seq, item, recipient)

@rpc("any_peer", "call_remote", "reliable", 0)
func _buy(r: int, request_id: int, item: String, recipient: int) -> void:
	if net.is_host:
		_buy_host(multiplayer.get_remote_sender_id(), r, request_id, item, recipient)

func _buy_host(id: int, r: int, request_id: int, item: String, recipient := 0) -> Dictionary:
	if not enabled or not net.slots.has(id):
		return {}
	var buyer: NetMatch.Slot = net.slots[id]
	var res: Dictionary
	if r != net.round_id:
		res = {"ok": false, "reason": "Round changed", "item": item, "credits": econ.wallet(id), "request": request_id}
	else:
		var target: NetMatch.Slot = net.slots.get(recipient if recipient != 0 else id)
		var eligible := target != null and target.team == buyer.team and target.alive
		var owned := ShopCatalog.owned(target.lo, item) if eligible else 0
		if item == "encrypt":
			owned = int(econ.encrypted[buyer.team])
		res = econ.buy(id, buyer.team == rules.attack_team, item, request_id, owned,
			rules.phase == RoundRules.Phase.PREP, buyer.alive, "" if eligible else "Teammate unavailable")
		if res.ok and not res.get("duplicate", false):
			ShopCatalog.grant(target.lo, item)
			if item == "encrypt":
				econ.encrypted[buyer.team] = true
			if target.id != id:
				res.recipient_name = target.pname
				var message := "%s bought you %s" % [buyer.pname, ShopCatalog.find(item).name]
				if target.id == net.my_id:
					_gift_received(message)
				elif target.id in net.ready_peers:
					_gift_received.rpc_id(target.id, message)
		elif item == "encrypt" and econ.encrypted[buyer.team] and not res.ok:
			res.reason = "Your team already has an encrypted radio this round"
	if id == net.my_id:
		_apply_buy_result(res)
	elif id in net.ready_peers:
		_buy_result.rpc_id(id, res) # bots have no peer to answer
	sync()
	return res

@rpc("authority", "call_remote", "reliable", 0)
func _buy_result(res: Dictionary) -> void:
	_apply_buy_result(res)

@rpc("authority", "call_remote", "reliable", 0)
func _gift_received(message: String) -> void:
	net.g.loadout.say(message)
	menu.show_feedback(message)


func _apply_buy_result(res: Dictionary) -> void:
	var text: String
	if res.get("ok", false):
		var recipient := " for " + String(res.recipient_name) if res.has("recipient_name") else ""
		text = "Bought %s%s ($%d left)" % [ShopCatalog.find(String(res.item)).name, recipient, int(res.credits)]
	else:
		text = String(res.get("reason", "Purchase failed"))
	if not res.get("duplicate", false):
		ProcAudio.play(self, "buy" if res.get("ok", false) else "reject", null, -9.0)
	net.g.loadout.say(text)
	menu.show_feedback(text)

func request(action: String) -> void:
	if net.is_host:
		_action_host(net.my_id, net.round_id, action)
	else:
		_action.rpc_id(1, net.round_id, action)

@rpc("any_peer", "call_remote", "reliable", 0)
func _action(r: int, action: String) -> void:
	if net.is_host:
		_action_host(multiplayer.get_remote_sender_id(), r, action)

func debug_tools_available() -> bool:
	return OS.is_debug_build() or NetworkManager.args.has("dev")

func _action_host(id: int, r: int, action: String) -> void:
	if not enabled or r != net.round_id or not net.slots.has(id):
		return
	if net.tick - int(_request_at.get(id, -60)) < 15:
		return
	_request_at[id] = net.tick
	if action.begins_with("take_over:"):
		var target := action.get_slice(":", 1)
		if not target.is_valid_int() or not net.take_over_bot(id, target.to_int()):
			return
	elif action == "debug_money_toggle":
		if id != 1 or not debug_tools_available() or rules.phase != RoundRules.Phase.PREP:
			return
		debug_money = not debug_money
	elif action == "debug_money_fill":
		if not debug_money or rules.phase != RoundRules.Phase.PREP or not (net.slots[id] as NetMatch.Slot).alive:
			return
		econ.credits[id] = econ.tuning.credit_cap
	elif action == "rematch" and id == 1 and rules.phase == RoundRules.Phase.RESULT:
		rules.rematch()
		performance.reset_match()
		inputs.clear()
		net.assign_spawns(0)
		net.restart_round()
	elif rules.phase == RoundRules.Phase.LOBBY:
		if action == "ready":
			rules.ready[id] = not rules.ready.get(id, false)
		elif action == "team":
			var s: NetMatch.Slot = net.slots[id]
			var count := 0
			for other: NetMatch.Slot in net.slots.values():
				if other.team != s.team:
					count += 1
			if count >= 3 and net.bots and net.bots.swap_out(1 - s.team):
				count -= 1 # a bot on the full team moves over to make room
			if count < 3:
				s.team = 1 - s.team
				rules.ready[id] = false
				net.assign_spawns(0)
				net.restart_round()
		else:
			return
	else:
		return
	rules.serial += 1
	sync()

func _toggle_menu() -> void:
	if rules.phase == RoundRules.Phase.PREP and net.local_alive():
		menu.toggle()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("ready_toggle"):
			request("ready")
		elif event.is_action_pressed("team_switch"):
			request("team")
		elif rules.phase == RoundRules.Phase.RESULT and event.is_action_pressed("rematch"):
			request("rematch")
		elif not net.local_alive() and event.is_action_pressed("take_over_bot"):
			if roster.get(watched_id, {}).get("bot", false):
				request("take_over:%d" % watched_id)
		elif not net.local_alive() and event.is_action_pressed("spectate_next"):
			_watch += 1
		elif event.is_action_pressed("buy_menu"):
			_toggle_menu()

var _shown_phase := -1
var _shown_round := -1

func _objective_audio_state() -> Dictionary:
	var point := rules.bomb_pos
	# On the host the carried objective can still reference an unseen player while spectating.
	if rules.carrier != 0 and net.is_host and not net.can_observe(net.my_id, rules.carrier):
		point = Vector3.ZERO
	if rules.phase == RoundRules.Phase.PLANTED and net.is_host:
		point = _planted_position_for(net.slots[net.my_id])
	return {"round": rules.round_number, "phase": rules.phase, "carrier": rules.carrier,
		"actor": rules.actor if point != Vector3.ZERO else 0, "point": point}

func _objective_audio(seconds_left: float) -> void:
	var previous := _heard_objective
	var current := _objective_audio_state()
	_heard_objective = current
	var point: Vector3 = current.point + Vector3.UP * 0.2
	if not previous.is_empty() and current.round == previous.round:
		if current.phase != previous.phase and current.phase == RoundRules.Phase.PLANTED:
			ProcAudio.play(self, "bomb_planted", null, -4.0)
		elif current.phase != previous.phase and current.phase == RoundRules.Phase.RESOLUTION:
			if rules.reason == "Bomb defused":
				ProcAudio.play(self, "bomb_defused", null, -4.0)
			elif rules.reason == "Bomb exploded":
				var caught: bool = net.g.player.global_position.distance_to(rules.bomb_pos) <= rules.tuning.bomb_blast_radius
				ProcAudio.play(self, "boom_heavy", null if caught else point)
				if net.g.loadout.effects:
					net.g.loadout.effects.burst(point, Vector3.UP, true, true)
			ProcAudio.play(self, "round_win" if rules.winner == net.local_team() else "round_loss", null, -10.0)
		elif current.phase == previous.phase:
			if current.carrier != previous.carrier:
				if current.carrier == 0:
					ProcAudio.play(self, "bomb_drop", point)
				else:
					ProcAudio.play(self, "bomb_pickup", previous.point + Vector3.UP * 0.2)
			if current.actor != previous.actor:
				var planted: bool = current.phase == RoundRules.Phase.PLANTED
				if previous.actor != 0 and (planted or previous.point != Vector3.ZERO):
					ProcAudio.play(self, "bomb_interrupted", previous.point + Vector3.UP * 0.2)
				if current.actor != 0 and (planted or current.point != Vector3.ZERO):
					ProcAudio.play(self, "defuse_start" if planted else "plant_start", point)
	if int(current.actor) == 0 or rules.phase != RoundRules.Phase.PLANTED:
		_defuse_beat = -1
	else:
		var beat := rules.progress / 36
		if beat != _defuse_beat:
			_defuse_beat = beat
			ProcAudio.play(self, "defuse_work", null if current.actor == net.my_id else point, -3.0, "", 10.0)
	if rules.phase != RoundRules.Phase.PLANTED:
		_beep_slot = -1
		return
	if current.point == Vector3.ZERO:
		return
	var slot := int(ceil(seconds_left / 2.0)) * 4
	if seconds_left <= 10.0:
		slot = int(ceil(seconds_left)) * 2
	if seconds_left <= 4.0:
		slot = int(ceil(seconds_left * 2.0))
	# Smoothing the network clock can nudge it backwards across a beat boundary.
	if seconds_left > 0.0 and (_beep_slot < 0 or slot < _beep_slot):
		_beep_slot = slot
		ProcAudio.play(self, "bomb_urgent" if seconds_left <= 4.0 else "bomb_tick", point, 1.0, "", rules.tuning.bomb_beep_range)


## Defenders who stay outside the building for longer than `outside_reveal` seconds are
## revealed to attackers until they go back in. The courtyard counts as inside.
func _track_outside() -> void:
	var revealed: Array = []
	var active := rules.phase in [RoundRules.Phase.LIVE, RoundRules.Phase.PLANTED]
	for s: NetMatch.Slot in net.slots.values():
		if active and s.alive and s.team != rules.attack_team and net.g.is_outside(s.node.global_position):
			outside_ticks[s.id] = int(outside_ticks.get(s.id, 0)) + 1
		else:
			outside_ticks.erase(s.id)
		if int(outside_ticks.get(s.id, 0)) > rules.ticks(rules.tuning.outside_reveal):
			revealed.append(s.id)
	revealed.sort()
	if revealed != rules.spotted:
		rules.spotted = revealed
		rules.serial += 1

## Defenders stay inside during prep: exterior doorways are blocked until the round goes live.
func _prep_barriers() -> void:
	var on := enabled and rules.phase == RoundRules.Phase.PREP
	if on != _barriers_on:
		_barriers_on = on
		net.g.set_prep_barriers(on)

## Attackers' slot 5 is the bomb while they carry it, else empty; defenders keep the kit there.
func _bomb_slot(lo: Loadout, team: int, id: int) -> void:
	lo.bomb_slot = rules.phase != RoundRules.Phase.LOBBY and team == rules.attack_team
	lo.has_bomb = lo.bomb_slot and rules.carrier == id and rules.phase in [RoundRules.Phase.PREP, RoundRules.Phase.LIVE]

func _process(_delta: float) -> void:
	if enabled and not net.is_host:
		_bomb_slot(net.g.loadout, net.local_team(), net.my_id)
		_prep_barriers()
	if not enabled:
		return
	var team := net.local_team()
	var alive := net.local_alive()
	# The buy menu opens by itself once per prep phase (not in headless tests); B reopens it.
	if rules.phase == RoundRules.Phase.PREP and (_shown_phase != rules.phase or _shown_round != rules.round_number):
		if alive and DisplayServer.get_name() != "headless" and not menu.is_open:
			menu.open()
	_shown_phase = rules.phase
	_shown_round = rules.round_number
	var now := float(net.tick) if net.is_host else net._server_tick_f
	var seconds_left := maxf((rules.deadline - now) / NetMatch.TICK_RATE, 0.0)
	var left := int(ceil(seconds_left))
	_objective_audio(seconds_left)
	var phase_name: String = ["LOBBY", "PREP", "LIVE", "BOMB PLANTED", "ROUND OVER", "MATCH RESULT"][rules.phase]
	var role := "ATTACK — plant at A or B" if team == rules.attack_team else "DEFEND — protect A and B"
	var text := "%s | %s | %d:%02d\nRed %d — Blue %d | Round %d · First to %d" % [role, phase_name, left / 60, left % 60,
		rules.scores[0], rules.scores[1], rules.round_number, rules.wins_needed()]
	if rules.phase == RoundRules.Phase.LOBBY:
		text += "\n%s ready/unready · %s change team (max 3)\nBoth teams and everyone ready to start" % [Keys.key("ready_toggle"), Keys.key("team_switch")]
		for id: int in roster:
			text += "\n%s %s: %s" % ["Red" if int(roster[id].team) == 0 else "Blue", roster[id].name,
				"READY" if rules.ready.get(id, false) else "waiting"]
	elif rules.phase == RoundRules.Phase.PREP:
		text += "\nCredits $%d · %s opens the buy menu" % [credits, Keys.key("buy_menu")]
		text += "\nAttackers wait for LIVE" if team == rules.attack_team else "\nMove to prepare inside · exits open at LIVE · %s kit · hold %s on an intact wall (%d left · team reinforced %d)" % [Keys.key("tool_5"), Keys.key("primary_fire"), net.g.loadout.charges[Loadout.Tool.REINFORCE], reinforce_used]
		if debug_money:
			text += "\nDEBUG MONEY enabled · fill wallet in the buy menu"
		text += "\nSurvivors keep guns, armor and unused defuse kits; breach tools reset each round. Credits reset at the side swap."
	elif rules.phase in [RoundRules.Phase.RESOLUTION, RoundRules.Phase.RESULT]:
		var outcome := "DRAW" if rules.winner < 0 else ("RED WINS" if rules.winner == 0 else "BLUE WINS")
		text += "\n%s · %s" % [outcome, rules.reason]
		text += "\nCredits $%d (+$%d)" % [credits, income]
		if rules.phase == RoundRules.Phase.RESULT:
			text += "\nHost: %s rematch · Esc → Leave Game" % Keys.key("rematch")
	else:
		if rules.carrier == net.my_id:
			text += "\nYou carry the bomb · %s bomb, then hold %s inside A/B to plant · %s drop" % [Keys.key("tool_5"), Keys.key("primary_fire"), Keys.key("drop_bomb")]
		elif rules.phase == RoundRules.Phase.PLANTED:
			if team == rules.attack_team:
				text += "\nDefend Site %s" % ["A", "B"][rules.site]
			elif alive and objective_available(net.my_id):
				text += "\nHold %s to defuse" % Keys.key("interact")
			else:
				text += "\nLocate the bomb"
		else:
			text += "\nBomb: %s · hold %s near a dropped bomb to recover" % ["carried" if rules.carrier != 0 else "DROPPED", Keys.key("interact")]
		text += "\nCredits $%d (+$%d this round)" % [credits, income]
		if team != rules.attack_team:
			text += "\n%s kit · hold %s on an intact panel to reinforce (%d left · team reinforced %d)" % [Keys.key("tool_5"), Keys.key("primary_fire"), net.g.loadout.charges[Loadout.Tool.REINFORCE], reinforce_used]
	_spectate(team, alive)
	if not alive and rules.phase != RoundRules.Phase.LOBBY:
		if watched_id != 0:
			text += "\nSpectating %s · %s next teammate" % [roster.get(watched_id, {}).get("name", ""), Keys.key("spectate_next")]
			if accepts_combat() and roster.get(watched_id, {}).get("bot", false) and net.local_can_take_over():
				text += " · %s take over bot" % Keys.key("take_over_bot")
		elif rules.phase == RoundRules.Phase.PLANTED and team == rules.attack_team:
			text += "\nSpectating the planted bomb"
		else:
			text += "\nWaiting for the next round"
	_hud.text = text
	_hud.visible = not net.g._panel.visible and not menu.is_open
	var point := rules.bomb_pos
	if rules.phase == RoundRules.Phase.PLANTED and net.is_host:
		point = _planted_position_for(net.slots[net.my_id])
	_bomb.visible = rules.carrier == 0 and point != Vector3.ZERO and rules.phase in [RoundRules.Phase.LIVE, RoundRules.Phase.PLANTED]
	_bomb.position = point + Vector3(0, 0.12, 0)

func _spectate(team: int, alive: bool) -> void:
	if net.g.loadout.viewmodel:
		net.g.loadout.viewmodel.visible = alive
	watched_id = 0
	if alive or rules.phase == RoundRules.Phase.LOBBY:
		_watch = 0
		# Spectating hides the followed body. Restore it on respawn/rematch as well
		# as switching cameras; otherwise that teammate stays invisible locally.
		if net.is_host:
			for slot: NetMatch.Slot in net.slots.values():
				if slot.body_vis:
					slot.body_vis.visible = true
		else:
			for remote: NetMatch.Remote in net.remotes.values():
				remote.vis.visible = true
		if _camera.current:
			net.g.player.camera.make_current()
		return
	var views := {}
	if net.is_host:
		for slot: NetMatch.Slot in net.slots.values():
			if slot.body_vis:
				slot.body_vis.visible = slot.team == team
			if slot.team == team and slot.alive and slot.id != net.my_id:
				views[slot.id] = slot.node.camera.global_transform
	else:
		for remote: NetMatch.Remote in net.remotes.values():
			remote.vis.visible = remote.team == team
			if remote.team == team and remote.alive:
				views[remote.id] = Transform3D(remote.root.global_basis * Basis(Vector3.RIGHT, remote.pitch),
					remote.pos + Vector3(0, remote.height - 0.15, 0))
	if not views.is_empty():
		var ids := views.keys()
		ids.sort()
		watched_id = ids[_watch % ids.size()]
		var view: Transform3D = views[watched_id]
		var eye := view.origin
		var back := view.basis.z
		back.y = 0.0
		var desired := eye + back.normalized() * 2.1 + view.basis.x * 0.32 + Vector3.UP * 0.26
		var camera_pos := _clear_camera_position(eye, desired)
		_camera.global_transform = view
		if camera_pos.distance_to(eye) > 0.53:
			_camera.global_position = camera_pos
			_camera.look_at(eye - back.normalized() * 2.0 - Vector3.UP * 0.2)
		elif net.is_host:
			var body: Node3D = net.slots[watched_id].body_vis
			if body:
				body.visible = false
		else:
			net.remotes[watched_id].vis.visible = false
	elif rules.phase == RoundRules.Phase.PLANTED and team == rules.attack_team:
		var target := rules.bomb_pos + Vector3.UP * 0.2
		_camera.global_position = _clear_camera_position(target, target + Vector3(0.0, 1.55, 1.05))
		_camera.look_at(target)
	else:
		_camera.global_position = Vector3(0, -100, 0)
	_camera.make_current()


func _clear_camera_position(origin: Vector3, desired: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(origin, desired, 1)
	var hit := net.g.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return desired
	return (hit.position as Vector3).move_toward(origin, 0.12)
