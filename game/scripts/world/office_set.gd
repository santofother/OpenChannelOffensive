class_name OfficeSet
extends RefCounted
## Session 04 look for the graybox office: environment, practical lights, restrained dressing and the night exterior.
## Lighting is fully dynamic (no baking), so breached walls light and shadow correctly with no extra work.
## Budget: 4 shadowed spot lights + 1 shadowed moon; everything else unshadowed. Dressing has no
## collision unless it is something a player would bump into (desks, chairs, cabinets, plants).
## `g` is the graybox scene; its _box(name, a, b, mat, collide) helper builds every box.

const WARM := Color(1.0, 0.79, 0.56)
const COOL := Color(0.62, 0.72, 1.0)


static func build_environment(g: Node3D) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.015, 0.02, 0.045)
	sm.sky_horizon_color = Color(0.08, 0.1, 0.15)
	sm.ground_horizon_color = Color(0.05, 0.06, 0.08)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.015)
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	g.add_child(we)


static func build_lights(g: Node3D) -> void:
	# Corridor: two warm ceiling downlights (shadowed) with soft unshadowed fill.
	for z in [-2.5, -7.2]:
		_fixture(g, Vector3(0, 2.79, z), Vector2(0.6, 0.6), "lamp_warm")
		_spot(g, "CorridorLamp", Vector3(0, 2.72, z), Vector3(-90, 0, 0), WARM, 3.2, 6.0, 80.0, true)
		_omni(g, Vector3(0, 2.3, z), WARM, 0.35, 5.0)
	# Duct: caged bulkhead lamp.
	_deco(g, "DuctLamp", Vector3(-1.5, 1.08, -11.68), Vector3(-1.38, 1.22, -11.52), "lamp_warm")
	_omni(g, Vector3(-1.2, 1.15, -11.6), WARM, 0.9, 3.2)
	# Room: one warm ceiling light and the desk lamp.
	_fixture(g, Vector3(5.5, 2.79, -4.5), Vector2(1.2, 0.3), "lamp_warm")
	_spot(g, "RoomLamp", Vector3(5.5, 2.72, -4.5), Vector3(-90, 0, 0), WARM, 4.0, 7.0, 95.0, true)
	_omni(g, Vector3(5.5, 2.2, -5.5), WARM, 0.6, 7.0)
	_spot(g, "DeskLamp", Vector3(2.75, 1.1, -8.49), Vector3(-65, -20, 0), WARM, 3.0, 3.0, 50.0, true)
	# Moonlight from the east through the exterior windows.
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = COOL
	moon.light_energy = 0.5
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 40.0
	g.add_child(moon)
	moon.basis = Basis.looking_at(Vector3(-1.0, -0.72, 0.3).normalized())


static func build_dressing(g: Node3D) -> void:
	var trim := "trim"
	# Baseboards on non-breachable runs only (a floating skirting strip after a breach would look wrong).
	if not g.net_mode:
		_deco(g, "Base_CorridorW", Vector3(-1.5, 0, -0.1), Vector3(-1.48, 0.1, -13.0), trim)
		_deco(g, "Base_DividerA", Vector3(1.38, 0, -0.1), Vector3(1.4, 0.1, -2.0), trim)
		_deco(g, "Base_DividerD2", Vector3(1.38, 0, -9.0), Vector3(1.4, 0.1, -10.5), trim)
	# Doorway frame (z -3.5..-4.5, h 2.1) and interior window frame (z -6.3..-7.5, y 1..2).
	_frame(g, "DoorFrame", 1.5, -3.5, -4.5, 0.0, 2.1, false)
	_frame(g, "WindowFrame", 1.5, -6.3, -7.5, 0.0 if g.net_mode else 1.0, 2.0, not g.net_mode)
	# Corridor: notice board, vent, plant.
	_deco(g, "NoticeFrame", Vector3(-1.5, 1.0, -4.2), Vector3(-1.47, 1.9, -5.6), trim)
	_deco(g, "NoticeCork", Vector3(-1.47, 1.04, -4.24), Vector3(-1.46, 1.86, -5.56), "cork")
	for p in [[-4.4, 1.5], [-4.85, 1.35], [-5.25, 1.55]]:
		_deco(g, "Paper", Vector3(-1.46, p[1] - 0.14, p[0]), Vector3(-1.455, p[1] + 0.14, p[0] - 0.21), "paper")
	_deco(g, "CorridorVent", Vector3(-0.25, 2.785, -4.75), Vector3(0.25, 2.8, -5.25), trim)
	_plant(g, Vector3(-1.15, 0, -6.4))
	# Room: two desks with monitors and chairs along the south wall, cabinets, whiteboard, plant, blinds.
	_desk(g, "DeskA", 2.4, true)
	_desk(g, "DeskB", 5.6, false)
	_cabinet(g, "CabinetA", -2.15)
	_cabinet(g, "CabinetB", -2.67)
	_deco(g, "WhiteboardFrame", Vector3(4.5, 1.0, -2.1), Vector3(6.5, 2.0, -2.13), trim)
	_deco(g, "Whiteboard", Vector3(4.53, 1.03, -2.13), Vector3(6.47, 1.97, -2.135), "paper")
	_plant(g, Vector3(9.1, 0, -8.55))
	for i in 11:
		var y := 2.25 - i * 0.06
		var s: Node3D = _deco(g, "BlindSlat", Vector3(9.40, y - 0.005, -3.05), Vector3(9.44, y + 0.005, -4.62), "painted_metal")
		s.rotation.z = deg_to_rad(25)


