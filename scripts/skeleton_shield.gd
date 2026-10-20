extends Node3D

## The shield skeleton's tower shield (prosthetic.gd &"shield"; note 93): strapped
## across BOTH forearms, which have no hands -- both hand bones are shrunk into the
## wrists (the rig's clips carry no scale tracks, so they stay so). Both arms are
## posed in code over the body's clip, two bones each reaching for a grip on the
## shield's back, and the shield is hung between the two wrists:
##
##   * carried low in front while it is not fighting (`raise` 0),
##   * braced up in front of the chest, the skull peering over it (`raise` 1),
##   * driven forward in a bash (`bash` 0..1; a little drawn back is negative).
##
## Posed only on ticks the rig was advanced (`stepped`), as skeleton_sword.gd:
## the arms are set from the clip's pose, and re-set on their own result they
## would drift. Between those ticks it rides on the body as it was.

const WIDTH := 0.72
const HEIGHT := 1.1
const THICK := 0.05
## Behind the shield's face, where the wrists grip it, and how far apart.
const GRIP_BACK := 0.09
const GRIP_APART := 0.14
const SEEN := 45.0

var enemy: CharacterBody3D
var _sk: Skeleton3D
var _bones := {}
var _len := {}
var _model: MeshInstance3D
var _boss_mat: StandardMaterial3D
var _flash_tween: Tween
var _dropped := false

static var _mesh_cache: ArrayMesh = null


## Straps a shield to both forearms of the rig under `e`. Null without a rig.
static func attach(e: CharacterBody3D) -> Node3D:
	var found := e.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var s: Node3D = load("res://scripts/skeleton_shield.gd").new()
	s.name = "Shield"
	s.set("enemy", e)
	s.set("_sk", sk)
	e.add_child(s)
	return s


func _ready() -> void:
	for side in [&"L", &"R"]:
		var upper := _sk.find_bone("upper_arm." + side)
		var fore := _sk.find_bone("forearm." + side)
		var hand := _sk.find_bone("hand." + side)
		if upper < 0 or fore < 0 or hand < 0:
			continue
		_bones[side] = [upper, fore, hand]
		_len[side] = [_sk.get_bone_global_rest(upper).origin.distance_to(_sk.get_bone_global_rest(fore).origin),
			_sk.get_bone_global_rest(fore).origin.distance_to(_sk.get_bone_global_rest(hand).origin)]
		_sk.set_bone_pose_scale(hand, Vector3.ONE * 0.02)
	_model = MeshInstance3D.new()
	_model.mesh = _mesh()
	_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_model.visibility_range_end = SEEN
	_model.visibility_range_end_margin = 4.0
	add_child(_model)
	# The boss on its face, its own material so it can flare when it blocks.
	_boss_mat = StandardMaterial3D.new()
	_boss_mat.albedo_color = Color(0.32, 0.3, 0.27)
	_boss_mat.metallic = 0.45
	_boss_mat.roughness = 0.45
	_boss_mat.emission_enabled = true
	_boss_mat.emission = Color(1.0, 0.78, 0.45)
	_boss_mat.emission_energy_multiplier = 0.0
	var boss := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.1
	dome.height = 0.1
	dome.radial_segments = 10
	dome.rings = 4
	boss.mesh = dome
	boss.material_override = _boss_mat
	boss.position = Vector3(0.0, 0.0, -THICK * 0.5)
	boss.scale = Vector3(1.0, 1.0, 0.7)
	boss.visibility_range_end = SEEN
	_model.add_child(boss)


## Called by prosthetic.gd every physics tick.
func update(stepped: bool, raise: float, bash: float) -> void:
	if _dropped or _sk == null or not stepped:
		return
	var f := -enemy.global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 1e-4 else Vector3.FORWARD
	var u := Vector3.UP
	var shoulders := {}
	for side in _bones:
		shoulders[side] = _sk.global_transform * _sk.get_bone_global_pose(_bones[side][0]).origin
	if shoulders.size() < 2:
		return
	var chest: Vector3 = (shoulders[&"L"] + shoulders[&"R"]) * 0.5
	# Where the shield's face is centred: low and close carried, high and out
	# braced, further out in a bash.
	var low := chest + f * 0.3 - u * 0.52
	var high := chest + f * 0.44 - u * 0.14
	var centre := low.lerp(high, smoothstep(0.0, 1.0, raise)) + f * 0.32 * bash
	# Leant back a little when carried low.
	var face_up := (u - f * 0.18 * (1.0 - raise)).normalized()
	var across := f.cross(face_up).normalized()
	for side in _bones:
		var out: Vector3 = shoulders[side] - chest
		var s := signf(out.dot(across))
		var grip := centre - f * GRIP_BACK + across * s * GRIP_APART
		_reach(side, shoulders[side], grip, across * s)
	# Hung between the two wrists, facing forward.
	var wrists := Vector3.ZERO
	for side in _bones:
		wrists += _sk.global_transform * _sk.get_bone_global_pose(_bones[side][2]).origin
	wrists /= float(_bones.size())
	var at := wrists + f * GRIP_BACK
	transform = enemy.global_transform.affine_inverse() * Transform3D(Basis.looking_at(f, face_up), at)


