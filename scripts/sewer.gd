extends Node3D

## The sewer (2026-10-15): big round brick pipes under the dungeon, reached by
## ladders down the five manholes (manhole.gd).
##
## Layout, on the dungeon's own 6 m grid so the map can draw it the same way
## (`SewerMap`, handed to explore_map.gd as a second level): the manhole cells
## are its nodes, joined by a minimum spanning tree plus one extra link (a
## single loop) -- much simpler than the maze above -- each link an L of pipe
## along the grid, and a few short dead-end spurs. Chosen from the level seed.
##
## Remade with Higgsfield (2026-10-15): concept art and source images from
## gpt_image_2_5 seeded with the user's wall and vault photos, turned into
## models by Tripo H3.1 (tools/build_sewer_kit.py -> models/sewer/sewer_kit.glb).
## Straight cells are the kit's tunnel -- a sculpted brick vault with a walkway
## each side of a channel of black water -- one 6 m section per cell. Bends,
## junctions, dead ends and manholes are round domed brick CHAMBERS, built as
## one CSG tree baked a frame later (`_bake`: CSG needs a frame before it will
## bake) and split into CHUNK-sized pieces; their mouths are cut to the tunnel's
## measured inside, their closed sides are barred culverts behind the kit's
## rusted gate, and their brick is the Higgsfield texture
## (tools/build_sewer_texture.py), world triplanar. Bone heaps and pale fungus
## from the kit lie about. Collision: the chambers' baked shape plus one trimesh
## of the tunnel section shared by every cell. A shaft rises from each manhole's
## chamber to the dungeon floor, an iron ladder down it.
##
## Light: torches along the pipes (module_level `_hang_torch`, flagged `sewer`
## so torch.gd ranks them only while the camera is down here). Everything
## here draws on VISUAL_LAYER, which no dungeon light reaches (maze
## `_wall_off_sewer`), and its torches reach only this layer and layer 1 (the
## player, items): the floor above is not a shadow caster, so without the split
## the dungeon's torches and the moon lit the pipes through it. The sewer is
## hidden while the camera is above ground (`_process`).

const ModuleMaze := preload("res://scripts/module_maze.gd")
const ModuleLevel := preload("res://scripts/module_level.gd")

## The walkway's height. The dungeon's floor is 0; its collision slab ends at -1.2.
const FLOOR_Y := -12.0
## Below this the camera is in the sewer (torch.gd uses the same split).
const SPLIT_Y := -4.0
## The kit (tools/build_sewer_kit.py): Higgsfield images turned into Tripo
## models -- "tunnel" (one 6 m straight section, walkway at y 0, running along
## Z), "grate", "bones", "fungus".
const KIT := "res://models/sewer/sewer_kit.glb"
## The tunnel's inside, measured by the kit build with rays (tunnel_profile.json):
## [height above the walkway, half-width] from the channel's bottom to the crown.
## The chambers' mouths are cut to it, padded by MOUTH_PAD.
const TUNNEL_PROFILE := [[-0.87, 0.28], [-0.77, 0.55], [-0.07, 0.53], [0.03, 0.92],
	[0.13, 1.96], [1.03, 1.90], [2.03, 1.90], [2.23, 1.82], [2.43, 1.77], [2.63, 1.69],
	[2.83, 1.58], [3.03, 1.43], [3.23, 1.28], [3.43, 0.96], [3.63, 0.58], [3.70, 0.0]]
