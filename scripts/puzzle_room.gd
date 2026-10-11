extends Node3D

## Puzzle rooms (2026-10-08). Every chest room except the morgue is one of these:
## the cloister round an open court, dressed with a puzzle. Step into the room and
## its gates rise behind you (maze.gd reads `sealed`); solve it and they sink,
## the court's sky light comes back up, and a stone plinth rises out of the floor
## with the room's chest on it -- or, in the one room furthest from the start,
## the mimic. The chest holds the room's SHARD (and potions and coins); the
## boss's great door (shard_door.gd) wants every shard before it opens.
##
## While a room is sealed it is a WARD: the Remnant cannot find the player in it
## (`is_warding`, read by stalker.gd), because being shut in with it would be a
## death sentence nobody could do anything about.
##
## The five dealt to the five rooms (`DEALT`, 2026-10-09), each colour-coded:
##   platforms  THE STAIR OF KEYS -- seven levers, each a colour, each raising
##              two or three of five stone platforms one step; the platforms
##              wear a band of colour for every lever that moves them. Exactly
##              one set of levers makes the stair 1-2-3-4-5 up to the keystone
##              (5.1 m); climb it and stand on it.
##   drowning   THE DROWNING COURT -- the court's arches shut with stone and black
##              water pours in, a stage at a time. Four coloured stones stand at
##              four heights; each can only be stood on at ONE water level (lower
##              and it is out of reach, higher and it is under). Step on them in
##              the order the Eye shows; a wrong stone makes the water surge. A
##              drain wheel in the middle lets two stages out. The water is cold:
##              in it to the chest, health drains (never below a quarter).
##   weighing   THE WEIGHING ROOM -- three coloured scales, each with its weight
##              in gold ingots; shrouded bodies, skulls and bundles of bones on
##              the floor. Carry them (E) onto the scales until all three balance,
##              with nothing left over.
##   mirrors    THE MIRROR CORRIDOR -- a red beam crosses the court; turn the
##              mirrors (E) to bring it to the eye on the far side, through the
##              coloured glass of the colour the eye wears. Pillars stop it.
##   bells      THE BELL PARRY -- three blades swing on gallows, each with a bell
##              above it. Stand in a blade's circle and parry it (block just
##              before it strikes) three times running to ring its bell.
## Three more are built but no longer dealt:
##   prism      THE PRISM -- three levers, each switching one or two of the red,
##              green and blue beams that meet in a crystal (rings on each lever
##              say which). Hold the crystal at the colour the Eye shows, three
##              times.
##   chorus     THE CHORUS OF STONES -- six coloured standing stones sing a
##              sequence; strike them back in the same order. Three rounds,
##              growing longer; a wrong note costs health (never below a quarter).
##   veil       THE VEIL -- four stone dials, each with four glyphs. Which glyph
##              each dial wants is written on the stelae in the corners, in a
##              hand only a ghost can read: it shows only in ghost mode.
##
## Built by maze.gd (`build`) under the navigation region, before the bake. The
## room keeps its state across deaths once solved; an unsolved room resets
## (`on_world_reset`, called by maze.gd after the world repopulates).

const CHEST_SCENE := preload("res://scenes/chest.tscn")
const MIMIC_SCENE := preload("res://scenes/mimic.tscn")

const KINDS: Array[StringName] = [&"platforms", &"drowning", &"weighing", &"mirrors", &"bells",
	&"prism", &"chorus", &"veil"]
## What the rooms are dealt from, every one before any repeats (maze.gd).
const DEALT: Array[StringName] = [&"platforms", &"drowning", &"weighing", &"mirrors", &"bells"]
const TITLES := {
	&"platforms": ["THE STAIR OF KEYS", "Seven levers raise the stones. Only one set makes a stair to the keystone."],
	&"drowning": ["THE DROWNING COURT", "Stand on the stones in the order the Eye shows. The water decides what you can reach."],
	&"weighing": ["THE WEIGHING ROOM", "Balance every scale. Nothing may be left on the floor."],
	&"mirrors": ["THE MIRROR CORRIDOR", "Turn the mirrors. Bring the light to the eye, in the colour it wears."],
	&"bells": ["THE BELL PARRY", "Parry each blade three times running, and its bell will ring."],
	&"prism": ["THE PRISM", "Turn the crystal to the colour of the Eye."],
	&"chorus": ["THE CHORUS OF STONES", "Listen to the stones. Then answer them."],
	&"veil": ["THE VEIL", "What is written here, only a ghost can read."],
}

const RED := Color(1.0, 0.13, 0.08)
const ORANGE := Color(1.0, 0.45, 0.06)
const YELLOW := Color(1.0, 0.86, 0.12)
const GREEN := Color(0.2, 1.0, 0.3)
const BLUE := Color(0.16, 0.42, 1.0)
const VIOLET := Color(0.68, 0.22, 1.0)
const GOLD := Color(1.0, 0.7, 0.12)
const CYAN := Color(0.15, 0.95, 1.0)
const WHITE := Color(0.95, 0.95, 1.0)
const PALE := Color(0.85, 0.82, 0.74)

## While a room is unsolved its sky light burns at this share of its own energy:
## the court darker, the puzzle's own glow the brightest thing in it.
## At 0.35 the stone of the puzzles (posts, platforms, standing stones) was
## black: only their glowing parts showed, as floating shapes.
const SKY_DIM := 0.55
## A light over the court in the room's own colour, so the stone of the puzzle
## is seen in it -- stronger while the room is unsolved.
const HEART_ENERGY := 2.6
const HEART_SOLVED := 0.9
## How far inside the gates the player must be before they rise behind them, so
## the bars never come up through someone standing in the doorway.
const SEAL_IN := 1.8
const PLINTH_H := 0.6

var built
var room: Dictionary = {}
var kind: StringName = &"platforms"
var shard: StringName = &""
var is_mimic := false
var maze: Node
var tint := 1.0

var solved := false
var sealed := false
## The shard has been taken (the chest opened, or the mimic killed).
var looted := false

var _rng := RandomNumberGenerator.new()
var _span := 9.0
var _block := 15.0
var _colour := Color.WHITE
var _stone: StandardMaterial3D
var _player: Node3D
var _prompt: Interact.Prompt
## {node, text, act: Callable, reach, ok?: Callable}
var _usable: Array[Dictionary] = []
var _focus: Dictionary = {}
## [light, its own energy] for the court's sky lights.
var _sky: Array = []
var _ring_mat: StandardMaterial3D
var _heart: OmniLight3D
var _vault_mat: StandardMaterial3D
var _vault_at := Vector3(0.0, 0.0, -5.3)
var _plinth: AnimatableBody3D
var _reward: Node3D
var _time := 0.0

static var _mats := {}


static func build(holder: Node3D, level, room_: Dictionary, kind_: StringName, shard_: StringName,
		mimic_: bool, maze_: Node, tint_: float) -> Node3D:
	var p := Node3D.new()
	p.set_script(load("res://scripts/puzzle_room.gd"))
	p.name = "PuzzleRoom"
	p.set("built", level)
	p.set("room", room_)
	p.set("kind", kind_)
	p.set("shard", shard_)
	p.set("is_mimic", mimic_)
	p.set("maze", maze_)
	p.set("tint", tint_)
	holder.add_child(p)
	p.call("_dress")
	return p


func title() -> String:
	return String(TITLES[kind][0])


# --- Building ---------------------------------------------------------------------

func _dress() -> void:
	add_to_group(&"puzzle_room")
	var centre: Vector3 = built.room_world(room)
	# The local frame: origin the court's centre, +Z toward the first way in.
	var out := Vector3(0.0, 0.0, 1.0)
	var doors: Array = built.room_doors(room)
	if not doors.is_empty():
		var step: Vector2i = doors[0]["outward"]
		out = Vector3(float(step.x), 0.0, float(step.y))
	global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), centre)
	_rng.seed = hash(room["centre"]) ^ 0x70757a
	_span = built.court_half_span(room)
	_block = (float(room["half"]) + 0.5) * float(built.cell_size)
	_colour = Inventory.item_color(shard)
	_stone = _mat(&"stone")
	_prompt = Interact.prompt("E   Use")
	add_child(_prompt)

	_build_atmosphere()
	match kind:
		&"platforms":
			_build_platforms()
		&"drowning":
			_build_drowning()
		&"weighing":
			_build_weighing()
		&"mirrors":
			_build_mirrors()
		&"bells":
			_build_bells()
		&"prism":
			_build_prism()
		&"chorus":
			_build_chorus()
		_:
			_build_veil()
	_build_vault()
	_gather_sky.call_deferred()
	print("[puzzle] %s at %s%s, shard %s" % [title(), room["centre"],
		" (the mimic's room)" if is_mimic else "", shard])


