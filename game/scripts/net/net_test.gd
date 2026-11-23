class_name NetTest
extends Node
## Multi-process networked match test (headless). Every process is a scripted bot that plays only through
## NetCmds (the same path as a human); the host orchestrates scenarios over a reliable test channel and
## compares every client's view (state digest) with its own authoritative state.
## Host:   -- --match-host --net-test=<players> [--late-file=<path>] [--metrics-out=<path>] [--sim-*]
## Client: -- --match-join=<ip> --net-test --host-left-ok [--wait-file=<path>] [--sim-*]
## tools/net_test.sh launches the processes. Prints SMOKE_OK match / SMOKE_FAIL match on the host.

const EYE := 1.65
const FIRE_GAP := 8 ## ticks between single shots (> fire_interval)
## Bystanders wait here (room, east side) so they never stand in a test's line of fire.
const PARK := [Vector3(8.2, 0.05, -3.0), Vector3(8.2, 0.05, -4.2), Vector3(8.2, 0.05, -6.3), Vector3(7.9, 0.05, -7.0),
	Vector3(5.0, 0.05, -6.5), Vector3(5.5, 0.05, -3.0)]

var g: Node3D
var net: NetMatch
var _fails := 0
var _op_seq := 0
var _done := {} ## op id -> result (host)
var _reports := {} ## tag -> {peer: report}
var results := {}


func start(graybox: Node3D) -> void:
	g = graybox
	net = g.net
	name = "NetTest"
	process_physics_priority = -20
	net.test_msg.connect(_on_test_msg)
	var limit := 300.0
	get_tree().create_timer(limit).timeout.connect(func() -> void:
		print("SMOKE_FAIL match timeout (%s)" % ("host" if net.is_host else "client"))
		get_tree().quit(1))
	if net.is_host:
		_run_host.call_deferred()


# ================================================================== messaging

func _on_test_msg(sender: int, d: Dictionary) -> void:
	if net.is_host:
		if String(d.get("op", "")) == "done":
			_done[int(d["id"])] = d.get("result", {})
		return
	if sender != 1:
		return
	_client_exec(d)


func _client_exec(d: Dictionary) -> void:
	var result: Dictionary = await _exec(d)
	net.send_test(1, {"op": "done", "id": d["id"], "result": result})
	if String(d["op"]) == "quit":
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(0)


## Runs ops on several players at once and waits for all of them. ops: {player_id: op_dict}
func _all(ops: Dictionary, timeout: float = 30.0) -> Dictionary:
	var ids := {}
	for pid: int in ops:
		_op_seq += 1
		var d: Dictionary = ops[pid].duplicate()
		d["id"] = _op_seq
		ids[pid] = _op_seq
		if pid == 1:
			_host_local(d)
		else:
			net.send_test(pid, d)
	var t := 0.0
	while t < timeout:
		var all_done := true
		for pid: int in ids:
			if not _done.has(ids[pid]):
				all_done = false
		if all_done:
			break
		await get_tree().physics_frame
		t += NetMatch.DT
	var out := {}
	for pid: int in ids:
		out[pid] = _done.get(ids[pid], null)
		if out[pid] == null:
			_check("op %s on %d finished" % [ops[pid]["op"], pid], false)
	return out


func _do(pid: int, op: Dictionary) -> Dictionary:
	var r := await _all({pid: op})
	return r[pid] if r[pid] != null else {}


func _host_local(d: Dictionary) -> void:
	var result: Dictionary = await _exec(d)
	_done[int(d["id"])] = result


# ================================================================== bot actions (run on the acting player's process)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _target_pos(id: int) -> Vector3:
	if net.is_host:
		return (net.slots[id] as NetMatch.Slot).node.global_position
	if net.remotes.has(id):
		return (net.remotes[id] as NetMatch.Remote).pos
	return Vector3.ZERO


func _look_at(point: Vector3) -> void:
	var p: Player = g.player
	var eye := p.camera.global_position
	var d := point - eye
	p.set_look(rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


func _exec(d: Dictionary) -> Dictionary:
	var p: Player = g.player
	var lo: Loadout = g.loadout
	match String(d["op"]):
		"controls_input":
			p.script_lean = int(d.get("lean", 0))
			lo.script_fire = bool(d.get("fire", false))
			if d.has("recoil"):
				lo.use_recoil = bool(d.recoil)
			await _frames(int(d.get("frames", 30)))
			return {"lean": p.lean, "pitch": p.pitch(), "yaw": p.rotation.y, "mag": lo.mag, "spray": lo.spray_shots}
		"controls_remote":
			var r: NetMatch.Remote = net.remotes[int(d.target)]
			return {"lean": r.lean, "roll": r.vis.rotation.z}
		"gadget_digest":
			return {"projectiles": g.gadgets.projectiles.size(), "zones": g.gadgets.zones.size(),
				"owned": lo.gadgets_owned, "smoke": lo.charges[Loadout.Tool.SMOKE], "flash": float(g.gadgets.flashes.get(net.my_id, 0.0))}
		"grenade_throw":
			lo.want_tool = int(d.tool)
			lo.script_fire = false
			await _frames(4)
			lo.script_fire = true
			await _frames(8)
			lo.script_fire = false
			return {}
		"round_action":
			if d.has("round_back"):
				var rr := net.round_id - int(d.round_back)
				if net.is_host:
					net.loop._action_host(net.my_id, rr, String(d.action))
				else:
					net.loop._action.rpc_id(1, rr, String(d.action))
			else:
				net.loop.request(String(d["action"]))
			return {}
		"round_input":
			net.loop.script_hold = bool(d.get("hold", false))
			net.loop.script_drop = bool(d.get("drop", false))
			p.script_move = d.get("move", Vector2.ZERO)
			lo.script_fire = bool(d.get("fire", false)) or bool(d.get("plant", false))
			if d.get("plant", false):
				lo.want_tool = Loadout.Tool.BOMB # slot 5 + held fire plants
			await _frames(int(d.get("frames", 1)))
			return {}
		"round_capture":
			if NetworkManager.args.has("capture-rounds") and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var path := String(NetworkManager.args["capture-rounds"]).path_join("%s_%d.png" % [d["tag"], net.my_id])
				g.get_viewport().get_texture().get_image().save_png(path)
			return {}
		"round_buy":
			if d.get("replay", false):
				net.loop._buy_seq -= 1 # same request id again: must answer, never charge twice
			net.loop.request_buy(String(d["item"]), int(d.get("recipient", 0)))
			await _frames(3)
			return {}
		"round_buy_raw":
			net.loop._buy_seq += 1
			var rr := net.round_id - int(d.get("round_back", 0))
			if net.is_host:
				net.loop._buy_host(net.my_id, rr, net.loop._buy_seq, String(d["item"]), int(d.get("recipient", 0)))
			else:
				net.loop._buy.rpc_id(1, rr, net.loop._buy_seq, String(d["item"]), int(d.get("recipient", 0)))
			await _frames(3)
			return {}
		"hold_tool":
			_look_at(d["point"])
			lo.want_tool = int(d["tool"])
			await _frames(4)
			_look_at(d["point"])
			lo.script_fire = true
			await _frames(int(d["frames"]))
			lo.script_fire = false
			await _frames(4)
			lo.want_tool = Loadout.Tool.RIFLE
			await _frames(2)
			return {}
		"loot_take":
			var id := int(d.drop_id)
			if not net.weapon_drops.drops.has(id):
				return {}
			_look_at(net.weapon_drops.drops[id].pos)
			await _frames(12)
			net.request_interaction()
			return {}
		"loot_report":
			return {"drops": net.weapon_drops.drops.keys(), "primary": lo.primary,
				"ammo": lo.gun_inventory(Loadout.Tool.RIFLE).get("ammo", []),
				"flash": ShopCatalog.owned(lo, "flash"), "smoke": ShopCatalog.owned(lo, "smoke"),
				"kit": lo.defuse_kit}
		"round_report":
			return {"credits": net.loop.credits, "kits": lo.charges[Loadout.Tool.REINFORCE],
				"pen": g._mod("Divider_C_ordinary").get_meta("pen_mult"),"state": net.loop.state(), "alive": net.local_alive(), "team": net.local_team(),
				"view": net.remote_view(), "voice_people": net.voice.people.duplicate(true),
				"camera": str(g.get_viewport().get_camera_3d().name), "nodes": get_tree().get_node_count(),
				"round": net.round_id, "mag": lo.mag, "pos": p.global_position, "kit": lo.defuse_kit,
				"health": net.my_health, "watching": net.loop.watched_id,
				"viewpoint": g.get_viewport().get_camera_3d().global_position}
		"round_rejoin":
			var target := int(d["target"])
			var remote: NetMatch.Remote = net.remotes[target]
			var pname := remote.pname
			var team := remote.team
			# Steam can reuse the same peer ID after departure. Exercise the real event/snapshot paths.
			net.inject_event([NetMatch.Ev.LEFT, target])
			net.inject_event([NetMatch.Ev.JOINED, target, pname, team])
			await _frames(12)
			return {"restored": not net._departed.has(target) and net.remotes[target].buf.size() > 0}
		"round_old_snapshot":
			var buf := StreamPeerBuffer.new()
			buf.data_array = d["snapshot"]
			buf.seek(1)
			var saved := net._last_snap_tick
			net._last_snap_tick = -1 # force delivery after the reliable KILLED, as across RPC channels
			net._on_snapshot(buf)
			net._last_snap_tick = saved
			return {"alive": net.my_alive}
		"round_stale":
			var before := net.loop.rules.state()
			net.inject_event([NetMatch.Ev.LOOP, net.round_id - 1, d["state"]])
			return {"unchanged": before == net.loop.rules.state()}
		"view_remote":
			_look_at(_target_pos(int(d["target"])) + Vector3(0, 1.0, 0))
			await _frames(10)
			if NetworkManager.args.has("capture-net-view") and DisplayServer.get_name() != "headless":
				var path := String(NetworkManager.args["capture-net-view"]).path_join("peer_%d.png" % net.my_id)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(path)
			return {}
		"voice_send":
			var pcm := PackedFloat32Array()
			for i in VoiceQueue.SAMPLES:
				pcm.append(sin(i * 0.11) * 0.3)
			var packet := VoiceAudio.Codec.encode(pcm)
			for i in int(d.get("chunks", 25)):
				net.voice.send_audio(packet, bool(d.get("radio", false)))
				await get_tree().create_timer(0.02).timeout
			return {}
		"voice_recover_radio":
			_look_at(d.point)
			await _frames(12)
			net.request_interaction()
			return {}
		"voice_mute_enemy":
			net.voice.toggle_enemy_radio()
			return {"muted": net.voice.enemy_radio_muted}
		"voice_report":
			return {"received": net.voice._test_received.duplicate(), "stolen": net.voice.stolen.duplicate(),
				"bot_radio": net.voice.bot_radio_received,
				"muted_enemy": net.voice.enemy_radio_muted, "epoch": net.voice.epoch, "speakers": net.voice._speakers.size(), "pickups": net.voice.pickups.size(),
				"relays": net.voice.recipients.duplicate(), "rpc_count": net.voice.audio_rpcs, "sim_drops": net.voice.sim_dropped,
				"invalid": net.voice.received_invalid, "pending": net.voice._delayed.size(), "enet_throttle": _voice_throttle()}
		"voice_clear":
			net.voice._test_received.clear()
			net.voice.recipients.clear()
			net.voice.audio_rpcs = 0
			net.voice.sim_dropped = 0
			net.voice.received_invalid = 0
			return {}
		"pattern":
			for st: Array in d["steps"]:
				p.script_move = Vector2(st[0], st[1])
				p.script_crouch = bool(st[2])
				p.script_slow_walk = bool(st[3])
				lo.script_fire = st.size() > 5 and bool(st[5])
				await _frames(int(st[4]))
			p.script_move = Vector2.ZERO
			p.script_crouch = false
			p.script_slow_walk = false
			lo.script_fire = false
			await _frames(30)
		"fire":
			lo.want_tool = int(d.get("tool", Loadout.Tool.RIFLE))
			lo.script_aim = true
			var target := int(d.get("target", -1))
			var point: Vector3 = d.get("point", Vector3.ZERO)
			var aim_offset := Vector3.UP * float(d.get("height", 1.2))
			for k in 4:
				_look_at(_target_pos(target) + aim_offset if target >= 0 else point)
				await _frames(1)
			for i in int(d["shots"]):
				for k in int(d.get("gap", FIRE_GAP)):
					_look_at(_target_pos(target) + aim_offset if target >= 0 else point)
					lo.script_fire = k == 0
					await _frames(1)
			lo.script_fire = false
			lo.script_aim = false
			await _frames(4)
		"place":
			_look_at(d["point"])
			lo.want_tool = int(d["tool"])
			await _frames(4)
			_look_at(d["point"])
			lo.script_fire = true
			await _frames(1)
			lo.script_fire = false
			await _frames(4)
			lo.want_tool = Loadout.Tool.RIFLE
			await _frames(2)
		"walk":
			p.set_look(float(d["yaw"]), 0.0)
			p.script_move = Vector2(0, -1)
			await _frames(int(d["ticks"]))
			p.script_move = Vector2.ZERO
			await _frames(30)
		"forge":
			net.send_forged_cmds(bool(d.get("old_seq", false)), bool(d.get("old_round", false)))
			await _frames(30)
		"inject_stale":
			var before := int(net.metrics["stale_events"])
			var m: WallModule = g._mod("Divider_C_ordinary")
			var st0 := [m.state, m.revision]
			net.inject_event([NetMatch.Ev.WALL, net.round_id, m.wall_id, WallModule.State.INTACT, m.revision, m.material, [], Vector3.ZERO, []]) # duplicate rev
			net.inject_event([NetMatch.Ev.WALL, net.round_id - 1, m.wall_id, WallModule.State.BREACHED, m.revision + 5, m.material, [], Vector3.ZERO, []]) # old round
			net.inject_event([NetMatch.Ev.ROUND, net.round_id - 1, {}]) # old round reset
			net.inject_event([NetMatch.Ev.KILLED, net.round_id - 1, net.my_id, 1]) # old round death
			return {"ignored": int(net.metrics["stale_events"]) - before, "unchanged": [m.state, m.revision] == st0,
				"alive": net.my_alive}
		"desync":
			# Move the local player without telling the host: the next snapshot must pull it back.
			var c0 := int(net.metrics["corrections"])
			p.global_position += Vector3(0.0, 0.0, 0.6)
			await _frames(40)
			return {"corrections": int(net.metrics["corrections"]) - c0, "pos": p.global_position}
		"report":
			return _report()
		"quit":
			return {}
	return {}


func _report() -> Dictionary:
	var m := net.metrics
	var corr: PackedFloat32Array = m["corr_err"]
	var rtt: PackedFloat32Array = m["rtt_ms"]
	return {"digest": net.digest(), "pos": g.player.global_position, "nodes": get_tree().get_node_count(),
		"steps_local": m.steps_local, "steps_remote": m.steps_remote.duplicate(), "incoming_shots": m.incoming_shots,
		"voice_roster": net.voice.people.keys(), "voice_speakers": net.voice._speakers.keys(),
		"remote_view": net.remote_view(), "remotes": net.remotes.size(), "corrections": m["corrections"], "corr_max": _max(corr), "corr_mean": _mean(corr),
		"rtt_mean": _mean(rtt), "rtt_p95": _pct(rtt, 0.95), "rtt_n": rtt.size(), "snaps": m["snaps"],
		"stale_snaps": m["stale_snaps"], "stale_events": m["stale_events"], "rx_dropped_sim": m["rx_dropped_sim"],
		"enet_tx": m["enet_tx"], "enet_rx": m["enet_rx"], "secs": (Time.get_ticks_msec() - int(m["t0"])) / 1000.0}


static func _mean(a: Variant) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _max(a: Variant) -> float:
	var r := 0.0
	for v in a:
		r = maxf(r, v)
	return r


static func _pct(a: Variant, q: float) -> float:
	if a.size() == 0:
		return 0.0
	var arr: Array = Array(a)
	arr.sort()
	return float(arr[clampi(int(ceil(q * arr.size())) - 1, 0, arr.size() - 1)])


# ================================================================== host orchestration

func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("  PASS " if ok else "  FAIL ") + label + (" " + detail if detail != "" else ""))
	if not ok:
		_fails += 1


