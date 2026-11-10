extends Node3D

## The knight's arms holding what is in hand (notes 156, 157, 168). A child of
## the player's Head, made by player.gd `_ready`.
##
## There is one knight (coop_avatar.gd, note 168): this solves ITS arms, the same
## arms the other player sees and the shadow casts, seen here from its own eyes.
## Nothing has a first-person model of its own any more.
##
## Every weapon still poses itself in the head's frame -- the sword on its clips
## and strokes, the spear's, the axe's chop and throw, the flask raised to drink
## -- and that pose is where the hand is to be. Each frame (after the body has
## been posed, its walk and any attack clip), the right arm is solved onto it:
## the fist put on the thing's grip, turned to its haft, the elbow and shoulder
## following by two-bone IK. Through an attack clip the weapon is carried by the
## clip's own fist (blended in and out with the move, `motion_w`) and the arm
## follows it with the clip's elbow, so the capture plays on the arm the eye sees.
## The weapon LEADS and the hand holds it (note 169): the fist is put exactly on
## its grip, turned with it, and the fingers (tools/build_player_knight.py gave
## the knight its finger and thumb bones) close round it (`_curl`).
##
## - The LEFT arm is the guard (note 157): right click brings the forearm up
##   across the view, plate to the front, a blocked blow drives it back at the
##   face, a parry bats the blow out wide. Its elbow, wrist and plate run on
##   springs (`_update_guard`). Down, the body's own walk has it.
## - The shoulder is the body's own joint, wherever the body has it: never moved,
##   so the arm never parts from the pauldron. Out of reach the fist stops short,
##   and the thing held comes with it.
## - Held: the sword's hilt, the spear and the axe up their hafts (`SPEAR_UP`,
##   `AXE_UP`), the flask, a live rat's tail.

## Where a handle sits in each hand (glTF space, the left hand; the right
## mirrored): in the palm, at the root of the fingers, just under the palm's
## plate and across the middle of the hand's depth (note 169; slices of the dark
## knight's gauntlet). The fingers close round it from there (`_grip_curl`).
const GRIP := Vector3(0.925, 1.306, -0.0736)
## Where the elbow is pushed (head space, the right arm; mirrored for the left):
## down, out to the side and a little back.
const POLE := Vector3(0.55, -1.0, 0.35)
## How far up the haft the fist holds the spear and the axe (see `_held`).
const SPEAR_UP := 0.28
const AXE_UP := 0.12
const RIGHT := 0
const LEFT := 1

## The left arm's poses (head space, metres; the eye at the origin, -Z ahead):
## where the elbow and the wrist go, and which way the back of the gauntlet --
## the vambrace's outer plate -- faces. Down: below the view.
const DOWN_ELBOW := Vector3(-0.30, -0.60, 0.04)
const DOWN_WRIST := Vector3(-0.20, -0.82, -0.10)
const DOWN_BACK := Vector3(-0.4, -0.2, -1.0)
## The guard (note 158): the forearm laid flat across the lower half of the
## view, square to it -- elbow and fist at one height and one depth, the elbow a
## hand's breadth left of centre, driven forward as into a door. The plate to
## the front, tipped up.
const GUARD_ELBOW := Vector3(-0.22, -0.14, -0.263)
const GUARD_WRIST := Vector3(0.094, -0.14, -0.248)
const GUARD_BACK := Vector3(0.0, 0.35, -1.0)
## The parry's beat: the forearm swung up and out round the elbow, standing
## upright to the left of the view, the plate turned out -- the blow batted wide.
## Held for `PARRY_BEAT`, then `PARRY_HOLD` more before the arm may go down.
const PARRY_ELBOW := Vector3(-0.30, -0.30, -0.20)
const PARRY_WRIST := Vector3(-0.26, 0.0, -0.30)
const PARRY_BACK := Vector3(-1.0, 0.1, -0.5)
const PARRY_BEAT := 0.16
const PARRY_HOLD := 0.18
## Springs: (stiffness in rad/s, damping ratio). The elbow stiffer than the
## wrist, so it leads. Near critical damping (note 158): the arm snaps up and
## locks -- a braced arm, not a wobbling one.
const ELBOW_SPRING := Vector2(44.0, 0.92)
const WRIST_SPRING := Vector2(36.0, 0.88)
const BACK_SPRING := Vector2(32.0, 0.95)
const PARRY_SPRING := Vector2(56.0, 0.8)
## Going down the springs are this much softer: the arm drops, heavy.
const DROP_SPRING := 0.55
## How far a turn of the head leaves the raised arm behind (m per radian).
const LOOK_LAG := 0.04
## Held up, how much it breathes (m at the wrist) -- no tremble.
const BREATH := 0.002
## A blow's recoil: its own spring, on top of the pose, and the kick each gives
## it (m/s: a block back and down at the face, a parry out wide).
const RECOIL_SPRING := Vector2(26.0, 0.85)
const BLOCK_KICK := Vector3(0.15, -0.3, 1.2)
const PARRY_KICK := Vector3(-1.0, 0.45, -1.0)
## A blow's shudder through the plate: metres at full, and how fast it dies.
const SHUDDER := 0.003
const SHUDDER_FADE := 14.0
## How long the guard arm takes to hand back to the body's walk once it is down.
const GUARD_RELEASE := 0.2

