extends "res://scripts/morgue.gd"

## The surgery (2026-10-21; refurnished after the user's reference picture,
## note 95): the hall where the dead prisoners were to be made bionic. An
## enclosed vaulted hall like the morgue's (module_level `_make_surgery_hall`;
## this extends morgue.gd for its piers, torches and bodies), round the machine
## that did the work: the surgical table (scripts/surgical_table.gd), fixed in
## the middle of the hall inside an iron floor rail, its long claw folded up
## into the ring in the vault over it until a player walks in.
##
## Dressed from the reference with the Higgsfield kit (models/surgery/,
## tools/build_surgery_kit.py): apothecary shelves of bottles and candles,
## glowing specimen jars, a worktable with a skull and an open book under an
## anatomy chart, iron-bound chests, candle chandeliers in the bays.
##
## What is in here to beat it with -- nothing marked, all of it to be watched:
## - THREE WALL MECHANISMS, one per system, each joined to the table by its own
##   thick cable across the floor: the ARMS' pistons and gear (their cable
##   twitches whenever the claw strikes), the HOIST's flywheel (the "legs"
##   system; its cable shivers as the claw travels), the CORE's glass column
##   (its cable carries the core's pulse).
## - THREE LEVERS on the piers, which system each cuts shuffled per seed. A
##   pull cuts it for a while (surgical_table.gd `cut`) and shows something:
##   cutting the arms springs the wall CLAMP open (it sits on the arms' relay);
##   cutting the hoist drops the claw and stops the flywheel, which can then be
##   JAMMED with the iron bar hanging beside it; cutting the core stalls the
##   table until the other two cables flare and feed it back.
## - THE CLAMP, at the end of an aisle so the claw can be lured straight down
##   it: once open, the claw driven into its jaws is caught, the power cable at
##   its wrist in reach -- until the hoist tears it free.
## - Cover: the piers (the claw cannot reach round them), the slabs the last
##   prisoners lie strapped to, a broken table on its side, a toppled rack of
##   prosthetic limbs, the furniture.
## Depowered the claw crashes to the floor, its light goes out, the lamp in the
## ring dies with it and its hum -- the only machine sound in the dungeon --
## stops.

const Table := preload("res://scripts/surgical_table.gd")
const CABLE_SHADER := preload("res://shaders/surgery_cable.gdshader")
const SkeletonSword := preload("res://scripts/skeleton_sword.gd")
const ModuleMaze := preload("res://scripts/module_maze.gd")

## The systems, in the order of the table's plugs.
const SYSTEMS: Array[StringName] = [&"arms", &"legs", &"core"]
## Sections in each cable, and their radius.
const CABLE_SECTIONS := 30
const CABLE_RADIUS := 0.075
const CABLE_REPATH := 0.25
## The clamp catches the shackle this close to the middle of its jaws.
const CATCH := 1.15
## Its jaws' mouth, from the wall face.
const CLAMP_MOUTH := Vector3(0.0, 1.35, 0.95)
## The levers: on the face of these inner piers (room frame), at this height.
const LEVER_PIERS := [[Vector3(-9.0, 0.0, 3.0), Vector3.RIGHT], [Vector3(9.0, 0.0, -3.0), Vector3.LEFT],
	[Vector3(3.0, 0.0, -9.0), Vector3.BACK]]
const LEVER_HEIGHT := 1.25
const LEVER_REACH := 2.4
## The lamp: in the hub of the ceiling ring.
const LAMP_HEIGHT := 4.05
## The Higgsfield kit (note 95).
const SHELF := preload("res://models/surgery/shelf.glb")
const JAR := preload("res://models/surgery/jar.glb")
const WORKTABLE := preload("res://models/surgery/worktable.glb")
const CHEST := preload("res://models/surgery/chest.glb")
const CHANDELIER := preload("res://models/surgery/chandelier.glb")
const CHART := preload("res://textures/surgery_chart.png")
## The chandeliers: in the four corner bays, hanging from the crown (5.1 m).
const CHANDELIER_TOP := 5.0
const CANDLE_COLOUR := Color(1.0, 0.68, 0.38)
## The iron rail let into the floor round the table.
const RAIL_RADIUS := 2.05

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
var _cables: Array = []
var _lamp: SpotLight3D
var _lamp_mat: StandardMaterial3D
var _lamp_energy := 2.4
var _wall := 13.9
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
	var pilaster_in := _wall - PILASTER_PROUD

	_build_piers(h, cell, pilaster_in)
	_hang_wall_torches(h, cell, pilaster_in)
	_hang_chandeliers()

	# The wall slots between the pilasters, the doorways' left out.
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
	# The clamp at the end of an aisle (k 0: on a line through the middle,
	# clear of the piers), so the claw can be lured straight down it into the
	# jaws; the arms' mechanism, whose relay it sits on, beside it.
	var clamp_slot: Dictionary = take.call([[&"left", 0], [&"right", 0], [&"back", 0], [&"front", 0]])
	var clamp_wall: StringName = clamp_slot.get("wall", &"left")
	var arms_slot: Dictionary = take.call([[clamp_wall, -1], [clamp_wall, 1], [&"back", -1]])
	var core_slot: Dictionary = take.call([[&"back", 0], [&"back", -1], [&"back", 1]])
	var opposite := {&"left": &"right", &"right": &"left", &"back": &"front", &"front": &"back"}
	var legs_slot: Dictionary = take.call([[opposite.get(clamp_wall, &"right"), 0], [opposite.get(clamp_wall, &"right"), 1],
		[opposite.get(clamp_wall, &"right"), -1]])
	_build_arms_mechanism(arms_slot)
	_build_legs_mechanism(legs_slot)
	_build_core_mechanism(core_slot)
	_build_clamp(clamp_slot)
	_build_rail()
	_build_lamp()
	_build_levers()
	_build_story(h, cell)
	_furnish(slots)

	_spawn_table(pilaster_in)
	_build_cables()
	_limit_view(_wall)
	print("[surgery] the surgical table asleep, its claw folded in the vault; levers %s; %d bodies laid out (%d broken)"
		% [", ".join(_levers.map(func(l): return String(l["system"]))), _corpse_count, _missing_count])


