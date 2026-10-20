extends CanvasLayer

## Health bar, inventory slots, and a transient line of text for pickups,
## consumable use and death.

@export var low_health_fraction := 0.3
## The green flash holds this long before the red starts climbing into it.
@export var gain_hold := 0.3
## How long the red then takes to close the gap, whatever its size. Timing the
## whole gap rather than using a fixed rate means a small heal is just as
## visible as a large one -- a 20-point rally used to flash past in 0.14 s.
@export var gain_climb_time := 0.75
@export var normal_color := Color(0.788235, 0.235294, 0.254902)
@export var low_color := Color(0.937255, 0.415686, 0.184314)

@export var dodge_ready_color := Color(0.407843, 0.705882, 0.898039)
@export var dodge_charging_color := Color(0.317647, 0.360784, 0.415686)
@export var count_color := Color(0.929412, 0.941176, 0.952941)
## Used for the count once the stack cannot take any more.
@export var count_full_color := Color(0.427451, 0.898039, 0.478431)

@onready var bar: ProgressBar = $HealthGroup/HealthStack/HealthBar
## Was the yellow stretch of damage that hitting back could win back. That is
## gone; the bar is kept hidden rather than pulled out of the scene.
@onready var rally_bar: ProgressBar = $HealthGroup/HealthStack/RallyBar
## Sits between them at the true health value. When health rises the red bar
## eases up to meet it, and the gap shows as a green flash of health gained.
@onready var gain_bar: ProgressBar = $HealthGroup/HealthStack/GainBar
@onready var label: Label = $HealthGroup/HealthLabel
@onready var dodge_bar: ProgressBar = $HealthGroup/DodgeBar
@onready var slam_bar: ProgressBar = $HealthGroup/SlamBar
@onready var slots_box: HBoxContainer = $Slots
@onready var toast: Label = $Toast
@onready var boss_group: VBoxContainer = $BossGroup
@onready var boss_label: Label = $BossGroup/BossLabel
@onready var boss_bar: ProgressBar = $BossGroup/BossStack/BossBar
## Lags behind the boss's real health, so a hit leaves a yellow stretch that
## holds for a beat and then sweeps away.
@onready var boss_trail_bar: ProgressBar = $BossGroup/BossStack/BossTrailBar
## Poise. Hidden for anything that does not have any, since an enemy with no
## poise is interrupted by every hit and has nothing to show.
@onready var poise_bar: ProgressBar = $BossGroup/PoiseBar
@onready var perf_panel: PanelContainer = $PerfPanel
@onready var perf_label: Label = $PerfPanel/PerfLabel
@onready var dash_streaks: ColorRect = $DashStreaks
@onready var damage_mark: ColorRect = $DamageMark
@onready var banner: VBoxContainer = $Banner
@onready var banner_title: Label = $Banner/BannerTitle
@onready var banner_sub: Label = $Banner/BannerSub

@export_group("Hit marker")
## Four small diagonal ticks that pop out around the crosshair when a hit
## lands -- the shooter's hit marker, kept light.
@export var hit_mark_time := 0.18
@export var hit_mark_color := Color(1.0, 1.0, 1.0, 0.85)
## Where the ticks start and how far they spread, pixels from the centre --
## outside the crosshair's ring.
@export var hit_mark_inner := 12.0
@export var hit_mark_spread := 4.0
@export var hit_mark_length := 5.0

@export_group("Crosshair")
## A white dot inside a white ring. While something can be used with E, four
## corner brackets close in round the ring -- the only sign; nothing is written
## in the world.
@export var crosshair_color := Color(1.0, 1.0, 1.0, 0.8)
@export var crosshair_radius := 9.0
## Seconds for the brackets to close in and to go.
@export var interact_morph_time := 0.12

@export_group("Kill banner")
@export var banner_fade_in := 0.45
@export var banner_hold := 2.6
@export var banner_fade_out := 1.1

@export_group("Performance readout")
## Frames per second, plus the two numbers that actually explain a bad one:
## how many objects the renderer was handed and how many draw calls that cost.
@export var show_performance := true
## How often the readout is recomputed. Updating it every frame makes the
## digits unreadable and costs more than it measures.
@export var perf_interval := 0.25

@export_group("Boss bar")
@export var boss_title := "THE WARDEN"
## How long the yellow stretch holds before it starts sweeping away.
@export var boss_trail_hold := 0.45
## How long the yellow takes to catch up to the real health once it moves.
@export var boss_trail_drain := 0.9
## Poise damage piling up.
@export var poise_color := Color(0.615686, 0.678431, 0.87451)
## Shown for the length of the stagger the bar just earned.
@export var poise_broken_color := Color(1.0, 0.831373, 0.443137)

