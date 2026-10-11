class_name WallContour
extends RefCounted

## Turns a solid/open tile grid into smooth wall curves.
##
## The maze is still carved on a grid, because that is what guarantees every
## room stays reachable and what the spawner, the cells and the gates all key
## off. Only the *geometry* changes: instead of drawing axis-aligned boxes on
## tile boundaries, this traces the boundary between floor and rock as a closed
## loop, rounds it, and lets it wander off the grid lines. Wall panels are then
## placed along that curve.
##
## Everything here works in tile-corner units, where tile (x, z) occupies the
## square from corner (x, z) to (x + 1, z + 1). The caller converts to world.


## Traces every closed boundary loop around the open region.
##
## Each open tile contributes one directed edge per solid neighbour, wound so
## the open floor is consistently on the same side. Chaining those edges start
## to end gives closed loops -- the outer wall of the maze plus one loop around
## each island of rock.
static func trace(open_at: Callable, tiles: int) -> Array[PackedVector2Array]:
	# start corner -> list of end corners. A list, not a single value: pinch
	# points where two corridors touch diagonally have two edges leaving the
	# same corner, and dropping one would leave the loop unclosed.
	var out_edges := {}
	for z in tiles:
		for x in tiles:
			if not open_at.call(x, z):
				continue
			if not open_at.call(x, z - 1):
				_add_edge(out_edges, Vector2i(x, z), Vector2i(x + 1, z))
			if not open_at.call(x + 1, z):
				_add_edge(out_edges, Vector2i(x + 1, z), Vector2i(x + 1, z + 1))
			if not open_at.call(x, z + 1):
				_add_edge(out_edges, Vector2i(x + 1, z + 1), Vector2i(x, z + 1))
			if not open_at.call(x - 1, z):
				_add_edge(out_edges, Vector2i(x, z + 1), Vector2i(x, z))

	var loops: Array[PackedVector2Array] = []
	for start in out_edges.keys():
		while not (out_edges[start] as Array).is_empty():
			var loop := PackedVector2Array()
			var at: Vector2i = start
			var guard := 0
			while guard < 1_000_000:
				guard += 1
				var outs: Array = out_edges.get(at, [])
				if outs.is_empty():
					break
				var next: Vector2i = outs.pop_back()
				loop.append(Vector2(at.x, at.y))
				at = next
				if at == start:
					break
			if loop.size() >= 4:
				loops.append(loop)
	return loops


static func _add_edge(map: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not map.has(a):
		map[a] = []
	(map[a] as Array).append(b)


## Chaikin corner cutting on a closed loop. Two passes turns a right angle into
## a readable curve; more than three costs vertices for very little shape.
##
## It cuts corners inward, which narrows a turn slightly -- that narrowing IS
## the rounded corner, but it has to be measured, because a corridor that
## pinches below the boss's radius stops being pathable.
static func smooth(loop: PackedVector2Array, passes: int) -> PackedVector2Array:
	var current := loop
	for _p in maxi(passes, 0):
		var next := PackedVector2Array()
		var n := current.size()
		if n < 3:
			return current
		for i in n:
			var a := current[i]
			var b := current[(i + 1) % n]
			next.append(a * 0.75 + b * 0.25)
			next.append(a * 0.25 + b * 0.75)
		current = next
	return current


## Pushes the curve off the grid lines so corridors stop running dead straight
## along north/south/east/west.
##
## Displacement is along the local normal and driven by low-frequency noise, so
## neighbouring points move together and the wall waves rather than jitters.
## Amplitude is deliberately small: this is a wobble, not a reshaping, and every
## metre of inward push is a metre off the corridor width.
static func wander(loop: PackedVector2Array, noise: FastNoiseLite,
		amount: float, scale: float) -> PackedVector2Array:
	var n := loop.size()
	if n < 3 or amount <= 0.0:
		return loop
	var out := PackedVector2Array()
	for i in n:
		var prev := loop[(i - 1 + n) % n]
		var next := loop[(i + 1) % n]
		var tangent := (next - prev)
		if tangent.length_squared() < 0.000001:
			out.append(loop[i])
			continue
		tangent = tangent.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var p := loop[i]
		var d := noise.get_noise_2d(p.x * scale, p.y * scale)
		out.append(p + normal * d * amount)
	return out


## Resamples a loop to roughly even spacing, so wall panels placed along it are
## evenly distributed instead of bunching where the trace happened to be dense.
static func resample(loop: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var n := loop.size()
	if n < 3 or spacing <= 0.0:
		return loop
	var out := PackedVector2Array()
	var carry := 0.0
	for i in n:
		var a := loop[i]
		var b := loop[(i + 1) % n]
		var seg := a.distance_to(b)
		if seg < 0.000001:
			continue
		var t := carry
		while t < seg:
			out.append(a.lerp(b, t / seg))
			t += spacing
		carry = t - seg
	if out.size() < 3:
		return loop
	return out


## Bends the whole plane with smooth 2D noise.
##
## This is what actually removes the grid. Rounding the boundary only softens
## corners -- the corridors still run due north/south/east/west, because the
## topology is still rectilinear. Displacing every point by a low-frequency
## noise field curves the corridors themselves, and because the field is smooth
## and small the mapping stays invertible: nothing folds over itself, so the
## connectivity the maze carver guaranteed still holds.
##
## Apply the identical warp to tile centres, props and spawn points or the
## gameplay grid and the geometry stop agreeing with each other.
static func warp(p: Vector2, noise: FastNoiseLite, amount: float,
		scale: float) -> Vector2:
	if amount <= 0.0:
		return p
	var dx := noise.get_noise_2d(p.x * scale, p.y * scale)
	# Offset so the second axis samples an uncorrelated part of the field;
	# reusing the same coordinates would push everything along one diagonal.
	var dy := noise.get_noise_2d(p.x * scale + 311.7, p.y * scale - 179.3)
	return p + Vector2(dx, dy) * amount


static func warp_loop(loop: PackedVector2Array, noise: FastNoiseLite,
		amount: float, scale: float) -> PackedVector2Array:
	if amount <= 0.0:
		return loop
	var out := PackedVector2Array()
	for p in loop:
		out.append(warp(p, noise, amount, scale))
	return out


## Smallest distance from any walkable point to the nearest wall, in tile units.
## Multiply by tile_size for metres.
##
## This is the metric that matters, and it is deliberately not "how close does
## the wall come to itself". That question finds the diagonal corner-touches
## where two blocks of rock meet at a point: they measure as a zero-width gap,
## they have always been there, and they are solid wall rather than a corridor.
## What actually decides whether a body can get through is the clearance along
## the floor it walks on, so that is what this measures.
## `walkable` must already be in the same space as the loops -- if the level is
## warped, pass warped centres, or the measurement compares two different worlds.
static func clearance(loops: Array[PackedVector2Array],
		walkable: Array, stride: int = 2) -> float:
	var points: Array[Vector2] = []
	for loop in loops:
		var i := 0
		while i < loop.size():
			points.append(loop[i])
			i += stride
	if points.is_empty() or walkable.is_empty():
		return 0.0
	var worst := INF
	for centre in walkable:
		var near := INF
		for p in points:
			var d := (centre as Vector2).distance_squared_to(p)
			if d < near:
				near = d
		if near < worst:
			worst = near
	return sqrt(worst)
