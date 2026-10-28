extends Node3D

## The chest rooms (2026-10-09), replacing the puzzle rooms: places a living
## dungeon would have. Built by maze.gd (`_build_puzzle_rooms`) under the
## navigation region, before the bake; one per chest room except the morgue,
## each holding one of the great door's shards.
##
##   prison   THE PRISON BLOCK -- two rows of barred cells facing each other
##            across the court, a generator between them running on a red
##            crystal, and enforcers (enforcer.gd) posted in front of the
##            cells. Step into the room and they turn on you. Once they are
##            all down the crystal can be taken (E): the generator dies, every
##            lock lets go, the cell doors swing open and the prisoners come
##            out fighting. The room's chest is in one of the cells -- the
##            confiscated goods -- and opens only once the power is cut.
##   mine     THE CRYSTAL MINE (2026-10-10) -- a face of raw rock across the
##            back of the court, seamed with gold and red crystal, worked by
##            shackled prisoners with drills for hands (note 93) and by three electric drills
##            grinding into it, powered down brass cables from a generator that
##            runs on the room's SHARD. Two enforcers oversee the work. Step
##            in and the enforcers turn on you and drive the miners at you, drills
##            and all. With every one of them down, E takes the shard out of the
##            generator: the drills spin down and the shard is the player's.
##   vacant   A placeholder until the other rooms are designed: the court with
##            the chest (or, in the room furthest from the start, the mimic) on
##            a low dais.
##
## Not sealed: maze.gd still reads `sealed` (always false here), and the
## Remnant asks `is_warding` (never). Deaths: enforcers come back unless every
## one was destroyed; a cut generator stays cut, and prisoners who were let out
## and not yet killed are back in their open cells.

const CHEST_SCENE := preload("res://scenes/chest.tscn")
const MIMIC_SCENE := preload("res://scenes/mimic.tscn")
const SKELETON_MODEL := preload("res://models/ossuary_skeleton_rigged.glb")
const ENFORCER_SCRIPT := preload("res://scripts/enforcer.gd")
const EYES := preload("res://scripts/skeleton_eyes.gd")
const BEAM_SHADER := preload("res://shaders/energy_beam.gdshader")
## The crystal's centre as a share of the Tripo generator's height: inside the
## open brass cradle on top (its base at ~0.78, the prongs' tips at 1.0).
const GEN_CRYSTAL_AT := 0.9
## The kit frieze's length (build_brick_kit.FRIEZE_LEN).
const FRIEZE_LEN := 6.7

const TITLES := {
	&"prison": ["THE PRISON BLOCK", "The enforcers turn from the cells."],
	&"mine": ["THE CRYSTAL MINE", "The enforcers drive the miners at you."],
	&"vacant": ["", ""],
}

const RED := Color(1.0, 0.12, 0.07)

## The cells: two rows of CELLS across the court, facing each other.
const CELLS := 4
const CELL_W := 2.5
const CELL_D := 2.7
const CELL_H := 2.9
const WALL := 0.25
## Centre of the court to the front of a row.
const FRONT := 4.4
const DOOR_W := 1.15
const DOOR_H := 2.35
const BAR_R := 0.022
## How many cells (of the eight) hold a prisoner; one is the locker.
const PRISONERS := 5
## The enforcers' posts in front of the cells: (x, z, which row they watch).
const POSTS := [Vector3(-3.5, -2.0, -1.0), Vector3(3.5, -2.0, -1.0), Vector3(0.0, 2.3, 1.0)]
## How far inside the room's block the player is before the enforcers notice.
const ALARM_IN := 1.8
const PRISONER_SCALE := 0.94

## A CONTAINMENT block (note 120) is a prison holding one skeleton type, `hand`
## (&"blade", &"hammer", &"shield", &"crossbow", &"drill"): its prisoners are real
## skeletons of that type, caged (enemy.gd `caged`) -- blind, deaf and unhurt --
## and every cell has a mechanical back door in its back wall. The crystal out,
## the front gates stay shut and the back doors grind up: the prisoners walk out
## through them into the dark, and the type is loose in the maze
## (maze.gd `release_hand`). Empty for the plain prison.
var hand: StringName = &""
const HAND_NAMES := {&"blade": "SWORD", &"hammer": "HAMMER", &"shield": "SHIELD",
	&"crossbow": "CROSSBOW", &"drill": "DRILL"}
const BACK_DOOR_W := 1.2
const BACK_DOOR_H := 2.3
## How far the back door's slab slides up its rails.
const BACK_LIFT := 2.25
## How far in front of BAY_DEEP the door is built: the brick's real face.
const BACK_FACE := 0.16
## How fast a prisoner walks out to it.
const WALK_OUT := 1.3
const GREEN := Color(0.25, 1.0, 0.35)
var _back_lamp_mat: StandardMaterial3D
## The prisoners let out this run; the room's share of `release_hand`.
var walked_out := 0

var built
var room: Dictionary = {}
var kind: StringName = &"vacant"
var shard: StringName = &""
var is_mimic := false
var maze: Node
var tint := 1.0

## maze.gd reads these: never sealed, the shard taken or not.
var sealed := false
var looted := false
var enforcers_down := false
var powered_off := false
var prisoners_down := false

var _rng := RandomNumberGenerator.new()
var _span := 9.0
var _block := 15.0
var _player: Node3D
var _prompt: Interact.Prompt
var _focus := false
var _alarmed := false
var _reward: Node3D

# The prison's parts.
## {row, k, centre (local), door, door_body, prisoner (decor) or null,
##  locker: bool, alive: bool (its prisoner, once let out)}
var _cells: Array[Dictionary] = []
var _enforcers: Array[Node] = []
var _freed: Array[Node] = []
var _gen: Node3D
var _crystal: Node3D
var _crystal_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _gen_light: OmniLight3D
var _pistons: Array[Node3D] = []
var _flywheel: Node3D
var _crystal_y := 2.05
var _beams: Array[MeshInstance3D] = []
var _power := 1.0
var _time := 0.0

static var _mats := {}
static var _meshes := {}


static func build(holder: Node3D, level, room_: Dictionary, kind_: StringName, shard_: StringName,
		mimic_: bool, maze_: Node, tint_: float, hand_ := &"") -> Node3D:
	var p := Node3D.new()
	p.set_script(load("res://scripts/dungeon_room.gd"))
	p.name = "ChestRoom"
	p.set("hand", hand_)
	p.set("built", level)
	p.set("room", room_)
	p.set("kind", kind_)
	p.set("shard", shard_)
	p.set("is_mimic", mimic_)
	p.set("maze", maze_)
	p.set("tint", tint_)
	holder.add_child(p)
	p.call("_dress")
	return p


func title() -> String:
	if kind == &"prison" and hand != &"":
		return "CONTAINMENT: %s HANDS" % HAND_NAMES.get(hand, String(hand).to_upper())
	return String(TITLES[kind][0]) if kind != &"vacant" else "CHEST ROOM"


func is_containment() -> bool:
	return kind == &"prison" and hand != &""


## Where the collector (collector.gd) hands its subjects in: the corridor cell
## just outside the block's nearest way in to `from`.
func drop_point(from: Vector3) -> Vector3:
	var best := global_position
	var best_d := INF
	for door in built.room_doors(room):
		var step: Vector2i = door["outward"]
		var at: Vector3 = built.to_world((door["cell"] as Vector2i) + step)
		var d := at.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = at
	return best


## Never: nothing here shuts the player in. (The Remnant asks.)
func is_warding(_point: Vector3) -> bool:
	return false


# --- Building ---------------------------------------------------------------------

func _dress() -> void:
	add_to_group(&"chest_room")
	var centre: Vector3 = built.room_world(room)
	# The local frame: origin the court's centre, +Z toward the first way in.
	var out := Vector3(0.0, 0.0, 1.0)
	var doors: Array = built.room_doors(room)
	if not doors.is_empty():
		var step: Vector2i = doors[0]["outward"]
		out = Vector3(float(step.x), 0.0, float(step.y))
	global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), centre)
	_rng.seed = hash(room["centre"]) ^ 0x7072
	_span = built.court_half_span(room)
	_block = (float(room["half"]) + 0.5) * float(built.cell_size)
	_prompt = Interact.prompt("E   Take the shard" if kind == &"mine" else "E   Take the crystal")
	add_child(_prompt)
	_prompt.visible = false
	match kind:
		&"prison":
			_build_prison()
		&"mine":
			_build_mine()
		_:
			_build_vacant()
	print("[rooms] %s at %s%s, shard %s" % [title(), room["centre"],
		" (the mimic's room)" if is_mimic else "", shard])


func _build_vacant() -> void:
	var dais := _box(self, Vector3(2.6, 0.14, 2.0), Vector3(0.0, 0.07, 0.0), _mat(&"stone"))
	dais.name = "Dais"
	_solid(self, Vector3(2.6, 0.14, 2.0), Vector3(0.0, 0.07, 0.0))


## --- The prison block as a domed hall (2026-10-10) ---------------------------------
##
## With the brick kit the prison is no longer two rows of cells in an open
## court. The cells ARE the room's arcade: every arch round the court (one per
## ring cell along each side) is closed by a Tripo iron gate (brick kit
## "jail_gate_l/_r", cut from the gate of Tripo's prison cell), and the bay of
## arcade behind it is walled off from its neighbours ("wall" + "wall_top" in
## every ring-to-ring arch) into a cell. The bays at the room's doorways stay
## open: they are the way in. Over the court a band of brick wall rises from
## the arches to DOME_BASE and the Tripo dome ("prison_dome") springs from just
## outside it, wide enough to span the corners. A Tripo torch on every arch.
## (2026-10-11: the first dome was lopsided and open at the top, its corners
## closed by an untextured ring; replaced by a second Tripo dome turned inside
## out. The skylight beam and the hanging gibbets are gone; the gates are a
## second Tripo pass, full of bars.)
const BAY_GATE_IN := 0.5
const BAY_DEEP := 4.85
const BAND_BASE := 5.0
const BAND_FRONT := 0.62
const DOME_BASE := 8.35
## The dome's height as a share of its radius (the model rises 1.49 x it).
const DOME_RISE := 0.62
const GATE_HALF := 1.64


func _build_prison() -> void:
	if load("res://scripts/module_level.gd").brick:
		_build_domed_prison()
		return
	_build_block_prison()


