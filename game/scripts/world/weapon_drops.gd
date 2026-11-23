class_name WeaponDrops
extends Node3D
## Host-owned floor loot. Guns swap by interaction, while consumables are collected on foot.

const REACH := 2.2
const WALKOVER_RADIUS := .43
var net: NetMatch
var drops := {}
var _nodes := {}
var _next_id := 0


func drop_player(s: NetMatch.Slot, from: Vector3) -> void:
	for slot in [Loadout.Tool.RIFLE, Loadout.Tool.SIDEARM]:
		var gun := s.lo.gun_inventory(slot)
		if gun.is_empty():
			continue
		var offset := Vector3.RIGHT * (-.55 if slot == Loadout.Tool.RIFLE else .55)
		_add({"gun": gun.id, "ammo": gun.ammo}, drop_position(from, offset, s.last_ground, .07))
	for i in ShopCatalog.DROP_UTILITY.size() + 1:
		var item: String = "defuse_kit" if i == ShopCatalog.DROP_UTILITY.size() else ShopCatalog.DROP_UTILITY[i]
		var count := ShopCatalog.owned(s.lo, item)
		if count == 0:
			continue
		var offset := Vector3.FORWARD.rotated(Vector3.UP, (i + .5) * TAU / 9.0) * .87
		_add({"item": item, "count": count}, drop_position(from, offset, s.last_ground, .07))
		match item:
			"defuse_kit": s.lo.defuse_kit = false
			"zip_tie": s.lo.zip_ties = 0
			_: s.lo.charges[Loadout.key_tool(item)] = 0
	_publish()


func drop_position(from: Vector3, offset: Vector3, fallback: Vector3, height: float) -> Vector3:
	var pos := fallback
	var occupied: Array = drops.values()
	occupied.append_array(net.voice.pickups.values())
	var origin := from + Vector3.UP * .25
	var floor_hit := _floor(from)
	var base := float(floor_hit.position.y) if not floor_hit.is_empty() else from.y
	if not floor_hit.is_empty():
		pos = floor_hit.position
	var best_spacing := -1.0
	for i in 8:
		var candidate := from + offset.rotated(Vector3.UP, i * TAU / 8.0)
		var hit := _floor(candidate)
		if hit.is_empty() or absf(float(hit.position.y) - base) > .32 \
				or GameAudio.blocked(get_world_3d(), origin, candidate + Vector3.UP * .25):
			continue
		var point: Vector3 = hit.position
		var spacing := INF
		for row: Dictionary in occupied:
			spacing = minf(spacing, point.distance_squared_to(row.pos))
		if spacing > best_spacing:
			best_spacing = spacing
			pos = point
		if spacing >= .34 * .34:
			break
	return pos + Vector3.UP * height


func _floor(from: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from + Vector3.UP * .12, from + Vector3.DOWN * 12.0, 1))


func _add(row: Dictionary, pos: Vector3) -> void:
	_next_id += 1
	row.pos = pos
	drops[_next_id] = row


func target(player: Player) -> int:
	var best := 0
	var best_dot := .86
	for id: int in drops:
		var row: Dictionary = drops[id]
		if not row.has("gun"):
			continue
		var alignment := aim_at(player, row.pos, REACH)
		if alignment > best_dot:
			best_dot = alignment
			best = id
	return best


func aim_at(player: Player, point: Vector3, reach: float) -> float:
	if player.global_position.distance_squared_to(point) > reach * reach:
		return -1.0
	var eye := player.camera.global_position
	var alignment := (-player.camera.global_basis.z).dot(eye.direction_to(point))
	if alignment < .86 or GameAudio.blocked(get_world_3d(), eye, point):
		return -1.0
	return alignment


func clear() -> void:
	receive({})
	_next_id = 0


