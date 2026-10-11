extends RefCounted

## Builds the playable level out of the solid tunnel sections in models/kit.
##
## `module_maze.gd` decides the layout; this turns it into meshes, collision,
## rooms and the two sealed exits. Nothing here places a wall panel: a cell is
## one finished piece of tunnel with its own floor, walls and vault.
##
## ## Collision is the modules' own surface
##
## It used to be boxes derived from the grid, placed at the CELL BOUNDARY. The
## visible wall face is well inside the cell -- 1.90 m from the centre of a
## straight, against a boundary at 3.0 m -- so the player could walk more than
## a metre into stone that looked solid. `tools/build_modules.py` now exports a
## walls-only collision mesh beside every module, and each cell collides with
## its own module's surface. The shape is one shared resource per kind, so four
## hundred cells cost six trimeshes, not four hundred.
##
## ## Rooms are cloisters
##
## See `module_maze.gd`. A room's ring cells are ordinary modules, which gives
## the arcade and its piers; the cells inside the ring are `court`, which get
## a paved floor and nothing else -- no walls, no roof, open to the sky.

const ModuleMaze := preload("res://scripts/module_maze.gd")

const KINDS := ["straight", "corner", "tee", "cross", "dead", "gate"]

## Clear width of each kind's archway, in metres, measured off the built
## meshes by tools/verify_modules.py. Only used by the fallback box collision
## now, but it MUST track the meshes: stale figures wall up the middle of a
## widened archway with invisible geometry.
const ARCH_WIDTH := {
	"straight": 3.80,
	"corner": 3.50,
	"tee": 3.50,
	"cross": 3.50,
	"dead": 3.50,
	"gate": 3.60,
}

## A cool cast on the stone, to hold it at grey under warm torchlight.
##
## The albedo maps are desaturated at build time, but every light in this game
## is a fire, so neutral stone still reads as brown on screen. Leaning the
## albedo slightly blue is what makes it come back to grey once it is lit.
const STONE_CAST := Color(0.88, 0.94, 1.06)

## Normal map strength. The modules now keep their full Tripo resolution, so
## the normal map sits on the mesh it was authored for and needs far less
## pushing than it did at 6k triangles -- overdriving it on a matching mesh
## just makes every mortar line look like a trench.
const NORMAL_STRENGTH := 1.25

## How much each cell's stone is allowed to differ from its neighbours, in
## brightness and in warmth. Six meshes over a few hundred cells is a lot of
## repetition, and varying each instance a little is free.
const CELL_VALUE_JITTER := 0.16
const CELL_WARMTH_JITTER := 0.07

## --- Invented surfaces ------------------------------------------------------
##
## Every surface `build_modules.py` makes rather than inherits -- the reveals
## of a bored archway, the lid, the floor slab -- carries the material name
## below. None of them has usable UVs into a module's atlas, which is why they
## used to render as flat grey. They get the project's tileable stone instead,
## projected in WORLD space, which needs no UVs and runs continuously across
## cell boundaries, so a cut reveal lines up with the one in the next cell.
const SYNTH_MATERIAL := "synth_stone"
## A graded copy of the pre-Tripo brick (`tools/grade_texture.py`), put through
## the same desaturate / contrast / darken the Tripo atlases get. The original
## is warm tan brick with green vines, and lining every bored archway with it
## made each opening look like it belonged to a different building.
const SYNTH_ALBEDO := "res://textures/stone_grey_albedo.png"
const SYNTH_NORMAL := "res://textures/stone_brick_normal.png"
## Larger blocks than `Mat_wall` used: at 0.5 the bricks came out about 20 cm,
## against Tripo stones of 50-80 cm, and read as tile rather than masonry.
const SYNTH_SCALE := 0.3

## The courtyard paving. Open to the sky, so it is deliberately a different
## surface from the corridor floors -- an outdoor court, not more corridor.
const COURT_ALBEDO := "res://textures/ground_albedo.png"
const COURT_NORMAL := "res://textures/ground_normal.png"
const COURT_SCALE := 0.22
const COURT_DEPTH := 0.6

## --- Atmosphere -------------------------------------------------------------
##
## Torchlight is wide and slow to fall off, so pools of light overlap into
## gloom instead of ending at an edge. `omni_attenuation` below 1 is what does
## most of that work.
const TORCH_COLOUR := Color(1.0, 0.76, 0.50)
const TORCH_ENERGY := 10.0
const TORCH_RANGE := 15.0
const TORCH_ATTENUATION := 0.55
## Height up the wall, as a fraction of the module.
const TORCH_HEIGHT := 0.46
## Roughly one torch per this many corridor cells. Omni light count is a
## per-pixel cost on this hardware, so this is the main lever on frame time.
const TORCH_EVERY := 2
## ...and in a room's arcade, one per this many ring cells. Measured: at 2 the
## boss room's edge ran 24.0 ms and the chest room 22.7 ms, at 4 they were 21.1
## and 20.2 -- rooms put more lights on screen at once than anywhere else, and
## overlapping lights are the per-pixel cost on this card. But at 4 the arcades
## lost their firelight and the rooms read as merely tinted red, so it sits
## between the two. The courtyard sky lights carry the rest.
const ROOM_TORCH_EVERY := 3

