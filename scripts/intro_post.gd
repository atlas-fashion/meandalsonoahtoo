extends StaticBody3D

## A training post in the ruins (note 131): a weathered trunk sunk in the ground
## with a crossbar, wrapped in rope. STAND-IN (bark cylinders, made in code).
## Solid to the player and on the damageable layer, so every weapon's blow finds
## it (`take_damage`); it rocks with each hit and counts them by the weapon that
## was in hand (`hits`), which the lessons read.

const Flora := preload("res://scripts/intro_flora.gd")

## Blows taken, by weapon (&"sword", &"spear", &"axe"), and in all.
var hits := {}
var total := 0
var _pivot: Node3D
var _rock := Vector2.ZERO
var _rock_v := Vector2.ZERO


func _ready() -> void:
	collision_layer = 1 | 4 | 256
	collision_mask = 0
	_pivot = Node3D.new()
	add_child(_pivot)
	var bark := Flora.bark_material()
	var trunk := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.17
	c.bottom_radius = 0.21
	c.height = 2.1
	trunk.mesh = c
	trunk.material_override = bark
	trunk.position.y = 1.05
	_pivot.add_child(trunk)
	var bar := MeshInstance3D.new()
	var b := CylinderMesh.new()
	b.top_radius = 0.08
	b.bottom_radius = 0.09
	b.height = 1.3
	bar.mesh = b
	bar.material_override = bark
	bar.rotation.z = PI * 0.5
	bar.position.y = 1.45
	_pivot.add_child(bar)
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.5, 0.42, 0.28)
	rope.roughness = 1.0
	for y: float in [0.75, 1.05, 1.75]:
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.17
		t.outer_radius = 0.23
		ring.mesh = t
		ring.material_override = rope
		ring.position.y = y
		_pivot.add_child(ring)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 2.2
	cs.shape = cap
	cs.position.y = 1.1
	add_child(cs)


func take_damage(_amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
	var p := Coop.nearest(global_position)
	var held: StringName = p.call("held_item") if p != null and p.has_method("held_item") else &""
	hits[held] = int(hits.get(held, 0)) + 1
	total += 1
	var d := from_direction
	if d.length_squared() < 0.0001 and p != null:
		d = global_position - (p as Node3D).global_position
	d.y = 0.0
	d = global_basis.inverse() * d.normalized() if d.length_squared() > 0.0001 else Vector3.ZERO
	_rock_v += Vector2(d.z, -d.x) * 2.2


func apply_knockback(impulse: Vector3, _stun := 0.0) -> void:
	var d := global_basis.inverse() * impulse.normalized()
	_rock_v += Vector2(d.z, -d.x) * 1.5


func _process(delta: float) -> void:
	# A spring back upright.
	_rock_v += -_rock * 60.0 * delta - _rock_v * 6.0 * delta
	_rock += _rock_v * delta
	_pivot.rotation = Vector3(_rock.x * 0.12, 0.0, _rock.y * 0.12)
