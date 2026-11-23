class_name MatchVoice
extends Node
## Independent unreliable voice channel; host policy precedes every relay. No peer can spoof a speaker.
const PACKET_BYTES := 163 # 320-sample self-contained ADPCM
var net: NetMatch
var stolen := {} # holder -> original channel, never changes transmit channel
var pickups := {} # id -> {team, pos}, nonphysics and host owned
var people := {}
var epoch := 0
var voice_round := 0
var handset_leak := false
var tx_bytes := 0
var rx_packets := 0
var rejected := 0
var audio_rpcs := 0
var sim_dropped := 0
var received_invalid := 0
var recipients := {} # diagnostic: actual relays per listener
var _next_pickup := 0
var _tx_open := false
var _seq := 0
var _last_seq := {}
var _budget := {}
var _ping_at := {}
var _speakers := {}
var _pickup_nodes := {}
var _pings: Array[Node3D] = []
var _hud: Label
var _feed: Label
var _feed_lines: Array = [] ## [expires_msec, text]
var enemy_radio_muted := false ## local receive-only toggle, reset each round
var _listen_button: Button
var radio_open := false ## comms wheel: team radio stays open without holding the radio key
var wheel: CommWheel
var _delayed: Array = []
var _test_received := {} # speaker -> count (headless network verification)
var bot_radio_received := 0

func start(match_node: NetMatch) -> void:
	name = "Voice"
	net = match_node
	handset_leak = NetworkManager.args.get("handset-leak", "0") == "1"
	VoiceAudio.packet.connect(_capture)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12, 88)
	_hud.size = Vector2(760, 42)
	_hud.clip_text = true
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer.add_child(_hud)
	_feed = Label.new()
	_feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_feed.position = Vector2(12, -230)
	_feed.size = Vector2(560, 120)
	_feed.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_feed.add_theme_color_override("font_shadow_color", Color.BLACK)
	_feed.add_theme_constant_override("shadow_offset_x", 1)
	_feed.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_feed)
	_listen_button = Button.new()
	_listen_button.position = Vector2(12, 128)
	_listen_button.pressed.connect(toggle_enemy_radio)
	layer.add_child(_listen_button)
	wheel = CommWheel.new()
	layer.add_child(wheel)
	wheel.chosen.connect(_on_wheel)
	if net.is_host:
		sync_state()

func _exit_tree() -> void:
	VoiceAudio.set_loopback(false)
	purge()

func _host_people() -> Dictionary:
	var out := {}
	for s: NetMatch.Slot in net.slots.values():
		out[s.id] = {"pos": s.node.global_position + Vector3(0, 1.5, 0), "team": s.team, "alive": s.alive}
	return out

func sync_state() -> void:
	if not net.is_host:
		return
	epoch += 1
	if voice_round != net.round_id:
		enemy_radio_muted = false
		_clear_pings() # markers belong to one round; a death or pickup mid-round keeps them
	voice_round = net.round_id
	people = _host_people()
	_stop_unauthorized_handset()
	purge()
	_rebuild_pickups()
	for id: int in net.ready_peers:
		var safe_people := people.duplicate(true)
		if net.loop and net.loop.enabled and not net.slots[id].alive:
			for other: int in safe_people:
				if int(safe_people[other].team) != int(safe_people[id].team):
					safe_people[other].pos = Vector3.ZERO
		var held := {id: stolen[id]} if stolen.has(id) else {}
		_state.rpc_id(id, voice_round, epoch, safe_people, held, pickups, handset_leak)

@rpc("authority", "call_remote", "reliable", 0)
func _state(round_number: int, revision: int, roster: Dictionary, held: Dictionary, dropped: Dictionary, leak: bool) -> void:
	if revision <= epoch:
		return
	if voice_round != round_number:
		enemy_radio_muted = false
		_clear_pings()
	voice_round = round_number
	epoch = revision
	people = roster
	if held.has(net.my_id) and not stolen.has(net.my_id) and net.synced:
		ProcAudio.play(self, "radio_theft", null, -6.0)
	stolen = held
	pickups = dropped
	handset_leak = leak
	_stop_unauthorized_handset()
	purge()
	_rebuild_pickups()