## A ring of the room's colour inlaid in the paving, and dust hanging in the
## dark over the court.
func _build_atmosphere() -> void:
	var ring := MeshInstance3D.new()
	ring.name = "RuneRing"
	var torus := TorusMesh.new()
	torus.inner_radius = _span - 1.75
	torus.outer_radius = _span - 1.5
	torus.rings = 72
	torus.ring_segments = 6
	ring.mesh = torus
	_ring_mat = _glow(_colour, 0.35)
	ring.material_override = _ring_mat
	ring.scale = Vector3(1.0, 0.08, 1.0)
	ring.position.y = 0.0
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_heart = OmniLight3D.new()
	_heart.name = "RoomLight"
	_heart.light_color = _colour.lerp(Color(1.0, 0.85, 0.7), 0.45)
	_heart.light_energy = HEART_ENERGY
	_heart.omni_range = _span * 1.6
	_heart.omni_attenuation = 0.8
	_heart.light_specular = 0.2
	_heart.shadow_enabled = false
	_heart.distance_fade_enabled = true
	_heart.distance_fade_begin = 45.0
	_heart.distance_fade_length = 12.0
	_heart.position = Vector3(0.0, 4.5, 0.0)
	add_child(_heart)
	# Effects are optional: every pixel of a transparent particle is paid for.
	if not Graphics.effects:
		return
	var motes := GPUParticles3D.new()
	motes.name = "Motes"
	motes.amount = 70
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.position.y = 2.6
	motes.visibility_aabb = AABB(Vector3(-_span, -3.0, -_span), Vector3(_span * 2.0, 8.0, _span * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(_span - 1.0, 2.4, _span - 1.0)
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.12
	pm.gravity = Vector3(0.0, 0.015, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	motes.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_color = Color(_colour.lerp(Color.WHITE, 0.6), 0.55)
	quad.material = mm
	motes.draw_pass_1 = quad
	add_child(motes)


## Where the reward comes up: a dark disc in the floor with a ring of the room's
## colour, and the plinth waiting under it.
func _build_vault() -> void:
	var disc := _cyl(1.3, 0.04, 40, _mat(&"dark"))
	disc.position = _vault_at
	add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.02
	torus.outer_radius = 1.14
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	_vault_mat = _glow(_colour, 0.35)
	ring.material_override = _vault_mat
	ring.scale = Vector3(1.0, 0.12, 1.0)
	ring.position = _vault_at + Vector3(0.0, 0.025, 0.0)
	add_child(ring)
	# Origin at its top: under the paving (-0.02) until the room is solved.
	_plinth = AnimatableBody3D.new()
	_plinth.name = "Plinth"
	_plinth.collision_layer = 1 | 2
	_plinth.collision_mask = 0
	_plinth.position = _vault_at + Vector3(0.0, -0.06, 0.0)
	add_child(_plinth)
	var size := Vector3(1.8, PLINTH_H, 1.3)
	_box(_plinth, size, Vector3(0.0, -PLINTH_H * 0.5, 0.0), _stone)
	_box(_plinth, Vector3(1.88, 0.06, 1.38), Vector3(0.0, -0.03, 0.0), _mat(&"gold"))
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = -PLINTH_H * 0.5
	_plinth.add_child(cs)


func _gather_sky() -> void:
	_sky.clear()
	var holder: Node = maze.get("_room_sky_lights") if maze != null else null
	if holder == null:
		return
	var centre := global_position
	for node in holder.find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		if String(light.name).begins_with("RockFill"):
			continue
		var p := light.global_position
		if absf(p.x - centre.x) <= _span + 1.0 and absf(p.z - centre.z) <= _span + 1.0:
			_sky.append([light, light.light_energy])
	_set_sky(1.0 if solved else SKY_DIM, 0.0)


func _set_sky(share: float, time: float) -> void:
	for pair in _sky:
		var light: OmniLight3D = pair[0]
		if not is_instance_valid(light):
			continue
		if time <= 0.0:
			light.light_energy = float(pair[1]) * share
		else:
			create_tween().tween_property(light, "light_energy", float(pair[1]) * share, time)


# --- Running -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	_time += delta
	if not solved and not sealed:
		_check_seal()
	match kind:
		&"platforms":
			_tick_platforms(delta)
		&"drowning":
			_tick_drowning(delta)
		&"weighing":
			_tick_weighing(delta)
		&"mirrors":
			_tick_mirrors(delta)
		&"bells":
			_tick_bells(delta)
		&"prism":
			_tick_prism(delta)
		&"chorus":
			_tick_chorus(delta)
		_:
			_tick_veil(delta)
	_update_focus()


func _check_seal() -> void:
	if _player.get("_dead") == true:
		return
	var p := to_local(_player.global_position)
	var inner := _block - SEAL_IN
	# The drowning court shuts at the court's own arches, so it waits until the
	# player is in the court, clear of them -- seal it from the arcade and they
	# would be shut out of the puzzle and in with nothing.
	if kind == &"drowning":
		inner = _span - 1.2
	if absf(p.x) < inner and absf(p.z) < inner and p.y > -1.5 and p.y < 6.0:
		_seal()


func _seal() -> void:
	sealed = true
	var hud := _hud()
	if hud != null and hud.has_method("announce"):
		hud.announce(String(TITLES[kind][0]), String(TITLES[kind][1]))
	_shake(0.22)
	var t := create_tween()
	t.tween_property(_ring_mat, "emission_energy_multiplier", 2.4, 0.3)
	t.tween_property(_ring_mat, "emission_energy_multiplier", 0.6, 1.6)
	if kind == &"chorus":
		_autoplay(2.2)
	elif kind == &"drowning":
		_shut_sluices(true)
		_next_rise = _time + RISE_FIRST


## True for a point inside this room while it is sealed: nothing outside finds
## the player in here (the Remnant asks).
func is_warding(point: Vector3) -> bool:
	if not sealed:
		return false
	var p := to_local(point)
	return absf(p.x) < _block and absf(p.z) < _block and p.y > -2.0 and p.y < 8.0


func _update_focus() -> void:
	_focus = {}
	var blocked: bool = solved or _player.get("in_cutscene") == true or _player.get("_dead") == true \
		or _player.get("ui_open") == true
	if not blocked:
		var best := INF
		for u in _usable:
			var node: Node3D = u["node"]
			if not is_instance_valid(node) or not node.is_visible_in_tree():
				continue
			if u.has("ok") and not (u["ok"] as Callable).call():
				continue
			var to := node.global_position - _player.global_position
			var flat := Vector2(to.x, to.z).length()
			var reach := float(u["reach"])
			if flat > reach or absf(to.y) > 2.6:
				continue
			if not Interact.looked_at(node, reach + 1.6, 0.08):
				continue
			if flat < best:
				best = flat
				_focus = u
	_prompt.visible = not _focus.is_empty()
	if _prompt.visible:
		var text = _focus["text"]
		_prompt.text = String((text as Callable).call() if text is Callable else text)


func _unhandled_input(event: InputEvent) -> void:
	if not Interact.pressed(event):
		return
	if _focus.is_empty():
		# Carrying something in the weighing room: E with nothing in the
		# crosshair sets it down.
		if _carry != null and not solved:
			get_viewport().set_input_as_handled()
			_drop_carried()
		return
	get_viewport().set_input_as_handled()
	(_focus["act"] as Callable).call()


## `text` is a String, or a Callable returning one (a pan says Place or Take).
func _usable_add(node: Node3D, text: Variant, act: Callable, reach := 2.4, ok := Callable()) -> void:
	var u := {"node": node, "text": text, "act": act, "reach": reach}
	if ok.is_valid():
		u["ok"] = ok
	_usable.append(u)


func _solve() -> void:
	if solved:
		return
	solved = true
	sealed = false
	_focus = {}
	_prompt.visible = false
	var hud := _hud()
	if hud != null and hud.has_method("announce"):
		hud.announce("THE SEAL IS BROKEN", "Something rises from the floor.")
	_shake(0.3)
	_set_sky(1.0, 2.5)
	create_tween().tween_property(_heart, "light_energy", HEART_SOLVED, 2.5)
	var t := create_tween()
	t.tween_property(_ring_mat, "emission_energy_multiplier", 3.0, 0.25)
	t.tween_property(_ring_mat, "emission_energy_multiplier", 0.15, 2.5)
	match kind:
		&"drowning":
			# The water goes first, then the sluices; the plinth comes up dry.
			_set_water(0.0, DRAIN_ALL_TIME)
			_shut_sluices(false, DRAIN_ALL_TIME)
			get_tree().create_timer(DRAIN_ALL_TIME).timeout.connect(_reveal)
			return
		&"weighing":
			if _carry != null:
				_drop_carried()
		&"bells":
			for p in _pendulums:
				p["stopping"] = true
	_reveal()


## The plinth rises out of the floor in a column of light, and the reward
## appears on it.
func _reveal() -> void:
	var glow := create_tween()
	glow.tween_property(_vault_mat, "emission_energy_multiplier", 3.5, 0.5)
	_light_column()
	var rise := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	rise.tween_interval(0.5)
	rise.tween_property(_plinth, "position:y", _vault_at.y + PLINTH_H, 1.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rise.tween_callback(func() -> void: _shake(0.12))
	rise.tween_callback(func() -> void: _place_reward.call_deferred(true))


func _light_column() -> void:
	var beam := MeshInstance3D.new()
	beam.name = "LightColumn"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.9
	cyl.height = 34.0
	cyl.radial_segments = 24
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(_colour.lerp(Color.WHITE, 0.3), 0.0)
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = _vault_at + Vector3(0.0, 17.0, 0.0)
	add_child(beam)
	var t := create_tween()
	t.tween_property(m, "albedo_color:a", 0.3, 0.5)
	t.tween_interval(1.8)
	t.tween_property(m, "albedo_color:a", 0.0, 2.2)
	t.tween_callback(beam.queue_free)
	if Graphics.effects:
		var light := OmniLight3D.new()
		light.light_color = _colour.lerp(Color.WHITE, 0.3)
		light.omni_range = 9.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.position = _vault_at + Vector3(0.0, 2.5, 0.0)
		add_child(light)
		var lt := create_tween()
		lt.tween_property(light, "light_energy", 5.0, 0.5)
		lt.tween_interval(1.8)
		lt.tween_property(light, "light_energy", 0.0, 2.2)
		lt.tween_callback(light.queue_free)


func _place_reward(pop: bool) -> void:
	if looted:
		return
	var top := to_global(_vault_at + Vector3(0.0, PLINTH_H, 0.0))
	if is_mimic:
		var m: Node3D = MIMIC_SCENE.instantiate()
		m.set("shard", shard)
		# It springs when opened from the floor beside its plinth.
		m.set("wake_floor", -1.3)
		maze.add_child(m)
		m.global_position = top
		m.rotation.y = global_rotation.y
		m.connect("died", _on_reward_taken)
		if maze.has_method("register_mimic"):
			maze.call("register_mimic", m)
		_reward = m
		return
	var c: Node3D = CHEST_SCENE.instantiate()
	c.set("shard", shard)
	c.set("coins", _rng.randi_range(25, 60))
	c.set("min_amount", 1)
	c.set("max_amount", 3)
	c.set("opened_title", "SHARD RECOVERED")
	add_child(c)
	c.position = _vault_at + Vector3(0.0, PLINTH_H, 0.0)
	c.connect("opened", _on_reward_taken.unbind(1))
	_reward = c
	if pop:
		c.scale = Vector3.ONE * 0.05
		create_tween().tween_property(c, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_reward_taken() -> void:
	looted = true
	create_tween().tween_property(_vault_mat, "emission_energy_multiplier", 0.15, 1.5)


## --- Saving (save_system.gd, via maze.gd) -----------------------------------------

func save_state() -> Dictionary:
	return {"kind": kind, "solved": solved, "looted": looted}


## A loaded game: the room as it was left. Unsolved is how it was built; solved
## is put straight into its finished look -- no scene, no column of light --
## with the reward on its plinth unless it was taken.
func restore_state(data: Dictionary) -> void:
	if not bool(data.get("solved", false)):
		return
	solved = true
	sealed = false
	looted = bool(data.get("looted", false))
	_set_sky(1.0, 0.0)
	_heart.light_energy = HEART_SOLVED
	_ring_mat.emission_energy_multiplier = 0.15
	_vault_mat.emission_energy_multiplier = 0.15 if looted else 3.5
	_plinth.position.y = _vault_at.y + PLINTH_H
	match kind:
		&"platforms":
			for l in _levers.size():
				var lever: Dictionary = _levers[l]
				lever["on"] = bool(_answer & (1 << l))
				(lever["arm"] as Node3D).rotation.x = LEVER_ON if lever["on"] else LEVER_OFF
				(lever["gem"] as StandardMaterial3D).emission_energy_multiplier = 3.2 if lever["on"] else 0.7
			for i in _plats.size():
				_plats[i]["level"] = i + 1
				(_plats[i]["body"] as Node3D).position.y = _plat_top(i + 1)
		&"weighing":
			for k in mini(_assign.size(), _items.size()):
				_put_on_pan(k, _assign[k])
			_reweigh()
		&"mirrors":
			_restore_mirrors()
		&"bells":
			for pd in _pendulums:
				pd["rung"] = true
				pd["stopping"] = true
				pd["amp"] = 0.0
				pd["ang"] = 0.0
				(pd["bell_mat"] as StandardMaterial3D).emission_energy_multiplier = 1.5
				for lm in pd["lamps"]:
					(lm as StandardMaterial3D).emission = GOLD
					(lm as StandardMaterial3D).emission_energy_multiplier = 3.0
	if not looted:
		_place_reward(false)
	elif not is_mimic:
		# Its chest stands open and empty on the plinth.
		var c: Node3D = CHEST_SCENE.instantiate()
		c.set("opened_already", true)
		add_child(c)
		c.position = _vault_at + Vector3(0.0, PLINTH_H, 0.0)
		var lid := c.get_node_or_null("LidPivot") as Node3D
		if lid != null:
			lid.rotation.x = deg_to_rad(-105.0)
		_reward = c


## Any setting of the mirrors that brings the right colour to the eye.
func _restore_mirrors() -> void:
	var mirrors: Array = []
	for c in _grid:
		if _grid[c]["kind"] == &"mirror":
			mirrors.append(c)
	for mask in 1 << mirrors.size():
		for i in mirrors.size():
			_grid[mirrors[i]]["orient"] = (mask >> i) & 1
		var r := _trace()
		if r["hit"] and r["colour"] == _dst["colour"]:
			for i in mirrors.size():
				var item: Dictionary = _grid[mirrors[i]]
				item["turns"] = int(item["orient"])
				(item["spin"] as Node3D).rotation.y = -PI * 0.25 + float(item["turns"]) * PI * 0.5
			break
	_draw_beam()


## The world was reset by a death (maze.gd calls this AFTER it repopulates). An
## unsolved room starts again; a solved one stays solved, and an unkilled mimic
## is back, asleep, on its plinth.
func on_world_reset() -> void:
	if not solved:
		sealed = false
		_reset_puzzle()
		_set_sky(SKY_DIM, 0.0)
		_ring_mat.emission_energy_multiplier = 0.35
	elif is_mimic and not looted:
		if is_instance_valid(_reward):
			_reward.free()
		_reward = null
		_place_reward(false)


func _reset_puzzle() -> void:
	match kind:
		&"platforms":
			_reset_platforms()
		&"drowning":
			_reset_drowning()
		&"weighing":
			_reset_weighing()
		&"mirrors":
			_reset_mirrors()
		&"bells":
			_reset_bells()
		&"prism":
			_reset_prism()
		&"chorus":
			_reset_chorus()
		_:
			_reset_veil()


# --- THE STAIR OF KEYS ----------------------------------------------------------------

const RISE := 0.85
const PLATFORM := 1.8
const KEY_SIZE := 2.0
## Harder since 2026-10-09: five platforms and seven levers (was four and
## four), the keystone at 6 steps (5.1 m). With seven levers there are 128
## combinations and the planner keeps only layouts where exactly one works.
const PLATS := 5
const LEVERS := 7
const KEY_LEVEL := 6
## No platform may be raised past this, whatever is pulled.
const MAX_LEVEL := 6
## Centre to centre along the diagonal: 0.89 m of air between faces.
const PLAT_STEP := 2.69
## Platforms are tall columns whose top is the body's origin; the rest of them
## is under the floor at every height they reach.
const PLAT_TALL := 7.0
const LEVER_COLOURS: Array[Color] = [RED, BLUE, GREEN, GOLD, VIOLET, CYAN, WHITE]

var _plats: Array[Dictionary] = []
var _levers: Array[Dictionary] = []
## The one set of levers that works, as a bit mask (for a loaded, solved room).
var _answer := 0
var _key_at := Vector3(-5.6, 0.0, -5.6)
var _key_plate: StandardMaterial3D


static func _plat_top(level: int) -> float:
	return 0.02 + float(level) * RISE


## Which platforms each lever moves, where they start, and the one combination
## of levers that makes the stair 1-2-3-4-5 to the keystone at 6. The answer
## takes three or four of the seven levers, and every lever moves two or three
## platforms, so no platform can be set on its own.
func _plan_platforms() -> Dictionary:
	for attempt in 4000:
		var moves: Array = []
		for l in LEVERS:
			var pool: Array = range(PLATS)
			for i in range(PLATS - 1, 0, -1):
				var j := _rng.randi_range(0, i)
				var tmp = pool[i]
				pool[i] = pool[j]
				pool[j] = tmp
			var n := 2 if _rng.randf() < 0.6 else 3
			var picked: Array = pool.slice(0, n)
			picked.sort()
			moves.append(picked)
		var cover: Array = []
		for i in PLATS:
			cover.append(0)
		for m in moves:
			for i in m:
				cover[i] += 1
		if 0 in cover:
			continue
		# The answer: three or four levers.
		var order: Array = range(LEVERS)
		for i in range(LEVERS - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		var answer := 0
		for k in _rng.randi_range(3, 4):
			answer |= 1 << int(order[k])
		var base: Array = []
		var ok := true
		for i in PLATS:
			var up := 0
			for l in LEVERS:
				if answer & (1 << l) and i in moves[l]:
					up += 1
			var lv: int = i + 1 - up
			if lv < 0 or lv + int(cover[i]) > MAX_LEVEL:
				ok = false
			base.append(lv)
		if not ok:
			continue
		var solutions := 0
		for mask in 1 << LEVERS:
			var right := true
			for i in PLATS:
				var lv: int = base[i]
				for l in LEVERS:
					if mask & (1 << l) and i in moves[l]:
						lv += 1
				if lv != i + 1:
					right = false
					break
			if right:
				solutions += 1
				if solutions > 1:
					break
		if solutions != 1:
			continue
		return {"moves": moves, "base": base, "answer": answer}
	push_warning("puzzle_room: no unique Stair of Keys found; using the plain one")
	# Always solvable: lever i raises platform i, the last two nothing useful.
	var plain := {"moves": [], "base": [], "answer": 0}
	for l in LEVERS:
		plain["moves"].append([l % PLATS])
	for i in PLATS:
		plain["base"].append(i)
		plain["answer"] |= 1 << i
	return plain


func _build_platforms() -> void:
	var plan := _plan_platforms()
	_answer = int(plan["answer"])
	var dir := Vector3(1.0, 0.0, 1.0).normalized()
	var yaw := PI * 0.25
	var key_top := _plat_top(KEY_LEVEL)
	# The keystone: a column the stair has to reach, a glowing plate on its top.
	var key := Node3D.new()
	key.name = "Keystone"
	key.position = _key_at
	key.rotation.y = yaw
	add_child(key)
	_box(key, Vector3(KEY_SIZE, key_top + 0.1, KEY_SIZE), Vector3(0.0, (key_top - 0.1) * 0.5, 0.0), _stone)
	_solid(key, Vector3(KEY_SIZE, key_top + 0.1, KEY_SIZE), Vector3(0.0, (key_top - 0.1) * 0.5, 0.0))
	_box(key, Vector3(KEY_SIZE + 0.16, 0.12, KEY_SIZE + 0.16), Vector3(0.0, key_top - 0.08, 0.0), _mat(&"gold"))
	_key_plate = _glow(_colour, 0.9)
	var plate := _cyl(0.6, 0.05, 6, _key_plate)
	plate.position.y = key_top + 0.02
	key.add_child(plate)

	var band_mats: Array[StandardMaterial3D] = []
	for c in LEVER_COLOURS:
		band_mats.append(_glow(c, 1.6))
	for i in PLATS:
		var body := AnimatableBody3D.new()
		body.name = "Platform%d" % i
		body.collision_layer = 1 | 2
		body.collision_mask = 0
		body.position = _key_at + dir * PLAT_STEP * float(PLATS - i)
		body.rotation.y = yaw
		add_child(body)
		_box(body, Vector3(PLATFORM, PLAT_TALL, PLATFORM), Vector3(0.0, -PLAT_TALL * 0.5, 0.0), _stone)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(PLATFORM, PLAT_TALL, PLATFORM)
		cs.shape = bs
		cs.position.y = -PLAT_TALL * 0.5
		body.add_child(cs)
		# A band of colour round its top for every lever that moves it.
		var k := 0
		for l in LEVERS:
			if i in plan["moves"][l]:
				_box(body, Vector3(PLATFORM + 0.07, 0.08, PLATFORM + 0.07),
					Vector3(0.0, -0.13 - 0.17 * float(k), 0.0), band_mats[l])
				k += 1
		var base: int = plan["base"][i]
		body.position.y = _plat_top(base)
		_plats.append({"body": body, "base": base, "level": base})

	# Between the court's arches (at 0 and +-6 along each side) and clear of the
	# stair's diagonal and the vault.
	var spots: Array[Vector3] = [Vector3(-7.4, 0.0, 3.0), Vector3(-3.0, 0.0, 7.4),
		Vector3(3.0, 0.0, 7.4), Vector3(7.4, 0.0, 3.0), Vector3(7.4, 0.0, -3.0),
		Vector3(3.0, 0.0, -7.4), Vector3(-7.4, 0.0, -3.0)]
	for l in LEVERS:
		var lever := _lever(spots[l], LEVER_COLOURS[l])
		lever["moves"] = plan["moves"][l]
		_levers.append(lever)
		_usable_add(lever["node"], "E   Pull", _pull_platform_lever.bind(l))
	_vault_at = Vector3(4.6, 0.0, -4.6)


func _pull_platform_lever(l: int) -> void:
	var lever: Dictionary = _levers[l]
	lever["on"] = not lever["on"]
	_swing_lever(lever)
	for i in PLATS:
		var level: int = _plats[i]["base"]
		for k in LEVERS:
			if _levers[k]["on"] and i in _levers[k]["moves"]:
				level += 1
		if level != int(_plats[i]["level"]):
			_plats[i]["level"] = level
			var t := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			t.tween_property(_plats[i]["body"], "position:y", _plat_top(level), 1.1) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shake(0.14)


func _tick_platforms(_delta: float) -> void:
	if _key_plate != null:
		_key_plate.emission_energy_multiplier = 0.2 if solved else 0.9 + 0.5 * sin(_time * 2.2)
	if solved or not sealed:
		return
	var body := _player as CharacterBody3D
	if body == null or not body.is_on_floor():
		return
	var p := to_local(_player.global_position)
	var d := Vector2(p.x - _key_at.x, p.z - _key_at.z).length()
	if d < KEY_SIZE * 0.62 and p.y > _plat_top(KEY_LEVEL) - 0.3:
		_solve()


func _reset_platforms() -> void:
	for lever in _levers:
		lever["on"] = false
		(lever["arm"] as Node3D).rotation.x = LEVER_OFF
		(lever["gem"] as StandardMaterial3D).emission_energy_multiplier = 0.7
	for p in _plats:
		p["level"] = p["base"]
		(p["body"] as Node3D).position.y = _plat_top(int(p["base"]))


# --- THE DROWNING COURT ---------------------------------------------------------------

## The water's four stages, and the tops of the four stones that go with them.
## A jump from the water reaches about surface + 0.32 (floating with the feet
## `SWIM_FLOAT` 0.95 under, plus the 1.27 m jump), so a stone is out of reach
## below its stage; it must stand at least 5 cm clear of the surface to be
## stood on, so above its stage it is under water. Each is usable at ONE stage.
## The lowest is a plate on the floor (stage 0); dry, a jump reaches only 1.27,
## short of the first column's 1.45.
const STAGE_Y: Array[float] = [0.0, 1.3, 2.4, 3.5]
const STONE_TOP: Array[float] = [0.02, 1.45, 2.55, 3.65]
## Seconds before the first rise after sealing, between rises, and to rise.
const RISE_FIRST := 6.0
const RISE_EVERY := 9.0
const RISE_TIME := 2.5
## The drain wheel lets two stages out.
const DRAIN_STAGES := 2
const DRAIN_TIME := 2.5
const DRAIN_ALL_TIME := 4.0
## Health per second in the water to the chest, never below a quarter.
const COLD_DRAIN := 3.0
const COLD_FLOOR := 0.25
const STONE_COLOURS: Array[Color] = [RED, BLUE, GREEN, GOLD]
## A module cell's sides, as maze.gd `_boss_court_gates` reads them.
const _SIDE_STEP := {1: Vector2i(0, -1), 2: Vector2i(1, 0), 4: Vector2i(0, 1), 8: Vector2i(-1, 0)}
const _OPPOSITE := {1: 4, 4: 1, 2: 8, 8: 2}
## The court-facing arches (measured for the boss court, 2026-09-29): 3.6 m
## wide, crown 3.82, the passage ~2.55 m in from the arcade cell's centre.
const ARCH_W := 3.8
const ARCH_H := 4.1
const ARCH_DEPTH := 2.55

var _stage := 0
var _surface := 0.0
var _water_tween: Tween
var _water: MeshInstance3D
var _next_rise := INF
var _wstones: Array[Dictionary] = []
var _order: Array[int] = []
var _step := 0
var _gems: Array[StandardMaterial3D] = []
var _sluices: Array[Dictionary] = []
var _spouts: Array[MeshInstance3D] = []
var _wheel: Node3D
var _on_stone := -1
var _cold_warned := false
var _rising_until := 0.0


## Where the water stands over `point` (world y), or -INF: read by the player
## (group "water") to float.
func water_surface_at(point: Vector3) -> float:
	if _surface <= 0.02:
		return -INF
	var p := to_local(point)
	if absf(p.x) > _span or absf(p.z) > _span:
		return -INF
	return global_position.y + _surface


func _build_drowning() -> void:
	add_to_group(&"water")
	var colours: Array[Color] = STONE_COLOURS.duplicate()
	for i in range(colours.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := colours[i]
		colours[i] = colours[j]
		colours[j] = tmp
	# The stones in the corners: a plate on the floor, then three columns.
	var spots: Array[Vector3] = [Vector3(-6.6, 0.0, 6.6), Vector3(6.6, 0.0, 6.6),
		Vector3(6.6, 0.0, -6.6), Vector3(-6.6, 0.0, -6.6)]
	for s in 4:
		var at := spots[s]
		var top := STONE_TOP[s]
		var mat := _glow(colours[s], 0.6)
		if s > 0:
			_box(self, Vector3(1.6, top, 1.6), at + Vector3(0.0, top * 0.5, 0.0), _stone)
			_box(self, Vector3(1.72, 0.1, 1.72), at + Vector3(0.0, top - 0.05, 0.0), _mat(&"gold"))
			_solid(self, Vector3(1.6, top, 1.6), at + Vector3(0.0, top * 0.5, 0.0))
		else:
			var rim := _cyl(0.85, 0.04, 32, _mat(&"gold"))
			rim.position = at + Vector3(0.0, 0.0, 0.0)
			add_child(rim)
		var plate := _cyl(0.6, 0.05, 32, mat)
		plate.position = at + Vector3(0.0, top + 0.02, 0.0)
		add_child(plate)
		_wstones.append({"at": at, "top": top, "mat": mat, "colour": colours[s]})
	# The order, never simply low to high or high to low.
	while true:
		_order = [0, 1, 2, 3]
		for i in range(3, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp := _order[i]
			_order[i] = _order[j]
			_order[j] = tmp
		var up := true
		var down := true
		for k in 3:
			up = up and _order[k + 1] == _order[k] + 1
			down = down and _order[k + 1] == _order[k] - 1
		if not up and not down:
			break
	# The Eye over the vault, above the highest water: four gems in the order.
	_vault_at = Vector3(0.0, 0.0, -5.3)
	for s: float in [-1.0, 1.0]:
		_box(self, Vector3(0.4, 5.4, 0.4), Vector3(s * 1.6, 2.7, -7.0), _stone)
		_solid(self, Vector3(0.4, 5.4, 0.4), Vector3(s * 1.6, 2.7, -7.0))
	_box(self, Vector3(3.8, 0.4, 0.45), Vector3(0.0, 5.55, -7.0), _stone)
	for k in 4:
		var gem_mat := _glow(_wstones[_order[k]]["colour"], 0.5)
		var gem := _octa(0.26, 0.5, gem_mat)
		gem.position = Vector3(-0.9 + 0.6 * float(k), 4.6, -6.95)
		add_child(gem)
		_gems.append(gem_mat)
	# The drain wheel, in the middle, high enough to reach from the water.
	_box(self, Vector3(0.35, 2.0, 0.35), Vector3(0.0, 1.0, 1.0), _stone)
	_solid(self, Vector3(0.35, 2.0, 0.35), Vector3(0.0, 1.0, 1.0))
	_wheel = Node3D.new()
	_wheel.name = "DrainWheel"
	_wheel.position = Vector3(0.0, 2.05, 1.25)
	add_child(_wheel)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.56
	ring.mesh = torus
	ring.material_override = _mat(&"iron")
	ring.rotation.x = PI * 0.5
	_wheel.add_child(ring)
	for k in 3:
		var spoke := _box(_wheel, Vector3(1.0, 0.05, 0.05), Vector3.ZERO, _mat(&"iron"))
		spoke.rotation.z = PI * float(k) / 3.0
	_wheel.add_child(_sphere(0.1, _glow(PALE, 0.8)))
	_usable_add(_wheel, "E   Drain", _drain, 2.4)
	# The water.
	_water = MeshInstance3D.new()
	_water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_span * 2.0 + 0.6, _span * 2.0 + 0.6)
	_water.mesh = plane
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/black_water.gdshader")
	_water.material_override = wm
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water.visible = false
	add_child(_water)
	_build_sluices()
	# Spouts over the middle of each side, pouring while it rises.
	var pour := StandardMaterial3D.new()
	pour.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pour.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pour.albedo_color = Color(0.08, 0.1, 0.11, 0.6)
	for side in 4:
		var a := TAU * float(side) / 4.0
		var out := Vector3(sin(a), 0.0, cos(a))
		var head := _box(self, Vector3(0.6, 0.45, 0.7), out * (_span - 0.1) + Vector3(0.0, 4.5, 0.0), _stone)
		head.rotation.y = a
		var stream := _cyl(0.16, 4.3, 8, pour)
		stream.position = out * (_span - 0.5) + Vector3(0.0, 2.15, 0.0)
		stream.visible = false
		add_child(stream)
		_spouts.append(stream)


## A stone slab for each arch between the arcade and the court, sunk under the
## floor until the room seals.
func _build_sluices() -> void:
	var centre: Vector2i = room["centre"]
	var half: int = room["half"]
	for side in _SIDE_STEP:
		var out: Vector2i = _SIDE_STEP[side]
		var along := Vector2i(-out.y, out.x)
		var inward := Vector3(-float(out.x), 0.0, -float(out.y))
		for e in range(-(half - 1), half):
			var pos: Vector2i = centre + out * half + along * e
			var cell = built.cells.get(pos)
			if cell == null or not (int(cell.open) & int(_OPPOSITE[side])):
				continue
			var holder := Node3D.new()
			holder.name = "Sluice"
			add_child(holder)
			holder.global_transform = Transform3D(Basis(Vector3.UP, atan2(inward.x, inward.z)),
				built.to_world(pos) + inward * ARCH_DEPTH)
			var slab := Node3D.new()
			holder.add_child(slab)
			_box(slab, Vector3(ARCH_W, ARCH_H, 0.4), Vector3(0.0, ARCH_H * 0.5, 0.0), _stone)
			_box(slab, Vector3(ARCH_W * 0.7, 0.08, 0.06), Vector3(0.0, ARCH_H * 0.62, -0.22), _glow(_colour, 0.8))
			var body := _solid(slab, Vector3(ARCH_W, ARCH_H, 0.4), Vector3(0.0, ARCH_H * 0.5, 0.0))
			var shape := body.get_child(0) as CollisionShape3D
			shape.disabled = true
			slab.position.y = -ARCH_H - 0.1
			_sluices.append({"slab": slab, "shape": shape})


func _shut_sluices(shut: bool, time := 1.1) -> void:
	for s in _sluices:
		var shape: CollisionShape3D = s["shape"]
		shape.set_deferred(&"disabled", not shut)
		var t := create_tween()
		t.tween_property(s["slab"], "position:y", 0.0 if shut else -ARCH_H - 0.1, time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if shut:
		_shake(0.25)


func _set_stage(s: int, time: float) -> void:
	_stage = clampi(s, 0, STAGE_Y.size() - 1)
	_set_water(STAGE_Y[_stage], time)
	_next_rise = _time + time + RISE_EVERY


## One tween at a time: a drain still running would otherwise go on pulling the
## water down under a surge (or a rise) started after it.
func _set_water(y: float, time: float) -> void:
	if y > _surface:
		_rising_until = _time + time
	if _water_tween != null and _water_tween.is_valid():
		_water_tween.kill()
	_water_tween = create_tween()
	_water_tween.tween_property(self, "_surface", y, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _drain() -> void:
	if solved:
		return
	var t := create_tween()
	t.tween_property(_wheel, "rotation:z", _wheel.rotation.z + TAU, 1.2).set_trans(Tween.TRANS_QUAD)
	if _stage == 0:
		return
	_set_stage(_stage - DRAIN_STAGES, DRAIN_TIME)
	_shake(0.12)


func _tick_drowning(delta: float) -> void:
	_water.visible = _surface > 0.02
	_water.position.y = _surface
	var pouring := _time < _rising_until
	for stream in _spouts:
		stream.visible = pouring
	if solved or not sealed:
		return
	if _time >= _next_rise and _stage < STAGE_Y.size() - 1:
		_set_stage(_stage + 1, RISE_TIME)
	# Which stone, if any, the player is standing on.
	var body := _player as CharacterBody3D
	var p := to_local(_player.global_position)
	var on := -1
	if body != null and body.is_on_floor():
		for i in _wstones.size():
			var st: Dictionary = _wstones[i]
			var at: Vector3 = st["at"]
			var top: float = st["top"]
			# Counted only at its own stage: above it, the stone is under water.
			if Vector2(p.x - at.x, p.z - at.z).length() < 0.75 and absf(p.y - top) < 0.3 \
					and _surface < STAGE_Y[i] + 0.05:
				on = i
	if on != _on_stone:
		_on_stone = on
		if on >= 0:
			_stood_on(on)
	# The cold.
	var depth: float = _player.call("water_depth") if _player.has_method("water_depth") else -INF
	# Floating puts the feet 0.95 under: chest deep is anything past 0.8.
	if depth > 0.8:
		_player.call("drain_health", COLD_DRAIN * delta, float(_player.get("max_health")) * COLD_FLOOR)
		if not _cold_warned:
			_cold_warned = true
			var hud := _hud()
			if hud != null and hud.has_method("_show_toast"):
				hud.call("_show_toast", "The water is cold as the grave.", 2.0)


func _stood_on(i: int) -> void:
	# Back onto the stone just counted (a bob off its edge, a step down and up
	# again) is not a wrong stone.
	if _step > 0 and _order[_step - 1] == i:
		return
	var mat: StandardMaterial3D = _wstones[i]["mat"]
	if _order[_step] == i:
		_gems[_step].emission_energy_multiplier = 4.0
		_step += 1
		mat.emission_energy_multiplier = 3.5
		_shake(0.08)
		if _step >= _order.size():
			_solve()
		return
	# The wrong stone: the water surges and the Eye forgets.
	_step = 0
	for g in _gems:
		g.emission_energy_multiplier = 0.5
	for st in _wstones:
		(st["mat"] as StandardMaterial3D).emission_energy_multiplier = 0.6
	if _stage < STAGE_Y.size() - 1:
		_set_stage(_stage + 1, 1.2)
	_shake(0.3)
	var hud := _hud()
	if hud != null and hud.has_method("_show_toast"):
		hud.call("_show_toast", "The wrong stone. The water surges.", 1.8)


func _reset_drowning() -> void:
	if _water_tween != null and _water_tween.is_valid():
		_water_tween.kill()
	_stage = 0
	_surface = 0.0
	_rising_until = 0.0
	_next_rise = INF
	_step = 0
	_on_stone = -1
	for g in _gems:
		g.emission_energy_multiplier = 0.5
	for st in _wstones:
		(st["mat"] as StandardMaterial3D).emission_energy_multiplier = 0.6
	for s in _sluices:
		(s["shape"] as CollisionShape3D).set_deferred(&"disabled", true)
		(s["slab"] as Node3D).position.y = -ARCH_H - 0.1


# --- THE WEIGHING ROOM -----------------------------------------------------------------

const SCALE_COLOURS: Array[Color] = [RED, BLUE, GREEN]
const WEIGHTS := {&"shroud": 5, &"skull": 2, &"bones": 1}
## What lies on the floor: two shrouded bodies, three skulls, four bundles.
const LOAD: Array[StringName] = [&"shroud", &"shroud", &"skull", &"skull", &"skull",
	&"bones", &"bones", &"bones", &"bones"]
const BEAM_Y := 2.45
const ARM_L := 1.25
const HANG := 1.45
const SKULL_MODEL := "res://models/skull_worn_ready.glb"

var _scales: Array[Dictionary] = []
var _items: Array[Dictionary] = []
var _carry: Node3D = null
var _carry_i := -1
var _balanced_for := 0.0
## How the load was dealt: one answer, for putting a solved room back on load.
var _assign: Array[int] = []


func _build_weighing() -> void:
	# Deal the load into three heaps; each heap's weight is a scale's target.
	var targets: Array[int] = []
	var assign: Array[int] = []
	for attempt in 200:
		assign.clear()
		targets = [0, 0, 0]
		for k in LOAD.size():
			var g := _rng.randi_range(0, 2)
			assign.append(g)
			targets[g] += int(WEIGHTS[LOAD[k]])
		if targets.min() >= 3 and targets[0] != targets[1] and targets[1] != targets[2] \
				and targets[0] != targets[2]:
			break
	_assign = assign
	var spots: Array[Vector3] = [Vector3(-5.4, 0.0, -3.4), Vector3(5.4, 0.0, -3.4), Vector3(0.0, 0.0, 3.6)]
	for i in 3:
		_scales.append(_scale(spots[i], SCALE_COLOURS[i], targets[i]))
	# The load, scattered over the floor clear of the scales and the vault.
	_vault_at = Vector3(0.0, 0.0, -6.2)
	var placed: Array[Vector3] = []
	for k in LOAD.size():
		var at := Vector3.ZERO
		for tries in 200:
			at = Vector3(_rng.randf_range(-7.4, 7.4), 0.0, _rng.randf_range(-7.4, 7.4))
			var clear := at.distance_to(_vault_at) > 2.4
			for s in spots:
				if at.distance_to(s) < 2.6:
					clear = false
			for q in placed:
				if at.distance_to(q) < 1.9:
					clear = false
			if clear:
				break
		placed.append(at)
		var node := _load_item(LOAD[k])
		node.position = at
		node.rotation.y = _rng.randf_range(-PI, PI)
		_items.append({"node": node, "kind": LOAD[k], "weight": int(WEIGHTS[LOAD[k]]),
			"home": node.transform, "on": -1})
		_usable_add(node, "E   Lift", _lift_item.bind(k), 2.2,
			func() -> bool: return _carry == null and int(_items[k]["on"]) == -1)


## A scale on its post at `at`: a beam with a pan for the load at -X and a pan
## of gold ingots, `target` of them, at +X.
func _scale(at: Vector3, col: Color, target: int) -> Dictionary:
	var node := Node3D.new()
	node.name = "Scale"
	node.position = at
	add_child(node)
	_box(node, Vector3(0.9, 0.2, 0.9), Vector3(0.0, 0.1, 0.0), _stone)
	_box(node, Vector3(0.24, BEAM_Y, 0.24), Vector3(0.0, BEAM_Y * 0.5, 0.0), _stone)
	_solid(node, Vector3(0.6, BEAM_Y, 0.6), Vector3(0.0, BEAM_Y * 0.5, 0.0))
	var rune := _glow(col, 0.6)
	var gem := _octa(0.22, 0.4, rune)
	gem.position = Vector3(0.0, BEAM_Y + 0.42, 0.0)
	node.add_child(gem)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.58
	ring.mesh = torus
	ring.material_override = rune
	ring.scale = Vector3(1.0, 0.2, 1.0)
	ring.position.y = 0.21
	node.add_child(ring)
	var beam := Node3D.new()
	beam.position = Vector3(0.0, BEAM_Y, 0.0)
	node.add_child(beam)
	_box(beam, Vector3(ARM_L * 2.0 + 0.2, 0.1, 0.1), Vector3.ZERO, _mat(&"gold"))
	var pans: Array[Node3D] = []
	var rods: Array[MeshInstance3D] = []
	for s: float in [-1.0, 1.0]:
		var pan := Node3D.new()
		pan.name = "Pan"
		node.add_child(pan)
		var dish := _cyl(0.62, 0.05, 28, _mat(&"gold"))
		pan.add_child(dish)
		var rod := _cyl(0.025, HANG, 6, _mat(&"iron"))
		rod.position.y = HANG * 0.5
		pan.add_child(rod)
		pans.append(pan)
		rods.append(rod)
	# The counterweight: `target` ingots on the right pan, three to a row.
	for k in target:
		var row := k / 3
		var col_i := k % 3
		var layer := row / 2
		var ingot := _box(pans[1], Vector3(0.24, 0.08, 0.11),
			Vector3(-0.27 + 0.27 * float(col_i), 0.065 + 0.085 * float(layer), -0.14 + 0.28 * float(row % 2)),
			_mat(&"gold"))
		ingot.name = "Ingot"
	var d := {"node": node, "beam": beam, "pans": pans, "rune": rune, "target": target,
		"angle": 0.3, "weight": 0}
	_usable_add(pans[0], _pan_text.bind(_scales.size()), _use_pan.bind(_scales.size()), 2.4,
		_pan_ok.bind(_scales.size()))
	_pose_scale(d)
	return d


func _pan_text(_i: int) -> String:
	return "E   Place" if _carry != null else "E   Take"


func _pan_ok(i: int) -> bool:
	return _carry != null or not _on_pan(i).is_empty()


func _on_pan(i: int) -> Array[int]:
	var out: Array[int] = []
	for k in _items.size():
		if int(_items[k]["on"]) == i:
			out.append(k)
	return out


func _load_item(kind_: StringName) -> Node3D:
	var node := Node3D.new()
	node.name = String(kind_).capitalize()
	add_child(node)
	match kind_:
		&"shroud":
			var cloth := StandardMaterial3D.new()
			cloth.albedo_color = Color(0.3, 0.26, 0.2)
			cloth.roughness = 1.0
			var body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.24
			cap.height = 1.6
			body.mesh = cap
			body.material_override = cloth
			body.rotation.z = PI * 0.5
			body.position.y = 0.22
			body.scale = Vector3(1.0, 1.0, 0.75)
			node.add_child(body)
			for x: float in [-0.45, 0.1, 0.55]:
				var band := _cyl(0.245, 0.06, 12, _mat(&"rope"))
				band.rotation.z = PI * 0.5
				band.position = Vector3(x, 0.22, 0.0)
				band.scale = Vector3(1.0, 1.0, 0.76)
				node.add_child(band)
		&"skull":
			var packed := load(SKULL_MODEL) as PackedScene
			if packed != null:
				var skull: Node3D = packed.instantiate()
				node.add_child(skull)
				var box := Interact.drawn_bounds(skull)
				var s := 0.26 / maxf(box.size.y, 0.01)
				skull.scale = Vector3.ONE * s
				skull.position.y = 0.13
				for mi in skull.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).material_override = _mat(&"bone")
		_:
			for k in 3:
				var bone := MeshInstance3D.new()
				var cap := CapsuleMesh.new()
				cap.radius = 0.035
				cap.height = 0.62
				bone.mesh = cap
				bone.material_override = _mat(&"bone")
				bone.rotation = Vector3(PI * 0.5, 0.25 * float(k - 1), 0.0)
				bone.position = Vector3(0.05 * float(k - 1), 0.05 + 0.04 * float(k % 2), 0.0)
				node.add_child(bone)
			var tie := _cyl(0.09, 0.05, 10, _mat(&"rope"))
			tie.rotation.x = PI * 0.5
			tie.position.y = 0.07
			node.add_child(tie)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _lift_item(k: int) -> void:
	if _carry != null:
		return
	_take_up(k)


## Into the player's hands: held before the view, the hands' own weapon away,
## and slowed by what it weighs.
func _take_up(k: int) -> void:
	var camera := get_viewport().get_camera_3d()
	var node: Node3D = _items[k]["node"]
	if camera == null:
		return
	_items[k]["on"] = -2
	node.reparent(camera, false)
	match StringName(_items[k]["kind"]):
		&"shroud":
			node.transform = Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, 0.25),
				Vector3(0.0, -0.78, -1.05))
			_player.set("carry_speed_scale", 0.55)
		&"skull":
			node.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.34, -0.5, -1.05))
			_player.set("carry_speed_scale", 0.85)
		_:
			node.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.3, -0.45, -0.8))
			_player.set("carry_speed_scale", 0.95)
	_carry = node
	_carry_i = k
	_player.set("hands_busy", true)


func _let_go() -> void:
	_carry = null
	_carry_i = -1
	if _player != null:
		_player.set("hands_busy", false)
		_player.set("carry_speed_scale", 1.0)


## Item `k` onto scale `i`'s load pan, on top of whatever is there.
func _put_on_pan(k: int, i: int) -> void:
	var pan: Node3D = _scales[i]["pans"][0]
	var node: Node3D = _items[k]["node"]
	var count := _on_pan(i).size()
	node.reparent(pan, false)
	var a := float(count) * 2.1
	var r := 0.0 if count == 0 else 0.22
	node.transform = Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * r, 0.03 + 0.07 * float(count), sin(a) * r))
	_items[k]["on"] = i