func _ids() -> Array:
	var ids: Array = net.slots.keys()
	ids.sort()
	return ids


func _wait_players(n: int, timeout: float) -> bool:
	var t := 0.0
	while net.slots.size() < n and t < timeout:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return net.slots.size() >= n


func _park(active: Array) -> void:
	var i := 0
	for id in _ids():
		if id not in active:
			net.test_teleport(id, PARK[i % PARK.size()], 90.0)
			i += 1


func _hits_on(id: int) -> int:
	return int(net.metrics["hits_by"].get(id, 0))


func _settle(secs: float = 0.6) -> void:
	await get_tree().create_timer(secs).timeout


func _hp(id: int) -> float:
	return (net.slots[id] as NetMatch.Slot).health


func _slot(id: int) -> NetMatch.Slot:
	return net.slots[id]


## Every client's view must agree with the host: round, walls (state, revision, collision = authored parts),
## every player's health/alive, its own ammo/charges, and the number of live charges.
func _consistency(tag: String) -> Dictionary:
	await _settle(0.6)
	var ops := {}
	for id in _ids():
		ops[id] = {"op": "report"}
	var reps := await _all(ops)
	var hd: Dictionary = net.digest()
	var bad: Array[String] = []
	for id: int in reps:
		if id == 1 or reps[id] == null:
			continue
		var views: Dictionary = reps[id]["remote_view"]
		for pid: int in net.slots:
			if pid == id:
				continue
			if not views.has(pid):
				bad.append("%d missing rendered player %d" % [id, pid])
				continue
			var view: Dictionary = views[pid]
			if (view.render_pos as Vector3).distance_to(_slot(pid).node.global_position) > 0.08:
				bad.append("%d renders %d at %s, host %s" % [id, pid, view.render_pos, _slot(pid).node.global_position])
			if int(view.visible_meshes) == 0 or (view.scale as Vector3).length() < 0.1:
				bad.append("%d has invisible player %d" % [id, pid])
		var cd: Dictionary = reps[id]["digest"]
		if int(cd["round"]) != int(hd["round"]):
			bad.append("%d round %s!=%s" % [id, cd["round"], hd["round"]])
		for w: String in hd["walls"]:
			var a: Array = hd["walls"][w]
			var b: Array = cd["walls"][w]
			if a[0] != b[0] or a[1] != b[1] or not bool(b[3]) or a[2] != b[2]:
				bad.append("%d wall %s %s!=%s" % [id, w, b, a])
		for pid: int in hd["hp"]:
			if not cd["hp"].has(pid):
				bad.append("%d missing player %d" % [id, pid])
			elif cd["hp"][pid] != hd["hp"][pid]:
				bad.append("%d sees %d hp %s (host %s)" % [id, pid, cd["hp"][pid], hd["hp"][pid]])
		if cd["hp"].size() != hd["hp"].size():
			bad.append("%d sees %d players (host %d)" % [id, cd["hp"].size(), hd["hp"].size()])
		if cd["ammo"][id] != hd["ammo"][id]:
			bad.append("%d ammo %s (host %s)" % [id, cd["ammo"][id], hd["ammo"][id]])
		if int(cd["charges"]) != int(hd["charges"]):
			bad.append("%d charges %d (host %d)" % [id, cd["charges"], hd["charges"]])
		var hp_pos := _slot(id).node.global_position
		if (reps[id]["pos"] as Vector3).distance_to(hp_pos) > 0.05:
			bad.append("%d pos %s (host %s)" % [id, reps[id]["pos"], hp_pos])
	_check("consistent: " + tag, bad.is_empty(), "; ".join(bad))
	_reports[tag] = reps
	return reps


## --steps=a,b,... limits the run (move, los, moving, pen, breach, late, death, forged, resets, leave).
func _want(step: String) -> bool:
	var a := NetworkManager.args
	return not a.has("steps") or step in String(a["steps"]).split(",")


