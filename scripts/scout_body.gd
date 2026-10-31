extends Node3D

## The SCOUT's body (note 127): a hunched robot soldier in rusted, riveted
## brass and iron plate -- a domed helmet-head with two big round goggle eyes
## glowing the enforcer's cyan, brass ear gears, two antennae and a grimacing
## slot of a mouth; big rounded pauldrons, plated forearms and shins, gear
## joints at the elbows and knees, tassets over the hips; a ragged hooded mantle
## round the neck and shoulders; a long ringed spear with a barbed head held low
## in both hands.
##
## The model is models/scout.glb, made in Blender by tools/build_scout.py (note
## 134): ONE skinned mesh (three surfaces: the plate, the cloth, the glow) on a
## 31-bone rig, cached and shared by every scout, and the spear as a second
## mesh. Every plate is rigid on its bone (a machine of plates needs no soft
## skin); the mantle's hanging part is skinned to seven two-bone strands. That
## build's bones must stay exactly the rig laid out here in BONES.
##
## ANIMATED PROCEDURALLY, every frame (`_process`), nothing baked:
##   * the FEET are planted in the world and step: a foot lifts when it has
##     fallen a stride behind where it should be (or turned too far), swings
##     on an arc to where it will be needed when it lands -- re-aimed through
##     the swing as the body's speed changes -- and plants again. Starting,
##     stopping, turning on the spot, sidestepping and running all come out of
##     that one rule, and no foot ever slides on the floor;
##   * the LEGS reach them by two-bone IK; the pelvis lowers when a planted foot
##     would otherwise be out of reach; the heel rolls up as a foot trails;
##   * the PELVIS bobs, sways over the standing foot, drops on the swinging
##     side and turns with the stride; the chest turns against it;
##   * the body LEANS into acceleration and banks into turns;
##   * the SPEAR leads the arms: each pose and each move is a path for the
##     spear (in the chest's frame, so the torso carries it), the rear hand
##     holds it and the front hand slides along the shaft to wherever it can
##     reach -- in a thrust the shaft runs through it, as it does for a real
##     spearman;
##   * every pose value is followed by a damped spring, so the weight carries:
##     a blow overshoots a little and settles, a hit knocks the torso back and it
##     wobbles upright, nothing ever snaps;
##   * the HEAD looks the way a hunter looks: quick turns and holds (saccades),
##     the neck taking part of the turn and the chest a little more;
##   * it breathes, and now and then it shifts its weight or regrips;
##   * the MANTLE swings: each strand is a verlet chain hung from the shoulders,
##     drawn back to its drape, kept out of the body.
##
## The scout (scout.gd) only says what is going on: how fast it moves, how
## alert it is, which move it is in and how far through, what to look at.

const MODEL := "res://models/scout.glb"

enum { HIPS, SPINE, CHEST, NECK, HEAD, UARM_R, FARM_R, HAND_R, UARM_L, FARM_L, HAND_L,
	THIGH_R, SHIN_R, FOOT_R, THIGH_L, SHIN_L, FOOT_L, CLOAK0 }

## Name, parent, rest position (model space; every rest orientation identity).
## The head bone is "Head", not "head": skeleton_eyes.gd puts the skeletons'
## yellow eyes on any rig with a "head".
const BONES := [
	["Hips", -1, Vector3(0.0, 0.98, 0.0)],
	["Spine", HIPS, Vector3(0.0, 1.08, 0.0)],
	["Chest", SPINE, Vector3(0.0, 1.28, 0.0)],
	["Neck", CHEST, Vector3(0.0, 1.49, 0.0)],
	["Head", NECK, Vector3(0.0, 1.58, 0.0)],
	["UpperArmR", CHEST, Vector3(0.21, 1.45, 0.0)],
	["ForearmR", UARM_R, Vector3(0.21, 1.14, 0.0)],
	["HandR", FARM_R, Vector3(0.21, 0.85, 0.0)],
	["UpperArmL", CHEST, Vector3(-0.21, 1.45, 0.0)],
	["ForearmL", UARM_L, Vector3(-0.21, 1.14, 0.0)],
	["HandL", FARM_L, Vector3(-0.21, 0.85, 0.0)],
	["ThighR", HIPS, Vector3(0.11, 0.93, 0.0)],
	["ShinR", THIGH_R, Vector3(0.11, 0.50, 0.0)],
	["FootR", SHIN_R, Vector3(0.11, 0.08, 0.0)],
	["ThighL", HIPS, Vector3(-0.11, 0.93, 0.0)],
	["ShinL", THIGH_L, Vector3(-0.11, 0.50, 0.0)],
	["FootL", SHIN_L, Vector3(-0.11, 0.08, 0.0)],
]
const UPPER_ARM := 0.31
const FOREARM := 0.29
const THIGH := 0.43
const SHIN := 0.42
const ANKLE := 0.08
## From the palm's middle (on the shaft) to the wrist.
const GRIP_OFF := 0.07
## Hip, shoulder and spine offsets from their parents, as in BONES.
const HIP_SOCKET := Vector3(0.11, -0.05, 0.0)
const SHOULDER := Vector3(0.21, 0.17, 0.0)
const CHEST_REST := Vector3(0.0, 1.28, 0.0)

## The spear, in its own frame: the rear grip at the origin, the point along -Z.
const SPEAR_TIP := 1.80
const SPEAR_BUTT := 0.60
## The front hand slides along the shaft, between these (metres from the grip).
const SLIDE_MIN := 0.26
const SLIDE_MAX := 1.15
const SLIDE_SPEED := 3.0
## The pelvis rises or drops no faster than this, metres a second.
const HIPS_SPEED := 1.8

## The mantle: STRANDS strands of two bones, across the back from -120 to 120
## degrees (0 straight behind).
const STRANDS := 7
const STRAND_SPAN := 120.0

## The enforcer's crystal colour (enforcer.gd reads it off its material).
const EYE_COLOUR := Color(0.0, 0.91, 1.0)
const EYE_ENERGY := 3.2

# --- The poses -------------------------------------------------------------------
##
## grip: the rear (right) hand's place on the shaft, in the chest's frame. aim:
## the way the point goes, turned with the chest but level (its hunch is not
## the spear's: y is up and down in the world). twist: the chest turned on the
## pelvis (+ to its left). pelvis: the pelvis turned on the body. lean: the
## torso pitched forward. crouch: the pelvis dropped. side: the chest rolled.
## lead / back: the left foot forward and the right foot back of the hips
## (a spearman's stance, left foot leading); wide: the feet further apart; out:
## the rear foot turned out.

const P_GUARD := {"grip": Vector3(0.15, -0.30, -0.16), "aim": Vector3(-0.42, -0.5, -0.76),
	"roll": 0.0, "twist": -0.3, "pelvis": 0.14, "lean": 0.42, "crouch": 0.1, "side": 0.0,
	"lead": 0.1, "back": 0.06, "wide": 0.0, "out": 0.3}
const P_HUNT := {"grip": Vector3(0.17, -0.17, -0.02), "aim": Vector3(-0.24, -0.2, -0.95),
	"roll": 0.0, "twist": -0.36, "pelvis": 0.22, "lean": 0.32, "crouch": 0.14, "side": 0.0,
	"lead": 0.2, "back": 0.12, "wide": 0.05, "out": 0.5}
## Caught sight of them: up straight, the spear snatched up.
const P_SPOT := {"grip": Vector3(0.19, -0.08, 0.04), "aim": Vector3(-0.2, 0.12, -0.97),
	"roll": 0.0, "twist": -0.42, "pelvis": 0.2, "lean": 0.12, "crouch": 0.06, "side": 0.03,
	"lead": 0.18, "back": 0.12, "wide": 0.05, "out": 0.5}
