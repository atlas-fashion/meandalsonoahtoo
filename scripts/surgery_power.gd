extends Node3D

## The surgery's POWERING ROOM and the HATCH down to it (2026-10-25, note 102).
## The user: "There should be a crystal powering the whole room in a separate
## 'powering room' under the surgery room, only accessible through a hatch that
## is under a specific movable vat ... When the player comes back up out of the
## powering room after removing the crystal from the room, the surgeon should be
## gone."
##
## THE HATCH: an iron trapdoor (models/surgery/hatch.glb) over a hole in the
## hall's floor, made as a manhole's is -- the brick kit's notched flagstones
## (module_level `_pick_surgery_hatch`, brick_level) -- under one of the vats
## (surgery.gd, surgery_vat.gd). Push that vat off it and E on the lid hauls it
## up by its ring and lets it fall open on its hinges; E on the open hole climbs
## down. The climb is manhole.gd's: the screen fades to black on the way into
## the shaft and back in on the ladder's last stretch, in the room. At the
## bottom, E on the ladder climbs back up. Open, it stays open (saved); a curb
## round it (surgery_vat.gd STOP_LAYER) stops a vat being shoved over the hole.
##
## THE ROOM, under the hall (FLOOR_Y .. CEIL_Y -- above the sewer's split at -4,
## so the map, the torches and the sewer's haze all still count it as the
## dungeon): brick walls and flagstones (the dungeon's own kit), a plank
## ceiling, the iron ladder (the kit's rail stood on end), and the machine that
## feeds the hall above -- galvanic coils, a bank of pistons, a glass core
## column, a lever box, a flywheel and gear on the far wall turning while it runs
## -- all of note 98's Higgsfield pieces. In the middle, held upright between two
## iron clamps on a gear laid flat, THE CRYSTAL (models/surgery/crystal.glb), a
## cold blue light in it, cables from the clamps up through the ceiling.
##
## E on the crystal: THE PULL, a short scene. The player sets themselves, takes
## hold; the clamps fight it -- arcs off them, the light stuttering -- and it
## tears free into their hands (the inventory's "power_crystal"). The room goes
## dark but for the candles; the flywheel runs down; overhead the claw falls
## (surgical_table.gd `power_off`, dust shaken from the ceiling) and the
## booth's console dies (surgery_control.gd `power_cut`). Climbing back out, the
## surgeon is gone from his booth (`surgery_control.gd` `leave`, done while the
## screen is black).
##
## Everything down here draws on POWER_LAYER, which no light up in the dungeon
## reaches (`_wall_off`, as maze.gd walls the sewer off): the floor between is no
## shadow caster, so the hall's torches would light it through the flags.

signal crystal_taken
signal surgeon_left

const KIT := {
	"hatch": preload("res://models/surgery/hatch.glb"),
	"crystal": preload("res://models/surgery/crystal.glb"),
	"gear": preload("res://models/surgery/gear.glb"),
	"clampmount": preload("res://models/surgery/clampmount.glb"),
	"cable": preload("res://models/surgery/cable.glb"),
	"galvanic": preload("res://models/surgery/galvanic.glb"),
	"pistons": preload("res://models/surgery/pistons.glb"),
	"column": preload("res://models/surgery/column.glb"),
	"leverbox": preload("res://models/surgery/leverbox.glb"),
	"flywheel": preload("res://models/surgery/flywheel.glb"),
	"candelabra": preload("res://models/surgery/candelabra.glb"),
	"track": preload("res://models/surgery/track.glb"),
	"beam": preload("res://models/surgery/beam.glb"),
}
const PLANKS := preload("res://textures/surgery_planks.png")
const Table := preload("res://scripts/surgical_table.gd")
const BrickLevel := preload("res://scripts/brick_level.gd")
const Vat := preload("res://scripts/surgery_vat.gd")
const WOOD_DOOR := preload("res://scripts/wood_door.gd")
const FX_DUST := preload("res://textures/surgery_fx_dust.png")

## What is drawn down here, and the only layer its lights reach.
const POWER_LAYER := 1 << 16

## The room, in this node's frame (origin the hole, on the hall's floor; +Z
## toward the hall's middle, the ladder on the -Z side): its floor and ceiling,
## its walls.
const FLOOR_Y := -3.9
const CEIL_Y := -1.25
const HALF_W := 3.5
const BACK := -0.62
const FRONT := 7.4
## The shaft: square, this far either side of the hole's middle.
const SHAFT := 0.6
## The hole cut by the notched flags (manhole.gd HOLE_R).
const HOLE_R := 0.5
## The crystal's place, and the clamps either side of it.
const CRYSTAL_AT := Vector3(0.0, 0.0, 4.4)
const CLAMP_X := 0.66

## The lid (1.35 m along its hinges' normal, 1.16 along them): hinged on the
## hole's +X side, it falls open past upright to LID_OPEN.
const LID_LEN := 1.35
const LID_OPEN := 1.85
## Reach to use the lid or the hole, and where the player stands to.
const REACH := 2.6
const LIFT_STAND := 1.05
const DOWN_STAND := 0.9
## A vat this near the hole's middle covers the lid.
const COVERED := Vat.RADIUS + 0.62

