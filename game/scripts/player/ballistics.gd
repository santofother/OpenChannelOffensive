class_name Ballistics
extends RefCounted
## Hitscan with muzzle obstruction and bounded penetration.
## The aim ray (camera -> crosshair point) says where the player is looking; the shot itself leaves the muzzle,
## which sits off-axis. Cover between camera and muzzle, or cover the muzzle ray stops on before the aim point,
## blocks the shot. Penetrable bodies carry meta "pen_mult" (damage multiplier) and must be box shapes no thicker
## than PEN_MAX_THICKNESS; at most PEN_MAX_SURFACES are passed. Openings are collision holes, so a breached panel
## changes what the shot can pass through together with its mesh and collision.
## Players are not physics-raycast: callers pass hit volumes (vertical capsules, possibly rewound for lag
## compensation) as [{id, a: feet point, b: top point}] and they are tested analytically on every segment.

const PEN_MAX_SURFACES := 2
const PEN_MAX_THICKNESS := 0.3
const PLAYER_RADIUS := 0.3
## Hits whose closest point on the body axis lies within this distance of the top end count as headshots.
const HEAD_ZONE := 0.24


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return space.intersect_ray(q)


## Nearest player capsule crossed by segment p->q. Returns {} or {id, position, t (distance from p)}.
static func players_on_segment(p: Vector3, q: Vector3, players: Array) -> Dictionary:
	var best := {}
	var seg_len := p.distance_to(q)
	if seg_len < 0.0001:
		return best
	var d := (q - p) / seg_len
	for pl in players:
		var c := Geometry3D.get_closest_points_between_segments(p, q, pl["a"], pl["b"])
		var miss := c[0].distance_to(c[1])
		if miss > PLAYER_RADIUS:
			continue
		var t := maxf(p.distance_to(c[0]) - sqrt(PLAYER_RADIUS * PLAYER_RADIUS - miss * miss), 0.0)
		if best.is_empty() or t < float(best["t"]):
			var head: bool = c[1].distance_to(pl["b"]) <= HEAD_ZONE
			best = {"id": int(pl["id"]), "position": p + d * t, "t": t, "head": head}
	return best


## Distance from `point` (on the entry face) to where a ray along `dir` leaves the box shape that was hit,
## or -1 if the shape is not a box.
static func box_exit(body: CollisionObject3D, shape_idx: int, point: Vector3, dir: Vector3) -> float:
	var owner_id := body.shape_find_owner(shape_idx)
	var node := body.shape_owner_get_owner(owner_id) as Node3D
	if node == null:
		return -1.0
	var shape := body.shape_owner_get_shape(owner_id, 0) as BoxShape3D
	if shape == null:
		return -1.0
	var inv := node.global_transform.affine_inverse()
	var lp := inv * point
	var ld := (inv.basis * dir).normalized()
	var half := shape.size * 0.5
	var t_exit := INF
	for i in 3:
		if absf(ld[i]) < 0.000001:
			continue
		var t1 := (-half[i] - lp[i]) / ld[i]
		var t2 := (half[i] - lp[i]) / ld[i]
		t_exit = minf(t_exit, maxf(t1, t2))
	return maxf(t_exit, 0.0)