func _build_domed_prison() -> void:
	_lamp_mat = _glow(RED, 3.0)
	_back_lamp_mat = _glow(RED, 3.0)
	var kit = load("res://scripts/brick_level.gd")
	var bays := _prison_bays()
	var cells: Array[int] = []
	for i in bays.size():
		if not bays[i]["entrance"]:
			cells.append(i)
	for i in range(cells.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	# No chest in any cell (2026-10-14): the shard comes out of the generator
	# with its crystal, as in the mine.
	var held := {}
	for n in mini(PRISONERS, cells.size()):
		held[cells[n]] = true

	var level = load("res://scripts/module_level.gd")
	var torch_scene: PackedScene = load(level.TORCH_SCENE)
	var energy: float = float(maze.get("module_torch_energy")) * 1.6 if maze != null else 3.0
	for i in bays.size():
		var bay: Dictionary = bays[i]
		var xf: Transform3D = bay["xf"]
		# A torch on every arch, on its left leg's court face.
		var at := xf * Vector3(-2.42, 2.65, BAND_FRONT + 0.02)
		level._hang_torch(self, torch_scene, at, xf.basis * Vector3(0.0, 0.0, -1.0), energy, 13.0)
		if bay["entrance"]:
			continue
		var cell := {"row": 0.0, "k": i, "centre": xf * Vector3(0.0, 0.0, -BAY_DEEP * 0.5),
			"locker": false, "alive": false, "prisoner": null,
			"open": -1.6, "open2": 1.6}
		for side: float in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.name = "Gate%d%s" % [i, "L" if side < 0.0 else "R"]
			hinge.transform = xf * Transform3D(Basis(), Vector3(side * GATE_HALF, 0.0, BAY_GATE_IN))
			add_child(hinge)
			var leaf := MeshInstance3D.new()
			leaf.mesh = kit.standalone("jail_gate_l" if side < 0.0 else "jail_gate_r")
			leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			hinge.add_child(leaf)
			cell["door" if side < 0.0 else "door2"] = hinge
		# One blocker over the whole opening (bars do not stop sight: layer 1),
		# live once the navmesh is baked.
		var db := StaticBody3D.new()
		db.collision_layer = 1
		db.collision_mask = 0
		add_child(db)
		_add_shape(db, Vector3(GATE_HALF * 2.0, 4.6, 0.15), xf * Vector3(0.0, 2.3, BAY_GATE_IN))
		(db.get_child(0) as CollisionShape3D).rotation = xf.basis.get_euler()
		(db.get_child(0) as CollisionShape3D).disabled = true
		cell["door_body"] = db
		var lamp := _sphere(0.07, _lamp_mat)
		lamp.position = xf * Vector3(0.0, 4.95, BAND_FRONT + 0.1)
		cell["lock"] = lamp.position
		add_child(lamp)
		_dress_bay(cell, xf, held.has(i))
		_cells.append(cell)

	if is_containment():
		_torches_off_back_doors()
	_build_partitions(kit)
	_build_dome_hall(kit)
	_build_generator()
	_build_beams()
	_drop_sky_lights()
	if maze != null and maze.has_signal("level_built"):
		maze.connect("level_built", _arm_doors, CONNECT_ONE_SHOT)


## One bay per ring cell along each side of the court (corners have none):
## {pos, xf, entrance}, `xf` in this room's frame with its origin on the court
## boundary at the middle of the arch and +Z pointing into the court.
func _prison_bays() -> Array:
	var c: Vector2i = room["centre"]
	var h: int = room["half"]
	var cs: float = built.cell_size
	var entrances := _open_ring()
	var out := []
	for dz in range(-h, h + 1):
		for dx in range(-h, h + 1):
			if maxi(absi(dx), absi(dz)) != h or (absi(dx) == h and absi(dz) == h):
				continue
			var p := c + Vector2i(dx, dz)
			if not built.cells.has(p):
				continue
			var step := Vector2i(-signi(dx) if absi(dx) == h else 0, -signi(dz) if absi(dz) == h else 0)
			var inward_w := Vector3(float(step.x), 0.0, float(step.y))
			var boundary := to_local((built.to_world(p) as Vector3) + inward_w * cs * 0.5)
			var inward := (global_basis.inverse() * inward_w).normalized()
			var basis := Basis(Vector3.UP, atan2(inward.x, inward.z))
			out.append({"pos": p, "xf": Transform3D(basis, Vector3(boundary.x, 0.0, boundary.z)),
				"entrance": entrances.has(p)})
	return out


## The ring cells that must stay passages, not cells: every doorway's ring cell,
## and -- when a doorway comes in at a CORNER, which has no bay of its own onto
## the court -- the bay beside that corner as well, so the way runs corner ->
## bay -> court. Without it the walls between cells sealed every corner
## entrance off (measured: 3 of 3 corner entrances led nowhere). Also fills
## `_open_pairs`, the ring-to-ring arches that must not be walled.
var _open_pairs := {}


func _open_ring() -> Dictionary:
	var c: Vector2i = room["centre"]
	var h: int = room["half"]
	var open := {}
	_open_pairs.clear()
	for way in room["entrances"]:
		var cell: Vector2i = way["cell"]
		open[cell] = true
		var d := cell - c
		if absi(d.x) != h or absi(d.y) != h:
			continue
		# A corner: of its two ring neighbours, the one along the side the
		# corridor did NOT come in through (that side's bay faces the court the
		# same way, so either works; this keeps the choice fixed for a seed).
		var step: Vector2i = load("res://scripts/module_maze.gd").DIRS[way["side"]]
		var along := Vector2i(-signi(d.x), 0) if step.x == 0 else Vector2i(0, -signi(d.y))
		var bay := cell + along
		if not built.cells.has(bay):
			bay = cell + (Vector2i(0, -signi(d.y)) if along.y == 0 else Vector2i(-signi(d.x), 0))
		open[bay] = true
		_open_pairs[_pair_key(cell, bay)] = true
	return open


static func _pair_key(a: Vector2i, b: Vector2i) -> Array:
	return [mini(a.x, b.x), mini(a.y, b.y), maxi(a.x, b.x), maxi(a.y, b.y)]


## Straw, chains on the back wall, a bucket, and a prisoner or bones. (The
## locker cell with the room's chest is gone, 2026-10-14: the shard comes out
## of the generator with the crystal.) In the bay's frame: the gate at +BAY_GATE_IN, the
## cell running back to -BAY_DEEP.
func _dress_bay(cell: Dictionary, xf: Transform3D, held: bool) -> void:
	var straw := _box(self, Vector3(1.4, 0.06, 1.0), Vector3.ZERO, _mat(&"straw"))
	straw.transform = xf * Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)),
		Vector3(_rng.randf_range(-1.0, 1.0), 0.03, -3.0))
	# A containment cell's back door takes the middle of the back wall; the
	# chains move out to its sides.
	var chains_at := 0.6
	if is_containment():
		_build_back_door(cell, xf)
		chains_at = 1.45
	for side: float in [-chains_at, chains_at]:
		var chain := _cyl(0.015, 0.9, 4, _mat(&"iron"))
		chain.position = xf * Vector3(side, 1.55, -BAY_DEEP + 0.14)
		add_child(chain)
		var cuff := _cyl(0.05, 0.05, 8, _mat(&"iron"))
		cuff.position = xf * Vector3(side, 1.08, -BAY_DEEP + 0.14)
		add_child(cuff)
	if _rng.randf() < 0.5:
		var bucket := _cyl(0.16, 0.3, 10, _mat(&"wood"))
		bucket.position = xf * Vector3(1.5, 0.15, -BAY_DEEP + 0.5)
		add_child(bucket)
	if cell["locker"]:
		var c: Node3D = CHEST_SCENE.instantiate()
		c.set("shard", shard)
		c.set("coins", _rng.randi_range(25, 60))
		c.set("min_amount", 1)
		c.set("max_amount", 3)
		c.set("opened_title", "SHARD RECOVERED")
		c.set("locked", true)
		add_child(c)
		c.transform = xf * Transform3D(Basis(), Vector3(0.0, 0.0, -3.4))
		c.connect("opened", _on_reward_taken.unbind(1))
		_reward = c
		for k in 2:
			var crate := _box(self, Vector3(0.5, 0.45, 0.5), Vector3.ZERO, _mat(&"wood"))
			crate.transform = xf * Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.2, 0.2)),
				Vector3(-1.4, 0.225 + 0.45 * float(k), -4.0))
		return
	if held and is_containment():
		# Where its caged skeleton stands (`_cage_prisoner`, put back on every
		# world reset): up at the bars, facing out into the hall, as the
		# prison's figures do. -Z of an enemy is its front.
		cell["xf"] = xf * Transform3D(Basis(Vector3.UP, PI + _rng.randf_range(-0.25, 0.25)),
			Vector3(_rng.randf_range(-0.5, 0.5), 0.0, -0.9))
		cell["held"] = true
		return
	if held:
		var decor := Node3D.new()
		decor.name = "Prisoner"
		var model: Node3D = SKELETON_MODEL.instantiate()
		model.transform = Transform3D(Basis.from_scale(Vector3(-PRISONER_SCALE, PRISONER_SCALE, -PRISONER_SCALE)),
			Vector3.ZERO)
		decor.add_child(model)
		add_child(decor)
		# Up at the bars, facing out into the hall.
		decor.transform = xf * Transform3D(Basis(Vector3.UP, PI + _rng.randf_range(-0.25, 0.25)),
			Vector3(_rng.randf_range(-0.5, 0.5), 0.0, -0.9))
		var ap := model.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			var anim := ap[0] as AnimationPlayer
			if anim.has_animation(&"idle"):
				anim.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
				anim.play(&"idle", -1.0, _rng.randf_range(0.8, 1.1))
				anim.seek(_rng.randf_range(0.0, anim.current_animation_length), true)
		EYES.attach(decor)
		cell["prisoner"] = decor
		cell["xf"] = decor.transform
		return
	for k in 5:
		var bone := _cyl(0.025, _rng.randf_range(0.25, 0.42), 5, _mat(&"bone"))
		bone.transform = xf * Transform3D(Basis.from_euler(Vector3(PI * 0.5, _rng.randf_range(0.0, TAU), 0.0)),
			Vector3(_rng.randf_range(-1.2, 1.2), 0.03, -_rng.randf_range(1.5, 4.0)))
		add_child(bone)


## A containment cell's mechanical back door, in the middle of its back wall
## (bay frame: the wall face at -BAY_DEEP): iron rails up either side, a riveted
## slab that slides up them, a gear wheel that turns as it goes, a lamp that goes
## from red to green, and pure black behind -- the passage the prisoners walk
## out into. Nothing is cut in the wall: the black is a panel on its face, and a
## prisoner reaching it is taken off the floor and slid into it (`_vanish`).
func _build_back_door(cell: Dictionary, xf: Transform3D) -> void:
	# The brick's face stands proud of BAY_DEEP: a panel at -BAY_DEEP + 0.03 was
	# behind it, and the open door showed brick (measured, screenshot).
	var z := -BAY_DEEP + BACK_FACE
	var w := BACK_DOOR_W
	var h := BACK_DOOR_H
	var hole := _box(self, Vector3(w, h, 0.02), Vector3.ZERO, _mat(&"void"))
	hole.transform = xf * Transform3D(Basis(), Vector3(0.0, h * 0.5, z + 0.03))
	hole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rail_h := h + BACK_LIFT + 0.2
	for side: float in [-1.0, 1.0]:
		var rail := _box(self, Vector3(0.14, rail_h, 0.16), Vector3.ZERO, _mat(&"rust"))
		rail.transform = xf * Transform3D(Basis(), Vector3(side * (w * 0.5 + 0.07), rail_h * 0.5, z + 0.08))
	var lintel := _box(self, Vector3(w + 0.28, 0.18, 0.18), Vector3.ZERO, _mat(&"rust"))
	lintel.transform = xf * Transform3D(Basis(), Vector3(0.0, h + 0.11, z + 0.09))
	# The slab rides in front of the rails, so it slides up over the lintel.
	var slab := Node3D.new()
	slab.name = "BackDoor%d" % int(cell["k"])
	slab.transform = xf * Transform3D(Basis(), Vector3(0.0, 0.0, z + 0.21))
	add_child(slab)
	_box(slab, Vector3(w, h, 0.07), Vector3(0.0, h * 0.5, 0.0), _mat(&"iron"))
	for band_y: float in [0.35, 1.15, 1.95]:
		_box(slab, Vector3(w + 0.02, 0.08, 0.1), Vector3(0.0, band_y, 0.0), _mat(&"rust"))
	for k in 6:
		var rivet := _sphere(0.025, _mat(&"iron"))
		rivet.position = Vector3((float(k % 3) - 1.0) * 0.42, 0.75 + 0.8 * float(k / 3), 0.05)
		slab.add_child(rivet)
	var gear := _cyl(0.24, 0.07, 12, _mat(&"rust"))
	gear.transform = xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5),
		Vector3(-(w * 0.5 + 0.42), h - 0.3, z + 0.06))
	add_child(gear)
	var hub := _cyl(0.07, 0.12, 8, _mat(&"iron"))
	gear.add_child(hub)
	var lamp := _sphere(0.06, _back_lamp_mat)
	lamp.position = xf * Vector3(w * 0.5 + 0.36, h - 0.2, z + 0.1)
	add_child(lamp)
	cell["back_door"] = slab
	cell["gear"] = gear
	cell["bay_xf"] = xf
	# Where a prisoner walks to (a step off the door), and where it goes.
	cell["back"] = xf * Vector3(0.0, 0.0, z + 0.6)
	cell["into"] = xf * Vector3(0.0, 0.0, z - 1.2)


