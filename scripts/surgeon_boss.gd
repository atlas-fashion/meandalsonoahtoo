extends CharacterBody3D

## THE SURGEON as a boss (2026-10-25; the frame of the fight note 105; his body,
## the claw on his back and his three moves note 109).
##
## The user (note 109): "The surgeon should not be the model that was created.
## Make a temporary model. It should have robotic arms and legs. Its attacks
## should be a 'spear dash' with a precision needle bionic hand, a fast spin
## using all 4 appendages, while the surgeon uses the claw on his back as legs,
## and a delayed jump onto his back, slamming the claw into the ground."
##
## HIS BODY (`_build_body`): a STAND-IN made of primitives until a real model --
## a coated, bald man in red-lensed goggles whose arms and legs are iron: brass
## ball joints, steel shafts, a three-fingered clamp for a left hand and for a
## right a long precision NEEDLE. Posed every frame from joint angles (`_pose`,
## `_animate`): standing, walking, at work, reaching, striking, the three moves,
## lying. Facing his +Z.
##
## THE CLAW (`mount_claw`): taken off the dead machine's arm (surgical_table.gd
## `take_claw`) and worn on his back -- folded up over his shoulder; let down
## and lengthened under him as a second pair of legs for the spin; out of his
## back for the slam. Its fingers open and shut as the table's did.
##
## STATES:
##   AT_WORK   at his console in the booth (the machine running); untouchable.
##   FLUNG     in the air, out of the booth (the kick, surgery_control.gd).
##   DOWN      lying where he landed in the hall, out cold.
##   SCRIPTED  in a scene (surgery_control.gd): walked, hopped and posed by it.
##   WAITING   on his feet in the hall: the fight starts the moment a player is
##             in the hall (a save, a world reset).
##   RISING    RISE_TIME, then the fight.
##   FIGHT     `engaged` (the HUD's boss bar); he can be hurt; the bars at the
##             ways in are up (surgery.gd). Between moves he walks at them round
##             the vats (his own grid, below); then one of:
##     DASH   the needle drawn back (DASH_WIND, the parry cue), then driven
##            straight through where they were, DASH_SPEED for DASH_TIME.
##     SPIN   up on the claw's fingers (SPIN_RISE), arms and legs flung out,
##            spinning (SPIN_TIME) -- anyone within SPIN_REACH cut every
##            SPIN_EVERY -- down, and dizzy a moment.
##     SLAM   a crouch, a leap SLAM_HEIGHT up, a hang at the top as he turns
##            onto his back (SLAM_HANG -- the parry cue), and down claw-first on
##            where they stood: SLAM_DAMAGE close, thrown down out to SLAM_KNOCK;
##            then on his back a while (SLAM_LIE), hurt the more for it.
##   A parry off the needle or the spin staggers him (STAGGER_TIME).
##   DEAD      `defeated`: the bars come down.
##
## Its numbers are first guesses, all here.

signal fight_started
signal defeated

enum State { AT_WORK, FLUNG, DOWN, WAITING, RISING, FIGHT, DEAD, SCRIPTED }
enum Move { NONE, DASH, SPIN, SLAM, STAGGER }

const MAX_HEALTH := 600.0
const RISE_TIME := 1.2
const WALK_SPEED := 2.2
const STOP_AT := 2.0
const TURN_RATE := 6.0
const RADIUS := 0.38
const HEIGHT := 1.85
## Between moves, a while (random in the range).
const REST := Vector2(0.8, 1.6)

## (Note 110: wind 0.65 -> 0.85 and the run 0.32 -> 0.4 s, so it is seen coming
## and seen go; too close, he hops back DASH_BACK first.)
const DASH_WIND := 0.85
const DASH_TIME := 0.4
const DASH_BACK := 2.6
const DASH_CLOSE := 3.5
const DASH_SPEED := 17.0
const DASH_DAMAGE := 28.0
const DASH_REACH := 0.9
const DASH_RECOVER := 0.6

const SPIN_RISE := 0.45
const SPIN_TIME := 1.3
const SPIN_RATE := 15.0
const SPIN_REACH := 2.5
const SPIN_DAMAGE := 12.0
const SPIN_EVERY := 0.3
const SPIN_DOWN := 0.4
const SPIN_DIZZY := 0.7

const SLAM_CROUCH := 0.35
const SLAM_RISE := 0.45
const SLAM_HANG := 0.55
const SLAM_DROP := 0.22
const SLAM_HEIGHT := 3.4
const SLAM_DAMAGE := 34.0
const SLAM_HIT := 2.0
const SLAM_KNOCK := 3.8
const SLAM_LIE := 1.4
const SLAM_UP := 0.6
## On his back after the slam, blows land this much harder.
const SLAM_EXPOSED := 1.5

const STAGGER_TIME := 1.4

@export var display_name := "THE SURGEON"
var max_health := MAX_HEALTH
var health := MAX_HEALTH
## Read by the HUD for the boss bar.
var engaged := false
var state: State = State.AT_WORK
var move: Move = Move.NONE
## The hall (surgery.gd): `in_hall(world)`, its table for sparks and dust.
var surgery: Node3D
var _wait_at := Transform3D.IDENTITY
var _t := 0.0
var _mt := 0.0
var _next_move := 0.0
var _move_dir := Vector3.FORWARD
var _move_at := Vector3.ZERO
var _move_from := Vector3.ZERO
var _hit_once := {}
var _spin_yaw := 0.0
var _cued := false
var _target: Node3D = null


func _ready() -> void:
	add_to_group(&"boss")
	add_to_group(&"surgeon")
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	collision_layer = 1 | 4
	collision_mask = 1 | 2
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(cs)
	_build_body()
	pose(&"work")


func _set_state(s: State) -> void:
	state = s
	_t = 0.0
	engaged = s == State.FIGHT
	if s != State.FIGHT:
		move = Move.NONE


# --- His body (a stand-in: primitives) -------------------------------------------------

var _rig: Node3D
var _j := {}
var _want := {}
var _rig_pos := Vector3.ZERO
var _rig_rot := Vector3.ZERO
var _back: Node3D
var _needle: MeshInstance3D
var _needle_light: OmniLight3D
var _walk_ph := 0.0
var _walking := 0.0
var _pose_name := &"stand"

