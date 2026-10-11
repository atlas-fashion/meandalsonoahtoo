extends "res://scripts/enemy.gd"

## The warden bot (2026-10-09): a crude iron machine the dungeon's keepers built
## to herd the dead, walking on the power of a gold crystal caged in its chest.
## (The boss is THE WARDEN; these are his machines.)
##
## Made like the archer: the maze puts this script on an enemy.tscn instance
## before it enters the tree (so its numbers live in `_init`), and on entering
## the tree it throws the skeleton model away and builds its own body out of
## primitives -- merged per rigid part, so a bot is ~20 draws, and all bots
## share the meshes. No rig: the legs, arms and head are driven in code.
##
## One walks with every skeleton pack (maze.gd `_spawn_pack`), keeping close to
## its `escort` while they amble. The prison hubs (dungeon_room.gd) post more
## of them in front of their cells.
##
## Hunting (`_chase`, enemy.gd's hook):
##   * the BEAM: with a clear line through stone and the player within
##     BEAM_RANGE, it plants itself and charges (CHARGE_TIME -- the crystals
##     flare and a thin aiming line appears, the tell), then holds a beam on the
##     player for up to BEAM_TIME: `player.beam_hit` -- BEAM_DPS a second and
##     slowed, a raised guard taking a tenth. The beam swings after the player
##     at TRACK_RATE, so a fast sidestep (a ghost) can slip it; stone stops it,
##     its fellows do not. Then it vents for VENT_TIME.
##   * otherwise it walks in, and close enough it clubs (`attack_damage`).
## Heavy: 240 health, hard to shove, slow on its feet.

const BEAM_DPS := 5.0
const BEAM_RANGE := 20.0
const CHARGE_TIME := 0.65
const BEAM_TIME := 3.2
const VENT_TIME := 1.6
## Seconds after first noticing the player before the first charge.
const FIRST_BEAM := 0.6
## How fast the beam swings after the player, rad/s.
const TRACK_RATE := 0.95
## Stone: the sight layer and the exact walls.
const WORLD_MASK := 2 | 256
## The player as a capsule: feet + LOW to feet + HIGH, this thick.
const BODY_LOW := 0.25
const BODY_HIGH := 1.6
const BODY_RADIUS := 0.4
## Escorting a pack: closes up when further than this from its escort.
const ESCORT_FAR := 3.6
## Between beams it walks in only while further off than this (or out of line).
const KEEP_FAR := 12.0
## The drawn beam stops this far short of a player it is on.
const SHORT_OF_PLAYER := 0.8

const GOLD := Color(1.0, 0.72, 0.22)
const HOT := Color(1.0, 0.93, 0.7)

enum Beam { IDLE, CHARGE, FIRE, VENT }

## The skeleton it walks with, set by the maze. Null for a posted guard.
var escort: Node3D = null
## Its whole pack (escort included), which it does not collide with.
var pack: Array[Node3D] = []
## How close it lets a pack-mate stand before stepping aside.
const PACK_ROOM := 1.2

var _beam := Beam.IDLE
var _phase_until := 0.0
var _beam_ready := -1.0
var _aim_dir := Vector3.FORWARD
var _clear := false
var _next_clear := 0.0
var _lost_line_at := -1.0
var _beam_end := Vector3.ZERO
var _beam_on_player := false

var _built := false
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _gun_arm: Node3D
var _muzzle: Node3D
var _club_arm: Node3D
var _crystals: Array[MeshInstance3D] = []
var _parts: Array[MeshInstance3D] = []
var _beam_root: Node3D
## The core's and the glow's holders, stretched to the beam's length each tick.
var _spans: Array[Node3D] = []
var _beam_core: MeshInstance3D
var _beam_glow: MeshInstance3D
var _beam_flare: MeshInstance3D
var _beam_light: OmniLight3D
var _beam_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _stride := 0.0
var _club := 0.0

static var _meshes := {}
static var _mats := {}


