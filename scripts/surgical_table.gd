extends CharacterBody3D

## The surgical table (2026-10-21; stationary under a ceiling claw, note 95; the
## claw a hunter that carries its victims to the table, note 96; on an overhead
## GANTRY that crosses the whole hall, note 99): the machine in the surgery
## (surgery.gd) that was to make the dead prisoners bionic. It cannot be killed
## -- a blow on it only rings off the iron. It is switched off from the CONTROL
## ROOM (surgery_control.gd: kick the door in, kill the surgeon, throw the
## master lever), and only there (note 99: "control room only").
##
## The table itself never moves: a riveted iron slab on a base of gears and
## pistons (models/surgery/table.glb), in the middle of the hall over the
## disposal shaft, a dead prisoner strapped to it with a mechanical arm half
## fitted. A player walking in wakes it: the restraints snap open and throw the
## body off, and the claw comes down off its gantry and hunts the hall.
##
## THE GANTRY (note 99, the user: "base of claw should move on the X and Y axis
## across the whole room"): an overhead crane. A bridge girder spans the hall
## between the side walls, its end carriages running on runway girders along
## those walls (Z); along the bridge runs the trolley (X) -- the old ceiling
## ring, now the hub the arm hangs from. Each axis is driven on its own with its
## own acceleration and top speed (`_drive`), as a real crane's are, so a
## diagonal chase bends; the heavy bridge is slower to start and stop than the
## trolley. The arm telescopes straight down from the trolley to the wrist and
## SWINGS under it -- a stiff, damped pendulum driven by the trolley's
## acceleration (`_swing`) -- so it lags behind a start, overshoots a stop and
## settles, instead of sliding about rigidly.
##
## It FOLLOWS the nearest player (the trolley over them, the claw hanging above
## the bookshelves) and SLAMS down to GRAB them. The slam (State.REAR) is made
## hard to get away from (the user: "make it pause to drop much later"): it
## draws up (WIND), keeps following them the whole time it is drawn up
## (TRACK), and only at the very end locks on where they are (LOCK -- a brief
## shudder, the parry cue) and drops (DROP, accelerating like a weight). Where
## it lands the floor cracks, dust and stone chips burst out, sparks fly, a flash
## lights the stone and the view shakes (`_impact_fx`). Caught, they are CARRIED
## to the table and STRAPPED down; they can STRUGGLE free (player.gd `restrain`
## / `struggles`). Missed, the claw is stuck in the floor a moment and tears
## itself free in a spray of grit.

signal depowered(cause: StringName)
signal woke

const SKELETON := preload("res://models/ossuary_skeleton_rigged.glb")
const CUFF_MODEL := preload("res://models/surgery/cuff.glb")
const ITEM_DROP := preload("res://scripts/item_drop.gd")
const TABLE_MODEL := preload("res://models/surgery/table.glb")
const RING_MODEL := preload("res://models/surgery/ring.glb")
const CLAW_MODEL := preload("res://models/surgery/claw.glb")
const SEGMENT_MODEL := preload("res://models/surgery/segment.glb")
const GIRDER_MODEL := preload("res://models/surgery/girder.glb")
const TRUCK_MODEL := preload("res://models/surgery/endtruck.glb")
const FX_DUST := preload("res://textures/surgery_fx_dust.png")
const FX_CRACK := preload("res://textures/surgery_fx_crack.png")
const FX_CHIP := preload("res://textures/surgery_fx_chip.png")

## (GRAB, SWEEP, CLAMPED and STALL are gone with the levers and the clamp; kept
## so the numbering of the rest is what it was.)
enum State { DORMANT, WAKING, HUNT, GRAB, SWEEP, REAR, CLAMPED, STALL, DYING, DEAD, CARRY, STRAP }

## --- The table -------------------------------------------------------------------
## The slab's top off the floor (the model is 3.0 long along Z, 1.48 wide).
const TOP := 1.2
const TABLE_SIZE := Vector3(1.48, 1.2, 3.0)
## Kept for the sandbox, which reads it.
const RADIUS := 1.6
const CORE_AT := Vector3(0.52, 0.55, 0.0)
const CORE_COLOUR := Color(0.55, 0.9, 1.0)
const EYE_COLOUR := Color(1.0, 0.32, 0.12)

## --- The gantry (the room's frame: the hall's middle on the floor) ---------------
## The bridge girder's middle, the trolley (the old ring, smaller) under it, and
## the arm's root under the trolley. surgery.gd's runways sit under the bridge's
## end carriages at +-`rail_x`.
const BRIDGE_Y := 7.2
const TROLLEY_TOP := 6.95
const TROLLEY_SCALE := 0.5
const ROOT_Y := 6.25
## Bridge girder sections (girder.glb is 4.4 m) and the end carriages
## (endtruck.glb, 3 m along Z, its wheels on the runway at RUNWAY_TOP).
const GIRDER_LEN := 4.4
const RUNWAY_TOP := 6.75
## The drives: the trolley (along X) quicker than the heavy bridge (along Z).
## Top speed by anger (`level`), acceleration fixed.
const TROLLEY_SPEED: Array[float] = [5.0, 5.6, 6.2, 6.8, 7.4]
const BRIDGE_SPEED: Array[float] = [4.0, 4.5, 5.0, 5.5, 6.0]
const TROLLEY_ACCEL := 9.0
const BRIDGE_ACCEL := 6.0
## The swing of the hanging arm: its natural rate (rad/s) and damping ratio,
## and how far a hard start or stop throws it (m per m/s^2), at most SWING_MAX.
const SWING_RATE := 3.4
const SWING_DAMP := 0.32
const SWING_GAIN := 0.075
const SWING_MAX := 1.2
## The arm: segments about this long, this thick (segment.glb is 1 m, 0.13 m).
const SEG_LEN := 0.9
const SEG_MAX := 10
const SEG_THICK := 2.4
## The claw: wrist to fingertips, and its scale.
const CLAW_LEN := 1.55
const CLAW_SCALE := 0.95
## Hoisting and paying out the arm (m/s).
const HOIST_SPEED := 3.2
## Asleep: the claw drawn right up under the trolley, over the table.
const FOLD_LEN := 0.3
## Following: the wrist this high over the floor under it (the fingertips,
## CLAW_LEN under it, clear the 3.9 m bookshelves -- note 100), the trolley this
## far back toward the table from them.
const HOVER_Y := 5.6
const HOVER_BACK := 0.8
## A little ahead of them: their velocity times this.
const LEAD := 0.25

