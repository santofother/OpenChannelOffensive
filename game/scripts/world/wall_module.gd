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

var wall_id := ""
var material := Mat.ORDINARY
var breakable := true
var state := State.INTACT
var revision := 0 ## increments on each state change; reset() returns to 0
var charge: Node = null ## pending charge, if any
var _size := Vector3.ONE
var _color := Color.GRAY
var _long_x := false


static func can_breach(mat: int, kind: int) -> bool:
	return (mat == Mat.ORDINARY and kind == Kind.ORDINARY) or (mat == Mat.REINFORCED and kind == Kind.HEAVY)


## `lo`/`hi` are world-space min/max corners (any order). Call before add_child.
func setup(id: String, lo: Vector3, hi: Vector3, mat: int, col: Color, can_break: bool = true) -> void:
	name = id
	wall_id = id
	material = mat
	breakable = can_break
	_color = col
	_size = (hi - lo).abs()
	_long_x = _size.x > _size.z
	position = (lo + hi) * 0.5
	collision_layer = 1
	collision_mask = 0
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color if state == State.INTACT else _color.darkened(0.25)
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
		bm.material = mat
		mi.mesh = bm
		mi.position = b.get_center()
		add_child(mi)
