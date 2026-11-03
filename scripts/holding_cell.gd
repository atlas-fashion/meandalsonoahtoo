extends "res://scripts/jail_cell.gd"

## A jail cell out in the maze (note 153): a dead end shut by the prison's iron
## gate, holding two or three proels of different types. Each is a real enemy,
## `caged` as in a containment block (enemy.gd): blind, deaf and unhurt behind
## the bars. The gate swings open once every type inside has been let out of
## containment (maze.gd `_open_holding_cells`), so nothing still contained gets
## loose, and the prisoners go into the maze as loose subjects. Open or shut
## follows from `released_hands`, which is saved; a cell saves nothing itself.
##
## Dressed with the starting cell's straw and shackles (jail_cell.gd, whose frame
## this keeps: +Z towards the way out). Built before the navmesh bake with its
## blocker off, so the floor inside is on the mesh and the prisoners can walk out;
## `arm` makes the bars solid after it. maze.gd marks the cell's tiles WALL, so no
## patrol, spawn or wander goal lies behind the bars.

## The gate pair, as in the prison (dungeon_room.gd). It hangs in the arch that
## runs 2.4 to 3.6 m out of the dead end, on the cell's side of it.
const GATE_HALF := 1.64
const GATE_HEIGHT := 4.6
const GATE_Z := 2.5
## Outward, into the corridor: inward a leaf would swing through the dead end's
## corner pillars. Short of square, so it also clears the next cell's.
const OPEN_ANGLE := 1.5
const OPEN_TIME := 0.8
## The cell's torch: out by the gate, so it falls on the prisoners' fronts, and
## stronger than a corridor's, so the cell is a pool of light seen from outside.
## At the starting cell's z 0.5 and 0.6 of a torch they stood black against it.
const TORCH_Z := 1.25
const TORCH_SHARE := 3.0
## Where each prisoner stands, by how many there are. Far enough apart that no
## two capsules touch, off the bars and the walls, and clear of the middle line:
## the gate's solid lock plate hides anyone straight behind it.
## Prisoners, straw and shackles stop drawing here, past the fog. Each chain link
## is a default torus of 4,096 triangles: ten cells' worth, with nothing to cull
## them, were 500k more at every bench station, near or not.
const DRAWN_TO := 55.0
const SPOTS := {
	2: [Vector3(-1.1, 0.3, 0.2), Vector3(1.1, 0.3, 0.2)],
	3: [Vector3(-1.25, 0.3, 0.45), Vector3(1.25, 0.3, 0.2), Vector3(0.45, 0.3, -1.15)],
}

var maze: Node
var cell := Vector2i.ZERO
## What it holds: distinct types, as maze.gd `make_skeleton` takes them.
var hands: Array[StringName] = []
var is_open := false

var _hinges: Array[Node3D] = []
var _blocker: CollisionShape3D
var _prisoners: Array[Node3D] = []


## A cell in the dead end `at`, whose one way out is `out`. `torch_energy` 0 hangs
## no torch of its own.
static func place(parent: Node3D, built, at: Vector2i, out: Vector3, roster: Array[StringName],
		owner_maze: Node, torch_energy: float) -> Node3D:
	var node := Node3D.new()
	node.set_script(load("res://scripts/holding_cell.gd"))
	node.name = "HoldingCell%d_%d" % [at.x, at.y]
	parent.add_child(node)
	node.global_basis = Basis.looking_at(-out, Vector3.UP)
	node.global_position = built.to_world(at)
	node.set("maze", owner_maze)
	node.set("cell", at)
	node.set("hands", roster)
	node.call("_furnish", torch_energy, built)
	return node


