extends "res://scripts/prosthetic.gd"

## The Proel builder (note 149; the hammer hand of note 93, its hand still `&"hammer"`,
## which is in the saves): the user's rusted metal golem, as tall and gaunt as the
## Proel swordsman, its forearms ending in yokes and iron heads half a metre across. Slow,
## very hard to stop, and with two moves:
##
##   the pound   going after someone it walks at them at SLAM_SPEED, and every stride
##               brings a hammer down on the floor in front of it, left, right, left
##               (`slam_walk`). With nowhere left to go it stands and does the same
##               (`slam_stand`). A hammer that catches them on the way down knocks them
##               flat; the floor where it lands shakes for SHOCK_RADIUS round it.
##   the spin    close in, off a left hammer landing: it twists away over the hammer and
##               hauls it into a coil, shaking under the load, then comes round three times,
##               fast, the hammers dragging it (`spin_*`, notes 150, 151), walking itself at
##               them as it goes.
##
## models/proel_builder.glb carries every clip, baked by tools/anim_proel_builder.py,
## and plays them at 1x on their own clocks, so the feet and the hammers keep to the floor:
##
##   idle, walk, turn_l, turn_r       walking about (`_update_locomotion`)
##   slam_in                          from a stand into the pound
##   slam_walk, slam_stand            the pound: same clock, same arms
##   spin_w, spin_s                   one clip each: wind-up, swing, recovery. They start on
##                                    the frame of a left hammer landing in slam_walk or
##                                    slam_stand and end inside slam_in, so no blend either way
##   reel_wl/wr/sl/sr, reel_o         parried (`reel_from`): by which hammer, in stride or
##                                    standing, or in the spin; ending inside slam_in too
##   stagger_b/f/l/r                  thrown by a shove hard enough (`apply_knockback`)
##   death_b/f/s                      by where the last blow came from
##
## Every change of clip is inertialized (sword_skeleton_react.gd), but for those. `root` is
## lifted out of the clips once: its y walks the body through a spin or a reel (`_slide`),
## its x is the turn of a spin or of `reel_o`, which the model takes (`_turn_model`), so
## anything breaking the spin off leaves it facing wherever it had got to.
##
## It turns no faster than TURN_MOST (`_face`), so getting behind it works, for a moment.
## Ordinary blows land without breaking its stride (`apply_knockback`); a shove of
## SHOVE_STOPS does, and a parried hammer does (`reel_from`).

const MODEL := preload("res://models/proel_builder.glb")
const REACT := preload("res://scripts/sword_skeleton_react.gd")
const HAMMERS := preload("res://scripts/proel_builder_hammers.gd")
const EYES := preload("res://scripts/skeleton_eyes.gd")

