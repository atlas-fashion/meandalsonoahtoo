class_name PlayerMotion
extends RefCounted

## The player's attack motion (notes 167, 168).
##
## Every attack and the parry are motion-captured clips from Higgsfield's 3D
## Rigging (Meshy's action library), on the same 24-bone Meshy skeleton the
## knight has (note 155). Only the bones' motion is used: tools/strip_anim_clip.py
## cuts each result down to its skeleton and clip (models/anims/*.glb), and here
## it is put on the game's one knight, models/player_knight.glb.
##
## There is ONE body (note 168; the user: "the player shouldn't have two
## separate models for the camera and for third person, it should all be one
## model from different perspectives"). The clip poses it (coop_avatar.gd,
## `body_pose`), retargeted in knight space -- each bone takes the clip's turn
## from ITS rest to now, applied to the knight's rest, so neither rig's bone axes
## matter. The first-person view is that body's own eyes: the weapon is in the
## body's hand (first_person_arms.gd places it there, the grip below), and the
## camera rides the clip's head (`head_offset`, `head_turn`).
##
## Each MOVE plays a stretch of a clip on the game's clock through a time warp
## (`knots`: pose seconds -> clip seconds, a monotone cubic through them,
## `_warp`): a slow gather, a hang at the top, the cut faster than the capture
## but not by much (1.3-1.7x; note 167's 2.5-3x read as frantic from the eyes),
## the follow-through bleeding off -- with no jump in speed anywhere. A move
## blends in from whatever pose came before (`in`) and out to rest (`out` ->
## `end`), so every move runs into every other. The bite windows, the wave's
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
	&"sword_guard": "res://models/anims/sword_guard.glb",        # Sword_Parry (147): the stance, a held high guard
}

## Each move: its clip; `knots` [pose s, clip s] (the warp); `in` the blend from
## the pose before (pose s); `out` and `end`, the blend home to rest; `ref`, the
## clip second of its stance (where the camera's ride is measured from);
## `right_only`, the left arm left to the walk or the guard (the sword's: the
## captures carried a shield on it).
const MOVES := {
	# The hold whenever the hands are free (note 171): Sword_Parry's high guard,
	# the weapon raised across the body, breathing on a loop -- in view from the
	# eyes. (Combat_Stance held it low at the hip, out of the view.) Everything
	# else is laid over it and blends back into it (coop_avatar.gd `_apply_motion`).
	&"stance": {"right_only": true, "clip": &"sword_guard", "loop": true, "in": 0.0, "out": 1e9, "end": 1e9,
		"ref": 0.0, "knots": [[0.0, 0.0], [1.0, 1.0]]},
	# The forehand: drawn back and up behind the right shoulder, a hang at the
	# top, cut from right to left, ending high on the left -- exactly where the
	# backhand starts.
	&"slash": {"right_only": true, "clip": &"sword_swipes", "in": 0.08, "out": 0.48, "end": 0.75, "ref": 0.0,
		"knots": [[0.0, 0.03], [0.12, 0.38], [0.21, 0.565], [0.24, 0.62], [0.40, 0.95], [0.50, 1.08], [0.75, 1.12]]},
	# The backhand: from the forehand's end, gathered a beat, cut back from left to
	# right, and blended home from its follow-through. (The capture's own recovery
	# after it turned the whole body sideways, which from the eyes was an arm
	# parked under the camera.)
	&"chop": {"right_only": true, "clip": &"sword_swipes", "in": 0.08, "out": 0.4, "end": 0.66, "ref": 0.0,
		"knots": [[0.0, 1.08], [0.11, 1.165], [0.14, 1.20], [0.31, 1.53], [0.42, 1.64], [0.66, 1.70]]},
	# The heavy: a long slow gathering sweep over to the left, held and creeping
	# at the end of it, then the explosive backhand back across.
	&"heavy": {"right_only": true, "clip": &"sword_heavy", "in": 0.1, "out": 1.05, "end": 1.45, "ref": 0.0,
		"knots": [[0.0, 0.06], [0.40, 0.62], [0.66, 1.04], [0.72, 1.10], [0.90, 1.36], [1.04, 1.50], [1.45, 1.98]]},
	# The ult (Sword Judgment), near the capture's own pace: a crouch, a leap with
	# the blade wheeled up and round, the airborne cut that throws the wave, a deep
	# landing held, rising through a flourish to a last sweep, and settled.
	&"wave": {"right_only": true, "clip": &"sword_ult", "in": 0.12, "out": 2.9, "end": 3.3, "ref": 0.0,
		"knots": [[0.0, 0.20], [0.27, 0.47], [0.55, 0.85], [0.65, 0.93], [0.78, 1.07], [0.92, 1.22],
			[1.15, 1.45], [1.75, 2.15], [2.35, 2.85], [2.85, 3.45], [3.3, 3.90]]},
	# The parry: a snap back off the blow and a recovery, on the upper body over
	# the guard.
	&"parry": {"right_only": true, "clip": &"sword_parry", "in": 0.05, "out": 0.55, "end": 0.75, "ref": 0.2,
		"knots": [[0.0, 0.22], [0.12, 0.42], [0.28, 0.6], [0.75, 1.28]]},
	# The spear's two short jabs (the capture's two right-hand jabs).
	&"jab_a": {"clip": &"spear_jabs", "in": 0.04, "out": 0.14, "end": 0.28, "ref": 0.28,
		"knots": [[0.0, 0.32], [0.05, 0.46], [0.09, 0.64], [0.18, 0.85], [0.28, 1.02]]},
	&"jab_b": {"clip": &"spear_jabs", "in": 0.04, "out": 0.14, "end": 0.28, "ref": 1.22,
		"knots": [[0.0, 1.26], [0.05, 1.42], [0.09, 1.62], [0.18, 1.84], [0.28, 2.05]]},
	# The third: drawn back, a beat, and driven through with a step in.
	&"lunge": {"clip": &"spear_lunge", "in": 0.05, "out": 0.42, "end": 0.6, "ref": 0.0,
		"knots": [[0.0, 0.10], [0.16, 0.50], [0.22, 0.60], [0.30, 0.84], [0.42, 0.98], [0.6, 1.05]]},
	# Q: the delayed sweep -- wound up high on the left and swept low through the
	# legs from left to right.
	&"sweep": {"clip": &"spear_sweep", "in": 0.08, "out": 0.86, "end": 1.2, "ref": 0.0,
		"knots": [[0.0, 0.08], [0.45, 0.70], [0.55, 0.78], [0.70, 1.12], [0.86, 1.30], [1.2, 1.85]]},
}

