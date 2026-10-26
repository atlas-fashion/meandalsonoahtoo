extends "res://scripts/morgue.gd"

## The surgery (2026-10-21; refurnished after the user's reference picture,
## note 95; an open medieval hall, note 96; rebuilt, note 98; redone, note 99;
## its bookshelves turned to VATS and its power put under the floor, note 102):
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
## THE WALLS (note 99): the dungeon's own brick carried up to the roof
## (`_raise_walls`) behind an open gothic arcade frame on every cell, no skulls.
##
## THE FLOOR (note 102, the user: "Remove the bookshelves, the room should
## instead be filled with large vats of pieces that the claw uses to make bionic
## soldiers. The player should be able to push the vats around the room, but
## they should be heavy and cumbersome"):
## - THE VATS fill the hall in rows (`_lay_vats`): riveted iron tubs of bones
##   and of gold prostheses (surgery_vat.gd), on a 3 m lattice with aisles
##   carved between them like a maze's -- a random spanning tree with a few loops
##   -- the middle round the table, the intake, the rail and the ways in left
##   clear. Every one can be shoved, slowly (surgery_vat.gd). Some of the gold
##   ones glow with the oil in them: the hall's light, carried where they go.
## - ONE VAT stands over the HATCH to the POWERING ROOM under the hall
##   (surgery_power.gd), and nothing marks which (asked: no hint). In the room,
##   THE CRYSTAL that powers the machine: pulled out, the claw drops dead, and
##   climbing back out the player finds the SURGEON gone from his booth.
## - INTAKE under the CONTROL ROOM (the tray cart, crates, a casket); ASSEMBLY:
##   a floor RAIL from there into the open middle, where the surgical table
##   stands over the DISPOSAL SHAFT's grating and the claw on its overhead
##   gantry does the work; DISPATCH: the finished soldiers in the HOLDING PENS
##   behind iron bars along the far wall, a portcullis between them and the hall.
## - THE CONTROL ROOM (surgery_control.gd): up on its platform over the intake,
##   leaded windows over the hall, the surgeon at his console working the claw.
##   The other way to beat the room (note 104): up onto the table, across the
##   vats, one shoved up beside the booth, onto its landing -- the door kicked
##   in, the surgeon thrown out of the window, the machine switched off there.
## - NOTE 104: a vat across each way in and, the first time a player comes up
##   to one, THE ENTRANCE SCENE (`_intro`): they shove it aside and walk in on
##   the claw at work, it drops its soldier in the pens, turns on them, and the
##   BARS come up out of the floor at every way in (`raise_bars`; down when the
##   machine is off, or on a world reset). The pens' soldiers are real
##   skeletons, thrown into the hall by the claw (`turn_loose`); every vat has
##   a removable lid (surgery_vat.gd).
##
## The whole plan is laid out in its own frame (`_plan`, the booth's wall at its
## -X) turned to whichever of the four ways keeps the booth and the pens off the
## hall's ways in and the hatch off the rail (`_choose_plan`).

const Table := preload("res://scripts/surgical_table.gd")
const ControlRoom := preload("res://scripts/surgery_control.gd")
const Power := preload("res://scripts/surgery_power.gd")
const Vat := preload("res://scripts/surgery_vat.gd")
const ModuleMaze := preload("res://scripts/module_maze.gd")
const PROSTHETIC := preload("res://scripts/prosthetic.gd")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

## The Higgsfield kit (notes 95, 96, 98, 99, 102).
const K := {
	"jar": preload("res://models/surgery/jar.glb"),
	"chest": preload("res://models/surgery/chest.glb"),
	"candelabra": preload("res://models/surgery/candelabra.glb"),
	"barrels": preload("res://models/surgery/barrels.glb"),
	"beam": preload("res://models/surgery/beam.glb"),
	"brace": preload("res://models/surgery/brace.glb"),
	"casket": preload("res://models/surgery/casket.glb"),
	"crates": preload("res://models/surgery/crates.glb"),
	"bundle": preload("res://models/surgery/bundle.glb"),
	"chain": preload("res://models/surgery/chain.glb"),
	"prosthetic": preload("res://models/surgery/prosthetic.glb"),
	"wallframe": preload("res://models/surgery/wallframe.glb"),
	"lintel2": preload("res://models/surgery/lintel2.glb"),
	"frieze2": preload("res://models/surgery/frieze2.glb"),
	"girder": preload("res://models/surgery/girder.glb"),
	"floorrail": preload("res://models/surgery/floorrail.glb"),
	"traycart": preload("res://models/surgery/traycart.glb"),
	"portcullis": preload("res://models/surgery/portcullis.glb"),
	"penbars": preload("res://models/surgery/penbars.glb"),
	"shaftgrate": preload("res://models/surgery/shaftgrate.glb"),
	"vat_bones": preload("res://models/surgery/vat_bones.glb"),
	"vat_gold": preload("res://models/surgery/vat_gold.glb"),
}
const PLANKS := preload("res://textures/surgery_planks.png")
## How much each kit piece glows with its own picture (surgical_table.gd `glow`).
const GLOWS := {"jar": 1.1, "candelabra": 1.2, "vat_gold": 0.14, "vat_bones": 0.05}

## The walls: open frames BAY_DEPTH deep in front of the brick, CEIL tall.
const BAY_DEPTH := 0.5
## The wallframe's end colonettes, measured off the model (5 m wide, 0.5 deep):
## their middles this far either side of its centre, their faces this far in
## front of its middle -- where the wall torches hang (note 101).
const FRAME_POST_X := 2.07
const FRAME_POST_FRONT := 0.135
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

