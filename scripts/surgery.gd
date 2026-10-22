extends "res://scripts/morgue.gd"

## The surgery (2026-10-21; refurnished after the user's reference picture,
## note 95; an open medieval hall, note 96; rebuilt, note 98): the hall where
## the dead prisoners were made bionic and shipped out. An enclosed hall
## (module_level `_make_surgery_hall`, the chest room nearest the boss, note 97;
## this extends morgue.gd for its torches and bodies), no piers, no vaults.
##
## EVERYTHING in it is a Higgsfield asset (note 98: "no original assets or
## models that were made directly in claude"): gpt_image_2_5 pictures, Tripo
## H3.1 models, fitted by tools/build_surgery_kit.py into models/surgery/. The
## two flat things are flat by nature -- the plank ceiling and the anatomy
## chart carry generated textures.
##
## The architecture (`_build_walls`, `_build_roof`): every wall a run of carved
## gothic stone bays between engaged pilasters, a diagonal pilaster in each
## corner, a skull lintel and a tracery frieze over each way in; a plank ceiling
## on oak beams in sections, each end on a grotesque stone corbel with an oak
## brace. Torches hang on the pilasters, chandeliers on chains from the beams.
##
## The hall in four corners (`_zones`), chosen from where the ways in are:
## - the STUDY, the corner furthest from them: bookcases, a writing desk and
##   chair, a lectern with its grimoire, an armillary sphere, a rug, piles of
##   books, a candelabra;
## - the SHIPPING corner, the one nearest a way in: upright shipping caskets,
##   a cage cart, pallets of crates, a hand cart, barrels, and an overhead
##   monorail of hooks with the finished subjects hanging wrapped from them;
## - the LAB: laboratory benches of glassware, a copper still, specimen jars,
##   the worktable, an apothecary shelf, the anatomy chart;
## - the TRIALS: the testing chair, a galvanic machine, slabs with subjects
##   fitted with their new arms, an iron maiden, the tool rack, the rack and
##   the pillory, gibbet cages from the beams, the older dead.
## In the middle the machine that did the work: the surgical table
## (scripts/surgical_table.gd) inside its floor rail, the claw folded under the
## ring until a player walks in -- then it follows them, slams down to grab
## them, and straps them to the table.
##
## What is in here to beat it with -- nothing marked, all of it to be watched:
## - THREE WALL MECHANISMS, one per system, each joined to the table by its own
##   thick cable across the floor: the ARMS' pistons and gear (their cable
##   twitches whenever the claw strikes), the HOIST's flywheel (the "legs"
##   system; its cable shivers as the claw travels), the CORE's glass column
##   (its cable carries the core's pulse).
## - THREE LEVERS on their posts, which system each cuts shuffled per seed. A
##   pull cuts it for a while (surgical_table.gd `cut`) and shows something:
##   cutting the arms springs the wall CLAMP open (it sits on the arms' relay)
##   and makes the claw let go of whoever it holds; cutting the hoist drops the
##   claw and stops the flywheel, which can then be JAMMED with the iron bar
##   hanging beside it; cutting the core stalls the table until the other two
##   cables flare and feed it back.
## - THE CLAMP in the middle of a wall: once open, a slam brought down by its
##   jaws is caught there, the power cable at the claw's wrist in reach --
##   until the hoist tears it free.
## Depowered the claw crashes to the floor, its light goes out, the lamp in the
## ring dies with it and its hum -- the only machine sound in the dungeon --
## stops.

const Table := preload("res://scripts/surgical_table.gd")
const CABLE_SHADER := preload("res://shaders/surgery_cable.gdshader")
const ModuleMaze := preload("res://scripts/module_maze.gd")

## The systems, in the order of the table's plugs.
const SYSTEMS: Array[StringName] = [&"arms", &"legs", &"core"]
## Sections in each cable.
const CABLE_SECTIONS := 30
const CABLE_RADIUS := 0.08
const CABLE_REPATH := 0.25
## The clamp catches the claw slammed down this close to its mouth (along
## the floor).
const CATCH := 1.8
## Its jaws' mouth, from the bay's face.
const CLAMP_MOUTH := Vector3(0.0, 1.35, 1.6)
## The levers: each on its post standing here (room frame), facing the given
## side, its handle's pivot at this height.
const LEVER_PIERS := [[Vector3(-9.0, 0.0, 3.0), Vector3.RIGHT], [Vector3(9.0, 0.0, -3.0), Vector3.LEFT],
	[Vector3(3.0, 0.0, -9.0), Vector3.BACK]]
const LEVER_HEIGHT := 1.42
const LEVER_REACH := 2.4
## The lamp: in the hub of the ceiling ring.
const LAMP_HEIGHT := 6.55

## The Higgsfield kit (notes 95, 96, 98).
const K := {
	"shelf": preload("res://models/surgery/shelf.glb"),
	"jar": preload("res://models/surgery/jar.glb"),
	"worktable": preload("res://models/surgery/worktable.glb"),
	"chest": preload("res://models/surgery/chest.glb"),
	"chandelier": preload("res://models/surgery/chandelier.glb"),
	"maiden": preload("res://models/surgery/maiden.glb"),
	"rack": preload("res://models/surgery/rack.glb"),
	"gibbet": preload("res://models/surgery/gibbet.glb"),
	"brazier": preload("res://models/surgery/brazier.glb"),
	"pillory": preload("res://models/surgery/pillory.glb"),
	"toolrack": preload("res://models/surgery/toolrack.glb"),
	"barrels": preload("res://models/surgery/barrels.glb"),
	"candelabra": preload("res://models/surgery/candelabra.glb"),
	"wallbay": preload("res://models/surgery/wallbay.glb"),
	"jamb": preload("res://models/surgery/jamb.glb"),
	"lintel": preload("res://models/surgery/lintel.glb"),
	"frieze": preload("res://models/surgery/frieze.glb"),
	"beam": preload("res://models/surgery/beam.glb"),
	"brace": preload("res://models/surgery/brace.glb"),
	"corbel": preload("res://models/surgery/corbel.glb"),
	"bookcase": preload("res://models/surgery/bookcase.glb"),
	"desk": preload("res://models/surgery/desk.glb"),
	"lectern": preload("res://models/surgery/lectern.glb"),
	"globe": preload("res://models/surgery/globe.glb"),
	"rug": preload("res://models/surgery/rug.glb"),
	"books": preload("res://models/surgery/books.glb"),
	"railring": preload("res://models/surgery/railring.glb"),
	"labbench": preload("res://models/surgery/labbench.glb"),
	"galvanic": preload("res://models/surgery/galvanic.glb"),
	"testchair": preload("res://models/surgery/testchair.glb"),
	"still": preload("res://models/surgery/still.glb"),
	"slab": preload("res://models/surgery/slab.glb"),
	"casket": preload("res://models/surgery/casket.glb"),
	"cagecart": preload("res://models/surgery/cagecart.glb"),
	"crates": preload("res://models/surgery/crates.glb"),
	"handcart": preload("res://models/surgery/handcart.glb"),
	"track": preload("res://models/surgery/track.glb"),
	"hook": preload("res://models/surgery/hook.glb"),
	"bundle": preload("res://models/surgery/bundle.glb"),
	"leverbox": preload("res://models/surgery/leverbox.glb"),
	"handle": preload("res://models/surgery/handle.glb"),
	"pistons": preload("res://models/surgery/pistons.glb"),
	"gear": preload("res://models/surgery/gear.glb"),
	"flywheel": preload("res://models/surgery/flywheel.glb"),
	"bar": preload("res://models/surgery/bar.glb"),
	"column": preload("res://models/surgery/column.glb"),
	"clampmount": preload("res://models/surgery/clampmount.glb"),
	"clampjaw": preload("res://models/surgery/clampjaw.glb"),
	"cable": preload("res://models/surgery/cable.glb"),
	"chain": preload("res://models/surgery/chain.glb"),
	"prosthetic": preload("res://models/surgery/prosthetic.glb"),
	"grate": preload("res://models/surgery/grate.glb"),
	"hearthjamb": preload("res://models/surgery/hearthjamb.glb"),
	"mantel": preload("res://models/surgery/mantel.glb"),
}
const CHART := preload("res://textures/surgery_chart.png")
const PLANKS := preload("res://textures/surgery_planks.png")
const FLAME := preload("res://textures/surgery_flame.png")
## How much each kit piece glows with its own picture (surgical_table.gd `glow`).
const GLOWS := {"shelf": 0.35, "jar": 1.1, "worktable": 0.3, "chandelier": 1.4, "candelabra": 1.2,
	"labbench": 0.6, "galvanic": 0.5, "still": 0.5, "desk": 0.4, "books": 0.2, "railring": 0.6,
	"grate": 1.4, "brazier": 0.9, "column": 0.0, "bookcase": 0.15}

