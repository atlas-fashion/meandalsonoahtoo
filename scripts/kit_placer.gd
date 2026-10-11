extends RefCounted

## Computes placement transforms for the modular dungeon kit -- wall panels,
## ceiling slabs and cell doors -- as plain data. Nothing here creates a node,
## a mesh or a scene: every function returns `Array[Transform3D]`, meant to be
## fed straight into a `MultiMesh`. That is deliberate -- it is what lets this
## whole module be exercised headlessly, without a tree, a renderer or an
## instantiated scene anywhere in the loop.
##
## Module contract (fixed, authored Y-up, outward/visible face is local -Z):
##   wall panel : 2.0 wide (X) x 0.857 deep (Z) x 2.237 tall (Y); origin BOTTOM CENTRE
##   ceiling    : 3.0 x 2.997 (X, Z) x 0.969 thick (Y);           origin TOP FACE centre
##   cell door  : 2.2 wide (X) x 3.0 tall (Y) x 0.2 deep (Z);     origin BOTTOM CENTRE
##   cell frame : 3.247 wide (X) x 3.3 tall (Y) x 1.66 deep (Z);  origin BOTTOM CENTRE
##
## These are the measured sizes of the shipped `models/kit/*_ready.glb`, not
## round numbers chosen up front -- see `models/kit/README.md` for why the
## contract follows the assets rather than the other way round.
##
## Walls are built by STACKING panels: a wall of `wall_rows` rows is
## `wall_rows * 2.237` m tall, one authored-size panel per row, never a
## scaled one -- the panel is a real stone texture, and scaling it to hit an
## arbitrary height would stretch the blocks and make some panels visibly
## wider or narrower than their neighbours.
##
## No `Node3D` exists to hang a `look_at()` off, so every rotation here is
## built directly as a `Basis` from a horizontal facing direction.

const WALL_BASE_WIDTH := 2.0
const WALL_BASE_HEIGHT := 2.237 # one row; stack `wall_rows` of these
const CEIL_SIZE := 3.0
const DOOR_BASE_WIDTH := 2.2
const DOOR_BASE_HEIGHT := 3.0

## How far to either side of a contour point the walkable-side probe looks.
## Small next to any corridor or cell radius in the kit (all >= ~2.3 m), but
## generous next to the couple of tenths of a metre the rasterised, smoothed
## contour can sit off the true analytic boundary -- so the probe reliably
## lands on one clear side or the other rather than re-measuring noise.
const SIDE_PROBE := 0.5


