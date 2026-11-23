extends Node
## Consequential geometry checks use the real Jolt world and standing player capsule.
var g: Node3D
var fails := 0

func start(scene: Node3D) -> void:
	g = scene
	get_tree().create_timer(180).timeout.connect(func() -> void: get_tree().quit(1))
	_run.call_deferred()

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("  PASS " if ok else "  FAIL ") + label + " " + detail)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func clear_at(feet: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = .35
	query.shape = capsule
	query.transform.origin = feet + Vector3(0, .9, 0)
	query.collision_mask = 1
	return g.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

## Door rules through the real host paths (offline authority): block, open/close, zip tie, handle shot, kick, blast.
func _door_checks(layout: LightwellLayout) -> void:
	var doors: DoorSystem = g.doors
	check("every doorway has a door", doors != null and doors.doors.size() == layout.doors().size())
	var authored: DoorSystem.Door = doors.doors[0]
	var point := authored.center(.05)
	var normal := authored.normal
	var d: DoorSystem.Door = doors.target_door(point + normal * 1.0 + Vector3(0, 1.6, 0), -normal, DoorSystem.REACH)
	check("facing a doorway targets its door", d != null and d.id == 0)
	if d == null:
		return
	var ear := point + Vector3.UP * 1.5
	var listener := ear + normal * .8
	var source := ear - normal * .8
	check("closed door obstructs the shared audio ray", GameAudio.blocked(g.get_world_3d(), listener, source))
	g.player.teleport(point + normal * 1.05, _yaw(-normal))
	g.player.script_move = Vector2(0, -1)
	await frames(50)
	g.player.script_move = Vector2.ZERO
	check("a closed door blocks walking", (g.player.global_position - point).dot(normal) > .2, str(g.player.global_position))
	var mark_at := ear + normal * DoorSystem.LEAF_THICKNESS * .5
	g.loadout._add_mark(mark_at, normal, d.body)
	var mark: Node3D = g.loadout._marks.back()
	var mark_local := mark.position
	g.player.teleport(point + normal * 1.05, _yaw(-normal))
	await frames(2)
	doors._last_act.clear()
	doors._host_act(1, 0, DoorSystem.Act.USE)
	await frames(30)
	check("open doorway clears the shared audio ray", not GameAudio.blocked(g.get_world_3d(), listener, source))
	check("a bullet mark follows the solid leaf", mark.get_parent() == d.body and mark.position.is_equal_approx(mark_local)
		and mark.global_position.distance_to(mark_at) > .2)
	var panel_mid := d.body.to_global(Vector3(d.width * .5, 1.0, 0))
	var panel_normal := d.body.global_basis.z
	var ray := PhysicsRayQueryParameters3D.create(panel_mid + panel_normal * .18, panel_mid - panel_normal * .18, 1)
	var hit := g.get_world_3d().direct_space_state.intersect_ray(ray)
	check("an open door still blocks crossing the actual leaf", not hit.is_empty() and hit.collider == d.body)
	check("F opens away and the leaf stays solid", d.target != 0.0 and d.body.collision_layer == 1
		and d.normal.dot(normal) * signf(d.target) < 0.0, str(d.target))
	g.player.script_move = Vector2(0, -1)
	await frames(50)
	g.player.script_move = Vector2.ZERO
	check("an open door can be walked through", (g.player.global_position - point).dot(normal) < -.55, str(g.player.global_position))
	g.player.teleport(point + normal * 1.05, _yaw(-normal))
	await frames(2)
	doors._last_act.clear()
	doors._host_act(1, 0, DoorSystem.Act.USE)
	await frames(50)
	check("F closes it again and collision returns", d.target == 0.0 and d.angle == 0.0 and d.body.collision_layer == 1)
	g.loadout.zip_ties = 0
	doors._last_act.clear()
	doors._host_act(1, 0, DoorSystem.Act.ZIP)
	check("no zip tie, no lock", not d.locked)
	g.loadout.zip_ties = 1
	doors._last_act.clear()
	doors._host_act(1, 0, DoorSystem.Act.ZIP)
	check("zip tie locks a closed door and is used up", d.locked and g.loadout.zip_ties == 0 and d.tie_node.visible)
	doors._last_act.clear()
	doors._host_act(1, 0, DoorSystem.Act.USE)
	check("a zip-tied door does not open", d.target == 0.0 and d.locked)
	var handle := d.hinge + d.along * (d.width - .02 - DoorSystem.HANDLE_ALONG) + Vector3(0, DoorSystem.HANDLE_Y, 0)
	doors.on_shot({"hit": false, "impacts": [{"position": handle + Vector3(.03, .02, 0), "collider": d.body}], "origin": handle + normal * 3.0})
	check("shooting the handle snaps the tie and the door swings ajar", not d.locked and not d.handle and absf(d.target) == DoorSystem.AJAR_ANGLE)
	var body_shot := doors.doors[1]
	doors.on_shot({"hit": true, "position": body_shot.hinge + body_shot.along * .3 + Vector3(0, 1.5, 0), "collider": body_shot.body, "impacts": []})
	check("a shot away from the handle leaves the door latched", body_shot.handle and body_shot.target == 0.0)
	body_shot.locked = true
	doors.kick(body_shot, body_shot.center(0.0) + body_shot.normal)
	check("one kick does not break a zip-tied door", not body_shot.broken and body_shot.locked)
	doors.kick(body_shot, body_shot.center(0.0) + body_shot.normal)
	check("two kicks leave a zip-tied door intact", not body_shot.broken and body_shot.locked)
	doors.kick(body_shot, body_shot.center(0.0) + body_shot.normal)
	check("three kicks leave a zip-tied door intact", not body_shot.broken and body_shot.locked)
	doors.kick(body_shot, body_shot.center(0.0) + body_shot.normal)
	check("fourth kick breaks it off its hinges", body_shot.broken and body_shot.body.collision_layer == 0)
	var kicked := doors.doors[2]
	doors.kick(kicked, kicked.center(0.0) + kicked.normal)
	check("kicking an unlocked door bursts it open", kicked.target != 0.0 and not kicked.broken)
	var blasted := doors.doors[3]
	doors.blast(blasted.center(1.2) + blasted.normal * .3, 1.2)
	check("a nearby blast blows the door off", blasted.broken)
	check("a distant blast leaves other doors alone", not doors.doors[4].broken)
	g.restart()
	await frames(2)

func _yaw(dir: Vector3) -> float:
	return rad_to_deg(atan2(-dir.x,-dir.z))


func _stair_path(layout: LightwellLayout, stair: Dictionary, ascending: bool) -> Array[Vector3]:
	var height := layout.elevation(1)
	var points: Array[Vector3] = []
	if stair.get("kind", "") == "straight":
		var u := float(stair.u)
		var from := float(stair["from"])
		var to := float(stair.to)
		var toward := signf(to - from)
		var l: Array = stair.landing
		var wall_side := float(l[1]) + float(l[3]) if toward > 0 else float(l[1])
		points = [layout.world(u,from - toward*.9,.06),layout.world(u,from + toward*.3,.2),
			layout.world(u,to + toward*.35,height),layout.world(u,wall_side + toward*.95,height)]
	else:
		var p: Array = stair.rect
		var first: float = p[0] + p[2] * (.25 if stair.low_left else .75)
		var second: float = p[0] + p[2] * (.75 if stair.low_left else .25)
		var v := float(p[1])
		var end: float = v + p[3] - .57
		var start_left := float(p[0]) + float(stair.entry)
		var start_right := float(p[0]) + float(stair.exit)
		points = [
			layout.world(start_left,v-.65,.06),layout.world(first,v+.48,.03),
			layout.world(first,end,height*.5),layout.world(second,end,height*.5),
			layout.world(second,v+.4,height),layout.world(start_right,v-.65,height)]
	if not ascending:
		points.reverse()
	return points


func _walk_to(goal: Vector3) -> bool:
	for i in 240:
		var feet: Vector3 = g.player.global_position
		var delta := Vector3(goal.x-feet.x,0,goal.z-feet.z)
		if delta.length() < .16:
			g.player.script_move = Vector2.ZERO
			return absf(goal.y - feet.y) < .28
		g.player.set_look(_yaw(delta),0)
		g.player.script_move = Vector2(0,-.8)
		await frames(1)
	g.player.script_move = Vector2.ZERO
	return false


var _names: Array[String] = []

func _all_names(n: Node) -> Array[String]:
	var out: Array[String] = [str(n.get_path()) + ":" + n.get_class()]
	for c in n.get_children():
		out.append_array(_all_names(c))
	return out

func _quiet_route_depths(layout: LightwellLayout) -> Array[int]:
	var graph := {"outside":[]}
	for r: Dictionary in layout.data.rooms:
		graph["%d/%s" % [r.level, r.id]] = []
	for d: Dictionary in layout.doors():
		var connected: Array = []
		for room: String in layout.data.walls[d.run].rooms:
			connected.append("%d/%s" % [d.level,room])
		if connected.size() == 1:
			connected.append(String(layout.data.walls[d.run].get("to", "outside")))
		graph[connected[0]].append(connected[1])
		graph[connected[1]].append(connected[0])
	for stair: Dictionary in layout.data.stairs:
		var link: Array = stair.get("links", ["0/" + String(stair.id), "1/" + String(stair.id)])
		graph[link[0]].append(link[1])
		graph[link[1]].append(link[0])
	var distance := {"outside":0}
	var queue := ["outside"]
	while not queue.is_empty():
		var node: String = queue.pop_front()
		for other: String in graph[node]:
			if not distance.has(other):
				distance[other] = int(distance[node]) + 1
				queue.append(other)
	return [int(distance.get("0/a",-1)) - 1,int(distance.get("1/office",-1)) - 1]


func _check_cover_edges(space: PhysicsDirectSpaceState3D) -> void:
	var peeks := 0
	for furniture: WallModule in g.modules:
		if not furniture.bullet_breakable or furniture._size.y < 1.72 or furniture._size.y > 2.2 or furniture.position.y > 1.15:
			continue
		var normal := furniture.face_normal()
		var tangent := normal.cross(Vector3.UP)
		var center := Vector3(furniture.position.x,1.65,furniture.position.z)
		var depth := minf(furniture._size.x,furniture._size.z) * .5 + .55
		var span := maxf(furniture._size.x,furniture._size.z) * .5 + .17
		var a := center + normal * depth
		var b := center - normal * depth
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
		if hit.is_empty() or hit.collider != furniture:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(a + tangent*span,b + tangent*span,1)).is_empty() \
				or space.intersect_ray(PhysicsRayQueryParameters3D.create(a - tangent*span,b - tangent*span,1)).is_empty():
			peeks += 1
	check("standing-height furniture blocks the centre lane and leaves peeks at an edge", peeks >= 4, str(peeks))


