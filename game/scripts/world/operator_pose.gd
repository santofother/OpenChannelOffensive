class_name OperatorPose
extends Node
## Cosmetic in-place posing in skeleton space. No transforms are written to the player.
## Long guns sit in the right shoulder pocket with the torso bladed and the support hand on the
## handguard; pistols use a two-handed compressed ready that extends to an isosceles stance on aim.

## Gun-local distance from the grip origin to the support hand, from the Blender Hand_L sockets.
const SUPPORT := {"carbine": .28, "service_rifle": .315, "marksman": .315, "smg": .219}
## Gun-local sight point (height above the grip origin, z) from the viewmodel Sight sockets.
const SIGHT := {"carbine": Vector2(.122, -.055), "service_rifle": Vector2(.12, -.052), "marksman": Vector2(.118, -.003),
		"smg": Vector2(.107, -.044), "p9": Vector2(.018, .08), "p9_match": Vector2(.029, .07), "revolver": Vector2(.059, -.002)}
## Gun-local z of the butt plate (rear of the stock).
const BUTT := {"carbine": .198, "service_rifle": .198, "marksman": .258, "smg": .07}
## Right eye in rest model space; aimed guns put their sight on this line.
const EYE := Vector3(.034, 1.66, -.085)
## Rest-space right shoulder pocket (between the pectoral and the shoulder joint) for a lowered long gun.
const POCKET := Vector3(.1, 1.46, -.07)

var socket: Node3D
var rig: Skeleton3D
var breath := 0.0
var fall := 0.0
var phase := 0.0
var reload_time := 0.0
var delta_rest := {}
var sidearm := false
var armed := true
var support := .3
var sight := Vector2(.12, -.05)
var butt := .2
## Smoothed 0..1 raise from the ready position to the aimed hold.
var raise := 0.0

func setup(model: Node3D) -> void:
	socket = GearModels.socket(model, "Weapon")
	rig = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in rig.get_bone_count():
		delta_rest[rig.get_bone_name(i)] = rig.get_bone_global_rest(i).affine_inverse()

func set_weapon(weapon: String) -> void:
	armed = weapon != ""
	sidearm = weapon in ["p9", "p9_match", "revolver"]
	support = SUPPORT.get(weapon, .3)
	sight = SIGHT.get(weapon, Vector2(.12, -.05))
	butt = BUTT.get(weapon, .2)

func _joint(bone: String) -> Vector3:
	return rig.get_bone_global_pose(rig.find_bone(bone)).origin

func _offset(bone: String) -> Transform3D:
	return rig.get_bone_global_pose(rig.find_bone(bone)) * Transform3D(delta_rest[bone])

func _rotate(bone: String, rotation: Basis) -> void:
	var i := rig.find_bone(bone)
	var pose := rig.get_bone_global_pose(i)
	pose.basis = rotation * rig.get_bone_global_rest(i).basis
	rig.set_bone_global_pose(i, pose)

## Bend a child bone about a rest-space axis, on top of whatever its parent is doing.
func _bend(bone: String, parent: String, axis: Vector3, angle: float) -> void:
	_rotate(bone, _offset(parent).basis * Basis(axis, angle))

## Rotation taking the rest hand frame (fingers along ±X, palm down) to the target frame.
static func _hand_frame(s: int, along: Vector3, palm: Vector3) -> Basis:
	var a := along.normalized()
	var p := (palm - a * a.dot(palm)).normalized()
	var rest := Basis(Vector3(s, 0, 0), Vector3.DOWN, Vector3(s, 0, 0).cross(Vector3.DOWN))
	return Basis(a, p, a.cross(p)) * rest.inverse()

