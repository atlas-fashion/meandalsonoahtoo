extends CharacterBody3D

## A chest that is not a chest. It sits on its pedestal looking exactly like the
## others until someone climbs up to open it, then bucks them off and comes down
## after them.
##
## Slow on its feet with exactly one attack: a long jump that hurts everything
## around where it lands. The landing spot is drawn on the ground for the whole
## time it is airborne, so the attack is dodged by reading it, not by reacting.

signal died

enum State { DORMANT, WAKING, CHASE, CROUCH, AIRBORNE, RECOVER }

@export var max_health := 750.0
## Handed over when it dies, in place of the chest it was pretending to be.
@export var reward: ConsumableType = preload("res://resources/health_potion.tres")
@export var reward_amount := 5
## In a puzzle room it is the room's reward, and the room's shard is in it.
@export var shard: StringName = &""

@export_group("Waking")
## How close the player must get before it springs. Measured to the lid, so it
## triggers when they have actually climbed up to open it.
@export var wake_radius := 2.6
## Vertical window for the same test, so walking past underneath is safe.
## Measured from the chest's own base: the player has to be up at its level or
## above it, which means they climbed the pedestal.
@export var wake_height := 2.0
@export var wake_floor := -0.4
@export var wake_time := 0.55
## Thrown off the pedestal: outward shove plus a bit of lift.
@export var knock_back_speed := 11.0
@export var knock_up_speed := 6.0

@export_group("Movement")
## Deliberately ponderous -- it is a heavy box with legs.
@export var move_speed := 2.6
@export var acceleration := 9.0
@export var aggro_range := 45.0
@export var repath_interval := 0.25

@export_group("Jump attack")
## Gap at which it will commit to a leap, edge to edge.
@export var jump_trigger_range := 16.0
@export var jump_cooldown := 3.2
## Crouch before the leap: the wind-up you get to read.
@export var crouch_time := 0.7
## How high the arc peaks. The flight time falls out of this, so the marker is
## always placed for exactly as long as the leap takes.
@export var jump_peak_height := 11.0
@export var jump_damage := 70.0
@export var jump_radius := 4.5
## A hit throws the player a long way back but only a little up: the lift is
## kept low so a hit cannot loft anyone onto the top of a maze wall.
@export var jump_knockback := 19.0
@export var jump_knock_up := 3.0
@export var landing_shake := 0.35
## Fraction of the flight that passes before the ring appears. The landing spot
## is chosen from where the player is AT THAT MOMENT, and the rest of the leap
## is re-aimed at it -- so running early does nothing, and the ring is a read
## of where it is actually coming down.
@export_range(0.0, 0.95) var marker_delay := 0.76

@export_group("Jaw")
## Where the lid sits between bites once it is awake.
@export var jaw_rest_degrees := -34.0
## It snaps at the air on the way in, on this interval.
@export var chomp_interval := 2.4
## Layers the landing check rays against: world and level geometry.
@export_flags_3d_physics var landing_mask := 3
## Height of the arena floor. It only ever lands here, never on a pedestal, a
## pillar or a stepping block -- the fight stays on the ground.
@export var arena_floor_y := 0.0
## How far the ground under a candidate spot may differ from the arena floor
## before it counts as raised and gets rejected.
@export var landing_tolerance := 0.8

@onready var body: MeshInstance3D = $Body/MeshInstance3D
@onready var lid_pivot: Node3D = $LidPivot
@onready var shape: CollisionShape3D = $CollisionShape3D
@onready var marker: MeshInstance3D = $LandingMarker
@onready var impact: MeshInstance3D = $ImpactRing
@onready var agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

var health := 0.0
var state := State.DORMANT
var awake := false
## What the HUD shows above the bar.
@export var display_name := "THE MIMIC"

@export_group("Death")
@export var death_burst: PackedScene = preload("res://scenes/death_burst.tscn")
@export var burst_radius := 2.6
@export var burst_color := Color(1.0, 0.647059, 0.301961)
## True once it has sprung and is hunting, which is when the bar appears.
var engaged := false

