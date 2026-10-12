extends Node3D

## The player's starting room is a jail cell (2026-10-08): the dead end the
## player wakes in, shut by the gate door they have to kick in to get out
## (`module_level._pick_spawn`, `place_doors` -- the door is untouched).
##
## Dressed here: a plank bed with a straw mattress and a blanket along one side
## wall, straw strewn over the floor, two pairs of shackles and chains on the
## back wall with the bones of the last prisoner slumped under one of them, a
## wooden slop bucket in a corner, and tally marks scratched into the other
## side wall. Built from primitives (and the cage skull), in the dead end's own
## frame: +Z toward the door. A dead end is not a square room -- measured with
## rays, the back wall is `FACE` 2.79 m from the centre but two thick piers fill
## the back corners, so behind z = -1.2 the room is an alcove only `ALCOVE`
## 1.80 m either side; the full 2.79 m width is only toward the door. The bed
## lies across the alcove's back wall, the shackles beside it, the tally marks on
## the right-hand pier, the bucket out in the wider front part. Things that hang
## on the stone are snapped onto it by ray once the collision is live
## (`_snap_to_walls`): Tripo stone stands up to ~10 cm proud of the measured face.
##
## Built by `maze._build_module_level` before the navmesh bake, so the bed and
## bucket (layer 1) are walked round.

const SKULL := preload("res://models/skull_worn_ready.glb")
## Cell centre to the inside face of a dead end's walls (module_level.WALL_FACE).
static var FACE := 2.79
## Half-width of the alcove at the back, between the corner piers, and where
## the piers end (toward the door).
static var ALCOVE := 1.8
static var PIER_END := -1.2
## Where the tally marks are scratched: the right-hand pier in a module dead
## end; the right-hand wall in a brick one, whose corner pillars leave too
## little of their faces showing.
static var TALLY_AT := Vector3(1.8, 1.25, -2.05)
const STRAW_BLADES := 260
const BED_LENGTH := 1.8

var _wall_items: Array[Node3D] = []


## Builds the cell in `built`'s spawn dead end. Null when the spawn is not in one.
static func build(parent: Node3D, built, torch_energy := 1.3) -> Node3D:
	if built.spawn_door.is_empty():
		return null
	# The brick kit's dead end (brick_level.gd): walls 1.9 m out, its corner
	# pillars filling 1.55 to 2.45 m on both axes.
	if load("res://scripts/module_level.gd").brick:
		FACE = 1.9
		ALCOVE = 1.5
		PIER_END = -1.55
		TALLY_AT = Vector3(1.9, 1.25, -0.95)
	else:
		FACE = 2.79
		ALCOVE = 1.8
		PIER_END = -1.2
		TALLY_AT = Vector3(1.8, 1.25, -2.05)
	var cell: Vector2i = built.spawn_door["cell"]
	var step: Vector2i = load("res://scripts/module_maze.gd").DIRS[int(built.spawn_door["side"])]
	var out := Vector3(float(step.x), 0.0, float(step.y))
	var jail := Node3D.new()
	jail.set_script(load("res://scripts/jail_cell.gd"))
	jail.name = "JailCell"
	parent.add_child(jail)
	# +Z toward the door.
	jail.global_basis = Basis.looking_at(-out, Vector3.UP)
	jail.global_position = built.to_world(cell)
	jail.call("_dress")
	# Its own torch, on the left wall in the front half (bed and shackles are
	# on the back wall, the tally marks on the right). Before torches cast
	# shadows the cell was lit through its walls by the corridor's; with them it
	# measured 30x darker than before -- black.
	var level = load("res://scripts/module_level.gd")
	level._hang_torch(jail, load(level.TORCH_SCENE), Vector3(-FACE, built.height * level.TORCH_HEIGHT, 0.5),
		Vector3.LEFT, torch_energy * 0.6, level.TORCH_RANGE)
	return jail


func _ready() -> void:
	_snap_to_walls.call_deferred()


# --- Materials -------------------------------------------------------------------

