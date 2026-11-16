extends Node3D
## M0 bootstrap: plain room, one capsule per rostered player, minimal host/join/leave UI.
## Smoke hooks (headless tests): --smoke-offline, --smoke-host, --smoke-join=<ip>, --expect-reject

var _status: Label
var _roster: Label
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _lobby_list: ItemList
var _lobbies: Array = []
var _capsules: Dictionary = {}
var _smoke_timeout := 20.0


func _ready() -> void:
	_build_room()
	_build_ui()
	NetworkManager.status_changed.connect(_set_status)
	NetworkManager.connection_failed.connect(func(r: String) -> void: _set_status("ERROR: " + r))
	NetworkManager.roster_changed.connect(_refresh_roster)
	SteamManager.status_changed.connect(_set_status)
	SteamManager.lobby_list_updated.connect(_on_lobbies)
	_set_status(SteamManager.init_message)
	_refresh_roster()
	var a := NetworkManager.args
	if a.has("smoke-offline"):
		print("SMOKE_OK offline build=", NetworkManager.build_id, " steam='", SteamManager.init_message, "'")
		get_tree().quit(0)
	elif a.has("smoke-host"):
		NetworkManager.host_enet(int(a.get("port", NetworkManager.DEFAULT_PORT)))
	elif a.has("smoke-join"):
		NetworkManager.join_enet(String(a["smoke-join"]), int(a.get("port", NetworkManager.DEFAULT_PORT)))
		if a.has("expect-reject"):
			NetworkManager.session_ended.connect(func(r: String) -> void:
				print("SMOKE_REJECTED ", r)
				get_tree().quit(0 if "Can't join" in r else 1))
	if a.has("smoke-host") or a.has("smoke-join"):
		NetworkManager.roster_changed.connect(_smoke_check)


func _smoke_check() -> void:
	var a := NetworkManager.args
	var want := int(a.get("want", 2))
	if NetworkManager.player_names.size() >= want and not a.has("expect-reject"):
		print("SMOKE_OK roster=", NetworkManager.player_names)
		get_tree().create_timer(1.0).timeout.connect(func() -> void: get_tree().quit(0))


func _process(delta: float) -> void:
	var a := NetworkManager.args
	if a.has("smoke-host") or a.has("smoke-join"):
		_smoke_timeout -= delta
		if _smoke_timeout <= 0.0:
			print("SMOKE_FAIL timeout roster=", NetworkManager.player_names)
			get_tree().quit(1)


func _build_room() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.1, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	_box(Vector3(12, 0.2, 12), Vector3(0, -0.1, 0), Color(0.35, 0.35, 0.38))
	_box(Vector3(12, 3, 0.2), Vector3(0, 1.5, -6), Color(0.55, 0.5, 0.45))
	_box(Vector3(12, 3, 0.2), Vector3(0, 1.5, 6), Color(0.55, 0.5, 0.45))
	_box(Vector3(0.2, 3, 12), Vector3(-6, 1.5, 0), Color(0.55, 0.5, 0.45))
	_box(Vector3(0.2, 3, 12), Vector3(6, 1.5, 0), Color(0.55, 0.5, 0.45))
	var cam := Camera3D.new()
	cam.position = Vector3(0, 7, 9)
	cam.rotation_degrees = Vector3(-35, 0, 0)
	add_child(cam)


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(340, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Open Channel Offensive — M0 (build %s)" % NetworkManager.build_id
	box.add_child(title)
	_name_edit = LineEdit.new()
	_name_edit.text = NetworkManager.local_name
	_name_edit.placeholder_text = "Your name"
	_name_edit.text_changed.connect(func(t: String) -> void: NetworkManager.local_name = t)
	box.add_child(_name_edit)
	_button(box, "Host (Steam)", func() -> void: SteamManager.host_lobby())
	_button(box, "Refresh Steam lobbies", func() -> void: SteamManager.request_lobby_list())
	_lobby_list = ItemList.new()
	_lobby_list.custom_minimum_size = Vector2(0, 80)
	box.add_child(_lobby_list)
	_button(box, "Join selected lobby", _join_selected)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	box.add_child(_ip_edit)
	_button(box, "Host (ENet local test)", func() -> void: NetworkManager.host_enet())
	_button(box, "Join (ENet local test)", func() -> void: NetworkManager.join_enet(_ip_edit.text))
	_button(box, "Leave", func() -> void: NetworkManager.leave())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_roster = Label.new()
	box.add_child(_roster)


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _join_selected() -> void:
	var sel := _lobby_list.get_selected_items()
	if sel.is_empty():
		_set_status("Select a lobby first.")
		return
	SteamManager.join_lobby(int(_lobbies[sel[0]]["id"]))


func _on_lobbies(lobbies: Array) -> void:
	_lobbies = lobbies
	_lobby_list.clear()
	for l in lobbies:
		_lobby_list.add_item("%s (%d/%d) %s" % [l["name"], l["members"], NetworkManager.MAX_PLAYERS,
			"" if l["build"] == NetworkManager.build_id else "[different build]"])


func _set_status(t: String) -> void:
	if _status:
		_status.text = t
	print("[UI] ", t)


func _refresh_roster() -> void:
	var names: Dictionary = NetworkManager.player_names
	if _roster:
		_roster.text = "Players %d/%d: %s" % [names.size(), NetworkManager.MAX_PLAYERS, ", ".join(names.values())]
	for id in _capsules.keys():
		if not names.has(id):
			_capsules[id].queue_free()
			_capsules.erase(id)
	var i := 0
	for id in names.keys():
		if not _capsules.has(id):
			var mi := MeshInstance3D.new()
			mi.mesh = CapsuleMesh.new()
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color.from_hsv(float(i) / NetworkManager.MAX_PLAYERS, 0.6, 0.9)
			mi.mesh.material = mat
			add_child(mi)
			_capsules[id] = mi
		_capsules[id].position = Vector3(-4 + i * 1.6, 1.0, 0)
		i += 1
