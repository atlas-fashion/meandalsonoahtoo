extends Node3D

## The morgue (2026-10-08; rebuilt 2026-10-15): no longer a cloister but one
## enclosed hall -- the room's whole block built as vaulted brick cells with no
## arches between them (module_level `_make_morgue_hall`, brick_level `hall`),
## so the only arches are its doorways and the vaults are its roof. Square
## brick piers where four vaults meet, pilasters along the walls with a torch
## on each, catacomb burial walls (Tripo "wall_loculi": the corridor brick, six
## shrouded bodies to a wall) between the pilasters, Tripo mortuary slabs each
## with a shrouded body in the bays, old coffins in the corners, broken
## skeletons on the floor -- and, at the back, facing the way in, the royal
## standing sarcophagus that held the Remnant before it was a ghost.
##
## The Remnant guards it. With the crosshair on the sarcophagus, E ("Open")
## starts a scene the player does not survive: the player walks up and pulls at
## the lid; it gives a hand's breadth; the whole room goes ice blue in an
## instant; the view turns -- the Remnant is right behind them -- it rears up and
## brings its arms down, and the view is crushed into the floor and cut to
## black. The player dies (`player.kill_in_scene`) and gets up at their anchor
## (player.gd `_begin_wake`); the world resets with them, and so does this room.
##
## Built by maze.gd (`build`) under the navigation region, before the bake, so
## everything that stands here is walked round.

const SKELETON := preload("res://models/ossuary_skeleton_rigged.glb")
const SKULL_MODEL := "res://models/skull_worn_ready.glb"
const WOOD_TEXTURE := "res://textures/wood_door_albedo.png"
const WoodDoor := preload("res://scripts/wood_door.gd")
const Torch := preload("res://scripts/torch.gd")

## What a broken body may have lost. Scaling a bone to nothing collapses the
## mesh weighted to it -- and everything hanging from it -- into its joint.
const LIMBS := [&"head", &"upper_arm.L", &"upper_arm.R", &"forearm.L", &"forearm.R",
	&"thigh.L", &"thigh.R", &"shin.L", &"shin.R"]
## The enemies' skeleton is the model at 0.94; the Remnant is it at 1.75.
const BODY_SCALE := 0.94
const REMNANT_SCALE := 1.75

## The royal sarcophagus: an anthropoid outline (narrow at the feet, widest at
## the shoulders) tall enough for the Remnant as it was, ~3.3 m.
const ROYAL_HEIGHT := 3.9
const ROYAL_FOOT := 0.62
const ROYAL_SHOULDER := 0.98
const ROYAL_HEAD := 0.7
const ROYAL_DEPTH := 1.1
const DAIS := Vector3(3.6, 0.32, 2.6)
## Ordinary standing coffins.
const COFFIN_HEIGHT := 2.05
const COFFIN_FOOT := 0.3
const COFFIN_SHOULDER := 0.46
const COFFIN_HEAD := 0.34
const COFFIN_DEPTH := 0.62
const SLAB := Vector3(1.0, 0.86, 2.2)

## The enclosed hall (2026-10-15). Kit pieces measured off the build
## (build_brick_kit.py): the burial wall, and the pier face.
const BrickLevel := preload("res://scripts/brick_level.gd")
const LOCULI_LEN := 3.9
const LOCULI_HEIGHT := 2.82
const LOCULI_DEPTH := 0.86
## Bodies in one burial wall: three rows of two.
const LOCULI_BODIES := 6
const PIER_HALF := 1.1
## Up past the vault crown (5.1 m), under the lid.
const PIER_TOP := 7.8
## How far a pilaster stands out in front of the burial walls.
const PILASTER_PROUD := 0.25
## Skeletons on the floor.
const FLOOR_DEAD := 14
const TORCH_HEIGHT := 2.6
const TORCH_BOOST := 1.2
const TORCH_ENERGY := 1.3
## The level's chunks draw to maze `module_view_range` (70 m).
const VIEW_RANGE := 75.0

## Where the player can open the royal sarcophagus from (horizontal, from its
## front), and where the scene stands them.
const REACH := 3.6
const STAND_OFF := 2.0
## How far behind the player the Remnant appears.
const BEHIND := 3.4

var built
var room: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _royal: Node3D
var _royal_lid: Node3D
var _prompt: Interact.Prompt
var _player: Node3D
var _near := false
var _busy := false
## [light, its own colour] for the room's lights the cold reaches.
var _cold_lights: Array = []
var _bars: CanvasLayer
var _corpse_count := 0
var _missing_count := 0

static var _mats := {}


static func build(holder: Node3D, level, room_: Dictionary) -> Node3D:
	var m := Node3D.new()
	m.set_script(load("res://scripts/morgue.gd"))
	m.name = "Morgue"
	m.set("built", level)
	m.set("room", room_)
	holder.add_child(m)
	m.call("_dress")
	return m


# --- Building ---------------------------------------------------------------------

