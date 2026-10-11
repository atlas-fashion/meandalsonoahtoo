extends Node3D

## The great door at the top of the boss stair (2026-10-08): two leaves of dark
## stone and old gold, 8 m square, filling the arch into the throne hall. On its
## face a gold medallion holds one socket per puzzle room, each ringed in the
## colour of that room's shard. E with the crosshair on it sets every shard the
## player carries -- each flies from the hand into its socket and lights -- and
## when the last is in, the shards blaze, the seal burns away, and the leaves
## swing into the hall.
##
## Built by maze.gd after the boss hall, in the hall's arch, on its HALL side
## (the portcullis hangs in the middle of the same arch, so the opened leaves lie
## inside the hall past it). Shards set stay set through death; an opened door
## stays open.

const WoodDoor := preload("res://scripts/wood_door.gd")

const LEAF_THICK := 0.45
const MEDALLION_Y := 3.3
const SOCKET_RING := 1.3
## Horizontal reach in front of the door's face.
const REACH := 3.6

var shards: Array[StringName] = []
var filled: Array[bool] = []
var opened := false

var _width := 8.0
var _height := 8.0
var _busy := false
var _near := false
var _player: Node3D
var _prompt: Interact.Prompt
var _leaves: Array[Node3D] = []
var _sockets: Array[Dictionary] = []
var _seal: Node3D
var _blocker: StaticBody3D
var _seam_mat: StandardMaterial3D
var _light: OmniLight3D
var _bars: CanvasLayer

static var _mats := {}


## `gate` is the boss hall's portcullis transform (local Z through the arch,
## origin on the floor in the middle of the arch), `size` its width and height,
## `wall` the arch's depth.
static func build(parent: Node3D, gate: Transform3D, size: Vector2, wall: float,
		shards_: Array[StringName]) -> Node3D:
	var d := Node3D.new()
	d.set_script(load("res://scripts/shard_door.gd"))
	d.name = "ShardDoor"
	parent.add_child(d)
	d.global_transform = gate.translated_local(Vector3(0.0, 0.0, wall * 0.5))
	d.call("_dress", size, shards_)
	return d


func _dress(size: Vector2, shards_: Array[StringName]) -> void:
	_width = size.x
	_height = size.y
	shards = shards_
	filled.clear()
	for s in shards:
		filled.append(false)
	_prompt = Interact.prompt("E   Set shards", Vector3(0.0, MEDALLION_Y, -LEAF_THICK))
	add_child(_prompt)

	# The leaves, hinged at the jambs on the hall side, closed across the arch.
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.name = "Leaf" + ("L" if side < 0.0 else "R")
		pivot.position = Vector3(side * _width * 0.5, 0.0, 0.0)
		add_child(pivot)
		_leaf(pivot, -side)
		_leaves.append(pivot)

	# The seal on the face: medallion, sockets, and the seam's glow.
	_seal = Node3D.new()
	_seal.name = "Seal"
	# Proud of the raised panels (which stand 5 cm off the leaves), or the
	# sockets sink into them.
	_seal.position = Vector3(0.0, 0.0, -LEAF_THICK - 0.08)
	add_child(_seal)
	var medallion := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.8
	torus.outer_radius = 2.0
	torus.rings = 64
	medallion.mesh = torus
	medallion.material_override = _mat(&"gold")
	medallion.rotation.x = PI * 0.5
	medallion.scale = Vector3(1.0, 0.5, 1.0)
	medallion.position.y = MEDALLION_Y
	_seal.add_child(medallion)
	var boss := _cyl(0.42, 0.08, 32, _mat(&"gold"))
	boss.position = Vector3(0.0, MEDALLION_Y, -0.02)
	_seal.add_child(boss)
	for k in shards.size():
		var a := PI * 0.5 + TAU * float(k) / float(shards.size())
		var at := Vector3(cos(a) * SOCKET_RING, MEDALLION_Y + sin(a) * SOCKET_RING, 0.0)
		var col := Inventory.item_color(shards[k])
		var ring := MeshInstance3D.new()
		var rt := TorusMesh.new()
		rt.inner_radius = 0.2
		rt.outer_radius = 0.27
		ring.mesh = rt
		var ring_mat := _glow(col, 0.5)
		ring.material_override = ring_mat
		ring.rotation.x = PI * 0.5
		ring.position = at
		_seal.add_child(ring)
		var hole := _cyl(0.2, 0.04, 20, _mat(&"dark"))
		hole.position = at + Vector3(0.0, 0.0, 0.01)
		_seal.add_child(hole)
		var gem_mat := _glow(col, 3.0)
		var gem := _octa(0.17, 0.42, gem_mat)
		gem.position = at + Vector3(0.0, 0.0, -0.06)
		gem.visible = false
		_seal.add_child(gem)
		_sockets.append({"gem": gem, "mat": gem_mat, "ring": ring_mat, "at": at})
	_seam_mat = _glow(Color(1.0, 0.85, 0.6), 0.0)
	var seam := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.05, _height - 0.1, 0.02)
	seam.mesh = sb
	seam.material_override = _seam_mat
	seam.position = Vector3(0.0, _height * 0.5, 0.0)
	_seal.add_child(seam)

	_light = OmniLight3D.new()
	_light.light_energy = 0.0
	_light.omni_range = 7.0
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 40.0
	_light.distance_fade_length = 10.0
	_light.position = Vector3(0.0, MEDALLION_Y, -LEAF_THICK - 1.4)
	add_child(_light)

	# Shut: solid to everyone (1) and to sight (2).
	_blocker = StaticBody3D.new()
	_blocker.name = "Blocker"
	_blocker.collision_layer = 1 | 2
	_blocker.collision_mask = 0
	add_child(_blocker)
	var shape := BoxShape3D.new()
	shape.size = Vector3(_width, _height, LEAF_THICK)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, _height * 0.5, -LEAF_THICK * 0.5)
	_blocker.add_child(cs)
	print("[shard door] %d sockets, %.0f x %.0f m" % [shards.size(), _width, _height])


