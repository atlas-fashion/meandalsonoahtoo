class_name SettingsPanel
extends CenterContainer

## The settings page, shared by the pause menu and the title screen
## (2026-10-09): CONTROLS (mouse sensitivity) and GRAPHICS (the preset and
## every quality knob, generated from SPEC). Moved out of pause_menu.gd so both
## menus show exactly the same page.
##
## Graphics rows are generated from SPEC rather than laid out by hand, so adding
## a quality setting is one line here and one property on the Graphics autoload.
## Sensitivity is not a quality setting: moving it never flips the preset to
## Custom (`Graphics.set_mouse_sensitivity`).

signal back_pressed

const ROW_HEIGHT := 30

## Every graphics row. `key` names a property on the Graphics autoload.
const SPEC := [
	{"key": "render_scale", "label": "Resolution scale", "type": "slider",
		"min": 0.4, "max": 1.0, "step": 0.05, "suffix": "%", "mul": 100.0,
		"hint": "Renders the 3D scene smaller and scales it up. The biggest single win."},
	{"key": "msaa", "label": "Anti-aliasing", "type": "option",
		"choices": [["Off (FXAA)", 0], ["2x MSAA", 1], ["4x MSAA", 2]],
		"hint": "MSAA is per-pixel and expensive. FXAA is nearly free."},
	{"key": "shadows", "label": "Shadows", "type": "option",
		"choices": [["Off", 0], ["Hard", 1], ["Soft", 2]],
		"hint": "Wall torches cast shadows near you. Hard is cheaper: two passes a torch, not six."},
	{"key": "shadow_atlas", "label": "Shadow resolution", "type": "option",
		"choices": [["256", 256], ["512", 512], ["1024", 1024], ["2048", 2048], ["4096", 4096]]},
	{"key": "torch_lights", "label": "Lit torches", "type": "slider",
		"min": 4.0, "max": 20.0, "step": 1.0, "suffix": "", "mul": 1.0,
		"hint": "How many torches near you give light. Each casts a shadow, so none lights through a wall."},
	{"key": "coop_torch_share", "label": "Co-op lit torches", "type": "slider",
		"min": 0.25, "max": 1.0, "step": 0.05, "suffix": "%", "mul": 100.0,
		"hint": "Split-screen only: the share of the lit torches. Each half draws its own torch shadows; half is about 1 ms cheaper."},
	{"key": "ssao", "label": "Ambient occlusion", "type": "check",
		"hint": "A full-screen pass. Costly for what it adds in a dark maze."},
	{"key": "glow", "label": "Bloom", "type": "check"},
	{"key": "fog", "label": "Fog", "type": "check",
		"hint": "Distance fog: nothing is seen past about 60 m, and nothing past it is drawn. Free."},
	{"key": "volumetric_fog", "label": "Volumetric mist", "type": "option",
		"choices": [["Off", 0], ["On", 1], ["Fine", 2]],
		"hint": "Mist the torches glow in and the moon shafts through. Needs Fog on."},
	{"key": "effects", "label": "Impact effects", "type": "check",
		"hint": "Death bursts and flourishes."},
	{"key": "damp", "label": "Damp floors and drips", "type": "check",
		"hint": "Wet patches on the floor that catch the torchlight, and water dripping from the vault."},
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

var sensitivity_slider: HSlider
var fov_slider: HSlider
var _preset_picker: OptionButton
var _readout: Label
var _hint: Label
var _widgets := {}
var _syncing := false
var _debounce: Timer
var _buttons: HBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.18
	_debounce.process_mode = Node.PROCESS_MODE_ALWAYS
	_debounce.timeout.connect(func() -> void:
		Graphics.mark_custom()
		sync())
	add_child(_debounce)
	_build()
	sync()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_readout.text = "%d FPS   %.1f ms   %d draw calls   %s preset" % [
			Engine.get_frames_per_second(),
			1000.0 / maxf(Engine.get_frames_per_second(), 1.0),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Graphics.preset_name(),
		]


## Adds a button to the row along the bottom, after Back.
func add_button(text: String, action: Callable) -> void:
	_buttons.add_child(menu_button(text, action, 150))


func _build() -> void:
	var box := panel_box(self, 640)
	box.add_child(title_label("SETTINGS"))

	box.add_child(section_label("CONTROLS"))
	var srow := HBoxContainer.new()
	srow.custom_minimum_size.y = ROW_HEIGHT
	var sl := Label.new()
	sl.text = "Mouse sensitivity"
	sl.custom_minimum_size.x = 210
	srow.add_child(sl)
	sensitivity_slider = HSlider.new()
	sensitivity_slider.min_value = Graphics.SENSITIVITY_MIN
	sensitivity_slider.max_value = Graphics.SENSITIVITY_MAX
	sensitivity_slider.step = 0.05
	sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sv := Label.new()
	sv.custom_minimum_size.x = 64
	sv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sensitivity_slider.value_changed.connect(func(v: float) -> void:
		sv.text = "%d%%" % roundi(v * 100.0)
		if not _syncing:
			Graphics.set_mouse_sensitivity(v))
	srow.add_child(sensitivity_slider)
	srow.add_child(sv)
	srow.mouse_entered.connect(func() -> void:
		_hint.text = "How far the view turns for the mouse's travel. 100% is the game's own.")
	srow.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(srow)

	var frow := HBoxContainer.new()
	frow.custom_minimum_size.y = ROW_HEIGHT
	var fl := Label.new()
	fl.text = "Field of view"
	fl.custom_minimum_size.x = 210
	frow.add_child(fl)
	fov_slider = HSlider.new()
	fov_slider.min_value = Graphics.FOV_MIN
	fov_slider.max_value = Graphics.FOV_MAX
	fov_slider.step = 1.0
	fov_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fov_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fv := Label.new()
	fv.custom_minimum_size.x = 64
	fv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fov_slider.value_changed.connect(func(v: float) -> void:
		fv.text = "%d°" % roundi(v)
		if not _syncing:
			Graphics.set_field_of_view(v))
	frow.add_child(fov_slider)
	frow.add_child(fv)
	frow.mouse_entered.connect(func() -> void:
		_hint.text = "How much of the world the view takes in, top to bottom. 75° is the game's own.")
	frow.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(frow)
	box.add_child(_rule())

	box.add_child(section_label("GRAPHICS"))
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 14)
	_readout.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	box.add_child(_readout)

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
			sync()
			return
		Graphics.set_preset(idx)
		sync())
	preset_row.add_child(_preset_picker)
	box.add_child(preset_row)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 300
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
	_buttons = HBoxContainer.new()
	_buttons.add_child(menu_button("Back", func() -> void: back_pressed.emit(), 150))
	box.add_child(_buttons)


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


## Pushes the saved values back into the widgets. Guarded, because assigning a
## widget's value fires its own signal and would otherwise look like the player
## had just edited it -- which would flip the preset to Custom.
func sync() -> void:
	if _preset_picker == null:
		return
	_syncing = true
	_preset_picker.select(Graphics.preset)
	sensitivity_slider.value = Graphics.mouse_sensitivity
	fov_slider.value = Graphics.field_of_view
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


# --- Small builders, shared with the menus that hold this page ----------------------

static func panel_box(parent: Control, width := 360) -> VBoxContainer:
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


static func title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(0.93, 0.80, 0.62))
	return l


static func section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.75, 0.42, 0.36))
	return l


static func dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.6, 0.56, 0.52))
	return l


static func menu_button(text: String, action: Callable, width := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b


static func spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(0.35, 0.22, 0.20, 0.8)
	r.custom_minimum_size.y = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
