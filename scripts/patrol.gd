extends Node

## A skeleton pack on patrol (2026-10-10): every pack in the corridors is always
## on the move, in a column -- the leader walking a route through the maze, the
## rest following in its footsteps, the warden bot bringing up the rear.
##
## Nothing here runs by itself. Each member's `_wander` (enemy.gd, warden.gd)
## hands over to `step` while it has nothing better to do; the moment one sees
## the player it fights as ever, and when it has lost them it falls back in.
##
## - The LEADER walks to a corridor point 14-40 m off along the navmesh, then
##   picks another. Making no headway (a shut door, a crowd) it picks again. It
##   slows to wait when the column has fallen too far behind.
## - FOLLOWERS walk the leader's own trail, each SPACING further back along it,
##   so they go where it went -- round corners, through doorways -- and never
##   cut across the stone.
## - The leader is whichever member is first and still standing; a new one
##   starts a fresh trail.

const SPACING := 1.5
## The warden walks this much further back than the last skeleton.
const TAIL_GAP := 1.2
## Of each member's own `wander_speed`.
const PACE := 1.25
const CATCH_UP := 1.9
const WAIT_BEHIND := 7.0
const LEG_MIN := 14.0
const LEG_MAX := 40.0
const TRAIL_STEP := 0.35
## A route passing this near a shut wooden door is refused.
const DOOR_CLEAR := 1.6
## 14 m: the longest column (six and a warden) needs ~11.
const TRAIL_MAX := 40

## Untyped (see `_leader`): it holds members after they are killed and freed,
## until `_prune` drops them.
var members: Array = []
## Corridor points to walk between (the maze's spawn candidates).
var points: Array[Vector3] = []

## Untyped on purpose, like `members`: a member killed in a fight is FREED, and
## a freed object in a typed variable or passed to a typed parameter is a
## script error every tick ("previously freed ... not a subclass").
var _leader = null
var _trail: Array[Vector3] = []
var _path := PackedVector3Array()
var _at := 0
var _check_at := 0.0
var _check_from := Vector3.ZERO
var _lag := 0.0
var _rng := RandomNumberGenerator.new()


func setup(pack: Array[Node3D], route_points: Array[Vector3], seed_value: int) -> void:
	members.assign(pack)
	points = route_points
	_rng.seed = seed_value
	for m in members:
		m.set("patrol", self)


## While two members are both on the march they pass through each other: in a
## column on a corridor a follower that ends up in front of its leader (spawned
## there, or come back from a fight) otherwise meets it head on and both stop
## for good (measured: 2 of 49 patrols, an archer and its leader nose to nose).
## In a fight they are solid to each other again, so a pack does not stack up
## on one spot round the player. The warden passes through its pack always
## (maze.gd), so its pairs are left alone.
var _marching := {}
var _next_sync := 0.0


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_sync:
		return
	_next_sync = now + 0.25
	# The dead are freed: drop them before anything touches them.
	_prune()
	if members.is_empty():
		queue_free()
		return
	var changed := false
	for m in members:
		var on: bool = _alive(m) and m.get("engaged") != true
		if _marching.get(m, null) != on:
			_marching[m] = on
			changed = true
	if not changed:
		return
	for i in members.size():
		var a = members[i]
		if not _alive(a) or a.has_method("is_warden"):
			continue
		for j in range(i + 1, members.size()):
			var b = members[j]
			if not _alive(b) or b.has_method("is_warden"):
				continue
			if _marching.get(a, false) and _marching.get(b, false):
				a.add_collision_exception_with(b)
			else:
				a.remove_collision_exception_with(b)


## The velocity `e` wants this tick while it is not fighting.
func step(e: Node3D, delta: float, now: float) -> Vector3:
	var lead := _current_leader()
	if lead == null:
		return Vector3.ZERO
	if e == lead:
		return _lead(e, delta, now)
	return _follow(e, lead)


## Untyped: `m` may be a freed member (see `_leader`).
static func _alive(m) -> bool:
	return is_instance_valid(m) and m.get("_dying") != true


func _prune() -> void:
	var kept: Array = []
	for m in members:
		if is_instance_valid(m):
			kept.append(m)
	if kept.size() != members.size():
		members = kept
		for key in _marching.keys():
			if not is_instance_valid(key):
				_marching.erase(key)


func _current_leader() -> Node3D:
	if _alive(_leader):
		return _leader
	_leader = null
	_prune()
	for m in members:
		# The warden walks behind; it leads only when every skeleton is down.
		if _alive(m) and not m.has_method("is_warden"):
			_leader = m
			break
	if _leader == null:
		for m in members:
			if _alive(m):
				_leader = m
				break
	_trail.clear()
	_path = PackedVector3Array()
	return _leader