## What the clips are authored for (tools/anim_proel_builder.py WALK_V, SLAM_V).
const WALK_SPEED := 1.1
const SLAM_SPEED := 1.15
const TURN_RATE := 1.22
const POUNDS: Array[StringName] = [&"slam_walk", &"slam_stand"]
const SPINS: Array[StringName] = [&"spin_w", &"spin_s"]
const REELS: Array[StringName] = [&"reel_wl", &"reel_wr", &"reel_sl", &"reel_sr", &"reel_o"]
## The pound's clock: tools/anim_proel_builder.py SLAM_T, HIT_L and HIT_R x SLAM_T, and
## IN_PHASE x SLAM_T. When each hammer lands, left then right, and where `slam_in` ends.
const SLAM_CYCLE := 2.0
const SLAM_AT: Array[float] = [0.12, 1.12]
const SLAM_FROM_IN := 0.64
## Before a hammer lands: when it starts to listen for a parry, and when it can hurt. The
## first is as it hangs at the top, the second as it comes down in front of them.
const SLAM_CUE := 0.5
const SLAM_LISTEN := 0.55
const SLAM_LIVE := 0.3
## The floor where a hammer lands, for anyone with their feet on it, through a guard
## as any blow, and how far off that can be felt.
const SHOCK_RADIUS := 1.7
const SHOCK_DAMAGE := 12.0
const SHOCK_FELT := 14.0
const SHOCK_SHAKE := 0.26
## A blow that lands through a guard shoves them this hard.
const GUARD_SHOVE := 5.0
## The spin. In reach by this gap it goes into it, this often, as the LEFT hammer lands: its
## clip starts on that frame. How hard it hits, how far it throws them, how far it means to
## walk to get at them, and how far the rest of a stride carries it into the coil (SLAM_V x
## SPIN_CARRY x 0.5), until SPIN_COILED. SPIN_JOIN and REEL_JOIN: how far into `slam_in` the
## end of each clip is (tools/anim_proel_builder.py, which has all of these).
const SPIN_FROM := 2.6
const SPIN_SHARE := 0.75
const SPIN_DAMAGE := 40.0
const SPIN_THROW := 10.0
const SPIN_TRAVEL := 1.5
const SPIN_TRAVEL_MOST := 1.2
const SPIN_STANDOFF := 0.9
const SPIN_CARRIED := 0.29
const SPIN_COILED := 1.15
const SPIN_JOIN := 0.9
const REEL_JOIN := 0.7
## Parried: tools/anim_proel_builder.py REEL; the moment its hammer comes back down onto the
## floor, as `reel`'s `hit_arm` has it; how fast the spin turns flat out (`[spin] top speed`).
const REEL_TIME := 2.2
const REEL_THUD := 1.02
const SPIN_TOP_RATE := 10.66
## The stamp the coil ends on, and how hard the two are felt.
const COIL_PLANT := 0.92
const THUD_SHAKE := 0.14
## The most it turns, rad/s, and how stiff the model's heading is on the body's.
const TURN_MOST := 1.3
const TURN_SPRING := 12.0
## Under this it stands; over it, the turning shows in the feet.
const TURN_SHOWS := 0.5
## What it takes to stop it: the same shove that breaks a shield's guard. The stagger
## clips are this long (tools/anim_proel_builder.py `stagger`), and it is stopped for it.
const SHOVE_STOPS := 8.5
const STAGGER_TIME := 1.2
## Keeping apart: how often it looks for fellows, how far, how near they may come
## centre to centre, and how hard they are eased apart.
const PACK_EVERY := 0.3
const SPACE := 2.2
const SPACE_PUSH := 1.6
## A taller capsule than enemy.tscn's, as the swordsman's.
const HEIGHT := 2.1
## How near it walks up to someone, edge to edge, and how much further than that they
## must get before it sets off again.
const STOP_AT := 0.35
const STOP_SLACK := 0.6
## The eyes, in the skeleton's own space (+Y up, +Z its front), as the swordsman's.
const EYE_POINTS: Array[Vector3] = [Vector3(0.01, 2.03, 0.335), Vector3(-0.06, 2.025, 0.335)]
const EYE_COLOUR := Color(1.0, 0.07, 0.04)
const EYE_HALO := 0.2
const EYE_HALO_SIZE := 0.05
const EYE_HOT := 1.5
## Where the skull looks as it was modelled, in skeleton space: straight ahead, stooped.
const HEAD_REST_FACE := Vector3(0.0, -0.5, 0.85)
## How long a clip may take to settle in.
const BLEND_MOVE := 0.4
const BLEND_POUND := 0.35
const BLEND_IN := 0.3
const BLEND_HIT := 0.26
const BLEND_PARRY := 0.12
const BLEND_DEATH := 0.3
## Lying dead this long, then it goes.
const LIE_DEAD := 6.0

## Clip name -> forward distance by 1/60 s: the root tracks, lifted out once.
static var _roots := {}
## Clip name -> its turn, radians to its left by 1/60 s, for those that turn.
static var _yaws := {}
static var _glow_hot: StandardMaterial3D
static var _glow_out: StandardMaterial3D
static var _dust_mesh: QuadMesh
static var _dust_fade: Gradient

