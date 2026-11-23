class_name ProcAudio
extends RefCounted
## Original procedural samples cached once. Profiles describe duration, pitch, noise, decay and peak.
const RATE := 22050
enum Gait { WALK, SLOW, CROUCH, RUN }
const STEP_STRIDE := [0.86, 0.74, 0.67, 0.87]
const STEP_RANGE := [32.0, 4.5, 2.2, 44.0]
const STEP_GAIN := [4.0, -22.0, -30.0, 8.0]
const DEFS := {
	"creak": [0.46, 106.0, 0.34, 5.0, 0.32],
	"latch": [0.10, 290.0, 0.55, 32.0, 0.35],
	"handle_release": [0.22, 460.0, 0.73, 13.0, 0.42],
	"kick": [0.17, 74.0, 0.72, 19.0, 0.50],
	"kick_1": [0.16, 67.0, 0.73, 20.0, 0.50],
	"kick_2": [0.19, 74.0, 0.78, 17.0, 0.51],
	"kick_3": [0.23, 82.0, 0.83, 13.0, 0.52],
	"door_break": [0.44, 94.0, 0.76, 8.0, 0.56],
	"rattle": [0.24, 280.0, 0.68, 10.0, 0.36],
	"zip": [0.24, 1330.0, 0.80, 9.0, 0.30],
	"dry": [0.05, 860.0, 0.35, 69.0, 0.24],
	"mag_out": [0.14, 265.0, 0.68, 20.0, 0.28],
	"mag_in": [0.12, 154.0, 0.62, 24.0, 0.36],
	"action": [0.13, 540.0, 0.76, 23.0, 0.32],
	"cylinder_open": [0.13, 400.0, 0.72, 20.0, 0.33],
	"cylinder_load": [0.21, 780.0, 0.72, 11.0, 0.32],
	"cylinder_close": [0.11, 245.0, 0.62, 29.0, 0.40],
	"buy": [0.14, 620.0, 0.23, 15.0, 0.30],
	"beep": [0.09, 1250.0, 0.0, 23.0, 0.26],
	"boom": [0.55, 78.0, 0.72, 7.8, 0.65],
	"boom_heavy": [0.78, 51.0, 0.70, 5.6, 0.72],
	"wall_rupture": [0.29, 120.0, 0.91, 12.0, 0.31],
	"cover_break": [0.38, 185.0, 0.84, 10.0, 0.50],
	"hit": [0.06, 520.0, 0.40, 45.0, 0.32],
	"incoming_impact": [0.26, 86.0, 0.52, 20.0, 0.62],
	"reject": [0.18, 170.0, 0.10, 14.0, 0.28],
	"smoke_burst": [.52, 130.0, .98, 6.0, .58],
	"flash_burst": [.16, 240.0, .90, 27.0, .64],
	"fire_burst": [.48, 85.0, .84, 7.0, .65],
	"defuse_work": [.16, 220.0, .86, 17.0, .55],
	"bomb_drop": [0.25, 170.0, 0.72, 13.0, 0.45],
	"bomb_pickup": [0.17, 374.0, 0.48, 19.0, 0.35],
	"plant_start": [0.20, 720.0, 0.23, 11.0, 0.37],
	"defuse_start": [0.23, 440.0, 0.37, 10.0, 0.37],
	"bomb_interrupted": [0.21, 490.0, 0.12, 12.0, 0.39],
	"bomb_planted": [0.46, 870.0, 0.10, 5.0, 0.72],
	"bomb_defused": [0.46, 670.0, 0.14, 5.0, 0.65],
	"bomb_tick": [0.10, 975.0, 0.04, 21.0, 0.42],
	"bomb_urgent": [0.10, 1490.0, 0.04, 20.0, 0.42],
	"round_win": [0.41, 390.0, 0.04, 5.0, 0.39],
	"round_loss": [0.39, 260.0, 0.05, 5.0, 0.37],
	"radio_tx": [0.09, 780.0, 0.64, 28.0, 0.22],
	"radio_rx": [0.07, 570.0, 0.50, 36.0, 0.19],
	"radio_beacon": [.085, 1430.0, .02, 24.0, .17],
	"radio_theft": [0.31, 860.0, 0.09, 8.0, 0.32],
}
## Per-gun body, brightness and tail length, indexed by Weapons.ORDER.
const GUNS := [[175.0, .78, .16], [202.0, .86, .14], [92.0, .64, .28],
	[232.0, .84, .11], [122.0, .79, .23], [99.0, .68, .29], [76.0, .60, .37]]