func _furnish(torch_energy: float, built) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell)
	_strewn_straw(_mat(Color(0.29, 0.22, 0.1), 1.0), rng)
	var iron := _mat(Color(0.11, 0.1, 0.095), 0.6, 0.75)
	_shackles(Vector3(-0.62, 0.0, -FACE), iron, false)
	_shackles(Vector3(0.62, 0.0, -FACE), iron, true)
	_build_gate()
	_draw_to(self, DRAWN_TO)
	if torch_energy > 0.0:
		# As in the starting cell: a dead end with no torch of its own is black.
		var level = load("res://scripts/module_level.gd")
		level._hang_torch(self, load(level.TORCH_SCENE), Vector3(-FACE, built.height * level.TORCH_HEIGHT, TORCH_Z),
			Vector3.LEFT, torch_energy * TORCH_SHARE, level.TORCH_RANGE)


func _build_gate() -> void:
	var kit = load("res://scripts/brick_level.gd")
	for side: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "GateL" if side < 0.0 else "GateR"
		hinge.position = Vector3(side * GATE_HALF, 0.0, GATE_Z)
		add_child(hinge)
		var leaf := MeshInstance3D.new()
		leaf.mesh = kit.standalone("jail_gate_l" if side < 0.0 else "jail_gate_r")
		# No shadow, unlike the prison's: the bars cut the player's hand torch to
		# nothing, and from the corridor the prisoners stood black behind them.
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hinge.add_child(leaf)
		_hinges.append(hinge)
	# Bars do not stop sight: layer 1 only, as the prison's.
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(GATE_HALF * 2.0 + 0.1, GATE_HEIGHT, 0.15)
	_blocker = CollisionShape3D.new()
	_blocker.shape = box
	_blocker.position = Vector3(0.0, GATE_HEIGHT * 0.5, GATE_Z)
	_blocker.disabled = true
	body.add_child(_blocker)


## The navmesh is baked: the bars mean something now.
func arm() -> void:
	if not is_open:
		_blocker.disabled = false


func all_let_out() -> bool:
	var out: Array[StringName] = maze.get("released_hands")
	return hands.all(func(h: StringName) -> bool: return out.has(h))


## Puts its prisoners back, on the first population and after a death; a cell
## already opened stands open and empty.
func stock() -> void:
	_prisoners.clear()
	if all_let_out():
		swing_open(true)
	if is_open:
		return
	var spots: Array = SPOTS[hands.size()]
	for i in hands.size():
		var e: Node3D = maze.call("make_skeleton", hands[i])
		if e == null:
			continue
		e.set("caged", true)
		e.set("wanders", false)
		e.position = maze.call("to_local", to_global(spots[i]))
		# Facing the bars (an enemy's forward is -Z, the cell's way out +Z), each
		# a little its own way.
		e.rotation.y = global_rotation.y + PI + (float(i) - 1.0) * 0.25
		maze.call("adopt_enemy", e)
		e.set("aggro_range", 0.5)
		_draw_to(e, DRAWN_TO)
		_prisoners.append(e)


## Leaves alone what has a limit of its own (a sword, a health bar).
static func _draw_to(node: Node3D, reach: float) -> void:
	for found in node.find_children("*", "GeometryInstance3D", true, false):
		var mesh := found as GeometryInstance3D
		if mesh.visibility_range_end == 0.0 or mesh.visibility_range_end == DRAWN_TO:
			mesh.visibility_range_end = reach


## The gate swings out and the prisoners are loose. `now`: already so, as a
## reload finds it.
func swing_open(now := false) -> void:
	if is_open:
		return
	is_open = true
	_blocker.set_deferred("disabled", true)
	for i in _hinges.size():
		# Left leaf (i 0) runs +X from its hinge: a negative turn takes it to +Z.
		var to := -OPEN_ANGLE if i == 0 else OPEN_ANGLE
		if now:
			_hinges[i].rotation.y = to
		else:
			create_tween().tween_property(_hinges[i], "rotation:y", to, OPEN_TIME) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not now:
		get_tree().create_timer(OPEN_TIME * 0.5).timeout.connect(_let_go)


func _let_go() -> void:
	if not is_inside_tree():
		return
	for e in _prisoners:
		if is_instance_valid(e):
			e.set("caged", false)
			_draw_to(e, 0.0)
			maze.call("turn_loose_subject", e)
	_prisoners.clear()
