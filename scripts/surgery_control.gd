extends Node3D

## The surgery's CONTROL ROOM and its SURGEON (2026-10-22, note 99; 102; 104;
## 105). Built by surgery.gd in its plan frame, up against the -X wall over the
## INTAKE: a timber booth on an iron platform at BOOTH_FLOOR -- leaded windows
## over the hall and at its far end (note 101's glazing), a door at its near
## end onto a LANDING in the hall's corner, a plank roof -- on oak posts. In it
## the CONSOLE, the master LEVER, and the SURGEON at the console
## (models/surgery/surgeon.glb, the Meshy-rigged character; a boss body of his
## own, surgeon_boss.gd).
##
## Two ways to switch the machine off, and both end with him to fight
## (note 105):
## - THE BOOTH: up onto the table, across the vats, a jump from a vat shoved up
##   to the landing; E at the door (`_storm`): the kick throws the door in and
##   him out of the far window onto the flags; E at the lever (`_pull_lever`):
##   the machine dies and he gets up (`surgeon_rises`).
## - THE CRYSTAL (surgery_power.gd): `power_cut` -- his lamps die, he turns from
##   the window; `leave` -- done while the player climbs out with the screen
##   black: he has come down into the hall, the door left open, and waits.

const KIT := {
	"platform": preload("res://models/surgery/platform.glb"),
	"boothwindow": preload("res://models/surgery/boothwindow.glb"),
	"boothdoorwall": preload("res://models/surgery/boothdoorwall.glb"),
	"door": preload("res://models/surgery/door.glb"),
	"console": preload("res://models/surgery/console.glb"),
	"beam": preload("res://models/surgery/beam.glb"),
	"leverbox": preload("res://models/surgery/leverbox.glb"),
	"handle": preload("res://models/surgery/handle.glb"),
}
const PLANKS := preload("res://textures/surgery_planks.png")
const WOOD_DOOR := preload("res://scripts/wood_door.gd")
const DEBRIS := preload("res://scripts/door_debris.gd")
const Vat := preload("res://scripts/surgery_vat.gd")
const Table := preload("res://scripts/surgical_table.gd")

## The booth's floor (its top) and its walls' height.
const BOOTH_FLOOR := 2.9
## The window band (note 108: the walls go on up to `_top`, the hall's roof).
const BOOTH_H := 2.3
## The door (note 108): the dungeon's door leaf, its size -- 1.94 wide, 4.2 to
## the point of its head -- drawn LEAF_DEPTH thick.
const DOOR_W := 1.94
const DOOR_H := 4.2
const LEAF_DEPTH := 0.3
const BrickLevel := preload("res://scripts/brick_level.gd")
const MODULE_LEVEL := preload("res://scripts/module_level.gd")
## Gone, he left the door this far open (radians).
const DOOR_LEFT_OPEN := 1.5
## The kick (as note 99's): squaring up, the rush, the slow motion as it bursts.
const TURN_TIME := 0.3
const RUSH_TIME := 0.2
const SLOWMO := 0.3
const SLOWMO_TIME := 0.3
## The lever (note 105): the kit's lever box, scaled to the booth, its handle
## this high on it, up (rest) and pulled.
const LEVER_SCALE := 0.85
const LEVER_HEIGHT := 1.42
const HANDLE_UP := -0.35
const HANDLE_DOWN := 2.4
const BOSS := preload("res://scripts/surgeon_boss.gd")

var surgery: Node3D
var table: Node3D
var _inner := 13.4
var _c := 2.98

## Built nodes.
var _booth: Node3D
## The booth's top (surgery.gd `booth_top`) and its door's height.
var _top := 6.3
var _door_h := DOOR_H
var _door: Node3D
var _door_body: StaticBody3D
var _console: Node3D
var _surgeon: Node3D
var _booth_light: OmniLight3D
var _console_mats: Array = []

var powered := true
var surgeon_gone := false
## Note 104: the door kicked in, the surgeon thrown out through the window.
var door_broken := false
var surgeon_thrown := false
var _busy := false
var _hall_pane: MeshInstance3D
var _hall_window: Node3D
var _end_pane: MeshInstance3D
## Note 105: the surgeon as a boss (surgeon_boss.gd), the lever, the prompts.
var boss: CharacterBody3D
var lever_pulled := false
var _lever: Node3D
var _handle: Node3D
var _door_prompt: Interact.Prompt
var _lever_prompt: Interact.Prompt


func setup(surgery_: Node3D, table_: Node3D, inner: float, cell: float) -> void:
	surgery = surgery_
	table = table_
	_inner = inner
	_c = cell
	_build_booth()
	_build_surgeon()
	_build_landing()
	_build_lever()


# --- The booth -------------------------------------------------------------------

## The booth's middle on its floor, plan frame.
func booth_centre() -> Vector3:
	return Vector3(-_inner + _c * 0.5, BOOTH_FLOOR, -_inner + _c * 2.0)


func _piece(name_: String, parent: Node3D, at: Vector3, yaw := 0.0) -> Node3D:
	var n: Node3D = (KIT[name_] as PackedScene).instantiate()
	Table.grade(n)
	parent.add_child(n)
	n.position = at
	n.rotation.y = yaw
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return n


