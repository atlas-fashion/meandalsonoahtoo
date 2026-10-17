extends "res://scripts/enemy.gd"

## The SEWER LIZARD (2026-10-16): the sewer's common vermin -- a slimy lizard,
## glistening and mottled with a faint radioactive glow, that keeps its distance
## and spits radioactive goo (goo.gd): SPIT_DAMAGE a gob, one every SPIT_EVERY.
## A placeholder until there is a design: built from primitives here and animated
## in code -- the spine snaking side to side as it runs, the tail sweeping after
## it, the legs paddling in diagonal pairs, the head rearing back to spit.
##
## Put on an enemy.tscn instance before it enters the tree, like the archer and
## the enforcers (maze.gd `_spawn_sewer_lizards`, in sewer cells only).
##
## Hunting (`_chase`): beyond KEEP_FAR, or with no line to the player, it comes
## on along the sewer's navmesh; inside KEEP_NEAR it scuttles back; in between it
## holds and sidles. Whenever it has a clear line within SPIT_RANGE it rears up
## (SPIT_WINDUP, its throat glowing) and spits -- the gob lobbed to land where the
## player will be. Small and low: look down to cut it.

const GOO_SCRIPT := preload("res://scripts/goo.gd")
const ENF := preload("res://scripts/enforcer.gd")
const SPLIT_Y := -4.0
const SPIT_DAMAGE := 5.0
const SPIT_EVERY := 1.0
const SPIT_WINDUP := 0.24
const SPIT_RANGE := 16.0
const SPIT_SPEED := 12.0
const KEEP_NEAR := 4.5
const KEEP_FAR := 10.0
const RUN_SPEED := 4.2
## Its glow: the goo's green, much fainter.
const GLOW := Color(0.55, 1.0, 0.18)

var sewer: Node3D = null

var _built := false
var _rig: Node3D
var _parts: Array[MeshInstance3D] = []
var _chest: Node3D
var _hips: Node3D
var _head: Node3D
var _jaw: Node3D
var _throat: MeshInstance3D
var _throat_mat: StandardMaterial3D
var _tail: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _state_proxy: MeshInstance3D
var _phase := 0.0
var _rear := 0.0
var _spit_at := 0.0
var _windup_until := -1.0
var _side := 1.0
var _side_at := 0.0
## Spits fired (for the tests).
var spits := 0

static var _skin: StandardMaterial3D
static var _eye_mat: StandardMaterial3D


func _init() -> void:
	armed = false
	max_health = 30.0
	move_speed = RUN_SPEED
	acceleration = 18.0
	vision_cone_degrees = 170.0
	sight_needs_line_of_sight = true
	sight_memory = 5.0
	eye_height = 0.35
	aggro_range = 24.0
	wanders = true
	wander_speed = 1.1
	can_slam = false
	can_spin = false
	can_lunge = false
	can_normal = false
	knockback_resistance = 0.0
	tint_albedo = false
	base_glow = 0.0
	hit_punch = 0.0
	dormant_range = 40.0
	display_name = "SEWER LIZARD"
	drop_rolls_min = 0
	drop_rolls_max = 1
	drop_odds = {&"bone_fragment": 0.3, &"health_potion": 0.08}


# --- The body ---------------------------------------------------------------------

func _enter_tree() -> void:
	if _built:
		return
	_built = true
	var vis := get_node_or_null("Visual") as Node3D
	if vis == null:
		vis = Node3D.new()
		vis.name = "Visual"
		add_child(vis)
		move_child(vis, 0)
	for child in vis.get_children():
		vis.remove_child(child)
		child.free()
	_build_lizard(vis)
	_state_proxy = MeshInstance3D.new()
	_state_proxy.name = "StateProxy"
	_state_proxy.mesh = SphereMesh.new()
	_state_proxy.visible = false
	vis.add_child(_state_proxy)
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		cap.height = 0.85
		cs.shape = cap
		cs.position = Vector3(0.0, 0.43, 0.0)
	var ag := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if ag != null:
		ag.radius = 0.35
		ag.height = 0.85


func _ready() -> void:
	_state_proxy.material_override = StandardMaterial3D.new()
	mesh = _state_proxy
	super()
	name = "SewerLizard"
	add_to_group(&"sewer_lizards")
	_spit_at = _now() + randf_range(0.3, 1.0)