## The layout's cells (note 99's maze grid, still the plan's measure for the
## intake, the rail and the pens): N x N across the hall.
const N := 9

## The vats (note 102): a lattice VAT_STEP apart -- the dungeon's flagstone
## grid, so the hatch (cut where two flags meet) falls on one of its points --
## no further out than VAT_REACH. Kept clear: the middle (CLEAR_MIDDLE either
## way), CLEAR_RAIL either side of the rail, CLEAR_DOOR round each way in. A
## share VAT_LOOPS of the walls left standing after the aisles are carved is
## opened for loops. At most VAT_LIGHTS of the gold vats glow.
const VAT_STEP := 3.0
const VAT_REACH := 12.05
const CLEAR_MIDDLE := 3.1
const CLEAR_RAIL := 1.2
const CLEAR_DOOR := 3.2
const VAT_LOOPS := 0.15
const VAT_LIGHTS := 6
const VAT_OIL := Color(1.0, 0.62, 0.28)

const CANDLE_COLOUR := Color(1.0, 0.68, 0.38)

## --- Note 104 --------------------------------------------------------------------------
## The finished soldiers in the pens are real skeletons (prosthetic.gd), rooted
## and blind there until the claw throws one into the hall (surgical_table.gd
## FERRY, `turn_loose`); these hands, in turn.
const PEN_HANDS: Array[StringName] = [&"blade", &"hammer", &"drill", &"blade", &"shield", &"hammer"]
## The bars at the ways in (the kit's pen bars): sunk this far under the
## floor, raised over BARS_TIME; they wait for anyone standing in the way.
const BARS_DOWN := -3.9
const BARS_TIME := 0.9
const BARS_H := 3.7
## The vats across the ways in (note 105): this far out from the wall face, in
## the corridor's mouth, this much bigger than the rest.
const ENTRY_OUT := 1.2
const ENTRY_GROW := 1.26

var table: CharacterBody3D
var control: Node3D
var power: Node3D
var vats: Array[Node3D] = []

var _wall := 13.9
var _inner := 13.4
## A layout cell.
var _c := 2.98
## The ways in: [point on the wall face, the way out], room frame.
var _doorways: Array = []
## The frames' end colonettes: [their face at the floor, the wall], room frame.
var _posts: Array = []
## The plan's frame (see the header), and its turn in quarter turns.
var _plan: Node3D
var _turn := 0
## The hatch (module_level `_pick_surgery_hatch`): its hole, world, and the
## middle of the dungeon cell it is in.
var _hole := Vector3.ZERO
var _hole_cell := Vector3.ZERO
## The vats: their holder, the lattice's open slots, and which stands on the hatch.
var _vat_holder: Node3D
var _floor := {}
var _hatch_vat: Node3D
## The lattice's offset from the middle, plan frame (`_lattice_off`).
var _off := Vector2.ZERO

## Note 104: the entrance scene played (it plays once; saved), the bars up,
## the pens' soldiers and the ones thrown loose, where the pens' soldiers stand
## ([plan-frame point, yaw]), the vat across each way in, the bars.
var intro_done := false
var bars_up := false
var _want_bars := false
var _pen_spots: Array = []
var _pen: Array[Node3D] = []
var _loose: Array[Node3D] = []
var _entry_vats: Array = []
var _entry_bars: Array[Node3D] = []
var _entry_bar_bodies: Array[StaticBody3D] = []
var _intro_running := false
var _ferried_at = null
var _stocked := false


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
	_find_hatch()

	_raise_walls(h, cell)
	_build_walls(h, cell)
	_build_roof()
	_build_runways()
	_hang_wall_torches(h, cell)

	_choose_plan()
	_build_intake()
	_build_rail()
	_build_dispatch()
	_build_centre()
	_lay_vats()
	_block_entrances()

	_spawn_table()
	control = Node3D.new()
	control.set_script(ControlRoom)
	control.name = "ControlRoom"
	_plan.add_child(control)
	control.call("setup", self, table, _inner, _c)
	var boss: Node = control.get("boss")
	boss.connect("fight_started", _on_fight_started)
	boss.connect("defeated", _on_surgeon_defeated)
	_build_power()
	_build_bars()
	table.connect("depowered", _on_depowered)
	table.connect("woke", _on_woke)
	table.connect("ferried", func(at: Vector3) -> void: _ferried_at = at)
	_light_hall()
	_limit_view(_wall)
	print("[surgery] the surgical table asleep under its gantry; %d vats, one over the hatch at %s; the plan turned %d; %d bodies laid out"
		% [vats.size(), to_local(_hole).snapped(Vector3.ONE * 0.1), _turn * 90, _corpse_count])


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
				for s: float in [-1.0, 1.0]:
					_posts.append([base - d * FRAME_POST_FRONT + along * s * FRAME_POST_X * sx.x, d])


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


## A torch at every join between two frames, none at a way in -- on the face
## of the frame's end colonette beside the join. (The frame is open at the join
## itself, so a torch hung on the frames' front plane there stood in the air,
## half a metre out from the brick and clear of both colonettes: note 101.)
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
			var at := d * _inner + Vector3(-d.z, 0.0, d.x) * v
			if _door_distance(at) < 2.0:
				continue
			var post := _post_near(at, d)
			if post == Vector3.INF:
				continue
			level._hang_torch(self, scene, post + Vector3(0.0, TORCH_HEIGHT, 0.0), d, energy, 13.0)


