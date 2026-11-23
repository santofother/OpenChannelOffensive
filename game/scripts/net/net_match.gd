class_name NetMatch
extends Node
## Host-authoritative match layer for the office graybox (Session 05). Uses only Godot's `multiplayer` API,
## so it runs the same over ENet (local tests) and SteamMultiplayerPeer.
##
## Host: owns every player's simulation. Each physics tick (60 Hz) it consumes buffered NetCmds per player in
## sequence order (duplicates/stale seqs ignored, commands from an old round dropped, a per-player credit budget
## stops clients from running faster than real time), runs the same Player.simulate()/Loadout.apply_cmd() used
## offline, commits hits/deaths/charges/walls and sends 20 Hz snapshots. Shots rewind other players' hit volumes
## to the tick the shooter was viewing (bounded, MAX_REWIND); walls are always tested in their CURRENT host state
## (walls only open during a round and resets bump round_id, so a rewound shot can never pass a wall the shooter
## could not see through; at worst it is stopped by a panel that had already opened on the host).
## Client: predicts its own movement/ammo from its commands, reconciles against snapshots (replays unacked
## commands), interpolates other players INTERP_TICKS behind, and applies reliable events (charges, wall
## revisions, hits, deaths, rounds) guarded by round_id and wall revisions.
## Optional network simulation on receive: --sim-latency=ms (one way) --sim-jitter=ms --sim-loss=0..1.

signal test_msg(sender: int, data: Dictionary)

const TICK_RATE := 60
const DT := 1.0 / TICK_RATE
const SNAP_EVERY := 3 ## 20 Hz snapshots
const INTERP_TICKS := 6 ## remote players render 100 ms behind the newest snapshot
const MAX_REWIND := 12 ## lag compensation bound: 200 ms
const HISTORY := 64
const CMD_REDUNDANCY := 4 ## each command packet repeats the last N commands (loss tolerance)
const CREDIT_CAP := 8.0
const MAX_PENDING := 32
const MAX_PER_TICK := 3
const MAX_HEALTH := 100.0
const CORRECTION_EPS := 0.02
const SPAWNS := [
	[Vector3(0.0, 0.05, -1.0), 0.0], [Vector3(-0.8, 0.05, -1.4), 0.0], [Vector3(0.8, 0.05, -1.4), 0.0],
	[Vector3(6.0, 0.05, -3.3), 90.0], [Vector3(6.0, 0.05, -5.2), 90.0], [Vector3(6.2, 0.05, -6.6), 90.0],
]

enum Msg { CMD, SNAP, PING, PONG, READY, FULL, EVENT, TEST, SHOT, PLAYER_AUDIO }
enum Ev { JOINED, LEFT, CHARGE, DETONATE, WALL, HIT, KILLED, ROUND, REJECT, FACE, LOOP, GADGETS, GADGET_BURST, DOOR, DOOR_IMPACTS, TAKEOVER, INCOMING_SHOT, WEAPON_DROPS, LOOT_EQUIPPED }
enum Interact { DOOR, RADIO, GUN }
var interaction := []
var _last_interact := {}



class Slot:
	var slow_walk := false
	var crouching := false ## human gait mirrored by teammate bots
	var id := 0
	var pname := ""
	var team := 0
	var spawn := 0
	var node: Player
	var lo: Loadout
	var body_vis: Node3D
	var health := MAX_HEALTH
	var alive := true
	var last_ground := Vector3.ZERO
	var tp := 0 ## bumps on every host teleport/respawn so the owner snaps instead of reconciling
	var pending := {} ## seq -> NetCmd
	var last_seq := 0
	var credits := 2.0
	var history: Array = [] ## [tick, pos, height, alive]
	var takeover_tick := -1 ## floor for commands sent while controlling a replacement body
	var bot := false ## host-run bot (BotDirector): no peer, commands come from its BotBrain


class Remote:
	var id := 0
	var pname := ""
	var team := 0
	var root: Node3D
	var vis: Node3D
	var buf: Array = [] ## [tick, pos, yaw, height, alive]
	var health := MAX_HEALTH
	var alive := true
	var pos := Vector3.ZERO
	var height := 1.8
	var lean := 0.0
	var pitch := 0.0
	var velocity := Vector3.ZERO
	var aiming := false
	var reloading := false
	var kick := 0.0


var loop: MatchLoop
var voice: MatchVoice
var weapon_drops: WeaponDrops
var bots: BotDirector ## host only, when empty team slots are filled with bots
var g: Node3D ## graybox
var is_host := false
var my_id := 1
var tick := 0
var round_id := 1
var lag_comp := true
var synced := false ## client: full state received
var slots := {} ## host: id -> Slot
var remotes := {} ## client: id -> Remote
var _departed := {} ## client: ids that left; late unreliable snapshots must not resurrect them
var ready_peers: Array[int] = []
var my_health := MAX_HEALTH
var _down_this_round := false
var _took_over := false
var _local_died := false
var my_alive := true
var my_team := 0
var metrics := {}
var test_godmode := false ## tests: count hits without lowering health

var _seq := 0
var _hist := {} ## client: seq -> {cmd, pos, vel, crouched, height, mag, reserve}
var _my_tp := 0
var _sent: Array[NetCmd] = []
var _last_snap_tick := -1
var _loot_ammo_after_seq := -1
var _server_tick_f := 0.0
var _next_charge := 0
var _resetting := false
var _view_tick := 0
var _shooter := 0
var _sim_latency := 0.0
var _sim_jitter := 0.0
var _sim_loss := 0.0
var _rx_queue: Array = [] ## [deliver_usec, sender, data, reliable]
var _last_reliable_at := {} ## sender -> usec (keeps simulated reliable delivery ordered)
var _rng := RandomNumberGenerator.new()
var _hud: Label
var _center: Label
var _ping_left := 0.0
var _ready_retry := 1.0
var _report_after := 3.0
var _lan_hud := ""
var _last_snapshot_at := -1
var _last_send_error := ""
var _last_error_log := 0
var _spawn_attack_team := 0
var _attack_zone := -1
var _remaining_attack_zones: Array[int] = []
var _test_dropped_full := false
var _bytes_window := {"up": 0, "down": 0, "t": 0.0, "up_rate": 0.0, "down_rate": 0.0}


func _init() -> void:
	name = "NetMatch"


func start(graybox: Node3D) -> void:
	g = graybox
	is_host = multiplayer.is_server()
	my_id = multiplayer.get_unique_id()
	if is_host and NetworkManager.mode == NetworkManager.Mode.ENET:
		_lan_hud = "LAN %s:%d" % [", ".join(NetworkManager.lan_addresses()), NetworkManager.enet_port]
	var a := NetworkManager.args
	_sim_latency = float(a.get("sim-latency", 0.0)) / 1000.0
	_sim_jitter = float(a.get("sim-jitter", 0.0)) / 1000.0
	_sim_loss = float(a.get("sim-loss", 0.0))
	lag_comp = not a.has("no-lag-comp")
	_rng.seed = hash([my_id, Time.get_ticks_usec()])
	_reset_metrics()
	process_physics_priority = -10 ## run before other physics nodes
	process_priority = -1 ## Resolve the local interact target before its HUD prompts draw.
	g.player.net_driven = true
	g.loadout.net_driven = true
	g.loadout.owner_id = my_id
	g.loadout.use_spread = true
	g.loadout.player_volumes = _volumes_for.bind(my_id)
	_build_hud()
	if is_host:
		g.loadout.authority = true
		for m: WallModule in g.modules:
			m.state_changed.connect(_on_wall_changed)
		var s := _add_slot(1, NetworkManager.local_name, g.player, g.loadout)
		_teleport(s)
		NetworkManager.peer_left.connect(_on_peer_left)
	else:
		g.loadout.authority = false
		_send(1, _rel(Msg.READY, {"name": NetworkManager.local_name}), true)
	voice = MatchVoice.new()
	voice.name = "Voice"
	add_child(voice)
	voice.start(self)
	loop = MatchLoop.new()
	add_child(loop)
	loop.start(self)
	weapon_drops = WeaponDrops.new()
	weapon_drops.name = "WeaponDrops"
	weapon_drops.net = self
	add_child(weapon_drops)
	g.gadgets.net = self
	if g.doors:
		g.doors.net = self
	if is_host and NetworkManager.fill_bots and not a.has("net-test"):
		bots = BotDirector.new()
		add_child(bots)
		bots.start(self)
	print("[Match] started host=%s id=%d sim=%.0fms±%.0f loss=%.3f lagcomp=%s" % [is_host, my_id,
		_sim_latency * 1000.0, _sim_jitter * 1000.0, _sim_loss, lag_comp])


func _reset_metrics() -> void:
	metrics = {"sim_us": PackedInt32Array(), "cmds": 0, "dup_cmds": 0, "stale_round_cmds": 0, "starved": 0,
		"budget_drops": 0, "rewind": PackedInt32Array(), "corrections": 0, "corr_err": PackedFloat32Array(),
		"steps_local": 0, "steps_remote": {}, "incoming_shots": 0,
		"rtt_ms": PackedFloat32Array(), "stale_snaps": 0, "stale_events": 0, "snaps": 0, "tx": 0, "rx": 0,
		"enet_tx": 0, "enet_rx": 0, "t0": Time.get_ticks_msec(), "rx_dropped_sim": 0, "hits": 0, "damage": 0.0, "hits_by": {}}


# ================================================================== transport

func _rel(kind: int, payload: Variant) -> PackedByteArray:
	var b := PackedByteArray([kind])
	b.append_array(var_to_bytes(payload))
	return b


