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

enum Msg { CMD, SNAP, PING, PONG, READY, FULL, EVENT, TEST, SHOT }
enum Ev { JOINED, LEFT, CHARGE, DETONATE, WALL, HIT, KILLED, ROUND, REJECT, FACE }


class Slot:
	var id := 0
	var pname := ""
	var team := 0
	var spawn := 0
	var node: Player
	var lo: Loadout
	var body_vis: Node3D
	var health := MAX_HEALTH
	var alive := true
	var tp := 0 ## bumps on every host teleport/respawn so the owner snaps instead of reconciling
	var pending := {} ## seq -> NetCmd
	var last_seq := 0
	var credits := 2.0
	var history: Array = [] ## [tick, pos, height, alive]


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
var my_alive := true
var my_team := 0
var metrics := {}
var test_godmode := false ## tests: count hits without lowering health

var _seq := 0
var _hist := {} ## client: seq -> {cmd, pos, vel, crouched, height, mag, reserve}
var _my_tp := 0
var _sent: Array[NetCmd] = []
var _last_snap_tick := -1
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
var _bytes_window := {"up": 0, "down": 0, "t": 0.0, "up_rate": 0.0, "down_rate": 0.0}


func _init() -> void:
	name = "NetMatch"


func start(graybox: Node3D) -> void:
	g = graybox
	is_host = multiplayer.is_server()
	my_id = multiplayer.get_unique_id()
	var a := NetworkManager.args
	_sim_latency = float(a.get("sim-latency", 0.0)) / 1000.0
	_sim_jitter = float(a.get("sim-jitter", 0.0)) / 1000.0
	_sim_loss = float(a.get("sim-loss", 0.0))
	lag_comp = not a.has("no-lag-comp")
	_rng.seed = hash([my_id, Time.get_ticks_usec()])
	_reset_metrics()
	process_physics_priority = -10 ## run before other physics nodes
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
	print("[Match] started host=%s id=%d sim=%.0fms±%.0f loss=%.3f lagcomp=%s" % [is_host, my_id,
		_sim_latency * 1000.0, _sim_jitter * 1000.0, _sim_loss, lag_comp])


func _reset_metrics() -> void:
	metrics = {"sim_us": PackedInt32Array(), "cmds": 0, "dup_cmds": 0, "stale_round_cmds": 0, "starved": 0,
		"budget_drops": 0, "rewind": PackedInt32Array(), "corrections": 0, "corr_err": PackedFloat32Array(),
		"rtt_ms": PackedFloat32Array(), "stale_snaps": 0, "stale_events": 0, "snaps": 0, "tx": 0, "rx": 0,
		"enet_tx": 0, "enet_rx": 0, "t0": Time.get_ticks_msec(), "rx_dropped_sim": 0, "hits": 0, "damage": 0.0, "hits_by": {}}


# ================================================================== transport

func _rel(kind: int, payload: Variant) -> PackedByteArray:
	var b := PackedByteArray([kind])
	b.append_array(var_to_bytes(payload))
	return b


func _send(to: int, data: PackedByteArray, reliable: bool) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	metrics["tx"] += data.size()
	if reliable:
		_rr.rpc_id(to, data)
	else:
		_ru.rpc_id(to, data)


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
				if not is_host:
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
			if is_host:
				data[0] = Msg.PONG
				_send(sender, data, false)
		Msg.PONG:
			if not is_host:
				var sent := buf.get_u64()
				metrics["rtt_ms"].append((Time.get_ticks_usec() - sent) / 1000.0)
		Msg.SHOT:
			if not is_host:
				_on_remote_shot(buf)


func send_test(to: int, d: Dictionary) -> void:
	_send(to, _rel(Msg.TEST, d), true)


# ================================================================== host

func _add_slot(id: int, pname: String, node: Player, lo: Loadout) -> Slot:
	var s := Slot.new()
	s.id = id
	s.pname = pname
	var counts := [0, 0]
	var used := []
	for o: Slot in slots.values():
		counts[o.team] += 1
		used.append(o.spawn)
	s.team = 0 if counts[0] <= counts[1] else 1
	for i in 3:
		var idx: int = s.team * 3 + i
		if idx not in used:
			s.spawn = idx
			break
	s.node = node
	s.lo = lo
	lo.player_hit.connect(_on_player_hit.bind(id))
	lo.charge_placed.connect(_on_charge_placed)
	lo.fired.connect(_on_fired.bind(id))
	slots[id] = s
	return s


