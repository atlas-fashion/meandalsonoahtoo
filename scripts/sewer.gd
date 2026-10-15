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
## Geometry: one CSG tree -- the pipes' and chambers' outer shells, minus their
## insides cut flat at the floor, minus a water channel down the middle and a
## few round inlets in the walls -- baked to a mesh a frame later (`_bake`: CSG
## needs a frame before it will bake) and split into CHUNK-sized pieces, so a
## torch's shadow pass draws only the stone near it. One trimesh collision.
## A round chamber at every manhole, its shaft up through the ceiling to the
## dungeon floor, an iron ladder down it. Pipes: brick (textures/
## sewer_brick_*.png, tools/build_sewer_brick.py), world triplanar.
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
## The pipe: inner radius, axis height above the walkway, shell thickness.
const PIPE_R := 2.2
const AXIS_UP := 1.4
const SHELL := 1.0
## The chamber under each manhole.
const CHAMBER_R := 3.0
const CHAMBER_H := 5.0
## The chamber is centred this far back from the cell centre, away from the
## shaft, so the shaft (1.5 m out) rises at its wall and the ladder is fixed
## to stone rather than standing free in the middle of the room.
const CHAMBER_SHIFT := 0.9
## The shaft up to the manhole.
const SHAFT_R := 0.56
const SHAFT_OUTER := 0.95
## The water channel down the middle of the walkway.
const CHANNEL_W := 0.8
const CHANNEL_D := 0.35
const WATER_DROP := 0.13
const WATER_TRIM := 2.1
## Round inlets in the pipe walls.
const INLET_R := 0.42
const INLET_DEEP := 0.8
const INLET_EVERY := 3
## Dead-end spurs off the main runs.
const SPURS := 3
## Render chunks.
const CHUNK := 24.0
const VISUAL_LAYER := 1 << 15
## Torches: one every TORCH_EVERY cells of pipe, sides alternating.
const TORCH_EVERY := 2
const TORCH_UP := 1.0
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
			"chamber": built.to_world(pos) - along * CHAMBER_SHIFT + Vector3(0.0, FLOOR_Y, 0.0)})
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

func _build_csg() -> void:
	var wall := _brick_material()
	var floor_mat := _floor_material()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.018, 0.016)
	dark.roughness = 1.0
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
	var axis_y := FLOOR_Y + AXIS_UP

	for run in _runs():
		var a: Vector3 = map.to_world(run[0])
		var b: Vector3 = map.to_world(run[1])
		var mid := (a + b) * 0.5
		var length := a.distance_to(b)
		var along_x := absf(b.x - a.x) > 0.1
		for layer in [[outer, PIPE_R + SHELL, length + 0.02, wall], [inner, PIPE_R, length + 0.02, wall]]:
			var cyl := CSGCylinder3D.new()
			cyl.radius = layer[1]
			cyl.height = layer[2]
			cyl.sides = 28
			cyl.material = layer[3]
			cyl.position = Vector3(mid.x, axis_y, mid.z)
			cyl.rotation = Vector3(0.0, 0.0, PI * 0.5) if along_x else Vector3(PI * 0.5, 0.0, 0.0)
			(layer[0] as Node).add_child(cyl)
		var ch := CSGBox3D.new()
		ch.size = Vector3(length, CHANNEL_D * 2.0, CHANNEL_W) if along_x else Vector3(CHANNEL_W, CHANNEL_D * 2.0, length)
		ch.position = Vector3(mid.x, FLOOR_Y, mid.z)
		ch.material = floor_mat
		cuts.add_child(ch)

	# Joints: a ball at every cell that is not a plain straight, so bends and
	# junctions are round; a chamber at every manhole.
	for key in map.cells:
		var c: ModuleMaze.Cell = map.cells[key]
		var at: Vector3 = map.to_world(key)
		if built.manholes.has(key):
			continue
		if c.open == (ModuleMaze.N | ModuleMaze.S) or c.open == (ModuleMaze.E | ModuleMaze.W):
			continue
		for layer in [[outer, PIPE_R + SHELL], [inner, PIPE_R]]:
			var ball := CSGSphere3D.new()
			ball.radius = layer[1]
			ball.radial_segments = 28
			ball.rings = 14
			ball.material = wall
			ball.position = Vector3(at.x, axis_y, at.z)
			(layer[0] as Node).add_child(ball)
	for s in shafts:
		var ch: Vector3 = s["chamber"]
		for layer in [[outer, CHAMBER_R + SHELL, CHAMBER_H + SHELL * 2.0, FLOOR_Y - SHELL],
				[inner, CHAMBER_R, CHAMBER_H + 1.0, FLOOR_Y - 1.0]]:
			var cyl := CSGCylinder3D.new()
			cyl.radius = layer[1]
			cyl.height = layer[2]
			cyl.sides = 36
			cyl.material = wall
			cyl.position = Vector3(ch.x, float(layer[3]) + float(layer[2]) * 0.5, ch.z)
			(layer[0] as Node).add_child(cyl)
		# The shaft: a tube from the chamber's roof up to just under the
		# dungeon's floor tiles, and its bore through everything.
		var hole: Vector3 = s["hole"]
		var top := -0.15
		var bottom := FLOOR_Y + CHAMBER_H
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

	# Round inlets in the walls of plain straights, sides alternating.
	var n := 0
	for key in map.cells:
		var c: ModuleMaze.Cell = map.cells[key]
		var ns: bool = c.open == (ModuleMaze.N | ModuleMaze.S)
		if built.manholes.has(key) or not (ns or c.open == (ModuleMaze.E | ModuleMaze.W)):
			continue
		if (key.x * 7 + key.y * 13) % INLET_EVERY != 0:
			continue
		n += 1
		var side := 1.0 if n % 2 == 0 else -1.0
		var out_dir := Vector3(side, 0.0, 0.0) if ns else Vector3(0.0, 0.0, side)
		var at: Vector3 = map.to_world(key)
		var inlet := CSGCylinder3D.new()
		inlet.radius = INLET_R
		inlet.height = INLET_DEEP * 2.0
		inlet.sides = 16
		inlet.material = dark
		inlet.position = Vector3(at.x, axis_y + 0.35, at.z) + out_dir * PIPE_R
		inlet.rotation = Vector3(0.0, 0.0, PI * 0.5) if ns else Vector3(PI * 0.5, 0.0, 0.0)
		cuts.add_child(inlet)
	# The chambers' floors are whole: the channel stops at their walls, so the
	# ladder's foot is never in the water.
	for s in shafts:
		var ch: Vector3 = s["chamber"]
		var fill := CSGCylinder3D.new()
		fill.radius = CHAMBER_R + 0.02
		fill.height = CHANNEL_D + 0.1
		fill.sides = 36
		fill.material = floor_mat
		fill.position = Vector3(ch.x, FLOOR_Y - (CHANNEL_D + 0.1) * 0.5, ch.z)
		_csg.add_child(fill)
	_csg.visible = false
	_csg.use_collision = false


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
	var body := StaticBody3D.new()
	body.name = "SewerCollision"
	body.collision_layer = 1 | 2 | 256
	body.collision_mask = 0
	add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# Split by triangle centre into chunks, one surface per material.
	var tools := {}
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if idx.size() > 0 else verts.size()
		var mat := mesh.surface_get_material(s)
		for t in range(0, count, 3):
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
		mi.name = "Pipes_%d_%d" % [ck.x, ck.y]
		mi.mesh = by_chunk[ck]
		mi.layers = VISUAL_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		_chunks.append(mi)
	_set_below(false, true)
	print("[sewer] baked %d triangles into %d chunks" % [tris, _chunks.size()])