## The climb (manhole.gd): metres climbed in the dark, metres that fade back in.
const DARK_STRETCH := 1.0
const LIGHT_STRETCH := 2.5
const RUNG := 0.3
const CLIMB_PACE := 0.62
const FADE_OUT := 0.9
const FADE_IN := 1.2
## The ladder's face this far out from the hole's middle (toward -Z).
const LADDER_OUT := 0.5

## The machine: how fast the flywheel turns (rad/s) while it runs.
const FLY_SPIN := 2.4
const CRYSTAL_COLOUR := Color(0.45, 0.8, 1.0)

var surgery: Node3D
var table: Node3D
var control: Node3D

var hatch_open := false
var crystal_gone := false
var surgeon_gone := false

var _room: Node3D
var _lid_hinge: Node3D
var _lid: Node3D
var _lid_body: StaticBody3D
var _curb: StaticBody3D
var _ladder: Node3D
var _crystal: Node3D
var _crystal_mats: Array = []
var _crystal_light: OmniLight3D
var _glow_mats: Array = []
var _flywheel: Node3D
var _gear: Node3D
var _spin := 1.0
var _candle: OmniLight3D
var _lid_prompt: Interact.Prompt
var _ladder_prompt: Interact.Prompt
var _crystal_prompt: Interact.Prompt
var _player: Node3D
var _busy := false
var _near_top := false
var _near_bottom := false
var _near_crystal := false


## Built by surgery.gd: `hole` (world) the hole's middle on the hall's floor,
## `cell_centre` (world) the middle of the dungeon cell it is in (the bed under
## that cell's flags is laid here, with the hole left in it), the room's +Z
## (world) toward the hall's middle.
func setup(surgery_: Node3D, table_: Node3D, control_: Node3D, cell_centre: Vector3) -> void:
	surgery = surgery_
	table = table_
	control = control_
	_build_bed(cell_centre)
	_build_lid()
	_room = Node3D.new()
	_room.name = "PoweringRoom"
	add_child(_room)
	_build_shell()
	_build_machine()
	_build_crystal()
	_build_ladder()
	_lid_prompt = Interact.prompt("E   Open the hatch", Vector3(0.0, 0.25, 0.0))
	add_child(_lid_prompt)
	_ladder_prompt = Interact.prompt("E   Climb up", Vector3.ZERO)
	add_child(_ladder_prompt)
	_ladder_prompt.position = Vector3(0.0, FLOOR_Y + 1.4, LADDER_OUT * -0.5)
	_crystal_prompt = Interact.prompt("E   Pull the crystal", Vector3.ZERO)
	add_child(_crystal_prompt)
	_crystal_prompt.position = CRYSTAL_AT + Vector3(0.0, FLOOR_Y + 1.3, 0.0)
	_lay_out(_room)
	_wall_off.call_deferred()


# --- Building: the hatch, up in the hall ---------------------------------------------

## The bed under this cell's flagstones with the hole left in it (manhole.gd's;
## brick_level leaves this cell's bed out).
func _build_bed(cell_centre: Vector3) -> void:
	var bed_mat := BrickLevel.bed_material()
	var c := to_local(cell_centre)
	var gap := SHAFT
	var x0 := c.x - 3.0
	var x1 := c.x + 3.0
	var z0 := c.z - 3.0
	var z1 := c.z + 3.0
	for r in [[x0, -gap, z0, z1], [gap, x1, z0, z1], [-gap, gap, z0, -gap], [-gap, gap, gap, z1]]:
		var w: float = r[1] - r[0]
		var d: float = r[3] - r[2]
		if w <= 0.01 or d <= 0.01:
			continue
		var box := BoxMesh.new()
		box.size = Vector3(w, 0.2, d)
		box.material = bed_mat
		var mi := MeshInstance3D.new()
		mi.name = "Bed"
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((r[0] + r[1]) * 0.5, -0.16, (r[2] + r[3]) * 0.5)
		add_child(mi)


## The lid on its hinges along the hole's +X side, lying shut across it (the
## model's hinges on its -X edge, turned to face this way).
func _build_lid() -> void:
	_lid_hinge = Node3D.new()
	_lid_hinge.name = "HatchHinge"
	add_child(_lid_hinge)
	_lid_hinge.position = Vector3(LID_LEN * 0.5, 0.012, 0.0)
	_lid = _piece("hatch", _lid_hinge, Vector3(-LID_LEN * 0.5, 0.0, 0.0), PI, false)
	Table.grade(_lid)
	# Open, it stands on its hinges: solid then, so no one walks through it.
	_lid_body = StaticBody3D.new()
	_lid_body.name = "LidBody"
	_lid_body.collision_layer = 1 | 2
	_lid_body.collision_mask = 0
	add_child(_lid_body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.16, 1.3, 1.16)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(LID_LEN * 0.5 + 0.1, 0.65, 0.0)
	cs.disabled = true
	_lid_body.add_child(cs)
	# The curb that keeps vats off the open hole: their layer only.
	_curb = StaticBody3D.new()
	_curb.name = "VatCurb"
	_curb.collision_layer = 0
	_curb.collision_mask = 0
	add_child(_curb)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.95
	cyl.height = 1.5
	var cc := CollisionShape3D.new()
	cc.shape = cyl
	cc.position = Vector3(0.0, 0.75, 0.0)
	_curb.add_child(cc)