## Every wall slot of a ring cell that is not a corner and not a doorway:
## {"wall", "k" (-1..1 along it), "at" (on the wall face), "into" (the wall)}.
func _wall_slots(h: int, cell: float) -> Array:
	var ways: Array = []
	for way in room["entrances"]:
		var local := to_local(built.to_world(way["cell"]))
		var step: Vector2i = ModuleMaze.DIRS[way["side"]]
		var dir := global_basis.inverse() * Vector3(float(step.x), 0.0, float(step.y))
		ways.append([Vector3(local.x, 0.0, local.z), dir])
	var walls := {&"back": Vector3.FORWARD, &"front": Vector3.BACK, &"left": Vector3.LEFT, &"right": Vector3.RIGHT}
	var out: Array = []
	for wall in walls:
		var into: Vector3 = walls[wall]
		var along := Vector3(-into.z, 0.0, into.x)
		for k in range(-h + 1, h):
			var ring := into * float(h) * cell + along * float(k) * cell
			var blocked := false
			for w in ways:
				if (w[0] as Vector3).distance_to(ring) < 1.0 and (w[1] as Vector3).dot(into) > 0.9:
					blocked = true
			if blocked:
				continue
			# `k` runs the same way for every wall: toward -X / -Z first, so
			# "left, -1" is the left wall's back half.
			var kk := k if along.x + along.z > 0.0 else -k
			out.append({"wall": wall, "k": kk, "at": into * _wall + along * float(k) * cell,
				"into": into, "used": false})
	return out


## A node on the wall face at slot `s`, its +Z out into the room.
func _on_wall(s: Dictionary, name_: String) -> Node3D:
	var n := Node3D.new()
	n.name = name_
	add_child(n)
	n.transform = Transform3D(Basis.looking_at(s["into"], Vector3.UP), s["at"])
	return n


func _solid(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	parent.add_child(body)
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## The arms' mechanism: two pistons pumping in their cylinders and a gear
## between them, turning whenever the arms move.
func _build_arms_mechanism(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "ArmsMechanism")
	n.add_child(Table._merge([
		[Table._boxm(Vector3(3.0, 2.9, 0.25)), Transform3D(Basis(), Vector3(0.0, 1.45, 0.12)), &"rust"],
		[Table._boxm(Vector3(0.22, 3.1, 0.34)), Transform3D(Basis(), Vector3(-1.42, 1.55, 0.2)), &"dark"],
		[Table._boxm(Vector3(0.22, 3.1, 0.34)), Transform3D(Basis(), Vector3(1.42, 1.55, 0.2)), &"dark"],
		[Table._boxm(Vector3(3.0, 0.2, 0.4)), Transform3D(Basis(), Vector3(0.0, 2.95, 0.22)), &"dark"],
		[Table._cylm(0.17, 0.17, 1.2, 12), Transform3D(Basis(), Vector3(-0.75, 2.15, 0.45)), &"steel"],
		[Table._cylm(0.17, 0.17, 1.2, 12), Transform3D(Basis(), Vector3(0.75, 2.15, 0.45)), &"steel"],
		[Table._cylm(0.2, 0.2, 0.08, 12), Transform3D(Basis(), Vector3(-0.75, 1.55, 0.45)), &"brass"],
		[Table._cylm(0.2, 0.2, 0.08, 12), Transform3D(Basis(), Vector3(0.75, 1.55, 0.45)), &"brass"],
		[Table._cylm(0.1, 0.1, 0.3, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.45, 0.4)), &"brass"],
	], "Frame"))
	var rods: Array[Node3D] = []
	for x: float in [-0.75, 0.75]:
		var rod := Node3D.new()
		rod.position = Vector3(x, 1.0, 0.45)
		n.add_child(rod)
		rod.add_child(Table._merge([[Table._cylm(0.07, 0.07, 1.1, 8), Transform3D(Basis(), Vector3(0.0, 0.0, 0.0)), &"steel"],
			[Table._boxm(Vector3(0.3, 0.1, 0.2)), Transform3D(Basis(), Vector3(0.0, -0.55, 0.0)), &"dark"]], "Rod"))
		rods.append(rod)
	var gear := _gear(0.55, 14)
	gear.position = Vector3(0.0, 1.05, 0.42)
	n.add_child(gear)
	_solid(n, Vector3(3.2, 3.0, 0.75), Vector3(0.0, 1.5, 0.35))
	_mech[&"arms"] = {"node": n, "port": n.transform * Vector3(0.0, 0.45, 0.6), "rods": rods, "gear": gear}


