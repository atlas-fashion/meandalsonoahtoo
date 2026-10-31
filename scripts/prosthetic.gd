extends "res://scripts/enemy.gd"

## The skeleton types (the user, 2026-10-20; note 93). Every fighting skeleton
## has lost a hand, or both, and wears a tool in its place -- and the tool is
## what kind of fighter it is:
##
##   &"drill"   the DRILL hand (the crystal mine's miners): jabs, and dashes at
##              you from range like the old skeleton's charge, bit spinning.
##   &"blade"   the SWORD hand: cannot dash. A light slice (the old cut, quick,
##              often) and a heavy slice -- a long wind-up, then a flat sweep
##              across the whole front for twice the damage.
##   &"hammer"  the HAMMER hand: slow on its feet, a long wind-up, an overhead
##              smash for 30 that knocks the player off their feet unless the
##              guard is up. Hard to shove.
##   &"shield"  a tower SHIELD on BOTH arms: guards its fellows. It picks one
##              (a crossbowman first) and stands braced between it and the
##              player; a blow at that fellow through the shield is taken by
##              the shield (enemy.gd `_covering_shield`), and so is any blow at
##              its own front. A heavy blow (40+, or a shove of 8.5+ -- the
##              slam, the spin, the spear's dash, a blast, a parry) breaks the
##              guard for GUARD_BROKEN s. Up close it bashes: a shove and 9.
##
## The crossbow hand is archer.gd. All are enemy.tscn with this script put on
## before it enters the tree (`make`), as the archer and the enforcer are; the
## arm posing is skeleton_sword.gd's (the prostheses) and skeleton_shield.gd's.

const SHIELD := preload("res://scripts/skeleton_shield.gd")
const HANDS: Array[StringName] = [&"drill", &"blade", &"hammer", &"shield"]

## The sword hand's two blows, wind-up, swing and recovery. The blade is its whole
## arm: a long heave, a short swing that is all the ATTACK window there is, and a long
## time getting it back and letting it settle (notes 137, 138). tools/anim_sword_skeleton.py
## `LIGHT` and `HEAVY` are these same numbers, baked into the clips: change both.
const BLADE_WINDUP := 0.9
const BLADE_SWING := 0.24
const BLADE_RECOVER := 1.3
const HEAVY_DAMAGE := 26.0
const HEAVY_WINDUP := 1.25
const HEAVY_SWING := 0.3
const HEAVY_RECOVER := 1.85
## Of the moments both slices are ready, how often it chooses the heavy one.
const HEAVY_SHARE := 0.4
## The drill's dash hits harder than its jab.
const DRILL_DASH_DAMAGE := 18.0
## The hammer.
const HAMMER_WINDUP := 0.95
const HAMMER_RECOVER := 1.2
const HAMMER_KNOCKDOWN := 6.5
## The shield's bash shoves the player this hard (half through a guard).
const BASH_SHOVE := 8.0
## The shield: what a blocked blow still takes off it, and what breaks it.
const SHIELD_CHIP := 0.1
const GUARD_BREAK_DAMAGE := 40.0
const GUARD_BREAK_PUSH := 8.5
const GUARD_BROKEN := 1.5
## How far in front of its ward it stands, and how far it looks for one.
const GUARD_AHEAD := 1.5
const WARD_SEARCH := 12.0
const WARD_EVERY := 0.6
## Half the shield's width, plus a body: how far off the blow's line a ward
## may stand and still be covered.
const COVER_HALF := 0.75

## Which hand. Setting it (before the body enters the tree) sets its numbers;
## anything the caller sets after that wins.
var hand := &"blade":
	set(value):
		hand = value
		_apply_hand()

var _shield: Node3D = null
## 0 carried low .. 1 braced in front, and the bash's shove forward.
var _raise := 0.0
var _guard_broken_until := 0.0
var _ward: Node3D = null
var _next_ward := 0.0


## An enemy.tscn instance with this script and `which` hand, ready to place.
static func make(scene: PackedScene, which: StringName) -> CharacterBody3D:
	var e: CharacterBody3D = scene.instantiate()
	e.set_script(script_for(which))
	e.set("hand", which)
	return e


## The sword hand has a body of its own (sword_skeleton.gd, note 135).
static func script_for(which: StringName) -> Script:
	return load("res://scripts/sword_skeleton.gd" if which == &"blade" else "res://scripts/prosthetic.gd")


func _init() -> void:
	# What enemy.tscn sets on the plain skeleton (a script swap drops it).
	move_speed = 4.5
	vision_cone_degrees = 120.0
	sight_needs_line_of_sight = true
	sight_memory = 4.5
	wanders = true
	wander_speed = 1.1
	attack_cooldown = 0.0
	can_normal = true
	normal_range = 1.5
	normal_cooldown = 3.0
	slam_cooldown = 10.0
	tint_albedo = false
	walk_anim_speed = 1.45
	run_anim_speed = 3.56
	run_anim_threshold = 2.4
	_apply_hand()