static var _mats := {}


static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"coat":
			m.albedo_color = Color(0.17, 0.14, 0.12)
			m.roughness = 0.92
		"apron":
			m.albedo_color = Color(0.3, 0.2, 0.14)
			m.roughness = 0.75
		"skin":
			m.albedo_color = Color(0.74, 0.64, 0.58)
			m.roughness = 0.6
		"steel":
			# Not too metallic: in the hall's dark, a mirror-steel reads black.
			m.albedo_color = Color(0.56, 0.57, 0.62)
			m.metallic = 0.5
			m.roughness = 0.4
		"brass":
			m.albedo_color = Color(0.7, 0.52, 0.24)
			m.metallic = 0.6
			m.roughness = 0.35
			m.emission_enabled = true
			m.emission = Color(1.0, 0.6, 0.25)
			m.emission_energy_multiplier = 0.25
		"lens":
			m.albedo_color = Color(0.3, 0.02, 0.0)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.2, 0.08)
			m.emission_energy_multiplier = 3.0
		"needle":
			m.albedo_color = Color(0.8, 0.84, 0.88)
			m.metallic = 1.0
			m.roughness = 0.1
			m.emission_enabled = true
			m.emission = Color(0.55, 0.85, 1.0)
			m.emission_energy_multiplier = 0.6
	_mats[key] = m
	return m


