extends "res://scripts/enemy.gd"

## The DECREPIT ENFORCER (2026-10-15): a rotted, hunched, one-armed enforcer
## gone feral in the sewer, its arm a great pointed shield. Only in the sewer, at
## most three at once, each placed alone (maze.gd `_spawn_decrepit`); 250 health.
##
## The model and its animations are the user's (`models/decrepit.glb`, built by
## tools/build_decrepit.py from models/source/enforcer/PUTRID_ENFORCER_BAKED.blend;
## second delivery 2026-10-17): five BAKED clips -- CRAWL_BAKED, a loping crawl
## (wandering, slow; hunting, frantic), SWIPE_BAKED, the shield swung across its
## front in a lunge (the close attack), JUMP_BAKED, a leap that brings the
## shield's point down into the floor (the JUMP SLASH), DROPKICK_BAKED, a dive, a
## flip and a two-footed kick (the long leap), and DASH_BAKED, a crouch thrown
## into a wide lunge with the shield out (the DASH STAB; in place -- the body is
## driven here). The build takes the root motion out of the swipe, the jump and
## the dropkick, so they play in place, and prints their travel as the ROOT_*
## tables here: the body is moved along them (scaled, before the blow, to land
## it on the player), so the feet stay where the clip puts them.
##
## Like the enforcer, the script is put on an enemy.tscn instance before it
## enters the tree; it throws the skeleton away for its own model.
##
## SEAMLESS: no clip may be seen to start or end. Every change of clip is
## INERTIALIZED on the reaction layer (enforcer_react.gd `crossfade`): the pose
## and how fast it was moving carry across the switch and the difference decays
## smoothly into the new clip. Coming back to the crawl it starts at the moment
## of its cycle nearest the pose it leaves (`_match_phase`), not at frame 0. And
## the BODY's own speed carries too: a move starts with the chase's momentum
## (`_carry`, shed at CARRY_DECEL), the crawl resumes at the move's last speed.
##
## Hunting (`_chase`), fast -- CHASE_SPEED, against the player's 4.25 walk:
##   * the SWIPE: its lunge stretched to land the shield on them;
##     SWIPE_DAMAGE, and unguarded it throws the player off their feet
##     (`player.knock_down`, SWIPE_THROW) -- and as the swipe ends it LEAPS on
##     them where they fell: the jump slash, re-aimed through its flight, its
##     point coming down after their invulnerability and before they are up.
##     A held guard takes it standing (a tenth through), shoved back.
##   * close in (CLOSE_RANGE): ANY of its four moves -- picked at random among
##     those off cooldown (CLOSE_WEIGHTS, the last one used less likely), with a
##     short breath between (CLOSE_PAUSE) -- the swipe, the jump, the dropkick
##     (their travel shrunk to land on them where they stand) or the dash.
##   * further off it closes the gap: at DASH_MIN..DASH_MAX the DASH, always
##     first, the moment it is off cooldown -- the -- a crouch, the lunge, and then it SLIDES at them along the floor,
##     the lunge held and the shield out, scraping sparks, re-aimed as they move,
##     slowing to arrive with its point on them (DASH_DAMAGE); at
##     LEAP_MIN..LEAP_MAX with a clear floor between, now and then a leap -- the
##     JUMP SLASH (JUMP_DAMAGE) or the DROPKICK (DROPKICK_DAMAGE, and unguarded
##     it knocks them down).
##   * a PARRY of any throws it on its back (the whole body toppled about its
##     heels, the limbs flailing over it), it lies there KNOCK_LIE, then it is up
##     fast and straight back into the attack.
## Every blow that lands throws sparks off its plating (the enforcer's) and plays
## one of three hit reactions at random.
##
## It walks the sewer's channel grating like anyone else, and paths on the
## sewer's navmesh, baked from the grating and the stone.

const ENF := preload("res://scripts/enforcer.gd")
const REACT := preload("res://scripts/decrepit_react.gd")
const HITBOX := preload("res://scripts/shield_hitbox.gd")
const MODEL := preload("res://models/decrepit.glb")
## The mesh crouches ~4 m tall at the authored size; drawn at ~2.6 m.
const MODEL_SCALE := 0.65
const MODEL_LIFT := -0.03
const CLIP_CRAWL := &"CRAWL_BAKED"
const CLIP_SWIPE := &"SWIPE_BAKED"
const CLIP_JUMP := &"JUMP_BAKED"
const CLIP_DROPKICK := &"DROPKICK_BAKED"
const CLIP_DASH := &"DASH_BAKED"

enum Move { NONE, SWIPE, JUMP, DROPKICK, DASH }
## Below this the player is in the sewer (sewer.gd SPLIT_Y).
const SPLIT_Y := -4.0
## The crawl's planted feet slide back at 4.886 m/s at the authored size.
const CRAWL_GROUND := 4.886 * MODEL_SCALE
const CHASE_SPEED := 7.4
const WANDER_SPEED := 2.4

