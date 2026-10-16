extends SkeletonModifier3D

## The enforcer's hit reactions and its parry stagger (2026-10-15), as a layer
## ON TOP of whatever clip is playing -- walk, beam, recoil, swipe -- so a blow
## never cuts an animation off: the reaction eases in and out over it, and the
## clip underneath carries on. A SkeletonModifier3D runs after the
## AnimationPlayer has posed the rig each frame, and its changes are not kept,
## so nothing builds up.
##
## Each reaction is keyframed here in the skeleton's own space (+Y up, +Z the
## mech's front, +X its left), authored for a blow arriving from the FRONT,
## and turned at play time to face whoever struck it -- it always rocks AWAY
## from the blow. Keys are smoothly interpolated (cubic, zero slope at both
## ends), so every reaction starts and ends at exactly nothing.
##
## Channels: rotations in degrees as small rotation vectors (x pitch -- minus
## tips the top back; y yaw -- plus turns the front toward +X; z roll -- plus
## leans the top toward -X) for the torso (pivot at the hips), head, shoulders
## and arms; "hip", the torso's offset in leg lengths. The legs are not keyed:
## they are solved (two-bone IK) so the feet stay exactly where the clip puts
## them while the hips drop, twist and sway above.
##
## Three hits (`HITS`), picked at random and never the same twice running, half
## of them mirrored; and one long `STAGGER` for a parry, which also shakes with
## a fading servo judder. A hit landing during a stagger is not played over it.

const TORSO := &"TORSO"
const HEAD := &"HEAD"
const LEGS := [[&"THIGH_L", &"CALF_L", &"FOOT_L"], [&"THIGH_R", &"CALF_R", &"FOOT_R"]]

## Struck square in the chest: the hull rocks back and the hips sink and shove
## back, the head snaps back a beat later, both arms are flung back, then it
## rocks forward past upright and settles.
const HIT_CHEST := {
	"len": 0.62,
	"torso": [[0.0, Vector3.ZERO], [0.07, Vector3(-10, 0, 0)], [0.22, Vector3(3.5, 0, 0)], [0.38, Vector3(-1.2, 0, 0)], [0.62, Vector3.ZERO]],
	"hip": [[0.0, Vector3.ZERO], [0.08, Vector3(0, -0.035, -0.04)], [0.26, Vector3(0, -0.01, 0.006)], [0.62, Vector3.ZERO]],
	"head": [[0.0, Vector3.ZERO], [0.05, Vector3(-2, 0, 0)], [0.12, Vector3(-14, 0, 0)], [0.28, Vector3(6, 0, 0)], [0.45, Vector3(-1.5, 0, 0)], [0.62, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.09, Vector3(-4, 0, -6)], [0.3, Vector3(2, 0, 2)], [0.62, Vector3.ZERO]],
	"sh_r": [[0.0, Vector3.ZERO], [0.09, Vector3(-4, 0, 6)], [0.3, Vector3(2, 0, -2)], [0.62, Vector3.ZERO]],
	"arm_l": [[0.0, Vector3.ZERO], [0.06, Vector3(-3, 0, 0)], [0.14, Vector3(-16, 0, -5)], [0.32, Vector3(7, 0, 2)], [0.48, Vector3(-2, 0, 0)], [0.62, Vector3.ZERO]],
	"arm_r": [[0.0, Vector3.ZERO], [0.06, Vector3(-3, 0, 0)], [0.14, Vector3(-16, 0, 5)], [0.32, Vector3(7, 0, -2)], [0.48, Vector3(-2, 0, 0)], [0.62, Vector3.ZERO]],
}

