extends RefCounted

## Splits the maze into unlockable phases, and hands back a restricted VIEW of
## the graph containing only the parts that are currently open.
##
## The intent this exists for: what ships today is "phase 1" of a larger maze.
## Killing the boss opens the next region, which brings new enemies with it.
## None of that unlocking is implemented here -- no trigger, no transition, no
## new enemies. What is implemented is the seam it needs, so that adding it
## later is a change to the game's rules rather than to how the level is built.
##
## The seam is a duck-typed wrapper. Everything downstream -- `kit_placer`,
## `organic_maze`, the contour tracer, `maze.gd`'s own grid rasteriser -- asks
## the graph the same two questions, `inside(p)` and `distance(p)`, and reads
## `nodes`, `corridors`, `cells` and `chamber_at`. A `View` answers all of those
## as if the locked corridors had never been generated, so the wall contour
## closes around the open region on its own, collision follows it, the grid
## rasterises to it and the navmesh bakes from it. Nothing downstream needs to
## know phases exist.
##
## Phases are assigned by corridor distance from the ARENA, not from the player
## spawn. The arena is the fixed landmark the whole map is arranged around, and
## the boss is what unlocks the next band, so "how far past the boss is this"
## is the question the bands should answer.


## A restricted view of a graph. Duck-types the members every consumer reads.
class View extends RefCounted:
	var nodes: Array = []
	var corridors: Array = []
	var cells: Array = []
	var chamber_at: Dictionary = {}
	var edges: Array = []
	var boss_centre: Vector2
	var boss_radius: float
	var corridor_radius: float
	var cell_radius: float
	var cell_gap_value: float = 0.0
	var spawn_node: int = 0
	## Copied because `maze.gd` hangs the arena's portcullises off it. Leaving
	## it out threw on every build the moment phases were switched on.
	var boss_door_dirs: Array = []

	var _source = null
	var _open_nodes := {}

	func _init(source, open_nodes: Dictionary) -> void:
		_source = source
		_open_nodes = open_nodes
		boss_centre = source.boss_centre
		boss_radius = source.boss_radius
		corridor_radius = source.corridor_radius
		cell_radius = source.cell_radius
		boss_door_dirs = source.boss_door_dirs

		# The spawn has to be INSIDE the open region.
		#
		# The base graph puts the player at the node furthest from the arena,
		# which is the whole point -- the boss should be hard to find. But that
		# node is by definition in the last phase to unlock, so restricting the
		# map stranded the player in locked rock: the grid rasterised to 0.0%
		# reachable from spawn on every phase but the last.
		#
		# So the spawn moves to the deepest node that is actually open, which
		# preserves the intent band by band.
		spawn_node = source.spawn_node
		if not open_nodes.has(int(source.spawn_node)):
			var hops: PackedInt32Array = source.hops_from(0)
			var best := -1
			for i in hops.size():
				if not open_nodes.has(i) or hops[i] < 0:
					continue
				if best < 0 or hops[i] > hops[best]:
					best = i
			if best >= 0:
				spawn_node = best
		# Node INDICES are preserved, not compacted. Everything else in the
		# project refers to nodes by index -- `spawn_node`, `chamber_at`, the
		# edge list -- and renumbering them here would silently repoint all of
		# it at the wrong places.
		nodes = source.nodes
		for i in source.chamber_at.keys():
			if open_nodes.has(int(i)):
				chamber_at[i] = source.chamber_at[i]
		for e in source.edges:
			if open_nodes.has(int(e.x)) and open_nodes.has(int(e.y)):
				edges.append(e)
		# Cells are alcoves on the arena rim; they belong to the arena, which is
		# always open, so they always come through.
		cells = source.cells

	## True where the OPEN region is walkable. A locked corridor reads as solid
	## rock, which is exactly what the wall builder should make of it.
	func inside(p: Vector2) -> bool:
		if p.distance_squared_to(boss_centre) <= boss_radius * boss_radius:
			return true
		for i in chamber_at.keys():
			var r: float = chamber_at[i]
			if p.distance_squared_to(nodes[i]) <= r * r:
				return true
		var cr2: float = cell_radius * cell_radius
		for c in cells:
			if p.distance_squared_to(c) <= cr2:
				return true
		for line in corridors:
			for k in range(line.size() - 1):
				if _to_segment(p, line[k], line[k + 1]) <= corridor_radius:
					return true
		return false

	## Signed distance to the open region: negative inside, positive outside.
	## Must agree with `inside()` -- when these two disagreed in the base graph
	## the wall phase sealed every jail alcove shut.
	func distance(p: Vector2) -> float:
		var best: float = p.distance_to(boss_centre) - boss_radius
		for i in chamber_at.keys():
			best = minf(best, p.distance_to(nodes[i]) - float(chamber_at[i]))
		for c in cells:
			best = minf(best, p.distance_to(c) - cell_radius)
		for line in corridors:
			for k in range(line.size() - 1):
				best = minf(best, _to_segment(p, line[k], line[k + 1]) - corridor_radius)
		return best

	static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
		var ab := b - a
		var denom := ab.dot(ab)
		if denom < 0.000001:
			return p.distance_to(a)
		var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
		return p.distance_to(a + ab * t)


