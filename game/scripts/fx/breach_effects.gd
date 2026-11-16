class_name BreachEffects
extends Node3D
## Cosmetic, local, nonblocking breach effects (dust + chunk particles + boom). Hard-capped.

const MAX_BURSTS := 3
const DUST_AMOUNT := 48
const CHUNK_AMOUNT := 14
const LIFETIME := 1.4

var active := 0
var _gen := 0 ## bumps on clear() so stale timers don't corrupt `active`


func burst(pos: Vector3, normal: Vector3, heavy: bool, silent: bool = false) -> bool:
	if active >= MAX_BURSTS:
		return false
	active += 1
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	root.add_child(_particles(DUST_AMOUNT, 0.35 if heavy else 0.25, Color(0.72, 0.69, 0.64, 0.55), Vector3(0, 0.3, 0), 0.5, 2.2, true))
	root.add_child(_particles(CHUNK_AMOUNT, 0.07, Color(0.45, 0.43, 0.4, 1.0), Vector3(0, -9.0, 0), 1.5, 4.5, false))
	if not silent:
		ProcAudio.play(root, "boom", pos, 4.0 if heavy else 0.0)
	var timer := Timer.new() ## child of root, so clear() frees it along with the burst
	timer.one_shot = true
	timer.wait_time = LIFETIME
	root.add_child(timer)
	timer.timeout.connect(_burst_done.bind(root, _gen))
	timer.start()
	return true


func _burst_done(root: Node3D, gen: int) -> void:
	if gen == _gen:
		active -= 1
	root.queue_free()


func clear() -> void:
	_gen += 1
	active = 0
	for c in get_children():
		c.free()


func _particles(amount: int, size: float, col: Color, grav: Vector3, v0: float, v1: float, fade: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = LIFETIME
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = grav
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	if fade:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.8))
		g.set_color(1, Color(1, 1, 1, 0.0))
		p.color_ramp = g
		var s := SphereMesh.new()
		s.radius = size
		s.height = size * 2.0
		s.material = m
		p.mesh = s
	else:
		var b := BoxMesh.new()
		b.size = Vector3.ONE * size
		b.material = m
		p.mesh = b
	p.emitting = true
	return p
