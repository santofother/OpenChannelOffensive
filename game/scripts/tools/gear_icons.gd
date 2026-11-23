extends SceneTree
## Reproducible shop thumbnails from the shipped meshes (run windowed with --script).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 128)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(cam)
	cam.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -40, 0)
	light.light_energy = 2.0
	stage.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .6
	stage.add_child(environment)
	DirAccess.make_dir_recursive_absolute("res://assets/icons")
	var ids := ["vest", "helmet", "medkit", "ordinary", "heavy", "kit", "frag", "flash", "smoke", "incendiary", "flashlight", "laser", "nvg"] + Weapons.ORDER
	for id: String in ids:
		var family := "weapons" if Weapons.DEFS.has(id) else ("wearables" if id in ["vest", "helmet"] else ("attachments" if id in ["flashlight", "laser", "nvg"] else ("grenades" if id in ["frag", "flash", "smoke", "incendiary"] else "gear")))
		var model := GearModels.instance(family + "/" + id)
		if model == null:
			continue
		stage.add_child(model)
		var bounds := AABB()
		var first := true
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mi.global_transform * mi.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		var center := bounds.get_center()
		cam.size = maxf(bounds.size.length() * .82, .1)
		cam.position = center + Vector3(1.4, .6, 1.0) * maxf(bounds.size.length(), .2)
		cam.look_at(center)
		await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://assets/icons/" + id + ".png")
		model.free()
	print("GEAR_ICONS_DONE")
	quit()