## Ambient is a floor on visibility, not a light source. It stays COOL so the
## darkness reads as gloom against warm fire, and it costs nothing.
const AMBIENT_COLOUR := Color(0.16, 0.175, 0.225)
const AMBIENT_ENERGY := 7.0
const FOG_COLOUR := Color(0.035, 0.035, 0.045)
const FOG_DENSITY := 0.030

## Distance from a cell's centre to the inside face of its solid walls, in
## metres, measured off the built meshes by tools/verify_modules.py. The plugged
## walls sit closer to the boundary than the native ones, so a torch hung at a
## fixed distance is buried in stone in one module and floating in the next.
## `cross` is 0 because it has no solid wall at all.
const WALL_FACE := {
	"straight": 1.90,
	"corner": 2.79,
	"tee": 2.79,
	"cross": 0.0,
	"dead": 2.79,
	"gate": 2.06,
}

const TORCH_SCENE := "res://scenes/torch.tscn"

## --- Barred windows ---------------------------------------------------------
##
## A grate set into a corridor wall with red light coming through it from
## somewhere outside, lit from BEHIND so the bars read as dark ironwork.
const WINDOW_MESH := "res://models/kit/wall_window_ready.glb"
const WINDOW_EVERY := 11
const WINDOW_COLOUR := Color(1.0, 0.13, 0.06)
## Strong, because most of what a light behind stone and a grate emits never
## reaches the corridor.
const WINDOW_ENERGY := 7.0
const WINDOW_RANGE := 8.5
const WINDOW_HEIGHT := 0.52

## Thickness of the rock slab placed behind walls that face the outside.
const BACKING_DEPTH := 1.0

## Thickness of the floor collision slab, and of the fallback wall boxes.
const WALL_DEPTH := 1.2
const JAMB_DEPTH := 0.9
## Cells per chunk on each axis. Chunking is what lets visibility ranges cull
## anything, and it keeps the draw-call counter honest.
const CHUNK_CELLS := 4


class Built extends RefCounted:
	var cells: Dictionary          ## Vector2i -> ModuleMaze.Cell
	var size: Vector2i
	var cell_size: float
	var height: float
	var origin: Vector3            ## World position of grid cell (0, 0) centre.
	var spawn: Vector3
	var gates: Array[Dictionary]   ## {pos: Vector2i, world: Vector3, facing: Vector3}
	## {kind: "boss"|"chest", centre: Vector2i, half: int,
	##  entrances: [{cell: Vector2i, side: int}]}
	var rooms: Array[Dictionary] = []
	## Cells that already carry a torch, so a window does not land on top of
	## one. Filled by `place_torches`, read by `place_windows`.
	var torch_cells := {}

	func to_world(grid: Vector2i) -> Vector3:
		return origin + Vector3(float(grid.x) * cell_size, 0.0, float(grid.y) * cell_size)

	func boss_room() -> Dictionary:
		for room in rooms:
			if room["kind"] == "boss":
				return room
		return {}

	func chest_rooms() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for room in rooms:
			if room["kind"] == "chest":
				out.append(room)
		return out

	## World-space centre of a room's courtyard.
	func room_world(room: Dictionary) -> Vector3:
		return to_world(room["centre"])

	## Half the width of a room's open courtyard, in metres.
	func court_half_span(room: Dictionary) -> float:
		return (float(room["half"]) - 0.5) * cell_size

	## World-space entrances: where each doorway meets the corridor, and which
	## way is out.
	func room_doors(room: Dictionary) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for way in room["entrances"]:
			var step: Vector2i = ModuleMaze.DIRS[way["side"]]
			var outward := Vector3(float(step.x), 0.0, float(step.y))
			out.append({
				"cell": way["cell"],
				"outward": step,
				# The gate sits in the archway on the room's side of the
				# boundary, so it closes the room rather than the corridor.
				"world": to_world(way["cell"]) + outward * (cell_size * 0.5 - 0.6),
			})
		return out


## Options for `build`. Kept in one dictionary because the set grew with
## every round of requests, and positional arguments past the fifth were
## already being passed wrong.
const DEFAULTS := {
	"exits": 2,
	"boss_half": 3,
	"chest_half": 2,
	"chest_rooms": 5,
}


