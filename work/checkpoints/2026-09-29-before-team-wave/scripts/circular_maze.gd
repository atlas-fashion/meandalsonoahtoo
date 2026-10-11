extends RefCounted

## A circular maze: concentric rings of wedge-shaped cells around a central
## chamber, carved by Wilson's algorithm with loop-erased random walks.
##
## The graph is genuinely circular. Nothing here generates a rectangular maze
## and bends it -- ring membership, angular wraparound and inner/outer adjacency
## are all first-class, and an inner cell may border several outer cells.
##
## Angles are held in TURNS (0..1) rather than radians. The seam at the start of
## a ring is then exact integer arithmetic instead of a float comparison against
## TAU, which is where circular layouts usually develop a one-cell crack.
##
## Potential adjacency (what touches what) is kept separate from carved
## passages (what you can walk through). Agents must route on passages.

const EPS := 1e-9


class Cell extends RefCounted:
	var id: int
	var ring: int
	var index: int
	var r_inner: float
	var r_outer: float
	## Angular span in turns, [a0, a1). a1 may be 1.0 for the last cell.
	var a0: float
	var a1: float
	## A point comfortably inside the cell, for spawning and as a path waypoint.
	var centre := Vector2.ZERO
	## Everything geometrically touching this cell.
	var neighbours: PackedInt32Array = PackedInt32Array()
	## The subset of `neighbours` joined by an open passage.
	var passages: PackedInt32Array = PackedInt32Array()

	func mid_angle() -> float:
		return (a0 + a1) * 0.5

	func mid_radius() -> float:
		return (r_inner + r_outer) * 0.5


# --- configuration ---------------------------------------------------------
var rings := 7
var chamber_radius := 9.0
var ring_depth := 5.0
## Tangential width a cell aims for. Ring cell counts are chosen to hold roughly
## to this as the circumference grows.
var target_cell_width := 7.0
var wall_thickness := 0.8
var wall_height := 9.0
## Half-width of the widest thing that must fit through a passage.
var agent_clearance := 1.4

# --- results ---------------------------------------------------------------
var cells: Array[Cell] = []
## Cell ids per ring; ring 0 is the chamber.
var ring_cells: Array[PackedInt32Array] = []
var chamber_id := 0
## Outer-boundary cell opened to the outside world, or -1.
var entrance_id := -1
var goal_id := 0

var _rng := RandomNumberGenerator.new()
var _seed := 0


func used_seed() -> int:
	return _seed


## Returns "" when the configuration can actually be built, or a description of
## why it cannot.
##
## The tightest point in a wedge passage is its inner arc, where the ring's
## cells are narrowest. Checking only the average or the outer edge lets a
## configuration through that is impassable near the middle of the maze -- so
## this checks the inner arc of every ring, which is where it really fails.
func validate() -> String:
	if rings < 1:
		return "rings must be at least 1"
	if chamber_radius <= 0.0 or ring_depth <= 0.0:
		return "chamber_radius and ring_depth must be positive"
	var need := agent_clearance * 2.0
	var radial := ring_depth - wall_thickness
	if radial < need:
		return ("ring_depth %.2f leaves %.2f m between walls, but %.2f m is needed "
			+ "for clearance %.2f") % [ring_depth, radial, need, agent_clearance]
	var counts := _ring_counts()
	for i in counts.size():
		var r_in: float = chamber_radius + float(i) * ring_depth
		var arc := TAU * r_in / float(counts[i]) - wall_thickness
		if arc < need:
			return ("ring %d holds %d cells, %.2f m wide at its inner arc, but "
				+ "%.2f m is needed. Use fewer rings, a bigger chamber, or a "
				+ "larger target_cell_width.") % [i + 1, counts[i], arc, need]
	return ""


## Cell count for each ring, outward from the chamber.
##
## The count only ever stays the same or doubles. That keeps every angular
## boundary in an outer ring aligned with one in the ring inside it, so an inner
## cell spans a whole number of outer cells and no sliver cells appear.
func _ring_counts() -> PackedInt32Array:
	var counts := PackedInt32Array()
	var count := maxi(int(round(TAU * (chamber_radius + ring_depth * 0.5)
		/ maxf(target_cell_width, 0.001))), 4)
	for i in rings:
		var r_mid: float = chamber_radius + (float(i) + 0.5) * ring_depth
		var width := TAU * r_mid / float(count)
		# Double when cells have stretched to half again the target, which keeps
		# the width oscillating around it rather than drifting upwards.
		if width > target_cell_width * 1.5:
			count *= 2
		counts.append(count)
	return counts


