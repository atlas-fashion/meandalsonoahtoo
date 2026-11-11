extends "res://scripts/holding_cell.gd"

## A beacon room (note 179): a dead end dressed as the user's cell photo (the cell
## kit, note 177 -- the bench under its chains, the shelf, the drain, straw, the
## caged lantern) with the photo's bronze gear door on its back wall, here the
## winch of the room's iron gate. The gate hangs raised in the arch; walk in and it
## crashes down behind you, and you are shut in until you hold E on the wheel,
## which cranks the gate back up (let go and it sinks back; take a hit and you lose
## your grip). The room's respawn beacon stands in the middle, so the place you
## rise is a room you have to wind your way out of.
##
## The first room is laid out exactly as the photo (`identical`): the bench and
## chains on the left, the shelf on the right, the lantern over the middle; the
## rest are mirrored or rearranged, some with what is left of a prisoner, so no
## two read alike.
##
## Built like the holding cells (holding_cell.gd's frame: +Z the way out), in
## maze.gd's `_holding_cells` so clutter, the ruins and spawns keep out of it, but
## with no prisoners and no swinging gate. Nothing about it is saved: a level
## built afresh has its gates raised.

## How high the raised gate's foot hangs: a head clears it (the gate's top then
## stands just under the boss hall's floor, 7.0 m).
const LIFT := 2.3
const DROP_TIME := 0.32
## Held E this long winds the gate all the way up.
const CRANK_TIME := 3.2
## Letting go, the gate sinks back this many times as fast as it rose.
const SINK := 1.6
## Walked in this far past the gate's line, and it drops after DROP_DELAY.
const TRIGGER_IN := 1.0
const DROP_DELAY := 0.35
## The winch on the back wall: the wheel's middle.
const WHEEL_AT := Vector3(0.0, 1.45, -1.78)
const WHEEL_R := 0.62
const WHEEL_REACH := 2.4
const BEACON_SPOT := Vector3(0.0, 0.0, 0.75)

var identical := false
## 1 up (open), 0 down.
var _lift := 1.0
var _locked := false
var _armed := true
var _drop_in := -1.0
var _wheel: Node3D
var _wheel_spin: Node3D
var _holder: Node3D
var _holder_health := 0.0
var _player: Node3D


static func place_room(parent: Node3D, built, at: Vector2i, out: Vector3, owner_maze: Node,
		torch_energy: float, wall_torch: int, first: bool) -> Node3D:
	fit_kit()
	var node := Node3D.new()
	node.set_script(load("res://scripts/wheel_room.gd"))
	node.name = "BeaconRoom%d_%d" % [at.x, at.y]
	parent.add_child(node)
	node.global_basis = Basis.looking_at(-out, Vector3.UP)
	node.global_position = built.to_world(at)
	node.set("maze", owner_maze)
	node.set("cell", at)
	node.set("pilaster", wall_torch)
	node.set("identical", first)
	node.call("_furnish_room", torch_energy, built)
	return node


## Where maze.gd stands this room's beacon (the back wall has the winch).
func beacon_spot() -> Vector3:
	return BEACON_SPOT


func _furnish_room(torch_energy: float, built) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell) ^ 0x77ee1
	_strewn_straw(_mat(Color(0.29, 0.22, 0.1), 1.0), rng)
	# The photo's layout in the first room (bench left); the others mirrored at
	# random, unless a wall torch decides it.
	if not identical and pilaster == 0 and rng.randf() < 0.5:
		pilaster = 1 if rng.randf() < 0.5 else -1
		_kit_dress(rng)
		pilaster = 0
	else:
		_kit_dress(rng)
	if not identical and rng.randf() < 0.5:
		_remains(_mat(Color(0.48, 0.44, 0.36), 0.9), rng)
	if torch_energy > 0.0:
		_hang_lantern(built, torch_energy * TORCH_SHARE)
	_build_gate()
	_build_wheel()
	_gate.position.y = LIFT * _lift
	_draw_to(self, DRAWN_TO)
	_prompt = Interact.prompt("Hold E   Turn the wheel", Vector3(0.0, 0.2, 0.35))
	_wheel.add_child(_prompt)
	_prompt.visible = false


# --- The winch: the photo's bronze gear door -----------------------------------------

static var _bronze: StandardMaterial3D
static var _brass: StandardMaterial3D
static var _iron: StandardMaterial3D


