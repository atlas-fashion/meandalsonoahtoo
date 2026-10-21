extends CharacterBody3D

## The surgical table (2026-10-21): the machine in the surgery (surgery.gd)
## that was to make the dead prisoners bionic. It cannot be killed -- a blow on
## it only rings off the steel -- only DEPOWERED.
##
## It sleeps on its pedestal in the middle of the hall with a dead prisoner
## strapped to it, a drill half fitted to the forearm. A player walking in wakes
## it: its head-like sensor turns to them, the restraints snap open and throw
## the body off, its six legs unfold and it climbs off the pedestal and hunts.
##
## Three SYSTEMS, each fed by its own thick cable to its own wall mechanism
## (surgery.gd draws the cables and works the mechanisms off what this exposes):
## - ARMS: the long restraint arm (a telescoping arm ending in a shackle, the
##   GRAB) and the two pincer arms (the SWEEP). Their cable twitches whenever
##   they move (`arm_motion`).
## - LEGS: the crawl, and the rear-up slam. Their cable shivers as it walks
##   (`leg_motion`).
## - CORE: the light in its belly. Its cable pulses with it (`core_glow`).
## A lever cuts one for a while (`cut`): the arms go limp; the legs give and it
## drags itself face down on its pincers; the core stalls it for a moment and
## then the arms' and legs' cables flare as they feed it back (`feed_*`). Each
## first cut makes it angrier (`level`): faster, quicker to strike, its levers
## shorter.
##
## Its weakness is the POWER CABLE under the chassis: three cuts sever it
## (`_cable_hit`). It is only in reach when the belly is (`exposed`): reared up
## before a slam, held up by the wall clamp, or dragging itself with its legs
## dead. The ways to finish it:
## - lure the restraint arm into the wall clamp (opened by cutting the ARMS --
##   it sits on the arms' relay) and cut the cable while it is held;
## - cut the cable while it rears;
## - jam the legs' flywheel while the legs are cut, so it drags itself for good;
## - the relay sequence: cut the CORE while the arms and legs are both cut, so
##   nothing feeds it back.

signal depowered(cause: StringName)
signal system_changed(system: StringName, on: bool)
signal woke

const SKELETON := preload("res://models/ossuary_skeleton_rigged.glb")
const SkeletonSword := preload("res://scripts/skeleton_sword.gd")
const ITEM_DROP := preload("res://scripts/item_drop.gd")

enum State { DORMANT, WAKING, HUNT, GRAB, SWEEP, REAR, CLAMPED, STALL, DYING, DEAD }

## --- The body ------------------------------------------------------------------
## The table top (the slab): long along Z, its head end -Z.
const SLAB := Vector3(0.9, 0.12, 2.35)
## Height of the slab's underside off the floor: asleep on the pedestal,
## standing on its legs, and down on its belly.
const LIFT_SLEEP := 0.84
const LIFT_STAND := 1.08
const LIFT_DRAG := 0.5
const LIFT_DEAD := 0.36
## The collision: a cylinder round the table's middle -- its legs reach past
## it. Any wider and it could not get between the piers (3.8 m apart) and the
## cover in the cells between them.
const RADIUS := 0.95
const BODY_HEIGHT := 1.5
## Legs: three a side; hips under the slab's edge, thigh and shin.
const LEG_Z: Array[float] = [-0.72, 0.0, 0.72]
const HIP := Vector3(0.36, -0.3, 0.0)
const THIGH := 0.9
const SHIN := 1.25
## A planted foot sits here from the middle (sideways x side, along x LEG_Z).
const FOOT_OUT := 1.32
const FOOT_ALONG := 1.38
## A foot steps once it is this far from where it should be.
const STEP := 0.5
const STEP_TIME := 0.24
const STEP_LIFT := 0.3
## The core in the chassis, and the three plugs the cables come out of (arms,
## legs, core), in the slab's frame.
const CORE_AT := Vector3(0.0, -0.3, 0.05)
const PLUGS := [Vector3(-0.42, -0.34, 0.95), Vector3(0.42, -0.34, 0.95), Vector3(0.0, -0.4, 1.12)]
## The colours.
const CORE_COLOUR := Color(0.55, 0.9, 1.0)
const EYE_COLOUR := Color(1.0, 0.32, 0.12)
const FEED_COLOUR := Color(1.0, 0.72, 0.4)

## --- Pace, by anger (`level` 0..4) ------------------------------------------------
const SPEED: Array[float] = [1.6, 2.1, 2.6, 3.1, 3.5]
const TURN: Array[float] = [1.4, 1.75, 2.1, 2.5, 2.9]
const DRAG_SPEED := 0.55
## Lever cuts last this long.
const CUT_TIME: Array[float] = [7.5, 6.5, 5.5, 5.0, 4.5]
const LEVEL_MAX := 4

## --- The grab (the restraint arm) ----------------------------------------------
## It strikes from up to GRAB_RANGE away, and the arm runs on past the aim to
## GRAB_REACH unless stone stops it -- so a player who stands before the clamp
## and steps aside sends it on into the jaws.
const GRAB_RANGE := 5.2
const GRAB_REACH := 7.5
const GRAB_MIN := 2.4
const GRAB_WINDUP: Array[float] = [1.15, 1.0, 0.88, 0.78, 0.7]
## The aim is fixed this long before the lunge: step aside then.
const GRAB_LOCK := 0.28
const GRAB_LUNGE := 0.2
const GRAB_HOLD := 0.45
const GRAB_RETRACT := 0.9
const GRAB_DAMAGE := 20.0
const GRAB_YANK := 6.0
const GRAB_COOLDOWN: Array[float] = [3.6, 3.1, 2.7, 2.3, 2.0]
## A body this close to the arm's line is caught by it.
const GRAB_HIT := 0.6
## The arm's shoulder (on the slab, behind the sensor) and its length folded.
const SHOULDER := Vector3(0.0, 0.14, -0.55)
const ARM_FOLDED := 1.35
const ARM_SEGMENTS := 4

## --- The sweep (the pincers) -----------------------------------------------------
const SWEEP_RANGE := 2.9
const SWEEP_WINDUP: Array[float] = [0.62, 0.55, 0.5, 0.45, 0.4]
const SWEEP_SWING := 0.24
const SWEEP_RECOVER := 0.55
const SWEEP_DAMAGE := 12.0
const SWEEP_COOLDOWN: Array[float] = [2.4, 2.1, 1.8, 1.6, 1.4]
const PINCER_AT := Vector3(0.5, -0.02, -0.92)
const PINCER_UPPER := 0.78
const PINCER_FORE := 0.85

## --- The rear-up slam -------------------------------------------------------------
const REAR_RANGE := 3.3
const REAR_RISE := 0.95
const REAR_HOLD := 0.4
const REAR_SLAM := 0.14
const REAR_SETTLE := 0.8
const REAR_PITCH := 0.78
const REAR_DAMAGE := 24.0
const REAR_RADIUS := 3.1
const REAR_COOLDOWN: Array[float] = [8.0, 7.0, 6.0, 5.5, 5.0]

## --- The core stalled -----------------------------------------------------------
const STALL_TIME := 1.9
## When in the stall the cut systems' cables flare, feeding it back.
const FEED_AT := 0.9

