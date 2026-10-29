extends Node

## Taken to the boss (note 128). Once the surgeon is dead and his claw kept
## (surgery_control.gd `_take_his_claw`), a sack comes down over the player's
## head from behind, they are lifted and carried, and they are dropped on their
## knees in the boss's throne hall. One of two scouts standing over them pulls
## the sack off with its spear -- hooks the crown on the barbs and flicks it
## away over its shoulder -- and there is the boss on his dais. Then the long
## cutscene (a placeholder for now: `_long_scene`), the scouts walk out, and
## the fight begins. It replaces walking to the great door and setting the
## shards in it.
##
## Co-op: every player who is up is bagged and carried; they kneel side by
## side, a scout before each. Solo: the second scout stands guard behind.
##
## Made by maze.gd `take_to_the_boss`; it frees itself when done and tells the
## maze (`_on_taken_to_boss`). Nothing in it is saved: a save part way through
## plays it again on load (maze.gd `_resume_abduction`).

const SCOUT := preload("res://scripts/scout.gd")
const WOOD_DOOR := preload("res://scripts/wood_door.gd")
const BAG_SHADER := preload("res://shaders/burlap_bag.gdshader")

## Through the bag: carried this long (s); dropped, this long before the sack
## is pulled off.
const CARRY_TIME := 6.0
const KNELT_TIME := 1.6
## Where they kneel: this share of the way from the arch to the boss's spot,
## and this far apart in co-op.
const KNEEL_SHARE := 0.42
const KNEEL_APART := 1.9
## The eye knelt (player.gd `scene_lean`, as the claw scene's kneel).
const KNEEL_LEAN := Vector3(0.0, -0.62, -0.15)
## A scout stands this far before its captive (it then walks in or out until
## its point is at the sack: `_reach`).
const SCOUT_OFF := 2.0
## The move (scout_body.gd MOVES "unhood"): the point in the sack's crown at
## HOOK_AT, the sack carried on the barbs until LET_GO, done at UNHOOD_END.
const HOOK_AT := 0.95
const LET_GO := 1.32
const UNHOOD_END := 2.3
## The sack let fly (m/s): back over the scout's shoulder, and up.
const SACK_BACK := 2.4
const SACK_UP := 3.2
## Co-op: the second scout pulls its sack this much later.
const SECOND_DELAY := 0.4
## The stand-in for the long cutscene, until it is made.
const LONG_SCENE_STANDIN := 1.5
## The scouts walk out at this pace; one is let go once behind every player's
## view (or out through the arch), all of them after SCOUT_EXIT_MAX.
const SCOUT_EXIT_SPEED := 2.2
const SCOUT_EXIT_MAX := 7.0

## The long cutscene's place in the sequence (see `_long_scene`).
signal long_scene_reached
signal finished

var maze: Node3D
var boss: Node3D
## One per captive: {p, layer, rect, mat, scout, sack, t, playing, hooked, thrown, h}.
var _entries: Array[Dictionary] = []
## Solo: the scout standing guard behind them.
var _guard: Node3D = null
var _bars: CanvasLayer = null
var _clock := 0.0
## How hard the view bounces with the carrier's stride (0 knelt).
var _carry_bob := 0.0
## Where everything stands in the hall (world).
var _into := Vector3.FORWARD
var _gate_at := Vector3.ZERO
var _boss_at := Vector3.ZERO

static var _sack_mat: StandardMaterial3D = null


## Starts it on `maze_` after `delay` s, once everyone up is free.
static func begin(maze_: Node3D, boss_: Node3D, delay: float) -> Node:
	var a := Node.new()
	a.set_script(load("res://scripts/boss_abduction.gd"))
	a.name = "BossAbduction"
	a.set("maze", maze_)
	a.set("boss", boss_)
	maze_.add_child(a)
	a.call("_run", delay)
	return a