func _run_host() -> void:
	var a := NetworkManager.args
	var want := int(a.get("net-test", 2))
	var late := a.has("late-file")
	print("[Test] waiting for %d players" % want)
	_check("%d players joined" % want, await _wait_players(want, 60.0), "have %d" % net.slots.size())
	if _fails > 0:
		_finish()
		return
	await _settle(1.0)
	if a.has("round-test"):
		await _round_checks()
		_finish()
		return
	var ids := _ids()
	var S: int = ids[1] ## shooter: first client
	var V: int = ids[2] if ids.size() > 2 else 1 ## victim: second client, or the host
	var P: int = 1 ## second placer for the simultaneous-charge race
	if ids.size() > 3:
		P = ids[3]
	print("[Test] players %s shooter=%d victim=%d placer2=%d" % [ids, S, V, P])

	if _want("controls"):
		await _controls_checks(S)
	if _want("gadgets"):
		await _gadget_checks(S)
	if _want("visibility"):
		net.test_teleport(1, Vector3(0, 0.05, -5), 180)
		net.test_teleport(S, Vector3(0, 0.05, -2), 0)
		await _settle()
		await _all({1: {"op": "view_remote", "target": S}, S: {"op": "view_remote", "target": 1}})
		await _consistency("mutual player visibility")
	if _want("voice"):
		await _voice_checks()

	# ---- 1. everyone moves at once (prediction / reconciliation under load)
	if _want("move"):
		var pat := {"op": "pattern", "steps": [[0, -1, 0, 0, 30], [1, 0, 0, 0, 25], [0, 1, 0, 1, 30], [-1, 0, 1, 0, 30],
			[0, -1, 1, 0, 20], [0, 0, 0, 0, 10], [0, 1, 0, 0, 20], [1, 1, 0, 0, 15]]}
		var ops := {}
		for id in ids:
			ops[id] = pat
		await _all(ops)
		var reports := await _consistency("after simultaneous movement")
		if reports.has(S):
			var report: Dictionary = reports[S]
			_check("owner predicts footsteps once and receives remote footsteps",
				int(report.steps_local) > 0 and int(report.steps_remote.get(1, 0)) > 0 and not report.steps_remote.has(S))
		var before := _slot(S).node.global_position
		var ds := await _do(S, {"op": "desync"})
		_check("client desync is corrected by reconciliation", int(ds.get("corrections", 0)) >= 1
			and (ds["pos"] as Vector3).distance_to(_slot(S).node.global_position) < 0.05
			and _slot(S).node.global_position.distance_to(before) < 0.05, str(ds))

	# ---- 2. static line-of-sight hits: 2 body hits (3 would kill at the quick-TTK damage)
	if _want("los"):
		_park([S, V])
		net.test_teleport(S, Vector3(0.0, 0.05, -1.0), 0.0)
		net.test_teleport(V, Vector3(0.0, 0.05, -7.0), 180.0)
		await _settle(0.5)
		var mag0 := _slot(S).lo.mag
		var dmg := _slot(S).lo.tuning.damage
		await _do(S, {"op": "fire", "target": V, "shots": 2})
		await _settle(0.4)
		_check("LOS: 2 hits = 2 x weapon damage", is_equal_approx(_hp(V), 100.0 - 2.0 * dmg), "hp=%.0f" % _hp(V))
		_check("LOS: shooter spent 2 rounds (host)", _slot(S).lo.mag == mag0 - 2, "mag %d -> %d" % [mag0, _slot(S).lo.mag])
		await _consistency("after LOS hits")

	# ---- 3. moving target: lag compensation on vs off (counts hits; godmode keeps the target alive)
	if _want("moving"):
		for mode in [true, false]:
			net.restart_round()
			net.lag_comp = mode
			net.test_godmode = true
			await _settle(0.8)
			_park([S, V])
			net.test_teleport(S, Vector3(0.0, 0.05, -1.0), 0.0)
			net.test_teleport(V, Vector3(0.7, 0.05, -8.0), 180.0)
			await _settle(0.6)
			var h0 := _hits_on(V)
			var other0 := int(net.metrics["hits"]) - h0
			var strafe := {"op": "pattern", "steps": []}
			for i in 8:
				strafe["steps"].append([1 if i % 2 == 0 else -1, 0, 0, 0, 24])
			var shoot := {"op": "fire", "target": V, "shots": 12, "gap": 12}
			var xs := [INF, -INF]
			var track := func() -> void:
				var x: float = _slot(V).node.global_position.x
				xs[0] = minf(xs[0], x)
				xs[1] = maxf(xs[1], x)
			get_tree().physics_frame.connect(track)
			await _all({V: strafe, S: shoot})
			get_tree().physics_frame.disconnect(track)
			print("[Test] target x range on host: %.2f .. %.2f" % [xs[0], xs[1]])
			_check("moving target strafed across the line of fire", xs[1] - xs[0] > 1.0, "x %.2f..%.2f" % [xs[0], xs[1]])
			await _settle(0.3)
			var hits := _hits_on(V) - h0
			_check("moving target: no stray hits on bystanders", int(net.metrics["hits"]) - _hits_on(V) == other0)
			results["moving_hits_lagcomp_" + ("on" if mode else "off")] = hits
			print("[Test] moving target, lag comp %s: %d/12 hits" % ["on" if mode else "off", hits])
		net.test_godmode = false
		net.lag_comp = not a.has("no-lag-comp")
		_check("moving target hit with lag compensation (>=10/12)", int(results["moving_hits_lagcomp_on"]) >= 10,
			"on=%d off=%d" % [results["moving_hits_lagcomp_on"], results["moving_hits_lagcomp_off"]])

	# ---- 4. penetration: ordinary panel halves damage, reinforced stops the round
	if _want("pen"):
		net.restart_round()
		await _settle(0.8)
		_park([S, V])
		net.test_teleport(S, Vector3(0.3, 0.05, -8.2), -90.0)
		net.test_teleport(V, Vector3(2.0, 0.05, -8.2), 90.0)
		await _settle(0.6)
		await _do(S, {"op": "fire", "target": V, "shots": 2})
		await _settle(0.4)
		var half := _slot(S).lo.tuning.damage * 0.5
		_check("through ordinary panel: 2 x half damage", is_equal_approx(_hp(V), 100.0 - 2.0 * half), "hp=%.0f" % _hp(V))
		net.test_teleport(S, Vector3(0.3, 0.05, -2.75), -90.0)
		net.test_teleport(V, Vector3(2.2, 0.05, -2.75), 90.0)
		await _settle(0.6)
		await _do(S, {"op": "fire", "target": V, "shots": 2})
		await _settle(0.4)
		_check("reinforced panel stops rounds", is_equal_approx(_hp(V), 100.0 - 2.0 * half), "hp=%.0f" % _hp(V))
		await _consistency("after penetration")

	# ---- 5. simultaneous charge placement on one panel, breach, walk through
	if _want("breach"):
		net.restart_round()
		await _settle(0.8)
		_park([S, P])
		net.test_teleport(S, Vector3(0.4, 0.05, -5.6), -90.0)
		net.test_teleport(P, Vector3(0.4, 0.05, -5.0), -90.0)
		await _settle(0.6)
		await _all({S: {"op": "place", "tool": Loadout.Tool.ORDINARY_CHARGE, "point": Vector3(1.4, 1.2, -5.6)},
			P: {"op": "place", "tool": Loadout.Tool.ORDINARY_CHARGE, "point": Vector3(1.4, 1.2, -5.0)}})
		await _settle(0.5)
		var spent: int = 6 - _slot(S).lo.charges[Loadout.Tool.ORDINARY_CHARGE] - _slot(P).lo.charges[Loadout.Tool.ORDINARY_CHARGE]
		_check("simultaneous placement: exactly one charge", net.digest()["charges"] == 1 and spent == 1,
			"charges=%d spent=%d" % [net.digest()["charges"], spent])
		await _consistency("charge armed (countdown)")
		await _settle(3.5)
		var wc: WallModule = g._mod("Divider_C_ordinary")
		_check("panel breached once (host)", wc.state == WallModule.State.BREACHED and wc.revision == 1)
		await _consistency("after breach")
		net.test_teleport(S, Vector3(0.4, 0.05, -5.4), -90.0)
		await _settle(0.5)
		await _do(S, {"op": "walk", "yaw": -90.0, "ticks": 70})
		_check("shooter walked through the new opening (host)", _slot(S).node.global_position.x > 3.0,
			"x=%.2f" % _slot(S).node.global_position.x)
		await _consistency("after walking through opening")

	# ---- 6. late join: snapshot reproduces the opening
	if late and _want("late"):
		var f := FileAccess.open(String(a["late-file"]), FileAccess.WRITE)
		f.store_string("go")
		f.close()
		_check("late joiner arrived", await _wait_players(want + 1, 40.0), "have %d" % net.slots.size())
		await _settle(1.0)
		var reps := await _consistency("late joiner sees current openings")
		var lj: int = _ids()[_ids().size() - 1]
		if reps.has(lj) and reps[lj] != null:
			var w: Array = reps[lj]["digest"]["walls"]["Divider_C_ordinary"]
			_check("late joiner: Divider_C breached rev 1 with matching collision", w[0] == WallModule.State.BREACHED
				and w[1] == 1 and bool(w[3]), str(w))
		ids = _ids()

	# ---- 7. death: dead players can't move or shoot
	if _want("death"):
		_park([S, V])
		net.test_teleport(S, Vector3(0.0, 0.05, -1.0), 0.0)
		net.test_teleport(V, Vector3(0.0, 0.05, -7.0), 180.0)
		await _settle(0.6)
		var before_hit := await _do(V, {"op": "report"})
		var expected_hits := ceili(_hp(V) / _slot(S).lo.tuning.damage)
		await _do(S, {"op": "fire", "target": V, "shots": 5})
		await _settle(0.4)
		_check("body hits kill", not _slot(V).alive and _hp(V) == 0.0, "hp=%.0f" % _hp(V))
		var after_hit := await _do(V, {"op": "report"})
		_check("victim receives one shot cue per hit including the lethal hit",
			int(after_hit.incoming_shots) - int(before_hit.incoming_shots) == expected_hits)
		var vpos := _slot(V).node.global_position
		var shp := _hp(S)
		await _do(V, {"op": "pattern", "steps": [[0, -1, 0, 0, 30, true], [1, 0, 0, 0, 30, true]]})
		_check("dead player can't move", _slot(V).node.global_position.distance_to(vpos) < 0.05,
			"moved %.2f" % _slot(V).node.global_position.distance_to(vpos))
		_check("dead player can't shoot", _hp(S) == shp)
		await _consistency("after death")

	if _want("headshots"):
		net.restart_round()
		await _settle()
		_park([S, V])
		net.test_teleport(S, Vector3(0.0, 0.05, -1.0), 0.0)
		net.test_teleport(V, Vector3(0.0, 0.05, -7.0), 180.0)
		_slot(V).lo.helmet = true
		await _settle(0.6)
		await _do(S, {"op": "fire", "tool": Loadout.Tool.SIDEARM, "target": V, "height": 1.65, "shots": 1})
		await _settle(0.4)
		_check("a clean starter pistol headshot downs a full-health helmeted player", not _slot(V).alive)
		await _consistency("after helmeted headshot")
		net.restart_round()
		await _settle()

	# ---- 8. duplicate / stale commands and events
	if _want("forged"):
		var dup0 := int(net.metrics["dup_cmds"])
		var stale0 := int(net.metrics["stale_round_cmds"])
		var m0 := _slot(S).lo.mag
		var p0 := _slot(S).node.global_position
		await _do(S, {"op": "forge", "old_seq": true})
		_check("replayed old commands ignored", int(net.metrics["dup_cmds"]) - dup0 >= NetMatch.CMD_REDUNDANCY
			and _slot(S).lo.mag == m0 and _slot(S).node.global_position.distance_to(p0) < 0.05,
			"dups=%d mag %d->%d" % [int(net.metrics["dup_cmds"]) - dup0, m0, _slot(S).lo.mag])
		await _do(S, {"op": "forge", "old_round": true})
		_check("old-round commands consumed without effect", int(net.metrics["stale_round_cmds"]) - stale0 >= NetMatch.CMD_REDUNDANCY
			and _slot(S).lo.mag == m0 and _slot(S).node.global_position.distance_to(p0) < 0.05,
			"stale=%d mag %d->%d" % [int(net.metrics["stale_round_cmds"]) - stale0, m0, _slot(S).lo.mag])
		var inj := await _do(S, {"op": "inject_stale"})
		_check("client ignores duplicate/old-round events", int(inj.get("ignored", 0)) == 4 and bool(inj.get("unchanged", false))
			and bool(inj.get("alive", false)), str(inj))
		await _consistency("after forged commands/events")

	# ---- 9. repeated resets leave nothing behind
	if _want("resets"):
		var counts: Array = []
		for r in 3:
			net.restart_round()
			await _settle(0.8)
			_park([S])
			net.test_teleport(S, Vector3(0.4, 0.05, -5.4), -90.0)
			await _settle(0.4)
			await _do(S, {"op": "place", "tool": Loadout.Tool.ORDINARY_CHARGE, "point": Vector3(1.4, 1.2, -5.4)})
			await _do(S, {"op": "fire", "point": Vector3(-1.6, 1.5, -3.0), "shots": 6})
			await _settle(3.8)
			net.restart_round()
			await _settle(1.5)
			var reps := await _consistency("reset %d" % (r + 1))
			var row := {1: get_tree().get_node_count()}
			for id: int in reps:
				if id != 1 and reps[id] != null:
					row[id] = int(reps[id]["nodes"])
			counts.append(row)
		_check("node counts stable across resets (all processes)", counts[1] == counts[2], "%s" % [counts])
		var d := net.digest()
		var all_intact := true
		for w: String in d["walls"]:
			all_intact = all_intact and d["walls"][w][0] == WallModule.State.INTACT and d["walls"][w][1] == 0
		_check("after resets: walls intact rev 0, no charges, full health", all_intact and d["charges"] == 0
			and (d["hp"] as Dictionary).values().all(func(v: Array) -> bool: return v[0] == 100 and v[1]))
		results["node_counts_per_reset"] = counts

	# ---- 10. a client disconnects
	if _want("leave"):
		ids = _ids()
		var leaver: int = ids[ids.size() - 1]
		if leaver != S and ids.size() > 2:
			var before := net.slots.size()
			await _do(leaver, {"op": "quit"})
			await _settle(1.5)
			_check("host removed the leaver", net.slots.size() == before - 1 and not net.slots.has(leaver))
			var r2 := await _do(S, {"op": "report"})
			_check("other clients removed the leaver", not (r2["digest"]["hp"] as Dictionary).has(leaver)
				and int(r2["remotes"]) == net.slots.size() - 1, "remotes=%s" % r2.get("remotes"))
			_check("disconnect purges voice routing and playback", leaver not in r2["voice_roster"] and leaver not in r2["voice_speakers"])
			await _consistency("after disconnect")
	_finish()


