extends Node3D

## A barred niche in a corridor wall with a skull sitting on a heap of gold and
## white jewels. Aim at it and press E (action "interact") and it plays a short
## scene (`_play`): the player walks over and squares up to it, the door swings
## open, the sword goes through the skull, and the coins and jewels fly out to
## the player one by one on glowing gold and white trails. Blows still land
## during it. Then the player is paid the cage's 5-13 currency.
##
## Built by `module_level.place_windows`, which makes the children this drives:
## "Door" (the bars, hinged on the left jamb), "Loot" (MultiMeshes of coins and
## jewels) and "Skull". Local +Z is out of the wall into the corridor.

signal flight_finished

@export var reach := 2.4
@export var currency_min := 5
@export var currency_max := 13
@export var turn_time := 0.5
@export var door_time := 0.45
## The last piece leaves this long after the first, so they arrive unevenly.
@export var launch_spread := 0.9
@export var flight_min := 0.55
@export var flight_max := 1.0
@export_group("Stare")
## The skull wakes and watches anyone in front of its cage within this reach --
## aimed at or not -- and while it watches it drains their health, lightly.
@export var watch_reach := 3.4
@export var drain_per_second := 2.5
## It never takes the player below this share of their health on its own.
@export_range(0.0, 1.0) var drain_floor := 0.25

const TRAIL_POINTS := 10
## Thin: at 3.5 cm, near the camera, the ribbons read as broad white cones.
const TRAIL_WIDTH := 0.009
const GOLD_TRAIL := Color(1.0, 0.6, 0.12)
const WHITE_TRAIL := Color(0.9, 0.94, 1.0)

var looted := false
var _busy := false
var _near := false
## In front of the cage within `watch_reach`: the skull is looking at them.
var _watching := false
var _player: Node3D = null
var _prompt: Interact.Prompt
var _amount := 0

# The flight: one Dictionary per coin or jewel.
var _pieces: Array[Dictionary] = []
var _flight_clock := 0.0
var _flying := false
var _trail_mesh: ImmediateMesh
var _trail_node: MeshInstance3D

# The skull: it lifts off the heap and watches the player while they are at the
# cage, eyes glowing red, and settles back when they go.
const SKULL_FLOAT := 0.2
const EYE_GLOW := 5.0
var _skull: Node3D = null
var _skull_rest := Transform3D.IDENTITY
var _skull_scale := 1.0
var _hover := 0.0
var _bob := 0.0
var _settle := 0.0
var _settle_now := 0.0
var _loot_gone := false
var _eye_mat: StandardMaterial3D
var _eyes: Array[MeshInstance3D] = []

func _ready() -> void:
	# The builder put exactly this many pieces in the heap.
	_amount = int(get_meta("amount", randi_range(currency_min, currency_max)))
	_prompt = Interact.prompt("E   Open", Vector3(0.0, 0.62, 0.35))
	add_child(_prompt)


func _process(delta: float) -> void:
	_update_skull(delta)
	if not _bones.is_empty():
		_update_bones(delta)
	if _flying:
		_update_flight(delta)
		return
	if looted or _busy:
		return
	# Co-op: whoever is nearest, or in a scene with it (coop.gd `user_for`).
	_player = Coop.user_for(self, _player)
	if _player == null:
		return
	var to := _player.global_position - global_position
	var flat := Vector2(to.x, to.z)
	# In front of the cage and close to it: never from behind the wall, or from
	# the next corridor over. Usable only with the crosshair on the cage; watched
	# (and drained) from a little further, whichever way the player looks.
	var in_front := to.dot(global_basis.z) > 0.3
	_watching = in_front and flat.length() <= watch_reach
	_near = in_front and flat.length() <= reach and Interact.looked_at(self, 3.4, 0.1, [], _player)
	_prompt.visible = _near
	_prompt.player = _player


