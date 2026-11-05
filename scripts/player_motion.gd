class_name PlayerMotion
extends RefCounted

## The player's attack motion (note 167; the user: "Have higgsfield make
## animations for all of the player's attacks and parry ... The player model
## should be doing the same animations as the first person player").
##
## Every attack is a motion-captured clip from Higgsfield's 3D Rigging (Meshy's
## action library), on the same 24-bone Meshy skeleton the knight has (note
## 155). Only the bones' motion is used: tools/strip_anim_clip.py cuts each
## result down to its skeleton and clip (models/anims/*.glb), and here it is put
## on the game's own knight, models/player_knight.glb.
##
## One clip drives both views, so they cannot disagree:
##   * the BODY (coop_avatar.gd) is posed bone by bone from it (`body_pose`),
##     retargeted in knight space: each bone takes the clip's turn from ITS rest
##     to now, applied to the knight's rest (`_delta`), so the two rigs' own bone
##     axes never matter;
##   * the FIRST-PERSON weapon (player.gd, spear.gd) is put where the clip's
##     right fist is relative to the eye (`fp_sword`, `fp_spear_delta`), and the
##     knight's first-person arm is IK'd onto it as before (first_person_arms.gd).
##
## Each MOVE plays a stretch of a clip against the game's own clock through a
## time warp (`MOVES[...]["knots"]`: pose seconds -> clip seconds, a monotone
## cubic through them, `_warp`), so the speed changes for weight and emphasis --
## a slow gather, a hang at the top, the cut many times the capture's speed, the
## follow-through bleeding off -- with no jump in speed anywhere. A move blends
## in from whatever pose came before (`in`) and out to rest (`out` -> `end`), so
## every move runs smoothly into every other. The bite windows, the wave's
## release and the like are in player.gd / spear.gd, in the same pose seconds.

## The clips: game name -> the stripped file, and the Higgsfield action it is.
const CLIPS := {
	&"sword_swipes": "res://models/anims/sword_swipes.glb",      # Left_Slash (97): forehand, then backhand
	&"sword_heavy": "res://models/anims/sword_heavy.glb",        # Charged_Slash (242)
	&"sword_ult": "res://models/anims/sword_ult.glb",            # Sword_Judgment (102)
	&"sword_parry": "res://models/anims/sword_parry.glb",        # Sword_Parry_Backward (148)
	&"spear_jabs": "res://models/anims/spear_jabs.glb",          # Punch_Combo_3 (203)
	&"spear_lunge": "res://models/anims/spear_lunge.glb",        # Thrust_Slash (240)
	&"spear_sweep": "res://models/anims/spear_sweep.glb",        # Axe_Spin_Attack (238)
}