## The two bones of one arm reaching for `grip`, the elbow out (`out`) and down.
func _reach(side: StringName, shoulder: Vector3, grip: Vector3, out: Vector3) -> void:
	var bones: Array = _bones[side]
	var lens: Array = _len[side]
	var lu: float = lens[0]
	var lf: float = lens[1]
	var to_sk := _sk.global_transform.affine_inverse()
	var s := to_sk * shoulder
	var h := to_sk * grip
	var d := h - s
	var dist := clampf(d.length(), absf(lu - lf) + 0.01, (lu + lf) * 0.985)
	var dir := d.normalized() if d.length_squared() > 1e-6 else Vector3.DOWN
	var pole := (to_sk.basis * (out * 0.8 + Vector3.DOWN)).normalized()
	pole = pole - dir * pole.dot(dir)
	if pole.length_squared() < 1e-6:
		pole = Vector3.DOWN - dir * dir.y
	pole = pole.normalized()
	var a := (lu * lu - lf * lf + dist * dist) / (2.0 * dist)
	var hgt := sqrt(maxf(lu * lu - a * a, 0.0))
	var elbow := s + dir * a + pole * hgt
	_point(bones[0], elbow - s)
	var e_now := _sk.get_bone_global_pose(bones[1]).origin
	_point(bones[1], (s + dir * dist) - e_now)


func _point(bone: int, dir: Vector3) -> void:
	if dir.length_squared() < 1e-8:
		return
	var pose := _sk.get_bone_global_pose(bone)
	var basis := pose.basis.orthonormalized()
	pose.basis = Basis(Quaternion(basis.y.normalized(), dir.normalized())) * basis
	_sk.set_bone_global_pose(bone, pose)


## A blow taken on the shield: the boss flares and dies away.
func flash() -> void:
	if _boss_mat == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_boss_mat.emission_energy_multiplier = 3.5
	_flash_tween = create_tween()
	_flash_tween.tween_property(_boss_mat, "emission_energy_multiplier", 0.0, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Falls from the dead arms and lies face down on the floor.
func drop() -> void:
	if _dropped:
		return
	_dropped = true
	var held := global_transform
	top_level = true
	global_transform = held
	var f := -enemy.global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length_squared() > 1e-4 else Vector3.FORWARD
	var to := Transform3D(Basis.looking_at(Vector3.DOWN, f), Vector3(global_position.x, enemy.global_position.y + THICK * 0.5 + 0.02,
		global_position.z) + f * 0.4)
	var t := create_tween()
	t.tween_property(self, "global_transform", to, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


## Planks bound in iron, face toward -Z, centred on the origin; built once.
static func _mesh() -> ArrayMesh:
	if _mesh_cache != null:
		return _mesh_cache
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.26, 0.18, 0.11)
	wood.roughness = 0.9
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.25, 0.23, 0.21)
	iron.metallic = 0.4
	iron.roughness = 0.55
	var tools := {}
	var add := func(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(mesh, 0, xf)
	# Four planks, a hair apart, the middle two standing proud.
	for k in 4:
		var plank := BoxMesh.new()
		plank.size = Vector3(WIDTH / 4.0 - 0.008, HEIGHT - 0.04, THICK)
		var x := (float(k) - 1.5) * WIDTH / 4.0
		add.call(plank, Transform3D(Basis(), Vector3(x, 0.0, -0.006 if k == 1 or k == 2 else 0.0)), wood)
	# The iron rim and two bands across.
	for y: float in [-1.0, 1.0]:
		var edge := BoxMesh.new()
		edge.size = Vector3(WIDTH + 0.03, 0.05, THICK + 0.02)
		add.call(edge, Transform3D(Basis(), Vector3(0.0, y * HEIGHT * 0.5, 0.0)), iron)
	for x: float in [-1.0, 1.0]:
		var side := BoxMesh.new()
		side.size = Vector3(0.04, HEIGHT, THICK + 0.02)
		add.call(side, Transform3D(Basis(), Vector3(x * WIDTH * 0.5, 0.0, 0.0)), iron)
	for y: float in [-0.3, 0.3]:
		var band := BoxMesh.new()
		band.size = Vector3(WIDTH, 0.055, 0.012)
		add.call(band, Transform3D(Basis(), Vector3(0.0, y, -THICK * 0.5 - 0.01)), iron)
	# The two straps on the back the forearms go through.
	for x: float in [-GRIP_APART, GRIP_APART]:
		var strap := BoxMesh.new()
		strap.size = Vector3(0.05, 0.16, 0.06)
		add.call(strap, Transform3D(Basis(), Vector3(x, 0.0, THICK * 0.5 + 0.03)), iron)
	var am := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.generate_normals()
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	_mesh_cache = am
	return am
