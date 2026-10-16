extends Node3D

## The sewer (2026-10-15): brick pipes under the dungeon, reached by ladders down
## the five manholes (manhole.gd).
##
## Layout, on the dungeon's own 6 m grid so the map can draw it the same way
## (`SewerMap`, handed to explore_map.gd as a second level): the manhole cells
## are its nodes, joined by a minimum spanning tree plus one extra link (a
## single loop) -- much simpler than the maze above -- each link an L of pipe
## along the grid, and a few short dead-end spurs. Chosen from the level seed.
##
## Second remake (2026-10-15): ONE piece of stone. Pipes, chambers, the
## watercourse and the culverts are a single CSG tree (`_build_csg`, baked a frame
## later and split into CHUNK-sized pieces), all in one material,
## shaders/sewer_stone.gdshader: the domes' Higgsfield brick, darker, mapped in
## world space, under black mold, a sludge line, sludge and slime (Higgsfield
## textures too: tools/build_sewer_texture.py). Nothing meets anything at a
## seam, and the channel runs unbroken through every chamber. The water is one
## plane per cell under the walkways, world-mapped (shaders/sewer_water.gdshader).
##
## Straights are a brick pipe: walls PIPE_SPRING high under a round vault, a
## walkway each side of a channel with a rounded invert. Every other cell -- bend,
## junction, dead end, manhole -- is a round domed CHAMBER; the pipes run into it
## and their channels cross in its middle. A closed side is a CULVERT, a smaller
## pipe into the rock behind an iron grille made to its arch, its channel running
## out under the bars.
##
## No torches. The light is bioluminescent moss (`_build_moss`: Higgsfield moss as
## emissive decals in the cracks along the wall's foot and in patches up the
## walls, some with a faint omni of their own), fireflies drifting in the pipes
## (`_build_fireflies`), and a musty haze (`_set_below` changes the fog while the
## camera is down here). Everything here draws on VISUAL_LAYER, which no dungeon
## light reaches (maze `_wall_off_sewer`), and the sewer is hidden while the
## camera is above ground.

const ModuleMaze := preload("res://scripts/module_maze.gd")

## The walkway's height. The dungeon's floor is 0; its collision slab ends at -1.2.
const FLOOR_Y := -12.0
## Below this the camera is in the sewer (torch.gd uses the same split).
const SPLIT_Y := -4.0
## The generated props (tools/build_sewer_kit.py): "bones".
const KIT := "res://models/sewer/sewer_kit.glb"
## The pipe, across (x) and up (y) from the walkway at its middle: walls stand at
## +-PIPE_HALF and rise PIPE_SPRING before a round vault (crown 3.9 m).
const PIPE_HALF := 2.0
const PIPE_SPRING := 1.9
const SHELL := 0.8
const ARC_STEPS := 20
## The channel down the middle: straight sides CHANNEL_SIDE deep, then a round
## invert of radius CHANNEL_HALF (bottom 1.02 m down). Water stands at WATER_Y.
const CHANNEL_HALF := 0.62
const CHANNEL_SIDE := 0.4
const WATER_Y := -0.42
## Below everything: the stone's underside.
const BASE := -1.7
## The chambers: inner radius CH_R (the wall on the cell's edge), walls CH_WALL
## high under a dome rising DOME_RISE more.
const CH_R := 3.0
const CH_SHELL := 0.8
const CH_WALL := 4.4
const DOME_RISE := 1.8
## Culverts: a smaller pipe (the same shape at CULVERT_SCALE) into the rock on a
## chamber's closed side, CULVERT_DEEP beyond the wall (CULVERT_SHORT when another
## pipe runs past behind it), barred by a grille GRILLE_IN into its mouth.
const CULVERT_SCALE := 0.5
const CULVERT_DEEP := 2.2
const CULVERT_SHORT := 0.6
const GRILLE_IN := 0.22
const BAR_EVERY := 0.13
## The shaft up to the manhole.
const SHAFT_R := 0.56
const SHAFT_OUTER := 0.95
## Dead-end spurs off the main runs.
const SPURS := 3
## Render chunks.
const CHUNK := 24.0
const VISUAL_LAYER := 1 << 15
## Draw distance for the props, moss and fireflies.
const PIECE_RANGE := 40.0
## Bone heaps: share of pipe cells with one.
const BONES_SHARE := 0.22
## The ladder's rails stand this far from the shaft's centre (manhole.gd too).
const LADDER_OUT := 0.36
const RUNG_EVERY := 0.3
## The moss.
const MOSS_GLOW := Color(0.32, 1.0, 0.62)
const MOSS_LIGHT := Color(0.3, 1.0, 0.62)
const MOSS_LIGHT_ENERGY := 1.2
const MOSS_LIGHT_RANGE := 4.5
## Share of moss clusters that carry a light.
const MOSS_LIT_SHARE := 0.6
## The haze while the camera is below.
const HAZE_COLOUR := Color(0.06, 0.07, 0.045)
const HAZE_ENERGY := 1.0
const HAZE_DENSITY := 0.06
## And the base light: cold and a little green, a touch more than the dungeon's,
## which reads as black on stone this dark.
const DAMP_AMBIENT := Color(0.15, 0.18, 0.15)
const DAMP_AMBIENT_SCALE := 2.2

var built
var map: SewerMap
## Per manhole cell: {cell, hole (world, at the dungeon floor), along, foot
## (world, the ladder's foot on the walkway), chamber (world centre)}.
var shafts: Array[Dictionary] = []
var _csg: CSGCombiner3D
## Everything hidden while the camera is above ground.
var _chunks: Array[Node3D] = []
var _player: Node3D
var _below := false
var _stone: ShaderMaterial
var _iron: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
## The environment's own fog, kept while the haze is on.
var _fog_saved := {}

## The sewer's cells, in the shape explore_map.gd reads a level in.
class SewerMap extends RefCounted:
	var cells := {}
	var size: Vector2i
	var cell_size: float
	var origin: Vector3
	var rooms: Array[Dictionary] = []
	var doors: Array = []
	## Where each ladder comes down, for the map.
	var ladders: Array[Vector3] = []

	func to_world(grid: Vector2i) -> Vector3:
		return origin + Vector3(float(grid.x) * cell_size, FLOOR_Y, float(grid.y) * cell_size)