## The level hangs a torch on many a cell's back wall (module_level, before the
## rooms are dressed), and it hung right over the back door: moved along the
## wall to the door's side, clear of its gear and lamp.
func _torches_off_back_doors() -> void:
	var torch_script = load("res://scripts/torch.gd")
	for n in get_parent().find_children("*", "Node3D", true, false):
		if n.get_script() != torch_script or is_ancestor_of(n):
			continue
		var local := to_local((n as Node3D).global_position)
		for cell in _cells:
			if not cell.has("bay_xf"):
				continue
			var bay: Transform3D = cell["bay_xf"]
			var p := bay.affine_inverse() * local
			if absf(p.x) < 1.5 and p.z < -BAY_DEEP + 1.2 and p.z > -BAY_DEEP - 0.6:
				(n as Node3D).global_position = to_global(bay * Vector3(2.0 if p.x >= 0.0 else -2.0, p.y, p.z))
				n.set("_fixed_position", (n as Node3D).global_position)
				break


## A wall (and the band above it) across every arch between two ring cells:
## the arcade becomes a row of separate cells, and the corners are shut off.
func _build_partitions(kit) -> void:
	var c: Vector2i = room["centre"]
	var h: int = room["half"]
	var body := StaticBody3D.new()
	body.name = "CellWalls"
	body.collision_layer = 2 | 256 | 512
	body.collision_mask = 0
	add_child(body)
	for dz in range(-h, h + 1):
		for dx in range(-h, h + 1):
			if maxi(absi(dx), absi(dz)) != h:
				continue
			var p := c + Vector2i(dx, dz)
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var q := p + step
				var d := q - c
				if maxi(absi(d.x), absi(d.y)) != h or not built.cells.has(p) or not built.cells.has(q):
					continue
				# A corner doorway's way through to its open bay.
				if _open_pairs.has(_pair_key(p, q)):
					continue
				var mid := to_local(((built.to_world(p) as Vector3) + (built.to_world(q) as Vector3)) * 0.5)
				var n := (global_basis.inverse() * Vector3(float(step.x), 0.0, float(step.y))).normalized()
				var basis := Basis(Vector3.UP, atan2(n.x, n.z))
				var at := Vector3(mid.x, 0.0, mid.z) + n * 0.5
				for piece in [["wall", 0.0], ["wall_top", 3.4]]:
					var mi := MeshInstance3D.new()
					mi.mesh = kit.standalone(piece[0])
					mi.transform = Transform3D(basis, at + Vector3(0.0, piece[1], 0.0))
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
					add_child(mi)
				var shape := BoxShape3D.new()
				shape.size = Vector3(4.2, 5.0, 1.0)
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.transform = Transform3D(basis, Vector3(mid.x, 2.5, mid.z))
				body.add_child(cs)


## The band of wall over the arches and the dome over everything.
func _build_dome_hall(kit) -> void:
	# Overlapping a little: end to end, the wall pieces' ragged ends left dark
	# slots between them.
	var band_len := float(built.cell_size) + 0.7
	# Tripo's carved frieze (2026-10-14): a moulded course, a corbel table and
	# a cornice overhanging the court. The plain brick wall without the kit.
	var piece := "prison_frieze"
	var piece_len := FRIEZE_LEN
	if kit.standalone(piece) == null:
		piece = "wall"
		piece_len = 5.2
	for bay in _prison_bays():
		var xf: Transform3D = bay["xf"]
		var mi := MeshInstance3D.new()
		mi.name = "Frieze"
		mi.mesh = kit.standalone(piece)
		var b := xf.basis * Basis().scaled(Vector3(band_len / piece_len, 1.0, 1.0))
		mi.transform = Transform3D(b, xf * Vector3(0.0, BAND_BASE, BAND_FRONT))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
	# The dome (Tripo, turned inside out in build_brick_kit.py): wide enough to
	# span the hall's CORNERS, so it springs from just outside the band and
	# every view up meets wall or dome -- no flat ring round it. Centred on the
	# hall by construction, closed at the top (no skylight).
	var inner := _span - BAND_FRONT
	var radius := inner * sqrt(2.0) + 0.3
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	dome.mesh = kit.standalone("prison_dome")
	dome.transform = Transform3D(Basis().scaled(Vector3(radius, radius * DOME_RISE, radius)),
		Vector3(0.0, DOME_BASE, 0.0))
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(dome)
	# Turned inside out, the dome never cast the moon's shadow, nor did the band
	# (faced into the hall) on the moon's side: the hall was as moonlit as an
	# open court (note 114). Over the whole block, cells and all, floor to just
	# over the dome.
	var top := (dome.transform * dome.get_aabb()).end.y + 0.3
	kit.moon_shade(self, Vector3(_block * 2.0, top + 0.2, _block * 2.0), Vector3(0.0, top * 0.5 - 0.1, 0.0))
	# Embers' glow up under the dome, so its brick and ribs read out of the dark.
	for k in 4:
		var a := TAU * (float(k) + 0.5) / 4.0
		var up := OmniLight3D.new()
		up.light_color = Color(1.0, 0.5, 0.3)
		up.light_energy = 4.0
		up.omni_range = 13.0
		up.omni_attenuation = 1.1
		up.light_specular = 0.0
		up.shadow_enabled = false
		up.distance_fade_enabled = true
		up.distance_fade_begin = 45.0
		up.distance_fade_length = 10.0
		up.position = Vector3(cos(a) * 5.5, DOME_BASE + 2.0, sin(a) * 5.5)
		add_child(up)

## The room is roofed now: the court's sky lights go.
func _drop_sky_lights() -> void:
	var lights = maze.get("_room_sky_lights") if maze != null else null
	if lights == null or not is_instance_valid(lights):
		return
	for l in (lights as Node).get_children():
		var p := to_local((l as Node3D).global_position)
		if absf(p.x) < _block and absf(p.z) < _block:
			l.queue_free()


