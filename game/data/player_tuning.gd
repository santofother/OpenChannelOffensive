class_name PlayerTuning
extends Resource
## Movement and camera tuning for the first-person controller. Edit player_tuning.tres in the inspector.

@export_group("Speed (m/s)")
@export var walk_speed := 2.8
@export var secondary_speed := 3.15
@export var unarmed_speed := 3.4
@export var slow_walk_speed := 1.65
@export var crouch_speed := 1.2
@export_group("Acceleration (m/s^2)")
@export var ground_accel := 38.0
@export var ground_friction := 46.0
@export var air_accel := 6.0
@export var gravity := 20.0
@export_group("Body (m)")
@export var radius := 0.35
@export var stand_height := 1.8
@export var crouch_height := 1.2
## Eye sits this far below the top of the capsule.
@export var eye_below_top := 0.15
@export var crouch_height_speed := 5.0
@export_group("Lean")
@export var lean_distance := 0.38
@export var lean_roll_deg := 12.0
@export var lean_speed := 4.0 ## fractions of full lean per second
@export_group("Camera")
## Radians per pixel at sensitivity multiplier 1.0.
@export var base_sensitivity := 0.0022
@export var default_sensitivity := 1.0
@export var default_fov := 90.0
@export var min_fov := 60.0
@export var max_fov := 110.0
@export var pitch_limit_deg := 89.0
