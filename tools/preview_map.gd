extends SceneTree

## Verifies `scripts/explore_map.gd` by building the level the way
## `tools/preview_module_level.gd` does, walking a stand-in player through it
## cell by cell, and screenshotting the minimap and full map as more of the
## maze is revealed.
##
##   godot --path . --windowed --script res://tools/preview_map.gd
##
## Windowed, never headless: the map is a CanvasLayer of Controls, and a
## screenshot is the only way to actually see it. This also builds the real
## module level (meshes, collision) exactly like the game does, because the
## point is to exercise `explore_map.gd` against the real `Built` data, not a
## stand-in.

const ModuleMaze = preload("res://scripts/module_maze.gd")
const ModuleLevel = preload("res://scripts/module_level.gd")
const Graph = preload("res://scripts/maze_graph.gd")
const ExploreMap = preload("res://scripts/explore_map.gd")

const SEED := 20260928
const SIZE := Vector2i(33, 33)
const CELL := 6.0
const HEIGHT := 5.1
const VIEW_RANGE := 90.0
const TINT := 1.0
const EYE := 1.65
const SHOTS := "user://team/map"

## How many cells to step through before each checkpoint screenshot.
const STEPS_BEFORE_MINIMAP_SHOT := 6
const STEPS_BEFORE_FULL_SHOT := 10
const STEPS_BEFORE_LATER_SHOT := 40


func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var graph = Graph.new()
	graph.boss_radius = CELL * 3.5
	graph.corridor_radius = 2.2
	graph.cell_radius = 2.3
	graph.boss_doors = 2
	graph.dead_end_spurs = 16
	graph.long_link_count = 1
	graph.generate(SEED, 92.0, 13.0, 6, 7.0, 10.0)
	graph.build_cells(graph.safe_cell_count(1.8))
	graph._build_index()

	var built: ModuleLevel.Built = ModuleLevel.build(
		world, SEED, SIZE, CELL, HEIGHT, VIEW_RANGE, TINT, graph, {})
	print("cells: %d, rooms: %d" % [built.cells.size(), built.rooms.size()])

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	ModuleLevel.configure_environment(env)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)

	var cam := Camera3D.new()
	cam.fov = 78.0
	cam.current = true
	cam.position = built.spawn + Vector3(0.0, EYE, 0.0)
	world.add_child(cam)

	# A stand-in for the real CharacterBody3D player. explore_map.gd only
	# reads `global_position` and `global_basis`, so a bare Node3D is enough.
	var player := Node3D.new()
	player.name = "StandInPlayer"
	player.position = built.spawn
	world.add_child(player)

	var map = ExploreMap.new()
	root.add_child(map)

	# Nodes added during _initialize are not inside the tree yet (the same
	# trap tools/preview_module_level.gd notes for look_at): map's own
	# _ready() has not run, and `player.global_position` cannot be read.
	# Both need at least one process frame to catch up before `setup()`.
	DirAccess.make_dir_recursive_absolute(SHOTS)
	await process_frame
	map.setup(built, player)

	var path := _walk_path(built)
	print("path length: %d cells" % path.size())

	var shot_index := 0
	var total := 0
	for cell_pos in path:
		var world_pos := built.to_world(cell_pos)
		player.position = world_pos
		# Face down whichever open side the cell has, so the marker's arrow
		# visibly turns as the walk goes.
		var cell = built.cells[cell_pos]
		for side in [ModuleMaze.N, ModuleMaze.E, ModuleMaze.S, ModuleMaze.W]:
			if cell.open & side:
				var step: Vector2i = ModuleMaze.DIRS[side]
				player.rotation.y = atan2(-float(step.x), -float(step.y))
				break
		cam.position = world_pos + Vector3(0.0, EYE, 0.0)
		total += 1
		await process_frame
		await process_frame

		if total == STEPS_BEFORE_MINIMAP_SHOT:
			await _shot("%02d_minimap_only" % shot_index)
			shot_index += 1
		if total == STEPS_BEFORE_FULL_SHOT:
			map.set_full_map_open(true)
			await process_frame
			await _shot("%02d_full_map_open" % shot_index)
			shot_index += 1
			map.set_full_map_open(false)
		if total == STEPS_BEFORE_LATER_SHOT:
			map.set_full_map_open(true)
			await process_frame
			await _shot("%02d_full_map_later" % shot_index)
			shot_index += 1
			map.set_full_map_open(false)
			await _shot("%02d_minimap_later" % shot_index)
			shot_index += 1

	# Guarantee a room reveal for the resolution shots below, and give
	# `_rebuild_map_image()` its biggest single batch to cost out: entering a
	# room lands the whole footprint in `_revealed` in one call
	# (`_reveal_room`), not one cell at a time.
	if not built.rooms.is_empty():
		var last: Vector2i = path[path.size() - 1]
		var room: Dictionary = built.rooms[0]
		var room_path := _bfs_path(built, last, room["centre"])
		print("room walk: %d cells to room %s (kind=%s)" % [
			room_path.size(), room["centre"], room["kind"]])
		for cell_pos in room_path:
			var world_pos := built.to_world(cell_pos)
			player.position = world_pos
			cam.position = world_pos + Vector3(0.0, EYE, 0.0)
			await process_frame
			await process_frame
	else:
		push_warning("preview_map: built no rooms, cannot demonstrate a room reveal")

	_check_walls_stay_hidden(built, map)

	# Confirms the full map force-closes the instant the game pauses (the
	# brief's complaint: it used to stay open, frozen, underneath the pause
	# menu). GDScript's underscore convention isn't real privacy, so the
	# harness can read `_full_open` straight off the instance instead of
	# needing a getter added just for this check.
	map.set_full_map_open(true)
	await process_frame
	print("pause check: full map open before pause = %s" % map._full_open)
	# This script extends SceneTree, so it IS the tree -- `paused` directly,
	# not `get_tree().paused` (that accessor only exists on Node).
	paused = true
	await process_frame
	await process_frame
	print("pause check: full map open after pause  = %s" % map._full_open)
	paused = false
	await process_frame
	map.set_full_map_open(false)

	# Crispness check at the resolutions the brief calls out. Windowed and
	# resized here (not via --resolution), so both land in the same run and
	# the same PNG set.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var check_sizes := [Vector2i(1280, 720), Vector2i(3440, 1440)]
	for size in check_sizes:
		DisplayServer.window_set_size(size)
		await process_frame
		await process_frame
		map.set_full_map_open(false)
		await process_frame
		await _shot("res_%dx%d_minimap" % [size.x, size.y])
		map.set_full_map_open(true)
		await process_frame
		await _shot("res_%dx%d_fullmap" % [size.x, size.y])
		map.set_full_map_open(false)

	print("preview written to %s" % ProjectSettings.globalize_path(SHOTS))
	quit()