func _stop_unauthorized_handset() -> void:
	var alive := bool(people.get(net.my_id, {}).get("alive", false))
	if not alive:
		GameAudio.stop_bus("Team Radio")
	if not alive or not stolen.has(net.my_id):
		GameAudio.stop_bus("Intercepted Radio")

func died(id: int) -> void:
	if not net.is_host or not net.slots.has(id):
		return
	var s: NetMatch.Slot = net.slots[id]
	var pos := s.last_ground if s.node.global_position.y < -4.0 else s.node.global_position
	_drop(s.team, pos)
	if stolen.has(id):
		_drop(int(stolen[id]), pos, Vector3.BACK * .45)
	stolen.erase(id)
	sync_state()

func _drop(team: int, pos: Vector3, offset := Vector3.FORWARD * .45) -> void:
	_next_pickup += 1
	pickups[_next_pickup] = {"team": team, "pos": net.weapon_drops.drop_position(pos, offset, pos, .11)}

func departed(id: int) -> void:
	# A disconnected living player drops a held enemy radio, but not their own radio.
	if stolen.has(id) and net.slots.has(id):
		_drop(int(stolen[id]), net.slots[id].node.global_position)
	stolen.erase(id)
	_last_seq.erase(id)
	_budget.erase(id)
	_ping_at.erase(id)

func reset_round() -> void:
	enemy_radio_muted = false
	stolen.clear()
	pickups.clear()
	_last_seq.clear()
	_budget.clear()
	_ping_at.clear()
	_clear_pings()
	sync_state()

func _clear_pings() -> void:
	for p in _pings:
		if is_instance_valid(p):
			p.queue_free()
	_pings.clear()

func purge() -> void:
	VoiceAudio.discard_capture()
	_delayed.clear()
	for sp: Dictionary in _speakers.values():
		(sp.player as AudioStreamPlayer).stop()
		(sp.player as AudioStreamPlayer).queue_free()
	_speakers.clear()

func _capture(data: PackedByteArray) -> void:
	if VoiceAudio.hard_muted or not net.g.player.input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	send_audio(data, Input.is_action_pressed("push_to_talk") or radio_open)

func send_audio(data: PackedByteArray, radio: bool) -> void:
	if not net.is_host and not net.synced:
		return
	_seq += 1
	if net.is_host:
		_route(net.my_id, voice_round, epoch, _seq, radio, data)
	else:
		_upload.rpc_id(1, voice_round, epoch, _seq, radio, data)

@rpc("any_peer", "call_remote", "unreliable", 2)
func _upload(r: int, e: int, seq: int, radio: bool, data: PackedByteArray) -> void:
	if net.is_host:
		_schedule(_route.bind(multiplayer.get_remote_sender_id(), r, e, seq, radio, data))

func _blocked(a: Vector3, b: Vector3) -> bool:
	return GameAudio.blocked(net.g.get_world_3d(), a, b)

func _route(sender: int, r: int, e: int, seq: int, radio: bool, data: PackedByteArray) -> void:
	if r != net.round_id or e != epoch or not net.slots.has(sender) or data.size() != PACKET_BYTES \
			or (data[2] & 0x7F) > 88 or (data[2] & 0x80) == 0 or seq <= int(_last_seq.get(sender, -1)):
		rejected += 1
		return
	var now := Time.get_ticks_msec()
	var budget: Array = _budget.get(sender, [now, 6.0])
	budget[1] = minf(float(budget[1]) + (now - int(budget[0])) * 0.06, 6.0)
	budget[0] = now
	if float(budget[1]) < 1.0:
		_budget[sender] = budget
		rejected += 1
		return
	budget[1] -= 1.0
	_budget[sender] = budget
	_last_seq[sender] = seq
	if net.bots:
		net.bots.on_speech(sender, data)
	var roster := _host_people()
	for listener: int in roster:
		var path := VoicePolicy.route(sender, listener, roster, radio, stolen, _blocked, handset_leak)
		if path.is_empty():
			continue
		recipients[listener] = int(recipients.get(listener, 0)) + 1
		if listener == net.my_id:
			_receive(sender, r, e, seq, path, data)
		elif listener in net.ready_peers:
			tx_bytes += data.size() + 48 # payload estimate; ENet counters measure wire bytes separately
			_audio.rpc_id(listener, sender, r, e, seq, path, data)

