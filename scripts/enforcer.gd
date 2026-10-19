extends "res://scripts/enemy.gd"

## The ENFORCER (2026-10-15; the "warden bot" before): a rusted mech the
## dungeon's keepers built to herd the dead, a cyan crystal burning in its
## chest. (The boss is THE WARDEN; these are his machines.)
##
## The model and its animations are the user's (`models/enforcer.glb`, built by
## tools/build_enforcer.py from models/source/enforcer/ENFORCER_BAKED.blend):
## a 16-bone rig with four BAKED clips -- WALK_BAKED, BEAM_BAKED (the cannon
## arm raised onto the shield arm), BEAM_RECOIL_BAKED (the cannon kicking back
## as it fires) and SWIPE_1_BAKED (the shield drawn back and swept across). Its eyes and its beam glow the crystal's own colour, read off the
## crystal's material.
##
## Made like the archer: the maze puts this script on an enemy.tscn instance
## before it enters the tree (so its numbers live in `_init`); on entering the
## tree it throws the skeleton model away and puts the enforcer in its place.
## The clips are named so enemy.gd's own state animations never match them; this
## script plays them (enemy.gd still advances the player by hand, so far-off
## enforcers are posed less often).
##
## One walks with every skeleton pack (maze.gd `_spawn_enforcer`), keeping close
## to its `escort` while they amble. The prison and the mine (dungeon_room.gd)
## post more of them.
##
## Hunting (`_chase`, enemy.gd's hook):
##   * the BEAM: with a clear line through stone and the player within
##     BEAM_RANGE, it plants itself and raises the cannon (the BEAM_BAKED
##     clip at 1x up to the aim, the crystal and eyes flaring; no beam yet), then fires: BEAM_RECOIL_BAKED plays once and the beam comes on with
##     its kick (RECOIL_BEAM), both arms pitched so the barrel points along it
##     (enforcer_react.gd `aim_at`), and it holds the beam on the player for up
##     to BEAM_TIME:
##     `player.beam_hit` -- BEAM_DPS a second and slowed, a raised guard taking a
##     tenth. It swings after the player at TRACK_RATE; stone stops it, its
##     fellows do not. Then it vents for VENT_TIME.
##   * otherwise it walks in, and close enough it swipes with the shield
##     (SWIPE_1_BAKED at 1x, a move on its own clock: SWIPE_HITS, SWIPE_CUES):
##     `attack_damage`, and a player it catches unguarded is knocked off their
##     feet (`player.knock_down`: thrown back, on the floor, half a second to
##     get up) -- swipe 1 SWIPE1_THROW_SCALE harder. A held guard takes the blow
##     standing, shoved back; a parry throws the enforcer instead. Close in it
##     breaks off a beam for it. Missed or blocked, swipe 1 runs on into swipe 2
##     (SWIPE_2_BAKED), dashing at the player, then swipe 1 again, and so on --
##     THE SWIPE LOOP (SWIPE_CHAIN and below) -- until a blow connects, it is
##     parried (after which it takes the loop up again), or the player is out
##     of LOOP_BREAK.
## Heavy: 240 health, hard to shove, slow on its feet.

const MODEL := preload("res://models/enforcer.glb")
## The mesh is authored 4.42 m tall; drawn at 2.6 m.
const MODEL_SCALE := 0.59
## The model's feet sit this far under its origin at that scale.
const MODEL_LIFT := 0.05
## The clips (tools/build_enforcer.py), all 60 fps.
const ANIM_WALK_CLIP := &"WALK_BAKED"
const ANIM_BEAM_CLIP := &"BEAM_BAKED"
const ANIM_SWIPE_CLIP := &"SWIPE_1_BAKED"
## Firing: starts on BEAM_BAKED's settled pose (measured: the muzzle 0.000 m
## apart) and kicks the cannon back 0.23 m by its frame 18 without returning.
## Played ONCE as the beam fires, then held on its last frame for the rest of
## it (2026-10-17, the user: the beam and the recoil "should work together",
## and "remove any dynamic shaking of the beam arm for now" -- it ping-ponged
## the whole beam). The beam only comes on with the kick: RECOIL_BEAM into the
## clip (frame 9, the cannon starting back fastest), on the fire's own clock.
const ANIM_RECOIL_CLIP := &"BEAM_RECOIL_BAKED"
const RECOIL_BEAM := 8.0 / 60.0
## A clip held on its last frame is held this short of its end (still
## "playing", frozen, rather than finished).
const HOLD_EARLY := 0.04
## The walk's rate changes at most this fast (per second): eased, never jumped
## (a walk starting at full rate reads as a new clip starting). As the
## decrepit's crawl (CLAUDE.md 59).
const WALK_RATE_EASE := 7.0
## A planted foot slides back at this speed with the walk at rate 1 (measured
## in Blender: 1.4 m/s at the authored size).
const WALK_GROUND_SPEED := 0.82
## BEAM_BAKED: the cannon comes up by frame 37, but only SETTLES -- resting on
## the raised shield arm -- on the clip's last frame (47); held there while it
## fires. (Held at 37 the shield was still swinging across: "the beam arm is not
## setting on the shield arm", 2026-10-15.) A hair short of the end, so the
## clip is still playing, frozen, rather than finished.
const BEAM_SET_EARLY := 0.04
## THE SWIPE, a move of its own (2026-10-17, the user: "all enemy animations
## should have the same principles" -- the decrepit's): SWIPE_1_BAKED plays at
## 1x from its first frame, and everything it does is a time in that clip, on
## the move's own clock (`_swipe_t`; never read off the clip's position, which
## the animation LOD steps far off). It used to run on enemy.gd's wind-up timer,
## its clip slowed to x0.58 so the strike met the wind-up's end. The user's
## re-bake (CLAUDE.md 73): drawn back over frames 11-21, swept across the
## chest 22-26 (fastest 23-25).
## HIT WINDOWS: the swipe's blows, [start, end] clip seconds. While one is open
## its shield's hitbox (shield_hitbox.gd, ARM_L, 1.5x the shield) is live and
## lands the blow the first tick it overlaps the player, once per window.
const SWIPE_HITS := [[0.3833, 0.5167]]
## PARRY CUES (player.gd `parry_cue`): from each, a block press inside
## SWIPE_LISTEN parries the next blow (as the decrepit's; set so the window
## closes as the blow lands).
const SWIPE_CUES := [0.3]
const SWIPE_LISTEN := 0.25
## The move is over here (clip seconds); the walk takes it from there.
const SWIPE_END := 1.1
## It swings when the gap (edge to edge) is this or less -- at once if it was
## beaming (the beam is broken off for it), otherwise this long after its last
## swipe loop ended.
const SWIPE_TRIGGER := 1.65
const SWIPE_COOLDOWN := 1.1
## Swipe 1 landing unguarded throws the player this much FURTHER (the user:
## "1.75x the current amount"). Distance goes with the throw's speed squared, so
## the throw itself is sqrt of it (x1.75 on the throw sent them 17.6 m, ~3x).
const SWIPE1_THROW_SCALE := 1.75

## THE SWIPE LOOP (2026-10-17, the user). Close in it always opens with swipe
## 1. If it does not connect (missed or blocked), SWIPE_2_BAKED -- a backhand
## -- follows straight from swipe 1's follow-through (SWIPE_CHAIN, after its
## hit window: its pose there is swipe 2's first, the joints 0.1-0.8 units
## apart, measured) and DASHES at the player as it swings, as the decrepit's
## dash; if that does not connect either, swipe 1 again (blended from swipe 2's
## end, BLEND_CHAIN_21 -- no authored link: a straight blend lifts the shield
## from its side up across the chest, clear of the body, seen in renders), and
## so on until (A) a blow connects -- the loop ends with that swipe -- or (B)
## it is parried -- thrown, and as it recovers it takes up the loop again -- or
## (C) the player is further than LOOP_BREAK, out of the dash's reach, where the
## beam takes over.
const SWIPE_CHAIN := 0.5333
## Swipe 2 runs on into swipe 1 at SWIPE2_CHAIN (f22, just after its blow,
## still crouched), into swipe 1 at SWIPE1_LOOP_ENTRY (f15, crouched in its
## wind-up). Played to its end, swipe 2 stands up (f30-42) and swipe 1's start
## stands too, then crouches -- the user: "he shouldn't get back up briefly
## between swipe 2 and 1". Swipe 1's own crouch (f15-16) then ducks the torso
## under the blend -- kept: the user liked the duck, and entering after it
## (f16 -> f17) made the time between swipes uneven. The straight blend between
## the two poses keeps the shield out in front (renders).
const SWIPE2_CHAIN := 0.35
const SWIPE1_LOOP_ENTRY := 0.2333
const BLEND_CHAIN_12 := 0.15
const BLEND_CHAIN_21 := 0.2
const LOOP_BREAK := 7.0
## A breather (2026-10-17, the user: "far too pressuring"): after every
## LOOP_PAUSE_EVERY-th swipe of a loop that did not connect, LOOP_PAUSE before
## the next -- the swipe plays on through its own follow-through meanwhile,
## turning to face the player, rather than freezing. The count starts again with
## each new loop (from close in, out of a beam, after a parry).
const LOOP_PAUSE_EVERY := 3
const LOOP_PAUSE := 0.5
## Swipe 2 (clip seconds, at 1x but for the slide): its blows, cues and end.
## Its first blow's start is where the slide arrives.
const ANIM_SWIPE2_CLIP := &"SWIPE_2_BAKED"
const SWIPE2_HITS := [[0.2, 0.2667]]
const SWIPE2_CUES := [0.1]
const SWIPE2_LISTEN := 0.25
const SWIPE2_END := 0.6833
## THE DASH: at SWIPE2_LUNGE the body slides at the player -- fast at once,
## easing off into the blow, re-aimed every frame -- to put its body
## SWIPE2_ARRIVE from theirs; the clip from the lunge to the first blow is
## slowed to fill the slide. The slide lasts the distance over
## SWIPE2_SLIDE_SPEED, at most SWIPE2_SLIDE_MAX, and never less than that bit
## of clip at 1x (no slow motion when they are already close: the decrepit's
## lesson, CLAUDE.md 71).
const SWIPE2_LUNGE := 0.0833
const SWIPE2_ARRIVE := 1.3
const SWIPE2_SLIDE_SPEED := 14.0
const SWIPE2_SLIDE_MAX := 0.45
## It turns to follow the player (rad/s) until just before the blow.
const TURN_SWIPE := 6.0
## Clip changes into and out of the swipe settle within these (inertialized).
const BLEND_INTO_MOVE := 0.22
const BLEND_OUT_OF_MOVE := 0.35
const HITBOX := preload("res://scripts/shield_hitbox.gd")
## How hard a swipe that lands unguarded throws the player.
const SWIPE_THROW := 11.0
## ...and how hard one taken on a held guard shoves them.
const SWIPE_SHOVE := 4.0

const BEAM_DPS := 5.0
const BEAM_RANGE := 20.0
const BEAM_TIME := 3.2
## The beam opens from a third of its width to full over this, from the kick.
const BEAM_FLARE_IN := 0.08
const VENT_TIME := 1.6
## After first seeing the player, how long until it may first charge.
const FIRST_BEAM := 0.6
## How fast the beam swings after a moving player, radians a second.
const TRACK_RATE := 0.95
## Stone: the sight layer and the player's exact walls.
const WORLD_MASK := 2 | 256
## The player as the beam sees them: a capsule from the feet up.
const BODY_LOW := 0.25
const BODY_HIGH := 1.6
const BODY_RADIUS := 0.4
## Escorting a pack: closes up when further than this from its escort.
const ESCORT_FAR := 3.6
## Between beams it walks in only while further off than this (or out of line).
const KEEP_FAR := 12.0
## The drawn beam stops this far short of a player it is on.
const SHORT_OF_PLAYER := 0.8

## The crystal's colour, read off its material in `_ready` (cyan in the model).
var CRYSTAL := Color(0.0, 0.91, 1.0)
## The beam's hot core: the crystal's colour run toward white.
var HOT := Color(0.75, 0.97, 1.0)

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
## When the fire (the recoil) began, -1 when not firing.
var _fire_t0 := -1.0
## The body's extra turn that puts the barrel on the aim (`_barrel_facing`).
var _yaw_fix := 0.0
const BARREL_YAW_MAX := 0.35
const BARREL_YAW_RATE := 1.5

var _built := false
var _model: Node3D
var _muzzle: Node3D
var _parts: Array[MeshInstance3D] = []
## The shield's hitbox; the swipe's own clock (clip seconds since it began, -1
## when not swiping), the windows that have landed, when it may swing again,
## and the physics frame it last ran (it is broken off if `_chase` skips one).
var _hitbox: Node = null
var _swipe_t := -1.0
var _swipe_landed := {}
var _swipe_ready := 0.0
var _swipe_frame := -1
## Which swipe is under way: 1 or 2; whether it has connected (unguarded); and,
## parried, to take up the loop again once it has recovered.
var _swipe_kind := 1
var _swipe_hit := false
var _resume_loop := false
## Swipes so far in this loop, and when (on the swipe's clock) its pause ends --
## -1 when not pausing.
var _loop_count := 0
var _pause_end := -1.0
## The swipe's events on its own clock: hit windows, cues, where it chains into
## the other swipe (if nothing connected), and its end.
var _sw_hits: Array = []
var _sw_cues: Array = []
var _sw_chain := INF
var _sw_end := 0.0
## Swipe 2's slide: 0 before the lunge, 1 sliding, 2 after; its length, the time
## in it, the eased share done, the distance still to cover.
var _slide_phase := 0
var _slide_len := 0.0
var _slide_t := 0.0
var _slide_u := 0.0
var _slide_left := 0.0
## Stands in for enemy.gd's `mesh`: it takes a copy of this one's material as
## the state material, which is then put on the model's crystal and the eyes.
var _state_proxy: MeshInstance3D
var _eyes_glow: Array[MeshInstance3D] = []
## The eyes' own copy of the crystal's colour, at EYE_GLOW of its glow: on the same
## material, with the bloom, the two eyes (0.11 m apart) ran together into one ball.
var _eye_mat: StandardMaterial3D
const EYE_GLOW := 0.35
var _clip := &""
## The player's guard as the swipe lands: -1 none, 0 blocked, 1 parried.
var _guard_seen := -1
var _beam_root: Node3D
## The core's and the glow's holders, stretched to the beam's length each tick.
var _spans: Array[Node3D] = []
var _beam_core: MeshInstance3D
var _beam_glow: MeshInstance3D
var _beam_flare: MeshInstance3D
var _beam_light: OmniLight3D
var _beam_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D

static var _mats := {}