func _use_pan(i: int) -> void:
	var pan: Node3D = _scales[i]["pans"][0]
	if _carry != null:
		var k := _carry_i
		_let_go()
		_put_on_pan(k, i)
		_shake(0.05)
	else:
		var on := _on_pan(i)
		if on.is_empty():
			return
		_take_up(on[-1])
	_reweigh()


func _drop_carried() -> void:
	if _carry == null:
		return
	var k := _carry_i
	var node := _carry
	_let_go()
	node.reparent(self, false)
	var ahead := -_player.global_basis.z
	ahead.y = 0.0
	var at := to_local(_player.global_position + ahead.normalized() * 1.1)
	at.y = 0.0
	at.x = clampf(at.x, -_span + 0.8, _span - 0.8)
	at.z = clampf(at.z, -_span + 0.8, _span - 0.8)
	node.transform = Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)), at)
	_items[k]["on"] = -1
	_reweigh()


func _reweigh() -> void:
	for i in _scales.size():
		var w := 0
		for k in _on_pan(i):
			w += int(_items[k]["weight"])
		_scales[i]["weight"] = w


## The beam tips toward the heavier side, further the more it is off; the pans
## hang straight down from its ends.
func _pose_scale(d: Dictionary) -> void:
	var a: float = d["angle"]
	(d["beam"] as Node3D).rotation.z = a
	var pans: Array = d["pans"]
	for s in 2:
		var sx := -1.0 if s == 0 else 1.0
		var end := Vector3(sx * ARM_L * cos(a), BEAM_Y + sx * ARM_L * sin(a), 0.0)
		(pans[s] as Node3D).position = end - Vector3(0.0, HANG, 0.0)