@rpc("authority", "call_remote", "unreliable", 2)
func _audio(sender: int, r: int, e: int, seq: int, path: Dictionary, data: PackedByteArray) -> void:
	audio_rpcs += 1
	_schedule(_receive.bind(sender, r, e, seq, path, data))

func _receive(sender: int, r: int, e: int, seq: int, path: Dictionary, data: PackedByteArray) -> void:
	if r != voice_round or e != epoch or not people.has(sender) or data.size() != PACKET_BYTES:
		received_invalid += 1
		return
	if not VoicePolicy.should_play(path, int(people[sender].team), net.local_team(), enemy_radio_muted):
		return
	var pcm := VoiceAudio.Codec.decode(data)
	if pcm.size() != VoiceQueue.SAMPLES:
		return
	rx_packets += 1
	_test_received[sender] = int(_test_received.get(sender, 0)) + 1
	var bus := "Proximity Voice"
	if path.mode == "radio":
		bus = "Team Radio" if int(people[sender].team) == net.local_team() else "Intercepted Radio"
	elif path.mode == "dead":
		bus = "Team Radio"
	# Keep buffered audio on its authorized bus. Reordered packets from the old mode cannot switch it back.
	if _speakers.has(sender) and (_speakers[sender].player as AudioStreamPlayer).bus != bus:
		if seq <= int(_speakers[sender].newest):
			return
		(_speakers[sender].player as AudioStreamPlayer).stop()
		(_speakers[sender].player as AudioStreamPlayer).queue_free()
		_speakers.erase(sender)
	if not _speakers.has(sender):
		var player := AudioStreamPlayer.new()
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = VoiceQueue.RATE
		stream.buffer_length = 0.06
		player.stream = stream
		player.bus = bus
		if path.mode == "radio":
			ProcAudio.play(self, "radio_rx", null, -18.0, bus)
		add_child(player)
		player.play()
		_speakers[sender] = {"player": player, "playback": player.get_stream_playback(), "queue": VoiceQueue.new(), "path": path, "at": 0, "newest": -1, "lowpass": 0.0}
	var sp: Dictionary = _speakers[sender]
	if seq > int(sp.newest):
		sp.path = path
		sp.newest = seq
	sp.at = Time.get_ticks_msec()
	(sp.queue as VoiceQueue).put(seq, pcm, int(sp.at))

func _team_encrypted(team: int) -> bool:
	return net.loop != null and net.loop.enabled and bool(net.loop.econ.encrypted[team])

func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("mute_toggle"):
			VoiceAudio.set_muted(not VoiceAudio.hard_muted)
		elif event.is_action_pressed("enemy_radio_mute"):
			toggle_enemy_radio()
		elif event.is_action_pressed("command_regroup"):
			request_action(1)
		elif event.is_action_pressed("command_objective"):
			request_action(2)

func toggle_enemy_radio() -> void:
	if not stolen.has(net.my_id):
		return
	enemy_radio_muted = not enemy_radio_muted
	# Flush already buffered intercepted speech immediately; nearby speech keeps playing.
	for id: int in _speakers.keys():
		var sp: Dictionary = _speakers[id]
		if String(sp.path.mode) == "radio" and people.has(id) and int(people[id].team) != net.local_team():
			(sp.player as AudioStreamPlayer).stop()
			(sp.player as AudioStreamPlayer).queue_free()
			_speakers.erase(id)
	GameAudio.stop_bus("Intercepted Radio")


## Bot chatter contains a named area and intent. Exact world positions stay on the host.
func bot_radio(speaker: int, kind: int, room: String) -> void:
	if not net.is_host or not net.slots.has(speaker) or not net.slots[speaker].alive:
		return
	var source: NetMatch.Slot = net.slots[speaker]
	for listener: NetMatch.Slot in net.slots.values():
		if listener.bot or not listener.alive or not VoicePolicy.can_receive_radio(
				source.team, listener.team, int(stolen.get(listener.id, -1))):
			continue
		if listener.id == net.my_id:
			_hear_bot_radio(net.round_id, source.team, source.pname, kind, room, speaker)
		elif listener.id in net.ready_peers:
			_hear_bot_radio.rpc_id(listener.id, net.round_id, source.team, source.pname, kind, room, speaker)


