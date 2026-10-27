extends CharacterBody3D

## First-person character: WASD moves relative to where you are facing, F
## jumps, Space (held) blocks, right click (held) is ghost mode, R drinks a potion, the mouse looks around,
## left click swings the sword, Escape releases the mouse.

## Walking pace, m/s. Was 5.0; brought down 15% on request (2026-10-01).
@export var move_speed := 4.25
@export var acceleration := 14.0
@export var jump_velocity := 5.0
## Grace period after walking off an edge in which a jump still counts. Long
## enough to forgive a late press, short enough that it never reads as a
## second jump.
@export var coyote_time := 0.13
@export var mouse_sensitivity := 0.003
## Pitch limits in degrees, kept just shy of straight up/down so the view
## never flips over.
@export var min_pitch := -89.0
@export var max_pitch := 89.0
## Lower than it was: the swings are much faster now, so damage per second is
## up even though each individual cut lands for less.
@export var attack_damage := 20.0

## A shove on every sword hit, so a connecting swing visibly moves what it hits.
@export var attack_push := 5.5
@export var attack_stun := 0.15

## Forward shove on every swing. Added straight to velocity -- the movement
## damping already bleeds a surge off at `acceleration`, so it needs no clock of
## its own and reads as a committed step rather than a dash.
@export var attack_lunge := 4.6
## Movement damping is multiplied by this while a swing runs, so the lunge bleeds
## off inside the stroke. These two are solved together: at normal damping the
## surge outlasts the whole swing and hides the slow-down, and at heavy damping
## the surge dies instantly and the step disappears. This pair gives roughly a
## third of a metre of travel with the last third of the stroke visibly slower.
@export var attack_damp_scale := 2.4
## How much of your walking speed you keep while a swing is running.
@export var attack_move_scale := 0.6
## Degrees the view kicks up on a swing, and how far it rolls with the stroke.
@export var attack_view_kick := 1.5
@export var attack_view_roll := 1.1
## Degrees the field of view snaps IN by on a swing. Small, and inward: this is
## a punch, not a zoom.
@export var attack_fov_kick := 2.2
## How long the swing's view punch takes to fall away.
@export var attack_kick_time := 0.18
## Extra kick when a swing actually connects, so a hit reads differently from a
## miss. Costs nothing -- it is the existing camera, not a screen effect.
@export var attack_hit_kick := 0.55

## Half the thickness of the slab the blade sweeps out for its hit test. The
## blade itself is a few millimetres; a little more makes a cut that grazes a
## limb count, without hitting what the blade did not pass through.
@export var blade_hit_thickness := 0.06

@export_group("Sweep trail")
## A thin white ribbon left by the sword's TIP while it cuts. Purely visual:
## turn it off and the sword hits exactly the same things.
@export var sweep_trail_enabled := true
## Seconds a point of the ribbon lasts before it has thinned away.
@export var sweep_trail_life := 0.12
## Half-width at the tip, metres.
@export var sweep_trail_width := 0.006
@export var sweep_trail_alpha := 0.85

@export_subgroup("Animation")
## Cross-fade between the idle, run and jump clips. Long enough that changing
## direction or leaving the ground eases rather than snaps.
@export var locomotion_blend := 0.22
## Cross-fade into and out of a swing. Kept short on purpose -- a swing that
## eases in reads as mushy and makes the hit window feel disconnected from it.
@export var attack_blend := 0.07
## Ground speed above which the run clip takes over from idle.
@export var run_anim_speed := 1.6

## Walls block the swing, so you cannot cleave through a corner of the maze.
@export var require_line_of_sight := true
## Layer the line-of-sight ray tests against: level geometry only.
@export_flags_3d_physics var geometry_mask := 2
@export var max_health := 100.0
## Grace period after taking a hit, so standing next to an enemy drains health
## at a readable rate instead of every frame.
@export var invulnerable_time := 0.6
## ...but a blow taken on the guard (blocked or parried) only this long: the
## grace is for a hit that hurts. At 0.6 the enforcer's swipe 2, landing 0.36 s
## after a blocked swipe 1, always met an invulnerable player (2026-10-17).
@export var guarded_invulnerable_time := 0.25
@export var respawn_delay := 1.5

@export_group("Ghost mode")
## Hold "dodge" (Shift): the player rises a little off the ground and moves at
## `ghost_speed_scale` x walking pace, passing through every enemy, while the
## bar runs down. It replaced a one-shot dash (2026-10-01).
@export var ghost_speed_scale := 2.5
## Seconds of ghost a full bar holds, and seconds to refill it from empty.
@export var ghost_duration := 2.0
@export var ghost_refill := 4.0
## The least bar a ghost can be started on, so a nearly empty bar does not
## flicker it on and off.
@export var ghost_min_start := 0.08
## Share of the whole bar taken the moment a ghost starts. No attacking while
## in it either: a ghost is for getting somewhere, not for fighting.
@export_range(0.0, 1.0) var ghost_entry_cost := 0.1
## Height it floats above the floor, and how quickly it rises to it.
@export var ghost_hover := 0.3
@export var ghost_hover_rate := 9.0
## How much harder it steers than walking, so 2.5x speed stays controllable.
@export var ghost_acceleration_scale := 2.0
## Share of incoming damage still taken while a ghost: 0.2 is 80% off.
@export_range(0.0, 1.0) var ghost_damage_taken := 0.2
## Ghost goes straight through anything alive. Walls and floors still stop it.
@export var dodge_phases_through_enemies := true
## How far around you the dash looks for things to pass through, checked every
## frame of the dash. Only needs to cover a frame's travel plus a body's width,
## but a little slack costs nothing and catches anything closing on you.
@export var dodge_phase_radius := 3.0
## Extra gap required before a body counts as cleared and turns solid again.
@export var dodge_phase_clearance := 0.2
## How far above a body counts as standing on it rather than being stuck in
## it. Anything you are up on stays solid: a chest you can climb has to hold
## your weight, or the mimic pretending to be one is a hole in the floor.
@export var dodge_phase_step_height := 0.6
## Longest ghost will keep something intangible after it ends. A backstop
## only: normally solidity returns the moment you step clear.
@export var dodge_phase_hold_max := 4.0

@export_group("Head movement")
## Very small, deliberately. This is meant to sit below conscious notice: you
## should feel that the view is alive, not see it moving.
@export var head_bob := true
## Breathing sway while standing still, in metres.
@export var idle_bob_height := 0.0045
@export var idle_bob_rate := 0.9
@export var idle_bob_roll_degrees := 0.14
@export var idle_bob_pitch_degrees := 0.1
## Stride bob while moving. The vertical runs at twice the stride, because
## there are two footfalls per cycle.
@export var walk_bob_height := 0.019
@export var walk_bob_sway := 0.013
@export var walk_bob_roll_degrees := 0.34
## A small nod on each footfall.
@export var walk_bob_pitch_degrees := 0.22
## Stride cycles per metre travelled, so the bob follows your actual speed
## rather than a fixed beat. At the player's 5 m/s this works out to a little
## over four footfalls a second -- a long, loping stride rather than a scurry.
@export var walk_bob_per_metre := 0.44
## Airborne: the view drifts rather than bobs, since nothing is hitting ground.
@export var air_bob_height := 0.007
@export var air_bob_rate := 1.4
## How quickly the bob changes character between standing, moving and airborne.
@export var bob_blend_rate := 6.0

@export_subgroup("Looseness")
## How unevenly alternate footfalls land. 0 is a metronome.
@export_range(0.0, 1.0) var bob_limp := 0.24
## A slow noise wander over the top of everything, as a fraction of the walk
## bob. This is what keeps the cycle from ever repeating exactly.
@export_range(0.0, 1.5) var bob_wander := 0.45
@export var bob_wander_rate := 0.55
## How fast the head catches up to where the bob says it should be. Lower is
## looser and heavier; high enough and it is rigid again.
@export var bob_response := 13.0

@export_subgroup("Dash feel")
## How far the view opens out at the moment of a dash, in degrees. Widening the
## field of view is what actually sells speed; the streaks are dressing.
@export var dash_fov_kick := 9.0
## How far the view banks into a sideways dash. Scaled by how sideways the dash
## actually is, so a straight-ahead dash does not tilt at all.
@export var dash_roll_degrees := 3.2
## How long the whole flourish takes to fall away. Kept a little longer than
## the dash itself so it settles rather than stopping dead.
@export var dash_effect_time := 0.32
## Brightness of the streaks at the rim of the view. Kept faint: they are
## peripheral motion, not something to read.
@export_range(0.0, 1.0) var dash_streak_strength := 0.26
## How long the world takes to drain of colour at the start of a dash, and to
## get it back at the end.
@export var dash_desaturate_in := 0.07
@export var dash_desaturate_out := 0.22

@export_group("Landing bob")
## Downward camera dip on landing, in metres at full strength. Reuses the
## swing's decaying-scalar approach (see `attack_view_kick` and `_swing_kick`)
## rather than a second camera-shake system -- one more scalar decaying 0..1,
## composed straight onto the head in _update_head, bypassing the eased
## walk/idle bob so the impact reads as sudden rather than smoothed.
## How much authority airborne input has over velocity, as a fraction of the
## ground acceleration. Mid-air steering is full -- direction and speed both
## -- it is just slewed toward the wish velocity at this fraction of the
## ground rate rather than snapped to it, so a jump can turn and change pace
## without ever feeling as tight as the ground, and a knockback is not
## cancelled the instant a key is pressed.
@export_range(0.0, 1.0, 0.05) var air_damp_scale := 0.45
@export var landing_bob_height := 0.11
## Degrees the view pitches down on a hard landing.
@export var landing_view_kick := 3.2
## How long the landing dip takes to fall away.
@export var landing_kick_time := 0.32
## Downward speed, in m/s, at which a landing counts as a full-strength
## impact -- a long fall hits with everything below; a small hop barely
## registers. This is what impact speed is scaled against. An ordinary jump
## lands at about 5 m/s, which is roughly half strength.
@export var landing_speed_reference := 9.0
## Downward speed below which a landing produces no bob at all -- an ordinary
## footfall off a low step or a short hop, not worth a camera reaction.
@export var landing_speed_min := 1.5

@export_group("Jump takeoff")
## The push-off: the head dips as the legs drive, then comes up with the body.
@export var jump_bob_height := 0.045
## Degrees the view tips UP as you leave the ground.
@export var jump_view_kick := 1.6
## Degrees the field of view opens out on takeoff.
@export var jump_fov_kick := 2.0
## How long the takeoff flourish lasts.
@export var jump_kick_time := 0.38

@export_group("Damage indicator")
## How long the marker showing where a hit came from stays up.
@export var damage_mark_time := 0.9
## Brightness at the very worst hit.
##
## Pushed to full. The level is lit by red torches under a maroon sky with red
## fog, so a gentle red vignette is camouflage -- earlier versions were drawing
## correctly at 0.44 alpha and still went unnoticed in play. It needs to be
## louder than the room it sits in.
@export_range(0.0, 1.0) var damage_mark_strength := 1.0
## Damage that counts as a full-strength hit. Anything at or above this paints
## the marker at full size and brightness.
@export var damage_mark_reference := 45.0
## How wide the arc gets, in degrees, for the smallest and the largest hits.
@export var damage_mark_spread_min := 34.0
@export var damage_mark_spread_max := 96.0

@export_group("Jump slam")
## The heavy attack, Shift + right click. In mid-air it drives you straight down
## and the landing detonates in a ring around you; on the ground there is no
## jump -- the sword is raised overhead and brought down where you stand, with
## the same blast.
@export var slam_damage := 150.0
## Gates the blast only. The dive to the ground is always available, so the slam
## doubles as a way to get down fast.
@export var slam_cooldown := 20.0
@export var slam_radius := 4.5
## Colour and size of the slam's ring when the blast actually lands...
@export var slam_ring_color := Color(0.95, 0.97, 1.0)
## ...and when it is still on cooldown: a small pale puff of dust instead.
@export var slam_dud_color := Color(0.678431, 0.717647, 0.768627)
@export var slam_dud_radius := 1.8
@export var slam_descent_speed := 30.0
@export var slam_push := 9.0
@export var slam_stun := 0.35
## Safety net in case a slam never finds ground.
@export var slam_timeout := 3.0
## After the impact: how long the player is down and cannot move, how far the
## view drops while they are, and how violent the shake is.
@export var slam_recover_time := 1.0
## On the ground: how long the sword is raised overhead before it comes down.
@export var slam_ground_windup := 0.22
@export var slam_crouch_depth := 0.38
@export var slam_shake_time := 0.45
@export var slam_shake_strength := 1.0
## The ring painted on the floor under a dive, showing what the blast will catch.
@export var slam_marker_color := Color(0.92, 0.95, 1.0)

@export_group("Hunted by the Remnant")
## While the Remnant hunts the player (`set_remnant_hunt`, driven by the HUD and
## eased in over ~1.5 s): a fine tremble of the view -- this much offset
## (metres) and roll (degrees) at full -- and the field of view slowly drawn in
## by `remnant_fov_in` degrees, breathing `remnant_fov_breathe` either side
## every `remnant_fov_period` seconds. Meant to be felt, not seen.
@export var remnant_shake := 0.005
@export var remnant_shake_roll := 0.45
@export var remnant_fov_in := 2.5
@export var remnant_fov_breathe := 0.8
@export var remnant_fov_period := 5.0

@export_group("Low health")
## Below this share of max health the world starts losing its colour...
@export_range(0.0, 1.0) var low_health_desaturate_from := 0.5
## ...down to this share of its saturation at the brink of death.
@export_range(0.0, 1.0) var low_health_saturation := 0.12

@export_group("Drinking")
## How long a potion takes to drink, and the share of walking pace kept meanwhile.
@export var drink_time := 3.0
@export_range(0.0, 1.0) var drink_move_scale := 0.25

@export_group("Block and parry")
## Hold right click ("block") with any weapon in hand (`Inventory.is_weapon`):
## the guard comes up across the body, the player slows, and a hit from the front does
## `block_damage_taken` of its damage. A hit landing within `parry_window` of
## the block going up is PARRIED instead: `parry_damage_taken` of it (none), the
## attacker takes `parry_reflect` of its own blow back and is thrown back and
## staggered, with a purple flash and a beat of hit-stop.
@export_range(0.0, 1.0) var block_damage_taken := 0.1
@export var parry_window := 0.5
@export_range(0.0, 1.0) var parry_damage_taken := 0.0
@export_range(0.0, 2.0) var parry_reflect := 0.5
@export var parry_push := 14.0
@export var parry_stun := 0.9
## Half-angle of the front the sword covers, degrees. A blow from behind or
## from the side lands in full.
@export var block_arc := 75.0
@export var block_move_scale := 0.55
@export var parry_color := Color(0.66, 0.28, 1.0)
@export var block_spark_color := Color(1.0, 0.82, 0.55)

@export_group("Spin")
## Q with the sword: one full circle round the player (`_start_spin`). It cuts
## for `attack_damage` like a cut but throws harder -- `spin_push` against a
## cut's `attack_push` -- and stuns longer.
@export var spin_push := 11.0
@export var spin_stun := 0.35
## The camera's effort through it (`_spin_effort`): the lean into the turn
## (degrees), the crouch (metres) and the rush of field of view (degrees).
@export var spin_effort_roll := 6.0
@export var spin_effort_drop := 0.07
@export var spin_effort_fov := 6.0

@export_group("Lunge look")
## The lunge's look (the spear's dash): white speed lines rushing outward (the
## HUD's LungeLines, `lunge_intensity()`), and the view opening out by this many
## degrees, over `lunge_effect_time` seconds.
@export var lunge_fov_kick := 7.0
@export var lunge_effect_time := 0.45

@export_group("Haft strike camera")
## Striking a bomber is a moment: the view turns part of the way onto it, snaps
## in and tilts as the pommel lands, and the world drops into slow motion while
## it shatters, then everything eases back to exactly where the player was
## looking. All timings here are REAL seconds.
@export_range(0.05, 1.0) var haft_slowmo_scale := 0.18
## Held at the slowest, then eased back to full speed.
@export var haft_slowmo_hold := 0.16
@export var haft_slowmo_return := 0.45
## Degrees the field of view closes in by at the contact.
@export var haft_zoom := 14.0
## Degrees of dutch tilt toward the side struck.
@export var haft_roll := 5.0
## How much of the way the view turns onto the bomber, and the most it turns.
@export_range(0.0, 1.0) var haft_aim_share := 0.55
@export var haft_aim_max := 28.0
## How long the camera takes to settle back once the slow motion lets go.
@export var haft_settle_time := 0.55

@export_group("Inventory")
## The kinds of consumable that exist. Each is carried in `inventory` under the
## snake_case of its item_name ("Health Potion" -> &"health_potion"), which
## must match an entry in Inventory.ITEMS.
@export var consumables: Array[ConsumableType] = [
	preload("res://resources/health_potion.tres"),
]
## How many of each consumable the player starts with -- and is topped back
## up to on respawn -- matched to `consumables` by position.
@export var starting_counts: Array[int] = [3]

@export_group("Sword out of view")
## How close to the eye the sword is DRAWN, as a fraction of its real depth
## (`use_z_clip_scale` on its materials). It looks the same size and is lit the
## same, but is in front of every wall and enemy: nothing can cover it.
@export_range(0.05, 1.0) var sword_draw_depth := 0.12
## Where a put-away sword goes, relative to its pivot in the view: this far
## down and back, tipped this many radians back over the hand.
@export var sword_duck_drop := 0.95
@export var sword_duck_back := 0.25
@export var sword_duck_tilt := 0.9
## The spring's time to put the sword away, and to bring it back up.
@export var sword_duck_smooth_up := 0.045
@export var sword_duck_smooth_down := 0.14

signal health_changed(current: float, maximum: float)
signal healed(amount: float, source_name: String)
signal died
signal inventory_changed
signal consumable_gained(type: ConsumableType, amount: int)
signal dodged
## Emitted after death has returned the player to the start. The level builder
## uses this to restore the world.
signal respawned
## Treasure looted from the bone cages. Kept through death: it is earned.
signal currency_changed(total: int, gained: int)
## The weapon in hand changed: its weapon-wheel slot (0 up, 1 right, 2 down, 3 left).
signal selection_changed(slot: int)
## A sword or slam hit connected -- the HUD flashes the crosshair.
signal hit_landed(target: Node3D)
## The guard went up or came down, with any weapon. The hook for the shield
## that will pop out of the haft: up on true, away on false. `guard_amount()`
## gives the eased 0..1 for animating it, and `guarded` fires as it takes a blow.
signal guard_changed(raised: bool)
## A drink was cut short by an attack or a hit; `healed` is all it gave.
signal drink_interrupted(healed: float)
## A scripted stab (`stab_at`) has just driven home.
signal stab_landed
## The scripted stab's wrench, the beat after contact: what the scene breaks on.
signal stab_wrenched
## Something that is not a consumable or coins was picked up (`add_item`).
signal item_gained(id: StringName, amount: int)
## A blow was blocked (`parried` false) or parried (true).
signal guarded(parried: bool, attacker: Node3D)

## Everything carried: the weapon wheel (0-3), the quick-item wheel (4-7), then the bag. See inventory.gd.
var inventory := Inventory.new()
## Which weapon-wheel slot is in hand. The sword is drawn only while it is the sword.
var selected_slot := 0
## True while the inventory screen is open: no look, attack or movement input.
var ui_open := false
## True while a scene needs the player's hands (kicking a door in): whatever is
## held is put away, as the sword is when it would go into a wall.
var hands_busy := false
## True while the view is a robot rat's (rat_control.gd): the body stands where
## it was and takes no movement, look or attack input -- the rat does.
var remote_view := false
## Live rats thrown and the robot rat driven (scripts/rat_control.gd).
var rats: Node3D

## CO-OP (coop.gd, split_screen.gd): 0 is player 1 (keyboard and mouse, the
## left half), 1 player 2 (a controller, the right half). Player 2 is in
## scenes/main.tscn always and takes itself away outside co-op.
@export var player_index := 0
var _discarded := false
## This player as the other one sees them (coop_avatar.gd), co-op only.
var _avatar: Node3D
## The visual layer this player's first-person pieces are drawn on, co-op only.
var _viewmodel_layer := 0
var _layer_sweep := 0.0


func _enter_tree() -> void:
	if player_index == 1 and not Coop.active:
		# One player: player 2 is not here at all.
		_discarded = true
		remove_from_group(&"player")
		process_mode = Node.PROCESS_MODE_DISABLED
		queue_free()
		return
	Coop.register(self)
	# Co-op: the players pass through each other -- in a one-cell corridor
	# neither could get by, and starting on one spot would throw them apart.
	for other in Coop.all():
		if other != self:
			add_collision_exception_with(other)
			(other as PhysicsBody3D).add_collision_exception_with(self)


func _exit_tree() -> void:
	Coop.unregister(self)


## Co-op: this half's own Environment (split_screen.gd), so a dash or low
## health greys only this player's view (`_update_colour`).
func use_view_environment(env: Environment) -> void:
	if env == null:
		return
	_environment = env
	_base_saturation = env.adjustment_saturation


## Co-op: this player's first-person pieces onto `viewmodel` (only their own
## half draws it), and their stand-in body for the other half on `avatar`.
func set_view_layers(viewmodel: int, avatar: int) -> void:
	_viewmodel_layer = viewmodel
	_sweep_view_layers()
	if _avatar == null:
		_avatar = Node3D.new()
		_avatar.set_script(load("res://scripts/coop_avatar.gd"))
		# Built, layers and all, before it is in the scene (see above).
		_avatar.call("setup", self, avatar)
		add_child(_avatar)


## Everything drawn under the head -- sword, spear, potion, the torch in the
## hand, rats in the hand -- onto this player's viewmodel layer. Re-run now and
## then: some of it is built later (rat_control.gd, held_potion.gd).
func _sweep_view_layers() -> void:
	if _viewmodel_layer == 0:
		return
	for g in head.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi.layers != _viewmodel_layer:
			# Hidden while it changes: a lit instance whose layers change in
			# place is left paired with its lights ("BUG, indexing did not
			# unpair geometries from light", a flood of them).
			var shown := gi.visible
			gi.visible = false
			gi.layers = _viewmodel_layer
			gi.visible = shown

## Coins are carried in the inventory like anything else; this is their total.
var currency: int:
	get:
		return inventory.count(&"coins")

## True during a scripted moment (looting a bone cage): no input, no movement,
## no damage and no knockback, so it plays out and cannot be cancelled.
var in_cutscene := false


## --- Held (note 96) ---------------------------------------------------------------
## Something has hold of them -- the surgical table's claw, carrying them to the
## table and strapping them down (surgical_table.gd). The holder places them
## every frame; they can only look about and STRUGGLE (any fighting key), and
## blows still land. A scripted moment underneath (`in_cutscene`), so nothing
## else drives them meanwhile.
var restrained_by: Node3D = null
## Struggles since they were taken; the holder reads it.
var struggles := 0
## (drop m, pitch deg, roll deg) the holder sets, as `_knock_view`: strapped
## to the table the view is down on its back, looking up.
var restrain_view := Vector3.ZERO


func restrain(by: Node3D) -> void:
	if _dead:
		return
	unlatch()
	begin_cutscene(true)
	restrained_by = by
	struggles = 0


## Let go: thrown off with `push`.
func release(push := Vector3.ZERO) -> void:
	if restrained_by == null:
		return
	restrained_by = null
	restrain_view = Vector3.ZERO
	in_cutscene = false
	velocity = push


func is_restrained() -> bool:
	return restrained_by != null and is_instance_valid(restrained_by)


## --- Latched onto a vat (2026-10-25, note 106) -------------------------------------
##
## E on a surgery vat grabs it (surgery_vat.gd `grab`): both hands on it, the
## weapon put away (`hands_busy`), no attacking, guarding or jumping. The vat
## moves them with it and reads their keys -- forward pushes, back pulls, the
## sides turn it (only while it is not heaved) -- until E is let go (note 111:
## held, not toggled), a blow that knocks them down, the claw, a scene, or
## death lets go (`unlatch`). Their view keeps its yaw meanwhile.
var latched_to: Node3D = null


func latch(vat: Node3D) -> void:
	if latched_to == vat:
		return
	unlatch()
	latched_to = vat
	hands_busy = true
	_end_block()
	velocity = Vector3.ZERO


