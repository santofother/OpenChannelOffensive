extends Node3D
## Session 02 graybox: corridor + adjacent room at human scale (1 unit = 1 m).
## Corridor x[-1.5,1.4], z[-13,0]; divider wall (centre x=1.5) with doorway, window, reinforced section;
## room x[1.6,9.5], z[-9,-2]; low-ceiling duct (1.5 m) from z=-10.5 to the corridor end (standing blocked, crouch passes).
## F1-F3 fixed comparison cameras, F4 back to player, T restart, Esc releases the mouse.
## Session 04: PBR palette (Surfaces), lighting/dressing/exterior (OfficeSet), viewmodel, --capture / --bench (SliceBench).
## Session 03: divider modules B (reinforced), C and D1 (ordinary) are breachable WallModules; practice targets in the room.
## Keys: 1/2/3 rifle/ordinary charge/heavy charge, LMB fire/place, RMB aim, R reload, T restart (full reset).
## Evidence (windowed): -- --capture[=dir] | --bench[=secs] [--bench-out=path] [--vsync]
## Headless tests: godot --headless --path game res://scenes/graybox.tscn -- --smoke-graybox | --smoke-combat

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CEIL := 2.8
const DUCT_Z := -10.5 ## bulkhead face; ceiling drops to DUCT_H beyond it
const DUCT_H := 1.5

const WEAPON_TUNING := preload("res://data/weapon_tuning.tres")

var player: Player
var loadout: Loadout
var modules: Array[WallModule] = []
var targets: Array[PracticeTarget] = []
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
	player.reset_requested.connect(restart)
	_build_cameras()
	_build_ui()
	loadout = Loadout.new()
	loadout.name = "Loadout"
	add_child(loadout)
	loadout.setup(player, self, WEAPON_TUNING.duplicate())
	for m in modules:
		m.state_changed.connect(loadout.on_module_changed)
	if NetworkManager.args.has("smoke-graybox"):
		player.scripted = true
		_run_smoke()
	elif NetworkManager.args.has("smoke-combat"):
		player.scripted = true
		_run_smoke_combat()
	elif NetworkManager.args.has("capture") or NetworkManager.args.has("bench"):
		var bench := SliceBench.new()
		bench.name = "SliceBench"
		add_child(bench)
		bench.start(self)
	else:
		player.mouse_capture_changed.connect(_on_capture)
		player.capture_mouse(true)


# ---------------------------------------------------------------- level

func _build_environment() -> void:
	OfficeSet.build_environment(self)