func receive(state: Dictionary) -> void:
	drops = state
	for id: int in _nodes.keys():
		if not state.has(id):
			(_nodes[id] as Node3D).free()
			_nodes.erase(id)
	for id: int in state:
		if _nodes.has(id):
			continue
		var row: Dictionary = state[id]
		var gun: String = row.get("gun", "")
		var root := Node3D.new()
		add_child(root)
		root.global_position = row.pos
		var model: Node3D
		if not gun.is_empty():
			model = GearModels.instance("weapons/" + gun + "_w")
		elif row.item in ["frag", "flash", "smoke", "incendiary"]:
			model = GearModels.instance("grenades/" + row.item + "_w")
		elif row.item in ["medkit", "ordinary", "heavy"]:
			model = GearModels.instance("gear/" + row.item + "_w")
		if model == null:
			var fallback := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(.14, .08, .6 * Weapons.DEFS[gun].look) if not gun.is_empty() else Vector3(.16, .06, .21)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(.2, .8, .75) if row.get("item") == "defuse_kit" else Color(.62, .7, .74)
			box.material = mat
			fallback.mesh = box
			model = fallback
		model.rotation.z = PI * .5 if not gun.is_empty() else 0.0
		root.add_child(model)
		var prompt := Label3D.new()
		prompt.name = "Prompt"
		prompt.position.y = .26
		prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		prompt.pixel_size = .003
		prompt.visible = false
		root.add_child(prompt)
		_nodes[id] = root


func _process(_delta: float) -> void:
	var utility := 0
	if net.local_alive() and net.interaction.is_empty() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var best_dot := .97
		for id: int in drops:
			var row: Dictionary = drops[id]
			if not row.has("item"):
				continue
			var alignment := aim_at(net.g.player, row.pos, 1.8)
			if alignment > best_dot:
				best_dot = alignment
				utility = id
	for id: int in _nodes:
		var row: Dictionary = drops[id]
		var prompt: Label3D = _nodes[id].get_node("Prompt")
		prompt.visible = id == utility or net.interaction == [NetMatch.Interact.GUN, id]
		if prompt.visible:
			prompt.text = "%s ×%d" % [ShopCatalog.find(row.item).name, row.count] if id == utility \
				else "%s · Pick up %s" % [Keys.key("interact"), Weapons.DEFS[row.gun].name]


## Called after NetMatch validates the interactor and the aimed target on the host.
func take(s: NetMatch.Slot, drop_id: int) -> void:
	var row: Dictionary = drops[drop_id]
	var slot := Loadout.Tool.RIFLE if int(Weapons.DEFS[row.gun].slot) == 0 else Loadout.Tool.SIDEARM
	var old := s.lo.gun_inventory(slot)
	drops.erase(drop_id)
	if not old.is_empty():
		_add({"gun": old.id, "ammo": old.ammo}, row.pos)
	s.lo.equip_looted_gun(row.gun, row.ammo)
	if s.id in net.ready_peers:
		net._send(s.id, net._rel(NetMatch.Msg.EVENT,
			[NetMatch.Ev.LOOT_EQUIPPED, net.round_id, net.tick, row.gun, row.ammo]), true)
	_publish()


func host_tick() -> void:
	if not net.loop.accepts_combat() or drops.is_empty():
		return
	var changed := false
	for s: NetMatch.Slot in net.slots.values():
		if not s.alive:
			continue
		var collected := PackedStringArray()
		for id: int in drops.keys():
			var row: Dictionary = drops[id]
			if not row.has("item") or s.node.global_position.distance_squared_to(row.pos) > WALKOVER_RADIUS * WALKOVER_RADIUS:
				continue
			var item: String = row.item
			if item == "defuse_kit" and s.team == net.loop.rules.attack_team:
				continue
			var take_count := mini(int(row.count), net.loop.econ.limit(item) - ShopCatalog.owned(s.lo, item))
			if take_count <= 0 or GameAudio.blocked(get_world_3d(), s.node.global_position + Vector3.UP * .2, row.pos):
				continue
			for i in take_count:
				ShopCatalog.grant(s.lo, item)
			row.count -= take_count
			if row.count == 0:
				drops.erase(id)
			collected.append(ShopCatalog.find(item).name + (" ×%d" % take_count if take_count > 1 else ""))
			changed = true
		if not collected.is_empty():
			net.tell_player(s.id, "Picked up " + ", ".join(collected))
	if changed:
		_publish()


func _publish() -> void:
	receive(drops)
	net._broadcast(net._rel(NetMatch.Msg.EVENT, [NetMatch.Ev.WEAPON_DROPS, net.round_id, drops]), true)
