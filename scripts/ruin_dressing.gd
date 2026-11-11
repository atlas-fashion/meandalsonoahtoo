extends Node3D

## The dungeon's districts, each dressed as itself (note 176).
##
## The corridors are cut into DISTRICTS -- about one per DISTRICT_CELLS corridor
## cells (13 on the usual maze), grown evenly out from seeds spread as far apart
## as the maze allows (the first at the start) -- and every district has a LOOK,
## no two touching districts the same, each look used twice at most with its
## second district dressed its other way (`_variants`: crimson or blue banners,
## ice or violet crystal, crates or barrels...), so each part of the maze is a
## place of its own:
##
##   OVERGROWN   roots through every wall, round the pillars, over the arches,
##               hanging from the vaults; many of their tips alive (living_root.gd)
##   STOREHOUSE  breakable crates (breakable_crate.gd) stacked along the walls,
##               barrels, hand carts
##   OSSUARY     the dead sat against the walls, skulls, standing caskets,
##               candles burning down among them, candelabra
##   QUESTION    the torture quarter: iron maidens, racks, pillories, tool racks,
##               braziers, hooks and chains from the vaults
##   BANNERS     the old garrison: tattered banners, rugs, chandeliers,
##               candelabra, lecterns
##   CRYSTAL     a crystal seam: clusters growing out of the walls' feet and
##               down from the vaults, giving a cold light
##   GAOL        cages hanging from the vaults, chains in bunches, shackles on
##               the walls with what is left of their prisoners, cage carts
##
## Every district is densest at its heart and thins toward its edges (`_depth`),
## so one runs into the next. Roots, and now and then a crate, turn up a little
## everywhere; all the roots carry the faint gold.
##
## Built once with the level, before the navmesh bake (solid props are carved out
## of it, layer 512, and their floor is marked WALL for spawning through the
## spots `build` returns). Nothing here is saved: crates and living roots are
## whole and alive again in a level built afresh.

const Roots := preload("res://scripts/ruin_roots.gd")
const LivingRoot := preload("res://scripts/living_root.gd")
const Crate := preload("res://scripts/breakable_crate.gd")
const Table := preload("res://scripts/surgical_table.gd")
const ModuleMaze := preload("res://scripts/module_maze.gd")
const BrickLevel := preload("res://scripts/brick_level.gd")
const FLAME_SHADER := preload("res://shaders/torch_flame.gdshader")
const BANNER_SHADER := preload("res://shaders/ruin_banner.gdshader")
const SKELETON := preload("res://models/ossuary_skeleton_rigged.glb")
const SKULL := preload("res://models/skull_worn_ready.glb")
const CRACK := preload("res://textures/surgery_fx_crack.png")
const Vermin := preload("res://scripts/vermin.gd")

enum Look { OVERGROWN, STOREHOUSE, OSSUARY, QUESTION, BANNERS, CRYSTAL, GAOL }
const THEME_NAMES := ["overgrown", "storehouse", "ossuary", "question", "banners", "crystal", "gaol"]

## The Higgsfield pieces (models/surgery/, notes 95-98) used here, and how much
## each glows with its own picture (surgical_table.gd `glow`).
const KIT := "res://models/surgery/%s.glb"
const GLOWS := {"candelabra": 1.2, "chandelier": 1.3, "crystal": 0.75, "brazier": 0.0}

const WALL_FACE := 1.9
const SPRING := 3.0
const CROWN := 5.1
## Solid props: the player's exact layer and the enemies' / navmesh's simple
## one. Not 2 (sight): props never hide what is behind them from a blow.
const PROP_LAYERS := 256 | 512
## How far a prop's light reaches: small, so no unshadowed light gets through a
## wall into the corridor beyond (the walls are a metre thick, 1.9 m out).
const LIGHT_RANGE := 2.3
const LIGHT_FADE := 22.0

var out
var _seed := 0
var _rng := RandomNumberGenerator.new()
## cell -> district index; district -> Look.
var _district := {}
var _themes: Array[int] = []
## District -> 0 or 1: a look's second district is dressed its other way.
var _variants: Array[int] = []
## Corridor cells per district, about.
const DISTRICT_CELLS := 70
## The district being dressed: its look's variant.
var _variant := 0
## cell -> steps to its district's edge.
var _depth := {}
## cell -> {side: Array[Vector2]} stretches of each wall already taken.
var _busy := {}
var _blocked := {}
var _solid: Array = []
var _scenes := {}
var _relief_wall: Roots.Relief
var _relief_pillar: Roots.Relief
var _relief_arch_pos: Roots.Relief
var _relief_arch_neg: Roots.Relief
var _lights: Array[OmniLight3D] = []
var _casters: Array[GeometryInstance3D] = []
var _flame_mat: ShaderMaterial
var _wax_mat: StandardMaterial3D
var _bone_mesh: ArrayMesh
var _dead_mats := {}
var _skeleton_meshes: Array = []
var counts := {}
## Per district: a spot to look at it from, for screenshots and tests.
var samples: Array = []
## Every living root, for tests.
var living: Array = []
## The beetles (vermin.gd).
var _vermin = null


## Builds everything into this node. `blocked`: cells nothing goes in (doors,
## the spawn, hiding carts, holding cells, manholes). `anchors`: Look -> a cell
## that look's district should hold (the morgue's room for the ossuary, the
## surgery's for the question). Returns the solid spots, [{at, half}].
func build(built, blocked: Dictionary, seed_: int, anchors := {}) -> Array:
	out = built
	_seed = seed_
	_blocked = blocked
	add_to_group("ruin_dressing")
	var kit: Dictionary = BrickLevel.meshes(1.0)
	if kit.is_empty():
		return []
	var t0 := Time.get_ticks_msec()
	_relief_wall = Roots.planar_relief(kit["wall"], Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector2(-2.6, 2.6), Vector2(0.0, 3.6))
	_relief_pillar = Roots.pillar_relief(kit["pillar"], 3.3)
	_relief_arch_pos = Roots.planar_relief(kit["arch"], Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector2(-3.35, 3.35), Vector2(0.0, 5.65))
	_relief_arch_neg = Roots.planar_relief(kit["arch"], Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector2(-3.35, 3.35), Vector2(0.0, 5.65))
	var t_relief := Time.get_ticks_msec() - t0
	_districts(anchors)
	_vermin = Vermin.new()
	_vermin.name = "Vermin"
	add_child(_vermin)
	_vermin.setup(_relief_wall, _seed ^ 0xbee71e)
	for key in _district:
		_dress(key)
	counts["beetle nests"] = _vermin.nest_count()
	_apply_graphics()
	var gfx := get_node_or_null("/root/Graphics")
	if gfx != null and gfx.has_signal("changed"):
		gfx.changed.connect(_apply_graphics)
	var sizes := {}
	for d in _district.values():
		sizes[d] = int(sizes.get(d, 0)) + 1
	var parts: Array[String] = []
	for i in _themes.size():
		parts.append("%s %d" % [THEME_NAMES[_themes[i]], int(sizes.get(i, 0))])
	print("[ruins] districts: %s" % ", ".join(parts))
	var tally: Array[String] = []
	for k in counts:
		tally.append("%s %d" % [k, int(counts[k])])
	print("[ruins] %s; %d lights; reliefs %d ms, all %d ms" % [", ".join(tally), _lights.size(), t_relief,
		Time.get_ticks_msec() - t0])
	return _solid


func _count(what: String, n := 1) -> void:
	counts[what] = int(counts.get(what, 0)) + n


# --- Districts ---------------------------------------------------------------------

func _corridor(key: Vector2i) -> bool:
	var cell = out.cells.get(key)
	return cell != null and cell.room < 0 and not cell.court and not cell.hall


func _neighbours(key: Vector2i) -> Array[Vector2i]:
	var cell = out.cells[key]
	var list: Array[Vector2i] = []
	for side in ModuleMaze.ORDER:
		if cell.open & side:
			var other: Vector2i = key + ModuleMaze.DIRS[side]
			if _corridor(other):
				list.append(other)
	return list


## Steps from `from` to every corridor cell it reaches.
func _bfs(from: Array) -> Dictionary:
	var dist := {}
	var queue: Array = []
	for f in from:
		dist[f] = 0
		queue.append(f)
	var head := 0
	while head < queue.size():
		var k: Vector2i = queue[head]
		head += 1
		for n in _neighbours(k):
			if not dist.has(n):
				dist[n] = int(dist[k]) + 1
				queue.append(n)
	return dist


