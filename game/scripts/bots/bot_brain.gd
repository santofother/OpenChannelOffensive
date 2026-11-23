class_name BotBrain
extends RefCounted
## One bot's decisions, turned into the same NetCmd a person's keyboard produces. The host runs it through
## the normal authority path (round rules, phase/role locks, recoil, hit validation), so bots cannot do
## anything a player could not.
##
## Priorities each tick: fight a visible enemy > follow a teammate's order (comms) > investigate a sound or
## a teammate's enemy callout > the role default (carry/plant/recover the bomb, take or hold a site,
## reinforce site walls during prep, defuse).

const SEE_RANGE := 45.0
const FOV_COS := 0.5 ## ±60° from the view axis.
const ORDER_TICKS := 60 * 60 ## comms orders last a minute unless replaced or cleared

var id := 0
var net: NetMatch
var dir: BotDirector
var skill := 0.6 ## 0..1: reaction time, aim error, turn speed, trigger discipline
var rng := RandomNumberGenerator.new()
var index := 0 ## position within its team (spreads bots around sites)

## Orders from comms: {kind: "move"|"hold"|"follow"|"backup"|"fall_back"|"enemy", pos, who, until}
var order := {}
var investigate := Vector3.INF
var investigate_until := 0
var support_pos := Vector3.INF
var support_until := 0

var _yaw := 0.0
var _pitch := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF
var _door_path := PackedVector3Array()
var _door_path_until := 0
var _repath := 0.0
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _unstick := 0.0
var _unstick_dir := 0.0
var _target := 0
var _target_seen := -1000
var _last_seen := Vector3.ZERO
var _aim_seen := Vector3.ZERO
var _visible := false
var _react := 0.0
var _aim_err := Vector2.ZERO
var _burst_shots := 0
var _next_shot := 0
var _strafe := 1.0
var _strafe_left := 0.0
var _crouch_fight := false
var _scan_t := 0.0
var _scan_base := 0.0
var _perceive_in := 0
var _heard_step := Vector3.INF
var _step_look_until := 0
var _wall: WallModule
var _wall_t := 0.0
var _walls_done := 0


func _init(bot_id: int, owner_match: NetMatch, director: BotDirector, bot_skill: float, team_index: int) -> void:
	id = bot_id
	net = owner_match
	dir = director
	skill = bot_skill
	index = team_index
	rng.seed = hash([bot_id, Time.get_ticks_usec()])


func new_round() -> void:
	order.clear()
	investigate = Vector3.INF
	investigate_until = 0
	support_pos = Vector3.INF
	_target = 0
	_visible = false
	_heard_step = Vector3.INF
	_step_look_until = 0
	_scan_t = 0.0
	_path = PackedVector3Array()
	_path_goal = Vector3.INF
	_door_path.clear()
	_wall = null
	_walls_done = 0


func set_order(o: Dictionary) -> void:
	order = o
	order["until"] = net.tick + ORDER_TICKS
	_path_goal = Vector3.INF


func has_order() -> bool:
	return not order.is_empty() and net.tick < int(order.get("until", 0))


func target_id() -> int:
	return _target


# ------------------------------------------------------------------ command

func make_cmd(s: NetMatch.Slot) -> NetCmd:
	var c := NetCmd.new()
	var p := s.node
	_yaw = p.rotation.y # includes recoil kicks the host applied to this body
	_pitch = p.pitch()
	c.tool = Loadout.Tool.RIFLE
	if not s.alive or not net.loop.enabled:
		_finish(c)
		return c
	var rules := net.loop.rules
	if rules.phase in [RoundRules.Phase.LOBBY, RoundRules.Phase.RESOLUTION, RoundRules.Phase.RESULT]:
		_target = 0
		_finish(c)
		return c
	var attacker := s.team == rules.attack_team
	if rules.phase != RoundRules.Phase.PREP:
		_perceive_in -= 1
		if _perceive_in <= 0:
			_perceive_in = 3
			_perceive(s)
	if _target != 0 and rules.phase != RoundRules.Phase.PREP and not _retake_first(s, attacker):
		_fight(s, c)
	elif rules.phase == RoundRules.Phase.PREP:
		if not attacker:
			_prep_defend(s, c)
	else:
		_objective(s, c, attacker)
		if net.tick < _step_look_until and _heard_step != Vector3.INF and not c.interact and c.tool != Loadout.Tool.BOMB:
			# Turn toward a footstep without abandoning movement or a teammate's order.
			var move := Basis(Vector3.UP, _yaw) * Vector3(c.move.x, 0, c.move.y)
			_yaw = p.rotation.y
			_turn_to(_eye(s), _heard_step + Vector3.UP * 0.75, 300.0)
			_set_move(c, move)
	_finish(c)
	return c


