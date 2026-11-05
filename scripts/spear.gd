extends Node3D

## The spear (2026-10-08): the second weapon, held when the hotbar slot in hand
## holds `&"spear"`. Lives under the player's Head as the first-person model
## and does all of its own fighting; `player.gd` only routes the keys to it
## (`stab`, `sweep`, `throw`) and carries the body forward for the lunge
## (`player.begin_spear_dash`).
##
## Every attack is a Higgsfield motion clip (note 167, player_motion.gd), played
## by the body and by this first-person spear alike:
## - STAB (left click, "attack"): a combo of three (note 167; the user: "2 short
##   attacks and the third attack should wait a hair longer and move the player
##   forward and do a little more damage than the other two, then wait a hair
##   before starting the other little attacks"). Two short jabs, `STAB_DAMAGE`
##   each, `STAB_EVERY` apart (&"jab_a", &"jab_b"); the third after
##   `LUNGE_AFTER`, a lunge (&"lunge") that drives the player `LUNGE_STEP` forward
##   for `LUNGE_DAMAGE`; then `LUNGE_REST` before the jabs begin again. A click
##   held early fires on the beat; left alone for `COMBO_FORGET` the combo starts
##   over.
## - SWEEP (Q, "thrust"; the dash until note 167): the scout's delayed swipe
##   (scout.gd). Wound up high on the left for `SWEEP_STRIKE`, then swept low
##   through the legs, left to right: `SWEEP_DAMAGE` to everything in the arc and
##   KNOCKED DOWN (`_knock_down`). `SWEEP_COOLDOWN` between sweeps; a blow in the
##   wind-up cuts it off.
## - THROW (F, "slam"), once every `THROW_COOLDOWN` 10 s: drawn back over the shoulder and hurled down the
##   crosshair. Whatever it hits -- or `THROW_RANGE` out if it hits nothing --
##   it EXPLODES (`_explode`: `BLAST_DAMAGE` falling off to half at
##   `BLAST_RADIUS`, thrown outward, behind stone spared), then it is pulled back
##   to the hand along a glowing tether, butt first. Nothing else can be done
##   with the spear until it is caught.
##
## The stab's, sweep's and wind-up's times here are all before `time_scale()`, the
## player's `attack_time_scale` (note 144).
##
## The model is built from primitives (an ash shaft, a leaf blade, an iron socket
## and butt spike, leather bindings) along -Z, tip forward. In the hand it is
## drawn pulled toward the camera like the sword (`use_z_clip_scale`); the
## thrown one is an ordinary copy.

const STAB_DAMAGE := 10.0
## Jabs a little under four a second: out by STAB_OUT (where it bites), home by
## STAB_BACK. A
## click that comes too soon is not dropped but held (`_stab_queued`) and fired
## the moment the next is due, so spam-clicking gives a steady rhythm.
const STAB_EVERY := 0.28
const STAB_OUT := 0.09
const STAB_BACK := 0.28
## The third of the combo: after the second jab by LUNGE_AFTER (a hair longer
## than STAB_EVERY), biting at LUNGE_OUT for LUNGE_DAMAGE, the player carried
## LUNGE_STEP metres forward through it; the next jab LUNGE_REST after it. A
## combo left COMBO_FORGET past its next beat starts over.
const LUNGE_AFTER := 0.36
const LUNGE_OUT := 0.26
const LUNGE_DAMAGE := 16.0
const LUNGE_REACH := 3.2
const LUNGE_STEP := 1.1
const LUNGE_STEP_TIME := 0.14
const LUNGE_REST := 0.62
const COMBO_FORGET := 0.4
const COMBO := [&"jab_a", &"jab_b", &"lunge"]
## Eye to the furthest a stab reaches, and how wide it is.
const STAB_REACH := 2.7
const STAB_WIDTH := 0.45

## Q's sweep (the clip &"sweep"): it strikes at SWEEP_STRIKE (a long wind-up,
## the scout's 0.6), everything within the low arc in front (SWEEP_REACH out,
## SWEEP_WIDTH across, up to SWEEP_HIGH), knocked down for SWEEP_DOWN seconds and
## thrown SWEEP_PUSH.
const SWEEP_STRIKE := 0.6
const SWEEP_DAMAGE := 22.0
const SWEEP_REACH := 3.0
const SWEEP_WIDTH := 3.6
const SWEEP_HIGH := 1.3
const SWEEP_DOWN := 1.4
const SWEEP_PUSH := 6.0
const SWEEP_COOLDOWN := 2.4

