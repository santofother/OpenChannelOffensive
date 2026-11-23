class_name Loadout
extends Node
## Rifle + breach charges for one player, plus its HUD when `presentation` is on.
## Keys: 1 primary, 2 sidearm, 3/4 charges, 5 reinforcement (attackers: the bomb, when carried), 6 medkit, LMB use, RMB aim, R reload.
## All gameplay goes through apply_cmd(NetCmd) once per tick: offline from the keyboard, on the host for every
## player (authority: commits damage and charges), and on the owning client as prediction (no commits).
## Headless tests call fire_rifle()/start_reload()/place_charge()/select() directly.

signal handling(code: int, pos: Vector3)
signal fired(res: Dictionary) ## any shot (authority or predicted)
signal player_hit(victim_id: int, damage: float, head: bool) ## authority only; damage already includes the head multiplier
signal charge_placed(charge: Charge) ## authority only
signal reinforced(module: WallModule) ## authority only
signal healed(amount: float) ## authority only

## RIFLE = primary gun slot (key 1), SIDEARM = pistol slot (key 2). With no primary, RIFLE selects the sidearm.
enum Tool { RIFLE, ORDINARY_CHARGE, HEAVY_CHARGE, REINFORCE, SIDEARM, MEDKIT, FRAG, FLASH, SMOKE, INCENDIARY, HOLSTER, BOMB }

const RAY_MASK := 1 | 4 ## world + targets (players are tested analytically, see Ballistics)
const WALL_MASK := 1
const MAX_MARKS := 24
const HEAL_TIME := 3.0
const HEAL_AMOUNT := 50.0

var tuning: WeaponTuning
var player: Player
var world: Node3D
var effects: BreachEffects
var viewmodel: Viewmodel
var tool := Tool.RIFLE
var owner_id := 1
var authority := true ## commits hits/charges (offline or host)
var presentation := true ## HUD, viewmodel, flash, sounds, marks (the local player only)
var net_driven := false ## NetMatch calls apply_cmd(); _physics_process does nothing
var use_spread := true
var use_recoil := true ## scripted baseline tests opt out; gameplay authority and prediction both recoil
var spray_shots := 0
var spray_idle := 0.0
var last_fire_seq := -1
## Returns hit volumes of the other players for a shot: [{id, a, b}] (see Ballistics). Unset offline.
var player_volumes: Callable
## Net test bots set these (the keyboard is ignored when player.scripted).
var bot := false
var script_fire := false
var script_aim := false
var script_reload := false
var want_tool := Tool.RIFLE
var mag := 0
var reserve := 0
var reloading := false
var charges := {Tool.ORDINARY_CHARGE: 0, Tool.HEAVY_CHARGE: 0, Tool.REINFORCE: 0, Tool.MEDKIT: 0}
var gadgets_owned := 0 # flashlight=1, laser=2, NVG=4, silencer=8; reset every round
var zip_ties := 0 ## door locks carried (host-owned, synced with the equipment rows)
var gadgets_on := 0
var grenade_cooldown := 0.0
var primary := "" ## Weapons id, "" = none
var secondary := Weapons.DEFAULT_SIDEARM
var armor := 0 ## 0..100, absorbs half of incoming damage while it lasts
var helmet := false
var defuse_kit := false
var _gun_ammo := {Tool.RIFLE: [0, 0], Tool.SIDEARM: [0, 0]}
var _gun_tool := Tool.RIFLE
## Authority hook: returns "" if this player's team may reinforce another panel, else the refusal text.
var reinforce_gate: Callable
## Set by the round loop each tick. On attack, key 5 holds the bomb (when carried) instead of a kit.
var bomb_slot := false
var has_bomb := false
var install_left := 0.0 ## seconds left on the current reinforcement (0 = idle)
var _install_module: WallModule
var aiming := false
var shots_fired := 0
var last_shot: Dictionary = {}
var active_charges: Array[Charge] = []
var last_message := ""
var hit_marker := 0.0
var _hit_kill := false
var _hit_head := false
var _cooldown := 0.0
var _reload_left := 0.0
var _fire_armed := false
var _prev_reload := false
var _cur_seq := 0
var _flash_left := 0.0
var _flash: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _marks: Array[MeshInstance3D] = []
var _mark_next := 0
var _mark_mat: StandardMaterial3D
var _msg_left := 0.0
var _canvas: Control
var _ammo_label: Label
var _msg_label: Label
var _warn_label: Label


func setup(p: Player, w: Node3D, t: WeaponTuning, with_presentation: bool = true) -> void:
	player = p
	p.movement_loadout = self
	world = w
	tuning = t
	presentation = with_presentation
	use_spread = not p.scripted
	if not presentation:
		reset()
		return
	effects = BreachEffects.new()
	effects.name = "BreachEffects"
	world.add_child(effects)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.85, 0.5)
	_flash.omni_range = 4.0
	_flash.light_energy = 2.0
	_flash.visible = false
	_flash.position = tuning.muzzle_offset
	player.camera.add_child(_flash)
	viewmodel = Viewmodel.new()
	player.camera.add_child(viewmodel)
	viewmodel.setup(self)
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.albedo_color = Color(0.05, 0.05, 0.05, 0.85)
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_build_hud()
	reset()


func reset() -> void:
	gadgets_owned = 0
	gadgets_on = 0
	zip_ties = 0
	grenade_cooldown = 0.0
	for t in range(Tool.FRAG, Tool.INCENDIARY + 1):
		charges[t] = 0
	primary = Weapons.DEFAULT_PRIMARY
	secondary = Weapons.DEFAULT_SIDEARM
	armor = 0
	helmet = false
	defuse_kit = false
	_equip_all()
	tool = Tool.RIFLE if primary != "" else Tool.SIDEARM
	want_tool = tool
	reloading = false
	aiming = false
	_cooldown = 0.0
	_reload_left = 0.0
	shots_fired = 0
	last_fire_seq = -1
	spray_shots = 0
	spray_idle = 0.0
	last_shot = {}
	charges[Tool.ORDINARY_CHARGE] = tuning.ordinary_count
	charges[Tool.HEAVY_CHARGE] = tuning.heavy_count
	charges[Tool.REINFORCE] = tuning.reinforce_count
	charges[Tool.MEDKIT] = 0
	_cancel_install()
	for c in active_charges:
		if is_instance_valid(c):
			c.set_process(false)
			c.free()
	active_charges.clear()
	for m in _marks:
		m.queue_free()
	_marks.clear()
	_mark_next = 0
	if effects and presentation:
		effects.clear()
	hit_marker = 0.0
	_fire_armed = false
	_prev_reload = false
	script_fire = false
	script_aim = false
	script_reload = false
	if _flash:
		_flash.visible = false
	_say("")


## Model/catalog key of a non-gun tool ("" for the gun slots).
static func tool_key(t: int) -> String:
	return ["", "ordinary", "heavy", "kit", "", "medkit", "frag", "flash", "smoke", "incendiary"][t] if t >= 0 and t < 10 else ""


static func key_tool(key: String) -> int:
	return {"ordinary": Tool.ORDINARY_CHARGE, "heavy": Tool.HEAVY_CHARGE, "kit": Tool.REINFORCE, "medkit": Tool.MEDKIT, "frag": Tool.FRAG, "flash": Tool.FLASH, "smoke": Tool.SMOKE, "incendiary": Tool.INCENDIARY}.get(key, Tool.RIFLE)


## Duration of the current hold-to-use action (viewmodel animation length).
func use_time() -> float:
	return HEAL_TIME if tool == Tool.MEDKIT else tuning.reinforce_time


func silenced() -> bool:
	return gadgets_owned & 8 != 0


func is_gun() -> bool:
	return tool == Tool.RIFLE or tool == Tool.SIDEARM


func weapon_id() -> String:
	return primary if tool == Tool.RIFLE else secondary


## Refills both guns and wields the best one (host baseline and offline reset).
func _equip_all() -> void:
	for slot in [Tool.RIFLE, Tool.SIDEARM]:
		var id := primary if slot == Tool.RIFLE else secondary
		if id != "":
			_gun_ammo[slot] = [Weapons.DEFS[id].mag, Weapons.DEFS[id].reserve]
	_wield_force(Tool.RIFLE if primary != "" else Tool.SIDEARM)


## Switch the active gun: stores the old gun's ammo, loads the new gun's stats and ammo.
func _wield(slot: int) -> void:
	_gun_ammo[_gun_tool] = [mag, reserve]
	_wield_force(slot)


func _wield_force(slot: int) -> void:
	_gun_tool = slot
	var id := primary if slot == Tool.RIFLE else secondary
	if id == "":
		return
	Weapons.apply(tuning, id)
	mag = int(_gun_ammo[slot][0])
	reserve = int(_gun_ammo[slot][1])
	reloading = false


## New guns come with full ammo; unchanged guns keep theirs.
func set_gear(new_primary: String, new_secondary: String) -> void:
	_gun_ammo[_gun_tool] = [mag, reserve]
	for slot in [Tool.RIFLE, Tool.SIDEARM]:
		var old := primary if slot == Tool.RIFLE else secondary
		var id := new_primary if slot == Tool.RIFLE else new_secondary
		if id != old and id != "":
			_gun_ammo[slot] = [Weapons.DEFS[id].mag, Weapons.DEFS[id].reserve]
	primary = new_primary
	secondary = new_secondary
	var active := _gun_tool
	if active == Tool.RIFLE and primary == "":
		active = Tool.SIDEARM
	_wield_force(active)
	if tool == Tool.RIFLE or tool == Tool.SIDEARM:
		tool = active
		want_tool = active


