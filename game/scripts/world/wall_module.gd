class_name WallModule
extends StaticBody3D
## One destructible wall panel. State, visual mesh and collision are always rebuilt together from the same
## authored part list, so they cannot disagree. Transitions: INTACT -> BREACHED only (reset() restores).
## Ordinary panels need the ordinary charge; reinforced panels need the heavy charge.

enum Mat { ORDINARY, REINFORCED }
enum State { INTACT, BREACHED }
enum Kind { ORDINARY, HEAVY } ## charge kinds

signal state_changed(module: WallModule)

const OPENING_W := 1.2
const OPENING_H := 2.1
## Rifle damage multiplier through an intact ordinary panel (bounded by Ballistics thickness/surface limits).
const ORDINARY_PEN_MULT := 0.5

var wall_id := ""
var material := Mat.ORDINARY
var breakable := true
var state := State.INTACT
var revision := 0 ## increments on each state change; reset() returns to 0
var charge: Node = null ## pending charge, if any
var _size := Vector3.ONE
var _surface: Material
var _decor: Node3D
static var _scorch_tex: ImageTexture
var _long_x := false


static func can_breach(mat: int, kind: int) -> bool:
	return (mat == Mat.ORDINARY and kind == Kind.ORDINARY) or (mat == Mat.REINFORCED and kind == Kind.HEAVY)


## `lo`/`hi` are world-space min/max corners (any order). Call before add_child.
func setup(id: String, lo: Vector3, hi: Vector3, mat: int, surface: Material, can_break: bool = true) -> void:
	name = id
	wall_id = id
	material = mat
	breakable = can_break
	_surface = surface
	_size = (hi - lo).abs()
	_long_x = _size.x > _size.z
	position = (lo + hi) * 0.5
	collision_layer = 1
	collision_mask = 0
	set_meta("pen_mult", ORDINARY_PEN_MULT if mat == Mat.ORDINARY else 0.0)
	_rebuild()


func part_boxes(s: int) -> Array[AABB]:
	var out: Array[AABB] = []
	var half := _size * 0.5
	if s == State.INTACT or not breakable:
		out.append(AABB(-half, _size))
		return out
	var length := _size.x if _long_x else _size.z
	var h := _size.y
	var w := minf(OPENING_W, length - 0.4)
	var hh := minf(OPENING_H, h - 0.3)
	_add_part(out, -length * 0.5, -w * 0.5, 0.0, h)
	_add_part(out, w * 0.5, length * 0.5, 0.0, h)
	_add_part(out, -w * 0.5, w * 0.5, hh, h)
	return out


func _add_part(out: Array[AABB], u0: float, u1: float, y0: float, y1: float) -> void:
	if u1 - u0 < 0.001 or y1 - y0 < 0.001:
		return
	var thick := _size.z if _long_x else _size.x
	var sz := Vector3(u1 - u0, y1 - y0, thick) if _long_x else Vector3(thick, y1 - y0, u1 - u0)
	var centre := Vector3((u0 + u1) * 0.5, (y0 + y1) * 0.5 - _size.y * 0.5, 0.0) if _long_x \
		else Vector3(0.0, (y0 + y1) * 0.5 - _size.y * 0.5, (u0 + u1) * 0.5)
	out.append(AABB(centre - sz * 0.5, sz))


func breach(kind: int) -> bool:
	if not breakable or state != State.INTACT or not can_breach(material, kind):
		return false
	state = State.BREACHED
	revision += 1
	_rebuild()
	state_changed.emit(self)
	return true


## Replicated state from the host. Ignores stale or duplicate revisions (round changes go through reset()).
func apply_remote(new_state: int, new_revision: int) -> bool:
	if new_revision <= revision:
		return false
	state = new_state
	revision = new_revision
	charge = null
	_rebuild()
	state_changed.emit(self)
	return true


func reset() -> void:
	if state == State.INTACT and revision == 0:
		return
	state = State.INTACT
	revision = 0
	charge = null
	_rebuild()
	state_changed.emit(self)


func snapshot() -> Dictionary:
	return {"id": wall_id, "state": state, "revision": revision}


func shape_count() -> int:
	var n := 0
	for c in get_children():
		if c is CollisionShape3D:
			n += 1
	return n


func mesh_count() -> int:
	var n := 0
	for c in get_children():
		if c is MeshInstance3D:
			n += 1
	return n


func _rebuild() -> void:
	for c in get_children():
		if c is CollisionShape3D or c is MeshInstance3D:
			remove_child(c)
			c.free()
	if _decor:
		_decor.free()
		_decor = null
	for b in part_boxes(state):
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b.size
		cs.shape = bs
		cs.position = b.get_center()
		add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		bm.material = _surface
		mi.mesh = bm
		mi.position = b.get_center()
		add_child(mi)
	if state == State.BREACHED:
		_build_decor()


## Cosmetic only (no collision): scorch decal around the opening and a little floor rubble on both sides.
## Kept under one child node so mesh_count()/shape_count() still mirror the authored part list.
func _build_decor() -> void:
	_decor = Node3D.new()
	_decor.name = "BreachDecor"
	add_child(_decor)
	var thick := _size.z if _long_x else _size.x
	var hh := minf(OPENING_H, _size.y - 0.3)
	var d := Decal.new()
	d.texture_albedo = _scorch()
	d.modulate = Color(0.08, 0.07, 0.06) if material == Mat.ORDINARY else Color(0.05, 0.05, 0.06)
	d.albedo_mix = 0.9
	# Decal projects along its local Y; turn Y to the wall normal. Its X spans height, Z spans the wall.
	d.size = Vector3(hh + 1.0, thick + 0.3, OPENING_W + 1.2)
	d.position = Vector3(0, hh * 0.5 - _size.y * 0.5, 0)
	if _long_x:
		d.rotation = Vector3(0, deg_to_rad(90), deg_to_rad(90))
	else:
		d.rotation = Vector3(0, 0, deg_to_rad(90))
	d.cull_mask = 1
	_decor.add_child(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(wall_id)
	var chunk_mat := _surface
	for i in 10:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.05, 0.16)
		bm.size = Vector3(s, s * rng.randf_range(0.3, 0.7), s * rng.randf_range(0.6, 1.4))
		mi.mesh = bm
		mi.material_override = chunk_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var side := -1.0 if i % 2 == 0 else 1.0
		var u := rng.randf_range(-0.7, 0.7)
		var n := side * (thick * 0.5 + rng.randf_range(0.1, 0.8))
		var y := -_size.y * 0.5 + bm.size.y * 0.5
		mi.position = Vector3(u, y, n) if _long_x else Vector3(n, y, u)
		mi.rotation.y = rng.randf() * TAU
		_decor.add_child(mi)


static func _scorch() -> ImageTexture:
	if _scorch_tex:
		return _scorch_tex
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.06
	n.seed = 7
	for y in size:
		for x in size:
			var p := (Vector2(x, y) / float(size - 1)) * 2.0 - Vector2.ONE
			var r := p.length() + n.get_noise_2d(x, y) * 0.25
			var a := clampf(1.0 - smoothstep(0.35, 0.95, r), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * 0.9))
	img.generate_mipmaps()
	_scorch_tex = ImageTexture.create_from_image(img)
	return _scorch_tex
