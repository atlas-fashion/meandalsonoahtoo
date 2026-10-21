extends CharacterBody3D

## The surgical table (2026-10-21; made stationary with a ceiling claw on
## 2026-10-21, note 95): the machine in the surgery (surgery.gd) that was to make
## the dead prisoners bionic. It cannot be killed -- a blow on it only rings off
## the iron -- only DEPOWERED.
##
## The table itself never moves: a riveted iron slab on a base of gears and
## pistons (models/surgery/table.glb, Higgsfield), in the middle of the hall,
## a dead prisoner strapped to it with a drill half fitted to the forearm.
## Above it hangs the CEILING RING (ring.glb) and from the ring the CLAW: a very
## long jointed arm (segment.glb, as many as its length needs) ending in a
## three-fingered claw (claw.glb) with one red lens at the wrist. A player
## walking in wakes it: the restraints snap open and throw the body off, the
## claw unfolds from the vault and hunts the hall.
##
## The arm leaves the centre bay through the gap between two piers -- the aisle
## nearest its target (`_theta`, snapped to the room's axes) -- and to change
## aisles it first draws the claw back into the bay, turns, and reaches out
## again, so it never passes through the stone. Where its line to a player is
## blocked by a pier it cannot strike them: the piers are cover.
##
## Three SYSTEMS, each fed by its own thick cable to its own wall mechanism
## (surgery.gd draws the cables and works the mechanisms off what this exposes):
## - ARMS: the claw's drive: the GRAB (a lunge along the aim that runs on past
##   the player until stone stops it) and the SWEEP (a sideways rake). Their
##   cable twitches whenever the claw strikes (`arm_motion`).
## - LEGS (kept as the key the saves, levers and cables use): the HOIST that
##   holds the arm up -- the hovering, and the SLAM. Its cable shivers as the
##   claw travels (`leg_motion`).
## - CORE: the light in the table's base. Its cable pulses with it (`core_glow`).
## A lever cuts one for a while (`cut`): the claw goes limp; the hoist gives and
## the claw sags to the floor, dragging; the core stalls it for a moment and then
## the arms' and hoist's cables flare as they feed it back (`feed_*`). Each first
## cut makes it angrier (`level`): faster, quicker to strike, its levers shorter.
##
## Its weakness is the POWER CABLE wound round the claw's wrist: three cuts
## sever it (`_cable_hit`). It is only in reach when the wrist is (`exposed`):
## stuck in the floor after a slam, held by the wall clamp, or sagging with the
## hoist dead. The ways to finish it:
## - lure the claw into the wall clamp (opened by cutting the ARMS -- it sits on
##   the arms' relay; it stands at the end of an aisle) and cut the cable while
##   it is held;
## - cut the cable while the claw is stuck after a slam;
## - jam the hoist's flywheel while the hoist is cut, so the claw sags for good;
## - the relay sequence: cut the CORE while the arms and hoist are both cut, so
##   nothing feeds it back.

signal depowered(cause: StringName)
signal system_changed(system: StringName, on: bool)
signal woke

const SKELETON := preload("res://models/ossuary_skeleton_rigged.glb")
const SkeletonSword := preload("res://scripts/skeleton_sword.gd")
const ITEM_DROP := preload("res://scripts/item_drop.gd")
const TABLE_MODEL := preload("res://models/surgery/table.glb")
const RING_MODEL := preload("res://models/surgery/ring.glb")
const CLAW_MODEL := preload("res://models/surgery/claw.glb")
const SEGMENT_MODEL := preload("res://models/surgery/segment.glb")

enum State { DORMANT, WAKING, HUNT, GRAB, SWEEP, REAR, CLAMPED, STALL, DYING, DEAD }

## --- The table -------------------------------------------------------------------
## The slab's top off the floor (the model is 3.0 long along Z, 1.48 wide).
const TOP := 1.2
const TABLE_SIZE := Vector3(1.48, 1.2, 3.0)
## Its collision: the slab and base. Kept for the old navmesh code and the
## sandbox, which read it.
const RADIUS := 1.6
## The core: two glass bulbs either side of the base, and the three plugs the
## cables come out of (arms, legs, core) at its foot end, table frame.
const CORE_AT := Vector3(0.52, 0.55, 0.0)
const PLUGS := [Vector3(-0.32, 0.3, 1.15), Vector3(0.32, 0.3, 1.15), Vector3(0.0, 0.25, 1.25)]
## The colours.
const CORE_COLOUR := Color(0.55, 0.9, 1.0)
const EYE_COLOUR := Color(1.0, 0.32, 0.12)
const FEED_COLOUR := Color(1.0, 0.72, 0.4)

## --- The ring and the arm (the room's frame: the hall's middle on the floor) -----
## Measured off the hall (morgue.gd's vaults: the crown 5.1 m, the piers 6 m
## apart, 2.2 m square): the centre bay is clear for 1.9 m each way, and the
## arches over the gaps between its piers are over 4.4 m high.
const RING_TOP := 4.8
const RING_SCALE := 0.9
## Where the arm leaves the ring's hub, where it passes over the edge of the
## centre bay, and where it has cleared the piers' line (4.1 m) into the aisle.
const ROOT := Vector3(0.0, 4.15, 0.0)
const GAP_NEAR := 1.7
const GAP_NEAR_Y := 3.95
const GAP_FAR := 4.6
const GAP_FAR_Y := 3.55
## Inside this radius the claw can turn to another aisle without meeting stone.
const BAY_SAFE := 2.3
## Arm segments: about this long each, this thick (the model is 0.13 m).
const SEG_LEN := 1.05
const SEG_MAX := 16
const SEG_THICK := 2.7
## The claw: wrist to fingertips, and its scale.
const CLAW_LEN := 1.55
const CLAW_SCALE := 0.95
## Folded up under the ring, asleep.
const FOLD := Vector3(0.0, 3.55, 0.0)
## Hovering over the hall, this high (the wrist), this far short of its target.
const HOVER_Y := 3.25
const HOVER_SHORT := 3.4
## As far as the wrist reaches from the middle, hovering and lunging.
const HOVER_REACH := 9.5
const LUNGE_REACH := 13.4

## --- Pace, by anger (`level` 0..4) ------------------------------------------------
## The wrist's top speed while it hunts (m/s), and the arm's turn between aisles.
const SPEED: Array[float] = [3.6, 4.3, 5.0, 5.8, 6.6]
const TURN: Array[float] = [1.7, 2.0, 2.4, 2.8, 3.2]
## Sagging, the hoist dead: dragged along the floor this fast.
const DRAG_SPEED := 1.1
## Lever cuts last this long.
const CUT_TIME: Array[float] = [7.5, 6.5, 5.5, 5.0, 4.5]
const LEVEL_MAX := 4

## --- The grab ------------------------------------------------------------------
## It strikes at anyone within GRAB_RANGE of the middle whose line from the
## aisle is clear, and the claw runs on past the aim to GRAB_REACH unless stone
## stops it -- so a player who stands before the clamp and steps aside sends it
## on into the jaws.
const GRAB_RANGE := 12.6
const GRAB_MIN := 2.2
const GRAB_REACH := 9.5
const GRAB_WINDUP: Array[float] = [1.15, 1.0, 0.88, 0.78, 0.7]
## The aim is fixed this long before the lunge: step aside then.
const GRAB_LOCK := 0.28
const GRAB_LUNGE := 0.22
const GRAB_HOLD := 0.45
const GRAB_RETRACT := 0.9
const GRAB_DAMAGE := 20.0
const GRAB_YANK := 6.0
const GRAB_COOLDOWN: Array[float] = [3.6, 3.1, 2.7, 2.3, 2.0]
## A body this close to the claw's line is caught by it.
const GRAB_HIT := 0.75

## --- The sweep -------------------------------------------------------------------
## A rake sideways through anyone this close to the hovering claw.
const SWEEP_RANGE := 2.8
const SWEEP_SPAN := 2.8
const SWEEP_WINDUP: Array[float] = [0.7, 0.62, 0.55, 0.5, 0.45]
const SWEEP_SWING := 0.28
const SWEEP_RECOVER := 0.55
const SWEEP_DAMAGE := 12.0
const SWEEP_HIT := 1.3
const SWEEP_COOLDOWN: Array[float] = [2.4, 2.1, 1.8, 1.6, 1.4]

