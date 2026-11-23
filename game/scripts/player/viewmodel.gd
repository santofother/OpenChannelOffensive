class_name Viewmodel
extends Node3D
## First-person held item. Uses the Blender-made models (GearModels) with their authored clips
## (fire / reload / rack / use / throw) and gloved arms parented to the model's Hand_R / Hand_L sockets;
## falls back to the code-built placeholder when a model file is missing (tests and headless never need art).
## Code adds the responsive layer: hip/ADS blend, walk bob, look sway, recoil, reload tilt, lower/raise on switch,
## muzzle flash and ejected casings. Purely cosmetic: shots still come from WeaponTuning.muzzle_offset.

const VM_FOV := GearModels.VM_FOV
## Per item: hip = where the model origin sits relative to the camera, ads = distance of the Sight socket from the eye.
## Long guns sit in the lower right with the muzzle converging on the crosshair, so the left side of the
## receiver and the support arm's diagonal read clearly (the common shooter framing, e.g. Insurgency-style hip).
const VIEW_DEFAULT := {"hip": Vector3(0.115, -0.15, -0.31), "ads": 0.24, "arm_r": "ArmR_Grip", "arm_l": "ArmL_Fore", "tilt": 1.0, "rot": Vector3(1.2, 5.5, -5.0)}
const VIEW := {
	"p9": {"hip": Vector3(0.07, -0.122, -0.40), "ads": 0.42, "arm_r": "ArmR_Pistol", "arm_l": "ArmL_Support", "rot": Vector3(-1.0, 2.0, -2.0)},
	"p9_match": {"hip": Vector3(0.07, -0.122, -0.40), "ads": 0.42, "arm_r": "ArmR_Pistol", "arm_l": "ArmL_Support", "rot": Vector3(-1.0, 2.0, -2.0)},
	"revolver": {"hip": Vector3(0.07, -0.122, -0.40), "ads": 0.42, "arm_r": "ArmR_Pistol", "arm_l": "ArmL_Support", "rot": Vector3(-1.0, 2.0, -2.0)},
	"smg": {"hip": Vector3(0.11, -0.15, -0.36), "ads": 0.23},
	"marksman": {"hip": Vector3(0.115, -0.15, -0.37), "ads": 0.085},
	"ordinary": {"hip": Vector3(0.05, -0.20, -0.36), "arm_r": "ArmR_Hold", "arm_l": "ArmL_Hold"},
	"heavy": {"hip": Vector3(0.04, -0.21, -0.52), "arm_r": "ArmR_Hold", "arm_l": "ArmL_Hold"},
	"kit": {"hip": Vector3(0.04, -0.21, -0.38), "arm_r": "ArmR_Hold", "arm_l": "ArmL_Hold"},
	"medkit": {"hip": Vector3(0.05, -0.20, -0.36), "arm_r": "ArmR_Hold", "arm_l": "ArmL_Hold"},
	"frag": {"hip": Vector3(0.13, -0.17, -0.36), "arm_r": "ArmR_Hold", "arm_l": ""},
	"flash": {"hip": Vector3(0.13, -0.17, -0.36), "arm_r": "ArmR_Hold", "arm_l": ""},
	"smoke": {"hip": Vector3(0.13, -0.17, -0.36), "arm_r": "ArmR_Hold", "arm_l": ""},
	"incendiary": {"hip": Vector3(0.13, -0.17, -0.36), "arm_r": "ArmR_Hold", "arm_l": ""},
	## Empty hands: the medkit's carry pose with only the arms visible (nothing of that item owned).
	"hands": {"hip": Vector3(0.05, -0.23, -0.36), "arm_r": "ArmR_Hold", "arm_l": "ArmL_Hold", "base": "medkit"},
	## The carried bomb (attackers' slot 5) borrows the heavy charge's block model.
	"bomb": {"hip": Vector3(0.04, -0.21, -0.48), "arm_r": "ArmR_Hold", "arm_l": "ArmL_Hold", "base": "heavy"},
}
const EMPTY_HANDS := "hands"
const MAX_CASINGS := 6
const THROW_DURATION := .39

