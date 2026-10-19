extends Node3D

## A wall torch giving off a small pool of light that gutters and flares.
##
## Every torch seeds its own noise and starts at a random point along it, so a
## corridor of them never pulses in unison -- which is what gives the light its
## restless, un-mechanical feel.

@export var base_energy := 1.35
## How far the energy swings either side of base, as a fraction of it.
## 0.62 since 2026-10-10 ("increase the firelight effect"; was 0.4).
@export_range(0.0, 1.0) var flicker_amount := 0.62
@export var flicker_speed := 2.6
@export var light_range := 10.0
## Extra distance past the light's reach before flicker updates stop entirely.
@export var cull_margin := 14.0
## Chance per second of a deeper momentary guttering.
@export var gutter_chance := 0.6
@export var gutter_depth := 0.6
## The light sways with the flame by up to this much (metres), so its pool on
## the stone shifts as real firelight does, and runs hotter (yellow) as it
## flares and redder as it gutters by up to `colour_swing`.
@export var sway := 0.07
@export var colour_swing := 0.35
## The glow round the flame, drawn this much larger than the scene's card.
const HALO_SCALE := 1.6
const HOT := Color(1.0, 0.8, 0.55)
const EMBER := Color(1.0, 0.52, 0.27)
## Time constant of a light low-pass on the flicker (2026-10-14). The noise's
## fastest octave runs past the frame rate, so the light jumped by 16% of its
## brightness frame to frame on average and by over 15% on 45% of frames --
## measured, and it read as jarring. Smoothed, the swells and dips survive.
const FLICKER_SMOOTH := 0.03
## A gutter sinks in over this long instead of in one frame.
const GUTTER_IN := 0.12
var _light_home := Vector3.ZERO
## Wear the brick kit's Tripo torch (its ring bracket, wooden handle and wrapped
## head, cut from the torch pillar: "torch_mount") instead of this scene's old
## procedural plate, arm, ring, handle and head (2026-10-10: "always use the new
## torch bottom, never the old one"). Off for a torch whose body is something
## else -- the torch pillar's own carved torch, a brazier.
@export var kit_mount := true
## A sewer torch (sewer.gd), ranked against the sewer's level only.
var sewer := false
## Below this the camera is in the sewer (sewer.gd SPLIT_Y).
const SEWER_SPLIT_Y := -4.0
const OTHER_LEVEL := 1000.0
## The kit torch hangs with its head's top here (just above the flame's base),
## its wall side at z = 0; its head is KIT_HEAD_OUT off the wall, and the
## flame, halo, embers and light move out to it.
const KIT_TOP := Vector3(0.0, 0.42, 0.0)
const KIT_HEAD_OUT := 0.24
const OLD_FLAME_OUT := 0.49

@onready var light: OmniLight3D = $Light
## The fire is a shader card (shaders/torch_flame.gdshader) shared by every torch;
## per-torch variation goes through its INSTANCE uniforms, so there is still one
## material in the level rather than one per torch.
@onready var flame: GeometryInstance3D = $Flame
@onready var halo: GeometryInstance3D = get_node_or_null("Halo")
@onready var embers: GPUParticles3D = get_node_or_null("Embers")

## Shared across every torch in the level and refreshed once per frame. Looking
## the camera up per torch meant ~180 viewport traversals a frame for one answer
## that is the same for all of them.
static var _camera: Camera3D = null
static var _camera_frame := -1

## 0 fire, 1 ice: set by the HUD as the Remnant comes very close (hud.gd
## `_update_dread`). One value for every torch; each one in range fades its
## light and flame toward ICE_LIGHT and the flame shader's ice ramp.
static var chill := 0.0
const ICE_LIGHT := Color(0.42, 0.72, 1.0)

## --- Only shadowed torches give light (2026-10-12) ------------------------------
##
## Torchlight must never pass through stone, and a light lights through walls
## unless it casts a shadow -- but every shadow costs passes over the geometry,
## so only so many can cast. The torches hung by `module_level._hang_torch`
## (light meta "torch_shadow") are therefore RANKED by distance from the camera
## every RANK_PERIOD frames, and only the nearest `Graphics.torch_lights` give
## light at all; every one of those casts. The rest keep their flame and halo
## and give none. A torch fades over LIT_FADE metres of distance at the edge of
## the set, so pools come and go smoothly as the player walks.
static var _managed: Array = []
static var _rank_frame := -1
const RANK_PERIOD := 4
const LIT_FADE := 4.0
## How fast a pool follows its target (fraction a second).
const LIT_EASE := 2.5
## The positional shadow atlas's slots (graphics_settings `_apply_viewport`).
const SHADOW_SLOTS := 24
## The nearest-N set this torch belongs to: 1 lit, 0 dark, between at the edge.
var _lit := 0.0
var _lit_target := 0.0
var _is_managed := false

