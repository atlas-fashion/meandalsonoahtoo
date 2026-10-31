extends "res://scripts/enemy.gd"

## The SCOUT (note 127): the user -- "Make this guy a new enemy, but make his
## eyes blue, like the enforcer. He should also roam the halls, looking for the
## player. He should be easier to kill than the enforcers. They should be called
## scouts. Scouts should have a spear dash, a tri stab attack, and a swipe that
## knocks the player down." And: "Make all animations very realistic."
##
## A hunched robot soldier in rusted riveted plate with a ragged mantle and a
## barbed spear (models/scout.glb, made in Blender by tools/build_scout.py;
## scout_body.gd: all its animation, procedural).
## 160 health (an enforcer has 240; 110 before note 129); its blows are
## lighter than an enforcer's.
##
## ROAMING: alone, always on patrol (patrol.gd: legs between corridor points,
## stops to look about, its own area, never through a shut door), stalking with
## its head turning, quick looks and holds. It sees in a 140 degree cone through
## no stone and hears anyone within HEAR_RANGE whichever way it faces.
##
## HUNTING: on first sight it starts (SPOT: up straight, the spear snatched up,
## a beat), then comes on along the navmesh -- fast, slowing as it closes. Close
## in it circles, keeping its distance, until an attack is ready:
##   * the TRI-STAB (close): three thrusts -- the shaft run through the front
##     hand each time -- the last a lunge with a step in. STAB_DAMAGE each.
##   * the SWIPE (close): wound back over its right side, the spear swept low
##     across the front at the legs with the hips leading. Unguarded, it
##     knocks the player down (`player.knock_down`).
##   * the SPEAR DASH (DASH_MIN..DASH_MAX off, a clear floor): crouched, the
##     spear couched, then a burst at them -- re-aimed as they move -- the point
##     arriving on them. DASH_DAMAGE.
## Every blow lands only where the spear's point (the swipe: its shaft) really
## passes through them, and each has a parry cue (player.gd `parry_cue`).
## A parry throws it back reeling, the spear knocked up; blocked blows shove.
##
## SEARCHING: losing sight of them, it goes to where they were last seen and
## looks about, then on the way they were going, twice, then back to its
## patrol. Making no headway at them (a shut door between: nothing but the
## player opens one, note 126) it gives up and searches where it stands.
##
## TUNED (note 129), the user: "a little more health, faster, attack faster.
## When the scout performs the 3 stab attack he should move swiftly forward
## with each stab. He should be able to close the gap between himself and the
## player. He should be able to chain 2 attacks together, but not all the time.
## He should attack and move smart, with the goal of killing the player."
##   * 160 health (still well under an enforcer's 240); faster on its feet and
##     turning; every move runs at TEMPO, shorter breaths between them.
##   * the tri-stab DRIVES at them: each stab's step is stretched, as it
##     starts, to bring the point onto them (STAB_DRIVE), so it covers 1-3 m
##     and is started from up to STAB_GAP off.
##   * CHAINS: at a move's chain point it may go straight into another (a
##     chained move never chains again), more often when they are down,
##     drinking or swinging.
##   * SMART (`_read_player`): it punishes an opening (knocked down, drinking,
##     a swing recovering) at once, aiming low at someone on the floor; it
##     steps back out of a swing coming at it; faced with a raised guard it
##     circles to their side before it strikes (a guard covers only the front);
##     it dashes more readily at someone backing away.

const ENF := preload("res://scripts/enforcer.gd")
const BODY := preload("res://scripts/scout_body.gd")

const HUNT_SPEED := 5.5
## Coming in the last few metres: measured, not a charge.
const CLOSE_SPEED := 3.2
## Patrolling (patrol.gd walks it at PACE 1.25 of this).
const STALK_SPEED := 1.5
const SEARCH_SPEED := 2.8
const CIRCLE_SPEED := 1.9
## How fast it turns, radians a second; in a move, onto its target.
const TURN_RATE := 9.5
const TURN_STRIKE := 11.0
## Every move's clock runs this much faster than real time (its wind-ups,
## blows and recoveries all shorter by the same share; note 129).
const TEMPO := 1.25
## Heard within this, whichever way it faces (with no stone between).
const HEAR_RANGE := 4.0

enum Move { NONE, SPOT, TRISTAB, DASH, SWIPE }
const MOVE_NAMES := [&"", &"spot", &"tristab", &"dash", &"swipe"]

const SPOT_END := 0.6

## The tri-stab: three hit windows (move seconds), a cue before each, the steps
## in it takes ([from, to, metres]).
const STAB_DAMAGE := [8.0, 8.0, 12.0]
const STAB_HITS := [[0.37, 0.52], [0.72, 0.86], [1.14, 1.38]]
const STAB_CUES := [0.18, 0.56, 0.92]
const STAB_LISTEN := 0.25
const STAB_END := 1.75
## Each stab's step in: [from, to, least metres, most metres]. Its length is
## set as the step starts: as far as brings the point STAB_OVER past their
## middle, never under the least, never over the most (note 129).
const STAB_DRIVE := [[0.26, 0.42, 0.25, 1.1], [0.62, 0.78, 0.25, 1.1], [1.0, 1.2, 0.45, 1.4]]
## The point reaches this far ahead of its body at a stab's full extension.
const STAB_POINT := 2.05
const STAB_OVER := 0.25
## Edge to edge, from which it opens with a tri-stab (it drives the rest).
const STAB_GAP := 3.4
## The point counts as in them within their radius and this.
const POINT_REACH := 0.14