func _update_skull(delta: float) -> void:
	if _skull == null:
		_skull = get_node_or_null("Skull") as Node3D
		if _skull == null:
			return
		_skull_rest = _skull.transform
		_skull_scale = _skull_rest.basis.get_scale().x
		_make_eyes()
		_warm_up.call_deferred()
	if _impaled:
		# Still on the blade: no bob, no turning, only the shudder, and the eyes
		# blazing until it bursts.
		_shudder = maxf(_shudder - delta * 2.5, 0.0)
		var j := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
			* 0.014 * _shudder
		_skull.transform = Transform3D(_impaled_at.basis, _impaled_at.origin + j)
		if _eye_mat != null:
			_eye_mat.emission_energy_multiplier = EYE_GLOW * (1.0 + _eye_flare)
		_update_wisps(delta, false)
		return
	# Awake while the player stands at the cage, and through the scene until the
	# treasure it sits on has flown.
	var awake := (_watching or _busy) and not looted and not _loot_gone
	_hover = move_toward(_hover, 1.0 if awake else 0.0, delta * (2.0 if awake else 1.4))
	_settle_now = move_toward(_settle_now, _settle, delta * 0.6)
	_bob += delta
	var e := _hover * _hover * (3.0 - 2.0 * _hover)
	var rest_rot := _skull_rest.basis.orthonormalized()
	var pos := _skull_rest.origin + Vector3(0.0, -_settle_now + e * (SKULL_FLOAT + sin(_bob * 2.1) * 0.018), 0.0)
	var rot := rest_rot
	if e > 0.001 and is_instance_valid(_player):
		var camera := Coop.camera(_player)
		var eye: Vector3 = camera.global_position if camera else _player.global_position + Vector3(0, 1.6, 0)
		var to := to_local(eye) - pos
		if to.length_squared() > 0.01:
			# looking_at points -Z at the target, and this skull's face is its +X
			# (measured by rendering it from each side), so a quarter turn more.
			var look := Basis.looking_at(to, Vector3.UP) * Basis(Vector3.UP, PI * 0.5)
			rot = rest_rot.slerp(look.orthonormalized(), e)
	_skull.transform = Transform3D(rot.scaled(Vector3.ONE * _skull_scale), pos)
	# Once it is fully turned on them, its stare drains them, and its eyes pulse
	# with each draw.
	var draining := e > 0.9 and _watching and not _busy and is_instance_valid(_player) \
		and _player.has_method("drain_health")
	var sapping := false
	if draining:
		sapping = _player.drain_health(drain_per_second * delta, float(_player.max_health) * drain_floor) > 0.0
	# Wisps of black smoke run from the skull to the player while health is
	# actually being taken (not once the floor stops it), and any in the air
	# finish their run when it stops.
	_update_wisps(delta, sapping)
	if _eye_mat != null:
		var pulse := 1.0 + (0.5 + 0.5 * sin(_bob * 7.0)) * 0.8 if draining else 1.0
		_eye_mat.emission_energy_multiplier = EYE_GLOW * e * pulse
		for eye_node in _eyes:
			eye_node.visible = e > 0.02


## --- The drain's wisps -----------------------------------------------------------
##
## Thin black smoke: each wisp leaves the skull, snakes across to the player's
## chest on a wavering curve and is gone, a tapering tail behind it. All of a
## cage's wisps are one camera-facing ribbon mesh rebuilt each frame, drawn
## alpha-blended (black cannot be added), soft at its edges.

const WISP_EVERY := 0.11
const WISP_MAX := 10
const WISP_POINTS := 20
const WISP_WIDTH := 0.085
## The dull ember thread down each wisp's middle, so black smoke still reads
## against dark stone.
const WISP_CORE := Color(0.4, 0.04, 0.02)

## {k, life, amp, freq, phase, side, trail}
var _wisps: Array = []
var _wisp_clock := 0.0
var _wisp_mesh: ImmediateMesh
var _wisp_node: MeshInstance3D
var _wisp_core_mat: StandardMaterial3D


