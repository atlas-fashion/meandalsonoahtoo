extends CanvasLayer

## The SANDBOX MENU (2026-10-17): "sandbox_menu" (the ` key) opens and closes
## it, only in a sandbox session (sandbox.gd); Escape / B closes it too. Made by
## the maze after the level is built (maze.gd), over sandbox_world.gd.
##
##   SPAWN      a count, then one button per kind (sandbox_world.gd KINDS), each
##              spawning that many in a row in front of the player; Clear
##   SWITCHES   enemies take an interest (aggro) / the player takes damage /
##              the level's own enemies (its normal population, maze `_populate`)
##   WEAPONS    sword, spear and armor level, 1..UPGRADE_MAX (player.gd)
##   TELEPORT   every place the level built (sandbox_world.gd `destinations`)
##
## Like the workbench screen (workbench.gd): not a pause -- the world runs on
## behind it -- the player's `ui_open` holds their input and the mouse is freed;
## a pause, a cutscene or death closes it. Above the inventory (46), below the
## pause menu (50).

const SP := preload("res://scripts/settings_panel.gd")
const SW := preload("res://scripts/sandbox_world.gd")
const PLAYER := preload("res://scripts/player.gd")

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
var _levels := {}
var _teleports: VBoxContainer
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
	cols.add_child(_build_spawn())
	cols.add_child(_build_switches())
	cols.add_child(_build_teleport())


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
	return col


func _switch(text: String, on_toggle: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.toggled.connect(on_toggle)
	return c


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
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_teleports = VBoxContainer.new()
	_teleports.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_teleports.add_theme_constant_override("separation", 4)
	scroll.add_child(_teleports)
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
