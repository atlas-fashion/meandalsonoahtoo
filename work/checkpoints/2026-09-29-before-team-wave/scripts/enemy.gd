extends CharacterBody3D

## A fast, aggressive chaser that attacks by committing to one of several moves
## rather than draining health just for standing near you. The cycle is:
##
##   CHASE -> WINDUP (telegraph) -> ATTACK -> RECOVER -> CHASE
##
## The wind-up and the recovery are the same length whichever attack is chosen,
## so the tell always reads the same and the rhythm stays learnable. Only the
## ATTACK state deals damage, once per attack, so every move can be dodged.
##
## Sits on collision layer 3 ("damageable") as well as 1, because layer 3 is the
## only one the sword and dash scan.

signal died
## Raised when a scripted call for help completes, with which one it was.
signal summoned(index: int)

enum State { CHASE, WINDUP, ATTACK, RECOVER, STAGGER, SUMMON }
enum Attack { SLAM, SPIN, LUNGE, NORMAL }

@export var max_health := 100.0

@export_group("Movement")
## Deliberately above the player's move_speed (5.0).
@export var move_speed := 7.5
@export var acceleration := 22.0
## Gap between the two bodies' edges at which it stops closing, rather than
## grinding into the player. Not a centre-to-centre distance.
@export var stop_distance := 0.5
## Chases from anywhere on this map. Lower it if you want enemies to idle until
## noticed. Measured centre to centre.
@export var aggro_range := 60.0
## When above 0, the enemy guards its spawn: it will not chase a player who has
## gone further than this from where it spawned, and walks back if it strays.
@export var leash_radius := 0.0
## When non-zero, replaces the radial leash with a box around the spawn point
## (X and Z half-extents). A room is a rectangle, so a radius either misses its
## corners or spills into the corridors outside its doors -- a box is exactly
## the room. The enemy wakes when the player is inside it and walks back to the
## centre when they leave.
@export var aggro_box_extents := Vector3.ZERO

@export_group("Senses")
## Total width of the enemy's vision, in degrees, centred on the way it is
## facing. 0 means it has no front at all and notices you from any angle --
## which is what the boss wants, since his whole room is his business.
@export var vision_cone_degrees := 0.0
## Walls block sight. Without this an enemy notices you through a corner.
@export var sight_needs_line_of_sight := false
## Layer the sight ray tests against: level geometry only, so one enemy never
## blocks another's view.
@export_flags_3d_physics var sight_blocking_mask := 2
## How long it keeps hunting after losing sight of you. Without a memory it
## drops you the instant you round a corner, which reads as broken rather than
## as evasion.
@export var sight_memory := 4.5
## Height the eyes sit at, for the sight ray.
@export var eye_height := 1.5

@export_group("Wandering")
## Ambles around near where it spawned while it has not seen you, stopping to
## look about. An enemy standing perfectly still until aggro reads as scenery.
@export var wanders := false
## Deliberately much slower than the chase: an idle shuffle, not a patrol.
@export var wander_speed := 1.1
## How far from its spawn it will stray, in metres. Also the fallback range
## when no explicit wander area was handed to it.
@export var wander_radius := 9.0
@export var wander_pause_min := 1.1
@export var wander_pause_max := 3.4
## How fast it turns while stopped and looking about, in degrees per second.
@export var look_around_speed := 62.0
## How far it turns to either side while looking about.
@export var look_around_degrees := 85.0

@export_group("Attacks")
## Gap at which it commits to an attack, edge to edge.
@export var attack_trigger_range := 5.5
## Telegraph before any attack fires. Identical for all three.
@export var windup_time := 0.45
## Pause after any attack, whether or not it connected. Identical for all three.
@export var recover_time := 0.7
## Enforced gap between attacks, timed from the moment one ends. Runs alongside
## the recovery, so the real wait is whichever is longer.
@export var attack_cooldown := 0.0
@export var attack_damage := 14.0
## What the HUD shows if this one gets a boss bar.
@export var display_name := "THE WARDEN"
## An attack only lands if the player's feet are within this of the enemy's.
## Otherwise a ground enemy could hit someone standing on top of a pillar.
@export var max_height_difference := 1.5
## Which moves this enemy can roll. Basic enemies only slam.
@export var can_slam := true
@export var can_spin := false
@export var can_lunge := false
## A plain swing with whatever it has for hands.
##
## An enemy with one alone has a real problem: a charge only lands while it is
## genuinely charging, so once it is already up against you its attack fires
## and connects with nothing. Giving it a close-range move it can actually
## throw is what fixes that -- the charge then becomes how it closes the gap,
## not how it deals damage.
@export var can_normal := false

## A charging attack only connects while it is genuinely charging: it must be
## moving at this fraction of its attack speed. Without it, an enemy that is
## already touching you lands the hit the instant the move starts, which reads
## as being damaged by contact rather than by a dash.
@export_range(0.0, 1.0) var dash_connect_speed := 0.5

@export_subgroup("Normal")
## Gap at which it can reach you without moving, edge to edge. Inside this it
## swings; outside, it charges to get here.
@export var normal_range := 1.4
@export var normal_duration := 0.32
## Its own cooldown, separate from the charge's. Nothing in the interface shows
## either -- an enemy's timers are for the player to learn by watching, not to
## read off a bar.
@export var normal_cooldown := 3.0

@export_subgroup("Slam")
## A short committed step forward, bringing the weapon down in front.
@export var slam_speed := 18.0
@export var slam_duration := 0.45
## Gap at which the slam connects, edge to edge.
@export var slam_range := 0.7
## 0 falls back to attack_cooldown, which is what the boss wants.
@export var slam_cooldown := 0.0

@export_subgroup("Spin")
## Whirls on the spot, catching anything all the way around it.
@export var spin_duration := 1.1
@export var spin_range := 3.0
@export var spin_turns := 3.0
## 0 falls back to attack_cooldown.
@export var spin_cooldown := 0.0

@export_subgroup("Lunge")
## A long committed dash that crosses most of the arena.
@export var lunge_speed := 26.0
@export var lunge_duration := 1.1
@export var lunge_range := 1.0
## 0 falls back to attack_cooldown.
@export var lunge_cooldown := 0.0

