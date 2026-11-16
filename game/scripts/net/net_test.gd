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
		"pattern":
			for st: Array in d["steps"]:
				p.script_move = Vector2(st[0], st[1])
				p.script_crouch = bool(st[2])
				p.script_sprint = bool(st[3])
				lo.script_fire = st.size() > 5 and bool(st[5])
				await _frames(int(st[4]))
			p.script_move = Vector2.ZERO
			p.script_crouch = false
			p.script_sprint = false
			lo.script_fire = false
			await _frames(30)
		"fire":
			lo.want_tool = Loadout.Tool.RIFLE
			lo.script_aim = true
			var target := int(d.get("target", -1))
			var point: Vector3 = d.get("point", Vector3.ZERO)
			for k in 4:
				_look_at(_target_pos(target) + Vector3(0, 1.2, 0) if target >= 0 else point)
				await _frames(1)
			for i in int(d["shots"]):
				for k in int(d.get("gap", FIRE_GAP)):
					_look_at(_target_pos(target) + Vector3(0, 1.2, 0) if target >= 0 else point)
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
			net.inject_event([NetMatch.Ev.WALL, net.round_id, m.wall_id, WallModule.State.INTACT, m.revision]) # duplicate rev
			net.inject_event([NetMatch.Ev.WALL, net.round_id - 1, m.wall_id, WallModule.State.BREACHED, m.revision + 5]) # old round
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
		"remotes": net.remotes.size(), "corrections": m["corrections"], "corr_max": _max(corr), "corr_mean": _mean(corr),
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
	var ids := _ids()
	var S: int = ids[1] ## shooter: first client
	var V: int = ids[2] if ids.size() > 2 else 1 ## victim: second client, or the host
	var P: int = 1 ## second placer for the simultaneous-charge race
	if ids.size() > 3:
		P = ids[3]
	print("[Test] players %s shooter=%d victim=%d placer2=%d" % [ids, S, V, P])

	# ---- 1. everyone moves at once (prediction / reconciliation under load)
	if _want("move"):
		var pat := {"op": "pattern", "steps": [[0, -1, 0, 0, 30], [1, 0, 0, 0, 25], [0, 1, 0, 1, 30], [-1, 0, 1, 0, 30],
			[0, -1, 1, 0, 20], [0, 0, 0, 0, 10], [0, 1, 0, 0, 20], [1, 1, 0, 0, 15]]}
		var ops := {}
		for id in ids:
			ops[id] = pat
		await _all(ops)
		await _consistency("after simultaneous movement")
		var before := _slot(S).node.global_position
		var ds := await _do(S, {"op": "desync"})
		_check("client desync is corrected by reconciliation", int(ds.get("corrections", 0)) >= 1
			and (ds["pos"] as Vector3).distance_to(_slot(S).node.global_position) < 0.05
			and _slot(S).node.global_position.distance_to(before) < 0.05, str(ds))

	# ---- 2. static line-of-sight hits: 3 x 20 damage
	if _want("los"):
		_park([S, V])
		net.test_teleport(S, Vector3(0.0, 0.05, -1.0), 0.0)
		net.test_teleport(V, Vector3(0.0, 0.05, -7.0), 180.0)
		await _settle(0.5)
		var mag0 := _slot(S).lo.mag
		await _do(S, {"op": "fire", "target": V, "shots": 3})
		await _settle(0.4)
		_check("LOS: 3 hits = 60 damage", is_equal_approx(_hp(V), 40.0), "hp=%.0f" % _hp(V))
		_check("LOS: shooter spent 3 rounds (host)", _slot(S).lo.mag == mag0 - 3, "mag %d -> %d" % [mag0, _slot(S).lo.mag])
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
		_check("through ordinary panel: 2 x 10 damage", is_equal_approx(_hp(V), 80.0), "hp=%.0f" % _hp(V))
		net.test_teleport(S, Vector3(0.3, 0.05, -2.75), -90.0)
		net.test_teleport(V, Vector3(2.2, 0.05, -2.75), 90.0)
		await _settle(0.6)
		await _do(S, {"op": "fire", "target": V, "shots": 2})
		await _settle(0.4)
		_check("reinforced panel stops rounds", is_equal_approx(_hp(V), 80.0), "hp=%.0f" % _hp(V))
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
		await _do(S, {"op": "fire", "target": V, "shots": 5})
		await _settle(0.4)
		_check("5 hits kill", not _slot(V).alive and _hp(V) == 0.0, "hp=%.0f" % _hp(V))
		var vpos := _slot(V).node.global_position
		var shp := _hp(S)
		await _do(V, {"op": "pattern", "steps": [[0, -1, 0, 0, 30, true], [1, 0, 0, 0, 30, true]]})
		_check("dead player can't move", _slot(V).node.global_position.distance_to(vpos) < 0.05,
			"moved %.2f" % _slot(V).node.global_position.distance_to(vpos))
		_check("dead player can't shoot", _hp(S) == shp)
		await _consistency("after death")

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
			"sim_loss": float(a.get("sim-loss", 0)), "transport": "ENet localhost, headless, one machine"},
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
