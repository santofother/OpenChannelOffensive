class_name DoorSystem
extends Node
## Hinged, creaky doors in every doorway of maps that provide door specs (Lightwell). Host-authoritative:
## clients send requests (use / kick / zip-tie) and adopt the host's door states; no client prediction.
##
## Rules (proposals, exposed below):
## - F (interact) opens/closes when no bomb action applies. Doors swing away from the user.
## - X (hold ZIP_TIME) zip-ties a closed door shut; costs one zip tie. A locked door only rattles when used.
## - Shooting the handle (either face) snaps the zip tie and the latch: the door swings ajar, unlocked.
## - V (melee) kicks: an unlocked closed door bursts open; a locked door breaks off its hinges after
##   KICKS_TO_BREAK kicks.
## - Breach charges and frag grenades blow nearby doors off their hinges. A charge aimed at a door is placed on
##   the frame (header cell) above it.
## Closed doors block movement, bullets lose some damage through them, and they occlude voice like walls.
## The doorway clears as the solid leaf swings. A broken leaf has no collision.

enum Act { USE, KICK, ZIP }

const LEAF_HEIGHT := 2.05
const LEAF_THICKNESS := 0.045
const OPEN_ANGLE := PI * .5 ## radians from closed
const AJAR_ANGLE := 0.45
const REACH := 2.1 ## metres from the eye to the doorway centre
const KICK_REACH := 1.7
const ZIP_TIME := 1.0
const KICKS_TO_BREAK := 4
const PEN_MULT := 0.75 ## bullets through a closed door keep 75% damage
const HANDLE_ALONG := 0.12 ## handle distance from the latch edge
const HANDLE_Y := 1.0
const HANDLE_HIT := 0.12 ## hit tolerance around the handle
const COOLDOWN_MS := 450

var g: Node3D
var net: NetMatch
var doors: Array[Door] = []
var _last_act := {} ## player id -> msec of the last accepted action
var _zip_held := 0.0
var _zip_sent := false
var _wood: StandardMaterial3D
var _metal: StandardMaterial3D
var _tie: StandardMaterial3D
var _prompt: Label
var _prompt_in := 0.0


class Door:
	var id := 0
	var hinge := Vector3.ZERO ## floor point on the hinge jamb, centre of the wall thickness
	var along := Vector3.RIGHT ## from hinge to latch, closed
	var normal := Vector3.FORWARD ## wall normal
	var width := 1.4
	var header := "" ## WallModule id of the cell above the doorway
	var angle := 0.0 ## current swing, radians
	var target := 0.0 ## 0 closed, ±OPEN_ANGLE open, ±AJAR_ANGLE ajar
	var locked := false
	var broken := false
	var handle := true
	var kicks := 0
	var revision := 0
	var speed := 4.0
	var pivot: Node3D
	var body: AnimatableBody3D
	var handle_nodes: Array[Node3D] = []
	var tie_node: Node3D

	func center(y: float = 1.1) -> Vector3:
		return hinge + along * width * 0.5 + Vector3(0, y, 0)

	func closed() -> bool:
		return target == 0.0 and not broken


func setup(scene: Node3D, specs: Array) -> void:
	g = scene
	name = "Doors"
	add_to_group("door_system")
	_wood = StandardMaterial3D.new()
	_wood.albedo_color = Color(0.36, 0.25, 0.16)
	_wood.roughness = 0.8
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.7, 0.68, 0.62)
	_metal.metallic = 0.8
	_metal.roughness = 0.35
	_tie = StandardMaterial3D.new()
	_tie.albedo_color = Color(0.95, 0.95, 0.92)
	_tie.emission_enabled = true
	_tie.emission = Color(0.4, 0.4, 0.38)
	for i in specs.size():
		_build(i, specs[i])
	var layer := CanvasLayer.new()
	add_child(layer)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 17)
	_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	_prompt.add_theme_constant_override("shadow_offset_x", 2)
	_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -170
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	layer.add_child(_prompt)


