extends Node

## A skeleton pack on patrol (2026-10-10): every pack in the corridors is always
## on the move, in a column -- the leader walking a route through the maze, the
## rest following in its footsteps, the enforcer bringing up the rear.
##
## Nothing here runs by itself. Each member's `_wander` (enemy.gd, enforcer.gd)
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
## The enforcer walks this much further back than the last skeleton.
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
## 14 m: the longest column (six and an enforcer) needs ~11.
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
## Note 125: unsticking. How long it backs off, which way, the way it had
## been heading when it stuck (a new route must not set off that way), and
## for measuring, how often it stuck.
const UNSTICK_TIME := 0.7
var _unstick_until := 0.0
var _unstick_dir := Vector3.ZERO
var _avoid := Vector3.ZERO
var _plan_after := 0.0
var stalls := 0
var plan_fails := 0
## Note 126: its own area, round `home` (where the patrol began), and the stop
## it makes at the end of each leg: what it is doing there and till when.
const HOME_RADIUS := 45.0
const STOP_MIN := 2.0
const STOP_MAX := 6.0
var home := Vector3.ZERO
var _stop_until := 0.0
var _stop_kind := 0
var _stop_yaw := 0.0
var _stop_t := 0.0
## Followers: a navmesh path to their place in the column when it is round a
## corner, and their own unsticking (member -> state).
var _ways := {}


func setup(pack: Array[Node3D], route_points: Array[Vector3], seed_value: int) -> void:
	members.assign(pack)
	points = route_points
	_rng.seed = seed_value
	for m in members:
		m.set("patrol", self)
	if not members.is_empty() and is_instance_valid(members[0]):
		home = (members[0] as Node3D).global_position


## While two members are both on the march they pass through each other: in a
## column on a corridor a follower that ends up in front of its leader (spawned
## there, or come back from a fight) otherwise meets it head on and both stop
## for good (measured: 2 of 49 patrols, an archer and its leader nose to nose).
## In a fight they are solid to each other again, so a pack does not stack up
## on one spot round the player. The enforcer passes through its pack always
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
		if not _alive(a) or a.has_method("is_enforcer"):
			continue
		for j in range(i + 1, members.size()):
			var b = members[j]
			if not _alive(b) or b.has_method("is_enforcer"):
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
		for key in _ways.keys():
			if not is_instance_valid(key):
				_ways.erase(key)


func _current_leader() -> Node3D:
	if _alive(_leader):
		return _leader
	_leader = null
	_prune()
	for m in members:
		# The enforcer walks behind; it leads only when every skeleton is down.
		if _alive(m) and not m.has_method("is_enforcer"):
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
	# Arrived (note 126): it stops a while and does something there before
	# setting off again -- looks about, studies the wall, or turns and
	# listens back the way it came.
	if not _path.is_empty() and _at >= _path.size():
		_path = PackedVector3Array()
		_at = 0
		_begin_stop(e, now)
	if now < _stop_until:
		_do_stop(e, now)
		return Vector3.ZERO
	if _at >= _path.size() and now >= _plan_after:
		_plan(e)
		_check_at = now + 2.0
		_check_from = here
		# Nowhere to go from here (doors shut all round): not every tick.
		if _path.is_empty():
			_plan_after = now + 1.0
			plan_fails += 1
	if _path.is_empty():
		return Vector3.ZERO
	# No headway in two seconds: a shut door, a crowd, a corner it is pressed
	# into. Note 125: it backs off a step -- away from where it was heading,
	# turned a little at random -- and then takes a route that does not set
	# off the same way (`_avoid`), rather than replanning into the same spot.
	if now >= _check_at:
		if _flat(here, _check_from) < 0.6:
			var was := _heading_of(e)
			_avoid = was
			_unstick_dir = (-was).rotated(Vector3.UP, _rng.randf_range(-1.0, 1.0))
			_unstick_until = now + UNSTICK_TIME
			_path = PackedVector3Array()
			_at = 0
			stalls += 1
		_check_at = now + 2.0
		_check_from = here
	if now < _unstick_until:
		e.call("_face", -_unstick_dir)
		return _unstick_dir * float(e.get("wander_speed")) * PACE
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
	# Note 125: goals drawn only from the points in reach. Drawn from the whole
	# map, few of 40 picks were ever within LEG_MAX, so on a big map most plans
	# found nothing and the leader stood still (measured: half the stationary
	# leaders had no path). Hemmed in (doors all round), nearer goals will do.
	# At most PLAN_PATHS path queries a plan: they are the cost.
	var queried := 0
	# A route that ends short of its goal (the navmesh does not reach it) but
	# still goes somewhere, kept in case nothing better turns up: walking part
	# of the way beats standing (note 125).
	var partial := PackedVector3Array()
	for tries in 60:
		if queried >= PLAN_PATHS:
			break
		var g = sample_point(points, from, LEG_MIN * (1.0 if tries < 40 else 0.3), LEG_MAX, _rng)
		if g == null:
			continue
		var goal: Vector3 = g
		# Within its own area (note 126): HOME_RADIUS of where the patrol
		# began -- or, carried off it (a chase), a goal nearer home.
		if _flat(goal, home) > maxf(HOME_RADIUS, _flat(from, home) - 5.0):
			continue
		queried += 1
		var path := NavigationServer3D.map_get_path(map, from, goal, true)
		if path.size() < 2:
			continue
		if _flat(path[path.size() - 1], goal) > 3.0:
			if partial.is_empty():
				var cut := _until_door(path, shut)
				if cut.size() >= 2 and _flat(cut[cut.size() - 1], from) >= PARTIAL_MIN:
					partial = cut
			continue
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i].distance_to(path[i - 1])
		if length > LEG_MAX * 3.0:
			continue
		if _through_door(path, shut):
			# As far as the door, then: up to it and back is still a patrol.
			if partial.is_empty():
				var cut := _until_door(path, shut)
				if cut.size() >= 2 and _flat(cut[cut.size() - 1], from) >= PARTIAL_MIN:
					partial = cut
			continue
		# Not back the way it just stuck (`_lead`), for the first tries.
		if _avoid != Vector3.ZERO and tries < 30:
			var first := _first_leg(path)
			if first.dot(_avoid) > 0.6:
				continue
		_avoid = Vector3.ZERO
		_path = path
		return
	if not partial.is_empty():
		_avoid = Vector3.ZERO
		_path = partial