func _mat(colour: Color, rough := 0.95, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = rough
	m.metallic = metal
	return m


func _wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/wood_door_albedo.png")
	m.normal_enabled = true
	m.normal_texture = load("res://textures/wood_door_normal.png")
	m.albedo_color = Color(0.5, 0.42, 0.34)
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	return m


func _mesh(mesh: Mesh, material: Material, at: Vector3, rot := Vector3.ZERO, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = at
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _solid(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = at
	add_child(body)


# --- Dressing --------------------------------------------------------------------

func _dress() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1a17
	var wood := _wood()
	var iron := _mat(Color(0.11, 0.1, 0.095), 0.6, 0.75)
	# Dark on purpose: the door's two torches hang a metre or two away, and at
	# that range plain bright colours blew out to glowing orange against the
	# textured stone.
	var straw := _mat(Color(0.29, 0.22, 0.1), 1.0)
	var cloth := _mat(Color(0.1, 0.085, 0.07), 1.0)
	var bone := _mat(Color(0.48, 0.44, 0.36), 0.9)
	var scratch := _mat(Color(0.3, 0.28, 0.26), 1.0)
	_bed(wood, straw, cloth)
	_strewn_straw(straw, rng)
	_shackles(Vector3(0.62, 0.0, -FACE), iron, false)
	_shackles(Vector3(1.3, 0.0, -FACE), iron, true)
	_remains(bone, rng)
	_bucket(wood, iron)
	# Scratches float over the brick kit's deep mortar joints; only on smooth stone.
	if TALLY_AT.x < 1.85:
		_tally(scratch)


## A low plank bed across the back wall of the alcove, its head against the
## left pier, a lumpy straw mattress, and a blanket half off it. Kept 0.15-0.2 m
## off the stone, which stands up to ~10 cm proud of its measured face.
func _bed(wood: Material, straw: Material, cloth: Material) -> void:
	var half := BED_LENGTH * 0.5
	var x := -ALCOVE + 0.15 + half
	var z := -FACE + 0.2 + 0.45
	var bed := Node3D.new()
	bed.name = "Bed"
	bed.position = Vector3(x, 0.0, z)
	# Its length (local Z) along the wall.
	bed.rotation.y = PI * 0.5
	add_child(bed)
	for lx: float in [-0.36, 0.36]:
		for lz: float in [-(half - 0.08), half - 0.08]:
			_mesh(_box(Vector3(0.09, 0.32, 0.09)), wood, Vector3(lx, 0.16, lz), Vector3.ZERO, bed)
	for lx: float in [-0.38, 0.38]:
		_mesh(_box(Vector3(0.07, 0.1, BED_LENGTH)), wood, Vector3(lx, 0.34, 0.0), Vector3.ZERO, bed)
	var slats := 6
	for i in slats:
		_mesh(_box(Vector3(0.82, 0.035, 0.26)), wood,
			Vector3(0.0, 0.39, -half + 0.15 + i * (BED_LENGTH - 0.3) / float(slats - 1)),
			Vector3(0.0, 0.0, 0.02 * float(i % 3 - 1)), bed)
	# Straw pallet: a flat sacking mattress with a few low lumps on it.
	_mesh(_box(Vector3(0.78, 0.12, BED_LENGTH - 0.08)), straw, Vector3(0.0, 0.47, 0.0), Vector3.ZERO, bed)
	for i in 3:
		var lump := SphereMesh.new()
		lump.radius = 0.3
		lump.height = 0.12
		lump.radial_segments = 10
		lump.rings = 5
		_mesh(lump, straw, Vector3(0.05 * float(i - 1), 0.53, -half + 0.35 + i * (BED_LENGTH - 0.7) / 2.0),
			Vector3(0.0, 0.4 * float(i), 0.0), bed).scale = Vector3(1.0, 1.0, 1.25)
	# The blanket, rucked and sliding off toward the room (local -X is the room).
	_mesh(_box(Vector3(0.95, 0.03, 1.0)), cloth, Vector3(-0.12, 0.6, 0.2), Vector3(0.0, -0.18, 0.32), bed)
	_mesh(_box(Vector3(0.06, 0.4, 0.85)), cloth, Vector3(-0.56, 0.38, 0.26), Vector3(0.0, -0.18, -0.08), bed)
	_solid(Vector3(BED_LENGTH + 0.05, 0.62, 0.9), Vector3(x, 0.31, z))


## Straw everywhere: thin blades, thickest round the bed and in the back corner.
func _strewn_straw(straw: Material, rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var blade := BoxMesh.new()
	blade.size = Vector3(0.26, 0.006, 0.014)
	mm.mesh = blade
	mm.instance_count = STRAW_BLADES
	for i in STRAW_BLADES:
		var p: Vector3
		var roll := rng.randf()
		if roll < 0.5:
			# Round the bed and spilled off it into the alcove.
			p = Vector3(rng.randf_range(-ALCOVE + 0.15, 0.6), 0.0, rng.randf_range(-FACE + 0.15, -1.3))
		elif roll < 0.7:
			# Trodden out into the middle.
			p = Vector3(rng.randf_range(-1.4, 1.2), 0.0, rng.randf_range(-1.6, 0.2))
		else:
			# Thin, everywhere the floor reaches.
			p = Vector3(rng.randf_range(-ALCOVE + 0.1, ALCOVE - 0.1), 0.0, rng.randf_range(-FACE + 0.1, 0.9))
			if p.z > PIER_END + 0.1:
				p.x = rng.randf_range(-FACE + 0.15, FACE - 0.15)
		p.y = 0.012 + rng.randf() * 0.025
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, rng.randf_range(-0.15, 0.15))
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.6, 1.3)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Straw"
	mmi.multimesh = mm
	mmi.material_override = straw
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## A wall plate and ring at head height, a chain hanging from it, and an open
## manacle at its end. `at` is on the back wall's face; snapped onto the stone.
func _shackles(at: Vector3, iron: Material, short: bool) -> void:
	var holder := Node3D.new()
	holder.name = "Shackle"
	holder.position = at + Vector3(0.0, 1.7, 0.0)
	add_child(holder)
	# Snaps along -Z (into the back wall).
	holder.set_meta("into", Vector3(0, 0, -1))
	holder.set_meta("standoff", 0.02)
	_wall_items.append(holder)
	_mesh(_box(Vector3(0.14, 0.14, 0.03)), iron, Vector3(0.0, 0.0, 0.015), Vector3.ZERO, holder)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.035
	ring.outer_radius = 0.055
	_mesh(ring, iron, Vector3(0.0, -0.06, 0.06), Vector3(0.0, 0.0, PI * 0.5), holder)
	var link := TorusMesh.new()
	link.inner_radius = 0.014
	link.outer_radius = 0.028
	var links := 12 if short else 17
	for i in links:
		var y := -0.11 - i * 0.042
		_mesh(link, iron, Vector3(0.0, y, 0.06), Vector3(0.0, (PI * 0.5) * float(i % 2), PI * 0.5), holder)
	var manacle := TorusMesh.new()
	manacle.inner_radius = 0.045
	manacle.outer_radius = 0.07
	_mesh(manacle, iron, Vector3(0.0, -0.11 - links * 0.042 - 0.05, 0.08), Vector3(0.25, 0.0, 0.0), holder)


## The last prisoner, fallen to pieces under the second shackles: the skull on
## its side against the wall, ribs, a few long bones.
func _remains(bone: Material, rng: RandomNumberGenerator) -> void:
	var base := Vector3(1.0, 0.0, -FACE + 0.4)
	var skull: Node3D = SKULL.instantiate()
	skull.name = "Skull"
	skull.scale = Vector3.ONE * 0.85
	skull.position = base + Vector3(-0.25, 0.1, 0.05)
	skull.rotation = Vector3(0.0, -PI * 0.5 + 0.6, 1.2)
	add_child(skull)
	for node in skull.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var long := CylinderMesh.new()
	long.top_radius = 0.018
	long.bottom_radius = 0.022
	long.height = 0.42
	long.radial_segments = 6
	var knob := SphereMesh.new()
	knob.radius = 0.032
	knob.height = 0.06
	knob.radial_segments = 6
	knob.rings = 3
	for i in 5:
		var p := base + Vector3(rng.randf_range(-0.2, 0.55), 0.025, rng.randf_range(0.0, 0.55))
		var yaw := rng.randf() * TAU
		var b := Node3D.new()
		b.position = p
		b.rotation = Vector3(0.0, yaw, PI * 0.5)
		add_child(b)
		_mesh(long, bone, Vector3.ZERO, Vector3.ZERO, b)
		_mesh(knob, bone, Vector3(0.0, 0.21, 0.0), Vector3.ZERO, b)
		_mesh(knob, bone, Vector3(0.0, -0.21, 0.0), Vector3.ZERO, b)
	# Ribs: curved slivers in a loose heap.
	var rib := TorusMesh.new()
	rib.inner_radius = 0.13
	rib.outer_radius = 0.145
	rib.rings = 10
	rib.ring_segments = 4
	for i in 6:
		_mesh(rib, bone, base + Vector3(0.2 + i * 0.035, 0.03 + i * 0.012, 0.18),
			Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, 0.6), rng.randf_range(-0.2, 0.2))).scale = Vector3(1.0, 1.0, 0.7)