func _send(to: int, data: PackedByteArray, reliable: bool) -> void:
	if multiplayer.multiplayer_peer == null or to not in multiplayer.get_peers():
		return # a delayed packet may outlive its peer
	metrics["tx"] += data.size()
	var err: int
	if reliable:
		err = rpc_id(to, "_rr", data)
	else:
		err = rpc_id(to, "_ru", data)
	if err != OK:
		_last_send_error = "to=%d kind=%d: %s" % [to, data[0], error_string(err)]
		if Time.get_ticks_msec() - _last_error_log > 1000:
			_last_error_log = Time.get_ticks_msec()
			print("[Match] SEND FAILED ", _last_send_error)


func _broadcast(data: PackedByteArray, reliable: bool, except: int = -1) -> void:
	for p in ready_peers:
		if p != except:
			_send(p, data, reliable)


@rpc("any_peer", "call_remote", "unreliable", 1)
func _ru(data: PackedByteArray) -> void:
	_on_rx(multiplayer.get_remote_sender_id(), data, false)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rr(data: PackedByteArray) -> void:
	_on_rx(multiplayer.get_remote_sender_id(), data, true)


func _on_rx(sender: int, data: PackedByteArray, reliable: bool) -> void:
	if data.is_empty():
		return
	if not is_host and data[0] == Msg.FULL and NetworkManager.args.has("drop-first-full") and not _test_dropped_full:
		_test_dropped_full = true
		print("[Match] TEST dropped initial full state")
		return
	if not is_host and sender != 1:
		return
	metrics["rx"] += data.size()
	if _sim_latency <= 0.0 and _sim_loss <= 0.0 and _sim_jitter <= 0.0:
		_dispatch(sender, data, reliable)
		return
	var now := Time.get_ticks_usec()
	var delay := _sim_latency + _rng.randf_range(-_sim_jitter, _sim_jitter)
	if _rng.randf() < _sim_loss:
		if not reliable:
			metrics["rx_dropped_sim"] += 1
			return
		delay += 2.0 * _sim_latency + 0.03 ## a lost reliable packet arrives after a retransmit
	var at := now + int(maxf(delay, 0.0) * 1_000_000.0)
	if reliable:
		at = maxi(at, int(_last_reliable_at.get(sender, 0)))
		_last_reliable_at[sender] = at
	_rx_queue.append([at, sender, data, reliable])


func _deliver_due() -> void:
	if _rx_queue.is_empty():
		return
	var now := Time.get_ticks_usec()
	var due: Array = []
	var keep: Array = []
	for e in _rx_queue:
		if int(e[0]) <= now:
			due.append(e)
		else:
			keep.append(e)
	_rx_queue = keep
	due.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
	for e in due:
		_dispatch(int(e[1]), e[2], bool(e[3]))


func _dispatch(sender: int, data: PackedByteArray, reliable: bool) -> void:
	var kind := data[0]
	if reliable:
		var v: Variant = bytes_to_var(data.slice(1))
		match kind:
			Msg.READY:
				if is_host:
					_on_client_ready(sender, v as Dictionary)
			Msg.FULL:
				if not is_host and not synced:
					_apply_full(v as Dictionary, true)
			Msg.EVENT:
				if not is_host:
					_on_event(v as Array)
			Msg.TEST:
				test_msg.emit(sender, v as Dictionary)
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	match kind:
		Msg.CMD:
			if is_host:
				_on_cmds(sender, buf)
		Msg.SNAP:
			if not is_host:
				_on_snapshot(buf)
		Msg.PING:
			if is_host and slots.has(sender):
				data[0] = Msg.PONG
				_send(sender, data, false)
		Msg.PONG:
			if not is_host:
				var sent := buf.get_u64()
				metrics["rtt_ms"].append((Time.get_ticks_usec() - sent) / 1000.0)
		Msg.SHOT:
			if not is_host:
				_on_remote_shot(buf)
		Msg.PLAYER_AUDIO:
			if not is_host:
				_on_remote_player_audio(buf)


func send_test(to: int, d: Dictionary) -> void:
	_send(to, _rel(Msg.TEST, d), true)


# ================================================================== host

func _add_slot(id: int, pname: String, node: Player, lo: Loadout, team: int = -1) -> Slot:
	var s := Slot.new()
	s.id = id
	s.pname = pname
	var counts := [0, 0]
	var used := []
	for o: Slot in slots.values():
		counts[o.team] += 1
		used.append(o.spawn)
	s.team = team if team >= 0 else (0 if counts[0] <= counts[1] else 1)
	for i in 3:
		var idx: int = (0 if s.team == _spawn_attack_team else 3) + i
		if idx not in used:
			s.spawn = idx
			break
	s.node = node
	s.lo = lo
	lo.player_hit.connect(func(victim: int, dmg: float, head: bool) -> void: _on_player_hit(victim, dmg, id, head))
	lo.charge_placed.connect(_on_charge_placed)
	lo.reinforce_gate = func(owner: int) -> String: return loop.reinforce_gate(owner)
	lo.healed.connect(func(amount: float) -> void: _on_healed(id, amount))
	lo.reinforced.connect(func(_m: WallModule) -> void: loop.note_reinforced(id))
	lo.fired.connect(_on_fired.bind(id))
	lo.handling.connect(func(code: int, pos: Vector3) -> void: _on_player_audio(code, pos, ProcAudio.Gait.WALK, id))
	slots[id] = s
	return s


func _spawn_proxy(id: int, pname: String, team: int = -1) -> Slot:
	var p: Player = g.PLAYER_SCENE.instantiate()
	p.name = "Player_%d" % id
	p.scripted = true
	p.input_enabled = false
	p.net_driven = true
	p.get_node("Head/Camera").current = false
	g.add_child(p)
	p.camera.current = false
	g.player.camera.make_current()
	var lo := Loadout.new()
	lo.name = "Loadout_%d" % id
	lo.net_driven = true
	g.add_child(lo)
	lo.setup(p, g, g.WEAPON_TUNING.duplicate(), false)
	lo.owner_id = id
	lo.use_spread = true
	lo.use_recoil = not NetworkManager.args.has("net-test")
	lo.effects = g.loadout.effects
	lo.player_volumes = _volumes_for.bind(id)
	var s := _add_slot(id, pname, p, lo, team)
	s.body_vis = StandIn.build(_operator_color(s.team))
	p.add_child(s.body_vis)
	return s


func spawn_for(s: Slot) -> Array:
	return g.spawn_at(s.spawn, maxi(0, _attack_zone))


func _teleport(s: Slot) -> void:
	var sp := spawn_for(s)
	s.node.reset()
	s.node.teleport(sp[0], sp[1])
	s.last_ground = sp[0]
	s.tp = (s.tp + 1) % 256
	s.history.clear()


## Host-side move of a player (tests now; spawn/objective moves later). The owner snaps to the position via the
## teleport counter in snapshots and takes the facing from a reliable FACE event (commands carry absolute yaw,
## so without it the owner's next command would turn the player back).
func test_teleport(id: int, pos: Vector3, yaw_deg: float) -> void:
	var s: Slot = slots[id]
	s.node.teleport(pos, yaw_deg)
	s.last_ground = pos
	s.node.velocity = Vector3.ZERO
	s.tp = (s.tp + 1) % 256
	s.history.clear()
	if id != 1:
		_send(id, _rel(Msg.EVENT, [Ev.FACE, round_id, deg_to_rad(yaw_deg)]), true)


## Host: a bot player (BotDirector). Same proxy body/loadout as a remote player, but no peer: it never
## joins ready_peers, so nothing is sent to it. Joining mid-round it waits for the next round like anyone.
func spawn_bot(id: int, pname: String, team: int) -> Slot:
	var s := _spawn_proxy(id, pname, team)
	s.bot = true
	_teleport(s)
	if loop.enabled and loop.rules.phase != RoundRules.Phase.LOBBY:
		s.alive = false
		s.health = 0.0
	_broadcast(_rel(Msg.EVENT, [Ev.JOINED, id, pname, s.team]), true)
	voice.sync_state()
	loop.sync()
	return s


func _on_client_ready(id: int, d: Dictionary) -> void:
	if not NetworkManager.player_names.has(id):
		return
	if slots.has(id):
		# READY is retried until a client has applied its first full state. Never create a second player.
		_send(id, _rel(Msg.FULL, _full_state(id)), true)
		voice.sync_state()
		return
	if bots:
		bots.make_room() # a person takes a bot's place
	var pname := String(NetworkManager.player_names[id])
	var s := _spawn_proxy(id, pname)
	_teleport(s)
	if loop.enabled and loop.rules.phase != RoundRules.Phase.LOBBY:
		s.alive = false
		s.health = 0.0
	ready_peers.append(id)
	_broadcast(_rel(Msg.EVENT, [Ev.JOINED, id, pname, s.team]), true, id)
	_send(id, _rel(Msg.FULL, _full_state(id)), true)
	voice.sync_state()
	print("[Match] READY %d '%s' team %d (%d players)" % [id, pname, s.team, slots.size()])


func _on_peer_left(id: int, refill: bool = true) -> void:
	if not slots.has(id):
		return
	var s: Slot = slots[id]
	_last_interact.erase(id)
	loop.departed(id, s.last_ground if s.node.global_position.y < -4.0 else s.node.global_position)
	voice.departed(id)
	slots.erase(id)
	_rx_queue = _rx_queue.filter(func(packet: Array) -> bool: return int(packet[1]) != id)
	_last_reliable_at.erase(id)
	ready_peers.erase(id)
	s.lo.queue_free()
	s.node.queue_free()
	_broadcast(_rel(Msg.EVENT, [Ev.LEFT, id]), true)
	voice.sync_state()
	print("[Match] LEFT %d (%d players)" % [id, slots.size()])
	if bots and refill and not s.bot:
		bots.refill_soon() # a bot takes the empty slot


