extends Node3D

## The player's body: the knight in the user's fantasy armor (note 159;
## models/player_knight.glb, built by tools/build_player_knight.py from the
## user's Tripo armor on the Meshy knight's skeleton, note 155). The game is first person -- you see its arms (first_person_arms.gd)
## -- so the body is seen two ways:
##
## - ALONE: shadows only. The knight casts the player's shadow for the moon and
##   the wall torches, and is never drawn, so it can never clip the camera.
##   `Graphics.body_shadow` off takes it away altogether.
## - CO-OP (note 79): it is how the OTHER player sees you, drawn only by the
##   other half's camera (its own layer, split_screen.gd AVATAR), with what is
##   in hand -- the sword, the spear -- the left arm raised to guard (note 157),
##   and a name over the head. It casts a shadow while `body_shadow` is on.
##
## A child of the player, so it already turns with their yaw. Every bone is posed
## here from the player each frame, nothing baked: the legs stride with their
## pace, the arms swing, the head follows where they look, the sword arm winds
## up and cuts with their strokes, the left forearm comes up to guard, the whole knight
## lies down when they die and is gone while they hide.
##
## Every attack and the parry are the Higgsfield clips the first-person view
## plays (note 167, player_motion.gd): `_apply_motion` lays the clip's pose over
## the walking one, every bone, blended in and out with the move -- the legs
## left to the stride while they are walking -- so the body does exactly what the
## first-person sword and arm do.
##
## Posing: a target is a DIRECTION for a limb segment in the knight's own space
## (+Z forward, +X its left, +Y up), reached by the shortest turn from the
## segment's rest direction, relative to its parent's turn (`_aim`); trunk and
## head turns are rotations in the same space (`_turn`). Both go through
## `_set_bone`, which turns a rest-relative rotation in skeleton space into the
## bone's local pose, so the rig's own bone axes never matter.

const KNIGHT := preload("res://models/player_knight.glb")
## What it holds: the user's sword and spear (tools/build_weapons.py, note 163).
const SWORD := preload("res://models/sword.glb")
const SPEAR := preload("res://models/spear.glb")
## The sword's guard up its model, as tools/build_weapons.py prints it.
const SWORD_GUARD := 0.713
const SWORD_LENGTH := 1.0
const SPEAR_LENGTH := 2.2
const CLOTH := [Color(0.42, 0.12, 0.08), Color(0.13, 0.22, 0.38)]
const NAMES := ["PLAYER 1", "PLAYER 2"]
## The knight is 1.70 m to the top of the helmet (the armor built to it); at 1.05 its visor sits
## at the camera's 1.6 m and its crest at 1.79, inside the 1.8 m capsule.
const SCALE := 1.05
## How bright the molten cracks glow (the emission map the build cut out of the
## albedo). The game is dark: 1.0 was barely there under the torches.
const GLOW := 2.2
## The knight's layer when alone (split_screen.gd AVATAR[0]: nothing else uses
## it outside co-op). Every light's shadow_caster_mask includes it.
const SOLO_LAYER := 1 << 13

var player: Node3D
var _coop := false
var _layer := SOLO_LAYER
var _knight: Node3D
var _skel: Skeleton3D
var _meshes: Array[GeometryInstance3D] = []
var _props: Node3D
var _sword: Node3D
var _spear: Node3D
var _label: Label3D
var _phase := 0.0
var _lie := 0.0
var _stride := 0.0
## Knight space (the glTF scene root: +Z forward) -> skeleton space.
var _k2s := Basis.IDENTITY
## The same, with the skeleton's scale: for positions (the hips' offset).
var _k2s_pos := Basis.IDENTITY
## Bones parents first, and each one's parent (-1 for the root).
var _order: Array[int] = []
var _parent: Array[int] = []
## The knight's right fist at rest (knight space), for the blade's grip.
var _hand_rest_k := Basis.IDENTITY
var _fore_rest_k := Vector3.LEFT
## The pose the clip has the body in, 0..1 (the props follow the fist by it).
var _motion_w := 0.0
var _rest_global: Array[Basis] = []
var _rest_local: Array[Basis] = []
var _b := {}
## Each limb segment's rest direction (skeleton space), keyed by bone name.
var _rest_dir := {}
## Smoothed targets (knight space), so poses blend instead of snapping.
var _goal := {}


