extends RefCounted

## The scoutposts' chest (note 182, the user: "a stylized chest that fits the
## artstyle"): the Tripo chest already in the project (models/tripo_test_chest.glb,
## banded wood under an iron-bound dome) on chest.gd, its lid cut from the body so
## it swings open. The model's front -- the hasp -- is its +X, its length along
## Z; it is turned so the front is the chest's +Z and the lid hinges along X at
## the back, as chest.gd's lid (`LidPivot`, rotation.x) expects.

const MODEL := preload("res://models/tripo_test_chest.glb")
const CHEST_SCRIPT := preload("res://scripts/chest.gd")
## Where the lid parts from the body, as a share of the model's height from its
## foot: the iron band under the dome.
const LID_AT := 0.6
## Length of the chest in the hall (m).
const LENGTH := 1.15

static var _parts: Array = []


## The two halves of the model, [base, lid], cut by triangle along LID_AT; the
## lid's vertices relative to its hinge (the back of the cut). Shared.
static func _cut() -> Array:
	if not _parts.is_empty():
		return _parts
	var root := MODEL.instantiate()
	var found := root.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		root.free()
		return []
	var mi := found[0] as MeshInstance3D
	var mesh := mi.mesh
	var aabb := mesh.get_aabb()
	var split := aabb.position.y + aabb.size.y * LID_AT
	var hinge := Vector3(aabb.position.x, split, 0.0)
	var arrays := mesh.surface_get_arrays(0)
	# Both faces: the model is one surface, so an open lid and the box's inside
	# are seen from behind.
	var mat := mi.get_active_material(0)
	if mat is BaseMaterial3D:
		mat = mat.duplicate()
		(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if index.is_empty():
		index.resize(verts.size())
		for i in verts.size():
			index[i] = i
	var halves: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array()]
	for t in range(0, index.size(), 3):
		var c := (verts[index[t]] + verts[index[t + 1]] + verts[index[t + 2]]) / 3.0
		var k := 1 if c.y > split else 0
		halves[k].append(index[t])
		halves[k].append(index[t + 1])
		halves[k].append(index[t + 2])
	var out: Array = []
	for k in 2:
		var a := arrays.duplicate()
		a[Mesh.ARRAY_INDEX] = halves[k]
		if k == 1:
			var moved := verts.duplicate()
			for i in moved.size():
				moved[i] -= hinge
			a[Mesh.ARRAY_VERTEX] = moved
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		m.surface_set_material(0, mat)
		out.append(m)
	out.append(hinge)
	out.append(aabb)
	root.free()
	_parts = out
	return out


## A chest, closed, its front +Z, its foot at the origin; not yet in the tree.
## `coins` and `potions` what it gives (chest.gd).
static func make(potions: int, coins: int) -> Node3D:
	var chest := Node3D.new()
	chest.name = "LootChest"
	chest.set_script(CHEST_SCRIPT)
	chest.set("min_amount", potions)
	chest.set("max_amount", potions)
	chest.set("coins", coins)
	chest.set("opened_title", "CHEST OPENED")
	var parts := _cut()
	if parts.is_empty():
		return chest
	var hinge: Vector3 = parts[2]
	var aabb: AABB = parts[3]
	var s := LENGTH / aabb.size.z
	# Turned -90 about Y: the model's +X (the hasp) to +Z. Its foot on the floor.
	var turn := Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * s)
	var lift := Vector3(0.0, -aabb.position.y * s, 0.0)
	var model := Node3D.new()
	model.name = "Model"
	chest.add_child(model)
	var base := MeshInstance3D.new()
	base.name = "Base"
	base.mesh = parts[0]
	base.transform = Transform3D(turn, lift)
	model.add_child(base)
	var pivot := Node3D.new()
	pivot.name = "LidPivot"
	pivot.position = turn * hinge + lift
	chest.add_child(pivot)
	var lid := MeshInstance3D.new()
	lid.name = "Lid"
	lid.mesh = parts[1]
	lid.basis = turn
	pivot.add_child(lid)
	# The inside: a floor of dark boards just under the rim, so it is not seen
	# through to the flags.
	var inside := MeshInstance3D.new()
	inside.name = "Inside"
	var plane := PlaneMesh.new()
	plane.size = Vector2(aabb.size.z * s * 0.9, aabb.size.x * s * 0.86)
	inside.mesh = plane
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.06, 0.04)
	dark.roughness = 1.0
	inside.material_override = dark
	inside.position = Vector3(0.0, (hinge.y - aabb.position.y) * s - 0.12, 0.0)
	model.add_child(inside)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1 | 256 | 512
	body.collision_mask = 0
	chest.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(aabb.size.z, aabb.size.y, aabb.size.x) * s
	shape.shape = box
	shape.position = Vector3(0.0, aabb.size.y * s * 0.5, 0.0)
	body.add_child(shape)
	return chest