func _brick_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/sewer_brick_albedo.png")
	m.normal_enabled = true
	m.normal_texture = load("res://textures/sewer_brick_normal.png")
	m.normal_scale = 1.4
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.4
	m.roughness = 0.82
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m


func _floor_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/stone_plain_albedo.png")
	m.albedo_color = Color(2.2, 1.9, 1.6)
	m.normal_enabled = true
	m.normal_texture = load("res://textures/stone_plain_normal.png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5
	# Wet: a sheen for the torches to catch.
	m.roughness = 0.45
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


func _build_water() -> void:
	_water = StandardMaterial3D.new()
	_water.albedo_color = Color(0.035, 0.045, 0.035)
	_water.roughness = 0.06
	_water.metallic_specular = 0.7
	_water.normal_enabled = true
	_water.normal_texture = load("res://textures/stone_plain_normal.png")
	_water.normal_scale = 0.25
	_water.uv1_triplanar = true
	_water.uv1_world_triplanar = true
	_water.uv1_scale = Vector3.ONE * 0.6
	# One strip per joined pair of cells, merged into one mesh. Under a chamber
	# the channel is filled (`_build_csg`), so a strip starts WATER_TRIM from a
	# manhole cell's centre, inside the chamber's floor, hidden.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for key in map.cells:
		var c: ModuleMaze.Cell = map.cells[key]
		for side in [ModuleMaze.E, ModuleMaze.S]:
			if not (c.open & side):
				continue
			var other: Vector2i = key + ModuleMaze.DIRS[side]
			var a: Vector3 = map.to_world(key)
			var b: Vector3 = map.to_world(other)
			var dir := (b - a).normalized()
			if built.manholes.has(key):
				a += dir * WATER_TRIM
			if built.manholes.has(other):
				b -= dir * WATER_TRIM
			var length := a.distance_to(b)
			if length <= 0.05:
				continue
			var box := BoxMesh.new()
			box.size = Vector3(length, 0.02, CHANNEL_W - 0.02) if side == ModuleMaze.E else Vector3(CHANNEL_W - 0.02, 0.02, length)
			st.append_from(box, 0, Transform3D(Basis.IDENTITY, (a + b) * 0.5 + Vector3(0.0, -WATER_DROP, 0.0)))
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = _water
	mi.layers = VISUAL_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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
		var c: ModuleMaze.Cell = map.cells[key]
		var ns: bool = c.open == (ModuleMaze.N | ModuleMaze.S)
		if not (ns or c.open == (ModuleMaze.E | ModuleMaze.W)) or built.manholes.has(key):
			continue
		if (key.x * 5 + key.y * 3) % TORCH_EVERY != 0:
			continue
		n += 1
		var side := 1.0 if n % 2 == 0 else -1.0
		var out_dir := Vector3(side, 0.0, 0.0) if ns else Vector3(0.0, 0.0, side)
		var wall := sqrt(PIPE_R * PIPE_R - pow(TORCH_UP - AXIS_UP, 2.0))
		spots.append([map.to_world(key) + out_dir * (wall - 0.05) + Vector3(0.0, TORCH_UP, 0.0), out_dir])
	for s in shafts:
		var ch: Vector3 = s["chamber"]
		var along: Vector3 = s["along"]
		spots.append([ch - along * (CHAMBER_R - 0.05) + Vector3(0.0, 2.2, 0.0), -along])
	for spot in spots:
		var torch := ModuleLevel._hang_torch(_torches, scene, spot[0], spot[1], energy, 12.0)
		torch.set("sewer", true)
		var light := torch.get_node_or_null("Light") as Light3D
		if light != null:
			light.light_cull_mask = VISUAL_LAYER | 1
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