## The moves. Contact times, reaches and travel are measured by
## build_decrepit.py ("contacts" and "root" lines), in authored units where the
## name says so (x MODEL_SCALE in the game).
##
## SWIPE: the shield's point is furthest out at clip 0.533 s (f33), SWIPE_TIP
## ahead of the body in place. (How far the clip has travelled by the first hit
## is read off its root table at the time, so moving the hit keeps it aimed.)
const SWIPE_DAMAGE := 25.0
## HIT WINDOWS (2026-10-17): every blow is a [start, end] of clip seconds; while
## one is open the shield's hitbox (shield_hitbox.gd, ARM_L, 1.5x the shield)
## is live and lands the blow the first tick it overlaps the player -- once per
## window. The first window's start is what the lunge / leap aims to land.
## Swipe: the shield sweeps across its front f29-f35.
const SWIPE_HITS := [[0.4833, 0.5833]]
const SWIPE_TIP := 2.74 * MODEL_SCALE
const SWIPE_END := 0.733
const SWIPE_COOLDOWN := 1.3
## The lunge before the blow is stretched (on what is left of it, every frame)
## so the point arrives on them, within these multiples of the clip's own.
const SWIPE_STRETCH := Vector2(0.0, 1.6)
## How hard an unguarded swipe throws the player.
const SWIPE_THROW := 12.0
## A guarded blow shoves the player back this hard.
const BLOCK_SHOVE := 5.0
## JUMP SLASH: the point is in the floor at clip 0.50 s (f31), JUMP_TIP ahead.
const JUMP_DAMAGE := 50.0
## The jump: the point drives into the floor f29-f36.
const JUMP_HITS := [[0.4833, 0.6]]
const JUMP_TIP := 2.57 * MODEL_SCALE
const JUMP_END := 1.15
## DROPKICK: the feet are out in front at clip 1.0 s (f61), DROPKICK_TIP ahead
## and ~1.6 m up. Its early sidestep is left out (it dives straight at them).
const DROPKICK_DAMAGE := 35.0
## The dropkick kicks: its box is on the LEFT FOOT (FOOT_L, 1.5x the foot),
## not the shield. Tracked in game (the foot box's centre, from the body): over
## the top of the flip at f47 (1.4 m ahead, 4.2 m up), out in front f49-f51
## (2.2 m ahead, sweeping down from 3.0 to 1.2 m -- head and chest height), at
## the floor by f53, planted from f55. (The window first set, f55-f61, came from
## "whichever foot is furthest out" and opened after the left one had landed.)
const DROPKICK_HITS := [[0.8167, 0.8833]]
## How far ahead of the body the left foot kicks (metres, in game): what the
## leap is stretched to land on the player.
const DROPKICK_TIP := 2.1
const DROPKICK_END := 1.65
const DROPKICK_THROW := 10.0
## Leaps (jump or dropkick): their flight stretched up to LEAP_STRETCH (and
## shrunk to nothing close in), each on its own cooldown.
const LEAP_MIN := 4.0
const LEAP_MAX := 9.0
const JUMP_COOLDOWN := 3.0
const DROPKICK_COOLDOWN := 3.5
const LEAP_STRETCH := Vector2(0.0, 9.0)
## After the blow lands the travel left in the clip is cut to this share.
const AFTER_CONTACT := 0.3
## Close in, every move is in play: within CLOSE_RANGE it picks among those off
## cooldown by these weights (the move it used last at CLOSE_REPEAT of its
## weight), after a breath of CLOSE_PAUSE seconds from its last move's end.
const CLOSE_RANGE := 3.8
const CLOSE_WEIGHTS := {Move.SWIPE: 0.4, Move.JUMP: 0.2, Move.DROPKICK: 0.2, Move.DASH: 0.2}
const CLOSE_REPEAT := 0.3
const CLOSE_PAUSE := Vector2(0.25, 0.7)
## DASH, the gap closer (2026-10-17, the user: "he should slide to you"): the
## clip crouches and is thrown into a wide lunge, the shield out furthest at
## clip DASH_LUNGE 0.233 s (f15), DASH_TIP ahead. Then the body SLIDES at them
## along the floor for exactly DASH_SLIDE_TIME -- however far (at most
## DASH_TRAVEL), faster from further off -- fast at once and easing off
## (`_ease_slide`), re-aimed every frame on what is left, scraping sparks;
## meanwhile the clip plays on from DASH_LUNGE to its first hit (DASH_HITS),
## slowed to fill the slide (the held lunge). It arrives, the first blow lands,
## there, and the rest of the clip plays out at 1x to DASH_END (any later hits
## on the way). A FIXED slide (the user's
## choice, 2026-10-17) puts the blow at a fixed moment of the clip, so the dash
## has ordinary markers like the other moves -- its parry cues (DASH_CUES) are
## points in its clip.
const DASH_DAMAGE := 15.0
const DASH_LUNGE := 0.233
## The dash's blows, [start, end] clip seconds: the FIRST start is its arrival
## (the slide fills the clip from DASH_LUNGE to it); after it the clip plays at
## 1x (the shield held out, f18-f21).
const DASH_HITS := [[0.1667, 0.3]]
const DASH_END := 0.35
const DASH_SLIDE_TIME := 0.4
const DASH_TIP := 2.985 * MODEL_SCALE
const DASH_TRAVEL := 13.0
## From the edge of close range out: no gap where it only crawls.
const DASH_MIN := CLOSE_RANGE
const DASH_MAX := 14.0
const DASH_COOLDOWN := 2.2
## Sparks off the plating scraping the floor while it slides, this often.
const SCRAPE_EVERY := 0.05
const TURN_SWIPE := 12.0
const TURN_JUMP := 7.0
const TURN_DASH := 14.0

## PARRY CUES (player.gd `parry_cue`): each move's own markers -- `*_CUES`,
## moments in its clip, set on their own (not worked out from the hits; placed,
## dragged, added and deleted in tools/timing_preview) -- from each of which the
## player is listened to for `*_LISTEN` seconds; a block press inside that
## parries the next blow to land (the latest cue before a blow is the one it
## uses). A move may have several hits and several cues (cue -> hit -> cue ->
## hit), or no cue at all (then the plain guard-timing rule, player.gd). As set,
## each window closes as its blow lands; moving a cue or a hit changes that.
## The dash's cues are points in its clip too: during the slide the clip runs at
## (first hit - DASH_LUNGE) / DASH_SLIDE_TIME, so 0.2667 is 0.2 s of slide
## before the arrival. Every time is put on the move's own clock at its start
## (`_events`), never read off the clip's position -- far off, the animation
## LOD advances that in strides (a cue opened 0.15 s late from 12 m).
const SWIPE_CUES := [0.283]
const JUMP_CUES := [0.2]
const DROPKICK_CUES := [0.75]
const DASH_CUES := [0.25]
const SWIPE_LISTEN := 0.25
const JUMP_LISTEN := 0.3
const DROPKICK_LISTEN := 0.25
const DASH_LISTEN := 0.2

## Seamless: every clip change is inertialized over at most these (the offset
## settles sooner when it is small or already closing).
const BLEND_INTO_MOVE := 0.22
const BLEND_OUT_OF_MOVE := 0.35
const BLEND_CRAWL := 0.3
## How fast the crawl's playback rate may change (per second).
const CRAWL_RATE_EASE := 7.0
## The body's speed carried into a move, shed at this rate (m/s^2): from a full
## chase, gone in ~0.3 s.
const CARRY_DECEL := 26.0
## Parried: it topples back about its heels, lies, and is up again.
const KNOCK_FALL := 0.4
const KNOCK_LIE := 1.0
const KNOCK_RISE := 0.55
const KNOCK_PITCH := 1.32
const KNOCK_PIVOT := Vector3(0.0, 0.0, 0.55)
## Its glow is the moss's own green (sewer.gd MOSS_GLOW), so from any distance
## it reads as one more patch of moss in the dark -- until it is close enough to
## make out a face: two X-shaped eyes and the enforcers' crystal in its chest.
const GLOW := Color(0.32, 1.0, 0.62)
## Each eye is an X of two bars, EYE_BAR long and EYE_THICK thick (metres).
const EYE_BAR := 0.085
const EYE_THICK := 0.014
const EYE_BRIGHT := 1.8
## The chest crystal: an elongated octahedron (the enforcer's is one), half
## proud of the plating, CRYSTAL_SIZE across / tall / deep.
const CRYSTAL_SIZE := Vector3(0.11, 0.2, 0.08)
const CRYSTAL_PROUD := 0.035
const CRYSTAL_ENERGY := 3.2
## And a faint glow ahead of its face, so close up an attack can be read.
const GLOW_ENERGY := 0.75
const GLOW_RANGE := 4.0
const GLOW_AHEAD := Vector3(0.0, 1.85, -0.75)

## The clips' travel (build_decrepit.py), every 2 frames: [seconds, forward, left].
const ROOT_SWIPE := [[0.0, 0.0, 0.0], [0.0333, 0.142, 0.0], [0.0667, 0.427, 0.0], [0.1, 0.627, 0.0],
	[0.1333, 0.652, 0.0], [0.1667, 0.703, 0.0], [0.2, 0.779, 0.0], [0.2333, 0.881, 0.0],
	[0.2667, 0.9, 0.0], [0.3, 0.943, 0.0], [0.3333, 1.022, 0.0], [0.3667, 1.152, 0.0],
	[0.4, 1.346, 0.0], [0.4333, 1.616, 0.0], [0.4667, 1.978, 0.0], [0.5, 2.073, -0.032],
	[0.5333, 2.36, -0.128], [0.5667, 2.838, -0.289], [0.6, 3.149, -0.393], [0.6333, 3.149, -0.393],
	[0.6667, 3.149, -0.393], [0.7, 3.149, -0.393], [0.7333, 3.149, -0.393]]