## The walls: carved bays 5 m wide and BAY_DEPTH deep in front of the wall
## face, engaged pilasters (JAMB) between them every 6 m, all CEIL tall.
const BAY_DEPTH := 0.55
const JAMB_DEPTH := 0.8
## Over a way in: the lintel's underside, and the frieze above it.
const LINTEL_Y := 3.7
const FRIEZE_Y := 4.8
## The roof (note 96): a plank ceiling at CEIL on beams across the hall.
const CEIL := 8.6
const BEAM_Z: Array[float] = [-10.5, -6.0, -2.0, 2.0, 6.0, 10.5]
const BEAM := Vector2(0.55, 0.75)
const BEAM_LEN := 4.66
## The chandeliers hang from the beams to this height (their tops).
const CHANDELIER_TOP := 6.2
## Kept clear either side of the line from each way in to the table.
const LANE := 1.4
const CANDLE_COLOUR := Color(1.0, 0.68, 0.38)
const FIRE_COLOUR := Color(1.0, 0.55, 0.22)

var table: CharacterBody3D

## [system] -> {"node", "port", ...}: the mechanisms, built on the walls.
var _mech := {}
var _clamp := {}
var _clamp_state := &"shut"
var _levers: Array = []
var _jam_prompt: Interact.Prompt
var _jam_node: Node3D
var _bar: Node3D
var _bar_rest := Transform3D()
var _bar_jammed := Transform3D()
var _cables: Array = []
var _lamp: SpotLight3D
var _lamp_energy := 2.4
var _wall := 13.9
## The ways in: [point on the wall face, the way out], room frame.
var _doorways: Array = []
var _fires: Array = []
var _hanging: Array = []
var _cable_t := 0.0
var _spin := {"arms": 0.0, "legs": 0.0}


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
	_doorways = _find_doorways()

	_build_walls(h, cell)
	_build_roof()
	_hang_wall_torches(h, cell)
	_hang_chandeliers()

	# The wall slots, the doorways' left out.
	var slots := _wall_slots(h, cell)
	var take := func(prefs: Array) -> Dictionary:
		for want in prefs:
			for s in slots:
				if not s["used"] and s["wall"] == want[0] and s["k"] == want[1]:
					s["used"] = true
					return s
		for s in slots:
			if not s["used"]:
				s["used"] = true
				return s
		return {}
	# The clamp in the middle of a wall; the arms' mechanism, whose relay it
	# sits on, beside it.
	var clamp_slot: Dictionary = take.call([[&"left", 0], [&"right", 0], [&"back", 0], [&"front", 0]])
	var clamp_wall: StringName = clamp_slot.get("wall", &"left")
	var arms_slot: Dictionary = take.call([[clamp_wall, -1], [clamp_wall, 1], [&"back", -1]])
	var core_slot: Dictionary = take.call([[&"back", 0], [&"back", -1], [&"back", 1]])
	var opposite := {&"left": &"right", &"right": &"left", &"back": &"front", &"front": &"back"}
	var legs_slot: Dictionary = take.call([[opposite.get(clamp_wall, &"right"), 0], [opposite.get(clamp_wall, &"right"), 1],
		[opposite.get(clamp_wall, &"right"), -1]])
	var hearth_slot: Dictionary = take.call([[&"front", -1], [&"front", 1], [&"back", 1], [&"back", -1]])
	_build_arms_mechanism(arms_slot)
	_build_legs_mechanism(legs_slot)
	_build_core_mechanism(core_slot)
	_build_clamp(clamp_slot)
	_build_hearth(hearth_slot)
	_build_rail()
	_build_lamp()
	_build_levers()
	_zones(slots)

	_spawn_table(_wall - 0.4)
	_build_cables()
	_limit_view(_wall)
	print("[surgery] the surgical table asleep, its claw folded under the ring; levers %s; %d bodies laid out (%d broken)"
		% [", ".join(_levers.map(func(l): return String(l["system"]))), _corpse_count, _missing_count])


## Every wall slot of a ring cell that is not a corner and not a doorway:
## {"wall", "k" (-1..1 along it), "at" (on the wall face), "into" (the wall)}.
func _wall_slots(h: int, cell: float) -> Array:
	var walls := {&"back": Vector3.FORWARD, &"front": Vector3.BACK, &"left": Vector3.LEFT, &"right": Vector3.RIGHT}
	var out: Array = []
	for wall in walls:
		var into: Vector3 = walls[wall]
		var along := Vector3(-into.z, 0.0, into.x)
		for k in range(-h + 1, h):
			var at: Vector3 = into * _wall + along * float(k) * cell
			if _is_door(into, at):
				continue
			# `k` runs the same way for every wall: toward -X / -Z first, so
			# "left, -1" is the left wall's back half.
			var kk := k if along.x + along.z > 0.0 else -k
			out.append({"wall": wall, "k": kk, "at": at, "into": into, "used": false})
	return out


## A way in at the wall face point `at` on the wall `into` points at.
func _is_door(into: Vector3, at: Vector3) -> bool:
	for d in _doorways:
		if (d[1] as Vector3).dot(into) > 0.9 and (d[0] as Vector3).distance_to(at) < 1.0:
			return true
	return false


## A node on the face of the bay at slot `s`, its +Z out into the room.
func _on_wall(s: Dictionary, name_: String) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	add_child(n)
	n.transform = Transform3D(Basis.looking_at(s["into"], Vector3.UP), (s["at"] as Vector3) - (s["into"] as Vector3) * BAY_DEPTH)
	return n


func _solid(parent: Node3D, size: Vector3, at: Vector3, yaw := 0.0) -> void:
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


## A kit piece `name_` on `n` at `at`, turned `yaw`, glowing as GLOWS says,
## solid as a box of `size` (its footprint before the turn; none if zero).
func _kit(n: Node3D, name_: String, at: Vector3, yaw := 0.0, size := Vector3.ZERO, scale_ := Vector3.ONE) -> Node3D:
	var piece: Node3D = (K[name_] as PackedScene).instantiate()
	piece.name = name_.capitalize().replace(" ", "")
	n.add_child(piece)
	piece.position = at
	piece.rotation.y = yaw
	piece.scale = scale_
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


# --- The hall (notes 96, 98) ---------------------------------------------------------

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


