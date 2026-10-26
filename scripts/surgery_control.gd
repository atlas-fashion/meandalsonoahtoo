extends Node3D

## The surgery's CONTROL ROOM and its SURGEON (2026-10-22, note 99; note 102: no
## longer a way in or a way to stop the machine; note 104: both again -- see "The
## way in from the hall" below: the landing, the kick, the surgeon thrown out of
## the window, the lever). Note 99 had him killed in a
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
const WOOD_DOOR := preload("res://scripts/wood_door.gd")
const DEBRIS := preload("res://scripts/door_debris.gd")
const Vat := preload("res://scripts/surgery_vat.gd")
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
## The kick (as note 99's): squaring up, the rush, the slow motion as it bursts.
const TURN_TIME := 0.3
const RUSH_TIME := 0.2
const SLOWMO := 0.3
const SLOWMO_TIME := 0.3
## A player on a vat this near the landing or the booth (from the vat's middle
## to their edges) climbs up and the scene starts (note 104).
const CLIMB_NEAR := 2.2

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
## Note 104: the door kicked in, the surgeon thrown out through the window.
var door_broken := false
var surgeon_thrown := false
var _busy := false
var _hall_pane: MeshInstance3D
var _hall_window: Node3D


func setup(surgery_: Node3D, table_: Node3D, inner: float, cell: float) -> void:
	surgery = surgery_
	table = table_
	_inner = inner
	_c = cell
	_build_booth()
	_build_surgeon()
	_build_landing()


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
	_hall_window = win
	_hall_pane = win.get_node_or_null("Pane") as MeshInstance3D
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
	if _anim != null and not surgeon_thrown:
		var alert := _clip(&"alert")
		if alert != &"" and not now:
			_anim.get_animation(alert).loop_mode = Animation.LOOP_NONE
			_anim.play(alert, 0.3)
		else:
			_anim.pause()


## Gone (the player climbing out of the powering room, the screen black): no
## surgeon, the door left standing open behind him.
func leave() -> void:
	# Thrown out of the booth (note 104): he lies in the hall.
	if surgeon_thrown:
		return
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



# --- The way in from the hall (note 104) -------------------------------------------
##
## The user: "make the control room to where the player can push a vat over to
## it, jump on the vat, and start a cutscene where the player kicks the door
## down, throw the surgeon out of the control room down to the surgery room, and
## power off the system from the control room. The player has to start by
## jumping on the middle table, then to the vats." A vat (1.9 m) is too tall to
## jump onto from the floor; the table (1.2 m) is not, and from it the vats
## round the middle can be reached, and from vat to vat the rest. A player
## standing on a vat shoved up beside the booth (CLIMB_NEAR) climbs up onto the
## LANDING outside its door -- the iron platform the freight lift used to stop
## at (note 99), back in the corner -- and the scene runs (`_storm`).

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


## The landing's and the booth's footprints on the floor (plan frame, x and z).
func _landing_rect() -> Rect2:
	return Rect2(-_inner, -_inner, _c, _c)


func _booth_rect() -> Rect2:
	return Rect2(-_inner, -_inner + _c, _c, _c * 2.0)