var _fill: StyleBoxFlat
var _dodge_fill: StyleBoxFlat
var _poise_fill: StyleBoxFlat
var _toast_tween: Tween
var _player: Node
## The weapon in hand's name, shown for a moment above the health bar when it changes.
var _held_label: Label
var _held_tween: Tween
var _inventory_screen: CanvasLayer
## The red bar's shown value. Snaps down on damage, climbs on healing.
var _shown_health := -1.0
var _last_health := -1.0
var _gain_hold_left := 0.0
var _gain_rate := 0.0
var _boss: Node = null
var _boss_trail := 0.0
var _boss_last_health := 0.0
var _boss_hold_left := 0.0
var _perf_left := 0.0
var _banner_tween: Tween
## Worst frame seen since the readout was last reset, which is the number that
## matters -- an average hides exactly the hitches you are hunting.
var _worst_frame_ms := 0.0
var _hit_mark: Control
## 1 on a hit, falling to 0 over `hit_mark_time`.
var _hit_mark_left := 0.0
var _interact_mark: Control
var _drink_box: VBoxContainer
var _drink_bar: ProgressBar
## 0 = plain crosshair, 1 = interact cursor; eased between.
var _interact_k := 0.0
## CO-OP (coop.gd): whose HUD this is -- 0 player 1, 1 player 2. HUD2 is in
## scenes/main.tscn always and takes itself away outside co-op; in co-op
## split_screen.gd moves each HUD into its player's half.
@export var player_index := 0
var _discarded := false
## The player this HUD shows (coop.gd `hud`).
var player: Node:
	get:
		return _player


func _enter_tree() -> void:
	if player_index == 1 and not Coop.active and not _discarded:
		_discarded = true
		remove_from_group(&"hud")
		process_mode = Node.PROCESS_MODE_DISABLED
		queue_free()