var _model: Node3D = null
var _sk: Skeleton3D = null
var _react: SkeletonModifier3D = null
var _glow_surface := -1
var _shown_yaw := 0.0
var _yaw_v := 0.0
var _rate := 1.0
## A clip whose root walks the body, and where in it.
var _blow := &""
var _blow_t := 0.0
var _blow_scale := 1.0
var _last_blow := Vector3.ZERO
var _last_amount := 0.0
## Going somewhere, in the pound.
var _advancing := true
## The pound's clock last tick; < 0 when it was not pounding.
var _beat_t := -1.0
var _spinning := false
## The clip whose turn the model is taking, from this heading, this much of it.
var _yaw_clip := &""
var _spin_from := 0.0
var _yaw_scale := 1.0
var _held := false
var _reeling := false
## The moment in a spin or a reel still to be felt on the floor; < 0 when there is none.
var _thud_at := -1.0
## Other builders near it, untyped: one may be freed before the next look.
var _pack: Array = []
var _next_pack := 0.0


func _init() -> void:
	super()
	hand = &"hammer"
	walk_anim_speed = WALK_SPEED
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
	add_to_group(&"proel_builders")
	_next_pack = _now() + randf() * PACK_EVERY
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
	return HAMMERS.grip(self)


func _setup_animations() -> void:
	if anim == null:
		return
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for looping: StringName in [&"idle", &"walk", &"turn_l", &"turn_r"] + POUNDS:
		anim.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
	_lift_roots()
	var found := find_children("*", "Skeleton3D", true, false)
	_sk = found[0] as Skeleton3D
	_react = REACT.new()
	_react.name = "HitReact"
	_react.set("player", anim)
	_react.set("rest_face", HEAD_REST_FACE)
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


## Every clip's root track becomes a curve of forward distance, once, and the spin's its
## turn. The clips are shared by every builder, so this happens to them all at once.
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
		if clip_name.begins_with("spin_") or clip_name == "reel_o":
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
	_react.call("hit", from, 0.3 + 0.3 * clampf(_last_amount / 20.0, 0.0, 1.0))


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	_last_blow = _from_direction
	_last_amount = amount
	super(amount, _from_direction)


## Only a real shove stops it, and nothing does in the spin but a parry.
func apply_knockback(impulse: Vector3, stun_time := 0.25) -> void:
	if _reeling or _spinning or Vector2(impulse.x, impulse.z).length() < SHOVE_STOPS:
		return
	super(impulse, maxf(stun_time, STAGGER_TIME))


## Parried (player.gd `_on_guarded`): the hammer stops dead on the guard and is thrown back
## up, and takes the whole body back with it, in the clip from the pose it was in, stunned
## for the length of it. In the spin the body goes on round on what it had.
func reel_from(away: Vector3) -> void:
	if _dying or caged:
		return
	if anim == null:
		super.apply_knockback(away * 3.0, REEL_TIME)
		return
	_attack_connected = true
	var clip := _reel_clip()
	var spun := 0.0
	if _spinning and _yaw_clip != &"":
		var yaw: PackedFloat32Array = _yaws[_yaw_clip]
		var t := anim.current_animation_position
		spun = (_on_curve(yaw, t + 0.05) - _on_curve(yaw, t - 0.05)) / 0.1
	if state != State.CHASE:
		_enter_chase()
	_end_spin()
	_beat_t = -1.0
	var now := _now()
	# Over when its clip is (`_end_reel`): the parry's hit-stop slows one clock and not the other.
	_stun_until = maxf(_stun_until, now + REEL_TIME + 1.0)
	_reeling = true
	_cooldowns[Attack.SPIN] = maxf(_ready_at(Attack.SPIN), now + REEL_TIME + _cooldown_of(Attack.SPIN) * 0.5)
	if _react != null:
		# The spin's arms can be anywhere in their round; the pound's are where the clip starts.
		_react.call("crossfade", BLEND_HIT if clip == &"reel_o" else BLEND_PARRY)
		_react.call("stop_dead")
	_put_on(clip, 0.0)
	_blow = clip
	_blow_t = 0.0
	_blow_scale = 1.0
	_thud_at = REEL_THUD
	if clip == &"reel_o":
		_yaw_clip = clip
		_spin_from = _shown_yaw
		_yaw_scale = clampf(spun / SPIN_TOP_RATE, 0.0, 1.0)


