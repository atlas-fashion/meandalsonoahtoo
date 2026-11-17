extends Node3D

## The spear (2026-10-08): the second weapon, held when the weapon-wheel slot in
## hand holds `&"spear"`. Its fighting is its Weapon's (note 190, the timing-combat
## template: scenes/weapons/spear.tscn, scripts/combat/weapon.gd): LMB jabs,
## jabs, and LUNGES -- the third of the combo drawn back, then driven through,
## the player carried `lunge_distance` forward with it (player.gd adds the
## Weapon's `lunge_speed`) -- and the combo loops while the clicks keep coming in
## the chain window. Its sweep (Q) and its throw (F) went with the template.
##
## This node is what the eye sees: the user's spear (note 163) put on the
## Weapon's grip every frame (the model already runs down -Z from the hand, the
## grip's own convention), drawn back out of the left arm's way while the guard
## is up, lowered out of view when another slot is in hand. A scene can pose it
## instead (`player.spear_scene_pose`: the cage stab, a haft strike).

## From the hand to the point of the blade, and to the end of the butt: the
## model is fitted to these (tools/build_weapons.py, note 163); what a scene (`player.stab_at`, the haft strike)
## measures the spear by.
const TIP_REACH := 2.07
const BUTT_REACH := 0.67

## The pose the spear rests in, and where the hand holds it, head space (the
## Weapon's Rest marker is the same).
const REST_AT := Vector3(0.27, -0.36, -0.28)
const AIM_FAR := Vector3(0.0, -0.05, -6.0)
const BLAST_RADIUS := 4.5

var player: CharacterBody3D
## The spear's Weapon (player.gd `weapons[&"spear"]`).
var weapon: Weapon

var _model: Node3D
var _raise := 0.0
## The spear always leads the hand (note 190: every weapon does; first_person_arms.gd).
var lead := 1.0

static var _mats := {}


func setup(p: CharacterBody3D, w: Weapon) -> void:
	player = p
	weapon = w
	name = "Spear"
	_model = _build_model(true)
	add_child(_model)
	transform = _rest()
	_model.visible = false
	get_tree().create_timer(0.5).timeout.connect(_warm_up)


## True while the spear is in the hand and free to be used.
func ready_in_hand() -> bool:
	return true


func is_away() -> bool:
	return false


## A swing under way.
func busy() -> bool:
	return weapon != null and not weapon.is_idle()


## What every spear attack's time is multiplied by.
func time_scale() -> float:
	return player.attack_time_scale


func stance_ok() -> bool:
	return true


## No clip moves (note 190).
func motion() -> Array:
	return []


func reset() -> void:
	if weapon != null:
		weapon.reset()


func interrupt() -> void:
	if weapon != null:
		weapon.interrupt()


# --- Per frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	# A scene driving it (the cage stab, a haft strike: `player.spear_scene_pose`).
	var scene = player.spear_scene_pose()
	# Down too while a live rat hangs from the hand (rat_control.gd).
	var hands = player.get("rats")
	var held: bool = scene != null or (player.held_item() == &"spear" and not player.hands_busy \
		and not player.is_hidden() and not (hands != null and hands.get("holding") == true))
	# Raised into view when it is the slot in hand, lowered away otherwise.
	_raise = move_toward(_raise, 1.0 if held else 0.0, delta / 0.2)
	if scene != null:
		_raise = 1.0
	_model.visible = _raise > 0.01
	var pose: Transform3D = scene if scene != null else _grip()
	# The guard (`player._start_block`), eased by the player's own level.
	var g: float = player.guard_amount()
	if g > 0.0 and scene == null:
		pose = Transform3D(pose.basis, pose.origin + PLAYER.GUARD_DRAW * g)
	var lowered := Transform3D(pose.basis, pose.origin + Vector3(0.05, -0.7, 0.25))
	var up: float = _raise * (1.0 - player.weapon_dip())
	transform = lowered.interpolate_with(pose, up * up * (3.0 - 2.0 * up))


## Where the Weapon has the hand (its Grip, head space).
func _grip() -> Transform3D:
	if weapon != null and weapon.grip != null:
		return weapon.grip.transform
	return _rest()


# --- Poses ------------------------------------------------------------------------

func _aimed(at: Vector3, target: Vector3, roll := 0.0) -> Transform3D:
	var b := _facing(target - at)
	return Transform3D(b * Basis(Vector3.FORWARD, roll), at)


