class_name WallModule
extends StaticBody3D
## One destructible wall panel. State, visual mesh and collision are always rebuilt together from the same
## authored part list, so they cannot disagree. Transitions: INTACT -> BREACHED only (reset() restores).
## Ordinary panels need the ordinary charge; reinforced panels need the heavy charge.

enum Mat { ORDINARY, REINFORCED }
enum State { INTACT, BREACHED }
enum Kind { ORDINARY, HEAVY } ## charge kinds

signal state_changed(module: WallModule)
signal fragments_fell(module: WallModule, pieces: Array[Rect2])

const OPENING_W := 1.2
const OPENING_H := 2.1
## Rifle damage multiplier through an intact ordinary panel (bounded by Ballistics thickness/surface limits).
const ORDINARY_PEN_MULT := 0.5

var impact_destructible := false
var openings: Array[Rect2] = [] ## local wall-plane cutouts; shared by visible mesh and collision
const MAX_OPENINGS := 16
var detached: Array[Rect2] = [] ## permanent holes left by unsupported pieces
var bullet_breakable := false ## map cover only; ordinary walls still need explosives
var impact_hp := 120.0
var wall_id := ""
var material := Mat.ORDINARY
var base_material := Mat.ORDINARY ## authored material; reinforcement lasts one round
var breakable := true
var remove_whole := false ## bounded map cells clear completely for one qualified charge
var state := State.INTACT
var revision := 0 ## increments on each state change; reset() returns to 0
var charge: Node = null ## pending charge, if any
var _size := Vector3.ONE
var _surface: Material
var _base_surface: Material
var _decor: Node3D
static var _scorch_tex: ImageTexture
var _long_x := false


func face_normal() -> Vector3:
	return global_basis.z if _long_x else global_basis.x


static func can_breach(mat: int, kind: int) -> bool:
	return (mat == Mat.ORDINARY and kind == Kind.ORDINARY) or (mat == Mat.REINFORCED and kind == Kind.HEAVY)


## `lo`/`hi` are world-space min/max corners (any order). Call before add_child.
func setup(id: String, lo: Vector3, hi: Vector3, mat: int, surface: Material, can_break: bool = true) -> void:
	name = id
	wall_id = id
	material = mat
	base_material = mat
	breakable = can_break
	_surface = surface
	_base_surface = surface
	_size = (hi - lo).abs()
	_long_x = _size.x > _size.z
	position = (lo + hi) * 0.5
	collision_layer = 1
	collision_mask = 0
	_set_pen()
	_rebuild()


## Reinforced panels stop rifle rounds outright (pen_mult 0); ordinary panels pass half damage.
func _set_pen() -> void:
	set_meta("pen_mult", ORDINARY_PEN_MULT if material == Mat.ORDINARY else 0.0)


func can_reinforce() -> bool:
	return breakable and state == State.INTACT and material == Mat.ORDINARY and charge == null


## Upgrades an intact ordinary panel in place. Revision bumps so clients apply it exactly once.
func reinforce() -> bool:
	if not can_reinforce():
		return false
	material = Mat.REINFORCED
	_surface = Surfaces.get_mat("metal_plate")
	revision += 1
	_set_pen()
	_rebuild()
	state_changed.emit(self)
	return true


func part_boxes(s: int) -> Array[AABB]:
	var out: Array[AABB] = []
	var half := _size * 0.5
	if s == State.INTACT or not breakable:
		out.append(AABB(-half, _size))
		return _cut_parts(out, openings + detached) if impact_destructible else out
	if remove_whole:
		return out
	var length := _size.x if _long_x else _size.z
	var h := _size.y
	if length < 0.6 or h < 0.6:
		return out # short sill/lintel pieces are removed as a whole
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


func impact(point: Vector3, damage: float, melee: bool = false) -> bool:
	if not impact_destructible or not breakable or state != State.INTACT or material != Mat.ORDINARY:
		return false
	if bullet_breakable:
		hit_cover(damage, point)
		return true
	var local := to_local(point)
	var center := Vector2(local.x if _long_x else local.z, local.y)
	var radius := .27 if melee else clampf(sqrt(maxf(damage, 1.0) / 34.0) * .065, .04, .11)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([wall_id, revision, center])
	for band in 3:
		var width := radius * rng.randf_range(1.35, 2.0)
		var offset := rng.randf_range(-radius * .22, radius * .22)
		openings.append(Rect2(center + Vector2(-width * .5 + offset, -radius + band * radius * 2.0 / 3.0), Vector2(width, radius * 2.0 / 3.0 + .005)))
	# Sustained damage coalesces nearby chips into larger holes, never closes an existing opening.
	while openings.size() > MAX_OPENINGS:
		var best_a := 0
		var best_b := 1
		var best := INF
		for a in openings.size():
			for b in range(a + 1, openings.size()):
				var distance := openings[a].get_center().distance_squared_to(openings[b].get_center())
				if distance < best:
					best = distance
					best_a = a
					best_b = b
		openings[best_a] = openings[best_a].merge(openings[best_b])
		openings.remove_at(best_b)
	revision += 1
	_rebuild()
	state_changed.emit(self)
	return true

func plane_rect(box: AABB) -> Rect2:
	return Rect2(Vector2(box.position.x if _long_x else box.position.z, box.position.y),
		Vector2(box.size.x if _long_x else box.size.z, box.size.y))


