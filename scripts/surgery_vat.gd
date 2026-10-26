extends CharacterBody3D

## A vat in the surgery (2026-10-25, note 102). The user: "the room should
## instead be filled with large vats of pieces that the claw uses to make bionic
## soldiers. The player should be able to push the vats around the room, but
## they should be heavy and cumbersome."
##
## A riveted iron tub, as tall as a man and wider (models/surgery/vat_bones.glb,
## a prisoner's bones in brown slurry, or vat_gold.glb, the gold prostheses in
## oil), standing on the flags. surgery.gd lays them out in rows across the
## hall, aisles between; one of them stands over the hatch to the powering room
## (surgery_power.gd), and nothing marks which.
##
## PUSHING. A player walking into a vat (their own move_and_slide meets it) and
## still pressing toward it shoves it. Nothing moves at first: it takes
## BREAKAWAY s of steady shoving before the vat gives with a jolt; then it
## creeps in lurches -- each heave a shove, the slurry slopping -- up to
## PUSH_SPEED, and it stops dead within a stride once they let go. The way it
## goes follows the shove only slowly (TURN), so it cannot be steered round a
## corner. Two players shoving together move it faster (TEAM_BONUS each).
## It stops against anything solid -- walls, the table, other vats, a player in
## its way -- scraping a little along it (GRAZE). It never moves itself; the
## claw ignores it.
##
## A player can stand on it (note 104: the way across to the booth): standing
## on it they never shove it.
##
## Floating (no gravity) with its collision a cylinder from STAND_OFF up, clear
## of the flags: the floor's slab is on the walls' layer, which it does collide
## with.

const RADIUS := 1.15
const HEIGHT := 1.85
const STAND_OFF := 0.12
## Shoving: this long before it gives at all; then up to PUSH_SPEED (m/s) at
## ACCEL, braking at BRAKE once let go. Each heave a lurch HEAVE times a second,
## its low ebb LURCH of full speed. (Speed and acceleration 0.8 -> 1.1, note 103:
## "move the vats a bit faster".)
const BREAKAWAY := 0.55
const PUSH_SPEED := 1.1
const ACCEL := 1.1
const BRAKE := 5.0
const HEAVE := 1.3
const LURCH := 0.35
## The share of the shove's direction taken each second once it moves.
const TURN := 0.9
## A second player shoving with the first adds this much speed.
const TEAM_BONUS := 0.45
## A player counts as shoving if their stick points within this of the vat.
const SHOVE_DOT := 0.55
## A player this near its side counts as pressing on it (their move_and_slide
## does not meet it every tick once it gives), and a shove lapses only after
## GRACE_MS without one.
const TOUCH := 0.4 + 0.18
const GRACE_MS := 220
## Running into something: what is left of the move slides along it this much.
const GRAZE := 0.35
## What stops it besides the world: the open hatch's curb (surgery_power.gd).
const STOP_LAYER := 1 << 22

const FX_DUST := preload("res://textures/surgery_fx_dust.png")
## THE LID (note 104, the user: "Give the vats removable lids"): the kit's riveted
## `hatch` plate (a Higgsfield piece) laid over the tub, LID_SIZE across. A
## player lifts it off with E and leans it against the tub's side, or puts it
## back; the claw lifts it off to fish out a piece to throw (surgical_table.gd
## FETCH) and leaves it off. It moves with its vat.
const LID_MODEL := preload("res://models/surgery/hatch.glb")
const LID_SIZE := 2.3
const LID_TIME := 0.55
## The tub's rim, by kind (the models' heights).
const RIM := {"vat_bones": 1.89, "vat_gold": 1.83}