func _full_state(for_id: int) -> Dictionary:
	var pl: Array = []
	for s: Slot in slots.values():
		if not can_observe(for_id, s.id):
			continue
		pl.append({"id": s.id, "name": s.pname, "team": s.team, "pos": s.node.global_position,
			"yaw": s.node.rotation.y, "pitch": s.node.pitch(), "lean": s.node.lean,
			"height": s.node.height, "crouched": s.node.crouched, "spray": [s.lo.spray_shots, s.lo.spray_idle], "health": s.health, "alive": s.alive, "tp": s.tp, "mag": s.lo.mag,
			"reserve": s.lo.reserve, "ch": [s.lo.charges[Loadout.Tool.ORDINARY_CHARGE], s.lo.charges[Loadout.Tool.HEAVY_CHARGE], s.lo.charges[Loadout.Tool.REINFORCE], s.lo.charges[Loadout.Tool.MEDKIT]],
			"gear": [Weapons.index_of(s.lo.primary), Weapons.index_of(s.lo.secondary), s.lo.armor, s.lo.helmet],
			"tool": s.lo.tool, "gun_ammo": s.lo._gun_ammo.duplicate(true), "gun_tool": s.lo._gun_tool})
	var walls: Array = []
	for m: WallModule in g.modules:
		walls.append([m.wall_id, m.state, m.revision, m.material, m.openings.duplicate(), m.detached.duplicate()])
	var ch: Array = []
	for c: Charge in get_tree().get_nodes_in_group("charges"):
		if is_instance_valid(c) and c.left > 0.0:
			ch.append([c.charge_id, c.owner_id, c.module.wall_id, c.kind, c.global_position, c.normal, c.left,
				tick + int(roundf(c.left * TICK_RATE))])
	return {"round": round_id, "tick": tick, "you": for_id, "players": pl, "walls": walls, "charges": ch, "gadgets": g.gadgets.state(for_id), "loop": loop.state(for_id) if loop else {},
		"doors": g.doors.state() if g.doors else [], "weapon_drops": weapon_drops.drops}


func _on_cmds(sender: int, buf: StreamPeerBuffer) -> void:
	if not slots.has(sender):
		return
	var s: Slot = slots[sender]
	var n := buf.get_u8()
	if n > CMD_REDUNDANCY or buf.get_available_bytes() < n * NetCmd.SIZE:
		return
	for i in n:
		var c := NetCmd.decode(buf)
		if c.seq <= s.last_seq or s.pending.has(c.seq):
			metrics["dup_cmds"] += 1
			continue
		s.pending[c.seq] = c
	if s.pending.size() > MAX_PENDING:
		var keys := s.pending.keys()
		keys.sort()
		for k in keys.slice(0, s.pending.size() - MAX_PENDING):
			s.pending.erase(k)
			metrics["budget_drops"] += 1


func _host_tick() -> void:
	tick += 1
	# Host's own player: input is local, processed immediately.
	var me: Slot = slots[1]
	var c: NetCmd = g.player.make_cmd()
	g.loadout.fill_cmd(c)
	loop.fill_cmd(c)
	_seq += 1
	c.seq = _seq
	c.round_id = round_id & 0xFFFF
	c.view_tick = tick
	_process_cmd(me, c.quantised())
	if bots:
		bots.host_tick()
		for s: Slot in slots.values():
			if s.bot and bots.is_bot(s.id):
				var bc := bots.make_cmd(s)
				bc.seq = s.last_seq + 1
				bc.round_id = round_id & 0xFFFF
				bc.view_tick = tick # bots see the present: no lag-compensation rewind
				_process_cmd(s, bc.quantised())
	for s: Slot in slots.values():
		if s.id == 1 or s.bot:
			continue
		# Budget: one command per tick plus a small drift allowance, capped (no speed-up by flooding).
		s.credits = minf(s.credits + 1.0 + 1.0 / 60.0, CREDIT_CAP)
		var done := 0
		if s.pending.is_empty():
			metrics["starved"] += 1
		while not s.pending.is_empty() and s.credits >= 1.0 and done < MAX_PER_TICK:
			var keys := s.pending.keys()
			keys.sort()
			var k: int = keys[0]
			var cmd: NetCmd = s.pending[k]
			s.pending.erase(k)
			s.credits -= 1.0
			done += 1
			_process_cmd(s, cmd)
	if loop.enabled:
		for s: Slot in slots.values():
			if s.alive and s.node.is_on_floor():
				s.last_ground = s.node.global_position
			if s.alive and s.node.global_position.y < -4.0:
				_on_player_hit(s.id, MAX_HEALTH, s.id)
	weapon_drops.host_tick()
	loop.host_tick()
	g.gadgets.host_tick(DT)
	if g.doors and bots:
		g.doors.host_bots(bots.brains.keys())
	if tick % 6 == 0:
		for peer: int in ready_peers:
			_send(peer, _rel(Msg.EVENT, [Ev.GADGETS, round_id, tick, g.gadgets.state(peer)]), true)
	for s: Slot in slots.values():
		s.history.append([tick, s.node.global_position, s.node.height, s.alive, s.node.lean_offset()])
		if s.history.size() > HISTORY:
			s.history.pop_front()
		if s.body_vis:
			StandIn.animate(s.body_vis, DT, s.node.basis.inverse()*s.node.velocity, s.node.height,
					s.node.pitch(), s.node.lean, s.lo.aiming, s.lo.reloading, _kick(s.lo.spray_shots, s.lo.spray_idle), s.alive)
	if tick % SNAP_EVERY == 0:
		for peer: int in ready_peers:
			_send(peer, _snapshot(peer), false)


func _process_cmd(s: Slot, c: NetCmd) -> void:
	s.last_seq = c.seq
	metrics["cmds"] += 1
	if c.round_id != (round_id & 0xFFFF) or c.view_tick < s.takeover_tick:
		metrics["stale_round_cmds"] += 1
		return
	loop.command(s, c)
	loop.constrain(c, s.alive, s.team)
	if not s.alive:
		c.move = Vector2.ZERO
		c.fire = false
		c.reload = false
		c.crouch = false
		c.slow_walk = false
		c.lean = 0
		c.vault = false
	s.slow_walk = c.slow_walk and not c.crouch
	s.crouching = c.crouch
	_shooter = s.id
	_view_tick = c.view_tick
	_move_with_audio(s.node, c, s.id, s.alive)
	s.lo.apply_cmd(c, DT)
	_shooter = 0


func _move_with_audio(player: Player, command: NetCmd, id: int, alive: bool) -> void:
	var before := player.global_position
	var grounded := player.is_on_floor()
	player.simulate(command, DT)
	if not alive:
		player.reset_steps()
		return
	var cue := player.movement_cue(before, grounded, g, command)
	if cue.is_empty():
		return
	if id == my_id:
		metrics.steps_local += 1
		ProcAudio.player_cue(g, int(cue[0]), int(cue[2]))
	if is_host:
		_on_player_audio(int(cue[0]), cue[1], int(cue[2]), id)


func _on_player_audio(code: int, pos: Vector3, gait: int, id: int) -> void:
	var source: Slot = slots.get(id)
	if source == null or not source.alive:
		return
	if id != my_id and can_observe(my_id, id):
		ProcAudio.player_cue(source.node, code, gait, pos)
	if bots and code < ProcAudio.HANDLING_OFFSET:
		bots.on_footstep(id, pos, gait, code % 6 >= 4)
	var packet := StreamPeerBuffer.new()
	packet.put_u8(Msg.PLAYER_AUDIO)
	packet.put_u16(round_id & 0xFFFF)
	packet.put_u32(id)
	packet.put_u8(code | (gait << 5))
	for value in [pos.x, pos.y, pos.z]:
		packet.put_float(value)
	for peer: int in ready_peers:
		if peer != id and can_observe(peer, id):
			_send(peer, packet.data_array, false)


func _on_remote_player_audio(packet: StreamPeerBuffer) -> void:
	if not synced or packet.get_u16() != (round_id & 0xFFFF):
		return
	var id := packet.get_u32()
	var remote: Remote = remotes.get(id)
	if remote == null or not remote.alive or not (my_alive or remote.team == my_team or not loop.enabled):
		return
	var cue := packet.get_u8()
	var code := cue & 31
	var gait := cue >> 5
	if code >= ProcAudio.HANDLING_OFFSET + ProcAudio.HANDLING.size() or gait > ProcAudio.Gait.RUN:
		return
	var pos := Vector3(packet.get_float(), packet.get_float(), packet.get_float())
	if code < ProcAudio.HANDLING_OFFSET:
		metrics.steps_remote[id] = int(metrics.steps_remote.get(id, 0)) + 1
	ProcAudio.player_cue(remote.root, code, gait, pos)


## Hit volumes of everyone but `shooter`, rewound to the tick the shooter was viewing (host), or the current
## interpolated view (client prediction, cosmetic only).
func _volumes_for(shooter: int) -> Array:
	var out: Array = []
	if not is_host:
		for r: Remote in remotes.values():
			if r.alive:
				out.append({"id": r.id, "a": r.pos + Vector3(0, 0.1, 0), "b": r.pos + Vector3(0, r.height - 0.05, 0) + r.root.global_basis.x * r.lean * g.player.tuning.lean_distance})
		return out
	var rt := tick
	if lag_comp and shooter != 1 and _shooter == shooter:
		rt = clampi(_view_tick, tick - MAX_REWIND, tick)
	if shooter != 1:
		metrics["rewind"].append(tick - rt)
	for s: Slot in slots.values():
		if s.id == shooter or not s.alive:
			continue
		var pos := s.node.global_position
		var h := s.node.height
		var offset := s.node.lean_offset()
		var was_alive := true
		if rt < tick:
			for e: Array in s.history:
				if int(e[0]) == rt:
					pos = e[1]
					h = e[2]
					was_alive = e[3]
					offset = e[4]
					break
		if was_alive:
			out.append({"id": s.id, "a": pos + Vector3(0, 0.1, 0), "b": pos + Vector3(0, h - 0.05, 0) + offset})
	return out


