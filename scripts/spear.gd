extends Node3D

## The spear (2026-10-08): the second weapon, held when the hotbar slot in hand
## holds `&"spear"`. Lives under the player's Head as the first-person model
## and does all of its own fighting; `player.gd` only routes the keys to it
## (`stab`, `dash`, `throw`) and moves the body for the dash
## (`player.begin_spear_dash`).
##
## - STAB (left click, "attack"): a quick jab straight down the crosshair, 10
##   damage, a new one every `STAB_EVERY` s -- spammable, just.
## - DASH (Q, "thrust"): the player charges forward with the spear braced,
##   `DASH_SPEED` for `DASH_TIME`, running through everything in the way
##   (`DASH_DAMAGE` and a shove to the side, once each), with the lunge's speed
##   lines. `DASH_COOLDOWN` between dashes.
## - THROW (F, "slam"), once every `THROW_COOLDOWN` 10 s: drawn back over the shoulder and hurled down the
##   crosshair. Whatever it hits -- or `THROW_RANGE` out if it hits nothing --
##   it EXPLODES (`_explode`: `BLAST_DAMAGE` falling off to half at
##   `BLAST_RADIUS`, thrown outward, behind stone spared), then it is pulled back
##   to the hand along a glowing tether, butt first. Nothing else can be done
##   with the spear until it is caught.
##
## The model is built from primitives (an ash shaft, a leaf blade, an iron socket
## and butt spike, leather bindings) along -Z, tip forward. In the hand it is
## drawn pulled toward the camera like the sword (`use_z_clip_scale`); the
## thrown one is an ordinary copy.

const STAB_DAMAGE := 10.0
## Four jabs a second, evenly: out in 60 ms, home by 0.21 s, a beat at rest.
## A click that comes too soon is not dropped but held (`_stab_queued`) and
## fired the moment the next jab is due, so spam-clicking gives a steady
## rhythm instead of one that depends on when each click happened to land.
const STAB_EVERY := 0.25
const STAB_OUT := 0.06
const STAB_BACK := 0.21
## Eye to the furthest a stab reaches, and how wide it is.
const STAB_REACH := 2.7
const STAB_WIDTH := 0.45

const DASH_SPEED := 17.0
const DASH_TIME := 0.32
const DASH_DAMAGE := 25.0
const DASH_SHOVE := 9.0
const DASH_COOLDOWN := 1.4

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
## the dash and the thrown spear's blast (the heavy attack) always.
const STAB_STAGGER := 0.1
const DASH_STAGGER := 1.0
const BLAST_STAGGER := 1.0

## From the hand to the point of the blade (socket at 1.55, blade 0.52), and to
## the end of the butt spike: what a scene (`player.stab_at`, the haft strike)
## measures the spear by.
const TIP_REACH := 2.07
const BUTT_REACH := 0.67

## The pose the spear rests in, and where the hand holds it, head space.
const REST_AT := Vector3(0.27, -0.36, -0.28)
const AIM_FAR := Vector3(0.0, -0.05, -6.0)

enum Pose { REST, STAB, DASH, WINDUP, AWAY, CATCH }

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
var _dash_ready_at := 0.0
var _dash_until := 0.0
var _dash_hit := {}
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
	return is_away() or _pose in [Pose.STAB, Pose.DASH, Pose.WINDUP]


func dash_charge() -> float:
	return clampf(1.0 - (_dash_ready_at - _now()) / DASH_COOLDOWN, 0.0, 1.0)