func _districts(anchors: Dictionary) -> void:
	var cells: Array[Vector2i] = []
	for key in out.cells:
		if _corridor(key):
			cells.append(key)
	if cells.is_empty():
		return
	cells.sort()
	# The first seed at the start.
	var spawn_cell: Vector2i = out.spawn_door.get("cell", cells[0])
	if not _corridor(spawn_cell):
		spawn_cell = _nearest_cell(cells, out.to_world(spawn_cell))
	# Seeds spread out: each next one the cell furthest (in steps) from all
	# the others. About one district per DISTRICT_CELLS corridor cells, every
	# look at least once.
	var seeds: Array = [spawn_cell]
	var dist := _bfs(seeds)
	var count := clampi(cells.size() / DISTRICT_CELLS, mini(Look.size(), cells.size()), Look.size() * 2)
	while seeds.size() < count:
		var best: Vector2i = seeds[0]
		var best_d := -1
		for k in cells:
			# Only cells the start reaches: one cut off would seed a district of
			# a handful of cells.
			if not dist.has(k):
				continue
			var d := int(dist[k])
			if d > best_d and not seeds.has(k):
				best_d = d
				best = k
		if best_d <= 0:
			break
		seeds.append(best)
		var more := _bfs([best])
		for k in more:
			dist[k] = mini(int(dist.get(k, 1 << 20)), int(more[k]))
	# Grown evenly: the smallest district takes the next step, so a seed in a
	# far corner does not end up with a handful of cells and the start's with
	# half the maze.
	var owner := {}
	var fronts: Array = []
	var heads: Array[int] = []
	var sizes: Array[int] = []
	for i in seeds.size():
		owner[seeds[i]] = i
		fronts.append([seeds[i]])
		heads.append(0)
		sizes.append(1)
	while true:
		var pick := -1
		for i in seeds.size():
			if heads[i] < (fronts[i] as Array).size() and (pick < 0 or sizes[i] < sizes[pick]):
				pick = i
		if pick < 0:
			break
		var k: Vector2i = fronts[pick][heads[pick]]
		heads[pick] += 1
		for n in _neighbours(k):
			if not owner.has(n):
				owner[n] = pick
				(fronts[pick] as Array).append(n)
				sizes[pick] += 1
	# Cut off from every seed (a passage dug alone): the nearest district.
	for k in cells:
		if not owner.has(k):
			var near := _nearest_cell(seeds, out.to_world(k))
			owner[k] = owner[near]
	_district = owner
	# Which districts touch.
	var touching := {}
	for k in cells:
		for n in _neighbours(k):
			if owner[n] != owner[k]:
				touching[Vector2i(owner[k], owner[n])] = true
	# Looks: the start's district is the gaol (the player wakes in a cell); the
	# ossuary and the question go where they are anchored when they can; then
	# each district the look used least so far that none of its neighbours
	# has, ties drawn from the seed. A look's second district is its variant 1.
	_themes.resize(seeds.size())
	_themes.fill(-1)
	_variants.resize(seeds.size())
	_variants.fill(0)
	var used: Array[int] = []
	used.resize(Look.size())
	used.fill(0)
	_themes[0] = Look.GAOL
	used[Look.GAOL] = 1
	for t in anchors:
		var at: Vector2i = anchors[t]
		var near := _nearest_cell(cells, out.to_world(at))
		var d: int = owner.get(near, -1)
		if d > 0 and _themes[d] < 0 and used[t] == 0:
			_themes[d] = t
			used[t] = 1
	_rng.seed = _seed ^ 0x7275696e
	for i in seeds.size():
		if _themes[i] >= 0:
			continue
		var order: Array[int] = []
		for t in Look.size():
			order.append(t)
		_shuffle(order)
		var best := -1
		for t in order:
			var clash := false
			for j in seeds.size():
				if _themes[j] == t and (touching.has(Vector2i(i, j)) or touching.has(Vector2i(j, i))):
					clash = true
					break
			if clash:
				continue
			if best < 0 or used[t] < used[best]:
				best = t
		if best < 0:
			best = order[0]
		_themes[i] = best
		_variants[i] = used[best] % 2
		used[best] += 1
	# How deep in its district each cell lies.
	var edge: Array = []
	for k in cells:
		for n in _neighbours(k):
			if owner[n] != owner[k]:
				edge.append(k)
				break
	var depth := _bfs(edge) if not edge.is_empty() else {}
	for k in cells:
		_depth[k] = int(depth.get(k, 6))
	# A spot to look at each district from: its deepest straight.
	for i in seeds.size():
		var best: Vector2i = seeds[i]
		var best_d := -1
		for k in cells:
			if owner[k] != i or out.cells[k].kind != "straight" or _blocked.has(k):
				continue
			var score := mini(int(_depth[k]), 4) * 10 + _free_walls(k).size()
			if score > best_d:
				best_d = score
				best = k
		samples.append({"theme": "%s%d" % [THEME_NAMES[_themes[i]], _variants[i]], "cell": best})


func _nearest_cell(cells: Array, world: Vector3) -> Vector2i:
	var best: Vector2i = cells[0]
	var best_d := INF
	for k in cells:
		var p: Vector3 = out.to_world(k)
		var d := Vector2(p.x - world.x, p.z - world.z).length_squared()
		if d < best_d:
			best_d = d
			best = k
	return best


func theme_at(world: Vector3) -> String:
	var key := Vector2i(roundi((world.x - out.origin.x) / out.cell_size), roundi((world.z - out.origin.z) / out.cell_size))
	if not _district.has(key):
		return ""
	return THEME_NAMES[_themes[int(_district[key])]]


# --- One cell ----------------------------------------------------------------------

func _dir(side: int) -> Vector3:
	var s: Vector2i = ModuleMaze.DIRS[side]
	return Vector3(float(s.x), 0.0, float(s.y))


## A closed side's wall frame: its face's foot, x along it, +z out into the cell.
func _wall_xf(key: Vector2i, side: int) -> Transform3D:
	var d := _dir(side)
	var into := -d
	return Transform3D(Basis(Vector3.UP, atan2(into.x, into.z)), out.to_world(key) + d * WALL_FACE)


## The walls of `key` free to dress: closed, no torch, no iron cage, not an
## end wall's door.
func _free_walls(key: Vector2i) -> Array[int]:
	var cell = out.cells[key]
	var cages: Dictionary = out.get_meta("cage_walls", {})
	var clutter: Dictionary = out.get_meta("clutter_walls", {})
	var walls: Array[int] = []
	for side in ModuleMaze.ORDER:
		if cell.open & side:
			continue
		if out.torch_cells.has(key) and int(out.torch_cells[key]) == side:
			continue
		if cages.has(key) and side in cages[key]:
			continue
		if clutter.has(key) and side in clutter[key]:
			continue
		walls.append(side)
	return walls


## The walls of `key` roots may grow on: every closed one but an iron cage's
## (a torch's wall keeps its middle clear, `_wall_roots`; the clutter's wood
## stands in front of them).
func _root_walls(key: Vector2i) -> Array[int]:
	var cell = out.cells[key]
	var cages: Dictionary = out.get_meta("cage_walls", {})
	var walls: Array[int] = []
	for side in ModuleMaze.ORDER:
		if cell.open & side:
			continue
		if cages.has(key) and side in cages[key]:
			continue
		walls.append(side)
	_shuffle(walls)
	return walls


## How far along a wall things may stand: clear of the junction pillars.
func _wall_span(key: Vector2i) -> float:
	# A beacon hall's wall runs on between its pilasters (1.9 m each side).
	if out.cells[key].hall:
		return 1.7
	return 2.3 if out.cells[key].kind == "straight" else 1.25


## Takes the stretch [x - half, x + half] of a wall if it is free.
func _reserve(key: Vector2i, side: int, x: float, half: float) -> bool:
	if not _busy.has(key):
		_busy[key] = {}
	if not _busy[key].has(side):
		_busy[key][side] = []
	for span in _busy[key][side]:
		if x + half > span.x and x - half < span.y:
			return false
	_busy[key][side].append(Vector2(x - half, x + half))
	return true


## A free place on wall (`key`, `side`) for something `half` wide: x along it, or
## NAN if none could be found.
func _spot(key: Vector2i, side: int, half: float, tries := 6) -> float:
	var span := _wall_span(key) - half
	if span < 0.0:
		return NAN
	for i in tries:
		var x := _rng.randf_range(-span, span)
		if _reserve(key, side, x, half + 0.12):
			return x
	return NAN


func _dress(key: Vector2i) -> void:
	if _blocked.has(key):
		return
	var cell = out.cells[key]
	_rng.seed = hash(key) ^ _seed ^ 0x5eed
	var theme: int = _themes[int(_district[key])]
	_variant = _variants[int(_district[key])]
	var depth := int(_depth.get(key, 0))
	# 0.5 at the district's edge, 1 three cells in.
	var core := clampf(0.5 + float(depth) * 0.17, 0.5, 1.0)
	var walls := _free_walls(key)
	_shuffle(walls)
	match theme:
		Look.OVERGROWN:
			_overgrown(key, cell, walls, core)
		Look.STOREHOUSE:
			_storehouse(key, cell, walls, core)
		Look.OSSUARY:
			_ossuary(key, cell, walls, core)
		Look.QUESTION:
			_question(key, cell, walls, core)
		Look.BANNERS:
			_banners(key, cell, walls, core)
		Look.CRYSTAL:
			_crystal(key, cell, walls, core)
		Look.GAOL:
			_gaol(key, cell, walls, core)
	# Roots everywhere now and then, and the odd crate.
	var root_walls := _root_walls(key)
	if theme != Look.OVERGROWN and not root_walls.is_empty() and _rng.randf() < 0.34:
		var strands: Array = []
		var live: Array = []
		var side: int = root_walls[0]
		_wall_roots(key, side, _rng.randi_range(4, 8), 1 if _rng.randf() < 0.45 else 0, strands, live)
		_root_mesh(key, strands, live)
	if theme != Look.STOREHOUSE and not walls.is_empty() and _rng.randf() < 0.05:
		_crates(key, walls[_rng.randi_range(0, walls.size() - 1)], 1)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


# --- Roots -------------------------------------------------------------------------

## `count` roots down wall (`key`, `side`), `tips` of them living, into
## `strands` (world space) and `live` ([base, wall normal, r0]).
func _wall_roots(key: Vector2i, side: int, count: int, tips: int, strands: Array, live: Array) -> void:
	var xf := _wall_xf(key, side)
	var mine: Array = []
	var ends: Array = []
	# A torch's pilaster stands in the middle of its wall: kept clear.
	var band := 0.75 if out.torch_cells.has(key) and int(out.torch_cells[key]) == side else 0.0
	for s in Roots.wall_strands(_rng, _relief_wall, count, tips, ends, band):
		var st: Roots.Strand = s
		# Off the junction pillars' faces in a junction.
		if out.cells[key].kind != "straight" and absf(st.pts[0].x) > 1.5:
			continue
		mine.append(st.transformed(xf))
	# Roots that have burst out through the masonry itself, mid-wall: thick
	# where they come out of the stone, the brick shattered round them.
	var span := 2.2 if out.cells[key].kind == "straight" else 1.2
	for b in Roots.burst_strands(_rng, _relief_wall, maxi(count / 4, 1) if count >= 4 else 0, span, band):
		var st: Roots.Strand = b
		mine.append(st.transformed(xf))
		_crack(xf, st.pts[0], st.radii[0])
	strands.append_array(mine)
	for e in ends:
		var p: Vector3 = e[0]
		if out.cells[key].kind != "straight" and absf(p.x) > 1.4:
			continue
		live.append([xf * p, xf.basis.z, float(e[2])])
	# Beetles in the roots (vermin.gd).
	if count >= 4 and _vermin != null:
		_vermin.add_nest(xf, _rng.randi_range(5, 12), -span, span)


## Shattered brick where a root broke out of the wall at `at` (the wall's own
## frame): the crack picture projected into the face.
func _crack(xf: Transform3D, at: Vector3, r: float) -> void:
	var d := Decal.new()
	d.name = "RootCrack"
	d.texture_albedo = CRACK
	var s := clampf(r * 7.0, 0.5, 1.2)
	d.size = Vector3(s, 0.6, s)
	d.cull_mask = 1
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.distance_fade_enabled = true
	d.distance_fade_begin = 30.0
	d.distance_fade_length = 6.0
	add_child(d)
	# A decal projects down its -Y: turned so that is into the wall (-Z).
	d.transform = Transform3D(xf.basis * Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, _rng.randf() * TAU),
		xf * Vector3(at.x, at.y, 0.1))
	_count("root cracks")


## The cell's roots as one mesh, its living tips beside it.
func _root_mesh(key: Vector2i, strands: Array, live: Array) -> void:
	if strands.is_empty():
		return
	var mesh := Roots.build_mesh(strands)
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Roots"
	mi.set_meta("cell", key)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 60.0
	mi.visibility_range_end_margin = 6.0
	add_child(mi)
	_count("root strands", strands.size())
	var alive := 0
	for l in live:
		var tip := LivingRoot.make(l[0], l[1], float(l[2]), hash(key) + alive)
		tip.cluster = mi
		add_child(tip)
		living.append(tip)
		alive += 1
	mi.set_meta("alive", alive)
	_count("living roots", alive)


func _overgrown(key: Vector2i, cell, walls: Array[int], core: float) -> void:
	var strands: Array = []
	var live: Array = []
	# Variant 0: the walls buried in roots. Variant 1: fewer on the walls, a
	# curtain of them hanging from the vaults, and more of them alive.
	var alive := 0.85 if _variant == 0 else 0.95
	var tips_left := 1 if _rng.randf() < alive * core else 0
	if cell.kind == "straight" and _rng.randf() < (alive - 0.35) * core:
		tips_left += 1
	for side in _root_walls(key):
		var t := 1 if tips_left > 0 else 0
		tips_left -= t
		var n := _rng.randf_range(11.0, 17.0) if _variant == 0 else _rng.randf_range(6.0, 10.0)
		_wall_roots(key, side, roundi(n * core), t, strands, live)
	# Round the junction pillars.
	if cell.kind != "straight":
		for px: float in [-1.0, 1.0]:
			for pz: float in [-1.0, 1.0]:
				if _rng.randf() > 0.75 * core:
					continue
				var at: Vector3 = out.to_world(key) + Vector3(px, 0.0, pz) * BrickLevel.PILLAR_AT
				for s in Roots.pillar_strands(_rng, _relief_pillar, _rng.randi_range(2, 4), BrickLevel.PILLAR_HEIGHT):
					strands.append((s as Roots.Strand).transformed(Transform3D(Basis(), at)))
	# Over the arches.
	for side in ModuleMaze.ORDER:
		if not (cell.open & side) or _rng.randf() > 0.7 * core:
			continue
		var arch := _arch_frame(key, side)
		if arch.is_empty():
			continue
		var relief: Roots.Relief = _relief_arch_pos if arch["sign"] > 0.0 else _relief_arch_neg
		for s in Roots.arch_strands(_rng, relief, _rng.randi_range(1, 3), arch["sign"]):
			strands.append((s as Roots.Strand).transformed(arch["xf"]))
	# Hanging from the vault.
	var hang := _rng.randf_range(7.0, 14.0) if _variant == 0 else _rng.randf_range(14.0, 24.0)
	_hanging_roots(key, cell, roundi(hang * core), strands)
	_root_mesh(key, strands, live)
	_rubble(key, walls, core)


## The arch on the boundary of `key` toward `side`, and which of its faces
## looks into `key`: {xf, sign}; {} if none stands there.
func _arch_frame(key: Vector2i, side: int) -> Dictionary:
	var other: Vector2i = key + ModuleMaze.DIRS[side]
	if not out.cells.has(other):
		return {}
	var a = out.cells[key]
	var b = out.cells[other]
	if a.hall and b.hall:
		return {}
	# brick_level builds each arch from the lower-ordered cell, or from the
	# corridor when the other side is a court; its +Z faces the builder.
	var builder := key
	var target := other
	var mine_first := key.x < other.x or (key.x == other.x and key.y < other.y)
	if not (mine_first or b.court):
		builder = other
		target = key
	var d := Vector3(float(target.x - builder.x), 0.0, float(target.y - builder.y))
	var into := -d
	var xf := Transform3D(Basis(Vector3.UP, atan2(into.x, into.z)), out.to_world(builder) + d * out.cell_size * 0.5)
	return {"xf": xf, "sign": 1.0 if builder == key else -1.0}


## How high the vault's soffit is `across` metres off a straight's axis.
func _vault_at(across: float) -> float:
	var a := clampf(absf(across) / WALL_FACE, 0.0, 1.0)
	return SPRING + (CROWN - SPRING) * sqrt(1.0 - a * a)


func _hanging_roots(key: Vector2i, cell, count: int, strands: Array) -> void:
	if out.skylights.has(key):
		return
	var centre: Vector3 = out.to_world(key)
	var axis := _axis(cell)
	var across := Vector3(axis.z, 0.0, axis.x).abs()
	for i in count:
		var lat := _rng.randf_range(-1.5, 1.5)
		var lon := _rng.randf_range(-2.6, 2.6)
		if cell.kind != "straight":
			lat = _rng.randf_range(-0.7, 0.7)
			lon = _rng.randf_range(-0.7, 0.7)
		var top := _vault_at(lat) + 0.2
		# Over the middle they stop over a head; by the walls they reach lower.
		var lowest := 2.35 if absf(lat) < 1.0 else 1.6
		var length := minf(_rng.randf_range(0.5, 2.6), top - lowest)
		if length < 0.3:
			continue
		var from := centre + axis * lon + across * lat + Vector3(0.0, top, 0.0)
		strands.append(Roots.hanging_strand(_rng, from, length, _rng.randf_range(0.012, 0.045)))


## A straight's axis (an open side's direction); +X for anything else.
func _axis(cell) -> Vector3:
	if cell.kind == "straight":
		for side in ModuleMaze.ORDER:
			if cell.open & side:
				return _dir(side).abs()
	return Vector3(1.0, 0.0, 0.0)


# --- Pieces ------------------------------------------------------------------------

func _scene(name_: String) -> PackedScene:
	if not _scenes.has(name_):
		var path := KIT % name_
		_scenes[name_] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[name_]


## A kit piece at `xf`, `scale_` its size, glowing as GLOWS says. `solid`: a box
## of that size (unscaled, in its own frame, its foot at the origin) on the
## props' layers. `shadow`: it casts (with the props' shadows on).
func _piece(name_: String, xf: Transform3D, scale_ := 1.0, solid := Vector3.ZERO, shadow := true) -> Node3D:
	var scene := _scene(name_)
	if scene == null:
		return null
	var piece: Node3D = scene.instantiate()
	piece.name = name_.capitalize().replace(" ", "")
	add_child(piece)
	piece.transform = Transform3D(xf.basis.scaled(Vector3.ONE * scale_) if scale_ != 1.0 else xf.basis, xf.origin)
	Table.grade(piece)
	Table.glow(piece, float(GLOWS.get(name_, 0.0)))
	for node in piece.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		g.visibility_range_end = 60.0
		g.visibility_range_end_margin = 6.0
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shadow:
			_casters.append(g)
	if solid != Vector3.ZERO:
		_solid_box(xf, solid * scale_)
	_count(name_)
	return piece


## A solid box `size` big standing at `xf` (its foot's middle).
func _solid_box(xf: Transform3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "PropCollision"
	body.collision_layer = PROP_LAYERS
	body.collision_mask = 0
	add_child(body)
	body.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(cs)
	_solid.append({"at": xf.origin, "half": Vector2(size.x, size.z) * 0.5})


## The frame for something standing against wall (`key`, `side`) at `x` along
## it, its back `back` off the face, turned to face into the cell.
func _against(key: Vector2i, side: int, x: float, back: float, turn := 0.0) -> Transform3D:
	var w := _wall_xf(key, side)
	return Transform3D(w.basis * Basis(Vector3.UP, turn), w * Vector3(x, 0.0, back))


## A small warm or cold light, no shadow, short reach (see LIGHT_RANGE).
func _light(at: Vector3, colour: Color, energy: float, reach := LIGHT_RANGE) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "PropLight"
	l.light_color = colour
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_volumetric_fog_energy = 0.0
	l.light_specular = 0.4
	l.distance_fade_enabled = true
	l.distance_fade_begin = LIGHT_FADE
	l.distance_fade_length = 6.0
	l.set_meta("energy", energy)
	l.set_meta("phase", _rng.randf() * 100.0)
	add_child(l)
	l.global_position = at
	_lights.append(l)
	return l


# --- Storehouse --------------------------------------------------------------------

func _storehouse(key: Vector2i, cell, walls: Array[int], core: float) -> void:
	var used := 0
	for side in walls:
		if used >= 2 or _rng.randf() > 0.8 * core:
			continue
		used += 1
		# Variant 0 mostly crates; variant 1 the barrel store, carts left about.
		var roll := _rng.randf()
		if roll < (0.62 if _variant == 0 else 0.38):
			_crates(key, side, _rng.randi_range(1, 4))
		elif roll < (0.82 if _variant == 0 else 0.75):
			var x := _spot(key, side, 0.85)
			if not is_nan(x):
				_piece("barrels", _against(key, side, x, 0.8, PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0)),
					0.72, Vector3(2.0, 1.1, 2.1) * 0.9)
		else:
			var x := _spot(key, side, 0.95)
			if not is_nan(x):
				_piece("handcart", _against(key, side, x, 0.6, _rng.randf_range(-0.12, 0.12)), 1.0,
					Vector3(1.8, 1.0, 1.0))
				if _rng.randf() < 0.5:
					_crates(key, side, 1)
	# A crate or two set down out from the wall now and then.
	if cell.kind != "straight" and _rng.randf() < 0.3 * core:
		var at: Vector3 = out.to_world(key) + Vector3(_rng.randf_range(-0.9, 0.9), 0.0, _rng.randf_range(-0.9, 0.9))
		_crate_at(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), at), _rng.randi_range(0, 3), null)


## `n` breakable crates along wall (`key`, `side`), now and then one stacked.
func _crates(key: Vector2i, side: int, n: int) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 3:
		tries += 1
		var kind := _rng.randi_range(0, Crate.SIZES.size() - 1)
		var size: Vector3 = Crate.SIZES[kind]
		var x := _spot(key, side, size.x * 0.5 + 0.05, 3)
		if is_nan(x):
			continue
		var xf := _against(key, side, x, size.z * 0.5 + 0.08, _rng.randf_range(-0.18, 0.18))
		var base := _crate_at(xf, kind, null)
		placed += 1
		# Stacked: a smaller one on top, turned a little.
		if _rng.randf() < 0.35 and kind != 3:
			var top_kind := 3
			var top_xf := Transform3D(xf.basis * Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)),
				xf.origin + Vector3(0.0, size.y + 0.026, 0.0))
			_crate_at(top_xf, top_kind, base)


func _crate_at(xf: Transform3D, kind: int, under: Node3D) -> Node3D:
	var c := Crate.make(kind, xf, hash(xf.origin))
	if under != null:
		c.set("resting_on", under)
	add_child(c)
	if under == null:
		var s: Vector3 = Crate.SIZES[kind]
		_solid.append({"at": xf.origin, "half": Vector2(s.x, s.z) * 0.5})
	_count("crates")
	return c


## The clutter's crates (brick_level.place_clutter), made breakable.
func clutter_crates(list: Array) -> void:
	for xf in list:
		_crate_at(xf, 0, null)


# --- Ossuary -----------------------------------------------------------------------

func _ossuary(key: Vector2i, cell, walls: Array[int], core: float) -> void:
	var lit := false
	for side in walls:
		# Whole walls turned to burial walls: the morgue's catacomb facade
		# (the kit's `wall_loculi`), the dead wrapped in their niches.
		if cell.kind == "straight" and _rng.randf() < 0.45 * core and _reserve(key, side, 0.0, 2.0):
			_loculi(key, side)
			if _rng.randf() < 0.7:
				lit = _candles(_against(key, side, _rng.randf_range(-1.4, 1.4), 0.45), _rng.randi_range(3, 6), not lit) or lit
			continue
		if _rng.randf() > 0.75 * core:
			continue
		# Variant 0 the dead sat among their candles; variant 1 the coffins
		# stood on end, candelabra between them.
		var roll := _rng.randf()
		if roll < (0.38 if _variant == 0 else 0.16):
			var x := _spot(key, side, 0.45)
			if is_nan(x):
				continue
			_seated_dead(_against(key, side, x, 0.0))
			if _rng.randf() < 0.6:
				lit = _candles(_against(key, side, x + (0.62 if _rng.randf() < 0.5 else -0.62), 0.22),
					_rng.randi_range(3, 6), not lit) or lit
		elif roll < (0.62 if _variant == 0 else 0.72):
			var x := _spot(key, side, 0.5)
			if is_nan(x):
				continue
			var casket := _piece("casket", _against(key, side, x, 0.36, _rng.randf_range(-0.08, 0.08)), 1.0,
				Vector3(0.9, 2.3, 0.6))
			if casket != null and _rng.randf() < 0.5:
				var x2 := _spot(key, side, 0.4)
				if not is_nan(x2):
					_piece("candelabra", _against(key, side, x2, 0.42), 0.85, Vector3(0.5, 1.8, 0.5), false)
					if not lit:
						lit = true
						_light(_against(key, side, x2, 0.6) * Vector3(0.0, 1.85, 0.0), Color(1.0, 0.62, 0.3), 0.9)
		elif roll < 0.82:
			var x := _spot(key, side, 0.55)
			if is_nan(x):
				continue
			_skull_pile(_against(key, side, x, 0.28))
			lit = _candles(_against(key, side, x, 0.5), _rng.randi_range(4, 8), not lit) or lit
		else:
			var x := _spot(key, side, 0.6)
			if is_nan(x):
				continue
			_bones(_against(key, side, x, 0.45), _rng.randi_range(4, 8))
	# Bones about the floor.
	if _rng.randf() < 0.5 * core:
		var c: Vector3 = out.to_world(key)
		_bones(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), c + Vector3(_rng.randf_range(-1.0, 1.0), 0.0,
			_rng.randf_range(-1.0, 1.0))), _rng.randi_range(2, 4))


## A catacomb burial wall standing on wall (`key`, `side`), its back on the
## brick, its front 0.86 m out (as the morgue stands them, morgue.gd `_loculi`).
const LOCULI_DEPTH := 0.86
const LOCULI_LEN := 3.9
const LOCULI_HEIGHT := 2.82


