class_name Comms
extends RefCounted
## Team callouts shared by the comms wheel (middle mouse), quick-ping keys, the host relay and the bots.
## `at`: where the host places the map marker — "aim" (what the caller looks at, up to 40 m),
## "self" (the caller), "site_a"/"site_b" (that bomb site) or "" (text only, no marker).
## `order`: what teammate bots do with it (see BotDirector.order()).

enum Kind { NONE, REGROUP_AIM, OBJECTIVE, GO_THERE, ENEMY, GO_A, GO_B, ON_ME, HOLD, BACKUP, FALL_BACK, AFFIRM, NEGATIVE, AS_YOU_WERE, BOMB_HERE }

const DEFS := {
	Kind.REGROUP_AIM: {"text": "Regroup there", "at": "aim", "order": "move", "color": Color(0.3, 0.9, 1.0)},
	Kind.OBJECTIVE: {"text": "Objective", "at": "aim", "order": "move", "color": Color(1.0, 0.75, 0.2)},
	Kind.GO_THERE: {"text": "Let's go there", "at": "aim", "order": "move", "color": Color(0.3, 0.9, 1.0)},
	Kind.ENEMY: {"text": "Enemy there!", "at": "aim", "order": "enemy", "color": Color(1.0, 0.3, 0.25)},
	Kind.GO_A: {"text": "Go to A", "at": "site_a", "order": "move", "color": Color(1.0, 0.75, 0.2)},
	Kind.GO_B: {"text": "Go to B", "at": "site_b", "order": "move", "color": Color(1.0, 0.75, 0.2)},
	Kind.ON_ME: {"text": "Regroup on me", "at": "self", "order": "follow", "color": Color(0.3, 0.9, 1.0)},
	Kind.HOLD: {"text": "Hold position", "at": "", "order": "hold", "color": Color(0.8, 0.85, 0.9)},
	Kind.BACKUP: {"text": "Need backup!", "at": "self", "order": "backup", "color": Color(1.0, 0.45, 0.3)},
	Kind.FALL_BACK: {"text": "Fall back", "at": "", "order": "fall_back", "color": Color(0.8, 0.85, 0.9)},
	Kind.AFFIRM: {"text": "Affirmative", "at": "", "order": "", "color": Color(0.5, 1.0, 0.55)},
	Kind.NEGATIVE: {"text": "Negative", "at": "", "order": "", "color": Color(1.0, 0.55, 0.5)},
	Kind.AS_YOU_WERE: {"text": "As you were (bots: free play)", "at": "", "order": "clear", "color": Color(0.8, 0.85, 0.9)},
	Kind.BOMB_HERE: {"text": "Bomb is here", "at": "aim", "order": "", "color": Color(1.0, 0.6, 0.1)},
}

## Comms wheel slices, clockwise from the top. "radio" toggles an open team radio; "signals" is reserved
## for hand signals (not built yet, shown disabled).
const WHEEL := [Kind.GO_THERE, Kind.ENEMY, Kind.GO_A, Kind.GO_B, Kind.ON_ME, Kind.HOLD, Kind.BACKUP,
	Kind.FALL_BACK, Kind.AFFIRM, Kind.NEGATIVE, Kind.AS_YOU_WERE, "radio", "signals"]
const MAX_KIND := Kind.BOMB_HERE


static func text(kind: int) -> String:
	return String(DEFS.get(kind, {}).get("text", "?"))


static func color(kind: int) -> Color:
	return DEFS.get(kind, {}).get("color", Color.WHITE)


static func placement(kind: int) -> String:
	return String(DEFS.get(kind, {}).get("at", ""))


static func order_of(kind: int) -> String:
	return String(DEFS.get(kind, {}).get("order", ""))
