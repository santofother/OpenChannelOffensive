class_name Player
extends CharacterBody3D
## First-person walk/crouch controller. Origin is at the feet. Esc releases the mouse; a click recaptures it.
## Movement is a pure step: simulate(NetCmd, delta). Offline it runs every physics tick from make_cmd();
## in a session NetMatch drives it (net_driven) on the host (authority) and on the owner (prediction/replay).

signal mouse_capture_changed(captured: bool)
signal reset_requested

const SETTINGS_PATH := "user://settings.cfg"

@export var tuning: PlayerTuning

@onready var _shape: CollisionShape3D = $Shape
@onready var _head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera

var look_sensitivity := 1.0 ## multiplier on tuning.base_sensitivity
var fov := 90.0
var crouched := false ## intent/state: true while crouching or forced down by a low ceiling
var height := 1.8
var input_enabled := true
var spawn_transform := Transform3D.IDENTITY
var movement_loadout: Node
var net_driven := false ## NetMatch calls simulate(); _physics_process does nothing

## Headless tests drive the player through these instead of the keyboard.
var scripted := false
var script_move := Vector2.ZERO ## x = right, y = back (same as Input.get_vector)
var script_crouch := false
var script_slow_walk := false
var script_lean := 0
var script_vault := false
var lean := 0.0 ## collision-limited fraction, -1 left / +1 right
var _lean_probe := SphereShape3D.new()

var _pitch := 0.0
var _stand_probe := CapsuleShape3D.new()
var _capsule: CapsuleShape3D


func _ready() -> void:
	if tuning == null:
		tuning = PlayerTuning.new()
	_capsule = (_shape.shape as CapsuleShape3D).duplicate()
	_shape.shape = _capsule
	_capsule.radius = tuning.radius
	_lean_probe.radius = Ballistics.PLAYER_RADIUS + 0.015
	_stand_probe.radius = tuning.radius - 0.02
	_stand_probe.height = tuning.stand_height - 0.04
	height = tuning.stand_height
	look_sensitivity = tuning.default_sensitivity
	fov = tuning.default_fov
	_load_settings()
	_apply_height()
	camera.fov = fov
	spawn_transform = global_transform


func _unhandled_input(event: InputEvent) -> void:
	if scripted or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var s := tuning.base_sensitivity * look_sensitivity
		rotate_y(-m.relative.x * s)
		_pitch = clampf(_pitch - m.relative.y * s, -deg_to_rad(tuning.pitch_limit_deg), deg_to_rad(tuning.pitch_limit_deg))
		_head.rotation.x = _pitch
		_limit_lean()
		_apply_lean()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse(true)
	elif event.is_action_pressed("menu"):
		capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("reset"):
		if reset_requested.get_connections().is_empty():
			reset()
		else:
			reset_requested.emit()


