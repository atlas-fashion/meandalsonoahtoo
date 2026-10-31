extends "res://scripts/prosthetic.gd"

## The Proel swordsman (notes 135, 136, 139; "the sword skeleton" until then, and its
## files, its hand `&"blade"` and the saves still say so): the user's rusty metal golem,
## very tall and gaunt, riveted plate over bone, the right forearm ending in a long
## blade. The numbers are the sword hand's (prosthetic.gd, enemy.gd); this file changes
## what it looks like doing them, and how it goes about killing the player.
##
## models/sword_skeleton.glb carries every clip, baked by
## tools/anim_sword_skeleton.py, and plays them all at 1x on their own clocks:
##
##   idle, idle_fight, walk, run, turn_l, turn_r   chosen each tick (`_update_locomotion`)
##   turn_gl, turn_gr, relax                       turning on guard; out of the guard
##   pivot_l/r, gpivot_l/r, and each again with b  a real turn: 90 degrees, or 180 (`b`)
##   slash_1/2/3, heavy, and each again with _s    one clip is the whole blow
##   link_1_2, 2_1, 2_3, 2_h, 3_2                  one blow's recovery into the next
##   out_1/2/3/h[s]_walk/run, out_g_walk/run       off out of a blow, or the guard
##   haul, idle_haul                               the blade dragged behind
##   stagger_b/f/l/r                               thrown by a blow (`_flinch`)
##   death_b/f/s                                   by where the last blow came from
##
## Every change of clip is inertialized (enforcer_react.gd `crossfade`, under
## sword_skeleton_react.gd), and walk and run share a phase, so one takes over
## from the other mid-stride. A blow is one clip, so nothing blends inside it, and
## it ends on the first frame of idle_fight.
##
## Chains (note 138): now and then a light blow goes on into a second, and that into
## a third. A blow runs as usual until CHAIN_OUT in its recovery; there the clip is
## swapped for a link, which runs to CHAIN_IN in the next blow's wind-up, and there
## for that blow. Those are the same pose at the same speed, so nothing has to blend.
##
## Out (note 139): once a blow's carry is spent, if the player has gone, an `out` clip
## takes over from it and runs into the first frame of the walk or the run. Those are
## swaps too: the clip starts as the blow stands and ends in stride.
##
## Root motion: each clip's `root` track is lifted out once and kept as a curve
## (`_roots`). During a blow the body moves by that curve, scaled to reach the
## player (`_slide`), so a planted foot stays planted through the step. `_s` is the
## same blow with a shuffle for a step, for when it is already close.
##
## The body's heading snaps (enemy.gd `_face`); the model follows it on a
## critically damped spring (`_turn_model`), and stood still that turning is what
## plays turn_l and turn_r. A turn too big for that is a pivot: the body waits and the
## clip's own turn, the `root` track's x, brings the model round on planted feet.

const MODEL := preload("res://models/sword_skeleton.glb")
const REACT := preload("res://scripts/sword_skeleton_react.gd")
const BLADE := preload("res://scripts/sword_skeleton_blade.gd")
const EYES := preload("res://scripts/skeleton_eyes.gd")

