extends Node3D
## Session 02 graybox: corridor + adjacent room at human scale (1 unit = 1 m).
## Corridor x[-1.5,1.4], z[-13,0]; divider wall (centre x=1.5) with doorway, window, reinforced section;
## room x[1.6,9.5], z[-9,-2]; low-ceiling duct (1.5 m) from z=-10.5 to the corridor end (standing blocked, crouch passes).
## F1-F3 fixed comparison cameras, F4 back to player, R reset, Esc releases the mouse.
## Headless test: godot --headless --path game res://scenes/graybox.tscn -- --smoke-graybox

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CEIL := 2.8
const DUCT_Z := -10.5 ## bulkhead face; ceiling drops to DUCT_H beyond it
const DUCT_H := 1.5
const ORDINARY := Color(0.55, 0.52, 0.48)
const REINFORCED := Color(0.28, 0.32, 0.38)

var player: Player
var _spawn: Marker3D
var _cams: Array[Camera3D] = []
var _hud: Label
var _panel: PanelContainer
var _sens: HSlider
var _fov: HSlider
var _fails := 0


func _ready() -> void:
	_build_environment()
	_build_level()
	_spawn = Marker3D.new()
	_spawn.name = "PlayerSpawn"
	_spawn.position = Vector3(0, 0.05, -1.0)
	add_child(_spawn)
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_transform = _spawn.global_transform
	player.spawn_transform = _spawn.global_transform
	_build_cameras()
	_build_ui()
	var smoke: bool = NetworkManager.args.has("smoke-graybox")
	if smoke:
		player.scripted = true
		_run_smoke()
	else:
		player.mouse_capture_changed.connect(_on_capture)
		player.capture_mouse(true)


# ---------------------------------------------------------------- level

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.environment.ambient_light_energy = 0.6
	add_child(env)


func _build_level() -> void:
	var floor_c := Color(0.32, 0.32, 0.35)
	var ceil_c := Color(0.62, 0.62, 0.64)
	_box("Floor", Vector3(-1.7, -0.2, -13.2), Vector3(9.7, 0.0, 0.2), floor_c)
	# Ceilings: corridor, room, and the low duct (bulkhead + low slab).
	_box("CeilingCorridor", Vector3(-1.5, CEIL, DUCT_Z), Vector3(1.5, CEIL + 0.2, 0.0), ceil_c)
	_box("CeilingRoom", Vector3(1.5, CEIL, -9.0), Vector3(9.5, CEIL + 0.2, -2.0), ceil_c)
	_box("DuctCeiling", Vector3(-1.5, DUCT_H, -13.0), Vector3(1.5, CEIL + 0.2, DUCT_Z), ceil_c)
	# Corridor end caps and west wall.
	_wall_z("CorridorStart", 0.0, -1.5, 1.5, 0.2, 0.0, CEIL, ORDINARY)
	_wall_z("CorridorEnd", -13.1, -1.5, 1.5, 0.2, 0.0, CEIL, ORDINARY)
	_wall_x("CorridorWest", -1.6, 0.0, -13.0, 0.2, 0.0, CEIL, ORDINARY)
	# Divider at x=1.5: ordinary, reinforced, doorway, window.
	_wall_x("Divider_A_ordinary", 1.5, 0.0, -2.0, 0.2, 0.0, CEIL, ORDINARY)
	_wall_x("Divider_B_reinforced", 1.5, -2.0, -3.5, 0.34, 0.0, CEIL, REINFORCED)
	_wall_x("Doorway_lintel", 1.5, -3.5, -4.5, 0.2, 2.1, CEIL, ORDINARY)
	_wall_x("Divider_C_ordinary", 1.5, -4.5, -6.3, 0.2, 0.0, CEIL, ORDINARY)
	_wall_x("Window_sill", 1.5, -6.3, -7.5, 0.2, 0.0, 1.0, ORDINARY)
	_wall_x("Window_lintel", 1.5, -6.3, -7.5, 0.2, 2.0, CEIL, ORDINARY)
	_wall_x("Divider_D_ordinary", 1.5, -7.5, -13.0, 0.2, 0.0, CEIL, ORDINARY)
	# Room walls: north, east, south (with a reinforced section).
	_wall_z("Room_north", -2.0, 1.6, 9.6, 0.2, 0.0, CEIL, ORDINARY)
	_wall_x("Room_east", 9.6, -2.0, -9.0, 0.2, 0.0, CEIL, ORDINARY)
	_wall_z("Room_south_W", -9.0, 1.6, 4.0, 0.2, 0.0, CEIL, ORDINARY)
	_wall_z("Room_south_reinforced", -9.0, 4.0, 6.0, 0.34, 0.0, CEIL, REINFORCED)
	_wall_z("Room_south_E", -9.0, 6.0, 9.6, 0.2, 0.0, CEIL, ORDINARY)
	# Scale references: 1.8 m figure in the room, 1.0 m crate.
	_box("ScaleFigure_1.8m", Vector3(7.0, 0.0, -5.0), Vector3(7.5, 1.8, -5.5), Color(0.85, 0.45, 0.15))
	_box("Crate_1.0m", Vector3(4.0, 0.0, -3.0), Vector3(5.0, 1.0, -4.0), Color(0.5, 0.38, 0.25))
	# Warm practical lights (no GI, per architecture notes).
	_light(Vector3(0, 2.5, -3), 7.0)
	_light(Vector3(0, 2.5, -8), 7.0)
	_light(Vector3(5.5, 2.5, -5.5), 10.0)
	_light(Vector3(0, 1.3, -12), 4.0)


