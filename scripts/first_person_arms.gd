extends Node3D

## The knight's own arms in the first-person view (note 156): the molten rust
## gauntlets holding what is in hand. A child of the player's Head, made by
## player.gd `_ready`.
##
## Nothing is animated here. Every weapon already poses itself -- the sword on
## its clips, the spear's stab and dash, the axe's chop and throw, the flask
## raised to drink -- so each arm is solved onto it every frame: the fist is put
## on the thing's grip, turned to its haft, and the elbow and shoulder follow
## by two-bone IK. Swings, guards, parries, ducks, queued strokes and anything
## added later move the arms with no work here.
##
## - The mesh is models/player_knight_arms.glb (tools/build_player_knight_arms.py):
##   the knight cut down to its arms, the fingers bent into fists. It is
##   dressed in the body's own material (coop_avatar.gd's knight), drawn pulled
##   toward the camera like the sword (`use_z_clip_scale`), so it is never cut
##   by a wall, and casts no shadow (the body does that, note 155).
## - The LEFT arm is the guard (note 157; the torch it held is gone): right
##   click brings the forearm up across the view, plate to the front, a
##   blocked blow drives it back at the face, a parry bats the blow out wide.
##   Its elbow, wrist and plate run on springs (`_update_guard`). Down, it is
##   under the view and hidden.
## - One copy of the mesh per arm, the other arm of each folded to a point.
## - What the hand holds is not all at one scale (the flask is half size 21 cm
##   from the eye), so the arm is drawn at the size of what it holds
##   (`SCALE_FOR`), scaled about the eye: it looks a full-sized arm wherever it
##   is (`k`).
## - The shoulder sits behind and below the eye, a little under the rig's joint
##   (`SHOULDER_DROP`). Out of reach, it slides toward the grip -- the body
##   leaning in, never seen.
## - Held: the sword's hilt, the spear and the axe up their hafts (`SPEAR_UP`,
##   `AXE_UP`), the flask, a live rat's tail. Nothing in hand, or it put away
##   (it drops out of view as it goes), and the arm is hidden.

const ARMS := preload("res://models/player_knight_arms.glb")
const KNIGHT := preload("res://models/player_knight.glb")
## The body's scale (coop_avatar.gd SCALE).
const BODY_SCALE := 1.05
## The eye in the knight's glTF space (+Z forward, +X its left): at the visor,
## 1.6 m up at BODY_SCALE.
const EYE := Vector3(0.0, 1.524, 0.04)
## The middle of each closed fist, where a haft passes through it (glTF space,
## the left fist; the right mirrored). Printed by the arms build.
const GRIP := Vector3(0.918, 1.329, -0.0544)
## Where the elbow is pushed (head space, the right arm; mirrored for the left):
## down, out to the side and a little back.
const POLE := Vector3(0.55, -1.0, 0.35)
## An arm's scale for each kind of thing, against the knight's real size.
const SCALE_FOR := {&"sword": 1.0, &"spear": 1.0, &"axe": 1.0, &"potion": 0.5, &"rat": 1.0}
## How far up the haft the fist holds the spear and the axe (see `_right_target`).
const SPEAR_UP := 0.28
const AXE_UP := 0.12
## The shoulder moved from the rig's joint (head space, metres, the right arm).
const SHOULDER_DROP := Vector3(0.02, -0.09, 0.0)
## The molten cracks' glow: dimmer than the body's 2.2, since here they are
## a hand's breadth from the eye.
const GLOW := 1.2
const RIGHT := 0
const LEFT := 1

