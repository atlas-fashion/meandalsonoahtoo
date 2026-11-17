@tool
class_name Swing
extends Resource
## One attack in a weapon's sequence (the timing-combat template, note 190). The grip
## draws back to windup_pose, strikes through strike_poses (the only time it can hit),
## then settles toward the weapon's rest pose. Pose names are the names of Marker3D
## children of the weapon's Poses node.

@export var display_name := "Swing"

@export_group("Path")
## Where the grip is drawn back to before striking.
@export var windup_pose: StringName = &"Right"
## Poses the blade passes through while it can hit, in order. The last one is where the
## strike ends. Add a middle pose to curve the arc.
@export var strike_poses: Array[StringName] = [&"Left"]
## How far the grip drifts back toward rest during recovery.
## 0 = stays where the strike ended, 1 = returns all the way to rest.
@export_range(0.0, 1.0, 0.01) var recovery_settle := 0.35

@export_group("Timing")
## Share of the swing spent in each phase. Only the ratios matter (they're normalised).
## The swing's total length comes from the weapon's hits_per_second, times
## `length_multiplier` for this swing alone.
## Windup: drawing back. Active: the blade can hit. Recovery: follow-through.
@export_range(0.0, 1.0, 0.01) var windup_share := 0.3
@export_range(0.0, 1.0, 0.01) var active_share := 0.2
@export_range(0.0, 1.0, 0.01) var recovery_share := 0.5
## This swing lasts this many weapon cycles (1 = 1 / hits_per_second). A slow special
## (the sword's heavy swipe, its wave slash) is one long swing on the same weapon.
@export_range(0.1, 10.0, 0.05, "or_greater") var length_multiplier := 1.0

@export_group("Easing")
## Optional curves shaping each phase (x = time 0..1, y = progress 0..1).
## Leave empty to use the built-in easing.
@export var windup_curve: Curve
@export var strike_curve: Curve
@export var recovery_curve: Curve

@export_group("Camera")
## Camera rotation the swing builds to by the end of its windup, in degrees
## (pitch, yaw, roll). Positive pitch looks up, positive yaw turns left, positive roll
## leans left. Uses the same timing and easing as the blade.
@export var camera_windup := Vector3.ZERO
## Camera rotation at the end of the strike. It eases back to zero during recovery.
@export var camera_strike := Vector3.ZERO

@export_group("Wielder")
## How far the wielder steps forward during the strike, in metres. The player is
## carried by it too (note 190: the heavy swipe's lurch, the spear's lunge).
@export var lunge_distance := 0.0
## How much of walking pace the wielder keeps through this swing (multiplies the
## weapon's Move Speed Multiplier).
@export_range(0.0, 1.0, 0.05) var move_multiplier := 1.0

@export_group("Combat")
## False for a swing whose blade deals nothing itself (the wave slash: the wave it
## throws is the damage). Its strike still animates and opens the hit window signals.
@export var hits := true
## Multiplies the weapon's damage for this swing.
@export var damage_multiplier := 1.0
## Multiplies the weapon's base knockback for this swing: final knockback = weapon
## Knockback × this. E.g. 1.5 for a heavy finishing blow.
@export_range(0.0, 5.0, 0.05) var knockback_multiplier := 1.0
## For this game's enemies (`apply_knockback(impulse, stun)`): how long a hit that
## staggers stuns, and the chance a hit staggers at all (player.gd `knock`).
@export var stun_time := 0.15
@export_range(0.0, 1.0, 0.01) var stagger_chance := 0.4


## Every pose name this swing uses, in path order.
func path_poses() -> Array[StringName]:
	var names: Array[StringName] = [windup_pose]
	names.append_array(strike_poses)
	return names


func end_pose() -> StringName:
	return strike_poses[-1] if not strike_poses.is_empty() else windup_pose


func windup_time(cycle: float) -> float:
	return cycle * length_multiplier * windup_share / _share_total()


func active_time(cycle: float) -> float:
	return cycle * length_multiplier * active_share / _share_total()


func recovery_time(cycle: float) -> float:
	return cycle * length_multiplier * recovery_share / _share_total()


func ease_windup(t: float) -> float:
	return windup_curve.sample_baked(t) if windup_curve else smoothstep(0.0, 1.0, t)


func ease_strike(t: float) -> float:
	# Default: fast out of the windup, decelerating into the follow-through.
	return strike_curve.sample_baked(t) if strike_curve else 1.0 - pow(1.0 - t, 3.0)


func ease_recovery(t: float) -> float:
	return recovery_curve.sample_baked(t) if recovery_curve else 1.0 - pow(1.0 - t, 2.0)


func _share_total() -> float:
	var total := windup_share + active_share + recovery_share
	return total if total > 0.0 else 1.0
