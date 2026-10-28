extends Node

## The collector (note 120, 2026-10-28): a lone enforcer walking the maze after
## the test subjects let out of the containment blocks -- the loose skeletons
## maze.gd spawns into group "loose_subjects". It goes to the nearest, shackles
## it (a chain from its hand to the subject's neck), and once it leads CARRY of
## them, or finds no more, walks them back to the nearest containment block
## (maze.gd `collector_drop`) and hands them in: they are gone. With nobody to
## collect it walks the corridors looking.
##
## Driven as a patrol is (patrol.gd): each member's `_wander` (enemy.gd,
## enforcer.gd) hands over to `step` while it has nothing better to do, so the
## moment any of them sees the player it fights as ever, and falls back in when
## it has lost them. Killed, the collector lets its subjects go: loose again.

const PACE := 1.25
## Within this of a subject, it is shackled.
const REACH := 2.2
## It leads this many before it takes them in.
const CARRY := 2
## How far it looks for a subject.
const SEARCH := 90.0
## Within this of the drop point, the subjects are handed in.
const DROP := 3.0
const REPLAN := 1.5
const THINK := 0.5
## The subjects walk this far apart behind it.
const SPACING := 1.7
const CATCH_UP := 1.9
const WAIT_BEHIND := 7.0
const ROAM_MIN := 14.0
const ROAM_MAX := 45.0
const TRAIL_STEP := 0.35
const TRAIL_MAX := 30
const CHAIN_R := 0.018
## A chain longer than this is not drawn (a subject dragged off in a fight).
const CHAIN_MAX := 7.0

## Untyped, like patrol.gd's members: a member killed in a fight is FREED, and
## a freed object in a typed variable is a script error every tick.
var warden = null
var led: Array = []
var target = null
var points: Array[Vector3] = []
var maze: Node = null
## For measuring: subjects shackled and handed in.
var collected := 0
var handed_in := 0

var _goal := Vector3.INF
var _roaming := false
var _path := PackedVector3Array()
var _at := 0
var _plan_at := 0.0
var _think_at := 0.0
var _check_at := 0.0
var _check_from := Vector3.ZERO
var _trail: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
## subject -> its chain
var _chains := {}
var _chain_mesh: CylinderMesh
var _chain_mat: StandardMaterial3D


func setup(w: Node3D, route_points: Array[Vector3], maze_: Node, seed_value: int) -> void:
	warden = w
	points = route_points
	maze = maze_
	_rng.seed = seed_value
	w.set("patrol", self)
	w.add_to_group(&"collectors")
	_chain_mesh = CylinderMesh.new()
	_chain_mesh.top_radius = CHAIN_R
	_chain_mesh.bottom_radius = CHAIN_R
	_chain_mesh.height = 1.0
	_chain_mesh.radial_segments = 5
	_chain_mesh.rings = 1
	_chain_mat = StandardMaterial3D.new()
	_chain_mat.albedo_color = Color(0.2, 0.19, 0.18)
	_chain_mat.metallic = 0.6
	_chain_mat.roughness = 0.5


## Still out: its enforcer standing.
func is_working() -> bool:
	return _alive(warden)


static func _alive(m) -> bool:
	return is_instance_valid(m) and m.get("_dying") != true


## The velocity `e` wants this tick while it is not fighting.
func step(e: Node3D, _delta: float, now: float) -> Vector3:
	if not _alive(warden):
		return Vector3.ZERO
	if e == warden:
		return _lead(e, now)
	return _follow(e)


func _physics_process(_delta: float) -> void:
	if _alive(warden):
		return
	# Its enforcer down: the shackled are loose again.
	for s in led:
		if _alive(s):
			# Back on its own patrol, if it had one (note 125).
			var own = s.get_meta("own_patrol") if s.has_meta("own_patrol") else null
			s.set("patrol", own if is_instance_valid(own) else null)
			s.add_to_group(&"loose_subjects")
	led.clear()
	for c in _chains.values():
		if is_instance_valid(c):
			c.queue_free()
	_chains.clear()
	set_physics_process(false)
	set_process(false)


func _lead(e: Node3D, now: float) -> Vector3:
	var here := e.global_position
	if _trail.is_empty() or _flat(_trail[0], here) >= TRAIL_STEP:
		_trail.push_front(here)
		if _trail.size() > TRAIL_MAX:
			_trail.pop_back()
	if now >= _think_at:
		_think_at = now + THINK
		_think(e, now)
	if _path.is_empty() or _at >= _path.size():
		return Vector3.ZERO
	# No headway in two seconds: a shut door or a crowd. Plan again.
	if now >= _check_at:
		if _flat(here, _check_from) < 0.6:
			_plan_at = 0.0
			if _roaming:
				_goal = Vector3.INF
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
	# Waits for the shackled when they have fallen behind.
	var lag := 0.0
	for s in led:
		if _alive(s) and s.get("engaged") != true:
			lag = maxf(lag, _flat(s.global_position, here))
	if lag > WAIT_BEHIND + SPACING * led.size():
		speed *= 0.25
	return dir * speed