const SURFACES := ["concrete", "carpet", "metal"]
static var _cache := {}

static func sound_keys() -> Array:
	var keys := DEFS.keys()
	keys.append_array(["cloth_1", "cloth_2"])
	for gun in GUNS.size():
		for mode in ["shot", "outdoor", "quiet", "far"]:
			keys.append("%s_%d" % [mode, gun])
	for surface in SURFACES.size():
		for variant in 6:
			keys.append(step_key(surface, variant))
	return keys

static func step_key(surface: int, variant: int) -> String:
	return "step_%d_%d" % [surface, variant]

static func bus_for(kind: String) -> String:
	if kind.begins_with("step_"):
		return "Movement"
	if kind.begins_with("bomb_") or kind.begins_with("round_") or kind in ["plant_start", "defuse_start", "defuse_work"]:
		return "Objectives"
	if kind.begins_with("kick_") or kind in ["boom", "boom_heavy", "wall_rupture", "cover_break", "creak", "latch", "kick", "rattle", "zip", "door_break", "handle_release", "smoke_burst", "flash_burst", "fire_burst"]:
		return "Breaching"
	if kind.begins_with("radio_") or kind in ["beep", "reject", "buy"]:
		return "Effects"
	return "Weapons"

static func range_for(kind: String) -> float:
	if kind.begins_with("quiet_"):
		return 17.0
	if is_loud_shot(kind):
		return 95.0
	if kind.begins_with("step_"):
		return STEP_RANGE[Gait.WALK]
	if kind in HANDLING or kind in ["latch", "zip"]:
		return 13.0
	if bus_for(kind) in ["Objectives", "Breaching"]:
		return 47.0 if kind in ["boom", "boom_heavy", "wall_rupture"] else 23.0
	return 42.0

static func is_loud_shot(kind: String) -> bool:
	return kind.begins_with("shot_") or kind.begins_with("far_") or kind.begins_with("outdoor_")

