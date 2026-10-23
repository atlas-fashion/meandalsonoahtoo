extends Node3D

## The surgery's CONTROL ROOM and its SURGEON (2026-10-22, note 99). The user:
## "a new 'enemy' that is the surgeon. He should be in an elevated control room.
## The task: get to the control room, kick the door down, kill the surgeon, and
## power off the system. When you interact with the door of the control room,
## the door breaking, killing of the surgeon, and turning off the power should
## all be a cutscene." The only way to switch the surgical table off.
##
## Built by surgery.gd in its plan frame (the lift's corner at -X -Z), over the
## INTAKE: a timber booth on an iron platform up against the wall -- leaded
## windows over the hall (their panes the kit's split-off "Glass", drawn
## translucent so he is seen at work), a door at the end facing the lift, a
## plank roof -- on oak posts. In it the CONSOLE of levers and gauges and the
## SURGEON at it (models/surgery/surgeon.glb, the Meshy-rigged character, three
## clips: "work", "alert", "die"), working the claw.
##
## The FREIGHT LIFT in the corner beside it -- the intake's, that brings the
## remains up from the crypts -- is the way up: an iron cage on an animatable
## body inside a frame of oak posts, its open side to the door. E inside it
## rides it up (or down); E at its foot calls it. The claw can still take you
## out of it on the way.
##
## At the top, E at the door: THE SCENE (`_storm`) -- letterbox bars; a kick
## (wood_door.gd's leg and debris) bursts the door in; the surgeon wheels round
## from his console; the player walks in and runs him through (player.gd
## `stab_at`, as the bone cages); he falls; the player throws the master lever,
## the console sparks and dies, and through the window the claw drops out of the
## air (surgical_table.gd `power_off`). The player cannot be hurt in it.

const KIT := {
	"platform": preload("res://models/surgery/platform.glb"),
	"boothwindow": preload("res://models/surgery/boothwindow.glb"),
	"boothdoorwall": preload("res://models/surgery/boothdoorwall.glb"),
	"door": preload("res://models/surgery/door.glb"),
	"console": preload("res://models/surgery/console.glb"),
	"liftcage": preload("res://models/surgery/liftcage.glb"),
	"handrail": preload("res://models/surgery/handrail.glb"),
	"beam": preload("res://models/surgery/beam.glb"),
	"chain": preload("res://models/surgery/chain.glb"),
	"surgeon": preload("res://models/surgery/surgeon.glb"),
}
const PLANKS := preload("res://textures/surgery_planks.png")
const WOOD_DOOR := preload("res://scripts/wood_door.gd")
const DEBRIS := preload("res://scripts/door_debris.gd")
const Table := preload("res://scripts/surgical_table.gd")

## The booth's floor (its top) and its walls' height.
const BOOTH_FLOOR := 3.6
const BOOTH_H := 2.3
## The door wall's opening: its middle across the wall (model +X, measured off
## the piece) and its width.
const DOOR_X := 0.6
const DOOR_W := 1.0
## The lift: the cage's travel and how long it takes, up or down.
const LIFT_TIME := 4.5
## The scene's beats (s).
const TURN_TIME := 0.3
const RUSH_TIME := 0.2
const SLOWMO := 0.3
const SLOWMO_TIME := 0.3

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
var _cage: AnimatableBody3D
var _cage_y := 0.0
var _cage_from := 0.0
var _cage_to := 0.0
var _cage_t := -1.0
var _ride_prompt: Interact.Prompt
var _call_prompt: Interact.Prompt
var _door_prompt: Interact.Prompt

var door_broken := false
var surgeon_dead := false
var _busy := false