func _spawn_proxy(id: int, pname: String) -> Slot:
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
	lo.effects = g.loadout.effects
	lo.player_volumes = _volumes_for.bind(id)
	var s := _add_slot(id, pname, p, lo)
	s.body_vis = StandIn.build(StandIn.TEAM_RED if s.team == 0 else StandIn.TEAM_BLUE)
	p.add_child(s.body_vis)
	return s


func _teleport(s: Slot) -> void:
	var sp: Array = SPAWNS[s.spawn]
	s.node.reset()
	s.node.teleport(sp[0], sp[1])
	s.tp = (s.tp + 1) % 256
	s.history.clear()


## Host-side move of a player (tests now; spawn/objective moves later). The owner snaps to the position via the
## teleport counter in snapshots and takes the facing from a reliable FACE event (commands carry absolute yaw,
## so without it the owner's next command would turn the player back).
func test_teleport(id: int, pos: Vector3, yaw_deg: float) -> void:
	var s: Slot = slots[id]
	s.node.teleport(pos, yaw_deg)
	s.node.velocity = Vector3.ZERO
	s.tp = (s.tp + 1) % 256
	s.history.clear()
	if id != 1:
		_send(id, _rel(Msg.EVENT, [Ev.FACE, round_id, deg_to_rad(yaw_deg)]), true)


func _on_client_ready(id: int, d: Dictionary) -> void:
	if not NetworkManager.player_names.has(id) or slots.has(id):
		return
	var pname := String(NetworkManager.player_names[id])
	var s := _spawn_proxy(id, pname)
	_teleport(s)
	ready_peers.append(id)
	_broadcast(_rel(Msg.EVENT, [Ev.JOINED, id, pname, s.team]), true, id)
	_send(id, _rel(Msg.FULL, _full_state(id)), true)
	print("[Match] READY %d '%s' team %d (%d players)" % [id, pname, s.team, slots.size()])


func _on_peer_left(id: int) -> void:
	if not slots.has(id):
		return
	var s: Slot = slots[id]
	slots.erase(id)
	ready_peers.erase(id)
	s.lo.queue_free()
	s.node.queue_free()
	_broadcast(_rel(Msg.EVENT, [Ev.LEFT, id]), true)
	print("[Match] LEFT %d (%d players)" % [id, slots.size()])


func _full_state(for_id: int) -> Dictionary:
	var pl: Array = []
	for s: Slot in slots.values():
		pl.append({"id": s.id, "name": s.pname, "team": s.team, "pos": s.node.global_position,
			"yaw": s.node.rotation.y, "health": s.health, "alive": s.alive, "tp": s.tp, "mag": s.lo.mag,
			"reserve": s.lo.reserve, "ch": [s.lo.charges[Loadout.Tool.ORDINARY_CHARGE], s.lo.charges[Loadout.Tool.HEAVY_CHARGE]]})
	var walls: Array = []
	for m: WallModule in g.modules:
		walls.append([m.wall_id, m.state, m.revision])
	var ch: Array = []
	for c: Charge in get_tree().get_nodes_in_group("charges"):
		if is_instance_valid(c) and c.left > 0.0:
			ch.append([c.charge_id, c.owner_id, c.module.wall_id, c.kind, c.global_position, c.normal, c.left])
	return {"round": round_id, "tick": tick, "you": for_id, "players": pl, "walls": walls, "charges": ch}


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
	_seq += 1
	c.seq = _seq
	c.round_id = round_id & 0xFFFF
	c.view_tick = tick
	_process_cmd(me, c.quantised())
	for s: Slot in slots.values():
		if s.id == 1:
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
	for s: Slot in slots.values():
		s.history.append([tick, s.node.global_position, s.node.height, s.alive])
		if s.history.size() > HISTORY:
			s.history.pop_front()
		if s.body_vis:
			s.body_vis.scale.y = s.node.height / 1.8
	if tick % SNAP_EVERY == 0:
		_broadcast(_snapshot(), false)