func _build_level() -> void:
	var ORDINARY := Surfaces.get_mat("plaster")
	var REINFORCED := Surfaces.get_mat("metal_plate")
	_box("Floor", Vector3(-1.7, -0.2, -13.2), Vector3(9.7, 0.0, 0.2), Surfaces.get_mat("carpet"))
	# Ceilings: corridor, room, and the low duct (bulkhead + low slab). Roof seals everything from moonlight.
	var ceil_m := Surfaces.get_mat("ceiling")
	_box("CeilingCorridor", Vector3(-1.5, CEIL, DUCT_Z), Vector3(1.5, CEIL + 0.2, 0.0), ceil_m)
	_box("CeilingRoom", Vector3(1.5, CEIL, -9.1), Vector3(9.6, CEIL + 0.2, -1.9), ceil_m)
	_box("DuctCeiling", Vector3(-1.5, DUCT_H, -13.0), Vector3(1.5, CEIL + 0.2, DUCT_Z), ORDINARY)
	_box("Roof", Vector3(-1.8, CEIL + 0.2, -13.3), Vector3(9.8, CEIL + 0.4, 0.3), Surfaces.get_mat("trim"))
	# Corridor end caps and west wall.
	_wall_z("CorridorStart", 0.0, -1.5, 1.5, 0.2, 0.0, CEIL, ORDINARY)
	_wall_z("CorridorEnd", -13.1, -1.5, 1.5, 0.2, 0.0, CEIL, ORDINARY)
	_wall_x("CorridorWest", -1.6, 0.0, -13.0, 0.2, 0.0, CEIL, ORDINARY)
	# Divider at x=1.5: ordinary, reinforced, doorway, window.
	_wall_x("Divider_A_ordinary", 1.5, 0.0, -2.0, 0.2, 0.0, CEIL, ORDINARY)
	_wall_x("Divider_B_reinforced", 1.5, -2.0, -3.5, 0.34, 0.0, CEIL, REINFORCED, WallModule.Mat.REINFORCED)
	_wall_x("Doorway_lintel", 1.5, -3.5, -4.5, 0.2, 2.1, CEIL, ORDINARY)
	_wall_x("Divider_C_ordinary", 1.5, -4.5, -6.3, 0.2, 0.0, CEIL, ORDINARY, WallModule.Mat.ORDINARY)
	_wall_x("Window_sill", 1.5, -6.3, -7.5, 0.2, 0.0, 1.0, ORDINARY)
	_wall_x("Window_lintel", 1.5, -6.3, -7.5, 0.2, 2.0, CEIL, ORDINARY)
	_wall_x("Divider_D1_ordinary", 1.5, -7.5, -9.0, 0.2, 0.0, CEIL, ORDINARY, WallModule.Mat.ORDINARY)
	_wall_x("Divider_D2_ordinary", 1.5, -9.0, -13.0, 0.2, 0.0, CEIL, ORDINARY)
	# Room walls: north, east (exterior window band z -3..-8, sill 0.9, head 2.3), south (with a reinforced section).
	_wall_z("Room_north", -2.0, 1.6, 9.6, 0.2, 0.0, CEIL, ORDINARY)
	_wall_x("Room_east_N", 9.6, -2.0, -3.0, 0.2, 0.0, CEIL, ORDINARY)
	_wall_x("Room_east_sill", 9.6, -3.0, -8.0, 0.2, 0.0, 0.9, ORDINARY)
	_wall_x("Room_east_head", 9.6, -3.0, -8.0, 0.2, 2.3, CEIL, ORDINARY)
	_wall_x("Room_east_S", 9.6, -8.0, -9.0, 0.2, 0.0, CEIL, ORDINARY)
	_wall_z("Room_south_W", -9.0, 1.6, 4.0, 0.2, 0.0, CEIL, ORDINARY)
	_wall_z("Room_south_reinforced", -9.0, 4.0, 6.0, 0.34, 0.0, CEIL, REINFORCED)
	_wall_z("Room_south_E", -9.0, 6.0, 9.6, 0.2, 0.0, CEIL, ORDINARY)
	# Exterior glazing: three panes with mullions (solid: blocks movement and shots).
	for i in 4:
		var z := -3.0 - i * (5.0 / 3.0)
		_box("Mullion_%d" % i, Vector3(9.55, 0.9, z + 0.04), Vector3(9.65, 2.3, z - 0.04), Surfaces.get_mat("trim"))
	_box("Glass_exterior", Vector3(9.59, 0.9, -3.0), Vector3(9.61, 2.3, -8.0), Surfaces.get_mat("glass"))
	# Scale references: operator stand-in (1.8 m class) in the room and a 1.0 m equipment case.
	_box("ScaleFigure_1.8m", Vector3(7.0, 0.0, -5.0), Vector3(7.5, 1.8, -5.5), null)
	var fig := StandIn.build(StandIn.TEAM_BLUE)
	fig.position = Vector3(7.25, 0.0, -5.25)
	fig.rotation.y = deg_to_rad(110)
	add_child(fig)
	_box("Crate_1.0m", Vector3(4.0, 0.0, -3.0), Vector3(5.0, 1.0, -4.0), Surfaces.get_mat("case"))
	# Practice targets in the room (x=8.4, facing the divider) and one by the corridor wall facing the corridor.
	for t in [["Target_1", Vector3(8.4, 0.0, -6.0), 90.0], ["Target_2", Vector3(8.4, 0.0, -3.5), 90.0], ["Target_3", Vector3(-1.1, 0.0, -9.0), -150.0]]:
		var tg := PracticeTarget.new()
		tg.setup(t[0], t[1], t[2])
		add_child(tg)
		targets.append(tg)
	OfficeSet.build_dressing(self)
	OfficeSet.build_lights(self)
	OfficeSet.build_exterior(self)


## Wall running along Z at fixed x (centre line), spanning z0..z1.
## `mat` >= 0 makes it a breachable WallModule of that material.
func _wall_x(wall_name: String, x: float, z0: float, z1: float, thick: float, y0: float, y1: float, col: Material, mat: int = -1) -> void:
	var a := Vector3(x - thick * 0.5, y0, z1)
	var b := Vector3(x + thick * 0.5, y1, z0)
	if mat >= 0:
		_module(wall_name, a, b, mat, col)
	else:
		_box(wall_name, a, b, col)


## Wall running along X at fixed z (centre line), spanning x0..x1.
func _wall_z(wall_name: String, z: float, x0: float, x1: float, thick: float, y0: float, y1: float, col: Material) -> void:
	_box(wall_name, Vector3(x0, y0, z - thick * 0.5), Vector3(x1, y1, z + thick * 0.5), col)