const THROW_WINDUP := 0.24
const THROW_SPEED := 46.0
const THROW_RANGE := 42.0
## How long it stays where it struck before it is pulled back.
const STUCK_TIME := 0.3
const RETURN_SPEED := 34.0
const BLAST_RADIUS := 4.5
const BLAST_DAMAGE := 100.0
## Seconds from one throw to the next, counted from the release.
const THROW_COOLDOWN := 10.0
const BLAST_PUSH := 15.0

## Chance each blow staggers what it hits (`player.knock`): the stab seldom,
## the lunge more often, the thrown spear's blast (the heavy attack) always.
const STAB_STAGGER := 0.1
const LUNGE_STAGGER := 0.4
const BLAST_STAGGER := 1.0

## From the hand to the point of the blade, and to the end of the butt: the
## model is fitted to these (tools/build_weapons.py, note 163); what a scene (`player.stab_at`, the haft strike)
## measures the spear by.
const TIP_REACH := 2.07
const BUTT_REACH := 0.67

## The pose the spear rests in, and where the hand holds it, head space.
const REST_AT := Vector3(0.27, -0.36, -0.28)
const AIM_FAR := Vector3(0.0, -0.05, -6.0)

enum Pose { REST, STAB, SWEEP, WINDUP, AWAY, CATCH, BACK }

var player: CharacterBody3D

var _model: Node3D
var _pose := Pose.REST
var _pose_t := 0.0
var _from := Transform3D()
var _raise := 0.0
## Stab timing runs on its own physics-step clock (`_stab_clock`), so the
## spacing is exactly STAB_EVERY in steps, not wall time jittered by frames.
var _stab_clock := 0.0
var _next_stab := 0.0
var _stab_queued := false
var _stab_hit := false
## The shoulder each stab is driven from, alternating (the player's view rolls
## to it -- `player._stab_effort`).
var stab_side := 1.0
## Which of COMBO comes next, the one playing (a PlayerMotion move), and when
## the combo is forgotten.
var _combo := 0
var _move := &""
var _combo_until := 0.0
var _lunged := false
var _sweep_ready_at := 0.0
var _swept := false
var _released := false
var _throw_ready_at := 0.0
## The thrown spear: null while in the hand.
var _flying: Node3D = null
var _fly_state := 0
var _fly_vel := Vector3.ZERO
var _fly_travelled := 0.0
var _stuck_until := 0.0
var _tether: MeshInstance3D
var _tether_mesh: ImmediateMesh

static var _mats := {}


## The workbench's level for the spear (player.gd `weapon_damage_scale`).
func _scale() -> float:
	if player != null and player.has_method("weapon_damage_scale"):
		return player.call("weapon_damage_scale", &"spear")
	return 1.0


func setup(p: CharacterBody3D) -> void:
	player = p
	name = "Spear"
	_model = _build_model(true)
	add_child(_model)
	transform = _rest()
	_model.visible = false
	_tether_mesh = ImmediateMesh.new()
	_tether = MeshInstance3D.new()
	_tether.name = "SpearTether"
	_tether.mesh = _tether_mesh
	_tether.material_override = _mat(&"tether")
	_tether.top_level = true
	_tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tether)
	get_tree().create_timer(0.5).timeout.connect(_warm_up)


## True while the spear is in the hand and free to be used.
func ready_in_hand() -> bool:
	return _flying == null and _pose != Pose.WINDUP and _pose != Pose.AWAY


func is_away() -> bool:
	return _flying != null or _pose == Pose.AWAY


## In the middle of something a guard must wait for: a stab, a dash, a throw's
## wind-up, or away in flight.
func busy() -> bool:
	return is_away() or _pose in [Pose.STAB, Pose.SWEEP, Pose.WINDUP]


## What every spear attack's time is multiplied by.
func time_scale() -> float:
	return player.attack_time_scale


## Whether the knight may hold it in its stance (note 171): in hand, and doing
## nothing posed of its own (the throw's wind-up, the catch, the step back).
func stance_ok() -> bool:
	return _flying == null and _pose in [Pose.REST, Pose.STAB, Pose.SWEEP]