## --- The power cable ------------------------------------------------------------
const CABLE_CUTS := 3
## Held by the wall clamp this long while the legs pull (`level` shortens it).
const CLAMP_HOLD: Array[float] = [7.5, 6.8, 6.0, 5.4, 4.8]
## Held, it is hauled to this far (its shoulder from the clamp).
const CLAMP_STANDOFF := 3.4
const CLAMP_PITCH := 0.5
## Pincers flail while it is held: a hit on anyone this close, this often.
const FLAIL_RANGE := 2.5
const FLAIL_EVERY := 1.3
const FLAIL_DAMAGE := 8.0

## --- Path -------------------------------------------------------------------------
const REPATH := 0.35
## How near the player it stops.
const STAND_OFF := 2.1

var room: Node3D
## The room's private navigation map: baked for a body this size
## (surgery.gd `_bake_table_nav`). An invalid RID means steer straight.
var nav_map := RID()
## The pedestal top: where it sleeps.
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
## While the belly is in reach.
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
var _path := PackedVector3Array()
var _path_i := 0
var _next_path := 0.0
var _next_grab := 0.0
var _next_sweep := 0.0
var _next_rear := 0.0
var _next_flail := 0.0
var _hit_done := false
var _aim := Vector3.FORWARD
var _aim_locked := false
var _reach := GRAB_REACH
var _clamp_point := Vector3.ZERO
var _strain := 0.0
var _last_cable_hit := -INF
var _stun_until := 0.0
var _home_yaw_hold := 0.0

## Pose, eased toward each frame's targets.
var _lift := LIFT_SLEEP
var _pitch := 0.0
var _pivot := 1.0
var _roll := 0.0
var _arm_len := ARM_FOLDED
var _arm_dir := Vector3.BACK
var _cuff_open := 0.0
var _power := 0.0
var _crawl := 0.0
var _gait := 0.0

## Nodes.
var _body: Node3D
var _neck: Node3D
var _head: Node3D
var _lens_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _belly_mat: StandardMaterial3D
var _core_light: OmniLight3D
var _arm_root: Node3D
var _arm_segs: Array[Node3D] = []
var _cuff: Node3D
var _cuff_jaws: Array[Node3D] = []
var _pincers: Array = []
var _cuffs: Array[Node3D] = []
var _legs: Array = []
var _cable_box: StaticBody3D
var _cable_shape: CollisionShape3D
var _belly_cable: MeshInstance3D
var _prisoner: Node3D
var _prisoner_rest := Transform3D()
var _audio: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _phase := Vector3.ZERO

static var _mats := {}