func _process_cmd(s: Slot, c: NetCmd) -> void:
	s.last_seq = c.seq
	metrics["cmds"] += 1
	if c.round_id != (round_id & 0xFFFF):
		metrics["stale_round_cmds"] += 1
		return
	if not s.alive:
		c.move = Vector2.ZERO
		c.fire = false
		c.reload = false
		c.crouch = false
		c.sprint = false
	_shooter = s.id
	_view_tick = c.view_tick
	s.node.simulate(c, DT)
	s.lo.apply_cmd(c, DT)
	_shooter = 0


## Hit volumes of everyone but `shooter`, rewound to the tick the shooter was viewing (host), or the current
## interpolated view (client prediction, cosmetic only).
func _volumes_for(shooter: int) -> Array:
	var out: Array = []
	if not is_host:
		for r: Remote in remotes.values():
			if r.alive:
				out.append({"id": r.id, "a": r.pos + Vector3(0, 0.1, 0), "b": r.pos + Vector3(0, r.height - 0.05, 0)})
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
		var was_alive := true
		if rt < tick:
			for e: Array in s.history:
				if int(e[0]) == rt:
					pos = e[1]
					h = e[2]
					was_alive = e[3]
					break
		if was_alive:
			out.append({"id": s.id, "a": pos + Vector3(0, 0.1, 0), "b": pos + Vector3(0, h - 0.05, 0)})
	return out


func _on_player_hit(victim_id: int, damage: float, shooter_id: int) -> void:
	if not slots.has(victim_id):
		return
	var v: Slot = slots[victim_id]
	if not v.alive:
		return
	metrics["hits"] += 1
	metrics["damage"] += damage
	metrics["hits_by"][victim_id] = int(metrics["hits_by"].get(victim_id, 0)) + 1
	if not test_godmode:
		v.health = maxf(v.health - damage, 0.0)
	var killed := v.health <= 0.0
	if killed:
		v.alive = false
		if v.body_vis:
			v.body_vis.rotation.x = -PI * 0.5
		_broadcast(_rel(Msg.EVENT, [Ev.KILLED, round_id, victim_id, shooter_id]), true)
		if victim_id == 1:
			_set_center("You are down. Press T to restart the round.")
	if shooter_id == 1:
		g.loadout.show_hit(killed)
	else:
		_send(shooter_id, _rel(Msg.EVENT, [Ev.HIT, round_id, victim_id, killed]), true)


func _on_fired(res: Dictionary, shooter_id: int) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(Msg.SHOT)
	b.put_u32(shooter_id)
	var o: Vector3 = res.get("origin", Vector3.ZERO)
	var e: Vector3 = res["position"]
	var n: Vector3 = res["normal"]
	var world_hit: bool = res["hit"] and int(res["player_id"]) < 0
	for v in [o, e, n]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	b.put_u8(int(world_hit))
	_broadcast(b.data_array, false, shooter_id)
	if shooter_id != 1:
		ProcAudio.play(g, "shot", o, -6.0)
		if world_hit:
			g.loadout._add_mark(e, n, res["collider"])


func _on_charge_placed(c: Charge) -> void:
	_next_charge += 1
	c.charge_id = _next_charge
	c.detonated.connect(_on_charge_detonated)
	_broadcast(_rel(Msg.EVENT, [Ev.CHARGE, round_id, c.charge_id, c.owner_id, c.module.wall_id, c.kind,
		c.global_position, c.normal, c.left]), true)
	if c.owner_id != 1:
		ProcAudio.play(g, "beep", c.global_position)


func _on_charge_detonated(c: Charge) -> void:
	_broadcast(_rel(Msg.EVENT, [Ev.DETONATE, round_id, c.charge_id]), true)


func _on_wall_changed(m: WallModule) -> void:
	if _resetting:
		return
	_broadcast(_rel(Msg.EVENT, [Ev.WALL, round_id, m.wall_id, m.state, m.revision]), true)


## Host only: new round id, every wall intact, charges/marks/effects cleared, everyone respawned.
func restart_round() -> void:
	if not is_host:
		return
	_resetting = true
	round_id += 1
	for m: WallModule in g.modules:
		m.reset()
	for s: Slot in slots.values():
		s.lo.reset()
		s.health = MAX_HEALTH
		s.alive = true
		s.pending.clear()
		if s.body_vis:
			s.body_vis.rotation.x = 0.0
		_teleport(s)
	_resetting = false
	_set_center("")
	for p in ready_peers:
		_send(p, _rel(Msg.EVENT, [Ev.ROUND, round_id, _full_state(p)]), true)
	print("[Match] ROUND %d" % round_id)


