class_name Loadout
extends Node
## Rifle + breach charges for the first-person player, plus its HUD. Offline for now.
## Keys: 1 rifle, 2 ordinary charge, 3 heavy charge, LMB fire/place, RMB aim, R reload.
## Headless tests call fire_rifle()/start_reload()/place_charge()/select() directly.

enum Tool { RIFLE, ORDINARY_CHARGE, HEAVY_CHARGE }

const RAY_MASK := 1 | 4 ## world + targets
const WALL_MASK := 1
const MAX_MARKS := 24

var tuning: WeaponTuning
var player: Player
var world: Node3D
var effects: BreachEffects
var viewmodel: Viewmodel
var tool := Tool.RIFLE
var mag := 0
var reserve := 0
var reloading := false
var charges := {Tool.ORDINARY_CHARGE: 0, Tool.HEAVY_CHARGE: 0}
var aiming := false
var shots_fired := 0
var last_shot: Dictionary = {}
var active_charges: Array[Charge] = []
var last_message := ""
var hit_marker := 0.0
var _hit_kill := false
var _cooldown := 0.0
var _reload_left := 0.0
var _fire_armed := false
var _flash_left := 0.0
var _flash: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _marks: Array[MeshInstance3D] = []
var _mark_next := 0
var _mark_mat: StandardMaterial3D
var _msg_left := 0.0
var _canvas: Control
var _ammo_label: Label
var _msg_label: Label
var _warn_label: Label


func setup(p: Player, w: Node3D, t: WeaponTuning) -> void:
	player = p
	world = w
	tuning = t
	effects = BreachEffects.new()
	effects.name = "BreachEffects"
	world.add_child(effects)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.85, 0.5)
	_flash.omni_range = 4.0
	_flash.light_energy = 2.0
	_flash.visible = false
	_flash.position = tuning.muzzle_offset
	player.camera.add_child(_flash)
	viewmodel = Viewmodel.new()
	player.camera.add_child(viewmodel)
	viewmodel.setup(self)
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_build_hud()
	reset()


func reset() -> void:
	tool = Tool.RIFLE
	mag = tuning.mag_size
	reserve = tuning.reserve_start
	reloading = false
	aiming = false
	_cooldown = 0.0
	_reload_left = 0.0
	shots_fired = 0
	last_shot = {}
	charges[Tool.ORDINARY_CHARGE] = tuning.ordinary_count
	charges[Tool.HEAVY_CHARGE] = tuning.heavy_count
	for c in active_charges:
		if is_instance_valid(c):
			c.set_process(false)
			c.free()
	active_charges.clear()
	for m in _marks:
		m.queue_free()
	_marks.clear()
	_mark_next = 0
	effects.clear()
	hit_marker = 0.0
	_fire_armed = false
	if _flash:
		_flash.visible = false
	_say("")


func reload_left() -> float:
	return _reload_left


func visible_marks() -> int:
	var n := 0
	for m in _marks:
		if is_instance_valid(m) and m.visible:
			n += 1
	return n


# ---------------------------------------------------------------- input / frame

func _can_act() -> bool:
	return not player.scripted and player.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if not _can_act():
		aiming = false
		_fire_armed = false
		return
	if Input.is_action_just_pressed("tool_1"):
		select(Tool.RIFLE)
	elif Input.is_action_just_pressed("tool_2"):
		select(Tool.ORDINARY_CHARGE)
	elif Input.is_action_just_pressed("tool_3"):
		select(Tool.HEAVY_CHARGE)
	if Input.is_action_just_pressed("reload"):
		start_reload()
	aiming = tool == Tool.RIFLE and not reloading and Input.is_action_pressed("aim")
	var fire := Input.is_action_pressed("primary_fire")
	if not fire:
		_fire_armed = true
	elif _fire_armed:
		if tool == Tool.RIFLE:
			fire_rifle()
		else:
			place_charge()
			_fire_armed = false


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
	hit_marker = maxf(hit_marker - delta, 0.0)
	_msg_left = maxf(_msg_left - delta, 0.0)
	_msg_label.modulate.a = clampf(_msg_left, 0.0, 1.0)
	if not player.scripted and player.camera.current:
		var target := player.fov * (tuning.ads_fov_mult if aiming else 1.0)
		player.camera.fov = lerpf(player.camera.fov, target, clampf(tuning.ads_speed * delta, 0.0, 1.0))
	_update_hud()
	_canvas.queue_redraw()