## The legs' mechanism: a great flywheel spinning with the crawl, and the iron
## bar hanging beside it that can be driven through its spokes.
func _build_legs_mechanism(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "LegsMechanism")
	n.add_child(Table._merge([
		[Table._boxm(Vector3(3.2, 3.2, 0.25)), Transform3D(Basis(), Vector3(0.0, 1.6, 0.12)), &"rust"],
		[Table._boxm(Vector3(0.3, 1.6, 0.5)), Transform3D(Basis(), Vector3(0.0, 0.8, 0.3)), &"dark"],
		[Table._cylm(0.14, 0.14, 0.7, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 1.65, 0.45)), &"steel"],
		[Table._cylm(0.1, 0.1, 0.3, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.6, 0.45, 0.4)), &"brass"],
		# The hook the bar hangs from.
		[Table._boxm(Vector3(0.08, 0.08, 0.35)), Transform3D(Basis(), Vector3(1.3, 2.25, 0.3)), &"dark"],
	], "Frame"))
	var wheel := Node3D.new()
	wheel.name = "Flywheel"
	wheel.position = Vector3(0.0, 1.65, 0.72)
	n.add_child(wheel)
	var wparts: Array = [[Table._torusm(0.92, 1.08), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), &"dark"],
		[Table._cylm(0.2, 0.2, 0.22, 12), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), &"brass"]]
	for i in 6:
		var a := TAU * float(i) / 6.0
		wparts.append([Table._boxm(Vector3(0.08, 0.95, 0.07)), Transform3D(Basis(Vector3.BACK, a), Vector3(-sin(a), cos(a), 0.0) * 0.5), &"rust"])
	wheel.add_child(Table._merge(wparts, "Wheel"))
	# The bar on its hook.
	_bar = Node3D.new()
	_bar.name = "IronBar"
	n.add_child(_bar)
	_bar.add_child(Table._merge([[Table._cylm(0.04, 0.04, 1.7, 8), Transform3D(), &"rust"],
		[Table._boxm(Vector3(0.1, 0.12, 0.06)), Transform3D(Basis(), Vector3(0.0, 0.8, 0.0)), &"dark"]], "Bar"))
	_bar_rest = Transform3D(Basis(Vector3.BACK, 0.06), Vector3(1.3, 1.35, 0.42))
	_bar.transform = _bar_rest
	_jam_node = wheel
	_jam_prompt = Interact.prompt("E   Jam", Vector3.ZERO)
	wheel.add_child(_jam_prompt)
	_solid(n, Vector3(3.4, 3.2, 0.6), Vector3(0.0, 1.6, 0.3))
	_mech[&"legs"] = {"node": n, "port": n.transform * Vector3(0.6, 0.45, 0.55), "wheel": wheel}


## The core's mechanism: a tall column of dark glass in an iron cage with a
## rod of light in it that beats with the core.
func _build_core_mechanism(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "CoreMechanism")
	var parts: Array = [
		[Table._boxm(Vector3(2.6, 3.5, 0.25)), Transform3D(Basis(), Vector3(0.0, 1.75, 0.12)), &"rust"],
		[Table._cylm(0.62, 0.62, 0.22, 16), Transform3D(Basis(), Vector3(0.0, 0.11, 0.65)), &"dark"],
		[Table._cylm(0.62, 0.62, 0.22, 16), Transform3D(Basis(), Vector3(0.0, 3.0, 0.65)), &"dark"],
		[Table._cylm(0.1, 0.1, 0.3, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.45, 0.25)), &"brass"],
	]
	for i in 6:
		var a := TAU * float(i) / 6.0
		parts.append([Table._cylm(0.035, 0.035, 2.8, 6), Transform3D(Basis(), Vector3(cos(a) * 0.55, 1.55, 0.65 + sin(a) * 0.55)), &"steel"])
	n.add_child(Table._merge(parts, "Frame"))
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = Table._cylm(0.46, 0.46, 2.6, 18)
	glass.material_override = _glass_mat()
	glass.position = Vector3(0.0, 1.55, 0.65)
	n.add_child(glass)
	var rod_mat: StandardMaterial3D = Table._mat(&"core").duplicate()
	var rod := MeshInstance3D.new()
	rod.name = "Rod"
	rod.mesh = Table._cylm(0.13, 0.13, 2.65, 10)
	rod.material_override = rod_mat
	rod.position = Vector3(0.0, 1.55, 0.65)
	n.add_child(rod)
	var light := OmniLight3D.new()
	light.name = "ColumnLight"
	light.light_color = Table.CORE_COLOUR
	light.omni_range = 4.5
	light.omni_attenuation = 1.5
	light.light_specular = 0.2
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.6, 1.4)
	n.add_child(light)
	_solid(n, Vector3(1.4, 3.2, 1.35), Vector3(0.0, 1.6, 0.65))
	_mech[&"core"] = {"node": n, "port": n.transform * Vector3(0.0, 0.45, 0.45), "rod": rod_mat, "light": light}


func _glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# Opaque, so it costs nothing to draw: dark glass with a sharp highlight, the
	# rod inside it seen at its ends.
	m.albedo_color = Color(0.03, 0.05, 0.055)
	m.metallic = 0.2
	m.roughness = 0.06
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.2
	return m