func unlatch() -> void:
	if latched_to == null:
		return
	var v := latched_to
	latched_to = null
	hands_busy = false
	if is_instance_valid(v) and v.has_method("release"):
		v.call("release", self)


## `hurts`: the scene happens in the world rather than outside it, and blows
## still land (the bone cages); otherwise the player cannot be hurt in it.
func begin_cutscene(hurts := false) -> void:
	unlatch()
	in_cutscene = true
	_cutscene_hurts = hurts
	_ghosting = false
	_end_block()
	velocity.x = 0.0
	velocity.z = 0.0


## --- The spear -------------------------------------------------------------------
##
## scripts/spear.gd does its own fighting; the player routes the keys to it
## while it is in hand (`_spear_free`) and moves the body for its dash.

var spear: Node3D
var _spear_dash_until := 0.0
var _spear_dash_vel := Vector3.ZERO


## Nothing in the way of using the spear right now.
func _spear_free() -> bool:
	return not _blocking and not _ghosting and not is_drinking() and not _slamming and not hands_busy \
		and not _dead and _now() >= _slam_recover_until


## Carried forward at `vel` for `time` s, steering locked, with the lunge's
## speed lines and widened view.
func begin_spear_dash(vel: Vector3, time: float) -> void:
	_spear_dash_vel = vel
	_spear_dash_until = _now() + time
	_lunge_age = 0.0


func is_spear_dashing() -> bool:
	return _now() < _spear_dash_until


## --- The axe (2026-10-20) ---------------------------------------------------------
##
## scripts/axe.gd does its own fighting, as the spear does; the player routes
## the keys to it (free when `_spear_free` is), holds the body still for the
## berserk roar and the throw's wind-up, slows it while the axe is in hand and
## speeds it up while berserk.

var axe: Node3D


## The berserk roar and the throw's wind-up: planted where it stands (axe.gd
## `ROAR_TIME`, `THROW_WINDUP`).
func _axe_planted() -> bool:
	return axe != null and (axe.is_roaring() or axe.is_winding_up())


## Walking pace multiplier: axe.gd `CARRY_SPEED` with the axe in hand; while
## berserk, ghost mode's pace (`ghost_speed_scale`) instead, the axe's weight
## and all (note 91).
func _axe_speed() -> float:
	if axe == null:
		return 1.0
	var carry: float = axe.CARRY_SPEED if held_item() == &"axe" and not axe.is_away() else 1.0
	return lerpf(carry, ghost_speed_scale, axe.berserk_amount())


## Thrown and not yet caught: the player has no weapon at all.
func axe_away() -> bool:
	return axe != null and axe.is_away()


## The spear's ordinary stab is put behind the shoulder: the player walks at
## `spear_stab_move_scale` while one is out, and the view drives into it -- a
## push forward, a dip, a nod, the shoulders rolling to alternate sides, the view
## drawn in -- with a strain that builds as the stabs keep coming
## (`_stab_effort`, composed in `_update_head` / `_update_dash_view`).
@export_range(0.0, 1.0) var spear_stab_move_scale := 0.45
@export var spear_effort_push := 0.07
@export var spear_effort_drop := 0.03
@export var spear_effort_pitch := 1.6
@export var spear_effort_roll := 2.4
@export var spear_effort_fov := 2.6
var _stab_strain := 0.0
var _stab_k := 0.0
var _stab_fov := 0.0


## spear.gd, as each stab is driven out.
func spear_stabbed() -> void:
	_stab_strain = minf(_stab_strain + 0.28, 1.0)


func _spear_stabbing() -> bool:
	return spear != null and spear.has_method("stab_time") and float(spear.call("stab_time")) >= 0.0


## (roll deg, pitch deg, drop m, fov deg) for the spear's stab; `_stab_k` is
## left as the drive, 0..1, for the push forward.
func _stab_effort() -> Vector4:
	_stab_k = 0.0
	if spear == null or not spear.has_method("stab_time"):
		return Vector4.ZERO
	var t: float = spear.call("stab_time")
	if t < 0.0 and _stab_strain <= 0.0:
		return Vector4.ZERO
	if t >= 0.0:
		var out: float = spear.get("STAB_OUT")
		var back: float = spear.get("STAB_BACK")
		if t < out:
			var r := t / out
			_stab_k = 1.0 - (1.0 - r) * (1.0 - r)
		else:
			_stab_k = 1.0 - smoothstep(out, back, t)
	var side: float = spear.get("stab_side")
	var k := _stab_k
	var e := Vector4(spear_effort_roll * side * k, -spear_effort_pitch * k, spear_effort_drop * k,
		-spear_effort_fov * k)
	# Kept at it, the arms start to shake.
	if _stab_strain > 0.0:
		var n := float(Time.get_ticks_msec()) / 1000.0 * 45.0
		var s := _stab_strain * _stab_strain
		e.x += _bob_noise.get_noise_2d(n, 131.0) * 1.1 * s
		e.y += _bob_noise.get_noise_2d(n, 157.0) * 0.6 * s
		e.z += absf(_bob_noise.get_noise_2d(n, 173.0)) * 0.008 * s
	return e


## --- Staggering -------------------------------------------------------------------
##
## Whether a blow STAGGERS what it hits is a roll, per hit, at the stroke's own
## chance. A stagger throws the body back and cancels whatever it was doing -- a
## wind-up, a swing already coming, a bow being drawn, a beam -- so it has to
## start its attack over (enemy.gd `_staggered`). A blow that does not stagger
## still hurts but neither moves nor interrupts it.
##
## Sword: cut `slash_stagger_chance`, spin and slam always. Spear (spear.gd):
## stab 10%, dash and the thrown spear's blast always.
@export_range(0.0, 1.0) var slash_stagger_chance := 0.4
@export_range(0.0, 1.0) var spin_stagger_chance := 1.0
@export_range(0.0, 1.0) var slam_stagger_chance := 1.0
## The shortest a stagger lasts, whatever the stroke's own stun.
@export var stagger_min_time := 0.45
## Emitted for every stagger the player causes.
signal staggered_enemy(body: Node)


## Rolls `chance`; on a stagger shoves `body` along `impulse` and interrupts it
## for `stun` (at least `stagger_min_time`). Returns whether it staggered.
func knock(body: Node, impulse: Vector3, stun: float, chance: float) -> bool:
	if body == null or not is_instance_valid(body) or not body.has_method("apply_knockback"):
		return false
	if chance < 1.0 and randf() >= chance:
		return false
	body.call("apply_knockback", impulse, maxf(stun, stagger_min_time))
	staggered_enemy.emit(body)
	return true


## --- Water ---------------------------------------------------------------------
##
## Anything in the group "water" with `water_surface_at(point) -> float` (the
## drowning court, puzzle_room.gd) can flood where the player stands. Deeper
## than `SWIM_FLOAT` they float with their head out (feet that far under) and
## tread water at `swim_speed_scale`; jump works from the water, which is how
## the court's ledges are reached. Shallower, they wade at `wade_speed_scale`.

const SWIM_FLOAT := 0.95
const CornerSlip := preload("res://scripts/corner_slip.gd")
@export var swim_speed_scale := 0.55
@export var wade_speed_scale := 0.7
## Set by whatever the player is carrying (a body to the weighing room's
## scales): 1 is unburdened.
var carry_speed_scale := 1.0
var _swimming := false


## Metres of water over the player's feet, or -INF on dry land.
func water_depth() -> float:
	var surface := -INF
	for w in get_tree().get_nodes_in_group(&"water"):
		surface = maxf(surface, float(w.call("water_surface_at", global_position)))
	return surface - global_position.y if surface > -INF else -INF


func is_swimming() -> bool:
	return _swimming


## --- Hiding ---------------------------------------------------------------------
##
## Shut in a hiding place (`hiding_spot.gd`): the body is put inside it with its
## collision off and held still, the hands are empty, nothing can hurt it
## (`take_damage`, `drain_health`) and nothing can see it (`is_hidden()`, read
## by the Remnant, the enemies and `Interact.looked_at`). The view can still turn,
## but only out through the doors.

signal hidden_changed(hidden: bool)

const HIDE_LOOK_YAW := 0.95
const HIDE_LOOK_PITCH := 0.6

var _hidden_in: Node3D = null
var _hide_yaw := 0.0


func is_hidden() -> bool:
	return _hidden_in != null and is_instance_valid(_hidden_in)


func hidden_in() -> Node3D:
	return _hidden_in if is_hidden() else null


func hide_in(spot: Node3D, at: Vector3, yaw: float) -> void:
	unlatch()
	_end_block()
	_cancel_drink()
	_ghosting = false
	_attacking = false
	_hidden_in = spot
	_hide_yaw = yaw
	global_position = at
	velocity = Vector3.ZERO
	rotation.y = yaw
	_look_pitch = 0.0
	hands_busy = true
	_set_body_solid(false)
	hidden_changed.emit(true)


func leave_hiding(at: Vector3, yaw: float) -> void:
	var was := is_hidden()
	_hidden_in = null
	global_position = at
	velocity = Vector3.ZERO
	rotation.y = yaw
	_look_pitch = 0.0
	hands_busy = false
	_set_body_solid(true)
	if was:
		hidden_changed.emit(false)


## --- Ladders (manhole.gd, 2026-10-15) ---------------------------------------------
##
## On a ladder the body is moved by the ladder's scene (`global_position`
## written each frame), not by physics: collision off, no input, nothing in the
## hands. It can still be hurt (a scene in the world).

var climbing := false


func begin_climb() -> void:
	begin_cutscene(true)
	_cancel_drink()
	climbing = true
	hands_busy = true
	velocity = Vector3.ZERO
	_set_body_solid(false)


## Faces the body to `yaw` and the view to `pitch` at once (for a ladder).
func climb_face(yaw: float, pitch: float) -> void:
	rotation.y = yaw
	_look_pitch = pitch


func end_climb() -> void:
	if not climbing:
		return
	climbing = false
	hands_busy = false
	velocity = Vector3.ZERO
	_set_body_solid(true)
	# The teleport down the ladder is not a fall.
	_was_grounded = true
	_land_kick = 0.0
	end_cutscene()


func _set_body_solid(solid: bool) -> void:
	var shape := get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred(&"disabled", not solid)


func end_cutscene() -> void:
	in_cutscene = false
	_cutscene_hurts = false
	_scene_walk_target = null
	_scene_look = null
	scene_frame(0.0, 0.0)
	scene_lean(Vector3.ZERO, 9.0)


## --- Scene camera ----------------------------------------------------------------
##
## For scenes: `scene_look_at` holds the view on a point in the world -- the body
## turns to it and the pitch follows, eased, whatever the scene is doing,
## walking included -- and `scene_frame` pushes the view in (degrees of field
## of view taken off) and tilts it. Both are eased toward, on the real clock,
## so a hit-stop does not freeze the camera.

var _scene_look = null
var _scene_look_rate := 6.0
var _scene_zoom := 0.0
var _scene_zoom_goal := 0.0
var _scene_roll := 0.0
var _scene_roll_goal := 0.0
var _scene_frame_rate := 3.0


## `point` is a world position, or null to let go.
func scene_look_at(point: Variant, rate := 6.0) -> void:
	_scene_look = point
	_scene_look_rate = rate


func scene_frame(zoom_degrees: float, roll_degrees: float, rate := 3.0) -> void:
	_scene_zoom_goal = zoom_degrees
	_scene_roll_goal = roll_degrees
	_scene_frame_rate = rate


## Moves the eye off its rest in a scene (body space: +X right, +Y up, -Z
## forward) -- leaning in over the rim of a cart, crouching to a lock --
## eased on the real clock. `end_cutscene` eases it home.
var _scene_lean := Vector3.ZERO
var _scene_lean_goal := Vector3.ZERO
var _scene_lean_rate := 5.0


func scene_lean(offset: Vector3, rate := 5.0) -> void:
	_scene_lean_goal = offset
	_scene_lean_rate = rate


func _update_scene_camera() -> void:
	var real := minf(get_process_delta_time() / maxf(Engine.time_scale, 0.001), 0.1)
	_scene_lean = _scene_lean.lerp(_scene_lean_goal, 1.0 - exp(-_scene_lean_rate * real))
	var k := 1.0 - exp(-_scene_frame_rate * real)
	_scene_zoom = lerpf(_scene_zoom, _scene_zoom_goal, k)
	_scene_roll = lerpf(_scene_roll, _scene_roll_goal, k)
	if absf(_scene_zoom - _scene_zoom_goal) < 0.01:
		_scene_zoom = _scene_zoom_goal
	if absf(_scene_roll - _scene_roll_goal) < 0.01:
		_scene_roll = _scene_roll_goal
	if _scene_look == null:
		return
	var to: Vector3 = (_scene_look as Vector3) - camera.global_position
	if to.length_squared() < 0.0001:
		return
	var a := 1.0 - exp(-_scene_look_rate * real)
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), a)
	_look_pitch = lerpf(_look_pitch, atan2(to.y, Vector2(to.x, to.z).length()), a)


## Emitted when a `scene_walk_to` arrives, gives up, or is cut short by death.
signal scene_walk_finished


## During a scene: walks the player to `target` at walking pace, turning to
## face the way they go, with the ordinary head bob. Finishes on arrival, after
## `timeout` seconds, or if they stop making headway (against a wall or an
## enemy); listen for `scene_walk_finished`.
func scene_walk_to(target: Vector3, timeout := 4.0) -> void:
	_scene_walk_target = target
	_scene_walk_until = _now() + timeout
	_scene_walk_stuck = 0.0


func _scene_walk(delta: float) -> void:
	var target: Vector3 = _scene_walk_target
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.12 or _now() > _scene_walk_until or _scene_walk_stuck > 0.6:
		_scene_walk_target = null
		velocity.x = 0.0
		velocity.z = 0.0
		scene_walk_finished.emit()
		return
	var dir := to / dist
	# Easing into the last half metre, so it does not stop dead.
	var speed := move_speed * clampf(dist * 2.5, 0.35, 1.0)
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	# Facing the way they go -- unless the scene is holding the view on something,
	# in which case they walk there still looking at it.
	if _scene_look == null:
		var yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-8.0 * delta))
		_look_pitch = lerpf(_look_pitch, -0.08, 1.0 - exp(-4.0 * delta))
	var before := global_position
	if not is_on_floor():
		velocity.y += get_gravity().y * delta
	move_and_slide()
	var made := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_scene_walk_stuck = _scene_walk_stuck + delta if made < speed * delta * 0.2 else 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var sweep_trail: MeshInstance3D = get_node_or_null("SweepTrail")
## The Hitbox Area3D is the editable sword volume -- move or resize it in the
## editor and the swing follows. Its overlaps are resolved with an explicit
## shape query rather than area monitoring, which does not report the static
## bodies the targets are built from.
@onready var hitbox: Area3D = $Head/SwordPivot/Hitbox
@onready var hitbox_shape: CollisionShape3D = $Head/SwordPivot/Hitbox/CollisionShape3D
## Pre-authored in the scene so its transparent shader is compiled at load;
## building the material at runtime would stall the first slam.
@onready var slam_ring: MeshInstance3D = $SlamRing

## Attacks alternate between these two so repeated clicks read as a combo.
const ATTACKS: Array[StringName] = [&"slash", &"chop"]
## The clips chosen by how you are moving rather than by what you pressed. All
## three loop, so `animation_finished` only ever fires for an attack.
const LOCOMOTION: Array[StringName] = [&"idle", &"run", &"jump"]

var _attacking := false
var _next_attack := 0
## True only during the active frames of a swing.
var _hit_window_open := false
## Bodies already hit by the current swing, so one swing deals damage once.
var _hit_this_swing: Array[Node3D] = []

var health := 0.0
var _invulnerable_until := 0.0
var _spawn_point := Vector3.ZERO
var _dead := false

@onready var sword_pivot: Node3D = $Head/SwordPivot
@onready var sword_model: Node3D = get_node_or_null("Head/SwordPivot/Sword")
## The sword model's own transform under its pivot, which the duck is built
## from fresh each frame, so it can never compound.
var _sword_rest := Transform3D.IDENTITY
## 0 = in hand, 1 = put away out of view.
var _sword_duck := 0.0
## The put-away spring's speed.
var _duck_vel := 0.0
## The potion held in the sword's place while a potion slot is selected.
var _held_potion: Node3D

## Latest moment a jump will still be honoured after leaving the ground.
var _coyote_until := 0.0
## Ghost mode: whether it is on, the bar (1 full, 0 empty), and whether the
## key has to be let go before it can start again (after running the bar dry,
## or after it was held through a menu, a scene, a death or a lost focus --
## note 113).
var _ghosting := false
var _ghost_meter := 1.0
var _ghost_locked := true
## Last physics frame the player was in play, and whether this frame follows a
## gap in that (`_physics_process`): a key held across the gap needs a fresh press.
var _ghost_frame := -10
var _ghost_resumed := false
## Pad device ids `_pad_held` asks (Godot's joypad slots).
const PAD_SLOTS := 16
## 1.0 while a ghost is on, decaying to 0 after. One clock drives the field of
## view, the bank and the HUD's streaks, so they can never drift apart.
var _dash_view := 0.0
## -1 for a dash straight left, +1 straight right, 0 dead ahead.
var _dash_lateral := 0.0
var _base_fov := 75.0
## Decaying 0..1 driving the swing's view punch.
var _swing_kick := 0.0
## +1 or -1, so alternating strokes roll the view opposite ways.
var _swing_roll := 1.0
## Decaying 0..1 driving the landing dip -- the same pattern as _swing_kick
## above, just triggered by a landing instead of a sword stroke.
var _land_kick := 0.0
## How hard the landing that set _land_kick off was, 0..1. Multiplies
## landing_bob_height/landing_view_kick so a long fall hits harder than a hop.
var _land_strength := 0.0
## Decaying 1..0 driving the jump takeoff flourish.
var _jump_kick := 0.0
## Grounded state as of the end of the previous physics frame. A landing is
## the transition from false to true here, not merely "on the floor now" --
## walking down a corridor is on the floor every single frame.
var _was_grounded := true
## The swing's arc, in radians either side of where the camera is facing.
var _sweep_mesh: ImmediateMesh
## The tip's recent positions, newest first: [world point, time].
var _tip_trail: Array = []
var _trail_clock := 0.0
var _trail_on := false
## The blade's hilt and tip in the sword model's space, and both in world space
## at the last hit test.
var _blade_base := Vector3.ZERO
var _blade_tip := Vector3(0, 1, 0)
## The butt of the grip, which a haft strike leads with.
var _blade_pommel := Vector3.ZERO
var _blade_prev: Array = []
## The blade's (width, hilt-to-tip, normal) in the pivot's frame.
var _blade_frame := Basis.IDENTITY
## The pose being played on the sword pivot in code, its clock (-1 = none) and
## the pivot's transform when it began.
var _pose_kind := &""
var _pose_time := -1.0
var _pose_from := Transform3D.IDENTITY

## Mouse look pitch, held separately from the node so the bob and the dash bank
## can be layered on top without feeding back into your aim.
var _look_pitch := 0.0
## Where the head sits with nothing acting on it.
var _head_rest := Vector3.ZERO
## Advances with distance travelled, so the stride matches your speed.
var _stride := 0.0
## Eased 0..1 weights for the three characters of movement, so switching
## between them is a blend rather than a jump.
var _bob_walk := 0.0
var _bob_air := 0.0
## The head's current bob, eased toward the target each frame rather than set
## to it, so the head trails the body slightly instead of tracking it exactly.
var _bob_offset := Vector3.ZERO
var _bob_roll := 0.0
var _bob_pitch := 0.0
## Drives the slow wander that keeps the cycle from repeating.
var _bob_noise := FastNoiseLite.new()

## The level's environment, so a dash can drain the colour out of it.
var _environment: Environment = null
var _base_saturation := 1.0
## Enemies the dash is currently allowed to pass through, so exactly those can
## be restored afterwards without disturbing anything else's exceptions.
var _phased_through: Array[Node] = []
## Backstop: after this, anything still intangible is turned solid regardless.
var _phase_hold_until := 0.0

## The marker showing where the last hit came from. 1 at the moment of impact,
## decaying to 0; bearing is relative to where you are looking, and severity
## scales with how hard the hit was.
var _damage_mark := 0.0
var _damage_bearing := 0.0
var _damage_severity := 0.0
var _slamming := false
## The impact's aftermath: down until this time, and the decaying crouch and
## shake (1 at impact, 0 when over).
var _slam_recover_until := 0.0
var _slam_crouch := 0.0
var _shake := 0.0
## The ring on the floor under a dive.
var _slam_marker: MeshInstance3D
var _slam_marker_mat: ShaderMaterial
var _slam_marker_tween: Tween
## Whether the dive currently in progress will detonate on landing.
var _slam_armed := false
var _slam_started_at := 0.0
## This slam began on the ground: no dive, the sword is raised and brought down.
var _slam_grounded := false
var _slam_ready_at := 0.0
## Damage the stroke in progress deals (a cut's; the spin cuts the same).
var _stroke_damage := 0.0
## Guarding: whether the block is up, when it went up (wall clock, for the
## parry window), and the decaying 0..1 shove a guarded blow gives the sword.
var _blocking := false
var _block_since := -1.0
var _guard_kick := 0.0
## The potion being drunk (null when not drinking) and the seconds left of it.
var _drink_type: ConsumableType = null
var _drink_left := 0.0
## A scene walking the player somewhere (`scene_walk_to`): where to, and the
## time to give up by; and whether this scene lets the player be hurt.
var _scene_walk_target = null
var _scene_walk_until := 0.0
var _scene_walk_stuck := 0.0
var _cutscene_hurts := false
## The haft strike's camera moment, on the wall clock: when it began and when
## the pommel landed (-1 = not running), the view's turn onto the target
## (yaw, pitch) and which way it tilts. `_cine_a` / `_cine_z` are this frame's
## weights for the turn and for the zoom and tilt.
var _cine_start := -1.0
var _cine_hit := -1.0
var _cine_aim := Vector2.ZERO
var _cine_roll := 1.0
var _cine_a := 0.0
var _cine_z := 0.0
var _slowmo_tween: Tween
var _slam_query := PhysicsShapeQueryParameters3D.new()
var _slam_material: StandardMaterial3D
var _slam_tween: Tween



func _ready() -> void:
	if _discarded:
		return
	health = max_health
	_spawn_point = global_position

	inventory.changed.connect(func() -> void: inventory_changed.emit())
	_reset_inventory(true)
	if sword_model != null:
		_sword_rest = sword_model.transform
		_measure_sword()
		_draw_sword_on_top()
		# After every node's _process, so the put-away motion is built on the
		# pivot pose actually drawn this frame.
		RenderingServer.frame_pre_draw.connect(_late_sword_update)
	_held_potion = Node3D.new()
	_held_potion.set_script(load("res://scripts/held_potion.gd"))
	head.add_child(_held_potion)
	# The second weapon (scripts/spear.gd): its own model and attacks.
	spear = Node3D.new()
	spear.set_script(load("res://scripts/spear.gd"))
	head.add_child(spear)
	spear.setup(self)
	# The third (scripts/axe.gd): slash, throw, berserk.
	axe = Node3D.new()
	axe.set_script(load("res://scripts/axe.gd"))
	head.add_child(axe)
	axe.setup(self)
	# Rats: the live ones thrown, the robot one set down and driven.
	rats = Node3D.new()
	rats.set_script(load("res://scripts/rat_control.gd"))
	head.add_child(rats)
	rats.setup(self)
	get_tree().create_timer(0.4).timeout.connect(_warm_guard_flash)
	# A torch in the left hand, down in the corner of the view (hand_torch.gd).
	var torch_hand := Node3D.new()
	torch_hand.set_script(load("res://scripts/hand_torch.gd"))
	camera.add_child(torch_hand)
	torch_hand.call("setup", self)


	var slam_shape := SphereShape3D.new()
	slam_shape.radius = slam_radius
	_slam_query.shape = slam_shape
	_slam_query.collision_mask = hitbox.collision_mask
	_slam_query.collide_with_bodies = true
	_slam_query.collide_with_areas = false
	_slam_query.exclude = [get_rid()]

	_slam_material = slam_ring.get_active_material(0) as StandardMaterial3D
	_hide_slam_ring()
	_build_slam_marker()

	anim.animation_finished.connect(_on_animation_finished)
	_setup_blending()
	_silence_viewmodel_shadows(head)
	if sweep_trail != null:
		_sweep_mesh = ImmediateMesh.new()
		sweep_trail.mesh = _sweep_mesh
		# Top level: the ribbon is laid in world space, where the tip has been.
		sweep_trail.top_level = true
		sweep_trail.visible = false
	anim.play(&"idle")
	Coop.set_mouse(self, Input.MOUSE_MODE_CAPTURED)
	_base_fov = camera.fov
	_look_pitch = head.rotation.x
	_head_rest = head.position
	_bob_noise.seed = randi()
	_bob_noise.frequency = 1.0
	_bob_noise.fractal_octaves = 2
	_ghost_meter = 1.0

	var world := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if world != null and world.environment != null:
		_environment = world.environment
		_base_saturation = _environment.adjustment_saturation
	health_changed.emit(health, max_health)
	inventory_changed.emit()