## Which reel: by the hammer that met the guard, in stride or standing, or the spin's.
func _reel_clip() -> StringName:
	var live: int = HAMMERS.NONE if _sword == null else int(_sword.get("live"))
	if _spinning or live == HAMMERS.BOTH:
		return &"reel_o"
	if live == HAMMERS.NONE:
		live = randi() % 2
	var walking := StringName(anim.assigned_animation) == &"slam_walk"
	return StringName("reel_%s%s" % ["w" if walking else "s", "l" if live == 0 else "r"])


## Thrown by a blow: a stumble the way it was thrown.
func _flinch(impulse: Vector3, _time: float) -> void:
	if _dying or anim == null:
		return
	_blow = &""
	_beat_t = -1.0
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
			_start_spin()
		ANIM_IDLE:
			_end_spin()
		ANIM_RECOVER:
			if _sword != null:
				_sword.set("live", HAMMERS.NONE)
		# The spin's clip carries on through its swing and its recovery.
		_:
			if state == State.ATTACK and _sword != null:
				_sword.set("live", HAMMERS.BOTH)


func _windup_for(_kind: int) -> float:
	return SPIN_WINDUP


func _recover_for(_kind: int) -> float:
	return SPIN_RECOVER


func _damage_for(kind: int) -> float:
	return SPIN_DAMAGE if kind == Attack.SPIN else attack_damage


func is_attacking() -> bool:
	return state == State.ATTACK or (_sword != null and int(_sword.get("live")) != HAMMERS.NONE)


## Knocked flat, or shoved if the guard met it. Parried, it is the one going back.
func _on_blow_landed(player: Node3D, kind: int) -> void:
	if _reeling:
		return
	var way := Vector3(_attack_direction.x, 0.0, _attack_direction.z).normalized()
	if player.get("_blocking") == true:
		if player.has_method("apply_knockback"):
			player.call("apply_knockback", way * GUARD_SHOVE)
	elif player.has_method("knock_down"):
		player.call("knock_down", way, SPIN_THROW if kind == Attack.SPIN else HAMMER_KNOCKDOWN)


## It turns as it can, and not at all once a spin is coming.
func _face(direction: Vector3) -> void:
	if _held or direction.length_squared() <= 0.001:
		return
	var want := atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(rotation.y, want, TURN_MOST * get_physics_process_delta_time())


# --- Clips ----------------------------------------------------------------------------

func _switch(clip: StringName, rate: float, blend: float) -> void:
	if _react != null:
		_react.call("crossfade", blend)
	_rate = rate
	anim.speed_scale = rate
	anim.play(clip, 0.0, 1.0)
	anim.seek(0.0, true)


## A swap with no blend: the two clips are the same pose here.
func _put_on(clip: StringName, t: float) -> void:
	_rate = 1.0
	anim.speed_scale = 1.0
	anim.play(clip, 0.0, 1.0)
	anim.seek(t, true)


func _update_locomotion() -> void:
	if anim == null or state != State.CHASE or _dying or is_stunned():
		return
	if engaged and not caged:
		_tend_pound_clip()
		return
	var moving := get_real_velocity()
	var speed := Vector2(moving.x, moving.z).length()
	var now := anim.current_animation
	var want := &"idle"
	var rate := 1.0
	if speed > 0.15:
		want = &"walk"
		rate = clampf(speed / WALK_SPEED, 0.55, 1.7)
	elif absf(_yaw_v) > TURN_SHOWS:
		want = &"turn_l" if _yaw_v > 0.0 else &"turn_r"
		rate = clampf(absf(_yaw_v) / TURN_RATE, 0.6, 1.5)
	if now != want:
		_switch(want, rate, BLEND_MOVE)
		return
	# Eased, never jumped: the feet would skip.
	_rate = move_toward(_rate, rate, get_physics_process_delta_time() * 6.0)
	anim.speed_scale = _rate