func _lead(e: Node3D, _delta: float, now: float) -> Vector3:
	var here := e.global_position
	# Trail: where it has been, newest first.
	if _trail.is_empty() or _flat(_trail[0], here) >= TRAIL_STEP:
		_trail.push_front(here)
		if _trail.size() > TRAIL_MAX:
			_trail.pop_back()
	if _at >= _path.size():
		_plan(e)
		_check_at = now + 2.0
		_check_from = here
	if _path.is_empty():
		return Vector3.ZERO
	# No headway in two seconds: a shut door or a crowd. Somewhere else.
	if now >= _check_at:
		if _flat(here, _check_from) < 0.6:
			_path = PackedVector3Array()
			_at = 0
		_check_at = now + 2.0
		_check_from = here
	while _at < _path.size() and _flat(_path[_at], here) < 0.6:
		_at += 1
	if _at >= _path.size():
		return Vector3.ZERO
	var to := _path[_at] - here
	to.y = 0.0
	var dir := to.normalized()
	e.call("_face", dir)
	var speed: float = float(e.get("wander_speed")) * PACE
	# Waits for a column that has fallen behind (a fight it was not in, a member
	# that was asleep).
	_lag = 0.0
	for m in members:
		if m != e and _alive(m) and m.get("engaged") != true:
			_lag = maxf(_lag, _flat(m.global_position, here))
	if _lag > WAIT_BEHIND + SPACING * members.size():
		speed *= 0.25
	return dir * speed


func _plan(e: Node3D) -> void:
	_path = PackedVector3Array()
	_at = 0
	if points.is_empty():
		return
	var map := e.get_world_3d().navigation_map
	var from := e.global_position
	# The navmesh runs straight through the wooden doors (it is baked before
	# they are shut), so a route through a shut one is refused here; a leader
	# walking into one stood at it for good, replanning into the same door.
	var shut: Array[Vector3] = []
	for d in e.get_tree().get_nodes_in_group(&"wood_doors"):
		if d.get("opened") != true:
			shut.append((d as Node3D).global_position)
	for tries in 40:
		# Hemmed in (doors all round), nearer goals will do.
		var near := LEG_MIN * (1.0 if tries < 20 else 0.35)
		var goal: Vector3 = points[_rng.randi_range(0, points.size() - 1)]
		var d := _flat(goal, from)
		if d < near or d > LEG_MAX:
			continue
		var path := NavigationServer3D.map_get_path(map, from, goal, true)
		if path.size() < 2 or _flat(path[path.size() - 1], goal) > 1.5:
			continue
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i].distance_to(path[i - 1])
		if length > LEG_MAX * 2.0 or _through_door(path, shut):
			continue
		_path = path
		return


static func _through_door(path: PackedVector3Array, shut: Array[Vector3]) -> bool:
	for door in shut:
		var p := Vector2(door.x, door.z)
		for i in range(1, path.size()):
			var a := Vector2(path[i - 1].x, path[i - 1].z)
			var b := Vector2(path[i].x, path[i].z)
			var c := Geometry2D.get_closest_point_to_segment(p, a, b)
			if c.distance_to(p) < DOOR_CLEAR and absf(path[i].y - door.y) < 2.5:
				return true
	return false


func _follow(e: Node3D, lead: Node3D) -> Vector3:
	var rank := 0
	for m in members:
		if m == lead or not _alive(m):
			continue
		rank += 1
		if m == e:
			break
	var back := SPACING * float(rank)
	if e.has_method("is_warden"):
		back += TAIL_GAP
	var target := _behind(lead.global_position, back)
	var to := target - e.global_position
	to.y = 0.0
	var dist := to.length()
	var base: float = float(e.get("wander_speed")) * PACE
	if dist < 0.25:
		return Vector3.ZERO
	var dir := to / dist
	e.call("_face", dir)
	# Keeps step with the column; hurries when it has dropped back.
	var speed := clampf(dist * 1.6, 0.0, base * (CATCH_UP if dist > 2.0 else 1.0))
	return dir * speed


## The point `back` metres behind `head` along the leader's trail -- and where
## the trail is not that long yet (a fresh patrol, a new leader), on straight
## back from the way the leader is heading. Returning the end of a short trail
## put every follower's goal ON the leader: they leant on it from all sides,
## it leant on them, and move_and_slide held the whole pack still (measured: 4
## of 49 patrols never moved).
func _behind(head: Vector3, back: float) -> Vector3:
	var prev := head
	var left := back
	for p in _trail:
		var seg := _flat(prev, p)
		if seg >= left:
			return prev.lerp(p, left / maxf(seg, 0.001))
		left -= seg
		prev = p
	return prev - _heading() * left


func _heading() -> Vector3:
	var here: Vector3 = _leader.global_position
	var to := Vector3.ZERO
	if _at < _path.size():
		to = _path[_at] - here
	elif _trail.size() >= 2:
		to = _trail[0] - _trail[_trail.size() - 1]
	to.y = 0.0
	if to.length_squared() < 0.01:
		to = -_leader.global_basis.z
		to.y = 0.0
	return to.normalized() if to.length_squared() > 1e-4 else Vector3.FORWARD


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