func _run(delay: float) -> void:
	await _wait(delay)
	var players := await _free_players()
	if not is_inside_tree():
		return
	print("[abduction] %d bagged" % players.size())
	if is_instance_valid(boss):
		# Held on his dais until the fight: blind, deaf and unhurt (enemy.gd).
		boss.set("caged", true)

	# 1. From behind, the sack comes down over their heads.
	for p in players:
		p.call("begin_cutscene")
		p.set("hands_busy", true)
		_entries.append(_bag(p))
	await _wait(0.35)
	for e in _entries:
		var rect: ColorRect = e["rect"]
		var tw := rect.create_tween().set_ignore_time_scale(true)
		tw.tween_property(rect, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(0.22)
	_bars = WOOD_DOOR.letterbox(self)
	for e in _entries:
		var p: Node3D = e["p"]
		p.set("_shake", 0.45)
		# Yanked back by it.
		p.call("scene_lean", Vector3(0.0, -0.08, 0.18), 8.0)
		p.call("scene_frame", -4.0, 8.0, 6.0)
	# A struggle.
	for k in 4:
		for e in _entries:
			var p: Node3D = e["p"]
			p.call("scene_lean", Vector3(0.09 * (1.0 if k % 2 == 0 else -1.0), -0.06, 0.16), 9.0)
			p.set("_shake", maxf(float(p.get("_shake")), 0.12))
		await _wait(0.22)

	# 2. Lifted onto a shoulder and carried.
	for e in _entries:
		var p: Node3D = e["p"]
		p.call("scene_lean", Vector3(0.22, 0.32, 0.2), 3.0)
		p.call("scene_frame", 0.0, 24.0, 2.5)
		p.set("_shake", 0.3)
	_carry_bob = 1.0
	await _wait(0.6)
	# Nobody sees out: they are in the hall from here on.
	_set_the_hall()
	var left := CARRY_TIME - 0.6
	var step := 0
	while left > 0.0:
		for e in _entries:
			var p: Node3D = e["p"]
			var up := 0.06 if step % 2 == 0 else -0.04
			p.call("scene_lean", Vector3(0.22, 0.32 + up, 0.2), 10.0)
			p.set("_shake", maxf(float(p.get("_shake")), 0.05))
		# Now and then a torch goes by outside.
		if step % 4 == 1:
			for e in _entries:
				var mat: ShaderMaterial = e["mat"]
				var tw := create_tween().set_ignore_time_scale(true)
				tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"glow", v),
					0.0, randf_range(0.35, 0.6), 0.5)
				tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"glow", v),
					0.5, 0.08, 0.9)
		step += 1
		await _wait(0.36)
		left -= 0.36

	# 3. Dropped on their knees, before the throne.
	_carry_bob = 0.0
	for e in _entries:
		var p: Node3D = e["p"]
		p.call("scene_frame", 0.0, 0.0, 6.0)
		p.call("scene_lean", KNEEL_LEAN, 7.0)
		p.set("_shake", 0.55)
		var scout: Node3D = e["scout"]
		p.call("scene_look_at", scout.global_position + Vector3(0.0, 1.5, 0.0), 4.0)
		var mat: ShaderMaterial = e["mat"]
		mat.set_shader_parameter(&"glow", 0.0)
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_method(func(v: float) -> void: mat.set_shader_parameter(&"see", v), 0.0, 0.6, 0.8)
	await _wait(KNELT_TIME)

	# 4. The sack hooked off by the scout before each of them.
	for i in _entries.size():
		_entries[i]["playing"] = true
		if i < _entries.size() - 1:
			await _wait(SECOND_DELAY)
	while _any_playing():
		await get_tree().process_frame
	for e in _entries:
		var scout: Node3D = e["scout"]
		scout.set("scripted_look", (e["p"] as Node3D).get("camera").global_position)

	# 5. The long cutscene goes here.
	await _long_scene()
	if not is_inside_tree():
		return

	# 6. The scouts go; the view turns to him.
	var head := _boss_at + Vector3(0.0, 2.2, 0.0)
	for e in _entries:
		var p: Node3D = e["p"]
		p.call("scene_look_at", head, 2.0)
		p.call("scene_lean", Vector3.ZERO, 2.5)
		p.call("scene_frame", 6.0, 0.0, 1.5)
	await _scouts_leave()

	# 7. The fight.
	if is_instance_valid(boss):
		boss.set("caged", false)
		boss.call("alert")
	_end()