var player: Node3D
var _body: Node3D
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
## 0..1: how much the guard has the left arm (eased off as it comes down).
var _guard_w := 0.0


class Arm:
	var side := RIGHT
	var skel: Skeleton3D
	var upper := -1
	var fore := -1
	var hand := -1
	var parent := -1
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
	p.connect("guarded", _on_guarded)


func _ready() -> void:
	# After the player, the weapons, the AnimationPlayer that swings the sword
	# and the body (coop_avatar.gd) have all posed this frame.
	process_priority = 900


## The body's arms, once the body is there.
func _bind() -> bool:
	_body = player.get("_avatar") as Node3D
	if _body == null or _body.get("_skel") == null:
		return false
	_arms.append(_make_arm(RIGHT))
	_arms.append(_make_arm(LEFT))
	return true


func _make_arm(side: int) -> Arm:
	var a := Arm.new()
	a.side = side
	a.skel = _body.get("_skel") as Skeleton3D
	var root := _body.get("_knight") as Node3D
	var pre := "Right" if side == RIGHT else "Left"
	var sk := a.skel
	a.upper = sk.find_bone(pre + "Arm")
	a.fore = sk.find_bone(pre + "ForeArm")
	a.hand = sk.find_bone(pre + "Hand")
	a.parent = sk.get_bone_parent(a.upper)
	a.rest_upper = _rest_global(sk, a.upper)
	a.rest_fore = _rest_global(sk, a.fore)
	a.rest_hand = _rest_global(sk, a.hand)
	a.len_upper = a.rest_upper.origin.distance_to(a.rest_fore.origin)
	a.len_fore = a.rest_fore.origin.distance_to(a.rest_hand.origin)
	# glTF scene space -> skeleton space.
	var k2s := _rel_transform(sk, root).affine_inverse()
	a.k2s = k2s.basis
	var mirror := 1.0 if side == LEFT else -1.0
	a.grip = k2s * Vector3(GRIP.x * mirror, GRIP.y, GRIP.z)
	# At rest (the T-pose) the fist points out along the arm, the back of the
	# hand up, the haft running forward through it.
	var out := (k2s.basis * Vector3(mirror, 0.0, 0.0)).normalized()
	var up := (k2s.basis * Vector3.UP).normalized()
	var fwd := (k2s.basis * Vector3.BACK).normalized()
	a.fist_rest = Basis(out, up, fwd)
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
	if _arms.is_empty() and not _bind():
		return
	if not _body.visible or player.get("_dead") == true:
		return
	_pose_right(_held())
	_update_guard(delta)


