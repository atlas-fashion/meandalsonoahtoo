extends "res://scripts/jail_cell.gd"

## A jail cell out in the maze (note 153, reworked in note 154): a dead end shut by
## the prison's iron gate, holding two or three proels of different types and a
## respawn beacon (respawn_anchor.gd) at the back. Each prisoner is a real enemy,
## `caged` as in a containment block (enemy.gd): blind, deaf and unhurt behind the
## bars. The player opens the gate with E whenever they like (note 154; it used to
## wait for every type inside to be let out of containment), and the prisoners go
## into the maze as loose subjects -- between the player and the beacon. An opened
## cell stays open and empty, through deaths and in the save (maze.gd
## `save_state` "cells_open"), since the player may rise at its beacon.
##
## The player's starting cell is one too (`start`): the starting cell's bed, bucket
## and remains, the same gate and a beacon, and nobody else inside.
##
## Dressed with the starting cell's straw and shackles (jail_cell.gd, whose frame
## this keeps: +Z towards the way out). Built before the navmesh bake with its
## blocker off, so the floor inside is on the mesh and the prisoners can walk out;
## `arm` makes the bars solid after it. maze.gd marks a maze cell's tiles WALL, so
## no patrol, spawn or wander goal lies behind the bars.

signal opened(cell: Node3D)

## The gate pair, as in the prison (dungeon_room.gd). It hangs in the arch that
## runs 2.4 to 3.6 m out of the dead end, on the cell's side of it.
const GATE_HALF := 1.64
const GATE_HEIGHT := 4.6
const GATE_Z := 2.5
## Outward, into the corridor: inward a leaf would swing through the dead end's
## corner pillars. Short of square, so it also clears the next cell's.
const OPEN_ANGLE := 1.5
const OPEN_TIME := 0.8
## E opens it from this near the gate's middle, either side of it.
const GATE_REACH := 3.0
## The cell's torch: out by the gate, so it falls on the prisoners' fronts, and
## stronger than a corridor's, so the cell is a pool of light seen from outside.
## At the starting cell's z 0.5 and 0.6 of a torch they stood black against it.
const TORCH_Z := 1.25
const TORCH_SHARE := 3.0
## The beacon stands this far back from the middle (the anchors' brick figure).
const BEACON_BACK := 1.1
## Prisoners, straw and shackles stop drawing here, past the fog. Each chain link
## is a default torus of 4,096 triangles: ten cells' worth, with nothing to cull
## them, were 500k more at every bench station, near or not.
const DRAWN_TO := 55.0
## Where each prisoner stands, by how many there are. Far enough apart that no
## two capsules touch, off the bars, the walls and the beacon's plinth (x 0.65,
## z -1.75 to -0.45), and clear of the middle line: the gate's solid lock plate
## hides anyone straight behind it.
const SPOTS := {
	2: [Vector3(-1.1, 0.3, 0.2), Vector3(1.1, 0.3, 0.2)],
	3: [Vector3(-1.25, 0.3, 0.45), Vector3(1.25, 0.3, 0.2), Vector3(0.5, 0.3, 1.45)],
}

var maze: Node
var cell := Vector2i.ZERO
## What it holds: distinct types, as maze.gd `make_skeleton` takes them.
var hands: Array[StringName] = []
var is_open := false
## The player's starting cell: no prisoners, the full starting-cell dressing.
var start := false
## A wall torch on a pilaster in the middle of the left (-1) or right (1) wall,
## or none (0): the prisoner on that side stands clear of it, and the cell's own
## torch goes on the other wall.
var pilaster := 0
## Its respawn beacon (respawn_anchor.gd), set by maze.gd.
var beacon: Node3D

var _gate: Node3D
var _hinges: Array[Node3D] = []
var _blocker: CollisionShape3D
var _prisoners: Array[Node3D] = []
var _prompt: Interact.Prompt
var _user: Node3D
var _near := false


## A cell in the dead end `at`, whose one way out is `out`. `torch_energy` 0 hangs
## no torch of its own.
static func place(parent: Node3D, built, at: Vector2i, out: Vector3, roster: Array[StringName],
		owner_maze: Node, torch_energy: float, is_start := false, wall_torch := 0) -> Node3D:
	fit_kit()
	var node := Node3D.new()
	node.set_script(load("res://scripts/holding_cell.gd"))
	node.name = "StartCell" if is_start else "HoldingCell%d_%d" % [at.x, at.y]
	parent.add_child(node)
	node.global_basis = Basis.looking_at(-out, Vector3.UP)
	node.global_position = built.to_world(at)
	node.set("maze", owner_maze)
	node.set("cell", at)
	node.set("hands", roster)
	node.set("start", is_start)
	node.set("pilaster", wall_torch)
	node.call("_furnish", torch_energy, built)
	return node


