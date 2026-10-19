extends Node

## Controller helpers (2026-10-10), autoload "Pad".
##
## `using_pad`: whether a controller was the last thing touched (any button, or a
## stick pushed past half way); any key, mouse button or real mouse movement
## sets it back.
##
## THE CURSOR. Screens that are worked with a mouse (the inventory, the full map)
## ask for it with `want_cursor(self, true)`. While one does and a pad is in use,
## an arrow is drawn and the left stick moves it; it is a mouse as far
## as the game is concerned -- every move is sent as a real InputEventMouseMotion
## and A as the left button (press and release; held, it drags), so hovering,
## clicking and drag-and-drop all work without the screens knowing. The OS
## pointer is hidden meanwhile and comes back the moment the mouse is moved.
##
## THE ON-SCREEN KEYBOARD. `attach_keyboard(line_edit)` on any text box: when it
## takes focus while a pad is in use, a keyboard pops up over everything. The
## d-pad / stick moves between keys, A types, B deletes, X is a space, Y shifts,
## Start (or the Done key) finishes. It sits on its own CanvasLayer added LAST to
## the root, so its input comes before any screen's (B would otherwise close the
## screen behind it).

signal device_changed(pad: bool)

const CURSOR_SPEED := 820.0
const STICK_DEAD := 0.18
## Synthetic mouse events carry this device id, so they are not mistaken for
## the real mouse (which would switch `using_pad` off).
const SYNTH_DEVICE := 77

var using_pad := false
var cursor_pos := Vector2(640.0, 360.0)

var _cursor_owners := {}
var _cursor_layer: CanvasLayer
var _arrow: Control
var _a_down := false
var _pad_device := 0
var _hid_mouse := false
## The left stick, from its own motion events (Input.get_joy_axis only sees
## what a joypad driver reports, not parsed events).
var _stick := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.layer = 120
	add_child(_cursor_layer)
	_arrow = Control.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.size = Vector2(1, 1)
	_arrow.visible = false
	_arrow.draw.connect(_draw_arrow)
	_cursor_layer.add_child(_arrow)


# --- Which device -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var motion := event as InputEventJoypadMotion
	if motion != null:
		if motion.axis == JOY_AXIS_LEFT_X:
			_stick.x = motion.axis_value
		elif motion.axis == JOY_AXIS_LEFT_Y:
			_stick.y = motion.axis_value
	var pad := using_pad
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		pad = true
		_pad_device = event.device
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		pad = true
		_pad_device = event.device
	elif event is InputEventMouseMotion and event.device != SYNTH_DEVICE \
			and (event as InputEventMouseMotion).relative.length() > 2.0:
		pad = false
	elif (event is InputEventMouseButton and event.device != SYNTH_DEVICE) or event is InputEventKey:
		pad = false
	if pad != using_pad:
		using_pad = pad
		device_changed.emit(pad)


# --- The cursor --------------------------------------------------------------------

## Two-monitor co-op (split_screen.gd): the cursor lives in player 2's own
## window -- drawn there, kept to it, and its clicks and moves handed straight
## to it (it never has the focus to get them otherwise). null: this window.
var _target: Viewport = null


func use_viewport(vp: Viewport) -> void:
	_target = vp
	var home: Node = vp if vp != null else self
	if _cursor_layer.get_parent() != home:
		_cursor_layer.reparent(home, false)


func _vp() -> Viewport:
	return _target if _target != null and is_instance_valid(_target) else get_viewport()


## A screen that wants the pad cursor while it is open. `click`: whether A is
## the left mouse button for it (the inventory works A itself, on the slot the
## cursor highlights, so it asks for no clicks).
func want_cursor(owner: Object, on: bool, click := true) -> void:
	# Co-op: the cursor is player 2's (the pad's); player 1's screens have
	# the real mouse.
	var who = owner.get("player") if owner.get("player") != null else owner.get("_player")
	if on and Coop.active and who != null and Coop.index_of(who) == 0:
		return
	if on:
		if _cursor_owners.is_empty():
			# Start where the real pointer is, so nothing jumps -- co-op, in the
			# middle of player 2's half.
			var r := _vp().get_visible_rect()
			if _vp() != get_viewport():
				cursor_pos = r.get_center()
			elif Coop.active:
				cursor_pos = Vector2(r.position.x + r.size.x * 0.75, r.position.y + r.size.y * 0.5)
			else:
				cursor_pos = get_viewport().get_mouse_position()
		_cursor_owners[owner] = click
	else:
		_cursor_owners.erase(owner)
		if _cursor_owners.is_empty():
			_release_a()
			if _hid_mouse and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_hid_mouse = false