## --- The slam (State.REAR) ---------------------------------------------------------
## Up over the player, a hold, down into the floor -- and stuck there, the
## wrist's cable in reach, until it tears itself free.
const REAR_RANGE := 9.0
const REAR_RISE := 0.8
const REAR_HOLD := 0.45
const REAR_SLAM := 0.14
const REAR_STUCK := 1.9
const REAR_SETTLE := 0.6
const REAR_HIGH := 4.0
const REAR_DAMAGE := 24.0
const REAR_RADIUS := 2.4
const REAR_COOLDOWN: Array[float] = [7.0, 6.2, 5.5, 5.0, 4.5]

## --- The core stalled -----------------------------------------------------------
const STALL_TIME := 1.9
## When in the stall the cut systems' cables flare, feeding it back.
const FEED_AT := 0.9

## --- The power cable ------------------------------------------------------------
const CABLE_CUTS := 3
## Held by the wall clamp this long while the hoist pulls (`level` shortens it).
const CLAMP_HOLD: Array[float] = [7.5, 6.8, 6.0, 5.4, 4.8]

var room: Node3D
## Not used since the table stopped walking; kept for surgery.gd's setter.
var nav_map := RID()
## Where it stands, and which way.
var home := Vector3.ZERO
var home_yaw := 0.0
## The room's walls, as half its inner square in the room's frame.
var bound := 12.6

var state: State = State.DORMANT
var level := 0
var cuts := 0
var legs_jammed := false
## What the cables and mechanisms show (surgery.gd), 0..1.
var arm_motion := 0.0
var leg_motion := 0.0
var core_glow := 0.0
var feed_arms := 0.0
var feed_legs := 0.0
## While the wrist's power cable is in reach.
var exposed := false
## The axe treats a body with this set as down (axe.gd `_is_down`).
var _dying := false

var _t := 0.0
var _arms_off_until := -INF
var _legs_off_until := -INF
var _was_arms := true
var _was_legs := true
var _cut_once := {}
var _target: Node3D = null
var _next_grab := 0.0
var _next_sweep := 0.0
var _next_rear := 0.0
var _hit_done := false
var _aim := Vector3.FORWARD
var _aim_locked := false
var _reach := GRAB_REACH
var _clamp_point := Vector3.ZERO
var _strain := 0.0
var _last_cable_hit := -INF
var _stun_until := 0.0

## The claw, in the room's frame: the wrist, the way the claw points from it,
## the aisle the arm is in (an angle about Y from the room's +X).
var _w := FOLD
var _axis := Vector3.DOWN
var _theta := 0.0
## The aisle it is turning to (a multiple of PI / 2); `_theta` eases to it.
var _aisle := 0.0
var _want_w := FOLD
var _want_axis := Vector3.DOWN
var _w_speed := 3.0
var _w_vel := 0.0
## Moves: where a lunge started and where a sweep or slam goes.
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _side := Vector3.RIGHT
var _blocked := false

## Pose, eased.
var _power := 0.0
var _roll := 0.0
var _spin := 0.0

## Nodes.
var _body: Node3D
var _lens_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _belly_mat: StandardMaterial3D
var _core_light: OmniLight3D
var _eye_light: OmniLight3D
var _power_mats: Array = []
var _ring: Node3D
var _claw: Node3D
var _segs: Array[MeshInstance3D] = []
var _seg_mesh: Mesh
var _cuffs: Array[Node3D] = []
var _cable_box: StaticBody3D
var _claw_box: StaticBody3D
var _prisoner: Node3D
var _prisoner_rest := Transform3D()
var _audio: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _phase := Vector3.ZERO

static var _mats := {}


## A hitbox on the wrist's power cable: anything that hurts takes a cut out of
## it.
class CableHitbox extends StaticBody3D:
	var table: Node

	func take_damage(_amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
		if is_instance_valid(table):
			table.call("_cable_hit", from_direction)


## The claw's fingers: a blow only rings off them.
class ClawHitbox extends StaticBody3D:
	var table: Node

	func take_damage(_amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
		if is_instance_valid(table):
			table.call("_ring_off", global_position, from_direction)


# --- Building ---------------------------------------------------------------------

func _ready() -> void:
	add_to_group(&"surgical_table")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Solid to everyone (1) and hurtable (3) -- the blow only rings off it.
	collision_layer = 1 | 4
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(TABLE_SIZE.x, TABLE_SIZE.y, TABLE_SIZE.z)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, TABLE_SIZE.y * 0.5, 0.0)
	add_child(cs)
	_build_body()
	_build_arm()
	_build_audio()
	_phase = Vector3(randf() * 10.0, randf() * 10.0, randf() * 10.0)
	_sleep_pose()


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var model: Node3D = TABLE_MODEL.instantiate()
	model.name = "Table"
	_body.add_child(model)
	_shadows(model)
	_power_glow(model, 0.55)

	# The core: a glass bulb of light either side of the base.
	_core_mat = _mat(&"core").duplicate()
	for s: float in [-1.0, 1.0]:
		var core := MeshInstance3D.new()
		core.name = "Core"
		core.mesh = _merge_mesh([[_sphm(0.15), Transform3D(), &"core"]])
		core.material_override = _core_mat
		core.position = CORE_AT * Vector3(s, 1.0, 1.0)
		_body.add_child(core)
		_body.add_child(_merge([[_torusm(0.13, 0.19), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), CORE_AT * Vector3(s, 1.0, 1.0)), &"brass"]], "Porthole"))
	for p: Vector3 in PLUGS:
		_body.add_child(_merge([[_cylm(0.085, 0.085, 0.16, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p), &"brass"]], "Plug"))
	_core_light = OmniLight3D.new()
	_core_light.name = "CoreLight"
	_core_light.light_color = CORE_COLOUR
	_core_light.omni_range = 5.5
	_core_light.omni_attenuation = 1.4
	_core_light.light_energy = 0.0
	_core_light.light_specular = 0.3
	_core_light.shadow_enabled = false
	_core_light.position = Vector3(0.0, 0.45, 0.0)
	_body.add_child(_core_light)

	# The restraints on the top: wrists by the head, ankles by the foot. Each a
	# hinged steel cuff over a leather strap, shut over the prisoner.
	var cuff_at := [Vector3(-0.3, 0.0, -0.52), Vector3(0.3, 0.0, -0.52), Vector3(-0.13, 0.0, 0.92), Vector3(0.13, 0.0, 0.92)]
	for c: Vector3 in cuff_at:
		var hinge := Node3D.new()
		hinge.name = "Restraint"
		var side := signf(c.x)
		hinge.position = Vector3(c.x + side * 0.12, TOP + 0.01, c.z)
		_body.add_child(hinge)
		var cuff_parts: Array = [
			[_boxm(Vector3(0.26, 0.04, 0.1)), Transform3D(Basis(), Vector3(-side * 0.12, 0.09, 0.0)), &"steel"],
			[_boxm(Vector3(0.04, 0.1, 0.1)), Transform3D(Basis(), Vector3(-side * 0.24, 0.05, 0.0)), &"steel"],
			[_boxm(Vector3(0.04, 0.1, 0.1)), Transform3D(Basis(), Vector3(0.0, 0.05, 0.0)), &"steel"],
			[_boxm(Vector3(0.24, 0.015, 0.08)), Transform3D(Basis(), Vector3(-side * 0.12, 0.115, 0.0)), &"leather"],
		]
		hinge.add_child(_merge(cuff_parts, "Cuff"))
		_cuffs.append(hinge)
	_build_prisoner()