static func build(parent: Node3D, level_built, seed_value: int) -> Node3D:
	if level_built.manholes.is_empty():
		return null
	var s := Node3D.new()
	s.set_script(load("res://scripts/sewer.gd"))
	s.name = "Sewer"
	s.set("built", level_built)
	parent.add_child(s)
	s.call("_lay_out", seed_value)
	s.call("_build_all", seed_value)
	return s


func _build_all(seed_value: int) -> void:
	_rng.seed = seed_value ^ 0x6d6f7373
	_stone = _stone_material()
	_iron = _iron_material()
	_build_csg()
	_build_ladders()
	_build_grilles()
	_build_plates()
	_build_props()
	_build_water()
	_build_moss()
	_build_fireflies()
	_build_feral_floor()


# --- Layout ------------------------------------------------------------------------

func _lay_out(seed_value: int) -> void:
	map = SewerMap.new()
	map.size = built.size
	map.cell_size = built.cell_size
	map.origin = built.origin
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x73657772
	var nodes: Array[Vector2i] = []
	for pos in built.manholes:
		nodes.append(pos)
	nodes.sort()
	for pos in nodes:
		_cell(pos)
	# Minimum spanning tree (Prim, Manhattan), then the shortest link not in it.
	var in_tree := {nodes[0]: true}
	var links: Array = []
	while in_tree.size() < nodes.size():
		var best := []
		var best_d := INF
		for a in in_tree:
			for b in nodes:
				if in_tree.has(b):
					continue
				var d := float(absi(a.x - b.x) + absi(a.y - b.y))
				if d < best_d:
					best_d = d
					best = [a, b]
		in_tree[best[1]] = true
		links.append(best)
	var extra := []
	var extra_d := INF
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var a := nodes[i]
			var b := nodes[j]
			var linked := false
			for l in links:
				if (l[0] == a and l[1] == b) or (l[0] == b and l[1] == a):
					linked = true
			if linked:
				continue
			var d := float(absi(a.x - b.x) + absi(a.y - b.y))
			if d < extra_d:
				extra_d = d
				extra = [a, b]
	if not extra.is_empty():
		links.append(extra)
	for l in links:
		_route(l[0], l[1], rng.randf() < 0.5)
	# Spurs: short dead ends off straight runs, into ground no pipe uses.
	var straights: Array[Vector2i] = []
	for key in map.cells:
		var c: ModuleMaze.Cell = map.cells[key]
		if c.open == (ModuleMaze.N | ModuleMaze.S) or c.open == (ModuleMaze.E | ModuleMaze.W):
			if not built.manholes.has(key):
				straights.append(key)
	straights.sort()
	var made := 0
	var tries := 0
	while made < SPURS and tries < 60 and not straights.is_empty():
		tries += 1
		var from: Vector2i = straights[rng.randi_range(0, straights.size() - 1)]
		var c: ModuleMaze.Cell = map.cells[from]
		var sides := [ModuleMaze.E, ModuleMaze.W] if c.open & ModuleMaze.N else [ModuleMaze.N, ModuleMaze.S]
		var side: int = sides[rng.randi_range(0, 1)]
		var step: Vector2i = ModuleMaze.DIRS[side]
		var length := rng.randi_range(2, 4)
		var ok := true
		for k in range(1, length + 2):
			var p := from + step * k
			if map.cells.has(p) or p.x < 1 or p.y < 1 or p.x >= map.size.x - 1 or p.y >= map.size.y - 1:
				ok = false
				break
		if not ok:
			continue
		var prev := from
		for k in range(1, length + 1):
			var p := from + step * k
			_cell(p)
			_join(prev, p)
			prev = p
		made += 1
	for key in map.cells:
		ModuleMaze._classify(map.cells[key])
	for pos in nodes:
		var mh: Dictionary = built.manholes[pos]
		var hole: Vector3 = mh["world"]
		var along: Vector3 = mh["along"]
		shafts.append({"cell": pos, "hole": hole, "along": along,
			"foot": Vector3(hole.x, FLOOR_Y, hole.z),
			"chamber": built.to_world(pos) + Vector3(0.0, FLOOR_Y, 0.0)})
		map.ladders.append(Vector3(hole.x, FLOOR_Y, hole.z))
	var total := 0
	for key in map.cells:
		total += 1
	print("[sewer] %d manholes, %d links, %d spurs, %d cells of pipe" % [nodes.size(), links.size(), made, total])


func _cell(p: Vector2i) -> ModuleMaze.Cell:
	if not map.cells.has(p):
		var c := ModuleMaze.Cell.new()
		c.pos = p
		map.cells[p] = c
	return map.cells[p]


func _join(a: Vector2i, b: Vector2i) -> void:
	var d := b - a
	for side in ModuleMaze.ORDER:
		if ModuleMaze.DIRS[side] == d:
			_cell(a).open |= side
		if ModuleMaze.DIRS[side] == -d:
			_cell(b).open |= side


## An L of pipe from `a` to `b`: along x first, or z first.
func _route(a: Vector2i, b: Vector2i, x_first: bool) -> void:
	var corner := Vector2i(b.x, a.y) if x_first else Vector2i(a.x, b.y)
	for leg in [[a, corner], [corner, b]]:
		var p: Vector2i = leg[0]
		var to: Vector2i = leg[1]
		while p != to:
			var step := Vector2i(signi(to.x - p.x), signi(to.y - p.y))
			_cell(p)
			_cell(p + step)
			_join(p, p + step)
			p += step


## Straight runs: [from cell, to cell] along x or z, maximal.
func _runs() -> Array:
	var out: Array = []
	for key in map.cells:
		var c: ModuleMaze.Cell = map.cells[key]
		for pair in [[ModuleMaze.E, ModuleMaze.W], [ModuleMaze.S, ModuleMaze.N]]:
			var fwd: int = pair[0]
			var back: int = pair[1]
			# Start a run only at its first cell.
			if not (c.open & fwd) or (c.open & back):
				continue
			var step: Vector2i = ModuleMaze.DIRS[fwd]
			var end: Vector2i = key
			while (map.cells[end] as ModuleMaze.Cell).open & fwd:
				end += step
			out.append([key, end])
	return out