## --- Pace, by anger (`level` 0..4; it rises with each player it carries off and
## each time one breaks free) -----------------------------------------------------
const LEVEL_MAX := 4

## --- The slam (State.REAR) -------------------------------------------------------
## Over them within this (horizontally) and it may slam.
const SLAM_OVER := 1.6
## WIND: drawn up this much over WIND_TIME, still following. TRACK: held drawn
## up, still following -- the long part. LOCK: the aim fixed where they are, a
## shudder, the parry cue. DROP: down, accelerating, onto the spot.
const WIND_RISE := 0.7
const WIND_TIME := 0.35
const TRACK_TIME: Array[float] = [0.5, 0.45, 0.4, 0.35, 0.3]
const LOCK_TIME: Array[float] = [0.16, 0.15, 0.14, 0.13, 0.12]
const DROP_TIME := 0.17
## Missed: stuck in the floor this long (parried: PARRY_STUCK), torn free and
## drawn up over PULL_TIME.
const REAR_STUCK := 1.3
const PARRY_STUCK := 3.0
const PULL_TIME := 0.5
## A player this near where it lands is GRABBED; nearer than SHAKE_RADIUS is
## thrown down by the blow.
const GRAB_RADIUS := 1.3
const SHAKE_RADIUS := 2.6
const GRAB_DAMAGE := 12.0
## Between one slam ending and the next beginning (note 100: was 2.6 .. 1.6 s,
## the user wanted more time between its attacks).
const REAR_COOLDOWN: Array[float] = [5.0, 4.5, 4.0, 3.6, 3.2]

## --- Carried and strapped down ----------------------------------------------------
const CARRY_SPEED := 5.0
## Carried with the wrist this high, held this far down the claw (`CARRY_GRIP`,
## of CLAW_LEN): the body's feet then clear the 3.9 m shelves as the gantry
## runs it over them (note 100; at 4.6 and 0.75 they swept through them).
const CARRY_Y := 5.9
const CARRY_GRIP := 0.45
## The struggles it takes to break free: carried, and strapped down (more as it
## angers).
const CARRY_BREAK := 8
const STRAP_BREAK: Array[int] = [12, 14, 16, 18, 20]
## Strapped: the claw works on them every OPERATE_EVERY s for OPERATE_DAMAGE.
const OPERATE_EVERY := 0.9
const OPERATE_DAMAGE: Array[float] = [6.0, 7.0, 8.0, 9.0, 10.0]
## Let go: thrown off this hard, and the claw holds off this long.
const THROW := 6.5
const RELEASE_REST := 3.5

## --- The floor's scars ----------------------------------------------------------
## Crack decals left where it lands: this many at most, fading after DECAL_LIFE.
const DECAL_MAX := 6
const DECAL_LIFE := 9.0

var room: Node3D
## Where the table stands, and which way.
var home := Vector3.ZERO
var home_yaw := 0.0
## The hall's inner half width (room frame), and where the runways run.
var bound := 12.6
var rail_x := 12.1

var state: State = State.DORMANT
var level := 0
## The table's light (the surgery's lamp and the control room read it).
var core_glow := 0.0
## The axe treats a body with this set as down (axe.gd `_is_down`).
var _dying := false

var _t := 0.0
var _target: Node3D = null
var _next_rear := 0.0
var _hit_done := false
var _parried := false
var _stun_until := 0.0
var _victim: Node3D = null
var _next_cut := 0.0
var _strap_prompt: Interact.Prompt

## The gantry, in the room's frame: the trolley's place over the floor (x, z),
## its velocity, where it is driven to; the arm's length under the root and the
## length wanted; the swing of the wrist from under the trolley and its rate.
var _b := Vector2.ZERO
var _bv := Vector2.ZERO
var _b_goal := Vector2.ZERO
var _b_speed := 1.0
var _len := FOLD_LEN
var _len_goal := FOLD_LEN
var _hoist := HOIST_SPEED
var _o := Vector2.ZERO
var _ov := Vector2.ZERO
var _swing_lock := 0.0
## The wrist and the way the claw points, room frame (from the above, each tick).
var _w := Vector3(0.0, ROOT_Y - FOLD_LEN, 0.0)
var _axis := Vector3.DOWN
## The slam: where it comes down (room frame, on the floor of whoever it is
## after), and how far the arm pays out to get there.
var _to := Vector3.ZERO
var _drop_len := 4.0

## Pose, eased.
var _power := 0.0
var _roll := 0.0
var _spin := 0.0
var _flex := 0.0

## Nodes.
var _body: Node3D
var _claw_mats: Array = []
var _core_light: OmniLight3D
var _eye_light: OmniLight3D
var _lamp: SpotLight3D
var _power_mats: Array = []
var _ring: Node3D
var _bridge: Node3D
var _claw: Node3D
var _segs: Array[MeshInstance3D] = []
var _seg_mesh: Mesh
var _cuffs: Array[Node3D] = []
var _claw_box: StaticBody3D
var _prisoner: Node3D
var _prisoner_rest := Transform3D()
var _audio: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _phase := Vector3.ZERO
var _decals: Array[Decal] = []