static func build_exterior(g: Node3D) -> void:
	g._box("ExtGround", Vector3(9.7, -0.5, -40.0), Vector3(50.0, -0.3, 25.0), Surfaces.get_mat("asphalt"))
	g._box("ExtFoundation", Vector3(9.7, -0.3, -9.2), Vector3(9.8, 0.0, -1.8), Surfaces.get_mat("plaster"))
	# Warehouse across the yard with a warm door lamp.
	g._box("Warehouse", Vector3(28.0, -0.3, -32.0), Vector3(42.0, 8.0, 4.0), Surfaces.get_mat("siding"))
	g._box("WarehouseDoor", Vector3(27.95, -0.3, -13.5), Vector3(28.0, 2.4, -11.5), Surfaces.get_mat("trim"), false)
	_deco(g, "WarehouseLamp", Vector3(27.8, 2.7, -12.7), Vector3(28.0, 2.85, -12.3), "lamp_warm")
	_omni(g, Vector3(27.5, 2.6, -12.5), WARM, 1.5, 6.0)
	# Fence line.
	for i in 15:
		var z := 10.0 - i * 2.5
		g._box("FencePost", Vector3(19.0, -0.3, z), Vector3(19.07, 2.2, z - 0.07), Surfaces.get_mat("painted_metal"), false)
	for y in [0.4, 2.1]:
		g._box("FenceRail", Vector3(19.0, y, 10.0), Vector3(19.05, y + 0.05, -25.0), Surfaces.get_mat("painted_metal"), false)
	# Street light (cool LED).
	g._box("LightPole", Vector3(15.0, -0.3, -5.0), Vector3(15.15, 6.5, -5.15), Surfaces.get_mat("painted_metal"), false)
	g._box("LightArm", Vector3(13.8, 6.35, -5.03), Vector3(15.0, 6.45, -5.12), Surfaces.get_mat("painted_metal"), false)
	_deco(g, "LightHead", Vector3(13.6, 6.25, -4.95), Vector3(14.2, 6.33, -5.2), "lamp_cool")
	_spot(g, "StreetLight", Vector3(13.9, 6.2, -5.07), Vector3(-90, 0, 0), Color(0.85, 0.9, 1.0), 6.0, 14.0, 60.0, false)
	# Parked van silhouette.
	g._box("Van", Vector3(23.0, 0.0, -17.0), Vector3(25.0, 2.1, -22.0), Surfaces.get_mat("painted_metal"), true)
	g._box("VanWheels", Vector3(22.95, -0.3, -17.6), Vector3(25.05, 0.05, -21.4), Surfaces.get_mat("plastic"), false)


# ---------------------------------------------------------------- pieces

static func _deco(g: Node3D, n: String, a: Vector3, b: Vector3, mat: String) -> Node3D:
	return g._box(n, a, b, Surfaces.get_mat(mat), false)


static func _fixture(g: Node3D, centre: Vector3, size: Vector2, mat: String) -> void:
	var h := Vector3(size.x * 0.5, 0.01, size.y * 0.5)
	_deco(g, "Fixture", centre - h, centre + h, mat)


static func _spot(g: Node3D, n: String, pos: Vector3, rot_deg: Vector3, col: Color, energy: float, rng: float,
		angle: float, shadow: bool) -> void:
	var l := SpotLight3D.new()
	l.name = n
	l.position = pos
	l.rotation_degrees = rot_deg
	l.light_color = col
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle * 0.5
	l.spot_angle_attenuation = 0.8
	l.shadow_enabled = shadow
	l.shadow_blur = 1.5
	g.add_child(l)