func _build(i: int, spec: Dictionary) -> void:
	var d := Door.new()
	d.id = i
	d.hinge = spec.hinge
	d.along = (spec.along as Vector3).normalized()
	d.normal = Vector3.UP.cross(d.along).normalized()
	d.width = float(spec.width)
	d.header = String(spec.get("header", ""))
	var leaf := d.width - 0.04
	d.pivot = Node3D.new()
	d.pivot.name = "Door_%02d" % i
	add_child(d.pivot)
	# Pivot local +X runs along the door (hinge -> latch), +Y up, +Z = -normal (right-handed). A positive
	# rotation about local Y moves the latch toward +normal, matching _away().
	d.pivot.global_transform = Transform3D(Basis(d.along, Vector3.UP, -d.normal), d.hinge)
	d.body = AnimatableBody3D.new()
	d.body.sync_to_physics = false
	d.body.collision_layer = 1
	d.body.collision_mask = 0
	d.body.set_meta("door_id", i)
	d.body.set_meta("pen_mult", PEN_MULT)
	d.body.add_to_group("door_bodies")
	d.pivot.add_child(d.body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(leaf, LEAF_HEIGHT, LEAF_THICKNESS)
	shape.shape = box
	shape.position = Vector3(0.02 + leaf * 0.5, LEAF_HEIGHT * 0.5 + 0.01, 0)
	d.body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	bm.material = _wood
	mesh.mesh = bm
	mesh.position = shape.position
	d.body.add_child(mesh)
	for side in [-1.0, 1.0]:
		var h := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.12, 0.025, 0.035)
		hm.material = _metal
		h.mesh = hm
		h.position = Vector3(d.width - 0.02 - HANDLE_ALONG, HANDLE_Y, side * (LEAF_THICKNESS * 0.5 + 0.03))
		d.body.add_child(h)
		d.handle_nodes.append(h)
	var tie := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.035
	tm.outer_radius = 0.045
	tm.material = _tie
	tie.mesh = tm
	tie.rotation.x = PI * 0.5
	tie.position = Vector3(d.width - 0.02 - HANDLE_ALONG + 0.05, HANDLE_Y, 0)
	tie.visible = false
	d.body.add_child(tie)
	d.tie_node = tie
	doors.append(d)
	_pose(d, true)


## Undo every change (new round / offline restart).
func reset() -> void:
	_last_act.clear()
	for d in doors:
		g.loadout.clear_door_marks(d.body)
		d.angle = 0.0
		d.target = 0.0
		d.locked = false
		d.broken = false
		d.handle = true
		d.kicks = 0
		d.revision = 0
		_pose(d, true)


func _authority() -> bool:
	return net == null or net.is_host


# ---------------------------------------------------------------- input (local player)

func _unhandled_input(event: InputEvent) -> void:
	if doors.is_empty() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo():
		if not net and event.is_action_pressed("interact"):
			_request(Act.USE)
		elif event.is_action_pressed("melee"):
			_request(Act.KICK)


func _physics_process(delta: float) -> void:
	for d in doors:
		if not d.broken and d.angle != d.target:
			d.angle = move_toward(d.angle, d.target, d.speed * delta)
			_pose(d, false)
			if d.angle == 0.0:
				_fx(d, "latch")


func _process(delta: float) -> void:
	if doors.is_empty():
		return
	_prompt_in -= delta
	if net or _prompt_in <= 0.0:
		_prompt_in = 0.15
		_update_prompt()
	# Hold-to-zip: a short local hold, then one request the host validates.
	var holding := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and InputMap.has_action("zip_tie") and Input.is_action_pressed("zip_tie")
	if holding and not _zip_sent:
		if _zip_held == 0.0:
			var lo: Loadout = g.loadout
			if lo.zip_ties <= 0:
				lo.say("No zip ties (buy them in the shop)")
				_zip_sent = true
				return
			lo.say("Zip-tying the door...")
		_zip_held += delta
		if _zip_held >= ZIP_TIME:
			_zip_sent = true
			_request(Act.ZIP)
	elif not holding:
		_zip_held = 0.0
		_zip_sent = false


## Local hint for the door in front of the player (state as last known; the host decides).
func _update_prompt() -> void:
	var cam: Camera3D = g.player.camera
	var d: Door
	if not net:
		d = target_door(cam.global_position, -cam.global_basis.z, REACH, true)
	elif not net.interaction.is_empty() and net.interaction[0] == NetMatch.Interact.DOOR:
		d = doors[net.interaction[1]]
	if d == null or d.broken:
		_prompt.text = ""
		return
	if d.locked:
		_prompt.text = "Zip-tied shut · %s kick (%d/4) · shoot the handle · blow it" % [Keys.key("melee"), d.kicks]
	elif d.target != 0.0:
		_prompt.text = "%s close door · %s kick" % [Keys.key("interact"), Keys.key("melee")]
	else:
		var tie := " · hold %s zip-tie (%d)" % [Keys.key("zip_tie"), g.loadout.zip_ties] if g.loadout.zip_ties > 0 and d.handle else ""
		_prompt.text = "%s open door · %s kick%s" % [Keys.key("interact"), Keys.key("melee"), tie]