## The walls: on every ring cell's outer side a carved gothic bay (or, over a
## way in, the skull lintel with the tracery frieze above it), engaged
## pilasters between the bays every 6 m, and one set diagonally in each corner
## that has no way in beside it. They stand in front of the brick, whose
## collision stops at the old crown; theirs takes the first 3 m.
func _build_walls(h: int, cell: float) -> void:
	var holder := Node3D.new()
	holder.name = "Walls"
	add_child(holder)
	var corner_doors := {}
	for d: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var along := Vector3(-d.z, 0.0, d.x)
		var face := Basis(Vector3.UP, atan2(-d.x, -d.z))
		for k in range(-h, h + 1):
			var cell_at: Vector3 = d * _wall + along * float(k) * cell
			var door := _is_door(d, cell_at)
			# The bay's span along the wall: between the pilasters, or for a
			# corner cell from its pilaster to the corner.
			var lo := float(k) * cell - cell * 0.5 + 0.5
			var hi := float(k) * cell + cell * 0.5 - 0.5
			if k == -h:
				lo = -_wall + (0.0 if door else 1.0)
			elif k == h:
				hi = _wall - (0.0 if door else 1.0)
			if door and absi(k) == h:
				corner_doors[(d + along * signf(float(k))).round()] = true
			var mid := (lo + hi) * 0.5
			var width := hi - lo
			var base := d * (_wall - BAY_DEPTH * 0.5) + along * mid
			var sx := Vector3(width / 5.0, 1.0, 1.0)
			if door:
				var lintel := _kit(holder, "lintel", base + Vector3(0.0, LINTEL_Y, 0.0), 0.0, Vector3.ZERO, sx)
				lintel.basis = face.scaled(sx)
				var frieze := _kit(holder, "frieze", base + Vector3(0.0, FRIEZE_Y, 0.0), 0.0, Vector3.ZERO, sx)
				frieze.basis = face.scaled(sx)
			else:
				var bay := _kit(holder, "wallbay", base, 0.0, Vector3.ZERO, sx)
				bay.basis = face.scaled(sx)
				_solid(holder, Vector3(width, 3.2, BAY_DEPTH), base + Vector3(0.0, 1.6, 0.0), atan2(-d.x, -d.z))
		# The pilasters between the bays.
		for k in range(-h, h):
			var a := (float(k) + 0.5) * cell
			var at := d * (_wall - JAMB_DEPTH * 0.5) + along * a
			var p := _kit(holder, "jamb", at)
			p.basis = face
			_solid(holder, Vector3(1.0, 3.2, JAMB_DEPTH), at + Vector3(0.0, 1.6, 0.0), atan2(-d.x, -d.z))
	# A pilaster across each corner, unless a way in opens beside it.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			if corner_doors.has(Vector3(sx, 0.0, sz)):
				continue
			var at := Vector3(sx, 0.0, sz) * (_wall - 0.55)
			var p := _kit(holder, "jamb", at)
			p.basis = Basis(Vector3.UP, atan2(sx, sz) + PI)
			_solid(holder, Vector3(1.2, 3.2, 1.2), at + Vector3(0.0, 1.6, 0.0), PI * 0.25)


## The roof: a plank ceiling (the generated plank texture, world-mapped) over
## the whole hall on oak beams in sections, each end on a grotesque stone
## corbel with an oak brace under it. One MultiMesh for the beams.
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
			# Every other section turned end for end: the straps do not repeat.
			xfs.append(Transform3D(Basis(Vector3.UP, PI * float(i % 2)), Vector3(x, CEIL - BEAM.y * 0.5, z)))
	_multi(beam, xfs, "Beams")
	var holder := Node3D.new()
	holder.name = "BeamEnds"
	add_child(holder)
	for z in BEAM_Z:
		for s: float in [-1.0, 1.0]:
			var x := s * (_wall - BAY_DEPTH)
			var c := _kit(holder, "corbel", Vector3(x - s * 0.43, CEIL - BEAM.y, z))
			c.rotation.y = -s * PI * 0.5
			var b := _kit(holder, "brace", Vector3(x - s * 0.84, CEIL - BEAM.y - 0.95, z))
			b.rotation.y = 0.0 if s < 0.0 else PI


## A torch on the face of every pilaster, none at a way in.
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
			var at := d * (_wall - JAMB_DEPTH - 0.02) + Vector3(-d.z, 0.0, d.x) * v
			if _door_distance(at) < 2.0:
				continue
			level._hang_torch(self, scene, at + Vector3(0.0, TORCH_HEIGHT, 0.0), d, energy, 13.0)


## Candle chandeliers on chains from the beams, their warm light under them.
## Plain lights without shadows: the hall's walls close them in, and Graphics
## scales their reach (light_detail).
func _hang_chandeliers() -> void:
	for at: Vector2 in [Vector2(-6.5, -6.0), Vector2(6.5, -6.0), Vector2(-6.5, 6.0), Vector2(6.5, 6.0)]:
		var c := Node3D.new()
		c.name = "Chandelier"
		add_child(c)
		c.position = Vector3(at.x, CHANDELIER_TOP, at.y)
		c.rotation.y = _rng.randf_range(-PI, PI)
		_kit(c, "chandelier", Vector3.ZERO)
		_chain(c, Vector3(0.0, CEIL - BEAM.y - CHANDELIER_TOP, 0.0), CEIL - BEAM.y - CHANDELIER_TOP)
		var light := OmniLight3D.new()
		light.name = "Candles"
		light.light_color = CANDLE_COLOUR
		light.light_energy = 3.0
		light.omni_range = 12.0
		# A gentle falloff: it has to reach the beams 3 m over it as well as the
		# floor 5 m under.
		light.omni_attenuation = 0.8
		light.light_specular = 0.2
		light.shadow_enabled = false
		light.position = Vector3(0.0, -1.35, 0.0)
		c.add_child(light)


## The great hearth in a wall slot: two carved jambs, the mantel and hood on
## them, an iron grate of burning logs between, its fire alive.
func _build_hearth(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "Hearth")
	for x: float in [-1.75, 1.75]:
		_kit(n, "hearthjamb", Vector3(x, 0.0, 0.3))
	_kit(n, "mantel", Vector3(0.0, 2.3, 0.85))
	_kit(n, "grate", Vector3(0.0, 0.0, 0.6))
	n.add_child(_flames(Vector3(0.0, 0.55, 0.6), Vector3(0.5, 0.05, 0.2), 26, 1.0))
	_solid(n, Vector3(4.2, 2.6, 1.3), Vector3(0.0, 1.3, 0.65))
	_add_fire(n, Vector3(0.0, 0.7, 0.9), 2.8, 9.5, 1.0)


## Flames: billboard licks of the generated flame, rising and shrinking, added
## light. Part of the fire's look, not an effect -- a few dozen quads.
func _flames(at: Vector3, extents: Vector3, amount: int, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Flames"
	p.amount = amount
	p.lifetime = 0.75
	p.direction = Vector3.UP
	p.spread = 8.0
	p.gravity = Vector3(0.0, 1.2, 0.0)
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.55) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Added: the picture's black ground adds nothing.
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = FLAME
	quad.material = m
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.6, 0.4, 0.0))
	p.color_ramp = ramp
	p.position = at
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A fire's light at `at` on `n`, flickering (`_work_fires`).
func _add_fire(n: Node3D, at: Vector3, energy: float, reach: float, _size: float) -> void:
	var light := OmniLight3D.new()
	light.name = "Fire"
	light.light_color = FIRE_COLOUR
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.3
	light.light_specular = 0.3
	light.shadow_enabled = false
	light.position = at + Vector3(0.0, 0.3, 0.0)
	n.add_child(light)
	_fires.append({"light": light, "energy": energy, "seed": _rng.randf() * 100.0})


## The fires flicker: two noises, slow and quick.
func _work_fires() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for f in _fires:
		var light: OmniLight3D = f["light"]
		var s: float = f["seed"]
		var k := 0.82 + 0.12 * sin(t * 2.3 + s) + 0.07 * sin(t * 7.9 + s * 1.7) + 0.05 * sin(t * 17.0 + s * 3.1)
		light.light_energy = float(f["energy"]) * k
	# The wrapped subjects sway on their hooks.
	for hanging in _hanging:
		var node: Node3D = hanging[0]
		var ph: float = hanging[1]
		node.rotation = Vector3(0.05 * sin(t * 0.7 + ph), node.rotation.y, 0.04 * sin(t * 0.9 + ph * 1.3))


