class_name WallSupport
extends Node3D
## Lightwell wall solids are supported by the deck or by face contact with supported solids.
## The authority removes detached collision; short-lived rigid bodies show the fall on each screen.

const CONTACT := .008
const MAX_DEBRIS := 18
var scene: Node3D
var _neighbors := {}
var _floors := {}
var _dirty := {}


class Fragment:
	var wall: WallModule
	var rect: Rect2
	var bounds: AABB
	var center: Vector2
	var axes: Array[Vector2]
	var half: Vector2
	var anchored: bool

	func _init(module: WallModule, box: AABB, floor_y: float) -> void:
		wall = module
		rect = wall.plane_rect(box)
		bounds = wall.transform * box
		var p := wall.transform * box.get_center()
		center = Vector2(p.x, p.z)
		axes = [Vector2(wall.basis.x.x, wall.basis.x.z), Vector2(wall.basis.z.x, wall.basis.z.z)]
		half = Vector2(box.size.x, box.size.z) * .5
		anchored = bounds.position.y <= floor_y + CONTACT

	func touches(other: Fragment) -> bool:
		if not bounds.grow(CONTACT).intersects(other.bounds):
			return false
		var vertical := minf(bounds.end.y, other.bounds.end.y) - maxf(bounds.position.y, other.bounds.position.y)
		var offset := other.center - center
		var touches_edge := false
		for axis: Vector2 in axes + other.axes:
			var reach := absf(axis.dot(axes[0])) * half.x + absf(axis.dot(axes[1])) * half.y \
				+ absf(axis.dot(other.axes[0])) * other.half.x + absf(axis.dot(other.axes[1])) * other.half.y
			var overlap := reach - absf(offset.dot(axis))
			if overlap < -CONTACT:
				return false
			touches_edge = touches_edge or overlap <= CONTACT
		# A vertical seam needs shared height; a stacked contact needs a common footprint.
		return vertical > CONTACT or not touches_edge


func setup(world: Node3D, deck_heights: Dictionary) -> void:
	scene = world
	_floors = deck_heights
	var authored: Array[Fragment] = []
	for wall: WallModule in _floors:
		_neighbors[wall] = []
		authored.append(Fragment.new(wall, AABB(-wall._size * .5, wall._size), _floors[wall]))
		wall.state_changed.connect(_wall_changed)
		wall.fragments_fell.connect(_show_fall)
	for i in authored.size():
		for j in range(i):
			var a := authored[i]
			var b := authored[j]
			if _floors[a.wall] == _floors[b.wall] and a.touches(b):
				_neighbors[a.wall].append(b.wall)
				_neighbors[b.wall].append(a.wall)


func clear() -> void:
	_dirty.clear()
	for body: Node in get_children():
		body.queue_free()


func _wall_changed(wall: WallModule) -> void:
	var net: NetMatch = scene.net
	if wall.revision == 0 or (scene.net_mode and (net == null or not net.is_host or net._resetting)):
		return
	if _dirty.is_empty():
		_flush.call_deferred()
	_dirty[wall] = true


func _parts(wall: WallModule, cache: Dictionary) -> Array:
	if not cache.has(wall):
		var pieces: Array[Fragment] = []
		for box: AABB in wall.part_boxes(wall.state):
			pieces.append(Fragment.new(wall, box, _floors[wall]))
		cache[wall] = pieces
	return cache[wall]


func _flush() -> void:
	if _dirty.is_empty():
		return
	var candidates := _dirty
	_dirty = {}
	for wall: WallModule in candidates.keys():
		for neighbor: WallModule in _neighbors[wall]:
			candidates[neighbor] = true
	var parts := {}
	var supported := {}
	var unsupported := {}
	var to_drop := {}
	for wall: WallModule in candidates:
		for fragment: Fragment in _parts(wall, parts):
			if fragment.anchored or supported.has(fragment) or unsupported.has(fragment):
				continue
			var component := {fragment: true}
			if _find_floor(fragment, parts, supported, component):
				supported.merge(component)
			else:
				unsupported.merge(component)
				for falling: Fragment in component:
					if not to_drop.has(falling.wall):
						to_drop[falling.wall] = [] as Array[Rect2]
					to_drop[falling.wall].append(falling.rect)
	for wall: WallModule in to_drop:
		wall.detach(to_drop[wall])


func _find_floor(first: Fragment, parts: Dictionary, supported: Dictionary, component: Dictionary) -> bool:
	var frontier: Array[Fragment] = [first]
	while not frontier.is_empty():
		var piece: Fragment = frontier.pop_back()
		var neighbors: Array = _neighbors[piece.wall]
		for wall: WallModule in [piece.wall] + neighbors:
			for other: Fragment in _parts(wall, parts):
				if component.has(other) or not piece.touches(other):
					continue
				if other.anchored or supported.has(other):
					return true
				component[other] = true
				frontier.append(other)
	return false


func _show_fall(wall: WallModule, pieces: Array[Rect2]) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([wall.wall_id, wall.revision])
	for rect: Rect2 in pieces:
		if get_child_count() >= MAX_DEBRIS:
			break
		var box := wall.plane_box(rect)
		if rect.get_area() < .012:
			continue
		var debris := RigidBody3D.new()
		debris.collision_layer = 0
		debris.collision_mask = 1
		debris.mass = clampf(box.get_volume() * 25.0, .5, 30.0)
		var shape := CollisionShape3D.new()
		var solid := BoxShape3D.new()
		solid.size = box.size * .94
		shape.shape = solid
		debris.add_child(shape)
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = box.size
		mesh.material = wall._surface
		visual.mesh = mesh
		debris.add_child(visual)
		add_child(debris)
		debris.global_transform = Transform3D(wall.global_basis, wall.to_global(box.get_center()))
		debris.angular_velocity = wall.global_basis.x * rng.randf_range(-2.5, 2.5)
		debris.linear_velocity = wall.face_normal() * rng.randf_range(-.46, .46)
		var debris_id := debris.get_instance_id()
		get_tree().create_timer(2.2).timeout.connect(func() -> void:
			if is_instance_id_valid(debris_id):
				instance_from_id(debris_id).queue_free())
