class_name WeaponTuning
extends Resource
## Rifle and breach-charge tuning. Edit weapon_tuning.tres in the inspector.

@export_group("Rifle")
@export var auto := true ## semi-auto guns need a fresh trigger pull per shot
@export var damage := 34.0
@export var head_mult := 4.0 ## headshot damage multiplier (helmets reduce headshots only)
@export var fire_interval := 0.1
@export var mag_size := 30
@export var reserve_start := 90
@export var reload_time := 1.8
@export var range_m := 120.0
@export var spread_hip_deg := 0.7
@export var spread_aim_deg := 0.1
## Vertical impulse scale; automatic weapons build a rising, reversing lateral spray.
@export var kick_deg := 1.0
@export var recoil_side := 1.0
@export var recoil_reset_time := 0.38
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
@export var reinforce_count := 2 ## offline/test default; matches use the shop (MatchTuning)
@export var reinforce_time := 2.5 ## seconds held on one panel; interrupted by looking away or switching
