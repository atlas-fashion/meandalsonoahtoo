extends StaticBody3D

## The glowing orb that surfaces on a boss whose stance has been broken.
##
## It is its own body on the "damageable" layer so the sword's existing shape
## query finds it, but it deliberately has neither `take_damage` nor
## `apply_knockback`. That matters: every untargeted attack in the game -- the
## dash, the jump slam, a door kicked in -- checks for exactly those two methods
## and so skips the orb entirely. Only a deliberate, aimed sword swing can cash
## it in, via `aim_tolerance` and `strike` below.
##
## Hidden and non-collidable unless the owner exposes it, so it can never be hit
## through the boss's armour. Hiding it also switches off its light.

## How far off centre the player may be looking and still connect, in degrees.
## Tested against the swing's forward vector without the usual allowance for the
## target's width, so this really is "put it near your crosshair". The sword's
## own sweep spans the whole field of view, which would otherwise mean any swing
## in the boss's direction landed the strike for free.
@export var aim_degrees := 17.0

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var shape: CollisionShape3D = $CollisionShape3D

var _host: Node = null
var _material: StandardMaterial3D
var _pulse: Tween


func _ready() -> void:
	_host = get_parent()
	var active := mesh.get_active_material(0)
	if active is StandardMaterial3D:
		_material = (active as StandardMaterial3D).duplicate()
		mesh.material_override = _material
	set_exposed(false)


func set_exposed(open: bool) -> void:
	visible = open
	# Deferred: this gets flipped from inside the attacker's shape query, and
	# the physics server will not take a shape change while it is being queried.
	shape.set_deferred(&"disabled", not open)

	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	if not open:
		return
	scale = Vector3.ONE * 0.2
	var grow := create_tween()
	grow.tween_property(self, "scale", Vector3.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _material == null:
		return
	# A hard, fast throb -- it has four seconds to catch the eye.
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_material, "emission_energy_multiplier", 11.0, 0.28)
	_pulse.tween_property(_material, "emission_energy_multiplier", 4.0, 0.28)


## The swing must land within this many radians of the orb to count.
func aim_tolerance() -> float:
	return deg_to_rad(aim_degrees)


## A clean hit. Returns the damage actually dealt.
func strike(from_direction: Vector3 = Vector3.ZERO) -> float:
	if _host == null or not is_instance_valid(_host):
		return 0.0
	if not _host.has_method("strike_weak_point"):
		return 0.0
	return _host.strike_weak_point(from_direction)