func gun_inventory(slot: int) -> Dictionary:
	var id := primary if slot == Tool.RIFLE else secondary
	if id.is_empty():
		return {}
	var ammo: Array = [mag, reserve] if _gun_tool == slot else _gun_ammo[slot].duplicate()
	return {"id": id, "ammo": ammo}


func equip_looted_gun(id: String, ammo: Array) -> void:
	cancel_use()
	var slot := Tool.RIFLE if int(Weapons.DEFS[id].slot) == 0 else Tool.SIDEARM
	_gun_ammo[_gun_tool] = [mag, reserve]
	if slot == Tool.RIFLE:
		primary = id
	else:
		secondary = id
	_gun_ammo[slot] = ammo.duplicate()
	_wield_force(slot)
	select(slot)
	want_tool = slot
	spray_shots = 0
	spray_idle = 0.0


func reload_left() -> float:
	return _reload_left


func visible_marks() -> int:
	var n := 0
	for m in _marks:
		if is_instance_valid(m) and m.visible:
			n += 1
	return n


# ---------------------------------------------------------------- input / frame

func _can_act() -> bool:
	return not player.scripted and player.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if net_driven:
		return
	if not _can_act():
		_tick(delta)
		aiming = false
		_fire_armed = false
		return
	var cmd := NetCmd.new()
	fill_cmd(cmd)
	_cur_seq += 1
	cmd.seq = _cur_seq
	apply_cmd(cmd, delta)


func _tick(delta: float) -> void:
	spray_idle = minf(spray_idle + delta, 10.0)
	if spray_idle >= tuning.recoil_reset_time:
		spray_shots = 0
	grenade_cooldown = maxf(grenade_cooldown - delta, 0.0)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if reloading:
		var progress_before := 1.0 - _reload_left / tuning.reload_time
		_reload_left -= delta
		var progress := 1.0 - _reload_left / tuning.reload_time
		if progress_before < 0.62 and progress >= 0.62:
			_handling_cue(1)
		if progress_before < 0.86 and progress >= 0.86:
			_handling_cue(2)
		if _reload_left <= 0.0:
			_finish_reload()


## Button state for this tick from the keyboard/mouse (or the bot fields).
func fill_cmd(cmd: NetCmd) -> void:
	if bot:
		cmd.fire = script_fire
		cmd.aim = script_aim
		cmd.reload = script_reload
		cmd.tool = want_tool
		cmd.gadgets = gadgets_on
		return
	if _can_act():
		if Input.is_action_just_pressed("holster"):
			want_tool = Tool.HOLSTER
		elif Input.is_action_just_pressed("tool_1"):
			want_tool = Tool.RIFLE
		elif Input.is_action_just_pressed("tool_2"):
			want_tool = Tool.SIDEARM
		elif Input.is_action_just_pressed("tool_3"):
			want_tool = Tool.ORDINARY_CHARGE
		elif Input.is_action_just_pressed("tool_4"):
			want_tool = Tool.HEAVY_CHARGE
		elif Input.is_action_just_pressed("tool_5"):
			if not bomb_slot:
				want_tool = Tool.REINFORCE
			elif has_bomb:
				want_tool = Tool.BOMB
		elif Input.is_action_just_pressed("tool_6"):
			want_tool = Tool.MEDKIT
		if Input.is_action_just_pressed("grenade_cycle"):
			for i in 4:
				var next := Tool.FRAG + posmod(want_tool - Tool.FRAG + i + 1, 4)
				if int(charges.get(next, 0)) > 0:
					want_tool = next
					break
		for pair in [["flashlight", 1], ["laser", 2], ["nightvision", 4]]:
			if Input.is_action_just_pressed(pair[0]):
				gadgets_on = (gadgets_on ^ int(pair[1])) & gadgets_owned
		cmd.fire = Input.is_action_pressed("primary_fire")
		cmd.aim = Input.is_action_pressed("aim")
		cmd.reload = Input.is_action_pressed("reload")
	cmd.tool = want_tool
	cmd.gadgets = gadgets_on


## One gameplay tick from a command. Edges (reload press, charge placement) derive from the previous command.
func apply_cmd(cmd: NetCmd, delta: float) -> void:
	_cur_seq = cmd.seq
	gadgets_on = cmd.gadgets & gadgets_owned
	_tick(delta)
	if cmd.tool != tool:
		select(cmd.tool)
	if tool == Tool.BOMB and not has_bomb:
		select(Tool.RIFLE) # planted or dropped: back to a gun
	if (tool != Tool.REINFORCE and tool != Tool.MEDKIT) or not cmd.fire:
		_cancel_install()
	if cmd.reload and not _prev_reload:
		start_reload()
	_prev_reload = cmd.reload
	aiming = is_gun() and not reloading and cmd.aim
	if not cmd.fire:
		_fire_armed = true
	elif tool == Tool.REINFORCE:
		_install(cmd.fire, delta)
	elif tool == Tool.MEDKIT:
		_heal(delta)
	elif _fire_armed:
		if is_gun():
			fire_rifle()
			if not tuning.auto:
				_fire_armed = false
		elif tool == Tool.HOLSTER or tool == Tool.BOMB:
			_fire_armed = false # the round loop reads a held fire with the bomb as planting
		elif tool >= Tool.FRAG:
			if authority and grenade_cooldown <= 0.0 and int(charges.get(tool, 0)) > 0:
				if world.gadgets.throw_grenade(self):
					charges[tool] -= 1
					grenade_cooldown = 0.6
			_fire_armed = false
		else:
			place_charge()
			_fire_armed = false