## The left arm's poses (head space, metres; the eye at the origin, -Z ahead):
## where the elbow and the wrist go, and which way the back of the gauntlet --
## the vambrace's outer plate -- faces. Down: out of the view under it.
const DOWN_ELBOW := Vector3(-0.30, -0.60, 0.04)
const DOWN_WRIST := Vector3(-0.20, -0.82, -0.10)
const DOWN_BACK := Vector3(-0.4, -0.2, -1.0)
## The guard: the elbow out and forward, the forearm across the lower half of
## the view rising to the fist right of centre, the plate square to the front;
## the shoulder brought forward and in behind it (`GUARD_SHOULDER`), as a body
## braces behind a forearm.
const GUARD_ELBOW := Vector3(-0.28, -0.30, -0.17)
const GUARD_WRIST := Vector3(0.04, -0.17, -0.27)
const GUARD_BACK := Vector3(0.0, 0.3, -1.0)
const GUARD_SHOULDER := Vector3(0.05, 0.02, -0.10)
## The parry's beat: the forearm swung up and out round the elbow, standing
## upright to the left of the view, the plate turned out -- the blow batted wide. Held for
## `PARRY_BEAT`, then `PARRY_HOLD` more before the arm may go down.
const PARRY_ELBOW := Vector3(-0.30, -0.30, -0.20)
const PARRY_WRIST := Vector3(-0.26, 0.0, -0.30)
const PARRY_BACK := Vector3(-1.0, 0.1, -0.5)
const PARRY_BEAT := 0.16
const PARRY_HOLD := 0.18
## Springs: (stiffness in rad/s, damping ratio). The elbow stiffer than the
## wrist, so it leads; under 1, so each overshoots a touch and settles.
const ELBOW_SPRING := Vector2(34.0, 0.62)
const WRIST_SPRING := Vector2(27.0, 0.55)
const BACK_SPRING := Vector2(24.0, 0.7)
const PARRY_SPRING := Vector2(48.0, 0.5)
## Going down the springs are this much softer: the arm drops, heavy.
const DROP_SPRING := 0.55
## How far a turn of the head leaves the raised arm behind (m per radian).
const LOOK_LAG := 0.12
## A blow's recoil: its own softer spring, on top of the pose, so the fist is
## driven back at the face and comes back over a third of a second. The kick
## each gives it (m/s: a block back and down at the face, a parry out wide).
const RECOIL_SPRING := Vector2(14.0, 0.5)
const BLOCK_KICK := Vector3(0.35, -0.7, 2.0)
const PARRY_KICK := Vector3(-1.3, 0.6, -1.2)
## A blow's shudder through the plate: metres at full, and how fast it dies.
const SHUDDER := 0.007
const SHUDDER_FADE := 9.0

var player: Node3D
var _material: Material
var _arms: Array[Arm] = []
## The left arm's springs (head space) and its clocks.
var _elbow := DOWN_ELBOW
var _elbow_v := Vector3.ZERO
var _wrist := DOWN_WRIST
var _wrist_v := Vector3.ZERO
var _back := DOWN_BACK
var _back_v := Vector3.ZERO
var _recoil := Vector3.ZERO
var _recoil_v := Vector3.ZERO
var _parry_t := -1.0
var _held_t := 0.0
var _shudder := 0.0
var _shudder_t := 0.0
var _last_yaw := 0.0
var _last_pitch := 0.0


class Arm:
	var side := RIGHT
	var root: Node3D
	var skel: Skeleton3D
	var k := 1.0
	var upper := -1
	var fore := -1
	var hand := -1
	var shoulder_parent := Transform3D.IDENTITY
	var rest_upper := Transform3D.IDENTITY
	var rest_fore := Transform3D.IDENTITY
	var rest_hand := Transform3D.IDENTITY
	var len_upper := 0.0
	var len_fore := 0.0
	## The fist's own frame at rest (skeleton space): columns forearm-to-fist,
	## back of the hand, along the haft toward its business end.
	var fist_rest := Basis.IDENTITY
	var grip := Vector3.ZERO
	var k2s := Basis.IDENTITY


func setup(p: Node3D) -> void:
	player = p
	name = "KnightArms"
	_material = _knight_material()
	_arms.append(_make_arm(RIGHT))
	_arms.append(_make_arm(LEFT))
	p.connect("guarded", _on_guarded)


func _ready() -> void:
	# After the player (and the head bob), the weapons and the AnimationPlayer
	# that swings the sword have all posed this frame.
	process_priority = 900