const MOUTH_PAD := 0.04
## The tunnel's channel, across the section (measured: -0.5 .. 0.7 m, 0.88 deep).
const CHANNEL_X0 := -0.48
const CHANNEL_X1 := 0.68
## Where its water stands, below the walkways.
const WATER_Y := -0.32
## A tunnel's walls at torch height (half-width 1.91 m at 1.2 m up).
const TUNNEL_WALL := 1.88
## The chambers: a round brick room at every bend, junction, dead end and
## manhole, inner radius CH_R (so the inner wall stands on the cell's edge),
## walls CH_WALL high under a dome rising DOME_RISE more.
const CH_R := 3.0
const CH_SHELL := 0.7
const CH_WALL := 3.9
const DOME_RISE := 1.7
## Mouths are cut from MOUTH_FROM to MOUTH_TO out from a chamber's centre.
const MOUTH_FROM := 2.3
const MOUTH_TO := 4.3
## A closed side gets a barred culvert: an alcove ALCOVE_W wide behind the
## kit's rusted gate.
const ALCOVE_W := 1.6
const ALCOVE_H := 2.45
const ALCOVE_DEEP := 0.55
const GRATE_W := 1.75
## The shaft up to the manhole.
const SHAFT_R := 0.56
const SHAFT_OUTER := 0.95
## Dead-end spurs off the main runs.
const SPURS := 3
## Render chunks.
const CHUNK := 24.0
const VISUAL_LAYER := 1 << 15
## Draw distance for the kit pieces (the chambers are chunked).
const PIECE_RANGE := 46.0
## Torches: one every TORCH_EVERY cells of tunnel, sides alternating.
const TORCH_EVERY := 2
## A torch every second section leaves the one between it 3-9 m from any
## flame: at the dungeon torches' 12 m reach that stretch was black. Wider and a
## little stronger pools, rather than more lights (each lit torch redraws the
## kit for its shadows: one per section cost ~1 ms more GPU).
const TORCH_REACH := 13.0
const TORCH_BOOST := 1.0
## Softer falloff than the dungeon's physical 1.0: in a long straight pipe the
## light has to carry to the next pool, or the stretch between is black.
const TORCH_FALLOFF := 0.55
const TORCH_UP := 1.3
## Props: share of tunnel cells with a fungus clump / a bone heap.
const FUNGUS_SHARE := 0.32
const BONES_SHARE := 0.2
## The ladder's rails stand this far from the shaft's centre, on the far side
## from the chamber's middle.
const LADDER_OUT := 0.36
const RUNG_EVERY := 0.3

var built
var map: SewerMap
## Per manhole cell: {cell, hole (world, at the dungeon floor), along, foot
## (world, the ladder's foot on the walkway), chamber (world centre)}.
var shafts: Array[Dictionary] = []
var _csg: CSGCombiner3D
var _chunks: Array[MeshInstance3D] = []
var _water: StandardMaterial3D
var _player: Node3D
var _below := false
var _torches: Node3D


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
	s.call("_build_csg")
	s.call("_build_kit")
	s.call("_build_ladders")
	s.call("_build_water")
	s.call("_build_torches")
	return s


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
##
## Straight cells are the kit's tunnel, one 6 m section per cell. Every other
## cell -- bend, junction, dead end, and every manhole -- is a CHAMBER: a round
## brick room with a dome, built here as CSG and baked (`_bake`), its mouths cut
## to the tunnel's measured profile so a section butts onto it from outside the
## wall; closed sides get a barred culvert. CSG handles chambers that sit next
## to each other: one tree, so each one's inside is cut through the other's wall.

## True for the cells built as a chamber.
func _is_chamber(key: Vector2i) -> bool:
	var c: ModuleMaze.Cell = map.cells[key]
	if built.manholes.has(key):
		return true
	return not (c.open == (ModuleMaze.N | ModuleMaze.S) or c.open == (ModuleMaze.E | ModuleMaze.W))


## A straight cell's basis: the tunnel's +Z (its length) along the corridor.
func _tunnel_basis(key: Vector2i) -> Basis:
	var c: ModuleMaze.Cell = map.cells[key]
	return Basis.IDENTITY if c.open & ModuleMaze.N else Basis(Vector3.UP, PI * 0.5)


func _side_dir(side: int) -> Vector3:
	var d: Vector2i = ModuleMaze.DIRS[side]
	return Vector3(float(d.x), 0.0, float(d.y))


## The tunnel's inside as a closed outline (x across, y up), padded.
func _mouth_polygon() -> PackedVector2Array:
	var right := PackedVector2Array()
	for i in TUNNEL_PROFILE.size():
		var row: Array = TUNNEL_PROFILE[i]
		var y := float(row[0]) - (MOUTH_PAD if i == 0 else 0.0)
		var x := float(row[1]) + (MOUTH_PAD if i < TUNNEL_PROFILE.size() - 1 else 0.0)
		right.append(Vector2(x, y))
	var poly := PackedVector2Array()
	for p in right:
		poly.append(p)
	for i in range(right.size() - 2, -1, -1):
		poly.append(Vector2(-right[i].x, right[i].y))
	return poly