func _process(delta: float) -> void:
	if not presentation:
		return
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
	hit_marker = maxf(hit_marker - delta, 0.0)
	_msg_left = maxf(_msg_left - delta, 0.0)
	_msg_label.modulate.a = clampf(_msg_left, 0.0, 1.0)
	if presentation and not player.scripted and player.camera.current:
		var target := ads_fov() if aiming else player.fov
		player.camera.fov = lerpf(player.camera.fov, target, clampf(tuning.ads_speed * delta, 0.0, 1.0))
	if presentation:
		_update_hud()
		_canvas.queue_redraw()


func ads_fov() -> float:
	var magnification := float(Weapons.DEFS[weapon_id()].get("magnification", 1.35)) if is_gun() else 1.0
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(player.fov) * 0.5) / magnification))


# ---------------------------------------------------------------- tools

func select(t: int) -> void:
	if t < 0 or t > Tool.BOMB:
		return
	if t == Tool.BOMB and not has_bomb:
		if want_tool == Tool.BOMB:
			want_tool = tool
		return
	if t == Tool.RIFLE and primary == "":
		t = Tool.SIDEARM
	want_tool = t
	if t == tool:
		return
	tool = t
	reloading = false
	if t == Tool.RIFLE or t == Tool.SIDEARM:
		if _gun_tool != t:
			_wield(t)
	if presentation:
		_say(["", "Ordinary charge", "Heavy charge", "Reinforcement kit", "", "Medkit", "Frag", "Flash", "Smoke", "Incendiary", "Empty hands", "Bomb"][t] if t != Tool.RIFLE and t != Tool.SIDEARM
			else Weapons.DEFS[weapon_id()].name)


func start_reload() -> bool:
	if not is_gun() or reloading or mag >= tuning.mag_size or reserve <= 0:
		return false
	reloading = true
	_reload_left = tuning.reload_time
	_handling_cue(0)
	return true


func _handling_cue(index: int) -> void:
	var code := ProcAudio.HANDLING_OFFSET + index + (3 if weapon_id() == "revolver" else 0)
	if presentation:
		ProcAudio.player_cue(world, code)
	if authority and net_driven:
		handling.emit(code, player.camera.global_position - Vector3.UP * 0.25)


func _finish_reload() -> void:
	reloading = false
	var take := mini(tuning.mag_size - mag, reserve)
	mag += take
	reserve -= take


## Fires one shot if allowed. Returns the Ballistics result, or {} if nothing fired.
func fire_rifle() -> Dictionary:
	if not is_gun() or reloading or _cooldown > 0.0:
		return {}
	if mag <= 0:
		_cooldown = 0.25
		if presentation:
			ProcAudio.play(world, "dry")
		if not start_reload():
			_say("Out of ammo")
		return {}
	mag -= 1
	shots_fired += 1
	last_fire_seq = _cur_seq
	_cooldown = tuning.fire_interval
	var xf := player.camera.global_transform
	var dir := -xf.basis.z
	if use_spread:
		# Seeded by owner + command seq so the host and the predicting client draw the same spread.
		_rng.seed = hash([owner_id, _cur_seq])
		var spread := deg_to_rad(tuning.spread_aim_deg if aiming else tuning.spread_hip_deg)
		if not aiming and gadgets_on & 2:
			spread *= 0.7
		# Sustained automatic fire blooms: up to +70% cone after ten shots.
		if tuning.auto:
			spread *= 1.0 + minf(spray_shots, 10) * 0.07
		var ang := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * spread
		dir = (dir + xf.basis.x * cos(ang) * r + xf.basis.y * sin(ang) * r).normalized()
	if use_recoil:
		var impulse := recoil_impulse(spray_shots)
		player.kick(deg_to_rad(impulse.y), deg_to_rad(impulse.x))
	spray_shots = mini(spray_shots + 1, 65535)
	spray_idle = 0.0
	var muzzle := xf * tuning.muzzle_offset
	var vols: Array = player_volumes.call() if player_volumes.is_valid() else []
	var res := Ballistics.resolve(player.get_world_3d().direct_space_state, xf.origin, dir, muzzle,
		tuning.range_m, RAY_MASK, [player.get_rid()] as Array[RID], vols)
	res["origin"] = muzzle
	res["silenced"] = silenced()
	res["weapon"] = Weapons.index_of(weapon_id())
	last_shot = res
	if presentation:
		ProcAudio.shot(world, int(res.weapon), bool(res.silenced))
		if not res["silenced"]:
			_flash.visible = true
			_flash_left = 0.04
		show_impacts(res)
	if authority:
		var wall_damage := tuning.damage
		for imp: Dictionary in res.get("impacts", []):
			if imp.get("collider") is WallModule:
				(imp.collider as WallModule).impact(imp.position, wall_damage)
			wall_damage *= float(imp.collider.get_meta("pen_mult", 1.0))
		if res.get("hit", false) and res.get("collider") is WallModule:
			(res.collider as WallModule).impact(res.position, tuning.damage * float(res.damage_mult))
	if authority and world and world.get("doors"):
		world.get("doors").call("on_shot", res) # untyped: --script tests can't compile DoorSystem's autoload deps
	fired.emit(res)
	if authority and res["hit"]:
		_on_hit(res)
	return res