# --- The machine's fittings ------------------------------------------------------------

## The arms' mechanism: the piston panel, its gear turning whenever the claw
## strikes.
func _build_arms_mechanism(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "ArmsMechanism")
	_kit(n, "pistons", Vector3(0.0, 0.0, 0.49))
	var gear := Node3D.new()
	gear.name = "Gear"
	gear.position = Vector3(0.0, 2.0, 1.1)
	n.add_child(gear)
	_kit(gear, "gear", Vector3.ZERO)
	_solid(n, Vector3(2.9, 3.0, 1.1), Vector3(0.0, 1.5, 0.55))
	_mech[&"arms"] = {"node": n, "port": n.transform * Vector3(0.0, 0.45, 1.0), "gear": gear}


## The hoist's (legs') mechanism: the great flywheel on the wall spinning as the
## claw travels, and the iron bar hanging beside it that can be driven through
## its spokes.
func _build_legs_mechanism(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "LegsMechanism")
	var wheel := Node3D.new()
	wheel.name = "Flywheel"
	wheel.position = Vector3(0.0, 1.65, 0.47)
	n.add_child(wheel)
	_kit(wheel, "flywheel", Vector3.ZERO)
	_bar = Node3D.new()
	_bar.name = "IronBar"
	n.add_child(_bar)
	_kit(_bar, "bar", Vector3.ZERO)
	_bar_rest = Transform3D(Basis(Vector3.BACK, 0.06), Vector3(1.55, 1.3, 0.25))
	_bar_jammed = Transform3D(Basis(Vector3.BACK, 0.9) * Basis(Vector3.RIGHT, 0.1), Vector3(0.35, 1.75, 0.95))
	_bar.transform = _bar_rest
	_jam_node = wheel
	_jam_prompt = Interact.prompt("E   Jam", Vector3.ZERO)
	wheel.add_child(_jam_prompt)
	_solid(n, Vector3(2.2, 2.8, 0.95), Vector3(0.0, 1.4, 0.47))
	_mech[&"legs"] = {"node": n, "port": n.transform * Vector3(0.6, 0.45, 0.6), "wheel": wheel}


## The core's mechanism: the caged glass column, its light beating with the
## core (its own glow materials, `_glow_own`).
func _build_core_mechanism(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "CoreMechanism")
	var column := _kit(n, "column", Vector3(0.0, 0.0, 0.7))
	var mats := _glow_own(column)
	var light := OmniLight3D.new()
	light.name = "ColumnLight"
	light.light_color = Table.CORE_COLOUR
	light.omni_range = 4.5
	light.omni_attenuation = 1.5
	light.light_specular = 0.2
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.6, 1.6)
	n.add_child(light)
	_solid(n, Vector3(1.4, 3.2, 1.4), Vector3(0.0, 1.6, 0.7))
	_mech[&"core"] = {"node": n, "port": n.transform * Vector3(0.0, 0.3, 1.0), "mats": mats, "light": light}


## A piece's own glow materials (its picture as its emission), not shared with
## any other copy: the column's light is driven by the core.
func _glow_own(piece: Node) -> Array:
	var out: Array = []
	for node in piece.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			m.emission_texture = src.albedo_texture
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mi.set_surface_override_material(i, m)
			out.append(m)
	return out


## The wall clamp: the iron mount and two toothed jaws on its hinges, shut
## until the arms' relay springs them open.
func _build_clamp(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "WallClamp")
	_kit(n, "clampmount", Vector3(0.0, 0.0, 0.5))
	var jaws: Array[Node3D] = []
	for up: float in [1.0, -1.0]:
		var jaw := Node3D.new()
		jaw.name = "Jaw"
		jaw.position = Vector3(0.0, 1.35 + up * 0.18, 0.95)
		n.add_child(jaw)
		# The upper jaw's teeth point down, the lower's up.
		var piece := _kit(jaw, "clampjaw", Vector3.ZERO)
		if up < 0.0:
			piece.rotation.z = PI
		jaws.append(jaw)
	_solid(n, Vector3(1.4, 2.7, 1.0), Vector3(0.0, 1.35, 0.5))
	_clamp = {"node": n, "jaws": jaws, "mouth": n.transform * CLAMP_MOUTH, "open": 0.0}


## The iron rail let into the floor round the table, its amber lamps lit.
func _build_rail() -> void:
	var rail := _kit(self, "railring", Vector3(0.0, 0.0, 0.0))
	for node in rail.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The surgical lamp: the light in the hub of the ceiling ring, a cold spot down
## onto the table. It is on the table's circuit.
func _build_lamp() -> void:
	var l := Node3D.new()
	l.name = "SurgicalLamp"
	l.position = Vector3(0.5, LAMP_HEIGHT, 0.0)
	add_child(l)
	_lamp = SpotLight3D.new()
	_lamp.name = "LampLight"
	_lamp.light_color = Color(0.8, 0.92, 1.0)
	_lamp.light_energy = _lamp_energy
	_lamp.spot_range = 8.0
	_lamp.spot_angle = 42.0
	_lamp.spot_attenuation = 1.0
	_lamp.light_specular = 0.4
	_lamp.shadow_enabled = false
	_lamp.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	l.add_child(_lamp)
	# And a dim warm fill under the roof: the beams and the ring above the lamp
	# would be black.
	var fill := OmniLight3D.new()
	fill.name = "RoofFill"
	fill.light_color = Color(1.0, 0.7, 0.45)
	fill.light_energy = 0.9
	fill.omni_range = 13.0
	fill.omni_attenuation = 0.7
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	fill.position = Vector3(-0.5, CEIL - BEAM.y - 1.4 - LAMP_HEIGHT, 0.0)
	l.add_child(fill)


## A lever on each post (the kit's lever box on its oak post), its handle up.
## Which system each cuts is shuffled.
func _build_levers() -> void:
	var order := SYSTEMS.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: StringName = order[i]
		order[i] = order[j]
		order[j] = t
	for i in LEVER_PIERS.size():
		var pier: Vector3 = LEVER_PIERS[i][0]
		var face: Vector3 = LEVER_PIERS[i][1]
		var n := Node3D.new()
		n.name = "Lever"
		add_child(n)
		n.transform = Transform3D(Basis.looking_at(-face, Vector3.UP), pier)
		_kit(n, "leverbox", Vector3.ZERO, 0.0, Vector3(0.7, 2.2, 0.8))
		var handle := Node3D.new()
		handle.name = "Handle"
		handle.position = Vector3(0.0, LEVER_HEIGHT, 0.45)
		n.add_child(handle)
		_kit(handle, "handle", Vector3.ZERO)
		handle.rotation.x = -0.35
		var prompt := Interact.prompt("E   Pull", Vector3(0.0, LEVER_HEIGHT, 0.45))
		n.add_child(prompt)
		_levers.append({"node": n, "handle": handle, "system": order[i], "prompt": prompt, "back_at": 0.0})


# --- The four corners (note 98) ----------------------------------------------------------

