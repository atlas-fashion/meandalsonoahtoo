class_name LockOnReticle
extends Control
## The marker drawn over the locked-on target (the timing-combat template, note 190).
## Positioned by LockOn each frame.

@export var color := Color(1.0, 0.85, 0.3, 0.95)
## Half the diamond's width, in pixels.
@export var radius := 14.0
@export var thickness := 2.5

var _point := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	hide()


func show_at(screen_point: Vector2) -> void:
	_point = screen_point
	show()
	queue_redraw()


func _draw() -> void:
	var r := radius
	var corners := PackedVector2Array([
		_point + Vector2(0, -r), _point + Vector2(r, 0),
		_point + Vector2(0, r), _point + Vector2(-r, 0), _point + Vector2(0, -r),
	])
	draw_polyline(corners, color, thickness, true)
	draw_circle(_point, 2.0, color)