static func _materials() -> void:
	if _skin != null:
		return
	# Slime: dark wet green, a mirror clearcoat, and a faint radioactive mottle
	# in the emission.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var mottle := NoiseTexture2D.new()
	mottle.width = 256
	mottle.height = 256
	mottle.seamless = true
	mottle.noise = noise
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.58, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(0, 0, 0), Color(0, 0, 0), GLOW * 0.6, GLOW])
	mottle.color_ramp = ramp
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = Color(0.1, 0.17, 0.06)
	_skin.roughness = 0.22
	_skin.metallic_specular = 0.7
	_skin.clearcoat_enabled = true
	_skin.clearcoat = 1.0
	_skin.clearcoat_roughness = 0.04
	_skin.rim_enabled = true
	_skin.rim = 0.35
	_skin.rim_tint = 0.6
	_skin.emission_enabled = true
	_skin.emission = Color(1, 1, 1)
	_skin.emission_texture = mottle
	# Multiplied, not the default ADD (which put white under the whole mottle).
	_skin.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	_skin.emission_energy_multiplier = 0.7
	_skin.uv1_triplanar = true
	_skin.uv1_scale = Vector3.ONE * 2.2
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(1.0, 0.95, 0.3) * 1.8


func _blob(parent: Node3D, size: Vector3, at: Vector3, mat: Material = null) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 14
	s.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.scale = size
	mi.position = at
	mi.material_override = mat if mat != null else _skin
	parent.add_child(mi)
	_parts.append(mi)
	return mi


## Built facing -Z (as every enemy faces), its belly 8 cm off the floor.
func _build_lizard(vis: Node3D) -> void:
	_materials()
	_rig = Node3D.new()
	_rig.name = "Lizard"
	vis.add_child(_rig)
	_chest = Node3D.new()
	_chest.position = Vector3(0.0, 0.24, -0.1)
	_rig.add_child(_chest)
	_blob(_chest, Vector3(0.3, 0.2, 0.42), Vector3(0, 0, -0.04))
	_hips = Node3D.new()
	_hips.position = Vector3(0.0, 0.22, 0.2)
	_rig.add_child(_hips)
	_blob(_hips, Vector3(0.26, 0.18, 0.36), Vector3(0, 0, 0.02))
	# Head: a flat wedge of a skull, a jaw that drops, eyes up on top, and a
	# throat that swells and glows before a spit.
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.04, -0.26)
	_chest.add_child(_head)
	_blob(_head, Vector3(0.2, 0.12, 0.3), Vector3(0, 0.02, -0.12))
	_jaw = Node3D.new()
	_jaw.position = Vector3(0.0, -0.025, -0.02)
	_head.add_child(_jaw)
	_blob(_jaw, Vector3(0.17, 0.06, 0.26), Vector3(0, -0.01, -0.12))
	for s: float in [-1.0, 1.0]:
		var e := _blob(_head, Vector3(0.045, 0.045, 0.045), Vector3(s * 0.07, 0.065, -0.14), _eye_mat)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_throat_mat = StandardMaterial3D.new()
	_throat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_throat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_throat_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_throat_mat.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.0)
	_throat = _blob(_head, Vector3(0.12, 0.08, 0.14), Vector3(0, -0.035, -0.08), _throat_mat)
	_throat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Tail: a chain of shrinking segments, each a joint of its own.
	var parent: Node3D = _hips
	var at := Vector3(0.0, -0.01, 0.2)
	for i in 7:
		var seg := Node3D.new()
		seg.position = at
		parent.add_child(seg)
		var r := lerpf(0.13, 0.03, float(i) / 6.0)
		_blob(seg, Vector3(r, r * 0.8, 0.2), Vector3(0, 0, 0.08))
		_tail.append(seg)
		parent = seg
		at = Vector3(0.0, -0.004, 0.15)
	# Legs: splayed out to the sides, elbows up, as a lizard's are.
	for spot in [Vector3(-0.15, -0.02, -0.08), Vector3(0.15, -0.02, -0.08), Vector3(-0.13, -0.02, 0.06), Vector3(0.13, -0.02, 0.06)]:
		var host: Node3D = _chest if spot.z < 0.0 else _hips
		var leg := Node3D.new()
		leg.position = spot
		host.add_child(leg)
		var s: float = signf(spot.x)
		_blob(leg, Vector3(0.18, 0.06, 0.07), Vector3(s * 0.08, 0.02, 0.0))
		var shin := Node3D.new()
		shin.position = Vector3(s * 0.16, 0.03, 0.0)
		leg.add_child(shin)
		_blob(shin, Vector3(0.06, 0.2, 0.06), Vector3(s * 0.01, -0.09, 0.0))
		_blob(shin, Vector3(0.09, 0.03, 0.11), Vector3(s * 0.02, -0.19, -0.02))
		_legs.append(leg)
	for mi in _parts:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mi == _throat else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- Each tick ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if not _dying and not _dormant:
		_animate(delta)