## The colonette face on wall `d` nearest `at` (within a metre), or INF.
func _post_near(at: Vector3, d: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := 1.0
	for p in _posts:
		if (p[1] as Vector3).dot(d) < 0.9:
			continue
		var dist := (p[0] as Vector3).distance_to(at)
		if dist < best_d:
			best_d = dist
			best = p[0]
	return best


# --- The plan (notes 99, 102) --------------------------------------------------------

## The hatch's hole: where module_level cut it in the floor, or (a level built
## without it) a point on the flagstone grid the same way out from the middle.
func _find_hatch() -> void:
	var meta: Dictionary = built.get_meta("surgery_hatch", {})
	if not meta.is_empty():
		_hole = meta["world"]
		_hole_cell = meta["world"] - (meta["along"] as Vector3) * 1.5
		return
	_hole = to_global(Vector3(6.0, 0.0, 4.5))
	_hole_cell = to_global(Vector3(6.0, 0.0, 6.0))


## The plan's turn: the first quarter turn that keeps the booth's wall and the
## pens' wall clear of every way in and the hatch off the rail (or the one that
## clears most).
func _choose_plan() -> void:
	var best := 0
	var best_bad := 99
	var hole := to_local(_hole)
	for k in 4:
		var b := Basis(Vector3.UP, float(k) * PI * 0.5)
		var bad := 0
		for d in _doorways:
			var p: Vector3 = b.inverse() * (d[0] as Vector3)
			var dir: Vector3 = (b.inverse() * (d[1] as Vector3)).round()
			if dir.x < -0.5 and p.z < -_inner + 3.0 * _c + 2.2 and p.z > -_inner + _c - 2.2:
				bad += 1
			elif dir.x > 0.5 and absf(p.z) < 1.5 * _c + 2.2:
				bad += 1
		var hp := b.inverse() * hole
		if _rail_distance(hp, _lattice_off(hp)) < CLEAR_RAIL:
			bad += 2
		if bad < best_bad:
			best_bad = bad
			best = k
	_turn = best
	_plan = Node3D.new()
	_plan.name = "Plan"
	add_child(_plan)
	_plan.transform = Transform3D(Basis(Vector3.UP, float(_turn) * PI * 0.5), Vector3.ZERO)
	_off = _lattice_off(_plan.transform.inverse() * hole)
	if best_bad > 0:
		push_warning("surgery: %d conflict(s) between the ways in, the booth, the pens, the hatch and the rail" % best_bad)


## The middle of layout cell (i, j), plan frame, on the floor.
func cell_at(i: int, j: int) -> Vector3:
	return Vector3(-_inner + _c * (float(i) + 0.5), 0.0, -_inner + _c * (float(j) + 0.5))


## The vats' lattice for a hatch at `hole` (plan frame): it sits on a flag joint,
## one coordinate a whole number of VAT_STEPs from the middle and the other half
## a step out -- the lattice's offset from the middle in x and z.
static func _lattice_off(hole: Vector3) -> Vector2:
	var on_x := absf(hole.x / VAT_STEP - roundf(hole.x / VAT_STEP)) < 0.2
	return Vector2(0.0 if on_x else VAT_STEP * 0.5, VAT_STEP * 0.5 if on_x else 0.0)


## The rail's run (plan frame): out from under the booth along a row of the
## vats' lattice (`off`) -- one row kept clear for it, not two -- then down a
## column of it into the middle.
func _rail_points(off := _off) -> PackedVector3Array:
	var z := roundf((-_inner + _c * 2.0 - off.y) / VAT_STEP) * VAT_STEP + off.y
	var x := roundf(-off.x / VAT_STEP) * VAT_STEP + off.x
	return PackedVector3Array([Vector3(-_inner + _c * 0.6, 0.0, z), Vector3(x, 0.0, z),
		Vector3(x, 0.0, -CLEAR_MIDDLE)])


## How far `p` (plan frame) is from the rail, across the floor.
func _rail_distance(p: Vector3, off := _off) -> float:
	var pts := _rail_points(off)
	var best := INF
	for s in pts.size() - 1:
		var a := Vector2(pts[s].x, pts[s].z)
		var b := Vector2(pts[s + 1].x, pts[s + 1].z)
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


# --- The vats (note 102) -----------------------------------------------------------

## A lattice point kept clear of vats: the middle, the booth's intake under it,
## the pens, the rail, the ways in.
func _kept_clear(p: Vector3) -> bool:
	if absf(p.x) <= CLEAR_MIDDLE and absf(p.z) <= CLEAR_MIDDLE:
		return true
	if p.x < -9.5 and p.z > -_inner + _c - 1.6 and p.z < -_inner + _c * 3.0 + 1.0:
		return true
	if p.x > -_inner + _c * float(N - 1) - 1.0 and absf(p.z) < 1.5 * _c + 1.1:
		return true
	if _rail_distance(p) < CLEAR_RAIL:
		return true
	return _door_distance(_plan.transform * p) < CLEAR_DOOR


## The vats laid out on the lattice through the hatch: the lattice's points split
## into junctions (both indices of one parity), the walls between them and the
## pillars at the corners, as a maze's cells and walls; every junction open, a
## random spanning tree of walls opened between them (Kruskal, the room's own
## generator), VAT_LOOPS of the rest, then whatever is still cut off joined up.
## A vat on every point left shut. The hatch is a wall between two junctions,
## never opened: its vat can be shoved off it into the aisle either side.
func _lay_vats() -> void:
	_vat_holder = Node3D.new()
	_vat_holder.name = "Vats"
	add_child(_vat_holder)
	var hole := _plan.transform.inverse() * to_local(_hole)



	var off := _off
	var xs: Array[float] = []
	var zs: Array[float] = []
	var v := off.x - floorf((VAT_REACH + off.x) / VAT_STEP) * VAT_STEP
	while v <= VAT_REACH:
		xs.append(v)
		v += VAT_STEP
	v = off.y - floorf((VAT_REACH + off.y) / VAT_STEP) * VAT_STEP
	while v <= VAT_REACH:
		zs.append(v)
		v += VAT_STEP
	var hi := 0
	var hj := 0
	for i in xs.size():
		if absf(xs[i] - hole.x) < absf(xs[hi] - hole.x):
			hi = i
	for j in zs.size():
		if absf(zs[j] - hole.z) < absf(zs[hj] - hole.z):
			hj = j
	var hatch := Vector2i(hi, hj)
	# Junction parity: the hatch a wall across X if it can be, else across Z.
	var par := Vector2i((hi + 1) % 2, hj % 2)
	if hi == 0 or hi == xs.size() - 1:
		par = Vector2i(hi % 2, (hj + 1) % 2)
	var at := func(s: Vector2i) -> Vector3: return Vector3(xs[s.x], 0.0, zs[s.y])
	var inside := func(s: Vector2i) -> bool: return s.x >= 0 and s.y >= 0 and s.x < xs.size() and s.y < zs.size()
	_floor.clear()
	var junctions: Array[Vector2i] = []
	var walls: Array = []
	for i in xs.size():
		for j in zs.size():
			var s := Vector2i(i, j)
			var jx := i % 2 == par.x
			var jz := j % 2 == par.y
			var clear: bool = _kept_clear(at.call(s))
			if jx and jz:
				junctions.append(s)
				_floor[s] = true
			elif clear and s != hatch:
				_floor[s] = true
			if jx != jz:
				# A wall: between the junctions either side of it.
				var step := Vector2i(1, 0) if not jx else Vector2i(0, 1)
				if inside.call(s - step) and inside.call(s + step):
					walls.append([s, s - step, s + step])
	# Kruskal over the junctions; the walls already open (kept clear) first.
	var uf := {}
	for s in junctions:
		uf[s] = s
	var find := func(a: Vector2i) -> Vector2i:
		while uf[a] != a:
			uf[a] = uf[uf[a]]
			a = uf[a]
		return a
	var shut: Array = []
	for w in walls:
		if _floor.has(w[0]):
			var ra: Vector2i = find.call(w[1])
			var rb: Vector2i = find.call(w[2])
			uf[ra] = rb
		elif w[0] != hatch:
			shut.append(w)
	for i in range(shut.size() - 1, 0, -1):
		var k := _rng.randi_range(0, i)
		var t = shut[i]
		shut[i] = shut[k]
		shut[k] = t
	var left: Array = []
	for w in shut:
		var ra: Vector2i = find.call(w[1])
		var rb: Vector2i = find.call(w[2])
		if ra != rb:
			uf[ra] = rb
			_floor[w[0]] = true
		else:
			left.append(w)
	for w in left:
		if _rng.randf() < VAT_LOOPS:
			_floor[w[0]] = true
	_join_up(xs.size(), zs.size(), hatch)
	# The vats: one on every point left shut, the hatch's among them.
	var n := 0
	var lights := 0
	for i in xs.size():
		for j in zs.size():
			var s := Vector2i(i, j)
			if _floor.has(s):
				continue
			var kind := "vat_gold" if _rng.randf() < 0.45 else "vat_bones"
			var glow := kind == "vat_gold" and lights < VAT_LIGHTS and _rng.randf() < 0.5
			if glow:
				lights += 1
			var vat := _vat(at.call(s), kind, glow, n)
			if s == hatch:
				_hatch_vat = vat
			n += 1


## Every open point reachable from the middle: a cut-off pocket is joined to the
## rest along the shortest run of points (never through the hatch's).
func _join_up(nx: int, nz: int, hatch: Vector2i) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var start := Vector2i(-1, -1)
	var best := INF
	for s: Vector2i in _floor:
		var d := Vector2(s.x - (nx - 1) * 0.5, s.y - (nz - 1) * 0.5).length()
		if d < best:
			best = d
			start = s
	if start.x < 0:
		return
	for guard in 40:
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_front()
			for d in dirs:
				var o: Vector2i = c + d
				if _floor.has(o) and not seen.has(o):
					seen[o] = true
					queue.append(o)
		var lost := Vector2i(-1, -1)
		for s: Vector2i in _floor:
			if not seen.has(s):
				lost = s
				break
		if lost.x < 0:
			return
		# From the lost pocket to anything reached, over any point but the hatch.
		var from := {lost: lost}
		var q2: Array[Vector2i] = [lost]
		var hit := Vector2i(-1, -1)
		while not q2.is_empty() and hit.x < 0:
			var c: Vector2i = q2.pop_front()
			for d in dirs:
				var o: Vector2i = c + d
				if o.x < 0 or o.y < 0 or o.x >= nx or o.y >= nz or o == hatch or from.has(o):
					continue
				from[o] = c
				if seen.has(o):
					hit = o
					break
				q2.append(o)
		if hit.x < 0:
			return
		var c: Vector2i = from[hit]
		while c != lost:
			_floor[c] = true
			c = from[c]


## A vat at `at` (plan frame), turned at random: the tub, its collision and its
## shove (surgery_vat.gd); some of the gold ones with the oil's glow.
func _vat(at: Vector3, kind: String, glow: bool, i: int, grow := 1.0) -> Node3D:
	var vat := CharacterBody3D.new()
	vat.set_script(Vat)
	vat.name = "Vat%d" % i
	vat.set("grow", grow)
	_vat_holder.add_child(vat)
	vat.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), _plan.transform * at)
	var model := _kit(vat, kind, Vector3.ZERO, 0.0, Vector3.ZERO, Vector3.ONE * grow)
	vat.set("model", model)
	vat.set("home", vat.transform)
	vat.set("kind", kind)
	vat.call("fit_lid")
	if glow:
		var oil := OmniLight3D.new()
		oil.name = "Oil"
		oil.light_color = VAT_OIL
		oil.light_energy = 0.9
		oil.omni_range = 5.5
		oil.omni_attenuation = 1.2
		oil.light_specular = 0.15
		oil.shadow_enabled = false
		oil.position = Vector3(0.0, 2.0, 0.0)
		vat.add_child(oil)
	vats.append(vat)
	return vat


