extends CharacterBody3D

## A fast orange flyer that closes on the player and detonates. It never deals
## contact damage -- the only threat is the explosion, and it telegraphs that by
## blinking for the whole fuse. Kill it during the blink and nothing happens.
##
## Deliberately fragile, so the blink is a real window rather than a formality.

signal died
signal fuse_started
signal detonated

@export var max_health := 10.0

@export_group("Flight")
@export var move_speed := 13.0
@export var acceleration := 30.0
## How far above the player's feet it tries to sit.
@export var hover_height := 1.5
@export var bob_amount := 0.18
@export var bob_speed := 3.4
@export var aggro_range := 32.0

@export_group("Performance")
## Past this distance from the player the bomber stops simulating altogether.
## Must stay comfortably above aggro_range or it would doze off mid-chase.
@export var dormant_range := 50.0
## How often a dormant bomber checks whether the player has come closer.
@export var dormant_poll := 0.4

@export_group("Fuse")
## Gap at which it latches on and lights the fuse, edge to edge.
@export var trigger_range := 0.9
@export var fuse_time := 3.0
## Once lit it latches on and follows, so backing away no longer saves you --
## killing it does. Fast enough to keep up with a run, not with a dodge.
@export var stick_speed := 14.0
@export var explosion_damage := 50.0
@export var explosion_radius := 3.5
## The blast only reaches a player on roughly the same level as the bomber.
@export var max_height_difference := 1.5
## Blinks per second at the start of the fuse and at the very end.
@export var blink_rate_start := 3.0
@export var blink_rate_end := 16.0
## Brightness of the flash at the moment of detonation.
@export var blast_light_energy := 9.0

@export_group("Colours")
@export var base_color := Color(1.0, 0.443137, 0.109804)
@export var blink_color := Color(1.0, 0.945098, 0.784314)
@export var base_glow := 1.1
@export var blink_glow := 4.5

@export_group("Navigation")
@export var repath_interval := 0.2

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var shape: CollisionShape3D = $CollisionShape3D
@onready var light: OmniLight3D = $Light
## Pre-authored so its transparent shader is compiled at load rather than
## stalling the frame something explodes.
@onready var blast: MeshInstance3D = $Blast
@onready var agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

var health := 0.0
var fusing := false

var _material: StandardMaterial3D
var _blast_material: StandardMaterial3D
var _dying := false
var _fuse_left := 0.0
var _blink_phase := 0.0
var _bob := 0.0
var _next_repath := 0.0
## Cached rather than looked up every frame.
var _player: Node3D = null
var _body_radius := 0.45
var _target_radius := -1.0
var _flash_tween: Tween
## Asleep: too far from the player to be worth simulating.
var _dormant := false
var _next_dormant_check := 0.0


func _ready() -> void:
	health = max_health
	_bob = randf() * TAU
	var active := mesh.get_active_material(0)
	if active is StandardMaterial3D:
		_material = (active as StandardMaterial3D).duplicate()
		mesh.material_override = _material
	var collider := shape.shape
	if collider is SphereShape3D:
		_body_radius = (collider as SphereShape3D).radius
	_blast_material = blast.get_active_material(0) as StandardMaterial3D
	if _blast_material != null:
		_blast_material = _blast_material.duplicate()
		blast.material_override = _blast_material
		_blast_material.albedo_color.a = 0.0
	blast.scale = Vector3.ONE * 0.01
	_paint(base_color, base_glow)


func _physics_process(delta: float) -> void:
	if _dying:
		return

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var player := _player
	if player == null:
		return

	# Dormancy: with dozens of these hovering around the map, simulating the
	# ones nobody can see is the bulk of the physics budget. A sleeping bomber
	# costs one distance check every dormant_poll seconds. Never sleeps once the
	# fuse is lit, so a primed one always gets to go off.
	if not fusing and _update_dormancy():
		return

	if _target_radius < 0.0:
		_target_radius = _player_radius(player)

	_bob += delta * bob_speed
	var to_player := player.global_position - global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	var gap := flat.length() - _body_radius - _target_radius

	if fusing:
		# Latched on: ride the player rather than hovering where it caught them.
		# Collision keeps it just outside their capsule, so it reads as stuck to
		# them.
		var attach := player.global_position + Vector3(0, hover_height, 0) - global_position
		if attach.length() > 0.05:
			velocity = attach.normalized() * stick_speed
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		_tick_fuse(delta, player)
		return

	if flat.length() > aggro_range:
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
		move_and_slide()
		return

	if gap <= trigger_range:
		_light_fuse()
		return

	# Route around walls when a navmesh is available; the path is flat, so the
	# height is steered separately.
	#
	# The agent's waypoint distances must exceed hover_height, or a flyer never
	# gets close enough to a floor-level waypoint to advance past it and just
	# jitters in place on the first one.
	var heading := flat.normalized()
	if agent != null:
		var now := Time.get_ticks_msec() / 1000.0
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = player.global_position
		if not agent.is_navigation_finished():
			var step := agent.get_next_path_position() - global_position
			step.y = 0.0
			# Ignore a waypoint we are already on top of; its direction is noise.
			if step.length() > 0.5:
				heading = step.normalized()

	var wanted_height := player.global_position.y + hover_height + sin(_bob) * bob_amount
	var climb := clampf(wanted_height - global_position.y, -1.0, 1.0)

	var desired := heading * move_speed
	desired.y = climb * move_speed * 0.8
	velocity = velocity.move_toward(desired, acceleration * delta)
	if flat.length_squared() > 0.001:
		rotation.y = atan2(-heading.x, -heading.z)
	move_and_slide()