var loadout: Loadout
var _items := {} ## key -> {root, anim, hip, ads, rest, muzzle, eject, model}
var _shown := ""
var _ads := 0.0
var _recoil := 0.0
var _recoil_side := 0.0
var _lower := 1.0
var _bob_t := 0.0
var _shots := 0
var _was_reloading := false
var _was_using := false
var _throw_left := 0.0
var _sway := Vector2.ZERO
var _last_yaw := 0.0
var _last_pitch := 0.0
var _mats := {}
var _flash: MeshInstance3D
var _flash_left := 0.0
var _casings: Array[MeshInstance3D] = []
var _casing_vel: Array[Vector3] = []
var _casing_spin: Array[Vector3] = []
var _casing_life: Array[float] = []
var _casing_next := 0
var _rng := RandomNumberGenerator.new()


func setup(l: Loadout) -> void:
	loadout = l
	name = "Viewmodel"
	_build_fx()
	# Dim fill light that only touches the viewmodel (render layer 2), so a dark gun never goes pure black.
	var fill := OmniLight3D.new()
	fill.name = "ViewmodelFill"
	fill.light_cull_mask = 2
	fill.light_energy = 0.35
	fill.light_color = Color(0.78, 0.84, 1.0)
	fill.omni_range = 2.5
	fill.shadow_enabled = false
	fill.position = Vector3(-0.35, 0.45, 0.25)
	loadout.player.camera.add_child.call_deferred(fill)


## Which item the loadout is holding ("" = nothing to show). A selected tool the player has none of
## (no charges, kits, medkits or that grenade) shows empty hands instead of the item.
func item_key() -> String:
	if loadout.is_gun():
		return loadout.weapon_id()
	if loadout.tool == Loadout.Tool.HOLSTER:
		return EMPTY_HANDS
	if loadout.tool == Loadout.Tool.BOMB:
		return "bomb"
	var key := Loadout.tool_key(loadout.tool)
	if key != "" and int(loadout.charges.get(loadout.tool, 0)) <= 0 and loadout.install_left <= 0.0 and _throw_left <= 0.0:
		if _shown == key and int(current().get("last_count", 0)) > 0:
			return key # the last grenade just left the hand: let this frame start its throw motion
		return EMPTY_HANDS
	return key


func current() -> Dictionary:
	return _items.get(_shown, {})


func _item(key: String) -> Dictionary:
	if _items.has(key):
		return _items[key]
	var view: Dictionary = VIEW_DEFAULT.duplicate()
	view.merge(VIEW.get(key, {}), true)
	var path := model_path(String(view.get("base", key)))
	var root := GearModels.instance(path, true)
	var it := {"model": root != null, "hip": view.hip, "ads_pos": Vector3(0.0, -0.093, -0.24), "anim": null, "rest": {}, "muzzle": null, "eject": null, "tilt": view.tilt, "rot": view.rot if root != null else Vector3.ZERO}
	var arms: Array[Node3D] = []
	if root == null:
		root = _placeholder(key)
		it.hip = Vector3(0.15, -0.16, -0.32)
		if root.has_meta("mag"):
			it["mag"] = root.get_meta("mag")
	else:
		for pair in [["Hand_R", view.arm_r], ["Hand_L", view.arm_l]]:
			var s := GearModels.socket(root, pair[0])
			if s and pair[1] != "":
				var arm := GearModels.piece("weapons/hands", pair[1], true)
				if arm:
					s.add_child(arm)
					arms.append(arm)
		for pair in [["flashlight", "Rail_Side", 1], ["laser", "Rail_Side_R", 2]]:
			var mount := GearModels.socket(root, pair[1])
			if mount:
				var attachment := GearModels.instance("attachments/" + pair[0], true)
				if attachment:
					attachment.name = "Attachment_" + pair[0]
					attachment.set_meta("gadget_bit", pair[2])
					mount.add_child(attachment)
		var muzzle := GearModels.socket(root, "Muzzle")
		if muzzle:
			# Procedural suppressor tube (no modelled asset yet), shown when the silencer is owned.
			var can := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.017
			cyl.bottom_radius = 0.017
			cyl.height = 0.15
			cyl.radial_segments = 14
			can.mesh = cyl
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.07, 0.07, 0.075)
			mat.roughness = 0.55
			mat.metallic = 0.6
			can.material_override = mat
			can.name = "Attachment_silencer"
			can.set_meta("gadget_bit", 8)
			can.rotation.x = PI * 0.5
			can.position = _local_to(root, muzzle) + Vector3(0, 0, -0.075)
			root.add_child(can)
		var sight := GearModels.socket(root, "Sight")
		if sight:
			var sp: Vector3 = root.transform * _local_to(root, sight)
			it.ads_pos = Vector3(-sp.x, -sp.y, -float(view.ads) - sp.z)
		it.anim = GearModels.anim(root)
		it.muzzle = GearModels.socket(root, "Muzzle")
		it.eject = GearModels.socket(root, "Eject")
		var stock := GearModels.socket(root, "Stock") # shoulder stocks sit behind the camera: hidden in first person
		if stock:
			stock.visible = false
		for n: Node3D in root.find_children("*", "Node3D", true, false):
			it.rest[n] = n.transform
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 3
		if view.has("base") and not arms.any(func(a: Node3D) -> bool: return a.is_ancestor_of(mi)):
			mi.visible = false # empty hands: keep the gloves/sleeves, hide the borrowed item
	root.visible = false
	add_child(root)
	it["root"] = root
	_items[key] = it
	return it