## Two-link analytic solve. The pole selects an elbow or knee bend plane. When `twist` is given
## (the end bone's rotation), the lower bone takes part of its roll so wrists do not candy-wrap.
func _limb(upper: String, lower: String, end: String, goal: Vector3, pole: Vector3, twist = null) -> void:
	var origin := _joint(upper)
	var first := rig.get_bone_global_rest(rig.find_bone(lower)).origin - rig.get_bone_global_rest(rig.find_bone(upper)).origin
	var second := rig.get_bone_global_rest(rig.find_bone(end)).origin - rig.get_bone_global_rest(rig.find_bone(lower)).origin
	var axis := origin.direction_to(goal)
	var distance := clampf(origin.distance_to(goal), .06, first.length()+second.length()-.0001)
	var along := (first.length_squared()-second.length_squared()+distance*distance)/(2.0*distance)
	var elbow := axis*along + pole.slide(axis).normalized()*sqrt(maxf(0, first.length_squared()-along*along))
	var reach := (axis*distance-elbow).normalized()
	_rotate(upper, Basis(Quaternion(first.normalized(), elbow.normalized())))
	var swing := Quaternion(second.normalized(), reach)
	if twist is Basis:
		var follow := Quaternion(twist * second.normalized(), reach) * Quaternion(twist)
		swing = swing.slerp(follow, .6)
	_rotate(lower, Basis(swing))

func _attach(label: String, xf: Transform3D) -> void:
	var item := get_parent().get_node_or_null(NodePath(label)) as Node3D
	if item:
		item.transform = xf

