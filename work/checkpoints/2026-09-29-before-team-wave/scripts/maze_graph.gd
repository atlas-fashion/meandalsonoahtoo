extends RefCounted

## An organic maze laid out as a graph of chambers joined by curved corridors,
## instead of corridors carved on a square grid.
##
## Nodes are scattered by dart-throwing with a minimum separation, joined into a
## spanning tree so every chamber is reachable, and each edge is bowed into a
## curve rather than drawn straight. The walkable region is then the union of
## those corridor capsules, the chamber discs, and a circular boss room at the
## centre.
##
## The region is defined analytically, as a signed distance. That matters for
## two different consumers:
##   * wall geometry samples it finely and gets smooth curves, independent of
##     any grid resolution;
##   * gameplay rasterises it onto the existing tile grid, so the spawner,
##     jail cells, gates and navmesh keep working against `is_open(tile)`
##     exactly as they did before.

var nodes: PackedVector2Array = PackedVector2Array()
## Which nodes are chambers rather than plain junctions, and how wide.
var chamber_at := {}
## One bowed polyline per corridor, in world XZ.
var corridors: Array[PackedVector2Array] = []
## The same corridors as node-index pairs, for graph queries.
var edges: Array[Vector2i] = []
## Where the player starts: the node furthest from the arena by corridor hops,
## so the boss room takes real exploring to find rather than being the first
## thing you walk into.
var spawn_node := -1

var boss_centre := Vector2.ZERO
var boss_radius := 24.0
var corridor_radius := 2.9

## Alcoves cut into the rim of the boss room, one skeleton each. They overlap
## the room slightly so each one opens into it through a mouth the cell door
## can fill, rather than being a sealed bubble in the rock.
var cells: PackedVector2Array = PackedVector2Array()
var cell_radius := 2.3
## How many corridors reach the boss room. One is a dead end for a boss fight;
## two is the approved direction, and leaves most of the rim solid so the arena
## takes finding.
var boss_doors := 2
## Which way each doorway leaves the arena. Cells cannot be built across these
## or the doorway carves straight through the alcove and opens a back way in.
var boss_door_dirs: Array[Vector2] = []

## Extra spacing between junctions, multiplying `min_sep` before nodes are
## scattered. Bigger gaps mean fewer junctions and a longer corridor between
## each pair of them -- the "walk for a while before choosing" knob -- and it
## also thins the pool the loop-link pass below draws from, so loops get
## rarer on their own, without a separate switch.
##
## There is deliberately no matching "make the map bigger" scale here: `extent`
## is not just this generator's own scatter radius, it is also the raster
## window every consumer traces the wall contour against (`_trace_contour()`
## in `maze.gd`, and this file's own preview tool) -- growing the graph past
## it without growing THEIR window clips the far edge of the map and reads as
## a disconnected island. "Bigger" is the caller raising `extent` itself
## (already exposed as `organic_extent` in `maze.gd`); everything below keeps
## working at whatever extent it is handed.
var junction_spacing_scale := 1.05
## Fraction of the node count drawn as extra loop links between nearby nodes,
## on top of the spanning tree. This is the cheapest lever in the file: a loop
## link never lengthens the corridor it doubles up on, it just gives a
## shortcut around it, so thinning them out is what actually turns short
## "which way now" hops into longer walks between real choices -- and, as a
## side effect, lets more of the tree's own leaves stay genuine dead ends
## instead of being looped back into the network. Down from the 0.22 this
## network used to carry as an unnamed constant.
var loop_link_fraction := 0.1

## Dead-end spurs added after the tree and its loops: each is one new node,
## joined to a random existing junction by exactly one corridor and given no
## loop link, so it goes somewhere and stops. The spanning tree already has a
## few leaves, but they are incidental and too few to read as "a maze" --
## these are deliberate.
var dead_end_spurs := 16
## How far a dead-end spur reaches from the junction it branches off, in
## metres. The actual reach is randomised between 60% and 100% of this.
var dead_end_reach := 22.0

