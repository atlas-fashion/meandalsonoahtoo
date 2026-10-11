extends CanvasLayer

## Escape brings this up. Runs with PROCESS_MODE_ALWAYS so it still gets input
## while the rest of the tree is frozen.
##
## The controls are generated from SPEC rather than laid out by hand, so adding
## a quality setting is one line here and one property on the Graphics autoload.

const ROW_HEIGHT := 30

## Every settings row. `key` names a property on the Graphics autoload.
const SPEC := [
	{"key": "render_scale", "label": "Resolution scale", "type": "slider",
		"min": 0.4, "max": 1.0, "step": 0.05, "suffix": "%", "mul": 100.0,
		"hint": "Renders the 3D scene smaller and scales it up. The biggest single win."},
	{"key": "msaa", "label": "Anti-aliasing", "type": "option",
		"choices": [["Off (FXAA)", 0], ["2x MSAA", 1], ["4x MSAA", 2]],
		"hint": "MSAA is per-pixel and expensive. FXAA is nearly free."},
	{"key": "shadows", "label": "Shadows", "type": "option",
		"choices": [["Off", 0], ["Hard", 1], ["Soft", 2]],
		"hint": "Your torch is the only shadow caster, and it redraws the scene every frame."},
	{"key": "shadow_atlas", "label": "Shadow resolution", "type": "option",
		"choices": [["256", 256], ["512", 512], ["1024", 1024], ["2048", 2048], ["4096", 4096]]},
	{"key": "ssao", "label": "Ambient occlusion", "type": "check",
		"hint": "A full-screen pass. Costly for what it adds in a dark maze."},
	{"key": "glow", "label": "Bloom", "type": "check"},
	{"key": "fog", "label": "Fog", "type": "check"},
	{"key": "effects", "label": "Impact effects", "type": "check",
		"hint": "Death bursts and flourishes."},
	{"key": "texture_detail", "label": "Texture detail", "type": "option",
		"choices": [["Untextured", 0], ["No triplanar", 1], ["Full", 2]],
		"hint": "Triplanar mapping samples each texture three times per pixel."},
	{"key": "light_detail", "label": "Light detail", "type": "slider",
		"min": 0.4, "max": 1.25, "step": 0.05, "suffix": "%", "mul": 100.0},
	{"key": "view_distance", "label": "View distance", "type": "slider",
		"min": 0.4, "max": 1.25, "step": 0.05, "suffix": "%", "mul": 100.0},
	{"key": "lod_threshold", "label": "Mesh LOD bias", "type": "slider",
		"min": 1.0, "max": 8.0, "step": 0.5, "suffix": " px", "mul": 1.0},
	{"key": "anim_quality", "label": "Animation detail", "type": "option",
		"choices": [["Nearby only", 0], ["Reduced at range", 1], ["Full", 2]],
		"hint": "Distant skeletons pose less often. They still move, just coarser."},
	{"key": "npc_detail", "label": "Enemy simulation range", "type": "slider",
		"min": 0.4, "max": 1.25, "step": 0.05, "suffix": "%", "mul": 100.0},
	{"key": "vsync", "label": "V-Sync", "type": "check"},
	{"key": "fps_cap", "label": "Frame rate cap", "type": "option",
		"choices": [["Unlimited", 0], ["30", 30], ["60", 60], ["120", 120]]},
]

var _root_panel: Control
var _settings_panel: Control
var _preset_picker: OptionButton
var _readout: Label
var _hint: Label
var _widgets := {}
var _syncing := false
var _debounce: Timer
var _was_captured := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_build()
	visible = false

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.18
	_debounce.process_mode = Node.PROCESS_MODE_ALWAYS
	_debounce.timeout.connect(func() -> void:
		Graphics.mark_custom()
		_sync())
	add_child(_debounce)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if not visible:
		_open()
	elif _settings_panel.visible:
		_show_page(false)
	else:
		_close()


func _process(_delta: float) -> void:
	if visible and _settings_panel.visible:
		_readout.text = "%d FPS   %.1f ms   %d draw calls   %s preset" % [
			Engine.get_frames_per_second(),
			1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Graphics.preset_name(),
		]


func _open() -> void:
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_page(false)
	_sync()


func _close() -> void:
	visible = false
	get_tree().paused = false
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_page(settings: bool) -> void:
	_root_panel.visible = not settings
	_settings_panel.visible = settings


