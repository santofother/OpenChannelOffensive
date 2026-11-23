extends Node
var g: Node3D

func start(scene: Node3D) -> void:
	g = scene
	_run.call_deferred()

func wait_frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw

func save_view(dir: String, label: String) -> void:
	await wait_frames(12)
	var result := g.get_viewport().get_texture().get_image().save_png(dir.path_join(label + ".png"))
	print("CAPTURE ",label," ",result)

func _run() -> void:
	var dir := String(NetworkManager.args["capture-lightwell"])
	if dir == "true":
		dir = ProjectSettings.globalize_path("user://lightwell-captures")
	DirAccess.make_dir_recursive_absolute(dir)
	for layer in g.find_children("*","CanvasLayer",true,false):
		layer.visible = false
	await wait_frames(60)
	if g.loadout.viewmodel:
		g.loadout.viewmodel.hide()
	if NetworkManager.args.has("operator-closeup"):
		await _closeups(dir)
		get_tree().quit()
		return
	if NetworkManager.args.has("operators"):
		await _operators(dir)
		get_tree().quit()
		return
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 44.0
	top.position = g.layout.world(24.5,19.5,35)
	top.rotation_degrees = Vector3(-90,0,0)
	g.add_child(top)
	for roof: Node3D in g.roofs:
		roof.hide()
	# Ground plan removes the upper fixtures and slabs, then restores them for
	# the upper plan. First-person capture below uses the intact level.
	var hidden: Array[Node3D] = []
	for n in g.get_children():
		if n is WallModule or n is Label3D or (n is Node3D and String(n.name).begins_with("CeilingLamp")):
			if n.position.y > g.layout.elevation(1) - .04:
				hidden.append(n)
	for n: Node3D in g.upper_floors:
		hidden.append(n)
	for n: Node3D in hidden:
		n.hide()
	top.make_current()
	await save_view(dir,"Ground_plan")
	for n: Node3D in hidden:
		n.show()
	top.position = g.layout.world(24.8,9.0,35)
	top.size = 25
	await save_view(dir,"Upper_plan")
	for roof: Node3D in g.roofs:
		roof.show()
	for camera: Camera3D in g._cams:
		camera.make_current()
		await save_view(dir,str(camera.name))
	var shaft: Array = g.layout.data.stairs[0].rect
	var stair_eye: Vector3 = g.layout.world(shaft[0]+shaft[2]*.24,shaft[1]+.54,1.53)
	var stair_focus: Vector3 = g.layout.world(shaft[0]+shaft[2]*.44,shaft[1]+shaft[3]-.9,2.15)
	var stair_camera := Camera3D.new()
	g.add_child(stair_camera)
	stair_camera.position = stair_eye
	stair_camera.look_at(stair_focus)
	stair_camera.make_current()
	await save_view(dir,"Staff_Stair_Inside")
	print("CAPTURE_OK lightwell ",dir)
	get_tree().quit(0)

## Capture the purchased combinations in map lighting and measure six skinned actors in view.
func _operators(dir: String) -> void:
	var actors: Array[Node3D] = []
	var camera := Camera3D.new()
	camera.fov = 53
	g.add_child(camera)
	camera.make_current()
	for i in 6:
		var actor := StandIn.build(StandIn.TEAM_RED if i % 2 == 0 else StandIn.TEAM_BLUE)
		g.add_child(actor)
		actors.append(actor)
	for location in ["WestLink","Courtyard"]:
		var center: Vector3 = g.layout.world(11.5,17.8,.015) if location == "WestLink" else g.layout.world(24.4,17.7,.015)
		camera.position = center + Vector3(0,1.33,3.4)
		camera.look_at(center+Vector3.UP*.91)
		for view: int in 3:
			for i in 6:
				var actor := actors[i]
				actor.position = center + Vector3((i-2.5)*.72,0,0)
				actor.rotation.y = PI + view * PI/2
				var mask := (i/2+view)%4
				StandIn.equip(actor,"service_rifle",100 if mask & 1 else 0,mask & 2 != 0)
				StandIn.animate(actor,.1,Vector3.FORWARD*2 if i>1 else Vector3.ZERO,
						1.2 if i>3 and view==1 else 1.8, .15 if view==1 else 0, .25 if view==1 else 0,
						view==1, false, 0, true)
			await save_view(dir,location+"_"+["front","side","back"][view])
		var counts := []
		for frame in 90:
			for actor in actors:
				StandIn.animate(actor,1.0/60,Vector3.RIGHT*2,1.8,0,0,false,false,0,true)
			await RenderingServer.frame_post_draw
			var viewport := g.get_viewport() as Viewport
			counts.append([viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
					viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)])
		print("OPERATOR_RENDER ",location," frames=",counts.size()," first=",counts.front()," last=",counts.back()," stable=",counts.all(func(v): return v==counts.front()))

		if location == "Courtyard":
			camera.fov = 65
			for i in 6:
				var actor := actors[i]
				actor.rotation.y = PI-.65 if i==5 else PI+.4
				StandIn.equip(actor, ["service_rifle","service_rifle","p9","","service_rifle","service_rifle"][i],
						100 if i%2 else 0,i>2)
				for step in 24:
					StandIn.animate(actor,1.0/60,Vector3.RIGHT*2.5 if i==0 else Vector3.ZERO,
							1.2 if i==1 else 1.8,-.12 if i==1 else .1,.75 if i==2 else 0,i==2,i==4,1 if i==0 else 0,i!=5)
			await save_view(dir,"Courtyard_actions")

