class_name KeybindsPanel
extends PanelContainer

## The keybinds page (note 164), opened from Settings' CONTROLS: a row per
## action (`Keybinds.ACTIONS`), its keyboard-and-mouse binding and its
## controller binding as buttons. Press one and the next key, mouse button, pad
## button or trigger becomes that binding (`Keybinds.bind`, which swaps with any
## action that had it). Escape or Start, or doing nothing for CAPTURE_TIMEOUT,
## leaves it as it was; Delete or Backspace clears it. "Reset all" puts the
## project's own back.

signal back_pressed

const CAPTURE_TIMEOUT := 6.0
## The press that started listening (the click or the pad's A) must not be what
## is bound: nothing is taken for this long after it.
const CAPTURE_GRACE := 0.18

var _buttons := {}
var _hint: Label
## The binding being listened for: [action, column], or empty.
var _capture: Array = []
var _capture_age := 0.0
var _first: Button


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.96)
	style.border_color = Color(0.45, 0.20, 0.18)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(22)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 640
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(SettingsPanel.title_label("KEY BINDINGS"))

	var head := HBoxContainer.new()
	var hl := SettingsPanel.section_label("ACTION")
	hl.custom_minimum_size.x = 210
	head.add_child(hl)
	for t in ["KEYBOARD / MOUSE", "CONTROLLER"]:
		var l := SettingsPanel.section_label(t)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(l)
	box.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 380
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	box.add_child(scroll)
	for row in Keybinds.ACTIONS:
		var action: StringName = row[0]
		if not InputMap.has_action(action):
			continue
		var line := HBoxContainer.new()
		line.custom_minimum_size.y = SettingsPanel.ROW_HEIGHT
		line.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.text = row[1]
		name_label.custom_minimum_size.x = 210
		line.add_child(name_label)
		for column in [Keybinds.KEYBOARD, Keybinds.PAD]:
			var b := Button.new()
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.y = 28
			b.pressed.connect(_listen.bind(action, column))
			line.add_child(b)
			_buttons[_key(action, column)] = b
			if _first == null:
				_first = b
		rows.add_child(line)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.y = 34
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	box.add_child(_hint)

	box.add_child(SettingsPanel._rule())
	var buttons := HBoxContainer.new()
	buttons.add_child(SettingsPanel.menu_button("Back", func() -> void:
		_stop_listening()
		back_pressed.emit(), 150))
	buttons.add_child(SettingsPanel.menu_button("Reset all", func() -> void:
		_stop_listening()
		Keybinds.reset_all()
		_hint.text = "Every binding is back to the game's own.", 150))
	box.add_child(buttons)

	Keybinds.changed.connect(refresh)
	refresh()
	_idle_hint()


## Shown: everything as bound now, and the first binding focused for a pad.
func open() -> void:
	_stop_listening()
	refresh()
	_idle_hint()
	if _first != null:
		_first.grab_focus.call_deferred()


func listening() -> bool:
	return not _capture.is_empty()


func refresh() -> void:
	for row in Keybinds.ACTIONS:
		for column in [Keybinds.KEYBOARD, Keybinds.PAD]:
			var b: Button = _buttons.get(_key(row[0], column))
			if b != null:
				b.text = Keybinds.text(row[0], column)


func _idle_hint() -> void:
	_hint.text = "Pick a binding, then press the key, button or trigger for it. An input another action has is swapped over."


func _listen(action: StringName, column: int) -> void:
	_stop_listening()
	_capture = [action, column]
	_capture_age = 0.0
	var b: Button = _buttons[_key(action, column)]
	b.text = "press..."
	if column == Keybinds.KEYBOARD:
		_hint.text = "Press a key or mouse button.   Esc: leave it   ·   Delete: clear it"
	else:
		_hint.text = "Press a controller button or trigger.   Start / Esc: leave it   ·   Delete: clear it"


func _stop_listening() -> void:
	if _capture.is_empty():
		return
	_capture = []
	refresh()


func _process(delta: float) -> void:
	if _capture.is_empty():
		return
	_capture_age += delta
	if _capture_age > CAPTURE_TIMEOUT or not is_visible_in_tree():
		_stop_listening()
		_idle_hint()


## In `_input`, so it comes before the menus' own Escape / B handling and the
## GUI's: while listening, every press is the binding's (or the way out).
func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()
	if _capture_age < CAPTURE_GRACE:
		return
	var action: StringName = _capture[0]
	var column: int = _capture[1]
	var key := event as InputEventKey
	var button := event as InputEventJoypadButton
	# The ways out, from either device.
	if (key != null and key.pressed and key.physical_keycode == KEY_ESCAPE) \
			or (button != null and button.pressed and button.button_index == JOY_BUTTON_START):
		_stop_listening()
		_idle_hint()
		return
	# Clearing it (either column: every pad button is bindable).
	if key != null and key.pressed and key.physical_keycode in [KEY_DELETE, KEY_BACKSPACE]:
		_capture = []
		Keybinds.unbind(action, column)
		_hint.text = "Cleared."
		return
	var e := Keybinds.bindable(event)
	if e == null or Keybinds.column_of(e) != column:
		return
	var other := Keybinds.action_with(e, action)
	_capture = []
	Keybinds.bind(action, e)
	_hint.text = "%s is now %s." % [_name_of(action), Keybinds.event_text(e)]
	if other != &"":
		_hint.text += "  %s took what it had: %s." % [_name_of(other), Keybinds.text(other, column)]
	var b: Button = _buttons[_key(action, column)]
	b.grab_focus.call_deferred()


static func _key(action: StringName, column: int) -> String:
	return "%s|%d" % [action, column]


static func _name_of(action: StringName) -> String:
	for row in Keybinds.ACTIONS:
		if row[0] == action:
			return row[1]
	return String(action)