@export_group("Summoning")
## Health values at which it breaks off, walks back to the middle of its room
## and calls for help. Each one fires once, in order.
@export var summon_at: Array[float] = []
## How long the weapon is held up. This is the whole tell: long enough to read
## as deliberate, and long enough to punish him for it.
@export var summon_time := 1.9
## How close to the middle it needs to get before it will start.
@export var summon_arrive := 2.5
## Worn while calling. Distinct from the attack colours, since nothing is
## about to hit you.
@export var summon_color := Color(0.619608, 0.450980, 1.0)
@export var summon_glow := 2.6
## Flashed when a hit is turned aside, and how far the body flares doing it.
## Swelling rather than squashing is what separates "blocked" from "hurt".
@export var deflect_color := Color(0.807843, 0.741176, 1.0)
@export_range(0.0, 0.5) var deflect_punch := 0.14

@export_group("Poise")
## Total poise. Leave at 0 to disable the whole system, which is what a basic
## enemy wants: no armour, interrupted by every hit, as before.
##
## Above 0 the enemy gains hyper-armour -- hits no longer break its rhythm --
## and the only way to stop it is to break the stance instead.
@export var max_poise := 0.0
## Poise damage per point of health damage. Proportional by design, so nothing
## needs balancing twice: whatever chews through health fastest breaks the
## stance fastest, and chip damage barely dents it.
@export var poise_damage_ratio := 1.0
## How long the stun lasts if the weak point is never struck.
@export var stagger_time := 4.0
## Poise recovered per second, once it has been left alone long enough.
##
## Keep this well under the rate the player can actually land hits. Regen is
## only meant to wipe the slate between fights, not to compete with a fight in
## progress: set too high, every dodge window gives back a whole sword hit and
## the bar visibly resets instead of ever filling.
@export var poise_regen := 6.0
## Quiet time required after the last hit before poise starts coming back. Long
## enough that ordinary dodging does not count as leaving the boss alone.
@export var poise_regen_delay := 6.0
## What one hit on the exposed weak point costs, as a fraction of max health.
@export_range(0.0, 1.0) var weak_point_damage := 0.15
## Worn while the stance is broken.
@export var stagger_color := Color(0.709804, 0.780392, 0.952941)
@export var stagger_glow := 1.2

@export_group("Colours")
## Shown during the telegraph, before any damage can land.
@export var windup_color := Color(0.980392, 0.803922, 0.298039)
## Shown while an attack is live and able to deal damage.
@export var attack_color := Color(1.0, 0.223529, 0.180392)
## How hard the body squashes when struck.
@export_range(0.0, 0.5) var hit_punch := 0.22
## Whether the state colours repaint the body or only light it up.
##
## Off for anything with a model worth looking at: flooding a skeleton with
## flat red loses everything that made it worth using, while letting it glow
## yellow to wind up reads just as clearly. On for the plain shapes, which have
## nothing to lose and whose colour IS the tell.
@export var tint_albedo := true

@export_group("Glow")
## Self-illumination while idle or chasing. Keep this at 0 so an enemy is lit
## only by your torch -- a glowing body would be visible in pitch darkness and
## would ignore the lighting entirely.
@export var base_glow := 0.0
## Self-illumination during the telegraph, so the wind-up is readable even when
## the enemy is outside your torch beam.
@export var windup_glow := 1.4
## Self-illumination while an attack is live.
@export var attack_glow := 2.2

@export_group("Knockback")
## How fast a knockback bleeds off, in m/s per second.
@export var knockback_damping := 14.0
## 0 = shoved at full force, 1 = immovable. Heavy things should resist.
@export_range(0.0, 1.0) var knockback_resistance := 0.0

@export_group("Performance")
## Past this distance from the player the enemy stops simulating altogether --
## no navigation query, no move_and_slide, nothing. It wakes the moment the
## player comes back inside it.
##
## With dozens of these on one map their physics is the single largest CPU cost
## in the level, and none of that work is observable from the far side of it.
## Set to 0 to disable, which is what the boss does: there is only one of him,
## so there is nothing to save, and he has room logic that wants to keep
## running. Must stay comfortably above aggro_range or enemies would doze off
## while hunting.
@export var dormant_range := 45.0
## How often a dormant enemy checks whether the player has come closer.
@export var dormant_poll := 0.4

@export_group("Navigation")
## How often the path to the player is recalculated. Only used when the scene
## has a NavigationAgent3D child; without one the enemy walks straight at the
## player, which is fine in open ground but useless in a maze.
@export var repath_interval := 0.2

@export_group("Death")
## Left empty for ordinary enemies, who just shrink away. A champion sets this
## and goes up instead.
@export var death_burst: PackedScene = null
@export var burst_radius := 4.0
@export var burst_color := Color(1.0, 0.360784, 0.235294)
## Whether killing this one puts a headline across the screen. Only a champion
## should -- a banner for every grunt would be noise.
@export var announce_death := false

@export_group("Drops")
@export_range(0.0, 1.0) var drop_chance := 0.65
## Which consumables can drop. With more than one entry they are picked between
## by their drop_weight.
@export var drop_table: Array[ConsumableType] = [
	preload("res://resources/health_potion.tres"),
]

## Logs every hit to the console. Off by default: when the game runs from the
## editor, each print is sent over the debugger socket and redrawn in the Output
## panel, which visibly hitches the frame it happens on.
@export var log_hits := false

## Ground speed the walk clip was authored for, in metres per second. The clip is
## played faster or slower than this so the feet keep pace with the floor instead
## of skating over it.
@export var walk_anim_speed := 1.45
## Ground speed the run clip was authored for. Same idea.
@export var run_anim_speed := 3.56
## Above this the run clip takes over from the walk.
@export var run_anim_threshold := 2.4

@onready var mesh: MeshInstance3D = _find_node_of("MeshInstance3D") as MeshInstance3D
@onready var shape: CollisionShape3D = $CollisionShape3D
## The pivot the body's look hangs from. The hit squash and the stagger slump
## both drive this, so it has to be a plain node with no authored turn or scale
## of its own -- a model needing either puts it on a child. Scenes that are just
## a primitive have no pivot and fall back to the mesh, which is the same thing.
@onready var visual: Node3D = _find_visual()
## Optional -- present in the shipped scenes, but the enemy still works without.
@onready var agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")
## Optional. When present, each state plays the matching animation, stretched so
## it lasts exactly as long as the state does. Searched for rather than fetched
## by path: an imported model brings its own, nested inside the imported scene.
@onready var anim: AnimationPlayer = _find_node_of("AnimationPlayer") as AnimationPlayer
## Optional. The glowing spot that opens up while staggered. Only meaningful on
## an enemy with poise; everything else leaves it out of its scene.
@onready var weak_point: Node3D = get_node_or_null("WeakPoint")