static var _mats := {}


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
	shape.size = TABLE_SIZE
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, TABLE_SIZE.y * 0.5, 0.0)
	add_child(cs)
	_build_body()
	_build_gantry()
	_build_arm()
	_build_audio()
	_strap_prompt = Interact.prompt("Struggle free", Vector3(0.0, TOP + 1.2, 0.0))
	add_child(_strap_prompt)
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
	# The restraints on the top: wrists by the head, ankles by the foot; each
	# swings open about its hinge (`rotation.z`).
	var cuff_at := [Vector3(-0.3, 0.0, -0.52), Vector3(0.3, 0.0, -0.52), Vector3(-0.13, 0.0, 0.92), Vector3(0.13, 0.0, 0.92)]
	for c: Vector3 in cuff_at:
		var hinge := Node3D.new()
		hinge.name = "Restraint"
		var side := signf(c.x)
		hinge.position = Vector3(c.x + side * 0.12, TOP + 0.01, c.z)
		_body.add_child(hinge)
		var cuff: Node3D = CUFF_MODEL.instantiate()
		cuff.position = Vector3(-side * 0.13, 0.0, 0.0)
		hinge.add_child(cuff)
		_shadows(cuff)
		_cuffs.append(hinge)
	_build_prisoner()


## The bridge (girder sections end to end across the hall, an end carriage at
## each end on the runways) and the trolley (the old ceiling ring) on it. Placed
## in world space every frame from the room's frame (`_pose_arm`).
func _build_gantry() -> void:
	_bridge = Node3D.new()
	_bridge.name = "GantryBridge"
	_bridge.top_level = true
	add_child(_bridge)
	var count := maxi(ceili(rail_x * 2.0 / GIRDER_LEN), 1)
	var span := float(count) * GIRDER_LEN
	for i in count:
		var g: Node3D = GIRDER_MODEL.instantiate()
		g.position = Vector3(-span * 0.5 + GIRDER_LEN * (float(i) + 0.5), BRIDGE_Y, 0.0)
		# Every other section turned end for end: the rivets do not repeat.
		g.rotation.y = PI * float(i % 2)
		g.scale = Vector3(rail_x * 2.0 / span, 1.0, 1.0)
		g.position.x *= rail_x * 2.0 / span
		_bridge.add_child(g)
		_shadows(g)
	for s: float in [-1.0, 1.0]:
		var truck: Node3D = TRUCK_MODEL.instantiate()
		truck.position = Vector3(s * rail_x, RUNWAY_TOP, 0.0)
		_bridge.add_child(truck)
		_shadows(truck)
	_ring = RING_MODEL.instantiate()
	_ring.name = "Trolley"
	_ring.top_level = true
	add_child(_ring)
	_shadows(_ring)
	_power_glow(_ring, 0.45)
	# Its lamp: a cold beam straight down from the trolley -- the light that
	# hunts the hall, on the machine's own circuit.
	_lamp = SpotLight3D.new()
	_lamp.name = "TrolleyLamp"
	_lamp.light_color = Color(0.85, 0.95, 1.0)
	_lamp.light_energy = 0.0
	_lamp.spot_range = 9.0
	_lamp.spot_angle = 28.0
	_lamp.spot_attenuation = 0.9
	_lamp.light_specular = 0.2
	_lamp.shadow_enabled = false
	_lamp.top_level = true
	add_child(_lamp)


## The arm's segments and the claw hanging from the trolley.
func _build_arm() -> void:
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
		grade(seg)
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
	_claw_mats = glow(claw_model, 0.3)
	# Its glow, the only light that travels with it: the claw is seen coming by
	# its own red light on the stone.
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


## --- One palette (note 100) ---------------------------------------------------------
## Each Higgsfield piece came with its own idea of colour: the kit's mean albedo
## ran from 0.08 to 0.19 in luminance and 0.12 to 0.70 in saturation, so pieces
## side by side looked dropped in from different sets. `grade` pulls each
## material's mean colour GRADE_PULL of the way toward GRADE_TARGET (the kit's own
## mean, a little desaturated), per channel, through its albedo_color -- the
## texture's detail is untouched. Once per material (they are shared by every
## copy of a piece), before any glow duplicate is made from it.
const GRADE_TARGET := Color(0.17, 0.135, 0.105)
const GRADE_PULL := 0.65
static var _graded := {}


static func grade(n: Node) -> void:
	var nodes := n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		nodes.append(n)
	for node in nodes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null or m.albedo_texture == null or _graded.has(m.get_instance_id()):
				continue
			_graded[m.get_instance_id()] = true
			var mean := _mean_colour(m.albedo_texture)
			var tint := Color(1.0, 1.0, 1.0)
			for c in 3:
				var want: float = GRADE_TARGET[c] / maxf(mean[c], 0.01)
				tint[c] = clampf(lerpf(1.0, want, GRADE_PULL), 0.6, 1.7)
			m.albedo_color = m.albedo_color * tint


## A texture's mean colour, from a 16 x 16 reduction of its image.
static func _mean_colour(t: Texture2D) -> Color:
	var img := t.get_image()
	if img == null:
		return GRADE_TARGET
	if img.is_compressed():
		img.decompress()
	img.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0.0, 0.0, 0.0, 0.0)
	for y in 16:
		for x in 16:
			sum += img.get_pixel(x, y)
	return sum / 256.0


static func _shadows(n: Node) -> void:
	grade(n)
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


## Lights a Higgsfield kit piece with its own albedo: the lamps and the green
## bottles are the bright parts of the generated pictures and the iron and wood
## the dark ones, so the picture itself is the emission map. Materials are
## duplicated once per source and energy, so every copy shares them.
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
## forearm gone and a mechanical arm bolted to the elbow -- the work left half done.
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
	var found := model.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		var sk := found[0] as Skeleton3D
		var fore := sk.find_bone(&"forearm.R")
		if fore >= 0:
			sk.set_bone_pose_scale(fore, Vector3.ONE * 0.001)
			var att := BoneAttachment3D.new()
			att.bone_name = "upper_arm.R"
			sk.add_child(att)
			load("res://scripts/surgery.gd").attach_prosthetic(att)
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