## Which corner is which: the shipping corner nearest a way in, the study
## furthest from them all, the lab and the trials the other two. Each corner
## dresses its own two wall slots and its floor.
func _zones(slots: Array) -> void:
	var corners: Array = [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]
	corners.sort_custom(func(a, b): return _door_distance(a * 11.0) < _door_distance(b * 11.0))
	var plan := {&"shipping": corners[0], &"study": corners[3]}
	# The other two by the seed.
	var mid: Array = [corners[1], corners[2]]
	if _rng.randf() < 0.5:
		mid.reverse()
	plan[&"lab"] = mid[0]
	plan[&"trials"] = mid[1]
	for zone in plan:
		var q: Vector3 = plan[zone]
		var walls: Array = []
		for s in slots:
			if s["used"]:
				continue
			# A slot is the corner's when it is on one of the corner's two walls
			# and on the corner's side of that wall's middle.
			var at: Vector3 = s["at"]
			var into: Vector3 = s["into"]
			var mine := false
			if absf(into.x) > 0.5:
				mine = signf(into.x) == q.x and absf(at.z) > 1.0 and signf(at.z) == q.z
			else:
				mine = signf(into.z) == q.z and absf(at.x) > 1.0 and signf(at.x) == q.x
			if mine:
				s["used"] = true
				walls.append(s)
		match zone:
			&"study":
				_study(q, walls)
			&"shipping":
				_shipping(q, walls)
			&"lab":
				_lab(q, walls)
			_:
				_trials(q, walls)
	# Any slot no corner took (a middle bay): an apothecary shelf pair.
	for s in slots:
		if not s["used"]:
			s["used"] = true
			var n := _on_wall(s, "Apothecary")
			for x: float in [-0.92, 0.92]:
				_kit(n, "shelf", Vector3(x, 0.0, 0.25), 0.0, Vector3(1.6, 3.0, 0.45))
	# Two braziers by the rail, on the open sides.
	for q: Vector3 in [plan[&"lab"], plan[&"trials"]]:
		var at := q * 3.5
		var n := Node3D.new()
		n.name = "Brazier"
		add_child(n)
		n.position = at
		_kit(n, "brazier", Vector3.ZERO, _rng.randf_range(-PI, PI), Vector3(0.9, 1.6, 0.9))
		n.add_child(_flames(Vector3(0.0, 1.5, 0.0), Vector3(0.2, 0.03, 0.2), 12, 0.6))
		_add_fire(n, Vector3(0.0, 1.45, 0.0), 1.6, 6.5, 0.5)


## A point in corner `q`'s frame: `a` out along X, `b` along Z, from the middle.
static func _q(q: Vector3, a: float, b: float) -> Vector3:
	return Vector3(q.x * a, 0.0, q.z * b)


## A yaw facing from `at` toward `to` (a kit piece's front is +Z).
static func _facing(at: Vector3, to: Vector3) -> float:
	return atan2(to.x - at.x, to.z - at.z)


## A free-standing piece, unless it would stand by a way in or in the lane
## from one to the table (`_in_lane`): the first build put the cage cart across
## the shipping corner's doorway and walled it off.
func _floor(name_: String, at: Vector3, yaw: float, size: Vector3) -> Node3D:
	if _door_distance(at) < 4.0 or _in_lane(at, maxf(size.x, size.z) * 0.5):
		print("[surgery] %s left out: it would stand in a way in" % name_)
		return null
	return _kit(self, name_, at, yaw, size)


## Whether something `reach` across, at `at`, comes within LANE of the line
## from any way in to the middle.
func _in_lane(at: Vector3, reach: float) -> bool:
	for d in _doorways:
		var a: Vector3 = d[0]
		var flat := Vector2(at.x, at.z)
		var from := Vector2(a.x, a.z)
		var t := clampf(flat.dot(from) / from.length_squared(), 0.0, 1.0)
		# The lane runs from the door (t 1) to the middle (t 0).
		if (flat - from * t).length() - reach < LANE:
			return true
	return false


## The study: bookcases along both walls of the corner, a rug with the writing
## desk on it, the lectern, the armillary sphere, piles of books, a candelabra.
func _study(q: Vector3, walls: Array) -> void:
	for s in walls:
		var n := _on_wall(s, "Bookcases")
		for x: float in [-1.35, 0.0, 1.35]:
			_kit(n, "bookcase", Vector3(x, 0.0, 0.25), 0.0, Vector3(1.26, 3.0, 0.49))
	# Two more in the corner's own bays, either wall.
	var c := _wall - BAY_DEPTH - 0.25
	_floor("bookcase", Vector3(q.x * c, 0.0, q.z * 11.2), atan2(-q.x, 0.0), Vector3(1.26, 3.0, 0.49))
	_floor("bookcase", Vector3(q.x * 11.2, 0.0, q.z * c), atan2(0.0, -q.z), Vector3(1.26, 3.0, 0.49))
	var centre := _q(q, 8.2, 8.2)
	_floor("rug", centre, PI * 0.25, Vector3.ZERO)
	_floor("desk", _q(q, 8.6, 8.6), _facing(_q(q, 8.6, 8.6), Vector3.ZERO), Vector3(2.0, 1.0, 1.6))
	_floor("lectern", _q(q, 5.8, 10.2), _facing(_q(q, 5.8, 10.2), Vector3.ZERO), Vector3(0.9, 1.4, 0.7))
	_floor("globe", _q(q, 10.4, 5.8), 0.3, Vector3(0.7, 1.9, 0.7))
	_floor("books", _q(q, 11.3, 9.0), _rng.randf_range(-PI, PI), Vector3(1.0, 0.6, 1.0))
	_floor("books", _q(q, 9.2, 11.4), _rng.randf_range(-PI, PI), Vector3(1.0, 0.6, 1.0))
	_floor("chest", _q(q, 6.6, 11.6), atan2(0.0, -q.z), Vector3(1.15, 0.62, 0.92))
	var cand := _floor("candelabra", _q(q, 6.4, 7.0), 0.0, Vector3(0.6, 2.0, 0.6))
	if cand != null:
		_candle_light(cand)


## The lab: laboratory benches of glassware against its walls with the anatomy
## chart over one, a bench as an island, the copper still in the corner,
## specimen jars, the worktable, a chest.
func _lab(q: Vector3, walls: Array) -> void:
	var first := true
	for s in walls:
		var n := _on_wall(s, "LabBench")
		_kit(n, "labbench", Vector3(0.0, 0.0, 0.75), 0.0, Vector3(3.0, 1.0, 1.5))
		for x: float in [-2.0, 2.0]:
			_kit(n, "jar", Vector3(x, 0.0, 0.45), _rng.randf_range(-PI, PI), Vector3(0.8, 2.1, 0.8))
		if first:
			first = false
			_chart(n, Vector3(0.0, 3.2, 0.03))
		var glow := OmniLight3D.new()
		glow.name = "SpecimenGlow"
		glow.light_color = Color(0.55, 1.0, 0.3)
		glow.light_energy = 0.8
		glow.omni_range = 4.0
		glow.omni_attenuation = 1.5
		glow.shadow_enabled = false
		glow.position = Vector3(0.0, 1.6, 1.4)
		n.add_child(glow)
	var corner := _q(q, 11.1, 11.1)
	_floor("still", corner, _facing(corner, Vector3.ZERO), Vector3(1.9, 3.0, 1.3))
	_floor("labbench", _q(q, 7.6, 7.6), PI * 0.25 * (q.x * q.z), Vector3(3.0, 1.0, 1.5))
	_floor("worktable", _q(q, 10.6, 6.2), PI * 0.5, Vector3(2.0, 0.95, 1.55))
	_floor("jar", _q(q, 6.2, 10.8), 0.4, Vector3(0.8, 2.1, 0.8))
	_floor("chest", _q(q, 8.4, 11.6), atan2(0.0, -q.z), Vector3(1.15, 0.62, 0.92))
	var cand := _floor("candelabra", _q(q, 5.6, 6.8), 0.0, Vector3(0.6, 2.0, 0.6))
	if cand != null:
		_candle_light(cand)