## Result: {hit, position, normal, collider, player_id (-1 none), distance, muzzle_blocked, damage_mult,
##          penetrated (surfaces passed), impacts: [{position, normal, collider}] entry points on passed surfaces}
static func resolve(space: PhysicsDirectSpaceState3D, eye: Vector3, dir: Vector3, muzzle: Vector3,
		max_range: float, mask: int, exclude: Array[RID], players: Array = []) -> Dictionary:
	var far := eye + dir * max_range
	var aim := _ray(space, eye, far, mask, exclude)
	var aim_point: Vector3 = aim["position"] if not aim.is_empty() else far
	var aim_obj: Variant = aim["collider"] if not aim.is_empty() else null
	var aim_pl := players_on_segment(eye, aim_point, players)
	if not aim_pl.is_empty():
		aim_point = aim_pl["position"]
		aim_obj = int(aim_pl["id"])
	var aim_dist := eye.distance_to(aim_point)
	# 1) Cover between the camera and the muzzle (e.g. wall pressed against the barrel).
	var near := _ray(space, eye, muzzle, mask, exclude)
	if not near.is_empty():
		return _world(near, eye, true, 1.0, 0, [])
	# 2) Aim point behind the muzzle plane: surface (or player) is closer than the barrel.
	var to_point := aim_point - muzzle
	if to_point.dot(dir) <= 0.05:
		if not aim_pl.is_empty():
			return _player(aim_pl, eye, false, 1.0, 0, [])
		if aim.is_empty():
			return _miss(true)
		return _world(aim, eye, true, 1.0, 0, [])
	# 3) The real shot from the muzzle through the aim point, passing penetrable surfaces.
	var shot_dir := to_point.normalized()
	var p := muzzle
	var end := muzzle + shot_dir * max_range
	var ex: Array[RID] = exclude.duplicate()
	var mult := 1.0
	var passed := 0
	var impacts: Array = []
	while true:
		var h := _ray(space, p, end, mask, ex)
		var seg_end: Vector3 = h["position"] if not h.is_empty() else end
		var pl := players_on_segment(p, seg_end, players)
		if not pl.is_empty():
			var blocked_p: bool = aim_obj is int and int(aim_obj) != int(pl["id"]) and eye.distance_to(pl["position"]) < aim_dist - 0.05
			return _player(pl, eye, blocked_p, mult, passed, impacts)
		if h.is_empty():
			var m := _miss(not aim.is_empty() and aim_pl.is_empty() and passed == 0)
			m["penetrated"] = passed
			m["impacts"] = impacts
			m["damage_mult"] = mult
			return m
		var col: Object = h["collider"]
		var pen := float(col.get_meta("pen_mult", 0.0)) if col is Node else 0.0
		if pen > 0.0 and passed < PEN_MAX_SURFACES and col is CollisionObject3D:
			var thick := box_exit(col as CollisionObject3D, int(h["shape"]), h["position"], shot_dir)
			if thick >= 0.0 and thick <= PEN_MAX_THICKNESS:
				impacts.append({"position": h["position"], "normal": h["normal"], "collider": col})
				mult *= pen
				passed += 1
				p = h["position"] + shot_dir * (thick + 0.002)
				ex.append((col as CollisionObject3D).get_rid())
				continue
		# aim_obj is a collider or, when the crosshair was on a player, that player's id (int):
		# a wall the muzzle hits short of an aimed-at player is cover blocking the shot.
		var aimed_other: bool = aim_obj is int or col != aim_obj
		var blocked: bool = aim_obj == null or (aimed_other and eye.distance_to(h["position"]) < aim_dist - 0.05)
		return _world(h, eye, blocked, mult, passed, impacts)
	return _miss(false)


static func _miss(blocked: bool) -> Dictionary:
	return {"hit": false, "position": Vector3.ZERO, "normal": Vector3.ZERO, "collider": null, "player_id": -1,
		"distance": 0.0, "muzzle_blocked": blocked, "damage_mult": 1.0, "penetrated": 0, "impacts": []}


static func _world(h: Dictionary, eye: Vector3, blocked: bool, mult: float, passed: int, impacts: Array) -> Dictionary:
	return {"hit": true, "position": h["position"], "normal": h["normal"], "collider": h["collider"], "player_id": -1,
		"distance": eye.distance_to(h["position"]), "muzzle_blocked": blocked, "damage_mult": mult,
		"penetrated": passed, "impacts": impacts}


static func _player(pl: Dictionary, eye: Vector3, blocked: bool, mult: float, passed: int, impacts: Array) -> Dictionary:
	return {"hit": true, "position": pl["position"], "normal": Vector3.ZERO, "collider": null, "player_id": int(pl["id"]),
		"distance": eye.distance_to(pl["position"]), "muzzle_blocked": blocked, "damage_mult": mult,
		"penetrated": passed, "impacts": impacts, "head": bool(pl.get("head", false))}
