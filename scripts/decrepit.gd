extends "res://scripts/enemy.gd"

## The DECREPIT ENFORCER (2026-10-15): a rotted, hunched, one-armed enforcer
## gone feral in the sewer, its arm a great pointed shield. Only ever one at a
## time, and only in the sewer (maze.gd `_spawn_decrepit`).
##
## The model and its animations are the user's (`models/decrepit.glb`, built by
## tools/build_decrepit.py from models/source/enforcer/PUTRID_ENFORCER_BAKED.blend):
## three BAKED clips -- CRAWL_BAKED, a loping crawl (wandering, slow; hunting,
## frantic), STABS_BAKED, the shield driven forward in three thrusts (the SHIELD
## SLAM), and JUMP_BAKED, a leap that brings the shield's point down into the
## floor (the JUMP SLASH). The build takes the root motion out of the slam and
## the jump, so they play in place, and prints their travel as the ROOT_* tables
## here: the body is moved along them (scaled, for the jump, to land on its
## target), so the feet stay where the clip puts them and nothing snaps back.
##
## Like the enforcer, the script is put on an enemy.tscn instance before it
## enters the tree; it throws the skeleton away for its own model. Clip changes
## are cross-faded by its reaction layer (decrepit_react.gd, the enforcer's layer
## with this creature's own clips), so every clip flows into every other.
##
## Hunting (`_chase`), fast -- CHASE_SPEED, against the player's 4.25 walk:
##   * close in: the SHIELD SLAM. Each thrust can land once; the first that
##     lands deals SLAM_DAMAGE and, unguarded, throws the player off their feet
##     (`player.knock_down`, SLAM_THROW) -- and straight away it LEAPS on them
##     where they fell: the jump slash, re-aimed through its flight to land its
##     point on them while they are down. A held guard takes the slam standing
##     (a tenth through), shoved back.
##   * at JUMP_MIN..JUMP_MAX with a clear floor between: now and then the JUMP
##     SLASH on its own, JUMP_DAMAGE where the point comes down.
##   * a PARRY of either throws it on its back (the whole body toppled about its
##     heels, the limbs flailing over it), it lies there KNOCK_LIE, then it is up
##     fast and straight back into the attack.
## Every blow that lands throws sparks off its plating (the enforcer's) and plays
## one of three hit reactions at random.
##
## It walks on its own floor over the sewer's channels (sewer.gd FERAL_FLOOR,
## layer 14, which nothing else collides with), straddling the water, and paths
## on the sewer's navmesh, baked from that floor and the stone.

const ENF := preload("res://scripts/enforcer.gd")
const REACT := preload("res://scripts/decrepit_react.gd")
const MODEL := preload("res://models/decrepit.glb")
## The mesh crouches ~4 m tall at the authored size; drawn at ~2.6 m.
const MODEL_SCALE := 0.65
const MODEL_LIFT := -0.03
const CLIP_CRAWL := &"CRAWL_BAKED"
const CLIP_SLAM := &"STABS_BAKED"
const CLIP_JUMP := &"JUMP_BAKED"
## Layer of the sewer's channel-spanning floor, which only this collides with.
const FERAL_FLOOR := 1 << 13
## Below this the player is in the sewer (sewer.gd SPLIT_Y).
const SPLIT_Y := -4.0
## The crawl's planted feet slide back at 4.886 m/s at the authored size.
const CRAWL_GROUND := 4.886 * MODEL_SCALE
const CHASE_SPEED := 7.4
const WANDER_SPEED := 2.4