const DASH_DAMAGE := 16.0
const DASH_WIND := 0.5
## The burst: up to DASH_TRAVEL in DASH_SLIDE, fastest at once (about 16 m/s
## at its longest -- a man sprinting at a lunge, not a projectile).
const DASH_SLIDE := 0.8
const DASH_HITS := [[0.85, 1.28]]
const DASH_CUES := [0.55]
const DASH_LISTEN := 0.35
const DASH_END := 1.7
## Centre to centre, from which it dashes.
const DASH_MIN := 5.0
const DASH_MAX := 9.5
## Where the slide stops (centre to centre): its point a little past them.
const DASH_ARRIVE := 1.25
const DASH_TRAVEL := 7.5
const DASH_COOLDOWN := 3.2
const DASH_CHANCE := 0.6
## At someone backing away.
const DASH_CHANCE_FLEEING := 0.9
const DASH_SHOVE := 4.0

const SWIPE_DAMAGE := 12.0
const SWIPE_HITS := [[0.6, 0.8]]
const SWIPE_CUES := [0.44]
const SWIPE_LISTEN := 0.26
const SWIPE_END := 1.45
const SWIPE_STEPS := [[0.56, 0.74, 0.3]]
const SWIPE_THROW := 7.0
const SWIPE_COOLDOWN := 2.4
const SWIPE_SHARE := 0.4
## The swept shaft counts within their radius and this.
const SHAFT_REACH := 0.12

## Edge to edge, inside which it uses its close moves.
const CLOSE_GAP := 1.9
const CLOSE_PAUSE := Vector2(0.2, 0.6)
## Chaining (move seconds at which it may go straight into another, the chance
## of it, and the chance when they are open).
const CHAIN_AT := {Move.TRISTAB: 1.42, Move.SWIPE: 1.02, Move.DASH: 1.32}
const CHAIN_CHANCE := 0.3
const CHAIN_CHANCE_OPEN := 0.75
## Stepping out of a swing coming at it: how often, how long, how fast.
const EVADE_CHANCE := 0.55
const EVADE_TIME := 0.32
const EVADE_SPEED := 4.2
## Circling round a raised guard to get at their side: for at most this long,
## then it strikes anyway. Their front: within this many degrees of their
## facing.
const FLANK_TIME := 1.6
const FLANK_SPEED := 2.8
const GUARD_FRONT := 60.0
const BLOCK_SHOVE := 3.5
## How long it searches at most, and the legs it walks doing it.
const SEARCH_TIME := 16.0
const SEARCH_LEGS := 3

var _body: BODY
var _state_proxy: MeshInstance3D
var _move := Move.NONE
var _move_t := 0.0
var _target: Node3D = null
var _windows: Array = []
var _cues: Array = []
var _end_at := 0.0
var _landed := {}
var _guard_seen := -1
var _close_ready := 0.0
var _dash_ready := 0.0
var _swipe_ready := 0.0
var _roll_at := 0.0
var _last_move := Move.NONE
var _slide_left := 0.0
var _slide_u := 0.0
var _prev_seg: Array = []
## Hunting someone (from the start of the chase to the end of the search).
var _hunting := false
var _last_seen := Vector3.ZERO
var _last_heading := Vector3.ZERO
var _search_until := 0.0
var _search_goal := Vector3.ZERO
var _search_phase := 0
var _search_look_until := 0.0
var _search_legs := 0
var _search_check_at := 0.0
var _search_from := Vector3.ZERO
var _progress_at := 0.0
var _progress_from := Vector3.ZERO
var _blind_until := 0.0
var _circle_sign := 1.0
var _circle_flip := 0.0
## Each stab's step length, decided as it starts (-1: not yet).
var _drive: Array[float] = [-1.0, -1.0, -1.0]
## This move was chained onto the last; whether its chain point was passed.
var _chained := false
var _chain_rolled := false
var _evade_until := 0.0
var _swing_ended_at := -10.0
var _swing_began := false
var _evade_dir := Vector3.ZERO
var _was_swinging := false
var _flank_until := -1.0
var chains := 0
var evades := 0
var flanks := 0
var _last_blow := Vector3.ZERO
## For the tests: how many of each move, how many blows landed.
var moves_made := {}
var blows_landed := 0


func _init() -> void:
	armed = false
	max_health = 160.0
	move_speed = HUNT_SPEED
	acceleration = 24.0
	vision_cone_degrees = 140.0
	sight_needs_line_of_sight = true
	sight_memory = 1.2
	eye_height = 1.62
	aggro_range = 32.0
	wanders = true
	wander_speed = STALK_SPEED
	can_slam = false
	can_spin = false
	can_lunge = false
	can_normal = false
	attack_damage = STAB_DAMAGE[0]
	knockback_resistance = 0.15
	tint_albedo = false
	base_glow = 0.0
	hit_punch = 0.0
	dormant_range = 48.0
	display_name = "SCOUT"
	drop_rolls_min = 1
	drop_rolls_max = 2
	drop_odds = {&"coins": 0.4, &"health_potion": 0.22, &"gold_crystal": 0.1}


