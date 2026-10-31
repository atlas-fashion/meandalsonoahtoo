extends "res://scripts/enforcer_react.gd"

## The sword skeleton's layer over its clips (sword_skeleton.gd, note 135):
## enforcer_react.gd's inertialized `crossfade` and its hit reactions, on this
## rig's longer chain. There the torso is one bone with the head and shoulders on
## it; here a rock of the torso is shared down the spine, the head is turned on
## its neck, and the feet are still held where the clip put them (two-bone IK).
##
## Also the head: it turns to `look_target`, over the clip, eased on and off.

## Bone, parent, the reaction's channel, this bone's share of it. Parents first.
const CHAIN := [
	[&"pelvis", &"", "torso", 0.14],
	[&"spine.01", &"pelvis", "torso", 0.28],
	[&"spine.02", &"spine.01", "torso", 0.29],
	[&"chest", &"spine.02", "torso", 0.29],
	[&"neck", &"chest", "head", 0.4],
	[&"head", &"neck", "head", 0.6],
	[&"clavicle.L", &"chest", "sh_l", 1.0],
	[&"upper_arm.L", &"clavicle.L", "arm_l", 1.0],
	[&"clavicle.R", &"chest", "sh_r", 1.0],
	[&"upper_arm.R", &"clavicle.R", "arm_r", 1.0],
]
const THIGHS := [[&"thigh.L", &"shin.L", &"foot.L"], [&"thigh.R", &"shin.R", &"foot.R"]]
## How far the head turns, and how fast it comes on.
const LOOK_MAX := 1.15
const LOOK_EASE := 3.5

var look_target = null
var look_strength := 1.0
## Whose clips these are, to read where the new clip's bones have just been.
var player: AnimationPlayer = null
## Animation -> {bone id: [rotation track, position track]}.
static var _maps := {}

var _ids := {}
var _look_w := 0.0
var _look_last := Vector3.ZERO
var _look_frame := -1
var _head_face := Vector3.BACK


func _init() -> void:
	super()
	free_velocity = true


func _find_bones(sk: Skeleton3D) -> void:
	_ready_bones = true
	for c in CHAIN:
		_ids[c[0]] = sk.find_bone(c[0])
	for leg in THIGHS:
		for b in leg:
			_ids[b] = sk.find_bone(b)
	_bone[TORSO] = _ids[&"pelvis"]
	var h := sk.get_bone_global_rest(_ids[&"thigh.L"]).origin
	var k := sk.get_bone_global_rest(_ids[&"shin.L"]).origin
	var f := sk.get_bone_global_rest(_ids[&"foot.L"]).origin
	_leg = h.distance_to(k) + k.distance_to(f)
	_head_face = sk.get_bone_global_rest(_ids[&"head"]).basis.inverse() * Vector3.BACK


func _track_of(a: Animation, bone_id: int) -> Array:
	if not _maps.has(a):
		var map := {}
		var sk := get_skeleton()
		for k in a.get_track_count():
			var b := sk.find_bone(String(a.track_get_path(k)).get_slice(":", 1))
			if b < 0:
				continue
			if not map.has(b):
				map[b] = [-1, -1]
			if a.track_get_type(k) == Animation.TYPE_ROTATION_3D:
				map[b][0] = k
			elif a.track_get_type(k) == Animation.TYPE_POSITION_3D:
				map[b][1] = k
		_maps[a] = map
	return _maps[a].get(bone_id, [-1, -1])


## Clip time one history step before now, wrapped on a loop; < 0: there is none.
func _time_before(a: Animation) -> float:
	var t := player.current_animation_position - player.speed_scale * _from_dt
	if t < 0.0:
		t = t + a.length if a.loop_mode != Animation.LOOP_NONE else 0.0
	return t


func _rot_before(bone_id: int, now: Quaternion) -> Quaternion:
	if player == null or not player.is_playing():
		return now
	var a := player.get_animation(player.current_animation)
	var k: int = _track_of(a, bone_id)[0]
	return now if k < 0 else a.rotation_track_interpolate(k, _time_before(a))


