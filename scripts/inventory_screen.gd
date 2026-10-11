extends CanvasLayer

## The full inventory, opened and closed with "inventory" (Tab, or Y on a pad);
## Escape / B closes it too. While it is open the mouse is free and the player
## stops taking movement, look and attack input -- the world carries on, so it
## is not a pause. Laid out after a reference the user supplied: a header,
## three framed panels and a strip of keys along the bottom.
##
##   left    the bag, five across, filtered by category (Q / E, LB / RB, or
##           click a tab: other kinds dim in place, so nothing moves while you
##           sort)
##   middle  the item under the mouse -- or the one in hand -- as a card: its
##           picture, what it is, live numbers, a line of lore
##   right   the character: the WEAPON wheel and the QUICK ITEM wheel, each as
##           four slots in a diamond (up 1, right 2, down 3, left 4) -- this is
##           where the wheels are set up -- then coins, potions, health, ghost
##           and slam
##
##   drag            move a stack onto another slot (merges or swaps); a wheel
##                   slot takes only its own kind (inventory.gd `slot_accepts`)
##   shift-click     send a stack between the bag and its wheel
##   right-click     split a stack in half
##
## On a controller (2026-10-10): a cursor (pad.gd `want_cursor`) -- the left
## stick / d-pad moves it, A is the mouse button (click, or hold to drag), X
## sends the stack under it between the bag and its wheel, LB / RB change
## category, B / Y close.
##
## The screen is laid out in the 1280 x 720 canvas the project stretches, so
## it fits at any resolution. Created by hud.gd once the player exists.

var player: Node = null

var _root: Control
var _slots: Array[ItemSlot] = []
var _hovered := -1
var _category := 0

## [shown name, item kinds it takes (none = everything), the tab's picture].
const CATEGORIES := [
	["All Items", [], &""],
	["Weapons", ["Weapon"], &"sword"],
	["Consumables", ["Consumable"], &"health_potion"],
	["Treasure", ["Treasure", "Relic"], &"coins"],
	["Materials", ["Material", "Trophy"], &"bone_fragment"],
]

const INK := Color(0.047, 0.044, 0.041, 0.97)
const EDGE := Color(0.33, 0.27, 0.19)
const GOLD := Color(0.86, 0.68, 0.38)
const PARCHMENT := Color(0.9, 0.86, 0.78)
const DIM := Color(0.62, 0.58, 0.52)

const BAG_SLOT := 62.0
## The wheels' slots: two diamonds of three across side by side in the
## character panel.
const WHEEL_SLOT := 44.0

var _serif: Font
var _italic: Font
var _spaced: Font

# Left panel.
var _tabs: Array[Control] = []
var _category_label: Label
var _capacity_label: Label
var _capacity_bar: Control
var _capacity := 0.0

# The card.
var _card: VBoxContainer
var _card_empty: Label
var _card_name: Label
var _card_kind: Label
var _card_icon: ItemIcon
var _card_desc: Label
var _card_left: Array = []
var _card_right: Array = []
var _card_quote: Label

# The character.
var _coins_value: Label
var _potions_value: Label
var _bars: Array = []


func _ready() -> void:
	layer = 46  # above the explore map (45), below the pause menu (50)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_fonts()
	_build()
	visible = false


func setup(p: Node) -> void:
	player = p
	var inv: Inventory = player.inventory
	for i in _slots.size():
		_slots[i].setup(inv, i, true)
	inv.changed.connect(_refresh)
	if player.has_signal("selection_changed"):
		player.selection_changed.connect(func(_slot: int) -> void: _refresh())


func is_open() -> bool:
	return visible


func set_open(open: bool) -> void:
	if open == visible or player == null:
		return
	# Another screen (the full map) has the player already.
	if open and player.ui_open:
		return
	visible = open
	_set_hovered(-1)
	player.ui_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	# On a pad, a cursor to work it with (pad.gd): the stick moves it, A clicks
	# and drags.
	Pad.want_cursor(self, open)
	if open:
		_refresh()