## What the clips are authored for (tools/anim_sword_skeleton.py).
const WALK_SPEED := 1.55
const RUN_SPEED := 4.6
const TURN_RATE := 1.745
const LIGHTS: Array[StringName] = [&"slash_1", &"slash_2", &"slash_3"]
const CYCLES: Array[StringName] = [&"walk", &"run"]
const STILL: Array[StringName] = [&"idle", &"idle_fight"]
const TURNS: Array[StringName] = [&"turn_l", &"turn_r", &"turn_gl", &"turn_gr"]
## Into a turn on guard here, with both feet nearest where the stance has them.
const TURN_FROM_GUARD := 0.26
## A chain. tools/anim_sword_skeleton.py `LINK`, `LINK_OUT` and `LINK_IN` are these
## same times, baked into the clips: change both. What can follow what is by where
## the blade ends up: slash_1 ends low on its left, where the backhand starts; the
## backhand ends high on its right, where the others start. The heavy only ever ends one.
const LINK_TIME := 0.75
const CHAIN_OUT := BLADE_WINDUP + BLADE_SWING + 0.62
const CHAIN_IN := {&"slash_1": 0.68, &"slash_2": 0.68, &"slash_3": 0.68, &"heavy": 0.97}
const CHAIN_NEXT := {&"slash_1": [&"slash_2"], &"slash_2": [&"slash_1", &"slash_3", &"heavy"], &"slash_3": [&"slash_2"]}
const LINK_TAG := {&"slash_1": "1", &"slash_2": "2", &"slash_3": "3", &"heavy": "h"}
## How often a light blow goes on to a second with nothing to go on, when the last one
## landed or was blocked, and how much less likely each blow added makes the next.
const CHAIN_SHARE := 0.4
const CHAIN_ON_HIT := 0.75
const CHAIN_ON_GUARD := 0.5
const CHAIN_TIRED := 0.7
## At most this many blows added to the first.
const CHAIN_MOST := 2
## Further off than this, centre to centre, it does not go on: it goes after them.
const CHAIN_REACH := 2.6
## Blown after a chain: this much longer until the next blow, for each one it added.
const CHAIN_REST := 0.7
## Under this share of their health it has them, and presses: more blows, less rest.
const LOW_HEALTH := 0.35
## How long after their swing ends they are open to a blow.
const SWING_OPEN := 0.45
## Sidestepping, m/s across the line between them: the overhead cannot catch that.
const SIDESTEP := 1.5
## When a blow's clock can break off into an `out` clip: past the carry, the right foot
## down. tools/anim_sword_skeleton.py `OUT_AT`: change both.
const OUT_AT := {&"slash_1": 1.46, &"slash_2": 1.52, &"slash_3": 1.46, &"heavy": 2.07}
## With the model turned further from them than this it pivots first.
const OUT_TURN := 1.2
## How much of a late start the crossfade takes up.
const BLEND_OUT := 0.22
## How near an `out` may take it before it stops: back in reach.
const OUT_STOP := 1.7
## Standing, or nearly: a turn bigger than this is a pivot, and bigger than the second
## the long one. The clips turn 90 and 180 degrees, scaled to fit by at most this.
const PIVOT_FROM := 0.95
const PIVOT_LONG := 2.3
const PIVOT_SPEED := 1.4
const PIVOT_SCALE_MIN := 0.7
const PIVOT_SCALE_MAX := 1.15
const BLEND_PIVOT := 0.2
const BLEND_PIVOT_BLOW := 0.45
## Stood still, the model turns no faster than turn_l's feet can go at their best.
const TURN_MOST := 2.6
## How far it leans into a turn on the move, per m/s/s of the turn, at most, and how
## quick that is.
const LEAN := 0.022
const LEAN_MOST := 0.16
const LEAN_EASE := 9.0
## A taller capsule than enemy.tscn's: the head is up there to be hit.
const HEIGHT := 2.1
## How near it walks up to someone: its whole arm is the weapon.
const STOP_AT := 1.0
## The red eyes, in the skeleton's own space (+Y up, +Z its front), and the soft halo on
## them: faint and small, the eyes' own material carrying the colour, so they do not bloom.
const EYE_POINTS: Array[Vector3] = [Vector3(-0.037, 2.035, 0.305), Vector3(0.031, 2.047, 0.277)]
const EYE_COLOUR := Color(1.0, 0.07, 0.04)
const EYE_HALO := 0.2
const EYE_HALO_SIZE := 0.04
## Through a blow they brighten by this, as a telegraph.
const EYE_HOT := 1.5
## Where a blow's step should leave it from the player, centre to centre.
const STANDOFF := 1.3
## The longest share of a clip's own step it will stretch or shrink to.
const STEP_MIN := 0.6
const STEP_MAX := 1.25
## A step this long needs the full stride.
const LONG_STEP := 0.32
## The body's speed going into a blow is shed at this, m/s/s.
const CARRY_DECEL := 15.0
## How stiff the model's heading spring is, walking about, in the swing, and with the
## weight of the blade up or still out at the end of its arm, when it comes round slowly.
const TURN_SPRING := 11.0
const TURN_SPRING_BLOW := 20.0
const TURN_SPRING_LOADED := 6.0
## Under this it stands; over it, the turning shows in the feet.
const TURN_SHOWS := 0.75
## How long a clip may take to settle in. A change of pace is slow; a blow, a
## telegraph the player reads, is quick.
const BLEND_MOVE := 0.34
const BLEND_BLOW := 0.3
const BLEND_HIT := 0.24
const BLEND_DEATH := 0.28
## Lying dead this long, then it goes.
const LIE_DEAD := 6.0

## Clip name -> forward distance by 1/60 s: the root tracks, lifted out once.
static var _roots := {}
## The pivots': radians turned to its left by 1/60 s.
static var _yaws := {}
static var _glow_hot: StandardMaterial3D
static var _glow_out: StandardMaterial3D

var _model: Node3D = null
var _sk: Skeleton3D = null
var _react: SkeletonModifier3D = null
var _glow_surface := -1
var _shown_yaw := 0.0
var _yaw_v := 0.0
var _blow := &""
var _blow_t := 0.0
var _blow_scale := 1.0
var _carry := Vector3.ZERO
var _last_light := &""
var _last_blow := Vector3.ZERO
var _last_amount := 0.0
var _rate := 1.0
var _turn_k := TURN_SPRING
var _lean := 0.0
## The chain: blows it has added, the one it is going to, and whether this blow has
## been weighed yet.
var _chained := 0
var _next := &""
var _chain_asked := false
## What came of the last blow: &"hit", &"blocked" or &"missed".
var _result := &"missed"
## An `out` clip is playing, in `_blow`.
var _out := false
## The pivot playing, where the model's heading was as it started, and how much of the
## clip's turn it wants.
var _pivot := &""
var _pivot_from := 0.0
var _pivot_scale := 1.0
## Their swing: going now, and when it last ended.
var _their_swing := false
var _swing_ended_at := -INF


func _init() -> void:
	super()
	hand = &"blade"
	walk_anim_speed = WALK_SPEED
	run_anim_speed = RUN_SPEED
	stop_distance = STOP_AT