func is_scout() -> bool:
	return true


# --- Scripted (note 128) ------------------------------------------------------------------
##
## A scene drives it (boss_abduction.gd: the two who carry the player to the
## boss): no AI, no patrol, no blows. It walks at `scripted_walk` (world, flat),
## turns to face `scripted_face` (a world point; null: the way it walks), looks
## at `scripted_look` (a world point, or null to look about), and plays the body
## move `scripted_move` (a scout_body.gd MOVES key) at `scripted_move_t`, which
## the scene advances, with the point pitched `scripted_pitch`.
var scripted := false
var scripted_walk := Vector3.ZERO
var scripted_face = null
var scripted_look = null
var scripted_move := &""
var scripted_move_t := 0.0
var scripted_pitch := 0.0


func _scripted_step(delta: float) -> void:
	_dormant = false
	engaged = false
	if not is_on_floor():
		velocity += get_gravity() * delta
	velocity.x = move_toward(velocity.x, scripted_walk.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, scripted_walk.z, acceleration * delta)
	if scripted_face != null:
		_face((scripted_face as Vector3) - global_position)
	elif scripted_walk.length_squared() > 0.01:
		_face(scripted_walk)
	move_and_slide()
	if _body == null:
		return
	var v := get_real_velocity()
	_body.velocity = Vector3(v.x, 0.0, v.z)
	_body.asleep = false
	_body.move = scripted_move
	_body.move_t = scripted_move_t
	_body.alert = 1.0
	_body.scanning = false
	_body.look_point = scripted_look
	_body.aim_pitch = scripted_pitch
	_body.lod_distance = 0.0
	_body.flare(0.0)


# --- The body ---------------------------------------------------------------------------

func _enter_tree() -> void:
	if _body != null:
		return
	var vis := get_node_or_null("Visual") as Node3D
	if vis == null:
		vis = Node3D.new()
		vis.name = "Visual"
		add_child(vis)
		move_child(vis, 0)
	for child in vis.get_children():
		vis.remove_child(child)
		child.free()
	_body = BODY.new()
	_body.name = "ScoutBody"
	vis.add_child(_body)
	# enemy.gd tints the material of its `mesh` by state; the scout keeps its own
	# colours (its eyes flare instead), so that machinery gets a proxy.
	_state_proxy = MeshInstance3D.new()
	_state_proxy.name = "StateProxy"
	_state_proxy.mesh = SphereMesh.new()
	_state_proxy.visible = false
	vis.add_child(_state_proxy)
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs != null:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.38
		cap.height = 1.8
		cs.shape = cap
		cs.position = Vector3(0.0, 0.9, 0.0)
	var ag := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if ag != null:
		ag.radius = 0.4
		ag.height = 1.8
		ag.path_desired_distance = 0.7


func _ready() -> void:
	_state_proxy.material_override = StandardMaterial3D.new()
	mesh = _state_proxy
	super()
	name = "Scout"
	# Not one of the skeletons: the shields guard and the crossbows hide behind
	# those (prosthetic.gd, archer.gd).
	remove_from_group(&"skeletons")
	add_to_group(&"scouts")
	_warm_sparks.call_deferred()
	_circle_sign = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	# Dead, it lies where it fell: enemy.gd would keep moving it under gravity,
	# and with its shape off that carried it down through the floor.
	if _dying:
		return
	if scripted:
		_scripted_step(delta)
		return
	var now := _now()
	_watch_swing(now)
	if _move != Move.NONE:
		if now < _stun_until:
			_end_move()
		elif _move != Move.SPOT and _swing_began and _target != null and is_instance_valid(_target) \
				and (_move_t < _first_blow() - 0.05 or _move_t > _last_blow_end()) and randf() < EVADE_CHANCE \
				and _target.global_position.distance_to(global_position) < 2.9:
			# Their swing comes in during its wind-up or its recovery: it breaks
			# off and steps out (between its blows it is committed).
			var to := _target.global_position - global_position
			_end_move()
			_close_ready = now
			_evade(Vector3(to.x, 0.0, to.z), now)
		else:
			if not is_on_floor():
				velocity += get_gravity() * delta
			_run_move(delta, now)
			_feed(now)
			return
	var was_hunting := _hunting and engaged
	super(delta)
	if _dying:
		return
	# Lost them: off to where they were last seen.
	if was_hunting and not engaged and _move == Move.NONE:
		if _retreating or _player_hidden():
			_hunting = false
		elif now >= _search_until:
			_begin_search(_last_seen, _last_heading, now)
	_feed(now)


func _player_hidden() -> bool:
	var p := _resolve_player()
	return p == null or Sandbox.enemies_passive or (p.has_method("is_hidden") and p.is_hidden())