func _tend_pound_clip() -> void:
	var clip := StringName(anim.assigned_animation)
	if clip == &"slam_in":
		# A tick short of the end: a clip that has stopped has no position.
		if not anim.is_playing() or anim.current_animation_position + get_physics_process_delta_time() * 1.5 >= anim.current_animation_length:
			# It ends on slam_stand's frame: the legs blend into a stride, the arms are the same.
			if _advancing and _react != null:
				_react.call("crossfade", BLEND_POUND)
			_put_on(&"slam_walk" if _advancing else &"slam_stand", SLAM_FROM_IN)
			# The hammer it hoisted is already nearly at the top: its cue is still to come.
			_beat_t = SLAM_FROM_IN - 0.05
		return
	# Nearly out of a spin or a reel, whatever the state's clock says: `_run_on` has it.
	if (clip in SPINS or clip in REELS) and anim.is_playing() and anim.current_animation_position > anim.current_animation_length - 0.3:
		return
	if clip not in POUNDS:
		_switch(&"slam_in", 1.0, BLEND_IN)
		return
	var want := &"slam_walk" if _advancing else &"slam_stand"
	if clip != want:
		var t := anim.current_animation_position
		if _react != null:
			_react.call("crossfade", BLEND_POUND)
		_put_on(want, t)


# --- The hunt -------------------------------------------------------------------------

## Along the navmesh, at the pound's own pace, only while the feet are walking.
func _chase(delta: float, now: float, _player_node: Node3D, flat: Vector3, _distance: float, gap: float) -> bool:
	var pursue := flat.normalized()
	if agent != null:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = global_position + flat
		if not agent.is_navigation_finished():
			var to_next := agent.get_next_path_position() - global_position
			to_next.y = 0.0
			if to_next.length() > 0.1:
				pursue = to_next.normalized()
	_advancing = gap > stop_distance + (0.0 if _advancing else STOP_SLACK)
	_face(pursue if _advancing else flat)
	var want := Vector3.ZERO
	if anim != null and _advancing and StringName(anim.assigned_animation) == &"slam_walk":
		want = -global_basis.z * SLAM_SPEED
	velocity.x = move_toward(velocity.x, want.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, want.z, acceleration * delta)
	_slide()
	return true


## The end of a spin or a reel is the middle of slam_in: straight on the tick it ends, with
## no blend, whatever state the clock says it is still in (a spin starts a tick or two into
## its clip, and a clip that has stopped would stand still). Only going after someone.
func _run_on(delta: float) -> void:
	if anim == null or not engaged or not anim.is_playing():
		return
	var clip := StringName(anim.assigned_animation)
	if clip not in SPINS and clip not in REELS:
		return
	var left := anim.current_animation_length - anim.current_animation_position
	if left <= delta * 1.5:
		_put_on(&"slam_in", (SPIN_JOIN if clip in SPINS else REEL_JOIN) - left)
		_blow = &""


## The reel's clip is over, however it ended.
func _end_reel() -> void:
	_reeling = false
	_blow = &""
	_stun_until = minf(_stun_until, _now())
	if _yaw_clip != &"":
		_yaw_clip = &""
		rotation.y = _shown_yaw
		_yaw_v = 0.0


## Each tick of the pound: its beats, read off the clip as it passes them.
func _tend_pound() -> void:
	if anim == null or _sword == null:
		return
	var clip := StringName(anim.assigned_animation)
	if clip not in POUNDS or not anim.is_playing() or state != State.CHASE or is_stunned() or not engaged:
		if state == State.CHASE:
			_sword.set("live", HAMMERS.NONE)
		_beat_t = -1.0
		return
	var t := anim.current_animation_position
	if _beat_t >= 0.0:
		for side in 2:
			if _passed(_beat_t, t, SLAM_AT[side] - SLAM_CUE):
				_listen()
			if _passed(_beat_t, t, SLAM_AT[side] - SLAM_LIVE):
				_bring_down(side)
			if _passed(_beat_t, t, SLAM_AT[side]):
				_land(side)
	_beat_t = t
	var player := _resolve_player()
	if player != null and int(_sword.get("live")) != HAMMERS.NONE:
		_aim_at(player)
		_sword_connect(player)


