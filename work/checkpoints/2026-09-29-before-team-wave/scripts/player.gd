extends CharacterBody3D

## First-person character: WASD moves relative to where you are facing, Space
## jumps, the mouse looks around, left click swings the sword, Escape releases
## the mouse.

@export var move_speed := 5.0
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
@export var attack_damage := 32.0
## The swing sweeps an arc in front of the camera rather than tracing the thin
## blade volume, so anything you can see within reach is cut.
@export var attack_reach := 3.4
## When true the sweep spans the camera's actual horizontal field of view, so
## anything you can see within reach is cut. Widescreen displays therefore get a
## wider swing, matching what is on screen.
@export var sweep_matches_fov := true
## Used only when sweep_matches_fov is off.
@export var attack_arc_degrees := 130.0
## A shove on every sword hit, so a connecting swing visibly moves what it hits.
@export var attack_push := 5.5
@export var attack_stun := 0.15
## Playback rate for the swing clips. The clips are untouched, so the method
## track that opens the hit window scales with them automatically.
@export var attack_speed := 1.7
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

@export_group("Sweep trail")
## Draws the arc the swing actually tests against -- same origin, same reach,
## same half-angle as the hit query -- so the trail cannot lie about what the
## sword reaches. Turn it off and the sword still hits exactly the same things.
@export var sweep_trail_enabled := true
## Seconds the arc takes to travel from one edge of the swing to the other.
@export var sweep_trail_span := 0.13
## Seconds it takes to fade once the hit window closes.
@export var sweep_trail_fade := 0.16
## Where the band starts, as a fraction of reach. The near half is where you are
## standing, so drawing it costs fill and shows nothing.
@export var sweep_trail_inner := 0.34
@export var sweep_trail_alpha := 0.5
@export var sweep_trail_segments := 14
@export var sweep_trail_color := Color(1.0, 0.78, 0.42)

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
@export var respawn_delay := 1.5

@export_group("Rally")
## Bloodborne-style regain: damage taken is banked instead of lost outright,
## and hitting something back claws it out of the bank. The banked amount shows
## as the yellow stretch on the health bar.
@export_range(0.0, 1.0) var rally_fraction := 1.0
## How long the bank sits at full before it starts draining away.
@export var rally_hold := 0.7
## How long it then takes to drain to nothing.
@export var rally_drain := 2.3
## Health regained per point of damage dealt, while the bank has anything in
## it. Was 0.5 -- rallying covered so much of a fight's damage back that
## missing was barely a cost. Cut to roughly a third of that.
@export var rally_recovery_ratio := 0.17

@export_group("Dodge")
@export var dodge_speed := 15.0
@export var dodge_duration := 0.22
## Time for the whole bar to refill from empty. With two charges that means one
## charge back every half of it.
@export var dodge_cooldown := 5.0
## Dashes held at once. The bar shows the pool, so each dash takes 1/charges
## of it -- two charges, half a bar each.
@export var dodge_charges := 2
## The dash goes straight through anything alive. Walls and floors still stop
## it, which is what keeps it a dodge rather than a teleport.
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
## Longest the dash will keep something intangible after it ends. A backstop
## only: normally solidity returns the moment you step clear.
@export var dodge_phase_hold_max := 4.0
## Most a dash may be stretched beyond its normal length to finish passing
## through something. A dash that hits nothing never uses any of this.
@export var dodge_max_extension := 0.45
## Invulnerable for the whole dodge. This is what makes the dodge an answer to
## enemies that are faster than you are -- you cannot outrun them, so you go
## through them instead.
@export var dodge_invulnerable := true
## The dash shoulder-checks anything it passes through.
@export var dodge_damage := 8.0
@export var dodge_push := 10.0
@export var dodge_stun := 0.2
@export var dodge_hit_radius := 1.1

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
## How strongly airborne input can change speed, as a fraction of the ground
## acceleration. The heading is locked mid-air; this is only how quickly the
## player may speed up or slow down along it.
@export_range(0.0, 1.0, 0.05) var air_damp_scale := 0.45
@export var landing_bob_height := 0.05
## Degrees the view pitches down on a hard landing.
@export var landing_view_kick := 1.8
## How long the landing dip takes to fall away.
@export var landing_kick_time := 0.22
## Downward speed, in m/s, at which a landing counts as a full-strength
## impact -- a long fall hits with everything below; a small hop barely
## registers. This is what impact speed is scaled against.
@export var landing_speed_reference := 14.0
## Downward speed below which a landing produces no bob at all -- an ordinary
## footfall off a low step or a short hop, not worth a camera reaction.
@export var landing_speed_min := 2.0

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
## Attacking in mid-air drives you straight down instead of swinging; the
## landing detonates in a ring around you.
@export var slam_damage := 150.0
## Gates the blast only. The dive to the ground is always available, so the slam
## doubles as a way to get down fast.
@export var slam_cooldown := 20.0
@export var slam_radius := 4.5
## Colour and size of the shockwave ring when the blast actually lands...
@export var slam_ring_color := Color(1.0, 0.529412, 0.223529)
## ...and when it is still on cooldown: a small pale puff of dust instead.
@export var slam_dud_color := Color(0.678431, 0.717647, 0.768627)
@export var slam_dud_radius := 1.8
@export var slam_descent_speed := 30.0
@export var slam_push := 9.0
@export var slam_stun := 0.35
## Safety net in case a slam never finds ground.
@export var slam_timeout := 3.0