## `layer` is the visual layer the knight is drawn on; `coop` false is the lone
## player's shadow-only body.
func setup(p: Node3D, layer: int, coop := true) -> void:
	player = p
	name = "CoopAvatar" if coop else "Body"
	_knight = KNIGHT.instantiate()
	_knight.rotation.y = PI
	_knight.scale = Vector3.ONE * SCALE
	add_child(_knight)
	_skel = _knight.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for g in _knight.find_children("*", "GeometryInstance3D", true, false):
		_meshes.append(g as GeometryInstance3D)
		var mi := g as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s) as StandardMaterial3D
				if m != null and m.emission_enabled:
					m = m.duplicate() as StandardMaterial3D
					m.emission_energy_multiplier = GLOW
					mi.set_surface_override_material(s, m)
	_read_rig()
	_build_props(clampi(int(p.get("player_index")), 0, 1))
	set_mode(layer, coop)
	if not Graphics.changed.is_connected(_apply_graphics):
		Graphics.changed.connect(_apply_graphics)


## Alone (shadow only) or co-op (drawn for the other half) -- player.gd
## `set_view_layers` turns the lone body into the co-op one.
func set_mode(layer: int, coop: bool) -> void:
	_coop = coop
	_layer = layer
	name = "CoopAvatar" if coop else "Body"
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = layer
	_props.visible = coop
	_label.visible = coop
	_apply_graphics()


func _apply_graphics() -> void:
	var cast := Graphics.body_shadow
	for g in _meshes:
		if _coop:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_knight.visible = _coop or cast
	# Nothing to pose for a body nobody sees and nothing casts.
	set_process(_coop or cast)


func _read_rig() -> void:
	# The skeleton's frame relative to the knight's root (the glTF scene space).
	_k2s = _rel_transform(_skel, _knight).basis.orthonormalized().inverse()
	_k2s_pos = _rel_transform(_skel, _knight).basis.inverse()
	var stack: Array[int] = []
	for r in _skel.get_parentless_bones():
		stack.append(r)
	while not stack.is_empty():
		var b: int = stack.pop_front()
		_order.append(b)
		for ch in _skel.get_bone_children(b):
			stack.append(ch)
	for i in _skel.get_bone_count():
		_parent.append(_skel.get_bone_parent(i))
	for i in _skel.get_bone_count():
		_b[_skel.get_bone_name(i)] = i
		_rest_global.append(_skel.get_bone_global_rest(i).basis.orthonormalized())
		_rest_local.append(_skel.get_bone_rest(i).basis.orthonormalized())
	for pair in [["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"],
			["RightArm", "RightForeArm"], ["RightForeArm", "RightHand"],
			["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"],
			["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"]]:
		var a: Vector3 = _skel.get_bone_global_rest(_b[pair[0]]).origin
		var c: Vector3 = _skel.get_bone_global_rest(_b[pair[1]]).origin
		_rest_dir[pair[0]] = (c - a).normalized()
	var to_k := _rel_transform(_skel, _knight)
	var rh: int = _b["RightHand"]
	var rf: int = _b["RightForeArm"]
	_hand_rest_k = (to_k.basis * _skel.get_bone_global_rest(rh).basis).orthonormalized()
	_fore_rest_k = (to_k * _skel.get_bone_global_rest(rh).origin - to_k * _skel.get_bone_global_rest(rf).origin).normalized()


