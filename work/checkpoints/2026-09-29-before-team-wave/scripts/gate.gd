extends Node3D

## A bar gate that rises out of the floor to seal a doorway while something in
## the room is awake, and sinks back out of sight when it is dealt with.
##
## It sinks rather than lifting so it never pokes through the ceiling of a
## corridor or above a wall into an open room's sky.

@export var travel_time := 0.7
## How far below the floor the bars hide when the way is clear.
@export var sunk_depth := 5.4

@onready var bars: Node3D = $Bars
@onready var blocker: CollisionShape3D = $Blocker/CollisionShape3D

var sealed := false
var _tween: Tween


func _ready() -> void:
	bars.position.y = -sunk_depth
	blocker.disabled = true


func set_sealed(shut: bool) -> void:
	if shut == sealed:
		return
	sealed = shut
	# Deferred: this is called from a frame callback, and toggling a shape
	# mid-step is not allowed.
	blocker.set_deferred("disabled", not shut)

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(bars, "position:y", 0.0 if shut else -sunk_depth, travel_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
