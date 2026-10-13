extends Node3D

## A hiding place (2026-10-10; it was a stone sarcophagus with a skeleton in it):
## a hauling cart of the kind the convoys push (convoy.gd), left against a
## corridor wall -- a big wooden barrow with a wheel at one end, handles at the
## other and a plank LID on hinges along its back edge.
##
## Since 2026-10-12 a cart starts SHUT and has to be searched first: E ("Search")
## walks the player up and swings the lid open on whatever is inside -- usually
## nothing, sometimes a few coins or bone fragments, now and then a health
## potion, which rise out and fly to the player (`ItemDrop.give`). The lid then
## stays open, and only a searched cart can be hidden in: E ("Hide") lies the
## player down in the tray and lets the lid down onto its stop, `LID_SLIT`
## short of shut -- the slit along the front is the view out (there is no
## peeking any more). `player.hide_in()`, so nothing can see or hurt them and
## the Remnant (`stalker.gd`) loses them. E again climbs out, the lid left open.
## The lid is drawn on both faces: one-sided, its underside was invisible from
## inside, and a hidden player looked straight through it.
##
## Placed by `maze._place_hiding_spots` before the navmesh bake. Local +X runs
## along the wall, +Z out into the corridor; the origin is on the floor at the
## middle of its footprint.

## The tray: inside length (along the wall), outside width, and the height of
## its rim; the tray's floor; plank thickness.
## Since 2026-10-10 the cart is the Tripo hand cart from the brick kit
## (brick_level "cart_body", "cart_wheels", "cart_lid"), exported at the
## convoy's size and drawn here CART_SCALE larger: tray 1.74 x 1.09 m, rim
## 1.3 m, two wheels under its middle reaching 0.82 m either side, the front
## board at -1.0 and the handles out to +1.6.
const CART_SCALE := 1.368
const LENGTH := 1.74
const WIDTH := 1.09
const HEIGHT := 1.3
const TRAY_FLOOR := 0.52
const BOARD := 0.05
const WHEEL_R := 0.51
## Where the base's collision starts (the front board), and the handles' end.
const AXLE_X := -0.49
const HANDLE_END := 1.6
## The kit cart's axle, in its own (convoy) frame: along +Z by this, this high.
const KIT_AXLE := Vector2(0.028, 0.375)
const REACH := 2.5
## The player stands this far out from its front to use it, and is put there
## on climbing out.
const STEP_OUT := 1.0
## The lid turns about its hinge (the back edge, along X): resting on its stop
## over a hidden player, the slit along the front open; and swung open (short
## of upright: the wall is only a hand's breadth behind).
const LID_SLIT := -0.08
const LID_OPEN := -1.42
const LID_TIME := 0.35
const LID_SEARCH_TIME := 0.7

## What a search finds: odds of each outcome (the rest is nothing), and how many.
const FIND_COINS := 0.19
const FIND_BONES := 0.19
const FIND_POTION := 0.15
const COINS_MIN := 3
const COINS_MAX := 7
const BONES_MIN := 1
const BONES_MAX := 3

enum State { SHUT, OPEN, OCCUPIED }

var state := State.SHUT
## Opened and looked in. Saved (maze "carts"); only a searched cart hides anyone.
var searched := false
## Set by the maze (kept for it; a cart has nobody in it).
var maze: Node = null
var skeleton_scene: PackedScene = null

var _prompt: Interact.Prompt
var _player: Node3D
var _near := false
var _busy := false
var _lid: Node3D


func _ready() -> void:
	_build()
	_prompt = Interact.prompt("E   Search", Vector3(0.0, HEIGHT, WIDTH * 0.5))
	add_child(_prompt)


## Where the player stands to use it and climbs out to, and which way they then
## face (out into the corridor).
func front_point() -> Vector3:
	return global_transform * Vector3(0.0, 0.05, WIDTH * 0.5 + STEP_OUT)


func facing_yaw() -> float:
	var out := global_basis.z
	return atan2(-out.x, -out.z)


## Searched and free to hide in.
func is_empty() -> bool:
	return searched


func is_occupied() -> bool:
	return state == State.OCCUPIED