const SLAM_DAMAGE := 25.0
const JUMP_DAMAGE := 50.0
## How hard an unguarded slam throws the player.
const SLAM_THROW := 12.0
## A guarded blow shoves the player back this hard.
const BLOCK_SHOVE := 5.0
## The slam's three thrusts reach furthest at these clip times (STABS_BAKED
## frames 28, 45, 72); the reach at each, from the body, is SLAM_REACH.
const SLAM_HITS := [0.45, 0.733, 1.183]
const SLAM_REACH := 2.45
const SLAM_TRIGGER := 2.9
const SLAM_END := 1.45
## After a thrust connects (or is guarded) the slam is over this much later.
const SLAM_AFTER := 0.28
const SLAM_COOLDOWN := 1.3
## The jump's point is in the floor at this clip time (JUMP_BAKED frame 43),
## JUMP_TIP ahead of the body (in place); the clip's travel by then is
## JUMP_ROOT_AT_HIT (authored units).
const JUMP_CONTACT := 0.70
const JUMP_TIP := 2.61 * MODEL_SCALE
const JUMP_ROOT_AT_HIT := 1.045
const JUMP_END := 1.5
const JUMP_MIN := 4.0
const JUMP_MAX := 9.0
## As far as it will leap onto a player it has just knocked down.
const JUMP_COMBO_MAX := 12.0
const JUMP_COOLDOWN := 3.5
## After the point lands it barely moves on (the clip's own drift, scaled).
const JUMP_AFTER := 0.3
const TURN_SLAM := 12.0
const TURN_JUMP := 7.0
## Parried: it topples back about its heels, lies, and is up again.
const KNOCK_FALL := 0.4
const KNOCK_LIE := 1.0
const KNOCK_RISE := 0.55
const KNOCK_PITCH := 1.32
const KNOCK_PIVOT := Vector3(0.0, 0.0, 0.55)
const EYE_RADIUS := 0.03
const EYE_COLOUR := Color(1.0, 0.56, 0.14)
## Its eyes cast a faint glow ahead of its face: without it, in this dark, the
## body was not there at all -- two points of light and nothing to read an attack
## by.
const GLOW_ENERGY := 0.9
const GLOW_RANGE := 4.2
const GLOW_AHEAD := Vector3(0.0, 1.85, -0.75)

## The clips' travel (build_decrepit.py), every 2 frames: [seconds, forward, left].
const ROOT_SLAM := [[0.0, 0.0, 0.0], [0.0333, 0.001, 0.0], [0.0667, 0.005, 0.002], [0.1, 0.019, 0.009],
	[0.1333, 0.051, 0.023], [0.1667, 0.113, 0.052], [0.2, 0.221, 0.102], [0.2333, 0.391, 0.181],
	[0.2667, 0.392, 0.182], [0.3, 0.4, 0.188], [0.3333, 0.433, 0.216], [0.3667, 0.523, 0.292],
	[0.4, 0.714, 0.452], [0.4333, 0.835, 0.452], [0.4667, 0.927, 0.452], [0.5, 0.942, 0.452],
	[0.5333, 0.927, 0.452], [0.5667, 0.832, 0.452], [0.6, 0.714, 0.452], [0.6333, 0.715, 0.452],
	[0.6667, 0.728, 0.452], [0.7, 0.768, 0.452], [0.7333, 0.863, 0.452], [0.7667, 0.942, 0.452],
	[0.8, 0.934, 0.452], [0.8333, 0.882, 0.452], [0.8667, 0.714, 0.452], [0.9, 0.714, 0.452],
	[0.9333, 0.714, 0.452], [0.9667, 0.714, 0.452], [1.0, 0.715, 0.452], [1.0333, 0.727, 0.452],
	[1.0667, 0.766, 0.452], [1.1, 0.856, 0.452], [1.1333, 1.032, 0.452], [1.1667, 1.165, 0.452],
	[1.2, 1.165, 0.452], [1.2333, 1.165, 0.452], [1.2667, 1.165, 0.452], [1.3, 1.164, 0.452],
	[1.3333, 1.163, 0.451], [1.3667, 1.159, 0.45], [1.4, 1.15, 0.446], [1.4333, 1.135, 0.44],
	[1.4667, 1.109, 0.43], [1.5, 1.07, 0.415], [1.5333, 1.014, 0.393], [1.5667, 0.935, 0.363],
	[1.6, 0.828, 0.321], [1.6333, 0.688, 0.267], [1.6667, 0.508, 0.197], [1.7, 0.281, 0.109],
	[1.7333, 0.0, 0.0]]
