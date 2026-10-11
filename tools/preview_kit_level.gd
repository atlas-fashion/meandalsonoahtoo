extends SceneTree

## Builds the organic maze out of the real Tripo kit and photographs it.
##
##   godot --path . --windowed --script res://tools/preview_kit_level.gd
##
## This is the first time the graph, the wall contour, the placer and the actual
## meshes are all in the same process, so it is the first thing that can show
## whether the kit tiles on a curved boundary or whether it gaps, z-fights and
## leans. Every check before this one was arithmetic on transforms; a transform
## list cannot tell you the wall looks wrong.
##
## NOT headless, on purpose -- `CLAUDE.md` is explicit that the dummy renderer
## reports fiction. This needs a real swapchain to produce an image at all.

const Graph = preload("res://scripts/maze_graph.gd")
const Contour = preload("res://scripts/wall_contour.gd")
const Placer = preload("res://scripts/kit_placer.gd")
## Preloaded so the preview shows the SAME material the game builds -- tint,
## world triplanar and normal strength. Without it this tool renders the raw
## imported material and quietly disagrees with the game about how the walls
## look, which is worse than having no preview.
const OrganicMaze = preload("res://scripts/organic_maze.gd")

## These mirror the `organic_*` exports on `Maze`. They are duplicated rather
## than read from the game because this tool builds the level without the game,
## but they DO have to be kept in step: a preview running the old numbers shows
## a level that no longer exists, which is worse than no preview.
const RES := 480
const EXTENT := 108.0
const PANEL_WIDTH := 2.0
const WALL_ROWS := 3
const CEIL_SLAB := 3.0
const CORRIDOR_RADIUS := 2.2
const DEAD_ENDS := 16
const LONG_LINKS := 1

const KIT := {
	"panel": "res://models/kit/wall_panel_ready.glb",
	"cracked": "res://models/kit/wall_cracked_ready.glb",
	"window": "res://models/kit/wall_window_ready.glb",
	"ceiling": "res://models/kit/ceiling_slab_ready.glb",
	"vault": "res://models/kit/v2_vault_ready.glb",
	"pillar": "res://models/kit/v2_pillar_ready.glb",
	"door": "res://models/kit/cell_door_ready.glb",
	"frame": "res://models/kit/cell_frame_ready.glb",
}

var _shots: Array[String] = []


func _initialize() -> void:
	# Without this the timings below read the refresh rate, not the game. The
	# first benchmark written for this project reported a flat 20.00 ms at every
	# station for exactly that reason.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run()