func _box(parent: Node3D, size: Vector3, at: Vector3, layer := 1 | 2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	parent.add_child(body)
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	return body


func _build_booth() -> void:
	var mid := booth_centre()
	var x0 := -_inner
	var x1 := -_inner + _c
	var z0 := -_inner + _c
	var z1 := -_inner + _c * 3.0
	_top = float(surgery.call("booth_top")) if surgery != null and surgery.has_method("booth_top") else BOOTH_FLOOR + 3.4
	var wall_h := _top - BOOTH_FLOOR
	var upper := wall_h - BOOTH_H
	_booth = Node3D.new()
	_booth.name = "Booth"
	add_child(_booth)
	# The iron floor, its long side along the wall.
	_piece("platform", _booth, Vector3(mid.x, BOOTH_FLOOR, mid.z), PI * 0.5)
	_box(_booth, Vector3(_c, 0.45, _c * 2.0), Vector3(mid.x, BOOTH_FLOOR - 0.225, mid.z))
	# Oak posts under its outer corners, from the floor up to it -- and on up its
	# corners to the roof (note 108).
	for z: float in [z0 + 0.2, z1 - 0.2]:
		var post := _piece("beam", _booth, Vector3(x1 - 0.2, (BOOTH_FLOOR - 0.45) * 0.5, z))
		post.basis = Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3((BOOTH_FLOOR - 0.45) / 4.66, 0.6, 0.6))
		_box(_booth, Vector3(0.35, BOOTH_FLOOR - 0.45, 0.35), Vector3(x1 - 0.2, (BOOTH_FLOOR - 0.45) * 0.5, z))
		var up := _piece("beam", _booth, Vector3(x1 - 0.12, BOOTH_FLOOR + wall_h * 0.5, z - 0.08 if z > mid.z else z + 0.08))
		up.basis = Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3(wall_h / 4.66, 0.5, 0.5))
	# The leaded windows over the hall, in a band at the bottom; plank wall over
	# them up to the roof.
	var win := _piece("boothwindow", _booth, Vector3(x1 - 0.125, BOOTH_FLOOR, mid.z), PI * 0.5)
	win.scale = Vector3(1.0, BOOTH_H / 2.5, 1.0)
	_glaze(win)
	_hall_window = win
	_hall_pane = win.get_node_or_null("Pane") as MeshInstance3D
	_box(_booth, Vector3(0.25, BOOTH_H, _c * 2.0), Vector3(x1 - 0.125, BOOTH_FLOOR + BOOTH_H * 0.5, mid.z))
	_planks(Vector3(0.25, upper, _c * 2.0), Vector3(x1 - 0.125, BOOTH_FLOOR + BOOTH_H + upper * 0.5, mid.z))
	# The far end: a narrower leaded window, planks over it.
	var end := _piece("boothwindow", _booth, Vector3(mid.x, BOOTH_FLOOR, z1 - 0.125), 0.0)
	end.scale = Vector3(_c / 5.94, BOOTH_H / 2.5, 1.0)
	_glaze(end)
	_end_pane = end.get_node_or_null("Pane") as MeshInstance3D
	_box(_booth, Vector3(_c, BOOTH_H, 0.25), Vector3(mid.x, BOOTH_FLOOR + BOOTH_H * 0.5, z1 - 0.125))
	_planks(Vector3(_c, upper, 0.25), Vector3(mid.x, BOOTH_FLOOR + BOOTH_H + upper * 0.5, z1 - 0.125))
	# The door's end, onto the landing (note 108: "make the door the size of all
	# the other ones"): a plank wall the booth's height with the dungeon's own
	# door leaf in it (brick kit `door_leaf`, 1.94 x 4.2 with its pointed head),
	# the wall cut to the leaf's outline (`_door_wall`).
	_door_h = minf(DOOR_H, wall_h - 0.2)
	_door_wall(Vector3(mid.x, BOOTH_FLOOR, z0 + 0.125), wall_h)
	_door = Node3D.new()
	_door.name = "Door"
	_booth.add_child(_door)
	_door.position = Vector3(mid.x, BOOTH_FLOOR, z0 + 0.125)
	_door.rotation.y = PI
	var leaf := MeshInstance3D.new()
	leaf.name = "Leaf"
	leaf.mesh = BrickLevel.standalone("door_leaf")
	if leaf.mesh != null:
		# The leaf is drawn 0.16-1.0 m behind its stone face: centred on the wall
		# and thinned to a plank door's depth.
		var aabb := leaf.mesh.get_aabb()
		var k := Vector3(DOOR_W / aabb.size.x, _door_h / aabb.size.y, LEAF_DEPTH / aabb.size.z)
		leaf.scale = k
		leaf.position = Vector3(-aabb.get_center().x * k.x, 0.0, -aabb.get_center().z * k.z)
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_door.add_child(leaf)
		var backing := MeshInstance3D.new()
		backing.name = "Backing"
		backing.mesh = MODULE_LEVEL._leaf_backing_mesh(aabb.get_center().z)
		backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.add_child(backing)
	_door_body = _box(_door, Vector3(DOOR_W, _door_h, 0.3), Vector3(0.0, _door_h * 0.5, 0.0))
	# The plank roof, seen from inside and out.
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_c, _c * 2.0)
	roof.mesh = plane
	roof.material_override = _plank_mat()
	_booth.add_child(roof)
	roof.position = Vector3(mid.x, _top, mid.z)
	_box(_booth, Vector3(_c, 0.1, _c * 2.0), Vector3(mid.x, _top + 0.05, mid.z))
	# The console, its levers toward the wall where he stands, the window beyond.
	_console = _piece("console", _booth, Vector3(x1 - 0.85, BOOTH_FLOOR, mid.z), -PI * 0.5)
	_console_mats = Table.glow(_console, 0.8)
	_box(_booth, Vector3(0.8, 1.1, 2.2), Vector3(x1 - 0.85, BOOTH_FLOOR + 0.55, mid.z))
	# His lamp: warm, behind him -- he is a shape against it from the hall.
	_booth_light = OmniLight3D.new()
	_booth_light.name = "BoothLamp"
	_booth_light.light_color = Color(1.0, 0.7, 0.42)
	_booth_light.light_energy = 1.6
	_booth_light.omni_range = 4.5
	_booth_light.omni_attenuation = 1.2
	_booth_light.shadow_enabled = false
	_booth.add_child(_booth_light)
	_booth_light.position = Vector3(x0 + 0.5, BOOTH_FLOOR + 2.0, mid.z)


