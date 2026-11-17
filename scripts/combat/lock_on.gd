class_name LockOn
extends Node
## Camera lock-on (the timing-combat template, note 190). While locked, the view turns to
## keep the target centred (so moving sideways circles it), and look input flicks between
## targets instead of turning.
##
## Targets: nodes in any of TARGET_GROUPS (every enemy type here joins its own group).
## They can provide lock_on_point() -> Vector3 (where to aim) and can_be_locked() -> bool;
## otherwise the point is a little above their origin and a dead one (`_dead`, `dead`,
## `is_dead()`, `health <= 0`) is passed over.

signal target_changed(target: Node3D)

const TARGET_GROUPS: Array[StringName] = [&"lock_on_targets", &"skeletons", &"scouts", &"enforcers",
	&"decrepits", &"stalker", &"sewer_lizards", &"boss", &"criers", &"mimics", &"enemies"]

@export_group("Parts")
## Turned left and right to face the target (the player body).
@export var body: Node3D
@export var camera: Camera3D
## Whose property holds the look's pitch (radians), and its name: the player keeps its
## pitch apart from the head's own rotation (player.gd `_look_pitch`).
var pitch_owner: Object
var pitch_property := &"_look_pitch"
@export var reticle: LockOnReticle

@export_group("Targeting")
## Farthest a target can be locked from (metres).
@export var max_range := 20.0
## The lock breaks if the target gets this far away (metres).
@export var break_range := 25.0
## Only targets within this angle of where you're looking can be locked (degrees).
@export_range(5.0, 180.0) var max_angle := 60.0
## Stone between the eye and a target stops it being locked, and breaks a lock held
## that long (seconds).
@export_flags_3d_physics var sight_mask := 2
@export var lost_sight_break := 1.0

@export_group("Camera")
## Roughly how long (seconds) the view takes to settle on the target. The view eases into
## the turn and out of it, so locking on pans smoothly instead of snapping, and it follows
## a moving target the same way. Lower = tighter tracking.
@export_range(0.02, 1.0, 0.01, "suffix:s") var smooth_time := 0.22
## Fastest the view turns while tracking (degrees per second). Caps the pan when locking
## onto a target far from the centre of the view.
@export_range(30.0, 1440.0, 10.0, "suffix:°/s") var max_turn_speed := 300.0
## Lowest and highest the view tilts while locked (degrees), so it doesn't stare at the
## floor or sky when the target is very close.
@export var min_pitch := -35.0
@export var max_pitch := 25.0

@export_group("Switching")
## Right-stick deflection that flicks to the next target left or right.
@export_range(0.1, 1.0, 0.05) var stick_switch_threshold := 0.7
## Sideways mouse movement (pixels) that flicks to the next target.
@export var mouse_switch_threshold := 80.0

## The locked target, or null.
var target: Node3D

var _mouse_flick := 0.0
var _stick_ready := true
var _unseen := 0.0
## Current turn rates of the view (radians per second), for smooth tracking.
var _yaw_velocity := 0.0
var _pitch_velocity := 0.0


## Called by the player every rendered frame, with the look stick's sideways deflection.
func update(delta: float, stick_x: float) -> void:
	if target == null:
		return
	if not _is_valid(target, break_range):
		release()
		return
	_unseen = _unseen + delta if not _visible(target) else 0.0
	if _unseen > lost_sight_break:
		release()
		return
	_handle_stick_switching(stick_x)
	_mouse_flick = move_toward(_mouse_flick, 0.0, mouse_switch_threshold * 2.0 * delta)
	_face_target(delta)
	_update_reticle()


# --- Public API ---------------------------------------------------------------------------

func is_locked() -> bool:
	return target != null


## Lock-on button: locks the best target in view, or releases the current lock.
func toggle() -> void:
	if is_locked():
		release()
	else:
		lock(_best_target())


func lock(new_target: Node3D) -> void:
	if new_target == null or new_target == target:
		return
	if target == null:
		# Starting a lock: the view eases into the turn from rest.
		_yaw_velocity = 0.0
		_pitch_velocity = 0.0
	target = new_target
	_mouse_flick = 0.0
	_unseen = 0.0
	target_changed.emit(target)


func release() -> void:
	if target == null:
		return
	target = null
	if reticle:
		reticle.hide()
	target_changed.emit(null)


## Locks the nearest target to the left (side = -1) or right (side = 1) of the current one.
## Only targets in view (within max_angle) count, so it never swings round to one behind.
func switch_target(side: int) -> void:
	if target == null:
		return
	var current_angle := _screen_angle(target)
	var best: Node3D = null
	var best_gap := INF
	for candidate in _candidates(max_range):
		if candidate == target or _view_angle(candidate) > max_angle:
			continue
		var gap := (_screen_angle(candidate) - current_angle) * side
		if gap > 0.0 and gap < best_gap:
			best_gap = gap
			best = candidate
	lock(best)


## Sideways mouse movement while locked; enough of it flicks to the next target.
func add_mouse_flick(pixels: float) -> void:
	_mouse_flick += pixels
	if absf(_mouse_flick) >= mouse_switch_threshold:
		switch_target(int(signf(_mouse_flick)))
		_mouse_flick = 0.0


