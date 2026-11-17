class_name Knockback
extends Node
## Knockback for any body (the timing-combat template, note 190). A hit shoves the body
## along the direction the blow was travelling, and it slides to a stop. How hard a
## weapon's hit pushes is set on the weapon: its base Knockback × the swing's Knockback
## Multiplier. This node decides how much of that the body takes and how quickly the
## slide dies out.
##
## The body calls step(delta) once per physics frame and adds the result to its velocity
## (player.gd adds it for the move and takes it back off after, so the walk is untouched).

## How much of a hit's knockback this body takes. 1 = normal; 0.5 = heavy, slides half as
## far; 0 = immovable.
@export_range(0.0, 3.0, 0.05) var taken := 1.0
## How quickly the slide dies out. Distance slid ≈ knockback × taken / recovery.
@export_range(0.5, 30.0, 0.5) var recovery := 8.0

## Current slide velocity (horizontal, metres per second).
var velocity := Vector3.ZERO


## Shoves the body with the knockback of the strike `weapon` is landing right now (read
## during take_hit), scaled by `scale` (e.g. less when blocked).
func from_hit(weapon: Weapon, owner_body: Node3D, scale := 1.0) -> void:
	if weapon == null:
		return
	push(hit_direction(weapon, owner_body) * weapon.last_hit_knockback * scale)


## Shoves the body along `direction` (flattened) at `speed` m/s × `scale`: a blow from
## something that is not a Weapon (this game's enemies hit with `take_damage`).
func from_direction(direction: Vector3, speed: float, scale := 1.0) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	push(direction.normalized() * speed * scale)


## Shoves the body with this velocity (metres per second), scaled by `taken`.
func push(push_velocity: Vector3) -> void:
	velocity += Vector3(push_velocity.x, 0.0, push_velocity.z) * taken


func clear() -> void:
	velocity = Vector3.ZERO


## Eases the slide out over delta seconds and returns the velocity to add this frame.
func step(delta: float) -> Vector3:
	velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-recovery * delta))
	if velocity.length_squared() < 0.0001:
		velocity = Vector3.ZERO
	return velocity


## Horizontal direction a strike pushes `owner_body`: the way the blade was travelling. For
## a strike that moved almost straight up or down, away from the weapon.
static func hit_direction(weapon: Weapon, owner_body: Node3D) -> Vector3:
	var direction := weapon.last_hit_direction
	direction.y = 0.0
	if direction.length() > 0.2:
		return direction.normalized()
	var away := owner_body.global_position - weapon.global_position
	away.y = 0.0
	return away.normalized()
