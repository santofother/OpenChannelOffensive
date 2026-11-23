extends Node
## Shared one-shot mixer. All voices are allocated once and follow the match lifetime.
const WORLD_VOICES := 24
const LOCAL_VOICES := 8
const EFFECTS_GAIN_DB := 4.0
const OCCLUDED_HZ := 1800.0
const WARMUP_BATCH := 6

var master := 1.0
var effects := 1.0
var intercepted := 0.8
var combat_duck_db := 1.5
var _speech_for := 0.0
var _duck_db := 0.0
var _world: Array[AudioStreamPlayer3D] = []
var _local: Array[AudioStreamPlayer] = []
var _until_update := 0.0
var peak_world_voices := 0

func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load("user://mix.cfg") == OK:
		master = clampf(float(settings.get_value("mix", "master", master)), 0.0, 1.0)
		effects = clampf(float(settings.get_value("mix", "effects", effects)), 0.0, 1.0)
		intercepted = clampf(float(settings.get_value("mix", "intercepted", intercepted)), 0.0, 1.0)
		combat_duck_db = clampf(float(settings.get_value("mix", "duck_db", combat_duck_db)), 0.0, 3.0)
	apply_mix()
	if DisplayServer.get_name() == "headless":
		return
	for i in WORLD_VOICES:
		var player := AudioStreamPlayer3D.new()
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.max_db = 6.0
		add_child(player)
		_world.append(player)
	for i in LOCAL_VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_local.append(player)
	_warm.call_deferred()

func _warm() -> void:
	var count := 0
	for kind: String in ProcAudio.sound_keys():
		ProcAudio.get_sound(kind)
		count += 1
		if count % WARMUP_BATCH == 0:
			await get_tree().process_frame

func apply_mix() -> void:
	_set_level("Master", master)
	_set_level("Effects", effects, EFFECTS_GAIN_DB)
	_set_level("Intercepted Radio", intercepted)

func save() -> void:
	apply_mix()
	var settings := ConfigFile.new()
	settings.set_value("mix", "master", master)
	settings.set_value("mix", "effects", effects)
	settings.set_value("mix", "intercepted", intercepted)
	settings.set_value("mix", "duck_db", combat_duck_db)
	settings.save("user://mix.cfg")

func _set_level(bus: StringName, level: float, gain_db := 0.0) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, level <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.0001)) + gain_db)