## The booth's planks (the hall's ceiling planks, triplanar), one material.
static var _planks_material: StandardMaterial3D


static func _plank_mat() -> StandardMaterial3D:
	if _planks_material == null:
		var m := StandardMaterial3D.new()
		m.albedo_texture = PLANKS
		m.albedo_color = Color(0.6, 0.52, 0.46)
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.4, 0.4, 0.4)
		_planks_material = m
	return _planks_material


## A plank wall `size` at `at` (plan frame): drawn and solid.
func _planks(size: Vector3, at: Vector3) -> void:
	if size.y <= 0.01:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _plank_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_booth.add_child(mi)
	mi.position = at
	_box(_booth, size, at)


## The door's end: a plank wall `height` tall across the booth's width at `at`
## (its foot, plan frame), with the door leaf's outline cut out of it -- straight
## sides to 3.05 of its 4.25 m, then the pointed head (tools/build_brick_kit.py
## DOOR_LEAF_HEAD), scaled to the door's height. CSG, solid where it stands.
func _door_wall(at: Vector3, height: float) -> void:
	var wall := CSGCombiner3D.new()
	wall.name = "DoorWall"
	wall.use_collision = true
	wall.collision_layer = 1 | 2
	wall.collision_mask = 0
	_booth.add_child(wall)
	wall.position = at
	var slab := CSGBox3D.new()
	slab.size = Vector3(_c, height, 0.25)
	slab.position = Vector3(0.0, height * 0.5, 0.0)
	slab.material = _plank_mat()
	wall.add_child(slab)
	var cut := CSGPolygon3D.new()
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	var k := _door_h / 4.25
	var pts := PackedVector2Array()
	var head: Array = [[3.05, 0.97], [3.25, 0.89], [3.45, 0.74], [3.65, 0.59], [3.85, 0.46], [4.05, 0.24], [4.25, 0.0]]
	var right := PackedVector2Array([Vector2(DOOR_W * 0.5 + 0.02, -0.1)])
	for h in head:
		right.append(Vector2((float(h[1]) / 0.97) * (DOOR_W * 0.5 + 0.02), float(h[0]) * k))
	for p in right:
		pts.append(p)
	for i in range(right.size() - 2, -1, -1):
		pts.append(Vector2(-right[i].x, right[i].y))
	cut.polygon = pts
	cut.depth = 0.6
	cut.position = Vector3(0.0, 0.0, 0.3)
	cut.material = _plank_mat()
	wall.add_child(cut)


## The window's glazing (note 101). The kit's split-off "Glass" holds the
## mullions and lancet tracery as well as the panes, and the panes are not flat
## -- Tripo's surface, crumpled, with the lead painted on in a smeared atlas --
## so drawn see-through it glittered like foil and showed nothing clearly. Now
## the pane faces (flat-on, within PANE_DEPTH of the middle) are taken out, the
## ironwork left opaque in its own picture, and behind it one FLAT pane of the
## Higgsfield leaded-glass picture (shaders/surgery_glass.gdshader): crisp lead
## cames, the quarries between them nearly clear.
const PANE_DEPTH := 0.045
## The opening behind the tracery, model frame (the Glass part's extent).
const PANE_X := 2.57
const PANE_Y := Vector2(0.81, 2.33)
const GLASS_PIC := preload("res://textures/surgery_glass.png")
const GLASS_SHADER := preload("res://shaders/surgery_glass.gdshader")
static var _tracery := {}


