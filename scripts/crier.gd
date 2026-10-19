extends CharacterBody3D

## A CRIER (2026-10-14; called a bomber before): the old warden bot's head, flying
## loose, that throws itself at the player's face and goes off there.
##
## The moment it SEES the player -- a clear line on the sight layer (2), which
## shut doors are on, so never through one -- it flies straight at their face
## at `rush_speed`, far faster than they can walk. Out of sight it makes for
## where it last saw them, then gives up. It has no other attack: reaching the
## face it STICKS (no blow), its lens blinking ever faster for `face_fuse`, and
## then it explodes -- a blow through the player's guard like any enemy's:
## parried, nothing; blocked, `block_damage_taken` of it; otherwise all of it.
## Either way it shatters into burning pieces with a fireball.
##
## 50 health and every weapon hurts it; killed, it shatters harmlessly.

signal died
signal fuse_started
signal detonated

@export var max_health := 50.0
## Its pieces fly the way it was hit and outward from its centre this hard.
@export var shatter_push := 5.5
@export var shatter_burst := 3.5

@export_group("Flight")
## Straight at the face once it sees the player (they walk at 4.25 m/s).
@export var rush_speed := 14.0
## Making for where it last saw them, round the walls.
@export var move_speed := 11.0
@export var acceleration := 40.0
## How far above the player's feet it hovers when it has lost them.
@export var hover_height := 1.5
@export var bob_amount := 0.18
@export var bob_speed := 3.4
## How far it can see the player from.
@export var aggro_range := 32.0
## After losing sight it searches this long before giving up.
@export var memory := 5.0

@export_group("Performance")
## Past this distance from the player the crier stops simulating altogether.
@export var dormant_range := 50.0
@export var dormant_poll := 0.4

@export_group("Explosion")
## Stuck on the face this long before it goes off.
@export var face_fuse := 1.0
@export var explosion_damage := 50.0
## A held guard lets this share of the blast through (other enemies: the
## player's `block_damage_taken`, 10%). A parry takes none of it.
@export_range(0.0, 1.0) var block_damage_share := 0.25
## Blinks per second at the start of the fuse and at the very end.
@export var blink_rate_start := 3.0
@export var blink_rate_end := 16.0
@export var blast_light_energy := 9.0
@export var blast_radius := 3.5

@export_group("Colours")
## The lens: the old bot's gold crystal, blinking white-hot on the face.
@export var base_color := Color(1.0, 0.62, 0.16)
@export var blink_color := Color(1.0, 0.945098, 0.784314)
@export var base_glow := 1.6
@export var blink_glow := 4.5

@export_group("Navigation")
@export var repath_interval := 0.2

## Where it sits stuck on the face: this far in front of the eye, this far below
## the view's centre, drawn at FACE_SCALE, its lens turned to the eyes.
const FACE_DIST := 0.78
const FACE_DROP := 0.16
const FACE_SCALE := 0.62
## Reaching within this of the face point counts as contact.
const FACE_REACH := 0.55
## On the face its glow and its light are turned down: at full blink, right at
## the camera, it burnt to a flat white disc and lit every wall in view white.
const FACE_GLOW := 0.35
const FACE_LIGHT := 0.25
## And it blinks hot gold, not white.
const FACE_HOT := 0.4
## The old warden bot's head at this size: a 0.76 m box.
const HEAD_SCALE := 2.0
## Seconds between sight checks while it cannot see the player.
const LOOK_EVERY := 0.1

enum { HUNT, FACE }


@onready var shape: CollisionShape3D = $CollisionShape3D
@onready var light: OmniLight3D = $Light
## Pre-authored so its transparent shader is compiled at load rather than
## stalling the frame something explodes.
@onready var blast: MeshInstance3D = $Blast
@onready var agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")

## The head, built in _ready: `mesh` the plates (and what shatters), `lens` the
## crystal that blinks.
var mesh: MeshInstance3D
var lens: MeshInstance3D

var health := 0.0
## Stuck on the face, fuse running.
var fusing := false
## The health bar hides while it is on the face (enemy_health_bar.gd reads it).
var scripted := false

