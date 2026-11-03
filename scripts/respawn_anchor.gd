extends Node3D

## A respawn beacon (once "anchor"): a rune-cut obelisk with a crystal turning
## over it, at the back of a holding cell (holding_cell.gd, note 154). It starts
## RED. Aim at it and HOLD E ("interact") for `CLAIM_TIME` to turn it gold;
## letting go, looking or walking away, or taking any damage meanwhile stops it
## and the hold starts again from nothing. Once gold it stays gold, and the
## player rises here when they die, until another beacon is claimed or chosen.
## Only one is ever active -- `maze.gd` keeps track (`_on_anchor_attuned`) and
## dims the old one. A gold beacon is chosen again with a plain press of E, the
## active one included: every choosing saves the map as it is now (what a death
## keeps), and the player always rises at the one chosen last (2026-10-11).
##
## Red it glows dull ember; gold it glows warm, and the active one blazes gold
## and gives off light (one light, on the active beacon, or the one being held).
##
## Local +Z points out of the dead end, towards the corridor: the way the player
## faces when they rise here (`spawn_point`, `spawn_yaw`).

signal attuned(anchor: Node3D)

const REACH := 2.4
const RED := Color(1.0, 0.16, 0.08)
const GOLD := Color(1.0, 0.72, 0.22)
## How long E is held to turn it gold.
const CLAIM_TIME := 3.0
## Where the player rises: this far out in front of it.
const RISE_AHEAD := 1.6
const CRYSTAL_HEIGHT := 3.05

var active := false
## Gold: claimed, so the player can rise here.
var claimed := false

var _prompt: Interact.Prompt
var _player: Node3D
var _near := false
## The hold under way: who is holding, how long so far, their health as it began.
var _holder: Node3D
var _hold := 0.0
var _holder_health := 0.0
var _crystal: MeshInstance3D
var _crystal_mat: StandardMaterial3D
var _rune_mat: StandardMaterial3D
var _light: OmniLight3D
var _clock := 0.0


func _ready() -> void:
	_clock = randf() * 10.0
	_build()
	_prompt = Interact.prompt("Hold E   Claim the beacon", Vector3(0.0, 1.6, 0.6))
	add_child(_prompt)
	_apply_look()


## Where the player rises, and which way they face (out of the dead end).
func spawn_point() -> Vector3:
	return global_position + global_basis.z * RISE_AHEAD + Vector3(0.0, 0.2, 0.0)


func spawn_yaw() -> float:
	var out := global_basis.z
	return atan2(-out.x, -out.z)


func set_active(on: bool) -> void:
	active = on
	_apply_look()


## Gold or red, as a save has it.
func set_claimed(on: bool) -> void:
	claimed = on
	_cancel_hold()
	_apply_look()


func _process(delta: float) -> void:
	_clock += delta
	# How far a hold has got, 0 to 1: the crystal turns from red to gold with it.
	var k := _hold / CLAIM_TIME
	if _crystal != null:
		_crystal.rotation.y = _clock * (1.6 if active else 0.4 + 3.0 * k)
		_crystal.position.y = CRYSTAL_HEIGHT + sin(_clock * 1.7) * (0.08 if active else 0.03)
	if active and _crystal_mat != null:
		_crystal_mat.emission_energy_multiplier = 4.0 + sin(_clock * 3.0) * 0.8
		if _light != null:
			_light.light_energy = 3.0 + sin(_clock * 3.0) * 0.4
	# Co-op: whoever is nearest, or in a scene with it (coop.gd `user_for`).
	_player = Coop.user_for(self, _player)
	if _player == null:
		_cancel_hold()
		return
	var to := _player.global_position - global_position
	_near = Vector2(to.x, to.z).length() <= REACH and absf(to.y) < 2.0 \
		and Interact.looked_at(self, 3.4, 0.1, [], _player) \
		and not _player.get("in_cutscene") and _player.get("_dead") != true
	if _holder != null:
		if _holder != _player or not _near or not is_instance_valid(_holder) \
				or not Coop.held(_holder, &"interact"):
			_cancel_hold()
		else:
			_hold += delta
			_show_hold()
			if _hold >= CLAIM_TIME:
				_claim()
	if claimed:
		_prompt.text = "E   Save progress" if active else "E   Rise here"
	else:
		_prompt.text = "Hold E   Claim the beacon"
	_prompt.progress = _hold / CLAIM_TIME if _holder != null else -1.0
	_prompt.visible = _near
	_prompt.player = _player


func _unhandled_input(event: InputEvent) -> void:
	if not _near or not Interact.pressed(event, _player):
		return
	if _player == null or _player.get("in_cutscene") or _player.get("_dead"):
		return
	get_viewport().set_input_as_handled()
	if not claimed:
		_start_hold(_player)
		return
	_near = false
	_prompt.visible = false
	attuned.emit(self)
	# A burst of its light, from the crystal.
	if _player.has_method("_guard_flash"):
		_player._guard_flash(_crystal.global_position, GOLD, true)
	# No announcement (2026-10-15, at the user's request): the burst of light
	# and the anchor waking are the only sign.