func _module(id: String, a: Vector3, b: Vector3, mat: int, col: Material) -> void:
	var m := WallModule.new()
	m.setup(id, a, b, mat, col)
	add_child(m)
	modules.append(m)


## Full round restart: player, wall panels, targets, ammo/charges, marks and effects.
func restart() -> void:
	player.reset()
	for m in modules:
		m.reset()
	for t in targets:
		t.reset()
	loadout.reset()


## Axis-aligned box from min corner a to max corner b (any order); static collision + mesh.
## `mat` null = invisible collider (used under stand-ins); `collide` false = decoration only.
func _box(box_name: String, a: Vector3, b: Vector3, mat: Material, collide: bool = true) -> Node3D:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var size := hi - lo
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return null
	var body: Node3D
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		sb.add_child(shape)
		body = sb
	else:
		body = Node3D.new()
	body.name = box_name
	body.position = (lo + hi) * 0.5
	if mat:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		body.add_child(mi)
	add_child(body)
	return body


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
	_hud.text = "WASD move · Shift sprint · C crouch · LMB fire/place · RMB aim · R reload · 1 rifle 2 ordinary charge 3 heavy charge · T restart · Esc mouse · F1-F3 cams, F4 player\nspeed %.1f m/s  %s  height %.2f m  FOV %.0f" % [
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


# ---------------------------------------------------------------- headless combat smoke test

func _mod(id: String) -> WallModule:
	for m in modules:
		if m.wall_id == id:
			return m
	return null


func _stand_at(pos: Vector3, yaw_deg: float) -> void:
	player.script_move = Vector2.ZERO
	player.teleport(pos, yaw_deg)


func _run_smoke_combat() -> void:
	var t := get_tree().create_timer(120.0)
	t.timeout.connect(func() -> void:
		print("SMOKE_FAIL combat timeout")
		get_tree().quit(1))
	var lo := loadout
	lo.tuning.ordinary_fuse = 0.4
	lo.tuning.heavy_fuse = 0.4
	lo.tuning.reload_time = 0.5
	await _frames(10)
	var t1 := targets[0]
	var t2 := targets[1]
	var wall_c := _mod("Divider_C_ordinary")
	var wall_b := _mod("Divider_B_reinforced")
	var wall_d := _mod("Divider_D1_ordinary")

	# --- rifle: hit, damage, ammo, feedback
	_check("starts with full mag", lo.mag == 30 and lo.reserve == 90 and lo.tool == Loadout.Tool.RIFLE)
	_stand_at(Vector3(3.0, 0.05, -6.0), -90.0)
	await _frames(5)
	var r := lo.fire_rifle()
	_check("rifle hits target", r.get("hit", false) and r["collider"] == t1 and not r["muzzle_blocked"])
	_check("hit does damage + marker", is_equal_approx(t1.health, 80.0) and lo.hit_marker > 0.0 and lo.mag == 29)
	_check("fire rate gate", lo.fire_rifle().is_empty())
	for i in 4:
		await _frames(8)
		lo.fire_rifle()
	_check("5 hits down the target", not t1.alive and lo.mag == 25 and t1.collision_layer == 0)
	_stand_at(Vector3(3.0, 0.05, -6.0), 0.0)
	await _frames(8)
	r = lo.fire_rifle()
	_check("wall shot leaves a bounded mark", r.get("hit", false) and not (r["collider"] is PracticeTarget) and lo.visible_marks() == 1)

	# --- reload / dry fire
	_check("reload starts", lo.start_reload() and lo.reloading)
	await _frames(8)
	_check("cannot fire while reloading", lo.fire_rifle().is_empty() and lo.mag == 24)
	await _frames(40)
	_check("reload fills mag from reserve", not lo.reloading and lo.mag == 30 and lo.reserve == 84, "mag=%d res=%d" % [lo.mag, lo.reserve])
	var fired := lo.shots_fired
	lo.mag = 0
	lo.reserve = 0
	await _frames(20)
	_check("dry fire does nothing", lo.fire_rifle().is_empty() and lo.shots_fired == fired)
	lo.mag = 30
	lo.reserve = 84

	# --- nearby cover blocks muzzle shots (crate 1.0 m high, x 4..5)
	_stand_at(Vector3(3.6, 0.05, -3.5), -90.0)
	player.script_crouch = false
	await _frames(20)
	await _frames(8)
	r = lo.fire_rifle()
	_check("standing shot clears crate, hits target", r.get("hit", false) and r["collider"] == t2 and not r["muzzle_blocked"])
	t2.reset()
	player.script_crouch = true
	await _frames(40)
	await _frames(8)
	r = lo.fire_rifle()
	_check("crouched behind crate: muzzle blocked", r.get("hit", false) and r["muzzle_blocked"] and str(r["collider"].name).begins_with("Crate")
		and is_equal_approx(t2.health, 100.0), "collider=%s" % (r["collider"].name if r.get("hit", false) else "none"))
	player.script_crouch = false
	await _frames(30)
	# wall pressed against the barrel
	_stand_at(Vector3(1.04, 0.05, -1.0), -90.0)
	await _frames(15)
	r = lo.fire_rifle()
	_check("barrel against wall: blocked at wall", r.get("hit", false) and r["muzzle_blocked"] and r["distance"] < 1.0)

	# --- wall-module state logic
	_check("tool/material table", WallModule.can_breach(WallModule.Mat.ORDINARY, WallModule.Kind.ORDINARY)
		and WallModule.can_breach(WallModule.Mat.REINFORCED, WallModule.Kind.HEAVY)
		and not WallModule.can_breach(WallModule.Mat.ORDINARY, WallModule.Kind.HEAVY)
		and not WallModule.can_breach(WallModule.Mat.REINFORCED, WallModule.Kind.ORDINARY))
	_check("modules start intact, 1 part", wall_c.state == WallModule.State.INTACT and wall_c.revision == 0
		and wall_c.shape_count() == 1 and wall_c.mesh_count() == 1)

	# --- wrong tools / invalid placement rejected (no charge spent, no state change)
	_stand_at(Vector3(0.5, 0.05, -2.75), -90.0)
	await _frames(5)
	lo.select(Loadout.Tool.ORDINARY_CHARGE)
	_check("ordinary charge rejected on reinforced", not lo.place_charge() and wall_b.state == WallModule.State.INTACT
		and lo.active_charges.is_empty() and lo.charges[Loadout.Tool.ORDINARY_CHARGE] == 3, lo.last_message)
	_stand_at(Vector3(0.5, 0.05, -5.4), -90.0)
	await _frames(5)
	lo.select(Loadout.Tool.HEAVY_CHARGE)
	_check("heavy charge rejected on ordinary", not lo.place_charge() and wall_c.charge == null
		and lo.charges[Loadout.Tool.HEAVY_CHARGE] == 2, lo.last_message)
	lo.select(Loadout.Tool.ORDINARY_CHARGE)
	lo.tuning.place_reach = 1.5
	_stand_at(Vector3(-0.5, 0.05, -5.4), -90.0)
	await _frames(5)
	_check("too far rejected", not lo.place_charge() and lo.active_charges.is_empty(), lo.last_message)
	lo.tuning.place_reach = 2.5
	_stand_at(Vector3(-0.5, 0.05, -5.4), 90.0)
	await _frames(5)
	_check("non-breachable wall rejected", not lo.place_charge() and lo.active_charges.is_empty(), lo.last_message)

	# --- ordinary charge opens the ordinary panel
	_stand_at(Vector3(0.5, 0.05, -5.4), -90.0)
	await _frames(5)
	_check("ordinary charge placed", lo.place_charge() and wall_c.charge != null and lo.active_charges.size() == 1
		and lo.charges[Loadout.Tool.ORDINARY_CHARGE] == 2)
	_check("second charge on same panel rejected", not lo.place_charge() and lo.active_charges.size() == 1, lo.last_message)
	_check("countdown running, panel still intact", wall_c.state == WallModule.State.INTACT and lo.active_charges[0].left > 0.0)
	await _frames(70)
	_check("panel breached after fuse", wall_c.state == WallModule.State.BREACHED and wall_c.revision == 1
		and lo.active_charges.is_empty() and wall_c.charge == null)
	await _frames(5)
	_check("breached panel: mesh and collision agree", wall_c.shape_count() == 3 and wall_c.mesh_count() == 3 and _parts_match(wall_c))
	_check("ordinary panel can't be breached twice", not wall_c.breach(WallModule.Kind.ORDINARY) and wall_c.revision == 1)
	_stand_at(Vector3(0.5, 0.05, -4.65), -90.0)
	await _frames(5)
	_check("already breached rejected", not lo.place_charge() and lo.last_message == "Already breached", lo.last_message)
	var space := get_world_3d().direct_space_state
	var mask := 1
	var through := PhysicsRayQueryParameters3D.create(Vector3(0.5, 1.0, -5.4), Vector3(3.0, 1.0, -5.4), mask)
	var side := PhysicsRayQueryParameters3D.create(Vector3(0.5, 1.0, -4.65), Vector3(3.0, 1.0, -4.65), mask)
	var lintel := PhysicsRayQueryParameters3D.create(Vector3(0.5, 2.4, -5.4), Vector3(3.0, 2.4, -5.4), mask)
	_check("opening is clear, jambs and lintel remain", space.intersect_ray(through).is_empty()
		and not space.intersect_ray(side).is_empty() and not space.intersect_ray(lintel).is_empty())
	_stand_at(Vector3(0.5, 0.05, -5.4), -90.0)
	player.script_move = Vector2(0, -1)
	await _frames(100)
	_check("player walks through the opening", player.global_position.x > 3.0, "x=%.2f" % player.global_position.x)

	# --- heavy charge opens the reinforced panel
	_stand_at(Vector3(0.5, 0.05, -2.75), -90.0)
	await _frames(5)
	lo.select(Loadout.Tool.HEAVY_CHARGE)
	_check("heavy charge placed on reinforced", lo.place_charge() and lo.charges[Loadout.Tool.HEAVY_CHARGE] == 1)
	await _frames(70)
	_check("reinforced panel breached", wall_b.state == WallModule.State.BREACHED and wall_b.revision == 1
		and wall_b.shape_count() == 3 and _parts_match(wall_b))
	player.script_move = Vector2(0, -1)
	await _frames(100)
	_check("player walks through reinforced opening", player.global_position.x > 3.0, "x=%.2f" % player.global_position.x)

	# --- effects bounded
	for i in 20:
		lo.effects.burst(Vector3(3, 1, -5), Vector3.LEFT, i % 2 == 0)
	_check("effects capped", lo.effects.active <= BreachEffects.MAX_BURSTS and lo.effects.get_child_count() <= BreachEffects.MAX_BURSTS
		, "active=%d children=%d" % [lo.effects.active, lo.effects.get_child_count()])

	# --- restart restores everything
	player.script_move = Vector2.ZERO
	restart()
	await _frames(5)
	_check("restart: panels intact", wall_c.state == WallModule.State.INTACT and wall_c.revision == 0 and wall_c.shape_count() == 1
		and wall_b.state == WallModule.State.INTACT and wall_d.state == WallModule.State.INTACT and wall_b.mesh_count() == 1)
	_check("restart: targets restored", t1.alive and is_equal_approx(t1.health, 100.0) and t1.collision_layer == 4 and t1.rotation.x == 0.0)
	_check("restart: loadout restored", lo.mag == 30 and lo.reserve == 90 and lo.tool == Loadout.Tool.RIFLE
		and lo.charges[Loadout.Tool.ORDINARY_CHARGE] == 3 and lo.charges[Loadout.Tool.HEAVY_CHARGE] == 2 and lo.active_charges.is_empty())
	_check("restart: marks and effects cleared", lo.visible_marks() == 0 and lo.effects.active == 0 and lo.effects.get_child_count() == 0)
	_check("restart: player at spawn", player.global_position.distance_to(_spawn.global_position) < 0.1)
	_stand_at(Vector3(0.5, 0.05, -5.4), -90.0)
	player.script_move = Vector2(0, -1)
	await _frames(100)
	_check("restart: wall blocks again", player.global_position.x < 1.1, "x=%.2f" % player.global_position.x)

	if _fails == 0:
		print("SMOKE_OK combat")
		get_tree().quit(0)
	else:
		print("SMOKE_FAIL combat failures=", _fails)
		get_tree().quit(1)


## Collision shapes and meshes of a module must match its authored part list exactly.
func _parts_match(m: WallModule) -> bool:
	var boxes := m.part_boxes(m.state)
	var shapes: Array[CollisionShape3D] = []
	var meshes: Array[MeshInstance3D] = []
	for c in m.get_children():
		if c is CollisionShape3D:
			shapes.append(c)
		elif c is MeshInstance3D:
			meshes.append(c)
	if shapes.size() != boxes.size() or meshes.size() != boxes.size():
		return false
	for i in boxes.size():
		var ok_s: bool = ((shapes[i].shape as BoxShape3D).size - boxes[i].size).length() < 0.001 \
			and (shapes[i].position - boxes[i].get_center()).length() < 0.001
		var ok_m: bool = ((meshes[i].mesh as BoxMesh).size - boxes[i].size).length() < 0.001 \
			and (meshes[i].position - boxes[i].get_center()).length() < 0.001
		if not (ok_s and ok_m):
			return false
	return true