var _state := HUNT
var _material: StandardMaterial3D
var _plate_material: StandardMaterial3D
var _blast_material: StandardMaterial3D
var _dying := false
var _fuse_left := 0.0
var _blink_phase := 0.0
var _bob := 0.0
var _next_repath := 0.0
var _player: Node3D = null
var _flash_tween: Tween
var _dormant := false
var _next_dormant_check := 0.0
## Where and when it last saw the player; -1: never.
var _seen_at := Vector3.ZERO
var _seen_time := -100.0
var _sees := false
var _next_look := 0.0
## Set by the player's `guarded` signal while the explosion is being dealt.
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
## Pieces cut once per source mesh and shared by every crier, so the first
## shatter does not stall on cutting them.
static var _shard_cache := {}
static var _head_mesh: ArrayMesh
static var _lens_mesh: Mesh


func _ready() -> void:
	health = max_health
	_bob = randf() * TAU
	# Placed on the face after the player has moved the camera this frame.
	process_priority = 10
	_build_head()
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


## The old warden bot's head: plate box, neck, brass rim round a gold
## crystal lens, an aerial -- merged into one mesh, shared by every crier, and
## centred on the box so it flies and shatters about its middle.
func _build_head() -> void:
	var old := get_node_or_null("MeshInstance3D")
	if old != null:
		old.free()
	if _head_mesh == null:
		var tools := {}
		var add := func(m: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			var centre := Transform3D(Basis().scaled(Vector3.ONE * HEAD_SCALE),
				Vector3(0.0, -0.27 * HEAD_SCALE, 0.0))
			(tools[mat] as SurfaceTool).append_from(m, 0, centre * xf)
		var neck := _robot_cyl(0.07, 0.09, 0.14, 6)
		add.call(neck, Transform3D(Basis(), Vector3(0.0, 0.07, 0.0)), _robot_mat(&"dark"))
		add.call(_robot_box(Vector3(0.38, 0.28, 0.34)), Transform3D(Basis(Vector3.FORWARD, 0.04),
			Vector3(0.0, 0.27, 0.0)), _robot_mat(&"plate"))
		add.call(_robot_cyl(0.1, 0.1, 0.06, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5),
			Vector3(0.05, 0.28, -0.18)), _robot_mat(&"brass"))
		add.call(_robot_cyl(0.012, 0.012, 0.4, 4), Transform3D(Basis(Vector3.FORWARD, 0.2),
			Vector3(-0.12, 0.56, 0.06)), _robot_mat(&"brass"))
		_head_mesh = ArrayMesh.new()
		for mat in tools:
			var st: SurfaceTool = tools[mat]
			st.generate_normals()
			st.commit(_head_mesh)
			_head_mesh.surface_set_material(_head_mesh.get_surface_count() - 1, mat)
		var s := SphereMesh.new()
		s.radius = 0.06 * HEAD_SCALE
		s.height = 0.05 * HEAD_SCALE
		s.radial_segments = 4
		s.rings = 2
		_lens_mesh = s
	mesh = MeshInstance3D.new()
	mesh.name = "Head"
	mesh.mesh = _head_mesh
	add_child(mesh)
	move_child(mesh, 0)
	# Its plates warm with the lens as it blinks: their own copy of the plate
	# material, emission off until then.
	for i in _head_mesh.get_surface_count():
		if _head_mesh.surface_get_material(i) == _robot_mat(&"plate"):
			_plate_material = _robot_mat(&"plate").duplicate() as StandardMaterial3D
			_plate_material.emission_enabled = true
			_plate_material.emission = Color.BLACK
			mesh.set_surface_override_material(i, _plate_material)
	lens = MeshInstance3D.new()
	lens.name = "Lens"
	lens.mesh = _lens_mesh
	lens.rotation.x = PI * 0.5
	lens.position = Vector3(0.05, 0.01, -0.21) * HEAD_SCALE
	_material = StandardMaterial3D.new()
	_material.albedo_color = base_color
	_material.emission_enabled = true
	_material.emission = base_color
	_material.emission_energy_multiplier = base_glow
	_material.metallic = 0.2
	_material.roughness = 0.3
	lens.material_override = _material
	mesh.add_child(lens)
	for mi in [mesh, lens]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(delta: float) -> void:
	if _dying:
		return
	# Co-op (coop.gd): after the nearest player -- but one stuck on a face stays
	# on it -- and listening to every player's guard.
	if _state != FACE or _player == null or not is_instance_valid(_player):
		_player = Coop.nearest(global_position) as Node3D
	for p in Coop.all():
		if p.has_signal("guarded") and not p.is_connected("guarded", _on_player_guarded):
			p.connect("guarded", _on_player_guarded)
	var player := _player
	if player == null:
		return
	if _state == FACE:
		_tick_fuse(delta)
		return
	if _update_dormancy():
		return

	_bob += delta * bob_speed
	var now := Time.get_ticks_msec() / 1000.0
	# Scared off by a thrown rat (`scare`): away from the spot at its rush
	# speed, keeping its height, until the fright is over.
	if now < _scared_until:
		var away := global_position - _scared_from
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3.FORWARD
		var flee := away.normalized() * rush_speed
		flee.y = clampf(_scared_from.y + hover_height + 0.6 - global_position.y, -1.0, 1.0) * move_speed * 0.8
		velocity = velocity.move_toward(flee, acceleration * 2.0 * delta)
		_turn_to(away)
		move_and_slide()
		return
	var eye := _eye(player)
	if _sees or now >= _next_look:
		_next_look = now + LOOK_EVERY
		_sees = _can_see(player, eye)
		if _sees:
			_seen_at = player.global_position
			_seen_time = now

	if _sees:
		# Straight at the face.
		var face := _face_point(player)
		var to_face := face - global_position
		if to_face.length() <= FACE_REACH:
			_stick()
			return
		_turn_to(to_face)
		velocity = velocity.move_toward(to_face.normalized() * rush_speed, acceleration * 2.0 * delta)
		move_and_slide()
		return

	if now - _seen_time > memory:
		# Lost them: hang where it is, bobbing.
		velocity = velocity.move_toward(Vector3(0.0, cos(_bob) * bob_amount, 0.0), acceleration * delta)
		move_and_slide()
		return

	# Round the walls to where it last saw them. The agent's waypoint distances
	# must exceed hover_height, or a flyer never gets close enough to a
	# floor-level waypoint to advance past it and jitters on the first one.
	var to_seen := _seen_at - global_position
	var heading := Vector3(to_seen.x, 0.0, to_seen.z).normalized()
	if agent != null:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = _seen_at
		if not agent.is_navigation_finished():
			var step := agent.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.5:
				heading = step.normalized()
	var wanted_height := _seen_at.y + hover_height + sin(_bob) * bob_amount
	var desired := heading * move_speed
	desired.y = clampf(wanted_height - global_position.y, -1.0, 1.0) * move_speed * 0.8
	velocity = velocity.move_toward(desired, acceleration * delta)
	if heading.length_squared() > 0.001:
		_turn_to(heading)
	move_and_slide()