func _request(act: int) -> void:
	if _authority():
		_host_act(net.my_id if net else 1, net.round_id if net else 0, act)
	else:
		_act.rpc_id(1, net.round_id, act)


@rpc("any_peer", "call_remote", "reliable", 0)
func _act(r: int, act: int) -> void:
	if net and net.is_host and act in [Act.KICK, Act.ZIP]:
		_host_act(multiplayer.get_remote_sender_id(), r, act)


# ---------------------------------------------------------------- host rules

## {player: Player, lo: Loadout, team: int} for an acting id, or {} when that player may not act now.
func _actor(id: int) -> Dictionary:
	if net == null:
		return {"player": g.player, "lo": g.loadout, "team": 1}
	if not net.slots.has(id):
		return {}
	var s: NetMatch.Slot = net.slots[id]
	if not s.alive:
		return {}
	if net.loop and net.loop.enabled:
		var rules := net.loop.rules
		if rules.phase in [RoundRules.Phase.RESOLUTION, RoundRules.Phase.RESULT]:
			return {}
		if rules.phase == RoundRules.Phase.PREP and s.team == rules.attack_team:
			return {} # attackers are frozen in prep
	return {"player": s.node, "lo": s.lo, "team": s.team}


func use_target(player: Player) -> Door:
	return target_door(player.camera.global_position, -player.camera.global_basis.z, REACH, true)


func _host_act(id: int, r: int, act: int) -> void:
	if not _authority() or (net and r != net.round_id):
		return
	var a := _actor(id)
	if a.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_act.get(id, -10000)) < COOLDOWN_MS:
		return
	var player: Player = a.player
	var d := use_target(player) if act == Act.USE else target_door(player.camera.global_position,
		-player.camera.global_basis.z, KICK_REACH if act == Act.KICK else REACH)
	if d == null:
		if act == Act.KICK:
			var eye := player.camera.global_position
			var hit := g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye - player.camera.global_basis.z * KICK_REACH, 1))
			if not hit.is_empty() and hit.collider is WallModule:
				_last_act[id] = now
				(hit.collider as WallModule).impact(hit.position, 45.0, true)
				ProcAudio.play(g, "kick", hit.position, -6.0)
		if act == Act.ZIP:
			_tell(id, "Aim at a closed door to zip-tie it")
		return
	if act == Act.USE and net and net.loop and net.loop.enabled and net.loop.objective_available(id):
		return # F plants/defuses/recovers first
	_last_act[id] = now
	var lo: Loadout = a.lo
	match act:
		Act.USE:
			if d.broken:
				return
			if d.locked:
				_change(d, "rattle")
				_tell(id, "Zip-tied shut: shoot the handle, kick it (%s) or blow it" % Keys.key("melee"))
			elif d.target == 0.0:
				var sign := _swing_sign(d, player.global_position)
				if sign == 0.0:
					_tell(id, "Blocked")
					return
				d.target = sign * OPEN_ANGLE
				d.speed = 3.2
				_change(d, "creak")
			else:
				if _occupied(d) or _swing_blocked(d, signf(d.angle)):
					_tell(id, "Someone is in the doorway")
					return
				d.target = 0.0
				d.speed = 3.2
				_change(d, "creak")
		Act.KICK:
			kick(d, player.global_position)
		Act.ZIP:
			if d.broken or absf(d.target) >= OPEN_ANGLE:
				_tell(id, "Close the door first")
			elif d.locked:
				_tell(id, "Already zip-tied")
			elif not d.handle:
				_tell(id, "The handle is shot off: nothing to tie")
			elif lo.zip_ties <= 0:
				_tell(id, "No zip ties")
			else:
				lo.zip_ties -= 1
				d.locked = true
				_change(d, "zip")
				_tell(id, "Door zip-tied (%d left)" % lo.zip_ties)


