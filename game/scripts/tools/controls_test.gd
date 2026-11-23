extends SceneTree
## Deterministic gameplay checks for spray and collision-safe lean; no presentation required.
var fails := 0

class InteractionWorld extends Node3D:
	var doors: Node

func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		fails += 1

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := InteractionWorld.new()
	root.add_child(world)
	var ps := preload("res://scenes/player.tscn")
	var p: Player = ps.instantiate()
	p.scripted = true
	p.net_driven = true
	world.add_child(p)
	var twin: Player = ps.instantiate()
	twin.scripted = true
	twin.net_driven = true
	world.add_child(twin)
	twin.position.z = 10.0
	var lo := Loadout.new()
	lo.net_driven = true
	world.add_child(lo)
	lo.setup(p, world, WeaponTuning.new(), false)
	lo.use_recoil = true
	var predicted := Loadout.new()
	predicted.net_driven = true
	world.add_child(predicted)
	predicted.setup(twin, world, WeaponTuning.new(), false)
	predicted.authority = false
	predicted.use_recoil = true
	await physics_frame
	var c := NetCmd.new()
	c.tool = Loadout.Tool.INCENDIARY
	c.gadgets = 7
	c.interact = true
	c.vault = true
	c.fire = true
	for side in [-1, 0, 1]:
		c.lean = side
		var q := c.quantised()
		check("lean wire roundtrip %d preserves buttons and gear" % side, q.lean == side and q.tool == c.tool and q.gadgets == 7 and q.fire and q.interact and q.vault)
	check("Q/E lean and F interaction bindings", InputMap.action_get_events("lean_left")[0].physical_keycode == KEY_Q and InputMap.action_get_events("lean_right")[0].physical_keycode == KEY_E and InputMap.action_get_events("interact")[0].physical_keycode == KEY_F)
	var actions := ["lean_left", "lean_right", "interact", "command_regroup", "command_objective", "grenade_cycle"]
	var keys := []
	for action in actions:
		keys.append(InputMap.action_get_events(action)[0].physical_keycode)
	var unique := {}
	for key in keys:
		unique[key] = true
	check("lean, interact/radio, commands and grenade keys are distinct", unique.size() == keys.size())
	check("weapons and radios use the single interaction binding", not InputMap.has_action("pickup_weapon") and not InputMap.has_action("radio_steal"))
	# Rebindable controls: every action comes from ctl.actions(); bindings round-trip; MMB opens comms.
	var ctl: Node = root.get_node("Controls") # autoload names are not compiled into --script tests
	var all_bound := true
	for a: Array in ctl.actions():
		all_bound = all_bound and InputMap.has_action(a[0]) and ctl.current_spec(a[0]) == a[2]
	check("every action is bound to its code default", all_bound)
	check("comms wheel defaults to the middle mouse button", (InputMap.action_get_events("comm_wheel")[0] as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE)
	var round_trip := true
	for spec in ["W", "Shift", "Space", "Enter", "Tab", "F5", "Mouse1", "Mouse3", "Mouse8"]:
		round_trip = round_trip and ctl.spec_of(ctl.parse(spec)) == spec
	check("binding strings round-trip (keys and mouse buttons)", round_trip)
	check("interaction binding has no conflicts", ctl.conflicts("interact").is_empty())
	ctl._set_event("reload", ctl.parse("G"))
	check("rebinding reports a clash with the other user", "Cycle grenades" in ctl.conflicts("reload") and ctl.key("reload") == "G")
	ctl._apply_defaults()
	check("defaults restore", ctl.key("reload") == "R" and ctl.conflicts("reload").is_empty())
	# Do not simulate falling while testing the view geometry.
	p.tuning.gravity = 0.0
	c = NetCmd.new()
	c.lean = 1
	for i in 20:
		p.simulate(c, 1.0 / 60.0)
	check("full right lean shifts eye and rolls camera", p.lean > 0.99 and p.camera.position.is_zero_approx() and p.camera.global_position.x > 0.37 and p.camera.rotation.z < -0.2)
	var hit := Ballistics.players_on_segment(Vector3(0.6, 1.7, -2), Vector3(0.6, 1.7, 2),
		[{"id": 1, "a": Vector3(0, 0.1, 0), "b": Vector3(0, 1.75, 0) + p.lean_offset()}])
	var neutral_hit := Ballistics.players_on_segment(Vector3(0.6, 1.7, -2), Vector3(0.6, 1.7, 2),
		[{"id": 1, "a": Vector3(0, 0.1, 0), "b": Vector3(0, 1.75, 0)}])
	check("exposed leaning head can be hit outside neutral volume", not hit.is_empty() and neutral_hit.is_empty())
	var before := p.get_move_state()
	p.set_move_state(p.position, Vector3.ZERO, p.crouched, p.height, 0.0)
	p.set_move_state(before.pos, before.vel, before.crouched, before.height, before.lean)
	check("reconciliation restores lean", absf(p.lean - 1.0) < 0.001)
	c.lean = -1
	for i in 35:
		p.simulate(c, 1.0 / 60.0)
	check("left lean exposes left side", p.lean < -0.99 and p.lean_offset().x < -0.37)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 3.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector3(0.6, 1.5, 0.0)
	await physics_frame
	c.lean = 1
	for i in 35:
		p.simulate(c, 1.0 / 60.0)
	check("wall clamps lean and keeps head volume outside cover", p.lean < 0.65 and p.camera.global_position.x + Ballistics.PLAYER_RADIUS < 0.55)
	c.crouch = true
	for i in 30:
		p.simulate(c, 1.0 / 60.0)
	check("crouched lean remains collision-safe", p.crouched and p.camera.global_position.x + Ballistics.PLAYER_RADIUS < 0.55)
	p.reset()
	check("reset centers lean and camera", p.lean == 0.0 and p.camera.rotation.z == 0.0 and p.lean_offset() == Vector3.ZERO)
	wall.queue_free()
	await physics_frame
	# Both peers consume the same absolute look commands, including prior recoil and mouse input.
	p.set_look(0, 0)
	twin.set_look(0, 0)
	c = NetCmd.new()
	lo.apply_cmd(c, 0.02)
	predicted.apply_cmd(c, 0.02)
	c.fire = true
	var agreement := true
	for i in 30:
		c.seq = i + 1
		c.yaw = p.rotation.y
		c.pitch = p.pitch()
		p.simulate(c, 0.1)
		twin.simulate(c, 0.1)
		lo.apply_cmd(c, 0.1)
		predicted.apply_cmd(c, 0.1)
		agreement = agreement and is_equal_approx(p.pitch(), twin.pitch()) and is_equal_approx(p.rotation.y, twin.rotation.y) and lo.mag == predicted.mag
	check("30-shot authoritative and predicted spray agree", agreement and lo.mag == 0 and lo.spray_shots == 30)
	check("sustained rifle spray requires substantial downward compensation", rad_to_deg(p.pitch()) > 30.0)
	check("spray reverses horizontally", lo.recoil_impulse(8).x < -0.5 and lo.recoil_impulse(16).x > 0.8 and lo.recoil_impulse(23).x < -0.8)
	c.fire = false
	lo.apply_cmd(c, 0.5)
	check("pause resets spray without erasing mouse aim", lo.spray_shots == 0 and p.pitch() > 0.5)
	# The next real ADS shot after a pause starts with the opening impulse, even after a full spray.
	lo.mag = 1
	p.set_look(0, 0)
	c.fire = true
	c.aim = true
	lo.apply_cmd(c, 0.1)
	check("ADS burst restarts at the full opening recoil", lo.aiming and lo.spray_shots == 1 and is_equal_approx(p.pitch(), deg_to_rad(lo.tuning.kick_deg)))
	for id in Weapons.ORDER:
		Weapons.apply(lo.tuning, id)
		check("weapon has meaningful recoil: " + id, lo.recoil_impulse(0).y >= 0.6)
	# Exercise the host policy when a bomb interaction and an enemy radio occupy the same spot.
	p.reset()
	var net_script = load("res://scripts/net/net_match.gd")
	var match_net = net_script.new()
	var loop = load("res://scripts/match/match_loop.gd").new()
	var voice = load("res://scripts/voice/match_voice.gd").new()
	var drops = load("res://scripts/world/weapon_drops.gd").new()
	world.add_child(drops)
	drops.set_process(false)
	drops.net = match_net
	match_net.weapon_drops = drops
	match_net.is_host = true
	match_net.g = world
	match_net.voice = voice
	match_net.loop = loop
	loop.net = match_net
	voice.net = match_net
	var slot = net_script.Slot.new()
	slot.id = 1
	slot.node = p
	match_net.slots[1] = slot
	loop.rules.tuning = MatchTuning.new()
	var test_sites: Array[Vector3] = [p.global_position]
	loop.rules.tuning.sites = test_sites
	loop.rules.bomb_pos = p.global_position + Vector3(0, 0.15, 0)
	loop.rules.phase = RoundRules.Phase.LIVE
	loop.rules.carrier = 1
	var radio_at := p.global_position + Vector3(0, .11, -.8)
	p.set_look(0.0, -60.0)
	voice.pickups[1] = {"team": 1, "pos": radio_at}
	match_net._interact_host(1, match_net.round_id, match_net.Interact.RADIO, 1)
	check("planting moved to slot 5: a carrier's F in a site takes the radio", voice.pickups.is_empty())
	voice.stolen.clear()
	voice.pickups[1] = {"team": 1, "pos": radio_at}
	match_net.tick += 8 # past the per-player interaction cooldown
	loop.rules.carrier = 0
	match_net._interact_host(1, match_net.round_id, match_net.Interact.RADIO, 1)
	check("F prioritizes bomb recovery over nearby radio", voice.stolen.is_empty() and voice.pickups.size() == 1)
	loop.rules.phase = RoundRules.Phase.PLANTED
	slot.team = 1
	voice.pickups[1].team = 0
	match_net._interact_host(1, match_net.round_id, match_net.Interact.RADIO, 1)
	check("F prioritizes defusing over nearby radio", voice.stolen.is_empty() and voice.pickups.size() == 1)
	loop.rules.phase = RoundRules.Phase.LIVE
	loop.rules.carrier = 2
	var gun_at := radio_at + Vector3.RIGHT * .5
	drops.drops[1] = {"gun": "carbine", "ammo": [5, 10], "pos": gun_at}
	check("looking at the radio selects it over a nearby gun",
		match_net.interaction_target(1, p, slot.team) == [match_net.Interact.RADIO, 1])
	var aim := p.camera.global_position.direction_to(gun_at)
	p.set_look(rad_to_deg(atan2(-aim.x, -aim.z)), rad_to_deg(asin(aim.y)))
	check("looking at the gun selects it over a nearby radio",
		match_net.interaction_target(1, p, slot.team) == [match_net.Interact.GUN, 1])
	match_net._interact_host(1, match_net.round_id, match_net.Interact.RADIO, 1)
	check("the host refuses a mismatched target", voice.stolen.is_empty() and voice.pickups.has(1))
	p.set_look(0.0, -60.0)
	match_net._interact_host(1, match_net.round_id, match_net.Interact.RADIO, 1)
	check("F can steal when no objective action is available", voice.stolen.has(1) and voice.pickups.is_empty())
	voice.pickups[2] = {"team": 0, "pos": radio_at}
	check("a player with an enemy radio gets no prompt on a second enemy radio",
		voice.target_radio(p, slot.team, true) == 0 and voice.target_radio(p, slot.team, false) == 2)
	voice.pickups[3] = {"team": 1, "pos": radio_at}
	match_net.tick += 8
	match_net._interact_host(1, match_net.round_id, match_net.Interact.RADIO, 3)
	check("recovering an allied radio removes it while keeping the intercepted channel",
		not voice.pickups.has(3) and voice.pickups.has(2) and int(voice.stolen[1]) == 0)
	voice.toggle_enemy_radio()
	check("enemy radio can mute independently of microphone", voice.enemy_radio_muted)
	voice.reset_round()
	check("stolen radio listening defaults on each round", not voice.enemy_radio_muted and voice.stolen.is_empty())
	check("buy, drop and enemy mute have distinct defaults", ctl.key("buy_menu") == "B" and ctl.key("drop_bomb") == "J" and ctl.key("enemy_radio_mute") == "O")
	lo.select(Loadout.Tool.HOLSTER)
	var empty_cmd := NetCmd.new()
	empty_cmd.tool = Loadout.Tool.HOLSTER
	empty_cmd.fire = true
	lo.apply_cmd(empty_cmd, .1)
	check("holster round-trips and cannot fire or place charges", empty_cmd.quantised().tool == Loadout.Tool.HOLSTER and not lo.is_gun() and lo.tool == Loadout.Tool.HOLSTER)
	check("primary slower than sidearm slower than empty hands", p.movement_speed(Loadout.Tool.RIFLE) < p.movement_speed(Loadout.Tool.SIDEARM) and p.movement_speed(Loadout.Tool.SIDEARM) < p.movement_speed(Loadout.Tool.HOLSTER))
	p.reset()
	empty_cmd.move = Vector2(0,-1)
	empty_cmd.slow_walk = true
	empty_cmd.lean = 1
	for i in 60:
		p.simulate(empty_cmd, 1.0 / 60.0)
	check("Shift slow walk has a distinct speed and preserves lean", ctl.key("slow_walk") == "Shift" and empty_cmd.quantised().slow_walk
		and is_equal_approx(Vector2(p.velocity.x, p.velocity.z).length(), p.tuning.slow_walk_speed) and p.lean > .99)
	empty_cmd.crouch = true
	for i in 24:
		p.simulate(empty_cmd, 1.0 / 60.0)
	check("crouch overrides slow walk with a lower speed", p.crouched and p.tuning.crouch_speed < p.tuning.slow_walk_speed
		and is_equal_approx(Vector2(p.velocity.x, p.velocity.z).length(), p.tuning.crouch_speed))
	lo.select(Loadout.Tool.RIFLE)
	for base_fov in [60.0, 90.0, 110.0]:
		p.fov = base_fov
		lo.set_gear("marksman", "p9")
		var ratio := tan(deg_to_rad(base_fov) * .5) / tan(deg_to_rad(lo.ads_fov()) * .5)
		check("4x optical zoom at base FOV %.0f" % base_fov, absf(ratio - 4.0) < .001)
	lo.select(Loadout.Tool.SIDEARM)
	check("secondary ADS restores its own magnification", lo.ads_fov() > 70.0 and lo.ads_fov() < p.fov)
	await _test_vault(p, world)
	drops.free()
	voice.free()
	loop.free()
	match_net.free()
	print("SMOKE_OK controls" if fails == 0 else "SMOKE_FAIL controls")
	quit(0 if fails == 0 else 1)


func _test_vault(p: Player, world: Node3D) -> void:
	_box(world, Vector3(0, -0.2, -2.0), Vector3(8, 0.4, 8))
	var crate := _box(world, Vector3(0, 0.32, -1.0), Vector3(1.0, 0.64, 0.8))
	await physics_frame
	p.tuning.gravity = 20.0
	var c := NetCmd.new()
	c.move = Vector2(0, -1)
	p.teleport(Vector3(0, 0.05, 0), 0)
	for i in 30:
		p.simulate(c, 1.0 / 60.0)
	check("low cover blocks regular movement", p.global_position.y < 0.05 and p.global_position.z > -0.5)
	c.vault = true
	p.simulate(c.quantised(), 1.0 / 60.0)
	check("Space vaults the player onto low cover", p.global_position.y > .59 and p.global_position.y < .69)
	_box(world, Vector3(0, 2.12, -0.52), Vector3(1.2, 0.2, 2.0))
	await physics_frame
	p.teleport(Vector3(0, 0.05, 0), 0)
	for i in 30:
		p.simulate(c, 1.0 / 60.0)
	check("vault clearance prevents passing through a low ceiling", p.global_position.y < 0.05)
	crate.queue_free()


func _box(world: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.position = pos
	return body