func _loculi(key: Vector2i, side: int) -> void:
	var mesh: Mesh = BrickLevel.standalone("wall_loculi")
	if mesh == null:
		return
	var w := _wall_xf(key, side)
	var into := -w.basis.z
	var b := Basis.looking_at(into, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "BurialWall"
	mi.mesh = mesh
	mi.visibility_range_end = 60.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# The kit piece's origin is on its front face.
	mi.transform = Transform3D(b, w.origin - into * LOCULI_DEPTH)
	_casters.append(mi)
	_solid_box(Transform3D(w.basis, w.origin + w.basis.z * (LOCULI_DEPTH * 0.5)),
		Vector3(LOCULI_LEN - 0.15, LOCULI_HEIGHT, LOCULI_DEPTH))
	_count("burial walls")


## The dead sat against a wall (`xf` at the wall's foot, facing out): the rigged
## skeleton posed slumped once per pose and baked to a still mesh, then shared.
func _seated_dead(xf: Transform3D) -> void:
	var mesh := _seated_mesh(_rng.randi_range(0, 2))
	if _vermin != null and _rng.randf() < 0.6:
		_vermin.add_nest(xf, _rng.randi_range(3, 7), -0.7, 0.7)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "SeatedDead"
	mi.mesh = mesh
	mi.material_override = _dead_material()
	mi.visibility_range_end = 50.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_casters.append(mi)
	add_child(mi)
	var aabb := mesh.get_aabb()
	# Back to the wall, sat on the floor.
	var s := 0.94
	mi.transform = Transform3D((xf.basis * Basis(Vector3.UP, _rng.randf_range(-0.25, 0.25))).scaled(Vector3.ONE * s),
		xf * Vector3(0.0, -aabb.position.y * s, -aabb.position.z * s + 0.02))
	# Its legs out across the floor: walked round, not through.
	_solid_box(xf * Transform3D(Basis(), Vector3(0.0, 0.0, 0.45)), Vector3(0.65, 0.5, 0.9))
	_count("seated dead")


## The skeleton sat on the floor, legs out, back against the wall, head fallen
## forward or aside, arms hanging: posed by world turns of its bones (+Z is its
## front, +Y up, X across), baked once per `pose` and cached.
func _seated_mesh(pose: int) -> Mesh:
	while _skeleton_meshes.size() <= pose:
		_skeleton_meshes.append(null)
	if _skeleton_meshes[pose] != null:
		return _skeleton_meshes[pose]
	var model: Node3D = SKELETON.instantiate()
	add_child(model)
	var sk: Skeleton3D = null
	var found := model.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		sk = found[0]
	var skin: MeshInstance3D = null
	for n in model.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).skin != null or not (n as MeshInstance3D).skeleton.is_empty():
			skin = n
			break
	if sk == null or skin == null:
		model.queue_free()
		return null
	var r := RandomNumberGenerator.new()
	r.seed = 4411 + pose * 977
	var spread: float = [0.12, 0.3, -0.05][pose]
	var knee_l: float = [0.95, 0.45, 1.35][pose]
	var knee_r: float = [0.55, 1.2, 0.3][pose]
	var lean: float = [0.35, 0.55, 0.15][pose]
	var head_fwd: float = [0.7, 0.45, 0.9][pose]
	var head_side: float = [0.35, -0.55, 0.1][pose]
	# Legs out in front: the thighs forward, the shins back down a way.
	_turn(sk, &"thigh.L", Vector3.RIGHT, -1.45)
	_turn(sk, &"thigh.L", Vector3.UP, spread)
	_turn(sk, &"shin.L", Vector3.RIGHT, knee_l)
	_turn(sk, &"thigh.R", Vector3.RIGHT, -1.45)
	_turn(sk, &"thigh.R", Vector3.UP, -spread * 0.7)
	_turn(sk, &"shin.R", Vector3.RIGHT, knee_r)
	_turn(sk, &"foot.L", Vector3.RIGHT, -0.6)
	_turn(sk, &"foot.R", Vector3.RIGHT, -0.6)
	# Slumped forward over itself.
	_turn(sk, &"spine.01", Vector3.RIGHT, lean * 0.5)
	_turn(sk, &"spine.02", Vector3.RIGHT, lean * 0.5)
	_turn(sk, &"neck", Vector3.RIGHT, head_fwd * 0.4)
	_turn(sk, &"head", Vector3.RIGHT, head_fwd * 0.6)
	_turn(sk, &"head", Vector3.FORWARD, head_side)
	# Arms hanging, the hands in the lap or on the floor.
	for s: String in ["L", "R"]:
		var sgn := 1.0 if s == "L" else -1.0
		_aim(sk, StringName("upper_arm." + s), Vector3(sgn * 0.25, -1.0, 0.25 + r.randf() * 0.2))
		_aim(sk, StringName("forearm." + s), Vector3(sgn * 0.1, -0.6, 0.8 + r.randf() * 0.3))
	if sk.has_method("force_update_all_bone_transforms"):
		sk.call("force_update_all_bone_transforms")
	var mesh: ArrayMesh = skin.bake_mesh_from_current_skeleton_pose()
	model.queue_free()
	_skeleton_meshes[pose] = mesh
	return mesh


## Turns bone `name_` by `angle` about `axis` (the skeleton's own frame) at its
## joint, carrying its children with it.
func _turn(sk: Skeleton3D, name_: StringName, axis: Vector3, angle: float) -> void:
	var b := sk.find_bone(name_)
	if b < 0:
		return
	var parent := sk.get_bone_parent(b)
	var pg := sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var g := sk.get_bone_global_pose(b)
	var want := Basis(axis.normalized(), angle) * g.basis
	sk.set_bone_pose_rotation(b, (pg.basis.inverse() * want).get_rotation_quaternion())


## Turns bone `name_` so it points along `dir` (the skeleton's frame).
func _aim(sk: Skeleton3D, name_: StringName, dir: Vector3) -> void:
	var b := sk.find_bone(name_)
	if b < 0:
		return
	var g := sk.get_bone_global_pose(b)
	var now := g.basis.y.normalized()
	var want := dir.normalized()
	var axis := now.cross(want)
	if axis.length_squared() < 1e-8:
		return
	_turn(sk, name_, axis, now.signed_angle_to(want, axis.normalized()))


func _dead_material() -> Material:
	if _dead_mats.has("body"):
		return _dead_mats["body"]
	var model: Node3D = SKELETON.instantiate()
	var m: Material = null
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := (n as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			var src := mesh.surface_get_material(0) as BaseMaterial3D
			if src != null:
				var d := src.duplicate() as BaseMaterial3D
				d.emission_enabled = false
				d.albedo_color = d.albedo_color * Color(0.72, 0.68, 0.62)
				m = d
				break
	model.free()
	_dead_mats["body"] = m
	return m


func _skull_pile(xf: Transform3D) -> void:
	for i in _rng.randi_range(3, 6):
		var skull: Node3D = SKULL.instantiate()
		add_child(skull)
		var s := _rng.randf_range(0.16, 0.2)
		var off := Vector3(_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.15, 0.2))
		var lift := s * 0.5 + (0.12 if i >= 3 else 0.0)
		skull.transform = Transform3D(xf.basis * Basis(Vector3.UP, _rng.randf_range(-0.8, 0.8))
			* Basis(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3)) * Basis.from_scale(Vector3.ONE * s),
			xf * (off + Vector3(0.0, lift, 0.0)))
		for g in skull.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(g as GeometryInstance3D).visibility_range_end = 40.0
	_count("skull piles")
	_bones(xf, _rng.randi_range(2, 4))


## Loose long bones on the floor, about `xf`.
func _bones(xf: Transform3D, n: int) -> void:
	if _bone_mesh == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.46, 0.38)
		m.roughness = 0.85
		var long := CylinderMesh.new()
		long.top_radius = 0.016
		long.bottom_radius = 0.02
		long.height = 0.4
		long.radial_segments = 6
		long.rings = 1
		var knob := SphereMesh.new()
		knob.radius = 0.03
		knob.height = 0.055
		knob.radial_segments = 6
		knob.rings = 3
		# One mesh: the shaft and its two knuckles.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(long, 0, Transform3D())
		st.append_from(knob, 0, Transform3D(Basis(), Vector3(0.0, 0.2, 0.0)))
		st.append_from(knob, 0, Transform3D(Basis(), Vector3(0.0, -0.2, 0.0)))
		_bone_mesh = st.commit()
		_bone_mesh.surface_set_material(0, m)
	for i in n:
		var mi := MeshInstance3D.new()
		mi.name = "Bone"
		mi.mesh = _bone_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 30.0
		add_child(mi)
		var p := xf * Vector3(_rng.randf_range(-0.45, 0.45), 0.022, _rng.randf_range(-0.25, 0.3))
		mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.FORWARD, PI * 0.5), p)
	_count("bones", n)