# --- Geometry ----------------------------------------------------------------------

## True for the cells built as a chamber.
func _is_chamber(key: Vector2i) -> bool:
	var c: ModuleMaze.Cell = map.cells[key]
	if built.manholes.has(key):
		return true
	return not (c.open == (ModuleMaze.N | ModuleMaze.S) or c.open == (ModuleMaze.E | ModuleMaze.W))


func _side_dir(side: int) -> Vector3:
	var d: Vector2i = ModuleMaze.DIRS[side]
	return Vector3(float(d.x), 0.0, float(d.y))


## How far a chamber's culvert on `side` runs past its wall: short where another
## pipe runs behind it, barely a niche where another chamber does.
func _culvert_deep(key: Vector2i, side: int) -> float:
	var nb: Vector2i = key + ModuleMaze.DIRS[side]
	if not map.cells.has(nb):
		return CULVERT_DEEP
	return 0.12 if _is_chamber(nb) else CULVERT_SHORT


## A pipe's outline across (x) and up (y): walls at +-half up to `spring`, a round
## vault over, down to `bottom`.
func _pipe_outline(half: float, spring: float, bottom: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	poly.append(Vector2(-half, bottom))
	for i in ARC_STEPS + 1:
		var a := PI - PI * float(i) / float(ARC_STEPS)
		poly.append(Vector2(cos(a) * half, spring + sin(a) * half))
	poly.append(Vector2(half, bottom))
	return poly


## The channel: straight sides, then a round invert.
func _channel_outline() -> PackedVector2Array:
	var r := CHANNEL_HALF
	var poly := PackedVector2Array()
	poly.append(Vector2(-r, 0.4))
	for i in ARC_STEPS + 1:
		var a := PI + PI * float(i) / float(ARC_STEPS)
		poly.append(Vector2(cos(a) * r, -CHANNEL_SIDE + sin(a) * r))
	poly.append(Vector2(r, 0.4))
	return poly


## The height of a culvert's inside above the walkway, `x` across it.
func _culvert_top(x: float) -> float:
	var half := PIPE_HALF * CULVERT_SCALE
	return PIPE_SPRING * CULVERT_SCALE + sqrt(maxf(half * half - x * x, 0.0))


func _extrude(parent: Node, poly: PackedVector2Array, from: Vector3, dir: Vector3, depth: float) -> void:
	var cut := CSGPolygon3D.new()
	cut.polygon = poly
	cut.mode = CSGPolygon3D.MODE_DEPTH
	cut.depth = depth
	cut.smooth_faces = true
	cut.material = _stone
	cut.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), from)
	parent.add_child(cut)


func _build_csg() -> void:
	_csg = CSGCombiner3D.new()
	_csg.name = "SewerCSG"
	add_child(_csg)
	var outer := CSGCombiner3D.new()
	_csg.add_child(outer)
	var hollow := CSGCombiner3D.new()
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	_csg.add_child(hollow)
	var inner := CSGCombiner3D.new()
	hollow.add_child(inner)
	# The insides end flat at the walkway; only the channels go below it.
	var w: float = float(map.size.x + 4) * map.cell_size
	var d: float = float(map.size.y + 4) * map.cell_size
	var above := CSGBox3D.new()
	above.size = Vector3(w, 60.0, d)
	above.position = Vector3(map.origin.x + w * 0.5 - 2.0 * map.cell_size, FLOOR_Y + 30.0,
		map.origin.z + d * 0.5 - 2.0 * map.cell_size)
	above.operation = CSGShape3D.OPERATION_INTERSECTION
	above.material = _stone
	hollow.add_child(above)
	var cuts := CSGCombiner3D.new()
	cuts.operation = CSGShape3D.OPERATION_SUBTRACTION
	_csg.add_child(cuts)

	# The pipes: one extrusion per straight run, chamber centre to chamber
	# centre, so a run is one unbroken piece of stone, channel and all.
	var air := _pipe_outline(PIPE_HALF, PIPE_SPRING, -0.6)
	var shell := _pipe_outline(PIPE_HALF + SHELL, PIPE_SPRING, BASE)
	var chan := _channel_outline()
	for run in _runs():
		var a: Vector3 = map.to_world(run[0])
		var b: Vector3 = map.to_world(run[1])
		var dir := (b - a).normalized()
		var length := a.distance_to(b)
		_extrude(outer, shell, a, dir, length)
		_extrude(inner, air, a, dir, length)
		_extrude(cuts, chan, a, dir, length)

	var c_air := _pipe_outline(PIPE_HALF * CULVERT_SCALE, PIPE_SPRING * CULVERT_SCALE, -0.6)
	var c_shell := _pipe_outline(PIPE_HALF * CULVERT_SCALE + 0.6, PIPE_SPRING * CULVERT_SCALE, BASE)
	var count := 0
	for key in map.cells:
		if not _is_chamber(key):
			continue
		count += 1
		var c: ModuleMaze.Cell = map.cells[key]
		var at: Vector3 = map.to_world(key)
		for layer in [[outer, CH_R + CH_SHELL, BASE, DOME_RISE + CH_SHELL],
				[inner, CH_R, -0.6, DOME_RISE]]:
			var r: float = layer[1]
			var cyl := CSGCylinder3D.new()
			cyl.radius = r
			cyl.height = CH_WALL - float(layer[2])
			cyl.sides = 48
			cyl.material = _stone
			cyl.position = Vector3(at.x, at.y + (float(layer[2]) + CH_WALL) * 0.5, at.z)
			(layer[0] as Node).add_child(cyl)
			var dome := CSGSphere3D.new()
			dome.radius = r
			dome.radial_segments = 48
			dome.rings = 24
			dome.material = _stone
			dome.position = Vector3(at.x, at.y + CH_WALL, at.z)
			dome.scale = Vector3(1.0, float(layer[3]) / r, 1.0)
			(layer[0] as Node).add_child(dome)
		# Every closed side is a culvert, its channel running on into it.
		for side in ModuleMaze.ORDER:
			if c.open & side:
				continue
			var dir := _side_dir(side)
			var deep := _culvert_deep(key, side)
			var start := CH_R - 0.6
			_extrude(outer, c_shell, at + dir * start, dir, CH_R + deep - start + 0.5)
			_extrude(inner, c_air, at + dir * start, dir, CH_R + deep - start)
			_extrude(cuts, chan, at, dir, CH_R + deep)
	for s in shafts:
		var hole: Vector3 = s["hole"]
		var top := -0.15
		var bottom := FLOOR_Y + CH_WALL
		var tube := CSGCylinder3D.new()
		tube.radius = SHAFT_OUTER
		tube.height = top - bottom
		tube.sides = 20
		tube.material = _stone
		tube.position = Vector3(hole.x, (top + bottom) * 0.5, hole.z)
		outer.add_child(tube)
		var bore := CSGCylinder3D.new()
		bore.radius = SHAFT_R
		bore.height = 2.0 - (bottom - 0.5)
		bore.sides = 20
		bore.material = _stone
		bore.position = Vector3(hole.x, (2.0 + bottom - 0.5) * 0.5, hole.z)
		inner.add_child(bore)
	_csg.visible = false
	_csg.use_collision = false
	print("[sewer] %d chambers" % count)