func _init() -> void:
	# A club for an arm, not a sword (enemy.gd `armed`).
	armed = false
	max_health = 240.0
	move_speed = 2.7
	acceleration = 14.0
	vision_cone_degrees = 160.0
	sight_needs_line_of_sight = true
	sight_memory = 6.0
	eye_height = 1.95
	wanders = true
	wander_speed = 1.3
	can_slam = false
	can_normal = true
	normal_range = 1.9
	normal_duration = 0.35
	normal_cooldown = 2.2
	windup_time = 0.6
	recover_time = 0.75
	attack_damage = 22.0
	knockback_resistance = 0.85
	tint_albedo = false
	base_glow = 2.4
	windup_glow = 4.5
	attack_glow = 6.0
	windup_color = Color(1.0, 0.55, 0.15)
	attack_color = Color(1.0, 0.3, 0.1)
	hit_punch = 0.08
	display_name = "WARDEN BOT"
	drop_rolls_min = 1
	drop_rolls_max = 1
	drop_odds = {&"gold_crystal": 0.6, &"health_potion": 0.15}


func is_warden() -> bool:
	return true


# --- The body ---------------------------------------------------------------------

## Before `_ready` (and enemy.gd's @onready lookups): the skeleton goes, the
## robot goes in its place, and the capsule grows to fit it.
func _enter_tree() -> void:
	if _built:
		return
	_built = true
	var vis := get_node_or_null("Visual") as Node3D
	if vis == null:
		vis = Node3D.new()
		vis.name = "Visual"
		add_child(vis)
		move_child(vis, 0)
	for child in vis.get_children():
		vis.remove_child(child)
		child.free()
	_build_body(vis)
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.55
		cap.height = 2.25
		cs.shape = cap
		cs.position = Vector3(0.0, 1.125, 0.0)
	var ag := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if ag != null:
		ag.radius = 0.55
		ag.height = 2.25


func _ready() -> void:
	super()
	name = "Warden"
	add_to_group(&"wardens")
	# enemy.gd made its own copy of the first mesh's material -- the chest
	# crystal's -- and tints it by state; every crystal on the bot shares it.
	for c in _crystals:
		c.material_override = _material
	_build_beam()


func _build_body(vis: Node3D) -> void:
	var crystal := _mat(&"crystal")

	# The chest crystal first: enemy.gd takes the first mesh's material as its own.
	_torso = Node3D.new()
	_torso.name = "Torso"
	_torso.position = Vector3(0.0, 1.08, 0.0)
	vis.add_child(_torso)
	var core := _crystal_mesh(0.13, 0.26)
	core.position = Vector3(0.0, 0.5, -0.33)
	core.material_override = crystal
	_torso.add_child(core)
	_crystals.append(core)

	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0.0, 1.0, 0.0)
	vis.add_child(_hips)
	_hips.add_child(_part(&"hips", _fill_hips))

	# Legs: hip pivot, thigh, knee pivot, shin and a flat foot.
	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.3 * side, 1.0, 0.0)
		vis.add_child(hip)
		hip.add_child(_part(&"thigh", _fill_thigh))
		var knee := Node3D.new()
		knee.position = Vector3(0.0, -0.5, 0.0)
		hip.add_child(knee)
		knee.add_child(_part(&"shin", _fill_shin))
		_legs.append(hip)
		_knees.append(knee)

	_torso.add_child(_part(&"torso", _fill_torso))

	# A box of a head on a neck, one gold lens and an aerial.
	_head = Node3D.new()
	_head.position = Vector3(0.0, 0.92, 0.0)
	_torso.add_child(_head)
	_head.add_child(_part(&"head", _fill_head))
	var lens := _crystal_mesh(0.06, 0.05)
	lens.rotation.x = PI * 0.5
	lens.position = Vector3(0.05, 0.28, -0.21)
	lens.material_override = crystal
	_head.add_child(lens)
	_crystals.append(lens)

	# The beam arm (right): modelled along -Z, a barrel ending in a crystal.
	_gun_arm = Node3D.new()
	_gun_arm.position = Vector3(0.6, 0.82, 0.0)
	_torso.add_child(_gun_arm)
	_gun_arm.add_child(_part(&"gun_arm", _fill_gun_arm))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.0, -0.02, -0.98)
	_gun_arm.add_child(_muzzle)
	var tip := _crystal_mesh(0.07, 0.16)
	tip.rotation.x = PI * 0.5
	tip.position = Vector3(0.0, -0.02, -0.86)
	tip.material_override = crystal
	_gun_arm.add_child(tip)
	_crystals.append(tip)

	# The club arm (left): a pipe of an arm and an iron block of a fist,
	# hanging down (-Y).
	_club_arm = Node3D.new()
	_club_arm.position = Vector3(-0.6, 0.82, 0.0)
	_torso.add_child(_club_arm)
	_club_arm.add_child(_part(&"club_arm", _fill_club_arm))

	for mi in vis.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _fill_hips(add: Callable) -> void:
	add.call(_box(Vector3(0.78, 0.22, 0.46)), Transform3D(), _mat(&"iron"))
	add.call(_box(Vector3(0.82, 0.06, 0.5)), Transform3D(Basis(), Vector3(0.0, 0.12, 0.0)), _mat(&"brass"))
	add.call(_cyl(0.11, 0.11, 0.9, 8), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), _mat(&"dark"))


