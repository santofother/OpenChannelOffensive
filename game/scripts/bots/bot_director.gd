class_name BotDirector
extends Node
## Host-only. Keeps every team at three players by adding bots to empty slots (when the host's
## "Fill empty team slots with bots" option is on), removes a bot when a person needs the slot, runs each
## bot's brain once per host tick, buys their equipment during prep, auto-readies them in the lobby and
## turns team callouts (comms wheel / ping keys) into bot orders.
##
## Bots are ordinary host slots: they have no network peer, so nothing is ever sent to them, and clients
## see them through the same JOINED events and snapshots as any other player.

const PER_TEAM := 3
const BOT_ID_BASE := 0x7F000000 ## far above the peer ids Godot hands out in practice; checked anyway
const NAMES := ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet"]
const SPOT_COOLDOWN := 540 ## Nine seconds, enough to finish the call and reply.
const REPLY_DELAY := 190

var net: NetMatch
var nav := BotNav.new()
var brains := {} ## bot id -> BotBrain
var _next := 0
var _attack_site := [0, 0] ## per team, chosen each round (comms Go A/B changes it)
var _spot_at := [-10000, -10000]
var _radio_reply := [{}, {}]
var _speech_sample_at := {}
var _claimed := {} ## WallModule -> bot id
var _last_round := -1
var _last_phase := -1
var _buy_req := {}
var _retriever := [0, 0]
var _retriever_tick := -1
var _known_bomb := Vector3.INF
var _searched_sites := {}
var _secure_sites := {}
var _defusing := 0
var _reload_call := {}


func _init() -> void:
	name = "Bots"


func start(owner_match: NetMatch) -> void:
	net = owner_match
	# Bake after the map has finished building its walls this frame.
	await get_tree().physics_frame
	nav.build(net.g, _play_area())
	fill()


func _exit_tree() -> void:
	nav.free_rids()


func is_bot(id: int) -> bool:
	return brains.has(id)


## Everything players can reach: spawns and sites, padded, kept under the roof slabs.
func _play_area() -> AABB:
	if net.g.has_method("bot_nav_area"):
		return net.g.bot_nav_area()
	var box := AABB(net.g.spawn_at(0)[0], Vector3.ZERO)
	for i in 6:
		box = box.expand(net.g.spawn_at(i)[0])
	for zone in range(1, net.g.attack_zone_count()):
		for i in PER_TEAM:
			box = box.expand(net.g.spawn_at(i, zone)[0])
	for site: Vector3 in net.loop.rules.tuning.sites:
		box = box.expand(site)
	box = box.grow(14.0)
	box.position.y = -0.6
	box.size.y = 3.0 # floors to 2.4 m: walls included, roofs (≥2.8 m) left out
	return box


# ------------------------------------------------------------------ roster

func _counts() -> Array:
	var counts := [0, 0]
	for s: NetMatch.Slot in net.slots.values():
		counts[s.team] += 1
	return counts


## Add bots until both teams have three players (no-op when the option is off).
func fill() -> void:
	if not NetworkManager.fill_bots:
		return
	var counts := _counts()
	for team in 2:
		while counts[team] < PER_TEAM:
			_add_bot(team)
			counts[team] += 1


func _add_bot(team: int) -> void:
	var id := BOT_ID_BASE + _next
	while net.slots.has(id):
		_next += 1
		id = BOT_ID_BASE + _next
	var bot_name := "BOT %s" % NAMES[_next % NAMES.size()]
	_next += 1
	var s := net.spawn_bot(id, bot_name, team)
	var index := 0
	for b: int in brains:
		if net.slots.has(b) and (net.slots[b] as NetMatch.Slot).team == team:
			index += 1
	brains[id] = BotBrain.new(id, net, self, 0.55 + 0.1 * float(_next % 3), index)
	s.bot = true
	print("[Bots] + %s (team %d)" % [bot_name, team])