## Candles burning down on the floor about `xf` (its foot): `n` of them, each a
## wax stub with its own small flame card; with `light`, one small light for
## the group. Returns whether it made a light.
func _candles(xf: Transform3D, n: int, light: bool) -> bool:
	if _wax_mat == null:
		var w := StandardMaterial3D.new()
		w.albedo_color = Color(0.78, 0.72, 0.6)
		w.roughness = 0.55
		w.emission_enabled = true
		w.emission = Color(1.0, 0.55, 0.2)
		w.emission_energy_multiplier = 0.06
		_wax_mat = w
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = FLAME_SHADER
		_flame_mat.set_shader_parameter("brightness", 1.5)
	var flame_quad := QuadMesh.new()
	flame_quad.size = Vector2(0.045, 0.085)
	flame_quad.material = _flame_mat
	var top := 0.0
	# The stubs all one mesh about the group's foot; each flame its own card
	# (the flame shader turns each card to the camera about its own origin).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var h := _rng.randf_range(0.06, 0.3)
		var r := _rng.randf_range(0.018, 0.034)
		var stub := CylinderMesh.new()
		stub.top_radius = r * 0.92
		stub.bottom_radius = r * 1.15
		stub.height = h
		stub.radial_segments = 8
		stub.rings = 1
		var local := Vector3(_rng.randf_range(-0.32, 0.32), 0.0, _rng.randf_range(-0.14, 0.14))
		var at := xf * local
		st.append_from(stub, 0, Transform3D(Basis(), local + Vector3(0.0, h * 0.5, 0.0)))
		# Some burnt out.
		if _rng.randf() < 0.8:
			var f := MeshInstance3D.new()
			f.mesh = flame_quad
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			f.visibility_range_end = 35.0
			f.set_instance_shader_parameter("seed", _rng.randf() * 100.0)
			f.set_instance_shader_parameter("intensity", _rng.randf_range(0.8, 1.0))
			add_child(f)
			f.global_position = at + Vector3(0.0, h + 0.035, 0.0)
		top = maxf(top, h)
	var stubs := MeshInstance3D.new()
	stubs.name = "Candles"
	stubs.mesh = st.commit()
	stubs.material_override = _wax_mat
	stubs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stubs.visibility_range_end = 35.0
	add_child(stubs)
	stubs.transform = xf
	_count("candles", n)
	if light:
		_light(xf * Vector3(0.0, top + 0.25, 0.25), Color(1.0, 0.6, 0.28), 0.75, 2.0)
	return light


# --- The question (torture) --------------------------------------------------------

func _question(key: Vector2i, cell, walls: Array[int], core: float) -> void:
	var big := 0
	# Variant 0 the maidens and racks; variant 1 the pillories and tool racks,
	# more hooks overhead.
	var maiden := 0.4 if _variant == 0 else 0.12
	var rack := 0.72 if _variant == 0 else 0.3
	for side in walls:
		if big >= 1 or _rng.randf() > 0.85 * core:
			continue
		var roll := _rng.randf()
		if roll < maiden:
			var x := _spot(key, side, 0.65)
			if not is_nan(x):
				_piece("maiden", _against(key, side, x, 0.48, _rng.randf_range(-0.1, 0.1)), 1.0, Vector3(1.0, 2.4, 0.9))
				big += 1
		elif roll < rack:
			var x := _spot(key, side, 1.55)
			if not is_nan(x):
				_piece("rack", _against(key, side, x, 0.62, PI * 0.5), 1.0, Vector3(1.1, 1.2, 3.0))
				big += 1
		elif roll < 0.84:
			var x := _spot(key, side, 1.05)
			if not is_nan(x):
				_piece("pillory", _against(key, side, x, 0.75), 1.0, Vector3(2.0, 2.2, 0.5))
				big += 1
		else:
			var x := _spot(key, side, 1.1)
			if not is_nan(x):
				_piece("toolrack", _against(key, side, x, 0.22), 1.0, Vector3(2.2, 1.6, 0.4))
				big += 1
	# A brazier of coals, out from a wall.
	if not walls.is_empty() and _rng.randf() < 0.45 * core:
		var side: int = walls[_rng.randi_range(0, walls.size() - 1)]
		var x := _spot(key, side, 0.5)
		if not is_nan(x):
			var xf := _against(key, side, x, 0.75)
			var b := _piece("brazier", xf, 0.9, Vector3(0.8, 1.4, 0.8))
			if b != null:
				_coals(xf * Vector3(0.0, 1.25, 0.0))
	# Shackles on a wall.
	for side in walls:
		if _rng.randf() < 0.25 * core:
			var x := _spot(key, side, 0.35)
			if not is_nan(x):
				_shackles(key, side, x)
	var hooks := 0.35 if _variant == 0 else 0.7
	_hooks(key, cell, _rng.randi_range(1, 2) if _rng.randf() < hooks * core else 0)


## Glowing coals in a brazier's bowl: an ember disc and a small light.
func _coals(at: Vector3) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.3
	disc.bottom_radius = 0.26
	disc.height = 0.06
	disc.radial_segments = 12
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.04, 0.03)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.32, 0.08)
	m.emission_energy_multiplier = 1.6
	m.roughness = 1.0
	disc.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 45.0
	add_child(mi)
	mi.global_position = at
	_light(at + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.42, 0.16), 1.1, 2.4)


## Hooks on chains from the vault's crown, some with a wrapped body on them.
func _hooks(key: Vector2i, cell, n: int) -> void:
	if out.skylights.has(key):
		return
	var centre: Vector3 = out.to_world(key)
	var axis := _axis(cell)
	var across := Vector3(axis.z, 0.0, axis.x).abs()
	for i in n:
		var lat := _rng.randf_range(-1.0, 1.0)
		var lon := _rng.randf_range(-2.0, 2.0) if cell.kind == "straight" else _rng.randf_range(-0.5, 0.5)
		var top := _vault_at(lat) - 0.05
		var at := centre + axis * lon + across * lat
		# A run of chain down to the hook, which hangs 1.6 m from its top.
		var drop := _rng.randf_range(0.2, 0.9)
		_chain(Vector3(at.x, top, at.z), drop)
		var hook := _piece("hook", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(at.x, top - drop, at.z)),
			1.0, Vector3.ZERO, false)
		if hook != null and absf(lat) > 0.6 and _rng.randf() < 0.45:
			var hang := top - drop - 1.45
			_piece("bundle", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(at.x, hang, at.z)),
				0.9, Vector3.ZERO, false)
			# Hanging down to body height: something to walk round.
			var foot := hang - 1.9 * 0.9
			_solid_box(Transform3D(Basis(), Vector3(at.x, foot, at.z)), Vector3(0.4, hang - foot, 0.4))


## A hanging run of the kit's chain from `top` down `length`.
func _chain(top: Vector3, length: float) -> void:
	if length <= 0.05:
		return
	var runs := maxi(ceili(length), 1)
	var each := length / float(runs)
	var yaw := _rng.randf() * TAU
	for i in runs:
		_piece("chain", Transform3D(Basis(Vector3.UP, yaw + float(i) * PI * 0.5).scaled(Vector3(1.0, each, 1.0)),
			top - Vector3(0.0, each * float(i), 0.0)), 1.0, Vector3.ZERO, false)


## Iron shackles on a wall: two cuffs at shoulder height on short chains, and
## now and then what is left of the one they held, sat beneath.
func _shackles(key: Vector2i, side: int, x: float) -> void:
	var w := _wall_xf(key, side)
	for s: float in [-0.32, 0.32]:
		var ring := w * Vector3(x + s, 1.75, 0.06)
		_chain(ring, 0.28)
		_piece("cuff", Transform3D(w.basis * Basis(Vector3.RIGHT, PI * 0.5), ring - Vector3(0.0, 0.34, 0.0) + w.basis.z * 0.04),
			0.9, Vector3.ZERO, false)
	_count("shackles")
	if _rng.randf() < 0.45:
		_seated_dead(_against(key, side, x, 0.0))


# --- Banners -----------------------------------------------------------------------