func _update_wisps(delta: float, sapping: bool) -> void:
	if not sapping and _wisps.is_empty():
		if _wisp_node != null and _wisp_node.visible:
			_wisp_mesh.clear_surfaces()
			_wisp_node.visible = false
		return
	if _wisp_node == null:
		_make_wisp_node()
	_wisp_node.visible = true
	var mi := _skull as MeshInstance3D
	var from: Vector3 = mi.global_transform * mi.mesh.get_aabb().get_center() if mi != null and mi.mesh != null \
		else global_position
	# The player's chest: just under the view, so they come AT the player and
	# pass out of frame rather than filling it.
	var to: Vector3 = _player.global_position + Vector3(0.0, 1.05, 0.0) if is_instance_valid(_player) \
		else from + global_basis.z * 2.0
	if sapping:
		_wisp_clock -= delta
		if _wisp_clock <= 0.0 and _wisps.size() < WISP_MAX:
			_wisp_clock = WISP_EVERY * randf_range(0.6, 1.4)
			_wisps.append({"k": 0.0, "life": randf_range(0.8, 1.25), "amp": randf_range(0.25, 0.5),
				"freq": randf_range(2.0, 3.5), "phase": randf() * TAU, "side": randf_range(-1.0, 1.0),
				"trail": []})
	var along := to - from
	var up := Vector3.UP
	var across := along.cross(up).normalized()
	if across.length_squared() < 1e-4:
		across = Vector3.RIGHT
	var lift := across.cross(along).normalized()
	var alive: Array = []
	for w in _wisps:
		var trail: Array = w["trail"]
		var k: float = w["k"]
		if k < 1.0:
			k = minf(k + delta / float(w["life"]), 1.0)
			w["k"] = k
			# Eased in from the skull, quickening toward the player; the waver is
			# strongest mid-way and pinned at both ends.
			var e := k * k * (3.0 - 2.0 * k)
			var bend := sin(PI * e)
			var t: float = float(w["phase"]) + e * float(w["freq"]) * TAU
			var pos := from + along * e \
				+ across * sin(t) * float(w["amp"]) * bend \
				+ lift * (cos(t * 0.7) * 0.5 + float(w["side"]) * 0.5) * float(w["amp"]) * bend
			trail.push_front(pos)
			if trail.size() > WISP_POINTS:
				trail.pop_back()
		else:
			# Arrived: the tail runs in after it.
			trail.pop_back()
			if not trail.is_empty():
				trail.pop_back()
		if not trail.is_empty():
			alive.append(w)
	_wisps = alive
	_draw_wisps()


func _make_wisp_node() -> void:
	_wisp_mesh = ImmediateMesh.new()
	_wisp_node = MeshInstance3D.new()
	_wisp_node.name = "Wisps"
	_wisp_node.mesh = _wisp_mesh
	_wisp_node.top_level = true
	_wisp_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wisp_node.custom_aabb = AABB(Vector3(-1.0e4, -1.0e4, -1.0e4), Vector3(2.0e4, 2.0e4, 2.0e4))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Soft across its width: opaque down the middle, nothing at the edges.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 4
	tex.height = 32
	mat.albedo_texture = tex
	# Given per surface in `_draw_wisps` (an override would cover the core too).
	_wisp_node.set_meta("smoke", mat)
	var core := mat.duplicate() as StandardMaterial3D
	core.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_wisp_core_mat = core
	add_child(_wisp_node)
	_wisp_node.global_transform = Transform3D.IDENTITY


func _draw_wisps() -> void:
	_wisp_mesh.clear_surfaces()
	var camera := Coop.camera(_player)
	if camera == null:
		return
	var eye := camera.global_position
	# The black smoke, then its ember thread over it.
	_wisp_surface(eye, _wisp_node.get_meta("smoke"), 1.0, Color(0.015, 0.0, 0.0), 0.85)
	_wisp_surface(eye, _wisp_core_mat, 0.32, WISP_CORE, 0.38)


## One surface of every wisp's ribbon: `scale` of the full width, in `colour`
## at up to `alpha`.
func _wisp_surface(eye: Vector3, material: Material, scale: float, colour: Color, alpha: float) -> void:
	# Gathered first: a surface begun and given no vertices (every segment
	# degenerate) is an error, and leaves the mesh stuck mid-surface.
	var verts: Array = []
	for w in _wisps:
		var trail: Array = w["trail"]
		for i in trail.size() - 1:
			var p0: Vector3 = trail[i]
			var p1: Vector3 = trail[i + 1]
			var seg := p1 - p0
			if seg.length_squared() < 1e-8:
				continue
			var side := seg.cross(eye - p0).normalized()
			# Thickest just behind the head, tapering to a thread at the tail.
			var f0 := 1.0 - float(i) / float(WISP_POINTS)
			var f1 := 1.0 - float(i + 1) / float(WISP_POINTS)
			var w0 := side * WISP_WIDTH * scale * f0
			var w1 := side * WISP_WIDTH * scale * f1
			var c0 := Color(colour, alpha * f0)
			var c1 := Color(colour, alpha * f1)
			verts.append_array([[p0 - w0, c0, Vector2(0, 0)], [p0 + w0, c0, Vector2(0, 1)], [p1 + w1, c1, Vector2(1, 1)],
				[p0 - w0, c0, Vector2(0, 0)], [p1 + w1, c1, Vector2(1, 1)], [p1 - w1, c1, Vector2(1, 0)]])
	if verts.is_empty():
		return
	_wisp_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for v in verts:
		_wisp_mesh.surface_set_color(v[1])
		_wisp_mesh.surface_set_uv(v[2])
		_wisp_mesh.surface_add_vertex(v[0])
	_wisp_mesh.surface_end()


