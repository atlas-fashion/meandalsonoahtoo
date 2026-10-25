extends Node3D

## The surgery's CONTROL ROOM and its SURGEON (2026-10-22, note 99; note 102: no
## longer a way in or a way to stop the machine). Note 99 had him killed in a
## cutscene behind a door kicked in at the top of a freight lift, and the master
## lever thrown; the user then asked for the crystal under the floor
## (surgery_power.gd) to be the machine's power, "and when the player comes back
## up out of the powering room after removing the crystal from the room, the
## surgeon should be gone." The lift, the kick and the scene are gone (asked:
## the booth stays, no kick-in).
##
## Built by surgery.gd in its plan frame, up against the -X wall over the
## INTAKE: a timber booth on an iron platform -- leaded windows over the hall
## (note 101's glazing), a door at the end (shut), a plank roof -- on oak posts.
## In it the CONSOLE of levers and gauges and the SURGEON at it
## (models/surgery/surgeon.glb, the Meshy-rigged character; his "work" clip),
## working the claw, seen through the glass from the hall.
##
## `power_cut`: the crystal is out -- the console's lamps die and his lamp
## gutters; he stays at it, staring. `leave`: done while the player climbs out
## of the powering room with the screen black -- he is gone, the booth's door
## stands open, the lamp low.

const KIT := {
	"platform": preload("res://models/surgery/platform.glb"),
	"boothwindow": preload("res://models/surgery/boothwindow.glb"),
	"boothdoorwall": preload("res://models/surgery/boothdoorwall.glb"),
	"door": preload("res://models/surgery/door.glb"),
	"console": preload("res://models/surgery/console.glb"),
	"beam": preload("res://models/surgery/beam.glb"),
	"surgeon": preload("res://models/surgery/surgeon.glb"),
}
const PLANKS := preload("res://textures/surgery_planks.png")
const Table := preload("res://scripts/surgical_table.gd")

## The booth's floor (its top) and its walls' height.
const BOOTH_FLOOR := 3.6
const BOOTH_H := 2.3
## The door wall's opening: its middle across the wall (model +X, measured off
## the piece) and its width.
const DOOR_X := 0.6
const DOOR_W := 1.0
## Gone, he left the door this far open (radians).
const DOOR_LEFT_OPEN := 1.5

var surgery: Node3D
var table: Node3D
var _inner := 13.4
var _c := 2.98

## Built nodes.
var _booth: Node3D
var _door: Node3D
var _door_body: StaticBody3D
var _console: Node3D
var _surgeon: Node3D
var _anim: AnimationPlayer
var _booth_light: OmniLight3D
var _console_mats: Array = []

var powered := true
var surgeon_gone := false