@export_group("Shockwave")
## Purely a crowd-control tool -- it deals no damage, it only clears space.
@export var shockwave_radius := 6.0
## Enemies are flung radially outward at this speed.
@export var shockwave_push := 18.0
@export var shockwave_stun := 0.45
@export var shockwave_cooldown := 2.5

@export_group("Inventory")
## Carried consumables, in hotkey order -- slot 1 is the "1" key. Add a type
## here and it gets a slot and a hotkey automatically.
@export var consumables: Array[ConsumableType] = [
	preload("res://resources/health_potion.tres"),
]
## What the player starts carrying, matched to `consumables` by position.
@export var starting_counts: Array[int] = [3]
@export var max_stack := 20

signal health_changed(current: float, maximum: float)
signal healed(amount: float, source_name: String)
signal died
signal inventory_changed
signal consumable_gained(type: ConsumableType, amount: int)
signal dodged
signal shockwave_cast
## Emitted after death has returned the player to the start. The level builder
## uses this to restore the world.
signal respawned

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
## Pre-authored in the scene so its transparent material's shader is compiled at
## load. Building the material at runtime would stall the first cast.
@onready var shockwave_ring: MeshInstance3D = $Shockwave
## Same pre-authored trick as the shockwave ring: built in the scene so its
## transparent shader is compiled at load rather than stalling the first slam.
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
var _query := PhysicsShapeQueryParameters3D.new()

var health := 0.0
## Health that is still recoverable by fighting back. Drawn in yellow.
var rally_health := 0.0
var _rally_hold_until := 0.0
var _invulnerable_until := 0.0
var _spawn_point := Vector3.ZERO
var _dead := false

## How many of each entry in `consumables` is carried, same order.
var counts: Array[int] = []

## Latest moment a jump will still be honoured after leaving the ground.
var _coyote_until := 0.0
var _dodge_until := 0.0
## Charges in hand, fractional while refilling.
var _dodge_meter := 0.0
var _dodge_ready_at := 0.0
var _dodge_direction := Vector3.ZERO
## 1.0 the instant a dash starts, decaying to 0. One clock drives the field of
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
## Grounded state as of the end of the previous physics frame. A landing is
## the transition from false to true here, not merely "on the floor now" --
## walking down a corridor is on the floor every single frame.
var _was_grounded := true
## The horizontal line the player committed to when they last left the ground.
## Only used as a fallback for a standing-start jump, where there is no velocity
## to read a heading from yet.
var _air_heading := Vector3.ZERO
## The swing's arc, in radians either side of where the camera is facing.
var _sweep_from := 0.0
var _sweep_to := 0.0
## How far the drawn arc has travelled, 0..1, and how bright it still is.
var _sweep_progress := 0.0
var _sweep_fade := 0.0
var _sweep_mesh: ImmediateMesh

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
## Ceiling on stretching a dash to get clear of what it ran into.
var _dodge_extend_limit := 0.0

## The marker showing where the last hit came from. 1 at the moment of impact,
## decaying to 0; bearing is relative to where you are looking, and severity
## scales with how hard the hit was.
var _damage_mark := 0.0
var _damage_bearing := 0.0
var _damage_severity := 0.0
## Cleared at the start of each dash, so one dash hits each enemy once.
var _hit_this_dash: Array[Node3D] = []
var _dash_query := PhysicsShapeQueryParameters3D.new()

var _slamming := false
## Whether the dive currently in progress will detonate on landing.
var _slam_armed := false
var _slam_started_at := 0.0
var _slam_ready_at := 0.0
var _slam_query := PhysicsShapeQueryParameters3D.new()
var _slam_material: StandardMaterial3D
var _slam_tween: Tween

var _shockwave_ready_at := 0.0
var _wave_query := PhysicsShapeQueryParameters3D.new()
var _wave_material: StandardMaterial3D
var _wave_tween: Tween


