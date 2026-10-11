extends Area3D

## A locked doorway at a dead end on the rim of the maze, leading to a zone
## that does not exist yet.
##
## The intended shape of the feature is: beat the boss, the gate unlocks, walk
## into it, the screen cuts to black and you come back somewhere else. Only
## the last part -- the other somewhere -- is missing, so this plays the whole
## transition and returns the player where they stood, with the scene swap
## marked as the one open TODO. That way the trigger volume, the fade timing,
## the locked state and the prompt are all real and tested now, rather than
## being written blind later against a transition nobody has seen run.

signal entered(gate: Node3D)
signal refused(gate: Node3D)

## Identifies which zone this doorway leads to. Set per gate by the placer.
@export var zone_name := ""
## Where the zone lives, once it exists. Empty means the TODO below is hit.
@export var zone_scene: PackedScene = null
## Gates start shut. The boss unlocking them is gameplay that lives elsewhere;
## this only needs to know which state it is in.
@export var locked := true

var _fade: CanvasLayer
var _inside := false


func setup(fade: CanvasLayer, name_of_zone: String, extents: Vector3) -> void:
	_fade = fade
	zone_name = name_of_zone
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = extents
	shape.shape = box
	shape.position = Vector3(0.0, extents.y * 0.5, 0.0)
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func unlock() -> void:
	locked = false


func _on_body_entered(body: Node3D) -> void:
	if _inside or not body.is_in_group("player"):
		return
	_inside = true
	if locked:
		refused.emit(self)
		return
	if _fade == null or (_fade.has_method("is_busy") and _fade.is_busy()):
		return
	entered.emit(self)
	_fade.play(_travel)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_inside = false


## Runs while the screen is fully black.
func _travel() -> void:
	if zone_scene == null:
		# TODO: the zones behind these doors are not built yet. When one is,
		# this is the whole change: swap the scene here, while the screen is
		# black, and the fade back in belongs to the new level. Everything
		# else about the transition -- trigger, lock, timing -- already works.
		push_warning("zone_gate: '%s' has no zone_scene yet; staying put" % zone_name)
		return
	get_tree().change_scene_to_packed(zone_scene)
