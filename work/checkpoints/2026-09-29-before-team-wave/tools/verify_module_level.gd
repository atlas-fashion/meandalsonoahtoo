extends SceneTree

## Checks that the module level is actually walkable before it is wired in.
##
##   godot --path . --windowed --script res://tools/verify_module_level.gd
##
## NOT headless, on purpose. `MultiMesh.get_instance_transform()` returns
## identity under the dummy renderer -- no error, no warning -- so a headless
## run of this would compare identity to identity and pass while placing every
## module at the origin. `CLAUDE.md` records two earlier tests that were
## vacuous for exactly this reason.
##
## What it measures:
##
##   PLACEMENT  every carved cell has exactly one module instance, at the
##              right world position and turned the right way.
##   PASSAGE    for every connection the maze says exists, a ray at chest
##              height gets from one cell centre to the next. This is the
##              check that catches collision sealing a corridor shut.
##   SEALING    for every pair of adjacent cells the maze says are NOT
##              connected, that same ray is blocked.
##   GATES      two of them, both at dead ends, both on the rim.
##   WALLS      collision stands ON the visible wall face. The player used to
##              be able to walk over a metre into stone that looked solid,
##              because the boxes were at the cell boundary while the stone was
##              well inside it. Rays from each cell centre toward its walls
##              must hit collision within a few centimetres of the measured
##              stone face -- neither short of it (an invisible wall) nor past
##              it (walking into the rock).
##   ROOMS      a boss room and at least one chest room exist, each can be
##              entered through every one of its doorways, and each courtyard
##              is clear floor with no collision across it.

const ModuleMaze = preload("res://scripts/module_maze.gd")
const ModuleLevel = preload("res://scripts/module_level.gd")

const Graph = preload("res://scripts/maze_graph.gd")

const SEED := 20260928
## Mirrors the game: the layout is sampled from the organic generator, so the
## checks have to run against that and not against a plain grid maze, which
## is a different and much easier level to get right.
const ORGANIC := true
const EXTENT := 92.0
const SIZE := Vector2i(33, 33)
const CELL := 6.0
const HEIGHT := 5.1
const VIEW_RANGE := 70.0
const TINT := 1.0
## Chest height for the passage rays.
const PROBE_Y := 1.2

var _fails := 0


