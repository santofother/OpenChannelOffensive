class_name GearCapture
extends Node
## Session 09.75 evidence tool (needs a real window): first-person and world screenshots of the gear models.
##   res://scenes/graybox.tscn -- --gear-capture=<abs dir> [--gear=service_rifle,p9,...] [--gear-shots=hip,ads,reload,fire]
## Drives the loadout with scripted commands so the real viewmodel code and clips are what gets captured.

var g: Node3D
var player: Player
var loadout: Loadout
var _fire := false
var _aim := false
var _reload := false
var _tool := Loadout.Tool.RIFLE
var _seq := 0
var _checks := []
var _failures := 0


func start(graybox: Node3D) -> void:
	g = graybox
	player = g.player
	loadout = g.loadout
	player.scripted = true
	loadout.net_driven = true
	var a := NetworkManager.args
	var dir := String(a["gear-capture"])
	if dir == "true":
		dir = ProjectSettings.globalize_path("user://gear")
	DirAccess.make_dir_recursive_absolute(dir)
	var keys: Array = String(a.get("gear", ",".join(Weapons.ORDER))).split(",")
	var shots: Array = String(a.get("gear-shots", "hip,ads,reload,fire")).split(",")
	_run(dir, keys, shots)


func _physics_process(delta: float) -> void:
	if loadout == null:
		return
	var cmd := NetCmd.new()
	_seq += 1
	cmd.seq = _seq
	cmd.fire = _fire
	cmd.aim = _aim
	cmd.reload = _reload
	cmd.tool = _tool
	loadout.apply_cmd(cmd, delta)
	# Scripted players skip the normal input-driven camera zoom; reproduce it for honest ADS captures.
	var fov := loadout.ads_fov() if loadout.aiming else player.fov
	player.camera.fov = lerpf(player.camera.fov, fov, clampf(loadout.tuning.ads_speed * delta, 0.0, 1.0))


func _run(dir: String, keys: Array, shots: Array) -> void:
	if not NetworkManager.args.has("gear-hud"):
		for c in g.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	await _wait(120)
	var a := NetworkManager.args
	var pos := Vector3(-0.55, 0.05, -0.6)
	var tgt := Vector3(0.35, 1.35, -10.0)
	if a.has("gear-view"):
		var v := String(a["gear-view"]).split_floats(",")
		pos = Vector3(v[0], v[1], v[2])
		tgt = Vector3(v[3], v[4], v[5])
	var d := tgt - (pos + Vector3(0, 1.65, 0))
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	player.teleport(pos, yaw)
	player.set_look(yaw, rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
	player.camera.make_current()
	if a.has("gear-hud"):
		player.capture_mouse(true)
	if a.has("gear-light"): # neutral inspection light for judging shapes (not used for evidence shots)
		var l := OmniLight3D.new()
		l.light_energy = 1.2
		l.omni_range = 3.0
		l.position = Vector3(-0.3, 0.25, 0.2)
		player.camera.add_child(l)
	for key: String in keys:
		if Weapons.DEFS.has(key):
			if int(Weapons.DEFS[key].slot) == 0:
				loadout.set_gear(key, loadout.secondary)
				_tool = Loadout.Tool.RIFLE
			else:
				loadout.set_gear("", key)
				_tool = Loadout.Tool.SIDEARM
		else:
			_tool = Loadout.key_tool(key)
			loadout.charges[_tool] = 2
		_aim = false
		await _wait(60)
		if "hip" in shots:
			_save(dir, key + "_hip")
		if not Weapons.DEFS.has(key):
			if "use" in shots:
				_fire = true
				await _wait(40)
				_save(dir, key + "_use")
				_fire = false
				await _wait(20)
			continue
		if "ads" in shots:
			_aim = true
			await _wait(40)
			_save(dir, key + "_ads")
			_aim = false
			await _wait(25)
		if "fire" in shots:
			_fire = true
			await _wait(3)
			_save(dir, key + "_fire")
			_fire = false
			await _wait(20)
		if "reload" in shots:
			loadout.mag = 1
			_reload = true
			await _wait(2)
			_reload = false
			var frames := int(loadout.tuning.reload_time * 60.0)
			var last := 0
			for k in [0.3, 0.45, 0.7, 0.88]:
				var f := int(frames * k)
				await _wait(f - last)
				last = f
				_save(dir, "%s_reload_%d" % [key, int(k * 100)])
			await _wait(frames - last + 20)
	if a.has("gear-shop"):
		var loop := MatchLoop.new()
		var session := NetMatch.new()
		session.g = g
		session.is_host = true
		var slot := NetMatch.Slot.new()
		slot.id = 1
		slot.team = 1
		slot.node = player
		slot.lo = loadout
		session.slots[1] = slot
		loop.debug_money = true
		loop.net = session
		loop.credits = 9000
		loop.rules.phase = RoundRules.Phase.PREP
		loop.rules.deadline = 1800
		var shop := ShopMenu.new()
		shop.loop = loop
		g.add_child(shop)
		shop.open()
		await _wait(10)
		_save(dir, "shop")
		shop.free()
		session.free()
		loop.free()
	var report := FileAccess.open(dir.path_join("pose-checks.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(_checks, "\t"))
	print("GEAR_CAPTURE_DONE failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _save(dir: String, n: String) -> void:
	if n.ends_with("_ads"):
		var vm := loadout.viewmodel
		var it := vm.current()
		var sight := GearModels.socket(it.root, "Sight")
		if sight:
			var eye := player.camera.to_local(sight.global_position)
			var ok := Vector2(eye.x, eye.y).length() < .001
			_checks.append({"shot": n, "sight_at_eye": [eye.x, eye.y, eye.z], "centered": ok})
			if not ok:
				_failures += 1
				push_error("ADS sight is off axis: " + n)
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(n + ".jpg")
	print(("  saved " if img.save_jpg(path, 0.9) == OK else "  FAILED ") + path)


func _wait(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
