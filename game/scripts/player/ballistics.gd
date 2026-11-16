class_name Ballistics
extends RefCounted
## Hitscan with muzzle obstruction. The aim ray (camera -> crosshair point) says where the player is
## looking; the shot itself leaves the muzzle, which sits off-axis. Cover between camera and muzzle,
## or cover that the muzzle ray hits before the aim point, blocks the shot.


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, exclude: Array[RID]) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return space.intersect_ray(q)


## Result: {hit, position, normal, collider, distance, muzzle_blocked}
static func resolve(space: PhysicsDirectSpaceState3D, eye: Vector3, dir: Vector3, muzzle: Vector3,
		max_range: float, mask: int, exclude: Array[RID]) -> Dictionary:
	var far := eye + dir * max_range
	var aim := _ray(space, eye, far, mask, exclude)
	var aim_point: Vector3 = aim["position"] if not aim.is_empty() else far
	# 1) Cover between the camera and the muzzle (e.g. wall pressed against the barrel).
	var near := _ray(space, eye, muzzle, mask, exclude)
	if not near.is_empty():
		return _result(near, eye, true)
	# 2) Aim point behind the muzzle plane: surface is closer than the barrel.
	var to_point := aim_point - muzzle
	if to_point.dot(dir) <= 0.05:
		return _result(aim, eye, true)
	# 3) The real shot from the muzzle toward the aim point, slightly overshooting the surface.
	var shot_dir := to_point.normalized()
	var overshoot := 0.1 if not aim.is_empty() else 0.0
	var shot := _ray(space, muzzle, muzzle + shot_dir * (to_point.length() + overshoot), mask, exclude)
	var blocked := false
	if not shot.is_empty():
		blocked = aim.is_empty() or shot["collider"] != aim["collider"]
	return _result(shot, muzzle, blocked)


static func _result(h: Dictionary, origin: Vector3, blocked: bool) -> Dictionary:
	if h.is_empty():
		return {"hit": false, "position": Vector3.ZERO, "normal": Vector3.ZERO, "collider": null,
			"distance": 0.0, "muzzle_blocked": blocked}
	return {"hit": true, "position": h["position"], "normal": h["normal"], "collider": h["collider"],
		"distance": origin.distance_to(h["position"]), "muzzle_blocked": blocked}
