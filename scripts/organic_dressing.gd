extends RefCounted

## Hangs torches on the organic maze's walls, and scatters bone debris on its
## floor.
##
## The old level picked "wall faces" off the square tile grid: a solid tile with
## an open neighbour gave both a position and a cardinal facing for free. The
## organic level has no such thing -- its boundary is a smoothed polyline at
## arbitrary angles -- so everything here works in arc length along that
## contour instead.
##
## Torches are not decoration. `Environment_dark` runs sky ambient at 0.38
## energy with a 0.07-energy moon, which is to say the player sees almost
## nothing that a torch is not lighting. A torch mounted facing into solid rock
## lights nothing, so which way round it goes is the whole job.
##
## Autoload names do not resolve under `--script` (see CLAUDE.md), so `Graphics`
## is fetched by path and tolerated as null.

const Placer = preload("res://scripts/kit_placer.gd")

## How far out of the wall a torch sits. The panels are rough stone and their
## surface wanders either side of the traced contour, so a torch flush with the
## contour ends up half-buried in a block.
const TORCH_PROUD := 0.35

## Debris clusters are chunked at this edge length, for the same reason every
## other MultiMesh in this project is: a single one spanning the map has one
## AABB, always intersects the frustum, and can never be culled.
const CHUNK := 24.0


## `loops` are contour polylines in RASTER GRID units, as `WallContour` produces
## them; `origin + point * cell_size` maps to world XZ.
##
## `targets` may omit or null any of "torches", "debris_chunks", "lean_chunks";
## that part is then skipped. Returns the counts actually placed.
static func build(graph, loops: Array, cell_size: float, origin: Vector2,
		targets: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var spacing: float = float(opts.get("torch_spacing", 13.0))
	var height: float = float(opts.get("torch_height", 2.5))
	var torch_scene: PackedScene = opts.get("torch_scene")
	var seed_value: int = int(opts.get("seed", 0))

	var out := {"torches": 0, "debris": 0, "leaning_bars": 0}
	var world_loops := _world_loops(loops, cell_size, origin)

	out["torches"] = _build_torches(graph, world_loops, targets.get("torches"),
		torch_scene, spacing, height, float(opts.get("torch_energy", 1.0)), bool(opts.get("torch_shadows", true)))
	out["debris"] = _build_debris(graph, targets.get("debris_chunks"),
		int(opts.get("skull_count", 0)), int(opts.get("bone_count", 0)), seed_value)
	return out


# --------------------------------------------------------------------------
# torches
# --------------------------------------------------------------------------

## One torch every `spacing` metres of wall, facing into the open.
##
## The spacing is closed exactly around each loop -- `count` steps of
## `perimeter / count` rather than fixed strides with a remainder -- so the last
## torch before the seam is no further from the first than any other pair. A
## leftover stride is a dark spot, and a dark spot in this game is a place the
## player cannot see a skeleton coming.
static func _build_torches(graph, world_loops: Array, holder: Node3D,
		torch_scene: PackedScene, spacing: float, height: float,
		energy_scale: float = 1.0, shadows: bool = true) -> int:
	if holder == null or torch_scene == null or spacing <= 0.0:
		return 0
	_clear(holder)

	var placed := 0
	for loop in world_loops:
		var n: int = loop.size()
		if n < 3:
			continue
		var cum := _closed_cumulative(loop)
		var perimeter: float = cum[n]
		if perimeter < spacing * 0.5:
			# A short island does not need a ring of torches round it, but it
			# should not be a black hole either.
			continue
		var count := maxi(1, int(round(perimeter / spacing)))
		var step: float = perimeter / float(count)

		for i in count:
			var s: float = float(i) * step
			var p: Vector2 = _sample_closed(loop, cum, s)
			# Tangent over a window rather than from the one segment the sample
			# landed on: the traced contour carries sub-metre raster jitter, and
			# a segment-local normal chases that noise and can point a torch
			# sideways into the wall it is mounted on.
			var ahead: Vector2 = _sample_closed(loop, cum, fposmod(s + 1.5, perimeter))
			var behind: Vector2 = _sample_closed(loop, cum, fposmod(s - 1.5, perimeter))
			var tangent: Vector2 = ahead - behind
			if tangent.length_squared() < 0.000001:
				continue
			tangent = tangent.normalized()

			var inward := _open_side(graph, p, tangent)
			if inward == Vector2.ZERO:
				continue

			var torch := torch_scene.instantiate()
			torch.position = Vector3(p.x, height, p.y) \
				+ Vector3(inward.x, 0.0, inward.y) * TORCH_PROUD
			# The torch scene points its flame down its own -Z, so -Z has to
			# become `inward`. A yaw of t gives local +Z = (sin t, 0, cos t),
			# hence -Z = (-sin t, 0, -cos t); setting that equal to `inward`
			# needs the NEGATED arguments. `atan2(inward.x, inward.y)` is the
			# same angle turned 180 degrees, which mounts every torch facing
			# into the rock it is bolted to -- lighting nothing.
			torch.rotation.y = atan2(-inward.x, -inward.y)
			# `torch.gd` recomputes `light_energy = base_energy * flicker` every
			# frame, so the scale has to go on `base_energy` -- setting the
			# light's energy directly would be overwritten on the next frame.
			if energy_scale != 1.0 and "base_energy" in torch:
				torch.base_energy = torch.base_energy * energy_scale
			# Set BEFORE the torch enters the tree. `Graphics._apply_light()`
			# snapshots `shadow_enabled` into meta the first time it sees a
			# light and will never switch one on that was authored off, so
			# doing it here makes the choice stick instead of being restored on
			# the next `apply_all()`.
			if not shadows:
				var l := torch.get_node_or_null(^"Light")
				if l is Light3D:
					(l as Light3D).shadow_enabled = false
			holder.add_child(torch)
			placed += 1
	return placed


## Which side of the contour at `p` is walkable, asked of the graph directly.
##
## Never inferred from the loop's winding: `WallContour.trace()` does not
## promise a consistent winding and it flips between the outer boundary and the
## rock islands inside it, which would turn every torch on those islands to
## face into the rock.
static func _open_side(graph, p: Vector2, tangent: Vector2) -> Vector2:
	var perp := Vector2(-tangent.y, tangent.x)
	const PROBE := 0.6
	var a: bool = graph.inside(p + perp * PROBE)
	var b: bool = graph.inside(p - perp * PROBE)
	if a and not b:
		return perp
	if b and not a:
		return -perp
	# Both probes agreed: a sampling artefact right on the boundary. Fall back
	# to the analytic signed distance, which has no such ambiguity.
	if graph.distance(p + perp * PROBE) < graph.distance(p - perp * PROBE):
		return perp
	return -perp


# --------------------------------------------------------------------------
# debris
# --------------------------------------------------------------------------

## Skulls and loose bone strewn on the floor, as chunked MultiMeshes.
##
## Optional by definition, so it checks `Graphics.effects` first: on the lowest
## preset this is exactly the sort of thing that should not exist at all.
static func _build_debris(graph, holder: Node3D, skulls: int, bones: int,
		seed_value: int) -> int:
	if holder == null or (skulls <= 0 and bones <= 0):
		return 0
	_clear(holder)
	var gfx = _graphics()
	if gfx != null and not gfx.effects:
		return 0

	# Its own generator, seeded from the level seed. `Array.shuffle()` and the
	# global `randf()` both draw from Godot's GLOBAL random stream, so a level
	# built after anything else had consumed randomness would come out
	# different from the same seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x5EED

	var skull := SphereMesh.new()
	skull.radius = 0.11
	skull.height = 0.22
	skull.radial_segments = 6
	skull.rings = 4
	var bone := BoxMesh.new()
	bone.size = Vector3(0.32, 0.055, 0.055)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.70, 0.63)
	mat.roughness = 0.9
	skull.material = mat
	bone.material = mat

	var placed := 0
	placed += _scatter(graph, holder, skull, skulls, rng, "Skulls", 0.11)
	placed += _scatter(graph, holder, bone, bones, rng, "Bones", 0.03)
	return placed