## The ring in the vault and the arm and claw hanging from it. All of it is
## placed in world space every frame from the room's frame (`_pose_arm`).
func _build_arm() -> void:
	_ring = RING_MODEL.instantiate()
	_ring.name = "CeilingRing"
	_ring.top_level = true
	add_child(_ring)
	_shadows(_ring)
	_power_glow(_ring, 0.45)
	var seg_scene := SEGMENT_MODEL.instantiate()
	for node in seg_scene.find_children("*", "MeshInstance3D", true, false):
		_seg_mesh = (node as MeshInstance3D).mesh
		break
	seg_scene.free()
	for i in SEG_MAX:
		var seg := MeshInstance3D.new()
		seg.name = "ArmSegment%d" % i
		seg.mesh = _seg_mesh
		seg.top_level = true
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(seg)
		_segs.append(seg)
		_power_glow(seg, 0.3)
	_claw = Node3D.new()
	_claw.name = "Claw"
	_claw.top_level = true
	add_child(_claw)
	var claw_model: Node3D = CLAW_MODEL.instantiate()
	claw_model.scale = Vector3.ONE * CLAW_SCALE
	_claw.add_child(claw_model)
	_shadows(claw_model)
	_power_glow(claw_model, 0.3)
	# The lens at the front of the wrist, where the old sensor head was.
	_lens_mat = _mat(&"lens").duplicate()
	var lens := MeshInstance3D.new()
	lens.name = "Lens"
	lens.mesh = _sphm(0.075)
	lens.material_override = _lens_mat
	lens.position = Vector3(0.0, -0.42, 0.24)
	_claw.add_child(lens)
	# Its glow, the only light that travels with it: the claw is seen coming
	# by its own red light on the stone.
	_eye_light = OmniLight3D.new()
	_eye_light.name = "EyeLight"
	_eye_light.light_color = EYE_COLOUR
	_eye_light.omni_range = 4.5
	_eye_light.omni_attenuation = 1.3
	_eye_light.light_energy = 0.0
	_eye_light.light_specular = 0.5
	_eye_light.shadow_enabled = false
	_eye_light.position = Vector3(0.0, -0.5, 0.55)
	_claw.add_child(_eye_light)
	# The power cable, wound round the wrist and up into the arm. Glows with
	# the core; reddens as it is cut.
	_belly_mat = _mat(&"belly").duplicate()
	var cable := _merge([[_torusm(0.17, 0.23), Transform3D(Basis(), Vector3(0.0, -0.2, 0.0)), &"belly"],
		[_torusm(0.17, 0.23), Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0.0, -0.34, 0.0)), &"belly"],
		[_cylm(0.045, 0.045, 0.6, 8), Transform3D(Basis(Vector3.FORWARD, 0.15), Vector3(0.16, 0.05, 0.1)), &"belly"],
		[_cylm(0.045, 0.045, 0.6, 8), Transform3D(Basis(Vector3.FORWARD, -0.15), Vector3(-0.16, 0.05, -0.1)), &"belly"]], "PowerCable")
	cable.material_override = _belly_mat
	_claw.add_child(cable)
	_cable_box = CableHitbox.new()
	_cable_box.name = "PowerCableHitbox"
	_cable_box.set("table", self)
	_cable_box.collision_layer = 0
	_cable_box.collision_mask = 0
	_cable_box.position = Vector3(0.0, -0.3, 0.0)
	_claw.add_child(_cable_box)
	var cshape := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(0.9, 0.9, 0.9)
	cshape.shape = cbox
	_cable_box.add_child(cshape)
	_claw_box = ClawHitbox.new()
	_claw_box.name = "ClawHitbox"
	_claw_box.set("table", self)
	_claw_box.collision_layer = 4
	_claw_box.collision_mask = 0
	_claw_box.position = Vector3(0.0, -1.05, 0.0)
	_claw.add_child(_claw_box)
	var kshape := CollisionShape3D.new()
	var kbox := BoxShape3D.new()
	kbox.size = Vector3(0.8, 1.0, 0.8)
	kshape.shape = kbox
	_claw_box.add_child(kshape)


static func _shadows(n: Node) -> void:
	for node in n.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## The machine's own pieces glow with their pictures only while it has power:
## [material, its full energy], dimmed to an ember with it (`_apply_pose`).
func _power_glow(piece: Node, energy: float) -> void:
	for m in glow(piece, energy):
		var known := false
		for pair in _power_mats:
			known = known or pair[0] == m
		if not known:
			_power_mats.append([m, energy])


## Lights a Higgsfield kit piece with its own albedo: the candle flames, the
## amber indicator lamps, the green bottles and the specimen fluid are the
## bright parts of the generated pictures and the iron and wood the dark ones,
## so the picture itself is the emission map -- the lamps burn, the iron stays
## dark. Materials are duplicated once per source and energy (`_glow_mats`),
## so every copy shares them.
static var _glow_mats := {}


static func glow(piece: Node, energy: float) -> Array:
	var used: Array = []
	if energy <= 0.0:
		return used
	var nodes := piece.find_children("*", "MeshInstance3D", true, false)
	if piece is MeshInstance3D:
		nodes.append(piece)
	for node in nodes:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var key := "%d_%.2f" % [src.get_instance_id(), energy]
			if not _glow_mats.has(key):
				var m := src.duplicate() as StandardMaterial3D
				m.emission_enabled = true
				m.emission = Color.WHITE
				m.emission_texture = src.albedo_texture
				m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				m.emission_energy_multiplier = energy
				_glow_mats[key] = m
			mi.set_surface_override_material(i, _glow_mats[key])
			if not used.has(_glow_mats[key]):
				used.append(_glow_mats[key])
	return used


## The dead prisoner strapped to the top: the skeleton on its back, its right
## forearm gone and a drill bit bolted to the stump -- the work left half done.
func _build_prisoner() -> void:
	_prisoner = Node3D.new()
	_prisoner.name = "Prisoner"
	_body.add_child(_prisoner)
	var model: Node3D = SKELETON.instantiate()
	model.scale = Vector3(-0.92, 0.92, -0.92)
	_prisoner.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var key := "dead_%d" % src.get_instance_id()
			if not _mats.has(key):
				var m := src.duplicate() as BaseMaterial3D
				m.emission_enabled = false
				m.albedo_color = m.albedo_color * Color(0.78, 0.74, 0.68)
				_mats[key] = m
			mi.set_surface_override_material(i, _mats[key])
	var sk: Skeleton3D = null
	var found := model.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		sk = found[0] as Skeleton3D
	if sk != null:
		var fore := sk.find_bone(&"forearm.R")
		if fore >= 0:
			sk.set_bone_pose_scale(fore, Vector3.ONE * 0.001)
			var att := BoneAttachment3D.new()
			att.bone_name = "upper_arm.R"
			sk.add_child(att)
			var bit := MeshInstance3D.new()
			bit.mesh = SkeletonSword.drill_bit_mesh()
			bit.scale = Vector3.ONE * 1.3
			bit.position = Vector3(0.0, 0.27, 0.0)
			att.add_child(bit)
			var collar := MeshInstance3D.new()
			collar.mesh = _cylm(0.045, 0.05, 0.08, 8)
			collar.material_override = _mat(&"brass")
			collar.position = Vector3(0.0, 0.25, 0.0)
			att.add_child(collar)
	# On its back along the slab, head to the head end.
	_prisoner.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, TOP + 0.08, 0.88))
	_prisoner_rest = _prisoner.transform


func _build_audio() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.2
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "Hum"
	_audio.stream = gen
	_audio.unit_size = 7.0
	_audio.max_distance = 48.0
	_audio.volume_db = -4.0
	_audio.position = Vector3(0.0, 1.0, 0.0)
	add_child(_audio)


# --- Asleep, awake, depowered -------------------------------------------------------

## As built: the claw folded up under the ring, the prisoner strapped down.
func _sleep_pose() -> void:
	state = State.DORMANT
	_dying = false
	global_position = home
	global_rotation = Vector3(0.0, home_yaw, 0.0)
	_power = 0.0
	_w = FOLD
	_want_w = FOLD
	_axis = Vector3.DOWN
	_want_axis = Vector3.DOWN
	_theta = 0.0
	_aisle = 0.0
	exposed = false
	for c in _cuffs:
		c.rotation = Vector3.ZERO
	if _prisoner != null:
		if _prisoner.get_parent() != _body:
			_prisoner.get_parent().remove_child(_prisoner)
			_body.add_child(_prisoner)
		_prisoner.transform = _prisoner_rest
	_apply_pose(0.0)