const P_DRAW := {"grip": Vector3(0.22, -0.11, 0.24), "aim": Vector3(-0.12, 0.0, -0.99),
	"roll": 0.0, "twist": -0.62, "pelvis": 0.28, "lean": 0.24, "crouch": 0.16, "side": -0.03,
	"lead": 0.26, "back": 0.16, "wide": 0.06, "out": 0.6}
const P_EXTEND := {"grip": Vector3(0.02, -0.05, -0.4), "aim": Vector3(-0.04, -0.02, -1.0),
	"roll": 0.0, "twist": 0.06, "pelvis": -0.04, "lean": 0.44, "crouch": 0.18, "side": 0.02,
	"lead": 0.26, "back": 0.16, "wide": 0.06, "out": 0.6}
const P_DRAW_DEEP := {"grip": Vector3(0.24, -0.08, 0.3), "aim": Vector3(-0.1, 0.02, -0.99),
	"roll": 0.0, "twist": -0.78, "pelvis": 0.34, "lean": 0.2, "crouch": 0.19, "side": -0.05,
	"lead": 0.26, "back": 0.18, "wide": 0.07, "out": 0.65}
const P_LUNGE := {"grip": Vector3(-0.02, -0.03, -0.46), "aim": Vector3(0.0, -0.03, -1.0),
	"roll": 0.0, "twist": 0.2, "pelvis": -0.12, "lean": 0.58, "crouch": 0.23, "side": 0.03,
	"lead": 0.46, "back": 0.24, "wide": 0.07, "out": 0.7}
const P_DASH_WIND := {"grip": Vector3(0.22, -0.11, 0.28), "aim": Vector3(-0.05, -0.05, -1.0),
	"roll": 0.0, "twist": -0.52, "pelvis": 0.3, "lean": 0.54, "crouch": 0.23, "side": -0.03,
	"lead": 0.36, "back": 0.26, "wide": 0.05, "out": 0.65}
const P_DASH_RUN := {"grip": Vector3(0.14, -0.13, 0.08), "aim": Vector3(-0.04, -0.1, -1.0),
	"roll": 0.0, "twist": -0.3, "pelvis": 0.15, "lean": 0.7, "crouch": 0.14, "side": 0.0,
	"lead": 0.12, "back": 0.1, "wide": 0.0, "out": 0.3}
const P_DASH_STRIKE := {"grip": Vector3(0.0, -0.04, -0.44), "aim": Vector3(0.0, -0.02, -1.0),
	"roll": 0.0, "twist": 0.16, "pelvis": -0.08, "lean": 0.58, "crouch": 0.22, "side": 0.02,
	"lead": 0.48, "back": 0.26, "wide": 0.06, "out": 0.7}
## The swipe: wound back over the right side, swept low across the front at
## their legs with the hips leading, carried round to the left. Most of the
## sweep is the body turning (pelvis and chest, about 160 degrees); the spear
## turns only a little on it, so the whole is a real swing, not a whirl.
const P_SWIPE_WIND := {"grip": Vector3(0.3, -0.06, 0.08), "aim": Vector3(0.34, 0.15, -0.94),
	"roll": 0.35, "twist": -1.0, "pelvis": -0.42, "lean": 0.3, "crouch": 0.15, "side": -0.08,
	"lead": 0.3, "back": 0.2, "wide": 0.1, "out": 0.75}
const P_SWIPE_COIL := {"grip": Vector3(0.31, -0.04, 0.11), "aim": Vector3(0.42, 0.2, -0.9),
	"roll": 0.4, "twist": -1.1, "pelvis": -0.5, "lean": 0.28, "crouch": 0.17, "side": -0.1,
	"lead": 0.3, "back": 0.2, "wide": 0.1, "out": 0.75}
const P_SWIPE_MID := {"grip": Vector3(0.12, -0.22, -0.28), "aim": Vector3(0.1, -0.3, -0.95),
	"roll": 0.0, "twist": -0.1, "pelvis": 0.28, "lean": 0.42, "crouch": 0.2, "side": 0.0,
	"lead": 0.32, "back": 0.22, "wide": 0.1, "out": 0.75}
const P_SWIPE_FOLLOW := {"grip": Vector3(-0.15, -0.2, -0.18), "aim": Vector3(-0.36, -0.25, -0.9),
	"roll": -0.3, "twist": 0.86, "pelvis": 0.55, "lean": 0.38, "crouch": 0.19, "side": 0.1,
	"lead": 0.32, "back": 0.22, "wide": 0.1, "out": 0.6}
const P_SWIPE_SETTLE := {"grip": Vector3(-0.1, -0.22, -0.2), "aim": Vector3(-0.3, -0.3, -0.9),
	"roll": -0.2, "twist": 0.7, "pelvis": 0.45, "lean": 0.4, "crouch": 0.16, "side": 0.06,
	"lead": 0.28, "back": 0.2, "wide": 0.08, "out": 0.6}
## Thrown back by a parry or a heavy blow: the spear knocked up and out.
const P_REEL := {"grip": Vector3(0.24, 0.04, 0.12), "aim": Vector3(0.18, 0.8, -0.55),
	"roll": 0.2, "twist": 0.25, "pelvis": 0.1, "lean": -0.22, "crouch": 0.1, "side": 0.12,
	"lead": 0.2, "back": 0.3, "wide": 0.1, "out": 0.5}

## The bag pulled off a kneeling captive's head with the spear (note 128,
## boss_abduction.gd): the point reached out, slow, into the sack's crown (the
## scene pitches it at the head and walks the scout in or out until the point
## is there), then flicked up and back over its shoulder, the sack on the barbs.
const P_HOOK := {"grip": Vector3(0.06, -0.08, -0.3), "aim": Vector3(-0.05, 0.0, -1.0),
	"roll": 0.0, "twist": -0.08, "pelvis": 0.06, "lean": 0.3, "crouch": 0.12, "side": 0.0,
	"lead": 0.24, "back": 0.14, "wide": 0.05, "out": 0.5}
const P_FLICK := {"grip": Vector3(0.22, 0.06, 0.16), "aim": Vector3(0.12, 0.9, -0.42),
	"roll": 0.25, "twist": -0.5, "pelvis": 0.18, "lean": 0.02, "crouch": 0.06, "side": 0.06,
	"lead": 0.22, "back": 0.16, "wide": 0.06, "out": 0.5}

## Each move: [time, pose, ease into it]. Ease 0 smooth, 1 in (a strike,
## fastest as it arrives), 2 out (a draw or a settle, fastest as it leaves).
const MOVES := {
	&"spot": [[0.0, P_SPOT, 2], [0.38, P_SPOT, 0], [0.6, P_HUNT, 0]],
	&"tristab": [[0.0, P_HUNT, 0], [0.3, P_DRAW, 2], [0.4, P_EXTEND, 1], [0.5, P_EXTEND, 0],
		[0.66, P_DRAW, 2], [0.76, P_EXTEND, 1], [0.84, P_EXTEND, 0],
		[1.04, P_DRAW_DEEP, 2], [1.18, P_LUNGE, 1], [1.36, P_LUNGE, 0], [1.75, P_HUNT, 0]],
	&"dash": [[0.0, P_HUNT, 0], [0.42, P_DASH_WIND, 2], [0.5, P_DASH_WIND, 0],
		[0.66, P_DASH_RUN, 0], [0.98, P_DASH_STRIKE, 1], [1.25, P_DASH_STRIKE, 0], [1.7, P_HUNT, 0]],
	&"swipe": [[0.0, P_HUNT, 0], [0.48, P_SWIPE_WIND, 2], [0.56, P_SWIPE_COIL, 0],
		[0.68, P_SWIPE_MID, 1], [0.8, P_SWIPE_FOLLOW, 2], [1.0, P_SWIPE_SETTLE, 0], [1.45, P_HUNT, 0]],
	&"unhood": [[0.0, P_GUARD, 0], [0.6, P_HOOK, 2], [0.95, P_HOOK, 0], [1.2, P_FLICK, 1],
		[1.5, P_FLICK, 0], [2.3, P_GUARD, 0]],
}