func _dress() -> void:
	var centre: Vector3 = built.room_world(room)
	# The local frame: origin the middle of the block, +Z toward the way in, so
	# the back of the hall -- where the royal sarcophagus stands -- is -Z.
	var out := Vector3(0.0, 0.0, 1.0)
	var doors: Array = built.room_doors(room)
	if not doors.is_empty():
		var step: Vector2i = doors[0]["outward"]
		out = Vector3(float(step.x), 0.0, float(step.y))
	global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), centre)
	_rng.seed = hash(room["centre"]) ^ 0x6d6f7267
	var cell: float = built.cell_size
	var h: int = room["half"]
	var ring := float(h) * cell
	# The hall's walls (brick_level.gd: every closed side of a ring cell).
	var wall := ring + BrickLevel.WALL_FACE
	var kit_loculi: Mesh = BrickLevel.standalone("wall_loculi")
	var loc_depth := LOCULI_DEPTH if kit_loculi != null else 0.0
	# Pilasters stand proud of the burial walls.
	var pilaster_in := wall - loc_depth - PILASTER_PROUD

	# Ring cells in the local frame: which are doorways, which are corners.
	var entrances := {}
	for way in room["entrances"]:
		entrances[way["cell"]] = true
	var ring_cells: Array = []
	for dz in range(-h, h + 1):
		for dx in range(-h, h + 1):
			if maxi(absi(dx), absi(dz)) != h:
				continue
			var p: Vector2i = room["centre"] + Vector2i(dx, dz)
			var local := to_local(built.to_world(p))
			ring_cells.append({"pos": p, "at": Vector3(local.x, 0.0, local.z),
				"entrance": entrances.has(p), "corner": absi(dx) == h and absi(dz) == h})

	_build_piers(h, cell, pilaster_in)
	_hang_torches(h, cell, pilaster_in)

	# The royal sarcophagus on its dais against the back wall, facing the way in.
	var back := -(wall - loc_depth - 0.15 - DAIS.z * 0.5)
	_solid_box(Vector3(0.0, DAIS.y * 0.5, back), DAIS, _mat(&"dais"))
	_royal = _coffin(Vector3(0.0, DAIS.y, back), 0.0, true, "closed")
	_royal.name = "RoyalSarcophagus"
	_prompt = Interact.prompt("E   Open", Vector3(0.0, 1.6, ROYAL_DEPTH * 0.6))
	_royal.add_child(_prompt)
	# The body it held, standing in the dark behind the lid: the Remnant as it
	# was, crowned. Only seen once the lid is off.
	_royal_body(Vector3(0.0, DAIS.y + 0.05, back - 0.06))

	# Burial niches along every wall but the doorways' and the corners'.
	var walls_lined := 0
	for rc in ring_cells:
		if rc["corner"] or rc["entrance"] or kit_loculi == null:
			continue
		var at: Vector3 = rc["at"]
		_loculi(at + _into_wall(at) * (BrickLevel.WALL_FACE - 0.02), _into_wall(at), kit_loculi)
		walls_lined += 1

	# Slabs, each with a shrouded body on it: a pair to each bay inside the
	# ring, either side of the middle aisle. The ring is the walk along the
	# burial walls and stays clear: slabs there left gaps under a metre at
	# their corners, which the navmesh (radius 0.5) closes, and they cut the
	# corner doorways off from the hall (measured).
	var slab_mesh: Mesh = BrickLevel.standalone("morgue_slab")
	var taken: Array[Vector3] = []
	var slabs := 0
	for dz in range(-h + 1, h):
		for dx in range(-h + 1, h):
			var p: Vector2i = room["centre"] + Vector2i(dx, dz)
			var local := to_local(built.to_world(p))
			var at := Vector3(local.x, 0.0, local.z)
			# The middle column is the aisle from the way in to the sarcophagus.
			if absf(at.x) < 1.0:
				continue
			for s: float in [-1.0, 1.0]:
				var q := at + Vector3(s * 0.85, 0.0, _rng.randf_range(-0.25, 0.25))
				_slab(q, _rng.randf_range(-0.06, 0.06) + (PI if _rng.randf() < 0.5 else 0.0), slab_mesh)
				taken.append(q)
				slabs += 1

	# Old coffins stood in the corners, against both walls.
	var coffins := 0
	for rc in ring_cells:
		if not rc["corner"] or rc["entrance"]:
			continue
		var at: Vector3 = rc["at"]
		var sx := signf(at.x)
		var sz := signf(at.z)
		for k in 2:
			var along := float(k) * 0.85 - 0.6
			_coffin(Vector3(sx * (wall - 0.4), 0.0, at.z - sz * along), -sx * PI * 0.5,
				false, ["closed", "ajar", "open_body", "fallen"][_rng.randi_range(0, 3)])
			_coffin(Vector3(at.x - sx * along, 0.0, sz * (wall - 0.4)), 0.0 if sz < 0.0 else PI,
				false, ["closed", "ajar", "open", "closed"][_rng.randi_range(0, 3)])
			coffins += 2

	# The older dead on the floor: broken skeletons in the open, clear of the
	# slabs, the piers, the aisle and the dais.
	var placed: Array[Vector3] = []
	var tries := 0
	var reach := pilaster_in - 1.2
	while placed.size() < FLOOR_DEAD and tries < 600:
		tries += 1
		var p := Vector3(_rng.randf_range(-reach, reach), 0.0, _rng.randf_range(-reach, reach))
		if absf(p.x) < 1.6 and p.z > back + 2.0:
			continue
		if _near_pier(p, h, cell, PIER_HALF + 0.8):
			continue
		var clear := p.distance_to(Vector3(0.0, 0.0, back)) > 3.5
		for q in placed:
			if q.distance_to(p) < 1.8:
				clear = false
		for q in taken:
			if q.distance_to(p) < 1.9:
				clear = false
		if not clear:
			continue
		placed.append(p)
		_corpse(p, _rng.randf_range(-PI, PI), _missing(_rng.randf() < 0.8))

	_limit_view(wall)
	_gather_cold_lights.call_deferred(centre, wall)
	print("[morgue] enclosed hall: %d burial walls (%d bodies), %d slabs, %d coffins, %d bodies laid out (%d broken)"
		% [walls_lined, walls_lined * LOCULI_BODIES, slabs, coffins, _corpse_count, _missing_count])