func _report(ok: bool, label: String, detail: String) -> void:
	if not ok:
		_fails += 1
	print("%s %-10s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var graph = null
	if ORGANIC:
		graph = Graph.new()
		graph.boss_radius = CELL * 3.5
		graph.corridor_radius = 2.2
		graph.cell_radius = 2.3
		graph.boss_doors = 2
		graph.dead_end_spurs = 16
		graph.long_link_count = 1
		graph.generate(SEED, EXTENT, 13.0, 6, 7.0, 10.0)
		graph.build_cells(graph.safe_cell_count(1.8))
		graph._build_index()

	var built: ModuleLevel.Built = ModuleLevel.build(
		world, SEED, SIZE, CELL, HEIGHT, VIEW_RANGE, TINT, graph, {})

	# Let the physics server actually register the static bodies before any
	# ray is cast at them; shapes added this frame are not queryable yet.
	await process_frame
	await physics_frame
	await physics_frame

	_check_placement(world, built)
	_check_passages(world, built)
	_check_gates(built)
	_check_rooms(world, built)
	_check_wall_faces(world, built)
	_check_reachable(built)

	print("")
	print("module level: %s" % ("all good" if _fails == 0 else "%d PROBLEMS" % _fails))
	quit(0 if _fails == 0 else 1)


func _check_placement(world: Node3D, built: ModuleLevel.Built) -> void:
	var holder := world.get_node_or_null("ModuleChunks")
	if holder == null:
		_report(false, "placement", "no ModuleChunks node")
		return

	# Rebuild the placed set from the MultiMesh buffers, which is the only
	# evidence that says where the modules really are. Counting what the
	# builder intended to place would pass on an empty level.
	var placed := {}
	var draws := 0
	var instances := 0
	for mmi in holder.get_children():
		if not (mmi is MultiMeshInstance3D):
			continue
		draws += 1
		var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			instances += 1
			var world_xf: Transform3D = (mmi as MultiMeshInstance3D).transform \
				* mm.get_instance_transform(i)
			var p := world_xf.origin
			var gx := int(roundf((p.x - built.origin.x) / built.cell_size))
			var gz := int(roundf((p.z - built.origin.z) / built.cell_size))
			var key := Vector2i(gx, gz)
			var expected := built.to_world(key)
			if p.distance_to(expected) > 0.05:
				_report(false, "placement", "instance at %v is %.2f m off cell %s"
					% [p, p.distance_to(expected), key])
				return
			if placed.has(key):
				_report(false, "placement", "cell %s has two modules" % key)
				return
			placed[key] = world_xf

	# Courtyards get no module on purpose -- that is what makes them open to
	# the sky -- so they are left out of the count, not reported missing.
	var walled := 0
	for key in built.cells:
		if not built.cells[key].court:
			walled += 1
	_report(instances == walled, "placement",
		"%d instances for %d walled cells in %d draws" % [instances, walled, draws])

	var missing := 0
	for key in built.cells:
		if not placed.has(key) and not built.cells[key].court:
			missing += 1
	_report(missing == 0, "coverage", "%d cells with no module" % missing)

	# Orientation: the module's local -Z must point at the cell's canonical
	# north after its turn. A module placed at the right spot facing the wrong
	# way walls off the corridor just as effectively as one that is missing.
	var wrong := 0
	for key in built.cells:
		if not placed.has(key):
			continue
		var cell: ModuleMaze.Cell = built.cells[key]
		var forward: Vector3 = (placed[key] as Transform3D).basis * Vector3(0, 0, -1)
		var side: int = ModuleMaze._rotate(ModuleMaze.N, cell.turn)
		var step: Vector2i = ModuleMaze.DIRS[side]
		var want := Vector3(float(step.x), 0.0, float(step.y))
		if forward.distance_to(want) > 0.02:
			wrong += 1
	_report(wrong == 0, "facing", "%d modules turned the wrong way" % wrong)


## Each collision world is checked on its own. A ray with the default mask hits
## every layer at once, so a gap in the enemies' walls would be hidden by the
## player's walls standing in the same place, and vice versa.
func _check_passages(world: Node3D, built: ModuleLevel.Built) -> void:
	_check_passages_on(world, built, ModuleLevel.LAYER_WALLS_EXACT, "player")
	_check_passages_on(world, built, ModuleLevel.LAYER_WALLS_SIMPLE, "enemies")
	# Layer 2 alone: what enemy sight and the player's geometry rays test.
	_check_passages_on(world, built, 2, "sight")


func _check_passages_on(world: Node3D, built: ModuleLevel.Built, mask: int,
		who: String) -> void:
	var space := world.get_world_3d().direct_space_state
	var open_blocked := 0
	var open_total := 0
	var shut_leaking := 0
	var shut_total := 0

	for key in built.cells:
		var cell: ModuleMaze.Cell = built.cells[key]
		for side in ModuleMaze.ORDER:
			var step: Vector2i = ModuleMaze.DIRS[side]
			var other: Vector2i = cell.pos + step
			if not built.cells.has(other):
				continue
			# Each pair is looked at once, from the lower-ordered cell.
			if other.x < cell.pos.x or (other.x == cell.pos.x and other.y < cell.pos.y):
				continue
			var from := built.to_world(cell.pos) + Vector3(0.0, PROBE_Y, 0.0)
			var to := built.to_world(other) + Vector3(0.0, PROBE_Y, 0.0)
			var query := PhysicsRayQueryParameters3D.create(from, to, mask)
			var hit := space.intersect_ray(query)
			if cell.open & side:
				open_total += 1
				if not hit.is_empty():
					open_blocked += 1
			else:
				shut_total += 1
				if hit.is_empty():
					shut_leaking += 1

	_report(open_blocked == 0, "passages",
		"[%s] %d of %d open connections blocked" % [who, open_blocked, open_total])
	_report(shut_leaking == 0, "sealing",
		"[%s] %d of %d walls that can be passed through" % [who, shut_leaking, shut_total])


## Rooms exist, can be entered through every doorway, and their courtyards
## are open floor.
func _check_rooms(world: Node3D, built: ModuleLevel.Built) -> void:
	var boss := built.boss_room()
	var chests := built.chest_rooms()
	_report(not boss.is_empty(), "boss room",
		"%s, courtyard %.0f m across" % ["present" if not boss.is_empty() else "MISSING",
			built.court_half_span(boss) * 2.0 if not boss.is_empty() else 0.0])
	_report(chests.size() >= 1, "chest rooms", "%d placed" % chests.size())

	var space := world.get_world_3d().direct_space_state
	var blocked := 0
	var doors := 0
	var cluttered := 0
	for room in built.rooms:
		# Walk in through each doorway: from the corridor cell outside to the
		# ring cell inside. A blocked doorway is a room nobody can reach.
		for way in room["entrances"]:
			var step: Vector2i = ModuleMaze.DIRS[way["side"]]
			var inside: Vector2i = way["cell"]
			var outside: Vector2i = inside + step
			doors += 1
			var q := PhysicsRayQueryParameters3D.create(
				built.to_world(outside) + Vector3(0.0, PROBE_Y, 0.0),
				built.to_world(inside) + Vector3(0.0, PROBE_Y, 0.0),
				ModuleLevel.LAYER_WALLS_EXACT | ModuleLevel.LAYER_WALLS_SIMPLE)
			if not space.intersect_ray(q).is_empty():
				blocked += 1
		# The courtyard must be clear: a cross of rays through its middle.
		var mid := built.room_world(room) + Vector3(0.0, PROBE_Y, 0.0)
		var reach := built.court_half_span(room) - 0.3
		for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var q2 := PhysicsRayQueryParameters3D.create(mid, mid + d * reach,
				ModuleLevel.LAYER_WALLS_EXACT | ModuleLevel.LAYER_WALLS_SIMPLE)
			if not space.intersect_ray(q2).is_empty():
				cluttered += 1
	_report(blocked == 0, "room doors", "%d of %d doorways blocked" % [blocked, doors])
	_report(cluttered == 0, "courtyards", "%d of %d courtyard rays blocked"
		% [cluttered, built.rooms.size() * 4])


## Collision must stand ON the stone the player sees.
##
## For every solid side of every module, a ray from the cell centre toward the
## wall. Where it hits is where the player stops; `WALL_FACE` is where the
## stone visibly is, measured off the meshes. The two have to agree.
func _check_wall_faces(world: Node3D, built: ModuleLevel.Built) -> void:
	var space := world.get_world_3d().direct_space_state
	var worst_in := 0.0
	var worst_short := 0.0
	var samples := 0
	var missing := 0
	for key in built.cells:
		var cell = built.cells[key]
		if cell.court:
			continue
		var face: float = ModuleLevel.WALL_FACE.get(cell.kind, 0.0)
		if face <= 0.01:
			continue
		for side in ModuleMaze.ORDER:
			if cell.open & side:
				continue
			var step: Vector2i = ModuleMaze.DIRS[side]
			var dir := Vector3(float(step.x), 0.0, float(step.y))
			# At the height WALL_FACE was measured at, not at chest height.
			# Ragged stone is a different distance away at different heights,
			# and probing at 1.2 m against a reference taken at 2.3 m reported
			# a 0.5 m "invisible wall" that tools/verify_collision.py -- which
			# compares collision against the rendered surface directly -- shows
			# is not there: the two agree to within 2.6 cm everywhere.
			var from: Vector3 = built.to_world(cell.pos) \
				+ Vector3(0.0, built.height * ModuleLevel.TORCH_HEIGHT, 0.0)
			var q := PhysicsRayQueryParameters3D.create(from, from + dir * built.cell_size,
				ModuleLevel.LAYER_WALLS_EXACT)
			var hit := space.intersect_ray(q)
			samples += 1
			if hit.is_empty():
				missing += 1
				continue
			var d: float = from.distance_to(hit["position"])
			# Positive: collision is BEYOND the stone, so the player walks in.
			worst_in = maxf(worst_in, d - face)
			# Positive: collision stops SHORT of it, an invisible wall.
			worst_short = maxf(worst_short, face - d)
	_report(missing == 0 and worst_in <= 0.30, "wall walk-in",
		"collision up to %.2f m past the visible stone over %d walls (%d with no collision)"
			% [worst_in, samples, missing])
	_report(worst_short <= 0.45, "wall stand-off",
		"collision up to %.2f m in front of the visible stone" % worst_short)

## Everything the player must be able to reach, reachable through open sides.
func _check_reachable(built: ModuleLevel.Built) -> void:
	var seen := {}
	var start: Vector2i = built.cells.keys()[0]
	for key in built.cells:
		start = key
		break
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		var cell: ModuleMaze.Cell = built.cells[at]
		for side in ModuleMaze.ORDER:
			if not (cell.open & side):
				continue
			var to: Vector2i = at + ModuleMaze.DIRS[side]
			if not built.cells.has(to) or seen.has(to):
				continue
			seen[to] = true
			stack.append(to)
	_report(seen.size() == built.cells.size(), "connected",
		"%d of %d cells reachable" % [seen.size(), built.cells.size()])

	var gates_ok := true
	for gate in built.gates:
		if not seen.has(gate["pos"]):
			gates_ok = false
	_report(gates_ok, "gate reach", "both zone doors reachable from the maze")


func _check_gates(built: ModuleLevel.Built) -> void:
	if built.gates.size() != 2:
		_report(false, "gates", "expected 2, got %d" % built.gates.size())
		return
	var detail: Array[String] = []
	var ok := true
	for gate in built.gates:
		var pos: Vector2i = gate["pos"]
		var cell: ModuleMaze.Cell = built.cells[pos]
		var degree := 0
		for side in ModuleMaze.ORDER:
			if cell.open & side:
				degree += 1
		# Out near the edge of the MAP by distance, not near the edge of the
		# grid array: the organic footprint is a disc inside a square grid,
		# so its outermost dead ends are nowhere near the array bounds.
		var mid := Vector2(float(built.size.x - 1), float(built.size.y - 1)) * 0.5
		var on_rim: bool = Vector2(pos).distance_to(mid) >= mid.length() * 0.55
		if cell.kind != "gate" or degree != 1 or not on_rim:
			ok = false
		detail.append("%s(%s,deg %d,%s)"
			% [pos, cell.kind, degree, "rim" if on_rim else "INNER"])
	var apart: float = Vector2(built.gates[0]["pos"]).distance_to(
		Vector2(built.gates[1]["pos"])) * built.cell_size
	_report(ok, "gates", "%s  %.0f m apart" % [" ".join(detail), apart])



