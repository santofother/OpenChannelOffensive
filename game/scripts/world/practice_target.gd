class_name PracticeTarget
extends StaticBody3D
## Shootable practice silhouette. Collision layer 3 ("targets"). Falls over when its health reaches 0.

signal downed(target: PracticeTarget)

const MAX_HEALTH := 100.0

var health := MAX_HEALTH
var alive := true
var _mat: StandardMaterial3D
var _base := Color(0.85, 0.2, 0.15)
var _tween: Tween


func setup(id: String, pos: Vector3, yaw_deg: float = 0.0) -> void:
	name = id
	position = pos
	rotation.y = deg_to_rad(yaw_deg)
	collision_layer = 4
	collision_mask = 0
	var size := Vector3(0.5, 1.7, 0.12)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y * 0.5
	add_child(cs)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _base
	_mat.emission_enabled = true
	_mat.emission = Color.BLACK
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat
	mi.mesh = bm
	mi.position.y = size.y * 0.5
	add_child(mi)


## Returns true if this hit downed the target.
func apply_damage(amount: float) -> bool:
	if not alive:
		return false
	health = maxf(health - amount, 0.0)
	_mat.emission = Color(0.8, 0.8, 0.8)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_mat, "emission", Color.BLACK, 0.12)
	if health <= 0.0:
		alive = false
		collision_layer = 0
		_tween.parallel().tween_property(self, "rotation:x", -PI * 0.5, 0.3)
		downed.emit(self)
		return true
	return false


func reset() -> void:
	_kill_tween()
	health = MAX_HEALTH
	alive = true
	collision_layer = 4
	rotation.x = 0.0
	_mat.emission = Color.BLACK


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