## Degrees per shot: a steep opening climb, then alternating lateral runs. ADS keeps the full
## pattern; crouching slightly steadies it. The same function runs on host and predicting owner.
func recoil_impulse(index: int) -> Vector2:
	var side := 0.0
	var rise := 1.0
	if tuning.auto:
		const LATERAL := [0.0, 0.12, -0.08, 0.18, 0.32, 0.48, 0.65, 0.80,
			0.90, 0.85, 0.65, 0.35, -0.25, -0.65, -0.95, -1.10,
			-1.15, -1.0, -0.80, -0.45, 0.25, 0.65, 1.0, 1.10,
			0.95, 0.60, 0.15, -0.40, -0.85, -1.0]
		side = LATERAL[index % LATERAL.size()] * tuning.recoil_side
		rise = 1.0 + minf(index * 0.07, 0.56) if index < 9 else 0.9
	var steady := 0.85 if player.crouched else 1.0
	# Positive yaw turns left in Godot; positive pattern X means the muzzle kicks right.
	return Vector2(-side, tuning.kick_deg * rise) * steady


## Cosmetic bullet marks for every surface a shot entered or stopped on.
func show_impacts(res: Dictionary) -> void:
	for imp: Dictionary in res.get("impacts", []):
		if not net_driven or _door_impact_id(imp.collider) < 0:
			_add_mark(imp.position, imp.normal, imp.collider)
	if res["hit"] and int(res.get("player_id", -1)) < 0 and not (res["collider"] is PracticeTarget):
		if not net_driven or _door_impact_id(res.collider) < 0:
			_add_mark(res.position, res.normal, res.collider)


static func _door_impact_id(collider: Object) -> int:
	return int(collider.get_meta("door_id", -1)) if collider is Node3D and collider.has_meta("door_id") else -1


func _on_hit(res: Dictionary) -> void:
	var col: Object = res["collider"]
	var dmg := tuning.damage * float(res.get("damage_mult", 1.0))
	var head := bool(res.get("head", false))
	if head:
		dmg *= tuning.head_mult
	if int(res.get("player_id", -1)) >= 0:
		player_hit.emit(int(res["player_id"]), dmg, head)
	elif col is PracticeTarget:
		show_hit((col as PracticeTarget).apply_damage(dmg))


## Hit confirmation feedback (host-confirmed in a session).
func show_hit(killed: bool, head: bool = false) -> void:
	if not presentation:
		return
	hit_marker = 0.36 if head else 0.18
	_hit_kill = killed
	_hit_head = head
	ProcAudio.play(world, "hit")


func _add_mark(pos: Vector3, normal: Vector3, owner_module: Object) -> void:
	if not presentation:
		return
	if owner_module is WallModule and owner_module.impact_destructible and owner_module.material == WallModule.Mat.ORDINARY:
		return # physical openings replace a flat bullet-mark quad
	var mi: MeshInstance3D
	if _marks.size() < MAX_MARKS:
		mi = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.09, 0.09)
		q.material = _mark_mat
		mi.mesh = q
		world.add_child(mi)
		_marks.append(mi)
	else:
		mi = _marks[_mark_next]
	_mark_next = (_mark_next + 1) % MAX_MARKS
	var parent: Node3D = owner_module if _door_impact_id(owner_module) >= 0 else world
	if mi.get_parent() != parent:
		mi.reparent(parent)
	var up := Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(-normal, up), pos + normal * 0.004)
	mi.visible = true
	if owner_module is WallModule:
		mi.set_meta("module", owner_module)
	elif mi.has_meta("module"):
		mi.remove_meta("module")


## Clear marks attached to a door when its leaf returns to the round-start pose.
func clear_door_marks(door: Node3D) -> void:
	for mark in _marks:
		if is_instance_valid(mark) and mark.get_parent() == door:
			mark.visible = false


