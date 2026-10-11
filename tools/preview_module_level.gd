extends SceneTree

## Photographs the module level from inside, at eye height.
##
##   godot --path . --windowed --script res://tools/preview_module_level.gd
##
## Windowed, never headless: the dummy renderer cannot produce an image, and
## the point of this tool is the image. It exists because the last three
## versions of this environment were judged by looking at them, not by their
## numbers, and a render is far cheaper than finding out after integration.
##
## It is deliberately lit the way the game is -- dim ambient plus a warm point
## light at the camera, standing in for the hand torch. A preview with studio
## lighting flatters geometry that looks like a cave in the actual game, and
## `CLAUDE.md` already records one wrong conclusion drawn from exactly that.

const ModuleMaze = preload("res://scripts/module_maze.gd")
const ModuleLevel = preload("res://scripts/module_level.gd")

const Graph = preload("res://scripts/maze_graph.gd")

## These mirror the `module_*` exports on `Maze`. Duplicated rather than read
## from the game because this tool builds the level without the game, but they
## DO have to be kept in step: a preview running old numbers shows a level
## that no longer exists, which is worse than having no preview.
const SEED := 20260928
const ORGANIC := true
const EXTENT := 92.0
const SIZE := Vector2i(33, 33)
const CELL := 6.0
const HEIGHT := 5.1
const VIEW_RANGE := 90.0
const TINT := 1.0
const EYE := 1.65
## Team-wave convention: shots go under user://team/level/, never the
## benchmark's user://look_*.png. Overridable with --out=res_relative_path
## for one-off runs.
var SHOTS := "user://team/level/module_preview"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			SHOTS = arg.substr(6)

	var world := Node3D.new()
	root.add_child(world)
	var graph = null
	if ORGANIC:
		graph = Graph.new()
		graph.boss_radius = CELL * 3.5
		graph.corridor_radius = 2.2
		graph.cell_radius = 2.3
		graph.boss_doors = 2
		graph.dead_end_spurs = 16
		graph.long_link_count = 1
		graph.generate(SEED, EXTENT, 13.0, 6, 7.0, 10.0)
		graph.build_cells(graph.safe_cell_count(1.8))
		graph._build_index()

	var built: ModuleLevel.Built = ModuleLevel.build(
		world, SEED, SIZE, CELL, HEIGHT, VIEW_RANGE, TINT, graph, {})
	print("cells: %d, rooms: %d" % [built.cells.size(), built.rooms.size()])

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Not black: a pure black background hides whether anything leaks to the
	# skybox. Magenta makes a hole impossible to miss.
	env.background_color = Color(0.9, 0.0, 0.6)
	# Shared with the game rather than invented here. An earlier version of
	# this tool set its own ambient and its own torch, which is how the
	# previous level ended up with a note in CLAUDE.md about a preview that
	# measured the one configuration in which pixels are cheap.
	ModuleLevel.configure_environment(env)
	# `--flat` floods the level with white ambient and kills the fog, so a
	# hole in the geometry shows the magenta background instead of being one
	# more black patch in an already black corridor. Dark atmosphere and
	# hole-hunting are opposite jobs and one image cannot do both.
	if "--flat" in OS.get_cmdline_user_args():
		env.ambient_light_color = Color(1, 1, 1)
		env.ambient_light_energy = 2.0
		env.fog_enabled = false
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)

	var cam := Camera3D.new()
	cam.fov = 78.0
	cam.current = true
	world.add_child(cam)

	# The wall torches the level places itself, so the shot shows the lighting
	# the player will actually walk through.
	var torches := ModuleLevel.place_torches(world, built)
	print("torches: %d" % int(torches.get_meta("torch_count", 0)))
	var windows := ModuleLevel.place_windows(world, built)
	print("windows: %d" % int(windows.get_meta("window_count", 0)))
	var sky := ModuleLevel.place_room_lights(world, built)
	print("room sky lights: %d" % int(sky.get_meta("light_count", 0)))

	# Plus the hand torch, which is the one light in this game that follows the
	# player and the only one that casts shadows.
	var hand := OmniLight3D.new()
	hand.light_color = ModuleLevel.TORCH_COLOUR
	hand.light_energy = 2.0
	# Kept tight. A wide hand torch floods the corridor evenly and erases the
	# contrast the wall torches are there to create.
	hand.omni_range = 8.5
	hand.omni_attenuation = ModuleLevel.TORCH_ATTENUATION
	hand.light_specular = 0.0
	hand.position = Vector3(0.28, -0.35, 0.0)
	cam.add_child(hand)

	DirAccess.make_dir_recursive_absolute(SHOTS)
	# Nodes added during _initialize are not inside the tree yet, and look_at
	# refuses to run on one. Without this the first shot is aimed wherever the
	# camera happened to start.
	await process_frame

	# Stand in cells of different kinds, looking down a corridor each time,
	# plus one shot at a gate because that is the new feature.
	# The map, drawn rather than photographed. Every module has a roof, so a
	# camera above the level sees a field of lids; the layout is only legible
	# as a plan.
	_draw_map(built)

	var spots := _pick_wall_base_spots(built)
	spots.append_array(_pick_spots(built))
	# Stand back from the first window and look at it, so the shot shows the
	# grate, the red spill on the floor and which way the panel is facing.
	for child in windows.get_children():
		if not (child is Node3D):
			continue
		var face := (child as Node3D).global_transform.basis * Vector3(0, 0, 1)
		# Camera at the PLAYER's own eye height, not the window's -- the
		# acceptance test is what it looks like standing in the corridor,
		# and the window is now at eye height too (task: "visible from eye
		# level"), so the two should very nearly line up.
		var stand: Vector3 = child.position + face * 3.6
		stand.y = EYE
		spots.append({
			"label": "window",
			"at": stand,
			"dir": -face,
		})
		break
	var index := 0
	for spot in spots:
		cam.position = spot["at"]
		cam.look_at(spot["at"] + spot["dir"], Vector3.UP)
		# Two frames: one to move the camera, one drawn with it moved.
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/%02d_%s.png" % [SHOTS, index, spot["label"]]
		img.save_png(path)
		print("shot %s -> %s" % [spot["label"], ProjectSettings.globalize_path(path)])
		index += 1

	print("preview written to %s" % ProjectSettings.globalize_path(SHOTS))
	quit()