static func get_sound(kind: String) -> AudioStream:
	if _cache.has(kind):
		return _cache[kind]
	var fields := kind.split("_")
	var step := kind.begins_with("step_")
	var gun := fields[0] in ["shot", "outdoor", "quiet", "far"]
	if kind.begins_with("bot_radio_"):
		return _sample("res://assets/audio/radio/" + kind.trim_prefix("bot_radio_") + ".wav", kind)
	if kind.begins_with("cloth_"):
		return _sample("res://assets/audio/foley/" + kind + ".wav", kind)
	if step and fields[2].to_int() < 4:
		var sample_path := "res://assets/audio/foley/%s_%d.wav" % [SURFACES[fields[1].to_int()], fields[2].to_int()]
		if ResourceLoader.exists(sample_path):
			return _sample(sample_path, kind)
	var profile: Array = DEFS.get(kind, DEFS["beep"])
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	var smoothing := 0.44
	var scuff := false
	if step:
		var surface := fields[1].to_int()
		scuff = fields[2].to_int() >= 4
		profile = [[.15, 89.0, .67, 18.0, .59], [.11, 68.0, .40, 23.0, .52], [.15, 118.0, .86, 25.0, .54]][surface].duplicate()
		profile[1] *= rng.randf_range(.87, 1.15)
		profile[0] *= rng.randf_range(.91, 1.12)
		smoothing = [.46, .19, .60][surface]
		if scuff:
			profile[2] = .86
			profile[4] *= .51
	elif gun:
		var spec: Array = GUNS[fields[1].to_int()]
		match fields[0]:
			"quiet": profile = [.10, spec[0] * 1.45, .79, 34.0, .43]
			"far": profile = [spec[2] + .12, spec[0] * .71, .61, 12.0, .60]
			_: profile = [spec[2], spec[0], spec[1], 19.0, .76]
		smoothing = .27 if fields[0] == "far" else .74
	var duration := float(profile[0])
	var frequency := float(profile[1])
	var noise_mix := float(profile[2])
	var decay := float(profile[3])
	var gain := float(profile[4])
	var n := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var phase := 0.0
	var rise := kind in ["round_win", "bomb_planted", "radio_theft", "bomb_defused"]
	var fall := kind in ["round_loss", "bomb_interrupted"]
	var pitch_drop := gun or kind.begins_with("boom")
	var reflections := (gun and fields[0] in ["shot", "far"]) or kind in ["boom", "boom_heavy", "wall_rupture", "cover_break", "door_break"]
	var kit := (gun and fields[0] != "far") or step
	var rattle := kind in ["rattle", "zip", "cylinder_load"]
	for i in n:
		var t := float(i) / RATE
		var pitch := frequency
		if rise:
			pitch *= 1.0 if t < duration * .28 else 1.5
		elif fall:
			pitch *= 1.0 if t < duration * .28 else .70
		elif step:
			pitch *= .55 + .7 * exp(-t * 24.0)
		elif pitch_drop:
			pitch *= 0.62 + 0.55 * exp(-t * 36.0)
		elif kind == "creak":
			pitch *= 1.0 + 0.33 * sin(TAU * 7.0 * t)
		phase += TAU * pitch / RATE
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), smoothing)
		var value := sin(phase) * (1.0 - noise_mix) + lp * noise_mix
		var envelope := exp(-t * decay)
		if reflections:
			# Early room return and a short granular tail baked into each sample.
			envelope += .20 * exp(-absf(t - .047) * 49.0) + .09 * exp(-absf(t - .112) * 27.0)
		if kit:
			# Action/kit tick follows the main transient.
			value += lp * .34 * exp(-absf(t - .031) * 145.0)
		if rattle:
			value *= .35 + .65 * absf(sin(TAU * 19.0 * t))
		var fade := minf(t / (.009 if scuff else .0015), 1.0) * minf((duration - t) / .017, 1.0)
		data.encode_s16(i * 2, int(clampf(value * envelope * gain * fade, -1.0, 1.0) * 32767.0))
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = RATE
	sample.data = data
	_cache[kind] = sample
	return sample

static func _sample(path: String, kind: String) -> AudioStream:
	var sample := load(path) as AudioStream
	_cache[kind] = sample
	return sample

static func play(parent: Node, kind: String, pos: Variant = null, volume_db: float = 0.0, bus: String = "", radius: float = 0.0, pitch: float = 1.0) -> void:
	if parent.is_inside_tree():
		parent.get_node("/root/GameAudio").play(parent, kind, pos, volume_db, bus, radius, pitch)

static func shot(parent: Node, gun: int, silenced: bool, pos: Variant = null) -> void:
	gun = clampi(gun, 0, GUNS.size() - 1)
	var mode := "quiet" if silenced else "shot"
	if not silenced and pos is Vector3:
		var camera := parent.get_viewport().get_camera_3d()
		if camera and camera.global_position.distance_to(pos) >= 26.0:
			mode = "far"
	play(parent, "%s_%d" % [mode, gun], pos, -6.0 if silenced else (7.0 if pos == null else 8.0))


const HANDLING := ["mag_out", "mag_in", "action", "cylinder_open", "cylinder_load", "cylinder_close"]
const HANDLING_OFFSET := 18

static func footstep_range(gait: int, scuff: bool) -> float:
	return STEP_RANGE[gait] * (0.7 if scuff else 1.0)

static func player_cue(world: Node, code: int, gait: int = Gait.WALK, pos: Variant = null) -> void:
	if code < HANDLING_OFFSET:
		var variant := code % 6
		var gain: float = STEP_GAIN[gait] - (6.0 if pos == null else 0.0)
		play(world, step_key(code / 6, variant), pos, gain, "", footstep_range(gait, variant >= 4))
		if pos == null and variant >= 4 and gait in [Gait.WALK, Gait.RUN]:
			play(world, "cloth_%d" % (variant - 3), null, -14.0, "Movement")
	else:
		play(world, HANDLING[code - HANDLING_OFFSET], pos, -3.0)