func setup(surgery_: Node3D, table_: Node3D, inner: float, cell: float) -> void:
	surgery = surgery_
	table = table_
	_inner = inner
	_c = cell
	_build_booth()
	_build_lift()
	_build_surgeon()
	_ride_prompt = Interact.prompt("E   Ride the lift", Vector3(0.0, 1.4, 0.0))
	_cage.add_child(_ride_prompt)
	_call_prompt = Interact.prompt("E   Call the lift", Vector3(0.0, 1.4, 0.0))
	add_child(_call_prompt)
	_call_prompt.position = _lift_centre() + Vector3(0.0, 1.4, 0.0)
	_door_prompt = Interact.prompt("E   Kick in", Vector3(0.0, 1.2, 0.0))
	_door.add_child(_door_prompt)


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


# --- The freight lift --------------------------------------------------------------

func _lift_centre() -> Vector3:
	return Vector3(-_inner + _c * 0.5, 0.0, -_inner + _c * 0.5)


func _build_lift() -> void:
	var at := _lift_centre()
	var frame := Node3D.new()
	frame.name = "LiftFrame"
	add_child(frame)
	# Four oak posts at the cage's corners, up past the booth.
	var top := BOOTH_FLOOR + 2.6
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := at + Vector3(sx * 1.38, top * 0.5, sz * 1.38)
			var post := _piece("beam", frame, p)
			post.basis = Basis(Vector3.FORWARD, PI * 0.5).scaled(Vector3(top / 4.66, 0.45, 0.45))
			_box(frame, Vector3(0.25, top, 0.25), p)
	# The cage: its open side (the model's +X) toward the door (+Z).
	_cage = AnimatableBody3D.new()
	_cage.name = "LiftCage"
	_cage.collision_layer = 1 | 2
	_cage.collision_mask = 0
	_cage.sync_to_physics = true
	add_child(_cage)
	_cage.position = at
	_piece("liftcage", _cage, Vector3.ZERO, -PI * 0.5)
	for b in [[Vector3(2.5, 0.12, 2.5), Vector3(0.0, 0.06, 0.0)], [Vector3(2.5, 2.4, 0.1), Vector3(0.0, 1.2, -1.25)],
			[Vector3(0.1, 2.4, 2.5), Vector3(-1.25, 1.2, 0.0)], [Vector3(0.1, 2.4, 2.5), Vector3(1.25, 1.2, 0.0)],
			[Vector3(2.5, 0.1, 2.5), Vector3(0.0, 2.38, 0.0)]]:
		var shape := BoxShape3D.new()
		shape.size = b[0]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = b[1]
		_cage.add_child(cs)
	# The chains it hangs on, to the top of the frame.
	for sx: float in [-0.9, 0.9]:
		var c := Node3D.new()
		c.name = "LiftChain"
		_cage.add_child(c)
		c.position = Vector3(sx, 2.4, 0.0)
		for i in 5:
			var link: Node3D = _piece("chain", c, Vector3(0.0, float(i + 1) * 1.0, 0.0))
			link.rotation.y = 0.0
	_cage_y = 0.0


func _move_lift(to: float) -> void:
	_cage_from = _cage_y
	_cage_to = to
	_cage_t = 0.0


func _run_lift(delta: float) -> void:
	# The whole position, every frame (note 100): maze.gd moves the level under
	# the navmesh region after it is built, and a sync_to_physics body moved like
	# that takes back the physics server's transform -- still the origin -- so
	# the cage turned up on the surgical table in the middle of the hall, and a
	# player in it stood on the table top with their head through its roof.
	var want := _lift_centre() + Vector3(0.0, _cage_y, 0.0)
	if not _cage.position.is_equal_approx(want):
		_cage.position = want
	if _cage_t < 0.0:
		return
	_cage_t += delta
	var k := clampf(_cage_t / LIFT_TIME, 0.0, 1.0)
	_cage_y = lerpf(_cage_from, _cage_to, k * k * (3.0 - 2.0 * k))
	_cage.position.y = _cage_y
	# The chains run up into the frame as it rises.
	for c in _cage.get_children():
		if c.name.begins_with("LiftChain"):
			(c as Node3D).visible = true
	if k >= 1.0:
		_cage_t = -1.0