func _set_lid_open(open: bool) -> void:
	(_lid_body.get_child(0) as CollisionShape3D).disabled = not open
	_curb.collision_layer = Vat.STOP_LAYER if open else 0


# --- Building: the room under it -----------------------------------------------------

## A kit piece on `parent` at `at`, turned `yaw`, scaled `s`; down here (`deep`)
## drawn on POWER_LAYER.
func _piece(name_: String, parent: Node3D, at: Vector3, yaw := 0.0, deep := true, s := 1.0) -> Node3D:
	var n: Node3D = (KIT[name_] as PackedScene).instantiate()
	n.name = name_.capitalize().replace(" ", "")
	parent.add_child(n)
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return n


func _solid(size: Vector3, at: Vector3, parent: Node3D = null) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	(parent if parent != null else _room).add_child(body)
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## Everything under `n` on POWER_LAYER.
func _lay_out(n: Node) -> void:
	for g in n.find_children("*", "VisualInstance3D", true, false):
		if not g is Light3D:
			(g as VisualInstance3D).layers = POWER_LAYER


## Floor, walls, ceiling, the shaft: the dungeon's flags and brick, the
## surgery's planks.
func _build_shell() -> void:
	var h := CEIL_Y - FLOOR_Y
	var mid_z := (BACK + FRONT) * 0.5
	var floor_mesh: Mesh = BrickLevel.standalone("floor")
	if floor_mesh != null:
		# Three by three slabs (FLOOR_TILE, 3 m), each turned a quarter more.
		var k := 0
		for fx: float in [-3.0, 0.0, 3.0]:
			for fz: float in [0.9, 3.9, 6.9]:
				var mi := MeshInstance3D.new()
				mi.mesh = floor_mesh
				mi.position = Vector3(fx, FLOOR_Y, fz)
				mi.rotation.y = PI * 0.5 * float(k % 4)
				_room.add_child(mi)
				k += 1
	_solid(Vector3(HALF_W * 2.0, 0.4, FRONT - BACK), Vector3(0.0, FLOOR_Y - 0.2, mid_z))
	# Walls: the dungeon's brick piece, two to a side, its face inward (each a
	# little wider than half the side: the piece's ends do not quite meet).
	var wall_mesh: Mesh = BrickLevel.standalone("wall")
	var sides := [[Vector3(0, 0, -1), BACK, HALF_W * 2.0], [Vector3(0, 0, 1), FRONT, HALF_W * 2.0],
		[Vector3(-1, 0, 0), -HALF_W, FRONT - BACK], [Vector3(1, 0, 0), HALF_W, FRONT - BACK]]
	for s in sides:
		var d: Vector3 = s[0]
		var along := Vector3(-d.z, 0.0, d.x)
		var length: float = s[2]
		var centre := Vector3(0.0, 0.0, mid_z) * (Vector3.ONE - d.abs()) + d.abs() * float(s[1])
		if wall_mesh != null:
			for k in 2:
				var mi := MeshInstance3D.new()
				mi.mesh = wall_mesh
				var off := (float(k) - 0.5) * length * 0.5
				mi.transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)).scaled(
					Vector3(length * 0.5 * 1.08 / 5.19, h / 3.5, 1.0)), centre + along * off + Vector3(0.0, FLOOR_Y, 0.0))
				_room.add_child(mi)
		var size := Vector3(length, h, 0.4) if absf(d.z) > 0.5 else Vector3(0.4, h, length)
		_solid(size, centre + d * 0.2 + Vector3(0.0, FLOOR_Y + h * 0.5, 0.0))
	# The ceiling: planks, the shaft's square left open.
	var m := StandardMaterial3D.new()
	m.albedo_texture = PLANKS
	m.albedo_color = Color(0.5, 0.44, 0.38)
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.4, 0.4, 0.4)
	for r in [[-HALF_W, -SHAFT, BACK, FRONT], [SHAFT, HALF_W, BACK, FRONT], [-SHAFT, SHAFT, SHAFT, FRONT]]:
		var plane := PlaneMesh.new()
		plane.size = Vector2(r[1] - r[0], r[3] - r[2])
		plane.flip_faces = true
		var mi := MeshInstance3D.new()
		mi.name = "Ceiling"
		mi.mesh = plane
		mi.material_override = m
		mi.position = Vector3((r[0] + r[1]) * 0.5, CEIL_Y, (r[2] + r[3]) * 0.5)
		_room.add_child(mi)
	# Two oak beams across it, clear of the crystal.
	for z: float in [1.6, 6.6]:
		var beam := _piece("beam", _room, Vector3(0.0, CEIL_Y - 0.2, z))
		beam.basis = Basis.IDENTITY.scaled(Vector3(HALF_W * 2.0 / 4.66, 0.55, 0.55))
	# The shaft up to the hall's floor: the brick piece, squat, on its four sides.
	var sh := -0.26 - CEIL_Y
	if wall_mesh != null:
		for d: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
			var mi := MeshInstance3D.new()
			mi.name = "Shaft"
			mi.mesh = wall_mesh
			mi.transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)).scaled(
				Vector3(SHAFT * 2.0 / 5.19, sh / 3.5, 0.3)), d * SHAFT + Vector3(0.0, CEIL_Y, 0.0))
			_room.add_child(mi)
	# The light that comes down the shaft from the hall.
	var down := SpotLight3D.new()
	down.name = "ShaftLight"
	down.light_color = Color(1.0, 0.72, 0.48)
	down.light_energy = 1.6
	down.spot_range = 5.0
	down.spot_angle = 42.0
	down.shadow_enabled = false
	down.light_cull_mask = POWER_LAYER
	down.rotation.x = -PI * 0.5
	down.position = Vector3(0.0, -0.3, 0.0)
	_room.add_child(down)