## The model under it (surgery.gd hands it over).
var model: Node3D
## Where it started (room frame of the surgery): a world reset puts it back.
var home := Transform3D.IDENTITY
## Which tub ("vat_gold": the prostheses the claw throws; "vat_bones").
var kind := "vat_bones"
## Note 105: the vats across the ways in are bigger (`grow` x, set before it
## enters the tree) -- 1.45 m in radius, so the 3.4 m corridor mouth they stand
## in has no gap a player fits through -- and `entry`: the claw leaves them be.
var grow := 1.0
var entry := false
var radius := RADIUS
var height := HEIGHT
## A player has begun shoving it (the entrance scene starts on it, note 105).
signal shove_started(player: Node3D)
## The lid on (a world reset puts it back on).
var lid_on := true
var _lid: Node3D
var _lid_prompt: Interact.Prompt
var _lid_busy := false

var _push_t := 0.0
var _speed := 0.0
var _dir := Vector3.ZERO
var _phase := 0.0
var _rock := 0.0
var _rock_v := 0.0
var _dust: CPUParticles3D
var _jolted := false
## How many players shoved it this tick (`_shove`).
var _pushers := 0
var _last_shove := -100000
## The last player to shove it.
var _pusher: Node3D = null


func _ready() -> void:
	radius = RADIUS * grow
	height = HEIGHT * grow
	add_to_group(&"surgery_vat")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1 | 2
	# Not the players' layer (1): one pressed against it would stop it dead
	# every tick. A player in its way is looked for instead (`_player_ahead`).
	# The table is solid on 1 and 3 (hurtable): 3 stands in for it.
	collision_mask = 2 | 4 | STOP_LAYER
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height - STAND_OFF
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, STAND_OFF + shape.height * 0.5, 0.0)
	add_child(cs)
	_dust = _make_dust()
	add_child(_dust)


## The lid, on (surgery.gd calls it once `kind` is set), and its prompt.
func fit_lid() -> void:
	_lid = LID_MODEL.instantiate()
	_lid.name = "Lid"
	add_child(_lid)
	load("res://scripts/surgical_table.gd").grade(_lid)
	for g in _lid.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_lid_prompt = Interact.prompt("E   Lift the lid", Vector3(0.0, rim(), 0.0))
	add_child(_lid_prompt)
	_lid.transform = _lid_pose(true)


## The lid's place on the vat: `on` laid across the rim (a little turned, so
## the plate's corners do not line up with the hoops), else stood on its edge
## against the tub's side, leaning in.
func _lid_pose(on: bool) -> Transform3D:
	var size := Vector3(LID_SIZE / 1.35, 0.7, LID_SIZE / 1.164) * grow
	var rim := rim()
	if on:
		return Transform3D(Basis(Vector3.UP, 0.4).scaled(size), Vector3(0.0, rim - 0.02, 0.0))
	# On its edge on the floor, leaning back against the tub (+X of the vat).
	var b := Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5 - 0.2)
	return Transform3D(b.scaled(size), Vector3(radius + 0.28, LID_SIZE * grow * 0.5 - 0.05, 0.0))


## Lifts the lid off (`on` false) or puts it back, over LID_TIME: up off the
## rim, over, and down onto its edge (or the other way). `instant`: a save.
func set_lid(on: bool, instant := false) -> void:
	if _lid == null or (on == lid_on and not instant):
		return
	lid_on = on
	if instant:
		_lid.transform = _lid_pose(on)
		return
	_lid_busy = true
	var from := _lid.transform
	var to := _lid_pose(on)
	var lift := Vector3(0.0, 0.7, 0.0)
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		var e := k * k * (3.0 - 2.0 * k)
		var t := from.interpolate_with(to, e)
		t.origin += lift * sin(e * PI)
		_lid.transform = t, 0.0, 1.0, LID_TIME)
	tw.tween_callback(func() -> void: _lid_busy = false)


func _process(_delta: float) -> void:
	if _lid_prompt == null:
		return
	if _lid_busy or not _anyone_near():
		_lid_prompt.visible = false
		return
	var p := Interact.chooser(model if model != null else self, radius + 1.6, 2.4, 3.2, 0.1)
	# Not from on top of it: a player standing on the lid cannot lift it.
	if p != null and (p as Node3D).global_position.y > global_position.y + 1.0:
		p = null
	_lid_prompt.visible = p != null
	_lid_prompt.player = p
	_lid_prompt.text = "E   Lift the lid" if lid_on else "E   Put the lid on"