## CSG will not bake until a frame has passed since it was built.
func _ready() -> void:
	await get_tree().process_frame
	if is_inside_tree():
		_bake()


func _bake() -> void:
	var mesh := _csg.bake_static_mesh() as ArrayMesh
	var shape := _csg.bake_collision_shape()
	_csg.queue_free()
	_csg = null
	if mesh == null:
		push_error("sewer: the CSG did not bake")
		return
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_collision_body().add_child(cs)
	# Split by triangle centre into chunks.
	var tools := {}
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tri_count := idx.size() if idx.size() > 0 else verts.size()
		for t in range(0, tri_count, 3):
			var i0 := idx[t] if idx.size() > 0 else t
			var i1 := idx[t + 1] if idx.size() > 0 else t + 1
			var i2 := idx[t + 2] if idx.size() > 0 else t + 2
			var c := (verts[i0] + verts[i1] + verts[i2]) / 3.0
			var key := Vector2i(floori(c.x / CHUNK), floori(c.z / CHUNK))
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(_stone)
				tools[key] = st
			var st: SurfaceTool = tools[key]
			for i in [i0, i1, i2]:
				st.set_normal(normals[i])
				st.add_vertex(verts[i])
			tris += 1
	for ck: Vector2i in tools:
		var mi := MeshInstance3D.new()
		mi.name = "Stone_%d_%d" % [ck.x, ck.y]
		mi.mesh = (tools[ck] as SurfaceTool).commit()
		mi.layers = VISUAL_LAYER
		# Nothing down here casts: no light in the sewer has shadows.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks.append(mi)
	_set_below(_below, true)
	_build_nav()
	print("[sewer] stone baked: %d triangles in %d chunks" % [tris, tools.size()])


var _body: StaticBody3D


func _collision_body() -> StaticBody3D:
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "SewerCollision"
		_body.collision_layer = 1 | 2 | 256
		_body.collision_mask = 0
		add_child(_body)
	return _body


# --- Materials ----------------------------------------------------------------------

static var _noise_tex: NoiseTexture2D


static func _noise() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.008
		n.fractal_octaves = 4
		n.seed = 731
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 512
		_noise_tex.height = 512
		_noise_tex.seamless = true
		_noise_tex.generate_mipmaps = true
		_noise_tex.noise = n
	return _noise_tex


func _stone_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sewer_stone.gdshader")
	m.set_shader_parameter("brick_albedo", load("res://textures/sewer_hf_albedo.png"))
	m.set_shader_parameter("brick_normal", load("res://textures/sewer_hf_normal.png"))
	m.set_shader_parameter("mold_tex", load("res://textures/sewer_mold.png"))
	m.set_shader_parameter("sludge_tex", load("res://textures/sewer_sludge.png"))
	m.set_shader_parameter("sludge_normal", load("res://textures/sewer_sludge_normal.png"))
	m.set_shader_parameter("noise_tex", _noise())
	m.set_shader_parameter("floor_y", FLOOR_Y)
	return m


func _iron_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.085, 0.06, 0.045)
	m.metallic = 0.55
	m.roughness = 0.72
	return m


# --- Iron: grilles, ladders, the gratings at the ladders' feet ----------------------

## A culvert's grille, made to its arch: bars on BAR_EVERY reaching into the
## stone above and below (down into the channel in the middle), two flat bands
## across, one round the arch, and a padlock.
func _build_grilles() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := PIPE_HALF * CULVERT_SCALE
	var n := 0
	for key in map.cells:
		if not _is_chamber(key):
			continue
		var c: ModuleMaze.Cell = map.cells[key]
		var at: Vector3 = map.to_world(key)
		for side in ModuleMaze.ORDER:
			if c.open & side:
				continue
			n += 1
			var dir := _side_dir(side)
			var across := Vector3(-dir.z, 0.0, dir.x)
			var deep := _culvert_deep(key, side)
			var origin := at + dir * (CH_R + minf(GRILLE_IN, deep * 0.5))
			var b := Basis(across, Vector3.UP, -dir)
			var x := -half + 0.06
			while x < half - 0.05:
				var bottom := -0.95 if absf(x) < CHANNEL_HALF - 0.03 else -0.05
				var top := _culvert_top(x) + 0.06
				var bar := CylinderMesh.new()
				bar.top_radius = 0.017
				bar.bottom_radius = 0.017
				bar.height = top - bottom
				bar.radial_segments = 6
				bar.rings = 1
				st.append_from(bar, 0, Transform3D(b, origin + b * Vector3(x, (top + bottom) * 0.5, 0.0)))
				x += BAR_EVERY
			for y: float in [0.42, 1.18]:
				var wide := half if y <= PIPE_SPRING * CULVERT_SCALE else sqrt(maxf(half * half - pow(y - PIPE_SPRING * CULVERT_SCALE, 2.0), 0.0))
				var band := BoxMesh.new()
				band.size = Vector3(wide * 2.0 + 0.08, 0.055, 0.03)
				st.append_from(band, 0, Transform3D(b, origin + b * Vector3(0.0, y, 0.022)))
			var r := half - 0.04
			for i in 12:
				var a0 := PI * float(i) / 12.0
				var a1 := PI * float(i + 1) / 12.0
				var p0 := Vector3(cos(a0) * r, PIPE_SPRING * CULVERT_SCALE + sin(a0) * r, 0.022)
				var p1 := Vector3(cos(a1) * r, PIPE_SPRING * CULVERT_SCALE + sin(a1) * r, 0.022)
				var seg := BoxMesh.new()
				seg.size = Vector3(p0.distance_to(p1) + 0.01, 0.05, 0.03)
				var t := (p1 - p0).normalized()
				var sb := Basis(t, Vector3(0, 0, 1).cross(t), Vector3(0, 0, 1))
				st.append_from(seg, 0, Transform3D(b * sb, origin + b * ((p0 + p1) * 0.5)))
			var lock := BoxMesh.new()
			lock.size = Vector3(0.09, 0.12, 0.05)
			st.append_from(lock, 0, Transform3D(b, origin + b * Vector3(0.18, 0.95, 0.06)))
			var shape := BoxShape3D.new()
			shape.size = Vector3(half * 2.0, _culvert_top(0.0) + 0.2, 0.12)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = Transform3D(b, origin + Vector3(0.0, shape.size.y * 0.5 - 0.1, 0.0))
			_collision_body().add_child(cs)
	st.generate_normals()
	_add_iron(st.commit(), "Grilles")
	print("[sewer] %d culverts barred" % n)