static func _metal(albedo: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.6
	return m


static func _part(mesh: Mesh, mat: Material, at: Vector3, rot: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## A riveted bronze door in the back wall between two brass piston columns, and
## on it the great gear wheel, a handle on its rim. [winch, the turning wheel];
## `at` the wheel's middle, its y the height off the floor. Shared with the
## scoutposts (scoutpost.gd).
static func make_winch(parent: Node3D, at: Vector3) -> Array:
	if _bronze == null:
		_bronze = _metal(Color(0.62, 0.4, 0.19), 0.34, 0.85)
		_brass = _metal(Color(0.55, 0.42, 0.18), 0.3, 0.9)
		_iron = _metal(Color(0.2, 0.18, 0.16), 0.5, 0.7)
	var winch := Node3D.new()
	winch.name = "Winch"
	winch.position = at
	parent.add_child(winch)
	# The door behind it, set into the back wall.
	var door := BoxMesh.new()
	door.size = Vector3(1.75, 2.6, 0.1)
	_part(door, _bronze, Vector3(0.0, -at.y + 1.3, -0.08), Vector3.ZERO, winch)
	var rivet := SphereMesh.new()
	rivet.radius = 0.022
	rivet.height = 0.03
	rivet.radial_segments = 6
	rivet.rings = 3
	for i in 9:
		for x: float in [-0.8, 0.8]:
			_part(rivet, _brass, Vector3(x, -at.y + 0.15 + float(i) * 0.29, -0.025), Vector3.ZERO, winch)
	# The piston columns either side.
	var col := CylinderMesh.new()
	col.top_radius = 0.07
	col.bottom_radius = 0.07
	col.height = 2.2
	col.radial_segments = 12
	col.rings = 1
	var cap := CylinderMesh.new()
	cap.top_radius = 0.11
	cap.bottom_radius = 0.11
	cap.height = 0.12
	cap.radial_segments = 12
	cap.rings = 1
	for x: float in [-1.02, 1.02]:
		_part(col, _brass, Vector3(x, -at.y + 1.1, 0.04), Vector3.ZERO, winch)
		_part(cap, _bronze, Vector3(x, -at.y + 0.06, 0.04), Vector3.ZERO, winch)
		_part(cap, _bronze, Vector3(x, -at.y + 2.2, 0.04), Vector3.ZERO, winch)
	# The wheel, which turns.
	var spin := Node3D.new()
	spin.name = "Wheel"
	spin.position = Vector3(0.0, 0.0, 0.1)
	winch.add_child(spin)
	var rim := TorusMesh.new()
	rim.inner_radius = WHEEL_R - 0.07
	rim.outer_radius = WHEEL_R
	rim.rings = 32
	rim.ring_segments = 8
	_part(rim, _bronze, Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0), spin)
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.07, 0.09, 0.06)
	for i in 20:
		var a := TAU * float(i) / 20.0
		var t := _part(tooth, _bronze, Vector3(cos(a), sin(a), 0.0) * (WHEEL_R + 0.03), Vector3(0.0, 0.0, a), spin)
		t.rotation.z = a + PI * 0.5
	var spoke := BoxMesh.new()
	spoke.size = Vector3(0.05, WHEEL_R * 2.0 - 0.1, 0.04)
	for i in 3:
		_part(spoke, _iron, Vector3.ZERO, Vector3(0.0, 0.0, PI * float(i) / 3.0), spin)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.12
	hub.bottom_radius = 0.14
	hub.height = 0.12
	hub.radial_segments = 14
	hub.rings = 1
	_part(hub, _brass, Vector3(0.0, 0.0, 0.03), Vector3(PI * 0.5, 0.0, 0.0), spin)
	var handle := CylinderMesh.new()
	handle.top_radius = 0.03
	handle.bottom_radius = 0.03
	handle.height = 0.24
	handle.radial_segments = 8
	handle.rings = 1
	_part(handle, _iron, Vector3(WHEEL_R - 0.05, 0.0, 0.14), Vector3(PI * 0.5, 0.0, 0.0), spin)
	for mi in winch.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return [winch, spin]


func _build_wheel() -> void:
	var w := make_winch(self, WHEEL_AT)
	_wheel = w[0]
	_wheel_spin = w[1]


# --- No prisoners, no swinging ----------------------------------------------------------

func stock() -> void:
	_prisoners.clear()


func swing_open(_now := false) -> void:
	pass


func arm() -> void:
	_blocker.disabled = _lift > 0.5


# --- Shut in, and winding out -----------------------------------------------------------