func _ready() -> void:
	health = max_health
	_spawn_point = global_position

	_reset_inventory()

	var swing_shape := SphereShape3D.new()
	swing_shape.radius = attack_reach
	_query.shape = swing_shape
	_query.collision_mask = hitbox.collision_mask
	_query.collide_with_bodies = true
	_query.collide_with_areas = false
	_query.exclude = [get_rid()]

	# The dash and the shockwave scan the same "damageable" layer as the sword.
	var dash_shape := SphereShape3D.new()
	dash_shape.radius = dodge_hit_radius
	_dash_query.shape = dash_shape
	_dash_query.collision_mask = hitbox.collision_mask
	_dash_query.collide_with_bodies = true
	_dash_query.collide_with_areas = false
	_dash_query.exclude = [get_rid()]

	var wave_shape := SphereShape3D.new()
	wave_shape.radius = shockwave_radius
	_wave_query.shape = wave_shape
	_wave_query.collision_mask = hitbox.collision_mask
	_wave_query.collide_with_bodies = true
	_wave_query.collide_with_areas = false
	_wave_query.exclude = [get_rid()]

	var slam_shape := SphereShape3D.new()
	slam_shape.radius = slam_radius
	_slam_query.shape = slam_shape
	_slam_query.collision_mask = hitbox.collision_mask
	_slam_query.collide_with_bodies = true
	_slam_query.collide_with_areas = false
	_slam_query.exclude = [get_rid()]

	_wave_material = shockwave_ring.get_active_material(0) as StandardMaterial3D
	_hide_shockwave_ring()
	_slam_material = slam_ring.get_active_material(0) as StandardMaterial3D
	_hide_slam_ring()

	anim.animation_finished.connect(_on_animation_finished)
	_setup_blending()
	_silence_viewmodel_shadows(head)
	if sweep_trail != null:
		_sweep_mesh = ImmediateMesh.new()
		sweep_trail.mesh = _sweep_mesh
		# Top level: the arc is placed where the hit query actually runs, not
		# wherever the head happens to be bobbing this frame.
		sweep_trail.top_level = true
		sweep_trail.visible = false
	anim.play(&"idle")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_base_fov = camera.fov
	_look_pitch = head.rotation.x
	_head_rest = head.position
	_bob_noise.seed = randi()
	_bob_noise.frequency = 1.0
	_bob_noise.fractal_octaves = 2
	_dodge_meter = float(dodge_charges)

	var world := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if world != null and world.environment != null:
		_environment = world.environment
		_base_saturation = _environment.adjustment_saturation
	health_changed.emit(health, max_health)
	inventory_changed.emit()


## Camera flourishes run here rather than in _physics_process: they are purely
## visual, and at 60 Hz physics a fast punch like this would visibly step.
func _process(delta: float) -> void:
	_update_dash_view(delta)
	_update_head(delta)
	_update_sweep_trail(delta)
	_update_colour(delta)
	if _damage_mark > 0.0:
		_damage_mark = maxf(_damage_mark - delta / maxf(damage_mark_time, 0.001), 0.0)


## Opens the view out during a dash, then lets it fall away. The bank it used
## to apply directly now goes through _update_head, which composes it with the
## bob and your look so the three cannot overwrite one another.
func _update_dash_view(delta: float) -> void:
	if _dash_view <= 0.0 and _swing_kick <= 0.0:
		return
	if _dash_view > 0.0:
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
	camera.fov = _base_fov + dash_fov_kick * dash - attack_fov_kick * swing
	if _dash_view <= 0.0 and _swing_kick <= 0.0:
		# Land exactly back on the authored value rather than near it.
		camera.fov = _base_fov


## The whole head transform, assembled in one place every frame: your look, the
## dash bank, and the bob. Anything that writes to the head directly would be
## clobbered by whichever of these ran last, so nothing else does.
func _update_head(delta: float) -> void:
	if _land_kick > 0.0:
		_land_kick = maxf(_land_kick - delta / maxf(landing_kick_time, 0.001), 0.0)

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

	# Squared and applied straight to position, same as the swing/dash kicks
	# below -- a landing is an impact, not something that should ease in.
	var land := _land_kick * _land_kick * _land_strength
	head.position = _head_rest + _bob_offset - Vector3(0, landing_bob_height * land, 0)
	# Look is added untouched, never smoothed -- lagging the crosshair behind
	# the mouse would feel like input lag, not like weight.
	# The swing punch joins the same composition as everything else, for the
	# reason in the comment above this function.
	var swing := _swing_kick * _swing_kick
	head.rotation.x = _look_pitch + _bob_pitch + deg_to_rad(attack_view_kick) * swing \
		+ deg_to_rad(landing_view_kick) * land
	head.rotation.z = _bob_roll + deg_to_rad(dash_roll_degrees) \
		* (_dash_view * _dash_view) * _dash_lateral \
		+ deg_to_rad(attack_view_roll) * swing * _swing_roll


## Drains the colour out of the world while dashing and lets it back in as the
## dash ends, so the invulnerability is something you can see rather than
## something you have to remember.
func _update_colour(delta: float) -> void:
	if _environment == null:
		return
	var target: float = 0.0 if is_dodging() else _base_saturation
	# Out fast, back slowly: the drop should register instantly, the return
	# should feel like coming up for air.
	var rate: float = delta / maxf(
		dash_desaturate_in if target < _environment.adjustment_saturation
		else dash_desaturate_out, 0.001)
	_environment.adjustment_saturation = move_toward(
		_environment.adjustment_saturation, target, _base_saturation * rate)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Yaw turns the whole body so movement follows the view; pitch stays on
		# the head alone, otherwise looking up would tilt the capsule.
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Kept in its own variable rather than read back off the node. The head
		# also carries the bob and the dash bank, and accumulating look from a
		# value those have already nudged would let them drift into your aim.
		_look_pitch = clampf(
			_look_pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch),
		)
	elif event.is_action_pressed("attack"):
		# While the mouse is free, a click is the player asking for it back
		# rather than asking to swing.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_start_attack()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("shockwave"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			cast_shockwave()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("dodge"):
		try_dodge()
	# Escape is the pause menu's now -- it takes the event before this runs and
	# frees the mouse itself.
	else:
		for slot in consumables.size():
			if event.is_action_pressed("use_slot_%d" % (slot + 1)):
				use_consumable(slot)
				return