## Old saves listed every cart under "coffins" (they were all usable); that list
## means nothing for searching, so it is ignored.
func restore_emptied() -> void:
	pass


## A save says this one was searched: open, nothing in it.
func restore_searched() -> void:
	searched = true
	state = State.OPEN
	_set_lid(LID_OPEN)


func _set_lid(angle: float) -> void:
	_lid.rotation.x = angle


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	if state == State.OCCUPIED and not _busy and _player.call("hidden_in") != self:
		# Taken out some other way (a respawn): left open, as they found it.
		state = State.OPEN
		_set_lid(LID_OPEN)
	var usable := state != State.OCCUPIED and not _busy
	if not usable:
		_near = false
		_prompt.visible = false
		return
	_prompt.text = "E   Hide" if state == State.OPEN else "E   Search"
	var to := _player.global_position - global_position
	var in_front := to.dot(global_basis.z) > 0.2
	_near = in_front and Vector2(to.x, to.z).length() <= REACH + WIDTH * 0.5 and absf(to.y) < 1.5 \
		and not _player.get("in_cutscene") and Interact.looked_at(self, 3.4, 0.08)
	_prompt.visible = _near


func _unhandled_input(event: InputEvent) -> void:
	if _busy or not Interact.pressed(event) or _player == null:
		return
	if state == State.OCCUPIED and _player.call("hidden_in") == self:
		get_viewport().set_input_as_handled()
		_climb_out()
	elif _near and state == State.SHUT:
		get_viewport().set_input_as_handled()
		_search()
	elif _near and state == State.OPEN:
		get_viewport().set_input_as_handled()
		_climb_in()


# --- Searching ------------------------------------------------------------------