## Clipped high on one side: the hull twists away and leans, the struck
## shoulder is driven back and its arm flung out, the head whips round further
## and later, and it unwinds through a small counter-twist.
const HIT_TWIST := {
	"len": 0.7,
	"torso": [[0.0, Vector3.ZERO], [0.08, Vector3(-4, -14, 6)], [0.26, Vector3(1.5, 4, -2)], [0.44, Vector3(-0.5, -1.5, 0.6)], [0.7, Vector3.ZERO]],
	"hip": [[0.0, Vector3.ZERO], [0.09, Vector3(0.02, -0.025, -0.02)], [0.3, Vector3(0, -0.006, 0)], [0.7, Vector3.ZERO]],
	"head": [[0.0, Vector3.ZERO], [0.06, Vector3(0, -3, 0)], [0.15, Vector3(-5, -18, 7)], [0.34, Vector3(2, 6, -2)], [0.52, Vector3(0, -1.5, 0)], [0.7, Vector3.ZERO]],
	"sh_r": [[0.0, Vector3.ZERO], [0.08, Vector3(-9, -6, 8)], [0.28, Vector3(3, 2, -2)], [0.7, Vector3.ZERO]],
	"arm_r": [[0.0, Vector3.ZERO], [0.07, Vector3(-4, 0, 6)], [0.16, Vector3(-12, -6, 18)], [0.36, Vector3(5, 2, -6)], [0.54, Vector3(-1.5, 0, 1.5)], [0.7, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.1, Vector3(3, -3, -3)], [0.32, Vector3(-1, 1, 1)], [0.7, Vector3.ZERO]],
	"arm_l": [[0.0, Vector3.ZERO], [0.12, Vector3(8, -4, -6)], [0.34, Vector3(-3, 1, 2)], [0.7, Vector3.ZERO]],
}

## Hammered from above: the knees give, the hull hunches forward and down and
## the head drops, the shoulders sag, then it pushes back up, rising a touch
## past rest before it settles.
const HIT_CRUSH := {
	"len": 0.74,
	"torso": [[0.0, Vector3.ZERO], [0.08, Vector3(7, 0, -3)], [0.3, Vector3(-2, 0, 1)], [0.5, Vector3(0.6, 0, 0)], [0.74, Vector3.ZERO]],
	"hip": [[0.0, Vector3.ZERO], [0.09, Vector3(0, -0.075, 0)], [0.22, Vector3(0, -0.06, 0)], [0.42, Vector3(0, 0.012, 0)], [0.58, Vector3(0, -0.004, 0)], [0.74, Vector3.ZERO]],
	"head": [[0.0, Vector3.ZERO], [0.06, Vector3(3, 0, 0)], [0.13, Vector3(12, 0, -3)], [0.34, Vector3(-4, 0, 1)], [0.52, Vector3(1, 0, 0)], [0.74, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.1, Vector3(4, 0, 9)], [0.34, Vector3(-1.5, 0, -3)], [0.74, Vector3.ZERO]],
	"sh_r": [[0.0, Vector3.ZERO], [0.1, Vector3(4, 0, -9)], [0.34, Vector3(-1.5, 0, 3)], [0.74, Vector3.ZERO]],
	"arm_l": [[0.0, Vector3.ZERO], [0.12, Vector3(9, 0, 5)], [0.36, Vector3(-4, 0, -2)], [0.74, Vector3.ZERO]],
	"arm_r": [[0.0, Vector3.ZERO], [0.12, Vector3(9, 0, -5)], [0.36, Vector3(-4, 0, 2)], [0.74, Vector3.ZERO]],
}

const HITS := [HIT_CHEST, HIT_TWIST, HIT_CRUSH]

