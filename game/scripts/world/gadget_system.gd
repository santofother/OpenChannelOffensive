class_name GadgetSystem
extends Node3D
## Host-clock grenade simulation. Client copies are presentation only; never deal damage.
const CAP := 12
const ZONE_CAP := 6
const FUSE := 2.5
var g: Node3D
var net: NetMatch
var projectiles: Array = []
var zones: Array = []
var flashes := {}
var serial := 0
var visuals := {}
var equipment := {}
var debug_rows: Array = []
var overlay: ColorRect
var overlay_mat: ShaderMaterial
var mute_filter: AudioEffectLowPassFilter
var mute_gain: AudioEffectAmplify
var bursts: Array = []
var state_tick := -1
var fire_tick := 0.0

func setup(world: Node3D) -> void:
	g = world
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float blind = 0.0; uniform bool nvg = false;
void fragment() { vec3 c = texture(screen_texture, SCREEN_UV).rgb;
if(nvg) { float l = dot(c, vec3(.299,.587,.114)); c = vec3(.08,.95,.19) * clamp(l*3.0+.08,0.0,1.0); }
COLOR = vec4(mix(c,vec3(1.0),blind),1.0); }
"""
	overlay_mat = ShaderMaterial.new()
	overlay_mat.shader = shader
	overlay.material = overlay_mat
	mute_filter = AudioEffectLowPassFilter.new()
	mute_filter.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, mute_filter, 0)
	mute_gain = AudioEffectAmplify.new()
	AudioServer.add_bus_effect(0, mute_gain, 1)

func _exit_tree() -> void:
	for i in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
		if AudioServer.get_bus_effect(0, i) in [mute_filter, mute_gain]:
			AudioServer.remove_bus_effect(0, i)

func clear() -> void:
	for burst: Dictionary in bursts:
		burst.node.free()
	bursts.clear()
	projectiles.clear()
	zones.clear()
	flashes.clear()
	state_tick = -1
	for n: Node in visuals.values():
		n.free()
	visuals.clear()
	for n: Node in equipment.values():
		n.free()
	equipment.clear()

func throw_grenade(lo: Loadout) -> bool:
	if net and (not net.is_host or not net.slots[lo.owner_id].alive or not net.loop.accepts_combat()):
		return false
	if projectiles.size() >= CAP:
		return false
	var cam := lo.player.camera.global_transform
	var dir := -cam.basis.z
	# Start at the eye; sweep the launch offset so a close wall cannot be bypassed.
	var hit := _ray(cam.origin, cam.origin + dir * .35)
	var start: Vector3 = hit.position + hit.normal * .06 if not hit.is_empty() else cam.origin + dir * .35
	serial += 1
	projectiles.append({"id": serial, "kind": Loadout.tool_key(lo.tool), "owner": lo.owner_id,
		"pos": start, "vel": dir * 10.0 + Vector3.UP * 2.0, "left": FUSE, "bounces": 0, "rewarded": false})
	return true

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	if a.distance_squared_to(b) < .000001:
		return {}
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))

static func falloff(distance: float, radius: float) -> float:
	return clampf(1.0 - distance / radius, 0.0, 1.0)

static func blindness(distance: float, facing: float, nvg: bool) -> float:
	return clampf(falloff(distance, 12.0) * lerpf(.2, 1.0, clampf((facing + 1.0) * .5, 0.0, 1.0)) * (1.5 if nvg else 1.0), 0.0, 1.0)

func transmission(a: Vector3, b: Vector3, penetrate: bool = false) -> float:
	var hit := _ray(a, b)
	if hit.is_empty():
		return 1.0
	if penetrate and hit.collider is WallModule and hit.collider.material == WallModule.Mat.ORDINARY:
		# A second query excluding this panel must also be clear (no blast through two walls).
		var q := PhysicsRayQueryParameters3D.create(a, b, 1, [hit.collider.get_rid()])
		return .35 if get_world_3d().direct_space_state.intersect_ray(q).is_empty() else 0.0
	return 0.0

func host_tick(dt: float) -> void:
	for id in flashes.keys():
		flashes[id] = maxf(0.0, float(flashes[id]) - dt / 4.0)
	for p: Dictionary in projectiles.duplicate():
		p.left -= dt
		if p.bounces < 8:
			p.vel += Vector3.DOWN * 9.8 * dt
			var next: Vector3 = p.pos + p.vel * dt
			var hit := _ray(p.pos, next)
			if hit.is_empty():
				p.pos = next
			else:
				p.pos = hit.position + hit.normal * .045
				p.vel = (p.vel as Vector3).bounce(hit.normal) * .45
				p.bounces += 1
		if p.left <= 0.0:
			_detonate(p)
			projectiles.erase(p)
	fire_tick += dt
	var burn := fire_tick >= .25
	if burn:
		fire_tick = 0.0
	for z: Dictionary in zones.duplicate():
		z.left -= dt
		if z.left <= 0.0:
			zones.erase(z)
		elif burn and z.kind == "smoke" and not z.get("rewarded", false):
			_score_smoke(z)
		elif z.kind == "incendiary" and burn:
			for v: Dictionary in victims():
				var d: float = v.pos.distance_to(z.pos)
				if d < 3.0 and transmission(z.pos + Vector3.UP * .15, v.pos) > 0:
					_score_effect(z, v.id)
					damage(v.id, 22.0 * .25, z.owner)

func victims() -> Array:
	var out := []
	if net:
		for s: NetMatch.Slot in net.slots.values():
			if s.alive:
				out.append({"id": s.id, "pos": s.node.global_position + Vector3.UP * .9,
					"eye": s.node.camera.global_position, "forward": -s.node.camera.global_basis.z, "nvg": bool(s.lo.gadgets_on & 4)})
	else:
		out.append({"id": 1, "pos": g.player.global_position + Vector3.UP * .9, "eye": g.player.camera.global_position,
			"forward": -g.player.camera.global_basis.z, "nvg": bool(g.loadout.gadgets_on & 4)})
	return out

func damage(id: int, amount: float, owner_id: int) -> void:
	if net:
		net._on_player_hit(id, amount, owner_id)

func _can_see_effect(viewer: int, owner: int) -> bool:
	if not net:
		return true
	if net.is_host:
		var recipient: NetMatch.Slot = net.slots.get(viewer)
		var source: NetMatch.Slot = net.slots.get(owner)
		return recipient != null and (recipient.alive or (source != null and source.team == recipient.team))
	if net.local_alive() or owner == net.my_id:
		return true
	var remote: NetMatch.Remote = net.remotes.get(owner)
	return remote != null and remote.team == net.my_team


func _score_effect(entry: Dictionary, victim: int) -> void:
	if not net or entry.get("rewarded", false) or not net.slots.has(entry.owner) or not net.slots.has(victim):
		return
	if not net.loop.accepts_combat() or net.slots[entry.owner].team == net.slots[victim].team:
		return
	entry.rewarded = true
	net.loop.performance.award(entry.owner, net.loop.rules.tuning.points_tactical)


func blocks_vision(eye: Vector3, target: Vector3) -> bool:
	for zone: Dictionary in zones:
		if zone.kind != "smoke" or float(zone.duration) - float(zone.left) < 0.65:
			continue
		var center: Vector3 = zone.pos + Vector3.UP * 1.25
		var nearest := Geometry3D.get_closest_point_to_segment(center, eye, target)
		if nearest.distance_squared_to(center) < 1.85 * 1.85:
			return true
	return false


func _score_smoke(zone: Dictionary) -> void:
	if not net or not net.slots.has(zone.owner):
		return
	var center: Vector3 = zone.pos + Vector3.UP * 1.15
	var players := victims()
	var team: int = net.slots[zone.owner].team
	for ally: Dictionary in players:
		if net.slots[ally.id].team != team:
			continue
		for opponent: Dictionary in players:
			if net.slots[opponent.id].team == team:
				continue
			var closest := Geometry3D.get_closest_point_to_segment(center, ally.eye, opponent.eye)
			if closest.distance_squared_to(center) <= 2.0 * 2.0 and transmission(ally.eye, opponent.eye) > 0.0:
				_score_effect(zone, opponent.id)
				return


func _detonate(p: Dictionary) -> void:
	if _can_see_effect(net.my_id if net else 1, p.owner):
		show_burst(p.kind, p.pos)
	if net:
		for peer: int in net.ready_peers:
			if _can_see_effect(peer, p.owner):
				net._send(peer, net._rel(NetMatch.Msg.EVENT, [NetMatch.Ev.GADGET_BURST, net.round_id, p.kind, p.pos]), true)
	if p.kind in ["smoke", "incendiary"]:
		if zones.size() >= ZONE_CAP:
			zones.pop_front()
		var ground := _ray(p.pos, p.pos + Vector3.DOWN * 3.0)
		zones.append({"id": p.id, "kind": p.kind, "owner": p.owner,
			"pos": ground.position + Vector3.UP * .05 if not ground.is_empty() else p.pos,
			"duration": 15.0 if p.kind == "smoke" else 7.0,
			"left": 15.0 if p.kind == "smoke" else 7.0, "rewarded": false})
	if p.kind == "frag" and g.doors:
		g.doors.blast(p.pos, 2.0)
	for v: Dictionary in victims():
		var d: float = v.eye.distance_to(p.pos)
		if p.kind == "frag":
			var amount := 120.0 * falloff(d, 6.0) * transmission(p.pos, v.pos, true)
			if amount > 0.0:
				_score_effect(p, v.id)
				damage(v.id, amount, p.owner)
		elif p.kind == "flash" and transmission(p.pos, v.eye) > 0.0:
			var f: float = (v.forward as Vector3).dot((p.pos - v.eye).normalized())
			var amount := blindness(d, f, v.nvg)
			flashes[v.id] = maxf(float(flashes.get(v.id, 0.0)), amount)
			if amount >= .25:
				_score_effect(p, v.id)

func state(viewer: int) -> Dictionary:
	var alive: bool = not net or (net.slots.has(viewer) and net.slots[viewer].alive)
	var kit := []
	if net:
		for s: NetMatch.Slot in net.slots.values():
			if s.id == viewer or (s.alive and _can_see_effect(viewer, s.id)):
				kit.append([s.id, s.node.camera.global_position, -s.node.camera.global_basis.z,
					s.lo.gadgets_owned, s.lo.gadgets_on if s.alive else 0,
					[s.lo.charges[6], s.lo.charges[7], s.lo.charges[8], s.lo.charges[9]],
					s.lo.primary, s.lo.secondary, s.lo.armor, s.lo.helmet, s.lo.tool, s.lo.zip_ties, s.lo.defuse_kit])
	var visible_projectiles := projectiles.filter(func(p: Dictionary) -> bool: return _can_see_effect(viewer, p.owner))
	var visible_zones := zones.filter(func(z: Dictionary) -> bool: return _can_see_effect(viewer, z.owner))
	return {"p": visible_projectiles.duplicate(true), "z": visible_zones.duplicate(true),
		"flash": float(flashes.get(viewer, 0.0)) if alive else 0.0, "kit": kit}

func receive(d: Dictionary, at_tick: int) -> void:
	if at_tick < state_tick:
		return
	state_tick = at_tick
	projectiles = d.p
	zones = d.z
	flashes[net.my_id] = d.flash
	for row: Array in d.kit:
		if int(row[0]) == net.my_id:
			g.loadout.gadgets_owned = int(row[3])
			# Keep local toggle prediction; host owns ownership and effect.
			g.loadout.gadgets_on &= g.loadout.gadgets_owned
			for i in 4:
				g.loadout.charges[6 + i] = int(row[5][i])
			if row.size() > 11:
				g.loadout.zip_ties = int(row[11])
				g.loadout.defuse_kit = bool(row[12])
	_render_equipment(d.kit)

func _physics_process(delta: float) -> void:
	if not net:
		host_tick(delta)

func _process(delta: float) -> void:
	if not g:
		return
	var id: int = net.my_id if net else 1
	var alive: bool = not net or (net.slots[1].alive if net.is_host else net.my_alive)
	var blind := float(flashes.get(id, 0.0)) if alive else 0.0
	if net and not net.is_host:
		flashes[id] = maxf(0.0, blind - delta / 4.0)
	var nvg := alive and bool(g.loadout.gadgets_on & 4)
	overlay.visible = blind > .001 or nvg
	overlay_mat.set_shader_parameter("blind", blind)
	overlay_mat.set_shader_parameter("nvg", nvg)
	mute_filter.cutoff_hz = lerpf(20000.0, 350.0, blind)
	mute_gain.volume_db = -24.0 * blind
	for burst: Dictionary in bursts.duplicate():
		burst.left -= delta
		var light: OmniLight3D = burst.node
		light.light_energy = 4.0 * smoothstep(0.0, .14, burst.left)
		if burst.left <= 0.0:
			burst.node.free()
			bursts.erase(burst)
	_render_effects(delta, id)
	if net and net.is_host:
		_render_equipment(state(1).kit)
	elif not net:
		_render_equipment([[1, g.player.camera.global_position, -g.player.camera.global_basis.z,
			g.loadout.gadgets_owned, g.loadout.gadgets_on, [], g.loadout.primary, g.loadout.secondary, g.loadout.armor, g.loadout.helmet, g.loadout.tool]] + debug_rows)

func _render_effects(delta: float, viewer: int) -> void:
	var seen := {}
	for entry: Dictionary in projectiles + zones:
		if not _can_see_effect(viewer, entry.owner):
			continue
		var zone := not entry.has("vel")
		var key := "%d_%s" % [entry.id, "zone" if zone else "thrown"]
		seen[key] = true
		if not visuals.has(key):
			var node := _zone_visual(entry.kind) if zone else GearModels.instance("grenades/" + entry.kind + "_w")
			if node == null:
				node = _effect_lobe(.055, Color(.22, .25, .24))
			add_child(node)
			node.global_position = entry.pos
			visuals[key] = node
		var vis: Node3D = visuals[key]
		vis.global_position = vis.global_position.lerp(entry.pos, minf(1.0, delta * 20.0))
		if zone:
			var age := float(entry.get("duration", 15.0 if entry.kind == "smoke" else 7.0)) - float(entry.left)
			var size_curve := smoothstep(0.0, 1.45 if entry.kind == "smoke" else .5, age)
			vis.scale = Vector3.ONE * maxf(.03, size_curve * smoothstep(0.0, 1.15, entry.left))
			for i in vis.get_child_count():
				var lobe: Node3D = vis.get_child(i)
				lobe.position.y = float(lobe.get_meta("height")) + sin(age * 2.6 + i * 1.9) * .16
				lobe.scale.y = 1.0 + sin(age * 5.0 + i) * .12
		else:
			var motion: Vector3 = entry.vel
			vis.rotate_x(delta * minf(motion.length(), 12.0))
			vis.rotate_z(delta * 4.0)
	for key in visuals.keys():
		if not seen.has(key):
			visuals[key].free()
			visuals.erase(key)


func _zone_visual(kind: String) -> Node3D:
	var root := Node3D.new()
	var smoke := kind == "smoke"
	var count := 9 if smoke else 12
	for i in count:
		var opacity := .86 if smoke else .77
		var tint := Color(.32, .35, .36, opacity) if smoke else Color(1.0, .30 + (i % 4) * .12, .035, opacity)
		var lobe := _effect_lobe((1.08 + (i % 3) * .18) if smoke else (.24 + (i % 3) * .1), tint, not smoke)
		var radius := (1.12 if smoke else 2.25) * sqrt(float(i) / (count - 1))
		var angle := i * 2.4
		var height := (1.03 if smoke else .20) + (i % 3) * .18
		lobe.position = Vector3(cos(angle) * radius, height, sin(angle) * radius)
		lobe.set_meta("height", height)
		if not smoke:
			lobe.scale.x = .65
			lobe.scale.z = .65
		root.add_child(lobe)
	return root


func _effect_lobe(radius: float, tint: Color, emissive := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	if tint.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		mat.emission_enabled = true
		mat.emission = tint
	mesh.material_override = mat
	return mesh


func _render_equipment(rows: Array) -> void:
	var seen := {}
	for row: Array in rows:
		var id := int(row[0])
		if net and not net.is_host and not net.my_alive and (not net.remotes.has(id) or net.remotes[id].team != net.my_team):
			continue
		seen[id] = true
		var bits := int(row[4])
		if not equipment.has(id):
			var root := Node3D.new()
			add_child(root)
			var light := SpotLight3D.new()
			light.name = "Light"
			light.spot_range = 18.0
			light.spot_angle = 30.0
			light.light_energy = 2.0
			root.add_child(light)
			var dot := MeshInstance3D.new()
			dot.name = "Dot"
			var sphere := SphereMesh.new()
			sphere.radius = .025
			sphere.height = .05
			dot.mesh = sphere
			dot.material_override = GearModels.material("led_red")
			root.add_child(dot)
			equipment[id] = root
		var root: Node3D = equipment[id]
		root.global_position = row[1]
		root.look_at(row[1] + row[2], Vector3.UP)
		root.get_node("Light").visible = bits & 1 != 0
		var hit := _ray(row[1], row[1] + row[2] * 40.0)
		var dot: MeshInstance3D = root.get_node("Dot")
		dot.visible = bits & 2 != 0 and not hit.is_empty()
		if dot.visible:
			dot.global_position = hit.position + hit.normal * .02
		if net:
			var body: Node3D = null
			if net.is_host and net.slots.has(id):
				body = net.slots[id].body_vis
			elif net.remotes.has(id):
				body = net.remotes[id].vis
			if body:
				var weapon := ""
				if int(row[10]) == Loadout.Tool.RIFLE:
					weapon = row[6]
				elif int(row[10]) == Loadout.Tool.SIDEARM:
					weapon = row[7]
				StandIn.equip(body, weapon, int(row[8]), bool(row[9]), int(row[3]), bits)
	for id in equipment.keys():
		if not seen.has(id):
			equipment[id].free()
			equipment.erase(id)


func show_burst(kind: String, pos: Vector3) -> void:
	if bursts.size() >= 6:
		var oldest: Dictionary = bursts.pop_front()
		oldest.node.free()
	var light := OmniLight3D.new()
	light.omni_range = 7.0 if kind == "flash" else 4.0
	light.light_energy = 2.5
	light.light_color = Color.WHITE if kind == "flash" else Color(1, .4, .08)
	add_child(light)
	light.global_position = pos
	bursts.append({"node": light, "left": .15})
	ProcAudio.play(self, {"frag": "boom", "incendiary": "fire_burst", "smoke": "smoke_burst", "flash": "flash_burst"}.get(kind, "boom"), pos)