const ROOT_JUMP := [[0.0, 0.0, 0.0], [0.0333, 0.0, 0.0], [0.0667, 0.001, -0.002], [0.1, 0.004, -0.006],
	[0.1333, 0.011, -0.017], [0.1667, 0.025, -0.037], [0.2, 0.049, -0.072], [0.2333, 0.087, -0.128],
	[0.2667, 0.143, -0.211], [0.3, 0.223, -0.329], [0.3333, 0.289, -0.403], [0.3667, 0.325, -0.403],
	[0.4, 0.38, -0.402], [0.4333, 0.38, -0.402], [0.4667, 0.383, -0.401], [0.5, 0.397, -0.395],
	[0.5333, 0.434, -0.378], [0.5667, 0.511, -0.344], [0.6, 0.652, -0.281], [0.6333, 0.884, -0.178],
	[0.6667, 1.045, -0.107], [0.7, 1.045, -0.107], [0.7333, 1.045, -0.107], [0.7667, 1.049, -0.107],
	[0.8, 1.084, -0.107], [0.8333, 1.146, -0.107], [0.8667, 1.231, -0.107], [0.9, 1.332, -0.107],
	[0.9333, 1.443, -0.107], [0.9667, 1.556, -0.107], [1.0, 1.667, -0.107], [1.0333, 1.769, -0.107],
	[1.0667, 1.858, -0.107], [1.1, 1.943, -0.107], [1.1333, 2.036, -0.107], [1.1667, 2.147, -0.107],
	[1.2, 2.281, -0.107], [1.2333, 2.407, -0.107], [1.2667, 2.488, -0.107], [1.3, 2.5, -0.107],
	[1.3333, 2.498, -0.107], [1.3667, 2.492, -0.107], [1.4, 2.478, -0.107], [1.4333, 2.454, -0.107],
	[1.4667, 2.417, -0.107], [1.5, 2.363, -0.107], [1.5333, 2.29, -0.107], [1.5667, 2.195, -0.107],
	[1.6, 2.195, -0.107], [1.6333, 2.195, -0.107], [1.6667, 2.195, -0.107], [1.7, 2.195, -0.107],
	[1.7333, 2.195, -0.107]]

enum Move { NONE, SLAM, JUMP }

## The sewer it hunts (maze.gd), for wandering cell to cell.
var sewer: Node3D = null

var _built := false
var _model: Node3D
var _parts: Array[MeshInstance3D] = []
var _tip: Node3D
var _state_proxy: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _react: SkeletonModifier3D
var _clip := &""
var _visual_rest := Transform3D.IDENTITY

var _move := Move.NONE
var _move_t := 0.0
var _root_prev := Vector2.ZERO
var _thrusts_tried := 0
var _connected := false
var _end_at := INF
var _guard_seen := -1
var _target: Node3D = null
var _slam_ready := 0.0
var _jump_ready := 0.0
var _jump_roll_at := 0.0
var _twitch_at := 0.0
## Seconds into a parried knock-down, or -1.
var _knock_t := -1.0
## How many jump slashes followed a knock-down (for the tests).
var combos := 0


func _init() -> void:
	armed = false
	max_health = 150.0
	move_speed = CHASE_SPEED
	acceleration = 30.0
	vision_cone_degrees = 150.0
	sight_needs_line_of_sight = true
	sight_memory = 8.0
	eye_height = 1.9
	aggro_range = 40.0
	wanders = true
	wander_speed = WANDER_SPEED
	can_slam = false
	can_spin = false
	can_lunge = false
	can_normal = false
	attack_damage = SLAM_DAMAGE
	knockback_resistance = 0.35
	tint_albedo = false
	base_glow = 0.0
	hit_punch = 0.0
	dormant_range = 50.0
	display_name = "DECREPIT ENFORCER"
	drop_rolls_min = 1
	drop_rolls_max = 2
	drop_odds = {&"gold_crystal": 0.45, &"bone_fragment": 0.4, &"health_potion": 0.2}


func is_decrepit() -> bool:
	return true


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
	_model = MODEL.instantiate() as Node3D
	_model.name = "Decrepit"
	# Authored facing +Z; enemies face -Z.
	_model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * MODEL_SCALE),
		Vector3(0.0, MODEL_LIFT, 0.0))
	vis.add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_parts.append(m)
	_tip = _model.find_child("ShieldTip", true, false) as Node3D
	# enemy.gd tints the material of its `mesh` by state; this one keeps its own
	# colours, so that machinery gets a proxy that is never drawn.
	_state_proxy = MeshInstance3D.new()
	_state_proxy.name = "StateProxy"
	_state_proxy.mesh = SphereMesh.new()
	_state_proxy.visible = false
	vis.add_child(_state_proxy)
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.55
		cap.height = 2.4
		cs.shape = cap
		cs.position = Vector3(0.0, 1.2, 0.0)
	collision_mask |= FERAL_FLOOR
	var ag := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if ag != null:
		ag.radius = 0.6
		ag.height = 2.4
		ag.path_desired_distance = 0.8