## A world reset (everyone died) with the table still running: back to sleep.
func reset_to_sleep() -> void:
	if state == State.DEAD or state == State.DYING:
		return
	level = 0
	cuts = 0
	legs_jammed = false
	_cut_once.clear()
	_arms_off_until = -INF
	_legs_off_until = -INF
	_was_arms = true
	_was_legs = true
	_strain = 0.0
	_belly_mat.emission_energy_multiplier = 0.0
	_sleep_pose()


## A save that had it depowered: the claw down where it fell (`at`, world; the
## aisle `yaw`). Saves from before the claw held the walking table's position,
## in the middle: the claw is laid out in the aisle instead.
func set_dead_now(at: Vector3, yaw: float) -> void:
	state = State.DEAD
	_dying = true
	global_position = home
	global_rotation = Vector3(0.0, home_yaw, 0.0)
	_power = 0.0
	exposed = false
	_throw_prisoner(true)
	for c in _cuffs:
		c.rotation.z = 1.9 * signf(c.position.x)
	_theta = yaw if is_finite(yaw) else 0.0
	_aisle = _theta
	var local: Vector3 = room.to_local(at) if room != null else Vector3.ZERO
	if Vector2(local.x, local.z).length() < 2.5:
		local = _dir(_theta) * 4.2
	_w = Vector3(local.x, CLAW_LEN * 0.55, local.z)
	_axis = (_dir(_theta) + Vector3.DOWN * 0.6).normalized()
	_want_w = _w
	_want_axis = _axis
	_apply_pose(0.0)


## Where its claw lies, for the save (world), and the aisle it is in.
func rest_point() -> Vector3:
	return room.to_global(_w) if room != null else global_position


func rest_yaw() -> float:
	return _theta


func is_depowered() -> bool:
	return state == State.DEAD or state == State.DYING


func arms_on() -> bool:
	return _now() >= _arms_off_until and not is_depowered()


func legs_on() -> bool:
	return not legs_jammed and _now() >= _legs_off_until and not is_depowered()


## A lever: `system` off for a while. Cutting the core while both the arms and
## the hoist are off shuts it down for good.
func cut(system: StringName) -> void:
	if is_depowered():
		return
	if state == State.DORMANT:
		_wake()
	var now := _now()
	var span: float = CUT_TIME[level]
	if not _cut_once.has(system):
		_cut_once[system] = true
		_anger()
	match system:
		&"arms":
			_arms_off_until = now + span
			if state == State.GRAB or state == State.SWEEP:
				_enter(State.HUNT)
		&"legs":
			_legs_off_until = now + span
			if state == State.REAR:
				_enter(State.HUNT)
		&"core":
			if not arms_on() and not legs_on():
				_shutdown(&"relay")
				return
			if state != State.CLAMPED:
				_enter(State.STALL)
	_update_systems()


## The hoist's flywheel jammed while it was cut: it never comes back.
func jam_legs() -> void:
	if is_depowered():
		return
	legs_jammed = true
	_anger()
	_update_systems()


func _anger() -> void:
	level = mini(level + 1, LEVEL_MAX)


func _update_systems() -> void:
	var a := arms_on()
	var l := legs_on()
	if a != _was_arms:
		_was_arms = a
		system_changed.emit(&"arms", a)
	if l != _was_legs:
		_was_legs = l
		system_changed.emit(&"legs", l)


func _wake() -> void:
	if state != State.DORMANT:
		return
	_enter(State.WAKING)
	woke.emit()


func _shutdown(cause: StringName) -> void:
	if is_depowered():
		return
	if state == State.CLAMPED and room != null and room.has_method("clamp_release"):
		room.call("clamp_release", false)
	_enter(State.DYING)
	_dying = true
	exposed = false
	print("[surgery] the table is depowered (%s)" % cause)
	depowered.emit(cause)


func _enter(s: State) -> void:
	state = s
	_t = 0.0
	_hit_done = false
	_aim_locked = false
	_blocked = false


# --- Each tick ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if room == null:
		return
	_update_systems()
	var now := _now()
	_t += delta
	var sagging := _sagging()
	match state:
		State.DORMANT:
			if _intruder() != null:
				_wake()
			_want_w = FOLD
			_want_axis = Vector3.DOWN
			_w_speed = 2.0
		State.WAKING:
			# Unfolding out of the ring, the claw flexing.
			_want_w = FOLD + Vector3(0.0, -0.35 * clampf((_t - 1.4) / 0.8, 0.0, 1.0), 0.0)
			_want_axis = (Vector3.DOWN + Vector3(sin(_t * 3.0), 0.0, cos(_t * 2.3)) * 0.25).normalized()
			_w_speed = 2.0
			if _t >= 3.0:
				_enter(State.HUNT)
				_next_grab = now + 1.5
				_next_rear = now + 4.0
		State.HUNT:
			_hunt(now, sagging)
		State.GRAB:
			_grab(now, delta)
		State.SWEEP:
			_sweep(now)
		State.REAR:
			_slam(now)
		State.CLAMPED:
			_clamped(now, delta)
		State.STALL:
			# The hoist slack for a moment: the claw sinks.
			_want_w = Vector3(_w.x, lerpf(_w.y, 2.2, 0.5), _w.z)
			_want_axis = Vector3.DOWN
			_w_speed = 2.5
			if _t >= STALL_TIME:
				_enter(State.HUNT)
		State.DYING:
			# Swinging, then crashing down to the floor.
			var drop := clampf((_t - 1.0) / 0.35, 0.0, 1.0)
			var flat := Vector3(_w.x, 0.0, _w.z)
			if flat.length() < 2.5:
				flat = _dir(_theta) * 3.5
			_want_w = Vector3(flat.x, lerpf(_w.y, CLAW_LEN * 0.55, drop), flat.z)
			_want_axis = (_dir(_theta) * drop + Vector3.DOWN * (1.0 - 0.4 * drop)).normalized()
			_w_speed = 1.5 + 9.0 * drop
			if drop >= 1.0 and not _hit_done:
				_hit_done = true
				for p in Coop.all():
					var n := p as Node3D
					if n != null and n.get("_shake") != null and n.global_position.distance_to(room.to_global(_w)) < 16.0:
						n.set("_shake", maxf(float(n.get("_shake")), 0.6))
				_sparks(room.to_global(_w + _axis * CLAW_LEN), Color(1.0, 0.75, 0.45), 40)
			if _t >= 3.2:
				_die_done()
		State.DEAD:
			pass
	_move_claw(delta)


## The hoist dead: the claw on the floor, dragged.
func _sagging() -> bool:
	return not legs_on() and state not in [State.DORMANT, State.WAKING, State.DYING, State.DEAD, State.CLAMPED]


## The wrist toward `_want_w`, no faster than `_w_speed`, turning the arm into
## the aisle it needs on the way -- in to the bay first if it is out in another.
func _move_claw(delta: float) -> void:
	if state == State.DEAD:
		return
	var want := _want_w
	var flat := Vector2(want.x, want.z)
	# The aisle is chosen from the target (`_hunt`), never from where the claw
	# is told to wait: that is projected onto the aisle, and choosing from it
	# had the arm stop half turned, picking a new aisle every frame.
	if flat.length() > 1.2 and state in [State.HUNT, State.STALL, State.WAKING]:
		var d := wrapf(_aisle - _theta, -PI, PI)
		if absf(d) > 0.02:
			var here := Vector2(_w.x, _w.z)
			if here.length() > BAY_SAFE + 0.2:
				# Back into the bay before turning.
				var in_ := here.normalized() * BAY_SAFE if here.length() > 0.01 else Vector2.ZERO
				want = Vector3(in_.x, maxf(want.y, GAP_NEAR_Y - 0.4), in_.y)
			else:
				var step := TURN[level] * delta
				_theta = wrapf(_theta + clampf(d, -step, step), -PI, PI)
				var lim := Vector2(want.x, want.z).limit_length(BAY_SAFE)
				want = Vector3(lim.x, want.y, lim.y)
	var before := _w
	_w = _w.move_toward(want, _w_speed * delta)
	_w_vel = (_w - before).length() / maxf(delta, 0.0001)
	# Lerped, not slerped: slerp between two nearly equal directions takes the
	# axis of their tiny cross product and Godot rejects it as not normalised.
	var turned := _axis.lerp(_want_axis.normalized(), clampf(delta * (14.0 if state in [State.GRAB, State.REAR] else 5.0), 0.0, 1.0))
	if turned.length_squared() > 0.0001:
		_axis = turned.normalized()


