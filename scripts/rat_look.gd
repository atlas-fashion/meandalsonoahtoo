extends Node3D

## The live rat's look (2026-10-18): the user's Tripo rat, rigged and animated
## by tools/build_rat.py (models/rat.glb). Used by the wild / thrown rat
## (rat.gd) and the one held by its tail in the player's hand
## (rat_control.gd). The robot rat keeps its own procedural look
## (rat_model.gd).
##
## The glb stands nose along +X, about 1 m nose to tail tip; here it is scaled
## by SCALE and turned so the nose faces -Z, origin on the floor under it.
## Clips (all looped): Run (one gallop stride, RUN_STRIDE game metres in
## RUN_LENGTH s at 1x), Idle (sniffing on all fours), Rear (up on its haunches),
## Dangle (hung by the tail, writhing). TailTip is a bone at the very end of
## the tail: `tail_tip()` is where it is now, for hanging the rat by it.

const SCENE := preload("res://models/rat.glb")
const SCALE := 0.5
## tools/build_rat.py RUN_STRIDE (0.8 source metres) x SCALE, and its 10 frames
## at 30 fps.
const RUN_STRIDE := 0.4
const RUN_LENGTH := 10.0 / 30.0
## The gait never plays faster than this: above it the legs only strobe.
const RUN_MAX_RATE := 3.5
const CLIPS: Array[StringName] = [&"Run", &"Idle", &"Rear", &"Dangle"]

var anim: AnimationPlayer
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var clip := &""
var _tip := -1


func _ready() -> void:
	name = "RatLook"
	var body: Node3D = SCENE.instantiate()
	body.scale = Vector3.ONE * SCALE
	body.rotation.y = PI * 0.5
	add_child(body)
	anim = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = body.find_child("Skeleton3D", true, false) as Skeleton3D
	for m in body.find_children("*", "MeshInstance3D", true, false):
		mesh = m as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if skeleton != null:
		_tip = skeleton.find_bone("TailTip")
	if anim != null:
		for c in CLIPS:
			if anim.has_animation(c):
				anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR


## Not drawn beyond `metres`.
func set_draw_range(metres: float) -> void:
	if mesh != null:
		mesh.visibility_range_end = metres
		mesh.visibility_range_end_margin = 2.0


## Plays `name` at `rate`, blending from what was on over `blend` s; a fresh
## start lands at a random point, so rats side by side are not in step.
func play(name_: StringName, rate := 1.0, blend := 0.15) -> void:
	if anim == null:
		return
	if clip != name_:
		var fresh := clip == &""
		clip = name_
		anim.play(name_, blend)
		if fresh:
			anim.seek(randf() * anim.current_animation_length, true)
	anim.speed_scale = rate


## The gallop at the rate that matches `ground_speed` m/s, capped.
func run(ground_speed: float) -> void:
	play(&"Run", clampf(ground_speed / (RUN_STRIDE / RUN_LENGTH), 0.6, RUN_MAX_RATE), 0.1)


## Stops (asleep) or carries on.
func set_running(on: bool) -> void:
	if anim == null:
		return
	if on and not anim.is_playing() and clip != &"":
		anim.play(clip)
	elif not on and anim.is_playing():
		anim.pause()


## Where the tip of its tail is now, in the world.
func tail_tip() -> Vector3:
	if skeleton == null or _tip < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(_tip).origin
