extends RefCounted

## Turns an organic maze graph (`maze_graph.gd`) into the level's visual and
## collision geometry, out of the modular Tripo kit (`models/kit/README.md`).
##
## Pure builder: `build()` receives nodes to fill and fills them. It holds no
## state between calls -- a rebuild with the same graph must reproduce the
## exact same geometry, which is also why `Array.shuffle()` never appears
## here: it draws from Godot's global RNG stream, not a seeded one, so the
## same seed could come out different depending on what else the process had
## already drawn from that stream. Variant selection below is a position hash
## for the same reason -- a running counter would depend on iteration order
## surviving intact across builds, a hash of the panel's own position cannot.
##
## Autoload names do not resolve under `--script` (see CLAUDE.md), so nothing
## here references `Graphics` by name. In practice nothing here needs to:
## per-node distance culling and texture detail are applied generically by
## `graphics_settings.gd`'s own sweep the moment a `MultiMeshInstance3D` enters
## the tree, and the one knob that is this module's own -- whether the kit
## casts shadows -- arrives through `opts.shadows` instead, so the caller
## decides it from `Graphics.shadows` without this file ever touching the
## autoload.

const Placer = preload("res://scripts/kit_placer.gd")

## Extra courses of stone around a chest room, on top of `wall_rows`.
##
## The chest rooms are roofless and contain a stepped pedestal, so a hard shove
## from the mimic could put the player over a corridor-height wall and out of
## the room. Two more courses puts the lip well past anything a knockback can
## reach from the top step.
## How far an engaged pier is sunk into the wall, in metres.
## World-space texture scale and normal strength for the kit stone.
##
## Both lifted from `Mat_wall` in `scenes/maze.tscn`, the material the walls
## used before the kit: 0.5 puts one texture repeat every two metres, and 1.8
## is enough normal for a flat panel to read as carved stone.
const TRIPLANAR_SCALE := 0.5
const NORMAL_STRENGTH := 1.8
const PILLAR_EMBED := 1.15
const CHAMBER_EXTRA_ROWS := 2
## How far past a chamber's own radius the taller wall extends, in metres.
const CHAMBER_WALL_MARGIN := 3.0


## The chamber rims that get the taller treatment, as {centre, radius, rows}.
static func _tall_zones(graph, wall_rows: int) -> Array:
	var zones: Array = []
	for i in graph.chamber_at.keys():
		zones.append({
			"centre": graph.nodes[i],
			"radius": float(graph.chamber_at[i]) + CHAMBER_WALL_MARGIN,
			"rows": wall_rows + CHAMBER_EXTRA_ROWS,
		})
	return zones


## Chunk edge in metres for the MultiMesh split.
const CHUNK := 24.0

## The pieces this module places, keyed the way the rest of this file refers
## to them.
const KIT_PATHS := {
	"panel": "res://models/kit/wall_panel_ready.glb",
	"cracked": "res://models/kit/wall_cracked_ready.glb",
	"window": "res://models/kit/wall_window_ready.glb",
	"ceiling": "res://models/kit/ceiling_slab_ready.glb",
	"floor": "res://models/kit/floor_slab_ready.glb",
	"door": "res://models/kit/cell_door_ready.glb",
	"frame": "res://models/kit/cell_frame_ready.glb",
	# The vaulted ceiling and engaged piers from the reference corridor. Both
	# are optional: if the files are missing the level falls back to the flat
	# slab ceiling and no pillars, rather than failing to build.
	"vault": "res://models/kit/v2_vault_ready.glb",
	"pillar": "res://models/kit/v2_pillar_ready.glb",
}

## Measured shares of each wall variant. The grate is a strong visual beat, so
## it stays rare; cracked stone is common background wear; everything else
## left over is the plain course.
const WINDOW_SHARE := 0.08
const CRACKED_SHARE := 0.26

## Roughly how much contour run each wall-collision box covers, in metres.
## Measured down from 6.0: each box spans the straight CHORD between two
## samples while the contour bows away from it in between, and at a 6 m run with
## 1.0 m of thickness the bow on this boundary's tighter bends put the true wall
## outside the box entirely -- 36,252 sampled wall points had no collider on
## them, which is a wall the player walks through. Halving the run quarters the
## sagitta. The cost is more shapes, which is cheap: they are static boxes.
const COLLISION_RUN := 1.0
## Box thickness across the wall, in metres.
const COLLISION_THICKNESS := 1.6
## How far a box runs past its own arc ALONG the wall, in metres.
##
## Separate from the thickness, and much smaller. It used to reuse
## COLLISION_THICKNESS, so every box overshot its arc by 0.8 m at each end --
## harmless on a straight run, but at a bend the overshoot carries straight on
## into the corridor and cuts the corner. That left intrusions 1.73 m deep
## after the boxes had already been pushed back behind the wall face.
const COLLISION_END_PAD := 0.25
## Extra arc length sampled past each box's nominal run, split across both
## ends. A curved boundary sampled at even arc length always bows away from
## the straight chord between two sample points, so the chord is always a
## little short of the true run; padding it back out is what keeps that
## shortfall from opening a gap between neighbours instead of just adding
## invisible overlap -- the QA harness below measures which one actually
## happened.
const COLLISION_OVERLAP := 0.8