## The clip the spear is playing, [move, pose seconds], or [] (player.gd
## `body_motion`: the body plays it too).
func motion() -> Array:
	if _pose == Pose.STAB and _move != &"":
		return [_move, _pose_t]
	if _pose == Pose.SWEEP:
		return [&"sweep", _pose_t]
	return []


## For the HUD's attack icons (`player.attack_cooldowns`): throw, sweep, stab as
## [kind, seconds left, of how long, key]; -1 while the spear is away (the stab
## and the sweep cannot be used until it is caught). These clocks run whatever is
## in hand, so putting the spear away does not reset them.
func attack_cooldowns() -> Array:
	var now := _now()
	var away := is_away()
	var stab := maxf(_next_stab - _stab_clock, 0.0)
	if _pose == Pose.SWEEP:
		stab = maxf(stab, (PlayerMotion.length(&"sweep") - _pose_t) * time_scale())
	return [
		[&"throw", maxf(_throw_ready_at - now, 0.0), THROW_COOLDOWN, "F"],
		[&"sweep", -1.0 if away else maxf(_sweep_ready_at - now, 0.0), SWEEP_COOLDOWN * time_scale(), "Q"],
		[&"stab", -1.0 if away else stab, STAB_EVERY * time_scale(), "LMB"],
	]


## The throw's cooldown, 0 just thrown -> 1 ready (the hotbar slot shows it).
func throw_charge() -> float:
	return clampf(1.0 - (_throw_ready_at - _now()) / THROW_COOLDOWN, 0.0, 1.0)


## Back in the hand at once, with no projectile in the air (a respawn).
func reset() -> void:
	if _flying != null and is_instance_valid(_flying):
		_flying.queue_free()
	_flying = null
	_pose = Pose.REST
	_pose_t = 0.0
	_combo = 0
	_move = &""
	_released = false
	_stab_queued = false
	# A respawn starts the throw fresh, as it does the sword's slam.
	_throw_ready_at = 0.0
	_tether_mesh.clear_surfaces()
	_tether.visible = false


# --- Keys -------------------------------------------------------------------------

func stab() -> void:
	if not ready_in_hand() or _pose == Pose.SWEEP:
		return
	if _stab_clock < _next_stab - 0.001:
		# Too soon: held, and fired on the beat (`_physics_process`).
		_stab_queued = true
		return
	_fire_stab()


func _fire_stab() -> void:
	_stab_queued = false
	# Left too long, the combo starts over.
	if _stab_clock > _combo_until:
		_combo = 0
	_move = COMBO[_combo]
	# From the step it fires on. A held click fires on the very step it falls
	# due, so held clicks come exactly on the beat -- and nothing, early or late,
	# ever comes sooner than that: two jabs STAB_EVERY apart, the lunge a hair
	# after (LUNGE_AFTER), then a breath (LUNGE_REST).
	var gap: float = STAB_EVERY
	if _combo == 1:
		gap = LUNGE_AFTER
	elif _combo == 2:
		gap = LUNGE_REST
	_next_stab = _stab_clock + gap * time_scale()
	_combo_until = _next_stab + COMBO_FORGET * time_scale()
	_combo = (_combo + 1) % COMBO.size()
	_begin(Pose.STAB)
	_stab_hit = false
	_lunged = false
	stab_side = -stab_side
	player.spear_stabbed()


## Seconds into the stab in progress, or -1 when not stabbing.
func stab_time() -> float:
	return _pose_t if _pose == Pose.STAB else -1.0


## Q: the delayed low sweep.
func sweep() -> void:
	var now := _now()
	if not ready_in_hand() or _pose == Pose.SWEEP or now < _sweep_ready_at:
		return
	_stab_queued = false
	_sweep_ready_at = now + SWEEP_COOLDOWN * time_scale()
	_swept = false
	_begin(Pose.SWEEP)


func throw() -> void:
	if not ready_in_hand() or _pose == Pose.SWEEP or _now() < _throw_ready_at:
		return
	_released = false
	_begin(Pose.WINDUP)


## A blow knocked them out of it (player.gd `_flinch`): the sweep's and the
## throw's wind-up stop where they are. A stab bites as it starts, so it plays out.
func interrupt() -> void:
	_stab_queued = false
	if _pose == Pose.WINDUP or (_pose == Pose.SWEEP and not _swept):
		_begin(Pose.BACK)