@rpc("authority", "call_remote", "reliable", 0)
func _hear_bot_radio(r: int, team: int, speaker_name: String, kind: int, room: String, speaker: int) -> void:
	if r != net.round_id or not net.local_alive() or not BotRadio.ROOMS.has(room) or kind < 0 or kind >= BotRadio.KEYS.size():
		return
	var intercepted := team != net.local_team()
	if intercepted and (enemy_radio_muted or int(stolen.get(net.my_id, -1)) != team):
		return
	bot_radio_received += 1
	feed("[%s] %s · %s" % ["INTERCEPTED" if intercepted else "RADIO", speaker_name, BotRadio.text(kind, room)])
	ProcAudio.play(self, BotRadio.cue(kind, room, speaker % 2 != 0), null, 3.0,
		"Intercepted Radio" if intercepted else "Team Radio")

func _on_wheel(entry: Variant) -> void:
	if entry is String and entry == "radio":
		radio_open = not radio_open
		wheel.radio_open = radio_open
		feed("Team radio %s" % ("OPEN — teammates hear you without holding %s" % Keys.key("push_to_talk") if radio_open else "closed"), Color(0.6, 1.0, 0.6))
	elif entry is int:
		request_action(int(entry))


func request_action(action: int) -> void:
	if net.is_host:
		_action_host(net.my_id, net.round_id, action)
	else:
		_action.rpc_id(1, net.round_id, action)

@rpc("any_peer", "call_remote", "reliable", 0)
func _action(r: int, action: int) -> void:
	if net.is_host:
		_action_host(multiplayer.get_remote_sender_id(), r, action)

func _action_host(id: int, r: int, action: int) -> void:
	if r != net.round_id or not net.slots.has(id) or not net.slots[id].alive or not Comms.DEFS.has(action):
		return
	var s: NetMatch.Slot = net.slots[id]
	var now := Time.get_ticks_msec()
	if now - int(_ping_at.get(id, -1000)) < 500:
		return
	_ping_at[id] = now
	callout(id, action, _callout_pos(s, action))


## Called after NetMatch validates the interactor and the aimed handset.
func take_radio(id: int, pickup: int, team: int) -> void:
	var channel := int(pickups[pickup].team)
	if channel != team:
		stolen[id] = channel
	pickups.erase(pickup)
	if id == net.my_id:
		ProcAudio.play(self, "radio_theft", null, -6.0)
	sync_state()


## Host: where a callout's marker goes. Aim points use the caller's authoritative camera, never client data.
func _callout_pos(s: NetMatch.Slot, kind: int) -> Vector3:
	match Comms.placement(kind):
		"aim":
			var from := s.node.camera.global_position
			var to := from - s.node.camera.global_basis.z * 40.0
			var hit := net.g.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
			return hit.get("position", to)
		"site_a", "site_b":
			var sites: Array[Vector3] = net.loop.rules.tuning.sites if net.loop else []
			var i := 0 if Comms.placement(kind) == "site_a" else 1
			if i < sites.size():
				return sites[i]
	return s.node.global_position


## Host: relay one callout from a living player (or bot) to living teammates, then let teammate bots react.
func callout(id: int, kind: int, pos: Vector3) -> void:
	if not net.is_host or not net.slots.has(id):
		return
	var s: NetMatch.Slot = net.slots[id]
	var marker := Comms.placement(kind) != ""
	for other: NetMatch.Slot in net.slots.values():
		if other.team != s.team or not other.alive:
			continue
		if other.id == net.my_id:
			_show_ping(net.round_id, pos, kind, s.pname, marker)
		elif other.id in net.ready_peers:
			_ping.rpc_id(other.id, net.round_id, pos, kind, s.pname, marker)
	if net.bots:
		net.bots.on_callout(id, kind, pos)

@rpc("authority", "call_remote", "reliable", 0)
func _ping(r: int, pos: Vector3, kind: int, pname: String, marker: bool) -> void:
	_show_ping(r, pos, kind, pname, marker)


func feed(text: String, color: Color = Color.WHITE) -> void:
	_feed_lines.append([Time.get_ticks_msec() + 7000, text, color])
	while _feed_lines.size() > 6:
		_feed_lines.pop_front()