## Thickness of the single flat floor-collision slab, in metres. Matches the
## convention `maze.gd` already uses for its own flat floor collider: the
## visible relief may sink below this, but must never rise above it.
const FLOOR_COLLISION_THICKNESS := 0.4


## targets: {
##   "wall_chunks": Node3D, "wall_body": StaticBody3D,
##   "ceiling_chunks": Node3D, "floor_chunks": Node3D,
##   "floor_body": StaticBody3D, "occluder": OccluderInstance3D,
##   "door_chunks": Node3D,
## }   -- any key may be absent or null; skip that part silently.
## opts: { "wall_rows": int = 2, "overlap": float = 0.2, "slab": float = 3.0,
##         "chunk": float = CHUNK, "shadows": bool = true }
##
## `loops` are contour polylines in RASTER GRID units exactly as
## `WallContour.trace`/`resample`/`smooth` produce them; `origin + grid_point *
## cell_size` maps to world XZ.
static func build(graph, loops: Array, cell_size: float, origin: Vector2,
		targets: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var wall_rows: int = int(opts.get("wall_rows", 2))
	var overlap: float = float(opts.get("overlap", 0.2))
	var slab: float = float(opts.get("slab", 3.0))
	var chunk: float = float(opts.get("chunk", CHUNK))
	var shadows: bool = bool(opts.get("shadows", true))
	_tint = float(opts.get("tint", DEFAULT_TINT))
	var wall_top: float = float(wall_rows) * Placer.WALL_BASE_HEIGHT

	var meshes := _load_meshes()
	var counts := {
		"wall_panels": 0, "ceiling_slabs": 0, "floor_slabs": 0,
		"doors": 0, "collision_shapes": 0, "wall_top": wall_top,
	}

	var wall_body = targets.get("wall_body")
	var occluder_target = targets.get("occluder")
	var world_loops: Array = []
	if wall_body != null or occluder_target != null:
		world_loops = _world_loops(loops, cell_size, origin)

	counts["wall_panels"] = _build_walls(graph, loops, cell_size, origin, meshes,
		targets.get("wall_chunks"), wall_rows, overlap, chunk, shadows)
	counts["collision_shapes"] += _build_wall_collision(graph, world_loops, wall_body, wall_top,
		_tall_zones(graph, wall_rows))
	if world_loops.is_empty() and targets.get("wall_chunks") != null:
		world_loops = _world_loops(loops, cell_size, origin)
	counts["shell_quads"] = _build_shell(graph, world_loops, targets.get("wall_chunks"),
		-SHELL_OVERSHOOT, wall_top + SHELL_OVERSHOOT, chunk)
	# The flat slab grid stays, and it is the layer that SEALS: a grid has no
	# preferred direction so it covers a corridor of any width. The vault is
	# hung just below it as the thing you actually look at.
	#
	# The vault alone did not work. It is one fixed 4.4 m span, and at a
	# junction where two corridors meet the passage is wider than that -- the
	# arches came out as scattered fragments with open sky between them, which
	# is the one thing this level must never show.
	counts["ceiling_slabs"] = _build_ceiling(graph, meshes,
		targets.get("ceiling_chunks"), slab, wall_top, chunk)
	counts["vault_bays"] = maxi(0, _build_vault(graph, meshes,
		targets.get("ceiling_chunks"),
		float(opts.get("vault_bay", 3.0)), float(opts.get("vault_width", 1.0)),
		wall_top - float(opts.get("vault_drop", 0.35)), chunk))
	counts["pillars"] = _build_pillars(graph, loops, cell_size, origin, meshes,
		targets.get("pillar_chunks"), float(opts.get("pillar_spacing", 6.0)),
		chunk, shadows)
	counts["floor_slabs"] = _build_floor(graph, meshes, targets.get("floor_chunks"),
		slab, chunk)
	counts["collision_shapes"] += _build_floor_collision(graph, targets.get("floor_body"), slab)
	counts["doors"] = _build_doors(graph, meshes, targets.get("door_chunks"), shadows)
	if occluder_target != null:
		_build_occluder(world_loops, occluder_target, wall_top)

	return counts


# --------------------------------------------------------------------------
# walls
# --------------------------------------------------------------------------

## One MultiMeshInstance3D per (variant, spatial chunk). Variant is dealt out
## by a hash of the panel's own world position -- see the file header for why
## that, and not a counter, is what determinism demands here.
static func _build_walls(graph, loops: Array, cell_size: float, origin: Vector2,
		meshes: Dictionary, wall_chunks: Node3D,
		wall_rows: int, overlap: float, chunk: float, shadows: bool) -> int:
	if wall_chunks == null:
		return 0
	_clear(wall_chunks)

	var transforms: Array[Transform3D] = Placer.wall_transforms(
		graph, loops, cell_size, origin, Placer.WALL_BASE_WIDTH, wall_rows, overlap,
		_tall_zones(graph, wall_rows))
	if transforms.is_empty():
		return 0

	var buckets := {
		"panel": [] as Array[Transform3D],
		"cracked": [] as Array[Transform3D],
		"window": [] as Array[Transform3D],
	}
	var window_cut := int(WINDOW_SHARE * 100.0)
	var cracked_cut := int((WINDOW_SHARE + CRACKED_SHARE) * 100.0)
	for t in transforms:
		# Quantised to a quarter-metre grid before hashing: two rows of the
		# same column share the same (x, z), which is what puts a whole
		# course-height of stone into one variant rather than alternating
		# panel/cracked up a single stack.
		var h := hash(Vector2i(int(round(t.origin.x * 4.0)), int(round(t.origin.z * 4.0))))
		var r: int = absi(h) % 100
		var pick := "panel"
		if r < window_cut:
			pick = "window"
		elif r < cracked_cut:
			pick = "cracked"
		buckets[pick].append(t)

	last_windows = buckets["window"].duplicate()
	var placed := 0
	for key in buckets:
		placed += _chunked_multimesh(wall_chunks, meshes.get(key), buckets[key],
			"Wall_" + key, chunk, shadows)
	return placed


## A chain of `BoxShape3D` segments walking each contour loop, instead of one
## shape per panel -- 3,736 collision shapes is a physics (and navmesh-bake)
## cost for nothing when a few hundred boxes describe the same boundary. This
## is what the navmesh actually bakes from, so it has to follow the real
## boundary, not a simplified stand-in for it.
static func _build_wall_collision(graph, world_loops: Array, wall_body, wall_top: float,
		tall_zones: Array = []) -> int:
	if wall_body == null:
		return 0
	_clear(wall_body)
	var added := 0
	for loop in world_loops:
		added += _collision_chain(graph, loop, wall_body, wall_top, tall_zones)
	return added


## How far behind the panel faces the sealing shell sits, in metres.
##
## The panels are 0.857 m thick and centred on the contour, so they reach about
## 0.43 m either side. Half a metre puts the shell just behind their back faces:
## hidden in normal play, but there to be seen through any seam.
const SHELL_OFFSET := 0.5
## Segment length the shell is built at. The contour carries ~0.06 m vertices,
## which would be tens of thousands of needless quads.
const SHELL_STEP := 1.2
## How far the shell runs past the floor and the ceiling. The seams at the top
## and bottom of a panel course leak sky just as readily as the vertical ones.
const SHELL_OVERSHOOT := 0.8


## An opaque skin behind the wall panels, so no seam can show the sky.
##
## The kit tiles a curved boundary with flat panels. However carefully they are
## spaced they cannot close every joint on an organic contour -- the measured
## worst gap is 0.174 m -- and each of those slivers was a hole straight through
## the level to the red skybox. Chasing the gaps to zero with more panels is the
## wrong fix: it is expensive, it distorts the stonework, and one bad seam still
## ruins it.
##
## So the walls get a backing. It is a plain dark ribbon following the same
## contour, half a metre behind the panel faces and running past both the floor
## and the ceiling. Nothing sees it except through a gap, and through a gap it
## reads as unlit rock, which is what is supposed to be there.
##
## Double-sided on purpose: which side of the ribbon a given seam is viewed
## from depends on the local curvature, and a one-sided skin vanishes from
## exactly the angles that most need it.
static func _build_shell(graph, world_loops: Array, parent: Node3D,
		y_lo: float, y_hi: float, chunk: float) -> int:
	if parent == null:
		return 0
	var holder := Node3D.new()
	holder.name = "Shell"
	parent.add_child(holder)

	var mat := StandardMaterial3D.new()
	# Near-black, and deliberately darker than the tinted stone: this is meant
	# to read as depth behind the wall, not as another surface.
	mat.albedo_color = Color(0.035, 0.033, 0.031)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var by_chunk := {}
	for loop in world_loops:
		var pts := _resample_closed(loop, SHELL_STEP)
		var n: int = pts.size()
		if n < 3:
			continue
		var offset: Array[Vector2] = []
		for i in n:
			var before: Vector2 = pts[(i - 1 + n) % n]
			var after: Vector2 = pts[(i + 1) % n]
			var tangent: Vector2 = after - before
			if tangent.length_squared() < 0.000001:
				tangent = Vector2(1.0, 0.0)
			tangent = tangent.normalized()
			var perp := Vector2(-tangent.y, tangent.x)
			# Push AWAY from the walkable side, asked of the graph rather than
			# inferred from the loop's winding -- `WallContour.trace()` does not
			# promise a winding and it flips between the outer boundary and the
			# rock islands inside it. Get this backwards and the shell lands in
			# the corridor, in front of the panels, as a black wall.
			if graph.distance(pts[i] + perp * 0.6) < graph.distance(pts[i] - perp * 0.6):
				perp = -perp
			offset.append(pts[i] + perp * SHELL_OFFSET)
		for i in n:
			var a: Vector2 = offset[i]
			var b: Vector2 = offset[(i + 1) % n]
			var mid := (a + b) * 0.5
			var key := Vector2i(int(floor(mid.x / chunk)), int(floor(mid.y / chunk)))
			if not by_chunk.has(key):
				by_chunk[key] = []
			(by_chunk[key] as Array).append([a, b])

	var quads := 0
	for key in by_chunk:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for seg in by_chunk[key]:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var v0 := Vector3(a.x, y_lo, a.y)
			var v1 := Vector3(b.x, y_lo, b.y)
			var v2 := Vector3(b.x, y_hi, b.y)
			var v3 := Vector3(a.x, y_hi, a.y)
			st.add_vertex(v0)
			st.add_vertex(v1)
			st.add_vertex(v2)
			st.add_vertex(v0)
			st.add_vertex(v2)
			st.add_vertex(v3)
			quads += 1
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Shell_%d_%d" % [key.x, key.y]
		holder.add_child(mi)
	return quads


## Evenly spaced points around a closed polyline.
static func _resample_closed(pts: Array, step: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n: int = pts.size()
	if n < 3:
		return out
	var cum := _closed_cumulative(pts)
	var perimeter: float = cum[n]
	if perimeter < 0.001:
		return out
	var count := maxi(3, int(round(perimeter / step)))
	for i in count:
		out.append(_sample_closed(pts, cum, perimeter * float(i) / float(count)))
	return out


## Spacing at which a collision segment inspects the contour it is covering.
## Finer than the panel width and coarser than the traced contour's own ~0.06 m
## vertex spacing, so a segment sees the shape of its arc without the
## furthest-pair search below turning quadratic on thousands of points.
const ARC_SAMPLE := 0.25

## How far down the kit's albedo is pulled before it is drawn.
##
## Tripo generated near-white limestone, and the level it replaces was built
## from dark brick. Dropped into the same lighting -- `Environment_dark`'s sky
## ambient at 0.38 energy plus the torches -- the pale stone blew out: measured
## against the old level's screenshot, mean luminance ran 0.336 against 0.134,
## and the shadows sat at 0.160 against 0.0125. Thirteen times too bright in the
## dark parts, which is to say there were no dark parts.
##
## Fixed on the material rather than by turning the torches down, because the
## torches were correct -- they lit the old level properly and they are the
## gameplay-relevant light. It is the stone that is the wrong colour.
const DEFAULT_TINT := 0.38

## Set once per `build()` rather than threaded through every placement call.
## Module-level state is not free, but the alternative is an extra parameter on
## four builders and two mesh helpers for a value that never varies within a
## build.
static var _tint := DEFAULT_TINT
static var _tint_cache := {}
## Where the window panels ended up, for the caller to hang red light behind.
## A module-level handoff rather than another out-parameter threaded through
## four builders for something only one consumer wants.
static var last_windows: Array[Transform3D] = []


## The kit's own material, darkened. Returns null when no tint is wanted, which
## leaves the imported material in place.
##
## `albedo_color` MULTIPLIES the albedo texture, so this keeps every map the
## generator produced -- colour, normal and ORM -- and only changes how much
## light the surface claims to reflect. Repainting the textures would have
## thrown away the normal detail that makes the stone read as stone.
static func _tinted(mesh: Mesh, tint: float) -> Material:
	if mesh == null or tint >= 0.999 or mesh.get_surface_count() == 0:
		return null
	var key := "%d:%.3f" % [mesh.get_instance_id(), tint]
	if _tint_cache.has(key):
		return _tint_cache[key]
	var src := mesh.surface_get_material(0)
	var out: Material = null
	if src is StandardMaterial3D:
		# Duplicated, never mutated in place: the mesh is a cached imported
		# resource, and editing its material would follow the .glb into every
		# other scene that ever loads it, including the editor's.
		var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
		var a: Color = m.albedo_color
		m.albedo_color = Color(a.r * tint, a.g * tint, a.b * tint, a.a)
		# Stone is not a metal. Every kit piece imported with `metallic = 1.0`
		# driving Tripo's packed ORM map, which made the walls behave like wet
		# metal: the torches threw hard specular highlights and the lit stone
		# measured p90 0.414 against the old level's 0.258, while the unlit
		# stone went black. Forcing the scalar to zero leaves the roughness and
		# occlusion channels doing their job and stops the level looking varnished.
		m.metallic = 0.0

		# World triplanar, the way the pre-kit brick wall was mapped.
		#
		# The kit's own UVs are baked per asset, so every copy of a panel
		# shows the identical patch of stone and the seam between two panels
		# is a hard break in the pattern. Projecting the texture in WORLD
		# space instead makes it continuous across the whole level: neighbours
		# share the same stone, the joins stop reading as tiles, and the
		# surface detail comes from the normal map rather than from the
		# silhouette -- which is what lets the geometry be flat.
		#
		# The numbers are the ones `Mat_wall` in `scenes/maze.tscn` shipped
		# with before the kit existed, and they are here because they were
		# already tuned against this game's lighting.
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(TRIPLANAR_SCALE, TRIPLANAR_SCALE, TRIPLANAR_SCALE)
		m.roughness = 0.92
		if m.normal_enabled:
			m.normal_scale = NORMAL_STRENGTH
		# The baked per-instance light arrives as MultiMesh instance colour, which
		# only reaches albedo if the material is told to use it.
		m.vertex_color_use_as_albedo = true
		out = m
	_tint_cache[key] = out
	return out


## The contour points a collision segment is responsible for, between two arc
## lengths. Returned in order, wrapping round the closed loop.
static func _arc_points(pts: Array, cum: PackedFloat32Array, s_lo: float,
		s_hi: float, perimeter: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var span: float = s_hi - s_lo
	if span <= 0.0 or perimeter <= 0.0:
		return out
	var count := maxi(2, int(ceil(span / ARC_SAMPLE)))
	for i in count + 1:
		var s: float = s_lo + span * float(i) / float(count)
		out.append(_sample_closed(pts, cum, fposmod(s, perimeter)))
	return out


static func _collision_chain(graph, pts: Array, wall_body, wall_top: float,
		tall_zones: Array = []) -> int:
	var n: int = pts.size()
	if n < 2:
		return 0
	var cum := _closed_cumulative(pts)
	var perimeter: float = cum[n]
	if perimeter < 0.001:
		return 0

	# Never fewer than twelve segments around a closed loop.
	#
	# A single segment runs all the way round and returns to its start, so its
	# chord degenerates and the whole island ends up with no collision -- solid
	# to look at, walk-through in play. And a SMALL loop curves hard: at a fixed
	# 2.5 m run the 15.6 m rock island came out 54% uncovered while the 688 m
	# outer wall was 4%, because the error scales with how tight the bend is,
	# not with how long the loop is.
	var segments := maxi(12, int(round(perimeter / COLLISION_RUN)))
	var step: float = perimeter / float(segments)
	var pad: float = COLLISION_OVERLAP * 0.5
	var added := 0

	for i in segments:
		var s_lo: float = float(i) * step - pad
		var s_hi: float = float(i + 1) * step + pad
		# Every contour point this segment is responsible for, not just its two
		# endpoints. The box is then sized to CONTAIN these, which is what makes
		# coverage a property of the construction instead of a hope about how
		# straight the wall happened to be.
		var arc := _arc_points(pts, cum, s_lo, s_hi, perimeter)
		if arc.size() < 2:
			continue
		added += _emit_box(graph, arc, wall_body, wall_top, 0, tall_zones)
	return added


## How far an arc may bow away from its own chord before the segment is split
## rather than wrapped in a fatter box, in metres.
##
## A box has to contain its arc, so a hard bend produces a box as deep as the
## bend -- and that depth points straight into the corridor. Padding and
## shorter runs got the worst intrusion down from 1.73 m to 1.52 m but could
## not remove it, because a fixed run length cannot know where the corners are.
## Splitting where the bow is actually large can.
const COLLISION_MAX_BOW := 0.30
const COLLISION_MAX_DEPTH := 4


## One collision box for this arc, or several if it bends too hard for one.
static func _emit_box(graph, arc: Array[Vector2], wall_body, wall_top: float,
		depth: int, tall_zones: Array = []) -> int:
	if arc.size() < 2:
		return 0
	# Orientation comes from the two furthest-apart points on the arc, not from
	# first-to-last. At a hairpin -- the contour running out around a thin rock
	# spur and straight back -- first and last very nearly coincide, the chord
	# collapses, and an earlier version discarded the segment as degenerate.
	# That left a 3.50 m hole in the wall at (54.2, 4.2): a doorway the player
	# could walk through, on geometry that looked solid.
	var a := arc[0]
	var b := arc[arc.size() - 1]
	var best: float = a.distance_squared_to(b)
	for u in arc.size():
		for v in range(u + 1, arc.size()):
			var d: float = arc[u].distance_squared_to(arc[v])
			if d > best:
				best = d
				a = arc[u]
				b = arc[v]

	var run := b - a
	var length := run.length()
	if length < 0.001:
		# A genuine point-like arc. Give it a square post rather than dropping
		# it; a skipped segment is a hole.
		run = Vector2(1.0, 0.0)
		length = 1.0
	var x_axis := Vector3(run.x, 0.0, run.y) / length
	var y_axis := Vector3.UP
	var z_axis := x_axis.cross(y_axis).normalized()

	# Extents of the arc in the box's own frame, so nothing it is meant to
	# cover can fall outside it.
	var min_u := INF
	var max_u := -INF
	var min_v := INF
	var max_v := -INF
	var axis_u := Vector2(x_axis.x, x_axis.z)
	var axis_v := Vector2(z_axis.x, z_axis.z)
	for p in arc:
		var u: float = p.dot(axis_u)
		var v: float = p.dot(axis_v)
		min_u = minf(min_u, u)
		max_u = maxf(max_u, u)
		min_v = minf(min_v, v)
		max_v = maxf(max_v, v)

	# Bends too hard for one box get split instead of wrapped in a fatter one.
	# The extra depth of a fat box points into the corridor, which is the whole
	# problem; halving the arc halves the bow.
	if max_v - min_v > COLLISION_MAX_BOW and depth < COLLISION_MAX_DEPTH \
			and arc.size() >= 4:
		var mid: int = arc.size() / 2
		var left: Array[Vector2] = arc.slice(0, mid + 1)
		var right: Array[Vector2] = arc.slice(mid)
		return _emit_box(graph, left, wall_body, wall_top, depth + 1, tall_zones) \
			+ _emit_box(graph, right, wall_body, wall_top, depth + 1, tall_zones)

	var centre_uv := Vector2((min_u + max_u) * 0.5, (min_v + max_v) * 0.5)
	var centre := axis_u * centre_uv.x + axis_v * centre_uv.y
	var span_u: float = max_u - min_u
	var span_v: float = (max_v - min_v) + COLLISION_THICKNESS

	# Push the box OUTWARD so its inner face sits on the wall, not its centre
	# line.
	#
	# This was the invisible wall. The box was centred on the contour with
	# 1.6 m of thickness, so it reached 0.8 m INTO the corridor along every
	# wall in the level -- the player stopped short of the visible stone
	# everywhere, and a chest-room doorway lost 1.6 m of its width to the two
	# sides closing in. It went unnoticed because the test meant to catch it
	# sampled only corridor centrelines, which sit 2.2 m from the boundary and
	# never entered the intruding shell.
	var outward := axis_v
	if graph.distance(centre + axis_v * 0.6) < graph.distance(centre - axis_v * 0.6):
		outward = -axis_v

	# Never thicker than the rock actually behind the wall.
	#
	# The remaining intrusions were not bends at all. Where the rock between
	# two corridors is thinner than the box -- a spur, or the wall between a
	# dead end and the passage beside it -- a 1.6 m box pushed outward simply
	# came out the far side into the next corridor. That was the 1.52 m
	# intrusion at (-40.5, 31.0) that subdividing could not touch, because the
	# arc there is almost straight.
	#
	# So the rock is probed: step outward until the region turns walkable again
	# and stop short of it.
	# Probed along the whole arc, not just at its midpoint, and the THINNEST
	# reading wins. Sampling only the centre left 24 points still blocked and a
	# 0.65 m intrusion: rock thickness varies along a box, so a narrow spot at
	# either end punches through even when the middle is solid.
	var thickness := COLLISION_THICKNESS
	for sample_i in 5:
		var along: Vector2 = arc[int(float(sample_i) * float(arc.size() - 1) / 4.0)]
		var probe := 0.15
		while probe <= COLLISION_THICKNESS:
			if graph.distance(along + outward * probe) < 0.0:
				thickness = minf(thickness, maxf(0.2, probe - 0.15))
				break
			probe += 0.15
	var placed := centre + outward * (thickness * 0.5)
	span_v = (max_v - min_v) + thickness

	# Collision follows the taller chest-room wall. A visually higher wall with
	# corridor-height collision is no barrier at all -- the shove would put the
	# player straight through the courses that were added to stop it.
	var top := wall_top
	for zone in tall_zones:
		if centre.distance_to(zone["centre"]) <= float(zone["radius"]):
			top = maxf(top, float(zone["rows"]) * Placer.WALL_BASE_HEIGHT)
			break

	var box := BoxShape3D.new()
	box.size = Vector3(span_u + COLLISION_END_PAD, top, span_v)
	var collider := CollisionShape3D.new()
	collider.shape = box
	# Spans the arc it owns and then only outward from it, so the wall is solid
	# from its face backwards and the corridor keeps its full width.
	collider.transform = Transform3D(Basis(x_axis, y_axis, z_axis),
		Vector3(placed.x, top * 0.5, placed.y))
	wall_body.add_child(collider)
	return 1


# --------------------------------------------------------------------------
# ceiling
# --------------------------------------------------------------------------

## A vaulted ceiling running along the corridors, when the vault piece exists.
##
## Returns -1 when there is no vault mesh, so the caller can fall back to the
## flat slab grid rather than shipping a level with no ceiling at all.
static func _build_vault(graph, meshes: Dictionary, ceiling_chunks: Node3D,
		bay: float, width: float, height: float, chunk: float) -> int:
	if ceiling_chunks == null:
		return 0
	var mesh = meshes.get("vault")
	if mesh == null:
		return -1

	var transforms: Array[Transform3D] = Placer.vault_transforms(graph, bay, width, height)
	# Never casts shadows: there is nothing above it to shadow, and an omni
	# shadow is a cube map re-rendered per caster per frame.
	return _chunked_multimesh(ceiling_chunks, mesh, transforms, "Vault", chunk, false)


## Engaged piers along the corridor walls, marking the bays as in the
## reference. Silently does nothing when the pillar piece is absent.
static func _build_pillars(graph, loops: Array, cell_size: float, origin: Vector2,
		meshes: Dictionary, pillar_chunks: Node3D, spacing: float,
		chunk: float, shadows: bool) -> int:
	if pillar_chunks == null:
		return 0
	var mesh = meshes.get("pillar")
	if mesh == null:
		return 0
	_clear(pillar_chunks)
	var transforms: Array[Transform3D] = Placer.pillar_transforms(
		graph, loops, cell_size, origin, spacing, PILLAR_EMBED)
	return _chunked_multimesh(pillar_chunks, mesh, transforms, "Pillars", chunk, shadows)


static func _build_ceiling(graph, meshes: Dictionary, ceiling_chunks: Node3D,
		slab: float, wall_top: float, chunk: float) -> int:
	if ceiling_chunks == null:
		return 0
	_clear(ceiling_chunks)
	var transforms: Array[Transform3D] = Placer.ceiling_transforms(graph, slab, wall_top)
	# The chest chambers are roofless, like the arena: the user asked for open
	# sky over them with pillars, which is how the level read before the kit.
	# Filtered here rather than inside `kit_placer` because that module answers
	# "where does a ceiling go" for the region in general, and which rooms are
	# open is this level's decision, not the placer's.
	var roofed: Array[Transform3D] = []
	for t in transforms:
		var xz := Vector2(t.origin.x, t.origin.z)
		var open_room := false
		for i in graph.chamber_at.keys():
			# A half-slab margin, so the hole reaches the chamber wall instead
			# of leaving a ring of ceiling hanging over its edge.
			if xz.distance_to(graph.nodes[i]) <= float(graph.chamber_at[i]) + slab * 0.5:
				open_room = true
				break
		if not open_room:
			roofed.append(t)
	transforms = roofed
	# Nothing lives above the ceiling but sky -- it never needs to cast a
	# shadow on anything, regardless of `opts.shadows`.
	return _chunked_multimesh(ceiling_chunks, meshes.get("ceiling"), transforms,
		"Ceiling", chunk, false)


# --------------------------------------------------------------------------
# floor
# --------------------------------------------------------------------------

## Bounding box of the walkable region, padded the same way
## `Placer.ceiling_transforms` pads its own grid. Duplicated rather than
## shared because that function is `kit_placer.gd`'s and not this file's to
## change; the two are meant to describe the same rectangle.
static func _walkable_bounds(graph, slab: float) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in graph.nodes:
		lo = Vector2(minf(lo.x, n.x), minf(lo.y, n.y))
		hi = Vector2(maxf(hi.x, n.x), maxf(hi.y, n.y))
	for c in graph.cells:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.y))
	if lo.x > hi.x:
		return []
	var pad: float = graph.boss_radius + slab * 2.0
	return [lo - Vector2(pad, pad), hi + Vector2(pad, pad)]


## Same dilated-grid rule `Placer.ceiling_transforms` uses -- test a grid
## point against `graph.distance()` inflated by half a slab, so the last slab
## before a wall still reaches it -- but WITHOUT the boss-arena exclusion: the
## arena has no ceiling by design, but it still needs somewhere to stand.
static func _floor_transforms(graph, slab: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var bounds := _walkable_bounds(graph, slab)
	if bounds.is_empty():
		return out
	var lo: Vector2 = bounds[0]
	var hi: Vector2 = bounds[1]

	var step: float = slab * 0.9
	var reach: float = slab * 0.6
	var nx := int(ceil((hi.x - lo.x) / step))
	var ny := int(ceil((hi.y - lo.y) / step))
	for gy in range(ny + 1):
		for gx in range(nx + 1):
			var p := lo + Vector2(float(gx), float(gy)) * step
			# `distance()` is negative inside the region; `< reach` is
			# therefore "inside, or within half a slab of being inside".
			if graph.distance(p) >= reach:
				continue
			# The slab's origin is its TOP face, so y = 0 puts its surface
			# exactly at the floor plane the rest of the level stands on.
			out.append(Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)))
	return out


