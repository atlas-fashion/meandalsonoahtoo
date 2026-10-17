extends BoneAttachment3D

## A SHIELD HITBOX (2026-10-17): a box riding a bone, sized from the shield mesh
## itself and grown by SIZE_SCALE "to ensure good reach" (the user). Used by the
## enforcer (enforcer.gd, its swipe) and the decrepit enforcer (decrepit.gd, the
## swipe, the jump and the dash) -- both carry their shield on ARM_L.
##
## Size: the vertices skinned mostly (>= MIN_WEIGHT) to the bone, taken into the
## bone's rest space through the skin's bind pose; their bounding box, scaled by
## SIZE_SCALE about its centre. Measured once per mesh and bone (cached).
##
## A blow lands while its HIT WINDOW is open (each move's start..end, timed by
## its owner) and the box overlaps the target's collision body
## (`overlaps`, a physics shape query -- the box is turned into world units,
## since a query shape cannot be scaled). `set_live` shows it, a translucent
## red box, while a window is open (and `Sandbox.show_hitboxes` is on).

const SIZE_SCALE := 1.5
const MIN_WEIGHT := 0.5
const COLOUR := Color(1.0, 0.12, 0.08, 0.28)
const EDGE := Color(1.0, 0.35, 0.25, 0.9)

## Mesh rid + bone -> AABB of its vertices in the bone's rest space.
static var _cache := {}

## The box, in the bone's space (before the rig's scale).
var box_size := Vector3.ONE
var box_centre := Vector3.ZERO
var live := false
var _vis: MeshInstance3D
var _shape := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


## Rides `bone` of `skeleton`, sized from `meshes` (the skinned parts). False if
## no vertex of them is on that bone.
func setup(skeleton: Skeleton3D, bone: String, meshes: Array) -> bool:
	name = "ShieldHitbox"
	bone_name = bone
	skeleton.add_child(self)
	var box = _bone_box(skeleton, bone, meshes)
	if box == null:
		push_warning("shield hitbox: no vertices on %s" % bone)
		return false
	var aabb: AABB = box
	box_size = aabb.size * SIZE_SCALE
	box_centre = aabb.get_center()
	_build_visual()
	_query.shape = _shape
	_query.collide_with_bodies = true
	_query.collide_with_areas = false
	return true


static func _bone_box(skeleton: Skeleton3D, bone: String, meshes: Array) -> Variant:
	var bone_idx := skeleton.find_bone(bone)
	var out = null
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null or mi.skin == null:
			continue
		var key := "%d:%s" % [mi.mesh.get_rid().get_id(), bone]
		if _cache.has(key):
			var c = _cache[key]
			if c != null:
				out = c if out == null else (out as AABB).merge(c)
			continue
		var skin := mi.skin
		var bind := -1
		for i in skin.get_bind_count():
			if skin.get_bind_name(i) == StringName(bone) \
					or (skin.get_bind_name(i) == &"" and skin.get_bind_bone(i) == bone_idx):
				bind = i
				break
		var box = null
		if bind >= 0:
			var pose := skin.get_bind_pose(bind)
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones = arrays[Mesh.ARRAY_BONES]
				var weights = arrays[Mesh.ARRAY_WEIGHTS]
				if bones == null or weights == null or verts.is_empty():
					continue
				var stride: int = (bones as PackedInt32Array).size() / verts.size()
				for v in verts.size():
					for k in stride:
						var j := v * stride + k
						if bones[j] == bind and weights[j] >= MIN_WEIGHT:
							var p := pose * verts[v]
							box = AABB(p, Vector3.ZERO) if box == null else (box as AABB).expand(p)
							break
		_cache[key] = box
		if box != null:
			out = box if out == null else (out as AABB).merge(box)
	return out


func _build_visual() -> void:
	_vis = MeshInstance3D.new()
	_vis.name = "Visible"
	var mesh := BoxMesh.new()
	mesh.size = box_size
	_vis.mesh = mesh
	_vis.position = box_centre
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = COLOUR
	mat.no_depth_test = false
	_vis.material_override = mat
	_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Its edges, so it reads as a box rather than a pink haze.
	var lines := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var h := box_size * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()
	lines.mesh = im
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = EDGE
	lines.material_override = lm
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(lines)
	_vis.visible = false
	add_child(_vis)


## A hit window open (shown) or shut.
func set_live(on: bool) -> void:
	live = on
	if _vis != null:
		_vis.visible = on and Sandbox.show_hitboxes


## The box in the world: its transform (unscaled) and its size in metres.
func world_box() -> Array:
	var gt := global_transform
	var sc := gt.basis.get_scale()
	return [Transform3D(gt.basis.orthonormalized(), gt * box_centre), box_size * sc]


## Does the box touch `target`'s collision body?
func overlaps(target: CollisionObject3D) -> bool:
	if target == null or not is_inside_tree():
		return false
	var wb := world_box()
	_shape.size = wb[1]
	_query.transform = wb[0]
	_query.collision_mask = target.collision_layer
	for hit in get_world_3d().direct_space_state.intersect_shape(_query, 16):
		if hit["collider"] == target:
			return true
	return false
