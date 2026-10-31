extends "res://scripts/skeleton_sword.gd"

## The sword skeleton's blade (sword_skeleton.gd, note 135). skeleton_sword.gd
## poses an arm and hangs a model on it; here the clip does both, and the blade is
## part of the skinned mesh on the rig's `blade` bone. Only the sweep is kept: a
## blow lands where the real blade passes through the player, wherever the clip
## has swung it. `update` and `drop` have nothing to do: the death clips let go of
## the blade themselves.

## Along the bone from the grip: where the blade starts and its point.
const HILT := 0.08
const TIP := 1.16

var _bone := -1


static func grip(e: CharacterBody3D) -> Node3D:
	var found := e.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var b := sk.find_bone("blade")
	if b < 0:
		return null
	var s: Node3D = load("res://scripts/sword_skeleton_blade.gd").new()
	s.name = "Blade"
	s.set("enemy", e)
	s.set("kind", &"blade")
	s.set("_sk", sk)
	s.set("_bone", b)
	e.add_child(s)
	return s


func _ready() -> void:
	pass


func reach() -> float:
	return TIP


func update(_stepped: bool, _phase: int, _move: int, _p: float) -> void:
	pass


func blade() -> Array:
	var g := _sk.global_transform * _sk.get_bone_global_pose(_bone)
	var y := g.basis.y.normalized()
	return [g.origin + y * HILT, g.origin + y * TIP]


func drop() -> void:
	_dropped = true