func _build_csg() -> void:
	var wall := _brick_material()
	var floor_mat := _floor_material()
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
	# The insides end flat at the walkway.
	var w: float = float(map.size.x + 4) * map.cell_size
	var d: float = float(map.size.y + 4) * map.cell_size
	var above := CSGBox3D.new()
	above.size = Vector3(w, 60.0, d)
	above.position = Vector3(map.origin.x + w * 0.5 - 2.0 * map.cell_size, FLOOR_Y + 30.0,
		map.origin.z + d * 0.5 - 2.0 * map.cell_size)
	above.operation = CSGShape3D.OPERATION_INTERSECTION
	above.material = floor_mat
	hollow.add_child(above)
	var cuts := CSGCombiner3D.new()
	cuts.operation = CSGShape3D.OPERATION_SUBTRACTION
	_csg.add_child(cuts)
	var mouth := _mouth_polygon()
	var count := 0
	for key in map.cells:
		if not _is_chamber(key):
			continue
		count += 1
		var c: ModuleMaze.Cell = map.cells[key]
		var at: Vector3 = map.to_world(key)
		# Walls and dome: outside and inside.
		for layer in [[outer, CH_R + CH_SHELL, CH_WALL + 1.2, FLOOR_Y - 1.2, DOME_RISE + CH_SHELL],
				[inner, CH_R, CH_WALL + 1.0, FLOOR_Y - 1.0, DOME_RISE]]:
			var r: float = layer[1]
			var cyl := CSGCylinder3D.new()
			cyl.radius = r
			cyl.height = layer[2]
			cyl.sides = 40
			cyl.material = wall
			cyl.position = Vector3(at.x, float(layer[3]) + float(layer[2]) * 0.5, at.z)
			(layer[0] as Node).add_child(cyl)
			var dome := CSGSphere3D.new()
			dome.radius = r
			dome.radial_segments = 40
			dome.rings = 20
			dome.material = wall
			dome.position = Vector3(at.x, FLOOR_Y + CH_WALL, at.z)
			dome.scale = Vector3(1.0, float(layer[4]) / r, 1.0)
			(layer[0] as Node).add_child(dome)
		for side in ModuleMaze.ORDER:
			var dir := _side_dir(side)
			if c.open & side:
				# A mouth in the tunnel's own shape.
				var cut := CSGPolygon3D.new()
				cut.polygon = mouth
				cut.mode = CSGPolygon3D.MODE_DEPTH
				cut.depth = MOUTH_TO - MOUTH_FROM
				cut.material = wall
				cut.transform = Transform3D(Basis.looking_at(dir, Vector3.UP),
					at + dir * MOUTH_FROM)
				cuts.add_child(cut)
			else:
				# A barred culvert: an alcove behind where the gate will hang.
				var alcove := CSGBox3D.new()
				alcove.size = Vector3(ALCOVE_W, ALCOVE_H, ALCOVE_DEEP * 2.0)
				alcove.material = wall
				alcove.transform = Transform3D(Basis.looking_at(dir, Vector3.UP),
					at + dir * CH_R + Vector3(0.0, ALCOVE_H * 0.5, 0.0))
				cuts.add_child(alcove)
	for s in shafts:
		var hole: Vector3 = s["hole"]
		var top := -0.15
		var bottom := FLOOR_Y + CH_WALL
		var tube := CSGCylinder3D.new()
		tube.radius = SHAFT_OUTER
		tube.height = top - bottom
		tube.sides = 20
		tube.material = wall
		tube.position = Vector3(hole.x, (top + bottom) * 0.5, hole.z)
		outer.add_child(tube)
		var bore := CSGCylinder3D.new()
		bore.radius = SHAFT_R
		bore.height = 2.0 - (bottom - 0.5)
		bore.sides = 20
		bore.material = wall
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
	# Split by triangle centre into chunks, one surface per material.
	var tools := {}
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tri_count := idx.size() if idx.size() > 0 else verts.size()
		var mat := mesh.surface_get_material(s)
		for t in range(0, tri_count, 3):
			var i0 := idx[t] if idx.size() > 0 else t
			var i1 := idx[t + 1] if idx.size() > 0 else t + 1
			var i2 := idx[t + 2] if idx.size() > 0 else t + 2
			var c := (verts[i0] + verts[i1] + verts[i2]) / 3.0
			var key := Vector3i(floori(c.x / CHUNK), s, floori(c.z / CHUNK))
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(mat)
				tools[key] = st
			var st: SurfaceTool = tools[key]
			for i in [i0, i1, i2]:
				st.set_normal(normals[i])
				st.add_vertex(verts[i])
			tris += 1
	var by_chunk := {}
	for key: Vector3i in tools:
		var ck := Vector2i(key.x, key.z)
		if not by_chunk.has(ck):
			by_chunk[ck] = ArrayMesh.new()
		(tools[key] as SurfaceTool).commit(by_chunk[ck])
	for ck in by_chunk:
		var mi := MeshInstance3D.new()
		mi.name = "Chambers_%d_%d" % [ck.x, ck.y]
		mi.mesh = by_chunk[ck]
		mi.layers = VISUAL_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		_chunks.append(mi)
	_set_below(false, true)
	print("[sewer] chambers baked: %d triangles in %d chunks" % [tris, by_chunk.size()])