## What the body needs to know this tick.
func _feed(now: float) -> void:
	if _body == null:
		return
	var v := get_real_velocity()
	_body.velocity = Vector3(v.x, 0.0, v.z)
	_body.asleep = _dormant
	_body.move = MOVE_NAMES[_move]
	_body.move_t = _move_t
	var player := _player
	var searching := now < _search_until
	var alert_to := 1.0 if (engaged or _move != Move.NONE) else (0.6 if searching else 0.0)
	_body.alert = alert_to
	_body.scanning = searching or (not engaged and Vector2(v.x, v.z).length() < 0.3)
	_body.look_point = null
	_body.aim_pitch = 0.0
	if player != null and is_instance_valid(player):
		_body.lod_distance = global_position.distance_to(player.global_position)
		if engaged or _move != Move.NONE:
			_body.look_point = player.global_position + Vector3(0.0, 1.45, 0.0)
		if _move != Move.NONE and _move != Move.SPOT:
			var to := player.global_position - global_position
			var d := Vector2(to.x, to.z).length()
			var down: bool = player.has_method("is_knocked_down") and player.call("is_knocked_down")
			var lift := (to.y + (0.35 if down else 1.0)) - 1.25
			# The swipe goes for the legs whatever their height.
			if _move != Move.SWIPE:
				_body.aim_pitch = clampf(atan2(lift, maxf(d, 0.5)), -0.35, 0.35)
	if _body.has_method("flare"):
		var first: float = float(_windows[0][0]) if not _windows.is_empty() else 0.0
		_body.flare(1.0 if _move != Move.NONE and _move != Move.SPOT and _move_t < first else 0.0)


## Turns toward `direction` at TURN_RATE, never snapping round.
func _face(direction: Vector3) -> void:
	if direction.length_squared() <= 0.001:
		return
	var want := atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(rotation.y, want, TURN_RATE * get_physics_process_delta_time())


func _can_see(player: Node3D, distance: float) -> bool:
	if _now() < _blind_until:
		return false
	if distance <= HEAR_RANGE and not (player.has_method("is_hidden") and player.is_hidden()):
		return _clear_to(player, 1.2)
	return super(player, distance)


# --- Hunting ------------------------------------------------------------------------------

func _chase(delta: float, now: float, player: Node3D, flat: Vector3, distance: float, gap: float) -> bool:
	if _seen_until >= now + sight_memory - 0.05:
		_last_seen = player.global_position
		var pv = player.get("velocity")
		if pv is Vector3 and Vector2((pv as Vector3).x, (pv as Vector3).z).length() > 0.5:
			_last_heading = Vector3((pv as Vector3).x, 0.0, (pv as Vector3).z).normalized()
	_search_until = 0.0
	if not _hunting:
		# Caught sight of them: a beat, the spear snatched up.
		_hunting = true
		_progress_at = now + 2.5
		_progress_from = global_position
		_start_move(Move.SPOT, player)
		_run_move(delta, now)
		return true
	# No headway at them (a shut door, bars between): it gives up on them.
	if gap > 2.5 and now >= _progress_at:
		if global_position.distance_to(_progress_from) < 0.5:
			_give_up(now)
			_hold(delta)
			return true
		_progress_at = now + 2.5
		_progress_from = global_position
	elif gap <= 2.5:
		_progress_at = now + 2.5
		_progress_from = global_position
	var dy := absf(player.global_position.y - global_position.y)
	# Reading them (note 129): a swing coming at it close in is stepped out of;
	# an opening is punished at once; a raised guard is circled.
	if _swing_began and gap < 2.3 and randf() < EVADE_CHANCE:
		_evade(flat, now)
	if now < _evade_until:
		velocity.x = move_toward(velocity.x, _evade_dir.x * EVADE_SPEED, acceleration * 2.0 * delta)
		velocity.z = move_toward(velocity.z, _evade_dir.z * EVADE_SPEED, acceleration * 2.0 * delta)
		_face(flat)
		_slide()
		# Straight back in as it lands.
		_close_ready = minf(_close_ready, _evade_until)
		return true
	if _opening(player, now):
		_close_ready = minf(_close_ready, now)
	var front := _guard_front(player)
	if front and _flank_until < 0.0:
		_flank_until = now + FLANK_TIME
		flanks += 1
	elif not front:
		_flank_until = -1.0
	var flanking := front and now < _flank_until
	var pick := Move.NONE
	if not flanking and now >= _close_ready and gap <= STAB_GAP and dy < 1.2 and _clear_to(player, 1.1):
		pick = _pick_close(now) if gap <= CLOSE_GAP else Move.TRISTAB
	elif not flanking and distance >= DASH_MIN and distance <= DASH_MAX and now >= _dash_ready \
			and now >= _roll_at and dy < 1.0:
		_roll_at = now + 0.4
		var chance := DASH_CHANCE_FLEEING if _fleeing(player) else DASH_CHANCE
		if randf() < chance and _clear_to(player, 1.0) and _clear_to(player, 0.4):
			pick = Move.DASH
	if pick != Move.NONE:
		_start_move(pick, player)
		_run_move(delta, now)
		return true
	var want := Vector3.ZERO
	if flanking and gap < 4.0:
		# Round to their side, where the guard does not cover.
		var r := -flat.normalized() if flat.length_squared() > 0.0001 else global_basis.z
		var pf := -player.global_basis.z
		var side := pf.z * r.x - pf.x * r.z
		var t := Vector3(r.z, 0.0, -r.x) * (1.0 if side >= 0.0 else -1.0)
		want = t * FLANK_SPEED + (-r) * clampf(gap - 1.7, -1.0, 1.0) * 1.5
		_face(flat)
	elif gap > CLOSE_GAP + 0.6 or (now >= _close_ready and gap > CLOSE_GAP * 0.8):
		var dir := _path_dir(now, player.global_position)
		var speed := HUNT_SPEED if gap > 4.0 else lerpf(CLOSE_SPEED, HUNT_SPEED, clampf((gap - 1.5) / 2.5, 0.0, 1.0))
		want = dir * speed
		_face(dir if gap > 4.0 else flat)
	else:
		# Waiting for its opening: circling them, keeping its distance.
		if now >= _circle_flip:
			if randf() < 0.55:
				_circle_sign = -_circle_sign
			_circle_flip = now + randf_range(1.0, 2.2)
		var n := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
		var tangent := Vector3(-n.z, 0.0, n.x) * _circle_sign
		var radial := n * clampf(gap - 1.6, -1.0, 1.0) * 1.5
		want = tangent * CIRCLE_SPEED + radial
		if want.length() > CIRCLE_SPEED * 1.4:
			want = want.normalized() * CIRCLE_SPEED * 1.4
		_face(flat)
	velocity.x = move_toward(velocity.x, want.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, want.z, acceleration * delta)
	_slide()
	if is_on_wall() and gap <= CLOSE_GAP + 0.6:
		_circle_sign = -_circle_sign
		_circle_flip = now + 1.2
	return true