func _pipe(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.2:
		return
	var pipe := _cyl(0.05, length, 8, _mat(&"brass"))
	pipe.position = (a + b) * 0.5
	var dir := (b - a).normalized()
	pipe.basis = Basis(Vector3.UP, atan2(dir.x, dir.z)) * Basis(Vector3.RIGHT, PI * 0.5)
	add_child(pipe)


func _build_block_prison() -> void:
	var stone := _mat(&"stone")
	var dark := _mat(&"dark")
	_lamp_mat = _glow(RED, 3.0)
	# Which cell is the locker, and which hold prisoners.
	var order: Array[int] = []
	for i in CELLS * 2:
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	var locker := order[0]
	var held := {}
	for n in PRISONERS:
		held[order[1 + n]] = true

	for row: float in [-1.0, 1.0]:
		var front := row * FRONT
		var back := row * (FRONT + CELL_D)
		var mid_z := (front + back) * 0.5
		var span_x := float(CELLS) * CELL_W + WALL
		# The block: back wall, roof slab, and a wall between every pair of cells.
		var body := _solid(self, Vector3(span_x, CELL_H, WALL), Vector3(0.0, CELL_H * 0.5, back))
		_box(self, Vector3(span_x, CELL_H, WALL), Vector3(0.0, CELL_H * 0.5, back), stone)
		_box(self, Vector3(span_x + 0.3, 0.3, CELL_D + 0.35), Vector3(0.0, CELL_H + 0.15, mid_z + row * 0.05), stone)
		_add_shape(body, Vector3(span_x + 0.3, 0.3, CELL_D + 0.35), Vector3(0.0, CELL_H + 0.15, mid_z + row * 0.05))
		for k in CELLS + 1:
			var x := (float(k) - float(CELLS) * 0.5) * CELL_W
			_box(self, Vector3(WALL, CELL_H, CELL_D), Vector3(x, CELL_H * 0.5, mid_z), stone)
			_add_shape(body, Vector3(WALL, CELL_H, CELL_D), Vector3(x, CELL_H * 0.5, mid_z))
		# A lintel across the whole front, and a dark kerb along its foot.
		_box(self, Vector3(span_x, CELL_H - DOOR_H, 0.3), Vector3(0.0, (CELL_H + DOOR_H) * 0.5, front), stone)
		_add_shape(body, Vector3(span_x, CELL_H - DOOR_H, 0.3), Vector3(0.0, (CELL_H + DOOR_H) * 0.5, front))
		_box(self, Vector3(span_x, 0.08, 0.34), Vector3(0.0, 0.04, front), dark)

		for k in CELLS:
			var index := (0 if row < 0.0 else CELLS) + k
			var cx := (float(k) + 0.5 - float(CELLS) * 0.5) * CELL_W
			var inner := CELL_W - WALL
			var left := cx - inner * 0.5
			var cell := {"row": row, "k": k, "centre": Vector3(cx, 0.0, mid_z),
				"locker": index == locker, "alive": false, "prisoner": null}
			# The fixed half of the front: bars from the door's edge to the wall.
			var panel_w := inner - DOOR_W
			var panel := _bars(&"panel", panel_w)
			panel.position = Vector3(left + DOOR_W, 0.0, front)
			add_child(panel)
			var pb := StaticBody3D.new()
			pb.collision_layer = 1
			pb.collision_mask = 0
			add_child(pb)
			_add_shape(pb, Vector3(panel_w, DOOR_H, 0.1), Vector3(left + DOOR_W + panel_w * 0.5, DOOR_H * 0.5, front))
			# The door, hinged at the wall; it swings out into the aisle.
			var hinge := Node3D.new()
			hinge.name = "Door%d" % index
			hinge.position = Vector3(left, 0.0, front)
			add_child(hinge)
			hinge.add_child(_bars(&"door", DOOR_W))
			var lock := _box(hinge, Vector3(0.12, 0.2, 0.12), Vector3(DOOR_W - 0.08, 1.1, 0.0), _mat(&"iron"))
			lock.name = "Lock"
			cell["door"] = hinge
			# Bars do not stop sight (layer 1 only). Live once the navmesh is
			# baked, so the cell is not cut out of it and its prisoner can walk out.
			var db := StaticBody3D.new()
			db.collision_layer = 1
			db.collision_mask = 0
			hinge.add_child(db)
			_add_shape(db, Vector3(DOOR_W, DOOR_H, 0.1), Vector3(DOOR_W * 0.5, DOOR_H * 0.5, 0.0))
			(db.get_child(0) as CollisionShape3D).disabled = true
			cell["door_body"] = db
			# The lock lamp over the door: red while the generator runs.
			var lamp := _sphere(0.06, _lamp_mat)
			lamp.position = Vector3(left + DOOR_W * 0.5, DOOR_H + 0.15, front - row * 0.17)
			add_child(lamp)
			_dress_cell(cell, cx, front, back, row, held.has(index))
			_cells.append(cell)

	_build_generator()
	_build_conduits()
	if maze != null and maze.has_signal("level_built"):
		maze.connect("level_built", _arm_doors, CONNECT_ONE_SHOT)


## Straw, a bucket or chains, and either a prisoner, a heap of bones or (the
## locker) the room's chest.
func _dress_cell(cell: Dictionary, cx: float, front: float, back: float, row: float, held: bool) -> void:
	var straw := _box(self, Vector3(1.1, 0.06, 0.8), Vector3(cx + _rng.randf_range(-0.4, 0.4), 0.03,
		back - row * 0.6), _mat(&"straw"))
	straw.rotation.y = _rng.randf_range(-0.3, 0.3)
	for side: float in [-0.35, 0.35]:
		var chain := _cyl(0.015, 0.9, 4, _mat(&"iron"))
		chain.position = Vector3(cx + side, 1.55, back - row * 0.16)
		add_child(chain)
		var cuff := _cyl(0.05, 0.05, 8, _mat(&"iron"))
		cuff.position = Vector3(cx + side, 1.08, back - row * 0.16)
		add_child(cuff)
	if _rng.randf() < 0.5:
		var bucket := _cyl(0.16, 0.3, 10, _mat(&"wood"))
		bucket.position = Vector3(cx + 0.75, 0.15, back - row * 0.45)
		add_child(bucket)
	var facing := 0.0 if row < 0.0 else PI
	if cell["locker"]:
		var c: Node3D = CHEST_SCENE.instantiate()
		c.set("shard", shard)
		c.set("coins", _rng.randi_range(25, 60))
		c.set("min_amount", 1)
		c.set("max_amount", 3)
		c.set("opened_title", "SHARD RECOVERED")
		c.set("locked", true)
		add_child(c)
		c.position = Vector3(cx, 0.0, back - row * 0.75)
		c.rotation.y = facing
		c.connect("opened", _on_reward_taken.unbind(1))
		_reward = c
		# Crates of what else was taken off them, stacked beside it.
		for k in 2:
			var crate := _box(self, Vector3(0.5, 0.45, 0.5), Vector3(cx - 0.7, 0.225 + 0.45 * float(k),
				back - row * 0.45), _mat(&"wood"))
			crate.rotation.y = _rng.randf_range(-0.2, 0.2)
		return
	if held:
		var decor := Node3D.new()
		decor.name = "Prisoner"
		var model: Node3D = SKELETON_MODEL.instantiate()
		model.transform = Transform3D(Basis.from_scale(Vector3(-PRISONER_SCALE, PRISONER_SCALE, -PRISONER_SCALE)),
			Vector3.ZERO)
		decor.add_child(model)
		add_child(decor)
		# Standing up near the bars, facing out (-Z of the decor is its front).
		decor.position = Vector3(cx + _rng.randf_range(-0.35, 0.35), 0.0, front + row * 0.7)
		decor.rotation.y = (PI if row < 0.0 else 0.0) + _rng.randf_range(-0.25, 0.25)
		var ap := model.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			var anim := ap[0] as AnimationPlayer
			if anim.has_animation(&"idle"):
				anim.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
				anim.play(&"idle", -1.0, _rng.randf_range(0.8, 1.1))
				anim.seek(_rng.randf_range(0.0, anim.current_animation_length), true)
		EYES.attach(decor)
		cell["prisoner"] = decor
		return
	# Nobody: what is left of the last one.
	for k in 4:
		var bone := _cyl(0.025, _rng.randf_range(0.25, 0.42), 5, _mat(&"bone"))
		bone.position = Vector3(cx + _rng.randf_range(-0.5, 0.5), 0.03, back - row * _rng.randf_range(0.6, 1.4))
		bone.rotation = Vector3(PI * 0.5, _rng.randf_range(0.0, TAU), 0.0)
		add_child(bone)


## A panel of iron bars `width` across, from the floor to DOOR_H: one mesh,
## shared by every panel of that width.
func _bars(key: StringName, width: float) -> MeshInstance3D:
	var full := "%s_%.2f" % [key, width]
	if not _meshes.has(full):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := maxi(2, int(round(width / 0.15)))
		for b in n:
			var x := (float(b) + 0.5) / float(n) * width
			var bar := CylinderMesh.new()
			bar.top_radius = BAR_R
			bar.bottom_radius = BAR_R
			bar.height = DOOR_H
			bar.radial_segments = 6
			bar.rings = 1
			st.append_from(bar, 0, Transform3D(Basis(), Vector3(x, DOOR_H * 0.5, 0.0)))
		for y: float in [0.12, 1.25, DOOR_H - 0.08]:
			var band := BoxMesh.new()
			band.size = Vector3(width, 0.06, 0.05)
			st.append_from(band, 0, Transform3D(Basis(), Vector3(width * 0.5, y, 0.0)))
		var frame := BoxMesh.new()
		frame.size = Vector3(0.06, DOOR_H, 0.06)
		st.append_from(frame, 0, Transform3D(Basis(), Vector3(0.03, DOOR_H * 0.5, 0.0)))
		st.append_from(frame, 0, Transform3D(Basis(), Vector3(width - 0.03, DOOR_H * 0.5, 0.0)))
		st.generate_normals()
		_meshes[full] = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[full]
	mi.material_override = _mat(&"iron")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


## The generator in the middle of the hall, the red crystal floating in the
## cradle on top of it and lighting the room red.
func _build_generator() -> void:
	_gen = Node3D.new()
	_gen.name = "Generator"
	add_child(_gen)
	# The machine is Tripo's (brick kit "prison_generator", 2026-10-14) where
	# the kit is built; the crystal floats over its open cradle.
	var mesh: Mesh = null
	if load("res://scripts/module_level.gd").brick:
		mesh = load("res://scripts/brick_level.gd").standalone("prison_generator")
	if mesh != null:
		var machine := MeshInstance3D.new()
		machine.name = "Machine"
		machine.mesh = mesh
		machine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_gen.add_child(machine)
		var box := mesh.get_aabb()
		var tall := minf(box.size.y, 2.0)
		_solid(_gen, Vector3(box.size.x, tall, box.size.z),
			Vector3(box.get_center().x, box.position.y + tall * 0.5, box.get_center().z))
		_crystal_y = box.position.y + box.size.y * GEN_CRYSTAL_AT
		# Iron and brass: the kit flattens every piece to matte stone with no
		# specular, under which the machine read as a dull dark lump.
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s) as StandardMaterial3D
			if m != null:
				m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
				m.metallic = 0.5
				m.roughness = 0.5
	else:
		_build_generator_parts()
	_crystal = Node3D.new()
	_crystal.name = "Crystal"
	_crystal.position = Vector3(0.0, _crystal_y, 0.0)
	_gen.add_child(_crystal)
	_crystal_mat = _glow(RED, 4.0)
	var gem := _octa(0.34, 0.66, _crystal_mat)
	_crystal.add_child(gem)
	_gen_light = OmniLight3D.new()
	_gen_light.light_color = Color(1.0, 0.38, 0.26)
	_gen_light.light_energy = 3.0
	_gen_light.omni_range = 8.5
	_gen_light.omni_attenuation = 0.9
	_gen_light.shadow_enabled = false
	_gen_light.distance_fade_enabled = true
	_gen_light.distance_fade_begin = 40.0
	_gen_light.distance_fade_length = 10.0
	_gen_light.position = Vector3(0.0, _crystal_y + 0.55, 0.0)
	_gen.add_child(_gen_light)


## The old machine from primitives (no brick kit): a stone plinth, an iron
## housing with two pistons and a flywheel, and a brass cradle for the crystal.
func _build_generator_parts() -> void:
	var stone := _mat(&"stone")
	var iron := _mat(&"iron")
	var brass := _mat(&"brass")
	_box(_gen, Vector3(2.4, 0.35, 2.4), Vector3(0.0, 0.175, 0.0), stone)
	# Rusted plate, as the enforcers are made of: the plain dark iron read as a
	# black box under the crystal's red light.
	_box(_gen, Vector3(1.3, 1.0, 1.0), Vector3(0.0, 0.85, 0.0), _mat(&"rust"))
	_box(_gen, Vector3(1.38, 0.08, 1.08), Vector3(0.0, 1.32, 0.0), brass)
	_box(_gen, Vector3(1.38, 0.08, 1.08), Vector3(0.0, 0.42, 0.0), brass)
	var body := _solid(_gen, Vector3(2.4, 0.35, 2.4), Vector3(0.0, 0.175, 0.0))
	_add_shape(body, Vector3(1.3, 1.0, 1.0), Vector3(0.0, 0.85, 0.0))
	for side: float in [-0.35, 0.35]:
		var housing := _cyl(0.13, 0.3, 10, iron)
		housing.position = Vector3(side, 1.5, 0.3)
		_gen.add_child(housing)
		var piston := Node3D.new()
		piston.position = Vector3(side, 1.5, 0.3)
		_gen.add_child(piston)
		var rod := _cyl(0.06, 0.5, 8, brass)
		rod.position.y = 0.2
		piston.add_child(rod)
		_pistons.append(piston)
	_flywheel = Node3D.new()
	_flywheel.position = Vector3(0.75, 0.9, 0.0)
	_gen.add_child(_flywheel)
	var wheel := _cyl(0.42, 0.08, 18, iron)
	wheel.rotation.z = PI * 0.5
	_flywheel.add_child(wheel)
	for k in 3:
		var spoke := _box(_flywheel, Vector3(0.1, 0.78, 0.06), Vector3.ZERO, brass)
		spoke.rotation.x = PI * float(k) / 3.0
	# The cradle: four brass prongs up from the housing round the crystal.
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		var prong := _cyl(0.025, 0.9, 6, brass)
		prong.position = Vector3(cos(a) * 0.28, 1.75, sin(a) * 0.28)
		prong.rotation = Vector3(sin(a) * 0.22, 0.0, -cos(a) * 0.22)
		_gen.add_child(prong)
	_crystal_y = 2.05


## Beams of yellow energy from the crystal over the generator to every cell's
## lock lamp (2026-10-14; brass pipes along the floor before). One shared unit
## cylinder, stretched per beam; `_run_generator` drives their `power`.
func _build_beams() -> void:
	if _gen == null:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.055
	mesh.bottom_radius = 0.055
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 24
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	var from := _gen.position + Vector3(0.0, _crystal_y, 0.0)
	for i in _cells.size():
		var to: Vector3 = _cells[i]["lock"]
		var dir := to - from
		var length := dir.length()
		# Start a little out of the crystal so the beams meet round it, not in it.
		var a := from + dir / length * 0.35
		length -= 0.35
		var beam := MeshInstance3D.new()
		beam.name = "Beam%d" % i
		beam.mesh = mesh
		beam.material_override = mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var up := dir.normalized()
		beam.transform = Transform3D(Basis(Quaternion(Vector3.UP, up)) * Basis().scaled(Vector3(1.0, length, 1.0)),
			a + up * length * 0.5)
		beam.set_instance_shader_parameter(&"beam_length", length)
		beam.set_instance_shader_parameter(&"seed", float(i) * 1.37)
		add_child(beam)
		_beams.append(beam)


## Brass pipes from the generator along the floor to the foot of each row.
func _build_conduits() -> void:
	var brass := _mat(&"brass")
	for row: float in [-1.0, 1.0]:
		var length := FRONT - 1.2
		var pipe := _cyl(0.06, length, 8, brass)
		pipe.rotation.x = PI * 0.5
		pipe.position = Vector3(0.0, 0.07, row * (1.2 + length * 0.5))
		add_child(pipe)
		var run := float(CELLS) * CELL_W
		var along := _cyl(0.05, run, 8, brass)
		along.rotation.z = PI * 0.5
		along.position = Vector3(0.0, 0.07, row * (FRONT - 0.32))
		add_child(along)


# --- The crystal mine ------------------------------------------------------------------
##
## Local frame as ever: +Z toward the first way in. The rock face runs across
## the back of the court (-Z): seven lumps of raw rock (`_rock_mesh`, noise on a
## sphere, the room's stone mapped world-triplanar so nothing stretches) with
## gold and red crystal standing out of them. In front of it, from left to
## right, miners and drills take turns; the generator stands off to one side at
## the front, brass cables running back from it to every drill.

## Rock lumps across the back: how many, their radius, and how far in front of
## the court's back edge their centres stand.
const ROCKS := 7
const ROCK_R := 1.9
const ROCK_IN := 0.4
## The drills' x and the miners', across the face (fractions of the face width).
const DRILLS_AT := [-0.62, 0.0, 0.62]
const MINERS_AT := [-0.92, -0.31, 0.31, 0.92]
## Two more, breaking rock on the heap by the cart.
const HEAP_MINERS := 2
## Enforcers overseeing, (x, z) in the court; they face the rock.
const MINE_POSTS := [Vector2(-2.8, 0.2), Vector2(3.2, -1.2)]
const BIT_LENGTH := 1.25
const MINER_SCALE := 0.94