# --- What the scout tells it (scout.gd, each physics tick) ---------------------

## The body's velocity, world.
var velocity := Vector3.ZERO
## 0 patrolling, 1 hunting.
var alert := 0.0
## The move under way (a MOVES key) and how far into it, or &"".
var move := &""
var move_t := 0.0
## What to look at (world), or null to look about.
var look_point = null
## Looking about: wider, slower, longer holds (searching, a patrol stop).
var scanning := false
## Distance to the player it is after, for how often to pose (`_rate`).
var lod_distance := 0.0
## The point dipped (-) or raised (+) toward them in a move.
var aim_pitch := 0.0
## Asleep (enemy.gd's dormancy): no posing at all.
var asleep := false

# --- Its own -----------------------------------------------------------------------

var _skel: Skeleton3D
var _mesh_inst: MeshInstance3D
var _spear: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _eye_flare := 0.0
var _eye_level := 1.0
## Every bone's pose this frame, model space.
var _g: Array[Transform3D] = []
## The spear's transform, model space, and its grips.
var spear_xf := Transform3D.IDENTITY
var _springs := {}
var _feet: Array[Dictionary] = []
var _t := 0.0
var _debt := 0.0
var _started := false
var _yaw_prev := 0.0
var _yaw_rate := 0.0
var _vel_prev := Vector3.ZERO
var _accel := Vector3.ZERO
## Head looking: where it is turning to (yaw, pitch, in the chest's frame),
## held until `_look_hold`.
var _look_goal := Vector2.ZERO
var _look_hold := 0.0
## Weight shifts and regrips, now and then.
var _fidget_at := 0.0
var _fidget := 0.0
var _fidget_until := 0.0
## Reeling: a pose held a while (a parry, a heavy blow).
var _reel_until := 0.0
var _reel_len := 0.0
## The mantle: per strand [root, mid, bottom] now and last frame, world.
var _cloth: Array = []
var _cloth_prev: Array = []
var _cloth_live := false
var _cloak_posed := false
## Dead: collapsing (`die`).
var dead := false
var _dead_t := 0.0
var _dead_feet: Array[Vector3] = []
var _dead_side := 1.0

static var _mesh: ArrayMesh = null
static var _skin: Skin = null
static var _spear_mesh: ArrayMesh = null
## Which surface of the body is the glow, and its look (its own copy per scout).
static var _glow_surface := 0
static var _glow_mat: StandardMaterial3D = null
## Each strand's root, mid and bottom at rest (model space), and length.
static var _strand_rest: Array = []
static var _parents := PackedInt32Array()


func _ready() -> void:
	if _mesh == null:
		_load_model()
	_skel = Skeleton3D.new()
	_skel.name = "Rig"
	add_child(_skel)
	for i in _bone_count():
		var def: Array = _bone_def(i)
		_skel.add_bone(def[0])
	for i in _bone_count():
		var def: Array = _bone_def(i)
		var parent: int = def[1]
		_skel.set_bone_parent(i, parent)
		var rest_pos: Vector3 = def[2]
		var local := rest_pos - (_bone_def(parent)[2] as Vector3 if parent >= 0 else Vector3.ZERO)
		_skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, local))
	_skel.reset_bone_poses()
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "Body"
	_mesh_inst.mesh = _mesh
	_mesh_inst.skin = _skin
	_skel.add_child(_mesh_inst)
	_mesh_inst.skeleton = NodePath("..")
	# The rig reaches well outside its rest box (a lunge, the fall).
	_mesh_inst.custom_aabb = AABB(Vector3(-1.4, -0.3, -2.4), Vector3(2.8, 2.6, 4.2))
	_eye_mat = _glow_mat.duplicate() as StandardMaterial3D
	_mesh_inst.set_surface_override_material(_glow_surface, _eye_mat)
	_spear = MeshInstance3D.new()
	_spear.name = "Spear"
	_spear.mesh = _spear_mesh
	add_child(_spear)
	if _parents.is_empty():
		for i in _bone_count():
			_parents.append(int(_bone_def(i)[1]))
	_g.resize(_bone_count())
	for i in _bone_count():
		_g[i] = Transform3D(Basis.IDENTITY, _bone_def(i)[2])
	_fidget_at = randf_range(3.0, 7.0)


static func _bone_count() -> int:
	return BONES.size() + STRANDS * 2


static func _bone_def(i: int) -> Array:
	if i < BONES.size():
		return BONES[i]
	_strands_rest()
	var k := (i - BONES.size()) / 2
	var rest: Array = _strand_rest[k]
	if (i - BONES.size()) % 2 == 0:
		return ["Cloak%dA" % k, CHEST, rest[0]]
	return ["Cloak%dB" % k, i - 1, rest[1]]


## The parts drawn, for the hit flash.
func parts() -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = [_mesh_inst]
	if _spear != null and _spear.get_parent() == self:
		out.append(_spear)
	return out


## The spear's point, world.
func spear_tip() -> Vector3:
	return global_transform * (spear_xf * Vector3(0.0, 0.0, -SPEAR_TIP))


## A point `back` metres from the point along the shaft, world.
func spear_point(back: float) -> Vector3:
	return global_transform * (spear_xf * Vector3(0.0, 0.0, -SPEAR_TIP + back))


## The eyes flare (0..1) through a wind-up.
func flare(amount: float) -> void:
	_eye_flare = amount


## A blow landed on it from `dir` (world, the way the blow travelled), 0..1.
func hit(dir: Vector3, strength: float) -> void:
	var local := global_transform.basis.inverse() * dir
	var s := clampf(strength, 0.2, 1.0)
	_kick(&"r_lean", -2.6 * s * clampf(-local.z + 0.4, 0.2, 1.4))
	_kick(&"r_twist", 3.2 * s * clampf(local.x, -1.0, 1.0) + randf_range(-0.8, 0.8) * s)
	_kick(&"r_side", -2.0 * s * clampf(local.x, -1.0, 1.0))
	_kick(&"r_head", randf_range(-4.0, 4.0) * s)
	_kick(&"r_nod", -3.0 * s)


## Knocked off balance for `time` (a parry, a stagger): the REEL pose, the spear
## thrown up; the body shoved back is the scout's (enemy.gd's knockback).
func reel(dir: Vector3, time: float) -> void:
	_reel_until = _t + maxf(time, 0.3)
	_reel_len = maxf(time, 0.3)
	hit(dir, 1.0)


## Down: it buckles at the knees, lets the spear go and pitches over on its
## face. `dir`: the way the last blow went (world).
func die(dir: Vector3) -> void:
	if dead:
		return
	dead = true
	_dead_t = 0.0
	var local := global_transform.basis.inverse() * dir
	_dead_side = -1.0 if local.x < 0.0 else 1.0
	_dead_feet.clear()
	var inv := global_transform.affine_inverse()
	for f in _feet:
		_dead_feet.append(inv * (f["pos"] as Vector3))
	_drop_spear(dir)


## Everything in its rest pose, the feet under it: for a body put down somewhere
## new (a spawn, a teleport).
func settle() -> void:
	_started = false