func _finish() -> void:
	var a := NetworkManager.args
	var m := net.metrics
	var sim: PackedInt32Array = m["sim_us"]
	var secs := (Time.get_ticks_msec() - int(m["t0"])) / 1000.0
	var clients := {}
	var last_tag := ""
	for tag: String in _reports:
		last_tag = tag
	if last_tag != "":
		for id: int in _reports[last_tag]:
			var r: Variant = _reports[last_tag][id]
			if id != 1 and r != null:
				var rr: Dictionary = r
				clients[id] = {"rtt_mean_ms": rr["rtt_mean"], "rtt_p95_ms": rr["rtt_p95"], "corrections": rr["corrections"],
					"corr_max_m": rr["corr_max"], "corr_mean_m": rr["corr_mean"], "snaps": rr["snaps"],
					"stale_snaps": rr["stale_snaps"], "stale_events": rr["stale_events"], "sim_dropped": rr["rx_dropped_sim"],
					"up_Bps": rr["enet_tx"] / maxf(rr["secs"], 0.001), "down_Bps": rr["enet_rx"] / maxf(rr["secs"], 0.001)}
	var rw: PackedInt32Array = m["rewind"]
	var out := {
		"players": net.slots.size(), "build": NetworkManager.build_id, "date": Time.get_datetime_string_from_system(),
		"conditions": {"sim_latency_ms_one_way_each_side": float(a.get("sim-latency", 0)), "sim_jitter_ms": float(a.get("sim-jitter", 0)),
			"sim_loss": float(a.get("sim-loss", 0)), "transport": "ENet localhost, %s, one machine" % DisplayServer.get_name()},
		"host": {"sim_us_mean": _mean(sim), "sim_us_p95": _pct(sim, 0.95), "sim_us_p99": _pct(sim, 0.99),
			"sim_us_max": _pct(sim, 1.0), "ticks": sim.size(), "cmds": m["cmds"], "dup_cmds": m["dup_cmds"],
			"stale_round_cmds": m["stale_round_cmds"], "starved_slot_ticks": m["starved"], "budget_drops": m["budget_drops"],
			"rewind_ticks_mean": _mean(rw), "rewind_ticks_max": _pct(rw, 1.0),
			"up_Bps": m["enet_tx"] / secs, "down_Bps": m["enet_rx"] / secs, "secs": secs},
		"clients": clients, "results": results, "failures": _fails}
	var js := JSON.stringify(out, "  ")
	print("NET_RESULT ", JSON.stringify(out))
	if a.has("metrics-out"):
		var f := FileAccess.open(String(a["metrics-out"]), FileAccess.WRITE)
		if f:
			f.store_string(js)
			f.close()
	if _fails == 0:
		print("SMOKE_OK match players=%d" % net.slots.size())
	else:
		print("SMOKE_FAIL match failures=%d" % _fails)
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if _fails == 0 else 1)


## Actual socket routing tests. Synthetic audio bypasses microphone capture explicitly.
func _voice_checks() -> void:
	print("[Test] voice: proximity + simultaneous radio, theft, lifecycle and six-talker load")
	net.restart_round()
	await _settle()
	var enemy := -1
	var ally := -1
	for id: int in _ids():
		if id == 1:
			continue
		if _slot(id).team != _slot(1).team and enemy < 0:
			enemy = id
		elif _slot(id).team == _slot(1).team:
			ally = id
	_check("voice enemy available", enemy > 0)
	if enemy < 0:
		return
	for id: int in _ids():
		net.test_teleport(id, Vector3(26.0, -0.25, -6.0 - _slot(id).spawn * 0.8), 0)
	net.test_teleport(1, Vector3(0, 0.05, -1), 0)
	net.test_teleport(enemy, Vector3(0, 0.05, -3), 0)
	await _settle()
	net.voice.bot_radio(1, BotRadio.Kind.CONTACT, "a")
	await _settle(0.35)
	var chatter := await _voice_reports()
	_check("nearby enemy without a handset receives no bot radio", int(chatter[enemy].bot_radio) == 0)
	if ally > 0:
		_check("bot contact reaches a teammate's radio", int(chatter[ally].bot_radio) == 1)
	await _voice_clear_all()
	await _do(1, {"op": "voice_send", "radio": true})
	await _settle(0.5)
	var reports := await _voice_reports()
	_check("holding radio still sends proximity to nearby enemy", int(reports[enemy].received.get(1, 0)) >= 15, "peer=%d count=%s epoch=%s host_epoch=%s" % [enemy, reports[enemy].received.get(1, 0), reports[enemy].epoch, net.voice.epoch])
	results["voice_radio_recipient_counts"] = reports
	for id: int in reports:
		if id == 1 or id == enemy:
			continue
		if _slot(id).team == _slot(1).team:
			_check("radio reaches distant teammate %d" % id, int(reports[id].received.get(1, 0)) >= 15)
		else:
			_check("unauthorized distant enemy gets zero audio packets %d" % id, int(reports[id].received.get(1, 0)) == 0)
	await _voice_clear_all()
	await _do(1, {"op": "voice_send", "radio": false})
	await _settle(0.5)
	reports = await _voice_reports()
	if ally > 0:
		_check("distant teammate gets zero proximity-only packets", int(reports[ally].received.get(1, 0)) == 0)
	# Host kills an enemy: stationary pickup, no dead-to-living speech, atomic theft.
	net._on_player_hit(enemy, 100, 1)
	await _settle()
	_check("death drops exactly one radio", net.voice.pickups.size() == 1)
	var radio_id: int = net.voice.pickups.keys()[0]
	var radio_at: Vector3 = net.voice.pickups[radio_id].pos
	net._interact_host(1, net.round_id, NetMatch.Interact.RADIO, radio_id)
	_check("out-of-reach theft refused", not net.voice.stolen.has(1))
	net.test_teleport(1, radio_at + Vector3(0, -.06, 1.1), 0)
	await _settle()
	await _do(1, {"op": "voice_recover_radio", "point": radio_at})
	_check("host-authorized theft succeeds", net.voice.stolen.get(1, -1) == _slot(enemy).team and net.voice.pickups.is_empty())
	await _voice_clear_all()
	await _do(enemy, {"op": "voice_send", "radio": true})
	await _settle(0.5)
	reports = await _voice_reports()
	_check("dead speech never reaches living thief", int(reports[1].received.get(enemy, 0)) == 0)
	var other_enemy := -1
	for id: int in _ids():
		if id != enemy and _slot(id).team == _slot(enemy).team:
			other_enemy = id
	if other_enemy > 0:
		# Outside both proximity radii so these assertions isolate the intercepted radio path.
		net.test_teleport(other_enemy, Vector3(26.0, -0.25, -12.0), 0)
		await _settle()
		await _do(other_enemy, {"op": "voice_send", "radio": true})
		await _settle(0.5)
		reports = await _voice_reports()
		_check("stolen radio actually receives original team's remote packets", int(reports[1].received.get(other_enemy, 0)) >= 15)
		var heard := int(reports[1].bot_radio)
		net.voice.bot_radio(other_enemy, BotRadio.Kind.RESPONDING, "electrical")
		_check("stolen handset receives the bot's named-room reply", net.voice.bot_radio_received == heard + 1)
		await _do(1, {"op":"voice_mute_enemy"})
		net.voice.bot_radio(other_enemy, BotRadio.Kind.CONTACT, "b")
		_check("enemy-radio mute blocks bot chatter", net.voice.bot_radio_received == heard + 1)
		await _voice_clear_all()
		await _do(other_enemy, {"op":"voice_send", "radio":true})
		await _settle(.5)
		reports = await _voice_reports()
		_check("enemy-radio mute blocks intercepted playback", reports[1].muted_enemy and int(reports[1].received.get(other_enemy, 0)) == 0)
		await _do(1, {"op":"voice_mute_enemy"})
		await _voice_clear_all()
		await _do(other_enemy, {"op":"voice_send", "radio":true})
		await _settle(.5)
		reports = await _voice_reports()
		_check("unmuting restores interception", not reports[1].muted_enemy and int(reports[1].received.get(other_enemy, 0)) >= 15)
		await _voice_clear_all()
		await _do(1, {"op": "voice_send", "radio": true})
		await _settle(0.5)
		reports = await _voice_reports()
		_check("stolen radio cannot transmit to original channel", int(reports[other_enemy].received.get(1, 0)) == 0)
		if ally > 0:
			net.test_teleport(ally, Vector3(0, 0.05, -2.5), 0)
			await _settle()
			var ally_before := await _do(ally, {"op": "voice_report"})
			net.voice.bot_radio(other_enemy, BotRadio.Kind.SECURED, "b")
			await _settle(.35)
			var no_ear := await _do(ally, {"op": "voice_report"})
			_check("an ally cannot intercept just because a teammate took a handset",
				no_ear.stolen.is_empty() and no_ear.bot_radio == ally_before.bot_radio)
			net.voice._drop(_slot(other_enemy).team, _slot(ally).node.global_position)
			net.voice.sync_state()
			await _settle(.35)
			await _do(ally, {"op": "voice_recover_radio", "point": net.voice.pickups.values()[0].pos})
			await _settle(.35)
			net.voice.bot_radio(other_enemy, BotRadio.Kind.SECURED, "b")
			await _settle(.35)
			var has_ear := await _do(ally, {"op": "voice_report"})
			_check("an ally unlocks enemy chatter with their own handset",
				has_ear.stolen.get(ally, -1) == _slot(other_enemy).team and has_ear.bot_radio == ally_before.bot_radio + 1)
		net._on_player_hit(other_enemy, 100, 1)
		await _settle()
		await _voice_clear_all()
		await _do(enemy, {"op": "voice_send", "radio": false})
		await _settle(0.5)
		reports = await _voice_reports()
		_check("dead teammates hear each other on separate channel", int(reports[other_enemy].received.get(enemy, 0)) >= 15 and int(reports[1].received.get(enemy, 0)) == 0)
	var old_epoch := net.voice.epoch
	net.swap_sides()
	await _settle()
	reports = await _voice_reports()
	for id: int in reports:
		_check("side swap clears radio ownership and audio queues %d" % id, not reports[id].muted_enemy and reports[id].stolen.is_empty() and int(reports[id].pickups) == 0 and int(reports[id].speakers) == 0 and int(reports[id].epoch) > old_epoch)
	net.swap_sides() # restore original teams for combat scenarios
	await _settle()
	# Worst case: all six talkers nearby, all listeners authorized; actual ENet wire counters include gameplay.
	for id: int in _ids():
		net.test_teleport(id, Vector3(0, 0.05, -2.0 - _slot(id).spawn * 0.6), 0)
	await _settle()
	var before := int(net.metrics.enet_tx)
	var start_ms := Time.get_ticks_msec()
	var ops := {}
	for id: int in _ids():
		ops[id] = {"op": "voice_send", "radio": true, "chunks": 100}
	await _all(ops)
	var seconds := (Time.get_ticks_msec() - start_ms) / 1000.0
	results["voice_load"] = {"talkers": ops.size(), "host_wire_up_Bps_including_gameplay": (int(net.metrics.enet_tx) - before) / seconds,
		"seconds": seconds, "codec_bytes_per_20ms": 163, "queue_ms": 60, "actual_mouth_to_ear": "requires microphone/device test"}
	_check("voice remains bounded under simultaneous talkers", net.voice._speakers.size() <= 5 and net.voice._delayed.size() <= 128)
	var rejected0 := net.voice.rejected
	var pcm := PackedFloat32Array()
	pcm.resize(320)
	var data := VoiceAudio.Codec.encode(pcm)
	net.voice._route(1, net.round_id - 1, net.voice.epoch, 999999, true, data)
	net.voice._route(1, net.round_id, old_epoch, 999999, true, data)
	net.voice._route(999, net.round_id, net.voice.epoch, 999999, true, data)
	net.voice._route(1, net.round_id, net.voice.epoch, 999999, true, PackedByteArray([0]))
	_check("stale epoch/round, unregistered sender and malformed voice rejected", net.voice.rejected == rejected0 + 4)
	# Pings only go to living teammates; position is computed by the host, never supplied by a client.
	net.voice._action_host(1, net.round_id, 1)
	_check("nonverbal ping created", net.voice._pings.size() == 1)
	net.restart_round()
	await _settle()