## Where a ladder comes down, a grating over the channel: the foot of every ladder
## is on a channel's line (the shaft is on the corridor's axis above, and every
## chamber has a channel arm on each side).
func _build_plates() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in shafts:
		var at: Vector3 = s["chamber"]
		var off: Vector3 = (s["foot"] as Vector3) - at
		var dir := Vector3(signf(off.x), 0.0, 0.0) if absf(off.x) > absf(off.z) else Vector3(0.0, 0.0, signf(off.z))
		var reach := off.dot(dir)
		var from := maxf(0.35, reach - 1.25)
		var to := minf(CH_R - 0.2, reach + 0.9)
		var mid := at + dir * ((from + to) * 0.5)
		var length := to - from
		var b := Basis(Vector3(-dir.z, 0.0, dir.x), Vector3.UP, -dir)
		var wide := CHANNEL_HALF * 2.0 + 0.3
		for side: float in [-1.0, 1.0]:
			var rail := BoxMesh.new()
			rail.size = Vector3(0.07, 0.06, length)
			st.append_from(rail, 0, Transform3D(b, mid + b * Vector3(side * (CHANNEL_HALF + 0.08), -0.03, 0.0)))
		var z := -length * 0.5 + 0.05
		while z < length * 0.5 - 0.02:
			var slat := BoxMesh.new()
			slat.size = Vector3(wide, 0.045, 0.028)
			st.append_from(slat, 0, Transform3D(b, mid + b * Vector3(0.0, -0.025, z)))
			z += 0.085
		var shape := BoxShape3D.new()
		shape.size = Vector3(wide, 0.06, length)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(b, mid + Vector3(0.0, -0.03, 0.0))
		_collision_body().add_child(cs)
	st.generate_normals()
	_add_iron(st.commit(), "Gratings")


func _add_iron(mesh: Mesh, name_: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.material_override = _iron
	mi.layers = VISUAL_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_chunks.append(mi)


func _build_ladders() -> void:
	for s in shafts:
		var hole: Vector3 = s["hole"]
		var along: Vector3 = s["along"]
		var across := along.cross(Vector3.UP).normalized()
		var height := 0.0 - FLOOR_Y
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var base := Vector3(hole.x, FLOOR_Y, hole.z) + along * LADDER_OUT
		for side: float in [-0.24, 0.24]:
			var rail := BoxMesh.new()
			rail.size = Vector3(0.05, height, 0.05)
			var b := Basis.looking_at(along, Vector3.UP)
			st.append_from(rail, 0, Transform3D(b, base + across * side + Vector3(0.0, height * 0.5, 0.0)))
		var y := RUNG_EVERY
		while y < height - 0.1:
			var rung := CylinderMesh.new()
			rung.top_radius = 0.018
			rung.bottom_radius = 0.018
			rung.height = 0.48
			rung.radial_segments = 6
			rung.rings = 1
			st.append_from(rung, 0, Transform3D(Basis(along, across, -Vector3.UP),
				base + Vector3(0.0, y, 0.0)))
			y += RUNG_EVERY
		st.generate_normals()
		# Under a plain node: Interact.looked_at measures the meshes UNDER what
		# it is given, not the node itself.
		var holder := Node3D.new()
		holder.name = "Ladder"
		add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _iron
		holder.add_child(mi)
		s["ladder"] = holder


# --- The dead -----------------------------------------------------------------------

static var _bones_mesh: Mesh


static func _bones() -> Mesh:
	if _bones_mesh == null:
		if not ResourceLoader.exists(KIT):
			push_error("sewer: the kit is missing -- run tools/build_sewer_kit.py")
			return null
		var scene: Node = (load(KIT) as PackedScene).instantiate()
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var mesh := mi.mesh.duplicate() as Mesh
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s) as StandardMaterial3D
				if m == null:
					continue
				m = m.duplicate() as StandardMaterial3D
				# Tripo marks everything metal through its packed map; bone is not.
				m.metallic = 0.0
				m.metallic_texture = null
				m.roughness_texture = null
				m.roughness = 0.8
				m.albedo_color = Color(0.36, 0.34, 0.3)
				mesh.surface_set_material(s, m)
			_bones_mesh = mesh
		scene.free()
	return _bones_mesh


