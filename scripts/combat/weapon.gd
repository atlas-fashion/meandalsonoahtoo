@tool
class_name Weapon
extends Node3D
## Base script for every weapon scene: the timing-combat template's swing system
## (C:\DEV\godot\timing-combat, note 190), which replaced every player attack.
## A weapon scene owns everything about itself:
##
##   Poses/          Marker3D nodes: places the grip can be. Move and rotate them in the 3D view.
##   Grip/           The part that animates. Holds the Model (visuals) and the Hitbox (Area3D).
##   PreviewCamera   Editor only: look through it to see the weapon as the player will.
##   swings          The attack sequence. Each Swing moves the Grip between poses.
##
## The wielder only calls request_attack() / start_attack_at() (and interrupt() when it is
## hit). All timing and animation live here, and every swing scales with hits_per_second.
## The Hitbox (an Area3D) supplies the hit shape and collision mask. Hits are found by
## sweeping that shape along the strike's path, so they don't depend on frame rate.
##
## Poses use the convention: the blade points down -Z from the grip; positive pitch is tip
## up, positive yaw is tip left. Pose transforms are relative to the weapon root (for the
## player: the Head, so a pose is where the hand is in front of the eyes).
##
## This game's additions to the template (note 190):
## - `combo_length`: only the first swings chain; the ones after are specials started
##   with start_attack_at() (the sword's heavy swipe on Q and wave slash on F).
## - `time_scale`: every swing's length times this (player.gd `attack_time_scale`).
## - `wielder` is left out of the sweep; `sight_from` / `sight_mask` stop a blow through
##   stone; `hit_handler` hits a target with no take_hit() (every enemy here has
##   `take_damage` and `apply_knockback` instead).

signal swing_started(swing: Swing, index: int)
signal hit_window_opened(swing: Swing, index: int)
signal hit_window_closed(swing: Swing, index: int)
signal swing_finished(swing: Swing, index: int)
## A strike connected. result says whether the target took it, blocked it or parried it.
signal target_hit(target: Node, damage: float, result: HitResult)
## The target parried this weapon's strike. The wielder should react (e.g. be stunned).
signal parried(by: Node)
## The target blocked this weapon's strike.
signal blocked(by: Node)
## The chain window opened: a press now continues the combo.
signal chain_window_opened
## The chain window closed, either because the next swing started or because it expired.
signal chain_window_closed

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }
## What a target's take_hit() returns. Returning nothing counts as HIT.
enum HitResult { HIT, BLOCKED, PARRIED }

## Every weapon in play is in this group, so defenders can see who is winding up.
const GROUP := &"weapons"
## How finely a strike's path is checked for hits, in samples per full strike.
const STRIKE_SAMPLES := 24
## Draw every weapon's hit box (faint white idle, red while it can hit). The sandbox
## menu's "Show hitboxes".
static var show_hitboxes := false

@export var display_name := "Weapon"

@export_group("Timing")
## Swings per second when attacks are chained. One swing = one hit. Change this to make
## the weapon faster or slower; every swing's phases and animation scale with it.
@export_range(0.1, 10.0, 0.05, "or_greater") var hits_per_second := 2.0
## Every swing lasts this many times as long (the wielder's own pace: player.gd
## `attack_time_scale`). Set by the wielder; 1 in the editor.
var time_scale := 1.0

@export_group("Chain Window")
## The window in which a press continues the combo to the next swing, measured in swings:
## 0 = the start of the current swing, 1 = its end, above 1 = after it has finished.
## Presses before the window are ignored. A press during the swing is queued and the next
## swing starts the moment this one ends. A press after the swing starts the next swing
## at once. Once the window closes, the combo starts over at the first swing.
@export_range(0.0, 1.0, 0.01) var chain_window_start := 0.45
## When the chain window closes. 1.2 = it stays open for 20% of a swing after the swing ends.
@export_range(1.0, 2.0, 0.01) var chain_window_end := 1.2
## How many of `swings`, from the first, make the combo that chains and loops. The rest
## are specials, started only by start_attack_at(); they don't chain. 0 = all of them.
@export var combo_length := 0

