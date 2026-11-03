extends Node3D

## The player's body: the molten rust knight (note 155; models/player_knight.glb,
## built by tools/build_player_knight.py from the user's Higgsfield / Meshy
## knight). The game is first person -- you see its arms (first_person_arms.gd)
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
## Posing: a target is a DIRECTION for a limb segment in the knight's own space
## (+Z forward, +X its left, +Y up), reached by the shortest turn from the
## segment's rest direction, relative to its parent's turn (`_aim`); trunk and
## head turns are rotations in the same space (`_turn`). Both go through
## `_set_bone`, which turns a rest-relative rotation in skeleton space into the
## bone's local pose, so the rig's own bone axes never matter.

const KNIGHT := preload("res://models/player_knight.glb")
const CLOTH := [Color(0.42, 0.12, 0.08), Color(0.13, 0.22, 0.38)]
const NAMES := ["PLAYER 1", "PLAYER 2"]
## The Meshy knight is 1.70 m to the top of the helmet; at 1.05 its visor sits
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
	# Dropped as they go down.
	_sword.visible = held == &"sword" and _lie < 0.3
	_spear.visible = held == &"spear" and _lie < 0.3
	_label.visible = _coop and not dead

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
	elif kind in [&"slash", &"chop", &"spin", &"slam", &"raise", &"stab", &"haft"] and t >= 0.0:
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
	if _coop:
		_place_props()


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
	var hand_r := to_k * _skel.get_bone_global_pose(_b["RightHand"]).origin
	var fore_r: Vector3 = _goal["rfore"]
	var grip := hand_r + fore_r * 0.07
	_sword.transform = Transform3D(_along(fore_r + Vector3(0.0, 0.65, 0.6)), grip)
	_spear.transform = Transform3D(_along(fore_r), grip)


## A basis whose +Y runs along `dir`.
func _along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y).normalized())


func _build_props(i: int) -> void:
	var steel := _mat(Color(0.7, 0.72, 0.76), 0.35, 0.8)
	var wood := _mat(Color(0.35, 0.24, 0.14), 0.9)
	_props = Node3D.new()
	_props.name = "InHand"
	_knight.add_child(_props)
	# Props live in knight space, which is scaled: sizes are in metres / SCALE.
	var u := 1.0 / SCALE
	# The sword along +Y from the grip: grip, guard, blade.
	_sword = Node3D.new()
	_props.add_child(_sword)
	_part(_sword, _cyl(0.018 * u, 0.018 * u, 0.14 * u), Vector3(0.0, 0.0, 0.0), wood)
	_part(_sword, _box(Vector3(0.2, 0.03, 0.04) * u), Vector3(0.0, 0.08 * u, 0.0), wood)
	_part(_sword, _box(Vector3(0.05, 0.85, 0.012) * u), Vector3(0.0, 0.52 * u, 0.0), steel)
	# The spear along +Y, the head forward.
	_spear = Node3D.new()
	_props.add_child(_spear)
	_part(_spear, _cyl(0.018 * u, 0.018 * u, 2.0 * u), Vector3(0.0, 0.2 * u, 0.0), wood)
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.045 * u
	head.height = 0.22 * u
	_part(_spear, head, Vector3(0.0, 1.3 * u, 0.0), steel)
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


# --- Pieces -------------------------------------------------------------------------

func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _part(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi
