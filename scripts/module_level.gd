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
const BrickLevel := preload("res://scripts/brick_level.gd")

## Build the stone from the brick kit (scripts/brick_level.gd, 2026-10-10)
## instead of one Tripo tunnel module per cell. Same layout either way. Set by
## maze.gd from its `brick_kit` export before `build`.
static var brick := true

## The wall face's distance from a cell's centre, whichever stone is built.
static func wall_face(kind: String) -> float:
	if brick:
		return 0.0 if kind == "cross" else BrickLevel.WALL_FACE
	return WALL_FACE.get(kind, 0.0)

const KINDS :=["straight", "corner", "tee", "cross", "dead", "gate"]

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
## See its use in `_synth_material`: a small brightness lift so the floor
## slab (mean 0.122 before this) sits closer to the surrounding floor's own
## texture (mean 0.176) where a broken-paving dip exposes it.
const SYNTH_LIFT := 1.25

## `tools/build_modules.py` tags the boolean cutter's own faces -- the
## soffit and reveals of every bored archway, and ONLY those -- with this
## material, separately from SYNTH_MATERIAL (which still covers the lid and
## floor slab). Direction ruling: retexture the arches alone, with a plain
## stone, no brick courses or mortar, noticeably darker than the Tripo wall
## stone. Generated procedurally (Fourier-synthesis noise, exactly tileable)
## into textures/stone_plain_*.png -- see the harness that made it.
const ARCH_MATERIAL := "synth_arch"
const ARCH_ALBEDO := "res://textures/stone_plain_albedo.png"
const ARCH_NORMAL := "res://textures/stone_plain_normal.png"
## Measured: mean albedo ~0.115 vs the Tripo wall stone's 0.176 -- noticeably
## darker.
## 1.0, not 0.35: at 0.35 the texture repeated every ~2.9 m and its grain
## landed far too large, reading as soft cloud noise rather than stone
## (independent visual review). At 1.0 the same pixel content tiles every
## metre, which is what puts the regenerated texture's grain at true
## centimetre scale (see the harness that made it).
const ARCH_SCALE := 1.0

## The courtyard paving. Open to the sky, so it is deliberately a different
## surface from the corridor floors -- an outdoor court, not more corridor.
const COURT_ALBEDO := "res://textures/ground_albedo.png"
const COURT_NORMAL := "res://textures/ground_normal.png"
const COURT_SCALE := 0.22
const COURT_DEPTH := 0.6
## The court slab's top used to sit at y = 0, exactly flush with the arcade
## module floors it meets -- two different meshes claiming the same plane,
## which is one of the spots that phased ("textures phase through one
## another"). Recessed a hair below instead: invisible at the seam, and the
## slab has depth so nothing shows through underneath.
const COURT_Y_OFFSET := -0.02

## --- Atmosphere -------------------------------------------------------------
##
## Torchlight falls off physically (attenuation 1.0, since 2026-10-12): a pool
## round each torch, the stretch between them down to the base light. The
## earlier soft falloff (0.4) also carried light 20 m through stone.
## Fire orange. The earlier (1.0, 0.76, 0.50) read as a pale lamp. Orange has
## ~18% less luminance, which Maze.module_torch_energy makes back up.
const TORCH_COLOUR := Color(1.0, 0.5, 0.2)
const TORCH_ENERGY := 10.0
## 20 m / 0.4 from 2026-10-10 (wide soft pools); 14 m / 1.0 since 2026-10-12
## (darker, realistic). At 1.0 a torch adds little past ~12 m: 14 vs 20 m lost
## 10-25% between torches, and won 73.1 -> 79.4 fps (CLAUDE.md section 34).
const TORCH_RANGE := 14.0
const TORCH_ATTENUATION := 1.0
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

## Ambient is a floor on visibility, not a light source, and costs nothing.
## Only faintly cool: at (0.16, 0.175, 0.225) the dark read blue, and blue
## ambient under the orange fire turned near walls magenta.
const AMBIENT_COLOUR := Color(0.17, 0.175, 0.19)
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
const WINDOW_EVERY := 11
const WINDOW_COLOUR := Color(1.0, 0.13, 0.06)
## Strong, because most of what a light behind stone and a grate emits never
## reaches the corridor.
const WINDOW_ENERGY := 7.0
const WINDOW_RANGE := 8.5
## Metres above the floor, not a fraction of module height any more. The
## previous 0.52 * height put the panel at ~2.65 m -- above the player's
## camera and never actually seen -- against the ~1.6 m eye height it needs
## to be visible at.
const WINDOW_EYE_HEIGHT := 1.6
## The glowing opening, its stone frame and its bars. Emission comes from a
## radial gradient multiplied by this energy: bright enough at the centre to
## bloom a little, and dull red at the edge where the frame meets it.
const WINDOW_OPENING := Vector2(0.8, 1.2)
const WINDOW_FRAME := 0.16
const WINDOW_FRAME_DEPTH := 0.34
const WINDOW_BARS := 3
const WINDOW_GLOW_ENERGY := 1.6

## Thickness of the rock slab placed behind walls that face the outside.
const BACKING_DEPTH := 1.0
## Pulled inward from the cell boundary by this much, so its inner face sits
## a hair inside where the wall stone nominally ends rather than exactly on
## the boundary plane. A wall that happens to reach exactly to the boundary
## would otherwise be coplanar with backing's inner face and the two would
## z-fight (task: "textures phase through one another"). Moving inward only
## ever makes the backing catch a stray sightline EARLIER, so it cannot
## reopen the gaps it exists to close.
const BACKING_INSET := 0.03

## Thickness of the filler placed on the shared boundary between two
## neighbouring cells -- both where the join is a solid wall and, as a jamb
## either side of an open archway. It plugs the gap regardless of which
## side's ragged Tripo stone falls short of it.
##
## Neighbouring modules abut with no seam to fall through IN THEORY -- see
## the axis note in tools/build_modules.py -- but that only guarantees the
## CELL is exactly CELL_SIZE wide; it says nothing about whether the ragged
## Tripo stone inside actually reaches that boundary on both sides. Measured
## with a ray probe along cell boundaries (tools/team_level_seam_probe.py):
## before this fix, rays cast along the shared plane between adjacent solid
## walls and along archway jambs escaped through both pieces at once.
##
## Centred on the boundary, and much thinner than the first attempt (0.6 m).
## An asymmetric, outward-only filler was tried first -- reasoning that
## "moving away from the room can only help", the same principle
## `BACKING_INSET` uses for the rim -- but that reasoning only holds where
## there is one room to worry about. On an INTERIOR seam there are two, one
## on each side, and "outward" from the canonical (lower-ordered) cell is
## "into the room" from the other cell's own side of the exact same pair: a
## visibility probe (tools/team_level_visibility_probe.gd) still found the
## filler as the first-hit surface at similar rates after that change, just
## from the other side. Piers are not a uniform column on EITHER side, so
## the only depth that is safe from both is a thin one: enough to guarantee
## the escape-probe still crosses solid ground at the boundary plane (kept
## passing at 0/27028 -- the ray only needs to find SOMETHING anywhere along
## its path, so shrinking depth costs it nothing), small enough that either
## side's real pier stone -- whatever its actual thickness turns out to be
## -- has a much better chance of fully enclosing it.
const SEAM_FILL_DEPTH := 0.6
const JAMB_FILL_DEPTH := 0.1
## A per-sample-position escape probe (tools/team_level_gap_height.gd, no
## filler, raw module stone) found the real crack is NOT spread across the
## whole nominal jamb width: sampling five lateral positions from the
## archway's edge out to the cell boundary, the innermost four were solid
## (0% escaped) and only the outermost -- within ~0.06-0.3 m of the true cell
## boundary -- escaped, at ~80%. That is the two modules' piers not quite
## meeting at the seam, exactly as narrow as the name suggests. The filler
## that plugs it only needs to be this wide, hugging the boundary corner,
## not the full archway-edge-to-boundary panel the first version built --
## which is what independent visual review saw standing proud as a wide
## strip beside every archway.
const JAMB_FILL_WIDTH := 0.35
## The plain wall seam keeps a small outward bias: unlike a jamb, WALL_FACE
## says solid stone is thick well before the boundary on a plain wall (1.90
## to 2.79 m, against a 3.0 m boundary), so a tiny lip past it stays hidden.
const WALL_SEAM_INSET := 0.02
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
	## The way the player faces at the spawn: at the door that shuts them in.
	var spawn_yaw := 0.0
	## The spawn's dead end and the side its one exit is on: `place_doors`
	## always hangs a door there. {} when the spawn is not in a dead end.
	var spawn_door := {}
	var gates: Array[Dictionary]   ## {pos: Vector2i, world: Vector3, facing: Vector3}
	## {kind: "boss"|"chest", centre: Vector2i, half: int,
	##  entrances: [{cell: Vector2i, side: int}]}
	var rooms: Array[Dictionary] = []
	## Cells that already carry a torch, so a window does not land on top of
	## one. Filled by `place_torches`, read by `place_windows`.
	var torch_cells := {}
	## Straight cells built with the skylight variant of the module.
	var skylights := {}
	## Straight cells built with a bone-cage niche: pos -> {flip, dir}.
	var niches := {}
	## The boss hall's plan (`plan_boss_hall`): the stair up from the boss
	## room's one doorway and the hall above the corridor roofs. {} without a
	## boss room.
	var boss_hall := {}
	## Wooden doors: {cell: Vector2i, other: Vector2i, dir: Vector3}, where the
	## door stands in `cell`'s archway facing `dir`, towards `other`. Filled by
	## `place_doors`, read by `place_torches` to flank each one.
	var doors: Array[Dictionary] = []

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
	## Cells of maze kept between room blocks at the least, and the most
	## doorways a chest room keeps (0 = every corridor that ran into it).
	"room_gap": 1,
	"room_entrances": 0,
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
			int(opt["boss_half"]), int(opt["chest_half"]), int(opt["chest_rooms"]),
			int(opt["room_gap"]), int(opt["room_entrances"]))
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

	# Planned before the skylights, which must not open onto its underside.
	out.boss_hall = plan_boss_hall(out)
	if brick:
		# The kit always has its skylight vault and niche wall.
		var have := {SKYLIGHT_KIND: true, NICHE_KIND: true}
		_pick_skylights(out, have)
		_pick_niches(out, have)
		BrickLevel.build(parent, out, view_range, tint)
		_place_courts(parent, out, tint, true)
	else:
		var meshes := _load_meshes(tint)
		_pick_skylights(out, meshes)
		_pick_niches(out, meshes)
		_place_meshes(parent, out, meshes, view_range)
		_place_arch_liners(parent, out, tint)
		_place_courts(parent, out, tint)
		_place_backing(parent, out, tint)
		_place_collision(parent, out)
	_record_gates(out, chosen)
	out.spawn = _pick_spawn(out) + Vector3(0.0, 0.2, 0.0)
	return out