func _process(_delta: float) -> void:
	if not visible:
		return
	# Anything that takes the screen away -- the pause menu, a cutscene, death --
	# closes this first, so it is never left open underneath.
	if get_tree().paused or player == null or player.in_cutscene or player.get("_dead"):
		visible = false
		_set_hovered(-1)
		Pad.want_cursor(self, false)
		if player != null:
			player.ui_open = false
		return
	_update_bars()


func _input(event: InputEvent) -> void:
	if player == null or get_tree().paused:
		return
	if event.is_action_pressed("inventory"):
		if not player.in_cutscene and not player.get("_dead"):
			set_open(not visible)
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
		return
	# Q / E step through the categories. Taken here, before anything in the
	# world can read E as "interact" while the screen is up.
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo \
			and (key.physical_keycode == KEY_Q or key.physical_keycode == KEY_E):
		_set_category(posmod(_category + (1 if key.physical_keycode == KEY_E else -1), CATEGORIES.size()))
		get_viewport().set_input_as_handled()
		return
	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed:
		match pad.button_index:
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
				_set_category(posmod(_category + (1 if pad.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1),
					CATEGORIES.size()))
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_X:
				if _hovered >= 0:
					player.inventory.quick_move(_hovered)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		return


func _refresh() -> void:
	if player == null:
		return
	for s in _slots:
		s.refresh()
		# The weapon in hand is marked on the weapon wheel.
		s.selected = s.index == player.selected_slot
	_apply_category()
	var used := 0
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		if not player.inventory.is_empty(i):
			used += 1
	_capacity = float(used) / float(Inventory.BAG)
	_capacity_label.text = "%d / %d" % [used, Inventory.BAG]
	_capacity_bar.queue_redraw()
	_coins_value.text = _thousands(player.currency)
	_potions_value.text = str(player.inventory.count(&"health_potion"))
	_describe()


func _set_hovered(i: int) -> void:
	if _hovered >= 0 and _hovered < _slots.size():
		_slots[_hovered].hovered = false
	_hovered = i
	if i >= 0:
		_slots[i].hovered = true
	_describe()


func _set_category(c: int) -> void:
	_category = c
	_apply_category()


func _apply_category() -> void:
	_category_label.text = CATEGORIES[_category][0]
	var kinds: Array = CATEGORIES[_category][1]
	for s in _slots:
		var id: StringName = player.inventory.id_at(s.index) if player != null else &""
		s.faded = not kinds.is_empty() and id != &"" and not (Inventory.item_kind(id) in kinds)
	for t in _tabs:
		t.queue_redraw()


## --- The card ------------------------------------------------------------------

## What the card shows: the hovered item, or else the one in hand.
func _describe() -> void:
	if _card == null or player == null:
		return
	var slot := _hovered if _hovered >= 0 and not player.inventory.is_empty(_hovered) \
		else int(player.selected_slot)
	var id: StringName = player.inventory.id_at(slot)
	var n: int = player.inventory.count_at(slot)
	_card.visible = id != &""
	_card_empty.visible = id == &""
	if id == &"":
		return
	_card_name.text = Inventory.item_name(id) + ("  x%d" % n if n > 1 else "")
	_card_kind.text = Inventory.item_kind(id)
	_card_icon.item = id
	_card_desc.text = Inventory.item_description(id)
	var stats := _stats_for(id)
	_fill_column(_card_left, stats[0], stats[1])
	_fill_column(_card_right, stats[2], stats[3])
	_card_quote.text = Inventory.item_quote(id)
	_card_quote.visible = _card_quote.text != ""