## Phase index per node, by corridor hops from the arena, split into `count`
## bands of roughly equal depth.
##
## Returns a Dictionary of node index -> phase. Node 0 (the arena) is always
## phase 0: the boss has to be reachable from the start or there is nothing to
## kill to unlock anything.
static func assign(graph, count: int) -> Dictionary:
	var phases := {}
	var bands: int = maxi(count, 1)
	var hops: PackedInt32Array = graph.hops_from(0)
	var deepest := 0
	for h in hops:
		deepest = maxi(deepest, h)
	if deepest <= 0:
		for i in graph.nodes.size():
			phases[i] = 0
		return phases
	for i in hops.size():
		var h: int = hops[i]
		if h < 0:
			# Unreachable from the arena; park it in the last band rather than
			# leaving it unassigned and having it silently vanish.
			phases[i] = bands - 1
			continue
		phases[i] = mini(bands - 1, h * bands / (deepest + 1))
	phases[0] = 0
	return phases


## The set of node indices open at `active` (0-based, inclusive).
static func open_nodes(phases: Dictionary, active: int) -> Dictionary:
	var open := {}
	for i in phases.keys():
		if int(phases[i]) <= active:
			open[int(i)] = true
	return open


## A view of `graph` restricted to phases 0..`active`.
##
## Corridors are included only when BOTH endpoints are open, so a passage never
## runs half-built into a locked region and stop in mid-air. That does mean the
## boundary between phases falls on a junction, which is where a door or a
## collapse wants to be anyway.
static func view(graph, phases: Dictionary, active: int):
	var open := open_nodes(phases, active)
	var v := View.new(graph, open)
	var kept: Array = []
	var corridor_count: int = graph.corridors.size()
	for ci in corridor_count:
		var line = graph.corridors[ci]
		if line.size() < 2:
			continue
		# Corridors are not indexed by edge, so which nodes a line joins is
		# recovered from its own endpoints. Anything whose two ends are both
		# near open nodes is an open corridor.
		if _endpoint_open(graph, open, Vector2(line[0])) \
				and _endpoint_open(graph, open, Vector2(line[line.size() - 1])):
			kept.append(line)
	v.corridors = kept
	return v


static func _endpoint_open(graph, open: Dictionary, p: Vector2) -> bool:
	var best := INF
	var best_i := -1
	for i in graph.nodes.size():
		var d: float = p.distance_squared_to(graph.nodes[i])
		if d < best:
			best = d
			best_i = i
	return best_i >= 0 and open.has(best_i)


## How many nodes and corridors each phase adds, for reporting and for a test
## to assert against.
static func summarise(graph, phases: Dictionary, count: int) -> String:
	var per := {}
	for i in phases.keys():
		var ph: int = int(phases[i])
		per[ph] = int(per.get(ph, 0)) + 1
	var parts: Array[String] = []
	for ph in range(maxi(count, 1)):
		parts.append("phase %d: %d nodes" % [ph, int(per.get(ph, 0))])
	return ", ".join(parts)