const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_RUN := &"run"
const ANIM_WINDUP := &"windup"
const ANIM_RECOVER := &"recover"
const ATTACK_ANIMS := {
	Attack.SLAM: &"slam",
	Attack.SPIN: &"spin",
	Attack.LUNGE: &"lunge",
	Attack.NORMAL: &"attack",
}
## Rolled between for a normal attack, so repeated swings never read as a loop.
## A model that ships none of these falls back to ATTACK_ANIMS.
const NORMAL_ANIMS: Array[StringName] = [&"attack_1", &"attack_2", &"attack_3"]

var health := 0.0
## Remaining poise. Stays at 0 on enemies that do not use the system.
var poise := 0.0
var state := State.CHASE
## Which move the current (or most recent) attack is.
var attack_kind := Attack.SLAM
## True while it is actually hunting the player rather than idle or going home.
var engaged := false

var _material: StandardMaterial3D
var _base_color := Color.WHITE
## The mesh's authored scale, which a fitted model sets to something other than
## 1. Everything that squashes or resets the body works from this.
var _mesh_scale := Vector3.ONE
## The colour the current state wants, which a damage flash returns to.
var _state_color := Color.WHITE
var _dying := false
var _flash_tween: Tween
var _punch_tween: Tween
## Horizontal velocity imposed from outside, decaying back to zero.
var _knockback := Vector3.ZERO
var _stun_until := 0.0
## Poise only regenerates once the clock has run past this.
var _poise_quiet_until := 0.0
var _slump_tween: Tween
## Which punch variant went last, so the next roll can exclude it.
var _last_normal_anim := &""
## Elapsed time owed to the rig but not yet spent on it.
var _anim_debt := 0.0
## Asleep: too far from the player to be worth simulating.
var _dormant := false
var _next_dormant_check := 0.0
## How many of the summon marks have been passed, and whether the weapon is
## already up.
var _summon_index := 0
var _summon_raised := false
## Set when a health mark is crossed, acted on from the next standing chase.
var _summon_pending := false

## Where it may wander, as world points. Handed over by the level builder so
## the enemy never has to know what a room is: a corridor guard gets corridor
## tiles and a room guard gets room tiles, and neither can drift into the
## other's territory while idle.
var wander_spots: Array[Vector3] = []
## How close to one of those spots still counts as being inside the patch.
## Roughly half a tile, set by the level builder.
var wander_tolerance := 2.4
var _wander_target := Vector3.ZERO
var _has_wander_target := false
var _wander_pause_until := 0.0
## The heading it is scanning around while stopped.
var _look_centre := 0.0
var _look_phase := 0.0
## Clock until which it still counts as having seen the player.
var _seen_until := 0.0
var _next_repath := 0.0
## Where it spawned, which is what a leash is measured from.
var _home := Vector3.ZERO
var _body_radius := 0.5
## Negative until the player has been found and measured once.
var _target_radius := -1.0

var _state_until := 0.0
var _attack_direction := Vector3.ZERO
var _attack_connected := false
var _next_attack_allowed := 0.0
## When each move may next be thrown, keyed by Attack. Per move rather than
## one shared timer, so a ten-second charge does not also silence its fists.
var _cooldowns := {}
## Cached: a group lookup per enemy per frame adds up across 48 of them.
var _player: Node3D = null


func _ready() -> void:
	health = max_health
	poise = max_poise
	_home = global_position
	_body_radius = _radius_of(self)
	_mesh_scale = visual.scale

	# Each enemy needs its own material copy, otherwise one flashing would flash
	# all of them.
	if mesh != null:
		var active := mesh.get_active_material(0)
		if active is StandardMaterial3D:
			_material = (active as StandardMaterial3D).duplicate()
			_base_color = _material.albedo_color
			mesh.material_override = _material
	_state_color = _base_color
	_apply_state_color(_base_color, base_glow)
	_setup_animations()
	_play_state_anim(ANIM_IDLE, 0.0)


