extends CharacterBody3D

## The robot rat once it is set down (2026-10-18): the workbench's iron rat
## (rat_model.gd, robot) with its own camera between its eyes. rat_control.gd
## places it, makes its camera the one drawing, feeds it the player's movement
## (`move`) and look (`turn`) for as long as the fuse lasts, and blows it up.
## Faster than the player walks; it cannot jump. Collides with the player's own
## walls and floors (1 | 9), never with the player.

const RAT_MODEL := preload("res://scripts/rat_model.gd")
const SPEED := 5.5
const ACCEL := 40.0
## The camera: between the eyes, a hair in front of them (the scaled model's
## eyes are at z -0.16), so the snout shows at the foot of the view.
const EYE_AT := Vector3(0.0, 0.115, -0.165)
const FOV := 88.0
## The visual layer its own body is drawn on (20; 12, 13 and 16 are taken).
const SELF_LAYER := 1 << 19
const PITCH_MIN := -0.9
const PITCH_MAX := 0.75
## A little light of its own at the eyes, in their colour (effects on only).
const LIGHT_RANGE := 3.5
const LIGHT_ENERGY := 0.7

var camera: Camera3D
## The player's movement input (x right, y back), set every tick by rat_control.
var move := Vector2.ZERO
var pitch := 0.0

var _model: Node3D
var _tail: Node3D
var _phase := 0.0
var _clock := 0.0


func setup(player: Node3D) -> void:
	name = "RobotRat"
	collision_layer = 0
	collision_mask = 1 | 256
	floor_snap_length = 0.2
	add_collision_exception_with(player)
	# A flat box, as rat.gd's: a small ball dropped into the floor's cracks.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.22, 0.14, 0.36)
	shape.shape = box
	shape.position = Vector3(0.0, 0.07, 0.0)
	add_child(shape)
	_model = RAT_MODEL.build(true)
	add_child(_model)
	_tail = _model.get_node("Tail")
	# Drawn on its own layer, which its own camera leaves out: from between
	# the eyes the snout, lit by the eye light, was a great blob filling the
	# foot of the view.
	for g in RAT_MODEL.parts(_model):
		g.layers = SELF_LAYER
	camera = Camera3D.new()
	camera.name = "RatEyes"
	camera.position = EYE_AT
	camera.fov = FOV
	camera.near = 0.02
	var own := player.get("camera") as Camera3D
	if own != null:
		camera.far = own.far
		camera.attributes = own.attributes
		camera.cull_mask = own.cull_mask
	camera.cull_mask &= ~SELF_LAYER
	add_child(camera)
	if Graphics.effects:
		var light := OmniLight3D.new()
		light.name = "EyeLight"
		light.position = EYE_AT + Vector3(0.0, 0.05, -0.05)
		light.omni_range = LIGHT_RANGE
		light.light_energy = LIGHT_ENERGY
		light.light_color = RAT_MODEL.enforcer_eye_colour().lerp(Color.WHITE, 0.45)
		light.shadow_enabled = false
		add_child(light)


## Looking about: the body turns with yaw, the camera alone pitches.
func turn(yaw: float, dpitch: float) -> void:
	rotate_y(yaw)
	pitch = clampf(pitch + dpitch, PITCH_MIN, PITCH_MAX)
	if camera != null:
		camera.rotation.x = pitch


func _physics_process(delta: float) -> void:
	_clock += delta
	if not is_on_floor():
		velocity += get_gravity() * delta
	var dir := global_basis * Vector3(move.x, 0.0, move.y)
	dir.y = 0.0
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	velocity.x = move_toward(velocity.x, dir.x * SPEED, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * SPEED, ACCEL * delta)
	move_and_slide()


func _process(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 0.4:
		_phase += delta * (18.0 + speed * 2.5)
		_model.position.y = absf(sin(_phase)) * 0.01
		_tail.rotation.y = sin(_phase * 0.5) * 0.3
		if camera != null:
			camera.position.y = EYE_AT.y + absf(sin(_phase)) * 0.004
	else:
		_model.position.y = 0.0
		_tail.rotation.y = sin(_clock * 1.6) * 0.25
		if camera != null:
			camera.position.y = EYE_AT.y