func _banners(key: Vector2i, cell, walls: Array[int], core: float) -> void:
	var lit := false
	for side in walls:
		if _rng.randf() > 0.85 * core:
			continue
		var xs: Array[float] = []
		if cell.kind == "straight" and _rng.randf() < 0.35:
			xs.append_array([-1.15, 1.15])
		else:
			xs.append(_rng.randf_range(-0.8, 0.8))
		for x in xs:
			if not _reserve(key, side, x, 0.7):
				continue
			_banner(key, side, x)
		# A candelabra standing under them now and then.
		if _rng.randf() < 0.3 * core:
			var x := _spot(key, side, 0.35)
			if not is_nan(x):
				_piece("candelabra", _against(key, side, x, 0.42), 0.9, Vector3(0.5, 1.9, 0.5), false)
				if not lit:
					lit = true
					_light(_against(key, side, x, 0.6) * Vector3(0.0, 1.95, 0.0), Color(1.0, 0.62, 0.3), 0.85)
	# A rug down a straight.
	if cell.kind == "straight" and _rng.randf() < 0.45 * core:
		var axis := _axis(cell)
		var c: Vector3 = out.to_world(key)
		_piece("rug", Transform3D(Basis(Vector3.UP, atan2(axis.x, axis.z) + PI * 0.5 + _rng.randf_range(-0.05, 0.05)),
			c + Vector3(0.0, 0.012, 0.0)), _rng.randf_range(0.8, 0.95), Vector3.ZERO, false)
	# A chandelier in a junction.
	if cell.kind != "straight" and not out.skylights.has(key) and _rng.randf() < 0.55 * core:
		var c: Vector3 = out.to_world(key)
		var top := CROWN - 0.05
		var drop := _rng.randf_range(0.2, 0.6)
		_chain(c + Vector3(0.0, top, 0.0), drop)
		_piece("chandelier", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), c + Vector3(0.0, top - drop, 0.0)),
			0.85, Vector3.ZERO, false)
		_light(c + Vector3(0.0, top - drop - 1.2, 0.0), Color(1.0, 0.64, 0.32), 1.0, 3.6)
	# A lectern.
	if not walls.is_empty() and _rng.randf() < 0.12 * core:
		var side: int = walls[0]
		var x := _spot(key, side, 0.5)
		if not is_nan(x):
			_piece("lectern", _against(key, side, x, 0.55), 1.0, Vector3(0.95, 1.5, 0.65))


static var _banner_meshes := {}
static var _banner_mat: ShaderMaterial = null


## A banner on wall (`key`, `side`) at `x`: hung from an iron rod on two brackets
## under the vault's springing.
func _banner(key: Vector2i, side: int, x: float) -> void:
	var w := _wall_xf(key, side)
	var width := _rng.randf_range(0.85, 1.15)
	var length := _rng.randf_range(1.8, 2.5)
	var top := 2.95
	# Variant 0 the crimson and black of one house, variant 1 the blue and
	# green of another.
	var cloths := [Color(0.3, 0.035, 0.03), Color(0.24, 0.03, 0.035), Color(0.07, 0.06, 0.05)] if _variant == 0 \
		else [Color(0.04, 0.07, 0.17), Color(0.035, 0.1, 0.07), Color(0.05, 0.06, 0.12)]
	hang_cloth(Transform3D(w.basis, w * Vector3(x, top, 0.14)), width, length,
		cloths[_rng.randi_range(0, cloths.size() - 1)])
	# The rod and its two brackets, one mesh.
	var rod := MeshInstance3D.new()
	rod.name = "BannerRod"
	rod.mesh = _rod_mesh(snappedf(width, 0.05))
	rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rod.visibility_range_end = 55.0
	add_child(rod)
	rod.transform = Transform3D(w.basis, w * Vector3(x, top + 0.02, 0.0))
	_count("banners")


## A cloth hanging from `xf` (its top edge's middle, +Z its face): a banner, or
## with `plain` a rag with no border or device (the scoutposts' balconies).
func hang_cloth(xf: Transform3D, width: float, length: float, colour: Color, plain := false) -> MeshInstance3D:
	if _banner_mat == null:
		_banner_mat = ShaderMaterial.new()
		_banner_mat.shader = BANNER_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Rag" if plain else "Banner"
	mi.mesh = _banner_mesh(snappedf(width, 0.05), snappedf(length, 0.1))
	mi.material_override = _banner_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 55.0
	add_child(mi)
	mi.transform = xf
	mi.set_instance_shader_parameter("cloth", colour)
	mi.set_instance_shader_parameter("device", float(_rng.randi_range(0, 2)))
	mi.set_instance_shader_parameter("tear_seed", _rng.randf())
	mi.set_instance_shader_parameter("length_m", length)
	mi.set_instance_shader_parameter("plain", 1.0 if plain else 0.0)
	return mi


static var _rods := {}


## A banner's iron rod, `width` + 0.2 long, 0.14 m out from the wall on two
## brackets; the wall's face at z = 0.
static func _rod_mesh(width: float) -> ArrayMesh:
	var key := "%.2f" % width
	if _rods.has(key):
		return _rods[key]
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.018
	cyl.height = width + 0.2
	cyl.radial_segments = 8
	cyl.rings = 1
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, 0.16)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(cyl, 0, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.0, 0.14)))
	for s: float in [-1.0, 1.0]:
		st.append_from(bm, 0, Transform3D(Basis(), Vector3(s * (width * 0.5 + 0.06), 0.0, 0.07)))
	var mesh := st.commit()
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.09, 0.085, 0.08)
	iron.metallic = 0.6
	iron.roughness = 0.6
	mesh.surface_set_material(0, iron)
	_rods[key] = mesh
	return mesh


## A banner's cloth: a grid hanging down from its top edge (y 0), `width` across.
static func _banner_mesh(width: float, length: float) -> ArrayMesh:
	var key := "%.2f_%.2f" % [width, length]
	if _banner_meshes.has(key):
		return _banner_meshes[key]
	var cols := 8
	var rows := 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rows + 1:
		for i in cols + 1:
			var u := float(i) / float(cols)
			var v := float(j) / float(rows)
			st.set_normal(Vector3(0.0, 0.0, 1.0))
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3((u - 0.5) * width, -v * length, 0.0))
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			var b := a + cols + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	var mesh := st.commit()
	_banner_meshes[key] = mesh
	return mesh


# --- Crystal seam ------------------------------------------------------------------

const CRYSTAL_LIGHT := Color(0.55, 0.75, 1.0)
## The second seam's crystal: violet, the light it gives and the stone's tint.
const CRYSTAL_VIOLET := Color(0.78, 0.5, 1.0)
const VIOLET_TINT := Color(1.15, 0.6, 1.25)
var _tints := {}


## Variant 1's crystals are violet: their materials (the glow included)
## tinted, the copies shared.
func _crystal_tint(piece: Node3D) -> void:
	if piece == null or _variant == 0:
		return
	for node in piece.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.get_surface_override_material(i)
			if src == null:
				src = mi.mesh.surface_get_material(i)
			var m := src as StandardMaterial3D
			if m == null:
				continue
			var k := m.get_instance_id()
			if not _tints.has(k):
				var d := m.duplicate() as StandardMaterial3D
				d.albedo_color = d.albedo_color * VIOLET_TINT
				d.emission = d.emission * VIOLET_TINT
				_tints[k] = d
			mi.set_surface_override_material(i, _tints[k])


func _crystal(key: Vector2i, cell, walls: Array[int], core: float) -> void:
	var lit := false
	for side in walls:
		if _rng.randf() > 0.55 * core:
			continue
		var x := _spot(key, side, 0.6)
		if is_nan(x):
			continue
		_crystal_cluster(_against(key, side, x, 0.05), _rng.randi_range(3, 5), not lit)
		lit = true
	# Hanging from the vault.
	if not out.skylights.has(key) and _rng.randf() < 0.4 * core:
		var c: Vector3 = out.to_world(key)
		var axis := _axis(cell)
		var across := Vector3(axis.z, 0.0, axis.x).abs()
		for i in _rng.randi_range(2, 4):
			var lat := _rng.randf_range(-1.3, 1.3)
			var at := c + axis * _rng.randf_range(-1.5, 1.5) + across * lat
			var y := _vault_at(lat) + 0.25
			var s := _rng.randf_range(0.18, 0.4)
			_crystal_tint(_piece("crystal", Transform3D(Basis(Vector3.RIGHT, PI + _rng.randf_range(-0.35, 0.35))
				* Basis(Vector3.UP, _rng.randf() * TAU), Vector3(at.x, y, at.z)), s, Vector3.ZERO, false))
	# A cart left with a load of it.
	if not walls.is_empty() and _rng.randf() < 0.12 * core:
		var side: int = walls[walls.size() - 1]
		var x := _spot(key, side, 0.95)
		if not is_nan(x):
			var xf := _against(key, side, x, 0.6)
			_piece("handcart", xf, 1.0, Vector3(1.8, 1.0, 1.0))
			for i in 3:
				_crystal_tint(_piece("crystal", Transform3D(xf.basis * Basis(Vector3.FORWARD, _rng.randf_range(-0.6, 0.6)),
					xf * Vector3(_rng.randf_range(-0.4, 0.4), 0.55, _rng.randf_range(-0.15, 0.15))),
					_rng.randf_range(0.14, 0.22), Vector3.ZERO, false))