## One panel -- times `wall_rows`, stacked -- per step around each contour
## loop.
##
## `loops` are polylines in RASTER GRID units (as `WallContour.trace` /
## `resample` / `smooth` produce them); `cell_size` and `origin` map a grid
## point to world XZ: `world = origin + grid_point * cell_size`.
##
## A gap in a wall is a hole a player can see through the level's own rock;
## an overlap is two slabs of invisible stone occupying the same space. Those
## two failures are not equally bad, so this scheme is deliberately biased
## away from the first at the cost of more of the second: panels are spaced
## at `panel_width * (1.0 - overlap)`, i.e. closer together than one panel
## width, so neighbours always start out overlapping before curvature gets a
## vote. Closing the loop with a whole number of those steps still almost
## never divides evenly, so `count = ceil(perimeter / step_target)` -- ceil,
## not round, so the correction can only pull panels closer together (more
## overlap), never spread them further apart (which could reopen a gap) --
## and the actual step is then `perimeter / count`, fixed per loop so the
## seam closes exactly in arc length. On a curved run, individual seams can
## still show some residual gap or overlap where local curvature is tighter
## than the loop's average -- that's inherent to flat panels on an organic
## boundary and is exactly what the QA harness measures -- but the baseline
## overlap margin means the worst case is now a bigger overlap, not a gap.
##
## Panels are never scaled along local X: the authored 2.0 m width is real
## stone texture, and stretching it per panel to close a remainder would
## distort the blocks and make neighbouring panels visibly different widths.
## The overlap margin above is what absorbs the remainder instead.
##
## `wall_rows` panels are stacked per step, each one row's height (2.237 m)
## above the last, so a `wall_rows`-row wall reaches `wall_rows * 2.237` m --
## again no scaling, so the stone stays true to size right up to the top.
static func wall_transforms(graph, loops: Array, cell_size: float, origin: Vector2,
		panel_width: float, wall_rows: int = 2, overlap: float = 0.2,
		tall_zones: Array = []) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var rows := maxi(wall_rows, 1)
	var target_step: float = panel_width * (1.0 - overlap)
	if target_step <= 0.0001:
		target_step = panel_width # overlap >= 1.0 is nonsensical input; fall back rather than divide by ~0

	for loop in loops:
		var pts := _to_world_loop(loop, cell_size, origin)
		var n := pts.size()
		if n < 3:
			continue

		var cum := _closed_cumulative(pts)
		var perimeter: float = cum[n]
		if perimeter < 0.0001:
			continue

		var count := maxi(1, int(ceil(perimeter / target_step)))
		var step: float = perimeter / float(count)
		# Orientation is estimated over a window (+/- one panel_width, so two
		# widths point-to-point), not from the single raw contour segment the
		# sample point happens to land on. The traced-and-smoothed contour
		# still carries sub-panel jitter from the raster -- a segment-local
		# tangent chases that noise and left seams up to ~1 m even after the
		# overlap bias above. This window size was found empirically against
		# the reference maze: narrower windows still chased raster jitter,
		# wider ones started crossing into a neighbouring bend and picked up
		# the wrong direction; +/- one panel_width was the sweet spot. It does
		# not reach zero -- a few genuine sharp concave corners remain in this
		# organic boundary (two capsules/discs meeting at a real, if smoothed,
		# angle), and no amount of tangent averaging removes an actual corner.
		var half_span: float = panel_width

		for i in range(count):
			var s: float = float(i) * step
			var p: Vector2 = _sample_path(pts, cum, s, true)[0]
			var s0: float = fposmod(s - half_span, perimeter)
			var s1: float = fposmod(s + half_span, perimeter)
			var tangent: Vector2 = _sample_path(pts, cum, s1, true)[0] \
				- _sample_path(pts, cum, s0, true)[0]
			if tangent.length_squared() < 0.000001:
				continue
			tangent = tangent.normalized()

			var outward := _walkable_direction(graph, p, tangent)
			var basis := _facing_basis(outward, 1.0, 1.0)
			# Chest rooms get a taller wall than the corridors.
			#
			# They are open to the sky and they contain a stepped pedestal, so
			# a hard shove from the mimic could put the player over the top of
			# a corridor-height wall and out of the room entirely. Courses are
			# added rather than the panel being stretched: the stone is a real
			# texture and scaling it to reach would give the room visibly
			# taller blocks than the passage outside it.
			var here := rows
			for zone in tall_zones:
				if p.distance_to(zone["centre"]) <= float(zone["radius"]):
					here = maxi(here, int(zone["rows"]))
					break
			for row in range(here):
				var y: float = float(row) * WALL_BASE_HEIGHT
				out.append(Transform3D(basis, Vector3(p.x, y, p.y)))

	return out


