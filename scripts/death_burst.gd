extends Node3D

## A one-shot blast left behind by something dying.
##
## Spawned into the dying thing's *parent*, never as its child: the corpse frees
## itself a moment later and would take its own children down with it halfway
## through the animation.
##
## Everything is driven by tweens on per-instance material copies, so two things
## dying at once do not fight over one shared alpha.

## Both meshes are authored at 1 m across, so scale is the radius directly.
@export var radius := 2.4
@export var duration := 0.75
@export var colour := Color(1.0, 0.65, 0.30)
## Peak brightness of the flash, which then falls away over the same duration.
@export var light_energy := 9.0

@onready var core: MeshInstance3D = $Core
@onready var ring: MeshInstance3D = $Ring
@onready var flash: OmniLight3D = $Flash


func _ready() -> void:
	var core_material := _own_material(core)
	var ring_material := _own_material(ring)
	flash.light_color = colour
	flash.light_energy = light_energy
	flash.omni_range = radius * 3.0

	core.scale = Vector3.ONE * radius * 0.2
	# The ring starts as a point and outruns the core, which is what sells the
	# blast as having gone off rather than merely grown.
	ring.scale = Vector3(radius * 0.15, radius * 0.1, radius * 0.15)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(core, "scale", Vector3.ONE * radius, duration * 0.8) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "scale",
			Vector3(radius * 1.9, radius * 0.25, radius * 1.9), duration) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	if core_material != null:
		tween.tween_property(core_material, "albedo_color:a", 0.0, duration * 0.7) \
			.set_ease(Tween.EASE_IN)
	if ring_material != null:
		tween.tween_property(ring_material, "albedo_color:a", 0.0, duration) \
			.set_ease(Tween.EASE_IN)
	# The light dies fastest of all, so the room does not stay lit by a corpse.
	tween.tween_property(flash, "light_energy", 0.0, duration * 0.55) \
		.set_ease(Tween.EASE_IN)

	tween.chain().tween_callback(queue_free)


## A private copy tinted to `colour`, keeping its authored alpha.
func _own_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	var active := mesh.get_active_material(0)
	if not (active is StandardMaterial3D):
		return null
	var material := (active as StandardMaterial3D).duplicate() as StandardMaterial3D
	var alpha := material.albedo_color.a
	material.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	if material.emission_enabled:
		material.emission = colour
	mesh.material_override = material
	return material
