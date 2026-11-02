extends "res://scripts/skeleton_sword.gd"

## The Proel builder's two hammers (proel_builder.gd, note 149). As with the swordsman's
## blade (sword_skeleton_blade.gd) the clip does all the moving and only the sweep is
## kept, on each arm from the elbow to the head, reading the real bones. `live` says which
## can hurt: a pound brings one down at a time, and in a spin both are flying.

## How far down its bone each head's middle is, from the axle in the yoke.
const HEAD := 0.27
## Which hammers are live.
const NONE := -1
const BOTH := 2

## 0 the left, 1 the right, NONE or BOTH.
var live := NONE

var _bones := [-1, -1]
var _elbows := [-1, -1]
var _before := [[], []]


static func grip(e: CharacterBody3D) -> Node3D:
	var found := e.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	if sk.find_bone("hammer.L") < 0:
		return null
	var s: Node3D = load("res://scripts/proel_builder_hammers.gd").new()
	s.name = "Hammers"
	s.set("enemy", e)
	s.set("kind", &"hammer")
	s.set("_sk", sk)
	s.set("_bones", [sk.find_bone("hammer.L"), sk.find_bone("hammer.R")])
	s.set("_elbows", [sk.find_bone("forearm.L"), sk.find_bone("forearm.R")])
	e.add_child(s)
	return s


func _ready() -> void:
	pass


func reach() -> float:
	return HEAD


func update(_stepped: bool, _phase: int, _move: int, _p: float) -> void:
	pass


## The middle of a head, in the world.
func head(side: int) -> Vector3:
	var g := _sk.global_transform * _sk.get_bone_global_pose(_bones[side])
	return g.origin + g.basis.y.normalized() * HEAD


func _arm(side: int) -> Array:
	return [_sk.global_transform * _sk.get_bone_global_pose(_elbows[side]).origin, head(side)]


## Did a live hammer pass through them since the last tick?
func strike(player: Node3D) -> bool:
	var a := player.global_position + Vector3(0.0, BODY_LOW, 0.0)
	var b := player.global_position + Vector3(0.0, BODY_HIGH, 0.0)
	var hit := false
	for side in 2:
		if live != side and live != BOTH:
			continue
		var now := _arm(side)
		var was: Array = _before[side] if not (_before[side] as Array).is_empty() else now
		_before[side] = now
		for i in 5:
			var t := float(i) / 4.0
			var e: Vector3 = (was[0] as Vector3).lerp(now[0], t)
			var p: Vector3 = (was[1] as Vector3).lerp(now[1], t)
			var pts := Geometry3D.get_closest_points_between_segments(e, p, a, b)
			if (pts[0] as Vector3).distance_to(pts[1]) < _strike_radius():
				hit = true
	return hit


func clear_sweep() -> void:
	_before = [_arm(0), _arm(1)]


func drop() -> void:
	_dropped = true
	live = NONE