func _unhandled_input(event: InputEvent) -> void:
	if _lid_prompt == null or not _lid_prompt.visible:
		return
	if Interact.pressed(event, _lid_prompt.player):
		get_viewport().set_input_as_handled()
		set_lid(not lid_on)


## A player standing on it (on the lid or the rim), not beside it.
func _on_top(n: Node3D) -> bool:
	return n.global_position.y > global_position.y + height * 0.6


## Shoved by a scene (surgery.gd's entrance): slid to `to` (world, on the
## floor) over `time`, lurching and scraping as a shove does.
func scripted_push(to: Vector3, time: float) -> void:
	var from := global_position
	_dir = Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
	_rock_v -= 1.6
	_dust.emitting = true
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		var e := k - sin(k * TAU * 2.0) / (TAU * 2.0) * 0.6
		global_position = from.lerp(to, clampf(e, 0.0, 1.0))
		_phase = k * 4.0
		_speed = PUSH_SPEED * 0.8
		_sway(get_physics_process_delta_time()), 0.0, 1.0, time)
	tw.tween_callback(func() -> void:
		_speed = 0.0
		_dust.emitting = false)


## Grit kicked up round its foot while it scrapes along.
func _make_dust() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Scrape"
	p.emitting = false
	p.amount = 14
	p.lifetime = 1.1
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius * 0.95
	p.emission_ring_inner_radius = radius * 0.85
	p.emission_ring_height = 0.05
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 70.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0.0, -0.3, 0.0)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.7
	p.color = Color(0.42, 0.36, 0.3, 0.45)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.albedo_texture = FX_DUST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	quad.material = m
	p.mesh = quad
	p.position = Vector3(0.0, 0.05, 0.0)
	return p


func is_moving() -> bool:
	return _speed > 0.02


## Back where it started (a world reset), at rest.
func go_home(room: Node3D) -> void:
	global_transform = room.global_transform * home
	set_lid(true, true)
	_stop()


## Set down at `at` (world, on the floor), turned `yaw` (a save).
func place(at: Vector3, yaw: float) -> void:
	global_position = at
	global_rotation = Vector3(0.0, yaw, 0.0)
	_stop()


func _stop() -> void:
	_speed = 0.0
	_push_t = 0.0
	_dir = Vector3.ZERO
	_jolted = false
	_dust.emitting = false


func _physics_process(delta: float) -> void:
	# At rest with no one near it, nothing to do (twenty-odd of them in the hall).
	if _speed <= 0.0 and absf(_rock) < 0.0005 and absf(_rock_v) < 0.0005 and not _anyone_near():
		if _push_t > 0.0:
			_push_t = 0.0
			_jolted = false
		return
	var shove := _shove()
	var pushers := float(_pushers)
	if pushers > 0.0 and shove.length_squared() > 0.01:
		shove = shove.normalized()
		_last_shove = Time.get_ticks_msec()
		if _push_t <= 0.0:
			shove_started.emit(_pusher)
		_push_t += delta
		if _push_t >= BREAKAWAY:
			if not _jolted:
				# It gives: a jolt, the tub rocking back on its skids.
				_jolted = true
				_rock_v -= 1.6
				_dir = shove
			_dir = _dir.lerp(shove, clampf(TURN * delta, 0.0, 1.0)).normalized()
			var top := PUSH_SPEED * (1.0 + TEAM_BONUS * (pushers - 1.0))
			_speed = move_toward(_speed, top, ACCEL * delta)
	elif Time.get_ticks_msec() - _last_shove > GRACE_MS:
		# Let go: it stays put, and the next shove has to break it loose again.
		_push_t = maxf(_push_t - delta * 2.5, 0.0)
		if _push_t < BREAKAWAY * 0.5:
			_jolted = false
		_speed = move_toward(_speed, 0.0, BRAKE * delta)
	if _speed > 0.001 and _dir != Vector3.ZERO and _player_ahead():
		_speed = 0.0
	if _speed > 0.001 and _dir != Vector3.ZERO:
		_phase += delta * HEAVE
		var heave := LURCH + (1.0 - LURCH) * pow(absf(sin(_phase * PI)), 1.5)
		var hit := move_and_collide(_dir * _speed * heave * delta)
		if hit != null:
			var n := hit.get_normal()
			n.y = 0.0
			if n.length_squared() > 0.0001:
				var rest := hit.get_remainder().slide(n.normalized()) * GRAZE
				rest.y = 0.0
				move_and_collide(rest)
			if _speed > PUSH_SPEED * 0.5:
				_rock_v += 1.2
			_speed *= 0.4
	_dust.emitting = _speed > 0.15
	_sway(delta)