## Everything here stops drawing past the level's own view range, as its chunks
## do. Without it the hall's pieces -- burial walls, slabs, piers, 29 skinned
## bodies, 32 torches -- were drawn from anywhere they were in front of the
## camera, through the rock: +150-270 draw calls and ~0.5-1 ms at every bench
## station, the nearest 240 m away (measured). The MultiMeshes span the hall,
## so theirs carries its half diagonal.
func _limit_view(wall: float) -> void:
	for node in find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if g.visibility_range_end > 0.0:
			continue
		g.visibility_range_end = VIEW_RANGE + (wall * sqrt(2.0) if g is MultiMeshInstance3D else 0.0)
		g.visibility_range_end_margin = 4.0


## From a ring cell's centre, the way into its outside wall.
static func _into_wall(at: Vector3) -> Vector3:
	if absf(at.x) > absf(at.z):
		return Vector3(signf(at.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(at.z))


## A square brick pier at every vertex inside the hall, where four vaults meet,
## and a pilaster at every one along the walls: a dark core with the kit's pier
## face (the corridor brick, cut from the wall piece) on every side that shows.
## One MultiMesh for all the faces and one for the cores.
func _build_piers(h: int, cell: float, pilaster_in: float) -> void:
	var face: Mesh = BrickLevel.standalone("pier_face")
	var body := StaticBody3D.new()
	body.name = "Piers"
	body.collision_layer = BrickLevel.LAYER_WALLS
	body.collision_mask = 0
	add_child(body)
	var faces: Array[Transform3D] = []
	var cores: Array[Transform3D] = []
	var verts: Array[float] = []
	for k in range(-h, h):
		verts.append((float(k) + 0.5) * cell)
	var mid := pilaster_in + PIER_HALF
	var piers: Array = []
	for vx in verts:
		for vz in verts:
			piers.append([Vector3(vx, 0.0, vz), [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]])
	for v in verts:
		piers.append([Vector3(v, 0.0, -mid), [Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]])
		piers.append([Vector3(v, 0.0, mid), [Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]])
		piers.append([Vector3(-mid, 0.0, v), [Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]])
		piers.append([Vector3(mid, 0.0, v), [Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]])
	for pier in piers:
		var c: Vector3 = pier[0]
		cores.append(Transform3D(Basis(), c + Vector3(0.0, PIER_TOP * 0.5, 0.0)))
		for d: Vector3 in pier[1]:
			# A kit piece's front is +Z: turned so it looks out along d.
			faces.append(Transform3D(Basis.looking_at(-d, Vector3.UP), c + d * PIER_HALF))
		var shape := BoxShape3D.new()
		shape.size = Vector3(PIER_HALF * 2.0, 6.0, PIER_HALF * 2.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = c + Vector3(0.0, 3.0, 0.0)
		body.add_child(cs)
	if face != null:
		_multi(face, faces, "PierFaces")
	var core := BoxMesh.new()
	core.size = Vector3(PIER_HALF * 2.0 - 0.12, PIER_TOP, PIER_HALF * 2.0 - 0.12)
	core.material = _mat(&"core")
	_multi(core, cores, "PierCores")


func _multi(mesh: Mesh, xfs: Array[Transform3D], name_: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


func _near_pier(p: Vector3, h: int, cell: float, margin: float) -> bool:
	for k in range(-h, h):
		for j in range(-h, h):
			var v := Vector3((float(k) + 0.5) * cell, 0.0, (float(j) + 0.5) * cell)
			if absf(p.x - v.x) < margin and absf(p.z - v.z) < margin:
				return true
	return false


## A torch on the inner face of every pilaster.
func _hang_torches(h: int, cell: float, pilaster_in: float) -> void:
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
			# `d` points into the wall; the pilaster's face is `pilaster_in` out.
			var along := Vector3(-d.z, 0.0, d.x) * v
			var at := d * (pilaster_in - 0.02) + along + Vector3(0.0, TORCH_HEIGHT, 0.0)
			level._hang_torch(self, scene, at, d, energy, 13.0)
	# And one on every pier inside, on the face toward the middle aisle, or the
	# middle of a 28 m hall lit only from its walls is black.
	for k in range(-h, h):
		for j in range(-h, h):
			var c := Vector3((float(k) + 0.5) * cell, TORCH_HEIGHT, (float(j) + 0.5) * cell)
			var d := Vector3(signf(c.x), 0.0, 0.0)
			level._hang_torch(self, scene, c - d * (PIER_HALF + 0.02), d, energy, 13.0)


## A burial wall (kit "wall_loculi": the corridor brick with three rows of
## niches, a body in its shroud in each) with its back on the wall face at
## `at`, `into` pointing into the wall.
func _loculi(at: Vector3, into: Vector3, mesh: Mesh) -> void:
	var b := Basis.looking_at(into, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "BurialWall"
	mi.mesh = mesh
	# The kit piece's origin is on its front face.
	mi.transform = Transform3D(b, at - into * LOCULI_DEPTH)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	add_child(body)
	var shape := BoxShape3D.new()
	# A hair shorter than the mesh, which tucks its ends into the pilasters.
	shape.size = Vector3(LOCULI_LEN - 0.15, LOCULI_HEIGHT, LOCULI_DEPTH)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(b, at - into * LOCULI_DEPTH * 0.5 + Vector3(0.0, LOCULI_HEIGHT * 0.5, 0.0))
	body.add_child(cs)


## A mortuary slab with its shrouded body (kit "morgue_slab", Tripo), its
## length along local Z turned by `yaw`; without the kit, the old bare slab
## and a skeleton.
func _slab(at: Vector3, yaw: float, mesh: Mesh) -> void:
	var b := Basis(Vector3.UP, yaw)
	if mesh == null:
		_solid_box(at + Vector3(0.0, SLAB.y * 0.5, 0.0), SLAB, _mat(&"slab"))
		_corpse(at + Vector3(0.0, SLAB.y, 0.0), yaw, _missing(_rng.randf() < 0.5))
		return
	_corpse_count += 1
	var mi := MeshInstance3D.new()
	mi.name = "Slab"
	mi.mesh = mesh
	mi.transform = Transform3D(b, at)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	var box := mesh.get_aabb()
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = box.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(b, at + b * box.get_center())
	body.add_child(cs)


## A random set of lost parts: one to three limbs (or the head) when `broken`.
func _missing(broken: bool) -> Array:
	if not broken:
		return []
	var pool := LIMBS.duplicate()
	var out: Array = []
	for i in _rng.randi_range(1, 3):
		out.append(pool.pop_at(_rng.randi_range(0, pool.size() - 1)))
	return out


## A body lying on its back where it fell (or was laid), limbs askew, `missing`
## collapsed away, with the bones it lost lying near it.
func _corpse(at: Vector3, yaw: float, missing: Array) -> Node3D:
	_corpse_count += 1
	if not missing.is_empty():
		_missing_count += 1
	var root := Node3D.new()
	root.name = "Corpse"
	add_child(root)
	var model: Node3D = SKELETON.instantiate()
	model.scale = Vector3(-BODY_SCALE, BODY_SCALE, -BODY_SCALE)
	root.add_child(model)
	_make_dead(model)
	var sk := _skeleton_of(model)
	if sk != null:
		_sprawl(sk, 0.55)
		for bone in missing:
			var b := sk.find_bone(bone)
			if b >= 0:
				sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)
	# On its back: the model faces -Z once flipped, and a quarter turn about X
	# turns that face to the sky. A little rolled onto one side.
	root.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, _rng.randf_range(-0.35, 0.35)) \
		* Basis(Vector3.RIGHT, PI * 0.5)
	# Down onto the floor: the lowest point of the body's rest bounds.
	var low := _lowest(root)
	root.position = at + Vector3(0.0, -low + 0.005, 0.0)
	for bone in missing:
		var off := Vector3(_rng.randf_range(-0.7, 0.7), 0.0, _rng.randf_range(-0.7, 0.7))
		if bone == &"head":
			_loose_skull(at + off)
		else:
			_loose_bone(at + off)
	return root


## Every joint knocked a little out of true, so a body does not lie like a
## plank: its rest pose bent at random by up to `amount` radians.
func _sprawl(sk: Skeleton3D, amount: float) -> void:
	for name_ in [&"spine.02", &"neck", &"head", &"upper_arm.L", &"upper_arm.R", &"forearm.L",
			&"forearm.R", &"thigh.L", &"thigh.R", &"shin.L", &"shin.R"]:
		var b := sk.find_bone(name_)
		if b < 0:
			continue
		var rest := sk.get_bone_rest(b).basis.get_rotation_quaternion()
		var axis := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
		sk.set_bone_pose_rotation(b, rest * Quaternion(axis, _rng.randf_range(0.1, amount)))


## The skeleton's material with its emission taken off (the enemies' copy is
## lit up by state) and its bone dulled with dust. Shared by every body here.
func _make_dead(model: Node3D) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src == null:
				continue
			var key := "dead_%d" % src.get_instance_id()
			if not _mats.has(key):
				var m := src.duplicate() as BaseMaterial3D
				if m != null:
					m.emission_enabled = false
					m.albedo_color = m.albedo_color * Color(0.78, 0.74, 0.68)
				_mats[key] = m
			mi.set_surface_override_material(i, _mats[key])


func _skeleton_of(model: Node3D) -> Skeleton3D:
	var found := model.find_children("*", "Skeleton3D", true, false)
	return null if found.is_empty() else found[0] as Skeleton3D


## Lowest point of `node`'s meshes' rest bounds, in its parent's space.
func _lowest(node: Node3D) -> float:
	var low := INF
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := node.transform * (node.global_transform.affine_inverse() * m.global_transform)
		var box := m.get_aabb()
		for i in 8:
			low = minf(low, (xf * box.get_endpoint(i)).y - node.position.y)
	return 0.0 if low == INF else low


## The Remnant as it was, standing in its coffin: the skeleton at its size,
## arms at its sides, crowned.
func _royal_body(at: Vector3) -> void:
	var root := Node3D.new()
	root.name = "RoyalBody"
	add_child(root)
	root.position = at
	var model: Node3D = SKELETON.instantiate()
	model.scale = Vector3(-REMNANT_SCALE, REMNANT_SCALE, -REMNANT_SCALE)
	root.add_child(model)
	_make_dead(model)
	var sk := _skeleton_of(model)
	if sk == null:
		return
	# Head bowed a little, the way a body sags upright.
	var head := sk.find_bone(&"head")
	if head >= 0:
		var rest := sk.get_bone_rest(head).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(head, rest * Quaternion(Vector3.RIGHT, 0.25))
		var attach := BoneAttachment3D.new()
		attach.bone_name = "head"
		sk.add_child(attach)
		var crown := _crown(0.13)
		crown.position = Vector3(0.0, 0.17, 0.0)
		attach.add_child(crown)


# --- Coffins ------------------------------------------------------------------------

## A standing coffin at `at` (local), facing `yaw` (0 = toward +Z, the way in).
## `state`: "closed", "ajar", "open" (lid swung wide), "open_body" (and a broken
## body standing inside), "fallen" (the lid lying on the floor in front).
## Returns the coffin's root; for the royal one, `_royal_lid` is its lid pivot.
func _coffin(at: Vector3, yaw: float, royal: bool, state: String) -> Node3D:
	var h := ROYAL_HEIGHT if royal else COFFIN_HEIGHT
	var fw := ROYAL_FOOT if royal else COFFIN_FOOT
	var sw := ROYAL_SHOULDER if royal else COFFIN_SHOULDER
	var hw := ROYAL_HEAD if royal else COFFIN_HEAD
	var d := ROYAL_DEPTH if royal else COFFIN_DEPTH
	var sy := h * 0.72
	var outline := PackedVector2Array([Vector2(-fw, 0.0), Vector2(fw, 0.0), Vector2(sw, sy),
		Vector2(hw, h), Vector2(-hw, h), Vector2(-sw, sy)])
	var body_mat := _mat(&"royal_stone" if royal else &"wood_dark")
	var lid_mat := _mat(&"royal_stone" if royal else &"wood")
	var trim_mat := _mat(&"gold" if royal else &"iron")

	var root := Node3D.new()
	root.name = "Coffin"
	add_child(root)
	root.position = at
	root.rotation.y = yaw
	var wall := 0.07 if royal else 0.045
	# The shell: a back panel and a wall along each edge of the outline.
	var back := MeshInstance3D.new()
	back.mesh = _prism(outline, wall)
	back.material_override = body_mat
	back.position = Vector3(0.0, 0.0, -d * 0.5 + wall * 0.5)
	root.add_child(back)
	for i in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		_edge_box(root, a, b, wall, d, Vector3.ZERO, body_mat)
		if royal:
			# Gold along every edge of the front.
			_edge_box(root, a, b, 0.07, 0.07, Vector3(0.0, 0.0, d * 0.5 + 0.02), trim_mat, 1.06)
	# The lid, on a hinge down its left side.
	var lid_pivot := Node3D.new()
	lid_pivot.name = "LidPivot"
	root.add_child(lid_pivot)
	lid_pivot.position = Vector3(-sw, 0.0, d * 0.5)
	var lid := MeshInstance3D.new()
	var inset := PackedVector2Array()
	for p in outline:
		inset.append(p * Vector2(0.97, 1.0) + Vector2(0.0, 0.0))
	lid.mesh = _prism(inset, 0.08 if royal else 0.05)
	lid.material_override = lid_mat
	lid.position = Vector3(sw, 0.0, 0.04)
	lid_pivot.add_child(lid)
	if royal:
		_royal_lid_dressing(lid_pivot, sw, h, sy)
	else:
		# A plain cross of iron straps.
		_box(lid_pivot, Vector3(0.05, h * 0.62, 0.02), Vector3(sw, h * 0.47, 0.08), trim_mat)
		_box(lid_pivot, Vector3(sw * 1.1, 0.05, 0.02), Vector3(sw, sy - 0.05, 0.08), trim_mat)

	match state:
		"ajar":
			lid_pivot.rotation.y = -_rng.randf_range(0.35, 0.7)
		"open":
			lid_pivot.rotation.y = -_rng.randf_range(1.6, 2.0)
		"open_body":
			lid_pivot.rotation.y = -_rng.randf_range(1.7, 2.1)
			_standing_body(root, d)
		"fallen":
			# Off its hinge, tipped forward and lying flat on the floor in front:
			# a quarter turn about X lays its height out along +Z.
			lid_pivot.position = Vector3(-sw, 0.07, d * 0.5 + 0.15)
			lid_pivot.rotation = Vector3(PI * 0.5, 0.0, 0.0)

	# Solid to everyone (1) and to sight (2).
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	root.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(sw * 2.0, h, d)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, h * 0.5, 0.0)
	body.add_child(cs)
	if royal:
		_royal_lid = lid_pivot
	return root


## The royal lid: a gold border, a long gold sword down its length, a crown at
## the top and a crest on the breast.
func _royal_lid_dressing(pivot: Node3D, sw: float, h: float, sy: float) -> void:
	var gold := _mat(&"gold")
	var cx := sw
	var z := 0.13
	# The sword: blade, guard, grip, pommel.
	_box(pivot, Vector3(0.09, h * 0.5, 0.03), Vector3(cx, h * 0.3, z), gold)
	_box(pivot, Vector3(0.5, 0.07, 0.04), Vector3(cx, h * 0.56, z), gold)
	_box(pivot, Vector3(0.06, 0.24, 0.04), Vector3(cx, h * 0.64, z), gold)
	var pommel := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.06
	ball.height = 0.12
	pommel.mesh = ball
	pommel.material_override = gold
	pommel.position = Vector3(cx, h * 0.69, z)
	pivot.add_child(pommel)
	# The crest: a gold ring on the breast.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.26
	ring.mesh = torus
	ring.material_override = gold
	ring.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	ring.position = Vector3(cx, sy - 0.12, z)
	pivot.add_child(ring)
	# The crown, over the head.
	var crown := _crown(0.24)
	crown.position = Vector3(cx, h - 0.42, z + 0.02)
	crown.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	pivot.add_child(crown)


## A crown: a band with five points, in gold.
func _crown(radius: float) -> Node3D:
	var crown := Node3D.new()
	crown.name = "Crown"
	var gold := _mat(&"gold")
	var band := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = radius
	tube.bottom_radius = radius * 0.95
	tube.height = radius * 0.45
	tube.radial_segments = 16
	band.mesh = tube
	band.material_override = gold
	crown.add_child(band)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = radius * 0.22
		cone.height = radius * 0.6
		cone.radial_segments = 6
		spike.mesh = cone
		spike.material_override = gold
		spike.position = Vector3(cos(a) * radius * 0.92, radius * 0.5, sin(a) * radius * 0.92)
		crown.add_child(spike)
	return crown


## A broken body standing in an open coffin, slumped.
func _standing_body(coffin: Node3D, depth: float) -> void:
	var model: Node3D = SKELETON.instantiate()
	model.scale = Vector3(-BODY_SCALE, BODY_SCALE, -BODY_SCALE)
	model.position = Vector3(0.0, 0.06, -depth * 0.1)
	# Faces the way the coffin does (+Z): the flip turned it to -Z.
	model.rotation.y = PI
	coffin.add_child(model)
	_make_dead(model)
	var sk := _skeleton_of(model)
	if sk != null:
		_sprawl(sk, 0.3)
		var lost: Array = [[&"forearm.L"], [&"upper_arm.R"], [&"head"], [&"forearm.R", &"shin.L"]][_rng.randi_range(0, 3)]
		for bone in lost:
			var b := sk.find_bone(bone)
			if b >= 0:
				sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)
	_corpse_count += 1
	_missing_count += 1