## Steps back out of a swing, a little to one side, for EVADE_TIME.
func _evade(flat: Vector3, now: float) -> void:
	var away := -flat.normalized() if flat.length_squared() > 0.0001 else global_basis.z
	_evade_dir = (away + Vector3(-away.z, 0.0, away.x) * randf_range(-0.7, 0.7)).normalized()
	_evade_until = now + EVADE_TIME
	evades += 1


## Whether their swing began or ended this tick (`_swing_began`,
## `_swing_ended_at`), read once a tick before anything acts on it.
func _watch_swing(now: float) -> void:
	_swing_began = false
	var p := _player
	if p == null or not is_instance_valid(p):
		return
	var swinging: bool = p.get("_attacking") == true
	_swing_began = swinging and not _was_swinging
	if _was_swinging and not swinging:
		_swing_ended_at = now
	_was_swinging = swinging


## They are open: knocked down, drinking, or just finished a swing.
func _opening(player: Node3D, now: float) -> bool:
	if player.has_method("is_knocked_down") and player.call("is_knocked_down"):
		return true
	if player.has_method("is_drinking") and player.call("is_drinking"):
		return true
	return now - _swing_ended_at < 0.45


## Their guard is up and it is in front of them (where it covers).
func _guard_front(player: Node3D) -> bool:
	if not (player.has_method("is_blocking") and player.call("is_blocking")):
		return false
	var pf := -player.global_basis.z
	pf.y = 0.0
	var r := global_position - player.global_position
	r.y = 0.0
	if pf.length_squared() < 0.0001 or r.length_squared() < 0.0001:
		return false
	return rad_to_deg(pf.normalized().angle_to(r.normalized())) < GUARD_FRONT


## Backing away from it.
func _fleeing(player: Node3D) -> bool:
	var pv = player.get("velocity")
	if not (pv is Vector3):
		return false
	var r := player.global_position - global_position
	r.y = 0.0
	return r.length_squared() > 0.0001 and (pv as Vector3).dot(r.normalized()) > 1.5


func _pick_close(now: float) -> int:
	var swipe_ok := now >= _swipe_ready
	var share := SWIPE_SHARE * (0.4 if _last_move == Move.SWIPE else 1.0)
	if _last_move == Move.TRISTAB:
		share = minf(share * 1.5, 0.75)
	if swipe_ok and randf() < share:
		return Move.SWIPE
	return Move.TRISTAB


func _give_up(now: float) -> void:
	_blind_until = now + 5.0
	_seen_until = 0.0
	engaged = false
	_begin_search(global_position, _last_heading, now)
	_search_phase = 1
	_search_look_until = now + randf_range(1.8, 3.0)
	_look_centre = rotation.y
	_look_phase = 0.0


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