## Heaps of the dead on the walkways, and in the chambers' corners (the diagonals:
## the channels run on the axes).
func _build_props() -> void:
	var holder := Node3D.new()
	holder.name = "Bones"
	add_child(holder)
	_chunks.append(holder)
	var mesh := _bones()
	if mesh == null:
		return
	var keys: Array = map.cells.keys()
	keys.sort()
	var n := 0
	for key: Vector2i in keys:
		var at: Vector3 = map.to_world(key)
		var p := Vector3.INF
		if _is_chamber(key):
			if _rng.randf() < 0.5:
				for tries in 4:
					var ang := PI * 0.25 + PI * 0.5 * float(_rng.randi_range(0, 3))
					var q := at + Vector3(cos(ang), 0.0, sin(ang)) * 2.0
					var clear := true
					for s in shafts:
						var hole: Vector3 = s["hole"]
						if Vector2(q.x - hole.x, q.z - hole.z).length() < 1.4:
							clear = false
					if clear:
						p = q
						break
		elif _rng.randf() < BONES_SHARE:
			var c: ModuleMaze.Cell = map.cells[key]
			var along := Vector3(0, 0, 1) if c.open & ModuleMaze.N else Vector3(1, 0, 0)
			var across := Vector3(along.z, 0.0, along.x)
			p = at + across * (1.32 if _rng.randf() < 0.5 else -1.32) + along * _rng.randf_range(-2.2, 2.2)
		if p == Vector3.INF:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.55, 0.75)), p)
		mi.layers = VISUAL_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = PIECE_RANGE
		holder.add_child(mi)
		n += 1
	print("[sewer] %d bone heaps" % n)


# --- Water --------------------------------------------------------------------------

## One plane per cell at the water's level, under the walkways: the stone hides it
## everywhere but the channels, and the shader maps it in world space, so the
## watercourse is one surface from end to end. Deep culverts reach past their
## cell and get a strip of their own.
func _build_water() -> void:
	add_to_group(&"water")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sewer_water.gdshader")
	m.set_shader_parameter("sludge_tex", load("res://textures/sewer_sludge.png"))
	m.set_shader_parameter("sludge_normal", load("res://textures/sewer_sludge_normal.png"))
	m.set_shader_parameter("noise_tex", _noise())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = map.cell_size * 0.5
	for key in map.cells:
		var at: Vector3 = map.to_world(key) + Vector3(0.0, WATER_Y, 0.0)
		_quad(st, at, Vector3(half, 0, 0), Vector3(0, 0, half))
		if not _is_chamber(key):
			continue
		var c: ModuleMaze.Cell = map.cells[key]
		for side in ModuleMaze.ORDER:
			if c.open & side or map.cells.has(key + ModuleMaze.DIRS[side]):
				continue
			var dir := _side_dir(side)
			var across := Vector3(-dir.z, 0.0, dir.x)
			var reach := CH_R + _culvert_deep(key, side) - half
			_quad(st, at + dir * (half + reach * 0.5), across * (CHANNEL_HALF + 0.05), dir * (reach * 0.5))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.layers = VISUAL_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_chunks.append(mi)


## An upward-facing quad, centre `c`, half-extents `u` and `v`.
func _quad(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3) -> void:
	var a := c - u - v
	var b := c + u - v
	var d := c + u + v
	var e := c - u + v
	var up := (u.cross(v)).normalized()
	# Wind it so it faces up.
	if up.y < 0.0:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(d)
		st.add_vertex(a); st.add_vertex(d); st.add_vertex(e)
	else:
		st.add_vertex(a); st.add_vertex(d); st.add_vertex(b)
		st.add_vertex(a); st.add_vertex(e); st.add_vertex(d)


## player.gd `water_depth` asks every "water" node: the surface over `point`, or
## -INF where there is none. Water is wherever a channel is: along every pipe,
## across every chamber, and into its culverts (which reach into the next cell,
## so the neighbours are asked too).
func water_surface_at(point: Vector3) -> float:
	if point.y > SPLIT_Y or map == null:
		return -INF
	var rel := point - map.origin
	var key := Vector2i(roundi(rel.x / map.cell_size), roundi(rel.z / map.cell_size))
	for k: Vector2i in [key, key + Vector2i(1, 0), key - Vector2i(1, 0), key + Vector2i(0, 1), key - Vector2i(0, 1)]:
		if not map.cells.has(k):
			continue
		var c: ModuleMaze.Cell = map.cells[k]
		var off := point - map.to_world(k)
		var chamber := _is_chamber(k)
		for side in ModuleMaze.ORDER:
			var reach: float
			if c.open & side:
				reach = map.cell_size * 0.5 + 0.01
			elif chamber:
				reach = CH_R + _culvert_deep(k, side)
			else:
				continue
			var d := _side_dir(side)
			var along := off.x * d.x + off.z * d.z
			var across := absf(off.x * d.z - off.z * d.x)
			if along >= -CHANNEL_HALF and along <= reach and across <= CHANNEL_HALF:
				return FLOOR_Y + WATER_Y
	return -INF


# --- Light: moss and fireflies ------------------------------------------------------

