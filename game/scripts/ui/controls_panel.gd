class_name ControlsPanel
extends PanelContainer
## Settings → Controls: one row per action. Click a binding, then press a key or mouse button.
## Esc cancels, Backspace/Delete unbinds. Saved immediately to user://controls.cfg (see core/controls.gd).

var C: Node ## the Controls autoload (looked up so --script tests can compile this class)
var _rows := {} ## action -> {button, warn}
var _listening := ""
var _listen_armed := false
var _status: Label


func _init() -> void:
	name = "ControlsPanel"
	C = Keys.ctl()
	custom_minimum_size = Vector2(470, 0)
	var box := VBoxContainer.new()
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func() -> void:
		_listening = ""
		C.reset_to_defaults())
	head.add_child(reset)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void:
		_listening = ""
		visible = false)
	head.add_child(close)
	_status = Label.new()
	_status.text = "Click a binding, then press a key or mouse button."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(450, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var category := ""
	for a: Array in C.actions():
		if a[3] != category:
			category = a[3]
			var cat := Label.new()
			cat.text = category.to_upper()
			cat.modulate = Color(0.65, 0.8, 1.0)
			list.add_child(cat)
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = a[1]
		l.custom_minimum_size.x = 210
		row.add_child(l)
		var b := Button.new()
		b.custom_minimum_size.x = 110
		var action: String = a[0]
		b.disabled = C.is_fixed(action)
		b.pressed.connect(func() -> void: _listen(action))
		row.add_child(b)
		var warn := Label.new()
		warn.modulate = Color(1.0, 0.75, 0.3)
		warn.add_theme_font_size_override("font_size", 12)
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(warn)
		list.add_child(row)
		_rows[action] = {"button": b, "warn": warn}
	C.changed.connect(_refresh)
	_refresh()


func _listen(action: String) -> void:
	_listening = action
	_listen_armed = false # the click that pressed the button must not become the binding
	(_rows[action].button as Button).text = "press…"
	_status.text = "Press a key or mouse button for \"%s\" · Esc cancels · Backspace unbinds" % C.label_of(action)
	get_tree().create_timer(0.15).timeout.connect(func() -> void: _listen_armed = true)


func _input(event: InputEvent) -> void:
	if _listening == "" or not visible:
		return
	var pressed := (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if not _listen_armed:
		return
	var action := _listening
	_listening = ""
	if event is InputEventKey:
		var code := (event as InputEventKey).physical_keycode
		if code == KEY_ESCAPE:
			_status.text = "Cancelled."
			_refresh()
			return
		if code == KEY_BACKSPACE or code == KEY_DELETE:
			C.rebind(action, "")
			_status.text = "%s is now unbound." % C.label_of(action)
			return
	var spec: String = C.spec_of(event)
	if spec == "":
		_refresh()
		return
	C.rebind(action, spec)
	var clash: Array = C.conflicts(action)
	_status.text = "%s → %s%s" % [C.label_of(action), Keys.key(action),
		"  (also used by: %s)" % ", ".join(clash) if not clash.is_empty() else ""]


func _refresh() -> void:
	for action: String in _rows:
		var r: Dictionary = _rows[action]
		var spec: String = C.current_spec(action)
		(r.button as Button).text = Keys.key(action) if spec != "" else "—"
		var clash: Array = C.conflicts(action)
		var note := ""
		if not clash.is_empty():
			note = "also: " + ", ".join(clash)
		elif spec != C.default_of(action):
			note = "default %s" % C.event_text(C.parse(C.default_of(action)))
		(r.warn as Label).text = note