## A hitbox on the power cable: anything that hurts takes a cut out of it.
class CableHitbox extends StaticBody3D:
	var table: Node

	func take_damage(_amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
		if is_instance_valid(table):
			table.call("_cable_hit", from_direction)


# --- Building ---------------------------------------------------------------------

func _ready() -> void:
	add_to_group(&"surgical_table")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	# Solid to everyone (1) and hurtable (3) -- the blow only rings off it. It
	# walks against props (1) and the walls' simple copy (10).
	collision_layer = 1 | 4
	collision_mask = 1 | 512
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = BODY_HEIGHT
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	# Held well off the floor: in floating mode the floor is a wall like any
	# other, and the brick floor's unevenness stopped it dead.
	cs.position = Vector3(0.0, BODY_HEIGHT * 0.5 + 0.3, 0.0)
	add_child(cs)
	_build_body()
	_build_audio()
	_phase = Vector3(randf() * 10.0, randf() * 10.0, randf() * 10.0)
	_sleep_pose()


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var parts: Array = []
	var hs := SLAB * 0.5
	# The slab: a steel top with a raised rim, a drain at the foot.
	parts.append([_boxm(SLAB), Transform3D(Basis(), Vector3(0.0, SLAB.y * 0.5, 0.0)), &"steel"])
	for s: float in [-1.0, 1.0]:
		parts.append([_boxm(Vector3(0.05, 0.06, SLAB.z)), Transform3D(Basis(), Vector3(s * (hs.x - 0.025), SLAB.y + 0.03, 0.0)), &"steel"])
	parts.append([_boxm(Vector3(SLAB.x, 0.06, 0.05)), Transform3D(Basis(), Vector3(0.0, SLAB.y + 0.03, -hs.z + 0.025)), &"steel"])
	parts.append([_cylm(0.07, 0.07, 0.02, 10), Transform3D(Basis(), Vector3(0.0, SLAB.y + 0.005, hs.z - 0.22)), &"dark"])
	# The chassis under it, armoured skirts down its sides, the core's cage.
	parts.append([_boxm(Vector3(0.62, 0.36, 1.85)), Transform3D(Basis(), Vector3(0.0, -0.2, 0.05)), &"dark"])
	for s: float in [-1.0, 1.0]:
		var skirt := Basis(Vector3.FORWARD, s * 0.22)
		parts.append([_boxm(Vector3(0.05, 0.42, 2.0)), Transform3D(skirt, Vector3(s * 0.4, -0.22, 0.0)), &"rust"])
		# Rivets along the skirt.
		for k in 7:
			parts.append([_cylm(0.018, 0.018, 0.02, 6), Transform3D(skirt * Basis(Vector3.FORWARD, PI * 0.5),
				Vector3(s * 0.43, -0.1, -0.9 + float(k) * 0.3)), &"brass"])
		# The porthole the core shows through.
		parts.append([_torusm(0.15, 0.21), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(s * 0.33, -0.24, CORE_AT.z)), &"brass"])
		# Hip housings.
		for z in LEG_Z:
			parts.append([_cylm(0.11, 0.11, 0.2, 10), Transform3D(Basis(Vector3.FORWARD, PI * 0.5),
				Vector3(s * HIP.x, HIP.y, z)), &"dark"])
	# The rear socket the cables come out of.
	parts.append([_boxm(Vector3(0.95, 0.24, 0.24)), Transform3D(Basis(), Vector3(0.0, -0.32, 1.02)), &"dark"])
	for p: Vector3 in PLUGS:
		parts.append([_cylm(0.085, 0.085, 0.14, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0.0, 0.0, 0.0)), &"brass"])
	# The pincer and arm mounts.
	parts.append([_cylm(0.16, 0.2, 0.14, 12), Transform3D(Basis(), SHOULDER + Vector3(0.0, -0.06, 0.0)), &"dark"])
	for s: float in [-1.0, 1.0]:
		parts.append([_boxm(Vector3(0.16, 0.16, 0.22)), Transform3D(Basis(), PINCER_AT * Vector3(s, 1.0, 1.0)), &"dark"])
	_body.add_child(_merge(parts, "Chassis"))

	# The core: a sphere of light in the chassis, seen through both portholes.
	_core_mat = _mat(&"core").duplicate()
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sphere := SphereMesh.new()
	sphere.radius = 0.19
	sphere.height = 0.38
	sphere.radial_segments = 14
	sphere.rings = 7
	core.mesh = sphere
	core.material_override = _core_mat
	core.position = CORE_AT
	_body.add_child(core)
	_core_light = OmniLight3D.new()
	_core_light.name = "CoreLight"
	_core_light.light_color = CORE_COLOUR
	_core_light.omni_range = 5.5
	_core_light.omni_attenuation = 1.4
	_core_light.light_energy = 0.0
	_core_light.light_specular = 0.3
	_core_light.shadow_enabled = false
	_core_light.position = CORE_AT + Vector3(0.0, -0.25, 0.0)
	_body.add_child(_core_light)

	# The power cable: out of the core, down in a loop under the belly and up
	# into the rear socket. Glows with the core; reddens as it is cut.
	_belly_mat = _mat(&"belly").duplicate()
	var cable_parts: Array = []
	var pts := [CORE_AT + Vector3(0.0, -0.12, 0.08), Vector3(0.0, -0.52, 0.22), Vector3(0.0, -0.64, 0.48),
		Vector3(0.0, -0.6, 0.74), Vector3(0.0, -0.42, 0.95)]
	for i in pts.size() - 1:
		cable_parts.append([_cylm(0.075, 0.075, (pts[i + 1] - pts[i]).length() + 0.06, 10),
			_along(pts[i], pts[i + 1]), &"belly"])
	_belly_cable = _merge(cable_parts, "PowerCable")
	_belly_cable.material_override = _belly_mat
	_body.add_child(_belly_cable)
	_cable_box = CableHitbox.new()
	_cable_box.name = "PowerCableHitbox"
	_cable_box.set("table", self)
	_cable_box.collision_layer = 0
	_cable_box.collision_mask = 0
	_cable_box.position = Vector3(0.0, -0.55, 0.5)
	_body.add_child(_cable_box)
	_cable_shape = CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1.1, 1.0, 1.4)
	_cable_shape.shape = cbox
	_cable_box.add_child(_cable_shape)

	# The sensor: a neck rising at the head end and a head with one big lens.
	_neck = Node3D.new()
	_neck.name = "Neck"
	_neck.position = Vector3(0.0, SLAB.y, -hs.z + 0.2)
	_body.add_child(_neck)
	var neck_parts: Array = [
		[_cylm(0.06, 0.09, 0.42, 10), Transform3D(Basis(), Vector3(0.0, 0.21, 0.0)), &"dark"],
		[_cylm(0.12, 0.12, 0.06, 12), Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)), &"brass"],
	]
	_neck.add_child(_merge(neck_parts, "NeckMesh"))
	_head = Node3D.new()
	_head.name = "Sensor"
	_head.position = Vector3(0.0, 0.46, 0.0)
	_neck.add_child(_head)
	var head_parts: Array = [
		[_boxm(Vector3(0.34, 0.24, 0.3)), Transform3D(Basis(), Vector3(0.0, 0.04, 0.02)), &"rust"],
		[_cylm(0.12, 0.14, 0.12, 14), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.04, -0.17)), &"dark"],
		[_boxm(Vector3(0.04, 0.16, 0.2)), Transform3D(Basis(), Vector3(-0.19, 0.04, 0.02)), &"brass"],
		[_boxm(Vector3(0.04, 0.16, 0.2)), Transform3D(Basis(), Vector3(0.19, 0.04, 0.02)), &"brass"],
	]
	_head.add_child(_merge(head_parts, "SensorMesh"))
	_lens_mat = _mat(&"lens").duplicate()
	var lens := MeshInstance3D.new()
	lens.name = "Lens"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.085
	disc.bottom_radius = 0.085
	disc.height = 0.02
	disc.radial_segments = 14
	disc.rings = 1
	lens.mesh = disc
	lens.material_override = _lens_mat
	lens.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	lens.position = Vector3(0.0, 0.04, -0.235)
	_head.add_child(lens)

	# The restraints on the top: wrists by the head, ankles by the foot. Each a
	# hinged steel cuff over a leather strap, shut over the prisoner.
	var cuff_at := [Vector3(-0.3, 0.0, -0.52), Vector3(0.3, 0.0, -0.52), Vector3(-0.13, 0.0, 0.92), Vector3(0.13, 0.0, 0.92)]
	for c: Vector3 in cuff_at:
		var hinge := Node3D.new()
		hinge.name = "Restraint"
		var side := signf(c.x)
		hinge.position = Vector3(c.x + side * 0.12, SLAB.y + 0.02, c.z)
		_body.add_child(hinge)
		var cuff_parts: Array = [
			[_boxm(Vector3(0.26, 0.04, 0.1)), Transform3D(Basis(), Vector3(-side * 0.12, 0.09, 0.0)), &"steel"],
			[_boxm(Vector3(0.04, 0.1, 0.1)), Transform3D(Basis(), Vector3(-side * 0.24, 0.05, 0.0)), &"steel"],
			[_boxm(Vector3(0.04, 0.1, 0.1)), Transform3D(Basis(), Vector3(0.0, 0.05, 0.0)), &"steel"],
			[_boxm(Vector3(0.24, 0.015, 0.08)), Transform3D(Basis(), Vector3(-side * 0.12, 0.115, 0.0)), &"leather"],
		]
		hinge.add_child(_merge(cuff_parts, "Cuff"))
		_cuffs.append(hinge)

	# The restraint arm: a turret on the top, four telescoping sections and the
	# shackle at the end.
	_arm_root = Node3D.new()
	_arm_root.name = "RestraintArm"
	_arm_root.position = SHOULDER
	_body.add_child(_arm_root)
	var turret: Array = [[_sphm(0.16), Transform3D(), &"brass"]]
	_arm_root.add_child(_merge(turret, "Turret"))
	for i in ARM_SEGMENTS:
		var seg := Node3D.new()
		seg.name = "Section%d" % i
		_arm_root.add_child(seg)
		var r := 0.1 - float(i) * 0.016
		var len_ := ARM_FOLDED + 0.05
		var seg_parts: Array = [[_cylm(r, r, len_, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -len_ * 0.5)), &"steel" if i % 2 == 0 else &"dark"],
			[_cylm(r + 0.02, r + 0.02, 0.07, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, -len_ + 0.04)), &"brass"]]
		seg.add_child(_merge(seg_parts, "SectionMesh"))
		_arm_segs.append(seg)
	_cuff = Node3D.new()
	_cuff.name = "Shackle"
	_arm_root.add_child(_cuff)
	_cuff.add_child(_merge([[_boxm(Vector3(0.36, 0.1, 0.12)), Transform3D(), &"dark"]], "ShackleBase"))
	for s: float in [-1.0, 1.0]:
		var jaw := Node3D.new()
		jaw.position = Vector3(s * 0.16, 0.0, 0.0)
		_cuff.add_child(jaw)
		var jaw_parts: Array = [
			[_boxm(Vector3(0.05, 0.08, 0.34)), Transform3D(Basis(), Vector3(0.0, 0.0, -0.17)), &"steel"],
			[_boxm(Vector3(0.16, 0.08, 0.05)), Transform3D(Basis(), Vector3(-s * 0.08, 0.0, -0.34)), &"steel"],
		]
		jaw.add_child(_merge(jaw_parts, "Jaw"))
		_cuff_jaws.append(jaw)

	# The pincers: shoulder, upper arm, elbow, forearm, two fingers.
	for s: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.name = "Pincer"
		sh.position = PINCER_AT * Vector3(s, 1.0, 1.0)
		_body.add_child(sh)
		sh.add_child(_merge([[_boxm(Vector3(0.1, 0.12, PINCER_UPPER)), Transform3D(Basis(), Vector3(0.0, 0.0, -PINCER_UPPER * 0.5)), &"rust"],
			[_cylm(0.035, 0.035, PINCER_UPPER * 0.8, 8), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.09, -PINCER_UPPER * 0.5)), &"steel"]], "Upper"))
		var el := Node3D.new()
		el.position = Vector3(0.0, 0.0, -PINCER_UPPER)
		sh.add_child(el)
		el.add_child(_merge([[_sphm(0.08), Transform3D(), &"brass"],
			[_boxm(Vector3(0.08, 0.09, PINCER_FORE)), Transform3D(Basis(), Vector3(0.0, 0.0, -PINCER_FORE * 0.5)), &"dark"]], "Fore"))
		var claw := Node3D.new()
		claw.position = Vector3(0.0, 0.0, -PINCER_FORE)
		el.add_child(claw)
		var fingers: Array[Node3D] = []
		for f: float in [-1.0, 1.0]:
			var finger := Node3D.new()
			claw.add_child(finger)
			finger.add_child(_merge([[_boxm(Vector3(0.03, 0.05, 0.3)), Transform3D(Basis(), Vector3(0.0, 0.0, -0.15)), &"steel"],
				[_boxm(Vector3(0.03, 0.05, 0.1)), Transform3D(Basis(Vector3.UP, -f * 0.9), Vector3(-f * 0.03, 0.0, -0.3)), &"steel"]], "Finger"))
			fingers.append(finger)
		_pincers.append({"shoulder": sh, "elbow": el, "fingers": fingers, "side": s})

	# The legs: thigh and shin, a knee between, a hooked foot.
	for s: float in [-1.0, 1.0]:
		for i in LEG_Z.size():
			var thigh := MeshInstance3D.new()
			thigh.mesh = _merge_mesh([[_boxm(Vector3(0.11, THIGH, 0.13)), Transform3D(Basis(), Vector3(0.0, THIGH * 0.5, 0.0)), &"rust"],
				[_cylm(0.03, 0.03, THIGH * 0.7, 8), Transform3D(Basis(), Vector3(0.0, THIGH * 0.5, 0.09)), &"steel"]])
			add_child(thigh)
			var shin := MeshInstance3D.new()
			# Its mesh runs from the foot (y 0, a hooked point) up to the knee.
			shin.mesh = _merge_mesh([[_cylm(0.06, 0.035, SHIN, 8), Transform3D(Basis(), Vector3(0.0, SHIN * 0.5, 0.0)), &"dark"],
				[_sphm(0.075), Transform3D(Basis(), Vector3(0.0, SHIN, 0.0)), &"brass"],
				[_cylm(0.04, 0.0, 0.16, 6), Transform3D(Basis(), Vector3(0.0, -0.04, 0.0)), &"steel"]])
			add_child(shin)
			for mi: MeshInstance3D in [thigh, shin]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_legs.append({"side": s, "z": LEG_Z[i], "thigh": thigh, "shin": shin,
				"group": (i + (1 if s > 0.0 else 0)) % 2, "foot": Vector3.ZERO,
				"from": Vector3.ZERO, "to": Vector3.ZERO, "step": -1.0})

	_build_prisoner()


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
	_prisoner.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, SLAB.y + 0.12, 0.88))
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
	_audio.position = Vector3(0.0, 0.8, 0.0)
	add_child(_audio)