func _search() -> void:
	_busy = true
	_near = false
	_prompt.visible = false
	_player.begin_cutscene(true)
	_player.scene_look_at(global_transform * Vector3(0.0, HEIGHT * 0.6, 0.0), 9.0)
	await _step_up()
	if not _still_alive():
		return
	# Into the tray as the lid comes up.
	_player.scene_look_at(global_transform * Vector3(0.0, TRAY_FLOOR, 0.1), 6.0)
	var t := create_tween()
	t.tween_method(_set_lid, _lid.rotation.x, LID_OPEN, LID_SEARCH_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	if not _still_alive():
		return
	searched = true
	state = State.OPEN
	await get_tree().create_timer(0.25).timeout
	_give(_roll())
	_player.end_cutscene()
	_busy = false


## [item id, how many], or [] for nothing.
static func _roll() -> Array:
	var r := randf()
	if r < FIND_POTION:
		return [&"health_potion", 1]
	r -= FIND_POTION
	if r < FIND_COINS:
		return [&"coins", randi_range(COINS_MIN, COINS_MAX)]
	r -= FIND_COINS
	if r < FIND_BONES:
		return [&"bone_fragment", randi_range(BONES_MIN, BONES_MAX)]
	return []


func _give(find: Array) -> void:
	if find.is_empty():
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("_show_toast"):
			hud.call("_show_toast", "Empty")
		return
	var id: StringName = find[0]
	var count: int = find[1]
	var inside := global_transform * Vector3(0.0, TRAY_FLOOR + 0.12, 0.0)
	var inventory = _player.get("inventory")
	var fits: int = mini(count, inventory.room_for(id)) if inventory != null else 0
	var item_drop = load("res://scripts/item_drop.gd")
	if fits > 0:
		item_drop.give(get_parent(), inside, id, fits)
	if count > fits:
		# No room: what is left pops out onto the floor, to be taken later.
		item_drop.spawn(get_parent(), global_transform * Vector3(0.0, HEIGHT + 0.2, WIDTH * 0.5 + 0.3), id, count - fits)


# --- Hiding ---------------------------------------------------------------------

## The eye, lying in the tray: just under the rim, in the middle of the tray,
## so the view out is the slit between the front board and the lid's edge.
const EYE := Vector3(0.0, HEIGHT - 0.04, 0.0)
var _body_at := Vector3.ZERO


func _climb_in() -> void:
	_busy = true
	_near = false
	_prompt.visible = false
	_player.begin_cutscene(true)
	_player.scene_look_at(global_transform * Vector3(0.0, HEIGHT * 0.6, 0.0), 9.0)
	await _step_up()
	if not _still_alive():
		return
	_player.end_cutscene()
	var head_height: float = _player.head.position.y if _player.get("head") != null else 1.6
	_body_at = global_transform * EYE - Vector3(0.0, head_height, 0.0)
	_player.hide_in(self, _body_at, facing_yaw())
	state = State.OCCUPIED
	var shut := create_tween()
	shut.tween_method(_set_lid, _lid.rotation.x, LID_SLIT, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await shut.finished
	_busy = false


func _climb_out() -> void:
	_busy = true
	var t := create_tween()
	t.tween_method(_set_lid, _lid.rotation.x, LID_OPEN, LID_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	_player.leave_hiding(front_point(), facing_yaw())
	state = State.OPEN
	_busy = false


## Walks the player to the front of it, if they are not there already.
func _step_up() -> void:
	var stand := front_point()
	stand.y = _player.global_position.y
	if Vector2(stand.x - _player.global_position.x, stand.z - _player.global_position.z).length() > 0.35:
		_player.scene_walk_to(stand, 1.5)
		await _player.scene_walk_finished


func _still_alive() -> bool:
	if is_instance_valid(_player) and not _player.get("_dead"):
		return true
	_busy = false
	state = State.OPEN if searched else State.SHUT
	_set_lid(LID_OPEN if searched else 0.0)
	if is_instance_valid(_player) and _player.in_cutscene:
		_player.end_cutscene()
	return false


# --- Build ----------------------------------------------------------------------

const CONVOY := preload("res://scripts/convoy.gd")

static var _body_mesh: ArrayMesh
static var _wheel_mesh: ArrayMesh
static var _lid_mesh: ArrayMesh


## Boxes and rods into one surface per material, as convoy.gd builds its cart.
static func _merged(fill: Callable) -> ArrayMesh:
	var tools := {}
	var add := func(mesh: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(mesh, 0, xf)
	fill.call(add)
	var am := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.generate_normals()
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	return am


static func _bx(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## The cart: a plank tray with sides leaning out a little and iron rails round
## its rim, two beams under it from the axle out to the handles, legs at the
## handle end, iron corner straps, and the axle.
static func _fill_body(add: Callable) -> void:
	var wood: Material = CONVOY._mat(&"wood")
	var iron: Material = CONVOY._mat(&"iron")
	var h := HEIGHT - TRAY_FLOOR
	add.call(_bx(Vector3(LENGTH, BOARD, WIDTH - 0.04)), Transform3D(Basis(), Vector3(0.0, TRAY_FLOOR, 0.0)), wood)
	for side: float in [-1.0, 1.0]:
		# Front and back boards, leaning out.
		add.call(_bx(Vector3(LENGTH + 0.08, h, BOARD)), Transform3D(Basis(Vector3.RIGHT, -0.1 * side),
			Vector3(0.0, TRAY_FLOOR + h * 0.5, side * (WIDTH * 0.5 - 0.02))), wood)
		# End boards.
		add.call(_bx(Vector3(BOARD, h, WIDTH)), Transform3D(Basis(Vector3.BACK, 0.08 * side),
			Vector3(side * (LENGTH * 0.5 + 0.02), TRAY_FLOOR + h * 0.5, 0.0)), wood)
		# The iron rails along the rim.
		add.call(_bx(Vector3(LENGTH + 0.14, 0.05, 0.06)), Transform3D(Basis(),
			Vector3(0.0, HEIGHT - 0.01, side * (WIDTH * 0.5 + 0.03))), iron)
		add.call(_bx(Vector3(0.06, 0.05, WIDTH + 0.1)), Transform3D(Basis(),
			Vector3(side * (LENGTH * 0.5 + 0.06), HEIGHT - 0.01, 0.0)), iron)
		# Beams under the tray, from the axle out past the handle end.
		var a := Vector3(AXLE_X, WHEEL_R, side * 0.34)
		var b := Vector3(HANDLE_END, 0.78, side * 0.34)
		add.call(CONVOY._rod(a, b, 0.045), CONVOY._rod_xf(a, b), wood)
		# Legs, at the handle end.
		add.call(_bx(Vector3(0.07, TRAY_FLOOR, 0.07)), Transform3D(Basis(),
			Vector3(LENGTH * 0.5 - 0.15, TRAY_FLOOR * 0.5, side * 0.36)), wood)
		# Corner straps.
		for sx: float in [-1.0, 1.0]:
			add.call(_bx(Vector3(0.12, h + 0.02, 0.02)), Transform3D(Basis(),
				Vector3(sx * (LENGTH * 0.5 - 0.04), TRAY_FLOOR + h * 0.5, side * (WIDTH * 0.5 + 0.02))), iron)
	# Hand grips on the handles' ends.
	for side: float in [-1.0, 1.0]:
		add.call(_bx(Vector3(0.2, 0.06, 0.06)), Transform3D(Basis(), Vector3(HANDLE_END - 0.08, 0.79, side * 0.34)),
			CONVOY._mat(&"rope"))
	var axle := CylinderMesh.new()
	axle.top_radius = 0.04
	axle.bottom_radius = 0.04
	axle.height = 0.8
	axle.radial_segments = 8
	axle.rings = 1
	add.call(axle, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(AXLE_X, WHEEL_R, 0.0)), iron)


## The wheel: a wooden disc in an iron tyre with iron spokes, about the Z axis.
static func _fill_wheel(add: Callable) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = WHEEL_R - 0.03
	disc.bottom_radius = WHEEL_R - 0.03
	disc.height = 0.08
	disc.radial_segments = 18
	disc.rings = 1
	add.call(disc, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), CONVOY._mat(&"wood"))
	var tyre := TorusMesh.new()
	tyre.inner_radius = WHEEL_R - 0.04
	tyre.outer_radius = WHEEL_R
	tyre.rings = 26
	tyre.ring_segments = 6
	add.call(tyre, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), CONVOY._mat(&"iron"))
	for k in 4:
		add.call(_bx(Vector3(0.05, WHEEL_R * 1.8, 0.1)), Transform3D(Basis(Vector3.BACK, PI * float(k) / 4.0),
			Vector3.ZERO), CONVOY._mat(&"iron"))


## The lid, built from its hinge (the origin) forward along +Z: five planks the
## length of the tray, three iron straps across them, and a hasp at the front.
static func _fill_lid(add: Callable) -> void:
	var wood: Material = CONVOY._mat(&"wood")
	var iron: Material = CONVOY._mat(&"iron")
	var deep := WIDTH + 0.1
	var planks := 5
	var gap := 0.008
	var each := deep / float(planks)
	for i in planks:
		add.call(_bx(Vector3(LENGTH + 0.16, BOARD, each - gap)), Transform3D(Basis(),
			Vector3(0.0, BOARD * 0.5, each * (float(i) + 0.5))), wood)
	for x: float in [-LENGTH * 0.36, 0.0, LENGTH * 0.36]:
		add.call(_bx(Vector3(0.07, 0.02, deep + 0.02)), Transform3D(Basis(), Vector3(x, BOARD + 0.01, deep * 0.5)), iron)
	add.call(_bx(Vector3(0.12, 0.14, 0.03)), Transform3D(Basis(), Vector3(0.0, -0.02, deep + 0.01)), iron)
	# The hinge pins along the back.
	for x: float in [-LENGTH * 0.36, LENGTH * 0.36]:
		var pin := CylinderMesh.new()
		pin.top_radius = 0.025
		pin.bottom_radius = 0.025
		pin.height = 0.16
		pin.radial_segments = 6
		pin.rings = 1
		add.call(pin, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, 0.0, 0.0)), iron)