func _ready() -> void:
	if _discarded:
		return
	toast.modulate.a = 0.0
	# Duplicate so recolouring the fill does not mutate the shared stylebox.
	_fill = (bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	bar.add_theme_stylebox_override("fill", _fill)
	_dodge_fill = (dodge_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	dodge_bar.add_theme_stylebox_override("fill", _dodge_fill)
	_poise_fill = (poise_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	poise_bar.add_theme_stylebox_override("fill", _poise_fill)
	perf_panel.visible = show_performance
	banner.modulate.a = 0.0
	_layout_health()
	_hit_mark = Control.new()
	_hit_mark.name = "HitMark"
	_hit_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_mark.visible = false
	_hit_mark.draw.connect(_draw_hit_mark)
	$Crosshair.add_child(_hit_mark)
	# The ring (and, when something is usable, the brackets) round the scene's
	# centre dot. The scene's four cross ticks are retired.
	_interact_mark = Control.new()
	_interact_mark.name = "Ring"
	_interact_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_mark.draw.connect(_draw_interact_mark)
	$Crosshair.add_child(_interact_mark)
	for tick in ["Up", "Down", "Left", "Right"]:
		($Crosshair.get_node(tick) as CanvasItem).visible = false
	($Crosshair/Dot as ColorRect).color = crosshair_color
	_build_blackout()
	# Started from the title, the loading screen faded to black: the game picks
	# up in black and stays there while the level builds, until the player
	# gets up (a new game) or the view fades in (a loaded one; maze.gd).
	if Saves.slot >= 0:
		fade_black(1.0, 0.0)
	# Deferred so the player is guaranteed to be in its group already.
	_bind_player.call_deferred()


## --- Fade to and from black -------------------------------------------------------
##
## A black sheet over everything -- the HUD and the scene letterbox included --
## on its own canvas layer. Death fades to it; the respawn fades back out of it
## (player.gd `_respawn` / `_update_wake`); the morgue's cutscene cuts to it.

var _blackout: ColorRect
var _blackout_tween: Tween


func _build_blackout() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Blackout"
	layer.layer = 90
	add_child(layer)
	_blackout = ColorRect.new()
	_blackout.color = Color(0.0, 0.0, 0.0, 1.0)
	_blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.modulate.a = 0.0
	_blackout.visible = false
	layer.add_child(_blackout)


## Fades the black sheet to `alpha` (0 clear, 1 black) over `time` seconds of
## REAL time (it ignores slow motion).
func fade_black(alpha: float, time: float) -> void:
	if _blackout == null:
		return
	if _blackout_tween != null and _blackout_tween.is_valid():
		_blackout_tween.kill()
	_blackout.visible = true
	if time <= 0.0:
		_blackout.modulate.a = alpha
		_blackout.visible = alpha > 0.0
		return
	_blackout_tween = create_tween().set_ignore_time_scale(true)
	_blackout_tween.tween_property(_blackout, "modulate:a", alpha, time)
	if alpha <= 0.0:
		_blackout_tween.tween_callback(func() -> void: _blackout.visible = false)


## As `fade_black`, but only once the game is running smoothly: a level's first
## frames are long stalls, and one of them would swallow the whole fade (a cut).
## Waits for three frames in a row under 0.1 s, or 3 s at most.
func fade_black_when_steady(alpha: float, time: float) -> void:
	var steady := 0
	var waited := 0.0
	while steady < 3 and waited < 3.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		waited += dt
		steady = steady + 1 if dt < 0.1 else 0
	fade_black(alpha, time)


func black_amount() -> float:
	return _blackout.modulate.a if _blackout != null and _blackout.visible else 0.0


func _bind_player() -> void:
	_player = Coop.player(player_index) if Coop.active else get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("HUD found no node in the 'player' group; it will not update.")
		return

	_player.health_changed.connect(_on_health_changed)
	_player.healed.connect(_on_healed)
	_player.drink_interrupted.connect(func(amount: float) -> void:
		_show_toast("Drink cut short  +%d" % roundi(amount)))
	_player.died.connect(_on_died)
	_player.inventory_changed.connect(_refresh_slots)
	_player.consumable_gained.connect(_on_consumable_gained)
	_player.selection_changed.connect(_on_selection_changed)
	if _player.has_signal("hit_landed"):
		_player.hit_landed.connect(_on_hit_landed)
	if _player.has_signal("item_gained"):
		_player.item_gained.connect(func(id: StringName, amount: int) -> void:
			_show_toast("Found %s  x%d" % [Inventory.item_name(id), amount]))

	_build_bottom()
	_on_health_changed(_player.health, _player.max_health)
	_refresh_slots()
	var icons := HBoxContainer.new()
	icons.set_script(load("res://scripts/attack_icons.gd"))
	add_child(icons)
	icons.call("setup", _player)

	_inventory_screen = CanvasLayer.new()
	_inventory_screen.name = "InventoryScreen"
	_inventory_screen.set_script(load("res://scripts/inventory_screen.gd"))
	add_child(_inventory_screen)
	_inventory_screen.setup(_player)


## --- Health at the bottom (2026-10-10) ----------------------------------------
##
## The health bar sits centred at the bottom of the screen, the numbers on the
## bar itself, the ghost bar a thin line beneath. (It sat under the hotbar,
## which the wheels have since replaced; it keeps the hotbar's old width.) The
## orange slam bar is retired: the heavy attack's icon (attack_icons.gd) shows
## that cooldown now. Laid out here rather than in hud.tscn, so the scene stays
## as it was.

const HEALTH_WIDTH := 570.0
const HEALTH_HEIGHT := 26.0
const HEALTH_BOTTOM := -16.0
## The top of the health bar, from the bottom of the screen: the held weapon's
## name and the drinking bar sit above it.
const HEALTH_TOP := HEALTH_BOTTOM - HEALTH_HEIGHT - 11.0


func _layout_health() -> void:
	var group := $HealthGroup as VBoxContainer
	var stack := $HealthGroup/HealthStack as Control
	var width := HEALTH_WIDTH
	group.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	group.grow_horizontal = Control.GROW_DIRECTION_BOTH
	group.grow_vertical = Control.GROW_DIRECTION_BEGIN
	group.add_theme_constant_override("separation", 4)
	var tall := HEALTH_HEIGHT + 4.0 + 7.0
	group.offset_left = -width * 0.5
	group.offset_right = width * 0.5
	group.offset_bottom = HEALTH_BOTTOM
	group.offset_top = HEALTH_BOTTOM - tall
	stack.custom_minimum_size = Vector2(width, HEALTH_HEIGHT)
	dodge_bar.custom_minimum_size = Vector2(width, 7.0)
	slam_bar.visible = false
	# The numbers on the bar, centred.
	label.reparent(stack, false)
	# Offsets too, or it keeps its old size and sits left of centre.
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 17)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The bottom of the screen. The old consumables strip (bottom right) and the
## hotbar are both retired (2026-10-10): weapons and quick items are on the two
## wheels (radial_menu.gd), built here too.
func _build_bottom() -> void:
	slots_box.visible = false
	for which in [&"weapons", &"quick"]:
		var wheel := Control.new()
		wheel.set_script(load("res://scripts/radial_menu.gd"))
		add_child(wheel)
		wheel.call("setup", _player, which)

	_held_label = Label.new()
	_held_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_held_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_held_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_held_label.offset_bottom = HEALTH_TOP - 8
	_held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held_label.add_theme_font_size_override("font_size", 17)
	_held_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.8))
	_held_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_held_label.add_theme_constant_override("shadow_offset_x", 1)
	_held_label.add_theme_constant_override("shadow_offset_y", 1)
	_held_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_label.modulate.a = 0.0
	add_child(_held_label)
	_build_drink_bar()
	_build_lunge_lines()
	_build_dread()


## White speed lines over the view while the spear's dash carries the player
## forward (`shaders/lunge_lines.gdshader`). Built here rather than in the scene,
## drawn first so it sits under the rest of the HUD, and hidden at rest.
var _lunge_lines: ColorRect


func _build_lunge_lines() -> void:
	_lunge_lines = ColorRect.new()
	_lunge_lines.name = "LungeLines"
	_lunge_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lunge_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lunge_lines.color = Color.WHITE
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/lunge_lines.gdshader")
	_lunge_lines.material = material
	add_child(_lunge_lines)
	move_child(_lunge_lines, 0)
	# Drawn once, invisibly, at load so its shader is compiled before the first
	# lunge rather than during it.
	material.set_shader_parameter("strength", 0.0)
	_lunge_lines.visible = true
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if is_instance_valid(_lunge_lines) and _player != null and _player.has_method("lunge_intensity") \
				and _player.lunge_intensity() <= 0.0:
			_lunge_lines.visible = false)


## --- The Remnant's presence, and the view from a hiding place --------------------
##
## No overlay: the warning is in the world. When the Remnant (stalker.gd) is
## very close -- from `CHILL_FAR` metres, full at `CHILL_NEAR` -- every torch in
## view fades from its fire to ice blue (`torch.gd` `chill`). While it HUNTS the
## player, the whole view takes an icy blue grade (the environment's colour
## correction LUT, `_apply_ice_grade`) and the camera trembles and breathes
## (`player.set_remnant_hunt`). Gameplay information, so NOT gated on
## `Graphics.effects`. `_slats`: the hiding place while the player is hidden.

## The torches start to cool at CHILL_FAR and are fully ice blue at CHILL_NEAR:
## a long, gradual ramp, so how blue they are says roughly how near it is.
## (First 18 / 6 m: too late to be any use as warning.)
const CHILL_FAR := 32.0
const CHILL_NEAR := 10.0
## Seconds for the hunt's grade to come in, and to fade once it gives up.
const HUNT_IN := 1.5
const HUNT_OUT := 3.0
const Torch := preload("res://scripts/torch.gd")

var _slats: ColorRect
var _stalker: Node3D
var _chill := 0.0
## Set by a scene to force the Remnant's cold on (torches and grade) whatever
## the distance -- the morgue's reveal. 0 normally.
var ice_override := 0.0
var _hunted_shown := 0.0
var _environment: Environment
## This HUD's share of the torches' chill (co-op: the colder HUD wins).
var torch_chill := 0.0
var _ice_gradient: Gradient
var _ice_lut: GradientTexture1D
var _ice_applied := -1.0


## --- Blood on the view at low health -------------------------------------------
##
## `shaders/blood_screen.gdshader`, driven by `_wound`: none above
## `BLOOD_FROM` of max health, full at `BLOOD_FULL`. It eases toward that --
## quickly when health drops, so a hit splashes it in, slowly as it is healed,
## so the blood washes away over the drink. Below `BLOOD_HEART` the rim throbs
## with a heartbeat. Gameplay information, so NOT gated on `Graphics.effects`.

const BLOOD_FROM := 0.5
const BLOOD_FULL := 0.1
const BLOOD_HEART := 0.35

var _blood: ColorRect
var _wound := 0.0
var _blood_phase := 0.0


func _update_blood(delta: float) -> void:
	if _blood == null or _player == null:
		return
	var fraction: float = _player.health / maxf(_player.max_health, 1.0)
	var target := 0.0 if _player.get("_dead") == true \
		else clampf((BLOOD_FROM - fraction) / (BLOOD_FROM - BLOOD_FULL), 0.0, 1.0)
	_wound = move_toward(_wound, target, delta * (3.0 if target > _wound else 0.35))
	var shown := _wound > 0.002
	if not _blood.has_meta("warming") and _blood.visible != shown:
		_blood.visible = shown
	if not shown:
		return
	var heart := clampf((BLOOD_HEART - fraction) / BLOOD_HEART, 0.0, 1.0)
	_blood_phase = fmod(_blood_phase + delta * lerpf(70.0, 130.0, heart) / 60.0, 1.0)
	var lub := exp(-pow(_blood_phase, 2.0) / 0.004)
	var dub := exp(-pow(_blood_phase - 0.28, 2.0) / 0.004) * 0.6
	var material := _blood.material as ShaderMaterial
	material.set_shader_parameter("wound", _wound)
	material.set_shader_parameter("pulse", clampf(lub + dub, 0.0, 1.0) * heart)
	var size := get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


## --- An enforcer's beam on the player (enforcer.gd) -----------------------------------
##
## A gold glow round the edges of the view while a beam holds the player (and
## for its short linger), so the slow has a visible cause. Gameplay information:
## not gated on `Graphics.effects`. A plain radial gradient, no shader.

var _beam_glow: TextureRect
var _beam_shown := 0.0


func _update_beam_glow(delta: float) -> void:
	if _player == null or not _player.has_method("beam_amount"):
		return
	if _beam_glow == null:
		var g := Gradient.new()
		# The enforcer's crystal cyan (2026-10-15; gold before), as its beam.
		g.set_color(0, Color(0.2, 0.85, 1.0, 0.0))
		g.set_color(1, Color(0.1, 0.8, 1.0, 0.55))
		g.add_point(0.55, Color(0.2, 0.85, 1.0, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.05, 0.5)
		tex.width = 256
		tex.height = 256
		_beam_glow = TextureRect.new()
		_beam_glow.name = "BeamGlow"
		_beam_glow.texture = tex
		_beam_glow.stretch_mode = TextureRect.STRETCH_SCALE
		_beam_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		_beam_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_beam_glow.modulate.a = 0.0
		_beam_glow.visible = false
		add_child(_beam_glow)
	var want: float = _player.beam_amount()
	_beam_shown = move_toward(_beam_shown, want, delta * (8.0 if want > _beam_shown else 3.0))
	_beam_glow.visible = _beam_shown > 0.01
	_beam_glow.modulate.a = _beam_shown * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.03))