# --- Per frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	# A scene driving it (the cage stab, a haft strike: `player.spear_scene_pose`).
	var scene = player.spear_scene_pose()
	# Down too while a live rat hangs from the hand (rat_control.gd).
	var hands = player.get("rats")
	var held: bool = scene != null or (player.held_item() == &"spear" and not player.hands_busy \
		and not player.is_hidden() and not (hands != null and hands.get("holding") == true))
	# Raised into view when it is the slot in hand, lowered away otherwise.
	_raise = move_toward(_raise, 1.0 if held else 0.0, delta / 0.2)
	if scene != null:
		_raise = 1.0
	# The MODEL is hidden, not this node: the tether is a child, and a hidden
	# parent hides a top_level child too.
	_model.visible = _raise > 0.01 and _pose != Pose.AWAY
	_pose_t += delta / time_scale()
	var pose: Transform3D = scene if scene != null else _pose_transform()
	# The guard (`player._start_block`), eased by the player's own level.
	var g: float = player.guard_amount()
	if g > 0.0 and _pose in [Pose.REST, Pose.CATCH]:
		pose = pose.interpolate_with(_guard_pose(), g)
	var lowered := Transform3D(pose.basis, pose.origin + Vector3(0.05, -0.7, 0.25))
	var up: float = _raise * (1.0 - player.weapon_dip())
	transform = lowered.interpolate_with(pose, up * up * (3.0 - 2.0 * up))
	if _pose == Pose.WINDUP and not _released and _pose_t >= THROW_WINDUP:
		_release()
	_update_tether()


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_stab_clock += delta
	if _stab_queued:
		# The held click, fired on the beat -- if the spear is still in hand
		# and free (not blocking, drinking, ghosting...); otherwise forgotten.
		if player.held_item() != &"spear" or not player._spear_free() \
				or not ready_in_hand() or _pose == Pose.SWEEP:
			_stab_queued = false
		elif _stab_clock >= _next_stab - 0.001:
			_fire_stab()
	if _pose == Pose.STAB:
		var lunge := _move == &"lunge"
		if lunge and not _lunged and _pose_t >= LUNGE_OUT - 0.04:
			_lunged = true
			_lunge_step()
		if not _stab_hit and _pose_t >= (LUNGE_OUT if lunge else STAB_OUT):
			_stab_hit = true
			_stab_strike(lunge)
	if _pose == Pose.SWEEP and not _swept and _pose_t >= SWEEP_STRIKE:
		_swept = true
		_sweep_strike()
	if _flying != null:
		_update_flight(delta)


func _begin(pose: Pose) -> void:
	_from = transform if _raise > 0.5 else _rest()
	_pose = pose
	_pose_t = 0.0


# --- Poses ------------------------------------------------------------------------

func _aimed(at: Vector3, target: Vector3, roll := 0.0) -> Transform3D:
	var b := _facing(target - at)
	return Transform3D(b * Basis(Vector3.FORWARD, roll), at)