static func _build_floor(graph, meshes: Dictionary, floor_chunks: Node3D,
		slab: float, chunk: float) -> int:
	if floor_chunks == null:
		return 0
	_clear(floor_chunks)
	var transforms := _floor_transforms(graph, slab)
	return _chunked_multimesh(floor_chunks, meshes.get("floor"), transforms, "Floor", chunk, false)


## A single flat box under the whole region, not one shape per slab -- the
## navmesh and the player's footing only ever need one flat plane, and the
## visible relief (if any is layered on top later) is cosmetic.
static func _build_floor_collision(graph, floor_body, slab: float) -> int:
	if floor_body == null:
		return 0
	_clear(floor_body)
	var bounds := _walkable_bounds(graph, slab)
	if bounds.is_empty():
		return 0
	var lo: Vector2 = bounds[0]
	var hi: Vector2 = bounds[1]

	var box := BoxShape3D.new()
	box.size = Vector3(hi.x - lo.x, FLOOR_COLLISION_THICKNESS, hi.y - lo.y)
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.position = Vector3((lo.x + hi.x) * 0.5, -FLOOR_COLLISION_THICKNESS * 0.5,
		(lo.y + hi.y) * 0.5)
	floor_body.add_child(collider)
	return 1


# --------------------------------------------------------------------------
# cell doors and frames
# --------------------------------------------------------------------------