var _noise := FastNoiseLite.new()
var _time := 0.0
var _gutter := 0.0
var _gutter_falling := false
## The flicker after its low-pass (see FLICKER_SMOOTH).
var _factor := 1.0
## The light's own colour, read once, and the chill this torch last showed.
var _fire_colour := Color.WHITE
var _chill_shown := 0.0


## How many frames between range checks. Phase-spread per torch, so the work is
## smeared across frames rather than spiking on one.
const CULL_PERIOD := 6

## A torch is static, so its world position is read once instead of every frame.
var _fixed_position := Vector3.ZERO
var _in_range := true
var _cull_phase := 0


func _ready() -> void:
	if kit_mount:
		_wear_kit_mount()
	_fixed_position = global_position
	_cull_phase = int(randi() % CULL_PERIOD)
	_noise.seed = randi()
	_noise.frequency = 0.5
	_noise.fractal_octaves = 3
	# A random starting offset, so even identical seeds would drift apart.
	_time = randf() * 500.0

	light.omni_range = light_range
	_fire_colour = light.light_color
	_light_home = light.position
	if halo != null:
		halo.scale *= HALO_SCALE
	var seed := randf() * 100.0
	flame.set_instance_shader_parameter("seed", seed)
	if halo != null:
		halo.set_instance_shader_parameter("seed", seed)
	# Embers are an effect that only exists sometimes, so they follow the
	# effects knob (CLAUDE.md section 3), now and whenever it changes.
	if embers != null:
		var gfx := get_node_or_null("/root/Graphics")
		if gfx != null:
			_apply_effects(gfx)
			gfx.changed.connect(_apply_effects.bind(gfx))
	# Deferred: `_hang_torch` tags the light after adding the torch to the tree.
	_register.call_deferred()


func _register() -> void:
	if not is_instance_valid(light) or not light.has_meta("torch_shadow"):
		return
	_is_managed = true
	_managed.append(self)
	# Dark until the first ranking says otherwise.
	_lit = 0.0
	light.visible = false


func _exit_tree() -> void:
	if _is_managed:
		_managed.erase(self)


## Ranks every managed torch by distance from the camera and sets each one's
## target: only the nearest `Graphics.torch_lights` give light.
static func _rank(cameras: Array[Vector3], limit: int) -> void:
	var distances := PackedFloat32Array()
	distances.resize(_managed.size())
	for i in _managed.size():
		# Co-op: by the nearer of the two cameras (one point outside co-op).
		var best := INF
		for camera_at in cameras:
			var d := (_managed[i]._fixed_position as Vector3).distance_to(camera_at)
			# Torches on the other level (sewer / dungeon) light nothing the
			# camera can see through the rock: rank them last.
			if _managed[i].sewer != (camera_at.y < SEWER_SPLIT_Y):
				d += OTHER_LEVEL
			best = minf(best, d)
		distances[i] = best
	var cut := INF
	if limit <= 0:
		cut = -INF
	elif _managed.size() > limit:
		var sorted := distances.duplicate()
		sorted.sort()
		# The first torch left out sits exactly at the cut: target 0.
		cut = sorted[limit]
	var fading: Array = []
	var alight := 0
	for i in _managed.size():
		var t = _managed[i]
		t._lit_target = clampf((cut - distances[i]) / LIT_FADE, 0.0, 1.0)
		if t._lit_target <= 0.0 and not t._in_range:
			# It will not process again until it is near: put it out now.
			t._lit = 0.0
			t.light.visible = false
		if t._lit > 0.0 or t._lit_target > 0.0:
			alight += 1
			if t._lit_target < t._lit:
				fading.append([distances[i], t])
	# Never more lit than the atlas has slots (Graphics: 24): a lit torch with
	# no slot casts nothing and lights through walls. After a jump (a respawn)
	# the old set would still be fading out as the new one fades in; the
	# furthest of those go out at once instead.
	if alight > SHADOW_SLOTS:
		fading.sort_custom(func(a, b): return a[0] > b[0])
		for f in fading:
			if alight <= SHADOW_SLOTS:
				break
			f[1]._lit = 0.0
			f[1]._lit_target = 0.0
			f[1].light.visible = false
			alight -= 1


var _effects_on := true


func _wear_kit_mount() -> void:
	var kit = load("res://scripts/brick_level.gd")
	var mesh: Mesh = kit.standalone("torch_mount") if kit != null else null
	if mesh == null:
		return
	for part in ["Plate", "Arm", "Ring", "Handle", "Head"]:
		var n := get_node_or_null(part) as Node3D
		if n != null:
			n.visible = false
	var mount := MeshInstance3D.new()
	mount.name = "KitTorch"
	mount.mesh = mesh
	# The kit's torch reaches out along its +Z; this scene's along -Z.
	mount.transform = Transform3D(Basis(Vector3.UP, PI), KIT_TOP)
	mount.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mount.visibility_range_end = 30.0
	mount.visibility_range_end_margin = 5.0
	add_child(mount)
	var shift := Vector3(0.0, 0.0, OLD_FLAME_OUT - KIT_HEAD_OUT)
	for part in ["Flame", "Halo", "Embers", "Light"]:
		var n := get_node_or_null(part) as Node3D
		if n != null:
			n.position += shift