func _snapshot() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(Msg.SNAP)
	b.put_u32(tick)
	b.put_u16(round_id & 0xFFFF)
	b.put_u8(slots.size())
	for s: Slot in slots.values():
		var p := s.node
		b.put_u32(s.id)
		b.put_u8(s.tp)
		b.put_u8(int(s.alive) | int(p.crouched) << 1 | int(s.lo.reloading) << 2)
		for v in [p.global_position, p.velocity]:
			b.put_float(v.x)
			b.put_float(v.y)
			b.put_float(v.z)
		b.put_float(p.rotation.y)
		b.put_float(p.pitch())
		b.put_float(p.height)
		b.put_u8(int(ceilf(s.health)))
		b.put_u32(s.last_seq)
		b.put_u8(s.lo.mag)
		b.put_u16(s.lo.reserve)
		b.put_u8(s.lo.tool)
		b.put_u8(s.lo.charges[Loadout.Tool.ORDINARY_CHARGE])
		b.put_u8(s.lo.charges[Loadout.Tool.HEAVY_CHARGE])
	return b.data_array


# ================================================================== client

func _client_tick() -> void:
	if not synced:
		return
	tick += 1
	var c: NetCmd = g.player.make_cmd()
	g.loadout.fill_cmd(c)
	_seq += 1
	c.seq = _seq
	c.round_id = round_id & 0xFFFF
	c.view_tick = maxi(int(_server_tick_f) - INTERP_TICKS, 0)
	if not my_alive:
		c.move = Vector2.ZERO
		c.fire = false
		c.reload = false
		c.crouch = false
		c.sprint = false
	c = c.quantised()
	g.player.simulate(c, DT)
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
		"mag": g.loadout.mag, "reserve": g.loadout.reserve}


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
		var hp := buf.get_u8()
		var ack := buf.get_u32()
		var mag := buf.get_u8()
		var reserve := buf.get_u16()
		var _tool := buf.get_u8()
		var ch_o := buf.get_u8()
		var ch_h := buf.get_u8()
		var alive := flags & 1 != 0
		if id == my_id:
			_set_alive(alive)
			my_health = hp
			g.loadout.charges[Loadout.Tool.ORDINARY_CHARGE] = ch_o
			g.loadout.charges[Loadout.Tool.HEAVY_CHARGE] = ch_h
			_reconcile(tp, ack, pos, vel, flags & 2 != 0, h, mag, reserve)
		elif not _departed.has(id):
			var rm := _remote(id)
			rm.health = hp
			if rm.alive != alive:
				rm.alive = alive
				rm.vis.rotation.x = 0.0 if alive else -PI * 0.5
			rm.buf.append([t, pos, yaw, h, alive])
			if rm.buf.size() > 30:
				rm.buf.pop_front()


func _reconcile(tp: int, ack: int, pos: Vector3, vel: Vector3, crouched: bool, h: float, mag: int, reserve: int) -> void:
	var p: Player = g.player
	var replay := false
	if tp != _my_tp:
		_my_tp = tp
		replay = true
	else:
		var e: Dictionary = _hist.get(ack, {})
		if e.is_empty():
			return
		var err: float = (e["pos"] as Vector3).distance_to(pos)
		if err > CORRECTION_EPS or bool(e["crouched"]) != crouched:
			replay = true
			metrics["corrections"] += 1
			metrics["corr_err"].append(err)
		var dm := mag - int(e["mag"])
		var dr := reserve - int(e["reserve"])
		if dm != 0 or dr != 0:
			g.loadout.mag = clampi(g.loadout.mag + dm, 0, g.loadout.tuning.mag_size)
			g.loadout.reserve = maxi(g.loadout.reserve + dr, 0)
			for k in _hist.keys():
				if k > ack:
					_hist[k]["mag"] = int(_hist[k]["mag"]) + dm
					_hist[k]["reserve"] = int(_hist[k]["reserve"]) + dr
	for k in _hist.keys():
		if k <= ack:
			_hist.erase(k)
	if not replay:
		return
	var yaw: float = p.rotation.y
	var pitch: float = p.pitch()
	p.set_move_state(pos, vel, crouched, h)
	var keys := _hist.keys()
	keys.sort()
	for k in keys:
		var c: NetCmd = _hist[k]["cmd"]
		p.simulate(c, DT)
		_hist[k]["pos"] = p.global_position
		_hist[k]["vel"] = p.velocity
		_hist[k]["crouched"] = p.crouched
		_hist[k]["height"] = p.height
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


