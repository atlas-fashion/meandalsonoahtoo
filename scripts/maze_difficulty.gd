extends RefCounted

## Measures how hard a generated circular maze is to solve, and picks the
## hardest of several candidates.
##
## A big maze is not automatically a hard one. A long solution through a
## corridor with no junctions is just walking. What makes a maze hard is being
## asked to choose, often, with convincing wrong answers -- so that is what
## gets measured.
##
## The score is a heuristic with published weights, not a measurement of human
## difficulty. It needs playtesting to mean anything.


class Report extends RefCounted:
	var seed_value := 0
	## Solution length in cell transitions, and in approximate world metres.
	var path_cells := 0
	var path_metres := 0.0
	## Cells on the solution where more than one way leads onward.
	var decisions := 0
	## Wrong turns available across all those decision points.
	var wrong_turns := 0
	## Size of the largest wrong branch, in cells, and how deep it runs.
	var worst_branch_cells := 0
	var worst_branch_depth := 0
	var mean_branch_cells := 0.0
	## Longest run of corridor with no choice at all.
	var longest_forced := 0
	var dead_ends := 0
	## Solution length over the straight-line distance from entrance to centre.
	var indirectness := 1.0
	## Ring count, used as the yardstick for everything else.
	var rings := 1
	var score := 0.0

	func line() -> String:
		return ("seed %d  path %d cells / %.0f m  decisions %d  wrong turns %d  "
			+ "worst branch %d cells deep %d  forced run %d  dead ends %d  "
			+ "indirect %.2fx  SCORE %.1f") % [
			seed_value, path_cells, path_metres, decisions, wrong_turns,
			worst_branch_cells, worst_branch_depth, longest_forced, dead_ends,
			indirectness, score]


## Weights. Documented because a score whose weights are hidden is not a
## measurement, it is an opinion with a number attached.
##
## Everything is measured against the RING COUNT, not against the path length.
## An earlier version divided each metric by the path length, which rewarded a
## short solution with dense junctions and ranked an 11-cell route above a
## 47-cell one. Rings are the right yardstick: reaching the middle of an
## n-ring maze takes at least n cells, so a route of 4n has genuinely wandered.
const W_ROUTE_LENGTH := 26.0
const W_DECISIONS := 26.0
const W_BRANCH_DEPTH := 20.0
const W_BRANCH_SIZE := 12.0
const W_WRONG_TURNS := 8.0
const W_INDIRECTNESS := 8.0

## What each ratio counts as "as hard as it usefully gets". Beyond these the
## metric stops earning score, so one runaway number cannot dominate.
const FULL_ROUTE := 5.0      # route this many times the minimum
const FULL_DECISIONS := 3.0  # this many choices per ring of depth
const FULL_DEPTH := 4.0      # deepest wrong branch, in rings
const FULL_INDIRECT := 3.0


static func measure(maze) -> Report:
	var r := Report.new()
	r.seed_value = maze.used_seed()
	var path: PackedInt32Array = maze.route(maze.entrance_id, maze.goal_id)
	r.path_cells = path.size()
	if path.size() < 2:
		return r

	var on_path := {}
	for id in path:
		on_path[id] = true

	# World length of the solution, measured through the passage crossings
	# rather than centre to centre -- a straight line between two cell centres
	# in a ring cuts through the wall between them, so it is not the distance
	# anything actually travels.
	var metres := 0.0
	for i in range(path.size() - 1):
		var a: Vector2 = maze.safe_point(path[i])
		var x: Vector2 = maze.crossing(path[i], path[i + 1])
		var b: Vector2 = maze.safe_point(path[i + 1])
		metres += a.distance_to(x) + x.distance_to(b)
	r.path_metres = metres

	var entrance: Vector2 = maze.safe_point(maze.entrance_id)
	r.indirectness = metres / maxf(entrance.length(), 0.001)

	# Decision points and the wrong branches hanging off them.
	var branch_sizes: Array[int] = []
	var forced_run := 0
	for i in path.size():
		var id: int = path[i]
		var offshoots: Array[int] = []
		for nb in maze.cells[id].passages:
			if not on_path.has(nb):
				offshoots.append(nb)
		if offshoots.is_empty():
			forced_run += 1
			r.longest_forced = maxi(r.longest_forced, forced_run)
			continue
		forced_run = 0
		r.decisions += 1
		r.wrong_turns += offshoots.size()
		for nb in offshoots:
			var sized := _subtree(maze, nb, id)
			branch_sizes.append(sized.x)
			r.worst_branch_cells = maxi(r.worst_branch_cells, sized.x)
			r.worst_branch_depth = maxi(r.worst_branch_depth, sized.y)

	if not branch_sizes.is_empty():
		var total := 0
		for b in branch_sizes:
			total += b
		r.mean_branch_cells = float(total) / float(branch_sizes.size())

	for c in maze.cells:
		if c.passages.size() == 1 and c.id != maze.entrance_id:
			r.dead_ends += 1

	r.rings = maze.rings
	r.score = _score(r, maze.cells.size())
	return r