func _loose_bone(at: Vector3) -> void:
	var mat := _mat(&"bone")
	var bone := Node3D.new()
	add_child(bone)
	bone.position = at + Vector3(0.0, 0.025, 0.0)
	bone.rotation = Vector3(PI * 0.5, _rng.randf_range(-PI, PI), 0.0)
	var shaft := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.022
	cap.height = _rng.randf_range(0.24, 0.42)
	cap.radial_segments = 8
	cap.rings = 2
	shaft.mesh = cap
	shaft.material_override = mat
	bone.add_child(shaft)
	for side in [-1.0, 1.0]:
		var knob := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.034
		ball.height = 0.06
		ball.radial_segments = 8
		ball.rings = 4
		knob.mesh = ball
		knob.material_override = mat
		knob.position = Vector3(0.0, side * cap.height * 0.5, 0.0)
		bone.add_child(knob)


func _loose_skull(at: Vector3) -> void:
	var packed := load(SKULL_MODEL) as PackedScene
	if packed == null:
		return
	var skull: Node3D = packed.instantiate()
	add_child(skull)
	# The cage skull, sized to a skeleton's (~0.2 m) and rolled onto its side.
	var box := Interact.drawn_bounds(skull)
	var s := 0.2 / maxf(box.size.y, 0.01)
	skull.scale = Vector3.ONE * s
	skull.rotation = Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-PI, PI), _rng.randf_range(0.6, 1.4))
	skull.position = at + Vector3(0.0, 0.09, 0.0)
	for node in skull.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = _mat(&"bone")
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- Geometry helpers -----------------------------------------------------------------

