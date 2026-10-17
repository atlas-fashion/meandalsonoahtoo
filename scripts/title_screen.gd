extends Control

## The title screen (2026-10-09), the game's main scene: Play, Settings, Quit.
##
## Play opens the four save slots. An empty slot asks for a name and starts a
## new game there; a used one shows its name, its zone and when it was saved,
## carries on from its save (Saves.start), and can be deleted. The
## settings page is the shared SettingsPanel, the same one the pause menu shows.
##
## `--bench` or `--skip-title` after `--` go straight into a game with no slot,
## so the benchmark and quick runs still land in the level and never write a
## save.

const GOLD := Color(0.93, 0.80, 0.62)
const DIM := Color(0.62, 0.56, 0.5)
const BLOOD := Color(0.45, 0.2, 0.18)
## Seconds "DESCENDING..." is shown, then to fade it to black.
const LOADING_HOLD := 0.7
const LOADING_FADE := 1.0

var _serif: Font
var _main: Control
var _slots: Control
var _slot_rows: VBoxContainer
var _settings: SettingsPanel
var _naming: Control
var _name_edit: LineEdit
var _name_slot := -1
var _loading: Label
var _confirm: ConfirmationDialog
var _delete_slot := -1
var _embers: CPUParticles2D
var _time := 0.0
var _title: Label


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# `-- --sandbox`: straight into the sandbox (sandbox.gd).
	if args.has("--sandbox"):
		Sandbox.start.call_deferred()
		return
	if args.has("--bench") or args.has("--skip-title"):
		Saves.slot = -1
		Saves.pending = {}
		get_tree().change_scene_to_file.call_deferred(Saves.GAME_SCENE)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
	_serif = serif
	_build()
	_show(&"main")


func _process(delta: float) -> void:
	_time += delta
	if _title != null:
		# A slow breath of light through the title.
		var k := 0.5 + 0.5 * sin(_time * 0.9)
		_title.add_theme_color_override("font_color", GOLD.lerp(Color(1.0, 0.88, 0.7), k * 0.35))


## In `_input`: a focused button (for the pad) would take "ui_cancel" first.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _main.visible and not _loading.visible:
		get_viewport().set_input_as_handled()
		_show(&"slots" if _naming.visible else &"main")


func _begin_named() -> void:
	if _name_slot >= 0:
		_play(_name_slot, _name_edit.text)


func _show(page: StringName) -> void:
	_main.visible = page == &"main"
	_slots.visible = page == &"slots"
	_settings.visible = page == &"settings"
	_naming.visible = false
	if page == &"slots":
		_fill_slots()
	elif page == &"settings":
		_settings.sync()
	# A pad needs something focused to move from (the mouse ignores focus).
	var shown: Control = _main if page == &"main" else (_slots if page == &"slots" else _settings)
	_focus_first.call_deferred(shown)


func _focus_first(page: Control) -> void:
	for b in page.find_children("*", "Button", true, false):
		var button := b as Button
		if button.is_visible_in_tree() and not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return


# --- Building --------------------------------------------------------------------