@export_group("Combat")
@export var damage := 10.0
## Base knockback: how hard this weapon's hits shove the target, as the speed (metres per
## second) it's knocked along the direction the blade was travelling. Each swing scales it
## with its Knockback Multiplier; see knockback_for().
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var knockback := 2.0
## Wielder's movement speed multiplier while a swing is in progress.
@export_range(0.0, 1.0, 0.05) var move_speed_multiplier := 0.8
## Damage × this (the workbench's upgrades). Set by the wielder.
var damage_scale := 1.0

@export_group("Animation")
## Played in order and looped while attacks are chained. Starts over at the first swing
## after the weapon goes idle.
@export var swings: Array[Swing] = []
## Pose the grip returns to when not swinging.
@export var rest_pose: StringName = &"Rest"
## How quickly the grip and camera return to rest once swinging stops.
@export var return_speed := 8.0
## Scales the camera motion of every swing on this weapon. 0 turns it off.
@export_range(0.0, 3.0, 0.05) var camera_strength := 1.0

@export_group("Hitbox")
## The area that deals damage: a box that starts at the Hitbox node (placed where the blade
## begins, at the guard) and extends forward along the blade. Make it longer than the blade
## for extra reach; it always grows from the blade's start. Width and thickness are centred
## on the blade.
@export_range(0.05, 3.0, 0.01, "or_greater", "suffix:m") var hit_length := 1.0:
	set(value):
		hit_length = value
		_apply_hitbox_size()
## Size across the blade's edge direction.
@export_range(0.01, 1.0, 0.01, "or_greater", "suffix:m") var hit_width := 0.3:
	set(value):
		hit_width = value
		_apply_hitbox_size()
## Size through the blade's flat.
@export_range(0.01, 1.0, 0.01, "or_greater", "suffix:m") var hit_thickness := 0.3:
	set(value):
		hit_thickness = value
		_apply_hitbox_size()
## Whether the sweep also hits Area3Ds (off: this game's triggers and prompts are areas).
@export var hit_areas := false

@export_group("Telegraph")
## Optional material that glows during the windup, building to its brightest the instant
## the strike begins. This is the cue a defender times against. The material needs
## emission enabled; its emission energy is driven from 0 to telegraph_energy.
@export var telegraph_material: StandardMaterial3D
@export var telegraph_energy := 4.0

@export_group("Parts")
@export var grip: Node3D
@export var poses: Node3D
@export var hitbox: Area3D

@export_group("Editor Preview")
## Editor only: snaps the Grip to this pose so you can see it. Clear it to edit the model.
@export var preview_pose: StringName = &"":
	set(value):
		preview_pose = value
		if Engine.is_editor_hint() and is_node_ready():
			_snap_to(preview_pose if preview_pose != &"" else rest_pose)

var phase: Phase = Phase.IDLE
## Seconds spent in the current phase.
var phase_time := 0.0
## Index into swings of the current (or last) swing.
var swing_index := 0
## Counts every swing started. Identifies one specific swing, e.g. to match a parry to it.
var swing_serial := 0

## Set by the wielder (not saved in the scene):
## The body swinging, left out of the sweep.
var wielder: CollisionObject3D
## A hit only lands if a ray from here to the target's middle meets nothing on
## `sight_mask` (stone): the blade passes through walls, the blow does not.
var sight_from: Node3D
var sight_mask := 0
## Hits a target that has no take_hit(): `func(target: Node, amount: float) -> int`,
## returning a HitResult, or -1 to pass it over (it is not counted as struck).
var hit_handler: Callable

var _buffered := false
## Multiplies the current swing's windup length (set by start_attack_at; 1 otherwise).
var _windup_scale := 1.0
## Seconds the chain window stays open after a swing finished without a queued press.
var _chain_time_after_swing := 0.0
var _chain_was_open := false
var _from := Transform3D.IDENTITY
## Strike progress (0..1) already checked for hits this swing; -1 = nothing checked yet.
var _strike_checked := -1.0