func _apply_hand() -> void:
	armed = hand != &"shield"
	weapon = hand
	can_normal = true
	can_slam = false
	can_spin = false
	can_lunge = false
	match hand:
		&"drill":
			display_name = "DRILL SKELETON"
			max_health = 100.0
			move_speed = 4.5
			# The old skeleton's charge: 8 m in 0.45 s.
			can_slam = true
			slam_speed = 18.0
			slam_duration = 0.45
			slam_cooldown = 8.0
			normal_cooldown = 2.4
			attack_damage = 14.0
		&"hammer":
			display_name = "HAMMER SKELETON"
			max_health = 140.0
			move_speed = 3.4
			acceleration = 14.0
			normal_range = 1.6
			normal_duration = 0.5
			normal_cooldown = 2.4
			attack_damage = 30.0
			knockback_resistance = 0.45
		&"shield":
			display_name = "SHIELD SKELETON"
			max_health = 120.0
			move_speed = 3.9
			normal_range = 1.2
			normal_duration = 0.3
			normal_cooldown = 2.2
			attack_damage = 9.0
			knockback_resistance = 0.3
		_:
			display_name = "SWORD SKELETON"
			max_health = 100.0
			move_speed = 4.6
			normal_cooldown = 1.6
			attack_damage = 12.0
			windup_time = BLADE_WINDUP
			normal_duration = BLADE_SWING
			recover_time = BLADE_RECOVER
			# The heavy slice is SLAM: a short planted step, not a charge.
			slam_speed = 2.5
			slam_duration = HEAVY_SWING
			slam_cooldown = 4.5


func _ready() -> void:
	super()
	name = String(hand).capitalize() + "Skeleton"
	if hand == &"shield":
		add_to_group(&"shield_guards")
		_shield = SHIELD.attach(self)


# --- Moves --------------------------------------------------------------------------

func _sword_move(kind: int) -> int:
	match hand:
		&"drill":
			return 2
		&"hammer":
			return 1
		&"blade":
			return 4 if kind == Attack.SLAM else 0
	return super(kind)


func _windup_for(kind: int) -> float:
	if hand == &"hammer":
		return HAMMER_WINDUP
	if hand == &"blade" and kind == Attack.SLAM:
		return HEAVY_WINDUP
	return windup_time


func _recover_for(kind: int) -> float:
	if hand == &"hammer":
		return HAMMER_RECOVER
	if hand == &"blade" and kind == Attack.SLAM:
		return HEAVY_RECOVER
	return recover_time


func _damage_for(kind: int) -> float:
	if kind == Attack.SLAM:
		if hand == &"blade":
			return HEAVY_DAMAGE
		if hand == &"drill":
			return DRILL_DASH_DAMAGE
	return attack_damage


## The sword hand never closes the gap with a move: in reach it picks a slice,
## out of reach it walks.
func _pick_attack(gap: float, now: float) -> int:
	if hand != &"blade":
		return super(gap, now)
	if gap > normal_range:
		return -1
	var heavy := now >= _ready_at(Attack.SLAM)
	var light := now >= _ready_at(Attack.NORMAL)
	if heavy and (not light or randf() < HEAVY_SHARE):
		return Attack.SLAM
	return Attack.NORMAL if light else -1


func _on_blow_landed(player: Node3D, _kind: int) -> void:
	var guarding: bool = player.get("_blocking") == true
	match hand:
		&"hammer":
			if not guarding and player.has_method("knock_down"):
				player.call("knock_down", _attack_direction, HAMMER_KNOCKDOWN)
		&"shield":
			if player.has_method("apply_knockback"):
				var push := Vector3(_attack_direction.x, 0.0, _attack_direction.z).normalized() * BASH_SHOVE
				player.call("apply_knockback", push * (0.5 if guarding else 1.0))


# --- The shield ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if _shield == null or _dying:
		return
	var up := engaged and state != State.STAGGER and not is_stunned() and _now() >= _guard_broken_until
	_raise = move_toward(_raise, 1.0 if up else 0.0, delta * (4.0 if up else 3.0))
	var bash := 0.0
	var now := _now()
	if attack_kind == Attack.NORMAL:
		if state == State.WINDUP:
			bash = -0.25 * clampf(1.0 - (_state_until - now) / maxf(_windup_len, 0.01), 0.0, 1.0)
		elif state == State.ATTACK:
			bash = sin(clampf(1.0 - (_state_until - now) / maxf(normal_duration, 0.01), 0.0, 1.0) * PI)
	_shield.call("update", _anim_stepped, _raise, bash)
	_anim_stepped = false


## A seek re-poses the whole rig from the new clip: the arms go back on the
## shield the same tick.
func _play_state_anim(which: StringName, duration: float) -> void:
	super(which, duration)
	if _shield != null:
		_anim_stepped = true


func _guard_up() -> bool:
	return _shield != null and not _dying and _raise > 0.6 and state != State.STAGGER \
		and not is_stunned() and _now() >= _guard_broken_until


## A blow travelling along `blow` comes at its front.
func _frontal(blow: Vector3) -> bool:
	var b := Vector3(blow.x, 0.0, blow.z)
	if b.length_squared() < 0.01:
		return false
	var facing := -global_basis.z
	facing.y = 0.0
	return facing.normalized().dot(b.normalized()) < -0.35