## [left header, left rows, right header, right rows]; rows are [name, value].
## Read off the player, so the numbers never go stale.
func _stats_for(id: StringName) -> Array:
	match id:
		&"sword":
			return [
				"Attack", [
					["Cut", str(roundi(player.attack_damage))],
					["Spin", "%d all round" % roundi(player.attack_damage)],
					["Slam", str(roundi(player.slam_damage))],
					["Slam reach", "%.1f m" % player.slam_radius],
					["Slam cooldown", "%d s" % roundi(player.slam_cooldown)],
					["Block", "-%d%%" % roundi((1.0 - player.block_damage_taken) * 100.0)],
					["Parry", "-%d%%" % roundi((1.0 - player.parry_damage_taken) * 100.0)],
					["Parry return", "%d%%" % roundi(player.parry_reflect * 100.0)],
				],
				"Controls", [
					["Cut", "LMB / RB"],
					["Spin", "Q / RT"],
					["Slam", "F / LT"],
					["Block", "hold RMB / LB"],
					["Parry", "RMB / LB as it lands"],
					["Ghost", "hold Shift / L3"],
					["Haft strike", "E / X"],
				],
			]
		&"spear":
			var s = player.spear
			return [
				"Attack", [
					["Stab", str(roundi(s.STAB_DAMAGE))],
					["Stab rate", "%.2f s" % s.STAB_EVERY],
					["Dash", str(roundi(s.DASH_DAMAGE))],
					["Dash cooldown", "%.1f s" % s.DASH_COOLDOWN],
					["Throw blast", str(roundi(s.BLAST_DAMAGE))],
					["Blast reach", "%.1f m" % s.BLAST_RADIUS],
					["Throw cooldown", "%d s" % roundi(s.THROW_COOLDOWN)],
					["Block", "-%d%%" % roundi((1.0 - player.block_damage_taken) * 100.0)],
				],
				"Controls", [
					["Stab", "LMB / RB"],
					["Dash", "Q / RT"],
					["Throw", "F / LT"],
					["Block", "hold RMB / LB"],
					["Ghost", "hold Shift / L3"],
				],
			]
		&"coins":
			return [
				"Treasure", [["Carried", _thousands(player.currency)]],
				"Found in", [["Bone cages", ""], ["Chests", ""]],
			]
		&"bone_fragment", &"skeleton_skull":
			return [
				Inventory.item_kind(id), [["Carried", str(player.inventory.count(id))]],
				"Dropped by", [["Skeletons", "%d%%" % roundi(_drop_chance(id) * 100.0)]],
			]
	var type: ConsumableType = player._consumable_for(id)
	if type != null:
		return [
			"Effect", [["Heals", str(roundi(type.heal_amount))], ["Carried", str(player.inventory.count(id))]],
			"Use", [["Quick wheel", "hold X"], ["Pad", "D-pad"]],
		]
	return ["", [], "", []]


## A skeleton's chance per roll of dropping `id`, read off enemy.gd's defaults.
static func _drop_chance(id: StringName) -> float:
	var enemy_script := load("res://scripts/enemy.gd") as Script
	var odds: Variant = enemy_script.get_property_default_value("drop_odds") if enemy_script else null
	return float((odds as Dictionary).get(id, 0.0)) if odds is Dictionary else 0.0


## A column is [header label, grid]; rows are rebuilt each time.
func _fill_column(column: Array, header: String, rows: Array) -> void:
	var title: Label = column[0]
	var grid: GridContainer = column[1]
	title.text = header
	title.get_parent().visible = header != ""
	for child in grid.get_children():
		child.queue_free()
	for row in rows:
		grid.add_child(_text(row[0], 13, DIM))
		var value := _text(row[1], 13, PARCHMENT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)


## --- The character's numbers -----------------------------------------------------

func _update_bars() -> void:
	if player == null:
		return
	for bar in _bars:
		var fill := 0.0
		var text := ""
		match bar.get_meta("kind"):
			"health":
				fill = player.health / maxf(player.max_health, 1.0)
				text = "%d / %d" % [roundi(player.health), roundi(player.max_health)]
			"ghost":
				fill = player.dodge_charge()
				text = "%d%%" % roundi(fill * 100.0)
			"slam":
				fill = player.slam_charge()
				text = "Ready" if fill >= 1.0 else "%d s" % ceili((1.0 - fill) * player.slam_cooldown)
		bar.set_meta("fill", fill)
		(bar.get_meta("label") as Label).text = text
		bar.queue_redraw()


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


## --- Building ---------------------------------------------------------------------

func _make_fonts() -> void:
	var names := PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
	var serif := SystemFont.new()
	serif.font_names = names
	_serif = serif
	var italic := SystemFont.new()
	italic.font_names = names
	italic.font_italic = true
	_italic = italic
	var spaced := FontVariation.new()
	spaced.base_font = serif
	spaced.spacing_glyph = 3
	_spaced = spaced


