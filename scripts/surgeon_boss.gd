extends CharacterBody3D

## THE SURGEON as a boss (2026-10-25, note 105). The user: "the player should
## have to fight the surgeon after the claw gets depowered. make infrastructure
## for that, and ill give you details later." So this is the frame of the
## fight -- who he is, when it starts, what ends it, the bar, the bars at the
## ways in, saving and dying -- with a stand-in for how he fights (FIGHT: he
## turns to the nearest player and walks at them; no attacks yet).
##
## His body is the Meshy-rigged surgeon (models/surgery/surgeon.glb; clips
## "work", "alert", "die" only -- a walk, his attacks, a hit and a rise will need
## clips of their own), built and placed by surgery_control.gd.
##
## STATES:
##   AT_WORK  at his console in the booth (the machine running); untouchable.
##   FLUNG    in the air, out of the booth (the kick, surgery_control.gd); the
##            control room moves him.
##   DOWN     lying where he landed in the hall, out cold, until the machine is
##            off (the lever, or the crystal).
##   WAITING  on his feet in the hall, the machine off: the fight starts the
##            moment a player is in the hall (a save, a world reset, the
##            crystal route).
##   RISING   getting up -- RISE_TIME -- and the fight is on.
##   FIGHT    `engaged`: the HUD's boss bar (hud.gd `_engaged_champion`: group
##            "boss"); he can be hurt; the bars at the ways in are up.
##   DEAD     `defeated`: the bars come down (surgery.gd).
##
## A world reset during the fight (everyone died): full health, back where he
## waits (`wait_at`), WAITING.

signal fight_started
signal defeated

enum State { AT_WORK, FLUNG, DOWN, WAITING, RISING, FIGHT, DEAD }

## Placeholder numbers until the fight is designed.
const MAX_HEALTH := 600.0
const RISE_TIME := 1.6
const WALK_SPEED := 1.6
const STOP_AT := 1.8
const TURN_RATE := 5.0
const RADIUS := 0.38
const HEIGHT := 1.85

@export var display_name := "THE SURGEON"
var max_health := MAX_HEALTH
var health := MAX_HEALTH
## Read by the HUD for the boss bar.
var engaged := false
var state: State = State.AT_WORK
## The hall (surgery.gd): `in_hall(world)`, its table for sparks.
var surgery: Node3D
## The model (its AnimationPlayer found below) and where he waits (world).
var model: Node3D
var _anim: AnimationPlayer
var _wait_at := Transform3D.IDENTITY
var _t := 0.0


func _ready() -> void:
	add_to_group(&"boss")
	add_to_group(&"surgeon")
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	collision_layer = 1 | 4
	collision_mask = 1 | 2
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(cs)


## The model under him (surgery_control.gd hands it over).
func take_model(m: Node3D) -> void:
	model = m
	var found := m.find_children("*", "AnimationPlayer", true, false)
	_anim = found[0] as AnimationPlayer if not found.is_empty() else null


## The clip whose name has `key` in it.
func clip(key: StringName) -> StringName:
	if _anim == null:
		return &""
	for n in _anim.get_animation_list():
		if String(n).to_lower().contains(String(key)):
			return n
	return &""


func play(key: StringName, blend := 0.2, speed := 1.0, loop := false) -> void:
	var c := clip(key)
	if c == &"":
		return
	_anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_anim.play(c, blend, speed)


## Held at the end of `key` (a save: lying, dead).
func hold_end(key: StringName) -> void:
	var c := clip(key)
	if c == &"":
		return
	_anim.play(c)
	_anim.seek(_anim.get_animation(c).length - 0.01, true)


func _set_state(s: State) -> void:
	state = s
	_t = 0.0
	engaged = s == State.FIGHT


# --- Moments ---------------------------------------------------------------------------

## Lying in the hall where the kick put him, out cold.
func lie_down() -> void:
	_set_state(State.DOWN)
	velocity = Vector3.ZERO


