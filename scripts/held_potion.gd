extends Node3D

## The health potion in the player's right hand while its hotbar slot is the
## one selected. Built by player.gd under the Head, so it moves with the view
## and the head bob like the sword does.
##
## The model is `models/potion_held.glb` (tools/build_potion.py); its materials
## are replaced here by name, because the glass needs alpha blending and the
## liquid a glow that the glTF round trip does not carry reliably.
##
## It never needs the sword's wall test: it is held inside the player's own
## collision radius (0.4 m), so a wall can never come nearer the eye than the
## flask is. `HOLD` keeps its whole width inside that.
##
##   want     true while a potion is the selected item; it rises into view,
##            and drops out of it when this goes false
##   drink()  lifts it to the mouth and back (player.gd calls it on a drink)

const MODEL := preload("res://models/potion_held.glb")

## Where it is held, in the head's frame, and how it is turned there.
## Half the modelled size: 13.5 cm of flask held 21 cm from the eye.
const SCALE := 0.5
const HOLD := Vector3(0.17, -0.155, -0.21)
const TURN := Vector3(0.10, -0.45, 0.14)
## How far below HOLD it waits while put away.
const LOWER := 0.3
const RAISE_RATE := 4.0
const LOWER_RATE := 6.0
const DRINK_TIME := 0.62
## The small health potion (note 130) is the same flask at this size.
const SMALL_SCALE := 0.72

## Saturated and not too bright: ACES desaturates anything hot, and at 2.6 the
## liquid read as pale mint rather than green.
const LIQUID := Color(0.08, 0.8, 0.18)
const GLOW := 1.1

var want := false
## Holding the small health potion: the flask drawn smaller.
var small := false

var _raise := 0.0
var _drink := -1.0
var _drink_time := DRINK_TIME
var _clock := 0.0
var _liquid_mat: StandardMaterial3D
var _model: Node3D


func _ready() -> void:
	name = "HeldPotion"
	_model = MODEL.instantiate() as Node3D
	_model.scale = Vector3.ONE * SCALE
	add_child(_model)
	_dress(_model)
	# No light of its own. A small green omni inside the flask was tried and
	# measured at ~1 ms a frame on the P620 (19.6 vs 18.5 ms, the same at a
	# 0.8 m range as at 1.4), and all it visibly did was tint the glass neck and
	# the cork green from inside. A faint glow on the glass does that for free.
	visible = false


## Real materials for the placeholder ones, matched by name.
func _dress(node: Node) -> void:
	for child in node.get_children():
		_dress(child)
	var mi := node as MeshInstance3D
	if mi == null:
		return
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s in mi.mesh.get_surface_count():
		var source := mi.mesh.surface_get_material(s)
		var named := source.resource_name if source != null else ""
		mi.set_surface_override_material(s, _material_for(named, mi.name))


func _material_for(material_name: String, node_name: String) -> Material:
	var key := material_name if material_name != "" else node_name
	var m := StandardMaterial3D.new()
	if key.contains("Glass"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Clear: at 0.2 alpha the torchlit glass laid a beige film over the glow.
		m.albedo_color = Color(0.62, 0.9, 0.7, 0.09)
		m.roughness = 0.05
		m.metallic_specular = 0.9
		m.rim_enabled = true
		m.rim = 0.2
		m.rim_tint = 0.5
		# The liquid's light caught in the glass.
		m.emission_enabled = true
		m.emission = Color(0.2, 1.0, 0.35)
		m.emission_energy_multiplier = 0.35
	elif key.contains("Liquid"):
		# Nearly all glow, barely lit: lit, the orange hand torch mixed yellow
		# into it and it read as lime. A little albedo keeps some shape.
		m.albedo_color = Color(0.02, 0.2, 0.05)
		m.roughness = 0.2
		m.emission_enabled = true
		m.emission = LIQUID
		m.emission_energy_multiplier = GLOW
		_liquid_mat = m
	elif key.contains("Cork"):
		m.albedo_color = Color(0.42, 0.28, 0.16)
		m.roughness = 0.92
	else:
		m.albedo_color = Color(0.5, 0.42, 0.28)
		m.roughness = 0.95
	return m


## Lifts it to the mouth, holds it there sipping for the rest of `duration`
## seconds, and lowers it again at the end.
func drink(duration := DRINK_TIME) -> void:
	_drink = 0.0
	_drink_time = maxf(duration, 0.1)


func is_drinking() -> bool:
	return _drink >= 0.0


## Cut short (the player struck or was struck): straight into the lowering
## that ends a drink, rather than snapping away from the lips.
func stop() -> void:
	if _drink < 0.0:
		return
	var edge := minf(0.35 / _drink_time, 0.45)
	_drink = maxf(_drink, 1.0 - edge)


func _process(delta: float) -> void:
	_clock += delta
	# Stays up through a drink even if that was the last one in the stack.
	var up := want or _drink >= 0.0
	_raise = move_toward(_raise, 1.0 if up else 0.0, (RAISE_RATE if up else LOWER_RATE) * delta)
	visible = _raise > 0.001
	if not visible:
		_drink = -1.0
		return
	var e := _raise * _raise * (3.0 - 2.0 * _raise)
	_model.scale = Vector3.ONE * SCALE * (SMALL_SCALE if small else 1.0)

	var d := 0.0
	var sip := 0.0
	if _drink >= 0.0:
		_drink += delta / _drink_time
		if _drink >= 1.0:
			_drink = -1.0
		else:
			# Up to the lips in the first ~0.35 s, down in the last, held between
			# with the slow tip and settle of swallowing.
			var edge := minf(0.35 / _drink_time, 0.45)
			d = minf(smoothstep(0.0, edge, _drink), 1.0 - smoothstep(1.0 - edge, 1.0, _drink))
			sip = sin(_drink * _drink_time * 4.5) * 0.12 * d

	# A slow sway, so it does not hang dead still in the hand.
	var sway := Vector3(sin(_clock * 1.3) * 0.02, sin(_clock * 0.9 + 1.0) * 0.03, sin(_clock * 1.1) * 0.025)
	# Drinking: up and in towards the mouth, tipped back over the lip.
	position = HOLD + Vector3(-0.09 * d, 0.1 * d - LOWER * (1.0 - e), 0.05 * d)
	rotation = TURN + sway + Vector3(1.25 * d + sip, 0.0, 0.35 * d)

	if _liquid_mat != null:
		_liquid_mat.emission_energy_multiplier = GLOW * (1.0 + 0.12 * sin(_clock * 2.4))