## As built: the trolley parked over the table, the claw drawn up under it, the
## prisoner strapped down.
func _sleep_pose() -> void:
	state = State.DORMANT
	_dying = false
	global_position = home
	global_rotation = Vector3(0.0, home_yaw, 0.0)
	_power = 0.0
	_b = Vector2.ZERO
	_bv = Vector2.ZERO
	_b_goal = Vector2.ZERO
	_len = FOLD_LEN
	_len_goal = FOLD_LEN
	_o = Vector2.ZERO
	_ov = Vector2.ZERO
	_update_wrist()
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
	if _victim != null:
		_let_go(_now(), false)
	level = 0
	_sleep_pose()


## A save that had it switched off: the claw lying where it fell (`at`, world,
## the wrist), the trolley over it.
func set_dead_now(at: Vector3, _yaw: float) -> void:
	state = State.DEAD
	_dying = true
	global_position = home
	global_rotation = Vector3(0.0, home_yaw, 0.0)
	_power = 0.0
	_throw_prisoner(true)
	for c in _cuffs:
		c.rotation.z = 1.9 * signf(c.position.x)
	var local: Vector3 = room.to_local(at) if room != null else Vector3.ZERO
	if Vector2(local.x, local.z).length() < 2.0:
		local = Vector3(2.6, 0.0, 1.0)
	_b = Vector2(local.x, local.z)
	_bv = Vector2.ZERO
	_b_goal = _b
	_o = Vector2(0.35, 0.2)
	_len = ROOT_Y - CLAW_LEN * 0.95
	_len_goal = _len
	_update_wrist()
	_apply_pose(0.0)


## Where its claw lies, for the save (world).
func rest_point() -> Vector3:
	return room.to_global(_w) if room != null else global_position


func rest_yaw() -> float:
	return 0.0


func is_depowered() -> bool:
	return state == State.DEAD or state == State.DYING


## The master lever in the control room (surgery_control.gd): the power cut.
func power_off(cause: StringName = &"control") -> void:
	if state == State.DORMANT:
		_enter(State.HUNT)
	_shutdown(cause)


func _anger() -> void:
	level = mini(level + 1, LEVEL_MAX)


func _wake() -> void:
	if state != State.DORMANT:
		return
	_enter(State.WAKING)
	woke.emit()


func _shutdown(cause: StringName) -> void:
	if is_depowered():
		return
	if _victim != null:
		_let_go(_now(), true)
	_enter(State.DYING)
	_dying = true
	print("[surgery] the table is depowered (%s)" % cause)
	depowered.emit(cause)


func _enter(s: State) -> void:
	state = s
	_t = 0.0
	_hit_done = false


# --- Each tick ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if room == null:
		return
	var now := _now()
	_t += delta
	match state:
		State.DORMANT:
			if _intruder() != null:
				_wake()
			_b_goal = Vector2.ZERO
			_len_goal = FOLD_LEN
		State.WAKING:
			# The arm pays out of the trolley, the claw flexing.
			_b_goal = Vector2.ZERO
			_len_goal = lerpf(FOLD_LEN, ROOT_Y - HOVER_Y, clampf((_t - 1.4) / 1.2, 0.0, 1.0))
			_hoist = 2.0
			if _t >= 3.0:
				_enter(State.HUNT)
				# The first slam a while after it wakes (note 100).
				_next_rear = now + 2.5
		State.HUNT:
			_hunt(now)
		State.REAR:
			_slam(now)
		State.CARRY:
			_carry(now)
		State.STRAP:
			_strap(now)
		State.DYING:
			_die_out(delta)
		State.DEAD:
			pass
		_:
			_enter(State.HUNT)
	if state != State.DEAD:
		_drive(delta)
		_swing(delta)
		_len = move_toward(_len, _len_goal, _hoist * delta)
		_update_wrist()
	_hold_victim()


## The two drives: each axis toward its goal at its own top speed and
## acceleration, braking to arrive (a crane's motors, not a slide).
func _drive(delta: float) -> void:
	var lim := Vector2(rail_x - 0.4, bound - 0.6)
	_b_goal = Vector2(clampf(_b_goal.x, -lim.x, lim.x), clampf(_b_goal.y, -lim.y, lim.y))
	var vmax := Vector2(TROLLEY_SPEED[level], BRIDGE_SPEED[level]) * _b_speed
	var acc := Vector2(TROLLEY_ACCEL, BRIDGE_ACCEL) * maxf(_b_speed, 0.6)
	var before := _bv
	for i in 2:
		var d := _b_goal[i] - _b[i]
		# The speed it can still stop from in the distance left.
		var want := signf(d) * minf(vmax[i], sqrt(2.0 * acc[i] * absf(d)))
		_bv[i] = move_toward(_bv[i], want, acc[i] * delta)
		_b[i] += _bv[i] * delta
	_last_accel = (_bv - before) / maxf(delta, 0.0001)


var _last_accel := Vector2.ZERO


## The hanging arm swings: a damped spring pulled back under the trolley, thrown
## the other way by the trolley's acceleration. Locked (`_swing_lock`) while it
## strikes, so the drop goes where it was aimed.
func _swing(delta: float) -> void:
	var w := SWING_RATE * (1.0 + 2.0 * _swing_lock)
	var acc := -_o * w * w - _ov * 2.0 * SWING_DAMP * w - _last_accel * SWING_GAIN * w * w * (1.0 - _swing_lock)
	_ov += acc * delta
	_o += _ov * delta
	if _o.length() > SWING_MAX:
		_o = _o.normalized() * SWING_MAX
		_ov *= 0.5


## The wrist under the trolley, swung out, and the way the claw points: along
## the arm, from the root to the wrist.
func _update_wrist() -> void:
	var root := Vector3(_b.x, ROOT_Y, _b.y)
	_w = Vector3(_b.x + _o.x, ROOT_Y - _len, _b.y + _o.y)
	var d := _w - root
	_axis = d.normalized() if d.length() > 0.2 else Vector3.DOWN