## `graph`, when given, is a generated `maze_graph.gd`. The layout is then
## sampled from it -- the organic map's footprint, rooms and dead ends on
## right-angled corridors -- instead of being carved as a plain grid maze.
static func build(parent: Node3D, seed_value: int, size: Vector2i, cell_size: float,
		height: float, view_range: float, tint: float, graph = null,
		options: Dictionary = {}) -> Built:
	var opt := DEFAULTS.duplicate()
	opt.merge(options, true)

	var carved: Dictionary
	if graph != null:
		carved = ModuleMaze.carve_from_graph(graph, size, cell_size,
			int(opt["boss_half"]), int(opt["chest_half"]), int(opt["chest_rooms"]))
	else:
		carved = ModuleMaze.carve(seed_value, size, 4, 0)
	var cells: Dictionary = carved["cells"]

	var out := Built.new()
	out.cells = cells
	out.size = size
	out.cell_size = cell_size
	out.height = height
	if carved.has("rooms"):
		out.rooms.assign(carved["rooms"])
	out.origin = Vector3(
		-float(size.x - 1) * cell_size * 0.5, 0.0, -float(size.y - 1) * cell_size * 0.5)

	# The two furthest-apart rim dead ends become the sealed doorways. They are
	# chosen before the meshes are picked, because a gate is a different piece
	# from a plain dead end and the placer has to know which is which.
	var chosen: Array = ModuleMaze.pick_exits(carved, size, int(opt["exits"]))
	for p in chosen:
		var cell: ModuleMaze.Cell = cells[p]
		if cell.kind == "dead":
			cell.kind = "gate"

	var meshes := _load_meshes(tint)
	_place_meshes(parent, out, meshes, view_range)
	_place_courts(parent, out, tint)
	_place_backing(parent, out)
	_place_collision(parent, out)
	_record_gates(out, chosen)
	out.spawn = _pick_spawn(out) + Vector3(0.0, 0.2, 0.0)
	return out


## Furthest corridor cell from the boss, by walking distance through the maze,
## preferring a through-corridor over a dead end.
static func _pick_spawn(out: Built) -> Vector3:
	var depth := {}
	var queue: Array[Vector2i] = []
	var boss := out.boss_room()
	if boss.is_empty():
		for key in out.cells:
			queue.append(key)
			depth[key] = 0
			break
	else:
		var c: Vector2i = boss["centre"]
		var h: int = boss["half"]
		for dx in range(-h, h + 1):
			for dy in range(-h, h + 1):
				var p := c + Vector2i(dx, dy)
				if out.cells.has(p):
					depth[p] = 0
					queue.append(p)
	if queue.is_empty():
		return out.to_world(Vector2i(out.size.x / 2, out.size.y / 2))

	var head := 0
	var furthest: Vector2i = queue[0]
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		var here: ModuleMaze.Cell = out.cells[at]
		# Never inside a room: the player should arrive in the maze, not in a
		# chest room with the mimic, and never in the boss's courtyard.
		if here.room < 0:
			var best: ModuleMaze.Cell = out.cells[furthest]
			if best.room >= 0 or _spawn_score(here, depth[at]) > _spawn_score(best, depth[furthest]):
				furthest = at
		for side in ModuleMaze.ORDER:
			if not (here.open & side):
				continue
			var to: Vector2i = at + ModuleMaze.DIRS[side]
			if not out.cells.has(to) or depth.has(to):
				continue
			depth[to] = depth[at] + 1
			queue.append(to)
	return out.to_world(furthest)


## How good a cell is to start in: far from the boss, but not a dead end.
static func _spawn_score(cell: ModuleMaze.Cell, depth: int) -> float:
	var degree := 0
	for side in ModuleMaze.ORDER:
		if cell.open & side:
			degree += 1
	return float(depth) + (0.0 if degree <= 1 else 6.0)


## Pulls one Mesh per kind out of the imported glTF scenes.
static func _load_meshes(tint: float) -> Dictionary:
	var meshes := {}
	for kind in KINDS:
		var path := "res://models/kit/module_%s.glb" % kind
		var found := _first_mesh(path)
		if found == null:
			push_error("module_level: no mesh in %s -- run tools/build_modules.py" % path)
			continue
		_fix_material(found, tint)
		meshes[kind] = found
	return meshes


static func _first_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var scene := packed.instantiate()
	var found: Mesh = null
	for node in _walk(scene):
		if node is MeshInstance3D:
			found = (node as MeshInstance3D).mesh
			break
	scene.free()
	return found


static func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


## Shared, so every invented surface in the level is one material and one set
## of textures in video memory.
static var _synth: StandardMaterial3D = null


static func _synth_material(tint: float) -> StandardMaterial3D:
	if _synth != null:
		return _synth
	var m := StandardMaterial3D.new()
	m.resource_name = SYNTH_MATERIAL
	m.albedo_texture = load(SYNTH_ALBEDO)
	m.normal_enabled = true
	m.normal_texture = load(SYNTH_NORMAL)
	m.normal_scale = 1.6
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(SYNTH_SCALE, SYNTH_SCALE, SYNTH_SCALE)
	# Pulled toward the tone of the treated Tripo stone, so a bored archway's
	# reveal reads as the same wall rather than as a patch.
	# The texture is already graded dark, so it takes the same multiply the
	# Tripo materials do and no more.
	m.albedo_color = Color(tint * STONE_CAST.r, tint * STONE_CAST.g, tint * STONE_CAST.b)
	m.metallic = 0.0
	m.roughness = 0.96
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.vertex_color_use_as_albedo = true
	_synth = m
	return m


