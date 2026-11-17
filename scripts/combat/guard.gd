class_name Guard
extends Node
## The player's guard and parry RULES: the timing-combat template's GuardArm (note 190),
## without its arm. The knight's own left arm shows it (first_person_arms.gd reads
## `player.is_blocking()` and the `guarded` signal), as it did before.
##
## An attack is winding up while it is "cued": this game's enemies call
## `player.parry_cue(self, listen)` as their wind-up reaches its tell, and the cue stays
## open for `listen` seconds, up to the blow (decrepit.gd, enforcer.gd, scout.gd,
## enemy.gd's skeletons...). A Weapon in the `weapons` group winding up counts the same.
##
## When a blow lands, resolve() decides:
## - PARRIED: the guard is up, and was PRESSED while that exact attack was winding up
##   (its cue open, matched by the cue's serial). No damage, no shove; the attacker
##   reels.
## - BLOCKED: the guard is up any other way. Damage × block_damage_multiplier, shove ×
##   block_knockback_multiplier.
## - HIT: the guard is down.
## Holding the guard up before the wind-up began never parries: it is the press that is
## timed. The guard ignores the blow's direction (the template's rule).

signal raised
signal lowered
signal parried(attacker: Node)
signal blocked(attacker: Node)

## Share of damage taken while blocking. 0.3 = 70% negated.
@export_range(0.0, 1.0, 0.01) var block_damage_multiplier := 0.3
## Movement speed multiplier while the guard is up.
@export_range(0.0, 1.0, 0.05) var move_speed_multiplier := 0.6
## Share of a blow's knockback taken when blocking it (driven back, but less).
@export_range(0.0, 1.0, 0.05) var block_knockback_multiplier := 0.5
## Share of a blow's knockback taken when parrying it.
@export_range(0.0, 1.0, 0.05) var parry_knockback_multiplier := 0.0

## The body enemy Weapons hit, to tell which of them are a threat to it.
var wielder: CollisionObject3D
## True while the guard button is held.
var is_up := false
## When it went up (Time seconds), for the arm's raise.
var up_since := -INF

## Open wind-ups: attacker instance id -> [serial, closes (Time seconds)].
var _cues := {}
var _cue_serial := 0
## Attacker instance id -> the cue serial it was winding up with when guard was pressed.
var _parry_marks := {}


## Guard button pressed. Marks every hostile attack that is winding up right now: if one
## of those lands while the guard is still up, it is parried.
func press() -> void:
	if is_up:
		return
	is_up = true
	up_since = _now()
	_parry_marks.clear()
	var now := _now()
	for id in _cues.keys():
		var cue: Array = _cues[id]
		if float(cue[1]) >= now:
			_parry_marks[id] = int(cue[0])
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(Weapon.GROUP):
			var weapon := node as Weapon
			if weapon and weapon.phase == Weapon.Phase.WINDUP and weapon.can_hit(wielder):
				_parry_marks[weapon.get_instance_id()] = -weapon.swing_serial - 1
	raised.emit()


## Guard button released (or dropped: a menu, a scene, death).
func release() -> void:
	if not is_up:
		return
	is_up = false
	_parry_marks.clear()
	lowered.emit()


## An attack's wind-up reached its tell: it can be parried by a press from now until
## its blow, `listen` seconds at most.
func open_cue(attacker: Node, listen: float) -> void:
	if attacker == null:
		return
	var now := _now()
	_cue_serial += 1
	_cues[attacker.get_instance_id()] = [_cue_serial, now + listen]
	# A press already made inside this same wind-up does not carry over: it must be
	# made while the attack winds up.
	for id in _cues.keys():
		if float(_cues[id][1]) < now - 5.0:
			_cues.erase(id)


## An attack broken off before its blow: its wind-up is over.
func forget_cue(attacker: Node) -> void:
	if attacker != null and is_instance_valid(attacker):
		_cues.erase(attacker.get_instance_id())


## Decides what a blow from `attacker` (a Node, a Weapon or null) does. Uses up the cue.
func resolve(attacker: Node) -> Weapon.HitResult:
	var key := -1
	var serial := 0
	if attacker != null and is_instance_valid(attacker):
		key = attacker.get_instance_id()
		var weapon := attacker as Weapon
		if weapon != null:
			serial = -weapon.swing_serial - 1
		elif _cues.has(key):
			serial = int(_cues[key][0])
		_cues.erase(key)
	if not is_up:
		return Weapon.HitResult.HIT
	if key >= 0 and serial != 0 and _parry_marks.get(key, 0) == serial:
		_parry_marks.erase(key)
		parried.emit(attacker)
		return Weapon.HitResult.PARRIED
	blocked.emit(attacker)
	return Weapon.HitResult.BLOCKED


## Whether `attacker` has a wind-up open right now (a press now would parry it).
func is_winding_up(attacker: Node) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	var cue = _cues.get(attacker.get_instance_id())
	return cue != null and float(cue[1]) >= _now()


## Movement speed multiplier the wielder should use right now.
func move_multiplier() -> float:
	return move_speed_multiplier if is_up else 1.0


func clear() -> void:
	_cues.clear()
	_parry_marks.clear()
	release()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