func _start_hold(by: Node3D) -> void:
	_cancel_hold()
	_holder = by
	_hold = 0.0
	if by.has_signal("health_changed"):
		by.connect("health_changed", _on_holder_health)
	_holder_health = float(by.get("health"))


## Any damage stops the hold, and it starts again from nothing.
func _on_holder_health(current: float, _maximum: float) -> void:
	if current < _holder_health - 0.001:
		_cancel_hold()
		return
	_holder_health = current


func _cancel_hold() -> void:
	if _holder != null and is_instance_valid(_holder) \
			and _holder.is_connected("health_changed", _on_holder_health):
		_holder.disconnect("health_changed", _on_holder_health)
	var was := _holder != null
	_holder = null
	_hold = 0.0
	if _prompt != null:
		_prompt.progress = -1.0
	if was:
		_apply_look()


func _claim() -> void:
	var by := _holder
	_cancel_hold()
	claimed = true
	_near = false
	_prompt.visible = false
	attuned.emit(self)
	if by != null and by.has_method("_guard_flash"):
		by._guard_flash(_crystal.global_position, GOLD, true)


## Red running into gold as the hold goes on, its light coming up.
func _show_hold() -> void:
	var k := clampf(_hold / CLAIM_TIME, 0.0, 1.0)
	var colour := RED.lerp(GOLD, k)
	_crystal_mat.albedo_color = colour.darkened(0.4)
	_crystal_mat.emission = colour
	_crystal_mat.emission_energy_multiplier = lerpf(0.9, 4.0, k)
	_rune_mat.emission = colour
	_rune_mat.emission_energy_multiplier = lerpf(0.5, 2.5, k)
	_light.visible = true
	_light.light_color = colour
	_light.light_energy = 3.0 * k


func _apply_look() -> void:
	if _crystal_mat == null:
		return
	var colour := GOLD if claimed else RED
	_crystal_mat.albedo_color = colour.darkened(0.4)
	_crystal_mat.emission = colour
	_crystal_mat.emission_energy_multiplier = 4.0 if active else (1.4 if claimed else 0.9)
	_rune_mat.emission = colour
	_rune_mat.emission_energy_multiplier = 2.5 if active else (0.8 if claimed else 0.5)
	_light.light_color = GOLD
	_light.light_energy = 3.0
	_light.visible = active


func _build() -> void:
	# The arch stone, without the instance colour the MultiMeshes feed it (a
	# plain mesh has none, and would render black).
	var stone := (load("res://scripts/module_level.gd")._synth_arch_material(1.0) as StandardMaterial3D) \
		.duplicate() as StandardMaterial3D
	stone.vertex_color_use_as_albedo = false
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 0.5, 1.3)
	box.material = stone
	plinth.mesh = box
	plinth.position = Vector3(0.0, 0.25, 0.0)
	add_child(plinth)

	var obelisk := MeshInstance3D.new()
	obelisk.name = "Obelisk"
	var shaft := CylinderMesh.new()
	shaft.radial_segments = 4
	shaft.rings = 1
	shaft.top_radius = 0.22
	shaft.bottom_radius = 0.42
	shaft.height = 2.2
	shaft.material = stone
	obelisk.mesh = shaft
	obelisk.position = Vector3(0.0, 0.5 + 1.1, 0.0)
	# Square to the plinth, a face towards the corridor.
	obelisk.rotation.y = PI * 0.25
	add_child(obelisk)

	_rune_mat = StandardMaterial3D.new()
	_rune_mat.albedo_color = Color(0.05, 0.08, 0.1)
	_rune_mat.emission_enabled = true
	var runes := MeshInstance3D.new()
	runes.name = "Runes"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bar := BoxMesh.new()
	# A carved line down the front face, with three cross-cuts.
	bar.size = Vector3(0.05, 1.5, 0.03)
	st.append_from(bar, 0, Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0.0, 1.55, 0.27)))
	for k in 3:
		bar.size = Vector3(0.2 - 0.04 * k, 0.04, 0.03)
		st.append_from(bar, 0, Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0.0, 1.0 + 0.45 * k, 0.31 - 0.035 * k)))
	st.set_material(_rune_mat)
	runes.mesh = st.commit()
	add_child(runes)

	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.emission_enabled = true
	_crystal_mat.roughness = 0.2
	_crystal_mat.metallic_specular = 0.8
	_crystal = MeshInstance3D.new()
	_crystal.name = "Crystal"
	var gem := SphereMesh.new()
	gem.radial_segments = 4
	gem.rings = 2
	gem.radius = 0.2
	gem.height = 0.62
	gem.material = _crystal_mat
	_crystal.mesh = gem
	_crystal.position = Vector3(0.0, CRYSTAL_HEIGHT, 0.0)
	add_child(_crystal)

	# The stone casts torch shadows; the glowing crystal does not.
	_crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_light = OmniLight3D.new()
	_light.light_color = GOLD
	_light.light_energy = 3.0
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.light_specular = 0.2
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 30.0
	_light.distance_fade_length = 8.0
	_light.position = Vector3(0.0, CRYSTAL_HEIGHT, 0.4)
	add_child(_light)

	# Solid to everyone and to sight; built before the navmesh bake, so
	# enemies path round it.
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, 2.7, 1.3)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 1.35, 0.0)
	body.add_child(cs)
