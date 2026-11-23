class_name VoicePolicy
extends RefCounted
## Pure host recipient rules. No audio is broadcast for client-side muting.
const RANGE := 24.0
const BLOCKED_RANGE := 16.0
const LEAK_RANGE := 2.0

## Encrypted team radio: an enemy listening on a stolen handset gets "garbled" instead of "radio".
## Proximity speech is never encrypted.
static func encrypt(path: Dictionary, speaker_team: int, listener_team: int, encrypted: bool) -> Dictionary:
	if encrypted and path.get("mode", "") == "radio" and speaker_team != listener_team:
		var out := path.duplicate()
		out.mode = "garbled"
		return out
	return path

## Makes speech unintelligible but still clearly "someone is talking": ring modulation, coarse sample-and-hold,
## block reversal and hiss. `offset` keeps the carrier continuous across packets.
static func garble(pcm: PackedFloat32Array, offset: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(pcm.size())
	var block := 160
	var held := 0.0
	for i in pcm.size():
		var b := i - i % block
		var j := b + (block - 1 - i % block) if (b / block + offset / block) % 2 == 0 else i
		j = mini(j, pcm.size() - 1)
		if i % 7 == 0:
			held = pcm[j]
		var n := offset + i
		var carrier := sin(TAU * 1230.0 * n / 16000.0)
		var hiss := (fmod(sin(n * 12.9898) * 43758.5453, 1.0)) * 0.12
		out[i] = clampf(held * carrier * 1.6 + hiss * absf(held) * 4.0, -1.0, 1.0)
	return out

## Local listening control only affects intercepted radio; proximity and own team remain audible.
static func should_play(path: Dictionary, speaker_team: int, listener_team: int, enemy_muted: bool) -> bool:
	return not (enemy_muted and path.get("mode", "") == "radio" and speaker_team != listener_team)


static func can_receive_radio(speaker_team: int, listener_team: int, stolen_team: int) -> bool:
	return speaker_team == listener_team or stolen_team == speaker_team

static func route(speaker: int, listener: int, people: Dictionary, radio: bool,
		stolen: Dictionary, blocked: Callable, handset_leak: bool = false) -> Dictionary:
	if speaker == listener or not people.has(speaker) or not people.has(listener):
		return {}
	var s: Dictionary = people[speaker]
	var l: Dictionary = people[listener]
	if not s.alive or not l.alive:
		return {"mode": "dead", "pos": s.pos, "gain": 1.0} if not s.alive and not l.alive and s.team == l.team else {}
	var d: float = s.pos.distance_to(l.pos)
	if d < RANGE:
		var occluded: bool = blocked.call(s.pos, l.pos)
		if not occluded or d < BLOCKED_RANGE:
			var radius := BLOCKED_RANGE if occluded else RANGE
			return {"mode": "near", "pos": s.pos, "gain": (0.55 if occluded else 1.0) * sqrt(1.0 - d / radius),
				"blocked": occluded}
	if not radio:
		return {}
	if can_receive_radio(s.team, l.team, int(stolen.get(listener, -1))):
		return {"mode": "radio", "pos": s.pos, "gain": 0.85}
	# Experiment only: receive-only handsets emit a quiet local copy. Pick one source, never mix duplicates.
	if handset_leak:
		for id: int in people:
			var h: Dictionary = people[id]
			if id == speaker or not h.alive or (h.team != s.team and int(stolen.get(id, -1)) != s.team):
				continue
			if h.pos.distance_to(l.pos) < LEAK_RANGE and not blocked.call(h.pos, l.pos):
				return {"mode": "leak", "pos": h.pos, "gain": 0.12}
	return {}