## Where the view aims on a target.
func point_of(candidate: Node3D) -> Vector3:
	return _point(candidate)


# --- Internals ----------------------------------------------------------------------------

## The target closest to the centre of the view (nearer ones win ties), within max_angle.
func _best_target() -> Node3D:
	var best: Node3D = null
	var best_score := INF
	for candidate in _candidates(max_range):
		var angle := _view_angle(candidate)
		if angle > max_angle or not _visible(candidate):
			continue
		var score := angle + camera.global_position.distance_to(_point(candidate))
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _candidates(within: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var seen := {}
	for group in TARGET_GROUPS:
		for node in get_tree().get_nodes_in_group(group):
			var candidate := node as Node3D
			if candidate == null or seen.has(candidate) or candidate == body:
				continue
			seen[candidate] = true
			if _is_valid(candidate, within):
				found.append(candidate)
	return found


func _is_valid(candidate: Node3D, within: float) -> bool:
	if not is_instance_valid(candidate) or not candidate.is_inside_tree() or not candidate.is_visible_in_tree():
		return false
	if candidate.has_method(&"can_be_locked"):
		if not candidate.call(&"can_be_locked"):
			return false
	elif _looks_dead(candidate):
		return false
	return camera.global_position.distance_to(_point(candidate)) <= within


static func _looks_dead(candidate: Node) -> bool:
	if candidate.get(&"_dead") == true or candidate.get(&"dead") == true or candidate.get(&"is_dead") == true:
		return true
	if candidate.has_method(&"is_dead") and candidate.call(&"is_dead") == true:
		return true
	var hp = candidate.get(&"health")
	return (hp is float or hp is int) and float(hp) <= 0.0


func _point(candidate: Node3D) -> Vector3:
	if candidate.has_method(&"lock_on_point"):
		return candidate.call(&"lock_on_point")
	return candidate.global_position + Vector3(0.0, 1.2, 0.0)


func _visible(candidate: Node3D) -> bool:
	if sight_mask == 0:
		return true
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, _point(candidate), sight_mask)
	if body is CollisionObject3D:
		ray.exclude = [(body as CollisionObject3D).get_rid()]
	return body.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## Degrees between where the camera looks and the direction to the candidate.
func _view_angle(candidate: Node3D) -> float:
	var to_candidate := _point(candidate) - camera.global_position
	return rad_to_deg((-camera.global_basis.z).angle_to(to_candidate))


## Horizontal angle of the candidate relative to the camera (degrees; positive = right).
func _screen_angle(candidate: Node3D) -> float:
	var local := camera.global_transform.affine_inverse() * _point(candidate)
	return rad_to_deg(atan2(local.x, -local.z))


func _handle_stick_switching(stick: float) -> void:
	if _stick_ready and absf(stick) >= stick_switch_threshold:
		switch_target(int(signf(stick)))
		_stick_ready = false
	elif absf(stick) < stick_switch_threshold * 0.4:
		_stick_ready = true


## Turns the body (yaw) and the look's pitch toward the target's lock-on point, tracking
## it smoothly rather than snapping.
func _face_target(delta: float) -> void:
	var eye := camera.global_position
	var direction := _point(target) - eye
	var yaw := atan2(-direction.x, -direction.z)
	var level := Vector2(direction.x, direction.z).length()
	var pitch := clampf(atan2(direction.y, level), deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	var max_speed := deg_to_rad(max_turn_speed)
	var yaw_step := _smooth_angle(body.rotation.y, yaw, _yaw_velocity, max_speed, delta)
	body.rotation.y = yaw_step.x
	_yaw_velocity = yaw_step.y
	if pitch_owner != null:
		var now: float = pitch_owner.get(pitch_property)
		var pitch_step := _smooth_angle(now, pitch, _pitch_velocity, max_speed, delta)
		pitch_owner.set(pitch_property, pitch_step.x)
		_pitch_velocity = pitch_step.y


## One step of a critically damped follow from `current` toward `goal` (angles, radians),
## settling in about smooth_time with its speed capped at max_speed. Returns
## (new angle, new velocity).
func _smooth_angle(current: float, goal: float, velocity: float, max_speed: float, delta: float) -> Vector2:
	goal = current + angle_difference(current, goal)  # take the short way round
	var omega := 2.0 / smooth_time
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var max_change := max_speed * smooth_time
	var change := clampf(current - goal, -max_change, max_change)
	var reachable_goal := current - change
	var temp := (velocity + omega * change) * delta
	velocity = (velocity - omega * temp) * decay
	var result := reachable_goal + (change + temp) * decay
	# Don't overshoot the goal.
	if (goal - current > 0.0) == (result > goal):
		result = goal
		velocity = 0.0
	return Vector2(result, velocity)


func _update_reticle() -> void:
	if reticle == null:
		return
	var point := _point(target)
	if camera.is_position_behind(point):
		reticle.hide()
	else:
		reticle.show_at(camera.unproject_position(point))