## Crystals growing out of a wall's foot about `xf`, leaning out of the stone,
## the biggest at the back; with `light`, a cold light among them.
func _crystal_cluster(xf: Transform3D, n: int, light: bool) -> void:
	for i in n:
		var s := _rng.randf_range(0.2, 0.62) * (1.0 - float(i) / float(n) * 0.5)
		var lean := Basis(Vector3.RIGHT, _rng.randf_range(0.08, 0.5)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.4, 0.4))
		var at := xf * Vector3(_rng.randf_range(-0.45, 0.45), -0.05, _rng.randf_range(0.0, 0.3) + float(i) * 0.04)
		_crystal_tint(_piece("crystal", Transform3D(xf.basis * lean * Basis(Vector3.UP, _rng.randf() * TAU), at), s, Vector3.ZERO, false))
	_solid_box(xf * Transform3D(Basis(), Vector3(0.0, 0.0, 0.3)), Vector3(1.0, 1.0, 0.6))
	_count("crystal clusters")
	if light:
		_light(xf * Vector3(0.0, 0.7, 0.5), CRYSTAL_LIGHT if _variant == 0 else CRYSTAL_VIOLET, 0.9, 2.2)


# --- Gaol --------------------------------------------------------------------------

func _gaol(key: Vector2i, cell, walls: Array[int], core: float) -> void:
	# Variant 0 the hanging cages; variant 1 chains, shackles and cage carts.
	var cages := 0.3 if _variant == 0 else 0.1
	var bunches := 0.2 if _variant == 0 else 0.45
	var shackles := 0.18 if _variant == 0 else 0.35
	var carts := 0.2 if _variant == 0 else 0.45
	# Cages hanging from the vault, along a straight's sides.
	if not out.skylights.has(key) and _rng.randf() < cages * core:
		var c: Vector3 = out.to_world(key)
		var axis := _axis(cell)
		var across := Vector3(axis.z, 0.0, axis.x).abs()
		for i in _rng.randi_range(1, 2):
			var lat := _rng.randf_range(0.8, 1.15) * (1.0 if _rng.randf() < 0.5 else -1.0)
			var lon := _rng.randf_range(-1.8, 1.8) if cell.kind == "straight" else _rng.randf_range(-0.4, 0.4)
			if cell.kind != "straight":
				lat *= 0.4
			var top := _vault_at(lat) - 0.05
			var at := c + axis * lon + across * lat
			# High enough to walk under: its foot over a head.
			var scale_ := _rng.randf_range(0.72, 0.8)
			var drop := clampf(top - 2.7 * scale_ - 2.35, 0.0, 0.3)
			_chain(Vector3(at.x, top, at.z), drop)
			_piece("gibbet", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(at.x, top - drop, at.z)),
				scale_, Vector3.ZERO, false)
	# Chains in bunches.
	if not out.skylights.has(key) and _rng.randf() < bunches * core:
		var c: Vector3 = out.to_world(key)
		var axis := _axis(cell)
		var across := Vector3(axis.z, 0.0, axis.x).abs()
		var lat := _rng.randf_range(-1.2, 1.2)
		var at := c + axis * _rng.randf_range(-2.0, 2.0) + across * lat
		for i in _rng.randi_range(2, 4):
			var p := at + Vector3(_rng.randf_range(-0.25, 0.25), 0.0, _rng.randf_range(-0.25, 0.25))
			var top := _vault_at(lat) - 0.05
			_chain(Vector3(p.x, top, p.z), _rng.randf_range(0.8, minf(2.6, top - 2.3)))
	# Shackles with their prisoners.
	for side in walls:
		if _rng.randf() < shackles * core:
			var x := _spot(key, side, 0.4)
			if not is_nan(x):
				_shackles(key, side, x)
	# A cage cart in a junction or a dead end.
	if cell.kind != "straight" and not walls.is_empty() and _rng.randf() < carts * core:
		var side: int = walls[0]
		var x := _spot(key, side, 1.0)
		if not is_nan(x):
			_piece("cagecart", _against(key, side, x, 0.92), 0.8, Vector3(2.6, 2.1, 1.8))


# --- Rubble (the overgrowth's broken stone) ------------------------------------------

func _rubble(key: Vector2i, walls: Array[int], core: float) -> void:
	if walls.is_empty() or _rng.randf() > 0.35 * core:
		return
	var side: int = walls[_rng.randi_range(0, walls.size() - 1)]
	var x := _spot(key, side, 0.5)
	if is_nan(x):
		return
	var w := _wall_xf(key, side)
	if _stone_mat == null:
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.albedo_color = Color(0.16, 0.15, 0.15)
		_stone_mat.roughness = 0.95
	# The fallen stones of one heap as one mesh, in the wall's frame.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _rng.randi_range(4, 9):
		var bm := BoxMesh.new()
		bm.size = Vector3(_rng.randf_range(0.12, 0.32), _rng.randf_range(0.08, 0.18), _rng.randf_range(0.1, 0.24))
		st.append_from(bm, 0, Transform3D(Basis(Vector3(_rng.randf(), _rng.randf(), _rng.randf()).normalized(),
			_rng.randf_range(0.0, 0.6)), Vector3(x + _rng.randf_range(-0.4, 0.4), bm.size.y * 0.35,
			_rng.randf_range(0.08, 0.45))))
	var mi := MeshInstance3D.new()
	mi.name = "Rubble"
	mi.mesh = st.commit()
	mi.material_override = _stone_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 35.0
	add_child(mi)
	mi.transform = w
	_count("rubble")


var _stone_mat: StandardMaterial3D = null


# --- The scoutposts (notes 180, 181) ----------------------------------------------------
##
## scoutpost.gd dresses its hall with these pieces, so the scoutposts are the same
## stone, roots, wood and iron as the districts round them. It brackets its
## work in `hall_begin` / `hall_end`.

## Seeds the props' dice from the hall and takes the crimson house's colours.
## Returns where the hall's solid pieces start in the list.
func hall_begin(seed_: int) -> int:
	_rng.seed = seed_ ^ 0x4a11
	_variant = 0
	return _solid.size()


## The hall's solid pieces ([{at, half}]), its new props' shadows set.
func hall_end(from: int) -> Array:
	_apply_graphics()
	return _solid.slice(from)


## A root lying along the floor, from `from` (world) the way `dir` points, `length`
## long, half sunk in the flags and wandering side to side.
func floor_strand(from: Vector3, dir: Vector3, length: float, r0: float) -> Roots.Strand:
	var s := Roots.Strand.new()
	s.seed = _rng.randf()
	s.tint = _rng.randf_range(0.75, 1.1)
	s.gold = _rng.randf_range(0.5, 1.0)
	s.up = Vector3.UP
	s.flat = 0.6
	var side := Vector3(-dir.z, 0.0, dir.x)
	var wob := _rng.randf() * 20.0
	var amp := _rng.randf_range(0.25, 0.7)
	var n := maxi(int(length / 0.12), 4)
	for i in n + 1:
		var t := float(i) / float(n)
		var r := r0 * (1.0 - 0.8 * t) + 0.006
		var p := from + dir * (length * t) + side * (sin(wob + t * 5.3) * amp * t + sin(wob * 2.1 + t * 13.0) * 0.06)
		# Up off the wall's foot, then down into the floor.
		p.y = r * 0.45 + maxf(0.0, 0.35 - t * length) * 0.6
		s.pts.append(p)
		s.radii.append(r)
	return s


# --- Settings ----------------------------------------------------------------------

## The props' shadows and lights follow the graphics settings (section 3):
## `Graphics.ruin_shadows` lets the big pieces cast, `Graphics.effects` lights
## the candles, coals, chandeliers and crystals.
func _apply_graphics() -> void:
	var gfx := get_node_or_null("/root/Graphics")
	var shadows := true if gfx == null or gfx.get("ruin_shadows") == null else bool(gfx.get("ruin_shadows"))
	var effects := true if gfx == null else bool(gfx.get("effects"))
	for g in _casters:
		if not is_instance_valid(g):
			continue
		var copy := g.get_node_or_null("lod_shadow") as GeometryInstance3D
		if copy != null:
			copy.visible = shadows
		else:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for l in _lights:
		if is_instance_valid(l):
			l.visible = effects


## The flames flicker their lights (only those near enough to see).
func _process(_delta: float) -> void:
	if _lights.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var t := float(Time.get_ticks_msec()) * 0.001
	for l in _lights:
		if not l.visible or l.global_position.distance_squared_to(eye) > LIGHT_FADE * LIGHT_FADE * 1.6:
			continue
		var ph: float = l.get_meta("phase")
		var f := 0.86 + 0.09 * sin(t * 9.1 + ph) + 0.05 * sin(t * 23.7 + ph * 2.0)
		l.light_energy = float(l.get_meta("energy")) * f


func _physics_process(_delta: float) -> void:
	Crate.watch(Coop.all())