## -Z down `dir`; safe straight up or down, where looking_at with UP fails.
static func _facing(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.BACK
	return Basis.looking_at(dir, up)


## The player's script, for its `GUARD_DRAW`.
const PLAYER := preload("res://scripts/player.gd")


func _rest() -> Transform3D:
	# From the lower right corner up to just under and right of the crosshair,
	# so the blade is in plain view rather than hidden behind the reticle.
	return _aimed(REST_AT, Vector3(0.35, 0.05, -6.0), 0.25)


# --- The rat bomb's burst (rat_control.gd borrows it) ------------------------------

func _blast_visual(at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "SpearBlast"
	holder.top_level = true
	player.get_parent().add_child(holder)
	holder.global_position = at
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	ball.mesh = sphere
	ball.material_override = _fire_mat()
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * 0.3
	holder.add_child(ball)
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(6.0, 6.0)
	flash.mesh = quad
	flash.material_override = _mat(&"flash")
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(flash)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = _mat(&"ring")
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3.ONE * 0.4
	holder.add_child(ring)
	var t := holder.create_tween().set_parallel(true)
	t.tween_property(ball, "scale", Vector3.ONE * BLAST_RADIUS * 0.7, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_method(func(v: float) -> void: ball.set_instance_shader_parameter(&"fade", v),
		0.0, 1.0, 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_property(flash, "transparency", 1.0, 0.18)
	t.tween_property(ring, "scale", Vector3(BLAST_RADIUS, 1.0, BLAST_RADIUS) * 1.1, 0.4).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "transparency", 1.0, 0.45)
	if Graphics.effects:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 10.0
		light.omni_range = 10.0
		light.shadow_enabled = false
		holder.add_child(light)
		t.tween_property(light, "light_energy", 0.0, 0.5)
		preload("res://scripts/door_debris.gd").dust(holder, at, Vector3.UP, 34, 1.4)
	t.chain().tween_interval(0.9)
	t.chain().tween_callback(holder.queue_free)


## The burst's materials compiling on first use would stall that frame: draw a
## speck of each in front of the camera at load.
func _warm_up() -> void:
	var cam := Coop.camera(player)
	if cam == null:
		return
	for key in [&"fire", &"flash", &"ring"]:
		var speck := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.002, 0.002)
		speck.mesh = quad
		speck.material_override = _fire_mat() if key == &"fire" else _mat(key)
		cam.add_child(speck)
		speck.position = Vector3(0.0, 0.0, -0.5)
		get_tree().create_timer(0.3).timeout.connect(speck.queue_free)


# --- Materials and the model ------------------------------------------------------

static var _fire: ShaderMaterial


static func _fire_mat() -> ShaderMaterial:
	if _fire == null:
		_fire = ShaderMaterial.new()
		_fire.shader = load("res://shaders/spear_blast.gdshader")
	return _fire


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"fire", &"flash", &"ring", &"tether":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.no_depth_test = key == &"flash"
			match key:
				&"fire":
					m.albedo_color = Color(1.0, 0.5, 0.15, 0.8)
				&"flash":
					m.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
					m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
					var grad := GradientTexture2D.new()
					grad.fill = GradientTexture2D.FILL_RADIAL
					grad.fill_from = Vector2(0.5, 0.5)
					grad.fill_to = Vector2(1.0, 0.5)
					var g := Gradient.new()
					g.set_color(0, Color(1, 1, 1, 1))
					g.set_color(1, Color(1, 1, 1, 0))
					grad.gradient = g
					m.albedo_texture = grad
				&"ring":
					m.albedo_color = Color(1.0, 0.7, 0.35, 0.7)
				&"tether":
					m.albedo_color = Color(1.0, 0.62, 0.25, 0.85)
	_mats[key] = m
	return m


## The user's spear (note 163), fitted by tools/build_weapons.py: along -Z, tip
## forward, the hand at the origin, the butt's end at +BUTT_REACH and the point
## at -TIP_REACH.
const MODEL := preload("res://models/spear.glb")

## Thrown, the head (socket and blade) glows like the tether, so it can be
## followed out and back: its materials, lit, made once.
static var _hot := {}


static func _hot_mat(source: BaseMaterial3D) -> BaseMaterial3D:
	if not _hot.has(source):
		var m := source.duplicate() as BaseMaterial3D
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.16)
		m.emission_energy_multiplier = 2.2
		_hot[source] = m
	return _hot[source]


## `in_hand` gives every surface the viewmodel's pulled-forward depth, as the
## sword has; out of the hand it is the thrown spear, its head alight.
func _build_model(in_hand: bool) -> Node3D:
	var root := MODEL.instantiate() as Node3D
	root.name = "SpearModel"
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if source == null:
				continue
			var mat := source
			if in_hand:
				mat = source.duplicate() as BaseMaterial3D
				mat.use_z_clip_scale = true
				mat.z_clip_scale = float(player.get("sword_draw_depth")) if player != null else 0.12
			elif source.resource_name in ["SpearSocket", "SpearBlade"]:
				mat = _hot_mat(source)
			mi.set_surface_override_material(i, mat)
	return root


func _head() -> Node3D:
	return get_parent() as Node3D


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The in-hand model's `z_clip_scale`: 1.0 for real depth while it is driven into
## something in a scene, so what it goes into hides the buried part.
func set_depth(scale: float) -> void:
	if _model == null:
		return
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(i) as BaseMaterial3D
			if mat != null and mat.use_z_clip_scale:
				mat.z_clip_scale = scale