## Does the raised shield stand between `ward` and a blow along `blow`? (enemy.gd
## asks every guard before a skeleton takes a hit or a shove.)
func covers(ward: Node3D, blow: Vector3) -> bool:
	if not _guard_up() or not _frontal(blow):
		return false
	var b := Vector3(blow.x, 0.0, blow.z).normalized()
	var rel := global_position - ward.global_position
	rel.y = 0.0
	# How far toward where the blow came from it stands, and how far off its line.
	var ahead := rel.dot(-b)
	if ahead < 0.4 or ahead > 3.0:
		return false
	return (rel + b * ahead).length() < COVER_HALF


## The shield takes a blow -- its own, or one meant for its ward: the shield
## flares, the body swells, and only a chip of it gets through.
func block_for(amount: float, blow: Vector3) -> void:
	if _dying:
		return
	alert()
	_deflect()
	if _shield != null:
		_shield.call("flash")
	var b := Vector3(blow.x, 0.0, blow.z)
	if b.length_squared() > 0.01:
		_knockback += b.normalized() * 1.2
	_chip(amount * SHIELD_CHIP)


func _chip(amount: float) -> void:
	if amount <= 0.0 or _dying:
		return
	health = maxf(health - amount, 0.0)
	if health <= 0.0:
		_die()


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	if _shield != null and _guard_up() and _frontal(_from_direction):
		if amount >= GUARD_BREAK_DAMAGE:
			# Driven through: the guard is down and half the blow lands.
			_guard_broken_until = _now() + GUARD_BROKEN
			super(amount * 0.5, _from_direction)
			return
		block_for(amount, _from_direction)
		return
	super(amount, _from_direction)


func apply_knockback(impulse: Vector3, stun_time := 0.25) -> void:
	if _shield != null and _guard_up() and _frontal(impulse):
		if Vector2(impulse.x, impulse.z).length() < GUARD_BREAK_PUSH:
			_knockback += Vector3(impulse.x, 0.0, impulse.z) * 0.2
			return
		_guard_broken_until = _now() + GUARD_BROKEN
	super(impulse, stun_time)


## Guarding: braced on the line from its ward to the player, GUARD_AHEAD in front
## of the ward, facing the player. With nobody to guard, or the player at its
## shield, it comes on and bashes (enemy.gd's ordinary chase).
func _chase(delta: float, now: float, player: Node3D, flat: Vector3, _distance: float, gap: float) -> bool:
	if _shield == null:
		return false
	if gap <= normal_range + 0.4:
		return false
	if now >= _next_ward or (_ward != null and not _ward_ok(_ward)):
		_next_ward = now + WARD_EVERY
		_pick_ward()
	if _ward == null:
		return false
	var to_player := player.global_position - _ward.global_position
	to_player.y = 0.0
	# The player is on its ward already: go for the player.
	if to_player.length() < GUARD_AHEAD + 1.0:
		return false
	var post := _ward.global_position + to_player.normalized() * GUARD_AHEAD
	post = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, post)
	var to := post - global_position
	to.y = 0.0
	_face(flat)
	if to.length() < 0.35:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		_slide()
		return true
	var dir := to.normalized()
	if agent != null and to.length() > 2.0:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = post
		if not agent.is_navigation_finished():
			var step := agent.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.1:
				dir = step.normalized()
	var speed := move_speed * clampf(to.length() / 1.2, 0.35, 1.0)
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	_slide()
	return true


func _ward_ok(s: Node3D) -> bool:
	return is_instance_valid(s) and s.is_inside_tree() and s.get("_dying") != true and s.get("_dormant") != true \
		and s.global_position.distance_to(global_position) <= WARD_SEARCH


## The fellow to guard: the nearest within WARD_SEARCH, a crossbowman counting as
## half as far; never another shield, nor one another shield already guards.
func _pick_ward() -> void:
	if _ward != null and is_instance_valid(_ward) and _ward.has_meta(&"shield_guard") and _ward.get_meta(&"shield_guard") == self:
		_ward.remove_meta(&"shield_guard")
	_ward = null
	var best := INF
	for node in get_tree().get_nodes_in_group(&"skeletons"):
		var s := node as Node3D
		if s == null or s == self or s.is_in_group(&"shield_guards") or not _ward_ok(s):
			continue
		var held = s.get_meta(&"shield_guard") if s.has_meta(&"shield_guard") else null
		if held != null and held != self and is_instance_valid(held) and held.get("_dying") != true:
			continue
		var d := s.global_position.distance_to(global_position) * (0.5 if s.has_method("is_archer") else 1.0)
		if d < best:
			best = d
			_ward = s
	if _ward != null:
		_ward.set_meta(&"shield_guard", self)


func _die() -> void:
	if _ward != null and is_instance_valid(_ward) and _ward.has_meta(&"shield_guard") and _ward.get_meta(&"shield_guard") == self:
		_ward.remove_meta(&"shield_guard")
	_ward = null
	if _shield != null and is_instance_valid(_shield):
		_shield.call("drop")
	super()