## For the HUD's attack icons (`player.attack_cooldowns`): throw, dash, stab as
## [kind, seconds left, of how long, key]; -1 while the spear is away (the stab
## and the dash cannot be used until it is caught). These clocks run whatever is
## in hand, so putting the spear away does not reset them.
func attack_cooldowns() -> Array:
	var now := _now()
	var away := is_away()
	var stab := maxf(_next_stab - _stab_clock, 0.0)
	if _pose == Pose.DASH:
		stab = maxf(stab, _dash_until - now)
	return [
		[&"throw", maxf(_throw_ready_at - now, 0.0), THROW_COOLDOWN, "F"],
		[&"dash", -1.0 if away else maxf(_dash_ready_at - now, 0.0), DASH_COOLDOWN, "Q"],
		[&"stab", -1.0 if away else stab, STAB_EVERY, "LMB"],
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
	_dash_until = 0.0
	_released = false
	_stab_queued = false
	# A respawn starts the throw fresh, as it does the sword's slam.
	_throw_ready_at = 0.0
	_tether_mesh.clear_surfaces()
	_tether.visible = false


# --- Keys -------------------------------------------------------------------------

func stab() -> void:
	if not ready_in_hand() or _pose == Pose.DASH:
		return
	if _stab_clock < _next_stab - 0.001:
		# Too soon: held, and fired on the beat (`_physics_process`).
		_stab_queued = true
		return
	_fire_stab()


func _fire_stab() -> void:
	_stab_queued = false
	# From the step it fires on. A held click fires on the very step it falls
	# due, so held clicks come exactly STAB_EVERY apart -- and nothing, early
	# or late, ever comes sooner than that.
	_next_stab = _stab_clock + STAB_EVERY
	_begin(Pose.STAB)
	_stab_hit = false
	stab_side = -stab_side
	player.spear_stabbed()


## Seconds into the stab in progress, or -1 when not stabbing.
func stab_time() -> float:
	return _pose_t if _pose == Pose.STAB else -1.0


func dash() -> void:
	var now := _now()
	if not ready_in_hand() or _pose == Pose.DASH or now < _dash_ready_at:
		return
	var forward := -player.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	_dash_ready_at = now + DASH_COOLDOWN
	_dash_until = now + DASH_TIME
	_dash_hit.clear()
	_begin(Pose.DASH)
	player.begin_spear_dash(forward.normalized() * DASH_SPEED, DASH_TIME)


func throw() -> void:
	if not ready_in_hand() or _pose == Pose.DASH or _now() < _throw_ready_at:
		return
	_released = false
	_begin(Pose.WINDUP)


# --- Per frame --------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null:
		return
	# A scene driving it (the cage stab, a haft strike: `player.spear_scene_pose`).
	var scene = player.spear_scene_pose()
	var held: bool = scene != null or (player.held_item() == &"spear" and not player.hands_busy \
		and not player.is_hidden())
	# Raised into view when it is the slot in hand, lowered away otherwise.
	_raise = move_toward(_raise, 1.0 if held else 0.0, delta / 0.2)
	if scene != null:
		_raise = 1.0
	# The MODEL is hidden, not this node: the tether is a child, and a hidden
	# parent hides a top_level child too.
	_model.visible = _raise > 0.01 and _pose != Pose.AWAY
	_pose_t += delta
	var pose: Transform3D = scene if scene != null else _pose_transform()
	# The guard (`player._start_block`), eased by the player's own level.
	var g: float = player.guard_amount()
	if g > 0.0 and _pose in [Pose.REST, Pose.CATCH]:
		pose = pose.interpolate_with(_guard_pose(), g)
	var lowered := Transform3D(pose.basis, pose.origin + Vector3(0.05, -0.7, 0.25))
	transform = lowered.interpolate_with(pose, _raise * _raise * (3.0 - 2.0 * _raise))
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
				or not ready_in_hand() or _pose == Pose.DASH:
			_stab_queued = false
		elif _stab_clock >= _next_stab - 0.001:
			_fire_stab()
	if _pose == Pose.STAB and not _stab_hit and _pose_t >= STAB_OUT * 0.6:
		_stab_hit = true
		_stab_strike()
	if _pose == Pose.DASH:
		if _now() < _dash_until:
			_dash_strike()
		else:
			_begin(Pose.REST)
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


## The guard: the spear brought up level across the body, the middle of the
## haft -- where the crystal and the shield will sit -- square in front of the
## face, the blade off to the left. A blow taken knocks it forward and up
## (`player._guard_kick`), as it does the sword. PLACEHOLDER until the haft's
## shield and its animation exist.
const GUARD_CENTRE := Vector3(0.0, -0.2, -0.62)
const GUARD_ALONG := Vector3(-1.0, 0.22, -0.12)
## The middle of the haft, measured along the model from the hand.
const HAFT_MIDDLE := 0.66


func _guard_pose() -> Transform3D:
	var dir := GUARD_ALONG.normalized()
	var hand := GUARD_CENTRE - dir * HAFT_MIDDLE
	var pose := _aimed(hand, hand + dir * 6.0, PI * 0.5)
	var kick: float = player.get("_guard_kick")
	if kick > 0.0:
		var k := kick * kick
		pose = Transform3D(Basis(Vector3.RIGHT, 0.15 * k) * pose.basis,
			pose.origin + Vector3(0.0, 0.05, -0.16) * k)
	return pose


func _rest() -> Transform3D:
	# From the lower right corner up to just under and right of the crosshair,
	# so the blade is in plain view rather than hidden behind the reticle.
	return _aimed(REST_AT, Vector3(0.35, 0.05, -6.0), 0.25)


func _pose_transform() -> Transform3D:
	var t := _pose_t
	match _pose:
		Pose.STAB:
			var out := _aimed(Vector3(0.14, -0.26, -0.95), AIM_FAR, 0.1)
			if t < STAB_OUT:
				var k := t / STAB_OUT
				return _from.interpolate_with(out, 1.0 - (1.0 - k) * (1.0 - k))
			if t < STAB_BACK:
				var k := (t - STAB_OUT) / (STAB_BACK - STAB_OUT)
				return out.interpolate_with(_rest(), k * k * (3.0 - 2.0 * k))
			_pose = Pose.REST
			return _rest()
		Pose.DASH:
			var braced := _aimed(Vector3(0.16, -0.3, -0.6), AIM_FAR, 0.05)
			return _from.interpolate_with(braced, minf(t / 0.08, 1.0))
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
	return _rest()


# --- The stab and the dash --------------------------------------------------------

func _stab_strike() -> void:
	var cam: Camera3D = player.camera
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	var box := BoxShape3D.new()
	box.size = Vector3(STAB_WIDTH, STAB_WIDTH, STAB_REACH)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(cam.global_basis, eye + fwd * STAB_REACH * 0.5)
	q.collision_mask = player.hitbox.collision_mask
	q.exclude = [player.get_rid()]
	var struck := false
	for hit in player.get_world_3d().direct_space_state.intersect_shape(q, 16):
		var body := hit["collider"] as Node3D
		if body == null or not body.has_method("take_damage") or body.has_method("swat"):
			continue
		if player._is_blocked(eye, body):
			continue
		body.take_damage(STAB_DAMAGE * _scale(), fwd)
		player.knock(body, Vector3(fwd.x, 0.0, fwd.z).normalized() * 3.0, 0.1, STAB_STAGGER)
		player.hit_landed.emit(body)
		struck = true
		break
	player.set("_swing_kick", maxf(float(player.get("_swing_kick")), 0.6 if struck else 0.35))


func _dash_strike() -> void:
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), player.global_position + Vector3(0.0, 1.0, 0.0) + fwd * 0.9)
	q.collision_mask = player.hitbox.collision_mask
	q.exclude = [player.get_rid()]
	for hit in player.get_world_3d().direct_space_state.intersect_shape(q, 16):
		var body := hit["collider"] as Node3D
		if body == null or _dash_hit.has(body) or not body.has_method("take_damage") or body.has_method("swat"):
			continue
		_dash_hit[body] = true
		body.take_damage(DASH_DAMAGE * _scale(), fwd)
		# Thrown aside, off the line of the charge.
		var side := player.global_basis.x
		var to := body.global_position - player.global_position
		side = side if to.dot(side) >= 0.0 else -side
		player.knock(body, (side + fwd * 0.6).normalized() * DASH_SHOVE, 0.5, DASH_STAGGER)
		player.hit_landed.emit(body)
		player.set("_shake", maxf(float(player.get("_shake")), 0.25))


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
	var cam := get_viewport().get_camera_3d()
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
## half at the edge and is thrown outward; a bomber is popped (`swat`); the view
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
	var cam := get_viewport().get_camera_3d()
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
		&"wood":
			m.albedo_texture = load("res://textures/wood_door_albedo.png")
			m.albedo_color = Color(1.0, 0.86, 0.66)
			m.roughness = 0.8
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
		&"iron":
			# Bright and only half metal: fully metallic, with nothing in these
			# halls to reflect, it rendered black.
			m.albedo_color = Color(0.78, 0.79, 0.82)
			m.metallic = 0.4
			m.roughness = 0.32
		&"iron_hot":
			m.albedo_color = Color(0.5, 0.4, 0.34)
			m.roughness = 0.4
			m.emission_enabled = true
			m.emission = Color(1.0, 0.5, 0.16)
			m.emission_energy_multiplier = 2.2
		&"leather":
			m.albedo_color = Color(0.2, 0.12, 0.07)
			m.roughness = 0.9
	_mats[key] = m
	return m


