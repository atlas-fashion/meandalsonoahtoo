extends "res://scripts/morgue.gd"

## The surgery (2026-10-21; refurnished after the user's reference picture,
## note 95; an open medieval hall, note 96; rebuilt, note 98; REDONE, note 99):
## the hall where the dead prisoners were made into soldiers -- intake,
## assembly, dispatch. An enclosed hall (module_level `_make_surgery_hall`, the
## chest room nearest the boss, note 97; this extends morgue.gd for its torches
## and bodies), no piers, no vaults.
##
## Everything in it is a Higgsfield asset (note 98's rule: "no original assets
## or models that were made directly in claude"): gpt_image_2_5 pictures, Tripo
## H3.1 models (the surgeon a Meshy rigged character), fitted by
## tools/build_surgery_kit.py into models/surgery/. Flat by nature: the plank
## ceiling and the effect textures (the claw's dust, chips and floor cracks).
##
## THE WALLS (note 99, the user: "no skulls, and the brick texture should be the
## same as the dungeon walls. The room's architecture looks great though"): the
## dungeon's own brick wall piece carried up course on course to the roof
## (`_raise_walls`, brick_level's "wall", the same stone as every corridor), and
## in front of it an open gothic arcade frame on every cell -- colonettes,
## lancet arches, a cornice, NO back panel, so the brick shows through every
## arch -- with an open tracery frieze and a plain lintel over each way in. No
## skulls, no carved faces anywhere on them.
##
## THE FLOOR, after the user's layout:
## - INTAKE: the FREIGHT LIFT in one corner brings the remains up from the
##   crypts; under the CONTROL ROOM beside it the tray carts are unloaded, and
##   the numbered trays and the catalogue drawers stand among the shelves.
## - THE BOOKSHELF MAZE fills the hall (`_carve_maze`, `_build_maze`): a
##   9 x 9 grid of ~3 m cells walled by back-to-back bookcases (six kinds:
##   ledgers, catalogue drawers, bone trays, scrolls, specimens, a ruined one),
##   a random spanning tree with a few loops cut in, so the claw has to be lost
##   in it. Its dead ends hold the anatomists' things -- a desk, a lectern, the
##   armillary, candelabras.
## - ASSEMBLY: a floor RAIL carries the trays from the intake into the open
##   middle, where the surgical table stands over the DISPOSAL SHAFT's grating
##   and the claw on its overhead gantry does the work.
## - DISPATCH: the finished soldiers stand in the HOLDING PENS behind iron bars
##   along the far wall, a portcullis between them and the middle.
## - THE CONTROL ROOM (surgery_control.gd): up on its platform over the intake,
##   leaded windows over the hall, the SURGEON at his console working the
##   claw. The freight lift goes up to its door. Kick it in, kill him, throw
##   the master lever: that, and only that, switches the machine off.
##
## The whole plan is laid out in its own frame (`_plan`, the lift's corner at
## its -X -Z) turned to whichever of the four ways keeps the lift, the control
## room and the pens off the hall's ways in (`_choose_plan`).

const Table := preload("res://scripts/surgical_table.gd")
const ControlRoom := preload("res://scripts/surgery_control.gd")
const ModuleMaze := preload("res://scripts/module_maze.gd")

## The Higgsfield kit (notes 95, 96, 98, 99).
const K := {
	"jar": preload("res://models/surgery/jar.glb"),
	"chest": preload("res://models/surgery/chest.glb"),
	"candelabra": preload("res://models/surgery/candelabra.glb"),
	"barrels": preload("res://models/surgery/barrels.glb"),
	"beam": preload("res://models/surgery/beam.glb"),
	"brace": preload("res://models/surgery/brace.glb"),
	"desk": preload("res://models/surgery/desk.glb"),
	"lectern": preload("res://models/surgery/lectern.glb"),
	"globe": preload("res://models/surgery/globe.glb"),
	"rug": preload("res://models/surgery/rug.glb"),
	"books": preload("res://models/surgery/books.glb"),
	"casket": preload("res://models/surgery/casket.glb"),
	"crates": preload("res://models/surgery/crates.glb"),
	"bundle": preload("res://models/surgery/bundle.glb"),
	"chain": preload("res://models/surgery/chain.glb"),
	"prosthetic": preload("res://models/surgery/prosthetic.glb"),
	"wallframe": preload("res://models/surgery/wallframe.glb"),
	"lintel2": preload("res://models/surgery/lintel2.glb"),
	"frieze2": preload("res://models/surgery/frieze2.glb"),
	"girder": preload("res://models/surgery/girder.glb"),
	"shelf_ledgers": preload("res://models/surgery/shelf_ledgers.glb"),
	"shelf_drawers": preload("res://models/surgery/shelf_drawers.glb"),
	"shelf_trays": preload("res://models/surgery/shelf_trays.glb"),
	"shelf_scrolls": preload("res://models/surgery/shelf_scrolls.glb"),
	"shelf_specimens": preload("res://models/surgery/shelf_specimens.glb"),
	"shelf_ruined": preload("res://models/surgery/shelf_ruined.glb"),
	"floorrail": preload("res://models/surgery/floorrail.glb"),
	"traycart": preload("res://models/surgery/traycart.glb"),
	"portcullis": preload("res://models/surgery/portcullis.glb"),
	"penbars": preload("res://models/surgery/penbars.glb"),
	"shaftgrate": preload("res://models/surgery/shaftgrate.glb"),
}
const PLANKS := preload("res://textures/surgery_planks.png")
## How much each kit piece glows with its own picture (surgical_table.gd `glow`).
const GLOWS := {"jar": 1.1, "candelabra": 1.2, "desk": 0.4, "books": 0.2, "shelf_specimens": 0.35,
	"shelf_ledgers": 0.12, "shelf_drawers": 0.12, "shelf_trays": 0.15, "shelf_scrolls": 0.15, "shelf_ruined": 0.1}