func _can_see(player: Node3D, distance: float) -> bool:
	if _other_level(player):
		return false
	return super(player, distance)


func _chase(delta: float, now: float, player: Node3D, flat: Vector3, distance: float, _gap: float) -> bool:
	if _other_level(player):
		_hold(delta)
		return true
	var clear := _clear_to(player)
	if _windup_until > 0.0:
		# Rearing to spit: planted, turned on them.
		_hold(delta)
		_face(flat)
		if now >= _windup_until:
			_windup_until = -1.0
			_spit(player)
		return true
	if clear and distance <= SPIT_RANGE and now >= _spit_at:
		_windup_until = now + SPIT_WINDUP
		_spit_at = now + SPIT_EVERY
		_hold(delta)
		_face(flat)
		return true
	if distance < KEEP_NEAR:
		# Too close: scuttle back, still facing them.
		_walk_to(delta, now, global_position - flat.normalized() * 4.0, RUN_SPEED)
		_face(flat)
	elif distance > KEEP_FAR or not clear:
		_walk_to(delta, now, player.global_position, RUN_SPEED)
		_face_velocity(flat)
	else:
		# In range: sidle, changing its mind now and then.
		if now >= _side_at:
			_side_at = now + randf_range(0.8, 2.0)
			_side = -_side if randf() < 0.6 else _side
		var across := Vector3(-flat.z, 0.0, flat.x).normalized() * _side
		_walk_to(delta, now, global_position + across * 2.0, RUN_SPEED * 0.45)
		_face(flat)
	return true


func _walk_to(delta: float, now: float, goal: Vector3, speed: float) -> void:
	var to := goal - global_position
	to.y = 0.0
	var dir := to.normalized() if to.length_squared() > 0.0001 else Vector3.ZERO
	if agent != null:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = goal
		if not agent.is_navigation_finished():
			var step := agent.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.1:
				dir = step.normalized()
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	move_and_slide()


func _face_velocity(fallback: Vector3) -> void:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	_face(v if v.length_squared() > 0.25 else fallback)


