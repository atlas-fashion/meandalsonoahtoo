extends Node3D

## The axe (2026-10-20): the third weapon, held when the weapon-wheel slot in
## hand holds `&"axe"`. Lives under the player's Head as the first-person model
## and does its own fighting, as the spear does; `player.gd` only routes the
## keys to it (`slash`, `throw`, `berserk`), stops the body for the berserk roar
## and the throw's wind-up, and sets its pace (`player._axe_speed`): 25% slower
## with the axe in hand (`CARRY_SPEED`), faster while berserk.
##
## HEAVY (the user, 2026-10-20, note 87): "very heavy and cumbersome, but very
## strong".
## - SLASH (LMB, "attack"): a CHOP -- raised overhead over `SLASH_WIND` (the
##   delay before it lands), brought straight down in `SLASH_CUT`, 60 to the
##   ONE body nearest along a narrow strip down the crosshair
##   (`SLASH_HALF_WIDTH`), so it cannot sweep a crowd. One every `SLASH_EVERY`
##   0.75 s. A click that comes too soon is held and fired on the beat, as the
##   spear's stab. (Note 85's alternating side cuts are gone.)
## - THROW (Q, "thrust"): the player stops dead for `THROW_WINDUP` 0.5 s with
##   the axe drawn back over the shoulder, then hurls it down the crosshair,
##   end over end. What it strikes takes 60 and the axe STAYS IN IT for
##   `STICK_TIME` 2 s, riding along as it moves, then flies back to the
##   hand. If the blow kills it, or it dies while the axe is in it, there is
##   nothing to stay in: straight back. Stone, or nothing within `THROW_RANGE`,
##   sends it straight back too. Until it is caught the player has NO WEAPON:
##   no slash, no throw, no berserk, no guard, and the weapon wheel will not
##   change hands (`player.select_slot`).
## - BERSERK (F, "slam"): the player stops dead for `ROAR_TIME` (a shockwave
##   across the floor), then for `BERSERK_TIME` 7 s moves `BERSERK_SPEED`
##   faster, every axe attack takes half the time (`time_scale`), and health
##   comes back `BERSERK_HEAL` 7 a second (`_berserk_heal`). A red ring
##   burns on the floor round the feet, and the edges of the view glow red
##   (hud.gd `_update_berserk_glow`). `BERSERK_COOLDOWN` after it wears off.
##
## The model is built from primitives along +Y (the haft, hand at the origin)
## with the bearded head at the top, its edge toward -Z. In the hand it is drawn
## pulled toward the camera like the sword (`use_z_clip_scale`).

const SLASH_DAMAGE := 60.0
const SLASH_EVERY := 0.75
## The cut's timeline (before `time_scale`): drawn back, through, home.
const SLASH_WIND := 0.36
const SLASH_CUT := 0.1
const SLASH_BACK := 0.3
## Heavier (note 88). The last part of the wind-up is spent hanging at the top
## before the drop; a chop that lands bites, the swing held there for HIT_STOP;
## and the blow drags the view down after it (the landing dip, player.gd
## `_land_kick` / `_land_strength`), deeper on a hit.
const WIND_HANG := 0.22
const HIT_STOP := 0.07
const CHOP_DIP_HIT := 0.5
const CHOP_DIP_MISS := 0.28
## The chop's white streak, as the sword's (player.gd `_update_sweep_trail`):
## through the middle of the edge, sampled every TRAIL_STEP of the cut's
## progress, TRAIL_WIDTH times the sword's width. Its life, width and switch are
## the player's `sweep_trail_*`.
const TRAIL_AT := Vector3(0.0, 0.6, -0.205)
const TRAIL_STEP := 0.04
const TRAIL_WIDTH := 1.6
## Eye to the furthest the chop reaches, and half the width of the strip down
## the crosshair a body's centre must be in to be struck.
const SLASH_REACH := 2.6
const SLASH_HALF_WIDTH := 0.5
const SLASH_STAGGER := 0.6
## Walking pace with the axe in hand.
const CARRY_SPEED := 0.75

const THROW_DAMAGE := 60.0
const THROW_WINDUP := 0.5
const THROW_SPEED := 30.0
const THROW_RANGE := 30.0
## How long it stays in what it struck before it comes back.
const STICK_TIME := 2.0
const RETURN_SPEED := 30.0
## How near the flight a body has to pass to be struck: the head's reach.
const FLY_RADIUS := 0.35
const THROW_STAGGER := 1.0
## How far short of the struck collision shape the edge stops, so it shows
## against the model rather than inside it.
const STICK_PROUD := 0.3

const ROAR_TIME := 0.6
const BERSERK_TIME := 7.0
const BERSERK_SPEED := 1.5
## Health a second restored through the seven seconds (note 89), not the roar.
const BERSERK_HEAL := 7.0
## Every axe attack's time is multiplied by this while berserk: halved.
const BERSERK_ATTACK_SCALE := 0.5
## Seconds from the end of one berserk to the next being ready.
const BERSERK_COOLDOWN := 20.0
const GROUND_RADIUS := 1.6