## --- Berserk (the axe's heavy attack, axe.gd) ---------------------------------------
##
## Red burning in round the edges of the view while berserk, throbbing like a
## pulse, with a harder flare over the roar. Gameplay information (how long the
## speed lasts): not gated on `Graphics.effects`. A plain radial gradient, as the
## beam's glow, so no shader and no extra pass beyond the one blended rect.

var _berserk_glow: TextureRect
var _berserk_shown := 0.0


func _update_berserk_glow(delta: float) -> void:
	if _player == null or _player.get("axe") == null:
		return
	if _berserk_glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.9, 0.05, 0.02, 0.0))
		g.set_color(1, Color(0.75, 0.02, 0.0, 0.6))
		g.add_point(0.5, Color(0.9, 0.05, 0.02, 0.0))
		g.add_point(0.8, Color(0.85, 0.06, 0.02, 0.35))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.05, 0.5)
		tex.width = 256
		tex.height = 256
		_berserk_glow = TextureRect.new()
		_berserk_glow.name = "BerserkGlow"
		_berserk_glow.texture = tex
		_berserk_glow.stretch_mode = TextureRect.STRETCH_SCALE
		_berserk_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		_berserk_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_berserk_glow.modulate.a = 0.0
		_berserk_glow.visible = false
		add_child(_berserk_glow)
		move_child(_berserk_glow, 0)
	var axe: Node = _player.get("axe")
	var want: float = axe.berserk_amount()
	_berserk_shown = move_toward(_berserk_shown, want, delta * (6.0 if want > _berserk_shown else 2.0))
	_berserk_glow.visible = _berserk_shown > 0.01
	if not _berserk_glow.visible:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var beat := fmod(t * 2.2, 1.0)
	var pulse := exp(-beat * beat / 0.01) + 0.6 * exp(-pow(beat - 0.3, 2.0) / 0.01)
	var roar := 0.35 if axe.is_roaring() else 0.0
	_berserk_glow.modulate.a = clampf(_berserk_shown * (0.7 + 0.25 * pulse) + roar, 0.0, 1.0)


func _build_dread() -> void:
	_blood = _full_screen_rect("Blood", "res://shaders/blood_screen.gdshader")
	(_blood.material as ShaderMaterial).set_shader_parameter("seed", randf() * 50.0)
	_slats = _full_screen_rect("HideSlats", "res://shaders/hide_slats.gdshader")


## A full-screen shader rect at the back of the HUD, drawn once at load so its
## shader is compiled before it is first needed, then hidden.
func _full_screen_rect(name_: String, shader: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = name_
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color.WHITE
	var material := ShaderMaterial.new()
	material.shader = load(shader)
	rect.material = material
	material.set_shader_parameter("opacity", 0.0)
	rect.set_meta("warming", true)
	add_child(rect)
	move_child(rect, 0)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if is_instance_valid(rect):
			rect.visible = false
			material.set_shader_parameter("opacity", 1.0)
			rect.remove_meta("warming"))
	return rect


func _update_dread(delta: float) -> void:
	if _player == null:
		return
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var hidden: bool = _player.has_method("is_hidden") and _player.is_hidden()
	if _slats != null and not _slats.has_meta("warming") and _slats.visible != hidden:
		_slats.visible = hidden
		(_slats.material as ShaderMaterial).set_shader_parameter("aspect", aspect)

	if _stalker == null or not is_instance_valid(_stalker):
		_stalker = get_tree().get_first_node_in_group("stalker") as Node3D
	var near := 0.0
	var hunted := false
	if _stalker != null and not _stalker.get("_dying"):
		var to: Vector3 = _stalker.global_position - (_player as Node3D).global_position
		near = 1.0 - smoothstep(CHILL_NEAR, CHILL_FAR, Vector2(to.x, to.z).length())
		# Co-op: hunted only if it is this player it is after (stalker.gd `_player`).
		hunted = _stalker.get("hunting") == true and (not Coop.active or _stalker.get("_player") == _player)
	# The torches go cold over about a second either way, never in a snap.
	_chill = move_toward(_chill, near, delta * 1.2)
	_hunted_shown = move_toward(_hunted_shown, 1.0 if hunted else 0.0,
		delta / (HUNT_IN if hunted else HUNT_OUT))
	# A scene may force the cold in faster and harder (the morgue's royal
	# sarcophagus): `ice_override` 0..1, eased by whoever sets it.
	torch_chill = maxf(_chill, ice_override)
	# Co-op: the torches are both players'; the colder of the two holds.
	var cold := torch_chill
	for h in Coop.huds():
		cold = maxf(cold, float(h.get("torch_chill")))
	Torch.chill = cold
	_apply_ice_grade(maxf(_hunted_shown, ice_override))
	if _player.has_method("set_remnant_hunt"):
		_player.set_remnant_hunt(_hunted_shown)