func _inside(p: Node3D) -> bool:
	var l := to_local(p.global_position)
	return l.z < GATE_Z - TRIGGER_IN and absf(l.x) < FACE and l.y > -1.0 and l.y < 3.0


func _process(delta: float) -> void:
	var players: Array = []
	for p in Coop.all():
		if is_instance_valid(p) and p.get("_dead") != true:
			players.append(p)
	var anyone := players.any(func(p) -> bool: return _inside(p))
	if not _locked:
		if not anyone:
			_armed = true
			_drop_in = -1.0
		elif _armed and _lift >= 1.0:
			if _drop_in < 0.0:
				_drop_in = DROP_DELAY
			_drop_in -= delta
			if _drop_in <= 0.0:
				_slam()
	# The wheel: whoever is in front of it and looking at it.
	_player = Coop.user_for(_wheel, _player)
	var near := false
	if _player != null and _locked:
		var to := _player.global_position - _wheel.global_position
		near = Vector2(to.x, to.z).length() <= WHEEL_REACH and absf(to.y) < 2.5 \
			and Interact.looked_at(_wheel, 3.2, 0.15, [], _player) and _player.get("in_cutscene") != true
	if _holder != null and (_holder != _player or not near or not is_instance_valid(_holder)
			or not Coop.held(_holder, &"interact")):
		_let_go_wheel()
	if _locked:
		var was := _lift
		if _holder != null:
			_lift = minf(_lift + delta / CRANK_TIME, 1.0)
		else:
			_lift = maxf(_lift - delta * SINK / CRANK_TIME, 0.0)
		_wheel_spin.rotation.z += (_lift - was) * TAU * 3.0
		_gate.position.y = LIFT * _lift
		if _lift >= 1.0:
			_unlock()
	_prompt.visible = near and _locked
	_prompt.player = _player
	_prompt.progress = _lift if _holder != null else -1.0


func _unhandled_input(event: InputEvent) -> void:
	if not _locked or _player == null or not _prompt.visible or not Interact.pressed(event, _player):
		return
	get_viewport().set_input_as_handled()
	_let_go_wheel()
	_holder = _player
	if _holder.has_signal("health_changed"):
		_holder.connect("health_changed", _on_holder_health)
	_holder_health = float(_holder.get("health"))


## A hit loosens the grip: the wheel runs back until it is taken again.
func _on_holder_health(current: float, _maximum: float) -> void:
	if current < _holder_health - 0.001:
		_let_go_wheel()
		return
	_holder_health = current


func _let_go_wheel() -> void:
	if _holder != null and is_instance_valid(_holder) and _holder.is_connected("health_changed", _on_holder_health):
		_holder.disconnect("health_changed", _on_holder_health)
	_holder = null


## The gate comes down behind them.
func _slam() -> void:
	_locked = true
	_armed = false
	_drop_in = -1.0
	_blocker.set_deferred("disabled", false)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_lift = v
		_gate.position.y = LIFT * v, _lift, 0.0, DROP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_landed)


func _landed() -> void:
	for p in Coop.all():
		if is_instance_valid(p) and (p as Node3D).global_position.distance_to(global_position) < 9.0 and p.get("_shake") != null:
			p.set("_shake", maxf(float(p.get("_shake")), 0.35))
	var gfx := get_node_or_null("/root/Graphics")
	if gfx != null and not bool(gfx.get("effects")):
		return
	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.emitting = false
	dust.amount = 14
	dust.lifetime = 1.6
	dust.explosiveness = 0.95
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(GATE_HALF, 0.05, 0.1)
	dust.direction = Vector3(0.0, 0.3, 1.0)
	dust.spread = 80.0
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 1.8
	dust.damping_min = 2.0
	dust.damping_max = 3.0
	dust.gravity = Vector3(0.0, 0.2, 0.0)
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.5, 0.44, 0.55))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.46, 0.4, 0.0))
	dust.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = load("res://textures/surgery_fx_dust.png")
	m.roughness = 1.0
	quad.material = m
	dust.mesh = quad
	_gate.add_child(dust)
	dust.position = Vector3(0.0, 0.1, 0.0)
	dust.restart()
	get_tree().create_timer(2.0).timeout.connect(dust.queue_free)


## Wound all the way up: open, and it stays up until they leave and come back.
func _unlock() -> void:
	_locked = false
	_armed = false
	_let_go_wheel()
	_blocker.set_deferred("disabled", true)