## The aisle for a point (room frame): the one the arm is in unless the point
## is well round toward another -- a player on a diagonal does not make it
## swing back and forth.
func _aisle_for(p: Vector3) -> float:
	var a := atan2(p.z, p.x)
	if absf(wrapf(a - _aisle, -PI, PI)) < PI * 0.25 + 0.15:
		return _aisle
	return snappedf(a, PI * 0.5)


## The nearest standing player inside the hall, or null.
func _intruder() -> Node3D:
	if Sandbox.enemies_passive:
		return null
	var best: Node3D = null
	var best_d := INF
	for p in Coop.all():
		var n := p as Node3D
		if n == null or n.get("_dead") == true or (n.has_method("is_hidden") and n.is_hidden()):
			continue
		var local: Vector3 = room.to_local(n.global_position)
		if absf(local.x) > bound + 1.2 or absf(local.z) > bound + 1.2 or absf(local.y) > 3.0:
			continue
		var d := n.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _hunt(now: float, sagging: bool) -> void:
	_target = _intruder()
	exposed = sagging
	if _target == null or now < _stun_until:
		if _target == null:
			# Nobody in the hall: back up over the table, to wait.
			_want_w = Vector3(0.0, HOVER_Y + 0.3, 0.0) if not sagging else Vector3(_w.x, CLAW_LEN * 0.6, _w.z)
			_want_axis = Vector3.DOWN
			_w_speed = 2.0
		return
	var p: Vector3 = room.to_local(_target.global_position)
	var flat := Vector2(p.x, p.z)
	var dist := flat.length()
	# Hover: short of them, toward them along a line the stone allows.
	var want := Vector3.ZERO
	var r := clampf(dist - HOVER_SHORT, 0.0, HOVER_REACH)
	var toward := flat.normalized() if dist > 0.01 else Vector2.RIGHT
	want = Vector3(toward.x * r, HOVER_Y, toward.y * r)
	_aisle = _aisle_for(Vector3(p.x, 0.0, p.z))
	if r > BAY_SAFE and not _reachable(want):
		# Blocked by a pier: up the aisle as far as they are along it.
		var along := _dir(_aisle)
		var a := clampf(Vector3(p.x, 0.0, p.z).dot(along) - HOVER_SHORT * 0.5, 0.0, HOVER_REACH)
		want = along * a + Vector3(0.0, HOVER_Y, 0.0)
	var sway := Vector3(sin(now * 1.3), sin(now * 0.9) * 0.4, cos(now * 1.1)) * 0.25
	if sagging:
		# Dragged along the floor, slowly, toward them.
		want = Vector3(want.x, CLAW_LEN * 0.6, want.z)
		_want_axis = (Vector3(toward.x, 0.0, toward.y) * 0.8 + Vector3.DOWN).normalized()
		_w_speed = DRAG_SPEED
	else:
		want += sway
		var look := (Vector3(p.x, 1.0, p.z) - _w)
		_want_axis = (Vector3.DOWN * 1.6 + look.normalized()).normalized()
		_w_speed = SPEED[level]
	_want_w = want
	# Attacks, only with the arm settled in its aisle.
	var settled := Vector2(_w.x, _w.z).length() < BAY_SAFE \
		or (absf(wrapf(_aisle - _theta, -PI, PI)) < 0.05 and absf(wrapf(atan2(_w.z, _w.x) - _theta, -PI, PI)) < PI * 0.25 + 0.2)
	if not settled:
		return
	var chest := p + Vector3(0.0, 1.05, 0.0)
	var claw_flat := Vector2(_w.x - p.x, _w.z - p.z).length()
	if not sagging and arms_on() and claw_flat < SWEEP_RANGE and now >= _next_sweep:
		_side = Vector3(-toward.y, 0.0, toward.x) * (1.0 if randf() < 0.5 else -1.0)
		_enter(State.SWEEP)
		_next_sweep = now + SWEEP_COOLDOWN[level]
		return
	if not sagging and legs_on() and dist < REAR_RANGE and now >= _next_rear \
			and _reachable(Vector3(p.x, REAR_HIGH, p.z)):
		_to = Vector3(p.x, CLAW_LEN * 0.95, p.z)
		_enter(State.REAR)
		_next_rear = now + REAR_COOLDOWN[level]
		return
	if arms_on() and dist > GRAB_MIN and dist < GRAB_RANGE and now >= _next_grab and _reachable(chest):
		_enter(State.GRAB)
		# Down to their height first: the thrust runs level along the aisle --
		# on past them into the clamp, if that is where they stood.
		_from = Vector3(_w.x, chest.y + 0.7, _w.z)
		_aim = (chest - _from).normalized()
		return


## Whether the arm can run from the aisle's end point to `local` (room frame)
## without meeting stone (sight's layer: walls, piers, props).
func _reachable(local: Vector3) -> bool:
	var a := _gap_far(local)
	var q := PhysicsRayQueryParameters3D.create(room.to_global(a), room.to_global(local), 2)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The arm's point past the piers' line in its aisle -- drawn in when the wrist
## is nearer than that. In the aisle it is turning to (the same one once it
## has).
func _gap_far(wrist: Vector3) -> Vector3:
	var along := _dir(_aisle)
	var a := clampf(Vector3(wrist.x, 0.0, wrist.z).dot(along), 0.0, GAP_FAR)
	return along * a + Vector3(0.0, GAP_FAR_Y, 0.0)


static func _dir(theta: float) -> Vector3:
	return Vector3(cos(theta), 0.0, sin(theta))


func _chest(p: Node3D) -> Vector3:
	return p.global_position + Vector3(0.0, 1.05, 0.0)


# --- The grab --------------------------------------------------------------------

func _grab(now: float, _delta: float) -> void:
	var windup: float = GRAB_WINDUP[level]
	if not arms_on():
		_enter(State.HUNT)
		return
	var tip := room.to_global(_w + _axis * CLAW_LEN)
	if _t < windup - GRAB_LOCK:
		# Tracking: drawn back toward the aisle and trembling, its cable twitching.
		if _target != null and is_instance_valid(_target):
			_aim = (room.to_local(_chest(_target)) - _from).normalized()
		_want_w = _from - _aim * 0.9
		_want_axis = _aim
		_w_speed = 2.5
		return
	if not _aim_locked:
		_aim_locked = true
		# Where it will go: along the aim until something stony stops it (sight's
		# layer: the walls, piers, props -- not the players, it goes through
		# where they stood).
		var start := _from - _aim * 0.9
		var from := room.to_global(start)
		var q := PhysicsRayQueryParameters3D.create(from, from + room.global_basis * _aim * (GRAB_REACH + CLAW_LEN), 2)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		_reach = GRAB_REACH
		if not hit.is_empty():
			_reach = maxf(from.distance_to(hit["position"]) - CLAW_LEN - 0.15, 0.5)
		# Never past the walls' reach from the middle.
		var end := start + _aim * _reach
		var flat := Vector2(end.x, end.z)
		if flat.length() > LUNGE_REACH:
			_reach = maxf(_reach - (flat.length() - LUNGE_REACH), 0.5)
		_to = start + _aim * _reach
		for p in Coop.all():
			if p.has_method("parry_cue"):
				p.call("parry_cue", self, GRAB_LOCK + GRAB_LUNGE + 0.25)
		return
	if _t < windup:
		return
	if _t < windup + GRAB_LUNGE + GRAB_HOLD:
		_want_w = _to
		_want_axis = _aim
		_w_speed = (_reach + 1.0) / GRAB_LUNGE
		var shoulder := room.to_global(_gap_far(_w))
		# The clamp: the claw driven on into its open jaws is caught there.
		if room.has_method("clamp_try_catch") and room.call("clamp_try_catch", shoulder, tip):
			_clamp_point = room.to_local(room.call("clamp_hold_point"))
			_enter(State.CLAMPED)
			_strain = 0.0
			_anger()
			return
		if not _hit_done:
			var wrist := room.to_global(_w)
			for p in Coop.all():
				var n := p as Node3D
				if n == null or n.get("_dead") == true:
					continue
				if _segment_distance(_chest(n), wrist, tip) <= GRAB_HIT:
					_hit_done = true
					var parried := _strike(n, GRAB_DAMAGE)
					if parried:
						# Turned aside: the claw snaps back and the machine reels.
						_stun_until = now + 0.9
						_enter(State.HUNT)
						_next_grab = now + GRAB_COOLDOWN[level] + 0.8
						return
					# Hauled in toward the table.
					var pull := global_position - n.global_position
					pull.y = 0.0
					if n.has_method("apply_knockback") and pull.length_squared() > 0.01:
						n.call("apply_knockback", pull.normalized() * GRAB_YANK)
					break
		return
	# Back up the aisle.
	_want_w = _from
	_want_axis = Vector3.DOWN
	_w_speed = (_reach + 1.0) / GRAB_RETRACT
	if _t >= windup + GRAB_LUNGE + GRAB_HOLD + GRAB_RETRACT:
		_next_grab = now + GRAB_COOLDOWN[level]
		_enter(State.HUNT)