## Transfer the bot's current equipment and ammunition to its new controller.
func adopt_equipment(from: Loadout) -> void:
	cancel_use()
	set_gear(from.primary, from.secondary)
	_gun_ammo = from._gun_ammo.duplicate(true)
	_gun_tool = from._gun_tool
	tool = from.tool
	want_tool = from.tool
	tuning = from.tuning.duplicate()
	mag = from.mag
	reserve = from.reserve
	charges = from.charges.duplicate()
	armor = from.armor
	helmet = from.helmet
	defuse_kit = from.defuse_kit
	gadgets_owned = from.gadgets_owned
	gadgets_on = from.gadgets_on
	zip_ties = from.zip_ties
	_cooldown = from._cooldown
	grenade_cooldown = from.grenade_cooldown
	spray_shots = from.spray_shots
	spray_idle = from.spray_idle


## Called when a wall panel changes state: hide cosmetic marks that were on it.
func on_module_changed(m: WallModule) -> void:
	for mi in _marks:
		if is_instance_valid(mi) and mi.has_meta("module") and mi.get_meta("module") == m:
			mi.visible = false


# ---------------------------------------------------------------- charges

func check_placement(t: int) -> Dictionary:
	var kind := t - 1 ## Tool.ORDINARY_CHARGE -> Kind.ORDINARY, HEAVY_CHARGE -> HEAVY
	var cam := player.camera.global_transform
	var from := cam.origin
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.basis.z * tuning.place_reach, WALL_MASK,
		[player.get_rid()] as Array[RID])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "reason": "Too far: aim at a wall within %.1f m" % tuning.place_reach}
	var col: Object = hit["collider"]
	var on_door := false
	if col is Node and (col as Node).has_meta("door_id") and world.get("doors"):
		# A charge aimed at a closed door goes on the frame (header cell) above it and blows the door too.
		var door: Object = world.get("doors").get("doors")[int((col as Node).get_meta("door_id"))]
		var header: Variant = world.call("_mod", door.get("header")) if world.has_method("_mod") else null
		if header is WallModule:
			col = header
			on_door = true
			var p: Vector3 = hit["position"]
			hit = {"collider": header, "normal": hit["normal"], "position": Vector3(p.x, (door.get("hinge") as Vector3).y + 2.3, p.z)}
	if not (col is WallModule) or not (col as WallModule).breakable:
		return {"ok": false, "reason": "Can't breach this surface"}
	var m := col as WallModule
	var n: Vector3 = hit["normal"]
	var pos: Vector3 = hit["position"]
	if absf(n.y) > 0.3:
		return {"ok": false, "reason": "Place charges on the wall face"}
	if not on_door and (pos.y < 0.3 or pos.y > 2.5):
		return {"ok": false, "reason": "Aim between knee and head height"}
	if m.state != WallModule.State.INTACT:
		return {"ok": false, "reason": "Already breached"}
	if m.charge != null and is_instance_valid(m.charge):
		return {"ok": false, "reason": "Charge already placed here"}
	if not WallModule.can_breach(m.material, kind):
		var need := "heavy" if m.material == WallModule.Mat.REINFORCED else "ordinary"
		var mat_name := "reinforced" if m.material == WallModule.Mat.REINFORCED else "ordinary"
		return {"ok": false, "reason": "Wrong tool: %s wall needs the %s charge" % [mat_name, need]}
	return {"ok": true, "reason": "", "module": m, "position": pos, "normal": n}


func place_charge() -> bool:
	if not (tool == Tool.ORDINARY_CHARGE or tool == Tool.HEAVY_CHARGE):
		return false
	if int(charges[tool]) <= 0:
		_reject("No charges left")
		return false
	var c := check_placement(tool)
	if not c["ok"]:
		_reject(c["reason"])
		return false
	if not authority:
		# Prediction only: the host places (or refuses) the charge and replicates it.
		_say("Placing charge...")
		return true
	var kind := tool - 1
	var fuse := tuning.heavy_fuse if kind == WallModule.Kind.HEAVY else tuning.ordinary_fuse
	var charge := Charge.new()
	charge.owner_id = owner_id
	world.add_child(charge)
	charge.setup(c["module"], kind, fuse, c["position"], c["normal"])
	(c["module"] as WallModule).charge = charge
	charge.detonated.connect(_on_detonated)
	active_charges.append(charge)
	charges[tool] = int(charges[tool]) - 1
	if presentation:
		ProcAudio.play(world, "beep")
	_say("Charge armed: %.0f s. Move away!" % fuse)
	charge_placed.emit(charge)
	return true


