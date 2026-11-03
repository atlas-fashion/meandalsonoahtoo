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
## - The right arm only, the left of that copy folded away to a point. The left
##   hand holds the torch, which is held so low in the corner that only its
##   flame shows (hand_torch.gd): that fist and arm would be under the view.
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

var player: Node3D
var _material: Material
var _arms: Array[Arm] = []


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
	# The right arm only. The left holds the hand torch, which is held so low in
	# the corner that only its flame shows (hand_torch.gd): its fist would be
	# under the bottom of the view, and so would all of that arm.
	_arms.append(_make_arm(RIGHT))


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


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_pose(_arms[RIGHT], _right_target())


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
	a.root.visible = true
	a.k = SCALE_FOR.get(target[0], 1.0)
	# Scaled about the eye (the head's origin), turned to face the view's -Z.
	var b := Basis(Vector3.UP, PI).scaled(Vector3.ONE * BODY_SCALE * a.k)
	a.root.transform = Transform3D(b, -(b * EYE))
	var to_skel := a.skel.global_transform.affine_inverse()
	var p: Vector3 = to_skel * (target[1] as Vector3)
	var g: Vector3 = (to_skel.basis * (target[2] as Vector3)).normalized()
	var mirror := -1.0 if a.side == RIGHT else 1.0
	var head_basis := (get_parent() as Node3D).global_basis
	# The rig's shoulder joint sits high, at the top of the pauldron; a real
	# one is lower, and there the upper arm stays out of the bottom of the view.
	var shoulder := a.rest_upper.origin + to_skel.basis * head_basis \
		* (Vector3(SHOULDER_DROP.x * -mirror, SHOULDER_DROP.y, SHOULDER_DROP.z) * a.k)
	# The fist: its haft along g, the forearm coming at it from the shoulder.
	var h := (p - shoulder) - g * (p - shoulder).dot(g)
	if h.length_squared() < 1e-8:
		h = a.fist_rest.x
	h = h.normalized()
	var back := (g.cross(h) if a.side == LEFT else h.cross(g)).normalized()
	var turn := Basis(h, back, g) * a.fist_rest.inverse()
	var hand_basis := turn * a.rest_hand.basis
	var wrist := p - turn * (a.grip - a.rest_hand.origin)
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
	var pole := to_skel.basis * (get_parent() as Node3D).global_basis \
		* Vector3(POLE.x * -mirror, POLE.y, POLE.z)
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