## The pose the axe rests in, head space.
const REST_AT := Vector3(0.3, -0.42, -0.42)
## The point by the right shoulder the chop swings round, and how far out from
## it the hand is.
const SWING_PIVOT := Vector3(0.14, -0.1, -0.3)
const SWING_HAND := 0.3
## The chop's arc in its (near vertical) plane: from up and back over the head
## to down in front.
const SWING_FROM := deg_to_rad(-35.0)
const SWING_TO := deg_to_rad(150.0)
## Hand to the edge of the blade, along the haft: what the thrown axe buries.
const EDGE_AT := Vector3(0.0, 0.6, -0.2)
## The thrown axe turns about its balance point, this far up the haft.
const BALANCE := 0.4

enum Pose { REST, WIND, CUT, BACK, WINDUP, AWAY, CATCH }

var player: CharacterBody3D

var _model: Node3D
var _pose := Pose.REST
var _pose_t := 0.0
var _from := Transform3D()
var _raise := 0.0
var _clock := 0.0
var _next_slash := 0.0
var _slash_queued := false
var _slash_hit := false
var _released := false
## The thrown axe: null while in the hand.
var _flying: Node3D = null
## 0 out, 1 stuck in `_stuck_in`, 2 coming back.
var _fly_state := 0
var _fly_vel := Vector3.ZERO
var _fly_travelled := 0.0
## Bodies the flight passes through: the player, and anything already dying.
var _fly_exclude: Array[RID] = []
var _stuck_in: Node3D = null
var _stuck_local := Transform3D()
var _stuck_until := 0.0
var _roar_until := 0.0
var _berserk_until := 0.0
var _berserk_ready_at := 0.0
var _ground: MeshInstance3D
var _ground_light: OmniLight3D
## The swing is held (no `_pose_t`) until this, after a chop bites.
var _hold_until := 0.0
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
## [head-space point, time] newest first.
var _trail_pts: Array = []
var _trail_clock := 0.0
## How far through the cut the last sample was; -1 between cuts.
var _trail_k := -1.0

static var _mats := {}


## The workbench's level for the axe (player.gd `weapon_damage_scale`).
func _scale() -> float:
	if player != null and player.has_method("weapon_damage_scale"):
		return player.call("weapon_damage_scale", &"axe")
	return 1.0


func setup(p: CharacterBody3D) -> void:
	player = p
	name = "Axe"
	_model = _build_model(true)
	add_child(_model)
	transform = _rest()
	_model.visible = false
	_ground = MeshInstance3D.new()
	_ground.name = "BerserkGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GROUND_RADIUS * 2.0
	_ground.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/berserk_ground.gdshader")
	_ground.material_override = gm
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.top_level = true
	_ground.visible = false
	add_child(_ground)
	_trail_mesh = ImmediateMesh.new()
	_trail = MeshInstance3D.new()
	_trail.name = "AxeTrail"
	_trail.mesh = _trail_mesh
	# Top level: laid in world space each frame from the head-space samples.
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sweep = player.get("sweep_trail")
	if sweep is GeometryInstance3D and sweep.material_override != null:
		_trail.material_override = sweep.material_override
	else:
		_trail.material_override = _mat(&"trail")
	_trail.visible = false
	add_child(_trail)
	get_tree().create_timer(0.5).timeout.connect(_warm_up)


# --- State ------------------------------------------------------------------------

## True while the axe is in the hand and free to be used.
func ready_in_hand() -> bool:
	return _flying == null and _pose != Pose.WINDUP and _pose != Pose.AWAY


func is_away() -> bool:
	return _flying != null or _pose == Pose.AWAY


## In the middle of something a guard must wait for: a cut, a throw's wind-up,
## the roar, or away in flight.
func busy() -> bool:
	return is_away() or is_roaring() or _pose in [Pose.WIND, Pose.CUT, Pose.WINDUP]


## Drawn back for the throw: the player is held still meanwhile.
func is_winding_up() -> bool:
	return _pose == Pose.WINDUP and not _released


func is_roaring() -> bool:
	return _now() < _roar_until


func is_berserk() -> bool:
	return _now() < _berserk_until


## 0..1: how berserk, for the speed and the red at the edges of the view. Up
## over the roar, full for the seven seconds, easing off over the last half.
func berserk_amount() -> float:
	var now := _now()
	if now < _roar_until:
		return 1.0 - (_roar_until - now) / ROAR_TIME
	if now >= _berserk_until:
		return 0.0
	return clampf((_berserk_until - now) / 0.5, 0.0, 1.0)


## What every axe attack's time is multiplied by: half while berserk.
func time_scale() -> float:
	return BERSERK_ATTACK_SCALE if is_berserk() else 1.0


## For the HUD's attack icons (`player.attack_cooldowns`): berserk, throw, slash
## as [kind, seconds left, of how long, key]; -1 while the axe is away (nothing
## of it can be used until it is caught).
func attack_cooldowns() -> Array:
	var now := _now()
	var away := is_away()
	var slash := maxf(_next_slash - _clock, 0.0)
	var rage := maxf(_berserk_ready_at - now, 0.0)
	return [
		[&"berserk", -1.0 if away else rage, ROAR_TIME + BERSERK_TIME + BERSERK_COOLDOWN, "F"],
		[&"axe_throw", -1.0 if away else 0.0, 1.0, "Q"],
		[&"axe_slash", -1.0 if away else slash, SLASH_EVERY * time_scale(), "LMB"],
	]