func _voice_clear_all() -> void:
	var ops := {}
	for id: int in _ids():
		ops[id] = {"op": "voice_clear"}
	await _all(ops)

func _voice_reports() -> Dictionary:
	var ops := {}
	for id: int in _ids():
		ops[id] = {"op": "voice_report"}
	return await _all(ops)


func _voice_throttle() -> Dictionary:
	var out := {}
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and net.is_host:
		for id in multiplayer.get_peers():
			var p: ENetPacketPeer = peer.get_peer(id)
			out[id] = p.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)
	return out


# S7 integration: actual NetCmd holds + host world validation and real replication/reset paths.
func _round_checks() -> void:
	_prep_input_checks()
	var loop := net.loop
	var rules := loop.rules
	rules.tuning = rules.tuning.duplicate()
	rules.tuning.prep = 45.0 # first prep exercises shop, debug requests, movement and reinforcement
	rules.tuning.live = 40.0
	rules.tuning.plant = 0.3
	rules.tuning.defuse = 0.4
	rules.tuning.fuse = 4.0
	rules.tuning.resolution = 2.0
	var ids := _ids()
	var attacker := 1
	var defender := 0
	for id: int in ids:
		if _slot(id).team == 0 and id != 1:
			attacker = id
		if _slot(id).team == 1:
			defender = id
	await _do(1, {"op": "round_capture", "tag": "lobby"})
	var start_pos := _slot(attacker).node.global_position
	var mag := _slot(attacker).lo.mag
	await _do(attacker, {"op": "round_input", "move": Vector2(0, -1), "fire": true, "frames": 20})
	await _do(attacker, {"op": "round_input"})
	_check("lobby blocks movement and firing", Vector2(_slot(attacker).node.global_position.x - start_pos.x, _slot(attacker).node.global_position.z - start_pos.z).length() < 0.02 and _slot(attacker).lo.mag == mag, "pos=%s start=%s mag=%d" % [_slot(attacker).node.global_position, start_pos, _slot(attacker).lo.mag])
	var ops := {}
	for id: int in ids:
		ops[id] = {"op": "round_action", "action": "ready"}
	await _all(ops)
	_check("readiness begins the first prep", await _phase(RoundRules.Phase.PREP, 5.0))
	rules.tuning.prep = 0.4
	await _economy_checks(ids, attacker, defender)
	_check("prep ends and the round goes live", await _phase(RoundRules.Phase.LIVE, 8.0))
	await _post_live_economy(attacker, defender)
	_check("balanced teams have at most three players", _team_count(0) <= 3 and _team_count(1) <= 3)
	if NetworkManager.args.has("late-file"):
		var f := FileAccess.open(String(NetworkManager.args["late-file"]), FileAccess.WRITE)
		f.store_string("go")
		f.close()
		_check("late join connected during live round", await _wait_players(ids.size() + 1, 30.0))
		await _settle(0.6)
		for id: int in _ids():
			if id not in ids:
				var late_report := await _do(id, {"op": "round_report"})
				_check("mid-round join waits dead with teammate camera", not _slot(id).alive and not late_report.alive and String(late_report.camera) == "TeammateCamera")
				_check("late join receives no enemy player transforms", _only_teammates(late_report.view, int(late_report.team)))
				ids.append(id)
	# Transfer bomb to remote attacker through drop/recovery rather than changing client inventory.
	var original := rules.carrier
	net.test_teleport(original, Vector3(0, 0.05, -2), 0)
	await _settle(0.2)
	await _do(original, {"op": "round_input", "drop": true, "frames": 8})
	await _do(original, {"op": "round_input"})
	_check("B drops bomb on host", rules.carrier == 0)
	net.test_teleport(attacker, Vector3(0, 0.05, -2), 0)
	await _settle(0.2)
	await _do(attacker, {"op": "round_input", "hold": true, "frames": 20})
	await _do(attacker, {"op": "round_input"})
	_check("F recovers bomb through network command", rules.carrier == attacker)
	# Reject an out-of-site hold, then an interrupted valid plant.
	await _do(attacker, {"op": "round_input", "plant": true, "frames": 30})
	_check("host rejects planting outside sites", rules.phase == RoundRules.Phase.LIVE and rules.progress == 0)
	await _do(attacker, {"op": "round_input"})
	net.test_teleport(attacker, rules.tuning.sites[0], 0)
	await _settle(0.2)
	await _do(attacker, {"op": "round_input", "plant": true, "frames": 4})
	await _do(attacker, {"op": "round_input"})
	await _settle(0.2)
	_check("release interrupts authoritative plant progress", rules.phase == RoundRules.Phase.LIVE and rules.progress == 0)
	# Site eligibility uses host position. Attempting from the wrong side of a wall can't defuse.
	await _do(attacker, {"op": "round_input", "plant": true, "frames": 36})
	await _do(attacker, {"op": "round_input"})
	_check("slot-5 bomb with held fire plants at A", rules.phase == RoundRules.Phase.PLANTED and rules.site == 0)
	await _do(attacker, {"op": "round_capture", "tag": "planted"})
	# Dead clients must lose enemy transforms, including the full join state and voice roster positions.
	if attacker != 1:
		var old_snapshot := net._snapshot(attacker)
		net._on_player_hit(attacker, 1000.0, defender)
		await _settle(0.3)
		var replayed := await _do(attacker, {"op": "round_old_snapshot", "snapshot": old_snapshot})
		_check("pre-death snapshot cannot revive a dead client", not replayed.alive)
		var dead := await _do(attacker, {"op": "round_report"})
		_check("death selects teammate camera and removes enemy transforms", not dead.alive and String(dead.camera) == "TeammateCamera" and _only_teammates(dead.view, int(dead.team)))
		var safe := true
		for id: int in dead.voice_people:
			if int(dead.voice_people[id].team) != int(dead.team):
				safe = safe and dead.voice_people[id].pos == Vector3.ZERO
		_check("dead voice roster contains no enemy position", safe)
		_check("planted round continues after carrier dies", rules.phase == RoundRules.Phase.PLANTED)
		await _do(attacker, {"op": "round_capture", "tag": "spectator"})
		for id: int in ids:
			var member := _slot(id)
			if member.alive and member.team == rules.attack_team:
				net._on_player_hit(id, 1000.0, id)
		await _settle(0.25)
		var bomb_view := await _do(attacker, {"op": "round_report"})
		_check("last attacker dies and the spectator camera watches the bomb", int(bomb_view.watching) == 0
			and Vector3(bomb_view.viewpoint).distance_to(rules.bomb_pos) < 3.0)
	net.test_teleport(defender, rules.tuning.sites[0] + Vector3(0.5, 0, 0), 0)
	await _settle(0.2)
	await _do(defender, {"op": "round_input", "hold": true, "frames": 66})
	await _do(defender, {"op": "round_input"})
	_check("network defender hold defuses and awards once", rules.reason == "Bomb defused" and rules.scores == [0, 1] and rules.awards == 1, "phase=%d reason=%s progress=%d" % [rules.phase, rules.reason, rules.progress])
	var stale := loop.state().duplicate(true)
	_check("next round starts automatically", await _phase(RoundRules.Phase.PREP, 3.0) or rules.round_number == 2)
	await _settle(0.3)
	var reset_ok := true
	for id: int in ids:
		reset_ok = reset_ok and _slot(id).alive and _slot(id).health == 100.0 and _slot(id).lo.mag == _slot(id).lo.tuning.mag_size
	for wall: WallModule in g.modules:
		reset_ok = reset_ok and wall.state == WallModule.State.INTACT and wall.revision == 0
	var econ := loop_econ()
	var t := econ.tuning
	# The defender also earns in-round income (kill/damage/reinforcing) and the survival bonus; exact amounts are
	# covered by the economy unit tests. The attacker died, so its pay is exactly loss base + plant bonus.
	_check("round income: winners paid, losers get base + plant bonus, once", econ.wallet(defender) >= _spent[defender] + (t.win_reward + t.survive_bonus) * 2 / 5
		and econ.wallet(attacker) == _spent[attacker] + (t.loss_base + t.plant_bonus) * 2 / 5,
		"def %d vs %d, atk %d vs %d" % [econ.wallet(defender), _spent[defender] + t.win_reward * 2 / 5, econ.wallet(attacker), _spent[attacker] + (t.loss_base + t.plant_bonus) * 2 / 5])
	_check("equipment resets to baseline, credits carry over", _slot(attacker).lo.charges[Loadout.Tool.ORDINARY_CHARGE] == t.base_ordinary
		and _slot(attacker).lo.charges[Loadout.Tool.HEAVY_CHARGE] == 0 and _slot(defender).lo.charges[Loadout.Tool.REINFORCE] == t.base_reinforce * t.reinforce_per_kit)
	_check("reinforcement is undone at round reset", g._mod("Divider_C_ordinary").material == WallModule.Mat.ORDINARY and econ.reinforced == [0, 0])
	await _settle(0.4)
	_check("clients see income and carried credits", await _wallet_matches(attacker) and await _wallet_matches(defender))
	_check("round reset restores all peers, walls, tools and radio inventory", reset_ok and net.voice.stolen.is_empty() and net.voice.pickups.is_empty() and rules.actor == 0)
	for id: int in ids:
		if id != 1:
			var replay := await _do(id, {"op": "round_stale", "state": stale})
			_check("stale loop state rejected by client", replay.unchanged)
	# Finish the remaining rounds until the winning team clinches deterministically via real host timeout, explosion and elimination paths.
	for number in range(2, 9):
		_check("round %d becomes live" % number, await _phase(RoundRules.Phase.LIVE, 3.0))
		_check("round %d role swap" % number, rules.attack_team == (1 if number > 6 else 0))
		if number == 7:
			var fresh := true
			for id: int in ids:
				fresh = fresh and loop_econ().wallet(id) == loop_econ().tuning.start_credits
			_check("side swap resets credits", fresh)
		if number == 2:
			# Destroy a wall and hold inventory to prove the next reset cleans them.
			g._mod("Divider_C_ordinary").breach(WallModule.Kind.ORDINARY)
			var carrier := rules.carrier
			net.test_teleport(carrier, rules.tuning.sites[1], 0)
			await _settle(0.2)
			await _do(carrier, {"op": "round_input", "plant": true, "frames": 36})
			await _do(carrier, {"op": "round_input"})
			_check("slot-5 bomb with held fire plants at B", rules.phase == RoundRules.Phase.PLANTED and rules.site == 1)
			var outside := defender
			net.test_teleport(outside, Vector3(26, -0.25, -6), 0)
			await _settle(.35)
			var viewer := await _do(outside, {"op": "round_report"})
			if int(viewer.team) != rules.attack_team:
				_check("far defender learns the bomb is planted without its site or coordinates",
					int(viewer.state.rules.phase) == RoundRules.Phase.PLANTED and int(viewer.state.rules.site) == -1 and viewer.state.rules.bomb_pos == Vector3.ZERO)
			var doomed := _slot(carrier)
			doomed.lo.set_gear("carbine", Weapons.DEFAULT_SIDEARM)
			doomed.lo.select(Loadout.Tool.RIFLE)
			doomed.lo.mag = 9
			doomed.lo.reserve = 21
			_check("bomb explosion resolves round", await _phase(RoundRules.Phase.RESOLUTION, 6.0) and rules.reason == "Bomb exploded")
			_check("the blast kills the nearby planter and spares a player outside 10 m", not doomed.alive and _slot(outside).alive)
			_check("blast deaths leave both guns with their current ammo", net.weapon_drops.drops.values().any(
				func(drop: Dictionary) -> bool: return drop.get("gun") == "carbine" and drop.ammo == [9, 21]))
		elif number <= 6:
			rules.deadline = net.tick + 5
			_check("preplant timeout resolves round", await _phase(RoundRules.Phase.RESOLUTION, 2.0) and rules.reason == "Time expired")
		else:
			for id: int in ids:
				if _slot(id).team != rules.attack_team:
					net._on_player_hit(id, 1000.0, rules.carrier)
			_check("team elimination resolves round", await _phase(RoundRules.Phase.RESOLUTION, 2.0) and rules.reason == "Defenders eliminated")
		if number < 8:
			await _phase(RoundRules.Phase.PREP, 2.0)
	_check("complete match clinches at seven wins", await _phase(RoundRules.Phase.RESULT, 3.0) and rules.awards == 8 and rules.scores == [1, 7])
	var client: int = ids[1]
	await _do(client, {"op": "round_capture", "tag": "result"})
	var final_report := await _do(client, {"op": "round_report"})
	_check("client receives authoritative round MVP", final_report.state.mvp == net.loop.round_mvp and not net.loop.round_mvp.is_empty())
	_check("client sees authoritative final score and result", final_report.state.rules.scores == rules.scores and int(final_report.state.rules.phase) == RoundRules.Phase.RESULT)
	await _do(client, {"op": "round_action", "action": "rematch"})
	await _settle(0.2)
	_check("client cannot force rematch", rules.phase == RoundRules.Phase.RESULT)
	loop.request("rematch")
	await _settle(0.3)
	_check("host rematch returns everyone to unready lobby", rules.phase == RoundRules.Phase.LOBBY and rules.scores == [0, 0] and rules.ready.is_empty())
	ops.clear()
	for id: int in ids:
		ops[id] = {"op": "round_action", "action": "ready"}
	await _all(ops)
	_check("rematch starts without reloading editor", await _phase(RoundRules.Phase.LIVE, 5.0) and rules.round_number == 1)
	var rematch_fresh := true
	for id: int in ids:
		rematch_fresh = rematch_fresh and loop_econ().wallet(id) == loop_econ().tuning.start_credits
	_check("rematch resets credits", rematch_fresh)
	var rejoined := await _do(client, {"op": "round_rejoin", "target": 1})
	_check("returning peer ID resumes snapshot updates", rejoined.restored)
	var looter := client
	var donor_slot := net.spawn_bot(1900000002, "Drop fixture", _slot(looter).team)
	donor_slot.alive = true
	donor_slot.health = NetMatch.MAX_HEALTH
	var donor := donor_slot.id
	donor_slot.lo.defuse_kit = true
	donor_slot.lo.charges[Loadout.Tool.FLASH] = 3
	var ground := Vector3(0, 0.05, -2.0)
	_slot(donor).lo.set_gear("carbine", Weapons.DEFAULT_SIDEARM)
	_slot(donor).lo.select(Loadout.Tool.RIFLE)
	_slot(donor).lo.mag = 8
	_slot(donor).lo.reserve = 17
	net.test_teleport(donor, ground, 0)
	net._on_player_hit(donor, 1000.0, donor)
	net.test_teleport(looter, ground + Vector3(0, 0, 1.2), 0)
	await _settle(.35)
	var rifle_id := 0
	for id: int in net.weapon_drops.drops:
		if net.weapon_drops.drops[id].get("gun") == "carbine":
			rifle_id = id
	_check("client sees the authoritative dropped rifle", rifle_id != 0 and rifle_id in (await _do(looter, {"op": "loot_report"})).drops)
	if rifle_id != 0:
		await _do(looter, {"op": "loot_take", "drop_id": rifle_id})
		await _settle(.45)
		var picked_up := await _do(looter, {"op": "loot_report"})
		_check("weapon pickup consumes the drop once and syncs exact ammo to its new owner",
			rifle_id not in picked_up.drops and picked_up.primary == "carbine" and picked_up.ammo == [8, 17], str(picked_up))
	var utility_id := 0
	var kit_id := 0
	for id: int in net.weapon_drops.drops:
		var item: String = net.weapon_drops.drops[id].get("item", "")
		if item == "defuse_kit":
			kit_id = id
		elif item == "flash":
			utility_id = id
	_check("death drops carried grenades and the defuse kit", utility_id != 0 and kit_id != 0
		and net.weapon_drops.drops[utility_id].count == 3)
	if utility_id != 0 and kit_id != 0:
		var walking_attacker := 1
		for id: int in _ids():
			if _slot(id).team == rules.attack_team:
				walking_attacker = id
				break
		var walking_defender := defender
		var fla: Vector3 = net.weapon_drops.drops[utility_id].pos
		var kit: Vector3 = net.weapon_drops.drops[kit_id].pos
		_slot(walking_attacker).lo.charges[Loadout.Tool.FLASH] = 2
		_slot(walking_defender).lo.defuse_kit = true
		net.test_teleport(walking_attacker, fla, 0)
		await _settle(.35)
		var utilities := await _do(walking_attacker, {"op": "loot_report"})
		_check("walking over utility fills that type to three and leaves excess on the ground",
			utilities.flash == 3 and net.weapon_drops.drops.get(utility_id, {}).get("count") == 2)
		net.test_teleport(walking_attacker, kit, 0)
		await _settle(.2)
		_check("an attacker cannot auto-pick up a defuse kit", net.weapon_drops.drops.has(kit_id))
		net.test_teleport(walking_defender, kit, 0)
		await _settle(.2)
		_check("a defender already carrying a kit leaves the spare", net.weapon_drops.drops.has(kit_id))
		_slot(walking_defender).lo.defuse_kit = false
		await _settle(.3)
		var equipped := await _do(walking_defender, {"op": "loot_report"})
		_check("walking over a kit equips an eligible defender and syncs to the client",
			not net.weapon_drops.drops.has(kit_id) and equipped.kit)
	var takeover_peer := attacker if attacker != 1 else client
	var replacement := net.spawn_bot(1900000001, "Test replacement", _slot(takeover_peer).team)
	replacement.alive = true
	replacement.health = 53.0
	replacement.lo.defuse_kit = true
	replacement.lo.mag = 8
	net.test_teleport(replacement.id, g.spawn_at(replacement.spawn)[0], 90.0)
	net._on_player_hit(takeover_peer, 1000.0, takeover_peer)
	await _settle(.25)
	var before_takeover := await _do(takeover_peer, {"op": "round_report"})
	await _do(takeover_peer, {"op": "round_action", "action": "take_over:%d" % replacement.id})
	await _settle(.45)
	var after_takeover := await _do(takeover_peer, {"op": "round_report"})
	_check("dead client follows a living allied bot", int(before_takeover.watching) != 0 and not before_takeover.alive)
	_check("bot takeover transfers live state and equipment over LAN", after_takeover.alive and after_takeover.kit
		and int(after_takeover.mag) == 8 and int(after_takeover.health) == 53 and not replacement.alive)
	net._on_player_hit(takeover_peer, 1000.0, takeover_peer)
	_check("a second takeover in the round is rejected", not net.take_over_bot(takeover_peer, replacement.id))
	net._on_peer_left(replacement.id, false)
	# Live carrier disconnect drops the bomb before slot deletion, then peers see the departure.
	var leaver := 0
	for id: int in ids:
		if id != 1 and _slot(id).team == rules.attack_team:
			leaver = id
	if leaver != 0:
		var carrier := rules.carrier
		rules.drop(carrier, _slot(carrier).node.global_position)
		rules.carrier = leaver
		await _do(leaver, {"op": "quit"})
		await _settle(0.5)
		_check("carrier disconnect removes peer and drops bomb", not net.slots.has(leaver) and rules.carrier == 0)
	results["rounds"] = {"full_match": true, "rematch": true, "players": ids.size(), "failures": _fails}