func remove_bot(id: int) -> void:
	if not brains.has(id):
		return
	for m: WallModule in _claimed.keys():
		if _claimed[m] == id:
			_claimed.erase(m)
	brains.erase(id)
	net._on_peer_left(id, false)


## A person is joining: free the slot they will take (the team with fewer players, red on a tie).
func make_room() -> void:
	if brains.is_empty() or net.slots.size() < 2 * PER_TEAM:
		return
	var counts := _counts()
	var team := 0 if counts[0] <= counts[1] else 1
	for t in [team, 1 - team]:
		for id: int in brains.keys():
			if (net.slots[id] as NetMatch.Slot).team == t:
				remove_bot(id)
				return


## Lobby team change for a person when the other team is full: a bot from that team swaps over.
func swap_out(dest_team: int) -> bool:
	for id: int in brains.keys():
		var s: NetMatch.Slot = net.slots[id]
		if s.team == dest_team:
			s.team = 1 - dest_team
			return true
	return false


func refill_soon() -> void:
	fill.call_deferred()


# ------------------------------------------------------------------ per tick

func make_cmd(s: NetMatch.Slot) -> NetCmd:
	var brain: BotBrain = brains[s.id]
	var c := brain.make_cmd(s)
	# Mirror a human teammate's quiet gait: Shift slow-walks, crouching crouches too.
	# Outside a fight only, so bots keep their own combat footwork.
	for mate: NetMatch.Slot in net.slots.values():
		if mate.alive and not mate.bot and mate.team == s.team and (mate.slow_walk or mate.crouching):
			c.slow_walk = true
			if mate.crouching and brain.target_id() == 0:
				c.crouch = true
			break
	if brain.target_id() == 0 and s.lo.is_gun() and not s.lo.reloading and s.lo.reserve > 0 \
			and s.lo.mag < int(s.lo.tuning.mag_size * 0.5):
		c.reload = true
	return c


func host_tick() -> void:
	var loop := net.loop
	if not loop.enabled:
		return
	var rules := loop.rules
	if rules.phase == RoundRules.Phase.LOBBY:
		var changed := false
		for id: int in brains:
			if not rules.ready.get(id, false):
				rules.ready[id] = true
				changed = true
		if changed:
			rules.serial += 1
			loop.sync()
	if net.round_id != _last_round:
		_last_round = net.round_id
		_new_round()
	if rules.phase != _last_phase:
		if rules.phase == RoundRules.Phase.PREP:
			_buy_all()
		_last_phase = rules.phase
	if loop.accepts_combat():
		_radio_tick()
		if net.tick % 12 == 0:
			_objective_comms()


func _new_round() -> void:
	_claimed.clear()
	_known_bomb = Vector3.INF
	_searched_sites.clear()
	_secure_sites.clear()
	_reload_call.clear()
	_defusing = 0
	for team in 2:
		_attack_site[team] = randi() % maxi(net.loop.rules.tuning.sites.size(), 1)
		_spot_at[team] = -10000
		_radio_reply[team] = {}
	_speech_sample_at.clear()
	for b: BotBrain in brains.values():
		b.new_round()


## Simple buy logic: the best gun they can afford, then armor, then (defenders) another kit.
func _buy_all() -> void:
	var loop := net.loop
	for id: int in brains:
		var s: NetMatch.Slot = net.slots[id]
		if not s.alive:
			continue
		var plan: Array[String] = []
		var money := loop.econ.wallet(id)
		if s.lo.primary == "":
			for gun in ["service_rifle", "carbine", "smg"]:
				var price := ShopCatalog.price(loop.econ.tuning, gun)
				if money >= price + (650 if gun != "smg" else 0) or (gun == "smg" and money >= price):
					plan.append(gun)
					money -= price
					break
		if not s.lo.helmet and money >= 1000:
			plan.append("armor_helmet")
			money -= 1000
		elif s.lo.armor < 100 and money >= 650:
			plan.append("vest")
			money -= 650
		if s.team != loop.rules.attack_team and not s.lo.defuse_kit and money >= 400:
			plan.append("defuse_kit")
			money -= 400
		if s.team != loop.rules.attack_team and money >= loop.econ.tuning.price_reinforce + 400:
			plan.append("kit")
		for item in plan:
			_buy_req[id] = int(_buy_req.get(id, 0)) + 1
			loop._buy_host(id, net.round_id, _buy_req[id], item)