# --- Asleep, awake, depowered -------------------------------------------------------

## As built: on its pedestal, legs folded, the prisoner strapped down.
func _sleep_pose() -> void:
	state = State.DORMANT
	_dying = false
	global_position = home
	global_rotation = Vector3(0.0, home_yaw, 0.0)
	_lift = LIFT_SLEEP
	_pitch = 0.0
	_roll = 0.0
	_power = 0.0
	_arm_len = ARM_FOLDED
	_arm_dir = Vector3.BACK
	exposed = false
	for c in _cuffs:
		c.rotation = Vector3.ZERO
	if _prisoner != null:
		if _prisoner.get_parent() != _body:
			_prisoner.get_parent().remove_child(_prisoner)
			_body.add_child(_prisoner)
		_prisoner.transform = _prisoner_rest
	for leg in _legs:
		var f := _fold_target(leg)
		leg["foot"] = f
		leg["step"] = -1.0
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


## A save that had it depowered: down where it fell.
func set_dead_now(at: Vector3, yaw: float) -> void:
	state = State.DEAD
	_dying = true
	global_position = at
	global_rotation = Vector3(0.0, yaw, 0.0)
	_power = 0.0
	_lift = LIFT_DEAD
	_pitch = -0.06
	_roll = 0.12
	exposed = false
	_throw_prisoner(true)
	for c in _cuffs:
		c.rotation.z = 1.9 * signf(c.position.x)
	for leg in _legs:
		leg["foot"] = _limp_target(leg)
	_apply_pose(0.0)


func is_depowered() -> bool:
	return state == State.DEAD or state == State.DYING


func arms_on() -> bool:
	return _now() >= _arms_off_until and not is_depowered()


func legs_on() -> bool:
	return not legs_jammed and _now() >= _legs_off_until and not is_depowered()


## A lever: `system` off for a while. Cutting the core while both the arms and
## the legs are off shuts it down for good.
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


## The legs' flywheel jammed while they were cut: they never come back.
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


# --- Each tick ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if room == null:
		return
	_update_systems()
	var now := _now()
	_t += delta
	var want := Vector3.ZERO
	match state:
		State.DORMANT:
			if _intruder() != null:
				_wake()
		State.WAKING:
			if _t >= 3.0:
				_enter(State.HUNT)
				_next_grab = now + 1.5
				_next_rear = now + 4.0
		State.HUNT:
			want = _hunt(now)
		State.GRAB:
			_grab(now, delta)
		State.SWEEP:
			_sweep()
		State.REAR:
			_rear()
		State.CLAMPED:
			want = _clamped(now, delta)
		State.STALL:
			if _t >= STALL_TIME:
				_enter(State.HUNT)
		State.DYING:
			if _t >= 3.2:
				_die_done()
	if state == State.DORMANT or state == State.DEAD or state == State.DYING:
		velocity = Vector3.ZERO
		return
	velocity = Vector3(want.x, 0.0, want.z)
	if velocity.length_squared() > 0.0001:
		move_and_slide()
	# Never out of the hall: its walls are the room's, but a doorway is not.
	var local: Vector3 = room.to_local(global_position)
	var clamped := Vector3(clampf(local.x, -bound, bound), 0.0, clampf(local.z, -bound, bound))
	if not clamped.is_equal_approx(Vector3(local.x, 0.0, local.z)):
		global_position = room.to_global(clamped)
	global_position.y = home.y
	_crawl = lerpf(_crawl, velocity.length(), clampf(delta * 6.0, 0.0, 1.0))


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


func _hunt(now: float) -> Vector3:
	_target = _intruder()
	var flat_fwd := -global_basis.z
	var speed: float = SPEED[level] if legs_on() else DRAG_SPEED
	if now < _stun_until:
		return Vector3.ZERO
	if _target == null:
		# Nobody in the hall: back to the pedestal, to wait.
		var to_home := home - global_position
		to_home.y = 0.0
		if to_home.length() > 2.6:
			return _follow(home, now, speed * 0.6)
		_turn_toward(global_position + Basis(Vector3.UP, home_yaw) * Vector3.FORWARD, 0.6)
		return Vector3.ZERO
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var facing := flat_fwd.dot(to.normalized()) if dist > 0.01 else 1.0
	_turn_toward(_target.global_position, TURN[level] * (1.0 if legs_on() else 0.5))
	# Attacks, nearest first.
	if facing > 0.75:
		if legs_on() and dist < REAR_RANGE and now >= _next_rear:
			_enter(State.REAR)
			_next_rear = now + REAR_COOLDOWN[level]
			return Vector3.ZERO
		if arms_on() and dist < SWEEP_RANGE and now >= _next_sweep:
			_enter(State.SWEEP)
			_next_sweep = now + SWEEP_COOLDOWN[level]
			return Vector3.ZERO
		if arms_on() and dist > GRAB_MIN and dist < GRAB_RANGE and now >= _next_grab \
				and _clear_line(_shoulder_world(), _target.global_position + Vector3(0.0, 1.1, 0.0)):
			_enter(State.GRAB)
			_aim = (_target.global_position + Vector3(0.0, 1.1, 0.0) - _shoulder_world()).normalized()
			return Vector3.ZERO
	if dist <= STAND_OFF:
		return Vector3.ZERO
	return _follow(_target.global_position, now, speed)