const ROOT_JUMP := [[0.0, 0.0, 0.0], [0.0333, 0.002, -0.003], [0.0667, 0.017, -0.025], [0.1, 0.066, -0.097],
	[0.1333, 0.179, -0.265], [0.1667, 0.295, -0.403], [0.2, 0.332, -0.403], [0.2333, 0.38, -0.402],
	[0.2667, 0.38, -0.402], [0.3, 0.383, -0.401], [0.3333, 0.397, -0.395], [0.3667, 0.434, -0.378],
	[0.4, 0.511, -0.344], [0.4333, 0.652, -0.281], [0.4667, 0.884, -0.178], [0.5, 1.045, -0.107],
	[0.5333, 1.045, -0.107], [0.5667, 1.045, -0.107], [0.6, 1.058, -0.107], [0.6333, 1.155, -0.107],
	[0.6667, 1.315, -0.107], [0.7, 1.504, -0.107], [0.7333, 1.689, -0.107], [0.7667, 1.836, -0.107],
	[0.8, 1.95, -0.107], [0.8333, 2.071, -0.107], [0.8667, 2.238, -0.107], [0.9, 2.416, -0.107],
	[0.9333, 2.5, -0.107], [0.9667, 2.498, -0.107], [1, 2.485, -0.107], [1.0333, 2.45, -0.107],
	[1.0667, 2.382, -0.107], [1.1, 2.271, -0.107], [1.1333, 2.195, -0.107], [1.1667, 2.195, -0.107],
	[1.2, 2.195, -0.107], [1.2333, 2.195, -0.107]]
const ROOT_DROPKICK := [[0.0, 0.0, 0.0], [0.0333, 0.0, -0.351], [0.0667, 0.0, -0.731], [0.1, 0.022, -0.87],
	[0.1333, 0.175, -0.936], [0.1667, 0.432, -0.982], [0.2, 0.741, -1.012], [0.2333, 1.05, -1.029],
	[0.2667, 1.307, -1.036], [0.3, 1.46, -1.038], [0.3333, 1.481, -1.038], [0.3667, 1.481, -1.038],
	[0.4, 1.481, -1.038], [0.4333, 1.481, -1.038], [0.4667, 1.481, -1.038], [0.5, 1.481, -1.038],
	[0.5333, 1.481, -1.038], [0.5667, 1.481, -1.038], [0.6, 1.481, -1.038], [0.6333, 1.481, -1.038],
	[0.6667, 1.481, -1.038], [0.7, 1.481, -1.038], [0.7333, 1.481, -1.038], [0.7667, 1.481, -1.038],
	[0.8, 1.481, -1.038], [0.8333, 1.483, -1.038], [0.8667, 1.489, -1.038], [0.9, 1.495, -1.038],
	[0.9333, 1.501, -1.038], [0.9667, 1.531, -1.038], [1, 1.651, -1.038], [1.0333, 2.335, -1.038],
	[1.0667, 3.114, -1.039], [1.1, 3.19, -1.046], [1.1333, 3.179, -1.061], [1.1667, 3.153, -1.084],
	[1.2, 3.12, -1.111], [1.2333, 3.089, -1.139], [1.2667, 3.069, -1.165], [1.3, 3.066, -1.176],
	[1.3333, 3.066, -1.176], [1.3667, 3.066, -1.177], [1.4, 3.066, -1.178], [1.4333, 3.066, -1.181],
	[1.4667, 3.066, -1.187], [1.5, 3.066, -1.197], [1.5333, 3.066, -1.213], [1.5667, 3.066, -1.236],
	[1.6, 3.067, -1.246], [1.6333, 3.067, -1.257], [1.6667, 3.068, -1.266], [1.7, 3.068, -1.269]]

## The sewer it hunts (maze.gd), for wandering cell to cell.
var sewer: Node3D = null

var _built := false
var _model: Node3D
var _parts: Array[MeshInstance3D] = []
var _tip: Node3D
var _state_proxy: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _react: SkeletonModifier3D
var _clip := &""
var _visual_rest := Transform3D.IDENTITY

var _move := Move.NONE
var _move_t := 0.0
var _root_prev := Vector2.ZERO
var _connected := false
var _end_at := INF
var _guard_seen := -1
var _target: Node3D = null
var _swipe_ready := 0.0
var _jump_ready := 0.0
var _dropkick_ready := 0.0
var _dash_ready := 0.0
var _roll_at := 0.0
## Close in, no move before this (the breath after the last one).
var _close_ready := 0.0
var _last_move := Move.NONE
## The dash: 0 crouch and lunge, 1 sliding, 2 rising out of it.
var _dash_phase := 0
var _slide_t := 0.0
var _slide_u := 0.0
var _slide_left := 0.0
var _scrape_t := 0.0
## The move under way's blows and cues, on its own clock (seconds since it
## began), sorted; computed at its start (`_events`).
var _hit_windows: Array = []
var _cue_times: Array = []
## Windows whose blow has landed, by index.
var _landed := {}
## The shield's hitbox (shield_hitbox.gd), on ARM_L; and the left foot's, on
## FOOT_L, for the dropkick.
var _hitbox: Node = null
var _foot_box: Node = null
## The swipe knocked them down: the jump follows as it ends.
var _combo_pending := false
## Body speed carried into a move, and the last speed a move moved it at.
var _carry := Vector3.ZERO
var _move_vel := Vector3.ZERO
var _skel: Skeleton3D
## Per clip: the rotation / position tracks used to match a pose.
var _match_tracks := {}
var _twitch_at := 0.0
## Seconds into a parried knock-down, or -1.
var _knock_t := -1.0
## How many jump slashes followed a swipe's knock-down (for the tests).
var combos := 0


func _init() -> void:
	armed = false
	max_health = 250.0
	move_speed = CHASE_SPEED
	acceleration = 30.0
	vision_cone_degrees = 150.0
	sight_needs_line_of_sight = true
	sight_memory = 8.0
	eye_height = 1.9
	aggro_range = 40.0
	wanders = true
	wander_speed = WANDER_SPEED
	can_slam = false
	can_spin = false
	can_lunge = false
	can_normal = false
	attack_damage = SWIPE_DAMAGE
	knockback_resistance = 0.35
	tint_albedo = false
	base_glow = 0.0
	hit_punch = 0.0
	dormant_range = 50.0
	display_name = "DECREPIT ENFORCER"
	drop_rolls_min = 1
	drop_rolls_max = 2
	drop_odds = {&"gold_crystal": 0.45, &"bone_fragment": 0.4, &"health_potion": 0.2}


func is_decrepit() -> bool:
	return true


# --- The body ---------------------------------------------------------------------

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
	_model.name = "Decrepit"
	# Authored facing +Z; enemies face -Z.
	_model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * MODEL_SCALE),
		Vector3(0.0, MODEL_LIFT, 0.0))
	vis.add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_parts.append(m)
	_tip = _model.find_child("ShieldTip", true, false) as Node3D
	# enemy.gd tints the material of its `mesh` by state; this one keeps its own
	# colours, so that machinery gets a proxy that is never drawn.
	_state_proxy = MeshInstance3D.new()
	_state_proxy.name = "StateProxy"
	_state_proxy.mesh = SphereMesh.new()
	_state_proxy.visible = false
	vis.add_child(_state_proxy)
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.55
		cap.height = 2.4
		cs.shape = cap
		cs.position = Vector3(0.0, 1.2, 0.0)
	var ag := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if ag != null:
		ag.radius = 0.6
		ag.height = 2.4
		ag.path_desired_distance = 0.8


func _ready() -> void:
	var plain := StandardMaterial3D.new()
	_state_proxy.material_override = plain
	mesh = _state_proxy
	super()
	name = "DecrepitEnforcer"
	add_to_group(&"decrepits")
	_visual_rest = visual.transform
	_setup_clips()
	_attach_eyes()
	_attach_crystal()
	_attach_react()
	_warm_sparks.call_deferred()
	_twitch_at = _now() + randf_range(0.6, 1.8)