## The model goes in before the @onready lookups run.
func _enter_tree() -> void:
	if _model != null:
		return
	var pivot := get_node("Visual") as Node3D
	var old := pivot.get_node_or_null("Model")
	if old != null:
		pivot.remove_child(old)
		old.free()
	_model = MODEL.instantiate() as Node3D
	_model.name = "Model"
	# The rig's front is +Z, the body's -Z.
	_model.rotation.y = PI
	pivot.add_child(_model)
	var hull := get_node("CollisionShape3D") as CollisionShape3D
	var capsule := (hull.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.height = HEIGHT
	hull.shape = capsule
	hull.position.y = HEIGHT * 0.5


func _ready() -> void:
	super()
	_shown_yaw = rotation.y
	# Whoever placed it may turn it after it enters the tree.
	_settle_yaw.call_deferred()


func _settle_yaw() -> void:
	_shown_yaw = rotation.y


# --- What enemy.gd asks for -----------------------------------------------------------

func _own_material() -> bool:
	return false


func _hang_eyes() -> Node3D:
	return EYES.attach_at(self, EYE_POINTS, EYE_COLOUR, EYE_HALO, EYE_HALO_SIZE)


func _arm() -> Node3D:
	return BLADE.grip(self)


func _setup_animations() -> void:
	if anim == null:
		return
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for looping: StringName in [&"idle", &"idle_fight", &"walk", &"run", &"turn_l", &"turn_r", &"turn_gl", &"turn_gr", &"haul", &"idle_haul"]:
		anim.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
	_lift_roots()
	var found := find_children("*", "Skeleton3D", true, false)
	_sk = found[0] as Skeleton3D
	_react = REACT.new()
	_react.name = "HitReact"
	_react.set("player", anim)
	_sk.add_child(_react)
	for node in _sk.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m != null and m.resource_name == "SkelGlow":
				_glow_surface = i
				mesh = mi
				_make_glows(m as StandardMaterial3D)
	# No two standing in step.
	anim.play(&"idle", 0.0, 1.0)
	anim.seek(randf() * anim.get_animation(&"idle").length, true)


## Every clip's root track becomes a curve of forward distance, once, and a pivot's its
## turn. The clips are shared by every skeleton, so this happens to them all at once.
func _lift_roots() -> void:
	if not _roots.is_empty():
		return
	for clip_name in anim.get_animation_list():
		var a := anim.get_animation(clip_name)
		var curve := PackedFloat32Array()
		var yaw := PackedFloat32Array()
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D and String(a.track_get_path(i)).ends_with(":root"):
				var n := int(round(a.length * 60.0)) + 1
				curve.resize(n)
				yaw.resize(n)
				for k in n:
					var at := a.position_track_interpolate(i, float(k) / 60.0)
					curve[k] = at.z
					yaw[k] = at.x
				a.remove_track(i)
				break
		_roots[StringName(clip_name)] = curve
		if clip_name.contains("pivot_"):
			_yaws[StringName(clip_name)] = yaw


static func _make_glows(base: StandardMaterial3D) -> void:
	if _glow_hot != null:
		return
	_glow_hot = base.duplicate() as StandardMaterial3D
	_glow_hot.emission_energy_multiplier = base.emission_energy_multiplier * EYE_HOT
	_glow_out = base.duplicate() as StandardMaterial3D
	_glow_out.emission_energy_multiplier = 0.0
	_glow_out.albedo_color = Color(0.03, 0.02, 0.015)


## The state's glow is the eyes: hotter through a blow.
func _apply_state_color(colour: Color, glow: float) -> void:
	_state_color = colour
	if _glow_surface >= 0 and mesh != null:
		mesh.set_surface_override_material(_glow_surface, _glow_hot if glow > 0.5 else null)


## Struck: the reaction rides over whatever clip is playing, no squash.
func _flash() -> void:
	if _react == null:
		return
	var from := global_position + global_basis.z * -1.0
	if _last_blow.length_squared() > 0.01:
		from = global_position - Vector3(_last_blow.x, 0.0, _last_blow.z).normalized() * 2.0
	_react.call("hit", from, 0.5 + 0.5 * clampf(_last_amount / 20.0, 0.0, 1.0))


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	_last_blow = _from_direction
	_last_amount = amount
	super(amount, _from_direction)


## Thrown by a blow: a stumble the way it was thrown.
func _flinch(impulse: Vector3, _time: float) -> void:
	if _dying or anim == null:
		return
	_blow = &""
	_next = &""
	var away := Vector3(impulse.x, 0.0, impulse.z)
	if away.length_squared() < 1e-4:
		away = global_basis.z
	var ahead := away.dot(-global_basis.z)
	var side := away.dot(-global_basis.x)
	var clip := &"stagger_b"
	if absf(side) > absf(ahead):
		clip = &"stagger_l" if side > 0.0 else &"stagger_r"
	elif ahead > 0.0:
		clip = &"stagger_f"
	_switch(clip, 1.0, BLEND_HIT)


func _play_state_anim(which: StringName, _duration: float) -> void:
	if anim == null:
		return
	match which:
		ANIM_WINDUP:
			_start_blow()
		ANIM_IDLE:
			_blow = &""
			_next = &""
			_out = false
			_rest()
		# The blow's clip carries on through its swing and its recovery.
		_:
			if state == State.ATTACK:
				_result = &"missed"
				_measure_step()


func _update_locomotion() -> void:
	if anim == null or state != State.CHASE or _dying or is_stunned():
		return
	if _out:
		_tend_out()
		return
	if _pivot != &"":
		if anim.is_playing() and StringName(anim.assigned_animation) == _pivot:
			# Most of the way round before it swings; until then it is turning.
			if anim.current_animation_position < anim.current_animation_length * 0.7:
				_next_attack_allowed = maxf(_next_attack_allowed, _now() + 0.05)
			return
		_pivot = &""
	var moving := get_real_velocity()
	var speed := Vector2(moving.x, moving.z).length()
	var now := anim.current_animation
	var want := &"idle_fight" if engaged else &"idle"
	var rate := 1.0
	# A little either way of each threshold, so it does not chatter.
	var to_run := run_anim_threshold * (0.85 if now == &"run" else 1.0)
	# Going for someone, it does not bother to walk first.
	if engaged:
		to_run = minf(to_run, 1.4)
	var to_walk := 0.15 if now == &"walk" else 0.3
	var off := wrapf(rotation.y - _shown_yaw, -PI, PI)
	if speed < PIVOT_SPEED and absf(off) > PIVOT_FROM and not caged and _shown_close():
		_start_pivot(off)
		return
	if speed >= to_run:
		want = &"run"
		rate = clampf(speed / RUN_SPEED, 0.6, 1.5)
	elif speed > to_walk:
		want = &"walk"
		rate = clampf(speed / WALK_SPEED, 0.55, 1.65)
	elif absf(_yaw_v) > TURN_SHOWS * (0.7 if now in TURNS else 1.0):
		var left := _yaw_v > 0.0
		if engaged:
			want = &"turn_gl" if left else &"turn_gr"
		else:
			want = &"turn_l" if left else &"turn_r"
		rate = clampf(absf(_yaw_v) / TURN_RATE, 0.6, 1.6)
	# Nobody left to fight: the two stances are a stride apart, so it steps out of
	# the guard rather than skating.
	if want == &"idle":
		if now == &"relax":
			return
		if now != &"idle" and _on_guard(anim.assigned_animation):
			want = &"relax"
	# Off from the guard, in stride, the way it goes off from a blow.
	if want in CYCLES and now not in CYCLES and _on_guard(anim.assigned_animation) and _shown_close():
		if _react != null:
			_react.call("crossfade", BLEND_OUT)
		_put_on(StringName("out_g_run" if engaged else "out_g_walk"), 0.0)
		_blow_scale = 1.0
		_carry = Vector3.ZERO
		_out = true
		return
	if now != want:
		_switch(want, rate, BLEND_MOVE)
		return
	# Eased, never jumped: the feet would skip.
	_rate = move_toward(_rate, rate, get_physics_process_delta_time() * 6.0)
	anim.speed_scale = _rate


## Is the rig in the fighting stance at the end of this clip? Every blow ends there.
static func _on_guard(clip: StringName) -> bool:
	var name_ := String(clip)
	return clip == &"idle_fight" or clip == &"turn_gl" or clip == &"turn_gr" or name_.begins_with("gpivot") \
		or name_.begins_with("slash") or name_.begins_with("heavy") or name_.begins_with("link")


## Puts `clip` on the rig, the old pose decaying into it. Walk and run take over
## at the same point of the stride; out of a stand or a blow, on the right foot,
## which is the one ahead. `assigned_animation`, not `current_animation`: a blow's
## clip may have run out the tick before.
func _switch(clip: StringName, rate: float, blend: float) -> void:
	_pivot = &""
	if _out:
		_out = false
		_blow = &""
	var now := StringName(anim.assigned_animation)
	var at := -1.0
	if clip in CYCLES:
		if now in CYCLES:
			at = anim.current_animation_position / anim.get_animation(now).length
		elif now in STILL or _on_guard(now):
			at = 0.52
	elif clip == &"turn_gl" or clip == &"turn_gr":
		at = TURN_FROM_GUARD
	if _react != null:
		_react.call("crossfade", blend)
	_rate = rate
	anim.speed_scale = rate
	anim.play(clip, 0.0, 1.0)
	if at >= 0.0:
		anim.seek(at * anim.get_animation(clip).length, true)
	elif clip not in STILL:
		anim.seek(0.0, true)


# --- Turning ---------------------------------------------------------------------------

## Near enough that its clips are running every frame or so: a far rig's may not run at
## all (`_advance_anim`), and a body waiting on one would wait for ever.
func _shown_close() -> bool:
	var player := _resolve_player()
	if player == null:
		return false
	var near := minf(18.0, Graphics.anim_half_distance)
	return global_position.distance_squared_to(player.global_position) < near * near


func _start_pivot(off: float) -> void:
	var long := absf(off) > PIVOT_LONG
	var clip := "%s%s%s" % ["gpivot_" if engaged else "pivot_", "l" if off > 0.0 else "r", "b" if long else ""]
	# Out of a blow the blade is a long way from the stance.
	var blown := String(anim.assigned_animation).begins_with("slash") or String(anim.assigned_animation).begins_with("heavy")
	_switch(StringName(clip), 1.0, BLEND_PIVOT_BLOW if blown else BLEND_PIVOT)
	_pivot = StringName(clip)
	_pivot_from = _shown_yaw
	_pivot_scale = clampf(absf(off) / (PI if long else PI * 0.5), PIVOT_SCALE_MIN, PIVOT_SCALE_MAX)


# --- Off after them --------------------------------------------------------------------

## Past the carry, is there anything to stay for? Gone out of reach, it goes after them;
## nobody to fight, it walks off.
func _should_leave() -> bool:
	if caged or is_stunned() or not _shown_close():
		return false
	var player := _resolve_player()
	return not engaged or _flat_to(player) > CHAIN_REACH


## Takes the blow off into an `out` clip, late if the player only just went. Turned too
## far from them to run at them, the state is over and `_update_locomotion` pivots.
func _leave(t: float) -> void:
	var base := _base_blow()
	var name_ := String(_blow)
	var off := wrapf(rotation.y - _shown_yaw, -PI, PI)
	var late := t - float(OUT_AT[base])
	_enter_chase()
	if absf(off) > OUT_TURN:
		return
	var clip := "out_%s%s_%s" % [LINK_TAG[base], "s" if name_.ends_with("_s") else "", "run" if engaged else "walk"]
	if late > 0.04 and _react != null:
		_react.call("crossfade", BLEND_OUT)
		late = 0.0
	_put_on(StringName(clip), late)
	_blow_scale = 1.0
	_carry = Vector3.ZERO
	_out = true


## Each tick of an `out` clip. Its end is the first frame of the gait, at the gait's speed.
func _tend_out() -> void:
	var player := _resolve_player()
	if engaged and player != null and _flat_to(player) < OUT_STOP:
		_out = false
		_blow = &""
		return
	# A tick short of it: `_slide` reads the clip, and a clip that has stopped has no speed.
	if anim.is_playing() and anim.current_animation_position + get_physics_process_delta_time() * 1.5 < anim.current_animation_length:
		return
	var gait := &"run" if String(_blow).ends_with("run") else &"walk"
	_out = false
	_blow = &""
	_rate = 1.0
	anim.speed_scale = 1.0
	anim.play(gait, 0.0, 1.0)
	anim.seek(0.0, true)


func _flat_to(node: Node3D) -> float:
	return Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z).length()