## Camera flourishes run here rather than in _physics_process: they are purely
## visual, and at 60 Hz physics a fast punch like this would visibly step.
func _process(delta: float) -> void:
	if _viewmodel_layer != 0:
		_layer_sweep -= delta
		if _layer_sweep <= 0.0:
			_layer_sweep = 0.5
			_sweep_view_layers()
	_pad_look(delta)
	_update_cine()
	_update_scene_camera()
	_update_lunge(delta)
	_update_drink(delta)
	_update_wake(delta)
	if _guard_kick > 0.0:
		_guard_kick = maxf(_guard_kick - delta / 0.25, 0.0)
	_guard_level = move_toward(_guard_level, 1.0 if _blocking else 0.0,
		delta / (GUARD_UP if _blocking else GUARD_DOWN))
	_update_dash_view(delta)
	_update_head(delta)
	_update_pose(delta)
	_update_sweep_trail(delta)
	_update_colour(delta)
	if _damage_mark > 0.0:
		_damage_mark = maxf(_damage_mark - delta / maxf(damage_mark_time, 0.001), 0.0)


## Opens the view out during a dash, then lets it fall away. The bank it used
## to apply directly now goes through _update_head, which composes it with the
## bob and your look so the three cannot overwrite one another.
func _update_dash_view(delta: float) -> void:
	# The base is the player's Field of view setting.
	_base_fov = Graphics.field_of_view
	if _dash_view <= 0.0 and _swing_kick <= 0.0 and _jump_kick <= 0.0 and _cine_z <= 0.0 \
			and _scene_zoom == 0.0 and _lunge_age < 0.0 and _pose_kind != &"spin" \
			and _remnant_hunt <= 0.0 and _stab_fov == 0.0:
		if camera.fov != _base_fov:
			camera.fov = _base_fov
		return
	# Held at full while a ghost is on; it only falls away once the ghost ends.
	# (Decaying here and re-setting it at the physics rate made the view pulse.)
	if _dash_view > 0.0 and not _ghosting:
		_dash_view = maxf(_dash_view - delta / maxf(dash_effect_time, 0.001), 0.0)
	if _swing_kick > 0.0:
		_swing_kick = maxf(_swing_kick - delta / maxf(attack_kick_time, 0.001), 0.0)
	# Squared, so both punch at the start and ease out rather than sliding
	# back linearly.
	var dash := _dash_view * _dash_view
	var swing := _swing_kick * _swing_kick
	# A dash opens the view out and a swing snaps it in. They are composed here
	# rather than each writing the field of view, so swinging mid-dash reads as
	# both instead of whichever ran last.
	camera.fov = _base_fov + dash_fov_kick * dash - attack_fov_kick * swing \
		+ jump_fov_kick * sin(PI * (1.0 - _jump_kick)) - haft_zoom * _cine_z - _scene_zoom \
		+ lunge_fov_kick * lunge_intensity() + _spin_effort().w + _remnant_fov() + _stab_fov
	if _dash_view <= 0.0 and _swing_kick <= 0.0 and _jump_kick <= 0.0 and _cine_z <= 0.0 \
			and _scene_zoom == 0.0 and _lunge_age < 0.0 and _pose_kind != &"spin" \
			and _remnant_hunt <= 0.0 and _stab_fov == 0.0:
		# Land exactly back on the authored value rather than near it.
		camera.fov = _base_fov


## The whole head transform, assembled in one place every frame: your look, the
## dash bank, and the bob. Anything that writes to the head directly would be
## clobbered by whichever of these ran last, so nothing else does.
func _update_head(delta: float) -> void:
	if _land_kick > 0.0:
		_land_kick = maxf(_land_kick - delta / maxf(landing_kick_time, 0.001), 0.0)
	if _slam_crouch > 0.0:
		_slam_crouch = maxf(_slam_crouch - delta / maxf(slam_recover_time, 0.001), 0.0)
	if _shake > 0.0:
		_shake = maxf(_shake - delta / maxf(slam_shake_time, 0.001), 0.0)
	if _jump_kick > 0.0:
		_jump_kick = maxf(_jump_kick - delta / maxf(jump_kick_time, 0.001), 0.0)

	var grounded := is_on_floor()
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := grounded and speed > 0.4

	# Ease the weights rather than switching, or stepping off a ledge would
	# snap the bob from one character to another.
	var blend := delta * bob_blend_rate
	_bob_walk = move_toward(_bob_walk, 1.0 if moving else 0.0, blend)
	_bob_air = move_toward(_bob_air, 0.0 if grounded else 1.0, blend)
	var idle_weight: float = clampf(1.0 - _bob_walk - _bob_air, 0.0, 1.0)

	var offset := Vector3.ZERO
	var roll := 0.0
	var pitch := 0.0

	if head_bob:
		# Driven by distance covered, not by a clock, so the stride speeds up
		# and slows down with you instead of running at a fixed beat.
		_stride += speed * walk_bob_per_metre * delta * TAU
		var time := float(Time.get_ticks_msec()) / 1000.0

		# Nobody's gait is symmetric. Modulating on the stride itself makes
		# alternate footfalls land slightly differently, which is most of the
		# difference between walking and a metronome.
		var gait := 1.0 + bob_limp * sin(_stride)

		# Two footfalls per stride, so the vertical runs at twice the rate the
		# sway does -- that ratio is what makes it read as walking.
		offset.y += sin(_stride * 2.0) * walk_bob_height * gait * _bob_walk
		offset.x += sin(_stride) * walk_bob_sway * _bob_walk
		roll += sin(_stride) * deg_to_rad(walk_bob_roll_degrees) * _bob_walk
		# A small nod on each footfall, offset from the rise so the head is
		# still settling as the body lifts.
		pitch += sin(_stride * 2.0 - 0.7) \
			* deg_to_rad(walk_bob_pitch_degrees) * _bob_walk

		# Breathing, as two frequencies rather than one: a single sine in and
		# out is the most obviously mechanical thing a still camera can do.
		offset.y += (sin(time * idle_bob_rate) * 0.7
			+ sin(time * idle_bob_rate * 1.63 + 1.1) * 0.3) \
			* idle_bob_height * idle_weight
		roll += sin(time * idle_bob_rate * 0.7) \
			* deg_to_rad(idle_bob_roll_degrees) * idle_weight
		pitch += sin(time * idle_bob_rate * 0.53 + 2.2) \
			* deg_to_rad(idle_bob_pitch_degrees) * idle_weight

		# Airborne: a slow float, no footfalls to sync to.
		offset.y += sin(time * air_bob_rate) * air_bob_height * _bob_air

		# A slow wander on top of everything, so the pattern never repeats
		# exactly however long you stand or walk. This is what stops the eye
		# from ever locking on to the cycle.
		# Scaled down when standing, but not away: a still camera is where a
		# repeating cycle is easiest to notice, so it needs the wander most.
		var wander: float = walk_bob_height * bob_wander \
			* (0.55 + 0.45 * _bob_walk)
		offset.x += _bob_noise.get_noise_2d(time * bob_wander_rate, 0.0) * wander
		offset.y += _bob_noise.get_noise_2d(time * bob_wander_rate, 31.0) * wander
		roll += _bob_noise.get_noise_2d(time * bob_wander_rate, 67.0) \
			* deg_to_rad(walk_bob_roll_degrees) * bob_wander

	# Eased rather than applied outright. A head has mass: it arrives a moment
	# after the body does, and that lag is most of what separates a camera that
	# feels carried from one that feels driven.
	var ease: float = 1.0 - exp(-bob_response * delta)
	_bob_offset = _bob_offset.lerp(offset, ease)
	_bob_roll = lerpf(_bob_roll, roll, ease)
	_bob_pitch = lerpf(_bob_pitch, pitch, ease)

	# Applied straight to position, bypassing the eased bob -- a landing is an
	# impact. It drops in over the first ~15% (about 50 ms) rather than in one
	# frame, which at this strength read as a glitch, then eases back out.
	var land := _landing_shape(1.0 - _land_kick) * _land_strength
	# Takeoff: the head dips as the legs drive, then rises a little past rest
	# as the body comes up with it; the view tips up and opens out meanwhile.
	var jump_phase := 1.0 - _jump_kick
	var push := sin(PI * clampf(jump_phase / 0.4, 0.0, 1.0)) \
		- 0.4 * sin(PI * clampf((jump_phase - 0.4) / 0.6, 0.0, 1.0))
	var lift := sin(PI * jump_phase)
	# The slam: down hard on impact, rising over the recovery as the player gets
	# up; and a violent shake on top, squared so it hits and then settles fast.
	var crouch := _landing_shape(1.0 - _slam_crouch) if _slam_crouch > 0.0 else 0.0
	var quake := _shake * _shake * slam_shake_strength
	var shake_offset := Vector3.ZERO
	var shake_pitch := 0.0
	var shake_roll := 0.0
	if quake > 0.0:
		var t := float(Time.get_ticks_msec()) / 1000.0 * 32.0
		shake_offset = Vector3(_bob_noise.get_noise_2d(t, 11.0), _bob_noise.get_noise_2d(t, 37.0), 0.0) * 0.09 * quake
		shake_pitch = _bob_noise.get_noise_2d(t, 73.0) * deg_to_rad(5.0) * quake
		shake_roll = _bob_noise.get_noise_2d(t, 91.0) * deg_to_rad(7.0) * quake
	# The spin's effort: a lean, a nod and a crouch (its FOV is in
	# `_update_dash_view`).
	var effort := _spin_effort()
	if _stab_strain > 0.0:
		_stab_strain = maxf(_stab_strain - delta * 1.1, 0.0)
	var stab := _stab_effort()
	_stab_fov = stab.w
	effort += stab
	var tremble := _remnant_tremble()
	shake_offset += Vector3(tremble.x, tremble.y, 0.0)
	shake_roll += tremble.z
	# Getting up after a death, and a scene's crush into the floor.
	var wake := _wake_view() + _knock_view() + restrain_view
	var crushed := _scene_crush * _scene_crush * (3.0 - 2.0 * _scene_crush)
	effort.x += wake.z + 38.0 * crushed
	effort.y += wake.y - 25.0 * crushed
	effort.z += wake.x + 1.35 * crushed
	head.position = _head_rest + _bob_offset + shake_offset + _scene_lean \
		- Vector3(0, landing_bob_height * land + jump_bob_height * push + slam_crouch_depth * crouch + effort.z,
			spear_effort_push * _stab_k)
	# Look is added untouched, never smoothed -- lagging the crosshair behind
	# the mouse would feel like input lag, not like weight.
	# The swing punch joins the same composition as everything else, for the
	# reason in the comment above this function.
	var swing := _swing_kick * _swing_kick
	head.rotation.x = _look_pitch + _bob_pitch + deg_to_rad(attack_view_kick) * swing \
		- deg_to_rad(landing_view_kick) * land + deg_to_rad(jump_view_kick) * lift \
		- deg_to_rad(7.0) * crouch + shake_pitch + _cine_aim.y * _cine_a + deg_to_rad(effort.y)
	head.rotation.z = _bob_roll + deg_to_rad(dash_roll_degrees) \
		* (_dash_view * _dash_view) * _dash_lateral \
		+ deg_to_rad(attack_view_roll) * swing * _swing_roll + shake_roll \
		+ deg_to_rad(haft_roll) * _cine_roll * _cine_z + deg_to_rad(_scene_roll) + deg_to_rad(effort.x)
	# The haft strike's turn onto its target. Only ever here, on the head: the
	# body's yaw is the player's aim and is never touched.
	head.rotation.y = _cine_aim.x * _cine_a + _spin_view_yaw(delta)


## Puts the sword away when something else is in hand (or the hands are busy,
## as in the door kick), and brings it back. Applied to the Sword MODEL under
## its pivot as `_sword_duck` 0..1: the pivot is posed every frame by the clips
## or the swing, so anything layered there would be overwritten or compound.
## The sword has no reaction to walls at all -- it is drawn in front of them
## instead (`_draw_sword_on_top`).
func _update_sword(delta: float) -> void:
	if sword_model == null:
		return
	# A haft strike or a scripted stab draws the sword unless the spear is in
	# hand to do it (`_scene_weapon`).
	var forced := (_pose_kind == &"haft" or _pose_kind == &"stab") and _scene_weapon == &"sword"
	if _held_potion != null:
		_held_potion.want = _consumable_for(held_item()) != null and not hands_busy \
			and not forced
	# The sword is put away while a flask is at the lips, whatever is in hand.
	# Also while a live rat hangs from the hand (rat_control.gd).
	var away: bool = held_item() != &"sword" or hands_busy or is_drinking() \
		or (rats != null and rats.get("holding") == true)
	var goal := 1.0 if away and not forced else 0.0
	var smooth := sword_duck_smooth_up if goal > _sword_duck else sword_duck_smooth_down
	_sword_duck = clampf(_smooth_damp(_sword_duck, goal, delta, smooth), 0.0, 1.0)
	sword_model.visible = _sword_duck < 0.999
	sword_model.transform = _duck_transform(_sword_duck)