## The icy blue grade over the whole view while the Remnant hunts: a 1D colour
## correction LUT on the scene's environment, mapping each channel through a
## curve that holds red down and lifts blue (shadows most of all), blended in by
## `amount`. Removed outright at 0, so it costs nothing the rest of the time.
func _apply_ice_grade(amount: float) -> void:
	if absf(amount - _ice_applied) < 0.004:
		return
	_ice_applied = amount
	if _environment == null:
		# Co-op: this half's own Environment (split_screen.gd).
		var own: Camera3D = Coop.view_camera(_player) if Coop.active else null
		if own != null and own.environment != null:
			_environment = own.environment
		else:
			var world := get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
			if world == null or world.environment == null:
				return
			_environment = world.environment
	if amount <= 0.001:
		_environment.adjustment_color_correction = null
		return
	if _ice_gradient == null:
		_ice_gradient = Gradient.new()
		_ice_lut = GradientTexture1D.new()
		_ice_lut.width = 256
		_ice_lut.gradient = _ice_gradient
	var e := amount * amount * (3.0 - 2.0 * amount)
	_ice_gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	# Brightness kept about level (this level's light is mostly red, so cutting
	# red alone -- the first try, mid grey to 0.25/0.42/0.6 -- took the view
	# nearly to black); the colour shifts cold instead.
	_ice_gradient.colors = PackedColorArray([
		Color(0.0, 0.015, 0.05).lerp(Color(0.0, 0.0, 0.0), 1.0 - e),
		Color(0.45, 0.45, 0.45).lerp(Color(0.34, 0.47, 0.6), e),
		Color(1.0, 1.0, 1.0).lerp(Color(0.82, 0.95, 1.0), e)])
	_environment.adjustment_color_correction = _ice_lut


func _update_lunge_lines() -> void:
	if _lunge_lines == null or not _player.has_method("lunge_intensity"):
		return
	var strength: float = _player.lunge_intensity()
	if strength <= 0.0 or not Graphics.effects:
		if _lunge_lines.visible:
			_lunge_lines.visible = false
		return
	var material := _lunge_lines.material as ShaderMaterial
	_lunge_lines.visible = true
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("clock", _player.lunge_age())
	var size := get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


## A small countdown above the health bar while a potion is being drunk: it starts
## full and empties as the drink goes down.
func _build_drink_bar() -> void:
	_drink_box = VBoxContainer.new()
	_drink_box.name = "DrinkBar"
	_drink_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_drink_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_drink_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drink_box.offset_bottom = HEALTH_TOP - 34
	_drink_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_drink_box.add_theme_constant_override("separation", 3)
	_drink_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drink_box.visible = false
	add_child(_drink_box)
	var label := Label.new()
	label.text = "Drinking"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.86, 0.95, 0.86))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drink_box.add_child(label)
	_drink_bar = ProgressBar.new()
	_drink_bar.custom_minimum_size = Vector2(240, 8)
	_drink_bar.max_value = 1.0
	_drink_bar.step = 0.001
	_drink_bar.show_percentage = false
	_drink_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.03, 0.04, 0.03, 0.8)
	back.border_color = Color(0.0, 0.0, 0.0, 0.9)
	back.set_border_width_all(1)
	back.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.24, 0.85, 0.32)
	fill.set_corner_radius_all(2)
	_drink_bar.add_theme_stylebox_override("background", back)
	_drink_bar.add_theme_stylebox_override("fill", fill)
	_drink_box.add_child(_drink_bar)


func _update_drink_bar() -> void:
	if _drink_box == null or not _player.has_method("drink_remaining"):
		return
	var left: float = _player.drink_remaining()
	_drink_box.visible = left >= 0.0
	if left >= 0.0:
		_drink_bar.value = left


## (The hotbar this refreshed is gone; the wheels draw straight from the
## inventory each frame they are up.)
func _refresh_slots() -> void:
	pass


func _on_selection_changed(slot: int) -> void:
	_refresh_slots()
	var id: StringName = _player.inventory.id_at(slot)
	_held_label.text = "" if id == &"" else Inventory.item_name(id)
	if _held_tween != null and _held_tween.is_valid():
		_held_tween.kill()
	_held_label.modulate.a = 1.0
	_held_tween = create_tween()
	_held_tween.tween_interval(1.1)
	_held_tween.tween_property(_held_label, "modulate:a", 0.0, 0.4)


## Polled rather than signalled: a cooldown is a continuous value, and emitting
## it every frame would just be a signal pretending to be one.
func _process(delta: float) -> void:
	# Before the player guard: a frame counter that stops during a respawn, or
	# before the player has bound, is exactly the counter you wanted to read.
	_update_performance(delta)
	if _player == null:
		return
	var charge: float = _player.dodge_charge()
	dodge_bar.value = charge
	# The ghost bar: lit while a ghost can be started.
	var dash_ready: bool = _player.dodge_ready() if _player.has_method("dodge_ready") \
		else charge >= 1.0
	_dodge_fill.bg_color = dodge_ready_color if dash_ready else dodge_charging_color

	slam_bar.value = _player.slam_charge()
	_update_dash_streaks()
	_update_lunge_lines()
	_update_dread(delta)
	_update_blood(delta)
	_update_beam_glow(delta)
	_update_berserk_glow(delta)
	_update_damage_mark()

	_update_health_bars(delta)
	_update_boss_bar(delta)
	_update_hit_mark(delta)
	_update_interact_mark(delta)
	_update_drink_bar()