## Did the clock pass `at` between these two readings of it, going round if need be?
static func _passed(from: float, to: float, at: float) -> bool:
	var x := fposmod(at, SLAM_CYCLE)
	if to >= from:
		return from < x and x <= to
	return x > from or x <= to


func _aim_at(player: Node3D) -> void:
	var way := player.global_position - global_position
	way.y = 0.0
	if way.length_squared() > 0.01:
		_attack_direction = way.normalized()


func _listen() -> void:
	for node in Coop.all():
		var p := node as Node3D
		if p.has_method("parry_cue") and p.global_position.distance_squared_to(global_position) < 36.0:
			p.call("parry_cue", self, SLAM_LISTEN)


func _bring_down(side: int) -> void:
	attack_kind = Attack.SLAM
	_attack_connected = false
	_sword.set("live", side)
	_sword.call("clear_sweep")
	_apply_state_color(windup_color, windup_glow)


## A hammer on the floor. It is not a blow from anyone: the floor, through the guard as any
## blow is, and no parry. Then, if it was the left, it may go into the spin.
func _land(side: int) -> void:
	_sword.set("live", HAMMERS.NONE)
	_apply_state_color(_base_color, base_glow)
	var at: Vector3 = _sword.call("head", side)
	at.y = global_position.y
	_dust(at)
	for node in Coop.all():
		var p := node as Node3D
		var way := p.global_position - at
		way.y = 0.0
		var off := way.length()
		if off < SHOCK_FELT:
			p.set("_shake", maxf(float(p.get("_shake")), SHOCK_SHAKE * (1.0 - off / SHOCK_FELT)))
		var aired: bool = p.has_method("is_on_floor") and not p.call("is_on_floor")
		if off > SHOCK_RADIUS or aired or absf(p.global_position.y - global_position.y) > max_height_difference:
			continue
		if p == _player and _attack_connected:
			continue
		p.call("take_damage", SHOCK_DAMAGE, way / off if off > 0.01 else -global_basis.z, null)
	var player := _resolve_player()
	if side == 0 and player != null and _wants_spin(player):
		_enter_windup(Attack.SPIN)


func _wants_spin(player: Node3D) -> bool:
	var seen := _now() + sight_memory - _seen_until < 0.4
	var gap := _flat_gap(global_position, player.global_position) - _body_radius - maxf(_target_radius, 0.0)
	return seen and _now() >= _ready_at(Attack.SPIN) and gap <= SPIN_FROM and randf() < SPIN_SHARE \
		and absf(player.global_position.y - global_position.y) <= max_height_difference


## Something heavy felt through the floor, short of hurting anyone.
func _thud(at: Vector3) -> void:
	at.y = global_position.y
	_dust(at)
	for node in Coop.all():
		var p := node as Node3D
		var off := p.global_position.distance_to(at)
		if off < SHOCK_FELT:
			p.set("_shake", maxf(float(p.get("_shake")), THUD_SHAKE * (1.0 - off / SHOCK_FELT)))