## The trials: the testing chair facing the table, the galvanic machine and an
## iron maiden on the walls with the tool rack, slabs with subjects fitted with
## their new arms, the rack and the pillory, gibbet cages from the beams, the
## older dead in the corner.
func _trials(q: Vector3, walls: Array) -> void:
	var i := 0
	for s in walls:
		var n := _on_wall(s, "Trials")
		if i == 0:
			_kit(n, "galvanic", Vector3(-1.2, 0.0, 0.5), 0.0, Vector3(1.6, 2.6, 0.95))
			_kit(n, "toolrack", Vector3(1.2, 1.1, 0.12), 0.0, Vector3(2.2, 1.5, 0.25))
		else:
			_kit(n, "maiden", Vector3(-1.0, 0.0, 0.5), _rng.randf_range(-0.2, 0.2), Vector3(1.2, 2.4, 0.9))
			_kit(n, "toolrack", Vector3(1.1, 1.1, 0.12), 0.0, Vector3(2.2, 1.5, 0.25))
		i += 1
	var chair := _q(q, 7.4, 7.4)
	_floor("testchair", chair, _facing(chair, Vector3.ZERO), Vector3(1.2, 2.4, 1.6))
	_subject_slab(_q(q, 5.6, 10.6), 0.0, 0)
	_subject_slab(_q(q, 10.6, 5.6), PI * 0.5, 1)
	_floor("rack", _q(q, 10.2, 9.6), PI * 0.25, Vector3(1.1, 1.2, 3.0))
	_floor("pillory", _q(q, 7.8, 11.6), atan2(0.0, -q.z), Vector3(2.0, 2.2, 1.1))
	if _door_distance(_q(q, 11.8, 11.8)) > 4.0:
		_corpse(_q(q, 11.9, 11.9), _rng.randf_range(-PI, PI), _missing(true))
	for at: Vector2 in [Vector2(9.0, 6.0), Vector2(5.5, 10.5)]:
		var g := Node3D.new()
		g.name = "Gibbet"
		add_child(g)
		var top := 5.6 + _rng.randf_range(-0.3, 0.3)
		var z := _nearest_beam(q.z * at.y)
		g.position = Vector3(q.x * at.x, top, z)
		g.rotation.y = _rng.randf_range(-PI, PI)
		_kit(g, "gibbet", Vector3.ZERO)
		_chain(g, Vector3(0.0, CEIL - BEAM.y - top, 0.0), CEIL - BEAM.y - top)


## The shipping corner: shipping caskets stood along its walls, the cage cart,
## pallets of crates, the hand cart, barrels, and the overhead monorail along
## its beam with the finished subjects hanging wrapped from its hooks.
func _shipping(q: Vector3, walls: Array) -> void:
	for s in walls:
		var n := _on_wall(s, "Caskets")
		for x: float in [-1.65, -0.55, 0.55, 1.65]:
			_kit(n, "casket", Vector3(x, 0.0, 0.35), _rng.randf_range(-0.08, 0.08), Vector3(0.93, 2.3, 0.61))
	_floor("cagecart", _q(q, 10.3, 4.6), PI * 0.5 * (1.0 if _rng.randf() < 0.5 else -1.0), Vector3(2.6, 2.1, 1.8))
	_floor("crates", _q(q, 11.2, 11.2), _facing(_q(q, 11.2, 11.2), Vector3.ZERO), Vector3(2.0, 1.7, 1.64))
	_floor("crates", _q(q, 10.8, 8.0), _rng.randf_range(-0.3, 0.3) + PI * 0.5, Vector3(2.0, 1.7, 1.64))
	_floor("handcart", _q(q, 4.6, 11.0), _rng.randf_range(-PI, PI), Vector3(1.8, 1.0, 1.07))
	_floor("barrels", _q(q, 7.0, 11.4), _rng.randf_range(-PI, PI), Vector3(1.9, 1.1, 2.0))
	# The monorail: along the beam over the corner, from the middle out to the
	# wall, its hooks hung with the wrapped subjects ready to go.
	var z := q.z * absf(BEAM_Z[1])
	var track := Node3D.new()
	track.name = "Monorail"
	add_child(track)
	for i in 3:
		var x := q.x * (2.4 + 4.0 * (float(i) + 0.5))
		_kit(track, "track", Vector3(x, CEIL - BEAM.y, z))
	for i in 5:
		var x := q.x * (3.4 + 2.2 * float(i))
		var hook := Node3D.new()
		hook.name = "Hook"
		track.add_child(hook)
		hook.position = Vector3(x, CEIL - BEAM.y - 0.55, z)
		hook.rotation.y = _rng.randf_range(-0.4, 0.4)
		_kit(hook, "hook", Vector3.ZERO)
		if i != 2:
			_kit(hook, "bundle", Vector3(0.0, -1.35, 0.0))
		_hanging.append([hook, _rng.randf() * TAU])


func _candle_light(n: Node3D) -> void:
	var light := OmniLight3D.new()
	light.light_color = CANDLE_COLOUR
	light.light_energy = 1.3
	light.omni_range = 5.5
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.position = Vector3(0.0, 2.1, 0.0)
	n.add_child(light)


## The anatomy chart (a generated picture) pinned to a bay.
func _chart(n: Node3D, at: Vector3) -> void:
	var chart := MeshInstance3D.new()
	chart.name = "AnatomyChart"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.35, 1.8)
	chart.mesh = quad
	var m := StandardMaterial3D.new()
	m.albedo_texture = CHART
	m.albedo_color = Color(0.62, 0.58, 0.52)
	m.roughness = 0.95
	chart.material_override = m
	chart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chart.position = at
	chart.rotation.z = _rng.randf_range(-0.04, 0.04)
	n.add_child(chart)


## An iron operating slab with a subject strapped down on it: on its back, one
## arm gone and the kit's mechanical arm fitted in its place.
func _subject_slab(at: Vector3, yaw: float, kind: int) -> void:
	if _door_distance(at) < 4.0 or _in_lane(at, 1.15):
		return
	var n := Node3D.new()
	n.name = "OperatingSlab"
	add_child(n)
	n.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	_kit(n, "slab", Vector3.ZERO, 0.0, Vector3(1.05, 1.0, 2.3))
	var body := _corpse(Vector3.ZERO, 0.0, [])
	remove_child(body)
	n.add_child(body)
	var low := body.position.y
	body.transform = Transform3D(Basis(Vector3.UP, PI * float(kind % 2)) * body.transform.basis, Vector3(0.0, 1.0 + low, 0.0))
	var sk: Skeleton3D = null
	var found := body.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		sk = found[0] as Skeleton3D
	if sk == null:
		return
	var limb: StringName = [&"forearm.R", &"forearm.L"][kind % 2]
	var b := sk.find_bone(limb)
	if b < 0:
		return
	sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)
	var att := BoneAttachment3D.new()
	att.bone_name = "upper_arm.R" if limb == &"forearm.R" else "upper_arm.L"
	sk.add_child(att)
	attach_prosthetic(att)


## The kit's mechanical arm on an upper-arm bone attachment, out along the bone
## from the elbow (the bone's +Y), its socket at the elbow. Shared with the
## table's prisoner (surgical_table.gd).
static func attach_prosthetic(att: Node3D) -> void:
	var arm: Node3D = (K["prosthetic"] as PackedScene).instantiate()
	att.add_child(arm)
	# The model hangs from its top (its socket) down -Y: turned to run up +Y,
	# from the elbow.
	arm.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.0, 0.27, 0.0))
	arm.scale = Vector3.ONE * 1.2


func _nearest_beam(z: float) -> float:
	var best: float = BEAM_Z[0]
	for b in BEAM_Z:
		if absf(b - z) < absf(best - z):
			best = b
	return best


# --- The table ------------------------------------------------------------------

## The table in the middle of the hall, lying across it: whoever walks in sees
## it side on, and the claw over it turn to them.
func _spawn_table(inner: float) -> void:
	table = CharacterBody3D.new()
	table.set_script(Table)
	table.name = "SurgicalTable"
	table.set("room", self)
	table.set("home", global_transform * Vector3.ZERO)
	table.set("home_yaw", global_rotation.y + PI * 0.5)
	table.set("bound", inner - 0.5)
	add_child(table)
	table.connect("system_changed", _on_system_changed)
	table.connect("depowered", _on_depowered)


