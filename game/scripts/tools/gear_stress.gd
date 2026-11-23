class_name GearStress
extends Node
## Synthetic rendering load, not a substitute for a real six-player hardware playtest.
var g: Node3D
var actors: Array[Node3D] = []
var elapsed := 0.0
func start(world: Node3D) -> void:
	g = world
	g.loadout.gadgets_owned = 7
	g.loadout.gadgets_on = 1
	for i in 6:
		var actor := StandIn.build(StandIn.TEAM_BLUE if i % 2 else StandIn.TEAM_RED)
		g.add_child(actor)
		StandIn.equip(actor, "service_rifle", 100, true, 7, 3)
		actors.append(actor)
	for i in 6:
		g.gadgets.zones.append({"id": 10000 + i, "kind": "smoke" if i % 2 else "incendiary", "owner": 1,
			"pos": Vector3(4.0 + i % 3 * 1.5, .1, -3.0 - i / 3 * 4.0), "left": 999.0})
func _process(delta: float) -> void:
	elapsed += delta
	var rows := []
	for i in actors.size():
		var actor := actors[i]
		actor.position = Vector3(3.0 + i % 3 * 2.0 + sin(elapsed + i) * .4, 0, -3.0 - i / 3 * 4.0)
		actor.rotation.y = sin(elapsed * .6 + i)
		rows.append([10 + i, actor.position + Vector3.UP * 1.5, -actor.basis.z, 7, 3, [], "service_rifle", "p9", 100, true, 0])
	g.gadgets.debug_rows = rows