## -Z down `dir`; safe straight up or down, where looking_at with UP fails.
static func _facing(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.BACK
	return Basis.looking_at(dir, up)


## The player's script, for its `GUARD_DRAW`.
const PLAYER := preload("res://scripts/player.gd")


## The guard is the knight's left arm (first_person_arms.gd, note 157): the spear
## is only drawn back out of its way, still pointing ahead.
func _guard_pose() -> Transform3D:
	var rest := _rest()
	return Transform3D(rest.basis, rest.origin + PLAYER.GUARD_DRAW)


func _rest() -> Transform3D:
	# From the lower right corner up to just under and right of the crosshair,
	# so the blade is in plain view rather than hidden behind the reticle.
	return _aimed(REST_AT, Vector3(0.35, 0.05, -6.0), 0.25)


func _pose_transform() -> Transform3D:
	var t := _pose_t
	match _pose:
		Pose.STAB:
			if _move == &"" or t >= PlayerMotion.length(_move):
				_pose = Pose.REST
				_move = &""
				return _rest()
			return _motion_transform(_move, t)
		Pose.SWEEP:
			if t >= PlayerMotion.length(&"sweep"):
				_pose = Pose.REST
				return _rest()
			return _motion_transform(&"sweep", t)
		Pose.WINDUP:
			var drawn := _aimed(Vector3(0.36, -0.02, 0.22), Vector3(0.2, 1.4, -6.0), 0.3)
			var k := minf(t / THROW_WINDUP, 1.0)
			return _from.interpolate_with(drawn, 1.0 - (1.0 - k) * (1.0 - k))
		Pose.CATCH:
			var k := minf(t / 0.18, 1.0)
			var arriving := _aimed(Vector3(0.2, -0.3, -1.1), AIM_FAR, 0.0)
			if k >= 1.0:
				_pose = Pose.REST
			return arriving.interpolate_with(_rest(), 1.0 - (1.0 - k) * (1.0 - k))
		Pose.BACK:
			var k := minf(t / 0.18, 1.0)
			if k >= 1.0:
				_pose = Pose.REST
			return _from.interpolate_with(_rest(), k * k * (3.0 - 2.0 * k))
	return _rest()


## A clip move's spear (notes 167, 168): where the hand is asked to be -- the
## pose it began from, eased to rest. The clip itself is the knight's arm
## (coop_avatar.gd), and first_person_arms.gd blends to it by the move's weight
## and puts the spear in its fist, along the forearm; so this only matters at the
## move's two ends, where it blends.
func _motion_transform(kind: StringName, t: float) -> Transform3D:
	var k := clampf(t / maxf(float(PlayerMotion.move(kind)["in"]) * 2.0, 0.001), 0.0, 1.0)
	return _from.interpolate_with(_rest(), k * k * (3.0 - 2.0 * k))


# --- The stab and the sweep -------------------------------------------------------

## The lunge's step: the player carried forward with it (player.gd
## `begin_spear_dash`, which stone stops as it stops anything).
func _lunge_step() -> void:
	var forward := -player.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	var time := LUNGE_STEP_TIME * time_scale()
	player.begin_spear_dash(forward.normalized() * LUNGE_STEP / time, time)


func _stab_strike(lunge := false) -> void:
	var cam: Camera3D = player.camera
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	var reach := LUNGE_REACH if lunge else STAB_REACH
	var box := BoxShape3D.new()
	box.size = Vector3(STAB_WIDTH, STAB_WIDTH, reach)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(cam.global_basis, eye + fwd * reach * 0.5)
	q.collision_mask = player.hitbox.collision_mask
	q.exclude = [player.get_rid()]
	var struck := false
	for hit in player.get_world_3d().direct_space_state.intersect_shape(q, 16):
		var body := hit["collider"] as Node3D
		if body == null or not body.has_method("take_damage") or body.has_method("swat"):
			continue
		if player._is_blocked(eye, body):
			continue
		body.take_damage((LUNGE_DAMAGE if lunge else STAB_DAMAGE) * _scale(), fwd)
		player.knock(body, Vector3(fwd.x, 0.0, fwd.z).normalized() * (5.0 if lunge else 3.0), 0.1,
			LUNGE_STAGGER if lunge else STAB_STAGGER)
		player.hit_landed.emit(body)
		struck = true
		break
	var kick := (0.9 if struck else 0.6) if lunge else (0.6 if struck else 0.35)
	player.set("_swing_kick", maxf(float(player.get("_swing_kick")), kick))


## The sweep's blow: everything in the low arc in front, not behind stone, hurt
## and knocked down.
func _sweep_strike() -> void:
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var box := BoxShape3D.new()
	box.size = Vector3(SWEEP_WIDTH, SWEEP_HIGH, SWEEP_REACH)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	var basis := Basis.looking_at(fwd, Vector3.UP)
	q.transform = Transform3D(basis, player.global_position + Vector3(0.0, SWEEP_HIGH * 0.5, 0.0)
		+ fwd * SWEEP_REACH * 0.5)
	q.collision_mask = player.hitbox.collision_mask
	q.exclude = [player.get_rid()]
	var eye: Vector3 = player.camera.global_position
	var struck := false
	for hit in player.get_world_3d().direct_space_state.intersect_shape(q, 24):
		var body := hit["collider"] as Node3D
		if body == null or not body.has_method("take_damage") or body.has_method("swat"):
			continue
		if player._is_blocked(eye, body):
			continue
		var away := body.global_position - player.global_position
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 1e-4 else fwd
		body.take_damage(SWEEP_DAMAGE * _scale(), away)
		_knock_down(body, away)
		player.hit_landed.emit(body)
		struck = true
	player.set("_swing_kick", maxf(float(player.get("_swing_kick")), 1.0 if struck else 0.6))
	player.set("_shake", maxf(float(player.get("_shake")), 0.22 if struck else 0.08))


## Off its feet: the enemies with a fall of their own take it
## (`knock_down_from`: the decrepit's topple, the proels' throw onto the back);
## the rest are thrown and stunned for as long as a fall would take.
func _knock_down(body: Node3D, away: Vector3) -> void:
	if body.has_method("knock_down_from"):
		body.call("knock_down_from", away)
		player.staggered_enemy.emit(body)
		return
	player.knock(body, away * SWEEP_PUSH, SWEEP_DOWN, 1.0)


# --- The throw ------------------------------------------------------------------

func _release() -> void:
	_released = true
	_throw_ready_at = _now() + THROW_COOLDOWN
	_pose = Pose.AWAY
	var cam: Camera3D = player.camera
	var fwd := -cam.global_basis.z
	_flying = Node3D.new()
	_flying.name = "ThrownSpear"
	_flying.top_level = true
	player.get_parent().add_child(_flying)
	_flying.add_child(_build_model(false))
	_flying.global_position = cam.global_position + fwd * 0.6 + cam.global_basis.x * 0.2 - Vector3(0.0, 0.15, 0.0)
	_flying.global_basis = _facing(fwd)
	_fly_vel = fwd * THROW_SPEED
	_fly_travelled = 0.0
	_fly_state = 0
	player.set("_swing_kick", 1.0)
	# Thrown with the face against stone (or an enemy): it bursts right there
	# rather than starting its flight on the far side.
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, _flying.global_position,
		player.geometry_mask | 256 | player.hitbox.collision_mask)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_flying.global_position = cam.global_position
		_strike_at(hit["position"])