## Each move: its clip; `knots` [pose s, clip s] (the warp); `in` the blend from
## the pose before (pose s); `out` and `end`, the blend home to rest; `ref`, the
## clip second its stance is read from (the spear's and the parry's motion is
## taken relative to it).
const MOVES := {
	# The forehand: drawn back and up behind the right shoulder, a hang at the
	# top, then cut from right to left at 2.5x the capture, ending high on the left
	# -- exactly where the backhand starts.
	&"slash": {"clip": &"sword_swipes", "in": 0.07, "out": 0.36, "end": 0.58, "ref": 0.0,
		"knots": [[0.0, 0.03], [0.09, 0.40], [0.16, 0.565], [0.18, 0.62], [0.29, 0.95], [0.36, 1.08], [0.58, 1.12]]},
	# The backhand: from the forehand's end, gathered a beat, then cut back from
	# left to right and carried round home by the clip's own recovery.
	&"chop": {"clip": &"sword_swipes", "in": 0.08, "out": 0.42, "end": 0.68, "ref": 0.0,
		"knots": [[0.0, 1.08], [0.13, 1.165], [0.15, 1.20], [0.26, 1.53], [0.34, 1.64], [0.68, 2.45]]},
	# The heavy: a long slow gathering sweep over to the left, held and creeping
	# at the end of it, then the explosive backhand back across.
	&"heavy": {"clip": &"sword_heavy", "in": 0.1, "out": 0.86, "end": 1.15, "ref": 0.0,
		"knots": [[0.0, 0.06], [0.30, 0.62], [0.56, 1.04], [0.62, 1.10], [0.75, 1.36], [0.86, 1.50], [1.15, 1.98]]},
	# The ult (Sword Judgment): a crouch, a leap with the blade wheeled up and
	# round, the airborne cut that throws the wave, a deep landing held, rising
	# through a flourish to a last sweep, and settled.
	&"wave": {"clip": &"sword_ult", "in": 0.12, "out": 2.0, "end": 2.35, "ref": 0.0,
		"knots": [[0.0, 0.20], [0.22, 0.47], [0.48, 0.85], [0.58, 0.93], [0.66, 1.07], [0.74, 1.22],
			[0.95, 1.45], [1.35, 2.15], [1.70, 2.85], [1.95, 3.45], [2.35, 3.90]]},
	# The parry: a snap back off the blow and a recovery to guard. Relative to
	# the guard it is played over (`ref`), in both views.
	&"parry": {"relative": true, "clip": &"sword_parry", "in": 0.04, "out": 0.42, "end": 0.6, "ref": 0.2,
		"knots": [[0.0, 0.22], [0.09, 0.42], [0.22, 0.6], [0.6, 1.28]]},
	# The spear's two short jabs (the capture's two right-hand jabs), each out and
	# back in a quarter second.
	&"jab_a": {"relative": true, "clip": &"spear_jabs", "in": 0.04, "out": 0.12, "end": 0.24, "ref": 0.28,
		"knots": [[0.0, 0.32], [0.035, 0.46], [0.07, 0.64], [0.14, 0.82], [0.24, 1.02]]},
	&"jab_b": {"relative": true, "clip": &"spear_jabs", "in": 0.04, "out": 0.12, "end": 0.24, "ref": 1.22,
		"knots": [[0.0, 1.26], [0.035, 1.42], [0.07, 1.62], [0.14, 1.82], [0.24, 2.05]]},
	# The third: drawn back, a beat, and driven through with a step in.
	&"lunge": {"relative": true, "clip": &"spear_lunge", "in": 0.05, "out": 0.34, "end": 0.52, "ref": 0.0,
		"knots": [[0.0, 0.10], [0.12, 0.50], [0.17, 0.60], [0.23, 0.84], [0.34, 0.98], [0.52, 1.05]]},
	# Q: the delayed sweep -- wound up high on the left and swept low through the
	# legs from left to right.
	&"sweep": {"relative": true, "clip": &"spear_sweep", "in": 0.08, "out": 0.78, "end": 1.05, "ref": 0.0,
		"knots": [[0.0, 0.08], [0.38, 0.70], [0.48, 0.78], [0.62, 1.12], [0.78, 1.30], [1.05, 1.85]]},
}

## Bake rate of each clip (Hz): every bone's turn and the fist, sampled.
const BAKE_HZ := 60.0
## The eye in the knight's glTF space, as the first-person arm has it
## (first_person_arms.gd EYE: the visor, 1.6 m up at BODY). The clip's eye rides
## its head bone, this far from it at rest.
const EYE := Vector3(0.0, 1.524, 0.04)
## The first-person arm's shoulder is the rig's moved down (first_person_arms.gd
## SHOULDER_DROP, head space): the fist goes with it, so the reach is the clip's.
const SHOULDER_DROP := Vector3(0.02, -0.09, 0.0)
## The sword in the fist (knight space, at the T-pose rest): out along the arm
## and up, half way between, its edge forward. Read off the capture's own prop
## sword in Higgsfield's previews of Left_Slash: straight up through the wind-up
## (0.53 s), across the front pointing left at the cut (0.83), out to the left
## and up as it follows through (0.9); and the heavy's backhand ends pointing
## right, as its preview does. (Straight out of the thumb side, +Z, pointed it
## down the view through every cut.) The spear lies along the forearm.
const BLADE_REST := Vector3(-0.70710678, 0.70710678, 0.0)
const EDGE_REST := Vector3(0.0, 0.0, 1.0)
## The first-person arm, fist and shoulder together, this much lower (head
## space) through a move: at the capture's height a cut at the eyes filled the
## view with the arm.
const FP_LOWER := Vector3(0.0, -0.12, -0.03)
## The fist's grip, from the wrist (the hand bone) out toward the knuckles.
const GRIP_OUT := 0.085
## Knight space -> the camera's head space (+Z forward, +X the knight's left ->
## -Z forward, +X right): half a turn about up.
const K2H := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
## The knight's scale in game (coop_avatar.gd SCALE): the clip's metres to the
## world's.
const BODY := 1.05


