extends RefCounted
## Each furniture envelope is a normal breakable cover module. Its cosmetic
## details travel with it and vanish when the authority removes or reinforces it.
const WOOD := ["desk", "meeting", "table", "credenza", "bench", "workbench"]

static func material_key(kind: String) -> String:
	if kind in WOOD:
		return "wood"
	if kind == "screen":
		return "siding"
	if kind in ["rack", "panel", "shelf", "locker", "files", "printer"]:
		return "painted_metal"
	if kind in ["pallet", "box"]:
		return "cork"
	if kind in ["chair", "divider", "sofa"]:
		return "fabric_tan"
	return "case"

static func dress(module: WallModule, kind: String) -> void:
	var detail := Node3D.new()
	detail.name = "FurnitureDetails"
	module.add_child(detail)
	var span := module._size
	var top := span.y * .5
	var front := span.z * .5
	match kind:
		"desk", "meeting", "table", "credenza", "bench", "workbench":
			_part(detail, Vector3(span.x + .055,.07,span.z + .05), Vector3(0,top,0), "wood")
			if kind in ["desk", "workbench"]:
				_part(detail, Vector3(.33,.23,.035), Vector3(-span.x*.2,top+.21,-front*.3), "screen")
				_part(detail, Vector3(.11,.15,.08), Vector3(-span.x*.2,top+.085,-front*.3), "trim")
				_part(detail, Vector3(.29,.025,.11), Vector3(-span.x*.2,top+.045,front*.23), "plastic")
			if kind != "bench":
				_part(detail, Vector3(.27,.025,.21), Vector3(span.x*.24,top+.043,front*.24), "paper")
				_part(detail, Vector3(.19,.065,.13), Vector3(span.x*.16,top+.065,-front*.32), "case")
		"locker", "files", "panel", "rack", "shelf", "printer":
			var bands := 5 if kind == "rack" else 3
			for i in bands:
				var y := -top + span.y * float(i + 1) / float(bands + 1)
				_part(detail, Vector3(span.x*.92,.035,.025), Vector3(0,y,front + .008), "trim")
				if kind == "rack" or kind == "panel":
					_part(detail, Vector3(.065,.029,.027), Vector3(span.x*.28,y+.05,front+.017), "lamp_cool")
				else:
					_part(detail, Vector3(.13,.035,.039), Vector3(0,y+.075,front+.024), "metal_plate")
			if kind == "rack" or kind == "panel":
				for side in [-1.0,1.0]:
					var access := Node3D.new()
					access.rotation.y = float(side) * PI * .5
					access.position.x = float(side) * (span.x*.5+.012)
					detail.add_child(access)
					_part(access,Vector3(span.z*.81,span.y*.84,.035),Vector3.ZERO,"plastic")
					for i in 7:
						var y := span.y * (float(i) / 9.0 - .33)
						_part(access,Vector3(span.z*.68,.04,.028),Vector3(0,y,.029),"metal_plate")
						if i % 2 == 0:
							_part(access,Vector3(.05,.022,.022),Vector3(span.z*.25,y+.037,.033),"lamp_cool")
			if kind == "printer":
				_part(detail, Vector3(span.x*.62,.06,span.z*.5), Vector3(0,top+.012,0), "plastic")
				_part(detail, Vector3(.22,.024,.29), Vector3(0,top+.05,.06), "paper")
			elif kind in ["files", "shelf"]:
				_part(detail, Vector3(.25,.18,.26), Vector3(-span.x*.22,top+.085,0), "cork")
		"pallet", "box", "case", "screen":
			var strap := "metal_plate" if kind == "screen" or kind == "case" else "fabric_dark"
			for offset in [-.28,.28]:
				_part(detail, Vector3(.055,span.y,.03), Vector3(span.x*offset,0,front+.012), strap)
				_part(detail, Vector3(.055,.028,span.z), Vector3(span.x*offset,top+.012,0), strap)
			_part(detail, Vector3(minf(span.x*.5,.31),.16,.022), Vector3(0,top*.38,front+.011),
				"lamp_warm" if kind == "screen" else "paper")
		"sofa", "chair", "divider":
			_part(detail, Vector3(span.x*.98,.10,span.z*.84), Vector3(0,top,0), "fabric_dark")
			_part(detail, Vector3(span.x*.76,.095,.035), Vector3(0,top*.33,front+.013), "fabric_dark")
		"plant", "planter":
			for i in 5:
				var leaf := _part(detail, Vector3(span.x*.23,.085,span.z*.55),
					Vector3(span.x * (i-2) * .13,top+.04+i*.015,0), "foliage")
				leaf.rotation.y = i * 1.2
				leaf.rotation.z = (i-2) * .16
	_watch_support(module, detail)


static func add_baseboard(module: WallModule) -> void:
	var detail := Node3D.new()
	detail.name = "Baseboard"
	module.add_child(detail)
	for side in [-1.0,1.0]:
		_part(detail, Vector3(module._size.x,.1,.021),
			Vector3(0,-module._size.y*.5+.05, (module._size.z*.5 + .008) * side), "trim")
	_watch_support(module, detail)


static func add_sign(module: WallModule, text: String, side: float) -> void:
	var detail := Node3D.new()
	detail.name = "DoorSign"
	detail.rotation.y = 0 if side > 0 else PI
	detail.position.z = (module._size.z * .5 + .013) * side
	detail.position.y = -.08
	module.add_child(detail)
	_part(detail, Vector3(minf(module._size.x-.05,.39+text.length()*.037),.18,.03), Vector3.ZERO, "trim")
	var label := Label3D.new()
	label.text = text
	label.font_size = 34
	label.pixel_size = .0023
	label.position.z = .022
	label.double_sided = false
	label.outline_size = 0
	label.modulate = Color(.82,.9,.94) if text.begins_with("A ·") else Color(.95,.86,.70)
	detail.add_child(label)
	_watch_support(module,detail)


static func _watch_support(module: WallModule, detail: Node3D) -> void:
	module.state_changed.connect(func(m: WallModule) -> void:
		detail.visible = m.state == WallModule.State.INTACT and m.material == WallModule.Mat.ORDINARY and m.openings.is_empty() and m.detached.is_empty())


static func _part(parent: Node3D, size: Vector3, pos: Vector3, key: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = Surfaces.get_mat(key)
	node.mesh = mesh
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
