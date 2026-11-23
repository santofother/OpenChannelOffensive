extends Node
var g: Node3D
var out: String

func start(scene: Node3D) -> void:
	g = scene
	out = String(NetworkManager.args["capture-feedback"])
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func frames(n: int = 20) -> void:
	for i in n:
		await RenderingServer.frame_post_draw

func snap(label: String) -> void:
	await frames()
	g.get_viewport().get_texture().get_image().save_png(out.path_join(label + ".png"))
	print("CAPTURE ", label)

func key_b() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	key = InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = false
	Input.parse_input_event(key)
	await frames(2)

func _run() -> void:
	await frames(60)
	g.net.set_physics_process(false)
	g.player.scripted = true
	g.loadout.bot = true
	var r: RoundRules = g.net.loop.rules
	r.phase = RoundRules.Phase.PREP
	r.round_number = 2
	r.attack_team = 0
	r.deadline = g.net.tick + 1800
	r.carrier = 1
	r.bomb_pos = g.player.global_position
	g.loadout.armor = 67
	g.loadout.helmet = true
	g.net.loop.credits = 4700
	await frames()
	await snap("buy_armor")
	await key_b()
	if g.net.loop.menu.is_open:
		push_error("B did not close menu")
	await key_b()
	if not g.net.loop.menu.is_open:
		push_error("B did not reopen menu")
	print("PASS B closes and reopens the buy menu")
	g.net.loop.menu.close()
	r.phase = RoundRules.Phase.LIVE
	g.player.teleport(g.layout.world(26.5, 7, .05), 0)
	r.carrier = 0
	r.bomb_pos = g.layout.world(26.5, 5.8, .05)
	g.net.voice.stolen[1] = 1
	await snap("bomb_dropped")
	r.phase = RoundRules.Phase.RESOLUTION
	r.scores = [2, 1]
	r.winner = 0
	r.reason = "Bomb defused"
	g.net.loop.round_mvp = {"name":"Player · 2 kills / 180 damage"}
	await snap("round_over_mvp")
	r.phase = RoundRules.Phase.LIVE
	g.loadout.set_gear("marksman", "p9")
	g.loadout.select(Loadout.Tool.RIFLE)
	g.loadout.aiming = true
	g.player.camera.fov = g.loadout.ads_fov()
	await snap("scope_4x")
	g.loadout.aiming = false
	g.player.camera.fov = g.player.fov
	r.phase = RoundRules.Phase.LIVE
	g.loadout.set_gear("service_rifle", "p9")
	g.loadout.select(Loadout.Tool.RIFLE)
	var wall: WallModule = g.modules[0]
	g.player.teleport(Vector3(wall.position.x, .05, wall.position.z - 1.3), 180)
	for point in [Vector3(-.2, 1.0, 0), Vector3(.1, 1.4, 0), Vector3(-.1, 1.7, 0)]:
		wall.impact(Vector3(wall.position.x + point.x, point.y, wall.position.z), 45, true)
	wall.impact(Vector3(wall.position.x + .5, 1.6, wall.position.z), 34)
	await snap("localized_wall_damage")
	# Top-down revised geometry without roofs for review.
	for layer in g.find_children("*", "CanvasLayer", true, false):
		layer.visible = false
	g.loadout.viewmodel.hide()
	for roof: Node3D in g.roofs:
		roof.hide()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 47
	camera.position = g.layout.world(16, 17, 50)
	camera.rotation_degrees.x = -90
	g.add_child(camera)
	camera.make_current()
	await snap("layout_topdown_v2")
	print("CAPTURE_OK feedback")
	get_tree().quit()