func _build() -> void:
	# A dark, blood-lit backdrop: near black, warmer toward the bottom, with
	# embers drifting up through it.
	var back := ColorRect.new()
	back.color = Color(0.025, 0.018, 0.02)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.38, 0.05, 0.03, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.15, 1.15)
	tex.width = 256
	tex.height = 256
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	var floor_glow := TextureRect.new()
	var g2 := Gradient.new()
	g2.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	g2.set_color(1, Color(0.5, 0.12, 0.04, 0.35))
	var t2 := GradientTexture2D.new()
	t2.gradient = g2
	t2.fill_from = Vector2(0.5, 0.0)
	t2.fill_to = Vector2(0.5, 1.0)
	floor_glow.texture = t2
	floor_glow.stretch_mode = TextureRect.STRETCH_SCALE
	floor_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	floor_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	floor_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_glow)
	_embers = CPUParticles2D.new()
	_embers.amount = 70
	_embers.lifetime = 7.0
	_embers.preprocess = 7.0
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(700.0, 10.0)
	_embers.direction = Vector2(0.0, -1.0)
	_embers.spread = 25.0
	_embers.gravity = Vector2(0.0, -6.0)
	_embers.initial_velocity_min = 18.0
	_embers.initial_velocity_max = 55.0
	_embers.scale_amount_min = 1.0
	_embers.scale_amount_max = 2.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.55, 0.2, 0.0))
	ramp.set_color(1, Color(0.8, 0.15, 0.05, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.6, 0.25, 0.9))
	ramp.add_point(0.7, Color(0.9, 0.25, 0.08, 0.5))
	_embers.color_ramp = ramp
	add_child(_embers)
	resized.connect(_place_embers)
	_place_embers()

	# The main page.
	_main = _page()
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	_main.add_child(col)
	_title = Label.new()
	_title.text = String(ProjectSettings.get_setting("application/config/name", "")).to_upper()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", _spaced(18))
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", GOLD)
	_title.add_theme_color_override("font_shadow_color", Color(0.5, 0.05, 0.02, 0.8))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.add_theme_constant_override("shadow_outline_size", 10)
	col.add_child(_title)
	var rule := ColorRect.new()
	rule.color = BLOOD
	rule.custom_minimum_size = Vector2(360, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(rule)
	col.add_child(SettingsPanel.spacer(30))
	for entry in [["Play", func() -> void: _show(&"slots")],
			["Sandbox", func() -> void: _play_sandbox()],
			["Settings", func() -> void: _show(&"settings")],
			["Quit", func() -> void: get_tree().quit()]]:
		col.add_child(_big_button(entry[0], entry[1]))

	# The slots.
	_slots = _page()
	var box := SettingsPanel.panel_box(_slots, 620)
	var head := SettingsPanel.title_label("CHOOSE A SAVE")
	head.add_theme_font_override("font", _spaced(6))
	box.add_child(head)
	box.add_child(SettingsPanel.dim_label("The game saves itself every minute. Save by hand from the pause menu."))
	box.add_child(SettingsPanel.spacer(6))
	_slot_rows = VBoxContainer.new()
	_slot_rows.add_theme_constant_override("separation", 10)
	box.add_child(_slot_rows)
	box.add_child(SettingsPanel.spacer(6))
	box.add_child(SettingsPanel.menu_button("Back", func() -> void: _show(&"main")))

	# Naming a new game.
	_naming = _page()
	var nbox := SettingsPanel.panel_box(_naming, 460)
	var nhead := SettingsPanel.title_label("NAME YOUR GAME")
	nhead.add_theme_font_override("font", _spaced(6))
	nbox.add_child(nhead)
	nbox.add_child(SettingsPanel.spacer(6))
	_name_edit = LineEdit.new()
	_name_edit.max_length = Saves.NAME_MAX
	_name_edit.custom_minimum_size.y = 44
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.text_submitted.connect(func(_t: String) -> void: _begin_named())
	# On a pad, the on-screen keyboard comes up when it takes focus (pad.gd);
	# its Done submits, which begins the game.
	Pad.attach_keyboard(_name_edit)
	nbox.add_child(_name_edit)
	nbox.add_child(SettingsPanel.spacer(6))
	var nrow := HBoxContainer.new()
	nrow.add_child(SettingsPanel.menu_button("Back", func() -> void: _show(&"slots"), 150))
	nrow.add_child(SettingsPanel.menu_button("Begin", _begin_named, 150))
	nbox.add_child(nrow)

	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.back_pressed.connect(func() -> void: _show(&"main"))

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete save"
	_confirm.ok_button_text = "Delete"
	_confirm.confirmed.connect(func() -> void:
		if _delete_slot >= 0:
			Saves.erase(_delete_slot)
		_delete_slot = -1
		_fill_slots())
	add_child(_confirm)

	_loading = Label.new()
	_loading.text = "DESCENDING..."
	_loading.add_theme_font_override("font", _spaced(10))
	_loading.add_theme_font_size_override("font_size", 28)
	_loading.add_theme_color_override("font_color", GOLD)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	add_child(_loading)


func _place_embers() -> void:
	_embers.position = Vector2(size.x * 0.5, size.y + 10.0)
	_embers.emission_rect_extents = Vector2(size.x * 0.55, 10.0)


func _page() -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _spaced(spacing: int) -> Font:
	var f := FontVariation.new()
	f.base_font = _serif
	f.spacing_glyph = spacing
	return f


func _big_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(300, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", _spaced(6))
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", Color(0.85, 0.78, 0.68))
	b.add_theme_color_override("font_hover_color", GOLD)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.04, 0.045, 0.75)
	normal.border_color = Color(0.32, 0.14, 0.12)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.05, 0.04, 0.9)
	hover.border_color = Color(0.7, 0.32, 0.22)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(action)
	return b


# --- The slots ---------------------------------------------------------------------

func _fill_slots() -> void:
	for child in _slot_rows.get_children():
		child.queue_free()
	for i in Saves.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var meta: Dictionary = Saves.summary(i)
		var card := Button.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.y = 64
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_theme_font_size_override("font_size", 16)
		# Its name, the zone, when -- never how far the game has got.
		if meta.is_empty():
			card.text = "  Slot %d        Empty  -  begin a new game" % (i + 1)
			card.pressed.connect(_ask_name.bind(i))
		else:
			card.text = "  %s\n  %s        Saved %s" % [String(meta.get("name", "Game %d" % (i + 1))),
				String(meta.get("zone_name", "Zone 1")), String(meta.get("saved_at", "")).replace("T", "  ")]
			card.pressed.connect(_play.bind(i))
		row.add_child(card)
		var del := Button.new()
		del.text = "Delete"
		del.custom_minimum_size = Vector2(90, 64)
		del.disabled = meta.is_empty()
		del.pressed.connect(func() -> void:
			_delete_slot = i
			_confirm.dialog_text = "Delete the save in slot %d? This cannot be undone." % (i + 1)
			_confirm.popup_centered())
		row.add_child(del)
		_slot_rows.add_child(row)


## A new game: name it first.
func _ask_name(i: int) -> void:
	_name_slot = i
	_name_edit.text = ""
	_name_edit.placeholder_text = "Game %d" % (i + 1)
	_slots.visible = false
	_naming.visible = true
	_name_edit.grab_focus()


func _play(i: int, new_name := "") -> void:
	await _descend()
	Saves.start(i, new_name)


## The SANDBOX (sandbox.gd): the same descent, into an empty level and a flat
## test plane, with nothing ever saved.
func _play_sandbox() -> void:
	await _descend()
	Sandbox.start()


## "DESCENDING...", then the whole screen fades to black; the game picks up in
## that black (hud.gd) and the player gets up out of it.
func _descend() -> void:
	_main.visible = false
	_slots.visible = false
	_settings.visible = false
	_naming.visible = false
	_loading.visible = true
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.modulate.a = 0.0
	add_child(black)
	var t := create_tween()
	t.tween_interval(LOADING_HOLD)
	t.tween_property(black, "modulate:a", 1.0, LOADING_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	# One frame drawn fully black before the level's build stalls the window.
	await get_tree().process_frame
	await get_tree().process_frame
