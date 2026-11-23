class_name ShopMenu
extends CanvasLayer
## CS-style buy menu: opens automatically when prep starts (B reopens), B / Esc close; spans ~94% of the
## screen width. Columns per category; click an item or press the column number then
## the item number. Purchases go through MatchLoop.request_buy (host validates, atomic, request IDs).
var loop: MatchLoop
var is_open := false
var _root: Control
var _debug_toggle: Button
var _debug_fill: Button
var _header: Label
var _equipment: Label
var _recipient: OptionButton
var _recipients := {}
var _feedback: Label
var _hint: Label
var _cols := [] ## per category: [{id, button}]
var _picked := -1
var _refresh_in := 0.0

func _ready() -> void:
	layer = 20
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025, .035, .05, .97)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_root.add_theme_stylebox_override("panel", style)
	add_child(_root)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 24)
	box.add_child(_header)
	var recipient_row := HBoxContainer.new()
	recipient_row.add_theme_constant_override("separation", 12)
	box.add_child(recipient_row)
	var label := Label.new()
	label.text = "Buy for"
	recipient_row.add_child(label)
	_recipient = OptionButton.new()
	_recipient.custom_minimum_size.x = 170
	_update_recipients()
	_recipient.item_selected.connect(func(_index: int) -> void:
		_feedback.text = ""
		_refresh())
	recipient_row.add_child(_recipient)
	_equipment = Label.new()
	recipient_row.add_child(_equipment)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var colored := [Color(0.5, 0.9, 0.8), Color(0.55, 0.8, 1.0), Color(0.8, 0.8, 1.0), Color(1.0, 0.85, 0.5),
		Color(1.0, 0.6, 0.4), Color(0.7, 0.7, 0.7), Color(0.7, 0.7, 0.7)]
	for c in ShopCatalog.CATEGORIES.size():
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 150
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)
		var title := Label.new()
		title.text = "%d  %s" % [c + 1, ShopCatalog.CATEGORIES[c]]
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", colored[c])
		col.add_child(title)
		var entries := []
		var n := 0
		for it: Dictionary in ShopCatalog.ITEMS:
			if int(it.cat) != c:
				continue
			n += 1
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size.y = 72
			b.add_theme_font_size_override("font_size", 14)
			b.clip_text = true
			var icon_path := "res://assets/icons/" + ("helmet" if it.id == "armor_helmet" else String(it.id)) + ".png"
			if ResourceLoader.exists(icon_path):
				b.icon = load(icon_path)
				b.expand_icon = true
				b.add_theme_constant_override("icon_max_width", 18 if it.id == "armor_helmet" else 32)
			b.pressed.connect(func() -> void: _buy(String(it.id)))
			col.add_child(b)
			entries.append({"id": it.id, "button": b, "n": n})
		_cols.append(entries)
	var debug_row := HBoxContainer.new()
	box.add_child(debug_row)
	_debug_toggle = Button.new()
	_debug_toggle.pressed.connect(func() -> void: loop.request("debug_money_toggle"))
	debug_row.add_child(_debug_toggle)
	_debug_fill = Button.new()
	_debug_fill.pressed.connect(func() -> void: loop.request("debug_money_fill"))
	debug_row.add_child(_debug_fill)
	_feedback = Label.new()
	_feedback.add_theme_color_override("font_color", Color(.72, .94, .91))
	box.add_child(_feedback)
	_hint = Label.new()
	_hint.text = "Click an item, or press a column number then an item number · %s close · %s reopen" % [Keys.key("buy_menu"), Keys.key("buy_menu")]
	box.add_child(_hint)

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	is_open = true
	_picked = -1
	_recipient.select(0)
	_feedback.text = ""
	_root.visible = true
	var vp := get_viewport().get_visible_rect().size
	_root.reset_size()
	_root.size = Vector2(vp.x * 0.94, _root.get_combined_minimum_size().y)
	_root.position = Vector2(vp.x * 0.03, maxf(16.0, (vp.y - _root.size.y) * 0.5))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _buy(id: String) -> void:
	loop.request_buy(id, _selected_recipient())
	_refresh_in = 0.1


func show_feedback(message: String) -> void:
	_feedback.text = message


func _selected_recipient() -> int:
	return int(_recipient.get_selected_metadata()) if _recipient.selected >= 0 else 0


func _update_recipients() -> void:
	var choices := {0: "You"}
	for id: int in loop.roster:
		var row: Dictionary = loop.roster[id]
		if id != loop.net.my_id and row.team == loop.net.local_team() and row.alive:
			choices[id] = String(row.name)
	if choices == _recipients:
		return
	var selected := _selected_recipient()
	_recipients = choices
	_recipient.clear()
	var index := 0
	for id: int in choices:
		_recipient.add_item(choices[id])
		var entry := _recipient.item_count - 1
		_recipient.set_item_metadata(entry, id)
		if id == selected:
			index = entry
	_recipient.select(index)