## Parried: thrown right back on its heels, arms flung wide, the knees buckle
## and it staggers to one side and back, flailing, catches itself leaning
## forward, and only slowly straightens. `len` is how long the enforcer is
## stunned for (enforcer.gd PARRY_STAGGER).
const STAGGER := {
	"len": 2.1,
	"torso": [[0.0, Vector3.ZERO], [0.12, Vector3(-21, 0, 3)], [0.32, Vector3(-17, -6, 11)], [0.58, Vector3(-12, 5, -7)], [0.86, Vector3(-6, -3, 6)],
		[1.18, Vector3(7, 2, -2)], [1.5, Vector3(3, 0, 1)], [1.8, Vector3(-0.8, 0, 0)], [2.1, Vector3.ZERO]],
	"hip": [[0.0, Vector3.ZERO], [0.1, Vector3(0, -0.02, -0.12)], [0.34, Vector3(-0.04, -0.11, -0.1)], [0.62, Vector3(0.05, -0.09, -0.07)],
		[0.9, Vector3(-0.02, -0.07, -0.03)], [1.2, Vector3(0, -0.06, 0.03)], [1.55, Vector3(0, -0.02, 0.01)], [2.1, Vector3.ZERO]],
	"head": [[0.0, Vector3.ZERO], [0.07, Vector3(-6, 0, 0)], [0.17, Vector3(-27, 4, 0)], [0.42, Vector3(-14, -10, 9)], [0.7, Vector3(-6, 9, -8)],
		[1.0, Vector3(4, -4, 3)], [1.3, Vector3(10, 0, 0)], [1.65, Vector3(2, 0, 0)], [2.1, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.13, Vector3(-10, 0, -20)], [0.45, Vector3(-4, 4, -14)], [0.8, Vector3(3, 0, -6)], [1.2, Vector3(4, 0, 2)], [2.1, Vector3.ZERO]],
	"sh_r": [[0.0, Vector3.ZERO], [0.13, Vector3(-10, 0, 20)], [0.45, Vector3(-4, -4, 14)], [0.8, Vector3(3, 0, 6)], [1.2, Vector3(4, 0, -2)], [2.1, Vector3.ZERO]],
	"arm_l": [[0.0, Vector3.ZERO], [0.1, Vector3(-8, 0, -6)], [0.2, Vector3(-28, 0, -16)], [0.45, Vector3(-10, 6, -10)], [0.7, Vector3(16, -4, 2)],
		[0.98, Vector3(-9, 2, -4)], [1.28, Vector3(8, 0, 2)], [1.65, Vector3(-2, 0, 0)], [2.1, Vector3.ZERO]],
	"arm_r": [[0.0, Vector3.ZERO], [0.1, Vector3(-8, 0, 6)], [0.2, Vector3(-28, 0, 16)], [0.45, Vector3(-10, -6, 10)], [0.7, Vector3(16, 4, -2)],
		[0.98, Vector3(-9, -2, 4)], [1.28, Vector3(8, 0, -2)], [1.65, Vector3(-2, 0, 0)], [2.1, Vector3.ZERO]],
	# Servo judder: degrees of shake on head and arms, fading out.
	"judder": [[0.0, Vector3.ZERO], [0.1, Vector3(2.2, 0, 0)], [0.6, Vector3(1.0, 0, 0)], [1.1, Vector3(0.3, 0, 0)], [1.4, Vector3.ZERO]],
}

const CHANNELS := ["torso", "head", "sh_l", "sh_r", "arm_l", "arm_r"]
const MAX_ACTIVE := 3

var _bone := {}
var _ready_bones := false
## Leg length in skeleton units (hip offsets are given in these).
var _leg := 1.0
## Playing: [clip, time, yaw of the blow's side (rad, skeleton space), mirror (+-1), scale].
var _active: Array = []
var _last_hit := -1
var _noise := FastNoiseLite.new()
var _clock := 0.0
## Each bone's skeleton-space pose as the clip left it this frame.
var _clip_pose := {}


func _init() -> void:
	_noise.frequency = 1.0
	_noise.seed = randi()


## A blow from `from_world` (where the attacker stands): one of the three hits,
## not the last one played, half the time mirrored. Ignored during a stagger.
func hit(from_world: Vector3, strength := 1.0) -> void:
	if staggering():
		return
	var pick := randi_range(0, HITS.size() - 1)
	if pick == _last_hit:
		pick = (pick + randi_range(1, HITS.size() - 1)) % HITS.size()
	_last_hit = pick
	_start(HITS[pick], from_world, 1.0 if randf() < 0.5 else -1.0, clampf(strength, 0.4, 1.3))


## Parried: the long stagger, away from `from_world`. Clears the hits under it.
func stagger(from_world: Vector3) -> void:
	_active.clear()
	_start(STAGGER, from_world, 1.0 if randf() < 0.5 else -1.0, 1.0)


func staggering() -> bool:
	for a in _active:
		if a[0] == STAGGER:
			return true
	return false


func busy() -> bool:
	return not _active.is_empty()


func _start(clip: Dictionary, from_world: Vector3, mirror: float, scale: float) -> void:
	var sk := get_skeleton()
	var yaw := 0.0
	if sk != null and sk.is_inside_tree():
		var local := sk.global_transform.affine_inverse() * from_world
		var at := Vector3.ZERO
		if _bone.has(TORSO):
			at = sk.get_bone_global_pose(_bone[TORSO]).origin
		var d := Vector2(local.x - at.x, local.z - at.z)
		if d.length_squared() > 1e-6:
			# Turns the clip's front (+Z) toward the attacker.
			yaw = atan2(d.x, d.y)
	if _active.size() >= MAX_ACTIVE:
		_active.pop_front()
	_active.append([clip, 0.0, yaw, mirror, scale])
	active = true