## The nearest standing player inside the hall (at any height: on the floor, in
## the lift, on the landing), or null. Not one already held.
func _intruder() -> Node3D:
	if Sandbox.enemies_passive:
		return null
	var best: Node3D = null
	var best_d := INF
	for p in Coop.all():
		var n := p as Node3D
		if n == null or n.get("_dead") == true or (n.has_method("is_hidden") and n.is_hidden()) or n == _victim:
			continue
		if n.get("in_cutscene") == true:
			continue
		var local: Vector3 = room.to_local(n.global_position)
		if absf(local.x) > bound + 1.2 or absf(local.z) > bound + 1.2 or local.y < -1.0 or local.y > 5.5:
			continue
		var d := n.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## Following: the trolley over them, a little ahead of where they are going and
## a little back toward the table, the claw hanging over the shelves; over them
## and ready, down it comes.
func _hunt(now: float) -> void:
	_target = _intruder()
	_hoist = HOIST_SPEED
	_b_speed = 1.0
	if _target == null or now < _stun_until:
		if _target == null:
			# Nobody in the hall: back over the table, to wait.
			_b_goal = Vector2.ZERO
			_len_goal = ROOT_Y - HOVER_Y - 0.4
		return
	var p := _aim_point(_target, LEAD)
	var flat := Vector2(p.x, p.z)
	var back := flat.normalized() * HOVER_BACK if flat.length() > HOVER_BACK + 0.5 else Vector2.ZERO
	_b_goal = flat - back
	# Over a player up on the lift or the landing, it hangs over them there.
	var floor_y := maxf(p.y, 0.0)
	_len_goal = clampf(ROOT_Y - (floor_y + HOVER_Y), FOLD_LEN, ROOT_Y - 1.0)
	var over := Vector2(_w.x - p.x, _w.z - p.z).length()
	if over < SLAM_OVER and now >= _next_rear:
		_parried = false
		_enter(State.REAR)


## Where a player is (room frame), `lead` seconds ahead along their velocity.
func _aim_point(n: Node3D, lead: float) -> Vector3:
	var p: Vector3 = room.to_local(n.global_position)
	var vel: Vector3 = Vector3.ZERO
	if n.get("velocity") != null:
		vel = n.get("velocity")
	var v: Vector3 = room.global_basis.inverse() * vel
	return p + Vector3(v.x, 0.0, v.z) * lead


func _chest(p: Node3D) -> Vector3:
	return p.global_position + Vector3(0.0, 1.05, 0.0)


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


# --- The slam ----------------------------------------------------------------------

## WIND (drawn up), TRACK (held up, still following them), LOCK (the aim fixed,
## a shudder, the parry cue), DROP (down onto the spot), then stuck in the
## floor and torn free.
func _slam(now: float) -> void:
	var track: float = TRACK_TIME[level]
	var lock: float = LOCK_TIME[level]
	var lock_at := WIND_TIME + track
	var drop_at := lock_at + lock
	var land_at := drop_at + DROP_TIME
	var stuck_for := PARRY_STUCK if _parried else REAR_STUCK
	var hover_len := clampf(ROOT_Y - (_to.y + HOVER_Y), FOLD_LEN, ROOT_Y - 1.0)
	if _t < lock_at:
		# Still following, drawn up over them: the arm hauled in, the claw spread.
		if _target != null and is_instance_valid(_target):
			var p := _aim_point(_target, LEAD * 0.6)
			_to = Vector3(p.x, maxf(p.y, 0.0), p.z)
		_b_goal = Vector2(_to.x, _to.z)
		_b_speed = 1.15
		var wind := clampf(_t / WIND_TIME, 0.0, 1.0)
		hover_len = clampf(ROOT_Y - (_to.y + HOVER_Y), FOLD_LEN, ROOT_Y - 1.0)
		_len_goal = maxf(hover_len - WIND_RISE * (wind * wind * (3.0 - 2.0 * wind)), FOLD_LEN)
		_hoist = 4.0
		_swing_lock = 0.35
		_flex = wind
		return
	if _t < drop_at:
		# LOCKED: the aim fixed where they are now; the trolley brakes hard over
		# it, the swing is killed, the claw shudders -- and this is the cue.
		if not _hit_done:
			_hit_done = true
			if _target != null and is_instance_valid(_target):
				var p: Vector3 = room.to_local(_target.global_position)
				_to = Vector3(p.x, maxf(p.y, 0.0), p.z)
			for pl in Coop.all():
				if pl.has_method("parry_cue"):
					pl.call("parry_cue", self, lock + DROP_TIME)
		_b_goal = Vector2(_to.x, _to.z) - _o * 0.6
		_b_speed = 1.6
		_swing_lock = 1.0
		_flex = 1.0
		return
	if _t < land_at:
		# DROPPING: paid out with gravity's ease-in, straight onto the spot.
		var k := clampf((_t - drop_at) / DROP_TIME, 0.0, 1.0)
		_drop_len = ROOT_Y - (_to.y + CLAW_LEN * 0.95)
		var from := maxf(hover_len - WIND_RISE, FOLD_LEN)
		_len = lerpf(from, _drop_len, k * k)
		_len_goal = _len
		_swing_lock = 1.0
		_flex = 0.4
		return
	if _hit_done:
		_hit_done = false
		_len = _drop_len
		_len_goal = _drop_len
		_impact(now)
		if state != State.REAR:
			return
	if _t < land_at + stuck_for:
		# Stuck in the floor, wrenching at it.
		var wr := 0.05 * sin(_t * 31.0)
		_o = Vector2(wr, -wr) * 0.3
		_len_goal = _drop_len - absf(wr) * 2.0
		_hoist = 6.0
		_b_goal = _b
		return
	if _t < land_at + stuck_for + 0.05 and _flex < 2.0:
		# Torn free: grit and chips off the floor.
		_flex = 2.0
		_impact_fx(room.to_global(Vector3(_to.x, _to.y, _to.z)), 0.45)
	_len_goal = hover_len
	_hoist = absf(_drop_len - hover_len) / PULL_TIME + 0.5
	_swing_lock = 0.0
	_flex = 0.0
	if _t >= land_at + stuck_for + PULL_TIME:
		_next_rear = now + REAR_COOLDOWN[level]
		_enter(State.HUNT)


