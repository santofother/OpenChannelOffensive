class_name GearModels
extends RefCounted
## Loads Blender-made gear (res://assets/models/<family>/<name>.glb) and gives it the shared gear materials.
## The .glb files carry only material *names*; assets/models/materials.json (also read by the Blender build
## scripts in tools/art) defines them, so one table drives both programs and textures are shared.
## Everything returns null when a model is missing: callers keep their code-built placeholder.

const DIR := "res://assets/models/"
const TEX := "res://assets/textures/gear/"
const VM_FOV := 70.0

static var _defs := {}
static var _mats := {}
static var _scenes := {}
static var _tex := {}


static func has(path: String) -> bool:
	return not OS.get_cmdline_user_args().has("--no-models") and ResourceLoader.exists(DIR + path + ".glb")


## Instance of a model. `viewmodel` materials use the fixed first-person FOV and a z-clip scale.
static func instance(path: String, viewmodel: bool = false, team: Color = Color.WHITE) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(DIR + path + ".glb") if has(path) else null
	var ps: PackedScene = _scenes[path]
	if ps == null:
		return null
	var root := ps.instantiate() as Node3D
	apply_materials(root, viewmodel, team)
	return root


## One named child of a multi-part library file (e.g. an arm from weapons/hands), detached and ready to parent.
static func piece(path: String, node_name: String, viewmodel: bool = false, team: Color = Color.WHITE) -> Node3D:
	var root := instance(path, viewmodel, team)
	if root == null:
		return null
	var n := root.find_child(node_name, true, false) as Node3D
	if n:
		n.get_parent().remove_child(n)
		n.owner = null
		n.transform = Transform3D.IDENTITY
	root.free()
	return n


static func apply_materials(root: Node, viewmodel: bool, team: Color = Color.WHITE) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if viewmodel:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src:
				mi.set_surface_override_material(i, material(src.resource_name, viewmodel, team))


static func socket(root: Node, n: String) -> Node3D:
	return root.find_child(n, true, false) as Node3D if root else null


static func anim(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var l := root.find_children("*", "AnimationPlayer", true, false)
	return l[0] as AnimationPlayer if not l.is_empty() else null


static func triangles(root: Node) -> int:
	var n := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			n += mi.mesh.surface_get_array_index_len(i) / 3
	return n


static func material(mat_name: String, viewmodel: bool = false, team: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%d|%s" % [mat_name, int(viewmodel), team.to_html() if mat_name in ["team", "uniform"] else ""]
	if _mats.has(key):
		return _mats[key]
	if _defs.is_empty():
		var f := FileAccess.open(DIR + "materials.json", FileAccess.READ)
		if f:
			_defs = JSON.parse_string(f.get_as_text())
	var d: Dictionary = _defs.get(mat_name, {"color": [0.5, 0.5, 0.5]})
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	var c: Array = d["color"]
	var col := Color(c[0], c[1], c[2]).linear_to_srgb()
	if mat_name == "team":
		col = team
	elif mat_name == "uniform" and team == StandIn.TEAM_BLUE:
		col = Color("#293449")
	col.a = float(d.get("alpha", 1.0))
	m.albedo_color = col
	m.metallic = float(d.get("metallic", 0.0))
	m.roughness = float(d.get("roughness", 0.6))
	# The aiming mark represents emitted light; baked mesh occlusion must not dim it.
	m.vertex_color_use_as_albedo = mat_name != "reticle"
	var s := float(d.get("uv_scale", 4.0))
	m.uv1_scale = Vector3(s, s, s)
	if d.has("albedo_tex"):
		m.albedo_texture = _texture(String(d["albedo_tex"]))
	elif float(d.get("grunge", 0.0 if d.has("emission") else 1.0)) > 0.5:
		m.albedo_texture = _texture("grunge")
		m.roughness_texture = _texture("grunge")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = minf(m.roughness * 1.15, 1.0)
	if d.has("normal"):
		m.normal_enabled = true
		m.normal_texture = _texture(String(d["normal"]) + "_n")
		m.normal_scale = float(d.get("normal_scale", 0.5))
	if d.has("emission"):
		var e: Array = d["emission"]
		m.emission_enabled = true
		m.emission = Color(e[0], e[1], e[2])
		m.emission_energy_multiplier = float(d.get("emission_energy", 2.0))
	if d.get("unshaded", false):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if viewmodel:
		m.use_fov_override = true
		m.fov_override = VM_FOV
		m.use_z_clip_scale = true
		m.z_clip_scale = 0.2
	_mats[key] = m
	return m


static func _texture(n: String) -> Texture2D:
	if not _tex.has(n):
		var p := TEX + n + ".png"
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	return _tex[n]
