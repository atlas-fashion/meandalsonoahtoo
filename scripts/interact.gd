class_name Interact
extends RefCounted

## What everything you can use shows when you are close enough: chests, the
## mimic (which has to look exactly like a chest), bone cages, doors and
## criers. Nothing is drawn in the world any more -- the HUD's crosshair turns
## into the interact cursor while any prompt is up (`focus`). The key is the
## "interact" action (E).

const GROUP := &"interact_prompt"


## An invisible marker: its `visible` says "usable now", its `text` what E does
## ("Open", "Strike", "Full"...), which the cursor reads for its colour.
class Prompt extends Node3D:
	var text := ""
	## Co-op: the player it is up for (their HUD shows it); null = whoever.
	var player: Node = null

	func _ready() -> void:
		add_to_group(GROUP)


static func prompt(text := "E   Open", at := Vector3.ZERO) -> Prompt:
	var marker := Prompt.new()
	marker.name = "Prompt"
	marker.text = text
	marker.position = at
	marker.visible = false
	return marker


## The prompt that is up right now, or null. Several can be (a chest beside a
## cage); any of them means E does something. Given a `player`, only a prompt
## up for them (or for whoever) counts -- co-op, each HUD its own.
static func focus(tree: SceneTree, for_player: Node = null) -> Prompt:
	for node in tree.get_nodes_in_group(GROUP):
		var p := node as Prompt
		if p != null and p.is_visible_in_tree() \
				and (for_player == null or p.player == null or p.player == for_player):
			return p
	return null


## Co-op: the player who can use `node` now -- within `near` (flat) and
## `rise` (height) of it, not in a menu, a scene, a hiding place or a robot
## rat's eyes, dead or not, and with their view on it (`looked_at`, within
## `reach` of their eye). The first such player, by index; null if none.
## Outside co-op, the one player under the same tests.
static func chooser(node: Node3D, near: float, rise := 1.5, reach := 3.4, margin := 0.1,
		parts: Array = []) -> Node:
	for p in Coop.all():
		if p.get("ui_open") or p.get("in_cutscene") or p.get("_dead") == true or p.get("remote_view"):
			continue
		var to: Vector3 = (p as Node3D).global_position - node.global_position
		if Vector2(to.x, to.z).length() > near or absf(to.y) > rise:
			continue
		if looked_at(node, reach, margin, parts, p):
			return p
	return null


## True while the centre of the view lies on `node`: the view ray meets the box
## round everything drawn under it (meshes and multimeshes, padded by `margin`)
## within `reach` metres of the eye. Nothing can be used without the crosshair
## on it. The box is measured once, the first time it is asked for, in the
## node's own space -- so it moves and turns with the node.
## `parts`, when given, are the only subtrees measured -- for a node that also
## carries big effect meshes (the mimic's landing marker and impact ring).
static func looked_at(node: Node3D, reach := 3.4, margin := 0.1, parts: Array = [], by: Node = null) -> bool:
	# Co-op: along the eyes of the player asked about (`by`), or the first.
	var viewer: Node = by if by != null else (Coop.all()[0] if Coop.count() > 0 else null)
	var camera: Camera3D = Coop.camera(viewer) if viewer != null and Coop.active \
		else node.get_viewport().get_camera_3d()
	if camera == null:
		return false
	# Shut in a hiding place, the only thing within reach is its doors (which
	# handle that themselves).
	var player := viewer
	if player != null and player.has_method("is_hidden") and player.is_hidden():
		return false
	var box: AABB
	if node.has_meta(&"aim_box"):
		box = node.get_meta(&"aim_box")
	else:
		box = drawn_bounds(node, parts)
		if box.size == Vector3.ZERO:
			return false
		node.set_meta(&"aim_box", box)
	var to_local := node.global_transform.affine_inverse()
	var from := to_local * camera.global_position
	var dir := to_local.basis * -camera.global_basis.z.normalized()
	var hit: Variant = box.grow(margin).intersects_ray(from, dir)
	if hit == null:
		return false
	return (node.global_transform * (hit as Vector3)).distance_to(camera.global_position) <= reach


## The box round every visible mesh under `node` (or under each of `parts`), in
## `node`'s space. Lights, labels and particles are left out: their bounds are
## their reach, not a shape.
static func drawn_bounds(node: Node3D, parts: Array = []) -> AABB:
	var to_node := node.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	var found: Array = []
	for root in (parts if not parts.is_empty() else [node]):
		found.append_array((root as Node).find_children("*", "GeometryInstance3D", true, false))
		if root != node and (root is MeshInstance3D or root is MultiMeshInstance3D):
			found.append(root)
	for child in found:
		if not (child is MeshInstance3D or child is MultiMeshInstance3D):
			continue
		var gi := child as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var part: AABB = (to_node * gi.global_transform) * gi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## True for the key press that should trigger an interaction.
static func pressed(event: InputEvent, by: Node = null) -> bool:
	# Co-op: only from the device of the player it is for (coop.gd `owns`).
	return event.is_action_pressed("interact") and not event.is_echo() \
		and (by == null or Coop.owns(by, event))