func _physics_process(delta: float) -> void:
	# A slam is fully committed: straight down, no steering, until it lands.
	if _slamming:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = -slam_descent_speed
		move_and_slide()
		if is_on_floor() or _now() - _slam_started_at > slam_timeout:
			_land_slam()
		# The dive forces its own velocity every frame regardless of the floor,
		# so it is never a "landing" for the bob below -- the ring already
		# sells that impact. Kept in step here so the normal branch does not
		# see a false false->true edge on the frame right after the slam ends.
		_was_grounded = is_on_floor()
		_drain_rally(delta)
		return

	var was_grounded := _was_grounded

	if not is_on_floor():
		velocity += get_gravity() * delta

	# Coyote time. Walking off a ledge and pressing jump a moment later is what
	# a player means to do, and refusing it reads as the jump being eaten
	# rather than as their timing being wrong. Only ever granted for walking
	# off an edge -- the moment you jump, the credit is spent, so it can never
	# hand out a second jump in mid-air.
	if is_on_floor():
		_coyote_until = _now() + coyote_time
	if Input.is_action_just_pressed("jump") and _now() < _coyote_until:
		velocity.y = jump_velocity
		_coyote_until = 0.0

	# The pool refills continuously rather than in whole charges, so the bar
	# creeps back up instead of jumping half a width at a time.
	if dodge_cooldown > 0.0 and _dodge_meter < float(dodge_charges):
		_dodge_meter = minf(
			_dodge_meter + delta * float(dodge_charges) / dodge_cooldown,
			float(dodge_charges))

	var dodging := is_dodging()
	if _phase_window_open():
		_update_phasing()
		# Checked before the movement below, so a dash that is still inside an
		# enemy carries on this frame rather than stopping inside it.
		_extend_dash_if_inside(delta)
		dodging = is_dodging()
	else:
		# Per body, and only once that body is clear.
		_release_phasing()

	if dodging:
		# A dodge is committed: no steering for its duration.
		velocity.x = _dodge_direction.x * dodge_speed
		velocity.z = _dodge_direction.z * dodge_speed
	elif is_on_floor():
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (global_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

		# Swinging slows you. Without it the faster strokes would let you cover
		# ground at full walking pace while permanently mid-attack.
		var walk := move_speed * (attack_move_scale if _attacking else 1.0)
		var target_velocity := direction * walk
		# Damping is raised during a swing so the lunge surge is gone well before
		# the stroke ends, leaving the back half of it visibly slower.
		var damp := acceleration * (attack_damp_scale if _attacking else 1.0)
		velocity.x = move_toward(velocity.x, target_velocity.x, damp * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, damp * delta)
		# Remember the line being travelled, so losing the ground freezes it.
		# Taken from the input rather than the velocity: at the instant of a
		# standing-start jump the velocity is still near zero, but the direction
		# the player has committed to is already in their hands.
		if direction != Vector3.ZERO:
			_air_heading = direction
		elif absf(velocity.x) > 0.01 or absf(velocity.z) > 0.01:
			_air_heading = Vector3(velocity.x, 0.0, velocity.z).normalized()
	else:
		# Airborne and not dashing: the HEADING is locked, the SPEED is not.
		#
		# Freezing horizontal velocity outright locked both, which made a jump a
		# fixed-length glide the player could not shorten. They can now throttle
		# along the line they committed to -- ease off and you slow, hold it and
		# you keep pace -- but they cannot turn.
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		var speed_now := horizontal.length()
		# The heading is re-read from the live velocity rather than from the
		# stored one, so a knockback that shoves the player sideways redirects
		# the lock instead of being dragged back onto the old line. Being hit is
		# not steering. A dash overrides this branch entirely, above.
		var heading := horizontal / speed_now if speed_now > 0.01 else _air_heading
		if heading != Vector3.ZERO:
			var air_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			var wish := global_basis * Vector3(air_input.x, 0.0, air_input.y)
			# Only the component ALONG the locked heading counts. Sideways input
			# does nothing, and pushing back does not reverse you, because a
			# reversal is a direction change and that is the thing being
			# forbidden.
			var throttle := 0.0
			if wish.length_squared() > 0.000001:
				throttle = clampf(wish.normalized().dot(heading), 0.0, 1.0)
			var air_walk := move_speed * (attack_move_scale if _attacking else 1.0)
			# Gentler than on the ground: at full ground damping, releasing the
			# stick mid-jump stops the player dead in the air, which reads as
			# hitting an invisible wall rather than as easing off.
			var air_damp := acceleration * air_damp_scale \
				* (attack_damp_scale if _attacking else 1.0)
			var new_speed := move_toward(speed_now, air_walk * throttle, air_damp * delta)
			velocity.x = heading.x * new_speed
			velocity.z = heading.z * new_speed
	# The camera is untouched by all of the above; look is handled entirely in
	# _unhandled_input, so the player can always see where they are going even
	# when they cannot change it.

	# Impact speed for the landing bob below, read before move_and_slide can
	# zero it against the floor.
	var pre_move_fall_speed := -velocity.y

	move_and_slide()
	_update_locomotion()

	if is_on_floor() and not was_grounded:
		_on_landed(pre_move_fall_speed)
	_was_grounded = is_on_floor()

	if _hit_window_open:
		_resolve_hits()
	if dodging:
		_resolve_dash_hits()

	_drain_rally(delta)


## The bank holds briefly, then bleeds away -- the yellow stretch on the bar
## shrinking is the window closing.
func _drain_rally(delta: float) -> void:
	if rally_health <= 0.0 or _dead:
		return
	if _now() < _rally_hold_until:
		return
	var rate := max_health if rally_drain <= 0.0 else (max_health / rally_drain)
	rally_health = maxf(rally_health - rate * delta, 0.0)


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


## Claws health back out of the bank for damage dealt. Returns what was taken.
func rally_from_damage(amount: float) -> float:
	if _dead or rally_health <= 0.0 or amount <= 0.0:
		return 0.0
	var regained := minf(amount * rally_recovery_ratio, rally_health)
	regained = minf(regained, max_health - health)
	if regained <= 0.0:
		return 0.0
	health += regained
	rally_health -= regained
	health_changed.emit(health, max_health)
	return regained


## Draws the arc the swing is really testing against.
##
## This is deliberately not a ribbon traced along the blade. The sword does not
## damage what the mesh passes through -- `_resolve_hits` sweeps a sphere of
## `attack_reach` around the player and keeps whatever falls inside
## `_sweep_half_angle()` of where the camera is looking. A blade-shaped trail
## would therefore advertise a thin line while a wide wedge is what actually
## cuts. This draws that wedge instead, from the same origin, so what you see is
## what the swing hits.
##
## Re-aimed every frame rather than pinned at the start: the hit query reads the
## current facing too, so turning mid-swing has to move both together or the
## picture stops matching.
func _update_sweep_trail(delta: float) -> void:
	if sweep_trail == null or _sweep_mesh == null:
		return
	# Transparent, overlapping and full-screen-ish -- exactly the shape of thing
	# the low presets are meant to drop.
	if not sweep_trail_enabled or not Graphics.effects:
		if sweep_trail.visible:
			sweep_trail.visible = false
		return

	if _hit_window_open:
		_sweep_progress = minf(
			_sweep_progress + delta / maxf(sweep_trail_span, 0.001), 1.0)
	elif _sweep_fade > 0.0:
		_sweep_fade = maxf(_sweep_fade - delta / maxf(sweep_trail_fade, 0.001), 0.0)

	if _sweep_fade <= 0.0:
		if sweep_trail.visible:
			sweep_trail.visible = false
			_sweep_mesh.clear_surfaces()
		return

	var forward := -head.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	sweep_trail.global_transform = Transform3D(
		Basis.looking_at(forward.normalized(), Vector3.UP),
		global_position + Vector3(0, 0.9, 0))
	sweep_trail.visible = true
	_build_sweep_mesh()


func _build_sweep_mesh() -> void:
	var outer := attack_reach
	var inner := attack_reach * clampf(sweep_trail_inner, 0.0, 0.95)
	var lead := lerpf(_sweep_from, _sweep_to, _sweep_progress)
	var segs := maxi(sweep_trail_segments, 3)

	_sweep_mesh.clear_surfaces()
	_sweep_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var a0 := lerpf(_sweep_from, lead, t0)
		var a1 := lerpf(_sweep_from, lead, t1)
		# The far end of the arc is where the blade has just been, so the tail
		# behind it is dimmer and the leading edge is brightest.
		var f0 := _sweep_fade * sweep_trail_alpha * (0.12 + 0.88 * t0)
		var f1 := _sweep_fade * sweep_trail_alpha * (0.12 + 0.88 * t1)
		var in0 := _sweep_point(a0, inner)
		var out0 := _sweep_point(a0, outer)
		var in1 := _sweep_point(a1, inner)
		var out1 := _sweep_point(a1, outer)
		# Faded towards the middle so the band marks the edge of reach rather
		# than filling the whole wedge with colour.
		_sweep_tri(in0, f0 * 0.2, out0, f0, out1, f1)
		_sweep_tri(in0, f0 * 0.2, out1, f1, in1, f1 * 0.2)
	_sweep_mesh.surface_end()


## -Z is forward, and a positive angle yaws left, matching `_resolve_hits`.
func _sweep_point(angle: float, radius: float) -> Vector3:
	return Vector3(-sin(angle) * radius, 0.0, -cos(angle) * radius)


func _sweep_tri(a: Vector3, aa: float, b: Vector3, ba: float, c: Vector3, ca: float) -> void:
	var c3 := sweep_trail_color
	_sweep_mesh.surface_set_color(Color(c3.r, c3.g, c3.b, aa))
	_sweep_mesh.surface_add_vertex(a)
	_sweep_mesh.surface_set_color(Color(c3.r, c3.g, c3.b, ba))
	_sweep_mesh.surface_add_vertex(b)
	_sweep_mesh.surface_set_color(Color(c3.r, c3.g, c3.b, ca))
	_sweep_mesh.surface_add_vertex(c)


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
	# In the air, the attack button means "come down on them" instead. The dive
	# always happens; whether it detonates depends on the cooldown.
	if not is_on_floor() and not _slamming:
		_start_slam()
		return
	if _attacking or _slamming:
		return
	_attacking = true
	anim.play(ATTACKS[_next_attack], -1.0, attack_speed)
	# Alternating strokes roll the view opposite ways, so a combo reads as two
	# distinct cuts rather than the same one twice.
	_swing_roll = 1.0 if _next_attack == 0 else -1.0
	_swing_kick = maxf(_swing_kick, 1.0)
	# A positive yaw about +Y points left, so a right-to-left stroke runs from
	# -half_arc to +half_arc. Index 0 (`slash`) goes right to left; index 1
	# (`chop`) comes back the other way.
	var half := _sweep_half_angle()
	_sweep_from = -half if _next_attack == 0 else half
	_sweep_to = half if _next_attack == 0 else -half
	_next_attack = (_next_attack + 1) % ATTACKS.size()

	# A swing carries you forward: one impulse, bled off by the raised damping
	# below rather than by a clock of its own.
	var facing := -global_basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.0001:
		facing = facing.normalized()
		velocity.x += facing.x * attack_lunge
		velocity.z += facing.z * attack_lunge


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
	if _attacking or _slamming or _dead:
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
	_slam_started_at = _now()
	# Decided on commitment so the landing knows which effect to play, and so a
	# long fall does not stretch the cooldown.
	_slam_armed = _now() >= _slam_ready_at
	if _slam_armed:
		_slam_ready_at = _now() + slam_cooldown
	_attacking = false
	_hit_window_open = false
	# Its own clip now. `chop` used to be borrowed for this pose, but `chop` is a
	# horizontal sweep these days and reads as nothing like a dive.
	anim.play(&"dive")
	anim.seek(0.0, true)


func _land_slam() -> void:
	_slamming = false

	if not _slam_armed:
		# Landed, but the blast is still charging: a puff of dust, no damage.
		_play_slam_ring(slam_dud_color, slam_dud_radius, 0.45)
		_update_locomotion()
		return

	var origin := global_position + Vector3(0, 0.6, 0)
	_slam_query.transform = Transform3D(Basis(), origin)

	for hit in get_world_3d().direct_space_state.intersect_shape(_slam_query, 32):
		var body := hit["collider"] as Node3D
		if body == null:
			continue
		var away := body.global_position - global_position
		away.y = 0.0
		var direction := away.normalized() if away.length_squared() > 0.0001 else -global_basis.z
		if body.has_method("take_damage"):
			body.take_damage(slam_damage, direction)
			rally_from_damage(slam_damage)
		if body.has_method("apply_knockback"):
			body.apply_knockback(direction * slam_push, slam_stun)

	_play_slam_ring(slam_ring_color, slam_radius, 0.85)
	_update_locomotion()


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


func _hide_slam_ring() -> void:
	if _slam_material != null:
		_slam_material.albedo_color.a = 0.0
	slam_ring.scale = Vector3.ONE * 0.25


## Called from a method track partway into each swing -- the sword only bites
## during the active frames of the animation, not the wind-up or recovery.
func _hitbox_on() -> void:
	# The slam reuses the chop clip purely as a pose; its damage is the ring.
	if _slamming:
		return
	_hit_this_swing.clear()
	_hit_window_open = true
	_sweep_progress = 0.0
	_sweep_fade = 1.0


func _hitbox_off() -> void:
	_hit_window_open = false



## Polled every physics frame while the window is open. Everything inside the
## reach sphere and within the arc of the camera is cut, once per swing, so a
## wide sweep connects with a whole group instead of only what the blade mesh
## happened to pass through.
func _resolve_hits() -> void:
	var origin := global_position + Vector3(0, 0.9, 0)
	_query.transform = Transform3D(Basis(), origin)

	var forward := -head.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	var half_arc := _sweep_half_angle()

	for hit in get_world_3d().direct_space_state.intersect_shape(_query, 24):
		var body := hit["collider"] as Node3D
		if body == null or body in _hit_this_swing:
			continue

		var offset := body.global_position - global_position
		offset.y = 0.0
		if offset.length_squared() < 0.0001:
			continue
		var distance := offset.length()

		# Some targets have to be aimed at rather than merely swung near -- a
		# boss's exposed weak point, for one. They answer aim_tolerance() with a
		# much tighter cone, and get no allowance for their own width, so the
		# player has to actually put them on the crosshair. Everything else is
		# measured to its near edge, not its centre, so something only half on
		# screen still counts as within the swing.
		var aimed := body.has_method("aim_tolerance")
		var tolerance: float = body.aim_tolerance() if aimed else half_arc
		if not aimed:
			var radius := _body_radius_of(body)
			if distance > radius:
				tolerance += asin(radius / distance)
		if forward.angle_to(offset.normalized()) > tolerance:
			continue
		if require_line_of_sight and _is_blocked(origin, body):
			continue

		_hit_this_swing.append(body)
		# A connecting swing punches the view harder than a miss. Capped rather
		# than accumulated, so cutting through a whole pack does not slam the
		# camera once per body.
		_swing_kick = minf(_swing_kick + attack_hit_kick, 1.5)
		var push_dir := offset.normalized()
		if aimed:
			# Rallies off what the strike really did, not the sword's usual
			# figure, since a weak point is worth many times a normal hit.
			rally_from_damage(body.strike(push_dir))
			continue
		if body.has_method("take_damage"):
			body.take_damage(attack_damage, push_dir)
			rally_from_damage(attack_damage)
		if body.has_method("apply_knockback"):
			body.apply_knockback(push_dir * attack_push, attack_stun)


## Half the width of the swing, in radians. Derived from the camera so the
## sweep covers exactly what is on screen: Godot keeps the vertical FOV and
## widens horizontally, so an ultrawide display genuinely swings wider.
func _sweep_half_angle() -> float:
	var fallback := deg_to_rad(attack_arc_degrees * 0.5)
	if not sweep_matches_fov:
		return fallback
	var camera := head.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return fallback
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		return deg_to_rad(camera.fov * 0.5)

	var view := get_viewport().get_visible_rect().size
	if view.y <= 0.0:
		return fallback
	return atan(tan(deg_to_rad(camera.fov * 0.5)) * (view.x / view.y))


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


## Dashes in the direction being held, or straight backwards if no direction is
## held. Returns false when the dodge is still on cooldown.
func try_dodge() -> bool:
	var now := _now()
	if _dead or _dodge_meter < 1.0:
		return false

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		# Nothing held: retreat, the instinctive panic dodge. +Z is behind us.
		direction = global_basis.z
	_dodge_direction = direction.normalized()

	_dodge_until = now + dodge_duration
	_dodge_meter -= 1.0
	_hit_this_dash.clear()
	if dodge_invulnerable:
		_invulnerable_until = maxf(_invulnerable_until, _dodge_until)
	# Deliberately not cleared first: dashing again while still inside someone
	# should keep passing through them, not snap them solid underneath you.
	_phase_hold_until = now + dodge_phase_hold_max
	# Ceiling on how far a dash may be stretched to get clear of something, so
	# a body that somehow never clears cannot make the dash run forever.
	_dodge_extend_limit = now + dodge_duration + dodge_max_extension
	_update_phasing()

	# How sideways this dash is, measured against where you are looking rather
	# than where the body faces, so the bank matches what is on screen.
	_dash_lateral = clampf(_dodge_direction.dot(head.global_basis.x), -1.0, 1.0)
	_dash_view = 1.0

	dodged.emit()
	return true


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


## Intangible for exactly as long as the dash lasts -- and the dash lasts
## longer when it ran into something. See _extend_dash_if_inside.
func _phase_window_open() -> bool:
	return is_dodging()


## True while the dash is still inside something it went into.
func _inside_anything() -> bool:
	for body in _phased_through:
		if is_instance_valid(body) and _overlapping(body):
			return true
	return false


## Keeps a dash going while it is still inside an enemy, so you always come out
## the far side rather than stopping half way through one.
##
## A dash that touches nothing is exactly the length it always was; this only
## ever adds time, and only while there is a body still around you.
func _extend_dash_if_inside(delta: float) -> void:
	if _now() + delta < _dodge_until:
		return
	if _now() >= _dodge_extend_limit or not _inside_anything():
		return
	_dodge_until = _now() + delta * 1.5


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


## Whole charges in hand.
func dodge_charges_ready() -> int:
	return int(floor(_dodge_meter))


## True when there is at least one dash banked.
func dodge_ready() -> bool:
	return _dodge_meter >= 1.0


## Everything the dash barges through takes a little damage and gets shoved
## along the dash direction, once per dash.
func _resolve_dash_hits() -> void:
	_dash_query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.9, 0))
	for hit in get_world_3d().direct_space_state.intersect_shape(_dash_query, 16):
		var body := hit["collider"] as Node3D
		if body == null or body in _hit_this_dash:
			continue
		_hit_this_dash.append(body)
		if body.has_method("take_damage"):
			body.take_damage(dodge_damage, _dodge_direction)
			rally_from_damage(dodge_damage)
		if body.has_method("apply_knockback"):
			body.apply_knockback(_dodge_direction * dodge_push, dodge_stun)


