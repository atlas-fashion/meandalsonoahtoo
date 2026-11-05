extends Node3D

## The player's body, and the only one (note 168; the user: "the player
## shouldn't have two separate models for the camera and for third person, it
## should all be one model from different perspectives ... items shouldn't have
## their own player model"). The knight in the user's dark armor
## (models/player_knight.glb, note 166), on the Meshy knight's skeleton (note 155).
##
## Seen three ways, the same body each time:
## - FROM ITS OWN EYES: the camera is in its head. The player's own camera draws
##   it with the head and neck cut away (`_make_view_meshes`: every triangle a
##   head bone carries), so the arms, the hands, the chest and the legs below are
##   there when they look down, and nothing of the helmet is in front of the eye.
##   Its arms hold whatever is in hand (first_person_arms.gd solves them onto it).
## - BY THE OTHER PLAYER in co-op (note 79): the whole knight, on its own layer
##   (split_screen.gd AVATAR), and a name over its head.
## - AS A SHADOW for the moon and every lit torch, while `Graphics.body_shadow` is on.
##
## A child of the player, so it already turns with their yaw. Every bone is posed
## here from the player each frame: the legs stride with their pace, the arms
## swing, the head follows where they look, the left forearm comes up to guard,
## the whole knight lies down when they die and is gone while they hide. Every
## attack and the parry are Higgsfield clips (notes 167, 168, player_motion.gd):
## `_apply_motion` lays the clip's pose over the walking one, every bone, blended
## in and out with the move -- the legs left to the stride while they walk -- and
## the chest bends with the look (`LOOK_BEND`) so a cut goes where the player
## looks. The arms are then finished by first_person_arms.gd (it reads the clip's
## own arm pose here, `clip_arm`, and blends its IK with it).
##
## Posing: a target is a DIRECTION for a limb segment in the knight's own space
## (+Z forward, +X its left, +Y up), reached by the shortest turn from the
## segment's rest direction, relative to its parent's turn (`_aim`); trunk and
## head turns are rotations in the same space (`_turn`). Both go through
## `_set_bone`, which turns a rest-relative rotation in skeleton space into the
## bone's local pose, so the rig's own bone axes never matter.

const KNIGHT := preload("res://models/player_knight.glb")
## The bones whose triangles the player's own camera does not draw: the helmet
## and the neck, which would sit over the eye, and the pauldrons (they ride the
## shoulder bones, note 156), which sit at its height either side and filled the
## bottom of the view through every cut. Seen from outside and in the shadow,
## as ever.
const HEAD_BONES := ["Head", "neck", "head_end", "headfront", "LeftShoulder", "RightShoulder"]
## How much of the look's pitch the chest bends by under an attack clip: a cut
## aimed up or down goes there. And a lean into every attack on top (radians):
## the captures cut at shoulder height, which from the eyes is the arm across
## the face and the blade over an enemy's head.
const LOOK_BEND := 0.6
const ATTACK_LEAN := 0.22
const CLOTH := [Color(0.42, 0.12, 0.08), Color(0.13, 0.22, 0.38)]
const NAMES := ["PLAYER 1", "PLAYER 2"]
## The knight is 1.70 m to the top of the helmet (the armor built to it); at 1.05 its visor sits
## at the camera's 1.6 m and its crest at 1.79, inside the 1.8 m capsule.
const SCALE := 1.05
## How bright the molten cracks glow (the emission map the build cut out of the
## albedo). The game is dark: 1.0 was barely there under the torches.
const GLOW := 2.2
## The knight's layer when alone (split_screen.gd AVATAR[0]: nothing else uses
## it outside co-op). Every light's shadow_caster_mask includes it. The whole
## knight is there, casting the shadow; the headless one the eye sees is on the
## world's own layer.
const SOLO_LAYER := 1 << 13

var player: Node3D
var _coop := false
var _layer := SOLO_LAYER
var _knight: Node3D
var _skel: Skeleton3D
var _meshes: Array[GeometryInstance3D] = []
## The same knight without its head, for the player's own camera.
var _view_meshes: Array[GeometryInstance3D] = []
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
## The clip the body is in this frame, 0..1 (`_apply_motion`), and its own pose
## of each arm bone (local), for first_person_arms.gd to blend its IK with.
var motion_w := 0.0
var _clip_local := {}
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
	_make_view_meshes()
	_build_label(clampi(int(p.get("player_index")), 0, 1))
	set_mode(layer, coop)
	if not Graphics.changed.is_connected(_apply_graphics):
		Graphics.changed.connect(_apply_graphics)


## Alone or co-op -- player.gd `set_view_layers` turns the lone body into the
## co-op one. `layer` is where the whole knight goes: alone, the shadow-only
## SOLO_LAYER; in co-op, the layer the other half draws. The headless knight is
## on the layer only this player's camera draws (the world's own, alone).
func set_mode(layer: int, coop: bool) -> void:
	_coop = coop
	_layer = layer
	name = "CoopAvatar" if coop else "Body"
	var view := 1
	if coop and int(player.get("_viewmodel_layer")) != 0:
		view = int(player.get("_viewmodel_layer"))
	for g in _meshes:
		_set_layers(g, layer)
	for g in _view_meshes:
		_set_layers(g, view)
	_label.visible = coop
	_apply_graphics()