## A gear: a disc with teeth round it, turning about its local Z.
func _gear(r: float, teeth: int) -> Node3D:
	var g := Node3D.new()
	g.name = "Gear"
	var parts: Array = [[Table._cylm(r, r, 0.1, 18), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), &"brass"],
		[Table._cylm(r * 0.25, r * 0.25, 0.16, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), &"dark"]]
	for i in teeth:
		var a := TAU * float(i) / float(teeth)
		parts.append([Table._boxm(Vector3(0.09, 0.12, 0.1)), Transform3D(Basis(Vector3.BACK, a), Vector3(-sin(a), cos(a), 0.0) * (r + 0.04)), &"brass"])
	g.add_child(Table._merge(parts, "GearMesh"))
	return g


## The wall clamp: a heavy mount and two toothed jaws hinged at the back, shut
## until the arms' relay springs them open.
func _build_clamp(s: Dictionary) -> void:
	if s.is_empty():
		return
	var n := _on_wall(s, "WallClamp")
	n.add_child(Table._merge([
		[Table._boxm(Vector3(2.0, 2.7, 0.3)), Transform3D(Basis(), Vector3(0.0, 1.35, 0.15)), &"rust"],
		[Table._boxm(Vector3(0.3, 1.4, 0.5)), Transform3D(Basis(), Vector3(-0.8, 1.35, 0.45)), &"dark"],
		[Table._boxm(Vector3(0.3, 1.4, 0.5)), Transform3D(Basis(), Vector3(0.8, 1.35, 0.45)), &"dark"],
		[Table._cylm(0.09, 0.09, 1.9, 10), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, 1.35, 0.55)), &"steel"],
		# Its springs, either side.
		[Table._cylm(0.1, 0.1, 0.9, 10), Transform3D(Basis(), Vector3(-0.8, 2.4, 0.45)), &"steel"],
		[Table._cylm(0.1, 0.1, 0.9, 10), Transform3D(Basis(), Vector3(0.8, 2.4, 0.45)), &"steel"],
	], "Mount"))
	var jaws: Array[Node3D] = []
	for up: float in [1.0, -1.0]:
		var jaw := Node3D.new()
		jaw.position = Vector3(0.0, 1.35 + up * 0.06, 0.55)
		n.add_child(jaw)
		var parts: Array = [[Table._boxm(Vector3(1.3, 0.16, 0.75)), Transform3D(Basis(), Vector3(0.0, up * 0.08, 0.38)), &"dark"]]
		for t in 6:
			parts.append([Table._cylm(0.0, 0.05, 0.14, 4), Transform3D(Basis(Vector3.RIGHT, PI if up > 0.0 else 0.0),
				Vector3(-0.5 + float(t) * 0.2, -up * 0.06, 0.66)), &"steel"])
		jaw.add_child(Table._merge(parts, "Jaw"))
		jaws.append(jaw)
	_solid(n, Vector3(2.0, 2.7, 0.6), Vector3(0.0, 1.35, 0.3))
	_clamp = {"node": n, "jaws": jaws, "mouth": n.transform * CLAMP_MOUTH, "open": 0.0}


## The iron rail let into the floor round the table, as in the reference: a
## riveted ring with amber lamps set in it. Flush with the floor -- nothing to
## trip on.
func _build_rail() -> void:
	var parts: Array = [[Table._torusm(RAIL_RADIUS - 0.09, RAIL_RADIUS + 0.09), Transform3D(Basis().scaled(Vector3(1.0, 0.3, 1.0)), Vector3(0.0, 0.0, 0.0)), &"dark"],
		[Table._torusm(RAIL_RADIUS - 0.03, RAIL_RADIUS + 0.03), Transform3D(Basis().scaled(Vector3(1.0, 0.4, 1.0)), Vector3(0.0, 0.025, 0.0)), &"brass"]]
	for i in 12:
		var a := TAU * float(i) / 12.0
		var at := Vector3(cos(a), 0.0, sin(a))
		if i % 3 == 0:
			parts.append([Table._boxm(Vector3(0.22, 0.05, 0.32)), Transform3D(Basis(Vector3.UP, -a), at * RAIL_RADIUS + Vector3(0.0, 0.02, 0.0)), &"rust"])
		else:
			parts.append([Table._cylm(0.045, 0.055, 0.04, 8), Transform3D(Basis(), at * RAIL_RADIUS + Vector3(0.0, 0.035, 0.0)), &"amber"])
	var rail := Table._merge(parts, "FloorRail")
	rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rail)


## The surgical lamp: the light in the hub of the ceiling ring, a cold spot down
## onto the table. It is on the table's circuit.
func _build_lamp() -> void:
	var l := Node3D.new()
	l.name = "SurgicalLamp"
	# Beside the arm, which hangs from the middle of the hub.
	l.position = Vector3(0.5, LAMP_HEIGHT, 0.0)
	add_child(l)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.2, 0.22, 0.22)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(0.85, 0.95, 1.0)
	_lamp_mat.emission_energy_multiplier = 1.5
	var glow := MeshInstance3D.new()
	glow.mesh = Table._cylm(0.16, 0.16, 0.02, 14)
	glow.material_override = _lamp_mat
	glow.position = Vector3(0.0, 0.0, 0.0)
	l.add_child(glow)
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
	_lamp.position = Vector3(0.0, -0.05, 0.0)
	l.add_child(_lamp)