func capture_mouse(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(on)


func set_fov(value: float) -> void:
	fov = clampf(value, tuning.min_fov, tuning.max_fov)
	camera.fov = fov


var _step_distance := 0.0
var _step_moving := false
var _step_index := 0
var _last_step_gait := ProcAudio.Gait.WALK

func reset_steps() -> void:
	_step_distance = 0.0
	_step_moving = false

## Called only after a fresh offline, predicted or authoritative step.
func movement_cue(before: Vector3, grounded: bool, world: Node3D, command: NetCmd) -> Array:
	if not grounded or not is_on_floor():
		reset_steps()
		return []
	var travel := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var gait := ProcAudio.Gait.CROUCH if crouched else (ProcAudio.Gait.SLOW if command.slow_walk else ProcAudio.Gait.WALK)
	if gait == ProcAudio.Gait.WALK and movement_speed(command.tool) > tuning.walk_speed:
		gait = ProcAudio.Gait.RUN
	var variant := -1
	if travel < 0.003:
		gait = _last_step_gait
		if _step_moving:
			variant = 5
		reset_steps()
	elif travel < 0.22:
		_last_step_gait = gait
		_step_distance += travel
		var stride := ProcAudio.STEP_STRIDE[gait] as float
		if not _step_moving and _step_distance >= 0.17:
			_step_moving = true
			_step_distance = 0.0
			variant = 4
		elif _step_moving and _step_distance >= stride:
			_step_distance -= stride
			variant = _step_index % 4
			_step_index += 1
	if variant < 0:
		return []
	return [int(world.footstep_surface(global_position)) * 6 + variant, global_position + Vector3.UP * 0.18, gait]


func reset() -> void:
	reset_steps()
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	_pitch = 0.0
	_head.rotation.x = 0.0
	lean = 0.0
	_apply_lean()
	crouched = false
	height = tuning.stand_height
	_apply_height()


## Two-axis view impulse (radians). Absolute look in the next command includes recoil and mouse compensation.
func kick(pitch_rad: float, yaw_rad: float = 0.0) -> void:
	rotate_y(yaw_rad)
	_limit_lean()
	_apply_lean()
	_pitch = clampf(_pitch + pitch_rad, -deg_to_rad(tuning.pitch_limit_deg), deg_to_rad(tuning.pitch_limit_deg))
	_head.rotation.x = _pitch


func teleport(pos: Vector3, yaw_deg: float) -> void:
	reset_steps()
	lean = 0.0
	_apply_lean()
	global_position = pos
	rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	velocity = Vector3.ZERO


## Sets view direction directly (scripted captures/benchmarks).
func set_look(yaw_deg: float, pitch_deg: float) -> void:
	rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	_pitch = clampf(deg_to_rad(pitch_deg), -deg_to_rad(tuning.pitch_limit_deg), deg_to_rad(tuning.pitch_limit_deg))
	_head.rotation.x = _pitch


func can_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _stand_probe
	q.transform = Transform3D(Basis(), global_position + Vector3(0.0, tuning.stand_height * 0.5 + 0.02, 0.0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _physics_process(delta: float) -> void:
	if net_driven:
		return
	if global_position.y < -20.0:
		reset()
	var before := global_position
	var grounded := is_on_floor()
	var command := make_cmd()
	simulate(command, delta)
	var world := get_parent()
	if world.has_method("footstep_surface"):
		var cue := movement_cue(before, grounded, world, command)
		if not cue.is_empty():
			ProcAudio.player_cue(world, int(cue[0]), int(cue[2]))


func pitch() -> float:
	return _pitch


## Movement/look intent for this tick from the keyboard or the scripted fields. Buttons are filled by Loadout.
func make_cmd() -> NetCmd:
	var c := NetCmd.new()
	c.yaw = rotation.y
	c.pitch = _pitch
	if scripted:
		c.move = script_move
		c.crouch = script_crouch
		c.slow_walk = script_slow_walk
		c.lean = script_lean
		c.vault = script_vault
	elif input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		c.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		c.crouch = Input.is_action_pressed("crouch")
		c.slow_walk = Input.is_action_pressed("slow_walk")
		c.vault = Input.is_action_pressed("jump")
		c.lean = int(Input.is_action_pressed("lean_right")) - int(Input.is_action_pressed("lean_left"))
	if movement_loadout:
		c.tool = movement_loadout.want_tool
	return c


## One deterministic movement step. Same code offline, on the host and in client replay.
func simulate(cmd: NetCmd, delta: float) -> void:
	rotation = Vector3(0.0, cmd.yaw, 0.0)
	_pitch = clampf(cmd.pitch, -deg_to_rad(tuning.pitch_limit_deg), deg_to_rad(tuning.pitch_limit_deg))
	_head.rotation.x = _pitch
	var move := cmd.move
	var want_crouch := cmd.crouch

	# Crouch: release only when the standing capsule fits; otherwise stay down.
	if want_crouch:
		crouched = true
	elif crouched and can_stand():
		crouched = false
	var target_h := tuning.crouch_height if crouched else tuning.stand_height
	height = move_toward(height, target_h, tuning.crouch_height_speed * delta)
	_apply_height()

	var speed := movement_speed(cmd.tool)
	if crouched:
		speed = tuning.crouch_speed
	elif cmd.slow_walk:
		speed = tuning.slow_walk_speed
	var wish := (global_transform.basis * Vector3(move.x, 0.0, move.y))
	wish.y = 0.0
	wish = wish.normalized() * minf(move.length(), 1.0) * speed

	var on_floor := is_on_floor()
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var rate := tuning.air_accel
	if on_floor:
		rate = tuning.ground_accel if wish.length() > 0.01 else tuning.ground_friction
	hv = hv.move_toward(wish, rate * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if on_floor:
		velocity.y = -0.5
	else:
		velocity.y -= tuning.gravity * delta
	if on_floor and cmd.vault and not crouched and wish.length_squared() > 0.1:
		_try_vault(wish.normalized())
	move_and_slide()
	var target_lean := float(clampi(cmd.lean, -1, 1))
	lean = move_toward(lean, target_lean, tuning.lean_speed * delta)
	_limit_lean()
	_apply_lean()


## Sweep the body up and over, then require solid, walkable footing on the obstacle.
## Using the player capsule for all legs prevents bypassing low ceilings or adjacent walls.
func _try_vault(direction: Vector3) -> void:
	var start := global_transform
	var shin := start.origin + Vector3.UP * 0.24
	var space := get_world_3d().direct_space_state
	var reach := tuning.radius + 0.46
	var front := space.intersect_ray(PhysicsRayQueryParameters3D.create(shin, shin + direction * reach, 1))
	if front.is_empty() or absf(front.normal.y) > 0.45:
		return
	var across := direction * (shin.distance_to(front.position) + tuning.radius + 0.12)
	var lift := Vector3.UP * 0.97
	const MARGIN := 0.002
	if test_move(start, lift, null, MARGIN):
		return
	var raised := start.translated(lift)
	if test_move(raised, across, null, MARGIN):
		return
	var over := raised.translated(across)
	var landing := KinematicCollision3D.new()
	if not test_move(over, Vector3.DOWN * 0.80, landing, MARGIN) or landing.get_normal().y < 0.76:
		return
	var dest := over.origin + landing.get_travel() + Vector3.UP * 0.003
	if dest.y - start.origin.y > 0.91:
		return
	global_position = dest

func movement_speed(selected: int) -> float:
	if selected != Loadout.Tool.RIFLE and selected != Loadout.Tool.SIDEARM:
		return tuning.unarmed_speed
	if selected == Loadout.Tool.SIDEARM or (selected == Loadout.Tool.RIFLE and movement_loadout and movement_loadout.primary == ""):
		return tuning.secondary_speed
	return tuning.walk_speed


## Movement state for prediction/reconciliation.
func get_move_state() -> Dictionary:
	return {"pos": global_position, "vel": velocity, "crouched": crouched, "height": height, "lean": lean}


func set_move_state(pos: Vector3, vel: Vector3, is_crouched: bool, h: float, lean_state: float = 0.0) -> void:
	global_position = pos
	velocity = vel
	crouched = is_crouched
	height = h
	lean = lean_state
	_apply_height()
	_limit_lean()
	_apply_lean()


func _apply_height() -> void:
	_capsule.height = height
	_shape.position.y = height * 0.5
	_head.position.y = height - tuning.eye_below_top


## Cast a head-sized volume from the unleaned eye. Recheck after movement/turning/crouching so a
## held lean cannot carry the camera through cover. World collision is shared by authority and prediction.
func _limit_lean() -> void:
	if is_zero_approx(lean):
		return
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _lean_probe
	q.collision_mask = 1
	q.exclude = [get_rid()]
	q.margin = 0.01
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (height - tuning.eye_below_top))
	q.motion = global_basis.x * lean * tuning.lean_distance
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(q, 1).is_empty():
		lean = 0.0
		return
	var fraction := space.cast_motion(q)
	lean *= fraction[0]


func _apply_lean() -> void:
	_head.position.x = lean * tuning.lean_distance
	camera.rotation.z = -lean * deg_to_rad(tuning.lean_roll_deg)


func lean_offset() -> Vector3:
	return global_basis.x * lean * tuning.lean_distance


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("look", "sensitivity", look_sensitivity)
	cfg.set_value("look", "fov", fov)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	if scripted:
		return
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	look_sensitivity = clampf(float(cfg.get_value("look", "sensitivity", look_sensitivity)), 0.1, 5.0)
	fov = clampf(float(cfg.get_value("look", "fov", fov)), tuning.min_fov, tuning.max_fov)