## The brackets close in while any prompt is up.
func _update_interact_mark(delta: float) -> void:
	var focus := Interact.focus(get_tree(), _player)
	var want := 1.0 if focus != null and not _player.in_cutscene and not _player.ui_open else 0.0
	if want == _interact_k:
		return
	_interact_k = move_toward(_interact_k, want, delta / maxf(interact_morph_time, 0.001))
	_interact_mark.queue_redraw()


## The ring always; the four corner brackets as `_interact_k` rises, closing in
## from a little further out as they fade up.
func _draw_interact_mark() -> void:
	_interact_mark.draw_arc(Vector2.ZERO, crosshair_radius, 0.0, TAU, 40, crosshair_color, 1.5, true)
	var k := _interact_k
	if k <= 0.0:
		return
	var e := k * k * (3.0 - 2.0 * k)
	var colour := Color(crosshair_color, crosshair_color.a * e)
	var reach := crosshair_radius + 4.0 + 4.0 * (1.0 - e)
	var arm := 4.0
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var corner := d * (reach * 0.7071 + 2.0)
		_interact_mark.draw_line(corner, corner - Vector2(d.x * arm, 0.0), colour, 1.5, true)
		_interact_mark.draw_line(corner, corner - Vector2(0.0, d.y * arm), colour, 1.5, true)


func _on_hit_landed(_target: Node3D) -> void:
	# Several bodies cut by one stroke land in the same frame; one pop is enough.
	_hit_mark_left = 1.0
	_hit_mark.visible = true
	_hit_mark.queue_redraw()


func _update_hit_mark(delta: float) -> void:
	if _hit_mark_left <= 0.0:
		return
	_hit_mark_left = maxf(_hit_mark_left - delta / maxf(hit_mark_time, 0.001), 0.0)
	_hit_mark.visible = _hit_mark_left > 0.0
	_hit_mark.queue_redraw()


func _draw_hit_mark() -> void:
	var k := _hit_mark_left
	# Pops straight out to full size, then drifts outward as it fades.
	var r0 := hit_mark_inner + hit_mark_spread * (1.0 - k)
	var colour := Color(hit_mark_color, hit_mark_color.a * k)
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var n := d.normalized()
		_hit_mark.draw_line(n * r0, n * (r0 + hit_mark_length), colour, 1.5, true)


## F3 toggles the readout, so it can be left on while playing and taken away
## for a clean look at the level.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		show_performance = not show_performance
		perf_panel.visible = show_performance
		get_viewport().set_input_as_handled()


## Streaks racing past the edges while the player is dashing. Driven from the
## player's own dash clock rather than a separate timer here, so the streaks
## cannot drift out of step with the view punch.
##
## Hidden outright at rest: this is a full-screen rect, and leaving it up at
## zero alpha would still cost a screen's worth of fill every frame.
func _update_dash_streaks() -> void:
	if not _player.has_method("dash_intensity"):
		return
	var intensity: float = _player.dash_intensity()
	if intensity <= 0.0:
		if dash_streaks.visible:
			dash_streaks.visible = false
		return

	var material := dash_streaks.material as ShaderMaterial
	if material == null:
		return
	dash_streaks.visible = true
	# Eased the same way the view punch is, so they rise and fall together.
	material.set_shader_parameter("strength",
		intensity * intensity * _player.dash_streak_strength)
	# The world slides opposite to the way you went, so the streaks pile up on
	# the side you are dashing away from.
	material.set_shader_parameter("lean",
		Vector2(-_player.dash_lateral(), 0.0))
	var size := get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


## A red arc at the rim pointing back at whatever just hit you, sized and lit
## by how hard the hit was. Hidden between hits, so it costs nothing the rest
## of the time.
func _update_damage_mark() -> void:
	if not _player.has_method("damage_mark"):
		return
	var mark: float = _player.damage_mark()
	if mark <= 0.0:
		if damage_mark.visible:
			damage_mark.visible = false
		return

	var material := damage_mark.material as ShaderMaterial
	if material == null:
		return
	damage_mark.visible = true
	var severity: float = _player.damage_severity()
	# Squared, so it flares on impact and thins out rather than dimming evenly.
	material.set_shader_parameter("strength",
		mark * mark * severity * _player.damage_mark_strength)
	material.set_shader_parameter("bearing", _player.damage_bearing())
	material.set_shader_parameter("spread", deg_to_rad(lerpf(
		_player.damage_mark_spread_min, _player.damage_mark_spread_max, severity)))
	var size := get_viewport().get_visible_rect().size
	material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))


## Big centred text with a smaller line under it. Found through the "hud"
## group, so nothing in the level has to hold a reference to this node.
## `subtitle` may be empty, in which case only the headline shows.
func announce(title: String, subtitle := "") -> void:
	banner_title.text = title
	banner_sub.text = subtitle
	banner_sub.visible = subtitle != ""

	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "modulate:a", 1.0, banner_fade_in) \
		.set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(banner_hold)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, banner_fade_out) \
		.set_ease(Tween.EASE_IN)