func _tick_weighing(delta: float) -> void:
	var all := not _scales.is_empty()
	for d in _scales:
		var off := int(d["weight"]) - int(d["target"])
		# A positive angle lifts the +X end (the ingots) and drops the load's
		# pan: heavier than its target, the load goes down.
		var want := clampf(float(off) * 0.06, -0.3, 0.3)
		d["angle"] = lerpf(float(d["angle"]), want, 1.0 - exp(-4.0 * delta))
		_pose_scale(d)
		var level := off == 0
		(d["rune"] as StandardMaterial3D).emission_energy_multiplier = 3.2 if level else 0.6
		if not level:
			all = false
	if solved or not sealed:
		return
	_balanced_for = _balanced_for + delta if all and _carry == null else 0.0
	if _balanced_for > 0.8:
		_solve()


func _reset_weighing() -> void:
	if _carry != null:
		_let_go()
	for k in _items.size():
		var node: Node3D = _items[k]["node"]
		if node.get_parent() != self:
			node.reparent(self, false)
		node.transform = _items[k]["home"]
		_items[k]["on"] = -1
	_reweigh()
	_balanced_for = 0.0


# --- THE MIRROR CORRIDOR ---------------------------------------------------------------

## A 5 x 5 grid of places across the court, 3 m apart. Beams run along its
## rows and columns at chest height; mirrors turn them 90 degrees.
const GRID: Array[float] = [-6.0, -3.0, 0.0, 3.0, 6.0]
const LIGHT_Y := 1.3
## Where the beam can come in and go out: the rows and columns at +-3 m, which
## meet the court's edge between its arches. `out` points from the grid cell
## to the edge.
const PORTS: Array[Dictionary] = [
	{"cell": Vector2i(0, 1), "out": Vector2i(-1, 0)}, {"cell": Vector2i(0, 3), "out": Vector2i(-1, 0)},
	{"cell": Vector2i(4, 1), "out": Vector2i(1, 0)}, {"cell": Vector2i(4, 3), "out": Vector2i(1, 0)},
	{"cell": Vector2i(1, 0), "out": Vector2i(0, -1)}, {"cell": Vector2i(3, 0), "out": Vector2i(0, -1)},
	{"cell": Vector2i(1, 4), "out": Vector2i(0, 1)}, {"cell": Vector2i(3, 4), "out": Vector2i(0, 1)},
]
## The corner the vault comes up in: nothing stands at that grid place.
const VAULT_CELL := Vector2i(0, 0)
const RECEIVER_COLOURS: Array[Color] = [BLUE, GREEN, GOLD]