func _process(delta: float) -> void:
	if asleep and not dead:
		return
	delta = minf(delta, 0.1)
	_debt += delta
	var stride := _stride()
	if _debt < stride:
		return
	var dt := minf(_debt, 0.25)
	_debt = 0.0
	_t += dt
	_animate(dt)


## How long between poses: every frame close in or in a move; further off, at
## the rig rates the settings give (Graphics, as enemy.gd's `_advance_anim`).
func _stride() -> float:
	if dead or move != &"" or Graphics.anim_full_distance >= 1.0e8:
		return 0.0
	if lod_distance > Graphics.anim_half_distance:
		return 1.0 / Graphics.anim_far_rate if Graphics.anim_far_rate > 0.0 else 1.0e9
	if lod_distance > Graphics.anim_full_distance:
		return 1.0 / maxf(Graphics.anim_near_rate, 1.0)
	return 0.0


# --- The frame -----------------------------------------------------------------------

func _animate(dt: float) -> void:
	var xf := global_transform
	if not _started:
		_start(xf)
	var yaw := _yaw_of(xf)
	_yaw_rate = lerpf(_yaw_rate, angle_difference(_yaw_prev, yaw) / dt, clampf(dt * 10.0, 0.0, 1.0))
	_yaw_prev = yaw
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	_accel = _accel.lerp((flat - _vel_prev) / dt, clampf(dt * 8.0, 0.0, 1.0))
	_vel_prev = flat
	var inv := xf.affine_inverse()
	var local_v := xf.basis.inverse() * flat
	var local_a := xf.basis.inverse() * _accel
	var speed := flat.length()

	# The pose wanted, and its springs.
	var want := _target_pose()
	var fast := move != &"" or _t < _reel_until
	# Stiff enough in a move for the scout's quickened tempo (note 129).
	var w_spear := 31.0 if fast else 9.0
	var w_body := 18.0 if fast else 7.5
	var z_spear := 0.68 if fast else 0.9
	var z_body := 0.72 if fast else 0.92
	_sp(&"grip", want["grip"], w_spear, z_spear, dt)
	_sp(&"aim", (want["aim"] as Vector3).normalized(), w_spear * 0.95, z_spear, dt)
	_sp(&"roll", want["roll"], w_spear * 0.7, z_spear, dt)
	_sp(&"twist", want["twist"], w_body * 1.15, z_body - 0.05, dt)
	_sp(&"pelvis", want["pelvis"], w_body * 1.25, z_body - 0.05, dt)
	# Leaning into the speed and into acceleration; banking into a turn.
	var lean_t: float = want["lean"] + clampf(-local_v.z * 0.035, -0.1, 0.18) \
		+ clampf(-local_a.z * 0.022, -0.16, 0.22)
	var side_t: float = want["side"] + clampf(_yaw_rate * speed * 0.035, -0.22, 0.22) \
		+ clampf(local_a.x * 0.012, -0.08, 0.08)
	_sp(&"lean", lean_t, w_body, z_body, dt)
	_sp(&"side", side_t, w_body, z_body, dt)
	_sp(&"crouch", want["crouch"], w_body, z_body, dt)
	# The reactions: kicked by a blow, sprung back to nothing, wobbling.
	for k in [&"r_lean", &"r_twist", &"r_side", &"r_head", &"r_nod"]:
		_sp(k, 0.0, 11.0, 0.32, dt)

	# The feet.
	var stance := {"lead": want["lead"], "back": want["back"], "wide": want["wide"],
		"out": want["out"]}
	if dead:
		_dead_t += dt
	else:
		_gait(dt, xf, flat, stance)
	var gait := _gait_offsets(speed)
	_sp(&"bob", gait.x, 16.0, 1.0, dt)
	_sp(&"sway", gait.y, 12.0, 1.0, dt)
	_sp(&"groll", gait.z, 14.0, 1.0, dt)
	_sp(&"gyaw", _gait_yaw(speed), 12.0, 1.0, dt)

	# Breathing, and now and then a shift of weight.
	var breath := sin(_t * TAU * (0.26 + 0.2 * alert)) * (0.016 + 0.01 * alert)
	_tick_fidget(speed)
	_sp(&"fidget", _fidget if _t < _fidget_until else 0.0, 3.5, 1.0, dt)

	var lean: float = _v(&"lean") + _v(&"r_lean")
	var crouch: float = _v(&"crouch")
	var twist: float = _v(&"twist") + _v(&"r_twist") - _v(&"gyaw") * 0.6
	var side: float = _v(&"side") + _v(&"r_side")
	if dead:
		var d := _death_curve()
		lean = lerpf(lean, 0.95, d.x)
		crouch = lerpf(crouch, 0.44, d.x)
		side = lerpf(side, 0.25 * _dead_side, d.x)

	# --- The pelvis --------------------------------------------------------------
	var hips_pos := Vector3(_v(&"sway") + _v(&"fidget") * 0.05,
		BONES[HIPS][2].y - crouch + _v(&"bob"), lean * 0.07)
	var hips_basis := Basis(Vector3.UP, _v(&"pelvis") + _v(&"gyaw")) \
		* Basis(Vector3.RIGHT, -lean * 0.25) * Basis(Vector3.FORWARD, _v(&"groll") + _v(&"fidget") * 0.05)
	# No higher than the planted feet can reach (a leg never locks out).
	var feet_m: Array[Vector3] = []
	for i in 2:
		feet_m.append(_foot_model(i, inv, hips_pos))
	if not dead:
		for i in 2:
			if not bool(_feet[i]["planted"]):
				continue
			var side_s := 1.0 if i == 0 else -1.0
			var socket := hips_pos + hips_basis * (HIP_SOCKET * Vector3(side_s, 1.0, 1.0))
			var d := Vector2(socket.x - feet_m[i].x, socket.z - feet_m[i].z).length()
			var reach := (THIGH + SHIN) * 0.985
			var top := feet_m[i].y + sqrt(maxf(reach * reach - d * d, 0.0)) - HIP_SOCKET.y
			hips_pos.y = minf(hips_pos.y, top)
	# Down fast (a leg must never be left short of its foot), up gently -- but
	# never faster than HIPS_SPEED: a drop in one frame reads as a pop.
	_sp_capped(&"hips_y", hips_pos.y, 40.0 if hips_pos.y < float(_v(&"hips_y")) else 22.0, HIPS_SPEED, dt)
	hips_pos.y = _v(&"hips_y")
	_g[HIPS] = Transform3D(hips_basis, hips_pos)

	# --- The spine, the head --------------------------------------------------------
	_g[SPINE] = _g[HIPS] * Transform3D(Basis(Vector3.RIGHT, -lean * 0.35) * Basis(Vector3.UP, twist * 0.35),
		Vector3(0.0, 0.10, 0.0))
	_g[CHEST] = _g[SPINE] * Transform3D(Basis(Vector3.RIGHT, -lean * 0.4 + breath) * Basis(Vector3.UP, twist * 0.65)
		* Basis(Vector3.FORWARD, side), Vector3(0.0, 0.20, 0.0))
	var look := _look(dt, xf)
	var nod: float = _v(&"r_nod")
	if dead:
		nod += _death_curve().x * 0.7
	_g[NECK] = _g[CHEST] * Transform3D(Basis(Vector3.UP, look.x * 0.35)
		* Basis(Vector3.RIGHT, lean * 0.55 + look.y * 0.35 - breath * 0.5), Vector3(0.0, 0.21, 0.0))
	_g[HEAD] = _g[NECK] * Transform3D(Basis(Vector3.UP, look.x * 0.65 + _v(&"r_head") * 0.3)
		* Basis(Vector3.RIGHT, lean * 0.4 + look.y * 0.65 - nod * 0.3), Vector3(0.0, 0.09, 0.0))

	# --- The spear, then the arms that hold it ---------------------------------------
	var chest := _g[CHEST]
	if _spear.get_parent() == self:
		var grip: Vector3 = chest * (_v(&"grip") as Vector3)
		# The point's way turns with the chest but does not pitch with its hunch:
		# the hunched chest pointed every thrust at the floor.
		var cf := -chest.basis.z
		var aim: Vector3 = (Basis(Vector3.UP, atan2(-cf.x, -cf.z)) * (_v(&"aim") as Vector3)).normalized()
		_sp(&"pitch", aim_pitch if move != &"" else 0.0, 14.0, 1.0, dt)
		var pitch: float = _v(&"pitch")
		if absf(pitch) > 0.001:
			var right := aim.cross(Vector3.UP)
			if right.length_squared() > 1e-4:
				aim = aim.rotated(right.normalized(), pitch)
		# The rear hand cannot reach past its arm: the grip comes back to it.
		var sh_r := chest * (SHOULDER + Vector3(0.0, 0.0, 0.0))
		var to_grip := grip - sh_r
		var reach_r := UPPER_ARM + FOREARM + GRIP_OFF - 0.01
		if to_grip.length() > reach_r:
			grip = sh_r + to_grip.normalized() * reach_r
		var z := -aim
		var up := chest.basis.y
		var x := up.cross(z)
		if x.length_squared() < 1e-4:
			x = chest.basis.x
		x = x.normalized().rotated(z, _v(&"roll") + _v(&"fidget") * 0.25)
		var y := z.cross(x).normalized()
		spear_xf = Transform3D(Basis(x, y, z), grip)
		_spear.transform = spear_xf
		_arm(true, chest, grip, aim)
		# Where the front hand is on the shaft, followed by a spring: the hand
		# slides along it, it never jumps.
		# Never faster than SLIDE_SPEED: a grip that shoots along the shaft in a
		# swing reads as the hand coming off it.
		_sp_capped(&"slide", _front_grip(chest * (SHOULDER * Vector3(-1.0, 1.0, 1.0)), grip, aim), 22.0, SLIDE_SPEED, dt)
		var front: Vector3 = grip + aim * float(_v(&"slide"))
		_arm(false, chest, front, aim)
	else:
		_limp_arm(true, chest, dt)
		_limp_arm(false, chest, dt)

	# --- The legs ----------------------------------------------------------------------
	for i in 2:
		_leg(i, feet_m[i], xf)

	# --- The mantle --------------------------------------------------------------------
	_cloak(dt, xf)

	# --- Out to the rig ----------------------------------------------------------------
	# The mantle's bones only while it swings (hanging still, they keep their
	# pose on the chest).
	var count := _bone_count() if (_cloth_live or not _cloak_posed) else CLOAK0
	_cloak_posed = true
	for i in count:
		var parent: int = _parents[i]
		var local: Transform3D = _g[i] if parent < 0 else _g[parent].affine_inverse() * _g[i]
		_skel.set_bone_pose_position(i, local.origin)
		_skel.set_bone_pose_rotation(i, local.basis.orthonormalized().get_rotation_quaternion())

	if dead:
		_topple()
	_eyes(dt)