func _rebuild_remote_vis(r: Remote) -> void:
	if r.vis:
		r.vis.free()
	r.vis = StandIn.build(StandIn.TEAM_RED if r.team == 0 else StandIn.TEAM_BLUE)
	r.root.add_child(r.vis)
	r.vis.rotation.x = 0.0 if r.alive else -PI * 0.5


func _drop_remote(id: int) -> void:
	if remotes.has(id):
		(remotes[id] as Remote).root.queue_free()
		remotes.erase(id)


func _set_alive(alive: bool) -> void:
	if alive == my_alive:
		return
	my_alive = alive
	_set_center("" if alive else "You are down. Wait for the host to restart the round.")


func _apply_full(d: Dictionary, first: bool) -> void:
	round_id = int(d["round"])
	if first:
		_server_tick_f = float(d["tick"])
		tick = int(d["tick"])
	_last_snap_tick = -1
	_hist.clear()
	_sent.clear()
	var seen := {}
	for pd: Dictionary in d["players"]:
		var id := int(pd["id"])
		seen[id] = true
		if id == my_id:
			_my_tp = int(pd["tp"])
			my_team = int(pd["team"])
			g.player.reset()
			g.player.teleport(pd["pos"], rad_to_deg(float(pd["yaw"])))
			my_health = float(pd["health"])
			_set_alive(bool(pd["alive"]))
			g.loadout.mag = int(pd["mag"])
			g.loadout.reserve = int(pd["reserve"])
			g.loadout.charges[Loadout.Tool.ORDINARY_CHARGE] = int(pd["ch"][0])
			g.loadout.charges[Loadout.Tool.HEAVY_CHARGE] = int(pd["ch"][1])
		else:
			var r := _remote(id, String(pd["name"]), int(pd["team"]))
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
	for w: Array in d["walls"]:
		var m: WallModule = g._mod(String(w[0]))
		if m == null:
			continue
		if int(w[1]) == WallModule.State.INTACT and int(w[2]) == 0:
			m.reset()
		else:
			m.apply_remote(int(w[1]), int(w[2]))
	for c: Node in get_tree().get_nodes_in_group("charges"):
		c.free()
	for cd: Array in d["charges"]:
		_spawn_remote_charge(cd[0], cd[1], cd[2], cd[3], cd[4], cd[5], cd[6])
	synced = true


func _spawn_remote_charge(cid: int, owner: int, wall_id: String, kind: int, pos: Vector3, n: Vector3, left: float) -> void:
	var m: WallModule = g._mod(wall_id)
	if m == null:
		return
	var c := Charge.new()
	c.charge_id = cid
	c.owner_id = owner
	c.authoritative = false
	g.add_child(c)
	c.setup(m, kind, left, pos, n)
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
			_apply_full(ev[2] as Dictionary, false)
			_set_center("")
			return
	# Everything below belongs to one round.
	if int(ev[1]) != round_id:
		metrics["stale_events"] += 1
		return
	match kind:
		Ev.CHARGE:
			if _find_charge(int(ev[2])) == null:
				_spawn_remote_charge(ev[2], ev[3], ev[4], ev[5], ev[6], ev[7], ev[8])
				if int(ev[3]) == my_id:
					g.loadout.say("Charge armed: %.0f s. Move away!" % float(ev[8]))
		Ev.DETONATE:
			var c := _find_charge(int(ev[2]))
			if c:
				if g.loadout.effects:
					g.loadout.effects.burst(c.global_position, c.normal, c.kind == WallModule.Kind.HEAVY)
				if c.module and c.module.charge == c:
					c.module.charge = null
				c.queue_free()
		Ev.WALL:
			var m: WallModule = g._mod(String(ev[2]))
			if m == null or not m.apply_remote(int(ev[3]), int(ev[4])):
				metrics["stale_events"] += 1
		Ev.HIT:
			g.loadout.show_hit(bool(ev[3]))
		Ev.KILLED:
			if int(ev[2]) == my_id:
				_set_alive(false)
			elif remotes.has(int(ev[2])):
				var r: Remote = remotes[int(ev[2])]
				r.alive = false
				r.vis.rotation.x = -PI * 0.5
		Ev.REJECT:
			g.loadout.say(String(ev[2]))
		Ev.FACE:
			g.player.set_look(rad_to_deg(float(ev[2])), 0.0)


