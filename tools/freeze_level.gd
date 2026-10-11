extends SceneTree

## Freezes the procedural level into a static, bakeable scene.
##
##   godot --path . --windowed --script res://tools/freeze_level.gd
##
## Writes `scenes/level_baked.tscn`, then YOU press "Bake Lightmaps" in the
## editor with that scene open. The bake itself cannot be automated:
## `LightmapGI` exposes only `set_light_data`/`get_light_data`/`bake_quality`
## to scripting -- `bake()` is an editor-only operation, confirmed by probing
## the class rather than assumed.
##
## Why freezing is necessary at all: a lightmap is precomputed for fixed
## geometry, and this maze is generated at runtime from a seed. There is
## nothing to bake against until the level exists. So one seed becomes the
## level, and that is the trade the baked lighting costs.
##
## Two further constraints drive the shape of this file:
##
##   * `LightmapGI` cannot light a `MultiMeshInstance3D`. Every chunk is
##     therefore MERGED into a single ArrayMesh with its instance transforms
##     baked into the vertices. Draw calls stay about the same -- one per chunk
##     either way -- but the geometry is no longer instanced, so it costs real
##     memory. That is the price of baked light.
##   * Lightmapped meshes need a UV2 channel, which generated meshes do not
##     have. `ArrayMesh.lightmap_unwrap()` builds one, and it is slow, so it
##     runs per chunk rather than over the whole level at once.

const Graph = preload("res://scripts/maze_graph.gd")
const Contour = preload("res://scripts/wall_contour.gd")
const OrganicMaze = preload("res://scripts/organic_maze.gd")
const Dressing = preload("res://scripts/organic_dressing.gd")

## Must match the Maze exports, or the baked geometry will not line up with the
## grid, spawns and navigation that `maze.gd` still generates at runtime.
const SEED := 20260918
const EXTENT := 92.0
const MARGIN := 16.0
const RES := 480
const CORRIDOR_RADIUS := 2.2
const BOSS_RADIUS := 30.0
const WALL_ROWS := 3
const CHEST_ROOMS := 6
const LONG_LINKS := 1
const DEAD_ENDS := 16
const STONE_TINT := 0.55
const TORCH_ENERGY := 0.6
const TORCH_SPACING := 17.0

## Metres per lightmap texel. Coarse on purpose: the map is 216 m across, and
## at a quarter of this the atlases run into gigabytes and the bake never
## finishes on a Quadro P620.
const TEXEL := 0.6

## Binary, not .tscn. A text scene stores every vertex as ASCII: the first
## attempt wrote 510 MB for 2.2 M triangles, which Godot would spend minutes
## parsing on every load. `.scn` is the same scene packed as bytes.
const OUT_PATH := "res://scenes/level_baked.scn"


func _initialize() -> void:
	_run()