## One leaf, drawn from its hinge toward the middle (`dir` is +1 or -1 along X).
func _leaf(pivot: Node3D, dir: float) -> void:
	var w := _width * 0.5 - 0.01
	var h := _height
	var t := LEAF_THICK
	var face := -t - 0.025
	_box(pivot, Vector3(w, h, t), Vector3(dir * w * 0.5, h * 0.5, -t * 0.5), _mat(&"stone"))
	# Raised panels, lighter stone, two up each leaf.
	for panel: Vector2 in [Vector2(0.55, 2.4), Vector2(4.9, 2.6)]:
		_box(pivot, Vector3(w - 0.9, panel.y, 0.06), Vector3(dir * w * 0.5, panel.x + panel.y * 0.5, face + 0.005),
			_mat(&"panel"))
	var gold := _mat(&"gold")
	# A gold frame: top, bottom, the hinge edge and the meeting edge.
	_box(pivot, Vector3(w, 0.14, 0.06), Vector3(dir * w * 0.5, h - 0.07, face), gold)
	_box(pivot, Vector3(w, 0.14, 0.06), Vector3(dir * w * 0.5, 0.07, face), gold)
	_box(pivot, Vector3(0.14, h, 0.06), Vector3(dir * 0.07, h * 0.5, face), gold)
	_box(pivot, Vector3(0.1, h, 0.06), Vector3(dir * (w - 0.05), h * 0.5, face), gold)
	# Bands across, and a row of studs along each.
	for y: float in [3.15, 7.65]:
		_box(pivot, Vector3(w, 0.1, 0.05), Vector3(dir * w * 0.5, y, face), gold)
	for y: float in [0.3, 7.75]:
		for k in 6:
			var stud := _sphere(0.06, gold)
			stud.position = Vector3(dir * (0.45 + float(k) * (w - 0.9) / 5.0), y + 0.12, face - 0.02)
			pivot.add_child(stud)
	# A great iron ring to haul on, low on each leaf beside the meeting edge.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.26
	ring.mesh = torus
	ring.material_override = _mat(&"iron")
	ring.rotation.x = PI * 0.5
	ring.position = Vector3(dir * (w - 0.6), 1.25, face - 0.04)
	pivot.add_child(ring)


# --- Using it ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if opened or _busy:
		_near = false
		_prompt.visible = false
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var p := to_local(_player.global_position)
	_near = p.z < -LEAF_THICK and -p.z - LEAF_THICK <= REACH and absf(p.x) < _width * 0.5 + 0.3 \
		and p.y > -1.2 and p.y < 2.0 and _player.get("in_cutscene") != true and _player.get("_dead") != true \
		and Interact.looked_at(self, REACH + 3.0, 0.1)
	_prompt.visible = _near


