class_name ItemSlot
extends Panel

## One square of the inventory: the item's picture, how many, and -- on the
## hotbar -- the number key that selects it. The hotbar and the inventory screen
## are both built from these, so they always look alike.
##
## With `interactive` on (the inventory screen) a slot can be dragged onto
## another to move, merge or swap it; shift-click sends it between the bag and
## the hotbar; right-click splits the stack in half into the first empty slot
## of the same section.

const SIZE := 58.0

var inventory: Inventory
var index := 0
var interactive := false
var selected := false:
	set(value):
		selected = value
		_restyle()
## Under the mouse (inventory screen only): lit up so you can see what you are
## pointing at, and the screen describes it.
var hovered := false:
	set(value):
		hovered = value
		_restyle()
## Dimmed by the inventory screen's category filter: the item is not of the
## kind being shown.
var faded := false:
	set(value):
		faded = value
		_restyle()
## The inventory screen's look: square, dark iron-grey, a hairline bronze edge
## and a gold glow when pointed at. The HUD hotbar keeps the plain look.
var ornate := false


var _icon: ItemIcon
var _count: Label
var _key: Label
var _box: StyleBoxFlat
## A cooldown over the slot (the HUD's hotbar): a dark shade over the share
## still to recharge, draining downward, and the seconds left.
var _shade: ColorRect
var _shade_label: Label


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	_box = StyleBoxFlat.new()
	_box.set_corner_radius_all(5)
	_box.set_border_width_all(2)
	add_theme_stylebox_override("panel", _box)

	_icon = ItemIcon.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = 7
	_icon.offset_top = 7
	_icon.offset_right = -7
	_icon.offset_bottom = -7
	add_child(_icon)

	_key = Label.new()
	_key.position = Vector2(5, 1)
	_key.add_theme_font_size_override("font_size", 12)
	_key.add_theme_color_override("font_color", Color(0.85, 0.85, 0.82, 0.85))
	_key.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_key)

	_count = Label.new()
	_count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count.offset_right = -5
	_count.offset_bottom = -1
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_size_override("font_size", 15)
	_count.add_theme_color_override("font_color", Color(0.96, 0.96, 0.94))
	_count.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_count.add_theme_constant_override("shadow_offset_x", 1)
	_count.add_theme_constant_override("shadow_offset_y", 1)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)

	_shade = ColorRect.new()
	_shade.color = Color(0.0, 0.0, 0.0, 0.62)
	# ColorRect defaults to stopping the mouse; this one must never.
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.visible = false
	add_child(_shade)
	_shade_label = Label.new()
	_shade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shade_label.add_theme_font_size_override("font_size", 18)
	_shade_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.8))
	_shade_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_shade_label.add_theme_constant_override("shadow_offset_x", 1)
	_shade_label.add_theme_constant_override("shadow_offset_y", 1)
	_shade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade_label.visible = false
	add_child(_shade_label)
	_restyle()


## `share` 0..1 of the slot still recharging (0 hides it), `seconds` left.
func set_cooldown(share: float, seconds: float) -> void:
	var on := share > 0.001
	_shade.visible = on
	_shade_label.visible = on
	if not on:
		return
	var h := size.y * clampf(share, 0.0, 1.0)
	_shade.position = Vector2(0.0, size.y - h)
	_shade.size = Vector2(size.x, h)
	_shade_label.text = str(ceili(seconds))


## Size and look for the inventory screen. `font` draws the count.
func make_ornate(side: float, font: Font) -> void:
	ornate = true
	custom_minimum_size = Vector2(side, side)
	var pad := side * 0.12
	_icon.offset_left = pad
	_icon.offset_top = pad
	_icon.offset_right = -pad
	_icon.offset_bottom = -pad
	_count.add_theme_font_override("font", font)
	_count.add_theme_font_size_override("font_size", int(side * 0.24))
	_count.offset_right = -side * 0.07
	_key.add_theme_font_override("font", font)
	_restyle()


func setup(inv: Inventory, i: int, is_interactive: bool) -> void:
	inventory = inv
	index = i
	interactive = is_interactive
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	# On a wheel: its direction's number (up 1, right 2, down 3, left 4).
	_key.text = str(i % 4 + 1) if i < Inventory.HOTBAR else ""
	refresh()


func refresh() -> void:
	if inventory == null:
		return
	var id := inventory.id_at(index)
	_icon.item = id
	var n := inventory.count_at(index)
	_count.text = str(n) if n > 1 else ""
	# The inventory screen's description panel says what this is now.
	tooltip_text = ""
	_restyle()


func _restyle() -> void:
	if _box == null:
		return
	modulate.a = 0.28 if faded else 1.0
	if ornate:
		_box.set_corner_radius_all(1)
		_box.bg_color = Color(0.085, 0.078, 0.07, 0.96) if not hovered else Color(0.12, 0.1, 0.075, 0.98)
		var gold := Color(0.86, 0.66, 0.32)
		if hovered:
			_box.border_color = gold
			_box.set_border_width_all(2)
			_box.shadow_color = Color(gold, 0.35)
			_box.shadow_size = 6
		elif selected:
			_box.border_color = Color(gold, 0.7)
			_box.set_border_width_all(2)
			_box.shadow_size = 0
		else:
			_box.border_color = Color(0.3, 0.26, 0.2, 0.9)
			_box.set_border_width_all(1)
			_box.shadow_size = 0
		return
	_box.bg_color = Color(0.16, 0.14, 0.11, 0.9) if hovered else Color(0.07, 0.075, 0.09, 0.78)
	if selected:
		_box.border_color = Color(1.0, 0.82, 0.45, 0.95)
	elif hovered:
		_box.border_color = Color(0.86, 0.78, 0.62, 0.95)
	else:
		_box.border_color = Color(0.42, 0.4, 0.38, 0.75)
	_box.set_border_width_all(3 if selected or hovered else 2)


# --- Dragging (inventory screen only) ---------------------------------------

func _get_drag_data(_at: Vector2) -> Variant:
	if not interactive or inventory.is_empty(index):
		return null
	var preview := ItemIcon.new()
	preview.item = inventory.id_at(index)
	preview.size = Vector2(SIZE, SIZE) * 0.8
	preview.position = -preview.size * 0.5
	var holder := Control.new()
	holder.add_child(preview)
	set_drag_preview(holder)
	return {"inventory_slot": index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return interactive and data is Dictionary and data.has("inventory_slot")


func _drop_data(_at: Vector2, data: Variant) -> void:
	inventory.move(int(data["inventory_slot"]), index)


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	if click.button_index == MOUSE_BUTTON_LEFT and click.shift_pressed:
		inventory.quick_move(index)
		accept_event()
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		# Half the stack into the first empty slot of this section.
		var lo := 0 if index < Inventory.HOTBAR else Inventory.HOTBAR
		var hi := Inventory.HOTBAR if index < Inventory.HOTBAR else Inventory.SIZE
		for j in range(lo, hi):
			if inventory.is_empty(j) and Inventory.slot_accepts(j, inventory.id_at(index)):
				inventory.split(index, j)
				break
		accept_event()
