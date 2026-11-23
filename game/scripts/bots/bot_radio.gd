class_name BotRadio
extends RefCounted
## Short, pre-rendered lines on the virtual handset. The host picks the phrase and room.
const ROOMS := {
	"a": "Site A", "b": "Site B", "reception": "Reception", "conference": "Conference",
	"server_staging": "Server Staging", "lobby": "Lobby", "north_ring": "North Ring",
	"west": "West Hall", "courtyard": "Courtyard", "east": "East Hall", "south_ring": "South Ring",
	"electrical": "Electrical", "loading_staging": "Loading Staging", "workshop": "Workshop",
	"stores": "Stores", "hallway": "the hallway", "outside": "Outside", "office": "the office",
	"loading": "Loading",
}

enum Kind { CONTACT, RESPONDING, NO_BOMB, SECURED, BOMB_HERE, DEFUSING, RELOADING, AFFIRM }
const KEYS := ["contact", "responding", "no_bomb", "secured", "bomb_here", "defusing", "reloading", "affirm"]


static func room_key(label: String) -> String:
	if label.begins_with("A ·"):
		return "a"
	if label.begins_with("B ·"):
		return "b"
	var key := label.to_lower().replace(" ", "_")
	return key if ROOMS.has(key) else "hallway"


static func text(kind: int, room: String) -> String:
	var label: String = ROOMS[room]
	match kind:
		Kind.CONTACT:
			return "Contact outside. Need backup." if room == "outside" else "Contact at %s. Need backup." % label
		Kind.RESPONDING:
			return "I'm outside. On my way." if room == "outside" else "I'm at %s. On my way." % label
		Kind.NO_BOMB:
			return "No bomb at %s." % label
		Kind.SECURED:
			return "%s secured." % label
		Kind.BOMB_HERE:
			return "Found the bomb at %s." % label
		Kind.DEFUSING:
			return "I'm on the defuse. Cover me."
		Kind.RELOADING:
			return "Reloading. Cover me."
		Kind.AFFIRM:
			return "Copy. Moving."
	return ""


static func cue(kind: int, room: String, alternate := false) -> String:
	var suffix := "_2" if alternate else ""
	return "bot_radio_%s%s%s" % [KEYS[kind], "_" + room if kind <= Kind.BOMB_HERE else "", suffix]