## Back in the hand at once, nothing in the air, berserk over (a respawn).
func reset() -> void:
	if _flying != null and is_instance_valid(_flying):
		_flying.queue_free()
	_flying = null
	_stuck_in = null
	_pose = Pose.REST
	_pose_t = 0.0
	_released = false
	_slash_queued = false
	_roar_until = 0.0
	_berserk_until = 0.0
	_berserk_ready_at = 0.0
	_ground.visible = false
	if _ground_light != null:
		_ground_light.queue_free()
		_ground_light = null
	_hold_until = 0.0
	_trail_pts.clear()
	_trail_k = -1.0
	_trail.visible = false


# --- Keys -------------------------------------------------------------------------

func slash() -> void:
	if not ready_in_hand() or is_roaring():
		return
	if _clock < _next_slash - 0.001 or _pose in [Pose.WIND, Pose.CUT]:
		# Too soon: held, and fired on the beat (`_physics_process`).
		_slash_queued = true
		return
	_fire_slash()


func _fire_slash() -> void:
	_slash_queued = false
	_next_slash = _clock + SLASH_EVERY * time_scale()
	_slash_hit = false
	_begin(Pose.WIND)


func throw() -> void:
	if not ready_in_hand() or is_roaring() or _pose in [Pose.WIND, Pose.CUT]:
		return
	_released = false
	_slash_queued = false
	_begin(Pose.WINDUP)


func berserk() -> void:
	var now := _now()
	if not ready_in_hand() or is_roaring() or is_berserk() or now < _berserk_ready_at:
		return
	_slash_queued = false
	_roar_until = now + ROAR_TIME
	_berserk_until = _roar_until + BERSERK_TIME
	_berserk_ready_at = _berserk_until + BERSERK_COOLDOWN
	_begin(Pose.REST)
	player.set("_shake", maxf(float(player.get("_shake")), 0.5))
	_shockwave()
	_ground.visible = true
	if Graphics.effects:
		_ground_light = OmniLight3D.new()
		_ground_light.name = "BerserkLight"
		_ground_light.light_color = Color(1.0, 0.18, 0.08)
		_ground_light.light_energy = 0.0
		_ground_light.omni_range = 3.5
		_ground_light.shadow_enabled = false
		_ground_light.top_level = true
		add_child(_ground_light)


# --- Per frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	var hands = player.get("rats")
	var scene: bool = player.get("_pose_kind") in [&"haft", &"stab"]
	var held: bool = player.held_item() == &"axe" and not player.hands_busy and not scene \
		and not player.is_hidden() and not (hands != null and hands.get("holding") == true)
	_raise = move_toward(_raise, 1.0 if held else 0.0, delta / 0.2)
	_model.visible = _raise > 0.01 and _pose != Pose.AWAY
	if _now() >= _hold_until:
		_pose_t += delta / time_scale()
	var pose := _pose_transform()
	_update_trail(delta)
	var g: float = player.guard_amount()
	if g > 0.0 and _pose in [Pose.REST, Pose.CATCH]:
		pose = pose.interpolate_with(_guard_pose(), g)
	var lowered := Transform3D(pose.basis, pose.origin + Vector3(0.05, -0.7, 0.25))
	transform = lowered.interpolate_with(pose, _raise * _raise * (3.0 - 2.0 * _raise))
	if _pose == Pose.WINDUP and not _released and _pose_t >= THROW_WINDUP:
		_release()
	_update_ground(delta)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_clock += delta
	if _slash_queued:
		# The held click, fired on the beat -- if the axe is still in hand and
		# free; otherwise forgotten.
		if player.held_item() != &"axe" or not player._spear_free() or not ready_in_hand() \
				or is_roaring():
			_slash_queued = false
		elif _clock >= _next_slash - 0.001 and not (_pose in [Pose.WIND, Pose.CUT]):
			_fire_slash()
	# Struck partway through the cut -- or, if a long frame carried the pose
	# past the cut altogether, the moment it is seen to be past it.
	if not _slash_hit and (_pose == Pose.BACK or _pose == Pose.CUT and _pose_t >= SLASH_CUT * 0.45):
		_slash_hit = true
		_slash_strike()
	if _flying != null:
		_update_flight(delta)
	_berserk_heal(delta)


## Berserk heals BERSERK_HEAL a second, evenly, straight into health as a
## potion's drink does (player.gd `_update_drink`) -- no "healed" toast a frame.
func _berserk_heal(delta: float) -> void:
	if not is_berserk() or is_roaring() or player.get("_dead") == true:
		return
	var health: float = player.get("health")
	var top: float = player.get("max_health")
	if health >= top:
		return
	health = minf(health + BERSERK_HEAL * delta, top)
	player.set("health", health)
	player.health_changed.emit(health, top)


func _begin(pose: Pose) -> void:
	_from = transform if _raise > 0.5 else _rest()
	_pose = pose
	_pose_t = 0.0


# --- Poses ------------------------------------------------------------------------

