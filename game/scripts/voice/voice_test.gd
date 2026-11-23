extends Node
var fails := 0
func check(label: String, ok: bool) -> void:
	print("  %s voice: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1

func _ready() -> void:
	var codec = VoiceAudio.Codec
	var pcm := PackedFloat32Array()
	var energy := 0.0
	var error := 0.0
	for i in 320:
		pcm.append(0.5 * sin(i * 0.11) + 0.2 * sin(i * 0.37))
	var packet: PackedByteArray = codec.encode(pcm)
	var decoded: PackedFloat32Array = codec.decode(packet)
	for i in 320:
		energy += pcm[i] * pcm[i]
		error += pow(pcm[i] - decoded[i], 2)
	var snr := 10.0 * log(energy / error) / log(10.0)
	print("VOICE codec: %d bytes/20ms, %.2f kbit/s, SNR %.1f dB" % [packet.size(), packet.size() * 50 * 0.008, snr])
	check("codec size / quality", packet.size() == 163 and decoded.size() == 320 and snr > 20)
	for n in [1, 2, 3, 7, 160, 319]:
		var short := PackedFloat32Array()
		short.resize(n)
		check("codec exact length %d" % n, codec.decode(codec.encode(short)).size() == n)
	for malformed in [PackedByteArray(), PackedByteArray([0]), PackedByteArray([0, 0, 255]), PackedByteArray([0, 0, 128])]:
		check("malformed codec rejected", codec.decode(malformed).is_empty())
	# Feed stereo device frames through the actual streaming gain/resampler/codec path.
	# Includes devices below 16 kHz; these must not double speech speed/pitch.
	for rate in [8000, 16000, 44100, 48000]:
		var capture := preload("res://scripts/voice/voice_audio.gd").new()
		capture.gain = 1.0
		var emitted: Array = []
		capture.packet.connect(func(data: PackedByteArray) -> void: emitted.append(data))
		var raw := PackedVector2Array()
		for i in int(rate / 50):
			var v := 0.3 * sin(TAU * 400.0 * i / rate)
			raw.append(Vector2(v, v))
		capture._ingest(raw, rate)
		check("device resample %d Hz -> one 20ms packet" % rate, emitted.size() == 1 and codec.decode(emitted[0]).size() == 320)
		capture.free()
	var partial := preload("res://scripts/voice/voice_audio.gd").new()
	var emitted_partial: Array = []
	partial.packet.connect(func(data: PackedByteArray) -> void: emitted_partial.append(data))
	var half := PackedVector2Array()
	half.resize(160)
	half.fill(Vector2(0.2, 0.2))
	partial._ingest(half, 16000)
	partial.discard_capture() # death/reset/device transition must not splice the old voice into a new life
	half.fill(Vector2(-0.2, -0.2))
	partial._ingest(half, 16000)
	check("lifecycle discards incomplete old speech", emitted_partial.is_empty())
	partial._ingest(half, 16000)
	check("new speech begins with new samples", emitted_partial.size() == 1 and codec.decode(emitted_partial[0])[0] < -0.3)
	partial.free()
	var q := VoiceQueue.new()
	q.put(0, pcm, 0)
	q.put(2, pcm, 20)
	q.put(1, pcm, 30)
	check("duplicate ignored", not q.put(1, pcm, 35))
	check("prebuffer", q.take(59).is_empty())
	check("reorder in sequence", q.take(60) == pcm and q.take(80) == pcm and q.take(100) == pcm)
	var silence := q.take(120)
	check("loss concealed", silence.size() == 320 and silence[20] == 0 and q.concealed == 1)
	check("late discarded", not q.put(1, pcm, 121))
	for seq in range(100, 200):
		q.put(seq, pcm, 130)
	check("queue cap", q.pending.size() <= VoiceQueue.CAP)
	check("invalid queue frame", not q.put(201, PackedFloat32Array(), 140))
	q.put(250, pcm, 1000)
	check("idle spurt rebuffer", q.expected == 250 and q.pending.size() == 1 and q.take(1059).is_empty() and q.take(1060) == pcm)
	var p := {
		1: {"team": 0, "alive": true, "pos": Vector3.ZERO},
		2: {"team": 1, "alive": true, "pos": Vector3(3, 0, 0)},
		3: {"team": 0, "alive": true, "pos": Vector3(30, 0, 0)},
		4: {"team": 1, "alive": true, "pos": Vector3(55, 0, 0)},
		5: {"team": 0, "alive": false, "pos": Vector3.ZERO},
		6: {"team": 0, "alive": false, "pos": Vector3.ZERO}}
	var clear := func(_a: Vector3, _b: Vector3) -> bool: return false
	var blocked := func(_a: Vector3, _b: Vector3) -> bool: return true
	check("nearby enemy hears open speech", VoicePolicy.route(1, 2, p, false, {}, clear).get("mode") == "near")
	check("distant teammate has no open packets", VoicePolicy.route(1, 3, p, false, {}, clear).is_empty())
	check("held radio reaches teammate", VoicePolicy.route(1, 3, p, true, {}, clear).get("mode") == "radio")
	check("distant enemy unauthorized", VoicePolicy.route(1, 4, p, true, {}, clear).is_empty())
	check("theft receives original channel", VoicePolicy.route(1, 4, p, true, {4: 0}, clear).get("mode") == "radio")
	check("stolen radio cannot impersonate", VoicePolicy.route(4, 3, p, true, {4: 0}, clear).is_empty())
	check("radio and proximity deduplicate", VoicePolicy.route(1, 2, p, true, {2: 0}, clear).get("mode") == "near")
	p[2].pos = Vector3(7, 0, 0)
	var muffled := VoicePolicy.route(1, 2, p, false, {}, blocked)
	check("wall muffles proximity", muffled.get("blocked", false) and muffled.gain < VoicePolicy.route(1, 2, p, false, {}, clear).gain)
	p[2].pos = Vector3(14, 0, 0)
	check("proximity speech carries through a wall at 14 m", VoicePolicy.route(1, 2, p, false, {}, blocked).get("mode") == "near")
	p[2].pos = Vector3(20, 0, 0)
	check("proximity speech carries 20 m in the clear and walls shorten range",
		VoicePolicy.route(1, 2, p, false, {}, clear).get("mode") == "near" and VoicePolicy.route(1, 2, p, false, {}, blocked).is_empty())
	check("dead cannot speak to living", VoicePolicy.route(5, 1, p, true, {}, clear).is_empty())
	check("living cannot speak to dead", VoicePolicy.route(1, 5, p, true, {}, clear).is_empty())
	check("dead team isolated", VoicePolicy.route(5, 6, p, false, {}, clear).get("mode") == "dead")
	p[6].team = 1
	check("dead enemy isolated", VoicePolicy.route(5, 6, p, true, {}, clear).is_empty())
	p[4].pos = Vector3(31, 0, 0)
	check("handset experiment opt in", VoicePolicy.route(1, 4, p, true, {}, clear, false).is_empty() and VoicePolicy.route(1, 4, p, true, {}, clear, true).get("mode") == "leak")
	p[1].team = 1
	check("side swap recomputes channel", VoicePolicy.route(1, 4, p, true, {}, clear).get("mode") == "radio" and VoicePolicy.route(1, 3, p, true, {}, clear).is_empty())
	check("muted enemy radio is silent", not VoicePolicy.should_play({"mode":"radio"}, 0, 1, true))
	check("unmuted stolen radio plays", VoicePolicy.should_play({"mode":"radio"}, 0, 1, false))
	check("enemy radio mute preserves proximity and own team", VoicePolicy.should_play({"mode":"near"}, 0, 1, true) and VoicePolicy.should_play({"mode":"radio"}, 1, 1, true))
	p[1].team = 0
	p[4].pos = Vector3(50, 0, 0)
	check("mutual theft permits both radio directions", VoicePolicy.route(4, 1, p, true, {4:0, 1:1}, clear).get("mode") == "radio" and VoicePolicy.route(1, 4, p, true, {4:0, 1:1}, clear).get("mode") == "radio")
	check("headless never captures", not VoiceAudio.active)
	print("SMOKE_OK voice" if fails == 0 else "SMOKE_FAIL voice")
	get_tree().quit(0 if fails == 0 else 1)
