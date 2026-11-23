extends "res://scripts/world/match_scene.gd"
## Original office demo and its regression fixtures.
const CEIL := 2.8
const DUCT_Z := -10.5
const DUCT_H := 1.5

func _start_tools() -> bool:
	if net_mode:
		if not NetworkManager.args.has("net-test"):
			return false
		player.scripted = true
		loadout.bot = true
		loadout.use_recoil = false
		var nt := NetTest.new()
		add_child(nt)
		nt.start(self)
	elif NetworkManager.args.has("smoke-graybox"):
		player.scripted = true
		_run_smoke()
	elif NetworkManager.args.has("smoke-combat"):
		loadout.use_recoil = false
		player.scripted = true
		_run_smoke_combat()
	elif NetworkManager.args.has("gear-capture"):
		var gc := GearCapture.new()
		add_child(gc)
		gc.start(self)
	elif NetworkManager.args.has("capture") or NetworkManager.args.has("bench"):
		var bench := SliceBench.new()
		add_child(bench)
		bench.start(self)
	else:
		return false
	return true


func _build_level() -> void:
	var ORDINARY := Surfaces.get_mat("plaster")
	var REINFORCED := Surfaces.get_mat("metal_plate")
	_box("Floor", Vector3(-1.7, -0.2, -13.2), Vector3(9.7, 0.0, 0.2), Surfaces.get_mat("carpet"))
	if net_mode:
		_box("ExteriorWalkway", Vector3(-5, -0.2, -17), Vector3(13, -0.01, 4), Surfaces.get_mat("asphalt"))
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
	if not net_mode:
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
	if not net_mode:
		_box("ScaleFigure_1.8m", Vector3(7.0, 0.0, -5.0), Vector3(7.5, 1.8, -5.5), null)
		var fig := StandIn.build(StandIn.TEAM_BLUE)
		fig.position = Vector3(7.25, 0.0, -5.25)
		fig.rotation.y = deg_to_rad(110)
		add_child(fig)
	_box("Crate_1.0m", Vector3(4.0, 0.0, -3.0), Vector3(5.0, 1.0, -4.0), Surfaces.get_mat("case"))
	# Practice targets in the room (x=8.4, facing the divider) and one by the corridor wall facing the corridor.
	# Offline only: in a session the other players are the targets.
	for t in [] if net_mode else [["Target_1", Vector3(8.4, 0.0, -6.0), 90.0], ["Target_2", Vector3(8.4, 0.0, -3.5), 90.0], ["Target_3", Vector3(-1.1, 0.0, -9.0), -150.0]]:
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
	if net_mode and mat < 0:
		mat = WallModule.Mat.ORDINARY
	if mat >= 0:
		_module(wall_name, a, b, mat, col)
	else:
		_box(wall_name, a, b, col)