## A pose with the haft along `up` from the hand at `at`, the edge toward `edge`.
static func _held(at: Vector3, up: Vector3, edge: Vector3) -> Transform3D:
	var y := up.normalized()
	var fwd := (edge - y * edge.dot(y)).normalized()
	var z := -fwd
	return Transform3D(Basis(y.cross(z), y, z), at)


func _rest() -> Transform3D:
	# Low on the right, the haft leaning up and away, the head turned to show
	# its profile with the edge toward the middle of the view.
	return _held(REST_AT, Vector3(0.1, 1.0, -0.55), Vector3(-1.0, 0.0, -0.4))


## The chop, `a` along its arc: the hand swung round SWING_PIVOT in a plane
## through straight up (leaning a touch right and back) and straight ahead, the
## haft pointing out from the pivot, the edge leading. Near vertical, so it
## comes down on one thing, not across several.
func _swing(a: float) -> Transform3D:
	var e1 := Vector3(0.12, 1.0, 0.3).normalized()
	var e2 := Vector3(0.0, -0.05, -1.0).normalized()
	var radial := e1 * cos(a) + e2 * sin(a)
	var tangent := -e1 * sin(a) + e2 * cos(a)
	return _held(SWING_PIVOT + radial * SWING_HAND, radial, tangent)


## The guard: the haft level across the face, the head off to the left.
func _guard_pose() -> Transform3D:
	var pose := _held(Vector3(0.28, -0.24, -0.5), Vector3(-1.0, 0.15, -0.1), Vector3(0.0, 1.0, -0.3))
	var kick: float = player.get("_guard_kick")
	if kick > 0.0:
		var k := kick * kick
		pose = Transform3D(Basis(Vector3.RIGHT, 0.15 * k) * pose.basis,
			pose.origin + Vector3(0.0, 0.05, -0.16) * k)
	return pose


func _pose_transform() -> Transform3D:
	var t := _pose_t
	match _pose:
		Pose.WIND:
			var k := minf(t / SLASH_WIND, 1.0)
			if k >= 1.0:
				_pose = Pose.CUT
				_pose_t = 0.0
			# Hauled up, then hung at the top for the last WIND_HANG of it.
			var up := minf(k / (1.0 - WIND_HANG), 1.0)
			return _from.interpolate_with(_swing(SWING_FROM), 1.0 - (1.0 - up) * (1.0 - up))
		Pose.CUT:
			var k := minf(t / SLASH_CUT, 1.0)
			if k >= 1.0:
				_from = _swing(SWING_TO)
				_pose = Pose.BACK
				_pose_t = 0.0
			return _swing(_cut_angle(k))
		Pose.BACK:
			var k := minf(t / SLASH_BACK, 1.0)
			if k >= 1.0:
				_pose = Pose.REST
			return _from.interpolate_with(_rest(), k * k * (3.0 - 2.0 * k))
		Pose.WINDUP:
			var drawn := _held(Vector3(0.38, 0.0, 0.12), Vector3(0.3, 0.6, 0.8), Vector3(0.0, 1.0, -0.2))
			var k := minf(t / THROW_WINDUP, 1.0)
			return _from.interpolate_with(drawn, 1.0 - (1.0 - k) * (1.0 - k))
		Pose.CATCH:
			var k := minf(t / 0.18, 1.0)
			if k >= 1.0:
				_pose = Pose.REST
			return _from.interpolate_with(_rest(), 1.0 - (1.0 - k) * (1.0 - k))
	return _rest()


## The chop's angle `k` (0..1) of the way through the cut.
static func _cut_angle(k: float) -> float:
	return lerpf(SWING_FROM, SWING_TO, k * k * (3.0 - 2.0 * k))


# --- The cut ----------------------------------------------------------------------

## The ONE damageable body nearest the eye whose centre is within
## SLASH_HALF_WIDTH of the crosshair's line (across, on the level) and
## SLASH_REACH along it, that stone does not shelter.
func _slash_strike() -> void:
	var cam: Camera3D = player.camera
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var sphere := SphereShape3D.new()
	sphere.radius = SLASH_REACH
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), eye)
	q.collision_mask = player.hitbox.collision_mask
	q.exclude = [player.get_rid()]
	var target: Node3D = null
	var nearest := INF
	for hit in player.get_world_3d().direct_space_state.intersect_shape(q, 32):
		var body := _damageable(hit["collider"])
		if body == null or body.has_method("swat") or _is_down(body):
			continue
		var to := body.global_position - eye
		var level := Vector3(to.x, 0.0, to.z)
		var along := level.dot(flat)
		var across := (level - flat * along).length()
		if along < -0.3 or along > SLASH_REACH or across > SLASH_HALF_WIDTH or along >= nearest:
			continue
		if player._is_blocked(eye, body):
			continue
		target = body
		nearest = along
	var struck := target != null
	if struck:
		target.take_damage(SLASH_DAMAGE * _scale(), fwd)
		if is_instance_valid(target):
			player.knock(target, flat * 5.0, 0.3, SLASH_STAGGER)
			player.hit_landed.emit(target)
	# Heavy: the whole view jolts as it lands, more on a hit.
	player.set("_swing_kick", maxf(float(player.get("_swing_kick")), 1.0 if struck else 0.6))
	player.set("_shake", maxf(float(player.get("_shake")), 0.3 if struck else 0.15))
	# ...and is dragged down after the blow, as by a landing.
	var dip := CHOP_DIP_HIT if struck else CHOP_DIP_MISS
	if float(player.get("_land_kick")) > 0.0:
		dip = maxf(dip, float(player.get("_land_strength")))
	player.set("_land_kick", 1.0)
	player.set("_land_strength", dip)
	if struck:
		# The edge bites: the swing held where it met the body.
		_hold_until = _now() + HIT_STOP * time_scale()