func cursor_active() -> bool:
	return not _cursor_owners.is_empty() and (using_pad or Coop.active) and not keyboard_open()


## Whether `p` is working a screen with a pad -- co-op, player 2 always and
## player 1 never; otherwise whichever was touched last.
func for_player(p: Node) -> bool:
	return Coop.on_pad(p) if Coop.active else using_pad


func _process(delta: float) -> void:
	for owner in _cursor_owners.keys():
		if not is_instance_valid(owner):
			_cursor_owners.erase(owner)
	var active := cursor_active()
	_arrow.visible = active
	if not active:
		_release_a()
		if _hid_mouse and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_hid_mouse = false
		return
	# Co-op: the real pointer is player 1's; it is left alone.
	if not Coop.active and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_hid_mouse = true
	# The LEFT STICK moves it (2026-10-14; it used to be the ui_* actions, which
	# carry the d-pad -- the inventory steps its highlight on the d-pad).
	var v := _stick
	if v.length() < STICK_DEAD:
		v = Vector2.ZERO
	else:
		v = v.limit_length(1.0)
	if v != Vector2.ZERO:
		var rect := _vp().get_visible_rect()
		# Co-op: kept on the right half, player 2's (or in their own window).
		if Coop.active and _vp() == get_viewport():
			rect = Rect2(rect.position + Vector2(rect.size.x * 0.5, 0.0), Vector2(rect.size.x * 0.5, rect.size.y))
		cursor_pos = (cursor_pos + v * v.length() * CURSOR_SPEED * delta).clamp(rect.position, rect.end - Vector2(2, 2))
		_send_motion(v * v.length() * CURSOR_SPEED * delta)
	# A is the left mouse button -- for screens that asked for clicks.
	var a := Input.is_joy_button_pressed(_pad_device, JOY_BUTTON_A) and _cursor_owners.values().has(true)
	if a != _a_down:
		_a_down = a
		_send_button(a)
	_arrow.position = cursor_pos
	_arrow.queue_redraw()


func _release_a() -> void:
	if _a_down:
		_a_down = false
		_send_button(false)


## Canvas (viewport) coordinates to the window's, which is what a mouse event
## carries in (the stretch is undone on the way in).
func _window_pos(p: Vector2) -> Vector2:
	return _vp().get_final_transform() * p


func _send_motion(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.device = SYNTH_DEVICE
	ev.position = _window_pos(cursor_pos)
	ev.global_position = ev.position
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _a_down else 0
	_deliver(ev)


func _send_button(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.device = SYNTH_DEVICE
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = _window_pos(cursor_pos)
	ev.global_position = ev.position
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	_deliver(ev)


func _deliver(ev: InputEvent) -> void:
	if _vp() != get_viewport():
		_vp().push_input(ev)
	else:
		Input.parse_input_event(ev)


func _draw_arrow() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 22), Vector2(6, 17), Vector2(10, 26),
		Vector2(14, 24), Vector2(10, 15.5), Vector2(17, 15.5)])
	_arrow.draw_colored_polygon(pts, Color(0.98, 0.94, 0.84))
	pts.append(Vector2(0, 0))
	_arrow.draw_polyline(pts, Color(0.08, 0.06, 0.04), 2.0, true)


# --- The on-screen keyboard -----------------------------------------------------------

const ROWS := ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.-"]

var _kb_layer: CanvasLayer
var _kb_target: LineEdit
var _kb_keys: Array[Button] = []
var _kb_shift := false
var _kb_preview: Label


## Gives `edit` the on-screen keyboard whenever it takes focus with a pad in use.
func attach_keyboard(edit: LineEdit) -> void:
	if edit.has_meta(&"osk"):
		return
	edit.set_meta(&"osk", true)
	edit.focus_entered.connect(func() -> void:
		if using_pad:
			show_keyboard(edit))
	# Already focused and a pad picks up: A on it opens the keyboard too.
	edit.gui_input.connect(func(e: InputEvent) -> void:
		if using_pad and not keyboard_open() and e.is_action_pressed(&"ui_accept"):
			show_keyboard(edit))