func _find_bones(sk: Skeleton3D) -> void:
	_ready_bones = true
	for n in [TORSO, HEAD, &"SHOULDER_L", &"SHOULDER_R", &"ARM_L", &"ARM_R",
			&"THIGH_L", &"CALF_L", &"FOOT_L", &"THIGH_R", &"CALF_R", &"FOOT_R"]:
		var i := sk.find_bone(n)
		if i >= 0:
			_bone[n] = i
	if _bone.has(&"THIGH_L") and _bone.has(&"CALF_L") and _bone.has(&"FOOT_L"):
		var h := sk.get_bone_global_rest(_bone[&"THIGH_L"]).origin
		var k := sk.get_bone_global_rest(_bone[&"CALF_L"]).origin
		var f := sk.get_bone_global_rest(_bone[&"FOOT_L"]).origin
		_leg = h.distance_to(k) + k.distance_to(f)


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if not _ready_bones:
		_find_bones(sk)
	_blend_clips(sk, delta)
	if _active.is_empty() or not _bone.has(TORSO):
		return
	_clock += delta
	# Sum every playing reaction, each turned to its blow and mirrored.
	var rot := {}
	for c in CHANNELS:
		rot[c] = Vector3.ZERO
	var hip := Vector3.ZERO
	var judder := 0.0
	var still: Array = []
	for a in _active:
		var clip: Dictionary = a[0]
		a[1] += delta
		var t: float = a[1]
		if t >= clip["len"]:
			continue
		still.append(a)
		var turn := Basis(Vector3.UP, a[2])
		var m: float = a[3]
		var s: float = a[4]
		for c in CHANNELS:
			var key: String = c
			if m < 0.0:
				# Mirrored: left and right swap, yaw and roll reverse.
				key = c.replace("_l", "_X").replace("_r", "_l").replace("_X", "_r")
			if not clip.has(key):
				continue
			var v := _sample(clip[key], t)
			if m < 0.0:
				v = Vector3(v.x, -v.y, -v.z)
			rot[c] += turn * (v * (deg_to_rad(1.0) * s))
		if clip.has("hip"):
			var o := _sample(clip["hip"], t)
			if m < 0.0:
				o.x = -o.x
			hip += turn * (o * (_leg * s))
		if clip.has("judder"):
			judder += _sample(clip["judder"], t).x * s
	_active = still
	if judder > 0.0:
		var j := deg_to_rad(judder)
		var n := _clock * 23.0
		rot["head"] += Vector3(_noise.get_noise_2d(n, 1.0), _noise.get_noise_2d(n, 7.0), _noise.get_noise_2d(n, 13.0)) * j
		rot["arm_l"] += Vector3(_noise.get_noise_2d(n, 19.0), 0.0, _noise.get_noise_2d(n, 23.0)) * j * 1.4
		rot["arm_r"] += Vector3(_noise.get_noise_2d(n, 29.0), 0.0, _noise.get_noise_2d(n, 31.0)) * j * 1.4
	_apply(sk, rot, hip)


## Cubic through the keys, slopes from the neighbours, flat at both ends.
static func _sample(keys: Array, t: float) -> Vector3:
	var n := keys.size()
	if t <= keys[0][0]:
		return keys[0][1]
	if t >= keys[n - 1][0]:
		return keys[n - 1][1]
	var i := 0
	while i < n - 2 and t >= keys[i + 1][0]:
		i += 1
	var t0: float = keys[i][0]
	var t1: float = keys[i + 1][0]
	var p0: Vector3 = keys[i][1]
	var p1: Vector3 = keys[i + 1][1]
	var m0 := Vector3.ZERO
	var m1 := Vector3.ZERO
	if i > 0:
		m0 = (p1 - (keys[i - 1][1] as Vector3)) / (t1 - float(keys[i - 1][0]))
	if i + 2 < n:
		m1 = ((keys[i + 2][1] as Vector3) - p0) / (float(keys[i + 2][0]) - t0)
	var h := t1 - t0
	var u := (t - t0) / h
	var u2 := u * u
	var u3 := u2 * u
	return p0 * (2.0 * u3 - 3.0 * u2 + 1.0) + m0 * h * (u3 - 2.0 * u2 + u) \
		+ p1 * (-2.0 * u3 + 3.0 * u2) + m1 * h * (u3 - u2)