## Hold fire on one intact ordinary panel for `reinforce_time`. Looking away, switching tool, moving out of
## reach, a charge appearing on it, or being killed cancels it. Only the authority commits the upgrade.
func check_reinforce() -> Dictionary:
	var cam := player.camera.global_transform
	var from := cam.origin
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.basis.z * tuning.place_reach, WALL_MASK,
		[player.get_rid()] as Array[RID])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"ok": false, "reason": "Too far: aim at a wall within %.1f m" % tuning.place_reach}
	var col: Object = hit["collider"]
	if not (col is WallModule) or not (col as WallModule).breakable:
		return {"ok": false, "reason": "Can't reinforce this surface"}
	var m := col as WallModule
	if m.state != WallModule.State.INTACT:
		return {"ok": false, "reason": "Already breached"}
	if m.material == WallModule.Mat.REINFORCED:
		return {"ok": false, "reason": "Already reinforced"}
	if m.charge != null and is_instance_valid(m.charge):
		return {"ok": false, "reason": "A charge is armed here"}
	return {"ok": true, "reason": "", "module": m}


## Hold fire for `heal_time`: restores 50 health on the authority, spends one medkit. Damage, release or
## switching cancels it (NetMatch calls cancel_use() on a hit).
func _heal(delta: float) -> void:
	if int(charges[Tool.MEDKIT]) <= 0:
		if _fire_armed:
			_reject("No medkits")
		_fire_armed = false
		return
	if not _fire_armed and install_left <= 0.0:
		return
	if install_left <= 0.0:
		install_left = HEAL_TIME
	_fire_armed = false
	install_left -= delta
	if presentation:
		_say("Healing... %d%%" % int(100.0 * (1.0 - maxf(install_left, 0.0) / HEAL_TIME)))
	if install_left > 0.0:
		return
	install_left = 0.0
	if authority:
		charges[Tool.MEDKIT] = int(charges[Tool.MEDKIT]) - 1
		healed.emit(HEAL_AMOUNT)


func cancel_use() -> void:
	_cancel_install()


func _cancel_install() -> void:
	if install_left > 0.0 and presentation:
		_say("Reinforcement interrupted")
	install_left = 0.0
	_install_module = null


func _install(held: bool, delta: float) -> void:
	if not held:
		_fire_armed = true
		return
	if not _fire_armed and install_left <= 0.0:
		return
	if int(charges[Tool.REINFORCE]) <= 0:
		if _fire_armed:
			_reject("No reinforcement kits")
		_fire_armed = false
		return
	var c := check_reinforce()
	if not c["ok"]:
		if _fire_armed:
			_reject(c["reason"])
		_cancel_install()
		_fire_armed = false
		return
	if authority and reinforce_gate.is_valid():
		var why: String = reinforce_gate.call(owner_id)
		if why != "":
			if _fire_armed:
				_reject(why)
			_fire_armed = false
			return
	if _install_module != c["module"]:
		_install_module = c["module"]
		install_left = tuning.reinforce_time
	_fire_armed = false
	install_left -= delta
	if presentation:
		_say("Reinforcing... %d%%" % int(100.0 * (1.0 - maxf(install_left, 0.0) / tuning.reinforce_time)))
	if install_left > 0.0:
		return
	var m: WallModule = _install_module
	install_left = 0.0
	_install_module = null
	if not authority:
		return # the host commits and replicates; the snapshot corrects the kit count
	if m.reinforce():
		charges[Tool.REINFORCE] = int(charges[Tool.REINFORCE]) - 1
		reinforced.emit(m)
		if presentation:
			ProcAudio.play(world, "beep")
			_say("Panel reinforced: needs a heavy charge")


func _on_detonated(c: Charge) -> void:
	active_charges.erase(c)
	if effects:
		effects.burst(c.global_position, c.normal, c.kind == WallModule.Kind.HEAVY)
	_say("Breach!")


func _reject(text: String) -> void:
	if presentation:
		ProcAudio.play(world, "reject")
	_say(text)


## Message line on the HUD (also used by NetMatch for host replies).
func say(text: String) -> void:
	_say(text)


func _say(text: String) -> void:
	last_message = text
	_msg_left = 2.5 if text != "" else 0.0
	if _msg_label:
		_msg_label.text = text


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LoadoutHud"
	world.add_child(layer)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	layer.add_child(_canvas)
	_ammo_label = _hud_label(layer, Control.PRESET_BOTTOM_RIGHT, Vector2(-460, -140), 22)
	_ammo_label.custom_minimum_size.x = 440
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_msg_label = _hud_label(layer, Control.PRESET_CENTER_BOTTOM, Vector2(-250, -130), 20)
	_msg_label.custom_minimum_size.x = 500
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label = _hud_label(layer, Control.PRESET_CENTER_TOP, Vector2(-250, 40), 26)
	_warn_label.custom_minimum_size.x = 500
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.modulate = Color(1.0, 0.35, 0.25)