## The walls: open frames BAY_DEPTH deep in front of the brick, CEIL tall.
const BAY_DEPTH := 0.5
## Over a way in: the lintel's underside, and the frieze above it.
const LINTEL_Y := 3.7
const FRIEZE_Y := 4.8
## The brick kit's wall piece: its height and width (one course).
const COURSE := 3.5
const COURSE_W := 5.19
## The roof (note 96): a plank ceiling at CEIL on oak beams across the hall.
const CEIL := 8.6
const BEAM_Z: Array[float] = [-10.5, -6.0, -2.0, 2.0, 6.0, 10.5]
const BEAM := Vector2(0.55, 0.75)
const BEAM_LEN := 4.66
## The gantry's runways: girders along the side walls (room +-X), this far in
## from the frames' faces, their tops at the table's RUNWAY_TOP.
const RUNWAY_IN := 0.5
const GIRDER_LEN := 4.4
const GIRDER_H := 0.53

## The maze: N x N cells across the hall; the bookcases' depth and height.
const N := 9
const SHELF_DEPTH := 0.42
const SHELF_H := 3.9
## The oak posts at the maze's joins (note 100).
const POST_W := 0.88
const SHELVES := ["shelf_ledgers", "shelf_ledgers", "shelf_drawers", "shelf_scrolls", "shelf_specimens",
	"shelf_trays", "shelf_ruined"]
## A share of the walls left standing after the maze is carved is cut open,
## for loops (a maze with one path is a trap the claw can corner you in).
const LOOPS := 0.13
## Lights in the maze's dead ends at most (the candelabras').
const DEAD_END_LIGHTS := 6

const CANDLE_COLOUR := Color(1.0, 0.68, 0.38)

var table: CharacterBody3D
var control: Node3D

var _wall := 13.9
var _inner := 13.4
## A maze cell.
var _c := 2.98
## The ways in: [point on the wall face, the way out], room frame.
var _doorways: Array = []
## The plan's frame (see the header), and its turn in quarter turns.
var _plan: Node3D
var _turn := 0
## The maze: which cells are what, and which walls between them are open.
var _kind := {}
var _open := {}
var _cells: Array[Vector2i] = []


static func build_room(holder: Node3D, level, room_: Dictionary) -> Node3D:
	var m := Node3D.new()
	m.set_script(load("res://scripts/surgery.gd"))
	m.name = "Surgery"
	m.set("built", level)
	m.set("room", room_)
	holder.add_child(m)
	m.call("_dress")
	return m


# --- Building ---------------------------------------------------------------------

func _dress() -> void:
	var centre: Vector3 = built.room_world(room)
	# The local frame: origin the middle of the block, +Z toward the way in.
	var out := Vector3(0.0, 0.0, 1.0)
	var doors: Array = built.room_doors(room)
	if not doors.is_empty():
		var step: Vector2i = doors[0]["outward"]
		out = Vector3(float(step.x), 0.0, float(step.y))
	global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), centre)
	_rng.seed = hash(room["centre"]) ^ 0x73757267
	var cell: float = built.cell_size
	var h: int = room["half"]
	_wall = float(h) * cell + BrickLevel.WALL_FACE
	_inner = _wall - BAY_DEPTH
	_c = _inner * 2.0 / float(N)
	_doorways = _find_doorways()

	_raise_walls(h, cell)
	_build_walls(h, cell)
	_build_roof()
	_build_runways()
	_hang_wall_torches(h, cell)

	_choose_plan()
	_carve_maze()
	_build_maze()
	_build_intake()
	_build_rail()
	_build_dispatch()
	_build_centre()
	_furnish_dead_ends()

	_spawn_table()
	control = Node3D.new()
	control.set_script(ControlRoom)
	control.name = "ControlRoom"
	_plan.add_child(control)
	control.call("setup", self, table, _inner, _c)
	_light_hall()
	_limit_view(_wall)
	print("[surgery] the surgical table asleep under its gantry; a %dx%d bookshelf maze (%d open walls), the plan turned %d; %d bodies laid out"
		% [N, N, _open.size(), _turn * 90, _corpse_count])


