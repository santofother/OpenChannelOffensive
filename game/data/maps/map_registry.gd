class_name MapRegistry
extends RefCounted
const SCENES := {"demo": "res://scenes/graybox.tscn", "lightwell": "res://scenes/maps/lightwell.tscn"}

static func identity(map_id: String) -> String:
	return LightwellLayout.new().identity() if map_id == "lightwell" else "demo/v1"

static func manifests() -> Dictionary:
	var out := {}
	for id: String in SCENES:
		out[id] = identity(id)
	return out