## A blow on player `p`; true if they parried it.
func _strike(p: Node3D, amount: float) -> bool:
	var dir := p.global_position - room.to_global(_w)
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else -global_basis.z
	var parried := [false]
	var watch := func(parry: bool, attacker: Node3D) -> void:
		if attacker == self and parry:
			parried[0] = true
	if p.has_signal("guarded"):
		p.connect("guarded", watch)
	if p.has_method("take_damage"):
		p.call("take_damage", amount, dir, self)
	if p.has_signal("guarded") and p.is_connected("guarded", watch):
		p.disconnect("guarded", watch)
	return parried[0]


static func _segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- The sweep ----------------------------------------------------------------------

## Down beside the player, then a rake sideways through where they stand. Stone
## in the way stops it dead.
func _sweep(now: float) -> void:
	var windup: float = SWEEP_WINDUP[level]
	if not arms_on():
		_enter(State.HUNT)
		return
	if _t < windup:
		if _target != null and is_instance_valid(_target):
			var p: Vector3 = room.to_local(_target.global_position)
			_from = Vector3(p.x, 1.85, p.z) + _side * SWEEP_SPAN
			_to = Vector3(p.x, 1.85, p.z) - _side * SWEEP_SPAN
		_want_w = _from
		_want_axis = (Vector3.DOWN + _side * 0.5).normalized()
		_w_speed = 9.0
		if not _aim_locked and _t >= windup - 0.25:
			_aim_locked = true
			for p in Coop.all():
				if p.has_method("parry_cue"):
					p.call("parry_cue", self, 0.5)
		return
	if not _blocked and _t < windup + SWEEP_SWING:
		_want_w = _to
		_want_axis = (Vector3.DOWN - _side * 0.7).normalized()
		_w_speed = SWEEP_SPAN * 2.0 / SWEEP_SWING
		# Stone across the rake stops it, sparking.
		var tip := room.to_global(_w + _axis * CLAW_LEN)
		var ahead := room.to_global(_w + _axis * CLAW_LEN - _side * 0.6)
		var q := PhysicsRayQueryParameters3D.create(tip, ahead, 2)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			_blocked = true
			_want_w = _w
			_sparks(hit["position"], Color(1.0, 0.8, 0.5), 18)
	if not _hit_done and _t >= windup + SWEEP_SWING * 0.3:
		var wrist := room.to_global(_w)
		var tip := room.to_global(_w + _axis * CLAW_LEN)
		for p in Coop.all():
			var n := p as Node3D
			if n == null or n.get("_dead") == true:
				continue
			if _segment_distance(_chest(n) - Vector3(0.0, 0.3, 0.0), wrist, tip) > SWEEP_HIT:
				continue
			_hit_done = true
			if _strike(n, SWEEP_DAMAGE):
				_stun_until = now + 0.7
			elif n.has_method("apply_knockback"):
				n.call("apply_knockback", room.global_basis * (-_side) * 5.0)
	if _t >= windup + SWEEP_SWING + SWEEP_RECOVER:
		_enter(State.HUNT)


# --- The slam -------------------------------------------------------------------------

func _slam(now: float) -> void:
	var stuck_at := REAR_RISE + REAR_HOLD + REAR_SLAM
	exposed = _t >= stuck_at and _t < stuck_at + REAR_STUCK
	if not legs_on():
		exposed = false
		_enter(State.HUNT)
		return
	if _t < REAR_RISE + REAR_HOLD:
		# Up over them, following, the claw spread and trembling.
		if _target != null and is_instance_valid(_target) and _t < REAR_RISE + REAR_HOLD * 0.5:
			var p: Vector3 = room.to_local(_target.global_position)
			_to = Vector3(p.x, CLAW_LEN * 0.95, p.z)
		_want_w = Vector3(_to.x, REAR_HIGH, _to.z)
		_want_axis = Vector3.DOWN
		_w_speed = SPEED[level] * 1.6
		if not _aim_locked and _t >= REAR_RISE:
			_aim_locked = true
			for p in Coop.all():
				if p.has_method("parry_cue"):
					p.call("parry_cue", self, REAR_HOLD + REAR_SLAM)
		return
	if _t < stuck_at:
		_want_w = _to
		_want_axis = Vector3.DOWN
		_w_speed = (REAR_HIGH - _to.y) / REAR_SLAM + 2.0
		return
	if not _hit_done:
		_hit_done = true
		var at := room.to_global(Vector3(_to.x, 0.0, _to.z))
		for p in Coop.all():
			var n := p as Node3D
			if n == null or n.get("_dead") == true:
				continue
			var d := Vector2(n.global_position.x - at.x, n.global_position.z - at.z).length()
			if n.get("_shake") != null and d < 9.0:
				n.set("_shake", maxf(float(n.get("_shake")), 0.45 * (1.0 - d / 9.0)))
			if d > REAR_RADIUS:
				continue
			var guarded: bool = n.has_method("is_blocking") and n.call("is_blocking")
			_strike(n, REAR_DAMAGE)
			if not guarded and n.has_method("knock_down"):
				n.call("knock_down", n.global_position - at, 6.5)
		_sparks(at + Vector3(0.0, 0.1, 0.0), Color(1.0, 0.7, 0.4), 30)
	if _t < stuck_at + REAR_STUCK:
		# Stuck in the floor, wrenching at it.
		var wr := 0.04 * sin(_t * 31.0)
		_want_w = _to + Vector3(wr, 0.0, -wr)
		_want_axis = Vector3.DOWN
		_w_speed = 4.0
		return
	if not _blocked:
		# Torn free.
		_blocked = true
		_sparks(room.to_global(Vector3(_to.x, 0.05, _to.z)), Color(1.0, 0.75, 0.45), 16)
	_want_w = Vector3(_to.x, HOVER_Y, _to.z)
	_w_speed = 5.0
	if _t >= stuck_at + REAR_STUCK + REAR_SETTLE:
		_enter(State.HUNT)


# --- Held by the clamp -------------------------------------------------------------

func _clamped(now: float, delta: float) -> void:
	exposed = true
	# The claw held in the jaws, the wrist before them.
	var aim := (_clamp_point - _gap_far(_clamp_point)).normalized()
	var shake := Vector3(sin(now * 37.0), sin(now * 29.0), cos(now * 33.0)) * 0.04 * (1.0 if legs_on() else 0.3)
	_want_w = _clamp_point - aim * (CLAW_LEN * 0.6) + shake
	_want_axis = aim
	_w_speed = 12.0
	# The hoist pulls it free in time; with it cut it cannot pull at all.
	if legs_on():
		_strain += delta
	if _strain >= CLAMP_HOLD[level]:
		exposed = false
		if room.has_method("clamp_release"):
			room.call("clamp_release", true)
		_stun_until = now + 0.6
		_next_grab = now + GRAB_COOLDOWN[level] + 1.5
		_anger()
		_enter(State.HUNT)


## How far it has pulled against the clamp, 0..1 (surgery.gd shakes the clamp).
func strain() -> float:
	return clampf(_strain / float(CLAMP_HOLD[level]), 0.0, 1.0) if state == State.CLAMPED else 0.0


