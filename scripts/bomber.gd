extends CharacterBody3D

## A fast orange flyer that throws itself at the player's FACE (2026-10-14).
##
## It chases, and once it has a clear line to the player (the sight layer, which
## shut doors are on -- so it never goes off behind one) and is within
## LUNGE_RANGE it flares for WINDUP and lunges. Reaching the face is a BLOW,
## through the player's guard like any other enemy's:
##   - PARRIED: it is thrown back and SHATTERS -- no explosion, no harm done.
##   - blocked: the usual `block_damage_taken` of the blow, and it sticks;
##   - unguarded: the blow, and it sticks.
## Stuck on the face it covers the view, blinking ever faster for FACE_FUSE,
## then explodes -- again a blow through the guard (block 10%, parry nothing) --
## and shatters into burning pieces with a fireball.
##
## It has `max_health` 50 and every weapon hurts it; killed, it shatters
## harmlessly. A parry is the clean answer. (Before this it ignored weapons and
## was struck with the sword's haft on E; that prompt is gone, and nothing calls
## `player.haft_strike` any more.)

signal died
signal fuse_started
signal detonated

@export var max_health := 50.0
## Thrown back by a parry or a kill, its pieces fly the way it was hit and
## outward from its centre this hard.
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

@export_group("Attack")
## From this far (centre to eye), with a clear line, it winds up and lunges.
@export var lunge_range := 3.4
@export var windup := 0.4
@export var lunge_speed := 15.0
## The blow of it reaching the face.
@export var latch_damage := 8.0
## Stuck on the face this long before it goes off.
@export var face_fuse := 1.8
@export var explosion_damage := 50.0
## Blinks per second at the start of the fuse and at the very end.
@export var blink_rate_start := 3.0
@export var blink_rate_end := 16.0
## Brightness of the flash at the moment of detonation.
@export var blast_light_energy := 9.0
@export var blast_radius := 3.5

@export_group("Colours")
@export var base_color := Color(1.0, 0.443137, 0.109804)
@export var blink_color := Color(1.0, 0.945098, 0.784314)
@export var base_glow := 1.1
@export var blink_glow := 4.5

@export_group("Navigation")
@export var repath_interval := 0.2

## Where on the face it sits: this far in front of the eye, this far below the
## view's centre, drawn at FACE_SCALE (a 0.9 m ball at arm's length would be
## the whole screen; this covers the middle of it).
const FACE_DIST := 0.78
const FACE_DROP := 0.16
const FACE_SCALE := 0.62
## On the face its glow and its light are turned down: at full blink, right at
## the camera, it burnt to a flat white disc and its light blew out every wall
## in view (measured in a screenshot).
const FACE_GLOW := 0.35
const FACE_LIGHT := 0.25
## And it blinks hot orange, not white: albedo plus emission at the white blink
## colour saturated it to a flat disc with no shape.
const FACE_HOT := 0.4
## Reaching within this of the face point counts as contact.
const FACE_REACH := 0.55
## A lunge that has not connected after this long gives up and chases again.
const LUNGE_GIVE_UP := 0.7
## Seconds between attacks after one is called off.
const RECOVER := 0.8

enum { CHASE, WINDUP, LUNGE, FACE }

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var shape: CollisionShape3D = $CollisionShape3D
@onready var light: OmniLight3D = $Light
## Pre-authored so its transparent shader is compiled at load rather than
## stalling the frame something explodes.
@onready var blast: MeshInstance3D = $Blast
@onready var agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

var health := 0.0
## Lit: stuck on the face, fuse running (kept for anything that asked before).
var fusing := false
## The health bar hides while it is on the face (enemy_health_bar.gd reads it).
var scripted := false

var _state := CHASE
var _state_time := 0.0
var _recover := 0.0
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
var _flash_tween: Tween
## Asleep: too far from the player to be worth simulating.
var _dormant := false
var _next_dormant_check := 0.0
## Set by the player's `guarded` signal while our blow is being dealt.
var _parried := false
## Shattered pieces in flight: [node, velocity, rotation, spin axis, spin rate].
var _shards: Array = []
var _shard_time := 0.0
var _shard_material: StandardMaterial3D
var _shard_ray := PhysicsRayQueryParameters3D.new()
var _sight := PhysicsRayQueryParameters3D.new()

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


func _ready() -> void:
	health = max_health
	_bob = randf() * TAU
	# Placed on the face after the player has moved the camera this frame.
	process_priority = 10
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
	preload("res://scripts/enemy_health_bar.gd").attach(self)
	_sight.collision_mask = 2
	set_process(false)
	_warm_up.call_deferred()