func _finish(c: NetCmd) -> void:
	c.yaw = _yaw
	c.pitch = _pitch


# ------------------------------------------------------------------ senses

func _eye(s: NetMatch.Slot) -> Vector3:
	return s.node.camera.global_position


func _chest(o: NetMatch.Slot) -> Vector3:
	return o.node.global_position + Vector3(0, o.node.height * 0.64, 0) + o.node.lean_offset() * 0.64


func clear_line(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return net.g.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _perceive(s: NetMatch.Slot) -> void:
	var eye := _eye(s)
	var fwd := -s.node.camera.global_basis.z
	var best := 0
	var best_d := INF
	var best_score := INF
	var best_aim := Vector3.ZERO
	for o: NetMatch.Slot in net.slots.values():
		if o.team == s.team or not o.alive:
			continue
		var tgt := _chest(o)
		var d := eye.distance_to(tgt)
		var moving := Vector2(o.node.velocity.x, o.node.velocity.z).length_squared() > 3.0
		var attended := net.tick < _step_look_until and tgt.distance_to(_heard_step) < 5.0
		var angle_cos := FOV_COS - (0.13 if moving else 0.0) - (0.10 if attended else 0.0)
		var range_limit := SEE_RANGE + (5.0 if moving else 0.0) - (8.0 if o.node.crouched and not attended else 0.0)
		if d > range_limit or fwd.dot((tgt - eye).normalized()) <= angle_cos:
			continue
		var head := o.node.global_position + Vector3(0, o.node.height - 0.12, 0) + o.node.lean_offset()
		# Require a visible part of the model. Where only the head peeks out, aim at that part.
		var chest_visible: bool = clear_line(eye, tgt) and not net.g.gadgets.blocks_vision(eye, tgt)
		var score := d * (0.72 if o.id == _target else 1.0)
		if score < best_score and (chest_visible or (clear_line(eye, head) and not net.g.gadgets.blocks_vision(eye, head))):
			best = o.id
			best_d = d
			best_score = score
			best_aim = tgt if chest_visible else head
	_visible = best != 0
	if best != 0:
		if best != _target:
			_react = lerpf(0.58, 0.26, skill) + rng.randf_range(0.02, 0.10)
			_aim_err = _new_aim_error(best_d)
			_crouch_fight = best_d > 12.0 and rng.randf() < 0.35
			_burst_shots = 0
			_next_shot = net.tick
			dir.saw_enemy(id, net.slots[best])
		_target = best
		_target_seen = net.tick
		_last_seen = net.slots[best].node.global_position
		_aim_seen = best_aim
	elif _target != 0 and (net.tick - _target_seen > 27 or not net.slots.has(_target) or not net.slots[_target].alive):
		var lost_alive: bool = net.slots.has(_target) and net.slots[_target].alive
		_target = 0
		if lost_alive:
			hear(_last_seen, 5.0) # lost sight: check the last place they were


## Footsteps prompt a short look without overwriting an active, higher-confidence sound or callout.
func hear_footstep(pos: Vector3) -> void:
	if _target == 0 and net.tick >= investigate_until:
		_heard_step = pos
		_step_look_until = net.tick + 48


## A shot, explosion or callout worth turning toward / walking to.
func hear(pos: Vector3, seconds: float) -> void:
	if _target != 0:
		return
	_heard_step = pos
	_step_look_until = net.tick + 54
	investigate = pos
	investigate_until = net.tick + int(seconds * NetMatch.TICK_RATE)
	_path_goal = Vector3.INF


func support(pos: Vector3) -> void:
	support_pos = pos
	support_until = net.tick + 9 * NetMatch.TICK_RATE


# ------------------------------------------------------------------ combat

func _fight(s: NetMatch.Slot, c: NetCmd) -> void:
	if not net.slots.has(_target) or not net.slots[_target].alive:
		_target = 0
		return
	var dt := NetMatch.DT
	var lo := s.lo
	var eye := _eye(s)
	var aim_at := _aim_seen
	var dist := eye.distance_to(aim_at)
	var err := _turn_to(eye, aim_at, lerpf(170.0, 300.0, skill), _aim_err)
	if _visible:
		_react -= dt
	# Guns: prefer the primary, fall back to the sidearm when it is dry.
	c.tool = Loadout.Tool.RIFLE
	if lo.tool == Loadout.Tool.RIFLE and lo.primary != "" and lo.mag == 0 and lo.reserve == 0:
		c.tool = Loadout.Tool.SIDEARM
	c.aim = dist > 9.0 and not lo.reloading
	if lo.is_gun() and lo.mag == 0:
		c.reload = true
		if lo.reserve > 0:
			dir.reload_comms(s)
	if _react <= 0.0 and _visible and net.tick >= _next_shot and err < deg_to_rad(3.5) \
			and lo.mag > 0 and not lo.reloading and clear_line(eye, aim_at) and not net.g.gadgets.blocks_vision(eye, aim_at):
		c.fire = true
		_burst_shots += 1
		var spacing := lo.tuning.fire_interval + NetMatch.DT * 2.0
		if lo.tuning.auto and _burst_shots < (4 if dist < 13.0 else 3):
			spacing = maxf(0.11, spacing)
		else:
			_burst_shots = 0
			spacing = maxf(spacing, rng.randf_range(0.24, 0.43))
			_aim_err = _new_aim_error(dist)
		_next_shot = net.tick + int(ceilf(spacing * NetMatch.TICK_RATE))
	# Footwork: strafe, sometimes crouch at range, close in on distant enemies.
	_strafe_left -= dt
	if _strafe_left <= 0.0:
		_strafe = -_strafe if rng.randf() < 0.7 else _strafe
		_strafe_left = rng.randf_range(0.45, 1.1)
	var basis := Basis(Vector3.UP, _yaw)
	var move := basis.x * _strafe * 0.8
	if dist > 24.0:
		move += -basis.z * 0.7
	if not clear_line(s.node.global_position + Vector3(0, 0.5, 0), s.node.global_position + Vector3(0, 0.5, 0) + move.normalized() * 0.8):
		_strafe = -_strafe
		move = basis.x * _strafe * 0.8
	c.crouch = _crouch_fight and c.fire
	if not c.crouch:
		_set_move(c, move)
	# Being seen while carrying the bomb near a site: finish the plant only when the fight is over.


func _new_aim_error(distance: float) -> Vector2:
	var spread := deg_to_rad(lerpf(3.4, 1.6, skill)) * clampf(11.0 / maxf(distance, 1.0), 0.4, 1.0)
	return Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * spread


# ------------------------------------------------------------------ objectives

func _objective(s: NetMatch.Slot, c: NetCmd, attacker: bool) -> void:
	var rules := net.loop.rules
	var pos := s.node.global_position
	# The carrier plants as soon as it stands inside any site, whatever led it there.
	if attacker and rules.carrier == id and rules.phase == RoundRules.Phase.LIVE:
		if rules.tuning.site_at(pos) >= 0 and s.node.is_on_floor():
			# Like a player: select the bomb in slot 5 and hold fire to plant.
			_look_toward(s, pos + Vector3.FORWARD + Vector3(0, 0.15, 0))
			c.move = Vector2.ZERO
			c.tool = Loadout.Tool.BOMB
			c.fire = s.lo.tool == Loadout.Tool.BOMB and s.node.velocity.length() < 0.6
			return
	# Defenders standing at a planted bomb always defuse, whatever their orders.
	if not attacker and rules.phase == RoundRules.Phase.PLANTED \
			and net.loop.objective_available(id):
		_hold_interact(s, c, rules.bomb_pos)
		return
	# After the plant, defenders go for the bomb ahead of orders, backup calls and noises.
	if not attacker and rules.phase == RoundRules.Phase.PLANTED:
		_defend_default(s, c)
		return
	if has_order():
		if _do_order(s, c):
			return
	elif not order.is_empty():
		order.clear()
	if support_pos != Vector3.INF and net.tick < support_until and pos.distance_to(support_pos) > 2.4:
		_go(s, c, support_pos, true)
		return
	support_pos = Vector3.INF
	if investigate != Vector3.INF and net.tick < investigate_until:
		var sound := investigate
		if _eye(s).distance_to(sound) > 3.0 and not clear_line(_eye(s), sound):
			_go(s, c, investigate, false)
		else:
			_look_toward(s, sound)
		return
	investigate = Vector3.INF
	if attacker:
		_attack_default(s, c)
	else:
		_defend_default(s, c)


## A planted defender drops a fight with an unseen enemy, or any fight once only
## the defuse time (plus a short walk) is left on the fuse.
func _retake_first(s: NetMatch.Slot, attacker: bool) -> bool:
	var rules := net.loop.rules
	if attacker or rules.phase != RoundRules.Phase.PLANTED:
		return false
	if not _visible:
		return true
	var kit: bool = s.lo.defuse_kit
	var needed := rules.tuning.defuse * (rules.tuning.defuse_with_kit if kit else rules.tuning.defuse_without_kit) + 3.0
	var left := float(rules.deadline - net.tick) / NetMatch.TICK_RATE
	return left <= needed


func _attack_default(s: NetMatch.Slot, c: NetCmd) -> void:
	var rules := net.loop.rules
	if rules.phase == RoundRules.Phase.PLANTED:
		_hold_near(s, c, rules.bomb_pos, 5.0)
		return
	if rules.carrier == 0 and dir.retriever(s.team) == id:
		# Dropped bomb: the nearest attacker bot picks it up.
		if s.node.global_position.distance_to(rules.bomb_pos) <= rules.tuning.interact_range * 0.55:
			_hold_interact(s, c, rules.bomb_pos)
		else:
			_go(s, c, rules.bomb_pos, true)
		return
	var site := dir.attack_site(s.team)
	if rules.carrier == id:
		_go(s, c, site, true)
	else:
		_hold_near(s, c, site + _spread(2.5), 1.2)


func _defend_default(s: NetMatch.Slot, c: NetCmd) -> void:
	var rules := net.loop.rules
	if rules.phase == RoundRules.Phase.PLANTED:
		var found := dir.bomb_location()
		_go(s, c, found if found != Vector3.INF else dir.plant_search(index), true)
		return
	_hold_near(s, c, dir.defend_point(s.team, index), 1.0)


## Defenders spend prep reinforcing walls around their site, then take their position.
func _prep_defend(s: NetMatch.Slot, c: NetCmd) -> void:
	if has_order():
		_do_order(s, c)
		return
	if int(s.lo.charges[Loadout.Tool.REINFORCE]) > 0 and _walls_done < 4:
		if _wall == null or _wall.material != WallModule.Mat.ORDINARY or _wall.state != WallModule.State.INTACT:
			if _wall != null:
				_walls_done += 1
				dir.release_wall(_wall)
			_wall = dir.claim_wall(id, dir.defend_site(s.team, index), s.node.global_position)
			_wall_t = 0.0
		if _wall:
			var stand := dir.wall_stand_point(_wall, dir.defend_site(s.team, index))
			if _flat(s.node.global_position, stand) > 0.35:
				_go(s, c, stand, true)
				_wall_t += NetMatch.DT
				if _wall_t > 9.0: # unreachable: give it up
					dir.release_wall(_wall)
					_wall = null
					_walls_done += 1
				return
			var aim := _wall.global_position + Vector3(0, 1.25 - _wall.global_position.y, 0)
			var err := _turn_to(_eye(s), aim, 400.0)
			c.tool = Loadout.Tool.REINFORCE
			c.fire = err < deg_to_rad(6.0)
			_wall_t += NetMatch.DT
			if _wall_t > 14.0:
				dir.release_wall(_wall)
				_wall = null
				_walls_done += 1
			return
	_defend_default(s, c)


func _do_order(s: NetMatch.Slot, c: NetCmd) -> bool:
	var kind := String(order.get("kind", ""))
	var goal: Vector3 = order.get("pos", s.node.global_position)
	match kind:
		"move":
			var carrier := net.loop.rules.carrier == id
			_hold_near(s, c, goal + (Vector3.ZERO if carrier else _spread(1.4)), 0.5 if carrier else 1.0)
		"enemy":
			if _flat(s.node.global_position, goal) > 4.0 and not clear_line(_eye(s), goal + Vector3(0, 1.0, 0)):
				_go(s, c, goal, true)
			else:
				_look_toward(s, goal + Vector3(0, 1.0, 0))
		"follow", "backup":
			var who := int(order.get("who", 0))
			if not net.slots.has(who) or not net.slots[who].alive:
				order.clear()
				return false
			var leader: Vector3 = net.slots[who].node.global_position
			if s.node.global_position.distance_to(leader) > 2.6:
				_go(s, c, leader, kind == "backup" or _flat(s.node.global_position, leader) > 8.0)
			else:
				_scan(s)
		"hold":
			_hold_near(s, c, goal, 0.8)
		"fall_back":
			var sp := net.spawn_for(s)
			_hold_near(s, c, sp[0], 1.2)
		_:
			return false
	return true


# ------------------------------------------------------------------ movement helpers

func _spread(radius: float) -> Vector3:
	var a := index * TAU / 3.0 + 0.6
	return Vector3(cos(a), 0, sin(a)) * radius


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _hold_near(s: NetMatch.Slot, c: NetCmd, goal: Vector3, radius: float) -> void:
	var distance := s.node.global_position.distance_to(goal)
	if distance > radius:
		_go(s, c, goal, distance > 6.0)
	else:
		_scan(s)


## Stand still on the objective and hold interact (plant / defuse / recover need a stationary player).
func _hold_interact(s: NetMatch.Slot, c: NetCmd, at: Vector3) -> void:
	_look_toward(s, at + Vector3(0, 0.15, 0))
	c.move = Vector2.ZERO
	c.interact = s.node.velocity.length() < 0.6


## Slowly sweep the view around a base direction while holding a spot.
func _scan(s: NetMatch.Slot) -> void:
	if _scan_t <= 0.0:
		_scan_t = 1.4
		_scan_base = _yaw + rng.randf_range(-1.6, 1.6)
	_scan_t -= NetMatch.DT
	_yaw = rotate_toward(_yaw, _scan_base, deg_to_rad(90.0) * NetMatch.DT)
	_pitch = move_toward(_pitch, 0.0, deg_to_rad(90.0) * NetMatch.DT)


func _look_toward(s: NetMatch.Slot, point: Vector3) -> void:
	_turn_to(_eye(s), point, 360.0)


## Turns view toward `point` at a limited rate (deg/s). Returns the remaining angle (radians) to the true point.
func _turn_to(eye: Vector3, point: Vector3, rate_deg: float, err: Vector2 = Vector2.ZERO) -> float:
	var d := point - eye
	var flat := Vector2(d.x, d.z).length()
	var want_yaw := atan2(-d.x, -d.z) + err.x
	var want_pitch := clampf(atan2(d.y, flat) + err.y, -1.3, 1.3)
	var step := deg_to_rad(rate_deg) * NetMatch.DT
	_yaw = rotate_toward(_yaw, want_yaw, step)
	_pitch = rotate_toward(_pitch, want_pitch, step * 0.8)
	return Vector2(angle_difference(_yaw, want_yaw - err.x), angle_difference(_pitch, want_pitch - err.y)).length()


## World-space wish direction -> local NetCmd move (x right, y back) for the yaw this command will carry.
func _set_move(c: NetCmd, world_dir: Vector3) -> void:
	var b := Basis(Vector3.UP, _yaw)
	world_dir.y = 0.0
	c.move = Vector2(world_dir.dot(b.x), world_dir.dot(b.z)).limit_length(1.0)


## The baked mesh sees an open doorway. A solid leaf can still block the turn
## just beyond it. Go around the exposed tip from the side the bot is on.
func _door_direction(s: NetMatch.Slot, fallback: Vector3) -> Vector3:
	var pos := s.node.global_position
	if not _door_path.is_empty():
		if net.tick >= _door_path_until:
			_door_path.clear()
		elif _flat(pos, _door_path[0]) < 0.23:
			_door_path.remove_at(0)
		if not _door_path.is_empty():
			return _door_path[0] - pos
		_repath = 0.0
		return fallback
	if not net.g.doors:
		return fallback
	for i in s.node.get_slide_collision_count():
		var hit := s.node.get_slide_collision(i)
		var body := hit.get_collider() as Node3D
		if body == null or not body.has_meta("door_id") or fallback.dot(hit.get_normal()) >= 0.0:
			continue
		var door: DoorSystem.Door = net.g.doors.doors[int(body.get_meta("door_id"))]
		if door.broken or absf(door.angle) < DoorSystem.OPEN_ANGLE - 0.1:
			continue
		var along := body.global_basis.x
		var across := along.cross(Vector3.UP)
		var side := across * signf((pos - door.hinge).dot(across)) * 0.55
		var tip := door.hinge + along * (door.width + 0.55)
		_door_path = PackedVector3Array([tip + side, tip - side])
		_door_path_until = net.tick + 150
		_unstick = 0.0
		return _door_path[0] - pos
	return fallback


## Walk along the navigation path to `goal`, facing where it walks.
func _go(s: NetMatch.Slot, c: NetCmd, goal: Vector3, urgent: bool) -> void:
	_scan_t = 0.0
	var dt := NetMatch.DT
	var pos := s.node.global_position
	_repath -= dt
	if _path_goal == Vector3.INF or _path_goal.distance_to(goal) > 0.75 or _repath <= 0.0:
		_path = dir.nav.path(pos, goal)
		_path_i = 0
		_path_goal = goal
		_repath = 2.0
	while _path_i < _path.size() and _path[_path_i].distance_to(pos) < 0.55:
		_path_i += 1
	var wp := goal if _path_i >= _path.size() else _path[_path_i]
	var to := _door_direction(s, wp - pos)
	to.y = 0.0
	if to.length() < 0.05:
		return
	to = to.normalized()
	# Unstick: a short sidestep when no progress was made (door frames, other players).
	_stuck_t += dt
	if _stuck_t > 0.8:
		if pos.distance_to(_stuck_pos) < 0.2 and _door_path.is_empty():
			_unstick = 0.5
			_unstick_dir = -1.0 if rng.randf() < 0.5 else 1.0
			_repath = 0.0
		_stuck_t = 0.0
		_stuck_pos = pos
	var face := pos + to * 4.0 + Vector3(0, s.node.height - 0.15, 0)
	_turn_to(_eye(s), face, 420.0)
	var move := to
	if _unstick > 0.0:
		_unstick -= dt
		move = (to + Basis(Vector3.UP, _yaw).x * _unstick_dir * 1.2).normalized()
	_set_move(c, move)
	c.slow_walk = not urgent and to.dot(-Basis(Vector3.UP, _yaw).z) > 0.85 and _flat(pos, goal) < 5.0 and _unstick <= 0.0