## Tripo material defaults are wrong for stone in a dark level.
##
## Pieces import with metallic = 1.0 driving a packed ORM map and an albedo
## close to white. Left alone the walls blow out near a torch and read as
## polished metal rather than rock.
static func _fix_material(mesh: Mesh, tint: float) -> void:
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if mat != null and mat.resource_name == SYNTH_MATERIAL:
			mesh.surface_set_material(i, _synth_material(tint))
			continue
		if mat is StandardMaterial3D:
			var m: StandardMaterial3D = mat
			if not m.has_meta("authored_albedo"):
				m.set_meta("authored_albedo", m.albedo_color)
			# Always scale from the authored value. Scaling from the current
			# one compounds every time settings are re-applied.
			var base: Color = m.get_meta("authored_albedo")
			m.albedo_color = Color(
				base.r * tint * STONE_CAST.r,
				base.g * tint * STONE_CAST.g,
				base.b * tint * STONE_CAST.b,
				base.a)
			m.metallic = 0.0
			# The roughness scalar MULTIPLIES the packed ORM map, and Tripo's
			# map is glossy, so it is dropped for the scalar to mean anything.
			m.metallic_texture = null
			m.roughness_texture = null
			m.roughness = 0.97
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			if m.normal_enabled:
				m.normal_scale = NORMAL_STRENGTH
			# Per-cell tinting rides in on instance colour.
			m.vertex_color_use_as_albedo = true


