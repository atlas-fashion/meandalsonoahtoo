extends CharacterBody3D

## A dungeon rat (2026-10-18). Harmless: it never touches the player. It sits
## sniffing for a moment, then darts off in a straight line, very fast, to
## somewhere close by, and does it again. Coming near it is noticed: the rat
## FREEZES for REACT seconds, then bolts well away. That freeze is the chance to
## grab it: aim at it and press E ("interact") within reach and it goes into the
## inventory as a Live Rat (inventory.gd, a utility quick item) and up into the
## hand, held by its tail (rat_control.gd). It looks like the user's Tripo rat,
## galloping, sniffing, rearing, writhing (rat_look.gd, models/rat.glb).
##
## Thrown (the quick wheel: rat_control.gd `throw_rat` -> `throw`), it flies
## tumbling, and where it lands it squeals: everything within SCARE_RADIUS that
## can be scared (enemy.gd / crier.gd `scare`) flees from that spot for
## SCARE_TIME. Then it scurries off out of the player's sight and is gone.
##
## Spawned through the corridors and the sewer by maze.gd `_spawn_rats`, and by
## the sandbox menu (sandbox_world.gd KINDS). Asleep (no physics) beyond
## SLEEP_RANGE of the player, scaled by the NPC detail setting, and not drawn
## beyond DRAW_RANGE. Collides with the player's own walls and floors (1 | 9)
## but never with the player.

const RAT_LOOK := preload("res://scripts/rat_look.gd")

enum Mode { WILD, THROWN, FLEE }

## Darting about: speed, how far each dart goes, how long it sits between.
## (The player walks at 4.25 m/s. 7 and 9.5 m/s at first; slowed so the
## gallop -- rat_look.gd, at most RUN_MAX_RATE x its own pace -- does not strobe.)
const RUN_SPEED := 5.5
const DART_MIN := 2.5
const DART_MAX := 9.0
const PAUSE_MIN := 0.5
const PAUSE_MAX := 2.6
## Of its pauses, the share spent up on its haunches (the Rear clip).
const REAR_SHARE := 0.3
const ACCEL := 60.0
## Bolting from the player.
const BOLT_SPEED := 7.5
const BOLT_MIN := 7.0
const BOLT_MAX := 13.0
## Noticing the player (flat distance): further off while they move than while
## they stand still. Noticed, it freezes for REACT, then bolts.
const NOTICE_MOVING := 4.0
const NOTICE_STILL := 1.8
const REACT := 0.5
## Grabbing: from the camera to the rat, and the aim box's padding (it is small).
const GRAB_REACH := 3.0
const GRAB_MARGIN := 0.12
## Where a thrown one lands.
const SCARE_RADIUS := 8.0
const SCARE_TIME := 4.0
## Running off once landed: gone once out of sight that long, or after the
## give-up time whatever happens.
const GONE_AFTER_HIDDEN := 0.3
const FLEE_GIVE_UP := 9.0
## Asleep beyond this (x Graphics.npc_detail), checked every SLEEP_POLL.
const SLEEP_RANGE := 25.0
const SLEEP_POLL := 0.5
const DRAW_RANGE := 20.0
## Fallen this far below where it last stood: through the floor.
const FALL_GUARD := 2.5

var mode := Mode.WILD

## The look (rat_look.gd), on a pivot it tumbles about when thrown.
var _look: Node3D
var _pivot: Node3D
var _rear := false
var _prompt: Interact.Prompt
var _player: Node3D
var _clock := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _speed := RUN_SPEED
var _pause_until := 0.0
var _noticed_at := -1.0
var _bolting := false
var _stuck := 0.0
var _asleep := false
var _next_sleep_check := 0.0
var _air_time := 0.0
var _fled_at := 0.0
var _hidden_for := 0.0
var _next_sight_check := 0.0
var _seen := true
var _replanned := false
var _last_ground := Vector3.ZERO
var _has_ground := false


func _ready() -> void:
	add_to_group(&"rats")
	name = "Rat"
	collision_layer = 0
	collision_mask = 1 | 256
	floor_snap_length = 0.2
	# A flat box the length of the body, not a ball: a 0.08 m ball dropped into
	# the cracks between the floor slabs, and one fell out of the world.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.12, 0.34)
	shape.shape = box
	shape.position = Vector3(0.0, 0.06, 0.0)
	add_child(shape)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_look = RAT_LOOK.new()
	_pivot.add_child(_look)
	_look.call("set_draw_range", DRAW_RANGE)
	_look.call("play", &"Idle")
	_prompt = Interact.prompt("E   Grab", Vector3(0.0, 0.15, 0.0))
	add_child(_prompt)
	_pause_until = randf_range(0.0, PAUSE_MAX)
	rotation.y = randf() * TAU