func _on_system_changed(system: StringName, on: bool) -> void:
	# The clamp sits on the arms' relay: cut them and its jaws spring open,
	# and stay open (latched) until something is caught in them.
	if system == &"arms" and not on and _clamp_state == &"shut" and not _clamp.is_empty():
		_clamp_state = &"open"
		var mouth: Vector3 = to_global(_clamp["mouth"])
		table.call("_sparks", mouth, Color(1.0, 0.8, 0.5), 14)


func _on_depowered(_cause: StringName) -> void:
	if _clamp_state == &"held":
		_clamp_state = &"shut"


# --- The clamp ------------------------------------------------------------------------

## The claw slammed down at `at` (world, on the floor): caught if the clamp is
## open and it came down by its jaws -- they snap shut on its wrist (note 96).
func clamp_try_catch_at(at: Vector3) -> bool:
	if _clamp.is_empty() or _clamp_state != &"open":
		return false
	var mouth := to_global(_clamp["mouth"])
	if Vector2(mouth.x - at.x, mouth.z - at.z).length() > CATCH:
		return false
	_clamp_state = &"held"
	table.call("_sparks", mouth, Color(1.0, 0.8, 0.5), 30)
	for p in Coop.all():
		if p.get("_shake") != null and (p as Node3D).global_position.distance_to(mouth) < 14.0:
			p.set("_shake", maxf(float(p.get("_shake")), 0.35))
	return true


func clamp_hold_point() -> Vector3:
	return to_global(_clamp["mouth"])


## It let go: `torn` when the table tore free (the jaws slam shut, sparking).
func clamp_release(torn: bool) -> void:
	if _clamp.is_empty():
		return
	_clamp_state = &"shut"
	if torn:
		table.call("_sparks", to_global(_clamp["mouth"]), Color(1.0, 0.75, 0.45), 40)


func clamp_state() -> StringName:
	return _clamp_state


# --- The cables -------------------------------------------------------------------------

func _build_cables() -> void:
	# The kit's cable section (1 m along Y), its picture as the sheath under
	# the glow shader.
	var mesh := _mesh_of("cable")
	var mat := ShaderMaterial.new()
	mat.shader = CABLE_SHADER
	var src := mesh.surface_get_material(0) as StandardMaterial3D
	if src != null and src.albedo_texture != null:
		mat.set_shader_parameter("sheath_tex", src.albedo_texture)
	for i in SYSTEMS.size():
		var system := SYSTEMS[i]
		if not _mech.has(system):
			_cables.append({})
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = CABLE_SECTIONS
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cable_%s" % system
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# At the room's origin, NOT the world's: a visibility range is measured
		# from the node (section 6.09).
		add_child(mmi)
		_cables.append({"system": system, "mm": mm, "node": mmi, "path": PackedVector3Array(), "next": 0.0,
			"port": to_global(_mech[system]["port"])})
	_update_cables(0.0)


## Each cable: from the table's plug along the floor -- round the piers, by the
## level's navmesh -- to its mechanism's port, re-routed every CABLE_REPATH as
## the table moves. The arms' twitches as they move, the legs' shivers as it
## walks, the core's carries its beat out to the wall; while the core stalls
## the other two flare, feeding it back.
func _update_cables(delta: float) -> void:
	if table == null:
		return
	_cable_t += delta
	var now := _cable_t
	var floor_y := global_position.y
	var nav := get_world_3d().navigation_map
	for i in _cables.size():
		var c: Dictionary = _cables[i]
		if c.is_empty():
			continue
		var plug: Vector3 = table.call("plug_point", i)
		var port: Vector3 = c["port"]
		if now >= float(c["next"]) or (c["path"] as PackedVector3Array).is_empty():
			c["next"] = now + CABLE_REPATH
			var a := Vector3(plug.x, floor_y, plug.z)
			var b := Vector3(port.x, floor_y, port.z) + (to_global(Vector3.ZERO) - Vector3(port.x, floor_y, port.z)).normalized() * 0.4
			var path := PackedVector3Array()
			if NavigationServer3D.map_get_iteration_id(nav) > 0:
				path = NavigationServer3D.map_get_path(nav, a, b, true)
			if path.size() < 2:
				path = PackedVector3Array([a, b])
			c["path"] = path
		var route := PackedVector3Array([plug])
		var path: PackedVector3Array = c["path"]
		# Skip the start of the routed path that the table has since walked past.
		var start := 1
		while start < path.size() - 1 and Vector2(path[start].x - plug.x, path[start].z - plug.z).length() < 0.6:
			start += 1
		for k in range(start, path.size()):
			route.append(path[k])
		route.append(port)
		var pts := _resample(route, CABLE_SECTIONS + 1)
		var total := 0.0
		for k in range(1, pts.size()):
			total += pts[k].distance_to(pts[k - 1])
		# Off the floor at the plug, down onto it, up the wall into the port.
		var run := 0.0
		for k in pts.size():
			if k > 0:
				run += pts[k].distance_to(pts[k - 1])
			var from_plug := run
			var to_port := total - run
			var p := pts[k]
			var y := floor_y + CABLE_RADIUS
			y = lerpf(plug.y, y, smoothstep(0.0, 1.1, from_plug))
			y = lerpf(port.y, y, smoothstep(0.0, 0.7, to_port))
			pts[k] = Vector3(p.x, y, p.z)
		_animate_cable(c, pts, i, now)


func _animate_cable(c: Dictionary, pts: PackedVector3Array, i: int, now: float) -> void:
	var arm_motion: float = table.get("arm_motion")
	var leg_motion: float = table.get("leg_motion")
	var glow: float = table.get("core_glow")
	var feed: float = table.get("feed_arms") if i == 0 else (table.get("feed_legs") if i == 1 else 0.0)
	var n := pts.size()
	var moved := PackedVector3Array(pts)
	for k in range(1, n - 1):
		var env := sin(PI * float(k) / float(n - 1))
		var dir := (pts[k + 1] - pts[k - 1])
		dir.y = 0.0
		var side := Vector3(-dir.z, 0.0, dir.x).normalized() if dir.length_squared() > 0.0001 else Vector3.RIGHT
		var off := Vector3.ZERO
		match i:
			0:
				# Twitching: jerks running along it whenever the arms move.
				var jerk := sin(now * 13.0 - float(k) * 0.7) * sin(now * 3.1 + float(k) * 0.2)
				off = side * 0.16 * arm_motion * jerk * env + Vector3.UP * 0.05 * arm_motion * absf(jerk) * env
			1:
				# A fast shiver as it walks.
				off = (side * sin(now * 61.0 + float(k) * 2.3) + Vector3.UP * sin(now * 47.0 + float(k) * 1.7)) * 0.03 * leg_motion * env
		moved[k] = pts[k] + off
	var mm: MultiMesh = c["mm"]
	var to_room := global_transform.affine_inverse()
	for k in CABLE_SECTIONS:
		var a := moved[k]
		var b := moved[k + 1]
		var len_ := maxf(a.distance_to(b), 0.01)
		var y := (b - a) / len_
		var ref := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
		var x := ref.cross(y).normalized()
		var z := x.cross(y).normalized()
		mm.set_instance_transform(k, to_room * Transform3D(Basis(x, y * (len_ * 1.08), z), (a + b) * 0.5))
		var t := float(k) / float(CABLE_SECTIONS - 1)
		var g := 0.0
		var col := Table.CORE_COLOUR
		match i:
			2:
				# The core's beat running out from the table to the wall.
				var wave := pow(maxf(sin((t * 3.0 - now * 1.6) * TAU * 0.5), 0.0), 8.0)
				g = glow * (0.06 + 0.5 * wave)
			_:
				# Feeding back: warm light running in from the wall.
				var wave := pow(maxf(sin(((1.0 - t) * 2.0 - now * 3.0) * TAU * 0.5), 0.0), 4.0)
				g = feed * (0.3 + 0.9 * wave)
				col = Table.FEED_COLOUR
		mm.set_instance_custom_data(k, Color(g, col.r, col.g, col.b))