## The player starts at the END of the maze, shut in: the dead end furthest
## from EVERY room (by walking distance to the nearest one, boss room included;
## the boss's own distance breaks ties) whose one exit opens onto a corridor.
## It used to be furthest from the boss alone, which could put the start two
## cells from a chest room (2026-10-09). `place_doors` hangs a door across that
## exit, and the player stands back from it, facing it, so the first thing they
## do is kick it in. Without such a dead end, the old rule: the furthest
## through-corridor.
static func _pick_spawn(out: Built) -> Vector3:
	var fallback := _furthest_corridor(out)
	var depth: Dictionary = out.get_meta("spawn_depth", {})
	var near := _room_depth(out)
	# Far from the rooms both ways: a long walk round to a room whose wall is
	# just through the rock still feels like starting next door. Corridors wind
	# to about three times the straight line, hence the 3.
	var score := func(key: Vector2i) -> float:
		var straight := INF
		for room in out.rooms:
			var c: Vector2i = room["centre"]
			var h: int = room["half"]
			straight = minf(straight, float(maxi(maxi(absi(key.x - c.x), absi(key.y - c.y)) - h, 0)))
		return minf(float(near.get(key, 0)), straight * 3.0) * 1000.0 + float(depth[key])
	var best := Vector2i(-1, -1)
	var best_side := 0
	for key in depth:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.room >= 0 or cell.court or cell.kind != "dead":
			continue
		var exits := 0
		var exit_side := 0
		for side in ModuleMaze.ORDER:
			if cell.open & side:
				exits += 1
				exit_side = side
		if exits != 1:
			continue
		var other = out.cells.get(key + ModuleMaze.DIRS[exit_side])
		if other == null or other.court or other.room >= 0:
			continue
		if best.x < 0 or score.call(key) > score.call(best):
			best = key
			best_side = exit_side
	if best.x < 0:
		return fallback
	var step: Vector2i = ModuleMaze.DIRS[best_side]
	var dir := Vector3(float(step.x), 0.0, float(step.y))
	out.spawn_door = {"cell": best, "side": best_side}
	# Forward (-Z) along the way out, at the door.
	out.spawn_yaw = atan2(-dir.x, -dir.z)
	# Back from the middle of the cell, so the door fills the view without
	# being in the player's face.
	# The brick kit's door hangs in the arch 2.38 m out, so the player stands a
	# little forward of the middle to have it within reach.
	return out.to_world(best) - dir * (BRICK_SPAWN_BACK if brick else SPAWN_BACK)


## --- The boss hall's plan -------------------------------------------------------
##
## The boss room is no longer a cloister on the corridors' level. From its one
## doorway a walled stair climbs straight in, in two flights with a landing,
## to HALL_FLOOR_Y -- above the 5.1 m corridor roofs -- and the hall at the top
## is free of the 6 m grid: it reaches out over the corridors round the room as
## far as it can without roofing a chest room's open court or leaving the map.
## Everything is laid out in the stair's own frame: `u` across it, `v` from the
## doorway inward (`into`), `y` up. boss_hall.gd builds it from this plan.

const HALL_FLOOR_Y := 7.0
const STAIR_WIDTH := 8.0
## Per flight. 18 x 2 risers of 0.194 m on 0.42 m treads: about 25 degrees,
## easy for the player's capsule and inside the navmesh's 45 degree limit.
const STAIR_STEPS := 18
const STAIR_TREAD := 0.42
## Flat floor in from the doorway before the first step.
const STAIR_LEAD := 1.0
const STAIR_LANDING := 3.0
const HALL_WALL := 1.6
## Largest and smallest hall, (across, deep), in metres.
const HALL_MAX := Vector2(40.0, 48.0)
const HALL_MIN := Vector2(26.0, 30.0)


static func plan_boss_hall(out: Built) -> Dictionary:
	var boss := out.boss_room()
	if boss.is_empty() or (boss["entrances"] as Array).is_empty():
		return {}
	var way: Dictionary = boss["entrances"][0]
	var step: Vector2i = ModuleMaze.DIRS[int(way["side"])]
	var into := -Vector3(float(step.x), 0.0, float(step.y))
	var flight := float(STAIR_STEPS) * STAIR_TREAD
	var top := STAIR_LEAD + flight * 2.0 + STAIR_LANDING
	var plan := {
		# Where the doorway meets the room's block, on the stair's centre line.
		"door": out.to_world(way["cell"]) - into * out.cell_size * 0.5,
		"door_cell": way["cell"],
		"into": into,
		"across": Vector3.UP.cross(into),
		"floor_y": HALL_FLOOR_Y,
		"stair_width": STAIR_WIDTH,
		"steps": STAIR_STEPS,
		"tread": STAIR_TREAD,
		"rise": HALL_FLOOR_Y / float(STAIR_STEPS * 2),
		"lead": STAIR_LEAD,
		"landing": STAIR_LANDING,
		"top": top,
		"wall": HALL_WALL,
	}
	# The largest hall that fits: deepest first, then widest.
	var best := Vector2.ZERO
	var d := HALL_MAX.y
	while d >= HALL_MIN.y - 0.01 and best == Vector2.ZERO:
		var w := HALL_MAX.x
		while w >= HALL_MIN.x - 0.01:
			plan["width"] = w
			plan["depth"] = d
			if _hall_fits(out, plan):
				best = Vector2(w, d)
				break
			w -= 2.0
		d -= 3.0
	if best == Vector2.ZERO:
		push_warning("module_level: no clear ground for the boss hall; building the smallest")
		best = HALL_MIN
	plan["width"] = best.x
	plan["depth"] = best.y
	plan["centre"] = plan["door"] + into * (top + best.y * 0.5) + Vector3.UP * HALL_FLOOR_Y
	return plan


## The hall's footprint on the ground plane, walls included (x, z).
static func hall_rect(plan: Dictionary) -> Rect2:
	var door: Vector3 = plan["door"]
	var into: Vector3 = plan["into"]
	var across: Vector3 = plan["across"]
	var half_w: float = float(plan["width"]) * 0.5 + float(plan["wall"])
	var v0: float = plan["top"]
	var v1: float = v0 + float(plan["depth"]) + float(plan["wall"])
	var r := Rect2(Vector2(door.x, door.z), Vector2.ZERO)
	for u: float in [-half_w, half_w]:
		for v: float in [v0, v1]:
			var p := door + across * u + into * v
			r = r.expand(Vector2(p.x, p.z))
	return r


static func _hall_fits(out: Built, plan: Dictionary) -> bool:
	var r := hall_rect(plan)
	var lo := out.origin - Vector3(1.0, 0.0, 1.0) * out.cell_size * 0.5
	var hi := out.origin + Vector3(float(out.size.x) - 0.5, 0.0, float(out.size.y) - 0.5) * out.cell_size
	if r.position.x < lo.x or r.position.y < lo.z or r.end.x > hi.x or r.end.y > hi.z:
		return false
	for room in out.rooms:
		if room["kind"] == "boss":
			continue
		# A chest room's COURT is open to the sky and must stay so; its arcade
		# is roofed at the corridors' height, so the hall may stand over that.
		var mid: Vector3 = out.room_world(room)
		var half: float = out.court_half_span(room) + 2.0
		if r.intersects(Rect2(mid.x - half, mid.z - half, half * 2.0, half * 2.0)):
			return false
	return true


## True when `world` lies under the boss hall (on the ground plane).
static func under_boss_hall(out: Built, world: Vector3, margin := 0.0) -> bool:
	if out.boss_hall.is_empty():
		return false
	return hall_rect(out.boss_hall).grow(margin).has_point(Vector2(world.x, world.z))


## How far behind the dead end's centre the player stands, away from its door.
## 0.7 + the door's 1.38 m from a dead end's centre puts it 2.08 m away: the
## whole gate in view, and within the door's 2.4 m reach.
const SPAWN_BACK := 0.7
## The brick door's node is at the leaf, 2.96 m out: the player starts 0.75 m
## toward it, 2.2 m off, within its 2.4 m reach.
const BRICK_SPAWN_BACK := -0.75


## Furthest corridor cell from the boss, by walking distance through the maze,
## preferring a through-corridor over a dead end. Leaves every cell's walking
## depth on `out` as meta "spawn_depth".
static func _furthest_corridor(out: Built) -> Vector3:
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
	out.set_meta("spawn_depth", depth)
	return out.to_world(furthest)


## Walking distance, in cells, from every cell to the nearest room's block.
static func _room_depth(out: Built) -> Dictionary:
	var depth := {}
	var queue: Array[Vector2i] = []
	for key in out.cells:
		if (out.cells[key] as ModuleMaze.Cell).room >= 0:
			depth[key] = 0
			queue.append(key)
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		var here: ModuleMaze.Cell = out.cells[at]
		for side in ModuleMaze.ORDER:
			if not (here.open & side):
				continue
			var to: Vector2i = at + ModuleMaze.DIRS[side]
			if out.cells.has(to) and not depth.has(to):
				depth[to] = depth[at] + 1
				queue.append(to)
	return depth


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
	# Optional: without it the level simply has no skylights.
	for extra in [SKYLIGHT_KIND, NICHE_KIND]:
		var variant := _first_mesh("res://models/kit/module_%s.glb" % extra)
		if variant != null:
			_fix_material(variant, tint)
			meshes[extra] = variant
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
static var _synth_arch: StandardMaterial3D = null


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
	# Tripo materials do, plus a small extra lift (SYNTH_LIFT): this material
	# also covers the floor slab that shows through low dips in a module's
	# own broken-paving floor (measured ~9% of floor area on module_tee), and
	# at the bare tint multiply it read as a visibly darker, flatter patch
	# against the floor's own texture (mean 0.176) rather than blending in.
	m.albedo_color = Color(tint * STONE_CAST.r * SYNTH_LIFT, tint * STONE_CAST.g * SYNTH_LIFT,
		tint * STONE_CAST.b * SYNTH_LIFT)
	m.metallic = 0.0
	m.roughness = 0.96
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Both sides. The booleans that bored the archways leave a fringe of faces
	# wound the wrong way round each opening; culled, they were see-through
	# triangles showing the stone behind. Drawn from both sides they are solid.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	_synth = m
	return m


## The arch's own plain, darker stone -- see ARCH_MATERIAL above. Separate
## resource from `_synth_material` so lids and floor slabs are untouched.
static func _synth_arch_material(tint: float) -> StandardMaterial3D:
	if _synth_arch != null:
		return _synth_arch
	var m := StandardMaterial3D.new()
	m.resource_name = ARCH_MATERIAL
	m.albedo_texture = load(ARCH_ALBEDO)
	m.normal_enabled = true
	m.normal_texture = load(ARCH_NORMAL)
	m.normal_scale = 1.4
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(ARCH_SCALE, ARCH_SCALE, ARCH_SCALE)
	# The texture is already darker than the wall stone on its own; the same
	# cool multiply the rest of the level's stone gets keeps it from reading
	# as a different material family under torchlight.
	m.albedo_color = Color(tint * STONE_CAST.r, tint * STONE_CAST.g, tint * STONE_CAST.b)
	m.metallic = 0.0
	m.roughness = 0.97
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	_synth_arch = m
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
		if mat != null and mat.resource_name == ARCH_MATERIAL:
			mesh.surface_set_material(i, _synth_arch_material(tint))
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
			# Tripo stone stays one-sided; the arch linings cover the torn soffits,
			# and only the invented stone (arch reveals, fillers) is double-sided.
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
		var kind := SKYLIGHT_KIND if out.skylights.has(cell.pos) else cell.kind
		if out.niches.has(cell.pos):
			kind = NICHE_KIND
		var bucket_key := "%d_%d_%s" % [chunk.x, chunk.y, kind]
		if not buckets.has(bucket_key):
			buckets[bucket_key] = {"chunk": chunk, "kind": kind, "cells": []}
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
			var basis := _cell_basis(cell)
			# The niche piece is turned half round when its niche is wanted on
			# the other wall; a straight is the same corridor either way.
			if out.niches.has(cell.pos) and out.niches[cell.pos]["flip"]:
				basis = basis * Basis(Vector3.UP, PI)
			mm.set_instance_transform(i, Transform3D(basis, out.to_world(cell.pos) - chunk_origin))
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


## --- Archway linings ----------------------------------------------------------
##
## The junction pieces' archways were bored by a boolean (`widen_passages` in
## `build_modules.py`), and the underside it made is torn: a fringe of floating
## shards with gaps between them, through which the stone behind shows -- the
## "see-through triangles". Drawing the stone double-sided fixed only the faces
## that were merely wound backwards; the rest is simply missing. So every bored
## archway gets a clean lining here, the cutter's own shape (square jambs up to
## the springing, a round head), set a hair inside the cut so it hides it.
## The measurements match the cutter and the probe of the court arches: 3.6 m
## wide, springing 2.0 m above a 0.02 m base, crown 3.82 m; the arch's passage
## runs from ~2.3 m out from the cell centre to the cell's edge.
const ARCH_LINER_RADIUS := 1.785
const ARCH_LINER_SPRING := 2.02
const ARCH_LINER_BASE := 0.02
const ARCH_LINER_FROM := 2.25
const ARCH_LINER_TO := 3.02
## Kinds whose open sides were bored. The straight's archways are Tripo's own,
## and the gate is a separate piece.
const BORED_KINDS := ["cross", "tee", "corner", "dead"]


static func _arch_liner_mesh() -> ArrayMesh:
	var profile: Array[Vector2] = [Vector2(-ARCH_LINER_RADIUS, ARCH_LINER_BASE)]
	var steps := 16
	for i in steps + 1:
		var a := PI - PI * float(i) / float(steps)
		profile.append(Vector2(cos(a), sin(a)) * ARCH_LINER_RADIUS + Vector2(0.0, ARCH_LINER_SPRING))
	profile.append(Vector2(ARCH_LINER_RADIUS, ARCH_LINER_BASE))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Along local -Z, from the inner end of the passage out to the cell edge;
	# the normals face in, towards the middle of the opening.
	var z0 := -ARCH_LINER_FROM
	var z1 := -ARCH_LINER_TO
	for i in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		var mid := (a + b) * 0.5
		var inward := Vector3(-mid.x, ARCH_LINER_SPRING - mid.y if mid.y > ARCH_LINER_SPRING else 0.0, 0.0)
		if inward.length() < 1e-4:
			inward = Vector3(0.0, -1.0, 0.0)
		st.set_normal(inward.normalized())
		for p in [Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1),
				Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)]:
			st.add_vertex(p)
	return st.commit()


static func _place_arch_liners(parent: Node3D, out: Built, tint: float) -> void:
	var transforms: Array[Transform3D] = []
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.court or not (cell.kind in BORED_KINDS):
			continue
		for side in ModuleMaze.ORDER:
			if not (cell.open & side):
				continue
			var step: Vector2i = ModuleMaze.DIRS[side]
			var dir := Vector3(float(step.x), 0.0, float(step.y))
			transforms.append(Transform3D(
				Basis(Vector3.UP, atan2(-dir.x, -dir.z)), out.to_world(cell.pos)))
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _arch_liner_mesh()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ArchLinings"
	mmi.multimesh = mm
	var mat := _synth_arch_material(tint).duplicate() as StandardMaterial3D
	# No vertex colours on this mesh.
	mat.vertex_color_use_as_albedo = false
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	mmi.set_meta("liner_count", transforms.size())


## --- Wooden doors ---------------------------------------------------------------
##
## Old dark wooden double doors in some corridor archways. They fill the bored
## junction arches exactly -- the same profile as the arch linings above.
##
## They hang at the MOUTH of the arch, on the junction side, and always swing
## into the junction. A door further into the arch cannot open without its
## leaves going through stone: measured with rays at the hinge line, the arch's
## vault comes down to 2.58 m from 2.2 to 2.7 m out, and the leaves stand
## 3.8 m at their free edge. They used to hang at 2.6 m, in the middle of it.
## Nearer the cell centre than ~1.65 m the junction room is clear overhead.
## A dead end's plugs stand proud of that, so its door hangs a little further in.
const DOOR_SCRIPT := preload("res://scripts/wood_door.gd")
## One corridor-to-corridor archway in this many gets a door.
const DOOR_EVERY := 12
const DOOR_DEPTH := 1.65
const DOOR_DEPTH_BY_KIND := {"dead": 1.38}
## With the brick kit every door hangs at the junction-side mouth of the pointed
## arch on the boundary (brick_level.gd: the arch runs 2.4 to 3.6 m out).
const BRICK_DOOR_DEPTH := 2.38
## The Tripo door's leaf is 0.16-1.0 m behind its stone face; the door node sits
## at the leaf's middle, so a kick from either side lands on it.
const BRICK_DOOR_LEAF := 0.58
## The leaf's outline (tools/build_brick_kit.py DOOR_LEAF_HEAD): 1.94 m wide, its
## pointed head 4.2 m up; the stone either side of it out to the arch's legs.
const BRICK_LEAF_HALF := 0.97
const BRICK_LEAF_TOP := 4.2
const BRICK_FRAME_HALF := 1.8
const DOOR_PLANK := 0.2
const DOOR_THICK := 0.08
## Segments along each plank's curved top.
const DOOR_TOP_STEPS := 4
## A door's flanking torches: how far either side of the arch's centre line,
## and where the wall face beside the arch is, per junction kind (measured --
## see `_door_torch_spots`).
const DOOR_TORCH_OUT := 2.05
const DOOR_WALL_FACE := {"cross": 1.76, "tee": 1.76, "corner": 1.76, "dead": 1.46}
## On a straight beyond a door: how far back from its end the pair hangs, and
## roughly where its side walls are there (snapped to the real stone in game).
const DOOR_SIDE_BACK := 1.6
const DOOR_SIDE_FACE := 1.77
## The Tripo gate used as the door (tools/build_gate_door.py), and its measured
## shape in the door's frame: a pointed arch of two arcs, each centred
## GATE_OFFSET_C to the far side of the middle on the springing line. Must
## track SCALE and the measurements in that script.
const GATE_DOOR := "res://models/kit/gate_door.glb"
const GATE_SCALE := 1.15
const GATE_HALF_W := 1.21 * GATE_SCALE
const GATE_SPRING := 2.0 * GATE_SCALE
const GATE_OFFSET_C := 0.719 * GATE_SCALE
const GATE_RADIUS := 1.929 * GATE_SCALE
## How far behind the leaves' plane their backs reach (0.121 m measured), plus
## a little: where the stone surround behind them starts.
const GATE_BACK := 0.13
## How far the surround reaches in under the leaves' edges.
const GATE_OVERLAP := 0.075
## The hinge pin's distance in front of the boards -- see `_build_gate_door`.
const GATE_HINGE_FORWARD := 0.30
## The seam batten: between the leaves' backs (to 0.121) and the surround (0.13).
const GATE_BATTEN_DEPTH := 0.125
const GATE_BATTEN_HEIGHT := 4.2
## The solid stone either side of the gate, out to the bored arch's jambs.
const GATE_JAMB_OUT := 1.84
const GATE_JAMB_HEIGHT := 2.4
## The stone surround behind a door -- see `_door_frame_mesh`.
const FRAME_HALF := 1.95
const FRAME_TOP := 4.7
const FRAME_IN := 1.70
const FRAME_GAP := 0.008
const FRAME_THICK := 0.04


static func place_doors(parent: Node3D, out: Built) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ModuleDoors"
	parent.add_child(holder)

	# Old weathered planks: textures/wood_door_*.png from tools/build_wood_texture.py
	# (four different planks side by side, each the full height of a door).
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://textures/wood_door_albedo.png")
	wood.normal_enabled = true
	wood.normal_texture = load("res://textures/wood_door_normal.png")
	wood.normal_scale = 1.2
	wood.roughness = 0.92
	wood.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var leaves := {-1.0: _door_leaf_mesh(-1.0, wood), 1.0: _door_leaf_mesh(1.0, wood)}
	# The Tripo gate from the `gate` module, cut out by tools/build_gate_door.py.
	# Without it the procedural planks above are the fallback.
	var gate := _gate_door_parts()
	var frame_stone := _synth_arch_material(1.0).duplicate() as StandardMaterial3D
	# No vertex colours on this mesh.
	frame_stone.vertex_color_use_as_albedo = false
	var frame := _door_frame_mesh(frame_stone, not gate.is_empty())
	var iron := StandardMaterial3D.new()
	# Old iron, a little rusty.
	iron.albedo_color = Color(0.07, 0.05, 0.04)
	iron.metallic = 0.45
	iron.roughness = 0.8
	var strap := _box(Vector3(ARCH_LINER_RADIUS - 0.12, 0.07, DOOR_THICK + 0.03), iron)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.055
	ring.outer_radius = 0.075
	ring.rings = 10
	ring.ring_segments = 5
	ring.material = iron

	var rng := RandomNumberGenerator.new()
	var seen := {}
	var placed := 0
	# [cell, step] for every door: the spawn's own first, always, hung in the
	# dead end so its face (+Z, the iron side) is towards the player; then one
	# in DOOR_EVERY of the corridor-to-corridor archways.
	var wanted: Array = []
	if not out.spawn_door.is_empty():
		var spawn_cell: Vector2i = out.spawn_door["cell"]
		var spawn_step: Vector2i = ModuleMaze.DIRS[int(out.spawn_door["side"])]
		wanted.append([out.cells[spawn_cell], spawn_step])
		seen[_door_edge(spawn_cell, spawn_step)] = true
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.court or cell.room >= 0 or not (cell.kind in BORED_KINDS):
			continue
		for side in ModuleMaze.ORDER:
			if not (cell.open & side):
				continue
			var step: Vector2i = ModuleMaze.DIRS[side]
			var other = out.cells.get(cell.pos + step)
			# Corridor to corridor only: never into a room or a courtyard.
			if other == null or other.court or other.room >= 0:
				continue
			var edge := _door_edge(cell.pos, step)
			if seen.has(edge):
				continue
			seen[edge] = true
			rng.seed = hash(edge) ^ 0x0d00
			if rng.randi_range(0, DOOR_EVERY - 1) != 0:
				continue
			wanted.append([cell, step])
	for pair in wanted:
		var cell: ModuleMaze.Cell = pair[0]
		var step: Vector2i = pair[1]
		var dir := Vector3(float(step.x), 0.0, float(step.y))
		var door := Node3D.new()
		door.set_script(DOOR_SCRIPT)
		var depth := BRICK_DOOR_DEPTH + BRICK_DOOR_LEAF if brick else float(DOOR_DEPTH_BY_KIND.get(cell.kind, DOOR_DEPTH))
		door.position = out.to_world(cell.pos) + dir * depth
		door.rotation.y = atan2(-dir.x, -dir.z)
		holder.add_child(door)
		if brick:
			_build_brick_door(door)
			out.doors.append({"cell": cell.pos, "other": cell.pos + step, "dir": dir, "node": door})
			placed += 1
			continue
		if gate.is_empty():
			_build_door(door, leaves, strap, ring)
		else:
			_build_gate_door(door, gate)
		var surround := MeshInstance3D.new()
		surround.name = "Frame"
		surround.mesh = frame
		surround.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surround.visibility_range_end = 40.0
		door.add_child(surround)
		out.doors.append({"cell": cell.pos, "other": cell.pos + step, "dir": dir, "node": door})
		placed += 1
	holder.set_meta("door_count", placed)
	return holder


## One key per archway, whichever side it is reached from.
static func _door_edge(pos: Vector2i, step: Vector2i) -> Array:
	return [mini(pos.x, pos.x + step.x), mini(pos.y, pos.y + step.y), step.x != 0]


## The Tripo gate's three parts -- "LeafL", "LeafR" (each with its origin on its
## hinge) and "GateFrame" -- wearing the gate module's own materials, matched
## by name. Those are already fixed by `_fix_material` and shared, so the
## textures are not loaded twice; the copies only turn off vertex colour (these
## are not MultiMesh instances, and with it on they render black) and draw both
## faces, so a leaf seen edge-on or from behind is never a hole. {} if the
## model is missing.
static func _gate_door_parts() -> Dictionary:
	if not ResourceLoader.exists(GATE_DOOR):
		return {}
	var packed := load(GATE_DOOR) as PackedScene
	if packed == null:
		return {}
	var by_name := {}
	var module := _first_mesh("res://models/kit/module_gate.glb")
	if module != null:
		for s in module.get_surface_count():
			var m := module.surface_get_material(s)
			if m != null:
				by_name[m.resource_name] = m
	var scene := packed.instantiate()
	var parts := {}
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			var own := mesh.surface_get_material(s)
			var source: Material = by_name.get(own.resource_name if own != null else "", own)
			var m := source.duplicate() as StandardMaterial3D if source is StandardMaterial3D \
				else StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = false
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.surface_set_material(s, m)
		parts[String(mi.name)] = mesh
	scene.free()
	if not (parts.has("LeafL") and parts.has("LeafR") and parts.has("GateFrame")):
		push_warning("module_level: %s is missing a part; using the plank doors" % GATE_DOOR)
		return {}
	return parts


## Brick kit: the Tripo arched door (`door_frame` + `door_leaf` from the brick
## kit) set in the arch on the boundary. One leaf ("LeafL"; wood_door.gd takes
## either) that the kick breaks; the stone frame stays.
static func _build_brick_door(door: Node3D) -> void:
	var frame := MeshInstance3D.new()
	frame.name = "GateFrame"
	frame.mesh = BrickLevel.standalone("door_frame")
	frame.position = Vector3(0.0, 0.0, BRICK_DOOR_LEAF)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	frame.visibility_range_end = 60.0
	door.add_child(frame)
	var leaf := Node3D.new()
	leaf.name = "LeafL"
	door.add_child(leaf)
	var boards := MeshInstance3D.new()
	boards.name = "Boards"
	boards.mesh = BrickLevel.standalone("door_leaf")
	boards.position = Vector3(0.0, 0.0, BRICK_DOOR_LEAF)
	boards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	boards.visibility_range_end = 60.0
	leaf.add_child(boards)
	# The blocker over the leaf (layers 1 + 2, armed after the bake: wood_door.gd).
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = 3
	body.collision_mask = 0
	door.add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(BRICK_LEAF_HALF * 2.0, BRICK_LEAF_TOP, 0.3)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = box
	shape.position = Vector3(0.0, BRICK_LEAF_TOP * 0.5, 0.0)
	shape.disabled = true
	body.add_child(shape)
	# The frame's stone either side of the leaf: solid from the start, so the
	# navmesh bakes the narrower doorway.
	var jambs := StaticBody3D.new()
	jambs.name = "Jambs"
	jambs.collision_layer = 3
	jambs.collision_mask = 0
	door.add_child(jambs)
	var width := BRICK_FRAME_HALF - BRICK_LEAF_HALF
	for s: float in [-1.0, 1.0]:
		var jbox := BoxShape3D.new()
		jbox.size = Vector3(width, 3.4, 1.2)
		var js := CollisionShape3D.new()
		js.shape = jbox
		js.position = Vector3(s * (BRICK_LEAF_HALF + width * 0.5), 1.7, 0.0)
		jambs.add_child(js)


## A door built from the Tripo gate: its two pointed leaves on their hinges,
## its moulded stone arch round them, a blocker across the opening and stone
## jambs where the gate is narrower than the bored arch it stands in.
static func _build_gate_door(door: Node3D, gate: Dictionary) -> void:
	var batten_mat := StandardMaterial3D.new()
	batten_mat.albedo_color = Color(0.11, 0.065, 0.04)
	batten_mat.roughness = 0.95
	for leaf_side: float in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.name = "LeafL" if leaf_side < 0.0 else "LeafR"
		# The hinge axis stands GATE_HINGE_FORWARD in front of the boards, as a
		# real door's pin does. On the boards' own line, the iron straps (which
		# run past it) swung 8-28 cm into the stone moulding beside the leaf;
		# from in front, every point of the leaf swings inward, clear of it.
		leaf.position = Vector3(leaf_side * GATE_HALF_W, 0.0, GATE_HINGE_FORWARD)
		door.add_child(leaf)
		var boards := MeshInstance3D.new()
		boards.mesh = gate[leaf.name]
		boards.position = Vector3(0.0, 0.0, -GATE_HINGE_FORWARD)
		boards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		boards.visibility_range_end = 40.0
		leaf.add_child(boards)
		if leaf_side > 0.0:
			# The Tripo leaves meet with a ~2 cm gap that backed onto solid wall
			# in the module and onto open corridor here. A thin batten behind the
			# right leaf covers it. The left leaf opens first, so it is clear by
			# the time this one swings.
			var batten := MeshInstance3D.new()
			batten.name = "Batten"
			var bm := BoxMesh.new()
			bm.size = Vector3(0.1, GATE_BATTEN_HEIGHT, 0.006)
			bm.material = batten_mat
			batten.mesh = bm
			batten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batten.visibility_range_end = 40.0
			batten.position = Vector3(-GATE_HALF_W, GATE_BATTEN_HEIGHT * 0.5,
				-GATE_BATTEN_DEPTH - GATE_HINGE_FORWARD)
			leaf.add_child(batten)
	var moulding := MeshInstance3D.new()
	moulding.name = "GateFrame"
	moulding.mesh = gate["GateFrame"]
	moulding.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moulding.visibility_range_end = 40.0
	door.add_child(moulding)

	# The blocker, as for the plank doors: layers 1 + 2, disabled until the
	# level is built (see wood_door.gd).
	var apex := GATE_SPRING + sqrt(GATE_RADIUS * GATE_RADIUS - GATE_OFFSET_C * GATE_OFFSET_C)
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = 3
	body.collision_mask = 0
	door.add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(GATE_HALF_W * 2.0, apex, 0.2)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = box
	shape.position = Vector3(0.0, apex * 0.5, 0.0)
	shape.disabled = true
	body.add_child(shape)

	# The gate is 2.78 m wide and the arch it stands in 3.57, so the stone either
	# side of it is solid -- for everyone and for sight, and from the start, so
	# the navmesh bakes the narrower doorway. Up to head height is enough.
	var jambs := StaticBody3D.new()
	jambs.name = "Jambs"
	jambs.collision_layer = 3
	jambs.collision_mask = 0
	door.add_child(jambs)
	var width := GATE_JAMB_OUT - GATE_HALF_W
	for jamb_side: float in [-1.0, 1.0]:
		var jbox := BoxShape3D.new()
		jbox.size = Vector3(width, GATE_JAMB_HEIGHT, 0.4)
		var js := CollisionShape3D.new()
		js.shape = jbox
		js.position = Vector3(jamb_side * (GATE_HALF_W + width * 0.5), GATE_JAMB_HEIGHT * 0.5, 0.0)
		jambs.add_child(js)


## Two leaves of vertical planks cut to the round head of the arch, with iron
## straps and a ring pull, and one blocker across the opening.
static func _build_door(door: Node3D, leaves: Dictionary, strap: Mesh, ring: Mesh) -> void:
	var r := ARCH_LINER_RADIUS - 0.01
	for leaf_side: float in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.name = "LeafL" if leaf_side < 0.0 else "LeafR"
		# Hinged on its own jamb.
		leaf.position = Vector3(leaf_side * r, 0.0, 0.0)
		door.add_child(leaf)
		var boards := _window_part(leaf, leaves[leaf_side], Vector3.ZERO)
		boards.visibility_range_end = 40.0
		for y in [0.75, 2.45]:
			var s := _window_part(leaf, strap, Vector3(-leaf_side * (r - 0.06) * 0.5, y, 0.0))
			s.visibility_range_end = 40.0
		for face in [-1.0, 1.0]:
			var pull := _window_part(leaf, ring, Vector3(-leaf_side * (r - 0.22), 1.25, face * (DOOR_THICK * 0.5 + 0.02)))
			pull.rotation.x = PI * 0.5
			pull.visibility_range_end = 30.0

	# Layers 1 + 2 like the gates: the player and every enemy collide with 1,
	# and 2 is the sight layer, so nothing sees through a shut door. Disabled
	# until the level is built -- see wood_door.gd.
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = 3
	body.collision_mask = 0
	door.add_child(body)
	var box := BoxShape3D.new()
	box.size = Vector3(r * 2.0, ARCH_LINER_SPRING + r, 0.2)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = box
	shape.position = Vector3(0.0, (ARCH_LINER_SPRING + r) * 0.5, 0.0)
	shape.disabled = true
	body.add_child(shape)


## The stone surround that closes the arch's mouth round a door. The door hangs
## at the mouth, and the mouth flares much wider than the arch -- at 1.7 m off
## the centre line it is open to 3.77 m, where the arch is 2.56 -- so from the
## corridor side the light came straight round the leaves' edges. This is a
## flat slab just behind the leaves (on the corridor side, local -Z), filling
## FRAME_HALF either side of the centre line from the floor to FRAME_TOP, with
## an arch-shaped hole FRAME_IN in radius: 7.5 cm smaller than the leaves, so
## they overlap it all round. It never moves; the leaves swing the other way.
## It stops short of the torches beside the arch (2.05 m out). Where it runs
## into stone it is simply hidden.
##
## For the Tripo gate (`pointed`) the hole is the gate's own pointed arch, the
## same GATE_OVERLAP smaller than its leaves, and the slab sits just behind the
## leaves' backs (GATE_BACK) instead of a plank door's.
static func _door_frame_mesh(stone: Material, pointed := false) -> Mesh:
	var spring := ARCH_LINER_SPRING
	var inner := FRAME_IN
	if pointed:
		spring = GATE_SPRING
		inner = GATE_HALF_W - GATE_OVERLAP
	var outline := PackedVector2Array([
		Vector2(-FRAME_HALF, -0.05), Vector2(-FRAME_HALF, FRAME_TOP),
		Vector2(FRAME_HALF, FRAME_TOP), Vector2(FRAME_HALF, -0.05),
		Vector2(inner, -0.05), Vector2(inner, spring),
	])
	var arc := 24
	if pointed:
		# Two arcs, each centred on the far side of the middle, meeting at the apex.
		var r := GATE_RADIUS - GATE_OVERLAP
		var c := GATE_OFFSET_C
		var top := acos(c / r)
		for k in range(1, arc + 1):
			var a := top * float(k) / float(arc)
			outline.append(Vector2(-c + cos(a) * r, spring + sin(a) * r))
		for k in range(arc - 1, 0, -1):
			var a := top * float(k) / float(arc)
			outline.append(Vector2(c - cos(a) * r, spring + sin(a) * r))
	else:
		for k in range(1, arc):
			var a := PI * float(k) / float(arc)
			outline.append(Vector2(cos(a) * inner, spring + sin(a) * inner))
	outline.append(Vector2(-inner, spring))
	outline.append(Vector2(-inner, -0.05))
	var tris := Geometry2D.triangulate_polygon(outline)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front := -(GATE_BACK if pointed else DOOR_THICK * 0.5 + FRAME_GAP)
	var back := front - FRAME_THICK
	for i in range(0, tris.size(), 3):
		var a := outline[tris[i]]
		var b := outline[tris[i + 1]]
		var c := outline[tris[i + 2]]
		for z: float in [front, back]:
			var n := Vector3(0, 0, 1) if z == front else Vector3(0, 0, -1)
			for p: Vector2 in ([a, b, c] if z == front else [a, c, b]):
				st.set_normal(n)
				st.set_uv(p)
				st.add_vertex(Vector3(p.x, p.y, z))
	# The edge of the hole and the outer edge, so it has thickness side-on.
	for i in outline.size():
		var p0 := outline[i]
		var p1 := outline[(i + 1) % outline.size()]
		var along := (p1 - p0).normalized()
		var n := Vector3(along.y, -along.x, 0.0)
		for v: Vector3 in [Vector3(p0.x, p0.y, front), Vector3(p1.x, p1.y, front), Vector3(p1.x, p1.y, back),
				Vector3(p0.x, p0.y, front), Vector3(p1.x, p1.y, back), Vector3(p0.x, p0.y, back)]:
			st.set_normal(n)
			st.set_uv(Vector2(v.x, v.y))
			st.add_vertex(v)
	st.set_material(stone)
	return st.commit()


