class_name VoiceQueue
extends RefCounted
## 60 ms prebuffer, 120 ms maximum queued audio; sequence order, duplicate rejection and bounded PLC.
const SAMPLES := 320
const RATE := 16000
const FRAME_MS := 20
const PREBUFFER_MS := 60
const CAP := 6
var pending := {}
var expected := -1
var due := 0
var last_at := 0
var late := 0
var concealed := 0
var played := 0

func put(seq: int, pcm: PackedFloat32Array, now: int) -> bool:
	if seq < 0 or pcm.size() != SAMPLES:
		return false
	if expected < 0 or now - last_at > 300:
		pending.clear()
		expected = seq
		due = now + PREBUFFER_MS
	last_at = now
	if seq < expected or pending.has(seq):
		late += 1
		return false
	pending[seq] = pcm
	if seq - expected >= CAP:
		expected = seq - CAP + 1
		due = now
	for key: int in pending.keys():
		if key < expected:
			pending.erase(key)
	return true

func take(now: int) -> PackedFloat32Array:
	if expected < 0 or now < due:
		return PackedFloat32Array()
	if now - last_at > 160 and pending.is_empty():
		expected = -1
		return PackedFloat32Array()
	# A slow rendering frame must not replay a long backlog.
	if now - due > 120:
		due = now
	var pcm: PackedFloat32Array
	if pending.has(expected):
		pcm = pending[expected]
		pending.erase(expected)
	else:
		pcm = PackedFloat32Array()
		pcm.resize(SAMPLES) # silence concealment avoids repeating words/feedback
		concealed += 1
	expected += 1
	due += FRAME_MS
	played += 1
	return pcm
