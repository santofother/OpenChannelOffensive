class_name SliceBench
extends Node
## Session 04 evidence tools for the graybox office. Needs a real window (not --headless).
##   --capture[=<abs dir>]   Saves the reference views + F1-F3 cams, intact then breached, as JPGs, then quits.
##   --bench[=<seconds>]      Drives the player along a fixed walk/breach/shoot loop and records frame times
##                            (VSync off unless --vsync). Prints BENCH_RESULT <json>; --bench-out=<abs path> saves it.
## Both work in exported builds: main.gd forwards these args to the graybox scene.

const EYE := 1.65
const WARMUP := 5.0
## Waypoints [x, z, action]. Actions: ordinary:<wall id>, heavy:<wall id>, wait:<s>, fire:<target name>.
const PATH := [
	[0.0, -1.0, ""], [0.0, -5.4, "ordinary:Divider_C_ordinary"], [0.0, -8.0, "wait:3.5"],
	[0.3, -5.4, ""], [3.0, -5.4, ""], [6.0, -6.6, "fire:Target_1"], [8.3, -7.0, ""], [5.0, -6.6, ""],
	[3.0, -4.6, ""], [0.0, -4.0, ""], [0.0, -2.75, "heavy:Divider_B_reinforced"], [0.0, -0.8, "wait:4.5"],
	[0.0, -2.75, ""], [3.0, -2.75, ""], [6.5, -2.6, "fire:Target_2"], [3.0, -2.6, ""], [3.0, -5.4, ""],
	[0.3, -5.4, ""], [0.0, -9.5, "fire:Target_3"], [0.0, -1.0, ""],
]

var g: Node3D
var player: Player
var loadout: Loadout
var _frames: PackedFloat32Array = []
var _draws: PackedInt32Array = []
var _prims: PackedInt32Array = []
var _breach_frame := -1
var _last_us := 0
var _measuring := false
var _wp := 0
var _wp_time := 0.0
var _busy := false
var _t := 0.0
var _spikes: Array = [] ## [seconds into measurement, ms, waypoint index, action]
var _last_action := ""


func start(graybox: Node3D) -> void:
	g = graybox
	player = g.player
	loadout = g.loadout
	player.scripted = true
	var a := NetworkManager.args
	if a.has("capture"):
		var dir := String(a["capture"])
		if dir == "true":
			dir = ProjectSettings.globalize_path("user://captures")
		_capture(dir)
	elif a.has("bench"):
		var secs := 60.0 if String(a["bench"]) == "true" else float(a["bench"])
		_bench(secs)


# ---------------------------------------------------------------- capture