## The long cutscene -- PLACEHOLDER (note 128; the user will ask for it
## separately). When it starts, everyone is still in the scene, letterboxed,
## kneeling in the hall with the sack off, each looking up at their scout
## (`_entries[i]["scout"]`; solo, `_guard` stands behind them), the boss held
## on his dais (`boss`, `caged`). Play it here and return when it is over:
## the scouts then walk out and the fight starts. Until then, a beat.
func _long_scene() -> void:
	long_scene_reached.emit()
	print("[abduction] long cutscene hook (placeholder)")
	await _wait(LONG_SCENE_STANDIN)


# --- Setting it up ------------------------------------------------------------------------

## Everyone up and free (no scene, menu, hiding place, climb, rat's eyes) -- at
## least one; the dead are left to rise at their anchor.
func _free_players() -> Array[Node3D]:
	while true:
		var live: Array[Node3D] = []
		var busy := false
		for q in Coop.all():
			var n := q as Node3D
			if n == null or n.get("_dead") == true:
				continue
			if n.get("in_cutscene") == true or n.get("ui_open") == true or n.get("wheel_open") == true \
					or n.get("remote_view") == true or n.get("climbing") == true \
					or (n.has_method("is_hidden") and bool(n.call("is_hidden"))):
				busy = true
			live.append(n)
		if not busy and not live.is_empty():
			return live
		await get_tree().process_frame
	return []


## The sack over `p`'s view: a burlap shader on their half of the screen, up
## out of view until it comes down.
func _bag(p: Node3D) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.name = "Sack"
	# Over the HUD, under the letterbox (40).
	layer.layer = 38
	Coop.ui_root(p).add_child(layer)
	var size := layer.get_viewport().get_visible_rect().size
	var mat := ShaderMaterial.new()
	mat.shader = BAG_SHADER
	mat.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	# A little larger than the view, so a sway or the pull never shows an edge.
	rect.size = size * 1.2
	rect.pivot_offset = rect.size * 0.5
	rect.position = Vector2(-size.x * 0.1, -size.y * 1.3)
	layer.add_child(rect)
	return {"p": p, "layer": layer, "rect": rect, "mat": mat, "scout": null, "sack": null,
		"t": 0.0, "playing": false, "hooked": false, "thrown": false,
		"h": size.y}


## While they are carried (no one can see): the great door opened, each of
## them put on their knees in the hall facing the boss, a scout before each.
func _set_the_hall() -> void:
	var hall: Dictionary = maze.get("_boss_hall")
	var door = maze.call("shard_door")
	if door != null and is_instance_valid(door):
		door.call("open_now")
	var gate: Transform3D = maze.global_transform * (hall["gate"] as Transform3D)
	_gate_at = gate.origin
	_boss_at = maze.to_global(hall["boss_spot"])
	_into = _boss_at - _gate_at
	_into.y = 0.0
	var span := _into.length()
	_into = _into / maxf(span, 0.01)
	var floor_y := maze.to_global(Vector3(0.0, float(hall["floor_y"]), 0.0)).y
	var centre := _gate_at + _into * span * KNEEL_SHARE
	centre.y = floor_y + 0.05
	var right := _into.cross(Vector3.UP).normalized()
	var yaw := atan2(-_into.x, -_into.z)
	var n := _entries.size()
	for i in n:
		var e: Dictionary = _entries[i]
		var p: Node3D = e["p"]
		var at := centre + right * (float(i) - float(n - 1) * 0.5) * KNEEL_APART
		p.global_position = at
		p.set("velocity", Vector3.ZERO)
		p.rotation.y = yaw
		p.call("scene_look_at", at + _into * 3.0 + Vector3(0.0, 1.0, 0.0), 6.0)
		var scout := _scout(at + _into * SCOUT_OFF, at)
		scout.set("scripted_face", at)
		scout.set("scripted_look", at + Vector3(0.0, 1.0, 0.0))
		e["scout"] = scout
	if n == 1:
		var at: Vector3 = (_entries[0]["p"] as Node3D).global_position
		_guard = _scout(at - _into * 1.6 - right * 0.9, at + _into * 10.0)
		_guard.set("scripted_face", at + _into * 10.0)
		_guard.set("scripted_look", at + Vector3(0.0, 1.0, 0.0))