func _run() -> void:
	await frames(5)
	var layout: LightwellLayout = g.layout
	var space := g.get_world_3d().direct_space_state
	var surfaces := {}
	for r: Dictionary in layout.data.rooms:
		var center := layout.world(r.label[0], r.label[1], layout.elevation(r.level))
		surfaces[g.footstep_surface(center)] = true
	check("Lightwell has concrete, carpet and metal footsteps", surfaces.size() == 3)
	var ids := {}
	var cells := layout.cells()
	for m: WallModule in g.modules:
		ids[m.wall_id] = true
	check("unique stable wall cell IDs", ids.size() == cells.size() and cells.size() == g.modules.size(), str(cells.size()))
	var depths := _quiet_route_depths(layout)
	# The exterior Fire Stair deliberately shortens B: Records Store, Print/Rack Prep and one more room.
	check("A needs four rooms and upstairs B needs three", depths[0] >= 4 and depths[1] >= 3, str(depths))
	check("angled damageable cells are present", cells.any(
		func(c: Dictionary) -> bool: return absf(sin(2.0 * float(c.yaw))) > .1 and c.run >= 0))
	check("seven distinct three-player attacker zones", layout.attack_zone_count() == 7 and
		layout.data.attack_zones.all(func(zone: Dictionary) -> bool: return zone.spawns.size() == 3))
	for zone in layout.attack_zone_count():
		var clear := true
		for i in 6:
			var start := layout.spawn_at(i, zone)
			var spawn: Vector3 = start[0]
			clear = clear and clear_at(spawn)
			if i < 3:
				clear = clear and Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(start[1])).dot(-spawn.normalized()) > .5
			for j in range(i + 1, 6):
				clear = clear and spawn.distance_to(layout.spawn_at(j, zone)[0]) > .65
		check("zone %s has clear role slots and attackers face inward" % layout.data.attack_zones[zone].name, clear)
	var tuning := layout.tuning()
	check("site B is on the upper floor", absf(tuning.sites[1].y - layout.elevation(1) - 0.05) < 0.01)
	var pockets_clear := true
	for site: Vector3 in tuning.sites:
		for i in 33:
			var angle := TAU * i / 32.0
			var point := site if i == 32 else site + Vector3(cos(angle), 0, sin(angle)) * tuning.site_radius
			pockets_clear = pockets_clear and clear_at(point)
	check("A/B objective waypoints have capsule clearance", pockets_clear)
	var bounds_ok := true
	for i in tuning.site_areas.size():
		var area: Dictionary = tuning.site_areas[i]
		var center: Vector3 = tuning.sites[i]
		for vertex: Vector2 in area.polygon:
			var near_corner := Vector2(center.x, center.z).lerp(vertex, .88)
			var inside := Vector3(near_corner.x, center.y, near_corner.y)
			bounds_ok = bounds_ok and tuning.site_at(inside) == i and inside.distance_to(center) > tuning.site_radius
			var wrong_floor := inside + Vector3.UP * layout.elevation(1) * (1.0 if i == 0 else -1.0)
			bounds_ok = bounds_ok and tuning.site_at(wrong_floor) != i
	check("both entire site footprints support planting on their own floors", bounds_ok)
	check("Server Prep and Gallery stay outside the site footprints",
		tuning.site_at(layout.world(29.5, 4.01, .05)) == -1 and tuning.site_at(layout.world(25.2, 9.63, layout.elevation(1) + .05)) == -1)
	var yard := layout.world(24,17.5,1)
	var roof_clear := space.intersect_ray(PhysicsRayQueryParameters3D.create(yard,yard + Vector3.UP * 8,1)).is_empty()
	check("courtyard is open to sky", roof_clear)
	var room := layout.world(8.7,7,1)
	check("roof covers occupied rooms", GameAudio.blocked(g.get_world_3d(),room,room + Vector3.UP * 8))
	await _door_checks(layout)
	var door_count := 0
	for d: DoorSystem.Door in g.doors.doors:
		d.target = DoorSystem.OPEN_ANGLE
		g.doors._pose(d, true)
	await frames(2)
	for d: DoorSystem.Door in g.doors.doors:
		var point := d.center(.065)
		var normal := d.normal
		var can_cross := true
		for side in [-1,1]:
			var open_feet: Vector3 = point + normal * side * .64
			# At upper stairs a landing abuts the inclined flight just beyond the threshold.
			var can_start := clear_at(open_feet)
			var q := PhysicsShapeQueryParameters3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.height = 1.8
			capsule.radius = .35
			q.shape = capsule
			q.collision_mask = 1
			q.transform.origin = open_feet + Vector3.UP * .9
			q.motion = -normal * side * 1.28
			can_cross = can_cross and can_start and space.cast_motion(q)[0] >= .999
		check("door %02d standing threshold clearance" % d.id, can_cross, str(point))
		door_count += 1
	check("all scheduled doors exercised", door_count == layout.doors().size())
	for d: DoorSystem.Door in g.doors.doors:
		d.body.collision_layer = 0
	await frames(2)
	for stair: Dictionary in layout.data.stairs:
		for ascending in [true,false]:
			var points := _stair_path(layout, stair, ascending)
			g.player.teleport(points[0],0)
			var traversed := true
			for i in range(1,points.size()):
				traversed = await _walk_to(points[i]) and traversed
			check("%s staircase traverses %s with the real standing controller" % [stair.id, "up" if ascending else "down"],
				traversed and absf(g.player.global_position.y - points[-1].y) < .12, str(g.player.global_position))
	var nav := BotNav.new()
	nav.build(g, g.bot_nav_area())
	for i in 100:
		if nav.ready and nav.snap(layout.spawn_at(0)[0]) != Vector3.ZERO:
			break
		await get_tree().create_timer(.02,false,false,true).timeout
	print("    navigation sync: ready=",nav.ready," iteration=",NavigationServer3D.map_get_iteration_id(nav.map),
		" spawn snap=",nav.snap(layout.spawn_at(0)[0])," site snap=",nav.snap(layout.tuning().sites[0]))
	var upper_point := layout.world(22.0,10.1,layout.elevation(1))
	var stair_route := nav.path(layout.spawn_at(4)[0], upper_point)
	for stair: Dictionary in layout.data.stairs:
		var probes := _stair_path(layout,stair,true)
		for i in probes.size():
			var snap := nav.snap(probes[i])
			var from_floor := nav.path(probes[0],probes[i])
			print("    stair nav ",stair.id," ",i," goal=",probes[i]," snap=",snap,
				" path_end=",str(from_floor[-1]) if not from_floor.is_empty() else "none")
	check("baked navigation connects ground and upper rooms", stair_route.size() > 4 and
		stair_route[0].y < .25 and stair_route[-1].distance_to(upper_point) < .7, "end %s, target %s" % [str(stair_route[-1]) if not stair_route.is_empty() else "none", str(upper_point)])
	for zone in layout.attack_zone_count():
		var all_reachable := true
		for i in 3:
			for site: Vector3 in layout.tuning().sites:
				var route := nav.path(layout.spawn_at(i,zone)[0],site)
				var reached := route.size() >= 2 and route[-1].distance_to(site) < .65
				if not reached and i == 0:
					print("    route to ", site, " ", str(route))
				all_reachable = all_reachable and reached
		check("walkable routes from all %s starts to either site" % layout.data.attack_zones[zone].name, all_reachable)
	var unreachable: Array[String] = []
	for r: Dictionary in layout.data.rooms:
		if r.kind == "stairs":
			continue
		var center := layout.world(r.label[0],r.label[1],layout.elevation(r.level))
		var reached := false
		var poly := layout.polygon(r)
		# A room label can sit under a table. Test reachable floor around it.
		for offset in [Vector3.ZERO,Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK,
				Vector3.RIGHT * 2.0,Vector3.LEFT * 2.0,Vector3.FORWARD * 2.0,Vector3.BACK * 2.0]:
			var goal := nav.snap(center + offset)
			if absf(goal.y-center.y) > .45 or not Geometry2D.is_point_in_polygon(Vector2(goal.x,goal.z),poly):
				continue
			var route := nav.path(layout.spawn_at(0)[0], goal)
			if not route.is_empty() and route[-1].distance_to(goal) < .45:
				reached = true
				break
		if not reached:
			unreachable.append(String(r.name))
	check("every furnished room has a walkable nav route", unreachable.is_empty(), str(unreachable))
	nav.free_rids()
	_check_cover_edges(space)
	var exposed := []
	for spec: Dictionary in layout.doors():
		if not spec.exterior or int(spec.level) != 0:
			continue
		var normal: Vector3 = spec.along.cross(Vector3.UP)
		for t in [.2, .5, .8]:
			for eye_y in [1.05, 1.65]:
				var center: Vector3 = spec.hinge + spec.along * spec.width * t + Vector3.UP * eye_y
				for offset in [-.75, -.35, 0.0, .35, .75]:
					var eye: Vector3 = center + normal * offset
					for zone in layout.attack_zone_count():
						for i in 3:
							var spawn: Vector3 = layout.spawn_at(i, zone)[0]
							for height in [1.05, 1.65]:
								var target := Vector3(spawn.x,height,spawn.z)
								var across: Vector3 = (target - eye).cross(Vector3.UP).normalized() * .2
								for body: Vector3 in [target - across,target,target + across]:
									if not GameAudio.blocked(g.get_world_3d(), eye, body):
										exposed.append([spec.run,zone,i,offset])
	var exposed_pairs := {}
	for ray: Array in exposed:
		var pair := Vector2i(ray[0],ray[1])
		exposed_pairs[pair] = int(exposed_pairs.get(pair,0)) + 1
	check("exterior thresholds shield all attacker starts", exposed.is_empty(), str(exposed_pairs))
	# Ordinary cover breaks on the fourth service-rifle body impact; reinforcement resists bullets.
	var cover: WallModule
	for m: WallModule in g.modules:
		if m.bullet_breakable:
			cover = m
			break
	for i in 3:
		cover.hit_cover(34)
	check("cover survives three rifle impacts", cover.state == WallModule.State.INTACT)
	cover.hit_cover(34)
	check("fourth rifle impact clears cover mesh, detail and collision", cover.state == WallModule.State.BREACHED
		and cover.shape_count() == 0 and cover.mesh_count() == 0 and not cover.get_node("FurnitureDetails").visible)
	cover.reset()
	cover.reinforce()
	cover.hit_cover(1000)
	check("reinforced cover resists bullets", cover.state == WallModule.State.INTACT)
	g.restart()
	await frames(2)
	var wall_coverage := true
	for m: WallModule in g.modules:
		wall_coverage = wall_coverage and m.can_reinforce() and m.reinforce() and not m.breach(WallModule.Kind.ORDINARY)
		wall_coverage = wall_coverage and m.breach(WallModule.Kind.HEAVY) and m.shape_count() == 0 and m.mesh_count() == 0 and g._parts_match(m)
	check("every cell including headers reinforces and clears completely", wall_coverage)
	await frames(2)
	var baseline := 0
	var reset_stable := true
	for iteration in 10:
		g.restart()
		await frames(2)
		# Gadget equipment visuals are rebuilt every frame (queue_free), so sample everything else.
		var count := get_tree().get_node_count() - _all_names(g.gadgets).size()
		if iteration == 0:
			baseline = count
		if count != baseline:
			print("    reset %d node count %d (baseline %d)" % [iteration, count, baseline])
		reset_stable = reset_stable and count == baseline
		for m: WallModule in g.modules:
			reset_stable = reset_stable and m.state == WallModule.State.INTACT and m.revision == 0 and m.can_reinforce() and g._parts_match(m) \
				and (not m.bullet_breakable or m.get_node("FurnitureDetails").visible)
	check("ten resets restore wall collision and stable node counts", reset_stable, str(baseline))
	check("resets close, unlock and restore every door", g.doors.doors.all(func(d: DoorSystem.Door) -> bool:
		return d.target == 0.0 and not d.locked and not d.broken and d.handle and d.body.collision_layer == 1))
	var evidence := {"map": layout.identity(),"wall_cells": cells.size(),"door_thresholds_checked_on_both_faces":door_count,"stairs_checked_both_directions":layout.data.stairs.size(), "intact_intervening_rooms":depths,
		"attack_zones":layout.attack_zone_count(),"spawn_slots":3 * (1 + layout.attack_zone_count()),
		"exposed_door_rays":exposed.size(),"plant_pocket_samples":66,"reset_iterations":10,"settled_nodes":baseline,"failures":fails}
	var path := String(NetworkManager.args.get("geometry-out","user://lightwell-geometry.json"))
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(evidence,"  "))
	print("SMOKE_%s lightwell" % ("OK" if fails == 0 else "FAIL"))
	get_tree().quit(0 if fails == 0 else 1)