func _init() -> void:
	# A shield for an arm, not a sword (enemy.gd `armed`).
	armed = false
	max_health = 240.0
	move_speed = 2.2
	acceleration = 12.0
	vision_cone_degrees = 160.0
	sight_needs_line_of_sight = true
	sight_memory = 6.0
	eye_height = 2.15
	wanders = true
	wander_speed = 1.3
	# Its swipe is its own move (SWIPE_*), not enemy.gd's wind-up / strike /
	# recover: the base chase never swings for it (`_chase` always handles it).
	can_slam = false
	can_normal = false
	attack_damage = 22.0
	knockback_resistance = 0.85
	tint_albedo = false
	base_glow = 2.0
	windup_glow = 3.5
	attack_glow = 4.5
	windup_color = Color(0.45, 0.95, 1.0)
	attack_color = Color(0.8, 1.0, 1.0)
	hit_punch = 0.06
	display_name = "ENFORCER"
	drop_rolls_min = 1
	drop_rolls_max = 1
	drop_odds = {&"gold_crystal": 0.6, &"health_potion": 0.15}


func is_enforcer() -> bool:
	return true


# --- The body ---------------------------------------------------------------------

## Before `_ready` (and enemy.gd's @onready lookups): the skeleton goes, the
## enforcer goes in its place, and the capsule grows to fit it.
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
	_model = MODEL.instantiate() as Node3D
	_model.name = "Enforcer"
	# Authored facing +Z; enemies face -Z.
	_model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * MODEL_SCALE),
		Vector3(0.0, MODEL_LIFT, 0.0))
	vis.add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).begins_with("EyeGlow"):
			continue
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_parts.append(m)
	_muzzle = _model.find_child("Muzzle", true, false) as Node3D
	# The state material's holder (see `_state_proxy`): never drawn.
	_state_proxy = MeshInstance3D.new()
	_state_proxy.name = "StateCrystal"
	_state_proxy.mesh = SphereMesh.new()
	_state_proxy.visible = false
	vis.add_child(_state_proxy)
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.6
		cap.height = 2.5
		cs.shape = cap
		cs.position = Vector3(0.0, 1.25, 0.0)
	var ag := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if ag != null:
		ag.radius = 0.6
		ag.height = 2.5


func _ready() -> void:
	# The crystal's material: its colour is the eyes' and the beam's.
	var crystal_part: MeshInstance3D = null
	var crystal_surface := -1
	for m in _parts:
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null and mat.resource_name.contains("Crystal"):
				crystal_part = m
				crystal_surface = i
				CRYSTAL = mat.emission
				HOT = CRYSTAL.lerp(Color.WHITE, 0.7)
	var state := _crystal_material()
	_state_proxy.material_override = state
	# enemy.gd copies its `mesh`'s material as the state material.
	mesh = _state_proxy
	super()
	name = "Enforcer"
	add_to_group(&"enforcers")
	if crystal_part != null:
		crystal_part.set_surface_override_material(crystal_surface, _material)
	_attach_eyes()
	_setup_clips()
	_build_beam()
	_warm_hit_sparks.call_deferred()
	_attach_react()


func _crystal_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = CRYSTAL
	m.emission_enabled = true
	m.emission = CRYSTAL
	m.emission_energy_multiplier = base_glow
	m.roughness = 0.2
	return m


## A glowing RING in each eye (2026-10-15; full discs before), in the crystal's
## colour (they flare with it, at EYE_GLOW). The rings are the model's own
## ("EyeGlowL" / "EyeGlowR", built by tools/build_enforcer.py): laid on the
## outer part of each grey lens, traced from its real outline and following its
## surface a few millimetres off it -- the first rings were fixed-size tori on
## markers that sat on each lens's inner edge, off-centre and cutting into the
## bezel. The tori below are only a fallback for a model without them. No halo
## cards: with the bloom they ran the two eyes together into one ball.
const EYE_RING_OUTER := 0.062
const EYE_RING_INNER := 0.04


func _attach_eyes() -> void:
	_eye_mat = _material.duplicate() as StandardMaterial3D
	_eye_mat.emission_energy_multiplier = base_glow * EYE_GLOW
	var traced := false
	for name_ in ["EyeGlowL", "EyeGlowR"]:
		var ring := _model.find_child(name_, true, false) as MeshInstance3D
		if ring == null:
			continue
		traced = true
		ring.material_override = _eye_mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_eyes_glow.append(ring)
	if traced:
		return
	for name_ in ["EyeL", "EyeR"]:
		var at := _model.find_child(name_, true, false) as Node3D
		if at == null:
			continue
		var lens := MeshInstance3D.new()
		var unit: float = maxf(at.global_basis.get_scale().x, 0.001)
		var ring := TorusMesh.new()
		ring.outer_radius = EYE_RING_OUTER / unit
		ring.inner_radius = EYE_RING_INNER / unit
		ring.rings = 24
		ring.ring_segments = 8
		lens.mesh = ring
		# A torus lies flat about its Y; stood up to face along the face's +Z
		# (the markers are not turned: the model faces +Z).
		lens.rotation.x = PI * 0.5
		lens.material_override = _eye_mat
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		at.add_child(lens)
		_eyes_glow.append(lens)