## Bioluminescent moss: clusters of the Higgsfield moss as emissive decals in the
## crack where a wall meets the walkway (each decal cast at 45 deg into the
## corner, so it paints both), and patches up the walls. Square decals turned at
## random about their own axis, overlapping, so no cluster repeats another. A
## share of the clusters carry a faint omni, the only light down here.
func _build_moss() -> void:
	var holder := Node3D.new()
	holder.name = "Moss"
	add_child(holder)
	_chunks.append(holder)
	var tex: Texture2D = load("res://textures/sewer_moss.png")
	var keys: Array = map.cells.keys()
	keys.sort()
	var decals := 0
	var lights := 0
	for key: Vector2i in keys:
		var at: Vector3 = map.to_world(key)
		var c: ModuleMaze.Cell = map.cells[key]
		if _is_chamber(key):
			for i in _rng.randi_range(2, 3):
				var ang := _rng.randf() * TAU
				var out := Vector3(cos(ang), 0.0, sin(ang))
				# Not across a pipe's mouth or a culvert's.
				var gap := false
				for side in ModuleMaze.ORDER:
					if out.dot(_side_dir(side)) > 0.88:
						gap = true
				if gap:
					continue
				var r := _moss_crack(holder, tex, at + out * CH_R, out, Vector3(-out.z, 0.0, out.x))
				decals += r[0]
				lights += r[1]
			# Moss deep in every culvert, glowing behind its grille: the bars read
			# as black iron against it (the way the dungeon's windows are lit).
			for side in ModuleMaze.ORDER:
				if c.open & side:
					continue
				var deep := _culvert_deep(key, side)
				if deep < 0.3:
					continue
				var dir := _side_dir(side)
				var inside := at + dir * (CH_R + deep * 0.75)
				var across := Vector3(-dir.z, 0.0, dir.x)
				for s: float in [-1.0, 1.0]:
					_moss_decal(holder, tex, inside + across * s * PIPE_HALF * CULVERT_SCALE,
						(across * s - Vector3.UP).normalized(), dir, _rng.randf_range(0.35, 0.55), 0.7)
					decals += 1
				var l := _moss_light(inside + Vector3(0.0, 0.5, 0.0), 1.0)
				l.omni_range = 2.6
				holder.add_child(l)
				lights += 1
			if _rng.randf() < 0.6:
				var ang := _rng.randf() * TAU
				var out := Vector3(cos(ang), 0.0, sin(ang))
				decals += _moss_patch(holder, tex, at + out * CH_R + Vector3(0, _rng.randf_range(0.8, 3.0), 0), out)
			continue
		var along := Vector3(0, 0, 1) if c.open & ModuleMaze.N else Vector3(1, 0, 0)
		var across := Vector3(along.z, 0.0, along.x)
		for side: float in [-1.0, 1.0]:
			if _rng.randf() < 0.55:
				var r := _moss_crack(holder, tex, at + across * side * PIPE_HALF + along * _rng.randf_range(-2.4, 2.4),
					across * side, along)
				decals += r[0]
				lights += r[1]
			if _rng.randf() < 0.22:
				decals += _moss_patch(holder, tex, at + across * side * PIPE_HALF + along * _rng.randf_range(-2.6, 2.6)
					+ Vector3(0, _rng.randf_range(0.5, 1.7), 0), across * side)
	print("[sewer] moss: %d decals, %d lights" % [decals, lights])


## A run of moss in the crack at `corner` (on the walkway, at the wall's foot),
## the wall's outward normal `out` and the crack's direction `along`. Returns
## [decals, lights].
func _moss_crack(holder: Node3D, tex: Texture2D, corner: Vector3, out: Vector3, along: Vector3) -> Array:
	var length := _rng.randf_range(0.7, 2.2)
	var n := maxi(2, int(length / 0.55))
	var proj := (out - Vector3.UP).normalized()
	for i in n:
		var t := (float(i) / float(maxi(n - 1, 1)) - 0.5) * length + _rng.randf_range(-0.12, 0.12)
		var size := _rng.randf_range(0.4, 0.75)
		_moss_decal(holder, tex, corner + along * t, proj, along, size, 0.8)
	var lit := 0
	if _rng.randf() < MOSS_LIT_SHARE:
		lit = 1
		holder.add_child(_moss_light(corner - out * 0.35 + Vector3(0.0, 0.22, 0.0), _rng.randf_range(0.7, 1.2)))
	return [n, lit]


## A faint omni the colour of the moss: no shadows, on this layer only.
func _moss_light(at: Vector3, strength: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = MOSS_LIGHT
	l.light_energy = MOSS_LIGHT_ENERGY * strength
	l.omni_range = MOSS_LIGHT_RANGE
	l.omni_attenuation = 1.2
	l.light_specular = 0.6
	l.shadow_enabled = false
	l.light_cull_mask = VISUAL_LAYER | 1
	l.distance_fade_enabled = true
	l.distance_fade_begin = 30.0
	l.distance_fade_length = 8.0
	l.position = at
	return l


## A patch of moss on a wall at `at`, its outward normal `out`.
func _moss_patch(holder: Node3D, tex: Texture2D, at: Vector3, out: Vector3) -> int:
	var along := Vector3(-out.z, 0.0, out.x)
	var k := _rng.randi_range(1, 3)
	for i in k:
		var p := at + along * _rng.randf_range(-0.35, 0.35) + Vector3(0, _rng.randf_range(-0.3, 0.3), 0)
		_moss_decal(holder, tex, p, out, along, _rng.randf_range(0.3, 0.6), 0.6)
	return k


func _moss_decal(holder: Node3D, tex: Texture2D, at: Vector3, proj: Vector3, along: Vector3,
		size: float, depth: float) -> void:
	var y := -proj
	var x := along - y * along.dot(y)
	x = x.normalized().rotated(y, _rng.randf() * TAU)
	var z := x.cross(y)
	var d := Decal.new()
	d.size = Vector3(size, depth, size)
	d.transform = Transform3D(Basis(x, y, z), at)
	d.texture_albedo = tex
	d.texture_emission = tex
	d.emission_energy = _rng.randf_range(0.5, 1.1)
	d.albedo_mix = 0.7
	d.modulate = Color(1.0, 1.0, 1.0, _rng.randf_range(0.75, 1.0))
	d.upper_fade = 0.25
	d.lower_fade = 0.35
	d.normal_fade = 0.0
	d.cull_mask = VISUAL_LAYER
	d.distance_fade_enabled = true
	d.distance_fade_begin = PIECE_RANGE - 6.0
	d.distance_fade_length = 6.0
	holder.add_child(d)


## Fireflies: a few tiny glowing bugs drifting in most cells, blinking out of
## step (shaders/sewer_firefly.gdshader). GPU particles wandering on turbulence;
## fewer without `Graphics.effects`.
func _build_fireflies() -> void:
	var holder := Node3D.new()
	holder.name = "Fireflies"
	add_child(holder)
	_chunks.append(holder)
	var gfx := get_node_or_null("/root/Graphics")
	var effects: bool = gfx == null or bool(gfx.get("effects"))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.22
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.02
	pm.damping_max = 0.06
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 2.6
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	pm.scale_min = 0.6
	pm.scale_max = 1.25
	var hue := Gradient.new()
	hue.set_color(0, Color(0.78, 1.0, 0.32))
	hue.set_color(1, Color(0.42, 1.0, 0.6))
	var hue_tex := GradientTexture1D.new()
	hue_tex.gradient = hue
	pm.color_initial_ramp = hue_tex
	# The blink, over each bug's life: out of step because their lives are.
	var blink := Gradient.new()
	blink.offsets = PackedFloat32Array([0.0, 0.07, 0.15, 0.27, 0.36, 0.5, 0.58, 0.72, 0.8, 0.9, 1.0])
	blink.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.12),
		Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.05), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.2),
		Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	var blink_tex := GradientTexture1D.new()
	blink_tex.gradient = blink
	pm.color_ramp = blink_tex
	var pm_room := pm.duplicate() as ParticleProcessMaterial
	pm_room.emission_box_extents = Vector3(1.8, 1.0, 1.8)
	# The pipes' box lies along the pipe (the node is turned to it), over the walkways.
	pm.emission_box_extents = Vector3(1.3, 0.9, 2.8)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var fm := ShaderMaterial.new()
	fm.shader = load("res://shaders/sewer_firefly.gdshader")
	quad.material = fm
	var keys: Array = map.cells.keys()
	keys.sort()
	var n := 0
	for key: Vector2i in keys:
		if _rng.randf() > 0.7:
			continue
		var at: Vector3 = map.to_world(key)
		var c: ModuleMaze.Cell = map.cells[key]
		var p := GPUParticles3D.new()
		p.amount = 5 if effects else 2
		p.lifetime = 9.0
		p.randomness = 0.5
		p.preprocess = 9.0
		p.process_material = pm
		p.draw_pass_1 = quad
		p.local_coords = false
		p.layers = VISUAL_LAYER
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
		p.visibility_range_end = PIECE_RANGE
		p.position = at + Vector3(0.0, 1.7, 0.0)
		if _is_chamber(key):
			p.process_material = pm_room
		elif not (c.open & ModuleMaze.N):
			p.rotation.y = PI * 0.5
		holder.add_child(p)
		n += 1
	print("[sewer] fireflies in %d cells" % n)