## Where it lands: whoever is under it is grabbed, everyone near thrown down,
## and the floor takes the blow (`_impact_fx`).
func _impact(now: float) -> void:
	var at := room.to_global(Vector3(_to.x, _to.y, _to.z))
	_impact_fx(at, 1.0)
	var caught: Node3D = null
	for p in Coop.all():
		var n := p as Node3D
		if n == null or n.get("_dead") == true or (n.has_method("is_hidden") and n.is_hidden()) \
				or (n.has_method("is_restrained") and n.is_restrained()):
			continue
		var flat := Vector2(n.global_position.x - at.x, n.global_position.z - at.z).length()
		var d := Vector3(n.global_position.x - at.x, (n.global_position.y - at.y) * 2.0, n.global_position.z - at.z).length()
		if n.get("_shake") != null and flat < 12.0:
			n.set("_shake", maxf(float(n.get("_shake")), 0.6 * (1.0 - flat / 12.0)))
		if d > SHAKE_RADIUS:
			continue
		var guarded: bool = n.has_method("is_blocking") and n.call("is_blocking")
		if d <= GRAB_RADIUS:
			if _strike(n, GRAB_DAMAGE):
				# Turned aside: it bites deep into the floor and is stuck longer.
				_parried = true
				_sparks(at + Vector3(0.0, 0.4, 0.0), Color(1.0, 0.85, 0.55), 24)
				continue
			if not guarded and caught == null and n.has_method("restrain"):
				caught = n
				continue
		if not guarded and n.has_method("knock_down"):
			n.call("knock_down", n.global_position - at, 5.5)
	if caught != null:
		_take(caught, now)


## The floor taking the blow at `at` (world, on the floor), `strength` 0..1: a
## crack decal (it stays a while), a burst of dust rolling out low, stone chips
## thrown up and out, sparks off the iron, a flash on the stone. Off with
## `Graphics.effects` but for the crack and a little dust.
func _impact_fx(at: Vector3, strength: float) -> void:
	if not is_inside_tree():
		return
	var parent := get_parent()
	var effects: bool = Graphics.effects
	if strength >= 0.9:
		_crack(at)
	_emit(parent, _dust_burst(strength, effects), at + Vector3(0.0, 0.25, 0.0), 2.6)
	if effects:
		_emit(parent, _chips(strength), at + Vector3(0.0, 0.1, 0.0), 1.8)
		_sparks(at + Vector3(0.0, 0.15, 0.0), Color(1.0, 0.7, 0.4), int(30.0 * strength))
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.78, 0.55)
		flash.light_energy = 3.2 * strength
		flash.omni_range = 6.0
		flash.shadow_enabled = false
		parent.add_child(flash)
		flash.global_position = at + Vector3(0.0, 0.6, 0.0)
		var tw := flash.create_tween()
		tw.tween_property(flash, "light_energy", 0.0, 0.22).set_ease(Tween.EASE_OUT)
		tw.tween_callback(flash.queue_free)


## The crack left in the flagstones, fading after DECAL_LIFE; the oldest goes
## when there are DECAL_MAX.
func _crack(at: Vector3) -> void:
	var d := Decal.new()
	d.texture_albedo = FX_CRACK
	d.size = Vector3(3.4, 1.2, 3.4)
	d.cull_mask = 1
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	get_parent().add_child(d)
	d.global_position = at
	d.global_rotation = Vector3(0.0, randf() * TAU, 0.0)
	_decals.append(d)
	if _decals.size() > DECAL_MAX:
		var old: Decal = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := d.create_tween()
	tw.tween_interval(DECAL_LIFE)
	tw.tween_property(d, "modulate:a", 0.0, 2.5)
	tw.tween_callback(_drop_decal.bind(d))


func _drop_decal(d: Decal) -> void:
	_decals.erase(d)
	if is_instance_valid(d):
		d.queue_free()


## A one-shot burst into `parent` at `at` (world), freed after `life` s.
func _emit(parent: Node, p: CPUParticles3D, at: Vector3, life: float) -> void:
	parent.add_child(p)
	p.global_position = at
	p.restart()
	get_tree().create_timer(life).timeout.connect(p.queue_free)