## The machine round the walls (note 98's pieces, unused since note 99), its
## cables up into the ceiling, and the candles by the ladder.
func _build_machine() -> void:
	var f := FLOOR_Y
	var coil := _piece("galvanic", _room, Vector3(-2.75, f, 2.3), PI * 0.5, true, 0.94)
	_glow_mats.append_array(Table.glow(coil, 0.5))
	_solid(Vector3(1.1, 2.4, 1.2), Vector3(-2.75, f + 1.2, 2.3))
	var coil2 := _piece("galvanic", _room, Vector3(2.75, f, 6.2), -PI * 0.5, true, 0.94)
	_glow_mats.append_array(Table.glow(coil2, 0.5))
	_solid(Vector3(1.1, 2.4, 1.2), Vector3(2.75, f + 1.2, 6.2))
	_piece("pistons", _room, Vector3(2.85, f, 2.1), -PI * 0.5, true, 0.74)
	_solid(Vector3(1.0, 2.5, 2.0), Vector3(2.85, f + 1.25, 2.1))
	var core := _piece("column", _room, Vector3(-2.8, f, 6.6), 0.0, true, 0.74)
	_glow_mats.append_array(Table.glow(core, 0.9))
	_solid(Vector3(0.9, 2.4, 0.9), Vector3(-2.8, f + 1.2, 6.6))
	_piece("leverbox", _room, Vector3(2.9, f, 4.3), -PI * 0.5, true, 0.9)
	_solid(Vector3(0.7, 2.0, 1.0), Vector3(2.9, f + 1.0, 4.3))
	# The flywheel and its gear on the far wall, turning while it runs.
	_flywheel = _piece("flywheel", _room, Vector3(-0.9, f + 1.32, FRONT - 0.32), PI, true, 1.0)
	_gear = _piece("gear", _room, Vector3(0.82, f + 1.75, FRONT - 0.3), PI, true, 1.0)
	_solid(Vector3(3.6, 2.4, 0.6), Vector3(0.0, f + 1.3, FRONT - 0.3))
	# Cables from the machines up through the ceiling.
	for at: Vector3 in [Vector3(-2.75, 0.0, 2.3), Vector3(2.75, 0.0, 6.2), Vector3(-2.8, 0.0, 6.6)]:
		_cable(Vector3(at.x, f + 2.35, at.z), CEIL_Y)
	# The candles by the ladder: the only light once the crystal is out.
	var cand := _piece("candelabra", _room, Vector3(-1.25, f, 0.05), PI * 0.5, true, 0.95)
	Table.glow(cand, 1.2)
	_candle = OmniLight3D.new()
	_candle.name = "Candles"
	_candle.light_color = Color(1.0, 0.66, 0.36)
	_candle.light_energy = 1.3
	_candle.omni_range = 6.0
	_candle.omni_attenuation = 1.2
	_candle.shadow_enabled = false
	_candle.light_cull_mask = POWER_LAYER
	_candle.position = Vector3(0.0, 1.9, 0.0)
	cand.add_child(_candle)


## A run of the kit's cable straight up from `from` to the ceiling at `top`.
func _cable(from: Vector3, top: float) -> void:
	var length := top - from.y
	if length <= 0.05:
		return
	var c := _piece("cable", _room, from + Vector3(0.0, length * 0.5, 0.0), 0.0, true, 1.0)
	c.scale = Vector3(1.0, length, 1.0)