## {node, bit, sparks, base} per drill.
var _drills: Array[Dictionary] = []
var _swing_rng := RandomNumberGenerator.new()


func _build_mine() -> void:
	_swing_rng.seed = _rng.randi()
	var stone := _mat(&"rock")
	var face_w := float(ROCKS - 1) * ROCK_R * 1.05
	var back := -_span + ROCK_IN
	# The rock face.
	var gold := SurfaceTool.new()
	var red := SurfaceTool.new()
	gold.begin(Mesh.PRIMITIVE_TRIANGLES)
	red.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rock_body := StaticBody3D.new()
	rock_body.collision_layer = 1 | 2
	rock_body.collision_mask = 0
	add_child(rock_body)
	for k in ROCKS:
		var x := lerpf(-face_w * 0.5, face_w * 0.5, float(k) / float(ROCKS - 1))
		var size := Vector3(ROCK_R * _rng.randf_range(1.0, 1.2), ROCK_R * _rng.randf_range(1.2, 1.6),
			ROCK_R * 0.9)
		var at := Vector3(x, size.y * 0.35, back)
		var mi := MeshInstance3D.new()
		mi.mesh = _rock_mesh(k % 4)
		mi.material_override = stone
		mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.5, 0.5)).scaled(size), at)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		# A box inside the lump, short of its front, so nothing walks into the rock.
		_add_shape(rock_body, Vector3(size.x * 1.5, size.y * 1.6, size.z * 1.3), at - Vector3(0.0, 0.0, size.z * 0.2))
		# Seams of crystal standing out of the face.
		for c in _rng.randi_range(2, 3):
			var dir := Vector3(_rng.randf_range(-0.7, 0.7), _rng.randf_range(-0.1, 0.8), 1.0).normalized()
			var on := at + Vector3(dir.x * size.x, dir.y * size.y, dir.z * size.z) * 0.86
			var st := gold if _rng.randf() < 0.6 else red
			for n in _rng.randi_range(3, 5):
				var gem := SphereMesh.new()
				gem.radius = _rng.randf_range(0.07, 0.15)
				gem.height = _rng.randf_range(0.4, 0.8)
				gem.radial_segments = 4
				gem.rings = 2
				var out := (dir + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.3, 0.5),
					_rng.randf_range(-0.3, 0.3))).normalized()
				var b := Basis(Quaternion(Vector3.UP, out))
				st.append_from(gem, 0, Transform3D(b, on + out * gem.height * 0.25
					+ Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.12, 0.12), 0.0)))
	for pair in [[gold, Color(1.0, 0.72, 0.2)], [red, RED]]:
		var st: SurfaceTool = pair[0]
		st.generate_normals()
		var veins := MeshInstance3D.new()
		veins.name = "Veins"
		veins.mesh = st.commit()
		veins.material_override = _glow(pair[1], 2.2)
		veins.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(veins)
	# Where the face stands, for the drills and miners in front of it.
	var front := back + ROCK_R * 0.9 * 0.9
	for fx: float in DRILLS_AT:
		_drills.append(_build_drill(fx * face_w * 0.5, front))
	var index := 0
	for fx: float in MINERS_AT:
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.2, 0.2)),
			Vector3(fx * face_w * 0.5, 0.0, front + 1.05))
		_cells.append({"xf": xf, "prisoner": null, "alive": false, "dead": false, "index": index})
		index += 1
	# The heap by the ore cart, on the right, with two more breaking it up.
	var heap_at := Vector3(_span - 2.6, 0.0, -1.0)
	_build_heap(heap_at)
	for n in HEAP_MINERS:
		var side := -1.0 if n == 0 else 1.0
		var spot := heap_at + Vector3(side * 1.25, 0.0, 0.9)
		var face := (heap_at - spot)
		face.y = 0.0
		var xf := Transform3D(Basis.looking_at(face.normalized(), Vector3.UP), spot)
		_cells.append({"xf": xf, "prisoner": null, "alive": false, "dead": false, "index": index})
		index += 1
	for cell in _cells:
		_make_miner(cell)
	# The generator, off to the left at the front, burning the room's shard.
	_build_generator()
	_gen.position = Vector3(-_span + 3.2, 0.0, 2.6)
	var colour := Inventory.item_color(shard)
	_crystal_mat.emission = colour
	_crystal_mat.albedo_color = colour.darkened(0.6)
	_gen_light.light_color = colour.lerp(Color.WHITE, 0.2)
	# Cables from it to every drill, laid on the floor.
	var brass := _mat(&"brass")
	var from := _gen.position + Vector3(0.9, 0.06, 0.0)
	for d in _drills:
		var to: Vector3 = (d["node"] as Node3D).position + Vector3(0.0, 0.06, 0.9)
		var corner := Vector3(to.x, 0.06, from.z)
		for seg in [[from, corner], [corner, to]]:
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			var length := a.distance_to(b)
			if length < 0.05:
				continue
			var cable := _cyl(0.045, length, 6, brass)
			cable.position = (a + b) * 0.5
			cable.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
			add_child(cable)
	# The workbench (2026-10-11): front right, its front toward the middle of
	# the court, behind the enforcers' patch. Gold crystals buy weapon and armor
	# levels there. Solid, and built before the bake.
	var bench := Node3D.new()
	bench.name = "Workbench"
	bench.set_script(load("res://scripts/workbench.gd"))
	bench.position = Vector3(_span - 2.0, 0.0, _span - 3.4)
	bench.rotation.y = -PI * 0.5
	add_child(bench)


## A lump of rock: a coarse sphere pushed in and out by noise and shaded FLAT,
## so it reads as broken, chiselled stone. Smooth-shaded at finer resolution it
## read as orange clay under the court's red sky. Four kinds, shared.
static func _rock_mesh(kind_: int) -> ArrayMesh:
	var key := "rock_%d" % kind_
	if _meshes.has(key):
		return _meshes[key]
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 14
	sphere.rings = 8
	var arrays := sphere.get_mesh_arrays()
	var noise := FastNoiseLite.new()
	noise.seed = 31 + kind_ * 7
	noise.frequency = 0.8
	noise.fractal_octaves = 3
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var moved := {}
	for i in verts.size():
		var v := verts[i]
		# The seam's twin vertices share a position, so they are moved alike.
		if not moved.has(v):
			var n := v.normalized()
			var bump := noise.get_noise_3dv(v * 1.3) * 0.42 + noise.get_noise_3dv(v * 3.5) * 0.12
			var p := n * (1.0 + bump)
			# Flattened underneath, so it sits on the floor rather than on a point.
			p.y = maxf(p.y, -0.55)
			moved[v] = p
		verts[i] = moved[v]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Every face its own normal.
	st.set_smooth_group(0xFFFFFFFF)
	for i in index.size():
		st.set_uv(uvs[index[i]])
		st.add_vertex(verts[index[i]])
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## An electric drill on a skid: an iron frame, a rusted motor with brass coils
## and a glowing core, and a long spiralled bit driven into the face.
func _build_drill(x: float, face_z: float) -> Dictionary:
	var node := Node3D.new()
	node.name = "Drill"
	# Its origin on the floor, BIT_LENGTH + the motor back from the face.
	node.position = Vector3(x, 0.0, face_z + BIT_LENGTH + 0.75)
	add_child(node)
	var iron := _mat(&"iron")
	var rust := _mat(&"rust")
	var brass := _mat(&"brass")
	var wood := _mat(&"wood")
	_box(node, Vector3(1.0, 0.12, 1.6), Vector3(0.0, 0.06, 0.15), wood)
	for side: float in [-0.42, 0.42]:
		# An A-frame each side holding the motor up.
		for lean: float in [-0.35, 0.35]:
			var leg := _box(node, Vector3(0.06, 1.05, 0.06), Vector3(side, 0.6, 0.0), iron)
			leg.rotation.x = lean
			leg.position.z = lean * 0.5
	var motor := Node3D.new()
	motor.name = "Motor"
	motor.position = Vector3(0.0, 1.05, 0.0)
	node.add_child(motor)
	var housing := _cyl(0.32, 0.9, 12, rust)
	housing.rotation.x = PI * 0.5
	motor.add_child(housing)
	for z: float in [-0.3, 0.0, 0.3]:
		var coil := _cyl(0.35, 0.08, 12, brass)
		coil.rotation.x = PI * 0.5
		coil.position.z = z
		motor.add_child(coil)
	var core := _sphere(0.14, _glow(Color(1.0, 0.72, 0.2), 3.0))
	core.position = Vector3(0.0, 0.3, 0.1)
	motor.add_child(core)
	# The bit, spinning about its own length (-Z, into the rock).
	var bit := Node3D.new()
	bit.name = "Bit"
	bit.position = Vector3(0.0, 0.0, -0.45)
	motor.add_child(bit)
	var shaft := _cyl(0.07, 0.3, 8, iron)
	shaft.rotation.x = PI * 0.5
	shaft.position.z = -0.15
	bit.add_child(shaft)
	var cone := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.2
	c.height = BIT_LENGTH
	c.radial_segments = 10
	c.rings = 1
	cone.mesh = c
	cone.material_override = iron
	cone.rotation.x = -PI * 0.5
	cone.position.z = -0.3 - BIT_LENGTH * 0.5
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	bit.add_child(cone)
	# The flutes: thin blades wound round the cone, so the spin can be seen.
	for k in 10:
		var t := float(k) / 10.0
		var flute := _box(bit, Vector3(0.04, 0.03 + 0.2 * (1.0 - t), 0.16), Vector3.ZERO, brass)
		var a := t * TAU * 2.0
		var r := 0.2 * (1.0 - t)
		flute.position = Vector3(cos(a) * r, sin(a) * r, -0.3 - t * BIT_LENGTH)
		flute.rotation = Vector3(0.0, 0.0, a)
	var body := _solid(node, Vector3(1.0, 1.4, 1.6), Vector3(0.0, 0.7, 0.15))
	body.name = "DrillBody"
	var sparks: CPUParticles3D = null
	if Graphics.effects:
		sparks = CPUParticles3D.new()
		sparks.amount = 18
		sparks.lifetime = 0.45
		sparks.position = Vector3(0.0, 1.05, -0.45 - 0.3 - BIT_LENGTH + 0.1)
		sparks.direction = Vector3(0.0, 0.4, 1.0)
		sparks.spread = 55.0
		sparks.initial_velocity_min = 1.5
		sparks.initial_velocity_max = 3.5
		sparks.gravity = Vector3(0.0, -6.0, 0.0)
		sparks.scale_amount_min = 0.5
		sparks.scale_amount_max = 1.0
		var q := QuadMesh.new()
		q.size = Vector2(0.025, 0.025)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_color = Color(1.0, 0.7, 0.3)
		q.material = m
		sparks.mesh = q
		node.add_child(sparks)
	return {"node": node, "bit": bit, "motor": motor, "sparks": sparks}


