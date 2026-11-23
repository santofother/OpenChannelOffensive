class_name StandIn
extends RefCounted
## Shared third-person operator and optional equipment. Feet at zero, facing -Z.

const TEAM_RED := Color("#cf572e")
const TEAM_BLUE := Color("#2679d5")


## `body` lets callers pass their own fatigue material (e.g. to flash it on hit).
static func build(team: Color, body: StandardMaterial3D = null) -> Node3D:
	var model := GearModels.instance("wearables/operator", false, team)
	if model:
		model.name = "StandIn"
		model.set_meta("team", team)
		var pose := OperatorPose.new()
		pose.name = "Pose"
		model.add_child(pose)
		pose.setup(model)
		equip(model, "service_rifle", 0, false)
		pose.update(0, Vector3.ZERO, 1.8, 0, 0, false, false, 0, true)
		return model
	var root := Node3D.new()
	root.name = "StandIn"
	root.set_meta("team", team)
	var carrier := Node3D.new()
	carrier.name = "FallbackVest"
	root.add_child(carrier)
	var shell := Node3D.new()
	shell.name = "FallbackHelmet"
	root.add_child(shell)
	var firearm := Node3D.new()
	firearm.name = "FallbackWeapon"
	root.add_child(firearm)
	var fat := body if body else Surfaces.get_mat("fabric_dark")
	var gear := Surfaces.get_mat("fabric_tan")
	var band := StandardMaterial3D.new()
	band.albedo_color = team
	band.emission_enabled = true
	band.emission = team
	band.emission_energy_multiplier = 0.35
	# legs
	for s in [-1, 1]:
		_part(root, _capsule(0.08, 0.86), Vector3(0.1 * s, 0.43, 0.0), fat)
		_part(root, _box(Vector3(0.11, 0.08, 0.26)), Vector3(0.1 * s, 0.04, -0.04), Surfaces.get_mat("plastic"))
	# torso, plate carrier, pouches
	_part(root, _box(Vector3(0.38, 0.56, 0.22)), Vector3(0, 1.17, 0), band)
	_part(carrier, _box(Vector3(0.4, 0.4, 0.3)), Vector3(0, 1.2, 0), gear)
	_part(carrier, _box(Vector3(0.3, 0.1, 0.06)), Vector3(0, 1.06, -0.17), gear)
	_part(root, _box(Vector3(0.34, 0.08, 0.26)), Vector3(0, 0.92, 0), gear)
	# arms (raised, holding a rifle forward) and team band
	for s in [-1, 1]:
		_part(root, _capsule(0.06, 0.34), Vector3(0.24 * s, 1.28, -0.08), fat, Vector3(deg_to_rad(-60), 0, 0))
		_part(root, _box(Vector3(0.13, 0.05, 0.13)), Vector3(0.24 * s, 1.36, -0.02), band)
	_part(firearm, _box(Vector3(0.05, 0.08, 0.7)), Vector3(0.08, 1.33, -0.38), Surfaces.get_mat("plastic"))
	# head + helmet + ear cups
	_part(root, _sphere(0.11), Vector3(0, 1.58, 0), fat)
	_part(shell, _sphere(0.135, 0.7), Vector3(0, 1.64, 0.01), gear)
	for s in [-1, 1]:
		_part(shell, _sphere(0.05), Vector3(0.12 * s, 1.57, 0), Surfaces.get_mat("plastic"))
	equip(root, "service_rifle", 0, false)
	return root


static func _part(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


static func _sphere(r: float, hemi: float = 1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	if hemi < 1.0:
		s.is_hemisphere = true
		s.height = r
	return s


static func equip(root: Node3D, weapon: String, armor: int, helmet: bool, gadgets: int = 0, active: int = 0) -> void:
	var key := "%s|%s|%s|%d|%d" % [weapon, armor > 0, helmet, gadgets, active]
	if root.get_meta("equipment", "") == key:
		return
	root.set_meta("equipment", key)
	var pose := root.get_node_or_null("Pose") as OperatorPose
	if not pose:
		root.get_node("FallbackVest").visible = armor > 0
		root.get_node("FallbackHelmet").visible = helmet
		root.get_node("FallbackWeapon").visible = weapon != ""
		return
	if pose:
		pose.set_weapon(weapon)
	for label in ["EquippedVest", "EquippedHelmet", "EquippedGun", "EquippedNVG"]:
		var old := root.get_node_or_null(NodePath(label))
		if old:
			old.free()
	for pair in [["vest", armor > 0, "EquippedVest"], ["helmet", helmet, "EquippedHelmet"]]:
		if pair[1]:
			var item := GearModels.instance("wearables/" + pair[0], false, root.get_meta("team", Color.WHITE))
			if item:
				item.name = pair[2]
				root.add_child(item)
	var gun := GearModels.instance("weapons/" + weapon + "_w") if weapon != "" else null
	if gun:
		gun.name = "EquippedGun"
		gun.position = Vector3(.09, 1.42, -.31)
		root.add_child(gun)
		for pair in [["flashlight", 1, -.06], ["laser", 2, .06]]:
			if gadgets & int(pair[1]):
				var addon := GearModels.instance("attachments/" + pair[0])
				if addon:
					addon.position = Vector3(pair[2], .04, -.25)
					gun.add_child(addon)
	if gadgets & 4:
		var goggles := GearModels.instance("attachments/nvg")
		if goggles:
			goggles.name = "EquippedNVG"
			goggles.position = Vector3(0, 1.69, -.13)
			root.add_child(goggles)
			var animation := GearModels.anim(goggles)
			if animation and animation.has_animation("up") and not active & 4:
				animation.play("up")
				animation.seek(animation.get_animation("up").length, true)
				animation.pause()

static func animate(root: Node3D, dt: float, vel: Vector3, height: float, pitch: float, lean: float, aim: bool, reload: bool, kick: float, alive: bool) -> void:
	var pose := root.get_node_or_null("Pose") as OperatorPose
	if pose:
		pose.update(dt, vel, height, pitch, lean, aim, reload, kick, alive)
	else:
		root.scale.y = height / 1.8
		root.rotation.z = -lean * .16
