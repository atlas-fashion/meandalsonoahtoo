extends Node

## The controls, rebindable (note 164; the user: "Make a keybinds menu").
##
## Every gameplay action on the keybinds page (`ACTIONS`) has one binding in each
## of two columns: the keyboard and mouse, and the controller. The project's own
## bindings (project.godot) are the defaults, read off the InputMap at startup
## before anything is changed; the player's changes are saved to SAVE_PATH and
## laid over them at startup, and "Reset" puts the defaults back.
##
## Everything the game asks goes through the InputMap ("attack", `_action_held`,
## Coop's split "p1_" / "p2_" copies), so a rebinding is picked up everywhere at
## once. In co-op the split copies are rebuilt from the new bindings
## (`Coop.resplit`).
##
## "pause" (Escape / Start) and the "ui_" actions are not on the page: they are
## how the player gets out of a menu, and a lost Escape cannot be found again.
## For the same reason Escape and Start cannot be bound to anything.

signal changed

const SAVE_PATH := "user://keybinds.cfg"

const KEYBOARD := 0
const PAD := 1

## The page's rows, in order: [action, label].
const ACTIONS := [
	[&"move_forward", "Move forward"],
	[&"move_back", "Move back"],
	[&"move_left", "Move left"],
	[&"move_right", "Move right"],
	[&"jump", "Jump"],
	[&"sprint", "Sprint (hold)"],
	[&"dodge", "Dash"],
	[&"attack", "Attack"],
	[&"thrust", "Heavy attack"],
	[&"slam", "Special attack"],
	[&"block", "Block / parry"],
	[&"interact", "Interact"],
	[&"inventory", "Inventory"],
	[&"toggle_map", "Map"],
	[&"weapon_wheel", "Weapon wheel"],
	[&"quick_wheel", "Quick wheel"],
	[&"quick_1", "Quick slot 1"],
	[&"quick_2", "Quick slot 2"],
	[&"quick_3", "Quick slot 3"],
	[&"quick_4", "Quick slot 4"],
]

## Controller buttons by index, as an Xbox pad labels them.
const PAD_BUTTONS := ["A", "B", "X", "Y", "View", "Guide", "Start", "L3", "R3", "LB", "RB",
	"D-Up", "D-Down", "D-Left", "D-Right", "Share"]
## Inputs that cannot be bound: they are the way out of every menu.
const RESERVED_KEYS := [KEY_ESCAPE]
const RESERVED_PAD := [JOY_BUTTON_START, JOY_BUTTON_GUIDE]

## action -> the project's own events, as they were at startup.
var _defaults := {}


func _ready() -> void:
	for row in ACTIONS:
		var action: StringName = row[0]
		if not InputMap.has_action(action):
			continue
		var list: Array[InputEvent] = []
		for e in InputMap.action_get_events(action):
			list.append(e.duplicate())
		_defaults[action] = list
	load_bindings()


# --- Reading them -------------------------------------------------------------------

## Which column an event belongs in.
static func column_of(e: InputEvent) -> int:
	return PAD if e is InputEventJoypadButton or e is InputEventJoypadMotion else KEYBOARD


## `action`'s bindings in `column`.
func events(action: StringName, column: int) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			if column_of(e) == column:
				out.append(e)
	return out


## `action`'s binding in `column` as the screen says it: "LMB", "L-Ctrl", "RT";
## "--" for none.
func text(action: StringName, column: int) -> String:
	var names: PackedStringArray = []
	for e in events(action, column):
		names.append(event_text(e))
	return "--" if names.is_empty() else " ".join(names)


## Both columns, keyboard first: "LMB / RB". A column with nothing in it is left
## out.
func label(action: StringName) -> String:
	var parts: PackedStringArray = []
	for column in [KEYBOARD, PAD]:
		if not events(action, column).is_empty():
			parts.append(text(action, column))
	return " / ".join(parts) if not parts.is_empty() else "--"


