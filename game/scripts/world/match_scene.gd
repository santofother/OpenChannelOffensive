extends Node3D
## Shared player, loadout, match lifecycle and settings for the demo and Lightwell.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

const WEAPON_TUNING := preload("res://data/weapon_tuning.tres")
## Surfaces rifle rounds pass through (damage multiplier), bounded by Ballistics thickness/surface limits.
const PEN_MULT := {"plaster": 0.5, "glass": 0.85}

var player: Player
var gadgets: GadgetSystem
var doors: DoorSystem ## null on maps without door specs
var loadout: Loadout
var modules: Array[WallModule] = []
var targets: Array[PracticeTarget] = []
var net: NetMatch ## set when this scene runs inside a network session
var net_mode := false
var _leaving := false
var _spawn: Marker3D
var _cams: Array[Camera3D] = []
var _hud: Label
var _panel: PanelContainer
var _sens: HSlider
var _fov: HSlider
var _controls: ControlsPanel
var _fails := 0


func _ready() -> void:
	net_mode = NetworkManager.is_in_session() and not NetworkManager.args.has("smoke-graybox") \
		and not NetworkManager.args.has("smoke-combat")
	_build_environment()
	_build_level()
	_spawn = Marker3D.new()
	_spawn.name = "PlayerSpawn"
	var spawn := spawn_at(0)
	_spawn.position = spawn[0]
	_spawn.rotation.y = deg_to_rad(spawn[1])
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
	gadgets = GadgetSystem.new()
	gadgets.name = "Gadgets"
	add_child(gadgets)
	gadgets.setup(self)
	var specs := door_specs()
	if not specs.is_empty():
		doors = DoorSystem.new()
		add_child(doors)
		doors.setup(self, specs)
	if NetworkManager.args.has("gear-stress") and not net_mode:
		var stress := GearStress.new()
		add_child(stress)
		stress.start(self)
	for m in modules:
		m.state_changed.connect(loadout.on_module_changed)
	if DisplayServer.get_name() != "headless" and not NetworkManager.args.has("capture") and not NetworkManager.args.has("gear-capture"):
		_warm_up_graphics()
	if net_mode:
		net = NetMatch.new()
		add_child(net)
		net.start(self)
		NetworkManager.session_ended.connect(_on_session_ended)
	if _start_tools():
		return
	player.mouse_capture_changed.connect(_on_capture)
	player.capture_mouse(true)


func attack_zone_count() -> int:
	return 1

func spawn_at(index: int, _attack_zone: int = 0) -> Array:
	return NetMatch.SPAWNS[index]


## Doorways that get hinged doors (DoorSystem). Maps override; the original demo keeps open doorways.
func door_specs() -> Array:
	return []

func match_tuning() -> MatchTuning:
	return preload("res://data/match_tuning.tres").duplicate(true)


func _start_tools() -> bool:
	return false


func _build_environment() -> void:
	OfficeSet.build_environment(self)


func _build_level() -> void:
	pass


func _build_cameras() -> void:
	pass


## True when a position is outside the building (maps without a footprint: never).
func is_outside(_pos: Vector3) -> bool:
	return false


## Prep-phase barriers in exterior doorways keep defenders inside (no-op without a footprint).
func set_prep_barriers(_on: bool) -> void:
	pass


func clear_wall_debris() -> void:
	pass


func restart() -> void:
	if net:
		if net.is_host and (NetworkManager.args.has("dev") or NetworkManager.args.has("net-test")):
			if net.loop.enabled and net.loop.rules.phase != RoundRules.Phase.PREP:
				loadout.say("Development reset is available during prep")
				return
			net.loop.inputs.clear()
			net.loop.rules.interrupt()
			net.restart_round()
		else:
			loadout.say("Rounds restart automatically (host --dev: %s during prep)" % Keys.key("reset"))
		return
	GameAudio.clear()
	clear_wall_debris()
	player.reset()
	for m in modules:
		m.reset()
	for t in targets:
		t.reset()
	loadout.reset()
	gadgets.clear()
	if doors:
		doors.reset()