func plane_box(rect: Rect2) -> AABB:
	var lo := Vector3(rect.position.x, rect.position.y, -_size.z * .5) if _long_x \
		else Vector3(-_size.x * .5, rect.position.y, rect.position.x)
	var size := Vector3(rect.size.x, rect.size.y, _size.z) if _long_x \
		else Vector3(_size.x, rect.size.y, rect.size.x)
	return AABB(lo, size)


func _cut_parts(parts: Array[AABB], cuts: Array[Rect2]) -> Array[AABB]:
	for hole: Rect2 in cuts:
		var next: Array[AABB] = []
		for box: AABB in parts:
			var rect := plane_rect(box)
			var cut := rect.intersection(hole)
			if not cut.has_area():
				next.append(box)
				continue
			# Four non-overlapping residual rectangles exactly tile the original minus this cut.
			for piece: Rect2 in [Rect2(rect.position, Vector2(cut.position.x - rect.position.x, rect.size.y)),
				Rect2(Vector2(cut.end.x, rect.position.y), Vector2(rect.end.x - cut.end.x, rect.size.y)),
				Rect2(Vector2(cut.position.x, rect.position.y), Vector2(cut.size.x, cut.position.y - rect.position.y)),
				Rect2(Vector2(cut.position.x, cut.end.y), Vector2(cut.size.x, rect.end.y - cut.end.y))]:
				if piece.size.x < .001 or piece.size.y < .001:
					continue
				next.append(plane_box(piece))
		parts = next
	return parts

func hit_cover(damage: float, point: Variant = null) -> void:
	if not bullet_breakable or material != Mat.ORDINARY or state != State.INTACT:
		return
	impact_hp -= maxf(0.0, damage)
	if impact_hp <= 0.0:
		breach(Kind.ORDINARY, point)


var break_contact: Vector3

func breach(kind: int, point: Variant = null) -> bool:
	if not breakable or state != State.INTACT or not can_breach(material, kind):
		return false
	state = State.BREACHED
	break_contact = point if point is Vector3 else global_position
	if bullet_breakable:
		ProcAudio.play(self, "cover_break", break_contact)
	revision += 1
	_rebuild()
	state_changed.emit(self)
	return true


## The cohesion pass removes unsupported solids from the authoritative wall.
func detach(pieces: Array[Rect2]) -> void:
	detached.append_array(pieces)
	if part_boxes(state).is_empty():
		state = State.BREACHED
		break_contact = global_position
	revision += 1
	_release_charge(pieces)
	_rebuild()
	state_changed.emit(self)
	fragments_fell.emit(self, pieces)


func _release_charge(pieces: Array[Rect2]) -> void:
	if not is_instance_valid(charge):
		return
	var local := to_local((charge as Node3D).global_position)
	var point := Vector2(local.x if _long_x else local.z, local.y)
	for piece: Rect2 in pieces:
		if piece.grow(.015).has_point(point):
			charge.queue_free()
			charge = null
			return


## Replicated state from the host. Ignores stale or duplicate revisions (round changes go through reset()).
func apply_remote(new_state: int, new_revision: int, new_material: int = -1, cuts: Array = [],
		missing: Array = [], animate := false) -> bool:
	if new_revision <= revision:
		return false
	var falling: Array[Rect2] = []
	for i in range(detached.size(), missing.size()):
		falling.append(missing[i])
	state = new_state
	openings.assign(cuts)
	detached.assign(missing)
	if new_material >= 0:
		_set_material(new_material)
	revision = new_revision
	_release_charge(falling)
	_rebuild()
	state_changed.emit(self)
	if animate and not falling.is_empty():
		fragments_fell.emit(self, falling)
	return true


func _set_material(m: int) -> void:
	material = m
	_surface = _base_surface if m == base_material else Surfaces.get_mat("metal_plate")
	_set_pen()


func reset() -> void:
	impact_hp = 120.0
	openings.clear()
	detached.clear()
	if state == State.INTACT and revision == 0:
		return
	state = State.INTACT
	_set_material(base_material)
	revision = 0
	charge = null
	_rebuild()
	state_changed.emit(self)


func snapshot() -> Dictionary:
	return {"id": wall_id, "state": state, "revision": revision, "material": material, "openings": openings.duplicate(), "detached": detached.duplicate()}


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
	if state == State.BREACHED and not remove_whole:
		_build_decor()
	elif state == State.INTACT and material == Mat.REINFORCED and openings.is_empty() and detached.is_empty():
		_build_reinforced_art()


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


func _build_reinforced_art() -> void:
	if not GearModels.has("gear/reinforced_panel"):
		return
	_decor = Node3D.new()
	_decor.name = "ReinforcedArt"
	add_child(_decor)
	var width := _size.x if _long_x else _size.z
	var thick := _size.z if _long_x else _size.x
	for side in [-1, 1]:
		var panel := GearModels.instance("gear/reinforced_panel")
		_decor.add_child(panel)
		panel.scale = Vector3(width, _size.y, 1.0)
		panel.position = Vector3(0, 0, side * (thick * .5 + .015)) if _long_x else Vector3(side * (thick * .5 + .015), 0, 0)
		panel.rotation.y = (0.0 if side == 1 else PI) + (0.0 if _long_x else PI * .5)