func _setup_clips() -> void:
	if anim == null:
		return
	if anim.has_animation(CLIP_CRAWL):
		anim.get_animation(CLIP_CRAWL).loop_mode = Animation.LOOP_LINEAR
	for c in [CLIP_SWIPE, CLIP_JUMP, CLIP_DROPKICK, CLIP_DASH]:
		if anim.has_animation(c):
			anim.get_animation(c).loop_mode = Animation.LOOP_NONE
	_play_clip(CLIP_CRAWL, 0.0, 0.0)


## Plays `clip` at `rate`; switching clips is inertialized over at most `blend`
## on the reaction layer (see the header; the AnimationPlayer's own fade stalls
## into a clip held still and lurches at the start of others). The crawl is
## entered at the moment of its cycle nearest the pose shown.
func _play_clip(clip: StringName, rate: float, blend := 0.2, restart := false) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if _clip == clip and not restart and anim.is_playing():
		anim.speed_scale = rate
		return
	var start := 0.0
	if clip == CLIP_CRAWL:
		start = _match_phase(clip)
	if _react != null:
		_react.call("crossfade", blend)
	_clip = clip
	anim.play(clip, 0.0, 1.0)
	anim.speed_scale = rate
	anim.seek(start, true)


## The time in `clip` whose pose is nearest the pose shown last frame: every
## bone's rotation (radians apart) and position (rig units), checked at 48
## points of the clip. 0 if there is no pose to match.
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


## The eyes: an X of light in each of the mask's lenses. The face, the chest
## crystal and the glow ahead of it are all the moss's green.
func _attach_eyes() -> void:
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = GLOW * EYE_BRIGHT
	_eye_mat.disable_receive_shadows = true
	_glow = OmniLight3D.new()
	_glow.name = "FaceGlow"
	_glow.light_color = GLOW
	_glow.light_energy = GLOW_ENERGY
	_glow.omni_range = GLOW_RANGE
	_glow.omni_attenuation = 1.3
	_glow.shadow_enabled = false
	_glow.light_specular = 0.5
	_glow.light_cull_mask = (1 << 15) | 1
	_glow.position = GLOW_AHEAD
	add_child(_glow)
	for n in ["EyeL", "EyeR"]:
		var marker := _model.find_child(n, true, false) as Node3D
		if marker == null:
			continue
		# The markers carry the rig's scale (armature x model); bars are sized in
		# metres against it. Their local axes are the model's at rest: X across
		# the face, Y up, Z out of it.
		var s := _marker_scale(marker)
		var bar := BoxMesh.new()
		bar.size = Vector3(EYE_BAR, EYE_THICK, EYE_THICK) / s
		var x := Node3D.new()
		x.name = "X"
		x.position = Vector3(0.0, 0.0, 0.012 / s)
		marker.add_child(x)
		for a: float in [PI * 0.25, -PI * 0.25]:
			var mi := MeshInstance3D.new()
			mi.mesh = bar
			mi.material_override = _eye_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.rotation = Vector3(0.0, 0.0, a)
			x.add_child(mi)


## The crystal in its chest, on the "Chest" marker (build_decrepit.py: the
## torso's plating just under the mask), half proud of it.
func _attach_crystal() -> void:
	var marker := _model.find_child("Chest", true, false) as Node3D
	if marker == null:
		return
	var s := _marker_scale(marker)
	var h := CRYSTAL_SIZE / s * 0.5
	var pts := [Vector3(0, h.y, 0), Vector3(0, -h.y, 0), Vector3(h.x, 0, 0), Vector3(0, 0, h.z),
		Vector3(-h.x, 0, 0), Vector3(0, 0, -h.z)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for apex in [0, 1]:
		for i in 4:
			var a: Vector3 = pts[2 + i]
			var b: Vector3 = pts[2 + (i + 1) % 4]
			var tip: Vector3 = pts[apex]
			# Wound outward (Godot's front faces are clockwise seen from outside).
			if apex == 0:
				st.add_vertex(tip); st.add_vertex(b); st.add_vertex(a)
			else:
				st.add_vertex(tip); st.add_vertex(a); st.add_vertex(b)
	st.generate_normals()
	_crystal_mat = StandardMaterial3D.new()
	_crystal_mat.albedo_color = GLOW.darkened(0.6)
	_crystal_mat.roughness = 0.15
	_crystal_mat.metallic_specular = 0.8
	_crystal_mat.emission_enabled = true
	_crystal_mat.emission = GLOW
	_crystal_mat.emission_energy_multiplier = CRYSTAL_ENERGY
	_crystal_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Crystal"
	mi.mesh = st.commit()
	mi.material_override = _crystal_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.0, CRYSTAL_PROUD / s)
	mi.rotation = Vector3(0.0, 0.0, 0.18)
	marker.add_child(mi)


static func _marker_scale(marker: Node3D) -> float:
	if marker.is_inside_tree():
		return maxf(marker.global_basis.get_scale().x, 0.001)
	return MODEL_SCALE * 1.746


## --- The flicker: insane, tripped energy ---------------------------------------------
##
## Every glow on it -- the X eyes, the chest crystal, the face glow -- stutters on
## its own fits: under a restless shimmer (fast noise), at random intervals it
## cuts OUT for a few frames, STUTTERS on and off at 14-30 Hz, SURGES too bright,
## or sags DIM. The eyes and the crystal have a fit each, out of step; now and
## then one fit runs through both at once, a surge through the whole machine.

var _glow: OmniLight3D
var _crystal_mat: StandardMaterial3D
var _flicker_noise := FastNoiseLite.new()
var _fit_eyes := {"mode": &"", "until": 0.0, "next": 0.0, "rate": 20.0, "seed": 0.0}
var _fit_core := {"mode": &"", "until": 0.0, "next": 0.0, "rate": 20.0, "seed": 37.0}
## Last levels applied (for the tests).
var eye_level := 1.0
var core_level := 1.0


func _process(_delta: float) -> void:
	# Not drawn while the camera is above ground (12 m of stone between).
	var cam := get_viewport().get_camera_3d()
	if cam != null and visual != null:
		# On a different level from the camera (12 m of stone between): hidden.
		visual.visible = (cam.global_position.y < SPLIT_Y) == (global_position.y < SPLIT_Y)
	if _dying or _eye_mat == null:
		return
	var now := _now()
	var e := _fit(_fit_eyes, _fit_core, now)
	var c := _fit(_fit_core, _fit_eyes, now)
	eye_level = e
	core_level = c
	_eye_mat.albedo_color = GLOW * (EYE_BRIGHT * e)
	if _crystal_mat != null:
		_crystal_mat.emission_energy_multiplier = CRYSTAL_ENERGY * c
	if _glow != null:
		_glow.light_energy = GLOW_ENERGY * (0.55 * e + 0.45 * c)


func _fit(st: Dictionary, other: Dictionary, now: float) -> float:
	if now >= float(st["next"]):
		var roll := randf()
		var mode := &"dim"
		var dur := randf_range(0.18, 0.55)
		if roll < 0.32:
			mode = &"out"
			dur = randf_range(0.035, 0.17)
		elif roll < 0.62:
			mode = &"stutter"
			dur = randf_range(0.12, 0.42)
			st["rate"] = randf_range(14.0, 30.0)
		elif roll < 0.84:
			mode = &"surge"
			dur = randf_range(0.04, 0.11)
		st["mode"] = mode
		st["until"] = now + dur
		st["next"] = now + dur + randf_range(0.06, 0.85)
		# A tripped surge through the whole machine.
		if randf() < 0.22:
			other["mode"] = mode
			other["until"] = st["until"]
			other["rate"] = st["rate"]
			other["next"] = maxf(float(other["next"]), float(st["until"]) + 0.05)
	var shimmer := 0.78 + 0.22 * _flicker_noise.get_noise_1d(now * 11.0 * 60.0 + float(st["seed"]) * 100.0)
	if now < float(st["until"]):
		match st["mode"]:
			&"out":
				return 0.03
			&"stutter":
				return shimmer if fmod(now * float(st["rate"]), 1.0) < 0.5 else 0.06
			&"surge":
				return 1.9
			&"dim":
				return shimmer * 0.32
	return shimmer