# --- Being hit ----------------------------------------------------------------------

## A blow on the table itself: iron rings, sparks fly. Nothing is hurt.
func take_damage(_amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
	if state == State.DEAD:
		return
	var at := global_position + Vector3(0.0, TOP + 0.1, 0.0) - from_direction * 0.9
	_ring_off(at, from_direction)


## A blow on the table or the claw's fingers.
func _ring_off(at: Vector3, _dir_: Vector3) -> void:
	if state == State.DEAD:
		return
	_sparks(at, Color(1.0, 0.85, 0.55), 10)
	if state == State.DORMANT:
		_wake()


## Too heavy to shove.
func apply_knockback(_impulse: Vector3, _stun_time := 0.0) -> void:
	pass


## A cut in the power cable. Only reachable while `exposed` (the hitbox is off
## otherwise).
func _cable_hit(_dir: Vector3) -> void:
	if not exposed or is_depowered():
		return
	var now := _now()
	if now - _last_cable_hit < 0.15:
		return
	_last_cable_hit = now
	cuts += 1
	_sparks(_cable_box.global_position, Color(0.7, 0.95, 1.0), 40)
	_power = minf(_power, 0.6)
	if cuts >= CABLE_CUTS:
		_shutdown(&"cable")
		return
	# It feels that: a lurch, and it comes for them harder.
	_stun_until = now + 0.35


func _sparks(at: Vector3, colour: Color, amount: int) -> void:
	if not Graphics.effects or not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.55
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = colour
	quad.material = m
	p.mesh = quad
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _die_done() -> void:
	_enter(State.DEAD)
	_dying = true
	# What it held: the core's crystals and the coins prised from the dead it
	# worked on, out of a cracked porthole.
	var at := _body.global_transform * (CORE_AT + Vector3(0.5, 0.0, 0.0))
	ITEM_DROP.spawn(get_parent(), at, &"gold_crystal", 2)
	ITEM_DROP.spawn(get_parent(), at + Vector3(0.0, 0.1, 0.0), &"coins", 40)


# --- The pose -------------------------------------------------------------------------

func _process(delta: float) -> void:
	_apply_pose(delta)
	_feed_audio()


func _apply_pose(delta: float) -> void:
	var k := clampf(delta * 6.0, 0.0, 1.0) if delta > 0.0 else 1.0
	var fast := clampf(delta * 14.0, 0.0, 1.0) if delta > 0.0 else 1.0
	var now := _now()
	var power := 1.0
	var roll := 0.0
	var arms_live := arms_on()
	var legs_live := legs_on()
	match state:
		State.DORMANT:
			power = 0.0
		State.WAKING:
			power = clampf(_t / 1.2, 0.0, 1.0) * (0.6 + 0.4 * absf(sin(_t * 23.0))) if _t < 1.2 else 1.0
			# The restraints snap open one after another, and the body is thrown.
			for i in _cuffs.size():
				var open_at := 1.0 + float(i) * 0.12
				if _t >= open_at:
					var side := signf(_cuffs[i].position.x)
					var o := clampf((_t - open_at) / 0.09, 0.0, 1.0)
					_cuffs[i].rotation.z = side * (2.05 - 0.15 * sin(o * PI)) * o
			roll = 0.012 * sin(_t * 40.0) if _t < 1.6 else 0.0
			if _t >= 1.25 and _prisoner.get_parent() == _body:
				_throw_prisoner(false)
		State.STALL:
			power = 0.06 if _t < FEED_AT else clampf((_t - FEED_AT) / 0.5, 0.0, 1.0) * (1.0 + 0.6 * sin(_t * 40.0))
		State.DYING:
			power = clampf(1.0 - _t / 2.6, 0.0, 1.0) * (0.5 + 0.5 * absf(sin(_t * 31.0)))
			roll = 0.01 * sin(_t * 21.0) * clampf(1.0 - _t / 2.0, 0.0, 1.0)
		State.DEAD:
			power = 0.0
	if state == State.REAR and _hit_done and exposed:
		roll = 0.006 * sin(now * 37.0)
	if now < _stun_until:
		roll += 0.006 * sin(now * 40.0)
	if state in [State.DORMANT, State.STALL, State.DYING, State.DEAD]:
		exposed = exposed and state == State.STALL and _sagging()
	_roll = lerpf(_roll, roll, k) if delta > 0.0 else roll
	_power = lerpf(_power, power, fast) if delta > 0.0 else power
	_body.transform = Transform3D(Basis(Vector3.FORWARD, _roll), Vector3.ZERO)

	# The power cable's hitbox only while it can be reached.
	_cable_box.collision_layer = 4 if exposed and not is_depowered() else 0

	# The core and its glow: a heartbeat, quicker as it angers.
	var beat := 0.75 + 0.25 * pow(absf(sin(now * (2.6 + 0.5 * float(level)))), 6.0)
	core_glow = _power * beat
	_core_mat.emission_energy_multiplier = 0.4 + 5.0 * core_glow
	_core_light.light_energy = 1.6 * core_glow
	_core_light.visible = core_glow > 0.02
	var wound := float(cuts) / float(CABLE_CUTS)
	_belly_mat.emission = CORE_COLOUR.lerp(Color(1.0, 0.3, 0.1), wound)
	_belly_mat.emission_energy_multiplier = (0.04 + 1.6 * wound) * core_glow + (1.2 if exposed else 0.0) * core_glow
	_lens_mat.emission_energy_multiplier = 0.0 if _power < 0.05 else (2.5 + 3.0 * float(level) / LEVEL_MAX) * _power
	_eye_light.light_energy = (1.4 + 0.4 * float(level) / LEVEL_MAX) * _power
	_eye_light.visible = _power > 0.03
	for pair in _power_mats:
		(pair[0] as StandardMaterial3D).emission_energy_multiplier = float(pair[1]) * (0.3 + 0.7 * _power)
	# The feed-back flare along the cables while the core stalls.
	var feed := 0.0
	if state == State.STALL and _t >= FEED_AT:
		feed = clampf(1.0 - (_t - FEED_AT) / 0.9, 0.0, 1.0)
	feed_arms = lerpf(feed_arms, feed if arms_live else 0.0, fast)
	feed_legs = lerpf(feed_legs, feed if legs_live else 0.0, fast)

	_pose_arm(delta)

	# What the cables show.
	var arms_moving := 0.0
	if arms_live and _power > 0.3:
		arms_moving = 0.2
		if state in [State.GRAB, State.SWEEP, State.CLAMPED] or _sagging():
			arms_moving = 1.0
	arm_motion = lerpf(arm_motion, arms_moving, fast)
	leg_motion = lerpf(leg_motion, clampf(_w_vel / 4.0, 0.0, 1.0) if legs_live and _power > 0.3 else 0.0, fast)


## The ring, the arm's segments and the claw, from the wrist and the aisle.
func _pose_arm(delta: float) -> void:
	if room == null:
		return
	var rt := room.global_transform
	# The ring turns with the arm.
	_ring.global_transform = rt * Transform3D(Basis(Vector3.UP, -_theta).scaled(Vector3.ONE * RING_SCALE), Vector3(0.0, RING_TOP, 0.0))
	# The claw: its -Y along the axis, turning slowly at the wrist (fast while
	# it strikes).
	if delta > 0.0 and _power > 0.05:
		_spin += delta * (0.4 + (3.0 if state in [State.GRAB, State.SWEEP] else 0.0)) * _power
	var y := -_axis.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var claw_basis := Basis(x, y, z) * Basis(Vector3.UP, _spin)
	_claw.global_transform = rt * Transform3D(claw_basis, _w)
	# The arm: from the hub, over the edge of the bay, out along the aisle past
	# the piers, and down into the wrist along the claw's line.
	var along := _dir(_theta)
	var reach := Vector3(_w.x, 0.0, _w.z).dot(along)
	var far := clampf(reach - 0.6, 0.0, GAP_FAR)
	var near := minf(GAP_NEAR, far * 0.5)
	var pts: Array[Vector3] = [ROOT + Vector3(0.0, 0.4, 0.0), ROOT]
	# Each further point only if it brings the arm nearer the wrist: folded up,
	# or hovering close in, the bends would double back on themselves.
	for c: Vector3 in [along * near + Vector3(0.0, lerpf(ROOT.y - 0.3, GAP_NEAR_Y, clampf(near / GAP_NEAR, 0.0, 1.0)), 0.0),
			along * far + Vector3(0.0, GAP_FAR_Y, 0.0), _w - _axis * 0.9]:
		if c.distance_to(_w) < pts[pts.size() - 1].distance_to(_w) - 0.3:
			pts.append(c)
	pts.append(_w)
	var line := _spline(pts, 6)
	var lengths: Array[float] = [0.0]
	for i in range(1, line.size()):
		lengths.append(lengths[i - 1] + line[i].distance_to(line[i - 1]))
	var total: float = lengths[lengths.size() - 1]
	var n := clampi(ceili(total / SEG_LEN), 2, SEG_MAX)
	var prev := _at_length(line, lengths, 0.0)
	for i in SEG_MAX:
		var seg := _segs[i]
		if i >= n:
			seg.visible = false
			continue
		seg.visible = true
		var next := _at_length(line, lengths, total * float(i + 1) / float(n))
		var d := next - prev
		var len_ := d.length()
		if len_ < 0.001:
			seg.visible = false
			prev = next
			continue
		var sy := d / len_
		var sref := Vector3.UP if absf(sy.y) < 0.95 else Vector3.RIGHT
		var sx := sref.cross(sy).normalized()
		var sz := sx.cross(sy).normalized()
		# The model is 1 m along Y: stretched to the span, a little over so the
		# joint collars overlap.
		seg.global_transform = rt * Transform3D(Basis(sx * SEG_THICK, sy * (len_ * 1.06), sz * SEG_THICK), (prev + next) * 0.5)
		prev = next


## A Catmull-Rom curve through `pts`, `per` points a span.
static func _spline(pts: Array[Vector3], per: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var m := pts.size()
	for i in m - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, m - 1)]
		for s in per:
			var t := float(s) / float(per)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[m - 1])
	return out


