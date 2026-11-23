extends Node
## Device/capture/codec only. MatchVoice owns transport and recipient policy.
signal packet(data: PackedByteArray)
const Codec := preload("res://scripts/voice/voice_adpcm.gd")
const SETTINGS := "user://voice.cfg"
var hard_muted := true
var gain := 2.0
var volume := 1.0
var device := "Default"
var loopback := false
var level := 0.0
var active := false
var status := "Microphone off — enable in Esc settings"
var speaking := false
var _restart := 0
var _frames := PackedFloat32Array()
var _phase := 0.0
var _sum := 0.0
var _count := 0
var _gate := 0.0
var _loop: AudioStreamPlayer
var _loop_playback: AudioStreamGeneratorPlayback
var _empty_for := 0.0

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		hard_muted = bool(cfg.get_value("voice", "muted", true))
		gain = clampf(float(cfg.get_value("voice", "gain", 2.0)), 0.25, 12.0)
		volume = clampf(float(cfg.get_value("voice", "volume", 1.0)), 0.0, 2.0)
		device = String(cfg.get_value("voice", "device", "Default"))
	_apply_volume()
	if not hard_muted:
		_start.call_deferred()

func save() -> void:
	_apply_volume()
	var cfg := ConfigFile.new()
	cfg.set_value("voice", "muted", hard_muted)
	cfg.set_value("voice", "gain", gain)
	cfg.set_value("voice", "volume", volume)
	cfg.set_value("voice", "device", device)
	cfg.save(SETTINGS)

func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Voice")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume == 0.0)

func set_muted(muted: bool) -> void:
	hard_muted = muted
	_restart += 1
	_stop()
	save()
	if not muted:
		_start()

func _stop() -> void:
	if active:
		AudioServer.set_input_device_active(false)
	active = false
	speaking = false
	level = 0.0
	_frames.clear()
	_phase = 0.0
	_sum = 0.0
	_count = 0
	_gate = 0.0
	status = "Microphone off — hard muted" if hard_muted else "Microphone stopped"
	if _loop:
		_loop.stop()
		_loop.queue_free()
		_loop = null
		_loop_playback = null

func _start() -> void:
	if hard_muted or DisplayServer.get_name() == "headless":
		status = "Microphone unavailable (headless)" if not hard_muted else status
		return
	var devices := AudioServer.get_input_device_list()
	if devices.is_empty():
		status = "No input device — you can still listen and ping"
		return
	if device not in devices:
		device = "Default"
	AudioServer.input_device = device
	var err := AudioServer.set_input_device_active(true)
	active = err == OK
	_empty_for = 0.0
	status = "Open proximity mic — checking input" if active else "Mic unavailable / permission denied: %s" % error_string(err)

func select_device(value: String) -> void:
	if value == device:
		return # avoid restarting the same WASAPI device
	_restart += 1
	var ticket := _restart
	_stop()
	device = value
	save()
	await get_tree().create_timer(0.5).timeout
	if ticket == _restart and not hard_muted:
		_start()

func set_loopback(enabled: bool) -> void:
	loopback = enabled
	if not enabled and _loop:
		_loop.stop()
		_loop.queue_free()
		_loop = null
		_loop_playback = null

func discard_capture() -> void:
	_frames.clear()
	_phase = 0.0
	_sum = 0.0
	_count = 0
	_gate = 0.0
	speaking = false
	if active:
		var available := AudioServer.get_input_frames_available()
		if available > 0:
			AudioServer.get_input_frames(available)

func _process(delta: float) -> void:
	if not active or hard_muted:
		return
	var n := AudioServer.get_input_frames_available()
	if n <= 0:
		_empty_for += delta
		if _empty_for > 2.0:
			status = "No mic frames — check device and OS microphone permission"
		return
	_empty_for = 0.0
	# Discard capture backlog after stalls, rather than transmitting old speech.
	var rate := maxf(AudioServer.get_input_mix_rate(), 1.0)
	var raw := AudioServer.get_input_frames(n)
	if n > rate * 0.12:
		_frames.clear()
		return
	_ingest(raw, rate)
	status = "Open proximity mic — hold team-radio key (nearby enemies hear you)"

func _ingest(raw: PackedVector2Array, rate: float) -> void:
	level = 0.0
	for f in raw:
		var sample := clampf((f.x + f.y) * 0.5 * gain, -1.0, 1.0)
		level = maxf(level, absf(sample))
		_sum += sample
		_count += 1
		_phase += 1.0
		while _phase + 1e-9 >= rate / VoiceQueue.RATE:
			_phase = maxf(_phase - rate / VoiceQueue.RATE, 0.0)
			_frames.append(_sum / _count if _count > 0 else sample)
			_sum = 0.0
			_count = 0
			if _frames.size() == VoiceQueue.SAMPLES:
				_emit_frame(_frames)
				_frames.clear()

func _emit_frame(pcm: PackedFloat32Array) -> void:
	var peak := 0.0
	for v in pcm:
		peak = maxf(peak, absf(v))
	_gate = 0.2 if peak > 0.008 else maxf(_gate - 0.02, 0.0)
	speaking = _gate > 0.0
	if not speaking:
		return
	var data := Codec.encode(pcm)
	if loopback:
		if not _loop:
			_loop = AudioStreamPlayer.new()
			var stream := AudioStreamGenerator.new()
			stream.mix_rate = VoiceQueue.RATE
			stream.buffer_length = 0.12
			_loop.stream = stream
			_loop.bus = "Proximity Voice"
			add_child(_loop)
			_loop.play()
			_loop_playback = _loop.get_stream_playback()
		var decoded := Codec.decode(data)
		var stereo := PackedVector2Array()
		for v in decoded:
			stereo.append(Vector2(v, v) * 0.24)
		if _loop_playback.can_push_buffer(stereo.size()):
			_loop_playback.push_buffer(stereo)
		return # local test never transmits, preventing a loopback feedback path into the match
	elif _loop:
		_loop.stop()
		_loop.queue_free()
		_loop = null
		_loop_playback = null
	packet.emit(data)