static func _omni(g: Node3D, pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	g.add_child(l)


## Trim around an opening in the x = `x` divider (both faces), spanning z0..z1 and y0..y1.
static func _frame(g: Node3D, n: String, x: float, z0: float, z1: float, y0: float, y1: float, sill: bool) -> void:
	var t := 0.06
	var x0 := x - 0.13
	var x1 := x + 0.13
	_deco(g, n + "_J0", Vector3(x0, y0, z0), Vector3(x1, y1 + t, z0 - t), "trim")
	_deco(g, n + "_J1", Vector3(x0, y0, z1 + t), Vector3(x1, y1 + t, z1), "trim")
	_deco(g, n + "_Head", Vector3(x0, y1, z0), Vector3(x1, y1 + t, z1), "trim")
	if sill:
		_deco(g, n + "_Sill", Vector3(x0 - 0.04, y0 - 0.03, z0), Vector3(x1 + 0.04, y0 + 0.02, z1), "trim")


static func _desk(g: Node3D, n: String, x0: float, lamp: bool) -> void:
	var x1 := x0 + 1.8
	g._box(n, Vector3(x0, 0, -8.85), Vector3(x1, 0.76, -8.1), null)
	_deco(g, n + "_Top", Vector3(x0, 0.72, -8.85), Vector3(x1, 0.76, -8.1), "wood")
	_deco(g, n + "_SideL", Vector3(x0 + 0.02, 0, -8.82), Vector3(x0 + 0.06, 0.72, -8.13), "painted_metal")
	_deco(g, n + "_SideR", Vector3(x1 - 0.06, 0, -8.82), Vector3(x1 - 0.02, 0.72, -8.13), "painted_metal")
	_deco(g, n + "_Modesty", Vector3(x0 + 0.06, 0.3, -8.82), Vector3(x1 - 0.06, 0.7, -8.8), "painted_metal")
	var mx := x0 + 0.95
	_deco(g, n + "_MonStand", Vector3(mx - 0.03, 0.76, -8.62), Vector3(mx + 0.03, 0.95, -8.58), "plastic")
	_deco(g, n + "_MonBase", Vector3(mx - 0.11, 0.76, -8.68), Vector3(mx + 0.11, 0.775, -8.52), "plastic")
	_deco(g, n + "_Monitor", Vector3(mx - 0.29, 0.92, -8.6), Vector3(mx + 0.29, 1.27, -8.57), "plastic")
	_deco(g, n + "_Screen", Vector3(mx - 0.27, 0.94, -8.57), Vector3(mx + 0.27, 1.25, -8.566), "screen")
	_deco(g, n + "_Keyboard", Vector3(mx - 0.22, 0.76, -8.38), Vector3(mx + 0.22, 0.78, -8.24), "plastic")
	if lamp:
		_deco(g, n + "_LampBase", Vector3(x0 + 0.2, 0.76, -8.6), Vector3(x0 + 0.34, 0.78, -8.46), "plastic")
		_deco(g, n + "_LampArm", Vector3(x0 + 0.26, 0.78, -8.55), Vector3(x0 + 0.28, 1.12, -8.52), "plastic")
		_deco(g, n + "_LampHead", Vector3(x0 + 0.27, 1.08, -8.56), Vector3(x0 + 0.43, 1.16, -8.42), "lamp_warm")
	# Chair facing the desk.
	var cx := mx
	g._box(n + "_Chair", Vector3(cx - 0.25, 0, -7.85), Vector3(cx + 0.25, 1.0, -7.35), null)
	_deco(g, n + "_ChairSeat", Vector3(cx - 0.25, 0.42, -7.85), Vector3(cx + 0.25, 0.5, -7.35), "fabric_dark")
	_deco(g, n + "_ChairBack", Vector3(cx - 0.23, 0.55, -7.4), Vector3(cx + 0.23, 1.05, -7.34), "fabric_dark")
	_deco(g, n + "_ChairPost", Vector3(cx - 0.03, 0.06, -7.63), Vector3(cx + 0.03, 0.42, -7.57), "plastic")
	_deco(g, n + "_ChairFoot", Vector3(cx - 0.28, 0.0, -7.63), Vector3(cx + 0.28, 0.06, -7.57), "plastic")
	_deco(g, n + "_ChairFoot2", Vector3(cx - 0.03, 0.0, -7.88), Vector3(cx + 0.03, 0.06, -7.32), "plastic")


static func _cabinet(g: Node3D, n: String, z0: float) -> void:
	g._box(n, Vector3(8.95, 0, z0), Vector3(9.45, 1.32, z0 - 0.5), Surfaces.get_mat("painted_metal"))
	for i in 4:
		var y := 0.04 + i * 0.32
		_deco(g, n + "_Drawer", Vector3(8.94, y + 0.24, z0 - 0.2), Vector3(8.95, y + 0.27, z0 - 0.3), "trim")


static func _plant(g: Node3D, base: Vector3) -> void:
	g._box("Plant", base + Vector3(-0.2, 0, 0.2), base + Vector3(0.2, 0.45, -0.2), null)
	var root := Node3D.new()
	root.name = "PlantMesh"
	root.position = base
	g.add_child(root)
	var pot := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.18
	c.bottom_radius = 0.14
	c.height = 0.4
	pot.mesh = c
	pot.material_override = Surfaces.get_mat("plastic")
	pot.position.y = 0.2
	root.add_child(pot)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.x * 100.0 + base.z)
	for i in 7:
		var leaf := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = rng.randf_range(0.14, 0.22)
		s.height = s.radius * 1.2
		s.radial_segments = 10
		s.rings = 5
		leaf.mesh = s
		leaf.material_override = Surfaces.get_mat("foliage")
		leaf.position = Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.6, 1.15), rng.randf_range(-0.15, 0.15))
		root.add_child(leaf)
