extends Control

## The two wheels (2026-10-10), which replace the hotbar: held up by a key, aimed
## with the mouse or the right stick, chosen on release.
##
##   weapons  "weapon_wheel" (C / right stick click): the four weapon-wheel slots
##            (inventory 0-3). Released on one, it is taken in hand.
##   quick    "quick_wheel" (X): the four quick-item slots (inventory 4-7).
##            Released on one, it is used (a potion drunk). On a controller a
##            d-pad direction holds it up on that slot until it is let go, which
##            uses it; another direction moves the choice; B cancels.
##
## Directions are fixed: up 1, right 2, down 3, left 4. The mouse's travel while
## the wheel is up is gathered into `_aim` (and swallowed, so the view does not
## turn); the right stick sets it outright. Nothing is chosen until it has moved
## DEAD_ZONE from the middle, so letting go at once does nothing.
##
## What goes in each slot is set in the inventory screen (Tab). The world keeps
## going while a wheel is up, and the player can still walk; looking and
## attacking wait (`player.wheel_open`).

const RADIUS := 150.0
const CELL := 92.0
## In canvas pixels: mouse travel arrives scaled by the window's stretch (half,
## in a 2x window), so this is ~56 px of real mouse movement there.
const DEAD_ZONE := 28.0
const AIM_MAX := 170.0
const GOLD := Color(0.95, 0.78, 0.42)
const INK := Color(0.93, 0.88, 0.78)
## Up, right, down, left.
const DIRS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

var player: Node
var kind := &"weapons"
var _action := &"weapon_wheel"
var _first := 0
var _open := false
var _aim := Vector2.ZERO
var _choice := -1
## Held up by a d-pad direction (its "quick_N" action), not the wheel key.
var _held := &""
var _font: Font


func setup(p: Node, which: StringName) -> void:
	player = p
	kind = which
	_action = &"weapon_wheel" if which == &"weapons" else &"quick_wheel"
	_first = 0 if which == &"weapons" else Inventory.QUICK_FIRST
	name = "WeaponWheel" if which == &"weapons" else "QuickWheel"
	# Offsets too: anchors alone left it zero-sized, drawn round the top-left corner.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func is_open() -> bool:
	return _open


## Which quick slot a d-pad press is for ("quick_1".."quick_4"), or -1.
func _dpad_slot(event: InputEvent) -> int:
	for n in Inventory.QUICK:
		if event.is_action_pressed(&"quick_%d" % (n + 1)) and not event.is_echo():
			return n
	return -1


func _can_open() -> bool:
	return player != null and not player.get("ui_open") and not player.get("in_cutscene") \
		and player.get("_dead") != true and not player.get("wheel_open") and not player.get("remote_view") \
		and not player.call("is_hidden") and not get_tree().paused


