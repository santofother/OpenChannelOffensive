class_name Viewmodel
extends Node3D
## Placeholder first-person rifle, gloves and held charge built from primitives, animated in code:
## hip/ADS blend, walk bob, recoil kick, reload dip with a mag drop, lower/raise on tool switch.
## Materials use a fixed FOV and a z-clip scale so the model never pokes through nearby walls.
## Purely cosmetic: shots still come from WeaponTuning.muzzle_offset.

const HIP := Vector3(0.15, -0.16, -0.32)
const ADS := Vector3(0.0, -0.093, -0.24)
const VM_FOV := 70.0

var loadout: Loadout
var _rifle: Node3D
var _mag: Node3D
var _charge_ord: Node3D
var _charge_heavy: Node3D
var _ads := 0.0
var _recoil := 0.0
var _lower := 0.0
var _bob_t := 0.0
var _shots := 0
var _mats := {}


func setup(l: Loadout) -> void:
	loadout = l
	name = "Viewmodel"
	_rifle = Node3D.new()
	add_child(_rifle)
	var dark := _mat(Color(0.13, 0.13, 0.135), 0.4, 0.45)
	var polymer := _mat(Color(0.17, 0.16, 0.14), 0.0, 0.7)
	var glove := _mat(Color(0.16, 0.15, 0.13), 0.0, 0.95)
	var sleeve := _mat(Color(0.22, 0.23, 0.18), 0.0, 0.95)
	# Rifle, -Z forward. Origin = sight line.
	_box(_rifle, Vector3(0.05, 0.065, 0.3), Vector3(0, -0.05, 0.0), dark)       # receiver
	_box(_rifle, Vector3(0.056, 0.06, 0.26), Vector3(0, -0.047, -0.27), polymer) # handguard
	_box(_rifle, Vector3(0.022, 0.012, 0.52), Vector3(0, -0.012, -0.12), dark)   # top rail
	_cyl(_rifle, 0.011, 0.12, Vector3(0, -0.045, -0.46), dark)                   # barrel
	_cyl(_rifle, 0.022, 0.15, Vector3(0, -0.045, -0.58), polymer)                # suppressor
	_box(_rifle, Vector3(0.03, 0.085, 0.045), Vector3(0, -0.11, 0.08), polymer, -20.0)  # grip
	_box(_rifle, Vector3(0.042, 0.075, 0.18), Vector3(0, -0.055, 0.24), polymer)  # stock
	_mag = Node3D.new()
	_mag.position = Vector3(0, -0.12, -0.07)
	_rifle.add_child(_mag)
	_box(_mag, Vector3(0.032, 0.13, 0.065), Vector3(0, -0.02, 0), dark, 10.0)
	# Red-dot sight: open frame so ADS looks through it, dot sits on the sight line.
	for s in [-1, 1]:
		_box(_rifle, Vector3(0.006, 0.04, 0.05), Vector3(0.022 * s, 0.008, -0.06), dark)
	_box(_rifle, Vector3(0.05, 0.006, 0.05), Vector3(0, 0.03, -0.06), dark)
	_box(_rifle, Vector3(0.05, 0.012, 0.06), Vector3(0, -0.006, -0.06), dark)
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0009
	sm.height = 0.0018
	dot.mesh = sm
	var dm := _mat(Color(1, 0.1, 0.05), 0.0, 1.0)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material_override = dm
	dot.position = Vector3(0, 0.0, -0.08)
	_rifle.add_child(dot)
	# Hands and forearms.
	_box(_rifle, Vector3(0.06, 0.06, 0.09), Vector3(0.01, -0.12, 0.08), glove)      # right hand
	_limb(_rifle, Vector3(0.02, -0.13, 0.12), Vector3(0.16, -0.36, 0.42), 0.075, sleeve)  # right forearm
	_box(_rifle, Vector3(0.065, 0.055, 0.1), Vector3(-0.02, -0.08, -0.3), glove)    # left hand
	_limb(_rifle, Vector3(-0.03, -0.1, -0.27), Vector3(-0.3, -0.38, 0.05), 0.07, sleeve)  # left forearm
	_charge_ord = _charge(Color(0.55, 0.5, 0.36), Vector3(0.14, 0.06, 0.22), glove, sleeve)
	_charge_heavy = _charge(Color(0.18, 0.18, 0.2), Vector3(0.2, 0.08, 0.28), glove, sleeve)
	position = HIP