static func event_text(e: InputEvent) -> String:
	var key := e as InputEventKey
	if key != null:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		var side := ""
		if key.location == KEY_LOCATION_LEFT:
			side = "L-"
		elif key.location == KEY_LOCATION_RIGHT:
			side = "R-"
		match code:
			KEY_CTRL:
				return side + "Ctrl"
			KEY_SHIFT:
				return side + "Shift"
			KEY_ALT:
				return side + "Alt"
			KEY_SPACE:
				return "Space"
			KEY_ESCAPE:
				return "Esc"
			KEY_QUOTELEFT:
				return "`"
		# The key as this keyboard's layout labels it (AZERTY's A where QWERTY
		# has Q), falling back to the physical key's own name.
		var shown := code
		if DisplayServer.get_name() != "headless":
			var local := DisplayServer.keyboard_get_label_from_physical(code)
			if local != KEY_NONE:
				shown = local
		return side + OS.get_keycode_string(shown)
	var mouse := e as InputEventMouseButton
	if mouse != null:
		match mouse.button_index:
			MOUSE_BUTTON_LEFT:
				return "LMB"
			MOUSE_BUTTON_RIGHT:
				return "RMB"
			MOUSE_BUTTON_MIDDLE:
				return "MMB"
			MOUSE_BUTTON_WHEEL_UP:
				return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Wheel down"
			MOUSE_BUTTON_XBUTTON1:
				return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2:
				return "Mouse 5"
		return "Mouse %d" % mouse.button_index
	var button := e as InputEventJoypadButton
	if button != null:
		if button.button_index >= 0 and button.button_index < PAD_BUTTONS.size():
			return PAD_BUTTONS[button.button_index]
		return "Button %d" % button.button_index
	var motion := e as InputEventJoypadMotion
	if motion != null:
		var up := motion.axis_value < 0.0
		match motion.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			JOY_AXIS_LEFT_X:
				return "L-stick left" if up else "L-stick right"
			JOY_AXIS_LEFT_Y:
				return "L-stick up" if up else "L-stick down"
			JOY_AXIS_RIGHT_X:
				return "R-stick left" if up else "R-stick right"
			JOY_AXIS_RIGHT_Y:
				return "R-stick up" if up else "R-stick down"
		return "Axis %d%s" % [motion.axis, "-" if up else "+"]
	return "?"


# --- Changing them ------------------------------------------------------------------

## An input the page may bind, cleaned to what a binding keeps: the physical key
## (and which side, for the left / right pairs), the mouse button, the pad button,
## or the axis and its direction; any device. Null when it is not one, or is
## reserved.
static func bindable(e: InputEvent) -> InputEvent:
	var key := e as InputEventKey
	if key != null:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if not key.pressed or key.echo or code == KEY_NONE or code in RESERVED_KEYS:
			return null
		var k := InputEventKey.new()
		k.physical_keycode = code
		# The side matters only for the keys that come in pairs.
		if code in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
			k.location = key.location
		return k
	var mouse := e as InputEventMouseButton
	if mouse != null:
		if not mouse.pressed:
			return null
		var m := InputEventMouseButton.new()
		m.button_index = mouse.button_index
		return m
	var button := e as InputEventJoypadButton
	if button != null:
		if not button.pressed or button.button_index in RESERVED_PAD:
			return null
		var b := InputEventJoypadButton.new()
		b.button_index = button.button_index
		b.device = -1
		return b
	var motion := e as InputEventJoypadMotion
	if motion != null:
		if absf(motion.axis_value) < 0.6:
			return null
		var a := InputEventJoypadMotion.new()
		a.axis = motion.axis
		a.axis_value = signf(motion.axis_value)
		a.device = -1
		return a
	return null


static func same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		var ca := ka.physical_keycode if ka.physical_keycode != KEY_NONE else ka.keycode
		var cb := kb.physical_keycode if kb.physical_keycode != KEY_NONE else kb.keycode
		if ca != cb:
			return false
		# An unsided binding and a sided one of the same key are the same key.
		return ka.location == kb.location or ka.location == KEY_LOCATION_UNSPECIFIED \
			or kb.location == KEY_LOCATION_UNSPECIFIED
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false