## Two red points of light in the sockets, placed from the skull's own bounds:
## a little either side of the middle, a little above centre, near the front.
func _make_eyes() -> void:
	var mi := _skull as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var box := mi.mesh.get_aabb()
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(1.0, 0.1, 0.05)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = Color(1.0, 0.08, 0.03)
	_eye_mat.emission_energy_multiplier = 0.0
	var ball := SphereMesh.new()
	# 1.4 cm in the world; the skull node is scaled, so undo that here.
	ball.radius = 0.014 / _skull_scale
	ball.height = 0.028 / _skull_scale
	ball.radial_segments = 8
	ball.rings = 4
	ball.material = _eye_mat
	var c := box.get_center()
	for side in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.mesh = ball
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The face is +X, so the sockets sit side by side along Z.
		e.position = Vector3(box.end.x - box.size.x * EYE_DEPTH, c.y + box.size.y * EYE_RISE,
			c.z + side * box.size.z * EYE_SPREAD)
		e.visible = false
		mi.add_child(e)
		_eyes.append(e)


## Where a flying piece ends: this far in front of the eye, and far enough
## below the bottom edge of the view (margin x the frustum's half-height there)
## that it is out of frame before it is removed.
const OFFSCREEN_AHEAD := 0.5
const OFFSCREEN_MARGIN := 1.35

## Where the sockets sit in the skull's bounds (fractions of its size).
const EYE_SPREAD := 0.235
const EYE_RISE := -0.025
const EYE_DEPTH := 0.13


## On the input EVENT rather than polling is_action_just_pressed each frame,
## which can miss a press that lands between frames.
func _unhandled_input(event: InputEvent) -> void:
	if _near and not looted and not _busy and Interact.pressed(event, _player):
		_near = false
		get_viewport().set_input_as_handled()
		_play()


const WOOD_DOOR := preload("res://scripts/wood_door.gd")
## The stab drives the sword's TIP through the skull, and the sword is 2 m from
## guard to tip, so the player is stood off far enough for the tip, not the
## middle of the blade, to reach it: blade length + STAB_REACH (how far ahead of
## the eye the hilt is at full stretch) - STAB_THROUGH, from eye to skull --
## nearer if the corridor's far wall is closer than that.
const STAB_REACH := 0.9
const STAB_THROUGH := 0.14

var _bars: CanvasLayer = null