## A box from `a` to `b` in the coffin's outline plane (XY), `thick` across it
## and `deep` through it, offset by `off`.
func _edge_box(parent: Node3D, a: Vector2, b: Vector2, thick: float, deep: float, off: Vector3,
		mat: Material, stretch := 1.0) -> void:
	var mid := (a + b) * 0.5
	var along := b - a
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(along.length() * stretch, thick, deep)
	mi.mesh = box
	mi.material_override = mat
	mi.position = Vector3(mid.x, mid.y, 0.0) + off
	mi.rotation.z = atan2(along.y, along.x)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


## A box you cannot walk through (layers 1 and 2), drawn in `mat`.
func _solid_box(at: Vector3, size: Vector3, mat: Material) -> void:
	_box(self, size, at, mat)
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	add_child(body)
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## A flat slab with `outline` (XY) for its faces, `depth` thick along Z,
## centred on z = 0. Wound for Godot (clockwise is the front) with explicit
## outward normals.
static func _prism(outline: PackedVector2Array, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := depth * 0.5
	var n := outline.size()
	for i in range(1, n - 1):
		var a := Vector3(outline[0].x, outline[0].y, hz)
		var b := Vector3(outline[i].x, outline[i].y, hz)
		var c := Vector3(outline[i + 1].x, outline[i + 1].y, hz)
		_tri(st, a, b, c, Vector3(0, 0, 1))
		_tri(st, Vector3(a.x, a.y, -hz), Vector3(b.x, b.y, -hz), Vector3(c.x, c.y, -hz), Vector3(0, 0, -1))
	for i in n:
		var p: Vector2 = outline[i]
		var q: Vector2 = outline[(i + 1) % n]
		var e := q - p
		var normal := Vector3(e.y, -e.x, 0.0).normalized()
		# Outward is away from the outline's middle.
		var mid := Vector2.ZERO
		for v in outline:
			mid += v
		mid /= float(n)
		if Vector2(normal.x, normal.y).dot((p + q) * 0.5 - mid) < 0.0:
			normal = -normal
		var a := Vector3(p.x, p.y, hz)
		var b := Vector3(q.x, q.y, hz)
		var c := Vector3(q.x, q.y, -hz)
		var d := Vector3(p.x, p.y, -hz)
		_tri(st, a, b, c, normal)
		_tri(st, a, c, d, normal)
	return st.commit()


## One triangle facing `normal`: wound clockwise as seen from that side (Godot's
## front), whichever order it was given in.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t := b
		b = c
		c = t
	for v in [a, b, c]:
		st.set_normal(normal)
		st.set_uv(Vector2(v.x + v.z, v.y))
		st.add_vertex(v)


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"wood", &"wood_dark":
			m.albedo_texture = load(WOOD_TEXTURE)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.4, 1.4, 1.4)
			m.albedo_color = Color(0.5, 0.42, 0.34) if key == &"wood" else Color(0.32, 0.26, 0.21)
			m.roughness = 0.88
		&"iron":
			m.albedo_color = Color(0.2, 0.2, 0.21)
			m.metallic = 0.5
			m.roughness = 0.55
		&"royal_stone":
			# Dark polished stone, the grain from the plain stone's normal map.
			# Its colour map is NOT used: it averages 30/255, so under any tint
			# it rendered as solid black -- a hole cut in the room.
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.9, 0.9, 0.9)
			# Matched to the brick walls (their map averages 53/255): 0.3 read as a
			# pale pink block beside them.
			m.albedo_color = Color(0.1, 0.1, 0.115)
			m.metallic = 0.1
			m.roughness = 0.4
		&"gold":
			# Old, dull gold. Bright (1.0 / 0.74 / 0.3) under the court's red sky
			# light it read as glowing neon.
			m.albedo_color = Color(0.6, 0.44, 0.17)
			m.metallic = 0.6
			m.roughness = 0.42
		&"dais", &"slab":
			# Normal map only, for the same reason as the royal stone.
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.albedo_color = Color(0.17, 0.16, 0.155) if key == &"slab" else Color(0.11, 0.105, 0.1)
			m.roughness = 0.92
		&"core":
			# Inside a pier, behind its brick faces: only ever seen through a crack.
			m.albedo_color = Color(0.03, 0.028, 0.03)
			m.roughness = 1.0
		&"bone":
			m.albedo_color = Color(0.62, 0.58, 0.5)
			m.roughness = 0.9
	_mats[key] = m
	return m