## Hidden while its layers change: a lit instance whose layers change in place
## stays paired with its lights ("BUG, indexing did not unpair geometries from
## light", a flood of them).
static func _set_layers(g: GeometryInstance3D, layers: int) -> void:
	if g.layers == layers:
		return
	var shown := g.visible
	g.visible = false
	g.layers = layers
	g.visible = shown


func _apply_graphics() -> void:
	var cast := Graphics.body_shadow
	for g in _meshes:
		if _coop:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.visible = true
		else:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			g.visible = cast
	for g in _view_meshes:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The knight without its head (`HEAD_BONES`), sharing the skeleton and skin:
## each surface's triangles kept unless a corner is carried mostly by a head
## bone. Cut once and shared by every player.
static var _headless := {}


func _make_view_meshes() -> void:
	for g in _meshes:
		var mi := g as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null:
			continue
		var key := mi.mesh.get_rid().get_id()
		var cut: ArrayMesh = _headless.get(key)
		if cut == null:
			cut = _cut_head(mi)
			_headless[key] = cut
		var view := MeshInstance3D.new()
		view.name = String(mi.name) + "View"
		view.mesh = cut
		view.skin = mi.skin
		mi.get_parent().add_child(view)
		view.transform = mi.transform
		view.skeleton = view.get_path_to(_skel)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s)
			if m != null:
				view.set_surface_override_material(s, m)
		# A hand's breadth from the eye: never culled for being off to one side.
		view.extra_cull_margin = 2.0
		_view_meshes.append(view)


func _cut_head(mi: MeshInstance3D) -> ArrayMesh:
	var head := {}
	for b in mi.skin.get_bind_count():
		var bn := mi.skin.get_bind_name(b)
		if bn == &"":
			bn = _skel.get_bone_name(mi.skin.get_bind_bone(b))
		if String(bn) in HEAD_BONES:
			head[b] = true
	var out := ArrayMesh.new()
	for s in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var per := 4 if bones.size() <= verts.size() * 4 else 8
		var in_head := PackedByteArray()
		in_head.resize(verts.size())
		for v in verts.size():
			var weight := 0.0
			for k in per:
				if head.has(int(bones[v * per + k])):
					weight += float(weights[v * per + k])
			in_head[v] = 1 if weight > 0.5 else 0
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if in_head[idx[t]] == 0 and in_head[idx[t + 1]] == 0 and in_head[idx[t + 2]] == 0:
				kept.append(idx[t])
				kept.append(idx[t + 1])
				kept.append(idx[t + 2])
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
			Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0)
		out.surface_set_material(s, mi.mesh.surface_get_material(s))
	return out


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
	_label.visible = _coop and not dead
	# Down and dead, the eye is not in it: the player's own camera draws none of it.
	for g in _view_meshes:
		g.visible = _lie < 0.05
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
	_apply_motion(dead, pitch)


## The attack or parry clip over the walking pose (note 167): each bone turned
## from ITS rest the way the clip's turned from the capture's rest (knight space,
## so neither rig's bone axes matter), blended by the move's own in/out. The
## legs and the hips' travel give way to the stride while walking, or the feet
## would skate; the parry plays on the upper body over the guard.
func _apply_motion(dead: bool, pitch: float) -> void:
	motion_w = 0.0
	_clip_local.clear()
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
	motion_w = w
	var walk := clampf(_stride * 1.6, 0.0, 1.0)
	var not_left: bool = PlayerMotion.move(kind).get("right_only", false)
	var pose := PlayerMotion.body_pose(kind, t)
	var glob := {}
	for i in _order:
		var bn := _skel.get_bone_name(i)
		var rg := _rest_global[i]
		var turn := Basis(pose.get(bn, Quaternion.IDENTITY) as Quaternion)
		glob[i] = (_k2s * turn * _k2s.inverse()) * rg
		var par := _parent[i]
		var want: Basis = glob[i] if par < 0 else (glob[par] as Basis).inverse() * (glob[i] as Basis)
		if bn.ends_with("Arm") or bn.ends_with("Hand"):
			_clip_local[i] = want.get_rotation_quaternion()
		var bw := w
		# A one-handed sword: the left arm keeps to the walk (or the guard) through
		# the sword's clips, which were captured with a shield on it.
		if not_left and bn.begins_with("Left") and not _is_leg(bn):
			bw = 0.0
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
	# The chest bent with the look, over the clip: a cut goes where they look.
	for bn in ["Spine01", "Spine"]:
		var i: int = _b[bn]
		var par := _parent[i]
		var axis := (_skel.get_bone_global_pose(par).basis.orthonormalized().inverse() * (_k2s * Vector3.RIGHT)).normalized()
		var bend := Quaternion(axis, (-pitch * LOOK_BEND + ATTACK_LEAN) * 0.5 * w)
		_skel.set_bone_pose_rotation(i, bend * _skel.get_bone_pose_rotation(i))


## The clip's own local turn of arm bone `i` this frame, or null outside a clip.
func clip_arm(i: int) -> Variant:
	return _clip_local.get(i)


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


# --- The name over the head (co-op) ---------------------------------------------------

func _build_label(i: int) -> void:
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