# --- Intake, assembly, dispatch --------------------------------------------------------

## INTAKE, under the control room: the tray carts unloaded there, crates of
## remains, caskets waiting.
func _build_intake() -> void:
	var a := cell_at(0, 1)
	var b := cell_at(0, 2)
	_kit(_plan, "traycart", a + Vector3(-0.35, 0.0, -0.45), 0.0, Vector3(0.9, 0.7, 2.2))
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


## ASSEMBLY: the floor rail from the intake to the middle (along a row of the
## vats' lattice, then down a column of it), and a tray cart that runs it.
var _rail: PackedVector3Array
var _cart: Node3D
var _cart_t := 0.0


func _build_rail() -> void:
	_rail = _rail_points()
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
	_cart = _kit(holder, "traycart", _rail[0], atan2(1.0, 0.0))



func _run_cart(delta: float) -> void:
	if _cart == null or table == null:
		return
	# Out to the middle and back, resting at each end, while the machine has
	# power; stopped where it is once it has none.
	if bool(table.call("is_depowered")) or table.get("state") == Table.State.DORMANT:
		return
	var was := _cart_t
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
	# A vat shoved onto the rail stops it (note 102): it waits behind it.
	var world := _plan.global_transform * at
	for v in vats:
		var to := v.global_position - world
		if Vector2(to.x, to.z).length() < Vat.RADIUS + 0.75:
			_cart_t = was
			return
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
	# Where the soldiers stand, in two ranks (real ones, note 104: `stock_pens`),
	# and their shipping caskets.
	for k in 6:
		var j := 3 + k % 3
		var row := float(k / 3)
		var at := cell_at(N - 1, j) + Vector3(-0.55 + row * 0.9, 0.0, _rng.randf_range(-0.5, 0.5))
		_pen_spots.append([at, -PI * 0.5 + _rng.randf_range(-0.25, 0.25)])
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