func _run() -> void:
	var g = Graph.new()
	g.boss_radius = 30.0
	g.corridor_radius = CORRIDOR_RADIUS
	g.cell_radius = 2.3
	g.boss_doors = 2
	g.dead_end_spurs = DEAD_ENDS
	g.long_link_count = LONG_LINKS
	g.generate(20260918, EXTENT - 16.0, 13.0, 6, 7.0, 10.0)
	g.build_cells(g.safe_cell_count(1.8))
	g._build_index()

	var meshes := {}
	for key in KIT:
		var m := _mesh_of(KIT[key])
		if m == null:
			push_error("kit piece missing or not imported: %s" % KIT[key])
			quit(1)
			return
		meshes[key] = m
		print("%-8s %d surfaces, aabb %s" % [key, m.get_surface_count(),
			str(m.get_aabb().size).pad_decimals(2)])

	var root := Node3D.new()
	get_root().add_child(root)
	_light(root)

	# --- walls ---------------------------------------------------------------
	var cell_size := (EXTENT * 2.0) / float(RES)
	var origin := Vector2(-EXTENT + cell_size * 0.5, -EXTENT + cell_size * 0.5)
	var loops := _contour(g, cell_size)
	var walls: Array[Transform3D] = Placer.wall_transforms(
		g, loops, cell_size, origin, PANEL_WIDTH, WALL_ROWS, 0.2)
	print("wall transforms %d over %d loops" % [walls.size(), loops.size()])

	# Variants are dealt out by position, not by a counter, so the same panel
	# lands in the same place on every build -- a wall that reshuffles its own
	# stonework between runs of the same seed is not reproducible.
	var buckets := {"panel": [] as Array[Transform3D],
		"cracked": [] as Array[Transform3D], "window": [] as Array[Transform3D]}
	for t in walls:
		var h := hash(Vector2i(int(round(t.origin.x * 4.0)), int(round(t.origin.z * 4.0))))
		var pick: String = "panel"
		var r: int = absi(h) % 100
		if r < 8:
			pick = "window"
		elif r < 34:
			pick = "cracked"
		buckets[pick].append(t)
	for key in buckets:
		print("  %-8s %d" % [key, buckets[key].size()])
		_multimesh(root, meshes[key], buckets[key], "Wall_" + key)

	# --- ceiling -------------------------------------------------------------
	var ceil_y: float = float(WALL_ROWS) * Placer.WALL_BASE_HEIGHT
	var ceilings: Array[Transform3D] = Placer.ceiling_transforms(g, CEIL_SLAB, ceil_y)
	var vaults: Array[Transform3D] = Placer.vault_transforms(g, 3.0, 1.0, ceil_y - 0.35)
	print("ceiling slabs %d at y = %.2f" % [ceilings.size(), ceil_y])
	_multimesh(root, meshes["ceiling"], ceilings, "Ceiling")
	_multimesh(root, meshes["vault"], vaults, "Vault")
	print("ceiling %d slabs, %d vault bays" % [ceilings.size(), vaults.size()])
	var piers: Array[Transform3D] = Placer.pillar_transforms(
		g, loops, cell_size, origin, 7.0, 1.15)
	print("pillars %d" % piers.size())
	_multimesh(root, meshes["pillar"], piers, "Pillars")

	# --- cells ---------------------------------------------------------------
	var doors: Array[Transform3D] = Placer.cell_door_transforms(g, 3.0)
	print("cell doors %d" % doors.size())
	_multimesh(root, meshes["door"], doors, "Doors")
	# The frame is a separate, deeper piece; it shares the door's placement but
	# is pushed back so the bars sit inside the archway rather than in front of
	# it. Without the offset the door plane and the frame's opening coincide and
	# the two z-fight along the whole jamb.
	var frames: Array[Transform3D] = []
	for t in doors:
		frames.append(Transform3D(t.basis, t.origin - t.basis.z * 0.35))
	_multimesh(root, meshes["frame"], frames, "Frames")

	_floor(root, g)

	await _shoot(root, g, "eye")
	await _shoot(root, g, "over")
	await _shoot(root, g, "arena")
	# Ablation, not intuition: each row turns off one thing and re-times, so the
	# cost lands on whatever actually carries it. `CLAUDE.md` settled that this
	# game is per-pixel bound, and the render-scale row is what tests whether
	# that still holds once the kit is what is being drawn.
	var base: float = await _measure(root, g, "everything")
	_set_visible(root, ["Wall_panel", "Wall_cracked", "Wall_window"], false)
	var no_walls: float = await _measure(root, g, "walls off")
	_set_visible(root, ["Wall_panel", "Wall_cracked", "Wall_window"], true)
	_set_visible(root, ["Ceiling"], false)
	var no_ceiling: float = await _measure(root, g, "ceiling off")
	_set_visible(root, ["Ceiling"], true)

	# Everything off is the control. Without it "walls cost 10 ms" is not
	# actionable: it does not say whether the other 17 ms is the rest of the kit
	# or a fixed per-frame cost that no amount of geometry work will touch.
	_set_visible(root, ["Wall_panel", "Wall_cracked", "Wall_window", "Ceiling",
		"Doors", "Frames", "Floor"], false)
	var nothing: float = await _measure(root, g, "nothing drawn")
	_set_visible(root, ["Wall_panel", "Wall_cracked", "Wall_window", "Ceiling",
		"Doors", "Frames", "Floor"], true)

	get_root().scaling_3d_scale = 0.5
	var half: float = await _measure(root, g, "render scale 0.5")
	get_root().scaling_3d_scale = 1.0

	print("")
	print("ABLATION against %.2f ms baseline" % base)
	print("  walls off         %+6.2f ms" % (no_walls - base))
	print("  ceiling off       %+6.2f ms" % (no_ceiling - base))
	print("  nothing drawn     %+6.2f ms   (fixed cost %.2f ms)" % [nothing - base, nothing])
	print("  render scale 0.5  %+6.2f ms" % (half - base))

	for s in _shots:
		print("SHOT %s" % ProjectSettings.globalize_path(s))
	quit(0)


func _set_visible(root: Node3D, names: Array, on: bool) -> void:
	for name in names:
		var n := root.get_node_or_null(NodePath(name))
		if n != null:
			(n as Node3D).visible = on