# ---------------------------------------------------------------------------
# construction
# ---------------------------------------------------------------------------
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ColorRect blocks the mouse by default, which is exactly what a modal wants.
	add_child(dim)

	_root_panel = _centred()
	add_child(_root_panel)
	var menu := _panel_box(_root_panel)
	menu.add_child(_title("PAUSED"))
	menu.add_child(_spacer(10))
	menu.add_child(_menu_button("Resume", _close))
	menu.add_child(_menu_button("Graphics settings", func() -> void: _show_page(true)))
	menu.add_child(_menu_button("Quit to desktop", func() -> void: get_tree().quit()))
	menu.add_child(_spacer(6))
	menu.add_child(_dim_label("Esc closes this menu"))

	_settings_panel = _centred()
	add_child(_settings_panel)
	var box := _panel_box(_settings_panel, 640)
	box.add_child(_title("GRAPHICS"))

	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 14)
	_readout.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	box.add_child(_readout)
	box.add_child(_spacer(6))

	var preset_row := HBoxContainer.new()
	var pl := Label.new()
	pl.text = "Quality preset"
	pl.custom_minimum_size.x = 210
	preset_row.add_child(pl)
	_preset_picker = OptionButton.new()
	_preset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in Graphics.PRESET_NAMES.size():
		_preset_picker.add_item(Graphics.PRESET_NAMES[i], i)
	_preset_picker.item_selected.connect(func(idx: int) -> void:
		if _syncing:
			return
		if idx == Graphics.Preset.CUSTOM:
			_sync()
			return
		Graphics.set_preset(idx)
		_sync())
	preset_row.add_child(_preset_picker)
	box.add_child(preset_row)
	box.add_child(_spacer(4))
	box.add_child(_rule())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 360
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	box.add_child(scroll)
	for entry in SPEC:
		rows.add_child(_row(entry))

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.y = 34
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	box.add_child(_hint)

	box.add_child(_rule())
	var buttons := HBoxContainer.new()
	buttons.add_child(_menu_button("Back", func() -> void: _show_page(false), 150))
	buttons.add_child(_menu_button("Resume", _close, 150))
	box.add_child(buttons)
	_settings_panel.visible = false


func _row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var label := Label.new()
	label.text = entry["label"]
	label.custom_minimum_size.x = 210
	row.add_child(label)

	var key: String = entry["key"]
	match entry["type"]:
		"slider":
			var holder := HBoxContainer.new()
			holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var slider := HSlider.new()
			slider.min_value = entry["min"]
			slider.max_value = entry["max"]
			slider.step = entry["step"]
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var value := Label.new()
			value.custom_minimum_size.x = 64
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			slider.value_changed.connect(func(v: float) -> void:
				value.text = "%d%s" % [roundi(v * entry["mul"]), entry["suffix"]]
				if _syncing:
					return
				Graphics.set(key, v)
				# Dragging fires continuously and every apply walks the whole
				# level, so the work waits until the drag settles.
				_debounce.start())
			holder.add_child(slider)
			holder.add_child(value)
			row.add_child(holder)
			_widgets[key] = slider
		"option":
			var picker := OptionButton.new()
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for choice in entry["choices"]:
				picker.add_item(choice[0])
				picker.set_item_metadata(picker.item_count - 1, choice[1])
			picker.item_selected.connect(func(idx: int) -> void:
				if _syncing:
					return
				Graphics.set(key, picker.get_item_metadata(idx))
				_debounce.start())
			row.add_child(picker)
			_widgets[key] = picker
		"check":
			var check := CheckButton.new()
			check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			check.toggled.connect(func(on: bool) -> void:
				if _syncing:
					return
				Graphics.set(key, on)
				_debounce.start())
			row.add_child(check)
			_widgets[key] = check

	if entry.has("hint"):
		row.mouse_entered.connect(func() -> void: _hint.text = entry["hint"])
		row.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


## Pushes the Graphics values back into the widgets. Guarded, because assigning
## a widget's value fires its own signal and would otherwise look like the
## player had just edited it -- which would flip the preset to Custom.
func _sync() -> void:
	_syncing = true
	_preset_picker.select(Graphics.preset)
	for entry in SPEC:
		var key: String = entry["key"]
		var w: Control = _widgets.get(key)
		if w == null:
			continue
		var v = Graphics.get(key)
		if w is HSlider:
			(w as HSlider).value = v
		elif w is OptionButton:
			var picker := w as OptionButton
			for i in picker.item_count:
				if picker.get_item_metadata(i) == v:
					picker.select(i)
					break
		elif w is CheckButton:
			(w as CheckButton).button_pressed = v
	_syncing = false


# ---------------------------------------------------------------------------
# small builders
# ---------------------------------------------------------------------------
func _centred() -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _panel_box(parent: Control, width := 360) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.96)
	style.border_color = Color(0.45, 0.20, 0.18)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = width
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(0.93, 0.80, 0.62))
	return l


func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.6, 0.56, 0.52))
	return l


func _menu_button(text: String, action: Callable, width := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(0.35, 0.22, 0.20, 0.8)
	r.custom_minimum_size.y = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
