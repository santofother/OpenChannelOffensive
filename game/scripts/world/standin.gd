class_name StandIn
extends RefCounted
## Operator silhouette stand-in (~1.78 m), built from primitives. Faces -Z, feet at y = 0.
## Readability first: mid-tone tan gear on dark fatigues plus a team-colour band on the upper arms.

const TEAM_RED := Color(0.85, 0.18, 0.12)
const TEAM_BLUE := Color(0.2, 0.45, 0.95)


## `body` lets callers pass their own fatigue material (e.g. to flash it on hit).
static func build(team: Color, body: StandardMaterial3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "StandIn"
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
	_part(root, _box(Vector3(0.38, 0.56, 0.22)), Vector3(0, 1.17, 0), fat)
	_part(root, _box(Vector3(0.4, 0.4, 0.3)), Vector3(0, 1.2, 0), gear)
	_part(root, _box(Vector3(0.3, 0.1, 0.06)), Vector3(0, 1.06, -0.17), gear)
	_part(root, _box(Vector3(0.34, 0.08, 0.26)), Vector3(0, 0.92, 0), gear)
	# arms (raised, holding a rifle forward) and team band
	for s in [-1, 1]:
		_part(root, _capsule(0.06, 0.34), Vector3(0.24 * s, 1.28, -0.08), fat, Vector3(deg_to_rad(-60), 0, 0))
		_part(root, _box(Vector3(0.13, 0.05, 0.13)), Vector3(0.24 * s, 1.36, -0.02), band)
	_part(root, _box(Vector3(0.05, 0.08, 0.7)), Vector3(0.08, 1.33, -0.38), Surfaces.get_mat("plastic"))
	# head + helmet + ear cups
	_part(root, _sphere(0.11), Vector3(0, 1.58, 0), fat)
	_part(root, _sphere(0.135, 0.7), Vector3(0, 1.64, 0.01), gear)
	for s in [-1, 1]:
		_part(root, _sphere(0.05), Vector3(0.12 * s, 1.57, 0), Surfaces.get_mat("plastic"))
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