func _hold(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	_slide()


## A clear line through stone from its body to the player's, at `height`.
func _clear_to(player: Node3D, height: float) -> bool:
	var from := global_position + Vector3(0.0, height, 0.0)
	var to := player.global_position + Vector3(0.0, minf(height, 1.0), 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 2 | 256)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Searching ------------------------------------------------------------------------------

func _begin_search(at: Vector3, heading: Vector3, now: float) -> void:
	_search_until = now + SEARCH_TIME
	var map := get_world_3d().navigation_map
	_search_goal = NavigationServer3D.map_get_closest_point(map, at)
	_search_phase = 0
	_search_legs = 0
	_search_check_at = now + 2.0
	_search_from = global_position
	_last_heading = heading
	_next_repath = 0.0


func _wander(delta: float, now: float) -> Vector3:
	if now < _search_until:
		return _search_step(delta, now)
	if _hunting:
		_hunting = false
	return super(delta, now)


func _search_step(delta: float, now: float) -> Vector3:
	if _search_phase == 0:
		var to := _search_goal - global_position
		to.y = 0.0
		var stuck := false
		if now >= _search_check_at:
			stuck = global_position.distance_to(_search_from) < 0.4
			_search_check_at = now + 2.0
			_search_from = global_position
		if to.length() < 1.2 or stuck:
			_search_phase = 1
			_search_look_until = now + randf_range(1.6, 3.0)
			_look_centre = rotation.y
			_look_phase = 0.0
			return Vector3.ZERO
		var dir := _path_dir(now, _search_goal)
		_face(dir)
		return dir * SEARCH_SPEED
	# Stood, looking about: body turning slowly, the head quicker (the body's).
	_look_phase += delta * 1.1
	rotation.y = rotate_toward(rotation.y, _look_centre + sin(_look_phase) * 1.1, 2.5 * delta)
	if now < _search_look_until:
		return Vector3.ZERO
	_search_legs += 1
	if _search_legs >= SEARCH_LEGS:
		_search_until = 0.0
		_hunting = false
		return Vector3.ZERO
	# On a little, the way they were going (or anywhere, if that was not seen).
	var map := get_world_3d().navigation_map
	var shut: Array[Vector3] = []
	for d in get_tree().get_nodes_in_group(&"wood_doors"):
		if d.get("opened") != true:
			shut.append((d as Node3D).global_position)
	for tries in 8:
		var way := _last_heading
		if way.length_squared() < 0.01 or tries >= 4:
			var a := randf() * TAU
			way = Vector3(cos(a), 0.0, sin(a))
		way = way.rotated(Vector3.UP, randf_range(-0.8, 0.8))
		var p := NavigationServer3D.map_get_closest_point(map, global_position + way * randf_range(5.0, 9.0))
		if Vector2(p.x - global_position.x, p.z - global_position.z).length() < 3.0:
			continue
		var path := NavigationServer3D.map_get_path(map, global_position, p, true)
		if path.size() < 2 or preload("res://scripts/patrol.gd")._through_door(path, shut):
			continue
		_search_goal = p
		_search_phase = 0
		_search_check_at = now + 2.0
		_search_from = global_position
		_next_repath = 0.0
		return Vector3.ZERO
	_search_look_until = now + randf_range(1.0, 2.0)
	return Vector3.ZERO


# --- The moves -------------------------------------------------------------------------------

func _start_move(kind: int, player: Node3D, chained := false) -> void:
	_chained = chained
	_chain_rolled = false
	_drive = [-1.0, -1.0, -1.0]
	if chained:
		chains += 1
	_move = kind
	_move_t = 0.0
	_target = player
	_landed.clear()
	_prev_seg.clear()
	_windows.clear()
	_cues.clear()
	var now := _now()
	moves_made[MOVE_NAMES[kind]] = int(moves_made.get(MOVE_NAMES[kind], 0)) + 1
	match kind:
		Move.SPOT:
			_end_at = SPOT_END
		Move.TRISTAB:
			_windows = STAB_HITS.duplicate(true)
			_cues = STAB_CUES.duplicate()
			_end_at = STAB_END
		Move.DASH:
			_windows = DASH_HITS.duplicate(true)
			_cues = DASH_CUES.duplicate()
			_end_at = DASH_END
			_dash_ready = now + DASH_COOLDOWN
			_slide_left = 0.0
			_slide_u = 0.0
		Move.SWIPE:
			_windows = SWIPE_HITS.duplicate(true)
			_cues = SWIPE_CUES.duplicate()
			_end_at = SWIPE_END
			_swipe_ready = now + SWIPE_COOLDOWN
	if kind != Move.SPOT:
		_last_move = kind
	_link_guard(player)


func _end_move() -> void:
	_move = Move.NONE
	_move_t = 0.0
	_target = null
	_windows.clear()
	_cues.clear()
	_close_ready = _now() + randf_range(CLOSE_PAUSE.x, CLOSE_PAUSE.y)


func _run_move(delta: float, _now_t: float) -> void:
	var player := _target
	if player == null or not is_instance_valid(player):
		_end_move()
		return
	var prev := _move_t
	var tempo := _tempo()
	_move_t += delta * tempo
	var to := player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var gap := flat.length() - _body_radius - maxf(_target_radius, 0.3)
	var fwd := 0.0
	var turn := TURN_STRIKE
	var tracking := true
	match _move:
		Move.TRISTAB:
			fwd = minf(_drive_step(prev, flat.length()), maxf(gap - 0.25, 0.0))
			tracking = _tracking(0.05)
		Move.SWIPE:
			fwd = minf(_steps(SWIPE_STEPS, prev, _move_t), maxf(gap - 0.3, 0.0))
			tracking = _move_t < 0.52
		Move.DASH:
			fwd = _dash_step(flat)
			tracking = _move_t < DASH_WIND or _slide_u < 0.75
			turn = 10.0
		Move.SPOT:
			turn = 6.0
	if tracking and flat.length_squared() > 0.01:
		rotation.y = rotate_toward(rotation.y, atan2(-flat.x, -flat.z), turn * delta * tempo)
	var step := -global_basis.z * fwd
	velocity.x = step.x / delta
	velocity.z = step.z / delta
	_slide()
	velocity.x = 0.0
	velocity.z = 0.0
	for c in _cues:
		if prev < float(c) and _move_t >= float(c) and player.has_method("parry_cue"):
			var listen := STAB_LISTEN if _move == Move.TRISTAB else (DASH_LISTEN if _move == Move.DASH else SWIPE_LISTEN)
			player.call("parry_cue", self, listen)
	_tick_windows(prev, player)
	# Its chain point: now and then (not after a chain) straight into another.
	if _move != Move.NONE and not _chain_rolled and CHAIN_AT.has(_move) and _move_t >= float(CHAIN_AT[_move]):
		_chain_rolled = true
		if not _chained and engaged and _try_chain(player, flat.length()):
			return
	if _move != Move.NONE and _move_t >= _end_at:
		_end_move()


## At a chain point: straight into a second move if one fits where they are.
func _try_chain(player: Node3D, dist: float) -> bool:
	var now := _now()
	var chance := CHAIN_CHANCE_OPEN if _opening(player, now) else CHAIN_CHANCE
	if randf() >= chance or not _clear_to(player, 1.1):
		return false
	var gap := dist - _body_radius - maxf(_target_radius, 0.3)
	var next := Move.NONE
	if gap <= CLOSE_GAP:
		next = Move.SWIPE if (_move != Move.SWIPE and now >= _swipe_ready and randf() < 0.5) else Move.TRISTAB
	elif gap <= STAB_GAP:
		next = Move.TRISTAB
	elif dist >= DASH_MIN and dist <= DASH_MAX and now >= _dash_ready and _clear_to(player, 0.4):
		next = Move.DASH
	if next == Move.NONE:
		return false
	_start_move(next, player, true)
	return true


## A tri-stab's drive this tick: each stab's step, its length set as it begins
## to bring the point STAB_OVER past their middle (`dist` centre to centre).
func _drive_step(prev: float, dist: float) -> float:
	var out := 0.0
	for k in STAB_DRIVE.size():
		var d: Array = STAB_DRIVE[k]
		var t0 := float(d[0])
		var t1 := float(d[1])
		if _move_t < t0 or prev > t1:
			continue
		if _drive[k] < 0.0:
			_drive[k] = clampf(dist + STAB_OVER - STAB_POINT, float(d[2]), float(d[3]))
		var ua := clampf((prev - t0) / (t1 - t0), 0.0, 1.0)
		var ub := clampf((_move_t - t0) / (t1 - t0), 0.0, 1.0)
		out += _drive[k] * (_smooth(ub) - _smooth(ua))
	return out


## How fast the move's clock runs: TEMPO, but the swipe's sweep itself at
## 1x -- quickened, its front hand went past 20 m/s.
func _tempo() -> float:
	if _move == Move.SWIPE and _move_t >= 0.56 and _move_t <= 0.86:
		return 1.0
	return TEMPO


## When the move's last blow is over (move seconds), or 0.
func _last_blow_end() -> float:
	return float(_windows[-1][1]) if not _windows.is_empty() else 0.0


## When the move's first blow comes (move seconds), or its end.
func _first_blow() -> float:
	return float(_windows[0][0]) if not _windows.is_empty() else _end_at


## Still turning onto them: until `lead` seconds before the next blow.
func _tracking(lead: float) -> bool:
	for w in _windows:
		if _move_t < float(w[0]) - lead:
			return true
		if _move_t <= float(w[1]):
			return false
	return true


## The metres of the steps in a move between `a` and `b` (each step eased).
static func _steps(table: Array, a: float, b: float) -> float:
	var out := 0.0
	for s in table:
		var t0 := float(s[0])
		var t1 := float(s[1])
		var ua := clampf((a - t0) / (t1 - t0), 0.0, 1.0)
		var ub := clampf((b - t0) / (t1 - t0), 0.0, 1.0)
		out += float(s[2]) * (_smooth(ub) - _smooth(ua))
	return out


static func _smooth(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


## The dash: the wind-up standing; then the burst, its length fixed, fast at
## once and easing off as its point arrives, re-aimed on what is left.
func _dash_step(flat: Vector3) -> float:
	if _move_t < DASH_WIND:
		return 0.0
	var dist := flat.length()
	if _slide_u == 0.0 and _slide_left == 0.0:
		_slide_left = clampf(dist - DASH_ARRIVE, 0.0, DASH_TRAVEL)
	if _slide_u >= 1.0:
		return 0.0
	var u := minf((_move_t - DASH_WIND) / DASH_SLIDE, 1.0)
	var ea := sin(_slide_u * PI * 0.5)
	var eb := sin(u * PI * 0.5)
	_slide_u = maxf(u, 0.0001)
	var left := minf(_slide_left, maxf(dist - DASH_ARRIVE, 0.0))
	var fwd := left * (eb - ea) / maxf(1.0 - ea, 0.001)
	_slide_left = maxf(_slide_left - fwd, 0.0)
	return fwd


## Each open hit window tests the spear against them, and lands its blow the
## first tick it touches; once a window.
func _tick_windows(prev: float, player: Node3D) -> void:
	var seg := _spear_segment()
	for i in _windows.size():
		if _move == Move.NONE:
			break
		var w: Array = _windows[i]
		if _move_t < float(w[0]) or prev > float(w[1]) or _landed.has(i):
			continue
		if _touches(player, seg):
			_landed[i] = true
			_land(player, i)
	_prev_seg = seg


## What of the spear can strike now: the point's last 0.4 m, or, sweeping, the
## shaft from the front hand to the point. World.
func _spear_segment() -> Array:
	if _body == null:
		return []
	var back := 1.25 if _move == Move.SWIPE else 0.4
	return [_body.spear_point(back), _body.spear_tip()]


func _touches(player: Node3D, seg: Array) -> bool:
	if seg.is_empty():
		return false
	var r := _radius_of(player) + (SHAFT_REACH if _move == Move.SWIPE else POINT_REACH)
	var foot := player.global_position + Vector3(0.0, 0.1, 0.0)
	var head := player.global_position + Vector3(0.0, 1.75, 0.0)
	var segs: Array = [seg]
	# The swipe sweeps fast: between last tick's shaft and this one's too.
	if _move == Move.SWIPE and _prev_seg.size() == 2:
		for f in [0.33, 0.66]:
			segs.append([(_prev_seg[0] as Vector3).lerp(seg[0], f), (_prev_seg[1] as Vector3).lerp(seg[1], f)])
	for s in segs:
		var c := Geometry3D.get_closest_points_between_segments(s[0], s[1], foot, head)
		if c[0].distance_to(c[1]) <= r:
			return _clear_to(player, 1.0)
	return false


func _land(player: Node3D, index: int) -> void:
	var to := player.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var away := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	var damage := DASH_DAMAGE
	match _move:
		Move.TRISTAB:
			damage = STAB_DAMAGE[mini(index, STAB_DAMAGE.size() - 1)]
		Move.SWIPE:
			damage = SWIPE_DAMAGE
	var outcome := _strike(player, damage, flat)
	if outcome == &"miss" or outcome == &"parried":
		return
	blows_landed += 1
	if outcome == &"hit":
		if _move == Move.SWIPE and player.has_method("knock_down"):
			player.call("knock_down", away, SWIPE_THROW)
		elif _move == Move.DASH and player.has_method("apply_knockback"):
			player.call("apply_knockback", away * DASH_SHOVE)
	elif outcome == &"blocked" and player.has_method("apply_knockback"):
		player.call("apply_knockback", away * BLOCK_SHOVE)


## A blow through the player's own guard: &"hit", &"blocked", &"parried" or
## &"miss" (an invulnerable moment, a hiding place).
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


## Staggered (the player's roll, or a parry's shove): whatever it was doing is over.
func _on_staggered() -> void:
	if _move != Move.NONE:
		_end_move()


## The stagger, seen: knocked back reeling, the spear thrown up.
func _flinch(impulse: Vector3, time: float) -> void:
	if _body != null:
		_body.reel(impulse, time)


func _on_scared() -> void:
	if _move != Move.NONE:
		_end_move()


# --- Blows on it, death -------------------------------------------------------------------

func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	# In a scene (note 128): part of it, not a target.
	if scripted:
		return
	var was_dying := _dying
	if amount > 0.0 and _from_direction.length_squared() > 0.0001:
		_last_blow = _from_direction
	super(amount, _from_direction)
	if was_dying or amount <= 0.0:
		return
	_hit_sparks()
	if not _dying and _body != null:
		_body.hit(_from_direction, 0.4 + 0.6 * clampf(amount / 25.0, 0.0, 1.0))


## A white flash over the plating; no squash (the body's own reaction is the
## movement).
func _flash() -> void:
	if _body == null:
		return
	var flash := ENF._mat(&"flash")
	for gi in _body.parts():
		gi.material_overlay = flash
	get_tree().create_timer(0.08).timeout.connect(_unflash)


func _unflash() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	for gi in _body.parts():
		if is_instance_valid(gi):
			gi.material_overlay = null


func _die() -> void:
	_dying = true
	_move = Move.NONE
	_search_until = 0.0
	died.emit()
	shape.disabled = true
	_grant_drop()
	if _body != null:
		var dir := _last_blow if _last_blow.length_squared() > 0.0001 else global_basis.z
		_body.die(dir)
		_body.move = &""
	if Graphics.effects:
		_hit_sparks()
	var gone := create_tween()
	gone.tween_interval(4.2)
	gone.tween_property(self, "scale", Vector3(1.0, 0.01, 1.0), 0.45).set_ease(Tween.EASE_IN)
	gone.tween_callback(queue_free)


## The enforcer's spray of hot sparks off struck plating, toward the camera.
func _hit_sparks() -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	var base := global_position
	var cam := get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam != null else base + Vector3(0.0, 1.6, 2.0)
	var y := clampf(eye.y - 0.35, base.y + 0.7, base.y + 1.6)
	var out := Vector3(eye.x - base.x, 0.0, eye.z - base.z)
	out = out.normalized() if out.length_squared() > 0.0001 else -global_basis.z
	var at := Vector3(base.x, y, base.z) + out * 0.32
	var effects: bool = Graphics.effects
	var n := randi_range(ENF.HIT_SPARKS_MIN, ENF.HIT_SPARKS_MAX) if effects \
		else randi_range(ENF.HIT_SPARKS_PLAIN.x, ENF.HIT_SPARKS_PLAIN.y)
	var p := ENF._spark_burst(n)
	parent.add_child(p)
	p.global_position = at
	p.direction = (out + Vector3(0.0, 0.55, 0.0)).normalized()
	p.restart()
	get_tree().create_timer(ENF.HIT_SPARK_LIFE * 1.6 + 0.2).timeout.connect(p.queue_free)


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