func keyboard_open() -> bool:
	return _kb_layer != null and _kb_layer.visible


func show_keyboard(edit: LineEdit) -> void:
	_kb_target = edit
	if _kb_layer == null:
		_build_keyboard()
	# Last child of the root: its input comes first.
	var root := get_tree().root
	if _kb_layer.get_parent() != root:
		if _kb_layer.get_parent() != null:
			_kb_layer.get_parent().remove_child(_kb_layer)
		root.add_child.call_deferred(_kb_layer)
	else:
		root.move_child(_kb_layer, -1)
	_kb_layer.visible = true
	_kb_shift = false
	_relabel()
	_update_preview()
	# "q": the first letter.
	_kb_keys[10].grab_focus.call_deferred()


func hide_keyboard() -> void:
	if _kb_layer == null or not _kb_layer.visible:
		return
	_kb_layer.visible = false
	var edit := _kb_target
	_kb_target = null
	if edit != null and is_instance_valid(edit):
		edit.text_submitted.emit(edit.text)
		# On to whatever comes after the box (its Save button, say).
		var nxt := edit.find_next_valid_focus()
		if nxt != null and nxt != edit:
			nxt.grab_focus()


func _build_keyboard() -> void:
	_kb_layer = CanvasLayer.new()
	_kb_layer.name = "OnScreenKeyboard"
	_kb_layer.layer = 125
	_kb_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_kb_layer.set_script(load("res://scripts/pad_keyboard_input.gd"))
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kb_layer.add_child(holder)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.045, 0.04, 0.97)
	box.border_color = Color(0.86, 0.68, 0.38)
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", box)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -30
	holder.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	_kb_preview = Label.new()
	_kb_preview.add_theme_font_size_override("font_size", 20)
	_kb_preview.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	_kb_preview.custom_minimum_size = Vector2(560, 30)
	column.add_child(_kb_preview)
	_kb_keys.clear()
	for row: String in ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 5)
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_child(line)
		for ch in row:
			var b := _key(ch, 50)
			b.pressed.connect(func() -> void: _type(b.text))
			line.add_child(b)
			_kb_keys.append(b)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 5)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(bottom)
	var shift := _key("Shift  (Y)", 120)
	shift.pressed.connect(_toggle_shift)
	bottom.add_child(shift)
	var space := _key("Space  (X)", 200)
	space.pressed.connect(func() -> void: _type(" "))
	bottom.add_child(space)
	var back := _key("Delete  (B)", 120)
	back.pressed.connect(_backspace)
	bottom.add_child(back)
	var done := _key("Done  (Start)", 140)
	done.pressed.connect(hide_keyboard)
	bottom.add_child(done)
	_kb_layer.visible = false


func _key(label: String, width: float) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(width, 46)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 18)
	return b


func _type(s: String) -> void:
	if _kb_target == null or not is_instance_valid(_kb_target):
		return
	_kb_target.insert_text_at_caret(s)
	if _kb_shift:
		_kb_shift = false
		_relabel()
	_update_preview()


func _backspace() -> void:
	if _kb_target == null or not is_instance_valid(_kb_target):
		return
	var col := _kb_target.caret_column
	if col > 0:
		_kb_target.delete_text(col - 1, col)
	_update_preview()


func _toggle_shift() -> void:
	_kb_shift = not _kb_shift
	_relabel()


func _relabel() -> void:
	for b in _kb_keys:
		b.text = b.text.to_upper() if _kb_shift else b.text.to_lower()


func _update_preview() -> void:
	if _kb_preview != null and _kb_target != null and is_instance_valid(_kb_target):
		_kb_preview.text = _kb_target.text + "_"


## The keyboard's own buttons, read before anything else sees them (its layer is
## the root's last child): B deletes, X spaces, Y shifts, Start finishes. A is
## left to the focused key.
func keyboard_input(event: InputEvent) -> bool:
	if not keyboard_open():
		return false
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed:
		# Escape on a keyboard closes it too.
		if event is InputEventKey and (event as InputEventKey).pressed \
				and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			hide_keyboard()
			return true
		return false
	match pad.button_index:
		JOY_BUTTON_B:
			_backspace()
		JOY_BUTTON_X:
			_type(" ")
		JOY_BUTTON_Y:
			_toggle_shift()
		JOY_BUTTON_START:
			hide_keyboard()
		_:
			return false
	return true
