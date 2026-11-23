class_name BotNav
extends RefCounted
## Host-only walkable mesh for bots, baked once per match from the map's static colliders (world layer),
## so it works for any map without hand-placed waypoints. Bakes off the main thread; until it is ready
## (and wherever no path exists) bots walk straight at their goal.
## Breached walls are not re-baked: bots keep to doorways and open floor, which stays correct as walls
## only ever open during a round.

const AGENT_RADIUS := 0.38 ## player capsule 0.35 + a little clearance on door frames
const CELL := 0.1

var map := RID()
var region := RID()
var ready := false
var _mesh: NavigationMesh


## `area`: the playable volume to bake. Maps can exclude roof and other non-walkable slabs.
func build(root: Node3D, area: AABB) -> void:
	_mesh = NavigationMesh.new()
	_mesh.agent_radius = AGENT_RADIUS
	_mesh.agent_height = 1.7
	_mesh.agent_max_climb = 0.3
	_mesh.agent_max_slope = 40.0
	_mesh.cell_size = CELL
	_mesh.cell_height = 0.05
	_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_mesh.geometry_collision_mask = 1
	_mesh.filter_baking_aabb = area
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, CELL)
	NavigationServer3D.map_set_cell_height(map, 0.05)
	NavigationServer3D.map_set_active(map, true)
	var source := NavigationMeshSourceGeometryData3D.new()
	var t0 := Time.get_ticks_msec()
	# Doors open for bots (DoorSystem.host_bots): bake doorways as walkable.
	var ignored := root.get_tree().get_nodes_in_group("door_bodies")
	ignored.append_array(root.get_tree().get_nodes_in_group("navigation_exclude"))
	var layers := []
	for body: CollisionObject3D in ignored:
		layers.append(body.collision_layer)
		body.collision_layer = 0
	NavigationServer3D.parse_source_geometry_data(_mesh, source, root)
	for i in ignored.size():
		(ignored[i] as CollisionObject3D).collision_layer = layers[i]
	NavigationServer3D.bake_from_source_geometry_data_async(_mesh, source, func() -> void:
		_on_baked.call_deferred(t0))


func _on_baked(t0: int) -> void:
	if not map.is_valid():
		return
	region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, _mesh)
	ready = true
	print("[Bots] navigation baked in %d ms (%d polygons)" % [Time.get_ticks_msec() - t0, _mesh.get_polygon_count()])


## Walkable route from `from` to `to`; empty while baking or when no route exists.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not ready or NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(map, from, to, true)


## Nearest walkable point (or the point itself before the bake finishes).
func snap(p: Vector3) -> Vector3:
	if not ready or NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	return NavigationServer3D.map_get_closest_point(map, p)


func free_rids() -> void:
	if region.is_valid():
		NavigationServer3D.free_rid(region)
	if map.is_valid():
		NavigationServer3D.free_rid(map)
	region = RID()
	map = RID()
	ready = false