## A node of the plan's frame at `at`, turned `yaw`.
func _node(name_: String, at: Vector3, yaw := 0.0, parent: Node3D = null) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	(parent if parent != null else _plan).add_child(n)
	n.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	return n


func _solid(parent: Node3D, size: Vector3, at: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	parent.add_child(body)
	body.position = at
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


## A kit piece `name_` on `n` at `at`, turned `yaw`, glowing as GLOWS says,
## solid as a box of `size` (its footprint before the turn; none if zero).
func _kit(n: Node3D, name_: String, at: Vector3, yaw := 0.0, size := Vector3.ZERO, scale_ := Vector3.ONE) -> Node3D:
	var piece: Node3D = (K[name_] as PackedScene).instantiate()
	piece.name = name_.capitalize().replace(" ", "")
	n.add_child(piece)
	piece.position = at
	piece.rotation.y = yaw
	piece.scale = scale_
	Table.grade(piece)
	Table.glow(piece, float(GLOWS.get(name_, 0.0)))
	for node in piece.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if size != Vector3.ZERO:
		var body := StaticBody3D.new()
		body.collision_layer = 1 | 2
		body.collision_mask = 0
		piece.add_child(body)
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0.0, size.y * 0.5, 0.0)
		body.add_child(cs)
	return piece


## The first mesh in a kit piece, for MultiMeshes.
static func _mesh_of(name_: String) -> Mesh:
	var scene: Node = (K[name_] as PackedScene).instantiate()
	Table.grade(scene)
	var mesh: Mesh = null
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		mesh = (node as MeshInstance3D).mesh
		break
	scene.free()
	return mesh


## A hanging chain of the kit's chain link-run from `top` down `length`.
func _chain(n: Node3D, top: Vector3, length: float) -> void:
	var runs := maxi(ceili(length), 1)
	var each := length / float(runs)
	for i in runs:
		_kit(n, "chain", top - Vector3(0.0, each * float(i), 0.0), 0.0, Vector3.ZERO, Vector3(1.0, each, 1.0))


# --- The hall (notes 96, 98, 99) ------------------------------------------------------

## The ways in: [the middle of the gap in the wall face, the way out], room frame.
func _find_doorways() -> Array:
	var out: Array = []
	for way in room["entrances"]:
		var local := to_local(built.to_world(way["cell"]))
		var step: Vector2i = ModuleMaze.DIRS[way["side"]]
		var dir := (global_basis.inverse() * Vector3(float(step.x), 0.0, float(step.y))).round()
		var at := Vector3(local.x, 0.0, local.z) * (Vector3.ONE - dir.abs()) + dir * _wall
		out.append([at, dir])
	return out


## How near `p` (room frame, on the floor) is to the nearest way in.
func _door_distance(p: Vector3) -> float:
	var best := INF
	for d in _doorways:
		best = minf(best, Vector2(p.x - d[0].x, p.z - d[0].z).length())
	return best


func _is_door(into: Vector3, at: Vector3) -> bool:
	for d in _doorways:
		if (d[1] as Vector3).dot(into) > 0.9 and (d[0] as Vector3).distance_to(at) < 1.0:
			return true
	return false


## The dungeon's own brick, carried up to the roof: course on course of the brick
## kit's wall piece (the corridors' stone, note 27) on every wall face above the
## first, which the level built. Over a way in the courses start over the arch.
func _raise_walls(h: int, cell: float) -> void:
	var mesh: Mesh = BrickLevel.standalone("wall")
	if mesh == null:
		return
	var xfs: Array[Transform3D] = []
	for d: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var along := Vector3(-d.z, 0.0, d.x)
		var face := Basis(Vector3.UP, atan2(-d.x, -d.z))
		for k in range(-h, h + 1):
			for y: float in [COURSE, COURSE * 2.0]:
				var at := d * _wall + along * float(k) * cell + Vector3(0.0, y, 0.0)
				xfs.append(Transform3D(face.scaled(Vector3(cell / COURSE_W, 1.0, 1.0)), at))
	_multi(mesh, xfs, "RaisedBrick")


## The walls' stone: on every wall cell an open gothic frame in front of the brick
## (or, over a way in, the plain lintel with the open frieze above it). They
## stand in front of the brick, whose collision stops at the old crown; theirs
## takes the first 3 m.
func _build_walls(h: int, cell: float) -> void:
	var holder := Node3D.new()
	holder.name = "Walls"
	add_child(holder)
	for d: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var along := Vector3(-d.z, 0.0, d.x)
		var face := Basis(Vector3.UP, atan2(-d.x, -d.z))
		for k in range(-h, h + 1):
			var cell_at: Vector3 = d * _wall + along * float(k) * cell
			var door := _is_door(d, cell_at)
			var lo := float(k) * cell - cell * 0.5
			var hi := float(k) * cell + cell * 0.5
			if k == -h:
				lo = -_wall + BAY_DEPTH
			elif k == h:
				hi = _wall - BAY_DEPTH
			var mid := (lo + hi) * 0.5
			var width := hi - lo
			var base := d * (_wall - BAY_DEPTH * 0.5) + along * mid
			var sx := Vector3(width / 5.0, 1.0, 1.0)
			if door:
				var lintel := _kit(holder, "lintel2", base + Vector3(0.0, LINTEL_Y, 0.0))
				lintel.basis = face.scaled(sx)
				var frieze := _kit(holder, "frieze2", base + Vector3(0.0, FRIEZE_Y, 0.0))
				frieze.basis = face.scaled(Vector3(sx.x, 1.0, (CEIL - FRIEZE_Y) / 3.9))
			else:
				var bay := _kit(holder, "wallframe", base)
				bay.basis = face.scaled(sx)
				_solid(holder, Vector3(width, 3.2, BAY_DEPTH), base + Vector3(0.0, 1.6, 0.0), atan2(-d.x, -d.z))


## The roof: a plank ceiling (the generated plank texture, world-mapped) over
## the whole hall on oak beams in sections, their ends into the walls. One
## MultiMesh for the beams.
func _build_roof() -> void:
	var span := _wall * 2.0 + 0.6
	var ceiling := MeshInstance3D.new()
	ceiling.name = "Ceiling"
	var plane := PlaneMesh.new()
	plane.size = Vector2(span, span)
	plane.flip_faces = true
	ceiling.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_texture = PLANKS
	m.albedo_color = Color(0.75, 0.68, 0.62)
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.4, 0.4, 0.4)
	ceiling.material_override = m
	ceiling.position = Vector3(0.0, CEIL, 0.0)
	add_child(ceiling)
	var beam := _mesh_of("beam")
	var xfs: Array[Transform3D] = []
	var count := ceili(span / BEAM_LEN)
	for z in BEAM_Z:
		for i in count:
			var x := -span * 0.5 + BEAM_LEN * (float(i) + 0.5)
			xfs.append(Transform3D(Basis(Vector3.UP, PI * float(i % 2)), Vector3(x, CEIL - BEAM.y * 0.5, z)))
	_multi(beam, xfs, "Beams")


## The gantry's runways (surgical_table.gd rides its bridge on them): riveted
## iron girders along the two side walls, each on oak knee braces from the wall.
func _build_runways() -> void:
	var holder := Node3D.new()
	holder.name = "Runways"
	add_child(holder)
	var rail_x := _inner - RUNWAY_IN
	var count := maxi(ceili(_inner * 2.0 / GIRDER_LEN), 1)
	var each := _inner * 2.0 / float(count)
	var girder := _mesh_of("girder")
	var xfs: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		for i in count:
			var z := -_inner + each * (float(i) + 0.5)
			var b := Basis(Vector3.UP, PI * 0.5 + PI * float(i % 2)).scaled(Vector3(each / GIRDER_LEN, 1.0, 1.0))
			xfs.append(Transform3D(b, Vector3(s * rail_x, Table.RUNWAY_TOP - GIRDER_H * 0.5, z)))
			if i % 2 == 0:
				var brace := _kit(holder, "brace", Vector3(s * (_inner - 0.84), Table.RUNWAY_TOP - GIRDER_H - 0.95, z))
				brace.rotation.y = (0.0 if s < 0.0 else PI) + PI * 0.5
	_multi(girder, xfs, "RunwayGirders")


## A torch on the wall between every two frames, none at a way in.
func _hang_wall_torches(h: int, cell: float) -> void:
	var level = load("res://scripts/module_level.gd")
	var scene: PackedScene = load(level.TORCH_SCENE)
	var energy: float = TORCH_ENERGY
	var n := get_parent()
	while n != null and n.get("module_torch_energy") == null:
		n = n.get_parent()
	if n != null:
		energy = float(n.get("module_torch_energy")) * TORCH_BOOST
	for k in range(-h, h):
		var v := (float(k) + 0.5) * cell
		for d: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			var at := d * (_inner - 0.05) + Vector3(-d.z, 0.0, d.x) * v
			if _door_distance(at) < 2.0:
				continue
			level._hang_torch(self, scene, at + Vector3(0.0, TORCH_HEIGHT, 0.0), d, energy, 13.0)


# --- The plan (note 99) ------------------------------------------------------------

