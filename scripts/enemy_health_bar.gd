extends MeshInstance3D

## A very thin health bar floating over an enemy, with the player's bar's
## effects: damage snaps the red down and leaves an orange stretch that holds
## for a beat and then drains away; a gain shows green first, and the red
## climbs into it. Polls its host's `health` and `max_health`, so enemies need
## nothing beyond `attach(self)` in their `_ready`.
##
## One shared opaque material, the values as instance uniforms: no per-enemy
## material, no blending, no sorting.

const SHADER := preload("res://shaders/enemy_health_bar.gdshader")
## Size of the bar, metres, and its clearance above the top of the body.
const WIDTH := 0.8
const HEIGHT := 0.035
const CLEARANCE := 0.35
## Not drawn beyond this, metres: a two-pixel line is no use to anyone.
const RANGE := 28.0
## Same timings as the HUD's bars.
const TRAIL_HOLD := 0.45
const TRAIL_DRAIN := 0.9
const GAIN_HOLD := 0.3
const GAIN_CLIMB := 0.75

static var _material: ShaderMaterial
static var _mesh: QuadMesh

var _host: Node3D
var _shown := -1.0
var _trail := 0.0
var _last := 0.0
var _trail_hold := 0.0
var _gain_hold := 0.0
var _gain_rate := 0.0


## Hangs a bar over `host`, sized to it and raised clear of its collision.
static func attach(host: Node3D) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	bar.set_script(load("res://scripts/enemy_health_bar.gd"))
	bar.name = "HealthBar"
	host.add_child(bar)
	return bar


func _ready() -> void:
	_host = get_parent() as Node3D
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(1.0, 1.0)
	mesh = _mesh
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = RANGE
	var top := _top_of(_host)
	# Wider for bigger bodies, never thicker.
	var span := WIDTH * clampf(_radius_of(_host) / 0.45, 0.8, 2.2)
	position = Vector3(0.0, top + CLEARANCE, 0.0)
	scale = Vector3(span, HEIGHT, 1.0)
	visible = false


func _process(delta: float) -> void:
	if _host == null or not is_instance_valid(_host):
		return
	var maximum: float = maxf(float(_host.get("max_health")), 1.0)
	var current: float = clampf(float(_host.get("health")), 0.0, maximum)
	var dying: Variant = _host.get("_dying")
	var awake: Variant = _host.get("awake")
	# A mimic is a chest until it springs, and a chest has no health bar.
	# Nor does anything a scene is driving (the Remnant in the morgue).
	var want: bool = current > 0.0 and not (dying == true) and awake != false \
		and _host.get("scripted") != true
	if visible != want:
		visible = want
	if not want:
		return

	if _shown < 0.0:
		_shown = current
		_trail = current
		_last = current
	if current < _last:
		_trail_hold = TRAIL_HOLD
		_trail = maxf(_trail, _last)
	elif current > _last:
		_gain_hold = GAIN_HOLD
		_gain_rate = (current - _shown) / GAIN_CLIMB
	_last = current

	if current < _shown:
		_shown = current
		_gain_hold = 0.0
	elif current > _shown:
		if _gain_hold > 0.0:
			_gain_hold -= delta
		else:
			_shown = minf(_shown + _gain_rate * delta, current)
	if _trail < current:
		_trail = current
	elif _trail > current:
		if _trail_hold > 0.0:
			_trail_hold -= delta
		else:
			_trail = maxf(_trail - maximum / TRAIL_DRAIN * delta, current)

	set_instance_shader_parameter(&"shown", _shown / maximum)
	set_instance_shader_parameter(&"health", current / maximum)
	set_instance_shader_parameter(&"trail", _trail / maximum)


## The highest point of the host's own collision shapes, in its frame.
static func _top_of(host: Node3D) -> float:
	var top := 1.8
	var found := false
	for child in host.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var half := 0.0
		if cs.shape is CapsuleShape3D:
			half = (cs.shape as CapsuleShape3D).height * 0.5
		elif cs.shape is CylinderShape3D:
			half = (cs.shape as CylinderShape3D).height * 0.5
		elif cs.shape is BoxShape3D:
			half = (cs.shape as BoxShape3D).size.y * 0.5
		elif cs.shape is SphereShape3D:
			half = (cs.shape as SphereShape3D).radius
		else:
			continue
		var y := cs.position.y + half * cs.scale.y
		top = y if not found else maxf(top, y)
		found = true
	return top


static func _radius_of(host: Node3D) -> float:
	for child in host.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		if cs.shape is CapsuleShape3D:
			return (cs.shape as CapsuleShape3D).radius
		if cs.shape is CylinderShape3D:
			return (cs.shape as CylinderShape3D).radius
		if cs.shape is SphereShape3D:
			return (cs.shape as SphereShape3D).radius
		if cs.shape is BoxShape3D:
			return (cs.shape as BoxShape3D).size.x * 0.5
	return 0.45