## The player nearest it (co-op: either; coop.gd), and never a body it bumps.
func _resolve_player() -> Node3D:
	for p in Coop.all():
		if not _excepted.has(p):
			_excepted.append(p)
			add_collision_exception_with(p)
	_player = Coop.nearest(global_position, false) as Node3D
	return _player


var _excepted: Array[Node] = []


# --- Being thrown (rat_control.gd) ----------------------------------------------------

## Off the hand at `from` with velocity `vel`: tumbling until it lands.
func throw(from: Vector3, vel: Vector3) -> void:
	mode = Mode.THROWN
	global_position = from
	velocity = vel
	_air_time = 0.0
	_asleep = false
	if _prompt != null:
		_prompt.visible = false


func is_wild() -> bool:
	return mode == Mode.WILD


# --- Each tick ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	var player := _resolve_player()
	if player == null:
		return
	if mode == Mode.WILD:
		if _clock >= _next_sleep_check:
			_next_sleep_check = _clock + SLEEP_POLL
			_asleep = global_position.distance_to(player.global_position) > SLEEP_RANGE * Graphics.npc_detail
		if _asleep:
			return
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif mode != Mode.THROWN:
		_last_ground = global_position
		_has_ground = true
	# Through the floor after all (a gap the box still found): a wild one is put
	# back where it last stood; one running off is simply gone.
	if _has_ground and global_position.y < _last_ground.y - FALL_GUARD:
		if mode == Mode.WILD:
			global_position = _last_ground + Vector3(0.0, 0.05, 0.0)
			velocity = Vector3.ZERO
			_arrive()
		else:
			queue_free()
		return
	match mode:
		Mode.WILD:
			_wild(delta, player)
		Mode.THROWN:
			_air_time += delta
			move_and_slide()
			# Down on something it can stand on, a moment after leaving the hand.
			if _air_time > 0.05 and is_on_floor():
				_land(player)
			elif _air_time > 4.0:
				queue_free()
		Mode.FLEE:
			_flee(delta, player)


func _wild(delta: float, player: Node3D) -> void:
	var to := player.global_position - global_position
	var dist := Vector2(to.x, to.z).length()
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.6
	var notice := NOTICE_MOVING if moving else NOTICE_STILL
	var awake_player: bool = player.get("_dead") != true and not player.call("is_hidden")
	if _noticed_at < 0.0 and not _bolting and awake_player and dist < notice and absf(to.y) < 2.5:
		# Caught sight of them: freeze, whiskers up.
		_noticed_at = _clock
		_path = PackedVector3Array()
	if _noticed_at >= 0.0:
		_halt(delta)
		if _clock - _noticed_at >= REACT:
			_noticed_at = -1.0
			_bolt_from(player.global_position)
		return
	if _path.is_empty():
		_halt(delta)
		if _clock >= _pause_until:
			_bolting = false
			_dart()
		return
	_follow(delta)


## Off somewhere close by, at a run: the first of a few random headings with
## room for a proper dart.
func _dart() -> void:
	for i in 6:
		var angle := randf() * TAU
		if _dash(Vector3(cos(angle), 0.0, sin(angle)), randf_range(DART_MIN, DART_MAX), RUN_SPEED, DART_MIN * 0.6):
			return
	_pause_until = _clock + PAUSE_MIN


## Away from `from`, flat out: the clearest of a fan of headings away.
func _bolt_from(from: Vector3) -> void:
	var away := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if away.length_squared() < 0.01:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	away = away.normalized()
	var want := randf_range(BOLT_MIN, BOLT_MAX)
	var best := Vector3.ZERO
	var best_reach := 0.0
	for i in 7:
		var dir := away.rotated(Vector3.UP, (float(i) - 3.0) * 0.45)
		var reach := _reach(dir, want)
		if reach > best_reach + 0.5:
			best = dir
			best_reach = reach
	_bolting = true
	if best_reach < 0.8 or not _dash(best, best_reach, BOLT_SPEED, 0.8):
		_bolting = false
		_pause_until = _clock + PAUSE_MIN