func _input(event: InputEvent) -> void:
	if player == null:
		return
	# Co-op: only this wheel's player's keys, mouse or pad (coop.gd).
	if not Coop.owns(player, event):
		return
	if not _open:
		if event.is_action_pressed(_action) and not event.is_echo() and _can_open():
			_open_wheel()
			get_viewport().set_input_as_handled()
			return
		# The d-pad (2026-10-14): a direction opens the quick wheel on that slot
		# and holds it up until that button is let go, which uses it.
		if kind == &"quick":
			var n := _dpad_slot(event)
			if n >= 0 and _can_open():
				_open_wheel()
				_held = &"quick_%d" % (n + 1)
				_choice = n
				queue_redraw()
				get_viewport().set_input_as_handled()
		return
	if _held != &"":
		# Another direction while one is held moves the choice there.
		var n := _dpad_slot(event)
		if n >= 0:
			_held = &"quick_%d" % (n + 1)
			_choice = n
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(_held):
			_close(true)
			get_viewport().set_input_as_handled()
			return
		# B before the release: put it down, use nothing.
		var pad := event as InputEventJoypadButton
		if pad != null and pad.pressed and pad.button_index == JOY_BUTTON_B:
			_close(false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventJoypadButton or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if event.is_action_released(_action):
		_close(true)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_aim = (_aim + (event as InputEventMouseMotion).relative).limit_length(AIM_MAX)
		_update_choice()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		# Clicks while choosing do nothing in the world.
		get_viewport().set_input_as_handled()


func _open_wheel() -> void:
	_open = true
	_aim = Vector2.ZERO
	_choice = -1
	player.set("wheel_open", true)
	if player.has_method("_end_block"):
		player.call("_end_block")
	visible = true
	queue_redraw()


func _close(apply: bool) -> void:
	if not _open:
		return
	_open = false
	_held = &""
	visible = false
	player.set("wheel_open", false)
	if not apply or _choice < 0:
		return
	var inv: Inventory = player.get("inventory")
	var slot := _first + _choice
	if kind == &"weapons":
		# An empty slot is no choice: the weapon in hand stays.
		if not inv.is_empty(slot):
			player.call("select_slot", _choice)
	elif not inv.is_empty(slot):
		player.call("use_consumable", slot)


func _process(_delta: float) -> void:
	if not _open:
		return
	# Something took the screen (a scene, death, a menu): put the wheel down.
	if player.get("ui_open") or player.get("in_cutscene") or player.get("_dead") == true or get_tree().paused:
		_close(false)
		return
	# The key let go without the release reaching us (focus lost): the same.
	if not Coop.held(player, _held if _held != &"" else _action):
		_close(true)
		return
	var stick := Coop.vector(player, &"look_left", &"look_right", &"look_up", &"look_down")
	if stick.length() > 0.5:
		_aim = stick.normalized() * AIM_MAX
		_update_choice()
	queue_redraw()


func _update_choice() -> void:
	if _aim.length() < DEAD_ZONE:
		_choice = -1
		return
	var best := -1
	var best_dot := -2.0
	for i in DIRS.size():
		var d: float = (DIRS[i] as Vector2).dot(_aim.normalized())
		if d > best_dot:
			best_dot = d
			best = i
	_choice = best


func _draw() -> void:
	if not _open or player == null:
		return
	var inv: Inventory = player.get("inventory")
	var c := size * 0.5
	draw_circle(c, RADIUS + CELL * 0.85, Color(0.0, 0.0, 0.0, 0.42))
	draw_arc(c, RADIUS + CELL * 0.85, 0.0, TAU, 64, Color(GOLD, 0.25), 2.0, true)
	# The pointer.
	if _aim.length() > 4.0:
		var tip := c + _aim.normalized() * minf(_aim.length(), RADIUS - CELL * 0.6)
		draw_line(c, tip, Color(GOLD, 0.6), 3.0, true)
		draw_circle(tip, 5.0, GOLD)
	draw_circle(c, 6.0, Color(INK, 0.6))
	for i in DIRS.size():
		var slot := _first + i
		var id: StringName = inv.id_at(slot)
		# A quick slot run dry: its item greyed out with a 0.
		var kept: StringName = inv.assigned_at(slot) if id == &"" else &""
		var chosen := i == _choice
		var side := CELL * (1.12 if chosen else 1.0)
		var at: Vector2 = c + (DIRS[i] as Vector2) * RADIUS
		var rect := Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side))
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(16)
		box.anti_aliasing = true
		box.bg_color = Color(0.14, 0.12, 0.09, 0.92) if chosen else Color(0.06, 0.065, 0.08, 0.86)
		var in_hand: bool = kind == &"weapons" and i == int(player.get("selected_slot")) and id != &""
		box.border_color = GOLD if chosen else (Color(GOLD, 0.6) if in_hand else Color(0.42, 0.4, 0.38, 0.8))
		box.set_border_width_all(3 if chosen else 2)
		draw_style_box(box, rect)
		if id != &"":
			var pad := side * 0.16
			ItemIcon.paint(self, id, rect.grow(-pad))
			var n := inv.count_at(slot)
			if n > 1:
				draw_string(_font, rect.end - Vector2(28, 8), str(n), HORIZONTAL_ALIGNMENT_RIGHT, 22, 18, INK)
		elif kept != &"":
			var pad := side * 0.16
			ItemIcon.paint(self, kept, rect.grow(-pad), ItemSlot.GHOST)
			draw_string(_font, rect.end - Vector2(28, 8), "0", HORIZONTAL_ALIGNMENT_RIGHT, 22, 18, Color(INK, 0.55))
		else:
			draw_string(_font, Vector2(rect.position.x, at.y + 6), "empty", HORIZONTAL_ALIGNMENT_CENTER,
				side, 14, Color(INK, 0.35))
		draw_string(_font, rect.position + Vector2(8, 18), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(INK, 0.7))
		if in_hand:
			draw_string(_font, Vector2(rect.position.x, rect.end.y + 16), "in hand", HORIZONTAL_ALIGNMENT_CENTER,
				side, 12, Color(GOLD, 0.8))
	# The title, and the chosen item's name, in the middle.
	var title := "WEAPONS" if kind == &"weapons" else "QUICK ITEMS"
	draw_string(_font, c + Vector2(-100, -16), title, HORIZONTAL_ALIGNMENT_CENTER, 200, 15, Color(INK, 0.75))
	if _choice >= 0:
		var chosen_id: StringName = inv.id_at(_first + _choice)
		var label := Inventory.item_name(chosen_id) if chosen_id != &"" else "Empty"
		var kept_id: StringName = inv.assigned_at(_first + _choice)
		if chosen_id == &"" and kept_id != &"":
			label = "%s (none left)" % Inventory.item_name(kept_id)
		draw_string(_font, c + Vector2(-110, 30), label, HORIZONTAL_ALIGNMENT_CENTER, 220, 18, GOLD)
