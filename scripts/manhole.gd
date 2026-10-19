extends Node3D

## A manhole in a corridor floor (2026-10-15): an iron collar round a hole
## through the floor (the kit's notched flagstone, brick_level.gd), shut by
## Tripo's cast-iron cover (`manhole_cover` in brick_kit.glb), over a shaft and
## ladder down to the sewer (sewer.gd).
##
## E on the cover: the player crouches, prises it up and drags it aside. E on
## the open hole: they climb down -- the screen fades to black on the way into
## the shaft, and fades back in on the last stretch of the ladder, in the
## sewer's chamber. At the bottom, E on the ladder climbs back up the same way.
## A cover comes off only from ABOVE (2026-10-15, user): under a covered
## manhole the ladder leads to a shut lid ("Sealed" -- E says so and does
## nothing). Once open, a manhole works from both sides and stays open, saved
## by maze.gd.
##
## The hole is visual only -- the dungeon's floor collision runs whole under it
## -- and an open hole can be walked over (2026-10-16; it used to carry a
## collider, `_blocker`, now never switched on). On a ladder the player's body is driven by the
## scene (player.gd `begin_climb`).

const SEWER := preload("res://scripts/sewer.gd")

## The hole (the notch in the flagstones is cut at this radius).
const HOLE_R := 0.5
## Reach to use it, and where the player stands to.
const REACH := 2.6
const LIFT_STAND := 0.95
const DOWN_STAND := 0.9
## The cover is dragged this far aside.
const COVER_ASIDE := 1.12
## The climb: the stretch climbed in the dark, and the stretch that fades back
## in at the other end, both in metres of ladder.
const DARK_STRETCH := 2.3
const LIGHT_STRETCH := 2.4
const RUNG := 0.3
## Seconds per metre of ladder.
const CLIMB_PACE := 0.62
const FADE_OUT := 1.1
const FADE_IN := 1.3
## The rails stand this far from the hole's centre (sewer.gd LADDER_OUT).
const LADDER_OUT := 0.36

enum State { COVERED, OPEN }

var state := State.COVERED
## The sewer's record of this shaft: hole, along, foot, ladder...
var shaft: Dictionary = {}
var along := Vector3.FORWARD
var index := 0

var _cover: Node3D
var _cover_home := Transform3D.IDENTITY
var _cover_aside := Transform3D.IDENTITY
var _blocker: CollisionShape3D
var _frame: MeshInstance3D
var _prompt: Interact.Prompt
var _ladder_prompt: Interact.Prompt
var _player: Node3D
var _busy := false
var _near_top := false
var _near_bottom := false


static func build(parent: Node3D, sewer_shaft: Dictionary, cell_centre: Vector3, i: int) -> Node3D:
	var m := Node3D.new()
	m.set_script(load("res://scripts/manhole.gd"))
	m.name = "Manhole%d" % i
	m.set("shaft", sewer_shaft)
	m.set("index", i)
	m.set("along", sewer_shaft["along"])
	m.position = sewer_shaft["hole"]
	parent.add_child(m)
	m.call("_dress", cell_centre)
	return m


