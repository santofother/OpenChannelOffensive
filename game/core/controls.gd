extends Node
## Every rebindable action and its DEFAULT binding live here — the single place to change default keys.
## At startup the defaults are written into the InputMap, then the player's saved overrides
## (`user://controls.cfg`, written by the Controls settings panel) replace them.
##
## Binding strings: a key name as Godot spells it ("W", "Shift", "Space", "Tab", "Enter", "Escape", "F1")
## or a mouse button: "Mouse1" left, "Mouse2" right, "Mouse3" middle, "Mouse4"/"Mouse5" wheel up/down,
## "Mouse8"/"Mouse9" side buttons. Keys bind by physical position (layout-independent).

signal changed

const SAVE_PATH := "user://controls.cfg"

## [action, label shown in settings, default binding, category]
const ACTIONS := [
	["move_forward", "Move forward", "W", "Movement"],
	["move_back", "Move back", "S", "Movement"],
	["move_left", "Move left", "A", "Movement"],
	["move_right", "Move right", "D", "Movement"],
	["crouch", "Crouch (hold)", "C", "Movement"],
	["slow_walk", "Slow walk (hold)", "Shift", "Movement"],
	["jump", "Vault low cover", "Space", "Movement"],
	["lean_left", "Lean left", "Q", "Movement"],
	["lean_right", "Lean right", "E", "Movement"],
	["primary_fire", "Fire / use", "Mouse1", "Combat"],
	["aim", "Aim down sights", "Mouse2", "Combat"],
	["reload", "Reload", "R", "Combat"],
	["tool_1", "Primary gun", "1", "Combat"],
	["tool_2", "Sidearm", "2", "Combat"],
	["tool_3", "Ordinary charge", "3", "Combat"],
	["tool_4", "Heavy charge", "4", "Combat"],
	["tool_5", "Reinforcement kit (attack: bomb)", "5", "Combat"],
	["holster", "Holster equipment / empty hands", "0", "Combat"],
	["tool_6", "Medkit", "6", "Combat"],
	["grenade_cycle", "Cycle grenades", "G", "Combat"],
	["flashlight", "Flashlight", "L", "Combat"],
	["laser", "Laser sight", "K", "Combat"],
	["nightvision", "Night vision", "N", "Combat"],
	["melee", "Melee / kick door", "V", "Combat"],
	["interact", "Use door, pick up weapon or radio, use bomb", "F", "Objective"],
	["zip_tie", "Zip-tie door shut (hold)", "X", "Objective"],
	["drop_bomb", "Drop bomb", "J", "Objective"],
	["buy_menu", "Buy menu (open / close)", "B", "Objective"],
	["comm_wheel", "Comms wheel (hold)", "Mouse3", "Comms"],
	["push_to_talk", "Team radio (hold)", "T", "Comms"],
	["enemy_radio_mute", "Mute / unmute stolen enemy radio", "O", "Comms"],
	["command_regroup", "Quick ping: regroup", "H", "Comms"],
	["command_objective", "Quick ping: objective", "P", "Comms"],
	["mute_toggle", "Hard mute microphone", "M", "Comms"],
	["ready_toggle", "Lobby: ready / unready", "Y", "Match"],
	["team_switch", "Lobby: change team", "U", "Match"],
	["rematch", "Host: rematch", "Enter", "Match"],
	["scoreboard", "Scoreboard (hold)", "Tab", "Match"],
	["spectate_next", "Spectate next teammate", "Right", "Match"],
	["take_over_bot", "Take over spectated bot", "Enter", "Match"],
	["reset", "Restart (offline / dev)", "F8", "Match"],
	["menu", "Pause / settings", "Escape", "Match"],
]
const SHARED_OK := [["rematch", "take_over_bot"]]
## Escape always opens the pause menu, so a bad binding can never lock a player out of settings.
const FIXED := ["menu"]


func _init() -> void:
	# Before any scene (and before other autoloads' _ready) so the InputMap is complete from the first frame.
	_apply_defaults()
	_load()


func is_fixed(action: String) -> bool:
	return action in FIXED


func actions() -> Array:
	return ACTIONS


func default_of(action: String) -> String:
	for a: Array in ACTIONS:
		if a[0] == action:
			return a[2]
	return ""


func label_of(action: String) -> String:
	for a: Array in ACTIONS:
		if a[0] == action:
			return a[1]
	return action


## Human-readable binding for HUD hints, e.g. key("interact") -> "F", key("comm_wheel") -> "MMB".
func key(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	var evs := InputMap.action_get_events(action)
	return event_text(evs[0]) if not evs.is_empty() else "unbound"


static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
			MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
			MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5"}.get(
			(ev as InputEventMouseButton).button_index, "Mouse %d" % (ev as InputEventMouseButton).button_index)
	return "?"


## Binding string -> InputEvent (null if the string is not understood).
static func parse(spec: String) -> InputEvent:
	if spec.begins_with("Mouse") and spec.substr(5).is_valid_int():
		var mb := InputEventMouseButton.new()
		mb.button_index = int(spec.substr(5)) as MouseButton
		return mb
	var code := OS.find_keycode_from_string(spec)
	if code == KEY_NONE:
		return null
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


## InputEvent -> binding string (the inverse of parse), or "" for events that cannot be bindings.
static func spec_of(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(code) if code != KEY_NONE else ""
	if ev is InputEventMouseButton:
		return "Mouse%d" % (ev as InputEventMouseButton).button_index
	return ""


func _set_event(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)
	InputMap.action_erase_events(action)
	if ev:
		InputMap.action_add_event(action, ev)


func _apply_defaults() -> void:
	for a: Array in ACTIONS:
		_set_event(a[0], parse(a[2]))


## Rebind one action (spec "" = unbound) and save. FIXED actions keep their default.
func rebind(action: String, spec: String) -> void:
	if action in FIXED:
		return
	_set_event(action, parse(spec) if spec != "" else null)
	save()
	changed.emit()


func reset_to_defaults() -> void:
	_apply_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	changed.emit()


func current_spec(action: String) -> String:
	var evs := InputMap.action_get_events(action) if InputMap.has_action(action) else []
	return spec_of(evs[0]) if not evs.is_empty() else ""


## Other actions using the same binding (excluding deliberate shared defaults).
func conflicts(action: String) -> Array[String]:
	var out: Array[String] = []
	var mine := current_spec(action)
	if mine == "":
		return out
	for a: Array in ACTIONS:
		var other: String = a[0]
		if other == action or current_spec(other) != mine:
			continue
		var shared := false
		for pair: Array in SHARED_OK:
			if action in pair and other in pair:
				shared = true
		if not shared:
			out.append(label_of(other))
	return out


## Only actions that differ from the defaults are written, so changing a default in ACTIONS reaches
## everyone who never customised that key.
func save() -> void:
	var cfg := ConfigFile.new()
	for a: Array in ACTIONS:
		var spec := current_spec(a[0])
		if spec != a[2]:
			cfg.set_value("bindings", a[0], spec)
	cfg.save(SAVE_PATH)


func _load() -> void:
	if DisplayServer.get_name() == "headless":
		return # headless tests always run on the defaults, whatever this machine's player saved
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for a: Array in ACTIONS:
		if a[0] in FIXED or not cfg.has_section_key("bindings", a[0]):
			continue
		var spec := String(cfg.get_value("bindings", a[0], a[2]))
		_set_event(a[0], parse(spec) if spec != "" else null)