# --- The throw --------------------------------------------------------------------

func _release() -> void:
	_released = true
	_pose = Pose.AWAY
	var cam: Camera3D = player.camera
	var fwd := -cam.global_basis.z
	_flying = Node3D.new()
	_flying.name = "ThrownAxe"
	_flying.top_level = true
	player.get_parent().add_child(_flying)
	var model := _build_model(false)
	model.position = Vector3(0.0, -BALANCE, 0.0)
	_flying.add_child(model)
	_flying.global_position = cam.global_position + fwd * 0.7 + cam.global_basis.x * 0.2 - Vector3(0.0, 0.1, 0.0)
	_flying.global_basis = _held(Vector3.ZERO, cam.global_basis.y, fwd).basis
	_fly_vel = fwd * THROW_SPEED
	_fly_travelled = 0.0
	_fly_state = 0
	_stuck_in = null
	_fly_exclude = [player.get_rid()]
	player.set("_swing_kick", 1.0)
	# Thrown with the face against stone (or an enemy): it strikes right there
	# rather than starting its flight on the far side.
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, _flying.global_position,
		player.geometry_mask | 256 | player.hitbox.collision_mask)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_flying.global_position = cam.global_position
		_strike(hit)


func _update_flight(delta: float) -> void:
	if not is_instance_valid(_flying):
		reset()
		return
	match _fly_state:
		0:
			# Out: straight down the line, end over end, until it strikes
			# something or runs out.
			var from := _flying.global_position
			var step := _fly_vel * delta
			var q := PhysicsRayQueryParameters3D.create(from, from + step,
				player.geometry_mask | 256 | player.hitbox.collision_mask)
			q.exclude = _fly_exclude
			var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty():
				# Something already falling is flown straight through.
				var body := _damageable(hit["collider"])
				if body != null and _is_down(body) and hit["collider"] is CollisionObject3D:
					_fly_exclude.append((hit["collider"] as CollisionObject3D).get_rid())
					return
				if body != null:
					_strike(hit)
					return
			# The head is broad: a body within FLY_RADIUS of where the step ends
			# is struck too, so a target stepping aside is not missed by a hair.
			var reach: Vector3 = from + step if hit.is_empty() else hit["position"]
			var near := _body_near(reach)
			if not near.is_empty():
				_strike(near)
				return
			if not hit.is_empty():
				_strike(hit)
				return
			_flying.global_position = from + step
			_fly_travelled += step.length()
			_flying.rotate_object_local(Vector3.RIGHT, -delta * 20.0)
			if _fly_travelled >= THROW_RANGE:
				_come_back()
		1:
			# In what it struck, riding along with it -- until the time is up,
			# or there is nothing left to stay in.
			if _is_down(_stuck_in) or _now() >= _stuck_until:
				_come_back()
			else:
				_flying.global_transform = _stuck_in.global_transform * _stuck_local
		2:
			# Back to the hand, end over end.
			var hand: Vector3 = _head().global_transform * REST_AT
			var to := hand - _flying.global_position
			var dist := to.length()
			var speed := RETURN_SPEED
			if dist <= speed * delta + 0.5:
				_caught()
				return
			_flying.global_position += to / dist * speed * delta
			_flying.rotate_object_local(Vector3.RIGHT, delta * 20.0)


## The flight met `hit` (a ray result). Something that can be hurt takes the
## blow and keeps the axe for STICK_TIME, unless the blow killed it; stone
## sends it straight back.
func _strike(hit: Dictionary) -> void:
	var at: Vector3 = hit["position"]
	var body := _damageable(hit["collider"])
	var dir := _fly_vel.normalized()
	if body == null or body.has_method("swat") or _is_down(body):
		# Stone (or nothing worth staying in): straight back.
		_flying.global_position = at - dir * 0.3
		player.set("_shake", maxf(float(player.get("_shake")), 0.05))
		_come_back()
		return
	body.take_damage(THROW_DAMAGE * _scale(), dir)
	if not is_instance_valid(body):
		# Freed by the blow itself: nothing to knock or stay in.
		_flying.global_position = at - dir * 0.3
		_come_back()
		return
	player.knock(body, Vector3(dir.x, 0.0, dir.z).normalized() * 3.0, 0.3, THROW_STAGGER)
	if body.has_method("alert"):
		body.alert()
	player.hit_landed.emit(body)
	if _is_down(body):
		_flying.global_position = at - dir * 0.3
		_come_back()
		return
	# Edge first into the face it struck, the haft standing out from it up and
	# back toward the thrower. A little short of the ray's hit: the collision
	# shape sits inside the model, and buried at it the axe would be hidden.
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var b := _held(Vector3.ZERO, -flat + Vector3.UP * 1.2 + flat.cross(Vector3.UP) * 0.3, flat).basis
	var edge := at - flat * STICK_PROUD
	_flying.global_transform = Transform3D(b, edge - b * (EDGE_AT - Vector3(0.0, BALANCE, 0.0)))
	_stuck_in = body
	_stuck_local = body.global_transform.affine_inverse() * _flying.global_transform
	_stuck_until = _now() + STICK_TIME
	_fly_state = 1