var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _dying := false
var _state_until := 0.0
var _next_jump := 0.0
var _landing := Vector3.ZERO
var _next_repath := 0.0
var _body_radius := 0.9
var _target_radius := -1.0
var _marker_material: StandardMaterial3D
var _impact_material: StandardMaterial3D
var _impact_tween: Tween
var _chomp_tween: Tween
var _next_chomp := 0.0
var _flight_time := 1.0
## The pending ring reveal for the current leap, killed if another leap starts.
var _reveal_tween: Tween
## Set once the ring is up. It may not touch down before this: with the ring
## shown late, an early touchdown would slam without ever showing it.
var _revealed := false
var _flash_tween: Tween
## Cached instead of looked up every frame by every enemy in the level.
var _player: Node3D = null
var _near_player := false
var _prompt: Interact.Prompt


func _ready() -> void:
	health = max_health
	# The chests' own prompt, at a chest's height, so nothing gives it away.
	_prompt = Interact.prompt("E   Open", Vector3(0.0, 1.15, 0.0))
	add_child(_prompt)
	# Its own copies, so flashing it does not flash the real chests.
	for node in [body, $LidPivot/MeshInstance3D]:
		var active := (node as MeshInstance3D).get_active_material(0)
		if active is StandardMaterial3D:
			var copy := (active as StandardMaterial3D).duplicate()
			(node as MeshInstance3D).material_override = copy
			_materials.append(copy)
			_base_colors.append(copy.albedo_color)
	var collider := shape.shape
	if collider is BoxShape3D:
		_body_radius = (collider as BoxShape3D).size.x * 0.5

	_marker_material = marker.get_active_material(0) as StandardMaterial3D
	if _marker_material != null:
		_marker_material = _marker_material.duplicate()
		marker.material_override = _marker_material
	marker.visible = false
	marker.top_level = true
	marker.scale = Vector3(jump_radius, 1.0, jump_radius)

	_impact_material = impact.get_active_material(0) as StandardMaterial3D
	if _impact_material != null:
		_impact_material = _impact_material.duplicate()
		impact.material_override = _impact_material
		_impact_material.albedo_color.a = 0.0
	impact.top_level = true
	impact.visible = false
	preload("res://scripts/enemy_health_bar.gd").attach(self)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var player := _player
	if player == null:
		move_and_slide()
		return
	if _target_radius < 0.0:
		_target_radius = _player_radius(player)

	var now := _now()
	var to_player := player.global_position - global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	var gap := flat.length() - _body_radius - _target_radius

	match state:
		State.DORMANT:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			# Up on the pedestal with it, it offers to be opened exactly as a real
			# chest does -- the same prompt, the same key -- and springs when the
			# player takes it up on that. The lower bound matters as much as the
			# upper one: without it, a player walking past below could open it.
			# And, as for a chest, only with the crosshair on it.
			_near_player = flat.length() <= wake_radius \
					and to_player.y >= wake_floor and to_player.y <= wake_height \
					and Interact.looked_at(self, 3.4, 0.1, [$Body, $LidPivot])
			_prompt.visible = _near_player
			return

		State.WAKING:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			if now >= _state_until:
				state = State.CHASE
			return

		State.CROUCH:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			_face(flat)
			move_and_slide()
			if now >= _state_until:
				_launch(player)
			return

		State.AIRBORNE:
			move_and_slide()
			# Landing counts as touching down after the arc has had time to rise.
			if now >= _state_until or (_revealed and is_on_floor() and now >= _state_until - _flight_time * 0.5):
				_land(player)
			return

		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			_face(flat)
			move_and_slide()
			if now >= _state_until:
				state = State.CHASE
			return

	# --- CHASE ---
	if flat.length() > aggro_range:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	var heading := flat.normalized()
	if agent != null:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = player.global_position
		if not agent.is_navigation_finished():
			var step := agent.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.4:
				heading = step.normalized()

	_face(heading)
	velocity.x = move_toward(velocity.x, heading.x * move_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, heading.z * move_speed, acceleration * delta)
	move_and_slide()

	if now >= _next_chomp:
		_next_chomp = now + chomp_interval
		_chomp(1)

	if gap <= jump_trigger_range and now >= _next_jump and is_on_floor():
		_crouch()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.DORMANT and _near_player and _player != null and Interact.pressed(event):
		get_viewport().set_input_as_handled()
		_wake(_player)