func _unhandled_input(event: InputEvent) -> void:
	if not _near or _busy or opened or not Interact.pressed(event):
		return
	get_viewport().set_input_as_handled()
	_use()


func set_count() -> int:
	var n := 0
	for f in filled:
		if f:
			n += 1
	return n


func _use() -> void:
	var inv = _player.get("inventory")
	var to_set: Array[int] = []
	if inv != null:
		var spare := {}
		for k in shards.size():
			if filled[k]:
				continue
			var id := shards[k]
			if not spare.has(id):
				spare[id] = int(inv.count(id))
			if int(spare[id]) > 0:
				spare[id] = int(spare[id]) - 1
				to_set.append(k)
	if to_set.is_empty():
		_toast("The door is sealed: %d of %d shards set. The rest lie in the puzzle rooms."
			% [set_count(), shards.size()], 2.6)
		return
	# Out of the pack at once, so dying part way through cannot lose or copy one.
	for k in to_set:
		inv.remove(shards[k], 1)
	_set_shards(to_set)


func _set_shards(to_set: Array[int]) -> void:
	_busy = true
	var player := _player
	player.call("begin_cutscene", false)
	player.set("hands_busy", true)
	var centre := to_global(Vector3(0.0, MEDALLION_Y, -LEAF_THICK))
	player.call("scene_look_at", centre, 4.0)
	player.call("scene_frame", 6.0, 0.0, 2.5)
	await _wait(0.45)
	for k in to_set:
		await _fly_shard(k, player)
		filled[k] = true
		var s: Dictionary = _sockets[k]
		(s["gem"] as Node3D).visible = true
		var mat: StandardMaterial3D = s["mat"]
		mat.emission_energy_multiplier = 9.0
		create_tween().tween_property(mat, "emission_energy_multiplier", 3.0, 0.5)
		(s["ring"] as StandardMaterial3D).emission_energy_multiplier = 2.2
		_seam_mat.emission_energy_multiplier = 0.4 * float(set_count())
		_light.light_color = Inventory.item_color(shards[k])
		_light.light_energy = 0.5 + 0.35 * float(set_count())
		player.set("_shake", maxf(float(player.get("_shake")), 0.1))
		_toast("%s set   %d / %d" % [Inventory.item_name(shards[k]), set_count(), shards.size()], 1.4)
		await _wait(0.25)
	if set_count() >= shards.size():
		await _open(player)
	else:
		player.set("hands_busy", false)
		player.call("end_cutscene")
		_busy = false