func _show_ping(r: int, pos: Vector3, kind: int, pname: String, marker: bool = true) -> void:
	if r != net.round_id:
		return
	var col := Comms.color(kind)
	feed("[TEAM] %s: %s" % [pname, Comms.text(kind)], col)
	if not marker:
		return
	var label := Label3D.new()
	label.text = "%s: %s\n▼" % [pname, Comms.text(kind).to_upper()]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.pixel_size = 0.006
	label.modulate = col
	label.outline_size = 8
	net.g.add_child(label)
	label.global_position = pos + Vector3(0, 0.3, 0)
	_pings.append(label)
	while _pings.size() > 4:
		var old: Node3D = _pings.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var label_id := label.get_instance_id()
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_id_valid(label_id):
			var expired := instance_from_id(label_id) as Node3D
			_pings.erase(expired)
			expired.queue_free())

func target_radio(player: Player, team: int, has_enemy_radio: bool) -> int:
	var best := 0
	var best_dot := .86
	for key: int in pickups:
		var radio: Dictionary = pickups[key]
		if has_enemy_radio and int(radio.team) != team:
			continue
		var alignment := net.weapon_drops.aim_at(player, radio.pos, 2.0)
		if alignment > best_dot:
			best = key
			best_dot = alignment
	return best


func _rebuild_pickups() -> void:
	for id: int in _pickup_nodes.keys():
		if not pickups.has(id):
			(_pickup_nodes[id] as Node3D).free()
			_pickup_nodes.erase(id)
	for id: int in pickups:
		if _pickup_nodes.has(id):
			continue
		var p: Dictionary = pickups[id]
		var root := Node3D.new()
		net.g.add_child(root)
		root.global_position = p.pos
		var case_color := Color(.22, .095, .08) if int(p.team) == 0 else Color(.085, .14, .23)
		_radio_part(root, Vector3(.14, .19, .068), Vector3.ZERO, case_color)
		_radio_part(root, Vector3(.014, .105, .014), Vector3(-.05, .134, 0), Color(.07, .085, .09))
		var led_color := Color(1.0, .64, .18)
		var led := _radio_part(root, Vector3(.023, .017, .018), Vector3(.032, .09, 0), led_color)
		var led_mat := led.material_override as StandardMaterial3D
		led_mat.emission_enabled = true
		led_mat.emission = led_color
		var halo := OmniLight3D.new()
		halo.position = Vector3(.032, .102, 0)
		halo.light_color = led_color
		halo.omni_range = .48
		halo.name = "LED"
		root.add_child(halo)
		root.set_meta("led_material", led_mat)
		root.set_meta("beep_cycle", -1)
		var label := Label3D.new()
		label.name = "Prompt"
		label.visible = false
		label.position.y = 0.4
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.003
		root.add_child(label)
		_pickup_nodes[id] = root