## Scene/world geometry only. Doors, wall openings and destroyed cover use live collision.
func blocked(world: World3D, from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.0001:
		return false
	return not world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()

func play(parent: Node, kind: String, position: Variant, gain_db: float, bus_override: String, radius_override: float, pitch: float = 1.0) -> void:
	if _local.is_empty() or not parent.is_inside_tree():
		return
	var bus := ProcAudio.bus_for(kind) if bus_override.is_empty() else bus_override
	var camera := get_viewport().get_camera_3d()
	if kind.begins_with("shot_") and camera:
		var origin: Vector3 = position if position is Vector3 else camera.global_position
		if not blocked(camera.get_world_3d(), origin, origin + Vector3.UP * 4.0):
			kind = "outdoor_" + kind.get_slice("_", 1)
	var stream := ProcAudio.get_sound(kind)
	if stream == null:
		return
	if position is Vector3:
		if camera == null:
			return
		var radius := radius_override if radius_override > 0.0 else ProcAudio.range_for(kind)
		var distance := camera.global_position.distance_to(position)
		if distance >= radius:
			return
		var priority := (2.0 if bus in ["Objectives", "Weapons"] else 1.0) - distance / radius
		var player := _choose(_world, priority) as AudioStreamPlayer3D
		if player == null:
			return
		_configure(player, parent, stream, bus, priority, pitch)
		player.global_position = position
		player.max_distance = radius
		var loud_shot := ProcAudio.is_loud_shot(kind)
		player.unit_size = 17.0 if loud_shot else (5.0 if bus == "Movement" else 5.5)
		player.panning_strength = 1.65 if loud_shot or bus == "Movement" else 1.0
		player.set_meta("gain", gain_db)
		player.set_meta("loud_shot", loud_shot)
		_update_path(player, camera)
		player.play()
		var active := 0
		for voice in _world:
			active += int(voice.playing)
		peak_world_voices = maxi(peak_world_voices, active)
	else:
		var priority := 2.0 if kind == "incoming_impact" or kind.begins_with("bot_radio_") else 1.0
		var player := _choose(_local, priority) as AudioStreamPlayer
		if player:
			_configure(player, parent, stream, bus, priority, pitch)
			player.volume_db = gain_db
			player.play()

func _choose(pool: Array, priority: float) -> Node:
	var candidate: Node
	var lowest := INF
	for player: Node in pool:
		if not player.playing:
			return player
		var score: float = player.get_meta("priority")
		if score < lowest:
			lowest = score
			candidate = player
	return candidate if priority >= lowest else null

func _configure(player: Node, parent: Node, stream: AudioStream, bus: String, priority: float, pitch: float) -> void:
	player.stop()
	player.set_meta("owner", parent.get_instance_id())
	player.set_meta("priority", priority)
	player.stream = stream
	player.bus = bus
	player.pitch_scale = pitch

func _update_path(player: AudioStreamPlayer3D, camera: Camera3D) -> void:
	var occluded := blocked(camera.get_world_3d(), camera.global_position, player.global_position)
	var movement := player.bus == &"Movement"
	var loud_shot := bool(player.get_meta("loud_shot"))
	var wall_loss := -4.0 if loud_shot else (-11.0 if movement else -7.0)
	player.volume_db = float(player.get_meta("gain")) + (wall_loss if occluded else 0.0)
	if occluded:
		player.attenuation_filter_cutoff_hz = 3000.0 if loud_shot else OCCLUDED_HZ
		player.attenuation_filter_db = -12.0 if loud_shot else -18.0
	else:
		# Rear footsteps lose some brightness so a sound directly behind isn't mixed like one ahead.
		var direction := (player.global_position - camera.global_position).normalized()
		var rearward := maxf(camera.global_basis.z.dot(direction), 0.0) if movement or loud_shot else 0.0
		player.attenuation_filter_cutoff_hz = lerpf(20500.0, 4800.0 if loud_shot else 3800.0, rearward)
		player.attenuation_filter_db = -6.0 * rearward

func speech_played() -> void:
	_speech_for = 0.15

func _process(delta: float) -> void:
	_speech_for = maxf(_speech_for - delta, 0.0)
	for player in _local:
		if player.playing and (player.bus == &"Team Radio" or (player.bus == &"Intercepted Radio" and intercepted > 0.0)):
			speech_played()
	var target := -combat_duck_db if _speech_for > 0.0 else 0.0
	var next := move_toward(_duck_db, target, 18.0 * delta)
	if next != _duck_db:
		_duck_db = next
		for bus: String in ["Weapons", "Breaching"]:
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), _duck_db)

func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	_until_update -= delta
	var update_paths := _until_update <= 0.0
	if update_paths:
		_until_update = 0.08
	for player in _world:
		if not player.playing:
			continue
		if camera == null or not is_instance_id_valid(int(player.get_meta("owner"))):
			player.stop()
		elif update_paths:
			_update_path(player, camera)
	for player in _local:
		if player.playing and not is_instance_id_valid(int(player.get_meta("owner"))):
			player.stop()

func clear() -> void:
	_speech_for = 0.0
	for player in _world:
		player.stop()
	for player in _local:
		player.stop()

func stop_owner(owner: Node) -> void:
	for player in _world:
		if player.playing and int(player.get_meta("owner")) == owner.get_instance_id():
			player.stop()


func stop_bus(bus: StringName) -> void:
	for player in _local:
		if player.playing and player.bus == bus:
			player.stop()