## Builds the graph and carves it. Same seed and configuration always produce
## the same maze.
func build(seed_value: int) -> String:
	var problem := validate()
	if problem != "":
		return problem
	_seed = seed_value
	_rng.seed = seed_value
	_build_graph()
	_wilson()
	return ""


func _build_graph() -> void:
	cells.clear()
	ring_cells.clear()

	# Ring 0: the chamber, one cell spanning the whole turn.
	var chamber := Cell.new()
	chamber.id = 0
	chamber.ring = 0
	chamber.index = 0
	chamber.r_inner = 0.0
	chamber.r_outer = chamber_radius
	chamber.a0 = 0.0
	chamber.a1 = 1.0
	chamber.centre = Vector2.ZERO
	cells.append(chamber)
	ring_cells.append(PackedInt32Array([0]))
	chamber_id = 0
	goal_id = 0

	var counts := _ring_counts()
	for i in counts.size():
		var count: int = counts[i]
		var ids := PackedInt32Array()
		var r_in: float = chamber_radius + float(i) * ring_depth
		var r_out: float = r_in + ring_depth
		for k in count:
			var c := Cell.new()
			c.id = cells.size()
			c.ring = i + 1
			c.index = k
			c.r_inner = r_in
			c.r_outer = r_out
			c.a0 = float(k) / float(count)
			c.a1 = float(k + 1) / float(count)
			var ang := c.mid_angle() * TAU
			var rad := c.mid_radius()
			c.centre = Vector2(cos(ang) * rad, sin(ang) * rad)
			cells.append(c)
			ids.append(c.id)
		ring_cells.append(ids)

	# Within each ring: clockwise and anticlockwise, including the seam.
	for i in range(1, ring_cells.size()):
		var ids := ring_cells[i]
		var n := ids.size()
		if n < 2:
			continue
		for k in n:
			# With two cells in a ring the two links coincide; _link guards
			# against the duplicate.
			_link(ids[k], ids[(k + 1) % n])

	# The chamber borders every cell of ring 1.
	for id in ring_cells[1]:
		_link(chamber_id, id)

	# Between rings: only where the angular spans overlap by a real segment.
	# Touching at a single boundary is not adjacency -- allowing it would let a
	# passage open across a corner where there is no wall to remove.
	for i in range(1, ring_cells.size() - 1):
		for a in ring_cells[i]:
			for b in ring_cells[i + 1]:
				var lo: float = maxf(cells[a].a0, cells[b].a0)
				var hi: float = minf(cells[a].a1, cells[b].a1)
				if hi - lo > EPS:
					_link(a, b)


func _link(a: int, b: int) -> void:
	if a == b:
		return
	if cells[a].neighbours.has(b):
		return
	cells[a].neighbours.append(b)
	cells[b].neighbours.append(a)


## Wilson's algorithm: a uniform spanning tree by loop-erased random walk.
##
## Every cell not yet in the tree starts a random walk over its POTENTIAL
## neighbours, each chosen with equal probability. Whenever the walk steps onto
## a cell it has already visited during this walk, the loop is erased on the
## spot. The walk ends when it touches the existing tree, and the surviving path
## is added whole.
##
## The walk is deliberately unbiased -- no pull toward the centre or the exit.
## Weighting the steps would still produce a maze, but it would no longer be a
## uniform spanning tree, and the difficulty metrics would be measuring a
## distribution nobody chose.
func _wilson() -> void:
	var total := cells.size()
	var in_tree := {}
	in_tree[chamber_id] = true
	var added := 1

	# Stable order, so the same seed rebuilds the same maze.
	for start in total:
		if added >= total:
			break
		if in_tree.has(start):
			continue

		# Ordered walk plus a position lookup, so erasing a loop is O(loop).
		var walk: Array[int] = [start]
		var at_step := {start: 0}
		var current := start
		while not in_tree.has(current):
			var options: PackedInt32Array = cells[current].neighbours
			current = options[_rng.randi_range(0, options.size() - 1)]
			if at_step.has(current):
				# Erase back to the earlier visit, dropping the loop from both
				# the list and the lookup.
				var cut: int = at_step[current]
				for j in range(walk.size() - 1, cut, -1):
					at_step.erase(walk[j])
				walk.resize(cut + 1)
			else:
				at_step[current] = walk.size()
				walk.append(current)

		# `current` is the tree cell the walk arrived at; join the path to it.
		for j in walk.size():
			var a: int = walk[j]
			var b: int = walk[j + 1] if j + 1 < walk.size() else current
			_carve(a, b)
			if not in_tree.has(a):
				in_tree[a] = true
				added += 1