## Broken rock and crystal heaped beside an ore cart on a stretch of rail.
func _build_heap(at: Vector3) -> void:
	var stone := _mat(&"rock")
	for k in 9:
		var mi := MeshInstance3D.new()
		mi.mesh = _rock_mesh(k % 4)
		mi.material_override = stone
		var s := _rng.randf_range(0.18, 0.42)
		mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.8, s)),
			at + Vector3(_rng.randf_range(-0.6, 0.6), s * 0.3, _rng.randf_range(-0.5, 0.5)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
	_solid(self, Vector3(1.4, 0.6, 1.2), at + Vector3(0.0, 0.3, 0.0))
	# The rails, from the heap back toward the way in, and the cart on them.
	var iron := _mat(&"iron")
	var wood := _mat(&"wood")
	var rail_x := at.x + 1.6
	var z0 := at.z - 2.0
	var z1 := at.z + 6.0
	for side: float in [-0.35, 0.35]:
		_box(self, Vector3(0.06, 0.08, z1 - z0), Vector3(rail_x + side, 0.04, (z0 + z1) * 0.5), iron)
	var z := z0
	while z <= z1:
		_box(self, Vector3(1.0, 0.05, 0.16), Vector3(rail_x, 0.025, z), wood)
		z += 0.7
	var cart := Node3D.new()
	cart.position = Vector3(rail_x, 0.0, at.z + 0.6)
	add_child(cart)
	_box(cart, Vector3(0.9, 0.5, 1.2), Vector3(0.0, 0.5, 0.0), _mat(&"rust"))
	for wz: float in [-0.4, 0.4]:
		for wx: float in [-0.38, 0.38]:
			var wheel := _cyl(0.14, 0.06, 10, iron)
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(wx, 0.14, wz)
			cart.add_child(wheel)
	# Its load: ore and crystal standing out of the top.
	for k in 6:
		var mi := MeshInstance3D.new()
		mi.mesh = _rock_mesh(k % 4)
		mi.material_override = stone
		mi.scale = Vector3.ONE * _rng.randf_range(0.16, 0.24)
		mi.position = Vector3(_rng.randf_range(-0.28, 0.28), 0.78, _rng.randf_range(-0.4, 0.4))
		cart.add_child(mi)
	for k in 4:
		var gem := _octa(0.12, 0.34, _glow(Color(1.0, 0.72, 0.2) if k % 2 == 0 else RED, 2.0))
		gem.position = Vector3(_rng.randf_range(-0.3, 0.3), 0.88, _rng.randf_range(-0.4, 0.4))
		gem.rotation = Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5))
		cart.add_child(gem)
	_solid(cart, Vector3(0.9, 1.0, 1.2), Vector3(0.0, 0.5, 0.0))


## A shackled prisoner at work: the skeleton model with a pick in its right hand
## (on the hand bone, so it goes where the swing goes), an iron ball chained to
## its ankle on the floor beside it.
func _make_miner(cell: Dictionary) -> void:
	if cell.get("dead", false) or cell["prisoner"] != null:
		return
	var xf: Transform3D = cell["xf"]
	var decor := Node3D.new()
	decor.name = "Miner"
	var model: Node3D = SKELETON_MODEL.instantiate()
	model.transform = Transform3D(Basis.from_scale(Vector3(-MINER_SCALE, MINER_SCALE, -MINER_SCALE)), Vector3.ZERO)
	decor.add_child(model)
	add_child(decor)
	decor.transform = xf
	var sk_list := model.find_children("*", "Skeleton3D", true, false)
	if not sk_list.is_empty():
		var sk := sk_list[0] as Skeleton3D
		var hand := sk.find_bone("hand.R")
		var fore := sk.find_bone("forearm.R")
		if hand >= 0 and fore >= 0:
			# A drill for a hand (note 93): the hand shrunk into the wrist (no
			# clip scales it back) and the drill on the forearm, out from the
			# wrist, its bit turning (`_run_mine`).
			sk.set_bone_pose_scale(hand, Vector3.ONE * 0.02)
			var hold := BoneAttachment3D.new()
			hold.bone_name = "forearm.R"
			sk.add_child(hold)
			var weapons := preload("res://scripts/skeleton_sword.gd")
			var drill := MeshInstance3D.new()
			drill.mesh = weapons._mesh(&"drill")
			drill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			drill.position = Vector3(0.0, sk.get_bone_rest(hand).origin.length(), 0.0)
			hold.add_child(drill)
			var bit := MeshInstance3D.new()
			bit.mesh = weapons.drill_bit_mesh()
			bit.position = Vector3(0.0, weapons.DRILL_BIT_AT, 0.0)
			drill.add_child(bit)
			cell["bit"] = bit
	var ap := model.find_children("*", "AnimationPlayer", true, false)
	if not ap.is_empty():
		var anim := ap[0] as AnimationPlayer
		if anim.has_animation(&"idle"):
			anim.get_animation(&"idle").loop_mode = Animation.LOOP_LINEAR
			anim.play(&"idle")
		cell["anim"] = anim
	cell["next_swing"] = _time + _swing_rng.randf_range(0.2, 2.0)
	EYES.attach(decor)
	# Something to hit: struck at its work, it turns (`_miner_struck`).
	var hit := MinerHit.new()
	hit.name = "Hit"
	hit.room = self
	hit.cell = cell
	hit.collision_layer = 4
	hit.collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	hit.add_child(shape)
	decor.add_child(hit)
	# The ball and chain.
	if not cell.has("ball"):
		var ball := _sphere(0.13, _mat(&"iron"))
		ball.position = (cell["xf"] as Transform3D) * Vector3(0.45, 0.13, 0.35)
		add_child(ball)
		var chain := _cyl(0.012, 0.5, 4, _mat(&"iron"))
		var foot := (cell["xf"] as Transform3D) * Vector3(0.1, 0.05, 0.0)
		chain.position = (ball.position + foot) * 0.5
		chain.basis = Basis(Quaternion(Vector3.UP, (foot - ball.position).normalized()))
		chain.scale.y = ball.position.distance_to(foot) / 0.5
		add_child(chain)
		cell["ball"] = ball
	cell["prisoner"] = decor


func _run_mine(delta: float) -> void:
	# The drills turn with the generator, and shake, and throw sparks.
	for d in _drills:
		var bit: Node3D = d["bit"]
		bit.rotation.z += delta * 26.0 * _power
		var motor: Node3D = d["motor"]
		motor.position = Vector3(sin(_time * 53.0) * 0.006 * _power, 1.05 + sin(_time * 71.0) * 0.006 * _power, 0.0)
		var sparks: CPUParticles3D = d["sparks"]
		if sparks != null:
			var on := _power > 0.3
			if sparks.emitting != on:
				sparks.emitting = on
	# The miners swing at the rock in their own time (those still at work).
	for cell in _cells:
		if cell["prisoner"] == null or not cell.has("anim"):
			continue
		var bit = cell.get("bit")
		if bit != null and is_instance_valid(bit):
			(bit as Node3D).rotation.y += delta * 30.0
		if _time < float(cell["next_swing"]):
			continue
		var anim: AnimationPlayer = cell["anim"]
		var clip := &"attack_1" if _swing_rng.randf() < 0.6 else &"attack_2"
		if anim.has_animation(clip):
			anim.play(clip, 0.12, _swing_rng.randf_range(0.8, 1.0))
			anim.queue(&"idle")
		cell["next_swing"] = _time + _swing_rng.randf_range(1.1, 2.0)


## The miner drops its work and comes at the player with its pick. Returns the
## enemy that takes its place (null if it was not at work).
func _release_miner(cell: Dictionary) -> Node3D:
	if not is_inside_tree() or cell["prisoner"] == null:
		return null
	var decor: Node3D = cell["prisoner"]
	var xf := decor.global_transform if is_instance_valid(decor) else to_global_xf(cell)
	if is_instance_valid(decor):
		decor.queue_free()
	cell["prisoner"] = null
	cell.erase("anim")
	cell.erase("bit")
	cell["alive"] = true
	return _spawn_prisoner(cell, Transform3D(xf.basis.orthonormalized(), xf.origin), true, &"drill")


## --- Who turns on the player, and when (2026-10-10) ------------------------------
##
## Walking into the mine sets nothing off. The enforcers stroll about the court
## watching the miners (`_respawn_mine`: wanderers with the court in front of
## the face as their patch, leashed to the room) and fight only once they SEE
## the player, each on its own eyes. The miners keep working until either:
##   * both enforcers are down -- MINERS_TURN later, every one still at work
##     drops its work and comes for the player; or
##   * the player strikes one at its work (its `MinerHit` body on the damageable
##     layer): that one turns, taking the blow, and the rest keep working.

const MINERS_TURN := 2.5


## A working miner's body as far as blows are concerned: on the damageable layer
## (3) only, so it is cut, stabbed and blasted like any enemy, but walked through
## by nothing and left out of the navmesh.
class MinerHit extends StaticBody3D:
	var room: Node
	var cell: Dictionary

	func take_damage(amount: float, from_direction := Vector3.ZERO) -> void:
		if room != null and is_instance_valid(room):
			room.call("_miner_struck", cell, amount, from_direction)


func _miner_struck(cell: Dictionary, amount: float, from_direction: Vector3) -> void:
	var e := _release_miner(cell)
	if e != null and is_instance_valid(e) and e.has_method("take_damage"):
		e.call("take_damage", amount, from_direction)


func _release_all_miners() -> void:
	if not is_inside_tree():
		return
	var delay := 0.0
	for cell in _cells:
		if cell["prisoner"] != null:
			get_tree().create_timer(delay).timeout.connect(_release_miner.bind(cell))
			delay += 0.15


## After a death or a load: the enforcers back on their posts unless every one
## was destroyed; every miner not yet killed back at work.
func _respawn_mine() -> void:
	for w in _enforcers:
		if is_instance_valid(w):
			w.free()
	_enforcers.clear()
	for e in _freed:
		if is_instance_valid(e):
			e.free()
	_freed.clear()
	if not enforcers_down and maze != null:
		var scene: PackedScene = maze.get("enemy_scene")
		for post: Vector2 in MINE_POSTS:
			var w: Node3D = scene.instantiate()
			w.set_script(ENFORCER_SCRIPT)
			var at := to_global(Vector3(post.x, 0.3, post.y))
			var face := to_global(Vector3(post.x, 0.3, post.y - 1.0)) - at
			face.y = 0.0
			w.transform = maze.global_transform.affine_inverse() * Transform3D(Basis.looking_at(face.normalized(), Vector3.UP), at)
			# Strolling about in front of the face, watching the work; on its own
			# eyes, not a room-wide alarm, and leashed to the room.
			w.set("wanders", true)
			w.set("wander_spots", _watch_spots())
			w.set("wander_tolerance", 2.4)
			# The room is its zone: it does not follow the player out of it.
			w.set("aggro_box_extents", Vector3(_block, 4.0, _block))
			w.set("aggro_box_origin", global_position)
			maze.call("adopt_enemy", w)
			w.set("aggro_range", 22.0)
			w.connect("died", _on_enforcer_died)
			_enforcers.append(w)
	for cell in _cells:
		cell["alive"] = false
		if not cell.get("dead", false):
			_make_miner(cell)
	prisoners_down = true
	for cell in _cells:
		if not cell.get("dead", false):
			prisoners_down = false
	if looted:
		_mine_off_now()


## Where the enforcers stroll: a loose grid over the court between the miners
## and the way in, clear of the generator, the drills and the ore heap.
func _watch_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var back := -_span + ROCK_IN + ROCK_R * 0.81 + 2.4
	var z := back
	while z <= back + 6.0:
		var x := -_span + 2.0
		while x <= _span - 2.0:
			var p := Vector3(x, 0.0, z)
			var clear := p.distance_to(_gen.position) > 2.6 if _gen != null else true
			for d in _drills:
				if p.distance_to((d["node"] as Node3D).position) < 1.8:
					clear = false
			if p.distance_to(Vector3(_span - 2.6, 0.0, -1.0)) < 2.6:
				clear = false
			if clear:
				spots.append(to_global(p))
			x += 2.0
		z += 2.0
	return spots


## The shard already taken: the generator dead and the drills still.
func _mine_off_now() -> void:
	powered_off = true
	_power = 0.0
	if _crystal != null and is_instance_valid(_crystal):
		_crystal.queue_free()
	_crystal = null
	if _gen_light != null:
		_gen_light.light_energy = 0.0


## The doors' collision comes on once the navmesh has been baked without it.
func _arm_doors() -> void:
	# A containment block's front gates never open.
	if powered_off and not is_containment():
		return
	for cell in _cells:
		var db: StaticBody3D = cell["door_body"]
		(db.get_child(0) as CollisionShape3D).disabled = false