## How far it can run along `dir` (flat) before stone or a body, up to `want`.
## Rats run in STRAIGHT lines between pauses, as enemy.gd's wanderers walk: no
## navmesh path. (Paths to random points logged "It's not expect to not find
## the most reachable polygons" from the navigation server now and then -- a
## point on an island the start could not reach -- and cost more.)
func _reach(dir: Vector3, want: float) -> float:
	var from := global_position + Vector3(0.0, 0.08, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * want, 1 | 256, [get_rid()])
	if _player != null and is_instance_valid(_player):
		q.exclude = [get_rid(), _player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return want
	return maxf(from.distance_to(hit["position"]) - 0.25, 0.0)


## Runs `want` along `dir` at `speed`, or as far as is clear; false (and
## nothing done) if that is under `least`.
func _dash(dir: Vector3, want: float, speed: float, least: float) -> bool:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return false
	dir = dir.normalized()
	var reach := _reach(dir, want)
	if reach < least:
		return false
	_path = PackedVector3Array([global_position, global_position + dir * reach])
	_path_i = 1
	_speed = speed
	_stuck = 0.0
	return true


func _follow(delta: float) -> void:
	while _path_i < _path.size():
		var p := _path[_path_i]
		if Vector2(p.x - global_position.x, p.z - global_position.z).length() > 0.25:
			break
		_path_i += 1
	if _path_i >= _path.size():
		_arrive()
		_halt(delta)
		return
	var to := _path[_path_i] - global_position
	to.y = 0.0
	var dir := to.normalized()
	velocity.x = move_toward(velocity.x, dir.x * _speed, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * _speed, ACCEL * delta)
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-22.0 * delta))
	move_and_slide()
	# Wedged on something: give the dart up.
	if Vector2(velocity.x, velocity.z).length() < _speed * 0.25:
		_stuck += delta
		if _stuck > 0.4:
			_arrive()
	else:
		_stuck = 0.0


func _arrive() -> void:
	_path = PackedVector3Array()
	_bolting = false
	_pause_until = _clock + randf_range(PAUSE_MIN, PAUSE_MAX)
	# Some pauses up on its haunches, looking about.
	_rear = randf() < REAR_SHARE


func _halt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
	velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
	move_and_slide()


# --- Landing, and running off -------------------------------------------------------

## Down from a throw: every enemy in reach that can be scared flees from here,
## and the rat makes for somewhere out of the player's sight.
func _land(player: Node3D) -> void:
	mode = Mode.FLEE
	_fled_at = _clock
	_pivot.rotation = Vector3.ZERO
	scare_around(self, global_position, SCARE_RADIUS, SCARE_TIME)
	_plan_escape(player)


## Scares everything scareable (a `scare(from, time)` method) on the
## damageable layer within `radius` of `at`. Returns how many.
static func scare_around(from_node: Node3D, at: Vector3, radius: float, time: float) -> int:
	var space := from_node.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 4
	var seen := {}
	var n := 0
	for hit in space.intersect_shape(q, 64):
		var body := hit["collider"] as Node
		if body == null or seen.has(body):
			continue
		seen[body] = true
		if body.has_method("scare") and body.call("scare", at, time):
			n += 1
	return n


## A spot 8-15 m off that the player cannot see from where they stand --
## behind stone, or out of the view altogether (in the open, the sandbox's
## plane, that is the only cover there is) -- tried round the compass starting
## away from them; the furthest found if none is hidden.
func _plan_escape(player: Node3D) -> void:
	var eye := _eye(player)
	var cam := Coop.view_camera(player)
	var space := get_world_3d().direct_space_state
	var away := Vector3(global_position.x - eye.x, 0.0, global_position.z - eye.z)
	var base := atan2(away.z, away.x) if away.length_squared() > 0.01 else randf() * TAU
	var best := Vector3.ZERO
	var best_reach := 0.0
	for i in 16:
		# Straight away first, then swinging out either side.
		var a := base + floorf(float(i + 1) * 0.5) * (0.4 if i % 2 == 1 else -0.4)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var reach := _reach(dir, randf_range(8.0, 15.0))
		if reach < 2.0:
			continue
		var p := global_position + dir * reach + Vector3(0.0, 0.15, 0.0)
		var q := PhysicsRayQueryParameters3D.create(eye, p, 2 | 256, [player.get_rid()])
		var hidden := not space.intersect_ray(q).is_empty() \
			or (cam != null and not cam.is_position_in_frustum(p))
		if hidden and _dash(dir, reach, BOLT_SPEED, 2.0):
			return
		if reach > best_reach:
			best_reach = reach
			best = dir
	if best_reach > 0.0:
		_dash(best, best_reach, BOLT_SPEED, 0.5)