func _text(s: String, font_size: int, colour: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = s
	label.add_theme_font_override("font", font if font != null else _serif)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A framed panel: dark, a hairline bronze edge, small gold brackets at its
## corners. Returns [the frame to place, the column to fill].
func _frame(min_size: Vector2, pad := 14.0) -> Array:
	var holder := MarginContainer.new()
	holder.custom_minimum_size = min_size
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = INK
	box.border_color = EDGE
	box.set_border_width_all(1)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	panel.add_theme_stylebox_override("panel", box)
	holder.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var deco := Control.new()
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func() -> void: _draw_corners(deco))
	holder.add_child(deco)
	return [holder, column]


func _draw_corners(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size).grow(-3.0)
	var arm := 12.0
	var colour := Color(GOLD, 0.6)
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x < r.get_center().x else -1.0
		var sy := 1.0 if corner.y < r.get_center().y else -1.0
		c.draw_line(corner, corner + Vector2(arm * sx, 0.0), colour, 1.0)
		c.draw_line(corner, corner + Vector2(0.0, arm * sy), colour, 1.0)
		var d := corner + Vector2(sx, sy) * 4.0
		c.draw_colored_polygon(PackedVector2Array([d + Vector2(0, -2), d + Vector2(2, 0), d + Vector2(0, 2), d + Vector2(-2, 0)]), colour)


func _rule(vertical := false) -> Control:
	var line := ColorRect.new()
	line.color = Color(EDGE, 0.8)
	line.custom_minimum_size = Vector2(1, 0) if vertical else Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _keycap(key: String) -> Control:
	var cap := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.065, 0.06)
	box.border_color = Color(0.55, 0.5, 0.42)
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", box)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(_text(key, 12, PARCHMENT))
	return cap


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# The game stays faintly visible behind: it is not a pause.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Nearly opaque: at 0.86 the HUD's bars and readouts showed through.
	dim.color = Color(0.02, 0.018, 0.016, 0.95)
	# Stop, so a click that misses every slot does not fall through to the game.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 0)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(page)

	page.add_child(_build_header())
	var middle := CenterContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(middle)
	var panels := HBoxContainer.new()
	panels.add_theme_constant_override("separation", 14)
	middle.add_child(panels)
	page.add_child(_build_footer())

	# The weapon wheel is 0-3, the quick-item wheel 4-7 and the bag 8-37.
	_slots.resize(Inventory.SIZE)
	for i in Inventory.SIZE:
		var slot := ItemSlot.new()
		slot.make_ornate(BAG_SLOT if i >= Inventory.HOTBAR else WHEEL_SLOT, _serif)
		_slots[i] = slot
		slot.mouse_entered.connect(func() -> void: _set_hovered(i))
		slot.mouse_exited.connect(func() -> void:
			if _hovered == i:
				_set_hovered(-1))

	panels.add_child(_build_items())
	panels.add_child(_build_card())
	panels.add_child(_build_character())


func _build_header() -> Control:
	var bar := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.028, 0.026, 0.92)
	box.border_color = EDGE
	box.border_width_bottom = 1
	box.content_margin_left = 28
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", box)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	var crest := Control.new()
	crest.custom_minimum_size = Vector2(30, 38)
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.draw.connect(func() -> void: _draw_crest(crest))
	row.add_child(crest)
	var title := _text("INVENTORY", 26, Color(0.9, 0.82, 0.66), _spaced)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	return bar


## A small shield with a sword down it, in the panel gold.
func _draw_crest(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var shield := PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.55), Vector2(w * 0.5, h), Vector2(0, h * 0.55), Vector2(0, 0)])
	c.draw_colored_polygon(shield, Color(0.1, 0.085, 0.06))
	c.draw_polyline(shield, GOLD, 1.5, true)
	c.draw_line(Vector2(w * 0.5, h * 0.12), Vector2(w * 0.5, h * 0.82), GOLD, 2.0)
	c.draw_line(Vector2(w * 0.28, h * 0.32), Vector2(w * 0.72, h * 0.32), GOLD, 2.0)