## A lever on each chosen pier's face, its handle up, a conduit running up the
## pier from its box into the vault. Which system each cuts is shuffled.
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
		n.transform = Transform3D(Basis.looking_at(-face, Vector3.UP), pier + face * (PIER_HALF + 0.02))
		n.add_child(Table._merge([
			[Table._boxm(Vector3(0.42, 0.62, 0.2)), Transform3D(Basis(), Vector3(0.0, LEVER_HEIGHT, 0.1)), &"rust"],
			[Table._boxm(Vector3(0.08, 0.5, 0.12)), Transform3D(Basis(), Vector3(0.0, LEVER_HEIGHT, 0.24)), &"dark"],
			[Table._cylm(0.05, 0.05, 5.0 - LEVER_HEIGHT, 8), Transform3D(Basis(), Vector3(0.12, LEVER_HEIGHT + (5.0 - LEVER_HEIGHT) * 0.5 + 0.3, 0.06)), &"dark"],
		], "Box"))
		var handle := Node3D.new()
		handle.name = "Handle"
		handle.position = Vector3(0.0, LEVER_HEIGHT, 0.3)
		n.add_child(handle)
		handle.add_child(Table._merge([
			[Table._cylm(0.03, 0.03, 0.55, 8), Transform3D(Basis(), Vector3(0.0, 0.27, 0.0)), &"steel"],
			[Table._sphm(0.07), Transform3D(Basis(), Vector3(0.0, 0.56, 0.0)), &"dark"],
			[Table._cylm(0.06, 0.06, 0.1, 10), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), &"brass"],
		], "HandleMesh"))
		handle.rotation.x = -0.35
		var prompt := Interact.prompt("E   Pull", Vector3(0.0, LEVER_HEIGHT, 0.3))
		n.add_child(prompt)
		_levers.append({"node": n, "handle": handle, "system": order[i], "prompt": prompt, "back_at": 0.0})


## The story of the room: the last prisoners strapped to slabs with their new
## limbs half fitted, a table like the machine's own broken on its side, a rack
## of prosthetic limbs toppled, tools dropped where they were used, torn
## restraints, and the older dead on the floor. Returns the solid pieces
## ([centre, size, yaw] in the room's frame).
func _build_story(h: int, cell: float) -> Array:
	var cover: Array = []
	var bays := [Vector3(-6.0, 0.0, -6.0), Vector3(6.0, 0.0, -6.0), Vector3(-6.0, 0.0, 6.0), Vector3(6.0, 0.0, 6.0)]
	# Shuffled so the room is not the same in every seed.
	for i in range(bays.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: Vector3 = bays[i]
		bays[i] = bays[j]
		bays[j] = t
	# Two bays: a pair of slabs, a prisoner strapped to each.
	for b in 2:
		var bay: Vector3 = bays[b]
		var yaw := PI * 0.5 if _rng.randf() < 0.5 else 0.0
		for s: float in [-1.0, 1.0]:
			var along := Basis(Vector3.UP, yaw) * Vector3(s * 0.9, 0.0, 0.0)
			var at := bay + along
			_steel_slab(at, yaw, b * 2 + (0 if s < 0.0 else 1))
			cover.append([at + Vector3(0.0, 0.45, 0.0), Vector3(0.9, 0.9, 2.2), yaw])
	# A table like the machine's, broken and on its side.
	var wreck: Vector3 = bays[2]
	var wy := _rng.randf_range(-0.4, 0.4)
	_broken_table(wreck, wy)
	cover.append([wreck + Vector3(0.0, 0.5, 0.0), Vector3(2.5, 1.0, 1.0), wy])
	# The rack of limbs, toppled, and the crates they came in.
	var rack: Vector3 = bays[3]
	var ry := _rng.randf_range(-0.3, 0.3) + PI * 0.5
	_limb_rack(rack, ry)
	cover.append([rack + Vector3(0.0, 0.55, 0.0), Vector3(2.6, 1.1, 1.1), ry])
	# Tools on the floor round the pedestal, and a tray stand knocked over.
	for i in 9:
		var a := _rng.randf_range(-PI, PI)
		var r := _rng.randf_range(1.6, 2.6)
		_tool(Vector3(cos(a) * r, 0.0, sin(a) * r), _rng.randi_range(0, 3))
	# Torn restraints by the slabs and along the walls.
	for i in 8:
		var bay: Vector3 = bays[i % 2]
		_torn_restraint(bay + Vector3(_rng.randf_range(-2.0, 2.0), 0.0, _rng.randf_range(-2.0, 2.0)))
	# The older dead: in the ring's corners and against the walls, clear of the
	# lanes the table hunts down.
	var corners := [Vector3(-11.6, 0.0, -11.6), Vector3(11.6, 0.0, -11.6), Vector3(-11.6, 0.0, 11.6), Vector3(11.6, 0.0, 11.6)]
	for c: Vector3 in corners:
		if _rng.randf() < 0.85:
			_corpse(c + Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5)),
				_rng.randf_range(-PI, PI), _missing(_rng.randf() < 0.7))
	return cover


