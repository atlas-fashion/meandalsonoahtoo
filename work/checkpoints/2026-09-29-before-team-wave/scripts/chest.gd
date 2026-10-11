extends Node3D

## A chest that opens when the player walks up to it and hands over consumables.
## Like the old world pickups, it refuses to open if the player cannot actually
## carry the contents, so a full stack does not waste the chest.

signal opened(amount: int)

@export var consumable: ConsumableType = preload("res://resources/health_potion.tres")
@export var min_amount := 1
@export var max_amount := 3
@export var open_radius := 2.4
## Headline shown when it opens, above the count of what was inside.
@export var opened_title := "CHEST OPENED"

@onready var lid_pivot: Node3D = $LidPivot

var opened_already := false


func _process(_delta: float) -> void:
	if opened_already:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not player.has_method("add_consumable"):
		return
	# Measure to the player's centre of mass, not the floor at their feet.
	if global_position.distance_to(player.global_position + Vector3(0, 0.9, 0)) <= open_radius:
		_try_open(player)


func _try_open(player: Node3D) -> void:
	var wanted := randi_range(min_amount, max_amount)
	# Granted quietly: the banner below says it far more clearly than the small
	# line at the bottom of the screen, and saying both says it twice.
	var given: int = player.add_consumable(consumable, wanted, false)
	if given <= 0:
		# Inventory full -- leave it shut so it is still here later.
		return

	_announce(given)
	opened_already = true
	set_process(false)
	var tween := create_tween()
	tween.tween_property(lid_pivot, "rotation:x", deg_to_rad(-105.0), 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	opened.emit(given)


## The same headline treatment a felled mimic gets, since opening a chest is
## the other moment the player is handed a pile of something.
func _announce(amount: int) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("announce") or consumable == null:
		return
	var noun := consumable.item_name.to_lower()
	if amount != 1:
		noun += "s"
	hud.announce(opened_title, "+%d %s" % [amount, noun])