func _update_performance(delta: float) -> void:
	if not show_performance:
		return
	_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)
	_perf_left -= delta
	if _perf_left > 0.0:
		return
	_perf_left = perf_interval

	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var drawn := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var script_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	perf_label.text = "\n".join([
		"%d FPS      worst %.1f ms" % [roundi(fps), _worst_frame_ms],
		"drawn   %d" % roundi(drawn),
		"calls   %d" % roundi(calls),
		"script  %.2f ms" % script_ms,
		"physics %.2f ms" % physics_ms,
	])
	_worst_frame_ms = 0.0


## Two stacked bars, back to front (the yellow "rally" bar behind them is
## hidden: hitting back no longer wins health back, 2026-10-03):
##   green   health          -- the true value, exposed while the red climbs
##   red     _shown_health   -- snaps down on damage, eases up on healing
func _update_health_bars(delta: float) -> void:
	var current: float = _player.health
	var maximum: float = _player.max_health
	if _shown_health < 0.0:
		_shown_health = current
		_last_health = current

	if current > _last_health:
		# Fresh healing: hold the green, then time the climb to the whole gap so
		# even a small gain is on screen long enough to read.
		_gain_hold_left = gain_hold
		_gain_rate = (current - _shown_health) / maxf(gain_climb_time, 0.01)
	_last_health = current

	if current < _shown_health:
		# Damage reads instantly.
		_shown_health = current
		_gain_hold_left = 0.0
	elif current > _shown_health:
		if _gain_hold_left > 0.0:
			_gain_hold_left -= delta
		else:
			_shown_health = minf(_shown_health + _gain_rate * delta, current)

	for b in [gain_bar, bar]:
		b.max_value = maximum
	rally_bar.visible = false
	gain_bar.value = current
	bar.value = _shown_health


## The boss is spawned after the navmesh bake, and replaced whenever the world
## resets, so it is looked up lazily rather than bound once.
## Any big enemy currently hunting the player gets the bar: the Warden, or the
## mimic once it has sprung. Whichever is engaged wins; the Warden takes
## precedence if somehow both are.
func _engaged_champion() -> Node:
	for group in ["boss", "mimic"]:
		for node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and node.get("engaged"):
				return node
	return null


func _update_boss_bar(delta: float) -> void:
	var champion := _engaged_champion()
	if champion == null:
		boss_group.visible = false
		_boss = null
		return
	if champion != _boss:
		_boss = champion
		boss_bar.max_value = _boss.max_health
		boss_trail_bar.max_value = _boss.max_health
		_boss_trail = _boss.health
		_boss_last_health = _boss.health
		_boss_hold_left = 0.0
		var title: Variant = _boss.get("display_name")
		boss_title = str(title) if title != null else boss_title

	boss_group.visible = true

	var current: float = _boss.health
	if current < _boss_last_health:
		# Fresh damage: restart the hold so the yellow lingers where it was.
		_boss_hold_left = boss_trail_hold
	_boss_last_health = current

	if current > _boss_trail:
		_boss_trail = current
	elif current < _boss_trail:
		if _boss_hold_left > 0.0:
			_boss_hold_left -= delta
		else:
			var rate: float = _boss.max_health if boss_trail_drain <= 0.0 \
				else (_boss.max_health / boss_trail_drain)
			_boss_trail = maxf(_boss_trail - rate * delta, current)

	boss_bar.value = current
	boss_trail_bar.value = _boss_trail
	boss_label.text = "%s      %d / %d%s" % [
		boss_title, roundi(current), roundi(_boss.max_health), _poise_readout(),
	]


## Drives the poise strip under the health bar and returns the suffix the boss
## label wants. Read by polling rather than signals, because the champion is
## swapped out whenever the world resets.
func _poise_readout() -> String:
	var total: Variant = _boss.get("max_poise")
	var capacity := 0.0 if total == null else float(total)
	poise_bar.visible = capacity > 0.0
	if capacity <= 0.0:
		return ""

	var broken: bool = _boss.has_method("is_staggered") and _boss.is_staggered()
	poise_bar.max_value = capacity
	# Shows poise damage dealt rather than poise remaining, so the bar fills
	# toward the stagger instead of draining toward it. A bar that empties as
	# you win reads as losing ground, which is the opposite of what is happening.
	poise_bar.value = capacity if broken else capacity - float(_boss.get("poise"))
	_poise_fill.bg_color = poise_broken_color if broken else poise_color
	return "      STAGGERED" if broken else ""


## The bar values themselves are driven by _update_health_bars each frame; this
## only handles the readout and the low-health colour.
func _on_health_changed(current: float, maximum: float) -> void:
	label.text = "%d / %d" % [roundi(current), roundi(maximum)]
	var fraction := current / maximum if maximum > 0.0 else 0.0
	_fill.bg_color = low_color if fraction <= low_health_fraction else normal_color


func _on_healed(amount: float, source_name: String) -> void:
	if source_name.is_empty():
		_show_toast("+%d health" % roundi(amount))
	else:
		_show_toast("Used %s  +%d" % [source_name, roundi(amount)])


func _on_consumable_gained(type: ConsumableType, amount: int) -> void:
	_show_toast("Found %s  x%d" % [type.item_name, amount])


func _on_died() -> void:
	_show_toast("You died", 2.0)


func _show_toast(text: String, hold := 1.2) -> void:
	toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(hold)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.45)