## Dust, kicked out along the floor. One mesh and one fade for all of them.
func _dust(at: Vector3) -> void:
	if not Graphics.effects:
		return
	var player := _resolve_player()
	if player == null or global_position.distance_squared_to(player.global_position) > 625.0:
		return
	if _dust_mesh == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
		var soft := Gradient.new()
		soft.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		soft.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		var puff := GradientTexture2D.new()
		puff.gradient = soft
		puff.fill = GradientTexture2D.FILL_RADIAL
		puff.fill_from = Vector2(0.5, 0.5)
		puff.fill_to = Vector2(1.0, 0.5)
		puff.width = 48
		puff.height = 48
		m.albedo_texture = puff
		var q := QuadMesh.new()
		q.size = Vector2(0.8, 0.8)
		q.material = m
		_dust_mesh = q
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.34, 0.31, 0.27, 0.42))
		ramp.set_color(1, Color(0.3, 0.27, 0.24, 0.0))
		_dust_fade = ramp
	var p := CPUParticles3D.new()
	p.mesh = _dust_mesh
	p.one_shot = true
	p.emitting = false
	p.amount = 18
	p.lifetime = 0.7
	p.lifetime_randomness = 0.4
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 80.0
	p.flatness = 0.75
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0.0, 0.25, 0.0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.color_ramp = _dust_fade
	get_parent().add_child(p)
	p.global_position = at + Vector3(0.0, 0.08, 0.0)
	p.finished.connect(p.queue_free)
	p.emitting = true


# --- The spin -------------------------------------------------------------------------

## The body takes its line at them now and keeps it; the model's heading is the clip's
## from here, from wherever it stood. The clip starts on the frame of the hammer that has
## just landed, so it goes straight on from where the pound is.
func _start_spin() -> void:
	var player := _resolve_player()
	var walking := StringName(anim.assigned_animation) == &"slam_walk"
	var since := fposmod(anim.current_animation_position - SLAM_AT[0], SLAM_CYCLE)
	var clip := &"spin_w" if walking else &"spin_s"
	# A hammer that met nobody left its cue open, and the spin has none.
	for node in Coop.all():
		if node.has_method("_take_parry_cue"):
			node.call("_take_parry_cue", self)
	_spin_from = _shown_yaw
	_yaw_clip = clip
	_yaw_scale = 1.0
	_spinning = true
	_beat_t = -1.0
	_thud_at = COIL_PLANT
	var need := SPIN_TRAVEL
	if player != null:
		var to := player.global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.01:
			rotation.y = atan2(-to.x, -to.z)
		need = to.length() - SPIN_STANDOFF - (SPIN_CARRIED if walking else 0.0)
	_held = true
	_blow_scale = clampf(need / SPIN_TRAVEL, 0.0, SPIN_TRAVEL_MOST)
	_put_on(clip, since)
	_blow = clip
	_blow_t = since


## However it ended, the body takes the heading the model has got to.
func _end_spin() -> void:
	if not _spinning:
		return
	_spinning = false
	_yaw_clip = &""
	_held = false
	_blow = &""
	rotation.y = _shown_yaw
	# At once: a parry comes after this tick's `_turn_model`.
	if _model != null:
		_model.rotation.y = PI
	_yaw_v = 0.0
	if _sword != null:
		_sword.set("live", HAMMERS.NONE)