func _hud_label(layer: CanvasLayer, preset: int, off: Vector2, size: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position += off
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(l)
	return l


func _hud_visible() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and player.camera.current


func _update_hud() -> void:
	var show := _hud_visible()
	_ammo_label.visible = show
	_msg_label.visible = show
	_warn_label.visible = show
	if is_gun():
		_ammo_label.text = "%s  %d / %d%s" % [String(Weapons.DEFS[weapon_id()].name).to_upper(), mag, reserve, "  (reloading)" if reloading else ""]
	elif tool == Tool.HOLSTER:
		_ammo_label.text = "EMPTY HANDS · 1 primary / 2 sidearm"
	elif tool == Tool.BOMB:
		_ammo_label.text = "BOMB · hold %s inside A or B to plant" % Keys.key("primary_fire")
	else:
		_ammo_label.text = "%s  x%d" % [["", "ORDINARY CHARGE", "HEAVY CHARGE", "REINFORCEMENT KIT", "", "MEDKIT", "FRAG", "FLASH", "SMOKE", "INCENDIARY"][tool], int(charges[tool])]
	if armor > 0 or helmet:
		_ammo_label.text += "\nARMOR %d%s" % [armor, " + HELMET" if helmet else ""]
	var grenades := []
	for t in range(Tool.FRAG, Tool.INCENDIARY + 1):
		if int(charges.get(t, 0)) > 0:
			grenades.append("%s ×%d" % [tool_key(t), charges[t]])
	if not grenades.is_empty():
		_ammo_label.text += "\n%s: %s" % [Keys.key("grenade_cycle"), ", ".join(grenades)]
	if gadgets_owned:
		_ammo_label.text += "\n" + ("L Light  " if gadgets_owned & 1 else "") + ("K Laser  " if gadgets_owned & 2 else "") + ("N NVG  " if gadgets_owned & 4 else "") + ("SILENCED" if gadgets_owned & 8 else "")
	if zip_ties > 0:
		_ammo_label.text += "\nZIP TIES %d (hold %s on a closed door)" % [zip_ties, Keys.key("zip_tie")]
	var warn := ""
	for c: Charge in world.get_tree().get_nodes_in_group("charges"):
		if is_instance_valid(c) and c.left > 0.0:
			var near := c.global_position.distance_to(player.global_position) < tuning.warn_radius
			warn = "CHARGE %.1f s%s" % [c.left, "  BACK AWAY!" if near else ""]
	_warn_label.text = warn


func _draw_hud() -> void:
	if not _hud_visible():
		return
	var c := _canvas.size * 0.5
	var col := Color(1, 1, 1, 0.85)
	var sc := viewmodel.scope_amount() if viewmodel else 0.0
	if sc > 0.0:
		# scope overlay: black surround with a round window, fine crosshair and mil ticks
		var r := _canvas.size.y * 0.44
		var w := _canvas.size.length()
		var black := Color(0, 0, 0, sc)
		_canvas.draw_arc(c, r + w * 0.5, 0.0, TAU, 96, black, w)
		_canvas.draw_arc(c, r, 0.0, TAU, 96, Color(0.02, 0.02, 0.02, sc), 6.0, true)
		var lc := Color(0, 0, 0, 0.9 * sc)
		_canvas.draw_line(c + Vector2(-r, 0), c + Vector2(-8, 0), lc, 1.5)
		_canvas.draw_line(c + Vector2(8, 0), c + Vector2(r, 0), lc, 1.5)
		_canvas.draw_line(c + Vector2(0, 8), c + Vector2(0, r), lc, 1.5)
		_canvas.draw_line(c + Vector2(0, -r), c + Vector2(0, -8), lc, 1.5)
		for i in range(1, 6):
			_canvas.draw_line(c + Vector2(i * r * 0.1, -4), c + Vector2(i * r * 0.1, 4), lc, 1.5)
			_canvas.draw_line(c + Vector2(-i * r * 0.1, -4), c + Vector2(-i * r * 0.1, 4), lc, 1.5)
			_canvas.draw_line(c + Vector2(-4, i * r * 0.1), c + Vector2(4, i * r * 0.1), lc, 1.5)
		_canvas.draw_circle(c, 1.5, Color(1, 0.15, 0.1, sc))
		return
	if tool in [Tool.ORDINARY_CHARGE, Tool.HEAVY_CHARGE, Tool.REINFORCE]:
		var ok: bool = (check_reinforce() if tool == Tool.REINFORCE else check_placement(tool))["ok"]
		col = Color(0.3, 1.0, 0.4, 0.9) if ok else Color(1.0, 0.35, 0.3, 0.9)
		_canvas.draw_arc(c, 9.0, 0.0, TAU, 24, col, 2.0)
		return
	# ADS uses the gun's actual iron/optical sights; reserve the generic crosshair for hip fire.
	if not aiming:
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_canvas.draw_line(c + d * 7.0, c + d * 14.0, col, 2.0)
	if hit_marker > 0.0:
		var hc := Color(1.0, 0.25, 0.2) if _hit_kill else (Color(1.0, 0.83, 0.55) if _hit_head else Color.WHITE)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_canvas.draw_line(c + d * 8.0, c + d * 15.0, hc, 2.0)
		if _hit_head:
			_canvas.draw_string(ThemeDB.fallback_font, c + Vector2(-32.0, 32.0), "HEADSHOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hc)
