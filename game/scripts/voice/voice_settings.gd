class_name VoiceSettings
extends VBoxContainer
var _status: Label
var _enable: CheckButton
var _meter: ProgressBar

func _ready() -> void:
	var title := Label.new()
	title.text = "Voice — open mic; nearby enemies hear you. Use headphones."
	add_child(title)
	_enable = CheckButton.new()
	var mute := _enable
	mute.text = "Enable microphone (requests OS permission)"
	mute.button_pressed = not VoiceAudio.hard_muted
	mute.toggled.connect(func(on: bool) -> void: VoiceAudio.set_muted(not on))
	add_child(mute)
	var device := OptionButton.new()
	device.fit_to_longest_item = false
	device.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var devices := AudioServer.get_input_device_list()
	for d in devices:
		device.add_item(d)
		if d == VoiceAudio.device:
			device.select(device.item_count - 1)
	device.disabled = devices.is_empty()
	device.item_selected.connect(func(index: int) -> void: VoiceAudio.select_device(device.get_item_text(index)))
	add_child(device)
	var refresh := Button.new()
	refresh.text = "Refresh microphones / retry capture"
	refresh.pressed.connect(func() -> void:
		device.clear()
		for d in AudioServer.get_input_device_list():
			device.add_item(d)
			if d == VoiceAudio.device:
				device.select(device.item_count - 1)
		device.disabled = device.item_count == 0
		VoiceAudio.set_muted(VoiceAudio.hard_muted))
	add_child(refresh)
	add_slider("Mic gain", 0.25, 12.0, VoiceAudio.gain, func(v: float) -> void:
		VoiceAudio.gain = v
		VoiceAudio.save())
	add_slider("Master volume", 0.0, 1.0, GameAudio.master, func(v: float) -> void:
		GameAudio.master = v
		GameAudio.save())
	add_slider("Effects volume", 0.0, 1.0, GameAudio.effects, func(v: float) -> void:
		GameAudio.effects = v
		GameAudio.save())
	add_slider("Enemy radio", 0.0, 1.0, GameAudio.intercepted, func(v: float) -> void:
		GameAudio.intercepted = v
		GameAudio.save())
	add_slider("Voice volume", 0.0, 2.0, VoiceAudio.volume, func(v: float) -> void:
		VoiceAudio.volume = v
		VoiceAudio.save())
	add_slider("Combat ducking (dB)", 0.0, 3.0, GameAudio.combat_duck_db, func(v: float) -> void:
		GameAudio.combat_duck_db = v
		GameAudio.save())
	var loop := CheckButton.new()
	loop.text = "Local loopback test (no transmission)"
	loop.toggled.connect(func(on: bool) -> void: VoiceAudio.set_loopback(on))
	add_child(loop)
	_meter = ProgressBar.new()
	_meter.custom_minimum_size.y = 16
	_meter.show_percentage = false
	add_child(_meter)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

func add_slider(text: String, low: float, high: float, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 160
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size.x = 200
	slider.value_changed.connect(cb)
	row.add_child(slider)
	add_child(row)

func _process(_delta: float) -> void:
	_enable.set_pressed_no_signal(not VoiceAudio.hard_muted)
	_meter.value = VoiceAudio.level * 100.0
	_status.text = VoiceAudio.status

func _exit_tree() -> void:
	VoiceAudio.set_loopback(false)