static func _rect_gap(r: Rect2, p: Vector2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(q)


func _process(_delta: float) -> void:
	if _busy or door_broken or table == null or bool(table.call("is_depowered")):
		return
	for p in Coop.all():
		var n := p as CharacterBody3D
		if n == null or n.get("_dead") == true or n.get("in_cutscene") == true or not n.is_on_floor():
			continue
		if n.has_method("is_restrained") and n.is_restrained():
			continue
		var vat := _vat_under(n)
		if vat == null:
			continue
		var at := to_local(vat.global_position)
		var flat := Vector2(at.x, at.z)
		if _rect_gap(_landing_rect(), flat) < CLIMB_NEAR or _rect_gap(_booth_rect(), flat) < CLIMB_NEAR:
			_storm(n)
			return


## The vat `n` stands on, if any.
func _vat_under(n: Node3D) -> Node3D:
	for v in get_tree().get_nodes_in_group(&"surgery_vat"):
		var vat := v as Node3D
		var to := n.global_position - vat.global_position
		if to.y > 1.5 and to.y < 2.4 and Vector2(to.x, to.z).length() < Vat.RADIUS + 0.2:
			return vat
	return null


func _tween() -> Tween:
	return create_tween().set_parallel(true).set_ignore_time_scale(true)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _surgeon_head() -> Vector3:
	return _surgeon.global_position + Vector3(0.0, 1.6, 0.0)


## Up off the vat onto the landing, the door kicked in, the surgeon heaved out
## through the window down into the hall, the master lever thrown -- one scene,
## the player untouchable in it.
func _storm(p: Node3D) -> void:
	if p == null or _busy or door_broken:
		return
	_busy = true
	p.call("begin_cutscene")
	p.set("hands_busy", true)
	var bars := WOOD_DOOR.letterbox(self)
	# Through the door: the booth's +Z in the world (the door faces the landing).
	var into := (global_basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var door_at := _door.global_position

	# 1. Up onto the landing: a hand on its edge, hauled up and over.
	var here := to_local(p.global_position)
	var r := _landing_rect()
	var on := Vector3(clampf(here.x, r.position.x + 0.6, r.end.x - 0.6), BOOTH_FLOOR + 0.02,
		clampf(here.z, r.position.y + 0.6, r.end.y - 0.6))
	var edge := Vector3(clampf(here.x, r.position.x, r.end.x), BOOTH_FLOOR - 0.4, clampf(here.z, r.position.y, r.end.y))
	p.call("scene_look_at", global_transform * (on + Vector3(0.0, 0.3, 0.0)), 6.0)
	var t := _tween()
	t.tween_property(p, "global_position", global_transform * here.lerp(edge, 0.6), 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await t.finished
	t = _tween()
	t.tween_property(p, "global_position", global_transform * on, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	p.set("velocity", Vector3.ZERO)

	# 2. Square up to the door, a step back.
	var base := Vector3(door_at.x, p.global_position.y, door_at.z)
	var windup := base - into * 1.6
	var strike := base - into * 0.75
	p.call("scene_look_at", door_at + Vector3(0.0, 1.1, 0.0), 6.0)
	p.call("scene_walk_to", windup, 3.0)
	await Signal(p, &"scene_walk_finished")
	p.call("scene_look_at", null)
	var yaw: float = p.rotation.y + wrapf(atan2(-into.x, -into.z) - p.rotation.y, -PI, PI)
	t = _tween()
	t.tween_property(p, "rotation:y", yaw, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(p, "_look_pitch", -0.1, TURN_TIME)
	await t.finished

	# 3. The kick.
	var maker := WOOD_DOOR.new()
	var leg: Node3D = maker._make_leg(p)
	maker.free()
	p.set("_dash_view", 1.0)
	t = _tween()
	t.tween_property(p, "global_position", strike, RUSH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(p, "_look_pitch", -0.3, RUSH_TIME)
	t.tween_property(leg, "rotation:x", 0.9, RUSH_TIME * 0.65).set_trans(Tween.TRANS_SINE)
	t.chain().tween_property(leg, "rotation:x", WOOD_DOOR.LEG_STRIKE, RUSH_TIME * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished

	# 4. The door bursts in; he wheels round from his console.
	_burst_door(into)
	Engine.time_scale = SLOWMO
	p.set("_land_kick", 1.0)
	p.set("_land_strength", 0.5)
	var alert := _clip(&"alert")
	if alert != &"":
		_anim.get_animation(alert).loop_mode = Animation.LOOP_NONE
		_anim.play(alert, 0.15)
	await _wait(SLOWMO_TIME)
	Engine.time_scale = 1.0
	t = _tween()
	t.tween_property(leg, "rotation:x", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	leg.queue_free()
	p.set("hands_busy", false)
	if p.get("_dead") == true:
		_end_scene(p, bars)
		return

	# 5. In, onto him: at his side, between him and the door.
	p.call("scene_look_at", _surgeon_head(), 6.0)
	p.call("scene_frame", 6.0, 0.0, 2.0)
	var stand := _surgeon.global_position - into * 0.95
	stand.y = p.global_position.y
	p.call("scene_walk_to", stand, 3.5)
	await Signal(p, &"scene_walk_finished")
	await _wait(0.2)

	# 6. Seized and heaved over the console, through the window, down into the
	# hall.
	p.call("scene_lean", Vector3(0.0, -0.1, -0.25), 9.0)
	p.call("scene_frame", 12.0, -4.0, 5.0)
	await _wait(0.25)
	await _throw_surgeon(p)
	p.call("scene_lean", Vector3.ZERO, 4.0)
	p.call("scene_frame", 0.0, 0.0, 2.0)
	await _wait(0.7)

	# 7. The master lever: the console sparks and dies, and the machine with it.
	var lever := _console.global_transform * Vector3(0.95, 1.1, 0.0)
	p.call("scene_look_at", lever, 5.0)
	var at_lever := _console.global_transform * Vector3(0.95, 0.0, 0.85)
	at_lever.y = p.global_position.y
	p.call("scene_walk_to", at_lever, 2.5)
	await Signal(p, &"scene_walk_finished")
	await _wait(0.35)
	_throw_lever()
	await _wait(0.5)
	# 8. Out of the broken window: the claw falls.
	var claw := table.get_node_or_null("Claw") as Node3D
	if claw != null:
		p.call("scene_look_at", claw.global_position, 3.0)
	await _wait(2.6)
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
	_door_body.collision_layer = 0
	var impact := _door.global_position + Vector3(0.0, 1.1, 0.0)
	var pieces: Array = []
	for node in _door.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		pieces.append_array(DEBRIS.shatter(mi, self, into, impact, 4 if Graphics.effects else 3, 6 if Graphics.effects else 3, 0.35, false))
		mi.visible = false
	DEBRIS.crumble(pieces, Graphics.effects)
	if Graphics.effects:
		DEBRIS.dust(self, impact, into)


## Where he lands in the hall: under the window, out from the booth (plan frame).
func _landing_spot() -> Vector3:
	var mid := booth_centre()
	return Vector3(-_inner + _c + 2.4, 0.0, mid.z + 0.5)


## He goes over the console and through the leaded glass in a burst of it, and
## falls to the flags below, where he lies (his "die" clip).
func _throw_surgeon(p: Node3D) -> void:
	surgeon_thrown = true
	var mid := booth_centre()
	var start := _surgeon.global_position
	var through := global_transform * Vector3(-_inner + _c - 0.1, BOOTH_FLOOR + 1.0, mid.z + 0.2)
	var land := global_transform * _landing_spot()
	var die := _clip(&"die")
	if die != &"":
		_anim.get_animation(die).loop_mode = Animation.LOOP_NONE
		_anim.play(die, 0.1, 1.4)
	p.call("scene_look_at", through, 7.0)
	var t := _tween()
	t.tween_method(func(k: float) -> void:
		var a := start.lerp(through, k)
		a.y += sin(k * PI) * 0.6
		_surgeon.global_position = a, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	_break_window(through)
	p.call("scene_look_at", land, 5.0)
	t = _tween()
	t.tween_method(func(k: float) -> void:
		var a := through.lerp(land, k)
		a.y = lerpf(through.y, land.y, k * k) + sin(k * PI) * 0.4
		_surgeon.global_position = a, 0.0, 1.0, 0.6)
	await t.finished
	if table != null:
		table.call("_impact_fx", land, 0.4)
	_booth_light.light_energy = 0.8


## The hall window's glass bursts out (the lead tracery stays): its pane gone,
## a spray of glass out over the hall.
func _break_window(at: Vector3) -> void:
	if _hall_pane != null:
		_hall_pane.visible = false
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
	p.direction = global_basis * Vector3(1.0, 0.3, 0.0)
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


## A save with the booth taken: the door gone, the window broken, he lies in
## the hall, the console dark.
func set_thrown_now() -> void:
	door_broken = true
	surgeon_thrown = true
	powered = false
	_door.visible = false
	_door_body.collision_layer = 0
	if _hall_pane != null:
		_hall_pane.visible = false
	_surgeon.global_position = global_transform * _landing_spot()
	var die := _clip(&"die")
	if die != &"":
		_anim.play(die)
		_anim.seek(_anim.get_animation(die).length - 0.01, true)
	for m in _console_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = 0.0
	_booth_light.light_energy = 0.35