## Radial burst centred on the player: throws everything in range straight
## outward and interrupts it, without dealing damage. Returns false while on
## cooldown.
func cast_shockwave() -> bool:
	var now := _now()
	if _dead or now < _shockwave_ready_at:
		return false
	_shockwave_ready_at = now + shockwave_cooldown

	var origin := global_position + Vector3(0, 0.9, 0)
	_wave_query.transform = Transform3D(Basis(), origin)
	var struck := 0
	for hit in get_world_3d().direct_space_state.intersect_shape(_wave_query, 32):
		var body := hit["collider"] as Node3D
		if body == null:
			continue
		var away := body.global_position - global_position
		away.y = 0.0
		# Directly on top of us: shove it the way we are facing instead.
		var direction := away.normalized() if away.length_squared() > 0.0001 else -global_basis.z
		if body.has_method("apply_knockback"):
			body.apply_knockback(direction * shockwave_push, shockwave_stun)
		struck += 1

	_play_shockwave_ring()
	shockwave_cast.emit()
	return struck >= 0


## 0.0 just after casting, 1.0 when ready again.
func shockwave_charge() -> float:
	if shockwave_cooldown <= 0.0:
		return 1.0
	var remaining := _shockwave_ready_at - _now()
	return clampf(1.0 - remaining / shockwave_cooldown, 0.0, 1.0)