## A scripted scout (scout.gd `scripted`) standing at `at`, facing `toward`.
func _scout(at: Vector3, toward: Vector3) -> Node3D:
	var s: Node3D = (maze.get("enemy_scene") as PackedScene).instantiate()
	s.set_script(SCOUT)
	s.set("scripted", true)
	maze.add_child(s)
	s.global_position = at + Vector3(0.0, 0.3, 0.0)
	var to := toward - at
	s.rotation.y = atan2(-to.x, -to.z)
	return s


# --- Every frame: the weave's sway, the scouts' pull --------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	for e in _entries:
		var mat: ShaderMaterial = e["mat"]
		if mat != null:
			var bob := Vector2(sin(_clock * 1.7) * 0.006, cos(_clock * 1.3) * 0.005)
			bob += Vector2(0.0, absf(sin(_clock * 8.7)) * 0.02) * _carry_bob
			mat.set_shader_parameter(&"drift", bob)
		if e["playing"]:
			_unhood(e, delta)


func _any_playing() -> bool:
	for e in _entries:
		if e["playing"]:
			return true
	return false


## One tick of a scout pulling a sack off: the point brought to the crown of
## it, hooked, flicked up and back, the sack let fly.
func _unhood(e: Dictionary, delta: float) -> void:
	var scout: Node3D = e["scout"]
	var p: Node3D = e["p"]
	if not is_instance_valid(scout) or not is_instance_valid(p):
		e["playing"] = false
		return
	var body: Node3D = scout.get("_body")
	e["t"] = float(e["t"]) + delta
	var t: float = e["t"]
	scout.set("scripted_move", &"unhood")
	scout.set("scripted_move_t", t)
	var crown: Vector3 = (p.get("camera") as Node3D).global_position + Vector3(0.0, 0.1, 0.0)
	var fwd := -scout.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var grip_y := scout.global_position.y + 1.2
	var flat := Vector2(crown.x - scout.global_position.x, crown.z - scout.global_position.z).length()
	scout.set("scripted_pitch", clampf(atan2(crown.y - grip_y, maxf(flat - 0.2, 0.5)), -0.6, 0.6))
	var tip: Vector3 = body.call("spear_tip") if body != null else crown
	# In or out until the point is at the sack.
	if t > 0.25 and t < HOOK_AT:
		var err := (crown - tip).dot(fwd)
		scout.set("scripted_walk", fwd * clampf(err * 3.5, -1.2, 1.2))
	else:
		scout.set("scripted_walk", Vector3.ZERO)
	if not e["hooked"] and t >= HOOK_AT:
		e["hooked"] = true
		e["sack"] = _sack(tip)
		_pull_off(e)
		p.set("_shake", maxf(float(p.get("_shake")), 0.3))
		p.call("scene_look_at", scout.global_position + Vector3(0.0, 1.55, 0.0), 3.0)
		p.call("scene_frame", 3.0, 0.0, 3.0)
	var sack = e["sack"]
	if sack != null and is_instance_valid(sack) and not e["thrown"]:
		var b := sack as RigidBody3D
		if t < LET_GO:
			b.global_position = tip + Vector3(0.0, -0.12, 0.0)
		else:
			e["thrown"] = true
			b.freeze = false
			# Flung up and back over its shoulder. Not the tip's own speed: one
			# long frame made that 25 m/s and sent the sack out of the hall.
			var side := fwd.cross(Vector3.UP).normalized()
			b.linear_velocity = -fwd * SACK_BACK + Vector3.UP * SACK_UP + side * randf_range(-0.6, 0.6)
			b.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	if t >= UNHOOD_END:
		e["playing"] = false
		scout.set("scripted_move", &"")
		scout.set("scripted_pitch", 0.0)
		scout.set("scripted_walk", Vector3.ZERO)


