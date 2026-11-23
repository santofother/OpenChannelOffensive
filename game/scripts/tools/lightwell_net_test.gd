extends NetTest
## Map-specific transport fixtures retain the old demo coordinates unchanged.
func _exec(d: Dictionary) -> Dictionary:
	if String(d.op) == "map_report":
		return {"identity":g.layout.identity(),"walls":net.digest().walls,"alive":net.local_alive(),
			"state":net.loop.state(),"team":net.local_team(),"view":net.remote_view()}
	return await super._exec(d)

func _wall_reports(tag: String) -> void:
	await _settle()
	var ops := {}
	for id: int in _ids():
		ops[id] = {"op":"map_report"}
	var reports := await _all(ops)
	var walls: Dictionary = net.digest().walls
	for id: int in reports:
		_check(tag + " peer %d layout/material/damage/collision" % id, reports[id].identity == g.layout.identity() and reports[id].walls == walls)

func _fixture(kind: String) -> Dictionary:
	var space := g.get_world_3d().direct_space_state
	for m: WallModule in g.modules:
		if m.state != WallModule.State.INTACT or m.position.y > 1.5:
			continue
		var run := int(m.get_meta("run"))
		if kind == "cover":
			if run >= 0 or m._size.y < 1.25 or m.get_node_or_null("FurnitureDetails") == null:
				continue
		else:
			if run < 0 or m._size.y < 2.6 or m._size.x < 1.25:
				continue
			var spec: Dictionary = g.layout.data.walls[run]
			if kind == "courtyard" and not spec.rooms.has("court"):
				continue
			if kind == "exterior" and (not spec.exterior or absf(sin(m.rotation.y * 2.0)) < .2):
				continue
		var normal := m.face_normal()
		var floor_origin := Vector3(m.position.x,.06,m.position.z)
		var aim := floor_origin + Vector3.UP * minf(m._size.y*.66,1.5)
		for side in [-1.0,1.0]:
			var cross := normal * float(side)
			var start := floor_origin - cross * (maxf(.11,minf(m._size.x,m._size.z)*.5) + .96)
			var eye := start + Vector3.UP * 1.65
			var ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,aim,1))
			if ray.is_empty() or ray.collider != m or not _capsule_clear(start):
				continue
			if kind != "cover" and not _capsule_clear(floor_origin + cross * .95):
				continue
			return {"module":m,"start":start,"aim":aim,"cross":cross,"yaw":rad_to_deg(atan2(-cross.x,-cross.z))}
	return {}