func _glaze(win: Node3D) -> void:
	for node in win.find_children("Glass*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var key := mi.mesh.get_instance_id()
		if not _tracery.has(key):
			_tracery[key] = _without_panes(mi.mesh)
		mi.mesh = _tracery[key]
	var pane := MeshInstance3D.new()
	pane.name = "Pane"
	var quad := QuadMesh.new()
	quad.size = Vector2(PANE_X * 2.0, PANE_Y.y - PANE_Y.x)
	pane.mesh = quad
	var m := ShaderMaterial.new()
	m.shader = GLASS_SHADER
	m.set_shader_parameter("pic", GLASS_PIC)
	m.set_shader_parameter("scale", Vector2(win.scale.x, win.scale.y))
	pane.material_override = m
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	win.add_child(pane)
	pane.position = Vector3(0.0, (PANE_Y.x + PANE_Y.y) * 0.5, 0.0)


## `mesh` without its flat-on faces near the middle plane: the ironwork alone.
static func _without_panes(mesh: Mesh) -> Mesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if v.is_empty() or idx.is_empty():
			# The headless dummy renderer keeps no mesh data: leave it whole.
			return mesh
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var a := v[idx[t]]
			var b := v[idx[t + 1]]
			var c := v[idx[t + 2]]
			var n := (b - a).cross(c - a).normalized()
			if absf(n.z) > 0.8 and absf((a.z + b.z + c.z) / 3.0) < PANE_DEPTH:
				continue
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		arr[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


# --- The surgeon ------------------------------------------------------------------

## He is a body (surgeon_boss.gd, note 105) with the Meshy model under it, at his
## console, working.
func _build_surgeon() -> void:
	var mid := booth_centre()
	boss = CharacterBody3D.new()
	boss.set_script(BOSS)
	boss.name = "Surgeon"
	boss.set("surgery", surgery)
	_booth.add_child(boss)
	boss.position = Vector3(-_inner + 1.25, BOOTH_FLOOR, mid.z)
	boss.rotation.y = PI * 0.5
	# His body is his own now (note 109: a stand-in, surgeon_boss.gd), at work.
	_surgeon = boss
	boss.call("pose", &"work")


## Where he stands to fight, in the hall below the booth's far window, facing
## the middle (world): where the kick throws him (`_landing_spot`).
func _boss_spot() -> Transform3D:
	var at := global_transform * _landing_spot()
	var to := surgery.global_position - at
	return Transform3D(Basis(Vector3.UP, atan2(to.x, to.z)), at)


# --- The power cut, and after ---------------------------------------------------

## The crystal is out: the console's lamps die, his lamp gutters and stays low.
## He stops at his levers, turned to the window. `now`: a save, no flicker.
func power_cut(now := false) -> void:
	if not powered:
		return
	powered = false
	if now:
		for m in _console_mats:
			(m as StandardMaterial3D).emission_energy_multiplier = 0.0
		_booth_light.light_energy = 0.35
	else:
		var tw := create_tween().set_parallel(true)
		for m in _console_mats:
			tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.6)
		var lt := create_tween()
		for k in 4:
			lt.tween_property(_booth_light, "light_energy", 0.2 if k % 2 == 0 else 1.2, 0.08)
		lt.tween_property(_booth_light, "light_energy", 0.35, 0.4)
	if not surgeon_thrown:
		boss.call("pose", &"alert")


## The crystal route (the player climbing out of the powering room, the screen
## black): he has come down out of his booth -- the door left standing open
## behind him -- and waits in the hall to fight (note 105; note 102 had him
## simply gone).
## `at` (world; note 109): where he waits for them -- beside the hatch, for the
## ambush (`ambush`) as they climb out; none: at his spot, to fight. True if he
## did come down.
func leave(at := Transform3D.IDENTITY) -> bool:
	if surgeon_thrown or surgeon_gone:
		return false
	surgeon_gone = true
	power_cut(true)
	_swing_door_open()
	_down_to_the_hall()
	if at == Transform3D.IDENTITY:
		_arm_him()
		boss.call("wait_at", _boss_spot())
	else:
		boss.call("script_on")
		boss.global_transform = at
		boss.call("pose", &"stand")
	return true


func _swing_door_open() -> void:
	if door_broken:
		return
	# Swung on its edge (the model's -X), not about its middle.
	var edge := Vector3(-DOOR_W * 0.5, 0.0, 0.0)
	var pivot := _door.transform * edge
	_door.rotation.y = PI + DOOR_LEFT_OPEN
	_door.position = pivot - _door.basis * edge
	_door_body.collision_layer = 0


## His body out of the booth into the hall's frame, keeping where it is.
func _down_to_the_hall() -> void:
	if boss.get_parent() == surgery:
		return
	boss.reparent(surgery, true)


# --- The way in from the hall (notes 104, 105) ------------------------------------
##
## Note 104 (the user): "make the control room to where the player can push a
## vat over to it, jump on the vat, and start a cutscene where the player kicks
## the door down, throw the surgeon out of the control room down to the surgery
## room, and power off the system from the control room. The player has to start
## by jumping on the middle table, then to the vats." Note 105: "Make the
## control room lower, so the player can actually jump onto the landing by the
## control room door. Make the cutscene start when the player interacts with the
## control room door. The cutscene should be the player kicking the door down
## with such force, that it sends the surgeon out the window, and the surgeon
## lands on the ground. The player should then be able to interact with the
## lever, actually flip it, and the system powers down."
##
## The booth is at BOOTH_FLOOR 2.9: a vat's top is 1.97, so from a vat shoved up
## against the LANDING outside the door (the platform in the corner) a jump
## (1.28 m high) gets onto it. E at the door: `_storm` -- the kick bursts the door
## in and the door hits him: he goes out through the booth's far window and
## down onto the flags, where he lies. Then the LEVER at the back of the booth:
## E flips it (`_pull_lever`), the machine dies, and he gets up to fight
## (surgeon_boss.gd).

## The landing outside the door, over the hall's corner cell, at the booth's
## floor: the kit's platform, an oak post under its outer corner.
func _build_landing() -> void:
	var x0 := -_inner
	var x1 := -_inner + _c
	var z0 := -_inner
	var z1 := -_inner + _c
	var mid := Vector3((x0 + x1) * 0.5, BOOTH_FLOOR, (z0 + z1) * 0.5)
	var plat := _piece("platform", _booth, mid, PI * 0.5)
	plat.scale = Vector3(0.5, 1.0, 1.0)
	_box(_booth, Vector3(_c, 0.45, _c), Vector3(mid.x, BOOTH_FLOOR - 0.225, mid.z))
	var post := _piece("beam", _booth, Vector3(x1 - 0.2, (BOOTH_FLOOR - 0.45) * 0.5, z0 + 0.2))
	post.basis = Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3((BOOTH_FLOOR - 0.45) / 4.66, 0.6, 0.6))
	_box(_booth, Vector3(0.35, BOOTH_FLOOR - 0.45, 0.35), Vector3(x1 - 0.2, (BOOTH_FLOOR - 0.45) * 0.5, z0 + 0.2))
	_door_prompt = Interact.prompt("E   Kick in", Vector3(0.0, 1.1, 0.0))
	_door.add_child(_door_prompt)