## --- Scared off by a thrown rat (rat.gd, 2026-10-18) ---------------------------
## Like the walkers' (enemy.gd `scare`): `time` seconds flying away from
## `from`, and it forgets where it last saw the player. Too late once it is
## on the face. Returns whether it took fright.
var _scared_until := 0.0
var _scared_from := Vector3.ZERO


func scare(from: Vector3, time: float) -> bool:
	if _dying or _state == FACE:
		return false
	_scared_until = maxf(_scared_until, Time.get_ticks_msec() / 1000.0 + time)
	_scared_from = from
	_dormant = false
	_sees = false
	_seen_time = -100.0
	return true


func is_scared() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _scared_until


func _turn_to(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length_squared() > 0.0001:
		rotation.y = atan2(-dir.x, -dir.z)


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


## In plain sight and in range: alive, not hidden or in a scene, and a clear
## line on the sight layer -- which a shut door blocks.
func _can_see(player: Node3D, eye: Vector3) -> bool:
	if player.get("_dead") == true or player.get("in_cutscene") == true:
		return false
	if player.has_method("is_hidden") and player.is_hidden():
		return false
	if Sandbox.enemies_passive:
		return false
	if global_position.distance_squared_to(eye) > aggro_range * aggro_range:
		return false
	_sight.from = global_position
	_sight.to = eye
	_sight.exclude = [player.get_rid(), get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(_sight).is_empty()


## Reached the face: it sticks there and the fuse starts. No blow -- the only
## thing that hurts is the explosion.
func _stick() -> void:
	_state = FACE
	fusing = true
	scripted = true
	_fuse_left = face_fuse
	_blink_phase = 0.0
	velocity = Vector3.ZERO
	shape.set_deferred(&"disabled", true)
	mesh.scale = Vector3.ONE * FACE_SCALE
	set_process(true)
	fuse_started.emit()


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
	if _plate_material != null:
		_plate_material.emission = base_color * (0.35 * progress if lit else 0.1 * progress)
	if _fuse_left <= 0.0:
		_detonate(player)


## Goes off in the player's face: a blow through the guard. Parried, the guard
## takes all of it and the crier is blown back off the face in pieces -- no
## fireball, so a parry reads as a parry (with the purple flash dead centre:
## `guard_flash_centre`). Otherwise it shatters in a fireball.
func _detonate(player: Node3D) -> void:
	var blow := (_eye(player) - global_position).normalized()
	_dying = true
	fusing = false
	_parried = false
	if player.has_method("take_damage"):
		player.take_damage(explosion_damage, blow, self)
	detonated.emit()
	if _parried:
		_shatter(-blow, false)
	else:
		_shatter(-blow, true)
		_play_blast()
	died.emit()


## The player's guard flash goes in the middle of the view while this is on
## the face (player._on_guarded).
func guard_flash_centre() -> bool:
	return _state == FACE


func _on_player_guarded(parried: bool, attacker: Node3D) -> void:
	if attacker == self and parried:
		_parried = true


## Killed, or nothing to go off on: it shatters, with no explosion.
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
	# White-hot at the break, cooling to the lens's gold as they fly.
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_shard_material, "albedo_color", base_color.darkened(0.5), 0.35)
	tween.tween_property(_shard_material, "emission", base_color, 0.35)
	tween.tween_property(_shard_material, "emission_energy_multiplier", base_glow * 0.5, 0.5)
	if not burning:
		# One flash from its own light, dying with the burst.
		light.light_color = blink_color
		light.light_energy = blink_glow * 2.0
		tween.tween_property(light, "light_energy", 0.0, 0.3)


func _make_shard_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# Pieces are closed solids, but cheap enough to draw from both sides, which
	# saves caring about winding.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.35
	m.roughness = 0.7
	m.albedo_color = blink_color
	m.emission_enabled = true
	m.emission = blink_color
	m.emission_energy_multiplier = blink_glow
	return m


## The first shatter stalled its frame (79 ms measured): the double-sided shard
## material compiling on first draw. So the first crier to come up cuts the
## pieces and draws one speck of a piece in that material in front of the
## camera, once, while the level is still loading.
static var _warmed := false

func _warm_up() -> void:
	if _warmed or mesh == null or mesh.mesh == null:
		return
	var player := Coop.all()[0] if Coop.count() > 0 else get_tree().get_first_node_in_group("player")
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
	# rides the view without lagging a frame behind it -- lens to the eyes.
	if _state == FACE and not _dying and _player != null and is_instance_valid(_player):
		global_position = _face_point(_player)
		var cam: Camera3D = _player.get("camera")
		if cam != null:
			global_basis = cam.global_basis.orthonormalized() * Basis(Vector3.UP, PI)
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


## The head cut into SHARD_COUNT chunks: each triangle goes to the nearest of
## SHARD_COUNT directions spread over the sphere, and each group is closed into
## a solid -- its outer facets, the same pulled in to SHARD_DEPTH, and walls
## along its open edges. Returns [mesh centred on itself, its centre, its
## direction] per piece.
static func _pieces(source: Mesh) -> Array:
	if _shard_cache.has(source):
		return _shard_cache[source]
	var tris: Array = []
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index = arrays[Mesh.ARRAY_INDEX]
		if index == null or (index as PackedInt32Array).is_empty():
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


func _flash() -> void:
	if _plate_material == null or _state == FACE:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_plate_material.emission = Color(0.9, 0.85, 0.75)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_plate_material, "emission", Color.BLACK, 0.15)


func _paint(colour: Color, glow: float) -> void:
	if _material != null:
		_material.albedo_color = colour
		if _material.emission_enabled:
			_material.emission = colour
			_material.emission_energy_multiplier = glow
	light.light_color = colour
	light.light_energy = glow


# --- The old warden bot's head pieces ---------------------------------------------
## The bots became the ENFORCERS (2026-10-15), a rigged model (enforcer.gd); the
## crier keeps the old bot's head, so the primitives and plates it was made of
## live here now.

static var _robot_mats := {}


static func _robot_box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _robot_cyl(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = maxi(sides, 4)
	c.rings = 1
	return c


static func _robot_mat(key: StringName) -> StandardMaterial3D:
	if _robot_mats.has(key):
		return _robot_mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"plate":
			m.albedo_color = Color(0.36, 0.24, 0.16)
			m.metallic = 0.35
			m.roughness = 0.82
		&"brass":
			m.albedo_color = Color(0.56, 0.42, 0.18)
			m.metallic = 0.55
			m.roughness = 0.5
		&"dark":
			m.albedo_color = Color(0.07, 0.06, 0.05)
			m.roughness = 0.9
	_robot_mats[key] = m
	return m
