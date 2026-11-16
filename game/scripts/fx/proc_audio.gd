class_name ProcAudio
extends RefCounted
## Placeholder sounds synthesised in code (no asset licences). Replace with real audio later.

const RATE := 22050
## kind -> [duration s, tone Hz (0 = none), noise mix 0..1, decay 1/s, gain]
const DEFS := {
	"shot": [0.14, 0.0, 1.0, 26.0, 0.7],
	"dry": [0.05, 900.0, 0.1, 60.0, 0.5],
	"reload": [0.16, 300.0, 0.5, 18.0, 0.6],
	"beep": [0.09, 1250.0, 0.0, 22.0, 0.5],
	"boom": [0.9, 65.0, 0.8, 4.0, 0.9],
	"hit": [0.06, 520.0, 0.4, 45.0, 0.5],
	"reject": [0.18, 170.0, 0.1, 14.0, 0.6],
}
static var _cache := {}


static func get_sound(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var d: Array = DEFS[kind]
	var n := int(float(d[0]) * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		if float(d[1]) > 0.0:
			s += sin(TAU * float(d[1]) * t) * (1.0 - float(d[2]))
		lp = lerpf(lp, rng.randf() * 2.0 - 1.0, 0.35)
		s += lp * float(d[2])
		data.encode_s16(i * 2, int(clampf(s * exp(-t * float(d[3])) * float(d[4]), -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_cache[kind] = w
	return w


## One-shot sound; 3D when `pos` is given. Frees itself.
static func play(parent: Node, kind: String, pos: Variant = null, volume_db: float = 0.0) -> void:
	if pos is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = get_sound(kind)
		p3.volume_db = volume_db
		p3.finished.connect(p3.queue_free)
		parent.add_child(p3)
		p3.global_position = pos
		p3.play()
		return
	var p2 := AudioStreamPlayer.new()
	p2.stream = get_sound(kind)
	p2.volume_db = volume_db
	p2.finished.connect(p2.queue_free)
	parent.add_child(p2)
	p2.play()