## Rejection-samples positions inside the walkable region and drops `count`
## copies of `mesh` on the floor there.
static func _scatter(graph, holder: Node3D, mesh: Mesh, count: int,
		rng: RandomNumberGenerator, name: String, lift: float) -> int:
	if count <= 0:
		return 0
	var bounds := _bounds(graph)
	var lo: Vector2 = bounds[0]
	var hi: Vector2 = bounds[1]

	var xforms: Array[Transform3D] = []
	var tries := 0
	while xforms.size() < count and tries < count * 60:
		tries += 1
		var p := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
		# Well inside, not merely inside: a skull half-buried in the wall reads
		# as a bug rather than as dressing.
		if graph.distance(p) > -0.8:
			continue
		var t := Transform3D(Basis.IDENTITY, Vector3(p.x, lift, p.y))
		t.basis = t.basis.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		xforms.append(t)

	if xforms.is_empty():
		return 0
	_chunked(holder, mesh, xforms, name)
	return xforms.size()


static func _bounds(graph) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in graph.nodes:
		lo = Vector2(minf(lo.x, n.x), minf(lo.y, n.y))
		hi = Vector2(maxf(hi.x, n.x), maxf(hi.y, n.y))
	var pad: float = graph.boss_radius + 4.0
	return [lo - Vector2(pad, pad), hi + Vector2(pad, pad)]


static func _chunked(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D],
		name: String) -> void:
	var by_chunk := {}
	for t in xforms:
		var key := Vector2i(int(floor(t.origin.x / CHUNK)), int(floor(t.origin.z / CHUNK)))
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
		mm.mesh = mesh
		mm.instance_count = group.size()
		for i in group.size():
			mm.set_instance_transform(i, group[i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.name = "%s_%d_%d" % [name, key.x, key.y]
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(inst)


# --------------------------------------------------------------------------
# shared helpers
# --------------------------------------------------------------------------

## Autoloads are not in scope under `--script`, so this asks the tree by path
## and returns null when there is no tree to ask.
static func _graphics():
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(^"/root/Graphics")


static func _clear(node: Node) -> void:
	for child in node.get_children():
		child.free()


static func _world_loops(loops: Array, cell_size: float, origin: Vector2) -> Array:
	var out: Array = []
	for loop in loops:
		var pts: Array[Vector2] = []
		for gp in loop:
			var world: Vector2 = origin + Vector2(gp.x, gp.y) * cell_size
			if pts.is_empty() or pts[-1].distance_to(world) > 0.0001:
				pts.append(world)
		# A traced loop can repeat its start point at the end; drop it so the
		# closing segment is not zero-length.
		if pts.size() > 1 and pts[0].distance_to(pts[-1]) <= 0.0001:
			pts.remove_at(pts.size() - 1)
		if pts.size() >= 3:
			out.append(pts)
	return out


static func _closed_cumulative(pts: Array) -> PackedFloat32Array:
	var n: int = pts.size()
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in n:
		cum[i + 1] = cum[i] + (pts[i] as Vector2).distance_to(pts[(i + 1) % n])
	return cum


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
	var a: Vector2 = pts[lo]
	var b: Vector2 = pts[(lo + 1) % n]
	var seg: float = cum[lo + 1] - cum[lo]
	if seg <= 0.000001:
		return a
	return a.lerp(b, clampf((s - cum[lo]) / seg, 0.0, 1.0))