func _setup_clips() -> void:
	if anim == null:
		return
	if anim.has_animation(ANIM_WALK_CLIP):
		anim.get_animation(ANIM_WALK_CLIP).loop_mode = Animation.LOOP_LINEAR
	for c in [ANIM_BEAM_CLIP, ANIM_SWIPE_CLIP, ANIM_SWIPE2_CLIP]:
		if anim.has_animation(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_NONE
	if anim.has_animation(ANIM_RECOIL_CLIP):
		anim.get_animation(ANIM_RECOIL_CLIP).loop_mode = Animation.LOOP_NONE
	_play_clip(ANIM_WALK_CLIP, 0.0, 0.0)


## Plays `clip` at `rate`, cross-fading over `blend` -- unless it is already the
## clip playing, when only the rate changes. The fade is the reaction layer's
## (enforcer_react.gd `crossfade`, inertialized), not the AnimationPlayer's:
## that one stalled fading into a clip held at speed 0 and lurched at the start
## of every other fade. So the clip is switched outright and the layer eases the
## rig from the last pose shown into it. The walk is entered at the moment of
## its cycle nearest the pose shown (`_match_phase`), as the decrepit's crawl.
func _play_clip(clip: StringName, rate: float, blend := 0.2, restart := false, at := 0.0) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if _clip == clip and not restart and anim.is_playing():
		anim.speed_scale = rate
		return
	var start := at
	if clip == ANIM_WALK_CLIP:
		start = _match_phase(clip)
	if _react != null:
		_react.call("crossfade", blend)
	_clip = clip
	anim.play(clip, 0.0, 1.0)
	anim.speed_scale = rate
	anim.seek(start, true)


## The time in `clip` whose pose is nearest the pose shown last frame: every
## bone's rotation (radians apart) and position (rig units), checked at 48
## points of the clip. 0 if there is no pose to match. (decrepit.gd's.)
var _match_tracks := {}


func _match_phase(clip: StringName) -> float:
	if _react == null or _skel == null or anim == null or not _react.has_method(&"shown_rotation"):
		return 0.0
	var a := anim.get_animation(clip)
	if a == null:
		return 0.0
	if not _match_tracks.has(clip):
		var list: Array = []
		for ti in a.get_track_count():
			var ty := a.track_get_type(ti)
			if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
				continue
			var bone := _skel.find_bone(String(a.track_get_path(ti).get_concatenated_subnames()))
			if bone >= 0:
				list.append([ti, bone, ty == Animation.TYPE_ROTATION_3D])
		_match_tracks[clip] = list
	var tracks: Array = _match_tracks[clip]
	if tracks.is_empty():
		return 0.0
	var shown := {}
	for tr in tracks:
		var v = _react.call("shown_rotation" if tr[2] else "shown_position", tr[1])
		if v == null:
			return 0.0
		shown[tr[0]] = v
	var best := 0.0
	var best_cost := INF
	var steps := 48
	for k in steps:
		var t := a.length * float(k) / float(steps)
		var cost := 0.0
		for tr in tracks:
			if tr[2]:
				cost += a.rotation_track_interpolate(tr[0], t).angle_to(shown[tr[0]])
			else:
				cost += a.position_track_interpolate(tr[0], t).distance_to(shown[tr[0]])
		if cost < best_cost:
			best_cost = cost
			best = t
	return best


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
		&"flash":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(1.0, 0.9, 0.75, 0.55)
	_mats[key] = m
	return m


# --- The shield swipe ---------------------------------------------------------------

## enemy.gd's reach never lands the swipe: its shield's hitbox does, in the
## swipe's hit windows (`_run_swipe`).
func _try_connect(_player: Node3D, _gap: float, _reach: float, _charge_speed := 0.0) -> void:
	pass


## Into swipe `kind` (1 or 2): its clip from the first frame at 1x, its clock at
## 0. `blend`: how long the switch from the pose shown may take. `chained`: the
## loop going on (counted towards its pause), not a new loop.
func _start_swipe(player: Node3D, kind := 1, blend := BLEND_INTO_MOVE, from := 0.0, chained := false) -> void:
	_loop_count = _loop_count + 1 if chained else 1
	_pause_end = -1.0
	_swipe_kind = kind
	_swipe_t = from
	_swipe_hit = false
	_swipe_landed.clear()
	_attack_connected = false
	_slide_phase = 0
	_slide_len = 0.0
	_swipe_events()
	if player.has_signal("guarded") and not player.is_connected("guarded", _on_player_guarded):
		player.connect("guarded", _on_player_guarded)
	_play_clip(ANIM_SWIPE_CLIP if kind == 1 else ANIM_SWIPE2_CLIP, 1.0, blend, true, from)


## The swipe's blows, cues, chain point and end, from clip seconds onto its own
## clock (swipe 2's through its slide, `_swipe2_clock`). Sorted.
func _swipe_events() -> void:
	var one := _swipe_kind == 1
	_sw_hits.clear()
	_sw_cues.clear()
	var last_shut := 0.0
	for w in _sorted_windows(SWIPE_HITS if one else SWIPE2_HITS):
		_sw_hits.append([_swipe_clock(float(w[0])), _swipe_clock(float(w[1]))])
		last_shut = maxf(last_shut, float(w[1]))
	for c in (SWIPE_CUES if one else SWIPE2_CUES):
		_sw_cues.append(_swipe_clock(float(c)))
	_sw_cues.sort()
	# Each chains into the other at its chain point -- never before its last
	# blow could still land.
	_sw_chain = _swipe_clock(maxf(SWIPE_CHAIN if one else SWIPE2_CHAIN, last_shut))
	_sw_end = _swipe_clock(SWIPE_END if one else SWIPE2_END)


## A moment of the swipe's clip on its own clock: swipe 1's is its clip's;
## swipe 2's runs at 1x to the lunge, its lunge-to-first-blow stretched over the
## slide (`_slide_len`; until the lunge, that bit at 1x), then 1x again.
func _swipe_clock(clip_t: float) -> float:
	if _swipe_kind == 1 or clip_t <= SWIPE2_LUNGE:
		return clip_t
	var arrive := _swipe2_arrive()
	var span := maxf(arrive - SWIPE2_LUNGE, 0.0001)
	var slide := maxf(_slide_len, span)
	if clip_t <= arrive:
		return SWIPE2_LUNGE + (clip_t - SWIPE2_LUNGE) / span * slide
	return SWIPE2_LUNGE + slide + (clip_t - arrive)


## Swipe 2's first blow (clip seconds): where its slide arrives.
static func _swipe2_arrive() -> float:
	var w := _sorted_windows(SWIPE2_HITS)
	return maxf(float(w[0][0]), SWIPE2_LUNGE) if not w.is_empty() else SWIPE2_LUNGE


## A tick of the swipe on its own clock: swipe 1 stands, turning after the
## player until just before its blow; swipe 2 slides at them (`_slide_step`).
## Its cues open the player's parry listening as the clock passes them; an open
## hit window lands the blow the first tick the shield's box overlaps the
## player (shown while open). Nothing connected by the chain point: on round
## the loop (`_loop_on`); otherwise it plays out to its end.
func _run_swipe(delta: float, player: Node3D, flat: Vector3) -> void:
	_swipe_frame = Engine.get_physics_frames()
	var prev := _swipe_t
	_swipe_t += delta
	var fwd := 0.0
	var tracking := false
	if _swipe_kind == 2:
		fwd = _slide_step(delta, flat)
		tracking = _slide_phase == 0 or (_slide_phase == 1 and _slide_u < 0.75)
	else:
		var first: float = _sw_hits[0][0] if not _sw_hits.is_empty() else INF
		tracking = _swipe_t < first - 0.08
	# Pausing (LOOP_PAUSE), it turns to face them for the next.
	tracking = tracking or _pause_end >= 0.0
	if tracking and flat.length_squared() > 0.01:
		rotation.y = rotate_toward(rotation.y, atan2(-flat.x, -flat.z), TURN_SWIPE * delta)
	if fwd > 0.0:
		var step := -global_basis.z * fwd
		velocity.x = step.x / delta
		velocity.z = step.z / delta
		move_and_slide()
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_hold(delta)
	var listen := SWIPE_LISTEN if _swipe_kind == 1 else SWIPE2_LISTEN
	for cue in _sw_cues:
		if prev < float(cue) and _swipe_t >= float(cue) and player.has_method("parry_cue"):
			player.call("parry_cue", self, listen)
	var open := false
	for i in _sw_hits.size():
		var w: Array = _sw_hits[i]
		if _swipe_t < float(w[0]) or prev > float(w[1]):
			continue
		open = true
		if _swipe_landed.has(i):
			continue
		if _hitbox != null and _hitbox.call("overlaps", player):
			_swipe_landed[i] = true
			if _swipe_land(player) == &"hit":
				_swipe_hit = true
	_set_hitbox(open)
	if _swipe_t < 0.0:
		return
	if not _swipe_hit and _swipe_t >= _sw_chain:
		# Every LOOP_PAUSE_EVERY-th swipe: the clip plays on for LOOP_PAUSE first.
		if _pause_end < 0.0 and _loop_count % LOOP_PAUSE_EVERY == 0:
			_pause_end = _swipe_t + LOOP_PAUSE
		if _pause_end < 0.0 or _swipe_t >= _pause_end:
			_loop_on(player, flat)
	elif _swipe_t >= _sw_end:
		_end_swipe()


## Round the loop: nothing connected, so the other swipe -- unless the player
## is out of the dash's reach (C), where the loop ends and the beam may follow.
## After a pause the pose is no longer the chain's, so the plain blend into a
## move -- and swipe 1 from its start, its whole wind-up (the user preferred
## that to entering at its loop entry, which evened the two pauses out).
func _loop_on(player: Node3D, flat: Vector3) -> void:
	if flat.length() > LOOP_BREAK:
		_end_swipe()
		return
	var paused := _pause_end >= 0.0
	if _swipe_kind == 1:
		_start_swipe(player, 2, BLEND_INTO_MOVE if paused else BLEND_CHAIN_12, 0.0, true)
	else:
		_start_swipe(player, 1, BLEND_INTO_MOVE if paused else BLEND_CHAIN_21,
			0.0 if paused else SWIPE1_LOOP_ENTRY, true)


## Swipe 2's dash, a step (metres forward): nothing until the lunge; then the
## slide, its length fixed there from the distance, the clip slowed to fill it,
## fast at once and easing off, re-aimed on what is left each frame; then 1x.
func _slide_step(delta: float, flat: Vector3) -> float:
	var gap := maxf(flat.length() - SWIPE2_ARRIVE, 0.0)
	match _slide_phase:
		0:
			if _swipe_t >= SWIPE2_LUNGE:
				var span := maxf(_swipe2_arrive() - SWIPE2_LUNGE, 0.0001)
				_slide_len = clampf(gap / SWIPE2_SLIDE_SPEED, span, maxf(SWIPE2_SLIDE_MAX, span))
				_slide_left = minf(gap, SWIPE2_SLIDE_SPEED * _slide_len)
				_slide_t = 0.0
				_slide_u = 0.0
				_slide_phase = 1
				# Its blows, cues and end now sit where the slide puts them.
				_swipe_events()
				if anim != null:
					anim.speed_scale = span / _slide_len
			return 0.0
		1:
			_slide_t += delta
			var u := minf(_slide_t / _slide_len, 1.0)
			var a := 1.0 - (1.0 - _slide_u) * (1.0 - _slide_u)
			var b := 1.0 - (1.0 - u) * (1.0 - u)
			_slide_u = u
			var left := minf(gap, _slide_left)
			var fwd := left * (b - a) / maxf(1.0 - a, 0.001)
			_slide_left = maxf(_slide_left - fwd, 0.0)
			if u >= 1.0:
				_slide_phase = 2
				if anim != null:
					anim.speed_scale = 1.0
			return fwd
	return 0.0


## The swipe over -- or broken off (a stagger, the beam, the hunt dropped): the
## box shut, and the walk takes over, eased in from the pose shown. The next
## loop may start SWIPE_COOLDOWN from now.
func _end_swipe() -> void:
	if _swipe_t < 0.0:
		return
	_swipe_t = -1.0
	_set_hitbox(false)
	_swipe_ready = _now() + SWIPE_COOLDOWN
	if anim != null and anim.speed_scale != 1.0 and _clip == ANIM_SWIPE2_CLIP:
		anim.speed_scale = 1.0
	if not _dying and _beam != Beam.CHARGE and _beam != Beam.FIRE:
		_play_clip(ANIM_WALK_CLIP, 0.0, BLEND_OUT_OF_MOVE, true)


## Windows [start, end] in order, by start.
static func _sorted_windows(list: Array) -> Array:
	var out: Array = []
	for w in list:
		out.append([minf(float(w[0]), float(w[1])), maxf(float(w[0]), float(w[1]))])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out


## True while a hit window of the swipe under way is open.
func is_attacking() -> bool:
	if _swipe_t < 0.0:
		return false
	for w in _sw_hits:
		if _swipe_t >= float(w[0]) and _swipe_t <= float(w[1]):
			return true
	return false


func _set_hitbox(on: bool) -> void:
	if _hitbox != null and is_instance_valid(_hitbox) and _hitbox.get("live") != on:
		_hitbox.call("set_live", on)


## The swipe's blow, through the player's guard; then the knock-down: unguarded,
## the player goes off their feet (swipe 1 throws them SWIPE1_THROW_SCALE
## harder); a held guard keeps them standing, shoved back; a parry already threw
## this enforcer and leaves the player alone. Returns &"hit", &"blocked",
## &"parried" or &"miss" (it did not get through: an invulnerable moment).
func _swipe_land(player: Node3D) -> StringName:
	_guard_seen = -1
	if player.has_signal("guarded") and not player.is_connected("guarded", _on_player_guarded):
		player.connect("guarded", _on_player_guarded)
	var to := player.global_position - global_position
	var away := Vector3(to.x, 0.0, to.z)
	away = away.normalized() if away.length_squared() > 0.0001 else -global_basis.z
	var before = player.get("health")
	player.call("take_damage", attack_damage, away, self)
	_attack_connected = true
	var after = player.get("health")
	var hurt: bool = before != null and after != null and float(after) < float(before)
	if _guard_seen == 1:
		return &"parried"
	if _guard_seen == 0:
		if player.has_method("apply_knockback"):
			player.call("apply_knockback", away * SWIPE_SHOVE)
		return &"blocked"
	if not hurt:
		return &"miss"
	if player.has_method("knock_down"):
		player.call("knock_down", away, SWIPE_THROW * (sqrt(SWIPE1_THROW_SCALE) if _swipe_kind == 1 else 1.0))
	return &"hit"


func _on_player_guarded(parried: bool, attacker: Node3D) -> void:
	if attacker == self:
		_guard_seen = 1 if parried else 0
		if parried:
			_parry_stagger()
			# (B) Thrown -- and once it has recovered, back into the loop.
			_resume_loop = true


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
	_glow_mat.albedo_color = Color(CRYSTAL, 0.22)
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
	# Close in, it ALWAYS breaks off its beam -- charging or firing -- for swipe
	# 1 (the user, 2026-10-17), whatever its role.
	if (_beam == Beam.CHARGE or _beam == Beam.FIRE) and gap <= SWIPE_TRIGGER and _swipe_t < 0.0:
		_cancel_beam()
		_start_swipe(player, 1)
		_run_swipe(delta, player, flat)
		return true
	match _beam:
		Beam.CHARGE:
			_hold(delta)
			_face(flat)
			_aim_dir = _turn_toward(_aim_dir, _target_dir(player), TRACK_RATE * 3.0 * delta)
			if now >= _phase_until:
				# The recoil starts; the beam comes on with its kick.
				_beam = Beam.FIRE
				_fire_t0 = now
				_phase_until = now + RECOIL_BEAM + BEAM_TIME
				_lost_line_at = -1.0
			return true
		Beam.FIRE:
			_hold(delta)
			_aim_dir = _turn_toward(_aim_dir, _target_dir(player), TRACK_RATE * delta)
			var aim_flat := Vector3(_aim_dir.x, 0.0, _aim_dir.z)
			_face(_barrel_facing(aim_flat, delta))
			if not _clear:
				if _lost_line_at < 0.0:
					_lost_line_at = now
			else:
				_lost_line_at = -1.0
			if now >= _phase_until or (_lost_line_at >= 0.0 and now - _lost_line_at > 0.7):
				_vent(now)
			return true
	# A swipe under way runs to its end on its own clock.
	if _swipe_t >= 0.0:
		_run_swipe(delta, player, flat)
		return true
	# (B) Up again after a parry: straight back into the loop -- swipe 1 if
	# they are close, the dash (swipe 2) if they are within its reach.
	if _resume_loop:
		_resume_loop = false
		if gap <= SWIPE_TRIGGER:
			_start_swipe(player, 1)
			_run_swipe(delta, player, flat)
			return true
		if distance <= LOOP_BREAK:
			_start_swipe(player, 2)
			_run_swipe(delta, player, flat)
			return true
	_update_role(now, player, distance)
	match _role:
		Role.MELEE:
			# The shield: in close and swipe; the beam is someone else's.
			if gap <= SWIPE_TRIGGER:
				_close_in(delta, now, player, flat)
				return true
			_walk_to(delta, now, player.global_position, move_speed)
			_face_velocity(flat)
			return true
		Role.BEAM:
			# Never the shield while a fellow swipes: hold the range, and back off
			# a player who comes too close rather than swing at them.
			if now >= _beam_ready and _clear and distance <= BEAM_RANGE and not _other_beaming(player):
				_start_charge(delta, player, flat)
				return true
			if distance < BEAM_BACK_OFF:
				_walk_to(delta, now, global_position - flat.normalized() * 4.0, move_speed * 0.8)
				_face(flat)
			elif distance > KEEP_FAR or not _clear:
				_walk_to(delta, now, player.global_position, move_speed)
				_face_velocity(flat)
			else:
				_hold(delta)
				_face(flat)
			return true
	# Alone, it does both. Up close it swipes.
	if gap <= SWIPE_TRIGGER:
		_close_in(delta, now, player, flat)
		return true
	if now >= _beam_ready and _clear and distance <= BEAM_RANGE:
		_start_charge(delta, player, flat)
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


## The beam is on: firing, and past the recoil's kick (on the fire's own clock).
func _beam_live(now: float) -> bool:
	return _beam == Beam.FIRE and _fire_t0 >= 0.0 and now - _fire_t0 >= RECOIL_BEAM


## Which way to face so the BARREL, not the chest, points along `aim_flat`: the
## cannon sits off the body's front in the firing pose (~5 deg, measured; the
## reaction layer reads it off the rig every frame, `barrel_world`), so the body
## turns that much more -- eased in, so it does not snap as the fire starts.
func _barrel_facing(aim_flat: Vector3, delta: float) -> Vector3:
	var want := 0.0
	if _react != null:
		var bw: Vector3 = _react.get("barrel_world")
		var b := Vector3(bw.x, 0.0, bw.z)
		var fwd := -global_basis.z
		fwd.y = 0.0
		if b.length_squared() > 0.01 and fwd.length_squared() > 0.01:
			want = clampf(fwd.signed_angle_to(b, Vector3.UP), -BARREL_YAW_MAX, BARREL_YAW_MAX)
	_yaw_fix = move_toward(_yaw_fix, want, BARREL_YAW_RATE * delta)
	return aim_flat.rotated(Vector3.UP, -_yaw_fix)


## In swiping range: it swings the moment it may (its first step this same
## tick: a move that starts standing still for a tick reads as a seam), and
## otherwise stands and faces them.
func _close_in(delta: float, now: float, player: Node3D, flat: Vector3) -> void:
	if now >= _swipe_ready:
		_start_swipe(player)
		_run_swipe(delta, player, flat)
		return
	_hold(delta)
	_face(flat)


## The charge: BEAM_BAKED at 1x up to where it settles (`_beam_set_at`) -- the
## clip's own length is the charge's (it was squeezed into a CHARGE_TIME).
func _start_charge(delta: float, player: Node3D, flat: Vector3) -> void:
	_beam = Beam.CHARGE
	_phase_until = _now() + _beam_set_at()
	_aim_dir = _target_dir(player)
	_hold(delta)
	_face(flat)


# --- Taking turns (2026-10-15) --------------------------------------------------------
##
## Two or more enforcers on the same player do not make the same move: the
## nearest takes the SHIELD (walks in and swipes, never beams), the rest take the
## BEAM (hold their range and beam, never swipe -- they back away from a player
## who closes in), and only one beam is charged or fired at a time. Alone, an
## enforcer does both. Worked out every ROLE_EVERY; the one holding the shield
## keeps it mid-swipe, and loses it only to one ROLE_MARGIN nearer.
enum Role { BOTH, MELEE, BEAM }
const ROLE_EVERY := 0.25
## How far from the player another enforcer can be and still count as a partner.
const ROLE_RANGE := 30.0
const ROLE_MARGIN := 2.0
## A beam-holder backs off a player closer than this.
const BEAM_BACK_OFF := 4.0
var _role := Role.BOTH
var _role_at := 0.0


func _update_role(now: float, player: Node3D, distance: float) -> void:
	if now < _role_at:
		return
	_role_at = now + ROLE_EVERY
	var partners := 0
	var nearer := false
	var melee_held := false
	for e in get_tree().get_nodes_in_group(&"enforcers"):
		if e == self or not is_instance_valid(e) or e.get("_dying") == true or e.get("engaged") != true:
			continue
		var d := (e as Node3D).global_position.distance_to(player.global_position)
		if d > ROLE_RANGE:
			continue
		partners += 1
		# Someone already on the shield -- and anyone mid-swipe, however far --
		# keeps this one on the beam.
		if e.get("_role") == Role.MELEE and (d < distance + ROLE_MARGIN or e.call("_swiping")):
			melee_held = true
		if d < distance - (ROLE_MARGIN if _role == Role.MELEE else 0.0):
			nearer = true
	if partners == 0:
		_role = Role.BOTH
	elif _role == Role.MELEE and (_swiping() or not nearer):
		pass
	elif melee_held or nearer:
		_role = Role.BEAM
	else:
		_role = Role.MELEE


func _swiping() -> bool:
	return _swipe_t >= 0.0


## Another enforcer charging or firing at this player.
func _other_beaming(player: Node3D) -> bool:
	for e in get_tree().get_nodes_in_group(&"enforcers"):
		if e == self or not is_instance_valid(e) or e.get("_dying") == true:
			continue
		var b = e.get("_beam")
		if (b == Beam.CHARGE or b == Beam.FIRE) \
				and (e as Node3D).global_position.distance_to(player.global_position) <= ROLE_RANGE:
			return true
	return false


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
	_fire_t0 = -1.0
	_yaw_fix = 0.0


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


## The beam, drawn only while it is on (`_beam_live`): no aiming line through
## the charge any more -- it starts with the recoil's kick (the user, 2026-10-17).
func _draw_beam(now: float) -> void:
	var on := _beam_live(now)
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
	# A full beam that shivers, flaring up over its first BEAM_FLARE_IN.
	var grow := clampf((now - _fire_t0 - RECOIL_BEAM) / BEAM_FLARE_IN, 0.0, 1.0)
	grow = grow * grow * (3.0 - 2.0 * grow)
	var width := (1.0 + 0.18 * sin(now * 61.0) + 0.1 * sin(now * 23.0)) * lerpf(0.3, 1.0, grow)
	# By reference: two siblings named alike get renamed, and a lookup by name
	# left the glow a metre long while the core reached the target.
	for holder in _spans:
		holder.scale = Vector3(width, width, length)
	_beam_mat.albedo_color.a = 0.95
	_glow_mat.albedo_color.a = 0.26
	# Not on the player: a flare right under their eyes is a blot on the view, and
	# the HUD's gold edge already says they are in it.
	_beam_flare.visible = not _beam_on_player
	_beam_flare.position = Vector3(0.0, 0.0, -length)
	_beam_flare.scale = Vector3.ONE * (0.6 if _beam_on_player else 0.9) * width
	if Graphics.effects:
		if _beam_light == null:
			_beam_light = OmniLight3D.new()
			_beam_light.light_color = CRYSTAL
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
	# Anything that takes it off its feet or out of the hunt drops the beam --
	# and the swipe (as does a tick its hunt did not run it).
	if (_beam == Beam.CHARGE or _beam == Beam.FIRE) \
			and (state != State.CHASE or not engaged or is_stunned()):
		_cancel_beam()
	if _swipe_t >= 0.0 and (state != State.CHASE or not engaged or is_stunned()
			or _swipe_frame != Engine.get_physics_frames()):
		_end_swipe()
	if _beam_live(now):
		_fire(delta)
	_draw_beam(now)
	_animate(delta, now)
	_aim_arms()


## Both arms pitched so the barrel points along the beam, from the moment the
## fire starts (so they are on it by the kick); let go as it ends. And, awake,
## the reaction layer keeps tracking the rig's motion, so every clip change
## starts from how it was really moving (CLAUDE.md 59; the decrepit always does).
func _aim_arms() -> void:
	if _react == null:
		return
	_react.set("keep_tracking", engaged)
	if engaged and not _react.active:
		# Off since it last went idle: tracking only starts with it on.
		_react.active = true
	if _beam == Beam.FIRE and _muzzle != null:
		_react.call("aim_at", _muzzle.global_position + _aim_dir * 30.0)
	else:
		_react.call("aim_at", null)


## Which clip, at what rate. The beam owns the body while it charges and fires,
## the swipe while enemy.gd winds up, strikes and recovers, and the walk the
## rest of the time -- played at the rate that keeps its feet on the floor, and
## eased to a stop where it stands (there is no idle clip).
func _animate(delta: float, now: float) -> void:
	match _beam:
		Beam.CHARGE:
			# The whole clip, settling on the shield arm as the charge ends.
			_play_clip(ANIM_BEAM_CLIP, 1.0, 0.12, _clip != ANIM_BEAM_CLIP)
			_freeze_at(ANIM_BEAM_CLIP, _beam_set_at())
		Beam.FIRE:
			# The recoil, once -- the beam comes on with its kick -- then held
			# on its last frame while the beam lasts. No ping-pong.
			if anim == null or not anim.has_animation(ANIM_RECOIL_CLIP):
				if _clip != ANIM_BEAM_CLIP:
					_play_clip(ANIM_BEAM_CLIP, 0.0, 0.1, true)
					anim.seek(_beam_set_at(), true)
				_freeze_at(ANIM_BEAM_CLIP, _beam_set_at())
			else:
				if _clip != ANIM_RECOIL_CLIP:
					_play_clip(ANIM_RECOIL_CLIP, 1.0, 0.1, true)
				_freeze_at(ANIM_RECOIL_CLIP, anim.get_animation(ANIM_RECOIL_CLIP).length - HOLD_EARLY)
		_:
			if is_stunned():
				# Reeling (a parry, a stagger): it stands while the reaction
				# layer (enforcer_react.gd) throws it about, rather than
				# walking on the spot as the shove slides it.
				if _clip != ANIM_WALK_CLIP:
					_play_clip(ANIM_WALK_CLIP, 0.0, 0.3, true)
				elif anim != null:
					anim.speed_scale = move_toward(anim.speed_scale, 0.0, delta * 6.0)
			elif _swipe_t >= 0.0:
				# The swipe's clip, started with the move (`_start_swipe`), at 1x.
				pass
			else:
				# The walk at the rate that keeps its feet on the floor, eased to a
				# stop where it stands (no idle clip); entered from a move at the
				# phase nearest its pose, from a standstill, and eased up.
				var v := get_real_velocity()
				var speed := Vector2(v.x, v.z).length()
				var want := clampf(speed / WALK_GROUND_SPEED, 0.4, 3.2) if speed > 0.15 else 0.0
				if _clip != ANIM_WALK_CLIP:
					_play_clip(ANIM_WALK_CLIP, 0.0, 0.3, true)
				elif anim != null:
					anim.speed_scale = move_toward(anim.speed_scale, want,
						delta * (WALK_RATE_EASE if want > 0.0 else 4.0))

	# The crystal and the eyes: their rest glow, flaring through a charge and
	# burning hot while it fires. (enemy.gd's state colours ride on the same
	# material.)
	if _material != null:
		var e := base_glow
		var col := CRYSTAL
		match _beam:
			Beam.CHARGE:
				var t := 1.0 - clampf((_phase_until - now) / maxf(_beam_set_at(), 0.05), 0.0, 1.0)
				e = lerpf(base_glow, 6.0, t) * (1.0 + 0.25 * sin(now * 40.0))
				col = CRYSTAL.lerp(HOT, t)
			Beam.FIRE:
				e = 5.0 + 1.0 * sin(now * 53.0)
				col = HOT
			Beam.VENT:
				e = base_glow * 0.5
		# The swipe: its wind-up colour until the blow, the strike's while it lands.
		if _swipe_t >= 0.0:
			var hits := _sw_hits
			if not hits.is_empty() and _swipe_t < float(hits[0][0]):
				e = windup_glow
				col = windup_color
			elif is_attacking():
				e = attack_glow
				col = attack_color
		_material.albedo_color = col
		_material.emission = col
		_material.emission_energy_multiplier = e
		if _eye_mat != null:
			_eye_mat.albedo_color = col
			_eye_mat.emission = col
			_eye_mat.emission_energy_multiplier = e * EYE_GLOW


## Where BEAM_BAKED settles: its end, less BEAM_SET_EARLY.
func _beam_set_at() -> float:
	if anim == null or not anim.has_animation(ANIM_BEAM_CLIP):
		return 0.7
	return anim.get_animation(ANIM_BEAM_CLIP).length - BEAM_SET_EARLY


## Holds `clip` once it reaches `at`: still playing, at speed 0.
func _freeze_at(clip: StringName, at: float) -> void:
	if anim != null and anim.current_animation == clip \
			and anim.current_animation_position >= at:
		anim.speed_scale = 0.0


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

## The flash of a blow, WITHOUT enemy.gd's squash: that scaled the whole model
## in one frame and sprang it back -- a cartoon pop that, under the hit
## reactions (enforcer_react.gd), read as the rig snapping (measured: the head
## jumping 6-10 cm a frame on the blow). The reactions are the movement now.
func _flash() -> void:
	if _material != null:
		if _flash_tween != null and _flash_tween.is_valid():
			_flash_tween.kill()
		_material.albedo_color = Color(1.0, 0.95, 0.9)
		_flash_tween = create_tween()
		_flash_tween.tween_property(_material, "albedo_color", _state_color, 0.18)
	var flash := _mat(&"flash")
	for mi in _parts:
		mi.material_overlay = flash
	get_tree().create_timer(0.08).timeout.connect(_unflash)


func _unflash() -> void:
	for mi in _parts:
		if is_instance_valid(mi):
			mi.material_overlay = null


## It does not fold up like a skeleton: the crystal and eyes gutter, sparks fly,
## the rig stops where it stands, it sinks onto its knees, tips forward and lies
## a moment before it goes.
func _die() -> void:
	_cancel_beam()
	_set_hitbox(false)
	_dying = true
	died.emit()
	shape.disabled = true
	_grant_drop()
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	visual.scale = _mesh_scale
	if anim != null:
		anim.pause()
	if Graphics.effects:
		_sparks()
	if _material != null:
		var t := create_tween()
		for k in 5:
			t.tween_property(_material, "emission_energy_multiplier", 5.0 if k % 2 == 0 else 0.3, 0.07)
		t.tween_property(_material, "emission_energy_multiplier", 0.0, 0.5)
	if _eye_mat != null:
		create_tween().tween_property(_eye_mat, "emission_energy_multiplier", 0.0, 0.6)
	var fall := create_tween().set_parallel(true)
	fall.tween_property(visual, "position:y", -0.7, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(visual, "rotation:x", -1.25, 0.8).set_delay(0.3) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
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
	p.position = Vector3(0.0, 1.9, -0.3)
	add_child(p)
	p.emitting = true


## --- Struck metal (2026-10-15) ------------------------------------------------------
##
## Every blow that lands throws a spray of hot sparks off its plating, like a
## blade on armour: a random HIT_SPARKS_MIN..MAX streaks (fewer, and no flash of
## light, with `Graphics.effects` off) from the point on its body facing the
## player, flying back toward them and up, falling and cooling white -> orange
## -> red. Streaks, not dots: each is two crossed quads aligned to its velocity
## (`particle_flag_align_y`), so it reads as a line from any side. Mesh and
## material are shared, and drawn once at load so the first hit does not stall.

const HIT_SPARKS_MIN := 8
const HIT_SPARKS_MAX := 26
const HIT_SPARKS_PLAIN := Vector2i(3, 6)
const HIT_SPARK_SPEED := Vector2(3.0, 9.0)
const HIT_SPARK_LIFE := 0.5
## Radius of the body the sparks come off, and the band of it a blade can reach.
const HIT_SURFACE := 0.62
const HIT_LOW := 0.8
const HIT_HIGH := 2.2

static var _spark_mesh: ArrayMesh
static var _spark_warmed := false


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	var was_dying := _dying
	super(amount, _from_direction)
	if not was_dying and amount > 0.0:
		_hit_sparks()
		var player := _resolve_player()
		if _react != null and player != null and not _dying:
			_react.call("hit", player.global_position, 0.55 + 0.45 * clampf(amount / HIT_FULL, 0.0, 1.0))


## Where the blow met the plating: on the body's axis at the height the player's
## eye is aimed (within the band a weapon reaches), out to its surface toward
## them.
func _hit_point() -> Array:
	var base := global_position
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam != null else base + Vector3(0.0, 1.6, 2.0)
	var y := clampf(eye.y - 0.35, base.y + HIT_LOW, base.y + HIT_HIGH)
	var axis := Vector3(base.x, y, base.z)
	var out := Vector3(eye.x - base.x, 0.0, eye.z - base.z)
	out = out.normalized() if out.length_squared() > 0.0001 else -global_basis.z
	return [axis + out * HIT_SURFACE, out]


func _hit_sparks() -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var effects: bool = Graphics.effects
	var hit := _hit_point()
	var at: Vector3 = hit[0]
	var out: Vector3 = hit[1]
	var n := randi_range(HIT_SPARKS_MIN, HIT_SPARKS_MAX) if effects \
		else randi_range(HIT_SPARKS_PLAIN.x, HIT_SPARKS_PLAIN.y)
	var p := _spark_burst(n)
	parent.add_child(p)
	p.global_position = at
	# Back off the plating toward the player and up, fanned wide.
	p.direction = (out + Vector3(0.0, 0.55, 0.0)).normalized()
	p.restart()
	get_tree().create_timer(HIT_SPARK_LIFE * 1.6 + 0.2).timeout.connect(p.queue_free)
	if effects:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.38)
		light.light_energy = 2.4
		light.omni_range = 2.6
		light.shadow_enabled = false
		light.light_specular = 0.4
		parent.add_child(light)
		light.global_position = at + out * 0.15
		var t := light.create_tween()
		t.tween_property(light, "light_energy", 0.0, 0.14).set_ease(Tween.EASE_IN)
		t.tween_callback(light.queue_free)


static func _spark_burst(n: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = maxi(n, 1)
	p.lifetime = HIT_SPARK_LIFE
	p.lifetime_randomness = 0.55
	p.explosiveness = 1.0
	p.local_coords = false
	p.spread = 62.0
	p.initial_velocity_min = HIT_SPARK_SPEED.x
	p.initial_velocity_max = HIT_SPARK_SPEED.y
	p.gravity = Vector3(0.0, -11.0, 0.0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	p.particle_flag_align_y = true
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.86, 0.55, 1.0), Color(1.0, 0.6, 0.2, 0.95),
		Color(0.95, 0.32, 0.07, 0.7), Color(0.6, 0.12, 0.03, 0.0)])
	p.color_ramp = ramp
	p.mesh = _streak_mesh()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Two crossed quads along +Y, shared by every burst.