func _dress(cell_centre: Vector3) -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.13, 0.095, 0.075)
	iron.metallic = 0.45
	iron.roughness = 0.62
	iron.normal_enabled = true
	iron.normal_texture = load("res://textures/stone_plain_normal.png")
	iron.normal_scale = 0.6
	iron.uv1_triplanar = true
	iron.uv1_scale = Vector3.ONE * 1.6
	# The collar the cover sits in.
	var ring := TorusMesh.new()
	ring.inner_radius = HOLE_R
	ring.outer_radius = HOLE_R + 0.16
	ring.rings = 40
	ring.ring_segments = 10
	_frame = MeshInstance3D.new()
	_frame.name = "Frame"
	_frame.mesh = ring
	_frame.material_override = iron
	_frame.scale = Vector3(1.0, 0.35, 1.0)
	_frame.position.y = 0.0
	add_child(_frame)
	# The cover.
	_cover = Node3D.new()
	_cover.name = "Cover"
	add_child(_cover)
	var cover_mesh := MeshInstance3D.new()
	var kit: Mesh = load("res://scripts/brick_level.gd").standalone("manhole_cover")
	if kit != null:
		cover_mesh.mesh = kit
	else:
		var c := CylinderMesh.new()
		c.top_radius = 0.54
		c.bottom_radius = 0.54
		c.height = 0.08
		cover_mesh.mesh = c
		cover_mesh.position.y = 0.04
	cover_mesh.material_override = _cover_material()
	_cover.add_child(cover_mesh)
	_cover_home = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.018, 0.0))
	_cover.transform = _cover_home
	# The bed under this cell's flagstones, with the hole left in it.
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_color = Color(0.085, 0.062, 0.044)
	bed_mat.roughness = 1.0
	bed_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var c_local := cell_centre - position
	var gap := HOLE_R + 0.06
	var x0 := c_local.x - 3.0
	var x1 := c_local.x + 3.0
	var z0 := c_local.z - 3.0
	var z1 := c_local.z + 3.0
	for r in [[x0, -gap, z0, z1], [gap, x1, z0, z1], [-gap, gap, z0, -gap], [-gap, gap, gap, z1]]:
		var w: float = r[1] - r[0]
		var d: float = r[3] - r[2]
		if w <= 0.01 or d <= 0.01:
			continue
		var box := BoxMesh.new()
		box.size = Vector3(w, 0.2, d)
		box.material = bed_mat
		var mi := MeshInstance3D.new()
		mi.name = "Bed"
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((r[0] + r[1]) * 0.5, -0.16, (r[2] + r[3]) * 0.5)
		add_child(mi)
	# Kept, but never switched on (2026-10-16, at the user's request): an open
	# manhole can be walked over -- the floor's collision runs whole under the
	# hole. It used to stop everyone 0.95 m from its centre.
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	_blocker = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = HOLE_R + 0.04
	cyl.height = 2.0
	_blocker.shape = cyl
	_blocker.position.y = 1.0
	_blocker.disabled = true
	body.add_child(_blocker)
	_prompt = Interact.prompt("E   Lift", Vector3(0.0, 0.2, 0.0))
	add_child(_prompt)
	_ladder_prompt = Interact.prompt("E   Climb up", Vector3.ZERO)
	add_child(_ladder_prompt)
	_ladder_prompt.position = (shaft["foot"] as Vector3) - position + Vector3(0.0, 1.4, 0.0)


func _cover_material() -> StandardMaterial3D:
	# Dark old iron, rusted brown at the edges -- the dungeon's iron (door
	# straps, cage bars), not bright metal.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.22, 0.16)
	m.metallic = 0.35
	m.roughness = 0.58
	m.normal_enabled = true
	m.normal_texture = load("res://textures/stone_plain_normal.png")
	m.normal_scale = 0.45
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0
	return m


func is_open() -> bool:
	return state == State.OPEN


## Restored from a save: open, cover already aside, no scene.
func set_open_now() -> void:
	state = State.OPEN
	_cover_aside = _aside_for(global_position - along)
	_cover.transform = _cover_aside
	# Open, it stays walkable (2026-10-16): the floor runs whole under it.


# --- Running ----------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Co-op: whoever is nearest, or in a scene with it (coop.gd `user_for`).
	_player = Coop.user_for(self, _player)
	if _player == null:
		return
	if _busy or _player.get("in_cutscene") or _player.get("_dead"):
		_near_top = false
		_near_bottom = false
		_prompt.visible = false
		_ladder_prompt.visible = false
		return
	var at := _player.global_position
	var flat := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	_near_top = absf(at.y - global_position.y) < 1.2 and flat <= REACH \
		and Interact.looked_at(self, REACH, 0.12, [_frame], _player)
	_prompt.text = "E   Lift" if state == State.COVERED else "E   Climb down"
	_prompt.visible = _near_top
	_prompt.player = _player
	var foot: Vector3 = shaft["foot"]
	var ladder: Node3D = shaft.get("ladder")
	_near_bottom = ladder != null and absf(at.y - foot.y) < 1.2 \
		and Vector2(at.x - foot.x, at.z - foot.z).length() <= 2.2 \
		and Interact.looked_at(ladder, 2.6, 0.2, [], _player)
	_ladder_prompt.text = "E   Climb up" if state == State.OPEN else "E   Sealed"
	_ladder_prompt.visible = _near_bottom
	_ladder_prompt.player = _player


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _player == null or not Interact.pressed(event, _player):
		return
	if _near_top:
		get_viewport().set_input_as_handled()
		if state == State.COVERED:
			_lift()
		else:
			_climb_down()
	elif _near_bottom:
		get_viewport().set_input_as_handled()
		if state == State.OPEN:
			_climb_up()
		else:
			_toast("The cover is shut from above")


func _toast(text: String) -> void:
	var hud := _hud()
	if hud != null and hud.has_method("_show_toast"):
		hud.call("_show_toast", text)


func _hud() -> Node:
	return Coop.hud(_player)


func _ok() -> bool:
	return is_instance_valid(_player) and not _player.get("_dead")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# --- Lifting the cover ---------------------------------------------------------------