## The body's material, its emission as bright as the body's, drawn on top.
func _knight_material() -> Material:
	var k := KNIGHT.instantiate()
	var mat: Material = null
	for g in k.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
			break
	k.free()
	var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D if mat is StandardMaterial3D \
		else StandardMaterial3D.new()
	if m.emission_enabled:
		m.emission_energy_multiplier = GLOW
	m.use_z_clip_scale = true
	m.z_clip_scale = float(player.get("sword_draw_depth"))
	return m


func _make_arm(side: int) -> Arm:
	var a := Arm.new()
	a.side = side
	a.root = ARMS.instantiate()
	add_child(a.root)
	a.skel = a.root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for g in a.root.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Riding at the eye: never culled for being off to one side of a chunk.
		mi.extra_cull_margin = 2.0
	var pre := "Right" if side == RIGHT else "Left"
	a.upper = a.skel.find_bone(pre + "Arm")
	a.fore = a.skel.find_bone(pre + "ForeArm")
	a.hand = a.skel.find_bone(pre + "Hand")
	var sk := a.skel
	a.shoulder_parent = _rest_global(sk, sk.get_bone_parent(a.upper))
	a.rest_upper = _rest_global(sk, a.upper)
	a.rest_fore = _rest_global(sk, a.fore)
	a.rest_hand = _rest_global(sk, a.hand)
	a.len_upper = a.rest_upper.origin.distance_to(a.rest_fore.origin)
	a.len_fore = a.rest_fore.origin.distance_to(a.rest_hand.origin)
	# glTF scene space -> skeleton space.
	var s2k := _rel_transform(sk, a.root)
	var k2s := s2k.affine_inverse()
	a.k2s = k2s.basis
	var mirror := 1.0 if side == LEFT else -1.0
	a.grip = k2s * Vector3(GRIP.x * mirror, GRIP.y, GRIP.z)
	# At rest (the T-pose) the fist points out along the arm, the back of the
	# hand up, the haft running forward through it.
	var out := (k2s.basis * Vector3(mirror, 0.0, 0.0)).normalized()
	var up := (k2s.basis * Vector3.UP).normalized()
	var fwd := (k2s.basis * Vector3.BACK).normalized()
	a.fist_rest = Basis(out, up, fwd)
	# The other arm of this copy folded away to nothing at its shoulder.
	var other := sk.find_bone(("Left" if side == RIGHT else "Right") + "Arm")
	sk.set_bone_pose_scale(other, Vector3.ONE * 0.0001)
	a.root.visible = false
	return a


func _rest_global(sk: Skeleton3D, bone: int) -> Transform3D:
	var t := sk.get_bone_global_rest(bone)
	return Transform3D(t.basis.orthonormalized(), t.origin)


