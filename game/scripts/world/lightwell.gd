extends "res://scripts/world/match_scene.gd"
## Lightwell's first floor and upper office flank share metre coordinates.
const FURNISHINGS := preload("res://scripts/world/lightwell_furnishings.gd")
const FLOOR_MATS := ["asphalt", "carpet", "metal_plate"]

var layout := LightwellLayout.new()
var wall_support: WallSupport
var _floor_surfaces: Array[Dictionary] = []
var roofs: Array[Node3D] = []
var upper_floors: Array[Node3D] = []
var _footprint: Array[PackedVector2Array] = [] ## ground-floor room outlines, courtyard included
var _prep_barriers: Array[StaticBody3D] = []


func attack_zone_count() -> int:
	return layout.attack_zone_count()


func spawn_at(index: int, attack_zone: int = 0) -> Array:
	return layout.spawn_at(index, attack_zone)


func door_specs() -> Array:
	return layout.doors()


func match_tuning() -> MatchTuning:
	return layout.tuning()


func bot_nav_area() -> AABB:
	var d := layout.data
	var bb: Array = d.bounds
	return AABB(layout.world(bb[0],bb[1],-.35), Vector3(bb[2], float(d.deck) + 2.7, bb[3]))


func _build_level() -> void:
	var d := layout.data
	var ground: Array = d.bounds
	_plan_box("Ground", ground[0], ground[1], ground[2], ground[3], -.22, 0, "asphalt")
	for r: Dictionary in d.rooms:
		_build_room(r)
	for roof: Node3D in roofs:
		roof.add_to_group("navigation_exclude")
	for stair: Dictionary in d.stairs:
		_build_stairs(stair)
	var headers := {}
	var deck_heights := {}
	for c: Dictionary in layout.cells():
		var m := WallModule.new()
		var half: Vector3 = c.size * .5
		var center: Vector3 = c.center
		var prop: Dictionary = c.get("prop", {})
		var surface := "plaster"
		m.remove_whole = true
		m.impact_destructible = true
		m.bullet_breakable = not prop.is_empty()
		if m.bullet_breakable:
			surface = FURNISHINGS.material_key(prop.kind)
		m.setup(c.id, center - half, center + half, WallModule.Mat.ORDINARY, Surfaces.get_mat(surface))
		m.rotation.y = c.yaw
		m.set_meta("run", c.run)
		add_child(m)
		modules.append(m)
		if c.run >= 0:
			deck_heights[m] = layout.elevation(d.walls[c.run].level)
		if not prop.is_empty():
			FURNISHINGS.dress(m, prop.kind)
		elif m._size.y > 2.5:
			FURNISHINGS.add_baseboard(m)
		else:
			headers[c.id] = m
	_door_signs(headers)
	wall_support = WallSupport.new()
	add_child(wall_support)
	wall_support.setup(self, deck_heights)
	# Paint the finite staging boundary. Props and wall modules own their own collision.
	var edge := .12
	for p in [[ground[0],ground[1],ground[2],edge],
			[ground[0],ground[1]+ground[3]-edge,ground[2],edge],
			[ground[0],ground[1],edge,ground[3]],
			[ground[0]+ground[2]-edge,ground[1],edge,ground[3]]]:
		_plan_box("BoundaryStripe",p[0],p[1],p[2],p[3],.003,.009,"lamp_warm",false)
	for zone: Dictionary in d.attack_zones:
		var center: Array = zone.spawns[2]
		_floor_label(String(zone.name).to_upper(), center[0], center[1], .012, .7)
	_floor_label("EDGE — FALL HAZARD", float(d.size[0])*.5, ground[1] + ground[3] - 1, .012, .8)
	_lighting()
	_site_markings()
	_build_prep_barriers()


## The courtyard and every ground room count as inside; upper rooms sit above them.
func is_outside(pos: Vector3) -> bool:
	if pos.y > layout.elevation(2):
		return true
	for poly in _footprint:
		if Geometry2D.is_point_in_polygon(Vector2(pos.x, pos.z), poly):
			return false
	return true