## Dust: the generated puff, billboards rolling out low along the floor in a
## ring and rising slowly, swelling and thinning out.
func _dust_burst(strength: float, effects: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = int((22.0 if effects else 6.0) * strength) + 2
	p.lifetime = 1.8
	p.explosiveness = 0.92
	p.lifetime_randomness = 0.35
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.5
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.1
	p.direction = Vector3(1.0, 0.15, 0.0)
	p.spread = 180.0
	p.flatness = 0.85
	p.initial_velocity_min = 2.5 * strength
	p.initial_velocity_max = 6.0 * strength
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.gravity = Vector3(0.0, 0.35, 0.0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -30.0
	p.angular_velocity_max = 30.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.5
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(0.35, 1.0))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.66, 0.58, 0.75))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.55, 0.5, 0.45, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(1.3, 1.3)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = FX_DUST
	m.disable_receive_shadows = true
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Stone chips: the generated chip, thrown up and out, tumbling, falling.
func _chips(strength: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = int(26.0 * strength) + 4
	p.lifetime = 1.1
	p.explosiveness = 1.0
	p.lifetime_randomness = 0.3
	p.direction = Vector3.UP
	p.spread = 62.0
	p.initial_velocity_min = 3.5 * strength
	p.initial_velocity_max = 8.5 * strength
	p.gravity = Vector3(0.0, -15.0, 0.0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.13)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.albedo_texture = FX_CHIP
	m.roughness = 0.95
	quad.material = m
	p.mesh = quad
	return p


# --- Carried to the table and strapped down -----------------------------------------

## `n` is in the claw.
func _take(n: Node3D, _now_: float) -> void:
	_victim = n
	n.call("restrain", self)
	var hud: Node = Coop.hud(n)
	if hud != null and hud.has_method("announce"):
		hud.call("announce", "Struggle!", "Mash attack / jump to break free")
	_enter(State.CARRY)
	_sparks(_chest(n), Color(1.0, 0.8, 0.5), 12)


func _victim_ok() -> bool:
	return _victim != null and is_instance_valid(_victim) and _victim.get("_dead") != true \
		and _victim.get("restrained_by") == self


## Up, then the gantry runs them across the hall to over the table.
func _carry(now: float) -> void:
	if not _victim_ok():
		_let_go(now, false)
		return
	if int(_victim.get("struggles")) >= CARRY_BREAK:
		_let_go(now, false)
		_anger()
		return
	_len_goal = ROOT_Y - CARRY_Y
	_hoist = 4.0
	_swing_lock = 0.0
	if _t >= 0.5:
		_b_goal = Vector2.ZERO
		_b_speed = CARRY_SPEED / TROLLEY_SPEED[level]
	if _t >= 0.6 and _b.length() < 0.3 and absf(_len - _len_goal) < 0.2:
		# Laid down on it, the cuffs shut.
		_victim.set("struggles", 0)
		_next_cut = now + 1.2
		_enter(State.STRAP)


## On the table: the claw over them works at them until they struggle free or
## die.
func _strap(now: float) -> void:
	if not _victim_ok():
		_let_go(now, true)
		return
	if int(_victim.get("struggles")) >= STRAP_BREAK[level]:
		for c in _cuffs:
			_sparks(c.global_position, Color(1.0, 0.8, 0.5), 6)
		_let_go(now, true)
		_anger()
		return
	_b_goal = Vector2.ZERO
	_len_goal = ROOT_Y - (TOP + 2.4 + 0.35 * sin(_t * 9.0))
	_hoist = 3.0
	if now >= _next_cut:
		_next_cut = now + OPERATE_EVERY
		_victim.call("take_damage", OPERATE_DAMAGE[level], Vector3.DOWN, self)
		_sparks(_chest(_victim) + Vector3(0.0, 0.3, 0.0), Color(1.0, 0.85, 0.6), 14)


## Places whoever it holds: in the claw, or flat on the table.
func _hold_victim() -> void:
	if _victim == null:
		_strap_prompt.visible = false
		return
	if not _victim_ok():
		_let_go(_now(), false)
		return
	match state:
		State.CARRY:
			var grip := room.to_global(_w + _axis * CLAW_LEN * CARRY_GRIP)
			_victim.global_position = grip - Vector3(0.0, 1.05, 0.0)
			_victim.set("restrain_view", Vector3(0.0, -18.0, 12.0 * sin(_t * 5.0)))
		State.STRAP:
			_victim.global_position = global_transform * Vector3(0.0, TOP + 0.02, 0.25)
			_victim.set("restrain_view", Vector3(1.25, 72.0, 4.0 * sin(_t * 13.0)))
	_strap_prompt.player = _victim
	_strap_prompt.visible = true


## Lets go of whoever it holds -- off the table's side if they were on it
## (`thrown`) -- and holds off a moment.
func _let_go(now: float, thrown: bool) -> void:
	var v := _victim
	_victim = null
	_strap_prompt.visible = false
	if v != null and is_instance_valid(v) and v.get("restrained_by") == self and v.has_method("release"):
		var side := global_basis.x * (1.0 if randf() < 0.5 else -1.0)
		var push := Vector3.ZERO
		if thrown or state == State.STRAP:
			v.global_position = global_position + side * 1.2 + Vector3(0.0, TOP + 0.1, 0.0)
			push = side * THROW + Vector3(0.0, 3.0, 0.0)
		v.call("release", push)
	_stun_until = now + 1.0
	_next_rear = now + RELEASE_REST
	if state in [State.CARRY, State.STRAP]:
		_enter(State.HUNT)


# --- Switched off -------------------------------------------------------------------

## The power gone: the drives coast to a stop, the hoist runs slack -- the claw
## falls, swinging, and crashes into the floor -- and every light dies.
func _die_out(delta: float) -> void:
	_b_goal = _b + _bv * 0.6
	_b_speed = 0.4
	_swing_lock = 0.0
	var fall := clampf((_t - 0.6) / 0.7, 0.0, 1.0)
	var floor_len := ROOT_Y - CLAW_LEN * 0.95
	if _t > 0.6:
		_hoist = 2.0 + 14.0 * fall
		_len_goal = floor_len
	if not _hit_done and _t > 0.6 and _len >= floor_len - 0.05:
		_hit_done = true
		_impact_fx(room.to_global(Vector3(_w.x, 0.0, _w.z)), 1.0)
		for p in Coop.all():
			var n := p as Node3D
			if n != null and n.get("_shake") != null and n.global_position.distance_to(room.to_global(_w)) < 16.0:
				n.set("_shake", maxf(float(n.get("_shake")), 0.6))
	_o += Vector2(sin(_t * 3.0), cos(_t * 2.3)) * 0.12 * delta * (1.0 - fall)
	if _t >= 3.2:
		_die_done()


func _die_done() -> void:
	_enter(State.DEAD)
	_dying = true
	# What it held: the core's crystals and the coins prised from the dead it
	# worked on.
	var at := _body.global_transform * (CORE_AT + Vector3(0.5, 0.0, 0.0))
	ITEM_DROP.spawn(get_parent(), at, &"gold_crystal", 2)
	ITEM_DROP.spawn(get_parent(), at + Vector3(0.0, 0.1, 0.0), &"coins", 40)


# --- Being hit ----------------------------------------------------------------------

## A blow on the table itself: iron rings, sparks fly. Nothing is hurt.
func take_damage(_amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
	if state == State.DEAD:
		return
	var at := global_position + Vector3(0.0, TOP + 0.1, 0.0) - from_direction * 0.9
	_ring_off(at, from_direction)


func _ring_off(at: Vector3, _dir_: Vector3) -> void:
	if state == State.DEAD:
		return
	_sparks(at, Color(1.0, 0.85, 0.55), 10)
	if state == State.DORMANT:
		_wake()


## Too heavy to shove.
func apply_knockback(_impulse: Vector3, _stun_time := 0.0) -> void:
	pass


func _sparks(at: Vector3, colour: Color, amount: int) -> void:
	if not Graphics.effects or not is_inside_tree() or amount <= 0:
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
	match state:
		State.DORMANT:
			power = 0.0
		State.WAKING:
			power = clampf(_t / 1.2, 0.0, 1.0) * (0.6 + 0.4 * absf(sin(_t * 23.0))) if _t < 1.2 else 1.0
			for i in _cuffs.size():
				var open_at := 1.0 + float(i) * 0.12
				if _t >= open_at:
					var side := signf(_cuffs[i].position.x)
					var o := clampf((_t - open_at) / 0.09, 0.0, 1.0)
					_cuffs[i].rotation.z = side * (2.05 - 0.15 * sin(o * PI)) * o
			roll = 0.012 * sin(_t * 40.0) if _t < 1.6 else 0.0
			if _t >= 1.25 and _prisoner.get_parent() == _body:
				_throw_prisoner(false)
		State.DYING:
			power = clampf(1.0 - _t / 2.6, 0.0, 1.0) * (0.5 + 0.5 * absf(sin(_t * 31.0)))
			roll = 0.01 * sin(_t * 21.0) * clampf(1.0 - _t / 2.0, 0.0, 1.0)
		State.DEAD:
			power = 0.0
	if now < _stun_until:
		roll += 0.006 * sin(now * 40.0)
	if state == State.STRAP:
		for c in _cuffs:
			c.rotation.z = lerp_angle(c.rotation.z, 0.0, fast)
	elif state not in [State.DORMANT, State.WAKING, State.DEAD, State.DYING]:
		for c in _cuffs:
			c.rotation.z = lerp_angle(c.rotation.z, 2.05 * signf(c.position.x), k)
	_roll = lerpf(_roll, roll, k) if delta > 0.0 else roll
	_power = lerpf(_power, power, fast) if delta > 0.0 else power
	_body.transform = Transform3D(Basis(Vector3.FORWARD, _roll), Vector3.ZERO)
	var beat := 0.75 + 0.25 * pow(absf(sin(now * (2.6 + 0.5 * float(level)))), 6.0)
	core_glow = _power * beat
	_core_light.light_energy = 1.6 * core_glow
	_core_light.visible = core_glow > 0.02
	_eye_light.light_energy = (1.4 + 0.4 * float(level) / LEVEL_MAX) * _power * (1.0 + 0.8 * _flex)
	_eye_light.visible = _power > 0.03
	_lamp.light_energy = 2.2 * _power
	_lamp.visible = _power > 0.03
	for pair in _power_mats:
		(pair[0] as StandardMaterial3D).emission_energy_multiplier = float(pair[1]) * (0.3 + 0.7 * _power)
	# The claw reddens as it locks on.
	var hot := clampf(_flex, 0.0, 1.0) * _power if state == State.REAR else 0.0
	for m in _claw_mats:
		var mat: StandardMaterial3D = m
		mat.emission = Color.WHITE.lerp(Color(1.0, 0.35, 0.15), hot)
		mat.emission_energy_multiplier = 0.3 * (0.3 + 0.7 * _power) + 1.2 * hot
	_pose_arm(delta)


## The bridge, the trolley, the arm's segments and the claw.
func _pose_arm(delta: float) -> void:
	if room == null:
		return
	var rt := room.global_transform
	_bridge.global_transform = rt * Transform3D(Basis(), Vector3(0.0, 0.0, _b.y))
	_ring.global_transform = rt * Transform3D(Basis().scaled(Vector3.ONE * TROLLEY_SCALE), Vector3(_b.x, TROLLEY_TOP, _b.y))
	_lamp.global_transform = rt * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(_b.x, ROOT_Y - 0.2, _b.y))
	# The claw: its -Y along the arm, turning slowly at the wrist (fast while it
	# works on someone), its fingers trembling as it locks on.
	if delta > 0.0 and _power > 0.05:
		_spin += delta * (0.4 + (4.0 if state == State.STRAP else 0.0)) * _power
	var y := -_axis.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var shudder := 0.0
	if state == State.REAR and _flex >= 1.0:
		shudder = 0.05 * sin(_now() * 63.0)
	var claw_basis := Basis(x, y, z) * Basis(Vector3.UP, _spin + shudder) * Basis(Vector3.RIGHT, shudder)
	_claw.global_transform = rt * Transform3D(claw_basis, _w)
	# The arm: from the trolley straight down into the wrist, its segments as
	# many as the length needs -- it telescopes.
	var root := Vector3(_b.x, ROOT_Y + 0.35, _b.y)
	var total := root.distance_to(_w)
	var n := clampi(ceili(total / SEG_LEN), 1, SEG_MAX)
	for i in SEG_MAX:
		var seg := _segs[i]
		if i >= n or total < 0.05:
			seg.visible = false
			continue
		seg.visible = true
		var a := root.lerp(_w, float(i) / float(n))
		var b := root.lerp(_w, float(i + 1) / float(n))
		var d := b - a
		var len_ := d.length()
		var sy := d / len_
		var sref := Vector3.UP if absf(sy.y) < 0.95 else Vector3.RIGHT
		var sx := sref.cross(sy).normalized()
		var sz := sx.cross(sy).normalized()
		seg.global_transform = rt * Transform3D(Basis(sx * SEG_THICK, sy * (len_ * 1.08), sz * SEG_THICK), (a + b) * 0.5)


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


# --- The hum ----------------------------------------------------------------------------

## A low electric hum while it has power, whining up as the gantry runs -- the
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
	var motion := clampf(_bv.length() / 5.0 + absf(_len_goal - _len) * 0.5, 0.0, 1.0)
	var hum := 46.0 * (0.55 + 0.45 * _power)
	var whine := 180.0 + 260.0 * motion
	var amp := 0.22 * _power
	var w_amp := 0.05 * _power * motion
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


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