## What the right hand holds this frame, or {} for nothing: `kind`; `node`, what
## it hangs from (moved with the hand when it must be); `frame`, its GRIP frame
## (global: the origin where the fist closes on it, Z along the haft toward its
## business end, X the way the knuckles go -- a sword's edge -- when `edged`);
## and the fingers close round it by its kind (`_grip_curl`).
func _held() -> Dictionary:
	var sword := player.get("sword_model") as Node3D
	if sword != null and sword.is_visible_in_tree():
		var base: Vector3 = player.get("_blade_base")
		var pommel: Vector3 = player.get("_blade_pommel")
		var tip: Vector3 = player.get("_blade_tip")
		var t := sword.global_transform
		var z := (t.basis * (tip - base)).normalized()
		var pivot := player.get("sword_pivot") as Node3D
		var edge: Vector3 = pivot.global_basis * (player.get("_blade_frame") as Basis).x
		# On the hilt, nearer the guard than the pommel.
		return {"kind": &"sword", "node": pivot, "edged": true,
			"frame": _frame_from(t * base.lerp(pommel, 0.42), z, edge)}
	for kind: StringName in [&"spear", &"axe"]:
		var w := player.get(kind) as Node3D
		var m := w.get("_model") as Node3D if w != null else null
		if m != null and m.is_visible_in_tree():
			var t := m.global_transform
			if kind == &"spear":
				return {"kind": kind, "node": w, "edged": false,
					"frame": _frame_from(t * Vector3(0.0, 0.0, -SPEAR_UP), -t.basis.z, t.basis.x)}
			return {"kind": kind, "node": w, "edged": false,
				"frame": _frame_from(t * Vector3(0.0, AXE_UP, 0.0), t.basis.y, t.basis.x)}
	var potion := player.get("_held_potion") as Node3D
	var flask := potion.get("_model") as Node3D if potion != null else null
	if flask != null and flask.is_visible_in_tree():
		var t := flask.global_transform
		return {"kind": &"potion", "node": potion, "edged": false,
			"frame": _frame_from(t * Vector3(0.0, 0.07, 0.0), t.basis.y, t.basis.x)}
	# A live rat hung by the tail: the fist pinches its tip (rat_control.gd).
	var rats := player.get("rats") as Node3D
	var rat := rats.get("_live") as Node3D if rats != null else null
	if rat != null and rat.is_visible_in_tree():
		return {"kind": &"rat", "node": null, "edged": false,
			"frame": _frame_from(rat.call("tail_tip"), Vector3.UP, Vector3.RIGHT)}
	return {}