## Frame cost of the kit at the eye station, on the real card at the real
## resolution. `CLAUDE.md` asks for p99 as well as the average, because the
## average hides the stutter players actually notice.
##
## This is the KIT's cost in isolation -- no torches, enemies, physics, glow or
## SSAO -- so it is a floor for the finished level, not a prediction of it.
func _measure(parent: Node3D, g, label: String = "") -> float:
	# Re-asserted here, every station, and then read back. Setting it once in
	# `_initialize()` was not enough -- the first ablation came back with a
	# 16.70 ms median and a 33.55 ms p99, one and two 60 Hz refresh intervals,
	# and two completely different configurations produced identical numbers
	# because both were waiting on the display rather than on the GPU.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var mode := DisplayServer.window_get_vsync_mode()
	if mode != DisplayServer.VSYNC_DISABLED:
		push_error("vsync is still %d -- these timings are the refresh rate, not the game" % mode)

	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.current = true
	parent.add_child(cam)
	var p: Vector2 = g.nodes[g.spawn_node]
	cam.look_at_from_position(Vector3(p.x, 1.7, p.y),
		Vector3(g.boss_centre.x, 1.7, g.boss_centre.y), Vector3.UP)

	# Warm-up: the first frames pay for MultiMesh upload and pipeline
	# compilation, and folding those into the average would flatter nothing and
	# mislead everything.
	for i in 45:
		await process_frame

	var samples: Array[float] = []
	for i in 240:
		var t0 := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	var total := 0.0
	for s in samples:
		total += s
	var avg: float = total / float(samples.size())
	var p99: float = samples[int(float(samples.size()) * 0.99) - 1]
	var median: float = samples[samples.size() / 2]
	var size := DisplayServer.window_get_size()
	print("BENCH %-18s %dx%d  avg %6.2f ms  median %6.2f ms  p99 %6.2f ms  calls %d  prims %d"
		% [label, size.x, size.y, avg, median, p99,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	cam.queue_free()
	return avg


## Every kit piece is a .glb, so Godot hands back a PackedScene; the mesh is on
## the one MeshInstance3D inside it.
func _mesh_of(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path)
	if packed == null:
		return null
	var inst = packed.instantiate()
	var found: Mesh = null
	var stack: Array = [inst]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and found == null:
			found = (n as MeshInstance3D).mesh
		for c in n.get_children():
			stack.append(c)
	inst.queue_free()
	return found


func _contour(g, cell_size: float) -> Array:
	var solid := []
	for y in RES:
		var row := []
		row.resize(RES)
		for x in RES:
			row[x] = g.inside(Vector2(-EXTENT + (x + 0.5) * cell_size,
				-EXTENT + (y + 0.5) * cell_size))
		solid.append(row)
	var open_at := func(x: int, z: int) -> bool:
		if x < 0 or z < 0 or x >= RES or z >= RES:
			return false
		return solid[z][x]
	var out := []
	for loop in Contour.trace(open_at, RES):
		out.append(Contour.smooth(Contour.resample(loop, 1.2), 3))
	return out


## Chunk size for the MultiMesh split, in metres.
##
## Godot culls a MultiMeshInstance3D as ONE object, against the AABB of every
## instance in it. A single MultiMesh holding all 3,736 wall panels spans the
## whole map, so its AABB always intersects the frustum and all 4.5 M triangles
## are submitted every frame no matter where the player stands -- which is why
## the first measurement read 7 draw calls and 27 ms. `maze.gd` already splits
## its walls for exactly this reason; the kit has to do the same.
const CHUNK := 24.0


func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], name: String) -> void:
	if xforms.is_empty():
		return
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
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = OrganicMaze._tinted(mesh, 0.55)
		node.name = "%s_%d_%d" % [name, key.x, key.y]
		holder.add_child(node)


func _floor(parent: Node3D, g) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(EXTENT * 2.2, EXTENT * 2.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.095, 0.09)
	mat.roughness = 1.0
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.name = "Floor"
	parent.add_child(mi)


func _light(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.43, 0.40)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	parent.add_child(sun)


func _shoot(parent: Node3D, g, which: String) -> void:
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 75.0
	parent.add_child(cam)

	if which == "eye":
		# Standing where the player spawns, looking down the corridor they would
		# actually walk. Aimed along the corridor POLYLINE, not at the next
		# graph node: corridors are bowed Beziers, so the straight line between
		# two nodes leaves the corridor and the shot is a close-up of rock.
		var p: Vector2 = g.nodes[g.spawn_node]
		var best: PackedVector2Array = PackedVector2Array()
		var best_d := INF
		var from_start := true
		for line in g.corridors:
			if line.size() < 2:
				continue
			var d0: float = Vector2(line[0]).distance_to(p)
			var d1: float = Vector2(line[line.size() - 1]).distance_to(p)
			if minf(d0, d1) < best_d:
				best_d = minf(d0, d1)
				best = line
				from_start = d0 <= d1
		var eye := p
		var look := p + Vector2(1.0, 0.0)
		if best.size() >= 2:
			var idx := 0 if from_start else best.size() - 1
			var step := 1 if from_start else -1
			eye = Vector2(best[idx])
			# A few points along, so the aim follows the bend rather than the
			# first short segment.
			var ahead: int = clampi(idx + step * 3, 0, best.size() - 1)
			look = Vector2(best[ahead])
			if look.distance_to(eye) < 0.5:
				look = Vector2(best[clampi(idx + step * (best.size() - 1), 0, best.size() - 1)])
		cam.look_at_from_position(Vector3(eye.x, 1.7, eye.y),
			Vector3(look.x, 1.7, look.y), Vector3.UP)
	elif which == "arena":
		var c: Vector2 = g.boss_centre
		cam.look_at_from_position(Vector3(c.x, 26.0, c.y + g.boss_radius * 1.5),
			Vector3(c.x, 0.0, c.y), Vector3.UP)
	else:
		cam.look_at_from_position(Vector3(0.0, 120.0, 60.0), Vector3.ZERO, Vector3.UP)

	# A few frames so the MultiMeshes are uploaded and the light has settled;
	# grabbing on frame one gives a black image.
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := "user://kit_%s.png" % which
	img.save_png(path)
	_shots.append(path)
	cam.queue_free()