static func _build_doors(graph, meshes: Dictionary, door_chunks: Node3D, shadows: bool) -> int:
	if door_chunks == null:
		return 0
	_clear(door_chunks)

	var doors: Array[Transform3D] = Placer.cell_door_transforms(graph, Placer.DOOR_BASE_HEIGHT)
	if doors.is_empty():
		return 0

	var frames: Array[Transform3D] = []
	for t in doors:
		# Pushed back along local -Z so the bars sit inside the archway
		# instead of z-fighting with it (see preview_kit_level.gd).
		frames.append(Transform3D(t.basis, t.origin - t.basis.z * 0.35))

	var door_mesh: Mesh = meshes.get("door")
	if door_mesh != null:
		_flat_multimesh(door_chunks, door_mesh, doors, "Doors", shadows)
	var frame_mesh: Mesh = meshes.get("frame")
	if frame_mesh != null:
		_flat_multimesh(door_chunks, frame_mesh, frames, "Frames", shadows)

	return doors.size()


# --------------------------------------------------------------------------
# occluder
# --------------------------------------------------------------------------

## Vertical quads along each contour loop, `wall_top` tall -- corridors are
## exactly the case occlusion culling pays for, per CLAUDE.md's own numbers.
static func _build_occluder(world_loops: Array, occluder: OccluderInstance3D,
		wall_top: float) -> void:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for loop in world_loops:
		var n: int = loop.size()
		for i in n:
			var a: Vector2 = loop[i]
			var b: Vector2 = loop[(i + 1) % n]
			var base := verts.size()
			verts.append(Vector3(a.x, 0.0, a.y))
			verts.append(Vector3(b.x, 0.0, b.y))
			verts.append(Vector3(b.x, wall_top, b.y))
			verts.append(Vector3(a.x, wall_top, a.y))
			indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var shape := ArrayOccluder3D.new()
	shape.set_arrays(verts, indices)
	occluder.occluder = shape


