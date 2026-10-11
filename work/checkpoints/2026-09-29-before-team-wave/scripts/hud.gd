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
@export var shockwave_ready_color := Color(0.847059, 0.65098, 0.298039)
@export var shockwave_charging_color := Color(0.380392, 0.341176, 0.266667)
@export var count_color := Color(0.929412, 0.941176, 0.952941)
## Used for the count once the stack cannot take any more.
@export var count_full_color := Color(0.427451, 0.898039, 0.478431)

@onready var bar: ProgressBar = $HealthGroup/HealthStack/HealthBar
## Sits behind the health bar and extends past it, so the difference between
## the two shows as the yellow stretch of still-recoverable damage.
@onready var rally_bar: ProgressBar = $HealthGroup/HealthStack/RallyBar
## Sits between them at the true health value. When health rises the red bar
## eases up to meet it, and the gap shows as a green flash of health gained.
@onready var gain_bar: ProgressBar = $HealthGroup/HealthStack/GainBar
@onready var label: Label = $HealthGroup/HealthLabel
@onready var dodge_bar: ProgressBar = $HealthGroup/DodgeBar
@onready var shockwave_bar: ProgressBar = $HealthGroup/ShockwaveBar
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
var _wave_fill: StyleBoxFlat
var _poise_fill: StyleBoxFlat
var _toast_tween: Tween
var _player: Node
## One entry per inventory slot: the count label and the panel to dim.
var _slot_counts: Array[Label] = []
var _slot_panels: Array[PanelContainer] = []
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


func _ready() -> void:
	toast.modulate.a = 0.0
	# Duplicate so recolouring the fill does not mutate the shared stylebox.
	_fill = (bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	bar.add_theme_stylebox_override("fill", _fill)
	_dodge_fill = (dodge_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	dodge_bar.add_theme_stylebox_override("fill", _dodge_fill)
	_wave_fill = (shockwave_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	shockwave_bar.add_theme_stylebox_override("fill", _wave_fill)
	_poise_fill = (poise_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	poise_bar.add_theme_stylebox_override("fill", _poise_fill)
	perf_panel.visible = show_performance
	banner.modulate.a = 0.0
	# Deferred so the player is guaranteed to be in its group already.
	_bind_player.call_deferred()


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_warning("HUD found no node in the 'player' group; it will not update.")
		return

	_player.health_changed.connect(_on_health_changed)
	_player.healed.connect(_on_healed)
	_player.died.connect(_on_died)
	_player.inventory_changed.connect(_refresh_slots)
	_player.consumable_gained.connect(_on_consumable_gained)

	_build_slots()
	_on_health_changed(_player.health, _player.max_health)
	_refresh_slots()


## Slots are generated from the player's `consumables`, so adding a type there
## gives it a slot and a hotkey label without touching this scene.
func _build_slots() -> void:
	for child in slots_box.get_children():
		child.queue_free()
	_slot_counts.clear()
	_slot_panels.clear()

	for slot in _player.consumables.size():
		var type: ConsumableType = _player.consumables[slot]
		if type == null:
			continue

		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(108, 0)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.0784314, 0.0862745, 0.101961, 0.75)
		box.border_color = type.color
		box.border_width_left = 3
		box.set_corner_radius_all(4)
		box.content_margin_left = 8
		box.content_margin_right = 8
		box.content_margin_top = 5
		box.content_margin_bottom = 5
		panel.add_theme_stylebox_override("panel", box)

		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 1)

		var name_label := Label.new()
		name_label.text = "%d  %s" % [slot + 1, type.item_name]
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", type.color)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		var heal_label := Label.new()
		heal_label.text = "+%d hp" % roundi(type.heal_amount)
		heal_label.add_theme_font_size_override("font_size", 11)
		heal_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.72))

		var count_label := Label.new()
		count_label.add_theme_font_size_override("font_size", 17)
		count_label.add_theme_color_override("font_color", count_color)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		column.add_child(name_label)
		column.add_child(heal_label)
		column.add_child(count_label)
		panel.add_child(column)
		slots_box.add_child(panel)

		_slot_panels.append(panel)
		_slot_counts.append(count_label)


func _refresh_slots() -> void:
	for slot in _slot_counts.size():
		var count: int = _player.counts[slot] if slot < _player.counts.size() else 0
		var full: bool = count >= _player.max_stack
		# Says so outright rather than leaving you to remember the cap.
		_slot_counts[slot].text = ("x%d  FULL" % count) if full else ("x%d" % count)
		_slot_counts[slot].add_theme_color_override(
			"font_color", count_full_color if full else count_color
		)
		# Empty slots stay visible so the hotkey is still discoverable.
		_slot_panels[slot].modulate.a = 1.0 if count > 0 else 0.4


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
	# Ready as soon as one whole charge is banked, which is half a bar -- not
	# only when the pool is full.
	var dash_ready: bool = _player.dodge_ready() if _player.has_method("dodge_ready") \
		else charge >= 1.0
	_dodge_fill.bg_color = dodge_ready_color if dash_ready else dodge_charging_color

	var wave: float = _player.shockwave_charge()
	shockwave_bar.value = wave
	_wave_fill.bg_color = shockwave_ready_color if wave >= 1.0 else shockwave_charging_color

	slam_bar.value = _player.slam_charge()
	_update_dash_streaks()
	_update_damage_mark()

	_update_health_bars(delta)
	_update_boss_bar(delta)


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


## Three stacked bars, back to front:
##   yellow  health + rally  -- what was lost but is still winnable back
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
		# Damage reads instantly; the yellow behind it carries the history.
		_shown_health = current
		_gain_hold_left = 0.0
	elif current > _shown_health:
		if _gain_hold_left > 0.0:
			_gain_hold_left -= delta
		else:
			_shown_health = minf(_shown_health + _gain_rate * delta, current)

	for b in [rally_bar, gain_bar, bar]:
		b.max_value = maximum
	rally_bar.value = current + _player.rally_health
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