# --- Going for the kill ----------------------------------------------------------------
#
# What it reads off the player. It weighs a blow by whether it can finish them, whether
# they have left themselves open, and whether the blow can catch where they are going.
# There is always a little chance in it, so a chain cannot be learned by heart.

func _base_blow() -> StringName:
	return StringName(String(_blow).trim_suffix("_s"))


## Knocked down, drinking, or their swing just spent.
func _open(player: Node3D) -> bool:
	if player.has_method("is_knocked_down") and player.call("is_knocked_down"):
		return true
	if player.has_method("is_drinking") and player.call("is_drinking"):
		return true
	return _now() - _swing_ended_at < SWING_OPEN


## Their guard is up and turned on it. A guard covers only the front (player.gd `_guard`).
func _guarded(player: Node3D) -> bool:
	if not (player.has_method("is_blocking") and player.call("is_blocking")):
		return false
	var facing := -player.global_basis.z
	var to_it := global_position - player.global_position
	facing.y = 0.0
	to_it.y = 0.0
	if facing.length_squared() < 1e-4 or to_it.length_squared() < 1e-4:
		return false
	var arc = player.get("block_arc")
	return rad_to_deg(facing.angle_to(to_it)) <= (float(arc) if arc != null else 60.0)


## How fast they are going across the line between them, either way.
func _sidestep_speed(player: Node3D) -> float:
	var pv = player.get("velocity")
	var line := player.global_position - global_position
	line.y = 0.0
	if not (pv is Vector3) or line.length_squared() < 1e-4:
		return 0.0
	var across := Vector3(-line.z, 0.0, line.x).normalized()
	return absf((pv as Vector3).dot(across))


