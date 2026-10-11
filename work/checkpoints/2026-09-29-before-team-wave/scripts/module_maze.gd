extends RefCounted

## A maze laid out as a grid of SOLID TUNNEL SECTIONS.
##
## The kit this replaces tiled flat wall panels along a curved boundary, and
## everything that went wrong with it came from that: panels stepping against
## each other at bends, seams opening to the skybox, collision that could not
## follow the curve, and a texture that restarted on every panel. A section
## carries its own floor, walls and vault as one piece, so none of those joins
## exist to go wrong.
##
## The cost is that solid sections are straight, so the maze has to live on a
## grid. That is what this file is: a grid maze whose cells never exceed three
## connections, plus the lookup from a cell's open sides to which section to
## place and how far to turn it.
##
## Tripo was asked for a corner and returned a four-way cross, so crossings are
## free and there is no degree cap. `max_degree` is kept as an argument because
## the cap has to be applied while CARVING if it is ever wanted again: this is
## a spanning tree, every edge is a bridge, and removing one afterwards to
## reduce a degree would cut the maze in half.

## Sides, as bit flags. North is -Z, matching the game's `tile_to_world`.
const N := 1
const E := 2
const S := 4
const W := 8

const DIRS := {
	N: Vector2i(0, -1),
	E: Vector2i(1, 0),
	S: Vector2i(0, 1),
	W: Vector2i(-1, 0),
}
## The order used when a mask is rotated, so a turn of one step maps N->E->S->W.
const ORDER := [N, E, S, W]


class Cell extends RefCounted:
	var pos: Vector2i
	## Bit mask of the sides that are open.
	var open := 0
	## "straight", "corner", "tee", "cross", "dead", "gate" or "court".
	var kind := ""
	## Quarter-turns clockwise about +Y to apply to the module.
	var turn := 0
	## Index into the carve's `rooms`, or -1 for an ordinary corridor cell.
	var room := -1
	## Open-sky floor inside a room. It gets no module at all -- no walls, no
	## roof -- which is what makes the room open to the sky.
	var court := false