func _capture(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for c in g.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	await _wait(150) # noise textures generate on threads; let SSAO/shadows settle
	var views := [
		["A_quiet_approach", Vector3(-0.55, 0.05, -0.6), Vector3(0.35, 1.35, -10.0)],
		["B_reinforced_breach", Vector3(-0.95, 0.05, -0.8), Vector3(1.5, 1.4, -4.3)],
		["C_room_to_corridor", Vector3(6.6, 0.05, -6.2), Vector3(1.5, 1.2, -4.6)],
		["D_room_exterior", Vector3(2.4, 0.05, -4.9), Vector3(9.6, 1.4, -6.2)],
	]
	var saved := 0
	for state in ["intact", "breached"]:
		if state == "breached":
			for m: WallModule in g.modules:
				m.breach(WallModule.Kind.HEAVY if m.material == WallModule.Mat.REINFORCED else WallModule.Kind.ORDINARY)
			await _wait(20)
		for v in views:
			player.camera.make_current()
			_look_from(v[1], v[2])
			await _wait(45)
			saved += int(_save(dir, "%s_%s" % [v[0], state]))
		for i in g._cams.size():
			(g._cams[i] as Camera3D).make_current()
			await _wait(30)
			saved += int(_save(dir, "F%d_%s_%s" % [i + 1, g._cams[i].name, state]))
		player.camera.make_current()
	print("CAPTURE_OK saved=%d dir=%s size=%s" % [saved, dir, get_viewport().get_visible_rect().size])
	get_tree().quit(0)


func _save(dir: String, n: String) -> bool:
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(n + ".jpg")
	var ok := img.save_jpg(path, 0.88) == OK
	print(("  saved " if ok else "  FAILED ") + path)
	return ok


func _look_from(pos: Vector3, target: Vector3) -> void:
	player.teleport(pos, _yaw_to(pos, target))
	var eye := pos + Vector3(0, EYE, 0)
	var d := target - eye
	player.set_look(_yaw_to(pos, target), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return rad_to_deg(atan2(-d.x, -d.z))


func _wait(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


# ---------------------------------------------------------------- benchmark

func _bench(secs: float) -> void:
	if not NetworkManager.args.has("vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var nodes_start := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	await get_tree().create_timer(WARMUP).timeout
	_measuring = true
	_last_us = Time.get_ticks_usec()
	await get_tree().create_timer(secs).timeout
	_measuring = false
	var res := {
		"build_id": NetworkManager.build_id,
		"os": OS.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"window": str(get_viewport().get_visible_rect().size),
		"screen_scale": DisplayServer.screen_get_scale(),
		"vsync": NetworkManager.args.has("vsync"),
		"debug_build": OS.is_debug_build(),
		"seconds": secs,
		"frames": _frames.size(),
		"all": _stats(_frames),
		"pre_breach": _stats(_frames.slice(0, _breach_frame if _breach_frame >= 0 else _frames.size())),
		"post_breach": _stats(_frames.slice(_breach_frame)) if _breach_frame >= 0 else {},
		"draw_calls_avg": _avg(_draws), "draw_calls_max": _max(_draws),
		"primitives_avg": _avg(_prims),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"nodes_start": nodes_start, "nodes_end": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"walls_breached": g.modules.filter(func(m: WallModule) -> bool: return m.state == WallModule.State.BREACHED).size(),
		"waypoints_visited": _wp,
		"spikes_over_33ms": _spikes,
	}
	var txt := JSON.stringify(res)
	print("BENCH_RESULT " + txt)
	var out := String(NetworkManager.args.get("bench-out", ProjectSettings.globalize_path("user://bench_result.json")))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(res, "  "))
		print("BENCH_SAVED " + out)
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if not _measuring:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_t += ms / 1000.0
	_frames.append(ms)
	if ms > 33.3 and _spikes.size() < 20:
		_spikes.append([snappedf(_t, 0.01), snappedf(ms, 0.1), _wp, _last_action])
	_last_us = now
	_draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	if _breach_frame < 0 and g.modules.any(func(m: WallModule) -> bool: return m.state == WallModule.State.BREACHED):
		_breach_frame = _frames.size()


func _physics_process(delta: float) -> void:
	if g == null or not _measuring or _busy:
		return
	var wp: Array = PATH[_wp % PATH.size()]
	var target := Vector3(wp[0], player.global_position.y, wp[1])
	var to := target - player.global_position
	to.y = 0.0
	_wp_time += delta
	if to.length() < 0.25 or _wp_time > 8.0:
		player.script_move = Vector2.ZERO
		_wp_time = 0.0
		_busy = true
		await _act(String(wp[2]))
		_busy = false
		_wp += 1
		return
	player.set_look(_yaw_to(player.global_position, target), 0.0)
	player.script_move = Vector2(0, -1)


func _act(action: String) -> void:
	if action == "":
		return
	_last_action = action
	var kv := action.split(":")
	match kv[0]:
		"ordinary", "heavy":
			var m: WallModule = g._mod(kv[1])
			if m == null or m.state != WallModule.State.INTACT:
				return
			player.set_look(_yaw_to(player.global_position, m.global_position), 0.0)
			loadout.select(Loadout.Tool.ORDINARY_CHARGE if kv[0] == "ordinary" else Loadout.Tool.HEAVY_CHARGE)
			await get_tree().create_timer(0.4).timeout
			loadout.place_charge()
			await get_tree().create_timer(0.3).timeout
			loadout.select(Loadout.Tool.RIFLE)
		"wait":
			await get_tree().create_timer(float(kv[1])).timeout
		"fire":
			var t: Node3D = g.get_node_or_null(kv[1])
			if t == null:
				return
			var eye := player.global_position + Vector3(0, EYE, 0)
			var d := t.global_position + Vector3(0, 1.2, 0) - eye
			player.set_look(_yaw_to(player.global_position, t.global_position), rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
			for i in 6:
				loadout.fire_rifle()
				await get_tree().create_timer(0.13).timeout
			if loadout.mag < 10:
				loadout.start_reload()
				await get_tree().create_timer(loadout.tuning.reload_time + 0.1).timeout


func _stats(a: PackedFloat32Array) -> Dictionary:
	if a.is_empty():
		return {}
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	var total := 0.0
	var over33 := 0
	for v in s:
		total += v
		if v > 33.3:
			over33 += 1
	return {
		"frames": n, "mean_ms": snappedf(total / n, 0.01), "median_ms": snappedf(s[n / 2], 0.01),
		"p95_ms": snappedf(s[mini(int(n * 0.95), n - 1)], 0.01), "p99_ms": snappedf(s[mini(int(n * 0.99), n - 1)], 0.01),
		"max_ms": snappedf(s[n - 1], 0.01), "over_33ms": over33, "avg_fps": snappedf(1000.0 * n / total, 0.1),
	}


func _avg(a: PackedInt32Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0
	for v in a:
		t += v
	return snappedf(float(t) / a.size(), 0.1)


func _max(a: PackedInt32Array) -> int:
	var m := 0
	for v in a:
		m = maxi(m, v)
	return m