## The scene (2026-10-07): letterbox bars come in and the view locks onto the
## skull -- and stays on it to the last moment, walking included. The player
## backs off to the striking distance, the view pushes in, the door swings, the
## weapon in hand (sword or spear, `player.stab_at`) is hauled back and driven
## in until its tip comes out through the skull (a hit-stop, the eyes blazing,
## the skull shuddering on the blade), wrenched round -- the skull bursts -- and
## control comes back AT ONCE (2026-10-10); the coins fly to them after, wherever
## they are looking, and are paid on arrival. It happens in the world: blows still land on them
## throughout (`begin_cutscene(true)`), and if they die partway the scene is
## dropped and the cage left to try again.
func _play() -> void:
	_busy = true
	_prompt.visible = false
	_player.begin_cutscene(true)
	_bars = WOOD_DOOR.letterbox(self)
	var focus := _skull_centre()
	_player.scene_look_at(focus, 5.0)
	_player.scene_frame(4.0, 0.0, 2.0)

	var stand := _stab_stand(focus)
	var to := stand - _player.global_position
	if Vector2(to.x, to.z).length() > 0.15:
		_player.scene_walk_to(stand)
		await _player.scene_walk_finished
		if not _still_going():
			return
	# A beat, square to it, as the view settles on the skull and pushes in.
	_player.scene_frame(9.0, 0.0, 2.5)
	await get_tree().create_timer(turn_time * 0.6).timeout
	if not _still_going():
		return

	var door := get_node_or_null("Door") as Node3D
	if door != null:
		var swing := create_tween()
		# Swings outward on its hinge, into the corridor.
		swing.tween_property(door, "rotation:y", -1.8, door_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await swing.finished
		if not _still_going():
			return

	await _stab_skull()
	if not _still_going():
		return
	# The skull has burst: control (and the camera) is the player's again at
	# once, the weapon still coming out of the niche. The treasure flies to them
	# wherever they look, and is paid when it arrives.
	_drop_bars()
	if is_instance_valid(_player) and _player.in_cutscene:
		_player.end_cutscene()
	await get_tree().create_timer(AFTER_STAB, true, false, true).timeout
	_launch_loot()
	if _flying:
		await flight_finished
	_pay()


## False -- and the scene dropped, the cage left to try again -- once the
## player has died partway through it.
func _still_going() -> bool:
	if is_instance_valid(_player) and not _player.get("_dead"):
		return true
	_busy = false
	_impaled = false
	_drop_bars()
	if is_instance_valid(_player) and _player.in_cutscene:
		_player.end_cutscene()
	return false


func _drop_bars() -> void:
	if _bars != null and is_instance_valid(_bars):
		WOOD_DOOR.letterbox_out(_bars)
	_bars = null


func _skull_centre() -> Vector3:
	var mi := _skull as MeshInstance3D
	if mi == null or mi.mesh == null:
		return global_position
	return mi.global_transform * mi.mesh.get_aabb().get_center()


## Where the player stands to strike: straight out from the cage, so far that
## the eye is blade length + STAB_REACH - STAB_THROUGH from the skull, or short
## of the corridor's far wall if that is nearer.
func _stab_stand(focus: Vector3) -> Vector3:
	var out := global_basis.z
	out.y = 0.0
	out = out.normalized()
	var eye_height: float = _player.camera.global_position.y - _player.global_position.y
	var reach: float = _player.scene_reach() + STAB_REACH - STAB_THROUGH
	var rise: float = _player.global_position.y + eye_height - focus.y
	var across := sqrt(maxf(reach * reach - rise * rise, 1.0))
	# Out in the corridor (clear of the wall face in front of the niche), at
	# waist height, toward the far wall.
	var from := focus + out * 1.0
	from.y = _player.global_position.y + 1.0
	var ray := PhysicsRayQueryParameters3D.create(from, from + out * across, 2)
	ray.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		across = minf(across, 1.0 + from.distance_to(hit["position"]) - 0.5)
	var stand := focus + out * across
	stand.y = _player.global_position.y
	return stand


## --- The skull is put down -----------------------------------------------------
##
## Before the treasure flies, the player drives the sword through the skull that
## has been watching them: it bursts into chunks of bone in a puff of bone dust,
## its eyes flaring out, and the pieces tumble down the heap and shrink away.

const CRIER := preload("res://scripts/crier.gd")
const DEBRIS := preload("res://scripts/door_debris.gd")
const BONE_PIECES := 12
const BONE_LIFE := 0.85
const BONE_SHRINK := 0.3
const BONE_GRAVITY := 9.0
## Real seconds from the blade going in to the treasure lifting off.
const AFTER_STAB := 0.45

static var _bone_cache := {}

## [node, velocity, basis, spin axis, spin rate] per piece in flight.
var _bones: Array = []
var _bone_time := 0.0
var _bone_floor := 0.0


## Pinned where it hangs once the stab starts, so the blade meets it; it
## shudders on the blade (`_shudder`) and its eyes blaze (`_eye_flare`) between
## the tip going in and the wrench that bursts it.
var _impaled := false
var _impaled_at := Transform3D.IDENTITY
var _shudder := 0.0
var _eye_flare := 0.0


func _stab_skull() -> void:
	var mi := _skull as MeshInstance3D
	if mi == null or mi.mesh == null or not _player.has_method("stab_at"):
		return
	_impaled = true
	_impaled_at = _skull.transform
	var centre := _skull_centre()
	_player.scene_look_at(centre, 8.0)
	_player.stab_at(centre, STAB_THROUGH)
	# Hauled back: in close, the horizon tipping with the draw.
	_player.scene_frame(14.0, -3.0, 4.0)
	await _player.stab_landed
	# In. The tip is through it: the eyes blaze and it shudders on the blade.
	_shudder = 1.0
	_eye_flare = 3.0
	_player.scene_frame(18.0, 4.0, 14.0)
	await _player.stab_wrenched
	var camera := Coop.camera(_player)
	var from: Vector3 = camera.global_position if camera else _player.global_position
	_shatter_skull((centre - from).normalized())


## The skull's own material, drawn from both sides for the open-backed pieces.
func _bone_material(mi: MeshInstance3D) -> StandardMaterial3D:
	var source := mi.get_active_material(0)
	var mat: StandardMaterial3D
	if source is StandardMaterial3D:
		mat = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.82, 0.78, 0.68)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## The first break stalled its frame (58 ms measured): cutting the skull in
