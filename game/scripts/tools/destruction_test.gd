extends Node
var g: Node3D
var fails := 0
var normal := Vector3.ZERO
var tangent := Vector3.ZERO

func start(scene: Node3D) -> void:
	g = scene
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		fails += 1

func frames(n: int = 2) -> void:
	for i in n:
		await get_tree().physics_frame

func blocked(point: Vector3) -> bool:
	return not g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point - normal * .4, point + normal * .4, 1)).is_empty()

func _run() -> void:
	await frames()
	var m: WallModule
	for candidate: WallModule in g.modules:
		var run := int(candidate.get_meta("run"))
		if run < 0 or candidate._size.y < 2.5 or candidate._size.x < 1.3:
			continue
		var spec: Dictionary = g.layout.data.walls[run]
		if spec.exterior and int(spec.level) == 0 and spec.rooms == ["office"] and absf(sin(candidate.rotation.y * 2.0)) > .2:
			m = candidate
			break
	check("angled exterior fixture exists", m != null)
	if m == null:
		get_tree().quit(1)
		return
	normal = m.face_normal()
	tangent = m.global_basis.x
	var point := Vector3(m.position.x, 1.65, m.position.z)
	var origin := Vector3(point.x,.05,point.z)
	var yaw := rad_to_deg(atan2(-normal.x,-normal.z))
	check("intact angled wall blocks the chosen impact", blocked(point))
	g.player.teleport(origin - normal * 1.1, yaw)
	g.loadout.use_spread = false
	g.loadout.use_recoil = false
	g.loadout._fire_armed = true
	g.loadout.fire_rifle()
	await frames()
	check("real shot cuts through at impact, leaves surrounding wall", not blocked(point) and blocked(point + tangent * .35) and m.state == WallModule.State.INTACT and m.shape_count() > 1 and g._parts_match(m))
	var melee_point := point + tangent * .38
	g.player.teleport(origin + tangent * .38 - normal * 1.1, yaw)
	g.doors._last_act.clear()
	g.doors._host_act(1, 0, DoorSystem.Act.KICK)
	await frames()
	check("authoritative melee chips the aimed wall rather than a fixed panel", not blocked(melee_point) and blocked(point + -tangent * .4) and g._parts_match(m))
	var replica := WallModule.new()
	replica.impact_destructible = true
	replica.remove_whole = true
	replica.setup("replica", m.position - m._size * .5, m.position + m._size * .5, WallModule.Mat.ORDINARY, Surfaces.get_mat("plaster"))
	replica.rotation = m.rotation
	replica.apply_remote(m.state, m.revision, m.material, m.openings)
	var original := m.part_boxes(m.state)
	var copied := replica.part_boxes(replica.state)
	var agrees := original.size() == copied.size()
	for i in mini(original.size(), copied.size()):
		agrees = agrees and original[i].position.distance_to(copied[i].position) < .00001 and original[i].size.distance_to(copied[i].size) < .00001
	check("replicated cutout list rebuilds identical authored geometry", agrees)
	check("stale damage cannot replace newer holes", not replica.apply_remote(0, m.revision - 1, 0, []))
	for i in 48:
		m.impact(point + tangent * sin(i * 1.7) * .7 + Vector3.UP * cos(i * 1.2) * .9, 34)
	check("sustained damage coalesces within a bounded cutout budget", m.openings.size() <= WallModule.MAX_OPENINGS and m.shape_count() < 150 and g._parts_match(m))
	m.reinforce()
	await frames()
	check("reinforcement keeps existing holes open without repairing them", not m.openings.is_empty() and not blocked(point) and g._parts_match(m))
	m.reset()
	await frames()
	check("reset removes every hole and restores collision", m.openings.is_empty() and m.revision == 0 and m.shape_count() == 1 and blocked(point))
	m.reinforce()
	check("reinforced wall resists bullet and melee cutouts", not m.impact(point, 100) and not m.impact(point, 100, true) and m.openings.is_empty())
	replica.free()
	var header: WallModule = g._mod(g.doors.doors[0].header)
	var supports: Array = g.wall_support._neighbors[header].duplicate()
	check("door header has multiple wall supports", supports.size() >= 2)
	if supports.size() >= 2:
		var support: WallModule = supports.pop_back()
		support.breach(WallModule.Kind.ORDINARY)
		await frames()
		check("the header remains while attached on one side", header.shape_count() > 0 and header.detached.is_empty())
		for panel: WallModule in supports:
			panel.breach(WallModule.Kind.ORDINARY)
		await frames()
		check("the unsupported header loses both mesh and collision",
			header.shape_count() == 0 and header.mesh_count() == 0 and not header.detached.is_empty())
		g.restart()
		await frames()
		check("the round reset restores the header and its support",
			header.detached.is_empty() and header.shape_count() == 1 and support.shape_count() == 1)
	# Cut all the way across an isolated full-height cell halfway up using the regular damage geometry.
	var isolated: WallModule = g._mod(g.doors.doors[0].header)
	var base: WallModule
	for panel: WallModule in g.wall_support._neighbors[isolated]:
		if panel._size.y >= 2.5:
			base = panel
			break
	if base:
		for panel: WallModule in g.wall_support._neighbors[base]:
			panel.breach(WallModule.Kind.ORDINARY)
		for step in range(11):
			var local_x := lerpf(-base._size.x * .5, base._size.x * .5, step / 10.0)
			base.impact(base.to_global(Vector3(local_x, 0.0, 0.0)), 45.0, true)
		await frames()
		check("a detached top falls and its grounded lower wall remains",
			not base.detached.is_empty() and base.state == WallModule.State.INTACT and base.shape_count() > 0
			and base.part_boxes(base.state).all(func(piece: AABB) -> bool: return piece.end.y < .3))
	print("SMOKE_OK destruction" if fails == 0 else "SMOKE_FAIL destruction")
	get_tree().quit(0 if fails == 0 else 1)