static func model_path(key: String) -> String:
	if Weapons.DEFS.has(key):
		return "weapons/" + key
	if key in ["frag", "flash", "smoke", "incendiary"]:
		return "grenades/" + key
	return "gear/" + key


func _local_to(root: Node3D, n: Node3D) -> Vector3:
	var xf := n.transform
	var p := n.get_parent() as Node3D
	while p and p != root:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf.origin


func _reset_pose(it: Dictionary) -> void:
	var ap: AnimationPlayer = it.anim
	if ap:
		ap.stop()
	for n: Node3D in it.rest:
		if is_instance_valid(n):
			n.transform = it.rest[n]


func _play(it: Dictionary, clip: String, duration: float = 0.0) -> bool:
	var ap: AnimationPlayer = it.get("anim")
	if ap == null or not ap.has_animation(clip):
		return false
	var speed := 1.0
	if duration > 0.0:
		speed = ap.get_animation(clip).length / duration
	ap.stop()
	ap.play(clip, 0.0, speed)
	return true


func _process(delta: float) -> void:
	if loadout == null:
		return
	var want := item_key()
	var gun := loadout.is_gun()
	# lower -> swap -> raise
	if want != _shown:
		_lower = move_toward(_lower, 1.0, delta * 7.0)
		if _lower >= 0.999:
			if _items.has(_shown):
				_reset_pose(_items[_shown])
				(_items[_shown].root as Node3D).visible = false
			_shown = want
			_was_reloading = false
			_was_using = false
			if want != "":
				var nit := _item(want)
				(nit.root as Node3D).visible = true
				_play(nit, "rack")
	else:
		_lower = move_toward(_lower, 0.0, delta * 5.0)
	var it := current()
	if it.is_empty():
		return
	var root: Node3D = it.root
	_throw_left = maxf(0.0, _throw_left - delta)
	var grenade := loadout.tool >= Loadout.Tool.FRAG and loadout.tool <= Loadout.Tool.INCENDIARY and _shown != EMPTY_HANDS
	if grenade:
		var count := int(loadout.charges.get(loadout.tool, 0))
		if count < int(it.get("last_count", count)):
			_throw_left = THROW_DURATION
			_play(it, "pin", .13)
		it["last_count"] = count
	for attachment: Node3D in root.find_children("Attachment_*", "Node3D", true, false):
		attachment.visible = loadout.gadgets_owned & int(attachment.get_meta("gadget_bit")) != 0
	if not it.model and gun:
		root.scale.z = float(Weapons.DEFS[loadout.weapon_id()].look)
	_ads = move_toward(_ads, 1.0 if loadout.aiming else 0.0, delta * 7.0)
	# shots: recoil impulse + bolt/slide clip + flash + casing
	if loadout.shots_fired != _shots:
		if loadout.shots_fired > _shots and gun:
			_recoil = minf(_recoil + 1.0, 1.7)
			_recoil_side = _rng.randf_range(-1.0, 1.0)
			_play(it, "fire")
			_show_flash(it)
			_eject_casing(it)
		_shots = loadout.shots_fired
	_recoil = move_toward(_recoil, 0.0, delta * (9.0 + 6.0 * _recoil))
	# reload clip stretched to the gun's reload time
	if loadout.reloading and not _was_reloading:
		_play(it, "reload", loadout.tuning.reload_time)
	elif _was_reloading and not loadout.reloading:
		_reset_pose(it)
	_was_reloading = loadout.reloading
	var using := loadout.install_left > 0.0
	if using and not _was_using:
		_play(it, "use", loadout.use_time())
	elif _was_using and not using:
		_reset_pose(it)
	_was_using = using
	# walk bob and look sway
	var p := loadout.player
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if p.is_on_floor() and speed > 0.3:
		_bob_t += delta * speed * 2.2
	var bob_amt := (1.0 - _ads * 0.88) * clampf(speed / 4.0, 0.0, 1.5)
	var bob := Vector3(sin(_bob_t) * 0.0055, -absf(cos(_bob_t)) * 0.0065, 0) * bob_amt
	var yaw := p.rotation.y
	var pitch := p.camera.global_rotation.x
	var dy := wrapf(yaw - _last_yaw, -PI, PI)
	var dp := pitch - _last_pitch
	_last_yaw = yaw
	_last_pitch = pitch
	var target := Vector2(clampf(dy * 3.0, -0.06, 0.06), clampf(dp * 3.0, -0.05, 0.05)) * (1.0 - _ads * 0.7)
	_sway = _sway.lerp(target, clampf(delta * 9.0, 0.0, 1.0))
	var reload_k := 0.0
	if loadout.reloading and loadout.tuning.reload_time > 0.0:
		reload_k = sin(clampf(1.0 - loadout.reload_left() / loadout.tuning.reload_time, 0.0, 1.0) * PI)
	if not it.model and it.has("mag"):
		(it.mag as Node3D).position.y = -0.12 - reload_k * 0.25
		(it.mag as Node3D).visible = reload_k < 0.85
	var tilt: float = float(it.tilt) * (0.55 if it.model else 1.0)
	var hip: Vector3 = it.hip
	var base := hip.lerp(it.ads_pos, _ads) if gun else hip
	var low := _lower * _lower * (3.0 - 2.0 * _lower)
	position = base + bob + Vector3(_sway.x * 0.35 + _recoil_side * _recoil * 0.002, -0.05 * reload_k * tilt - 0.32 * low + _sway.y * 0.25,
		(0.028 if it.model else 0.035) * _recoil * (1.0 - 0.45 * _ads))
	var hr: Vector3 = it.rot * ((1.0 - _ads) if gun else 1.0)
	rotation = Vector3(deg_to_rad(hr.x + (1.6 if it.model else 2.2) * _recoil * (1.0 - 0.5 * _ads) - 38.0 * low + 6.0 * reload_k * tilt) + _sway.y * 0.6,
		_sway.x * 0.8 + deg_to_rad(hr.y + _recoil_side * _recoil * 0.4 + 14.0 * low),
		deg_to_rad(hr.z - 20.0 * reload_k * tilt) - _sway.x * 1.2)
	# scoped guns hand over to the 2D scope overlay at full ADS
	root.visible = not (gun and _ads > 0.92 and scoped())
	if grenade:
		var progress := 1.0 - _throw_left / THROW_DURATION
		var swing := smoothstep(0.0, .18, progress) * (1.0 - smoothstep(.22, .85, progress))
		position += Vector3(-.025, .145, -.18) * swing
		rotation += Vector3(-.96, .18, -.29) * swing
		root.visible = int(loadout.charges.get(loadout.tool, 0)) > 0 or _throw_left > 0.0
	_pose_arms(root)
	_tick_fx(delta)