func _apply_effects(gfx: Node) -> void:
	_effects_on = bool(gfx.get("effects"))
	embers.visible = _effects_on
	embers.emitting = _effects_on and _in_range


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
	var now_frame := Engine.get_process_frames()
	if _is_managed and now_frame != _rank_frame and now_frame % RANK_PERIOD == 0:
		_rank_frame = now_frame
		var points := _camera_points()
		var gfx := get_node_or_null("/root/Graphics")
		if not points.is_empty():
			var budget := float(gfx.get("torch_lights")) if gfx != null else 12.0
			# Co-op: its own share (graphics_settings.gd `coop_torch_share`).
			if Coop.active and gfx != null:
				budget = maxf(4.0, roundf(budget * float(gfx.get("coop_torch_share"))))
			_rank(points, int(budget))
	if (Engine.get_process_frames() + _cull_phase) % CULL_PERIOD == 0:
		var points := _camera_points()
		if points.is_empty():
			_in_range = true
		else:
			# Co-op: in range of either camera.
			var cutoff := light_range + cull_margin
			_in_range = false
			for at in points:
				if _fixed_position.distance_squared_to(at) <= cutoff * cutoff:
					_in_range = true
		# Out of range the embers stop simulating too, not just drawing.
		if embers != null and embers.emitting != (_effects_on and _in_range):
			embers.emitting = _effects_on and _in_range
	if not _in_range:
		return

	# The Remnant near: fire going cold. Only touched when it changes.
	if absf(chill - _chill_shown) > 0.002:
		_chill_shown = chill
		light.light_color = _fire_colour.lerp(ICE_LIGHT, chill)
		flame.set_instance_shader_parameter("chill", chill)
		if halo != null:
			halo.set_instance_shader_parameter("chill", chill)

	_time += delta * flicker_speed

	# Occasional dip on top of the steady wobble: it sinks in over GUTTER_IN
	# (it used to drop in a single frame, a visible blink) and recovers.
	if _gutter_falling:
		_gutter = move_toward(_gutter, gutter_depth, delta * gutter_depth / GUTTER_IN)
		_gutter_falling = _gutter < gutter_depth
	elif _gutter > 0.0:
		_gutter = maxf(_gutter - delta * 2.5, 0.0)
	elif randf() < gutter_chance * delta:
		_gutter_falling = true

	var wobble := _noise.get_noise_1d(_time * 12.0)
	var raw := clampf(1.0 + wobble * flicker_amount - _gutter, 0.08, 2.0)
	_factor = lerpf(_factor, raw, 1.0 - exp(-delta / FLICKER_SMOOTH))
	var factor := _factor

	var lit := 1.0
	if _is_managed:
		_lit = move_toward(_lit, _lit_target, delta * LIT_EASE)
		lit = _lit
		if light.visible != (_lit > 0.001):
			light.visible = _lit > 0.001
	light.light_energy = base_energy * factor * lit
	# The fire leans and shifts: the light moves with it.
	light.position = _light_home + Vector3(_noise.get_noise_2d(_time * 7.0, 31.0),
		_noise.get_noise_2d(_time * 9.0, 57.0) * 0.6, _noise.get_noise_2d(_time * 7.0, 83.0)) * sway
	# Hotter as it flares, deeper red as it gutters (the chill still wins).
	var heat := clampf((factor - 1.0) * 1.6, -1.0, 1.0) * colour_swing
	var fire := _fire_colour.lerp(HOT if heat > 0.0 else EMBER, absf(heat))
	light.light_color = fire.lerp(ICE_LIGHT, chill)
	# The card animates its own licking; this is only its brightness, in step
	# with the light, held off full black so a gutter dims rather than vanishes.
	var glow := 0.55 + factor * 0.45
	flame.set_instance_shader_parameter("intensity", glow)
	if halo != null:
		halo.set_instance_shader_parameter("intensity", glow)


func _shared_camera() -> Camera3D:
	var frame := Engine.get_process_frames()
	if frame != _camera_frame:
		_camera_frame = frame
		_camera = get_viewport().get_camera_3d()
	return _camera


## Where the cameras are: co-op, both halves' (split_screen.gd); otherwise the
## one drawing. Gathered once a frame for every torch.
static var _points: Array[Vector3] = []
static var _points_frame := -1


func _camera_points() -> Array[Vector3]:
	var frame := Engine.get_process_frames()
	if frame != _points_frame:
		_points_frame = frame
		_points.clear()
		if Coop.active and Coop.split != null and is_instance_valid(Coop.split):
			for c: Camera3D in Coop.split.call("cameras"):
				_points.append(c.global_position)
		else:
			var cam := _shared_camera()
			if cam != null:
				_points.append(cam.global_position)
	return _points
