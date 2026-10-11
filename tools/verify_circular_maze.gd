extends SceneTree

## Validation and preview for the circular maze generator.
##
##   godot --headless --path . --script res://tools/verify_circular_maze.gd
##
## Checks the properties the generator is supposed to guarantee, then renders a
## top-down view built from the actual shared boundaries -- so the picture is
## evidence about the geometry, not a separate drawing that could agree with a
## broken graph.

const Maze = preload("res://scripts/circular_maze.gd")
const IMG := 1000

var _ok := true


func _c(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_ok = false
	print("  %-52s %s   %s" % [label, "PASS" if cond else "FAIL", detail])


func _initialize() -> void:
	var m = Maze.new()
	m.rings = 7
	m.chamber_radius = 9.0
	m.ring_depth = 5.0
	m.target_cell_width = 7.0
	m.wall_thickness = 0.8
	m.agent_clearance = 1.4

	var problem: String = m.build(20260925)
	if problem != "":
		print("configuration rejected: %s" % problem)
		quit(1)
		return

	var n: int = m.cells.size()
	var counts := []
	for r in range(1, m.ring_cells.size()):
		counts.append(m.ring_cells[r].size())
	print("cells %d in %d rings, per ring %s" % [n, m.rings, str(counts)])
	m.set_entrance_at(0.0)
	print("entrance cell %d, goal cell %d" % [m.entrance_id, m.goal_id])
	print("")

	# --- topology -----------------------------------------------------------
	print("=== topology ===")
	var edges := 0
	var reciprocal_adj := true
	var reciprocal_pass := true
	var passage_is_adjacent := true
	for c in m.cells:
		for nb in c.neighbours:
			if not m.cells[nb].neighbours.has(c.id):
				reciprocal_adj = false
		for p in c.passages:
			edges += 1
			if not m.cells[p].passages.has(c.id):
				reciprocal_pass = false
			if not c.neighbours.has(p):
				passage_is_adjacent = false
	edges /= 2
	_c("adjacency is reciprocal", reciprocal_adj)
	_c("passages are reciprocal", reciprocal_pass)
	_c("every passage runs along a real shared boundary", passage_is_adjacent)
	_c("N cells have exactly N-1 passages", edges == n - 1,
		"%d passages, %d cells" % [edges, n])

	# Reachability and acyclicity together: a connected graph with N-1 edges is
	# a tree, so reaching every cell is the same statement as having no cycles.
	var seen := m.route(m.chamber_id, -1)  # unused; explicit flood below
	var reached := {}
	var stack: Array[int] = [m.chamber_id]
	reached[m.chamber_id] = true
	while not stack.is_empty():
		var at: int = stack.pop_back()
		for p in m.cells[at].passages:
			if not reached.has(p):
				reached[p] = true
				stack.append(p)
	_c("every cell is reachable from the chamber", reached.size() == n,
		"%d of %d" % [reached.size(), n])
	_c("no cycles (connected with N-1 edges)",
		reached.size() == n and edges == n - 1)

	var solution: PackedInt32Array = m.route(m.entrance_id, m.goal_id)
	_c("entrance reaches the goal", solution.size() > 0,
		"%d cells along the route" % solution.size())

	# --- circular specifics -------------------------------------------------
	print("=== circular structure ===")
	var wrap_ok := true
	for r in range(1, m.ring_cells.size()):
		var ids: PackedInt32Array = m.ring_cells[r]
		if ids.size() < 3:
			continue
		# First and last cell of a ring must touch across the seam.
		if not m.cells[ids[0]].neighbours.has(ids[ids.size() - 1]):
			wrap_ok = false
	_c("rings wrap around at the seam", wrap_ok)

	var chamber_ok: bool = m.cells[m.chamber_id].neighbours.size() == m.ring_cells[1].size()
	_c("chamber borders all of ring 1", chamber_ok,
		"%d neighbours, ring 1 has %d" % [m.cells[m.chamber_id].neighbours.size(),
			m.ring_cells[1].size()])

	# Inner/outer adjacency must come from a shared arc of real length, never a
	# corner touch -- a corner passage would open where there is no wall.
	var overlap_ok := true
	var cross_ring := 0
	for c in m.cells:
		for nb in c.neighbours:
			var o = m.cells[nb]
			if o.ring == c.ring or c.ring == 0 or o.ring == 0:
				continue
			cross_ring += 1
			var lo: float = maxf(c.a0, o.a0)
			var hi: float = minf(c.a1, o.a1)
			if hi - lo <= 1e-9:
				overlap_ok = false
	_c("ring transitions share a real arc, not a corner", overlap_ok,
		"%d cross-ring links" % (cross_ring / 2))

	# --- reproducibility ----------------------------------------------------
	print("=== reproducibility ===")
	var again = Maze.new()
	again.rings = m.rings
	again.chamber_radius = m.chamber_radius
	again.ring_depth = m.ring_depth
	again.target_cell_width = m.target_cell_width
	again.wall_thickness = m.wall_thickness
	again.agent_clearance = m.agent_clearance
	again.build(20260925)
	var same: bool = again.cells.size() == n
	if same:
		for i in n:
			if again.cells[i].passages != m.cells[i].passages:
				same = false
				break
	_c("same seed rebuilds the same maze", same)

	var other = Maze.new()
	other.rings = m.rings
	other.chamber_radius = m.chamber_radius
	other.ring_depth = m.ring_depth
	other.target_cell_width = m.target_cell_width
	other.wall_thickness = m.wall_thickness
	other.agent_clearance = m.agent_clearance
	other.build(20260926)
	var differs := false
	for i in n:
		if other.cells[i].passages != m.cells[i].passages:
			differs = true
			break
	# A generator that ignored its seed would pass the test above and fail this
	# one, so the pair together actually means something.
	_c("a different seed gives a different maze", differs)

	# --- clearance ----------------------------------------------------------
	print("=== clearance ===")
	_c("this configuration validates", m.validate() == "", m.validate())
	var tight = Maze.new()
	tight.rings = 7
	tight.chamber_radius = 2.0
	tight.ring_depth = 1.2
	tight.target_cell_width = 7.0
	tight.agent_clearance = 1.4
	var refused: String = tight.validate()
	_c("an impossible configuration is refused with a reason", refused != "",
		refused.substr(0, 64))

	print("")
	print("RESULT %s" % ("ALL PASS" if _ok else "FAILURES PRESENT"))
	_draw(m, solution)
	quit(0 if _ok else 1)


## Draws walls from the shared boundaries between cells that are NOT joined by a
## passage, so what is rendered is derived from the graph rather than asserted
## alongside it.
func _draw(m, solution: PackedInt32Array) -> void:
	var img := Image.create(IMG, IMG, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.07))
	var extent: float = m.chamber_radius + m.ring_depth * m.rings + 2.0
	var s := float(IMG) * 0.5 / extent
	var mid := Vector2(IMG, IMG) * 0.5

	var drawn := {}
	for c in m.cells:
		for nb in c.neighbours:
			var key := Vector2i(mini(c.id, nb), maxi(c.id, nb))
			if drawn.has(key):
				continue
			drawn[key] = true
			if c.passages.has(nb):
				continue
			var o = m.cells[nb]
			if c.ring == o.ring:
				var shared: float = c.a1 if absf(c.a1 - o.a0) < 1e-9 else c.a0
				var ang := shared * TAU
				var d := Vector2(cos(ang), sin(ang))
				_line(img, mid + d * c.r_inner * s, mid + d * c.r_outer * s,
					Color(0.8, 0.78, 0.72))
			else:
				var inner = c if c.ring < o.ring else o
				var outer = o if c.ring < o.ring else c
				var lo: float = maxf(inner.a0, outer.a0)
				var hi: float = minf(inner.a1, outer.a1)
				_arc(img, mid, outer.r_inner * s, lo, hi, Color(0.8, 0.78, 0.72))

	# Outer perimeter, minus the entrance.
	var last: PackedInt32Array = m.outer_ring()
	for id in last:
		if id == m.entrance_id:
			continue
		var c = m.cells[id]
		_arc(img, mid, c.r_outer * s, c.a0, c.a1, Color(0.85, 0.6, 0.35))

	# Solution.
	for i in range(solution.size() - 1):
		var a: Vector2 = m.safe_point(solution[i])
		var x: Vector2 = m.crossing(solution[i], solution[i + 1])
		var b: Vector2 = m.safe_point(solution[i + 1])
		_line(img, mid + a * s, mid + x * s, Color(0.35, 0.95, 0.5))
		_line(img, mid + x * s, mid + b * s, Color(0.35, 0.95, 0.5))

	var path := "user://circular_maze.png"
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _arc(img: Image, mid: Vector2, r: float, t0: float, t1: float, c: Color) -> void:
	var steps := maxi(int((t1 - t0) * TAU * r), 2)
	var prev := Vector2.ZERO
	for i in steps + 1:
		var t: float = lerpf(t0, t1, float(i) / float(steps)) * TAU
		var p := mid + Vector2(cos(t), sin(t)) * r
		if i > 0:
			_line(img, prev, p, c)
		prev = p


func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := maxi(int(a.distance_to(b)) + 1, 1)
	for t in steps + 1:
		var p := a.lerp(b, float(t) / float(steps))
		var px := int(p.x)
		var py := int(p.y)
		if px >= 0 and px < IMG and py >= 0 and py < IMG:
			img.set_pixel(px, py, c)