## Details of the strike that is landing, set just before a target's take_hit() is called:
## the world direction the blade was travelling (unit length) and the final knockback.
var last_hit_direction := Vector3.ZERO
var last_hit_knockback := 0.0
## Debug drawing of the hit box (see `show_hitboxes`).
var _debug_box: MeshInstance3D
var _debug_material: StandardMaterial3D
## Camera rotation in degrees, before camera_strength.
var _camera := Vector3.ZERO
var _camera_from := Vector3.ZERO
var _already_hit: Array[Node] = []


func _ready() -> void:
	_apply_hitbox_size()
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	if hitbox:
		hitbox.monitoring = false  # only its shape and mask are used, by the strike sweep
	_create_debug_box()
	var preview_camera := get_node_or_null("PreviewCamera")
	if preview_camera:
		preview_camera.queue_free()
	_snap_to(rest_pose)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# Keep the grip on the previewed pose while you move its marker.
		if preview_pose != &"":
			_snap_to(preview_pose)
		return
	# Ticks every rendered frame so the blade and camera move smoothly at any frame rate.
	# Swing timing stays exact: leftover time always carries over.
	tick(delta)


# --- Public API ---------------------------------------------------------------------------

## Press the attack button. Returns false when the press was ignored (too early in a swing).
## - Idle with the chain window still open: starts the next swing in the combo.
## - Idle otherwise: starts the combo from the first swing.
## - Mid-swing inside the chain window: queues the next swing for when this one ends.
func request_attack() -> bool:
	if swings.is_empty():
		return false
	if phase == Phase.IDLE:
		if _chain_time_after_swing > 0.0:
			swing_index = _next_in_combo(swing_index)
		else:
			swing_index = 0
		_chain_time_after_swing = 0.0
		phase_time = 0.0
		_windup_scale = 1.0
		_start_swing()
		_update_chain_signals()
		return true
	if is_chain_window_open():
		_buffered = true
		return true
	return false


## Starts a combo from idle at a specific swing in the sequence instead of the first, e.g.
## so an enemy can open with a different attack, or a special. Chaining continues from
## there. windup_scale stretches (> 1) or shortens (< 1) this one swing's windup; the pose
## and telegraph glow stretch with it, and swings chained after it use normal timing.
## Returns false if the weapon isn't idle or the index is out of range.
func start_attack_at(index: int, windup_scale := 1.0) -> bool:
	if phase != Phase.IDLE or index < 0 or index >= swings.size():
		return false
	swing_index = index
	_chain_time_after_swing = 0.0
	phase_time = 0.0
	_windup_scale = maxf(windup_scale, 0.05)
	_start_swing()
	_update_chain_signals()
	return true


## Advances the swing by delta seconds. Leftover time carries into the next phase and swing,
## so chained swings land at exactly hits_per_second regardless of frame rate.
func tick(delta: float) -> void:
	if phase == Phase.IDLE:
		_chain_time_after_swing = maxf(_chain_time_after_swing - delta, 0.0)
		_relax_to_rest(delta)
	else:
		phase_time += delta
		while phase != Phase.IDLE and phase_time >= _phase_duration(phase):
			phase_time -= _phase_duration(phase)
			_advance_phase()
		if phase == Phase.ACTIVE:
			_sweep_strike(clampf(phase_time / maxf(_phase_duration(Phase.ACTIVE), 0.0001), 0.0, 1.0))
		if phase != Phase.IDLE:
			_apply_swing_pose()
	_update_chain_signals()
	_update_debug_box()


func is_idle() -> bool:
	return phase == Phase.IDLE


## True while a press would continue the combo.
func is_chain_window_open() -> bool:
	if phase == Phase.IDLE:
		return _chain_time_after_swing > 0.0
	if not _in_combo(swing_index):
		return false
	return swing_progress() >= chain_window_start


func cycle_duration() -> float:
	return time_scale / maxf(hits_per_second, 0.01)


func current_swing() -> Swing:
	return swings[swing_index] if swing_index < swings.size() else null


## The swing in progress, or null when idle.
func active_swing() -> Swing:
	return null if is_idle() else current_swing()


## Camera rotation in degrees (pitch, yaw, roll) this weapon wants applied right now.
func camera_offset() -> Vector3:
	return _camera * camera_strength


