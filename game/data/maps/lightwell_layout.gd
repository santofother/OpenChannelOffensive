class_name LightwellLayout
extends RefCounted
## Metre coordinates, north is -Z. Each wall run can have openings measured
## from its first endpoint, including on the angled exterior and partitions.
const PATH := "res://data/maps/lightwell.json"
const CELL_VERSION := 2
var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))

func world(u: float, v: float, y: float = 0.0) -> Vector3:
	return Vector3(u - float(data.size[0]) * 0.5, y, v - float(data.size[1]) * 0.5)

func elevation(level: int) -> float:
	return float(data.deck) * level

func polygon(room: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p: Array in room.poly:
		var at := world(p[0], p[1])
		result.append(Vector2(at.x, at.z))
	return result

func identity() -> String:
	return "%s/v%d/%s" % [data.map_id, data.revision,
		(FileAccess.get_file_as_string(PATH) + "/cells-%d" % CELL_VERSION).sha256_text()]

func attack_zone_count() -> int:
	return data.attack_zones.size()

func spawn_at(index: int, attack_zone: int = 0) -> Array:
	var p: Array = data.attack_zones[attack_zone].spawns[index] if index < 3 else data.defend_spawns[index - 3]
	return [world(p[0], p[1], 0.05), float(p[2])]

func tuning() -> MatchTuning:
	var t: MatchTuning = preload("res://data/match_tuning.tres").duplicate(true)
	t.sites.clear()
	for i in data.sites.size():
		var p: Array = data.sites[i]
		var floor_y := elevation(int(p[2]))
		t.sites.append(world(p[0], p[1], floor_y + 0.05))
		var kind: String = ["siteA", "siteB"][i]
		for room: Dictionary in data.rooms:
			if room.kind == kind:
				t.site_areas.append({"polygon": polygon(room), "bottom": floor_y - .08,
					"top": floor_y + float(data.wall_height)})
				break
	return t

func cells() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in data.walls.size():
		var run: Dictionary = data.walls[index]
		var floor_y := elevation(run.level)
		var start := world(run.a[0], run.a[1], floor_y)
		var end := world(run.b[0], run.b[1], floor_y)
		var along := start.direction_to(end)
		var length := start.distance_to(end)
		# A small end lap seals angled joints. Cells within a straight run butt cleanly.
		var lap := float(data.wall_thickness) * .27
		var cursor := -lap
		var cell_index := 0
		var gaps: Array = run.gaps.duplicate()
		gaps.append([length + lap, length + lap])
		for gap: Array in gaps:
			var stop := float(gap[0])
			var n := ceili((stop - cursor) / float(data.max_cell_width))
			for i in n:
				var a := lerpf(cursor, stop, float(i) / n)
				var b := lerpf(cursor, stop, float(i + 1) / n)
				out.append(_cell(index, cell_index, start, along, a, b, 0.0, data.wall_height))
				cell_index += 1
			cursor = float(gap[1])
		for i in run.gaps.size():
			var gap: Array = run.gaps[i]
			out.append(_cell(index, 1000 + i, start, along, gap[0], gap[1], data.door_height, data.wall_height))
	for i in data.props.size():
		var prop: Dictionary = data.props[i]
		var p: Array = prop.rect
		var height := float(prop.height)
		var center := world(p[0] + p[2] * .5, p[1] + p[3] * .5, elevation(prop.level) + height * .5)
		out.append({"id": "lightwell/v%d/cover_%02d" % [data.revision, i], "run": -1,
			"center": center, "size": Vector3(p[2], height, p[3]), "yaw": deg_to_rad(float(prop.get("yaw", 0))),
			"prop": prop})
	return out

func doors() -> Array:
	var out := []
	for index in data.walls.size():
		var run: Dictionary = data.walls[index]
		var floor_y := elevation(run.level)
		var start := world(run.a[0], run.a[1], floor_y)
		var along := start.direction_to(world(run.b[0], run.b[1], floor_y))
		for i in run.gaps.size():
			var gap: Array = run.gaps[i]
			out.append({"hinge": start + along * float(gap[0]), "along": along, "width": float(gap[1]) - float(gap[0]),
				"header": _cell_id(index, 1000 + i), "run": index, "level": run.level, "exterior": run.exterior})
	return out

func _cell_id(run: int, index: int) -> String:
	return "lightwell/v%d/W%03d/cell_%04d" % [data.revision, run, index]

func _cell(run: int, index: int, start: Vector3, along: Vector3, a: float, b: float, bottom: float, top: float) -> Dictionary:
	return {"id": _cell_id(run, index), "run": run,
		"center": start + along * ((a + b) * .5) + Vector3.UP * ((top + bottom) * .5),
		"size": Vector3(b - a, top - bottom, data.wall_thickness), "yaw": -atan2(along.z, along.x)}