## The crystal upright on the gear laid flat, the two clamps gripping it, their
## cables up into the ceiling, its light.
func _build_crystal() -> void:
	var at := CRYSTAL_AT + Vector3(0.0, FLOOR_Y, 0.0)
	var base := _piece("gear", _room, at + Vector3(0.0, 0.1, 0.0), 0.0, true, 1.35)
	base.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	for s: float in [-1.0, 1.0]:
		var clamp := _piece("clampmount", _room, at + Vector3(s * CLAMP_X, 0.0, 0.0), -s * PI * 0.5, true, 0.6)
		_glow_mats.append_array(Table.glow(clamp, 0.15))
		_cable(at + Vector3(s * (CLAMP_X + 0.25), 1.62, 0.0), CEIL_Y)
	_solid(Vector3(2.2, 1.7, 1.4), at + Vector3(0.0, 0.85, 0.0))
	_crystal = _piece("crystal", _room, at + Vector3(0.0, 0.2, 0.0), 0.3, true, 0.86)
	_crystal_mats = Table.glow(_crystal, 0.55)
	_crystal_light = OmniLight3D.new()
	_crystal_light.name = "CrystalLight"
	_crystal_light.light_color = CRYSTAL_COLOUR
	_crystal_light.light_energy = 2.6
	_crystal_light.omni_range = 7.5
	_crystal_light.omni_attenuation = 1.1
	_crystal_light.light_specular = 0.4
	_crystal_light.shadow_enabled = false
	_crystal_light.light_cull_mask = POWER_LAYER
	_crystal_light.position = at + Vector3(0.0, 1.2, 0.0)
	_room.add_child(_crystal_light)


## The ladder: the kit's rail stood on end against the back wall, its hanging
## rings the rungs, from the floor up the shaft to the hall's flags.
func _build_ladder() -> void:
	_ladder = Node3D.new()
	_ladder.name = "Ladder"
	_room.add_child(_ladder)
	var length := -0.05 - FLOOR_Y
	var rail := _piece("track", _ladder, Vector3.ZERO, 0.0)
	# The rail lies along its X, rings hanging under it (-Y): X stood up, the
	# rings turned out into the room (+Z), its back against the wall.
	rail.basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)) * Basis.from_scale(Vector3(length / 4.0, 1.0, 1.0))
	_ladder.position = Vector3(0.0, FLOOR_Y + length * 0.5, BACK + 0.03)


## No light up in the dungeon reaches POWER_LAYER (run once the level's lights
## exist, and again on the way down for any made since).
func _wall_off() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().root.find_children("*", "Light3D", true, false):
		var light := n as Light3D
		if is_ancestor_of(light):
			continue
		light.light_cull_mask &= ~POWER_LAYER
		if light is DirectionalLight3D:
			light.shadow_caster_mask &= ~POWER_LAYER


# --- Running ----------------------------------------------------------------------

## The ladder's way, world: from the hole's middle toward its rungs.
func _along() -> Vector3:
	return (global_basis * Vector3(0.0, 0.0, -1.0)).normalized()


func _foot() -> Vector3:
	return global_transform * Vector3(0.0, FLOOR_Y, 0.0)


## A vat standing over the lid.
func is_covered() -> bool:
	for v in get_tree().get_nodes_in_group(&"surgery_vat"):
		var to: Vector3 = (v as Node3D).global_position - global_position
		if Vector2(to.x, to.z).length() < COVERED:
			return true
	return false


func _process(delta: float) -> void:
	# The machine turns while it runs; the crystal breathes.
	if _flywheel != null:
		var w := FLY_SPIN * _spin * delta
		_flywheel.rotate_object_local(Vector3(0.0, 0.0, 1.0), w)
		_gear.rotate_object_local(Vector3(0.0, 0.0, 1.0), -w * 1.75)
	if not crystal_gone and _crystal_light != null:
		var t := Time.get_ticks_msec() / 1000.0
		_crystal_light.light_energy = 2.6 + 0.35 * sin(t * 2.1) + 0.12 * sin(t * 13.0)
	# Drawn only while a camera is near (it is under the floor).
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var to := cam.global_position - global_position
		_room.visible = Vector2(to.x, to.z).length() < 30.0 and to.y < 4.0
	_prompts()


func _prompts() -> void:
	_player = Coop.user_for(self, _player)
	if _player == null:
		return
	if _busy or _player.get("in_cutscene") or _player.get("_dead"):
		_near_top = false
		_near_bottom = false
		_near_crystal = false
		_lid_prompt.visible = false
		_ladder_prompt.visible = false
		_crystal_prompt.visible = false
		return
	var at := _player.global_position
	var flat := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	_near_top = absf(at.y - global_position.y) < 1.2 and flat <= REACH and not is_covered() \
		and Interact.looked_at(self, REACH, 0.15, [_lid_hinge], _player)
	_lid_prompt.text = "E   Climb down" if hatch_open else "E   Open the hatch"
	_lid_prompt.visible = _near_top
	_lid_prompt.player = _player
	var foot := _foot()
	_near_bottom = absf(at.y - foot.y) < 1.2 and Vector2(at.x - foot.x, at.z - foot.z).length() <= 2.2 \
		and Interact.looked_at(_ladder, 2.6, 0.2, [], _player)
	_ladder_prompt.visible = _near_bottom
	_ladder_prompt.player = _player
	_near_crystal = not crystal_gone and absf(at.y - foot.y) < 1.2 \
		and Interact.looked_at(_crystal, 2.4, 0.15, [], _player)
	_crystal_prompt.visible = _near_crystal
	_crystal_prompt.player = _player


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _player == null or not Interact.pressed(event, _player):
		return
	if _near_top:
		get_viewport().set_input_as_handled()
		if hatch_open:
			_climb_down()
		else:
			_open_lid()
	elif _near_crystal:
		get_viewport().set_input_as_handled()
		_pull()
	elif _near_bottom:
		get_viewport().set_input_as_handled()
		_climb_up()