# --------------------------------------------------------------------------
# shared helpers
# --------------------------------------------------------------------------

## Every kit piece is a .glb, so Godot hands back a PackedScene; the mesh is on
## the one MeshInstance3D inside it. Same approach as `preview_kit_level.gd`,
## which already proved it works.
static func _mesh_of(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	# Untyped on purpose: `load()` returns Variant, so `:=` has nothing to infer
	# from and the file will not parse.
	var packed = load(path)
	if packed == null:
		return null
	var inst = packed.instantiate()
	var found: Mesh = null
	var stack: Array = [inst]
	while not stack.is_empty():
		var current = stack.pop_back()
		if current is MeshInstance3D and found == null:
			found = (current as MeshInstance3D).mesh
		for c in current.get_children():
			stack.append(c)
	inst.queue_free()
	return found


static func _load_meshes() -> Dictionary:
	var out := {}
	for key in KIT_PATHS:
		out[key] = _mesh_of(KIT_PATHS[key])
		if out[key] == null:
			push_error("organic_maze: kit piece missing or not imported: %s" % KIT_PATHS[key])
	return out


static func _clear(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.free()


## Godot culls a MultiMeshInstance3D as one object, against the AABB of every
## instance in it -- a single MultiMesh spanning the whole map is always in
## the frustum no matter where the player stands. Chunking by world position
## lets the frustum and the occluders throw away the parts that are not
## visible, the same reasoning `maze.gd` and `preview_kit_level.gd` already
## apply to their own geometry.
##
## Returns how many instances it actually placed, NOT how many it was asked to.
## The callers report this as the level's geometry count, and a count that
## reports intent instead of outcome is how a missing mesh went unnoticed: the
## floor slab had never been imported, `mesh` was null, this returned silently,
## and the build still claimed 1,571 floor slabs on an empty node.
static func _chunked_multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D],
		name: String, chunk: float, cast_shadow: bool) -> int:
	if mesh == null or xforms.is_empty():
		if mesh == null and not xforms.is_empty():
			push_warning("organic_maze: no mesh for '%s'; %d placements dropped"
				% [name, xforms.size()])
		return 0
	var by_chunk := {}
	for t in xforms:
		var key := Vector2i(int(floor(t.origin.x / chunk)), int(floor(t.origin.z / chunk)))
		if not by_chunk.has(key):
			by_chunk[key] = [] as Array[Transform3D]
		(by_chunk[key] as Array[Transform3D]).append(t)

	var holder := Node3D.new()
	holder.name = name
	parent.add_child(holder)
	for key in by_chunk:
		var group: Array[Transform3D] = by_chunk[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Per-instance colour, enabled before `instance_count` for the same reason
		# `transform_format` is: setting either afterwards reallocates the buffer and
		# silently discards what was already written. This is what carries the baked
		# torchlight -- see `organic_lighting.gd`.
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = group.size()
		for i in group.size():
			mm.set_instance_transform(i, group[i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = _tinted(mesh, _tint)
		inst.name = "%s_%d_%d" % [name, key.x, key.y]
		if not cast_shadow:
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(inst)
	return xforms.size()


## A single, unchunked MultiMesh -- for doors and frames, which cluster tight
## around the arena rim rather than spreading across the whole map, so there
## is nothing for spatial chunking to buy here.
static func _flat_multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D],
		name: String, cast_shadow: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Per-instance colour, enabled before `instance_count` for the same reason
	# `transform_format` is: setting either afterwards reallocates the buffer and
	# silently discards what was already written. This is what carries the baked
	# torchlight -- see `organic_lighting.gd`.
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = _tinted(mesh, _tint)
	inst.name = name
	if not cast_shadow:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


## Grid-unit loop -> deduplicated world-space points, dropping a repeated
## closing vertex. Same mapping `kit_placer.gd` uses (`world = origin +
## grid_point * cell_size`), kept as our own copy since that function is
## private to a file this module may not edit.
static func _to_world_loop(loop, cell_size: float, origin: Vector2) -> Array:
	var out: Array = []
	for gp in loop:
		var world: Vector2 = origin + Vector2(gp.x, gp.y) * cell_size
		if out.is_empty() or out[-1].distance_to(world) > 0.0001:
			out.append(world)
	if out.size() > 1 and out[0].distance_to(out[-1]) <= 0.0001:
		out.remove_at(out.size() - 1)
	return out


static func _world_loops(loops: Array, cell_size: float, origin: Vector2) -> Array:
	var out: Array = []
	for loop in loops:
		var w := _to_world_loop(loop, cell_size, origin)
		if w.size() >= 3:
			out.append(w)
	return out


## Cumulative arc length around a CLOSED polyline, including the closing
## segment back to the start. Size n + 1; index n holds the full perimeter.
static func _closed_cumulative(pts: Array) -> PackedFloat32Array:
	var n: int = pts.size()
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in range(n):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		cum[i + 1] = cum[i] + a.distance_to(b)
	return cum


## Position at arc length `s` along a CLOSED polyline, using `cum` as built by
## `_closed_cumulative`.
static func _sample_closed(pts: Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var n: int = pts.size()
	s = clampf(s, 0.0, cum[n])
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if cum[mid + 1] <= s:
			lo = mid + 1
		else:
			hi = mid
	var idx := lo
	var a: Vector2 = pts[idx]
	var b: Vector2 = pts[(idx + 1) % n]
	var seg_len: float = cum[idx + 1] - cum[idx]
	var t := 0.0
	if seg_len > 0.000001:
		t = clampf((s - cum[idx]) / seg_len, 0.0, 1.0)
	return a.lerp(b, t)