## script and the double-sided material compiling on first draw. So the first
## cage to come up cuts it now and draws one speck of a piece in that material
## in front of the camera, while the level is still loading.
static var _warmed := false

func _warm_up() -> void:
	var mi := _skull as MeshInstance3D
	if _warmed or mi == null or mi.mesh == null:
		return
	var camera := Coop.camera(_player)
	if camera == null:
		return
	_warmed = true
	var pieces := _skull_pieces(mi.mesh)
	if pieces.is_empty():
		return
	var speck := MeshInstance3D.new()
	speck.mesh = pieces[0][0]
	speck.material_override = _bone_material(mi)
	speck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(speck)
	speck.position = Vector3(0.0, 0.0, -0.5)
	speck.scale = Vector3.ONE * 0.002
	get_tree().create_timer(0.5).timeout.connect(speck.queue_free)


func _shatter_skull(direction: Vector3) -> void:
	var mi := _skull as MeshInstance3D
	var frame := mi.global_transform
	var mat := _bone_material(mi)
	var box := mi.mesh.get_aabb()
	_bone_floor = (frame * box.position).y
	var holder: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	for piece in _skull_pieces(mi.mesh):
		var bone := MeshInstance3D.new()
		bone.mesh = piece[0]
		bone.material_override = mat
		bone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(bone)
		var rot := frame.basis
		bone.global_transform = Transform3D(rot, frame * (piece[1] + box.get_center()))
		var outward: Vector3 = (rot * piece[2]).normalized()
		# Mostly on along the blade, into the back of the niche, and out sideways.
		var velocity := outward * randf_range(1.2, 2.6) + direction * randf_range(1.0, 2.4) \
			+ Vector3(0.0, randf_range(0.6, 1.8), 0.0)
		var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		_bones.append([bone, velocity, rot, axis.normalized() if axis.length_squared() > 1e-4 else Vector3.UP,
			randf_range(8.0, 18.0)])
	_bone_time = 0.0
	mi.visible = false
	for eye_node in _eyes:
		eye_node.visible = false
	_eye_mat = null
	# The eyes go out in one last red flash, and a puff of bone dust.
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.15, 0.05)
	flash.light_energy = 6.0
	flash.omni_range = 2.5
	flash.shadow_enabled = false
	holder.add_child(flash)
	flash.global_position = frame * box.get_center()
	var t := flash.create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	t.tween_callback(flash.queue_free)
	if Graphics.effects:
		DEBRIS.dust(holder as Node3D, frame * box.get_center(), -direction, 26, 0.6)


func _update_bones(delta: float) -> void:
	_bone_time += delta
	var size := clampf((BONE_LIFE - _bone_time) / BONE_SHRINK, 0.0, 1.0)
	for b in _bones:
		var bone: MeshInstance3D = b[0]
		var velocity: Vector3 = b[1]
		velocity.y -= BONE_GRAVITY * delta
		var to := bone.global_position + velocity * delta
		# The heap they burst off: bounce once or twice and roll.
		if to.y < _bone_floor:
			to.y = _bone_floor
			velocity = Vector3(velocity.x * 0.5, absf(velocity.y) * 0.3, velocity.z * 0.5)
			b[4] = (b[4] as float) * 0.5
		b[1] = velocity
		var rot: Basis = Basis(b[3], (b[4] as float) * delta) * (b[2] as Basis)
		b[2] = rot
		bone.global_transform = Transform3D(rot.orthonormalized().scaled(rot.get_scale() * maxf(size, 0.001)), to)
	if _bone_time >= BONE_LIFE:
		for b in _bones:
			(b[0] as Node).queue_free()
		_bones.clear()