## One leaf's planks as a single mesh with real UVs. Each plank is a box whose
## faces map one of the texture's four planks over the door's full height, so a
## leaf shows different wood in every board and draws in one call. Hinged at
## the origin; the planks run towards the middle of the door (-side * x).
static func _door_leaf_mesh(side: float, wood: Material) -> Mesh:
	var r := ARCH_LINER_RADIUS - 0.01
	var tall := ARCH_LINER_SPRING + r - ARCH_LINER_BASE
	var planks := int(ceil(r / DOOR_PLANK))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := DOOR_THICK * 0.5
	# A little below the floor (whose top is y = 0), so there is no slot of
	# light under the door.
	var y0 := -0.04
	var v_bot := 1.0
	for i in planks:
		var outer := float(i) * DOOR_PLANK
		# Edge to edge: the boards' dark seams are in the texture. A real gap
		# between them was see-through.
		var inner := minf(float(i + 1) * DOOR_PLANK, r)
		# Which of the four texture planks, so neighbouring boards never share
		# a grain, and a hair of depth jitter so they do not read as one sheet.
		var col := float((i + (0 if side < 0.0 else 2)) % 4)
		var u0 := col * 0.25 + 0.01
		var u1 := col * 0.25 + 0.24
		var z := (float(i % 3) - 1.0) * 0.003
		# The top follows the arch's curve across the board, sampled, not cut
		# flat or on one chord: at the jamb the arch is nearly vertical and a
		# single chord left an 18 cm notch against the stone.
		var xs: Array[float] = []
		var ys: Array[float] = []
		var us: Array[float] = []
		for k in DOOR_TOP_STEPS + 1:
			var t := float(k) / float(DOOR_TOP_STEPS)
			var d := lerpf(outer, inner, t)
			var from_mid := r - d
			xs.append(-side * d)
			ys.append(ARCH_LINER_SPRING + sqrt(maxf(r * r - from_mid * from_mid, 0.0)) - 0.03)
			# u runs the same way across the board on both leaves.
			us.append(lerpf(u0, u1, t if side < 0.0 else 1.0 - t))
		for k in DOOR_TOP_STEPS:
			# Order each strip left to right so the winding is always the same.
			var a := k if xs[k] < xs[k + 1] else k + 1
			var b := k + 1 if a == k else k
			var xa := xs[a]
			var xb := xs[b]
			var ya := ys[a]
			var yb := ys[b]
			var va := 1.0 - (ya - y0) / tall
			var vb := 1.0 - (yb - y0) / tall
			_quad(st, Vector3(xa, y0, half + z), Vector3(xb, y0, half + z), Vector3(xb, yb, half + z), Vector3(xa, ya, half + z),
				Vector3(0, 0, 1), Vector2(us[a], v_bot), Vector2(us[b], v_bot), Vector2(us[b], vb), Vector2(us[a], va))
			_quad(st, Vector3(xb, y0, -half + z), Vector3(xa, y0, -half + z), Vector3(xa, ya, -half + z), Vector3(xb, yb, -half + z),
				Vector3(0, 0, -1), Vector2(us[b], v_bot), Vector2(us[a], v_bot), Vector2(us[a], va), Vector2(us[b], vb))
			var slope := Vector3(xb - xa, yb - ya, 0.0).cross(Vector3(0, 0, -1)).normalized()
			if slope.y < 0.0:
				slope = -slope
			_quad(st, Vector3(xa, ya, half + z), Vector3(xb, yb, half + z), Vector3(xb, yb, -half + z), Vector3(xa, ya, -half + z),
				slope, Vector2(us[a], va), Vector2(us[b], vb), Vector2(us[b], vb + 0.01), Vector2(us[a], va + 0.01))
		# The two vertical edges: a sliver of the same plank.
		var lo := 0 if xs[0] < xs[DOOR_TOP_STEPS] else DOOR_TOP_STEPS
		var hi := DOOR_TOP_STEPS - lo
		var ylo := ys[lo]
		var yhi := ys[hi]
		var vlo := 1.0 - (ylo - y0) / tall
		var vhi := 1.0 - (yhi - y0) / tall
		var xl := xs[lo]
		var xh := xs[hi]
		_quad(st, Vector3(xl, y0, -half + z), Vector3(xl, y0, half + z), Vector3(xl, ylo, half + z), Vector3(xl, ylo, -half + z),
			Vector3(-1, 0, 0), Vector2(us[lo], v_bot), Vector2(us[lo] + 0.01, v_bot), Vector2(us[lo] + 0.01, vlo), Vector2(us[lo], vlo))
		_quad(st, Vector3(xh, y0, half + z), Vector3(xh, y0, -half + z), Vector3(xh, yhi, -half + z), Vector3(xh, yhi, half + z),
			Vector3(1, 0, 0), Vector2(us[hi] - 0.01, v_bot), Vector2(us[hi], v_bot), Vector2(us[hi], vhi), Vector2(us[hi] - 0.01, vhi))
	st.generate_tangents()
	st.set_material(wood)
	return st.commit()


## One quad, counter-clockwise seen from `normal`.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for v in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		st.set_normal(normal)
		st.set_uv(v[1])
		st.add_vertex(v[0])

## Paves each room's open courtyard.
##
## One slab per room rather than per cell: the court is a single open space,
## and a slab per cell would put a seam every six metres across it for no
## reason. The top sits at y = 0 to meet the arcade's floors, and it has depth
## for the same reason the module floors do -- a plane has no underside.
static func _place_courts(parent: Node3D, out: Built, tint: float, boss_only := false) -> void:
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
		# With the brick kit the courts are flagstones (brick_level.gd); only the
		# boss block, which the stair stands on, keeps its paving.
		if boss_only and room["kind"] != "boss":
			continue
		# Out to the ring's inner boundary, so the paving runs under the
		# arcade's arches and meets its floor rather than stopping short. The
		# boss room has no arcade (its whole block is the stair's ground), so
		# its paving covers the block.
		var span := (float(room["half"]) * 2.0 - 1.0) * out.cell_size
		if room["kind"] == "boss":
			span = (float(room["half"]) * 2.0 + 1.0) * out.cell_size
		var box := BoxMesh.new()
		box.size = Vector3(span, COURT_DEPTH, span)
		box.material = mat
		var mi := MeshInstance3D.new()
		mi.name = "Court_%s" % room["kind"]
		mi.mesh = box
		mi.position = out.room_world(room) \
			+ Vector3(0.0, COURT_Y_OFFSET - COURT_DEPTH * 0.5, 0.0)
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
## 12 since 2026-10-10 ("make the overall environment much darker"; was 22).
const SKY_LIGHT_ENERGY := 12.0
const SKY_LIGHT_HEIGHT := 8.5
## How bright the sky itself is drawn. The panorama is a blazing red, and
## against it anything lit at dungeon levels reads as a flat black cut-out.
## Pulled down, it is a dark blood-red sky that still reads as open air.
## 0.3 since 2026-10-10 (darker; was 0.42).
const SKY_ENERGY := 0.3


static func place_room_lights(parent: Node3D, out: Built) -> Node3D:
	var holder := Node3D.new()
	holder.name = "RoomSkyLights"
	parent.add_child(holder)
	var placed := 0
	for room in out.rooms:
		# The boss hall lights itself (boss_hall.gd); its ground is a stairwell.
		if room["kind"] == "boss":
			continue
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

	# Every wooden door gets a pair, one on each side wall of the corridor
	# leading up to it. Those cells then skip their ordinary random torch, so a
	# wall never carries two a couple of metres apart.
	var door_cells := {}
	var door_placed := 0
	# Brick kit: no torches beside doors (2026-10-10, at the user's request).
	for door in ([] if brick else out.doors):
		var hung: Array = []
		for spot in _door_torch_spots(out, door):
			hung.append(_hang_torch(holder, scene, spot["at"], spot["into"], energy, TORCH_RANGE))
			door_cells[spot["cell"]] = true
			out.torch_cells[spot["cell"]] = spot["side"]
			door_placed += 1
		# The door snaps them onto the real stone once collision exists.
		var node: Node = door.get("node")
		if node != null:
			node.set_meta("torches", hung)
	placed += door_placed
	holder.set_meta("door_torch_count", door_placed)

	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.court or door_cells.has(cell.pos):
			continue
		# Deterministic per cell, so torch positions do not shuffle when the
		# dictionary happens to iterate in a different order.
		rng.seed = hash(cell.pos) ^ 0x7f4a
		var odds: int = room_every if cell.room >= 0 else every
		if rng.randi_range(0, odds - 1) != 0:
			continue
		# Hang it on a side that is actually walled, or it floats in an arch.
		var walls: Array[int] = []
		var cages: Dictionary = out.get_meta("cage_walls", {})
		for side in ModuleMaze.ORDER:
			# Not on a brick wall with an iron cage standing out of it, nor on
			# the end wall of an exit, which carries the great door.
			if cages.has(cell.pos) and side in cages[cell.pos]:
				continue
			if brick and cell.kind == "gate" and BrickLevel._is_end_wall(cell, side):
				continue
			if not (cell.open & side):
				# ...and not the wall with a bone-cage niche in it.
				if out.niches.has(cell.pos):
					var s: Vector2i = ModuleMaze.DIRS[side]
					if Vector3(float(s.x), 0.0, float(s.y)).dot(out.niches[cell.pos]["dir"]) > 0.5:
						continue
				walls.append(side)
		if walls.is_empty():
			continue
		var side: int = walls[rng.randi_range(0, walls.size() - 1)]
		var step: Vector2i = ModuleMaze.DIRS[side]
		var dir := Vector3(float(step.x), 0.0, float(step.y))
		var face: float = wall_face(cell.kind) if brick else WALL_FACE.get(cell.kind, out.cell_size * 0.5 - 1.1)
		if face <= 0.01:
			continue
		if brick:
			_pilaster_torch(holder, scene, out.to_world(cell.pos) + dir * face, dir, energy)
			out.torch_cells[cell.pos] = side
			placed += 1
			continue
		_hang_torch(holder, scene,
			out.to_world(cell.pos) + dir * (face - 0.12)
				+ Vector3(0.0, out.height * TORCH_HEIGHT, 0.0),
			dir, energy, TORCH_RANGE)
		out.torch_cells[cell.pos] = side
		placed += 1

	holder.set_meta("torch_count", placed)
	return holder


## Where a door's torches go: a pair on each side of it.
##
## On the door's own side -- it hangs in the mouth of a junction cell's bored
## arch -- they go on the wall face either side of the arch, hanging back into
## that cell. That face was measured with rays against the exact collision:
## 1.76 m from the cell centre at DOOR_TORCH_OUT from the arch's centre line and
## torch height, in every junction kind but the dead end (1.46 m, its plugs).
## Further out than that a torch would hang in the mouth of a side arch
## wherever that side is open.
##
## On the far side, a junction gets the same pair on its own face; a straight
## has no face round its end -- its walls run straight on to the arch -- so the
## pair goes on its two side walls, DOOR_SIDE_BACK back from its end. Those
## walls are not where the mid-straight figure says (measured 1.77 m there on
## most straights, 2.05 m on others), so wood_door.gd snaps every one of these
## torches onto the real stone with a ray once the level's collision exists.
static func _door_torch_spots(out: Built, door: Dictionary) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	var dir: Vector3 = door["dir"]
	var lateral := Vector3(-dir.z, 0.0, dir.x)
	var up := Vector3(0.0, out.height * TORCH_HEIGHT, 0.0)
	if brick:
		# Brick kit: a junction has a pillar either side of the arch, and the
		# pair hangs on their faces towards the corridor's centre line; a
		# straight has its side walls running up to the arch. One pair, on the
		# junction side only (2026-10-10: the level was to be far darker).
		for side in [[door["cell"], dir]]:
			var pos: Vector2i = side[0]
			var toward: Vector3 = side[1]
			var cell = out.cells.get(pos)
			if cell == null or cell.court or cell.room >= 0:
				continue
			for sign_: float in [-1.0, 1.0]:
				var into := lateral * sign_
				var at: Vector3
				if cell.kind in BrickLevel.JUNCTIONS:
					at = out.to_world(pos) + toward * BrickLevel.PILLAR_AT \
						+ into * (BrickLevel.PILLAR_AT - BrickLevel.PILLAR_HALF - 0.04) + up
				else:
					at = out.to_world(pos) + toward * (out.cell_size * 0.5 - DOOR_SIDE_BACK) \
						+ into * (BrickLevel.WALL_FACE - 0.12) + up
				spots.append({"cell": pos, "side": _side_towards(into), "into": into, "at": at})
		return spots
	# [cell, direction from its centre to the door]
	for side in [[door["cell"], dir], [door["other"], -dir]]:
		var pos: Vector2i = side[0]
		var toward: Vector3 = side[1]
		var cell = out.cells.get(pos)
		if cell == null or cell.court or cell.room >= 0:
			continue
		var face: float = DOOR_WALL_FACE.get(cell.kind, 0.0)
		for sign_: float in [-1.0, 1.0]:
			if face > 0.01:
				spots.append({
					"cell": pos, "side": _side_towards(toward), "into": toward,
					"at": out.to_world(pos) + toward * (face - 0.12)
						+ lateral * sign_ * DOOR_TORCH_OUT + up,
				})
			elif cell.kind == "straight":
				# A bone-cage niche sits mid-wall, 0.45 m either side of the
				# centre; these hang 1.4 m from it, so it is no obstacle.
				var into := lateral * sign_
				spots.append({
					"cell": pos, "side": _side_towards(into), "into": into,
					"at": out.to_world(pos) + toward * (out.cell_size * 0.5 - DOOR_SIDE_BACK)
						+ into * (DOOR_SIDE_FACE - 0.12) + up,
				})
	return spots