func _build_footer() -> Control:
	var bar := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.028, 0.026, 0.92)
	box.border_color = EDGE
	box.border_width_top = 1
	box.content_margin_left = 28
	box.content_margin_right = 28
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", box)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	bar.add_child(row)
	for hint in [["Drag / A", "Move"], ["Shift + LMB / X", "Bag / wheel"], ["RMB", "Split"],
			["Q / E  LB / RB", "Category"]]:
		row.add_child(_hint(hint[0], hint[1]))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	row.add_child(_hint("Tab / Esc / B", "Back"))
	return bar


func _hint(key: String, what: String) -> Control:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 8)
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_child(_keycap(key))
	pair.add_child(_text(what, 13, DIM))
	return pair


## --- Left: the bag ----------------------------------------------------------------

func _build_items() -> Control:
	var framed := _frame(Vector2(0, 560))
	var column: VBoxContainer = framed[1]

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	column.add_child(tabs)
	tabs.add_child(_centred(_keycap("Q")))
	for c in CATEGORIES.size():
		var tab := Control.new()
		tab.custom_minimum_size = Vector2(54, 42)
		tab.tooltip_text = CATEGORIES[c][0]
		tab.draw.connect(func() -> void: _draw_tab(tab, c))
		tab.gui_input.connect(func(e: InputEvent) -> void:
			var click := e as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				_set_category(c))
		tabs.add_child(tab)
		_tabs.append(tab)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(gap)
	tabs.add_child(_centred(_keycap("E")))
	column.add_child(_rule())

	_category_label = _text("All Items", 16, PARCHMENT)
	column.add_child(_category_label)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for i in range(Inventory.HOTBAR, Inventory.SIZE):
		grid.add_child(_slots[i])

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(fill)
	column.add_child(_rule())
	var cap := HBoxContainer.new()
	cap.add_theme_constant_override("separation", 10)
	column.add_child(cap)
	var sack := Control.new()
	sack.custom_minimum_size = Vector2(18, 20)
	sack.draw.connect(func() -> void: _draw_sack(sack, Color(0.72, 0.62, 0.46)))
	cap.add_child(sack)
	_capacity_label = _text("0 / %d" % Inventory.BAG, 14, PARCHMENT)
	cap.add_child(_capacity_label)
	_capacity_bar = Control.new()
	_capacity_bar.custom_minimum_size = Vector2(0, 8)
	_capacity_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capacity_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_capacity_bar.draw.connect(func() -> void:
		_draw_bar(_capacity_bar, _capacity, Color(0.62, 0.5, 0.32)))
	cap.add_child(_capacity_bar)
	return framed[0]


func _centred(c: Control) -> Control:
	var box := CenterContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(c)
	return box


## A category tab: its picture, lit and underlined in gold when chosen.
func _draw_tab(tab: Control, c: int) -> void:
	var on := c == _category
	var r := Rect2(Vector2.ZERO, tab.size)
	if on:
		tab.draw_rect(r, Color(0.16, 0.12, 0.07, 0.9))
		tab.draw_line(Vector2(6, r.end.y - 1), Vector2(r.end.x - 6, r.end.y - 1), GOLD, 2.0)
	var tint := Color(1, 1, 1, 1.0 if on else 0.5)
	var s := 30.0
	var o := (tab.size - Vector2(s, s)) * 0.5
	match c:
		0:
			tab.draw_set_transform(o)
			_draw_sack_at(tab, Vector2(s, s), Color(0.8, 0.7, 0.52, tint.a))
			tab.draw_set_transform(Vector2.ZERO)
		_:
			ItemIcon.paint(tab, CATEGORIES[c][2], Rect2(o, Vector2(s, s)), tint)


func _draw_sack(c: Control, colour: Color) -> void:
	_draw_sack_at(c, c.size, colour)


func _draw_sack_at(c: Control, size: Vector2, colour: Color) -> void:
	var w := size.x
	var h := size.y
	var body := PackedVector2Array([
		Vector2(w * 0.32, h * 0.3), Vector2(w * 0.68, h * 0.3), Vector2(w * 0.9, h * 0.7),
		Vector2(w * 0.78, h * 0.95), Vector2(w * 0.22, h * 0.95), Vector2(w * 0.1, h * 0.7)])
	c.draw_colored_polygon(body, colour)
	c.draw_rect(Rect2(w * 0.34, h * 0.18, w * 0.32, h * 0.12), colour.darkened(0.3))
	c.draw_line(Vector2(w * 0.3, h * 0.3), Vector2(w * 0.7, h * 0.3), colour.darkened(0.5), 1.5)


