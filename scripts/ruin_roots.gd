extends RefCounted

## The roots that have broken through the dungeon (note 176).
##
## Every root is a swept tube grown in code along the stone it clings to: down a
## wall from the vault, round a junction pillar, over an arch's face, or hanging
## free from the crown. To lie ON the stone rather than float off it or sink
## through it, each kit piece's outer surface is measured once from its own
## triangles -- a relief (`Relief`): for a wall, how far its face stands out at
## every point of a 4 cm grid; for a pillar, its radius at every angle and
## height -- and the strand's centreline is set into that surface by a part of
## its own radius, so it reads as gripping the brick.
##
## All the strands of one corridor cell go into one mesh (`build_mesh`), drawn
## with one shared material (`bark_material`, root_bark.gdshader): bark and
## faint gold veins from noise, per strand shade and gold in the vertex colour.
## The mesh's own `life` instance uniform is its gold: ruin_dressing.gd lowers it
## once the living tips grown from it are cut (living_root.gd).

const BARK_SHADER := preload("res://shaders/root_bark.gdshader")
const TIP_SHADER := preload("res://shaders/root_tip.gdshader")

## Metres of strand per unit of UV.y (the bark's pattern along it).
const BARK_V := 0.4
## Below this the grid holds nothing.
const NONE := -1.0e9

## The brick kit's wall: its face spans these (brick_level.gd).
const WALL_HALF := 2.55
const WALL_TOP := 3.5
## Where a strand starts, up in the vault's springing, hidden in the stone.
const WALL_START := 3.38

static var _bark: ShaderMaterial = null
static var _tip: ShaderMaterial = null
static var _reliefs := {}


## One strand: its centreline and the radius at each point.
class Strand:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	## Bark shade (vertex colour r) and how much gold it carries (g).
	var tint := 1.0
	var gold := 1.0
	var seed := 0.0
	## The surface it lies on, for the first ring's turn.
	var up := Vector3.UP
	## Its section off that surface against across it (1 round, under 1 pressed flat).
	var flat := 1.0

	func transformed(xf: Transform3D) -> Strand:
		var s := Strand.new()
		s.pts = xf * pts
		s.radii = radii
		s.tint = tint
		s.gold = gold
		s.seed = seed
		s.up = xf.basis * up
		s.flat = flat
		return s


## A height field over a grid: the outermost surface of a mesh seen along one
## axis (planar), or its radius at each angle (cylindrical). NONE where nothing
## covers a cell.
class Relief:
	var u0 := 0.0
	var v0 := 0.0
	var step := 0.04
	var w := 0
	var h := 0
	var data := PackedFloat32Array()
	## Cylindrical: u is the angle, which wraps.
	var wraps := false

	func cell(u: float, v: float) -> Vector2i:
		return Vector2i(int(floor((u - u0) / step)), int(floor((v - v0) / step)))

	func at_cell(ix: int, iy: int) -> float:
		if wraps:
			ix = posmod(ix, w)
		if ix < 0 or iy < 0 or ix >= w or iy >= h:
			return NONE
		return data[iy * w + ix]

	## The surface at (u, v).
	func at(u: float, v: float) -> float:
		var c := cell(u, v)
		return at_cell(c.x, c.y)

	## The outermost surface within `r` of (u, v): a strand of radius r resting
	## there touches this, not the mortar between two bricks. NONE if any of the
	## middle is open (an edge, a doorway). The grid is max-filtered once per
	## reach (`_dilated`) and every lookup after is one read: every wall in the
	## level shares the one relief, so this is the strands' hottest call.
	func outer(u: float, v: float, r: float) -> float:
		var c := cell(u, v)
		if at_cell(c.x, c.y) <= NONE * 0.5:
			return NONE
		var n := clampi(int(ceil(r / step)), 0, 4)
		if n == 0:
			return at_cell(c.x, c.y)
		if not _dilated.has(n):
			_dilated[n] = _dilate(n)
		var ix := posmod(c.x, w) if wraps else c.x
		if ix < 0 or c.y < 0 or ix >= w or c.y >= h:
			return NONE
		return (_dilated[n] as PackedFloat32Array)[c.y * w + ix]

	var _dilated := {}

	func _dilate(n: int) -> PackedFloat32Array:
		# Separable: the max along x, then along y.
		var row := PackedFloat32Array()
		row.resize(w * h)
		for iy in h:
			for ix in w:
				var best := NONE
				for dx in range(-n, n + 1):
					best = maxf(best, at_cell(ix + dx, iy))
				row[iy * w + ix] = best
		var out := PackedFloat32Array()
		out.resize(w * h)
		for iy in h:
			for ix in w:
				var best := NONE
				for dy in range(-n, n + 1):
					var y := iy + dy
					if y >= 0 and y < h:
						best = maxf(best, row[y * w + ix])
				out[iy * w + ix] = best
		return out


