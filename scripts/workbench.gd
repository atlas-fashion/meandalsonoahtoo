extends Node3D

## The workbench in the crystal mine (2026-10-11): a heavy plank bench with an
## anvil at one end, a grinding wheel at the other, tools, and a tray of gold
## crystals -- built from primitives (no Tripo). Aim at it and press E
## ("interact") to open it: gold crystals buy levels for each weapon carried
## (more damage) and for the armor (less damage taken). The numbers live on
## the player (`player.upgrade`, `weapon_damage_scale`, `damage_negation`,
## `upgrade_cost`); this is the bench and its screen.
##
## Local frame: the bench runs along X, its front (where the player stands)
## faces +Z, origin on the floor at its middle.

const PLAYER := preload("res://scripts/player.gd")

const REACH := 2.6
const LENGTH := 2.2
const DEPTH := 0.85
const TOP := 0.92

var _player: Node3D
var _prompt: Interact.Prompt
var _near := false
var _wheel: Node3D
var _spin := 0.0

var _screen: CanvasLayer
var _rows: Array = []        # [{what, name, level, effect, cost, button}]
var _crystals_label: Label
var _serif: Font


func _ready() -> void:
	add_to_group(&"workbench")
	_build()
	_prompt = Interact.prompt("E   Workbench", Vector3(0.0, 1.3, DEPTH * 0.5))
	add_child(_prompt)


func is_open() -> bool:
	return _screen != null and _screen.visible


func _process(delta: float) -> void:
	if _wheel != null:
		_spin = move_toward(_spin, 0.0, delta * 3.0)
		_wheel.rotation.z -= delta * (0.4 + _spin * 14.0)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	if is_open():
		# Something took the screen (death, a scene, the pause menu): shut it.
		if get_tree().paused or _player.get("in_cutscene") or _player.get("_dead"):
			_close()
		return
	var to := _player.global_position - global_position
	_near = Vector2(to.x, to.z).length() <= REACH and absf(to.y) < 1.5 \
		and not _player.get("in_cutscene") and not _player.get("ui_open") \
		and Interact.looked_at(self, 3.4, 0.1)
	_prompt.visible = _near


func _unhandled_input(event: InputEvent) -> void:
	if is_open() or not _near or not Interact.pressed(event):
		return
	get_viewport().set_input_as_handled()
	_open()


## The screen hangs LAST under the root, so it sees input before the pause
## menu (Escape is both "pause" and "ui_cancel") and the inventory (Tab).
class Screen extends CanvasLayer:
	var bench: Node

	func _input(event: InputEvent) -> void:
		if visible and is_instance_valid(bench):
			bench._screen_input(event)


func _screen_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") \
			or event.is_action_pressed("inventory") or Interact.pressed(event):
		_close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _screen != null and is_instance_valid(_screen):
		_close()
		_screen.queue_free()
		_screen = null


# --- The screen ------------------------------------------------------------------