# ------------------------------------------------------------------ team knowledge

func attack_site(team: int) -> Vector3:
	var sites := net.loop.rules.tuning.sites
	return sites[clampi(_attack_site[team], 0, sites.size() - 1)]


func defend_site(_team: int, index: int) -> Vector3:
	var sites := net.loop.rules.tuning.sites
	return sites[index % sites.size()]


func defend_point(team: int, index: int) -> Vector3:
	var site := defend_site(team, index)
	var a := index * 2.1 + 0.4
	return nav.snap(site + Vector3(cos(a), 0, sin(a)) * 1.8)


## Nearest living attacker bot to a dropped bomb (cached per tick).
func retriever(team: int) -> int:
	if _retriever_tick != net.tick:
		_retriever_tick = net.tick
		_retriever = [0, 0]
		var best := [INF, INF]
		for id: int in brains:
			var s: NetMatch.Slot = net.slots[id]
			if not s.alive:
				continue
			var d := s.node.global_position.distance_to(net.loop.rules.bomb_pos)
			if d < best[s.team]:
				best[s.team] = d
				_retriever[s.team] = id
	return _retriever[team]


func claim_wall(bot: int, site: Vector3, from: Vector3) -> WallModule:
	var best: WallModule = null
	var best_d := INF
	for m: WallModule in net.g.modules:
		if not m.can_reinforce() or _claimed.has(m):
			continue
		var center := m.global_position
		var ds := Vector2(center.x - site.x, center.z - site.z).length()
		if absf(center.y - site.y) > 2.4:
			continue
		if ds > 6.5:
			continue
		var d := from.distance_to(center) + ds
		if d < best_d:
			best_d = d
			best = m
	if best:
		_claimed[best] = bot
	return best


func release_wall(m: WallModule) -> void:
	_claimed.erase(m)


## Where to stand to reinforce `m`: 0.9 m off its face, on the side facing the site.
func wall_stand_point(m: WallModule, site: Vector3) -> Vector3:
	var axis := m.face_normal()
	var side := signf((site - m.global_position).dot(axis))
	if side == 0.0:
		side = 1.0
	var p := m.global_position + axis * side * (0.9 + 0.5 * minf(m._size.x, m._size.z))
	p.y = m.global_position.y - m._size.y * 0.5 + 0.05
	return nav.snap(p)


# ------------------------------------------------------------------ comms

## A bot spotted someone: tell the team (rate-limited), which also sends other bots to look.
func saw_enemy(bot: int, enemy: NetMatch.Slot) -> void:
	if _radio_contact(bot):
		net.voice.callout(bot, Comms.Kind.ENEMY, enemy.node.global_position + Vector3.UP)


func under_fire(bot: int) -> void:
	if brains.has(bot):
		_radio_contact(bot)


func _radio_room(pos: Vector3) -> String:
	return net.g.radio_room(pos) if net.g.has_method("radio_room") else "office"


func _radio_contact(bot: int) -> bool:
	var team: int = (net.slots[bot] as NetMatch.Slot).team
	if net.tick - _spot_at[team] < SPOT_COOLDOWN:
		return false
	_spot_at[team] = net.tick
	var pos: Vector3 = net.slots[bot].node.global_position
	net.voice.bot_radio(bot, BotRadio.Kind.CONTACT, _radio_room(pos))
	_radio_reply[team] = {"caller": bot, "pos": pos, "tick": net.tick + REPLY_DELAY}
	return true


