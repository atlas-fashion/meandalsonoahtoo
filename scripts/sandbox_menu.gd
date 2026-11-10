extends CanvasLayer

## The SANDBOX MENU (2026-10-17): "sandbox_menu" (the ` key) opens and closes
## it, only in a sandbox session (sandbox.gd); Escape / B closes it too. Made by
## the maze after the level is built (maze.gd), over sandbox_world.gd.
##
##   SPAWN      a count, then one button per kind (sandbox_world.gd KINDS), each
##              spawning that many in a row in front of the player; Clear
##   SWITCHES   enemies take an interest (aggro) / the player takes damage /
##              the level's own enemies (its normal population, maze `_populate`)
##              / hitboxes / noclip (player.gd `_fly`, note 152)
##   WEAPONS    sword, spear and armor level, 1..UPGRADE_MAX (player.gd)
##   TELEPORT   every place the level built (sandbox_world.gd `destinations`)
##
## Like the workbench screen (workbench.gd): not a pause -- the world runs on
## behind it -- the player's `ui_open` holds their input and the mouse is freed;
## a pause, a cutscene or death closes it. Above the inventory (46), below the
## pause menu (50).
##
## The UI is 720 high however big the screen (project.godot: canvas_items over
## 1280 x 720, so 1720 x 720 at 3440 x 1440) and the columns are taller, so each
## scrolls on its own inside a panel kept on screen (`_fit`, note 152).

const SP := preload("res://scripts/settings_panel.gd")
const SW := preload("res://scripts/sandbox_world.gd")
const PLAYER := preload("res://scripts/player.gd")
## What the panel takes round its columns: borders, margins, title, hint line and
## a gap to the screen's edge.
const PANEL_CHROME := 140.0
## The tallest the columns need; on a tall window the panel stops there.
const COLUMNS_MAX := 780.0

var world: Node3D
var maze: Node3D
var _player: Node
var _root: Control
var _count: SpinBox
var _status: Label
var _aggro: CheckButton
var _damage: CheckButton
var _population: CheckButton
var _hitboxes: CheckButton
var _noclip: CheckButton
var _levels := {}
var _teleports: VBoxContainer
var _scrolls: Array[ScrollContainer] = []
var _first: Control
var _open := false


func setup(sandbox_world: Node3D, owner_maze: Node3D) -> void:
	world = sandbox_world
	maze = owner_maze


func _ready() -> void:
	layer = 47
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	if open == _open:
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return
	if open and _player.get("ui_open"):
		return
	_open = open
	_root.visible = open
	_player.set("ui_open", open)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_refresh()
		_fill_teleports()
		if _first != null:
			_first.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	if not _open:
		return
	if get_tree().paused or _player == null or not is_instance_valid(_player) \
			or _player.get("in_cutscene") or _player.get("_dead"):
		set_open(false)
		return
	_status.text = "%d spawned alive" % world.call("alive_count")


func _input(event: InputEvent) -> void:
	if get_tree().paused or not Sandbox.active:
		return
	if event.is_action_pressed("sandbox_menu"):
		if _open:
			set_open(false)
		else:
			var p := get_tree().get_first_node_in_group("player")
			if p != null and not p.get("in_cutscene") and not p.get("_dead"):
				set_open(true)
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	_aggro.set_pressed_no_signal(not Sandbox.enemies_passive)
	_damage.set_pressed_no_signal(not Sandbox.player_god)
	_population.set_pressed_no_signal(bool(maze.get("sandbox_population")))
	_hitboxes.set_pressed_no_signal(Sandbox.show_hitboxes)
	_noclip.set_pressed_no_signal(Sandbox.noclip)
	for id in _levels:
		var spin: SpinBox = _levels[id]
		var v: int = int(_player.get("armor_level")) if id == &"armor" else int(_player.call("weapon_level", id))
		spin.set_value_no_signal(v)