func _wake(player: Node3D) -> void:
	_near_player = false
	_prompt.visible = false
	awake = true
	engaged = true
	state = State.WAKING
	_state_until = _now() + wake_time
	# Throw whoever is stood on it clear of the pedestal.
	if player.has_method("apply_knockback"):
		var away := player.global_position - global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = -global_basis.z
		player.apply_knockback(away.normalized() * knock_back_speed + Vector3(0, knock_up_speed, 0))

	# Snaps its jaws as it comes alive.
	_chomp(3, -118.0, 0.11)


func _crouch() -> void:
	state = State.CROUCH
	_state_until = _now() + crouch_time
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.18, 0.7, 1.18), crouch_time * 0.8) \
		.set_ease(Tween.EASE_OUT)


## Ballistic arc onto a chosen spot, timed so the landing is exactly when the
## arc comes back down -- which is what makes the marker honest.
func _launch(player: Node3D) -> void:
	state = State.AIRBORNE

	var gravity := get_gravity().length()
	var rise := sqrt(2.0 * gravity * jump_peak_height)
	_landing = _choose_landing(player)

	# Solve for when the arc actually reaches the target height. Assuming it
	# comes back to its launch height would cut the jump short by however far it
	# is dropping -- which, leaping down off its own pedestal, is a long way.
	var drop := _landing.y - global_position.y
	var discriminant := rise * rise - 2.0 * gravity * drop
	var flight := (rise + sqrt(maxf(discriminant, 0.0))) / gravity
	_flight_time = flight
	_state_until = _now() + flight
	_next_jump = _now() + flight + jump_cooldown

	var travel := _landing - global_position
	velocity.x = travel.x / flight
	velocity.z = travel.z / flight
	velocity.y = rise

	# Stretches tall as it launches.
	scale = Vector3(0.78, 1.42, 0.78)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.3)

	marker.scale = Vector3(jump_radius, 1.0, jump_radius)
	marker.visible = false
	if _marker_material != null:
		_marker_material.albedo_color.a = 0.0
	_revealed = false
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	var reveal := create_tween()
	_reveal_tween = reveal
	reveal.tween_interval(flight * marker_delay)
	reveal.tween_callback(_reveal_landing.bind(player))
	if _marker_material != null:
		reveal.tween_property(_marker_material, "albedo_color:a", 0.6,
			flight * (1.0 - marker_delay) * 0.55)


## Late in the leap: picks the landing spot from where the player is NOW,
## steers the rest of the arc onto it, and shows the ring there. The vertical
## motion is untouched, so it still comes down exactly when the ring says.
func _reveal_landing(player: Node3D) -> void:
	if state != State.AIRBORNE or not is_instance_valid(player):
		return
	_landing = _choose_landing(player)
	var remaining := _state_until - _now()
	if remaining > 0.05:
		velocity.x = (_landing.x - global_position.x) / remaining
		velocity.z = (_landing.z - global_position.z) / remaining
	marker.global_position = _landing + Vector3(0, 0.06, 0)
	marker.visible = true
	_revealed = true