var _spent := {}

func _wallet_matches(id: int) -> bool:
	var report := await _do(id, {"op": "round_report"})
	var s := _slot(id)
	return int(report.credits) == loop_econ().wallet(id) and report.kits == s.lo.charges[Loadout.Tool.REINFORCE]


func loop_econ() -> Economy:
	return net.loop.econ


## Shop over real RPCs during the first prep: atomic purchases, limits, role gating, replayed/stale requests.
func _economy_checks(ids: Array, attacker: int, defender: int) -> void:
	var econ := loop_econ()
	var t := econ.tuning
	var a := _slot(attacker)
	var d := _slot(defender)
	_check("baseline loadout: attacker rifle + starter charge, defender starter kit", a.lo.charges[Loadout.Tool.ORDINARY_CHARGE] == t.base_ordinary
		and a.lo.charges[Loadout.Tool.HEAVY_CHARGE] == 0 and d.lo.charges[Loadout.Tool.REINFORCE] == t.base_reinforce * t.reinforce_per_kit
		and d.lo.charges[Loadout.Tool.ORDINARY_CHARGE] == 0 and a.lo.mag == a.lo.tuning.mag_size)
	_check("everyone starts with the same credits", econ.wallet(attacker) == t.start_credits and econ.wallet(defender) == t.start_credits)
	econ.credits[attacker] = 3000 # enough to reach the carry limits
	var funds: int = econ.wallet(attacker)
	await _do(attacker, {"op": "round_buy", "item": "ordinary"})
	await _do(attacker, {"op": "round_buy", "item": "ordinary"})
	await _do(attacker, {"op": "round_buy", "item": "ordinary"}) # over the carry limit
	await _do(attacker, {"op": "round_buy", "item": "heavy"})
	await _do(attacker, {"op": "round_buy", "item": "heavy", "replay": true}) # replayed request id
	await _do(attacker, {"op": "round_buy_raw", "item": "kit"}) # wrong role
	await _do(attacker, {"op": "round_buy_raw", "item": "bogus"}) # invalid id
	_check("attacker purchases are exact, limited and idempotent", a.lo.charges[Loadout.Tool.ORDINARY_CHARGE] == ShopCatalog.UTILITY_LIMIT
		and a.lo.charges[Loadout.Tool.HEAVY_CHARGE] == 1 and a.lo.charges[Loadout.Tool.REINFORCE] == 0
		and econ.wallet(attacker) == funds - (ShopCatalog.UTILITY_LIMIT - t.base_ordinary) * t.price_ordinary - t.price_heavy,
		"credits=%d ord=%d heavy=%d" % [econ.wallet(attacker), a.lo.charges[Loadout.Tool.ORDINARY_CHARGE], a.lo.charges[Loadout.Tool.HEAVY_CHARGE]])
	var recipient := 0
	for other: int in ids:
		if other != attacker and _slot(other).team == a.team:
			recipient = other
			break
	if recipient != 0:
		var buyer_funds := econ.wallet(attacker)
		var target_funds := econ.wallet(recipient)
		var target := _slot(recipient)
		await _do(attacker, {"op": "round_buy", "item": "smg", "recipient": recipient})
		await _do(attacker, {"op": "round_buy", "item": "smg", "recipient": recipient, "replay": true})
		_check("gift equips the teammate's weapon once and only the buyer pays",
			target.lo.primary == "smg" and a.lo.primary != "smg" and econ.wallet(recipient) == target_funds
			and econ.wallet(attacker) == buyer_funds - econ.price("smg"))
		for i in 4:
			await _do(attacker, {"op": "round_buy", "item": "flash", "recipient": recipient})
		await _do(attacker, {"op": "round_buy", "item": "smoke", "recipient": recipient})
		await _settle(.3)
		var kit := await _do(recipient, {"op": "loot_report"})
		_check("teammate gear uses its own per-item carry limit and syncs to its owner",
			kit.flash == 3 and kit.smoke == 1 and ShopCatalog.owned(a.lo, "flash") == 0
			and econ.wallet(attacker) == buyer_funds - econ.price("smg") - 3 * econ.price("flash") - econ.price("smoke"))
		var remaining := econ.wallet(attacker)
		await _do(attacker, {"op": "round_buy_raw", "item": "medkit", "recipient": defender})
		_check("gifting to an opponent leaves both inventories and the buyer's wallet unchanged",
			econ.wallet(attacker) == remaining and ShopCatalog.owned(d.lo, "medkit") == 0)
	_spent[attacker] = econ.wallet(attacker)
	await _do(defender, {"op": "round_buy", "item": "kit"})
	await _do(defender, {"op": "round_buy", "item": "kit"}) # no kit limit: a second kit also works
	await _do(defender, {"op": "round_buy_raw", "item": "heavy"}) # attackers' tool
	await _do(defender, {"op": "round_buy_raw", "item": "kit", "round_back": 1}) # stale round
	_check("defender buys two kits (5 each, no limit); role and stale-round requests fail", d.lo.charges[Loadout.Tool.REINFORCE] == (t.base_reinforce + 2) * t.reinforce_per_kit
		and d.lo.charges[Loadout.Tool.HEAVY_CHARGE] == 0 and econ.wallet(defender) == t.start_credits - 2 * t.price_reinforce,
		"credits=%d kits=%d" % [econ.wallet(defender), d.lo.charges[Loadout.Tool.REINFORCE]])
	_spent[defender] = econ.wallet(defender)
	await _settle(0.4)
	_check("each buyer's private wallet and kit count reach its client", await _wallet_matches(attacker) and await _wallet_matches(defender))
	net.loop.menu.open()
	await _settle(0.4)
	var menu_ok := net.loop.menu.is_open and net.loop.menu._cols.size() == ShopCatalog.CATEGORIES.size()
	var rifle_btn: Button = null
	for e: Dictionary in net.loop.menu._cols[3]:
		if e.id == "service_rifle":
			rifle_btn = e.button
	menu_ok = menu_ok and rifle_btn != null and rifle_btn.text.contains("$%d" % ShopCatalog.price(t, "service_rifle"))
	net.loop.menu.close()
	_check("buy menu opens in prep and lists catalog prices", menu_ok)
	_check("credits are never negative anywhere", econ.credits.values().all(func(c: int) -> bool: return c >= 0))

	# The real remote commands must allow defender prep movement while freezing attackers.
	net.test_teleport(defender, Vector3(5, .05, -5), 0)
	net.test_teleport(attacker, Vector3(0, .05, -2), 0)
	await _settle(.3)
	var dp := d.node.global_position
	var ap := a.node.global_position
	var dm := d.lo.mag
	await _do(defender, {"op": "round_input", "move": Vector2(0, -1), "fire": true, "frames": 20})
	await _do(defender, {"op": "round_input"})
	await _do(attacker, {"op": "round_input", "move": Vector2(0, -1), "fire": true, "frames": 20})
	await _do(attacker, {"op": "round_input"})
	await _settle(.3)
	_check("defender moves during prep; firing stays locked", d.node.global_position.distance_to(dp) > .3 and d.lo.mag == dm)
	_check("attacker remains frozen during prep", a.node.global_position.distance_to(ap) < .03)
	await _debug_money_checks(attacker)
	# Defender reinforces Divider_C by holding the kit; the host owns the result and every peer agrees.
	net.test_teleport(defender, Vector3(0.4, 0.05, -5.6), -90.0)
	await _settle(0.5)
	await _do(defender, {"op": "hold_tool", "tool": Loadout.Tool.REINFORCE, "point": Vector3(1.4, 1.2, -5.6), "frames": 190})
	await _settle(0.5)
	var wc: WallModule = g._mod("Divider_C_ordinary")
	_check("held kit reinforces the ordinary panel (host)", wc.material == WallModule.Mat.REINFORCED and wc.revision == 1
		and _slot(defender).lo.charges[Loadout.Tool.REINFORCE] == (t.base_reinforce + 2) * t.reinforce_per_kit - 1 and loop_econ().reinforced[_slot(defender).team] == 1,
		"mat=%d rev=%d kits=%d" % [wc.material, wc.revision, _slot(defender).lo.charges[Loadout.Tool.REINFORCE]])
	var rep := await _do(attacker, {"op": "round_report"})
	_check("attacker's client sees the reinforced panel stop rounds", float(rep.pen) == 0.0)
	await _consistency("panel reinforced")

	_check("reinforcement completes before LIVE", net.loop.rules.phase == RoundRules.Phase.PREP)
	net.loop.rules.deadline = net.tick + 12