## `node`'s transform relative to `root`, from local transforms (before either
## is in the tree).
func _rel_transform(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# --- Pose ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var hidden: bool = player.call("is_hidden")
	visible = not hidden
	if hidden:
		return
	var dead: bool = player.get("_dead") == true
	var held: StringName = player.call("held_item")
	_lie = move_toward(_lie, 1.0 if dead else 0.0, delta * 2.5)
	# Dropped as they go down.
	_sword.visible = held == &"sword" and _lie < 0.3
	_spear.visible = held == &"spear" and _lie < 0.3
	_label.visible = _coop and not dead
	# Everything from rest each frame: the clip may have turned bones the walk
	# never touches (the neck, the shoulders), and they must not stay turned.
	_skel.reset_bone_poses()

	# Pace: stride, bob and swing with how fast they move on the ground.
	var v: Vector3 = player.get("velocity")
	var speed := Vector2(v.x, v.z).length()
	_stride = lerpf(_stride, clampf(speed / 4.25, 0.0, 1.2), 1.0 - exp(-8.0 * delta))
	_phase += delta * (1.0 + speed * 1.9)
	var s := _stride
	var sw := sin(_phase)
	var cw := cos(_phase)

	# Staggered back and aside by a blow, as their view is (player.gd `flinch_view`).
	var flinch: Vector3 = player.call("flinch_view")
	_knight.rotation = Vector3(-PI * 0.5 * _lie * _lie + deg_to_rad(flinch.y), PI,
		deg_to_rad(flinch.z))
	_knight.position.y = 0.2 * _lie + absf(cw) * 0.035 * s - 0.03 * s
	_knight.position.z = 0.0

	var k := 1.0 - exp(-14.0 * delta)
	# Legs: the thigh swings fore and aft, the knee folds as the leg comes through.
	for side: float in [1.0, -1.0]:
		var a := 0.42 * s * sw * side
		var knee := 0.7 * s * maxf(0.0, cw * side) + 0.06
		var x := 0.06 * side
		var key := "l" if side > 0.0 else "r"
		_goal_dir(key + "thigh", Vector3(x, -cos(a), sin(a)), k)
		_goal_dir(key + "shin", Vector3(x * 0.5, -cos(a - knee), sin(a - knee)), k)

	# The left arm swings against the stride; on guard it is the shield (note
	# 157): elbow out and forward, the forearm across the front of the face.
	var lb := 0.12 - 0.35 * s * sw
	if player.get("_blocking") == true:
		_goal_dir("lupper", Vector3(0.55, -0.35, 0.75), 1.0 - exp(-30.0 * delta))
		_goal_dir("lfore", Vector3(-0.85, 0.35, 0.4), 1.0 - exp(-30.0 * delta))
	else:
		_goal_dir("lupper", Vector3(0.18, -cos(lb), sin(lb)), k)
		_goal_dir("lfore", Vector3(0.08, -0.75, 0.65), k)

	# The sword arm: forward with the blade out; cutting through a stroke;
	# drawn back on guard (the left arm blocks); the spear held level.
	var rb := 0.12 + 0.35 * s * sw
	var upper := Vector3(-0.2, -cos(rb), sin(rb))
	var fore := Vector3(-0.08, -0.55, 0.85)
	var kind: StringName = player.get("_pose_kind")
	var t: float = player.get("_pose_time")
	var ka := k
	if player.get("_blocking") == true:
		upper = Vector3(-0.25, -0.9, 0.2)
		fore = Vector3(-0.05, -0.2, 0.95)
	elif kind in [&"slash", &"chop", &"heavy", &"wave", &"slam", &"raise", &"stab", &"haft"] and t >= 0.0:
		var c := clampf(t / 0.35, 0.0, 1.0)
		upper = Vector3(-0.35, 0.85, 0.3).lerp(Vector3(0.25, -0.55, 0.8), c)
		fore = Vector3(-0.25, 1.0, -0.15).lerp(Vector3(0.55, -0.55, 0.6), c)
		ka = 1.0 - exp(-30.0 * delta)
	elif held == &"spear":
		upper = Vector3(-0.15, -0.7, 0.6)
		fore = Vector3(0.0, -0.2, 1.0)
	_goal_dir("rupper", upper, ka)
	_goal_dir("rfore", fore, ka)

	# The trunk leans into the stride and with the look; the head follows the look.
	var pitch := clampf(float(player.get("_look_pitch")), -1.2, 1.2)
	var hips := _turn("Hips", Basis(Vector3.UP, 0.12 * s * sw))
	var chest := hips * _turn("Spine01", Basis(Vector3.RIGHT, 0.12 * s - pitch * 0.15)) \
		* _turn("Spine", Basis(Vector3.RIGHT, -pitch * 0.15))
	_turn("Head", Basis(Vector3.RIGHT, -pitch * 0.55))

	# Each limb aimed under the turn its parents already have (hips, chest).
	_aim("LeftLeg", _goal["lshin"], _aim("LeftUpLeg", _goal["lthigh"], hips))
	_aim("RightLeg", _goal["rshin"], _aim("RightUpLeg", _goal["rthigh"], hips))
	_aim("LeftForeArm", _goal["lfore"], _aim("LeftArm", _goal["lupper"], chest))
	_aim("RightForeArm", _goal["rfore"], _aim("RightArm", _goal["rupper"], chest))
	_apply_motion(dead)
	if _coop:
		_place_props()


## The attack or parry clip over the walking pose (note 167): each bone turned
## from ITS rest the way the clip's turned from the capture's rest (knight space,
## so neither rig's bone axes matter), blended by the move's own in/out. The
## legs and the hips' travel give way to the stride while walking, or the feet
## would skate; the parry plays on the upper body over the guard.
func _apply_motion(dead: bool) -> void:
	_motion_w = 0.0
	if dead:
		return
	var m: Array = player.call("body_motion")
	var parry_t: float = player.get("_parry_t")
	var kind := &""
	var t := 0.0
	var upper_only := false
	if not m.is_empty():
		kind = m[0]
		t = m[1]
	elif parry_t >= 0.0:
		kind = &"parry"
		t = parry_t
		upper_only = true
	if kind == &"" or not PlayerMotion.has_move(kind):
		return
	var w := PlayerMotion.weight_in(kind, t) * PlayerMotion.weight_out(kind, t)
	if w <= 0.0:
		return
	_motion_w = w
	var walk := clampf(_stride * 1.6, 0.0, 1.0)
	var pose := PlayerMotion.body_pose(kind, t)
	var glob := {}
	for i in _order:
		var bn := _skel.get_bone_name(i)
		var rg := _rest_global[i]
		var turn := Basis(pose.get(bn, Quaternion.IDENTITY) as Quaternion)
		glob[i] = (_k2s * turn * _k2s.inverse()) * rg
		var par := _parent[i]
		var want: Basis = glob[i] if par < 0 else (glob[par] as Basis).inverse() * (glob[i] as Basis)
		var bw := w
		if _is_leg(bn):
			bw *= 1.0 - walk
			if upper_only:
				bw = 0.0
		elif upper_only and bn == "Hips":
			bw = 0.0
		if bw <= 0.0:
			continue
		var now := _skel.get_bone_pose_rotation(i)
		_skel.set_bone_pose_rotation(i, now.slerp(want.get_rotation_quaternion(), bw))
	if not upper_only:
		# The hips ride the clip's rise and fall, and a little of its travel.
		var d: Vector3 = pose["_hips"]
		var off := Vector3(d.x * 0.4, d.y, d.z * 0.4) * (1.0 - walk) + Vector3(0.0, d.y, 0.0) * walk
		var hips: int = _b["Hips"]
		_skel.set_bone_pose_position(hips, _skel.get_bone_rest(hips).origin + _k2s_pos * off * w)


static func _is_leg(bn: String) -> bool:
	return bn.ends_with("UpLeg") or bn.ends_with("Leg") or bn.ends_with("Foot") or bn.ends_with("ToeBase")


func _goal_dir(key: String, dir: Vector3, k: float) -> void:
	var d := dir.normalized()
	if not _goal.has(key):
		_goal[key] = d
	else:
		# lerp, not slerp: slerp between two nearly equal unit vectors raised
		# "The axis must be normalized" every frame.
		var v := (_goal[key] as Vector3).lerp(d, k)
		_goal[key] = v.normalized() if v.length_squared() > 1e-8 else d


## Turns the bone so its segment points along `dir` (knight space), given its
## parent chain has already turned by `parent` (skeleton space). Returns this
## bone's whole turn, for its child.
func _aim(bone_name: String, dir: Vector3, parent: Basis) -> Basis:
	var rest: Vector3 = _rest_dir[bone_name]
	var want := (parent.inverse() * (_k2s * dir)).normalized()
	var e := Basis(_arc(rest, want))
	_set_bone(bone_name, e)
	return parent * e


## A rest-relative rotation given in knight space. Returns it in skeleton space,
## for the bones under it.
func _turn(bone_name: String, r: Basis) -> Basis:
	var e := _k2s * r * _k2s.inverse()
	_set_bone(bone_name, e)
	return e


## `e` is a rotation in skeleton space applied to the bone at rest, relative to
## its parent: local = rest_local * (rest_global^-1 * e * rest_global).
func _set_bone(bone_name: String, e: Basis) -> void:
	var i: int = _b.get(bone_name, -1)
	if i < 0:
		return
	var rg := _rest_global[i]
	var local := _rest_local[i] * (rg.inverse() * e * rg)
	_skel.set_bone_pose_rotation(i, local.get_rotation_quaternion())


func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var c := from.cross(to)
	var d := from.dot(to)
	if d < -0.9999:
		var axis := from.cross(Vector3.UP)
		if axis.length_squared() < 0.0001:
			axis = from.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()


# --- What is in hand ----------------------------------------------------------------

## The sword and spear, placed each frame at the hands in the direction
## of the forearms (props are children of the knight's root: knight space).
func _place_props() -> void:
	var to_k := _rel_transform(_skel, _knight)
	var hand := to_k * _skel.get_bone_global_pose(_b["RightHand"])
	var hand_r := hand.origin
	var fore_r: Vector3 = _goal["rfore"]
	var grip := hand_r + fore_r * 0.07
	var sword_dir := fore_r + Vector3(0.0, 0.65, 0.6)
	var spear_dir := fore_r
	if _motion_w > 0.0:
		# In a clip the weapon is where the capture's fist holds it (as in first
		# person, PlayerMotion.fp_sword): the blade out of the thumb side, the
		# spear along the forearm.
		var hb := hand.basis.orthonormalized() * _hand_rest_k.inverse()
		var fore_now := (hb * _fore_rest_k).normalized()
		var clip_grip := hand_r + fore_now * PlayerMotion.GRIP_OUT
		sword_dir = sword_dir.normalized().lerp((hb * PlayerMotion.BLADE_REST).normalized(), _motion_w)
		spear_dir = fore_r.normalized().lerp(fore_now, _motion_w)
		grip = grip.lerp(clip_grip, _motion_w)
	_sword.transform = Transform3D(_along(sword_dir), grip)
	_spear.transform = Transform3D(_along(spear_dir), grip)


## A basis whose +Y runs along `dir`.
func _along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y).normalized())