## Where he waits for the fight (world), and that he is waiting there, on his
## feet. `now`: placed at once.
func wait_at(at: Transform3D) -> void:
	_wait_at = at
	global_transform = at
	health = max_health
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 1 | 4
	_set_state(State.WAITING)
	play(&"alert", 0.0, 0.0)


## Up, and the fight is on (the machine just died with him lying in the hall,
## or a player came in to find him waiting).
func begin_fight() -> void:
	if state in [State.RISING, State.FIGHT, State.DEAD]:
		return
	if state == State.DOWN or state == State.FLUNG:
		_wait_at = global_transform
	_set_state(State.RISING)
	play(&"alert", 0.3)


## A world reset with him still up: whole again, back where he waits.
func reset_wait() -> void:
	if state == State.DEAD:
		return
	wait_at(_wait_at if _wait_at != Transform3D.IDENTITY else global_transform)


## A save with him dead: lying where he fell.
func set_dead_now(at: Transform3D) -> void:
	global_transform = at
	health = 0.0
	collision_layer = 0
	_set_state(State.DEAD)
	hold_end(&"die")


# --- Each tick ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.WAITING:
			if _player_in_hall() != null:
				begin_fight()
		State.RISING:
			if _t >= RISE_TIME:
				_set_state(State.FIGHT)
				fight_started.emit()
		State.FIGHT:
			_fight(delta)


## The fight, for now: face the nearest player and walk at them, stopping
## STOP_AT short. (His moves are to come.)
func _fight(delta: float) -> void:
	var p := Coop.nearest(global_position) as Node3D
	if p == null:
		return
	var to := p.global_position - global_position
	to.y = 0.0
	if to.length() > 0.01:
		# (The model faces its +Z.)
		var want := atan2(to.x, to.z)
		rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-TURN_RATE * delta))
	var dir := Vector3.ZERO
	if to.length() > STOP_AT:
		if _t >= _replan_at or _path_i >= _path.size():
			_replan(p.global_position)
		dir = _steer(to)
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	move_and_slide()


# --- Finding his way round the vats ------------------------------------------------------
##
## The vats are not in the level's navmesh (they move), and he walked straight
## into them and stood there. So he finds his own way across the hall: an
## AStarGrid2D over its floor, GRID_CELL cells, every vat (and the table) solid
## out to its radius plus his, re-made every REPLAN s.

const GRID_CELL := 0.5
const REPLAN := 0.4
var _grid: AStarGrid2D
var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _replan_at := 0.0
## The cells the hall's fixed things stand in (the booth's posts, the intake's
## crates, the walls' frames): found once, by asking the physics.
var _static: Array[Vector2i] = []