func _post_live_economy(attacker: int, defender: int) -> void:
	var wc: WallModule = g._mod("Divider_C_ordinary")
	var econ := loop_econ()
	var before := econ.wallet(defender)
	net.loop.debug_money = true
	net.loop.sync()
	await _do(defender, {"op": "round_action", "action": "debug_money_fill"})
	await _settle(.35)
	_check("debug fill cannot bypass the closed LIVE shop", econ.wallet(defender) == before)
	net.loop.debug_money = false
	net.loop.sync()
	await _do(defender, {"op": "round_buy", "item": "kit"})
	_check("shop is closed once the round is live", econ.wallet(defender) == before and _slot(defender).lo.charges[Loadout.Tool.REINFORCE] == (econ.tuning.base_reinforce + 2) * econ.tuning.reinforce_per_kit - 1)
	# Attacker: ordinary charge is refused on it; the heavy charge opens it after its longer fuse.
	net.test_teleport(attacker, Vector3(0.4, 0.05, -5.4), -90.0)
	await _settle(0.5)
	var ord0: int = _slot(attacker).lo.charges[Loadout.Tool.ORDINARY_CHARGE]
	await _do(attacker, {"op": "place", "tool": Loadout.Tool.ORDINARY_CHARGE, "point": Vector3(1.4, 1.2, -5.4)})
	await _settle(0.4)
	_check("ordinary charge refused on reinforced panel", _slot(attacker).lo.charges[Loadout.Tool.ORDINARY_CHARGE] == ord0
		and wc.state == WallModule.State.INTACT and net.digest()["charges"] == 0)
	await _do(attacker, {"op": "place", "tool": Loadout.Tool.HEAVY_CHARGE, "point": Vector3(1.4, 1.2, -5.4)})
	await _settle(0.4)
	_check("heavy charge armed on reinforced panel", net.digest()["charges"] == 1 and _slot(attacker).lo.charges[Loadout.Tool.HEAVY_CHARGE] == 0)
	await _settle(5.0)
	_check("heavy charge breaches reinforced panel (revision 2)", wc.state == WallModule.State.BREACHED and wc.revision == 2)
	await _consistency("reinforced panel breached")