func _play_shockwave_ring() -> void:
	if _wave_material == null:
		return
	if _wave_tween != null and _wave_tween.is_valid():
		_wave_tween.kill()
	shockwave_ring.scale = Vector3.ONE * 0.2
	_wave_material.albedo_color.a = 0.8

	_wave_tween = create_tween().set_parallel(true)
	_wave_tween.tween_property(shockwave_ring, "scale", Vector3.ONE * shockwave_radius, 0.35) \
		.set_ease(Tween.EASE_OUT)
	_wave_tween.tween_property(_wave_material, "albedo_color:a", 0.0, 0.35)


func _hide_shockwave_ring() -> void:
	if _wave_material != null:
		_wave_material.albedo_color.a = 0.0
	shockwave_ring.scale = Vector3.ONE * 0.2


func is_dodging() -> bool:
	return _now() < _dodge_until


## 0.0 just after dodging, 1.0 when ready again -- for the HUD readout.
func dodge_charge() -> float:
	if dodge_charges <= 0:
		return 1.0
	return clampf(_dodge_meter / float(dodge_charges), 0.0, 1.0)


func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	var now := _now()
	if now < _invulnerable_until:
		return
	_invulnerable_until = now + invulnerable_time
	_mark_damage(amount, _from_direction)

	var before := health
	health = maxf(health - amount, 0.0)
	# Bank what was actually lost, capped so the bank can never imply more than
	# full health.
	var lost := before - health
	rally_health = minf(rally_health + lost * rally_fraction, max_health - health)
	_rally_hold_until = now + rally_hold

	health_changed.emit(health, max_health)
	if health <= 0.0:
		rally_health = 0.0
		_die()