## The ModuleMaze side flag whose direction matches `v`, or 0.
static func _side_towards(v: Vector3) -> int:
	for side in ModuleMaze.ORDER:
		var s: Vector2i = ModuleMaze.DIRS[side]
		if Vector3(float(s.x), 0.0, float(s.y)).dot(v) > 0.5:
			return side
	return 0


## Brick kit: a torch pillar from the kit stands against the wall as a pilaster
## (`face_point` is on the wall face, `into_wall` points at the stone), and the
## torch scene's flame, halo, light and embers -- without its own bracket,
## handle or head -- burn on the pillar's carved torch.
static var _pilaster_mesh: Mesh = null


static func _pilaster_torch(holder: Node3D, scene: PackedScene, face_point: Vector3,
		into_wall: Vector3, energy: float) -> Node3D:
	if _pilaster_mesh == null:
		var source: Mesh = BrickLevel.meshes(1.0).get("pillar_torch")
		if source == null:
			return _hang_torch(holder, scene, face_point - into_wall * 0.12
				+ Vector3(0.0, 2.35, 0.0), into_wall, energy, TORCH_RANGE)
		# A plain MeshInstance has no instance colour, and the kit's materials
		# take their albedo from it: copies with that off, or it renders black.
		var copy := source.duplicate() as Mesh
		for s in copy.get_surface_count():
			var m := copy.surface_get_material(s) as StandardMaterial3D
			if m != null:
				m = m.duplicate() as StandardMaterial3D
				m.vertex_color_use_as_albedo = false
				copy.surface_set_material(s, m)
		_pilaster_mesh = copy
	var basis := Basis(Vector3.UP, atan2(-into_wall.x, -into_wall.z))
	var centre := face_point + into_wall * (BrickLevel.PILLAR_HALF - BrickLevel.PILASTER_PROUD)
	var pillar := MeshInstance3D.new()
	pillar.name = "TorchPillar"
	pillar.mesh = _pilaster_mesh
	pillar.transform = Transform3D(basis, centre)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar.visibility_range_end = 70.0
	holder.add_child(pillar)
	var body := StaticBody3D.new()
	body.collision_layer = BrickLevel.LAYER_WALLS
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(BrickLevel.PILLAR_HALF * 2.0, BrickLevel.PILLAR_HEIGHT, BrickLevel.PILLAR_HALF * 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = centre + Vector3(0.0, BrickLevel.PILLAR_HEIGHT * 0.5, 0.0)
	holder.add_child(body)

	var head := centre + basis * BrickLevel.TORCH_HEAD
	# The pillar carries its own carved torch: no second one.
	var torch := _hang_torch(holder, scene, head, into_wall, energy, TORCH_RANGE, false)
	for part in ["Plate", "Arm", "Ring", "Handle", "Head"]:
		var n := torch.get_node_or_null(part) as Node3D
		if n != null:
			n.visible = false
	# The scene's flame stands at FLAME_AT on its own torch; put that on the
	# pillar torch's head, a little above its top.
	torch.position = head + Vector3(0.0, 0.04, 0.0) - torch.basis * Vector3(0.0, 0.37, -0.49)
	return torch


## Puts one torch on a wall. `into_wall` points from the room at the stone.
static func _hang_torch(holder: Node3D, scene: PackedScene, at: Vector3,
		into_wall: Vector3, energy: float, reach: float, kit_mount := true) -> Node3D:
	var torch := scene.instantiate() as Node3D
	torch.set("kit_mount", kit_mount)
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
		# Torches cast shadows -- only near the camera: `Graphics` sets
		# `distance_fade_shadow` from its shadow-distance knob for every light
		# carrying this meta, and switches them off on Potato. The torch's own
		# mount casts none, or it would shade its own light.
		light.shadow_enabled = true
		light.set_meta("torch_shadow", true)
		light.light_color = TORCH_COLOUR
	return torch


## --- Bone cages ---------------------------------------------------------------
##
## Every "window" in the level is a barred niche set INTO a corridor wall, with a
## random heap of bones and rocks inside it and red light shining down on them
## from the top of the niche -- the same red light the old windows threw, which
## also spills out into the corridor.
##
## The recess is real. `build_modules.py cut_niche` builds `straight_niche`, the
## straight with its +X wall face opened over a rectangle into the hollow inside
## of the Tripo wall shell (the wall is ~1.1 m thick there); this lines it with
## stone, puts the glowing panel at the back and the bars across the front.
## Straights only: they are symmetric, so a niche on either wall is the same
## piece turned half round, and collision (the plain straight's) is unchanged
## -- the player meets the wall face and the bars, never the inside.
const NICHE_KIND := "straight_niche"
## Must match NICHE_W / NICHE_H / NICHE_SILL in `build_modules.py`.
const NICHE_SIZE := Vector2(0.9, 0.8)
const NICHE_SILL := 1.05
## The wall face at the niche, as the build measured it ("wall face at 1.843 m").
const NICHE_FACE := 1.843
const NICHE_DEPTH := 0.55
## One straight corridor cell in this many gets a niche.
const NICHE_EVERY := 5
const CAGE_SKULL := "res://models/skull_worn_ready.glb"
const CAGE_SCRIPT := preload("res://scripts/bone_cage.gd")
## What a cage pays, and so how many coins and jewels are in it.
const CAGE_PAY_MIN := 5
const CAGE_PAY_MAX := 13
const CAGE_SKULL_WIDTH := 0.22


static func _pick_niches(out: Built, meshes: Dictionary) -> void:
	out.niches.clear()
	if not meshes.has(NICHE_KIND):
		return
	var rng := RandomNumberGenerator.new()
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.kind != "straight" or cell.room >= 0 or out.skylights.has(cell.pos):
			continue
		rng.seed = hash(cell.pos) ^ 0x2b0e
		if rng.randi_range(0, NICHE_EVERY - 1) != 0:
			continue
		# The niche piece has it on its +X wall; half the time the piece is
		# turned round so it lands on the other wall instead.
		var flip := rng.randf() < 0.5
		var dir := _cell_basis(cell) * Vector3.RIGHT
		out.niches[cell.pos] = {"flip": flip, "dir": -dir if flip else dir}


static func place_windows(parent: Node3D, out: Built, density: float = 1.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ModuleWindows"
	parent.add_child(holder)

	var w := NICHE_SIZE.x
	var h := NICHE_SIZE.y
	var d := NICHE_DEPTH

	# The glowing back of the niche, as the old windows' pane: a radial red
	# gradient, emission only.
	var glow_gradient := Gradient.new()
	glow_gradient.colors = PackedColorArray([
		Color(1.0, 0.16, 0.07), Color(0.55, 0.05, 0.03), Color(0.16, 0.015, 0.01)])
	glow_gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var glow_tex := GradientTexture2D.new()
	glow_tex.gradient = glow_gradient
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.width = 64
	glow_tex.height = 64
	var panel := QuadMesh.new()
	panel.size = NICHE_SIZE
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0, 0, 0)
	panel_mat.emission_enabled = true
	# Black: the default emission operator ADDS the texture to this colour.
	panel_mat.emission = Color(0, 0, 0)
	panel_mat.emission_texture = glow_tex
	panel_mat.emission_energy_multiplier = WINDOW_GLOW_ENERGY
	panel_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	panel_mat.roughness = 1.0
	panel.material = panel_mat

	# The corridors' light grey brick for the lining and the frame. A BoxMesh has
	# no vertex colours, so the shared material's vertex-colour flag comes off.
	var stone := _synth_material(1.0).duplicate() as StandardMaterial3D
	stone.vertex_color_use_as_albedo = false
	var t := 0.06
	var back := _box(Vector3(w + t * 2.0, h + t * 2.0, t), stone)
	var wall := _box(Vector3(t, h + t * 2.0, d + 0.1), stone)
	var sill := _box(Vector3(w, t, d + 0.1), stone)
	# A frame standing a little proud of the wall hides the cut edge of the
	# Tripo face round the opening, which is as ragged as the stone.
	var f := 0.13
	var jamb := _box(Vector3(f, h + f * 2.0, 0.16), stone)
	var lintel := _box(Vector3(w, f, 0.16), stone)

	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.045, 0.04, 0.04)
	iron.roughness = 0.7
	iron.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var bar := _rod(h, 0.02, iron)
	var band := _rod(w, 0.018, iron)
	var debris := _bone_parts()

	var lit_every := maxi(1, int(round(1.0 / maxf(density, 0.05))))
	var rng := RandomNumberGenerator.new()
	var placed := 0
	for pos in out.niches:
		var info: Dictionary = out.niches[pos]
		var dir: Vector3 = info["dir"]
		rng.seed = hash(pos) ^ 0x6b1d
		# One node per niche: origin in the wall face at the niche's centre,
		# local +Z back out into the corridor, -Z into the wall.
		var niche := Node3D.new()
		# Before it enters the tree, so the script's _ready runs.
		niche.set_script(CAGE_SCRIPT)
		niche.position = out.to_world(pos) + dir * (BrickLevel.WALL_FACE if brick else NICHE_FACE) \
			+ Vector3(0.0, NICHE_SILL + h * 0.5, 0.0)
		niche.rotation.y = atan2(-dir.x, -dir.z)
		niche.set_meta("window_kind", "cage")
		if brick:
			_brick_cage(holder, niche, out.to_world(pos) + dir * BrickLevel.WALL_FACE, debris, rng, density, placed, lit_every)
			placed += 1
			continue
		holder.add_child(niche)

		# Lining, from a hair in front of the face to the back of the recess.
		var mid_z := -d * 0.5 + 0.03
		_window_part(niche, back, Vector3(0.0, 0.0, -d - t * 0.5))
		_window_part(niche, wall, Vector3(-(w + t) * 0.5, 0.0, mid_z))
		_window_part(niche, wall, Vector3((w + t) * 0.5, 0.0, mid_z))
		_window_part(niche, sill, Vector3(0.0, -(h + t) * 0.5, mid_z))
		_window_part(niche, sill, Vector3(0.0, (h + t) * 0.5, mid_z))
		# No glowing panel over the back: the brick shows there too, and the red
		# light at the top of the niche is what makes it glow.
		for sx in [-1.0, 1.0]:
			_window_part(niche, jamb, Vector3(sx * (w + f) * 0.5, 0.0, 0.05))
		for sy in [-1.0, 1.0]:
			_window_part(niche, lintel, Vector3(0.0, sy * (h + f) * 0.5, 0.05))

		# The cage door: bars across the mouth, flush with the frame, hung on
		# the left jamb so one_cage.gd can swing it open.
		var door := Node3D.new()
		door.name = "Door"
		door.position = Vector3(-w * 0.5, 0.0, 0.07)
		niche.add_child(door)
		for i in 5:
			var x := (float(i) + 1.0) / 6.0 * w
			_window_part(door, bar, Vector3(x, 0.0, 0.0))
		for y in [-h * 0.28, h * 0.3]:
			var b := _window_part(door, band, Vector3(w * 0.5, y, 0.02))
			b.rotation.z = PI * 0.5

		_fill_niche(niche, debris, rng, w, h, d)

		placed += 1
		if density <= 0.0 or placed % lit_every != 0:
			continue
		# The old windows' red light, hung at the top of the niche so it shines
		# down on the bones; shadowless, so it also spills out into the corridor.
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
		glow.position = Vector3(0.0, h * 0.5 - 0.1, -d * 0.45)
		niche.add_child(glow)

	holder.set_meta("window_count", placed)
	return holder