func setup(surgery_: Node3D, table_: Node3D, inner: float, cell: float) -> void:
	surgery = surgery_
	table = table_
	_inner = inner
	_c = cell
	_build_booth()
	_build_surgeon()


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
	_booth = Node3D.new()
	_booth.name = "Booth"
	add_child(_booth)
	# The iron floor, its long side along the wall.
	_piece("platform", _booth, Vector3(mid.x, BOOTH_FLOOR, mid.z), PI * 0.5)
	_box(_booth, Vector3(_c, 0.45, _c * 2.0), Vector3(mid.x, BOOTH_FLOOR - 0.225, mid.z))
	# Oak posts under its outer corners, from the floor up to it.
	for z: float in [z0 + 0.2, z1 - 0.2]:
		var post := _piece("beam", _booth, Vector3(x1 - 0.2, (BOOTH_FLOOR - 0.45) * 0.5, z))
		post.basis = Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3((BOOTH_FLOOR - 0.45) / 4.66, 0.6, 0.6))
		_box(_booth, Vector3(0.35, BOOTH_FLOOR - 0.45, 0.35), Vector3(x1 - 0.2, (BOOTH_FLOOR - 0.45) * 0.5, z))
	# The leaded windows over the hall.
	var win := _piece("boothwindow", _booth, Vector3(x1 - 0.125, BOOTH_FLOOR, mid.z), PI * 0.5)
	win.scale = Vector3(1.0, BOOTH_H / 2.5, 1.0)
	_glaze(win)
	_box(_booth, Vector3(0.25, BOOTH_H, _c * 2.0), Vector3(x1 - 0.125, BOOTH_FLOOR + BOOTH_H * 0.5, mid.z))
	# The far end: a narrower leaded window.
	var end := _piece("boothwindow", _booth, Vector3(mid.x, BOOTH_FLOOR, z1 - 0.125), 0.0)
	end.scale = Vector3(_c / 5.94, BOOTH_H / 2.5, 1.0)
	_glaze(end)
	_box(_booth, Vector3(_c, BOOTH_H, 0.25), Vector3(mid.x, BOOTH_FLOOR + BOOTH_H * 0.5, z1 - 0.125))
	# The door's end, facing the lift; its opening at DOOR_X across it (the piece
	# turned to face -Z, so its +X runs along -X).
	_piece("boothdoorwall", _booth, Vector3(mid.x, BOOTH_FLOOR, z0 + 0.125), PI).scale = Vector3(1.0, BOOTH_H / 2.5, 1.0)
	var gap_x := mid.x - DOOR_X
	var left := (gap_x - DOOR_W * 0.5) - x0
	var right := x1 - (gap_x + DOOR_W * 0.5)
	_box(_booth, Vector3(left, BOOTH_H, 0.25), Vector3(x0 + left * 0.5, BOOTH_FLOOR + BOOTH_H * 0.5, z0 + 0.125))
	_box(_booth, Vector3(right, BOOTH_H, 0.25), Vector3(x1 - right * 0.5, BOOTH_FLOOR + BOOTH_H * 0.5, z0 + 0.125))
	_box(_booth, Vector3(DOOR_W, BOOTH_H - 2.1, 0.25), Vector3(gap_x, BOOTH_FLOOR + 2.1 + (BOOTH_H - 2.1) * 0.5, z0 + 0.125))
	# The door in it, shut.
	_door = Node3D.new()
	_door.name = "Door"
	_booth.add_child(_door)
	_door.position = Vector3(gap_x, BOOTH_FLOOR, z0 + 0.125)
	_door.rotation.y = PI
	_piece("door", _door, Vector3.ZERO).scale = Vector3(DOOR_W / 1.05, 1.0, 1.0)
	_door_body = _box(_door, Vector3(DOOR_W, 2.1, 0.2), Vector3(0.0, 1.05, 0.0))
	# The plank roof, seen from inside and out.
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_c, _c * 2.0)
	roof.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_texture = PLANKS
	m.albedo_color = Color(0.6, 0.52, 0.46)
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.4, 0.4, 0.4)
	roof.material_override = m
	_booth.add_child(roof)
	roof.position = Vector3(mid.x, BOOTH_FLOOR + BOOTH_H, mid.z)
	_box(_booth, Vector3(_c, 0.1, _c * 2.0), Vector3(mid.x, BOOTH_FLOOR + BOOTH_H + 0.05, mid.z))
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

func _build_surgeon() -> void:
	var mid := booth_centre()
	_surgeon = _piece("surgeon", _booth, Vector3(-_inner + 1.25, BOOTH_FLOOR, mid.z), PI * 0.5)
	var found := _surgeon.find_children("*", "AnimationPlayer", true, false)
	if not found.is_empty():
		_anim = found[0] as AnimationPlayer
		var work := _clip(&"work")
		if work != &"":
			_anim.get_animation(work).loop_mode = Animation.LOOP_LINEAR
			_anim.play(work)


## The clip whose name has `key` in it ("work", "alert", "die").
func _clip(key: StringName) -> StringName:
	if _anim == null:
		return &""
	for n in _anim.get_animation_list():
		if String(n).to_lower().contains(String(key)):
			return n
	return &""


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
	if _anim != null:
		var alert := _clip(&"alert")
		if alert != &"" and not now:
			_anim.get_animation(alert).loop_mode = Animation.LOOP_NONE
			_anim.play(alert, 0.3)
		else:
			_anim.pause()


## Gone (the player climbing out of the powering room, the screen black): no
## surgeon, the door left standing open behind him.
func leave() -> void:
	if surgeon_gone:
		return
	surgeon_gone = true
	power_cut(true)
	if _anim != null:
		_anim.stop()
	_surgeon.visible = false
	_surgeon.process_mode = Node.PROCESS_MODE_DISABLED
	# Swung on its edge (the model's -X), not about its middle.
	var edge := Vector3(-DOOR_W * 0.5, 0.0, 0.0)
	var pivot := _door.transform * edge
	_door.rotation.y = PI + DOOR_LEFT_OPEN
	_door.position = pivot - _door.basis * edge
	_door_body.collision_layer = 0