func _fill_thigh(add: Callable) -> void:
	add.call(_cyl(0.1, 0.12, 0.5, 8), Transform3D(Basis(), Vector3(0.0, -0.25, 0.0)), _mat(&"iron"))
	add.call(_box(Vector3(0.24, 0.3, 0.22)), Transform3D(Basis(), Vector3(0.0, -0.18, -0.02)), _mat(&"plate"))


func _fill_shin(add: Callable) -> void:
	add.call(_cyl(0.1, 0.1, 0.12, 8), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), _mat(&"brass"))
	add.call(_cyl(0.09, 0.13, 0.42, 8), Transform3D(Basis(), Vector3(0.0, -0.24, 0.0)), _mat(&"iron"))
	add.call(_cyl(0.035, 0.035, 0.4, 5), Transform3D(Basis(), Vector3(0.0, -0.22, 0.13)), _mat(&"brass"))
	add.call(_box(Vector3(0.3, 0.1, 0.46)), Transform3D(Basis(), Vector3(0.0, -0.5, -0.06)), _mat(&"plate"))


## The barrel of a body, riveted bands round it, the crystal in a cage at the
## front, a boiler stack at the back, plates bolted on askew.
func _fill_torso(add: Callable) -> void:
	var iron := _mat(&"iron")
	var plate := _mat(&"plate")
	var brass := _mat(&"brass")
	var dark := _mat(&"dark")
	add.call(_cyl(0.4, 0.44, 0.86, 12), Transform3D(Basis(), Vector3(0.0, 0.47, 0.0)), iron)
	for y: float in [0.1, 0.5, 0.86]:
		add.call(_cyl(0.455, 0.455, 0.06, 12), Transform3D(Basis(), Vector3(0.0, y, 0.0)), brass)
	# The crystal's window: a dark box sunk into the front, bars across it.
	add.call(_box(Vector3(0.36, 0.44, 0.12)), Transform3D(Basis(), Vector3(0.0, 0.5, -0.36)), dark)
	for x: float in [-0.12, 0.0, 0.12]:
		add.call(_cyl(0.014, 0.014, 0.46, 4), Transform3D(Basis(), Vector3(x, 0.5, -0.44)), brass)
	# Nobody built this carefully.
	add.call(_box(Vector3(0.34, 0.3, 0.05)), Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.FORWARD, 0.1),
		Vector3(0.32, 0.28, -0.24)), plate)
	add.call(_box(Vector3(0.3, 0.36, 0.05)), Transform3D(Basis(Vector3.UP, -0.6) * Basis(Vector3.FORWARD, -0.08),
		Vector3(-0.3, 0.62, -0.26)), plate)
	for side: float in [-1.0, 1.0]:
		add.call(_box(Vector3(0.3, 0.2, 0.36)), Transform3D(Basis(Vector3.FORWARD, -0.25 * side),
			Vector3(0.48 * side, 0.82, 0.0)), plate)
	add.call(_cyl(0.07, 0.09, 0.62, 8), Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.12, 1.0, 0.34)), dark)
	add.call(_cyl(0.1, 0.1, 0.06, 8), Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.12, 1.3, 0.4)), brass)
	add.call(_cyl(0.03, 0.03, 0.7, 5), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, 0.25, 0.42)), brass)