## The plan's turn: the first quarter turn that keeps the lift's corner, the
## wall under the control room and the pens' wall clear of every way in (or
## the one that clears most).
func _choose_plan() -> void:
	var best := 0
	var best_bad := 99
	for k in 4:
		var b := Basis(Vector3.UP, float(k) * PI * 0.5)
		var bad := 0
		for d in _doorways:
			var p: Vector3 = b.inverse() * (d[0] as Vector3)
			var dir: Vector3 = (b.inverse() * (d[1] as Vector3)).round()
			if dir.x < -0.5 and p.z < -_inner + 3.0 * _c + 2.2:
				bad += 1
			elif dir.z < -0.5 and p.x < -_inner + _c + 2.2:
				bad += 1
			elif dir.x > 0.5 and absf(p.z) < 1.5 * _c + 2.2:
				bad += 1
		if bad < best_bad:
			best_bad = bad
			best = k
	_turn = best
	_plan = Node3D.new()
	_plan.name = "Plan"
	add_child(_plan)
	_plan.transform = Transform3D(Basis(Vector3.UP, float(_turn) * PI * 0.5), Vector3.ZERO)
	if best_bad > 0:
		push_warning("surgery: %d way(s) in fall on the lift, the control room or the pens" % best_bad)


## The middle of maze cell (i, j), plan frame, on the floor.
func cell_at(i: int, j: int) -> Vector3:
	return Vector3(-_inner + _c * (float(i) + 0.5), 0.0, -_inner + _c * (float(j) + 0.5))


## What cell (i, j) is: "lift", "intake", "centre", "pen", or "maze".
func _kind_of(i: int, j: int) -> StringName:
	if i == 0 and j == 0:
		return &"lift"
	if i == 0 and (j == 1 or j == 2):
		return &"intake"
	if i >= 3 and i <= 5 and j >= 3 and j <= 5:
		return &"centre"
	if i == N - 1 and j >= 3 and j <= 5:
		return &"pen"
	return &"maze"