## Would this much, through whatever they have on and whatever they have up, end them?
func _finishes(player: Node3D, damage: float, guarded: bool) -> bool:
	var health = player.get("health")
	if health == null:
		return false
	var taken := damage
	if guarded:
		var share = player.get("block_damage_taken")
		taken *= float(share) if share != null else 0.1
	if player.has_method("damage_negation"):
		taken *= 1.0 - float(player.call("damage_negation"))
	return taken >= float(health)


func _nearly_dead(player: Node3D) -> bool:
	var health = player.get("health")
	var most = player.get("max_health")
	return health != null and most != null and float(health) <= float(most) * LOW_HEALTH


## How much it wants to throw `clip` at them now.
func _worth(clip: StringName, player: Node3D, guarded: bool) -> float:
	var heavy := clip == &"heavy"
	var damage := HEAVY_DAMAGE if heavy else attack_damage
	var score := randf() * 0.4
	if _finishes(player, damage, guarded):
		score += 3.0
	if _open(player):
		score += damage / HEAVY_DAMAGE
	# The most that gets through a guard.
	if guarded and heavy:
		score += 1.0
	# The flat cuts catch someone going sideways. The overhead comes down where they were.
	if _sidestep_speed(player) > SIDESTEP:
		score += -0.8 if clip == &"slash_3" else 0.8
	# The longer step for someone further off.
	if _flat_to(player) > STANDOFF + 0.4:
		score += _root_at(clip, 99.0)
	# The backhand is the blow the heavy follows: the way in, when the heavy is wanted.
	if clip == &"slash_2" and _now() >= _ready_at(Attack.SLAM) and (guarded or _nearly_dead(player)):
		score += 0.6
	return score