func _fill_head(add: Callable) -> void:
	add.call(_cyl(0.07, 0.09, 0.14, 6), Transform3D(Basis(), Vector3(0.0, 0.07, 0.0)), _mat(&"dark"))
	add.call(_box(Vector3(0.38, 0.28, 0.34)), Transform3D(Basis(Vector3.FORWARD, 0.04), Vector3(0.0, 0.27, 0.0)),
		_mat(&"plate"))
	add.call(_cyl(0.1, 0.1, 0.06, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.05, 0.28, -0.18)),
		_mat(&"brass"))
	add.call(_cyl(0.012, 0.012, 0.4, 4), Transform3D(Basis(Vector3.FORWARD, 0.2), Vector3(-0.12, 0.56, 0.06)),
		_mat(&"brass"))


func _fill_gun_arm(add: Callable) -> void:
	var brass := _mat(&"brass")
	add.call(_cyl(0.11, 0.11, 0.16, 8), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), brass)
	add.call(_cyl(0.08, 0.08, 0.32, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -0.18)),
		_mat(&"iron"))
	add.call(_cyl(0.13, 0.15, 0.48, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, -0.02, -0.56)),
		_mat(&"plate"))
	add.call(_cyl(0.16, 0.16, 0.05, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, -0.02, -0.8)), brass)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		add.call(_box(Vector3(0.03, 0.03, 0.16)), Transform3D(Basis(),
			Vector3(cos(a) * 0.13, -0.02 + sin(a) * 0.13, -0.88)), brass)


func _fill_club_arm(add: Callable) -> void:
	var iron := _mat(&"iron")
	var brass := _mat(&"brass")
	add.call(_cyl(0.11, 0.11, 0.16, 8), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), brass)
	add.call(_cyl(0.07, 0.08, 0.5, 8), Transform3D(Basis(), Vector3(0.0, -0.28, 0.0)), iron)
	add.call(_cyl(0.09, 0.09, 0.1, 8), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, -0.55, 0.0)), brass)
	add.call(_cyl(0.07, 0.08, 0.36, 8), Transform3D(Basis(), Vector3(0.0, -0.75, 0.0)), iron)
	add.call(_box(Vector3(0.3, 0.32, 0.3)), Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.0, -1.02, 0.0)),
		_mat(&"plate"))
	for k in 4:
		var a := TAU * float(k) / 4.0
		add.call(_box(Vector3(0.06, 0.06, 0.06)), Transform3D(Basis(), Vector3(cos(a) * 0.17, -1.02, sin(a) * 0.17)),
			brass)