func _physics_process(delta: float) -> void:
	if _dying:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player != null and _player.has_signal("guarded") \
				and not _player.is_connected("guarded", _on_player_guarded):
			_player.connect("guarded", _on_player_guarded)
	var player := _player
	if player == null:
		return

	if _state == FACE:
		_tick_fuse(delta)
		return
	# Dormancy: with dozens of these hovering around the map, simulating the
	# ones nobody can see is the bulk of the physics budget. Never mid-attack.
	if _state == CHASE and _update_dormancy():
		return

	_bob += delta * bob_speed
	_state_time += delta
	_recover = maxf(_recover - delta, 0.0)
	var eye := _eye(player)
	var to_eye := eye - global_position

	match _state:
		WINDUP:
			# Hang back and swell, facing the player: the tell.
			velocity = velocity.move_toward(Vector3.ZERO, acceleration * 2.0 * delta)
			move_and_slide()
			var k := clampf(_state_time / windup, 0.0, 1.0)
			_paint(base_color.lerp(blink_color, k), lerpf(base_glow, blink_glow, k))
			mesh.scale = Vector3.ONE * (1.0 + 0.18 * sin(k * PI))
			if _state_time >= windup:
				if _can_attack(player, eye) and to_eye.length() < lunge_range * 1.6:
					_set_state(LUNGE)
				else:
					_call_off()
			return
		LUNGE:
			var face := _face_point(player)
			var to_face := face - global_position
			if to_face.length() <= FACE_REACH:
				_hit_face(player)
				return
			if _state_time > LUNGE_GIVE_UP or not _can_attack(player, eye):
				_call_off()
				return
			velocity = to_face.normalized() * lunge_speed
			move_and_slide()
			return

	# CHASE.
	var flat := Vector3(to_eye.x, 0.0, to_eye.z)
	if flat.length() > aggro_range:
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
		move_and_slide()
		return
	if _recover <= 0.0 and to_eye.length() <= lunge_range and _can_attack(player, eye):
		_set_state(WINDUP)
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
	# Hold off a little short of the player rather than pressing into them.
	var speed := move_speed
	if flat.length() < lunge_range * 0.8:
		speed = 0.0
	var wanted_height := player.global_position.y + hover_height + sin(_bob) * bob_amount
	var climb := clampf(wanted_height - global_position.y, -1.0, 1.0)
	var desired := heading * speed
	desired.y = climb * move_speed * 0.8
	velocity = velocity.move_toward(desired, acceleration * delta)
	if flat.length_squared() > 0.001:
		rotation.y = atan2(-heading.x, -heading.z)
	move_and_slide()


func _set_state(s: int) -> void:
	_state = s
	_state_time = 0.0


## The attack was not on: back to chasing, and a beat before the next try.
func _call_off() -> void:
	_set_state(CHASE)
	_recover = RECOVER
	mesh.scale = Vector3.ONE
	_paint(base_color, base_glow)


func _eye(player: Node3D) -> Vector3:
	var cam: Camera3D = player.get("camera")
	if cam != null and cam.is_inside_tree():
		return cam.global_position
	return player.global_position + Vector3(0.0, 1.6, 0.0)


## Where it sits stuck on the face.
func _face_point(player: Node3D) -> Vector3:
	var cam: Camera3D = player.get("camera")
	if cam == null or not cam.is_inside_tree():
		return player.global_position + Vector3(0.0, 1.5, 0.0)
	var basis := cam.global_basis.orthonormalized()
	return cam.global_position - basis.z * FACE_DIST - basis.y * FACE_DROP


