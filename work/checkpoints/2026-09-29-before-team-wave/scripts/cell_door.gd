extends Node3D

## The barred front of a jail cell. Rises like a portcullis when opened and
## stays up.
##
## Built with its collision switched off, like the room gates: the navmesh is
## baked before these come down, so the cell interiors are on the mesh and
## whatever is inside can walk out once the bars lift.

signal opened

## How far the bars travel upward. A little more than the cell is tall, so they
## disappear into the lintel rather than stopping in view.
@export var lift := 3.2
@export var open_time := 0.9
## Staggered per door by whoever opens a batch, so ten cells do not move as one
## mechanism.
@export var open_delay := 0.0

@onready var bars: Node3D = $Bars
@onready var blocker: CollisionShape3D = $Blocker/CollisionShape3D

var is_open := false

var _rest := Vector3.ZERO
var _tween: Tween


func _ready() -> void:
	_rest = bars.position
	# Shut, but not solid yet: the navmesh bake has to see straight through.
	blocker.disabled = true


## Called once the bake is done, to make the bars mean something.
func make_solid() -> void:
	if not is_open:
		blocker.set_deferred(&"disabled", false)


func open() -> void:
	if is_open:
		return
	is_open = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	if open_delay > 0.0:
		_tween.tween_interval(open_delay)
	# Collision goes first, so the occupant is free the moment it starts moving
	# rather than waiting for the bars to finish travelling.
	_tween.tween_callback(func() -> void: blocker.set_deferred(&"disabled", true))
	_tween.tween_property(bars, "position", _rest + Vector3(0, lift, 0), open_time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func() -> void: opened.emit())