func _carve(a: int, b: int) -> void:
	if a == b:
		return
	if cells[a].passages.has(b):
		return
	cells[a].passages.append(b)
	cells[b].passages.append(a)


# --- queries ----------------------------------------------------------------

## Fewest cell transitions between two cells, as a list of ids, or empty.
func route(from_id: int, to_id: int) -> PackedInt32Array:
	if from_id == to_id:
		return PackedInt32Array([from_id])
	var came := {from_id: -1}
	var queue: Array[int] = [from_id]
	var head := 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		if at == to_id:
			break
		for n in cells[at].passages:
			if came.has(n):
				continue
			came[n] = at
			queue.append(n)
	if not came.has(to_id):
		return PackedInt32Array()
	var path := PackedInt32Array()
	var walk: int = to_id
	while walk != -1:
		path.append(walk)
		walk = came[walk]
	path.reverse()
	return path


## The cell containing a world XZ point, or -1 outside the maze.
func cell_at(p: Vector2) -> int:
	var r := p.length()
	if r <= chamber_radius:
		return chamber_id
	var ring := int(floor((r - chamber_radius) / ring_depth)) + 1
	if ring < 1 or ring >= ring_cells.size():
		return -1
	var turn := fposmod(atan2(p.y, p.x), TAU) / TAU
	var ids := ring_cells[ring]
	var k := int(floor(turn * float(ids.size()))) % ids.size()
	return ids[k]


func outer_ring() -> PackedInt32Array:
	return ring_cells[ring_cells.size() - 1]


## Opens the outer boundary at a given angle, in turns.
##
## This is a hole in the perimeter, not a spanning-tree edge: it joins the maze
## to the outside world and so cannot create a shortcut between two cells that
## were already connected. The tree is untouched.
func set_entrance_at(turn: float) -> int:
	var ids := outer_ring()
	var k := int(floor(fposmod(turn, 1.0) * float(ids.size()))) % ids.size()
	entrance_id = ids[k]
	return entrance_id


## A point well clear of the walls, for spawning or as a path waypoint.
func safe_point(id: int) -> Vector2:
	var c := cells[id]
	if c.ring == 0:
		return Vector2.ZERO
	var ang := c.mid_angle() * TAU
	return Vector2(cos(ang), sin(ang)) * c.mid_radius()


## Where a passage between two cells is crossed, so an agent can aim at the gap
## rather than at the next cell's centre -- a straight line between two centres
## in a ring cuts through the curved wall between them.
func crossing(a: int, b: int) -> Vector2:
	var ca := cells[a]
	var cb := cells[b]
	if ca.ring == cb.ring:
		# Shared radial wall: meet on it, midway out the ring.
		var shared := ca.a1 if is_equal_approx(ca.a1, cb.a0) else ca.a0
		if absf(ca.a0 - cb.a1) < EPS:
			shared = ca.a0
		elif absf(ca.a1 - cb.a0) < EPS:
			shared = ca.a1
		var ang := shared * TAU
		return Vector2(cos(ang), sin(ang)) * ca.mid_radius()
	# Shared arc: meet on it, midway across the overlap.
	var inner := ca if ca.ring < cb.ring else cb
	var outer := cb if ca.ring < cb.ring else ca
	var lo := maxf(inner.a0, outer.a0)
	var hi := minf(inner.a1, outer.a1)
	var mid := (lo + hi) * 0.5 * TAU
	return Vector2(cos(mid), sin(mid)) * outer.r_inner