# --- Running ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var cam := get_viewport().get_camera_3d()
	var y: float = cam.global_position.y if cam != null else _player.global_position.y
	_set_below(y < SPLIT_Y)


## The sewer draws only while the camera is down here, and the air goes thick and
## musty. (The dungeon stays drawn below: the shafts look up into it.)
func _set_below(below: bool, force := false) -> void:
	if below == _below and not force:
		return
	_below = below
	for c in _chunks:
		if is_instance_valid(c):
			c.visible = below
	_haze(below)
	# Lights spawned up there since the level was built (the boss, a chest's
	# room light) are kept off this layer too.
	if below and get_parent() != null and get_parent().has_method("_wall_off_sewer"):
		get_parent().call("_wall_off_sewer")


func _haze(on: bool) -> void:
	var world := get_viewport().find_world_3d() if is_inside_tree() else null
	var env: Environment = world.environment if world != null else null
	if env == null:
		return
	if on:
		if _fog_saved.is_empty():
			_fog_saved = {"colour": env.fog_light_color, "energy": env.fog_light_energy,
				"density": env.fog_density, "ambient": env.ambient_light_color,
				"ambient_energy": env.ambient_light_energy}
		env.fog_light_color = HAZE_COLOUR
		env.fog_light_energy = HAZE_ENERGY
		env.fog_density = HAZE_DENSITY
		env.ambient_light_color = DAMP_AMBIENT
		env.ambient_light_energy = float(_fog_saved["ambient_energy"]) * DAMP_AMBIENT_SCALE
	elif not _fog_saved.is_empty():
		env.fog_light_color = _fog_saved["colour"]
		env.fog_light_energy = _fog_saved["energy"]
		env.fog_density = _fog_saved["density"]
		env.ambient_light_color = _fog_saved["ambient"]
		env.ambient_light_energy = _fog_saved["ambient_energy"]
		_fog_saved = {}


func _exit_tree() -> void:
	_haze(false)


func is_below() -> bool:
	return _below


## The shaft whose ladder foot is nearest `at`.
func nearest_shaft(at: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in shafts:
		var d := (s["foot"] as Vector3).distance_to(at)
		if d < best_d:
			best_d = d
			best = s
	return best


# --- For the decrepit enforcer (decrepit.gd) ----------------------------------------
##
## A floor of its own over every channel, at the walkways' height, on a layer
## nothing else collides with: it bounds over the water, straddling it, where
## the player has to wade. And the sewer's navmesh, baked from that floor and
## the stone (the channels' sides would otherwise cut every pipe and chamber in
## two), as its own region on the world's map.

const FERAL_FLOOR := 1 << 13
const NAV_GROUP := &"sewer_nav"


func _build_feral_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "FeralFloor"
	body.collision_layer = FERAL_FLOOR
	body.collision_mask = 0
	body.add_to_group(NAV_GROUP)
	add_child(body)
	var n := 0
	for key in map.cells:
		var c: ModuleMaze.Cell = map.cells[key]
		var at: Vector3 = map.to_world(key)
		var chamber := _is_chamber(key)
		for side in ModuleMaze.ORDER:
			var reach: float
			if c.open & side:
				reach = map.cell_size * 0.5
			elif chamber:
				# Up to the culvert's grille.
				reach = CH_R + minf(GRILLE_IN, _culvert_deep(key, side) * 0.5) - 0.12
			else:
				continue
			var dir := _side_dir(side)
			var length := reach + CHANNEL_HALF
			var box := BoxShape3D.new()
			box.size = Vector3(CHANNEL_HALF * 2.0 + 0.2, 0.4, length)
			var cs := CollisionShape3D.new()
			cs.shape = box
			cs.transform = Transform3D(Basis.looking_at(dir, Vector3.UP),
				at + dir * ((reach - CHANNEL_HALF) * 0.5) + Vector3(0.0, -0.2, 0.0))
			body.add_child(cs)
			n += 1
	print("[sewer] feral floor: %d spans" % n)


func _build_nav() -> void:
	if _body != null:
		_body.add_to_group(NAV_GROUP)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 256 | FERAL_FLOOR
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = NAV_GROUP
	var region := NavigationRegion3D.new()
	region.name = "SewerNav"
	region.navigation_mesh = nm
	add_child(region)
	region.bake_finished.connect(func() -> void:
		print("[sewer] navmesh baked: %d polygons" % nm.get_polygon_count()))
	region.bake_navigation_mesh(true)
