extends CharacterBody3D

## A fast orange flyer that closes on the player and detonates. It never deals
## contact damage -- the only threat is the explosion, and it telegraphs that by
## blinking for the whole fuse.
##
## A sword does nothing to it: the blade (and the slam) pass straight through.
## The only answer is E ("interact") within `swat_reach` -- the player drives
## the sword's HAFT into it (`player.haft_strike`), and it is knocked away and
## pops without going off. That works on a lit one riding the player too.

signal died
signal fuse_started
signal detonated

@export var max_health := 10.0
## How near the player's eyes it must be for E to strike it.
@export var swat_reach := 2.6
## Struck by the haft, it shatters: how hard the pieces are thrown the way it
## was hit, and outward from its centre.
@export var shatter_push := 5.5
@export var shatter_burst := 3.5

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
var _prompt: Interact.Prompt
## Shattered pieces in flight: [node, velocity, rotation, spin axis, spin rate].
var _shards: Array = []
var _shard_time := 0.0
var _shard_material: StandardMaterial3D
var _shard_ray := PhysicsRayQueryParameters3D.new()

const SHARD_COUNT := 10
## The inner face of each piece sits at this fraction of the radius, so the
## pieces are chunks, not paper-thin shell.
const SHARD_DEPTH := 0.55
const SHARD_LIFE := 0.9
const SHARD_SHRINK := 0.3
const SHARD_GRAVITY := 14.0
## Pieces cut once per source mesh and shared by every bomber, so the first
## shatter does not stall on cutting them.
static var _shard_cache := {}
## Within reach of the player's eyes, with nothing in between.
var _near := false
var _sight := PhysicsRayQueryParameters3D.new()


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
	# No health bar: nothing can wear it down -- it is struck away or it goes off.
	_prompt = Interact.prompt("E   Strike", Vector3(0.0, 0.55, 0.0))
	add_child(_prompt)
	_sight.collision_mask = 2
	_warm_up.call_deferred()

func _physics_process(delta: float) -> void:
	if _dying:
		return

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	var player := _player
	if player == null:
		return
	_update_near(player)

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


func _update_near(player: Node3D) -> void:
	var eye := player.global_position + Vector3(0.0, 1.6, 0.0)
	var near := global_position.distance_squared_to(eye) <= swat_reach * swat_reach
	if near:
		_sight.from = eye
		_sight.to = global_position
		_sight.exclude = [player.get_rid(), get_rid()]
		near = get_world_3d().direct_space_state.intersect_ray(_sight).is_empty()
	# The crosshair has to be on it -- except once it is lit and latched on,
	# riding the player's shoulders where the view often cannot reach it.
	if near and not fusing:
		near = Interact.looked_at(self, swat_reach + 0.6, 0.15)
	_near = near
	if _prompt.visible != near:
		_prompt.visible = near


func _unhandled_input(event: InputEvent) -> void:
	if not _near or _dying or not Interact.pressed(event):
		return
	if _player != null and _player.has_method("haft_strike") and _player.haft_strike(self):
		get_viewport().set_input_as_handled()


## Struck by the haft: the fuse goes out and it SHATTERS -- the sphere breaks
## into chunks that burst out the way it was hit, tumble, bounce off the stone
## and shrink away. No explosion, no damage to anyone.
func swat(direction: Vector3) -> void:
	if _dying:
		return
	_dying = true
	fusing = false
	_near = false
	_prompt.visible = false
	shape.set_deferred(&"disabled", true)
	set_physics_process(false)
	died.emit()
	_shatter(direction.normalized())


func _shatter(direction: Vector3) -> void:
	mesh.visible = false
	_shard_material = _make_shard_material()
	_shard_ray.collision_mask = 2
	_shard_ray.exclude = [get_rid()]
	var frame := mesh.global_transform
	for piece in _pieces(mesh.mesh):
		var shard := MeshInstance3D.new()
		shard.mesh = piece[0]
		shard.material_override = _shard_material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.top_level = true
		add_child(shard)
		var rot := frame.basis.orthonormalized()
		shard.global_transform = Transform3D(rot, frame * piece[1])
		var outward: Vector3 = rot * piece[2]
		var velocity := outward * shatter_burst * randf_range(0.7, 1.3) \
			+ direction * shatter_push * randf_range(0.6, 1.3) \
			+ Vector3(0.0, randf_range(1.0, 3.0), 0.0)
		var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		_shards.append([shard, velocity, rot, axis.normalized() if axis.length_squared() > 1e-4 else Vector3.UP,
			randf_range(6.0, 14.0)])
	_shard_time = 0.0
	set_process(true)
	# White-hot at the break, cooling back to the bomber's orange as they fly.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_shard_material, "albedo_color", base_color, 0.35)
	tween.tween_property(_shard_material, "emission", base_color, 0.35)
	tween.tween_property(_shard_material, "emission_energy_multiplier", base_glow, 0.5)
	# One flash from its own light, dying with the burst.
	light.light_color = blink_color
	light.light_energy = blink_glow * 2.0
	tween.tween_property(light, "light_energy", 0.0, 0.3)


func _make_shard_material() -> StandardMaterial3D:
	var m := (_material.duplicate() if _material != null else StandardMaterial3D.new()) as StandardMaterial3D
	# Pieces are closed solids, but cheap enough to draw from both sides, which
	# saves caring about winding.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = blink_color
	m.emission_enabled = true
	m.emission = blink_color
	m.emission_energy_multiplier = blink_glow
	return m


## The first shatter stalled its frame (79 ms measured): a double-sided
## variant of the bomber material compiling on first draw. So the first bomber
## to come up cuts the pieces and draws one speck of a piece in that material in
## front of the camera, once, while the level is still loading.
static var _warmed := false