static func _rotvec(v: Vector3) -> Basis:
	var a := v.length()
	if a < 1e-6:
		return Basis.IDENTITY
	return Basis(v / a, a)


func _apply(sk: Skeleton3D, rot: Dictionary, hip: Vector3) -> void:
	# Every clip pose first: once the torso is moved, Godot may hand back its
	# children's skeleton-space poses already moved with it.
	_clip_pose.clear()
	for n in _bone:
		_clip_pose[_bone[n]] = sk.get_bone_global_pose(_bone[n])
	var ti: int = _bone[TORSO]
	var g_t: Transform3D = _clip_pose[ti]
	var r_t := _rotvec(rot["torso"])
	var g_t2 := Transform3D(r_t * g_t.basis, g_t.origin + hip)
	# The legs' clip pose, read before the torso moves them.
	var legs: Array = []
	for leg in LEGS:
		if _bone.has(leg[0]) and _bone.has(leg[1]) and _bone.has(leg[2]):
			legs.append([_clip_pose[_bone[leg[0]]], _clip_pose[_bone[leg[1]]],
				(_clip_pose[_bone[leg[2]]] as Transform3D).origin, _bone[leg[0]], _bone[leg[1]]])
	var torso_parent := sk.get_bone_parent(ti)
	var torso_local := g_t2 if torso_parent < 0 \
		else sk.get_bone_global_pose(torso_parent).affine_inverse() * g_t2
	sk.set_bone_pose_rotation(ti, torso_local.basis.get_rotation_quaternion())
	sk.set_bone_pose_position(ti, torso_local.origin)
	# Head and arms ride on the torso, each turned by its own channel too.
	if _bone.has(HEAD):
		_set_global_basis(sk, _bone[HEAD], g_t2, r_t * _rotvec(rot["head"]))
	for side in [["SHOULDER_L", "ARM_L", "sh_l", "arm_l"], ["SHOULDER_R", "ARM_R", "sh_r", "arm_r"]]:
		var sh := StringName(side[0])
		var arm := StringName(side[1])
		if not _bone.has(sh):
			continue
		var r_sh: Basis = r_t * _rotvec(rot[side[2]])
		var g_sh2 := _set_global_basis(sk, _bone[sh], g_t2, r_sh)
		if _bone.has(arm):
			_set_global_basis(sk, _bone[arm], g_sh2, r_sh * _rotvec(rot[side[3]]))
	# Legs: two-bone IK from the moved hips to the feet where the clip has them.
	for l in legs:
		_solve_leg(sk, g_t2, l[0], l[1], l[2], l[3], l[4])


## Sets bone `b`'s local rotation so that its skeleton-space basis is
## `delta * (its clip basis)`, under a parent now at `parent_new`. Returns its
## new skeleton-space transform.
func _set_global_basis(sk: Skeleton3D, b: int, parent_new: Transform3D, delta: Basis) -> Transform3D:
	var g: Transform3D = _clip_pose[b]
	var want := delta * g.basis
	var local_rot := (parent_new.basis.inverse() * want).get_rotation_quaternion()
	sk.set_bone_pose_rotation(b, local_rot)
	var pos := sk.get_bone_pose_position(b)
	return Transform3D(parent_new.basis * Basis(local_rot) * Basis.from_scale(sk.get_bone_pose_scale(b)),
		parent_new * pos)