static func _at_length(line: PackedVector3Array, lengths: Array[float], d: float) -> Vector3:
	for i in range(1, line.size()):
		if lengths[i] >= d:
			var span := maxf(lengths[i] - lengths[i - 1], 0.00001)
			return line[i - 1].lerp(line[i], clampf((d - lengths[i - 1]) / span, 0.0, 1.0))
	return line[line.size() - 1]


## The prisoner thrown off the side as the restraints open (`instant` for a
## save that already had it on the floor).
func _throw_prisoner(instant: bool) -> void:
	if _prisoner == null or _prisoner.get_parent() != _body:
		return
	var holder := get_parent()
	var from := _prisoner.global_transform
	_body.remove_child(_prisoner)
	holder.add_child(_prisoner)
	_prisoner.global_transform = from
	var side := global_basis.x * (1.0 if randf() < 0.5 else -1.0)
	var land := global_position + side * 1.9 + Vector3(0.0, 0.08, 0.0)
	var flat := Basis(Vector3.UP, randf_range(-PI, PI)) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.FORWARD, randf_range(-0.3, 0.3))
	if instant:
		_prisoner.global_transform = Transform3D(flat, land)
		return
	var tw := _prisoner.create_tween().set_parallel(true)
	tw.tween_property(_prisoner, "global_position", land, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_prisoner, "global_basis", flat, 0.5)


## Plug `i` (0 arms, 1 legs, 2 core) in world space: where its cable leaves the
## table.
func plug_point(i: int) -> Vector3:
	return _body.global_transform * (PLUGS[i] as Vector3 + Vector3(0.0, 0.0, 0.08))


# --- The hum ----------------------------------------------------------------------------

## A low electric hum while it has power, whining up as the claw moves -- the
## only machine sound in the dungeon, so that when it dies the silence is felt.
func _feed_audio() -> void:
	var near := Coop.nearest_distance(global_position) if Coop.count() > 0 else INF
	var on := _power > 0.02 and near < _audio.max_distance + 4.0
	if not on:
		if _audio.playing:
			_audio.stop()
			_playback = null
		return
	if not _audio.playing:
		_audio.play()
		_playback = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var rate := 22050.0
	var hum := 46.0 * (0.55 + 0.45 * _power)
	var whine := 180.0 + 260.0 * maxf(arm_motion, leg_motion)
	var amp := 0.22 * _power
	var w_amp := 0.05 * _power * maxf(arm_motion, leg_motion)
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		_phase.x = fmod(_phase.x + hum / rate, 1.0)
		_phase.y = fmod(_phase.y + whine / rate, 1.0)
		_phase.z = fmod(_phase.z + hum * 2.02 / rate, 1.0)
		var v := sin(_phase.x * TAU) * amp + sin(_phase.z * TAU) * amp * 0.45 \
			+ (fmod(_phase.y, 1.0) * 2.0 - 1.0) * w_amp
		buf[i] = Vector2(v, v)
	_playback.push_buffer(buf)


# --- Meshes ---------------------------------------------------------------------------

## One MeshInstance3D from many primitives: [mesh, transform, material key],
## merged into one surface per material.
static func _merge(parts: Array, name_: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = _merge_mesh(parts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


static func _merge_mesh(parts: Array) -> ArrayMesh:
	var by_mat := {}
	for part in parts:
		var key: StringName = part[2]
		if not by_mat.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			by_mat[key] = st
		(by_mat[key] as SurfaceTool).append_from(part[0] as Mesh, 0, part[1] as Transform3D)
	var am := ArrayMesh.new()
	for key in by_mat:
		var st: SurfaceTool = by_mat[key]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, _mat(key))
	return am


static func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cylm(top: float, bottom: float, height: float, segments := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func _sphm(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 5
	return s


static func _torusm(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 6
	return t


## A frame at `a` whose +Y points at `b`.
static func _segment(a: Vector3, b: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), a)


## A frame along a -> b for a primitive whose length runs along Y.
static func _along(a: Vector3, b: Vector3) -> Transform3D:
	var seg := _segment(a, b)
	seg.origin = (a + b) * 0.5
	return seg


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"steel":
			# Surgical steel gone dull: the plain stone's normal map, faint, for
			# scratches and grime.
			m.albedo_color = Color(0.36, 0.37, 0.38)
			m.metallic = 0.7
			m.roughness = 0.42
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.normal_scale = 0.35
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.5, 1.5, 1.5)
		&"rust":
			m.albedo_color = Color(0.2, 0.12, 0.08)
			m.metallic = 0.35
			m.roughness = 0.82
			m.normal_enabled = true
			m.normal_texture = load("res://textures/stone_plain_normal.png")
			m.normal_scale = 0.8
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(2.0, 2.0, 2.0)
		&"dark":
			m.albedo_color = Color(0.06, 0.06, 0.065)
			m.metallic = 0.5
			m.roughness = 0.6
		&"brass":
			m.albedo_color = Color(0.42, 0.3, 0.13)
			m.metallic = 0.65
			m.roughness = 0.45
		&"leather":
			m.albedo_color = Color(0.16, 0.09, 0.05)
			m.roughness = 0.88
		&"core":
			m.albedo_color = Color(0.1, 0.16, 0.18)
			m.emission_enabled = true
			m.emission = CORE_COLOUR
			m.emission_energy_multiplier = 0.0
			m.roughness = 0.2
		&"belly":
			m.albedo_color = Color(0.05, 0.05, 0.055)
			m.roughness = 0.7
			m.emission_enabled = true
			m.emission = CORE_COLOUR
			m.emission_energy_multiplier = 0.0
		&"lens":
			m.albedo_color = Color(0.08, 0.02, 0.01)
			m.emission_enabled = true
			m.emission = EYE_COLOUR
			m.emission_energy_multiplier = 0.0
			m.roughness = 0.1
		&"amber":
			m.albedo_color = Color(0.3, 0.16, 0.04)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.55, 0.15)
			m.emission_energy_multiplier = 2.2
			m.roughness = 0.3
		_:
			m.albedo_color = Color(0.3, 0.3, 0.3)
	_mats[key] = m
	return m


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
