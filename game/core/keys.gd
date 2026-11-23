class_name Keys
extends RefCounted
## Static access to the Controls autoload for game scripts. Scripts that name the autoload directly fail to
## compile in headless `--script` tests (autoload names are not registered there), so HUD/menu code calls
## Keys.key("interact") instead of Controls.key("interact").


static func ctl() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Controls") if tree else null


## Readable binding for HUD hints ("F", "MMB", ...).
static func key(action: String) -> String:
	var c := ctl()
	return c.key(action) if c else "?"