func _draw_bar(c: Control, fraction: float, colour: Color) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.03, 0.028, 0.025))
	var fill := r
	fill.size.x *= clampf(fraction, 0.0, 1.0)
	c.draw_rect(fill, colour)
	c.draw_rect(Rect2(fill.position, Vector2(fill.size.x, maxf(1.0, r.size.y * 0.3))), Color(colour.lightened(0.3), 0.5))
	c.draw_rect(r, Color(EDGE, 0.9), false, 1.0)


## --- Middle: the card ----------------------------------------------------------------

func _build_card() -> Control:
	var framed := _frame(Vector2(372, 560), 18.0)
	var column: VBoxContainer = framed[1]

	_card_empty = _text("Nothing in hand.\nPoint at an item to read about it.", 15, DIM, _italic)
	_card_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_card_empty)

	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 6)
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_card)
	_card_name = _text("", 24, PARCHMENT)
	_card.add_child(_card_name)
	_card_kind = _text("", 15, GOLD)
	_card.add_child(_card_kind)

	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 170)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(func() -> void: _draw_art_back(art))
	_card.add_child(art)
	_card_icon = ItemIcon.new()
	_card_icon.set_anchors_preset(Control.PRESET_CENTER)
	_card_icon.custom_minimum_size = Vector2(150, 150)
	_card_icon.size = Vector2(150, 150)
	_card_icon.position = Vector2(-75, -75)
	art.add_child(_card_icon)
	art.resized.connect(func() -> void: _card_icon.position = art.size * 0.5 - Vector2(75, 75))

	_card_desc = _text("", 14, Color(0.82, 0.78, 0.72))
	_card_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_desc.custom_minimum_size = Vector2(330, 0)
	_card.add_child(_card_desc)
	_card.add_child(_rule())

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	_card.add_child(stats)
	_card_left = _stat_column(stats)
	stats.add_child(_rule(true))
	_card_right = _stat_column(stats)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(fill)
	_card.add_child(_rule())
	_card_quote = _text("", 13, DIM, _italic)
	_card_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_quote.custom_minimum_size = Vector2(330, 0)
	_card.add_child(_card_quote)
	return framed[0]


## A faint ring and rays behind the item's picture, like a seal.
func _draw_art_back(c: Control) -> void:
	var centre := c.size * 0.5
	var r := minf(c.size.x, c.size.y) * 0.46
	c.draw_arc(centre, r, 0.0, TAU, 64, Color(GOLD, 0.12), 1.0, true)
	c.draw_arc(centre, r * 0.82, 0.0, TAU, 64, Color(GOLD, 0.07), 1.0, true)
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(centre + d * r * 0.86, centre + d * r * 1.04, Color(GOLD, 0.1), 1.0)


func _stat_column(parent: Control) -> Array:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	parent.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(8, 8)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.draw.connect(func() -> void:
		mark.draw_colored_polygon(PackedVector2Array([Vector2(4, 0), Vector2(8, 4), Vector2(4, 8), Vector2(0, 4)]), Color(GOLD, 0.8)))
	head.add_child(mark)
	var title := _text("", 14, Color(0.86, 0.8, 0.68))
	head.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	col.add_child(grid)
	return [title, grid]


## --- Right: the character ------------------------------------------------------------