func _attach_react() -> void:
	var sk := _model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	_skel = sk[0] as Skeleton3D
	_react = REACT.new()
	_react.name = "HitReact"
	_skel.add_child(_react)
	# The shield's hitbox, riding its bone.
	_hitbox = HITBOX.new()
	if not _hitbox.call("setup", _skel, "ARM_L", _parts):
		_hitbox.queue_free()
		_hitbox = null
	_foot_box = HITBOX.new()
	if not _foot_box.call("setup", _skel, "FOOT_L", _parts, "FootHitbox"):
		_foot_box.queue_free()
		_foot_box = null


# --- Each tick ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dying:
		super(delta)
		return
	var now := _now()
	if _knock_t >= 0.0:
		_run_knockdown(delta, now)
		return
	if _move != Move.NONE:
		if now < _stun_until:
			# Knocked out of it by a blow (the player's stagger roll).
			_end_move()
		else:
			if not is_on_floor():
				velocity += get_gravity() * delta
			_advance_anim(delta)
			_run_move(delta, now)
			return
	super(delta)
	if not _dying and not _dormant and _knock_t < 0.0 and _move == Move.NONE:
		_animate(delta)


## Not above ground: it lives down here.
func _can_see(player: Node3D, distance: float) -> bool:
	if _other_level(player):
		return false
	return super(player, distance)


func _chase(delta: float, now: float, player: Node3D, flat: Vector3, distance: float, _gap: float) -> bool:
	if _other_level(player):
		_hold(delta)
		return true
	if now >= _twitch_at:
		_twitch_at = now + randf_range(0.7, 2.2)
		if _react != null:
			_react.call("twitch", player.global_position)
	var dy := absf(player.global_position.y - global_position.y)
	var pick := Move.NONE
	if distance <= CLOSE_RANGE:
		# Close in: any move that is ready.
		if now >= _close_ready and dy < 1.6 and _clear_to(player, 1.3):
			pick = _pick_close(now)
	elif dy < 1.2:
		# Further off it closes the gap -- the DASH first, always, the moment it
		# is ready (the user, 2026-10-17); a leap now and then only while the
		# dash is cooling down.
		if now >= _dash_ready and distance >= DASH_MIN and distance <= DASH_MAX \
				and _clear_to(player, 1.3) and _clear_to(player, 0.45):
			pick = Move.DASH
		elif now >= _roll_at:
			_roll_at = now + 0.35
			if distance >= LEAP_MIN and distance <= LEAP_MAX and randf() < 0.45 \
					and _clear_to(player, 1.3) and _clear_to(player, 0.45):
				var leaps: Array = []
				if now >= _jump_ready:
					leaps.append(Move.JUMP)
				if now >= _dropkick_ready:
					leaps.append(Move.DROPKICK)
				if not leaps.is_empty():
					pick = leaps[randi() % leaps.size()]
	if pick != Move.NONE:
		_start_move(pick, player)
		# Its first step this same tick: a move that begins standing still for
		# a tick reads as a seam.
		_run_move(delta, now)
		return true
	_walk_to(delta, now, player.global_position, CHASE_SPEED)
	_face_velocity(flat)
	return true


## Close in: one of the moves off cooldown, by CLOSE_WEIGHTS, the last one used
## less likely. NONE if none is ready.
func _pick_close(now: float) -> int:
	var ready := {Move.SWIPE: now >= _swipe_ready, Move.JUMP: now >= _jump_ready,
		Move.DROPKICK: now >= _dropkick_ready, Move.DASH: now >= _dash_ready}
	var total := 0.0
	var weights := {}
	for m in CLOSE_WEIGHTS:
		if not ready[m]:
			continue
		var w: float = CLOSE_WEIGHTS[m] * (CLOSE_REPEAT if m == _last_move else 1.0)
		weights[m] = w
		total += w
	if total <= 0.0:
		return Move.NONE
	var roll := randf() * total
	for m in weights:
		roll -= weights[m]
		if roll <= 0.0:
			return m
	return weights.keys()[-1]


## Wandering the sewer: from cell to cell along its navmesh, a few cells at a
## time, stopping to look about.
func _wander(delta: float, now: float) -> Vector3:
	if sewer == null or not is_instance_valid(sewer):
		return super(delta, now)
	if now < _wander_pause_until:
		_look_phase += delta * deg_to_rad(look_around_speed)
		rotation.y = _look_centre + sin(_look_phase) * deg_to_rad(look_around_degrees)
		return Vector3.ZERO
	if not _has_wander_target:
		_pick_sewer_target()
	var to := _wander_target - global_position
	to.y = 0.0
	if to.length() < 1.3:
		_has_wander_target = false
		_wander_pause_until = now + randf_range(0.8, 2.6)
		_look_centre = rotation.y
		_look_phase = 0.0
		return Vector3.ZERO
	var dir := _path_dir(now, _wander_target)
	_face(dir)
	return dir * wander_speed


func _pick_sewer_target() -> void:
	var map = sewer.get("map")
	if map == null:
		return
	var here: Vector3 = global_position - map.origin
	var cs: float = map.cell_size
	var cell := Vector2i(roundi(here.x / cs), roundi(here.z / cs))
	var keys: Array = map.cells.keys()
	var near: Array = []
	for k: Vector2i in keys:
		var d := absi(k.x - cell.x) + absi(k.y - cell.y)
		if d >= 2 and d <= 7:
			near.append(k)
	if near.is_empty():
		near = keys
	_wander_target = map.to_world(near[randi() % near.size()])
	_has_wander_target = true


func _walk_to(delta: float, now: float, goal: Vector3, speed: float) -> void:
	var dir := _path_dir(now, goal)
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	move_and_slide()


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


