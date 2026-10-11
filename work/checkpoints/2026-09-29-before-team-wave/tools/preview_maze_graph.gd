extends SceneTree

## Previews the organic graph maze without touching the game.
##
##   godot --headless --path . --script res://tools/preview_maze_graph.gd
##
## Renders the walkable region, the corridor centrelines, and the smoothed wall
## contour, and reports connectivity and clearance. Nothing here ships; it
## exists so layout decisions are made against a picture and numbers rather than
## against an idea of what the generator probably does.

const Graph = preload("res://scripts/maze_graph.gd")
const Contour = preload("res://scripts/wall_contour.gd")

const RES := 480          # raster cells across the map
const IMG := 1100
const EXTENT := 86.0      # world half-size


func _initialize() -> void:
	var g = Graph.new()
	# Sized so that after the doorway gaps are cut, roughly 30 cells survive --
	# the Warden releases 10 at a time, three times.
	g.boss_radius = 30.0
	g.corridor_radius = 2.9
	g.cell_radius = 2.3
	# Two doors only, so most of the arena rim is solid and it takes finding.
	g.boss_doors = 2
	g.generate(20260925, EXTENT, 13.0, 10, 7.0, 10.0)
	var cell_count: int = g.safe_cell_count(1.8)
	g.build_cells(cell_count)
	g._build_index()

	print("nodes      %d" % g.nodes.size())
	print("corridors  %d  (tree would be %d, so %d loop links)"
		% [g.corridors.size(), g.nodes.size() - 1,
			g.corridors.size() - (g.nodes.size() - 1)])
	print("chambers   %d" % g.chamber_at.size())
	# Counted from the edges that actually touch the arena, not from
	# boss_door_dirs -- that counter cannot exceed its own target, so it
	# reported success while a third corridor was being forced in elsewhere.
	var mouths := 0
	for e in g.edges:
		if e.x == 0 or e.y == 0:
			mouths += 1
	var doors_ok: bool = mouths == g.boss_doors
	print("doors      %d corridors reach the arena (want %d) %s"
		% [mouths, g.boss_doors, "" if doors_ok else "  <-- WRONG"])
	var sep := 0.0
	if g.boss_door_dirs.size() == 2:
		sep = rad_to_deg(absf(g.boss_door_dirs[0].angle_to(g.boss_door_dirs[1])))
		print("           %.1f deg apart" % sep)
	var hops: PackedInt32Array = g.hops_from(0)
	var spawn: int = g.spawn_node
	print("spawn      node %d, %d corridors from the arena, %.0f m away as the crow flies"
		% [spawn, hops[spawn], g.nodes[spawn].length()])
	var reachable := 0
	var deepest := 0
	for h in hops:
		if h >= 0:
			reachable += 1
			deepest = maxi(deepest, h)
	print("depth      every node reachable: %s, deepest %d corridors"
		% [reachable == g.nodes.size(), deepest])
	print("cells      %d of %d requested (%d skipped for doorways), rock between %.2f m"
		% [g.cells.size(), cell_count, cell_count - g.cells.size(),
			g.cell_gap(cell_count)])

	# --- rasterise -----------------------------------------------------------
	var cell := (EXTENT * 2.0) / float(RES)
	var solid := []
	var open_count := 0
	for y in RES:
		var row := []
		row.resize(RES)
		for x in RES:
			var p := Vector2(-EXTENT + (x + 0.5) * cell, -EXTENT + (y + 0.5) * cell)
			var o: bool = g.inside(p)
			row[x] = o
			if o:
				open_count += 1
		solid.append(row)
	print("open cells %d of %d (%.1f%%)" % [open_count, RES * RES,
		100.0 * open_count / float(RES * RES)])

	# --- connectivity --------------------------------------------------------
	var seen := []
	for y in RES:
		var r := []
		r.resize(RES)
		r.fill(false)
		seen.append(r)
	var components := 0
	var largest := 0
	for y in RES:
		for x in RES:
			if not solid[y][x] or seen[y][x]:
				continue
			components += 1
			var size := 0
			var stack := [Vector2i(x, y)]
			seen[y][x] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				size += 1
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= RES or n.y >= RES:
						continue
					if solid[n.y][n.x] and not seen[n.y][n.x]:
						seen[n.y][n.x] = true
						stack.append(n)
			largest = maxi(largest, size)
	print("components %d, largest holds %.1f%% of the floor"
		% [components, 100.0 * largest / maxf(open_count, 1)])
	var connected := components == 1

	# --- cells must open ONLY into the boss room -----------------------------
	# A corridor grazing the rim would merge with an alcove and put a back door
	# into the arena: skeletons out, player in past the gate. Blank out the
	# boss disc and check no cell is still reachable from the rest of the maze.
	var blocked := []
	for y in RES:
		var r := []
		r.resize(RES)
		for x in RES:
			var p := Vector2(-EXTENT + (x + 0.5) * cell, -EXTENT + (y + 0.5) * cell)
			r[x] = solid[y][x] and p.distance_to(g.boss_centre) > g.boss_radius
		blocked.append(r)
	var outer := _flood(blocked, _cell_of(g.nodes[g.nodes.size() - 1], cell))
	var leaks := 0
	for c in g.cells:
		var ci := _cell_of(c, cell)
		if ci.x < 0 or ci.y < 0 or ci.x >= RES or ci.y >= RES or not outer[ci.y][ci.x]:
			continue
		leaks += 1
		# Say WHAT is leaking into it, rather than leaving the cause to guesswork.
		var near_corr := INF
		for line in g.corridors:
			for k in range(line.size() - 1):
				near_corr = minf(near_corr,
					Graph._to_segment(c, line[k], line[k + 1]))
		var near_cham := INF
		for i in g.chamber_at.keys():
			near_cham = minf(near_cham,
				c.distance_to(g.nodes[i]) - float(g.chamber_at[i]))
		var near_door := INF
		for d in g.boss_door_dirs:
			near_door = minf(near_door, absf(c.angle_to(d)))
		print("   leak at %5.1f deg r=%.1f : corridor %.2f m, chamber edge %.2f m, nearest door %4.1f deg"
			% [rad_to_deg(c.angle()), c.length(), near_corr - g.corridor_radius,
				near_cham, rad_to_deg(near_door)])
	print("cell leaks %d  (alcoves reachable without entering the arena)" % leaks)

	# --- wall contour --------------------------------------------------------
	var open_at := func(x: int, z: int) -> bool:
		if x < 0 or z < 0 or x >= RES or z >= RES:
			return false
		return solid[z][x]
	var raw := Contour.trace(open_at, RES)
	var loops: Array[PackedVector2Array] = []
	var pts := 0
	for loop in raw:
		var l: PackedVector2Array = Contour.resample(loop, 1.2)
		l = Contour.smooth(l, 3)
		loops.append(l)
		pts += l.size()
	print("wall loops %d, %d points after smoothing" % [loops.size(), pts])

	# Clearance is guaranteed by construction here -- the region is a union of
	# discs and capsules, and a union never narrows what it contains -- so this
	# confirms the corridor radius rather than hunting for a pinch.
	print("corridor half-width %.2f m (boss radius 1.2)" % g.corridor_radius)
	print("boss room diameter  %.1f m" % (g.boss_radius * 2.0))
	print("")
	var good: bool = connected and doors_ok and leaks == 0
	print("VERDICT: %s" % ("connected, walkable, %d doors, no leaks" % mouths
		if good else "FAILED - connected=%s doors=%d/%d leaks=%d"
		% [connected, mouths, g.boss_doors, leaks]))

	_draw(g, solid, loops, cell)
	quit(0 if good else 1)


