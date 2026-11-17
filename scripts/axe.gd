extends Node3D

## The axe (2026-10-20): the third weapon, held when the weapon-wheel slot in
## hand holds `&"axe"` (none does since note 172; kept for when one does). Its
## fighting is its Weapon's (note 190, the timing-combat template:
## scenes/weapons/axe.tscn): LMB, one heavy CHOP -- hauled up overhead and hung
## there, then brought straight down. Its throw (Q) and berserk (F) went with
## the template. Walking pace with it in hand is `CARRY_SPEED` (player.gd
## `_attack_move_scale`).
##
## This node is what the eye sees: the axe (built from primitives along +Y, the
## hand at the origin, the bearded head at the top with its edge toward -Z) put
## on the Weapon's grip every frame -- whose haft runs down -Z, so the model is
## turned a quarter round X onto it (`GRIP_TO_MODEL`).

## Walking pace with the axe in hand (0.75 in note 87, a little slower in 90).
const CARRY_SPEED := 0.65
## The pose the axe rests in, head space.
const REST_AT := Vector3(0.3, -0.42, -0.42)
## The model's frame from the grip's: the haft (model +Y) down the grip's -Z.
const GRIP_TO_MODEL := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3.ZERO)

var player: CharacterBody3D
var weapon: Weapon

var _model: Node3D
var _raise := 0.0

static var _mats := {}


func setup(p: CharacterBody3D, w: Weapon) -> void:
	player = p
	weapon = w
	name = "Axe"
	_model = _build_model(true)
	add_child(_model)
	transform = _rest()
	_model.visible = false


func ready_in_hand() -> bool:
	return true


func is_away() -> bool:
	return false


func busy() -> bool:
	return weapon != null and not weapon.is_idle()


func time_scale() -> float:
	return player.attack_time_scale


func reset() -> void:
	if weapon != null:
		weapon.reset()


func interrupt() -> void:
	if weapon != null:
		weapon.interrupt()


func _process(delta: float) -> void:
	if player == null:
		return
	var hands = player.get("rats")
	var held: bool = player.held_item() == &"axe" and not player.hands_busy and not player.is_hidden() \
		and not (hands != null and hands.get("holding") == true)
	_raise = move_toward(_raise, 1.0 if held else 0.0, delta / 0.2)
	_model.visible = _raise > 0.01
	var pose := _rest()
	if weapon != null and weapon.grip != null:
		pose = weapon.grip.transform * GRIP_TO_MODEL
	var g: float = player.guard_amount()
	if g > 0.0:
		pose = Transform3D(pose.basis, pose.origin + PLAYER.GUARD_DRAW * g)
	var lowered := Transform3D(pose.basis, pose.origin + Vector3(0.05, -0.7, 0.25))
	var up: float = _raise * (1.0 - player.weapon_dip())
	transform = lowered.interpolate_with(pose, up * up * (3.0 - 2.0 * up))


## A pose with the haft along `up` from the hand at `at`, the edge toward `edge`.
static func _held(at: Vector3, up: Vector3, edge: Vector3) -> Transform3D:
	var y := up.normalized()
	var fwd := (edge - y * edge.dot(y)).normalized()
	var z := -fwd
	return Transform3D(Basis(y.cross(z), y, z), at)


func _rest() -> Transform3D:
	return _held(REST_AT, Vector3(0.1, 1.0, -0.55), Vector3(-1.0, 0.0, -0.4))


## The player's script, for its `GUARD_DRAW`.
const PLAYER := preload("res://scripts/player.gd")


# --- Materials and the model ------------------------------------------------------

static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"shock":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_color = Color(1.0, 0.15, 0.05, 0.85)
		&"trail":
			# Only if the player has no SweepTrail to borrow from: its settings.
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.vertex_color_use_as_albedo = true
			m.disable_receive_shadows = true
		&"wood":
			m.albedo_texture = load("res://textures/wood_door_albedo.png")
			m.albedo_color = Color(0.82, 0.66, 0.5)
			m.roughness = 0.8
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		&"iron":
			# Half metal, as the spear's: fully metallic rendered black here.
			m.albedo_color = Color(0.62, 0.63, 0.66)
			m.metallic = 0.4
			m.roughness = 0.38
		&"edge":
			m.albedo_color = Color(0.9, 0.91, 0.94)
			m.metallic = 0.4
			m.roughness = 0.2
		&"edge_lit":
			# Thrown, the edge glows faintly, so it can be followed out and back.
			m.albedo_color = Color(0.9, 0.91, 0.94)
			m.roughness = 0.2
			m.emission_enabled = true
			m.emission = Color(1.0, 0.35, 0.2)
			m.emission_energy_multiplier = 1.4
		&"leather":
			m.albedo_color = Color(0.2, 0.12, 0.07)
			m.roughness = 0.9
	_mats[key] = m
	return m