## A steel slab on two trestles, a prisoner strapped down on it: on its back,
## one forearm gone and a new limb bolted in its place (`kind` picks which).
func _steel_slab(at: Vector3, yaw: float, kind: int) -> void:
	var n := Node3D.new()
	n.name = "OperatingSlab"
	add_child(n)
	n.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	n.add_child(Table._merge([
		[Table._boxm(Vector3(0.85, 0.08, 2.1)), Transform3D(Basis(), Vector3(0.0, 0.86, 0.0)), &"steel"],
		[Table._boxm(Vector3(0.75, 0.82, 0.08)), Transform3D(Basis(), Vector3(0.0, 0.41, -0.85)), &"dark"],
		[Table._boxm(Vector3(0.75, 0.82, 0.08)), Transform3D(Basis(), Vector3(0.0, 0.41, 0.85)), &"dark"],
		[Table._boxm(Vector3(0.9, 0.03, 0.09)), Transform3D(Basis(), Vector3(0.0, 0.98, -0.45)), &"leather"],
		[Table._boxm(Vector3(0.9, 0.03, 0.09)), Transform3D(Basis(), Vector3(0.0, 0.98, 0.5)), &"leather"],
	], "SlabMesh"))
	_solid(n, Vector3(0.85, 0.9, 2.1), Vector3(0.0, 0.45, 0.0))
	var body := _corpse(Vector3.ZERO, 0.0, [])
	# Onto the slab, along it.
	remove_child(body)
	n.add_child(body)
	var low := body.position.y
	body.transform = Transform3D(Basis(Vector3.UP, PI * float(kind % 2)) * body.transform.basis, Vector3(0.0, 0.9 + low, 0.0))
	var sk: Skeleton3D = null
	var found := body.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		sk = found[0] as Skeleton3D
	if sk == null:
		return
	var limb: StringName = [&"forearm.R", &"forearm.L", &"shin.R", &"forearm.R"][kind % 4]
	var parent_bone: String = {&"forearm.R": "upper_arm.R", &"forearm.L": "upper_arm.L", &"shin.R": "thigh.R"}[limb]
	var b := sk.find_bone(limb)
	if b < 0:
		return
	sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)
	var att := BoneAttachment3D.new()
	att.bone_name = parent_bone
	sk.add_child(att)
	var piece := MeshInstance3D.new()
	match kind % 3:
		0:
			piece.mesh = SkeletonSword.drill_bit_mesh()
			piece.scale = Vector3.ONE * 1.3
		1:
			piece.mesh = Table._merge_mesh([[Table._boxm(Vector3(0.02, 0.42, 0.07)), Transform3D(Basis(), Vector3(0.0, 0.21, 0.0)), &"steel"]])
		_:
			piece.mesh = Table._merge_mesh([[Table._cylm(0.03, 0.03, 0.3, 8), Transform3D(Basis(), Vector3(0.0, 0.15, 0.0)), &"steel"],
				[Table._boxm(Vector3(0.12, 0.14, 0.12)), Transform3D(Basis(), Vector3(0.0, 0.34, 0.0)), &"dark"]])
	piece.position = Vector3(0.0, 0.27, 0.0)
	att.add_child(piece)
	var collar := MeshInstance3D.new()
	collar.mesh = Table._cylm(0.045, 0.05, 0.08, 8)
	collar.material_override = Table._mat(&"brass")
	collar.position = Vector3(0.0, 0.25, 0.0)
	att.add_child(collar)


## A surgical table like the machine, but dead: on its side, two legs in the air.
func _broken_table(at: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.name = "BrokenTable"
	add_child(n)
	n.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	var side := Basis(Vector3.BACK, PI * 0.5 - 0.08)
	n.add_child(Table._merge([
		[Table._boxm(Vector3(0.9, 0.12, 2.3)), Transform3D(side, Vector3(0.0, 0.48, 0.0)), &"steel"],
		[Table._boxm(Vector3(0.6, 0.34, 1.8)), Transform3D(side, Vector3(-0.27, 0.45, 0.0)), &"dark"],
		[Table._boxm(Vector3(0.05, 0.4, 2.0)), Transform3D(side * Basis(Vector3.FORWARD, 0.4), Vector3(-0.4, 0.15, 0.0)), &"rust"],
		[Table._cylm(0.05, 0.035, 1.2, 8), Transform3D(Basis(Vector3.FORWARD, 0.5) * Basis(Vector3.RIGHT, 0.3), Vector3(-0.7, 1.0, -0.6)), &"dark"],
		[Table._cylm(0.05, 0.035, 1.1, 8), Transform3D(Basis(Vector3.FORWARD, 0.8) * Basis(Vector3.RIGHT, -0.4), Vector3(-0.75, 0.9, 0.7)), &"dark"],
		[Table._cylm(0.05, 0.035, 0.9, 8), Transform3D(Basis(Vector3.FORWARD, 1.4), Vector3(-0.9, 0.35, 0.1)), &"rust"],
	], "WreckMesh"))
	_solid(n, Vector3(1.0, 1.0, 2.4), Vector3(-0.1, 0.5, 0.0))


## A rack of prosthetic limbs, toppled over: its frame on the floor, drills,
## blades and hammer hands spilled from it, the crates they came in.
func _limb_rack(at: Vector3, yaw: float) -> void:
	var n := Node3D.new()
	n.name = "LimbRack"
	add_child(n)
	n.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	var parts: Array = [
		[Table._boxm(Vector3(2.4, 0.08, 0.08)), Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(0.0, 0.85, 0.0)), &"rust"],
		[Table._boxm(Vector3(2.4, 0.08, 0.08)), Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(0.0, 0.25, 0.3)), &"rust"],
		[Table._boxm(Vector3(0.08, 1.1, 0.08)), Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(-1.15, 0.55, 0.15)), &"rust"],
		[Table._boxm(Vector3(0.08, 1.1, 0.08)), Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(1.15, 0.55, 0.15)), &"rust"],
		[Table._boxm(Vector3(0.8, 0.6, 0.6)), Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.7, 0.3, -0.7)), &"rust"],
		[Table._boxm(Vector3(0.7, 0.5, 0.55)), Transform3D(Basis(Vector3.UP, -0.2), Vector3(0.6, 0.25, -0.75)), &"rust"],
	]
	for i in 5:
		var x := -0.9 + float(i) * 0.45
		parts.append([Table._boxm(Vector3(0.02, 0.36, 0.06)), Transform3D(Basis(Vector3.FORWARD, _rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, 1.3),
			Vector3(x, 0.06, 0.55 + _rng.randf_range(0.0, 0.4)) ), &"steel"])
	n.add_child(Table._merge(parts, "RackMesh"))
	for i in 3:
		var bit := MeshInstance3D.new()
		bit.mesh = SkeletonSword.drill_bit_mesh()
		bit.transform = Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)) * Basis(Vector3.FORWARD, PI * 0.5) * Basis().scaled(Vector3.ONE * 1.3),
			Vector3(_rng.randf_range(-1.0, 1.0), 0.05, _rng.randf_range(0.4, 1.0)))
		n.add_child(bit)
	for i in 3:
		_loose_bone(at + Basis(Vector3.UP, yaw) * Vector3(_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(0.6, 1.3)))
	_solid(n, Vector3(2.6, 1.1, 1.1), Vector3(0.0, 0.55, 0.0))