## A dim warm fill high in the middle: the roof and the vats' rims would be
## black otherwise (the claw's lamp and the glowing vats light only below them).
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


# --- The powering room (note 102) ------------------------------------------------------

## The hatch and the room under it (surgery_power.gd), in a frame at the hole:
## +Z the way toward the hall's middle (squared to the hall), so the room runs
## in under the hall from its ladder.
func _build_power() -> void:
	var hole := to_local(_hole)
	hole.y = 0.0
	var toward := -hole
	toward = Vector3(signf(toward.x), 0.0, 0.0) if absf(toward.x) > absf(toward.z) else Vector3(0.0, 0.0, signf(toward.z))
	if toward == Vector3.ZERO:
		toward = Vector3(0.0, 0.0, 1.0)
	power = Node3D.new()
	power.set_script(Power)
	power.name = "PoweringRoom"
	add_child(power)
	power.transform = Transform3D(Basis.looking_at(-toward, Vector3.UP), hole)
	power.call("setup", self, table, control, _hole_cell)


# --- The ways in: a vat across each, and the bars (note 104) ----------------------------

## A vat across each way in (the user: the player "pushes a vat out of the way
## of the entrance, so the player knows vats are pushable"; note 105: "the
## blocking vat needs to actually block the player, so to get in the player has
## to push it"): in the corridor's mouth, ENTRY_OUT outside the wall face, where
## it is 3.4 m wide -- and ENTRY_GROW times a vat's size, 1.45 m in radius, so
## there is no gap a player (0.4 m) gets by. Shoving it starts the entrance scene
## (`_on_entry_shoved`).
func _block_entrances() -> void:
	_entry_vats.clear()
	for k in _doorways.size():
		var d: Array = _doorways[k]
		var at: Vector3 = (d[0] as Vector3) + (d[1] as Vector3) * ENTRY_OUT
		at.y = 0.0
		var kind := "vat_bones" if k % 2 == 0 else "vat_gold"
		var vat := _vat(_plan.transform.inverse() * at, kind, false, vats.size(), ENTRY_GROW)
		vat.set("entry", true)
		vat.connect("shove_started", _on_entry_shoved.bind(k))
		_entry_vats.append(vat)


## The kit's pen bars in each way in, sunk under the floor until the claw
## shuts them in (`raise_bars`), with its collision off till then.
func _build_bars() -> void:
	# The ways in are about this wide (the level's corridors; its cells are 6 m).
	var opening := 3.2
	for d in _doorways:
		var dir: Vector3 = d[1]
		var holder := Node3D.new()
		holder.name = "EntranceBars"
		add_child(holder)
		holder.position = Vector3((d[0] as Vector3).x, BARS_DOWN, (d[0] as Vector3).z)
		holder.rotation.y = atan2(dir.x, dir.z)
		# The pens' spiked bars (the kit's portcullis is a solid riveted plate: it
		# read as a door), stretched up to the arch.
		var bars := _kit(holder, "penbars", Vector3.ZERO, 0.0)
		bars.scale = Vector3(opening / 2.97, BARS_H / 2.4, 1.0)
		var body := _solid(holder, Vector3(opening + 0.4, BARS_H, 0.5), Vector3(0.0, BARS_H * 0.5, 0.0))
		body.collision_layer = 0
		holder.visible = false
		_entry_bars.append(holder)
		_entry_bar_bodies.append(body)