static func _place_meshes(parent: Node3D, out: Built, meshes: Dictionary,
		view_range: float) -> void:
	var holder := Node3D.new()
	holder.name = "ModuleChunks"
	parent.add_child(holder)

	var buckets := {}
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		# A courtyard has no module: that absence IS the open sky.
		if cell.court:
			continue
		var chunk := Vector2i(cell.pos.x / CHUNK_CELLS, cell.pos.y / CHUNK_CELLS)
		var bucket_key := "%d_%d_%s" % [chunk.x, chunk.y, cell.kind]
		if not buckets.has(bucket_key):
			buckets[bucket_key] = {"chunk": chunk, "kind": cell.kind, "cells": []}
		buckets[bucket_key]["cells"].append(cell)

	for bucket_key in buckets:
		var bucket: Dictionary = buckets[bucket_key]
		var kind: String = bucket["kind"]
		if not meshes.has(kind):
			continue
		var list: Array = bucket["cells"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[kind]
		mm.instance_count = list.size()

		# Seeded from the cell position, so a cell keeps its shade whichever
		# chunk it lands in and the level looks the same every build.
		var jitter := RandomNumberGenerator.new()

		var chunk: Vector2i = bucket["chunk"]
		# The node sits at the chunk's CENTRE, not its corner: a visibility
		# range is measured from the node's origin, and with it on a corner
		# whole blocks were culled while still directly in front of the player.
		var chunk_origin := out.to_world(Vector2i(
			chunk.x * CHUNK_CELLS, chunk.y * CHUNK_CELLS)) \
			+ Vector3(1.0, 0.0, 1.0) * (float(CHUNK_CELLS - 1) * out.cell_size * 0.5)
		for i in list.size():
			var cell: ModuleMaze.Cell = list[i]
			mm.set_instance_transform(i, Transform3D(
				_cell_basis(cell), out.to_world(cell.pos) - chunk_origin))
			jitter.seed = hash(cell.pos)
			var value := 1.0 + jitter.randf_range(-CELL_VALUE_JITTER, CELL_VALUE_JITTER)
			var warmth := jitter.randf_range(-CELL_WARMTH_JITTER, CELL_WARMTH_JITTER)
			mm.set_instance_color(i, Color(value + warmth, value, value - warmth * 0.6))

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Chunk_%d_%d_%s" % [chunk.x, chunk.y, kind]
		mmi.multimesh = mm
		mmi.position = chunk_origin
		# The range also has to cover the chunk's own extent, or the far half
		# of a block vanishes while the near half is in view.
		var reach: float = float(CHUNK_CELLS) * out.cell_size * 0.708
		mmi.visibility_range_end = view_range + reach
		mmi.visibility_range_end_margin = out.cell_size
		holder.add_child(mmi)


## A turn of one step takes north to east. Looking down, that is a NEGATIVE
## rotation about +Y in Godot's right-handed basis.
static func _cell_basis(cell: ModuleMaze.Cell) -> Basis:
	return Basis(Vector3.UP, -float(cell.turn) * PI * 0.5)


## Paves each room's open courtyard.
##
## One slab per room rather than per cell: the court is a single open space,
## and a slab per cell would put a seam every six metres across it for no
## reason. The top sits at y = 0 to meet the arcade's floors, and it has depth
## for the same reason the module floors do -- a plane has no underside.
static func _place_courts(parent: Node3D, out: Built, tint: float) -> void:
	if out.rooms.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(COURT_ALBEDO)
	mat.normal_enabled = true
	mat.normal_texture = load(COURT_NORMAL)
	mat.normal_scale = 1.4
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(COURT_SCALE, COURT_SCALE, COURT_SCALE)
	mat.albedo_color = Color(0.72 * tint, 0.72 * tint, 0.74 * tint)
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var holder := Node3D.new()
	holder.name = "Courtyards"
	parent.add_child(holder)
	for room in out.rooms:
		# Out to the ring's inner boundary, so the paving runs under the
		# arcade's arches and meets its floor rather than stopping short.
		var span := (float(room["half"]) * 2.0 - 1.0) * out.cell_size
		var box := BoxMesh.new()
		box.size = Vector3(span, COURT_DEPTH, span)
		box.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Court_%s" % room["kind"]
		mi.mesh = box
		mi.position = out.room_world(room) + Vector3(0.0, -COURT_DEPTH * 0.5, 0.0)
		holder.add_child(mi)


## Sky light over each room's open courtyard.
##
## A courtyard open to a red sky has to be lit BY that sky. Without this the
## rooms were black silhouettes against it: every torch hangs inside the arcade
## facing its walkway, so nothing at all fell on the courtyard or on the side
## of the arcade that faces it. A handful of wide, soft lights above each court
## in the sky's colour does it, spills a little under the arches, and is still
## far cheaper than a directional light, which would shine through every roof
## in the level for want of shadows.
const SKY_LIGHT_COLOUR := Color(1.0, 0.44, 0.32)
## Far higher than a torch, and it has to be. These hang ~10 m from the
## arcade's faces, against a torch's ~2 m from its wall, and at the first
## value (5.5) the arcade stayed a black silhouette while the floor under the
## lights was lit -- measured in a flat-lit shot, which showed every wall
## present and intact, so the darkness was light and not geometry. Brighter
## lights cost nothing more than dim ones: the count and range are what decide
## which pixels they touch.
const SKY_LIGHT_ENERGY := 22.0
const SKY_LIGHT_HEIGHT := 8.5
## How bright the sky itself is drawn. The panorama is a blazing red, and
## against it anything lit at dungeon levels reads as a flat black cut-out.
## Pulled down, it is a dark blood-red sky that still reads as open air.
const SKY_ENERGY := 0.42


static func place_room_lights(parent: Node3D, out: Built) -> Node3D:
	var holder := Node3D.new()
	holder.name = "RoomSkyLights"
	parent.add_child(holder)
	var placed := 0
	for room in out.rooms:
		var mid: Vector3 = out.room_world(room)
		var half: float = out.court_half_span(room)
		# One light per ~15 m of courtyard on each side: one over a chest
		# room, a grid of four over the boss room.
		var per_side := maxi(1, int(round(half * 2.0 / 15.0)))
		var pitch := half * 2.0 / float(per_side)
		for i in per_side:
			for j in per_side:
				var light := OmniLight3D.new()
				light.light_color = SKY_LIGHT_COLOUR
				light.light_energy = SKY_LIGHT_ENERGY
				# Wide enough to reach the arcade on every side of the court
				# from above its middle.
				light.omni_range = maxf(pitch * 1.4, half * 1.5)
				light.omni_attenuation = 0.75
				light.light_specular = 0.0
				light.shadow_enabled = false
				# Only paid for where the room can be seen from.
				light.distance_fade_enabled = true
				light.distance_fade_begin = 55.0
				light.distance_fade_length = 15.0
				light.position = mid + Vector3(
					-half + pitch * (float(i) + 0.5), SKY_LIGHT_HEIGHT,
					-half + pitch * (float(j) + 0.5))
				holder.add_child(light)
				placed += 1
	holder.set_meta("light_count", placed)
	return holder


## Hangs torches on walls, more densely in the rooms.
##
## `density` scales how many are placed; omni light count is a per-pixel cost
## on this hardware, not a CPU one.
static func place_torches(parent: Node3D, out: Built, density: float = 1.0,
		energy: float = TORCH_ENERGY) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ModuleTorches"
	parent.add_child(holder)
	if density <= 0.0 or energy <= 0.0:
		return holder

	var scene: PackedScene = load(TORCH_SCENE)
	if scene == null:
		push_error("module_level: %s is missing; the level will be unlit" % TORCH_SCENE)
		return holder

	var every := maxi(1, int(round(float(TORCH_EVERY) / maxf(density, 0.05))))
	var room_every := maxi(1, int(round(float(ROOM_TORCH_EVERY) / maxf(density, 0.05))))
	var rng := RandomNumberGenerator.new()
	var placed := 0
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.court:
			continue
		# Deterministic per cell, so torch positions do not shuffle when the
		# dictionary happens to iterate in a different order.
		rng.seed = hash(cell.pos) ^ 0x7f4a
		var odds: int = room_every if cell.room >= 0 else every
		if rng.randi_range(0, odds - 1) != 0:
			continue
		# Hang it on a side that is actually walled, or it floats in an arch.
		var walls: Array[int] = []
		for side in ModuleMaze.ORDER:
			if not (cell.open & side):
				walls.append(side)
		if walls.is_empty():
			continue
		var side: int = walls[rng.randi_range(0, walls.size() - 1)]
		var step: Vector2i = ModuleMaze.DIRS[side]
		var dir := Vector3(float(step.x), 0.0, float(step.y))
		var face: float = WALL_FACE.get(cell.kind, out.cell_size * 0.5 - 1.1)
		if face <= 0.01:
			continue
		_hang_torch(holder, scene,
			out.to_world(cell.pos) + dir * (face - 0.12)
				+ Vector3(0.0, out.height * TORCH_HEIGHT, 0.0),
			dir, energy, TORCH_RANGE)
		out.torch_cells[cell.pos] = side
		placed += 1

	holder.set_meta("torch_count", placed)
	return holder


## Puts one torch on a wall. `into_wall` points from the room at the stone.
static func _hang_torch(holder: Node3D, scene: PackedScene, at: Vector3,
		into_wall: Vector3, energy: float, reach: float) -> void:
	var torch := scene.instantiate()
	torch.position = at
	# The scene points its flame down -Z, so it has to face back into the room.
	var outward := -into_wall
	torch.rotation.y = atan2(-outward.x, -outward.z)
	# The torch script owns its own flicker around these, so they are set
	# before it enters the tree and starts running.
	torch.base_energy = energy
	torch.light_range = reach
	holder.add_child(torch)
	var light := torch.get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.omni_attenuation = TORCH_ATTENUATION
		# No specular: a glossy hotspot on the stone reads as a lamp.
		light.light_specular = 0.0
		# Wall torches have never cast shadows in this game; the hand torch is
		# the only shadow caster, and shadows here were measured as worthless.
		light.shadow_enabled = false
		light.light_color = TORCH_COLOUR


## Sets barred windows into corridor walls, with red light coming through.
## Never on a cell that already has a torch.
static func place_windows(parent: Node3D, out: Built, density: float = 1.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ModuleWindows"
	parent.add_child(holder)
	if density <= 0.0:
		return holder
	var mesh := _first_mesh(WINDOW_MESH)
	if mesh == null:
		push_error("module_level: no mesh in %s; no windows" % WINDOW_MESH)
		return holder
	_light_the_grate(mesh)

	var every := maxi(1, int(round(float(WINDOW_EVERY) / maxf(density, 0.05))))
	var rng := RandomNumberGenerator.new()
	var placed := 0
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.court:
			continue
		rng.seed = hash(cell.pos) ^ 0x51ce
		if rng.randi_range(0, every - 1) != 0:
			continue
		if out.torch_cells.has(cell.pos):
			continue
		var face: float = WALL_FACE.get(cell.kind, 0.0)
		if face <= 0.01:
			continue
		var walls: Array[int] = []
		for side in ModuleMaze.ORDER:
			if not (cell.open & side):
				walls.append(side)
		if walls.is_empty():
			continue
		var side: int = walls[rng.randi_range(0, walls.size() - 1)]
		var step: Vector2i = ModuleMaze.DIRS[side]
		var dir := Vector3(float(step.x), 0.0, float(step.y))
		var at := out.to_world(cell.pos) + dir * (face - 0.06) \
			+ Vector3(0.0, out.height * WINDOW_HEIGHT, 0.0)

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = at
		# The panel faces +Z, so turn that to point back into the corridor.
		var inward := -dir
		mi.rotation.y = atan2(inward.x, inward.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 34.0
		mi.visibility_range_end_margin = 6.0
		holder.add_child(mi)

		# Behind the grate, out in the rock: shadowless lights are not stopped
		# by stone, and lit from behind the bars read as dark ironwork.
		var glow := OmniLight3D.new()
		glow.light_color = WINDOW_COLOUR
		glow.light_energy = WINDOW_ENERGY
		glow.omni_range = WINDOW_RANGE
		glow.omni_attenuation = 0.8
		glow.light_specular = 0.0
		glow.shadow_enabled = false
		glow.distance_fade_enabled = true
		glow.distance_fade_begin = 26.0
		glow.distance_fade_length = 8.0
		glow.position = at - inward * 0.45
		holder.add_child(glow)
		placed += 1

	holder.set_meta("window_count", placed)
	return holder


## Darkens the grate so the backlight makes it read as ironwork. No emission:
## any amount saturated the panel to flat red and took the bars with it.
static func _light_the_grate(mesh: Mesh) -> void:
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		if not (mat is StandardMaterial3D):
			continue
		var m: StandardMaterial3D = mat
		if not m.has_meta("authored_albedo"):
			m.set_meta("authored_albedo", m.albedo_color)
		var base: Color = m.get_meta("authored_albedo")
		m.albedo_color = Color(base.r * 0.45, base.g * 0.4, base.b * 0.4, base.a)
		m.metallic = 0.0
		m.roughness = 0.9
		m.emission_enabled = false


## Applies the level's atmosphere to an Environment, grade included, so a
## preview cannot quietly disagree with the game about how dark the level is.
static func configure_environment(env: Environment, ambient: float = 1.0,
		fog: bool = true) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOUR
	env.ambient_light_energy = AMBIENT_ENERGY * ambient
	# Without this the ambient colour does nothing: the scene ships with a sky
	# contribution of 1.0, so ambient came entirely from the sky whatever was
	# set here, and raising it produced a pixel-identical frame.
	env.ambient_light_sky_contribution = 0.0
	env.fog_enabled = fog
	env.fog_light_color = FOG_COLOUR
	env.fog_light_energy = 0.4
	env.fog_density = FOG_DENSITY
	# The game's own grade: ACES at white 4.0 plus a colour adjustment. A
	# fresh Environment is linear with no adjustment, and ACES crushes
	# midtones hard, so previews without this flattered the level badly.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.95
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.92
	# The rooms open onto the sky now, so its brightness is part of the look.
	env.background_energy_multiplier = SKY_ENERGY


## How much of a cell counts as walkable floor, and how wide its doorways are,
## both as fractions of the cell. Deliberately smaller than the real openings:
## the tile grid is a proxy the spawners use, and claiming floor where there is
## stone puts an enemy inside a wall.
const GRID_CORE := 0.30
const GRID_CHANNEL := 0.11


## Paints the module layout into a tile grid of `open_value` / `wall_value`.
##
## **The two grids must be in phase**: the cell size has to be a whole odd
## number of tiles and both counts odd, or the one-tile doorways land on stone
## and the maze rasterises into islands.
static func rasterise(out: Built, tiles: int, tile_size: float,
		open_value: int, wall_value: int) -> Array:
	var grid: Array[PackedByteArray] = []
	var core := out.cell_size * GRID_CORE
	var channel := out.cell_size * GRID_CHANNEL
	var offset := (float(tiles) - 1.0) * 0.5
	for z in tiles:
		var row := PackedByteArray()
		row.resize(tiles)
		for x in tiles:
			var world := Vector3(
				(float(x) - offset) * tile_size, 0.0, (float(z) - offset) * tile_size)
			row[x] = open_value if _walkable(out, world, core, channel) else wall_value
		grid.append(row)
	return grid


static func _walkable(out: Built, world: Vector3, core: float, channel: float) -> bool:
	var gx := int(round((world.x - out.origin.x) / out.cell_size))
	var gz := int(round((world.z - out.origin.z) / out.cell_size))
	var key := Vector2i(gx, gz)
	if not out.cells.has(key):
		return false
	var cell: ModuleMaze.Cell = out.cells[key]
	# A courtyard is open floor from edge to edge.
	if cell.court:
		return true
	var centre := out.to_world(key)
	var lx := world.x - centre.x
	var lz := world.z - centre.z
	if absf(lx) <= core and absf(lz) <= core:
		return true
	for side in ModuleMaze.ORDER:
		if not (cell.open & side):
			continue
		var step: Vector2i = ModuleMaze.DIRS[side]
		if step.x != 0:
			if absf(lz) <= channel and lx * float(step.x) >= 0.0:
				return true
		elif absf(lx) <= channel and lz * float(step.y) >= 0.0:
			return true
	return false


## Backs every wall that faces the outside of the maze with solid rock.
##
## Tripo stone has a ragged foot, so there are small gaps where a wall meets
## the floor. Inside the maze the neighbour's stone is right behind them; on
## the RIM there is nothing, and the same gaps showed the void -- the "large
## missing segments at the bottom of the walls".
static func _place_backing(parent: Node3D, out: Built) -> void:
	var faces: Array[Transform3D] = []
	var half := out.cell_size * 0.5
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.court:
			continue
		for side in ModuleMaze.ORDER:
			if cell.open & side:
				continue
			var step: Vector2i = ModuleMaze.DIRS[side]
			if out.cells.has(cell.pos + step):
				continue
			var dir := Vector3(float(step.x), 0.0, float(step.y))
			var basis := Basis().scaled(_axis_size(
				dir, BACKING_DEPTH, out.cell_size, out.height + BACKING_DEPTH))
			var at := out.to_world(cell.pos) + dir * (half + BACKING_DEPTH * 0.5) \
				+ Vector3(0.0, (out.height - BACKING_DEPTH) * 0.5, 0.0)
			faces.append(Transform3D(basis, at))

	if faces.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	# Near-black and matte: the rock the level is cut from, never a surface.
	mat.albedo_color = Color(0.035, 0.034, 0.040)
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	box.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = faces.size()
	for i in faces.size():
		mm.set_instance_transform(i, faces[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RimBacking"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	mmi.set_meta("backing_count", faces.size())


## One shared trimesh per kind, from the walls-only mesh the build exported.
static func _load_collision() -> Dictionary:
	var shapes := {}
	for kind in KINDS:
		var mesh := _first_mesh("res://models/kit/module_%s_col.glb" % kind)
		if mesh == null:
			continue
		var shape := mesh.create_trimesh_shape()
		if shape == null:
			continue
		# Both faces solid. Tripo meshes are not perfectly consistent in their
		# winding, and a wall whose normal happens to face away from the room
		# would otherwise let the player straight through it.
		shape.backface_collision = true
		shapes[kind] = shape
	return shapes


## --- Collision layers -------------------------------------------------------
##
## The walls exist twice, and which copy a body collides with depends on who
## it is.
##
## The PLAYER collides with the stone itself: the trimesh exported beside each
## module, so they cannot walk into a wall and do not stop short of one.
## ENEMIES collide with boxes. Measured: with the trimesh for everyone, physics
## at the boss room's edge went from 1.4 ms to between 5 and 13 ms, and the
## boss caught on ragged stone put a 104 ms hitch into the frame. Enemies walk
## the navmesh, so they have no use for centimetre-accurate walls, and the
## boxes are what the navmesh is baked from anyway.
##
## Layer 2 is this project's "blocks sight" layer -- `enemy.gd`'s
## `sight_blocking_mask` and `player.gd`'s `geometry_mask` are both 2 -- and
## the exact walls sit on it, so sight lines are judged against the real
## stone. The first module collision was on layer 1 alone, which let every
## enemy see and aggro straight through every wall in the level.
##
## Layers 9 and 10 are used by nothing else, so the extra mask bits the moving
## bodies carry for them are inert on the older levels.
const LAYER_WORLD := 1 | 2
const LAYER_WALLS_EXACT := 2 | 256     # layer 9: the player's walls
const LAYER_WALLS_SIMPLE := 512        # layer 10: the enemies' walls, and the navmesh's


static func _place_collision(parent: Node3D, out: Built) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "ModuleFloor"
	floor_body.collision_layer = LAYER_WORLD
	parent.add_child(floor_body)

	var exact := StaticBody3D.new()
	exact.name = "ModuleWallsExact"
	exact.collision_layer = LAYER_WALLS_EXACT
	exact.collision_mask = 0
	parent.add_child(exact)

	var simple := StaticBody3D.new()
	simple.name = "ModuleWallsSimple"
	simple.collision_layer = LAYER_WALLS_SIMPLE
	simple.collision_mask = 0
	parent.add_child(simple)

	var half := out.cell_size * 0.5
	var span_x := float(out.size.x) * out.cell_size
	var span_z := float(out.size.y) * out.cell_size
	var mid := out.to_world(Vector2i(0, 0)) + Vector3(
		span_x * 0.5 - half, 0.0, span_z * 0.5 - half)
	# One flat slab under everything. The collision meshes have their floors
	# stripped, so this is the only thing anyone stands on: steady footing over
	# broken paving, and one clean plane for the navmesh.
	_add_box(floor_body, Vector3(span_x, WALL_DEPTH, span_z),
		mid + Vector3(0.0, -WALL_DEPTH * 0.5, 0.0))

	var shapes := _load_collision()
	var fallback := 0
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.court:
			continue
		_add_cell_boxes(simple, out, cell)
		if shapes.has(cell.kind):
			var holder := CollisionShape3D.new()
			holder.shape = shapes[cell.kind]
			holder.transform = Transform3D(_cell_basis(cell), out.to_world(cell.pos))
			exact.add_child(holder)
		else:
			# No exact mesh for this kind: the player gets the boxes too,
			# rather than nothing at all.
			_add_cell_boxes(exact, out, cell)
			fallback += 1
	if fallback > 0:
		push_warning(("module_level: %d cells fell back to box collision -- "
			+ "rebuild the modules to get their *_col.glb") % fallback)
	exact.set_meta("fallback_cells", fallback)


## The old boxes, kept only for a module whose collision mesh is missing.
static func _add_cell_boxes(body: StaticBody3D, out: Built, cell: ModuleMaze.Cell) -> void:
	var half := out.cell_size * 0.5
	var centre := out.to_world(cell.pos)
	var arch: float = ARCH_WIDTH.get(cell.kind, 1.6)
	var face: float = WALL_FACE.get(cell.kind, half)
	if face <= 0.01:
		face = half
	for side in ModuleMaze.ORDER:
		var step: Vector2i = ModuleMaze.DIRS[side]
		var dir := Vector3(float(step.x), 0.0, float(step.y))
		if cell.open & side:
			var across := Vector3(dir.z, 0.0, dir.x)
			var jamb := (out.cell_size - arch) * 0.5
			if jamb > 0.01:
				for s: float in [-1.0, 1.0]:
					var offset: Vector3 = across * (arch * 0.5 + jamb * 0.5) * s
					_add_box(body, _axis_size(dir, JAMB_DEPTH * 2.0, jamb, out.height),
						centre + dir * half + offset + Vector3(0.0, out.height * 0.5, 0.0))
		else:
			# Inner face ON the visible wall face, not on the cell boundary.
			var depth := half - face + WALL_DEPTH
			_add_box(body, _axis_size(dir, depth, out.cell_size, out.height),
				centre + dir * (face + depth * 0.5) + Vector3(0.0, out.height * 0.5, 0.0))


## Builds a box size with `depth` along `dir` and `width` across it.
static func _axis_size(dir: Vector3, depth: float, width: float, height: float) -> Vector3:
	if absf(dir.x) > 0.5:
		return Vector3(depth, height, width)
	return Vector3(width, height, depth)


static func _add_box(body: StaticBody3D, size: Vector3, centre: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var owner_shape := CollisionShape3D.new()
	owner_shape.shape = shape
	owner_shape.position = centre
	body.add_child(owner_shape)


static func _record_gates(out: Built, chosen: Array) -> void:
	out.gates = []
	for p in chosen:
		var cell: ModuleMaze.Cell = out.cells[p]
		if cell.kind != "gate":
			continue
		# The doors face opposite the one open side, which is what `turn`
		# already encodes: north turned by `turn`.
		var open_side: int = ModuleMaze._rotate(ModuleMaze.N, cell.turn)
		var step: Vector2i = ModuleMaze.DIRS[open_side]
		var facing := -Vector3(float(step.x), 0.0, float(step.y))
		out.gates.append({
			"pos": cell.pos,
			"world": out.to_world(cell.pos) + facing * out.cell_size * 0.35,
			"facing": facing,
		})