## The tub rocks on its skids: back as it breaks loose and against each heave,
## forward when it is stopped -- a damped spring about the axis across the shove.
func _sway(delta: float) -> void:
	if model == null:
		return
	var lurch := -sin(_phase * PI * 2.0) * 0.6 * minf(_speed / PUSH_SPEED, 1.0)
	var acc := -_rock * 90.0 - _rock_v * 7.0 + lurch
	_rock_v += acc * delta
	_rock += _rock_v * delta
	_rock = clampf(_rock, -0.06, 0.06)
	var across := Vector3.UP.cross(_dir) if _dir != Vector3.ZERO else Vector3.RIGHT
	var local_axis := (global_basis.inverse() * across).normalized()
	if local_axis.length_squared() < 0.5:
		local_axis = Vector3.RIGHT
	model.transform = Transform3D(Basis(local_axis, _rock).scaled(Vector3.ONE * grow), model.transform.origin)


## The shove on it this tick: the sum of the directions (from them to it) of
## every player pressing into it; how many in `_pushers`.
func _shove() -> Vector3:
	var sum := Vector3.ZERO
	_pushers = 0
	for p in Coop.all():
		var n := p as CharacterBody3D
		if n == null or n.get("_dead") == true or n.get("in_cutscene") == true:
			continue
		if not n.is_on_floor() or (n.has_method("is_restrained") and n.is_restrained()):
			continue
		# Standing on it (note 104: the way up to the booth): no shove.
		if _on_top(n):
			continue
		var touching := false
		for i in n.get_slide_collision_count():
			if n.get_slide_collision(i).get_collider() == self:
				touching = true
				break
		if not touching:
			var gap := n.global_position - global_position
			gap.y = 0.0
			touching = gap.length() < radius + TOUCH
		if not touching:
			continue
		var input: Vector2 = n.call("_move_input")
		if input == Vector2.ZERO:
			continue
		var wish := n.global_basis * Vector3(input.x, 0.0, input.y)
		wish.y = 0.0
		var to := global_position - n.global_position
		to.y = 0.0
		if wish.length_squared() < 0.0001 or to.length_squared() < 0.0001:
			continue
		if wish.normalized().dot(to.normalized()) < SHOVE_DOT:
			continue
		sum += to.normalized()
		_pushers += 1
		_pusher = n
	return sum


## A player standing in its way (not one shoving it), close enough to be run into.
func _player_ahead() -> bool:
	for p in Coop.all():
		var n := p as Node3D
		if n == null or n.get("_dead") == true or _on_top(n):
			continue
		var to := n.global_position - global_position
		to.y = 0.0
		if to.length() < radius + 0.5 and to.normalized().dot(_dir) > 0.35:
			return true
	return false


func _anyone_near() -> bool:
	for p in Coop.all():
		var n := p as Node3D
		if n == null:
			continue
		var to := n.global_position - global_position
		if absf(to.y) < 3.0 and Vector2(to.x, to.z).length() < radius + 1.5:
			return true
	return false


## The tub's rim over the floor (its kind's).
func rim() -> float:
	return float(RIM.get(kind, 1.85)) * grow