func _hold(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	move_and_slide()


## A clear line through stone from its body to the player's, at `height`.
func _clear_to(player: Node3D, height: float) -> bool:
	var from := global_position + Vector3(0.0, height, 0.0)
	var to := player.global_position + Vector3(0.0, minf(height, 1.0), 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 2 | 256)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The crawl, at the rate that keeps its feet on the floor: slow ambling,
## frantic hunting; eased still when it stands or reels.
func _animate(delta: float) -> void:
	if is_stunned():
		if _clip != CLIP_CRAWL:
			_play_clip(CLIP_CRAWL, 0.0, BLEND_CRAWL, true)
		elif anim != null:
			anim.speed_scale = move_toward(anim.speed_scale, 0.0, delta * 6.0)
		return
	var v := get_real_velocity()
	var speed := Vector2(v.x, v.z).length()
	var want := clampf(speed / CRAWL_GROUND, 0.35, 2.6) if speed > 0.2 else 0.0
	if _clip != CLIP_CRAWL:
		_play_clip(CLIP_CRAWL, 0.0, BLEND_CRAWL, true)
	elif anim != null:
		# Eased, never jumped: a crawl starting at full rate from a standstill
		# reads as a new clip starting.
		anim.speed_scale = move_toward(anim.speed_scale, want, delta * CRAWL_RATE_EASE)


# --- The moves ---------------------------------------------------------------------

## Everything about a move its runner needs.
static func _spec(kind: int) -> Dictionary:
	match kind:
		Move.SWIPE:
			return {"clip": CLIP_SWIPE, "table": ROOT_SWIPE, "hits": SWIPE_HITS, "tip": SWIPE_TIP,
				"cues": SWIPE_CUES, "listen": SWIPE_LISTEN, "stretch": SWIPE_STRETCH, "end": SWIPE_END,
				"turn": TURN_SWIPE, "straight": false}
		Move.JUMP:
			return {"clip": CLIP_JUMP, "table": ROOT_JUMP, "hits": JUMP_HITS, "tip": JUMP_TIP,
				"cues": JUMP_CUES, "listen": JUMP_LISTEN, "stretch": LEAP_STRETCH, "end": JUMP_END,
				"turn": TURN_JUMP, "straight": false}
		Move.DROPKICK:
			return {"clip": CLIP_DROPKICK, "table": ROOT_DROPKICK, "hits": DROPKICK_HITS,
				"cues": DROPKICK_CUES, "listen": DROPKICK_LISTEN,
				"tip": DROPKICK_TIP, "stretch": LEAP_STRETCH,
				"end": DROPKICK_END, "turn": TURN_JUMP, "straight": true}
		_:
			# Its blow and its end come when the slide arrives (`_dash_step`).
			return {"clip": CLIP_DASH, "table": [], "hits": DASH_HITS, "tip": DASH_TIP,
				"cues": DASH_CUES, "listen": DASH_LISTEN,
				"stretch": Vector2.ONE, "end": DASH_END, "turn": TURN_DASH,
				"straight": true}


func _start_move(kind: int, player: Node3D) -> void:
	# The speed it was going at is carried in, not dropped.
	var v := get_real_velocity()
	_carry = Vector3(v.x, 0.0, v.z) if _move == Move.NONE else _move_vel
	_move = kind
	_move_t = 0.0
	_root_prev = Vector2.ZERO
	_connected = false
	_combo_pending = false
	_target = player
	var s := _spec(kind)
	_events(kind, s)
	var now := _now()
	_last_move = kind
	match kind:
		Move.SWIPE:
			_swipe_ready = now + SWIPE_COOLDOWN
		Move.DASH:
			_dash_ready = now + DASH_COOLDOWN
			_dash_phase = 0
			_scrape_t = 0.0
		Move.JUMP:
			_jump_ready = now + JUMP_COOLDOWN
		Move.DROPKICK:
			_dropkick_ready = now + DROPKICK_COOLDOWN
	_play_clip(s["clip"], 1.0, BLEND_INTO_MOVE, true)
	_link_guard(player)


func _end_move() -> void:
	var player := _target
	if _combo_pending and player != null and is_instance_valid(player) and not _dying:
		# Down -- and as the swipe ends it is on them before they are up.
		_combo_pending = false
		combos += 1
		_start_move(Move.JUMP, player)
		return
	_move = Move.NONE
	_target = null
	_combo_pending = false
	_set_hitbox(false)
	# A breath before the next one close in.
	_close_ready = _now() + randf_range(CLOSE_PAUSE.x, CLOSE_PAUSE.y)
	# The crawl takes up the speed the move left it moving at.
	velocity.x = _move_vel.x
	velocity.z = _move_vel.z
	_play_clip(CLIP_CRAWL, clampf(_move_vel.length() / CRAWL_GROUND, 0.0, 2.6), BLEND_OUT_OF_MOVE, true)


## The move's blows, cues and end, from clip seconds to its own clock: the same
## for every move but the dash, whose clip runs slowed through the slide
## (`_dash_clock`). Sorted.
func _events(kind: int, s: Dictionary) -> void:
	_hit_windows.clear()
	_cue_times.clear()
	_landed.clear()
	var hits := _windows(s["hits"])
	var cues: Array = (s["cues"] as Array).duplicate()
	cues.sort()
	var arrive: float = hits[0][0] if not hits.is_empty() else DASH_LUNGE
	for w in hits:
		if kind == Move.DASH:
			_hit_windows.append([_dash_clock(float(w[0]), arrive), _dash_clock(float(w[1]), arrive)])
		else:
			_hit_windows.append([float(w[0]), float(w[1])])
	for c in cues:
		_cue_times.append(_dash_clock(float(c), arrive) if kind == Move.DASH else float(c))
	var end: float = s["end"]
	_end_at = _dash_clock(end, arrive) if kind == Move.DASH else end


## A moment of the dash's clip on the move's clock: at 1x up to the lunge, the
## lunge to `arrive` (its first blow) slowed to fill DASH_SLIDE_TIME, at 1x after.
static func _dash_clock(clip_t: float, arrive: float) -> float:
	if clip_t <= DASH_LUNGE:
		return clip_t
	var span := maxf(arrive - DASH_LUNGE, 0.0001)
	if clip_t <= arrive:
		return DASH_LUNGE + (clip_t - DASH_LUNGE) / span * DASH_SLIDE_TIME
	return DASH_LUNGE + DASH_SLIDE_TIME + (clip_t - arrive)


## A move's hit windows, each [start, end] in order, sorted by start.
static func _windows(list: Array) -> Array:
	var out: Array = []
	for w in list:
		var a := float(w[0])
		var b := float(w[1])
		out.append([minf(a, b), maxf(a, b)])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out


## The first blow's window opening (the one a lunge or a leap aims), INF if none.
func _first_hit() -> float:
	return float(_hit_windows[0][0]) if not _hit_windows.is_empty() else INF


## How much further the carried speed will still take it, forward.
func _carry_ahead() -> float:
	var c := _carry.length()
	if c < 0.01:
		return 0.0
	return maxf(_carry.dot(-global_basis.z) / c, 0.0) * c * c / (2.0 * CARRY_DECEL)


func _run_move(delta: float, _now_t: float) -> void:
	var player := _target
	if player == null or not is_instance_valid(player):
		_end_move()
		return
	var s := _spec(_move)
	# The first blow: the lunge or the leap is stretched to land it on them.
	var contact := _first_hit()
	var prev := _move_t
	_move_t += delta
	var to := player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var fwd := 0.0
	var left := 0.0
	if _move == Move.DASH:
		fwd = _dash_step(delta, flat)
	else:
		var r := _root_at(s["table"], _move_t)
		var d := r - _root_prev
		_root_prev = r
		fwd = d.x * MODEL_SCALE
		left = 0.0 if s["straight"] else d.y * MODEL_SCALE
		if _move_t < contact:
			# Stretched so the blow arrives on them: the travel left before it
			# lands, against how far they are past where it would.
			var left_root: float = (_root_at(s["table"], contact).x - r.x) * MODEL_SCALE
			var need: float = flat.length() - float(s["tip"]) - _carry_ahead()
			var stretch: Vector2 = s["stretch"]
			if left_root + fwd > 0.01:
				fwd *= clampf(need / (left_root + fwd), stretch.x, stretch.y)
		else:
			fwd *= AFTER_CONTACT
	# Turning to follow them until just before the blow (the dash: until the
	# last quarter of its slide).
	var tracking := _move_t < contact - 0.08
	if _move == Move.DASH:
		tracking = _dash_phase == 0 or (_dash_phase == 1 and _slide_u < 0.75)
	if tracking and flat.length_squared() > 0.01:
		var want := atan2(-flat.x, -flat.z)
		rotation.y = rotate_toward(rotation.y, want, float(s["turn"]) * delta)
	var step := -global_basis.z * fwd - global_basis.x * left
	# The speed it came in with, shed fast: no dead stop as a move begins.
	step += _carry * delta
	_carry = _carry.move_toward(Vector3.ZERO, CARRY_DECEL * delta)
	velocity.x = step.x / delta
	velocity.z = step.z / delta
	move_and_slide()
	var rv := get_real_velocity()
	_move_vel = Vector3(rv.x, 0.0, rv.z)
	velocity.x = 0.0
	velocity.z = 0.0
	# Its cues and blows as the move's clock passes them, cues first: from a cue
	# the player is listened to for a block press; each blow uses the latest.
	for cue in _cue_times:
		if prev < cue and _move_t >= cue and player.has_method("parry_cue"):
			player.call("parry_cue", self, float(s["listen"]))
	_tick_windows(prev, player)
	if _move != Move.NONE and _move_t >= _end_at:
		_end_move()


## The dash, a step: the crouch and the lunge (the clip, the body still but for
## the speed it came in with); then held at the lunge and slid at them; on
## arrival the blow and the clip again, rising. Returns the forward step.
func _dash_step(delta: float, flat: Vector3) -> float:
	var gap := maxf(flat.length() - DASH_TIP - _carry_ahead(), 0.0)
	match _dash_phase:
		0:
			if _move_t >= DASH_LUNGE:
				# Lunged: the slide, its time fixed, the clip slowed to fill it.
				_dash_phase = 1
				if anim != null:
					var w := _windows(DASH_HITS)
					var arrive: float = w[0][0] if not w.is_empty() else DASH_LUNGE
					anim.speed_scale = maxf(arrive - DASH_LUNGE, 0.0) / DASH_SLIDE_TIME
				_slide_t = 0.0
				_slide_u = 0.0
				_slide_left = minf(gap, DASH_TRAVEL)
			return 0.0
		1:
			_slide_t += delta
			var u := minf(_slide_t / DASH_SLIDE_TIME, 1.0)
			var a := _ease_slide(_slide_u)
			var b := _ease_slide(u)
			_slide_u = u
			# Re-aimed on what is left: they may have moved.
			var left := minf(gap, _slide_left)
			var fwd := left * (b - a) / maxf(1.0 - a, 0.001)
			_slide_left = maxf(_slide_left - fwd, 0.0)
			_scrape(delta)
			if u >= 1.0:
				# Arrived, on time (its first blow is due now: `_run_move`);
				# the rest of the clip at 1x.
				_dash_phase = 2
				if anim != null:
					anim.speed_scale = 1.0
			return fwd
	return 0.0


## The slide's share done at `u` (0..1 of its time): fast at once, easing off
## into the blow.
static func _ease_slide(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u)


## Sparks off its plating scraping the floor, under its front, while it slides.
func _scrape(delta: float) -> void:
	_scrape_t -= delta
	if _scrape_t > 0.0 or not Graphics.effects:
		return
	_scrape_t = SCRAPE_EVERY
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var ahead := -global_basis.z
	var at := global_position + ahead * 0.7 + Vector3(0.0, 0.06, 0.0)
	# Up and back, the way it came.
	_spark_spray(parent, at, (Vector3.UP * 0.6 - ahead).normalized(), randi_range(3, 6), false)


static func _root_at(table: Array, t: float) -> Vector2:
	var n := table.size()
	if t <= float(table[0][0]):
		return Vector2(table[0][1], table[0][2])
	if t >= float(table[n - 1][0]):
		return Vector2(table[n - 1][1], table[n - 1][2])
	var i := 0
	while i < n - 2 and t >= float(table[i + 1][0]):
		i += 1
	var a: Array = table[i]
	var b: Array = table[i + 1]
	var u := (t - float(a[0])) / (float(b[0]) - float(a[0]))
	return Vector2(lerpf(a[1], b[1], u), lerpf(a[2], b[2], u))


## The hit windows this tick (the move's clock from `prev` to now): every open
## one tests the shield's box against the player -- the dropkick its kick's
## reach -- and lands its blow the first tick it touches; once per window. The
## shield's box is shown while any window is open.
func _tick_windows(prev: float, player: Node3D) -> void:
	var open := false
	for i in _hit_windows.size():
		if _move == Move.NONE:
			break
		var w: Array = _hit_windows[i]
		if _move_t < float(w[0]) or prev > float(w[1]):
			continue
		open = true
		# The jump's point strikes the stone as its window opens, hit or miss.
		if _move == Move.JUMP and prev < float(w[0]):
			_impact_sparks()
		if _landed.has(i):
			continue
		if _touches(player):
			_landed[i] = true
			_land(player)
	_set_hitbox(open and _move != Move.DROPKICK and _move != Move.NONE,
		open and _move == Move.DROPKICK)


## The shield's box and the foot's shown (live) or not; one argument: both.
func _set_hitbox(shield: bool, foot = null) -> void:
	var f: bool = shield if foot == null else foot
	if _hitbox != null and is_instance_valid(_hitbox) and _hitbox.get("live") != shield:
		_hitbox.call("set_live", shield)
	if _foot_box != null and is_instance_valid(_foot_box) and _foot_box.get("live") != f:
		_foot_box.call("set_live", f)


## Does the move under way reach the player now? The shield's box for the swipe,
## the jump and the dash, the left foot's for the dropkick (with a clear line,
## so not through stone; the jump's strike into the floor without).
func _touches(player: Node3D) -> bool:
	var box: Node = _foot_box if _move == Move.DROPKICK else _hitbox
	if box == null or not is_instance_valid(box):
		return false
	if not box.call("overlaps", player):
		return false
	return _move == Move.JUMP or _clear_to(player, 1.0)


## A blow of the move under way has landed: through the guard, and then what it
## does -- the swipe's and the dropkick's throw, the swipe's follow-up jump, a
## blocked blow's shove.
func _land(player: Node3D) -> void:
	var to := player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var away := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	var damage := 0.0
	var throw := 0.0
	match _move:
		Move.SWIPE:
			damage = SWIPE_DAMAGE
			throw = SWIPE_THROW
		Move.JUMP:
			damage = JUMP_DAMAGE
		Move.DROPKICK:
			damage = DROPKICK_DAMAGE
			throw = DROPKICK_THROW
		Move.DASH:
			damage = DASH_DAMAGE
	var outcome := _strike(player, damage, flat)
	if outcome == &"miss" or outcome == &"parried":
		return
	_connected = true
	if outcome == &"hit" and throw > 0.0:
		if player.has_method("knock_down"):
			player.call("knock_down", away, throw)
		if _move == Move.SWIPE:
			_combo_pending = true
	elif outcome == &"blocked" and player.has_method("apply_knockback"):
		player.call("apply_knockback", away * BLOCK_SHOVE)


## Lands a blow through the player's own guard: &"hit", &"blocked", &"parried"
## or &"miss" (it did not get through -- an invulnerable moment, a hiding place).
func _strike(player: Node3D, amount: float, flat: Vector3) -> StringName:
	_guard_seen = -1
	var before = player.get("health")
	var dir := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	player.call("take_damage", amount, dir, self)
	if _guard_seen == 1:
		return &"parried"
	if _guard_seen == 0:
		return &"blocked"
	var after = player.get("health")
	if before != null and after != null and float(after) < float(before):
		return &"hit"
	return &"miss"


func _link_guard(player: Node3D) -> void:
	if player.has_signal("guarded") and not player.is_connected("guarded", _on_player_guarded):
		player.connect("guarded", _on_player_guarded)


func _on_player_guarded(parried: bool, attacker: Node3D) -> void:
	if attacker != self:
		return
	_guard_seen = 1 if parried else 0
	if parried:
		_start_knockdown()


## A player's blow that staggers it (their roll) breaks off whatever it was
## doing.
func _on_staggered() -> void:
	if _move != Move.NONE:
		_end_move()


# --- Parried: thrown on its back ------------------------------------------------------

func _start_knockdown() -> void:
	if _dying or _knock_t >= 0.0:
		return
	_move = Move.NONE
	_target = null
	_combo_pending = false
	_set_hitbox(false)
	_move_vel = Vector3.ZERO
	_knock_t = 0.0
	_stun_until = maxf(_stun_until, _now() + KNOCK_FALL + KNOCK_LIE + KNOCK_RISE + 0.05)
	# The pose it was in, held as it goes over; the limbs flail on the layer.
	if anim != null:
		anim.speed_scale = 0.0
	var player := _resolve_player()
	if _react != null and player != null:
		_react.call("stagger", player.global_position)


func _run_knockdown(delta: float, now: float) -> void:
	_knock_t += delta
	if not is_on_floor():
		velocity += get_gravity() * delta
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	_decay_knockback(delta)
	_thrown_move()
	_advance_anim(delta)
	var pitch := _knock_pitch(_knock_t)
	var b := Basis(Vector3.RIGHT, pitch)
	visual.transform = _visual_rest * Transform3D(b, KNOCK_PIVOT - b * KNOCK_PIVOT)
	if _knock_t >= KNOCK_FALL + KNOCK_LIE + KNOCK_RISE:
		_knock_t = -1.0
		visual.transform = _visual_rest
		# Up -- and straight back at them.
		_swipe_ready = now
		_jump_ready = now
		_dropkick_ready = now
		_dash_ready = now
		_close_ready = now
		_roll_at = now
		alert()
		_play_clip(CLIP_CRAWL, 0.0, BLEND_CRAWL, true)


## How far it is tipped back, `t` seconds after the parry: over and down
## (accelerating), a jolt on landing, still (twitching on the layer), then
## heaved up fast -- forward past upright into its crouch -- and settled.
static func _knock_pitch(t: float) -> float:
	if t < KNOCK_FALL:
		var u := t / KNOCK_FALL
		return KNOCK_PITCH * u * u
	t -= KNOCK_FALL
	if t < 0.18:
		return KNOCK_PITCH - 0.13 * sin(PI * t / 0.18)
	if t < KNOCK_LIE:
		return KNOCK_PITCH
	t -= KNOCK_LIE
	var u := clampf(t / KNOCK_RISE, 0.0, 1.0)
	if u < 0.72:
		var v := u / 0.72
		return lerpf(KNOCK_PITCH, -0.2, 1.0 - pow(1.0 - v, 3.0))
	var w := (u - 0.72) / 0.28
	return lerpf(-0.2, 0.0, w * w * (3.0 - 2.0 * w))


# --- Blows, sparks, death -------------------------------------------------------------

## Where a blow meets its plating, and the radius / height band of it a blade
## reaches.
const HIT_SURFACE := 0.55
const HIT_LOW := 0.6
const HIT_HIGH := 2.0
const HIT_FULL := 20.0


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	var was_dying := _dying
	super(amount, _from_direction)
	if not was_dying and amount > 0.0:
		_hit_sparks()
		var player := _resolve_player()
		if _react != null and player != null and not _dying:
			_react.call("hit", player.global_position, 0.55 + 0.45 * clampf(amount / HIT_FULL, 0.0, 1.0))


func _hit_point() -> Array:
	var base := global_position
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam != null else base + Vector3(0.0, 1.6, 2.0)
	var y := clampf(eye.y - 0.35, base.y + HIT_LOW, base.y + HIT_HIGH)
	var axis := Vector3(base.x, y, base.z)
	var out := Vector3(eye.x - base.x, 0.0, eye.z - base.z)
	out = out.normalized() if out.length_squared() > 0.0001 else -global_basis.z
	return [axis + out * HIT_SURFACE, out]


## The enforcer's spray of hot sparks off struck plating (enforcer.gd).
func _hit_sparks() -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var effects: bool = Graphics.effects
	var hit := _hit_point()
	var at: Vector3 = hit[0]
	var out: Vector3 = hit[1]
	var n := randi_range(ENF.HIT_SPARKS_MIN, ENF.HIT_SPARKS_MAX) if effects \
		else randi_range(ENF.HIT_SPARKS_PLAIN.x, ENF.HIT_SPARKS_PLAIN.y)
	_spark_spray(parent, at, (out + Vector3(0.0, 0.55, 0.0)).normalized(), n, effects)


## The shield's point striking the stone, hit or miss.
func _impact_sparks() -> void:
	var parent := get_parent()
	if parent == null or _tip == null or not is_inside_tree():
		return
	var effects: bool = Graphics.effects
	var at := _tip.global_position
	at.y = maxf(at.y, global_position.y + 0.05)
	_spark_spray(parent, at, Vector3.UP, randi_range(10, 20) if effects else 4, effects)


func _spark_spray(parent: Node, at: Vector3, dir: Vector3, n: int, effects: bool) -> void:
	var p := ENF._spark_burst(n)
	parent.add_child(p)
	p.global_position = at
	p.direction = dir
	p.restart()
	get_tree().create_timer(ENF.HIT_SPARK_LIFE * 1.6 + 0.2).timeout.connect(p.queue_free)
	if effects:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.72, 0.38)
		light.light_energy = 2.4
		light.omni_range = 2.6
		light.shadow_enabled = false
		light.light_specular = 0.4
		parent.add_child(light)
		light.global_position = at + dir * 0.15
		var t := light.create_tween()
		t.tween_property(light, "light_energy", 0.0, 0.14).set_ease(Tween.EASE_IN)
		t.tween_callback(light.queue_free)