## The master lever: the kit's lever box (note 98's) against the booth's back
## wall at its far end, facing in; its handle up.
func _build_lever() -> void:
	var z1 := -_inner + _c * 3.0
	_lever = Node3D.new()
	_lever.name = "Lever"
	_booth.add_child(_lever)
	_lever.transform = Transform3D(Basis.looking_at(Vector3(-1.0, 0.0, 0.0), Vector3.UP), Vector3(-_inner + 0.42, BOOTH_FLOOR, z1 - 0.85))
	var box := _piece("leverbox", _lever, Vector3.ZERO)
	box.scale = Vector3.ONE * LEVER_SCALE
	_box(_lever, Vector3(0.7, 2.2, 0.8) * LEVER_SCALE, Vector3(0.0, 1.1 * LEVER_SCALE, 0.0))
	_handle = Node3D.new()
	_handle.name = "Handle"
	_lever.add_child(_handle)
	_handle.position = Vector3(0.0, LEVER_HEIGHT, 0.45) * LEVER_SCALE
	var h := _piece("handle", _handle, Vector3.ZERO)
	h.scale = Vector3.ONE * LEVER_SCALE
	_handle.rotation.x = HANDLE_UP
	_lever_prompt = Interact.prompt("E   Pull the lever", _handle.position)
	_lever.add_child(_lever_prompt)


func _process(_delta: float) -> void:
	if not _looking.is_empty():
		_process_look()
	var down := table == null or bool(table.call("is_depowered"))
	var kicker: Node = null
	if not _busy and not door_broken and not down and not surgeon_gone:
		kicker = Interact.chooser(_door, 2.4, 1.6, 3.0, 0.15)
	_door_prompt.visible = kicker != null
	_door_prompt.player = kicker
	var puller: Node = null
	if not _busy and door_broken and not down and not lever_pulled:
		puller = Interact.chooser(_lever, 2.2, 1.6, 3.0, 0.12, [_handle])
	_lever_prompt.visible = puller != null
	_lever_prompt.player = puller


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if _door_prompt.visible and Interact.pressed(event, _door_prompt.player):
		get_viewport().set_input_as_handled()
		_storm(_door_prompt.player as Node3D)
		return
	if _lever_prompt.visible and Interact.pressed(event, _lever_prompt.player):
		get_viewport().set_input_as_handled()
		_pull_lever()


func _tween() -> Tween:
	return create_tween().set_parallel(true).set_ignore_time_scale(true)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _surgeon_head() -> Vector3:
	return boss.global_position + Vector3(0.0, 1.6, 0.0)