func _open() -> void:
	if _screen == null:
		_build_screen()
	_screen.visible = true
	_prompt.visible = false
	_player.set("ui_open", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	# A pad works it by focus: the first upgrade that can be bought.
	for row in _rows:
		var b: Button = row["button"]
		if b.visible and not b.disabled:
			b.grab_focus()
			break


func _close() -> void:
	if _screen == null or not _screen.visible:
		return
	_screen.visible = false
	var f := get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()
	if is_instance_valid(_player):
		_player.set("ui_open", false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## What the bench can work on: every upgradable weapon carried, and the armor.
func _choices() -> Array[StringName]:
	var out: Array[StringName] = []
	var inv = _player.get("inventory")
	for id: StringName in PLAYER.UPGRADABLE:
		if inv.find(id) >= 0:
			out.append(id)
	out.append(&"armor")
	return out


func _refresh() -> void:
	var inv = _player.get("inventory")
	var have: int = inv.count(&"gold_crystal")
	_crystals_label.text = "Gold crystals:  %d" % have
	var choices := _choices()
	var top: int = PLAYER.UPGRADE_MAX
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var shown := i < choices.size()
		(row["box"] as Control).visible = shown
		if not shown:
			continue
		var what: StringName = choices[i]
		row["what"] = what
		var level: int = _player.get("armor_level") if what == &"armor" else _player.call("weapon_level", what)
		(row["name"] as Label).text = "Armor" if what == &"armor" else Inventory.item_name(what)
		var effect := ""
		if what == &"armor":
			var now := roundi(float(_player.call("damage_negation")) * 100.0)
			var step := roundi(float(PLAYER.ARMOR_STEP) * 100.0)
			effect = "Damage taken  -%d%%" % now + ("" if level >= top else "   ->   -%d%%" % (now + step))
		else:
			var now := roundi((float(_player.call("weapon_damage_scale", what)) - 1.0) * 100.0)
			var step := roundi(float(PLAYER.UPGRADE_DAMAGE) * 100.0)
			effect = "Damage  +%d%%" % now + ("" if level >= top else "   ->   +%d%%" % (now + step))
		(row["level"] as Label).text = "Level %d" % level + ("  (max)" if level >= top else "")
		(row["effect"] as Label).text = effect
		var b: Button = row["button"]
		if level >= top:
			(row["cost"] as Label).text = ""
			b.text = "Mastered"
			b.disabled = true
		else:
			var cost: int = _player.call("upgrade_cost", level)
			(row["cost"] as Label).text = "%d gold crystals" % cost
			(row["cost"] as Label).add_theme_color_override("font_color",
				GOLD if have >= cost else Color(0.6, 0.35, 0.3))
			b.text = "Upgrade"
			b.disabled = have < cost


func _upgrade(i: int) -> void:
	var what: StringName = _rows[i]["what"]
	if not _player.call("upgrade", what):
		return
	_spin = 1.0
	var level: int = _player.get("armor_level") if what == &"armor" else _player.call("weapon_level", what)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("announce"):
		var title := "ARMOR" if what == &"armor" else Inventory.item_name(what).to_upper()
		hud.announce("%s  LEVEL %d" % [title, level], "Tempered at the workbench")
	if _player.has_method("_guard_flash"):
		_player.call("_guard_flash", to_global(Vector3(LENGTH * 0.38, TOP + 0.45, 0.0)), GOLD, false)
	_refresh()
	var b: Button = _rows[i]["button"]
	if b.disabled:
		for row in _rows:
			var other: Button = row["button"]
			if other.visible and not other.disabled:
				other.grab_focus()
				return


const GOLD := Color(0.95, 0.74, 0.3)
const PARCHMENT := Color(0.9, 0.86, 0.78)
const DIM := Color(0.62, 0.58, 0.52)


func _build_screen() -> void:
	_serif = SystemFont.new()
	_serif.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman"])
	_screen = Screen.new()
	_screen.bench = self
	_screen.layer = 46
	get_tree().root.add_child(_screen)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.018, 0.016, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_screen.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(centre)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.055, 0.05, 0.97)
	box.border_color = Color(0.45, 0.36, 0.22)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(640, 0)
	panel.add_child(column)
	column.add_child(_label("WORKBENCH", 30, GOLD))
	_crystals_label = _label("", 18, PARCHMENT)
	column.add_child(_crystals_label)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(0.45, 0.36, 0.22, 0.8)
	column.add_child(rule)
	_rows.clear()
	for i in PLAYER.UPGRADABLE.size() + 1:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		column.add_child(row)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 2)
		row.add_child(left)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		left.add_child(head)
		var name_label := _label("", 22, PARCHMENT)
		head.add_child(name_label)
		var level := _label("", 16, GOLD)
		level.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(level)
		var effect := _label("", 15, DIM)
		left.add_child(effect)
		var cost := _label("", 15, GOLD)
		left.add_child(cost)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 46)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_override("font", _serif)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_upgrade.bind(i))
		row.add_child(b)
		_rows.append({"box": row, "what": &"", "name": name_label, "level": level, "effect": effect,
			"cost": cost, "button": b})
	column.add_child(_label("Esc / B / E: close", 14, DIM))
	_screen.visible = false


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _serif)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


# --- The bench ---------------------------------------------------------------------