## The material every static root shares.
static func bark_material() -> ShaderMaterial:
	if _bark == null:
		_bark = ShaderMaterial.new()
		_bark.shader = BARK_SHADER
	return _bark


static func tip_material() -> ShaderMaterial:
	if _tip == null:
		_tip = ShaderMaterial.new()
		_tip.shader = TIP_SHADER
	return _tip


# --- Reliefs ---------------------------------------------------------------------------

## The outer surface of `mesh` (its own frame) seen along `axis`, over a grid on
## (`u_axis`, `v_axis`) spanning `u_range` x `v_range`. Cached per mesh and axis.
static func planar_relief(mesh: Mesh, axis: Vector3, u_axis: Vector3, v_axis: Vector3,
		u_range: Vector2, v_range: Vector2, step := 0.04) -> Relief:
	var key := "%d_%s_%s" % [mesh.get_rid().get_id(), axis, u_axis]
	if _reliefs.has(key):
		return _reliefs[key]
	var r := Relief.new()
	r.u0 = u_range.x
	r.v0 = v_range.x
	r.step = step
	r.w = int(ceil((u_range.y - u_range.x) / step))
	r.h = int(ceil((v_range.y - v_range.x) / step))
	r.data.resize(r.w * r.h)
	r.data.fill(NONE)
	_raster(mesh, r, func(p: Vector3) -> Vector3:
		return Vector3(p.dot(u_axis), p.dot(v_axis), p.dot(axis)))
	_reliefs[key] = r
	return r


## The radius of `mesh` round its own Y axis at every angle and height, taken
## at its widest over its four quarter turns (the kit's pillars are stood at a
## random quarter turn each, brick_level.gd).
static func pillar_relief(mesh: Mesh, height: float, step := 0.04) -> Relief:
	var key := "pillar_%d" % mesh.get_rid().get_id()
	if _reliefs.has(key):
		return _reliefs[key]
	var r := Relief.new()
	r.wraps = true
	r.w = 96
	r.step = TAU / float(r.w)
	r.u0 = -PI
	r.v0 = 0.0
	# v is height, in its own steps: kept on `step` metres by scaling.
	var vstep := step
	r.h = int(ceil(height / vstep))
	r.data.resize(r.w * r.h)
	r.data.fill(NONE)
	var scale_v := r.step / vstep
	_raster(mesh, r, func(p: Vector3) -> Vector3:
		return Vector3(atan2(p.z, p.x), p.y * scale_v, Vector2(p.x, p.z).length()))
	# Widest of the four quarter turns.
	var quarter := r.w / 4
	var sym := r.data.duplicate()
	for iy in r.h:
		for ix in r.w:
			var best := NONE
			for k in 4:
				best = maxf(best, r.data[iy * r.w + posmod(ix + k * quarter, r.w)])
			sym[iy * r.w + ix] = best
	r.data = sym
	# Lookups take height in metres: undo the scaling there.
	r.v0 = 0.0
	_reliefs[key] = r
	r.set_meta("vstep", vstep)
	return r


## Height in a pillar relief's own rows (see `pillar_relief`).
static func pillar_at(r: Relief, angle: float, y: float, radius: float) -> float:
	var vstep: float = r.get_meta("vstep", r.step)
	return r.outer(wrapf(angle, -PI, PI), y * r.step / vstep, radius)