class Clip:
	var name: StringName
	var length := 0.0
	var frames := 0
	var bones: PackedStringArray = []
	## bone -> Array[Quaternion]: its turn from rest, knight space, per frame.
	var turn := {}
	## Per frame: the hips' offset from their rest (knight space, metres).
	var hips: Array[Vector3] = []
	## Per frame: the right fist (wrist frame, knight space), relative to the eye.
	var hand: Array[Transform3D] = []
	## Per frame: the head bone's height over its rest (the view rides it).
	var head_y: Array[float] = []
	## Per frame: the right shoulder joint relative to the eye; and at rest.
	var shoulder: Array[Vector3] = []
	var shoulder_rest := Vector3.ZERO
	## The right fist's rest frame (knight space) and the forearm's direction.
	var hand_rest := Basis.IDENTITY
	var fore_rest := Vector3.LEFT


static var _clips := {}


static func clip(name: StringName) -> Clip:
	if _clips.has(name):
		return _clips[name]
	var c := _bake(name)
	_clips[name] = c
	return c


## Bakes every clip (player.gd `_ready`).
static func warm() -> void:
	for name in CLIPS:
		clip(name)


static func move(kind: StringName) -> Dictionary:
	return MOVES.get(kind, {})


static func has_move(kind: StringName) -> bool:
	return MOVES.has(kind)


## The move's length (pose s).
static func length(kind: StringName) -> float:
	return float(MOVES[kind]["end"]) if MOVES.has(kind) else 0.0


## Clip second for pose second `t` of `kind` -- the warp.
static func clip_time(kind: StringName, t: float) -> float:
	return _warp(MOVES[kind]["knots"], t)


## How much of the move is showing at `t`, 0..1: in over `in`, out from `out` to
## `end`. (The blend's two ends are the pose before and rest.)
static func weight_in(kind: StringName, t: float) -> float:
	var m: Dictionary = MOVES[kind]
	return _smooth(clampf(t / maxf(float(m["in"]), 0.001), 0.0, 1.0))


static func weight_out(kind: StringName, t: float) -> float:
	var m: Dictionary = MOVES[kind]
	return 1.0 - _smooth(clampf((t - float(m["out"])) / maxf(float(m["end"]) - float(m["out"]), 0.001), 0.0, 1.0))