func _warm_up() -> void:
	if _warmed or mesh == null or mesh.mesh == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	var camera: Camera3D = player.get("camera") if player != null else null
	if camera == null or not camera.is_inside_tree():
		return
	_warmed = true
	var pieces := _pieces(mesh.mesh)
	if pieces.is_empty():
		return
	var speck := MeshInstance3D.new()
	speck.name = "ShardWarmUp"
	speck.mesh = pieces[0][0]
	speck.material_override = _make_shard_material()
	speck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(speck)
	speck.position = Vector3(0.0, 0.0, -0.5)
	speck.scale = Vector3.ONE * 0.002
	get_tree().create_timer(0.5).timeout.connect(speck.queue_free)


func _process(delta: float) -> void:
	if _shards.is_empty():
		set_process(false)
		return
	_shard_time += delta
	var size := clampf((SHARD_LIFE - _shard_time) / SHARD_SHRINK, 0.0, 1.0)
	var space := get_world_3d().direct_space_state
	for s in _shards:
		var shard: MeshInstance3D = s[0]
		var velocity: Vector3 = s[1]
		velocity.y -= SHARD_GRAVITY * delta
		var from := shard.global_position
		var to := from + velocity * delta
		# Off the stone, not through it.
		_shard_ray.from = from
		_shard_ray.to = to
		var hit := space.intersect_ray(_shard_ray)
		if not hit.is_empty():
			var normal: Vector3 = hit["normal"]
			to = (hit["position"] as Vector3) + normal * 0.04
			velocity = velocity.bounce(normal) * 0.35
			s[4] = (s[4] as float) * 0.5
		s[1] = velocity
		var rot: Basis = Basis(s[3], (s[4] as float) * delta) * (s[2] as Basis)
		s[2] = rot
		shard.global_transform = Transform3D(rot.scaled(Vector3.ONE * maxf(size, 0.001)), to)
	if _shard_time >= SHARD_LIFE:
		queue_free()


## The sphere cut into SHARD_COUNT chunks: each triangle goes to the nearest of
## SHARD_COUNT directions spread over the sphere, and each group is closed into
## a solid -- its outer facets, the same pulled in to SHARD_DEPTH, and walls
## along its open edges. Returns [mesh centred on itself, its centre, its
## direction] per piece.
static func _pieces(source: Mesh) -> Array:
	if _shard_cache.has(source):
		return _shard_cache[source]
	var arrays := source.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tris: Array = []
	if index.is_empty():
		for i in range(0, verts.size() - 2, 3):
			tris.append([verts[i], verts[i + 1], verts[i + 2]])
	else:
		for i in range(0, index.size() - 2, 3):
			tris.append([verts[index[i]], verts[index[i + 1]], verts[index[i + 2]]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seeds: Array[Vector3] = []
	for i in SHARD_COUNT:
		var y := 1.0 - (i + 0.5) / SHARD_COUNT * 2.0
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var a := i * 2.39996 + rng.randf_range(-0.4, 0.4)
		seeds.append(Vector3(cos(a) * r, y, sin(a) * r).normalized())
	var groups: Array = []
	for i in SHARD_COUNT:
		groups.append([])
	for tri in tris:
		var c: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		if ((tri[1] - tri[0]) as Vector3).cross(tri[2] - tri[0]).length_squared() < 1e-10:
			continue
		var best := 0
		var best_dot := -2.0
		for i in SHARD_COUNT:
			var d := c.normalized().dot(seeds[i])
			if d > best_dot:
				best_dot = d
				best = i
		groups[best].append(tri)
	var pieces: Array = []
	for i in SHARD_COUNT:
		if not groups[i].is_empty():
			pieces.append(_solid_piece(groups[i], seeds[i]))
	_shard_cache[source] = pieces
	return pieces


static func _solid_piece(tris: Array, direction: Vector3) -> Array:
	var outer := Vector3.ZERO
	var count := 0
	for tri in tris:
		for v in tri:
			outer += v
			count += 1
	outer /= float(count)
	# Between the outer facets and the inner face.
	var centre := outer * (1.0 + SHARD_DEPTH) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := {}
	for tri in tris:
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var n := (b - a).cross(c - a).normalized()
		if n.dot(a + b + c) < 0.0:
			n = -n
		for v in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(v - centre)
		for v in [a, b, c]:
			st.set_normal(-n)
			st.add_vertex(v * SHARD_DEPTH - centre)
		for e in [[a, b], [b, c], [c, a]]:
			var key := _edge_key(e[0], e[1])
			if edges.has(key):
				edges[key][2] += 1
			else:
				edges[key] = [e[0], e[1], 1]
	for key in edges:
		var e: Array = edges[key]
		if e[2] != 1:
			continue
		# An open edge of the group: wall it from the outer facet to the inner.
		var p: Vector3 = e[0]
		var q: Vector3 = e[1]
		var pi := p * SHARD_DEPTH
		var qi := q * SHARD_DEPTH
		var n := (q - p).cross(pi - p).normalized()
		var mid := (p + q + pi + qi) * 0.25
		if n.dot(mid - outer) < 0.0:
			n = -n
		for v in [p, q, qi, p, qi, pi]:
			st.set_normal(n)
			st.add_vertex(v - centre)
	return [st.commit(), centre, direction]


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var sa := str(a.snapped(Vector3.ONE * 1e-4))
	var sb := str(b.snapped(Vector3.ONE * 1e-4))
	return sa + sb if sa < sb else sb + sa

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
	_near = false
	_prompt.visible = false
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


## Blades and blasts pass through it -- only the haft strike (`swat`) works.
## Kept so anything that deals damage generically can still call it.
func take_damage(_amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	pass


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