## Test hook: feed an event as if it came from the host (stale/duplicate handling).
func inject_event(ev: Array) -> void:
	_on_event(ev)


func _on_remote_shot(buf: StreamPeerBuffer) -> void:
	var _shooter_id := buf.get_u32()
	var o := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	var e := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	var n := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	ProcAudio.play(g, "shot", o, -6.0)
	if buf.get_u8() == 1:
		g.loadout._add_mark(e, n, null)


func _interpolate() -> void:
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
		r.root.global_position = r.pos
		r.root.rotation.y = lerp_angle(float(a[2]), float(b[2]), k)
		r.vis.scale.y = r.height / 1.8


# ================================================================== frame

func _physics_process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_deliver_due()
	if is_host:
		_host_tick()
		metrics["sim_us"].append(Time.get_ticks_usec() - t0)
	else:
		_client_tick()


func _process(delta: float) -> void:
	if not is_host and synced:
		_server_tick_f += delta * TICK_RATE
		_interpolate()
	_pop_enet_stats()
	_bytes_window["t"] += delta
	if _bytes_window["t"] >= 1.0:
		_bytes_window["up_rate"] = (metrics["tx"] - _bytes_window["up"]) / _bytes_window["t"]
		_bytes_window["down_rate"] = (metrics["rx"] - _bytes_window["down"]) / _bytes_window["t"]
		_bytes_window["up"] = metrics["tx"]
		_bytes_window["down"] = metrics["rx"]
		_bytes_window["t"] = 0.0
	_update_hud()


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
	var hp := my_health
	if is_host and slots.has(1):
		hp = (slots[1] as Slot).health
	var rtt: PackedFloat32Array = metrics["rtt_ms"]
	lines.append("HP %d   round %d   %s" % [int(hp), round_id, "HOST" if is_host else "RTT %.0f ms" % (rtt[rtt.size() - 1] if rtt.size() > 0 else 0.0)])
	lines.append("net up %.1f KB/s  down %.1f KB/s%s" % [_bytes_window["up_rate"] / 1024.0, _bytes_window["down_rate"] / 1024.0,
		"  corrections %d" % metrics["corrections"] if not is_host else ""])
	if is_host:
		for s: Slot in slots.values():
			lines.append("%s %s  %d hp%s" % ["[R]" if s.team == 0 else "[B]", s.pname, int(s.health), "" if s.alive else "  DOWN"])
	else:
		lines.append("[%s] you  %d hp" % ["R" if _my_team() == 0 else "B", int(my_health)])
		for r: Remote in remotes.values():
			lines.append("%s %s  %d hp%s" % ["[R]" if r.team == 0 else "[B]", r.pname, int(r.health), "" if r.alive else "  DOWN"])
	_hud.text = "\n".join(lines)


func _my_team() -> int:
	return my_team


# ================================================================== state digest (tests)

func digest() -> Dictionary:
	var hp := {}
	var ammo := {}
	if is_host:
		for s: Slot in slots.values():
			hp[s.id] = [int(ceilf(s.health)), s.alive]
			ammo[s.id] = [s.lo.mag, s.lo.reserve, s.lo.charges[Loadout.Tool.ORDINARY_CHARGE], s.lo.charges[Loadout.Tool.HEAVY_CHARGE]]
	else:
		hp[my_id] = [int(ceilf(my_health)), my_alive]
		ammo[my_id] = [g.loadout.mag, g.loadout.reserve, g.loadout.charges[Loadout.Tool.ORDINARY_CHARGE], g.loadout.charges[Loadout.Tool.HEAVY_CHARGE]]
		for r: Remote in remotes.values():
			hp[r.id] = [int(ceilf(r.health)), r.alive]
	var walls := {}
	for m: WallModule in g.modules:
		walls[m.wall_id] = [m.state, m.revision, m.shape_count(), g._parts_match(m)]
	var ch := 0
	for c: Charge in get_tree().get_nodes_in_group("charges"):
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			ch += 1
	return {"round": round_id, "hp": hp, "ammo": ammo, "walls": walls, "charges": ch}