func _build_prep_barriers() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, .55, .1, .22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for spec: Dictionary in layout.doors():
		if not spec.exterior:
			continue
		var along: Vector3 = spec.along
		var size := Vector3(float(spec.width), float(layout.data.door_height), .06)
		var body := StaticBody3D.new()
		body.name = "PrepBarrier"
		body.collision_layer = 0
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var quad := BoxMesh.new()
		quad.size = size
		mesh.mesh = quad
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mesh)
		add_child(body)
		body.position = spec.hinge + along * float(spec.width) * .5 + Vector3.UP * size.y * .5
		body.rotation.y = -atan2(along.z, along.x)
		body.visible = false
		_prep_barriers.append(body)


func set_prep_barriers(on: bool) -> void:
	for body in _prep_barriers:
		body.collision_layer = 1 if on else 0
		body.visible = on


func clear_wall_debris() -> void:
	if wall_support:
		wall_support.clear()


func _door_signs(headers: Dictionary) -> void:
	for spec: Dictionary in layout.doors():
		var m: WallModule = headers[spec.header]
		var rooms: Array = layout.data.walls[spec.run].rooms
		for side in [-1.0, 1.0]:
			var behind := m.position - m.face_normal() * float(side) * .22
			var destination := String(layout.data.walls[spec.run].get("sign", "EXTERIOR"))
			for room: Dictionary in layout.data.rooms:
				if int(room.level) == int(spec.level) and room.id in rooms and \
						Geometry2D.is_point_in_polygon(Vector2(behind.x,behind.z),layout.polygon(room)):
					destination = String(room.name).to_upper()
					break
			FURNISHINGS.add_sign(m, destination, side)


func _build_room(r: Dictionary) -> void:
	var y := layout.elevation(r.level)
	var poly := layout.polygon(r)
	var surface := int(r.surface)
	var radio := BotRadio.room_key(r.name) if str(r.radio).is_empty() else String(r.radio)
	_floor_surfaces.append({"poly": poly, "y": y, "surface": surface, "radio": radio, "stairs": r.kind == "stairs"})
	if int(r.level) == 0:
		_footprint.append(poly)
	if r.kind == "stairs":
		if int(r.level) == 1:
			roofs.append(_slab("StairRoof", poly, y + float(layout.data.wall_height), y + float(layout.data.deck) - .018, "ceiling", true))
		return
	if int(r.level) == 0:
		_slab("Floor", poly, -.02, .004, FLOOR_MATS[surface], false)
	else:
		var floor_node := _slab("UpperFloor", poly, y - .08, y, FLOOR_MATS[surface], true)
		upper_floors.append(floor_node)
	if r.kind != "yard":
		roofs.append(_slab("Ceiling", poly, y + float(layout.data.wall_height), y + float(layout.data.deck) - .018, "ceiling", true))
	_floor_label(str(r.name).to_upper(), r.label[0], r.label[1], y + .016, .8 if r.kind == "hall" else 1.0)
	if r.kind == "yard":
		return
	var light := OmniLight3D.new()
	light.position = layout.world(r.label[0], r.label[1], y + 2.45)
	light.light_color = OfficeSet.COOL if surface == 2 else OfficeSet.WARM
	light.light_energy = 1.15 if r.kind != "hall" else .85
	light.omni_range = 5.6
	add_child(light)
	_plan_box("CeilingLamp",r.label[0]-.43,r.label[1]-.12,.86,.24,y+2.72,y+2.78,
		"lamp_cool" if surface == 2 else "lamp_warm",false)