## A tool dropped on the floor: a bone saw, forceps, a hand drill or a bucket.
func _tool(at: Vector3, kind: int) -> void:
	var parts: Array = []
	match kind:
		0:
			parts = [[Table._boxm(Vector3(0.36, 0.01, 0.1)), Transform3D(Basis(), Vector3(0.0, 0.01, 0.0)), &"steel"],
				[Table._boxm(Vector3(0.12, 0.04, 0.05)), Transform3D(Basis(), Vector3(-0.23, 0.02, 0.0)), &"leather"]]
		1:
			parts = [[Table._boxm(Vector3(0.22, 0.012, 0.015)), Transform3D(Basis(Vector3.UP, 0.12), Vector3(0.0, 0.01, 0.01)), &"steel"],
				[Table._boxm(Vector3(0.22, 0.012, 0.015)), Transform3D(Basis(Vector3.UP, -0.12), Vector3(0.0, 0.01, -0.01)), &"steel"]]
		2:
			parts = [[Table._cylm(0.03, 0.03, 0.25, 8), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, 0.03, 0.0)), &"brass"],
				[Table._boxm(Vector3(0.04, 0.03, 0.14)), Transform3D(Basis(), Vector3(0.05, 0.02, 0.08)), &"dark"]]
		_:
			parts = [[Table._cylm(0.15, 0.12, 0.28, 12), Transform3D(Basis(Vector3.BACK, 1.45), Vector3(0.0, 0.14, 0.0)), &"rust"]]
	var mi := Table._merge(parts, "Tool")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)), at)
	add_child(mi)


## A restraint torn off its slab: the cuff, a twisted strap, a few chain links.
func _torn_restraint(at: Vector3) -> void:
	var parts: Array = [[Table._boxm(Vector3(0.26, 0.04, 0.1)), Transform3D(Basis(Vector3.FORWARD, 0.2), Vector3(0.0, 0.04, 0.0)), &"steel"],
		[Table._boxm(Vector3(0.3, 0.012, 0.08)), Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.22, 0.008, 0.12)), &"leather"]]
	for k in 4:
		parts.append([Table._torusm(0.025, 0.045), Transform3D(Basis(Vector3.RIGHT, PI * 0.5 * float(k % 2)) * Basis(Vector3.UP, float(k)),
			Vector3(-0.18 - float(k) * 0.07, 0.03, -0.05 + float(k) * 0.02)), &"dark"])
	var mi := Table._merge(parts, "TornRestraint")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)), at)
	add_child(mi)


# --- The furnishing (note 95) ----------------------------------------------------

## Only the wall pilasters keep torches here: the middle of the hall is lit by
## the chandeliers in its bays and the lamp in the ring, as in the reference
## (morgue.gd hangs one on every pier as well -- sixteen more lights).
func _hang_wall_torches(h: int, cell: float, pilaster_in: float) -> void:
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
			var along := Vector3(-d.z, 0.0, d.x) * v
			level._hang_torch(self, scene, d * (pilaster_in - 0.02) + along + Vector3(0.0, TORCH_HEIGHT, 0.0), d, energy, 13.0)


## A candle chandelier (models/surgery/chandelier.glb) from the crown of each
## corner bay, its warm light under it. Plain lights without shadows: the
## hall's walls close them in, and Graphics scales their reach (light_detail).
func _hang_chandeliers() -> void:
	var cell: float = built.cell_size
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var c := Node3D.new()
			c.name = "Chandelier"
			add_child(c)
			c.position = Vector3(sx * cell, CHANDELIER_TOP, sz * cell)
			c.rotation.y = _rng.randf_range(-PI, PI)
			var model: Node3D = CHANDELIER.instantiate()
			c.add_child(model)
			_glow(model, 1.4)
			var light := OmniLight3D.new()
			light.name = "Candles"
			light.light_color = CANDLE_COLOUR
			light.light_energy = 2.8
			light.omni_range = 10.5
			light.omni_attenuation = 1.2
			light.light_specular = 0.2
			light.shadow_enabled = false
			light.position = Vector3(0.0, -1.35, 0.0)
			c.add_child(light)