static func _edge(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


var _uf := {}


func _find(a: Vector2i) -> Vector2i:
	while _uf[a] != a:
		_uf[a] = _uf[_uf[a]]
		a = _uf[a]
	return a


func _union(a: Vector2i, b: Vector2i) -> bool:
	var ra := _find(a)
	var rb := _find(b)
	if ra == rb:
		return false
	_uf[ra] = rb
	return true


## The maze: every cell but the pens joined by a random spanning tree (Kruskal)
## over the walls between them, after the openings the layout needs -- inside
## the middle, the intake, the rail's run from the intake to the middle, the
## aisle from the middle to the pens' gate -- then LOOPS of the rest cut open.
func _carve_maze() -> void:
	_kind.clear()
	_open.clear()
	_cells.clear()
	_uf.clear()
	for i in N:
		for j in N:
			var c := Vector2i(i, j)
			_kind[c] = _kind_of(i, j)
			if _kind[c] != &"pen":
				_cells.append(c)
				_uf[c] = c
	var forced: Array = [[Vector2i(0, 0), Vector2i(0, 1)], [Vector2i(0, 1), Vector2i(0, 2)],
		[Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(0, 2), Vector2i(1, 2)], [Vector2i(1, 2), Vector2i(2, 2)], [Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(3, 2), Vector2i(4, 2)], [Vector2i(4, 2), Vector2i(4, 3)],
		[Vector2i(5, 4), Vector2i(6, 4)], [Vector2i(6, 4), Vector2i(7, 4)]]
	for i in range(3, 6):
		for j in range(3, 6):
			if i < 5:
				forced.append([Vector2i(i, j), Vector2i(i + 1, j)])
			if j < 5:
				forced.append([Vector2i(i, j), Vector2i(i, j + 1)])
	# The lift's cage stands against its side: never open there.
	var shut := {_edge(Vector2i(0, 0), Vector2i(1, 0)): true}
	for f in forced:
		_open[_edge(f[0], f[1])] = true
		_union(f[0], f[1])
	var walls: Array = []
	for c in _cells:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var o: Vector2i = c + step
			if o.x >= N or o.y >= N or _kind.get(o) == &"pen":
				continue
			var e := _edge(c, o)
			if _open.has(e) or shut.has(e):
				continue
			walls.append([c, o])
	# Shuffled with the room's own generator: the same seed, the same maze.
	for i in range(walls.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = walls[i]
		walls[i] = walls[j]
		walls[j] = t
	var left: Array = []
	for w in walls:
		if _union(w[0], w[1]):
			_open[_edge(w[0], w[1])] = true
		else:
			left.append(w)
	for w in left:
		if _rng.randf() < LOOPS:
			_open[_edge(w[0], w[1])] = true


## Two bookcases back to back on every wall of the maze left standing, one
## facing each cell; one box of collision for the pair. Which kind, by where:
## the trays and the catalogue drawers nearest the intake.
func _build_maze() -> void:
	var holder := _node("Maze", Vector3.ZERO)
	var posts := {}
	for c in _cells:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var o: Vector2i = c + step
			if o.x >= N or o.y >= N:
				continue
			if _kind.get(o) == &"pen":
				continue
			if _open.has(_edge(c, o)):
				continue
			var a := cell_at(c.x, c.y)
			var b := cell_at(o.x, o.y)
			var mid := (a + b) * 0.5
			var normal := (b - a).normalized()
			# The pair's wall runs across `normal`; each case stands on its own
			# cell's side of the line, its back on the line, its front (+Z)
			# out into its cell. (Note 99 had them the other way round: both
			# fronts met inside the wall and only backs showed.)
			var near_intake := c.x <= 2 and c.y <= 3
			for facing: Vector3 in [normal, -normal]:
				var name_: String = _pick_shelf(near_intake)
				_kit(holder, name_, mid + facing * (SHELF_DEPTH * 0.5 + 0.005), atan2(facing.x, facing.z))
			_solid(holder, Vector3(_c - 0.06, SHELF_H, SHELF_DEPTH * 2.0), mid + Vector3(0.0, SHELF_H * 0.5, 0.0),
				atan2(normal.x, normal.z))
			# Its two ends, and which way the wall runs from each (note 100).
			var along := Vector3(-normal.z, 0.0, normal.x)
			for s: float in [-1.0, 1.0]:
				var v := mid + along * (_c * 0.5 * s)
				var key := Vector2i(roundi(v.x * 10.0), roundi(v.z * 10.0))
				if not posts.has(key):
					posts[key] = [v, {}]
				(posts[key][1] as Dictionary)[absf(along.x) > 0.5] = true
	# A post where two walls meet at a corner, a T or a cross: there the cases of
	# the one wall run into the other's, and the post covers the join. Where a
	# wall runs straight on, or ends, the cases stand as they are.
	for p in posts.values():
		if (p[1] as Dictionary).size() > 1:
			_maze_post(holder, p[0])


## An oak post at a join in the maze: the kit's beam stood on end, wide enough
## to cover both pairs' ends, its top under the cases' carved crests (which
## carry on over it).
func _maze_post(holder: Node3D, at: Vector3) -> void:
	var h := SHELF_H - 0.45
	var post := _kit(holder, "beam", at + Vector3(0.0, h * 0.5, 0.0))
	post.basis = Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3(h / 4.66, POST_W / 0.55, POST_W / 0.75))
	_solid(holder, Vector3(POST_W, h, POST_W), at + Vector3(0.0, h * 0.5, 0.0))


func _pick_shelf(near_intake: bool) -> String:
	if near_intake and _rng.randf() < 0.6:
		return "shelf_trays" if _rng.randf() < 0.6 else "shelf_drawers"
	return SHELVES[_rng.randi_range(0, SHELVES.size() - 1)]


## The cells off the maze's paths with only one way in.
func _dead_ends() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _cells:
		if _kind[c] != &"maze":
			continue
		var ways := 0
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _open.has(_edge(c, c + step)):
				ways += 1
		if ways == 1:
			out.append(c)
	return out


## The anatomists' things in the dead ends -- a desk on a rug, a lectern with
## its book, the armillary sphere, piles of books, a specimen jar, a chest --
## and a candelabra in some, the maze's only light but the claw's.
func _furnish_dead_ends() -> void:
	var ends := _dead_ends()
	for i in range(ends.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := ends[i]
		ends[i] = ends[j]
		ends[j] = t
	var things := ["desk", "lectern", "globe", "books", "jar", "chest", "books", "jar"]
	var lights := 0
	for k in ends.size():
		var c: Vector2i = ends[k]
		var at := cell_at(c.x, c.y)
		# Back against the wall opposite the way in.
		var way := Vector3.ZERO
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _open.has(_edge(c, c + step)):
				way = Vector3(float(step.x), 0.0, float(step.y))
		var back := at - way * (_c * 0.5 - SHELF_DEPTH - 0.45)
		var yaw := atan2(way.x, way.z)
		var thing: String = things[k % things.size()]
		match thing:
			"desk":
				_kit(_plan, "rug", at, yaw)
				_kit(_plan, "desk", back + way * 0.2, yaw, Vector3(1.9, 1.2, 0.9))
			"lectern":
				_kit(_plan, "lectern", back, yaw, Vector3(0.6, 1.4, 0.6))
			"globe":
				_kit(_plan, "globe", back, yaw, Vector3(0.9, 1.6, 0.9))
			"books":
				_kit(_plan, "books", back, yaw + _rng.randf_range(-0.4, 0.4))
			"jar":
				_kit(_plan, "jar", back, yaw, Vector3(0.8, 2.0, 0.8))
			"chest":
				_kit(_plan, "chest", back, yaw, Vector3(1.1, 0.8, 0.7))
		if lights < DEAD_END_LIGHTS and k % 2 == 0:
			lights += 1
			var side := Vector3(way.z, 0.0, -way.x) * 0.8
			var cand := _kit(_plan, "candelabra", back + side, yaw)
			_candle_light(cand)


func _candle_light(n: Node3D) -> void:
	var light := OmniLight3D.new()
	light.name = "Candles"
	light.light_color = CANDLE_COLOUR
	light.light_energy = 1.6
	light.omni_range = 6.5
	light.omni_attenuation = 1.1
	light.light_specular = 0.2
	light.shadow_enabled = false
	light.position = Vector3(0.0, 2.0, 0.0)
	n.add_child(light)


# --- Intake, assembly, dispatch --------------------------------------------------------

## INTAKE, under the control room: the tray carts unloaded there, crates of
## remains, caskets waiting.
func _build_intake() -> void:
	var a := cell_at(0, 1)
	var b := cell_at(0, 2)
	_kit(_plan, "traycart", a + Vector3(-0.35, 0.0, 0.0), 0.0, Vector3(0.9, 0.7, 2.2))
	_kit(_plan, "crates", b + Vector3(-0.7, 0.0, 0.5), PI * 0.5, Vector3(1.2, 1.6, 1.2))
	_kit(_plan, "casket", a + Vector3(-1.0, 0.0, -1.1), PI * 0.5, Vector3(0.9, 2.2, 0.6))
	var lamp := OmniLight3D.new()
	lamp.name = "IntakeLamp"
	lamp.light_color = CANDLE_COLOUR
	lamp.light_energy = 1.4
	lamp.omni_range = 7.0
	lamp.omni_attenuation = 1.2
	lamp.shadow_enabled = false
	_plan.add_child(lamp)
	lamp.position = (a + b) * 0.5 + Vector3(0.6, 2.8, 0.0)


## ASSEMBLY: the floor rail from the intake to the middle (along row 2, then up
## into the middle), and a tray cart that runs it.
var _rail: PackedVector3Array
var _cart: Node3D
var _cart_t := 0.0


func _build_rail() -> void:
	var start := cell_at(0, 2) + Vector3(0.6, 0.0, 0.0)
	var corner := cell_at(4, 2)
	var end := cell_at(4, 3) + Vector3(0.0, 0.0, -0.4)
	_rail = PackedVector3Array([start, corner, end])
	var holder := _node("Rail", Vector3.ZERO)
	for s in 2:
		var a := _rail[s]
		var b := _rail[s + 1]
		var length := a.distance_to(b)
		var count := maxi(roundi(length / 3.0), 1)
		var dir := (b - a) / length
		for i in count:
			var at := a + dir * (length * (float(i) + 0.5) / float(count))
			var piece := _kit(holder, "floorrail", at, atan2(dir.x, dir.z))
			piece.scale = Vector3(1.0, 1.0, length / float(count) / 3.0)
	_cart = _kit(holder, "traycart", start, atan2(1.0, 0.0))


func _run_cart(delta: float) -> void:
	if _cart == null or table == null:
		return
	# Out to the middle and back, resting at each end, while the machine has
	# power; stopped where it is once it has none.
	if bool(table.call("is_depowered")) or table.get("state") == Table.State.DORMANT:
		return
	_cart_t = fmod(_cart_t + delta, 36.0)
	var total := _rail[0].distance_to(_rail[1]) + _rail[1].distance_to(_rail[2])
	var u := 0.0
	if _cart_t < 6.0:
		u = 0.0
	elif _cart_t < 18.0:
		u = smoothstep(0.0, 1.0, (_cart_t - 6.0) / 12.0)
	elif _cart_t < 24.0:
		u = 1.0
	else:
		u = 1.0 - smoothstep(0.0, 1.0, (_cart_t - 24.0) / 12.0)
	var d := u * total
	var leg := _rail[0].distance_to(_rail[1])
	var at: Vector3
	var dir: Vector3
	if d <= leg:
		dir = (_rail[1] - _rail[0]).normalized()
		at = _rail[0] + dir * d
	else:
		dir = (_rail[2] - _rail[1]).normalized()
		at = _rail[1] + dir * (d - leg)
	_cart.position = at
	_cart.rotation.y = lerp_angle(_cart.rotation.y, atan2(dir.x, dir.z), clampf(delta * 3.0, 0.0, 1.0))


## DISPATCH: the holding pens along the far wall behind iron bars, the portcullis
## between them and the aisle from the middle, and the finished soldiers
## standing in them, fitted with their mechanical arms.
func _build_dispatch() -> void:
	var holder := _node("Dispatch", Vector3.ZERO)
	var x_bars := -_inner + _c * float(N - 1)
	for j in range(3, 6):
		var at := Vector3(x_bars, 0.0, cell_at(0, j).z)
		if j == 4:
			_kit(holder, "portcullis", at, -PI * 0.5)
			_solid(holder, Vector3(0.6, 3.6, _c), at + Vector3(0.0, 1.8, 0.0))
		else:
			_kit(holder, "penbars", at, -PI * 0.5)
			_solid(holder, Vector3(0.35, 2.4, _c), at + Vector3(0.0, 1.2, 0.0))
	for j: int in [3, 6]:
		var at := Vector3(cell_at(N - 1, 0).x, 0.0, -_inner + _c * float(j))
		_kit(holder, "penbars", at, 0.0 if j == 3 else PI)
		_solid(holder, Vector3(_c, 2.4, 0.35), at + Vector3(0.0, 1.2, 0.0))
	# The soldiers, in two ranks, and their shipping caskets.
	for k in 6:
		var j := 3 + k % 3
		var row := float(k / 3)
		var at := cell_at(N - 1, j) + Vector3(-0.55 + row * 0.9, 0.0, _rng.randf_range(-0.5, 0.5))
		_soldier(holder, at, -PI * 0.5 + _rng.randf_range(-0.25, 0.25))
	_kit(holder, "casket", cell_at(N - 1, 3) + Vector3(0.9, 0.0, -1.0), -PI * 0.5, Vector3(0.6, 2.2, 0.9))
	_kit(holder, "casket", cell_at(N - 1, 5) + Vector3(0.9, 0.0, 1.0), -PI * 0.5, Vector3(0.6, 2.2, 0.9))
	var light := OmniLight3D.new()
	light.name = "PenLight"
	light.light_color = Color(1.0, 0.45, 0.3)
	light.light_energy = 0.9
	light.omni_range = 7.0
	light.shadow_enabled = false
	holder.add_child(light)
	light.position = cell_at(N - 1, 4) + Vector3(0.4, 3.0, 0.0)


## A finished soldier: a prisoner's skeleton on its feet, its forearm replaced by
## the mechanical arm.
func _soldier(holder: Node3D, at: Vector3, yaw: float) -> void:
	var n := _node("Soldier", at, yaw, holder)
	var model: Node3D = SKELETON.instantiate()
	model.scale = Vector3(-0.92, 0.92, -0.92)
	n.add_child(model)
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var sk := found[0] as Skeleton3D
	var fore := sk.find_bone(&"forearm.R")
	if fore >= 0:
		sk.set_bone_pose_scale(fore, Vector3.ONE * 0.001)
		var att := BoneAttachment3D.new()
		att.bone_name = "upper_arm.R"
		sk.add_child(att)
		attach_prosthetic(att)


## The middle: the disposal shaft's grating under the table.
func _build_centre() -> void:
	_kit(_plan, "shaftgrate", Vector3(0.0, 0.02, 0.0), 0.0)


## The kit's mechanical arm on an upper-arm bone attachment, out along the bone
## from the elbow (the bone's +Y), its socket at the elbow. Shared with the
## table's prisoner (surgical_table.gd).
static func attach_prosthetic(att: Node3D) -> void:
	var arm: Node3D = (K["prosthetic"] as PackedScene).instantiate()
	load("res://scripts/surgical_table.gd").grade(arm)
	att.add_child(arm)
	arm.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 0.27, 0.0))
	arm.scale = Vector3.ONE * 1.2