func _update_flight(delta: float) -> void:
	if not is_instance_valid(_flying):
		reset()
		return
	var space := player.get_world_3d().direct_space_state
	match _fly_state:
		0:
			# Out: straight down the line, until it strikes something or runs out.
			var from := _flying.global_position
			var step := _fly_vel * delta
			var q := PhysicsRayQueryParameters3D.create(from, from + step,
				player.geometry_mask | 256 | player.hitbox.collision_mask)
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				_flying.global_position = hit["position"] - _fly_vel.normalized() * 0.3
				_strike_at(hit["position"])
				return
			_flying.global_position = from + step
			_fly_travelled += step.length()
			_flying.rotate_object_local(Vector3.FORWARD, delta * 12.0)
			if _fly_travelled >= THROW_RANGE:
				_strike_at(_flying.global_position)
		1:
			# Stuck where it struck, quivering.
			if _now() >= _stuck_until:
				_fly_state = 2
			else:
				var q2 := sin(_now() * 90.0) * 0.012
				_flying.rotate_object_local(Vector3.RIGHT, q2)
		2:
			# Pulled back to the hand, butt first, faster and faster.
			var hand: Vector3 = _head().global_transform * REST_AT
			var to := hand - _flying.global_position
			var dist := to.length()
			var speed := minf(RETURN_SPEED, 8.0 + _fly_travelled * 3.0)
			_fly_travelled += delta * 6.0
			if dist <= speed * delta + 0.5:
				_caught()
				return
			var dir := to / dist
			_flying.global_position += dir * speed * delta
			_flying.global_basis = _facing(-dir)


func _strike_at(at: Vector3) -> void:
	_fly_state = 1
	_stuck_until = _now() + STUCK_TIME
	_fly_travelled = 0.0
	_explode(at)


func _caught() -> void:
	if is_instance_valid(_flying):
		_flying.queue_free()
	_flying = null
	_tether_mesh.clear_surfaces()
	_tether.visible = false
	_from = _aimed(Vector3(0.2, -0.3, -1.1), AIM_FAR, 0.0)
	_pose = Pose.CATCH
	_pose_t = 0.0
	player.set("_shake", maxf(float(player.get("_shake")), 0.12))