## Armor absorbs part of body hits only; a helmet reduces headshots only.
const ARMOR_ABSORB := 0.35
const HELMET_HEAD := 0.75

func _on_player_hit(victim_id: int, damage: float, shooter_id: int, head := false) -> void:
	if not slots.has(victim_id):
		return
	var v: Slot = slots[victim_id]
	if damage <= 0.0 or not v.alive or not loop.accepts_combat():
		return
	loop.damaged[victim_id] = true
	metrics["hits"] += 1
	metrics["damage"] += damage
	metrics["hits_by"][victim_id] = int(metrics["hits_by"].get(victim_id, 0)) + 1
	v.lo.cancel_use()
	var dealt := damage
	if head:
		if v.lo.helmet:
			dealt *= HELMET_HEAD
	elif v.lo.armor > 0:
		var absorbed := minf(float(v.lo.armor), damage * ARMOR_ABSORB)
		v.lo.armor = maxi(0, v.lo.armor - int(ceilf(absorbed)))
		dealt -= absorbed
	var before := v.health
	if not test_godmode:
		v.health = maxf(v.health - dealt, 0.0)
	var killed := v.health <= 0.0
	var enemy := slots.has(shooter_id) and (slots[shooter_id] as Slot).team != v.team
	if bots and enemy and v.bot and not killed and before > v.health:
		bots.under_fire(victim_id)
	if enemy and before > v.health:
		loop.performance.enemy_hit(shooter_id, victim_id, before - v.health, killed)
		var tun := loop.econ.tuning
		var pay := int(round((before - v.health) * tun.damage_reward_per_hp))
		loop.reward(shooter_id, pay + (tun.kill_reward if killed else 0), "kill" if killed else "")
	if killed:
		loop.performance.death(victim_id, shooter_id if enemy else 0)
		v.alive = false
		v.lo.reloading = false
		GameAudio.stop_owner(v.node)
		loop.rules.drop(victim_id, v.last_ground if v.node.global_position.y < -4.0 else v.node.global_position)
		weapon_drops.drop_player(v, v.last_ground if v.node.global_position.y < -4.0 else v.node.global_position)
		voice.died(victim_id)
		if v.body_vis:
			v.body_vis.rotation.x = -PI * 0.5
		_broadcast(_rel(Msg.EVENT, [Ev.KILLED, round_id, victim_id, shooter_id]), true)
		if victim_id == 1:
			_set_center("You are down. Wait for the next round.")
	if shooter_id == 1:
		g.loadout.show_hit(killed, head)
	else:
		_send(shooter_id, _rel(Msg.EVENT, [Ev.HIT, round_id, victim_id, killed, head]), true)


func _on_fired(res: Dictionary, shooter_id: int) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(Msg.SHOT)
	b.put_u16(round_id & 0xFFFF)
	b.put_u32(shooter_id)
	var o: Vector3 = res.get("origin", Vector3.ZERO)
	var e: Vector3 = res["position"]
	var n: Vector3 = res["normal"]
	var world_hit: bool = res.hit and int(res.player_id) < 0
	var door_hit := Loadout._door_impact_id(res.collider)
	var marks: Array = []
	var surfaces: Array = res.get("impacts", []).duplicate()
	if world_hit:
		surfaces.append(res)
	for surface: Dictionary in surfaces:
		var door := Loadout._door_impact_id(surface.collider)
		if door >= 0:
			var leaf: Node3D = surface.collider
			marks.append([door, leaf.to_local(surface.position), leaf.global_basis.inverse() * (surface.normal as Vector3)])
	if not marks.is_empty():
		if can_observe(my_id, shooter_id):
			_show_door_impacts(marks)
		for peer: int in ready_peers:
			if can_observe(peer, shooter_id):
				_send(peer, _rel(Msg.EVENT, [Ev.DOOR_IMPACTS, round_id, marks]), true)
	for v in [o, e, n]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	var silenced := bool(res.get("silenced", false))
	var victim := int(res.player_id) if loop.accepts_combat() else -1
	if victim == my_id:
		_incoming_shot(o, int(res.weapon), silenced)
	elif victim in ready_peers:
		_send(victim, _rel(Msg.EVENT, [Ev.INCOMING_SHOT, round_id, o, res.weapon, silenced]), true)
	b.put_u8(int(world_hit and door_hit < 0) | int(silenced) << 1)
	b.put_u8(int(res.weapon))
	for peer: int in ready_peers:
		if peer != shooter_id and peer != victim and can_observe(peer, shooter_id):
			_send(peer, b.data_array, false)
	if bots:
		bots.on_shot(shooter_id, o, silenced)
	if shooter_id != 1:
		if my_id != victim and can_observe(my_id, shooter_id):
			ProcAudio.shot((slots[shooter_id] as Slot).node, int(res.weapon), silenced, o)
		if world_hit and door_hit < 0 and can_observe(my_id, shooter_id):
			g.loadout._add_mark(e, n, res["collider"])


func _incoming_shot(origin: Vector3, weapon: int, silenced: bool) -> void:
	# Keep this cue independent of the enemy model, which can disappear as soon as spectating starts.
	metrics.incoming_shots += 1
	ProcAudio.shot(g, weapon, silenced, origin)
	ProcAudio.play(g, "incoming_impact")


## Wall-clock stamp for timing logs (comparable between processes on one machine).
static func _t() -> String:
	return "%.3f" % fmod(Time.get_unix_time_from_system(), 1000.0)


func _on_charge_placed(c: Charge) -> void:
	_next_charge += 1
	c.charge_id = _next_charge
	print("[Timing] t=%s host CHARGE placed id=%d owner=%d fuse=%.2f tick=%d" % [_t(), c.charge_id, c.owner_id, c.left, tick])
	c.detonated.connect(_on_charge_detonated)
	_broadcast(_rel(Msg.EVENT, [Ev.CHARGE, round_id, c.charge_id, c.owner_id, c.module.wall_id, c.kind,
		c.global_position, c.normal, c.left, tick + int(roundf(c.left * TICK_RATE))]), true)
	if c.owner_id != 1:
		ProcAudio.play(g, "beep", c.global_position)


func _on_charge_detonated(c: Charge) -> void:
	print("[Timing] t=%s host DETONATE id=%d tick=%d" % [_t(), c.charge_id, tick])
	_broadcast(_rel(Msg.EVENT, [Ev.DETONATE, round_id, c.charge_id]), true)


func _on_wall_changed(m: WallModule) -> void:
	if _resetting:
		return
	_broadcast(_rel(Msg.EVENT, [Ev.WALL, round_id, m.wall_id, m.state, m.revision, m.material, m.openings.duplicate(), m.break_contact, m.detached.duplicate()]), true)


## Host only: new round id, every wall intact, charges/marks/effects cleared, everyone respawned.
func restart_round() -> void:
	if not is_host:
		return
	_resetting = true
	GameAudio.clear()
	round_id += 1
	weapon_drops.clear()
	g.clear_wall_debris()
	_last_interact.clear()
	interaction.clear()
	g.gadgets.clear()
	if g.doors:
		g.doors.reset()
	for m: WallModule in g.modules:
		m.reset()
	for s: Slot in slots.values():
		s.lo.reset()
		loop.apply_baseline(s)
		s.health = MAX_HEALTH
		s.slow_walk = false
		s.crouching = false
		s.alive = true
		s.node.velocity = Vector3.ZERO
		s.pending.clear()
		s.takeover_tick = -1
		if s.body_vis:
			s.body_vis.rotation.x = 0.0
			s.body_vis.visible = true
		_teleport(s)
	_resetting = false
	voice.reset_round()
	g.player.camera.make_current()
	_set_center("")
	for p in ready_peers:
		_send(p, _rel(Msg.EVENT, [Ev.ROUND, round_id, _full_state(p)]), true)
	print("[Match] ROUND %d" % round_id)


func swap_sides() -> void:
	if not is_host:
		return
	for s: Slot in slots.values():
		s.team = 1 - s.team
		s.spawn = (s.spawn + 3) % 6
		if s.body_vis:
			s.body_vis.free()
			s.body_vis = StandIn.build(_operator_color(s.team))
			s.node.add_child(s.body_vis)
	restart_round()


func _snapshot(for_id: int = 1) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(Msg.SNAP)
	b.put_u32(tick)
	b.put_u16(round_id & 0xFFFF)
	var visible: Array = []
	for s: Slot in slots.values():
		if can_observe(for_id, s.id):
			visible.append(s)
	b.put_u8(visible.size())
	for s: Slot in visible:
		var p := s.node
		b.put_u32(s.id)
		b.put_u8(s.tp)
		b.put_u8(int(s.alive) | int(p.crouched) << 1 | int(s.lo.reloading) << 2 | int(s.lo.aiming) << 3)
		for v in [p.global_position, p.velocity]:
			b.put_float(v.x)
			b.put_float(v.y)
			b.put_float(v.z)
		b.put_float(p.rotation.y)
		b.put_float(p.pitch())
		b.put_float(p.height)
		b.put_float(p.lean)
		b.put_u16(s.lo.spray_shots)
		b.put_float(s.lo.spray_idle)
		b.put_u8(int(ceilf(s.health)))
		b.put_u32(s.last_seq)
		b.put_u8(s.lo.mag)
		b.put_u16(s.lo.reserve)
		b.put_u8(s.lo._gun_tool)
		b.put_u8(s.lo.charges[Loadout.Tool.ORDINARY_CHARGE])
		b.put_u8(s.lo.charges[Loadout.Tool.HEAVY_CHARGE])
		b.put_u8(s.lo.charges[Loadout.Tool.REINFORCE])
		b.put_u8(s.lo.charges[Loadout.Tool.MEDKIT])
		b.put_u8(Weapons.index_of(s.lo.primary))
		b.put_u8(Weapons.index_of(s.lo.secondary))
		b.put_u8(s.lo.armor)
		b.put_u8(int(s.lo.helmet))
	return b.data_array