## Long-range corridors added once chambers are placed, connecting two of them
## (or, short of two chambers, two ordinary junctions) that lie far apart.
## This is the "cross the map and come out somewhere unexpected" lever the
## lost-in-a-maze feeling depends on.
var long_link_count := 3
## Minimum straight-line separation for a long-range link, as a fraction of
## the map's diameter (2 * extent). At the default 86 m extent that is
## roughly 95 m -- long enough that the corridor visibly crosses the map
## rather than nudging two neighbouring chambers together.
var long_link_span_fraction := 0.55

var _rng := RandomNumberGenerator.new()
## New nodes added by `_add_dead_ends()`, so `_add_long_range_links()` can
## leave them alone -- wiring one back into the network would erase the very
## dead end it was created to be.
var _dead_end_ids: Array[int] = []

## Uniform-grid index over corridor segments. The region gets sampled hundreds
## of thousands of times when it is rasterised, and testing every segment each
## time is minutes of work for an answer that only ever depends on the handful
## of segments within a corridor's width.
const CELL := 8.0
var _index := {}
var _segments: Array[PackedVector2Array] = []


func _build_index() -> void:
	_index = {}
	_segments.clear()
	for line in corridors:
		for k in range(line.size() - 1):
			var a: Vector2 = line[k]
			var b: Vector2 = line[k + 1]
			_segments.append(PackedVector2Array([a, b]))
			var idx := _segments.size() - 1
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * corridor_radius
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * corridor_radius
			var x0 := int(floor(lo.x / CELL))
			var x1 := int(floor(hi.x / CELL))
			var y0 := int(floor(lo.y / CELL))
			var y1 := int(floor(hi.y / CELL))
			for cy in range(y0, y1 + 1):
				for cx in range(x0, x1 + 1):
					var key := Vector2i(cx, cy)
					if not _index.has(key):
						_index[key] = PackedInt32Array()
					_index[key].append(idx)


func generate(seed_value: int, extent: float, min_sep: float,
		chambers: int, chamber_min: float, chamber_max: float) -> void:
	_rng.seed = seed_value
	nodes = PackedVector2Array()
	chamber_at = {}
	corridors.clear()
	edges.clear()
	_dead_end_ids.clear()

	var min_sep_eff := min_sep * junction_spacing_scale

	_scatter(extent, min_sep_eff)
	_connect(min_sep_eff)
	_add_dead_ends(min_sep_eff, extent)
	_open_boss_doors()
	_pick_chambers(chambers, chamber_min, chamber_max, extent)
	_add_long_range_links(extent)
	spawn_node = furthest_from(0)