## The kick: the door in, so hard it takes him out of the far window -- one
## scene, the player untouchable in it. Control back once he is down.
func _storm(p: Node3D) -> void:
	if p == null or _busy or door_broken:
		return
	_busy = true
	_door_prompt.visible = false
	p.call("begin_cutscene")
	p.set("hands_busy", true)
	var bars := WOOD_DOOR.letterbox(self)
	# Through the door: the booth's +Z in the world (the door faces the landing).
	var into := (global_basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var door_at := _door.global_position

	# 1. Square up to the door, a step back.
	var base := Vector3(door_at.x, p.global_position.y, door_at.z)
	var windup := base - into * 1.6
	var strike := base - into * 0.75
	p.call("scene_look_at", door_at + Vector3(0.0, 1.1, 0.0), 6.0)
	p.call("scene_walk_to", windup, 3.0)
	await Signal(p, &"scene_walk_finished")
	p.call("scene_look_at", null)
	var yaw: float = p.rotation.y + wrapf(atan2(-into.x, -into.z) - p.rotation.y, -PI, PI)
	var t := _tween()
	t.tween_property(p, "rotation:y", yaw, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(p, "_look_pitch", -0.05, TURN_TIME)
	await t.finished

	# 2. The kick.
	var maker := WOOD_DOOR.new()
	var leg: Node3D = maker._make_leg(p)
	maker.free()
	p.set("_dash_view", 1.0)
	t = _tween()
	t.tween_property(p, "global_position", strike, RUSH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(p, "_look_pitch", -0.2, RUSH_TIME)
	t.tween_property(leg, "rotation:x", 0.9, RUSH_TIME * 0.65).set_trans(Tween.TRANS_SINE)
	t.chain().tween_property(leg, "rotation:x", WOOD_DOOR.LEG_STRIKE, RUSH_TIME * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished

	# 3. The door bursts in, slow motion, and takes him with it: out through
	# the far window and down.
	_burst_door(into)
	p.set("_land_kick", 1.0)
	p.set("_land_strength", 0.6)
	Engine.time_scale = SLOWMO
	p.call("scene_look_at", _surgeon_head(), 9.0)
	_fling_surgeon(p)
	await _wait(SLOWMO_TIME)
	Engine.time_scale = 1.0
	t = _tween()
	t.tween_property(leg, "rotation:x", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	leg.queue_free()
	p.set("hands_busy", false)
	# Watching him go: through the window, onto the flags.
	while bool(boss.get("state") == BOSS.State.FLUNG):
		p.call("scene_look_at", boss.global_position + Vector3(0.0, 1.0, 0.0), 8.0)
		await get_tree().process_frame
	await _wait(0.9)
	_end_scene(p, bars)


func _end_scene(p: Node3D, bars: CanvasLayer) -> void:
	if bars != null and is_instance_valid(bars):
		WOOD_DOOR.letterbox_out(bars)
	if is_instance_valid(p):
		p.set("hands_busy", false)
		p.call("scene_look_at", null)
		if p.get("in_cutscene") == true:
			p.call("end_cutscene")
	_busy = false


## The door gives: in pieces, into the booth, in a cloud.
func _burst_door(into: Vector3) -> void:
	door_broken = true
	# No one at the console now: the claw stops hunting (note 106).
	if table != null:
		table.call("operator_gone")
	_door_body.collision_layer = 0
	var impact := _door.global_position + Vector3(0.0, 1.1, 0.0)
	var pieces: Array = []
	for node in _door.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		pieces.append_array(DEBRIS.shatter(mi, self, into * 2.2, impact, 4 if Graphics.effects else 3, 6 if Graphics.effects else 3, 0.35, false))
		mi.visible = false
	DEBRIS.crumble(pieces, Graphics.effects)
	if Graphics.effects:
		DEBRIS.dust(self, impact, into)


## Where he lands in the hall: out from the booth's far window (plan frame) --
## the first of a few spots there clear of the vats (one landed against a vat
## and stood stuck behind it).
func _landing_spot() -> Vector3:
	var base := Vector3(-_inner + 1.25, 0.0, -_inner + _c * 3.0 + 2.6)
	for off: Vector3 in [Vector3.ZERO, Vector3(0.0, 0.0, 1.2), Vector3(1.3, 0.0, 0.6), Vector3(0.0, 0.0, 2.4),
			Vector3(1.6, 0.0, 1.8), Vector3(2.6, 0.0, 0.4), Vector3(2.6, 0.0, 2.4)]:
		var at := base + off
		var w := global_transform * at
		var clear := true
		for v in surgery.get("vats"):
			var vat := v as Node3D
			var r: float = vat.get("radius")
			if Vector2(vat.global_position.x - w.x, vat.global_position.z - w.z).length() < r + 0.7:
				clear = false
				break
		if clear:
			return at
	return base


## The door's blow throws him the length of the booth, through the leaded glass
## of its far window in a burst of it, and down onto the flags, where he lies.
func _fling_surgeon(_p: Node3D) -> void:
	surgeon_thrown = true
	boss.set("state", BOSS.State.FLUNG)
	_down_to_the_hall()
	var start := boss.global_position
	var through := global_transform * Vector3(-_inner + 1.25, BOOTH_FLOOR + 0.9, -_inner + _c * 3.0)
	var land := global_transform * _landing_spot()
	var spin := boss.rotation
	boss.call("play", &"die", 0.05, 1.5)
	var t := _tween()
	t.tween_method(func(k: float) -> void:
		var a := start.lerp(through, k)
		a.y += sin(k * PI) * 0.35
		boss.global_position = a, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	_break_window(through, (through - start).normalized())
	t = _tween()
	t.tween_method(func(k: float) -> void:
		var a := through.lerp(land, k)
		a.y = lerpf(through.y, land.y, k * k) + sin(k * PI) * 0.5
		boss.global_position = a, 0.0, 1.0, 0.65)
	t.tween_property(boss, "rotation", spin + Vector3(0.0, 0.6, 0.0), 0.65)
	await t.finished
	if table != null:
		table.call("_impact_fx", land, 0.45)
	for q in Coop.all():
		var n := q as Node3D
		if n != null and n.get("_shake") != null:
			n.set("_shake", maxf(float(n.get("_shake")), 0.3))
	boss.call("lie_down")
	_booth_light.light_energy = 0.8


## The far window's glass bursts out (the lead tracery stays): its pane gone,
## a spray of glass out over the hall along `dir`.
func _break_window(at: Vector3, dir: Vector3) -> void:
	if _end_pane != null:
		_end_pane.visible = false
	if table != null:
		table.call("_sparks", at, Color(0.75, 0.85, 0.9), 30)
	if not Graphics.effects:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 60
	p.lifetime = 1.4
	p.explosiveness = 0.95
	p.direction = dir + Vector3(0.0, 0.3, 0.0)
	p.spread = 40.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.07)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.82, 0.85, 0.55)
	m.roughness = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	p.mesh = quad
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## E on the lever: the handle thrown down, sparks off the console, the lamps
## die, and the machine with them (the claw falls; surgery.gd then has him up).
func _pull_lever() -> void:
	if lever_pulled:
		return
	lever_pulled = true
	_lever_prompt.visible = false
	var t := create_tween()
	t.tween_property(_handle, "rotation:x", HANDLE_DOWN + 0.15, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(_handle, "rotation:x", HANDLE_DOWN, 0.12)
	await t.finished
	if table != null:
		table.call("_sparks", _handle.global_position, Color(1.0, 0.8, 0.45), 20)
	_throw_lever()


## The power off: a burst of sparks off the console, its lamps and gauges die,
## the booth's lamp gutters out, and the table's power is cut.
func _throw_lever() -> void:
	powered = false
	if table != null:
		table.call("_sparks", _console.global_transform * Vector3(0.95, 1.2, 0.0), Color(1.0, 0.8, 0.45), 40)
		table.call("power_off", &"control")
	var tw := create_tween().set_parallel(true)
	for m in _console_mats:
		tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.6)
	var lt := create_tween()
	for k in 4:
		lt.tween_property(_booth_light, "light_energy", 0.2 if k % 2 == 0 else 1.2, 0.08)
	lt.tween_property(_booth_light, "light_energy", 0.35, 0.4)


## The machine has just died: lying in the hall, he gets up (a beat later) and
## the fight is on.
## The machine has just died from the booth: once the claw has come home over
## the table, the scene -- he gets up, goes and takes it, and turns on them
## (`_claim`).
func surgeon_rises(after := 0.0) -> void:
	if boss == null or boss.call("is_dead") or boss.get("state") != BOSS.State.DOWN:
		return
	if after > 0.0:
		await _wait(after)
	var t := 0.0
	while table != null and table.get("state") != Table.State.DEAD and t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var p := Coop.nearest(boss.global_position) as Node3D
	if p != null:
		_claim(p, false)
	else:
		_arm_him()
		boss.call("begin_fight")


# --- Saving and resetting ---------------------------------------------------------

## A save with the booth taken: the door gone, the far window broken, the lever
## down, the console dark; he is in the hall, waiting or dead (`restore_boss`).
func set_thrown_now() -> void:
	door_broken = true
	surgeon_thrown = true
	lever_pulled = true
	powered = false
	_door.visible = false
	_door_body.collision_layer = 0
	if _end_pane != null:
		_end_pane.visible = false
	_handle.rotation.x = HANDLE_DOWN
	_down_to_the_hall()
	boss.call("wait_at", _boss_spot())
	for m in _console_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = 0.0
	_booth_light.light_energy = 0.35


## A save with the machine off: him dead where he fell (`at`), or waiting.
func restore_boss(dead: bool, at: Transform3D) -> void:
	_arm_him()
	if not dead:
		return
	_down_to_the_hall()
	boss.call("set_dead_now", at)


## A world reset with the machine off and him still up: whole, waiting.
func reset_boss() -> void:
	if boss == null or boss.call("is_dead"):
		return
	var s: int = boss.get("state")
	if s == BOSS.State.AT_WORK:
		# Off by the crystal, and they died before climbing out: he has come
		# down all the same.
		leave()
		return
	_arm_him()
	if s == BOSS.State.DOWN or s == BOSS.State.SCRIPTED:
		boss.call("wait_at", _boss_spot())
	else:
		boss.call("reset_wait")


## A save made after the kick but before the lever: the door gone, the far
## window broken, him lying in the hall, the claw idle (note 106).
func set_kicked_now() -> void:
	door_broken = true
	surgeon_thrown = true
	_door.visible = false
	_door_body.collision_layer = 0
	if _end_pane != null:
		_end_pane.visible = false
	_down_to_the_hall()
	boss.global_transform = Transform3D(boss.global_basis, global_transform * _landing_spot())
	boss.call("lie_down")
	boss.call("hold_end", &"die")
	if table != null:
		table.call("operator_gone")


# --- The claw taken, and the words before the fight (note 109) ----------------------
##
## The user: "There should then be 2 ways that the surgeon fight starts. The first
## should be an add on to the climb out of the underground part. The surgeon
## should knock the player down as hes climbing out of the powering room, and the
## surgeon should walk over to the table, stand on it, and take the claw off of
## the robot arm and put it on his back. The cutscene should be dramatic as the
## surgeon walks up to the player after the player was knocked down, and saying
## 'who are you' very slowly. The player should then quizically ask who the
## surgeon is, and the surgeon should say 'No matter, you will die for what
## you've done'. then starting the battle."
##
## The crystal route: `ambush` (surgery_power.gd, as they step off the ladder).
## The booth route: `surgeon_rises` (after the lever, the claw home). Both go on
## into `_claim`.

const SUBTITLES := preload("res://scripts/subtitles.gd")

## Everyone's view following him through a scene (`_follow_look`).
var _looking: Array[Node3D] = []


## The claw off the dead machine's arm and on his back -- at once (a save, a
## reset, a fight begun without the scene).
func _arm_him() -> void:
	if boss == null or bool(boss.call("has_claw")) or table == null:
		return
	var claw: Node3D = table.call("take_claw")
	if claw != null:
		boss.call("mount_claw", claw)


func _surgeon_eyes() -> Vector3:
	return boss.global_position + Vector3(0.0, 1.75, 0.0)


func _process_look() -> void:
	for n in _looking:
		if is_instance_valid(n):
			n.call("scene_look_at", _surgeon_eyes(), 4.0)


## The crystal route: as `p` steps off the ladder he is on them -- a backhand
## that puts them on the floor -- and the scene goes on (`_claim`).
func ambush(p: Node3D) -> void:
	if boss == null or boss.call("is_dead") or boss.get("state") != BOSS.State.SCRIPTED or _busy:
		return
	_busy = true
	p.call("begin_cutscene")
	boss.call("face", p.global_position)
	boss.call("pose", &"strike")
	await _wait(0.18)
	if table != null:
		table.call("_sparks", p.global_position + Vector3(0.0, 1.5, 0.0), Color(1.0, 0.8, 0.55), 18)
	p.set("_shake", 0.8)
	# Down: thrown back a stride, the view on the floor, rolled over.
	var back := p.global_position - boss.global_position
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else -p.global_basis.z
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(p, "global_position", p.global_position + back * 1.1, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	p.call("scene_lean", Vector3(0.0, -1.3, 0.35), 9.0)
	p.call("scene_frame", 0.0, 24.0, 6.0)
	p.call("scene_look_at", _surgeon_eyes(), 5.0)
	boss.call("pose", &"stand")
	await _wait(1.1)
	_busy = false
	_claim(p, true)


## He goes to the table, up onto it, takes the claw off the arm and onto his
## back, comes for them -- `knocked`: over them where they lie -- and speaks;
## then the fight.
func _claim(p: Node3D, knocked: bool) -> void:
	if _busy:
		return
	_busy = true
	var everyone: Array[Node3D] = []
	for q in Coop.all():
		var n := q as Node3D
		if n != null and n.get("_dead") != true:
			everyone.append(n)
			if n.get("in_cutscene") != true:
				n.call("begin_cutscene")
	var bars := WOOD_DOOR.letterbox(self)
	boss.call("script_on")
	_looking = everyone
	# Up off the floor (the booth route: he was out cold).
	if not knocked:
		boss.call("pose", &"crouch")
		await _wait(0.7)
		boss.call("pose", &"stand")
		await _wait(0.4)
	# To the table, the side nearer him, and up onto it.
	var tb := table.global_position
	var across: Vector3 = table.global_basis.x.normalized()
	var side := 1.0 if (boss.global_position - tb).dot(across) > 0.0 else -1.0
	await boss.call("walk_to", tb + across * side * 1.45)
	boss.call("face", tb)
	await boss.call("hop_to", tb + Vector3(0.0, float(Table.TOP), 0.0), 0.5)
	# The claw off the arm, onto his back.
	boss.call("pose", &"reach")
	await _wait(0.7)
	var claw: Node3D = table.call("take_claw")
	if claw != null:
		boss.call("mount_claw", claw)
	for n in everyone:
		n.set("_shake", maxf(float(n.get("_shake")), 0.25))
	await _wait(0.6)
	boss.call("pose", &"stand")
	await _wait(0.3)
	# Down, toward them.
	var to := p.global_position - tb
	to.y = 0.0
	to = to.normalized() if to.length() > 0.01 else across
	await boss.call("hop_to", tb + to * 1.9, 0.45)
	var stop := p.global_position - to * (1.5 if knocked else 3.2)
	stop.y = tb.y
	if knocked:
		await boss.call("walk_to", stop)
	else:
		# Under the booth's window, looking up at them.
		var under := Vector3(p.global_position.x, tb.y, p.global_position.z)
		await boss.call("walk_to", under - to * 2.4)
	boss.call("face", p.global_position)
	boss.call("pose", &"loom" if knocked else &"alert")
	await _wait(0.6)
	# The words.
	var sub := SUBTITLES.open(self)
	await sub.say("THE SURGEON", "Who...   are...   you...", 0.15, 1.0)
	await sub.say("YOU", "...Who are you?", 0.06, 0.9)
	await sub.say("THE SURGEON", "No matter. You will die for what you've done.", 0.055, 1.2)
	sub.close()
	_looking = []
	# Up (they were on the floor), and it begins.
	if knocked:
		p.call("scene_lean", Vector3.ZERO, 3.0)
		p.call("scene_frame", 0.0, 0.0, 3.0)
		await _wait(0.6)
	WOOD_DOOR.letterbox_out(bars)
	for n in everyone:
		if is_instance_valid(n):
			n.call("scene_look_at", null)
			if n.get("in_cutscene") == true:
				n.call("end_cutscene")
	boss.call("begin_fight", true)
	_busy = false