## Carves a grid maze and returns {cells: Dictionary of Vector2i -> Cell,
## order: Array[Vector2i] in carve order}.
##
## `size` is in cells. Deterministic from `seed_value`: every draw comes from a
## local generator, never `randi()` or `Array.shuffle()`, both of which read the
## global stream and would make the same seed produce different mazes depending
## on what else had run first.
## `arena_half` reserves a square of (2 * arena_half + 1) cells at the centre
## for the boss room. Those cells are left out of `cells` entirely and the
## carve routes around them; afterwards the arena is joined to the maze at the
## middle of each of its four sides, which is where the big room's archways
## are. Pass 0 for no arena.
static func carve(seed_value: int, size: Vector2i, max_degree: int = 4,
		arena_half: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var centre := Vector2i(size.x / 2, size.y / 2)
	var arena := {}
	if arena_half > 0:
		for dx in range(-arena_half, arena_half + 1):
			for dy in range(-arena_half, arena_half + 1):
				arena[centre + Vector2i(dx, dy)] = true

	var cells := {}
	var order: Array[Vector2i] = []
	# Start beside the arena rather than inside it. Starting in a reserved
	# cell would seed the whole maze somewhere it is not allowed to be.
	var start := centre
	while arena.has(start):
		start += Vector2i(0, 1)
		if start.y >= size.y:
			start = Vector2i(0, 0)
			break
	var first := Cell.new()
	first.pos = start
	cells[start] = first
	order.append(start)

	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var at: Vector2i = stack[stack.size() - 1]
		var here: Cell = cells[at]
		# A cell already at capacity cannot host another opening, so it stops
		# being a place to grow from even if it has unvisited neighbours.
		var options: Array[int] = []
		if _degree(here.open) < max_degree:
			for side in ORDER:
				var step: Vector2i = DIRS[side]
				var to: Vector2i = at + step
				if to.x < 0 or to.y < 0 or to.x >= size.x or to.y >= size.y:
					continue
				if cells.has(to) or arena.has(to):
					continue
				options.append(side)
		if options.is_empty():
			stack.pop_back()
			continue
		var side: int = options[rng.randi_range(0, options.size() - 1)]
		var to: Vector2i = at + DIRS[side]
		var made := Cell.new()
		made.pos = to
		made.open = _opposite(side)
		here.open |= side
		cells[to] = made
		order.append(to)
		stack.append(to)

	# A degree cap, or an arena wedged against the rim, can leave a pocket the
	# carve never reached. Those cells simply do not exist as corridor; that
	# is fine, but anything that assumes a full grid must not be handed one.
	var doors: Array[Vector2i] = []
	if arena_half > 0:
		doors = _join_arena(cells, arena, centre, arena_half, size)

	for key in cells:
		_classify(cells[key])
	return {
		"cells": cells,
		"order": order,
		"arena": arena,
		"arena_centre": centre if arena_half > 0 else Vector2i(-1, -1),
		"arena_half": arena_half,
		"arena_doors": doors,
	}


## Opens the arena to the maze at the middle of each of its four sides.
##
## Those are the only places it can join: the big room is one scaled module
## with one archway per side, centred. A corridor arriving anywhere else would
## run into blank wall, which is exactly the "dead end into a wall" the user
## reported on the previous level.
static func _join_arena(cells: Dictionary, arena: Dictionary, centre: Vector2i,
		half: int, size: Vector2i) -> Array[Vector2i]:
	var doors: Array[Vector2i] = []
	for side in ORDER:
		var step: Vector2i = DIRS[side]
		# One cell beyond the arena's edge, straight out from its middle.
		var outside: Vector2i = centre + step * (half + 1)
		if outside.x < 0 or outside.y < 0 or outside.x >= size.x or outside.y >= size.y:
			continue
		if not cells.has(outside):
			continue
		# The corridor cell opens back toward the arena. The arena itself is
		# not a Cell and keeps no mask; its archways are part of its mesh.
		var cell: Cell = cells[outside]
		cell.open |= _opposite(side)
		doors.append(outside)
	return doors


## Lays the ORGANIC maze out on the module grid.
##
## `scripts/maze_graph.gd` produces the sprawling, bowed-corridor map with a
## round arena, chambers, dead ends and long cross-map links. Its corridors
## run at arbitrary angles, and a solid tunnel section is a rigid square box,
## so the curves themselves cannot be built. What carries over is everything
## else: the footprint, the topology, the chambers, the dead ends and the
## sense of being lost. Corridors come out on right angles.
##
## The corridor POLYLINES are drawn onto the grid, like lines into a bitmap.
##
## The first attempt sampled the graph's distance field instead -- open any
## cell the network passes within half a cell of -- and it produced a solid
## disc of floor with a few islands of rock in it, nothing like a maze. A
## corridor is 4.4 m wide and the cells are 6 m, so a distance test that is
## loose enough not to drop cells is loose enough to swallow the rock between
## neighbouring corridors. Following the centrelines keeps corridors one cell
## wide however coarse the grid is, and a diagonal run becomes a staircase
## rather than a smear.
##
## ## Rooms
##
## The boss room and the chest rooms are CLOISTERS: a square block of cells in
## which every cell opens onto every neighbour inside the block. Nothing new is
## needed to build one, because the ordinary module kinds fall straight out of
## that rule -- a cell on the ring has one outside neighbour, so it becomes a
## T with its wall facing out and archways along the ring and into the middle;
## a ring corner becomes a corner piece; and the cells inside the ring become
## `court`, which gets no module at all. No walls and no roof over the middle
## is what makes the room open to the sky, and the ring of arches round it is
## the arcade -- which is also where the pillars the rooms were meant to have
## come from, since each pair of neighbouring arches meets on a pier.
##
## Corridors that ran into a room's footprint become its entrances, so a room
## is entered wherever the organic map had a route through that spot.
static func carve_from_graph(graph, size: Vector2i, cell_size: float,
		boss_half: int = 3, chest_half: int = 2, chest_count: int = 5) -> Dictionary:
	var cells := {}

	for line in graph.corridors:
		var prev := Vector2i(-9999, -9999)
		for p in line:
			var at := _to_grid(p, size, cell_size)
			if at == prev:
				continue
			if at.x < 0 or at.y < 0 or at.x >= size.x or at.y >= size.y:
				prev = Vector2i(-9999, -9999)
				continue
			if prev.x != -9999:
				_draw_run(cells, prev, at)
			else:
				_ensure(cells, at)
			prev = at

	var rooms := _choose_rooms(graph, size, cell_size, boss_half, chest_half, chest_count)
	for index in rooms.size():
		_build_room(cells, rooms[index], index)
	# A room nothing ran into would be sealed; give it one way in before
	# pruning, or pruning throws the whole room away as an island.
	for index in rooms.size():
		if (rooms[index]["entrances"] as Array).is_empty():
			_drive_entrance(cells, rooms[index], size)

	_keep_largest(cells)
	_close_dangling(cells, {})
	rooms = _finalise_rooms(cells, rooms)

	for key in cells:
		var cell: Cell = cells[key]
		if cell.court:
			cell.kind = "court"
			cell.turn = 0
		else:
			_classify(cell)
	return {
		"cells": cells,
		"order": cells.keys(),
		"rooms": rooms,
	}


## Picks where the rooms go: the boss room on the generator's arena, and chest
## rooms on its chambers, as many as fit without touching one another.
static func _choose_rooms(graph, size: Vector2i, cell_size: float, boss_half: int,
		chest_half: int, chest_count: int) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	var boss_at := _fit_room(_to_grid(graph.boss_centre, size, cell_size), boss_half, size)
	rooms.append({"kind": "boss", "centre": boss_at, "half": boss_half, "entrances": []})

	# Chambers first, because they are where the organic map meant a room to
	# be. The corridor junctions come after as a fallback, furthest from the
	# boss first, so if the chambers are too close together to all take a
	# room the extra ones still spread out rather than bunching.
	var candidates: Array[Vector2] = []
	candidates.append_array(graph.chamber_centres())
	var nodes: Array[Vector2] = []
	for p in graph.nodes:
		nodes.append(p)
	nodes.sort_custom(func(a, b):
		return a.distance_squared_to(graph.boss_centre) > b.distance_squared_to(graph.boss_centre))
	candidates.append_array(nodes)

	var placed := 0
	for world in candidates:
		if placed >= chest_count:
			break
		var at := _fit_room(_to_grid(world, size, cell_size), chest_half, size)
		if not _room_fits(rooms, at, chest_half, size):
			continue
		rooms.append({"kind": "chest", "centre": at, "half": chest_half, "entrances": []})
		placed += 1
	return rooms


## Nudges a room inward so it stays a cell clear of the grid's edge.
static func _fit_room(at: Vector2i, half: int, size: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(at.x, half + 1, size.x - half - 2),
		clampi(at.y, half + 1, size.y - half - 2))


## A room must keep at least one full cell of corridor between it and any
## other room. Touching blocks would merge into one room with a wall running
## through the middle of it.
static func _room_fits(rooms: Array[Dictionary], at: Vector2i, half: int,
		size: Vector2i) -> bool:
	if at.x - half < 1 or at.y - half < 1:
		return false
	if at.x + half > size.x - 2 or at.y + half > size.y - 2:
		return false
	for other in rooms:
		var c: Vector2i = other["centre"]
		var gap: int = half + int(other["half"]) + 1
		if absi(at.x - c.x) <= gap and absi(at.y - c.y) <= gap:
			return false
	return true


static func _in_block(p: Vector2i, centre: Vector2i, half: int) -> bool:
	return absi(p.x - centre.x) <= half and absi(p.y - centre.y) <= half


## Replaces a room's footprint with the room itself.
static func _build_room(cells: Dictionary, room: Dictionary, index: int) -> void:
	var c: Vector2i = room["centre"]
	var h: int = room["half"]

	# Remember every corridor that ran into the footprint before erasing it:
	# each one becomes an entrance, so the room is entered where the organic
	# map already had a route.
	var ways_in: Array = []
	for dx in range(-h, h + 1):
		for dy in range(-h, h + 1):
			var p := c + Vector2i(dx, dy)
			if absi(dx) != h and absi(dy) != h:
				continue
			for side in ORDER:
				var outside: Vector2i = p + DIRS[side]
				if _in_block(outside, c, h) or not cells.has(outside):
					continue
				if (cells[outside] as Cell).open & _opposite(side):
					ways_in.append([p, side])

	for dx in range(-h, h + 1):
		for dy in range(-h, h + 1):
			cells.erase(c + Vector2i(dx, dy))

	for dx in range(-h, h + 1):
		for dy in range(-h, h + 1):
			var p := c + Vector2i(dx, dy)
			var cell := Cell.new()
			cell.pos = p
			cell.room = index
			cell.court = absi(dx) < h and absi(dy) < h
			for side in ORDER:
				if _in_block(p + DIRS[side], c, h):
					cell.open |= side
			cells[p] = cell

	for way in ways_in:
		var p: Vector2i = way[0]
		var side: int = way[1]
		(cells[p] as Cell).open |= side
	room["entrances"] = ways_in


## Cuts a corridor out from the side of a room nearest the rest of the maze.
static func _drive_entrance(cells: Dictionary, room: Dictionary, size: Vector2i) -> void:
	var c: Vector2i = room["centre"]
	var h: int = room["half"]
	var best: Array[Vector2i] = []
	var best_side := -1
	for side in ORDER:
		var step: Vector2i = DIRS[side]
		var at: Vector2i = c + step * (h + 1)
		var path: Array[Vector2i] = []
		var hit := false
		while at.x >= 0 and at.y >= 0 and at.x < size.x and at.y < size.y:
			if cells.has(at):
				hit = true
				break
			path.append(at)
			at += step
		if hit and (best_side < 0 or path.size() < best.size()):
			best = path
			best_side = side
	if best_side < 0:
		return
	var step: Vector2i = DIRS[best_side]
	var from: Vector2i = c + step * h
	(cells[from] as Cell).open |= best_side
	var prev := from
	for at in best:
		var cell := _ensure(cells, at)
		cell.open |= _opposite(best_side)
		(cells[prev] as Cell).open |= best_side
		prev = at
	var end: Vector2i = prev + step
	(cells[prev] as Cell).open |= best_side
	(cells[end] as Cell).open |= _opposite(best_side)
	room["entrances"] = [[from, best_side]]


## Drops rooms that did not survive pruning and records their real entrances.
static func _finalise_rooms(cells: Dictionary, rooms: Array[Dictionary]) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for room in rooms:
		var c: Vector2i = room["centre"]
		var h: int = room["half"]
		if not cells.has(c):
			continue
		var ways: Array = []
		for dx in range(-h, h + 1):
			for dy in range(-h, h + 1):
				var p := c + Vector2i(dx, dy)
				if absi(dx) != h and absi(dy) != h:
					continue
				var cell: Cell = cells[p]
				for side in ORDER:
					var outside: Vector2i = p + DIRS[side]
					if _in_block(outside, c, h):
						continue
					if (cell.open & side) and cells.has(outside):
						ways.append({"cell": p, "side": side})
		room["entrances"] = ways
		kept.append(room)
	# Re-index, so a cell's `room` still points at its own entry.
	for index in kept.size():
		var room: Dictionary = kept[index]
		var c: Vector2i = room["centre"]
		var h: int = room["half"]
		for dx in range(-h, h + 1):
			for dy in range(-h, h + 1):
				(cells[c + Vector2i(dx, dy)] as Cell).room = index
	return kept


static func _ensure(cells: Dictionary, at: Vector2i) -> Cell:
	if not cells.has(at):
		var cell := Cell.new()
		cell.pos = at
		cells[at] = cell
	return cells[at]


## Connects two cells with an L: all of one axis, then all of the other.
##
## Consecutive samples along a curve can be a knight's move apart, and the two
## cells are then not neighbours at all. Stepping one axis at a time turns the
## curve into a staircase of real corridor rather than leaving a break.
static func _draw_run(cells: Dictionary, from: Vector2i, to: Vector2i) -> void:
	var at := from
	_ensure(cells, at)
	while at.x != to.x:
		var side: int = E if to.x > at.x else W
		var next: Vector2i = at + DIRS[side]
		_ensure(cells, at).open |= side
		_ensure(cells, next).open |= _opposite(side)
		at = next
	while at.y != to.y:
		var side: int = S if to.y > at.y else N
		var next: Vector2i = at + DIRS[side]
		_ensure(cells, at).open |= side
		_ensure(cells, next).open |= _opposite(side)
		at = next


static func _to_world(grid: Vector2i, size: Vector2i, cell_size: float) -> Vector2:
	return Vector2(
		(float(grid.x) - (float(size.x) - 1.0) * 0.5) * cell_size,
		(float(grid.y) - (float(size.y) - 1.0) * 0.5) * cell_size)


static func _to_grid(world: Vector2, size: Vector2i, cell_size: float) -> Vector2i:
	return Vector2i(
		int(round(world.x / cell_size + (float(size.x) - 1.0) * 0.5)),
		int(round(world.y / cell_size + (float(size.y) - 1.0) * 0.5)))



## Throws away anything the player could never walk to.
##
## Sampling a curved network onto a coarse grid always leaves a few islands --
## a chamber the corridor only clipped, a spur that fell between samples. They
## would render as sealed pockets of stone and confuse every spawner, so they
## go. The component kept is the one holding the hall.
static func _keep_largest(cells: Dictionary) -> void:
	if cells.is_empty():
		return
	var seen := {}
	var best: Dictionary = {}
	for key in cells:
		if seen.has(key):
			continue
		var group := {}
		var stack: Array[Vector2i] = [key]
		seen[key] = true
		group[key] = true
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			var cell: Cell = cells[at]
			for side in ORDER:
				if not (cell.open & side):
					continue
				var to: Vector2i = at + DIRS[side]
				if not cells.has(to) or seen.has(to):
					continue
				seen[to] = true
				group[to] = true
				stack.append(to)
		if group.size() > best.size():
			best = group
	for key in cells.keys():
		if not best.has(key):
			cells.erase(key)
## Closes any opening that points at nothing, and drops cells left sealed.
static func _close_dangling(cells: Dictionary, arena: Dictionary) -> void:
	# Openings that point at a discarded cell have to be closed, or the
	# module placed there has an archway onto solid rock.
	#
	# The ARENA is the exception, and missing it cost an hour: its nine cells
	# are deliberately absent from `cells`, so a blanket "close anything that
	# points at a cell I do not have" walls up all four of the hall's mouths
	# straight after they were opened. The hall then rasterised as a sealed
	# island of 181 tiles in the middle of the map.
	for key in cells:
		var cell: Cell = cells[key]
		for side in ORDER:
			var to: Vector2i = cell.pos + DIRS[side]
			if (cell.open & side) and not cells.has(to) and not arena.has(to):
				cell.open &= ~side
	# A cell left with no openings at all is a sealed box of stone that no
	# module can represent -- `_classify` has nothing to place there.
	for key in cells.keys():
		if (cells[key] as Cell).open == 0:
			cells.erase(key)


## Which section a cell needs, and how far to turn it.
##
## The canonical orientation of each section, which the placement code and the
## generated meshes must agree on:
##   straight  open N and S      (runs along Z)
##   corner    open N and E
##   tee       open N, E and S   (solid on W)
##   cross     open on all four
##   dead      open N only
##
## `gate` shares the dead end's shape and is chosen later, for the two cells
## `pick_exits` selects; every other leaf gets the plain `dead`.
static func _classify(cell: Cell) -> void:
	var degree := _degree(cell.open)
	if degree == 4:
		cell.kind = "cross"
		cell.turn = 0
		return
	for turn in 4:
		var mask := _rotate(cell.open, -turn)
		if degree == 2 and mask == (N | S):
			cell.kind = "straight"
			cell.turn = turn
			return
		if degree == 2 and mask == (N | E):
			cell.kind = "corner"
			cell.turn = turn
			return
		if degree == 3 and mask == (N | E | S):
			cell.kind = "tee"
			cell.turn = turn
			return
		if degree == 1 and mask == N:
			cell.kind = "dead"
			cell.turn = turn
			return
	# An isolated cell should be impossible, because every cell is carved from
	# a neighbour and so starts with one opening. If one appears, something
	# upstream changed, and silently placing the wrong section -- a blank wall
	# across a corridor the player is meant to walk down -- would be worse
	# than saying so.
	push_error("module_maze: cell %s has an unplaceable mask %d (degree %d)"
		% [cell.pos, cell.open, degree])
	cell.kind = "dead"
	cell.turn = 0


static func _degree(mask: int) -> int:
	var n := 0
	for side in ORDER:
		if mask & side:
			n += 1
	return n


static func _opposite(side: int) -> int:
	match side:
		N: return S
		S: return N
		E: return W
		_: return E


## Rotates a side mask by `turn` quarter-turns clockwise.
static func _rotate(mask: int, turn: int) -> int:
	var out := 0
	for i in ORDER.size():
		if mask & ORDER[i]:
			out |= ORDER[(i + ((turn % 4) + 4)) % 4]
	return out


## The dead ends furthest apart, for the locked doorways into future zones.
##
## Picked from the OUTER edge and by mutual distance, because two exits side by
## side in the middle of the map do not read as the edges of the world. Returns
## up to `count` cell positions.
static func pick_exits(carved: Dictionary, size: Vector2i, count: int) -> Array:
	var cells: Dictionary = carved["cells"]
	var candidates: Array[Vector2i] = []
	for key in cells:
		var cell: Cell = cells[key]
		if _degree(cell.open) != 1:
			continue
		# Out near the edge of the MAP, by distance from its middle, rather
		# than near the edge of the grid array. The organic footprint is a
		# rough disc inside a square grid, so its outermost dead ends are
		# nowhere near the array bounds.
		var mid := Vector2(float(size.x - 1), float(size.y - 1)) * 0.5
		var reach: float = mid.length() * 0.55
		if Vector2(cell.pos).distance_to(mid) < reach:
			continue
		candidates.append(cell.pos)
	if candidates.size() <= count:
		return candidates

	# Greedy farthest-point: take the pair that are furthest apart, which for
	# two exits is the whole selection.
	var best_a := candidates[0]
	var best_b := candidates[0]
	var best := -1.0
	for i in candidates.size():
		for j in range(i + 1, candidates.size()):
			var d: float = Vector2(candidates[i]).distance_squared_to(Vector2(candidates[j]))
			if d > best:
				best = d
				best_a = candidates[i]
				best_b = candidates[j]
	var out: Array[Vector2i] = [best_a, best_b]
	while out.size() < count:
		var far := candidates[0]
		var far_d := -1.0
		for c in candidates:
			if c in out:
				continue
			var nearest := INF
			for chosen in out:
				nearest = minf(nearest, Vector2(c).distance_squared_to(Vector2(chosen)))
			if nearest > far_d:
				far_d = nearest
				far = c
		out.append(far)
	return out