func _come_back() -> void:
	_stuck_in = null
	_fly_state = 2


func _caught() -> void:
	if is_instance_valid(_flying):
		_flying.queue_free()
	_flying = null
	_stuck_in = null
	_from = _held(Vector3(0.2, -0.25, -0.9), Vector3(0.0, 1.0, -0.3), Vector3(-1.0, 0.0, 0.0))
	_pose = Pose.CATCH
	_pose_t = 0.0
	player.set("_shake", maxf(float(player.get("_shake")), 0.12))


## A live body within FLY_RADIUS of `at`, as a ray result ({position,
## collider}), or {} -- with stone between them, none.
func _body_near(at: Vector3) -> Dictionary:
	var sphere := SphereShape3D.new()
	sphere.radius = FLY_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = player.hitbox.collision_mask
	q.exclude = _fly_exclude
	var space := player.get_world_3d().direct_space_state
	for hit in space.intersect_shape(q, 8):
		var body := _damageable(hit["collider"])
		if body == null or body.has_method("swat") or _is_down(body):
			continue
		var ray := PhysicsRayQueryParameters3D.create(_flying.global_position, at, player.geometry_mask)
		ray.exclude = _fly_exclude
		if not space.intersect_ray(ray).is_empty():
			continue
		return {"position": at, "collider": hit["collider"]}
	return {}


## What a collider belongs to that can be hurt: itself or a parent close above.
static func _damageable(collider: Object) -> Node3D:
	var n := collider as Node
	for i in 3:
		if n == null:
			return null
		if n.has_method("take_damage"):
			return n as Node3D
		n = n.get_parent()
	return null


## Dead, dying or gone: nothing for the axe to stay in. Untyped on purpose: the
## body the axe is stuck in can be freed under it (a kill by someone else), and
## a freed object passed to a typed parameter is an error before the check runs.
static func _is_down(target) -> bool:
	if not is_instance_valid(target):
		return true
	var body := target as Node
	if body == null or body.is_queued_for_deletion() or not body.is_inside_tree():
		return true
	if body.get("_dying") == true or body.get("_dead") == true:
		return true
	var h = body.get("health")
	return h != null and float(h) <= 0.0


# --- The chop's streak ------------------------------------------------------------

## The white line the chop leaves, as the sword's slash does: a camera-facing
## ribbon through where the middle of the edge has been, thinning and fading
## with age. Sampled from the swing itself between frames (`_cut_angle`), as
## the sword's is -- the cut covers 185 degrees in 0.1 s, a third of it a frame,
## and chords between frame positions would cut inside the arc. Kept in the
## HEAD's frame, so the view's kick and dip do not leave it behind.
func _update_trail(delta: float) -> void:
	if not Graphics.effects or player.get("sweep_trail_enabled") == false:
		if _trail.visible:
			_trail.visible = false
		_trail_pts.clear()
		_trail_k = -1.0
		return
	var before := _trail_clock
	_trail_clock += delta
	var now := _trail_clock
	# How far through the cut the swing is: the cut itself, or its end if the
	# pose went past it this frame.
	var k := -1.0
	if _pose == Pose.CUT:
		k = minf(_pose_t / SLASH_CUT, 1.0)
	elif _pose == Pose.BACK and _trail_k >= 0.0 and _trail_k < 1.0:
		k = 1.0
	if k >= 0.0 and _model.visible:
		var from_k := _trail_k if _trail_k >= 0.0 and _trail_k <= k else 0.0
		var steps := maxi(1, ceili((k - from_k) / TRAIL_STEP))
		for i in range(1 if _trail_k >= 0.0 else 0, steps + 1):
			var f := float(i) / float(steps)
			_trail_pts.push_front([_swing(_cut_angle(lerpf(from_k, k, f))) * TRAIL_AT, lerpf(before, now, f)])
		_trail_k = k
	else:
		_trail_k = -1.0
	var life: float = player.get("sweep_trail_life")
	while not _trail_pts.is_empty() and now - float(_trail_pts.back()[1]) > life:
		_trail_pts.pop_back()
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		_trail.visible = false
		return
	_trail.global_transform = Transform3D.IDENTITY
	var to_world := _head().global_transform
	var eye: Vector3 = player.camera.global_position
	var width: float = float(player.get("sweep_trail_width")) * TRAIL_WIDTH
	var alpha: float = player.get("sweep_trail_alpha")
	# Gathered first: a surface begun with no vertices errors (player.gd).
	var verts: Array = []
	for i in _trail_pts.size() - 1:
		var p0: Vector3 = to_world * (_trail_pts[i][0] as Vector3)
		var p1: Vector3 = to_world * (_trail_pts[i + 1][0] as Vector3)
		var along := p1 - p0
		if along.length_squared() < 1e-8:
			continue
		var side := along.cross(eye - p0).normalized()
		var f0 := 1.0 - clampf((now - float(_trail_pts[i][1])) / life, 0.0, 1.0)
		var f1 := 1.0 - clampf((now - float(_trail_pts[i + 1][1])) / life, 0.0, 1.0)
		var w0 := side * width * f0
		var w1 := side * width * f1
		var c0 := Color(1.0, 1.0, 1.0, f0 * alpha)
		var c1 := Color(1.0, 1.0, 1.0, f1 * alpha)
		verts.append_array([[p0 - w0, c0], [p0 + w0, c0], [p1 + w1, c1], [p0 - w0, c0], [p1 + w1, c1], [p1 - w1, c1]])
	_trail.visible = not verts.is_empty()
	if verts.is_empty():
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		_trail_mesh.surface_set_color(v[1])
		_trail_mesh.surface_add_vertex(v[0])
	_trail_mesh.surface_end()