## Rasterises every triangle of `mesh`, each vertex mapped by `project` to
## (u, v, height), into `r`, keeping the greatest height in each cell.
static func _raster(mesh: Mesh, r: Relief, project: Callable) -> void:
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var ids = arrays[Mesh.ARRAY_INDEX]
		if ids == null or (ids as PackedInt32Array).is_empty():
			ids = PackedInt32Array(range(verts.size()))
		var gx := PackedFloat32Array()
		var gy := PackedFloat32Array()
		var gd := PackedFloat32Array()
		gx.resize(verts.size())
		gy.resize(verts.size())
		gd.resize(verts.size())
		for k in verts.size():
			var q: Vector3 = project.call(verts[k])
			gx[k] = (q.x - r.u0) / r.step - 0.5
			gy[k] = (q.y - r.v0) / r.step - 0.5
			gd[k] = q.z
		var idx: PackedInt32Array = ids
		for t in range(0, idx.size() - 2, 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			var x0 := gx[a]
			var y0 := gy[a]
			var x1 := gx[b]
			var y1 := gy[b]
			var x2 := gx[c]
			var y2 := gy[c]
			# A triangle across the cylinder's seam: unwrap it.
			if r.wraps:
				var span := maxf(maxf(x0, x1), x2) - minf(minf(x0, x1), x2)
				if span > float(r.w) * 0.5:
					if x0 < float(r.w) * 0.5:
						x0 += float(r.w)
					if x1 < float(r.w) * 0.5:
						x1 += float(r.w)
					if x2 < float(r.w) * 0.5:
						x2 += float(r.w)
			var den := (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
			if absf(den) < 1e-9:
				continue
			var lo_x := int(ceil(minf(minf(x0, x1), x2)))
			var hi_x := int(floor(maxf(maxf(x0, x1), x2)))
			var lo_y := maxi(int(ceil(minf(minf(y0, y1), y2))), 0)
			var hi_y := mini(int(floor(maxf(maxf(y0, y1), y2))), r.h - 1)
			if not r.wraps:
				lo_x = maxi(lo_x, 0)
				hi_x = mini(hi_x, r.w - 1)
			for iy in range(lo_y, hi_y + 1):
				for ix in range(lo_x, hi_x + 1):
					var l0 := ((y1 - y2) * (ix - x2) + (x2 - x1) * (iy - y2)) / den
					var l1 := ((y2 - y0) * (ix - x2) + (x0 - x2) * (iy - y2)) / den
					var l2 := 1.0 - l0 - l1
					if l0 < -0.001 or l1 < -0.001 or l2 < -0.001:
						continue
					var d := l0 * gd[a] + l1 * gd[b] + l2 * gd[c]
					var cx := posmod(ix, r.w) if r.wraps else ix
					var at := iy * r.w + cx
					if d > r.data[at]:
						r.data[at] = d


# --- Strands ---------------------------------------------------------------------------

## The radius along a strand: thick at its root, tapering to a point (or to
## `end` for one a living tip grows out of).
static func _taper(r0: float, t: float, end := 0.004) -> float:
	return maxf(r0 * pow(maxf(1.0 - t, 0.0), 0.6), end)


## Strands down a wall, in the wall piece's own frame (x along it, y up, z out
## of its face), from the vault's springing. `count` main roots, each with a
## branch or two and a few hair roots. `live` (Array) collects
## [base, tangent] for each root grown to carry a living tip
## (`tips` of them), its end left blunt there.
static func wall_strands(rng: RandomNumberGenerator, relief: Relief, count: int,
		tips := 0, live: Array = [], band := 0.0) -> Array:
	var out: Array = []
	# Roots come through the stone in bundles: a few side by side, crossing
	# and parting as they go down. `band`: the middle of the wall kept clear
	# (a torch's pilaster), half its width.
	var bundle_x := 0.0
	var bundle_drift := 0.0
	var left_in_bundle := 0
	for i in count:
		var tip := i < tips
		if left_in_bundle <= 0 or tip:
			bundle_x = rng.randf_range(-WALL_HALF + 0.4, WALL_HALF - 0.4)
			if absf(bundle_x) < band + 0.25:
				bundle_x = signf(bundle_x + 0.001) * rng.randf_range(band + 0.25, WALL_HALF - 0.4)
			bundle_drift = rng.randf_range(-0.45, 0.45)
			if band > 0.0:
				bundle_drift = absf(bundle_drift) * signf(bundle_x)
			left_in_bundle = rng.randi_range(1, 3)
		left_in_bundle -= 1
		var x := clampf(bundle_x + rng.randf_range(-0.2, 0.2), -WALL_HALF + 0.3, WALL_HALF - 0.3)
		if absf(x) < band + 0.1:
			x = signf(bundle_x) * (band + 0.1)
		var r0 := rng.randf_range(0.035, 0.1) if not tip else rng.randf_range(0.07, 0.09)
		var length := rng.randf_range(1.6, 4.6)
		var stop_y := -1.0
		if tip:
			# Ends at chest height or a little over, where it can reach a passer-by.
			stop_y = rng.randf_range(1.55, 2.25)
			length = 6.0
		var s := _crawl(rng, relief, Vector2(x, WALL_START + rng.randf_range(0.0, 0.15)),
			r0, length, bundle_drift + rng.randf_range(-0.12, 0.12), stop_y, 0.055 if tip else 0.004, 0.08, band)
		if s == null:
			continue
		s.gold = rng.randf_range(0.6, 1.25)
		out.append(s)
		if tip and s.pts.size() > 2:
			var n := s.pts.size()
			live.append([s.pts[n - 1], (s.pts[n - 1] - s.pts[n - 3]).normalized(), s.radii[n - 1]])
		# Branches off it, and hair roots.
		var branches := rng.randi_range(0, 2)
		for b in branches:
			if s.pts.size() < 8:
				break
			var at := rng.randi_range(s.pts.size() / 5, s.pts.size() * 4 / 5)
			var from := s.pts[at]
			var br := _crawl(rng, relief, Vector2(from.x, from.y), s.radii[at] * rng.randf_range(0.45, 0.7),
				rng.randf_range(0.5, 1.8), rng.randf_range(0.5, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0), -1.0, 0.003,
				0.07, band)
			if br != null:
				br.gold = s.gold * rng.randf_range(0.5, 1.0)
				out.append(br)
		for h in (rng.randi_range(1, 3) if r0 > 0.05 else 0):
			if s.pts.size() < 4:
				break
			var at := rng.randi_range(1, s.pts.size() - 2)
			var from := s.pts[at]
			var hair := _crawl(rng, relief, Vector2(from.x, from.y), rng.randf_range(0.008, 0.016),
				rng.randf_range(0.15, 0.55), rng.randf_range(0.6, 1.6) * (1.0 if rng.randf() < 0.5 else -1.0), -1.0, 0.002,
				0.06, band)
			if hair != null:
				hair.gold = 0.0
				out.append(hair)
	return out


## One strand crawling down a planar relief from `start` (u, v): mostly down,
## wandering sideways by `drift`, until `length` metres, the floor (where it
## turns and runs along the wall's foot for a while), the relief's edge, or
## `stop_y`. Its centreline sunk into the surface by part of its radius.
static func _crawl(rng: RandomNumberGenerator, relief: Relief, start: Vector2, r0: float, length: float,
		drift: float, stop_y := -1.0, end := 0.004, step := 0.07, band := 0.0) -> Strand:
	var s := Strand.new()
	s.seed = rng.randf()
	s.tint = rng.randf_range(0.75, 1.2)
	s.up = Vector3(0.0, 0.0, 1.0)
	s.flat = 0.7
	var pos := start
	var dir := Vector2(drift, -1.0).normalized()
	var travelled := 0.0
	var along_floor := 0.0
	var floor_run := rng.randf_range(0.3, 1.4)
	var floor_dir := 1.0 if drift >= 0.0 else -1.0
	var wobble := rng.randf() * 100.0
	var pts: Array[Vector2] = []
	while travelled < length:
		pts.append(pos)
		if stop_y > 0.0 and pos.y <= stop_y:
			break
		var r := _taper(r0, travelled / length, end)
		if pos.y <= r + 0.02:
			# On the floor: along the wall's foot.
			along_floor += step
			if along_floor > floor_run:
				break
			dir = Vector2(floor_dir, 0.0)
		else:
			wobble += step * 2.3
			var turn := sin(wobble) * 0.55 + sin(wobble * 2.7 + 1.3) * 0.3
			dir = Vector2(dir.x + turn * 0.18 + drift * 0.05, -1.0)
			# Now and then a kink, where it met a harder stone.
			if rng.randf() < 0.07:
				dir.x += rng.randf_range(-0.6, 0.6)
			dir.x = clampf(dir.x, -1.3, 1.3)
			dir = dir.normalized()
		var next := pos + dir * step
		# Off the end of the wall: turn down instead.
		if absf(next.x) > WALL_HALF - 0.08:
			next.x = signf(next.x) * (WALL_HALF - 0.08)
			drift = -drift
			floor_dir = -floor_dir
		# Nor across the middle kept clear: turned back to its own side.
		if band > 0.0 and absf(next.x) < band and next.y > 0.15:
			next.x = signf(pos.x) * band
			drift = absf(drift) * signf(pos.x)
			floor_dir = signf(pos.x)
		next.y = maxf(next.y, r + 0.005)
		pos = next
		travelled += step
	if pts.size() < 3:
		return null
	var total := float(pts.size() - 1) * step
	for i in pts.size():
		var t := float(i) / float(pts.size() - 1)
		var r := _taper(r0, t * total / maxf(length, total), end)
		var p2 := pts[i]
		var z := relief.outer(p2.x, p2.y, r)
		if z <= NONE * 0.5:
			# Not on the stone yet (up in the vault's springing): start lower.
			if s.pts.is_empty():
				continue
			# Over open air (a doorway's edge): stop here.
			break
		# Sunk by 40% of its radius; on the floor it lies on the flags.
		s.pts.append(Vector3(p2.x, maxf(p2.y, r * 0.6), z + r * 0.42))
		s.radii.append(r)
	return s if s.pts.size() >= 3 else null


## Strands winding down a junction pillar (its own frame, origin at its foot),
## from its top. `relief` from `pillar_relief`.
static func pillar_strands(rng: RandomNumberGenerator, relief: Relief, count: int, top: float) -> Array:
	var out: Array = []
	for i in count:
		var s := Strand.new()
		s.seed = rng.randf()
		s.tint = rng.randf_range(0.75, 1.2)
		s.gold = rng.randf_range(0.6, 1.2)
		var angle := rng.randf() * TAU - PI
		var twist := rng.randf_range(0.5, 1.6) * (1.0 if rng.randf() < 0.5 else -1.0)
		var r0 := rng.randf_range(0.035, 0.08)
		var y := top + 0.1
		var stop := rng.randf_range(-0.2, 1.4)
		var step := 0.07
		var wob := rng.randf() * 50.0
		var n := 0
		while y > stop and n < 200:
			var t := (top + 0.1 - y) / maxf(top + 0.1 - stop, 0.1)
			var r := _taper(r0, t * 0.85, 0.006)
			var surf := pillar_at(relief, angle, maxf(y, 0.0), r)
			if surf > NONE * 0.5:
				var dir := Vector3(cos(angle), 0.0, sin(angle))
				s.pts.append(dir * (surf + r * 0.42) + Vector3(0.0, maxf(y, r * 0.6), 0.0))
				s.radii.append(r)
			wob += step * 2.0
			angle += twist * step * (0.7 + 0.5 * sin(wob))
			y -= step * 0.92
			n += 1
		if s.pts.size() >= 3:
			s.up = (s.pts[0] * Vector3(1.0, 0.0, 1.0)).normalized()
			s.flat = 0.75
			out.append(s)
	return out


## Strands draped over an arch's face (the arch piece's frame, the face toward
## its +Z or -Z per `relief`): from over the crown down one side of the ring, a
## little out from the opening's edge, and on down the leg. `sign_z` is the
## face's side, so a point's height off the face becomes its z.
static func arch_strands(rng: RandomNumberGenerator, relief: Relief, count: int, sign_z: float) -> Array:
	var out: Array = []
	for i in count:
		var s := Strand.new()
		s.seed = rng.randf()
		s.tint = rng.randf_range(0.75, 1.2)
		s.gold = rng.randf_range(0.6, 1.2)
		s.up = Vector3(0.0, 0.0, sign_z)
		s.flat = 0.75
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var r0 := rng.randf_range(0.035, 0.075)
		var inset := rng.randf_range(0.12, 0.55)
		var stop := rng.randf_range(0.0, 2.6)
		var wob := rng.randf() * 40.0
		var y := 5.45
		var step := 0.07
		var start_x := rng.randf_range(-0.3, 0.3)
		var x := start_x
		while y > stop:
			var t := (5.45 - y) / maxf(5.45 - stop, 0.1)
			var r := _taper(r0, t * 0.9, 0.005)
			wob += step * 2.1
			# The opening's edge at this height, from the middle outward.
			var edge := _opening_edge(relief, y)
			var want: float
			if edge < 0.0:
				want = start_x + side * t * 0.6
			else:
				want = side * (edge + inset + 0.08 * sin(wob))
			# Eased toward it: the ring's edge steps from row to row.
			x += clampf(want - x, -0.06, 0.06)
			var surf := relief.outer(x, y, r)
			if surf > NONE * 0.5:
				s.pts.append(Vector3(x, maxf(y, r * 0.6), sign_z * (surf + r * 0.42)))
				s.radii.append(r)
			y -= step
		if s.pts.size() >= 3:
			out.append(s)
	return out


## How far out from the arch's centre line the opening reaches at height `y`
## (where the face begins); -1 above the opening.
static func _opening_edge(relief: Relief, y: float) -> float:
	# Found once per row of the relief and kept: every arch in the level shares it.
	if not relief.has_meta("edges"):
		var edges := PackedFloat32Array()
		edges.resize(relief.h)
		for iy in relief.h:
			var row_y := relief.v0 + (float(iy) + 0.5) * relief.step
			var found := -1.0
			if relief.at(0.0, row_y) <= NONE * 0.5:
				var x := 0.0
				while x < 3.2:
					if relief.at(x, row_y) > NONE * 0.5:
						found = x
						break
					x += relief.step
			edges[iy] = found
		relief.set_meta("edges", edges)
	var all: PackedFloat32Array = relief.get_meta("edges")
	var row := int(floor((y - relief.v0) / relief.step))
	if row < 0 or row >= all.size():
		return -1.0
	return all[row]


## Roots hanging free from the vault (a cell's frame, y up): each from inside
## the stone at `from` straight down `length`, swinging a little out of true.
static func hanging_strand(rng: RandomNumberGenerator, from: Vector3, length: float, r0: float) -> Strand:
	var s := Strand.new()
	s.seed = rng.randf()
	s.tint = rng.randf_range(0.7, 1.15)
	s.gold = rng.randf_range(0.3, 1.0)
	s.up = Vector3(1.0, 0.0, 0.0)
	var lean := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * 0.12
	var step := 0.08
	var n := maxi(int(length / step), 3)
	var wob := rng.randf() * 30.0
	for i in n + 1:
		var t := float(i) / float(n)
		var p := from + Vector3(0.0, -length * t, 0.0) + lean * (t * t) * length
		p += Vector3(sin(wob + t * 5.0), 0.0, cos(wob * 1.3 + t * 4.0)) * 0.025 * t
		s.pts.append(p)
		s.radii.append(_taper(r0, t, 0.003))
	return s


# --- Meshes ----------------------------------------------------------------------------

## Every strand as one tube mesh: rings of 4 to 7 sides (by thickness) carried
## along each centreline by parallel transport, so a strand never twists.
static func build_mesh(strands: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colours := PackedColorArray()
	var idx := PackedInt32Array()
	for st in strands:
		var s := st as Strand
		var n := s.pts.size()
		if n < 2:
			continue
		var thick := 0.0
		for r in s.radii:
			thick = maxf(thick, r)
		var sides := 7 if thick > 0.075 else (6 if thick > 0.045 else (5 if thick > 0.022 else 4))
		var lengths := PackedFloat32Array()
		lengths.resize(n)
		var total := 0.0
		for i in range(1, n):
			total += s.pts[i].distance_to(s.pts[i - 1])
			lengths[i] = total
		if total < 0.02:
			continue
		var tangent := (s.pts[1] - s.pts[0]).normalized()
		var normal := s.up - tangent * s.up.dot(tangent)
		if normal.length_squared() < 1e-6:
			normal = tangent.cross(Vector3.RIGHT if absf(tangent.x) < 0.9 else Vector3.FORWARD)
		normal = normal.normalized()
		var base := verts.size()
		for i in n:
			var a := s.pts[maxi(i - 1, 0)]
			var b := s.pts[mini(i + 1, n - 1)]
			var t := (b - a)
			if t.length_squared() > 1e-10:
				t = t.normalized()
				# Parallel transport: the last ring's normal, squared up to here.
				normal = (normal - t * normal.dot(t))
				if normal.length_squared() < 1e-8:
					normal = t.cross(Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT)
				normal = normal.normalized()
				tangent = t
			var binormal := tangent.cross(normal)
			var r := s.radii[i]
			# Gnarled: it swells and narrows along its length, with a knot here
			# and there -- never back to the clean taper of a tube.
			var l := lengths[i]
			var knot := pow(maxf(sin(l * 2.9 + s.seed * 31.0), 0.0), 10.0) * 0.4
			r *= 1.0 + 0.16 * sin(l * 6.3 + s.seed * 17.0) * sin(l * 1.7 + s.seed * 5.0) + knot
			var v := l / BARK_V
			var along := l / total
			var p := s.pts[i]
			var trig: PackedFloat32Array = _ring(sides)
			var colour := Color(s.tint, s.gold, 0.0, 1.0)
			var uv2 := Vector2(along, s.seed)
			for j in sides + 1:
				var co := trig[j * 2]
				var si := trig[j * 2 + 1]
				# Pressed flat against what it grows on (`normal` is that
				# surface's, carried along): wide across it, shallow off it.
				verts.append(p + (normal * (co * s.flat) + binormal * si) * r)
				normals.append((normal * (co / s.flat) + binormal * si).normalized())
				var c := -normal * (si * s.flat) + binormal * co
				tangents.append_array([c.x, c.y, c.z, 1.0])
				uvs.append(Vector2(float(j) / float(sides), v))
				uv2s.append(uv2)
				colours.append(colour)
		for i in n - 1:
			for j in sides:
				var a := base + i * (sides + 1) + j
				var b := a + sides + 1
				idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, bark_material())
	return mesh


static var _rings := {}


## cos and sin round a ring of `sides`, the seam vertex repeated.
static func _ring(sides: int) -> PackedFloat32Array:
	if not _rings.has(sides):
		var t := PackedFloat32Array()
		for j in sides + 1:
			var ang := TAU * float(j) / float(sides)
			t.append(cos(ang))
			t.append(sin(ang))
		_rings[sides] = t
	return _rings[sides]


static var _tips := {}


## A living tip's tube, straight and tapered, `rings` rings along its length:
## the ring offsets in x and z, how far along in UV2.x; root_tip.gdshader bends
## it. `r0` its radius at the base, matched to the strand it grows from.
static func tip_mesh(length: float, r0: float) -> ArrayMesh:
	var key := "%.2f_%.3f" % [length, r0]
	if _tips.has(key):
		return _tips[key]
	var rings := 22
	var sides := 7
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colours := PackedColorArray()
	var idx := PackedInt32Array()
	for i in rings + 1:
		var t := float(i) / float(rings)
		# Thick at the base, a long whip to a fine point.
		var r := maxf(r0 * pow(1.0 - t, 0.75), 0.003)
		for j in sides + 1:
			var ang := TAU * float(j) / float(sides)
			var d := Vector3(cos(ang), 0.0, sin(ang))
			verts.append(d * r + Vector3(0.0, t, 0.0))
			normals.append(d)
			tangents.append_array([-sin(ang), 0.0, cos(ang), 1.0])
			uvs.append(Vector2(float(j) / float(sides), t * length / BARK_V))
			uv2s.append(Vector2(t, 0.37))
			colours.append(Color(1.0, 1.0, 0.0, 1.0))
	for i in rings:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, tip_material())
	_tips[key] = mesh
	return mesh