## Drinks the consumable in `slot` (0-based). Returns false and keeps the item
## if the slot is empty or the player is already at full health.
func use_consumable(slot: int) -> bool:
	if _dead or slot < 0 or slot >= consumables.size():
		return false
	var type := consumables[slot]
	if type == null or counts[slot] <= 0:
		return false
	if heal(type.heal_amount, type.item_name) <= 0.0:
		return false
	counts[slot] -= 1
	inventory_changed.emit()
	return true


## Returns how many were actually added, which is less than `amount` when the
## stack is already full.
## `notify` raises the small pickup line at the bottom of the screen. Anything
## that announces itself more loudly -- a chest, a mimic -- passes false, so the
## player is not told the same thing twice in two different places.
func add_consumable(type: ConsumableType, amount := 1, notify := true) -> int:
	var slot := _slot_of(type)
	if slot == -1:
		return 0
	var before := counts[slot]
	counts[slot] = mini(counts[slot] + amount, max_stack)
	var added := counts[slot] - before
	if added > 0:
		inventory_changed.emit()
		if notify:
			consumable_gained.emit(type, added)
	return added


## Matches by reference first, then by name -- two .tres loads of the same file
## are normally the same instance, but a duplicated resource should still stack.
func _slot_of(type: ConsumableType) -> int:
	if type == null:
		return -1
	var slot := consumables.find(type)
	if slot != -1:
		return slot
	for i in consumables.size():
		if consumables[i] != null and consumables[i].item_name == type.item_name:
			return i
	return -1


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
	died.emit()
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	# Forced: the body is being teleported anyway, so there is no overlap left
	# to walk out of and nothing to be shoved by.
	_release_phasing(true)
	global_position = _spawn_point
	velocity = Vector3.ZERO
	health = max_health
	_dead = false
	_invulnerable_until = _now() + invulnerable_time
	_dodge_until = 0.0
	_shockwave_ready_at = 0.0
	rally_health = 0.0
	_slamming = false
	_slam_ready_at = 0.0
	# The teleport is not a fall -- without this the next frame's is_on_floor()
	# transition would read as a landing and fire the bob for a hit that never
	# happened.
	_was_grounded = true
	_land_kick = 0.0
	_reset_inventory()
	health_changed.emit(health, max_health)
	respawned.emit()


func _reset_inventory() -> void:
	counts.resize(consumables.size())
	for slot in consumables.size():
		counts[slot] = starting_counts[slot] if slot < starting_counts.size() else 0
	inventory_changed.emit()


## Shoved by something in the world. Applied straight to velocity so the hit
## carries you, rather than being smoothed away by the movement code.
func apply_knockback(impulse: Vector3, _stun_time := 0.0) -> void:
	if _dead:
		return
	_slamming = false
	velocity += impulse


## Used by the level builder, which decides where the start actually is.
func set_spawn_point(point: Vector3) -> void:
	_spawn_point = point


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