func _pos_before(bone_id: int, now: Vector3) -> Vector3:
	if player == null or not player.is_playing():
		return now
	var a := player.get_animation(player.current_animation)
	var k: int = _track_of(a, bone_id)[1]
	return now if k < 0 else a.position_track_interpolate(k, _time_before(a))


func _process_modification_with_delta(delta: float) -> void:
	super(delta)
	var sk := get_skeleton()
	if sk != null and _ids.has(&"head"):
		_look(sk)


func _apply(sk: Skeleton3D, rot: Dictionary, hip: Vector3) -> void:
	var clip := {}
	for b in _ids:
		clip[b] = sk.get_bone_global_pose(_ids[b])
	var moved := {}
	var turned := {}
	for c in CHAIN:
		var b: StringName = c[0]
		var parent: StringName = c[1]
		var id: int = _ids[b]
		var d := _rotvec((rot[c[2]] as Vector3) * float(c[3]))
		var carried: Basis = d if parent == &"" else (turned[parent] as Basis) * d
		turned[b] = carried
		var g: Transform3D = clip[b]
		var want := carried * g.basis
		if parent == &"":
			var up := sk.get_bone_parent(id)
			var new_g := Transform3D(want, g.origin + hip)
			var local := new_g if up < 0 else sk.get_bone_global_pose(up).affine_inverse() * new_g
			sk.set_bone_pose_rotation(id, local.basis.get_rotation_quaternion())
			sk.set_bone_pose_position(id, local.origin)
			moved[b] = new_g
		else:
			var p: Transform3D = moved[parent]
			sk.set_bone_pose_rotation(id, (p.basis.inverse() * want).get_rotation_quaternion())
			moved[b] = Transform3D(want, p * sk.get_bone_pose_position(id))
	for leg in THIGHS:
		_solve_leg(sk, moved[&"pelvis"], clip[leg[0]], clip[leg[1]], (clip[leg[2]] as Transform3D).origin, _ids[leg[0]], _ids[leg[1]])


## Head and neck turned toward `look_target`, after everything else.
func _look(sk: Skeleton3D) -> void:
	var f := Engine.get_process_frames()
	if f != _look_frame:
		_look_frame = f
		var w: float = look_strength if look_target != null else 0.0
		_look_w = move_toward(_look_w, w, get_process_delta_time() * LOOK_EASE)
		if look_target != null:
			_look_last = look_target
	if _look_w <= 0.0:
		return
	var neck: int = _ids[&"neck"]
	var head: int = _ids[&"head"]
	var g_h := sk.get_bone_global_pose(head)
	var g_n := sk.get_bone_global_pose(neck)
	var to := (sk.global_transform.affine_inverse() * _look_last) - g_h.origin
	if to.length_squared() < 0.01:
		return
	var face := (g_h.basis * _head_face).normalized()
	var aim := to.normalized()
	var ang := face.angle_to(aim)
	if ang < 0.001:
		return
	var axis := face.cross(aim)
	if axis.length_squared() < 1e-6:
		return
	axis = axis.normalized()
	# Fading past the limit, rather than stopping at it.
	var w := _look_w * (1.0 - smoothstep(LOOK_MAX, LOOK_MAX + 0.7, ang))
	ang = minf(ang, LOOK_MAX) * w
	var new_n := Basis(axis, ang * 0.4) * g_n.basis
	var new_h := Basis(axis, ang) * g_h.basis
	var up := sk.get_bone_parent(neck)
	if up >= 0:
		var pb := sk.get_bone_global_pose(up).basis
		sk.set_bone_pose_rotation(neck, (pb.inverse() * new_n).get_rotation_quaternion())
	sk.set_bone_pose_rotation(head, (new_n.inverse() * new_h).get_rotation_quaternion())