func _furnish(torch_energy: float, built) -> void:
	var level = load("res://scripts/module_level.gd")
	if start:
		# The bed goes to the side wall: the beacon has the back.
		beacon_at_back = true
		_dress()
		if torch_energy > 0.0:
			level._hang_torch(self, load(level.TORCH_SCENE), Vector3(-FACE, built.height * level.TORCH_HEIGHT, 0.5),
				Vector3.LEFT, torch_energy * 0.6, level.TORCH_RANGE)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(cell)
		_strewn_straw(_mat(Color(0.29, 0.22, 0.1), 1.0), rng)
		var iron := _mat(Color(0.11, 0.1, 0.095), 0.6, 0.75)
		# Either side of the beacon's obelisk, not behind it.
		_shackles(Vector3(-1.15, 0.0, -FACE), iron, false)
		_shackles(Vector3(1.15, 0.0, -FACE), iron, true)
		if torch_energy > 0.0:
			# As in the starting cell: a dead end with no torch of its own is black.
			# On the left wall, or the right when a wall torch has the left.
			var side := 1.0 if pilaster < 0 else -1.0
			level._hang_torch(self, load(level.TORCH_SCENE), Vector3(side * FACE, built.height * level.TORCH_HEIGHT, TORCH_Z),
				Vector3(side, 0.0, 0.0), torch_energy * TORCH_SHARE, level.TORCH_RANGE)
	_build_gate()
	_draw_to(self, DRAWN_TO)
	_prompt = Interact.prompt("E   Open the cell", Vector3(0.0, 1.6, 0.0))
	_gate.add_child(_prompt)


func _build_gate() -> void:
	var kit = load("res://scripts/brick_level.gd")
	_gate = Node3D.new()
	_gate.name = "Gate"
	_gate.position = Vector3(0.0, 0.0, GATE_Z)
	add_child(_gate)
	for side: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.name = "GateL" if side < 0.0 else "GateR"
		hinge.position = Vector3(side * GATE_HALF, 0.0, 0.0)
		_gate.add_child(hinge)
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
	_gate.add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(GATE_HALF * 2.0 + 0.1, GATE_HEIGHT, 0.15)
	_blocker = CollisionShape3D.new()
	_blocker.shape = box
	_blocker.position = Vector3(0.0, GATE_HEIGHT * 0.5, 0.0)
	_blocker.disabled = true
	body.add_child(_blocker)


## The navmesh is baked: the bars mean something now.
func arm() -> void:
	if not is_open:
		_blocker.disabled = false


## Puts its prisoners back, on the first population and after a death; a cell
## already opened stands open and empty, and the starting cell holds nobody.
func stock() -> void:
	_prisoners.clear()
	if is_open or start:
		return
	var spots: Array = _spots()
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


## `SPOTS`, with the prisoner on a wall torch's side moved in and forward, clear of
## its pilaster (0.3 m proud of the wall, 0.9 m wide, at z 0), and the third to the
## other side of the middle line to make room.
func _spots() -> Array:
	var spots: Array = (SPOTS[hands.size()] as Array).duplicate()
	if pilaster == 0:
		return spots
	for i in spots.size():
		var p: Vector3 = spots[i]
		if signf(p.x) == float(pilaster) and absf(p.x) > 0.9:
			spots[i] = Vector3(0.95 * float(pilaster), p.y, 0.8)
		elif absf(p.x) <= 0.9:
			spots[i] = Vector3(-absf(p.x) * float(pilaster), p.y, p.z)
	return spots


## Leaves alone what has a limit of its own (a sword, a health bar).
static func _draw_to(node: Node3D, reach: float) -> void:
	for found in node.find_children("*", "GeometryInstance3D", true, false):
		var mesh := found as GeometryInstance3D
		if mesh.visibility_range_end == 0.0 or mesh.visibility_range_end == DRAWN_TO:
			mesh.visibility_range_end = reach


func _process(_delta: float) -> void:
	if is_open:
		_prompt.visible = false
		set_process(false)
		return
	# Co-op: whoever can use it, from either side of the bars.
	var by := Interact.chooser(_gate, GATE_REACH, 1.5, 3.4, 0.1, _hinges)
	_near = by != null
	if by != null:
		_user = by as Node3D
	_prompt.visible = _near
	_prompt.player = _user


func _unhandled_input(event: InputEvent) -> void:
	if is_open or not _near or _user == null or not Interact.pressed(event, _user):
		return
	get_viewport().set_input_as_handled()
	swing_open()


## The gate swings out and the prisoners are loose. `now`: already so, as a
## reload finds it.
func swing_open(now := false) -> void:
	if is_open:
		return
	is_open = true
	_near = false
	if _prompt != null:
		_prompt.visible = false
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
		opened.emit(self)


func _let_go() -> void:
	if not is_inside_tree():
		return
	for e in _prisoners:
		if is_instance_valid(e):
			e.set("caged", false)
			_draw_to(e, 0.0)
			maze.call("turn_loose_subject", e)
	_prisoners.clear()