## One rigid part: every primitive `fill` adds, merged into one mesh with a
## surface per material, built once and shared by every bot.
func _part(key: StringName, fill: Callable) -> MeshInstance3D:
	if not _meshes.has(key):
		var tools := {}
		var add := func(mesh: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			(tools[mat] as SurfaceTool).append_from(mesh, 0, xf)
		fill.call(add)
		var am := ArrayMesh.new()
		for mat in tools:
			var st: SurfaceTool = tools[mat]
			st.generate_normals()
			st.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		_meshes[key] = am
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	_parts.append(mi)
	return mi


func _crystal_mesh(radius: float, height: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var key := "crystal_%.2f_%.2f" % [radius, height]
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = radius
		s.height = height
		s.radial_segments = 4
		s.rings = 2
		_meshes[key] = s
	mi.mesh = _meshes[key]
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = maxi(sides, 4)
	c.rings = 1
	return c


static func _tube(top: float, bottom: float, sides: int) -> CylinderMesh:
	var c := _cyl(top, bottom, 1.0, sides)
	c.cap_top = false
	c.cap_bottom = false
	return c


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"iron":
			# Not fully metallic: in these halls there is nothing for it to reflect
			# and full metal renders black.
			m.albedo_color = Color(0.3, 0.25, 0.21)
			m.metallic = 0.45
			m.roughness = 0.72
		&"plate":
			m.albedo_color = Color(0.36, 0.24, 0.16)
			m.metallic = 0.35
			m.roughness = 0.82
		&"brass":
			m.albedo_color = Color(0.56, 0.42, 0.18)
			m.metallic = 0.55
			m.roughness = 0.5
		&"dark":
			m.albedo_color = Color(0.07, 0.06, 0.05)
			m.roughness = 0.9
		&"crystal":
			m.albedo_color = GOLD
			m.emission_enabled = true
			m.emission = GOLD
			m.emission_energy_multiplier = 2.4
			m.roughness = 0.2
		&"flash":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(1.0, 0.9, 0.75, 0.55)
	_mats[key] = m
	return m


# --- The beam ---------------------------------------------------------------------

func _build_beam() -> void:
	_beam_root = Node3D.new()
	_beam_root.name = "Beam"
	_beam_root.top_level = true
	_beam_root.visible = false
	add_child(_beam_root)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(HOT, 0.9)
	_glow_mat = _beam_mat.duplicate()
	_glow_mat.albedo_color = Color(GOLD, 0.22)
	# Unit length along -Z from the muzzle; scaled to the beam's length.
	# Open tubes narrowing toward the far end: seen down its length by the
	# player it hits, a capped tube ended in a flat disc under their eyes.
	# (Turned +90 about X, the mesh's top is at the muzzle, its bottom at the end.)
	_beam_core = MeshInstance3D.new()
	_beam_core.mesh = _tube(0.035, 0.012, 6)
	_beam_core.material_override = _beam_mat
	_beam_glow = MeshInstance3D.new()
	_beam_glow.mesh = _tube(0.11, 0.02, 8)
	_beam_glow.material_override = _glow_mat
	for mi: MeshInstance3D in [_beam_core, _beam_glow]:
		mi.rotation.x = PI * 0.5
		mi.position.z = -0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.add_child(mi)
		_beam_root.add_child(holder)
		_spans.append(holder)
	_beam_flare = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	s.radial_segments = 10
	s.rings = 5
	_beam_flare.mesh = s
	_beam_flare.material_override = _glow_mat
	_beam_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_root.add_child(_beam_flare)


func _chase(delta: float, now: float, player: Node3D, flat: Vector3, distance: float, gap: float) -> bool:
	if now >= _next_clear:
		_next_clear = now + 0.12
		_clear = _line_to(player)
	if _beam_ready < 0.0:
		_beam_ready = now + FIRST_BEAM
	match _beam:
		Beam.CHARGE:
			_hold(delta)
			_face(flat)
			_aim_dir = _turn_toward(_aim_dir, _target_dir(player), TRACK_RATE * 3.0 * delta)
			if now >= _phase_until:
				_beam = Beam.FIRE
				_phase_until = now + BEAM_TIME
				_lost_line_at = -1.0
			return true
		Beam.FIRE:
			_hold(delta)
			_aim_dir = _turn_toward(_aim_dir, _target_dir(player), TRACK_RATE * delta)
			var aim_flat := Vector3(_aim_dir.x, 0.0, _aim_dir.z)
			_face(aim_flat)
			if not _clear:
				if _lost_line_at < 0.0:
					_lost_line_at = now
			else:
				_lost_line_at = -1.0
			if now >= _phase_until or (_lost_line_at >= 0.0 and now - _lost_line_at > 0.7):
				_vent(now)
			return true
	# Up close it clubs; the base chase steps in and swings.
	if gap <= normal_range + 0.4:
		return false
	if now >= _beam_ready and _clear and distance <= BEAM_RANGE:
		_beam = Beam.CHARGE
		_phase_until = now + CHARGE_TIME
		_aim_dir = _target_dir(player)
		_hold(delta)
		_face(flat)
		return true
	# Between beams it keeps its range: on if too far or out of line, otherwise
	# it stands its ground and watches. It does not walk into a fist fight --
	# but come to it and it clubs.
	if distance > KEEP_FAR or not _clear:
		_walk_to(delta, now, player.global_position, move_speed)
		_face_velocity(flat)
	else:
		_hold(delta)
		_face(flat)
	return true


## Along the navmesh toward `goal`, at `speed`.
func _walk_to(delta: float, now: float, goal: Vector3, speed: float) -> void:
	var dir := _path_dir(now, goal)
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	move_and_slide()


## The way to go for `goal`: the next corner of the navmesh path, or straight.
func _path_dir(now: float, goal: Vector3) -> Vector3:
	var to := goal - global_position
	to.y = 0.0
	var dir := to.normalized() if to.length_squared() > 0.0001 else Vector3.ZERO
	if agent != null:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = goal
		if not agent.is_navigation_finished():
			var step := agent.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.1:
				dir = step.normalized()
	return dir


func _face_velocity(fallback: Vector3) -> void:
	var v := Vector3(velocity.x, 0.0, velocity.z)
	_face(v if v.length_squared() > 0.25 else fallback)


func _vent(now: float) -> void:
	_beam = Beam.VENT
	_beam_ready = now + VENT_TIME
	_beam_on_player = false


## Lowers the beam the moment it stops hunting -- shoved, swinging, lost the
## player, killed -- so it never hangs in the air.
func _cancel_beam() -> void:
	if _beam == Beam.CHARGE or _beam == Beam.FIRE:
		_vent(_now())
	if _beam_root != null:
		_beam_root.visible = false
	if _beam_light != null:
		_beam_light.visible = false


func _target_dir(player: Node3D) -> Vector3:
	var from := _muzzle.global_position if _muzzle != null else global_position + Vector3(0.0, 1.9, 0.0)
	var to := player.global_position + Vector3(0.0, 1.15, 0.0)
	var d := to - from
	return d.normalized() if d.length_squared() > 0.0001 else -global_basis.z


static func _turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle := from.angle_to(to)
	if angle <= max_angle or angle < 1e-4:
		return to
	return from.slerp(to, max_angle / angle).normalized()


func _hold(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	move_and_slide()


## A clear line from the muzzle to the player's chest through stone. Its
## fellows do not count: the beam passes them.
func _line_to(player: Node3D) -> bool:
	var from := _muzzle.global_position if _muzzle != null else global_position + Vector3(0.0, 1.9, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3(0.0, 1.15, 0.0),
		WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Fires the beam for this tick: from the muzzle along the aim to the first
## stone, and onto the player if they are in its path.
func _fire(delta: float) -> void:
	var from := _muzzle.global_position
	var to := from + _aim_dir * (BEAM_RANGE + 6.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		to = hit["position"]
	_beam_end = to
	_beam_on_player = false
	var player := _resolve_player()
	if _beam == Beam.FIRE and player != null and player.get("_dead") != true:
		var a := player.global_position + Vector3(0.0, BODY_LOW, 0.0)
		var b := player.global_position + Vector3(0.0, BODY_HIGH, 0.0)
		var pts := Geometry3D.get_closest_points_between_segments(from, to, a, b)
		if (pts[0] as Vector3).distance_to(pts[1]) < BODY_RADIUS:
			_beam_end = pts[0]
			_beam_on_player = true
			if player.has_method("beam_hit"):
				player.call("beam_hit", BEAM_DPS, delta, _aim_dir)


func _draw_beam(now: float) -> void:
	var on := _beam == Beam.CHARGE or _beam == Beam.FIRE
	_beam_root.visible = on
	if not on:
		if _beam_light != null:
			_beam_light.visible = false
		return
	var from := _muzzle.global_position
	var length := maxf(from.distance_to(_beam_end), 0.05)
	var dir := (_beam_end - from) / length
	# On the player it is drawn stopping short of them: it ends at their chest,
	# half a metre under the eye, and drawn all the way its glow filled the
	# bottom of the screen as a gold wedge.
	if _beam_on_player:
		length = maxf(length - SHORT_OF_PLAYER, 0.1)
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	_beam_root.global_transform = Transform3D(Basis.looking_at(dir, up), from)
	var charging := _beam == Beam.CHARGE
	# Charging: a thin, faint aiming line. Firing: a full beam that shivers.
	var t := 1.0 - clampf((_phase_until - now) / CHARGE_TIME, 0.0, 1.0) if charging else 1.0
	var width := lerpf(0.15, 0.35, t) if charging else 1.0 + 0.18 * sin(now * 61.0) + 0.1 * sin(now * 23.0)
	# By reference: two siblings named alike get renamed, and a lookup by name
	# left the glow a metre long while the core reached the target.
	for holder in _spans:
		holder.scale = Vector3(width, width, length)
	_beam_mat.albedo_color.a = lerpf(0.15, 0.45, t) if charging else 0.95
	_glow_mat.albedo_color.a = lerpf(0.05, 0.12, t) if charging else 0.26
	# Not on the player: a flare right under their eyes is a blot on the view, and
	# the HUD's gold edge already says they are in it.
	_beam_flare.visible = not charging and not _beam_on_player
	_beam_flare.position = Vector3(0.0, 0.0, -length)
	_beam_flare.scale = Vector3.ONE * (0.6 if _beam_on_player else 0.9) * width
	if Graphics.effects and not charging:
		if _beam_light == null:
			_beam_light = OmniLight3D.new()
			_beam_light.light_color = GOLD
			_beam_light.light_energy = 2.2
			_beam_light.omni_range = 4.5
			_beam_light.shadow_enabled = false
			_beam_light.top_level = true
			add_child(_beam_light)
		_beam_light.visible = true
		_beam_light.global_position = _beam_end - dir * 0.4


# --- Driving it ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dying:
		return
	super(delta)
	if _dying or _dormant:
		if _beam_root != null and _beam_root.visible:
			_cancel_beam()
		return
	var now := _now()
	# Anything that takes it off its feet or out of the hunt drops the beam.
	if (_beam == Beam.CHARGE or _beam == Beam.FIRE) \
			and (state != State.CHASE or not engaged or is_stunned()):
		_cancel_beam()
	if _beam == Beam.FIRE:
		_fire(delta)
	elif _beam == Beam.CHARGE:
		_beam_end = _muzzle.global_position + _aim_dir * minf(BEAM_RANGE,
			_muzzle.global_position.distance_to(_resolve_player().global_position) if _resolve_player() != null else BEAM_RANGE)
	_draw_beam(now)
	_animate(delta, now)


## Legs, bob, head and arms. No rig: every joint is a node turned here.
func _animate(delta: float, now: float) -> void:
	var v := get_real_velocity()
	var speed := Vector2(v.x, v.z).length()
	var walking := clampf(speed / 1.6, 0.0, 1.0)
	_stride += delta * (2.0 + speed * 2.4)
	var swing := sin(_stride) * 0.55 * walking
	for i in _legs.size():
		var s := swing if i == 0 else -swing
		_legs[i].rotation.x = s
		# The knee bends on the forward swing and straightens to plant.
		_knees[i].rotation.x = maxf(0.0, sin(_stride + (0.0 if i == 0 else PI) + 0.9)) * 0.7 * walking
	_hips.position.y = 1.0 - absf(cos(_stride)) * 0.05 * walking
	_torso.position.y = 1.08 - absf(cos(_stride)) * 0.06 * walking
	_torso.rotation.z = sin(_stride) * 0.05 * walking
	# Head: toward the player while hunting, otherwise a slow look about.
	var player := _resolve_player()
	var head_yaw := sin(now * 0.7 + float(get_instance_id() % 97)) * 0.5
	if engaged and player != null:
		var to := to_local(player.global_position)
		head_yaw = clampf(atan2(-to.x, -to.z), -1.0, 1.0)
	_head.rotation.y = lerp_angle(_head.rotation.y, head_yaw, clampf(delta * 5.0, 0.0, 1.0))

	# The gun arm: along the aim while charging or firing, otherwise hanging
	# forward and down.
	var aiming := _beam == Beam.CHARGE or _beam == Beam.FIRE
	if aiming:
		var up := Vector3.UP if absf(_aim_dir.y) < 0.95 else Vector3.FORWARD
		var want := Basis.looking_at(_aim_dir, up)
		var cur := _gun_arm.global_basis.orthonormalized()
		_gun_arm.global_basis = cur.slerp(want, clampf(delta * 14.0, 0.0, 1.0))
	else:
		var rest := Basis(Vector3.RIGHT, -1.05 + sin(_stride) * 0.15 * walking)
		_gun_arm.basis = _gun_arm.basis.orthonormalized().slerp(rest, clampf(delta * 6.0, 0.0, 1.0))

	# The club: back and up through the wind-up, down hard through the blow.
	var club_target := -sin(_stride) * 0.3 * walking
	match state:
		State.WINDUP:
			club_target = 2.4
		State.ATTACK:
			club_target = -1.1
		State.RECOVER:
			club_target = -0.4
	var rate := 20.0 if state == State.ATTACK else 7.0
	_club = lerpf(_club, club_target, clampf(delta * rate, 0.0, 1.0))
	_club_arm.rotation.x = _club

	# The crystals: their rest glow, flaring through a charge and burning hot
	# while it fires. (enemy.gd's state colours ride on the same material.)
	if _material != null:
		var e := base_glow
		var col := GOLD
		match _beam:
			Beam.CHARGE:
				var t := 1.0 - clampf((_phase_until - now) / CHARGE_TIME, 0.0, 1.0)
				e = lerpf(base_glow, 9.0, t) * (1.0 + 0.25 * sin(now * 40.0))
				col = GOLD.lerp(HOT, t)
			Beam.FIRE:
				e = 7.5 + 1.5 * sin(now * 53.0)
				col = HOT
			Beam.VENT:
				e = base_glow * 0.5
		if state == State.WINDUP:
			e = windup_glow
			col = windup_color
		elif state == State.ATTACK:
			e = attack_glow
			col = attack_color
		_material.emission = col
		_material.emission_energy_multiplier = e


## Ambling with its pack: it keeps close to its escort rather than wandering
## its own way. Alone (a posted guard, or its pack dead), it wanders as usual.
func _wander(delta: float, now: float) -> Vector3:
	# On patrol with its pack (patrol.gd): at the back of the column.
	if patrol != null and is_instance_valid(patrol):
		return patrol.call("step", self, delta, now)
	if escort != null and is_instance_valid(escort) and escort.get("_dying") != true:
		# It passes through its pack (so two of them side by side cannot wall
		# it in), so it keeps its own room: never stood inside one of them.
		var apart := Vector3.ZERO
		for m in pack:
			if not is_instance_valid(m):
				continue
			var off := global_position - m.global_position
			off.y = 0.0
			var d := off.length()
			if d < PACK_ROOM:
				apart += (off / maxf(d, 0.01)) * (PACK_ROOM - d)
		var to := escort.global_position - global_position
		to.y = 0.0
		if apart != Vector3.ZERO and to.length() <= ESCORT_FAR:
			return apart.normalized() * wander_speed
		if to.length() > ESCORT_FAR:
			# Along the navmesh: its pack may be round a corner.
			var heading := _path_dir(now, escort.global_position)
			_face(heading)
			return heading * wander_speed
		# Close enough: stand by and look the way its escort looks.
		rotation.y = lerp_angle(rotation.y, escort.rotation.y, clampf(delta * 1.5, 0.0, 1.0))
		return Vector3.ZERO
	return super(delta, now)


# --- Taking blows and dying ---------------------------------------------------------

func _flash() -> void:
	super()
	var flash := _mat(&"flash")
	for mi in _parts:
		mi.material_overlay = flash
	get_tree().create_timer(0.08).timeout.connect(_unflash)


func _unflash() -> void:
	for mi in _parts:
		if is_instance_valid(mi):
			mi.material_overlay = null


## It does not fold up like a skeleton: the crystal gutters, sparks fly, it
## drops onto its knees, tips forward and lies a moment before it goes.
func _die() -> void:
	_cancel_beam()
	_dying = true
	died.emit()
	shape.disabled = true
	_grant_drop()
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	visual.scale = _mesh_scale
	if Graphics.effects:
		_sparks()
	if _material != null:
		var t := create_tween()
		for k in 5:
			t.tween_property(_material, "emission_energy_multiplier", 8.0 if k % 2 == 0 else 0.4, 0.07)
		t.tween_property(_material, "emission_energy_multiplier", 0.0, 0.5)
	var fall := create_tween().set_parallel(true)
	fall.tween_property(visual, "position:y", -0.45, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(visual, "rotation:x", -0.95, 0.7).set_delay(0.3) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for i in _legs.size():
		fall.tween_property(_legs[i], "rotation:x", -1.3, 0.4)
		fall.tween_property(_knees[i], "rotation:x", 1.9, 0.4)
	fall.tween_property(_club_arm, "rotation:x", -0.2, 0.5)
	fall.tween_property(_gun_arm, "rotation", Vector3(-0.3, 0.0, 0.0), 0.5)
	var gone := create_tween()
	gone.tween_interval(2.6)
	gone.tween_property(self, "scale", Vector3(1.0, 0.01, 1.0), 0.4).set_ease(Tween.EASE_IN)
	gone.tween_callback(queue_free)


func _sparks() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 36
	p.lifetime = 0.9
	p.explosiveness = 0.9
	p.direction = Vector3(0.0, 1.0, -0.4)
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0.0, -9.0, 0.0)
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = HOT
	q.material = m
	p.mesh = q
	p.position = Vector3(0.0, 1.55, -0.3)
	add_child(p)
	p.emitting = true