static func _smooth(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


# --- The first-person weapon -------------------------------------------------------

## Head space: the fist's frame (`basis`, the clip's wrist turned into the view)
## and the grip point (`origin`), metres from the eye, for `kind` at pose second
## `t`.
static func fp_fist(kind: StringName, t: float) -> Transform3D:
	var c := clip(MOVES[kind]["clip"])
	var h := _sample_hand(c, clip_time(kind, t))
	var grip := h.origin + h.basis * (c.hand_rest.inverse() * (c.fore_rest * GRIP_OUT))
	return Transform3D(K2H * h.basis, K2H * grip * BODY + SHOULDER_DROP + FP_LOWER)


## How far the clip's right shoulder has moved from where the arm's rest has it
## (head space): the torso's twist and lean carry the first-person arm's
## shoulder with it, so the fist is always within the arm's reach
## (first_person_arms.gd `_shoulder`'s `extra`).
static func fp_shoulder_shift(kind: StringName, t: float) -> Vector3:
	var c := clip(MOVES[kind]["clip"])
	var f := _frame(c, clip_time(kind, t))
	var now: Vector3 = (c.shoulder[f[0]] as Vector3).lerp(c.shoulder[f[1]], f[2])
	return K2H * (now - c.shoulder_rest) * BODY + FP_LOWER


## The sword's pivot (head space) for `kind` at `t`, absolute: the blade along
## the fist as the capture held it. `grip` is the grip point in the pivot's
## frame, `frame` the blade's axes in it (player.gd `_blade_frame`: x its width,
## y hilt to tip).
static func fp_sword(kind: StringName, t: float, grip: Vector3, frame: Basis) -> Transform3D:
	var c := clip(MOVES[kind]["clip"])
	var fist := fp_fist(kind, t)
	# The blade's axes in the fist's frame, from the rest grip.
	var along := c.hand_rest.inverse() * BLADE_REST
	var edge := c.hand_rest.inverse() * EDGE_REST
	var k2h_fist := fist.basis
	var y := (k2h_fist * along).normalized()
	var x := k2h_fist * edge
	x = (x - y * x.dot(y)).normalized()
	var want := Basis(x, y, x.cross(y))
	var b := want * frame.inverse()
	return Transform3D(b, fist.origin - b * grip)


## The fist's change since the move's stance (`ref`), head space: [turn, offset].
## For the poses played relative to one the game holds (the parry over the
## guard, the spear's aimed jabs).
static func fp_delta(kind: StringName, t: float) -> Array:
	var ref := fp_fist_at(kind, float(MOVES[kind]["ref"]))
	var now := fp_fist(kind, t)
	return [now.basis * ref.basis.inverse(), now.origin - ref.origin]


static func fp_fist_at(kind: StringName, clip_s: float) -> Transform3D:
	var c := clip(MOVES[kind]["clip"])
	var h := _sample_hand(c, clip_s)
	var grip := h.origin + h.basis * (c.hand_rest.inverse() * (c.fore_rest * GRIP_OUT))
	return Transform3D(K2H * h.basis, K2H * grip * BODY + SHOULDER_DROP + FP_LOWER)


## The forearm's direction now (head space): where a spear held along it points.
static func fp_forearm(kind: StringName, t: float) -> Vector3:
	var c := clip(MOVES[kind]["clip"])
	var h := _sample_hand(c, clip_time(kind, t))
	return (K2H * (h.basis * (c.hand_rest.inverse() * c.fore_rest))).normalized()


## The view's rise and fall with the body (metres): the head bone over its height
## at the move's stance. The ult's leap and landing ride it.
static func head_rise(kind: StringName, t: float) -> float:
	var c := clip(MOVES[kind]["clip"])
	return (_sample_f(c.head_y, c, clip_time(kind, t)) - _sample_f(c.head_y, c, float(MOVES[kind]["ref"]))) * BODY


# --- The body -----------------------------------------------------------------------

## Every bone's turn from rest (knight space) and the hips' offset (knight space,
## clip metres) for `kind` at pose second `t`: {bone: Quaternion}, "_hips":
## Vector3.
static func body_pose(kind: StringName, t: float) -> Dictionary:
	var c := clip(MOVES[kind]["clip"])
	var ct := clip_time(kind, t)
	var out := {}
	var f := _frame(c, ct)
	for b in c.bones:
		var arr: Array = c.turn[b]
		out[b] = (arr[f[0]] as Quaternion).slerp(arr[f[1]], f[2])
	var ref := _frame(c, float(MOVES[kind]["ref"]))
	var hp: Vector3 = c.hips[f[0]].lerp(c.hips[f[1]], f[2])
	out["_hips"] = hp - c.hips[ref[0]]
	return out


# --- Baking -------------------------------------------------------------------------

static func _bake(name: StringName) -> Clip:
	var c := Clip.new()
	c.name = name
	var scene := (load(CLIPS[name]) as PackedScene).instantiate() as Node3D
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var ap := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var anim := ap.get_animation(ap.get_animation_list()[0])
	c.length = anim.length
	c.frames = int(ceil(anim.length * BAKE_HZ)) + 1
	var to_k := Transform3D.IDENTITY
	var n: Node = sk
	while n != null and n != scene:
		if n is Node3D:
			to_k = (n as Node3D).transform * to_k
		n = n.get_parent()
	var count := sk.get_bone_count()
	# Each bone's tracks.
	var rot_t := {}
	var pos_t := {}
	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		var bone := path.get_slice(":", 1)
		if bone == "":
			continue
		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				rot_t[bone] = i
			Animation.TYPE_POSITION_3D:
				pos_t[bone] = i
	# Parents before children.
	var order: Array[int] = []
	var stack: Array[int] = []
	for r in sk.get_parentless_bones():
		stack.append(r)
	while not stack.is_empty():
		var b: int = stack.pop_front()
		order.append(b)
		for ch in sk.get_bone_children(b):
			stack.append(ch)
	var rest_g: Array[Transform3D] = []
	rest_g.resize(count)
	for i in count:
		rest_g[i] = to_k * sk.get_bone_global_rest(i)
		c.bones.append(sk.get_bone_name(i))
		c.turn[sk.get_bone_name(i)] = []
	var rh := sk.find_bone("RightHand")
	var rf := sk.find_bone("RightForeArm")
	var ra := sk.find_bone("RightArm")
	var hd := sk.find_bone("Head")
	var hips := sk.find_bone("Hips")
	var eye_off := EYE - rest_g[hd].origin
	c.shoulder_rest = rest_g[ra].origin - EYE
	c.hand_rest = rest_g[rh].basis.orthonormalized()
	c.fore_rest = (rest_g[rh].origin - rest_g[rf].origin).normalized()
	var glob: Array[Transform3D] = []
	glob.resize(count)
	for f in c.frames:
		var t := minf(f / BAKE_HZ, anim.length)
		for i in order:
			var bn := sk.get_bone_name(i)
			var rest := sk.get_bone_rest(i)
			var q := rest.basis.get_rotation_quaternion()
			var p := rest.origin
			if rot_t.has(bn):
				q = anim.rotation_track_interpolate(rot_t[bn], t)
			if pos_t.has(bn):
				p = anim.position_track_interpolate(pos_t[bn], t)
			var local := Transform3D(Basis(q).scaled(rest.basis.get_scale()), p)
			var par := sk.get_bone_parent(i)
			glob[i] = (to_k * local) if par < 0 else glob[par] * local
		for i in count:
			var turn := (glob[i].basis.orthonormalized() * rest_g[i].basis.orthonormalized().inverse()).get_rotation_quaternion()
			(c.turn[sk.get_bone_name(i)] as Array).append(turn)
		c.hips.append(glob[hips].origin - rest_g[hips].origin)
		var eye := glob[hd].origin + eye_off
		c.hand.append(Transform3D(glob[rh].basis.orthonormalized(), glob[rh].origin - eye))
		c.shoulder.append(glob[ra].origin - eye)
		c.head_y.append(glob[hd].origin.y - rest_g[hd].origin.y)
	scene.free()
	return c


## [frame, next frame, blend] for clip second `t`.
static func _frame(c: Clip, t: float) -> Array:
	var x := clampf(t, 0.0, c.length) * BAKE_HZ
	var a := clampi(int(floor(x)), 0, c.frames - 1)
	var b := mini(a + 1, c.frames - 1)
	return [a, b, x - a]


static func _sample_hand(c: Clip, t: float) -> Transform3D:
	var f := _frame(c, t)
	return (c.hand[f[0]] as Transform3D).interpolate_with(c.hand[f[1]], f[2])


static func _sample_f(arr: Array[float], c: Clip, t: float) -> float:
	var f := _frame(c, t)
	return lerpf(arr[f[0]], arr[f[1]], f[2])


## A monotone cubic (Fritsch-Carlson) through `knots` [[x, y], ...]: the clip's
## time never runs backwards and its speed never jumps. Held at the ends.
static func _warp(knots: Array, x: float) -> float:
	var n := knots.size()
	if x <= float(knots[0][0]):
		return float(knots[0][1])
	if x >= float(knots[n - 1][0]):
		return float(knots[n - 1][1])
	var i := 0
	while i < n - 2 and x > float(knots[i + 1][0]):
		i += 1
	var x0 := float(knots[i][0])
	var x1 := float(knots[i + 1][0])
	var y0 := float(knots[i][1])
	var y1 := float(knots[i + 1][1])
	var h := x1 - x0
	var m0 := _slope(knots, i)
	var m1 := _slope(knots, i + 1)
	var s := (x - x0) / h
	var s2 := s * s
	var s3 := s2 * s
	return (2.0 * s3 - 3.0 * s2 + 1.0) * y0 + (s3 - 2.0 * s2 + s) * h * m0 \
		+ (-2.0 * s3 + 3.0 * s2) * y1 + (s3 - s2) * h * m1


static func _secant(knots: Array, i: int) -> float:
	return (float(knots[i + 1][1]) - float(knots[i][1])) / maxf(float(knots[i + 1][0]) - float(knots[i][0]), 1e-6)


static func _slope(knots: Array, i: int) -> float:
	var n := knots.size()
	if i == 0:
		return _secant(knots, 0)
	if i == n - 1:
		return _secant(knots, n - 2)
	var a := _secant(knots, i - 1)
	var b := _secant(knots, i)
	if a * b <= 0.0:
		return 0.0
	# Fritsch-Carlson: the harmonic mean keeps it monotone.
	return 2.0 * a * b / (a + b)