func _debug_money_checks(client: int) -> void:
	var loop := net.loop
	var before := loop.econ.wallet(client)
	await _do(client, {"op": "round_action", "action": "debug_money_fill"})
	await _settle(.35)
	_check("debug fill is off by default", not loop.debug_money and loop.econ.wallet(client) == before)
	await _do(client, {"op": "round_action", "action": "debug_money_toggle"})
	await _settle(.35)
	_check("client cannot enable debug money", not loop.debug_money)
	loop.request("debug_money_toggle")
	await _settle(.35)
	var report := await _do(client, {"op": "round_report"})
	_check("host debug option replicates to clients", loop.debug_money and bool(report.state.debug_money))
	await _do(client, {"op": "round_action", "action": "debug_money_fill", "round_back": 1})
	await _settle(.35)
	_check("stale debug request cannot change wallet", loop.econ.wallet(client) == before)
	await _do(client, {"op": "round_action", "action": "debug_money_fill"})
	await _settle(.35)
	_check("debug fill is host-owned, capped and privately synced", loop.econ.wallet(client) == loop.econ.tuning.credit_cap and await _wallet_matches(client))
	loop.request("debug_money_toggle")
	await _settle(.35)
	loop.econ.credits[client] = before # restore economic expectations for the full match
	loop.sync()
	await _do(client, {"op": "round_action", "action": "debug_money_fill"})
	await _settle(.35)
	_check("host disabling debug money rejects further fills", not loop.debug_money and loop.econ.wallet(client) == before)


func _phase(want: int, timeout: float) -> bool:
	var end := net.tick + int(timeout * 60)
	while net.tick < end:
		if net.loop.rules.phase == want:
			return true
		await get_tree().physics_frame
	return net.loop.rules.phase == want


func _team_count(team: int) -> int:
	var n := 0
	for s: NetMatch.Slot in net.slots.values():
		if s.team == team:
			n += 1
	return n


func _only_teammates(view: Dictionary, team: int) -> bool:
	for id: int in view:
		if int(view[id].team) != team:
			return false
	return true


func _gadget_checks(shooter: int) -> void:
	print("[Test] grenade and gadget replication")
	_check("radial falloff clamps at range", GadgetSystem.falloff(0, 6) == 1.0 and GadgetSystem.falloff(6, 6) == 0.0 and GadgetSystem.falloff(9, 6) == 0.0)
	_check("flash facing and NVG change exposure", GadgetSystem.blindness(4, 1, false) > GadgetSystem.blindness(4, -1, false) and GadgetSystem.blindness(4, 1, true) > GadgetSystem.blindness(4, 1, false))
	for t in range(10):
		var cmd := NetCmd.new()
		cmd.tool = t
		cmd.gadgets = 7
		cmd.interact = true
		cmd.drop_bomb = true
		var decoded := cmd.quantised()
		_check("tool %d wire round trip" % t, decoded.tool == t and decoded.gadgets == 7 and decoded.interact and decoded.drop_bomb)

	net.restart_round()
	await _settle()
	var lo: Loadout = net.slots[shooter].lo
	var panel: WallModule = g._mod("Divider_B_reinforced")
	var center: Vector3 = panel.global_position
	_check("reinforced panel blocks blast and flash", g.gadgets.transmission(center + Vector3.LEFT, center + Vector3.RIGHT, true) == 0.0 and g.gadgets.transmission(center + Vector3.LEFT, center + Vector3.RIGHT) == 0.0)
	ShopCatalog.grant(lo, "smoke")
	ShopCatalog.grant(lo, "flashlight")
	await _settle()
	var d := await _do(shooter, {"op": "gadget_digest"})
	_check("gadget purchase inventory replicated", int(d.owned) == 1 and int(d.smoke) == 1)
	await _do(shooter, {"op": "grenade_throw", "tool": Loadout.Tool.SMOKE})
	_check("host spends exactly one grenade", int(lo.charges[Loadout.Tool.SMOKE]) == 0)
	await _settle(.4)
	d = await _do(shooter, {"op": "gadget_digest"})
	_check("host projectile replicated", int(d.projectiles) == 1)
	await _settle(3.0)
	d = await _do(shooter, {"op": "gadget_digest"})
	_check("smoke detonation replicated", int(d.projectiles) == 0 and int(d.zones) == 1)
	_check("late full state includes active zone", net._full_state(shooter).gadgets.z.size() == 1)
	var slot: NetMatch.Slot = net.slots[shooter]
	slot.alive = false
	var enemy: int = 0
	for candidate: NetMatch.Slot in net.slots.values():
		if candidate.alive and candidate.team != slot.team:
			enemy = candidate.id
			break
	var enemy_zone: Dictionary = g.gadgets.zones[0].duplicate()
	enemy_zone.id = 999
	enemy_zone.owner = enemy
	g.gadgets.zones.append(enemy_zone)
	var private_state: Dictionary = g.gadgets.state(shooter)
	g.gadgets.zones.pop_back()
	var allies_only: bool = private_state.kit.all(func(row: Array) -> bool: return net.slots[int(row[0])].team == slot.team)
	_check("dead viewer receives allied smoke and equipment while enemy effects and positions stay private",
		enemy != 0 and allies_only and private_state.flash == 0.0 and private_state.z.size() == 1
		and int(private_state.z[0].owner) == shooter)
	slot.alive = true
	var old_enabled := net.loop.enabled
	var old_phase := net.loop.rules.phase
	net.loop.enabled = true
	net.loop.rules.phase = RoundRules.Phase.PREP
	_check("throws rejected during prep", not g.gadgets.throw_grenade(lo))
	net.loop.enabled = old_enabled
	net.loop.rules.phase = old_phase
	var flash_pos: Vector3 = slot.node.camera.global_position - slot.node.camera.global_basis.z * 2.0
	g.gadgets._detonate({"id": 998, "kind": "flash", "owner": 1, "pos": flash_pos})
	await _settle(.4)
	d = await _do(shooter, {"op": "gadget_digest"})
	_check("private flash reaches the victim", float(d.flash) > .1)
	var hp_before_fire: float = net.slots[1].health
	g.gadgets._detonate({"id": 997, "kind": "incendiary", "owner": shooter, "pos": g.player.global_position + Vector3.UP * .1})
	await _settle(.5)
	_check("fire zone deals host damage over time", net.slots[1].health < hp_before_fire)
	var before: float = net.slots[1].health
	g.gadgets._detonate({"id": 999, "kind": "frag", "owner": shooter, "pos": g.player.camera.global_position})
	_check("frag applies host radial damage", net.slots[1].health < before)
	net.restart_round()
	await _settle()
	d = await _do(shooter, {"op": "gadget_digest"})
	_check("round reset clears gadgets and effects", d.projectiles == 0 and d.zones == 0 and d.owned == 0 and d.smoke == 0)


func _prep_input_checks() -> void:
	var loop := net.loop
	var old_phase := loop.rules.phase
	var old_team := loop.rules.attack_team
	loop.rules.phase = RoundRules.Phase.PREP
	loop.rules.attack_team = 0
	for team in [0, 1]:
		for alive in [false, true]:
			for tool in range(10):
				var cmd := NetCmd.new()
				cmd.tool = tool
				cmd.move = Vector2(0, -1)
				cmd.fire = true
				cmd.reload = true
				cmd.slow_walk = true
				cmd.crouch = true
				loop.constrain(cmd, alive, team)
				var prep: bool = team == 1 and alive
				_check("prep input role=%d alive=%s tool=%d" % [team, alive, tool],
					(cmd.move != Vector2.ZERO) == prep and cmd.slow_walk == prep and cmd.crouch == prep
					and cmd.fire == (prep and tool == Loadout.Tool.REINFORCE) and not cmd.reload)
	loop.rules.attack_team = 1
	var swapped := NetCmd.new()
	swapped.move = Vector2.ONE
	swapped.fire = true
	swapped.tool = Loadout.Tool.REINFORCE
	loop.constrain(swapped, true, 0)
	_check("defender prep permission follows role swap", swapped.move == Vector2.ONE and swapped.fire)
	loop.rules.phase = RoundRules.Phase.RESOLUTION
	loop.constrain(swapped, true, 0)
	_check("resolution locks defender movement and kits", swapped.move == Vector2.ZERO and not swapped.fire)
	loop.rules.phase = old_phase
	loop.rules.attack_team = old_team


func _controls_checks(shooter: int) -> void:
	net.restart_round()
	_park([shooter])
	net.test_teleport(shooter, Vector3(0.0, 0.05, -4.0), 0.0)
	await _settle()
	var report := await _do(shooter, {"op": "controls_input", "lean": 1, "frames": 45})
	await _settle(0.5)
	var slot := _slot(shooter)
	_check("networked lean agrees with owner and host", float(report.lean) > 0.99 and slot.node.lean > 0.99)
	var others := _ids()
	others.erase(1)
	others.erase(shooter)
	if not others.is_empty():
		var remote := await _do(others[0], {"op": "controls_remote", "target": shooter})
		_check("observer interpolates visible lean", float(remote.lean) > 0.99 and float(remote.roll) < -0.1)
	var volume := {}
	for v: Dictionary in net._volumes_for(1):
		if int(v.id) == shooter:
			volume = v
	_check("leaned head participates in authoritative hit volume", not volume.is_empty() and (volume.b as Vector3).x > slot.node.global_position.x + 0.37)
	_check("lag compensation records leaned head offset", (slot.history.back()[4] as Vector3).length() > 0.37)
	slot.lo.use_recoil = true
	await _do(shooter, {"op": "controls_input", "lean": -1, "fire": true, "recoil": true, "frames": 65})
	report = await _do(shooter, {"op": "controls_input", "lean": -1, "frames": 20})
	await _settle(0.5)
	_check("networked sustained spray climbs with matching host aim", float(report.pitch) > 0.15 and absf(slot.node.pitch() - float(report.pitch)) < 0.001)
	_check("networked spray ammunition agrees", int(report.mag) == slot.lo.mag and slot.lo.mag < 25)
	_check("networked reverse lean agrees", float(report.lean) < -0.99 and slot.node.lean < -0.99)
	await _do(shooter, {"op": "controls_input", "recoil": false, "frames": 25})
	slot.lo.use_recoil = false
	net.restart_round()
	await _settle()
	_check("round reset clears lean and spray", slot.node.lean == 0.0 and slot.lo.spray_shots == 0)