var _grid := {}
var _src := {}
var _dst := {}
var _beam_root: Node3D
var _beam_mat := {}
var _receiver_mat: StandardMaterial3D
var _hit_for := 0.0
var _hit_right := false


static func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3(GRID[c.x], LIGHT_Y, GRID[c.y])


static func _in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < GRID.size() and c.y < GRID.size()


## orient 0: a mirror along (1, 1), swapping x and z; 1: along (1, -1).
static func _reflect(d: Vector2i, orient: int) -> Vector2i:
	return Vector2i(d.y, d.x) if orient == 0 else Vector2i(-d.y, -d.x)


func _plan_mirrors() -> bool:
	var a: Dictionary = PORTS[_rng.randi_range(0, PORTS.size() - 1)]
	var b: Dictionary = PORTS[_rng.randi_range(0, PORTS.size() - 1)]
	if a["out"] == b["out"]:
		return false
	_src = a.duplicate()
	_dst = b.duplicate()
	var path: Array = []
	var budget := [6000]
	if not _walk(a["cell"], -(a["out"] as Vector2i), {}, path, 0, budget):
		return false
	# Turns become mirrors; one straight stretch gets the eye's colour of glass.
	_grid.clear()
	var straight: Array[Vector2i] = []
	for step in path:
		var c: Vector2i = step[0]
		var din: Vector2i = step[1]
		var dout: Vector2i = step[2]
		if din == dout:
			straight.append(c)
		else:
			_grid[c] = {"kind": &"mirror", "orient": 0 if dout == Vector2i(din.y, din.x) else 1, "on_path": true}
	if straight.is_empty():
		return false
	var colour: Color = RECEIVER_COLOURS[_rng.randi_range(0, RECEIVER_COLOURS.size() - 1)]
	_dst["colour"] = colour
	_grid[straight[_rng.randi_range(0, straight.size() - 1)]] = {"kind": &"filter", "colour": colour}
	# Decoys: a pane of a wrong colour, three more mirrors, three pillars.
	var free: Array[Vector2i] = []
	var on_path := {}
	for step in path:
		on_path[step[0]] = true
	for x in GRID.size():
		for z in GRID.size():
			var c := Vector2i(x, z)
			if not on_path.has(c) and c != VAULT_CELL:
				free.append(c)
	for i in range(free.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := free[i]
		free[i] = free[j]
		free[j] = tmp
	var wrong: Array[Color] = []
	for c in RECEIVER_COLOURS:
		if c != colour:
			wrong.append(c)
	var decoys := [{"kind": &"filter", "colour": wrong[0]}, {"kind": &"mirror", "orient": 0},
		{"kind": &"mirror", "orient": 1}, {"kind": &"mirror", "orient": 0},
		{"kind": &"pillar"}, {"kind": &"pillar"}, {"kind": &"pillar"}]
	for k in mini(decoys.size(), free.size()):
		_grid[free[k]] = decoys[k]
	return true


## Depth-first through the grid from `c`, travelling `d`: straight on, or a
## turn (a mirror) either way. Done at the receiver's cell heading out of it,
## after at least three turns and seven cells.
func _walk(c: Vector2i, d: Vector2i, seen: Dictionary, path: Array, turns: int, budget: Array) -> bool:
	budget[0] -= 1
	if budget[0] <= 0 or not _in_grid(c) or seen.has(c) or c == VAULT_CELL or path.size() > 13:
		return false
	seen[c] = true
	var options: Array[Vector2i] = [d, Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]
	for i in range(2, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := options[i]
		options[i] = options[j]
		options[j] = tmp
	for o in options:
		var turn := 0 if o == d else 1
		path.append([c, d, o])
		if c == _dst["cell"] and o == _dst["out"] and turns + turn >= 3 and path.size() >= 7:
			return true
		if _walk(c + o, o, seen, path, turns + turn, budget):
			return true
		path.pop_back()
	seen.erase(c)
	return false


func _build_mirrors() -> void:
	var tries := 0
	while not _plan_mirrors():
		tries += 1
		if tries > 200:
			push_warning("puzzle_room: no mirror layout found")
			break
	_vault_at = Vector3(-7.4, 0.0, -7.4)
	_beam_root = Node3D.new()
	_beam_root.name = "Beam"
	add_child(_beam_root)
	# The source lantern and the receiving eye, on posts at the court's edge.
	var src_at := _port_point(_src)
	_box(self, Vector3(0.5, LIGHT_Y + 0.2, 0.5), src_at + Vector3(0.0, -(LIGHT_Y + 0.2) * 0.5 + 0.1, 0.0), _stone)
	_solid(self, Vector3(0.5, LIGHT_Y + 0.2, 0.5), src_at + Vector3(0.0, -(LIGHT_Y + 0.2) * 0.5 + 0.1, 0.0))
	var lamp := _sphere(0.24, _glow(RED, 3.0))
	lamp.position = src_at + Vector3(0.0, 0.3, 0.0)
	add_child(lamp)
	var dst_at := _port_point(_dst)
	_box(self, Vector3(0.5, LIGHT_Y, 0.5), dst_at - Vector3(0.0, LIGHT_Y * 0.5, 0.0), _stone)
	_solid(self, Vector3(0.5, LIGHT_Y, 0.5), dst_at - Vector3(0.0, LIGHT_Y * 0.5, 0.0))
	_receiver_mat = _glow(_dst["colour"], 0.6)
	var eye := _cyl(0.4, 0.08, 32, _receiver_mat)
	var into := -(_dst["out"] as Vector2i)
	var holder := Node3D.new()
	holder.position = dst_at + Vector3(0.0, 0.3, 0.0)
	holder.rotation.y = atan2(float(into.x), float(into.y))
	add_child(holder)
	eye.rotation.x = PI * 0.5
	holder.add_child(eye)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.52
	rim.mesh = torus
	rim.material_override = _mat(&"gold")
	rim.rotation.x = PI * 0.5
	holder.add_child(rim)
	# What stands in the grid.
	for c: Vector2i in _grid:
		var item: Dictionary = _grid[c]
		var at := _cell_pos(c)
		at.y = 0.0
		match StringName(item["kind"]):
			&"pillar":
				_box(self, Vector3(0.8, 3.2, 0.8), at + Vector3(0.0, 1.6, 0.0), _stone)
				_solid(self, Vector3(0.8, 3.2, 0.8), at + Vector3(0.0, 1.6, 0.0))
			&"filter":
				_box(self, Vector3(0.35, LIGHT_Y - 0.4, 0.35), at + Vector3(0.0, (LIGHT_Y - 0.4) * 0.5, 0.0), _stone)
				_solid(self, Vector3(0.5, LIGHT_Y + 0.4, 0.5), at + Vector3(0.0, (LIGHT_Y + 0.4) * 0.5, 0.0))
				var glass := StandardMaterial3D.new()
				glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glass.albedo_color = Color(item["colour"], 0.35)
				glass.emission_enabled = true
				glass.emission = item["colour"]
				glass.emission_energy_multiplier = 0.9
				glass.roughness = 0.1
				_box(self, Vector3(0.8, 0.8, 0.8), at + Vector3(0.0, LIGHT_Y, 0.0), glass)
				_box(self, Vector3(0.9, 0.06, 0.9), at + Vector3(0.0, LIGHT_Y - 0.43, 0.0), _mat(&"iron"))
				_box(self, Vector3(0.9, 0.06, 0.9), at + Vector3(0.0, LIGHT_Y + 0.43, 0.0), _mat(&"iron"))
			&"mirror":
				var node := Node3D.new()
				node.name = "Mirror"
				node.position = at
				add_child(node)
				_box(node, Vector3(0.3, LIGHT_Y - 0.5, 0.3), Vector3(0.0, (LIGHT_Y - 0.5) * 0.5, 0.0), _stone)
				_solid(node, Vector3(0.5, LIGHT_Y + 0.6, 0.5), Vector3(0.0, (LIGHT_Y + 0.6) * 0.5, 0.0))
				var spin := Node3D.new()
				spin.position.y = LIGHT_Y
				node.add_child(spin)
				_box(spin, Vector3(1.15, 1.05, 0.05), Vector3.ZERO, _mat(&"mirror"))
				_box(spin, Vector3(1.25, 0.08, 0.1), Vector3(0.0, 0.56, 0.0), _mat(&"gold"))
				_box(spin, Vector3(1.25, 0.08, 0.1), Vector3(0.0, -0.56, 0.0), _mat(&"gold"))
				item["node"] = node
				item["spin"] = spin
				# Scrambled: every mirror starts at random.
				item["orient"] = _rng.randi_range(0, 1)
				item["start"] = item["orient"]
				item["turns"] = int(item["orient"])
				spin.rotation.y = -PI * 0.25 + float(item["turns"]) * PI * 0.5
				_usable_add(node, "E   Turn", _turn_mirror.bind(c), 2.4)
	# Not already solved by the scramble.
	for guard in 20:
		var r := _trace()
		if not (r["hit"] and r["colour"] == _dst["colour"]):
			break
		var any: Vector2i = _grid.keys().filter(func(k) -> bool: return _grid[k]["kind"] == &"mirror")[0]
		_turn_mirror(any, true)
	_draw_beam()


## A point at the edge of the court for a port, at beam height.
func _port_point(port: Dictionary) -> Vector3:
	var c: Vector2i = port["cell"]
	var o: Vector2i = port["out"]
	return _cell_pos(c) + Vector3(float(o.x), 0.0, float(o.y)) * 2.6


func _turn_mirror(c: Vector2i, instant := false) -> void:
	var item: Dictionary = _grid[c]
	item["turns"] = int(item["turns"]) + 1
	item["orient"] = int(item["turns"]) % 2
	var to := -PI * 0.25 + float(item["turns"]) * PI * 0.5
	if instant:
		(item["spin"] as Node3D).rotation.y = to
	else:
		create_tween().tween_property(item["spin"], "rotation:y", to, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_draw_beam()


## Follows the light from the lantern: [from, to, colour] segments, and whether
## it reached the eye and in what colour.
func _trace() -> Dictionary:
	var segs: Array = []
	var col := RED
	var c: Vector2i = _src["cell"]
	var d: Vector2i = -(_src["out"] as Vector2i)
	var from := _port_point(_src)
	var last := c
	for n in 40:
		if not _in_grid(c):
			var hit: bool = last == _dst["cell"] and d == _dst["out"]
			var end := _port_point(_dst) if hit else _cell_pos(last) + Vector3(float(d.x), 0.0, float(d.y)) * 2.9
			segs.append([from, end, col])
			return {"segs": segs, "hit": hit, "colour": col}
		var at := _cell_pos(c)
		var item = _grid.get(c)
		if item != null:
			match StringName(item["kind"]):
				&"pillar":
					segs.append([from, at - Vector3(float(d.x), 0.0, float(d.y)) * 0.42, col])
					return {"segs": segs, "hit": false, "colour": col}
				&"mirror":
					segs.append([from, at, col])
					from = at
					d = _reflect(d, int(item["orient"]))
				&"filter":
					segs.append([from, at, col])
					from = at
					col = item["colour"]
		last = c
		c += d
	return {"segs": segs, "hit": false, "colour": col}


## The beam's segments are a pool of meshes, reused and hidden, never freed:
## freeing them the frame they were made left `Graphics` a deferred call on a
## dead node, an error per segment per turn.
func _draw_beam() -> void:
	var pool := _beam_root.get_children()
	for child in pool:
		(child as Node3D).visible = false
	var used := 0
	var r := _trace()
	for s in r["segs"]:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		if a.distance_to(b) < 0.01:
			continue
		var col: Color = s[2]
		var key := col.to_html()
		if not _beam_mat.has(key):
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(col.lerp(Color.WHITE, 0.2), 0.9)
			_beam_mat[key] = m
		var mi: MeshInstance3D
		if used < pool.size():
			mi = pool[used]
		else:
			mi = MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_beam_root.add_child(mi)
		used += 1
		(mi.mesh as BoxMesh).size = Vector3(0.05, 0.05, a.distance_to(b))
		mi.material_override = _beam_mat[key]
		mi.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5)
		mi.visible = true
	_hit_right = r["hit"] and r["colour"] == _dst["colour"]
	_receiver_mat.emission_energy_multiplier = 3.5 if _hit_right else (1.4 if r["hit"] else 0.6)


func _tick_mirrors(delta: float) -> void:
	if solved or not sealed:
		return
	_hit_for = _hit_for + delta if _hit_right else 0.0
	if _hit_for > 1.0:
		_solve()


func _reset_mirrors() -> void:
	for c: Vector2i in _grid:
		var item: Dictionary = _grid[c]
		if item["kind"] == &"mirror":
			item["orient"] = item["start"]
			item["turns"] = item["start"]
			(item["spin"] as Node3D).rotation.y = -PI * 0.25 + float(item["turns"]) * PI * 0.5
	_hit_for = 0.0
	_draw_beam()


# --- THE BELL PARRY ---------------------------------------------------------------------

const BELL_COLOURS: Array[Color] = [RED, BLUE, GOLD]
## Seconds for a full swing, there and back, slow to fast.
const BELL_PERIODS: Array[float] = [3.0, 2.5, 2.1]
const PIVOT_Y := 5.3
const ARM := 4.0
const SWING := 0.8
const STRIKE := 12.0
const PARRIES := 3
## Where a blade can reach someone, in the gallows' space: across the swing
## (|z|) and the blade's height over their feet.
const PATH_HALF := 0.8
const BLADE_REACH := 0.55


## What the player's parry throws back at: a blade has no body to shove, and
## takes no harm.
class Blade extends Node3D:
	func apply_knockback(_impulse: Vector3, _stun := 0.0) -> void:
		pass

	func take_damage(_amount: float, _from := Vector3.ZERO) -> void:
		pass


var _pendulums: Array[Dictionary] = []
var _guard_event = null
var _guard_hooked := false


func _build_bells() -> void:
	var places: Array = [[Vector3(-5.0, 0.0, -1.0), 0.0], [Vector3(5.0, 0.0, -1.0), PI],
		[Vector3(0.0, 0.0, 5.0), PI * 0.5]]
	for i in 3:
		_pendulums.append(_gallows(places[i][0], places[i][1], BELL_COLOURS[i], BELL_PERIODS[i]))
	_vault_at = Vector3(0.0, 0.0, -5.6)


## Gallows at `at`, turned `yaw`: two posts across the swing, a beam, a blade
## on an arm swinging along local X, a bell over it all, a circle to stand in
## and three lamps for the parries.
func _gallows(at: Vector3, yaw: float, col: Color, period: float) -> Dictionary:
	var node := Node3D.new()
	node.name = "Gallows"
	node.position = at
	node.rotation.y = yaw
	add_child(node)
	for s: float in [-1.0, 1.0]:
		_box(node, Vector3(0.35, PIVOT_Y + 0.4, 0.35), Vector3(0.0, (PIVOT_Y + 0.4) * 0.5, s * 1.5), _mat(&"wood"))
		_solid(node, Vector3(0.35, PIVOT_Y + 0.4, 0.35), Vector3(0.0, (PIVOT_Y + 0.4) * 0.5, s * 1.5))
	_box(node, Vector3(0.4, 0.35, 3.5), Vector3(0.0, PIVOT_Y + 0.2, 0.0), _mat(&"wood"))
	var edge := _glow(col, 0.6)
	_box(node, Vector3(0.42, 0.06, 3.0), Vector3(0.0, PIVOT_Y + 0.02, 0.0), edge)
	# The arm and the blade.
	var arm := Node3D.new()
	arm.position = Vector3(0.0, PIVOT_Y, 0.0)
	node.add_child(arm)
	var rod := _cyl(0.04, ARM - 0.3, 6, _mat(&"iron"))
	rod.position.y = -(ARM - 0.3) * 0.5
	arm.add_child(rod)
	var blade := Blade.new()
	blade.name = "Blade"
	blade.position.y = -ARM
	arm.add_child(blade)
	_box(blade, Vector3(1.1, 0.5, 0.05), Vector3.ZERO, _mat(&"iron"))
	var edge_mat := _glow(col, 0.4)
	for s: float in [-1.0, 1.0]:
		_box(blade, Vector3(0.05, 0.52, 0.07), Vector3(s * 0.56, 0.0, 0.0), edge_mat)
	# The bell, over the beam.
	var bell := Node3D.new()
	bell.position = Vector3(0.0, PIVOT_Y + 0.4, 0.0)
	node.add_child(bell)
	var bell_mat := _mat(&"bronze").duplicate() as StandardMaterial3D
	bell_mat.emission_enabled = true
	bell_mat.emission = col
	bell_mat.emission_energy_multiplier = 0.0
	var cup := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.5
	cone.height = 0.65
	cup.mesh = cone
	cup.material_override = bell_mat
	cup.position.y = 0.45
	bell.add_child(cup)
	# The circle to stand in, on the side the blade comes at.
	var circle := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.65
	circle.mesh = torus
	circle.material_override = edge
	circle.scale = Vector3(1.0, 0.1, 1.0)
	circle.position = Vector3(0.75, 0.01, 0.0)
	node.add_child(circle)
	var lamps: Array[StandardMaterial3D] = []
	for k in PARRIES:
		var lm := _glow(PALE, 0.12)
		var lamp := _sphere(0.09, lm)
		lamp.position = Vector3(0.22, PIVOT_Y - 0.1, -0.3 + 0.3 * float(k))
		node.add_child(lamp)
		lamps.append(lm)
	return {"node": node, "arm": arm, "blade": blade, "edge": edge_mat, "bell": bell, "bell_mat": bell_mat,
		"lamps": lamps, "ang": -SWING, "sign": 1.0, "amp": SWING, "w2": pow(TAU / period, 2.0),
		"count": 0, "rung": false, "stopping": false}


func _on_guarded(parried: bool, attacker: Node3D) -> void:
	_guard_event = [parried, attacker]


func _tick_bells(delta: float) -> void:
	if not _guard_hooked and _player.has_signal("guarded"):
		_guard_hooked = true
		_player.connect("guarded", _on_guarded)
	for pd in _pendulums:
		_swing(pd, delta)


## Swung by energy: at angle a its speed is what it would have falling from
## `amp`, so it never gains or loses height however it is stepped; it turns
## at +-amp. A blade meeting the player bounces back where it met them.
func _swing(pd: Dictionary, delta: float) -> void:
	if pd["stopping"]:
		pd["amp"] = move_toward(float(pd["amp"]), 0.0, delta * 0.35)
	var amp: float = pd["amp"]
	var w2: float = pd["w2"]
	var steps := 4
	var dt := delta / float(steps)
	var node: Node3D = pd["node"]
	var p := node.to_local(_player.global_position)
	var in_path: bool = absf(p.z) < PATH_HALF and absf(p.x) < ARM and p.y > -0.6 and p.y < 2.4 \
		and not solved and sealed and _player.get("_dead") != true
	for n in steps:
		var a: float = pd["ang"]
		var speed := sqrt(maxf(2.0 * w2 * (cos(a) - cos(amp)), 0.0)) + 0.12
		var before := ARM * sin(a)
		a += float(pd["sign"]) * speed * dt
		if absf(a) >= amp:
			a = clampf(a, -amp, amp)
			pd["sign"] = -float(pd["sign"])
		pd["ang"] = a
		var after := ARM * sin(a)
		var height := PIVOT_Y - ARM * cos(a) - p.y
		if in_path and height > 0.3 and height < 2.0:
			var reach := p.x - BLADE_REACH if after > before else p.x + BLADE_REACH
			if (before < reach and after >= reach) or (before > reach and after <= reach):
				var motion := signf(after - before)
				(pd["arm"] as Node3D).rotation.z = a
				_strike(pd, motion)
				pd["sign"] = -motion
				break
	(pd["arm"] as Node3D).rotation.z = float(pd["ang"])
	# The edge brightens as it comes at whoever is in its path.
	var near := 0.0
	if in_path:
		var gap := absf(ARM * sin(float(pd["ang"])) - p.x)
		near = clampf(1.0 - (gap - BLADE_REACH) / 2.0, 0.0, 1.0)
	(pd["edge"] as StandardMaterial3D).emission_energy_multiplier = 0.4 + 3.0 * near * near


func _strike(pd: Dictionary, motion: float) -> void:
	var node: Node3D = pd["node"]
	var dir := (node.global_basis.x * motion).normalized()
	var before := float(_player.get("health"))
	_guard_event = null
	_player.call("take_damage", STRIKE, dir, pd["blade"])
	var lamps: Array = pd["lamps"]
	if _guard_event != null and _guard_event[1] == pd["blade"]:
		if _guard_event[0]:
			pd["count"] = int(pd["count"]) + 1
			var k := int(pd["count"]) - 1
			if k < lamps.size():
				(lamps[k] as StandardMaterial3D).emission = GOLD
				(lamps[k] as StandardMaterial3D).emission_energy_multiplier = 3.0
			if int(pd["count"]) >= PARRIES and not pd["rung"]:
				_ring(pd)
			return
		_bell_miss(pd)
		return
	if float(_player.get("health")) < before:
		_bell_miss(pd)
		_player.call("apply_knockback", dir * 7.0 + Vector3.UP * 2.5)


func _bell_miss(pd: Dictionary) -> void:
	if pd["rung"]:
		return
	pd["count"] = 0
	for lm in pd["lamps"]:
		(lm as StandardMaterial3D).emission = PALE
		(lm as StandardMaterial3D).emission_energy_multiplier = 0.12


func _ring(pd: Dictionary) -> void:
	pd["rung"] = true
	pd["stopping"] = true
	var bell: Node3D = pd["bell"]
	var mat: StandardMaterial3D = pd["bell_mat"]
	var t := create_tween()
	for k in 4:
		t.tween_property(bell, "rotation:x", 0.35 * (1.0 - 0.2 * float(k)) * (1.0 if k % 2 == 0 else -1.0), 0.18)
	t.tween_property(bell, "rotation:x", 0.0, 0.2)
	mat.emission_energy_multiplier = 6.0
	create_tween().tween_property(mat, "emission_energy_multiplier", 1.5, 1.5)
	_shake(0.2)
	var rung := 0
	for p in _pendulums:
		if p["rung"]:
			rung += 1
	var hud := _hud()
	if hud != null and hud.has_method("_show_toast"):
		hud.call("_show_toast", "A bell rings.   %d / %d" % [rung, _pendulums.size()], 1.6)
	if rung >= _pendulums.size():
		_solve()


func _reset_bells() -> void:
	for pd in _pendulums:
		pd["rung"] = false
		pd["stopping"] = false
		pd["amp"] = SWING
		pd["count"] = 0
		(pd["bell_mat"] as StandardMaterial3D).emission_energy_multiplier = 0.0
		for lm in pd["lamps"]:
			(lm as StandardMaterial3D).emission = PALE
			(lm as StandardMaterial3D).emission_energy_multiplier = 0.12


# --- Levers (shared) ------------------------------------------------------------------

const LEVER_OFF := -0.55
const LEVER_ON := 0.55


## A lever on a stone post, facing the court's centre, with a crystal over it in
## `col` for reading from across the room. Returns {node, arm, gem, on}.
func _lever(at: Vector3, col: Color) -> Dictionary:
	var node := Node3D.new()
	node.name = "Lever"
	node.position = at
	node.rotation.y = atan2(-at.x, -at.z)
	add_child(node)
	_box(node, Vector3(0.42, 1.0, 0.42), Vector3(0.0, 0.5, 0.0), _stone)
	_box(node, Vector3(0.54, 0.1, 0.54), Vector3(0.0, 1.05, 0.0), _mat(&"iron"))
	_solid(node, Vector3(0.45, 1.1, 0.45), Vector3(0.0, 0.55, 0.0))
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, 0.86, 0.25)
	node.add_child(pivot)
	_box(pivot, Vector3(0.16, 0.14, 0.1), Vector3.ZERO, _mat(&"iron"))
	var arm := Node3D.new()
	pivot.add_child(arm)
	_box(arm, Vector3(0.06, 0.62, 0.06), Vector3(0.0, 0.31, 0.0), _mat(&"iron"))
	var gem := _glow(col, 0.7)
	var knob := _sphere(0.09, gem)
	knob.position = Vector3(0.0, 0.64, 0.0)
	arm.add_child(knob)
	var crown := _octa(0.16, 0.36, gem)
	crown.position = Vector3(0.0, 1.5, 0.0)
	node.add_child(crown)
	arm.rotation.x = LEVER_OFF
	return {"node": node, "arm": arm, "gem": gem, "on": false}


func _swing_lever(lever: Dictionary) -> void:
	var on: bool = lever["on"]
	var t := create_tween().set_parallel(true)
	t.tween_property(lever["arm"], "rotation:x", LEVER_ON if on else LEVER_OFF, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lever["gem"], "emission_energy_multiplier", 3.2 if on else 0.7, 0.2)


# --- THE PRISM ----------------------------------------------------------------------

const CHANNELS: Array[Color] = [Color(1.0, 0.0, 0.0), Color(0.0, 1.0, 0.0), Color(0.0, 0.0, 1.0)]
const PRISM_ROUNDS := 3
## Seconds the crystal has to hold the Eye's colour.
const PRISM_HOLD := 1.0
const HEART := Vector3(0.0, 2.5, 0.0)

var _prism_rows: Array[int] = []
var _prism_levers: Array[Dictionary] = []
var _channels := 0
var _targets: Array[int] = []
var _round := 0
var _hold := 0.0
var _between := false
var _crystal: Node3D
var _crystal_mat: StandardMaterial3D
var _crystal_light: OmniLight3D
var _beams: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _lamps: Array[StandardMaterial3D] = []


static func _mask_colour(mask: int) -> Color:
	return Color(1.0 if mask & 1 else 0.0, 1.0 if mask & 2 else 0.0, 1.0 if mask & 4 else 0.0)


static func _bits(mask: int) -> int:
	return (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1)


func _plan_prism() -> void:
	var masks: Array[int] = [1, 2, 4, 3, 5, 6]
	_prism_rows = [3, 6, 4]
	for attempt in 300:
		var rows: Array[int] = []
		for l in 3:
			rows.append(masks[_rng.randi_range(0, masks.size() - 1)])
		var twos := 0
		for r in rows:
			if _bits(r) == 2:
				twos += 1
		if twos < 2:
			continue
		# Every one of the 8 colours reachable: the rows independent over GF(2).
		var seen := {}
		for m in 8:
			var v := 0
			for l in 3:
				if m & (1 << l):
					v ^= rows[l]
			seen[v] = true
		if seen.size() == 8:
			_prism_rows = rows
			break
	# Two mixed colours and one more, never black.
	var mixed: Array[int] = [3, 5, 6, 7]
	var rest: Array[int] = [1, 2, 4, 3, 5, 6, 7]
	_targets.clear()
	while _targets.size() < 2:
		var m := mixed[_rng.randi_range(0, mixed.size() - 1)]
		if not m in _targets:
			_targets.append(m)
	while _targets.size() < PRISM_ROUNDS:
		var m := rest[_rng.randi_range(0, rest.size() - 1)]
		if not m in _targets:
			_targets.append(m)
	for i in range(_targets.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _targets[i]
		_targets[i] = _targets[j]
		_targets[j] = tmp


func _build_prism() -> void:
	_plan_prism()
	# The crystal over its pedestal, in the middle of the court.
	_box(self, Vector3(0.9, 1.3, 0.9), Vector3(0.0, 0.65, 0.0), _stone)
	_box(self, Vector3(1.05, 0.12, 1.05), Vector3(0.0, 1.3, 0.0), _mat(&"gold"))
	_solid(self, Vector3(0.9, 1.4, 0.9), Vector3(0.0, 0.7, 0.0))
	_crystal = Node3D.new()
	_crystal.name = "Crystal"
	_crystal.position = HEART
	add_child(_crystal)
	_crystal_mat = _glow(Color.BLACK, 0.0)
	_crystal_mat.albedo_color = Color(0.07, 0.07, 0.09)
	_crystal_mat.metallic = 0.3
	_crystal_mat.roughness = 0.12
	_crystal.add_child(_octa(0.46, 0.95, _crystal_mat))
	if Graphics.effects:
		_crystal_light = OmniLight3D.new()
		_crystal_light.omni_range = 8.0
		_crystal_light.light_energy = 0.0
		_crystal_light.shadow_enabled = false
		_crystal_light.distance_fade_enabled = true
		_crystal_light.distance_fade_begin = 40.0
		_crystal_light.distance_fade_length = 10.0
		_crystal_light.position = HEART
		add_child(_crystal_light)
	# A lantern in three corners, each throwing its colour at the crystal.
	var corners: Array[Vector3] = [Vector3(-7.3, 0.0, -7.3), Vector3(7.3, 0.0, -7.3), Vector3(7.3, 0.0, 7.3)]
	for c in 3:
		var at := corners[c]
		_box(self, Vector3(0.5, 2.6, 0.5), at + Vector3(0.0, 1.3, 0.0), _stone)
		_solid(self, Vector3(0.5, 2.6, 0.5), at + Vector3(0.0, 1.3, 0.0))
		_box(self, Vector3(0.64, 0.1, 0.64), at + Vector3(0.0, 2.62, 0.0), _mat(&"iron"))
		var orb := _sphere(0.22, _glow(CHANNELS[c], 2.6))
		orb.position = at + Vector3(0.0, 2.95, 0.0)
		add_child(orb)
		var beam := _beam(at + Vector3(0.0, 2.95, 0.0), HEART, CHANNELS[c])
		beam.visible = false
		_beams.append(beam)
	# The Eye, over the vault: the colour it wants, and a lamp per round won.
	_vault_at = Vector3(0.0, 0.0, -5.3)
	for s: float in [-1.0, 1.0]:
		_box(self, Vector3(0.4, 4.6, 0.4), Vector3(s * 1.45, 2.3, -7.0), _stone)
		_solid(self, Vector3(0.4, 4.6, 0.4), Vector3(s * 1.45, 2.3, -7.0))
	_box(self, Vector3(3.4, 0.4, 0.45), Vector3(0.0, 4.75, -7.0), _stone)
	_eye_mat = _glow(_mask_colour(_targets[0]), 2.4)
	var eye := _cyl(0.72, 0.1, 40, _eye_mat)
	eye.rotation.x = PI * 0.5
	eye.position = Vector3(0.0, 3.4, -7.0)
	add_child(eye)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.74
	torus.outer_radius = 0.92
	rim.mesh = torus
	rim.material_override = _mat(&"gold")
	rim.rotation.x = PI * 0.5
	rim.position = Vector3(0.0, 3.4, -7.0)
	add_child(rim)
	for k in PRISM_ROUNDS:
		var lamp_mat := _glow(PALE, 0.12)
		var lamp := _sphere(0.1, lamp_mat)
		lamp.position = Vector3(-0.45 + 0.45 * float(k), 2.3, -6.92)
		add_child(lamp)
		_lamps.append(lamp_mat)
	# The levers, in a row before the crystal. Each crown is the colour it makes
	# on its own; the rings round its post, the beams it switches.
	for l in 3:
		var at := Vector3(-2.4 + 2.4 * float(l), 0.0, 4.8)
		var lever := _lever(at, _mask_colour(_prism_rows[l]))
		var node: Node3D = lever["node"]
		var k := 0
		for c in 3:
			if _prism_rows[l] & (1 << c):
				var ring := MeshInstance3D.new()
				var t := TorusMesh.new()
				t.inner_radius = 0.25
				t.outer_radius = 0.31
				ring.mesh = t
				ring.material_override = _glow(CHANNELS[c], 1.8)
				ring.position = Vector3(0.0, 0.35 + 0.2 * float(k), 0.0)
				node.add_child(ring)
				k += 1
		_prism_levers.append(lever)
		_usable_add(node, "E   Pull", _pull_prism_lever.bind(l))


func _pull_prism_lever(l: int) -> void:
	var lever: Dictionary = _prism_levers[l]
	lever["on"] = not lever["on"]
	_swing_lever(lever)
	_channels = 0
	for k in 3:
		if _prism_levers[k]["on"]:
			_channels ^= _prism_rows[k]
	_show_channels()
	_hold = 0.0
	_shake(0.05)


func _show_channels() -> void:
	for c in 3:
		_beams[c].visible = bool(_channels & (1 << c))
	var col := _mask_colour(_channels)
	_crystal_mat.emission = col
	_crystal_mat.emission_energy_multiplier = 0.0 if _channels == 0 else 2.6
	if _crystal_light != null:
		_crystal_light.light_color = col if _channels != 0 else Color.WHITE
		_crystal_light.light_energy = 0.0 if _channels == 0 else 2.2


func _tick_prism(delta: float) -> void:
	_crystal.rotation.y += delta * 0.6
	_crystal.position.y = HEART.y + sin(_time * 1.3) * 0.08
	if solved or not sealed or _between:
		return
	if _channels == _targets[_round]:
		_hold += delta
		_eye_mat.emission_energy_multiplier = 2.4 + 3.0 * (_hold / PRISM_HOLD)
		if _hold >= PRISM_HOLD:
			_prism_round_won()
	else:
		_hold = 0.0
		_eye_mat.emission_energy_multiplier = 2.4


func _prism_round_won() -> void:
	_hold = 0.0
	_lamps[_round].emission = GOLD
	_lamps[_round].emission_energy_multiplier = 3.0
	_round += 1
	_shake(0.12)
	if _round >= PRISM_ROUNDS:
		_eye_mat.emission = Color.WHITE
		_solve()
		return
	_between = true
	_eye_mat.emission = Color.WHITE
	_eye_mat.emission_energy_multiplier = 6.0
	var t := create_tween()
	t.tween_interval(0.9)
	t.tween_callback(func() -> void:
		_eye_mat.emission = _mask_colour(_targets[_round])
		_eye_mat.emission_energy_multiplier = 2.4
		_between = false)


func _reset_prism() -> void:
	for lever in _prism_levers:
		lever["on"] = false
		(lever["arm"] as Node3D).rotation.x = LEVER_OFF
		(lever["gem"] as StandardMaterial3D).emission_energy_multiplier = 0.7
	_channels = 0
	_show_channels()
	_round = 0
	_hold = 0.0
	_between = false
	for m in _lamps:
		m.emission = PALE
		m.emission_energy_multiplier = 0.12
	_eye_mat.emission = _mask_colour(_targets[0])
	_eye_mat.emission_energy_multiplier = 2.4


# --- THE CHORUS OF STONES -------------------------------------------------------------

const CHORUS: Array[Color] = [RED, ORANGE, YELLOW, GREEN, BLUE, VIOLET]
const CHORUS_ROUNDS := 3
const NOTE_TIME := 0.62
const STONE_DIM := 0.3
## What a wrong note costs, never taking the player below a quarter of their
## health.
const WRONG_NOTE := 10.0

var _stones: Array[Dictionary] = []
var _seq: Array[int] = []
var _input := 0
var _playing := false
var _play_token := 0
var _bell: Node3D


func _new_sequence(length: int) -> Array[int]:
	var out: Array[int] = []
	while out.size() < length:
		var n := _rng.randi_range(0, CHORUS.size() - 1)
		# No stone twice running: a repeat is invisible when played back.
		if out.is_empty() or out[-1] != n:
			out.append(n)
	return out


func _build_chorus() -> void:
	var mid := Vector3(0.0, 0.0, 1.0)
	for i in CHORUS.size():
		var a := TAU * float(i) / float(CHORUS.size())
		var at := mid + Vector3(cos(a), 0.0, sin(a)) * 4.8
		var node := Node3D.new()
		node.name = "Stone%d" % i
		node.position = at
		node.rotation.y = atan2(mid.x - at.x, mid.z - at.z)
		add_child(node)
		_box(node, Vector3(1.05, 2.3, 0.5), Vector3(0.0, 1.15, 0.0), _stone)
		_box(node, Vector3(1.2, 0.14, 0.62), Vector3(0.0, 2.36, 0.0), _stone)
		_solid(node, Vector3(1.05, 2.4, 0.5), Vector3(0.0, 1.2, 0.0))
		var mat := _glow(CHORUS[i], STONE_DIM)
		var glyph := _cyl(0.27, 0.05, 24, mat)
		glyph.rotation.x = PI * 0.5
		glyph.position = Vector3(0.0, 1.55, 0.26)
		node.add_child(glyph)
		_box(node, Vector3(0.06, 0.9, 0.02), Vector3(0.0, 0.8, 0.255), mat)
		_stones.append({"node": node, "mat": mat, "tween": null})
		_usable_add(node, "E   Strike", _strike_stone.bind(i), 2.6)
	# The bell at the centre: E on it plays the round's song again.
	_bell = Node3D.new()
	_bell.name = "Bell"
	_bell.position = mid
	add_child(_bell)
	_box(_bell, Vector3(0.8, 1.05, 0.8), Vector3(0.0, 0.525, 0.0), _stone)
	_box(_bell, Vector3(0.94, 0.1, 0.94), Vector3(0.0, 1.07, 0.0), _mat(&"gold"))
	_solid(_bell, Vector3(0.8, 1.1, 0.8), Vector3(0.0, 0.55, 0.0))
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.38
	ring.mesh = torus
	ring.material_override = _mat(&"gold")
	ring.position.y = 1.75
	ring.rotation.x = PI * 0.5
	_bell.add_child(ring)
	for k in CHORUS_ROUNDS:
		var lamp_mat := _glow(PALE, 0.12)
		var lamp := _sphere(0.08, lamp_mat)
		lamp.position = Vector3(-0.25 + 0.25 * float(k), 1.17, 0.0)
		_bell.add_child(lamp)
		_lamps.append(lamp_mat)
	_usable_add(_bell, "E   Listen", _listen, 2.2, func() -> bool: return not _playing)
	_vault_at = Vector3(0.0, 0.0, -6.2)
	_seq = _new_sequence(3)


func _flare(i: int, strength := 1.0) -> void:
	var s: Dictionary = _stones[i]
	var old = s["tween"]
	if old != null and (old as Tween).is_valid():
		(old as Tween).kill()
	var mat: StandardMaterial3D = s["mat"]
	mat.emission_energy_multiplier = 4.5 * strength
	var t := create_tween()
	t.tween_property(mat, "emission_energy_multiplier", STONE_DIM, 0.55)
	s["tween"] = t


func _listen() -> void:
	if _playing or solved:
		return
	_input = 0
	_play_sequence()


func _autoplay(delay: float) -> void:
	_play_token += 1
	var token := _play_token
	await _wait(delay)
	if token != _play_token or solved or not sealed:
		return
	_play_sequence()


func _play_sequence() -> void:
	_play_token += 1
	var token := _play_token
	_playing = true
	_input = 0
	await _wait(0.4)
	for n in _seq:
		if token != _play_token:
			return
		_flare(n)
		await _wait(NOTE_TIME)
	if token == _play_token:
		_playing = false


func _strike_stone(i: int) -> void:
	if _playing or solved or _seq.is_empty():
		return
	_flare(i)
	if i != _seq[_input]:
		_chorus_wrong()
		return
	_input += 1
	if _input < _seq.size():
		return
	# The round is sung back.
	_input = 0
	_lamps[_round].emission = GOLD
	_lamps[_round].emission_energy_multiplier = 3.0
	_round += 1
	_shake(0.1)
	for k in _stones.size():
		get_tree().create_timer(0.35 + 0.08 * float(k)).timeout.connect(_flare.bind(k, 0.7))
	if _round >= CHORUS_ROUNDS:
		_solve()
		return
	_seq = _new_sequence(3 + _round)
	_autoplay(1.8)


func _chorus_wrong() -> void:
	_input = 0
	for k in _stones.size():
		var mat: StandardMaterial3D = _stones[k]["mat"]
		var t := create_tween()
		t.tween_property(mat, "emission_energy_multiplier", 0.0, 0.08)
		t.tween_interval(0.5)
		t.tween_property(mat, "emission_energy_multiplier", STONE_DIM, 0.6)
	if _player.has_method("drain_health"):
		_player.call("drain_health", WRONG_NOTE, float(_player.get("max_health")) * 0.25)
	_shake(0.28)
	var hud := _hud()
	if hud != null and hud.has_method("_show_toast"):
		hud.call("_show_toast", "A wrong note. The stones sing it again.", 1.8)
	_autoplay(1.6)


func _tick_chorus(delta: float) -> void:
	var ring := _bell.get_node_or_null(^"Ring") as Node3D
	if ring != null:
		ring.rotation.z += delta * 0.7
		ring.position.y = 1.75 + sin(_time * 1.4) * 0.05


func _reset_chorus() -> void:
	_play_token += 1
	_playing = false
	_input = 0
	_round = 0
	_seq = _new_sequence(3)
	for m in _lamps:
		m.emission = PALE
		m.emission_energy_multiplier = 0.12
	for s in _stones:
		(s["mat"] as StandardMaterial3D).emission_energy_multiplier = STONE_DIM


# --- THE VEIL -------------------------------------------------------------------------

## The glyphs: 0 ring, 1 triangle, 2 square, 3 cross.
const GLYPHS := 4

var _dials: Array[Dictionary] = []
var _ghost_mat: StandardMaterial3D
var _ghost := 0.0


func _build_veil() -> void:
	# What only a ghost sees: pale, unshaded, faded by ghost mode. Ghost mode
	# drains the colour from the view, which is why this puzzle is shapes and
	# not colours.
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.albedo_color = Color(0.92, 0.96, 1.0, 0.0)
	var carve := _glow(PALE, 0.45)
	var mark := _glow(GOLD, 1.2)
	carve.cull_mode = BaseMaterial3D.CULL_DISABLED
	mark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var targets: Array[int] = []
	var start: Array[int] = []
	for i in 4:
		targets.append(_rng.randi_range(0, GLYPHS - 1))
	while true:
		start.clear()
		var wrong := 0
		for i in 4:
			start.append(_rng.randi_range(0, GLYPHS - 1))
			if start[i] != targets[i]:
				wrong += 1
		if wrong >= 3:
			break
	for i in 4:
		var at := Vector3(-3.3 + 2.2 * float(i), 0.0, 1.2)
		var base := Node3D.new()
		base.name = "Dial%d" % i
		base.position = at
		add_child(base)
		_box(base, Vector3(1.15, 0.25, 1.15), Vector3(0.0, 0.125, 0.0), _stone)
		_solid(base, Vector3(1.15, 1.25, 1.15), Vector3(0.0, 0.625, 0.0))
		# Its number, in notches on the front of the base: I to IIII.
		for k in i + 1:
			_box(base, Vector3(0.05, 0.15, 0.02), Vector3((float(k) - float(i) * 0.5) * 0.11, 0.125, 0.58), mark)
		var drum := Node3D.new()
		drum.position = Vector3(0.0, 0.25, 0.0)
		base.add_child(drum)
		_box(drum, Vector3(0.9, 0.95, 0.9), Vector3(0.0, 0.475, 0.0), _stone)
		_box(drum, Vector3(0.98, 0.08, 0.98), Vector3(0.0, 0.95, 0.0), _mat(&"iron"))
		for g in GLYPHS:
			var side := Node3D.new()
			side.rotation.y = float(g) * PI * 0.5
			drum.add_child(side)
			var glyph := _glyph(g, carve)
			glyph.position = Vector3(0.0, 0.5, 0.456)
			side.add_child(glyph)
		# The pointer: the face toward it is the one that counts.
		var pointer := MeshInstance3D.new()
		pointer.mesh = _triangle_mesh(0.13, 0.02)
		pointer.material_override = mark
		# Lying flat, its point toward the dial.
		pointer.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		pointer.position = Vector3(0.0, 0.015, 0.8)
		base.add_child(pointer)
		drum.rotation.y = -float(start[i]) * PI * 0.5
		_dials.append({"drum": drum, "turns": start[i], "start": start[i], "target": targets[i], "busy": false})
		_usable_add(base, "E   Turn", _turn_dial.bind(i), 2.4)
	# The stelae in the corners, each naming one dial and the glyph it wants.
	var corners: Array[Vector3] = [Vector3(-7.3, 0.0, -7.3), Vector3(7.3, 0.0, -7.3),
		Vector3(-7.3, 0.0, 7.3), Vector3(7.3, 0.0, 7.3)]
	var order: Array[int] = [0, 1, 2, 3]
	for i in range(3, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in 4:
		var at := corners[order[i]]
		var node := Node3D.new()
		node.name = "Stela%d" % i
		node.position = at
		node.rotation.y = atan2(-at.x, -at.z)
		add_child(node)
		_box(node, Vector3(1.4, 2.8, 0.35), Vector3(0.0, 1.4, 0.0), _stone)
		_box(node, Vector3(1.55, 0.14, 0.45), Vector3(0.0, 2.84, 0.0), _stone)
		_solid(node, Vector3(1.4, 2.9, 0.35), Vector3(0.0, 1.45, 0.0))
		var writing := Node3D.new()
		writing.position = Vector3(0.0, 0.0, 0.19)
		node.add_child(writing)
		for k in i + 1:
			_box(writing, Vector3(0.07, 0.34, 0.01), Vector3((float(k) - float(i) * 0.5) * 0.15, 2.3, 0.0), _ghost_mat)
		var g := _glyph(targets[i], _ghost_mat)
		g.scale = Vector3(2.2, 2.2, 1.0)
		g.position = Vector3(0.0, 1.35, 0.0)
		writing.add_child(g)
	_vault_at = Vector3(0.0, 0.0, -5.3)


## A glyph, ~0.36 m across, flat in XY facing +Z.
func _glyph(g: int, mat: Material) -> Node3D:
	var root := Node3D.new()
	match g:
		0:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.12
			torus.outer_radius = 0.17
			torus.rings = 32
			ring.mesh = torus
			ring.material_override = mat
			ring.rotation.x = PI * 0.5
			ring.scale = Vector3(1.0, 0.3, 1.0)
			root.add_child(ring)
		1:
			# Built by hand: a CylinderMesh will not go below four sides, and a
			# "triangle" of four is a diamond -- the square glyph turned 45 deg.
			var tri := MeshInstance3D.new()
			tri.mesh = _triangle_mesh(0.22, 0.025)
			tri.material_override = mat
			tri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(tri)
		2:
			_box(root, Vector3(0.3, 0.3, 0.025), Vector3.ZERO, mat)
		_:
			_box(root, Vector3(0.38, 0.08, 0.025), Vector3.ZERO, mat)
			_box(root, Vector3(0.08, 0.38, 0.025), Vector3.ZERO, mat)
	return root


## An upright triangle `radius` from its middle to each corner, `depth` thick,
## flat in XY.
static func _triangle_mesh(radius: float, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := depth * 0.5
	var corners: Array[Vector2] = []
	for k in 3:
		var a := PI * 0.5 + TAU * float(k) / 3.0
		corners.append(Vector2(cos(a), sin(a)) * radius)
	for side: float in [1.0, -1.0]:
		var c: Array[Vector3] = []
		for k in 3:
			c.append(Vector3(corners[k].x, corners[k].y, hz * side))
		_face(st, c[0], c[1], c[2], Vector3(0.0, 0.0, side))
	for k in 3:
		var p := corners[k]
		var q := corners[(k + 1) % 3]
		var out := Vector3((p + q).x, (p + q).y, 0.0).normalized()
		var a := Vector3(p.x, p.y, hz)
		var b := Vector3(q.x, q.y, hz)
		var c2 := Vector3(q.x, q.y, -hz)
		var d := Vector3(p.x, p.y, -hz)
		_face(st, a, b, c2, out)
		_face(st, a, c2, d, out)
	return st.commit()


## One triangle facing `normal`, wound as Godot's front face (as morgue.gd `_tri`).
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(v)


func _turn_dial(i: int) -> void:
	var d: Dictionary = _dials[i]
	if d["busy"]:
		return
	d["busy"] = true
	d["turns"] = int(d["turns"]) + 1
	_shake(0.05)
	var t := create_tween()
	t.tween_property(d["drum"], "rotation:y", -float(d["turns"]) * PI * 0.5, 0.38) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		d["busy"] = false
		_check_veil())


func _check_veil() -> void:
	if solved or not sealed:
		return
	for d in _dials:
		if int(d["turns"]) % GLYPHS != int(d["target"]):
			return
	_solve()


func _tick_veil(delta: float) -> void:
	var ghost: bool = _player.has_method("is_dodging") and _player.call("is_dodging")
	_ghost = move_toward(_ghost, 1.0 if ghost else 0.0, delta * 3.0)
	_ghost_mat.albedo_color.a = _ghost * 0.9


func _reset_veil() -> void:
	for d in _dials:
		d["turns"] = d["start"]
		d["busy"] = false
		(d["drum"] as Node3D).rotation.y = -float(d["start"]) * PI * 0.5


# --- Helpers ---------------------------------------------------------------------------

func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")


func _shake(amount: float) -> void:
	if _player != null and is_instance_valid(_player):
		_player.set("_shake", maxf(float(_player.get("_shake")), amount))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Solid to everyone (1) and to sight (2).
func _solid(parent: Node3D, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	body.add_child(cs)
	return body


func _cyl(radius: float, height: float, segments: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = segments
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sphere(radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A crystal: an eight-faced gem `width` across and `height` tall.
func _octa(width: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = width * 0.5
	s.height = height
	s.radial_segments = 4
	s.rings = 2
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A thin bright line from `a` to `b` (local), drawn additive.
func _beam(a: Vector3, b: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var length := a.distance_to(b)
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = length
	cyl.radial_segments = 6
	cyl.rings = 1
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(col.lerp(Color.WHITE, 0.25), 0.85)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := (b - a).normalized()
	var side := up.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	mi.transform = Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5)
	add_child(mi)
	return mi


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.7)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.45
	return m


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"stone":
			# Plain grey stone, the grain from the normal map (as the morgue's
			# slabs). NOT the arch stone the level uses: that one is lit by the
			# baked colour of its MultiMesh instances, and on a plain mesh it
			# rendered black under any light -- the standing stones and
			# platforms were silhouettes. The faint emission stands in for an
			# ambient this level hardly has, so a face turned from every light
			# is still stone and not a hole.
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.normal_scale = 1.3
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.albedo_color = Color(0.21, 0.2, 0.195)
			m.roughness = 0.9
			m.emission_enabled = true
			m.emission = Color(0.03, 0.027, 0.027)
		&"gold":
			# Old gold, as in the morgue: bright gold read as neon under the red sky.
			m.albedo_color = Color(0.6, 0.44, 0.17)
			m.metallic = 0.6
			m.roughness = 0.42
		&"iron":
			m.albedo_color = Color(0.2, 0.2, 0.21)
			m.metallic = 0.5
			m.roughness = 0.55
		&"bronze":
			m.albedo_color = Color(0.42, 0.28, 0.14)
			m.metallic = 0.65
			m.roughness = 0.4
		&"wood":
			m.albedo_texture = load("res://textures/wood_door_albedo.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.2, 1.2, 1.2)
			m.albedo_color = Color(0.42, 0.34, 0.27)
			m.roughness = 0.9
		&"rope":
			m.albedo_color = Color(0.2, 0.16, 0.1)
			m.roughness = 1.0
		&"bone":
			m.albedo_color = Color(0.62, 0.58, 0.5)
			m.roughness = 0.9
		&"mirror":
			# Polished silver: it shows the red sky and the beam back.
			m.albedo_color = Color(0.82, 0.84, 0.88)
			m.metallic = 1.0
			m.roughness = 0.04
		&"dark":
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.albedo_color = Color(0.08, 0.075, 0.075)
			m.roughness = 0.9
	_mats[key] = m
	return m