## A shard flies from just in front of the player's view into its socket.
func _fly_shard(k: int, player: Node3D) -> void:
	var s: Dictionary = _sockets[k]
	var to: Vector3 = _seal.to_global(s["at"] + Vector3(0.0, 0.0, -0.06))
	var camera := get_viewport().get_camera_3d()
	var from := player.global_position + Vector3(0.0, 1.3, 0.0)
	if camera != null:
		from = camera.global_position - camera.global_basis.z * 0.7 - camera.global_basis.y * 0.25
	var gem := _octa(0.17, 0.42, s["mat"])
	gem.top_level = true
	add_child(gem)
	gem.global_position = from
	var lift := (from + to) * 0.5 + Vector3(0.0, 0.8, 0.0)
	var time := 0.55
	var t := 0.0
	while t < time:
		await get_tree().process_frame
		t += get_process_delta_time()
		var u := clampf(t / time, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		var a := from.lerp(lift, e)
		var b := lift.lerp(to, e)
		gem.global_position = a.lerp(b, e)
		gem.rotation.y += 0.3
	gem.queue_free()


func _open(player: Node3D) -> void:
	_bars = WoodDoor.letterbox(self)
	player.call("scene_frame", 10.0, 0.0, 1.5)
	# Every shard blazes; the light runs down the seam.
	var blaze := create_tween().set_parallel(true)
	for s in _sockets:
		blaze.tween_property(s["mat"], "emission_energy_multiplier", 14.0, 1.2)
	blaze.tween_property(_seam_mat, "emission_energy_multiplier", 9.0, 1.2)
	blaze.tween_property(_light, "light_energy", 6.0, 1.2)
	blaze.tween_property(_light, "light_color", Color(1.0, 0.9, 0.75), 1.2)
	for i in 12:
		player.set("_shake", maxf(float(player.get("_shake")), 0.05 + 0.02 * float(i)))
		await _wait(0.1)
	# The seal burns away.
	var hud := get_tree().get_first_node_in_group("hud")
	_seal.visible = false
	_blocker.queue_free()
	_blocker = null
	player.set("_shake", 0.6)
	player.call("scene_frame", 3.0, 0.0, 2.0)
	# And the leaves swing into the hall.
	var swing := create_tween().set_parallel(true)
	swing.tween_property(_leaves[0], "rotation:y", -PI * 0.5 * 0.97, 4.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	swing.tween_property(_leaves[1], "rotation:y", PI * 0.5 * 0.97, 4.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	swing.tween_property(_light, "light_energy", 0.0, 4.0)
	for i in 20:
		player.set("_shake", maxf(float(player.get("_shake")), 0.18))
		await _wait(0.2)
	_open_collision()
	opened = true
	if _bars != null and is_instance_valid(_bars):
		WoodDoor.letterbox_out(_bars)
		_bars = null
	if hud != null and hud.has_method("announce"):
		hud.announce("THE WAY IS OPEN", "Something waits on the throne.")
	player.call("scene_look_at", null)
	player.set("hands_busy", false)
	player.call("end_cutscene")
	_busy = false


## The opened leaves stand along the sides of the arch, inside the hall.
func _open_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "OpenLeaves"
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	add_child(body)
	for side: float in [-1.0, 1.0]:
		var shape := BoxShape3D.new()
		shape.size = Vector3(LEAF_THICK, _height, _width * 0.5)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(side * (_width * 0.5 - LEAF_THICK * 0.5), _height * 0.5, _width * 0.25)
		body.add_child(cs)


## --- Saving (save_system.gd, via maze.gd) -----------------------------------------

func save_state() -> Dictionary:
	return {"filled": filled.duplicate(), "opened": opened}


## A loaded game: the shards as they were set, and the door open if it was --
## at once, without its scene.
func restore_state(data: Dictionary) -> void:
	var was: Array = data.get("filled", [])
	for k in mini(was.size(), filled.size()):
		filled[k] = bool(was[k])
		(_sockets[k]["gem"] as Node3D).visible = filled[k]
		if filled[k]:
			(_sockets[k]["ring"] as StandardMaterial3D).emission_energy_multiplier = 2.2
	_seam_mat.emission_energy_multiplier = 0.4 * float(set_count())
	_light.light_energy = 0.0 if set_count() == 0 else 0.5 + 0.35 * float(set_count())
	if bool(data.get("opened", false)) and not opened:
		opened = true
		_seal.visible = false
		_light.light_energy = 0.0
		if _blocker != null:
			_blocker.queue_free()
			_blocker = null
		_leaves[0].rotation.y = -PI * 0.5 * 0.97
		_leaves[1].rotation.y = PI * 0.5 * 0.97
		_open_collision()


## For a harness or a debug key: every socket filled, the door left shut.
func fill_all() -> void:
	for k in shards.size():
		filled[k] = true
		(_sockets[k]["gem"] as Node3D).visible = true


# --- Helpers ---------------------------------------------------------------------------

func _toast(text: String, hold: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("_show_toast"):
		hud.call("_show_toast", text, hold)


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
	mi.rotation.x = PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _sphere(radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 5
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


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


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.7)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.35
	return m


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"stone", &"panel", &"dark":
			# Normal map only: the plain stone's colour map averages 30/255 and
			# rendered solid black under any tint (see morgue.gd).
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.6, 0.6, 0.6)
			m.roughness = 0.5
			m.metallic = 0.1
			m.albedo_color = {&"stone": Color(0.1, 0.1, 0.115), &"panel": Color(0.15, 0.145, 0.15),
				&"dark": Color(0.03, 0.03, 0.035)}[key]
		&"gold":
			m.albedo_color = Color(0.6, 0.44, 0.17)
			m.metallic = 0.6
			m.roughness = 0.42
		&"iron":
			m.albedo_color = Color(0.2, 0.2, 0.21)
			m.metallic = 0.5
			m.roughness = 0.55
	_mats[key] = m
	return m
