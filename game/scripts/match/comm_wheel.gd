class_name CommWheel
extends Control
## Hold the comms key (default middle mouse), move the mouse toward a slice, release to send it.
## Releasing in the centre sends nothing. The view does not turn while the wheel is open.
## Slices come from Comms.WHEEL: team callouts (spot/order pings), the open-radio toggle and the
## reserved hand-signals slice (disabled until hand signals exist).

signal chosen(entry: Variant) ## a Comms.Kind int, or "radio"

const OUTER := 190.0
const INNER := 58.0
const DEADZONE := 34.0

var radio_open := false ## drawn on the radio slice
var _cursor := Vector2.ZERO
var _hover := -1


func _init() -> void:
	name = "CommWheel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	_cursor = Vector2.ZERO
	_hover = -1
	visible = true
	queue_redraw()


func close(send: bool) -> void:
	if not visible:
		return
	visible = false
	if send and _hover >= 0:
		var entry: Variant = Comms.WHEEL[_hover]
		if not (entry is String and entry == "signals"):
			chosen.emit(entry)


func _input(event: InputEvent) -> void:
	var wheel_event := event.is_action("comm_wheel") if InputMap.has_action("comm_wheel") else false
	if wheel_event and not event.is_echo():
		if event.is_pressed() and not visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			open()
			get_viewport().set_input_as_handled()
		elif not event.is_pressed() and visible:
			close(true)
			get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		close(false)
		return
	if event is InputEventMouseMotion:
		_cursor += (event as InputEventMouseMotion).relative
		if _cursor.length() > OUTER:
			_cursor = _cursor.normalized() * OUTER
		_hover = _slice_at(_cursor)
		queue_redraw()
		get_viewport().set_input_as_handled() # no looking around while choosing


func _slice_at(v: Vector2) -> int:
	if v.length() < DEADZONE:
		return -1
	var n := Comms.WHEEL.size()
	var a := fposmod(v.angle() + PI * 0.5 + PI / n, TAU) # 0 = straight up, clockwise
	return int(a / (TAU / n)) % n


func _label(entry: Variant) -> String:
	if entry is String:
		return ("Radio: CLOSE channel" if radio_open else "Radio: open channel") if entry == "radio" else "Hand signals (soon)"
	return Comms.text(int(entry))


func _draw() -> void:
	var c := size * 0.5
	var n := Comms.WHEEL.size()
	var step := TAU / n
	draw_circle(c, OUTER + 8.0, Color(0, 0, 0, 0.35))
	for i in n:
		var entry: Variant = Comms.WHEEL[i]
		var a0 := -PI * 0.5 - step * 0.5 + i * step
		var pts := PackedVector2Array()
		for k in 9:
			pts.append(c + Vector2.from_angle(a0 + step * k / 8.0) * OUTER)
		for k in range(8, -1, -1):
			pts.append(c + Vector2.from_angle(a0 + step * k / 8.0) * INNER)
		var disabled: bool = entry is String and entry == "signals"
		var col := Color(0.12, 0.14, 0.17, 0.82)
		if i == _hover and not disabled:
			col = Color(0.2, 0.45, 0.6, 0.92)
		elif entry is String and entry == "radio" and radio_open:
			col = Color(0.15, 0.4, 0.2, 0.85)
		draw_colored_polygon(pts, col)
		draw_polyline(pts, Color(1, 1, 1, 0.18), 1.0)
		var mid := c + Vector2.from_angle(a0 + step * 0.5) * (INNER + OUTER) * 0.52
		var font := get_theme_default_font()
		var text := _label(entry)
		var fs := 13
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		var tc := Color(0.55, 0.55, 0.58) if disabled else (Comms.color(int(entry)) if entry is int else Color(0.85, 1.0, 0.85))
		draw_string(font, mid - Vector2(w * 0.5, -4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
	var font := get_theme_default_font()
	var hint := "release to send" if _hover >= 0 else "COMMS"
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
	draw_string(font, c - Vector2(hw * 0.5, -5), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
	draw_circle(c + _cursor, 4.0, Color(1, 1, 1, 0.9))