## `path` up to DOOR_CLEAR + 1 m short of the first shut door it meets.
static func _until_door(path: PackedVector3Array, shut: Array[Vector3]) -> PackedVector3Array:
	var out := PackedVector3Array()
	if path.is_empty():
		return out
	out.append(path[0])
	for i in range(1, path.size()):
		var a := Vector2(path[i - 1].x, path[i - 1].z)
		var b := Vector2(path[i].x, path[i].z)
		var near := false
		var stop := INF
		for door in shut:
			var p := Vector2(door.x, door.z)
			if absf(path[i].y - door.y) >= 2.5:
				continue
			var c := Geometry2D.get_closest_point_to_segment(p, a, b)
			if c.distance_to(p) < DOOR_CLEAR:
				near = true
				stop = minf(stop, a.distance_to(c) - (DOOR_CLEAR + 1.0))
		if near:
			if stop > 0.0:
				out.append(path[i - 1].lerp(path[i], clampf(stop / maxf(a.distance_to(b), 0.001), 0.0, 1.0)))
			return out
		out.append(path[i])
	return out


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
	if e.has_method("is_enforcer"):
		back += TAIL_GAP
	var target := _behind(lead.global_position, back)
	var to := target - e.global_position
	to.y = 0.0
	var dist := to.length()
	var base: float = float(e.get("wander_speed")) * PACE
	if dist < 0.25:
		return Vector3.ZERO
	var dir := to / dist
	# Note 125: dropped back round a corner (or out of a fight), straight at its
	# place would walk it into the stone: along the navmesh instead, replanned
	# twice a second. And pressed somewhere for two seconds, it backs off a step.
	var now := Time.get_ticks_msec() / 1000.0
	var way: Dictionary = _ways.get(e, {})
	if way.is_empty():
		way = {"check_at": now + 2.0, "from": e.global_position, "until": 0.0,
			"dir": Vector3.ZERO, "path": PackedVector3Array(), "plan_at": 0.0}
		_ways[e] = way
	if now < float(way["until"]):
		e.call("_face", -(way["dir"] as Vector3))
		return (way["dir"] as Vector3) * base
	if now >= float(way["check_at"]):
		if dist > 1.5 and _flat(e.global_position, way["from"]) < 0.4:
			way["dir"] = (-_heading_of(e)).rotated(Vector3.UP, _rng.randf_range(-1.0, 1.0))
			way["until"] = now + UNSTICK_TIME
			way["plan_at"] = 0.0
		way["check_at"] = now + 2.0
		way["from"] = e.global_position
	if dist > 2.5:
		if now >= float(way["plan_at"]):
			way["plan_at"] = now + 0.5
			way["path"] = NavigationServer3D.map_get_path(e.get_world_3d().navigation_map,
				e.global_position, target, true)
		var path: PackedVector3Array = way["path"]
		for i in range(1, path.size()):
			var step := path[i] - e.global_position
			step.y = 0.0
			if step.length() > 0.6:
				dir = step.normalized()
				break
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