## Shut in: the bars come up out of the floor at every way in. `now`: at once.
func raise_bars(now := false) -> void:
	_want_bars = false
	if bars_up:
		return
	bars_up = true
	for i in _entry_bars.size():
		var b := _entry_bars[i]
		b.visible = true
		_entry_bar_bodies[i].collision_layer = 1 | 2
		if now:
			b.position.y = 0.0
			continue
		var tw := b.create_tween()
		tw.tween_property(b, "position:y", 0.0, BARS_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if table != null:
			table.call("_impact_fx", b.global_position, 0.35)
	for p in Coop.all():
		var n := p as Node3D
		if n != null and n.get("_shake") != null:
			n.set("_shake", maxf(float(n.get("_shake")), 0.35))


## The bars back down into the floor (the machine off; a world reset).
func lower_bars(now := false) -> void:
	_want_bars = false
	if not bars_up:
		return
	bars_up = false
	for i in _entry_bars.size():
		var b := _entry_bars[i]
		_entry_bar_bodies[i].collision_layer = 0
		if now:
			b.position.y = BARS_DOWN
			b.visible = false
			continue
		var tw := b.create_tween()
		tw.tween_property(b, "position:y", BARS_DOWN, BARS_TIME * 1.6).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void: b.visible = false)


## Anyone standing in a way in (the bars wait for them to step through).
func _someone_in_doorway() -> bool:
	for p in Coop.all():
		var l := to_local((p as Node3D).global_position)
		for d in _doorways:
			if Vector2(l.x - (d[0] as Vector3).x, l.z - (d[0] as Vector3).z).length() < 1.3:
				return true
	return false


func _on_woke() -> void:
	if _intro_running:
		return
	# Woken without the scene (a world reset, the sandbox's teleport): no scene
	# now, but they are shut in all the same.
	intro_done = true
	_want_bars = true


## The machine off: the bars stay up -- there is still the surgeon to fight
## (note 105). Off from the booth, he is lying in the hall: he gets up.
func _on_depowered(cause: StringName) -> void:
	if cause == &"control" and control != null:
		control.call("surgeon_rises")


## His fight begun: shut in, if they were not.
func _on_fight_started() -> void:
	_want_bars = true


## He is dead: the bars come down; the room is done.
func _on_surgeon_defeated() -> void:
	lower_bars()


## Whether `at` (world) is in the hall, on its floor or up to the roof (not
## down in the powering room, nor out in a corridor).
func in_hall(at: Vector3) -> bool:
	var l := to_local(at)
	return absf(l.x) < _inner + 0.3 and absf(l.z) < _inner + 0.3 and l.y > -1.0 and l.y < 7.0


# --- The pens' soldiers (note 104) ----------------------------------------------------

## The pens filled: a soldier on every spot, rooted and blind (as the maze's jail
## cells keep theirs) until the claw throws it out.
func stock_pens() -> void:
	_stocked = true
	for e in _pen + _loose:
		if is_instance_valid(e):
			e.free()
	_pen.clear()
	_loose.clear()
	for k in _pen_spots.size():
		var spot: Array = _pen_spots[k]
		_pen_soldier(_plan.global_transform * (spot[0] as Vector3), _plan.global_rotation.y + float(spot[1]), PEN_HANDS[k % PEN_HANDS.size()])


func _pen_soldier(at: Vector3, yaw: float, hand: StringName) -> Node3D:
	var e := PROSTHETIC.make(ENEMY_SCENE, hand) as CharacterBody3D
	e.name = "PenSoldier"
	add_child(e)
	e.global_position = at + Vector3(0.0, 0.05, 0.0)
	e.global_rotation = Vector3(0.0, yaw, 0.0)
	e.set("wanders", false)
	e.set("aggro_range", 0.5)
	_pen.append(e)
	return e


