class_name ConsumableType
extends Resource

## Defines one kind of healing pickup. Stored as .tres files under
## res://resources/ so new consumables can be added without touching code.

@export var item_name := "Consumable"
@export var heal_amount := 25.0
## Tints the pickup's mesh and its glow.
@export var color := Color.WHITE
## Relative likelihood when an enemy rolls a drop. Higher is more common; the
## values are weights, not percentages, so they need not sum to anything.
@export var drop_weight := 1.0