func _part(parent: Node3D, mesh: Mesh, mat: String, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(mat)
	parent.add_child(mi)
	mi.position = at
	mi.rotation = rot
	return mi


func _joint(parent: Node3D, key: StringName, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = String(key)
	parent.add_child(n)
	n.position = at
	_j[key] = n
	_want[key] = Vector3.ZERO
	return n


static func _cyl(r: float, h: float, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r if top < 0.0 else top
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


static func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build_body() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	var pelvis := _joint(_rig, &"pelvis", Vector3(0.0, 1.0, 0.0))
	# The man: a long dark coat, a leather apron, a bald head, goggles.
	_part(pelvis, _boxm(Vector3(0.46, 0.66, 0.28)), "coat", Vector3(0.0, 0.36, 0.0))
	_part(pelvis, _cyl(0.36, 0.62, 0.25), "coat", Vector3(0.0, -0.15, 0.0))
	_part(pelvis, _boxm(Vector3(0.34, 0.8, 0.03)), "apron", Vector3(0.0, 0.05, 0.15))
	_part(pelvis, _boxm(Vector3(0.48, 0.05, 0.3)), "brass", Vector3(0.0, 0.45, 0.0))
	_part(pelvis, _boxm(Vector3(0.48, 0.06, 0.3)), "brass", Vector3(0.0, 0.02, 0.0))
	var neck := _joint(pelvis, &"neck", Vector3(0.0, 0.7, 0.0))
	_part(neck, _cyl(0.06, 0.1), "skin", Vector3(0.0, 0.03, 0.0))
	_part(neck, _ball(0.14), "skin", Vector3(0.0, 0.18, 0.01))
	_part(neck, _boxm(Vector3(0.17, 0.07, 0.1)), "steel", Vector3(0.0, 0.1, 0.08))
	for s: float in [-1.0, 1.0]:
		_part(neck, _cyl(0.038, 0.04), "lens", Vector3(0.055 * s, 0.2, 0.13), Vector3(PI * 0.5, 0.0, 0.0))
	_part(neck, _boxm(Vector3(0.3, 0.025, 0.02)), "brass", Vector3(0.0, 0.2, 0.115))
	# Iron arms: brass shoulders, steel shafts. His right (-X) ends in the needle.
	for side in [[&"l", 1.0], [&"r", -1.0]]:
		var k: StringName = side[0]
		var s: float = side[1]
		var sh := _joint(pelvis, StringName("sh_" + k), Vector3(0.3 * s, 0.6, 0.0))
		_part(sh, _ball(0.085), "brass", Vector3.ZERO)
		_part(sh, _cyl(0.055, 0.32), "steel", Vector3(0.0, -0.16, 0.0))
		var el := _joint(sh, StringName("el_" + k), Vector3(0.0, -0.32, 0.0))
		_part(el, _ball(0.065), "brass", Vector3.ZERO)
		_part(el, _cyl(0.048, 0.3), "steel", Vector3(0.0, -0.15, 0.0))
		var wr := _joint(el, StringName("wr_" + k), Vector3(0.0, -0.3, 0.0))
		_part(wr, _ball(0.05), "brass", Vector3.ZERO)
		if k == &"r":
			# The precision needle: a long tapering steel spike.
			_needle = _part(wr, _cyl(0.0, 0.85, 0.035), "needle", Vector3(0.0, -0.44, 0.0))
			_needle_light = OmniLight3D.new()
			_needle_light.light_color = Color(0.55, 0.85, 1.0)
			_needle_light.omni_range = 2.5
			_needle_light.light_energy = 0.0
			_needle_light.shadow_enabled = false
			wr.add_child(_needle_light)
			_needle_light.position = Vector3(0.0, -0.86, 0.0)
			_part(wr, _cyl(0.06, 0.06), "brass", Vector3(0.0, -0.03, 0.0))
		else:
			# A three-fingered clamp.
			for f in 3:
				var a := float(f) * TAU / 3.0
				_part(wr, _boxm(Vector3(0.025, 0.14, 0.025)), "steel", Vector3(cos(a) * 0.04, -0.09, sin(a) * 0.04), Vector3(sin(a) * 0.3, 0.0, -cos(a) * 0.3))
		# Iron legs.
		var hp := _joint(pelvis, StringName("hp_" + k), Vector3(0.13 * s, -0.05, 0.0))
		_part(hp, _ball(0.08), "brass", Vector3.ZERO)
		_part(hp, _cyl(0.068, 0.45), "steel", Vector3(0.0, -0.225, 0.0))
		var kn := _joint(hp, StringName("kn_" + k), Vector3(0.0, -0.45, 0.0))
		_part(kn, _ball(0.072), "brass", Vector3.ZERO)
		_part(kn, _cyl(0.058, 0.42), "steel", Vector3(0.0, -0.21, 0.0))
		var an := _joint(kn, StringName("an_" + k), Vector3(0.0, -0.42, 0.0))
		_part(an, _ball(0.055), "brass", Vector3.ZERO)
		_part(an, _boxm(Vector3(0.12, 0.07, 0.27)), "steel", Vector3(0.0, -0.04, 0.06))
	# Where the claw rides: high on his back.
	_back = Node3D.new()
	_back.name = "Back"
	pelvis.add_child(_back)
	_back.position = Vector3(0.0, 0.42, -0.2)
	for mi in _rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## A named pose's joint angles (Euler, radians) and the rig's offset and turn.
## (An arm hangs down its -Y: -x lifts it forward, +-z out to the side.)
func _pose_angles(p: StringName) -> Dictionary:
	var a := {}
	var rig := [Vector3.ZERO, Vector3.ZERO]
	match p:
		&"stand":
			a = {&"sh_l": Vector3(0.05, 0.0, 0.14), &"sh_r": Vector3(0.05, 0.0, -0.14),
				&"el_l": Vector3(-0.3, 0.0, 0.0), &"el_r": Vector3(-0.2, 0.0, 0.0)}
		&"work":
			a = {&"sh_l": Vector3(-0.9, 0.0, 0.1), &"sh_r": Vector3(-0.9, 0.0, -0.1),
				&"el_l": Vector3(-0.8, 0.0, 0.0), &"el_r": Vector3(-0.8, 0.0, 0.0), &"neck": Vector3(0.35, 0.0, 0.0)}
		&"alert":
			a = {&"sh_l": Vector3(-0.5, 0.0, 0.35), &"sh_r": Vector3(-0.6, 0.0, -0.35),
				&"el_l": Vector3(-1.1, 0.0, 0.0), &"el_r": Vector3(-0.6, 0.0, 0.0)}
		&"reach":
			a = {&"sh_l": Vector3(-2.9, 0.0, 0.15), &"sh_r": Vector3(-2.9, 0.0, -0.15),
				&"el_l": Vector3(-0.2, 0.0, 0.0), &"el_r": Vector3(-0.2, 0.0, 0.0), &"neck": Vector3(-0.5, 0.0, 0.0)}
		&"strike":
			a = {&"sh_l": Vector3(-1.5, 0.0, 0.9), &"sh_r": Vector3(-0.3, 0.0, -0.2),
				&"el_l": Vector3(-0.1, 0.0, 0.0), &"el_r": Vector3(-0.3, 0.0, 0.0)}
		&"loom":
			# Over someone on the floor, looking down at them.
			a = {&"sh_l": Vector3(0.1, 0.0, 0.25), &"sh_r": Vector3(-0.35, 0.0, -0.2),
				&"el_l": Vector3(-0.4, 0.0, 0.0), &"el_r": Vector3(-0.2, 0.0, 0.0), &"neck": Vector3(0.6, 0.0, 0.0)}
			rig = [Vector3.ZERO, Vector3(0.18, 0.0, 0.0)]
		&"dash_wind":
			a = {&"sh_l": Vector3(-0.9, 0.0, 0.4), &"sh_r": Vector3(1.1, 0.0, -0.25),
				&"el_l": Vector3(-0.5, 0.0, 0.0), &"el_r": Vector3(0.35, 0.0, 0.0),
				&"hp_l": Vector3(-0.7, 0.0, 0.0), &"kn_l": Vector3(1.0, 0.0, 0.0),
				&"hp_r": Vector3(0.3, 0.0, 0.0), &"kn_r": Vector3(0.6, 0.0, 0.0)}
			rig = [Vector3(0.0, -0.22, 0.0), Vector3(0.15, 0.0, 0.0)]
		&"dash":
			a = {&"sh_l": Vector3(0.6, 0.0, 0.5), &"sh_r": Vector3(-1.57, 0.0, 0.0),
				&"el_l": Vector3(-0.3, 0.0, 0.0), &"el_r": Vector3(0.0, 0.0, 0.0),
				&"hp_l": Vector3(-0.8, 0.0, 0.0), &"kn_l": Vector3(0.5, 0.0, 0.0),
				&"hp_r": Vector3(0.6, 0.0, 0.0), &"kn_r": Vector3(0.2, 0.0, 0.0)}
			rig = [Vector3(0.0, -0.15, 0.0), Vector3(0.45, 0.0, 0.0)]
		&"spin":
			# Arms and legs flung out, up on the claw's fingers.
			a = {&"sh_l": Vector3(0.0, 0.0, 1.5), &"sh_r": Vector3(0.0, 0.0, -1.5),
				&"el_l": Vector3.ZERO, &"el_r": Vector3.ZERO,
				&"hp_l": Vector3(0.0, 0.0, 1.1), &"hp_r": Vector3(0.0, 0.0, -1.1)}
			rig = [Vector3(0.0, 0.5, 0.0), Vector3.ZERO]
		&"crouch":
			a = {&"sh_l": Vector3(0.6, 0.0, 0.3), &"sh_r": Vector3(0.6, 0.0, -0.3),
				&"hp_l": Vector3(-1.1, 0.0, 0.0), &"hp_r": Vector3(-1.1, 0.0, 0.0),
				&"kn_l": Vector3(2.0, 0.0, 0.0), &"kn_r": Vector3(2.0, 0.0, 0.0)}
			rig = [Vector3(0.0, -0.45, 0.0), Vector3(0.3, 0.0, 0.0)]
		&"tuck":
			a = {&"sh_l": Vector3(-1.2, 0.0, 0.5), &"sh_r": Vector3(-1.2, 0.0, -0.5),
				&"el_l": Vector3(-1.2, 0.0, 0.0), &"el_r": Vector3(-1.2, 0.0, 0.0),
				&"hp_l": Vector3(-1.5, 0.0, 0.0), &"hp_r": Vector3(-1.5, 0.0, 0.0),
				&"kn_l": Vector3(2.0, 0.0, 0.0), &"kn_r": Vector3(2.0, 0.0, 0.0)}
		&"back":
			# On his back, arms and legs up and out (the slam, after it).
			a = {&"sh_l": Vector3(-1.2, 0.0, 0.9), &"sh_r": Vector3(-1.2, 0.0, -0.9),
				&"hp_l": Vector3(-0.9, 0.0, 0.4), &"hp_r": Vector3(-0.9, 0.0, -0.4),
				&"kn_l": Vector3(0.8, 0.0, 0.0), &"kn_r": Vector3(0.8, 0.0, 0.0)}
			rig = [Vector3(0.0, 1.0, -0.3), Vector3(-PI * 0.5, 0.0, 0.0)]
		&"down", &"dead":
			# Flat on the floor, on his back.
			a = {&"sh_l": Vector3(-0.3, 0.0, 1.0), &"sh_r": Vector3(-0.2, 0.0, -0.8),
				&"hp_l": Vector3(0.0, 0.0, 0.2), &"hp_r": Vector3(0.0, 0.0, -0.15),
				&"el_l": Vector3(-0.4, 0.0, 0.0), &"neck": Vector3(-0.3, 0.3, 0.0)}
			rig = [Vector3(0.0, 0.2, -0.95), Vector3(-PI * 0.5, 0.0, 0.0)]
		&"dizzy":
			a = {&"sh_l": Vector3(0.2, 0.0, 0.5), &"sh_r": Vector3(0.2, 0.0, -0.5),
				&"neck": Vector3(0.3, 0.0, 0.3), &"kn_l": Vector3(0.3, 0.0, 0.0), &"kn_r": Vector3(0.3, 0.0, 0.0)}
			rig = [Vector3(0.0, -0.08, 0.0), Vector3(0.1, 0.0, 0.15)]
	return {"joints": a, "rig": rig}


## Holds pose `p` (joints not named in it go back to rest).
func pose(p: StringName) -> void:
	_pose_name = p
	var d := _pose_angles(p)
	for k in _want:
		_want[k] = Vector3.ZERO
	for k in d["joints"]:
		_want[k] = d["joints"][k]
	_rig_pos = d["rig"][0]
	_rig_rot = d["rig"][1]


## The joints eased toward their pose (snapped with `rate` 0); walking swings
## the legs and arms on top of it.
func _animate(delta: float, rate := 12.0) -> void:
	var k := 1.0 if rate <= 0.0 else clampf(rate * delta, 0.0, 1.0)
	var swing := sin(_walk_ph) * _walking
	for key in _want:
		var w: Vector3 = _want[key]
		match key:
			&"hp_l":
				w.x += -swing * 0.55
			&"hp_r":
				w.x += swing * 0.55
			&"kn_l":
				w.x += maxf(0.0, swing) * 0.9
			&"kn_r":
				w.x += maxf(0.0, -swing) * 0.9
			&"sh_l":
				w.x += swing * 0.35
		var j: Node3D = _j[key]
		j.rotation = j.rotation.lerp(w, k)
	_rig_at = _rig_at.lerp(_rig_pos + Vector3(0.0, absf(swing) * 0.04, 0.0), k)
	_rig.position = _rig_at
	if _jolt > 0.001:
		var t := Time.get_ticks_msec() / 1000.0
		_rig.position += Vector3(sin(t * 61.0), sin(t * 47.0) * 0.5, cos(t * 53.0)) * 0.05 * _jolt
		_jolt = maxf(_jolt - delta * 3.0, 0.0)
	var spin := Vector3(0.0, _spin_yaw, 0.0) if move == Move.SPIN else Vector3.ZERO
	_rig.rotation = _rig.rotation.lerp(_rig_rot + spin, k) if move != Move.SPIN else _rig_rot + spin
	_pose_claw(delta)


func _process(delta: float) -> void:
	_animate(delta)


# --- The claw on his back -------------------------------------------------------------------

var _claw: Node3D
var _claw_skel: Skeleton3D
var _claw_open := -0.2
var _claw_mode := &"carry"
const CLAW_FINGERS: Array[float] = [30.0, 150.0, 270.0]


## The claw off the machine's arm (surgical_table.gd `take_claw`) onto his back.
func mount_claw(claw: Node3D) -> void:
	if claw == null:
		return
	_claw = claw
	if claw.get_parent() != null:
		claw.get_parent().remove_child(claw)
	_back.add_child(claw)
	claw.top_level = false
	var found := claw.find_children("*", "Skeleton3D", true, false)
	_claw_skel = found[0] as Skeleton3D if not found.is_empty() else null
	# Its old hitbox (a blow rang off the machine) is no longer anything.
	for b in claw.find_children("*", "StaticBody3D", true, false):
		(b as StaticBody3D).collision_layer = 0
	var eye := claw.get_node_or_null("EyeLight") as OmniLight3D
	if eye != null:
		eye.visible = true
		eye.light_energy = 1.0
	_claw_mode = &"carry"
	claw.transform = _claw_pose(&"carry")


func has_claw() -> bool:
	return _claw != null


## Where the claw is on him (world): its hub.
func claw_point() -> Vector3:
	return _claw.global_position if _claw != null else _back.global_position


## The claw torn off his back (note 111, surgery_control.gd `_take_his_claw`):
## handed over where it lies -- the caller gives it a new parent -- and no
## longer posed here.
func unmount_claw() -> Node3D:
	var c := _claw
	if c == null:
		return null
	_claw = null
	_claw_skel = null
	var at := c.global_transform
	c.get_parent().remove_child(c)
	c.transform = at
	return c


## The claw gone from him for good (a save made after it was taken).
func drop_claw_now() -> void:
	var c := unmount_claw()
	if c != null:
		c.queue_free()


## His body yanked about (the claw wrenched off him): a shake of the whole rig
## `amount` strong, dying away.
var _jolt := 0.0
var _rig_at := Vector3.ZERO


func jolt(amount: float) -> void:
	_jolt = maxf(_jolt, amount)


## The claw on his back by mode: folded up over his shoulder; let down and
## lengthened under him as legs; out of his back, fingers first.
func _claw_pose(mode: StringName) -> Transform3D:
	match mode:
		&"legs":
			# Its fingertips on the floor: the socket 1.92 up with him raised 0.5,
			# the claw 2.21 long at full size (the bigger claw, note 110).
			return Transform3D(Basis().scaled(Vector3.ONE * 0.87), Vector3(0.0, 0.0, -0.05))
		&"back":
			return Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * 0.65), Vector3.ZERO)
	return Transform3D(Basis(Vector3.RIGHT, PI - 0.45).scaled(Vector3.ONE * 0.6), Vector3(-0.08, 0.05, 0.0))


func _pose_claw(delta: float) -> void:
	if _claw == null:
		return
	var want := _claw_pose(_claw_mode)
	_claw.transform = _claw.transform.interpolate_with(want, clampf(delta * 10.0, 0.0, 1.0))
	if _claw_skel != null:
		var goal := -0.2
		match _claw_mode:
			&"legs":
				goal = 0.6
			&"back":
				goal = 0.75 if move == Move.SLAM and _mt < SLAM_CROUCH + SLAM_RISE + SLAM_HANG + SLAM_DROP else -0.3
		_claw_open = lerpf(_claw_open, goal, clampf(delta * 8.0, 0.0, 1.0))
		for f in CLAW_FINGERS.size():
			var a := deg_to_rad(CLAW_FINGERS[f])
			_claw_skel.set_bone_pose_rotation(f + 1, Quaternion(Vector3(-sin(a), 0.0, cos(a)), _claw_open))


# --- Moments (the scenes, surgery_control.gd) -----------------------------------------------

## Lying in the hall where the kick put him, out cold.
func lie_down() -> void:
	_set_state(State.DOWN)
	velocity = Vector3.ZERO
	pose(&"down")


## Kept for surgery_control.gd: the old clips' names as poses.
func play(key: StringName, _blend := 0.2, _speed := 1.0, _loop := false) -> void:
	match key:
		&"die":
			pose(&"down")
		&"alert":
			pose(&"alert")
		&"work":
			pose(&"work")
		_:
			pose(key)


func hold_end(key: StringName) -> void:
	play(key)
	_animate(1.0, 0.0)


## In a scene: walked and posed by it.
func script_on() -> void:
	_set_state(State.SCRIPTED)
	velocity = Vector3.ZERO


## Turned to world heading `yaw` (his +Z). He is a child of the surgery (or its
## booth), which is turned, so a world heading written into `rotation.y` was off
## by the room's turn -- sideways in a room turned 90 degrees (note 119).
func _face_yaw(yaw: float) -> void:
	var r := global_rotation
	r.y = yaw
	global_rotation = r


## Turns to face `at` (world) at once.
func face(at: Vector3) -> void:
	var to := at - global_position
	if Vector2(to.x, to.z).length() > 0.01:
		_face_yaw(atan2(to.x, to.z))


## Walks (a scene) to `target` (world) round the vats, at WALK_SPEED; returns
## when he is there (or after `timeout`).
func walk_to(target: Vector3, timeout := 14.0) -> void:
	pose(&"stand")
	_replan(target)
	var t0 := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t0 < timeout:
		var to := target - global_position
		to.y = 0.0
		if to.length() < 0.25:
			break
		var dir := _steer(to)
		var delta := get_physics_process_delta_time()
		global_position += dir * minf(WALK_SPEED * delta, to.length())
		_face_yaw(lerp_angle(global_rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-TURN_RATE * delta)))
		_walking = 1.0
		_walk_ph += delta * WALK_SPEED * 3.2
		if _path_i >= _path.size():
			_replan(target)
		await get_tree().physics_frame
	_walking = 0.0