## The spark material compiles on first draw: a speck in front of the camera.
func _warm_sparks() -> void:
	if ENF._spark_warmed or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	ENF._spark_warmed = true
	var p := ENF._spark_burst(1)
	p.scale_amount_min = 0.01
	p.scale_amount_max = 0.01
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.0
	p.gravity = Vector3.ZERO
	cam.add_child(p)
	p.position = Vector3(0.0, 0.0, -0.6)
	p.restart()
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func _flinch(_impulse: Vector3, _time: float) -> void:
	pass


## A white flash over the plating, with no squash (the reactions are the
## movement).
func _flash() -> void:
	var flash := ENF._mat(&"flash")
	for mi in _parts:
		mi.material_overlay = flash
	get_tree().create_timer(0.08).timeout.connect(_unflash)


func _unflash() -> void:
	for mi in _parts:
		if is_instance_valid(mi):
			mi.material_overlay = null


## The eyes go out, sparks spill, the rig stops where it is and it keels over
## sideways and lies a moment before it goes.
func _die() -> void:
	_dying = true
	_move = Move.NONE
	_set_hitbox(false)
	died.emit()
	shape.disabled = true
	_grant_drop()
	if anim != null:
		anim.pause()
	visual.transform = _visual_rest
	if Graphics.effects:
		_hit_sparks()
		_impact_sparks()
	if _eye_mat != null:
		create_tween().tween_property(_eye_mat, "albedo_color", Color(0.01, 0.03, 0.02), 0.5)
	if _crystal_mat != null:
		create_tween().tween_property(_crystal_mat, "emission_energy_multiplier", 0.0, 0.7)
	if _glow != null:
		create_tween().tween_property(_glow, "light_energy", 0.0, 0.6)
	var fall := create_tween().set_parallel(true)
	fall.tween_property(visual, "position:y", visual.position.y - 0.4, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(visual, "rotation:z", 1.35, 0.7).set_delay(0.15) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var gone := create_tween()
	gone.tween_interval(3.0)
	gone.tween_property(self, "scale", Vector3(1.0, 0.01, 1.0), 0.4).set_ease(Tween.EASE_IN)
	gone.tween_callback(queue_free)


## The player is on the other side of the sewer roof from it. Sewer dwellers
## neither see nor chase anyone above ground; one placed above ground (the
## sandbox's test plane, sandbox_world.gd) hunts there as it would below.
func _other_level(player: Node3D) -> bool:
	return (player.global_position.y > SPLIT_Y) != (global_position.y > SPLIT_Y)