# ---------------------------------------------------------------- tools

func select(t: int) -> void:
	if t == tool:
		return
	tool = t
	reloading = false
	_say(["Rifle", "Ordinary charge", "Heavy charge"][t])


func start_reload() -> bool:
	if tool != Tool.RIFLE or reloading or mag >= tuning.mag_size or reserve <= 0:
		return false
	reloading = true
	_reload_left = tuning.reload_time
	ProcAudio.play(world, "reload")
	return true


func _finish_reload() -> void:
	reloading = false
	var take := mini(tuning.mag_size - mag, reserve)
	mag += take
	reserve -= take


## Fires one shot if allowed. Returns the Ballistics result, or {} if nothing fired.
func fire_rifle() -> Dictionary:
	if tool != Tool.RIFLE or reloading or _cooldown > 0.0:
		return {}
	if mag <= 0:
		_cooldown = 0.25
		ProcAudio.play(world, "dry")
		if not start_reload():
			_say("Out of ammo")
		return {}
	mag -= 1
	shots_fired += 1
	_cooldown = tuning.fire_interval
	var xf := player.camera.global_transform
	var dir := -xf.basis.z
	if not player.scripted:
		var spread := deg_to_rad(tuning.spread_aim_deg if aiming else tuning.spread_hip_deg)
		var ang := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * spread
		dir = (dir + xf.basis.x * cos(ang) * r + xf.basis.y * sin(ang) * r).normalized()
		player.kick(deg_to_rad(tuning.kick_deg))
	var muzzle := xf * tuning.muzzle_offset
	var res := Ballistics.resolve(player.get_world_3d().direct_space_state, xf.origin, dir, muzzle,
		tuning.range_m, RAY_MASK, [player.get_rid()] as Array[RID])
	last_shot = res
	ProcAudio.play(world, "shot", null, -4.0)
	_flash.visible = true
	_flash_left = 0.04
	if res["hit"]:
		_on_hit(res)
	return res


func _on_hit(res: Dictionary) -> void:
	var col: Object = res["collider"]
	if col is PracticeTarget:
		var killed: bool = (col as PracticeTarget).apply_damage(tuning.damage)
		hit_marker = 0.18
		_hit_kill = killed
		ProcAudio.play(world, "hit")
	else:
		_add_mark(res["position"], res["normal"], col)


func _add_mark(pos: Vector3, normal: Vector3, owner_module: Object) -> void:
	var mi: MeshInstance3D
	if _marks.size() < MAX_MARKS:
		mi = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.09, 0.09)
		q.material = _mark_mat
		mi.mesh = q
		world.add_child(mi)
		_marks.append(mi)
	else:
		mi = _marks[_mark_next]
	_mark_next = (_mark_next + 1) % MAX_MARKS
	var up := Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.004)
	mi.visible = true
	if owner_module is WallModule:
		mi.set_meta("module", owner_module)
	elif mi.has_meta("module"):
		mi.remove_meta("module")


## Called when a wall panel changes state: hide cosmetic marks that were on it.
func on_module_changed(m: WallModule) -> void:
	for mi in _marks:
		if is_instance_valid(mi) and mi.has_meta("module") and mi.get_meta("module") == m:
			mi.visible = false


# ---------------------------------------------------------------- charges

func check_placement(t: int) -> Dictionary:
	var kind := t - 1 ## Tool.ORDINARY_CHARGE -> Kind.ORDINARY, HEAVY_CHARGE -> HEAVY
	var cam := player.camera.global_transform
	var from := cam.origin
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.basis.z * tuning.place_reach, WALL_MASK,
		[player.get_rid()] as Array[RID])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "reason": "Too far: aim at a wall within %.1f m" % tuning.place_reach}
	var col: Object = hit["collider"]
	if not (col is WallModule) or not (col as WallModule).breakable:
		return {"ok": false, "reason": "Can't breach this surface"}
	var m := col as WallModule
	var n: Vector3 = hit["normal"]
	var pos: Vector3 = hit["position"]
	if absf(n.y) > 0.3:
		return {"ok": false, "reason": "Place charges on the wall face"}
	if pos.y < 0.3 or pos.y > 2.5:
		return {"ok": false, "reason": "Aim between knee and head height"}
	if m.state != WallModule.State.INTACT:
		return {"ok": false, "reason": "Already breached"}
	if m.charge != null:
		return {"ok": false, "reason": "Charge already placed here"}
	if not WallModule.can_breach(m.material, kind):
		var need := "heavy" if m.material == WallModule.Mat.REINFORCED else "ordinary"
		var mat_name := "reinforced" if m.material == WallModule.Mat.REINFORCED else "ordinary"
		return {"ok": false, "reason": "Wrong tool: %s wall needs the %s charge" % [mat_name, need]}
	return {"ok": true, "reason": "", "module": m, "position": pos, "normal": n}


