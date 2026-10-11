extends CanvasLayer

## A black screen wipe, used when the player steps through a zone gate.
##
## Deliberately self-contained: it owns its own ColorRect and never touches
## the level, so a transition can be played from anywhere without a scene
## being set up for it first.

signal faded_out
signal finished

## Drawn above the HUD. The one thing a transition must never do is let a
## health bar float over a black screen.
const LAYER := 128

@export var colour := Color(0.0, 0.0, 0.0, 1.0)
@export var fade_time := 0.55
## How long the screen stays black between the two halves. This is where a
## real scene load goes, so it is long enough to read as a deliberate cut
## rather than a dropped frame.
@export var hold_time := 0.45

var _rect: ColorRect
var _busy := false


func _ready() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.color = Color(colour.r, colour.g, colour.b, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A ColorRect defaults to MOUSE_FILTER_STOP, and a parent's filter does not
	# propagate. Left alone, an invisible full-screen rect swallows every click
	# in the game for the rest of the session.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)


func is_busy() -> bool:
	return _busy


## Fades to black, waits, then fades back. `during` runs while the screen is
## fully black, which is where the zone change belongs.
func play(during: Callable = Callable()) -> void:
	if _busy:
		return
	_busy = true
	_rect.visible = true

	var tween := create_tween()
	tween.tween_property(_rect, "color:a", 1.0, fade_time)
	await tween.finished
	faded_out.emit()

	if during.is_valid():
		during.call()
	await get_tree().create_timer(hold_time).timeout

	tween = create_tween()
	tween.tween_property(_rect, "color:a", 0.0, fade_time)
	await tween.finished
	_rect.visible = false
	_busy = false
	finished.emit()