# --- Running -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if is_containment():
		_run_walkers(delta)
	# Co-op: whoever is nearest, or in a scene with it (coop.gd `user_for`).
	_player = Coop.user_for(self, _player)
	if _player == null:
		return
	if kind != &"prison" and kind != &"mine":
		return
	_run_generator(delta)
	if kind == &"mine":
		_run_mine(delta)
		# Walking in sets nothing off, and nothing is announced (2026-10-15, the
		# user: no commentary on walking into a room). The enforcers fight when
		# they see the player (their own eyes).
		if not _alarmed and _player_inside(ALARM_IN):
			_alarmed = true
	elif not _alarmed and not enforcers_down and _player_inside(ALARM_IN):
		_raise_alarm()
	_update_focus()


func _player_inside(margin: float) -> bool:
	if _player.get("_dead") == true:
		return false
	var p := to_local(_player.global_position)
	var inner := _block - margin
	return absf(p.x) < inner and absf(p.z) < inner and p.y > -1.5 and p.y < 6.0


func _run_generator(delta: float) -> void:
	if _gen == null:
		return
	# The machine winds down over a couple of seconds once the crystal is out.
	_power = move_toward(_power, 0.0 if powered_off else 1.0, delta * 0.5)
	for i in _pistons.size():
		_pistons[i].position.y = 1.5 + sin(_time * 9.0 * _power + float(i) * PI) * 0.12 * _power
	if _flywheel != null:
		_flywheel.rotation.x += delta * 7.0 * _power
	# The beams stutter out as the machine winds down.
	if not _beams.is_empty():
		var beam_power := 1.0 if not powered_off else _power * _power * _power * randf_range(0.2, 1.0)
		for b in _beams:
			b.visible = beam_power > 0.002
			b.set_instance_shader_parameter(&"power", beam_power)
	if not powered_off and _crystal != null:
		_crystal.rotation.y += delta * 0.8
		_crystal.position.y = _crystal_y + sin(_time * 1.7) * 0.04
		var pulse := 0.5 + 0.5 * sin(_time * 3.1)
		_crystal_mat.emission_energy_multiplier = 3.2 + pulse * 1.8
		_gen_light.light_energy = 2.5 + pulse * 1.0


func _raise_alarm() -> void:
	# No title card on walking in (2026-10-15): the enforcers simply turn.
	_alarmed = true
	for w in _enforcers:
		if is_instance_valid(w) and w.has_method("alert"):
			w.call("alert")


func _update_focus() -> void:
	_focus = false
	if not enforcers_down or powered_off or _crystal == null or (kind == &"mine" and not prisoners_down):
		_prompt.visible = false
		return
	var blocked: bool = _player.get("in_cutscene") == true or _player.get("_dead") == true \
		or _player.get("ui_open") == true
	if not blocked:
		var to := _crystal.global_position - _player.global_position
		if Vector2(to.x, to.z).length() <= 2.8 and Interact.looked_at(_crystal, 3.6, 0.12, [], _player):
			_focus = true
	_prompt.visible = _focus
	_prompt.player = _player
	if _focus:
		_prompt.global_position = _crystal.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not _focus or not Interact.pressed(event, _player):
		return
	get_viewport().set_input_as_handled()
	_cut_power()