## Final knockback of a swing (metres per second): the weapon's base knockback times the
## swing's knockback multiplier.
func knockback_for(swing: Swing) -> float:
	return knockback * (swing.knockback_multiplier if swing else 1.0)


## Movement speed multiplier the wielder should use right now.
func move_multiplier() -> float:
	if is_idle():
		return 1.0
	var swing := current_swing()
	return move_speed_multiplier * (swing.move_multiplier if swing else 1.0)


func phase_name() -> String:
	return Phase.keys()[phase]


## 0..1 progress through the current swing (0 when idle).
func swing_progress() -> float:
	return 0.0 if is_idle() else 1.0 - _time_left_in_swing() / swing_length()


## Seconds the current swing actually lasts: its share of cycle_duration(), unless its
## windup was scaled by start_attack_at().
func swing_length() -> float:
	if current_swing() == null:
		return cycle_duration()
	return _phase_duration(Phase.WINDUP) + _phase_duration(Phase.ACTIVE) + _phase_duration(Phase.RECOVERY)


## Seconds left in the swing in progress (0 when idle).
func time_left() -> float:
	return 0.0 if is_idle() else _time_left_in_swing()


## Cancels the current swing when the wielder is hit or staggered. Unlike reset(), the
## grip and camera ease back to rest instead of snapping. Closes the chain window.
func interrupt() -> void:
	if phase == Phase.ACTIVE:
		hit_window_closed.emit(current_swing(), swing_index)
	phase = Phase.IDLE
	phase_time = 0.0
	_buffered = false
	_chain_time_after_swing = 0.0
	_set_telegraph(0.0)
	_update_chain_signals()


## Forward speed (metres per second) the wielder should add right now for the swing's lunge.
func lunge_speed() -> float:
	if phase != Phase.ACTIVE:
		return 0.0
	var swing := current_swing()
	return swing.lunge_distance / maxf(swing.active_time(cycle_duration()), 0.0001)


## Stops any swing immediately, closes the chain window and puts the grip back at rest.
func reset() -> void:
	phase = Phase.IDLE
	phase_time = 0.0
	_buffered = false
	_chain_time_after_swing = 0.0
	_update_chain_signals()
	_camera = Vector3.ZERO
	_set_telegraph(0.0)
	_snap_to(rest_pose)


## Transform of a named pose, in this weapon's space (the space the Grip moves in).
func pose_transform(pose_name: StringName) -> Transform3D:
	var marker := _find_pose(pose_name)
	if marker == null:
		return grip.transform if grip else Transform3D.IDENTITY
	return poses.transform * marker.transform


## The index of the swing called `swing_name`, or -1.
func swing_named(swing_name: String) -> int:
	for i in swings.size():
		if swings[i] != null and swings[i].display_name == swing_name:
			return i
	return -1


# --- Swing state machine ------------------------------------------------------------------

## True if this weapon's hitbox can hit that body (by physics layers).
func can_hit(body: CollisionObject3D) -> bool:
	return hitbox != null and body != null and (hitbox.collision_mask & body.collision_layer) != 0


func _combo_size() -> int:
	return swings.size() if combo_length <= 0 else mini(combo_length, swings.size())


func _in_combo(index: int) -> bool:
	return index < _combo_size()


## The swing a chained press goes to after `index`: the next in the combo, looping; from a
## special, the combo's first.
func _next_in_combo(index: int) -> int:
	if not _in_combo(index):
		return 0
	return (index + 1) % _combo_size()


func _start_swing() -> void:
	_buffered = false
	swing_serial += 1
	phase = Phase.WINDUP
	_from = grip.transform if grip else Transform3D.IDENTITY
	_camera_from = _camera
	swing_started.emit(current_swing(), swing_index)