func _radio_tick() -> void:
	for team in 2:
		var pending: Dictionary = _radio_reply[team]
		if pending.is_empty() or net.tick < int(pending.tick):
			continue
		_radio_reply[team] = {}
		var caller: NetMatch.Slot = net.slots.get(int(pending.caller))
		if caller == null or not caller.alive or caller.team != team:
			continue
		var reply: NetMatch.Slot
		var best := INF
		for id: int in brains:
			var slot: NetMatch.Slot = net.slots[id]
			var brain: BotBrain = brains[id]
			if id == caller.id or not slot.alive or slot.team != team or brain.target_id() != 0 or brain.has_order():
				continue
			if net.loop.rules.carrier == id:
				continue
			var distance := slot.node.global_position.distance_squared_to(pending.pos)
			if distance < best:
				best = distance
				reply = slot
		if reply:
			net.voice.bot_radio(reply.id, BotRadio.Kind.RESPONDING, _radio_room(reply.node.global_position))
			(brains[reply.id] as BotBrain).support(pending.pos)


## Defender bots share physical discoveries over radio. The global plant alert
## only starts their search. It does not provide a destination.
func bomb_location() -> Vector3:
	return _known_bomb


func plant_search(index: int) -> Vector3:
	var sites := net.loop.rules.tuning.sites
	for offset in sites.size():
		var i := (index + offset) % sites.size()
		if not _searched_sites.has(i):
			return sites[i]
	return sites[index % sites.size()]


func _objective_comms() -> void:
	var rules := net.loop.rules
	for id: int in brains:
		var s: NetMatch.Slot = net.slots[id]
		var brain: BotBrain = brains[id]
		if not s.alive or s.team == rules.attack_team:
			continue
		var eye := s.node.camera.global_position
		var pos := s.node.global_position
		if rules.phase == RoundRules.Phase.PLANTED:
			var point := rules.bomb_pos + Vector3.UP * 0.2
			var distance := pos.distance_to(rules.bomb_pos)
			# Close walls muffle the beep. A visible device can be identified further away.
			var clear := brain.clear_line(eye, point)
			# Inside the planted room the beeping gives the device away.
			var same_room := rules.site >= 0 and rules.tuning.site_at(pos) == rules.site
			if _known_bomb == Vector3.INF and (distance <= 4.0 or (distance <= 9.0 and clear) or same_room):
				_known_bomb = rules.bomb_pos
				net.voice.bot_radio(id, BotRadio.Kind.BOMB_HERE, "a" if rules.site == 0 else "b")
				return
			if rules.actor == id and _defusing != id:
				_defusing = id
				net.voice.bot_radio(id, BotRadio.Kind.DEFUSING, "office")
				return
		for i in rules.tuning.sites.size():
			var site := rules.tuning.sites[i]
			if pos.distance_to(site) > 2.8 or not brain.clear_line(eye, site + Vector3.UP * 0.18):
				continue
			var key := "a" if i == 0 else "b"
			if rules.phase == RoundRules.Phase.PLANTED and not _searched_sites.has(i) and rules.site != i:
				_searched_sites[i] = true
				net.voice.bot_radio(id, BotRadio.Kind.NO_BOMB, key)
				return
			if rules.phase == RoundRules.Phase.LIVE and not _secure_sites.has(i) and brain.target_id() == 0:
				_secure_sites[i] = true
				net.voice.bot_radio(id, BotRadio.Kind.SECURED, key)
				return


func reload_comms(s: NetMatch.Slot) -> void:
	if net.tick >= int(_reload_call.get(s.team, 0)) and s.lo.mag == 0:
		_reload_call[s.team] = net.tick + 420
		net.voice.bot_radio(s.id, BotRadio.Kind.RELOADING, "office")


func on_shot(shooter: int, origin: Vector3, silenced := false) -> void:
	_on_noise(shooter, origin, 14.0 if silenced else 56.0, 4.0)