func _charge(col: Color, size: Vector3, glove: Material, sleeve: Material) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(0.0, -0.2, -0.36)
	n.rotation_degrees = Vector3(-55, -10, 0)
	add_child(n)
	_box(n, size, Vector3.ZERO, _mat(col, 0.1, 0.7))
	var stripe := _mat(Color(0.9, 0.75, 0.1), 0.0, 0.6)
	_box(n, Vector3(size.x + 0.004, size.y * 0.6, 0.03), Vector3(0, 0, -size.z * 0.3), stripe)
	var led := _mat(Color(1, 0.2, 0.05), 0.0, 1.0)
	led.emission_enabled = true
	led.emission = Color(1, 0.2, 0.05)
	led.emission_energy_multiplier = 3.0
	_box(n, Vector3(0.02, 0.01, 0.02), Vector3(0.03, size.y * 0.5 + 0.004, 0.05), led)
	_box(n, Vector3(0.07, 0.06, 0.09), Vector3(size.x * 0.5 + 0.02, -0.01, 0.04), glove)
	_limb(n, Vector3(size.x * 0.5 + 0.03, -0.02, 0.07), Vector3(size.x * 0.5 + 0.12, -0.08, 0.4), 0.07, sleeve)
	n.visible = false
	return n


func _process(delta: float) -> void:
	if loadout == null:
		return
	var rifle := loadout.tool == Loadout.Tool.RIFLE
	_ads = move_toward(_ads, 1.0 if loadout.aiming else 0.0, delta * 7.0)
	_lower = move_toward(_lower, 0.0 if rifle else 1.0, delta * 6.0)
	if loadout.shots_fired != _shots:
		if loadout.shots_fired > _shots:
			_recoil = minf(_recoil + 1.0, 1.6)
		_shots = loadout.shots_fired
	_recoil = move_toward(_recoil, 0.0, delta * 12.0)
	var p := loadout.player
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if p.is_on_floor() and speed > 0.3:
		_bob_t += delta * speed * 2.2
	var bob_amt := (1.0 - _ads * 0.85) * clampf(speed / 4.0, 0.0, 1.5)
	var bob := Vector3(sin(_bob_t) * 0.006, -absf(cos(_bob_t)) * 0.006, 0) * bob_amt
	var reload_k := 0.0
	if loadout.reloading and loadout.tuning.reload_time > 0.0:
		reload_k = sin(clampf(1.0 - loadout.reload_left() / loadout.tuning.reload_time, 0.0, 1.0) * PI)
	_mag.position.y = -0.12 - reload_k * 0.25
	_mag.visible = reload_k < 0.85
	var base := HIP.lerp(ADS, _ads)
	position = base + bob + Vector3(0, -0.07 * reload_k - 0.3 * _lower, 0.035 * _recoil)
	rotation = Vector3(deg_to_rad(2.2 * _recoil - 25.0 * _lower), 0, deg_to_rad(-22.0 * reload_k))
	_rifle.visible = _lower < 0.98
	_charge_ord.visible = loadout.tool == Loadout.Tool.ORDINARY_CHARGE
	_charge_heavy.visible = loadout.tool == Loadout.Tool.HEAVY_CHARGE


func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	m.use_fov_override = true
	m.fov_override = VM_FOV
	m.use_z_clip_scale = true
	m.z_clip_scale = 0.2
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, pitch_deg: float = 0.0, yaw_deg: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Box stretched between two points (forearms).
func _limb(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5)


func _cyl(parent: Node3D, r: float, length: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = length
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