func _hold(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	move_and_slide()


func _clear_to(player: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_mouth(), player.global_position + Vector3(0.0, 1.0, 0.0), 2 | 256)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _mouth() -> Vector3:
	return _head.global_position + (-_head.global_basis.z) * 0.26 if _head != null else global_position + Vector3(0, 0.3, 0)


## The gob, lobbed to land on where the player will be when it gets there.
func _spit(player: Node3D) -> void:
	var from := _mouth()
	var target := player.global_position + Vector3(0.0, 0.95, 0.0)
	var flight := clampf(from.distance_to(target) / SPIT_SPEED, 0.2, 1.4)
	var v = player.get("velocity")
	if v is Vector3:
		target += Vector3((v as Vector3).x, 0.0, (v as Vector3).z) * flight * 0.8
	GOO_SCRIPT.fire(get_parent(), from, target, self, SPIT_DAMAGE, flight)
	spits += 1
	_rear = -1.0


## Spine, tail, legs and head, from how fast it moves and whether it is spitting.
func _animate(delta: float) -> void:
	var v := get_real_velocity()
	var speed := Vector2(v.x, v.z).length()
	var run := clampf(speed / RUN_SPEED, 0.0, 1.0)
	_phase += delta * (2.0 + speed * 4.2)
	var wave := sin(_phase)
	_chest.rotation.y = wave * 0.28 * run
	_hips.rotation.y = -wave * 0.24 * run
	for i in _tail.size():
		_tail[i].rotation.y = sin(_phase - float(i) * 0.7) * (0.18 + 0.32 * run)
	for i in _legs.size():
		# Diagonal pairs: front-left with rear-right.
		var p := _phase + (0.0 if i == 0 or i == 3 else PI)
		var s := -1.0 if i % 2 == 0 else 1.0
		_legs[i].rotation = Vector3(0.0, sin(p) * 0.7 * run * -s, (0.25 + 0.3 * maxf(0.0, cos(p)) * run) * s)
	# Breathing when still; rearing back to spit, then snapping forward.
	var now := _now()
	var winding := _windup_until > 0.0
	var k := 0.0
	if winding:
		k = 1.0 - clampf((_windup_until - now) / SPIT_WINDUP, 0.0, 1.0)
	_rear = move_toward(_rear, 0.0, delta * 6.0)
	_head.rotation.x = 0.45 * k + 0.35 * _rear + sin(now * 2.3) * 0.03
	_jaw.rotation.x = -0.55 * k - 0.4 * absf(minf(_rear, 0.0))
	_chest.rotation.x = 0.12 * k
	_throat.scale = Vector3(0.12, 0.08, 0.14) * (1.0 + 0.7 * k)
	_throat_mat.albedo_color.a = 0.9 * k
	_rig.position.y = sin(now * 2.0) * 0.004 + 0.012 * run * absf(sin(_phase))


# --- Blows and death ---------------------------------------------------------------

func _flash() -> void:
	var flash := ENF._mat(&"flash")
	for mi in _parts:
		if is_instance_valid(mi):
			mi.material_overlay = flash
	get_tree().create_timer(0.08).timeout.connect(_unflash)


func _unflash() -> void:
	for mi in _parts:
		if is_instance_valid(mi):
			mi.material_overlay = null


## Flipped on its back, legs curling, a burst of goo, and gone.
func _die() -> void:
	_dying = true
	died.emit()
	shape.disabled = true
	_grant_drop()
	var parent := get_parent()
	if parent != null:
		var g := GOO_SCRIPT.fire(parent, global_position + Vector3(0, 0.3, 0), global_position + Vector3(0, 0.25, 0), self, 0.0, 0.2)
		g.call("_splash", global_position + Vector3(0, 0.2, 0), Vector3.UP)
	var t := create_tween().set_parallel(true)
	t.tween_property(_rig, "rotation:z", PI * 0.92, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_rig, "position:y", 0.3, 0.2)
	for leg in _legs:
		t.tween_property(leg, "rotation:x", 0.9, 0.5)
	var gone := create_tween()
	gone.tween_interval(2.2)
	gone.tween_property(self, "scale", Vector3(1.0, 0.01, 1.0), 0.3)
	gone.tween_callback(queue_free)


## Wandering the sewer cell to cell along its navmesh, stopping to look about.
func _wander(delta: float, now: float) -> Vector3:
	if sewer == null or not is_instance_valid(sewer):
		return super(delta, now)
	if now < _wander_pause_until:
		return Vector3.ZERO
	if not _has_wander_target:
		var map = sewer.get("map")
		if map == null:
			return Vector3.ZERO
		var here: Vector3 = global_position - map.origin
		var cs: float = map.cell_size
		var cell := Vector2i(roundi(here.x / cs), roundi(here.z / cs))
		var near: Array = []
		for k: Vector2i in map.cells:
			var dd := absi(k.x - cell.x) + absi(k.y - cell.y)
			if dd >= 1 and dd <= 4:
				near.append(k)
		if near.is_empty():
			return Vector3.ZERO
		_wander_target = map.to_world(near[randi() % near.size()]) + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
		_has_wander_target = true
	var to := _wander_target - global_position
	to.y = 0.0
	if to.length() < 1.0:
		_has_wander_target = false
		_wander_pause_until = now + randf_range(1.0, 4.0)
		return Vector3.ZERO
	var dir := to.normalized()
	if agent != null:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = _wander_target
		if not agent.is_navigation_finished():
			var step := agent.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.1:
				dir = step.normalized()
	_face(dir)
	return dir * wander_speed


## Not drawn while the camera is above ground (12 m of stone between): its ~30
## small parts were otherwise still in every dungeon torch's shadow pass.
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and visual != null:
		# On a different level from the camera (12 m of stone between): hidden.
		visual.visible = (cam.global_position.y < SPLIT_Y) == (global_position.y < SPLIT_Y)


## The player is on the other side of the sewer roof from it. Sewer dwellers
## neither see nor chase anyone above ground; one placed above ground (the
## sandbox's test plane, sandbox_world.gd) hunts there as it would below.
func _other_level(player: Node3D) -> bool:
	return (player.global_position.y > SPLIT_Y) != (global_position.y > SPLIT_Y)