# ================================================================== client

func _client_tick() -> void:
	if not synced:
		return
	tick += 1
	var c: NetCmd = g.player.make_cmd()
	g.loadout.fill_cmd(c)
	loop.fill_cmd(c)
	_seq += 1
	c.seq = _seq
	c.round_id = round_id & 0xFFFF
	c.view_tick = maxi(int(_server_tick_f) - INTERP_TICKS, 0)
	loop.constrain(c, my_alive, my_team)
	if not my_alive:
		c.move = Vector2.ZERO
		c.fire = false
		c.reload = false
		c.crouch = false
		c.slow_walk = false
		c.lean = 0
	c = c.quantised()
	_move_with_audio(g.player, c, my_id, my_alive)
	g.loadout.apply_cmd(c, DT)
	_hist[_seq] = _hist_entry(c)
	_sent.append(c)
	if _sent.size() > CMD_REDUNDANCY:
		_sent.pop_front()
	var b := StreamPeerBuffer.new()
	b.put_u8(Msg.CMD)
	b.put_u8(_sent.size())
	for sc in _sent:
		sc.encode(b)
	_send(1, b.data_array, false)
	_ping_left -= DT
	if _ping_left <= 0.0:
		_ping_left = 0.5
		var pb := StreamPeerBuffer.new()
		pb.put_u8(Msg.PING)
		pb.put_u64(Time.get_ticks_usec())
		_send(1, pb.data_array, false)


func _hist_entry(c: NetCmd) -> Dictionary:
	var p: Player = g.player
	return {"cmd": c, "pos": p.global_position, "vel": p.velocity, "crouched": p.crouched, "height": p.height,
		"mag": g.loadout.mag, "reserve": g.loadout.reserve, "gun_slot": g.loadout._gun_tool, "lean": p.lean,
		"spray_shots": g.loadout.spray_shots, "spray_idle": g.loadout.spray_idle,
		"shot": g.loadout.last_fire_seq == c.seq}


## Test hooks: replay already-processed sequence numbers carrying fire/move (the host must ignore them), and
## commands stamped with an old round id (consumed without effect).
func send_forged_cmds(old_seq: bool, old_round: bool) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(Msg.CMD)
	b.put_u8(CMD_REDUNDANCY)
	for i in CMD_REDUNDANCY:
		var c := NetCmd.new()
		if old_seq:
			c.seq = maxi(_seq - 40 + i, 1)
		else:
			_seq += 1
			c.seq = _seq
		c.round_id = (round_id - 1 if old_round else round_id) & 0xFFFF
		c.yaw = g.player.rotation.y
		c.pitch = g.player.pitch()
		c.fire = true
		c.move = Vector2(1, 0)
		c.encode(b)
	for i in 3: # unreliable: repeat so simulated loss can't hide the test
		_send(1, b.data_array, false)


func _on_snapshot(buf: StreamPeerBuffer) -> void:
	if not synced:
		return
	var t := buf.get_u32()
	var r := buf.get_u16()
	if t <= _last_snap_tick:
		metrics["stale_snaps"] += 1
		return
	if r != (round_id & 0xFFFF):
		metrics["stale_snaps"] += 1
		return
	_last_snap_tick = t
	metrics["snaps"] += 1
	_last_snapshot_at = Time.get_ticks_msec()
	if int(metrics["snaps"]) == 1:
		print("[Match] FIRST SNAP tick=%d round=%d" % [t, r])
	if absf(t - _server_tick_f) > 15.0:
		_server_tick_f = t
	else:
		_server_tick_f += (t - _server_tick_f) * 0.1
	var n := buf.get_u8()
	for i in n:
		var id := buf.get_u32()
		var tp := buf.get_u8()
		var flags := buf.get_u8()
		var pos := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		var vel := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		var yaw := buf.get_float()
		var _pitch := buf.get_float()
		var h := buf.get_float()
		var lean := buf.get_float()
		var spray_shots := buf.get_u16()
		var spray_idle := buf.get_float()
		var hp := buf.get_u8()
		var ack := buf.get_u32()
		var mag := buf.get_u8()
		var reserve := buf.get_u16()
		var gun_slot := buf.get_u8()
		var ch_o := buf.get_u8()
		var ch_h := buf.get_u8()
		var ch_k := buf.get_u8()
		var ch_m := buf.get_u8()
		var gp := buf.get_u8()
		var gs := buf.get_u8()
		var garmor := buf.get_u8()
		var ghelmet := buf.get_u8() != 0
		var alive := flags & 1 != 0
		if id == my_id:
			_set_alive(alive)
			my_health = hp
			g.loadout.charges[Loadout.Tool.ORDINARY_CHARGE] = ch_o
			g.loadout.charges[Loadout.Tool.HEAVY_CHARGE] = ch_h
			g.loadout.charges[Loadout.Tool.REINFORCE] = ch_k
			g.loadout.charges[Loadout.Tool.MEDKIT] = ch_m
			_apply_gear(gp, gs, garmor, ghelmet)
			_reconcile(tp, ack, pos, vel, flags & 2 != 0, h, mag, reserve, lean, spray_shots, spray_idle, gun_slot)
		elif not _departed.has(id):
			if loop.enabled and not my_alive and (not remotes.has(id) or (remotes[id] as Remote).team != my_team):
				continue
			var rm := _remote(id)
			rm.health = hp
			rm.pitch = _pitch
			rm.velocity = vel
			rm.aiming = flags & 8 != 0
			rm.reloading = flags & 4 != 0
			rm.kick = _kick(spray_shots, spray_idle)
			if rm.alive != alive:
				rm.alive = alive
				rm.vis.rotation.x = 0.0 if alive else -PI * 0.5
			rm.buf.append([t, pos, yaw, h, alive, lean])
			if rm.buf.size() > 30:
				rm.buf.pop_front()


## Client: adopt the host's weapons/armor. New guns arrive with the host's full ammo; same guns are left alone.
func _apply_gear(gp: int, gs: int, armor: int, helmet: bool) -> void:
	var lo: Loadout = g.loadout
	var np := Weapons.id_at(gp)
	var ns := Weapons.id_at(gs)
	if np != lo.primary or ns != lo.secondary:
		lo.set_gear(np, ns)
	lo.armor = armor
	lo.helmet = helmet


func _on_healed(id: int, amount: float) -> void:
	if slots.has(id) and (slots[id] as Slot).alive:
		var v: Slot = slots[id]
		v.health = minf(v.health + amount, MAX_HEALTH)


func _reconcile(tp: int, ack: int, pos: Vector3, vel: Vector3, crouched: bool, h: float, mag: int, reserve: int, lean: float, spray_shots: int, spray_idle: float, gun_slot: int) -> void:
	var p: Player = g.player
	var replay := false
	if tp != _my_tp:
		_my_tp = tp
		p.reset_steps()
		replay = true
	else:
		var e: Dictionary = _hist.get(ack, {})
		if e.is_empty():
			return
		var err: float = (e["pos"] as Vector3).distance_to(pos)
		if err > CORRECTION_EPS or bool(e["crouched"]) != crouched or absf(float(e["lean"]) - lean) > 0.015:
			replay = true
			metrics["corrections"] += 1
			metrics["corr_err"].append(err)
		# Samples predicted with the previous gun cannot reconcile the newly equipped magazine.
		if ack > _loot_ammo_after_seq and int(e["gun_slot"]) == gun_slot and g.loadout._gun_tool == gun_slot:
			var dm := mag - int(e["mag"])
			var dr := reserve - int(e["reserve"])
			if dm != 0 or dr != 0:
				g.loadout.mag = clampi(g.loadout.mag + dm, 0, g.loadout.tuning.mag_size)
				g.loadout.reserve = maxi(g.loadout.reserve + dr, 0)
				for k in _hist.keys():
					if k > ack and int(_hist[k]["gun_slot"]) == gun_slot:
						_hist[k]["mag"] = int(_hist[k]["mag"]) + dm
						_hist[k]["reserve"] = int(_hist[k]["reserve"]) + dr
	for k in _hist.keys():
		if k <= ack:
			_hist.erase(k)
	# Rebuild only spray bookkeeping from acknowledged host state and unacknowledged shot edges.
	# Absolute command look already includes the owner's recoil and mouse compensation; never kick twice.
	var lo: Loadout = g.loadout
	lo.spray_shots = spray_shots
	lo.spray_idle = spray_idle
	var pending_keys := _hist.keys()
	pending_keys.sort()
	for k in pending_keys:
		lo.spray_idle = minf(lo.spray_idle + DT, 10.0)
		if lo.spray_idle >= lo.tuning.recoil_reset_time:
			lo.spray_shots = 0
		if bool(_hist[k]["shot"]):
			lo.spray_shots += 1
			lo.spray_idle = 0.0
		_hist[k]["spray_shots"] = lo.spray_shots
		_hist[k]["spray_idle"] = lo.spray_idle
	if not replay:
		return
	var yaw: float = p.rotation.y
	var pitch: float = p.pitch()
	p.set_move_state(pos, vel, crouched, h, lean)
	var keys := _hist.keys()
	keys.sort()
	for k in keys:
		var c: NetCmd = _hist[k]["cmd"]
		p.simulate(c, DT)
		_hist[k]["pos"] = p.global_position
		_hist[k]["vel"] = p.velocity
		_hist[k]["crouched"] = p.crouched
		_hist[k]["height"] = p.height
		_hist[k]["lean"] = p.lean
	p.set_look(rad_to_deg(yaw), rad_to_deg(pitch))