func _advance_phase() -> void:
	var swing := current_swing()
	match phase:
		Phase.WINDUP:
			phase = Phase.ACTIVE
			_already_hit.clear()
			_strike_checked = -1.0
			hit_window_opened.emit(swing, swing_index)
		Phase.ACTIVE:
			_sweep_strike(1.0)  # finish checking the strike, even if the frame skipped past it
			if phase != Phase.ACTIVE:
				return  # the strike was parried and the swing interrupted
			phase = Phase.RECOVERY
			hit_window_closed.emit(swing, swing_index)
		Phase.RECOVERY:
			swing_finished.emit(swing, swing_index)
			if _buffered:
				swing_index = _next_in_combo(swing_index)
				_windup_scale = 1.0
				_start_swing()
			elif _in_combo(swing_index):
				# Keep the chain window open for the part of it that runs past the swing's end.
				_chain_time_after_swing = (chain_window_end - 1.0) * swing_length() - phase_time
				phase = Phase.IDLE
				phase_time = 0.0
			else:
				_chain_time_after_swing = 0.0
				phase = Phase.IDLE
				phase_time = 0.0


func _update_chain_signals() -> void:
	var open := is_chain_window_open()
	if open == _chain_was_open:
		return
	_chain_was_open = open
	if open:
		chain_window_opened.emit()
	else:
		chain_window_closed.emit()


func _phase_duration(p: Phase) -> float:
	var swing := current_swing()
	match p:
		Phase.WINDUP:
			return swing.windup_time(cycle_duration()) * _windup_scale
		Phase.ACTIVE:
			return swing.active_time(cycle_duration())
		Phase.RECOVERY:
			return swing.recovery_time(cycle_duration())
	return 0.0


func _time_left_in_swing() -> float:
	var elapsed := phase_time
	if phase >= Phase.ACTIVE:
		elapsed += _phase_duration(Phase.WINDUP)
	if phase >= Phase.RECOVERY:
		elapsed += _phase_duration(Phase.ACTIVE)
	return swing_length() - elapsed


# --- Hits ---------------------------------------------------------------------------------

## Checks the strike's path from where it was last checked up to progress `to` (0..1 of the
## active phase). The path is sampled STRIKE_SAMPLES times per full strike, using the same
## poses and easing as the animation, so hits don't depend on frame rate: a fast blade can't
## jump past a target between frames.
func _sweep_strike(to: float) -> void:
	if to <= _strike_checked:
		return
	var swing := current_swing()
	if not swing.hits:
		_strike_checked = to
		return
	var path := swing.path_poses()
	var start := maxf(_strike_checked, 0.0)
	var first := 0 if _strike_checked < 0.0 else 1  # include progress 0 on the first check
	var samples := maxi(ceili((to - start) * STRIKE_SAMPLES), 1)
	_strike_checked = to
	for i in range(first, samples + 1):
		var t := lerpf(start, to, float(i) / samples)
		_check_hits_at(_along_path(path, swing.ease_strike(t)), _travel_direction(swing, t))
		if phase != Phase.ACTIVE:
			return  # interrupted mid-strike (e.g. parried)


# --- Swing direction ----------------------------------------------------------------------

## The world direction the blade is travelling right now (unit length), or zero when it
## isn't striking. Worked out from the swing's own animation, so every swing knows which
## way it's going without any setup.
func swing_direction() -> Vector3:
	if phase != Phase.ACTIVE:
		return Vector3.ZERO
	var t := clampf(phase_time / maxf(_phase_duration(Phase.ACTIVE), 0.0001), 0.0, 1.0)
	return _travel_direction(current_swing(), t)


## Direction of travel of the middle of the hit box at strike progress t, in world space
## (in this weapon's space when not in the scene tree). Measured across a small slice of
## the path, so it follows the arc.
func _travel_direction(swing: Swing, t: float) -> Vector3:
	var path := swing.path_poses()
	var before := _hit_center(_along_path(path, swing.ease_strike(maxf(t - 0.03, 0.0))))
	var after := _hit_center(_along_path(path, swing.ease_strike(minf(t + 0.03, 1.0))))
	var direction := (after - before).normalized()
	return global_basis * direction if is_inside_tree() else direction


## Middle of the hit box, in this weapon's space, with the grip at this transform.
func _hit_center(grip_transform: Transform3D) -> Vector3:
	var local := hitbox.transform if hitbox else Transform3D.IDENTITY
	var shape_node := _hitbox_box()
	if shape_node:
		local = local * shape_node.transform
	return (grip_transform * local).origin