## Along its own navmesh toward `goal`, at `speed`.
func _follow(goal: Vector3, now: float, speed: float) -> Vector3:
	if now >= _next_path or _path.is_empty():
		_next_path = now + REPATH
		_path = PackedVector3Array()
		if nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			_path = NavigationServer3D.map_get_path(nav_map, global_position, goal, true)
		_path_i = 0
	# The end of the path is as near as it can get (the goal may be somewhere
	# it does not fit): there it waits, rather than walk into the stone.
	var next := _path[_path.size() - 1] if not _path.is_empty() else goal
	while _path_i < _path.size():
		var p := _path[_path_i]
		if Vector2(p.x - global_position.x, p.z - global_position.z).length() < 0.5:
			_path_i += 1
			continue
		next = p
		break
	var dir := next - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	dir = dir.normalized()
	# A crawler walks any way it likes; it turns to face where it goes only
	# while nothing is close enough to watch.
	if _target == null or global_position.distance_to(_target.global_position) > 9.0:
		_turn_toward(global_position + dir, TURN[level] * 0.7)
	return dir * speed


func _turn_toward(point: Vector3, rate: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var want := atan2(-to.x, -to.z)
	# World yaw: the room it stands in is turned.
	var d := wrapf(want - global_rotation.y, -PI, PI)
	var step := rate * get_physics_process_delta_time()
	global_rotation.y += clampf(d, -step, step)


func _clear_line(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoulder_world() -> Vector3:
	return _body.global_transform * SHOULDER


func _chest(p: Node3D) -> Vector3:
	return p.global_position + Vector3(0.0, 1.05, 0.0)


# --- The grab --------------------------------------------------------------------

func _grab(now: float, delta: float) -> void:
	var windup: float = GRAB_WINDUP[level]
	if not arms_on():
		_enter(State.HUNT)
		return
	if _t < windup - GRAB_LOCK:
		# Tracking: the arm drawn back and trembling, its cable twitching.
		if _target != null and is_instance_valid(_target):
			_aim = (_chest(_target) - _shoulder_world()).normalized()
			_turn_toward(_target.global_position, TURN[level])
		return
	if not _aim_locked:
		_aim_locked = true
		# Where it will go: along the aim until something stony stops it (sight's
		# layer: the walls, piers, props -- not the players, it goes through
		# where they stood).
		var from := _shoulder_world()
		var q := PhysicsRayQueryParameters3D.create(from, from + _aim * GRAB_REACH, 2)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		_reach = GRAB_REACH
		if not hit.is_empty():
			_reach = maxf(from.distance_to(hit["position"]) - 0.12, ARM_FOLDED)
		for p in Coop.all():
			if p.has_method("parry_cue"):
				p.call("parry_cue", self, GRAB_LOCK + GRAB_LUNGE + 0.25)
		return
	if _t < windup + GRAB_LUNGE + GRAB_HOLD:
		var tip := _shoulder_world() + _aim * _arm_len
		# The clamp: the arm driven on into its open jaws is caught there.
		if room != null and room.has_method("clamp_try_catch") and room.call("clamp_try_catch", _shoulder_world(), tip):
			_clamp_point = room.call("clamp_hold_point")
			_enter(State.CLAMPED)
			_strain = 0.0
			_anger()
			return
		if not _hit_done:
			for p in Coop.all():
				var n := p as Node3D
				if n == null or n.get("_dead") == true:
					continue
				if _segment_distance(_chest(n), _shoulder_world(), tip) <= GRAB_HIT:
					_hit_done = true
					var parried := _strike(n, GRAB_DAMAGE)
					if parried:
						# Turned aside: the arm snaps back and the machine reels.
						_stun_until = now + 0.9
						_enter(State.HUNT)
						_next_grab = now + GRAB_COOLDOWN[level] + 0.8
						return
					var pull := global_position - n.global_position
					pull.y = 0.0
					if n.has_method("apply_knockback") and pull.length_squared() > 0.01:
						n.call("apply_knockback", pull.normalized() * GRAB_YANK)
					break
		return
	if _t >= windup + GRAB_LUNGE + GRAB_HOLD + GRAB_RETRACT:
		_next_grab = now + GRAB_COOLDOWN[level]
		_enter(State.HUNT)


## A blow on player `p`; true if they parried it.
func _strike(p: Node3D, amount: float) -> bool:
	var dir := p.global_position - global_position
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

func _sweep() -> void:
	var windup: float = SWEEP_WINDUP[level]
	if not arms_on():
		_enter(State.HUNT)
		return
	if _t < windup:
		if not _aim_locked and _t >= windup - 0.25:
			_aim_locked = true
			for p in Coop.all():
				if p.has_method("parry_cue"):
					p.call("parry_cue", self, 0.45)
		return
	if not _hit_done and _t >= windup + SWEEP_SWING * 0.5:
		_hit_done = true
		var head := global_position - global_basis.z * 1.0
		for p in Coop.all():
			var n := p as Node3D
			if n == null or n.get("_dead") == true:
				continue
			var to := n.global_position - head
			to.y = 0.0
			if to.length() > SWEEP_RANGE or (-global_basis.z).dot(to.normalized()) < -0.2:
				continue
			if _strike(n, SWEEP_DAMAGE):
				_stun_until = _now() + 0.7
			elif n.has_method("apply_knockback"):
				n.call("apply_knockback", global_basis.x * (5.0 if to.dot(global_basis.x) > 0.0 else -5.0))
	if _t >= windup + SWEEP_SWING + SWEEP_RECOVER:
		_enter(State.HUNT)


# --- The rear-up slam ----------------------------------------------------------------

func _rear() -> void:
	exposed = _t < REAR_RISE + REAR_HOLD + REAR_SLAM * 0.5
	if not legs_on():
		exposed = false
		_enter(State.HUNT)
		return
	if not _hit_done and _t >= REAR_RISE + REAR_HOLD + REAR_SLAM:
		_hit_done = true
		var front := global_position - global_basis.z * 1.4
		for p in Coop.all():
			var n := p as Node3D
			if n == null or n.get("_dead") == true:
				continue
			var d := Vector2(n.global_position.x - front.x, n.global_position.z - front.z).length()
			if n.get("_shake") != null and d < 9.0:
				n.set("_shake", maxf(float(n.get("_shake")), 0.45 * (1.0 - d / 9.0)))
			if d > REAR_RADIUS:
				continue
			var guarded: bool = n.has_method("is_blocking") and n.call("is_blocking")
			_strike(n, REAR_DAMAGE)
			if not guarded and n.has_method("knock_down"):
				n.call("knock_down", n.global_position - global_position, 6.5)
		_sparks(front + Vector3(0.0, 0.1, 0.0), Color(1.0, 0.7, 0.4), 30)
	if _t >= REAR_RISE + REAR_HOLD + REAR_SLAM + REAR_SETTLE:
		_enter(State.HUNT)


# --- Held by the clamp -------------------------------------------------------------

func _clamped(now: float, delta: float) -> Vector3:
	exposed = true
	_aim = (_clamp_point - _shoulder_world()).normalized()
	_turn_toward(_clamp_point, 3.0)
	# Hauled in toward the clamp.
	var flat := _clamp_point - _shoulder_world()
	flat.y = 0.0
	var move := Vector3.ZERO
	if flat.length() > CLAMP_STANDOFF + 0.1 and _t < 1.2:
		move = flat.normalized() * 3.0
	# The legs pull it free in time; with them cut it cannot pull at all.
	if legs_on():
		_strain += delta
	if _strain >= CLAMP_HOLD[level]:
		exposed = false
		if room != null and room.has_method("clamp_release"):
			room.call("clamp_release", true)
		_stun_until = now + 0.6
		_next_grab = now + GRAB_COOLDOWN[level] + 1.5
		_anger()
		_enter(State.HUNT)
		return Vector3.ZERO
	# The pincers flail at anyone in close.
	if now >= _next_flail and arms_on():
		var head := global_position - global_basis.z * 1.0
		for p in Coop.all():
			var n := p as Node3D
			if n == null or n.get("_dead") == true:
				continue
			if Vector2(n.global_position.x - head.x, n.global_position.z - head.z).length() <= FLAIL_RANGE:
				_next_flail = now + FLAIL_EVERY
				_strike(n, FLAIL_DAMAGE)
				break
	return move


## How far it has pulled against the clamp, 0..1 (surgery.gd shakes the clamp).
func strain() -> float:
	return clampf(_strain / float(CLAMP_HOLD[level]), 0.0, 1.0) if state == State.CLAMPED else 0.0


# --- Being hit ----------------------------------------------------------------------

## A blow on the table itself: steel rings, sparks fly, the sensor finds whoever
## did it. Nothing is hurt.
func take_damage(_amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
	if state == State.DEAD:
		return
	var at := global_position + Vector3(0.0, _lift + 0.1, 0.0) - from_direction * 0.9
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
	# worked on, out of the cracked porthole.
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
	var lift := LIFT_STAND
	var pitch := 0.0
	var pivot := 1.0
	var roll := 0.0
	var power := 1.0
	var arm_target := Vector3(0.0, 0.85, 0.55)
	var arm_len := ARM_FOLDED + 0.25
	var cuff_open := 1.0
	var tremble := 0.0
	var arms_live := arms_on()
	var legs_live := legs_on()
	var arm_world := false
	match state:
		State.DORMANT:
			lift = LIFT_SLEEP
			power = 0.0
			arm_target = Vector3(0.0, 0.06, 1.0)
			arm_len = ARM_FOLDED
			cuff_open = 0.0
		State.WAKING:
			var w := clampf((_t - 1.8) / 0.9, 0.0, 1.0)
			lift = lerpf(LIFT_SLEEP, LIFT_STAND, smoothstep(0.0, 1.0, w))
			power = clampf(_t / 1.2, 0.0, 1.0) * (0.6 + 0.4 * absf(sin(_t * 23.0))) if _t < 1.2 else 1.0
			arm_target = Vector3(0.0, 0.06, 1.0).lerp(Vector3(0.0, 0.85, 0.55), w)
			cuff_open = w
			# The restraints snap open one after another, and the body is thrown.
			for i in _cuffs.size():
				var open_at := 1.0 + float(i) * 0.12
				if _t >= open_at:
					var side := signf(_cuffs[i].position.x)
					var o := clampf((_t - open_at) / 0.09, 0.0, 1.0)
					_cuffs[i].rotation.z = side * (2.05 - 0.15 * sin(o * PI)) * o
			if _t >= 1.25 and _prisoner.get_parent() == _body:
				_throw_prisoner(false)
		State.GRAB:
			var windup: float = GRAB_WINDUP[level]
			arm_world = true
			if _t < windup:
				# Drawn back along the aim, trembling.
				arm_len = ARM_FOLDED - 0.05
				tremble = 0.04 + 0.05 * (_t / windup)
			elif _t < windup + GRAB_LUNGE:
				arm_len = lerpf(ARM_FOLDED, _reach, smoothstep(0.0, 1.0, (_t - windup) / GRAB_LUNGE))
			elif _t < windup + GRAB_LUNGE + GRAB_HOLD:
				arm_len = _reach
				cuff_open = 0.0 if _hit_done else 1.0
			else:
				var r := clampf((_t - windup - GRAB_LUNGE - GRAB_HOLD) / GRAB_RETRACT, 0.0, 1.0)
				arm_len = lerpf(_reach, ARM_FOLDED, smoothstep(0.0, 1.0, r))
				arm_world = r < 0.6
		State.REAR:
			if _t < REAR_RISE:
				pitch = REAR_PITCH * smoothstep(0.0, 1.0, _t / REAR_RISE)
			elif _t < REAR_RISE + REAR_HOLD:
				pitch = REAR_PITCH + 0.04 * sin(_t * 30.0)
			elif _t < REAR_RISE + REAR_HOLD + REAR_SLAM:
				pitch = lerpf(REAR_PITCH, -0.06, (_t - REAR_RISE - REAR_HOLD) / REAR_SLAM)
			else:
				pitch = -0.06 * (1.0 - clampf((_t - REAR_RISE - REAR_HOLD - REAR_SLAM) / REAR_SETTLE, 0.0, 1.0))
			lift = LIFT_STAND + 0.12 * clampf(pitch / REAR_PITCH, 0.0, 1.0)
			pivot = 1.05
		State.CLAMPED:
			arm_world = true
			_aim = (_clamp_point - _shoulder_world()).normalized()
			arm_len = clampf(_shoulder_world().distance_to(_clamp_point), ARM_FOLDED, GRAB_REACH)
			cuff_open = 0.0
			pitch = CLAMP_PITCH + 0.05 * sin(now * 17.0) * (1.0 if legs_live else 0.3)
			pivot = 1.05
			roll = 0.07 * sin(now * 9.0)
		State.STALL:
			lift = LIFT_STAND - 0.22
			pitch = -0.05
			power = 0.06 if _t < FEED_AT else clampf((_t - FEED_AT) / 0.5, 0.0, 1.0) * (1.0 + 0.6 * sin(_t * 40.0))
			arm_target = Vector3(0.0, 0.25, 0.9)
		State.DYING:
			# It staggers, the legs buckle in turn, and it crashes down.
			var crash := clampf((_t - 1.2) / 0.25, 0.0, 1.0)
			lift = lerpf(LIFT_STAND - 0.15 * clampf(_t / 1.2, 0.0, 1.0), LIFT_DEAD, crash * crash)
			pitch = -0.06 * crash
			roll = 0.12 * crash + (0.05 * sin(_t * 21.0) if crash < 1.0 else 0.0)
			power = clampf(1.0 - _t / 2.6, 0.0, 1.0) * (0.5 + 0.5 * absf(sin(_t * 31.0)))
			arm_target = Vector3(0.0, -0.3, 0.95)
			arm_len = ARM_FOLDED + 0.4
			if crash >= 1.0 and not _hit_done:
				_hit_done = true
				for p in Coop.all():
					var n := p as Node3D
					if n != null and n.get("_shake") != null and n.global_position.distance_to(global_position) < 16.0:
						n.set("_shake", maxf(float(n.get("_shake")), 0.6))
				_sparks(global_position + Vector3(0.0, 0.4, 0.0), Color(1.0, 0.75, 0.45), 40)
		State.DEAD:
			lift = LIFT_DEAD
			pitch = -0.06
			roll = 0.12
			power = 0.0
			arm_target = Vector3(0.0, -0.3, 0.95)
			arm_len = ARM_FOLDED + 0.4
	# Legs cut (or jammed): face down on the floor, dragging itself on its
	# pincers, its back end and the power cable under it lifted into reach.
	var dragging := not legs_live and state not in [State.DORMANT, State.WAKING, State.DYING, State.DEAD, State.CLAMPED]
	if dragging:
		lift = LIFT_DRAG
		pitch = -0.2
		pivot = -1.0
		exposed = true
	elif state not in [State.REAR, State.CLAMPED]:
		exposed = false
	if state == State.HUNT and legs_live:
		lift += 0.03 * sin(_gait * PI * 2.0)
	if now < _stun_until:
		roll += 0.05 * sin(now * 40.0)

	_lift = lerpf(_lift, lift, k if state != State.DYING else fast)
	_pitch = lerpf(_pitch, pitch, fast if state == State.REAR else k)
	_pivot = lerpf(_pivot, pivot, k)
	_roll = lerpf(_roll, roll, k)
	if delta <= 0.0:
		_lift = lift
		_pitch = pitch
		_roll = roll
		_pivot = pivot
	_power = lerpf(_power, power, fast)
	_body.transform = Transform3D(Basis(), Vector3(0.0, _lift, 0.0)) \
		* Transform3D(Basis(), Vector3(0.0, 0.0, _pivot)) \
		* Transform3D(Basis(Vector3.FORWARD, _roll) * Basis(Vector3.RIGHT, _pitch), Vector3.ZERO) \
		* Transform3D(Basis(), Vector3(0.0, 0.0, -_pivot))

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
	_belly_mat.emission_energy_multiplier = (0.3 + 1.6 * wound) * core_glow + (0.6 if exposed else 0.0) * core_glow
	_lens_mat.emission_energy_multiplier = 0.0 if _power < 0.05 else (2.5 + 3.0 * float(level) / LEVEL_MAX) * _power
	# The feed-back flare along the cables while the core stalls.
	var feed := 0.0
	if state == State.STALL and _t >= FEED_AT:
		feed = clampf(1.0 - (_t - FEED_AT) / 0.9, 0.0, 1.0)
	feed_arms = lerpf(feed_arms, feed if arms_live else 0.0, fast)
	feed_legs = lerpf(feed_legs, feed if legs_live else 0.0, fast)

	_pose_sensor(k, now)
	_pose_arm(arm_target, arm_len, cuff_open, tremble, arm_world, fast if state == State.GRAB else k, delta)
	_pose_pincers(k, now, arms_live, dragging)
	_pose_legs(delta, legs_live)

	# What the cables show.
	var arms_moving := 0.0
	if arms_live and _power > 0.3:
		arms_moving = 0.2
		if state in [State.GRAB, State.SWEEP, State.CLAMPED] or dragging:
			arms_moving = 1.0
	arm_motion = lerpf(arm_motion, arms_moving, fast)
	leg_motion = lerpf(leg_motion, clampf(_crawl / 2.0, 0.0, 1.0) if legs_live and _power > 0.3 else 0.0, fast)


func _pose_sensor(k: float, now: float) -> void:
	var yaw := 0.0
	var pitch := -0.55
	if _power > 0.05 and state != State.DEAD:
		var look: Node3D = _target if _target != null and is_instance_valid(_target) else _intruder()
		if look != null:
			var local: Vector3 = _neck.global_transform.affine_inverse() * (look.global_position + Vector3(0.0, 1.5, 0.0))
			yaw = clampf(atan2(-local.x, -local.z), -2.4, 2.4)
			pitch = clampf(atan2(local.y - 0.46, Vector2(local.x, local.z).length()), -0.8, 0.7)
		else:
			yaw = 0.9 * sin(now * 0.5)
			pitch = -0.15
		if state == State.STALL:
			pitch = -0.6
	var rate := k * (0.35 if state == State.WAKING else 1.0)
	_neck.rotation.y = lerp_angle(_neck.rotation.y, yaw, rate)
	_head.rotation.x = lerp_angle(_head.rotation.x, pitch, rate)


func _pose_arm(target: Vector3, length: float, cuff_open: float, tremble: float, world: bool, k: float, delta: float) -> void:
	var want: Vector3
	if world:
		# The arm root turns in the body's frame.
		want = (_body.global_basis.inverse() * _aim).normalized()
	else:
		want = target.normalized()
	if delta <= 0.0:
		_arm_dir = want
		_arm_len = length
	else:
		_arm_dir = _arm_dir.slerp(want, clampf(k * 1.6, 0.0, 1.0)).normalized()
		_arm_len = lerpf(_arm_len, length, clampf(k * 2.0, 0.0, 1.0)) if not world else length
	var dir := _arm_dir
	if tremble > 0.0:
		var n := _now()
		dir = (dir + Vector3(sin(n * 53.0), sin(n * 61.0), cos(n * 47.0)) * tremble).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	_arm_root.basis = Basis.looking_at(dir, up)
	# The sections telescope: each starts a share of the extra length further out.
	var extra := maxf(_arm_len - ARM_FOLDED, 0.0)
	for i in _arm_segs.size():
		_arm_segs[i].position = Vector3(0.0, 0.0, -extra * float(i) / float(ARM_SEGMENTS - 1))
	_cuff.position = Vector3(0.0, 0.0, -_arm_len)
	_cuff_open = lerpf(_cuff_open, cuff_open, clampf(k * 2.0, 0.0, 1.0))
	for i in _cuff_jaws.size():
		var s := -1.0 if i == 0 else 1.0
		_cuff_jaws[i].rotation.y = -s * 0.6 * _cuff_open


func _pose_pincers(k: float, now: float, live: bool, dragging: bool) -> void:
	for pin in _pincers:
		var s: float = pin["side"]
		var yaw := 0.4
		var pitch := 0.45
		var elbow := 1.5
		var claw := 0.35
		if _power < 0.05 or state in [State.DORMANT, State.DEAD]:
			yaw = 0.05
			pitch = -0.25 if state == State.DORMANT else -0.9
			elbow = 2.5 if state == State.DORMANT else 0.4
			claw = 0.0
		elif not live:
			# Cut: hanging, swinging with the body.
			yaw = 0.15 + 0.1 * sin(now * 2.0 + s)
			pitch = -1.0
			elbow = 0.25
			claw = 0.6
		elif dragging:
			# Hauling itself along: reach, plant, pull, by the crawl's phase.
			var ph := fmod(_gait + (0.5 if s > 0.0 else 0.0), 1.0)
			yaw = 0.15
			pitch = lerpf(-0.15, -0.65, ph)
			elbow = lerpf(0.3, 1.5, ph)
			claw = 0.7 if ph < 0.15 else 0.1
		elif state == State.SWEEP:
			var windup: float = SWEEP_WINDUP[level]
			if _t < windup:
				var w := _t / windup
				yaw = lerpf(0.4, 1.35, w)
				pitch = 0.25
				elbow = lerpf(1.5, 0.55, w)
				claw = 1.0
			else:
				var sw := clampf((_t - windup) / SWEEP_SWING, 0.0, 1.0)
				yaw = lerpf(1.35, -0.35, sw)
				pitch = 0.15
				elbow = 0.35
				claw = 1.0 - sw
		elif state == State.CLAMPED:
			yaw = 0.6 + 0.6 * sin(now * 7.0 + s * 2.0)
			pitch = 0.3 + 0.3 * sin(now * 5.0 + s)
			elbow = 1.0 + 0.6 * sin(now * 6.0)
			claw = 0.5 + 0.5 * sin(now * 11.0)
		else:
			yaw += 0.08 * sin(now * 1.3 + s) + 0.1 * clampf(_crawl, 0.0, 1.0) * sin(_gait * TAU + s)
			pitch += 0.05 * sin(now * 1.7 + s)
		var sh: Node3D = pin["shoulder"]
		var el: Node3D = pin["elbow"]
		# Outward is -side about UP for an arm along -Z.
		var basis := Basis(Vector3.UP, -s * yaw) * Basis(Vector3.RIGHT, pitch)
		sh.basis = sh.basis.slerp(basis, k).orthonormalized() if k < 1.0 else basis
		el.rotation.x = lerp_angle(el.rotation.x, -elbow, k)
		var fingers: Array = pin["fingers"]
		for i in fingers.size():
			var f := -1.0 if i == 0 else 1.0
			(fingers[i] as Node3D).rotation.y = lerp_angle((fingers[i] as Node3D).rotation.y, f * (0.1 + 0.55 * claw), k)


# --- Legs ------------------------------------------------------------------------------

## Where a planted foot belongs now: out from the hip on the floor, leading the
## way it moves.
func _rest_target(leg: Dictionary) -> Vector3:
	var s: float = leg["side"]
	var z: float = leg["z"]
	var p := global_transform * Vector3(s * FOOT_OUT, 0.0, z * FOOT_ALONG)
	p += velocity * 0.28
	p.y = global_position.y
	return p


## Asleep: folded up tight against the chassis.
func _fold_target(leg: Dictionary) -> Vector3:
	var s: float = leg["side"]
	var z: float = leg["z"]
	return _body.global_transform * Vector3(s * 0.62, -0.42, z * 0.92)


## Limp: splayed out on the floor.
func _limp_target(leg: Dictionary) -> Vector3:
	var s: float = leg["side"]
	var z: float = leg["z"]
	var p := global_transform * Vector3(s * (FOOT_OUT + 0.15), 0.0, z * FOOT_ALONG * 1.1)
	p.y = global_position.y + 0.02
	return p


func _pose_legs(delta: float, live: bool) -> void:
	var walking := live and state in [State.HUNT, State.GRAB, State.SWEEP, State.REAR, State.CLAMPED] and _power > 0.3
	var waking := state == State.WAKING
	if walking and _crawl > 0.05:
		_gait = fmod(_gait + delta * (0.8 + _crawl * 0.9), 1.0)
	elif not live and state in [State.HUNT, State.GRAB, State.SWEEP, State.STALL]:
		_gait = fmod(_gait + delta * 0.9 * clampf(_crawl / DRAG_SPEED, 0.0, 1.0), 1.0)
	var stepping := [false, false]
	for leg in _legs:
		if float(leg["step"]) >= 0.0:
			stepping[int(leg["group"])] = true
	for leg in _legs:
		var foot: Vector3 = leg["foot"]
		if state == State.DORMANT or (waking and _t < 1.8):
			foot = _fold_target(leg) if delta <= 0.0 else foot.lerp(_fold_target(leg), clampf(delta * 8.0, 0.0, 1.0))
			leg["step"] = -1.0
		elif waking:
			# Unfolding: each foot reaches out and down to its place on the floor.
			var w := clampf((_t - 1.8) / 0.8, 0.0, 1.0)
			var to := _rest_target(leg)
			foot = _fold_target(leg).lerp(to, smoothstep(0.0, 1.0, w)) + Vector3(0.0, 0.35 * sin(w * PI), 0.0)
			leg["step"] = -1.0
		elif not walking or _power < 0.3:
			if delta > 0.0:
				foot = foot.lerp(_limp_target(leg), clampf(delta * 3.0, 0.0, 1.0))
			else:
				foot = _limp_target(leg)
			leg["step"] = -1.0
		elif state == State.REAR and float(leg["z"]) < -0.1 and _pitch > 0.15:
			# The front pair paw the air.
			var paw := _body.global_transform * Vector3(float(leg["side"]) * 0.95, -0.2 + 0.15 * sin(_t * 12.0), float(leg["z"]) - 0.55)
			foot = foot.lerp(paw, clampf(delta * 10.0, 0.0, 1.0))
			leg["step"] = -1.0
		else:
			var step: float = leg["step"]
			if step >= 0.0:
				step += delta / (STEP_TIME / (1.0 + 0.15 * float(level)))
				var t := clampf(step, 0.0, 1.0)
				var from: Vector3 = leg["from"]
				var to: Vector3 = leg["to"]
				foot = from.lerp(to, t) + Vector3(0.0, STEP_LIFT * sin(t * PI), 0.0)
				if t >= 1.0:
					step = -1.0
					foot = to
				leg["step"] = step
			else:
				var rest := _rest_target(leg)
				var g: int = leg["group"]
				var far := Vector2(foot.x - rest.x, foot.z - rest.z).length()
				if far > STEP and not stepping[1 - g] or far > STEP * 2.2:
					leg["from"] = foot
					leg["to"] = rest
					leg["step"] = 0.0
					stepping[g] = true
				elif foot.y > global_position.y + 0.05:
					# Down onto the floor (after a paw or the stall).
					foot = foot.lerp(Vector3(foot.x, global_position.y, foot.z), clampf(delta * 10.0, 0.0, 1.0))
		leg["foot"] = foot
		_ik_leg(leg)


## Two-bone IK, the knee bent up and out.
func _ik_leg(leg: Dictionary) -> void:
	var s: float = leg["side"]
	var hip: Vector3 = _body.global_transform * Vector3(s * HIP.x, HIP.y, float(leg["z"]))
	var foot: Vector3 = leg["foot"]
	var to := foot - hip
	var d := clampf(to.length(), 0.05, THIGH + SHIN - 0.001)
	var dir := to.normalized() if to.length_squared() > 0.000001 else Vector3.DOWN
	var cos_a := clampf((THIGH * THIGH + d * d - SHIN * SHIN) / (2.0 * THIGH * d), -1.0, 1.0)
	var a := acos(cos_a)
	var outward := global_basis.x * s
	var pole := outward * 0.5 + Vector3.UP * 1.0
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 0.0001:
		perp = Vector3.UP - dir * dir.y
	perp = perp.normalized()
	var knee := hip + dir * (THIGH * cos_a) + perp * (THIGH * sin(a))
	var tip := knee + (foot - knee).normalized() * SHIN
	(leg["thigh"] as Node3D).global_transform = _segment(hip, knee)
	# The shin's mesh runs from its foot (y 0) up to the knee.
	(leg["shin"] as Node3D).global_transform = _segment(tip, knee)


## A frame at `a` whose +Y points at `b`.
static func _segment(a: Vector3, b: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x, y, z), a)


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

## A low electric hum while it has power, whining up as it moves -- the only
## machine sound in the dungeon, so that when it dies the silence is felt.
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
		_:
			m.albedo_color = Color(0.3, 0.3, 0.3)
	_mats[key] = m
	return m


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