func _start(xf: Transform3D) -> void:
	_started = true
	_yaw_prev = _yaw_of(xf)
	_feet.clear()
	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		var p := xf * Vector3(s * 0.13, 0.0, 0.06 if i == 0 else -0.1)
		p.y = xf.origin.y
		_feet.append({"pos": p, "yaw": _yaw_prev, "planted": true, "from": p, "from_yaw": _yaw_prev,
			"u": 0.0, "dur": 0.3, "lift": 0.08, "stance_t": 1.0})
	_springs.clear()
	var p := _target_pose()
	for k in p:
		_springs[k] = [p[k], p[k] * 0.0]
	_springs[&"aim"] = [(p["aim"] as Vector3).normalized(), Vector3.ZERO]
	_springs[&"hips_y"] = [BONES[HIPS][2].y - float(p["crouch"]), 0.0]
	_cloth_live = false


# --- The pose wanted ------------------------------------------------------------------

func _target_pose() -> Dictionary:
	if _t < _reel_until:
		var left := _reel_until - _t
		if left < 0.3:
			return _blend(P_REEL, P_HUNT, 1.0 - left / 0.3)
		return P_REEL
	if move != &"" and MOVES.has(move):
		return _key_pose(MOVES[move], move_t)
	return _blend(P_GUARD, P_HUNT, clampf(alert, 0.0, 1.0))


static func _key_pose(keys: Array, t: float) -> Dictionary:
	if t <= float(keys[0][0]):
		return keys[0][1]
	for i in range(1, keys.size()):
		var b: Array = keys[i]
		if t <= float(b[0]):
			var a: Array = keys[i - 1]
			var u := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			match int(b[2]):
				1:
					u = u * u * u
				2:
					u = 1.0 - pow(1.0 - u, 3.0)
				_:
					u = u * u * (3.0 - 2.0 * u)
			return _blend(a[1], b[1], u)
	return keys[keys.size() - 1][1]