# --- Layout --------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)
	var outer := SP.panel_box(centre, 1100)
	outer.add_child(SP.title_label("SANDBOX"))
	outer.add_child(SP.dim_label("`  or  Esc / B  to close  --  the world keeps running"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	outer.add_child(cols)
	cols.add_child(_scrolled(_build_spawn()))
	cols.add_child(_scrolled(_build_switches()))
	cols.add_child(_scrolled(_build_teleport()))
	get_viewport().size_changed.connect(_fit)
	_fit()


## A column in its own scroll. `follow_focus` brings what a pad lands on into view.
func _scrolled(col: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	_scrolls.append(scroll)
	return scroll


## Sizes the columns to the screen, as it is now.
func _fit() -> void:
	var room := minf(get_viewport().get_visible_rect().size.y - PANEL_CHROME, COLUMNS_MAX)
	for scroll in _scrolls:
		scroll.custom_minimum_size.y = room


func _column(title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 330
	col.size_flags_vertical = Control.SIZE_FILL
	col.add_theme_constant_override("separation", 6)
	col.add_child(SP.section_label(title))
	return col


func _build_spawn() -> Control:
	var col := _column("SPAWN ENEMIES")
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "How many"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 10
	_count.value = 1
	row.add_child(_count)
	col.add_child(row)
	for entry in SW.KINDS:
		var kind: StringName = entry[0]
		var b := SP.menu_button(entry[1], func() -> void:
			world.call("spawn", kind, int(_count.value)))
		b.custom_minimum_size.y = 32
		if _first == null:
			_first = b
		col.add_child(b)
	col.add_child(SP.spacer(4))
	col.add_child(SP.menu_button("Clear spawned enemies", func() -> void: world.call("clear_spawned")))
	_status = SP.dim_label("")
	col.add_child(_status)
	return col


func _build_switches() -> Control:
	var col := _column("SWITCHES")
	_aggro = _switch("Enemies aggro", func(on: bool) -> void: Sandbox.enemies_passive = not on)
	col.add_child(_aggro)
	_damage = _switch("Player takes damage", func(on: bool) -> void: Sandbox.player_god = not on)
	col.add_child(_damage)
	_population = _switch("Level's own enemies", func(on: bool) -> void:
		maze.call("set_sandbox_population", on))
	col.add_child(_population)
	_hitboxes = _switch("Show hitboxes", func(on: bool) -> void: Sandbox.show_hitboxes = on)
	col.add_child(_hitboxes)
	_noclip = _switch("Noclip (fly through walls)", _set_noclip)
	col.add_child(_noclip)
	col.add_child(SP.dim_label("Fly where you look: WASD, Space up, Ctrl down,\nShift faster (pad: A up, B down, stick all the way)"))
	col.add_child(SP.spacer(10))
	col.add_child(SP.section_label("WEAPON LEVELS"))
	for entry in [[&"sword", "Sword"], [&"spear", "Spear"], [&"armor", "Armor"]]:
		var id: StringName = entry[0]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = entry[1]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = PLAYER.UPGRADE_MAX
		spin.value_changed.connect(func(v: float) -> void: _set_level(id, int(v)))
		row.add_child(spin)
		_levels[id] = spin
		col.add_child(row)
	col.add_child(SP.dim_label("Each level: +8% weapon damage, +4% armor"))
	# GIVE (2026-10-18): the utility items and what the workbench wants, to try
	# the rats without catching one first.
	col.add_child(SP.spacer(10))
	col.add_child(SP.section_label("GIVE ITEMS"))
	# Heals (note 117): health back to full at once, or potions to drink.
	var full := SP.menu_button("Heal to full", func() -> void:
		if _player != null and is_instance_valid(_player):
			_player.call("heal", float(_player.get("max_health"))))
	full.custom_minimum_size.y = 32
	col.add_child(full)
	for entry in [[&"health_potion", 5, "5 health potions"], [&"small_health_potion", 5, "5 small health potions"],
			[&"live_rat", 1, "Live rat"],
			[&"robot_rat", 1, "Robot rat"], [&"gold_crystal", 10, "10 gold crystals"]]:
		var id: StringName = entry[0]
		var n: int = entry[1]
		var b := SP.menu_button(entry[2], func() -> void:
			if _player != null and is_instance_valid(_player):
				_player.call("add_item", id, n))
		b.custom_minimum_size.y = 32
		col.add_child(b)
	return col


func _switch(text: String, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.toggled.connect(on_toggle)
	return c


func _set_noclip(on: bool) -> void:
	Sandbox.noclip = on
	if not on and _player != null and is_instance_valid(_player):
		world.call("land_from_noclip", _player)


func _set_level(id: StringName, level: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	level = clampi(level, 1, PLAYER.UPGRADE_MAX)
	if id == &"armor":
		_player.set("armor_level", level)
	else:
		var levels: Dictionary = _player.get("weapon_levels")
		levels[id] = level
	_player.emit_signal("inventory_changed")


func _build_teleport() -> Control:
	var col := _column("TELEPORT")
	col.add_child(SP.dim_label("Or anywhere: on the map (M), T / Y\nteleports to the cursor or the pin under it"))
	_teleports = VBoxContainer.new()
	_teleports.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_teleports.add_theme_constant_override("separation", 4)
	col.add_child(_teleports)
	return col


## Listed fresh on every opening (a room's kind is known only once built).
func _fill_teleports() -> void:
	for c in _teleports.get_children():
		c.queue_free()
	for d in world.call("destinations"):
		var at: Vector3 = d[1]
		var yaw: float = d[2]
		var b := SP.menu_button(d[0], func() -> void:
			set_open(false)
			world.call("teleport", at, yaw))
		b.custom_minimum_size.y = 32
		_teleports.add_child(b)