## Close framing of one operator per hold, for arm/shoulder deformation review.
## Each sheet shows rifle hip, rifle aim, pistol hip, pistol aim, unarmed and crouched rifle.
func _closeups(dir: String) -> void:
	var camera := Camera3D.new()
	camera.fov = 62
	g.add_child(camera)
	camera.make_current()
	var lamp := OmniLight3D.new()
	lamp.omni_range = 9
	lamp.light_energy = 2.2
	g.add_child(lamp)
	var center: Vector3 = g.layout.world(24.4,17.7,.015)
	var holds := [["service_rifle",false,1.8],["service_rifle",true,1.8],["p9",false,1.8],["p9",true,1.8],["",false,1.8],["service_rifle",true,1.2]]
	var actors: Array[Node3D] = []
	for i in holds.size():
		var actor := StandIn.build(StandIn.TEAM_RED if i % 2 == 0 else StandIn.TEAM_BLUE)
		g.add_child(actor)
		actors.append(actor)
		actor.position = center + Vector3((i-2.5)*.8,0,0)
		StandIn.equip(actor,holds[i][0],100,false)
		for step in 40:
			StandIn.animate(actor,1.0/60,Vector3.ZERO,holds[i][2],0,0,holds[i][1],false,0,true)
	if NetworkManager.args.has("closeup-solo"):
		await _solo_sheet(dir, camera, lamp, center, actors)
		return
	camera.position = center + Vector3(0,1.4,3.3)
	lamp.position = center + Vector3(0,2.6,2.5)
	camera.look_at(center+Vector3.UP*1.05)
	var tight := NetworkManager.args.has("closeup-tight")
	for view in [["front",PI],["front34",PI+.7],["side",PI+PI/2],["back34",.7],["back",0.0]]:
		for actor in actors:
			actor.rotation.y = view[1]
		if not tight:
			await save_view(dir,"closeup_"+view[0])
			continue
		# Three operators per frame, for hand and shoulder detail.
		camera.fov = 30
		for half in 2:
			var mid := center + Vector3((half*3-1.5)*.8,0,0)
			camera.position = mid + Vector3(0,1.4,3.3)
			camera.look_at(mid+Vector3.UP*1.2)
			await save_view(dir,"tight_%s_%d" % [view[0],half])

## One operator per tile, centred, so perspective does not skew the hold: rows are holds, columns are views.
func _solo_sheet(dir: String, camera: Camera3D, lamp: OmniLight3D, center: Vector3, actors: Array[Node3D]) -> void:
	var views := [PI, PI+.7, PI+PI/2, .7, 0.0, PI-PI/2]
	var tw := 300
	var th := 380
	var sheet := Image.create(tw*views.size(), th*actors.size(), false, Image.FORMAT_RGB8)
	camera.fov = 34
	for i in actors.size():
		for a in actors:
			a.visible = a == actors[i]
		var spot := actors[i].position
		camera.position = spot + Vector3(0,1.3,3.0)
		camera.look_at(spot+Vector3.UP*1.15)
		lamp.position = spot + Vector3(.6,2.6,2.4)
		for v in views.size():
			actors[i].rotation.y = views[v]
			await wait_frames(6)
			var img := g.get_viewport().get_texture().get_image()
			var w := img.get_height()*tw/th
			var tile := img.get_region(Rect2i((img.get_width()-w)/2, 0, w, img.get_height()))
			tile.convert(Image.FORMAT_RGB8)
			tile.resize(tw, th)
			sheet.blit_rect(tile, Rect2i(0,0,tw,th), Vector2i(v*tw, i*th))
	print("CAPTURE solo ", sheet.save_jpg(dir.path_join("solo_sheet.jpg"), .88))