func update(dt: float, velocity: Vector3, height: float, pitch: float, lean: float, aim: bool, reload: bool, kick: float, alive: bool) -> void:
	var speed := Vector2(velocity.x,velocity.z).length() if alive else 0.0
	phase = fmod(phase + dt * minf(speed*3.8, 12.0), TAU)
	reload_time = reload_time + dt if reload else 0.0
	var crouch := clampf((1.8-height)/.6, 0, 1)
	breath = fmod(breath + dt*1.9, TAU)
	fall = 0.0 if alive else move_toward(fall, 1.0, dt*2.8)
	var fallen := smoothstep(0, 1, fall)
	var visual := get_parent() as Node3D
	visual.rotation.x = -PI*.5*fallen
	visual.position.y = .22*fallen
	var holding := armed and alive
	var rifle := holding and not sidearm
	var pistol := holding and sidearm
	var look := clampf(pitch, -1.3, 1.3)
	raise = move_toward(raise, 1.0 if aim and holding else 0.0, dt*6.0)
	var k := smoothstep(0, 1, raise)
	var weld := k if rifle else 0.0  # cheek on the stock
	var hips := rig.find_bone("Hips")
	rig.set_bone_pose_position(hips, rig.get_bone_rest(hips).origin + Vector3(0,-.025-.53*crouch,.11*crouch))
	# Rifle stance blades the chest so the support shoulder leads; the gun stays on the aim line.
	var blade := -.3 if rifle else 0.0
	var tilt := Basis(Vector3.BACK, -lean*.34)
	# Weight forward over the toes when holding, more on aim.
	var press := (.05+.05*k) if holding else 0.0
	_rotate("Chest", tilt * Basis(Vector3.RIGHT, look*.6-.22*crouch-press+.009*sin(breath)*(1.0-fallen)) * Basis(Vector3.UP, blade))
	var chest := _offset("Chest")
	# Aiming a long gun drops the chin forward onto the stock and cants the head toward it.
	_rotate("Neck", chest.basis * Basis(Vector3.RIGHT, -.22*weld))
	_rotate("Head", Basis(Vector3.BACK, -lean*.35-.2*weld) * Basis(Vector3.RIGHT, look*.9-.12*weld))
	var head := _offset("Head")
	# Clavicles reach forward with the hands and lift slightly on aim.
	var reach := lerpf(.22, .32 if pistol else .25, k) if holding else .04
	for s: int in [-1,1]:
		var lift := (.04+.08*k if holding else .04) * (1.0 if s == 1 or not rifle else .5)
		_rotate(("Right" if s == 1 else "Left")+"Shoulder", chest.basis * Basis(Vector3.UP, s*reach) * Basis(Vector3.BACK, s*lift))
	var loading := sin(reload_time*4.0)*.5+.5 if reload else 0.0
	var gun := Transform3D(tilt * Basis(Vector3.RIGHT, look), chest * Vector3(.09, 1.42, -.31))
	if holding:
		# Aimed: the sight sits on the right eye's line, a weapon-specific eye relief ahead of it.
		var eye := head * EYE
		var line := tilt * Basis(Vector3.RIGHT, look)
		var relief := clampf(butt - sight.y - .1, .07, .16) if rifle else .5
		var aimed := Transform3D(line, eye + line * Vector3(0, -.006 - sight.x, -relief - sight.y))
		var ready: Transform3D
		if rifle:
			# Low ready: butt stays in the shoulder pocket, muzzle dropped and slightly inboard.
			var low := tilt * Basis(Vector3.UP, .08) * Basis(Vector3.RIGHT, maxf(look-.36, -1.15))
			ready = Transform3D(low, chest * POCKET - low * Vector3(0, .047, butt))
		else:
			# Compressed ready: both hands at the sternum, muzzle level to slightly down.
			ready = Transform3D(tilt * Basis(Vector3.RIGHT, maxf(look*.5-.22, -1.0)), chest * Vector3(.035, 1.3, -.32))
		gun = ready.interpolate_with(aimed, k)
	gun = gun * Transform3D(Basis(Vector3.RIGHT, .09*kick-.32*loading), Vector3(0,0,.025*kick))
	socket.transform = gun
	_attach("EquippedGun", gun)
	_attach("EquippedVest",chest)
	_attach("EquippedHelmet",head)
	_attach("EquippedNVG",head * Transform3D(Basis.IDENTITY,Vector3(0,1.69,-.13)))
	var dir := Vector3(velocity.x,0,velocity.z).normalized()
	for s: int in [-1,1]:
		var prefix := "Right" if s==1 else "Left"
		var stride := sin(phase)*s*minf(speed*.065,.26)
		# Long guns stand with the support foot forward and a slightly wider base.
		var stagger := .075 if rifle else .025
		var foot := Vector3(s*(.13 if rifle else .115),.115 + maxf(0,cos(phase)*s)*minf(speed*.026,.09),s*stagger) + dir*stride
		_limb(prefix+"UpLeg",prefix+"Leg",prefix+"Foot",foot,Vector3.FORWARD)
		_rotate(prefix+"Foot",Basis.IDENTITY)
		var wrist: Vector3
		var along: Vector3
		var palm: Vector3
		var pole: Vector3
		var curl := Vector3(.3, .35, .15)  # knuckles, finger tips, thumb
		if not holding:
			wrist = chest*Vector3(s*.235,.885,-.03+stride*.45)
			along = Vector3(s*.06,-1,-.12)
			palm = Vector3(-s,0,.1)
			pole = Vector3(s*.3,0,1)
		elif s == 1:
			# Trigger hand: wrist behind and below the grip, palm against its right side, thumb over.
			wrist = gun*(Vector3(.018,-.08,.08) if pistol else Vector3(.022,-.075,.075))
			along = gun.basis*Vector3(0,.45,-1)
			palm = gun.basis*Vector3.LEFT
			pole = chest.basis*(Vector3(.4,-1,.2) if pistol else Vector3(1,-.7,.3))
			curl = Vector3(.95,1.05,.9)
		elif pistol:
			# Support hand wraps the trigger hand from the left, thumbs forward.
			wrist = gun*Vector3(-.032,-.085,.07)
			along = gun.basis*Vector3(.3,.3,-1)
			palm = gun.basis*Vector3.RIGHT
			pole = chest.basis*Vector3(-.4,-1,.2)
			curl = Vector3(.8,.9,.2)
		else:
			# Support hand under the handguard, palm up, fingers wrapping the right side.
			wrist = gun*Vector3(-.036,-.028,-support+.05)
			along = gun.basis*Vector3(.35,.15,-1)
			palm = gun.basis*Vector3(.45,1,0)
			pole = chest.basis*Vector3(-.35,-1,0)
			curl = Vector3(1.25,1.15,.5)
		if reload and holding and s == -1:
			wrist = wrist.lerp(gun*Vector3(-.05,-.2,.0), loading)
		var grip := _hand_frame(s, along, palm)
		_limb(prefix+"Arm",prefix+"ForeArm",prefix+"Hand",wrist,pole,grip)
		_rotate(prefix+"Hand",grip)
		_bend(prefix+"Fingers",prefix+"Hand",Vector3(0,0,-s),curl.x)
		_bend(prefix+"FingerTips",prefix+"Fingers",Vector3(0,0,-s),curl.y)
		_bend(prefix+"Thumb",prefix+"Hand",Vector3.LEFT,curl.z)