## The crystal comes out: it flies to the player, the generator dies, every
## lock in the block lets go and the prisoners come out.
func _cut_power() -> void:
	if powered_off:
		return
	powered_off = true
	_focus = false
	_prompt.visible = false
	if is_containment():
		# The type is loose from this moment -- a death before the doors are up
		# still lets it out. The ones walking out are the room's own show.
		walked_out = 0
		for cell in _cells:
			if is_instance_valid(cell.get("caged")):
				walked_out += 1
		if maze != null and maze.has_method("release_hand"):
			maze.call("release_hand", hand, walked_out)
	var at := _crystal.global_position
	_crystal.top_level = true
	_crystal.global_position = at
	var cam := _player.get("camera") as Camera3D
	var to := cam.global_position - cam.global_basis.z * 0.5 - Vector3(0.0, 0.35, 0.0) if cam != null \
		else _player.global_position + Vector3(0.0, 1.2, 0.0)
	var fly := create_tween()
	fly.tween_property(_crystal, "global_position", to, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fly.parallel().tween_property(_crystal, "scale", Vector3.ONE * 0.3, 0.5)
	fly.tween_callback(_crystal.queue_free)
	if kind == &"mine":
		# The generator ran on the room's shard: it is the prize.
		if _player.has_method("add_item"):
			_player.call("add_item", shard, 1)
		looted = true
		var light_out := create_tween()
		for k in 4:
			light_out.tween_property(_gen_light, "light_energy", 0.4 if k % 2 == 0 else 3.0, 0.08)
		light_out.tween_property(_gen_light, "light_energy", 0.0, 0.9)
		var hud := _hud()
		if hud != null and hud.has_method("announce"):
			hud.announce("THE DRILLS FALL SILENT", "The shard is yours.")
		return
	if _player.has_method("add_item"):
		_player.call("add_item", &"red_crystal", 1)
		# No chest in the cells any more: the room's shard was set in the
		# generator's cradle under the crystal and comes out with it.
		if _reward == null:
			_player.call("add_item", shard, 1)
			looted = true
	# The machine gutters out.
	var light := create_tween()
	for k in 4:
		light.tween_property(_gen_light, "light_energy", 0.4 if k % 2 == 0 else 3.0, 0.08)
	light.tween_property(_gen_light, "light_energy", 0.0, 0.9)
	var lamps := create_tween()
	for k in 3:
		lamps.tween_property(_lamp_mat, "emission_energy_multiplier", 0.2 if k % 2 == 0 else 3.0, 0.1)
	lamps.tween_property(_lamp_mat, "emission_energy_multiplier", 0.0, 0.6)
	get_tree().create_timer(1.0).timeout.connect(
		_open_back_doors if is_containment() else _open_cells)


func _open_cells() -> void:
	if not is_inside_tree():
		return
	var hud := _hud()
	if hud != null and hud.has_method("announce"):
		hud.announce("THE LOCKS FAIL", "The prisoners are loose.")
	var delay := 0.0
	for cell in _cells:
		var hinge: Node3D = cell["door"]
		var swing := create_tween()
		swing.tween_interval(delay)
		swing.tween_property(hinge, "rotation:y", hinge.rotation.y + _open_angle(cell), 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# The domed prison's gates are pairs of leaves.
		if cell.has("door2"):
			var second: Node3D = cell["door2"]
			swing.parallel().tween_property(second, "rotation:y", second.rotation.y + float(cell["open2"]), 0.55) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		(cell["door_body"].get_child(0) as CollisionShape3D).set_deferred("disabled", true)
		if cell["prisoner"] != null:
			get_tree().create_timer(delay + 0.35).timeout.connect(_release.bind(cell))
		delay += 0.12
	if _reward != null and is_instance_valid(_reward):
		_reward.set("locked", false)


## Containment: the front gates stay shut and the back doors grind up, one after
## another along the block, and each prisoner turns and walks out through its own.
func _open_back_doors() -> void:
	if not is_inside_tree():
		return
	var hud := _hud()
	if hud != null and hud.has_method("announce"):
		hud.announce("THE BACK DOORS GRIND OPEN",
			"The %s hands are loose in the maze." % String(HAND_NAMES.get(hand, "")).to_lower())
	var delay := 0.0
	for cell in _cells:
		_lift_back_door(cell, delay, false)
		if is_instance_valid(cell.get("caged")):
			get_tree().create_timer(delay + 1.1).timeout.connect(_walk_out.bind(cell))
		delay += 0.15
	if _back_lamp_mat != null:
		var lamp := create_tween()
		lamp.tween_interval(0.4)
		lamp.tween_property(_back_lamp_mat, "emission", GREEN, 0.3)


func _lift_back_door(cell: Dictionary, delay: float, now: bool) -> void:
	var slab: Node3D = cell.get("back_door")
	if slab == null:
		return
	if cell.get("lifted", false):
		return
	cell["lifted"] = true
	var up := slab.position + Vector3(0.0, BACK_LIFT, 0.0)
	if now:
		slab.position = up
		return
	var lift := create_tween()
	lift.tween_interval(delay)
	# A jolt as the catch lets go, then the long haul up the rails.
	lift.tween_property(slab, "position", slab.position + Vector3(0.0, 0.06, 0.0), 0.12)
	lift.tween_property(slab, "position", up, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var gear: Node3D = cell.get("gear")
	if gear != null:
		# About its own axle (its local Y, out of the wall).
		var rest := gear.basis
		var spin := create_tween()
		spin.tween_interval(delay + 0.12)
		spin.tween_method(func(a: float) -> void: gear.basis = rest * Basis(Vector3.UP, a), 0.0, -TAU * 2.5, 1.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _walk_out(cell: Dictionary) -> void:
	if not is_inside_tree() or not is_instance_valid(cell.get("caged")):
		return
	cell["walking"] = true
	cell["walk_until"] = _time + 7.0


## Walks each let-out prisoner to its back door (it stays caged: blind, deaf,
## unhurt, walked by `cage_walk`), and takes it in through the door when there.
func _run_walkers(_delta: float) -> void:
	for cell in _cells:
		if not cell.get("walking", false):
			continue
		var e = cell.get("caged")
		if not is_instance_valid(e):
			cell["walking"] = false
			continue
		if not cell.has("back"):
			_vanish(cell, e)
			continue
		var to: Vector3 = to_global(cell["back"]) - (e as Node3D).global_position
		to.y = 0.0
		if to.length() < 0.35 or _time >= float(cell["walk_until"]):
			_vanish(cell, e)
		else:
			e.set("cage_walk", to.normalized() * WALK_OUT)


## Off the floor and into the dark behind the door, then gone.
func _vanish(cell: Dictionary, e: Node3D) -> void:
	cell["walking"] = false
	cell["caged"] = null
	cell["held"] = false
	_freed.erase(e)
	e.set("cage_walk", Vector3.ZERO)
	e.set_physics_process(false)
	(e as CollisionObject3D).collision_layer = 0
	(e as CollisionObject3D).collision_mask = 0
	var into: Vector3 = to_global(cell.get("into", cell.get("back", to_local(e.global_position))))
	into.y = e.global_position.y
	var go := create_tween()
	go.tween_property(e, "global_position", into, 1.1)
	go.tween_callback(e.queue_free)


## A real skeleton of the block's type, locked in its cell.
func _cage_prisoner(cell: Dictionary) -> Node3D:
	if maze == null or not maze.has_method("make_skeleton"):
		return null
	var e: Node3D = maze.call("make_skeleton", hand)
	if e == null:
		return null
	e.set("caged", true)
	e.set("wanders", false)
	var xf := to_global_xf(cell)
	e.transform = maze.global_transform.affine_inverse() * Transform3D(xf.basis.orthonormalized(),
		xf.origin + Vector3(0.0, 0.3, 0.0))
	maze.call("adopt_enemy", e)
	e.set("aggro_range", 0.5)
	cell["caged"] = e
	_freed.append(e)
	return e


## Out into the aisle. The door runs along +X from its hinge, and a turn of a
## about Y takes +X to (cos a, 0, -sin a): a back-row door (the aisle at +Z)
## turns negative, a front-row door (the aisle at -Z) positive.
static func _open_angle(cell: Dictionary) -> float:
	if cell.has("open"):
		return float(cell["open"])
	return -1.75 if float(cell["row"]) < 0.0 else 1.75


## Swaps a cell's standing figure for a real skeleton, which comes for the player.
func _release(cell: Dictionary) -> void:
	if not is_inside_tree():
		return
	var decor: Node3D = cell["prisoner"]
	var xf := decor.global_transform if is_instance_valid(decor) else to_global_xf(cell)
	if is_instance_valid(decor):
		decor.queue_free()
	cell["prisoner"] = null
	cell["alive"] = true
	_spawn_prisoner(cell, xf, true)


func to_global_xf(cell: Dictionary) -> Transform3D:
	if cell.has("xf"):
		return global_transform * (cell["xf"] as Transform3D)
	var row := float(cell["row"])
	var c: Vector3 = cell["centre"]
	var local := Transform3D(Basis(Vector3.UP, PI if row < 0.0 else 0.0), Vector3(c.x, 0.0, row * (FRONT + 0.7)))
	return global_transform * local


## A real enemy in a decor prisoner's place. Prisoners fight bare-handed
## (`weapon` empty); a miner is a drill skeleton (prosthetic.gd, note 93).
func _spawn_prisoner(cell: Dictionary, xf: Transform3D, alerted: bool, weapon := &"") -> Node3D:
	var scene: PackedScene = maze.get("enemy_scene") if maze != null else null
	if scene == null:
		return null
	var e: Node3D
	if weapon == &"drill":
		e = preload("res://scripts/prosthetic.gd").make(scene, &"drill")
	else:
		e = scene.instantiate()
		e.set("armed", weapon != &"")
		if weapon != &"":
			e.set("weapon", weapon)
	# The decor stands -Z out; an enemy faces -Z too.
	e.transform = maze.global_transform.affine_inverse() * Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3(0.0, 0.3, 0.0))
	e.set("wanders", false)
	maze.call("adopt_enemy", e)
	_freed.append(e)
	e.connect("died", _on_prisoner_died.bind(cell))
	if alerted and e.has_method("alert"):
		e.call_deferred("alert")
	return e


func _on_prisoner_died(cell: Dictionary) -> void:
	cell["alive"] = false
	cell["dead"] = true
	for c in _cells:
		# (A miner still at work, not yet let loose, is not down either.)
		if c["alive"] or (kind == &"mine" and c["prisoner"] != null):
			return
	prisoners_down = true
	var hud := _hud()
	if hud != null and hud.has_method("announce"):
		if kind == &"mine":
			hud.announce("THE MINERS ARE DOWN", "Take the shard from the generator." if enforcers_down
				else "The enforcers still stand.")
		else:
			hud.announce("THE BLOCK FALLS QUIET", "")


func _on_enforcer_died() -> void:
	for w in _enforcers:
		if is_instance_valid(w) and w.get("_dying") != true:
			return
	enforcers_down = true
	var hud := _hud()
	if hud != null and hud.has_method("announce"):
		if kind == &"mine":
			hud.announce("THE ENFORCERS ARE DOWN", "Take the shard from the generator." if prisoners_down
				else "The miners turn their drills on you...")
		else:
			hud.announce("THE ENFORCERS ARE DOWN", "The generator still holds the cells.")
	if kind == &"mine":
		# A moment later, with nobody standing over them, the miners turn.
		get_tree().create_timer(MINERS_TURN).timeout.connect(_release_all_miners)


func _on_reward_taken() -> void:
	looted = true


# --- Who is in the room ---------------------------------------------------------------

## After every repopulate (maze.gd `_populate` frees everything it spawned,
## these included) and after a load: puts back whoever should be here.
func on_world_reset() -> void:
	_alarmed = false
	if kind == &"prison":
		_respawn_prison()
	elif kind == &"mine":
		_respawn_mine()
	elif is_mimic and not looted:
		_place_mimic()
	elif not is_mimic and _reward == null:
		_place_chest()


func _respawn_prison() -> void:
	for w in _enforcers:
		if is_instance_valid(w):
			w.free()
	_enforcers.clear()
	for e in _freed:
		if is_instance_valid(e):
			e.free()
	_freed.clear()
	if not enforcers_down and maze != null:
		var scene: PackedScene = maze.get("enemy_scene")
		for post: Vector3 in POSTS:
			var w: Node3D = scene.instantiate()
			w.set_script(ENFORCER_SCRIPT)
			# POSTS are (x, z, the row watched).
			var at := to_global(Vector3(post.x, 0.3, post.y))
			# Facing the row it watches: -Z of an enforcer is its front.
			var watch := to_global(Vector3(post.x, 0.3, post.y + post.z))
			var face := (watch - at)
			face.y = 0.0
			var basis := Basis.looking_at(face.normalized(), Vector3.UP)
			w.transform = maze.global_transform.affine_inverse() * Transform3D(basis, at)
			w.set("wanders", false)
			w.set("aggro_box_extents", Vector3(_block, 4.0, _block))
			w.set("aggro_box_origin", global_position)
			maze.call("adopt_enemy", w)
			w.set("aggro_range", 26.0)
			w.connect("died", _on_enforcer_died)
			_enforcers.append(w)
	if is_containment():
		# Locked up again, unless they were let out.
		for cell in _cells:
			cell["walking"] = false
			cell["caged"] = null
			if not powered_off and cell.get("held", false):
				_cage_prisoner(cell)
		return
	if powered_off and not prisoners_down:
		for cell in _cells:
			if cell["alive"]:
				_spawn_prisoner(cell, to_global_xf(cell), false)


func _place_chest() -> void:
	var c: Node3D = CHEST_SCENE.instantiate()
	c.set("shard", shard)
	c.set("coins", _rng.randi_range(25, 60))
	c.set("min_amount", 1)
	c.set("max_amount", 3)
	c.set("opened_title", "SHARD RECOVERED")
	add_child(c)
	c.position = Vector3(0.0, 0.14, 0.0)
	c.connect("opened", _on_reward_taken.unbind(1))
	_reward = c


func _place_mimic() -> void:
	if is_instance_valid(_reward):
		_reward.free()
	var m: Node3D = MIMIC_SCENE.instantiate()
	m.set("shard", shard)
	maze.add_child(m)
	m.global_position = to_global(Vector3(0.0, 0.14, 0.0))
	m.rotation.y = global_rotation.y
	m.connect("died", _on_reward_taken)
	if maze.has_method("register_mimic"):
		maze.call("register_mimic", m)
	_reward = m


# --- Saving (save_system.gd, via maze.gd) -----------------------------------------

func save_state() -> Dictionary:
	var alive: Array[int] = []
	var dead: Array[int] = []
	for i in _cells.size():
		if _cells[i]["alive"]:
			alive.append(i)
		if _cells[i].get("dead", false):
			dead.append(i)
	return {"kind": kind, "looted": looted, "enforcers_down": enforcers_down,
		"powered_off": powered_off, "prisoners_down": prisoners_down, "freed_alive": alive,
		"miners_dead": dead}


## A loaded game: the room as it was left, straight into its finished look.
func restore_state(data: Dictionary) -> void:
	if StringName(data.get("kind", kind)) != kind:
		return
	looted = bool(data.get("looted", false))
	if kind == &"prison":
		# Saves from before the rename (2026-10-15) call them wardens.
		enforcers_down = bool(data.get("enforcers_down", data.get("wardens_down", false)))
		prisoners_down = bool(data.get("prisoners_down", false))
		if bool(data.get("powered_off", false)):
			_power_off_now(data.get("freed_alive", []))
			# Saved before the cells' chest was removed, with the power cut and
			# the chest still shut: the shard is owed. Given after the player
			# is restored (maze restores them after the world).
			if not looted and _reward == null:
				looted = true
				_give_owed_shard.call_deferred()
	elif kind == &"mine":
		# Saves from before the rename (2026-10-15) call them wardens.
		enforcers_down = bool(data.get("enforcers_down", data.get("wardens_down", false)))
		prisoners_down = bool(data.get("prisoners_down", false))
		for i: int in data.get("miners_dead", []):
			if i < _cells.size():
				_cells[i]["dead"] = true
		if looted:
			_mine_off_now()
	if looted and _reward != null and is_instance_valid(_reward):
		if is_mimic:
			_reward.free()
			_reward = null
		else:
			_reward.set("opened_already", true)
			_reward.set("locked", false)
			var lid := _reward.get_node_or_null("LidPivot") as Node3D
			if lid != null:
				lid.rotation.x = deg_to_rad(-105.0)
	on_world_reset()


func _give_owed_shard() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("add_item"):
		p.call("add_item", shard, 1)


## The generator already dead, doors open, the crystal gone, the prisoners out.
func _power_off_now(alive: Array) -> void:
	powered_off = true
	_power = 0.0
	if _crystal != null and is_instance_valid(_crystal):
		_crystal.queue_free()
	_crystal = null
	_gen_light.light_energy = 0.0
	_lamp_mat.emission_energy_multiplier = 0.0
	if is_containment():
		# The front gates still shut; the back doors up, their lamps green, the
		# cells empty.
		if _back_lamp_mat != null:
			_back_lamp_mat.emission = GREEN
		for cell in _cells:
			_lift_back_door(cell, 0.0, true)
			cell["held"] = false
		return
	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		(cell["door"] as Node3D).rotation.y += _open_angle(cell)
		if cell.has("door2"):
			(cell["door2"] as Node3D).rotation.y += float(cell["open2"])
		(cell["door_body"].get_child(0) as CollisionShape3D).disabled = true
		if cell["prisoner"] != null and is_instance_valid(cell["prisoner"]):
			(cell["prisoner"] as Node3D).queue_free()
		cell["prisoner"] = null
		cell["alive"] = alive.has(i) and not prisoners_down
	if _reward != null and is_instance_valid(_reward):
		_reward.set("locked", false)


# --- Helpers -----------------------------------------------------------------------

func _hud() -> Node:
	return Coop.hud(_player)


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


## Solid to everyone (1) and to sight (2).
func _solid(parent: Node3D, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	parent.add_child(body)
	_add_shape(body, size, at)
	return body


func _add_shape(body: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	body.add_child(cs)


func _cyl(radius: float, height: float, segments: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = maxi(segments, 4)
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _sphere(radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 5
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _octa(width: float, height: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = width * 0.5
	s.height = height
	s.radial_segments = 4
	s.rings = 2
	mi.mesh = s
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.6)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.35
	return m


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"stone":
			# The puzzle rooms' plain grey stone: the level's arch stone renders
			# black on plain meshes (it is lit by MultiMesh instance colours).
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.normal_scale = 1.3
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.albedo_color = Color(0.21, 0.2, 0.195)
			m.roughness = 0.9
			m.emission_enabled = true
			m.emission = Color(0.03, 0.027, 0.027)
		&"rock":
			# The mine's raw rock: the stone's normal map, harder, on a darker and
			# rougher face than the dressed stone.
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.normal_scale = 2.2
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.7, 0.7, 0.7)
			m.albedo_color = Color(0.13, 0.12, 0.115)
			m.roughness = 1.0
			m.emission_enabled = true
			m.emission = Color(0.02, 0.018, 0.018)
		&"dark":
			m.albedo_color = Color(0.08, 0.075, 0.075)
			m.roughness = 0.9
		&"iron":
			m.albedo_color = Color(0.2, 0.19, 0.19)
			m.metallic = 0.5
			m.roughness = 0.55
		&"rust":
			m.albedo_color = Color(0.36, 0.25, 0.17)
			m.metallic = 0.35
			m.roughness = 0.8
		&"brass":
			m.albedo_color = Color(0.5, 0.37, 0.15)
			m.metallic = 0.6
			m.roughness = 0.45
		&"wood":
			m.albedo_texture = load("res://textures/wood_door_albedo.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.2, 1.2, 1.2)
			m.albedo_color = Color(0.42, 0.34, 0.27)
			m.roughness = 0.9
		&"straw":
			m.albedo_color = Color(0.29, 0.22, 0.1)
			m.roughness = 1.0
		&"bone":
			m.albedo_color = Color(0.48, 0.45, 0.38)
			m.roughness = 0.9
		&"void":
			# The dark beyond a back door: no light reaches it.
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.0, 0.0, 0.0)
	_mats[key] = m
	return m