## Corridor hops from `start` to every node. -1 where unreachable.
func hops_from(start: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(nodes.size())
	out.fill(-1)
	if start < 0 or start >= nodes.size():
		return out
	var adjacency := {}
	for e in edges:
		if not adjacency.has(e.x):
			adjacency[e.x] = PackedInt32Array()
		if not adjacency.has(e.y):
			adjacency[e.y] = PackedInt32Array()
		adjacency[e.x].append(e.y)
		adjacency[e.y].append(e.x)
	out[start] = 0
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var at: int = queue[head]
		head += 1
		for nb in adjacency.get(at, PackedInt32Array()):
			if out[nb] == -1:
				out[nb] = out[at] + 1
				queue.append(nb)
	return out


## The node that takes the most corridors to reach from `start`.
func furthest_from(start: int) -> int:
	var hops := hops_from(start)
	var best := start
	var best_hops := -1
	for i in hops.size():
		if hops[i] > best_hops:
			best_hops = hops[i]
			best = i
	return best


## Rings the boss room with cells. Spacing is derived from the count so the rock
## between neighbours never goes thinner than a wall panel can represent.
func build_cells(count: int) -> void:
	cells = PackedVector2Array()
	if count <= 0:
		return
	var ring := boss_radius + cell_radius * 0.55
	# Angular half-width of the hole a doorway punches through the rim, plus a
	# cell's own reach and a margin of rock.
	var block: float = (corridor_radius + cell_radius + 1.5) / ring
	for i in count:
		var a := TAU * float(i) / float(count)
		var dir := Vector2(cos(a), sin(a))
		var clear := true
		for d in boss_door_dirs:
			if absf(dir.angle_to(d)) < block:
				clear = false
				break
		if not clear:
			continue

		# Then test the position itself against everything already carved.
		# Reasoning about keep-out radii kept missing cases -- a chord between
		# two nodes on the ring dips closer to the middle than either end does
		# -- so this asks the direct question instead: is this spot actually
		# clear? A cell that is not gets skipped rather than opening the arena
		# from behind.
		var here := boss_centre + dir * ring
		var need := cell_radius + 0.8
		for line in corridors:
			for k in range(line.size() - 1):
				if _to_segment(here, line[k], line[k + 1]) < corridor_radius + need:
					clear = false
					break
			if not clear:
				break
		if clear:
			for ch in chamber_at.keys():
				if here.distance_to(nodes[ch]) < float(chamber_at[ch]) + need:
					clear = false
					break
		if clear:
			cells.append(here)
	_index = {}


## Gap between neighbouring cell mouths, in metres. Negative means they have
## merged into a trench and stopped being separate cells.
func cell_gap(count: int) -> float:
	if count < 2:
		return INF
	var ring := boss_radius + cell_radius * 0.55
	var step := TAU * ring / float(count)
	return step - cell_radius * 2.0


## The most cells this arena can hold while keeping `min_rock` metres of stone
## between neighbours.
##
## How many cells there are is decided by the circumference, not by preference:
## asking for more than this merges them into a continuous trench, which both
## stops them reading as cells and opens the arena from behind. Ask for the
## number the geometry allows, and let the Warden release what exists.
func safe_cell_count(min_rock: float) -> int:
	var ring := boss_radius + cell_radius * 0.55
	return int(floor(TAU * ring / (cell_radius * 2.0 + min_rock)))


## A boss arena with one entrance is a corridor with a monster at the end. Force
## several approaches, spread around the rim rather than clustered.
func _open_boss_doors() -> void:
	var order: Array[int] = []
	for i in range(1, nodes.size()):
		order.append(i)
	order.sort_custom(func(a, b):
		return nodes[a].length_squared() < nodes[b].length_squared())
	boss_door_dirs.clear()
	var taken: Array[Vector2] = []
	var opened := 0
	for i in order:
		if opened >= boss_doors:
			break
		var dir := nodes[i].normalized()
		# With only a couple of doors they have to be pushed much further apart,
		# or both end up on the same side and half the arena is unreachable
		# without walking all the way round.
		var too_close: float = 0.35 if boss_doors > 2 else -0.15
		var clash := false
		for t in taken:
			if t.dot(dir) > too_close:
				clash = true
				break
		if clash:
			continue
		taken.append(dir)
		boss_door_dirs.append(dir)
		_add_corridor(0, i, true)
		opened += 1

	# Falling short used to be silent, which is the failure the separation rule
	# exists to prevent: an arena with one way in is a corridor with a monster
	# at the end. Relax the spread rather than ship that, and say so if even
	# that cannot manage it.
	if opened < boss_doors:
		for i in order:
			if opened >= boss_doors:
				break
			var dir := nodes[i].normalized()
			var seen := false
			for d in boss_door_dirs:
				if d.is_equal_approx(dir):
					seen = true
					break
			if seen:
				continue
			boss_door_dirs.append(dir)
			_add_corridor(0, i, true)
			opened += 1
	if opened < boss_doors:
		push_error("maze_graph: only %d of %d boss doors could be opened"
			% [opened, boss_doors])


## Dart throwing. Cheap and adequate for a few hundred points, and unlike a
## lattice it produces no preferred direction -- which is the whole point.
func _scatter(extent: float, min_sep: float) -> void:
	var ring := boss_radius + min_sep * 0.9
	var tries := 0
	while tries < 20000 and nodes.size() < 400:
		tries += 1
		var p := Vector2(
			_rng.randf_range(-extent, extent),
			_rng.randf_range(-extent, extent))
		if p.length() > extent:
			continue
		# Leave the boss room its own space, but keep a ring of nodes close
		# enough that corridors actually reach its doors.
		if p.length() < ring:
			continue
		var ok := true
		for q in nodes:
			if p.distance_squared_to(q) < min_sep * min_sep:
				ok = false
				break
		if ok:
			nodes.append(p)

	# The boss room is node 0 so corridors can be attached to it like any other.
	var all := PackedVector2Array([boss_centre])
	all.append_array(nodes)
	nodes = all


## Randomised Prim over a nearest-neighbour graph: a spanning tree, so every
## chamber is reachable and there is exactly one route between any two. A few
## extra edges are added afterwards so the place has loops and does not read as
## a pure tree.
func _connect(min_sep: float) -> void:
	var n := nodes.size()
	if n < 3:
		return
	# Prim is seeded from a scattered node, NOT the arena.
	#
	# Seeding from node 0 meant the first iteration could only pick the arena as
	# its attachment point. _add_corridor correctly refused that -- a curve
	# starting at the boss centre is zero metres from it, well inside the
	# keep-out -- but the fallback then had a one-element list to re-route
	# through, found nothing, and forced the corridor anyway. The result was a
	# third, uncounted mouth into the arena on every seed, while
	# `boss_door_dirs` reported the two that _open_boss_doors had added.
	#
	# With the arena kept out of `pending` entirely, the only edges it can ever
	# receive are the doors, which makes the count an invariant rather than a
	# hope.
	var joined := [1]
	var pending := {}
	for i in range(2, n):
		pending[i] = true

	while not pending.is_empty():
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for a in joined:
			for b in pending.keys():
				var d: float = nodes[a].distance_squared_to(nodes[b])
				# Jittered so the tree is not strictly nearest-neighbour, which
				# would look regular.
				d *= _rng.randf_range(1.0, 1.35)
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		if best_b < 0:
			break
		# If the nearest attachment would cut through the cell ring, attach the
		# node somewhere else instead. Forcing it through -- which is what this
		# used to do -- opens alcoves from behind and puts a back door into the
		# arena. Only strand-avoidance justifies punching through, and that is
		# the last resort after every joined node has been tried.
		if not _add_corridor(best_a, best_b):
			var alts := joined.duplicate()
			alts.sort_custom(func(p, q):
				return nodes[p].distance_squared_to(nodes[best_b]) \
					< nodes[q].distance_squared_to(nodes[best_b]))
			var linked := false
			for alt in alts:
				if alt == best_a:
					continue
				if _add_corridor(alt, best_b):
					linked = true
					break
			if not linked:
				_add_corridor(best_a, best_b, true)
		joined.append(best_b)
		pending.erase(best_b)

	# Extra links, so there is more than one way around and the place does not
	# read as a tree of dead ends.
	#
	# Drawn from the pairs that are actually close, not from random pairs: with
	# 49 nodes spread over 130 m, random draws almost never land within linking
	# distance, so the first version of this added no loops at all.
	var near: Array[Vector2i] = []
	# The window is derived from `min_sep` rather than fixed, so widening the
	# spacing (`junction_spacing_scale`) automatically thins this pool instead
	# of leaving it fishing for pairs that no longer exist at the new density.
	# At the historical min_sep of 13.0 this reproduces the original 9-30 m
	# window almost exactly.
	var near_min := min_sep * 0.7
	var near_max := min_sep * 2.3
	for a in n:
		for b in range(a + 1, n):
			var d := nodes[a].distance_to(nodes[b])
			if d >= near_min and d <= near_max:
				near.append(Vector2i(a, b))
	_shuffle(near)
	var extra := int(float(n) * loop_link_fraction)
	for i in mini(extra, near.size()):
		_add_corridor(near[i].x, near[i].y)


## Hangs `dead_end_spurs` new leaf nodes off random existing junctions, each
## joined by exactly one corridor and no loop link -- a genuine dead end,
## rather than an accident of the spanning tree. A candidate that cannot keep
## its distance from every other node, or would graze the boss room, is
## skipped rather than forced: falling a few short costs nothing structural,
## unlike the boss-door count.
func _add_dead_ends(min_sep: float, extent: float) -> void:
	_dead_end_ids.clear()
	if dead_end_spurs <= 0 or nodes.size() < 2:
		return
	var hosts: Array[int] = []
	for i in range(1, nodes.size()):
		hosts.append(i)
	_shuffle(hosts)

	var added := 0
	var attempts := 0
	var host_i := 0
	while added < dead_end_spurs and attempts < dead_end_spurs * 15:
		attempts += 1
		var anchor: int = hosts[host_i % hosts.size()]
		host_i += 1
		var dir := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		var reach := _rng.randf_range(dead_end_reach * 0.6, dead_end_reach)
		var candidate: Vector2 = nodes[anchor] + dir * reach
		if candidate.length() > extent:
			continue
		if candidate.distance_to(boss_centre) < boss_radius + min_sep:
			continue
		# A spur tip only needs to keep clear of other corridors and nodes, not
		# the full `min_sep` the scatter enforces between ordinary junctions --
		# that pass already packs the map close to its own limit, and asking a
		# spur tip to clear the same distance from EVERY node left almost no
		# legal spot to put one. Two corridor widths plus a margin is enough
		# room for its own capsule not to swallow a neighbour.
		var spur_clear: float = maxf(min_sep * 0.5, corridor_radius * 2.5)
		var clear := true
		for q in nodes:
			if candidate.distance_squared_to(q) < spur_clear * spur_clear:
				clear = false
				break
		if not clear:
			continue
		var new_index := nodes.size()
		nodes.append(candidate)
		if _add_corridor(anchor, new_index):
			_dead_end_ids.append(new_index)
			added += 1
		else:
			# Undo: a node with no corridor would be an orphan island and
			# break the "everything is reachable" invariant.
			nodes.resize(nodes.size() - 1)


## Corridors added between chambers (or, short of two of those, ordinary
## junctions) that lie far apart, so there is a route that actually crosses
## the map instead of only ever linking neighbours. Dead-end spurs are
## excluded -- wiring one back into the network would erase the dead end
## `_add_dead_ends()` just made.
func _add_long_range_links(extent: float) -> void:
	if long_link_count <= 0:
		return
	var pool: Array[int] = []
	if chamber_at.size() >= 2:
		for k in chamber_at.keys():
			pool.append(k)
	else:
		for i in range(1, nodes.size()):
			pool.append(i)
	for d in _dead_end_ids:
		pool.erase(d)
	if pool.size() < 2:
		return

	var min_span := 2.0 * extent * long_link_span_fraction
	var candidates: Array[Vector2i] = []
	for a_i in pool.size():
		for b_i in range(a_i + 1, pool.size()):
			var a: int = pool[a_i]
			var b: int = pool[b_i]
			if nodes[a].distance_to(nodes[b]) >= min_span:
				candidates.append(Vector2i(a, b))
	_shuffle(candidates)

	var added := 0
	for pair in candidates:
		if added >= long_link_count:
			break
		var already := false
		for e in edges:
			if (e.x == pair.x and e.y == pair.y) or (e.x == pair.y and e.y == pair.x):
				already = true
				break
		if already:
			continue
		if _add_corridor(pair.x, pair.y):
			added += 1


## Bows the corridor sideways and samples it as a polyline, so no two chambers
## are joined by a straight line and nothing runs due north.
func _add_corridor(a: int, b: int, is_door := false) -> bool:
	var pa := nodes[a]
	var pb := nodes[b]
	var mid := (pa + pb) * 0.5
	var along := pb - pa
	var across := Vector2(-along.y, along.x).normalized()
	# Doorways leave the arena dead straight. A bowed one crosses the rim at a
	# different angle than the straight line to its node, so the cells skipped
	# to make room for it are the wrong ones and the corridor cuts an alcove
	# open from behind.
	var bow := 0.0 if is_door else along.length() * _rng.randf_range(-0.28, 0.28)

	# A corridor that grazes the boss room would merge with a cell alcove and
	# open a back door into the arena -- skeletons out, player in, past the
	# gate. Bow it the other way first; only give up if the straight line
	# itself crosses the keep-out.
	var keep_out := boss_radius + cell_radius * 2.0 + corridor_radius + 1.0
	var line := _curve(pa, pb, mid + across * bow, 10)
	if not is_door and _closest_to_boss(line) < keep_out:
		line = _curve(pa, pb, mid - across * bow, 10)
		if _closest_to_boss(line) < keep_out:
			return false
	corridors.append(line)
	edges.append(Vector2i(a, b))
	return true


func _curve(pa: Vector2, pb: Vector2, control: Vector2, steps: int) -> PackedVector2Array:
	var line := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var u := 1.0 - t
		line.append(pa * (u * u) + control * (2.0 * u * t) + pb * (t * t))
	return line


func _closest_to_boss(line: PackedVector2Array) -> float:
	var best := INF
	for k in range(line.size() - 1):
		best = minf(best, _to_segment(boss_centre, line[k], line[k + 1]))
	return best


func _pick_chambers(count: int, r_min: float, r_max: float, extent: float) -> void:
	var candidates: Array[int] = []
	for i in range(1, nodes.size()):
		# Not jammed against the outer wall, where a chamber would be clipped.
		if nodes[i].length() < extent - r_max - 2.0:
			candidates.append(i)
	_shuffle(candidates)
	var placed := 0
	for i in candidates:
		if placed >= count:
			break
		var r := _rng.randf_range(r_min, r_max)
		# A chamber wide enough to reach the cell ring would swallow alcoves and
		# open the arena from behind.
		if nodes[i].length() - r < boss_radius + cell_radius * 2.0 + 2.0:
			continue
		var clash := false
		for j in chamber_at.keys():
			if nodes[i].distance_to(nodes[j]) < r + float(chamber_at[j]) + 9.0:
				clash = true
				break
		if clash:
			continue
		chamber_at[i] = r
		placed += 1


## Signed distance to the walkable region: negative inside, positive in rock.
func distance(p: Vector2) -> float:
	var best: float = p.distance_to(boss_centre) - boss_radius
	for i in chamber_at.keys():
		best = minf(best, p.distance_to(nodes[i]) - float(chamber_at[i]))
	# Cells belong to the region too. Leaving them out here while `inside()`
	# counted them meant the two functions described different mazes, and
	# anything building wall geometry from `distance()` would have sealed every
	# alcove shut.
	for c in cells:
		best = minf(best, p.distance_to(c) - cell_radius)
	for line in corridors:
		for k in range(line.size() - 1):
			best = minf(best, _to_segment(p, line[k], line[k + 1]) - corridor_radius)
	return best


## Fast membership test. Only asks whether the point is in the region, which
## needs nothing beyond the segments in the neighbouring index cells -- unlike
## `distance`, which has to consider everything to find a true minimum.
func inside(p: Vector2) -> bool:
	if p.distance_squared_to(boss_centre) <= boss_radius * boss_radius:
		return true
	for i in chamber_at.keys():
		var r: float = chamber_at[i]
		if p.distance_squared_to(nodes[i]) <= r * r:
			return true
	var cr2 := cell_radius * cell_radius
	for c in cells:
		if p.distance_squared_to(c) <= cr2:
			return true
	if _index.is_empty():
		_build_index()
	var r2 := corridor_radius * corridor_radius
	var cx := int(floor(p.x / CELL))
	var cy := int(floor(p.y / CELL))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var bucket = _index.get(Vector2i(cx + dx, cy + dy))
			if bucket == null:
				continue
			for idx in bucket:
				var seg: PackedVector2Array = _segments[idx]
				if _to_segment_sq(p, seg[0], seg[1]) <= r2:
					return true
	return false


static func _to_segment_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)


## Fisher-Yates drawing from this graph's own generator.
##
## `Array.shuffle()` uses Godot's GLOBAL random stream, not `_rng`, so a maze
## built with it depended on whatever else in the process had consumed random
## numbers first. The same seed produced different loop corridors and different
## chamber placement from run to run.
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap = arr[i]
		arr[i] = arr[j]
		arr[j] = swap


static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Chamber centres in world XZ, for the things that want a room to stand in.
func chamber_centres() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in chamber_at.keys():
		out.append(nodes[i])
	return out