## Up (or down) onto `to` (world) in a hop over `time`.
func hop_to(to: Vector3, time := 0.5) -> void:
	var from := global_position
	pose(&"crouch")
	await get_tree().create_timer(0.2, true, false, true).timeout
	pose(&"tuck")
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		var p := from.lerp(to, k)
		p.y += sin(k * PI) * 0.7
		global_position = p, 0.0, 1.0, time)
	await t.finished
	pose(&"stand")


# --- Moments (saves, resets) -------------------------------------------------------------------

## Where he waits for the fight (world), on his feet.
func wait_at(at: Transform3D) -> void:
	_wait_at = at
	global_transform = at
	health = max_health
	velocity = Vector3.ZERO
	visible = true
	collision_layer = 1 | 4
	_set_state(State.WAITING)
	pose(&"alert")


## The fight is on (after the scene that gives him the claw, or a player come
## in to find him waiting). `now`: straight into it, no getting up.
func begin_fight(now := false) -> void:
	if state in [State.RISING, State.FIGHT, State.DEAD]:
		return
	_wait_at = global_transform
	if now:
		_set_state(State.FIGHT)
		_next_move = 0.6
		pose(&"stand")
		fight_started.emit()
		return
	_set_state(State.RISING)
	pose(&"alert")


## A world reset with him still up: whole again, back where he waits.
func reset_wait() -> void:
	if state == State.DEAD:
		return
	_claw_mode = &"carry"
	wait_at(_wait_at if _wait_at != Transform3D.IDENTITY else global_transform)