## The spear along -Z, tip forward: the hand holds it at the origin, 0.55 m up
## the shaft from the butt. `in_hand` gives every surface the viewmodel's
## pulled-forward depth, as the sword has.
func _build_model(in_hand: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "SpearModel"
	var parts: Array = []
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.019
	shaft.bottom_radius = 0.022
	shaft.height = 2.0
	shaft.radial_segments = 8
	parts.append([shaft, &"wood", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -0.45))])
	var socket := CylinderMesh.new()
	socket.top_radius = 0.016
	socket.bottom_radius = 0.026
	socket.height = 0.14
	socket.radial_segments = 8
	parts.append([socket, &"iron", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, -1.49))])
	var butt := CylinderMesh.new()
	butt.top_radius = 0.024
	butt.bottom_radius = 0.004
	butt.height = 0.12
	butt.radial_segments = 8
	parts.append([butt, &"iron", Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0, 0.61))])
	for z: float in [-1.36, -1.32, -0.05, 0.05]:
		var band := TorusMesh.new()
		band.inner_radius = 0.02
		band.outer_radius = 0.028
		band.rings = 10
		band.ring_segments = 5
		parts.append([band, &"leather", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, z))])
	# Thrown, the head glows like the tether, so it can be followed out and back.
	parts.append([_blade_mesh(), &"iron" if in_hand else &"iron_hot", Transform3D(Basis(), Vector3(0.0, 0.0, -1.55))])
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