## Shortest path between two cells over the maze's own connectivity (its
## `open` bitmask), breadth-first. Used to walk the stand-in player straight
## to a room for the resolution shots, rather than hoping the spread-out
## `_walk_path` sample happens to pass through one.
func _bfs_path(built: ModuleLevel.Built, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return [from]
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		if at == to:
			break
		var cell = built.cells[at]
		for side in [ModuleMaze.N, ModuleMaze.E, ModuleMaze.S, ModuleMaze.W]:
			if not (cell.open & side):
				continue
			var nxt: Vector2i = at + ModuleMaze.DIRS[side]
			if not built.cells.has(nxt) or prev.has(nxt):
				continue
			prev[nxt] = at
			queue.append(nxt)
	if not prev.has(to):
		return []
	var path: Array[Vector2i] = [to]
	var cur := to
	while cur != from:
		cur = prev[cur]
		path.append(cur)
	path.reverse()
	return path


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [SHOTS, label]
	img.save_png(path)
	print("shot %s -> %s" % [label, ProjectSettings.globalize_path(path)])


## A long walk from the spawn cell through open connections, breadth-first,
## so it reaches a good spread of corridors, junctions and rooms rather than
## looping over a short stretch.
func _walk_path(built: ModuleLevel.Built) -> Array[Vector2i]:
	var start := Vector2i(
		int(round((built.spawn.x - built.origin.x) / built.cell_size)),
		int(round((built.spawn.z - built.origin.z) / built.cell_size)))

	var order: Array[Vector2i] = [start]
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size() and order.size() < 70:
		var at: Vector2i = queue[head]
		head += 1
		var cell = built.cells[at]
		for side in [ModuleMaze.N, ModuleMaze.E, ModuleMaze.S, ModuleMaze.W]:
			if not (cell.open & side):
				continue
			var to: Vector2i = at + ModuleMaze.DIRS[side]
			if seen.has(to) or not built.cells.has(to):
				continue
			seen[to] = true
			order.append(to)
			queue.append(to)
	return order


## Confirms a cell just beyond a wall from something the walk revealed stays
## hidden, and reports the revealed/total counts.
func _check_walls_stay_hidden(built: ModuleLevel.Built, map) -> void:
	var total := built.cells.size()
	var revealed: int = map.revealed_count()
	var found_example := false
	for key in built.cells:
		if not map.is_cell_revealed(key):
			continue
		var cell = built.cells[key]
		for side in [ModuleMaze.N, ModuleMaze.E, ModuleMaze.S, ModuleMaze.W]:
			if cell.open & side:
				continue
			var neighbour: Vector2i = key + ModuleMaze.DIRS[side]
			if not built.cells.has(neighbour):
				continue
			if map.is_cell_revealed(neighbour):
				continue
			print("adjacent-but-walled cell stays hidden: revealed %s is walled toward %s, which is NOT revealed"
				% [key, neighbour])
			found_example = true
			break
		if found_example:
			break

	print("revealed %d / %d cells (%.1f%%)" % [revealed, total, 100.0 * float(revealed) / float(total)])
	if not found_example:
		push_warning("preview_map: could not find a walled, unrevealed neighbour of a revealed cell to demonstrate")