# --- Berserk's look ---------------------------------------------------------------

## The ring burning on the floor round the feet while berserk.
func _update_ground(_delta: float) -> void:
	var amount := berserk_amount()
	if amount <= 0.0 and not is_roaring():
		if _ground.visible:
			_ground.visible = false
		if _ground_light != null:
			_ground_light.queue_free()
			_ground_light = null
		return
	var feet: Vector3 = player.global_position
	_ground.global_position = feet + Vector3(0.0, 0.04, 0.0)
	(_ground.material_override as ShaderMaterial).set_shader_parameter(&"strength", amount)
	if _ground_light != null:
		_ground_light.global_position = feet + Vector3(0.0, 0.5, 0.0)
		_ground_light.light_energy = 1.6 * amount * (0.85 + 0.15 * sin(_now() * 9.0))


## The roar's shockwave: a red ring racing out across the floor from the feet.
func _shockwave() -> void:
	var ring := MeshInstance3D.new()
	ring.name = "BerserkShockwave"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = _mat(&"shock")
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true
	player.get_parent().add_child(ring)
	ring.global_position = player.global_position + Vector3(0.0, 0.08, 0.0)
	ring.scale = Vector3(0.3, 0.2, 0.3)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(7.0, 0.2, 7.0), ROAR_TIME).set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_CUBIC)
	t.tween_property(ring, "transparency", 1.0, ROAR_TIME).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(ring.queue_free)
	if Graphics.effects:
		preload("res://scripts/door_debris.gd").dust(ring, player.global_position, Vector3.UP, 24, 1.0)


## Materials compiling on first use would stall that frame: draw a speck of
## each (and the thrown model) in front of the camera at load.
func _warm_up() -> void:
	var cam := Coop.camera(player)
	if cam == null:
		return
	var specks: Array = [_mat(&"shock"), _ground.material_override]
	for mat in specks:
		var speck := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.002, 0.002)
		speck.mesh = quad
		speck.material_override = mat
		cam.add_child(speck)
		speck.position = Vector3(0.0, 0.0, -0.5)
		get_tree().create_timer(0.3).timeout.connect(speck.queue_free)
	var plain := _build_model(false)
	plain.scale = Vector3.ONE * 0.001
	cam.add_child(plain)
	plain.position = Vector3(0.0, 0.0, -0.5)
	get_tree().create_timer(0.3).timeout.connect(plain.queue_free)


# --- Materials and the model ------------------------------------------------------

static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"shock":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_color = Color(1.0, 0.15, 0.05, 0.85)
		&"trail":
			# Only if the player has no SweepTrail to borrow from: its settings.
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.vertex_color_use_as_albedo = true
			m.disable_receive_shadows = true
		&"wood":
			m.albedo_texture = load("res://textures/wood_door_albedo.png")
			m.albedo_color = Color(0.82, 0.66, 0.5)
			m.roughness = 0.8
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		&"iron":
			# Half metal, as the spear's: fully metallic rendered black here.
			m.albedo_color = Color(0.62, 0.63, 0.66)
			m.metallic = 0.4
			m.roughness = 0.38
		&"edge":
			m.albedo_color = Color(0.9, 0.91, 0.94)
			m.metallic = 0.4
			m.roughness = 0.2
		&"edge_lit":
			# Thrown, the edge glows faintly, so it can be followed out and back.
			m.albedo_color = Color(0.9, 0.91, 0.94)
			m.roughness = 0.2
			m.emission_enabled = true
			m.emission = Color(1.0, 0.35, 0.2)
			m.emission_energy_multiplier = 1.4
		&"leather":
			m.albedo_color = Color(0.2, 0.12, 0.07)
			m.roughness = 0.9
	_mats[key] = m
	return m