func _build() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load("res://textures/wood_door_albedo.png")
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(1.2, 1.2, 1.2)
	wood.albedo_color = Color(0.5, 0.4, 0.31)
	wood.roughness = 0.9
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.19, 0.19)
	iron.metallic = 0.5
	iron.roughness = 0.55
	var stone := StandardMaterial3D.new()
	# Dark on purpose: a plain light grey blew out to flat pink under the
	# court's red sky light.
	stone.albedo_color = Color(0.24, 0.225, 0.21)
	stone.roughness = 0.95
	stone.normal_enabled = true
	stone.normal_texture = load("res://textures/stone_plain_normal.png")
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3(2.0, 2.0, 2.0)
	var gem := StandardMaterial3D.new()
	gem.albedo_color = Color(0.6, 0.42, 0.1)
	gem.emission_enabled = true
	gem.emission = Color(1.0, 0.72, 0.2)
	gem.emission_energy_multiplier = 2.4
	gem.roughness = 0.2

	var h := LENGTH * 0.5
	var d := DEPTH * 0.5
	_box(Vector3(LENGTH, 0.12, DEPTH), Vector3(0.0, TOP - 0.06, 0.0), wood)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(0.13, TOP - 0.12, 0.13), Vector3(sx * (h - 0.12), (TOP - 0.12) * 0.5, sz * (d - 0.1)), wood)
		# Iron corner straps on the top.
		_box(Vector3(0.06, 0.14, DEPTH + 0.02), Vector3(sx * (h - 0.02), TOP - 0.06, 0.0), iron)
	_box(Vector3(LENGTH - 0.3, 0.06, DEPTH - 0.2), Vector3(0.0, 0.24, 0.0), wood)
	# The anvil, on a stone block at the left end.
	_box(Vector3(0.34, 0.3, 0.3), Vector3(-h + 0.32, TOP + 0.15, 0.0), stone)
	_box(Vector3(0.6, 0.16, 0.22), Vector3(-h + 0.32, TOP + 0.38, 0.0), iron)
	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.08
	horn.height = 0.3
	horn.radial_segments = 10
	_part(horn, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-h + 0.32 + 0.44, TOP + 0.4, 0.0)), iron)
	# The grinding wheel, on two posts at the right end, with its crank.
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(0.06, 0.5, 0.06), Vector3(h - 0.38, TOP + 0.25, sz * 0.12), wood)
	_wheel = Node3D.new()
	_wheel.position = Vector3(h - 0.38, TOP + 0.46, 0.0)
	add_child(_wheel)
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.3
	wheel.bottom_radius = 0.3
	wheel.height = 0.1
	wheel.radial_segments = 20
	_part(wheel, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), stone, _wheel)
	var axle := CylinderMesh.new()
	axle.top_radius = 0.025
	axle.bottom_radius = 0.025
	axle.height = 0.4
	axle.radial_segments = 6
	_part(axle, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), iron, _wheel)
	_box(Vector3(0.04, 0.2, 0.04), Vector3(0.0, -0.1, 0.2), iron, _wheel)
	# A hammer and tongs, lying on the top.
	var tools := Node3D.new()
	tools.position = Vector3(-0.2, TOP, 0.12)
	tools.rotation.y = 0.35
	add_child(tools)
	_box(Vector3(0.04, 0.04, 0.42), Vector3(0.0, 0.02, 0.0), wood, tools)
	_box(Vector3(0.16, 0.07, 0.07), Vector3(0.0, 0.035, -0.22), iron, tools)
	for s: float in [-1.0, 1.0]:
		var leg := _box(Vector3(0.025, 0.02, 0.5), Vector3(0.34 + s * 0.03, 0.01, 0.02), iron, tools)
		leg.rotation.y = s * 0.08
	# The tray of gold crystals.
	_box(Vector3(0.42, 0.05, 0.26), Vector3(0.38, TOP + 0.025, -0.18), wood)
	for k in 5:
		var g := SphereMesh.new()
		g.radius = 0.035 + 0.01 * float(k % 2)
		g.height = 0.14 + 0.03 * float(k % 3)
		g.radial_segments = 4
		g.rings = 2
		var at := Vector3(0.24 + float(k) * 0.07, TOP + 0.09, -0.18 + (0.05 if k % 2 == 0 else -0.04))
		_part(g, Transform3D(Basis.from_euler(Vector3(0.3 * float(k % 2) - 0.15, float(k), 0.2)), at), gem)
	# Solid: the player and the enemies walk round it (built before the bake).
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2
	body.collision_mask = 0
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(LENGTH + 0.1, TOP + 0.6, DEPTH + 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, (TOP + 0.6) * 0.5, 0.0)
	body.add_child(cs)


func _box(size: Vector3, at: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _part(b, Transform3D(Basis(), at), mat, parent)


func _part(mesh: Mesh, xf: Transform3D, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