## Where the cover lies once dragged aside: to the right of someone standing
## at `stand` looking at the hole, flat on the floor, turned a little.
func _aside_for(stand: Vector3) -> Transform3D:
	var to := global_position - stand
	to.y = 0.0
	if to.length_squared() < 0.0001:
		to = along
	var right := to.normalized().cross(Vector3.UP)
	return Transform3D(Basis(Vector3.UP, 0.7), right * COVER_ASIDE + Vector3(0.0, 0.012, 0.0))


func _lift() -> void:
	_busy = true
	var from := _player.global_position
	var dir := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else -along
	var stand := global_position + dir * LIFT_STAND
	stand.y = from.y
	_player.begin_cutscene(true)
	_player.set("hands_busy", true)
	var bars: CanvasLayer = load("res://scripts/wood_door.gd").letterbox(self)
	_player.scene_look_at(global_position, 7.0)
	if Vector2(stand.x - from.x, stand.z - from.z).length() > 0.3:
		_player.scene_walk_to(stand, 2.0)
		await _player.scene_walk_finished
	if not _ok():
		_abort(bars)
		return
	# Crouch to it.
	_player.scene_lean(Vector3(0.0, -0.45, -0.12), 5.0)
	_player.scene_frame(4.0, 0.0, 3.0)
	await _wait(0.45)
	# Prised up at the near edge: it sticks, then gives.
	var tilt_axis := dir.cross(Vector3.UP).normalized()
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_method(func(k: float): _cover.transform = _tilted(tilt_axis, k * 0.08, k * 0.025),
		0.0, 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_method(func(k: float): _cover.transform = _tilted(tilt_axis, k * 0.08, k * 0.025),
		1.0, 0.3, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_method(func(k: float): _cover.transform = _tilted(tilt_axis, k * 0.08, k * 0.025),
		0.3, 2.6, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	if not _ok():
		_abort(bars)
		return
	_player.set("_shake", maxf(float(_player.get("_shake")), 0.16))
	# Dragged aside, grinding on the flags.
	_cover_aside = _aside_for(stand)
	var lifted := _cover.transform
	var d := create_tween().set_ignore_time_scale(true)
	d.tween_method(func(k: float): _cover.transform = lifted.interpolate_with(_cover_aside, k),
		0.0, 1.0, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_player.scene_look_at(global_position + _cover_aside.origin * 0.6, 4.0)
	await d.finished
	_player.set("_shake", maxf(float(_player.get("_shake")), 0.1))
	state = State.OPEN
	# Open, it stays walkable (2026-10-16): the floor runs whole under it.
	# A look down the hole, then back to the player.
	_player.scene_look_at(global_position + Vector3(0.0, -2.0, 0.0), 3.0)
	await _wait(0.5)
	load("res://scripts/wood_door.gd").letterbox_out(bars)
	_player.end_cutscene()
	_player.set("hands_busy", false)
	_busy = false


## The cover lifted `rise` at the edge furthest from `axis` and tilted `angle`
## about the near edge (scaled by k each step).
func _tilted(axis: Vector3, angle: float, rise: float) -> Transform3D:
	var b := Basis(axis, angle * 4.0)
	return Transform3D(b, _cover_home.origin + Vector3(0.0, rise * 4.0, 0.0))


func _abort(bars: CanvasLayer = null) -> void:
	if bars != null and is_instance_valid(bars):
		load("res://scripts/wood_door.gd").letterbox_out(bars)
	if is_instance_valid(_player):
		if _player.get("climbing"):
			_player.call("end_climb")
		elif _player.get("in_cutscene"):
			_player.end_cutscene()
		_player.set("hands_busy", false)
	if state == State.COVERED:
		_cover.transform = _cover_home
	_busy = false


# --- Climbing -------------------------------------------------------------------------

func _ladder_yaw() -> float:
	return atan2(-along.x, -along.z)


## Moves the body from `from` to `to` (body positions) rung by rung over the
## distance at CLIMB_PACE, the view easing from pitch `p0` to `p1`. Returns
## false if the player died on the way.
func _climb(from: Vector3, to: Vector3, p0: float, p1: float) -> bool:
	var dist := from.distance_to(to)
	var total := maxf(dist * CLIMB_PACE, 0.2)
	var rungs := maxf(dist / RUNG, 1.0)
	var t := 0.0
	var side := 1.0
	var last_rung := -1
	while t < total:
		await get_tree().process_frame
		if not _ok():
			return false
		t += minf(get_process_delta_time() / maxf(Engine.time_scale, 0.001), 0.05)
		var p := clampf(t / total, 0.0, 1.0)
		# One reach per rung: each one a quick pull then a pause.
		var q := p * rungs
		var r := floorf(q)
		var f := r + smoothstep(0.0, 1.0, clampf((q - r) * 1.35, 0.0, 1.0))
		var k := clampf(f / rungs, 0.0, 1.0)
		_player.global_position = from.lerp(to, k)
		if int(r) != last_rung:
			last_rung = int(r)
			side = -side
			_player.scene_lean(Vector3(0.035 * side, 0.0, 0.0), 6.0)
		_player.call("climb_face", _ladder_yaw(), lerpf(p0, p1, p))
	_player.global_position = to
	return true


## Fades the screen to `alpha` over `time` (real time) and returns at once.
func _fade(alpha: float, time: float) -> void:
	var hud := _hud()
	if hud != null and hud.has_method("fade_black"):
		hud.fade_black(alpha, time)


func _climb_down() -> void:
	_busy = true
	var top := global_position
	var stand := top - along * DOWN_STAND
	stand.y = _player.global_position.y
	_player.begin_cutscene(true)
	_player.set("hands_busy", true)
	_player.scene_look_at(top + along * LADDER_OUT, 6.0)
	if Vector2(stand.x - _player.global_position.x, stand.z - _player.global_position.z).length() > 0.25:
		_player.scene_walk_to(stand, 2.5)
		await _player.scene_walk_finished
	if not _ok():
		_abort()
		return
	_player.scene_look_at(null)
	_player.call("begin_climb")
	# Onto the ladder: forward over the hole and down into it.
	var on := Vector3(top.x, top.y - 0.6, top.z)
	if not await _climb(_player.global_position, on, -0.35, -0.6):
		_abort()
		return
	# Down the shaft into the dark.
	_fade(1.0, FADE_OUT)
	var dark_end := on - Vector3(0.0, DARK_STRETCH, 0.0)
	if not await _climb(on, dark_end, -0.6, -0.45):
		_abort()
		return
	var hud := _hud()
	var waited := 0.0
	while hud != null and hud.black_amount() < 0.99 and waited < 1.5:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _ok():
		_abort()
		return
	# Black: the rest of the shaft is skipped. Out of the dark on the last
	# stretch, into the chamber.
	var foot: Vector3 = shaft["foot"]
	var low := foot + Vector3(0.0, LIGHT_STRETCH, 0.0)
	_player.global_position = low
	await get_tree().process_frame
	_fade(0.0, FADE_IN)
	if not await _climb(low, foot, -0.3, 0.05):
		_abort()
		return
	# Off the ladder, back into the chamber.
	if not await _climb(foot, foot - along * 0.6 + Vector3(0.0, 0.02, 0.0), 0.05, 0.0):
		_abort()
		return
	_player.call("end_climb")
	_busy = false


func _climb_up() -> void:
	# Only through an open manhole: the cover cannot be shifted from below.
	if state != State.OPEN:
		return
	_busy = true
	var foot: Vector3 = shaft["foot"]
	var stand := foot - along * 0.6
	stand.y = _player.global_position.y
	_player.begin_cutscene(true)
	_player.set("hands_busy", true)
	_player.scene_look_at(foot + along * LADDER_OUT + Vector3(0.0, 1.5, 0.0), 6.0)
	if Vector2(stand.x - _player.global_position.x, stand.z - _player.global_position.z).length() > 0.25:
		_player.scene_walk_to(stand, 2.5)
		await _player.scene_walk_finished
	if not _ok():
		_abort()
		return
	_player.scene_look_at(null)
	_player.call("begin_climb")
	if not await _climb(_player.global_position, foot, 0.1, 0.35):
		_abort()
		return
	_fade(1.0, FADE_OUT)
	var high := foot + Vector3(0.0, LIGHT_STRETCH, 0.0)
	if not await _climb(foot, high, 0.35, 0.55):
		_abort()
		return
	var hud := _hud()
	var waited := 0.0
	while hud != null and hud.black_amount() < 0.99 and waited < 1.5:
		await get_tree().process_frame
		waited += get_process_delta_time()
	if not _ok():
		_abort()
		return
	var top := global_position
	var under := Vector3(top.x, top.y - 0.6 - DARK_STRETCH, top.z)
	_player.global_position = under
	await get_tree().process_frame
	_fade(0.0, FADE_IN)
	var push_at := Vector3(top.x, top.y - 1.4, top.z)
	if not await _climb(under, push_at, 0.55, 0.7):
		_abort()
		return
	var out := Vector3(top.x, top.y - 0.6, top.z)
	if not await _climb(push_at, out, 0.7, 0.2):
		_abort()
		return
	# Up and over the rim, onto the flags beyond the ladder.
	var off := top + along * (HOLE_R + 0.58) + Vector3(0.0, 0.05, 0.0)
	if not await _climb(out, off, 0.2, -0.1):
		_abort()
		return
	_player.call("end_climb")
	_busy = false