func _physics_process(delta: float) -> void:
	var now := _now()

	# Checked before anything else, including gravity: a dormant enemy must not
	# quietly accumulate downward velocity it would then dump on waking.
	if not _dying and _update_dormancy(now):
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if _dying:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_update_locomotion()
	_advance_anim(delta)

	# Calling for help outranks everything but a broken stance: he has decided
	# to do this and will not be talked out of it by being hit.
	if state == State.SUMMON:
		_run_summon(delta, now)
		return

	# A broken stance outranks everything else, including being shoved: the
	# opening lasts its own full length whatever else lands during it, so the
	# window the player earned cannot be cut short by their own follow-up.
	if state == State.STAGGER:
		if now < _state_until:
			velocity.x = _knockback.x
			velocity.z = _knockback.z
			_decay_knockback(delta)
			move_and_slide()
			return
		_recover_from_stagger()

	# Poise knits back together, but only after a stretch with nothing landing.
	# A sustained assault makes progress; a few opportunistic pokes do not.
	if max_poise > 0.0 and poise < max_poise and now >= _poise_quiet_until:
		poise = minf(poise + poise_regen * delta, max_poise)

	# Being shoved overrides everything, and interrupts a wind-up or an attack.
	if now < _stun_until:
		if state != State.CHASE:
			_enter_chase()
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		_decay_knockback(delta)
		move_and_slide()
		return
	_decay_knockback(delta)

	var player := _resolve_player()
	if player == null:
		move_and_slide()
		return
	if _target_radius < 0.0:
		_target_radius = _radius_of(player)

	# A leashed enemy guards a place: once the player leaves that area it gives
	# up and walks home instead of following them out through the doorway.
	var guarding := aggro_box_extents != Vector3.ZERO or leash_radius > 0.0
	var returning := false
	if aggro_box_extents != Vector3.ZERO:
		returning = not _inside_zone(player.global_position)
	elif leash_radius > 0.0:
		var player_from_home := Vector2(
			player.global_position.x - _home.x,
			player.global_position.z - _home.z,
		).length()
		returning = player_from_home > leash_radius
	if returning and state != State.CHASE:
		_enter_chase()

	var goal: Vector3 = _home if returning else player.global_position
	var to_goal := goal - global_position
	var flat := Vector3(to_goal.x, 0.0, to_goal.z)
	var distance := flat.length()
	# Reach is measured edge to edge. Centre-to-centre would hand a wide body
	# free reach equal to its own radius.
	var gap := distance - _body_radius - _target_radius

	# Worked out before the state machine, because the attack states return
	# early and a boss mid-swing is very much engaged.
	var out_of_reach := (not guarding) and distance > aggro_range
	if aggro_box_extents == Vector3.ZERO and leash_radius > 0.0:
		out_of_reach = distance > aggro_range

	# An enemy with a front has to actually notice you. Once it has, it keeps
	# hunting for sight_memory seconds after losing sight, so rounding a corner
	# buys you a few seconds rather than switching it off like a lamp.
	if _has_eyes():
		if _can_see(player, distance):
			_seen_until = now + sight_memory
		out_of_reach = out_of_reach or now >= _seen_until

	engaged = not returning and not out_of_reach

	match state:
		State.WINDUP:
			_face(flat)
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			move_and_slide()
			if now >= _state_until:
				_enter_attack(flat)
			return

		State.ATTACK:
			_run_attack(delta, player, gap)
			if now >= _state_until:
				_enter_recover()
			return

		State.RECOVER:
			_face(flat)
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			move_and_slide()
			if now >= _state_until:
				_enter_chase()
			return

	# --- CHASE ---
	# A call for help outranks ordinary business, but waits for a moment when
	# he is not already mid-swing or staggered.
	if _summon_pending:
		_enter_summon()
		return

	if returning and distance < 0.8:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	# A zone guard is awake for anyone inside its room, however far across it
	# they are; everything else falls back to sight.
	if not returning and out_of_reach:
		var amble := _wander(delta, now)
		velocity.x = move_toward(velocity.x, amble.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, amble.z, acceleration * delta)
		move_and_slide()
		return

	# Losing the target mid-amble: drop the stroll and hunt.
	_has_wander_target = false
	_wander_pause_until = 0.0

	# Follow the navmesh when one is available, so walls are routed around
	# rather than walked into. Falls back to the straight line toward the goal.
	var pursue := flat.normalized()
	if agent != null:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = goal
		if not agent.is_navigation_finished():
			var to_next := agent.get_next_path_position() - global_position
			to_next.y = 0.0
			if to_next.length() > 0.1:
				pursue = to_next.normalized()

	var advancing := (distance > 1.0) if returning else (gap > stop_distance)
	_face(pursue if advancing else flat)

	var desired := Vector3.ZERO
	if advancing:
		desired = pursue * move_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	move_and_slide()

	if not returning and gap <= attack_trigger_range and now >= _next_attack_allowed:
		var choice := _pick_attack(gap, now)
		if choice >= 0:
			_enter_windup(choice)


