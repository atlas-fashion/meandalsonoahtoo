extends Node3D

## Iron bars that drop out of an archway's crown to shut it, and draw back up
## into it when the way is clear. Same interface as `gate.gd` (`set_sealed`),
## so `Maze.seal_room` drives either without knowing which it has.
##
## The bars GROW down from the crown rather than sliding down from above it:
## a boss-room arch is 3.8 m tall under a 5.1 m roof that is open to the sky
## beside it, so bars stored above the crown would stand up through the roof.
## `gate.gd` sinks into the floor for the same reason.
##
## Built in code rather than as a scene because its size comes from the arch it
## fills, and that is measured, not authored.

@export var travel_time := 0.55
@export var width := 3.6
@export var height := 3.8
@export var bar_count := 7

var sealed := false
var _bars: Node3D
var _blocker: CollisionShape3D
var _tween: Tween


func _ready() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.086, 0.078, 0.075)
	iron.metallic = 0.8
	iron.roughness = 0.5

	# The pivot sits at the crown and the bars hang below it, so scaling this
	# node in Y makes them extend downward out of the stone.
	_bars = Node3D.new()
	_bars.name = "Bars"
	_bars.position.y = height
	add_child(_bars)

	var bar := BoxMesh.new()
	bar.size = Vector3(0.09, height, 0.09)
	bar.material = iron
	var pitch := width / float(bar_count + 1)
	for i in bar_count:
		_part(bar, Vector3(-width * 0.5 + pitch * float(i + 1), -height * 0.5, 0.0))
	var rail := BoxMesh.new()
	rail.size = Vector3(width, 0.1, 0.12)
	rail.material = iron
	for at in [0.25, 0.65]:
		_part(rail, Vector3(0.0, -height * at, 0.0))

	var body := StaticBody3D.new()
	body.name = "Blocker"
	# Layers 1 + 2, like `gate.tscn`: the player and every enemy collide with
	# layer 1, and 2 is the sight layer, so nothing aggroes through a shut gate.
	body.collision_layer = 3
	body.collision_mask = 0
	add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(width + 0.2, height, 0.5)
	_blocker = CollisionShape3D.new()
	_blocker.shape = box
	_blocker.position.y = height * 0.5
	_blocker.disabled = true
	body.add_child(_blocker)

	_bars.scale.y = 0.001
	_bars.visible = false


func _part(mesh: Mesh, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 45.0
	mi.visibility_range_end_margin = 6.0
	_bars.add_child(mi)


func set_sealed(shut: bool) -> void:
	if shut == sealed:
		return
	sealed = shut
	# Deferred: this is called from a frame callback, and toggling a shape
	# mid-step is not allowed.
	_blocker.set_deferred("disabled", not shut)

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_bars.visible = true
	_tween = create_tween()
	if shut:
		# Dropped: fast, with a heavy landing.
		_tween.tween_property(_bars, "scale:y", 1.0, travel_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		_tween.tween_property(_bars, "scale:y", 0.001, travel_time * 2.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_callback(func(): _bars.visible = false)