## True when this frame's simulation should be skipped entirely.
func _update_dormancy() -> bool:
	if dormant_range <= 0.0 or _player == null:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_dormant_check:
		return _dormant
	_next_dormant_check = now + dormant_poll

	_dormant = global_position.distance_squared_to(_player.global_position) \
		> dormant_range * dormant_range
	if _dormant:
		velocity = Vector3.ZERO
	return _dormant


func _light_fuse() -> void:
	fusing = true
	_fuse_left = fuse_time
	_blink_phase = 0.0
	fuse_started.emit()


func _tick_fuse(delta: float, player: Node3D) -> void:
	_fuse_left -= delta
	# The blink speeds up as it runs out, so the urgency reads without a number.
	var progress := clampf(1.0 - _fuse_left / fuse_time, 0.0, 1.0)
	_blink_phase += delta * lerpf(blink_rate_start, blink_rate_end, progress)
	var lit := fmod(_blink_phase, 1.0) < 0.5
	_paint(blink_color if lit else base_color, blink_glow if lit else base_glow)

	if _fuse_left <= 0.0:
		_detonate(player)


func _detonate(player: Node3D) -> void:
	# Only the player is hurt: everything else here shares its collision layers
	# and a blast that killed the whole pack would read as a bug.
	if player.has_method("take_damage"):
		var separation := global_position.distance_to(player.global_position + Vector3(0, 0.9, 0))
		# It hovers a fixed amount above whoever it is chasing, so its own
		# height minus that offset is the floor it is fighting on. If the player
		# has climbed away from it, the blast does not reach.
		var own_level := global_position.y - hover_height
		var level_gap: float = absf(own_level - player.global_position.y)
		if separation <= explosion_radius and level_gap <= max_height_difference:
			player.take_damage(explosion_damage, global_position.direction_to(player.global_position))
	detonated.emit()
	_play_blast()


## The body vanishes and a fireball takes its place, swelling to the blast
## radius and fading out. Only then is the node freed.
func _play_blast() -> void:
	_dying = true
	shape.disabled = true
	set_physics_process(false)
	mesh.visible = false
	# Hidden in the scene rather than merely scaled down to nothing: a shrunken
	# mesh is still submitted every frame, and with dozens of these hovering
	# around the map that was a sphere's worth of geometry each, for nothing.
	blast.visible = true

	var tween := create_tween().set_parallel(true)
	if _blast_material != null:
		_blast_material.albedo_color.a = 0.9
		tween.tween_property(_blast_material, "albedo_color:a", 0.0, 0.45) \
			.set_ease(Tween.EASE_IN)
	blast.scale = Vector3.ONE * 0.15
	tween.tween_property(blast, "scale", Vector3.ONE * explosion_radius, 0.4) \
		.set_ease(Tween.EASE_OUT)
	# A hard flash of light that dies with the fireball.
	light.light_color = blink_color
	light.light_energy = blast_light_energy
	light.omni_range = explosion_radius * 2.0
	tween.tween_property(light, "light_energy", 0.0, 0.45)

	tween.chain().tween_callback(queue_free)
	died.emit()


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	if _dying:
		return
	health = maxf(health - amount, 0.0)
	_flash()
	if health <= 0.0:
		# Killed before the fuse ran out, so no explosion.
		_die()


## Shoved like any other enemy, which also buys time by pushing it out of range.
func apply_knockback(impulse: Vector3, _stun_time := 0.25) -> void:
	if _dying:
		return
	velocity.x += impulse.x
	velocity.z += impulse.z


func _flash() -> void:
	if _material == null or fusing:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_material.albedo_color = Color(1.0, 0.98, 0.94)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "albedo_color", base_color, 0.15)


func _paint(colour: Color, glow: float) -> void:
	if _material != null:
		_material.albedo_color = colour
		if _material.emission_enabled:
			_material.emission = colour
			_material.emission_energy_multiplier = glow
	light.light_color = colour
	light.light_energy = glow


func _die() -> void:
	_dying = true
	died.emit()
	shape.disabled = true
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.2).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _player_radius(player: Node) -> float:
	var collider := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider != null and collider.shape is CapsuleShape3D:
		return (collider.shape as CapsuleShape3D).radius
	return 0.4