## `n` points evenly along the polyline `line`.
static func _resample(line: PackedVector3Array, n: int) -> PackedVector3Array:
	var lengths: Array[float] = [0.0]
	for i in range(1, line.size()):
		lengths.append(lengths[i - 1] + line[i].distance_to(line[i - 1]))
	var total: float = lengths[lengths.size() - 1]
	var out := PackedVector3Array()
	var seg := 0
	for k in n:
		var d := total * float(k) / float(n - 1)
		while seg < line.size() - 2 and lengths[seg + 1] < d:
			seg += 1
		var span := maxf(lengths[seg + 1] - lengths[seg], 0.0001)
		out.append(line[seg].lerp(line[seg + 1], clampf((d - lengths[seg]) / span, 0.0, 1.0)))
	return out


# --- Each frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if table == null:
		return
	_update_cables(delta)
	_work_mechanisms(delta)
	_work_levers()
	_work_fires()


func _work_mechanisms(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var glow: float = table.get("core_glow")
	var down: bool = table.call("is_depowered")
	if _mech.has(&"arms"):
		var m: Dictionary = _mech[&"arms"]
		var arm: float = table.get("arm_motion")
		_spin["arms"] = float(_spin["arms"]) + delta * arm * 4.0
		(m["gear"] as Node3D).rotation.z = float(_spin["arms"])
	if _mech.has(&"legs"):
		var m: Dictionary = _mech[&"legs"]
		var legs_on: bool = table.call("legs_on")
		var leg: float = table.get("leg_motion")
		var jammed: bool = table.get("legs_jammed")
		var target := 0.0 if not legs_on or jammed or down else (0.5 + 5.0 * leg) * glow
		var speed: float = m.get("speed", 0.0)
		speed = lerpf(speed, target, clampf(delta * (1.6 if target < speed else 3.0), 0.0, 1.0))
		m["speed"] = speed
		_spin["legs"] = float(_spin["legs"]) + delta * speed
		(m["wheel"] as Node3D).rotation.z = -float(_spin["legs"])
	if _mech.has(&"core"):
		var m: Dictionary = _mech[&"core"]
		var feed: float = maxf(table.get("feed_arms"), table.get("feed_legs"))
		for mat in m["mats"]:
			var rod: StandardMaterial3D = mat
			rod.emission = Table.CORE_COLOUR.lerp(Table.FEED_COLOUR, clampf(feed, 0.0, 1.0))
			rod.emission_energy_multiplier = 0.15 + 1.6 * glow + 1.2 * feed
		var light: OmniLight3D = m["light"]
		light.light_energy = 0.9 * glow + 0.6 * feed
		light.visible = light.light_energy > 0.02
	# The clamp's jaws: shut, sprung wide, or shut on the shackle and shaking.
	if not _clamp.is_empty():
		var open := 0.75 if _clamp_state == &"open" else (0.14 if _clamp_state == &"held" else 0.0)
		_clamp["open"] = lerpf(float(_clamp["open"]), open, clampf(delta * (18.0 if open < float(_clamp["open"]) else 5.0), 0.0, 1.0))
		var jaws: Array = _clamp["jaws"]
		var shake := 0.0
		if _clamp_state == &"held":
			shake = 0.04 * float(table.call("strain")) * sin(now * 70.0)
		(jaws[0] as Node3D).rotation.x = -float(_clamp["open"]) + shake
		(jaws[1] as Node3D).rotation.x = float(_clamp["open"]) - shake
	# The lamp is on the table's circuit: it gutters as the table stalls and dies
	# with it.
	if _lamp != null:
		var e := _lamp_energy * clampf(0.15 + glow * 0.95, 0.0, 1.1)
		if table.get("state") == Table.State.DORMANT:
			e = _lamp_energy * (0.55 + 0.1 * sin(now * 1.3) + (0.25 if fmod(now, 7.3) < 0.08 else 0.0))
		if down:
			e = 0.0 if float(table.get("core_glow")) < 0.05 else e
		_lamp.light_energy = e
		_lamp.visible = e > 0.02


## Levers and the jam: who is at one, and what pulling it does.
func _work_levers() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var down: bool = table.call("is_depowered")
	for l in _levers:
		var prompt: Interact.Prompt = l["prompt"]
		var handle: Node3D = l["handle"]
		var resting := now >= float(l["back_at"])
		var want := -0.35 if resting else 2.4
		handle.rotation.x = lerp_angle(handle.rotation.x, want, 0.25 if resting else 0.5)
		var p: Node = null
		if resting and not down:
			p = Interact.chooser(l["node"], LEVER_REACH, 1.6, 3.2, 0.12, [handle])
		prompt.visible = p != null
		prompt.player = p
	if _jam_prompt != null:
		var stopped: bool = not bool(table.call("legs_on")) and not bool(table.get("legs_jammed")) and not down
		var p: Node = Interact.chooser(_jam_node, 2.8, 2.0, 3.6, 0.2) if stopped else null
		_jam_prompt.visible = p != null
		_jam_prompt.player = p


func _unhandled_input(event: InputEvent) -> void:
	for l in _levers:
		var prompt: Interact.Prompt = l["prompt"]
		if prompt.visible and Interact.pressed(event, prompt.player):
			get_viewport().set_input_as_handled()
			_pull(l)
			return
	if _jam_prompt != null and _jam_prompt.visible and Interact.pressed(event, _jam_prompt.player):
		get_viewport().set_input_as_handled()
		_jam()


func _pull(l: Dictionary) -> void:
	var level: int = table.get("level")
	l["back_at"] = Time.get_ticks_msec() / 1000.0 + float(Table.CUT_TIME[level]) + 0.6
	(l["prompt"] as Interact.Prompt).visible = false
	table.call("_sparks", (l["handle"] as Node3D).global_position, Color(1.0, 0.8, 0.5), 8)
	table.call("cut", l["system"])


## The bar off its hook and through the stopped flywheel's spokes: the legs
## never turn again.
func _jam() -> void:
	_jam_prompt.visible = false
	var tw := _bar.create_tween()
	tw.tween_property(_bar, "transform", _bar_jammed, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	table.call("_sparks", _jam_node.global_position, Color(1.0, 0.8, 0.5), 20)
	table.call("jam_legs")


# --- Saving and resetting ----------------------------------------------------------------

func save_state() -> Dictionary:
	if table == null or not bool(table.call("is_depowered")):
		return {"down": false}
	# Where the claw fell, and the aisle its arm lay in (note 95).
	var p: Vector3 = table.call("rest_point")
	return {"down": true, "at": [p.x, p.y, p.z], "yaw": float(table.call("rest_yaw")),
		"jammed": bool(table.get("legs_jammed"))}


func restore_state(data: Dictionary) -> void:
	if table == null or not bool(data.get("down", false)):
		return
	var at: Array = data.get("at", [])
	var p := table.global_position if at.size() < 3 else Vector3(float(at[0]), float(at[1]), float(at[2]))
	table.call("set_dead_now", p, float(data.get("yaw", 0.0)))
	if bool(data.get("jammed", false)) and _bar != null:
		_bar.transform = _bar_jammed
	_clamp_state = &"shut"


## Everyone died: with the table still running, all of it back as it was.
func on_world_reset() -> void:
	if table == null or bool(table.call("is_depowered")):
		return
	table.call("reset_to_sleep")
	_clamp_state = &"shut"
	for l in _levers:
		l["back_at"] = 0.0
	if _bar != null:
		_bar.transform = _bar_rest


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