## A glowing line from the hand to the spear while it is away.
func _update_tether() -> void:
	_tether_mesh.clear_surfaces()
	if _flying == null or not is_instance_valid(_flying) or _fly_state == 0 and _fly_travelled < 1.0:
		_tether.visible = false
		return
	var cam := Coop.camera(player)
	if cam == null:
		return
	_tether.visible = true
	_tether.global_transform = Transform3D.IDENTITY
	var a: Vector3 = _head().global_transform * (REST_AT + Vector3(0.0, 0.0, -0.3))
	var b := _flying.global_transform * Vector3(0.0, 0.0, 0.75)
	var verts: Array = []
	var segments := 16
	for i in segments:
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var p0 := a.lerp(b, t0) + Vector3(0.0, sin(t0 * PI) * -0.25, 0.0)
		var p1 := a.lerp(b, t1) + Vector3(0.0, sin(t1 * PI) * -0.25, 0.0)
		var along := p1 - p0
		if along.length_squared() < 1e-8:
			continue
		var side := along.cross(cam.global_position - p0).normalized() * 0.02
		verts.append_array([p0 - side, p0 + side, p1 + side, p0 - side, p1 + side, p1 - side])
	if verts.is_empty():
		return
	_tether_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		_tether_mesh.surface_add_vertex(v)
	_tether_mesh.surface_end()


## The blast where the thrown spear strikes: everything damageable within
## `BLAST_RADIUS` that stone does not shelter takes `BLAST_DAMAGE` falling off to
## half at the edge and is thrown outward; anything with `swat()` is popped (nothing has one since the criers); the view
## shakes by how close the player is.
func _explode(at: Vector3) -> void:
	var space := player.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = BLAST_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = player.hitbox.collision_mask
	q.exclude = [player.get_rid()]
	var seen := {}
	for hit in space.intersect_shape(q, 32):
		var body := hit["collider"] as Node3D
		if body == null or seen.has(body):
			continue
		seen[body] = true
		var centre := body.global_position + Vector3(0.0, 0.9, 0.0)
		var ray := PhysicsRayQueryParameters3D.create(at, centre, player.geometry_mask)
		ray.exclude = [player.get_rid()]
		var wall := space.intersect_ray(ray)
		if not wall.is_empty() and (wall["position"] as Vector3).distance_to(at) > 0.4:
			continue
		var away := centre - at
		var dist := away.length()
		away = away / maxf(dist, 0.01)
		if body.has_method("swat"):
			body.swat(away)
			continue
		if not body.has_method("take_damage"):
			continue
		# Full damage within a metre -- the struck body's centre is ~0.9 m from
		# the point on its surface the spear hit -- falling to half at the edge.
		var falloff := 1.0 - 0.5 * clampf((dist - 1.0) / (BLAST_RADIUS - 1.0), 0.0, 1.0)
		body.take_damage(BLAST_DAMAGE * falloff * _scale(), away)
		player.knock(body, Vector3(away.x, 0.0, away.z).normalized() * BLAST_PUSH * falloff
			+ Vector3(0.0, 4.0, 0.0), 0.6, BLAST_STAGGER)
		if body.has_method("alert"):
			body.alert()
		player.hit_landed.emit(body)
	var near := player.global_position.distance_to(at)
	player.set("_shake", maxf(float(player.get("_shake")), clampf(1.0 - near / 25.0, 0.15, 0.9)))
	_blast_visual(at)