func _build_stairs(stair: Dictionary) -> void:
	if stair.get("kind", "") == "straight":
		_build_straight_stair(stair)
		return
	var p: Array = stair.rect
	var u := float(p[0])
	var v := float(p[1])
	var wide := float(p[2])
	var depth := float(p[3])
	var lane := wide * .5
	var upper := layout.elevation(1)
	var half := upper * .5
	var north := v + .77
	var south := v + depth - 1.52
	var first := u + lane * (.5 if stair.low_left else 1.5)
	var second := u + lane * (1.5 if stair.low_left else .5)
	var divider := u + lane
	for landing in [[first-lane*.5,v,lane,north-v,-.11,0.0],
			[second-lane*.5,v,lane,north-v,upper-.18,upper],
			[u,south,wide,v+depth-south,half-.18,half]]:
		var slab := _plan_box("StairLanding", landing[0],landing[1],landing[2],landing[3],landing[4],landing[5],"metal_plate")
		if landing[5] == upper:
			upper_floors.append(slab)
	_stair_flight(first, lane, north, south, 0, half)
	_stair_flight(second, lane, south, north, half, upper)
	# Open metal guardrails keep the switchback legible and protect the upper drop.
	var rail_a := layout.world(divider, north, upper + .44)
	var rail_b := layout.world(divider, south, half + .44)
	var guard := _beam("StairGuard", rail_a, rail_b, .085, .92, "painted_metal")
	# Thin collision envelope behind the visible rails protects the gaps.
	guard.get_child(1).visible = false
	for offset in [-.34, .36]:
		var raise := Vector3.UP * float(offset)
		_beam("StairHandrail", rail_a + raise, rail_b + raise, .075, .07, "painted_metal", false)
	for i in 5:
		var post := rail_a.lerp(rail_b, float(i)/5.0)
		_box("StairPost", post + Vector3(-.036,-.42,-.036), post + Vector3(.036,.42,.036), Surfaces.get_mat("painted_metal"), false)
	_plan_box("LandingGuard", divider-.045,v,.09,north-v,upper,upper+.95,"painted_metal")
	_floor_label(String(stair.name).to_upper(), first, v+.3, .02, .65)
	_floor_label(String(stair.name).to_upper(), second, v+.3, upper+.02, .65)
	var light := OmniLight3D.new()
	light.position = layout.world(divider, v+depth*.52, upper+1.65)
	light.light_color = OfficeSet.COOL
	light.light_energy = 1.8
	light.omni_range = 7.0
	add_child(light)


## One open flight from a ground-floor yard or the exterior to an upper doorway.
## Rails on both sides and around the top landing keep the drop guarded.
func _build_straight_stair(stair: Dictionary) -> void:
	var u := float(stair.u)
	var width := float(stair.width)
	var from := float(stair["from"])
	var to := float(stair.to)
	var upper := layout.elevation(1)
	var l: Array = stair.landing
	upper_floors.append(_plan_box("StairLanding", l[0], l[1], l[2], l[3], upper-.18, upper, "metal_plate"))
	_stair_flight(u, width, from, to, 0, upper)
	var toward := signf(to - from)
	var outer := float(l[1]) if toward > 0 else float(l[1]) + float(l[3])
	for side: float in [-1.0, 1.0]:
		var rail_u := u + side * (width * .5 + .05)
		var a := layout.world(rail_u, from + toward * .35, .48)
		var b := layout.world(rail_u, to, upper + .48)
		_beam("StairGuard", a, b, .085, .96, "painted_metal").get_child(1).visible = false
		_beam("StairHandrail", a + Vector3.UP * .4, b + Vector3.UP * .4, .075, .07, "painted_metal", false)
		# Side guards on the landing past the flight.
		var edge := float(l[0]) if side < 0 else float(l[0]) + float(l[2]) - .09
		_plan_box("LandingGuard", edge, l[1], .09, l[3], upper, upper+.95, "painted_metal")
	# Guard the landing's open edge on each side of the flight.
	var span_a := float(l[0])
	var span_b := float(l[0]) + float(l[2])
	for seg: Array in [[span_a, u - width*.5 - .05], [u + width*.5 + .05, span_b]]:
		var lo := float(seg[0])
		var hi := float(seg[1])
		if hi - lo > .05:
			_plan_box("LandingGuard", lo, outer if toward > 0 else outer - .09,
				hi - lo, .09, upper, upper+.95, "painted_metal")
	_floor_label(String(stair.name).to_upper(), u, from + toward * .4, .02, .6)
	var light := OmniLight3D.new()
	light.position = layout.world(u, (from + to) * .5, upper + 1.2)
	light.light_color = OfficeSet.COOL
	light.light_energy = 1.2
	light.omni_range = 6.0
	add_child(light)