func kick(d: Door, from: Vector3) -> void:
	if d.broken:
		return
	if d.locked:
		d.kicks += 1
		if d.kicks >= KICKS_TO_BREAK:
			d.broken = true
			d.locked = false
			_change(d, "door_break")
		else:
			_change(d, "kick_%d" % d.kicks)
		return
	if d.target == 0.0:
		var sign := _swing_sign(d, from)
		d.target = (sign if sign != 0.0 else 1.0) * OPEN_ANGLE
		d.speed = 12.0
		_change(d, "kick")


## Host: a resolved shot. Handle hits on closed doors snap the latch and any zip tie.
func on_shot(res: Dictionary) -> void:
	if not _authority():
		return
	var surfaces: Array = res.get("impacts", []).duplicate()
	if res.get("hit", false) and res.get("collider") != null:
		surfaces.append({"position": res["position"], "collider": res["collider"]})
	for s: Dictionary in surfaces:
		var col: Variant = s.get("collider")
		if not (col is Node) or not (col as Node).has_meta("door_id"):
			continue
		var d := doors[int((col as Node).get_meta("door_id"))]
		if d.broken or not d.handle:
			continue
		var p: Vector3 = s.position
		var along := (p - d.hinge).dot(d.along)
		if absf(along - (d.width - 0.02 - HANDLE_ALONG)) <= HANDLE_HIT and absf(p.y - d.hinge.y - HANDLE_Y) <= HANDLE_HIT:
			d.handle = false
			d.locked = false
			if d.target == 0.0:
				var origin: Vector3 = res.get("origin", p)
				d.target = _away(d, origin) * AJAR_ANGLE
				d.speed = 5.0
			_change(d, "handle_release")


## Host: explosions within `radius` of a doorway centre blow the door off its hinges.
func blast(pos: Vector3, radius: float) -> void:
	if not _authority():
		return
	for d in doors:
		if not d.broken and d.center(1.0).distance_to(pos) <= radius + d.width * 0.5:
			d.broken = true
			d.locked = false
			_change(d, "door_break")


## Host: bots open the doors they walk into, and kick locked ones.
func host_bots(ids: Array) -> void:
	if not _authority() or net == null:
		return
	for id: int in ids:
		var a := _actor(id)
		if a.is_empty():
			continue
		var pos: Vector3 = (a.player as Player).global_position
		for d in doors:
			if not d.closed() or d.angle != 0.0:
				continue
			var c := d.center(0.0)
			if absf(c.y - pos.y) > .65 or c.distance_to(pos) > .95:
				continue
			var now := Time.get_ticks_msec()
			if now - int(_last_act.get(id, -10000)) < 800:
				continue
			_last_act[id] = now
			if d.locked:
				kick(d, pos)
			else:
				var sign := _swing_sign(d, pos)
				d.target = (sign if sign != 0.0 else -_side(d, pos)) * OPEN_ANGLE
				d.speed = 3.2
				_change(d, "creak")


func _tell(id: int, text: String) -> void:
	if net == null or id == net.my_id:
		(g.loadout as Loadout).say(text)
	elif id in net.ready_peers:
		net._send(id, net._rel(NetMatch.Msg.EVENT, [NetMatch.Ev.REJECT, net.round_id, text]), true)


func _change(d: Door, fx: String) -> void:
	d.revision += 1
	_pose(d, false)
	_fx(d, fx)
	if net and net.is_host:
		net._broadcast(net._rel(NetMatch.Msg.EVENT, [NetMatch.Ev.DOOR, net.round_id, _row(d) + [fx]]), true)


# ---------------------------------------------------------------- geometry

## Door the eye is facing within `reach` (open or closed), with a clear line to the doorway.
func target_door(eye: Vector3, dir: Vector3, reach: float, intact_only := false) -> Door:
	var best: Door = null
	var best_cos := 0.0
	var space := g.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for d in doors:
		if intact_only and d.broken:
			continue
		var c := d.center(clampf(eye.y - d.hinge.y, 0.3, 1.8))
		var v := c - eye
		var dist := v.length()
		if dist > reach or dist < 0.01:
			continue
		var cosv := dir.dot(v / dist)
		var need := 0.55 if dist > 1.0 else 0.2
		if cosv < need or cosv <= best_cos:
			continue
		if ex.is_empty():
			for door in doors:
				ex.append(door.body.get_rid())
		var q := PhysicsRayQueryParameters3D.create(eye, c, 1, ex)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit.position as Vector3).distance_to(c) > 0.25:
			continue
		best = d
		best_cos = cosv
	return best