## Hits whatever the Hitbox's shapes overlap with the grip at this transform, while the
## blade travels in `direction` (world space).
func _check_hits_at(grip_transform: Transform3D, direction: Vector3) -> void:
	last_hit_direction = direction
	if hitbox == null or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var hitbox_transform := global_transform * grip_transform * hitbox.transform
	for child in hitbox.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null or shape_node.disabled:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = hitbox_transform * shape_node.transform
		query.collision_mask = hitbox.collision_mask
		query.collide_with_areas = hit_areas
		query.collide_with_bodies = true
		if wielder != null:
			query.exclude = [wielder.get_rid()]
		for result in space.intersect_shape(query, 16):
			var collider: Object = result.collider
			if collider is Node:
				_try_hit(collider)
			if phase != Phase.ACTIVE:
				return


## Hits each target once per swing. Targets opt in by having take_hit(damage, weapon),
## which may return a HitResult (nothing = HIT); anything else goes to `hit_handler`.
## During either the target can read last_hit_direction and last_hit_knockback.
func _try_hit(target: Node) -> void:
	if target in _already_hit:
		return
	_already_hit.append(target)
	if not _in_sight(target):
		return
	var amount := damage * damage_scale * current_swing().damage_multiplier
	last_hit_knockback = knockback_for(current_swing())
	var result := HitResult.HIT
	if target.has_method("take_hit"):
		var response: Variant = target.take_hit(amount, self)
		if response is int:
			result = response
	elif hit_handler.is_valid():
		var response: Variant = hit_handler.call(target, amount)
		if response is int and int(response) < 0:
			return
		if response is int:
			result = response
	else:
		return
	target_hit.emit(target, amount, result)
	match result:
		HitResult.PARRIED:
			parried.emit(target)
		HitResult.BLOCKED:
			blocked.emit(target)