func place_charge() -> bool:
	if tool == Tool.RIFLE:
		return false
	if int(charges[tool]) <= 0:
		_reject("No charges left")
		return false
	var c := check_placement(tool)
	if not c["ok"]:
		_reject(c["reason"])
		return false
	var kind := tool - 1
	var fuse := tuning.heavy_fuse if kind == WallModule.Kind.HEAVY else tuning.ordinary_fuse
	var charge := Charge.new()
	world.add_child(charge)
	charge.setup(c["module"], kind, fuse, c["position"], c["normal"])
	(c["module"] as WallModule).charge = charge
	charge.detonated.connect(_on_detonated)
	active_charges.append(charge)
	charges[tool] = int(charges[tool]) - 1
	ProcAudio.play(world, "beep")
	_say("Charge armed: %.0f s. Move away!" % fuse)
	return true


func _on_detonated(c: Charge) -> void:
	active_charges.erase(c)
	effects.burst(c.global_position, c.normal, c.kind == WallModule.Kind.HEAVY)
	_say("Breach!")


func _reject(text: String) -> void:
	ProcAudio.play(world, "reject")
	_say(text)


func _say(text: String) -> void:
	last_message = text
	_msg_left = 2.5 if text != "" else 0.0
	if _msg_label:
		_msg_label.text = text


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LoadoutHud"
	world.add_child(layer)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	layer.add_child(_canvas)
	_ammo_label = _hud_label(layer, Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -70), 22)
	_msg_label = _hud_label(layer, Control.PRESET_CENTER_BOTTOM, Vector2(-250, -130), 20)
	_msg_label.custom_minimum_size.x = 500
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label = _hud_label(layer, Control.PRESET_CENTER_TOP, Vector2(-250, 40), 26)
	_warn_label.custom_minimum_size.x = 500
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.modulate = Color(1.0, 0.35, 0.25)


func _hud_label(layer: CanvasLayer, preset: int, off: Vector2, size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position += off
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(l)
	return l


func _hud_visible() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.camera.current


func _update_hud() -> void:
	var show := _hud_visible()
	_ammo_label.visible = show
	_msg_label.visible = show
	_warn_label.visible = show
	if tool == Tool.RIFLE:
		_ammo_label.text = "RIFLE  %d / %d%s" % [mag, reserve, "  (reloading)" if reloading else ""]
	else:
		_ammo_label.text = "%s  x%d" % ["ORDINARY CHARGE" if tool == Tool.ORDINARY_CHARGE else "HEAVY CHARGE", int(charges[tool])]
	var warn := ""
	for c in active_charges:
		if is_instance_valid(c):
			var near := c.global_position.distance_to(player.global_position) < tuning.warn_radius
			warn = "CHARGE %.1f s%s" % [c.left, "  BACK AWAY!" if near else ""]
	_warn_label.text = warn


func _draw_hud() -> void:
	if not _hud_visible():
		return
	var c := _canvas.size * 0.5
	var col := Color(1, 1, 1, 0.85)
	if tool != Tool.RIFLE:
		var ok: bool = check_placement(tool)["ok"]
		col = Color(0.3, 1.0, 0.4, 0.9) if ok else Color(1.0, 0.35, 0.3, 0.9)
		_canvas.draw_arc(c, 9.0, 0.0, TAU, 24, col, 2.0)
		return
	var gap := 3.0 if aiming else 7.0
	for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_canvas.draw_line(c + d * gap, c + d * (gap + 7.0), col, 2.0)
	if hit_marker > 0.0:
		var hc := Color(1.0, 0.25, 0.2) if _hit_kill else Color(1, 1, 1)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_canvas.draw_line(c + d * 8.0, c + d * 15.0, hc, 2.0)