## A right-handed frame: Z along `along`, X as near `across` as that allows.
static func _frame_from(at: Vector3, along: Vector3, across: Vector3) -> Transform3D:
	var z := along.normalized()
	var x := across - z * across.dot(z)
	if x.length_squared() < 1e-8:
		x = z.cross(Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	return Transform3D(Basis(x, z.cross(x), z), at)


## The right hand on what it holds (note 169). Outside an attack clip what is
## held LEADS: it is posed by its own moves, and the hand is put exactly in its
## grip, position and turn (the knuckles along a sword's edge), the arm reaching
## it by IK; out of reach, the weapon comes back with the hand rather than the
## two parting. Through a clip the arm is the capture's own, bone for bone
## (blended in and out with the move's weight), and the weapon is in THAT hand's
## grip (`_clip_frame`) -- the IK's own forearm twist against the capture's
## pinched the gauntlet. Either way the fist is exactly on the grip, and then the
## fingers close round it. Nothing held: the body's own arm and a loose hand.
func _pose_right(held: Dictionary) -> void:
	var a := _arms[RIGHT]
	if held.is_empty():
		_curl(a, CURL_LOOSE, 0.0)
		return
	var sk := a.skel
	var to_world := sk.global_transform
	var to_skel := to_world.affine_inverse()
	var shoulder := _shoulder(a)
	var node := held["node"] as Node3D
	var frame: Transform3D = held["frame"]
	# The fist's frame on the grip: the haft through it (g), the knuckles out
	# along the edge (h, the side nearer where the arm comes from), the back of
	# the hand from the two. A haft with no edge: the forearm comes at it from
	# the shoulder, squared to it.
	var p := to_skel * frame.origin
	var g := (to_skel.basis * frame.basis.z).normalized()
	var reach := (p - shoulder) - g * (p - shoulder).dot(g)
	if reach.length_squared() < 1e-8:
		reach = a.fist_rest.x
	var h := reach.normalized()
	if held["edged"]:
		var e := (to_skel.basis * frame.basis.x).normalized()
		e = (e - g * e.dot(g)).normalized()
		h = e if e.dot(h) >= 0.0 else -e
	var back := h.cross(g).normalized()
	var turn := Basis(h, back, g) * a.fist_rest.inverse()
	var wrist := p - turn * (a.grip - a.rest_hand.origin)
	var q := _solve(a, shoulder, wrist, turn, back, _h2s(a).basis * POLE)
	var w: float = _body.get("motion_w") if held["kind"] in [&"sword", &"spear", &"axe"] else 0.0
	# The spear's thrusts lead the hand (note 172, spear.gd `lead`): the arm is
	# put on the spear, point first down the aim, not the spear in a boxer's fist.
	if held["kind"] == &"spear" and node != null:
		w *= 1.0 - float(node.get("lead"))
	var bones := [a.upper, a.fore, a.hand]
	for k in 3:
		var rot: Quaternion = q[k]
		if w > 0.0:
			var clip = _body.call("clip_arm", bones[k])
			if clip != null:
				rot = rot.slerp(clip as Quaternion, w)
		sk.set_bone_pose_rotation(bones[k], rot)
	if node != null:
		var now: Transform3D = held["frame"]
		var held_at: Transform3D
		if w > 0.0:
			# In the hand as the clip (and the blend) left it.
			held_at = _clip_frame(a, held["kind"])
			if held["edged"] and held_at.basis.x.dot(now.basis.x) < 0.0:
				held_at.basis = Basis(-held_at.basis.x, -held_at.basis.y, held_at.basis.z)
		else:
			# Where it was posed, carried back with the wrist if the arm fell short.
			held_at = frame
			var short: Vector3 = to_world.basis * ((q[3] as Vector3) - wrist)
			# A spear slides through the fist (note 172): out of reach, the haft runs
			# on through the hand rather than the thrust coming back with the wrist.
			if held["kind"] == &"spear":
				var along := frame.basis.z.normalized()
				short -= along * short.dot(along)
			held_at.origin += short
		node.global_transform = held_at * now.affine_inverse() * node.global_transform
	_curl(a, _grip_curl(a, held["kind"]), 0.0)


## Where the capture's fist holds the weapon (global grip frame): through the
## fist as the clip has posed the hand -- its grip point, the haft along the
## fist's own grip line, the knuckles along a sword's edge -- read off the body's
## arm before the IK. The hand is then exactly the capture's, with no twist put
## into the wrist to point the blade anywhere else (that pinched the gauntlet
## mid-cut).
func _clip_frame(a: Arm, _kind: StringName) -> Transform3D:
	var sk := a.skel
	var to_world := sk.global_transform
	var hand := sk.get_bone_global_pose(a.hand)
	var at := to_world * (hand * (a.rest_hand.affine_inverse() * a.grip))
	var turn := hand.basis.orthonormalized() * a.rest_hand.basis.inverse()
	var fist := turn * a.fist_rest
	return _frame_from(at, to_world.basis * fist.z, to_world.basis * fist.x)


# --- The fingers (note 169) ---------------------------------------------------------

## The fingers close round what is held until they touch it (`_grip_curl`):
## its handle a cylinder of HANDLE_R about the grip, along the haft, and each
## finger HALF_FINGER thick about its bones' line. A thing with no handle (a
## rat's tail) is pinched; an empty hand hangs loose; the guard is a fist.
const HANDLE_R := {&"sword": 0.016, &"spear": 0.017, &"axe": 0.018, &"potion": 0.034, &"rat": 0.004}
const HALF_FINGER := 0.009
## How far each finger joint may close at most (radians: knuckle, middle, last).
const CLOSE_MAX := [1.5, 1.7, 1.4]
## The thumb's two joints, laid along the haft (it lies on the grip, a sword's
## the way a swordsman's does).
const THUMB_ON := [0.15, 0.2]
const CURL_FIST := [1.2, 1.4, 1.1, 0.4, 0.5]
const CURL_LOOSE := [0.2, 0.3, 0.2, 0.05, 0.05]
const FINGERS := ["HandFinger1", "HandFinger2", "HandFinger3", "HandThumb1", "HandThumb2"]
var _grip_cache := {}


## The finger joints' closing for `kind`, found once per hand: each joint in turn,
## knuckle first, closed as far as it goes (to CLOSE_MAX) before the finger beyond
## it would come within the handle (its radius and the finger's half-thickness of
## the haft's line). In the hand's own rest frame, where the handle is fixed.
func _grip_curl(a: Arm, kind: StringName) -> Array:
	var key := "%d|%s" % [a.side, kind]
	if _grip_cache.has(key):
		return _grip_cache[key]
	var sk := a.skel
	var pre := "Right" if a.side == RIGHT else "Left"
	var mirror := -1.0 if a.side == RIGHT else 1.0
	var unit := (a.k2s * Vector3.RIGHT).length()
	var reach: float = (float(HANDLE_R.get(kind, 0.016)) + HALF_FINGER) * unit
	var on := a.grip
	var along := a.fist_rest.z.normalized()
	var axis := (a.k2s * Vector3(0.0, 0.0, 1.0)).normalized()
	var pts: Array[Vector3] = []
	for k in 3:
		pts.append(sk.get_bone_global_rest(sk.find_bone(pre + String(FINGERS[k]))).origin)
	pts.append(pts[2] + (pts[2] - pts[1]).normalized() * 0.02 * unit)
	var out: Array = []
	for k in 3:
		var lo := 0.0
		var hi: float = CLOSE_MAX[k]
		if _clear(_turned(pts, k, hi * -mirror, axis), k, on, along, reach):
			lo = hi
		else:
			for it in 20:
				var mid := (lo + hi) * 0.5
				if _clear(_turned(pts, k, mid * -mirror, axis), k, on, along, reach):
					lo = mid
				else:
					hi = mid
		pts = _turned(pts, k, lo * -mirror, axis)
		out.append(lo)
	out.append_array(THUMB_ON)
	_grip_cache[key] = out
	return out


## `pts` with everything past joint `k` turned about it by `angle` round `axis`.
static func _turned(pts: Array[Vector3], k: int, angle: float, axis: Vector3) -> Array[Vector3]:
	var out := pts.duplicate()
	var r := Basis(axis, angle)
	for i in range(k + 1, pts.size()):
		out[i] = pts[k] + r * (pts[i] - pts[k])
	return out


## Whether the finger from joint `k` out keeps `reach` from the haft's line.
static func _clear(pts: Array[Vector3], k: int, on: Vector3, along: Vector3, reach: float) -> bool:
	for i in range(k, pts.size() - 1):
		for s in 5:
			var p: Vector3 = pts[i].lerp(pts[i + 1], (s + 1) / 5.0)
			var d := p - on
			if (d - along * d.dot(along)).length() < reach:
				return false
	return true


## Closes `a`'s fingers by `curl` (finger joints from the knuckle, then the
## thumb's two). The four fingers bend down toward the palm about the hand's
## front-to-back line (knight Z); the thumb in about the arm's own line (knight
## X). Each joint is a turn from its rest relative to its parent, so the chain
## wraps.
func _curl(a: Arm, curl: Array, _unused: float) -> void:
	var sk := a.skel
	var pre := "Right" if a.side == RIGHT else "Left"
	var mirror := -1.0 if a.side == RIGHT else 1.0
	for k in FINGERS.size():
		var i := sk.find_bone(pre + String(FINGERS[k]))
		if i < 0:
			continue
		var axis: Vector3
		var angle: float = curl[k]
		if k < 3:
			axis = a.k2s * Vector3(0.0, 0.0, 1.0)
			angle *= -mirror
		else:
			axis = a.k2s * Vector3(1.0, 0.0, 0.0)
			angle *= mirror
		var rg := sk.get_bone_global_rest(i).basis.orthonormalized()
		var e := Basis(axis.normalized(), angle)
		var local := sk.get_bone_rest(i).basis.orthonormalized() * (rg.inverse() * e * rg)
		sk.set_bone_pose_rotation(i, local.get_rotation_quaternion())


## Head space -> skeleton space.
func _h2s(a: Arm) -> Transform3D:
	return a.skel.global_transform.affine_inverse() * (get_parent() as Node3D).global_transform


## The shoulder joint as the body has it now (skeleton space).
func _shoulder(a: Arm) -> Vector3:
	return a.skel.get_bone_global_pose(a.parent) * a.skel.get_bone_rest(a.upper).origin


## The bones from `shoulder` to `wrist` (skeleton space), the fist turned by
## `turn` from its rest, its back toward `back`, the elbow toward `pole`: their
## local turns [upper, fore, hand], and the wrist reached. Out of reach, the
## wrist stops short.
func _solve(a: Arm, shoulder: Vector3, wrist: Vector3, turn: Basis, back: Vector3,
		pole: Vector3) -> Array:
	var hand_basis := turn * a.rest_hand.basis
	var reach := (a.len_upper + a.len_fore) * 0.995
	var to_wrist := wrist - shoulder
	var d := to_wrist.length()
	if d > reach:
		wrist = shoulder + to_wrist / d * reach
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
	var parent := a.skel.get_bone_global_pose(a.parent).basis.orthonormalized()
	return [(parent.inverse() * upper_basis).get_rotation_quaternion(),
		(upper_basis.inverse() * fore_basis).get_rotation_quaternion(),
		(fore_basis.inverse() * hand_basis).get_rotation_quaternion(), wrist]


# --- The left arm: the guard (note 157) ----------------------------------------

## Physical, not keyed: the elbow, the wrist and the way the vambrace faces
## each run on a damped spring toward the pose of the moment, so the arm comes
## up with the elbow leading, settles, breathes, lags a turn of the head, and
## takes a blow as a shove into the springs (the fist driven back at the face,
## the plate shuddering) instead of a canned clip. Down and still, the body's own
## walk has the arm again (`_guard_w`).
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
		elbow_goal = PARRY_ELBOW
		wrist_goal = PARRY_WRIST
		back_goal = PARRY_BACK
	if up:
		_held_t += delta
		var breath := sin(_held_t * 1.9)
		wrist_goal += Vector3(0.0, BREATH * breath, 0.6 * BREATH * breath)
		elbow_goal += Vector3(0.0, 0.8 * BREATH * breath, 0.0)
	else:
		_held_t = 0.0
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
	var w_up := PARRY_SPRING if _parry_t >= 0.0 and _parry_t < PARRY_BEAT else WRIST_SPRING
	var s := 1.0 if up else DROP_SPRING
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
	# Down and still: handed back to the body's own walk.
	var settled := not up and _wrist.distance_to(DOWN_WRIST) < 0.04 and _wrist_v.length() < 0.2 \
		and _recoil.length() < 0.01
	_guard_w = move_toward(_guard_w, 0.0 if settled else 1.0, delta / GUARD_RELEASE)
	var loose: Array = []
	for k in CURL_FIST.size():
		loose.append(lerpf(CURL_LOOSE[k], CURL_FIST[k], _guard_w))
	_curl(a, loose, 0.0)
	if _guard_w <= 0.0:
		return
	var wrist := _wrist + _recoil + Vector3(sin(_shudder_t * 73.0), sin(_shudder_t * 61.0 + 1.0),
		sin(_shudder_t * 89.0 + 2.0)) * SHUDDER * _shudder
	var h2s := _h2s(a)
	var shoulder := _shoulder(a)
	var wr := h2s * wrist
	var e := h2s * (_elbow + _recoil * 0.6)
	# The fist straight on from the forearm, its back (the gauntlet's plate)
	# toward `_back`; the haft line through it falls out of the two.
	var h := (wr - e).normalized()
	var back := h2s.basis * _back
	back = (back - h * back.dot(h)).normalized()
	var g := h.cross(back).normalized()
	var turn_basis := Basis(h, back, g) * a.fist_rest.inverse()
	var q := _solve(a, shoulder, wr, turn_basis, back, e - shoulder)
	var sk := a.skel
	for k in 3:
		var bone: int = [a.upper, a.fore, a.hand][k]
		sk.set_bone_pose_rotation(bone, sk.get_bone_pose_rotation(bone).slerp(q[k], _guard_w))


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
		_back_v += Vector3(-3.0, 0.0, 1.2)
		_shudder = maxf(_shudder, 0.6)
	else:
		_recoil_v += BLOCK_KICK
		_back_v += Vector3(0.0, 1.2, 0.6)
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