func _build() -> void:
	var kit_body: Mesh = BRICK.standalone("cart_body")
	if kit_body != null:
		_build_kit(kit_body)
		_build_collision()
		return
	if _body_mesh == null:
		_body_mesh = _merged(_fill_body)
		_wheel_mesh = _merged(_fill_wheel)
		_lid_mesh = _merged(_fill_lid)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body_mesh
	add_child(body)
	var wheel := MeshInstance3D.new()
	wheel.name = "Wheel"
	wheel.mesh = _wheel_mesh
	wheel.position = Vector3(AXLE_X, WHEEL_R, 0.0)
	add_child(wheel)
	# The lid's hinge runs along the back rim.
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(0.0, HEIGHT + 0.015, -WIDTH * 0.5 - 0.05)
	add_child(_lid)
	var lid_mesh := MeshInstance3D.new()
	lid_mesh.mesh = _lid_mesh
	_lid.add_child(lid_mesh)
	_both_sides(lid_mesh)
	_build_collision()


const BRICK := preload("res://scripts/brick_level.gd")


## The Tripo cart: its length (the kit's +Z, handles at the back) turned onto
## +X, the lid's reach (the kit's +X from its hinge) onto +Z.
func _build_kit(kit_body: Mesh) -> void:
	var along := Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * CART_SCALE)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = kit_body
	body.transform = Transform3D(along, Vector3.ZERO)
	add_child(body)
	var wheels := MeshInstance3D.new()
	wheels.name = "Wheel"
	wheels.mesh = BRICK.standalone("cart_wheels")
	wheels.transform = Transform3D(along, Vector3(KIT_AXLE.x, KIT_AXLE.y, 0.0) * CART_SCALE)
	add_child(wheels)
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(0.0, HEIGHT + 0.005, -WIDTH * 0.5 - 0.05)
	add_child(_lid)
	var lid_mesh := MeshInstance3D.new()
	lid_mesh.mesh = BRICK.standalone("cart_lid")
	lid_mesh.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled(Vector3.ONE * CART_SCALE), Vector3.ZERO)
	_lid.add_child(lid_mesh)
	_both_sides(lid_mesh)