## A slop bucket out in the wider front part, against the right-hand wall:
## staves and two iron hoops.
func _bucket(wood: Material, iron: Material) -> void:
	var at := Vector3(FACE - 0.45, 0.0, -0.3)
	var body := CylinderMesh.new()
	body.top_radius = 0.22
	body.bottom_radius = 0.18
	body.height = 0.42
	body.radial_segments = 12
	_mesh(body, wood, at + Vector3(0.0, 0.21, 0.0))
	var hoop := CylinderMesh.new()
	hoop.top_radius = 0.205
	hoop.bottom_radius = 0.205
	hoop.height = 0.03
	hoop.radial_segments = 12
	_mesh(hoop, iron, at + Vector3(0.0, 0.1, 0.0)).scale = Vector3(1.0, 1.0, 1.0)
	_mesh(hoop, iron, at + Vector3(0.0, 0.33, 0.0)).scale = Vector3(1.07, 1.0, 1.07)
	var dark := CylinderMesh.new()
	dark.top_radius = 0.19
	dark.bottom_radius = 0.19
	dark.height = 0.01
	_mesh(dark, _mat(Color(0.05, 0.045, 0.03), 0.4), at + Vector3(0.0, 0.36, 0.0))
	var body_shape := CylinderShape3D.new()
	body_shape.radius = 0.22
	body_shape.height = 0.42
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = body_shape
	sb.add_child(cs)
	sb.position = at + Vector3(0.0, 0.21, 0.0)
	add_child(sb)