func _side(d: Door, pos: Vector3) -> float:
	return signf((pos - d.center(0.0)).dot(d.normal)) if (pos - d.center(0.0)).dot(d.normal) != 0.0 else 1.0


## Swing direction (sign of the angle) that moves the latch away from `pos`.
func _away(d: Door, pos: Vector3) -> float:
	var latch_motion := Vector3.UP.cross(d.along) # direction the latch moves for a small positive angle
	return 1.0 if latch_motion.dot(-_side(d, pos) * d.normal) > 0.0 else -1.0


## Opens away from the user unless someone stands in that swing, then toward them; 0 when both are blocked.
func _swing_sign(d: Door, pos: Vector3) -> float:
	var first := _away(d, pos)
	for sign in [first, -first]:
		if not _swing_blocked(d, sign):
			return sign
	return 0.0


func _people() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if net:
		for s: NetMatch.Slot in net.slots.values():
			if s.alive:
				out.append(s.node.global_position)
	else:
		out.append(g.player.global_position)
	return out


## Anyone standing in the solid leaf's swing on that side.
func _swing_blocked(d: Door, sign: float) -> bool:
	var side := d.normal * signf(Vector3.UP.cross(d.along).dot(d.normal) * sign)
	for p in _people():
		var rel := p - d.hinge
		rel.y = 0.0
		if rel.length() < d.width * 0.95 and rel.dot(side) > 0.15 and rel.dot(d.along) > 0.15:
			return true
	return false


## Someone overlapping the closed leaf (closing would trap them inside collision).
func _occupied(d: Door) -> bool:
	for p in _people():
		var rel := p - d.hinge
		rel.y = 0.0
		var t := rel.dot(d.along)
		if t > -0.35 and t < d.width + 0.35 and absf(rel.dot(d.normal)) < 0.45:
			return true
	return false


func _pose(d: Door, snap: bool) -> void:
	if snap:
		d.angle = d.target
	d.tie_node.visible = d.locked and not d.broken
	for h in d.handle_nodes:
		h.visible = d.handle
	if d.broken:
		# Blown or kicked off its hinges: the leaf lies flat on the floor, no collision.
		d.body.collision_layer = 0
		d.body.position = Vector3(0, 0.03, 0.5)
		d.body.rotation = Vector3(-PI * 0.5, 0, 0)
		return
	d.body.position = Vector3.ZERO
	d.body.rotation = Vector3(0, d.angle, 0)
	d.body.collision_layer = 1


func _fx(d: Door, fx: String) -> void:
	if fx == "" or not is_inside_tree():
		return
	var height := HANDLE_Y if fx in ["latch", "zip", "handle_release", "rattle"] else 1.0
	var point := d.center(height)
	if fx in ["latch", "zip", "handle_release", "rattle"]:
		point = d.hinge + d.along * (d.width - HANDLE_ALONG) + Vector3.UP * height
	ProcAudio.play(self, fx, point, -2.0 if fx.begins_with("kick") or fx == "door_break" else -6.0)


# ---------------------------------------------------------------- replication

func _row(d: Door) -> Array:
	return [d.id, d.target, d.locked, d.broken, d.handle, d.revision]


func state() -> Array:
	var out := []
	for d in doors:
		out.append(_row(d))
	return out


## Client: one host door change (with its sound), or a full-state row (no sound, snapped).
func apply(row: Array, animate: bool) -> void:
	var i := int(row[0])
	if i < 0 or i >= doors.size():
		return
	var d := doors[i]
	if int(row[5]) <= d.revision and animate:
		return
	var was_broken := d.broken
	d.target = float(row[1])
	d.locked = bool(row[2])
	d.broken = bool(row[3])
	d.handle = bool(row[4])
	d.revision = int(row[5])
	d.speed = 12.0 if row.size() > 6 and String(row[6]) == "kick" else 3.2
	_pose(d, not animate or (d.broken and not was_broken))
	if animate and row.size() > 6:
		_fx(d, String(row[6]))


func apply_all(rows: Array) -> void:
	for row: Array in rows:
		apply(row, false)


func open_count() -> int:
	return doors.filter(func(d: Door) -> bool: return d.target != 0.0 or d.broken).size()