## A dim warm fill high in the middle: the roof and the shelves' tops would be
## black otherwise (the claw's lamp and the candles light only below them).
func _light_hall() -> void:
	var fill := OmniLight3D.new()
	fill.name = "RoofFill"
	fill.light_color = Color(1.0, 0.78, 0.55)
	fill.light_energy = 0.8
	fill.omni_range = 19.0
	fill.omni_attenuation = 1.0
	fill.light_specular = 0.1
	fill.shadow_enabled = false
	fill.position = Vector3(0.0, 7.2, 0.0)
	add_child(fill)


# --- The table ------------------------------------------------------------------

## The table in the middle of the hall, lying across it, under its gantry.
func _spawn_table() -> void:
	table = CharacterBody3D.new()
	table.set_script(Table)
	table.name = "SurgicalTable"
	table.set("room", self)
	table.set("home", global_transform * Vector3.ZERO)
	table.set("home_yaw", global_rotation.y + PI * 0.5)
	table.set("bound", _inner - 0.5)
	table.set("rail_x", _inner - RUNWAY_IN)
	add_child(table)


# --- Each frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_run_cart(delta)


# --- Saving and resetting ----------------------------------------------------------------

func save_state() -> Dictionary:
	if table == null or not bool(table.call("is_depowered")):
		return {"down": false}
	var p: Vector3 = table.call("rest_point")
	return {"down": true, "at": [p.x, p.y, p.z]}


func restore_state(data: Dictionary) -> void:
	if table == null or not bool(data.get("down", false)):
		return
	var at: Array = data.get("at", [])
	var p := table.global_position if at.size() < 3 else Vector3(float(at[0]), float(at[1]), float(at[2]))
	table.call("set_dead_now", p, 0.0)
	if control != null:
		control.call("set_finished")


## Everyone died: with the table still running, all of it back as it was.
func on_world_reset() -> void:
	if table == null or bool(table.call("is_depowered")):
		return
	table.call("reset_to_sleep")
	if control != null:
		control.call("reset")


## Just inside the way in, facing the table: [position, yaw] (sandbox teleport).
func entry_point() -> Array:
	var doors: Array = built.room_doors(room)
	if doors.is_empty():
		return [global_position + Vector3(0.0, 0.3, 0.0), global_rotation.y]
	var d: Dictionary = doors[0]
	var step: Vector2i = d["outward"]
	var inward := -Vector3(float(step.x), 0.0, float(step.y))
	var at: Vector3 = d["world"] + inward * 2.5 + Vector3(0.0, 0.3, 0.0)
	return [at, atan2(-inward.x, -inward.z)]