func _flee(delta: float, player: Node3D) -> void:
	if _clock >= _next_sight_check:
		_next_sight_check = _clock + 0.1
		_seen = _in_view(player)
	_hidden_for = 0.0 if _seen else _hidden_for + delta
	var running := _clock - _fled_at > 0.25
	if (_hidden_for >= GONE_AFTER_HIDDEN and running) or _clock - _fled_at > FLEE_GIVE_UP:
		queue_free()
		return
	if _path.is_empty():
		# Ran out of path still in view: once more, then wait to be gone.
		if not _replanned:
			_replanned = true
			_plan_escape(player)
		_halt(delta)
		return
	_follow(delta)


func _eye(player: Node3D) -> Vector3:
	var cam := player.get("camera") as Camera3D
	if cam != null and cam.is_inside_tree():
		return cam.global_position
	return player.global_position + Vector3(0.0, 1.6, 0.0)


## On screen and not behind stone, from any player's camera (co-op: either half).
func _in_view(player: Node3D) -> bool:
	for p in Coop.all():
		if _seen_by(Coop.view_camera(p), p):
			return true
	return false


func _seen_by(cam: Camera3D, player: Node3D) -> bool:
	if cam == null:
		return false
	var at := global_position + Vector3(0.0, 0.1, 0.0)
	if not cam.is_position_in_frustum(at) or cam.global_position.distance_to(at) > DRAW_RANGE:
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, at, 2 | 256)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Being grabbed ------------------------------------------------------------------

func _process(delta: float) -> void:
	_animate(delta)
	var player := _player
	if _prompt == null or player == null or not is_instance_valid(player):
		return
	_prompt.visible = mode == Mode.WILD and not _asleep and _can_grab(player)
	_prompt.player = player


func _can_grab(player: Node3D) -> bool:
	if player.get("ui_open") or player.get("in_cutscene") or player.get("remote_view") \
			or player.get("_dead") == true or player.call("is_hidden"):
		return false
	if global_position.distance_to(_eye(player)) > GRAB_REACH + 0.3:
		return false
	return Interact.looked_at(self, GRAB_REACH, GRAB_MARGIN, [], player)


func _unhandled_input(event: InputEvent) -> void:
	if not _prompt.visible or not Interact.pressed(event, _player):
		return
	get_viewport().set_input_as_handled()
	grab()


## Into the player's bag (or onto the quick wheel), and up into their hand,
## dangling by the tail (rat_control.gd `hold_caught`). Full up: it gets away.
func grab() -> bool:
	var player := _resolve_player()
	if player == null or mode != Mode.WILD:
		return false
	if int(player.call("add_item", &"live_rat", 1)) > 0:
		var hands = player.get("rats")
		if hands != null and hands.has_method("hold_caught"):
			hands.call("hold_caught")
		queue_free()
		return true
	Coop.announce(player, "NO ROOM", "The rat wriggles free")
	_noticed_at = -1.0
	_bolt_from(player.global_position)
	return false


# --- Looks -------------------------------------------------------------------------

## Which clip (rat_look.gd): the gallop while it runs, at the pace of its feet;
## up on its haunches, nose working, when it has caught sight of the player and
## frozen, and in some of its pauses; sniffing on all fours in the rest;
## writhing as if still held by the tail while it flies, tumbling.
func _animate(delta: float) -> void:
	if _look == null:
		return
	if mode == Mode.WILD and _asleep:
		_look.call("set_running", false)
		return
	_look.call("set_running", true)
	if mode == Mode.THROWN:
		_look.call("play", &"Dangle", 1.6, 0.05)
		_pivot.rotation.x += delta * 12.0
		_pivot.rotation.z += delta * 5.0
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.6:
		_look.call("run", speed)
	elif _noticed_at >= 0.0 or _rear:
		_look.call("play", &"Rear", 1.0, 0.18)
	else:
		_look.call("play", &"Idle", 1.0, 0.25)
