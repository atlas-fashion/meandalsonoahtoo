extends Node3D

## A wall torch giving off a small pool of light that gutters and flares.
##
## Every torch seeds its own noise and starts at a random point along it, so a
## corridor of them never pulses in unison -- which is what gives the light its
## restless, un-mechanical feel.

@export var base_energy := 1.35
## How far the energy swings either side of base, as a fraction of it.
@export_range(0.0, 1.0) var flicker_amount := 0.4
@export var flicker_speed := 2.6
@export var light_range := 10.0
## Extra distance past the light's reach before flicker updates stop entirely.
@export var cull_margin := 14.0
## Chance per second of a deeper momentary guttering.
@export var gutter_chance := 0.35
@export var gutter_depth := 0.55

@onready var light: OmniLight3D = $Light
@onready var flame: MeshInstance3D = $Flame

## Shared across every torch in the level and refreshed once per frame. Looking
## the camera up per torch meant ~180 viewport traversals a frame for one answer
## that is the same for all of them.
static var _camera: Camera3D = null
static var _camera_frame := -1

var _noise := FastNoiseLite.new()
var _time := 0.0
var _gutter := 0.0
var _flame_material: StandardMaterial3D
var _flame_energy := 1.0


## How many frames between range checks. Phase-spread per torch, so the work is
## smeared across frames rather than spiking on one.
const CULL_PERIOD := 6

## A torch is static, so its world position is read once instead of every frame.
var _fixed_position := Vector3.ZERO
var _in_range := true
var _cull_phase := 0


func _ready() -> void:
	_fixed_position = global_position
	_cull_phase = int(randi() % CULL_PERIOD)
	_noise.seed = randi()
	_noise.frequency = 0.5
	_noise.fractal_octaves = 3
	# A random starting offset, so even identical seeds would drift apart.
	_time = randf() * 500.0

	light.omni_range = light_range
	var active := flame.get_active_material(0)
	if active is StandardMaterial3D:
		_flame_material = (active as StandardMaterial3D).duplicate()
		_flame_energy = _flame_material.emission_energy_multiplier
		flame.material_override = _flame_material


func _process(delta: float) -> void:
	# Beyond the light's fade-out there is nothing to see, so do not spend the
	# noise lookup. Most torches are skipped on any given frame.
	#
	# The skip itself used to cost more than it saved. The organic level carries
	# 347 of these, and every one of them was fetching the camera and reading
	# `global_position` -- which forces a global transform update -- purely to
	# decide to do nothing. Measured at 3.7 ms of CPU per frame, on a frame
	# budget of about 20.
	#
	# A torch never moves, so its position is cached once, and the range test
	# runs on one frame in CULL_PERIOD with the phase spread across instances.
	# Worst case a torch is a tenth of a second late noticing the player, which
	# is not perceptible on a light that is flickering anyway.
	if (Engine.get_process_frames() + _cull_phase) % CULL_PERIOD == 0:
		var camera := _shared_camera()
		if camera == null:
			_in_range = true
		else:
			var cutoff := light_range + cull_margin
			_in_range = _fixed_position.distance_squared_to(camera.global_position) \
				<= cutoff * cutoff
	if not _in_range:
		return

	_time += delta * flicker_speed

	# Occasional dip, decaying back, on top of the steady wobble.
	if _gutter > 0.0:
		_gutter = maxf(_gutter - delta * 2.5, 0.0)
	elif randf() < gutter_chance * delta:
		_gutter = gutter_depth

	var wobble := _noise.get_noise_1d(_time * 12.0)
	var factor := clampf(1.0 + wobble * flicker_amount - _gutter, 0.08, 2.0)

	light.light_energy = base_energy * factor
	if _flame_material != null:
		_flame_material.emission_energy_multiplier = _flame_energy * factor
	# A little vertical lick to match.
	flame.scale = Vector3(1.0, 1.0 + wobble * 0.16, 1.0)


func _shared_camera() -> Camera3D:
	var frame := Engine.get_process_frames()
	if frame != _camera_frame:
		_camera_frame = frame
		_camera = get_viewport().get_camera_3d()
	return _camera