## The room's own lights (not the torches, which have their own cold): the
## court's sky light, chiefly. Gathered once the level's lights exist.
func _gather_cold_lights(centre: Vector3, span: float) -> void:
	_cold_lights.clear()
	for node in get_tree().root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.get_parent() != null and light.get_parent().get_script() == Torch:
			continue
		var p := light.global_position
		if Vector2(p.x - centre.x, p.z - centre.z).length() <= span + 4.0:
			_cold_lights.append([light, light.light_color])


# --- Opening it ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Co-op: whoever is nearest, or in a scene with it (coop.gd `user_for`).
	_player = Coop.user_for(self, _player)
	if _player == null:
		return
	if _busy or _royal == null:
		_near = false
		_prompt.visible = false
		return
	var front := _royal.global_basis.z
	var to := _player.global_position - _royal.global_position
	_near = to.dot(front) > 0.5 and Vector2(to.x, to.z).length() <= REACH \
		and not _player.get("in_cutscene") and not _player.get("_dead") \
		and Interact.looked_at(_royal, 5.0, 0.1, [], _player)
	_prompt.visible = _near
	_prompt.player = _player


func _unhandled_input(event: InputEvent) -> void:
	if not _near or _busy or not Interact.pressed(event, _player):
		return
	get_viewport().set_input_as_handled()
	_open_royal()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _hud() -> Node:
	return Coop.hud(_player)