var _body: StaticBody3D


func _collision_body() -> StaticBody3D:
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = "SewerCollision"
		_body.collision_layer = 1 | 2 | 256
		_body.collision_mask = 0
		add_child(_body)
	return _body


## Brightness of each kit piece's own colour map, matched to the dungeon.
const KIT_TINT := {"tunnel": Color(0.85, 0.82, 0.78), "grate": Color(0.85, 0.8, 0.75),
	"bones": Color(0.7, 0.68, 0.64), "fungus": Color(0.75, 0.75, 0.72)}

## The kit's meshes by name, their materials made fit for this light: Tripo
## marks everything metallic through its packed map, which reads black away
## from a reflection, and stone and bone are not metal.
static var _kit := {}


static func kit_mesh(piece: String) -> Mesh:
	if _kit.is_empty():
		if not ResourceLoader.exists(KIT):
			push_error("sewer: the kit is missing -- run tools/build_sewer_kit.py")
			return null
		var scene: Node = (load(KIT) as PackedScene).instantiate()
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var mesh := mi.mesh.duplicate() as Mesh
			var metal := String(mi.name) == "grate"
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s) as StandardMaterial3D
				if m == null:
					continue
				m = m.duplicate() as StandardMaterial3D
				m.metallic = 0.55 if metal else 0.0
				m.metallic_texture = null
				# The packed map is glossy (the roughness scalar only multiplies it):
				# wet plastic under a torch. Dull stone, rusty iron.
				m.roughness_texture = null
				m.roughness = 0.6 if metal else 0.85
				m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
				m.albedo_color = KIT_TINT.get(String(mi.name), Color.WHITE)
				mesh.surface_set_material(s, m)
			_kit[String(mi.name)] = mesh
		scene.free()
	return _kit.get(piece)


var _pieces: Node3D


func _piece(name_: String, xf: Transform3D, shadows := true) -> MeshInstance3D:
	var mesh := kit_mesh(name_)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = name_.capitalize()
	mi.mesh = mesh
	mi.transform = xf
	mi.layers = VISUAL_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = PIECE_RANGE
	mi.visibility_range_end_margin = 4.0
	_pieces.add_child(mi)
	_chunks.append(mi)
	return mi