func on_footstep(id: int, pos: Vector3, gait: int, scuff: bool) -> void:
	_on_noise(id, pos, ProcAudio.footstep_range(gait, scuff), 1.4 if gait != ProcAudio.Gait.RUN else 2.4)


func on_speech(id: int, data: PackedByteArray) -> void:
	var source: NetMatch.Slot = net.slots[id]
	if not source.alive or not net.loop.accepts_combat() or net.tick < int(_speech_sample_at.get(id, 0)):
		return
	_speech_sample_at[id] = net.tick + 10
	var pcm: PackedFloat32Array = VoiceAudio.Codec.decode(data)
	var power := 0.0
	for i in range(0, pcm.size(), 4):
		power += pcm[i] * pcm[i]
	var rms := sqrt(power / maxf(1.0, pcm.size() / 4.0))
	if rms > 0.025:
		_on_noise(id, source.node.camera.global_position, VoicePolicy.RANGE * clampf(rms / 0.24, 0.25, 1.0), 2.0)


func _on_noise(id: int, pos: Vector3, radius: float, seconds: float) -> void:
	if not net.loop.accepts_combat() or not net.slots.has(id):
		return
	var source: NetMatch.Slot = net.slots[id]
	for listener: int in brains:
		var slot: NetMatch.Slot = net.slots[listener]
		if not slot.alive or slot.team == source.team:
			continue
		var ear := slot.node.camera.global_position
		var distance := ear.distance_to(pos)
		if distance >= radius:
			continue
		var occluded := GameAudio.blocked(net.g.get_world_3d(), ear, pos)
		if occluded and distance >= radius * 0.5:
			continue
		var brain: BotBrain = brains[listener]
		var cue := pos
		if occluded:
			# Approximate the sound behind cover so it cannot give frame-perfect wall tracking.
			var lateral := (pos - ear).cross(Vector3.UP).normalized()
			cue += lateral * brain.rng.randf_range(-1.0, 1.0) * minf(3.0, distance * 0.15)
		if seconds <= 1.4:
			brain.hear_footstep(cue)
		else:
			brain.hear(cue, seconds)


## A teammate's callout (human or bot). People give orders; bot callouts only alert idle bots.
func on_callout(caller: int, kind: int, pos: Vector3) -> void:
	if not net.slots.has(caller):
		return
	var team: int = (net.slots[caller] as NetMatch.Slot).team
	var from_bot := brains.has(caller)
	var what := Comms.order_of(kind)
	var responders: Array[int] = []
	for id: int in brains:
		var s: NetMatch.Slot = net.slots[id]
		if id == caller or s.team != team or not s.alive:
			continue
		var b: BotBrain = brains[id]
		if from_bot:
			if what == "enemy" and not b.has_order() and s.node.global_position.distance_to(pos) < 30.0:
				b.hear(pos, 8.0)
			continue
		match what:
			"move", "enemy":
				b.set_order({"kind": what, "pos": nav.snap(pos)})
			"follow", "backup":
				b.set_order({"kind": what, "who": caller})
			"hold":
				b.set_order({"kind": "hold", "pos": s.node.global_position})
			"fall_back":
				b.set_order({"kind": "fall_back"})
			"clear":
				b.order.clear()
			_:
				continue
		responders.append(id)
	if from_bot or responders.is_empty():
		return
	if kind in [Comms.Kind.GO_A, Comms.Kind.GO_B]:
		_attack_site[team] = 0 if kind == Comms.Kind.GO_A else 1
	# One bot acknowledges on the team feed.
	var ack := responders[randi() % responders.size()]
	var round_id := net.round_id
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if net.round_id == round_id and net.slots.has(ack) and (net.slots[ack] as NetMatch.Slot).alive:
			net.voice.callout(ack, Comms.Kind.AFFIRM, Vector3.ZERO)
			net.voice.bot_radio(ack, BotRadio.Kind.AFFIRM, "office"))