## The page's action holding `e` in its column, other than `except`; &"" for none.
func action_with(e: InputEvent, except: StringName = &"") -> StringName:
	for row in ACTIONS:
		var action: StringName = row[0]
		if action == except:
			continue
		for have in events(action, column_of(e)):
			if same(have, e):
				return action
	return &""


## `action`'s binding in `e`'s column becomes `e`. If another action on the page
## had it, the two swap: that one takes what this one had, so nothing is left
## doubled up, and nothing unbound that was not before. Saved at once.
func bind(action: StringName, e: InputEvent) -> void:
	if not InputMap.has_action(action) or e == null:
		return
	var column := column_of(e)
	var old := events(action, column)
	var other := action_with(e, action)
	if other != &"":
		for have in events(other, column):
			if same(have, e):
				InputMap.action_erase_event(other, have)
		for o in old:
			InputMap.action_add_event(other, o.duplicate())
	for o in old:
		InputMap.action_erase_event(action, o)
	InputMap.action_add_event(action, e)
	_applied()


## `action`'s bindings in `column` gone.
func unbind(action: StringName, column: int) -> void:
	for o in events(action, column):
		InputMap.action_erase_event(action, o)
	_applied()


## The project's own bindings, every one.
func reset_all() -> void:
	for action in _defaults:
		_restore(action)
	_applied()


func _restore(action: StringName) -> void:
	InputMap.action_erase_events(action)
	for e: InputEvent in _defaults[action]:
		InputMap.action_add_event(action, e.duplicate())


func _applied() -> void:
	save_bindings()
	if Coop.has_method("resplit"):
		Coop.resplit()
	changed.emit()


# --- Kept between runs --------------------------------------------------------------

## As strings, not stored Objects: "key:<physical>:<location>", "mouse:<button>",
## "joy:<button>", "axis:<axis>:<+1|-1>".
static func encode(e: InputEvent) -> String:
	var key := e as InputEventKey
	if key != null:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d:%d" % [code, key.location]
	if e is InputEventMouseButton:
		return "mouse:%d" % (e as InputEventMouseButton).button_index
	if e is InputEventJoypadButton:
		return "joy:%d" % (e as InputEventJoypadButton).button_index
	if e is InputEventJoypadMotion:
		var m := e as InputEventJoypadMotion
		return "axis:%d:%d" % [m.axis, int(signf(m.axis_value))]
	return ""


static func decode(s: String) -> InputEvent:
	var p := s.split(":")
	if p.size() < 2:
		return null
	match p[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(p[1])
			if p.size() > 2:
				k.location = int(p[2])
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(p[1])
			return m
		"joy":
			var b := InputEventJoypadButton.new()
			b.button_index = int(p[1])
			b.device = -1
			return b
		"axis":
			if p.size() < 3:
				return null
			var a := InputEventJoypadMotion.new()
			a.axis = int(p[1])
			a.axis_value = float(p[2])
			a.device = -1
			return a
	return null


## Only the actions that differ from the project's own are written, so a later
## change to a default reaches every player who never touched that action.
func save_bindings() -> void:
	var cfg := ConfigFile.new()
	for action in _defaults:
		var now := _encoded(InputMap.action_get_events(action))
		if now != _encoded(_defaults[action]):
			cfg.set_value("bindings", String(action), now)
	cfg.save(SAVE_PATH)


func load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section("bindings"):
		return
	for name_ in cfg.get_section_keys("bindings"):
		var action := StringName(name_)
		if not _defaults.has(action):
			continue
		var list = cfg.get_value("bindings", name_, [])
		if not (list is Array or list is PackedStringArray):
			continue
		InputMap.action_erase_events(action)
		for s in list:
			var e := decode(String(s))
			if e != null:
				InputMap.action_add_event(action, e)
	if Coop.has_method("resplit"):
		Coop.resplit()


static func _encoded(list: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for e in list:
		out.append(encode(e))
	out.sort()
	return out