func _build_character() -> Control:
	var framed := _frame(Vector2(318, 560))
	var column: VBoxContainer = framed[1]
	column.add_child(_text("Character", 18, PARCHMENT))

	var figure := Control.new()
	figure.custom_minimum_size = Vector2(0, 126)
	figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
	figure.draw.connect(func() -> void: _draw_figure(figure))
	column.add_child(figure)
	column.add_child(_rule())
	# The two wheels, each as a diamond of four slots in their directions: what
	# the C and R wheels (radial_menu.gd) will offer. The weapon in hand is
	# marked on its wheel.
	var wheels := HBoxContainer.new()
	wheels.add_theme_constant_override("separation", 10)
	wheels.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(wheels)
	wheels.add_child(_wheel_diamond("Weapons", "C", 0))
	wheels.add_child(_wheel_diamond("Quick Items", "X", Inventory.QUICK_FIRST))

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(fill)

	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.032, 0.03, 0.9)
	style.border_color = EDGE
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	box.add_theme_stylebox_override("panel", style)
	column.add_child(box)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	box.add_child(rows)
	_coins_value = _stat_line(rows, &"coins", "Coins")
	_potions_value = _stat_line(rows, &"health_potion", "Potions")
	rows.add_child(_rule())
	_bars.append(_meter(rows, "Health", Color(0.66, 0.13, 0.12), "health"))
	_bars.append(_meter(rows, "Ghost", Color(0.2, 0.36, 0.66), "ghost"))
	_bars.append(_meter(rows, "Slam", Color(0.26, 0.5, 0.24), "slam"))
	return framed[0]


## A wheel's four slots (inventory `first` .. `first` + 3) laid out as the wheel
## lays them out: up, right, down, left round an empty middle, with the wheel's
## name and key above.
func _wheel_diamond(title: String, key: String, first: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(_text(title, 14, PARCHMENT))
	head.add_child(_centred(_keycap(key)))
	box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	box.add_child(grid)
	# Grid cells 1, 5, 7, 3 are up, right, down, left.
	var at := {1: 0, 5: 1, 7: 2, 3: 3}
	for cell in 9:
		if at.has(cell):
			grid.add_child(_slots[first + int(at[cell])])
		else:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(WHEEL_SLOT, WHEEL_SLOT)
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(gap)
	return box


func _stat_line(parent: Control, icon: StringName, label: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var pic := ItemIcon.new()
	pic.item = icon
	pic.custom_minimum_size = Vector2(20, 20)
	row.add_child(pic)
	var name_label := _text(label, 14, PARCHMENT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value := _text("0", 14, PARCHMENT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


## A labelled bar; `_update_bars` fills it while the screen is open.
func _meter(parent: Control, label: String, colour: Color, kind: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var name_label := _text(label, 12, DIM)
	name_label.custom_minimum_size = Vector2(46, 0)
	row.add_child(name_label)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 9)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_meta("kind", kind)
	bar.set_meta("fill", 0.0)
	bar.draw.connect(func() -> void: _draw_bar(bar, float(bar.get_meta("fill")), colour))
	row.add_child(bar)
	var value := _text("", 12, PARCHMENT)
	value.custom_minimum_size = Vector2(58, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	bar.set_meta("label", value)
	return bar


## A dark, faceless figure standing in a dim glow -- the character, without
## pretending to show gear the game does not have.
func _draw_figure(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var mid := w * 0.5
	for i in 6:
		c.draw_circle(Vector2(mid, h * 0.42), h * (0.48 - i * 0.06), Color(0.55, 0.36, 0.18, 0.025))
	var shade := Color(0.012, 0.011, 0.01, 0.95)
	c.draw_circle(Vector2(mid, h * 0.13), h * 0.075, shade)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(mid - w * 0.06, h * 0.19), Vector2(mid + w * 0.06, h * 0.19),
		Vector2(mid + w * 0.24, h * 0.27), Vector2(mid + w * 0.27, h * 0.58),
		Vector2(mid + w * 0.2, h * 0.6), Vector2(mid + w * 0.17, h * 0.36),
		Vector2(mid + w * 0.14, h * 0.55), Vector2(mid + w * 0.13, h * 0.98),
		Vector2(mid + w * 0.02, h * 0.98), Vector2(mid, h * 0.62),
		Vector2(mid - w * 0.02, h * 0.98), Vector2(mid - w * 0.13, h * 0.98),
		Vector2(mid - w * 0.14, h * 0.55), Vector2(mid - w * 0.17, h * 0.36),
		Vector2(mid - w * 0.2, h * 0.6), Vector2(mid - w * 0.27, h * 0.58),
		Vector2(mid - w * 0.24, h * 0.27)]), shade)