func _blast_visual(at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "SpearBlast"
	holder.top_level = true
	player.get_parent().add_child(holder)
	holder.global_position = at
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	ball.mesh = sphere
	ball.material_override = _fire_mat()
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * 0.3
	holder.add_child(ball)
	var flash := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(6.0, 6.0)
	flash.mesh = quad
	flash.material_override = _mat(&"flash")
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(flash)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = _mat(&"ring")
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3.ONE * 0.4
	holder.add_child(ring)
	var t := holder.create_tween().set_parallel(true)
	t.tween_property(ball, "scale", Vector3.ONE * BLAST_RADIUS * 0.7, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_method(func(v: float) -> void: ball.set_instance_shader_parameter(&"fade", v),
		0.0, 1.0, 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_property(flash, "transparency", 1.0, 0.18)
	t.tween_property(ring, "scale", Vector3(BLAST_RADIUS, 1.0, BLAST_RADIUS) * 1.1, 0.4).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "transparency", 1.0, 0.45)
	if Graphics.effects:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 10.0
		light.omni_range = 10.0
		light.shadow_enabled = false
		holder.add_child(light)
		t.tween_property(light, "light_energy", 0.0, 0.5)
		preload("res://scripts/door_debris.gd").dust(holder, at, Vector3.UP, 34, 1.4)
	t.chain().tween_interval(0.9)
	t.chain().tween_callback(holder.queue_free)


## The blast's and the tether's materials compiling on first use would stall
## that frame: draw a speck of each in front of the camera at load.
func _warm_up() -> void:
	var cam := Coop.camera(player)
	if cam == null:
		return
	for key in [&"fire", &"flash", &"ring", &"tether"]:
		var speck := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.002, 0.002)
		speck.mesh = quad
		speck.material_override = _fire_mat() if key == &"fire" else _mat(key)
		cam.add_child(speck)
		speck.position = Vector3(0.0, 0.0, -0.5)
		get_tree().create_timer(0.3).timeout.connect(speck.queue_free)
	var plain := _build_model(false)
	plain.scale = Vector3.ONE * 0.001
	cam.add_child(plain)
	plain.position = Vector3(0.0, 0.0, -0.5)
	get_tree().create_timer(0.3).timeout.connect(plain.queue_free)


# --- Materials and the model ------------------------------------------------------

static var _fire: ShaderMaterial


static func _fire_mat() -> ShaderMaterial:
	if _fire == null:
		_fire = ShaderMaterial.new()
		_fire.shader = load("res://shaders/spear_blast.gdshader")
	return _fire


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"fire", &"flash", &"ring", &"tether":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.no_depth_test = key == &"flash"
			match key:
				&"fire":
					m.albedo_color = Color(1.0, 0.5, 0.15, 0.8)
				&"flash":
					m.albedo_color = Color(1.0, 0.85, 0.55, 0.9)
					m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
					var grad := GradientTexture2D.new()
					grad.fill = GradientTexture2D.FILL_RADIAL
					grad.fill_from = Vector2(0.5, 0.5)
					grad.fill_to = Vector2(1.0, 0.5)
					var g := Gradient.new()
					g.set_color(0, Color(1, 1, 1, 1))
					g.set_color(1, Color(1, 1, 1, 0))
					grad.gradient = g
					m.albedo_texture = grad
				&"ring":
					m.albedo_color = Color(1.0, 0.7, 0.35, 0.7)
				&"tether":
					m.albedo_color = Color(1.0, 0.62, 0.25, 0.85)
	_mats[key] = m
	return m


## The user's spear (note 163), fitted by tools/build_weapons.py: along -Z, tip
## forward, the hand at the origin, the butt's end at +BUTT_REACH and the point
## at -TIP_REACH.
const MODEL := preload("res://models/spear.glb")

## Thrown, the head (socket and blade) glows like the tether, so it can be
## followed out and back: its materials, lit, made once.
static var _hot := {}


static func _hot_mat(source: BaseMaterial3D) -> BaseMaterial3D:
	if not _hot.has(source):
		var m := source.duplicate() as BaseMaterial3D
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.16)
		m.emission_energy_multiplier = 2.2
		_hot[source] = m
	return _hot[source]


## `in_hand` gives every surface the viewmodel's pulled-forward depth, as the
## sword has; out of the hand it is the thrown spear, its head alight.
func _build_model(in_hand: bool) -> Node3D:
	var root := MODEL.instantiate() as Node3D
	root.name = "SpearModel"
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if source == null:
				continue
			var mat := source
			if in_hand:
				mat = source.duplicate() as BaseMaterial3D
				mat.use_z_clip_scale = true
				mat.z_clip_scale = float(player.get("sword_draw_depth")) if player != null else 0.12
			elif source.resource_name in ["SpearSocket", "SpearBlade"]:
				mat = _hot_mat(source)
			mi.set_surface_override_material(i, mat)
	return root


func _head() -> Node3D:
	return get_parent() as Node3D


## The in-hand model's `z_clip_scale`: 1.0 for real depth while it is driven into
## something in a scene, so what it goes into hides the buried part.
func set_depth(scale: float) -> void:
	if _model == null:
		return
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(i) as BaseMaterial3D
			if mat != null and mat.use_z_clip_scale:
				mat.z_clip_scale = scale


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