## A save with him dead: lying where he fell.
func set_dead_now(at: Transform3D) -> void:
	global_transform = at
	health = 0.0
	collision_layer = 0
	_set_state(State.DEAD)
	hold_end(&"dead")


func is_dead() -> bool:
	return state == State.DEAD


# --- Each tick ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.WAITING:
			if _player_in_hall() != null:
				begin_fight()
		State.RISING:
			if _t >= RISE_TIME:
				_set_state(State.FIGHT)
				_next_move = 0.5
				pose(&"stand")
				fight_started.emit()
		State.FIGHT:
			_fight(delta)


## The fight: between moves he walks at the nearest player round the vats; when
## his rest is up he picks a move by how far they are.
func _fight(delta: float) -> void:
	_target = Coop.nearest(global_position) as Node3D
	if move != Move.NONE:
		_run_move(delta)
		return
	if _target == null:
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.01:
		_face_yaw(lerp_angle(global_rotation.y, atan2(to.x, to.z), 1.0 - exp(-TURN_RATE * delta)))
	_next_move -= delta
	if _next_move <= 0.0 and dist < 12.0:
		_start_move(dist)
		if move != Move.NONE:
			return
	var dir := Vector3.ZERO
	if dist > STOP_AT:
		if _t >= _replan_at or _path_i >= _path.size():
			_replan(_target.global_position)
		dir = _steer(to)
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	_walking = 1.0 if dir != Vector3.ZERO else 0.0
	_walk_ph += delta * WALK_SPEED * 3.2 * _walking
	if _pose_name != &"stand":
		pose(&"stand")