func _radio_part(root: Node3D, size: Vector3, offset: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = offset
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	root.add_child(mesh)
	return mesh

func _schedule(callback: Callable) -> void:
	if net._rng.randf() < net._sim_loss or _delayed.size() >= 128:
		sim_dropped += 1
		return
	var delay := maxf(net._sim_latency + net._rng.randf_range(-net._sim_jitter, net._sim_jitter), 0.0)
	if delay <= 0.0:
		callback.call()
	else:
		_delayed.append([Time.get_ticks_msec() + int(delay * 1000.0), callback])

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var due: Array = []
	for entry: Array in _delayed:
		if int(entry[0]) <= now:
			due.append(entry)
	for entry: Array in due:
		_delayed.erase(entry)
		(entry[1] as Callable).call()
	var team := net.local_team()
	var camera := get_viewport().get_camera_3d()
	for id: int in _pickup_nodes:
		var root: Node3D = _pickup_nodes[id]
		var cycle_time := now + id * 397
		var cycle := cycle_time / 2300
		var flashing := cycle_time % 2300 < 155
		var led: StandardMaterial3D = root.get_meta("led_material")
		led.emission_energy_multiplier = 3.2 if flashing else .13
		(root.get_node("LED") as OmniLight3D).light_energy = .75 if flashing else 0.0
		if flashing and cycle != int(root.get_meta("beep_cycle")):
			root.set_meta("beep_cycle", cycle)
			if camera and camera.global_position.distance_squared_to(root.global_position) < 12.25:
				ProcAudio.play(root, "radio_beacon", root.global_position, -17.0, "", 3.5)
		var label: Label3D = root.get_node("Prompt")
		label.visible = net.interaction == [NetMatch.Interact.RADIO, id]
		if label.visible:
			label.text = "%s · %s" % [Keys.key("interact"),
				"Recover teammate radio" if int(pickups[id].team) == team else "Steal enemy radio"]
	var talking: Array[String] = []
	for id: int in _speakers.keys():
		var sp: Dictionary = _speakers[id]
		if now - int(sp.at) > 400:
			(sp.player as AudioStreamPlayer).queue_free()
			_speakers.erase(id)
			continue
		talking.append("%s [%s]" % [NetworkManager.player_names.get(id, str(id)), sp.path.mode])
		var playback: AudioStreamGeneratorPlayback = sp.playback
		var queue: VoiceQueue = sp.queue
		for i in 6:
			if not playback.can_push_buffer(VoiceQueue.SAMPLES):
				break
			var pcm := queue.take(now)
			if pcm.is_empty():
				break
			var pan := 0.0
			if sp.path.mode in ["near", "leak"]:
				var direction: Vector3 = (sp.path.pos - net.g.player.camera.global_position).normalized()
				pan = clampf(net.g.player.camera.global_basis.x.dot(direction), -1.0, 1.0)
			if sp.path.mode == "garbled":
				pcm = VoicePolicy.garble(pcm, int(sp.get("garble_n", 0)))
				sp["garble_n"] = int(sp.get("garble_n", 0)) + pcm.size()
			var stereo := PackedVector2Array()
			var scale: float = float(sp.path.gain) * 0.58
			var balance := Vector2(sqrt((1.0 - pan) * 0.5), sqrt((1.0 + pan) * 0.5))
			var lowpass := float(sp.lowpass)
			var cutoff := 1.0 - exp(-TAU * GameAudio.OCCLUDED_HZ / VoiceQueue.RATE) if sp.path.get("blocked", false) else 1.0
			for v in pcm:
				lowpass = lerpf(lowpass, v, cutoff)
				stereo.append(balance * lowpass * scale)
			sp.lowpass = lowpass
			playback.push_buffer(stereo)
			if scale * VoiceAudio.volume > 0.015 and (sp.path.mode != "radio" or int(people[id].team) == net.local_team() or GameAudio.intercepted > 0.0):
				GameAudio.speech_played()
	_listen_button.visible = stolen.has(net.my_id) and net.local_alive()
	_listen_button.text = "%s · Enemy radio %s (click to %s)" % [Keys.key("enemy_radio_mute"), "MUTED" if enemy_radio_muted else "ON", "listen" if enemy_radio_muted else "mute"]
	var stolen_text := " | stolen %s: RECEIVE ONLY" % ("R" if int(stolen.get(net.my_id, -1)) == 0 else "B") if stolen.has(net.my_id) else ""
	var radio_tx := Input.is_action_pressed("push_to_talk") or radio_open
	var transmitting := radio_tx and not VoiceAudio.hard_muted and not VoiceAudio.loopback and net.local_alive() \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if transmitting and not _tx_open:
		ProcAudio.play(self, "radio_tx", null, -14.0, "Team Radio")
	_tx_open = transmitting
	var tx := "HARD MUTED" if VoiceAudio.hard_muted else ("LOCAL TEST" if VoiceAudio.loopback else (("RADIO OPEN + PROXIMITY" if radio_open else "RADIO + PROXIMITY") if radio_tx else "PROXIMITY"))
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not VoiceAudio.hard_muted and not VoiceAudio.loopback:
		tx = "TRANSMISSION PAUSED"
	var lines: Array[String] = []
	_feed_lines = _feed_lines.filter(func(e: Array) -> bool: return int(e[0]) > now)
	for e: Array in _feed_lines:
		lines.append(String(e[1]))
	_feed.text = "\n".join(lines)
	if not _feed_lines.is_empty():
		_feed.modulate = Color.WHITE
	_hud.text = "%s%s · %s mic mute · hold %s radio\n%s" % [tx, stolen_text,
		Keys.key("mute_toggle"), Keys.key("push_to_talk"), ", ".join(talking)]
	_hud.visible = not net.g._panel.visible and not (net.loop and net.loop.menu and net.loop.menu.is_open)
