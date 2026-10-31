extends "res://scripts/prosthetic.gd"

## The sword skeleton (notes 135, 136): the user's rusty metal golem, very tall and
## gaunt, riveted plate over bone, the right forearm ending in a long blade. The
## numbers and the AI are the sword hand's (prosthetic.gd, enemy.gd); this file
## only changes what it looks like doing them.
##
## models/sword_skeleton.glb carries every clip, baked by
## tools/anim_sword_skeleton.py, and plays them all at 1x on their own clocks:
##
##   idle, idle_fight, walk, run, turn_l, turn_r   chosen each tick (`_update_locomotion`)
##   turn_gl, turn_gr, relax                       turning on guard; out of the guard
##   slash_1/2/3, heavy, and each again with _s    one clip is the whole blow
##   link_1_2, 2_1, 2_3, 2_h, 3_2                  one blow's recovery into the next
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
## Root motion: each clip's `root` track is lifted out once and kept as a curve
## (`_roots`). During a blow the body moves by that curve, scaled to reach the
## player (`_slide`), so a planted foot stays planted through the step. `_s` is the
## same blow with a shuffle for a step, for when it is already close.
##
## The body's heading snaps (enemy.gd `_face`); the model follows it on a
## critically damped spring (`_turn_model`), and stood still that turning is what
## plays turn_l and turn_r.

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
## How often a light blow goes on to a second, and that on to a third.
const CHAIN_SHARE := 0.4
const CHAIN_THIRD := 0.4
## Further off than this, centre to centre, it lets the blow finish.
const CHAIN_REACH := 2.6
## Blown after a chain: this much longer until the next blow, for each one it added.
const CHAIN_REST := 0.7
## A taller capsule than enemy.tscn's: the head is up there to be hit.
const HEIGHT := 2.1
## How near it walks up to someone: its whole arm is the weapon.
const STOP_AT := 1.0
## The amber eyes, in the skeleton's own space (+Y up, +Z its front).
const EYE_POINTS: Array[Vector3] = [Vector3(-0.037, 2.035, 0.305), Vector3(0.031, 2.047, 0.277)]
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
## The chain: blows it may still add, blows it has added, and the one it is going to.
var _chain_left := 0
var _chained := 0
var _next := &""


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
	return EYES.attach_at(self, EYE_POINTS)


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


## Every clip's root track becomes a curve of forward distance, once. The clips
## are shared by every skeleton, so this happens to them all at once.
func _lift_roots() -> void:
	if not _roots.is_empty():
		return
	for clip_name in anim.get_animation_list():
		var a := anim.get_animation(clip_name)
		var curve := PackedFloat32Array()
		for i in a.get_track_count():
			if a.track_get_type(i) == Animation.TYPE_POSITION_3D and String(a.track_get_path(i)).ends_with(":root"):
				var n := int(round(a.length * 60.0)) + 1
				curve.resize(n)
				for k in n:
					curve[k] = a.position_track_interpolate(i, float(k) / 60.0).z
				a.remove_track(i)
				break
		_roots[StringName(clip_name)] = curve


static func _make_glows(base: StandardMaterial3D) -> void:
	if _glow_hot != null:
		return
	_glow_hot = base.duplicate() as StandardMaterial3D
	_glow_hot.emission_energy_multiplier = base.emission_energy_multiplier * 2.6
	_glow_out = base.duplicate() as StandardMaterial3D
	_glow_out.emission_energy_multiplier = 0.0
	_glow_out.albedo_color = Color(0.03, 0.02, 0.015)


## The state's glow is the eyes and the amber lines: hot through a blow.
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
			_chain_left = 0
			_rest()
		# The blow's clip carries on through its swing and its recovery.
		_:
			if state == State.ATTACK:
				_measure_step()


func _update_locomotion() -> void:
	if anim == null or state != State.CHASE or _dying or is_stunned():
		return
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
	if now != want:
		_switch(want, rate, BLEND_MOVE)
		return
	# Eased, never jumped: the feet would skip.
	_rate = move_toward(_rate, rate, get_physics_process_delta_time() * 6.0)
	anim.speed_scale = _rate


## Is the rig in the fighting stance at the end of this clip? Every blow ends there.
static func _on_guard(clip: StringName) -> bool:
	var name_ := String(clip)
	return clip == &"idle_fight" or clip == &"turn_gl" or clip == &"turn_gr" \
		or name_.begins_with("slash") or name_.begins_with("heavy") or name_.begins_with("link")