## The tunnels, the gates in the closed sides of chambers, and the bones and
## fungus, from the kit.
func _build_kit() -> void:
	_pieces = Node3D.new()
	_pieces.name = "Kit"
	add_child(_pieces)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map.origin) ^ 0x6b6974
	var tunnel := kit_mesh("tunnel")
	var tunnel_shape: Shape3D = tunnel.create_trimesh_shape() if tunnel != null else null
	var tunnels := 0
	var gates := 0
	var props := 0
	var keys: Array = map.cells.keys()
	keys.sort()
	for key: Vector2i in keys:
		var at: Vector3 = map.to_world(key)
		var c: ModuleMaze.Cell = map.cells[key]
		if not _is_chamber(key):
			var b := _tunnel_basis(key)
			if _piece("tunnel", Transform3D(b, at)) != null:
				tunnels += 1
				var cs := CollisionShape3D.new()
				cs.shape = tunnel_shape
				cs.transform = Transform3D(b, at)
				_collision_body().add_child(cs)
			# Now and then something grows or lies on a walkway.
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var roll := rng.randf()
			if roll < FUNGUS_SHARE:
				var p := b * Vector3(side * 1.45, 0.02, rng.randf_range(-2.0, 2.0))
				_piece("fungus", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.0)), at + p), false)
				props += 1
			elif roll < FUNGUS_SHARE + BONES_SHARE:
				var p := b * Vector3(side * 1.35, 0.02, rng.randf_range(-1.8, 1.8))
				_piece("bones", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 0.72), at + p), false)
				props += 1
			continue
		# A chamber: gates across its closed sides, and its own heap of the dead.
		for side in ModuleMaze.ORDER:
			var dir := _side_dir(side)
			if not (c.open & side):
				var g := _piece("grate", Transform3D(Basis.looking_at(-dir, Vector3.UP).scaled(Vector3.ONE * GRATE_W),
					at + dir * (CH_R - 0.06)))
				if g != null:
					gates += 1
		var free_angles: Array[float] = []
		for k in 8:
			free_angles.append(k * TAU / 8.0 + PI / 8.0)
		var shaft := {}
		for s in shafts:
			if s["cell"] == key:
				shaft = s
		for pick in [["bones", 0.95, 2.0], ["fungus", 0.9, 2.25]]:
			if rng.randf() > 0.8:
				continue
			for tries in 6:
				var ang: float = free_angles[rng.randi_range(0, free_angles.size() - 1)]
				var p := Vector3(cos(ang), 0.0, sin(ang)) * float(pick[2])
				if not shaft.is_empty():
					var hole: Vector3 = shaft["hole"]
					if Vector2(at.x + p.x - hole.x, at.z + p.z - hole.z).length() < 1.4:
						continue
				free_angles.erase(ang)
				_piece(pick[0], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * float(pick[1])), at + p), false)
				props += 1
				break
	print("[sewer] kit: %d tunnel sections, %d gates, %d props" % [tunnels, gates, props])


func _brick_material() -> StandardMaterial3D:
	# The Higgsfield brick (tools/build_sewer_texture.py), world triplanar.
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/sewer_hf_albedo.png")
	m.albedo_color = Color(0.82, 0.8, 0.78)
	m.normal_enabled = true
	m.normal_texture = load("res://textures/sewer_hf_normal.png")
	m.normal_scale = 1.2
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.34
	m.roughness = 0.62
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m


func _floor_material() -> StandardMaterial3D:
	# The same brick laid as a floor, wet.
	var m := _brick_material()
	m.albedo_color = Color(0.6, 0.58, 0.55)
	m.roughness = 0.35
	return m


# --- Ladders, water, torches ---------------------------------------------------------

func _build_ladders() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.15, 0.12)
	iron.metallic = 0.45
	iron.roughness = 0.6
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
		mi.material_override = iron
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(mi)
		s["ladder"] = holder


## Black water standing in every tunnel's channel (WATER_Y under the
## walkways), and in the mouths' channel notches; one merged mesh. The sewer is
## in the group "water" (player.gd `water_depth`): step into a channel and you
## wade.
func _build_water() -> void:
	add_to_group(&"water")
	_water = StandardMaterial3D.new()
	_water.albedo_color = Color(0.02, 0.026, 0.02)
	_water.roughness = 0.04
	_water.metallic_specular = 0.8
	_water.normal_enabled = true
	_water.normal_texture = load("res://textures/stone_plain_normal.png")
	_water.normal_scale = 0.2
	_water.uv1_triplanar = true
	_water.uv1_world_triplanar = true
	_water.uv1_scale = Vector3.ONE * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := CHANNEL_X1 - CHANNEL_X0 - 0.04
	var mid := (CHANNEL_X0 + CHANNEL_X1) * 0.5
	for key in map.cells:
		var at: Vector3 = map.to_world(key)
		if not _is_chamber(key):
			var box := BoxMesh.new()
			box.size = Vector3(width, 0.02, map.cell_size)
			st.append_from(box, 0, Transform3D(_tunnel_basis(key), at + _tunnel_basis(key) * Vector3(mid, WATER_Y, 0.0)))
			continue
		var c: ModuleMaze.Cell = map.cells[key]
		for side in ModuleMaze.ORDER:
			if not (c.open & side):
				continue
			var dir := _side_dir(side)
			var b := Basis.looking_at(dir, Vector3.UP)
			var length := map.cell_size * 0.5 - MOUTH_FROM
			var box := BoxMesh.new()
			box.size = Vector3(1.0, 0.02, length)
			st.append_from(box, 0, Transform3D(b, at + dir * (MOUTH_FROM + length * 0.5) + Vector3(0.0, WATER_Y, 0.0)))
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = _water
	mi.layers = VISUAL_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## player.gd `water_depth` asks every "water" node: the surface over `point`,
