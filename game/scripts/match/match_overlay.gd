class_name MatchOverlay
extends Control
## Round result/MVP and objective guidance.
var loop: MatchLoop
var font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	visible = not loop.net.g._panel.visible and not loop.menu.is_open
	queue_redraw()

func caption(at: Vector2, text: String, color: Color = Color.WHITE, point_size: int = 18) -> void:
	draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, Color.BLACK)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, color)

func bomb_visible() -> bool:
	var r := loop.rules
	return loop.net.local_team() == r.attack_team and r.phase in [
		RoundRules.Phase.PREP, RoundRules.Phase.LIVE, RoundRules.Phase.PLANTED]

func _draw() -> void:
	if not loop or not font:
		return
	var r := loop.rules
	var vp := get_viewport_rect().size
	if Input.is_action_pressed("scoreboard"):
		_scoreboard(vp)
		return
	_health(vp)
	_objective_prompt(vp)
	var ended := r.phase in [RoundRules.Phase.RESOLUTION, RoundRules.Phase.RESULT]
	if ended:
		var won := r.winner == loop.net.local_team()
		var tint := Color(.4, 1, .7) if won else Color(1, .55, .4)
		var box := Rect2(Vector2(vp.x * .5 - 255, 18), Vector2(510, 144))
		draw_style_box(panel_style(), box)
		caption(box.position + Vector2(24, 38), ("MATCH " if r.phase == RoundRules.Phase.RESULT else "ROUND ") + ("WON" if won else "LOST"), tint, 30)
		caption(box.position + Vector2(24, 69), r.reason)
		caption(box.position + Vector2(24, 96), "Red %d — Blue %d · First to %d" % [r.scores[0], r.scores[1], r.wins_needed()])
		var mvp: Dictionary = loop.round_mvp
		caption(box.position + Vector2(24, 126), "Round MVP: %s" % mvp.get("name", "—"), Color(1, .85, .4), 20)
	if not ended:
		_spotted(vp)
	if bomb_visible() and not ended:
		var camera := get_viewport().get_camera_3d()
		var target := r.bomb_pos + Vector3.UP * .5
		if camera:
			var distance := camera.global_position.distance_to(target)
			var local := camera.to_local(target)
			var behind := local.z >= -.01
			var pt := Vector2(vp.x * .5 + signf(local.x) * vp.x * .35, vp.y - 190) if behind else camera.unproject_position(target)
			pt = pt.clamp(Vector2(100, 155), vp - Vector2(220, 170))
			var orange := Color(1, .7, .15)
			draw_circle(pt, 12, Color(.08, .07, .03, .9))
			draw_arc(pt, 12, 0, TAU, 24, orange, 2)
			caption(pt + Vector2(-5, 6), "B", orange, 17)
			var tag := "PLANTED · Site %s" % ["A", "B"][r.site] if r.phase == RoundRules.Phase.PLANTED else ("YOU HAVE BOMB" if r.carrier == loop.net.my_id else ("BOMB DROPPED" if r.carrier == 0 else "BOMB · " + str(loop.roster.get(r.carrier, {}).get("name", "teammate"))))
			caption(pt + Vector2(20, 5), "%s · %.0fm%s" % [tag, distance, " · behind" if behind else ""], orange, 16)

## Attackers see defenders who have stayed outside the building for too long.
func _spotted(vp: Vector2) -> void:
	var r := loop.rules
	var net := loop.net
	var camera := get_viewport().get_camera_3d()
	if camera == null or r.spotted.is_empty():
		return
	if net.local_team() != r.attack_team:
		if net.my_id in r.spotted:
			caption(Vector2(vp.x * .5 - 170, 150), "OUTSIDE · attackers can see you", Color(1, .4, .3), 20)
		return
	for id: int in r.spotted:
		var at := Vector3.INF
		if net.is_host and net.slots.has(id):
			at = (net.slots[id] as NetMatch.Slot).node.global_position
		elif net.remotes.has(id):
			at = (net.remotes[id] as NetMatch.Remote).pos
		if at == Vector3.INF:
			continue
		at += Vector3.UP * 2.1
		var local := camera.to_local(at)
		if local.z >= -.01:
			continue
		var pt := camera.unproject_position(at).clamp(Vector2(20, 20), vp - Vector2(20, 20))
		var red := Color(1, .3, .25)
		draw_colored_polygon(PackedVector2Array([pt + Vector2(-9, -14), pt + Vector2(9, -14), pt]), red)
		caption(pt + Vector2(12, -2), "SPOTTED %s · %.0fm" % [loop.roster.get(id, {}).get("name", ""),
			camera.global_position.distance_to(at)], red, 15)


func panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(.025, .04, .055, 1.0)
	s.border_color = Color(.3, .4, .45)
	s.set_border_width_all(1)
	return s


func _health(vp: Vector2) -> void:
	if not loop.net.local_alive():
		return
	var health := loop.net.local_health()
	var tint := Color(.97, .43, .32) if health <= 25 else Color(.59, .9, .84)
	var box := Rect2(Vector2(14, vp.y - 78), Vector2(142, 62))
	draw_style_box(panel_style(), box)
	caption(box.position + Vector2(12, 34), "%d HP" % health, Color.WHITE, 26)
	var bar := Rect2(box.position + Vector2(12, 45), Vector2(118, 5))
	draw_rect(bar, Color(.2, .28, .32))
	bar.size.x *= float(health) / NetMatch.MAX_HEALTH
	draw_rect(bar, tint)


func _objective_prompt(vp: Vector2) -> void:
	if not loop.net.local_alive():
		return
	var r := loop.rules
	var active := r.actor == loop.net.my_id and r.action_ticks > 0
	var planting := r.phase == RoundRules.Phase.LIVE and r.carrier == loop.net.my_id
	var defusing := r.phase == RoundRules.Phase.PLANTED and loop.net.local_team() != r.attack_team
	var in_site := planting and r.tuning.site_at(loop.net.g.player.global_position) >= 0
	if not ((planting or defusing) and (active or loop.objective_available(loop.net.my_id) or in_site)):
		return
	if planting and not active:
		var hint := Rect2(vp * Vector2(.5, .68) - Vector2(190, 0), Vector2(380, 44))
		draw_style_box(panel_style(), hint)
		var bomb_held: bool = loop.net.g.loadout.tool == Loadout.Tool.BOMB
		caption(hint.position + Vector2(16, 28), ("Hold %s to plant the bomb" % Keys.key("primary_fire")) if bomb_held
			else ("Press %s for the bomb, then hold %s to plant" % [Keys.key("tool_5"), Keys.key("primary_fire")]))
		return
	var box := Rect2(vp * Vector2(.5, .68) - Vector2(170, 0), Vector2(340, 68 if active else 44))
	draw_style_box(panel_style(), box)
	var key := Keys.key("interact")
	var label := "Planting bomb" if planting else "Defusing bomb"
	if not active:
		label = "Hold %s to defuse the bomb" % key
	caption(box.position + Vector2(16, 28), label)
	if active:
		var track := Rect2(box.position + Vector2(16, 43), Vector2(308, 10))
		draw_rect(track, Color(.21, .27, .32))
		track.size.x *= clampf(float(r.progress) / r.action_ticks, 0.0, 1.0)
		draw_rect(track, Color(1.0, .7, .22) if planting else Color(.38, .85, .78))


func _scoreboard(vp: Vector2) -> void:
	var r := loop.rules
	var rows: Array = loop.roster.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.team != b.team:
			return a.team < b.team
		if a.stats.points != b.stats.points:
			return a.stats.points > b.stats.points
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	var width := minf(vp.x - 32, 680)
	var box := Rect2(Vector2((vp.x - width) * .5, vp.y * .17), Vector2(width, 154 + 34 * rows.size()))
	draw_style_box(panel_style(), box)
	var left := box.position.x + 20
	var cols := [width - 262, width - 204, width - 133, width - 62]
	var y := box.position.y + 37
	caption(Vector2(left, y), "Red %d  /  Blue %d" % [r.scores[0], r.scores[1]], Color.WHITE, 26)
	y += 33
	for n in cols.size():
		caption(Vector2(box.position.x + cols[n] - 12, y), ["Kills", "Assists", "Deaths", "Points"][n], Color(.73, .79, .86), 15)
	var last_team := -1
	for row: Dictionary in rows:
		var tint := Color(1.0, .54, .48) if row.team == 0 else Color(.49, .78, 1.0)
		if row.team != last_team:
			last_team = row.team
			y += 32
			var attack := int(row.team) == r.attack_team
			caption(Vector2(left, y), ("RED" if row.team == 0 else "BLUE") + ("  ·  ATTACK" if attack else "  ·  DEFEND"), tint, 15)
		y += 34
		var name := String(row.name)
		var text_color := Color.WHITE if row.alive else Color(.68, .72, .76)
		draw_string(font, Vector2(left, y), name, HORIZONTAL_ALIGNMENT_LEFT, width - 298, 18, text_color)
		for n in cols.size():
			var value := int(row.stats[["kills", "assists", "deaths", "points"][n]])
			caption(Vector2(box.position.x + cols[n], y), str(value), text_color, 17)