func _best_of(from: Array, player: Node3D) -> StringName:
	var guarded := _guarded(player)
	var best: StringName = from[0]
	var top := -INF
	for clip: StringName in from:
		var score := _worth(clip, player, guarded)
		if score > top:
			top = score
			best = clip
	return best


## How likely it is to go on from this blow, with the result in front of it.
func _press_on(player: Node3D) -> float:
	var guarded := _guarded(player)
	if _open(player) or _finishes(player, HEAVY_DAMAGE, guarded):
		return 1.0
	var chance := CHAIN_SHARE
	if _result == &"hit":
		chance = CHAIN_ON_HIT
	elif _result == &"blocked":
		chance = CHAIN_ON_GUARD
	if _nearly_dead(player):
		chance += 0.25
	return chance * pow(CHAIN_TIRED, float(_chained))


## The light or the heavy, when both are ready: whichever ends it, or gets through a guard.
func _pick_attack(gap: float, now: float) -> int:
	var kind := super(gap, now)
	var player := _resolve_player()
	if kind < 0 or player == null or now < _ready_at(Attack.SLAM) or now < _ready_at(Attack.NORMAL):
		return kind
	var guarded := _guarded(player)
	if _finishes(player, attack_damage, guarded):
		return Attack.NORMAL
	if guarded or _finishes(player, HEAVY_DAMAGE, guarded):
		return Attack.SLAM
	return kind


## Each tick: what they are doing, and an opening does not wait for the cooldown.
func _watch_player() -> void:
	var player := _resolve_player()
	if player == null:
		return
	var swinging: bool = player.get("_attacking") == true
	if _their_swing and not swinging:
		_swing_ended_at = _now()
	_their_swing = swinging
	if state == State.CHASE and engaged and _flat_to(player) <= CHAIN_REACH and _open(player):
		_cooldowns[Attack.NORMAL] = minf(_ready_at(Attack.NORMAL), _now())


func _on_blow_landed(player: Node3D, kind: int) -> void:
	super(player, kind)
	_result = &"blocked" if _guarded(player) else &"hit"


# --- Blows ----------------------------------------------------------------------------

func _start_blow() -> void:
	if _next != &"":
		_start_link()
		return
	var clip := &"heavy"
	_chained = 0
	var player := _resolve_player()
	if attack_kind != Attack.SLAM:
		var from := LIGHTS.duplicate()
		from.erase(_last_light)
		clip = _best_of(from, player) if player != null else from[randi() % from.size()]
		_last_light = clip
	var need := 0.3
	if player != null:
		need = Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() - STANDOFF
		# What the speed it comes in at will carry it anyway.
		var coming := Vector2(velocity.x, velocity.z).length()
		need -= coming * coming * 0.5 / CARRY_DECEL
	if need < LONG_STEP:
		clip = StringName(String(clip) + "_s")
	var whole := _root_at(clip, 99.0)
	_blow_scale = clampf(need / maxf(whole, 0.01), STEP_MIN, STEP_MAX)
	_carry = Vector3(velocity.x, 0.0, velocity.z)
	_switch(clip, 1.0, BLEND_BLOW)
	_blow = clip
	_blow_t = 0.0


## The wind-up is long enough for them to have moved. The step is all still to come
## when the swing starts, so it is measured again from where they are now.
func _measure_step() -> void:
	var player := _resolve_player()
	if player == null or _blow == &"":
		return
	var need := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() - STANDOFF
	var left := _root_at(_blow, 99.0) - _root_at(_blow, _blow_t)
	_blow_scale = clampf(need / maxf(left, 0.01), STEP_MIN, STEP_MAX)


## The wind-up of a blow in a chain is what is left of the link and of its own.
func _windup_for(kind: int) -> float:
	if _next == &"":
		return super(kind)
	var swing_at: float = HEAVY_WINDUP if _next == &"heavy" else BLADE_WINDUP
	return LINK_TIME + swing_at - float(CHAIN_IN[_next]) - (anim.current_animation_position - CHAIN_OUT)


func _enter_recover() -> void:
	super()
	_chain_asked = false
	if not _may_go_on():
		_rest()


## A light blow, with a blow still left in the chain.
func _may_go_on() -> bool:
	return CHAIN_NEXT.has(_base_blow()) and _chained < CHAIN_MOST