## Note 110 ("I didnt see the spear dash"): he no longer picks by distance and
## chance -- the needle came only at range, and rarely -- but deals his three
## moves round in turn (a fresh shuffle each round, the needle first in the
## fight). The spin waits until they are within SPIN_NEAR (or he has walked at
## them DEAL_WAIT and gives up on it for the next); the needle, too close, backs
## off first (`_dash`).
var _deck: Array[Move] = []
var _held := 0.0
const SPIN_NEAR := 3.6
const DEAL_WAIT := 3.0


func _start_move(dist: float) -> void:
	if _deck.is_empty():
		_deck = [Move.DASH, Move.SPIN, Move.SLAM]
		_deck.shuffle()
		if _first_round:
			_first_round = false
			_deck.erase(Move.DASH)
			_deck.push_front(Move.DASH)
	var m: Move = _deck[0]
	if m == Move.SPIN and dist > SPIN_NEAR and _held < DEAL_WAIT:
		# Closer first: on walking at them.
		_held += get_physics_process_delta_time()
		_next_move = 0.0
		return
	_deck.pop_front()
	_held = 0.0
	begin_move(m)


var _first_round := true


## Into move `m` (the fight picks; a test may too).
func begin_move(m: Move) -> void:
	move = m
	_mt = 0.0
	_cued = false
	_hit_once.clear()
	_walking = 0.0
	_move_from = global_position
	velocity = Vector3.ZERO
	match m:
		Move.DASH:
			pose(&"dash_wind")
			if _target == null:
				_target = Coop.nearest(global_position) as Node3D
			_backing = _target != null and _target.global_position.distance_to(global_position) < DASH_CLOSE
		Move.SPIN:
			_claw_mode = &"legs"
			pose(&"spin")
			_spin_yaw = 0.0
		Move.SLAM:
			pose(&"crouch")
			_claw_mode = &"back"


func _end_move() -> void:
	_needle_glow(0.6)
	_streaked = false
	_backing = false
	move = Move.NONE
	_claw_mode = &"carry"
	_next_move = randf_range(REST.x, REST.y)
	_spin_yaw = 0.0
	pose(&"stand")


func _run_move(delta: float) -> void:
	_mt += delta
	match move:
		Move.DASH:
			_dash(delta)
		Move.SPIN:
			_spin(delta)
		Move.SLAM:
			_slam(delta)
		Move.STAGGER:
			velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
			move_and_slide()
			if _mt >= STAGGER_TIME:
				_end_move()


## The needle drawn back, then driven straight through where they were.
func _dash(delta: float) -> void:
	# The needle's glow: building through the wind-up, blazing on the run.
	var glow := 0.6
	if _mt < DASH_WIND:
		glow = lerpf(0.6, 7.0, clampf(_mt / DASH_WIND, 0.0, 1.0))
	elif _mt < DASH_WIND + DASH_TIME:
		glow = 9.0
	_needle_glow(glow)
	if _mt < DASH_WIND:
		# Too close for it: a hop back first (decided in begin_move), then the wind-up.
		if _backing and _mt < 0.35:
			var away := global_position - _target.global_position
			away.y = 0.0
			away = away.normalized() if away.length() > 0.01 else -global_basis.z
			velocity = away * (DASH_BACK / 0.35)
			velocity.y = 0.0
			move_and_slide()
		if _target != null:
			var to := _target.global_position + (_target.get("velocity") as Vector3) * 0.2 - global_position
			to.y = 0.0
			if to.length() > 0.01:
				_move_dir = to.normalized()
				_face_yaw(lerp_angle(global_rotation.y, atan2(to.x, to.z), 1.0 - exp(-14.0 * delta)))
		if not _cued and _mt >= DASH_WIND - 0.3:
			_cue(0.3 + DASH_TIME)
		return
	if _mt < DASH_WIND + DASH_TIME:
		if _pose_name != &"dash":
			pose(&"dash")
			_dash_from = global_position
		velocity = _move_dir * DASH_SPEED
		var before := global_position
		move_and_slide()
		var tip := global_position + Vector3(0.0, 1.35, 0.0) + _move_dir * 1.2
		for p in Coop.all():
			var n := p as Node3D
			if _hit_once.has(n) or n.get("_dead") == true:
				continue
			var mid := n.global_position + Vector3(0.0, 1.0, 0.0)
			var seg := Geometry3D.get_closest_point_to_segment(mid, before + Vector3(0.0, 1.35, 0.0), tip)
			if seg.distance_to(mid) < DASH_REACH:
				_hit_once[n] = true
				_hit(n, DASH_DAMAGE, _move_dir)
				if move != Move.DASH:
					return
		# Stopped by stone, a vat: the dash is over.
		if get_slide_collision_count() > 0 and (global_position - before).length() < DASH_SPEED * delta * 0.4:
			_mt = DASH_WIND + DASH_TIME
		return
	if not _streaked:
		_streaked = true
		_streak(_dash_from, global_position)
	velocity = Vector3.ZERO
	pose(&"stand")
	if _mt >= DASH_WIND + DASH_TIME + DASH_RECOVER:
		_end_move()


## Up on the claw, arms and legs out, spinning; anyone in reach cut.
func _spin(delta: float) -> void:
	if _mt < SPIN_RISE:
		if not _cued and _mt >= SPIN_RISE - 0.25:
			for p in Coop.all():
				if (p as Node3D).global_position.distance_to(global_position) < SPIN_REACH + 2.0:
					_cue_one(p, 0.6)
			_cued = true
		return
	if _mt < SPIN_RISE + SPIN_TIME:
		_spin_yaw += SPIN_RATE * delta
		# Drifting after them as it spins.
		if _target != null:
			var to := _target.global_position - global_position
			to.y = 0.0
			velocity = to.normalized() * 1.6 if to.length() > 1.0 else Vector3.ZERO
			move_and_slide()
		for p in Coop.all():
			var n := p as Node3D
			if n.get("_dead") == true:
				continue
			var gap := Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z).length()
			var due: float = _hit_once.get(n, -1.0)
			if gap < SPIN_REACH and _mt >= due:
				_hit_once[n] = _mt + SPIN_EVERY
				var dir := (n.global_position - global_position)
				dir.y = 0.0
				_hit(n, SPIN_DAMAGE, dir.normalized())
				if move != Move.SPIN:
					return
		return
	if _mt < SPIN_RISE + SPIN_TIME + SPIN_DOWN:
		_spin_yaw = lerpf(_spin_yaw, roundf(_spin_yaw / TAU) * TAU, 0.3)
		_claw_mode = &"carry"
		pose(&"dizzy")
		return
	if _mt >= SPIN_RISE + SPIN_TIME + SPIN_DOWN + SPIN_DIZZY:
		_end_move()