func _build_props(i: int) -> void:
	_props = Node3D.new()
	_props.name = "InHand"
	_knight.add_child(_props)
	# Props live in knight space, which is scaled: sizes are in metres / SCALE.
	var u := 1.0 / SCALE
	# The user's sword and spear (note 163), the same models as in first person,
	# shrunk to the body. Each prop's +Y runs from the grip along the weapon.
	# The sword model: pommel 0, guard SWORD_GUARD, tip 2.65 on +Y; a metre long
	# here, held where the first-person fist holds it (0.42 from guard to pommel).
	_sword = Node3D.new()
	_props.add_child(_sword)
	var sword := SWORD.instantiate() as Node3D
	var ss := SWORD_LENGTH / 2.65 * u
	sword.scale = Vector3.ONE * ss
	sword.position = Vector3(0.0, -SWORD_GUARD * 0.58 * ss, 0.0)
	_sword.add_child(sword)
	# The spear model runs along -Z, the hand at its origin, 2.74 long; here
	# turned onto +Y and 2.2 m long.
	_spear = Node3D.new()
	_props.add_child(_spear)
	var spear := SPEAR.instantiate() as Node3D
	var sp := SPEAR_LENGTH / 2.74 * u
	spear.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * sp), Vector3.ZERO)
	_spear.add_child(spear)
	_label = Label3D.new()
	_label.text = NAMES[i]
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.font_size = 28
	_label.pixel_size = 0.004
	_label.modulate = CLOTH[i].lightened(0.45)
	_label.outline_size = 6
	_label.position = Vector3(0.0, 2.05, 0.0)
	add_child(_label)
