extends RefCounted

## Glowing yellow eyes in a skeleton's sockets (2026-10-08): every skeleton
## enemy -- including the coffin guards -- the way the bone-cage skulls glow red
## (those stay red; this is not used for them).
##
## `attach(root)` finds the rig under `root` and hangs two small glowing balls,
## each with a soft additive halo, from its `head` bone, so they follow every
## animation. Where the sockets are is MEASURED, once per mesh: the vertices
## skinned mainly to `head` are the skull; their box in mesh space (the face is
## +Z on ossuary_skeleton_rigged.glb) gives the socket points, carried into the
## head bone's space through the skin's bind pose.

const COLOUR := Color(1.0, 0.78, 0.16)
## Socket height up the skull (the jaw is cut away, so the cranium and upper
## teeth are all there is), half the gap between them, and how far in from the
## front of the face, as fractions of the skull's box.
const HEIGHT_FRAC := 0.45
const SPREAD_FRAC := 0.22
const DEPTH := 0.035
const EYE_RADIUS := 0.017
const HALO_SIZE := 0.11

static var _cache := {}
static var _ball: SphereMesh
static var _halo: QuadMesh


## Hangs the eyes on the rig under `root`. Returns the node holding them (hide
## it to put them out), or null if there is no skinned skeleton with a head.
static func attach(root: Node) -> Node3D:
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var sk := skeletons[0] as Skeleton3D
	var head := sk.find_bone("head")
	if head < 0:
		return null
	var mi: MeshInstance3D = null
	for node in sk.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			mi = node
			break
	if mi == null:
		return null
	if not _cache.has(mi.mesh):
		_cache[mi.mesh] = _measure(mi, sk, head)
	var points: Array = _cache[mi.mesh]
	if points.is_empty():
		return null
	_make_meshes()
	var holder := BoneAttachment3D.new()
	holder.name = "Eyes"
	holder.bone_name = "head"
	sk.add_child(holder)
	for p: Vector3 in points:
		var ball := MeshInstance3D.new()
		ball.mesh = _ball
		ball.position = p
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(ball)
		var halo := MeshInstance3D.new()
		halo.mesh = _halo
		halo.position = p
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(halo)
	return holder


## The two socket points in the head bone's space.
static func _measure(mi: MeshInstance3D, sk: Skeleton3D, head: int) -> Array:
	var skin := mi.skin
	var bind := -1
	for i in skin.get_bind_count():
		if skin.get_bind_bone(i) == head or skin.get_bind_name(i) == sk.get_bone_name(head):
			bind = i
			break
	if bind < 0:
		return []
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if verts.is_empty() or bones.is_empty():
		return []
	var per := bones.size() / verts.size()
	var box := AABB()
	var found := false
	for v in verts.size():
		var best := -1
		var best_w := 0.0
		for k in per:
			if weights[v * per + k] > best_w:
				best_w = weights[v * per + k]
				best = bones[v * per + k]
		if best == bind and best_w > 0.5:
			box = AABB(verts[v], Vector3.ZERO) if not found else box.expand(verts[v])
			found = true
	if not found:
		return []
	var pose := skin.get_bind_pose(bind)
	var c := box.get_center()
	var y := box.position.y + box.size.y * HEIGHT_FRAC
	var z := box.end.z - DEPTH
	var out: Array = []
	for side: float in [-1.0, 1.0]:
		out.append(pose * Vector3(c.x + side * box.size.x * SPREAD_FRAC, y, z))
	return out


static func _make_meshes() -> void:
	if _ball != null:
		return
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = COLOUR
	core.emission_enabled = true
	core.emission = COLOUR
	core.emission_energy_multiplier = 4.0
	_ball = SphereMesh.new()
	_ball.radius = EYE_RADIUS
	_ball.height = EYE_RADIUS * 2.0
	_ball.radial_segments = 8
	_ball.rings = 4
	_ball.material = core
	# A soft glow round each, so they read from down a corridor.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_color = Color(COLOUR.r, COLOUR.g * 0.85, COLOUR.b, 0.55)
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	grad.gradient = g
	glow.albedo_texture = grad
	_halo = QuadMesh.new()
	_halo.size = Vector2(HALO_SIZE, HALO_SIZE)
	_halo.material = glow