## Picks somewhere on the floor to come down on. It will not land on top of a
## pillar or a pedestal: if the spot under the player is raised, the target is
## walked back toward the mimic until it is back down at floor level.
func _choose_landing(player: Node3D) -> Vector3:
	var wanted := player.global_position
	var space := get_world_3d().direct_space_state

	for attempt in 9:
		var t := 1.0 - float(attempt) * 0.11
		var spot := Vector3(
			lerpf(global_position.x, wanted.x, t),
			arena_floor_y,
			lerpf(global_position.z, wanted.z, t),
		)
		var params := PhysicsRayQueryParameters3D.create(
			spot + Vector3(0, jump_peak_height + 4.0, 0), spot + Vector3(0, -6.0, 0)
		)
		params.collision_mask = landing_mask
		params.exclude = [get_rid()]
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			continue
		# The first thing a downward ray meets is the top of whatever is there.
		# Only bare floor counts; a pedestal or a stepping block reads higher.
		var ground: float = (hit["position"] as Vector3).y
		if absf(ground - arena_floor_y) <= landing_tolerance:
			return Vector3(spot.x, ground, spot.z)

	# Nowhere clear: drop straight down off whatever it is stood on.
	return Vector3(global_position.x, arena_floor_y, global_position.z)


func _land(player: Node3D) -> void:
	state = State.RECOVER
	_state_until = _now() + 0.6
	marker.visible = false
	velocity.x = 0.0
	velocity.z = 0.0

	# Snap to the marked spot so the slam is dead centre of the ring the player
	# was reading, rather than wherever the arc happened to scrape to.
	var landed := Vector3(_landing.x, global_position.y, _landing.z)
	if Vector2(landed.x - global_position.x, landed.z - global_position.z).length() < jump_radius:
		global_position = landed

	scale = Vector3(1.45, 0.55, 1.45)
	var squash := create_tween()
	squash.tween_property(self, "scale", Vector3.ONE, landing_shake) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_play_impact()
	# Bites down as it hits.
	_chomp(2, -105.0, 0.1)

	if not player.has_method("take_damage"):
		return
	# Measured from the marked centre, so what was shown is what hurts.
	var flat := Vector2(
		player.global_position.x - _landing.x,
		player.global_position.z - _landing.z,
	).length()
	# Same height rule the other enemies use: it cannot squash someone stood on
	# a block above the impact.
	if flat <= jump_radius and absf(player.global_position.y - global_position.y) <= 2.0:
		var before = player.get("health")
		player.take_damage(jump_damage, global_position.direction_to(player.global_position), self)
		# Only a hit that actually landed throws them: during the invulnerable
		# window after a previous hit, the damage is refused and so is this.
		var hurt: bool = before == null or float(player.get("health")) < float(before)
		if hurt and player.has_method("apply_knockback"):
			var away := player.global_position - global_position
			away.y = 0.0
			# Dead centre has no "away"; throw them along the line of the leap.
			if away.length_squared() < 0.01:
				away = Vector3(velocity.x, 0.0, velocity.z)
			if away.length_squared() < 0.01:
				away = global_basis.z
			player.apply_knockback(away.normalized() * jump_knockback
				+ Vector3(0, jump_knock_up, 0))


## Snaps the lid open and shut like a jaw. The two rows of teeth ride the lid
## and the body rim, so they only show while it is open -- closed, each row is
## tucked inside the other half and the thing still passes for a chest.
func _chomp(times: int, open_degrees := -95.0, speed := 0.12) -> void:
	if _chomp_tween != null and _chomp_tween.is_valid():
		_chomp_tween.kill()
	_chomp_tween = create_tween()
	for i in times:
		_chomp_tween.tween_property(lid_pivot, "rotation:x", deg_to_rad(open_degrees), speed) \
			.set_ease(Tween.EASE_OUT)
		# Bites down past level, so the teeth visibly meet.
		_chomp_tween.tween_property(lid_pivot, "rotation:x", deg_to_rad(-4.0), speed * 0.7) \
			.set_ease(Tween.EASE_IN)
	# Settles with its jaw hanging open.
	_chomp_tween.tween_property(lid_pivot, "rotation:x", deg_to_rad(jaw_rest_degrees), 0.2)


