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
## captures carried a shield on it); `spin`, a whole turn of the body that the
## view turns with all the way (note 172); `turn`, a scale on how much of the
## body's turn the view keeps otherwise (player.gd `view_follow`).
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
	&"wave": {"right_only": true, "spin": true, "clip": &"sword_ult", "in": 0.12, "out": 2.9, "end": 3.3, "ref": 0.0,
		"knots": [[0.0, 0.20], [0.27, 0.47], [0.55, 0.85], [0.65, 0.93], [0.78, 1.07], [0.92, 1.22],
			[1.15, 1.45], [1.75, 2.15], [2.35, 2.85], [2.85, 3.45], [3.3, 3.90]]},
	# The parry: a snap back off the blow and a recovery, on the upper body over
	# the guard.
	&"parry": {"right_only": true, "clip": &"sword_parry", "in": 0.05, "out": 0.55, "end": 0.75, "ref": 0.2,
		"knots": [[0.0, 0.22], [0.12, 0.42], [0.28, 0.6], [0.75, 1.28]]},
	# The spear's two short jabs (the capture's two right-hand jabs; the arm is
	# the spear's own, driven point first down the aim, note 172).
	&"jab_a": {"turn": 0.4, "clip": &"spear_jabs", "in": 0.04, "out": 0.14, "end": 0.28, "ref": 0.28,
		"knots": [[0.0, 0.32], [0.05, 0.46], [0.09, 0.64], [0.18, 0.85], [0.28, 1.02]]},
	&"jab_b": {"turn": 0.4, "clip": &"spear_jabs", "in": 0.04, "out": 0.14, "end": 0.28, "ref": 1.22,
		"knots": [[0.0, 1.26], [0.05, 1.42], [0.09, 1.62], [0.18, 1.84], [0.28, 2.05]]},
	# The third: drawn back, a beat, and driven through with a step in.
	&"lunge": {"right_only": true, "clip": &"spear_lunge", "in": 0.05, "out": 0.42, "end": 0.6, "ref": 0.0,
		"knots": [[0.0, 0.10], [0.16, 0.50], [0.22, 0.60], [0.30, 0.84], [0.42, 0.98], [0.6, 1.05]]},
	# Q: the delayed sweep -- wound up high on the left and swept low through the
	# legs from left to right.
	&"sweep": {"spin": true, "clip": &"spear_sweep", "in": 0.08, "out": 0.86, "end": 1.2, "ref": 0.0,
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
	for kind in MOVES:
		if not MOVES[kind].get("loop", false):
			_ride(kind)


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


# --- The camera, made for the eyes (note 172) ------------------------------------------
#
# The captures were made to be watched from outside: a forehand turns the whole
# knight 95 degrees, the heavy 155, the sweep and the ult right round. From the
# eyes, with the view held to the aim, the body wheeled away under the camera
# and the blade swung out of sight behind it. So every move's head is split into
# its TURN about the vertical (`yaw`, unwound, so a spin reads -360 and not a
# jump at 180) and what is left (`nod`: pitch and roll), each sampled over the
# move's own clock and smoothed with a centred Gaussian (no lag) -- the capture
# is 30 fps, linearly joined, and its every frame was a kink in the view.
#
# The view turns with the body: all the way through a spin (`spin` moves), a
# share of it otherwise (player.gd `view_follow`); the BODY is turned back by
# the rest (`body_counter`, coop_avatar.gd), so the knight always faces where
# its eyes look and the weapon stays in front of them.

## Samples a second of each move's ride, and its smoothing (seconds, one sigma).
const RIDE_HZ := 120.0
const RIDE_SMOOTH := 0.03

## kind -> {"yaw": raw unwound turn, "yaw_s": smoothed, "nod": Vector2s (pitch,
## roll) smoothed, "off": head offsets smoothed (knight space, world metres)}.
static var _rides := {}


static func _ride(kind: StringName) -> Dictionary:
	if _rides.has(kind):
		return _rides[kind]
	var n := int(ceil(length(kind) * RIDE_HZ)) + 1
	var yaw := PackedFloat32Array()
	var nods: Array[Vector2] = []
	var offs: Array[Vector3] = []
	var last := 0.0
	var stance := _head_abs(&"stance", 0.0).inverse()
	for i in n:
		var t := i / RIDE_HZ
		var q := head_turn(kind, t)
		# The turn is measured from the STANCE's head, not the move's first frame:
		# the body blends in from the stance, and a move that starts already
		# turned (the sweep, 35 degrees) would otherwise leave the view that far
		# behind the head. Unwound against the last sample.
		var a := _twist(_head_abs(kind, t) * stance)
		a = last + wrapf(a - last, -PI, PI) if i > 0 else wrapf(a, -PI, PI)
		last = a
		yaw.append(a)
		var swing := Quaternion(Vector3.UP, -_twist(q)) * q
		var e := Basis(swing).get_euler(EULER_ORDER_YXZ)
		nods.append(Vector2(e.x, e.z))
		offs.append(head_offset(kind, t))
	var r := {"yaw": yaw, "yaw_s": _gauss_f(yaw), "nod": _gauss(nods), "off": _gauss(offs)}
	_rides[kind] = r
	return r


## The twist of `q` about the vertical (radians).
static func _twist(q: Quaternion) -> float:
	var tw := Quaternion(0.0, q.y, 0.0, q.w)
	if tw.length_squared() < 1e-10:
		return 0.0
	tw = tw.normalized()
	return 2.0 * atan2(tw.y, tw.w)


## The head's turn from rest (knight space) through `kind` at `t`.
static func _head_abs(kind: StringName, t: float) -> Quaternion:
	var c := clip(MOVES[kind]["clip"])
	if not c.turn.has("Head"):
		return Quaternion.IDENTITY
	var arr: Array = c.turn["Head"]
	var f := _frame(c, clip_time(kind, t))
	return (arr[f[0]] as Quaternion).slerp(arr[f[1]], f[2])


static func _kernel() -> PackedFloat32Array:
	var s := RIDE_SMOOTH * RIDE_HZ
	var half := int(ceil(s * 3.0))
	var k := PackedFloat32Array()
	var sum := 0.0
	for j in range(-half, half + 1):
		var v := exp(-0.5 * j * j / (s * s))
		k.append(v)
		sum += v
	for j in k.size():
		k[j] /= sum
	return k


## Centred Gaussian over samples, the ends held (so a move still starts and ends
## exactly where the capture does).
static func _gauss_f(a: PackedFloat32Array) -> PackedFloat32Array:
	var k := _kernel()
	var half := k.size() / 2
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		var v := 0.0
		for j in k.size():
			v += a[clampi(i + j - half, 0, a.size() - 1)] * k[j]
		out[i] = v
	return out


static func _gauss(a: Array) -> Array:
	var k := _kernel()
	var half := k.size() / 2
	var out := []
	for i in a.size():
		var v = a[0] * 0.0
		for j in k.size():
			v += a[clampi(i + j - half, 0, a.size() - 1)] * k[j]
		out.append(v)
	return out


static func _sample(arr, t: float):
	var x := clampf(t * RIDE_HZ, 0.0, float(arr.size() - 1))
	var a := int(floor(x))
	var b := mini(a + 1, arr.size() - 1)
	var f := x - a
	return arr[a] + (arr[b] - arr[a]) * f


## The head's turn about the vertical since the stance (radians, unwound).
static func ride_yaw(kind: StringName, t: float, smooth := true) -> float:
	return float(_sample(_ride(kind)["yaw_s" if smooth else "yaw"], t))


## The head's nod since the stance, its turn taken out: Vector2(pitch, roll).
static func ride_nod(kind: StringName, t: float) -> Vector2:
	return _sample(_ride(kind)["nod"], t)


## Where the head has gone since the stance (knight space, world metres),
## smoothed.
static func ride_offset(kind: StringName, t: float) -> Vector3:
	return _sample(_ride(kind)["off"], t)


## The turn the view takes at `t` (radians), `follow` of the head's -- weighted
## by the move, and eased out to the nearest whole turn, so a spin that ends
## past where it began goes on round rather than unwinding back.
static func view_yaw(kind: StringName, t: float, follow: float) -> float:
	var y := ride_yaw(kind, t) * follow
	var base := roundf(y / TAU) * TAU
	return base + (y - base) * weight(kind, t)


## The turn the body is given on top of the clip so its head faces where the
## view does (unweighted: coop_avatar.gd lays the clip on by its weight).
static func body_counter(kind: StringName, t: float, follow: float) -> float:
	return ride_yaw(kind, t) * follow - ride_yaw(kind, t, false)


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