func _ready() -> void:
	var plain := StandardMaterial3D.new()
	_state_proxy.material_override = plain
	mesh = _state_proxy
	super()
	name = "DecrepitEnforcer"
	add_to_group(&"decrepits")
	_visual_rest = visual.transform
	_setup_clips()
	_attach_eyes()
	_attach_react()
	_warm_sparks.call_deferred()
	_twitch_at = _now() + randf_range(0.6, 1.8)


func _setup_clips() -> void:
	if anim == null:
		return
	if anim.has_animation(CLIP_CRAWL):
		anim.get_animation(CLIP_CRAWL).loop_mode = Animation.LOOP_LINEAR
	for c in [CLIP_SLAM, CLIP_JUMP]:
		if anim.has_animation(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_NONE
	_play_clip(CLIP_CRAWL, 0.0, 0.0)


## Plays `clip` at `rate`; switching clips cross-fades over `blend` on the
## reaction layer (see enforcer.gd `_play_clip`: the AnimationPlayer's own fade
## stalls into a clip held still and lurches at the start of others).
func _play_clip(clip: StringName, rate: float, blend := 0.2, restart := false) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if _clip == clip and not restart and anim.is_playing():
		anim.speed_scale = rate
		return
	if _react != null:
		_react.call("crossfade", blend)
	_clip = clip
	anim.play(clip, 0.0, 1.0)
	anim.speed_scale = rate
	anim.seek(0.0, true)


## Two small amber points in the mask's pale eyes: it hunts in the dark, and
## they are how it is first seen.
func _attach_eyes() -> void:
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = EYE_COLOUR * 1.5
	var glow := OmniLight3D.new()
	glow.name = "EyeGlow"
	glow.light_color = EYE_COLOUR
	glow.light_energy = GLOW_ENERGY
	glow.omni_range = GLOW_RANGE
	glow.omni_attenuation = 1.3
	glow.shadow_enabled = false
	glow.light_specular = 0.5
	glow.light_cull_mask = (1 << 15) | 1
	glow.position = GLOW_AHEAD
	add_child(glow)
	for n in ["EyeL", "EyeR"]:
		var marker := _model.find_child(n, true, false) as Node3D
		if marker == null:
			continue
		var s := SphereMesh.new()
		var scale_world := marker.global_basis.get_scale().x if marker.is_inside_tree() else MODEL_SCALE * 1.746
		s.radius = EYE_RADIUS / maxf(scale_world, 0.001)
		s.height = s.radius * 2.0
		s.radial_segments = 10
		s.rings = 5
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = _eye_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.add_child(mi)


func _attach_react() -> void:
	var sk := _model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	_react = REACT.new()
	_react.name = "HitReact"
	(sk[0] as Skeleton3D).add_child(_react)


# --- Each tick ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dying:
		super(delta)
		return
	var now := _now()
	if _knock_t >= 0.0:
		_run_knockdown(delta, now)
		return
	if _move != Move.NONE:
		if now < _stun_until:
			# Knocked out of it by a blow (the player's stagger roll).
			_end_move()
		else:
			if not is_on_floor():
				velocity += get_gravity() * delta
			_advance_anim(delta)
			_run_move(delta, now)
			return
	super(delta)
	if not _dying and not _dormant and _knock_t < 0.0 and _move == Move.NONE:
		_animate(delta)


## Not above ground: it lives down here.
func _can_see(player: Node3D, distance: float) -> bool:
	if player.global_position.y > SPLIT_Y:
		return false
	return super(player, distance)


func _chase(delta: float, now: float, player: Node3D, flat: Vector3, distance: float, _gap: float) -> bool:
	if player.global_position.y > SPLIT_Y:
		_hold(delta)
		return true
	if now >= _twitch_at:
		_twitch_at = now + randf_range(0.7, 2.2)
		if _react != null:
			_react.call("twitch", player.global_position)
	var dy := absf(player.global_position.y - global_position.y)
	if now >= _slam_ready and distance <= SLAM_TRIGGER and dy < 1.6 and _clear_to(player, 1.3):
		_start_move(Move.SLAM, player)
		return true
	if now >= _jump_ready and now >= _jump_roll_at and distance >= JUMP_MIN and distance <= JUMP_MAX and dy < 1.2:
		_jump_roll_at = now + 0.35
		if randf() < 0.45 and _clear_to(player, 1.3) and _clear_to(player, 0.45):
			_start_move(Move.JUMP, player)
			return true
	_walk_to(delta, now, player.global_position, CHASE_SPEED)
	_face_velocity(flat)
	return true


## Wandering the sewer: from cell to cell along its navmesh, a few cells at a
## time, stopping to look about.
func _wander(delta: float, now: float) -> Vector3:
	if sewer == null or not is_instance_valid(sewer):
		return super(delta, now)
	if now < _wander_pause_until:
		_look_phase += delta * deg_to_rad(look_around_speed)
		rotation.y = _look_centre + sin(_look_phase) * deg_to_rad(look_around_degrees)
		return Vector3.ZERO
	if not _has_wander_target:
		_pick_sewer_target()
	var to := _wander_target - global_position
	to.y = 0.0
	if to.length() < 1.3:
		_has_wander_target = false
		_wander_pause_until = now + randf_range(0.8, 2.6)
		_look_centre = rotation.y
		_look_phase = 0.0
		return Vector3.ZERO
	var dir := _path_dir(now, _wander_target)
	_face(dir)
	return dir * wander_speed


func _pick_sewer_target() -> void:
	var map = sewer.get("map")
	if map == null:
		return
	var here: Vector3 = global_position - map.origin
	var cs: float = map.cell_size
	var cell := Vector2i(roundi(here.x / cs), roundi(here.z / cs))
	var keys: Array = map.cells.keys()
	var near: Array = []
	for k: Vector2i in keys:
		var d := absi(k.x - cell.x) + absi(k.y - cell.y)
		if d >= 2 and d <= 7:
			near.append(k)
	if near.is_empty():
		near = keys
	_wander_target = map.to_world(near[randi() % near.size()])
	_has_wander_target = true


func _walk_to(delta: float, now: float, goal: Vector3, speed: float) -> void:
	var dir := _path_dir(now, goal)
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	move_and_slide()


func _path_dir(now: float, goal: Vector3) -> Vector3:
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
	return dir


func _face_velocity(fallback: Vector3) -> void:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	_face(v if v.length_squared() > 0.25 else fallback)


func _hold(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	move_and_slide()


## A clear line through stone from its body to the player's, at `height`.
func _clear_to(player: Node3D, height: float) -> bool:
	var from := global_position + Vector3(0.0, height, 0.0)
	var to := player.global_position + Vector3(0.0, minf(height, 1.0), 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 2 | 256)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The crawl, at the rate that keeps its feet on the floor: slow ambling,
## frantic hunting; eased still when it stands or reels.
func _animate(delta: float) -> void:
	if is_stunned():
		if _clip != CLIP_CRAWL:
			_play_clip(CLIP_CRAWL, 0.0, 0.25, true)
		elif anim != null:
			anim.speed_scale = move_toward(anim.speed_scale, 0.0, delta * 6.0)
		return
	var v := get_real_velocity()
	var speed := Vector2(v.x, v.z).length()
	if speed > 0.2:
		_play_clip(CLIP_CRAWL, clampf(speed / CRAWL_GROUND, 0.35, 2.6), 0.2)
	else:
		if _clip != CLIP_CRAWL:
			_play_clip(CLIP_CRAWL, 0.0, 0.25, true)
		elif anim != null:
			anim.speed_scale = move_toward(anim.speed_scale, 0.0, delta * 4.0)


# --- The slam and the jump ----------------------------------------------------------

func _start_move(kind: int, player: Node3D) -> void:
	_move = kind
	_move_t = 0.0
	_root_prev = Vector2.ZERO
	_thrusts_tried = 0
	_connected = false
	_target = player
	_end_at = SLAM_END if kind == Move.SLAM else JUMP_END
	var now := _now()
	if kind == Move.SLAM:
		_slam_ready = now + SLAM_COOLDOWN
		_play_clip(CLIP_SLAM, 1.0, 0.1, true)
	else:
		_jump_ready = now + JUMP_COOLDOWN
		_play_clip(CLIP_JUMP, 1.0, 0.1, true)
	_link_guard(player)


func _end_move() -> void:
	_move = Move.NONE
	_target = null
	var v := get_real_velocity()
	_play_clip(CLIP_CRAWL, clampf(Vector2(v.x, v.z).length() / CRAWL_GROUND, 0.0, 2.6), 0.28, true)


func _run_move(delta: float, _now_t: float) -> void:
	var player := _target
	if player == null or not is_instance_valid(player):
		_end_move()
		return
	var prev := _move_t
	_move_t += delta
	var table: Array = ROOT_SLAM if _move == Move.SLAM else ROOT_JUMP
	var r := _root_at(table, _move_t)
	var d := r - _root_prev
	_root_prev = r
	var to := player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var fwd := d.x * MODEL_SCALE
	var left := d.y * MODEL_SCALE
	if _move == Move.JUMP:
		if _move_t < JUMP_CONTACT:
			# Scaled so the point comes down on them: what travel is left before
			# it lands, against how far they are past where it would.
			var left_root := (JUMP_ROOT_AT_HIT - r.x) * MODEL_SCALE
			var need := flat.length() - JUMP_TIP
			var k := 1.0
			if left_root + d.x * MODEL_SCALE > 0.01:
				k = clampf(need / (left_root + d.x * MODEL_SCALE), 0.0, 9.0)
			fwd *= k
		else:
			fwd *= JUMP_AFTER
	# Turning to follow them until just before each blow.
	var track_until := JUMP_CONTACT - 0.08
	var rate := TURN_JUMP
	if _move == Move.SLAM:
		rate = TURN_SLAM
		track_until = SLAM_HITS[mini(_thrusts_tried, SLAM_HITS.size() - 1)] - 0.1
	if _move_t < track_until and flat.length_squared() > 0.01:
		var want := atan2(-flat.x, -flat.z)
		rotation.y = rotate_toward(rotation.y, want, rate * delta)
	var step := -global_basis.z * fwd - global_basis.x * left
	velocity.x = step.x / delta
	velocity.z = step.z / delta
	move_and_slide()
	velocity.x = 0.0
	velocity.z = 0.0
	if _move == Move.SLAM:
		while _thrusts_tried < SLAM_HITS.size() and _move_t >= SLAM_HITS[_thrusts_tried]:
			_thrusts_tried += 1
			if not _connected:
				_try_slam(player)
	elif prev < JUMP_CONTACT and _move_t >= JUMP_CONTACT:
		_try_jump(player)
	if _move != Move.NONE and _move_t >= _end_at:
		_end_move()


static func _root_at(table: Array, t: float) -> Vector2:
	var n := table.size()
	if t <= float(table[0][0]):
		return Vector2(table[0][1], table[0][2])
	if t >= float(table[n - 1][0]):
		return Vector2(table[n - 1][1], table[n - 1][2])
	var i := 0
	while i < n - 2 and t >= float(table[i + 1][0]):
		i += 1
	var a: Array = table[i]
	var b: Array = table[i + 1]
	var u := (t - float(a[0])) / (float(b[0]) - float(a[0]))
	return Vector2(lerpf(a[1], b[1], u), lerpf(a[2], b[2], u))


## The shield's point within `reach` of the player's body (an upright segment).
func _tip_near(player: Node3D, reach: float) -> bool:
	if _tip == null:
		return false
	var p := _tip.global_position
	var base := player.global_position
	var y := clampf(p.y, base.y, base.y + 1.8)
	return p.distance_to(Vector3(base.x, y, base.z)) <= reach


func _try_slam(player: Node3D) -> void:
	var to := player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var ahead := -global_basis.z
	var off := ahead.angle_to(flat.normalized()) if flat.length_squared() > 0.0001 else 0.0
	var reach_ok := flat.length() <= SLAM_REACH + 0.45 and off <= deg_to_rad(55.0)
	if not (reach_ok or _tip_near(player, 0.85)) or absf(to.y) > 1.6 or not _clear_to(player, 1.3):
		return
	var outcome := _strike(player, SLAM_DAMAGE, flat)
	if outcome == &"miss":
		return
	_connected = true
	_end_at = minf(_end_at, _move_t + SLAM_AFTER)
	var away := flat.normalized() if flat.length_squared() > 0.0001 else ahead
	if outcome == &"hit":
		if player.has_method("knock_down"):
			player.call("knock_down", away, SLAM_THROW)
		# Down -- and it is on them before they are up.
		combos += 1
		_start_move(Move.JUMP, player)
		_end_at = JUMP_END
	elif outcome == &"blocked" and player.has_method("apply_knockback"):
		player.call("apply_knockback", away * BLOCK_SHOVE)


func _try_jump(player: Node3D) -> void:
	_impact_sparks()
	var to := player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var ahead := -global_basis.z
	var off := ahead.angle_to(flat.normalized()) if flat.length_squared() > 0.0001 else 0.0
	var reach_ok := flat.length() <= JUMP_TIP + 0.75 and off <= deg_to_rad(45.0)
	if not (reach_ok or _tip_near(player, 1.5)) or absf(to.y) > 1.5:
		return
	var outcome := _strike(player, JUMP_DAMAGE, flat)
	if outcome == &"blocked" and player.has_method("apply_knockback"):
		player.call("apply_knockback", flat.normalized() * BLOCK_SHOVE)


## Lands a blow through the player's own guard: &"hit", &"blocked", &"parried"
## or &"miss" (it did not get through -- an invulnerable moment, a hiding place).
func _strike(player: Node3D, amount: float, flat: Vector3) -> StringName:
	_guard_seen = -1
	var before = player.get("health")
	var dir := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	player.call("take_damage", amount, dir, self)
	if _guard_seen == 1:
		return &"parried"
	if _guard_seen == 0:
		return &"blocked"
	var after = player.get("health")
	if before != null and after != null and float(after) < float(before):
		return &"hit"
	return &"miss"


func _link_guard(player: Node3D) -> void:
	if player.has_signal("guarded") and not player.is_connected("guarded", _on_player_guarded):
		player.connect("guarded", _on_player_guarded)


func _on_player_guarded(parried: bool, attacker: Node3D) -> void:
	if attacker != self:
		return
	_guard_seen = 1 if parried else 0
	if parried:
		_start_knockdown()


## A player's blow that staggers it (their roll) breaks off whatever it was
## doing.
func _on_staggered() -> void:
	if _move != Move.NONE:
		_end_move()


# --- Parried: thrown on its back ------------------------------------------------------

func _start_knockdown() -> void:
	if _dying or _knock_t >= 0.0:
		return
	_move = Move.NONE
	_target = null
	_knock_t = 0.0
	_stun_until = maxf(_stun_until, _now() + KNOCK_FALL + KNOCK_LIE + KNOCK_RISE + 0.05)
	# The pose it was in, held as it goes over; the limbs flail on the layer.
	if anim != null:
		anim.speed_scale = 0.0
	var player := _resolve_player()
	if _react != null and player != null:
		_react.call("stagger", player.global_position)


func _run_knockdown(delta: float, now: float) -> void:
	_knock_t += delta
	if not is_on_floor():
		velocity += get_gravity() * delta
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	_decay_knockback(delta)
	_thrown_move()
	_advance_anim(delta)
	var pitch := _knock_pitch(_knock_t)
	var b := Basis(Vector3.RIGHT, pitch)
	visual.transform = _visual_rest * Transform3D(b, KNOCK_PIVOT - b * KNOCK_PIVOT)
	if _knock_t >= KNOCK_FALL + KNOCK_LIE + KNOCK_RISE:
		_knock_t = -1.0
		visual.transform = _visual_rest
		# Up -- and straight back at them.
		_slam_ready = now
		_jump_ready = now
		_jump_roll_at = now
		alert()
		_play_clip(CLIP_CRAWL, 1.8, 0.2, true)


## How far it is tipped back, `t` seconds after the parry: over and down
## (accelerating), a jolt on landing, still (twitching on the layer), then
## heaved up fast -- forward past upright into its crouch -- and settled.
static func _knock_pitch(t: float) -> float:
	if t < KNOCK_FALL:
		var u := t / KNOCK_FALL
		return KNOCK_PITCH * u * u
	t -= KNOCK_FALL
	if t < 0.18:
		return KNOCK_PITCH - 0.13 * sin(PI * t / 0.18)
	if t < KNOCK_LIE:
		return KNOCK_PITCH
	t -= KNOCK_LIE
	var u := clampf(t / KNOCK_RISE, 0.0, 1.0)
	if u < 0.72:
		var v := u / 0.72
		return lerpf(KNOCK_PITCH, -0.2, 1.0 - pow(1.0 - v, 3.0))
	var w := (u - 0.72) / 0.28
	return lerpf(-0.2, 0.0, w * w * (3.0 - 2.0 * w))


# --- Blows, sparks, death -------------------------------------------------------------

## Where a blow meets its plating, and the radius / height band of it a blade
## reaches.
const HIT_SURFACE := 0.55
const HIT_LOW := 0.6
const HIT_HIGH := 2.0
const HIT_FULL := 20.0


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	var was_dying := _dying
	super(amount, _from_direction)
	if not was_dying and amount > 0.0:
		_hit_sparks()
		var player := _resolve_player()
		if _react != null and player != null and not _dying:
			_react.call("hit", player.global_position, 0.55 + 0.45 * clampf(amount / HIT_FULL, 0.0, 1.0))


func _hit_point() -> Array:
	var base := global_position
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam != null else base + Vector3(0.0, 1.6, 2.0)
	var y := clampf(eye.y - 0.35, base.y + HIT_LOW, base.y + HIT_HIGH)
	var axis := Vector3(base.x, y, base.z)
	var out := Vector3(eye.x - base.x, 0.0, eye.z - base.z)
	out = out.normalized() if out.length_squared() > 0.0001 else -global_basis.z
	return [axis + out * HIT_SURFACE, out]


## The enforcer's spray of hot sparks off struck plating (enforcer.gd).
func _hit_sparks() -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var effects: bool = Graphics.effects
	var hit := _hit_point()
	var at: Vector3 = hit[0]
	var out: Vector3 = hit[1]
	var n := randi_range(ENF.HIT_SPARKS_MIN, ENF.HIT_SPARKS_MAX) if effects \
		else randi_range(ENF.HIT_SPARKS_PLAIN.x, ENF.HIT_SPARKS_PLAIN.y)
	_spark_spray(parent, at, (out + Vector3(0.0, 0.55, 0.0)).normalized(), n, effects)


## The shield's point striking the stone, hit or miss.
func _impact_sparks() -> void:
	var parent := get_parent()
	if parent == null or _tip == null or not is_inside_tree():
		return
	var effects: bool = Graphics.effects
	var at := _tip.global_position
	at.y = maxf(at.y, global_position.y + 0.05)
	_spark_spray(parent, at, Vector3.UP, randi_range(10, 20) if effects else 4, effects)


func _spark_spray(parent: Node, at: Vector3, dir: Vector3, n: int, effects: bool) -> void:
	var p := ENF._spark_burst(n)
	parent.add_child(p)
	p.global_position = at
	p.direction = dir
	p.restart()
	get_tree().create_timer(ENF.HIT_SPARK_LIFE * 1.6 + 0.2).timeout.connect(p.queue_free)
	if effects:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.38)
		light.light_energy = 2.4
		light.omni_range = 2.6
		light.shadow_enabled = false
		light.light_specular = 0.4
		parent.add_child(light)
		light.global_position = at + dir * 0.15
		var t := light.create_tween()
		t.tween_property(light, "light_energy", 0.0, 0.14).set_ease(Tween.EASE_IN)
		t.tween_callback(light.queue_free)


## The spark material compiles on first draw: a speck in front of the camera.
func _warm_sparks() -> void:
	if ENF._spark_warmed or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	ENF._spark_warmed = true
	var p := ENF._spark_burst(1)
	p.scale_amount_min = 0.01
	p.scale_amount_max = 0.01
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.gravity = Vector3.ZERO
	cam.add_child(p)
	p.position = Vector3(0.0, 0.0, -0.6)
	p.restart()
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func _flinch(_impulse: Vector3, _time: float) -> void:
	pass


## A white flash over the plating, with no squash (the reactions are the
## movement).
func _flash() -> void:
	var flash := ENF._mat(&"flash")
	for mi in _parts:
		mi.material_overlay = flash
	get_tree().create_timer(0.08).timeout.connect(_unflash)


func _unflash() -> void:
	for mi in _parts:
		if is_instance_valid(mi):
			mi.material_overlay = null


## The eyes go out, sparks spill, the rig stops where it is and it keels over
## sideways and lies a moment before it goes.
func _die() -> void:
	_dying = true
	_move = Move.NONE
	died.emit()
	shape.disabled = true
	_grant_drop()
	if anim != null:
		anim.pause()
	visual.transform = _visual_rest
	if Graphics.effects:
		_hit_sparks()
		_impact_sparks()
	if _eye_mat != null:
		create_tween().tween_property(_eye_mat, "albedo_color", Color(0.05, 0.02, 0.0), 0.5)
	var fall := create_tween().set_parallel(true)
	fall.tween_property(visual, "position:y", visual.position.y - 0.4, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(visual, "rotation:z", 1.35, 0.7).set_delay(0.15) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var gone := create_tween()
	gone.tween_interval(3.0)
	gone.tween_property(self, "scale", Vector3(1.0, 0.01, 1.0), 0.4).set_ease(Tween.EASE_IN)
	gone.tween_callback(queue_free)