func _solve_leg(sk: Skeleton3D, torso_new: Transform3D, g_thigh: Transform3D, g_calf: Transform3D,
		foot: Vector3, ti: int, ci: int) -> void:
	var hip0 := g_thigh.origin
	var knee0 := g_calf.origin
	var a := hip0.distance_to(knee0)
	var b := knee0.distance_to(foot)
	var hip := torso_new * sk.get_bone_pose_position(ti)
	var to := foot - hip
	var d := clampf(to.length(), absf(a - b) + 1e-3, a + b - 1e-3)
	var u := to.normalized()
	# Bend the way the knee already points.
	var w := (knee0 - hip0) - u * (knee0 - hip0).dot(u)
	if w.length_squared() < 1e-8:
		w = Vector3(0.0, 0.0, 1.0) - u * u.z
	w = w.normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var knee := hip + u * (a * cos_a) + w * (a * sqrt(1.0 - cos_a * cos_a))
	var thigh_basis := _swing(knee0 - hip0, knee - hip) * g_thigh.basis
	var calf_basis := _swing(foot - knee0, foot - knee) * g_calf.basis
	var thigh_local := (torso_new.basis.inverse() * thigh_basis).get_rotation_quaternion()
	sk.set_bone_pose_rotation(ti, thigh_local)
	var thigh_new := torso_new.basis * Basis(thigh_local) * Basis.from_scale(sk.get_bone_pose_scale(ti))
	sk.set_bone_pose_rotation(ci, (thigh_new.inverse() * calf_basis).get_rotation_quaternion())


## The shortest rotation taking direction `from` onto `to`.
static func _swing(from: Vector3, to: Vector3) -> Basis:
	var f := from.normalized()
	var t := to.normalized()
	var axis := f.cross(t)
	var s := axis.length()
	if s < 1e-7:
		return Basis.IDENTITY
	return Basis(axis / s, atan2(s, f.dot(t)))


## --- Cross-fading between clips ----------------------------------------------------
##
## The AnimationPlayer's own cross-fade could not be used here: it advances by
## delta x the player's `speed_scale`, so fading into a clip HELD at speed 0 (the
## stand after a swipe, the frozen aim) never progressed at all, and at speed 1
## it still lurched over its first two frames (measured on ARM_L: 0.29 and
## 0.38 then 0.1). enforcer.gd now switches clips outright and calls
## `crossfade`: the last pose shown is kept and eased into the new clip over
## `time`, on real time whatever speed the clip plays at. Runs every frame,
## under the reactions, so a reaction rides smoothly over a change of clip.

var _base_rot := {}
var _base_pos := {}
var _from_rot := {}
var _from_pos := {}
var _fade_t := 0.0
var _fade_len := 0.0
var _base_frame := -10


## Called BEFORE the new clip is put on the rig. While this layer is running,
## the pose last shown is `_base` (mid-fade it is the blend); while it is off
## (nothing to fade, nothing reacting) the rig shows its clip, which is what the
## skeleton holds right now.
func crossfade(time: float) -> void:
	var sk := get_skeleton()
	if sk == null or time <= 0.0:
		return
	# The pose stored last frame, if the layer ran then (a stale one, left from
	# whenever it last switched off, snapped the rig back to it).
	if not _base_rot.is_empty() and Engine.get_process_frames() - _base_frame <= 1:
		_from_rot = _base_rot.duplicate()
		_from_pos = _base_pos.duplicate()
	else:
		_from_rot.clear()
		_from_pos.clear()
		for i in sk.get_bone_count():
			_from_rot[i] = sk.get_bone_pose_rotation(i)
			_from_pos[i] = sk.get_bone_pose_position(i)
	_fade_t = 0.0
	_fade_len = time
	active = true


func _blend_clips(sk: Skeleton3D, delta: float) -> void:
	var n := sk.get_bone_count()
	if _fade_len > 0.0:
		_fade_t += delta
		var k := smoothstep(0.0, 1.0, _fade_t / _fade_len)
		for i in n:
			if not _from_rot.has(i):
				continue
			sk.set_bone_pose_rotation(i, (_from_rot[i] as Quaternion).slerp(sk.get_bone_pose_rotation(i), k))
			sk.set_bone_pose_position(i, (_from_pos[i] as Vector3).lerp(sk.get_bone_pose_position(i), k))
		if _fade_t >= _fade_len:
			_fade_len = 0.0
	for i in n:
		_base_rot[i] = sk.get_bone_pose_rotation(i)
		_base_pos[i] = sk.get_bone_pose_position(i)
	_base_frame = Engine.get_process_frames()
	# Nothing left to do: off, so a far-off or sleeping rig is not updated every
	# frame for nothing.
	if _fade_len <= 0.0 and _active.is_empty():
		set_deferred(&"active", false)
