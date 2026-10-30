extends CharacterBody3D

## The Vardian sentinel (note 131): a bronze guardian in the ruins that wakes
## when the handle comes near and spars -- the lessons' blocking, parrying and
## first real fight. STAND-IN body (intro_figure.gd style "sentinel").
##
## Its glaive comes down slowly and plainly: raised over WIND, the eyes and the
## blade flaring as it opens its parry cue (player.gd `parry_cue`, CUE_BEFORE
## the blow, listening CUE_LISTEN), then the blow (`take_damage` on the player,
## whose guard decides block / parry). A parry throws it reeling for REEL.
## It cannot be hurt until the lessons let it be (`mortal`), and it pulls its
## blows rather than kill anyone (nobody dies in the intro).

signal fallen

const Figure := preload("res://scripts/intro_figure.gd")

const WIND := 1.05
const CUE_BEFORE := 0.42
const CUE_LISTEN := 0.62
const RECOVER := 0.7
const COOLDOWN := 1.3
const REACH := 3.1
const DAMAGE := 7.0
const REEL := 1.3
const WALK := 1.5
const KEEP := 2.3

enum State { DORMANT, WAKING, FIGHT, REEL, DEAD }

var state := State.DORMANT
var mortal := false
var health := 160.0
var max_health := 160.0
var engaged := false
var display_name := "VARDIAN SENTINEL"
## Blows it has thrown that the player met with their guard, and parried.
var blocked := 0
var parried := 0

var figure: Node3D
var _t := 0.0
var _swing := -1.0
var _cued := false
var _next := 0.0
var _target: Node3D = null
var _flare := 0.0


func _ready() -> void:
	collision_layer = 1 | 4
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.1
	cs.shape = cap
	cs.position.y = 1.05
	add_child(cs)
	figure = Figure.new()
	figure.set("style", &"sentinel")
	add_child(figure)
	figure.call("snap", &"dormant")
	_set_glow(0.15)


func wake() -> void:
	if state != State.DORMANT:
		return
	state = State.WAKING
	_t = 0.0
	figure.call("pose", &"guard", 2.5)


func _set_glow(e: float) -> void:
	var m: StandardMaterial3D = figure.get("glow_mat")
	if m != null:
		m.emission_energy_multiplier = e


func _physics_process(delta: float) -> void:
	_t += delta
	_flare = maxf(_flare - delta * 3.0, 0.0)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0
	match state:
		State.DORMANT, State.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0
		State.WAKING:
			_set_glow(lerpf(0.15, 3.0, clampf(_t / 1.6, 0.0, 1.0)))
			if _t > 1.8:
				state = State.FIGHT
				engaged = true
				add_to_group(&"boss")
				_next = _t + 0.6
		State.REEL:
			velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
			if _t > REEL:
				state = State.FIGHT
				figure.call("pose", &"guard", 6.0)
				_next = _t + 0.5
		State.FIGHT:
			_fight(delta)
	if state != State.FIGHT or _swing < 0.0:
		if state == State.FIGHT:
			_set_glow(3.0 + _flare * 6.0)
	move_and_slide()


func _fight(delta: float) -> void:
	_target = Coop.nearest(global_position) as Node3D
	if _target == null:
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	# Facing them, always; its turn is not quick.
	if dist > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 1.0 - exp(-(3.5 if _swing < 0.0 else 1.2) * delta))
	if _swing >= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_swing += delta
		if not _cued and _swing >= WIND - CUE_BEFORE:
			_cued = true
			_flare = 1.0
			if _target.has_method("parry_cue"):
				_target.call("parry_cue", self, CUE_LISTEN)
		_set_glow(lerpf(3.0, 9.0, clampf(_swing / WIND, 0.0, 1.0)))
		if _swing >= WIND and _swing - delta < WIND:
			figure.call("pose", &"strike", 22.0)
			_land(dist, to)
		if _swing >= WIND + RECOVER:
			_swing = -1.0
			figure.call("pose", &"guard", 6.0)
			_next = _t + COOLDOWN
		return
	# Closing in to striking distance, or standing off.
	var dir := to / maxf(dist, 0.01)
	var want := 0.0
	if dist > KEEP + 0.4:
		want = WALK
	elif dist < KEEP - 0.6:
		want = -WALK * 0.6
	velocity.x = move_toward(velocity.x, dir.x * want, 6.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * want, 6.0 * delta)
	if _t >= _next and dist < REACH + 0.3 and _target.get("in_cutscene") != true:
		_swing = 0.0
		_cued = false
		figure.call("pose", &"wind", 4.0)


func _land(dist: float, to: Vector3) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var fwd := global_basis.z
	fwd.y = 0.0
	if dist > REACH or fwd.normalized().dot(to.normalized()) < 0.4:
		return
	var hp := float(_target.get("health"))
	# It pulls the blow rather than kill (nobody dies in the intro).
	var amount := clampf(minf(DAMAGE, hp - 30.0), 0.0, DAMAGE)
	_target.call("take_damage", amount, to.normalized(), self)


## The player's guard took the blow (player.gd emits `guarded`; the lessons pass
## it on): counted here.
func on_guarded(was_parry: bool) -> void:
	if was_parry:
		parried += 1
	else:
		blocked += 1


## A parry's shove: reeling.
func apply_knockback(impulse: Vector3, _stun := 0.0) -> void:
	if state != State.FIGHT:
		return
	state = State.REEL
	_t = 0.0
	_swing = -1.0
	velocity += Vector3(impulse.x, 0.0, impulse.z) * 0.35
	figure.call("pose", &"reel", 10.0)


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
	if state == State.DEAD or state == State.DORMANT:
		return
	_flare = 0.6
	if not mortal:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_fall()


func _fall() -> void:
	state = State.DEAD
	engaged = false
	remove_from_group(&"boss")
	collision_layer = 1
	figure.call("pose", &"collapse", 3.0)
	var tw := create_tween()
	tw.tween_method(_set_glow, 3.0, 0.0, 1.6)
	fallen.emit()