## Bake rate of each clip (Hz).
const BAKE_HZ := 60.0
## The sword in the fist (knight space, at the T-pose rest): out along the arm
## and up, half way between, its edge forward. Read off the capture's own prop
## sword in Higgsfield's previews of Left_Slash (note 167). The spear lies along
## the forearm.
const BLADE_REST := Vector3(-0.70710678, 0.70710678, 0.0)
const EDGE_REST := Vector3(0.0, 0.0, 1.0)
## The fist's grip, from the wrist (the hand bone) out toward the knuckles.
const GRIP_OUT := 0.085
## The knight's scale in game (coop_avatar.gd SCALE).
const BODY := 1.05


class Clip:
	var name: StringName
	var length := 0.0
	var frames := 0
	var bones: PackedStringArray = []
	## bone -> Array[Quaternion]: its turn from rest, knight space, per frame.
	var turn := {}
	## Per frame: the hips' and the head's offsets from their rest (knight space).
	var hips: Array[Vector3] = []
	var head: Array[Vector3] = []


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
	if MOVES[kind].get("loop", false):
		return fposmod(t, clip(MOVES[kind]["clip"]).length)
	return _warp(MOVES[kind]["knots"], t)


## How much of the move is showing at `t`, 0..1: in over `in`, out from `out` to
## `end`.
static func weight_in(kind: StringName, t: float) -> float:
	var m: Dictionary = MOVES[kind]
	return _smooth(clampf(t / maxf(float(m["in"]), 0.001), 0.0, 1.0))


static func weight_out(kind: StringName, t: float) -> float:
	var m: Dictionary = MOVES[kind]
	return 1.0 - _smooth(clampf((t - float(m["out"])) / maxf(float(m["end"]) - float(m["out"]), 0.001), 0.0, 1.0))


static func weight(kind: StringName, t: float) -> float:
	return weight_in(kind, t) * weight_out(kind, t)


static func _smooth(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


# --- The body -----------------------------------------------------------------------

## Every bone's turn from rest (knight space) and the hips' offset from the
## capture's rest (knight space, clip metres) for `kind` at pose second `t`: {bone: Quaternion}, "_hips":
## Vector3.
static func body_pose(kind: StringName, t: float) -> Dictionary:
	var c := clip(MOVES[kind]["clip"])
	var ct := clip_time(kind, t)
	var out := {}
	var f := _frame(c, ct)
	for b in c.bones:
		var arr: Array = c.turn[b]
		out[b] = (arr[f[0]] as Quaternion).slerp(arr[f[1]], f[2])
	# From the capture's own rest, not the move's stance: a crouched stance puts
	# the hips down, or the bent legs would push the feet through the floor.
	out["_hips"] = (c.hips[f[0]] as Vector3).lerp(c.hips[f[1]], f[2])
	return out


# --- The camera: the body's own eyes -------------------------------------------------

## Where the knight's head has gone since the move's stance (knight space,
## world metres): the view rides it.
static func head_offset(kind: StringName, t: float) -> Vector3:
	var c := clip(MOVES[kind]["clip"])
	var f := _frame(c, clip_time(kind, t))
	var ref := _frame(c, float(MOVES[kind]["ref"]))
	var now: Vector3 = c.head[f[0]].lerp(c.head[f[1]], f[2])
	return (now - c.head[ref[0]]) * BODY


## How the knight's head has turned since the move's stance (knight space).
static func head_turn(kind: StringName, t: float) -> Quaternion:
	var c := clip(MOVES[kind]["clip"])
	if not c.turn.has("Head"):
		return Quaternion.IDENTITY
	var arr: Array = c.turn["Head"]
	var f := _frame(c, clip_time(kind, t))
	var ref := _frame(c, float(MOVES[kind]["ref"]))
	var now := (arr[f[0]] as Quaternion).slerp(arr[f[1]], f[2])
	return now * (arr[ref[0]] as Quaternion).inverse()


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
	var rot_t := {}
	var pos_t := {}
	for i in anim.get_track_count():
		var bone := String(anim.track_get_path(i)).get_slice(":", 1)
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
	var hd := sk.find_bone("Head")
	var hips := sk.find_bone("Hips")
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
		c.head.append(glob[hd].origin - rest_g[hd].origin)
	scene.free()
	return c


## [frame, next frame, blend] for clip second `t`.
static func _frame(c: Clip, t: float) -> Array:
	var x := clampf(t, 0.0, c.length) * BAKE_HZ
	var a := clampi(int(floor(x)), 0, c.frames - 1)
	var b := mini(a + 1, c.frames - 1)
	return [a, b, x - a]


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