## The skull cut into BONE_PIECES chunks round its own centre (the crier's
## cutter, which expects a mesh centred on the origin). Cut once per mesh.
## Returns [mesh, centre relative to the skull's centre, direction] per piece.
static func _skull_pieces(source: Mesh) -> Array:
	if _bone_cache.has(source):
		return _bone_cache[source]
	var c := source.get_aabb().get_center()
	var tris: Array = []
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			for i in range(0, verts.size() - 2, 3):
				tris.append([verts[i] - c, verts[i + 1] - c, verts[i + 2] - c])
		else:
			for i in range(0, index.size() - 2, 3):
				tris.append([verts[index[i]] - c, verts[index[i + 1]] - c, verts[index[i + 2]] - c])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seeds: Array[Vector3] = []
	for i in BONE_PIECES:
		var y := 1.0 - (i + 0.5) / BONE_PIECES * 2.0
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var a := i * 2.39996 + rng.randf_range(-0.4, 0.4)
		seeds.append(Vector3(cos(a) * r, y, sin(a) * r).normalized())
	var groups: Array = []
	for i in BONE_PIECES:
		groups.append([])
	for tri in tris:
		var mid: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
		if ((tri[1] - tri[0]) as Vector3).cross(tri[2] - tri[0]).length_squared() < 1e-12:
			continue
		var best := 0
		var best_dot := -2.0
		for i in BONE_PIECES:
			var d := mid.normalized().dot(seeds[i])
			if d > best_dot:
				best_dot = d
				best = i
		groups[best].append(tri)
	var pieces: Array = []
	for i in BONE_PIECES:
		if not groups[i].is_empty():
			pieces.append(CRIER._solid_piece(groups[i], seeds[i]))
	_bone_cache[source] = pieces
	return pieces


## Every coin and jewel becomes its own glowing piece, starting where it lay.
func _launch_loot() -> void:
	var loot := get_node_or_null("Loot") as Node3D
	if loot == null:
		return
	var holder: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	for child in loot.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		var jewel := mm.mesh is SphereMesh
		var glow := _glow_material(mm.mesh.surface_get_material(0), jewel)
		for i in mm.instance_count:
			var at := mmi.global_transform * mm.get_instance_transform(i)
			var piece := MeshInstance3D.new()
			piece.mesh = mm.mesh
			piece.material_override = glow
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(piece)
			piece.global_transform = at
			# Out of the cage first -- forward, up and to one side -- then round
			# to the player, so the paths fan out rather than all running straight.
			var out := global_basis.z * randf_range(0.5, 1.1) \
				+ global_basis.x * randf_range(-0.9, 0.9) + Vector3(0.0, randf_range(0.3, 1.1), 0.0)
			_pieces.append({
				"node": piece, "from": at.origin, "via": at.origin + out, "basis": at.basis,
				"spin": Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0)),
				"delay": randf() * launch_spread, "time": randf_range(flight_min, flight_max),
				"trail": [], "colour": WHITE_TRAIL if jewel else GOLD_TRAIL, "done": false,
				"aim": Vector2(randf_range(-0.12, 0.12), randf_range(-0.08, 0.08)),
			})
	loot.queue_free()

	# The skull sat on the heap; with the heap gone it settles to the floor, and
	# goes still.
	_loot_gone = true
	if _skull != null:
		_settle = float(_skull.get_meta("drop", 0.0))

	_trail_mesh = ImmediateMesh.new()
	_trail_node = MeshInstance3D.new()
	_trail_node.mesh = _trail_mesh
	_trail_node.top_level = true
	_trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Drawn the whole way; the ribbons move every frame, so a stale cull box
	# would clip them.
	_trail_node.custom_aabb = AABB(Vector3(-1.0e4, -1.0e4, -1.0e4), Vector3(2.0e4, 2.0e4, 2.0e4))
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Above 1, so the trails glow rather than merely tint.
	# A little over 1, so they glow; more than that and the gold clips to white.
	trail_mat.albedo_color = Color(1.35, 1.35, 1.35)
	trail_mat.disable_fog = true
	_trail_node.material_override = trail_mat
	add_child(_trail_node)
	_trail_node.global_transform = Transform3D.IDENTITY
	_flight_clock = 0.0
	_flying = not _pieces.is_empty()


func _glow_material(source: Material, jewel: bool) -> Material:
	var m: StandardMaterial3D
	if source is StandardMaterial3D:
		m = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		m = StandardMaterial3D.new()
	m.emission_enabled = true
	m.emission_energy_multiplier = 1.8 if jewel else 1.3
	return m