func _input(event: InputEvent) -> void:
	if not is_open or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.physical_keycode
	if k == KEY_ESCAPE or event.is_action_pressed("buy_menu"):
		close()
		get_viewport().set_input_as_handled()
	elif k >= KEY_1 and k <= KEY_9:
		var n: int = k - KEY_1
		if _picked < 0:
			if n < _cols.size():
				_picked = n
		else:
			for e: Dictionary in _cols[_picked]:
				if int(e.n) == n + 1:
					_buy(String(e.id))
			_picked = -1
		_refresh()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_open:
		return
	if loop.rules.phase != RoundRules.Phase.PREP or not loop.net.local_alive():
		close()
		return
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = 0.2
		_refresh()

func _refresh() -> void:
	var net := loop.net
	var lo: Loadout = net.g.loadout
	var attacker := net.local_team() == loop.rules.attack_team
	var now := float(net.tick) if net.is_host else net._server_tick_f
	var left := maxi(0, int(ceil((loop.rules.deadline - now) / 60.0)))
	_header.text = "$%d      Buy Time Remaining  %02d:%02d      %s" % [loop.credits, left / 60, left % 60,
		"ATTACK" if attacker else "DEFEND"]
	_update_recipients()
	var recipient := _selected_recipient()
	var gear: Dictionary = loop.teammate_shop.get(recipient, {})
	var armor := lo.armor if recipient == 0 else int(gear.get("armor", 0))
	var helmet := lo.helmet if recipient == 0 else bool(gear.get("helmet", false))
	var kit := lo.defuse_kit if recipient == 0 else bool(gear.get("defuse_kit", false))
	_equipment.text = "Armor %d / 100 · Helmet %s%s" % [armor, "YES" if helmet else "NO", " · Defuse kit" if kit else ""]
	_debug_toggle.visible = net.is_host and loop.debug_tools_available()
	_debug_toggle.text = "Debug money: %s (host)" % ("ON" if loop.debug_money else "OFF")
	_debug_fill.visible = loop.debug_money
	_debug_fill.text = "Debug: fill wallet to $%d" % loop.econ.tuning.credit_cap
	_debug_fill.disabled = loop.credits >= loop.econ.tuning.credit_cap
	var buyable := ShopCatalog.buyable(attacker)
	for c in _cols.size():
		for e: Dictionary in _cols[c]:
			var it := ShopCatalog.find(String(e.id))
			var b: Button = e.button
			var role: String = it.get("role", "")
			b.visible = role == "" or (role == "attack") == attacker
			var price := loop.econ.price(it.id)
			var owned := ShopCatalog.owned(lo, it.id) if recipient == 0 else int(gear.get("owned", {}).get(it.id, 0))
			var tag := ""
			var ok := true
			if it.get("soon", false):
				tag = "  soon"
				ok = false
			elif it.id == "encrypt" and loop.team_encrypted:
				tag = "  team has one"
				ok = false
			elif owned >= loop.econ.limit(it.id):
				tag = "  owned" if int(it.get("limit", 9)) == 1 and not it.has("role") else "  max"
				ok = false
			elif loop.credits < price:
				ok = false
			var short_name: String = {"smg": "SMG", "carbine": "Carbine", "revolver": "Revolver", "flashlight": "Flashlight", "kit": "Reinforce Kit", "encrypt": "Encrypted Radio", "silencer": "Silencer", "zip_tie": "Zip Tie", "armor_helmet": "Vest + Helmet", "ordinary": "Charge", "heavy": "Heavy Charge", "service_rifle": "Service Rifle", "marksman": "Marksman", "flash": "Flashbang", "smoke": "Smoke", "incendiary": "Incendiary", "frag": "Frag", "nightvision": "Night Vision"}.get(it.id, it.name)
			b.text = "%d  %s\n$%d%s" % [e.n, short_name, price, tag]
			if it.id == "zip_tie":
				b.text = "%s\n$%d each  ·  %d/%d" % [short_name, price, owned, loop.econ.limit(it.id)]
			b.tooltip_text = "%s — $%d%s" % [it.name, price, tag]
			b.disabled = not ok
			b.modulate = Color(1, 1, 1) if ok else (Color(1.0, 0.5, 0.5) if loop.credits < price and not it.get("soon", false) else Color(0.6, 0.6, 0.6))
			if it.id in buyable and ok and c == _picked:
				b.modulate = Color(0.6, 1.0, 0.7)