static func _streak_mesh() -> ArrayMesh:
	if _spark_mesh != null:
		return _spark_mesh
	var w := 0.0035
	var h := 0.13
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for across: Vector3 in [Vector3(w, 0.0, 0.0), Vector3(0.0, 0.0, w)]:
		var a := -across + Vector3(0.0, -h * 0.5, 0.0)
		var b := across + Vector3(0.0, -h * 0.5, 0.0)
		var c := across + Vector3(0.0, h * 0.5, 0.0)
		var d := -across + Vector3(0.0, h * 0.5, 0.0)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
	_spark_mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0)
	m.disable_fog = true
	_spark_mesh.surface_set_material(0, m)
	return _spark_mesh


## The spark material compiles on first draw: one burst of a single speck in
## front of the camera at load, once for every enforcer.
func _warm_hit_sparks() -> void:
	if _spark_warmed or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_spark_warmed = true
	var p := _spark_burst(1)
	p.scale_amount_min = 0.01
	p.scale_amount_max = 0.01
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.gravity = Vector3.ZERO
	cam.add_child(p)
	p.position = Vector3(0.0, 0.0, -0.6)
	p.restart()
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


## --- Hit reactions and the parry stagger (2026-10-15) --------------------------------
##
## scripts/enforcer_react.gd, a SkeletonModifier3D on the rig: three hit
## reactions picked at random on every blow that lands, and a long stagger when
## a swipe is parried -- all layered OVER the clip playing, turned away from the
## attacker, the feet held planted by IK. They replace enemy.gd's `_flinch`,
## which tipped the whole model over rigidly, feet and all.
##
## A parry stuns it for PARRY_STAGGER (the stagger's own length; any enemy's is
## the player's `parry_stun` 0.9 s): it stands -- the walk eased to a stop --
## while it reels.