## Can it see the player right now? Range, then the cone, then the wall check --
## cheapest test first, because the ray is the only expensive part and most
## enemies fail on distance or angle before reaching it.
func _can_see(player: Node3D, distance: float) -> bool:
	if distance > aggro_range:
		return false

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return true

	if vision_cone_degrees > 0.0:
		# -Z is the way it faces, matching how _face aims it.
		var facing := -global_basis.z
		facing.y = 0.0
		if facing.length_squared() > 0.0001:
			var off := facing.normalized().angle_to(to_player.normalized())
			if off > deg_to_rad(vision_cone_degrees * 0.5):
				return false

	if not sight_needs_line_of_sight:
		return true
	var from := global_position + Vector3(0, eye_height, 0)
	var to := player.global_position + Vector3(0, 0.9, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = sight_blocking_mask
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(params).is_empty()


## Ambling about near home while nothing has been seen. Returns the velocity
## it wants; turning is handled here too, since looking around is the point.
func _wander(delta: float, now: float) -> Vector3:
	if not wanders:
		return Vector3.ZERO

	# Out of its patch: walk back in before doing anything else. Drift, a shove
	# or a navmesh path that cuts a corner can all carry it over the line, and
	# without this it would happily carry on wandering wherever it ended up.
	if not _inside_wander_area(global_position):
		var back := _home - global_position
		back.y = 0.0
		if back.length() > 0.5:
			_has_wander_target = false
			_wander_pause_until = 0.0
			var home_dir := back.normalized()
			_face(home_dir)
			return home_dir * wander_speed

	# Stopped and scanning.
	if now < _wander_pause_until:
		_look_phase += delta * deg_to_rad(look_around_speed)
		rotation.y = _look_centre + sin(_look_phase) * deg_to_rad(look_around_degrees)
		return Vector3.ZERO

	if not _has_wander_target:
		_pick_wander_target()
		if not _has_wander_target:
			return Vector3.ZERO

	var to_target := _wander_target - global_position
	to_target.y = 0.0
	if to_target.length() < 1.0:
		# Arrived: stand a moment and look about before choosing again.
		_has_wander_target = false
		_wander_pause_until = now + randf_range(wander_pause_min, wander_pause_max)
		_look_centre = rotation.y
		_look_phase = 0.0
		return Vector3.ZERO

	# Straight at it, deliberately not along the navmesh. Every wander spot is
	# a short hop away inside the same room or stretch of corridor, and a
	# navmesh path is free to swing out through a doorway and back -- which
	# walks the enemy through somewhere it is not supposed to go.
	var heading := to_target.normalized()
	# Do not step outside the patch to get there.
	if not _inside_wander_area(global_position + heading * 0.8):
		_has_wander_target = false
		return Vector3.ZERO
	_face(heading)
	return heading * wander_speed


## Is this point still inside the patch the level allotted it?
##
## Tested against the allowed spots themselves, not a box around them. A
## corridor bends, and the bounding box of an L covers the inside of the
## corner -- which is often the very room the enemy is supposed to stay out of.
## A couple of dozen distance checks, only for enemies actually wandering.
func _inside_wander_area(point: Vector3) -> bool:
	if wander_spots.is_empty():
		return true
	var limit := wander_tolerance * wander_tolerance
	for spot in wander_spots:
		var dx := point.x - spot.x
		var dz := point.z - spot.z
		if dx * dx + dz * dz <= limit:
			return true
	return false


## Somewhere else inside its own patch. Falls back to a circle around home when
## the level did not hand it a list.
func _pick_wander_target() -> void:
	if not wander_spots.is_empty():
		_wander_target = wander_spots[randi() % wander_spots.size()]
		_has_wander_target = true
		return
	var angle := randf() * TAU
	var reach := randf_range(wander_radius * 0.35, wander_radius)
	_wander_target = _home + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
	_has_wander_target = true


## Cached because a group lookup per enemy per frame adds up across dozens.
func _resolve_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


## True when this frame's simulation should be skipped entirely. Polled rather
## than tested every frame, so a sleeping enemy costs one distance check every
## `dormant_poll` seconds and nothing in between.
func _update_dormancy(now: float) -> bool:
	if dormant_range <= 0.0:
		return false
	if now < _next_dormant_check:
		return _dormant
	_next_dormant_check = now + dormant_poll

	var player := _resolve_player()
	if player == null:
		return _dormant
	# Scaled by the quality setting: on a weak machine the cast goes to sleep
	# closer in, which is the cheapest simulation saving available.
	var reach: float = dormant_range * Graphics.npc_detail
	var far := global_position.distance_squared_to(player.global_position) \
		> reach * reach

	if _dormant:
		if far:
			return true
		_dormant = false
		if anim != null:
			anim.active = true
		return false

	# Never doze off part way through an attack, only from a standing chase.
	if far and state == State.CHASE:
		_dormant = true
		velocity = Vector3.ZERO
		engaged = false
		# Posing a skeleton costs real CPU whether or not anyone can see it, and
		# most of the cast is asleep at any moment. Stop the rig with the body.
		if anim != null:
			anim.active = false
		return true
	return false


## Drives whichever move was rolled. Each one damages at most once.
func _run_attack(delta: float, player: Node3D, gap: float) -> void:
	match attack_kind:
		Attack.NORMAL:
			# Stands its ground and swings. No charge speed is asked of it,
			# which is the whole reason it exists: this is the move that can
			# land while the enemy is already pressed up against you.
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			move_and_slide()
			_try_connect(player, gap, normal_range)

		Attack.SPIN:
			# Whirls on the spot; the reach is all the way around.
			velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
			if spin_duration > 0.0:
				rotation.y += TAU * spin_turns * delta / spin_duration
			move_and_slide()
			_try_connect(player, gap, spin_range)

		Attack.LUNGE:
			velocity.x = _attack_direction.x * lunge_speed
			velocity.z = _attack_direction.z * lunge_speed
			move_and_slide()
			_try_connect(player, gap, lunge_range, lunge_speed)

		_:
			velocity.x = _attack_direction.x * slam_speed
			velocity.z = _attack_direction.z * slam_speed
			move_and_slide()
			_try_connect(player, gap, slam_range, slam_speed)


## `charge_speed` of 0 means the move is stationary by design (the spin), so no
## speed is required of it.
func _try_connect(player: Node3D, gap: float, reach: float, charge_speed := 0.0) -> void:
	if _attack_connected or gap > reach:
		return
	# Reach is horizontal; without this a swing at ground level would land on
	# someone stood on a block above it.
	if absf(player.global_position.y - global_position.y) > max_height_difference:
		return
	if charge_speed > 0.0:
		# get_real_velocity(), not velocity: the attack assigns velocity every
		# frame regardless, so the intended speed is always "full". Only the
		# distance actually covered says whether it is charging or just leaning
		# on the player.
		var travelling := Vector2(get_real_velocity().x, get_real_velocity().z).length()
		if travelling < charge_speed * dash_connect_speed:
			return
	if not player.has_method("take_damage"):
		return
	_attack_connected = true
	player.take_damage(attack_damage, _attack_direction)


## Picks a move for the range it is at, or -1 when nothing is off cooldown.
##
## An enemy with fists chooses by distance rather than at random: in reach it
## swings, out of reach it charges to get into reach. That is the whole point
## of the split -- the charge stops being the thing that damages you and
## becomes the thing that closes on you.
##
## Anything without fists keeps rolling at random among what it has, which is
## what makes the boss's three moves unpredictable.
func _pick_attack(gap: float, now: float) -> int:
	if not can_normal:
		return _roll_from(_ready_moves(now))
	if gap <= normal_range:
		return Attack.NORMAL if now >= _ready_at(Attack.NORMAL) else -1
	# Out of reach: only the moves that travel are any use here.
	var closers: Array[int] = []
	for kind in _ready_moves(now):
		if kind != Attack.NORMAL:
			closers.append(kind)
	return _roll_from(closers)


## Every enabled move whose own cooldown has run out.
func _ready_moves(now: float) -> Array[int]:
	var options: Array[int] = []
	if can_normal and now >= _ready_at(Attack.NORMAL):
		options.append(Attack.NORMAL)
	if can_slam and now >= _ready_at(Attack.SLAM):
		options.append(Attack.SLAM)
	if can_spin and now >= _ready_at(Attack.SPIN):
		options.append(Attack.SPIN)
	if can_lunge and now >= _ready_at(Attack.LUNGE):
		options.append(Attack.LUNGE)
	return options


func _roll_from(options: Array[int]) -> int:
	return options[randi() % options.size()] if not options.is_empty() else -1


## When this move may next be used.
func _ready_at(kind: int) -> float:
	return float(_cooldowns.get(kind, 0.0))


## Its own gap if it has been given one, otherwise the shared attack_cooldown.
func _cooldown_of(kind: int) -> float:
	var own := 0.0
	match kind:
		Attack.NORMAL:
			own = normal_cooldown
		Attack.SPIN:
			own = spin_cooldown
		Attack.LUNGE:
			own = lunge_cooldown
		_:
			own = slam_cooldown
	return own if own > 0.0 else attack_cooldown


func _attack_duration() -> float:
	match attack_kind:
		Attack.NORMAL:
			return normal_duration
		Attack.SPIN:
			return spin_duration
		Attack.LUNGE:
			return lunge_duration
		_:
			return slam_duration


## Is the point inside the guarded box, measured from the spawn point?
func _inside_zone(point: Vector3) -> bool:
	var offset := point - _home
	return absf(offset.x) <= aggro_box_extents.x and absf(offset.z) <= aggro_box_extents.z


func _face(direction: Vector3) -> void:
	if direction.length_squared() > 0.001:
		rotation.y = atan2(-direction.x, -direction.z)


func _enter_chase() -> void:
	state = State.CHASE
	_apply_state_color(_base_color, base_glow)
	_play_state_anim(ANIM_IDLE, 0.0)


func _enter_windup(kind: int) -> void:
	state = State.WINDUP
	# Decided before the telegraph starts, so the whole wind-up belongs to one
	# move rather than being chosen at the moment it lands.
	attack_kind = kind
	_state_until = _now() + windup_time
	_apply_state_color(windup_color, windup_glow)
	_play_state_anim(ANIM_WINDUP, windup_time)


func _enter_attack(toward: Vector3) -> void:
	state = State.ATTACK
	_state_until = _now() + _attack_duration()
	_attack_connected = false
	# Direction is locked when the attack starts, so side-stepping works.
	_attack_direction = toward.normalized() if toward.length_squared() > 0.001 else -global_basis.z
	if attack_kind != Attack.SPIN:
		_face(_attack_direction)
	_apply_state_color(attack_color, attack_glow)
	_play_state_anim(_anim_for_attack(attack_kind), _attack_duration())


func _enter_recover() -> void:
	state = State.RECOVER
	_state_until = _now() + recover_time
	_next_attack_allowed = _now() + attack_cooldown
	# Per move, timed from when it finished. A long charge cooldown then does
	# not stop it swinging at you in the meantime.
	_cooldowns[attack_kind] = _now() + _cooldown_of(attack_kind)
	_apply_state_color(_base_color, base_glow)
	_play_state_anim(ANIM_RECOVER, recover_time)


## Direct children win over deeper ones, so a scene that places its own node
## keeps control even when an imported model brings a second one along.
func _find_node_of(type: String) -> Node:
	for child in get_children():
		if child.is_class(type):
			return child
	return _search_below(self, type)


func _search_below(from: Node, type: String) -> Node:
	for child in from.get_children():
		if child.is_class(type):
			return child
		var deeper := _search_below(child, type)
		if deeper != null:
			return deeper
	return null


func _find_visual() -> Node3D:
	var pivot := get_node_or_null("Visual")
	if pivot is Node3D:
		return pivot as Node3D
	return _find_node_of("MeshInstance3D") as Node3D


## Loop the locomotion clips and cross-fade between everything.
##
## Every clip drives the same bones, so a hard cut between two of them snaps the
## whole body. Attacks get a much shorter blend than locomotion: the wind-up is a
## telegraph the player reads and reacts to, and smearing it costs them the read.
func _setup_animations() -> void:
	if anim == null:
		return
	# Advanced by hand from _physics_process instead of by the engine, so a rig
	# the player is nowhere near can be posed at a lower rate -- or not at all.
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for looping in [ANIM_IDLE, ANIM_WALK, ANIM_RUN]:
		if anim.has_animation(looping):
			anim.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
	var moves := [ANIM_IDLE, ANIM_WALK, ANIM_RUN]
	var clips := anim.get_animation_list()
	for from in clips:
		for to in clips:
			if from == to:
				continue
			var soft: bool = moves.has(StringName(from)) and moves.has(StringName(to))
			anim.set_blend_time(from, to, 0.22 if soft else 0.09)


## Picks the clip for an attack, rolling between the punch variants so a flurry
## reads as a combination rather than the same swing repeating.
func _anim_for_attack(kind: int) -> StringName:
	if kind != Attack.NORMAL or anim == null:
		return ATTACK_ANIMS[kind]
	var choices: Array[StringName] = []
	for name in NORMAL_ANIMS:
		if anim.has_animation(name):
			choices.append(name)
	if choices.is_empty():
		return ATTACK_ANIMS[kind]
	# Never the same punch twice running.
	if choices.size() > 1:
		choices.erase(_last_normal_anim)
	_last_normal_anim = choices[randi() % choices.size()]
	return _last_normal_anim


## Idle, walk or run, chosen from how fast the body is actually moving and played
## at the rate that keeps the feet with the floor. Only drives a standing chase:
## every other state is holding a clip of its own.
func _update_locomotion() -> void:
	if anim == null or state != State.CHASE:
		return
	var moving := get_real_velocity()
	var speed := Vector2(moving.x, moving.z).length()
	var want := ANIM_IDLE
	var rate := 1.0
	if speed >= run_anim_threshold and run_anim_speed > 0.0:
		want = ANIM_RUN
		rate = clampf(speed / run_anim_speed, 0.65, 1.9)
	elif speed > 0.2 and walk_anim_speed > 0.0:
		want = ANIM_WALK
		rate = clampf(speed / walk_anim_speed, 0.5, 1.9)
	if not anim.has_animation(want):
		want = ANIM_IDLE
		rate = 1.0
		if not anim.has_animation(want):
			return
	if anim.current_animation == want:
		anim.speed_scale = rate
		return
	anim.play(want, -1.0, rate)


## Steps the rig forward -- but not necessarily this frame.
##
## Posing 22 bones costs the same whether or not the player can make out the
## result, and most of the cast is somewhere else in the level. Close up this
## runs every frame; further out it accumulates the elapsed time and spends it
## in one larger step, which is the same motion at a coarser sample rate.
func _advance_anim(delta: float) -> void:
	if anim == null or not anim.active:
		return
	_anim_debt += delta
	var stride := 0.0
	if Graphics.anim_full_distance < 1.0e8:
		var player := _resolve_player()
		if player != null:
			var gap := global_position.distance_to(player.global_position)
			if gap > Graphics.anim_half_distance:
				if Graphics.anim_far_rate <= 0.0:
					return
				stride = 1.0 / Graphics.anim_far_rate
			elif gap > Graphics.anim_full_distance:
				stride = 1.0 / maxf(Graphics.anim_near_rate, 1.0)
	if _anim_debt < stride:
		return
	anim.advance(_anim_debt)
	_anim_debt = 0.0


## Plays `which` stretched to fill `duration`, so what the player sees telegraphs
## exactly the window the code is using. A duration of 0 plays at authored speed.
func _play_state_anim(which: StringName, duration: float) -> void:
	if anim == null or not anim.has_animation(which):
		return
	var length: float = anim.get_animation(which).length
	var speed := 1.0
	if duration > 0.0 and length > 0.0:
		speed = length / duration
	anim.play(which, -1.0, speed)
	# Explicit rewind: replaying a clip that already ran to its end can otherwise
	# resume at the end, so a repeated state would show no telegraph at all.
	anim.seek(0.0, true)


## True while an attack is live and able to deal damage.
func is_attacking() -> bool:
	return state == State.ATTACK


## Glow is per state, not permanent: at rest the body is unlit and only your
## torch reveals it, while an attack lights itself up so the telegraph still
## reads from outside the beam.
func _apply_state_color(colour: Color, glow: float) -> void:
	# With tinting off the body keeps its own colour and the state rides on the
	# glow alone.
	_state_color = colour if tint_albedo else _base_color
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	if _material == null:
		return
	_material.albedo_color = _state_color
	if _material.emission_enabled:
		_material.emission = colour
		_material.emission_energy_multiplier = glow


## Shoves the enemy along `impulse` (horizontal component only) and interrupts
## its pursuit for `stun_time`.
func apply_knockback(impulse: Vector3, stun_time := 0.25) -> void:
	if _dying:
		return
	# Resistance reduces how far something is thrown but not how long it is
	# interrupted: a boss should stagger without being punted across the room.
	var scale := 1.0 - knockback_resistance
	_knockback.x += impulse.x * scale
	_knockback.z += impulse.z * scale

	# Hyper-armour. Anything with poise shrugs the interruption off and keeps
	# swinging -- you cannot machine-gun a boss out of every wind-up. Breaking
	# its poise is the only thing that stops it, and that runs on its own clock
	# rather than this one.
	if max_poise > 0.0 and state != State.STAGGER:
		return
	_stun_until = maxf(_stun_until, _now() + stun_time)


func is_stunned() -> bool:
	return _now() < _stun_until


func _decay_knockback(delta: float) -> void:
	_knockback = _knockback.move_toward(Vector3.ZERO, knockback_damping * delta)


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	if _dying:
		return

	# Untouchable while calling for help, and it has to look it: a boss that
	# silently eats damage reads as a bug, not as a rule. The blow gets its own
	# response -- a hard flash and a flare outward rather than the usual squash
	# -- so the difference between "did nothing" and "was turned aside" is
	# visible on the frame it happens.
	if state == State.SUMMON:
		_deflect()
		return
	# Being hit counts as noticing you, whichever way it happened to be facing.
	# Otherwise you could stand behind one and whittle it down while it ambled
	# about none the wiser.
	_seen_until = _now() + sight_memory
	_has_wander_target = false
	_wander_pause_until = 0.0
	# Wake a sleeping one immediately rather than at its next poll.
	_dormant = false

	health = maxf(health - amount, 0.0)
	if log_hits:
		print("%s took %.0f damage (%.0f/%.0f)" % [name, amount, health, max_health])
	_flash()
	if health <= 0.0:
		_die()
		return
	# Checked after the damage lands, so a hit that crosses a mark calls for
	# help rather than the mark being missed between frames.
	_check_summon_thresholds()

	# Poise damage is a straight multiple of the damage dealt, so a jump slam
	# opens the boss up in a couple of landings while sword chip takes a proper
	# sustained beating. Hits landed during a stagger are already being paid for
	# by the stagger itself and do not feed back into it.
	if max_poise > 0.0 and amount > 0.0 and state != State.STAGGER:
		_poise_quiet_until = _now() + poise_regen_delay
		poise = maxf(poise - amount * poise_damage_ratio, 0.0)
		if poise <= 0.0:
			_enter_stagger()


## The stance breaks: the boss buckles, stops dead, and the spot on its front
## opens up for however long `stagger_time` allows.
func _enter_stagger() -> void:
	state = State.STAGGER
	poise = 0.0
	_state_until = _now() + stagger_time
	# Whatever it was in the middle of is over, and cannot still connect.
	_stun_until = 0.0
	_attack_connected = true
	velocity.x = 0.0
	velocity.z = 0.0
	# Drops where it stands. Any shove still in flight is spent, so the weak
	# point is not sliding away from the player at the moment it opens up.
	_knockback = Vector3.ZERO
	_apply_state_color(stagger_color, stagger_glow)
	_play_state_anim(ANIM_RECOVER, stagger_time)
	_slump(true)
	if weak_point != null and weak_point.has_method("set_exposed"):
		weak_point.set_exposed(true)


func _recover_from_stagger() -> void:
	poise = max_poise
	_poise_quiet_until = 0.0
	_stun_until = 0.0
	_knockback = Vector3.ZERO
	_slump(false)
	if weak_point != null and weak_point.has_method("set_exposed"):
		weak_point.set_exposed(false)
	# It stands up through a normal recovery, then waits a beat longer before it
	# may swing again -- getting back up should not itself be a trap.
	_enter_recover()
	_next_attack_allowed = maxf(_next_attack_allowed, _now() + 0.6)


## Called by the exposed weak point when the player lands an aimed hit on it.
## Worth a fixed slice of the boss's total health, and it closes the opening:
## the reward is one clean strike, not a free few seconds of them. Returns the
## damage dealt, or 0 if there was nothing to hit.
func strike_weak_point(from_direction: Vector3 = Vector3.ZERO) -> float:
	if _dying or state != State.STAGGER:
		return 0.0
	var payload := max_health * weak_point_damage
	take_damage(payload, from_direction)
	if not _dying:
		_recover_from_stagger()
	return payload


## Buckling forward, so a broken stance reads across the room even with the boss
## bar off the top of the screen. Uses rotation, leaving the hit flash's squash
## on `scale` free to play over the top of it.
func _slump(down: bool) -> void:
	if _slump_tween != null and _slump_tween.is_valid():
		_slump_tween.kill()
	var target := Vector3(deg_to_rad(24.0), 0.0, deg_to_rad(-10.0)) if down else Vector3.ZERO
	_slump_tween = create_tween()
	_slump_tween.tween_property(visual, "rotation", target, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Walks back to the middle of the room, plants, and holds the weapon up.
##
## Two phases in one state rather than two states, because from outside it is
## one move: he disengages, crosses the floor, and raises it. The raise only
## begins once he has arrived, so the tell always happens where the player can
## see it, in the middle of the arena.
func _run_summon(delta: float, now: float) -> void:
	var home := _home - global_position
	home.y = 0.0

	if not _summon_raised:
		if home.length() > summon_arrive:
			var heading := home.normalized()
			if agent != null:
				if now >= _next_repath:
					_next_repath = now + repath_interval
					agent.target_position = _home
				if not agent.is_navigation_finished():
					var step := agent.get_next_path_position() - global_position
					step.y = 0.0
					if step.length() > 0.1:
						heading = step.normalized()
			_face(heading)
			velocity.x = move_toward(velocity.x, heading.x * move_speed, acceleration * delta)
			velocity.z = move_toward(velocity.z, heading.z * move_speed, acceleration * delta)
			move_and_slide()
			return

		# Arrived: plant and lift it.
		_summon_raised = true
		_state_until = now + summon_time
		_apply_state_color(summon_color, summon_glow)
		_play_state_anim(ANIM_WINDUP, summon_time)

	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	# Faces whoever it is calling help against.
	var player := _resolve_player()
	if player != null:
		var at := player.global_position - global_position
		at.y = 0.0
		_face(at)
	move_and_slide()

	if now >= _state_until:
		summoned.emit(_summon_index)
		_summon_raised = false
		_enter_recover()


## Has it dropped past the next health mark? Called after damage lands.
##
## Only raises a flag. Starting the call here would fight whatever the same hit
## is already doing -- a blow big enough to cross a mark is often big enough to
## break poise too, and the stagger would simply overwrite the summon and lose
## it. The call is picked up from a standing chase instead, so a stagger the
## player earned still happens, and the help arrives afterwards.
func _check_summon_thresholds() -> void:
	while _summon_index < summon_at.size() and health <= summon_at[_summon_index]:
		_summon_index += 1
		_summon_pending = true


func _enter_summon() -> void:
	state = State.SUMMON
	_summon_pending = false
	_summon_raised = false
	_attack_connected = true
	_stun_until = 0.0
	_knockback = Vector3.ZERO
	_next_repath = 0.0


## True while calling for help, which is not an attack and cannot hurt you.
func is_summoning() -> bool:
	return state == State.SUMMON


## True when this one has a front and has to notice you, rather than simply
## knowing where you are.
func _has_eyes() -> bool:
	return vision_cone_degrees > 0.0 or sight_needs_line_of_sight


func is_staggered() -> bool:
	return state == State.STAGGER


## True while hits cannot interrupt it. Poise is what buys this.
func has_hyper_armor() -> bool:
	return max_poise > 0.0 and state != State.STAGGER


## A hit that was turned aside. Deliberately unlike _flash: the body swells
## instead of squashing, and it flares to the summon colour rather than to
## white, so the two never read as the same event.
func _deflect() -> void:
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	visual.scale = _mesh_scale * (1.0 + deflect_punch)
	_punch_tween = create_tween()
	_punch_tween.tween_property(visual, "scale", _mesh_scale, 0.26) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if _material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_material.albedo_color = deflect_color
	if _material.emission_enabled:
		_material.emission = deflect_color
		_material.emission_energy_multiplier = summon_glow * 2.2
	_flash_tween = create_tween().set_parallel(true)
	_flash_tween.tween_property(_material, "albedo_color", _state_color, 0.22)
	if _material.emission_enabled:
		_flash_tween.tween_property(
			_material, "emission_energy_multiplier", summon_glow, 0.22)


func _flash() -> void:
	# A quick squash on top of the colour flash, so a hit reads even when the
	# enemy is already lit up mid-attack.
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	# Relative to the mesh's authored scale, not to 1. A model fitted to the
	# collision capsule sits at 0.83, and squashing to an absolute size would
	# snap it to full height on the first hit and leave it there.
	visual.scale = _mesh_scale * Vector3(
		1.0 + hit_punch, 1.0 - hit_punch * 0.6, 1.0 + hit_punch)
	_punch_tween = create_tween()
	_punch_tween.tween_property(visual, "scale", _mesh_scale, 0.22) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if _material == null:
		return
	# Rapid hits would otherwise stack tweens that fight over the same colour,
	# and the flash returns to whatever colour the current state wants.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_material.albedo_color = Color(1.0, 0.95, 0.9)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "albedo_color", _state_color, 0.18)


func _die() -> void:
	_dying = true
	died.emit()
	shape.disabled = true
	# Otherwise the squash and slump tweens keep fighting the shrink-out.
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	if _slump_tween != null and _slump_tween.is_valid():
		_slump_tween.kill()
	mesh.scale = _mesh_scale
	if weak_point != null and weak_point.has_method("set_exposed"):
		weak_point.set_exposed(false)
	_grant_drop()

	if announce_death:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("announce"):
			hud.announce("%s HAS FALLEN" % display_name)

	if death_burst == null:
		# An ordinary enemy just folds up and goes.
		var quick := create_tween()
		quick.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35).set_ease(Tween.EASE_IN)
		quick.tween_callback(queue_free)
		return

	# A champion buckles first: it drops to its knees, sways, then collapses and
	# goes up. Long enough to register as an event rather than a disappearance.
	var tween := create_tween()
	tween.tween_property(mesh, "rotation", Vector3(deg_to_rad(28.0), 0.0, deg_to_rad(-14.0)), 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "scale", Vector3(1.08, 0.86, 1.08), 0.3)
	tween.tween_interval(0.35)
	tween.tween_property(self, "scale", Vector3(1.3, 0.06, 1.3), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(_burst)
	tween.tween_callback(queue_free)


## Spawned into the parent rather than as a child, because this node frees
## itself on the next line and would take the explosion with it.
func _burst() -> void:
	if death_burst == null or get_parent() == null:
		return
	# The burst is an additive, overlapping transparent shell plus a light --
	# which is exactly the shape of thing a weak GPU hates most.
	if not Graphics.effects:
		return
	var burst := death_burst.instantiate() as Node3D
	burst.radius = burst_radius
	burst.colour = burst_color
	get_parent().add_child(burst)
	burst.global_position = global_position + Vector3(0, 2.2, 0)


## Drops go straight into the player's inventory rather than spawning something
## to walk over.
func _grant_drop() -> void:
	if randf() > drop_chance:
		return
	var type := _roll_drop()
	if type == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("add_consumable"):
		return
	player.add_consumable(type, 1)


## Weighted pick across drop_table.
func _roll_drop() -> ConsumableType:
	var total := 0.0
	for type in drop_table:
		if type != null:
			total += maxf(type.drop_weight, 0.0)
	if total <= 0.0:
		return null

	var roll := randf() * total
	for type in drop_table:
		if type == null:
			continue
		roll -= maxf(type.drop_weight, 0.0)
		if roll <= 0.0:
			return type
	return null


## Horizontal half-width of a body, read from its collision shape so reach
## calculations do not have to hardcode per-scene sizes.
func _radius_of(body: Node) -> float:
	var collider := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider != null:
		var s := collider.shape
		if s is CapsuleShape3D:
			return (s as CapsuleShape3D).radius
		if s is SphereShape3D:
			return (s as SphereShape3D).radius
		if s is CylinderShape3D:
			return (s as CylinderShape3D).radius
		if s is BoxShape3D:
			return (s as BoxShape3D).size.x * 0.5
	return 0.5


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