static func _blend(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := {}
	for k in a:
		var x = a[k]
		var y = b[k]
		if x is Vector3:
			out[k] = (x as Vector3).lerp(y, u)
		else:
			out[k] = lerpf(float(x), float(y), u)
	return out


# --- Springs -------------------------------------------------------------------------------

## A damped spring after `target` (float or Vector3): `omega` how stiff, `zeta`
## how damped (1 none over, below that an overshoot).
func _sp(key: StringName, target, omega: float, zeta: float, dt: float) -> void:
	if not _springs.has(key):
		_springs[key] = [target, target * 0.0]
	var s: Array = _springs[key]
	var x = s[0]
	var v = s[1]
	var n := maxi(ceili(dt / 0.021), 1)
	var h := dt / float(n)
	for i in n:
		var a = (target - x) * (omega * omega) - v * (2.0 * zeta * omega)
		v += a * h
		x += v * h
	s[0] = x
	s[1] = v


## A critically damped spring on a float that never moves faster than `cap`
## a second.
func _sp_capped(key: StringName, target: float, omega: float, cap: float, dt: float) -> void:
	var was: float = _v(key) if _springs.has(key) else target
	_sp(key, target, omega, 1.0, dt)
	var s: Array = _springs[key]
	s[0] = was + clampf(float(s[0]) - was, -cap * dt, cap * dt)
	s[1] = clampf(float(s[1]), -cap, cap)


func _v(key: StringName):
	var s = _springs.get(key)
	return s[0] if s != null else 0.0


func _kick(key: StringName, speed: float) -> void:
	if not _springs.has(key):
		_springs[key] = [0.0, 0.0]
	_springs[key][1] = float(_springs[key][1]) + speed


# --- The feet -------------------------------------------------------------------------------

## Where foot `i` belongs under the body (world, on the floor) and which way it
## should point.
func _neutral(i: int, xf: Transform3D, stance: Dictionary) -> Vector3:
	var s := 1.0 if i == 0 else -1.0
	var z: float = float(stance["back"]) if i == 0 else -float(stance["lead"])
	var p := xf * Vector3(s * (0.13 + float(stance["wide"])), 0.0, z)
	p.y = xf.origin.y
	return p


func _neutral_yaw(i: int, xf: Transform3D, stance: Dictionary) -> float:
	var yaw := _yaw_of(xf)
	return yaw - float(stance["out"]) if i == 0 else yaw + 0.12


func _gait(dt: float, xf: Transform3D, flat: Vector3, stance: Dictionary) -> void:
	var s := flat.length()
	var ts := clampf(0.62 - 0.07 * s, 0.12, 0.62)
	var floor_y := xf.origin.y
	var neutral: Array[Vector3] = [_neutral(0, xf, stance), _neutral(1, xf, stance)]
	var yaws: Array[float] = [_neutral_yaw(0, xf, stance), _neutral_yaw(1, xf, stance)]
	# Put down somewhere new: the feet come with it.
	for i in 2:
		if (_feet[i]["pos"] as Vector3).distance_to(neutral[i]) > 3.0:
			_feet[i]["pos"] = neutral[i]
			_feet[i]["planted"] = true
	# The swinging feet: on along their arc, to where they will be needed.
	for i in 2:
		var f: Dictionary = _feet[i]
		if bool(f["planted"]):
			f["stance_t"] = float(f["stance_t"]) + dt
			var p: Vector3 = f["pos"]
			p.y = floor_y
			f["pos"] = p
			continue
		var u := minf(float(f["u"]) + dt / float(f["dur"]), 1.0)
		f["u"] = u
		var land: Vector3 = neutral[i] + flat * (ts * 0.5 + (1.0 - u) * float(f["dur"]))
		var e := u * u * (3.0 - 2.0 * u)
		var p: Vector3 = (f["from"] as Vector3).lerp(land, e)
		p.y = floor_y + float(f["lift"]) * sin(PI * u) * (1.0 - 0.3 * u)
		f["pos"] = p
		f["yaw"] = lerp_angle(float(f["from_yaw"]), yaws[i], e)
		if u >= 1.0:
			f["planted"] = true
			f["pos"] = Vector3(land.x, floor_y, land.z)
			f["yaw"] = yaws[i]
			f["stance_t"] = 0.0
	# Lift one? The foot furthest past where it should be, if the other is down
	# (running, once the other is well into its swing).
	var best := -1
	var best_r := 1.0
	for i in 2:
		var f: Dictionary = _feet[i]
		if not bool(f["planted"]) or float(f["stance_t"]) < 0.07:
			continue
		var o: Dictionary = _feet[1 - i]
		if not bool(o["planted"]) and not (s > 3.2 and float(o["u"]) > 0.55):
			continue
		var desired: Vector3 = neutral[i] + flat * ts * 0.5
		var p: Vector3 = f["pos"]
		var err := Vector2(p.x - desired.x, p.z - desired.z).length()
		var r := err / maxf(s * ts * 0.95, 0.15)
		r = maxf(r, absf(angle_difference(float(f["yaw"]), yaws[i])) / 0.6)
		if r > best_r:
			best_r = r
			best = i
	if best >= 0:
		var f: Dictionary = _feet[best]
		var desired: Vector3 = neutral[best] + flat * ts * 0.5
		var dist := Vector2((f["pos"] as Vector3).x - desired.x, (f["pos"] as Vector3).z - desired.z).length()
		var tw := clampf(0.36 - 0.022 * s, 0.2, 0.36)
		f["planted"] = false
		f["u"] = 0.0
		f["from"] = f["pos"]
		f["from_yaw"] = f["yaw"]
		f["dur"] = tw * clampf(0.7 + dist * 0.45, 0.7, 1.25)
		f["lift"] = clampf(0.05 + 0.035 * s, 0.05, 0.22) * clampf(dist / 0.35, 0.45, 1.0)


## The pelvis's bob, sway over the standing foot and drop on the swinging side,
## from the swinging foot's progress: (bob, sway, roll).
func _gait_offsets(speed: float) -> Vector3:
	if dead or _feet.is_empty():
		return Vector3.ZERO
	for i in 2:
		if not bool(_feet[i]["planted"]):
			var u := float(_feet[i]["u"])
			var side := 1.0 if i == 0 else -1.0
			var arc := sin(PI * u)
			var amp := 0.026 * clampf(1.3 - speed * 0.16, 0.35, 1.0)
			return Vector3(amp * arc, -side * 0.03 * arc * clampf(1.2 - speed * 0.12, 0.3, 1.0),
				side * 0.065 * arc)
	return Vector3.ZERO


## The pelvis turned with the stride: the swinging leg's hip goes forward.
func _gait_yaw(speed: float) -> float:
	if dead or _feet.is_empty():
		return 0.0
	for i in 2:
		if not bool(_feet[i]["planted"]):
			var side := 1.0 if i == 0 else -1.0
			return side * 0.11 * (2.0 * float(_feet[i]["u"]) - 1.0) * clampf(speed / 1.5, 0.0, 1.0)
	return 0.0


## Foot `i`'s ankle in model space (the heel rolled up as a planted foot trails
## behind the hips), with its yaw and pitch in `_foot_pose`.
var _foot_pose: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]


func _foot_model(i: int, inv: Transform3D, hips: Vector3) -> Vector3:
	if dead and _dead_feet.size() == 2:
		# The feet stay on the floor as it pitches over (the rig is turned by
		# `_topple`): toes down, shins lying behind it.
		var f := _death_curve().y
		_foot_pose[i] = Vector2(_foot_pose[i].x, lerpf(0.0, 1.38, f) - 0.35 * (1.0 - f) * minf(_dead_t * 2.0, 1.0))
		return _skel.transform.affine_inverse() * (_dead_feet[i] + Vector3(0.0, ANKLE * (1.0 - f), 0.12 * f))
	var f: Dictionary = _feet[i]
	var p: Vector3 = inv * (f["pos"] as Vector3)
	var yaw := angle_difference(_yaw_prev, float(f["yaw"]))
	var pitch := 0.0
	if bool(f["planted"]):
		var behind := p.z - hips.z
		if behind > 0.14:
			pitch = -clampf((behind - 0.14) * 1.8, 0.0, 0.55)
	else:
		var u := float(f["u"])
		if u < 0.5:
			pitch = -0.5 * sin(PI * u / 0.5)
		else:
			pitch = 0.28 * sin(PI * (u - 0.5) / 0.5)
	# Rolled about the toe (0.17 m ahead of the ankle) when the heel is up.
	if pitch < 0.0:
		var toe := Vector3(0.0, 0.0, -0.17).rotated(Vector3.UP, yaw)
		var tip := Vector3(0.0, 0.0, -0.17).rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)
		p += toe - tip
	p.y += ANKLE
	_foot_pose[i] = Vector2(yaw, pitch)
	return p


func _leg(i: int, ankle: Vector3, xf: Transform3D) -> void:
	var s := 1.0 if i == 0 else -1.0
	var thigh := THIGH_R if i == 0 else THIGH_L
	var hip := _g[HIPS] * (HIP_SOCKET * Vector3(s, 1.0, 1.0))
	var fwd := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _foot_pose[i].x)
	var pole := (fwd + Vector3(s * 0.18, 0.15, 0.0)).normalized()
	var r := _two_bone(hip, ankle, pole, THIGH, SHIN)
	var knee: Vector3 = r[0]
	var end: Vector3 = r[1]
	_g[thigh] = Transform3D(_limb_basis(hip - knee, -pole), hip)
	_g[thigh + 1] = Transform3D(_limb_basis(knee - end, -pole), knee)
	_g[thigh + 2] = Transform3D(Basis(Vector3.UP, _foot_pose[i].x) * Basis(Vector3.RIGHT, _foot_pose[i].y), end)