## Brick kit: the bone cage is the Tripo iron cage standing out of the wall
## (brick_level's "wall_cage" piece, put there by brick_level.build). Measured
## in that piece's frame (front face z = 0, +Z out, x along the wall): the cage
## stands 0.13-0.68 m out at x -0.03..1.13, y 1.55..2.63; inside it 0.77 x 0.78
## x 0.35 m from x 0.18, y 1.67, z 0.13. Its gate ("cage_door", the frame and
## bars in front of z 0.49) hinges on its left edge and swings out.
const CAGE_CENTRE := Vector3(0.565, 2.06, 0.0)
const CAGE_INSIDE := Vector3(0.77, 0.78, 0.35)
const CAGE_MID_Z := 0.3
const CAGE_HINGE := Vector3(-0.03, 0.0, 0.6)


static func _brick_cage(holder: Node3D, niche: Node3D, face_point: Vector3, debris: Dictionary,
		rng: RandomNumberGenerator, density: float, index: int, lit_every: int) -> void:
	# The holders sit at the origin unrotated, and the level is built before
	# it is in the tree: a local position, not a global one.
	niche.position = face_point + niche.basis.x * CAGE_CENTRE.x + Vector3(0.0, CAGE_CENTRE.y, 0.0)
	holder.add_child(niche)
	var door := Node3D.new()
	door.name = "Door"
	door.position = CAGE_HINGE - Vector3(CAGE_CENTRE.x, 0.0, 0.0)
	niche.add_child(door)
	var gate := MeshInstance3D.new()
	gate.mesh = BrickLevel.standalone("cage_door")
	# The gate mesh is in the wall piece's frame.
	gate.position = -Vector3(CAGE_CENTRE.x, CAGE_CENTRE.y, 0.0) - door.position
	gate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.visibility_range_end = 40.0
	door.add_child(gate)
	_fill_niche(niche, debris, rng, CAGE_INSIDE.x, CAGE_INSIDE.y, CAGE_INSIDE.z, CAGE_MID_Z)
	if density <= 0.0 or (index + 1) % lit_every != 0:
		return
	var glow := OmniLight3D.new()
	glow.light_color = WINDOW_COLOUR
	glow.light_energy = WINDOW_ENERGY * 0.6
	glow.omni_range = WINDOW_RANGE * 0.8
	glow.omni_attenuation = 0.8
	glow.light_specular = 0.0
	glow.shadow_enabled = false
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 26.0
	glow.distance_fade_length = 8.0
	glow.position = Vector3(0.0, CAGE_INSIDE.y * 0.5 - 0.08, CAGE_MID_Z)
	niche.add_child(glow)


static func _box(size: Vector3, material: Material) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	return box


static func _rod(length: float, radius: float, material: Material) -> CylinderMesh:
	var rod := CylinderMesh.new()
	rod.top_radius = radius
	rod.bottom_radius = radius
	rod.height = length
	rod.radial_segments = 6
	rod.material = material
	return rod


## Gold coins, white jewels and the Tripo skull.
static func _bone_parts() -> Dictionary:
	var parts := {}
	# Gold that reads as gold under red light: part metal, and a faint glow of
	# its own, because with the sky's reflections kept tiny (sky_setup.gd) a
	# fully metallic coin has nothing to reflect and goes nearly black.
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.72, 0.26)
	gold.metallic = 0.55
	gold.roughness = 0.3
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.62, 0.2)
	gold.emission_energy_multiplier = 0.22
	var coin := CylinderMesh.new()
	coin.top_radius = 0.032
	coin.bottom_radius = 0.032
	coin.height = 0.007
	coin.radial_segments = 10
	coin.rings = 1
	coin.material = gold
	parts["coin"] = coin
	# White jewels: glossy, and lit a little from within so they stay white
	# under a red light instead of turning pink.
	var gem := StandardMaterial3D.new()
	gem.albedo_color = Color(0.93, 0.95, 1.0)
	gem.roughness = 0.05
	gem.metallic_specular = 1.0
	gem.emission_enabled = true
	gem.emission = Color(0.75, 0.78, 0.9)
	gem.emission_energy_multiplier = 0.45
	var jewel := SphereMesh.new()
	jewel.radius = 0.026
	jewel.height = 0.042
	jewel.radial_segments = 5
	jewel.rings = 2
	jewel.material = gem
	parts["jewel"] = jewel
	var skull := _first_mesh(CAGE_SKULL)
	if skull != null:
		# Tripo assets import metallic (CLAUDE.md); bone is not metal, and
		# this one reads bleached white against the glow unless grimed down.
		skull = skull.duplicate() as Mesh
		for s in skull.get_surface_count():
			var m := skull.surface_get_material(s) as StandardMaterial3D
			if m != null:
				m = m.duplicate() as StandardMaterial3D
				m.metallic = 0.0
				m.roughness = 0.85
				m.albedo_color = m.albedo_color * Color(0.62, 0.58, 0.52)
				skull.surface_set_material(s, m)
		parts["skull"] = skull
	return parts


## A heap of coins and jewels on the niche floor, highest in the middle, with
## the skull sitting on top. The coins and jewels go under a "Loot" node, which
## `bone_cage.gd` scoops into the sack; the skull stays behind.
static func _fill_niche(niche: Node3D, parts: Dictionary, rng: RandomNumberGenerator,
		w: float, h: float, d: float, mid_override := NAN) -> void:
	var floor_y := -h * 0.5
	# In a recess the heap sits behind the wall face; in the brick kit's iron
	# cage it sits in front of it (`mid_override`).
	var mid_z := -d * 0.5 if is_nan(mid_override) else mid_override
	var rx := w * 0.5 - 0.09
	var rz := d * 0.5 - 0.09
	var peak := 0.15
	var loot := Node3D.new()
	loot.name = "Loot"
	niche.add_child(loot)
	# Exactly as many pieces as the cage pays, one currency each -- a heap of a
	# hundred read as far more than the 5-13 it gave. Mostly coins, a few jewels.
	var amount := rng.randi_range(CAGE_PAY_MIN, CAGE_PAY_MAX)
	niche.set_meta("amount", amount)
	var jewels := int(round(float(amount) * 0.25))
	peak = 0.03 + 0.006 * float(amount)
	# A small heap, gathered under the skull rather than strewn over the floor.
	rx *= 0.6
	rz *= 0.7
	for kind in [["coin", amount - jewels], ["jewel", jewels]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = parts[kind[0]]
		mm.instance_count = kind[1]
		for i in kind[1]:
			var a := rng.randf() * TAU
			var s := sqrt(rng.randf())
			var x := cos(a) * s * rx
			var z := mid_z + sin(a) * s * rz
			var y := floor_y + 0.006 + peak * (1.0 - s * s) * rng.randf_range(0.55, 1.0)
			var basis := Basis.from_euler(Vector3(
				rng.randf_range(-0.7, 0.7), rng.randf() * TAU, rng.randf_range(-0.7, 0.7)))
			if kind[0] == "jewel":
				basis = basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.35))
				y += 0.012
			mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 34.0
		mmi.visibility_range_end_margin = 6.0
		loot.add_child(mmi)
	if parts.has("skull"):
		var skull: Mesh = parts["skull"]
		var box := skull.get_aabb()
		var sc := CAGE_SKULL_WIDTH / maxf(box.size.x, 0.001)
		var mi := _window_part(niche, skull, Vector3(
			rng.randf_range(-0.05, 0.05), floor_y + peak * 0.85 - box.position.y * sc,
			mid_z + rng.randf_range(-0.03, 0.03)))
		mi.scale = Vector3.ONE * sc
		# The skull model faces its +X; a quarter turn back points it out of the
		# cage (it used to sit side-on).
		mi.rotation = Vector3(rng.randf_range(-0.12, 0.08), -PI * 0.5 + rng.randf_range(-0.6, 0.6), rng.randf_range(-0.15, 0.15))
		# bone_cage.gd drops it to the floor once the heap under it is gone.
		mi.name = "Skull"
		mi.set_meta("drop", peak * 0.85)


## --- Skylights --------------------------------------------------------------
##
## A barred opening in a straight corridor's vault, open to the red sky, with
## red light pouring down through it. The hole is real -- `build_modules.py`
## builds a `straight_sky` variant with the roof faces over it deleted and the
## lid laid as a frame round it -- so the sky shows through; everything else is
## dressing in the windows' style.
const SKYLIGHT_KIND := "straight_sky"
## Across the corridor x along it, metres. Must match SKYLIGHT_W / SKYLIGHT_L in
## `build_modules.py`, which cut the hole.
const SKYLIGHT_SIZE := Vector2(1.0, 2.4)
## The vault's underside at the opening, as reported by the build ("vault
## underside at 4.11 m"). The liner reaches just below it, so the cut edge
## of the vault is always behind stone.
const SKYLIGHT_UNDERSIDE := 4.11
## The cut is sliced clean, so the liner only has to read as a stone reveal.
const SKYLIGHT_LINER := 0.2
const BRICK_SKY_UNDERSIDE := 4.95
const BRICK_SKY_TOP := 6.6
## One straight in this many gets one. Deterministic per cell.
const SKYLIGHT_EVERY := 3
## Strong: the pool it throws is 5 m below, among warm torchlight.
const SKYLIGHT_ENERGY := 22.0
const SKYLIGHT_RANGE := 11.0


static func _pick_skylights(out: Built, meshes: Dictionary) -> void:
	out.skylights.clear()
	if not meshes.has(SKYLIGHT_KIND):
		return
	var rng := RandomNumberGenerator.new()
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		# Corridors only: a room's arcade is tees and corners anyway, and its
		# court is already open to the sky.
		if cell.kind != "straight" or cell.room >= 0:
			continue
		# Not under the boss hall: the shaft would open onto its floor's
		# underside rather than the sky.
		if under_boss_hall(out, out.to_world(cell.pos), out.cell_size * 0.5):
			continue
		rng.seed = hash(cell.pos) ^ 0x5c1e
		if rng.randi_range(0, SKYLIGHT_EVERY - 1) == 0:
			out.skylights[cell.pos] = true