## A leaf-shaped blade with a raised midrib: diamond cross-sections lofted from
## the socket to the point, along -Z.
static func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := 0.52
	var stations := 9
	var rings: Array = []
	for i in stations:
		var t := float(i) / float(stations - 1)
		# Swells to its widest a third of the way up, then draws to a point.
		var w := 0.024 + 0.07 * sin(PI * clampf(t / 0.9, 0.0, 1.0) * 0.85) * (1.0 - t * 0.45)
		if i == stations - 1:
			w = 0.0
		var th := maxf(w * 0.22, 0.003) if i < stations - 1 else 0.0
		var z := -t * length
		rings.append([Vector3(-w, 0.0, z), Vector3(0.0, th, z), Vector3(w, 0.0, z), Vector3(0.0, -th, z)])
	for i in stations - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for k in 4:
			var k2 := (k + 1) % 4
			st.add_vertex(a[k])
			st.add_vertex(b[k])
			st.add_vertex(b[k2])
			st.add_vertex(a[k])
			st.add_vertex(b[k2])
			st.add_vertex(a[k2])
	st.generate_normals()
	return st.commit()


func _head() -> Node3D:
	return get_parent() as Node3D


## The in-hand model's `z_clip_scale`: 1.0 for real depth while it is driven into
## something in a scene, so what it goes into hides the buried part.
func set_depth(scale: float) -> void:
	if _model == null:
		return
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mat := (node as MeshInstance3D).material_override as BaseMaterial3D
		if mat != null and mat.use_z_clip_scale:
			mat.z_clip_scale = scale


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