## Picks the outer-ring cell with the hardest route in, and opens it.
##
## This is the spec's "challenging entrance" mode. It matters more than any
## weighting: with a fixed entrance the route length is whatever the tree
## happened to give that spot, and on a 7-ring maze that was 11 cells -- barely
## further than walking straight in. Scoring every outer cell and taking the
## worst one is what actually makes the maze long to solve.
##
## The opening is a hole in the perimeter, not a tree edge, so it cannot create
## a shortcut between cells that were already connected.
static func choose_entrance(maze) -> Report:
	var best_id := -1
	var best: Report = null
	for id in maze.outer_ring():
		maze.entrance_id = id
		var r := measure(maze)
		if best == null or r.score > best.score:
			best = r
			best_id = id
	maze.entrance_id = best_id
	return best


## Size and depth of the off-path subtree reached by stepping from `from` into
## `into`. The maze is a tree, so not walking back through `from` is enough to
## stay inside the branch.
static func _subtree(maze, into: int, from: int) -> Vector2i:
	var size := 0
	var deepest := 0
	var stack: Array[Vector2i] = [Vector2i(into, 1)]
	var came := {from: true}
	while not stack.is_empty():
		var top: Vector2i = stack.pop_back()
		if came.has(top.x):
			continue
		came[top.x] = true
		size += 1
		deepest = maxi(deepest, top.y)
		for nb in maze.cells[top.x].passages:
			if not came.has(nb):
				stack.append(Vector2i(nb, top.y + 1))
	return Vector2i(size, deepest)


## Normalised so the score is comparable between a small maze and a large one.
## Without that, "hardest candidate" would just mean "biggest".
static func _score(r: Report, total_cells: int) -> float:
	if r.path_cells < 2 or total_cells < 2:
		return 0.0
	# Reaching the chamber from the rim costs at least one cell per ring, so
	# that is the floor every other figure is measured against.
	var minimum := maxf(float(r.rings), 1.0)
	var route := float(r.path_cells) / minimum
	var choices := float(r.decisions) / minimum
	var depth := float(r.worst_branch_depth) / minimum
	# Branch size against the average branch a maze this size could offer.
	var size := r.mean_branch_cells / maxf(float(total_cells) / minimum, 1.0)
	var turns := float(r.wrong_turns) / maxf(float(r.decisions), 1.0) - 1.0
	return (W_ROUTE_LENGTH * clampf(route / FULL_ROUTE, 0.0, 1.0)
		+ W_DECISIONS * clampf(choices / FULL_DECISIONS, 0.0, 1.0)
		+ W_BRANCH_DEPTH * clampf(depth / FULL_DEPTH, 0.0, 1.0)
		+ W_BRANCH_SIZE * clampf(size, 0.0, 1.0)
		+ W_WRONG_TURNS * clampf(turns, 0.0, 1.0)
		+ W_INDIRECTNESS * clampf((r.indirectness - 1.0) / FULL_INDIRECT, 0.0, 1.0))


## Generates `count` candidates from a master seed and keeps the best-scoring.
##
## Candidate seeds are derived from the master deterministically, so the whole
## selection reproduces from one number.
##
## This is NOT standard Wilson output. Filtering by score changes which spanning
## trees get chosen, so the result is no longer a uniform random spanning tree.
## Both modes are offered because that difference is real and worth keeping
## visible, not because one is better.
static func pick_hardest(maze_script, config: Dictionary, master_seed: int,
		count: int) -> Dictionary:
	var best = null
	var best_report: Report = null
	var all: Array[Report] = []
	for i in maxi(count, 1):
		var candidate = maze_script.new()
		for key in config:
			candidate.set(key, config[key])
		# Deterministic spread from the master seed. The multiplier is a large
		# odd number so consecutive candidates are not near-neighbours.
		var s := master_seed + i * 2654435761
		if candidate.build(s) != "":
			continue
		var report: Report
		if config.get("entrance_mode", "hardest") == "fixed":
			candidate.set_entrance_at(config.get("entrance_turn", 0.0))
			report = measure(candidate)
		else:
			report = choose_entrance(candidate)
		all.append(report)
		if best_report == null or report.score > best_report.score:
			best = candidate
			best_report = report
	return {"maze": best, "report": best_report, "all": all}