## A chain cost it: both blows wait longer than they would after one. With the player
## nearly dead it gets its wind back sooner.
func _rest() -> void:
	if _chained <= 0:
		return
	var player := _resolve_player()
	var rest := CHAIN_REST * float(_chained)
	if player != null and _nearly_dead(player):
		rest *= 0.4
	var until := _now() + _cooldown_of(Attack.NORMAL) + rest
	_cooldowns[Attack.NORMAL] = maxf(_ready_at(Attack.NORMAL), until)
	_cooldowns[Attack.SLAM] = maxf(_ready_at(Attack.SLAM), until)
	_chained = 0


## Each tick: from OUT_AT it goes after them if they have gone; at CHAIN_OUT the blow goes
## on, if it is going to; at the end of a link the next blow takes over. Just before the
## link's end, which its clip stops at.
func _tend_chain(delta: float) -> void:
	if anim == null or _blow == &"":
		return
	if _next != &"" and state == State.WINDUP:
		if not anim.is_playing():
			_join(LINK_TIME)
		elif anim.current_animation_position >= LINK_TIME - delta * 1.5:
			_join(anim.current_animation_position)
	elif state == State.RECOVER and anim.is_playing():
		var t := anim.current_animation_position
		if t >= float(OUT_AT.get(_base_blow(), INF)) and _should_leave():
			_leave(t)
		elif t >= CHAIN_OUT and not _chain_asked and _may_go_on():
			_go_on()


func _go_on() -> void:
	_chain_asked = true
	var from: Array = CHAIN_NEXT.get(_base_blow(), []).duplicate()
	var player := _resolve_player()
	var near := player != null and engaged and not is_stunned() and _flat_to(player) <= CHAIN_REACH
	# It will take the heavy off its cooldown only to finish them.
	if near and _now() < _ready_at(Attack.SLAM) and not _finishes(player, HEAVY_DAMAGE, _guarded(player)):
		from.erase(&"heavy")
	if not near or from.is_empty() or randf() >= _press_on(player):
		_rest()
		return
	_next = _best_of(from, player)
	_chained += 1
	if _next != &"heavy":
		_last_light = _next
	# The state's own wind-up, telegraph and all. `_start_blow` sees `_next`.
	_enter_windup(Attack.SLAM if _next == &"heavy" else Attack.NORMAL)


func _start_link() -> void:
	var clip := StringName("link_%s_%s" % [LINK_TAG[_base_blow()], LINK_TAG[_next]])
	var over := anim.current_animation_position - CHAIN_OUT
	_put_on(clip, over)
	_blow_scale = 1.0


## The link is over: the next blow, from where the link leaves it, on the step that
## suits where they are now.
func _join(t: float) -> void:
	var clip := _next
	var player := _resolve_player()
	if player != null:
		var need := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() - STANDOFF
		if need < LONG_STEP:
			clip = StringName(String(clip) + "_s")
	else:
		clip = StringName(String(clip) + "_s")
	_put_on(clip, float(CHAIN_IN[_next]) + t - LINK_TIME)
	_next = &""


## The swap itself. No crossfade: the two clips are the same pose at the same speed
## here, and `crossfade` would take a frame's movement for an offset and hold it.
func _put_on(clip: StringName, t: float) -> void:
	_rate = 1.0
	anim.speed_scale = 1.0
	anim.play(clip, 0.0, 1.0)
	anim.seek(t, true)
	_blow = clip
	_blow_t = t


## How far forward the clip's root has come at `t`.
static func _root_at(clip: StringName, t: float) -> float:
	return _on_curve(_roots.get(clip, PackedFloat32Array()), t)


static func _on_curve(curve: PackedFloat32Array, t: float) -> float:
	if curve.is_empty():
		return 0.0
	var f := clampf(t * 60.0, 0.0, float(curve.size() - 1))
	var i := int(f)
	var j := mini(i + 1, curve.size() - 1)
	return lerpf(curve[i], curve[j], f - float(i))


## Every move goes through here. In a blow the body goes where the clip's step
## takes it; the dead do not move, whatever gravity says (the capsule is off).
func _slide() -> void:
	if _dying:
		return
	# A pivot is the feet's turn: the body waits for it.
	if _pivot != &"":
		velocity.x = 0.0
		velocity.z = 0.0
	if _blow != &"" and anim != null:
		var dt := get_physics_process_delta_time()
		# The clip may have run out a tick before the recovery does.
		var t := anim.current_animation_position if anim.is_playing() else _blow_t
		var step := (_root_at(_blow, t) - _root_at(_blow, _blow_t)) * _blow_scale
		_blow_t = t
		_carry = _carry.move_toward(Vector3.ZERO, CARRY_DECEL * dt)
		var fwd := -global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		velocity.x = fwd.x * step / dt + _carry.x
		velocity.z = fwd.z * step / dt + _carry.z
	super()


# --- Each tick ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if _dying:
		_advance_anim(delta)
		return
	if _dormant or _model == null:
		return
	_turn_model(delta)
	_tend_chain(delta)
	_watch_player()
	_tend_react()