## The sack goes up off their view -- jerked up and a little aside -- and the
## world is there.
func _pull_off(e: Dictionary) -> void:
	var rect: ColorRect = e["rect"]
	var layer: CanvasLayer = e["layer"]
	var h: float = e["h"]
	var tw := rect.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.tween_property(rect, "position:y", -h * 1.35, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(rect, "position:x", rect.position.x + h * 0.12, 0.3)
	tw.tween_property(rect, "rotation", -0.14, 0.3)
	tw.chain().tween_callback(layer.queue_free)
	e["mat"] = null


## The sack in the world, on the spear's barbs: a body that is carried until
## it is let fly, then falls and lies.
func _sack(at: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = "Sack"
	b.collision_layer = 0
	b.collision_mask = 1
	b.mass = 0.6
	b.freeze = true
	b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.15
	cap.height = 0.42
	cs.shape = cap
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.17
	mesh.height = 0.46
	mesh.radial_segments = 14
	mesh.rings = 6
	mi.mesh = mesh
	mi.material_override = _sack_material()
	# Gathered at its mouth: narrower at the bottom, a cord round it.
	mi.scale = Vector3(1.0, 1.0, 0.85)
	b.add_child(mi)
	var cord := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.125
	torus.rings = 16
	torus.ring_segments = 6
	cord.mesh = torus
	cord.position.y = -0.14
	var cord_mat := StandardMaterial3D.new()
	cord_mat.albedo_color = Color(0.2, 0.15, 0.09)
	cord_mat.roughness = 1.0
	cord.material_override = cord_mat
	b.add_child(cord)
	maze.add_child(b)
	b.global_position = at
	get_tree().create_timer(25.0, false).timeout.connect(func() -> void:
		if is_instance_valid(b):
			b.queue_free())
	return b


static func _sack_material() -> StandardMaterial3D:
	if _sack_mat != null:
		return _sack_mat
	# A coarse weave drawn into a small texture, tiled over the sack.
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var over := ((x / 4) + (y / 4)) % 2 == 0
			var along := float((x if over else y) % 4) / 3.0
			var v := 0.75 + 0.25 * sin(along * PI)
			if (x % 4 == 0 and not over) or (y % 4 == 0 and over):
				v *= 0.55
			img.set_pixel(x, y, Color(0.42 * v, 0.31 * v, 0.18 * v))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_scale = Vector3(6.0, 4.0, 1.0)
	m.roughness = 1.0
	_sack_mat = m
	return m


# --- Ending ---------------------------------------------------------------------------------

## The scouts turn and walk out the way they came; each is let go once it is
## behind every player's view or out through the arch.
func _scouts_leave() -> void:
	var scouts: Array[Node3D] = []
	for e in _entries:
		if is_instance_valid(e["scout"]):
			scouts.append(e["scout"])
	if _guard != null and is_instance_valid(_guard):
		scouts.append(_guard)
	for s in scouts:
		s.set("scripted_face", null)
		s.set("scripted_look", null)
	var waited := 0.0
	while not scouts.is_empty() and waited < SCOUT_EXIT_MAX:
		for i in range(scouts.size() - 1, -1, -1):
			var s := scouts[i]
			var to := _gate_at - _into * 3.0 - s.global_position
			to.y = 0.0
			s.set("scripted_walk", to.normalized() * SCOUT_EXIT_SPEED if to.length() > 0.3 else Vector3.ZERO)
			if waited > 1.0 and (_unseen(s) or (s.global_position - _gate_at).dot(_into) < -0.5):
				scouts.remove_at(i)
				s.queue_free()
		await get_tree().process_frame
		waited += get_process_delta_time()
	for s in scouts:
		if is_instance_valid(s):
			s.queue_free()
	if _guard != null and is_instance_valid(_guard):
		_guard.queue_free()
	_guard = null


## Behind every player's view.
func _unseen(s: Node3D) -> bool:
	for e in _entries:
		var cam := Coop.camera(e["p"])
		if cam == null:
			continue
		var to := s.global_position + Vector3(0.0, 1.0, 0.0) - cam.global_position
		if to.normalized().dot(-cam.global_basis.z) > -0.05:
			return false
	return true


func _end() -> void:
	if _bars != null and is_instance_valid(_bars):
		WOOD_DOOR.letterbox_out(_bars)
		_bars = null
	for e in _entries:
		var layer = e["layer"]
		if layer != null and is_instance_valid(layer):
			(layer as Node).queue_free()
		var p: Node3D = e["p"]
		if not is_instance_valid(p):
			continue
		p.call("scene_look_at", null)
		p.set("hands_busy", false)
		if p.get("in_cutscene") == true:
			p.call("end_cutscene")
	print("[abduction] the fight begins")
	if maze != null and maze.has_method("_on_taken_to_boss"):
		maze.call("_on_taken_to_boss")
	finished.emit()
	queue_free()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