## The pen soldier nearest `at` (world), or null.
func pen_soldier_for(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in _pen:
		if not is_instance_valid(e) or e.get("_dying") == true:
			continue
		var d := e.global_position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = e
	return best


## In the claw's grip: no longer one of the pens'.
func soldier_taken(e: Node3D) -> void:
	_pen.erase(e)


## Thrown into the hall: an ordinary enemy, off its leash, after the players
## (maze.gd `_turn_loose`).
func turn_loose(e: Node3D) -> void:
	_pen.erase(e)
	if not _loose.has(e):
		_loose.append(e)
	e.set("wanders", false)
	e.set("wander_spots", [] as Array[Vector3])
	e.set("aggro_range", 70.0)
	e.set("vision_cone_degrees", 0.0)
	e.set("sight_needs_line_of_sight", false)
	e.set("_dormant", false)
	e.set("_seen_until", Time.get_ticks_msec() / 1000.0 + 9999.0)


## Thrown soldiers still up.
func loose_count() -> int:
	var n := 0
	for e in _loose:
		if is_instance_valid(e) and e.get("_dying") != true:
			n += 1
	return n


## Where the entrance scene's prisoner is set down: the middle pen (world).
func pen_drop_point() -> Vector3:
	return _plan.global_transform * (cell_at(N - 1, 4) + Vector3(0.3, 0.0, 0.0))


# --- The entrance scene (note 104) -----------------------------------------------------

## A player has begun shoving the vat across way in `k` (note 105: the scene
## starts "when the player actually starts pushing the blocking vat"), the claw
## asleep: the scene.
func _on_entry_shoved(p: Node3D, k: int) -> void:
	if intro_done or _intro_running or table == null or bool(table.call("is_depowered")) \
			or table.get("state") != Table.State.DORMANT or p == null:
		return
	_intro(p, k)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


## The user: "When the player walks up to the door of the surgery room, a
## cutscene should start where the player pushes a vat out of the way of the
## entrance ..., walks into the room as the claw is working on making a
## soldier, it dropping the soldier into the finished area, noticing the
## player, and raising bars at the entrances, blocking the player from
## escaping. Then, right as the claw starts targeting the player, give the
## player control back."
func _intro(p: Node3D, k: int) -> void:
	_intro_running = true
	intro_done = true
	var everyone: Array[Node3D] = []
	for q in Coop.all():
		var n := q as Node3D
		if n != null and n.get("_dead") != true and n.get("in_cutscene") != true:
			everyone.append(n)
			n.call("begin_cutscene")
	var bars := WoodDoor.letterbox(self)
	table.call("begin_work")
	var door: Vector3 = to_global((_doorways[k][0] as Vector3))
	var inward: Vector3 = -(global_basis * (_doorways[k][1] as Vector3)).normalized()
	var side := Vector3.UP.cross(inward).normalized()
	var vat: Node3D = _entry_vats[k] if k < _entry_vats.size() else null
	var claw := func() -> Vector3:
		var c := table.get_node_or_null("Claw") as Node3D
		return c.global_position + Vector3(0.0, -0.8, 0.0) if c != null else table.global_position + Vector3(0.0, 2.0, 0.0)
	for n in everyone:
		if n != p:
			n.call("scene_look_at", claw.call(), 3.0)

	# 1. Shoulder to the vat in the way (they had begun to): shoved in out of the
	# corridor, then on into the hall and to whichever side has more room.
	if vat != null and is_instance_valid(vat):
		var r: float = vat.get("radius")
		var v := vat.global_position
		var lean := side if _room_to(door + inward * 2.0 + side * 2.6) >= _room_to(door + inward * 2.0 - side * 2.6) else -side
		p.call("scene_look_at", v + Vector3(0.0, 1.2, 0.0), 5.0)
		p.call("scene_lean", Vector3(0.0, -0.15, -0.1), 6.0)
		for leg: Vector3 in [Vector3(door.x, v.y, door.z) + inward * 0.6, Vector3(door.x, v.y, door.z) + inward * 1.9 + lean * 1.8]:
			var from := vat.global_position
			var push := (leg - from).normalized()
			vat.call("scripted_push", leg, 1.5)
			var behind := leg - push * (r + 0.5)
			behind.y = p.global_position.y
			p.call("scene_walk_to", behind, 1.7)
			await Signal(p, &"scene_walk_finished")
			await _wait(0.15)
		p.call("scene_lean", Vector3.ZERO, 4.0)
		# 2. In past it, the claw at its work beyond.
		var inside := door + inward * 4.6 - lean * 1.7
		inside.y = p.global_position.y
		p.call("scene_look_at", claw.call(), 2.5)
		p.call("scene_walk_to", inside, 4.0)
		await Signal(p, &"scene_walk_finished")
	await _wait(0.5)

	# 3. Its work done: the soldier lifted off the table and dropped in the pens.
	_ferried_at = null
	table.call("ferry_prisoner", pen_drop_point())
	var t := 0.0
	while _ferried_at == null and t < 12.0:
		for n in everyone:
			n.call("scene_look_at", claw.call(), 4.0)
		await get_tree().process_frame
		t += get_process_delta_time()
	if _ferried_at != null:
		var at: Vector3 = _ferried_at
		var e := _pen_soldier(Vector3(at.x, global_position.y + 0.6, at.z), _plan.global_rotation.y - PI * 0.5, &"blade")
		table.call("_impact_fx", Vector3(at.x, global_position.y, at.z), 0.3)
		e.velocity = Vector3.ZERO
	await _wait(0.6)

	# 4. It turns on them.
	for n in everyone:
		n.call("scene_look_at", claw.call(), 6.0)
	table.call("notice")
	await _wait(0.7)

	# 5. The bars come up behind them.
	for n in everyone:
		n.call("scene_look_at", door + Vector3(0.0, 1.4, 0.0), 5.0)
	await _wait(0.35)
	raise_bars()
	await _wait(1.1)

	# 6. Back to it as it comes for them: control back.
	for n in everyone:
		n.call("scene_look_at", claw.call(), 6.0)
	await _wait(0.5)
	WoodDoor.letterbox_out(bars)
	for n in everyone:
		if is_instance_valid(n) and n.get("in_cutscene") == true:
			n.call("scene_look_at", null)
			n.call("end_cutscene")
	_intro_running = false


## How clear the floor is round `at` (world): the distance to the nearest vat.
func _room_to(at: Vector3) -> float:
	var best := INF
	for v in vats:
		var d := Vector2(v.global_position.x - at.x, v.global_position.z - at.z).length()
		best = minf(best, d)
	return best


# --- Each frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_run_cart(delta)
	# The pens filled once the level is up (note 105: the sandbox never repopulates
	# the level, so `on_world_reset` never ran there and the pens stood empty).
	if not _stocked:
		var maze := get_tree().get_first_node_in_group(&"maze")
		if maze != null and maze.get("is_built"):
			stock_pens()
	if _want_bars and not _someone_in_doorway():
		raise_bars()


# --- Saving and resetting ----------------------------------------------------------------

## The machine (off, and where the claw lies), where every vat stands, the hatch,
## the crystal, the surgeon.
func save_state() -> Dictionary:
	var out := {"down": false}
	if table != null and bool(table.call("is_depowered")):
		var p: Vector3 = table.call("rest_point")
		out = {"down": true, "at": [p.x, p.y, p.z]}
	var places: Array = []
	for v in vats:
		var at := to_local(v.global_position)
		places.append([at.x, at.z, v.global_rotation.y - global_rotation.y])
	out["vats"] = places
	# Note 104: the lids, the entrance scene, the booth taken.
	var lids: Array = []
	for v in vats:
		lids.append(bool(v.get("lid_on")))
	out["lids"] = lids
	out["intro"] = intro_done
	if control != null:
		out["booth"] = bool(control.get("surgeon_thrown"))
		# Note 105: the surgeon, dead (and where he lies) or not.
		var boss: Node3D = control.get("boss")
		if boss != null and bool(boss.call("is_dead")):
			var bt := to_local(boss.global_position)
			out["surgeon_dead"] = [bt.x, bt.y, bt.z, boss.global_rotation.y - global_rotation.y]
	if power != null:
		out["hatch"] = bool(power.get("hatch_open"))
		out["crystal"] = bool(power.get("crystal_gone"))
		out["gone"] = bool(power.get("surgeon_gone"))
	return out


func restore_state(data: Dictionary) -> void:
	var places: Array = data.get("vats", [])
	if places.size() == vats.size():
		for i in vats.size():
			var p: Array = places[i]
			vats[i].call("place", to_global(Vector3(float(p[0]), 0.0, float(p[1]))), global_rotation.y + float(p[2]))
	var lids: Array = data.get("lids", [])
	if lids.size() == vats.size():
		for i in vats.size():
			vats[i].call("set_lid", bool(lids[i]), true)
	intro_done = bool(data.get("intro", false))
	if power != null and bool(data.get("hatch", false)):
		power.call("set_open_now")
	if control != null and bool(data.get("booth", false)) and not bool(data.get("down", false)):
		# Kicked in but the lever not yet thrown (note 106).
		control.call("set_kicked_now")
	if table == null or not bool(data.get("down", false)):
		return
	var at: Array = data.get("at", [])
	var p := table.global_position if at.size() < 3 else Vector3(float(at[0]), float(at[1]), float(at[2]))
	table.call("set_dead_now", p, 0.0)
	lower_bars(true)
	if control != null and bool(data.get("booth", false)):
		# Taken from the booth (note 104): the door in, the surgeon thrown out.
		control.call("set_thrown_now")
		_restore_surgeon(data)
		return
	if power != null:
		# A save from before note 102 had it off by the control room's lever:
		# the crystal out and the surgeon gone, as if it had been pulled.
		var old := not data.has("crystal")
		power.call("set_taken_now", old or bool(data.get("gone", false)))
	if control != null:
		# Off by the crystal: he has come down into the hall (note 105) --
		# whether or not the save was made before they climbed back out.
		control.call("leave")
	_restore_surgeon(data)


## The surgeon from a save (note 105): dead where he fell, or (by default)
## waiting in the hall to fight.
func _restore_surgeon(data: Dictionary) -> void:
	var dead: Array = data.get("surgeon_dead", [])
	if control == null or dead.size() < 4:
		return
	var at := Transform3D(Basis(Vector3.UP, global_rotation.y + float(dead[3])), to_global(Vector3(float(dead[0]), float(dead[1]), float(dead[2]))))
	control.call("restore_boss", true, at)


## Everyone died: with the table still running, all of it back as it was --
## the vats where they stood (but one already shoved off an open hatch, and
## any whose place it now stands in).
func on_world_reset() -> void:
	# The pens full again, the thrown ones gone (note 104) -- the enemies are
	# restored with everyone else's.
	stock_pens()
	if table == null:
		return
	if bool(table.call("is_depowered")):
		# The machine off but the surgeon still up (note 105): whole again,
		# waiting in the hall; the bars down till they come back in.
		if control != null:
			control.call("reset_boss")
		lower_bars(true)
		return
	table.call("reset_to_sleep")
	lower_bars(true)
	var stay: Array[Node3D] = []
	if power != null and bool(power.get("hatch_open")):
		for v in vats:
			var home: Transform3D = global_transform * (v.get("home") as Transform3D)
			if Vector2(home.origin.x - _hole.x, home.origin.z - _hole.z).length() < Power.COVERED:
				stay.append(v)
	for v in vats:
		if stay.has(v):
			continue
		var home: Transform3D = global_transform * (v.get("home") as Transform3D)
		var blocked := false
		for s in stay:
			if Vector2(home.origin.x - s.global_position.x, home.origin.z - s.global_position.z).length() < Vat.RADIUS * 2.0:
				blocked = true
		if not blocked:
			v.call("go_home", self)


## Down in the powering room, a step off the ladder's foot, facing the crystal:
## [position, yaw] (sandbox teleport).
func powering_room_point() -> Array:
	var at: Vector3 = power.global_transform * Vector3(0.0, Power.FLOOR_Y + 0.3, 1.2)
	var ahead: Vector3 = power.global_basis * Vector3(0.0, 0.0, 1.0)
	return [at, atan2(-ahead.x, -ahead.z)]


## Just inside the way in, facing the table: [position, yaw] (sandbox teleport).
func entry_point() -> Array:
	var doors: Array = built.room_doors(room)
	if doors.is_empty():
		return [global_position + Vector3(0.0, 0.3, 0.0), global_rotation.y]
	var d: Dictionary = doors[0]
	var step: Vector2i = d["outward"]
	var inward := -Vector3(float(step.x), 0.0, float(step.y))
	# Inside and to one side: a vat stands across the way in (note 104).
	var side := Vector3.UP.cross(inward).normalized()
	var at: Vector3 = d["world"] + inward * 2.4 + side * 2.1 + Vector3(0.0, 0.3, 0.0)
	return [at, atan2(-inward.x, -inward.z)]