## Every surface of the sword gets its own copy of its material, drawn pulled
## toward the camera (`use_z_clip_scale`) so the sword is in front of every
## wall, door and enemy whatever the blade passes through. It keeps its size on
## screen; only its depth is compressed. No extra pass, no second viewport.
func _draw_sword_on_top() -> void:
	for node in sword_model.find_children("*", "GeometryInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := mi.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var copy := source.duplicate() as BaseMaterial3D
			copy.use_z_clip_scale = true
			copy.z_clip_scale = sword_draw_depth
			mi.set_surface_override_material(i, copy)

## Critically damped spring toward `target` (Game Programming Gems 4, 1.10):
## arrives in about `smooth_time` with no overshoot, and carries its speed
## across frames in `_duck_vel` so the motion has no corners.
func _smooth_damp(current: float, target: float, delta: float, smooth_time: float) -> float:
	var omega := 2.0 / maxf(smooth_time, 0.001)
	var x := omega * delta
	var decay := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var temp := (_duck_vel + omega * change) * delta
	_duck_vel = (_duck_vel - omega * temp) * decay
	return target + (change + temp) * decay


func _late_sword_update() -> void:
	if is_inside_tree():
		_update_sword(get_process_delta_time())


## The model's transform under its pivot for a duck of `level` (0..1). Built in
## the HEAD's frame, about the pivot's own origin, then carried into the
## pivot's frame: P^-1 * D * P * rest.
func _duck_transform(level: float) -> Transform3D:
	if level <= 0.0001:
		return _sword_rest
	var e := level * level * (3.0 - 2.0 * level)
	var pivot := sword_pivot.transform
	var around := Transform3D(Basis(), pivot.origin)
	var duck := Transform3D(Basis(Vector3.RIGHT, sword_duck_tilt * e),
		Vector3(0.0, -sword_duck_drop * e, sword_duck_back * e))
	return pivot.affine_inverse() * around * duck * around.affine_inverse() * pivot * _sword_rest


## The blade's hilt (between the guard's ends, its widest vertices) and tip (its
## highest vertex) in the sword model's own space, and its axes in the pivot's
## frame. Measured off the mesh, so a different sword model needs nothing
## changed here.
func _measure_sword() -> void:
	var found := sword_model.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		return
	var mi := found[0] as MeshInstance3D
	var to_model := sword_model.global_transform.affine_inverse() * mi.global_transform
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tip := verts[0]
	var left := verts[0]
	var right := verts[0]
	var pommel := verts[0]
	for v in verts:
		if v.y > tip.y:
			tip = v
		if v.y < pommel.y:
			pommel = v
		if v.x < left.x:
			left = v
		if v.x > right.x:
			right = v
	var guard_y := (left.y + right.y) * 0.5
	_blade_tip = to_model * tip
	_blade_pommel = to_model * Vector3(0.0, pommel.y, 0.0)
	_blade_base = to_model * Vector3(0.0, guard_y, 0.0)
	# The blade's own axes in the PIVOT's frame: hilt-to-tip, and its width (the
	# guard's span, squared to the blade).
	var along := (_sword_rest.basis * (_blade_tip - _blade_base)).normalized()
	var width := _sword_rest.basis * (to_model.basis * Vector3.RIGHT)
	width = (width - along * width.dot(along)).normalized()
	_blade_frame = Basis(width, along, width.cross(along))



## The weapon in hand, as an item id (&"" when its wheel slot is empty).
func held_item() -> StringName:
	return inventory.id_at(selected_slot)


## Takes the weapon in weapon-wheel slot `slot` (0-3) in hand.
func select_slot(slot: int) -> void:
	slot = clampi(slot, 0, Inventory.WEAPONS - 1)
	if slot == selected_slot:
		return
	# A thrown axe leaves the hands empty until it is caught: nothing else is
	# taken up meanwhile (axe.gd).
	if axe_away() and selected_slot >= 0:
		return
	selected_slot = slot
	selection_changed.emit(slot)


## --- Saving (save_system.gd) ----------------------------------------------------

func save_state() -> Dictionary:
	return {
		"pos": global_position,
		"yaw": rotation.y,
		"pitch": _look_pitch,
		"health": health,
		"slots": inventory.slots.duplicate(true),
		"quick_assigned": inventory.assigned.duplicate(),
		"weapon_levels": weapon_levels.duplicate(),
		"armor_level": armor_level,
		"selected": selected_slot,
		"axe_given": true,
	}


func restore_state(data: Dictionary) -> void:
	global_position = data.get("pos", global_position)
	velocity = Vector3.ZERO
	rotation.y = float(data.get("yaw", rotation.y))
	_look_pitch = float(data.get("pitch", 0.0))
	health = clampf(float(data.get("health", max_health)), 1.0, max_health)
	health_changed.emit(health, max_health)
	weapon_levels = (data.get("weapon_levels", {}) as Dictionary).duplicate()
	armor_level = int(data.get("armor_level", 1))
	var slots: Array = data.get("slots", [])
	var same_layout := slots.size() == Inventory.SIZE
	if same_layout:
		inventory.restore(slots, data.get("quick_assigned", {}))
		currency_changed.emit(currency, 0)
	elif not slots.is_empty():
		# A save from before the wheels (the 9-slot hotbar): everything carried
		# is put back where it now belongs.
		inventory.migrate(slots)
		currency_changed.emit(currency, 0)
	# Saves from before the axe (2026-10-20) are handed one, once.
	if not slots.is_empty() and not bool(data.get("axe_given", false)) and inventory.find(&"axe") < 0:
		inventory.add(&"axe", 1)
	var want := int(data.get("selected", 0)) if same_layout else maxi(inventory.find(&"sword"), 0)
	selected_slot = -1
	select_slot(want)


## Landing dip over its life, 0..1 in, 0..1 out: a fast drop, then an eased
## recovery.
static func _landing_shape(t: float) -> float:
	if t >= 1.0:
		return 0.0
	if t < 0.15:
		return sin(t / 0.15 * PI * 0.5)
	var back := (1.0 - t) / 0.85
	return back * back


## Drains the colour out of the world while dashing and lets it back in as the
## dash ends, so the invulnerability is something you can see rather than
## something you have to remember. Low health drains it too
## (`_health_saturation`): the world goes greyer the closer the player is to
## death. On the environment's own adjustment, so it costs no extra pass and
## leaves the HUD in full colour.
func _update_colour(delta: float) -> void:
	if _environment == null:
		return
	var target: float = 0.0 if is_dodging() \
		else _base_saturation * _health_saturation() * _wake_colour()
	# Out fast, back slowly: the drop should register instantly, the return
	# should feel like coming up for air.
	var rate: float = delta / maxf(
		dash_desaturate_in if target < _environment.adjustment_saturation
		else dash_desaturate_out, 0.001)
	_environment.adjustment_saturation = move_toward(
		_environment.adjustment_saturation, target, _base_saturation * rate)


## 0..1, how hunted the player is (the HUD eases it). Read by `_update_head`
## (tremble) and `_update_dash_view` (field of view).
var _remnant_hunt := 0.0


func set_remnant_hunt(amount: float) -> void:
	_remnant_hunt = clampf(amount, 0.0, 1.0)


## The tremble while hunted: (offset x, offset y, roll rad). Slow noise, not a
## jolt -- the body is tense, not struck.
func _remnant_tremble() -> Vector3:
	if _remnant_hunt <= 0.0:
		return Vector3.ZERO
	var t := float(Time.get_ticks_msec()) / 1000.0 * 7.0
	var h := _remnant_hunt
	return Vector3(_bob_noise.get_noise_2d(t, 131.0) * remnant_shake * h,
		_bob_noise.get_noise_2d(t, 157.0) * remnant_shake * h,
		_bob_noise.get_noise_2d(t, 173.0) * deg_to_rad(remnant_shake_roll) * h)


## The field of view while hunted: drawn in, and slowly breathing.
func _remnant_fov() -> float:
	if _remnant_hunt <= 0.0:
		return 0.0
	var t := float(Time.get_ticks_msec()) / 1000.0
	var h := _remnant_hunt * _remnant_hunt * (3.0 - 2.0 * _remnant_hunt)
	return (-remnant_fov_in + remnant_fov_breathe * sin(TAU * t / remnant_fov_period)) * h


## 1 (full colour) down to `low_health_saturation` as health falls from
## `low_health_desaturate_from` of max to nothing.
func _health_saturation() -> float:
	if _dead:
		return 1.0
	var k := clampf(health / maxf(max_health * low_health_desaturate_from, 0.01), 0.0, 1.0)
	return lerpf(low_health_saturation, 1.0, k * k * (3.0 - 2.0 * k))


## Radians per pixel of mouse travel: this body's own sensitivity times the
## player's setting (the settings menu's slider, kept by `Graphics`).
func _look_scale() -> float:
	return mouse_sensitivity * Graphics.mouse_sensitivity


## --- Looking with a controller (2026-10-10) ------------------------------------
##
## The right stick ("look_*" actions) turns the view at up to `pad_look_speed`
## radians a second at full tilt, scaled by the same sensitivity setting as the
## mouse, through a squared response so small corrections are fine and a full
## push turns fast. Every rule mouse look obeys holds here too: nothing in a
## menu, a scene or while a wheel is open (`wheel_open`, set by radial_menu.gd,
## which reads the stick itself then); clamped to the gap in a hiding place;
## nothing while a spin owns the view.

@export var pad_look_speed := 3.4
## Pitch is a little slower than yaw at the same tilt.
@export var pad_pitch_share := 0.7
## A wheel (radial_menu.gd) is up: the mouse and the right stick choose in it.
var wheel_open := false


func _pad_look(delta: float) -> void:
	if ui_open or wheel_open or (in_cutscene and restrained_by == null) or _dead or remote_view:
		return
	var v := Coop.vector(self, &"look_left", &"look_right", &"look_up", &"look_down")
	if v == Vector2.ZERO:
		return
	v *= v.length()
	var k := pad_look_speed * Graphics.mouse_sensitivity * delta
	if is_hidden():
		var yaw: float = rotation.y - v.x * k
		rotation.y = _hide_yaw + clampf(wrapf(yaw - _hide_yaw, -PI, PI), -HIDE_LOOK_YAW, HIDE_LOOK_YAW)
		_look_pitch = clampf(_look_pitch - v.y * k * pad_pitch_share, -HIDE_LOOK_PITCH, HIDE_LOOK_PITCH)
		return
	if _pose_kind == &"spin" and not _spin_released():
		return
	# On a vat, no turning (note 111).
	if latched_to == null:
		rotate_y(-v.x * k)
	_look_pitch = clampf(_look_pitch - v.y * k * pad_pitch_share, deg_to_rad(min_pitch), deg_to_rad(max_pitch))


func _unhandled_input(event: InputEvent) -> void:
	# Co-op: only this player's keys and mouse, or pad (coop.gd).
	if not Coop.owns(self, event):
		return
	if is_hidden():
		# Shut in a hiding place: only looking about, and only out of its doors.
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ui_open:
			var motion := event as InputEventMouseMotion
			var yaw: float = rotation.y - motion.relative.x * _look_scale()
			rotation.y = _hide_yaw + clampf(wrapf(yaw - _hide_yaw, -PI, PI), -HIDE_LOOK_YAW, HIDE_LOOK_YAW)
			_look_pitch = clampf(_look_pitch - motion.relative.y * _look_scale(),
				-HIDE_LOOK_PITCH, HIDE_LOOK_PITCH)
		return
	if restrained_by != null and not ui_open:
		# Held (note 96): looking about, and struggling with any fighting key.
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := event as InputEventMouseMotion
			rotate_y(-motion.relative.x * _look_scale())
			_look_pitch = clampf(_look_pitch - motion.relative.y * _look_scale(),
				deg_to_rad(min_pitch), deg_to_rad(max_pitch))
		elif event.is_action_pressed(&"attack") or event.is_action_pressed(&"jump") \
				or event.is_action_pressed(&"interact") or event.is_action_pressed(&"block"):
			struggles += 1
			_shake = maxf(_shake, 0.12)
		return
	if in_cutscene or ui_open:
		return
	# Seeing through a robot rat: rat_control.gd reads the keys and the mouse.
	if remote_view:
		return
	# A wheel is up (radial_menu.gd): it has the mouse; no attacking meanwhile.
	if wheel_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# The spin owns the view while it turns: always exactly one full circle,
		# so mouse look is ignored until the turn is complete (not saved up for
		# later) -- and is back the instant it is, while the blade comes home.
		if _pose_kind == &"spin" and not _spin_released():
			return
		# Yaw turns the whole body so movement follows the view; pitch stays on
		# the head alone, otherwise looking up would tilt the capsule.
		# Holding a vat (note 111: "The player shouldnt be able to turn when
		# pushing a vat"), only the pitch: they face it, and it is what turns.
		if latched_to == null:
			rotate_y(-event.relative.x * _look_scale())
		# Kept in its own variable rather than read back off the node. The head
		# also carries the bob and the dash bank, and accumulating look from a
		# value those have already nudged would let them drift into your aim.
		_look_pitch = clampf(
			_look_pitch - event.relative.y * _look_scale(),
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch),
		)
	elif latched_to != null:
		# Both hands on a vat (note 106): no swinging, guarding, jumping or
		# slamming -- only looking up and down (above); letting go of E lets go
		# (the vat's own, note 111).
		return
	elif event.is_action_pressed("attack"):
		_attack_key_spills_drink()
		# While the mouse is free, a click is the player asking for it back
		# rather than asking to swing.
		if Coop.aim_ready(self):
			# The button does whatever the weapon in hand does: the sword swings,
			# the spear stabs. (Potions are drunk from the quick-item wheel.)
			if held_item() == &"sword":
				# Nothing attacks out of ghost mode.
				if not _ghosting:
					_start_attack()
			elif held_item() == &"spear":
				if _spear_free():
					spear.stab()
			elif held_item() == &"axe":
				if _spear_free():
					axe.slash()
			elif held_item() == &"robot_rat":
				# Set down, and the view goes to its eyes (rat_control.gd).
				if not _ghosting and not is_drinking():
					rats.deploy()
		else:
			Coop.set_mouse(self, Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("thrust"):
		_attack_key_spills_drink()
		# Q: the spin with the sword; the dash with the spear; the axe thrown.
		if Coop.aim_ready(self) and held_item() == &"sword" \
				and not _ghosting:
			_start_spin()
		elif Coop.aim_ready(self) and held_item() == &"spear" \
				and _spear_free():
			spear.dash()
		elif Coop.aim_ready(self) and held_item() == &"axe" \
				and _spear_free():
			axe.throw()
	elif event.is_action_pressed("slam"):
		_attack_key_spills_drink()
		# F: the heavy attack. With the sword, a dive in the air or the blade
		# brought down where you stand; with the spear, the throw.
		if Coop.aim_ready(self) and not _ghosting \
				and held_item() == &"sword" and not _slamming and _now() >= _slam_recover_until \
				and _pose_kind != &"haft" and not is_drinking():
			_end_block()
			_start_slam()
		elif Coop.aim_ready(self) and held_item() == &"spear" \
				and _spear_free():
			spear.throw()
		elif Coop.aim_ready(self) and held_item() == &"axe" \
				and _spear_free():
			axe.berserk()
	elif event.is_action_pressed("block"):
		# Right click, held: the block. With the mouse free, a click takes it
		# back instead.
		if not Coop.aim_ready(self):
			Coop.set_mouse(self, Input.MOUSE_MODE_CAPTURED)
			_guard_click_spent = true
		else:
			_note_block_press()
			_start_block()
	elif event.is_action_released("block"):
		_guard_click_spent = false
		_end_block()
	# Escape is the pause menu's now -- it takes the event before this runs and
	# frees the mouse itself.
	# The d-pad holds the quick wheel up (radial_menu.gd) and uses the item
	# when it is let go.


func _physics_process(delta: float) -> void:
	# Out of play -- held, hidden, on a ladder or a vat, in a scene, or the game
	# paused (no call at all) -- leaves a gap in `_ghost_frame`, and a ghost key
	# still down across it has to be let go before it starts one (note 113).
	var frame := Engine.get_physics_frames()
	if not (is_hidden() or climbing or restrained_by != null or latched_to != null or in_cutscene):
		_ghost_resumed = frame - _ghost_frame > 1
		_ghost_frame = frame
	if is_hidden() or climbing or restrained_by != null:
		# Held: the holder places them every frame (note 96).
		velocity = Vector3.ZERO
		return
	# On a surgery vat (note 106): the vat moves them with it, reading their keys.
	if latched_to != null:
		velocity = Vector3.ZERO
		_check_block()
		return
	_check_block()
	_hold_guard()
	if in_cutscene and _scene_walk_target != null:
		_scene_walk(delta)
		return
	if in_cutscene:
		# Held where it stands; only gravity, so a mid-air start still lands.
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	# The berserk roar and the throw's wind-up: stopped dead (axe.gd).
	if _axe_planted():
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		_update_locomotion()
		return
	# The spear's dash: carried straight on at its speed, no steering, until it
	# runs out (stone stops it, as anything does).
	if is_spear_dashing():
		velocity.x = _spear_dash_vel.x
		velocity.z = _spear_dash_vel.z
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		_update_locomotion()
		return
	if _spear_dash_until > 0.0:
		# Out of the dash at walking pace, not coasting on at its speed.
		_spear_dash_until = 0.0
		var flat := Vector2(velocity.x, velocity.z).limit_length(move_speed)
		velocity.x = flat.x
		velocity.z = flat.y
	# A slam is fully committed: straight down, no steering, until it lands. On
	# the ground it is planted where it stands while the sword goes up and over.
	if _slamming:
		velocity.x = 0.0
		velocity.z = 0.0
		if _slam_grounded:
			velocity.y = 0.0 if is_on_floor() else velocity.y + get_gravity().y * delta
		else:
			velocity.y = -slam_descent_speed
		move_and_slide()
		_place_slam_marker()
		if _slam_grounded:
			# On the raise's own (game-time) clock, so slow motion slows it too.
			if _pose_kind != &"raise" or _pose_time >= slam_ground_windup:
				_land_slam()
		elif is_on_floor() or _now() - _slam_started_at > slam_timeout:
			_land_slam()
		# The dive forces its own velocity every frame regardless of the floor,
		# so it is never a "landing" for the bob below -- the ring already
		# sells that impact. Kept in step here so the normal branch does not
		# see a false false->true edge on the frame right after the slam ends.
		_was_grounded = is_on_floor()
		return

	var was_grounded := _was_grounded
	# Getting up after a slam: no moving, no jumping, no ghost.
	var down := _now() < _slam_recover_until

	_update_ghost(delta)

	# Deep water (the drowning court): the body floats with its head out.
	var depth := water_depth()
	_swimming = not _ghosting and depth > SWIM_FLOAT - 0.1
	if _swimming:
		var lift := clampf((depth - SWIM_FLOAT) * 4.0, -2.5, 3.0)
		if velocity.y > lift + 0.5:
			# Rising out of it from a jump: ordinary gravity until it peaks.
			velocity += get_gravity() * delta
		else:
			velocity.y = move_toward(velocity.y, lift, 18.0 * delta)
	elif not is_on_floor() and not _ghosting:
		velocity += get_gravity() * delta

	# Coyote time. Walking off a ledge and pressing jump a moment later is what
	# a player means to do, and refusing it reads as the jump being eaten
	# rather than as their timing being wrong. Only ever granted for walking
	# off an edge -- the moment you jump, the credit is spent, so it can never
	# hand out a second jump in mid-air.
	if is_on_floor():
		_coyote_until = _now() + coyote_time
	if not ui_open and not down and not _ghosting and not remote_view \
			and Coop.just_pressed(self, &"jump") and (_now() < _coyote_until or _swimming):
		velocity.y = jump_velocity
		_coyote_until = 0.0
		_jump_kick = 1.0

	if _phase_window_open():
		_update_phasing()
	else:
		# Per body, and only once that body is clear.
		_release_phasing()

	if down:
		# Knocked down, the throw carries the body back along the floor.
		var stop := KNOCK_FRICTION if is_knocked_down() else acceleration * 2.0
		velocity.x = move_toward(velocity.x, 0.0, stop * delta)
		velocity.z = move_toward(velocity.z, 0.0, stop * delta)
	elif _ghosting:
		# Full steering at ghost speed, a little off the floor.
		var ghost_input := _move_input()
		var ghost_dir := (global_basis * Vector3(ghost_input.x, 0.0, ghost_input.y)).normalized()
		var ghost_target := ghost_dir * move_speed * ghost_speed_scale * _beam_speed_scale()
		var ghost_accel := acceleration * ghost_acceleration_scale
		velocity.x = move_toward(velocity.x, ghost_target.x, ghost_accel * delta)
		velocity.z = move_toward(velocity.z, ghost_target.z, ghost_accel * delta)
		velocity.y = _ghost_lift(delta)
	elif _swimming:
		# Treading water: full steering, slowly.
		var swim_input := _move_input()
		var swim_dir := (global_basis * Vector3(swim_input.x, 0.0, swim_input.y)).normalized()
		var swim_target := swim_dir * move_speed * swim_speed_scale
		velocity.x = move_toward(velocity.x, swim_target.x, acceleration * 0.6 * delta)
		velocity.z = move_toward(velocity.z, swim_target.z, acceleration * 0.6 * delta)
	elif is_on_floor():
		var input_dir := _move_input()
		var direction := (global_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

		# Swinging slows you. Without it the faster strokes would let you cover
		# ground at full walking pace while permanently mid-attack.
		var walk := move_speed * (attack_move_scale if _attack_slows() else 1.0) \
			* (block_move_scale if _blocking else 1.0) \
			* (drink_move_scale if is_drinking() else 1.0) \
			* (wade_speed_scale if depth > 0.3 else 1.0) * carry_speed_scale * _beam_speed_scale() \
			* (spear_stab_move_scale if _spear_stabbing() else 1.0) * _axe_speed()
		var target_velocity := direction * walk
		# Damping is raised during a swing so the lunge surge is gone well before
		# the stroke ends, leaving the back half of it visibly slower.
		var damp := acceleration * (attack_damp_scale if _attack_slows() else 1.0)
		# Berserk picks up speed as ghost mode does, not at walking's rate.
		if axe != null:
			damp *= lerpf(1.0, ghost_acceleration_scale, axe.berserk_amount())
		velocity.x = move_toward(velocity.x, target_velocity.x, damp * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, damp * delta)
	else:
		# Airborne and not dashing: full steering, at reduced authority.
		#
		# This used to lock the heading the instant you left the ground and
		# only let you throttle along that fixed line. It is full control
		# again: input sets a wish direction AND speed exactly as it does on
		# the ground above, just slewed toward that wish velocity through
		# `air_damp_scale` instead of at full ground acceleration, so a jump
		# can turn and can speed up or slow down, but never as tightly as
		# standing on the floor.
		#
		# That reduced authority is also what keeps a knockback from being
		# worthless: the hit is a sudden, large velocity change, and clawing
		# it back with input at only a fraction of ground acceleration takes
		# real air time, so a hit still visibly carries the player rather
		# than being cancelled the instant a key is pressed. A dash overrides
		# this branch entirely, above.
		#
		# With no input at all this does not touch velocity: there is no air
		# resistance in this game, so a jump with the stick centred keeps
		# every bit of the horizontal speed it left the ground with, rather
		# than bleeding off toward a phantom "no input" target.
		var air_input := _move_input()
		if air_input != Vector2.ZERO:
			var wish := (global_basis * Vector3(air_input.x, 0.0, air_input.y)).normalized()
			var air_walk := move_speed * (attack_move_scale if _attack_slows() else 1.0) \
				* (drink_move_scale if is_drinking() else 1.0) * _beam_speed_scale() * _axe_speed()
			var target_velocity := wish * air_walk
			var air_damp := acceleration * air_damp_scale \
				* (attack_damp_scale if _attack_slows() else 1.0)
			velocity.x = move_toward(velocity.x, target_velocity.x, air_damp * delta)
			velocity.z = move_toward(velocity.z, target_velocity.z, air_damp * delta)
	# The camera is untouched by all of the above; look is handled entirely in
	# _unhandled_input, so the player can always see where they are going even
	# when they cannot change it.

	# Impact speed for the landing bob below, read before move_and_slide can
	# zero it against the floor.
	var pre_move_fall_speed := -velocity.y

	# move_and_slide, and a slip round any corner or arch leg it would stick
	# on (corner_slip.gd, note 92).
	CornerSlip.slide(self)
	_update_locomotion()

	if is_on_floor() and not was_grounded:
		_on_landed(pre_move_fall_speed)
	_was_grounded = is_on_floor()

	if _hit_window_open:
		_resolve_hits()


## Fires once on the physics frame a fall ends -- see `_was_grounded` for how
## that is told apart from merely already being on the floor. Below
## landing_speed_min the impact is too soft to bother with; an ordinary
## footstep should not produce a camera kick.
func _on_landed(impact_speed: float) -> void:
	if impact_speed < landing_speed_min:
		return
	_land_kick = 1.0
	_land_strength = clampf(
		(impact_speed - landing_speed_min)
			/ maxf(landing_speed_reference - landing_speed_min, 0.001),
		0.0, 1.0)


## The slash's trail: a camera-facing ribbon through the recent positions of the
## point on the blade that crosses the crosshair (`_trail_point`), thinning and
## fading with age -- so the white streak runs through the middle of the view,
## where the cut is aimed. During a cut it is sampled from the swing itself every
## few milliseconds between frames: a cut sweeps ~0.4 rad a frame, and straight
## chords between frame positions cut inside the arc and missed the crosshair.
func _update_sweep_trail(delta: float) -> void:
	if sweep_trail == null or _sweep_mesh == null:
		return
	# Transparent and drawn every frame -- the kind of thing the low presets drop.
	if not sweep_trail_enabled or not Graphics.effects:
		if sweep_trail.visible:
			sweep_trail.visible = false
		_tip_trail.clear()
		return
	# Game time, not the wall clock, so a slow-motion stroke leaves the same trail.
	var before := _trail_clock
	_trail_clock += delta
	var now := _trail_clock
	if _trail_on and sword_model != null and sword_model.is_visible_in_tree():
		# Kept in the HEAD's frame, like the sword: in world space the swing's view
		# kick and lunge carried the camera on after the blade had passed, so the
		# streak sat well above the crosshair, stepped at every frame's join.
		var point := _sword_rest * _trail_point()
		if _pose_kind == &"slash" or _pose_kind == &"chop" or _pose_kind == &"spin":
			var from_t := _trail_pose_t if _trail_pose_t >= 0.0 and _trail_pose_t < _pose_time else _pose_time
			var steps := maxi(1, ceili((_pose_time - from_t) / TRAIL_STEP))
			for k in range(1, steps + 1):
				var f := float(k) / float(steps)
				var at := lerpf(from_t, _pose_time, f)
				if _pose_kind == &"spin":
					# The head itself turns through a spin, so in the head's frame
					# the blade barely moves and there would be no trail. Kept in
					# the BODY's frame instead, the head's turn at that instant
					# rebuilt from `_spin_yaw_at` -- the streak stays in the world
					# and pours off the blade as the view comes round.
					var turn := Transform3D(Basis.from_euler(Vector3(head.rotation.x,
						_cine_aim.x * _cine_a + _spin_yaw_at(at), head.rotation.z)), head.position)
					_tip_trail.push_front([turn * (_spin_pose(at) * point), lerpf(before, now, f), true])
				else:
					var pose := _swing_pose(at, _pose_kind == &"chop")
					_tip_trail.push_front([pose * point, lerpf(before, now, f)])
			_trail_pose_t = _pose_time
		else:
			_tip_trail.push_front([head.global_transform.affine_inverse()
				* (sword_model.global_transform * _trail_point()), now])
	else:
		_trail_pose_t = -1.0
	while not _tip_trail.is_empty() and now - float(_tip_trail.back()[1]) > sweep_trail_life:
		_tip_trail.pop_back()
	_sweep_mesh.clear_surfaces()
	if _tip_trail.size() < 2:
		sweep_trail.visible = false
		return
	sweep_trail.global_transform = Transform3D.IDENTITY
	var eye := camera.global_position
	var to_world := head.global_transform
	# Samples from a spin are in the body's frame (a third element, true).
	var from_body := global_transform
	# Gathered first: a surface begun with no vertices (every segment degenerate,
	# as while the stroke is held at its end) errors and jams the mesh.
	var verts: Array = []
	for i in _tip_trail.size() - 1:
		var s0: Array = _tip_trail[i]
		var s1: Array = _tip_trail[i + 1]
		var p0: Vector3 = (from_body if s0.size() > 2 else to_world) * (s0[0] as Vector3)
		var p1: Vector3 = (from_body if s1.size() > 2 else to_world) * (s1[0] as Vector3)
		var along := p1 - p0
		if along.length_squared() < 1e-8:
			continue
		var side := along.cross(eye - p0).normalized()
		# Thin at the tip's newest point, thinning and fading to nothing behind.
		var f0 := 1.0 - clampf((now - float(_tip_trail[i][1])) / sweep_trail_life, 0.0, 1.0)
		var f1 := 1.0 - clampf((now - float(_tip_trail[i + 1][1])) / sweep_trail_life, 0.0, 1.0)
		var w0 := side * sweep_trail_width * f0
		var w1 := side * sweep_trail_width * f1
		var c0 := Color(1.0, 1.0, 1.0, f0 * sweep_trail_alpha)
		var c1 := Color(1.0, 1.0, 1.0, f1 * sweep_trail_alpha)
		verts.append_array([[p0 - w0, c0], [p0 + w0, c0], [p1 + w1, c1], [p0 - w0, c0], [p1 + w1, c1], [p1 - w1, c1]])
	sweep_trail.visible = not verts.is_empty()
	if verts.is_empty():
		return
	_sweep_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		_sweep_mesh.surface_set_color(v[1])
		_sweep_mesh.surface_add_vertex(v[0])
	_sweep_mesh.surface_end()

## Seconds of swing between the trail's samples.
const TRAIL_STEP := 0.004
var _trail_pose_t := -1.0
var _trail_frac := -1.0


## The point on the blade (sword model space) the trail follows: the one that
## actually passes through the crosshair. Found once by running a cut through
## the pose function a millisecond at a time and taking, at the moment the blade
## comes nearest the view's axis, the point on it nearest that axis. (A fixed
## distance worked out from `SWING_CROSS` passed 4 cm high: 16 px.)
func _trail_point() -> Vector3:
	if _trail_frac < 0.0:
		var base := _sword_rest * _blade_base
		var span := _sword_rest * _blade_tip - base
		var axis := Vector3(0.0, 0.0, -1.0)
		var best := INF
		_trail_frac = 1.0
		var t := SWING_WIND
		while t <= SWING_CUT:
			var pose := _swing_pose(t, false)
			var g := pose * base
			var u := pose.basis * span
			# Closest points between the blade's line and the view's axis.
			var a := u.dot(u)
			var b := u.dot(axis)
			var denom := a - b * b
			if denom > 1e-8:
				var s := (b * axis.dot(g) - u.dot(g)) / denom
				var r := (a * axis.dot(g) - b * u.dot(g)) / denom
				var gap := (g + u * s - axis * r).length()
				if s >= 0.0 and s <= 1.0 and r > 0.0 and gap < best:
					best = gap
					_trail_frac = s
			t += 0.001
	return _blade_base.lerp(_blade_tip, _trail_frac)


## Stops the first-person viewmodel from casting shadows.
##
## The sword and torch sit centimetres from the camera and inches from the torch
## light, so their shadows are enormous smears across whatever is in front of
## you -- and because that light is an omni, every one of them is rasterised into
## all six faces of its shadow cube. Measured at 3440x1440, leaving the sword
## casting cost 1.4-1.9 ms a frame and raised the primitive count by ~8,600 for
## a 1,264 triangle mesh, which is the 6x plus the main pass almost exactly.
func _silence_viewmodel_shadows(from: Node) -> void:
	for child in from.get_children():
		var geo := child as GeometryInstance3D
		if geo != null:
			geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_silence_viewmodel_shadows(child)


func _start_attack() -> void:
	if _slamming or _now() < _slam_recover_until or _pose_kind == &"haft" or _blocking \
			or _ghosting or is_drinking():
		return
	# A new stroke may cut into the last one's recovery, so a combo flows.
	if _attacking and _pose_time < _bite_end():
		return
	_attacking = true
	_stroke_damage = attack_damage * weapon_damage_scale(&"sword")
	_hit_this_swing.clear()
	_blade_prev.clear()
	# Index 0 sweeps right to left, index 1 back from left to right.
	_begin_pose(&"slash" if _next_attack == 0 else &"chop")
	# Alternating strokes roll the view opposite ways, so a combo reads as two
	# distinct cuts rather than the same one twice.
	_swing_roll = 1.0 if _next_attack == 0 else -1.0
	_swing_kick = maxf(_swing_kick, 1.0)
	_next_attack = (_next_attack + 1) % ATTACKS.size()

	# A swing carries you forward: one impulse, bled off by the raised damping
	# below rather than by a clock of its own.
	var facing := -global_basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		facing = facing.normalized()
		velocity.x += facing.x * attack_lunge
		velocity.z += facing.z * attack_lunge


## When the stroke in progress stops biting -- the earliest a new one may begin.
## A spin is committed through its full turn and hands control back the
## instant the turn is complete (SPIN_TURN); its recovery can be cut into.
func _bite_end() -> float:
	return SPIN_TURN if _pose_kind == &"spin" else SWING_HOLD


## The spin's turn is complete: from here the player has full control again --
## look, walk, attack, block -- while the blade finishes coming home.
func _spin_released() -> bool:
	return _pose_kind == &"spin" and _pose_time >= SPIN_TURN


## An attack is slowing the player down (a cut, a spin until its turn ends).
func _attack_slows() -> bool:
	return _attacking and not _spin_released()


## Q ("thrust" action) with the sword: one full turn, blade held out, cutting
## all round. The same hit as a cut -- `attack_damage`, `attack_push`,
## `attack_stun`, once per body -- through the same swept-blade test; the price
## of the reach is the long, committed animation (SPIN_END).
func _start_spin() -> void:
	if _slamming or _now() < _slam_recover_until or _pose_kind == &"haft" or _blocking \
			or _ghosting or is_drinking():
		return
	# Q overrides a cut in progress, as the heavy attack does: the slash or chop
	# is dropped where it is and the spin begins (it winds up from wherever the
	# blade is). Only a spin still turning refuses another.
	if _pose_kind == &"spin" and not _spin_released():
		return
	_attacking = true
	_stroke_damage = attack_damage * weapon_damage_scale(&"sword")
	_trail_on = false
	_hit_this_swing.clear()
	_blade_prev.clear()
	_begin_pose(&"spin")
	# The turn is the roll; the punch of the view comes as the spin lets go.
	_swing_roll = 1.0


## --- Block and parry -----------------------------------------------------------
##
## Right click ("block") held raises the sword across the body (`_guard_pose`). A blow
## from the front while it is up is BLOCKED, or PARRIED if the block went up
## within `parry_window` of the blow landing -- see `_guard`, called from
## `take_damage`. Pressed during an attack (a cut, a thrust, a slam or a
## scripted pose), the guard waits: the attack plays to its end, and if the
## button is still held then, the guard goes straight up (`_hold_guard`, polled
## every physics tick).

func _start_block() -> void:
	if _blocking or _dead or in_cutscene or ui_open or hands_busy or latched_to != null or not Inventory.is_weapon(held_item()) \
			or is_drinking() or _ghosting:
		return
	if _slamming or _now() < _slam_recover_until or _pose_kind in [&"haft", &"stab", &"raise", &"slam"]:
		return
	# Waits out a cut; a spin only until its turn is complete.
	if (_attacking or _pose_kind in [&"slash", &"chop", &"spin"]) and not _spin_released():
		return
	# The spear's own attacks wait the same way, and a thrown spear takes its
	# haft -- and the shield in it -- with it until it is caught.
	if held_item() == &"spear" and (spear.busy() or is_spear_dashing()):
		return
	# The axe likewise; thrown, there is nothing in the hands to guard with.
	if held_item() == &"axe" and axe.busy():
		return
	_attacking = false
	_hit_window_open = false
	_trail_on = false
	_blocking = true
	_block_since = _now()
	_block_item = held_item()
	# The sword's guard is a pose on its pivot; other weapons read
	# `is_blocking()` and pose themselves (spear.gd). The pose kind is set
	# either way, since it is what `_check_block` and the attack code test.
	_begin_pose(&"block")
	guard_changed.emit(true)


## The block button still held once whatever refused it has finished (an attack
## playing out, a slam's recovery): up it goes. Only with the mouse captured --
## a click that only takes the mouse back is not a block.
var _guard_click_spent := false


func _hold_guard() -> void:
	if not _blocking and not _guard_click_spent and Coop.aim_ready(self) \
			and _action_held(&"block"):
		_start_block()


func _end_block() -> void:
	if not _blocking:
		return
	_blocking = false
	if _pose_kind == &"block":
		_begin_pose(&"unblock")
	guard_changed.emit(false)


func is_blocking() -> bool:
	return _blocking


## The guard eased 0 -> 1 as it goes up (`GUARD_UP`) and back down
## (`GUARD_DOWN`), for anything that animates with it -- the haft's shield.
func guard_amount() -> float:
	return _guard_level * _guard_level * (3.0 - 2.0 * _guard_level)


## The weapon the guard went up with; `_guard_level` 0..1, stepped in `_process`.
var _block_item: StringName = &""
var _guard_level := 0.0


## Drops the guard if anything has made holding it impossible -- including a
## release that never arrived (the window losing focus mid-press).
func _check_block() -> void:
	if not _blocking:
		return
	# Switching weapons drops it; `_hold_guard` puts it straight back up with
	# the new one if the button is still held.
	if not _action_held(&"block") or held_item() != _block_item \
			or hands_busy or in_cutscene or ui_open or _dead or _slamming or _ghosting \
			or _pose_kind != &"block":
		_end_block()


## The sword across the body, flat to the front; a guarded blow knocks it a
## little forward and up (`_guard_kick`).
func _guard_pose() -> Transform3D:
	var pose := _blade_pose(GUARD_HAND, GUARD_DIR, GUARD_EDGE)
	if _guard_kick > 0.0:
		var k := _guard_kick * _guard_kick
		pose = Transform3D(Basis(Vector3.RIGHT, 0.18 * k) * pose.basis,
			pose.origin + Vector3(0.0, 0.06, -0.22) * k)
	return pose


## 0 the blow lands in full, 1 blocked, 2 parried. Only blows from the front
## are met by the sword; `blow` is the way the blow travels (attacker to player).
##
## Two rules for the parry:
##   * an attack that CUED it (`parry_cue`, 2026-10-17): parried if block was
##     PRESSED inside the window the cue opened -- a tap counts, held or not --
##     and the press was not wasted (a weapon in hand, free to guard). Missed,
##     it is a block if the guard is up, else it lands.
##   * any other blow: parried if the guard went up within `parry_window` of
##     it landing; blocked if up longer.
func _guard(blow: Vector3, attacker: Node3D = null) -> int:
	var front := true
	var from := -blow
	from.y = 0.0
	if from.length_squared() > 0.0001:
		var forward := -global_basis.z
		forward.y = 0.0
		front = rad_to_deg(forward.normalized().angle_to(from.normalized())) <= block_arc
	var cue = _take_parry_cue(attacker)
	if cue != null:
		if front and _block_pressed_at >= float(cue[0]) and _block_pressed_at <= float(cue[1]):
			return 2
		return 1 if _blocking and front else 0
	if not _blocking or not front:
		return 0
	return 2 if _now() - _block_since <= parry_window else 1


## --- Parry cues (2026-10-17) -------------------------------------------------------
##
## An attack marks a point in itself -- its cue -- and calls `parry_cue(self,
## listen)` there: from that moment the game listens `listen` seconds for the
## block button. When that attacker's blow lands (`_guard`), a press inside the
## window parries it. Each attack sets its own cue and window (decrepit.gd's
## moves: `cue` and `listen` in `_spec`), so a slow, telegraphed blow can be
## forgiving and a fast one tight. A press counts if it could have raised the
## guard (a weapon in hand, not drinking, ghosting, dead, in a scene or a menu,
## knocked down or in a slam's recovery) -- mid-attack too: it is the press that is timed, not the guard.

## When block was last pressed (and could have counted), `_now()` seconds.
var _block_pressed_at := -INF
## Open cues: attacker instance id -> [opened, closes], `_now()` seconds.
var _parry_cues := {}


## Called by an attack at its cue: listen for block for `listen` seconds.
func parry_cue(attacker: Node3D, listen: float) -> void:
	if attacker == null:
		return
	var now := _now()
	_parry_cues[attacker.get_instance_id()] = [now, now + listen]
	# Forgotten ones (an attack broken off before its blow) are dropped here.
	for id in _parry_cues.keys():
		if float(_parry_cues[id][1]) < now - 5.0:
			_parry_cues.erase(id)


## The cue `attacker` opened, used up by its blow; null if it opened none.
func _take_parry_cue(attacker: Node3D):
	if attacker == null or not is_instance_valid(attacker):
		return null
	var id := attacker.get_instance_id()
	if not _parry_cues.has(id):
		return null
	var cue = _parry_cues[id]
	_parry_cues.erase(id)
	return cue


## Whether the press that just came would count toward a cued parry.
func _note_block_press() -> void:
	if _dead or in_cutscene or ui_open or latched_to != null or not Inventory.is_weapon(held_item()) \
			or is_drinking() or _ghosting:
		return
	# Down on the floor (knocked down) or in a slam's recovery: no guard to raise.
	if _slamming or _now() < _slam_recover_until:
		return
	_block_pressed_at = _now()


## `blow_damage`: what the blow would have done unguarded; a parry turns
## `parry_reflect` of it back on the attacker.
func _on_guarded(parry: bool, blow: Vector3, attacker: Node3D, blow_damage := 0.0) -> void:
	_guard_kick = 1.0 if parry else 0.45
	_shake = maxf(_shake, 0.32 if parry else 0.14)
	var eye := camera.global_position
	var toward := -blow
	var at := Vector3.ZERO
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("guard_flash_centre") \
			and attacker.guard_flash_centre():
		# Something on the face (a crier): the flash goes dead in the middle of
		# the view, where the player is looking, not up over its head.
		at = eye - camera.global_basis.z * 1.15
	else:
		if attacker != null and is_instance_valid(attacker):
			toward = (attacker.global_position + Vector3(0.0, 1.3, 0.0)) - eye
		if toward.length_squared() < 0.0001:
			toward = -camera.global_basis.z
		at = eye + toward.normalized() * 1.15 + Vector3(0.0, -0.12, 0.0)
	if parry:
		if attacker != null and is_instance_valid(attacker) and attacker.has_method("apply_knockback"):
			var away := attacker.global_position - global_position
			away.y = 0.0
			away = away.normalized() if away.length_squared() > 0.0001 else -global_basis.z
			attacker.apply_knockback(away * parry_push, parry_stun)
		# Its own blow, turned back on it. After the shove, so a blow that kills
		# it does not shove a corpse.
		if attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage") \
				and blow_damage * parry_reflect > 0.0:
			var back := attacker.global_position - global_position
			back.y = 0.0
			attacker.take_damage(blow_damage * parry_reflect, back.normalized() if back.length_squared() > 0.0001 else Vector3.ZERO)
			hit_landed.emit(attacker)
		# A beat of hit-stop sells it.
		_slowmo(0.15, 0.09, 0.22)
		_guard_flash(at, parry_color, true)
	else:
		_guard_flash(at, block_spark_color, false)
	guarded.emit(parry, attacker)


## The flash where the sword meets a blow: a ring that bursts outward and a
## soft core, plus (with `Graphics.effects`) sparks and a flash of light. Purple
## and big for a parry, small and warm for a block. Played on the real clock,
## so the parry's hit-stop does not drag it out.
func _guard_flash(at: Vector3, colour: Color, big: bool) -> void:
	var parent := get_parent() as Node3D
	if parent == null:
		return
	var holder := Node3D.new()
	holder.name = "GuardFlash"
	holder.top_level = true
	parent.add_child(holder)
	holder.global_position = at
	var ring := _flash_quad(_flash_material(colour, true), 1.0)
	holder.add_child(ring)
	var core := _flash_quad(_flash_material(colour, false), 0.8 if big else 0.45)
	holder.add_child(core)
	var grow := 2.4 if big else 1.0
	var life := 0.32 if big else 0.2
	ring.scale = Vector3.ONE * 0.15
	var t := holder.create_tween().set_parallel(true).set_ignore_time_scale(true)
	t.tween_property(ring, "scale", Vector3.ONE * grow, life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(ring, "transparency", 1.0, life).set_ease(Tween.EASE_IN)
	t.tween_property(core, "scale", Vector3.ONE * 1.4, life * 0.7).set_ease(Tween.EASE_OUT)
	t.tween_property(core, "transparency", 1.0, life * 0.7)
	if Graphics.effects:
		holder.add_child(_flash_sparks(colour, 40 if big else 12, 6.5 if big else 3.5))
		var light := OmniLight3D.new()
		light.light_color = colour
		light.light_energy = 6.0 if big else 2.0
		light.omni_range = 6.0 if big else 3.0
		light.shadow_enabled = false
		light.light_specular = 0.0
		holder.add_child(light)
		t.tween_property(light, "light_energy", 0.0, life + 0.1)
	t.chain().tween_interval(0.35)
	t.chain().tween_callback(holder.queue_free)


static var _flash_materials := {}


## A soft additive billboard: a ring (bright at 70% of its radius) or a core
## (bright in the middle). One material per colour and shape, kept.
static func _flash_material(colour: Color, ring: bool) -> StandardMaterial3D:
	var key := "%s_%s" % [colour.to_html(), ring]
	if _flash_materials.has(key):
		return _flash_materials[key]
	var grad := Gradient.new()
	if ring:
		grad.offsets = PackedFloat32Array([0.0, 0.55, 0.72, 0.85, 1.0])
		grad.colors = PackedColorArray([Color(colour, 0.0), Color(colour, 0.15),
			Color(colour.lightened(0.35), 1.0), Color(colour, 0.35), Color(colour, 0.0)])
	else:
		grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
		grad.colors = PackedColorArray([Color(colour.lightened(0.6), 1.0), Color(colour, 0.7), Color(colour, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.disable_fog = true
	m.albedo_texture = tex
	m.albedo_color = Color(1.6, 1.6, 1.6)
	_flash_materials[key] = m
	return m


static func _flash_quad(material: Material, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _flash_sparks(colour: Color, amount: int, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = amount
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3(0.0, 0.2, 0.0)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -7.0, 0.0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(colour.lightened(0.5), 1.0), Color(colour, 0.0)])
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	quad.material = m
	p.mesh = quad
	return p


## The flash's materials compile on first draw; draw a speck of each now, while
## the level loads, rather than stalling the first parry.
func _warm_guard_flash() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	for colour: Color in [parry_color, block_spark_color]:
		for ring: bool in [true, false]:
			var speck := _flash_quad(_flash_material(colour, ring), 0.002)
			camera.add_child(speck)
			speck.position = Vector3(0.0, 0.0, -0.5)
			get_tree().create_timer(0.5).timeout.connect(speck.queue_free)
	var sparks := _flash_sparks(parry_color, 1, 0.0)
	sparks.scale_amount_min = 0.01
	sparks.scale_amount_max = 0.01
	camera.add_child(sparks)
	sparks.position = Vector3(0.0, 0.0, -0.5)
	get_tree().create_timer(0.6).timeout.connect(sparks.queue_free)


## --- The sword, posed in code -------------------------------------------------
##
## Swings and the slam's strike on the ground drive Head/SwordPivot directly
## instead of through the AnimationPlayer, which is paused meanwhile. A stroke is
## laid out as poses in the head's frame -- where the hand is, which way the
## blade points, which way its edge leads -- and travels the curve
## wind-up -> middle -> follow-through, so the blade really sweeps across the
## view. It ends exactly on the idle clip's first frame, where the player
## resumes, so nothing snaps.

## Idle clip, frame 0: where every pose ends.
const REST_POS := Vector3(0.34, -0.85, -0.35)
const REST_ROT := Vector3(-1.113895, 0.0, -0.244346)
## A stroke's timeline, seconds: into the wind-up, the cut, the follow-through
## held, and back to rest. The blade bites from SWING_WIND to SWING_HOLD.
const SWING_WIND := 0.07
const SWING_CUT := 0.21
const SWING_HOLD := 0.27
const SWING_END := 0.42
## The slam's: blade down onto the floor ahead, held, then up as the player rises.
const SLAM_STRIKE := 0.05
const SLAM_HOLD := 0.14
## The stroke's arc: how far it opens either side of straight ahead, always the
## same whatever is around. The blade crosses the crosshair SWING_CROSS metres
## out (`_cut_pitch`), on a diagonal from high to low of SWING_TILT radians.
const SWING_OPEN := 1.66
const SWING_CROSS := 2.0
const SWING_TILT := 0.42
## How far above the floor the struck tip rests.
const SLAM_TIP_LIFT := 0.03
## The spin's timeline: the blade wound back out to the right and the view
## coiled a little against the turn (SPIN_WIND), then the VIEW turns one full
## circle to the left with the blade held out leading it (SPIN_WIND to
## SPIN_TURN -- it bites all the way round), then the blade is brought home
## (SPIN_END). Only the head turns, never the body, so the aim is exactly where
## it was afterwards. The slash is done by 0.42 s; the spin takes a full second
## and cannot be cut short (`_bite_end`), which is what stops it being spammed.
const SPIN_WIND := 0.2
const SPIN_TURN := 0.62
const SPIN_END := 1.0
## How far the view turns back against the spin in the wind-up (radians), and
## where the blade is held through the turn: yaw from straight ahead, leading
## the turn on the left.
const SPIN_COIL := 0.3
const SPIN_LEAD := -0.45
## The guard: hand forward of the chest, blade rising across the view to the
## upper left with its flat to the front, and how long it takes to go up and down.
const GUARD_HAND := Vector3(0.36, -0.4, -0.7)
const GUARD_DIR := Vector3(-0.8, 0.5, -0.33)
const GUARD_EDGE := Vector3(0.52, 0.85, 0.0)
const GUARD_UP := 0.1
const GUARD_DOWN := 0.16

func _begin_pose(kind: StringName) -> void:
	if _stab_depth and kind != &"stab":
		_stab_depth = false
		_set_sword_depth(sword_draw_depth)
	anim.pause()
	_pose_kind = kind
	_pose_time = 0.0
	_pose_from = sword_pivot.transform


func _end_pose() -> void:
	if _stab_depth:
		_stab_depth = false
		_set_sword_depth(sword_draw_depth)
	_pose_time = -1.0
	_pose_kind = &""
	_attacking = false
	_hit_window_open = false
	_trail_on = false
	sword_pivot.transform = _rest_pose()
	# Straight onto the idle clip's first frame -- the pose just ended there --
	# with no blend from wherever the paused clip had been.
	anim.play(&"idle", 0.0)
	anim.seek(0.0, true)
	_update_locomotion()


func _update_pose(delta: float) -> void:
	if _pose_time < 0.0:
		return
	_pose_time += delta
	var length := SWING_END
	if _pose_kind == &"slam":
		length = slam_recover_time + SLAM_STRIKE
	elif _pose_kind == &"haft":
		length = HAFT_END
	elif _pose_kind == &"spin":
		length = SPIN_END
	elif _pose_kind == &"block":
		length = INF
	elif _pose_kind == &"unblock":
		length = GUARD_DOWN
	elif _pose_kind == &"stab":
		length = STAB_END
	elif _pose_kind == &"raise":
		# Held overhead until the slam lands and starts the strike.
		length = INF
	if _pose_time >= length:
		_end_pose()
		return
	if _pose_kind == &"slam":
		sword_pivot.transform = _slam_pose(_pose_time)
		return
	if _pose_kind == &"raise":
		var k := clampf(_pose_time / maxf(slam_ground_windup * 0.8, 0.01), 0.0, 1.0)
		# Up fast, then hanging at the top for the instant before it falls.
		var raised := _blade_pose(Vector3(0.22, 0.18, -0.5), Vector3(0.08, 0.95, 0.3), Vector3(0.0, 0.0, -1.0))
		sword_pivot.transform = _blend(_pose_from, raised, 1.0 - (1.0 - k) * (1.0 - k))
		return
	if _pose_kind == &"haft":
		if not _haft_landed:
			_aim_haft()
		sword_pivot.transform = _haft_pose(_pose_time)
		if not _haft_landed and _pose_time >= HAFT_HIT:
			_land_haft()
		return
	if _pose_kind == &"spin":
		sword_pivot.transform = _spin_pose(_pose_time)
		# Bites from the moment the turn starts to the moment it ends: the
		# blade is out the whole way round.
		_hit_window_open = _pose_time >= SPIN_WIND and _pose_time <= SPIN_TURN
		# The cut's white trail, all the way round (`_update_sweep_trail`).
		_trail_on = _pose_time >= SPIN_WIND * 0.6 and _pose_time <= SPIN_TURN + 0.03
		if _pose_time >= SPIN_TURN and _pose_time - delta < SPIN_TURN:
			# The release: a punch of the view and a shake as it comes round.
			_swing_kick = maxf(_swing_kick, 0.9)
			_shake = maxf(_shake, 0.2)
		return
	if _pose_kind == &"block":
		var k := clampf(_pose_time / GUARD_UP, 0.0, 1.0)
		sword_pivot.transform = _blend(_pose_from, _guard_pose(), 1.0 - (1.0 - k) * (1.0 - k))
		return
	if _pose_kind == &"unblock":
		sword_pivot.transform = _blend(_pose_from, _rest_pose(),
			smoothstep(0.0, 1.0, _pose_time / GUARD_DOWN))
		return
	if _pose_kind == &"stab":
		sword_pivot.transform = _stab_pose(_pose_time)
		_update_stab_events()
		return
	sword_pivot.transform = _swing_pose(_pose_time, _pose_kind == &"chop")
	_hit_window_open = _pose_time >= SWING_WIND and _pose_time <= SWING_HOLD
	_trail_on = _pose_time >= SWING_WIND * 0.6 and _pose_time <= SWING_HOLD + 0.03


func _rest_pose() -> Transform3D:
	return Transform3D(Basis.from_euler(REST_ROT), REST_POS)


## Seconds since the lunge (game clock), or -1 when there is none to show.
var _lunge_age := -1.0


## The lunge's effects, 0..1: in over the first 60 ms of the drive, out over the
## rest of `lunge_effect_time`. Drives the HUD's speed lines and the FOV.
func lunge_intensity() -> float:
	if _lunge_age < 0.0 or _lunge_age >= lunge_effect_time:
		return 0.0
	if _lunge_age < 0.06:
		return _lunge_age / 0.06
	var k := 1.0 - (_lunge_age - 0.06) / maxf(lunge_effect_time - 0.06, 0.01)
	return k * k


func lunge_age() -> float:
	return maxf(_lunge_age, 0.0)


func _update_lunge(delta: float) -> void:
	if _lunge_age < 0.0:
		return
	_lunge_age += delta
	if _lunge_age >= lunge_effect_time:
		_lunge_age = -1.0


## The blade's pitch all the way round, solved once: level, SPIN_DROP below the
## pitch that would pass the crosshair point straight ahead. Exactly at eye
## height the circle -- and its trail -- is seen edge-on and collapses into a
## flat line along the horizon; at chest height it reads as a sweep arcing
## across the lower half of the view, and still cuts through a skeleton's torso.
## (The blade is held at `SPIN_LEAD`, not straight ahead, but the pitch is the
## same all the way round.)
const SPIN_DROP := 0.25
var _spin_pitch := NAN


func _spin_level() -> float:
	if is_nan(_spin_pitch):
		_spin_pitch = _cut_pitch(0.0, true) - SPIN_DROP
	return _spin_pitch


## The blade through the spin, in head space: wound out to the right as the
## view coils, swept across to `SPIN_LEAD` on the left in the first quarter of
## the turn and held there, leading it, at a level pitch while the HEAD turns
## the full circle (`_spin_view_yaw`) -- so in the world the blade sweeps the
## whole circle round the player -- then brought home like a cut's recovery.
func _spin_pose(t: float) -> Transform3D:
	var level := _spin_level()
	if t < SPIN_WIND:
		var k := t / SPIN_WIND
		k = 1.0 - (1.0 - k) * (1.0 - k)
		var aim := _aim_of(_pose_from)
		return _blend(_pose_from, _arc_pose(lerpf(aim.x, SWING_OPEN, k),
			lerpf(aim.y, level, k), true), k)
	if t < SPIN_TURN:
		var s := smoothstep(0.0, 1.0, (t - SPIN_WIND) / ((SPIN_TURN - SPIN_WIND) * 0.25))
		return _arc_pose(lerpf(SWING_OPEN, SPIN_LEAD, s), level, true)
	var r := smoothstep(0.0, 1.0, (t - SPIN_TURN) / (SPIN_END - SPIN_TURN))
	var home := _aim_of(_rest_pose())
	return _blend(_arc_pose(lerpf(SPIN_LEAD, home.x, r), lerpf(level, home.y, r), true), _rest_pose(), r)


## The head's extra yaw through a spin at pose time `t`: back against it in the
## wind-up, then a full turn to the LEFT (+rotation.y), fast in the middle,
## ending on exactly a whole turn -- the same as none, so the view lands where
## it started.
func _spin_yaw_at(t: float) -> float:
	if t < 0.0:
		return 0.0
	if t < SPIN_WIND:
		var k := t / SPIN_WIND
		return -SPIN_COIL * (1.0 - (1.0 - k) * (1.0 - k))
	if t < SPIN_TURN:
		var s := smoothstep(0.0, 1.0, (t - SPIN_WIND) / (SPIN_TURN - SPIN_WIND))
		return lerpf(-SPIN_COIL, TAU, s)
	return 0.0


## `ahead`: the head is placed (`_update_head`) before `_update_pose` advances
## the stroke by the same delta, so it asks for the turn where the stroke WILL
## be this frame -- otherwise the view lags the blade and its trail by a frame
## (~0.37 rad at full speed) and the streak runs on past the blade.
func _spin_view_yaw(ahead := 0.0) -> float:
	if _pose_kind != &"spin" or _pose_time < 0.0:
		return 0.0
	return _spin_yaw_at(_pose_time + ahead)


## The camera through a spin, selling the effort without turning the view:
## (roll deg, pitch deg, drop m, fov deg). Wind-up: leaning back into the coil,
## head low, the view drawing in tight. The drive: leaning hard into the turn,
## crouched lower, the view rushing open, trembling with the strain while the
## blade is fastest. The release (with a punch and a shake, `_update_pose`):
## everything eases back.
func _spin_effort() -> Vector4:
	if _pose_kind != &"spin" or _pose_time < 0.0:
		return Vector4.ZERO
	var t := _pose_time
	var coil := Vector4(spin_effort_roll * -0.6, -2.0, spin_effort_drop * 0.55, -3.0)
	var drive := Vector4(spin_effort_roll, -1.0, spin_effort_drop, spin_effort_fov)
	if t < SPIN_WIND:
		var k := t / SPIN_WIND
		k = 1.0 - (1.0 - k) * (1.0 - k)
		var e := coil * k
		# Straining against the coil: a tremor that builds.
		e.x += sin(t * 61.0) * 0.35 * k
		return e
	if t < SPIN_TURN:
		var s := (t - SPIN_WIND) / (SPIN_TURN - SPIN_WIND)
		var e := coil.lerp(drive, smoothstep(0.0, 0.35, s))
		var strain := sin(PI * s)
		var n := float(Time.get_ticks_msec()) / 1000.0 * 40.0
		e.x += _bob_noise.get_noise_2d(n, 5.0) * 1.4 * strain
		e.y += _bob_noise.get_noise_2d(n, 23.0) * 0.8 * strain
		e.z += absf(_bob_noise.get_noise_2d(n, 41.0)) * 0.012 * strain
		return e
	var r := smoothstep(0.0, 1.0, (t - SPIN_TURN) / (SPIN_END - SPIN_TURN))
	return drive * (1.0 - r)


## The pivot pose that puts the hilt (the guard) at `at` with the blade aimed
## at `aim` (head space), its flat tipped a little so it reads as a blade, not a
## line.
func _hilt_at(at: Vector3, aim: Vector3) -> Transform3D:
	var pose := _blade_pose(Vector3.ZERO, aim - at, Vector3(1.0, 0.45, 0.0))
	pose.origin = at - pose.basis * (_sword_rest * _blade_base)
	return pose


## --- Scripted stab -------------------------------------------------------------
##
## For scenes (the bone cages): the sword is drawn whatever is held, hauled back
## high by the shoulder and driven violently at a point in the world. On contact
## `stab_landed` fires -- the scene breaks whatever was hit -- with a hit-stop,
## a hard shake and a punch of the view; the blade is held in, twisted, and
## pulled back out.

## Timeline, game seconds: hauled back (STAB_COCK), a beat held there, driven in
## (the tip enters at STAB_HIT), held in while it is wrenched round (the wrench
## lands at STAB_WRENCH), held, and out.
const STAB_COCK := 0.3
const STAB_DRIVE := 0.4
const STAB_HIT := 0.47
const STAB_WRENCH := 0.66
const STAB_HOLD := 0.82
const STAB_END := 1.2
## The shoulder the blade is aimed from, head space: the hilt travels along the
## line from here to the target.
const STAB_SHOULDER := Vector3(0.3, -0.26, 0.0)
## How far the hilt is driven, cocked to struck, metres.
const STAB_TRAVEL := 0.6

var _stab_target := Vector3.ZERO
var _stab_through := 0.14
var _stab_landed := false
var _stab_wrenched := false
var _stab_depth := false


## Guard to tip, metres: what a scene needs to stand the player far enough off
## for the tip, and not the middle of the blade, to reach what it stabs.
func blade_length() -> float:
	return (_sword_rest.basis * (_blade_tip - _blade_base)).length()


## Drives the TIP of the sword `through` metres past `world_target`. The scene
## should stand the player about `blade_length() + 0.9` from it; nearer, the
## tip goes further through.
func stab_at(world_target: Vector3, through := 0.14) -> void:
	_stab_target = world_target
	_stab_through = through
	_stab_landed = false
	_stab_wrenched = false
	_attacking = false
	_hit_window_open = false
	_trail_on = false
	_scene_weapon = _weapon_in_hand()
	if _scene_weapon == &"sword":
		_sword_duck = 0.0
		_duck_vel = 0.0
	else:
		_spear_from = spear.transform
	_begin_pose(&"stab")
	# Drawn with real depth for this, so whatever it goes into hides the part of
	# the blade inside it. Only the uniform changes: toggling the feature would
	# compile a shader variant mid-scene.
	_set_sword_depth(1.0)
	_stab_depth = true


## --- Scenes with the weapon in hand ---------------------------------------------
##
## The scripted stab (the bone cages) and the haft strike (bombers) are done with
## the weapon in hand: the spear if that is what is held (driven through the
## skull; its BUTT into the bomber), otherwise the sword. The timeline, the hit
## events and the camera are the same either way; only the model posed differs.
## The spear is posed from here (`spear_scene_pose`, read by spear.gd).

var _scene_weapon := &"sword"
var _spear_from := Transform3D()


func _weapon_in_hand() -> StringName:
	if held_item() == &"spear" and spear != null and spear.has_method("ready_in_hand") \
			and bool(spear.call("ready_in_hand")):
		return &"spear"
	return &"sword"


## How far the weapon a scene will use reaches, hand-side end to tip: what a
## scene stands the player off by.
func scene_reach() -> float:
	if _weapon_in_hand() == &"spear":
		return float(spear.get("TIP_REACH"))
	return blade_length()


## The spear's pose (head space) while a scene drives it, or null.
func spear_scene_pose() -> Variant:
	if _scene_weapon != &"spear" or spear == null:
		return null
	if _pose_kind == &"stab":
		return _spear_stab_pose(_pose_time)
	if _pose_kind == &"haft":
		return _spear_haft_pose(_pose_time)
	return null


## The spear on the same line and timeline as the sword's stab: the hand drawn
## back along the line from the shoulder, driven in until the TIP is
## `_stab_through` past the target, wrenched round its own length, pulled out.
func _spear_stab_pose(t: float) -> Transform3D:
	var aim := head.global_transform.affine_inverse() * _stab_target
	var dir := (aim - STAB_SHOULDER).normalized()
	var reach: float = spear.get("TIP_REACH")
	var struck_at := aim - dir * (reach - _stab_through)
	var cocked_at := struck_at - dir * STAB_TRAVEL
	cocked_at.z = minf(cocked_at.z, -0.12)
	var b: Basis = spear.call("_facing", dir)
	var cocked := Transform3D(b, cocked_at)
	var struck := Transform3D(b, struck_at)
	if t < STAB_COCK:
		var k := t / STAB_COCK
		return _spear_from.interpolate_with(cocked, 1.0 - (1.0 - k) * (1.0 - k))
	if t < STAB_DRIVE:
		var q := sin(t * 90.0) * 0.004
		return Transform3D(b, cocked_at + Vector3(q, -q, 0.0))
	if t < STAB_HIT:
		var k := (t - STAB_DRIVE) / (STAB_HIT - STAB_DRIVE)
		return cocked.interpolate_with(struck, k * k * k)
	var turn := smoothstep(STAB_HIT + 0.08, STAB_WRENCH, minf(t, STAB_HOLD))
	var twisted := Transform3D(b * Basis(Vector3.FORWARD, 0.9 * turn), struck_at)
	if t < STAB_HOLD:
		return twisted
	var rest: Transform3D = spear.call("_rest")
	return twisted.interpolate_with(rest, smoothstep(0.0, 1.0, (t - STAB_HOLD) / (STAB_END - STAB_HOLD)))


## The spear reversed for a haft strike: the head back over the right shoulder,
## the BUTT driven out along the line to the target -- as the sword's pommel is.
func _spear_haft_pose(t: float) -> Transform3D:
	var tip_dir := (-_haft_dir * 0.6 + Vector3(0.45, 0.75, 0.0)).normalized()
	var b: Basis = spear.call("_facing", tip_dir)
	var butt: float = spear.get("BUTT_REACH")
	# The hand sits up the shaft from the butt, toward the head.
	var cocked := Transform3D(b, Vector3(0.28, -0.5, -0.3) + tip_dir * butt)
	var struck := Transform3D(b, _haft_dir * 1.0 + tip_dir * butt)
	if t < HAFT_COCK:
		var k := t / HAFT_COCK
		return _spear_from.interpolate_with(cocked, 1.0 - (1.0 - k) * (1.0 - k))
	if t < HAFT_HIT:
		var k := (t - HAFT_COCK) / (HAFT_HIT - HAFT_COCK)
		return cocked.interpolate_with(struck, k * k)
	if t < HAFT_HOLD:
		return struck
	var rest: Transform3D = spear.call("_rest")
	return struck.interpolate_with(rest, smoothstep(0.0, 1.0, (t - HAFT_HOLD) / (HAFT_END - HAFT_HOLD)))


func _set_sword_depth(scale: float) -> void:
	if spear != null and spear.has_method("set_depth"):
		spear.call("set_depth", scale)
	if sword_model == null:
		return
	for node in sword_model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(i) as BaseMaterial3D
			if mat != null and mat.use_z_clip_scale:
				mat.z_clip_scale = scale


## The hilt (head space) cocked and struck, both on the line from the shoulder
## to the target, struck so the tip ends `_stab_through` past it.
func _stab_line() -> Array:
	var aim := head.global_transform.affine_inverse() * _stab_target
	var dir := (aim - STAB_SHOULDER).normalized()
	var struck_at := aim - dir * (blade_length() - _stab_through)
	var cocked_at := struck_at - dir * STAB_TRAVEL
	# Never drawn back behind the eye.
	cocked_at.z = minf(cocked_at.z, -0.12)
	return [aim, cocked_at, struck_at]


func _stab_pose(t: float) -> Transform3D:
	var line := _stab_line()
	var aim: Vector3 = line[0]
	var cocked := _hilt_at(line[1], aim)
	var struck := _hilt_at(line[2], aim)
	if t < STAB_COCK:
		var k := t / STAB_COCK
		return _blend(_pose_from, cocked, 1.0 - (1.0 - k) * (1.0 - k))
	if t < STAB_DRIVE:
		# Held back, quivering, for a beat.
		var q := sin(t * 90.0) * 0.004
		return Transform3D(cocked.basis, cocked.origin + Vector3(q, -q, 0.0))
	if t < STAB_HIT:
		# Accelerating all the way in.
		var k := (t - STAB_DRIVE) / (STAB_HIT - STAB_DRIVE)
		return _blend(cocked, struck, k * k * k)
	var twist := _stab_twist(struck, line[2], t)
	if t < STAB_HOLD:
		return twist
	return _blend(twist, _rest_pose(), smoothstep(0.0, 1.0, (t - STAB_HOLD) / (STAB_END - STAB_HOLD)))


## Held in, then wrenched a vicious quarter turn about the blade.
func _stab_twist(struck: Transform3D, hilt: Vector3, t: float) -> Transform3D:
	var k := smoothstep(STAB_HIT + 0.08, STAB_WRENCH, minf(t, STAB_HOLD))
	var axis := (struck.basis * _blade_frame.y).normalized()
	var turn := Basis(axis, 0.9 * k)
	return Transform3D(turn * struck.basis, hilt + turn * (struck.origin - hilt))


func _land_stab() -> void:
	_stab_landed = true
	_swing_kick = maxf(_swing_kick, 1.5)
	_shake = maxf(_shake, 0.55)
	# A hit-stop: almost frozen for a beat, then back.
	_slowmo(0.08, 0.12, 0.3)
	stab_landed.emit()


func _update_stab_events() -> void:
	if not _stab_landed and _pose_time >= STAB_HIT:
		_land_stab()
	if _stab_landed and not _stab_wrenched and _pose_time >= STAB_WRENCH:
		_stab_wrenched = true
		_shake = maxf(_shake, 0.35)
		stab_wrenched.emit()
	# Back on top of the world as it comes out.
	if _stab_depth and _pose_time >= STAB_HOLD:
		_stab_depth = false
		_set_sword_depth(sword_draw_depth)


## --- Haft strike ---------------------------------------------------------------
##
## Bombers cannot be cut -- the blade passes through them. The answer to one is
## E ("interact") within reach: the sword is snapped up, blade standing back over
## the shoulder, and the HAFT is driven forward into the bomber, which is knocked
## away and pops without going off. Called by the bomber, which owns the prompt
## and the reach test, like every other thing E is used on.

## Timeline, seconds: cocked, driven home (contact at HAFT_HIT), held, back to rest.
const HAFT_COCK := 0.05
const HAFT_HIT := 0.11
const HAFT_HOLD := 0.16
const HAFT_END := 0.32


var _haft_target: Node3D
## Head-space direction the haft is driven, toward the target, kept in front.
var _haft_dir := Vector3.FORWARD
var _haft_landed := false


## Starts a haft strike at `target` (which must have `swat(direction)`). False
## when the player is in no state to do it.
func haft_strike(target: Node3D) -> bool:
	if _dead or in_cutscene or ui_open or hands_busy or _slamming \
			or _now() < _slam_recover_until or _pose_kind == &"haft":
		return false
	# Striking a bomber is an attack too: it spills a drink.
	_interrupt_drink()
	_haft_target = target
	_haft_landed = false
	_start_haft_camera(target)
	_aim_haft()
	_attacking = false
	_hit_window_open = false
	_trail_on = false
	_scene_weapon = _weapon_in_hand()
	if _scene_weapon == &"sword":
		# In hand at once -- this is a reflex, not a draw.
		_sword_duck = 0.0
		_duck_vel = 0.0
	else:
		_spear_from = spear.transform
	_begin_pose(&"haft")
	return true


## Points the jab at the target from where the head is NOW -- re-aimed every
## frame up to contact, because the camera is turning onto the target meanwhile
## (and the target may be moving), and a direction fixed at the start would put
## the pommel beside it on screen.
func _aim_haft() -> void:
	if _haft_target == null or not is_instance_valid(_haft_target):
		return
	var local := head.global_transform.affine_inverse() * _haft_target.global_position
	# Latched bombers ride the player's shoulders, often beside or behind the
	# view; the jab still goes out front-ish toward them.
	local.z = minf(local.z, -0.35 * local.length())
	_haft_dir = local.normalized() if local.length_squared() > 1e-6 else Vector3.FORWARD


## The turn onto the target, measured from where the player is LOOKING (body
## yaw and `_look_pitch`, none of the head's flourishes), part of the way and
## capped, so a bomber on the shoulder does not spin the view round.
func _start_haft_camera(target: Node3D) -> void:
	var look := Transform3D(global_basis * Basis(Vector3.RIGHT, _look_pitch), head.global_position)
	var local := look.affine_inverse() * target.global_position
	var cap := deg_to_rad(haft_aim_max)
	var yaw := atan2(local.x, -local.z)
	var pitch := atan2(local.y, Vector2(local.x, local.z).length())
	# +rotation.y on the head turns the view LEFT; +rotation.x tips it up.
	_cine_aim = Vector2(clampf(-yaw * haft_aim_share, -cap, cap), clampf(pitch * haft_aim_share, -cap, cap))
	_cine_roll = -1.0 if yaw > 0.05 else 1.0
	_cine_start = _now()
	_cine_hit = -1.0


## This frame's weights for the haft camera: `_cine_a` for the turn, `_cine_z`
## for the zoom and tilt. On the wall clock, so the slow motion it starts does
## not slow the camera that is selling it.
func _update_cine() -> void:
	_cine_a = 0.0
	_cine_z = 0.0
	if _cine_start < 0.0:
		return
	var now := _now()
	if _cine_hit < 0.0:
		if _pose_kind != &"haft":
			# Cut short before contact: just let go.
			_cine_hit = now - haft_slowmo_hold
		else:
			# Turning onto it as the pommel is driven home; a slight push in.
			var k := smoothstep(0.0, HAFT_HIT, now - _cine_start)
			_cine_a = k
			_cine_z = 0.3 * k
			return
	var e := now - _cine_hit
	var settle := haft_slowmo_hold + haft_slowmo_return * 0.35
	var out := smoothstep(settle, settle + haft_settle_time, e)
	if out >= 1.0:
		_cine_start = -1.0
		_cine_hit = -1.0
		return
	_cine_a = 1.0 - out
	# Snaps the rest of the way in on contact.
	_cine_z = lerpf(0.3, 1.0, smoothstep(0.0, 0.05, e)) * (1.0 - out)


## Slow motion from the contact: held at `haft_slowmo_scale`, then eased back.
## Only if nothing else (a door kick) already has the clock slowed.
func _haft_slowmo() -> void:
	_slowmo(haft_slowmo_scale, haft_slowmo_hold, haft_slowmo_return)


## Slow motion at `scale` for `hold` real seconds, eased back over `back`.
func _slowmo(scale: float, hold: float, back: float) -> void:
	# Co-op: no slow motion -- the clock is both players'.
	if Coop.active:
		return
	if not is_equal_approx(Engine.time_scale, 1.0) and (_slowmo_tween == null or not _slowmo_tween.is_valid()):
		return
	if _slowmo_tween != null and _slowmo_tween.is_valid():
		_slowmo_tween.kill()
	Engine.time_scale = scale
	_slowmo_tween = create_tween().set_ignore_time_scale(true)
	# Runs through a pause too, so the pause menu never sits in slow motion.
	_slowmo_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_slowmo_tween.tween_interval(hold)
	_slowmo_tween.tween_method(func(v: float) -> void: Engine.time_scale = v,
		scale, 1.0, back).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_slowmo_tween.tween_callback(func() -> void: Engine.time_scale = 1.0)


func _end_slowmo() -> void:
	if _slowmo_tween != null and _slowmo_tween.is_valid():
		_slowmo_tween.kill()
		Engine.time_scale = 1.0
	_slowmo_tween = null
	_cine_start = -1.0
	_cine_hit = -1.0


func _haft_pose(t: float) -> Transform3D:
	# The sword reversed: the blade lies back over the right shoulder, AWAY from
	# the target, so the grip and pommel point at it and lead the blow. (Stood
	# upright, it read as a sword held in front of the face, pommel down.)
	var blade := (-_haft_dir * 0.6 + Vector3(0.45, 0.75, 0.0)).normalized()
	# Placed by the POMMEL, not the pivot: drawn back by the chest, then driven
	# out a metre along the line to the target, so it lands on it on screen.
	var cocked := _pommel_at(Vector3(0.28, -0.5, -0.3), blade)
	var struck := _pommel_at(_haft_dir * 1.0, blade)
	if t < HAFT_COCK:
		var k := t / HAFT_COCK
		return _blend(_pose_from, cocked, 1.0 - (1.0 - k) * (1.0 - k))
	if t < HAFT_HIT:
		# Accelerating into the blow.
		var k := (t - HAFT_COCK) / (HAFT_HIT - HAFT_COCK)
		return _blend(cocked, struck, k * k)
	if t < HAFT_HOLD:
		return struck
	return _blend(struck, _rest_pose(), smoothstep(0.0, 1.0, (t - HAFT_HOLD) / (HAFT_END - HAFT_HOLD)))


## The pivot pose that puts the pommel at `at` with the blade along `blade`.
func _pommel_at(at: Vector3, blade: Vector3) -> Transform3D:
	var pose := _blade_pose(Vector3.ZERO, blade, Vector3.RIGHT)
	pose.origin = at - pose.basis * (_sword_rest * _blade_pommel)
	return pose


func _land_haft() -> void:
	_haft_landed = true
	_swing_kick = maxf(_swing_kick, 1.2)
	_shake = maxf(_shake, 0.22)
	_cine_hit = _now()
	if _haft_target == null or not is_instance_valid(_haft_target):
		return
	_haft_slowmo()
	var away := _haft_target.global_position - global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 1e-4 else -global_basis.z
	if _haft_target.has_method("swat"):
		_haft_target.swat(away)
		hit_landed.emit(_haft_target)
	_haft_target = null

## A blade pose: the pivot at `at`, the blade (hilt to tip, as measured off the
## model) along `dir` in the head's frame, the flat of the blade turned so its
## width runs towards `edge`. Solved against the model's real axes, so the poses
## mean the same thing whichever way the sword asset happens to be built.
func _blade_pose(at: Vector3, dir: Vector3, edge: Vector3) -> Transform3D:
	var y := dir.normalized()
	var x := (edge - y * edge.dot(y)).normalized()
	var want := Basis(x, y, x.cross(y))
	return Transform3D(want * _blade_frame.inverse(), at)


static func _blend(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	return Transform3D(a.basis.orthonormalized().slerp(b.basis.orthonormalized(), t), a.origin.lerp(b.origin, t))


## The blade at `yaw` (radians from straight ahead, + to the right) and
## `pitch`, travelling left (`leftward`) or right. The hand follows the blade
## round a little, and the flat stays level with its edge leading, so the cut is
## a sweep and not a stab.
func _arc_pose(yaw: float, pitch: float, leftward: bool) -> Transform3D:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var hand := Vector3(0.1 + 0.28 * sin(yaw), -0.52, -0.3 - 0.15 * cos(yaw))
	var edge := Vector3(cos(yaw), 0.0, sin(yaw)) * (-1.0 if leftward else 1.0)
	return _blade_pose(hand, dir, edge)


## Right to left (`backhand` false), or left to right: wound up on one side,
## swept through straight ahead, followed through low on the other.
func _swing_pose(t: float, backhand: bool) -> Transform3D:
	var from_yaw := -SWING_OPEN if backhand else SWING_OPEN
	var to_yaw := SWING_OPEN if backhand else -SWING_OPEN
	var leftward := not backhand
	# Into the wind-up and back to rest the blade also travels ROUND the arc,
	# carried from where it is pointing now. Blending the two orientations
	# directly swung the 2.65 m blade up overhead on its way there (the tip 3 m
	# up).
	if t < SWING_WIND:
		var k := t / SWING_WIND
		k = 1.0 - (1.0 - k) * (1.0 - k)
		var aim := _aim_of(_pose_from)
		return _blend(_pose_from, _arc_pose(lerpf(aim.x, from_yaw, k),
			lerpf(aim.y, _cut_pitch(from_yaw, leftward), k), leftward), k)
	if t < SWING_CUT:
		var s := smoothstep(0.0, 1.0, (t - SWING_WIND) / (SWING_CUT - SWING_WIND))
		# Round the arc itself, so the tip keeps its distance the whole way.
		var yaw := lerpf(from_yaw, to_yaw, s)
		return _arc_pose(yaw, _cut_pitch(yaw, leftward), leftward)
	var low := _cut_pitch(to_yaw, leftward)
	if t < SWING_HOLD:
		return _arc_pose(to_yaw, low, leftward)
	var r := smoothstep(0.0, 1.0, (t - SWING_HOLD) / (SWING_END - SWING_HOLD))
	var home := _aim_of(_rest_pose())
	return _blend(_arc_pose(lerpf(to_yaw, home.x, r), lerpf(low, home.y, r), leftward), _rest_pose(), r)


## The blade's pitch at `yaw` in a cut: aimed so that the blade passes THROUGH
## the crosshair, `SWING_CROSS` metres down the view, as it sweeps across it, and
## tilted from high (where the stroke starts) to low (where it ends) by
## `SWING_TILT` over the whole arc -- the tilt is zero exactly where the blade
## heads at that point, so the diagonal does not lift it off the crosshair.
## Solved against the guard's real place on the model, a few times round.
func _cut_pitch(yaw: float, leftward: bool) -> float:
	var cross := Vector3(0.0, 0.0, -SWING_CROSS)
	var guard := _sword_rest * _blade_base
	var pitch := 0.0
	for i in 3:
		var to := cross - _arc_pose(yaw, pitch, leftward) * guard
		var heading := atan2(to.x, -to.z)
		var tilt := SWING_TILT * (yaw - heading) / (2.0 * SWING_OPEN) * (1.0 if leftward else -1.0)
		pitch = atan2(to.y, Vector2(to.x, to.z).length()) + tilt
	return pitch


## Where a pivot pose points the blade, as (yaw, pitch) in the head's frame.
func _aim_of(pose: Transform3D) -> Vector2:
	var d := (pose.basis * _blade_frame.y).normalized()
	return Vector2(atan2(d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))

## Down onto the floor ahead, held, then lifted back to rest as the player
## stands. The strike is aimed in the WORLD, every frame: the view is crouching,
## rising and shaking all through it, and may be pitched anywhere, so a pose
## fixed to the head put the tip anything up to 0.3 m into the stone. Solved
## instead so the tip rests on the floor in front of the player's feet.
func _slam_pose(t: float) -> Transform3D:
	var hand := Vector3(0.22, -0.62, -0.5)
	var to_head := head.global_basis.inverse()
	var hand_w := head.global_transform * hand
	var length := (_sword_rest * _blade_tip).dot(_blade_frame.y)
	var drop := clampf(global_position.y + SLAM_TIP_LIFT - hand_w.y, -length * 0.95, 0.0)
	var ahead := -global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length_squared() > 1e-4 else Vector3.FORWARD
	var tip_w := hand_w + ahead * sqrt(length * length - drop * drop) + Vector3(0.0, drop, 0.0)
	var strike := _blade_pose(hand, to_head * (tip_w - hand_w), to_head * Vector3.DOWN)
	if t < SLAM_STRIKE:
		var k := t / SLAM_STRIKE
		return _blend(_pose_from, strike, k * k)
	if t < SLAM_HOLD:
		return strike
	var span := slam_recover_time + SLAM_STRIKE
	return _blend(strike, _rest_pose(), smoothstep(0.0, 1.0, (t - SLAM_HOLD) / (span - SLAM_HOLD)))

## Every pair gets an explicit cross-fade, so no transition anywhere can snap.
## Set here rather than authored in the scene: it is one rule, and doing it in
## the inspector means twenty entries to keep in step by hand.
func _setup_blending() -> void:
	var clips: Array[StringName] = LOCOMOTION + ATTACKS
	for from in clips:
		for to in clips:
			if from == to:
				continue
			# Into a swing is snappy; everything else eases.
			anim.set_blend_time(from, to,
				attack_blend if to in ATTACKS else locomotion_blend)


## Picks the clip that matches how the player is actually moving. Called every
## frame; `play` on the clip already running is a no-op, so this costs nothing
## until the state genuinely changes.
func _update_locomotion() -> void:
	if _attacking or _slamming or _dead or _pose_time >= 0.0:
		return
	var want := &"idle"
	if not is_on_floor():
		want = &"jump"
	elif Vector2(velocity.x, velocity.z).length() > run_anim_speed:
		want = &"run"
	if anim.current_animation != want:
		anim.play(want)


func _on_animation_finished(anim_name: StringName) -> void:
	# The locomotion clips all loop, so this only fires for a swing. Guarded
	# anyway, since a clip losing its loop flag would otherwise drop the player
	# back to idle mid-run with no obvious cause.
	if anim_name in LOCOMOTION:
		return
	_attacking = false
	_hit_window_open = false
	_update_locomotion()


## For the HUD's attack icons (attack_icons.gd): the weapon in hand's attacks,
## heaviest first, as [kind, seconds before it can be used, of how long, key];
## -1 seconds = not usable at all just now. Empty with no weapon in hand. Read
## straight off the clocks the attacks keep (`_slam_ready_at`, the stroke in
## progress, the spear's own), none of which a change of weapon resets.
func attack_cooldowns() -> Array:
	var held := held_item()
	var now := _now()
	var recover := maxf(_slam_recover_until - now, 0.0)
	if held == &"sword":
		# A cut waits for the stroke in progress to stop biting (a spin blocks it
		# until its turn is done); a spin waits only for a spin still turning.
		var cut := 0.0
		if _attacking and _pose_time >= 0.0:
			cut = maxf(_bite_end() - _pose_time, 0.0)
		var spin := 0.0
		if _pose_kind == &"spin" and _pose_time >= 0.0 and not _spin_released():
			spin = SPIN_TURN - _pose_time
		return [
			[&"slam", maxf(_slam_ready_at - now, 0.0), slam_cooldown, "F"],
			[&"spin", maxf(spin, recover), SPIN_TURN, "Q"],
			[&"slash", maxf(cut, recover), SWING_HOLD, "LMB"],
		]
	if held == &"spear" and spear != null and spear.has_method("attack_cooldowns"):
		var list: Array = spear.call("attack_cooldowns")
		for entry: Array in list:
			if float(entry[1]) >= 0.0:
				entry[1] = maxf(float(entry[1]), recover)
		return list
	if held == &"axe" and axe != null:
		var list: Array = axe.call("attack_cooldowns")
		for entry: Array in list:
			if float(entry[1]) >= 0.0:
				entry[1] = maxf(float(entry[1]), recover)
		return list
	if held == &"robot_rat" and rats != null:
		return rats.call("attack_cooldowns")
	return []


## Drops out of the air, landing in a ring of damage. The descent is what sells
## it; the impact is where the damage happens.
## 0.0 just after slamming, 1.0 when it is available again -- for the HUD.
func slam_charge() -> float:
	if slam_cooldown <= 0.0:
		return 1.0
	var remaining := _slam_ready_at - _now()
	return clampf(1.0 - remaining / slam_cooldown, 0.0, 1.0)


func _start_slam() -> void:
	_slamming = true
	_ghosting = false
	_slam_started_at = _now()
	_slam_grounded = is_on_floor()
	# Decided on commitment so the landing knows which effect to play, and so a
	# long fall does not stretch the cooldown.
	_slam_armed = _now() >= _slam_ready_at
	if _slam_armed:
		_slam_ready_at = _now() + slam_cooldown
	# Paint what the blast will catch on the floor below, for the whole dive.
	_slam_marker_mat.set_shader_parameter("tint", slam_marker_color if _slam_armed else slam_dud_color)
	_slam_marker_mat.set_shader_parameter("strength", 1.0 if _slam_armed else 0.5)
	_slam_marker.scale = Vector3.ONE * (slam_radius if _slam_armed else slam_dud_radius)
	_place_slam_marker()
	# A new dive must not be hidden by the last one's fade finishing.
	if _slam_marker_tween != null and _slam_marker_tween.is_valid():
		_slam_marker_tween.kill()
	_slam_marker.visible = true
	# A swing in progress gives way to the dive; the clip takes the pivot back.
	_pose_time = -1.0
	_pose_kind = &""
	_trail_on = false
	_attacking = false
	_hit_window_open = false
	if _slam_grounded:
		# Up and over the head; `_land_slam` brings it down onto the floor.
		_begin_pose(&"raise")
		return
	# Its own clip now. `chop` used to be borrowed for this pose, but `chop` is a
	# horizontal sweep these days and reads as nothing like a dive.
	anim.play(&"dive")
	anim.seek(0.0, true)


func _land_slam() -> void:
	_slamming = false
	velocity = Vector3.ZERO
	# Down on the ground for a moment, getting up: no moving, view low and rising.
	_slam_recover_until = _now() + slam_recover_time
	_slam_crouch = 1.0
	_flash_slam_marker()

	if not _slam_armed:
		# Landed, but the blast is still charging: a puff of dust, no damage,
		# and only a jolt rather than the full shake.
		_shake = maxf(_shake, 0.35)
		_play_slam_ring(slam_dud_color, slam_dud_radius, 0.45)
		_begin_pose(&"slam")
		return
	_shake = 1.0
	_slam_impact_effects()

	var origin := global_position + Vector3(0, 0.6, 0)
	_slam_query.transform = Transform3D(Basis(), origin)

	for hit in get_world_3d().direct_space_state.intersect_shape(_slam_query, 32):
		var body := hit["collider"] as Node3D
		if body == null or body.has_method("swat"):
			continue
		var away := body.global_position - global_position
		away.y = 0.0
		var direction := away.normalized() if away.length_squared() > 0.0001 else -global_basis.z
		if body.has_method("take_damage"):
			body.take_damage(slam_damage * weapon_damage_scale(&"sword"), direction)
			hit_landed.emit(body)
		knock(body, direction * slam_push, slam_stun, slam_stagger_chance)

	_play_slam_ring(slam_ring_color, slam_radius, 0.85)
	# The blade comes down on the floor with the body, and is lifted back as
	# the player gets up.
	_begin_pose(&"slam")


func _play_slam_ring(colour: Color, radius: float, alpha: float) -> void:
	if _slam_material == null:
		return
	if _slam_tween != null and _slam_tween.is_valid():
		_slam_tween.kill()
	slam_ring.scale = Vector3.ONE * 0.25
	_slam_material.albedo_color = Color(colour.r, colour.g, colour.b, alpha)

	_slam_tween = create_tween().set_parallel(true)
	_slam_tween.tween_property(slam_ring, "scale", Vector3.ONE * radius, 0.3) \
		.set_ease(Tween.EASE_OUT)
	_slam_tween.tween_property(_slam_material, "albedo_color:a", 0.0, 0.3)


## The ring on the floor under a dive: a flat additive disc, bright at its rim,
## exactly the blast's radius. Its shader is compiled now, by drawing it once at
## zero strength, rather than stalling the first slam.
func _build_slam_marker() -> void:
	_slam_marker = MeshInstance3D.new()
	_slam_marker.name = "SlamMarker"
	_slam_marker.top_level = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	_slam_marker.mesh = plane
	_slam_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = SLAM_MARKER_SHADER
	_slam_marker_mat = ShaderMaterial.new()
	_slam_marker_mat.shader = shader
	_slam_marker_mat.set_shader_parameter("strength", 0.0)
	_slam_marker.material_override = _slam_marker_mat
	add_child(_slam_marker)
	_slam_marker.global_position = global_position + Vector3(0.0, 0.04, 0.0)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if not _slamming:
			_slam_marker.visible = false)


const SLAM_MARKER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform float strength = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float rim = smoothstep(0.84, 0.95, r) * (1.0 - smoothstep(0.97, 1.0, r));
	float fill = (1.0 - step(1.0, r)) * (0.05 + 0.07 * r * r);
	float pulse = 0.85 + 0.15 * sin(TIME * 18.0);
	ALBEDO = tint.rgb * 1.6;
	ALPHA = clamp((rim + fill) * strength * pulse, 0.0, 1.0);
}
"""


## On the floor straight below the player (floors are on the sight layer, 2).
func _place_slam_marker() -> void:
	var from := global_position + Vector3(0.0, 0.5, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -40.0, 0.0), 2)
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var floor_at: Vector3 = hit["position"] if not hit.is_empty() else global_position
	_slam_marker.global_position = floor_at + Vector3(0.0, 0.04, 0.0)


## The marker flares as the blast lands, then fades.
func _flash_slam_marker() -> void:
	var peak: float = 2.2 if _slam_armed else 0.8
	_slam_marker_mat.set_shader_parameter("strength", peak)
	_slam_marker_tween = create_tween()
	_slam_marker_tween.tween_method(func(v: float) -> void: _slam_marker_mat.set_shader_parameter("strength", v),
		peak, 0.0, 0.45).set_ease(Tween.EASE_IN)
	_slam_marker_tween.tween_callback(func() -> void: _slam_marker.visible = false)


## The blast going off: a ring of dust thrown out along the ground, and a flash
## of firelight on everything around (both only with `Graphics.effects` -- an
## extra light and a particle burst are the kind of thing that knob is for).
func _slam_impact_effects() -> void:
	if not Graphics.effects:
		return
	var at := global_position + Vector3(0.0, 0.2, 0.0)
	var parent := get_parent() as Node3D
	var debris := load("res://scripts/door_debris.gd")
	debris.dust(parent, at, Vector3.UP, 48, 1.7)
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.9, 0.94, 1.0)
	flash.light_energy = 7.0
	flash.omni_range = slam_radius * 1.6
	flash.shadow_enabled = false
	parent.add_child(flash)
	flash.global_position = global_position + Vector3(0.0, 0.8, 0.0)
	var t := flash.create_tween()
	t.tween_property(flash, "light_energy", 0.0, 0.3).set_ease(Tween.EASE_OUT)
	t.tween_callback(flash.queue_free)


func _hide_slam_ring() -> void:
	if _slam_material != null:
		_slam_material.albedo_color.a = 0.0
	slam_ring.scale = Vector3.ONE * 0.25


## While the cut is on, everything the BLADE passes through is hit, once a
## swing. Each physics tick the blade's sweep since the last one -- hilt and tip
## then, hilt and tip now -- is made into a thin convex slab and queried, so a
## fast stroke cannot step over something between frames, and nothing outside
## the blade's real path is touched.
func _resolve_hits() -> void:
	if sword_model == null or held_item() != &"sword" or hands_busy:
		_blade_prev.clear()
		return
	# The blade where the swing puts it. The sword passes freely through walls
	# (it is drawn in front of them); the line-of-sight test below is what stops
	# anything being cut THROUGH the stone.
	var xf := sword_pivot.global_transform * _sword_rest
	var now_pts := [xf * _blade_base, xf * _blade_tip]
	if _blade_prev.is_empty():
		_blade_prev = now_pts
		return
	var a0: Vector3 = _blade_prev[0]
	var a1: Vector3 = _blade_prev[1]
	var b0: Vector3 = now_pts[0]
	var b1: Vector3 = now_pts[1]
	_blade_prev = now_pts
	# The slash, the chop and the spin all sweep the blade sideways: the volume
	# is the slab between where it was last tick and where it is now.
	var pts := PackedVector3Array()
	var normal := (b1 - b0).cross(a1 - b1)
	if normal.length_squared() < 1e-6:
		normal = head.global_basis.z
	normal = normal.normalized() * blade_hit_thickness
	for p in [a0, a1, b0, b1]:
		pts.append(p + normal)
		pts.append(p - normal)
	var slab := ConvexPolygonShape3D.new()
	slab.points = pts
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = slab
	query.collision_mask = hitbox.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var eye := camera.global_position
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 24):
		var body := hit["collider"] as Node3D
		if body == null or body in _hit_this_swing:
			continue
		# Anything with swat() is passed over (nothing has one since the criers,
		# 2026-10-14: the bombers they replaced were struck with the haft).
		if body.has_method("swat"):
			continue
		if require_line_of_sight and _is_blocked(eye, body):
			continue
		_hit_this_swing.append(body)
		# A connecting swing punches the view harder than a miss. Capped rather
		# than accumulated, so cutting through a pack does not slam it per body.
		_swing_kick = minf(_swing_kick + attack_hit_kick, 1.5)
		var push_dir := body.global_position - global_position
		push_dir.y = 0.0
		push_dir = push_dir.normalized() if push_dir.length_squared() > 0.0001 else -global_basis.z
		hit_landed.emit(body)
		if body.has_method("strike"):
			# A weak point: worth many times a normal hit.
			body.strike(push_dir)
			continue
		if body.has_method("take_damage"):
			body.take_damage(_stroke_damage, push_dir)
		if _pose_kind == &"spin":
			knock(body, push_dir * spin_push, spin_stun, spin_stagger_chance)
		else:
			knock(body, push_dir * attack_push, attack_stun, slash_stagger_chance)

## Horizontal half-width of a body, from its collision shape.
func _body_radius_of(body: Node) -> float:
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
	return 0.0


## Level geometry sits on its own layer so this ray ignores other enemies --
## otherwise the first body in a crowd would shield everyone behind it.
func _is_blocked(origin: Vector3, body: Node3D) -> bool:
	var params := PhysicsRayQueryParameters3D.create(
		origin, body.global_position + Vector3(0, 0.9, 0)
	)
	params.collision_mask = geometry_mask
	params.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(params).is_empty()


## Ghost mode, held on "dodge" (Shift). On while the key is held and there is
## bar left; the bar drains over `ghost_duration` and refills over
## `ghost_refill` whenever it is off. Run dry, the key has to be let go before
## it will start again -- otherwise it would flicker on and off at the refill.
## While on, the dash's whole look is held: no colour, the view opened out,
## the edge streaks, a bank into sideways motion.
##
## A ghost only ever starts on a fresh press (note 113). A key that was already
## down when play resumed -- a menu closed (Shift-click in the inventory), a
## scene ended, the game unpaused, a respawn, the window back in focus -- or
## one pressed as part of a system chord (Win+Shift+S, Ctrl/Alt+Shift) locks
## it until it is let go, where before it set a ghost off by itself.
func _update_ghost(delta: float) -> void:
	var held := _dodge_held()
	if not held:
		_ghost_locked = false
	elif ui_open or _dead or _ghost_resumed or _system_chord():
		_ghost_locked = true
	var want := held and not _ghost_locked and not _slamming and _now() >= _slam_recover_until \
		and not is_drinking()
	var was := _ghosting
	if _ghosting and not want:
		_ghosting = false
	elif not _ghosting and want and _ghost_meter >= ghost_min_start:
		_ghosting = true
		# Going ghost costs a slice of the bar up front, so tapping it over and
		# over is not a way to move at ghost speed for free.
		_ghost_meter = maxf(_ghost_meter - ghost_entry_cost, 0.0)
		dodged.emit()
	if _ghosting:
		_ghost_meter = maxf(_ghost_meter - delta / maxf(ghost_duration, 0.01), 0.0)
		if _ghost_meter <= 0.0:
			_ghosting = false
			_ghost_locked = true
	else:
		_ghost_meter = minf(_ghost_meter + delta / maxf(ghost_refill, 0.01), 1.0)
	if _ghosting:
		_dash_view = 1.0
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		var lateral := 0.0
		if flat.length() > 0.5:
			lateral = clampf(flat.normalized().dot(head.global_basis.x), -1.0, 1.0)
		_dash_lateral = lerpf(_dash_lateral, lateral, 1.0 - exp(-6.0 * delta))
	if was and not _ghosting:
		# Solid again only once clear of whatever it was passing through.
		_phase_hold_until = _now() + dodge_phase_hold_max


## Whether the ghost key (Shift) is down RIGHT NOW.
func _dodge_held() -> bool:
	# Not while the view is a robot rat's: the body stays put.
	return not remote_view and _action_held(&"dodge")


func _notification(what: int) -> void:
	# The window lost focus (Alt+Tab, a snipping overlay): whatever is down now
	# was pressed for something else, so the ghost waits for a fresh press.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_ghost_locked = true


## Ctrl, Alt or the Windows key down with the keyboard player's Shift: a system
## shortcut (Win+Shift+S, the Copilot key, Ctrl+Shift+Esc), never a ghost. The
## game binds none of them.
func _system_chord() -> bool:
	if Coop.active and Coop.index_of(self) == 1:
		return false
	for k in [KEY_CTRL, KEY_ALT, KEY_META]:
		if Input.is_physical_key_pressed(k) or Input.is_key_pressed(k):
			return true
	return false


## Whether anything bound to `action` is down RIGHT NOW, asked of the keyboard
## and mouse themselves rather than of the action's stored state: that latched
## on (a release that never arrived, e.g. with the window losing focus
## mid-press) and the ghost carried on after its key was let go. Pad bindings
## are asked of the pads the same way (`_pad_held`): `is_action_pressed` there
## answered for the WHOLE action, keyboard state included, so the latched state
## came straight back for any action with a pad binding -- the ghost among them
## (note 113).
func _action_held(action: StringName) -> bool:
	# Co-op: player 2 holds it on their pad only (the split "p2_" action);
	# player 1 by keys and mouse alone, below, never the pad's binding.
	if Coop.active and Coop.index_of(self) == 1:
		return Coop.held(self, action)
	for e in InputMap.action_get_events(action):
		if Coop.active and (e is InputEventJoypadButton or e is InputEventJoypadMotion):
			continue
		var key := e as InputEventKey
		var button := e as InputEventMouseButton
		if key != null:
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			if Input.is_physical_key_pressed(code) or Input.is_key_pressed(code):
				return true
		elif button != null:
			if Input.is_mouse_button_pressed(button.button_index):
				return true
		elif _pad_held(e, InputMap.action_get_deadzone(action)):
			return true
	return false


## Whether a pad binding is down RIGHT NOW on the pad itself (every pad slot for
## a device -1 binding -- slots, not just connected pads, so a harness's made-up
## pad events count): a button pressed, or a stick / trigger past the action's
## deadzone on the binding's side.
func _pad_held(e: InputEvent, deadzone: float) -> bool:
	var pad_button := e as InputEventJoypadButton
	var motion := e as InputEventJoypadMotion
	if pad_button == null and motion == null:
		return false
	for device in PAD_SLOTS:
		if e.device >= 0 and device != e.device:
			continue
		if pad_button != null and Input.is_joy_button_pressed(device, pad_button.button_index):
			return true
		if motion != null:
			var value := Input.get_joy_axis(device, motion.axis)
			if signf(value) == signf(motion.axis_value) and absf(value) >= maxf(deadzone, 0.01):
				return true
	return false


## Vertical speed that holds a ghost `ghost_hover` above whatever floor is
## under it. Floors are on the sight layer (2); enemies are not, so floating
## over one does not lift you onto its head.
func _ghost_lift(delta: float) -> float:
	var from := global_position + Vector3(0.0, 0.5, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -3.0, 0.0), 2)
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return velocity.y + get_gravity().y * delta
	var target_y: float = (hit["position"] as Vector3).y + ghost_hover
	return (target_y - global_position.y) * ghost_hover_rate

## Lets the dash pass through anything alive without letting it pass through
## the level.
##
## Done with per-body collision exceptions rather than by changing the player's
## collision mask, because enemies share layer 1 with the floor and the walls --
## masking that layer out would drop the player through the ground. Exceptions
## name exactly the bodies to ignore and leave everything else alone.
##
## Re-run every frame of the dash rather than once at the start. Enemies move,
## and a pack closes: one that was out of range when the dash began can be in
## your way two frames later, and a body that was never granted an exception
## stops you dead. That is the difference between "usually works" and "works".
func _update_phasing() -> void:
	if not dodge_phases_through_enemies:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = dodge_phase_radius
	query.shape = shape
	query.collision_mask = hitbox.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.9, 0))

	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body := hit["collider"] as CollisionObject3D
		if body == null or body == self or body in _phased_through:
			continue
		# Never make a floor intangible. Dashing over a chest and then climbing
		# it would otherwise drop you straight through -- and the chest you are
		# most likely to climb is the mimic.
		if global_position.y > body.global_position.y + dodge_phase_step_height:
			continue
		# Both directions. An exception is one-way: it stops *this* body's
		# motion from colliding with that one, but the enemy is a moving body
		# too, and its own move_and_slide would still shove the player out.
		# One-sided, you sink in and get pushed straight back -- which is
		# exactly what "I still can't dash through them" looks like.
		add_collision_exception_with(body)
		body.add_collision_exception_with(self)
		_phased_through.append(body)


## Gives solidity back, but only once the player is genuinely clear of a body.
##
## This is the part that was really broken. A dash covers about 3.3 m and an
## enemy charging the other way closes most of that, so the dash routinely ends
## with the player still inside someone. Restoring collision at that moment
## hands a deep overlap to the solver, which shoves the pair apart -- and the
## player, being the lighter commitment, gets spat back the way they came. The
## phasing was working the whole time; the exit was throwing it away.
##
## `force` is for death and respawn, where the player is being moved anyway.
func _release_phasing(force := false) -> void:
	if _phased_through.is_empty():
		return
	var overdue := _now() >= _phase_hold_until
	var still: Array[Node] = []
	for body in _phased_through:
		if not is_instance_valid(body):
			continue
		if not (force or overdue) and _overlapping(body):
			still.append(body)
			continue
		remove_collision_exception_with(body)
		body.remove_collision_exception_with(self)
	_phased_through = still


## Intangible to enemies for exactly as long as ghost mode is on.
func _phase_window_open() -> bool:
	return _ghosting


## Are the two bodies still inside one another, horizontally?
func _overlapping(body: Node3D) -> bool:
	# Standing on top of something is not being stuck inside it -- it is using
	# it as a floor. A chest you can climb has to stay solid under your feet,
	# or the mimic pretending to be one is a hole in the ground.
	if global_position.y > body.global_position.y + dodge_phase_step_height:
		return false
	var gap := Vector2(
		global_position.x - body.global_position.x,
		global_position.z - body.global_position.z).length()
	return gap < _body_radius_of(self) + _body_radius_of(body) + dodge_phase_clearance


## Works out where a hit came from, in the frame of what you are looking at.
##
## Attackers pass the direction their blow travelled -- from them toward you --
## so the bearing back to the attacker is the opposite of it.
func _mark_damage(amount: float, blow: Vector3) -> void:
	_damage_severity = clampf(amount / maxf(damage_mark_reference, 0.001), 0.15, 1.0)
	_damage_mark = 1.0

	var source := -blow
	source.y = 0.0
	if source.length_squared() < 0.0001:
		# No direction given: mark the whole rim rather than guess a side.
		_damage_bearing = 0.0
		_damage_severity = 1.0
		return
	source = source.normalized()
	# Against the head, not the body: the marker has to agree with the view.
	var forward := -head.global_basis.z
	forward.y = 0.0
	var right := head.global_basis.x
	right.y = 0.0
	_damage_bearing = atan2(source.dot(right.normalized()),
		source.dot(forward.normalized()))


## 1.0 at the moment of a hit, falling to 0. Drives the HUD's marker.
func damage_mark() -> float:
	return _damage_mark


## Bearing to whatever hit you, relative to where you are looking: 0 is dead
## ahead, positive is to your right.
func damage_bearing() -> float:
	return _damage_bearing


## 0..1 by how hard the hit was, which sets the marker's size and brightness.
func damage_severity() -> float:
	return _damage_severity


## 1.0 at the instant of a dash, falling to 0 as it settles. The HUD reads this
## rather than timing its own copy, so the streaks and the view stay in step.
func dash_intensity() -> float:
	return _dash_view


## How sideways the current dash was: -1 left, +1 right, 0 straight ahead.
func dash_lateral() -> float:
	return _dash_lateral


## True while a dash cannot hurt you. Distinct from being merely on cooldown.
func is_invulnerable() -> bool:
	return _now() < _invulnerable_until


## True when a ghost can be started.
func dodge_ready() -> bool:
	return _ghost_meter >= ghost_min_start and not _ghost_locked


## True while ghost mode is on. Named for the dash it replaced: the HUD, the
## colour drain and anything else asking "is the player dodging" still ask this.
func is_dodging() -> bool:
	return _ghosting


## The ghost bar, 0 empty to 1 full -- for the HUD readout.
func dodge_charge() -> float:
	return _ghost_meter

## `attacker`, when given, is whoever struck the blow: a parry throws it back.
## --- Upgrades (the crystal mine's workbench, workbench.gd, 2026-10-11) -----------
##
## Gold crystals buy levels. A weapon's level scales everything it deals by
## `UPGRADE_DAMAGE` a level (sword: cut, spin, slam; spear: stab, dash, blast; axe: slash, throw);
## armor takes `ARMOR_STEP` a level off every hit and beam (`damage_negation`).
## Small steps on purpose. Levels start at 1 and are saved with the game.

const UPGRADE_DAMAGE := 0.08
const ARMOR_STEP := 0.04
const UPGRADE_MAX := 10
## The weapons the workbench can work on.
const UPGRADABLE: Array[StringName] = [&"sword", &"spear", &"axe"]

var weapon_levels := {}
var armor_level := 1


func weapon_level(id: StringName) -> int:
	return int(weapon_levels.get(id, 1))


func weapon_damage_scale(id: StringName) -> float:
	return 1.0 + UPGRADE_DAMAGE * float(weapon_level(id) - 1)


## The share of every hit the armor takes off (0 at level 1).
func damage_negation() -> float:
	return ARMOR_STEP * float(armor_level - 1)


## Gold crystals to go from `level` to the next: 3, 5, 7, 10, 15, 23, 34...
static func upgrade_cost(level: int) -> int:
	return int(round(3.0 * pow(1.5, float(level - 1))))


## Pays for and takes one level of `what` (a weapon id, or &"armor"). False if
## it is at the top or there are not enough crystals.
func upgrade(what: StringName) -> bool:
	var level := armor_level if what == &"armor" else weapon_level(what)
	if level >= UPGRADE_MAX:
		return false
	var cost := upgrade_cost(level)
	if inventory.count(&"gold_crystal") < cost:
		return false
	inventory.remove(&"gold_crystal", cost)
	if what == &"armor":
		armor_level += 1
	else:
		weapon_levels[what] = level + 1
	inventory_changed.emit()
	return true


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO,
		attacker: Node3D = null) -> void:
	if _dead or (in_cutscene and not _cutscene_hurts) or is_hidden():
		return
	var now := _now()
	if now < _invulnerable_until:
		return
	# The sword up in front takes the blow -- 90% of it blocked, all of it
	# parried (and half of it turned back on the attacker). Some blows (the
	# Remnant's) go through any guard.
	var guard := _guard(_from_direction, attacker)
	if attacker != null and is_instance_valid(attacker) and attacker.get("unblockable") == true:
		guard = 0
	match guard:
		2:
			_on_guarded(true, _from_direction, attacker, amount)
			amount *= parry_damage_taken
		1:
			# Some attackers set how much of their blow a block lets through
			# (a crier's blast: 25%).
			var share = attacker.get("block_damage_share") if attacker != null and is_instance_valid(attacker) else null
			amount *= float(share) if share != null else block_damage_taken
			_on_guarded(false, _from_direction, attacker)
	_invulnerable_until = now + (guarded_invulnerable_time if guard > 0 else invulnerable_time)
	# A ghost is mostly not there: it takes only ghost_damage_taken of a hit.
	if _ghosting:
		amount *= ghost_damage_taken
	# The armor (workbench upgrades).
	amount *= 1.0 - damage_negation()
	# Sandbox: nothing hurts (the guard above still registered, for the enemy).
	if Sandbox.player_god:
		amount = 0.0
	if amount <= 0.0:
		return
	_mark_damage(amount, _from_direction)
	# A hit that hurts spills the drink.
	_interrupt_drink()

	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()


## A slow drain rather than a hit (the cage skulls' stare): no invulnerability
## window, no knockback, no damage marker, and it never takes the player below
## `floor_health`. Returns what was taken.
func drain_health(amount: float, floor_health := 0.0) -> float:
	if _dead or in_cutscene or amount <= 0.0 or is_hidden() or Sandbox.player_god:
		return 0.0
	var taken := minf(amount, health - floor_health)
	if taken <= 0.0:
		return 0.0
	health -= taken
	health_changed.emit(health, max_health)
	return taken


## --- An enforcer's beam (enforcer.gd; the warden bot's, 2026-10-09) ------------------------------------
##
## Not a blow: it is held on the player, so it is paid by the frame. `dps` health a
## second and slowed to `beam_slow` (lingering `BEAM_LINGER` after it moves off),
## with no invulnerability window and no knockback. A guard raised toward it
## takes `block_damage_taken` of it and half the slow; a ghost takes
## `ghost_damage_taken`. A beam that hurts spills a drink, as a hit does. The
## damage marker is raised for what has built up, every `BEAM_MARK_EVERY` s.

## Of walking pace (and ghosting) while a beam is on the player.
@export_range(0.05, 1.0) var beam_slow := 0.45
const BEAM_LINGER := 0.35
const BEAM_MARK_EVERY := 0.5
var _beam_until := 0.0
var _beam_guarded := false
var _beam_owed := 0.0
var _beam_marked_at := 0.0


func beam_hit(dps: float, delta: float, blow: Vector3) -> void:
	if _dead or (in_cutscene and not _cutscene_hurts) or is_hidden():
		return
	var now := _now()
	var guarded := _guard(blow) != 0
	_beam_until = now + BEAM_LINGER
	_beam_guarded = guarded
	var amount := dps * delta * (1.0 - damage_negation())
	if Sandbox.player_god:
		amount = 0.0
	if guarded:
		amount *= block_damage_taken
	if _ghosting:
		amount *= ghost_damage_taken
	if amount <= 0.0:
		return
	_beam_owed += amount
	if now - _beam_marked_at >= BEAM_MARK_EVERY:
		_beam_marked_at = now
		_mark_damage(maxf(_beam_owed, 1.0), blow)
		_beam_owed = 0.0
	_interrupt_drink()
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()


## 0..1, how hard a beam is on the player right now (the HUD's glow reads it).
func beam_amount() -> float:
	var left := _beam_until - _now()
	return clampf(left / BEAM_LINGER, 0.0, 1.0)


## The slow on movement: 1 with no beam on the player.
func _beam_speed_scale() -> float:
	if _now() >= _beam_until:
		return 1.0
	return lerpf(beam_slow, 1.0, 0.5) if _beam_guarded else beam_slow


## Movement keys, or nothing while the inventory screen is open.
func _move_input() -> Vector2:
	if ui_open or remote_view:
		return Vector2.ZERO
	return Coop.vector(self, &"move_left", &"move_right", &"move_forward", &"move_back")


## Starts drinking one of whatever consumable is in inventory slot `slot`
## (the quick-item wheel is 4-7). A drink takes `drink_time`: the flask is used
## up as it starts and the healing flows in EVENLY over the drink
## (`_update_drink`). Meanwhile the player walks at `drink_move_scale`, cannot
## block or go ghost, and the HUD counts it down. Attacking (any weapon key) or
## taking a hit cuts it short (`_interrupt_drink`): what has flowed in so far
## is all it gives, and the flask is gone. Returns false and keeps it if the
## slot holds no consumable, the player is at full health, or busy.
func use_consumable(slot: int) -> bool:
	if _dead or is_drinking() or _slamming or _pose_kind in [&"haft", &"stab"]:
		return false
	if _attacking and _pose_time < _bite_end():
		return false
	# A live rat (a utility quick item) is taken in hand by the tail, not drunk
	# (rat_control.gd `take_rat`; LMB then throws it).
	if inventory.id_at(slot) == &"live_rat":
		return rats.take_rat(slot)
	var type := _consumable_for(inventory.id_at(slot))
	if type == null or health >= max_health:
		return false
	_end_block()
	_drink_type = type
	_drink_left = drink_time
	_drink_healed = 0.0
	if _held_potion != null:
		_held_potion.drink(drink_time)
	inventory.take(slot, 1)
	return true


func is_drinking() -> bool:
	return _drink_type != null


## 1 as a drink starts, falling to 0 as it is finished; -1 when not drinking.
## The HUD's countdown bar.
func drink_remaining() -> float:
	if _drink_type == null:
		return -1.0
	return clampf(_drink_left / maxf(drink_time, 0.01), 0.0, 1.0)


## What the drink in progress has restored so far (health it could give; at
## full health the rest is simply not needed).
var _drink_healed := 0.0


## The healing flows in at an even rate, `heal_amount` over `drink_time`, and
## is applied straight to health -- the HUD's "Used ..." line is raised once,
## for the total, when the drink ends (`_finish_drink`), not every frame.
func _update_drink(delta: float) -> void:
	if _drink_type == null or _dead:
		return
	var step := minf(delta, _drink_left)
	_drink_left -= step
	var dose := _drink_type.heal_amount * step / maxf(drink_time, 0.01)
	var before := health
	health = minf(health + dose, max_health)
	if health > before:
		_drink_healed += health - before
		health_changed.emit(health, max_health)
	if _drink_left <= 0.0:
		_finish_drink(false)


## Ends a drink, complete or cut short, and reports what it actually gave.
func _finish_drink(interrupted: bool) -> void:
	if _drink_type == null:
		return
	var type := _drink_type
	_drink_type = null
	_drink_left = 0.0
	if interrupted and _held_potion != null:
		_held_potion.stop()
	if interrupted:
		drink_interrupted.emit(_drink_healed)
	elif _drink_healed > 0.0:
		healed.emit(_drink_healed, type.item_name)


## An attack key with a weapon in hand, mid-drink: the drink stops and the
## attack goes ahead. (Left click with the potion in hand is the drink itself,
## not an attack.)
func _attack_key_spills_drink() -> void:
	if is_drinking() and Coop.aim_ready(self) \
			and Inventory.is_weapon(held_item()) and not in_cutscene and not ui_open:
		_interrupt_drink()


## An attack or a hit lands mid-drink: it stops here, with whatever has flowed
## in so far, and the flask -- used up as the drink began -- is gone.
func _interrupt_drink() -> void:
	_finish_drink(true)


## Death: no report, nothing more.
func _cancel_drink() -> void:
	if _drink_type != null and _held_potion != null:
		_held_potion.stop()
	_drink_type = null
	_drink_left = 0.0


## The inventory id a consumable is carried under.
static func _item_id(type: ConsumableType) -> StringName:
	return StringName(type.item_name.to_snake_case())


## The consumable type carried under `id`, or null if it is not one.
func _consumable_for(id: StringName) -> ConsumableType:
	if id == &"":
		return null
	for type in consumables:
		if type != null and _item_id(type) == id:
			return type
	return null


## Returns how many were actually added, which is less than `amount` when the
## stack is already full.
## `notify` raises the small pickup line at the bottom of the screen. Anything
## that announces itself more loudly -- a chest, a mimic -- passes false, so the
## player is not told the same thing twice in two different places.
func add_currency(amount: int) -> void:
	if amount <= 0:
		return
	var added := inventory.add(&"coins", amount)
	if added > 0:
		currency_changed.emit(currency, added)


## Matched by name, so a duplicated resource still stacks with the original.
func add_consumable(type: ConsumableType, amount := 1, notify := true) -> int:
	if type == null:
		return 0
	var added := inventory.add(_item_id(type), amount)
	if added > 0 and notify:
		consumable_gained.emit(type, added)
	return added


## Anything picked up off the floor (item_drop.gd). Consumables and coins go
## through their own paths, so their signals fire as they always have; anything
## else is announced with `item_gained`. Returns how many fitted.
func add_item(id: StringName, amount := 1) -> int:
	var type := _consumable_for(id)
	if type != null:
		return add_consumable(type, amount)
	if id == &"coins":
		var before := currency
		add_currency(amount)
		return currency - before
	var added := inventory.add(id, amount)
	if added > 0:
		item_gained.emit(id, added)
	return added


## Returns how much was actually restored, so a consumable is not wasted when
## the player is already at full health.
func heal(amount: float, source_name := "") -> float:
	if _dead:
		return 0.0
	var before := health
	health = minf(health + amount, max_health)
	var restored := health - before
	if restored > 0.0:
		health_changed.emit(health, max_health)
		healed.emit(restored, source_name)
	return restored


func _die() -> void:
	_dead = true
	unlatch()
	# Whatever held them lets go of a corpse (note 96).
	restrained_by = null
	restrain_view = Vector3.ZERO
	# Autosaved on death (2026-10-10): written once it is safe again -- after the
	# respawn and the getting-up (save_system.gd `_safe`), so the slot holds the
	# world as the death left it (the map back at its checkpoint).
	Saves.request("death")
	_cancel_drink()
	if _blocking:
		_blocking = false
		guard_changed.emit(false)
	if _scene_walk_target != null:
		_scene_walk_target = null
		scene_walk_finished.emit()
	died.emit()
	# The world goes out over most of the wait; the respawn fades back in from
	# black (`_begin_wake`). A scene that has already cut to black keeps it.
	var hud := Coop.hud(self)
	if hud != null and hud.has_method("fade_black") and hud.black_amount() < 0.99:
		hud.fade_black(1.0, respawn_delay * 0.75)
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


## A scene kills the player outright (the Remnant in the morgue): no guard, no
## invulnerability, no damage marker.
func kill_in_scene() -> void:
	if _dead or Sandbox.player_god:
		return
	health = 0.0
	health_changed.emit(health, max_health)
	_die()


## --- Getting up after a death ------------------------------------------------------
##
## Every respawn: the view comes up out of black (`hud.fade_black`) in black and
## white, colour seeping back over `WAKE_COLOUR` seconds, while the camera rises
## off the floor -- lying on its side, pushing up onto a knee, standing with a
## stagger (`_wake_view`). No control until `WAKE_CONTROL`.

const WAKE_FADE := 1.3
const WAKE_COLOUR := 2.8
const WAKE_CONTROL := 1.9
const WAKE_END := 2.4

var _wake_t := -1.0
## A scene's crush: 0..1, the view driven into the floor (`scene_crush`).
var _scene_crush := 0.0


## The start of a new game: lying on the floor, getting up (the respawn's wake).
## Held in the black until the game is running smoothly: the level's first
## frames are long stalls (shaders compiling), and one of them swallowed the
## whole fade -- black to clear in a single frame, a cut instead of a fade.
func wake_up() -> void:
	_begin_wake(true)


## Frames in a row that must come in under WAKE_STEADY_DELTA before a held
## wake starts, and the longest it waits for them.
const WAKE_STEADY_FRAMES := 3
const WAKE_STEADY_DELTA := 0.1
const WAKE_HOLD_MAX := 3.0
var _wake_steady := 0
var _wake_held := -1.0


func _begin_wake(hold := false) -> void:
	_wake_t = 0.0
	in_cutscene = true
	_cutscene_hurts = false
	# Weapons away while getting up: the sword is drawn over everything and
	# would hang in the air in front of a face lying on the floor.
	hands_busy = true
	# Black and white from the first frame: `_update_colour` eases toward its
	# target, and left to it the view came up in full colour.
	if _environment != null:
		_environment.adjustment_saturation = 0.0
	var hud := Coop.hud(self)
	if hud != null and hud.has_method("fade_black"):
		hud.fade_black(1.0, 0.0)
	_wake_steady = 0
	_wake_held = 0.0 if hold else -1.0
	if not hold:
		_wake_fade_in()


func _wake_fade_in() -> void:
	var hud := Coop.hud(self)
	if hud != null and hud.has_method("fade_black"):
		hud.fade_black(0.0, WAKE_FADE)


func _update_wake(delta: float) -> void:
	if _wake_t < 0.0:
		return
	if _wake_held >= 0.0:
		# Lying in the black, waiting for the frames to settle.
		_wake_held += delta
		_wake_steady = _wake_steady + 1 if delta < WAKE_STEADY_DELTA else 0
		if _wake_steady >= WAKE_STEADY_FRAMES or _wake_held >= WAKE_HOLD_MAX:
			_wake_held = -1.0
			_wake_fade_in()
		return
	var before := _wake_t
	# A stall mid-wake does not skip the getting up.
	_wake_t += minf(delta, 0.05)
	if before < WAKE_CONTROL and _wake_t >= WAKE_CONTROL and not _dead:
		in_cutscene = false
	if before < 1.3 and _wake_t >= 1.3:
		# The sword back in hand as the player gets a knee under them.
		hands_busy = false
	if _wake_t >= WAKE_END:
		_wake_t = -1.0


func is_waking() -> bool:
	return _wake_t >= 0.0


## The colour coming back: 0 black and white -> 1 full.
func _wake_colour() -> float:
	if _wake_t < 0.0:
		return 1.0
	var k := clampf((_wake_t - 0.2) / (WAKE_COLOUR - 0.2), 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## The view getting up: (drop m, pitch deg, roll deg). Lying on one side with
## the eye near the floor, then onto a knee looking down, then standing with a
## sway that settles.
func _wake_view() -> Vector3:
	if _wake_t < 0.0:
		return Vector3.ZERO
	var t := _wake_t
	var lying := Vector3(1.32, 8.0, 72.0)
	var kneel := Vector3(0.62, -16.0, 9.0)
	var view := lying
	if t > 0.45:
		var k := smoothstep(0.45, 1.25, t)
		view = lying.lerp(kneel, k)
	if t > 1.25:
		var k := smoothstep(1.25, 2.1, t)
		view = kneel.lerp(Vector3.ZERO, k)
		# A stagger: the body finding its balance as it stands.
		var sway := sin((t - 1.25) * 9.0) * (1.0 - smoothstep(1.4, WAKE_END, t))
		view += Vector3(0.0, 0.0, sway * 3.5)
	# Breathing hard while down.
	view.x += sin(t * 5.2) * 0.012 * (1.0 - smoothstep(1.0, 2.0, t))
	return view


## Drives the view into the floor: 0 none -> 1 crushed flat. For the morgue's
## death: eased by the scene.
func scene_crush(amount: float) -> void:
	_scene_crush = clampf(amount, 0.0, 1.0)


func _respawn() -> void:
	# Forced: the body is being teleported anyway, so there is no overlap left
	# to walk out of and nothing to be shoved by.
	_release_phasing(true)
	global_position = _spawn_point
	velocity = Vector3.ZERO
	health = max_health
	_dead = false
	_invulnerable_until = _now() + invulnerable_time
	_ghosting = false
	_ghost_meter = 1.0
	# Up again with the key still down: no ghost until it is pressed afresh.
	_ghost_locked = true
	_slam_recover_until = 0.0
	_knock_at = -1.0
	_slam_crouch = 0.0
	_shake = 0.0
	_slamming = false
	_slam_ready_at = 0.0
	_beam_until = 0.0
	_beam_owed = 0.0
	if _blocking:
		_blocking = false
		guard_changed.emit(false)
	_guard_level = 0.0
	_guard_kick = 0.0
	_cancel_drink()
	in_cutscene = false
	_cutscene_hurts = false
	_scene_walk_target = null
	_scene_look = null
	scene_frame(0.0, 0.0, 30.0)
	_lunge_age = -1.0
	_spear_dash_until = 0.0
	if spear != null:
		spear.reset()
	if axe != null:
		axe.reset()
	if rats != null:
		rats.call("reset")
	if _hidden_in != null:
		_hidden_in = null
		hands_busy = false
		_set_body_solid(true)
		hidden_changed.emit(false)
	if climbing:
		climbing = false
		_set_body_solid(true)
	_end_slowmo()
	# The teleport is not a fall -- without this the next frame's is_on_floor()
	# transition would read as a landing and fire the bob for a hit that never
	# happened.
	_was_grounded = true
	_land_kick = 0.0
	_scene_crush = 0.0
	_scene_lean = Vector3.ZERO
	_scene_lean_goal = Vector3.ZERO
	hands_busy = false
	# The inventory is exactly as it was at death (2026-10-11): no topping the
	# potions back up. `_reset_inventory` only runs for a new game now.
	inventory_changed.emit()
	health_changed.emit(health, max_health)
	respawned.emit()
	# Held in the black until the frames settle, like a new game's: the world
	# reset that `respawned` triggers respawns every enemy in this same frame
	# (~0.5 s on the big maze), and that one long frame jumped the fade.
	_begin_wake(true)


## A new game: the sword (weapon wheel, up), the starting consumables (quick
## wheel, up), the spear (weapon wheel, right), the axe (weapon wheel, down). Not run on respawn any more --
## the player rises with what they died with (2026-10-11).
func _reset_inventory(first_time := false) -> void:
	if first_time:
		inventory.clear()
		inventory.add(&"sword", 1)
	for i in consumables.size():
		var type := consumables[i]
		if type == null:
			continue
		var id := _item_id(type)
		var want: int = starting_counts[i] if i < starting_counts.size() else 0
		var home := inventory.find(id)
		inventory.remove(id, inventory.count(id))
		if want <= 0:
			continue
		if home >= 0 and inventory.is_empty(home):
			inventory.slots[home] = {"id": id, "count": 0}
		inventory.add(id, want)
	if inventory.find(&"sword") < 0:
		inventory.add(&"sword", 1)
	# The spear: the weapon wheel's second slot (right); the axe the third (down).
	if first_time:
		inventory.add(&"spear", 1)
		inventory.add(&"axe", 1)
	inventory_changed.emit()


## --- Knocked down (an enforcer's shield swipe, 2026-10-15) --------------------------
##
## Thrown back along `dir` and off their feet: the view falls to the floor
## (flat on the back, looking up, rolled a little) over KNOCK_FALL while the
## body slides back, then gets up over KNOCK_UP (0.5 s at first; 0.8 since the
## user asked for "a bit longer", 2026-10-15). No control meanwhile: the slam
## recovery's lock (`_slam_recover_until`) holds moving, jumping, swinging,
## blocking and ghost,
## and the slide bleeds off at KNOCK_FRICTION rather than the recovery's stop.
## Still hurtable on the floor. Not in a scene, not hidden, not dead.
@export var knockdown_lift := 2.6
const KNOCK_FALL := 0.32
const KNOCK_UP := 0.8
const KNOCK_FRICTION := 9.0
var _knock_at := -1.0
var _knock_side := 1.0


func knock_down(dir: Vector3, push := 7.5) -> void:
	if _dead or in_cutscene or is_hidden():
		return
	unlatch()
	var away := Vector3(dir.x, 0.0, dir.z)
	if away.length_squared() < 0.0001:
		away = global_basis.z
	away = away.normalized()
	_knock_at = _now()
	_knock_side = -1.0 if randf() < 0.5 else 1.0
	_slamming = false
	if _blocking:
		_end_block()
	velocity = away * push + Vector3(0.0, knockdown_lift, 0.0)
	_slam_recover_until = maxf(_slam_recover_until, _knock_at + KNOCK_FALL + KNOCK_UP)
	_shake = maxf(_shake, 0.5)


func is_knocked_down() -> bool:
	return _knock_at >= 0.0 and _now() - _knock_at < KNOCK_FALL + KNOCK_UP


## The view while knocked down: (drop m, pitch deg, roll deg), as `_wake_view`.
func _knock_view() -> Vector3:
	if _knock_at < 0.0:
		return Vector3.ZERO
	var t := _now() - _knock_at
	if t >= KNOCK_FALL + KNOCK_UP:
		_knock_at = -1.0
		return Vector3.ZERO
	# On the back, eye a foot off the floor, looking up past whatever hit them.
	var floored := Vector3(1.28, 34.0, 16.0 * _knock_side)
	if t < KNOCK_FALL:
		var k := t / KNOCK_FALL
		return floored * (k * k)
	var k := smoothstep(0.0, 1.0, (t - KNOCK_FALL) / KNOCK_UP)
	return floored * (1.0 - k)


## Shoved by something in the world. Applied straight to velocity so the hit
## carries you, rather than being smoothed away by the movement code.
func apply_knockback(impulse: Vector3, _stun_time := 0.0) -> void:
	if _dead or in_cutscene:
		return
	_slamming = false
	velocity += impulse


## Used by the level builder, which decides where the start actually is.
func set_spawn_point(point: Vector3) -> void:
	_spawn_point = point


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