## The wall slots the mechanisms left, furnished as the reference's walls are:
## a study (the worktable with its skull, book and tools, the anatomy chart over
## it, a chest), apothecary shelves, specimen jars with a chest between them.
func _furnish(slots: Array) -> void:
	var free: Array = slots.filter(func(s): return not s["used"])
	for i in range(free.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = free[i]
		free[i] = free[j]
		free[j] = t
	var kinds := [&"study", &"apothecary", &"specimens", &"apothecary", &"specimens", &"apothecary", &"study"]
	for i in free.size():
		var s: Dictionary = free[i]
		s["used"] = true
		var n := _on_wall(s, "Furniture")
		match kinds[i % kinds.size()]:
			&"study":
				_place(n, WORKTABLE, Vector3(0.0, 0.0, 0.9), PI * 0.5, Vector3(2.0, 0.95, 1.55))
				_place(n, CHEST, Vector3(1.75, 0.0, 0.6), PI * 0.5 + _rng.randf_range(-0.15, 0.15), Vector3(1.15, 0.62, 0.92))
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
				chart.position = Vector3(-0.2, 2.55, 0.03)
				chart.rotation.z = _rng.randf_range(-0.04, 0.04)
				n.add_child(chart)
			&"apothecary":
				for x: float in [-0.92, 0.92]:
					_place(n, SHELF, Vector3(x, 0.0, 0.25), 0.0, Vector3(1.6, 3.0, 0.45))
			_:
				for x: float in [-1.15, 1.15]:
					_place(n, JAR, Vector3(x, 0.0, 0.55), _rng.randf_range(-PI, PI), Vector3(0.8, 2.1, 0.8))
				_place(n, CHEST, Vector3(0.0, 0.0, 0.55), PI * 0.5 + _rng.randf_range(-0.2, 0.2), Vector3(1.15, 0.62, 0.92))
				# The jars' glow.
				var glow := OmniLight3D.new()
				glow.name = "SpecimenGlow"
				glow.light_color = Color(0.55, 1.0, 0.3)
				glow.light_energy = 0.7
				glow.omni_range = 3.6
				glow.omni_attenuation = 1.6
				glow.shadow_enabled = false
				glow.position = Vector3(0.0, 1.3, 1.1)
				n.add_child(glow)


## How much each kit piece glows with its own picture (`_glow`).
const GLOWS := {"shelf": 0.35, "jar": 1.1, "worktable": 0.3, "chest": 0.0}


## Lights a kit piece with its own picture (surgical_table.gd `glow`).
func _glow(piece: Node, energy: float) -> void:
	Table.glow(piece, energy)


## A kit piece on wall node `n` at `at` (+Z out into the room), turned `yaw`,
## solid as a box of `size` (its footprint, before the turn).
func _place(n: Node3D, scene: PackedScene, at: Vector3, yaw: float, size: Vector3) -> void:
	var piece: Node3D = scene.instantiate()
	n.add_child(piece)
	_glow(piece, float(GLOWS.get(scene.resource_path.get_file().get_basename(), 0.0)))
	piece.position = at
	piece.rotation.y = yaw
	for node in piece.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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

## The table's restraint arm, from its shoulder out to `tip`: caught if the
## clamp is open and the arm runs through its jaws -- it need not end in them:
## the jaws snap shut on whatever passes between them.
func clamp_try_catch(shoulder: Vector3, tip: Vector3) -> bool:
	if _clamp.is_empty() or _clamp_state != &"open":
		return false
	if Table._segment_distance(to_global(_clamp["mouth"]), shoulder, tip) > CATCH:
		return false
	_clamp_state = &"held"
	table.call("_sparks", tip, Color(1.0, 0.8, 0.5), 30)
	for p in Coop.all():
		if p.get("_shake") != null and (p as Node3D).global_position.distance_to(tip) < 14.0:
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
	var mesh := CylinderMesh.new()
	mesh.top_radius = CABLE_RADIUS
	mesh.bottom_radius = CABLE_RADIUS
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 1
	var mat := ShaderMaterial.new()
	mat.shader = CABLE_SHADER
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


func _work_mechanisms(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var glow: float = table.get("core_glow")
	var down: bool = table.call("is_depowered")
	if _mech.has(&"arms"):
		var m: Dictionary = _mech[&"arms"]
		var arm: float = table.get("arm_motion")
		_spin["arms"] = float(_spin["arms"]) + delta * arm * 4.0
		(m["gear"] as Node3D).rotation.z = float(_spin["arms"])
		var rods: Array = m["rods"]
		for k in rods.size():
			var pump := 0.22 * arm * sin(float(_spin["arms"]) * 3.0 + float(k) * PI)
			(rods[k] as Node3D).position.y = 1.0 + pump
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
		var rod: StandardMaterial3D = m["rod"]
		rod.emission = Table.CORE_COLOUR.lerp(Table.FEED_COLOUR, clampf(feed, 0.0, 1.0))
		rod.emission_energy_multiplier = 0.2 + 4.0 * glow + 2.0 * feed
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
		_lamp_mat.emission_energy_multiplier = e * 0.8


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
	tw.tween_property(_bar, "transform", Transform3D(Basis(Vector3.BACK, 0.9) * Basis(Vector3.RIGHT, 0.1),
		Vector3(0.35, 1.45, 0.72)), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
		_bar.transform = Transform3D(Basis(Vector3.BACK, 0.9) * Basis(Vector3.RIGHT, 0.1), Vector3(0.35, 1.45, 0.72))
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
