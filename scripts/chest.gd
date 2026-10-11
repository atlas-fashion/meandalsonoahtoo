extends Node3D

## A chest that opens when the player walks up to it and presses E (action
## "interact"), and hands over consumables. Like the old world pickups, it
## refuses to open if the player cannot actually carry the contents, so a full
## stack does not waste the chest.

signal opened(amount: int)

@export var consumable: ConsumableType = preload("res://resources/health_potion.tres")
@export var min_amount := 1
@export var max_amount := 3
@export var open_radius := 2.4
## Headline shown when it opens, above the count of what was inside.
@export var opened_title := "CHEST OPENED"
## A chest room's chest (dungeon_room.gd) also holds that room's shard, for the
## boss's door, and some coins.
@export var shard: StringName = &""
@export var coins := 0

@onready var lid_pivot: Node3D = $LidPivot

var opened_already := false
## Shut away (a prison hub's chest, behind a locked cell door: dungeon_room.gd):
## no prompt and no opening until it is set false.
var locked := false
var _near := false
var _player: Node3D = null
var _prompt: Interact.Prompt


func _ready() -> void:
	_prompt = Interact.prompt("E   Open", Vector3(0.0, 1.15, 0.0))
	add_child(_prompt)


func _process(_delta: float) -> void:
	if opened_already:
		return
	if locked:
		_near = false
		_prompt.visible = false
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or not _player.has_method("add_consumable"):
		return
	# Measure to the player's centre of mass, not the floor at their feet.
	# ...and the crosshair has to be on it.
	_near = global_position.distance_to(_player.global_position + Vector3(0, 0.9, 0)) <= open_radius \
		and Interact.looked_at(self)
	_prompt.visible = _near


func _unhandled_input(event: InputEvent) -> void:
	if _near and not opened_already and Interact.pressed(event):
		get_viewport().set_input_as_handled()
		_try_open(_player)


func _try_open(player: Node3D) -> void:
	var wanted := randi_range(min_amount, max_amount)
	var has_shard := shard != &""
	var inv = player.get("inventory")
	# The shard must fit, or the chest stays shut and keeps it.
	if has_shard and (inv == null or inv.room_for(shard) <= 0):
		_full()
		return
	# Granted quietly: the banner below says it far more clearly than the small
	# line at the bottom of the screen, and saying both says it twice.
	var given: int = player.add_consumable(consumable, wanted, false)
	if given <= 0 and not has_shard:
		# Inventory full -- leave it shut so it is still here later, and say so.
		_full()
		return

	if has_shard:
		inv.add(shard, 1)
		if coins > 0:
			player.add_currency(coins)
		var lines: Array[String] = [Inventory.item_name(shard)]
		if given > 0:
			lines.append("+%d %s%s" % [given, consumable.item_name.to_lower(), "" if given == 1 else "s"])
		if coins > 0:
			lines.append("+%d coins" % coins)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("announce"):
			hud.announce(opened_title, "    ".join(lines))
	else:
		_announce(given)
	opened_already = true
	_near = false
	_prompt.visible = false
	set_process(false)
	var tween := create_tween()
	tween.tween_property(lid_pivot, "rotation:x", deg_to_rad(-105.0), 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	opened.emit(given)


func _full() -> void:
	_prompt.text = "Full"
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(_prompt):
			_prompt.text = "E   Open")


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
