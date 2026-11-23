extends SceneTree
func _initialize() -> void:
	var failures := 0
	var rows := []
	for family: String in ["weapons", "gear", "grenades", "attachments", "wearables"]:
		for file in DirAccess.get_files_at("res://assets/models/" + family):
			if not file.ends_with(".glb"):
				continue
			var path: String = family + "/" + file.trim_suffix(".glb")
			var model := GearModels.instance(path)
			if model == null:
				failures += 1
				continue
			var tris := GearModels.triangles(model)
			rows.append({"asset": path, "triangles": tris})
			if tris <= 0:
				failures += 1
			if family == "weapons" and not file.ends_with("_w.glb") and file != "hands.glb":
				for socket in ["Hand_R", "Hand_L", "Muzzle", "Sight"]:
					if GearModels.socket(model, socket) == null:
						failures += 1
			if path in ["weapons/p9_match", "weapons/smg", "weapons/carbine", "weapons/service_rifle"]:
				var blocks := _sight_blocks(model)
				print("OPTIC_CLEAR ", path, " blockers=", blocks)
				if not blocks.is_empty():
					failures += 1
			if file == "hands.glb":
				var rigs := model.find_children("*", "Skeleton3D", true, false)
				if rigs.size() != 6:
					failures += 1
				for rig: Skeleton3D in rigs:
					if rig.find_bone("Forearm") < 0 or rig.find_bone("Hand") < 0:
						failures += 1
			model.free()
	for tint: Color in [StandIn.TEAM_RED, StandIn.TEAM_BLUE]:
		var actor := StandIn.build(tint)
		for mask in 4:
			StandIn.equip(actor, "service_rifle", 100 if mask & 1 else 0, mask & 2 != 0)
			StandIn.animate(actor, .1, Vector3.RIGHT, 1.2, .25, -.5, true, false, 0, true)
			if actor.has_node("EquippedVest") != bool(mask & 1) or actor.has_node("EquippedHelmet") != bool(mask & 2):
				failures += 1
			var pose := actor.get_node("Pose") as OperatorPose
			if pose.rig.get_bone_count() != 25 or not actor.get_node("EquippedGun").transform.is_equal_approx(pose.socket.transform):
				failures += 1
		actor.free()
	if rows.size() != 38:
		failures += 1
	var output := FileAccess.open("res://../session/evidence/09.75/asset-counts.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(rows, "\t"))
	print("GEAR_VERIFY ", rows.size(), " models; failures=", failures)
	quit(0 if failures == 0 else 1)


# A centered socket is insufficient if an opaque cap blocks the optic's actual sight line.
func _relative(n: Node3D, model: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent() as Node3D
	while p and p != model:
		xf = p.transform * xf
		p = p.get_parent() as Node3D
	return xf

func _sight_blocks(model: Node3D) -> Array:
	var sight := GearModels.socket(model, "Sight")
	var axis := _relative(sight, model).origin
	var blocks := []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.name in ["SightGlass", "Reticle", "Stock"]:
			continue
		var xf := _relative(mesh, model)
		var faces := mesh.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(axis + Vector3.BACK * .3, axis + Vector3.FORWARD * .5,
					xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]) != null:
				blocks.append(str(mesh.name))
				break
	return blocks