func _open_royal() -> void:
	_busy = true
	_near = false
	_prompt.visible = false
	var player := _player
	if not player.is_connected("respawned", _on_respawned):
		player.connect("respawned", _on_respawned, CONNECT_ONE_SHOT)
	player.begin_cutscene(false)
	player.set("hands_busy", true)
	_bars = WoodDoor.letterbox(self)
	# Up to it, eyes on the lid.
	var lid_point: Vector3 = _royal.global_transform * Vector3(0.0, ROYAL_HEIGHT * 0.55, ROYAL_DEPTH * 0.5)
	var stand: Vector3 = _royal.global_transform * Vector3(0.0, 0.0, ROYAL_DEPTH * 0.5 + STAND_OFF)
	stand.y = player.global_position.y
	player.scene_look_at(lid_point, 5.0)
	player.scene_walk_to(stand, 3.5)
	await Signal(player, "scene_walk_finished")
	player.scene_frame(7.0, 0.0, 2.2)
	await _wait(0.45)

	# A hand on it: the lid grinds open a hand's breadth.
	player.set("_shake", maxf(float(player.get("_shake")), 0.14))
	var creak := create_tween()
	creak.tween_property(_royal_lid, "rotation:y", -0.07, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _wait(0.5)

	# The cold: everything in the room ice blue, all at once.
	var hud := _hud()
	var cold := create_tween().set_parallel(true)
	if hud != null:
		cold.tween_property(hud, "ice_override", 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for pair in _cold_lights:
		var light: Light3D = pair[0]
		if is_instance_valid(light):
			cold.tween_property(light, "light_color", Color(0.45, 0.72, 1.0), 0.4)
	player.scene_frame(9.0, -2.0, 4.0)
	await _wait(0.75)

	# Behind them.
	var remnant := get_tree().get_first_node_in_group("stalker") as Node3D
	if remnant == null or not remnant.has_method("scripted_appear") or remnant.get("_dying"):
		# It is gone -- banished. Nothing guards the body any more: the lid
		# comes off and that is all.
		var open := create_tween()
		open.tween_property(_royal_lid, "rotation:y", -1.9, 1.2).set_trans(Tween.TRANS_QUAD)
		await _wait(1.4)
		_end_quietly(player)
		return
	var back_dir: Vector3 = player.global_basis.z
	back_dir.y = 0.0
	back_dir = back_dir.normalized()
	var at: Vector3 = player.global_position + back_dir * BEHIND
	at.y = player.global_position.y
	remnant.scripted_appear(at, player.global_position)
	player.set("_shake", maxf(float(player.get("_shake")), 0.2))
	await _wait(0.12)
	# The turn.
	player.scene_frame(-3.0, 3.0, 3.5)
	player.scene_look_at(remnant.head_point(), 3.6)
	await _wait(1.0)

	# It rears up over them; the view goes up with it.
	remnant.scripted_windup(0.8)
	player.scene_look_at(remnant.head_point() + Vector3(0.0, 0.9, 0.0), 2.6)
	player.scene_frame(5.0, -5.0, 2.0)
	await _wait(0.8)

	# Down.
	remnant.scripted_slam(0.26)
	await _wait(0.17)
	player.set("_shake", 1.0)
	var crush := create_tween()
	crush.tween_method(Callable(player, "scene_crush"), 0.0, 1.0, 0.14).set_ease(Tween.EASE_IN)
	if hud != null and hud.has_method("fade_black"):
		hud.fade_black(1.0, 0.1)
	await _wait(0.16)
	player.kill_in_scene()


## The scene ended without a death (the Remnant was gone): control back.
func _end_quietly(player: Node3D) -> void:
	if _bars != null and is_instance_valid(_bars):
		WoodDoor.letterbox_out(_bars)
		_bars = null
	player.set("hands_busy", false)
	player.end_cutscene()
	if player.is_connected("respawned", _on_respawned):
		player.disconnect("respawned", _on_respawned)
	var hud := _hud()
	if hud != null:
		create_tween().tween_property(hud, "ice_override", 0.0, 2.0)
	_restore_lights()


## The player is back up at their anchor: the room as it was.
func _on_respawned() -> void:
	if _bars != null and is_instance_valid(_bars):
		_bars.queue_free()
		_bars = null
	var hud := _hud()
	if hud != null:
		hud.set("ice_override", 0.0)
	_restore_lights()
	if _royal_lid != null:
		_royal_lid.rotation.y = 0.0
	_busy = false


func _restore_lights() -> void:
	for pair in _cold_lights:
		var light: Light3D = pair[0]
		if is_instance_valid(light):
			light.light_color = pair[1]
