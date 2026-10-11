extends SceneTree

## Sweeps maze geometry and difficulty, so the settings are chosen from measured
## results rather than from taste.
##
##   godot --headless --path . --script res://tools/tune_circular_maze.gd
##
## "Corridor style" and "hard" pull against each other: long runs with no
## junction feel like corridors, but being made to choose is what makes a maze
## hard. Both are reported so the trade is visible instead of implied.

const Maze = preload("res://scripts/circular_maze.gd")
const Difficulty = preload("res://scripts/maze_difficulty.gd")
const IMG := 1100

const CANDIDATES := 12
const MASTER_SEED := 20260925


func _initialize() -> void:
	var configs := [
		{"name": "current (roomy)", "rings": 7, "chamber_radius": 9.0,
			"ring_depth": 5.0, "target_cell_width": 7.0, "agent_clearance": 1.4},
		{"name": "longer, same width", "rings": 11, "chamber_radius": 9.0,
			"ring_depth": 5.0, "target_cell_width": 7.0, "agent_clearance": 1.4},
		{"name": "corridor, boss clearance", "rings": 11, "chamber_radius": 10.0,
			"ring_depth": 4.0, "target_cell_width": 5.0, "agent_clearance": 1.4},
		{"name": "tight, boss clearance", "rings": 13, "chamber_radius": 11.0,
			"ring_depth": 3.8, "target_cell_width": 4.5, "agent_clearance": 1.4},
		# Dropping clearance to skeleton size (capsule radius 0.35) is what
		# actually unlocks narrow corridors. The Warden then cannot follow into
		# the maze -- he is an arena boss, so that may be fine, but it is a
		# design decision and not a free win.
		{"name": "corridor, skeleton clearance", "rings": 14, "chamber_radius": 9.0,
			"ring_depth": 2.6, "target_cell_width": 3.2, "agent_clearance": 0.7},
		{"name": "tightest, skeleton clearance", "rings": 17, "chamber_radius": 8.0,
			"ring_depth": 2.2, "target_cell_width": 2.6, "agent_clearance": 0.7},
		# Deliberately impossible, to show the refusal is real.
		{"name": "impossible (should refuse)", "rings": 10, "chamber_radius": 3.0,
			"ring_depth": 1.5, "target_cell_width": 3.0, "agent_clearance": 1.4},
	]

	print("%-30s %6s %7s %7s %6s %6s %7s %6s" % [
		"config", "cells", "path", "metres", "choic", "cells/", "forced", "SCORE"])
	print("%-30s %6s %7s %7s %6s %6s %7s %6s" % [
		"", "", "cells", "", "pts", "choice", "run", ""])

	var best_name := ""
	var best_score := -1.0
	var best_pack = null

	for cfg: Dictionary in configs:
		var name: String = cfg["name"]
		var build_cfg: Dictionary = cfg.duplicate()
		build_cfg.erase("name")

		var probe = Maze.new()
		for k in build_cfg:
			probe.set(k, build_cfg[k])
		var refusal: String = probe.validate()
		if refusal != "":
			print("%-30s  REFUSED: %s" % [name, refusal.substr(0, 78)])
			continue

		var pack: Dictionary = Difficulty.pick_hardest(
			Maze, build_cfg, MASTER_SEED, CANDIDATES)
		var r = pack["report"]
		var m = pack["maze"]
		if r == null:
			print("%-30s  no candidate built" % name)
			continue
		var per_choice := float(r.path_cells) / maxf(float(r.decisions), 1.0)
		print("%-30s %6d %7d %7.0f %6d %6.1f %7d %6.1f" % [
			name, m.cells.size(), r.path_cells, r.path_metres, r.decisions,
			per_choice, r.longest_forced, r.score])
		if r.score > best_score:
			best_score = r.score
			best_name = name
			best_pack = pack

	if best_pack == null:
		print("nothing built")
		quit(1)
		return

	print("")
	print("hardest config: %s" % best_name)
	var best_report = best_pack["report"]
	print("  %s" % best_report.line())
	print("")
	print("candidate spread from master seed %d:" % MASTER_SEED)
	var scores: Array[float] = []
	for rep in best_pack["all"]:
		scores.append(rep.score)
	scores.sort()
	print("  %d candidates, scores %.1f .. %.1f (median %.1f)" % [
		scores.size(), scores[0], scores[scores.size() - 1],
		scores[scores.size() / 2]])
	print("  selection is NOT uniform Wilson output -- filtering by score")
	print("  changes which spanning trees get chosen.")

	_draw(best_pack["maze"], best_report)
	quit()


func _draw(m, report) -> void:
	var img := Image.create(IMG, IMG, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.07))
	var extent: float = m.chamber_radius + m.ring_depth * m.rings + 2.0
	var s := float(IMG) * 0.5 / extent
	var mid := Vector2(IMG, IMG) * 0.5

	var drawn := {}
	for c in m.cells:
		for nb in c.neighbours:
			var key := Vector2i(mini(c.id, nb), maxi(c.id, nb))
			if drawn.has(key):
				continue
			drawn[key] = true
			if c.passages.has(nb):
				continue
			var o = m.cells[nb]
			if c.ring == o.ring:
				var shared: float = c.a1 if absf(c.a1 - o.a0) < 1e-9 else c.a0
				var ang := shared * TAU
				var d := Vector2(cos(ang), sin(ang))
				_line(img, mid + d * c.r_inner * s, mid + d * c.r_outer * s,
					Color(0.82, 0.80, 0.74))
			else:
				var inner = c if c.ring < o.ring else o
				var outer = o if c.ring < o.ring else c
				_arc(img, mid, outer.r_inner * s,
					maxf(inner.a0, outer.a0), minf(inner.a1, outer.a1),
					Color(0.82, 0.80, 0.74))

	for id in m.outer_ring():
		if id == m.entrance_id:
			continue
		var c = m.cells[id]
		_arc(img, mid, c.r_outer * s, c.a0, c.a1, Color(0.85, 0.58, 0.32))

	var path: PackedInt32Array = m.route(m.entrance_id, m.goal_id)
	for i in range(path.size() - 1):
		var a: Vector2 = m.safe_point(path[i])
		var x: Vector2 = m.crossing(path[i], path[i + 1])
		var b: Vector2 = m.safe_point(path[i + 1])
		_line(img, mid + a * s, mid + x * s, Color(0.30, 0.95, 0.45))
		_line(img, mid + x * s, mid + b * s, Color(0.30, 0.95, 0.45))

	var out := "user://circular_tuned.png"
	img.save_png(out)
	print("wrote %s" % ProjectSettings.globalize_path(out))


func _arc(img: Image, mid: Vector2, r: float, t0: float, t1: float, c: Color) -> void:
	var steps := maxi(int((t1 - t0) * TAU * r), 2)
	var prev := Vector2.ZERO
	for i in steps + 1:
		var t: float = lerpf(t0, t1, float(i) / float(steps)) * TAU
		var p := mid + Vector2(cos(t), sin(t)) * r
		if i > 0:
			_line(img, prev, p, c)
		prev = p


func _line(img: Image, a: Vector2, b: Vector2, c: Color) -> void:
	var steps := maxi(int(a.distance_to(b)) + 1, 1)
	for t in steps + 1:
		var p := a.lerp(b, float(t) / float(steps))
		var px := int(p.x)
		var py := int(p.y)
		if px >= 0 and px < IMG and py >= 0 and py < IMG:
			img.set_pixel(px, py, c)
