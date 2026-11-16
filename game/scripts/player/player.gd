class_name Player
extends CharacterBody3D
## First-person walk/crouch controller. Offline for now; Session M2 adds host authority/prediction.
## Origin is at the feet. Esc releases the mouse; a click recaptures it.

signal mouse_capture_changed(captured: bool)

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

## Headless tests drive the player through these instead of the keyboard.
var scripted := false
var script_move := Vector2.ZERO ## x = right, y = back (same as Input.get_vector)
var script_crouch := false
var script_sprint := false

var _pitch := 0.0
var _stand_probe := CapsuleShape3D.new()
var _capsule: CapsuleShape3D


func _ready() -> void:
	if tuning == null:
		tuning = PlayerTuning.new()
	_capsule = (_shape.shape as CapsuleShape3D).duplicate()
	_shape.shape = _capsule
	_capsule.radius = tuning.radius
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
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse(true)
	elif event.is_action_pressed("menu"):
		capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("reset"):
		reset()


func capture_mouse(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(on)


func set_fov(value: float) -> void:
	fov = clampf(value, tuning.min_fov, tuning.max_fov)
	camera.fov = fov


func reset() -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	_pitch = 0.0
	_head.rotation.x = 0.0
	crouched = false
	height = tuning.stand_height
	_apply_height()


func teleport(pos: Vector3, yaw_deg: float) -> void:
	global_position = pos
	rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	velocity = Vector3.ZERO


func can_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _stand_probe
	q.transform = Transform3D(Basis(), global_position + Vector3(0.0, tuning.stand_height * 0.5 + 0.02, 0.0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _physics_process(delta: float) -> void:
	if global_position.y < -20.0:
		reset()
	var move := Vector2.ZERO
	var want_crouch := false
	var want_sprint := false
	if scripted:
		move = script_move
		want_crouch = script_crouch
		want_sprint = script_sprint
	elif input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want_crouch = Input.is_action_pressed("crouch")
		want_sprint = Input.is_action_pressed("sprint")

	# Crouch: release only when the standing capsule fits; otherwise stay down.
	if want_crouch:
		crouched = true
	elif crouched and can_stand():
		crouched = false
	var target_h := tuning.crouch_height if crouched else tuning.stand_height
	height = move_toward(height, target_h, tuning.crouch_height_speed * delta)
	_apply_height()

	var speed := tuning.walk_speed
	if crouched:
		speed = tuning.crouch_speed
	elif want_sprint and move.y < 0.0:
		speed = tuning.sprint_speed
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
	move_and_slide()


func _apply_height() -> void:
	_capsule.height = height
	_shape.position.y = height * 0.5
	_head.position.y = height - tuning.eye_below_top


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