func _remote(id: int, pname: String = "", team: int = -1) -> Remote:
	if remotes.has(id):
		var r0: Remote = remotes[id]
		if team >= 0 and team != r0.team:
			r0.team = team
			_rebuild_remote_vis(r0)
		if pname != "":
			r0.pname = pname
		return r0
	var r := Remote.new()
	r.id = id
	r.pname = pname if pname != "" else "Player%d" % id
	r.team = maxi(team, 0)
	r.root = Node3D.new()
	r.root.name = "Remote_%d" % id
	g.add_child(r.root)
	_rebuild_remote_vis(r)
	remotes[id] = r
	return r


func _operator_color(team: int) -> Color:
	var offense := loop.rules.attack_team if loop and loop.enabled else _spawn_attack_team
	return StandIn.TEAM_RED if team == offense else StandIn.TEAM_BLUE


func refresh_remote_colors() -> void:
	for r: Remote in remotes.values():
		if r.vis.get_meta("team", Color.WHITE) != _operator_color(r.team):
			_rebuild_remote_vis(r)


func _rebuild_remote_vis(r: Remote) -> void:
	if r.vis:
		r.vis.free()
	r.vis = StandIn.build(_operator_color(r.team))
	r.root.add_child(r.vis)
	r.vis.rotation.x = 0.0 if r.alive else -PI * 0.5


func _drop_remote(id: int) -> void:
	if remotes.has(id):
		(remotes[id] as Remote).root.queue_free()
		remotes.erase(id)


func _set_alive(alive: bool) -> void:
	if alive and _down_this_round:
		return # unreliable snapshots from before a reliable death cannot resurrect this player
	if not alive:
		_down_this_round = true
	if alive == my_alive:
		return
	my_alive = alive
	if not alive:
		g.loadout.reloading = false
	_set_center("" if alive or loop.enabled else "You are down. Wait for the host to restart the round.")
	if loop.enabled and not alive:
		for id: int in remotes.keys():
			if (remotes[id] as Remote).team != my_team:
				_drop_remote(id)


func _apply_takeover_remote(row: Dictionary) -> void:
	if not remotes.has(int(row.id)):
		return
	var remote: Remote = remotes[int(row.id)]
	remote.buf.clear()
	remote.alive = row.alive
	remote.vis.rotation.x = 0.0 if remote.alive else -PI * 0.5
	remote.pos = row.pos
	remote.root.global_position = remote.pos


func _apply_full(d: Dictionary, first: bool, takeover := false) -> void:
	GameAudio.clear()
	_down_this_round = false
	round_id = int(d["round"])
	if not takeover:
		_took_over = false
		_local_died = false
	if first:
		_server_tick_f = float(d["tick"])
		tick = int(d["tick"])
	_last_snap_tick = int(d.tick) if takeover else -1
	_loot_ammo_after_seq = -1
	_hist.clear()
	_sent.clear()
	var seen := {}
	for pd: Dictionary in d["players"]:
		var id := int(pd["id"])
		seen[id] = true
		_departed.erase(id) # a full host roster can restore a returning stable transport ID
		if id == my_id:
			_my_tp = int(pd["tp"])
			my_team = int(pd["team"])
			g.player.reset()
			g.player.teleport(pd["pos"], rad_to_deg(float(pd["yaw"])))
			g.player.set_look(rad_to_deg(float(pd.yaw)), rad_to_deg(float(pd.pitch)))
			g.player.crouched = bool(pd.crouched)
			g.player.height = float(pd.height)
			g.player._apply_height()
			g.player.lean = float(pd.get("lean", 0.0))
			g.player._apply_lean()
			g.loadout.spray_shots = int(pd["spray"][0])
			g.loadout.spray_idle = float(pd["spray"][1])
			my_health = float(pd["health"])
			_set_alive(bool(pd["alive"]))
			g.loadout.mag = int(pd["mag"])
			g.loadout.reserve = int(pd["reserve"])
			g.loadout.charges[Loadout.Tool.ORDINARY_CHARGE] = int(pd["ch"][0])
			g.loadout.charges[Loadout.Tool.HEAVY_CHARGE] = int(pd["ch"][1])
			g.loadout.charges[Loadout.Tool.REINFORCE] = int(pd["ch"][2])
			g.loadout.charges[Loadout.Tool.MEDKIT] = int(pd["ch"][3])
			_apply_gear(int(pd["gear"][0]), int(pd["gear"][1]), int(pd["gear"][2]), bool(pd["gear"][3]))
			if takeover:
				g.loadout._gun_ammo = pd.gun_ammo
				g.loadout._gun_tool = int(pd.gun_tool)
				g.loadout.tool = int(pd.tool)
				g.loadout.want_tool = int(pd.tool)
				Weapons.apply(g.loadout.tuning, g.loadout.primary if g.loadout._gun_tool == Loadout.Tool.RIFLE else g.loadout.secondary)
			g.loadout.mag = int(pd["mag"])
			g.loadout.reserve = int(pd["reserve"])
		else:
			var r := _remote(id, String(pd["name"]), int(pd["team"]))
			r.height = float(pd.height)
			r.pitch = float(pd.get("pitch", 0.0))
			r.lean = float(pd.get("lean", 0.0))
			r.health = float(pd["health"])
			r.alive = bool(pd["alive"])
			r.vis.rotation.x = 0.0 if r.alive else -PI * 0.5
			r.buf.clear()
			r.pos = pd["pos"]
			r.root.global_position = r.pos
			r.root.rotation.y = float(pd["yaw"])
	for id in remotes.keys():
		if not seen.has(id):
			_drop_remote(id)
	if not takeover:
		_apply_full_world(d)
	if loop.enabled and d.has("loop"):
		loop.receive(d.loop, true)
	if d.has("gadgets"):
		g.gadgets.receive(d.gadgets, int(d.tick))
	weapon_drops.receive(d.get("weapon_drops", {}))
	synced = true
	print("[Match] FULL applied: you=%d host=1 remotes=%s tick=%d" % [my_id, remotes.keys(), tick])


func _apply_full_world(d: Dictionary) -> void:
	g.clear_wall_debris()
	for w: Array in d["walls"]:
		var m: WallModule = g._mod(String(w[0]))
		if m == null:
			continue
		if int(w[1]) == WallModule.State.INTACT and int(w[2]) == 0:
			m.reset()
		else:
			m.apply_remote(int(w[1]), int(w[2]), int(w[3]), w[4], w[5])
	for c: Charge in get_tree().get_nodes_in_group("charges"):
		if c.module and c.module.charge == c:
			c.module.charge = null
		c.free()
	for cd: Array in d["charges"]:
		_spawn_remote_charge(cd[0], cd[1], cd[2], cd[3], cd[4], cd[5], cd[6], cd[7])
	if g.doors and d.has("doors"):
		g.doors.apply_all(d.doors)


## Client copy of a host charge. It counts down to the host's detonation tick (not from message arrival), so a
## late message or a frame stall can't make its countdown run behind the real breach.
func _spawn_remote_charge(cid: int, owner: int, wall_id: String, kind: int, pos: Vector3, n: Vector3, left: float,
		end_tick: int) -> void:
	var m: WallModule = g._mod(wall_id)
	if m == null:
		return
	var c := Charge.new()
	c.charge_id = cid
	c.owner_id = owner
	c.authoritative = false
	c.clock = func() -> float: return (end_tick - _server_tick_f) / TICK_RATE
	g.add_child(c)
	c.setup(m, kind, minf(left, maxf((end_tick - _server_tick_f) / TICK_RATE, 0.0)), pos, n)
	m.charge = c


func _find_charge(cid: int) -> Charge:
	for c: Charge in get_tree().get_nodes_in_group("charges"):
		if c.charge_id == cid:
			return c
	return null