## Draws the layout as a plan, for comparing against the reference map.
##
## Each cell becomes a block of pixels, with a bar joining it to each open
## neighbour, so corridors read as corridors rather than as a dotted grid.
func _draw_map(built: ModuleLevel.Built) -> void:
	var step := 14
	var pad := 2
	var w := built.size.x * step
	var img := Image.create(w, built.size.y * step, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.07))

	var floor_col := Color(0.62, 0.58, 0.52)
	for key in built.cells:
		var cell = built.cells[key]
		var ox: int = cell.pos.x * step
		var oy: int = cell.pos.y * step
		img.fill_rect(Rect2i(ox + pad, oy + pad, step - pad * 2, step - pad * 2), floor_col)
		# Bars into each open side, so joined cells form continuous runs.
		if cell.open & 1:
			img.fill_rect(Rect2i(ox + pad, oy - pad, step - pad * 2, pad * 2 + 1), floor_col)
		if cell.open & 4:
			img.fill_rect(Rect2i(ox + pad, oy + step - pad, step - pad * 2, pad * 2), floor_col)
		if cell.open & 8:
			img.fill_rect(Rect2i(ox - pad, oy + pad, pad * 2 + 1, step - pad * 2), floor_col)
		if cell.open & 2:
			img.fill_rect(Rect2i(ox + step - pad, oy + pad, pad * 2, step - pad * 2), floor_col)

	# Rooms: the courtyard in a flat colour over the ring, boss red, chest gold.
	for room in built.rooms:
		var c: Vector2i = room["centre"]
		var h: int = room["half"] - 1
		var col := Color(0.75, 0.32, 0.22) if room["kind"] == "boss" else Color(0.85, 0.7, 0.3)
		img.fill_rect(Rect2i((c.x - h) * step, (c.y - h) * step,
			(h * 2 + 1) * step, (h * 2 + 1) * step), col)

	for gate in built.gates:
		var p: Vector2i = gate["pos"]
		img.fill_rect(Rect2i(p.x * step, p.y * step, step, step),
			Color(0.35, 0.85, 0.45))

	var spawn := built.spawn
	var sx := int(round((spawn.x - built.origin.x) / built.cell_size))
	var sy := int(round((spawn.z - built.origin.z) / built.cell_size))
	img.fill_rect(Rect2i(sx * step, sy * step, step, step), Color(0.35, 0.65, 1.0))

	var path := "%s/map.png" % SHOTS
	img.save_png(path)
	print("map -> %s" % ProjectSettings.globalize_path(path))