## Its own copies of the lid's materials, drawn from both sides: from inside the
## cart the boards are seen from below, and one-sided they were not drawn at all.
static var _two_sided := {}


func _both_sides(mi: MeshInstance3D) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
		if m == null:
			continue
		if not _two_sided.has(m):
			var copy := m.duplicate() as BaseMaterial3D
			copy.cull_mode = BaseMaterial3D.CULL_DISABLED
			_two_sided[m] = copy
		mi.set_surface_override_material(s, _two_sided[m])


func _build_collision() -> void:
	# Hollow: a solid base under the tray and four walls round it, so the player
	# can lie in it. On the sight layer as well (2), so it hides what lies behind.
	var walls := StaticBody3D.new()
	walls.collision_layer = 1 | 2
	walls.collision_mask = 0
	add_child(walls)
	var h := HEIGHT - TRAY_FLOOR
	var total := HANDLE_END - (AXLE_X - WHEEL_R)
	var parts := [
		[Vector3(total, TRAY_FLOOR + BOARD * 0.5, WIDTH), Vector3((HANDLE_END + AXLE_X - WHEEL_R) * 0.5, (TRAY_FLOOR + BOARD * 0.5) * 0.5, 0.0)],
		[Vector3(LENGTH + 0.1, h, 0.1), Vector3(0.0, TRAY_FLOOR + h * 0.5, WIDTH * 0.5 - 0.03)],
		[Vector3(LENGTH + 0.1, h, 0.1), Vector3(0.0, TRAY_FLOOR + h * 0.5, -WIDTH * 0.5 + 0.03)],
		[Vector3(0.1, h, WIDTH), Vector3(LENGTH * 0.5 + 0.02, TRAY_FLOOR + h * 0.5, 0.0)],
		[Vector3(0.1, h, WIDTH), Vector3(-LENGTH * 0.5 - 0.02, TRAY_FLOOR + h * 0.5, 0.0)],
	]
	for part in parts:
		var shape := BoxShape3D.new()
		shape.size = part[0]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = part[1]
		walls.add_child(cs)
	# The lid carries its own collision, so it swings with it.
	var lid_body := StaticBody3D.new()
	lid_body.collision_layer = 1 | 2
	lid_body.collision_mask = 0
	_lid.add_child(lid_body)
	var lid_shape := BoxShape3D.new()
	lid_shape.size = Vector3(LENGTH + 0.16, BOARD, WIDTH + 0.1)
	var lcs := CollisionShape3D.new()
	lcs.shape = lid_shape
	lcs.position = Vector3(0.0, BOARD * 0.5, (WIDTH + 0.1) * 0.5)
	lid_body.add_child(lcs)
	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