## Wall running along X at fixed z (centre line), spanning x0..x1.
func _wall_z(wall_name: String, z: float, x0: float, x1: float, thick: float, y0: float, y1: float, col: Material) -> void:
	if net_mode:
		_module(wall_name, Vector3(x0, y0, z - thick * 0.5), Vector3(x1, y1, z + thick * 0.5),
			WallModule.Mat.REINFORCED if thick > 0.3 else WallModule.Mat.ORDINARY, col)
	else:
		_box(wall_name, Vector3(x0, y0, z - thick * 0.5), Vector3(x1, y1, z + thick * 0.5), col)


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
	_check("hit does damage + marker", is_equal_approx(t1.health, 100.0 - lo.tuning.damage) and lo.hit_marker > 0.0 and lo.mag == 29)
	_check("fire rate gate", lo.fire_rifle().is_empty())
	var to_kill := ceili(100.0 / lo.tuning.damage) # quick time-to-kill: 3 rifle body hits
	for i in to_kill - 1:
		await _frames(8)
		lo.fire_rifle()
	_check("%d hits down the target" % to_kill, not t1.alive and lo.mag == 30 - to_kill and t1.collision_layer == 0)
	_stand_at(Vector3(3.0, 0.05, -6.0), 0.0)
	await _frames(8)
	r = lo.fire_rifle()
	_check("plaster wall shot penetrates, leaves one bounded mark", int(r.get("penetrated", 0)) == 1 and lo.visible_marks() == 1,
		"pen=%d marks=%d" % [int(r.get("penetrated", 0)), lo.visible_marks()])

	# --- reload / dry fire
	_check("reload starts", lo.start_reload() and lo.reloading)
	await _frames(8)
	_check("cannot fire while reloading", lo.fire_rifle().is_empty() and lo.mag == 29 - to_kill)
	await _frames(40)
	_check("reload fills mag from reserve", not lo.reloading and lo.mag == 30 and lo.reserve == 89 - to_kill, "mag=%d res=%d" % [lo.mag, lo.reserve])
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

	# --- reinforcement: timed install, interruption, rejection, penetration, heavy-only breach
	var kit := NetCmd.new()
	kit.tool = Loadout.Tool.REINFORCE
	kit.fire = true
	var seq := 5000
	_stand_at(Vector3(0.5, 0.05, -2.75), -90.0)
	await _frames(5)
	lo.select(Loadout.Tool.REINFORCE)
	lo.apply_cmd(NetCmd.new(), 1.0 / 60.0)
	kit.seq = seq
	lo.apply_cmd(kit, 1.0 / 60.0)
	_check("already-reinforced panel can't take a kit", wall_b.material == WallModule.Mat.REINFORCED and lo.install_left <= 0.0
		and int(lo.charges[Loadout.Tool.REINFORCE]) == 2, lo.last_message)
	var open := NetCmd.new()
	open.tool = Loadout.Tool.REINFORCE
	lo.apply_cmd(open, 1.0 / 60.0)
	_stand_at(Vector3(0.5, 0.05, -8.25), -90.0)
	await _frames(5)
	lo.apply_cmd(open, 1.0 / 60.0)
	_check("ordinary panel stops rounds only after reinforcement", is_equal_approx(float(wall_d.get_meta("pen_mult")), WallModule.ORDINARY_PEN_MULT))
	for i in 60:
		seq += 1
		kit.seq = seq
		lo.apply_cmd(kit, 1.0 / 60.0)
	_check("install is progressing but not committed", lo.install_left > 0.0 and wall_d.material == WallModule.Mat.ORDINARY
		and int(lo.charges[Loadout.Tool.REINFORCE]) == 2)
	lo.apply_cmd(open, 1.0 / 60.0)
	_check("releasing fire interrupts the install", lo.install_left <= 0.0 and wall_d.material == WallModule.Mat.ORDINARY)
	for i in 40:
		seq += 1
		kit.seq = seq
		lo.apply_cmd(kit, 1.0 / 60.0)
	_stand_at(Vector3(-0.5, 0.05, -5.4), 90.0) # looking at a non-breachable surface cancels progress
	await _frames(2)
	seq += 1
	kit.seq = seq
	lo.apply_cmd(kit, 1.0 / 60.0)
	_check("looking away cancels the install", lo.install_left <= 0.0 and wall_d.material == WallModule.Mat.ORDINARY)
	lo.apply_cmd(open, 1.0 / 60.0)
	_stand_at(Vector3(0.5, 0.05, -8.25), -90.0)
	await _frames(5)
	lo.apply_cmd(open, 1.0 / 60.0)
	for i in int(lo.tuning.reinforce_time * 60.0) + 5:
		seq += 1
		kit.seq = seq
		lo.apply_cmd(kit, 1.0 / 60.0)
	_check("held install reinforces the panel and spends one kit", wall_d.material == WallModule.Mat.REINFORCED and wall_d.revision == 1
		and wall_d.state == WallModule.State.INTACT and int(lo.charges[Loadout.Tool.REINFORCE]) == 1, lo.last_message)
	_check("reinforced panel stops rifle rounds (pen_mult 0) and keeps matching collision", float(wall_d.get_meta("pen_mult")) == 0.0 and _parts_match(wall_d))
	lo.apply_cmd(open, 1.0 / 60.0)
	lo.select(Loadout.Tool.ORDINARY_CHARGE)
	_check("ordinary charge now refused on it", not lo.place_charge() and wall_d.state == WallModule.State.INTACT, lo.last_message)
	lo.select(Loadout.Tool.HEAVY_CHARGE)
	_check("heavy charge accepted on reinforced panel", lo.place_charge())
	_check("shipping tuning: heavy charge warns longer and costs more", WEAPON_TUNING.heavy_fuse > WEAPON_TUNING.ordinary_fuse
		and preload("res://data/match_tuning.tres").price_heavy > preload("res://data/match_tuning.tres").price_ordinary)
	_check("panel with an armed charge can't be reinforced", not wall_d.can_reinforce())
	await _frames(int(lo.tuning.heavy_fuse * 60.0) + 15)
	_check("reinforced panel breached by heavy charge (revision 2)", wall_d.state == WallModule.State.BREACHED and wall_d.revision == 2)
	_check("breached reinforced panel can't be reinforced again", not wall_d.reinforce())

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
		and wall_b.state == WallModule.State.INTACT and wall_d.state == WallModule.State.INTACT and wall_b.mesh_count() == 1
		and wall_d.material == WallModule.Mat.ORDINARY and float(wall_d.get_meta("pen_mult")) == WallModule.ORDINARY_PEN_MULT)
	_check("restart: targets restored", t1.alive and is_equal_approx(t1.health, 100.0) and t1.collision_layer == 4 and t1.rotation.x == 0.0)
	_check("restart: loadout restored", lo.mag == 30 and lo.reserve == 90 and lo.tool == Loadout.Tool.RIFLE
		and lo.charges[Loadout.Tool.ORDINARY_CHARGE] == 3 and lo.charges[Loadout.Tool.HEAVY_CHARGE] == 2 and int(lo.charges[Loadout.Tool.REINFORCE]) == 2 and lo.active_charges.is_empty())
	_check("restart: marks and effects cleared", lo.visible_marks() == 0 and lo.effects.active == 0 and lo.effects.get_child_count() == 0)
	_check("restart: player at spawn", player.global_position.distance_to(_spawn.global_position) < 0.1)
	_stand_at(Vector3(0.5, 0.05, -5.4), -90.0)
	player.script_move = Vector2(0, -1)
	await _frames(100)
	_check("restart: wall blocks again", player.global_position.x < 1.1, "x=%.2f" % player.global_position.x)

	# --- gun tiers, sidearm fallback, medkit
	var gun := NetCmd.new()
	gun.fire = true
	var idle := NetCmd.new()
	player.script_move = Vector2.ZERO
	lo.set_gear("", "p9")
	lo.apply_cmd(idle, 1.0 / 60.0)
	_check("no primary: key 1 selects the sidearm", lo.tool == Loadout.Tool.SIDEARM and lo.weapon_id() == "p9" and lo.mag == 12
		and is_equal_approx(lo.tuning.damage, Weapons.DEFS["p9"].damage))
	var shots0 := lo.shots_fired
	for i in 10:
		lo.apply_cmd(gun, 1.0 / 60.0)
	_check("pistol is semi-auto: one shot per trigger pull", lo.shots_fired == shots0 + 1, "shots=%d" % (lo.shots_fired - shots0))
	lo.set_gear("smg", "p9")
	_check("new primary arrives with full ammo and its stats", lo.primary == "smg", "tool=%d" % lo.tool)
	lo.apply_cmd(idle, 1.0 / 60.0)
	lo.select(Loadout.Tool.RIFLE)
	_check("SMG wielded: 30 rounds, automatic", lo.weapon_id() == "smg" and lo.mag == 30 and lo.tuning.auto and is_equal_approx(lo.tuning.damage, Weapons.DEFS["smg"].damage))
	lo.select(Loadout.Tool.SIDEARM)
	_check("sidearm keeps its own ammo", lo.weapon_id() == "p9" and lo.mag == 11 and is_equal_approx(lo.tuning.damage, Weapons.DEFS["p9"].damage), "mag=%d" % lo.mag)
	var healed := [0.0]
	lo.healed.connect(func(a: float) -> void: healed[0] += a)
	lo.charges[Loadout.Tool.MEDKIT] = 2
	var med := NetCmd.new()
	med.tool = Loadout.Tool.MEDKIT
	med.fire = true
	var med_idle := NetCmd.new()
	med_idle.tool = Loadout.Tool.MEDKIT
	lo.apply_cmd(med_idle, 1.0 / 60.0)
	for i in 60:
		lo.apply_cmd(med, 1.0 / 60.0)
	lo.apply_cmd(med_idle, 1.0 / 60.0)
	_check("releasing interrupts healing, no kit spent", healed[0] == 0.0 and int(lo.charges[Loadout.Tool.MEDKIT]) == 2)
	for i in 200:
		lo.apply_cmd(med, 1.0 / 60.0)
	_check("held medkit heals 50 once and is consumed", healed[0] == 50.0 and int(lo.charges[Loadout.Tool.MEDKIT]) == 1, "healed=%.0f kits=%d" % [healed[0], lo.charges[Loadout.Tool.MEDKIT]])

	if _fails == 0:
		print("SMOKE_OK combat")
		get_tree().quit(0)
	else:
		print("SMOKE_FAIL combat failures=", _fails)
		get_tree().quit(1)


## Collision shapes and meshes of a module must match its authored part list exactly.