## A crouch, a leap, a hang at the top turning onto his back, and down
## claw-first on where they stood; then on his back a while.
func _slam(delta: float) -> void:
	var rise_at := SLAM_CROUCH
	var hang_at := rise_at + SLAM_RISE
	var drop_at := hang_at + SLAM_HANG
	var land_at := drop_at + SLAM_DROP
	var floor_y := _move_from.y
	if _mt < rise_at:
		if _target != null:
			_move_at = _target.global_position
		return
	if _mt < hang_at:
		pose(&"tuck")
		var k := (_mt - rise_at) / SLAM_RISE
		var flat := _move_from.lerp(_move_at, k * 0.6)
		global_position = Vector3(flat.x, floor_y + SLAM_HEIGHT * sin(k * PI * 0.5), flat.z)
		return
	if _mt < drop_at:
		# The hang: turning over onto his back, still following them a little.
		pose(&"back")
		if _target != null:
			_move_at = _move_at.lerp(_target.global_position, clampf(delta * 2.0, 0.0, 1.0))
		if not _cued:
			_cued = true
			for p in Coop.all():
				_cue_one(p, SLAM_HANG + SLAM_DROP)
		var top := _move_from.lerp(_move_at, 0.6)
		global_position = Vector3(top.x, floor_y + SLAM_HEIGHT + 0.15 * sin(_mt * 9.0), top.z)
		return
	if _mt < land_at:
		var k := (_mt - drop_at) / SLAM_DROP
		var top := _move_from.lerp(_move_at, 0.6)
		var p := top.lerp(_move_at, k)
		global_position = Vector3(p.x, floor_y + SLAM_HEIGHT * (1.0 - k * k), p.z)
		return
	if not _cued_land:
		_cued_land = true
		global_position = Vector3(_move_at.x, floor_y, _move_at.z)
		_land()
	if _mt >= land_at + SLAM_LIE:
		pose(&"stand")
		_claw_mode = &"carry"
	if _mt >= land_at + SLAM_LIE + SLAM_UP:
		_cued_land = false
		_end_move()


var _cued_land := false


## Down claw-first: the floor cracks; close by, a heavy blow; further, thrown
## down.
func _land() -> void:
	var table: Node = surgery.get("table") if surgery != null else null
	if table != null:
		table.call("_impact_fx", global_position, 1.0)
	for p in Coop.all():
		var n := p as Node3D
		if n.get("_dead") == true:
			continue
		var to := n.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if n.get("_shake") != null:
			n.set("_shake", maxf(float(n.get("_shake")), 0.7 * clampf(1.0 - d / 12.0, 0.0, 1.0)))
		if d > SLAM_KNOCK:
			continue
		var dir := to.normalized() if d > 0.01 else Vector3.FORWARD
		var guard := 0
		if d < SLAM_HIT:
			guard = _hit(n, SLAM_DAMAGE, dir)
		if guard == 0 and n.has_method("knock_down"):
			n.call("knock_down", dir, 6.5)


# --- Hitting them ------------------------------------------------------------------------

## The parry cue for everyone near (player.gd `parry_cue`).
func _cue(listen: float) -> void:
	_cued = true
	for p in Coop.all():
		_cue_one(p, listen)


func _cue_one(p: Node, listen: float) -> void:
	if p.has_method("parry_cue"):
		p.call("parry_cue", self, listen)


## A blow on `p`: 0 it landed, 1 blocked, 2 parried (and he is staggered).
func _hit(p: Node3D, amount: float, dir: Vector3) -> int:
	var got := [0]
	var watch := func(parry: bool, attacker: Node3D) -> void:
		if attacker == self:
			got[0] = 2 if parry else 1
	if p.has_signal("guarded"):
		p.connect("guarded", watch)
	if p.has_method("take_damage"):
		p.call("take_damage", amount, dir, self)
	if p.has_signal("guarded") and p.is_connected("guarded", watch):
		p.disconnect("guarded", watch)
	if got[0] == 2 and move in [Move.DASH, Move.SPIN]:
		_stagger(-dir)
	return got[0]


## Thrown off a parry: staggered, open.
func _stagger(away: Vector3) -> void:
	_needle_glow(0.6)
	move = Move.STAGGER
	_mt = 0.0
	_claw_mode = &"carry"
	_spin_yaw = 0.0
	velocity = Vector3(away.x, 0.0, away.z) * 5.0
	pose(&"dizzy")


# --- Finding his way round the vats ------------------------------------------------------
##
## The vats are not in the level's navmesh (they move), and he walked straight
## into them and stood there. So he finds his own way across the hall: an
## AStarGrid2D over its floor, GRID_CELL cells, every vat (and the table) solid
## out to its radius plus his, re-made every REPLAN s.

const GRID_CELL := 0.5
const REPLAN := 0.4
var _grid: AStarGrid2D
var _path: PackedVector3Array = PackedVector3Array()
var _path_i := 0
var _replan_at := 0.0
## The cells the hall's fixed things stand in (the booth's posts, the intake's
## crates, the walls' frames): found once, by asking the physics.
var _static: Array[Vector2i] = []