## Vault bays laid END TO END along each corridor, arching across it.
##
## This walks the corridor CENTRELINES, where the flat-slab ceiling above walks
## a grid, and the difference is deliberate. A flat slab has no orientation, so
## a grid is the only way to guarantee cover. A vault does: it spans the
## corridor and its ribs run along it, so it has to follow the corridor's own
## direction or it reads as a tunnel crossing the passage sideways.
##
## The bay is scaled to the corridor's full width, so unlike the old centreline
## ceiling -- which lit 3.0 m of a 5.8 m corridor and left open sky down both
## edges -- there is nothing beside it left to cover.
##
## Bays overlap slightly (`bay * 0.92`), because a seam between two arches that
## almost meet is a slot straight up to the skybox.
static func vault_transforms(graph, bay: float, width: float,
		height: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if bay <= 0.01:
		return out
	var step: float = bay * 0.92
	for line in graph.corridors:
		var pts := _vec2_array(line)
		if pts.size() < 2:
			continue
		var cum := _open_cumulative(pts)
		var total: float = cum[cum.size() - 1]
		if total < 0.001:
			continue
		var count := maxi(1, int(ceil(total / step)))
		var actual: float = total / float(count)
		for i in range(count + 1):
			var s: float = minf(float(i) * actual, total)
			var sample := _sample_path(pts, cum, s, false)
			var p: Vector2 = sample[0]
			var tangent: Vector2 = sample[1]
			if tangent.length_squared() < 0.000001:
				continue
			# The arena is open to the sky by design and gets no vault.
			if p.distance_to(graph.boss_centre) <= graph.boss_radius:
				continue
			out.append(Transform3D(_run_basis(tangent.normalized(), width),
				Vector3(p.x, height, p.y)))
	return out


## Engaged pillars standing against the corridor walls, as in the reference:
## a pier every few metres marking the bays.
##
## Placed on the wall contour like the torches, and turned to face the open
## side by asking the graph rather than trusting the loop's winding -- the
## tracer does not promise one, and a pillar with its flat back to the corridor
## is a slab floating in the passage.
static func pillar_transforms(graph, loops: Array, cell_size: float,
		origin: Vector2, spacing: float, embed: float = 0.0) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if spacing <= 0.01:
		return out
	for loop in loops:
		var pts := _to_world_loop(loop, cell_size, origin)
		var n := pts.size()
		if n < 3:
			continue
		var cum := _closed_cumulative(pts)
		var perimeter: float = cum[n]
		if perimeter < spacing:
			continue
		var count := maxi(1, int(round(perimeter / spacing)))
		var step: float = perimeter / float(count)
		for i in range(count):
			var s: float = float(i) * step
			var p: Vector2 = _sample_path(pts, cum, s, true)[0]
			var ahead: Vector2 = _sample_path(pts, cum, fposmod(s + 1.2, perimeter), true)[0]
			var behind: Vector2 = _sample_path(pts, cum, fposmod(s - 1.2, perimeter), true)[0]
			var tangent: Vector2 = ahead - behind
			if tangent.length_squared() < 0.000001:
				continue
			var outward := _walkable_direction(graph, p, tangent.normalized())
			# Pushed back INTO the wall. The generated pier is 1.81 m across --
			# correct for the reference, far too wide to stand proud in a 4.4 m
			# passage -- so it is embedded until only its face shows, which is
			# what an engaged pier is.
			var seat: Vector2 = p - outward * embed
			out.append(Transform3D(_facing_basis(outward, 1.0, 1.0),
				Vector3(seat.x, 0.0, seat.y)))
	return out


## Basis with local X along `run` and +Y up, for a piece that lies ALONG a
## corridor rather than facing across it. `width` scales the span.
static func _run_basis(run: Vector2, width: float) -> Basis:
	var x_axis := Vector3(run.x, 0.0, run.y).normalized()
	var y_axis := Vector3.UP
	var z_axis := x_axis.cross(y_axis).normalized()
	# The vault's own X is its length along the corridor and its Z is the span,
	# so the span is what `width` scales.
	return Basis(x_axis, y_axis, z_axis * width)


## Slabs over every corridor and chamber, at Y = `height`. The arena is open
## to the sky and deliberately gets none.
##
## Corridors are walked at `slab * 0.9` so neighbouring slabs overlap a
## little rather than risk a sliver of bare ceiling between them; chambers
## get a plain square grid at `slab` spacing, clipped to the disc and to
## `graph.inside()`. The two passes overlap wherever a corridor meets a
## chamber, which is what the final dedup pass (`slab * 0.5` radius) is for.
static func ceiling_transforms(graph, slab: float, height: float) -> Array[Transform3D]:
	# A uniform grid over the whole walkable region, not a walk along the
	# corridor centrelines.
	#
	# Walking the centreline places one slab per sample, which covers a band
	# `slab` wide down the middle of a corridor that is `2 * corridor_radius`
	# across. At the shipped numbers that is a 3.0 m strip in a 5.8 m corridor,
	# and the render showed exactly that: open sky down both sides of every
	# passage, with the ceiling floating in the middle. A grid has no such
	# preferred direction and covers corridors, chambers and cell alcoves with
	# one rule.
	#
	# The region is DILATED by half a slab before testing, so the last slab
	# before a wall still reaches it -- an undilated grid leaves a ragged
	# fringe of daylight wherever the boundary falls between grid points.
	var step: float = slab * 0.9
	var reach: float = slab * 0.6

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in graph.nodes:
		lo = Vector2(minf(lo.x, n.x), minf(lo.y, n.y))
		hi = Vector2(maxf(hi.x, n.x), maxf(hi.y, n.y))
	for c in graph.cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
	if lo.x > hi.x:
		return [] as Array[Transform3D]
	var pad: float = graph.boss_radius + slab * 2.0
	lo -= Vector2(pad, pad)
	hi += Vector2(pad, pad)

	# The arena is open to the sky by design, so it is excluded along with a
	# half-slab margin -- without the margin a dilated grid point just outside
	# the rim drops a slab over the edge of the arena.
	var boss_keep: float = graph.boss_radius + slab * 0.5

	var out: Array[Transform3D] = []
	var nx := int(ceil((hi.x - lo.x) / step))
	var ny := int(ceil((hi.y - lo.y) / step))
	for gy in range(ny + 1):
		for gx in range(nx + 1):
			var p := lo + Vector2(float(gx), float(gy)) * step
			if p.distance_to(graph.boss_centre) <= boss_keep:
				continue
			# `distance()` is negative inside the region; `< reach` is therefore
			# "inside, or within half a slab of being inside".
			if graph.distance(p) >= reach:
				continue
			out.append(Transform3D(Basis.IDENTITY, Vector3(p.x, height, p.y)))
	return out


## One door per cell, standing at the alcove mouth (on the arena rim, at
## Y = 0 -- the origin is the bottom centre) and turned to look into the
## arena. `height` scales the authored 3.0 m tall door; it never moves the
## door off the ground.
static func cell_door_transforms(graph, height: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var y_scale: float = height / DOOR_BASE_HEIGHT

	for c in graph.cells:
		var dir: Vector2 = c - graph.boss_centre
		if dir.length_squared() < 0.000001:
			continue
		dir = dir.normalized()
		var mouth: Vector2 = graph.boss_centre + dir * graph.boss_radius
		var outward := -dir # look back toward boss_centre, into the arena
		var basis := _facing_basis(outward, 1.0, y_scale)
		out.append(Transform3D(basis, Vector3(mouth.x, 0.0, mouth.y)))

	return out


# --------------------------------------------------------------------------
# internals
# --------------------------------------------------------------------------

## Which side of the contour at `p` is walkable, found by direct query
## against the graph -- never assumed from the loop's winding, which the
## contour tracer does not promise and which silently flips per loop.
static func _walkable_direction(graph, p: Vector2, tangent: Vector2) -> Vector2:
	var perp := Vector2(-tangent.y, tangent.x)
	var a_in: bool = graph.inside(p + perp * SIDE_PROBE)
	var b_in: bool = graph.inside(p - perp * SIDE_PROBE)
	if a_in and not b_in:
		return perp
	if b_in and not a_in:
		return -perp
	# Both probes agreed (or disagreed with themselves) -- a sampling
	# artefact right at the boundary. Fall back to the analytic signed
	# distance rather than guessing.
	if graph.distance(p + perp * SIDE_PROBE) < graph.distance(p - perp * SIDE_PROBE):
		return perp
	return -perp


## Builds a basis with +Y up and local -Z pointing along `outward` (a
## normalised, horizontal direction in world XZ). The local X axis falls out
## of the cross product rather than being pinned to a tangent: every panel in
## this kit has a symmetric, centred origin, so which way +X happens to point
## along the wall is irrelevant -- only the facing and the up axis are part
## of the contract.
static func _facing_basis(outward: Vector2, x_scale: float, y_scale: float) -> Basis:
	var out3 := Vector3(outward.x, 0.0, outward.y)
	if out3.length_squared() < 0.000001:
		out3 = Vector3.FORWARD
	out3 = out3.normalized()
	var z_axis := -out3
	var y_axis := Vector3.UP
	var x_axis := y_axis.cross(z_axis).normalized()
	return Basis(x_axis * x_scale, y_axis * y_scale, z_axis)


static func _to_world_loop(loop, cell_size: float, origin: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for gp in loop:
		var world: Vector2 = origin + Vector2(gp.x, gp.y) * cell_size
		if out.is_empty() or out[-1].distance_to(world) > 0.0001:
			out.append(world)
	# A closed loop's trace can repeat its start point at the end; drop it so
	# the wrap-around segment isn't zero-length.
	if out.size() > 1 and out[0].distance_to(out[-1]) <= 0.0001:
		out.remove_at(out.size() - 1)
	return out


## A corridor polyline as plain Vector2s. Restored along with
## `_open_cumulative`: both were removed when the ceiling stopped walking the
## centrelines and became a grid, and the vault walks them again.
static func _vec2_array(line) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in line:
		out.append(Vector2(p))
	return out


## Cumulative arc length along an OPEN polyline. Size n; index n - 1 holds the
## total length.
static func _open_cumulative(pts: Array[Vector2]) -> PackedFloat32Array:
	var n := pts.size()
	var cum := PackedFloat32Array()
	cum.resize(n)
	cum[0] = 0.0
	for i in range(n - 1):
		cum[i + 1] = cum[i] + pts[i].distance_to(pts[i + 1])
	return cum


## Cumulative arc length around a CLOSED polyline, including the closing
## segment back to the start. Size n + 1; index n holds the full perimeter.
static func _closed_cumulative(pts: Array[Vector2]) -> PackedFloat32Array:
	var n := pts.size()
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		cum[i + 1] = cum[i] + a.distance_to(b)
	return cum


## Position and tangent at arc length `s` along `pts`, using `cum` as built by
## `_closed_cumulative`. Returns `[Vector2 position, Vector2 tangent]`.
static func _sample_path(pts: Array[Vector2], cum: PackedFloat32Array, s: float,
		closed: bool) -> Array:
	var n := pts.size()
	var segs := n if closed else n - 1
	s = clampf(s, 0.0, cum[segs])
	var lo := 0
	var hi := segs - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if cum[mid + 1] <= s:
			lo = mid + 1
		else:
			hi = mid
	var idx := lo
	var a: Vector2 = pts[idx]
	var b: Vector2 = pts[(idx + 1) % n] if closed else pts[idx + 1]
	var seg_len: float = cum[idx + 1] - cum[idx]
	var t: float = 0.0
	if seg_len > 0.000001:
		t = clampf((s - cum[idx]) / seg_len, 0.0, 1.0)
	return [a.lerp(b, t), b - a]