## True while the scope overlay should be drawn (marksman rifle at full ADS).
func scoped() -> bool:
	return loadout.is_gun() and bool(Weapons.DEFS[loadout.weapon_id()].get("scope", false))


func scope_amount() -> float:
	return clampf((_ads - 0.92) / 0.08, 0.0, 1.0) if scoped() and _shown == loadout.weapon_id() else 0.0


# ---------------------------------------------------------------- flash and casings

func _build_fx() -> void:
	_flash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	_flash.mesh = q
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.albedo_texture = _flash_texture()
	fm.albedo_color = Color(1.0, 0.82, 0.5)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	fm.use_fov_override = true
	fm.fov_override = VM_FOV
	fm.use_z_clip_scale = true
	fm.z_clip_scale = 0.2
	_flash.material_override = fm
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0028
	cm.bottom_radius = 0.003
	cm.height = 0.016
	cm.radial_segments = 8
	cm.rings = 1
	for i in MAX_CASINGS:
		var c := MeshInstance3D.new()
		c.mesh = cm
		c.material_override = GearModels.material("brass", true)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.visible = false
		add_child(c)
		_casings.append(c)
		_casing_vel.append(Vector3.ZERO)
		_casing_spin.append(Vector3.ZERO)
		_casing_life.append(0.0)


func _flash_texture() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := v.length()
			var a := atan2(v.y, v.x)
			var star := 0.45 + 0.55 * pow(absf(cos(a * 2.5)), 6.0)
			var k := clampf(1.0 - r / star, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, k * k))
	return ImageTexture.create_from_image(img)