## or -INF where there is none -- inside a tunnel's channel, the water's level.
func water_surface_at(point: Vector3) -> float:
	if point.y > SPLIT_Y or map == null:
		return -INF
	var rel := point - map.origin
	var key := Vector2i(roundi(rel.x / map.cell_size), roundi(rel.z / map.cell_size))
	if not map.cells.has(key) or _is_chamber(key):
		return -INF
	var local := _tunnel_basis(key).inverse() * (point - map.to_world(key))
	if local.x < CHANNEL_X0 or local.x > CHANNEL_X1:
		return -INF
	return FLOOR_Y + WATER_Y


func _build_torches() -> void:
	var scene: PackedScene = load(ModuleLevel.TORCH_SCENE)
	_torches = Node3D.new()
	_torches.name = "Torches"
	add_child(_torches)
	var maze := get_parent()
	var energy := 1.1
	if maze != null and maze.get("module_torch_energy") != null:
		energy = float(maze.get("module_torch_energy"))
	var spots: Array = []
	var n := 0
	for key in map.cells:
		var at: Vector3 = map.to_world(key)
		if not _is_chamber(key):
			if (key.x + key.y) % TORCH_EVERY != 0:
				continue
			n += 1
			var b := _tunnel_basis(key)
			var out := b * Vector3(1.0 if n % 2 == 0 else -1.0, 0.0, 0.0)
			spots.append([at + out * (TUNNEL_WALL - 0.05) + Vector3(0.0, TORCH_UP, 0.0), out])
			continue
		# One on the chamber wall, between two mouths, away from the ladder.
		var c: ModuleMaze.Cell = map.cells[key]
		var best := Vector3.ZERO
		var best_score := -INF
		for k in 4:
			var ang := PI * 0.25 + k * PI * 0.5
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var score := 0.0
			for s in shafts:
				if s["cell"] == key:
					score += (dir * CH_R).distance_to(s["hole"] as Vector3 - at)
			if score > best_score:
				best_score = score
				best = dir
		spots.append([at + best * (CH_R - 0.05) + Vector3(0.0, 2.1, 0.0), best])
	for spot in spots:
		var torch := ModuleLevel._hang_torch(_torches, scene, spot[0], spot[1], energy * TORCH_BOOST, TORCH_REACH)
		torch.set("sewer", true)
		var light := torch.get_node_or_null("Light") as Light3D
		if light != null:
			light.light_cull_mask = VISUAL_LAYER | 1
			(light as OmniLight3D).omni_attenuation = TORCH_FALLOFF
	print("[sewer] %d torches" % spots.size())


# --- Running ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var cam := get_viewport().get_camera_3d()
	var y: float = cam.global_position.y if cam != null else _player.global_position.y
	_set_below(y < SPLIT_Y)


## The sewer draws only while the camera is down here. (The dungeon stays drawn
## below: the shafts look up into it, and its torches are ranked out.)
func _set_below(below: bool, force := false) -> void:
	if below == _below and not force:
		return
	_below = below
	for c in _chunks:
		c.visible = below
	for child in get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Water"):
			(child as MeshInstance3D).visible = below
	if _torches != null:
		_torches.visible = below
	# Lights spawned up there since the level was built (the boss, a chest's
	# room light) are kept off this layer too.
	if below and get_parent() != null and get_parent().has_method("_wall_off_sewer"):
		get_parent().call("_wall_off_sewer")


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