## Drives the spin: it stands where the clip's root walks it, and both hammers can hurt.
func _run_attack(_delta: float, player: Node3D, _gap: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_slide()
	if _sword != null:
		_aim_at(player)
		_sword_connect(player)


# --- Each tick ------------------------------------------------------------------------

static func _on_curve(curve: PackedFloat32Array, t: float) -> float:
	if curve.is_empty():
		return 0.0
	var f := clampf(t * 60.0, 0.0, float(curve.size() - 1))
	var i := int(f)
	var j := mini(i + 1, curve.size() - 1)
	return lerpf(curve[i], curve[j], f - float(i))


func _root_at(clip: StringName, t: float) -> float:
	return _on_curve(_roots.get(clip, PackedFloat32Array()), t)


## Every move goes through here. In a spin or a reel the body goes where the clip's step
## takes it; the dead do not move, whatever gravity says (the capsule is off).
func _slide() -> void:
	if _dying:
		return
	if _blow != &"" and anim != null:
		var dt := get_physics_process_delta_time()
		var t := anim.current_animation_position if anim.is_playing() else _blow_t
		# The rest of a stride is not the walk at them: it goes as far as it goes.
		var step := (_root_at(_blow, t) - _root_at(_blow, _blow_t)) * (_blow_scale if t > SPIN_COILED else 1.0)
		_blow_t = t
		var fwd := -global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		velocity.x = fwd.x * step / dt
		velocity.z = fwd.z * step / dt
	var parted := _keep_clear()
	super()
	if parted != Vector3.ZERO:
		move_and_collide(parted * get_physics_process_delta_time())


func _keep_clear() -> Vector3:
	var now := _now()
	if now >= _next_pack:
		_next_pack = now + PACK_EVERY
		_pack.clear()
		if not caged:
			for node in get_tree().get_nodes_in_group(&"proel_builders"):
				var o := node as Node3D
				if o != self and global_position.distance_squared_to(o.global_position) < 25.0:
					_pack.append(o)
	var parted := Vector3.ZERO
	for o in _pack:
		if not is_instance_valid(o) or o.get("_dying") == true:
			continue
		var from: Vector3 = global_position - o.global_position
		if absf(from.y) > 1.5:
			continue
		from.y = 0.0
		var d := from.length()
		if d < SPACE:
			parted += (from / d if d > 0.01 else global_basis.x) * (1.0 - d / SPACE) * SPACE_PUSH
	return parted


func _physics_process(delta: float) -> void:
	_run_on(delta)
	if _reeling and (anim == null or not anim.is_playing() or StringName(anim.assigned_animation) not in REELS):
		_end_reel()
	super(delta)
	if _dying:
		_advance_anim(delta)
		return
	if _dormant or _model == null:
		return
	_turn_model(delta)
	_tend_pound()
	_tend_react()
	_tend_thud()


## The coil's last stamp, or the parried hammer back on the floor.
func _tend_thud() -> void:
	if _thud_at < 0.0 or anim == null or _sword == null:
		return
	var clip := StringName(anim.assigned_animation)
	if clip not in SPINS and clip not in REELS:
		_thud_at = -1.0
	elif anim.is_playing() and anim.current_animation_position >= _thud_at:
		_thud_at = -1.0
		_thud(_sword.call("head", 0))


## The model's heading chases the body's on a spring; in the spin or `reel_o` it is the
## clip's, and stays where the clip left it until that is over.
func _turn_model(delta: float) -> void:
	if _yaw_clip != &"":
		if anim.is_playing() and StringName(anim.assigned_animation) == _yaw_clip:
			var turned := _on_curve(_yaws[_yaw_clip], anim.current_animation_position) * _yaw_scale
			_shown_yaw = wrapf(_spin_from + turned, -PI, PI)
	else:
		var off := wrapf(rotation.y - _shown_yaw, -PI, PI)
		_yaw_v += (TURN_SPRING * TURN_SPRING * off - 2.0 * TURN_SPRING * _yaw_v) * delta
		_shown_yaw = wrapf(_shown_yaw + _yaw_v * delta, -PI, PI)
	_model.rotation.y = PI + wrapf(_shown_yaw - rotation.y, -PI, PI)


## Near the player the layer stays on, so every switch knows how the rig was moving, and
## the head follows them, right to the top of the coil. In the spin the hammers have the
## whole of it.
func _tend_react() -> void:
	if _react == null:
		return
	var player := _resolve_player()
	var near := player != null and global_position.distance_squared_to(player.global_position) < 324.0
	_react.set("keep_tracking", near)
	if near:
		_react.active = true
		var want = null
		if engaged and not is_stunned() and (not _spinning or state == State.WINDUP):
			want = player.global_position + Vector3(0.0, 1.5, 0.0)
		_react.set("look_target", want)
		_react.set("look_strength", 0.7)
	else:
		_react.set("look_target", null)


# --- Death ----------------------------------------------------------------------------

## It falls the way the blow would throw it, lies there, and goes.
func _fold_up() -> void:
	_reeling = false
	_end_spin()
	_yaw_clip = &""
	_thud_at = -1.0
	_blow = &""
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