## The axe along +Y, the hand at the origin: an ash haft 0.8 m long with a
## leather grip and a knob at the end, iron straps under a bearded head whose
## edge faces -Z. `in_hand` gives every surface the viewmodel's pulled-forward
## depth, as the sword has.
func _build_model(in_hand: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "AxeModel"
	var parts: Array = []
	var haft := CylinderMesh.new()
	haft.top_radius = 0.019
	haft.bottom_radius = 0.023
	haft.height = 0.8
	haft.radial_segments = 8
	parts.append([haft, &"wood", Transform3D(Basis(), Vector3(0.0, 0.28, 0.0))])
	var knob := SphereMesh.new()
	knob.radius = 0.03
	knob.height = 0.05
	knob.radial_segments = 8
	knob.rings = 4
	parts.append([knob, &"iron", Transform3D(Basis(), Vector3(0.0, -0.12, 0.0))])
	var grip := CylinderMesh.new()
	grip.top_radius = 0.026
	grip.bottom_radius = 0.026
	grip.height = 0.2
	grip.radial_segments = 8
	parts.append([grip, &"leather", Transform3D(Basis(), Vector3(0.0, -0.01, 0.0))])
	for y: float in [0.46, 0.5]:
		var band := TorusMesh.new()
		band.inner_radius = 0.019
		band.outer_radius = 0.027
		band.rings = 10
		band.ring_segments = 5
		parts.append([band, &"iron", Transform3D(Basis(), Vector3(0.0, y, 0.0))])
	parts.append([_head_mesh(), &"iron", Transform3D()])
	parts.append([_edge_mesh(), &"edge" if in_hand else &"edge_lit", Transform3D()])
	for part in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		var mat: StandardMaterial3D = _mat(part[1])
		if in_hand:
			mat = mat.duplicate() as StandardMaterial3D
			mat.use_z_clip_scale = true
			mat.z_clip_scale = float(player.get("sword_draw_depth")) if player != null else 0.12
		mi.material_override = mat
		mi.transform = part[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## The head's outline in the haft's plane, (z, y): the eye round the haft, the
## upper horn, the curved edge, the long beard swept back to the haft, and a
## short poll behind.
const HEAD_OUTLINE := [
	Vector2(0.06, 0.66), Vector2(0.03, 0.68), Vector2(-0.04, 0.665), Vector2(-0.12, 0.70),
	Vector2(-0.175, 0.735), Vector2(-0.195, 0.69), Vector2(-0.205, 0.62), Vector2(-0.2, 0.55),
	Vector2(-0.185, 0.49), Vector2(-0.16, 0.445), Vector2(-0.12, 0.47), Vector2(-0.07, 0.52),
	Vector2(-0.035, 0.55), Vector2(0.03, 0.555), Vector2(0.06, 0.575),
]


## Half the head's thickness at `z`: fattest at the eye, thin toward the edge.
static func _thick(z: float) -> float:
	return lerpf(0.026, 0.006, clampf((-z - 0.02) / 0.17, 0.0, 1.0))


static func _head_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := PackedVector2Array(HEAD_OUTLINE)
	var tris := Geometry2D.triangulate_polygon(outline)
	var at := func(p: Vector2, side: float) -> Vector3: return Vector3(side * _thick(p.x), p.y, p.x)
	for i in range(0, tris.size(), 3):
		var a: Vector2 = outline[tris[i]]
		var b: Vector2 = outline[tris[i + 1]]
		var c: Vector2 = outline[tris[i + 2]]
		# Both faces, wound to face outward.
		st.add_vertex(at.call(a, 1.0))
		st.add_vertex(at.call(c, 1.0))
		st.add_vertex(at.call(b, 1.0))
		st.add_vertex(at.call(a, -1.0))
		st.add_vertex(at.call(b, -1.0))
		st.add_vertex(at.call(c, -1.0))
	var n := outline.size()
	for i in n:
		var p: Vector2 = outline[i]
		var q: Vector2 = outline[(i + 1) % n]
		st.add_vertex(at.call(p, 1.0))
		st.add_vertex(at.call(q, 1.0))
		st.add_vertex(at.call(q, -1.0))
		st.add_vertex(at.call(p, 1.0))
		st.add_vertex(at.call(q, -1.0))
		st.add_vertex(at.call(p, -1.0))
	st.generate_normals()
	return st.commit()


## The bright bevel along the cutting edge: a thin strip just proud of the head
## from the horn to the beard.
static func _edge_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge: Array = HEAD_OUTLINE.slice(4, 10)
	for side: float in [1.0, -1.0]:
		for i in edge.size() - 1:
			var p: Vector2 = edge[i]
			var q: Vector2 = edge[i + 1]
			var pi := Vector2(p.x + 0.03, p.y)
			var qi := Vector2(q.x + 0.03, q.y)
			var v := func(u: Vector2) -> Vector3: return Vector3(side * (_thick(u.x) + 0.0015), u.y, u.x)
			if side > 0.0:
				st.add_vertex(v.call(p))
				st.add_vertex(v.call(qi))
				st.add_vertex(v.call(q))
				st.add_vertex(v.call(p))
				st.add_vertex(v.call(pi))
				st.add_vertex(v.call(qi))
			else:
				st.add_vertex(v.call(p))
				st.add_vertex(v.call(q))
				st.add_vertex(v.call(qi))
				st.add_vertex(v.call(p))
				st.add_vertex(v.call(qi))
				st.add_vertex(v.call(pi))
	st.generate_normals()
	return st.commit()


func _head() -> Node3D:
	return get_parent() as Node3D


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