## The way `e` was heading: its velocity, or its facing.
static func _heading_of(e: Node3D) -> Vector3:
	var v: Vector3 = e.get("velocity")
	v.y = 0.0
	if v.length_squared() < 0.01:
		v = -e.global_basis.z
		v.y = 0.0
	return v.normalized() if v.length_squared() > 1e-4 else Vector3.FORWARD


## The way a path sets off: toward its first point a metre or more away.
static func _first_leg(path: PackedVector3Array) -> Vector3:
	for i in range(1, path.size()):
		var d := path[i] - path[0]
		d.y = 0.0
		if d.length() >= 1.0:
			return d.normalized()
	return Vector3.ZERO


## The points in square buckets BUCKET metres across, shared by every patrol of
## a population (they share one points array): a plan looks only at the
## buckets in reach. Scanning every point per plan, every patrol, slowed the
## level to a crawl (note 125).
const BUCKET := 16.0
static var _bucket_key := ""
static var _buckets := {}


const PLAN_PATHS := 16
## A part-way route must go at least this far: boxed in a short stretch
## between shut doors, it paces that stretch rather than standing.
const PARTIAL_MIN := 2.0


## A random point of `src` between `least` and `most` metres (flat) from `at`,
## or null: a random bucket in reach, then a random point in it -- no scan.
## Also the criers' (crier.gd `_plan_patrol`), over their own route.
static func sample_point(src: Array, at: Vector3, least: float, most: float, rng: RandomNumberGenerator):
	_bucket(src)
	var r := ceili(most / BUCKET)
	var c := Vector2i(floori(at.x / BUCKET), floori(at.z / BUCKET))
	for tries in 6:
		var list = _buckets.get(c + Vector2i(rng.randi_range(-r, r), rng.randi_range(-r, r)))
		if list == null:
			continue
		var p: Vector3 = (list as Array)[rng.randi_range(0, (list as Array).size() - 1)]
		var d := _flat(p, at)
		if d >= least and d <= most:
			return p
	return null


static func _bucket(src: Array) -> void:
	var key := "%d:%s:%s" % [src.size(), src[0] if not src.is_empty() else Vector3.ZERO,
		src[src.size() - 1] if not src.is_empty() else Vector3.ZERO]
	# Keyed by what the points are, not which array holds them: the criers'
	# route is the same points in another array.
	if key != _bucket_key:
		_bucket_key = key
		_buckets.clear()
		for p in src:
			var b := Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))
			if not _buckets.has(b):
				_buckets[b] = []
			(_buckets[b] as Array).append(p)


## --- What it does at a stop (note 126) -----------------------------------------
##
## The user: "They should wander around in their respective areas, as if they
## have a brain and are doing something." At the end of each leg the leader
## stops STOP_MIN-STOP_MAX seconds and, rolled each time:
## - LOOK about: turning its head and body slowly side to side, as the old idle
##   wanderers did;
## - STUDY the nearest wall: turned square to it and standing there;
## - LISTEN back the way it came: turned round to face down its own trail.
## The column catches up behind and stands with it.
enum { LOOK, STUDY, LISTEN }


func _begin_stop(e: Node3D, now: float) -> void:
	_stop_until = now + _rng.randf_range(STOP_MIN, STOP_MAX)
	_stop_kind = _rng.randi_range(0, 2)
	_stop_t = 0.0
	_stop_yaw = e.rotation.y
	if _stop_kind == STUDY:
		var space := e.get_world_3d().direct_space_state
		var at := e.global_position + Vector3(0.0, 1.2, 0.0)
		var best := INF
		for k in 8:
			var dir := Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0))
			var q := PhysicsRayQueryParameters3D.create(at, at + dir * 3.0)
			q.collision_mask = 2
			q.exclude = [(e as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and at.distance_to(hit["position"]) < best:
				best = at.distance_to(hit["position"])
				_stop_yaw = atan2(-dir.x, -dir.z)
		if best == INF:
			_stop_kind = LOOK
	elif _stop_kind == LISTEN and _trail.size() >= 4:
		var back := _trail[mini(_trail.size() - 1, 8)] - e.global_position
		back.y = 0.0
		if back.length_squared() > 0.25:
			_stop_yaw = atan2(-back.x, -back.z)


func _do_stop(e: Node3D, _now: float) -> void:
	_stop_t += e.get_physics_process_delta_time()
	match _stop_kind:
		LOOK:
			e.rotation.y = _stop_yaw + sin(_stop_t * 0.9) * 0.9
		_:
			e.rotation.y = lerp_angle(e.rotation.y, _stop_yaw, clampf(e.get_physics_process_delta_time() * 3.0, 0.0, 1.0))