func _ok() -> bool:
	return is_instance_valid(_player) and not _player.get("_dead")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _fade(alpha: float, time: float) -> void:
	var hud := Coop.hud(_player)
	if hud != null and hud.has_method("fade_black"):
		hud.fade_black(alpha, time)


func _wait_black() -> void:
	var hud := Coop.hud(_player)
	var waited := 0.0
	while hud != null and hud.black_amount() < 0.99 and waited < 1.5:
		await get_tree().process_frame
		waited += get_process_delta_time()


func _abort(bars: CanvasLayer = null) -> void:
	if bars != null and is_instance_valid(bars):
		WOOD_DOOR.letterbox_out(bars)
	if is_instance_valid(_player):
		if _player.get("climbing"):
			_player.call("end_climb")
		elif _player.get("in_cutscene"):
			_player.end_cutscene()
		_player.set("hands_busy", false)
	_fade(0.0, 0.3)
	_busy = false


# --- The lid ------------------------------------------------------------------------

## Crouched to it, a heave on the ring: it comes up, past upright, and falls
## back open on its hinges with a clang.
func _open_lid() -> void:
	_busy = true
	var from := _player.global_position
	# Stand on the ring's side (-X), facing the hinges.
	var stand := global_transform * Vector3(-LIFT_STAND, 0.0, 0.0)
	stand.y = from.y
	_player.begin_cutscene(true)
	_player.set("hands_busy", true)
	var bars: CanvasLayer = WOOD_DOOR.letterbox(self)
	_player.scene_look_at(global_position, 7.0)
	if Vector2(stand.x - from.x, stand.z - from.z).length() > 0.3:
		_player.scene_walk_to(stand, 2.5)
		await _player.scene_walk_finished
	if not _ok():
		_abort(bars)
		return
	_player.scene_lean(Vector3(0.0, -0.45, -0.12), 5.0)
	_player.scene_frame(4.0, 0.0, 3.0)
	await _wait(0.4)
	# It sticks, gives a crack, then comes up hand over hand.
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(_lid_hinge, "rotation:z", -0.06, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_lid_hinge, "rotation:z", -0.02, 0.15).set_trans(Tween.TRANS_BOUNCE)
	t.tween_property(_lid_hinge, "rotation:z", -PI * 0.5, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	if not _ok():
		_lid_hinge.rotation.z = 0.0
		_abort(bars)
		return
	_player.scene_lean(Vector3(0.0, -0.1, 0.0), 4.0)
	# Over the top it goes, and falls open.
	var f := create_tween().set_ignore_time_scale(true)
	f.tween_property(_lid_hinge, "rotation:z", -LID_OPEN, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	f.tween_property(_lid_hinge, "rotation:z", -LID_OPEN + 0.08, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	f.tween_property(_lid_hinge, "rotation:z", -LID_OPEN, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await f.finished
	_player.set("_shake", maxf(float(_player.get("_shake")), 0.2))
	hatch_open = true
	_set_lid_open(true)
	_wall_off()
	# A look down the hole: a cold light at the bottom.
	_player.scene_look_at(global_position + Vector3(0.0, -2.0, 0.0), 3.0)
	await _wait(0.8)
	WOOD_DOOR.letterbox_out(bars)
	_player.end_cutscene()
	_player.set("hands_busy", false)
	_busy = false


## Restored from a save: open, no scene.
func set_open_now() -> void:
	hatch_open = true
	_lid_hinge.rotation.z = -LID_OPEN
	_set_lid_open(true)
	_wall_off.call_deferred()


# --- Climbing (manhole.gd's) ----------------------------------------------------------

func _ladder_yaw() -> float:
	var a := _along()
	return atan2(-a.x, -a.z)


func _climb(from: Vector3, to: Vector3, p0: float, p1: float) -> bool:
	var dist := from.distance_to(to)
	var total := maxf(dist * CLIMB_PACE, 0.2)
	var rungs := maxf(dist / RUNG, 1.0)
	var t := 0.0
	var side := 1.0
	var last_rung := -1
	while t < total:
		await get_tree().process_frame
		if not _ok():
			return false
		t += minf(get_process_delta_time() / maxf(Engine.time_scale, 0.001), 0.05)
		var p := clampf(t / total, 0.0, 1.0)
		var q := p * rungs
		var r := floorf(q)
		var f := r + smoothstep(0.0, 1.0, clampf((q - r) * 1.35, 0.0, 1.0))
		var k := clampf(f / rungs, 0.0, 1.0)
		_player.global_position = from.lerp(to, k)
		if int(r) != last_rung:
			last_rung = int(r)
			side = -side
			_player.scene_lean(Vector3(0.035 * side, 0.0, 0.0), 6.0)
		_player.call("climb_face", _ladder_yaw(), lerpf(p0, p1, p))
	_player.global_position = to
	return true


func _climb_down() -> void:
	_busy = true
	_wall_off()
	var top := global_position
	var along := _along()
	var stand := top - along * DOWN_STAND
	stand.y = _player.global_position.y
	_player.begin_cutscene(true)
	_player.set("hands_busy", true)
	_player.scene_look_at(top + along * LADDER_OUT, 6.0)
	if Vector2(stand.x - _player.global_position.x, stand.z - _player.global_position.z).length() > 0.25:
		_player.scene_walk_to(stand, 2.5)
		await _player.scene_walk_finished
	if not _ok():
		_abort()
		return
	_player.scene_look_at(null)
	_player.call("begin_climb")
	var on := Vector3(top.x, top.y - 0.6, top.z)
	if not await _climb(_player.global_position, on, -0.35, -0.6):
		_abort()
		return
	_fade(1.0, FADE_OUT)
	if not await _climb(on, on - Vector3(0.0, DARK_STRETCH, 0.0), -0.6, -0.45):
		_abort()
		return
	await _wait_black()
	if not _ok():
		_abort()
		return
	var foot := _foot()
	var low := foot + Vector3(0.0, LIGHT_STRETCH, 0.0)
	_player.global_position = low
	await get_tree().process_frame
	_fade(0.0, FADE_IN)
	if not await _climb(low, foot, -0.3, 0.05):
		_abort()
		return
	if not await _climb(foot, foot - along * 0.7 + Vector3(0.0, 0.02, 0.0), 0.05, 0.0):
		_abort()
		return
	_player.call("end_climb")
	_busy = false


func _climb_up() -> void:
	_busy = true
	var foot := _foot()
	var along := _along()
	var stand := foot - along * 0.7
	stand.y = _player.global_position.y
	_player.begin_cutscene(true)
	_player.set("hands_busy", true)
	_player.scene_look_at(foot + along * LADDER_OUT + Vector3(0.0, 1.5, 0.0), 6.0)
	if Vector2(stand.x - _player.global_position.x, stand.z - _player.global_position.z).length() > 0.25:
		_player.scene_walk_to(stand, 2.5)
		await _player.scene_walk_finished
	if not _ok():
		_abort()
		return
	_player.scene_look_at(null)
	_player.call("begin_climb")
	if not await _climb(_player.global_position, foot, 0.1, 0.35):
		_abort()
		return
	_fade(1.0, FADE_OUT)
	if not await _climb(foot, foot + Vector3(0.0, LIGHT_STRETCH * 0.6, 0.0), 0.35, 0.55):
		_abort()
		return
	await _wait_black()
	if not _ok():
		_abort()
		return
	# Black: while no one can see, the booth is emptied if the crystal is out --
	# and he waits for them beside the hatch (note 109: `ambush`, below).
	var ambush := false
	if crystal_gone and not surgeon_gone:
		ambush = _surgeon_leaves(true)
	var top := global_position
	var under := Vector3(top.x, top.y - 0.6 - DARK_STRETCH, top.z)
	_player.global_position = under
	await get_tree().process_frame
	_fade(0.0, FADE_IN)
	if not await _climb(under, Vector3(top.x, top.y - 0.6, top.z), 0.55, 0.3):
		_abort()
		return
	# Up and over the rim beyond the ladder.
	var off := top + along * (HOLE_R + 0.62) + Vector3(0.0, 0.05, 0.0)
	if not await _climb(Vector3(top.x, top.y - 0.6, top.z), off, 0.3, -0.1):
		_abort()
		return
	_player.call("end_climb")
	_busy = false
	if ambush and control != null:
		control.call("ambush", _player)


## `by_hatch` (note 109): he waits beside it, for the ambush, facing it.
func _surgeon_leaves(by_hatch := false) -> bool:
	surgeon_gone = true
	var came := false
	if control != null:
		if by_hatch:
			var along := _along()
			var at := global_position + along * (HOLE_R + 0.62 + 1.7)
			at.y = global_position.y
			var facing := Basis(Vector3.UP, atan2(-along.x, -along.z))
			came = bool(control.call("leave", Transform3D(facing, at)))
		else:
			came = bool(control.call("leave"))
	surgeon_left.emit()
	return came


# --- The crystal --------------------------------------------------------------------

## Pulled: set, a grip, the clamps fight it, it tears free -- and everything it
## fed dies, down here and up in the hall.
func _pull() -> void:
	_busy = true
	var at := _crystal.global_position + Vector3(0.0, 1.0, 0.0)
	var front := global_transform * (CRYSTAL_AT + Vector3(0.0, FLOOR_Y, -1.05))
	front.y = _player.global_position.y
	_player.begin_cutscene(true)
	_player.set("hands_busy", true)
	var bars: CanvasLayer = WOOD_DOOR.letterbox(self)
	_player.scene_look_at(at, 6.0)
	if Vector2(front.x - _player.global_position.x, front.z - _player.global_position.z).length() > 0.25:
		_player.scene_walk_to(front, 2.5)
		await _player.scene_walk_finished
	if not _ok():
		_abort(bars)
		return
	# Set: down a little, closer.
	_player.scene_lean(Vector3(0.0, -0.12, -0.25), 5.0)
	_player.scene_frame(8.0, 0.0, 3.0)
	await _wait(0.5)
	# The clamps fight it: it shudders, arcs leap off the jaws, the light stutters.
	var home := _crystal.position
	for k in 6:
		_crystal.position = home + Vector3(randf_range(-0.03, 0.03), 0.02 * float(k % 2), randf_range(-0.03, 0.03))
		if table != null:
			for s: float in [-1.0, 1.0]:
				table.call("_sparks", global_transform * (CRYSTAL_AT + Vector3(s * (CLAMP_X - 0.15), FLOOR_Y + 1.1, 0.0)),
					CRYSTAL_COLOUR.lightened(0.4), 10)
		_crystal_light.light_energy = 0.6 if k % 2 == 0 else 4.0
		_player.set("_shake", maxf(float(_player.get("_shake")), 0.08))
		_player.scene_lean(Vector3(0.04 * (1.0 if k % 2 == 0 else -1.0), -0.1, -0.3 + 0.08 * float(k % 2)), 9.0)
		await _wait(0.13)
	if not _ok():
		_crystal.position = home
		_abort(bars)
		return
	# It tears free, up and toward them, into their hands.
	_player.scene_lean(Vector3(0.0, 0.05, 0.12), 6.0)
	_player.set("_shake", maxf(float(_player.get("_shake")), 0.25))
	var hand: Vector3 = _crystal.get_parent().to_local(_player.global_position + Vector3(0.0, 1.0, 0.0))
	var t := create_tween().set_ignore_time_scale(true).set_parallel(true)
	t.tween_property(_crystal, "position", home + Vector3(0.0, 0.5, 0.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_crystal, "rotation:x", -0.5, 0.35)
	t.chain().tween_property(_crystal, "position", hand, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_crystal, "scale", Vector3.ONE * 0.2, 0.3)
	await t.finished
	_crystal.visible = false
	_take_crystal(false)
	if _player.has_method("add_item"):
		_player.call("add_item", &"power_crystal", 1)
	# Overhead, the claw comes down out of the air: dust off the ceiling, a boom.
	await _wait(0.5)
	_player.set("_shake", maxf(float(_player.get("_shake")), 0.5))
	_ceiling_dust()
	_player.scene_look_at(global_transform * Vector3(0.0, CEIL_Y, 3.0), 2.5)
	await _wait(1.6)
	WOOD_DOOR.letterbox_out(bars)
	_player.end_cutscene()
	_player.set("hands_busy", false)
	var hud := Coop.hud(_player)
	if hud != null and hud.has_method("_show_toast"):
		hud.call("_show_toast", "Power Crystal")
	_busy = false


## The crystal out: the room dark but the candles, the machine running down,
## and the hall's machine with it. `now`: a save, no fading.
func _take_crystal(now: bool) -> void:
	crystal_gone = true
	if now:
		_crystal.visible = false
		_crystal_light.light_energy = 0.0
		_spin = 0.0
		for m in _glow_mats:
			(m as StandardMaterial3D).emission_energy_multiplier = 0.0
	else:
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_crystal_light, "light_energy", 0.0, 0.4)
		tw.tween_property(self, "_spin", 0.0, 3.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		for m in _glow_mats:
			tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.8)
	if table != null and not bool(table.call("is_depowered")):
		table.call("power_off", &"crystal")
	if control != null:
		control.call("power_cut", now)
	crystal_taken.emit()


func _ceiling_dust() -> void:
	var p := CPUParticles3D.new()
	p.name = "CeilingDust"
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 40
	p.lifetime = 2.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(HALF_W * 0.9, 0.05, (FRONT - BACK) * 0.45)
	p.direction = Vector3.DOWN
	p.spread = 15.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0.0, -1.5, 0.0)
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.5
	p.color = Color(0.45, 0.4, 0.34, 0.5)
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_texture = FX_DUST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	quad.material = m
	p.mesh = quad
	p.layers = POWER_LAYER
	_room.add_child(p)
	p.position = Vector3(0.0, CEIL_Y - 0.1, (BACK + FRONT) * 0.5)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


# --- Saving ----------------------------------------------------------------------

## A save with the crystal out (and, if they had climbed out since, the surgeon
## gone).
func set_taken_now(gone: bool) -> void:
	_take_crystal(true)
	if gone:
		surgeon_gone = true
		if control != null:
			control.call("leave")