func _run() -> void:
	var started := Time.get_ticks_msec()
	var g = Graph.new()
	g.boss_radius = BOSS_RADIUS
	g.corridor_radius = CORRIDOR_RADIUS
	g.cell_radius = 2.3
	g.boss_doors = 2
	g.dead_end_spurs = DEAD_ENDS
	g.long_link_count = LONG_LINKS
	g.generate(SEED, EXTENT, 13.0, CHEST_ROOMS, 7.0, 10.0)
	g.build_cells(g.safe_cell_count(1.8))
	g._build_index()

	var cell := ((EXTENT + MARGIN) * 2.0) / float(RES)
	var origin := Vector2(-(EXTENT + MARGIN) + cell * 0.5, -(EXTENT + MARGIN) + cell * 0.5)
	var loops := _loops(g, cell)
	print("[freeze] graph: %d nodes, %d chambers, %d loops"
		% [g.nodes.size(), g.chamber_at.size(), loops.size()])

	var root := Node3D.new()
	root.name = "BakedLevel"
	get_root().add_child(root)

	var scratch := Node3D.new()
	var wall_chunks := Node3D.new()
	var ceiling_chunks := Node3D.new()
	var floor_chunks := Node3D.new()
	var wall_body := StaticBody3D.new()
	wall_body.name = "WallCollision"
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	scratch.add_child(wall_chunks)
	scratch.add_child(ceiling_chunks)
	scratch.add_child(floor_chunks)
	root.add_child(scratch)
	root.add_child(wall_body)
	root.add_child(floor_body)

	var counts: Dictionary = OrganicMaze.build(g, loops, cell, origin, {
		"wall_chunks": wall_chunks,
		"wall_body": wall_body,
		"ceiling_chunks": ceiling_chunks,
		"floor_chunks": floor_chunks,
		"floor_body": floor_body,
	}, {
		"wall_rows": WALL_ROWS,
		"slab": 3.0,
		"tint": STONE_TINT,
	})
	print("[freeze] built %d panels, %d ceiling, %d floor, %d collision shapes"
		% [counts.get("wall_panels", 0), counts.get("ceiling_slabs", 0),
			counts.get("floor_slabs", 0), counts.get("collision_shapes", 0)])

	# --- flatten every MultiMesh into a static, unwrapped mesh --------------
	var merged := Node3D.new()
	merged.name = "Static"
	root.add_child(merged)
	var total_tris := 0
	var unwrap_failures := 0
	for holder in [wall_chunks, ceiling_chunks, floor_chunks]:
		for node in holder.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi: MultiMeshInstance3D = node
			var made := _flatten(mmi, merged)
			if made < 0:
				unwrap_failures += 1
			else:
				total_tris += made
	print("[freeze] flattened to %d triangles across %d static meshes (%d unwrap failures)"
		% [total_tris, merged.get_child_count(), unwrap_failures])
	scratch.queue_free()
	root.remove_child(scratch)

	# --- torches, switched to static so their light is baked in ------------
	var torches := Node3D.new()
	torches.name = "Torches"
	root.add_child(torches)
	var torch_scene: PackedScene = load("res://scenes/torch.tscn")
	var dressed: Dictionary = Dressing.build(g, loops, cell, origin,
		{"torches": torches},
		{"torch_scene": torch_scene, "torch_spacing": TORCH_SPACING,
		 "torch_energy": TORCH_ENERGY, "seed": SEED})
	var staticised := 0
	for t in torches.get_children():
		var l := (t as Node3D).get_node_or_null(^"Light")
		if l is Light3D:
			# STATIC means the lightmapper accounts for this light and it stops
			# being evaluated per frame -- which is where the win comes from,
			# 209 real-time omnis being the level's single biggest cost.
			(l as Light3D).light_bake_mode = Light3D.BAKE_STATIC
			staticised += 1
	print("[freeze] %d torches, %d switched to BAKE_STATIC"
		% [dressed.get("torches", 0), staticised])

	var gi := LightmapGI.new()
	gi.name = "LightmapGI"
	gi.quality = LightmapGI.BAKE_QUALITY_LOW
	gi.bounces = 1
	root.add_child(gi)

	# --- save ----------------------------------------------------------------
	_set_owner(root, root)
	# Stamped so the game can refuse a mismatched pair. Baked geometry from one
	# seed with a grid generated from another desyncs silently: walls where the
	# map says corridor, and no error anywhere.
	root.set_meta("freeze_seed", SEED)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("[freeze] pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		push_error("[freeze] save failed: %d" % err)
		quit(1)
		return
	print("[freeze] wrote %s in %.1f s" % [OUT_PATH,
		float(Time.get_ticks_msec() - started) / 1000.0])
	print("[freeze] NEXT: open that scene in the editor, select LightmapGI,")
	print("[freeze]       and press Bake Lightmaps. The bake cannot be scripted.")
	quit(0)


## One MultiMesh -> one static MeshInstance3D with its transforms baked in and
## a UV2 channel generated. Returns the triangle count, or -1 if the unwrap
## failed (in which case the mesh is still added, just not lightmappable).
func _flatten(mmi: MultiMeshInstance3D, parent: Node3D) -> int:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null or mm.instance_count == 0:
		return 0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in mm.instance_count:
		var t: Transform3D = mmi.transform * mm.get_instance_transform(i)
		for s in mm.mesh.get_surface_count():
			st.append_from(mm.mesh, s, t)
	var mesh: ArrayMesh = st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return 0

	var tris := 0
	for s in mesh.get_surface_count():
		tris += mesh.surface_get_array_len(s) / 3

	var ok := mesh.lightmap_unwrap(Transform3D.IDENTITY, TEXEL)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = mmi.name
	# The material and the shadow setting come from the MultiMesh instance that
	# is being replaced, so the flattened copy looks identical.
	mi.material_override = mmi.material_override
	mi.cast_shadow = mmi.cast_shadow
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(mi)
	return tris if ok == OK else -1


## PackedScene only keeps nodes that are owned by the root being packed.
func _set_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_set_owner(child, owner_node)


func _loops(g, cell: float) -> Array:
	var solid: Array = []
	for y in RES:
		var row := []
		row.resize(RES)
		for x in RES:
			row[x] = g.inside(Vector2(-(EXTENT + MARGIN) + (x + 0.5) * cell,
				-(EXTENT + MARGIN) + (y + 0.5) * cell))
		solid.append(row)
	var open_at := func(x: int, z: int) -> bool:
		if x < 0 or z < 0 or x >= RES or z >= RES:
			return false
		return solid[z][x]
	var out: Array = []
	for loop in Contour.trace(open_at, RES):
		out.append(Contour.smooth(Contour.resample(loop, 1.2), 3))
	return out