## A player it can go for: alive, not hidden or in a scene, and in plain sight
## -- the line runs on the sight layer, which a shut door blocks.
func _can_attack(player: Node3D, eye: Vector3) -> bool:
	if player.get("_dead") == true or player.get("in_cutscene") == true:
		return false
	if player.has_method("is_hidden") and player.is_hidden():
		return false
	_sight.from = global_position
	_sight.to = eye
	_sight.exclude = [player.get_rid(), get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(_sight).is_empty()


## Contact: a blow through the guard. Parried, it is thrown off and shatters;
## otherwise it sticks.
func _hit_face(player: Node3D) -> void:
	var blow := (_eye(player) - global_position).normalized()
	_parried = false
	if player.has_method("take_damage"):
		player.take_damage(latch_damage, blow, self)
	if _parried:
		_burst(-blow)
		return
	_set_state(FACE)
	fusing = true
	scripted = true
	_fuse_left = face_fuse
	_blink_phase = 0.0
	velocity = Vector3.ZERO
	shape.set_deferred(&"disabled", true)
	mesh.scale = Vector3.ONE * FACE_SCALE
	set_process(true)
	fuse_started.emit()


func _on_player_guarded(parried: bool, attacker: Node3D) -> void:
	if attacker == self and parried:
		_parried = true


func _tick_fuse(delta: float) -> void:
	var player := _player
	if player == null or not is_instance_valid(player) or player.get("_dead") == true \
			or (player.get("in_cutscene") == true):
		# Nothing to go off on: it lets go and breaks.
		_burst(Vector3.UP)
		return
	_fuse_left -= delta
	# The blink speeds up as it runs out, so the urgency reads without a number.
	var progress := clampf(1.0 - _fuse_left / face_fuse, 0.0, 1.0)
	_blink_phase += delta * lerpf(blink_rate_start, blink_rate_end, progress)
	var lit := fmod(_blink_phase, 1.0) < 0.5
	_paint(base_color.lerp(blink_color, FACE_HOT) if lit else base_color.darkened(0.25),
		(blink_glow if lit else base_glow) * FACE_GLOW)
	light.light_energy *= FACE_LIGHT / FACE_GLOW
	if _fuse_left <= 0.0:
		_detonate(player)


## Goes off in the player's face: a blow through the guard, then it shatters in
## a fireball. Parried, the guard takes all of it.
func _detonate(player: Node3D) -> void:
	var blow := (_eye(player) - global_position).normalized()
	_dying = true
	fusing = false
	if player.has_method("take_damage"):
		player.take_damage(explosion_damage, blow, self)
	detonated.emit()
	_shatter(-blow, true)
	_play_blast()
	died.emit()


## Killed or parried: it shatters, with no explosion and no harm done.
func _burst(direction: Vector3) -> void:
	if _dying and _shards.size() > 0:
		return
	_dying = true
	fusing = false
	scripted = false
	died.emit()
	_shatter(direction.normalized() if direction.length_squared() > 1e-6 else Vector3.UP, false)


func _shatter(direction: Vector3, burning: bool) -> void:
	shape.set_deferred(&"disabled", true)
	set_physics_process(false)
	mesh.visible = false
	_shard_material = _make_shard_material()
	_shard_ray.collision_mask = 2
	_shard_ray.exclude = [get_rid()]
	var frame := mesh.global_transform
	var push := shatter_push * (1.8 if burning else 1.0)
	var burst := shatter_burst * (1.8 if burning else 1.0)
	for piece in _pieces(mesh.mesh):
		var shard := MeshInstance3D.new()
		shard.mesh = piece[0]
		shard.material_override = _shard_material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.top_level = true
		add_child(shard)
		var rot := frame.basis.orthonormalized()
		var scale := frame.basis.get_scale().x
		shard.global_transform = Transform3D(rot.scaled(Vector3.ONE * scale), frame * piece[1])
		var outward: Vector3 = rot * piece[2]
		var velocity := outward * burst * randf_range(0.7, 1.3) \
			+ direction * push * randf_range(0.6, 1.3) \
			+ Vector3(0.0, randf_range(1.0, 3.0), 0.0)
		var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		_shards.append([shard, velocity, rot.scaled(Vector3.ONE * scale), axis.normalized() if axis.length_squared() > 1e-4 else Vector3.UP,
			randf_range(6.0, 14.0)])
	_shard_time = 0.0
	set_process(true)
	# White-hot at the break, cooling back to the bomber's orange as they fly.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_shard_material, "albedo_color", base_color, 0.35)
	tween.tween_property(_shard_material, "emission", base_color, 0.35)
	tween.tween_property(_shard_material, "emission_energy_multiplier", base_glow, 0.5)
	if not burning:
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
	# Stuck on the face: placed every frame after the camera has moved, so it
	# rides the view without lagging a frame behind it.
	if _state == FACE and not _dying and _player != null and is_instance_valid(_player):
		global_position = _face_point(_player)
		var cam: Camera3D = _player.get("camera")
		if cam != null:
			global_basis = cam.global_basis.orthonormalized()
		return
	if _shards.is_empty():
		if not _dying:
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


## The fireball where it went off, swelling and fading round its pieces.
func _play_blast() -> void:
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
	tween.tween_property(blast, "scale", Vector3.ONE * blast_radius * 0.6, 0.4) \
		.set_ease(Tween.EASE_OUT)
	# A hard flash of light that dies with the fireball.
	light.light_color = blink_color
	light.light_energy = blast_light_energy
	light.omni_range = blast_radius * 2.0
	tween.tween_property(light, "light_energy", 0.0, 0.45)


## Every weapon hurts it; at nothing it shatters, harmlessly.
func take_damage(amount: float, from_direction: Vector3 = Vector3.ZERO) -> void:
	if _dying:
		return
	health -= amount
	_flash()
	if health <= 0.0:
		_burst(from_direction if from_direction.length_squared() > 1e-6 else Vector3.UP)


## Shoved like any other enemy -- except stuck on a face, where nothing but a
## kill gets it off.
func apply_knockback(impulse: Vector3, _stun_time := 0.25) -> void:
	if _dying or _state == FACE:
		return
	velocity.x += impulse.x
	velocity.z += impulse.z
	if _state != CHASE:
		_call_off()


func _flash() -> void:
	if _material == null or _state == FACE:
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