## The rear hand (right) on the grip, or the front hand (left) where it slid to.
func _arm(right: bool, chest: Transform3D, grip: Vector3, axis: Vector3) -> void:
	var s := 1.0 if right else -1.0
	var shoulder := chest * (SHOULDER * Vector3(s, 1.0, 1.0))
	var palm := shoulder - grip
	palm -= axis * palm.dot(axis)
	palm = palm.normalized() if palm.length_squared() > 1e-6 else chest.basis.y
	var wrist := grip + palm * GRIP_OFF
	# Elbows out and back (the rear arm) or out and down (the front).
	var pole := (chest.basis * (Vector3(0.7, -0.3, 0.62) if right else Vector3(-0.78, -0.55, 0.3))).normalized()
	var r := _two_bone(shoulder, wrist, pole, UPPER_ARM, FOREARM)
	var elbow: Vector3 = r[0]
	var end: Vector3 = r[1]
	var ua := UARM_R if right else UARM_L
	_g[ua] = Transform3D(_limb_basis(shoulder - elbow, pole), shoulder)
	_g[ua + 1] = Transform3D(_limb_basis(elbow - end, pole), elbow)
	_g[ua + 2] = Transform3D(_limb_basis(palm, -axis), end)


## Dead, the spear gone: the arms hang, swinging.
func _limp_arm(right: bool, chest: Transform3D, dt: float) -> void:
	var s := 1.0 if right else -1.0
	var shoulder := chest * (SHOULDER * Vector3(s, 1.0, 1.0))
	var key := &"limp_r" if right else &"limp_l"
	var hang := shoulder + Vector3(s * 0.08, -0.52, -0.1)
	_sp(key, hang, 9.0, 0.35, dt)
	var wrist: Vector3 = _v(key)
	var pole := (chest.basis * Vector3(s * 0.5, -0.2, 0.8)).normalized()
	var r := _two_bone(shoulder, wrist, pole, UPPER_ARM, FOREARM)
	var ua := UARM_R if right else UARM_L
	_g[ua] = Transform3D(_limb_basis(shoulder - r[0], pole), shoulder)
	_g[ua + 1] = Transform3D(_limb_basis(r[0] - r[1], pole), r[0])
	_g[ua + 2] = Transform3D(_limb_basis(r[0] - r[1], pole), r[1])


## Where on the shaft the front hand is (metres from the rear hand): the point
## nearest its shoulder, no nearer the rear hand than SLIDE_MIN, and pulled in
## along the shaft until its arm reaches it.
func _front_grip(shoulder: Vector3, grip: Vector3, axis: Vector3) -> float:
	var reach := UPPER_ARM + FOREARM + GRIP_OFF - 0.015
	var rel := shoulder - grip
	var t := clampf(rel.dot(axis), SLIDE_MIN, SLIDE_MAX)
	var p := grip + axis * t
	if p.distance_to(shoulder) > reach:
		var along := rel.dot(axis)
		var perp2 := rel.length_squared() - along * along
		if perp2 < reach * reach:
			# Of the two places on the shaft at arm's length, the one nearer where
			# the hand already is.
			var h := sqrt(reach * reach - perp2)
			var was: float = _v(&"slide") if _springs.has(&"slide") else along - h
			var a := clampf(along - h, SLIDE_MIN, SLIDE_MAX)
			var b := clampf(along + h, SLIDE_MIN, SLIDE_MAX)
			t = a if absf(a - was) <= absf(b - was) else b
	return t


## Two bones from `root` toward `target`, bending toward `pole`: [mid, end].
static func _two_bone(root: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float) -> Array:
	var to := target - root
	var dist := to.length()
	var dir := to / dist if dist > 1e-5 else Vector3.DOWN
	var d := clampf(dist, absf(l1 - l2) + 0.01, (l1 + l2) * 0.999)
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var bend := pole - dir * pole.dot(dir)
	if bend.length_squared() < 1e-6:
		bend = dir.cross(Vector3.RIGHT)
	bend = bend.normalized()
	return [root + dir * a + bend * h, root + dir * d]


## A bone whose +Y runs along `up` (from its child to it) with its +Z toward
## `z_ref` -- every rest orientation here is the identity.
static func _limb_basis(up: Vector3, z_ref: Vector3) -> Basis:
	var y := up.normalized()
	var z := z_ref - y * z_ref.dot(y)
	if z.length_squared() < 1e-6:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


# --- The head --------------------------------------------------------------------------

## Yaw and pitch of the look, relative to the chest: quick turns and holds.
func _look(dt: float, xf: Transform3D) -> Vector2:
	var chest := _g[CHEST]
	var goal := _look_goal
	if dead:
		goal = Vector2(0.4 * _dead_side, -0.3)
	elif look_point != null:
		var p: Vector3 = xf.affine_inverse() * (look_point as Vector3)
		var d := chest.basis.inverse() * (p - (chest * Vector3(0.0, 0.32, 0.0)))
		var flat_len := Vector2(d.x, d.z).length()
		var want := Vector2(clampf(atan2(-d.x, -d.z), -1.25, 1.25), clampf(atan2(d.y, flat_len), -0.6, 0.5))
		# A hunter fixes on its quarry: small moves are followed, not jumped.
		if want.distance_to(_look_goal) > 0.06 or _t >= _look_hold:
			_look_goal = want
			_look_hold = _t + 0.12
		goal = _look_goal
	elif _t >= _look_hold:
		var wide := 1.05 if scanning else 0.55
		_look_goal = Vector2(randf_range(-wide, wide), randf_range(-0.22, 0.12))
		if randf() < 0.3:
			_look_goal = Vector2(_look_goal.x * 0.2, -0.05)
		_look_hold = _t + (randf_range(0.7, 1.9) if scanning else randf_range(0.9, 2.6))
		goal = _look_goal
	_sp(&"look", Vector3(goal.x, goal.y, 0.0), 17.0, 0.86, dt)
	var l: Vector3 = _v(&"look")
	return Vector2(l.x, l.y)


func _tick_fidget(speed: float) -> void:
	if _t < _fidget_at:
		return
	_fidget_at = _t + randf_range(4.0, 9.0)
	if speed > 0.4 or move != &"" or alert > 0.6:
		return
	_fidget = randf_range(-1.0, 1.0)
	_fidget_until = _t + randf_range(1.2, 2.6)


# --- The mantle ------------------------------------------------------------------------

func _cloak(dt: float, xf: Transform3D) -> void:
	_strands_rest()
	var chest := _g[CHEST]
	var live := not dead and lod_distance <= Graphics.anim_full_distance * 1.3 and Graphics.anim_quality > 0
	var world_chest := xf * chest
	if not live or not _cloth_live:
		_cloth.clear()
		_cloth_prev.clear()
		for k in STRANDS:
			var rest: Array = _strand_rest[k]
			var pts := [world_chest * ((rest[0] as Vector3) - CHEST_REST), world_chest * ((rest[1] as Vector3) - CHEST_REST),
				world_chest * ((rest[2] as Vector3) - CHEST_REST)]
			_cloth.append(pts)
			_cloth_prev.append(pts.duplicate())
		_cloth_live = live
	if live:
		var inv_chest := world_chest.affine_inverse()
		var g := Vector3(0.0, -9.8, 0.0) * dt * dt
		for k in STRANDS:
			var rest: Array = _strand_rest[k]
			var pts: Array = _cloth[k]
			var prev: Array = _cloth_prev[k]
			pts[0] = world_chest * ((rest[0] as Vector3) - CHEST_REST)
			for j in [1, 2]:
				var p: Vector3 = pts[j]
				var v: Vector3 = (p - (prev[j] as Vector3)) * 0.9
				var nxt := p + v + g
				var drape := world_chest * ((rest[j] as Vector3) - CHEST_REST)
				nxt = nxt.lerp(drape, 1.0 - exp(-(4.5 if j == 1 else 3.0) * dt))
				prev[j] = p
				pts[j] = nxt
			var la: float = rest[3]
			for it in 2:
				for j in [1, 2]:
					var a: Vector3 = pts[j - 1]
					var b: Vector3 = pts[j]
					var d := b - a
					var len := d.length()
					if len > 1e-5:
						pts[j] = a + d / len * la
				# Out of the body: an ellipse round the torso in the chest's frame.
				for j in [1, 2]:
					var q: Vector3 = inv_chest * (pts[j] as Vector3)
					if q.y > -0.62:
						var e := Vector2(q.x / 0.42, q.z / 0.3)
						if e.length() < 1.0 and e.length() > 1e-4:
							var out := e.normalized()
							q.x = out.x * 0.42
							q.z = out.y * 0.3
							pts[j] = world_chest * q
	var inv := xf.affine_inverse()
	for k in STRANDS:
		var pts: Array = _cloth[k]
		var a: Vector3 = inv * (pts[0] as Vector3)
		var b: Vector3 = inv * (pts[1] as Vector3)
		var c: Vector3 = inv * (pts[2] as Vector3)
		var down := chest.basis * Vector3.DOWN
		var ia := CLOAK0 + 2 * k
		_g[ia] = Transform3D(_swing(down, b - a) * chest.basis, a)
		_g[ia + 1] = Transform3D(_swing(down, c - b) * chest.basis, b)