## Dresses every skylight cell: a stone liner round the shaft, iron bars across
## it and a red spotlight above it. `density` scales how many are LIT (the
## light is the per-pixel cost); the opening and its bars are always there.
static func place_skylights(parent: Node3D, out: Built, density: float = 1.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ModuleSkylights"
	parent.add_child(holder)

	# The arches' plain dark stone, so the shaft reads as a cut opening rather
	# than as more coursed brick. See place_windows: a BoxMesh carries no
	# vertex colours, so that flag has to come off.
	var stone := _synth_arch_material(1.0).duplicate() as StandardMaterial3D
	stone.vertex_color_use_as_albedo = false
	# Only 2 cm below the vault: any deeper and the liner's outer faces hang
	# below the curve of the vault like a box stuck to the ceiling.
	# The brick vault is far thicker: its inner face is ~4.95 m up beside the
	# opening and its back reaches 6.4 m, so the shaft runs through all of it.
	var underside := BRICK_SKY_UNDERSIDE if brick else SKYLIGHT_UNDERSIDE
	var top := BRICK_SKY_TOP if brick else out.height + 0.35
	var shaft := top - (underside - 0.02)
	var shaft_mid := (underside - 0.02) + shaft * 0.5
	var t := SKYLIGHT_LINER
	# Long sides run the length of the opening; the ends span its width plus
	# both long sides, so the four meet at the corners with no gap.
	var long_side := BoxMesh.new()
	long_side.size = Vector3(t, shaft, SKYLIGHT_SIZE.y + t * 2.0)
	long_side.material = stone
	var end_side := BoxMesh.new()
	end_side.size = Vector3(SKYLIGHT_SIZE.x, shaft, t)
	end_side.material = stone

	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.045, 0.04, 0.04)
	iron.roughness = 0.7
	iron.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var rung := CylinderMesh.new()
	rung.top_radius = 0.03
	rung.bottom_radius = 0.03
	rung.height = SKYLIGHT_SIZE.x
	rung.radial_segments = 8
	rung.material = iron
	var spine := CylinderMesh.new()
	spine.top_radius = 0.035
	spine.bottom_radius = 0.035
	spine.height = SKYLIGHT_SIZE.y
	spine.radial_segments = 8
	spine.material = iron

	var lit_every := maxi(1, int(round(1.0 / maxf(density, 0.05))))
	var placed := 0
	var lit := 0
	for pos in out.skylights:
		var cell: ModuleMaze.Cell = out.cells[pos]
		var sky := Node3D.new()
		sky.position = out.to_world(pos)
		# The module's own turn: its local Z runs along the corridor.
		sky.basis = _cell_basis(cell)
		holder.add_child(sky)

		var across := (SKYLIGHT_SIZE.x + t) * 0.5
		var along := (SKYLIGHT_SIZE.y + t) * 0.5
		_window_part(sky, long_side, Vector3(-across, shaft_mid, 0.0))
		_window_part(sky, long_side, Vector3(across, shaft_mid, 0.0))
		_window_part(sky, end_side, Vector3(0.0, shaft_mid, -along))
		_window_part(sky, end_side, Vector3(0.0, shaft_mid, along))

		# Rungs across the short way, a spine down the middle, just inside the
		# mouth of the shaft so they read against the sky from below.
		var bar_y := underside + 0.08
		for i in 3:
			var z := (float(i) + 1.0) / 4.0 * SKYLIGHT_SIZE.y - SKYLIGHT_SIZE.y * 0.5
			var r := _window_part(sky, rung, Vector3(0.0, bar_y, z))
			r.rotation.z = PI * 0.5
		var s := _window_part(sky, spine, Vector3(0.0, bar_y + 0.06, 0.0))
		s.rotation.x = PI * 0.5

		placed += 1
		if density <= 0.0 or placed % lit_every != 0:
			continue
		# Above the opening, pointing straight down: a pool of red on the floor
		# under the shaft. Shadowless, like every dressing light here, so the
		# roof round the opening does not stop it -- the cone does the shaping.
		var light := SpotLight3D.new()
		light.light_color = WINDOW_COLOUR
		light.light_energy = SKYLIGHT_ENERGY
		light.spot_range = SKYLIGHT_RANGE
		light.spot_angle = 34.0
		light.spot_angle_attenuation = 0.8
		light.spot_attenuation = 0.9
		light.light_specular = 0.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 26.0
		light.distance_fade_length = 8.0
		light.position = Vector3(0.0, top + 0.85, 0.0)
		light.rotation.x = -PI * 0.5
		sky.add_child(light)
		lit += 1

	holder.set_meta("skylight_count", placed)
	holder.set_meta("skylight_lit", lit)
	return holder


static func _window_part(window: Node3D, mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 34.0
	mi.visibility_range_end_margin = 6.0
	window.add_child(mi)
	return mi


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


## Backs every wall that faces the outside of the maze with solid rock, and
## plugs the seam between every pair of neighbouring cells with a filler.
##
## Tripo stone has a ragged foot, so there are small gaps where a wall meets
## the floor. Inside the maze the neighbour's stone is right behind them; on
## the RIM there is nothing, and the same gaps showed the void -- the "large
## missing segments at the bottom of the walls". That reasoning turned out
## not to cover every case: two neighbouring solid walls, or the jambs either
## side of an archway, can BOTH fall short of the cell boundary at once, with
## nothing behind either to hide the gap -- the "gaps between wall pieces" a
## ray probe along cell boundaries confirmed (see
## tools/team_level_seam_probe.py).
##
## Two materials, not one. The rim backing is genuinely never meant to be
## seen -- it faces the void outside the maze -- and stays the flat near-
## black "rock the level is cut from". The interior seam and jamb fillers
## are a different case: they sit INSIDE the walkable maze, where a lead
## review found them standing as visible untextured slabs in front of the
## real jambs. Anywhere one of these can be seen through a gap it now carries
## the same world-triplanar synth_stone the reveals use, so a visible sliver
## reads as more wall, not as a black box.
static func _place_backing(parent: Node3D, out: Built, tint: float) -> void:
	var rim: Array[Transform3D] = []
	var fill: Array[Transform3D] = []
	var jamb_fill: Array[Transform3D] = []
	var seam_count := 0
	var jamb_count := 0
	var half := out.cell_size * 0.5
	for key in out.cells:
		var cell: ModuleMaze.Cell = out.cells[key]
		if cell.court:
			continue
		for side in ModuleMaze.ORDER:
			var step: Vector2i = ModuleMaze.DIRS[side]
			var neighbour: Vector2i = cell.pos + step
			var dir := Vector3(float(step.x), 0.0, float(step.y))
			var has_neighbour: bool = out.cells.has(neighbour) \
				and not out.cells[neighbour].court
			# Once per pair, from the lower-ordered cell -- otherwise every
			# interior seam and jamb would be built twice, doubling the
			# instance count and inviting exactly the z-fight this is meant
			# to prevent.
			var canonical: bool = not (neighbour.x < cell.pos.x
				or (neighbour.x == cell.pos.x and neighbour.y < cell.pos.y))

			if cell.open & side:
				# An open connection: fill the two jamb corners beside the
				# archway, once per pair.
				if not has_neighbour or not canonical:
					continue
				# JAMB_FILL_WIDTH, not a width derived from the archway: see
				# its comment. The crack is a thin sliver right at the cell
				# boundary corner, not the whole archway-edge-to-boundary
				# panel the first version filled (which independent visual
				# review saw standing proud as a wide strip beside every
				# archway). Full height (out.height), not JAMB_FILL_HEIGHT --
				# the escape probe found the crack runs at least up to 3 m
				# with no sign of stopping, and a full-height sliver has no
				# top edge to read as a separate object, unlike a column that
				# stops partway up the wall.
				var jamb_w := JAMB_FILL_WIDTH
				var across := Vector3(dir.z, 0.0, dir.x)
				var mid := out.to_world(cell.pos) + dir * half
				for s: float in [-1.0, 1.0]:
					var offset: Vector3 = across * (half - jamb_w * 0.5) * s
					var basis := Basis().scaled(
						_axis_size(dir, JAMB_FILL_DEPTH, jamb_w, out.height))
					jamb_fill.append(Transform3D(basis,
						mid + offset + Vector3(0.0, out.height * 0.5, 0.0)))
					jamb_count += 1
				continue

			if has_neighbour:
				# Interior seam: both sides of the pair are solid -- the
				# maze's `open` bit is always set on both cells or neither
				# (module_maze.gd carves and joins symmetrically) -- so a
				# full-height, full-width filler closes it from whichever
				# side is short. A small lip (WALL_SEAM_INSET) past the
				# boundary is safe here because WALL_FACE says solid stone
				# starts well before it on a plain wall.
				if not canonical:
					continue
				var near2 := half - WALL_SEAM_INSET
				var basis2 := Basis().scaled(
					_axis_size(dir, SEAM_FILL_DEPTH, out.cell_size, out.height))
				var at2 := out.to_world(cell.pos) + dir * (near2 + SEAM_FILL_DEPTH * 0.5) \
					+ Vector3(0.0, out.height * 0.5, 0.0)
				fill.append(Transform3D(basis2, at2))
				seam_count += 1
				continue

			# Exterior (rim): back it with solid rock, pulled BACKING_INSET
			# inward of the boundary so a wall that does reach exactly to the
			# edge does not sit flush against backing's inner face.
			var basis3 := Basis().scaled(_axis_size(
				dir, BACKING_DEPTH, out.cell_size, out.height + BACKING_DEPTH))
			var at3 := out.to_world(cell.pos) \
				+ dir * (half - BACKING_INSET + BACKING_DEPTH * 0.5) \
				+ Vector3(0.0, (out.height - BACKING_DEPTH) * 0.5, 0.0)
			rim.append(Transform3D(basis3, at3))

	if not rim.is_empty():
		var rim_box := BoxMesh.new()
		rim_box.size = Vector3.ONE
		var rim_mat := StandardMaterial3D.new()
		# Near-black and matte: the rock the level is cut from, never a
		# surface -- and never seen, since it faces the void outside the maze.
		rim_mat.albedo_color = Color(0.035, 0.034, 0.040)
		rim_mat.roughness = 1.0
		rim_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		rim_box.material = rim_mat
		var rim_mm := MultiMesh.new()
		rim_mm.transform_format = MultiMesh.TRANSFORM_3D
		rim_mm.mesh = rim_box
		rim_mm.instance_count = rim.size()
		for i in rim.size():
			rim_mm.set_instance_transform(i, rim[i])
		var rim_mmi := MultiMeshInstance3D.new()
		rim_mmi.name = "RimBacking"
		rim_mmi.multimesh = rim_mm
		rim_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(rim_mmi)
		rim_mmi.set_meta("backing_count", rim.size())

	if not fill.is_empty():
		var fill_box := BoxMesh.new()
		fill_box.size = Vector3.ONE
		fill_box.material = _synth_material(tint)
		var fill_mm := MultiMesh.new()
		fill_mm.transform_format = MultiMesh.TRANSFORM_3D
		fill_mm.mesh = fill_box
		fill_mm.instance_count = fill.size()
		for i in fill.size():
			fill_mm.set_instance_transform(i, fill[i])
		var fill_mmi := MultiMeshInstance3D.new()
		fill_mmi.name = "SeamFill"
		fill_mmi.multimesh = fill_mm
		fill_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(fill_mmi)
		fill_mmi.set_meta("seam_count", seam_count)

	if not jamb_fill.is_empty():
		# The arch's own material, not the wall's synth_stone: a jamb filler
		# sits right beside the bored archway's own reveal (which already
		# carries ARCH_MATERIAL), so any sliver that does show matches the
		# reveal it is next to rather than reading as a separate grey-brick
		# patch (independent visual review).
		var jamb_box := BoxMesh.new()
		jamb_box.size = Vector3.ONE
		jamb_box.material = _synth_arch_material(tint)
		var jamb_mm := MultiMesh.new()
		jamb_mm.transform_format = MultiMesh.TRANSFORM_3D
		jamb_mm.mesh = jamb_box
		jamb_mm.instance_count = jamb_fill.size()
		for i in jamb_fill.size():
			jamb_mm.set_instance_transform(i, jamb_fill[i])
		var jamb_mmi := MultiMeshInstance3D.new()
		jamb_mmi.name = "JambFill"
		jamb_mmi.multimesh = jamb_mm
		jamb_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(jamb_mmi)
		jamb_mmi.set_meta("jamb_count", jamb_count)


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


