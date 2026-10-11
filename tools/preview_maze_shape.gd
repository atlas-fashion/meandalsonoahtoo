extends SceneTree

# Preloaded rather than referenced by class_name: the global class registry is
# populated by a project scan, so a freshly written class_name is not resolvable
# in the same session that created it.
const Contour = preload("res://scripts/wall_contour.gd")

const IMG := 1100


func _initialize() -> void:
	await process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 300:
		await physics_frame

	var maze = main.get_node("Maze")
	var tiles: int = maze.tiles
	var tile_size: float = maze.tile_size
	print("grid: %d x %d tiles, tile_size %.2f m" % [tiles, tiles, tile_size])

	var open_at := func(x: int, z: int) -> bool:
		return maze.is_open(Vector2i(x, z))

	var raw := Contour.trace(open_at, tiles)
	var pts := 0
	for l in raw:
		pts += l.size()
	print("traced %d loops, %d points" % [raw.size(), pts])

	var noise := FastNoiseLite.new()
	noise.seed = 1234
	noise.frequency = 1.0

	print("")
	print("%-40s %10s %10s" % ["setting", "clear m", "verdict"])
	# Half-width from the corridor centreline. The boss capsule is radius 1.2,
	# so anything under that cannot get down the corridor at all; 1.5 leaves it
	# room to turn without grinding.
	var need := 1.5
	var best_cfg := {}
	# Resample FIRST so Chaikin's corner cut is small in absolute terms, then
	# warp the whole plane -- the warp is what removes the cardinal directions.
	for cfg in [
		{"step": 0.25, "passes": 3, "warp": 1.4, "wscale": 0.038},
	]:
		var loops := _build(raw, cfg, noise)
		# Tile centres must be warped by the same field, or this compares the
		# unwarped gameplay grid against warped geometry and means nothing.
		var walk: Array = []
		for z in tiles:
			for x in tiles:
				if open_at.call(x, z):
					walk.append(Contour.warp(Vector2(x + 0.5, z + 0.5), noise,
						cfg["warp"], cfg["wscale"]))
		var gap: float = Contour.clearance(loops, walk, 3) * tile_size
		var ok := gap >= need
		print("%-40s %10.2f %10s" % [
			"chaikin %d, warp %.1f @ %.3f" % [cfg["passes"], cfg["warp"], cfg["wscale"]],
			gap, "ok" if ok else "TIGHT"])
		if ok:
			best_cfg = cfg
	print("(half-width from centreline; boss radius 1.2, want >= %.1f m)" % need)

	if best_cfg.is_empty():
		print("NO SAFE SETTING FOUND")
		quit(1)
		return
	print("")
	print("chosen: chaikin %d, warp %.1f @ %.3f"
		% [best_cfg["passes"], best_cfg["warp"], best_cfg["wscale"]])

	var final_loops := _build(raw, best_cfg, noise)
	_draw(maze, tiles, tile_size, raw, final_loops)
	quit()


func _build(raw: Array, cfg: Dictionary, noise: FastNoiseLite) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for loop in raw:
		var l: PackedVector2Array = loop
		if cfg["step"] > 0.0:
			l = Contour.resample(l, cfg["step"])
		l = Contour.smooth(l, cfg["passes"])
		l = Contour.warp_loop(l, noise, cfg["warp"], cfg["wscale"])
		out.append(l)
	return out


func _draw(maze, tiles: int, tile_size: float, raw: Array, smoothed: Array) -> void:
	var img := Image.create(IMG, IMG, false, Image.FORMAT_RGB8)
	img.fill(Color(0.06, 0.06, 0.08))
	var s := float(IMG) / float(tiles)

	# solid rock
	for z in tiles:
		for x in tiles:
			if maze.is_open(Vector2i(x, z)):
				continue
			var px := int(x * s)
			var pz := int(z * s)
			for dy in range(0, maxi(int(s), 1)):
				for dx in range(0, maxi(int(s), 1)):
					if px + dx < IMG and pz + dy < IMG:
						img.set_pixel(px + dx, pz + dy, Color(0.16, 0.15, 0.17))

	for loop in raw:
		_polyline(img, loop, s, Color(0.55, 0.16, 0.16))
	for loop in smoothed:
		_polyline(img, loop, s, Color(1.0, 0.76, 0.35))

	var path := "user://contour.png"
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _polyline(img: Image, loop: PackedVector2Array, s: float, c: Color) -> void:
	var n := loop.size()
	for i in n:
		var a := loop[i] * s
		var b := loop[(i + 1) % n] * s
		var steps := maxi(int(a.distance_to(b)) + 1, 1)
		for t in steps + 1:
			var p := a.lerp(b, float(t) / float(steps))
			var px := int(p.x)
			var py := int(p.y)
			if px >= 0 and px < IMG and py >= 0 and py < IMG:
				img.set_pixel(px, py, c)