## A ring thrown out along the ground where it lands, to sell the weight.
func _play_impact() -> void:
	if _impact_material == null:
		return
	if _impact_tween != null and _impact_tween.is_valid():
		_impact_tween.kill()
	impact.global_position = Vector3(_landing.x, global_position.y + 0.08, _landing.z)
	impact.scale = Vector3(0.6, 1.0, 0.6)
	impact.visible = true
	_impact_material.albedo_color.a = 0.85

	_impact_tween = create_tween().set_parallel(true)
	_impact_tween.tween_property(impact, "scale", Vector3(jump_radius, 1.0, jump_radius), 0.32) \
		.set_ease(Tween.EASE_OUT)
	_impact_tween.tween_property(_impact_material, "albedo_color:a", 0.0, 0.32)


func _face(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		rotation.y = atan2(-direction.x, -direction.z)


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	if _dying:
		return
	# While it is still pretending to be furniture, it is furniture: a chest
	# does not flinch and does not bleed. Hitting one has to tell you nothing,
	# or the disguise is worthless -- you would find the mimic by walking the
	# room swinging at every chest.
	#
	# This also closes the obvious exploit in waking it by damage, which was
	# killing it from the floor without ever climbing up.
	if state == State.DORMANT:
		return

	health = maxf(health - amount, 0.0)
	_flash()
	if health <= 0.0:
		_die()


## Heavy enough to ignore being shoved around.
func apply_knockback(_impulse: Vector3, _stun_time := 0.25) -> void:
	pass


func _flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween().set_parallel(true)
	for i in _materials.size():
		_materials[i].albedo_color = Color(1.0, 0.95, 0.9)
		_flash_tween.tween_property(_materials[i], "albedo_color", _base_colors[i], 0.18)


func _die() -> void:
	_dying = true
	engaged = false
	died.emit()
	shape.disabled = true
	marker.visible = false
	impact.visible = false
	set_physics_process(false)
	# Otherwise the chomp keeps working the jaw through the whole death.
	if _chomp_tween != null and _chomp_tween.is_valid():
		_chomp_tween.kill()

	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_consumable") and reward != null:
		# Quietly: the banner below already says what was won.
		player.add_consumable(reward, reward_amount, false)
		_announce(reward_amount)
	if player != null and shard != &"":
		var inv = player.get("inventory")
		# A full pack does not lose it: it falls to the floor to be picked up.
		if inv == null or int(inv.add(shard, 1)) < 1:
			load("res://scripts/item_drop.gd").spawn(get_parent(), global_position + Vector3(0, 1.0, 0), shard, 1)

	# Three beats: it shudders, throws its lid wide in one last silent scream,
	# then caves in on itself and goes up.
	var rest := position
	var tween := create_tween()
	for i in 5:
		var shake := Vector3(randf_range(-0.09, 0.09), 0.0, randf_range(-0.09, 0.09))
		tween.tween_property(self, "position", rest + shake, 0.05)
	tween.tween_property(self, "position", rest, 0.04)

	tween.parallel().tween_property(lid_pivot, "rotation:x", deg_to_rad(-118.0), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.12)
	tween.tween_property(self, "scale", Vector3(1.35, 0.08, 1.35), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(_burst)
	tween.tween_callback(queue_free)


## Detached from this node, which is about to free itself and would otherwise
## take the explosion with it.
func _burst() -> void:
	if death_burst == null or get_parent() == null:
		return
	var burst := death_burst.instantiate() as Node3D
	burst.radius = burst_radius
	burst.colour = burst_color
	get_parent().add_child(burst)
	burst.global_position = global_position + Vector3(0, 0.8, 0)


func _announce(potions: int) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("announce"):
		return
	var noun := "health potion" if potions == 1 else "health potions"
	var sub := "+%d %s" % [potions, noun]
	if shard != &"":
		sub = Inventory.item_name(shard) + "    " + sub
	hud.announce("%s HAS FALLEN" % display_name, sub)


func _player_radius(player: Node) -> float:
	var collider := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider != null and collider.shape is CapsuleShape3D:
		return (collider.shape as CapsuleShape3D).radius
	return 0.4


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