func _capsule_clear(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = .35
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform.origin = at + Vector3.UP * .9
	q.collision_mask = 1
	return g.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _plant_near_edge(site: int) -> Vector3:
	var tuning := net.loop.rules.tuning
	var area: Dictionary = tuning.site_areas[site]
	var center: Vector3 = tuning.sites[site]
	for vertex: Vector2 in area.polygon:
		for f in [.76, .66, .56]:
			var p := Vector2(center.x, center.z).lerp(vertex, f)
			var candidate := Vector3(p.x, center.y, p.y)
			if candidate.distance_to(center) > tuning.site_radius and _capsule_clear(candidate) and tuning.site_at(candidate) == site:
				return candidate
	return Vector3.INF


func _run_host() -> void:
	var want := int(NetworkManager.args.get("net-test",2))
	_check("Lightwell peers joined",await _wait_players(want,60))
	if _fails:
		_finish()
		return
	await _settle()
	await _consistency("Lightwell initial six spawn occupancy")
	var rules := net.loop.rules
	var ids := _ids()
	var defender := 0
	for id: int in ids:
		if _slot(id).team == 1:
			defender = id
	# Test tools in a live authority phase, then return to lobby for a complete real match.
	rules.phase = RoundRules.Phase.LIVE
	rules.deadline = net.tick + 36000
	rules.serial += 1
	net.loop.sync()
	for s: NetMatch.Slot in net.slots.values():
		s.lo.tuning.ordinary_fuse = .3
		s.lo.tuning.heavy_fuse = .4
	# The upper Copy Room sits over a ground-floor Server door. Navigation and
	# snapshots still use the real stacked levels, including automatic bot use.
	var stacked_door: DoorSystem.Door
	var specs: Array = g.layout.doors()
	for i in specs.size():
		var spec: Dictionary = specs[i]
		if spec.level == 0 and g.layout.data.walls[spec.run].rooms == ["a","prep"]:
			stacked_door = g.doors.doors[i]
			break
	_check("stacked door fixture exists", stacked_door != null)
	if stacked_door:
		var upper_point := stacked_door.center(g.layout.elevation(1) + .055)
		net.test_teleport(1,upper_point,0)
		await _settle(.3)
		await _consistency("upper floor location replicates")
		g.doors.host_bots([1])
		_check("automatic bot interaction ignores a door on the other floor", stacked_door.closed())
		net.test_teleport(1,stacked_door.center(.055) + stacked_door.normal * .62,0)
		await _settle(.2)
		g.doors.host_bots([1])
		_check("automatic bot interaction opens a door on its own floor", not stacked_door.closed())
	var court := _fixture("courtyard")
	var shell := _fixture("exterior")
	var furnishing := _fixture("cover")
	_check("clear courtyard, angled exterior and furniture test lanes", not court.is_empty() and not shell.is_empty() and not furnishing.is_empty())
	if _fails:
		_finish()
		return
	var courtyard: WallModule = court.module
	net.test_teleport(defender, court.start, court.yaw)
	await _settle()
	await _do(defender,{"op":"hold_tool","tool":Loadout.Tool.REINFORCE,"point":court.aim,"frames":190})
	_check("remote defender reinforces arbitrary courtyard cell",courtyard.material == WallModule.Mat.REINFORCED and courtyard.revision == 1)
	await _wall_reports("reinforced courtyard")
	for fixture: Dictionary in [shell,court]:
		var m: WallModule = fixture.module
		net.test_teleport(1,fixture.start,fixture.yaw)
		await _settle(.2)
		await _do(1,{"op":"place","tool":Loadout.Tool.HEAVY_CHARGE if m == courtyard else Loadout.Tool.ORDINARY_CHARGE,"point":fixture.aim})
		await _settle(1)
		_check("qualified charge fully clears " + m.wall_id,m.state == WallModule.State.BREACHED and m.shape_count() == 0)
		await _do(1,{"op":"walk","yaw":fixture.yaw,"ticks":55})
		await _settle(.25)
		_check("owner and host walk through " + m.wall_id,(_slot(1).node.position - m.position).dot(fixture.cross) > .4)
	var cover: WallModule = furnishing.module
	g.loadout.set_gear("service_rifle", "p9")
	g.loadout.use_spread = false
	net.test_teleport(1, furnishing.start, furnishing.yaw)
	await _settle(.3)
	await _do(1, {"op":"fire", "point":furnishing.aim, "shots":4, "gap":10})
	_check("authoritative rifle fire destroys furniture and its details", cover.state == WallModule.State.BREACHED
		and cover.shape_count() == 0 and not cover.get_node("FurnitureDetails").visible)
	var chip := _fixture("exterior")
	_check("second angled exterior test wall exists", not chip.is_empty())
	if chip.is_empty():
		_finish()
		return
	var chipped: WallModule = chip.module
	net.test_teleport(1, chip.start, chip.yaw)
	await _settle(.3)
	await _do(1, {"op":"fire", "point":chip.aim, "shots":1})
	_check("gunfire cuts a local opening in an angled wall", not chipped.openings.is_empty() and chipped.state == WallModule.State.INTACT and chipped.shape_count() > 1)
	var holes := chipped.openings.duplicate()
	_check("reinforcing a chipped wall preserves its cutouts", chipped.reinforce() and chipped.openings == holes)
	var header: WallModule = g._mod(stacked_door.header)
	for neighbor: WallModule in g.wall_support._neighbors[header]:
		neighbor.breach(WallModule.Kind.HEAVY if neighbor.material == WallModule.Mat.REINFORCED else WallModule.Kind.ORDINARY)
	await _settle(.3)
	_check("the host removes an unsupported header", not header.detached.is_empty() and header.shape_count() == 0)
	await _wall_reports("exterior damage and header collapse")
	if NetworkManager.args.has("late-file"):
		var file := FileAccess.open(String(NetworkManager.args["late-file"]),FileAccess.WRITE)
		file.store_string("go")
		file.close()
		_check("late join enters Lightwell",await _wait_players(want + 1,30))
		await _settle()
		for id: int in _ids():
			if id not in ids:
				var report := await _do(id,{"op":"map_report"})
				_check("late join waits and receives no enemy coordinates",not report.alive and _only_teammates(report.view,int(report.team)))
		await _wall_reports("late join damaged map")
	ids = _ids()
	rules.rematch()
	# Ten network resets, including material and all empty collision cells.
	for i in 10:
		net.assign_spawns(0)
		net.restart_round()
		await _settle(.12)
	await _consistency("ten Lightwell resets")
	rules.tuning.prep = .5
	rules.tuning.live = 40
	rules.tuning.plant = .3
	rules.tuning.defuse = .4
	rules.tuning.fuse = 8
	rules.tuning.resolution = 1
	var ops := {}
	for id: int in ids:
		ops[id] = {"op":"round_action","action":"ready"}
	await _all(ops)
	var zones := {}
	for number in range(1,14):
		var live := await _phase(RoundRules.Phase.LIVE,5)
		_check("Lightwell round %d live" % number,live)
		if not live:
			_finish()
			return
		zones[net._attack_zone] = true
		_check("Lightwell round %d role spawn set" % number,rules.attack_team == (1 if number > 6 else 0))
		var spawns_ok := true
		for s: NetMatch.Slot in net.slots.values():
			spawns_ok = spawns_ok and s.node.global_position.distance_to(net.spawn_for(s)[0]) < .1 and (s.spawn < 3) == (s.team == rules.attack_team)
		_check("all role spawns restored in round %d" % number,spawns_ok)
		await _consistency("Lightwell round %d spawn replication" % number)
		if number in [1,2]:
			var site := number - 1
			var carrier := rules.carrier
			var plant := _plant_near_edge(site)
			_check("a clear plant position exists outside the old circle", plant != Vector3.INF)
			net.test_teleport(carrier, plant if plant != Vector3.INF else rules.tuning.sites[site], 0)
			await _settle(.25)
			await _do(carrier,{"op":"round_input","plant":true,"frames":45})
			await _do(carrier,{"op":"round_input"})
			_check("network plant at the edge of site " + str(site),
				rules.phase == RoundRules.Phase.PLANTED and rules.site == site and rules.bomb_pos.distance_to(plant) < .12)
			net.test_teleport(carrier,g.spawn_at(0)[0],0)
			var defuser := 0
			for id: int in ids:
				if _slot(id).team != rules.attack_team:
					defuser = id
			net.test_teleport(defuser, plant if plant != Vector3.INF else rules.tuning.sites[site], 0)
			await _settle(.25)
			await _do(defuser,{"op":"round_input","hold":true,"frames":55})
			await _do(defuser,{"op":"round_input"})
			_check("real network defuse at site " + str(site),rules.reason == "Bomb defused")
		else:
			rules.deadline = net.tick + 10
			_check("host timeout resolves Lightwell round",await _phase(RoundRules.Phase.RESOLUTION,2))
		if number < 13:
			await _phase(RoundRules.Phase.PREP,3)
	_check("all seven attacker zones appeared in the match", zones.size() == 7)
	_check("Lightwell deciding round ends 7:6",await _phase(RoundRules.Phase.RESULT,4) and rules.awards == 13 and rules.scores == [7,6])
	net.loop.request("rematch")
	await _settle(.4)
	_check("Lightwell rematch returns unready lobby",rules.phase == RoundRules.Phase.LOBBY and rules.scores == [0,0])
	await _wall_reports("rematch ordinary baseline")
	results["lightwell"] = {"identity":g.layout.identity(),"cells":g.modules.size(),"both_sites":true,
		"deciding_round":true,"resets":10,"attack_zones_used":zones.size()}
	_finish()