## What it is about: a subject to fetch, subjects to hand in, or a walk.
func _think(e: Node3D, now: float) -> void:
	var here := e.global_position
	_prune()
	if not _alive(target) or not target.is_in_group(&"loose_subjects"):
		target = null
	if target == null and led.size() < CARRY:
		target = _nearest_subject(here)
	if target != null and _flat(target.global_position, here) <= REACH:
		_shackle(target)
		target = null
		if led.size() < CARRY:
			target = _nearest_subject(here)
	var goal := Vector3.INF
	_roaming = false
	if target != null:
		goal = target.global_position
	elif not led.is_empty():
		var drop = maze.call("collector_drop", here) if maze != null else null
		if drop != null:
			goal = drop
			if _flat(goal, here) <= DROP:
				_hand_in()
				goal = Vector3.INF
	if goal == Vector3.INF:
		_roaming = true
		if _goal == Vector3.INF or _flat(_goal, here) < 1.5 or _path.is_empty():
			goal = _roam_goal(here)
		else:
			goal = _goal
	if goal == Vector3.INF:
		return
	if now >= _plan_at or _flat(goal, _goal) > 2.0:
		_plan(e, goal)
		_plan_at = now + REPLAN
		_check_at = now + 2.0
		_check_from = here


func _nearest_subject(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := SEARCH
	for s in get_tree().get_nodes_in_group(&"loose_subjects"):
		if not _alive(s) or s.get("engaged") == true:
			continue
		var d := _flat((s as Node3D).global_position, from)
		if d < best_d:
			best_d = d
			best = s
	return best


func _shackle(s: Node3D) -> void:
	s.remove_from_group(&"loose_subjects")
	s.set_meta("own_patrol", s.get("patrol"))
	s.set("patrol", self)
	(s as PhysicsBody3D).add_collision_exception_with(warden)
	(warden as PhysicsBody3D).add_collision_exception_with(s)
	led.append(s)
	collected += 1
	var chain := MeshInstance3D.new()
	chain.mesh = _chain_mesh
	chain.material_override = _chain_mat
	chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chain.top_level = true
	add_child(chain)
	_chains[s] = chain


## Taken in at the block: the shackled are gone.
func _hand_in() -> void:
	for s in led:
		if is_instance_valid(s):
			handed_in += 1
			s.queue_free()
	led.clear()
	for c in _chains.values():
		if is_instance_valid(c):
			c.queue_free()
	_chains.clear()
	_trail.clear()


func _roam_goal(from: Vector3) -> Vector3:
	if points.is_empty() or maze == null:
		return Vector3.INF
	for tries in 30:
		var p: Vector3 = maze.to_global(points[_rng.randi_range(0, points.size() - 1)])
		var d := _flat(p, from)
		if d >= ROAM_MIN and d <= ROAM_MAX:
			return p
	return maze.to_global(points[_rng.randi_range(0, points.size() - 1)])


func _plan(e: Node3D, goal: Vector3) -> void:
	_goal = goal
	_at = 0
	var map := e.get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, e.global_position, goal, true)


func _prune() -> void:
	var kept: Array = []
	for s in led:
		if _alive(s):
			kept.append(s)
		elif _chains.has(s):
			if is_instance_valid(_chains[s]):
				_chains[s].queue_free()
			_chains.erase(s)
	led = kept
	for key in _chains.keys():
		if not is_instance_valid(key):
			if is_instance_valid(_chains[key]):
				_chains[key].queue_free()
			_chains.erase(key)


## A shackled subject walks the collector's own trail, SPACING apart.
func _follow(e: Node3D) -> Vector3:
	var rank := led.find(e)
	if rank < 0:
		return Vector3.ZERO
	var target_at := _behind(warden.global_position, SPACING * float(rank + 1))
	var to := target_at - e.global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.25:
		return Vector3.ZERO
	var dir := to / dist
	e.call("_face", dir)
	var base: float = float(e.get("wander_speed")) * PACE
	return dir * clampf(dist * 1.6, 0.0, base * (CATCH_UP if dist > 2.0 else 1.0))


func _behind(head: Vector3, back: float) -> Vector3:
	var prev := head
	var left := back
	for p in _trail:
		var seg := _flat(prev, p)
		if seg >= left:
			return prev.lerp(p, left / maxf(seg, 0.001))
		left -= seg
		prev = p
	var heading := -(warden as Node3D).global_basis.z
	heading.y = 0.0
	heading = heading.normalized() if heading.length_squared() > 1e-4 else Vector3.FORWARD
	return prev - heading * left


## The chains, from its hand to each subject's neck.
func _process(_delta: float) -> void:
	if not _alive(warden) or _chains.is_empty():
		return
	var w := warden as Node3D
	var hand := w.global_position + Vector3(0.0, 1.25, 0.0) - w.global_basis.z * 0.45
	for s in _chains.keys():
		var chain: MeshInstance3D = _chains[s]
		if not is_instance_valid(s) or not is_instance_valid(chain):
			continue
		var neck := (s as Node3D).global_position + Vector3(0.0, 1.35, 0.0)
		var span := neck - hand
		var length := span.length()
		chain.visible = length > 0.05 and length < CHAIN_MAX
		if not chain.visible:
			continue
		# The unit cylinder turned onto the span, then stretched along its own
		# axis (a local scale: `Basis.scaled` would stretch world Y).
		chain.global_transform = Transform3D(
			Basis(Quaternion(Vector3.UP, span / length)) * Basis.from_scale(Vector3(1.0, length, 1.0)),
			(hand + neck) * 0.5)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