## No stone between `sight_from` and the target's middle (always true without one).
func _in_sight(target: Node) -> bool:
	if sight_from == null or sight_mask == 0 or not (target is Node3D):
		return true
	var to := (target as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(sight_from.global_position, to, sight_mask)
	if wielder != null:
		ray.exclude = [wielder.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


# --- Animation ----------------------------------------------------------------------------

## Places the grip and the camera for the current moment of the swing. Both use the same
## phase progress and easing, so they always move together.
func _apply_swing_pose() -> void:
	var swing := current_swing()
	var t := clampf(phase_time / maxf(_phase_duration(phase), 0.0001), 0.0, 1.0)
	match phase:
		Phase.WINDUP:
			var w := swing.ease_windup(t)
			_camera = _camera_from.lerp(swing.camera_windup, w)
			_set_telegraph(t * t)  # raw time, so the glow peaks exactly as the strike starts
			if grip:
				grip.transform = _from.interpolate_with(pose_transform(swing.windup_pose), w)
		Phase.ACTIVE:
			_set_telegraph(0.0)
			var w := swing.ease_strike(t)
			_camera = swing.camera_windup.lerp(swing.camera_strike, w)
			if grip:
				grip.transform = _along_path(swing.path_poses(), w)
		Phase.RECOVERY:
			var w := swing.ease_recovery(t)
			_camera = swing.camera_strike.lerp(Vector3.ZERO, w)
			if grip:
				var end := pose_transform(swing.end_pose())
				var settle := end.interpolate_with(pose_transform(rest_pose), swing.recovery_settle)
				grip.transform = end.interpolate_with(settle, w)


## Position along a chain of poses, with progress 0..1 spread evenly over its segments.
func _along_path(path: Array[StringName], progress: float) -> Transform3D:
	var segments := path.size() - 1
	if segments <= 0:
		return pose_transform(path[0])
	var f := progress * segments
	var i := mini(int(f), segments - 1)
	return pose_transform(path[i]).interpolate_with(pose_transform(path[i + 1]), f - i)


func _relax_to_rest(delta: float) -> void:
	var k := 1.0 - exp(-return_speed * delta)
	_camera = _camera.lerp(Vector3.ZERO, k)
	if grip:
		grip.transform = grip.transform.interpolate_with(pose_transform(rest_pose), k)


func _set_telegraph(amount: float) -> void:
	if telegraph_material:
		telegraph_material.emission_energy_multiplier = telegraph_energy * amount


func _snap_to(pose_name: StringName) -> void:
	if grip and _find_pose(pose_name):
		grip.transform = pose_transform(pose_name)


func _find_pose(pose_name: StringName) -> Node3D:
	if poses == null or pose_name == &"":
		return null
	return poses.get_node_or_null(NodePath(pose_name)) as Node3D


# --- Editor support -----------------------------------------------------------------------

## Sizes the hit box from the Hitbox settings, anchored so its near end sits on the Hitbox
## node (the blade's start) and it extends forward (-Z) from there.
func _apply_hitbox_size() -> void:
	var shape_node := _hitbox_box()
	if shape_node == null:
		return
	var box := shape_node.shape as BoxShape3D
	box.size = Vector3(hit_width, hit_thickness, hit_length)
	shape_node.position = Vector3(0.0, 0.0, -hit_length * 0.5)
	if _debug_box:
		(_debug_box.mesh as BoxMesh).size = box.size


# --- Debug view ---------------------------------------------------------------------------

const DEBUG_IDLE_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const DEBUG_ACTIVE_COLOR := Color(1.0, 0.15, 0.1, 0.45)


## Draws the hit box as a see-through box, shown while `show_hitboxes` is on.
func _create_debug_box() -> void:
	var shape_node := _hitbox_box()
	if shape_node == null:
		return
	_debug_material = StandardMaterial3D.new()
	_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_debug_material.no_depth_test = true  # visible through bodies, so reach is easy to judge
	_debug_material.albedo_color = DEBUG_IDLE_COLOR
	var mesh := BoxMesh.new()
	mesh.size = (shape_node.shape as BoxShape3D).size
	_debug_box = MeshInstance3D.new()
	_debug_box.name = "DebugHitbox"
	_debug_box.mesh = mesh
	_debug_box.material_override = _debug_material
	_debug_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shape_node.add_child(_debug_box)
	_update_debug_box()


func _update_debug_box() -> void:
	if _debug_box == null:
		return
	_debug_box.visible = show_hitboxes
	if show_hitboxes:
		_debug_material.albedo_color = DEBUG_ACTIVE_COLOR if phase == Phase.ACTIVE else DEBUG_IDLE_COLOR


## The CollisionShape3D under the Hitbox whose BoxShape3D the Hitbox settings control.
func _hitbox_box() -> CollisionShape3D:
	if hitbox == null:
		return null
	for child in hitbox.get_children():
		var shape_node := child as CollisionShape3D
		if shape_node and shape_node.shape is BoxShape3D:
			return shape_node
	return null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if grip == null:
		warnings.append("Assign Parts > Grip (the node that animates).")
	if poses == null:
		warnings.append("Assign Parts > Poses (the parent of the pose markers).")
		return warnings
	if hitbox == null:
		warnings.append("Assign Parts > Hitbox, or the weapon can't hit anything.")
	elif _hitbox_box() == null:
		warnings.append("Hitbox needs a CollisionShape3D child with a BoxShape3D for the Hitbox settings to apply.")
	if swings.is_empty():
		warnings.append("Add at least one Swing under Animation > Swings.")
	if _find_pose(rest_pose) == null:
		warnings.append('Rest pose "%s" has no matching marker under Poses.' % rest_pose)
	for swing in swings:
		if swing == null:
			warnings.append("A slot in Animation > Swings is empty.")
			continue
		for pose_name in swing.path_poses():
			if _find_pose(pose_name) == null:
				warnings.append('Swing "%s" uses pose "%s", but Poses has no marker with that name.' % [swing.display_name, pose_name])
	return warnings


## Turns preview_pose into a dropdown of the markers under Poses.
func _validate_property(property: Dictionary) -> void:
	if property.name == "preview_pose" and poses:
		var names := PackedStringArray()
		for child in poses.get_children():
			names.append(child.name)
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ",".join(names)