## Days counted on the right-hand pier, beside the bed: groups of four strokes
## and a slash.
func _tally(scratch: Material) -> void:
	var holder := Node3D.new()
	holder.name = "Tally"
	holder.position = TALLY_AT
	holder.rotation.y = -PI * 0.5
	holder.set_meta("into", Vector3(1, 0, 0))
	holder.set_meta("standoff", 0.012)
	add_child(holder)
	_wall_items.append(holder)
	var stroke := _box(Vector3(0.012, 0.16, 0.01))
	var slash := _box(Vector3(0.012, 0.25, 0.01))
	for g in 6:
		var gx := -0.6 + g * 0.24
		var gy := 0.0 if g < 4 else -0.24
		if g >= 4:
			gx = -0.6 + (g - 4) * 0.24
		for s in 4:
			_mesh(stroke, scratch, Vector3(gx + s * 0.035, gy, 0.0), Vector3(0.0, 0.0, 0.04 * float(s % 2)), holder)
		_mesh(slash, scratch, Vector3(gx + 0.052, gy, 0.004), Vector3(0.0, 0.0, -1.05), holder)


## Each wall piece is moved onto the real stone along its `into` direction (in
## the cell's frame), `standoff` clear of it, once collision is live.
func _snap_to_walls() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for item in _wall_items:
		if not is_instance_valid(item):
			continue
		var into: Vector3 = (global_basis * (item.get_meta("into") as Vector3)).normalized()
		var standoff: float = item.get_meta("standoff")
		var from := item.global_position - into * 0.8
		var ray := PhysicsRayQueryParameters3D.create(from, from + into * 1.6, 2 | 256)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			item.global_position = (hit["position"] as Vector3) - into * standoff
			item.set_meta("snapped", true)