func _stair_flight(u: float, width: float, from: float, to: float, bottom: float, top: float) -> void:
	var a := layout.world(u, from, bottom)
	var b := layout.world(u, to, top)
	var normal := (b - a).normalized().cross(Vector3.RIGHT) * signf(to - from)
	var body := _beam("StairSlope", a - normal*.11, b - normal*.11, width, .22, "metal_plate")
	body.set_meta("step_surface", 2)
	body.get_child(1).visible = false
	for i in 10:
		var start := lerpf(from,to,i/10.0)
		var end := lerpf(from,to,(i+1)/10.0)
		var y := lerpf(bottom,top,(i+.25)/10.0)
		_plan_box("StairTread",u-width*.5,minf(start,end),width,absf(end-start)+.015,
			y-.18,y,"metal_plate",false)
		_plan_box("TreadEdge",u-width*.5+.04,end-.024,width-.08,.048,y-.024,y+.006,"trim",false)


func _beam(label: String, a: Vector3, b: Vector3, width: float, height: float, key: String, collide: bool = true) -> Node3D:
	var size := Vector3(width,height,a.distance_to(b))
	var half := size * .5
	var node := _box(label, -half, half, Surfaces.get_mat(key), collide)
	var z := a.direction_to(b)
	var x := Vector3.UP.cross(z).normalized()
	node.transform = Transform3D(Basis(x,z.cross(x),z), (a+b)*.5)
	return node


func _slab(label: String, poly: PackedVector2Array, bottom: float, top: float, key: String, collide: bool) -> Node3D:
	var faces := Geometry2D.triangulate_polygon(poly)
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,faces.size(),3):
		var a := poly[faces[i]]
		var b := poly[faces[i+1]]
		var c := poly[faces[i+2]]
		if (b-a).cross(c-a) < 0.0:
			var temp := b
			b = c
			c = temp
		for p: Vector2 in [a,b,c]:
			_slab_vertex(mesh,p,top,Vector3.UP)
		for p: Vector2 in [a,c,b]:
			_slab_vertex(mesh,p,bottom,Vector3.DOWN)
	var clockwise := Geometry2D.is_polygon_clockwise(poly)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i+1) % poly.size()]
		if clockwise:
			var temp := b
			b = a
			a = temp
		var normal := Vector3(b.y - a.y, 0, a.x - b.x).normalized()
		_slab_vertex(mesh,a,bottom,normal)
		_slab_vertex(mesh,b,bottom,normal)
		_slab_vertex(mesh,b,top,normal)
		_slab_vertex(mesh,a,bottom,normal)
		_slab_vertex(mesh,b,top,normal)
		_slab_vertex(mesh,a,top,normal)
	mesh.set_material(Surfaces.get_mat(key))
	var instance := MeshInstance3D.new()
	instance.mesh = mesh.commit()
	# Triplanar office materials supply their own mapping and tangent basis.
	var node: Node3D = StaticBody3D.new() if collide else Node3D.new()
	node.name = label
	add_child(node)
	node.add_child(instance)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := instance.mesh.create_trimesh_shape()
		shape.backface_collision = true
		cs.shape = shape
		node.add_child(cs)
		node.set_meta("step_surface", FLOOR_MATS.find(key))
	return node


func _slab_vertex(mesh: SurfaceTool, p: Vector2, y: float, normal: Vector3) -> void:
	mesh.set_normal(normal)
	mesh.set_uv(p)
	mesh.add_vertex(Vector3(p.x,y,p.y))


func footstep_surface(pos: Vector3) -> int:
	for r: Dictionary in _floor_surfaces:
		if absf(pos.y - r.y) < .14 and Geometry2D.is_point_in_polygon(Vector2(pos.x,pos.z),r.poly):
			return r.surface
	return super.footstep_surface(pos)


func radio_room(pos: Vector3) -> String:
	for r: Dictionary in _floor_surfaces:
		if (absf(pos.y - r.y) < .25 or (r.stairs and pos.y < layout.elevation(1) + .25)) 				and Geometry2D.is_point_in_polygon(Vector2(pos.x,pos.z),r.poly):
			return r.radio
	return "outside"