## The model's heading chases the body's on a spring, so a snapped `_face` reads
## as a turn. `_yaw_v`, its speed, is what the turning clips are played by. The swing
## takes hold at once; anything else eases in, or the end of a blow shows as a lurch.
## In a pivot the clip's own turn has the heading, and the spring takes back over from it.
func _turn_model(delta: float) -> void:
	var want := TURN_SPRING
	if _blow != &"" and not _out:
		want = TURN_SPRING_BLOW if state == State.ATTACK else TURN_SPRING_LOADED
	_turn_k = want if want == TURN_SPRING_BLOW else move_toward(_turn_k, want, delta * 20.0)
	var speed := Vector2(velocity.x, velocity.z).length()
	if _pivot != &"" and anim.is_playing():
		var was := _shown_yaw
		var yaw: float = _on_curve(_yaws.get(_pivot, PackedFloat32Array()), anim.current_animation_position)
		_shown_yaw = wrapf(_pivot_from + yaw * _pivot_scale, -PI, PI)
		_yaw_v = wrapf(_shown_yaw - was, -PI, PI) / delta
	else:
		var k := _turn_k
		var off := wrapf(rotation.y - _shown_yaw, -PI, PI)
		_yaw_v += (k * k * off - 2.0 * k * _yaw_v) * delta
		if _blow == &"" and speed < 0.3:
			_yaw_v = clampf(_yaw_v, -TURN_MOST, TURN_MOST)
		_shown_yaw = wrapf(_shown_yaw + _yaw_v * delta, -PI, PI)
	_model.rotation.y = PI + wrapf(_shown_yaw - rotation.y, -PI, PI)
	# Into the turn, as anything with weight on the move does.
	var lean := clampf(-_yaw_v * speed * LEAN, -LEAN_MOST, LEAN_MOST) if _pivot == &"" else 0.0
	_lean = lerpf(_lean, lean, 1.0 - exp(-LEAN_EASE * delta))
	_model.rotation.z = _lean


## Near the player the layer stays on, so every switch knows how the rig was
## moving, and the head follows them. Far off it sleeps.
func _tend_react() -> void:
	if _react == null:
		return
	var player := _resolve_player()
	var near := player != null and global_position.distance_squared_to(player.global_position) < 324.0
	_react.set("keep_tracking", near)
	if near:
		_react.active = true
		var want = null
		if engaged and not is_stunned():
			want = player.global_position + Vector3(0.0, 1.5, 0.0)
		# Nobody to look at: it looks where it is turning to.
		elif absf(wrapf(rotation.y - _shown_yaw, -PI, PI)) > 0.25:
			want = global_position + global_basis.z * -4.0 + Vector3(0.0, 1.8, 0.0)
		_react.set("look_target", want)
		var look := 0.45
		if state == State.CHASE or state == State.WINDUP:
			look = 1.0
		elif state == State.RECOVER:
			# Back on them by the time the blow is over, not all at once after it.
			look = lerpf(0.45, 1.0, smoothstep(0.4, 1.0, 1.0 - (_state_until - _now()) / maxf(_recover_len, 0.01)))
		_react.set("look_strength", look)
	else:
		_react.set("look_target", null)


## Hauling a cart (convoy.gd): the clip drags the blade behind it, clear of the cart.
## There is no right hand to take a handle, so only the left arm is posed: the
## right arm keeps the clip's pose, whatever convoy.gd asks of it.
func _haul_anim(delta: float) -> void:
	if anim == null:
		return
	var want := &"haul" if haul_speed > 0.15 else &"idle_haul"
	if anim.current_animation != want:
		_switch(want, 1.0, BLEND_MOVE)
	anim.speed_scale = clampf(haul_speed / WALK_SPEED, 0.5, 1.9) if want == &"haul" else 1.0
	_advance_anim(delta)
	var upper := _sk.find_bone("upper_arm.R")
	var fore := _sk.find_bone("forearm.R")
	var held := [_sk.get_bone_pose_rotation(upper), _sk.get_bone_pose_rotation(fore)]
	if hauled_by.has_method("pose_hauler"):
		hauled_by.call("pose_hauler", self)
	_sk.set_bone_pose_rotation(upper, held[0])
	_sk.set_bone_pose_rotation(fore, held[1])
	_anim_stepped = false


# --- Death ----------------------------------------------------------------------------

## It falls the way the blow would throw it, lies there, and goes.
func _fold_up() -> void:
	_blow = &""
	_next = &""
	_model.rotation.z = 0.0
	var clip := &"death_s"
	var b := Vector3(_last_blow.x, 0.0, _last_blow.z)
	if b.length_squared() > 0.01:
		var ahead := b.normalized().dot(-global_basis.z)
		if ahead < -0.4:
			clip = &"death_b"
		elif ahead > 0.4:
			clip = &"death_f"
	if _glow_surface >= 0 and mesh != null:
		mesh.set_surface_override_material(_glow_surface, _glow_out)
	if anim != null:
		_switch(clip, 1.0, BLEND_DEATH)
	if _react != null:
		_react.set("look_target", null)
	var gone := create_tween()
	gone.tween_interval(LIE_DEAD)
	gone.tween_property(self, "scale", Vector3(1.0, 0.01, 1.0), 0.45).set_ease(Tween.EASE_IN)
	gone.tween_callback(queue_free)