## Puts `clip` on the rig, the old pose decaying into it. Walk and run take over
## at the same point of the stride; out of a stand or a blow, on the right foot,
## which is the one ahead. `assigned_animation`, not `current_animation`: a blow's
## clip may have run out the tick before.
func _switch(clip: StringName, rate: float, blend: float) -> void:
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


# --- Blows ----------------------------------------------------------------------------

func _start_blow() -> void:
	if _next != &"":
		_start_link()
		return
	var clip := &"heavy"
	_chained = 0
	_chain_left = 0
	if attack_kind != Attack.SLAM:
		var from := LIGHTS.duplicate()
		from.erase(_last_light)
		clip = from[randi() % from.size()]
		_last_light = clip
		if randf() < CHAIN_SHARE:
			_chain_left = 2 if randf() < CHAIN_THIRD else 1
	var need := 0.3
	var player := _resolve_player()
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
	if _chain_left <= 0:
		_rest()


## A chain cost it: both blows wait longer than they would after one.
func _rest() -> void:
	if _chained <= 0:
		return
	var until := _now() + _cooldown_of(Attack.NORMAL) + CHAIN_REST * float(_chained)
	_cooldowns[Attack.NORMAL] = maxf(_ready_at(Attack.NORMAL), until)
	_cooldowns[Attack.SLAM] = maxf(_ready_at(Attack.SLAM), until)
	_chained = 0


## Each tick: at CHAIN_OUT the blow goes on, if it is going to; at the end of a link
## the next blow takes over. Just before the link's end, which its clip stops at.
func _tend_chain(delta: float) -> void:
	if anim == null or _blow == &"":
		return
	if _next != &"" and state == State.WINDUP:
		if not anim.is_playing():
			_join(LINK_TIME)
		elif anim.current_animation_position >= LINK_TIME - delta * 1.5:
			_join(anim.current_animation_position)
	elif state == State.RECOVER and _chain_left > 0 and anim.is_playing() \
			and anim.current_animation_position >= CHAIN_OUT:
		_go_on()


func _go_on() -> void:
	var base := StringName(String(_blow).trim_suffix("_s"))
	var from: Array = CHAIN_NEXT.get(base, []).duplicate()
	if _now() < _ready_at(Attack.SLAM):
		from.erase(&"heavy")
	var player := _resolve_player()
	var near := player != null and engaged and not is_stunned() \
		and Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() <= CHAIN_REACH
	if not near or from.is_empty():
		_chain_left = 0
		_rest()
		return
	_next = from[randi() % from.size()]
	_chain_left = 0 if _next == &"heavy" else _chain_left - 1
	_chained += 1
	if _next != &"heavy":
		_last_light = _next
	# The state's own wind-up, telegraph and all. `_start_blow` sees `_next`.
	_enter_windup(Attack.SLAM if _next == &"heavy" else Attack.NORMAL)


func _start_link() -> void:
	var from := StringName(String(_blow).trim_suffix("_s"))
	var clip := StringName("link_%s_%s" % [LINK_TAG[from], LINK_TAG[_next]])
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
	var curve: PackedFloat32Array = _roots.get(clip, PackedFloat32Array())
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
	_tend_react()


## The model's heading chases the body's on a spring, so a snapped `_face` reads
## as a turn. `_yaw_v`, its speed, is what the turning clips are played by. The swing
## takes hold at once; anything else eases in, or the end of a blow shows as a lurch.
func _turn_model(delta: float) -> void:
	var want := TURN_SPRING
	if _blow != &"":
		want = TURN_SPRING_BLOW if state == State.ATTACK else TURN_SPRING_LOADED
	_turn_k = want if want == TURN_SPRING_BLOW else move_toward(_turn_k, want, delta * 20.0)
	var k := _turn_k
	var off := wrapf(rotation.y - _shown_yaw, -PI, PI)
	_yaw_v += (k * k * off - 2.0 * k * _yaw_v) * delta
	_shown_yaw = wrapf(_shown_yaw + _yaw_v * delta, -PI, PI)
	_model.rotation.y = PI + wrapf(_shown_yaw - rotation.y, -PI, PI)


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
	_chain_left = 0
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