func _player_in_cage(p: Node3D) -> bool:
	var local := _cage.to_local(p.global_position)
	return absf(local.x) < 1.15 and absf(local.z) < 1.15 and local.y > -0.3 and local.y < 1.0


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
		for c in [&"alert", &"die"]:
			var n := _clip(c)
			if n != &"":
				_anim.get_animation(n).loop_mode = Animation.LOOP_NONE


## The clip whose name has `key` in it ("work", "alert", "die").
func _clip(key: StringName) -> StringName:
	if _anim == null:
		return &""
	for n in _anim.get_animation_list():
		if String(n).to_lower().contains(String(key)):
			return n
	return &""


func _surgeon_head() -> Vector3:
	return _surgeon.global_position + Vector3(0.0, 1.6, 0.0)


func _surgeon_chest() -> Vector3:
	return _surgeon.global_position + Vector3(0.0, 1.15, 0.0)


# --- Each frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	_run_lift(delta)
	if _busy:
		_ride_prompt.visible = false
		_call_prompt.visible = false
		_door_prompt.visible = false
		return
	var moving := _cage_t >= 0.0
	# In the cage: ride it.
	var rider: Node = null
	if not moving:
		for p in Coop.all():
			var n := p as Node3D
			if n != null and n.get("_dead") != true and n.get("in_cutscene") != true and _player_in_cage(n) \
					and not (n.has_method("is_restrained") and n.is_restrained()):
				rider = n
				break
	_ride_prompt.visible = rider != null
	_ride_prompt.player = rider
	_ride_prompt.text = "E   Ride down" if _cage_y > 1.0 else "E   Ride the lift"
	# At its foot, the cage up: call it.
	var caller: Node = null
	if not moving and _cage_y > 1.0:
		var foot := global_transform * _lift_centre()
		for p in Coop.all():
			var n := p as Node3D
			if n == null or n.get("_dead") == true or n.get("in_cutscene") == true:
				continue
			var to := n.global_position - foot
			if Vector2(to.x, to.z).length() < 2.4 and absf(to.y) < 1.2:
				caller = n
				break
	_call_prompt.visible = caller != null
	_call_prompt.player = caller
	# At the door.
	var kicker: Node = null
	if not door_broken and not moving:
		kicker = Interact.chooser(_door, 2.4, 1.6, 3.0, 0.15)
	_door_prompt.visible = kicker != null
	_door_prompt.player = kicker


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if _door_prompt.visible and Interact.pressed(event, _door_prompt.player):
		get_viewport().set_input_as_handled()
		_storm(_door_prompt.player as Node3D)
		return
	if _ride_prompt.visible and Interact.pressed(event, _ride_prompt.player):
		get_viewport().set_input_as_handled()
		_move_lift(0.0 if _cage_y > 1.0 else BOOTH_FLOOR)
		return
	if _call_prompt.visible and Interact.pressed(event, _call_prompt.player):
		get_viewport().set_input_as_handled()
		_move_lift(0.0)


# --- The scene ---------------------------------------------------------------------

func _tween() -> Tween:
	return create_tween().set_parallel(true).set_ignore_time_scale(true)


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