static func _swing(from: Vector3, to: Vector3) -> Basis:
	if to.length_squared() < 1e-8:
		return Basis.IDENTITY
	var a := from.normalized()
	var b := to.normalized()
	if a.dot(b) > 0.99999:
		return Basis.IDENTITY
	if a.dot(b) < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(a, b))


# --- The eyes --------------------------------------------------------------------------

func _eyes(dt: float) -> void:
	if _eye_mat == null:
		return
	var want := 0.0 if dead else 1.0 + _eye_flare * 1.4
	if dead:
		# Out with a flicker.
		want = 0.0 if _dead_t > 0.7 or fmod(_dead_t * 17.0, 1.0) < 0.5 else 0.6
	_eye_level = move_toward(_eye_level, want, dt * (9.0 if want > _eye_level else 4.0))
	_eye_mat.emission_energy_multiplier = EYE_ENERGY * _eye_level
	_eye_mat.emission = EYE_COLOUR.lerp(Color(0.75, 1.0, 1.0), clampf(_eye_flare, 0.0, 1.0) * 0.35)


# --- Death ------------------------------------------------------------------------------

## x: the knees going (0..1); y: the fall forward (0..1, with a bounce).
func _death_curve() -> Vector2:
	var t := _dead_t
	var knees := clampf(t / 0.38, 0.0, 1.0)
	knees = 1.0 - pow(1.0 - knees, 2.0)
	var fall := 0.0
	if t > 0.3:
		var u := clampf((t - 0.3) / 0.5, 0.0, 1.0)
		fall = u * u
		if u >= 1.0:
			var b := t - 0.8
			fall = 1.0 - 0.08 * exp(-b * 7.0) * absf(sin(b * 16.0))
	return Vector2(knees, fall)


## Over on its face, about its knees.
func _topple() -> void:
	var f := _death_curve().y
	var pivot := Vector3(0.0, 0.0, -0.32)
	var b := Basis(Vector3.RIGHT, -1.38 * f) * Basis(Vector3.FORWARD, 0.18 * f * _dead_side)
	_skel.transform = Transform3D(b, pivot - b * pivot)


func _drop_spear(dir: Vector3) -> void:
	if _spear == null or _spear.get_parent() != self:
		return
	var world := global_transform * spear_xf
	var host := get_tree().current_scene if get_tree() != null else null
	var at := get_parent()
	while at != null and not (at is CharacterBody3D):
		at = at.get_parent()
	if at != null and at.get_parent() != null:
		host = at.get_parent()
	if host == null:
		_spear.queue_free()
		return
	var rb := RigidBody3D.new()
	rb.name = "ScoutSpear"
	rb.collision_layer = 0
	rb.collision_mask = 1 | 2 | 256
	rb.mass = 2.5
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.04
	cap.height = SPEAR_TIP + SPEAR_BUTT
	cs.shape = cap
	cs.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	cs.position = Vector3(0.0, 0.0, (SPEAR_BUTT - SPEAR_TIP) * 0.5)
	rb.add_child(cs)
	_spear.material_overlay = null
	remove_child(_spear)
	_spear.transform = Transform3D.IDENTITY
	rb.add_child(_spear)
	host.add_child(rb)
	rb.global_transform = world
	rb.linear_velocity = Vector3(dir.x, 0.0, dir.z).normalized() * 1.2 + Vector3(0.0, 0.6, 0.0)
	rb.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5), randf_range(-2.0, 2.0))
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.queue_free())


static func _yaw_of(xf: Transform3D) -> float:
	return atan2(xf.basis.z.x, xf.basis.z.z)


# --- The mesh --------------------------------------------------------------------------

## Each strand's rest: [root, mid, bottom, half length], model space.
static func _strands_rest() -> void:
	if not _strand_rest.is_empty():
		return
	for k in STRANDS:
		var th := deg_to_rad(-STRAND_SPAN + 2.0 * STRAND_SPAN * float(k) / float(STRANDS - 1))
		var root := _cloak_edge(th)
		var bottom := _cloak_hang(th, 1.0, _cloak_len(th))
		var mid := root.lerp(bottom, 0.5)
		_strand_rest.append([root, mid, bottom, root.distance_to(bottom) * 0.5])


## The mantle's shoulder edge at angle `th` round the neck (0 behind, + to the
## right side), model space.
static func _cloak_edge(th: float) -> Vector3:
	return Vector3(sin(th) * 0.41, 1.5 + 0.07 * absf(sin(th)), cos(th) * 0.29)


static func _cloak_len(th: float) -> float:
	var a := absf(rad_to_deg(th))
	if a <= 90.0:
		return lerpf(0.72, 0.42, sin(deg_to_rad(a)))
	return lerpf(0.42, 0.26, clampf((a - 90.0) / 60.0, 0.0, 1.0))


static func _cloak_hang(th: float, f: float, length: float) -> Vector3:
	return _cloak_edge(th) + Vector3(sin(th) * 0.045 * f, -length * f, cos(th) * 0.06 * f)


## The Blender model: its body and spear meshes, and which surface glows.
static func _load_model() -> void:
	var root := (load(MODEL) as PackedScene).instantiate()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin != null:
			_mesh = mi.mesh
			_skin = _binds(mi.skin)
		else:
			_spear_mesh = mi.mesh
	root.free()
	for i in _mesh.get_surface_count():
		var m := _mesh.surface_get_material(i)
		if m != null and m.resource_name == "ScoutGlow":
			_glow_surface = i
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.02, 0.12, 0.14)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = EYE_COLOUR
	_glow_mat.emission_energy_multiplier = EYE_ENERGY
	_glow_mat.roughness = 0.2


## The model's bind order with this rig's rests. The exporter hangs a bone chain
## off a root turned to Y-up, so its own binds are not this rig's (every rest
## orientation the identity).
static func _binds(from: Skin) -> Skin:
	var rest := {}
	for i in _bone_count():
		var def: Array = _bone_def(i)
		rest[def[0]] = def[2]
	var out := Skin.new()
	for i in from.get_bind_count():
		var bone := String(from.get_bind_name(i))
		out.add_named_bind(bone, Transform3D(Basis.IDENTITY, rest[bone]).affine_inverse())
	return out