func _plan_box(label: String, u: float, v: float, w: float, h: float, bottom: float, top: float, surface: String, collision: bool = true) -> Node3D:
	return _box(label, layout.world(u, v, bottom), layout.world(u + w, v + h, top), Surfaces.get_mat(surface), collision)


func _floor_label(text: String, u: float, v: float, y: float, scale_factor: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 72
	label.pixel_size = .0034 * scale_factor
	label.rotation_degrees.x = -90
	label.position = layout.world(u, v, y)
	label.modulate = Color(.73,.8,.78)
	label.outline_size = 0
	add_child(label)


func _site_markings() -> void:
	var tuning := match_tuning()
	for i in tuning.site_areas.size():
		var site := tuning.sites[i]
		var y := site.y - .036
		var borders := Geometry2D.offset_polygon(tuning.site_areas[i].polygon, -.23)
		var paint := MeshInstance3D.new()
		var mesh := SurfaceTool.new()
		mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
		mesh.set_material(Surfaces.get_mat("lamp_cool" if i == 0 else "lamp_warm"))
		for border: PackedVector2Array in borders:
			for n in border.size():
				var a := border[n]
				var b := border[(n + 1) % border.size()]
				var width := (b - a).normalized().orthogonal() * .035
				for point: Vector2 in [a - width, b + width, b - width, a - width, a + width, b + width]:
					mesh.set_normal(Vector3.UP)
					mesh.add_vertex(Vector3(point.x, y, point.y))
		paint.mesh = mesh.commit()
		paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(paint)
		if int(layout.data.sites[i][2]) > 0:
			upper_floors.append(paint)
		_floor_label(["A", "B"][i], layout.data.sites[i][0], layout.data.sites[i][1], y + .002, 2.0)


func _lighting() -> void:
	var env: WorldEnvironment = get_node("WorldEnvironment")
	env.environment.ambient_light_energy = .73
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = OfficeSet.COOL
	moon.light_energy = .62
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 75
	moon.rotation_degrees = Vector3(-58, -30, 0)
	add_child(moon)


func _build_cameras() -> void:
	for view: Array in layout.data.views:
		var y := layout.elevation(view[5])
		var camera := Camera3D.new()
		camera.name = view[0]
		camera.position = layout.world(view[1], view[2], y + 1.65)
		add_child(camera)
		camera.look_at(layout.world(view[3], view[4], y + 1.22))
		_cams.append(camera)

func _start_tools() -> bool:
	if net_mode and NetworkManager.args.has("capture-feedback"):
		var capture := preload("res://scripts/tools/feedback_capture.gd").new()
		add_child(capture)
		capture.start(self)
	elif net_mode and NetworkManager.args.has("bot-test"):
		player.scripted = true
		loadout.bot = true
		var bot_test := preload("res://scripts/tools/bot_test.gd").new()
		add_child(bot_test)
		bot_test.start(self)
	elif net_mode and NetworkManager.args.has("net-test"):
		player.scripted = true
		loadout.bot = true
		loadout.use_recoil = false
		var test := preload("res://scripts/tools/lightwell_net_test.gd").new()
		add_child(test)
		test.start(self)
	elif NetworkManager.args.has("smoke-destruction"):
		player.scripted = true
		var test := preload("res://scripts/tools/destruction_test.gd").new()
		add_child(test)
		test.start(self)
	elif NetworkManager.args.has("smoke-lightwell"):
		player.scripted = true
		var test := preload("res://scripts/tools/lightwell_test.gd").new()
		add_child(test)
		test.start(self)
	elif NetworkManager.args.has("capture-lightwell"):
		player.scripted = true
		var capture := preload("res://scripts/tools/lightwell_capture.gd").new()
		add_child(capture)
		capture.start(self)
	else:
		return false
	return true

func _process(delta: float) -> void:
	super._process(delta)
	if not net_mode and player.global_position.y < -4:
		restart()
	if not net_mode:
		_hud.text += "\nLIGHTWELL · A Server / B North Office (upstairs) · Upper offices via Staff, Courtyard and exterior Fire stairs · F8 resets"