const REACT := preload("res://scripts/enforcer_react.gd")
const PARRY_STAGGER := 1.5
## Damage that plays a hit at full size; lighter blows play it smaller.
const HIT_FULL := 20.0

var _react: SkeletonModifier3D
var _skel: Skeleton3D


func _attach_react() -> void:
	var sk := _model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	_skel = sk[0] as Skeleton3D
	_react = REACT.new()
	_react.name = "HitReact"
	_skel.add_child(_react)
	# The barrel, for aiming the arms: from the cannon arm's joint to the
	# muzzle (a marker on that bone, so its position is in the bone's space).
	var holder := _muzzle.get_parent() as BoneAttachment3D if _muzzle != null else null
	if holder != null:
		_react.call("set_barrel", StringName(holder.bone_name), _muzzle.position)
	_hitbox = HITBOX.new()
	if not _hitbox.call("setup", sk[0], "ARM_L", _parts):
		_hitbox.queue_free()
		_hitbox = null


func _flinch(_impulse: Vector3, _time: float) -> void:
	pass


func _parry_stagger() -> void:
	if _dying:
		return
	_stun_until = maxf(_stun_until, _now() + PARRY_STAGGER)
	var player := _resolve_player()
	if _react != null and player != null:
		_react.call("stagger", player.global_position)


func is_reeling() -> bool:
	return _react != null and _react.call("staggering")