## The axe along +Y, the hand at the origin: an ash haft 0.8 m long with a
## leather grip and a knob at the end, iron straps under a bearded head whose
## edge faces -Z. `in_hand` gives every surface the viewmodel's pulled-forward
## depth, as the sword has.
func _build_model(in_hand: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "AxeModel"
	var parts: Array = []
	var haft := CylinderMesh.new()
	haft.top_radius = 0.019
	haft.bottom_radius = 0.023
	haft.height = 0.8
	haft.radial_segments = 8
	parts.append([haft, &"wood", Transform3D(Basis(), Vector3(0.0, 0.28, 0.0))])
	var knob := SphereMesh.new()
	knob.radius = 0.03
	knob.height = 0.05
	knob.radial_segments = 8
	knob.rings = 4
	parts.append([knob, &"iron", Transform3D(Basis(), Vector3(0.0, -0.12, 0.0))])
	var grip := CylinderMesh.new()
	grip.top_radius = 0.026
	grip.bottom_radius = 0.026
	grip.height = 0.2
	grip.radial_segments = 8
	parts.append([grip, &"leather", Transform3D(Basis(), Vector3(0.0, -0.01, 0.0))])
	for y: float in [0.46, 0.5]:
		var band := TorusMesh.new()
		band.inner_radius = 0.019
		band.outer_radius = 0.027
		band.rings = 10
		band.ring_segments = 5
		parts.append([band, &"iron", Transform3D(Basis(), Vector3(0.0, y, 0.0))])
	parts.append([_head_mesh(), &"iron", Transform3D()])
	parts.append([_edge_mesh(), &"edge" if in_hand else &"edge_lit", Transform3D()])
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		var mat: StandardMaterial3D = _mat(part[1])
		if in_hand:
			mat = mat.duplicate() as StandardMaterial3D
			mat.use_z_clip_scale = true
			mat.z_clip_scale = float(player.get("sword_draw_depth")) if player != null else 0.12
		mi.material_override = mat
		mi.transform = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## The head's outline in the haft's plane, (z, y): the eye round the haft, the
## upper horn, the curved edge, the long beard swept back to the haft, and a
## short poll behind.
const HEAD_OUTLINE := [
	Vector2(0.06, 0.66), Vector2(0.03, 0.68), Vector2(-0.04, 0.665), Vector2(-0.12, 0.70),
	Vector2(-0.175, 0.735), Vector2(-0.195, 0.69), Vector2(-0.205, 0.62), Vector2(-0.2, 0.55),
	Vector2(-0.185, 0.49), Vector2(-0.16, 0.445), Vector2(-0.12, 0.47), Vector2(-0.07, 0.52),
	Vector2(-0.035, 0.55), Vector2(0.03, 0.555), Vector2(0.06, 0.575),
]


## Half the head's thickness at `z`: fattest at the eye, thin toward the edge.
static func _thick(z: float) -> float:
	return lerpf(0.026, 0.006, clampf((-z - 0.02) / 0.17, 0.0, 1.0))


static func _head_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := PackedVector2Array(HEAD_OUTLINE)
	var tris := Geometry2D.triangulate_polygon(outline)
	var at := func(p: Vector2, side: float) -> Vector3: return Vector3(side * _thick(p.x), p.y, p.x)
	for i in range(0, tris.size(), 3):
		var a: Vector2 = outline[tris[i]]
		var b: Vector2 = outline[tris[i + 1]]
		var c: Vector2 = outline[tris[i + 2]]
		# Both faces, wound to face outward.
		st.add_vertex(at.call(a, 1.0))
		st.add_vertex(at.call(c, 1.0))
		st.add_vertex(at.call(b, 1.0))
		st.add_vertex(at.call(a, -1.0))
		st.add_vertex(at.call(b, -1.0))
		st.add_vertex(at.call(c, -1.0))
	var n := outline.size()
	for i in n:
		var p: Vector2 = outline[i]
		var q: Vector2 = outline[(i + 1) % n]
		st.add_vertex(at.call(p, 1.0))
		st.add_vertex(at.call(q, 1.0))
		st.add_vertex(at.call(q, -1.0))
		st.add_vertex(at.call(p, 1.0))
		st.add_vertex(at.call(q, -1.0))
		st.add_vertex(at.call(p, -1.0))
	st.generate_normals()
	return st.commit()


## The bright bevel along the cutting edge: a thin strip just proud of the head
## from the horn to the beard.
static func _edge_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge: Array = HEAD_OUTLINE.slice(4, 10)
	for side: float in [1.0, -1.0]:
		for i in edge.size() - 1:
			var p: Vector2 = edge[i]
			var q: Vector2 = edge[i + 1]
			var pi := Vector2(p.x + 0.03, p.y)
			var qi := Vector2(q.x + 0.03, q.y)
			var v := func(u: Vector2) -> Vector3: return Vector3(side * (_thick(u.x) + 0.0015), u.y, u.x)
			if side > 0.0:
				st.add_vertex(v.call(p))
				st.add_vertex(v.call(qi))
				st.add_vertex(v.call(q))
				st.add_vertex(v.call(p))
				st.add_vertex(v.call(pi))
				st.add_vertex(v.call(qi))
			else:
				st.add_vertex(v.call(p))
				st.add_vertex(v.call(q))
				st.add_vertex(v.call(qi))
				st.add_vertex(v.call(p))
				st.add_vertex(v.call(qi))
				st.add_vertex(v.call(pi))
	st.generate_normals()
	return st.commit()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