func _update_flight(delta: float) -> void:
	_flight_clock += delta
	var camera := Coop.camera(_player)
	var eye: Vector3 = camera.global_position if camera else global_position + global_basis.z
	var ahead: Vector3 = -camera.global_basis.z if camera else -global_basis.z
	var down: Vector3 = -camera.global_basis.y if camera else Vector3.DOWN
	var right: Vector3 = camera.global_basis.x if camera else global_basis.x
	# The pieces end BELOW the bottom edge of the view, so the player never
	# sees one vanish: they dive out of frame, into the player's hands.
	var half_fov := deg_to_rad(camera.fov * 0.5) if camera else 0.65
	var remaining := 0
	for p in _pieces:
		var trail: Array = p["trail"]
		if p["done"]:
			# The piece is gone; its tail drains after it rather than blinking out.
			if not trail.is_empty():
				trail.pop_back()
				if not trail.is_empty():
					trail.pop_back()
				remaining += 1
			continue
		remaining += 1
		var t: float = (_flight_clock - float(p["delay"])) / float(p["time"])
		if t <= 0.0:
			continue
		var node: MeshInstance3D = p["node"]
		# Recomputed as the view moves.
		var aim: Vector2 = p["aim"]
		var target := eye + ahead * OFFSCREEN_AHEAD \
			+ down * (OFFSCREEN_AHEAD * tan(half_fov) * OFFSCREEN_MARGIN + absf(aim.y)) + right * aim.x
		var k := clampf(t, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var a: Vector3 = p["from"]
		var b: Vector3 = p["via"]
		var pos := a.lerp(b, e).lerp(b.lerp(target, e), e)
		node.global_transform = Transform3D(
			(p["basis"] as Basis) * Basis.from_euler((p["spin"] as Vector3) * k)
				* Basis.from_scale(Vector3.ONE * lerpf(1.0, 0.6, smoothstep(0.6, 1.0, k))),
			pos)
		trail.push_front(pos)
		if trail.size() > TRAIL_POINTS:
			trail.pop_back()
		if t >= 1.0:
			p["done"] = true
			node.queue_free()
	_draw_trails(eye)
	if remaining == 0:
		_flying = false
		_pieces.clear()
		if is_instance_valid(_trail_node):
			_trail_node.queue_free()
		flight_finished.emit()


## One ribbon per piece, facing the camera, thinning and fading along its tail.
func _draw_trails(eye: Vector3) -> void:
	_trail_mesh.clear_surfaces()
	# Gathered first: a surface begun with no vertices is an error.
	var verts: Array = []
	for p in _pieces:
		var trail: Array = p["trail"]
		if trail.size() < 2:
			continue
		var colour: Color = p["colour"]
		for i in trail.size() - 1:
			var p0: Vector3 = trail[i]
			var p1: Vector3 = trail[i + 1]
			var along := p1 - p0
			if along.length_squared() < 1e-8:
				continue
			var side := along.cross(eye - p0).normalized()
			var f0 := 1.0 - float(i) / float(TRAIL_POINTS)
			var f1 := 1.0 - float(i + 1) / float(TRAIL_POINTS)
			var w0 := side * TRAIL_WIDTH * f0
			var w1 := side * TRAIL_WIDTH * f1
			var c0 := Color(colour.r, colour.g, colour.b, f0 * 0.75)
			var c1 := Color(colour.r, colour.g, colour.b, f1 * 0.75)
			verts.append_array([[p0 - w0, c0], [p0 + w0, c0], [p1 + w1, c1],
				[p0 - w0, c0], [p1 + w1, c1], [p1 - w1, c1]])
	if verts.is_empty():
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		_trail_mesh.surface_set_color(v[1])
		_trail_mesh.surface_add_vertex(v[0])
	_trail_mesh.surface_end()


## A loaded game: this cage was looted. Door open, heap gone, skull broken.
func restore_looted() -> void:
	looted = true
	_loot_gone = true
	_prompt.visible = false
	var door := get_node_or_null("Door") as Node3D
	if door != null:
		door.rotation.y = -1.8
	for part in ["Loot", "Skull"]:
		var node := get_node_or_null(part) as Node3D
		if node != null:
			node.visible = false


func _pay() -> void:
	looted = true
	_busy = false
	if is_instance_valid(_player) and _player.has_method("add_currency"):
		_player.add_currency(_amount)
	# "+N" rising off the open cage.
	var label := Label3D.new()
	label.text = "+%d" % _amount
	label.font_size = 64
	label.pixel_size = 0.004
	label.outline_size = 12
	label.modulate = Color(1.0, 0.8, 0.3)
	label.outline_modulate = Color(0.08, 0.03, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 0.5, 0.4)
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", 1.1, 1.1)
	tween.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