## `node`'s transform relative to `root`, from local transforms.
func _rel_transform(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_pose(_arms[RIGHT], _right_target())
	_update_guard(delta)


## What the right hand holds this frame: [kind, grip point, haft direction]
## (global), or [] for nothing in view.
func _right_target() -> Array:
	var held: StringName = player.call("held_item")
	var sword := player.get("sword_model") as Node3D
	if sword != null and sword.is_visible_in_tree():
		var base: Vector3 = player.get("_blade_base")
		var pommel: Vector3 = player.get("_blade_pommel")
		var tip: Vector3 = player.get("_blade_tip")
		var t := sword.global_transform
		# On the hilt, nearer the guard than the pommel.
		return [&"sword", t * base.lerp(pommel, 0.42), (t.basis * (tip - base)).normalized()]
	for kind: StringName in [&"spear", &"axe"]:
		var w := player.get(kind) as Node3D
		var m := w.get("_model") as Node3D if w != null else null
		if m != null and m.is_visible_in_tree():
			var t := m.global_transform
			# Up the haft from where the models put the hand (the spear's butt
			# bands, the axe's leather), which is under the bottom of the view:
			# the fist shows, reaching forward along it.
			if kind == &"spear":
				return [kind, t * Vector3(0.0, 0.0, -SPEAR_UP), -t.basis.z.normalized()]
			return [kind, t * Vector3(0.0, AXE_UP, 0.0), t.basis.y.normalized()]
	var potion := player.get("_held_potion") as Node3D
	var flask := potion.get("_model") as Node3D if potion != null else null
	if flask != null and flask.is_visible_in_tree():
		var t := flask.global_transform
		return [&"potion", t * Vector3(0.0, 0.07, 0.0), t.basis.y.normalized()]
	# A live rat hung by the tail: the fist pinches its tip (rat_control.gd).
	var rats := player.get("rats") as Node3D
	var rat := rats.get("_live") as Node3D if rats != null else null
	if rat != null and rat.is_visible_in_tree():
		return [&"rat", rat.call("tail_tip"), Vector3.UP]
	return []


## The arm's skeleton solved so the fist sits on `target`'s grip.
func _pose(a: Arm, target: Array) -> void:
	if target.is_empty():
		a.root.visible = false
		return
	var h2s := _place(a, SCALE_FOR.get(target[0], 1.0))
	var to_skel := a.skel.global_transform.affine_inverse()
	var p: Vector3 = to_skel * (target[1] as Vector3)
	var g: Vector3 = (to_skel.basis * (target[2] as Vector3)).normalized()
	var mirror := -1.0 if a.side == RIGHT else 1.0
	var shoulder := _shoulder(a, h2s)
	# The fist: its haft along g, the forearm coming at it from the shoulder.
	var h := (p - shoulder) - g * (p - shoulder).dot(g)
	if h.length_squared() < 1e-8:
		h = a.fist_rest.x
	h = h.normalized()
	var back := (g.cross(h) if a.side == LEFT else h.cross(g)).normalized()
	var turn := Basis(h, back, g) * a.fist_rest.inverse()
	var wrist := p - turn * (a.grip - a.rest_hand.origin)
	var pole := h2s.basis * Vector3(POLE.x * -mirror, POLE.y, POLE.z)
	_solve(a, shoulder, wrist, turn, back, pole)


## Shows `a`, drawn at `k` of the knight's size about the eye (the head's
## origin) and turned to face the view's -Z. Returns head space -> skeleton space.
func _place(a: Arm, k: float) -> Transform3D:
	a.root.visible = true
	a.k = k
	var b := Basis(Vector3.UP, PI).scaled(Vector3.ONE * BODY_SCALE * k)
	a.root.transform = Transform3D(b, -(b * EYE))
	return a.skel.global_transform.affine_inverse() * (get_parent() as Node3D).global_transform


## The shoulder joint, skeleton space. The rig's sits high, at the top of the
## pauldron; a real one is lower, and there the upper arm stays out of the
## bottom of the view. `extra` moves it on (head space, metres).
func _shoulder(a: Arm, h2s: Transform3D, extra := Vector3.ZERO) -> Vector3:
	var mirror := -1.0 if a.side == RIGHT else 1.0
	return a.rest_upper.origin + h2s.basis \
		* (Vector3(SHOULDER_DROP.x * -mirror, SHOULDER_DROP.y, SHOULDER_DROP.z) * a.k + extra)


## The bones from `shoulder` to `wrist` (skeleton space), the fist turned by
## `turn` from its rest, its back toward `back`, the elbow toward `pole`.
func _solve(a: Arm, shoulder: Vector3, wrist: Vector3, turn: Basis, back: Vector3,
		pole: Vector3) -> void:
	var hand_basis := turn * a.rest_hand.basis
	# Two bones from the shoulder to the wrist; out of reach, the shoulder
	# comes forward to it.
	var reach := (a.len_upper + a.len_fore) * 0.995
	var to_wrist := wrist - shoulder
	var d := to_wrist.length()
	if d > reach:
		shoulder = wrist - to_wrist / d * reach
		d = reach
	d = maxf(d, absf(a.len_upper - a.len_fore) + 0.001)
	var dir := (wrist - shoulder).normalized()
	var side_dir := pole - dir * pole.dot(dir)
	if side_dir.length_squared() < 1e-8:
		side_dir = a.fist_rest.y
	side_dir = side_dir.normalized()
	var cos_a := clampf((a.len_upper * a.len_upper + d * d - a.len_fore * a.len_fore)
		/ (2.0 * a.len_upper * d), -1.0, 1.0)
	var elbow := shoulder + (dir * cos_a + side_dir * sqrt(1.0 - cos_a * cos_a)) * a.len_upper
	# The upper arm by the shortest turn from rest; the forearm turned also
	# about its own length so its cuff meets the fist as it is turned.
	var upper_basis := Basis(_arc(a.rest_fore.origin - a.rest_upper.origin, elbow - shoulder)) \
		* a.rest_upper.basis
	var fore_rest_dir := (a.rest_hand.origin - a.rest_fore.origin).normalized()
	var fore_dir := (wrist - elbow).normalized()
	var fore_turn := _frame(fore_dir, back) * _frame(fore_rest_dir, a.fist_rest.y).inverse()
	var fore_basis := fore_turn * a.rest_fore.basis
	var sk := a.skel
	sk.set_bone_pose_position(a.upper, a.shoulder_parent.affine_inverse() * shoulder)
	sk.set_bone_pose_rotation(a.upper,
		(a.shoulder_parent.basis.inverse() * upper_basis).get_rotation_quaternion())
	sk.set_bone_pose_rotation(a.fore, (upper_basis.inverse() * fore_basis).get_rotation_quaternion())
	sk.set_bone_pose_rotation(a.hand, (fore_basis.inverse() * hand_basis).get_rotation_quaternion())


# --- The left arm: the guard (note 157) ----------------------------------------

## Physical, not keyed: the elbow, the wrist and the way the vambrace faces
## each run on a damped spring toward the pose of the moment, so the arm comes
## up with the elbow leading and a little overshoot, settles, breathes, lags a
## turn of the head, and takes a blow as a shove into the springs (the fist
## driven back at the face, the plate shuddering) instead of a canned clip.
func _update_guard(delta: float) -> void:
	var a := _arms[LEFT]
	var raised: bool = player.call("is_blocking")
	if _parry_t >= 0.0:
		_parry_t += delta
		if _parry_t > PARRY_BEAT + PARRY_HOLD:
			_parry_t = -1.0
	var up := raised or _parry_t >= 0.0
	var elbow_goal := GUARD_ELBOW if up else DOWN_ELBOW
	var wrist_goal := GUARD_WRIST if up else DOWN_WRIST
	var back_goal := GUARD_BACK if up else DOWN_BACK
	if _parry_t >= 0.0 and _parry_t < PARRY_BEAT:
		# The beat: the forearm swept out round the elbow, the plate turned
		# out, batting the blow wide; then back to the guard (or down).
		elbow_goal = PARRY_ELBOW
		wrist_goal = PARRY_WRIST
		back_goal = PARRY_BACK
	if up:
		# Held up: it breathes, and never quite stills.
		_held_t += delta
		var breath := sin(_held_t * 1.9)
		var tremble := Vector3(sin(_held_t * 11.3), sin(_held_t * 13.7 + 1.0), sin(_held_t * 9.1 + 2.0))
		wrist_goal += Vector3(0.0, 0.005 * breath, 0.003 * breath) + tremble * 0.0012
		elbow_goal += Vector3(0.0, 0.004 * breath, 0.0)
	else:
		_held_t = 0.0
	# A turn of the head: the arm, having weight, is left behind a little.
	var yaw: float = player.global_rotation.y
	var pitch: float = player.get("_look_pitch")
	var turn := Vector2(clampf(wrapf(yaw - _last_yaw, -PI, PI), -0.2, 0.2),
		clampf(pitch - _last_pitch, -0.2, 0.2))
	_last_yaw = yaw
	_last_pitch = pitch
	if up:
		var lag := Vector3(turn.x, -turn.y, 0.0) * LOOK_LAG
		_wrist += lag
		_elbow += lag * 0.6
	# Up quick and springy, the elbow ahead of the fist; down heavier.
	var w_up := PARRY_SPRING if _parry_t >= 0.0 and _parry_t < PARRY_BEAT else WRIST_SPRING
	var s := 1.0 if up else DROP_SPRING
	# Small steps: the springs are stiff, and a long frame must not blow them up.
	var steps := clampi(ceili(delta / 0.004), 1, 12)
	var dt := delta / float(steps)
	for i in steps:
		_elbow_v = _spring_v(_elbow, _elbow_v, elbow_goal, ELBOW_SPRING.x * s, ELBOW_SPRING.y, dt)
		_elbow += _elbow_v * dt
		_wrist_v = _spring_v(_wrist, _wrist_v, wrist_goal, w_up.x * s, w_up.y, dt)
		_wrist += _wrist_v * dt
		_back_v = _spring_v(_back, _back_v, back_goal, BACK_SPRING.x * s, BACK_SPRING.y, dt)
		_back += _back_v * dt
		_recoil_v = _spring_v(_recoil, _recoil_v, Vector3.ZERO, RECOIL_SPRING.x, RECOIL_SPRING.y, dt)
		_recoil += _recoil_v * dt
	_shudder *= exp(-SHUDDER_FADE * delta)
	_shudder_t += delta
	# Down and still: out of the view, nothing to draw.
	if not up and _wrist.distance_to(DOWN_WRIST) < 0.04 and _wrist_v.length() < 0.2 \
			and _recoil.length() < 0.01:
		a.root.visible = false
		return
	var wrist := _wrist + _recoil + Vector3(sin(_shudder_t * 73.0), sin(_shudder_t * 61.0 + 1.0),
		sin(_shudder_t * 89.0 + 2.0)) * SHUDDER * _shudder
	var h2s := _place(a, 1.0)
	# How far up the arm is, for the shoulder coming forward behind it.
	var raised_by := clampf(1.0 - _wrist.distance_to(GUARD_WRIST) / DOWN_WRIST.distance_to(GUARD_WRIST),
		0.0, 1.0)
	var shoulder := _shoulder(a, h2s, GUARD_SHOULDER * raised_by)
	var w := h2s * wrist
	var e := h2s * (_elbow + _recoil * 0.6)
	# The fist straight on from the forearm, its back (the gauntlet's plate)
	# toward `_back`; the haft line through it falls out of the two.
	var h := (w - e).normalized()
	var back := h2s.basis * _back
	back = (back - h * back.dot(h)).normalized()
	var g := h.cross(back).normalized()
	var turn_basis := Basis(h, back, g) * a.fist_rest.inverse()
	_solve(a, shoulder, w, turn_basis, back, e - shoulder)


## The spring's velocity after `dt`: stiffness `omega` (rad/s), damping ratio `zeta`.
func _spring_v(x: Vector3, v: Vector3, goal: Vector3, omega: float, zeta: float,
		dt: float) -> Vector3:
	return v + ((goal - x) * omega * omega - v * (2.0 * zeta * omega)) * dt


## A guarded blow: a block is a shove back into the face and a shudder through
## the plate; a parry starts the beat that bats it aside.
func _on_guarded(parried: bool, _attacker: Node3D) -> void:
	if parried:
		_parry_t = 0.0
		_recoil_v += PARRY_KICK
		_back_v += Vector3(-4.0, 0.0, 1.5)
		_shudder = maxf(_shudder, 0.6)
	else:
		_recoil_v += BLOCK_KICK
		_back_v += Vector3(0.0, 2.2, 1.0)
		_shudder = 1.0
	_shudder_t = 0.0


## A frame whose X runs along `along`, its Y as near `up` as that allows.
func _frame(along: Vector3, up: Vector3) -> Basis:
	var x := along.normalized()
	var y := up - x * up.dot(x)
	if y.length_squared() < 1e-8:
		y = x.cross(Vector3.FORWARD if absf(x.z) < 0.9 else Vector3.RIGHT)
	y = y.normalized()
	return Basis(x, y, x.cross(y))


func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var f := from.normalized()
	var t := to.normalized()
	var c := f.cross(t)
	var d := f.dot(t)
	if d < -0.9999:
		var axis := f.cross(Vector3.UP)
		if axis.length_squared() < 0.0001:
			axis = f.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()
