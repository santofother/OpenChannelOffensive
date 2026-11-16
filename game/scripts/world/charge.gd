class_name Charge
extends Node3D
## Placed breach charge: visible countdown label, beeps (faster at the end), then breaches its module.
## Only an authoritative charge (offline/host) breaches; a replicated client copy just counts down and waits
## for the host's wall event (NetMatch frees it).

signal detonated(charge: Charge)

var module: WallModule
var charge_id := 0
var owner_id := 1
var authoritative := true
## Replicated copies follow the host clock: returns seconds left (NetMatch). Unset = count down locally.
var clock: Callable
var kind := WallModule.Kind.ORDINARY
var normal := Vector3.RIGHT
var left := 3.0
var _label: Label3D
var _last_sec := 99
var _beep_gap := 0.0


func setup(m: WallModule, k: int, fuse: float, pos: Vector3, n: Vector3) -> void:
	add_to_group("charges")
	module = m
	kind = k
	normal = n
	left = fuse
	var heavy := k == WallModule.Kind.HEAVY
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.3, 0.1) if heavy else Vector3(0.25, 0.18, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.1, 0.08) if heavy else Color(0.9, 0.55, 0.1)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.6
	bm.material = mat
	mi.mesh = bm
	mi.position = Vector3(0, 0, bm.size.z * 0.5)
	add_child(mi)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.004
	_label.modulate = Color(1.0, 0.3, 0.2)
	_label.position = Vector3(0, 0.3, 0.15)
	add_child(_label)
	# Orient so local +Z points out of the wall.
	global_transform = Transform3D(Basis.looking_at(-n, Vector3.UP), pos + n * 0.01)
	_update_label()


func _process(delta: float) -> void:
	if clock.is_valid():
		left = minf(left, maxf(float(clock.call()), 0.0))
	else:
		left -= delta
	_beep_gap -= delta
	var sec := int(ceilf(left))
	if left <= 1.0:
		if _beep_gap <= 0.0:
			ProcAudio.play(self, "beep", global_position, 2.0)
			_beep_gap = 0.2
	elif sec != _last_sec:
		ProcAudio.play(self, "beep", global_position)
	_last_sec = sec
	_update_label()
	if left <= 0.0:
		set_process(false)
		if not authoritative:
			return
		module.charge = null
		module.breach(kind)
		detonated.emit(self)
		queue_free()


func _update_label() -> void:
	_label.text = "%.1f" % maxf(left, 0.0)