## Axis-aligned box from min corner a to max corner b (any order); static collision + mesh.
## `mat` null = invisible collider (used under stand-ins); `collide` false = decoration only.
func _module(id: String, a: Vector3, b: Vector3, mat: int, col: Material) -> void:
	var m := WallModule.new()
	m.setup(id, a, b, mat, col)
	add_child(m)
	modules.append(m)


## Full round restart: player, wall panels, targets, ammo/charges, marks and effects.
## In a session only the host restarts (new round id for everyone).
func footstep_surface(pos: Vector3) -> int:
	var ray := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * .15, pos - Vector3.UP * .3, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return int(hit.collider.get_meta("step_surface", 0)) if not hit.is_empty() else 0


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
		for k: String in PEN_MULT:
			if mat != null and mat == Surfaces.get_mat(k):
				sb.set_meta("pen_mult", PEN_MULT[k])
		if mat == Surfaces.get_mat("carpet"):
			sb.set_meta("step_surface", 1)
		elif mat == Surfaces.get_mat("metal_plate"):
			sb.set_meta("step_surface", 2)
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
	layer.add_child(_panel)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 12
	_panel.offset_top = -540
	_panel.offset_right = 535
	_panel.offset_bottom = -12
	var settings := VBoxContainer.new()
	_panel.add_child(settings)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var t := Label.new()
	t.text = "Paused — click empty space or Resume to capture mouse"
	box.add_child(t)
	_sens = _slider(box, "Sensitivity", 0.1, 3.0, player.look_sensitivity, func(v: float) -> void:
		player.look_sensitivity = v
		player.save_settings())
	_fov = _slider(box, "FOV", player.tuning.min_fov, player.tuning.max_fov, player.fov, func(v: float) -> void:
		player.set_fov(v)
		player.save_settings())
	_controls = ControlsPanel.new()
	_controls.position = Vector2(545, 12)
	_controls.visible = false
	layer.add_child(_controls)
	var keys := Button.new()
	keys.text = "Controls (rebind keys)…"
	keys.pressed.connect(func() -> void: _controls.visible = not _controls.visible)
	box.add_child(keys)
	if net_mode:
		var network_status := Label.new()
		network_status.custom_minimum_size.x = 480
		network_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if NetworkManager.mode == NetworkManager.Mode.ENET:
			network_status.text = "LAN addresses: %s (UDP %d)\nAllow the game in the host firewall and Mac Local Network settings." % [", ".join(NetworkManager.lan_addresses()), NetworkManager.enet_port]
		else:
			network_status.text = "Steam match — no LAN IP or port forwarding needed."
		box.add_child(network_status)
		var report := Button.new()
		report.text = "Copy connection report"
		report.pressed.connect(func() -> void:
			if net:
				var text := net.connection_report()
				DisplayServer.clipboard_set(text)
				print("[Connection report] ", text))
		box.add_child(report)
	box.add_child(VoiceSettings.new())
	var actions := HBoxContainer.new()
	settings.add_child(actions)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(func() -> void: player.capture_mouse(true))
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(resume)
	var back := Button.new()
	back.text = "Leave Game" if net_mode else "Back to Menu"
	back.pressed.connect(func() -> void:
		player.capture_mouse(false)
		_leaving = true
		if net:
			NetworkManager.leave("Left the match")
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(back)
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
	if captured:
		_controls.visible = false
	else:
		_sens.set_value_no_signal(player.look_sensitivity)
		_fov.set_value_no_signal(player.fov)


## First-use graphics stalls (shader/pipeline compiles for the charges, held-charge viewmodel, breach particles,
## scorch decal and bullet marks) froze a window for ~0.15–1.2 s the first time each appeared mid-fight.
## Draw each once at load, behind a short loading cover, so the cost lands here instead.
func _warm_up_graphics() -> void:
	var cover := CanvasLayer.new()
	cover.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.add_child(bg)
	var l := Label.new()
	l.text = "Loading..."
	l.set_anchors_preset(Control.PRESET_CENTER)
	cover.add_child(l)
	add_child(cover)
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	var cam := player.camera.global_transform
	var at := func(x: float, y: float, d: float) -> Vector3: return cam * Vector3(x, y, -d)
	var face := cam.basis.z
	var tmp: Array[Node] = []
	# Behind-cover geometry for decal/particles to land on.
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 3, 0.1)
	bm.material = Surfaces.get_mat("plaster")
	back.mesh = bm
	add_child(back)
	back.global_transform = Transform3D(cam.basis, at.call(0.0, 0.0, 3.0))
	tmp.append(back)
	for k in [WallModule.Kind.ORDINARY, WallModule.Kind.HEAVY]:
		var c := Charge.new()
		c.authoritative = false
		add_child(c)
		c.setup(modules[0], k, 99.0, at.call(-0.5 + k, 0.0, 2.0), face)
		c.remove_from_group("charges")
		c.set_process(false)
		tmp.append(c)
	var d := Decal.new()
	d.texture_albedo = WallModule._scorch()
	d.size = Vector3(2, 1, 2)
	add_child(d)
	d.global_transform = Transform3D(Basis.looking_at(-face, cam.basis.y) * Basis(Vector3.RIGHT, deg_to_rad(90)), at.call(0.0, 0.0, 2.95))
	tmp.append(d)
	var mark := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	q.material = loadout._mark_mat
	mark.mesh = q
	add_child(mark)
	mark.global_transform = Transform3D(cam.basis, at.call(0.3, 0.3, 2.0))
	tmp.append(mark)
	loadout.effects.burst(at.call(0.0, 0.0, 2.5), face, true, true)
	var vm := loadout.viewmodel
	var warmup_saved: Array = vm.begin_graphics_warmup() if vm else []
	for i in 4:
		await get_tree().process_frame
	for n in tmp:
		n.queue_free()
	loadout.effects.clear()
	if vm:
		vm.end_graphics_warmup(warmup_saved)
	cover.queue_free()
	print("[Warmup] graphics warm-up %d ms" % (Time.get_ticks_msec() - t0))