func _draw(g, solid: Array, loops: Array, cell: float) -> void:
	var img := Image.create(IMG, IMG, false, Image.FORMAT_RGB8)
	img.fill(Color(0.07, 0.065, 0.08))
	var s := float(IMG) / float(RES)

	for y in RES:
		for x in RES:
			if not solid[y][x]:
				continue
			var px := int(x * s)
			var py := int(y * s)
			for dy in range(0, maxi(int(s) + 1, 1)):
				for dx in range(0, maxi(int(s) + 1, 1)):
					if px + dx < IMG and py + dy < IMG:
						img.set_pixel(px + dx, py + dy, Color(0.015, 0.012, 0.02))

	# corridor centrelines, dim
	for line in g.corridors:
		for k in range(line.size() - 1):
			_line(img, _to_px(line[k], cell, s), _to_px(line[k + 1], cell, s),
				Color(0.30, 0.16, 0.16))
	# wall contour
	for loop in loops:
		var n: int = loop.size()
		for i in n:
			_line(img, Vector2(loop[i]) * s, Vector2(loop[(i + 1) % n]) * s,
				Color(1.0, 0.76, 0.35))
	for c in g.cells:
		_dot(img, _to_px(c, cell, s), 2, Color(0.95, 0.55, 0.25))
	# nodes
	for i in g.nodes.size():
		var c := Color(0.45, 0.85, 1.0) if g.chamber_at.has(i) else Color(0.5, 0.5, 0.6)
		if i == 0:
			c = Color(1.0, 0.35, 0.35)
		_dot(img, _to_px(g.nodes[i], cell, s), 3, c)
	if g.spawn_node >= 0:
		_dot(img, _to_px(g.nodes[g.spawn_node], cell, s), 6, Color(0.4, 1.0, 0.45))

	var path := "user://maze_graph.png"
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _cell_of(p: Vector2, cell: float) -> Vector2i:
	return Vector2i(int((p.x + EXTENT) / cell), int((p.y + EXTENT) / cell))


## Reachable set from `start` over cells that are true in `mask`.
func _flood(mask: Array, start: Vector2i) -> Array:
	var seen := []
	for y in RES:
		var r := []
		r.resize(RES)
		r.fill(false)
		seen.append(r)
	if start.x < 0 or start.y < 0 or start.x >= RES or start.y >= RES:
		return seen
	if not mask[start.y][start.x]:
		return seen
	var stack := [start]
	seen[start.y][start.x] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= RES or n.y >= RES:
				continue
			if mask[n.y][n.x] and not seen[n.y][n.x]:
				seen[n.y][n.x] = true
				stack.append(n)
	return seen


func _to_px(p: Vector2, cell: float, s: float) -> Vector2:
	return Vector2((p.x + EXTENT) / cell * s, (p.y + EXTENT) / cell * s)


func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := maxi(int(a.distance_to(b)) + 1, 1)
	for t in steps + 1:
		var p := a.lerp(b, float(t) / float(steps))
		var px := int(p.x)
		var py := int(p.y)
		if px >= 0 and px < IMG and py >= 0 and py < IMG:
			img.set_pixel(px, py, c)


func _dot(img: Image, p: Vector2, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var px := int(p.x) + dx
			var py := int(p.y) + dy
			if px >= 0 and px < IMG and py >= 0 and py < IMG:
				img.set_pixel(px, py, c)