func _on_event(ev: Array) -> void:
	var kind := int(ev[0])
	match kind:
		Ev.JOINED:
			_departed.erase(int(ev[1]))
			if loop.enabled and not my_alive and int(ev[3]) != my_team:
				return
			_remote(int(ev[1]), String(ev[2]), int(ev[3]))
			return
		Ev.LEFT:
			_departed[int(ev[1])] = true
			_drop_remote(int(ev[1]))
			return
		Ev.ROUND:
			if int(ev[1]) <= round_id:
				metrics["stale_events"] += 1
				return
			for m: WallModule in g.modules:
				m.reset()
			for c: Node in get_tree().get_nodes_in_group("charges"):
				c.free()
			g.loadout.reset()
			g.gadgets.clear()
			if g.doors:
				g.doors.reset()
			_apply_full(ev[2] as Dictionary, false)
			_set_center("")
			return
	# Everything below belongs to one round.
	if int(ev[1]) != round_id:
		metrics["stale_events"] += 1
		return
	match kind:
		Ev.GADGET_BURST:
			g.gadgets.show_burst(ev[2], ev[3])
		Ev.TAKEOVER:
			var at := int(ev[2])
			_last_snap_tick = maxi(_last_snap_tick, at)
			if ev.size() > 5:
				_took_over = true
				g.loadout.cancel_use()
				_apply_full(ev[5], false, true)
			else:
				_apply_takeover_remote(ev[3])
				_apply_takeover_remote(ev[4])
		Ev.DOOR_IMPACTS:
			_show_door_impacts(ev[2])
		Ev.DOOR:
			if g.doors:
				g.doors.apply(ev[2] as Array, true)
		Ev.GADGETS:
			g.gadgets.receive(ev[3], int(ev[2]))
		Ev.WEAPON_DROPS:
			weapon_drops.receive(ev[2])
		Ev.LOOT_EQUIPPED:
			if my_alive:
				_last_snap_tick = maxi(_last_snap_tick, int(ev[2]) - 1)
				_loot_ammo_after_seq = _seq
				g.loadout.equip_looted_gun(ev[3], ev[4])
		Ev.LOOP:
			loop.receive(ev[2])
		Ev.CHARGE:
			print("[Timing] t=%s client CHARGE recv id=%d left=%.2f by host clock=%.2f" % [_t(), int(ev[2]), float(ev[8]),
				(int(ev[9]) - _server_tick_f) / TICK_RATE])
			if _find_charge(int(ev[2])) == null:
				_spawn_remote_charge(ev[2], ev[3], ev[4], ev[5], ev[6], ev[7], ev[8], ev[9])
				if int(ev[3]) == my_id:
					g.loadout.say("Charge armed: %.0f s. Move away!" % float(ev[8]))
		Ev.DETONATE:
			print("[Timing] t=%s client DETONATE recv id=%d" % [_t(), int(ev[2])])
			var c := _find_charge(int(ev[2]))
			if c:
				if g.loadout.effects:
					g.loadout.effects.burst(c.global_position, c.normal, c.kind == WallModule.Kind.HEAVY)
				if c.module and c.module.charge == c:
					c.module.charge = null
				c.queue_free()
		Ev.WALL:
			print("[Timing] t=%s client WALL recv %s rev=%d" % [_t(), String(ev[2]), int(ev[4])])
			var m: WallModule = g._mod(String(ev[2]))
			if m == null or ev.size() < 9 or not m.apply_remote(int(ev[3]), int(ev[4]), int(ev[5]), ev[6], ev[8], true):
				metrics["stale_events"] += 1
			elif m.bullet_breakable and m.state == WallModule.State.BREACHED:
				ProcAudio.play(m, "cover_break", ev[7] if ev.size() > 7 else m.global_position)
		Ev.HIT:
			g.loadout.show_hit(bool(ev[3]), bool(ev[4]))
		Ev.INCOMING_SHOT:
			_incoming_shot(ev[2], int(ev[3]), bool(ev[4]))
		Ev.KILLED:
			if int(ev[2]) == my_id:
				_local_died = true
				_set_alive(false)
			elif remotes.has(int(ev[2])):
				var r: Remote = remotes[int(ev[2])]
				r.alive = false
				GameAudio.stop_owner(r.root)
				r.vis.rotation.x = -PI * 0.5
		Ev.REJECT:
			g.loadout.say(String(ev[2]))
		Ev.FACE:
			g.player.set_look(rad_to_deg(float(ev[2])), 0.0)


func _show_door_impacts(marks: Array) -> void:
	if not g.doors:
		return
	for mark: Array in marks:
		var leaf: Node3D = g.doors.doors[int(mark[0])].body
		var normal := (leaf.global_basis * (mark[2] as Vector3)).normalized()
		g.loadout._add_mark(leaf.to_global(mark[1]), normal, leaf)


## Test hook: feed an event as if it came from the host (stale/duplicate handling).
func inject_event(ev: Array) -> void:
	_on_event(ev)


func _on_remote_shot(buf: StreamPeerBuffer) -> void:
	if not synced or buf.get_u16() != (round_id & 0xFFFF):
		return
	var shooter := buf.get_u32()
	var remote: Remote = remotes.get(shooter)
	if remote == null or not (my_alive or remote.team == my_team or not loop.enabled):
		return
	var o := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	var e := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	var n := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	var flags := buf.get_u8()
	ProcAudio.shot(remote.root, buf.get_u8(), flags & 2 != 0, o)
	if flags & 1:
		g.loadout._add_mark(e, n, null)


func _kick(shots: int, idle: float) -> float:
	return maxf(0, 1.0-idle/.14) if shots > 0 else 0.0


func _interpolate(delta: float) -> void:
	var rt := _server_tick_f - INTERP_TICKS
	for r: Remote in remotes.values():
		if r.buf.is_empty():
			continue
		var a: Array = r.buf[0]
		var b: Array = r.buf[r.buf.size() - 1]
		if rt <= float(a[0]):
			b = a
		else:
			for i in range(r.buf.size() - 1):
				if float(r.buf[i][0]) <= rt and float(r.buf[i + 1][0]) >= rt:
					a = r.buf[i]
					b = r.buf[i + 1]
					break
		var span := float(b[0]) - float(a[0])
		var k := 0.0 if span <= 0.0 else clampf((rt - float(a[0])) / span, 0.0, 1.0)
		r.pos = (a[1] as Vector3).lerp(b[1], k)
		r.height = lerpf(a[3], b[3], k)
		r.lean = lerpf(a[5], b[5], k)
		r.root.global_position = r.pos
		r.root.rotation.y = lerp_angle(float(a[2]), float(b[2]), k)
		StandIn.animate(r.vis, delta, r.root.basis.inverse()*r.velocity, r.height, r.pitch, r.lean,
				r.aiming, r.reloading, r.kick, r.alive)


# ================================================================== frame

func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and g.player.input_enabled \
			and event.is_action_pressed("interact") and not event.is_echo():
		request_interaction()


func request_interaction() -> void:
	if not local_alive() or not (is_host or synced):
		return
	var target := interaction_target(my_id, g.player, local_team())
	if target.is_empty():
		return # Objective holds already travel with the movement commands.
	if is_host:
		_interact_host(my_id, round_id, target[0], target[1])
	else:
		_use.rpc_id(1, round_id, target[0], target[1])


@rpc("any_peer", "call_remote", "reliable", 0)
func _use(r: int, kind: int, target: int) -> void:
	if is_host:
		_interact_host(multiplayer.get_remote_sender_id(), r, kind, target)


func _interact_host(id: int, r: int, kind: int, target: int) -> void:
	var s: Slot = slots.get(id)
	if not is_host or r != round_id or s == null or not s.alive or tick - int(_last_interact.get(id, -60)) < 8:
		return
	if interaction_target(id, s.node, s.team) != [kind, target]:
		return
	_last_interact[id] = tick
	match kind:
		Interact.DOOR: g.doors._host_act(id, r, DoorSystem.Act.USE)
		Interact.RADIO: voice.take_radio(id, target, s.team)
		Interact.GUN: weapon_drops.take(s, target)


func interaction_target(id: int, player: Player, team: int) -> Array:
	if loop.objective_available(id):
		return []
	var target := []
	var eye := player.camera.global_position
	var direction := -player.camera.global_basis.z
	var best_dot := -1.0
	var door_allowed := not loop.enabled or loop.rules.phase in [
		RoundRules.Phase.LOBBY, RoundRules.Phase.LIVE, RoundRules.Phase.PLANTED] \
		or (loop.rules.phase == RoundRules.Phase.PREP and team != loop.rules.attack_team)
	if g.doors and door_allowed:
		var door: DoorSystem.Door = g.doors.use_target(player)
		if door:
			target = [Interact.DOOR, door.id]
			best_dot = direction.dot(eye.direction_to(door.center(clampf(eye.y - door.hinge.y, .3, 1.8))))
	if loop.accepts_combat():
		var gun := weapon_drops.target(player)
		if gun != 0:
			var alignment := direction.dot(eye.direction_to(weapon_drops.drops[gun].pos))
			if alignment > best_dot:
				target = [Interact.GUN, gun]
				best_dot = alignment
		var radio := voice.target_radio(player, team, voice.stolen.has(id))
		if radio != 0 and direction.dot(eye.direction_to(voice.pickups[radio].pos)) > best_dot:
			target = [Interact.RADIO, radio]
	return target


func tell_player(id: int, message: String) -> void:
	if id == my_id:
		g.loadout.say(message)
	elif id in ready_peers:
		_send(id, _rel(Msg.EVENT, [Ev.REJECT, round_id, message]), true)


func _physics_process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_deliver_due()
	if is_host:
		_host_tick()
		metrics["sim_us"].append(Time.get_ticks_usec() - t0)
	else:
		_client_tick()


func _process(delta: float) -> void:
	if not is_host and _report_after > 0.0:
		_report_after -= delta
		if _report_after <= 0.0:
			print("[Connection report] ", connection_report())
	if not is_host and not synced:
		_ready_retry -= delta
		if _ready_retry <= 0.0:
			_ready_retry = 1.0
			_send(1, _rel(Msg.READY, {"name": NetworkManager.local_name}), true)
	if delta > 0.1:
		print("[Timing] t=%s %s frame stall %.0f ms" % [_t(), "host" if is_host else "client", delta * 1000.0])
	if not is_host and synced:
		_server_tick_f += delta * TICK_RATE
		_interpolate(delta)
	_pop_enet_stats()
	_bytes_window["t"] += delta
	if _bytes_window["t"] >= 1.0:
		_bytes_window["up_rate"] = (metrics["tx"] - _bytes_window["up"]) / _bytes_window["t"]
		_bytes_window["down_rate"] = (metrics["rx"] - _bytes_window["down"]) / _bytes_window["t"]
		_bytes_window["up"] = metrics["tx"]
		_bytes_window["down"] = metrics["rx"]
		_bytes_window["t"] = 0.0
	_update_hud()
	interaction = interaction_target(my_id, g.player, local_team()) if local_alive() and g.player.input_enabled \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else []


func _pop_enet_stats() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and (peer as ENetMultiplayerPeer).host:
		var h := (peer as ENetMultiplayerPeer).host
		metrics["enet_tx"] += h.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
		metrics["enet_rx"] += h.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)


