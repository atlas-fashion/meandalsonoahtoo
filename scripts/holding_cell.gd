extends "res://scripts/jail_cell.gd"

## A jail cell out in the maze (note 153, reworked in note 154, remodelled in note
## 177): a dead end shut by a gate of rusted bars, holding two or three proels of different types and a
## respawn beacon (respawn_anchor.gd) at the back. Each prisoner is a real enemy,
## `caged` as in a containment block (enemy.gd): blind, deaf and unhurt behind the
## bars. The player opens the gate with E whenever they like (note 154; it used to
## wait for every type inside to be let out of containment), and the prisoners go
## into the maze as loose subjects -- between the player and the beacon. An opened
## cell stays open and empty, through deaths and in the save (maze.gd
## `save_state` "cells_open"), since the player may rise at its beacon.
##
## The player's starting cell is one too (`start`): the same dressing plus the
## starting cell's bucket and remains, the same gate and a beacon, and nobody else
## inside.
##
## Dressed from the cell kit (note 177, models/cell_kit.glb from
## tools/build_cell_kit.py): the gate's big bronze gear lock, a caged lantern on
## its chain from the vault (the cell's one light), chains and manacles over a
## stone bench with a frayed burlap cloth, a stone shelf with a bowl and a cup, a
## drain grate, straw. No door at the back (the user's call). jail_cell.gd's frame
## is kept: +Z towards the way out. Built before the navmesh bake with its
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

## The kit (note 177). Wall pieces are snapped onto the stone from this high up
## them, clear of the floor.
const KIT := "res://models/cell_kit.glb"
const SNAP_HEIGHT := 1.2
## The bench and the shelf, centred this far along the side walls: the bench
## (1.2 long) from the back corner pillar (z -1.55) to z -0.3, short of the
## prisoners; the shelf (0.8) clear of a wall torch's pilaster (|z| < 0.45).
const BENCH_Z := -0.9
const DRAIN_Z := 0.55
## The lantern hangs over the middle, a little towards the gate so its light
## falls on the prisoners' fronts; its hook here, the wick 0.335 m under it.
const LANTERN_HOOK_Y := 2.95
const LANTERN_Z := 1.0
const LANTERN_WICK_Y := -0.335
const LANTERN_FLAME := 0.2
const LANTERN_START_SHARE := 2.2
const CHAIN_RUN := 0.5
static var _kit_meshes := {}
static var _glass: StandardMaterial3D

var _lantern: Node3D
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
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell)
	var straw := _mat(Color(0.29, 0.22, 0.1), 1.0)
	_strewn_straw(straw, rng)
	_kit_dress(rng)
	if start:
		# The last prisoner's bones and the slop bucket stay (jail_cell.gd); the
		# plank bed gave way to the kit's stone bench.
		_remains(_mat(Color(0.48, 0.44, 0.36), 0.9), rng)
		_bucket(_wood(), _mat(Color(0.11, 0.1, 0.095), 0.6, 0.75))
	if torch_energy > 0.0:
		# The one light: the lantern's flame. The starting cell's own torch was
		# 0.6 of a corridor's; a maze cell's 3.0, to be a pool of light seen
		# from outside (note 153).
		_hang_lantern(built, torch_energy * (LANTERN_START_SHARE if start else TORCH_SHARE))
	_build_gate()
	_draw_to(self, DRAWN_TO)
	_prompt = Interact.prompt("E   Open the cell", Vector3(0.0, 1.6, 0.0))
	_gate.add_child(_prompt)


# --- The cell kit (note 177): models/cell_kit.glb, tools/build_cell_kit.py ---------

## The pieces of models/cell_kit.glb by name, read once.
static func kit_mesh(piece: String) -> Mesh:
	if _kit_meshes.is_empty():
		var scene := load(KIT) as PackedScene
		if scene != null:
			var root := scene.instantiate()
			for found in root.find_children("*", "MeshInstance3D", true, false):
				_kit_meshes[String(found.name)] = (found as MeshInstance3D).mesh
			root.free()
	return _kit_meshes.get(piece)


static func _glass_material() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.albedo_color = Color(0.8, 0.62, 0.38, 0.16)
		_glass.roughness = 0.08
		_glass.metallic_specular = 0.7
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass


## A kit piece under `parent`. `shadow`: whether it casts for the lantern.
func _piece(piece: String, parent: Node3D, at := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = piece.capitalize().replace(" ", "")
	mi.mesh = kit_mesh(piece)
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A holder on a wall: origin `SNAP_HEIGHT` up the wall at `at` (floor level),
## facing `facing` (its +Z into the room), snapped onto the real stone along
## `into` once collision is live. Its pieces hang `SNAP_HEIGHT` below it, so they
## stand on the floor.
func _wall_holder(holder_name: String, at: Vector3, facing: float, into: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = holder_name
	holder.position = at + Vector3(0.0, SNAP_HEIGHT, 0.0)
	holder.rotation.y = facing
	holder.set_meta("into", into)
	holder.set_meta("standoff", 0.004)
	add_child(holder)
	_wall_items.append(holder)
	return holder


func _solid_on(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = at
	parent.add_child(body)


## The reference's cell (its bronze gear door is the gate's lock: no door at the
## back, the user said): the chains slung over a stone bench with its burlap on one side wall, a stone
## shelf with a bowl and a cup on the other, a drain in the floor, straw. The
## bench goes on the left wall, or the right when a wall torch's pilaster has the
## left (it would stand in it).
func _kit_dress(rng: RandomNumberGenerator) -> void:
	var side := 1.0 if pilaster < 0 else -1.0
	var down := Vector3(0.0, -SNAP_HEIGHT, 0.0)

	# Against the bench's wall: local +Z into the room, +X towards the back.
	var facing := -side * PI * 0.5
	var bench := _wall_holder("Bench", Vector3(side * FACE, 0.0, BENCH_Z), facing, Vector3(side, 0, 0))
	_piece("bench", bench, down)
	_solid_on(bench, Vector3(1.2, 0.48, 0.5), down + Vector3(0.0, 0.24, 0.25))
	var chains := _wall_holder("Chains", Vector3(side * FACE, 0.0, BENCH_Z), facing, Vector3(side, 0, 0))
	_piece("wall_chains", chains, down)
	var shelf := _wall_holder("Shelf", Vector3(-side * FACE, 0.0, BENCH_Z), -facing, Vector3(-side, 0, 0))
	_piece("shelf", shelf, down)
	_solid_on(shelf, Vector3(0.8, 0.38, 0.32), down + Vector3(0.0, 1.01, 0.16))
	_piece("drain", self, Vector3(0.0, 0.0, DRAIN_Z), false)
	# Tufts of straw: under the bench, in the back corners, a few trodden about.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = kit_mesh("straw_tuft")
	var spots: Array[Vector3] = [
		Vector3(side * 1.55, 0.0, BENCH_Z - 0.2), Vector3(side * 1.35, 0.0, BENCH_Z + 0.35),
		Vector3(-side * 1.3, 0.0, -1.45), Vector3(side * 1.2, 0.0, -1.5),
		Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(0.9, 1.9)),
		Vector3(rng.randf_range(-1.4, 1.4), 0.0, rng.randf_range(-0.2, 0.5)),
		Vector3(-side * 1.45, 0.0, 0.9),
	]
	mm.instance_count = spots.size()
	for i in spots.size():
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.35))
		mm.set_instance_transform(i, Transform3D(b, spots[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "StrawTufts"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## The caged lantern on its chain from the vault, and in it the cell's one light:
## the torch scene without its mount (torch.gd keeps its flicker, its place in the
## nearest-N ranking and its shadow), its flame shrunk to a candle's.
func _hang_lantern(_built, energy: float) -> void:
	var lantern := Node3D.new()
	lantern.name = "Lantern"
	lantern.position = Vector3(0.0, LANTERN_HOOK_Y, LANTERN_Z)
	add_child(lantern)
	# No shadows from the cage: the light is inside it.
	_piece("lantern", lantern, Vector3.ZERO, false)
	var glass := _piece("lantern_glass", lantern, Vector3.ZERO, false)
	glass.material_override = _glass_material()
	_lantern = lantern
	var level = load("res://scripts/module_level.gd")
	var torch := (load(level.TORCH_SCENE) as PackedScene).instantiate() as Node3D
	torch.set("kit_mount", false)
	for part in ["Plate", "Arm", "Ring", "Handle", "Head", "Embers"]:
		var n := torch.get_node_or_null(part)
		if n != null:
			torch.remove_child(n)
			n.free()
	# Origin on the wick; the flame card stands up from it.
	torch.position = Vector3(0.0, LANTERN_WICK_Y, 0.0)
	(torch.get_node("Flame") as Node3D).position = Vector3.ZERO
	(torch.get_node("Flame") as Node3D).scale = Vector3.ONE * LANTERN_FLAME
	var halo := torch.get_node_or_null("Halo") as Node3D
	if halo != null:
		halo.position = Vector3(0.0, 0.06, 0.0)
		halo.scale = Vector3.ONE * LANTERN_FLAME
	var light := torch.get_node("Light") as OmniLight3D
	light.position = Vector3(0.0, 0.05, 0.0)
	torch.set("base_energy", energy)
	torch.set("light_range", level.TORCH_RANGE)
	lantern.add_child(torch)
	# As module_level._hang_torch sets up every torch's light.
	light.omni_attenuation = level.TORCH_ATTENUATION
	light.light_specular = level.TORCH_SPECULAR
	light.shadow_enabled = true
	light.set_meta("torch_shadow", true)
	var moon_only: int = load("res://scripts/brick_level.gd").MOON_ONLY_LAYER
	light.shadow_caster_mask &= ~moon_only
	light.light_cull_mask &= ~moon_only
	light.light_color = level.TORCH_COLOUR
	_hang_chain.call_deferred()


## Chain from the lantern's hook up into the vault, as long as the vault is high
## there (a ray, once collision is live).
func _hang_chain() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(_lantern):
		return
	var from := _lantern.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8.0, 2 | 256)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var reach := 1.5
	if not hit.is_empty():
		reach = (hit["position"] as Vector3).y - from.y + 0.15
	var runs := clampi(ceili(reach / CHAIN_RUN), 1, 12)
	for i in runs:
		var run := _piece("lantern_chain", _lantern, Vector3(0.0, CHAIN_RUN * float(i + 1), 0.0), false)
		run.rotation.y = PI * 0.5 * float(i % 2)
		run.visibility_range_end = DRAWN_TO


func _build_gate() -> void:
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
		leaf.mesh = kit_mesh("gate_l" if side < 0.0 else "gate_r")
		# No shadow, unlike the prison's: from the corridor the prisoners stood
		# black behind the bars (note 153).
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