func _show_flash(it: Dictionary) -> void:
	var mz: Node3D = it.get("muzzle")
	if mz == null or not is_instance_valid(mz):
		return
	_flash.position = to_local(mz.global_position) + Vector3(0, 0, -0.03)
	_flash.rotation = Vector3(0, 0, _rng.randf() * TAU)
	var s := _rng.randf_range(0.5, 0.85) * (1.0 - 0.4 * _ads)
	_flash.scale = Vector3(s, s, s)
	_flash.visible = true
	_flash_left = 0.035


func _eject_casing(it: Dictionary) -> void:
	var ej: Node3D = it.get("eject")
	if ej == null or not is_instance_valid(ej):
		return
	var i := _casing_next
	_casing_next = (_casing_next + 1) % MAX_CASINGS
	var c := _casings[i]
	c.position = to_local(ej.global_position)
	c.rotation = Vector3(PI * 0.5, 0, 0)
	c.visible = true
	_casing_vel[i] = Vector3(_rng.randf_range(0.9, 1.4), _rng.randf_range(0.5, 0.9), _rng.randf_range(0.1, 0.5))
	_casing_spin[i] = Vector3(_rng.randf_range(-20, 20), _rng.randf_range(-12, 12), _rng.randf_range(-30, 30))
	_casing_life[i] = 0.55