func _find_static(n: int) -> void:
	_static.clear()
	var inner: float = surgery.get("_inner")
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(GRID_CELL + RADIUS * 2.0, 1.0, GRID_CELL + RADIUS * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 2
	q.exclude = [get_rid()]
	for i in n:
		for j in n:
			var l := Vector3(-inner + (float(i) + 0.5) * GRID_CELL, 1.0, -inner + (float(j) + 0.5) * GRID_CELL)
			q.transform = Transform3D(surgery.global_basis, surgery.to_global(l))
			for hit in space.intersect_shape(q, 8):
				var c: Object = hit["collider"]
				# The vats move, and are marked each time; bodies come and go.
				if c is CharacterBody3D or (c is Node and (c as Node).is_in_group(&"surgery_vat")):
					continue
				_static.append(Vector2i(i, j))
				break


func _cell(l: Vector3) -> Vector2i:
	var inner: float = surgery.get("_inner")
	return Vector2i(floori((l.x + inner) / GRID_CELL), floori((l.z + inner) / GRID_CELL))


func _replan(target: Vector3) -> void:
	_replan_at = _t + REPLAN
	_path = PackedVector3Array()
	_path_i = 0
	if surgery == null:
		return
	var inner: float = surgery.get("_inner")
	var n := ceili(inner * 2.0 / GRID_CELL)
	if _grid == null:
		_grid = AStarGrid2D.new()
		_grid.region = Rect2i(0, 0, n, n)
		_grid.cell_size = Vector2(GRID_CELL, GRID_CELL)
		_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		_grid.update()
		_find_static(n)
	_grid.fill_solid_region(_grid.region, false)
	for s in _static:
		_grid.set_point_solid(s, true)
	var blocks: Array = []
	for v in surgery.get("vats"):
		var vat := v as Node3D
		blocks.append([surgery.to_local(vat.global_position), float(vat.get("radius")) + RADIUS + 0.1])
	var table: Node3D = surgery.get("table")
	if table != null:
		blocks.append([surgery.to_local(table.global_position), 1.7 + RADIUS])
	for b in blocks:
		var c: Vector3 = b[0]
		var r: float = b[1]
		var lo := _cell(c - Vector3(r, 0.0, r))
		var hi := _cell(c + Vector3(r, 0.0, r))
		for i in range(maxi(lo.x, 0), mini(hi.x, n - 1) + 1):
			for j in range(maxi(lo.y, 0), mini(hi.y, n - 1) + 1):
				var mid := Vector2(-inner + (float(i) + 0.5) * GRID_CELL, -inner + (float(j) + 0.5) * GRID_CELL)
				if mid.distance_to(Vector2(c.x, c.z)) < r:
					_grid.set_point_solid(Vector2i(i, j), true)
	var from := _cell(surgery.to_local(global_position)).clamp(Vector2i.ZERO, Vector2i(n - 1, n - 1))
	var goal := _cell(surgery.to_local(target)).clamp(Vector2i.ZERO, Vector2i(n - 1, n - 1))
	_grid.set_point_solid(from, false)
	if _grid.is_point_solid(goal):
		# Up on a vat, or the table: to the nearest floor beside it.
		var best := goal
		var best_d := INF
		for i in range(-6, 7):
			for j in range(-6, 7):
				var q := goal + Vector2i(i, j)
				if _grid.is_in_boundsv(q) and not _grid.is_point_solid(q) and Vector2(i, j).length() < best_d:
					best_d = Vector2(i, j).length()
					best = q
		goal = best
	var ids := _grid.get_id_path(from, goal, true)
	for id in ids:
		var l := Vector3(-inner + (float(id.x) + 0.5) * GRID_CELL, 0.0, -inner + (float(id.y) + 0.5) * GRID_CELL)
		_path.append(surgery.to_global(l))
	_path_i = 1 if _path.size() > 1 else 0


## The way to go along the path; straight at them with no path.
func _steer(to: Vector3) -> Vector3:
	while _path_i < _path.size():
		var w := _path[_path_i] - global_position
		w.y = 0.0
		if w.length() > 0.3:
			return w.normalized()
		_path_i += 1
	return to.normalized()


## A player standing in the hall (not in a scene), or null.
func _player_in_hall() -> Node3D:
	if surgery == null:
		return null
	for p in Coop.all():
		var n := p as Node3D
		if n == null or n.get("_dead") == true or n.get("in_cutscene") == true:
			continue
		if bool(surgery.call("in_hall", n.global_position)):
			return n
	return null


# --- Being hit ---------------------------------------------------------------------------

func take_damage(amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
	if state != State.FIGHT:
		return
	health = maxf(health - amount, 0.0)
	var table: Node = surgery.get("table") if surgery != null else null
	if table != null:
		table.call("_sparks", global_position + Vector3(0.0, 1.3, 0.0) - from_direction * 0.3, Color(0.7, 0.08, 0.05), 10)
	if health <= 0.0:
		_die()


func apply_knockback(impulse: Vector3, _stun_time := 0.0) -> void:
	if state != State.FIGHT:
		return
	velocity += Vector3(impulse.x, 0.0, impulse.z) * 0.25


func _die() -> void:
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	play(&"die", 0.1)
	defeated.emit()


func is_dead() -> bool:
	return state == State.DEAD