## The door kicked in, the surgeon killed, the power cut -- one scene, the player
## untouchable in it.
func _storm(p: Node3D) -> void:
	if p == null or _busy or door_broken:
		return
	_busy = true
	_door_prompt.visible = false
	p.call("begin_cutscene")
	p.set("hands_busy", true)
	var bars := WOOD_DOOR.letterbox(self)
	var door_at := _door.global_position
	# Through the door: the booth's +Z in the world (the door faces the lift).
	var into := (global_basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var base := Vector3(door_at.x, p.global_position.y, door_at.z)
	var windup := base - into * 1.6
	var strike := base - into * 0.75
	var yaw: float = p.rotation.y + wrapf(atan2(-into.x, -into.z) - p.rotation.y, -PI, PI)

	# 1. Square up to the door, a step back.
	var t := _tween()
	t.tween_property(p, "rotation:y", yaw, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(p, "global_position", windup, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(p, "_look_pitch", -0.1, TURN_TIME)
	await t.finished

	# 2. The kick.
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

	# 3. The door bursts in; he wheels round from the console.
	_burst_door(into)
	Engine.time_scale = SLOWMO
	p.set("_land_kick", 1.0)
	p.set("_land_strength", 0.5)
	var alert := _clip(&"alert")
	if alert != &"":
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

	# 4. In, onto him.
	p.call("scene_look_at", _surgeon_head(), 6.0)
	p.call("scene_frame", 6.0, 0.0, 2.0)
	var reach: float = float(p.call("scene_reach")) if p.has_method("scene_reach") else 1.2
	var to_him := _surgeon.global_position - p.global_position
	to_him.y = 0.0
	var stand := _surgeon.global_position - to_him.normalized() * (reach + 0.75)
	stand.y = p.global_position.y
	p.call("scene_walk_to", stand, 3.0)
	await Signal(p, &"scene_walk_finished")

	# 5. Run through.
	p.call("scene_look_at", _surgeon_chest(), 8.0)
	p.call("stab_at", _surgeon_chest(), 0.18)
	p.call("scene_frame", 14.0, -3.0, 4.0)
	await Signal(p, &"stab_landed")
	p.call("scene_frame", 18.0, 4.0, 14.0)
	if table != null:
		table.call("_sparks", _surgeon_chest(), Color(0.7, 0.08, 0.05), 26)
	await Signal(p, &"stab_wrenched")
	_kill_surgeon()
	await _wait(0.9)

	# 6. The master lever: the console sparks and dies, and the machine with it.
	var lever := _console.global_transform * Vector3(0.95, 1.1, 0.0)
	p.call("scene_look_at", lever, 5.0)
	p.call("scene_frame", 10.0, 0.0, 3.0)
	var at_lever := _console.global_transform * Vector3(0.95, 0.0, 0.85)
	at_lever.y = p.global_position.y
	p.call("scene_walk_to", at_lever, 2.5)
	await Signal(p, &"scene_walk_finished")
	await _wait(0.35)
	_throw_lever()
	await _wait(0.5)
	# 7. Through the window: the claw falls.
	if table != null:
		var claw := table.get_node_or_null("Claw") as Node3D
		if claw != null:
			p.call("scene_look_at", claw.global_position, 3.0)
	p.call("scene_frame", 4.0, 0.0, 2.0)
	await _wait(2.6)
	_end_scene(p, bars)


func _end_scene(p: Node3D, bars: CanvasLayer) -> void:
	if bars != null and is_instance_valid(bars):
		WOOD_DOOR.letterbox_out(bars)
	if is_instance_valid(p):
		p.set("hands_busy", false)
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


## He falls (his clip, or folded down if it is missing), the console still lit.
func _kill_surgeon() -> void:
	surgeon_dead = true
	var die := _clip(&"die")
	if die != &"":
		_anim.play(die, 0.1)
	else:
		var tw := _surgeon.create_tween()
		tw.tween_property(_surgeon, "rotation:x", -PI * 0.5, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## The power off: a burst of sparks off the console, its lamps and gauges die,
## the booth's lamp gutters out, and the table's power is cut.
func _throw_lever() -> void:
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


# --- Saving and resetting -----------------------------------------------------------

## A save with the machine off: the door gone, the surgeon dead on the floor, the
## console dark.
func set_finished() -> void:
	door_broken = true
	surgeon_dead = true
	_door.visible = false
	_door_body.collision_layer = 0
	var die := _clip(&"die")
	if die != &"":
		_anim.play(die)
		_anim.seek(_anim.get_animation(die).length - 0.01, true)
	for m in _console_mats:
		(m as StandardMaterial3D).emission_energy_multiplier = 0.0
	_booth_light.light_energy = 0.35


## Everyone died with the machine still running: the lift back down.
func reset() -> void:
	if door_broken:
		return
	_cage_t = -1.0
	_cage_y = 0.0
	_cage.position.y = 0.0