## Crouches at the foot of a walled side in each kind of module and stares at
## it, which is where the reported rectangular holes are.
##
## The background is magenta on purpose: anything that opens to the void
## outside the level blazes out instead of reading as one more dark patch in
## an already dark corridor.
func _pick_wall_base_spots(built: ModuleLevel.Built) -> Array[Dictionary]:
	var want := ["straight", "corner", "dead", "tee"]
	var spots: Array[Dictionary] = []
	for kind in want:
		for key in built.cells:
			var cell = built.cells[key]
			if cell.kind != kind:
				continue
			var walled := 0
			for side in [1, 2, 4, 8]:
				if not (cell.open & side):
					walled = side
					break
			if walled == 0:
				break
			var step: Vector2i = ModuleMaze.DIRS[walled]
			var dir := Vector3(float(step.x), 0.0, float(step.y))
			spots.append({
				"label": "base_%s" % kind,
				# Low and backed off, so the whole foot of the wall is in shot.
				"at": built.to_world(cell.pos) - dir * 1.4 + Vector3(0.0, 0.55, 0.0),
				"dir": dir + Vector3(0.0, -0.22, 0.0),
			})
			break
	return spots


func _pick_spots(built: ModuleLevel.Built) -> Array[Dictionary]:
	var want := ["straight", "cross", "tee", "corner", "dead"]
	var spots: Array[Dictionary] = []
	for kind in want:
		for key in built.cells:
			var cell: ModuleMaze.Cell = built.cells[key]
			if cell.kind != kind:
				continue
			# Face an open side, so the shot looks along a corridor rather
			# than into the nearest wall.
			var side: int = ModuleMaze._rotate(ModuleMaze.N, cell.turn)
			var step: Vector2i = ModuleMaze.DIRS[side]
			spots.append({
				"label": kind,
				"at": built.to_world(cell.pos) + Vector3(0.0, EYE, 0.0),
				"dir": Vector3(float(step.x), -0.06, float(step.y)),
			})
			break
	# Each kind of room, from a corner of its courtyard looking across it, so
	# the shot shows the open sky, the arcade round it and the far side.
	for kind in ["boss", "chest"]:
		for room in built.rooms:
			if room["kind"] != kind:
				continue
			var mid: Vector3 = built.room_world(room)
			var back: float = built.court_half_span(room) * 0.8
			spots.append({
				"label": "room_" + kind,
				"at": mid + Vector3(-back, EYE, -back),
				"dir": Vector3(1.0, 0.18, 1.0).normalized(),
			})
			break
	for gate in built.gates:
		var facing: Vector3 = gate["facing"]
		spots.append({
			"label": "gate",
			# Stand back from the doors and look at them.
			"at": built.to_world(gate["pos"]) - facing * 2.2 + Vector3(0.0, EYE, 0.0),
			"dir": facing,
		})
		break
	return spots