# ================================================================== HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NetHud"
	add_child(layer)
	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud.position = Vector2(-430, 8)
	_hud.custom_minimum_size.x = 420
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_hud)
	_center = Label.new()
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.position = Vector2(-300, 40)
	_center.custom_minimum_size.x = 600
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_theme_font_size_override("font_size", 24)
	_center.add_theme_color_override("font_shadow_color", Color.BLACK)
	_center.modulate = Color(1.0, 0.4, 0.3)
	layer.add_child(_center)


func _set_center(t: String) -> void:
	if _center:
		_center.text = t


func _update_hud() -> void:
	if _hud == null:
		return
	var lines: Array[String] = []
	var rtt: PackedFloat32Array = metrics["rtt_ms"]
	lines.append("Round %d   %s" % [loop.rules.round_number if loop.enabled else round_id, "HOST" if is_host else "RTT %.0f ms" % (rtt[rtt.size() - 1] if rtt.size() > 0 else 0.0)])
	lines.append("net up %.1f KB/s  down %.1f KB/s%s" % [_bytes_window["up_rate"] / 1024.0, _bytes_window["down_rate"] / 1024.0,
		"  corrections %d" % metrics["corrections"] if not is_host else ""])
	if not is_host:
		if not synced:
			lines.append("Waiting for host's match state...")
		elif _last_snapshot_at < 0 or Time.get_ticks_msec() - _last_snapshot_at > 2000:
			lines.append("Host updates missing — Esc: Copy connection report")
		else:
			lines.append("Receiving host updates | %d other player(s)" % remotes.size())
	elif NetworkManager.mode == NetworkManager.Mode.ENET:
		lines.append(_lan_hud)
	if is_host:
		for s: Slot in slots.values():
			lines.append("%s %s  %d hp%s" % ["[R]" if s.team == 0 else "[B]", s.pname, int(s.health), "" if s.alive else "  DOWN"])
	else:
		lines.append("[%s] you  %d hp" % ["R" if _my_team() == 0 else "B", int(my_health)])
		for r: Remote in remotes.values():
			lines.append("%s %s  %d hp%s" % ["[R]" if r.team == 0 else "[B]", r.pname, int(r.health), "" if r.alive else "  DOWN"])
	_hud.text = "\n".join(lines)


func _my_team() -> int:
	return local_team()


func local_team() -> int:
	return (slots[1] as Slot).team if is_host and slots.has(1) else my_team


func local_health() -> int:
	var hp := (slots[1] as Slot).health if is_host and slots.has(1) else my_health
	return int(ceilf(hp))


func local_alive() -> bool:
	return (slots[1] as Slot).alive if is_host and slots.has(1) else my_alive


## A human who died this round can use one living allied bot for the rest of the round.
func local_can_take_over() -> bool:
	if is_host:
		return loop.performance.died_this_round.has(my_id) and slots[my_id].takeover_tick < 0
	return _local_died and not _took_over


func take_over_bot(id: int, bot_id: int) -> bool:
	var human: Slot = slots.get(id)
	var bot: Slot = slots.get(bot_id)
	if not is_host or not loop.accepts_combat() or human == null or bot == null:
		return false
	if human.bot or human.alive or human.takeover_tick >= 0 or not loop.performance.died_this_round.has(id):
		return false
	if not bot.bot or not bot.alive or bot.team != human.team:
		return false
	var old_pos := human.node.global_position
	var pawn := bot.node
	human.node.teleport(pawn.global_position, rad_to_deg(pawn.rotation.y))
	human.node.set_look(rad_to_deg(pawn.rotation.y), rad_to_deg(pawn.pitch()))
	human.node.crouched = pawn.crouched
	human.node.height = pawn.height
	human.node._apply_height()
	human.node.velocity = pawn.velocity
	human.last_ground = bot.last_ground
	human.tp = (human.tp + 1) % 256
	human.pending.clear()
	human.history.clear()
	human.lo.adopt_equipment(bot.lo)
	human.health = bot.health
	human.alive = true
	human.takeover_tick = tick
	if human.body_vis:
		human.body_vis.rotation.x = 0.0
	bot.node.teleport(old_pos, rad_to_deg(bot.node.rotation.y))
	bot.history.clear()
	bot.lo.cancel_use()
	bot.alive = false
	bot.health = 0.0
	if bot.body_vis:
		bot.body_vis.rotation.x = -PI * 0.5
	loop.inputs.erase(id)
	loop.inputs.erase(bot_id)
	loop.damaged.erase(id)
	loop.damaged.erase(bot_id)
	loop.performance.contributors.erase(id)
	if loop.performance.contributors.has(bot_id):
		loop.performance.contributors[id] = loop.performance.contributors[bot_id]
		loop.performance.contributors.erase(bot_id)
	if loop.rules.carrier == bot_id:
		loop.rules.carrier = id
	if loop.rules.actor == bot_id:
		loop.rules.interrupt()
	voice.sync_state()
	loop.sync()
	var rider := {"id": id, "pos": human.node.global_position, "alive": true}
	var replaced := {"id": bot_id, "pos": old_pos, "alive": false}
	for peer: int in ready_peers:
		if not can_observe(peer, id):
			continue
		var payload := [Ev.TAKEOVER, round_id, tick, rider, replaced]
		if peer == id:
			payload.append(_full_state(id))
		_send(peer, _rel(Msg.EVENT, payload), true)
	if id == my_id:
		_set_center("")
	return true


func can_observe(viewer: int, target: int) -> bool:
	if not loop or not loop.enabled or not slots.has(viewer) or not slots.has(target):
		return true
	return slots[viewer].alive or slots[viewer].team == slots[target].team


## Draw once per new playable round. Exhaust the shuffled zones before repeating one.
func rotate_attack_zone() -> void:
	if _remaining_attack_zones.is_empty():
		_remaining_attack_zones.assign(range(g.attack_zone_count()))
		_remaining_attack_zones.shuffle()
		if _remaining_attack_zones.size() > 1 and _remaining_attack_zones.back() == _attack_zone:
			_remaining_attack_zones.push_front(_remaining_attack_zones.pop_back())
	_attack_zone = _remaining_attack_zones.pop_back()


func assign_spawns(attack_team: int) -> void:
	_spawn_attack_team = attack_team
	var counts := [0, 0]
	var ids := slots.keys()
	ids.sort()
	for id: int in ids:
		var s: Slot = slots[id]
		s.spawn = (0 if s.team == attack_team else 3) + counts[s.team]
		counts[s.team] += 1
		if s.body_vis:
			s.body_vis.free()
			s.body_vis = StandIn.build(_operator_color(s.team))
			s.node.add_child(s.body_vis)


# ================================================================== state digest (tests)

func digest() -> Dictionary:
	var hp := {}
	var ammo := {}
	if is_host:
		for s: Slot in slots.values():
			hp[s.id] = [int(ceilf(s.health)), s.alive]
			ammo[s.id] = [s.lo.mag, s.lo.reserve, s.lo.charges[Loadout.Tool.ORDINARY_CHARGE], s.lo.charges[Loadout.Tool.HEAVY_CHARGE], s.lo.charges[Loadout.Tool.REINFORCE], s.lo.charges[Loadout.Tool.MEDKIT], s.lo.primary, s.lo.secondary, s.lo.armor]
	else:
		hp[my_id] = [int(ceilf(my_health)), my_alive]
		ammo[my_id] = [g.loadout.mag, g.loadout.reserve, g.loadout.charges[Loadout.Tool.ORDINARY_CHARGE], g.loadout.charges[Loadout.Tool.HEAVY_CHARGE], g.loadout.charges[Loadout.Tool.REINFORCE], g.loadout.charges[Loadout.Tool.MEDKIT], g.loadout.primary, g.loadout.secondary, g.loadout.armor]
		for r: Remote in remotes.values():
			hp[r.id] = [int(ceilf(r.health)), r.alive]
	var walls := {}
	for m: WallModule in g.modules:
		walls[m.wall_id] = [m.state, m.revision, m.shape_count(), g._parts_match(m), m.material, m.openings.duplicate(), m.detached.duplicate()]
	var ch := 0
	for c: Charge in get_tree().get_nodes_in_group("charges"):
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			ch += 1
	return {"round": round_id, "hp": hp, "ammo": ammo, "walls": walls, "charges": ch}


func remote_view() -> Dictionary:
	var out := {}
	for r: Remote in remotes.values():
		var meshes := 0
		for node in r.vis.find_children("*", "MeshInstance3D", true, false):
			if node is MeshInstance3D and node.is_visible_in_tree():
				meshes += 1
		out[r.id] = {"pos": r.pos, "render_pos": r.root.global_position, "height": r.height,
			"scale": r.vis.global_basis.get_scale(), "visible_meshes": meshes,
			"alive": r.alive, "team": r.team, "buffered_snapshots": r.buf.size()}
	return out

func connection_report() -> String:
	var active_camera := g.get_viewport().get_camera_3d()
	return JSON.stringify({"build": NetworkManager.build_id, "os": OS.get_name(), "transport": NetworkManager.mode_name(),
		"host": is_host, "you": my_id, "round": round_id, "full_state_received": synced,
		"snapshot_count": metrics.get("snaps", 0), "snapshot_age_ms": Time.get_ticks_msec() - _last_snapshot_at if _last_snapshot_at >= 0 else -1,
		"roster": NetworkManager.player_names, "local_position": g.player.global_position,
		"remote_view": remote_view(), "last_send_error": _last_send_error,
		"active_camera": str(active_camera.get_path()) if active_camera else "none",
		"camera_position": active_camera.global_position if active_camera else Vector3.ZERO,
		"camera_forward": -active_camera.global_basis.z if active_camera else Vector3.ZERO,
		"ready_peers": ready_peers, "lan_addresses": NetworkManager.lan_addresses(), "port": NetworkManager.enet_port,
		"steam_channels": ProjectSettings.get_setting("steam/multiplayer_peer/max_channels", 0)}, "  ")