## Wall running along Z at fixed x (centre line), spanning z0..z1.
func _wall_x(wall_name: String, x: float, z0: float, z1: float, thick: float, y0: float, y1: float, col: Color) -> void:
	_box(wall_name, Vector3(x - thick * 0.5, y0, z1), Vector3(x + thick * 0.5, y1, z0), col)


## Wall running along X at fixed z (centre line), spanning x0..x1.
func _wall_z(wall_name: String, z: float, x0: float, x1: float, thick: float, y0: float, y1: float, col: Color) -> void:
	_box(wall_name, Vector3(x0, y0, z - thick * 0.5), Vector3(x1, y1, z + thick * 0.5), col)


## Axis-aligned box from min corner a to max corner b (any order); static collision + mesh.
func _box(box_name: String, a: Vector3, b: Vector3, col: Color) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var size := hi - lo
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = (lo + hi) * 0.5
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)


func _light(pos: Vector3, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = rng
	l.light_color = Color(1.0, 0.86, 0.65)
	l.light_energy = 1.2
	add_child(l)


# ---------------------------------------------------------------- cameras / UI

func _build_cameras() -> void:
	var defs := [
		["Cam_CorridorLong", Vector3(0, 1.65, -0.5), Vector3(0, 1.4, -13.0)],
		["Cam_DoorwayView", Vector3(-1.0, 1.65, -4.0), Vector3(5.0, 1.2, -4.0)],
		["Cam_RoomOverview", Vector3(9.0, 2.4, -2.5), Vector3(3.0, 0.9, -7.0)],
	]
	for d in defs:
		var c := Camera3D.new()
		c.name = d[0]
		c.fov = 90.0
		add_child(c)
		c.global_position = d[1]
		c.look_at(d[2])
		_cams.append(c)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_hud)
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 120)
	layer.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	_panel.add_child(box)
	var t := Label.new()
	t.text = "Paused — click empty space or Resume to capture mouse"
	box.add_child(t)
	_sens = _slider(box, "Sensitivity", 0.1, 3.0, player.look_sensitivity, func(v: float) -> void:
		player.look_sensitivity = v
		player.save_settings())
	_fov = _slider(box, "FOV", player.tuning.min_fov, player.tuning.max_fov, player.fov, func(v: float) -> void:
		player.set_fov(v)
		player.save_settings())
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func() -> void: player.capture_mouse(true))
	box.add_child(resume)
	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(func() -> void:
		player.capture_mouse(false)
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	box.add_child(back)
	_panel.visible = false


func _slider(parent: Control, label: String, lo: float, hi: float, value: float, cb: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(190, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(cb)
	row.add_child(s)
	parent.add_child(row)
	return s


func _on_capture(captured: bool) -> void:
	_panel.visible = not captured
	if not captured:
		_sens.set_value_no_signal(player.look_sensitivity)
		_fov.set_value_no_signal(player.fov)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).physical_keycode
	if k >= KEY_F1 and k <= KEY_F3:
		_cams[k - KEY_F1].make_current()
		player.input_enabled = false
	elif k == KEY_F4:
		player.camera.make_current()
		player.input_enabled = true


func _process(_delta: float) -> void:
	var v := player.velocity
	_hud.text = "WASD move · Shift sprint · C crouch (hold) · R reset · Esc mouse · F1-F3 cameras, F4 player\nspeed %.1f m/s  %s  height %.2f m  FOV %.0f" % [
		Vector2(v.x, v.z).length(), "CROUCHED" if player.crouched else "standing", player.height, player.fov]


# ---------------------------------------------------------------- headless smoke test

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("  PASS " if ok else "  FAIL ") + label + (" " + detail if detail != "" else ""))
	if not ok:
		_fails += 1


func _run_smoke() -> void:
	var t := get_tree().create_timer(60.0)
	t.timeout.connect(func() -> void:
		print("SMOKE_FAIL graybox timeout")
		get_tree().quit(1))
	await _frames(10)
	_check("spawns on floor", player.is_on_floor(), str(player.global_position))

	# Intact walls hold: strafe into east (ordinary, z=-1) and west walls.
	player.script_move = Vector2(1, 0)
	await _frames(120)
	_check("east wall blocks", player.global_position.x < 1.1, "x=%.2f" % player.global_position.x)
	player.script_move = Vector2(-1, 0)
	await _frames(240)
	_check("west wall blocks", player.global_position.x > -1.2, "x=%.2f" % player.global_position.x)

	player.script_move = Vector2.ZERO
	player.global_position.x = 0.7
	player.reset()
	await _frames(5)
	_check("reset returns to spawn", player.global_position.distance_to(_spawn.global_position) < 0.1)

	# Standing is blocked at the low duct.
	player.script_move = Vector2(0, -1)
	await _frames(300)
	_check("standing blocked by low ceiling", player.global_position.z > -10.4 and not player.crouched,
		"z=%.2f" % player.global_position.z)

	# Crouch passes under it.
	player.script_crouch = true
	await _frames(30)
	await _frames(120)
	_check("crouch passes under duct", player.global_position.z < -11.0 and player.global_position.z > -13.0,
		"z=%.2f h=%.2f" % [player.global_position.z, player.height])

	# Releasing crouch under the duct must not stand up through the ceiling.
	player.script_move = Vector2.ZERO
	player.script_crouch = false
	await _frames(40)
	_check("stays crouched under ceiling", player.crouched and player.height < 1.3, "h=%.2f" % player.height)
	player.script_move = Vector2(0, 1)
	await _frames(150)
	await _frames(40)
	_check("stands again once clear", not player.crouched and absf(player.height - 1.8) < 0.01,
		"z=%.2f h=%.2f" % [player.global_position.z, player.height])

	# Doorway is passable; reinforced section and window sill are not.
	player.script_move = Vector2(0, -1)
	player.teleport(Vector3(0, 0.05, -4.0), -90.0)
	await _frames(100)
	_check("doorway passable", player.global_position.x > 3.0, "x=%.2f" % player.global_position.x)
	player.teleport(Vector3(0, 0.05, -2.75), -90.0)
	await _frames(100)
	_check("reinforced section blocks", player.global_position.x < 1.1, "x=%.2f" % player.global_position.x)
	player.teleport(Vector3(0, 0.05, -6.9), -90.0)
	await _frames(100)
	_check("window sill blocks walking", player.global_position.x < 1.1, "x=%.2f" % player.global_position.x)

	# Camera/eye height sanity.
	player.script_move = Vector2.ZERO
	player.reset()
	await _frames(5)
	var eye := player.camera.global_position.y - player.global_position.y
	_check("standing eye height ~1.65 m", absf(eye - 1.65) < 0.02, "eye=%.2f" % eye)

	if _fails == 0:
		print("SMOKE_OK graybox")
		get_tree().quit(0)
	else:
		print("SMOKE_FAIL graybox failures=", _fails)
		get_tree().quit(1)