func _tick_fx(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
	for i in MAX_CASINGS:
		if _casing_life[i] <= 0.0:
			continue
		_casing_life[i] -= delta
		_casing_vel[i].y -= 6.0 * delta
		_casings[i].position += _casing_vel[i] * delta
		_casings[i].rotation += _casing_spin[i] * delta
		if _casing_life[i] <= 0.0:
			_casings[i].visible = false


# ---------------------------------------------------------------- placeholders (used when a model file is missing)

func _placeholder(key: String) -> Node3D:
	var n := Node3D.new()
	var glove := _mat(Color(0.16, 0.15, 0.13), 0.0, 0.95)
	var sleeve := _mat(Color(0.22, 0.23, 0.18), 0.0, 0.95)
	if Weapons.DEFS.has(key):
		var dark := _mat(Color(0.13, 0.13, 0.135), 0.4, 0.45)
		var polymer := _mat(Color(0.17, 0.16, 0.14), 0.0, 0.7)
		_box(n, Vector3(0.05, 0.065, 0.3), Vector3(0, -0.05, 0.0), dark)
		_box(n, Vector3(0.056, 0.06, 0.26), Vector3(0, -0.047, -0.27), polymer)
		_box(n, Vector3(0.022, 0.012, 0.52), Vector3(0, -0.012, -0.12), dark)
		_cyl(n, 0.011, 0.12, Vector3(0, -0.045, -0.46), dark)
		_cyl(n, 0.022, 0.15, Vector3(0, -0.045, -0.58), polymer)
		_box(n, Vector3(0.03, 0.085, 0.045), Vector3(0, -0.11, 0.08), polymer, -20.0)
		_box(n, Vector3(0.042, 0.075, 0.18), Vector3(0, -0.055, 0.24), polymer)
		var mag := Node3D.new()
		mag.position = Vector3(0, -0.12, -0.07)
		n.add_child(mag)
		_box(mag, Vector3(0.032, 0.13, 0.065), Vector3(0, -0.02, 0), dark, 10.0)
		n.set_meta("mag", mag)
		for s in [-1, 1]:
			_box(n, Vector3(0.006, 0.04, 0.05), Vector3(0.022 * s, 0.008, -0.06), dark)
		_box(n, Vector3(0.05, 0.006, 0.05), Vector3(0, 0.03, -0.06), dark)
		_box(n, Vector3(0.05, 0.012, 0.06), Vector3(0, -0.006, -0.06), dark)
		_box(n, Vector3(0.06, 0.06, 0.09), Vector3(0.01, -0.12, 0.08), glove)
		_limb(n, Vector3(0.02, -0.13, 0.12), Vector3(0.16, -0.36, 0.42), 0.075, sleeve)
		_box(n, Vector3(0.065, 0.055, 0.1), Vector3(-0.02, -0.08, -0.3), glove)
		_limb(n, Vector3(-0.03, -0.1, -0.27), Vector3(-0.3, -0.38, 0.05), 0.07, sleeve)
		return n
	if key == EMPTY_HANDS:
		var hands := Node3D.new()
		hands.position = Vector3(0.0, -0.2, -0.36)
		for side in [-1.0, 1.0]:
			_box(hands, Vector3(0.07, 0.06, 0.09), Vector3(0.09 * side, -0.01, 0.0), glove)
			_limb(hands, Vector3(0.1 * side, -0.02, 0.04), Vector3(0.22 * side, -0.1, 0.4), 0.07, sleeve)
		var holder0 := Node3D.new()
		holder0.add_child(hands)
		return holder0
	var col := Color(0.55, 0.5, 0.36)
	var size := Vector3(0.14, 0.06, 0.22)
	match key:
		"heavy":
			col = Color(0.18, 0.18, 0.2)
			size = Vector3(0.2, 0.08, 0.28)
		"kit":
			col = Color(0.55, 0.58, 0.62)
			size = Vector3(0.24, 0.035, 0.32)
		"medkit":
			col = Color(0.9, 0.9, 0.9)
			size = Vector3(0.16, 0.07, 0.22)
		"frag", "flash", "smoke", "incendiary":
			col = {"frag": Color(0.2, 0.25, 0.15), "flash": Color(0.6, 0.6, 0.62), "smoke": Color(0.4, 0.42, 0.45), "incendiary": Color(0.6, 0.2, 0.1)}[key]
			size = Vector3(0.06, 0.06, 0.11)
	n.position = Vector3(0.0, -0.2, -0.36)
	n.rotation_degrees = Vector3(-55, -10, 0)
	_box(n, size, Vector3.ZERO, _mat(col, 0.1, 0.7))
	_box(n, Vector3(size.x + 0.004, size.y * 0.6, 0.03), Vector3(0, 0, -size.z * 0.3), _mat(Color(0.9, 0.75, 0.1), 0.0, 0.6))
	_box(n, Vector3(0.07, 0.06, 0.09), Vector3(size.x * 0.5 + 0.02, -0.01, 0.04), glove)
	_limb(n, Vector3(size.x * 0.5 + 0.03, -0.02, 0.07), Vector3(size.x * 0.5 + 0.12, -0.08, 0.4), 0.07, sleeve)
	var holder := Node3D.new()
	holder.add_child(n)
	return holder


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


## Hand bones stay on the authored grip socket; the sleeve points back toward a camera-space elbow.
## A replacement skinned mesh can reuse these bone names without changing weapon clips.
func _pose_arms(root: Node3D) -> void:
	for skeleton: Skeleton3D in root.find_children("*", "Skeleton3D", true, false):
		var bone := skeleton.find_bone("Forearm")
		var end := skeleton.find_bone("ElbowEnd")
		if bone < 0 or end < 0:
			continue
		var rest := skeleton.get_bone_rest(bone)
		var length := skeleton.get_bone_rest(end).origin.length()
		var side := -1.0 if "ArmL" in str(skeleton.get_path()) else 1.0
		var elbow := loadout.player.camera.global_transform * Vector3(side * .25, -.42, -.10)
		var direction := skeleton.to_local(elbow) - rest.origin
		if direction.length() < .01 or length < .01:
			continue
		# Bone pose replaces the rest orientation in parent space.
		# Preserve the sleeve's authored roll while swinging its long axis toward the elbow.
		var rest_rotation := rest.basis.get_rotation_quaternion()
		var swing := Quaternion(rest.basis.y.normalized(), direction.normalized())
		# Reload sockets can travel far below the gun. Limit wrist deviation and arm stretch
		# rather than forcing an anatomical joint to reach a fixed, invisible elbow.
		var angle := rest.basis.y.angle_to(direction)
		if angle > deg_to_rad(55.0):
			swing = Quaternion.IDENTITY.slerp(swing, deg_to_rad(55.0) / angle)
		skeleton.set_bone_pose_rotation(bone, swing * rest_rotation)
		skeleton.set_bone_pose_scale(bone, Vector3(1, clampf(direction.length() / length, .85, 1.2), 1))


## Draw cached held models under the loading cover, preserving the active item's visibility.
func begin_graphics_warmup() -> Array:
	set_process(false)
	var saved := []
	for key in ["ordinary", "heavy", "service_rifle"]:
		var root: Node3D = _item(key).root
		saved.append([root, root.visible])
		root.visible = true
	return saved


func end_graphics_warmup(saved: Array) -> void:
	for entry: Array in saved:
		(entry[0] as Node3D).visible = entry[1]
	set_process(true)