## Host left (or we were dropped): back to the menu, which shows the reason.
func _on_session_ended(reason: String) -> void:
	print("[Match] session ended: ", reason)
	if is_inside_tree() and not _leaving:
		player.capture_mouse(false)
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).physical_keycode
	if net_mode and not NetworkManager.args.has("dev"):
		return
	if k >= KEY_F1 and k <= KEY_F3:
		_cams[k - KEY_F1].make_current()
		player.input_enabled = false
	elif k == KEY_F4:
		player.camera.make_current()
		player.input_enabled = true


## Two-line movement/combat key summary built from the current bindings.
static func controls_hint() -> String:
	var k := func(a: String) -> String: return Keys.key(a)
	return "%s%s%s%s move · %s crouch · %s/%s lean · %s use · %s aim · %s reload\n%s primary · %s pistol · %s/%s charges · %s kit · %s medkit · %s grenades" % [
		k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("crouch"),
		k.call("lean_left"), k.call("lean_right"), k.call("primary_fire"), k.call("aim"), k.call("reload"), k.call("tool_1"), k.call("tool_2"),
		k.call("tool_3"), k.call("tool_4"), k.call("tool_5"), k.call("tool_6"), k.call("grenade_cycle")]


func _process(_delta: float) -> void:
	if net_mode:
		_hud.text = controls_hint() + "\n%s interact · %s drop · %s ready · %s team · %s comms · Esc settings" % [
			Keys.key("interact"), Keys.key("drop_bomb"), Keys.key("ready_toggle"), Keys.key("team_switch"), Keys.key("comm_wheel")]
		return
	var v := player.velocity
	_hud.text = controls_hint() + "\n%s restart · Esc mouse · F1-F3 cams, F4 player\nspeed %.1f m/s  %s  height %.2f m  FOV %.0f" % [
		Keys.key("reset"), Vector2(v.x, v.z).length(), "CROUCHED" if player.crouched else "standing", player.height, player.fov]


# ---------------------------------------------------------------- headless smoke test

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("  PASS " if ok else "  FAIL ") + label + (" " + detail if detail != "" else ""))
	if not ok:
		_fails += 1


func _mod(id: String) -> WallModule:
	for m in modules:
		if m.wall_id == id:
			return m
	return null


func _stand_at(pos: Vector3, yaw_deg: float) -> void:
	player.script_move = Vector2.ZERO
	player.teleport(pos, yaw_deg)


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
