class_name WeaponTuning
extends Resource
## Rifle and breach-charge tuning. Edit weapon_tuning.tres in the inspector.

@export_group("Rifle")
@export var damage := 20.0
@export var fire_interval := 0.1
@export var mag_size := 30
@export var reserve_start := 90
@export var reload_time := 1.8
@export var range_m := 120.0
@export var spread_hip_deg := 0.7
@export var spread_aim_deg := 0.1
## Restrained upward camera kick per shot (degrees).
@export var kick_deg := 0.3
@export var ads_fov_mult := 0.8
@export var ads_speed := 12.0
@export_group("Muzzle")
## Camera-local offset (-Z is forward). Cover closer than this blocks shots.
@export var muzzle_offset := Vector3(0.18, -0.14, -0.45)
@export_group("Charges")
@export var ordinary_count := 3
@export var heavy_count := 2
@export var ordinary_fuse := 3.0
@export var heavy_fuse := 4.0
@export var place_reach := 2.5
@export var warn_radius := 3.5