func _find_static(n: int) -> void:
	_static.clear()
	var inner: float = surgery.get("_inner")
	var space := get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(GRID_CELL + RADIUS * 2.0, 1.0, GRID_CELL + RADIUS * 2.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.collision_mask = 2
	q.exclude = [get_rid()]
	for i in n:
		for j in n:
			var l := Vector3(-inner + (float(i) + 0.5) * GRID_CELL, 1.0, -inner + (float(j) + 0.5) * GRID_CELL)
			q.transform = Transform3D(surgery.global_basis, surgery.to_global(l))
			for hit in space.intersect_shape(q, 8):
				var c: Object = hit["collider"]
				# The vats move, and are marked each time; bodies come and go.
				if c is CharacterBody3D or (c is Node and (c as Node).is_in_group(&"surgery_vat")):
					continue
				_static.append(Vector2i(i, j))
				break


func _cell(l: Vector3) -> Vector2i:
	var inner: float = surgery.get("_inner")
	return Vector2i(floori((l.x + inner) / GRID_CELL), floori((l.z + inner) / GRID_CELL))


func _replan(target: Vector3) -> void:
	_replan_at = _t + REPLAN
	_path = PackedVector3Array()
	_path_i = 0
	if surgery == null:
		return
	var inner: float = surgery.get("_inner")
	var n := ceili(inner * 2.0 / GRID_CELL)
	if _grid == null:
		_grid = AStarGrid2D.new()
		_grid.region = Rect2i(0, 0, n, n)
		_grid.cell_size = Vector2(GRID_CELL, GRID_CELL)
		_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		_grid.update()
		_find_static(n)
	_grid.fill_solid_region(_grid.region, false)
	for s in _static:
		_grid.set_point_solid(s, true)
	var blocks: Array = []
	for v in surgery.get("vats"):
		var vat := v as Node3D
		blocks.append([surgery.to_local(vat.global_position), float(vat.get("radius")) + RADIUS + 0.1])
	var table: Node3D = surgery.get("table")
	if table != null:
		blocks.append([surgery.to_local(table.global_position), 1.7 + RADIUS])
	for b in blocks:
		var c: Vector3 = b[0]
		var r: float = b[1]
		var lo := _cell(c - Vector3(r, 0.0, r))
		var hi := _cell(c + Vector3(r, 0.0, r))
		for i in range(maxi(lo.x, 0), mini(hi.x, n - 1) + 1):
			for j in range(maxi(lo.y, 0), mini(hi.y, n - 1) + 1):
				var mid := Vector2(-inner + (float(i) + 0.5) * GRID_CELL, -inner + (float(j) + 0.5) * GRID_CELL)
				if mid.distance_to(Vector2(c.x, c.z)) < r:
					_grid.set_point_solid(Vector2i(i, j), true)
	var from := _cell(surgery.to_local(global_position)).clamp(Vector2i.ZERO, Vector2i(n - 1, n - 1))
	var goal := _cell(surgery.to_local(target)).clamp(Vector2i.ZERO, Vector2i(n - 1, n - 1))
	_grid.set_point_solid(from, false)
	if _grid.is_point_solid(goal):
		# Up on a vat, or the table: to the nearest floor beside it.
		var best := goal
		var best_d := INF
		for i in range(-6, 7):
			for j in range(-6, 7):
				var q := goal + Vector2i(i, j)
				if _grid.is_in_boundsv(q) and not _grid.is_point_solid(q) and Vector2(i, j).length() < best_d:
					best_d = Vector2(i, j).length()
					best = q
		goal = best
	var ids := _grid.get_id_path(from, goal, true)
	for id in ids:
		var l := Vector3(-inner + (float(id.x) + 0.5) * GRID_CELL, 0.0, -inner + (float(id.y) + 0.5) * GRID_CELL)
		_path.append(surgery.to_global(l))
	_path_i = 1 if _path.size() > 1 else 0


## The way to go along the path; straight at them with no path.
func _steer(to: Vector3) -> Vector3:
	while _path_i < _path.size():
		var w := _path[_path_i] - global_position
		w.y = 0.0
		if w.length() > 0.3:
			return w.normalized()
		_path_i += 1
	return to.normalized()


## A player standing in the hall (not in a scene), or null.
func _player_in_hall() -> Node3D:
	if surgery == null:
		return null
	for p in Coop.all():
		var n := p as Node3D
		if n == null or n.get("_dead") == true or n.get("in_cutscene") == true:
			continue
		if bool(surgery.call("in_hall", n.global_position)):
			return n
	return null


# --- Being hit ---------------------------------------------------------------------------


# --- Being hit ---------------------------------------------------------------------------

func take_damage(amount: float, from_direction: Vector3 = Vector3.ZERO, _attacker: Node3D = null) -> void:
	if state != State.FIGHT:
		return
	# On his back after the slam, open.
	if move == Move.SLAM and _cued_land:
		amount *= SLAM_EXPOSED
	health = maxf(health - amount, 0.0)
	var table: Node = surgery.get("table") if surgery != null else null
	if table != null:
		table.call("_sparks", global_position + Vector3(0.0, 1.3, 0.0) - from_direction * 0.3, Color(0.7, 0.08, 0.05), 10)
	if health <= 0.0:
		_die()


## A parry's shove (player.gd `_on_guarded`): staggers him out of the needle or
## the spin; otherwise a small push.
func apply_knockback(impulse: Vector3, _stun_time := 0.0) -> void:
	if state != State.FIGHT:
		return
	if move in [Move.DASH, Move.SPIN]:
		_stagger(impulse.normalized())
		return
	if move == Move.NONE:
		velocity += Vector3(impulse.x, 0.0, impulse.z) * 0.25


func _die() -> void:
	_needle_glow(0.6)
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	_spin_yaw = 0.0
	_claw_mode = &"carry"
	pose(&"dead")
	defeated.emit()


# --- The needle's show (note 110) -----------------------------------------------------------

var _backing := false
var _streaked := false
var _dash_from := Vector3.ZERO


## The needle's glow and the light at its tip (`energy` 0.6 at rest).
func _needle_glow(energy: float) -> void:
	_mat("needle").emission_energy_multiplier = energy
	if _needle_light != null:
		_needle_light.light_energy = maxf(energy - 0.6, 0.0) * 0.5
		_needle_light.visible = energy > 0.7


## A streak of light along the run, from `a` to `b` (world), fading.
func _streak(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.5 or surgery == null:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, length)
	mi.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.55, 0.85, 1.0, 0.8)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surgery.add_child(mi)
	var mid := (a + b) * 0.5 + Vector3(0.0, 1.35, 0.0)
	mi.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), mid)
	var t := mi.create_tween()
	t.tween_property(m, "albedo_color:a", 0.0, 0.5)
	t.tween_callback(mi.queue_free)
	var table: Node = surgery.get("table")
	if table != null:
		table.call("_sparks", b + Vector3(0.0, 1.3, 0.0), Color(0.6, 0.85, 1.0), 14)
