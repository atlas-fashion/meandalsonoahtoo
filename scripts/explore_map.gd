extends CanvasLayer

## A dungeon map that fills in as the player walks the maze: a small north-up
## minimap in the top-right corner, and a full map that is a PAGE of the
## inventory (inventory_screen.gd; "toggle_map", M or Select, opens it there --
## since 2026-10-17, when the ` key went to the sandbox menu). Built from `module_level.gd`'s `Built` data -- see
## `setup()`. The full map is worked with a cursor -- zoomed, panned and marked
## by the player; see "The full map" below.
##
## ## Reveal / line of sight
##
## A cell is revealed once the player has stood in it, OR once the player's
## current cell has a straight, unbroken run of open connections to it (a
## sightline down a corridor, up to `SIGHT_RANGE_CELLS` cells). The test at
## every step is the cell's own `open` bitmask -- the real connectivity the
## level was built from -- so a sightline stops dead at the first wall and
## never leaks through one. Entering a room (cloister) reveals the room's
## whole footprint at once, because standing anywhere in an open courtyard
## already shows the rest of it. Revealed cells persist in `_revealed` for as
## long as this node lives, i.e. for the session.
##
## ## Rendering
##
## The revealed set is painted into one Image (near-black background, amber
## wall outlines, a dark red centreline, coloured dots for junctions/rooms/
## gates) ONLY when a new cell is revealed -- see `_rebuild_map_image()`. Both
## the minimap and the full map read that same baked texture: the minimap
## wraps it in an AtlasTexture and just slides the crop `region` to follow the
## player every frame (a Rect2 assignment, not a redraw), and the full map
## displays it whole. The only per-frame work besides that slide is moving
## and rotating the two small marker triangles. Nothing here touches
## `Input.mouse_mode`, and this never sets `get_tree().paused` itself -- it
## only polls it, every frame (`process_mode = PROCESS_MODE_ALWAYS`), so the
## full map can force itself shut the instant something else pauses the
## game, instead of freezing open underneath the pause menu.
##
## ## Integration
##
##   var map = preload("res://scripts/explore_map.gd").new()
##   hud_or_canvas.add_child(map)
##   map.setup(module_level_built, player_node)
##
## `module_level_built` is the `ModuleLevel.Built` the maze already built
## (`cells`, `rooms`, `gates`, `origin`, `cell_size`, `size`). `player_node`
## needs only `global_position` and `global_basis` (or `rotation.y`).

const ModuleMaze := preload("res://scripts/module_maze.gd")

## Pixels per grid cell in the baked map image.
const PPC := 16
## Empty border baked into the image so the minimap's crop window never has
## to sample outside it, however close the player stands to the map's edge.
const MARGIN_CELLS := 8
## How far a sightline is allowed to run down a straight, unbroken corridor.
const SIGHT_RANGE_CELLS := 20
## Inset, in px, standing in for wall thickness inside a cell's footprint.
const WALL_PAD := 3

const MINIMAP_SIZE := 200.0
const MINIMAP_MARGIN := 18.0
## World metres visible across the minimap (falls inside the requested
## 40-60 m band).
const MINIMAP_SPAN_M := 50.0
## Fraction of the shorter viewport side the full map overlay occupies.
const FULLMAP_FRACTION := 0.82

const COL_BG := Color(0.018, 0.017, 0.02)
const COL_FLOOR := Color(0.05, 0.045, 0.04)
const COL_CENTERLINE := Color(0.22, 0.045, 0.04)
const COL_WALL := Color(0.82, 0.5, 0.16)
const COL_PLAYER := Color(1.0, 0.15, 0.1)
const COL_MARKER_OUTLINE := Color(0.05, 0.04, 0.04)


## A small triangle that always draws about its own (0, 0), so rotating the
## Control it belongs to turns the arrow in place. This is the only bright
## red thing the map ever draws. A dark outline, and ~2 px more size than
## before at every station, keeps it legible against the red centrelines
## inside rooms.
class MarkerControl extends Control:
	var marker_color := COL_PLAYER
	var marker_size := 6.0

	func _draw() -> void:
		var s := marker_size + 2.0
		_draw_triangle(s + 1.6, COL_MARKER_OUTLINE)
		_draw_triangle(s, marker_color)

	func _draw_triangle(s: float, color: Color) -> void:
		var pts := PackedVector2Array([
			Vector2(0.0, -s),
			Vector2(s * 0.62, s * 0.8),
			Vector2(-s * 0.62, s * 0.8),
		])
		draw_colored_polygon(pts, color)


var _built = null
var _player: Node3D = null

## Vector2i -> true. The set of cells the player has visited or seen.
var _revealed := {}
var _revealed_dirty := false
## Sentinel so the very first `_process` always runs a reveal pass.
var _last_cell := Vector2i(-999999, -999999)

var _img_w := 0
var _img_h := 0
var _map_texture: ImageTexture = null
var _atlas: AtlasTexture = null

var _full_open := false
## Shown as the inventory's Map page: the inventory owns the screen (ui_open,
## the keys that open and close it); the map keeps its own panning, zoom, pins.
var _embedded := false
var _hints: Label = null
## Tracks `get_tree().paused` frame to frame so the full map can be forced
## shut the instant the game pauses, whatever paused it (the pause menu's
## Esc handling lives in `pause_menu.gd`, which this file must not touch --
## polling `get_tree().paused` here works no matter what sets it).
var _was_paused := false
## Current side length (px) of the full-map panel, cached so the marker
## placement math and the texture layout agree on the same number.
var _full_side := 0.0

var _minimap_root: Control = null
var _mini_texture_rect: TextureRect = null
var _mini_marker: MarkerControl = null

var _full_root: Control = null
var _full_panel: Control = null
var _full_texture_rect: TextureRect = null
var _full_marker: MarkerControl = null


func _ready() -> void:
	layer = 45  # above the HUD (1), below the pause menu (50).
	# Same trick pause_menu.gd uses on itself: without this, the whole
	# CanvasLayer freezes the instant get_tree().paused goes true (inherited
	# process mode), so nothing here could ever notice the pause and close
	# the full map -- it would stay open, frozen, underneath the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"explore_map")
	_build_ui()


## Hands the map the level it should draw and the node to track.
func setup(built, player: Node3D) -> void:
	_built = built
	_player = player
	_index_doors()
	_revealed.clear()
	_revealed_dirty = false
	_last_cell = Vector2i(-999999, -999999)
	_img_w = (_built.size.x + MARGIN_CELLS * 2) * PPC
	_img_h = (_built.size.y + MARGIN_CELLS * 2) * PPC
	# Prime the map with wherever the player starts, so the minimap is not
	# blank for the first frame.
	_update_reveal()
	_update_marker_transforms()
	if player.has_signal("currency_changed"):
		if not player.currency_changed.is_connected(_on_currency_changed):
			player.currency_changed.connect(_on_currency_changed)
		_currency_label.text = str(int(player.get("currency")))


func _process(delta: float) -> void:
	var paused := get_tree().paused
	# Fires once on the frame the game pauses, regardless of what paused it
	# (pause menu, Esc, anything else) -- see `_was_paused`'s comment.
	if paused and not _was_paused and _full_open:
		set_full_map_open(false)
	_was_paused = paused
	if paused:
		return
	if _built == null or not is_instance_valid(_player):
		return
	# Something else took the screen (a scene, death): the map shuts.
	if _full_open and (_player.get("in_cutscene") or _player.get("_dead")):
		set_full_map_open(false)
	_check_level()
	_update_reveal()
	_update_marker_transforms()
	_pad_map(delta)


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	# Typing a note: every key is the note's, the map key included.
	if editor_open() and _editor_note.has_focus() and event is InputEventKey:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE and event.pressed:
			_close_editor()
			get_viewport().set_input_as_handled()
		return
	# Escape closes the note editor; otherwise, embedded, it is the inventory's
	# (it closes the whole screen). Opening and closing is the inventory's too.
	if _full_open and event.is_action_pressed("ui_cancel"):
		if editor_open():
			_close_editor()
		elif not _embedded:
			set_full_map_open(false)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if _full_open and not editor_open():
		_map_input(event)


## Public so a harness (or another system) can drive it without faking input.
## `embedded`: as the inventory's Map page (inventory_screen.gd), which owns
## the player's ui_open and leaves room for its header and footer.
func set_full_map_open(open: bool, embedded := false) -> void:
	if open and not embedded and _player != null and is_instance_valid(_player) 			and _player.get("ui_open") and not _took_ui:
		# Another screen (the inventory) is up.
		return
	_full_open = open
	_embedded = open and embedded
	if _hints != null:
		# Embedded, the inventory's footer carries the map's keys.
		_hints.visible = not _embedded
	if _full_title != null:
		_full_title.offset_top = 66 if _embedded else 58
	if _full_root != null:
		_full_root.visible = open
	# The two views fight for attention otherwise -- the reference has one
	# map on screen at a time.
	if _minimap_root != null:
		_minimap_root.visible = not open
	# The player stops taking input while it is open (not a pause). The mouse
	# stays captured: it moves the MAP under a cursor fixed in the middle
	# (2026-10-11); only the mark editor frees it.
	if _player != null and is_instance_valid(_player) and not embedded:
		if open and not _took_ui:
			_player.set("ui_open", true)
			_took_ui = true
		elif not open and _took_ui:
			_player.set("ui_open", false)
			_took_ui = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif embedded and open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not open:
		_close_editor()
		_pressed = false
		_dragging = false
	if open:
		_position_full_panel()
		# Centred on the player, a little way in.
		if _built != null and is_instance_valid(_player):
			_centre_px = _continuous_px(_player.global_position)
			_zoom = clampf(maxf(_zoom, 2.0), ZOOM_MIN, ZOOM_MAX)
			# Off the map altogether (the sandbox's test plane): the whole
			# dungeon, centred, instead of an empty panel.
			if _centre_px.x < 0.0 or _centre_px.y < 0.0 or _centre_px.x > float(_img_w) or _centre_px.y > float(_img_h):
				_centre_px = Vector2(_img_w, _img_h) * 0.5
				_zoom = clampf(1.0, ZOOM_MIN, ZOOM_MAX)
		_layout_full_texture()
		_update_marker_transforms()


func is_cell_revealed(pos: Vector2i) -> bool:
	return _revealed.has(pos)


func revealed_count() -> int:
	return _revealed.size()


## What has been mapped so far, to be put back later: a respawn anchor takes
## one when it is attuned, and dying restores it -- everything charted since
## the checkpoint is forgotten.
func snapshot() -> Dictionary:
	if _level != &"dungeon" and _stored.has(&"dungeon"):
		return (_stored[&"dungeon"]["revealed"] as Dictionary).duplicate()
	return _revealed.duplicate()


## Hiding places the player has emptied: world position -> along-wall axis.
## Kept apart from what is charted, so dying does not forget them (the coffin is
## still empty); each is drawn only while its cell is charted.
var _hiding_marks := {}


func mark_hiding_place(world: Vector3, along: Vector3) -> void:
	_hiding_marks[world] = along
	if _built != null:
		_rebuild_map_image()


func hiding_place_marked(world: Vector3) -> bool:
	return _hiding_marks.has(world)


func restore(snap: Dictionary) -> void:
	if _level != &"dungeon" and _stored.has(&"dungeon"):
		_stored[&"dungeon"]["revealed"] = snap.duplicate()
		return
	_revealed = snap.duplicate()
	# Redrawn now, and wherever the player stands is charted again next frame.
	_rebuild_map_image()
	_revealed_dirty = false
	_last_cell = Vector2i(-999999, -999999)


## --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.name = "ExploreMapRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_minimap(root)
	_build_currency(root)
	_build_full_map(root)


func _build_minimap(root: Control) -> void:
	var box := Control.new()
	box.name = "Minimap"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = -(MINIMAP_MARGIN + MINIMAP_SIZE)
	box.offset_right = -MINIMAP_MARGIN
	box.offset_top = MINIMAP_MARGIN
	box.offset_bottom = MINIMAP_MARGIN + MINIMAP_SIZE
	root.add_child(box)
	_minimap_root = box

	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.border_color = COL_WALL
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_frame_styles.append(style)
	frame.add_theme_stylebox_override("panel", style)
	box.add_child(frame)

	# The crop turns with the player (2026-10-11): the picture is drawn
	# MINI_SPIN_PAD larger than the frame and rotated about its middle, inside a
	# clip 2 px in from the frame's border, so no corner ever shows past it.
	var clip := Control.new()
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	clip.position = Vector2(2, 2)
	clip.size = Vector2(MINIMAP_SIZE - 4.0, MINIMAP_SIZE - 4.0)
	box.add_child(clip)
	var tex := TextureRect.new()
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var inner := MINIMAP_SIZE - 4.0
	tex.size = Vector2(inner, inner) * MINI_SPIN_PAD
	tex.position = (Vector2(inner, inner) - tex.size) * 0.5
	tex.pivot_offset = tex.size * 0.5
	clip.add_child(tex)
	_mini_texture_rect = tex

	# The player's marks, over the minimap's crop (clipped to its frame).
	_mini_marks = Control.new()
	_mini_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mini_marks.clip_contents = true
	_mini_marks.draw.connect(_draw_mini_marks)
	box.add_child(_mini_marks)

	_mini_marker = MarkerControl.new()
	_mini_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini_marker.size = Vector2(1, 1)
	_mini_marker.position = Vector2(MINIMAP_SIZE * 0.5, MINIMAP_SIZE * 0.5)
	box.add_child(_mini_marker)

	# Which map this is, when it is not the dungeon's.
	_level_label = Label.new()
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.add_theme_font_size_override("font_size", 13)
	_level_label.add_theme_color_override("font_color", COL_SEWER_WALL)
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_level_label.add_theme_constant_override("outline_size", 4)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.position = Vector2(0.0, MINIMAP_SIZE - 24.0)
	_level_label.size = Vector2(MINIMAP_SIZE, 20.0)
	_level_label.visible = false
	box.add_child(_level_label)


var _mini_marks: Control = null
## The minimap's crop is this much bigger than its frame, so it can turn.
const MINI_SPIN_PAD := 1.45
## How far the minimap is turned (the player's facing; heading up).
var _mini_spin := 0.0


func _draw_mini_marks() -> void:
	if _atlas == null or _built == null or not is_instance_valid(_player):
		return
	var region := _atlas.region
	if region.size.x <= 0.0:
		return
	var k := (MINIMAP_SIZE - 4.0) * MINI_SPIN_PAD / region.size.x
	var c := Vector2(MINIMAP_SIZE, MINIMAP_SIZE) * 0.5
	var me := _continuous_px(_player.global_position)
	for pin: Dictionary in _pins:
		# Pins are for the full map only; marks show here too.
		if pin.get("quick", false) or not _pin_on_level(pin):
			continue
		var at := c + ((_pin_px(pin) - me) * k).rotated(-_mini_spin)
		if Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)).grow(-4.0).has_point(at):
			_draw_mark(_mini_marks, at, pin["color"], int(pin.get("shape", 0)), 0.7)
	# North, on the rim: where the map's top has turned to.
	var north := c + Vector2(0.0, -(MINIMAP_SIZE * 0.5 - 13.0)).rotated(-_mini_spin)
	var font := ThemeDB.fallback_font
	_mini_marks.draw_circle(north, 9.0, Color(0.03, 0.025, 0.02, 0.85))
	_mini_marks.draw_string(font, north + Vector2(-5.0, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COL_WALL)


## --- Currency ---------------------------------------------------------------
##
## Treasure looted from the bone cages, shown just under the minimap: a gold
## coin and the running total, which gives a small pulse when it goes up.

var _currency_label: Label = null
var _currency_row: Control = null


class CoinIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(0.55, 0.36, 0.08))
		draw_circle(c, r * 0.8, Color(1.0, 0.76, 0.28))
		draw_circle(c + Vector2(-r * 0.25, -r * 0.25), r * 0.22, Color(1.0, 0.92, 0.6))


func _build_currency(root: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "Currency"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 1.0
	row.anchor_right = 1.0
	row.offset_left = -(MINIMAP_MARGIN + MINIMAP_SIZE)
	row.offset_right = -MINIMAP_MARGIN
	row.offset_top = MINIMAP_MARGIN + MINIMAP_SIZE + 8.0
	row.offset_bottom = MINIMAP_MARGIN + MINIMAP_SIZE + 40.0
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	var coin := CoinIcon.new()
	coin.custom_minimum_size = Vector2(22, 22)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin)
	var label := Label.new()
	label.text = "0"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.01))
	label.add_theme_constant_override("outline_size", 6)
	row.add_child(label)
	_currency_label = label
	_currency_row = row


func _on_currency_changed(total: int, _gained: int) -> void:
	if _currency_label == null:
		return
	_currency_label.text = str(total)
	_currency_label.pivot_offset = _currency_label.size * 0.5
	var tween := create_tween()
	tween.tween_property(_currency_label, "scale", Vector2.ONE * 1.35, 0.1)
	tween.tween_property(_currency_label, "scale", Vector2.ONE, 0.25)


## --- The full map (2026-10-10) -----------------------------------------------------
##
## A cursor over the map rather than a fixed picture: the scroll wheel (or the
## right stick up / down on a pad) zooms in and out about the cursor, dragging
## pans; a LEFT click drops a plain pin (full map only, no note; again to lift
## it), a RIGHT click marks the map -- a pin, a cross or a ring, in a colour the
## player picks, with a short note (`_open_editor`). A click on a mark opens it
## again to change or delete. Marks are kept in world space (`_pins`), saved
## with the game (maze.gd), not forgotten by a death, and drawn on the minimap
## too. The map draws no icons of its own any more -- no junctions, rooms,
## gates or hiding places: only the walls, the player's arrow and the player's
## own marks.
##
## While it is open the mouse is free and the player stops taking input (it is
## not a pause). On a pad the cursor comes from pad.gd (the left stick moves
## it, A clicks), it pans the map when pushed against the edge, and B closes.

const ZOOM_MIN := 1.0
const ZOOM_MAX := 10.0
const ZOOM_STEP := 1.2
## Right stick: how fast a full push zooms (per second, as a power of e).
const PAD_ZOOM_RATE := 1.8
## Pixels the cursor must travel with the button down before it is a drag
## rather than a click.
const DRAG_FROM := 5.0
## How near (screen px) a click must be to a mark to pick it.
const PIN_PICK := 12.0
const PIN_COLOURS := [Color(0.92, 0.22, 0.18), Color(0.96, 0.62, 0.16), Color(0.96, 0.9, 0.3),
	Color(0.36, 0.84, 0.36), Color(0.3, 0.82, 0.9), Color(0.36, 0.5, 1.0), Color(0.78, 0.42, 0.95),
	Color(0.94, 0.93, 0.9)]
const PIN_SHAPES := ["Pin", "Cross", "Ring"]
const NOTE_MAX := 48

## [{x, z (world), note, color, shape}].
var _pins: Array = []
var _zoom := 1.0
## The image pixel at the middle of the map panel.
var _centre_px := Vector2.ZERO
var _pin_layer: Control = null
var _drag_from := Vector2.ZERO
var _dragging := false
var _pressed := false
var _hover_pin := -1
var _press_button := 0
var _took_ui := false

var _editor: Control = null
var _editor_title: Label = null
var _editor_note: LineEdit = null
var _editor_delete: Button = null
var _editor_swatches: Array[Button] = []
var _editor_shapes: Array[Button] = []
var _editing := -1
var _edit_world := Vector2.ZERO
var _edit_colour := 0
var _edit_shape := 0


func _build_full_map(root: Control) -> void:
	var overlay := Control.new()
	overlay.name = "FullMap"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	root.add_child(overlay)
	_full_root = overlay

	var dim := ColorRect.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.add_child(dim)

	var panel := Panel.new()
	panel.name = "MapPanel"
	# Takes the mouse: wheel, drags and clicks are the map's.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.clip_contents = true
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = COL_BG
	pstyle.border_color = COL_WALL
	pstyle.set_border_width_all(3)
	_frame_styles.append(pstyle)
	panel.add_theme_stylebox_override("panel", pstyle)
	panel.gui_input.connect(_on_map_input)
	panel.mouse_exited.connect(func() -> void:
		_hover_pin = -1
		if _pin_layer != null:
			_pin_layer.queue_redraw())
	overlay.add_child(panel)
	_full_panel = panel

	var tex := TextureRect.new()
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(tex)
	_full_texture_rect = tex

	# The player's arrow and the marks, drawn over the picture at any zoom.
	_pin_layer = Control.new()
	_pin_layer.name = "Marks"
	_pin_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pin_layer.draw.connect(_draw_full_marks)
	panel.add_child(_pin_layer)

	_full_marker = MarkerControl.new()
	_full_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_marker.size = Vector2(1, 1)
	_full_marker.marker_size = 8.0
	panel.add_child(_full_marker)

	# The frame again, over the picture: the panel's own border is drawn under
	# its children, and the map image covered most of it.
	var rim := Panel.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rstyle := StyleBoxFlat.new()
	rstyle.draw_center = false
	rstyle.border_color = COL_WALL
	rstyle.set_border_width_all(3)
	_frame_styles.append(rstyle)
	rim.add_theme_stylebox_override("panel", rstyle)
	panel.add_child(rim)

	var hints := Label.new()
	_hints = hints
	hints.name = "Hints"
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.text = "Mouse / left stick: move the map      Scroll / right stick: zoom      Left click / A: pin (again to remove)      Right click / X: mark with a note      Esc / B: close"
	hints.add_theme_font_size_override("font_size", 14)
	hints.add_theme_color_override("font_color", Color(0.82, 0.8, 0.76))
	hints.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hints.add_theme_constant_override("outline_size", 4)
	# Along the top: at the bottom it sat on the HUD's health bar.
	hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hints.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hints.offset_top = 12
	hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(hints)

	_full_title = Label.new()
	_full_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_title.text = "DUNGEON"
	_full_title.add_theme_font_size_override("font_size", 20)
	_full_title.add_theme_color_override("font_color", Color(0.9, 0.86, 0.78))
	_full_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_full_title.add_theme_constant_override("outline_size", 5)
	_full_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_full_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_full_title.offset_top = 58
	_full_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(_full_title)

	_build_editor(overlay)


func _position_full_panel() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var view: Vector2 = vp.get_visible_rect().size
	_full_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Equal margins, so the panel's middle -- the map's cursor -- is the
	# screen's middle, where the crosshair is. Embedded, below the inventory's
	# header and the level's title, above its footer.
	if _embedded:
		_full_panel.position = Vector2(48.0, 100.0)
		_full_panel.size = view - Vector2(96.0, 100.0 + 64.0)
	else:
		_full_panel.position = Vector2(48.0, 48.0)
		_full_panel.size = view - Vector2(96.0, 96.0)
	_full_side = minf(_full_panel.size.x, _full_panel.size.y)
	_layout_full_texture()


## The scale that fits the whole image in the panel: zoom 1.
func _fit_scale() -> float:
	if _img_w <= 0 or _img_h <= 0 or _full_panel == null:
		return 1.0
	var inner := _full_panel.size - Vector2(12.0, 12.0)
	return minf(inner.x / float(_img_w), inner.y / float(_img_h))


func _full_display_scale() -> float:
	return _fit_scale() * _zoom


## Panel-local position of an image pixel, and back.
func _px_to_panel(px: Vector2) -> Vector2:
	return _full_panel.size * 0.5 + (px - _centre_px) * _full_display_scale()


func _panel_to_px(p: Vector2) -> Vector2:
	return _centre_px + (p - _full_panel.size * 0.5) / _full_display_scale()


## The middle of the view may not wander off the image.
func _clamp_centre() -> void:
	_centre_px = _centre_px.clamp(Vector2.ZERO, Vector2(_img_w, _img_h))


func _layout_full_texture() -> void:
	if _full_texture_rect == null or _img_w <= 0 or _img_h <= 0 or _full_panel == null:
		return
	_clamp_centre()
	var scale := _full_display_scale()
	_full_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if scale >= 1.0 \
		else CanvasItem.TEXTURE_FILTER_LINEAR
	_full_texture_rect.size = Vector2(_img_w, _img_h) * scale
	_full_texture_rect.position = _px_to_panel(Vector2.ZERO)
	# The mark under the cursor is the one a click would open.
	_hover_pin = _pin_at(_full_panel.size * 0.5)
	if _pin_layer != null:
		_pin_layer.queue_redraw()


## Zooms by `factor` keeping the image point under `at` (panel-local) where it is.
func _zoom_at(factor: float, at: Vector2) -> void:
	var keep := _panel_to_px(at)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_centre_px = keep - (at - _full_panel.size * 0.5) / _full_display_scale()
	_layout_full_texture()


## The open map (2026-10-11): the cursor is fixed in the middle of the panel --
## the screen's centre, where the crosshair always is -- and the MAP moves under
## it. Mouse movement drags the map along (the mouse is captured), the wheel
## zooms about the cursor, a left click marks the spot under it (or opens the
## mark there). The pad does the same in `_pad_map` (left stick / d-pad pan,
## right stick zoom) and A marks.
func _map_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_centre_px += motion.relative * MOUSE_PAN / _full_display_scale()
		_layout_full_texture()
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null:
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom_at(ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP,
				_full_panel.size * 0.5)
		elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			_quick_pin(_full_panel.size * 0.5)
		elif button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
			_click_map(_full_panel.size * 0.5)
		get_viewport().set_input_as_handled()
		return
	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed:
		if pad.button_index == JOY_BUTTON_A:
			_quick_pin(_full_panel.size * 0.5)
			get_viewport().set_input_as_handled()
		elif pad.button_index == JOY_BUTTON_X:
			_click_map(_full_panel.size * 0.5)
			get_viewport().set_input_as_handled()
		elif pad.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			# Panned in _pad_map; kept from the quick items.
			get_viewport().set_input_as_handled()


## Mouse travel to map travel, in screen pixels.
const MOUSE_PAN := 1.0
const CURSOR_RADIUS := 9.0
## The pad: a full push pans this many screen pixels a second.
const PAD_PAN := 720.0


func _on_map_input(event: InputEvent) -> void:
	if _editor != null and _editor.visible:
		return
	var button := event as InputEventMouseButton
	if button != null:
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom_at(ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP, button.position)
			_full_panel.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT \
				or button.button_index == MOUSE_BUTTON_MIDDLE:
			if button.pressed:
				_pressed = true
				_dragging = button.button_index == MOUSE_BUTTON_MIDDLE
				_press_button = button.button_index
				_drag_from = button.position
			elif _pressed:
				_pressed = false
				# A click that never became a drag: left pins, right marks.
				if not _dragging and _press_button == MOUSE_BUTTON_LEFT:
					_quick_pin(button.position)
				elif not _dragging and _press_button == MOUSE_BUTTON_RIGHT:
					_click_map(button.position)
				_dragging = false
			_full_panel.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _pressed:
			if not _dragging and motion.position.distance_to(_drag_from) > DRAG_FROM:
				_dragging = true
			if _dragging:
				_centre_px -= motion.relative / _full_display_scale()
				_layout_full_texture()
		var was := _hover_pin
		_hover_pin = _pin_at(motion.position)
		if _hover_pin != was:
			_pin_layer.queue_redraw()


## The mark nearest `p` (panel-local) within PIN_PICK, or -1.
func _pin_at(p: Vector2) -> int:
	var best := -1
	var best_d := PIN_PICK
	for i in _pins.size():
		if not _pin_on_level(_pins[i]):
			continue
		var d := _px_to_panel(_pin_px(_pins[i])).distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


func _pin_px(pin: Dictionary) -> Vector2:
	return _continuous_px(Vector3(float(pin["x"]), 0.0, float(pin["z"])))


func _click_map(p: Vector2) -> void:
	var hit := _pin_at(p)
	if hit >= 0:
		_open_editor(hit, Vector2.ZERO)
		return
	# Image pixel back to world x, z (the inverse of `_continuous_px`).
	var px := _panel_to_px(p)
	var gx := px.x / float(PPC) - float(MARGIN_CELLS) - 0.5
	var gy := px.y / float(PPC) - float(MARGIN_CELLS) - 0.5
	var world := Vector2(_built.origin.x + gx * _built.cell_size, _built.origin.z + gy * _built.cell_size)
	_open_editor(-1, world)


## Left click / A (2026-10-14): a PIN at the spot -- no note asked for, drawn
## on the full map only, not the minimap. On a pin already, it comes off again.
const QUICK_PIN_COLOUR := Color(0.96, 0.93, 0.86)

func _quick_pin(p: Vector2) -> void:
	var hit := _pin_at(p)
	if hit >= 0:
		if _pins[hit].get("quick", false):
			_pins.remove_at(hit)
			_hover_pin = -1
			_pin_layer.queue_redraw()
		return
	var world := _panel_to_world(p)
	_pins.append({"x": world.x, "z": world.y, "note": "", "color": QUICK_PIN_COLOUR, "shape": 0, "quick": true, "level": _level})
	_hover_pin = _pin_at(p)
	_pin_layer.queue_redraw()


## Panel point -> world x, z (the inverse of `_continuous_px`).
func _panel_to_world(p: Vector2) -> Vector2:
	var px := _panel_to_px(p)
	var gx := px.x / float(PPC) - float(MARGIN_CELLS) - 0.5
	var gy := px.y / float(PPC) - float(MARGIN_CELLS) - 0.5
	return Vector2(_built.origin.x + gx * _built.cell_size, _built.origin.z + gy * _built.cell_size)


## The player's arrow and every mark, at the current zoom; a hovered mark shows
## its note beside it.
func _draw_full_marks() -> void:
	if _built == null:
		return
	var font := ThemeDB.fallback_font
	for i in _pins.size():
		var pin: Dictionary = _pins[i]
		if not _pin_on_level(pin):
			continue
		var at := _px_to_panel(_pin_px(pin))
		_draw_mark(_pin_layer, at, pin["color"], int(pin.get("shape", 0)), 1.0 if i != _hover_pin else 1.3)
		if i == _hover_pin and String(pin["note"]) != "":
			var text := String(pin["note"])
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var box := Rect2(at + Vector2(14, -30), Vector2(w + 14, 24))
			_pin_layer.draw_rect(box, Color(0.04, 0.035, 0.03, 0.92))
			_pin_layer.draw_rect(box, Color(pin["color"], 0.9), false, 1.5)
			_pin_layer.draw_string(font, box.position + Vector2(7, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(0.95, 0.92, 0.85))
	# The cursor: the game's crosshair (a ring and a dot, hud.gd), fixed in the
	# middle; the map moves under it. Corner brackets close in over a mark.
	var c := _pin_layer.size * 0.5
	var ring := CURSOR_RADIUS
	_pin_layer.draw_arc(c, ring, 0.0, TAU, 40, Color(0, 0, 0, 0.7), 4.0, true)
	_pin_layer.draw_arc(c, ring, 0.0, TAU, 40, Color(1, 1, 1, 0.95), 1.8, true)
	_pin_layer.draw_circle(c, 2.6, Color(0, 0, 0, 0.7))
	_pin_layer.draw_circle(c, 1.8, Color(1, 1, 1, 0.95))
	if _hover_pin >= 0:
		var r := ring + 7.0
		for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var corner := c + q * r
			for leg: Vector2 in [Vector2(-q.x, 0), Vector2(0, -q.y)]:
				_pin_layer.draw_line(corner, corner + leg * 6.0, Color(0, 0, 0, 0.7), 4.0, true)
				_pin_layer.draw_line(corner, corner + leg * 6.0, Color(1, 1, 1, 0.95), 1.8, true)


## One mark: a pin (head and point), a cross, or a ring, outlined in black.
static func _draw_mark(c: CanvasItem, at: Vector2, colour: Color, shape: int, s: float) -> void:
	var dark := Color(0.04, 0.03, 0.03)
	match shape:
		1:
			for d: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
				c.draw_line(at - d * 7.0 * s, at + d * 7.0 * s, dark, 5.0 * s, true)
				c.draw_line(at - d * 7.0 * s, at + d * 7.0 * s, colour, 3.0 * s, true)
		2:
			c.draw_arc(at, 7.5 * s, 0.0, TAU, 24, dark, 5.0 * s, true)
			c.draw_arc(at, 7.5 * s, 0.0, TAU, 24, colour, 3.0 * s, true)
		_:
			# A pin standing on the spot it marks.
			var head := at + Vector2(0.0, -14.0 * s)
			c.draw_line(at, head, dark, 3.5 * s, true)
			c.draw_line(at, head, Color(0.85, 0.85, 0.85), 1.6 * s, true)
			c.draw_circle(head, 6.0 * s, dark)
			c.draw_circle(head, 4.6 * s, colour)
			c.draw_circle(head + Vector2(-1.5, -1.5) * s, 1.4 * s, Color(1, 1, 1, 0.7))


# --- Marking the map ------------------------------------------------------------------

func _build_editor(overlay: Control) -> void:
	# Centred in the top half of the screen: the on-screen keyboard (pad.gd)
	# comes up from the bottom and covered its buttons when it sat mid-screen.
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.anchor_bottom = 0.55
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	overlay.add_child(holder)
	_editor = holder
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.045, 0.04, 0.97)
	box.border_color = COL_WALL
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", box)
	holder.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(380, 0)
	panel.add_child(column)
	_editor_title = Label.new()
	_editor_title.add_theme_font_size_override("font_size", 20)
	_editor_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	column.add_child(_editor_title)
	_editor_note = LineEdit.new()
	_editor_note.max_length = NOTE_MAX
	_editor_note.placeholder_text = "A short note (optional)"
	_editor_note.custom_minimum_size = Vector2(0, 40)
	_editor_note.add_theme_font_size_override("font_size", 17)
	_editor_note.text_submitted.connect(func(_t: String) -> void:
		if not Pad.using_pad:
			_save_pin())
	column.add_child(_editor_note)
	Pad.attach_keyboard(_editor_note)
	var colours := HBoxContainer.new()
	colours.add_theme_constant_override("separation", 6)
	column.add_child(colours)
	_editor_swatches.clear()
	for i in PIN_COLOURS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		b.focus_mode = Control.FOCUS_ALL
		var sb := StyleBoxFlat.new()
		sb.bg_color = PIN_COLOURS[i]
		sb.set_corner_radius_all(6)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(func() -> void:
			_edit_colour = i
			_restyle_editor())
		colours.add_child(b)
		_editor_swatches.append(b)
	var shapes := HBoxContainer.new()
	shapes.add_theme_constant_override("separation", 6)
	column.add_child(shapes)
	_editor_shapes.clear()
	for i in PIN_SHAPES.size():
		var b := Button.new()
		b.text = PIN_SHAPES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(80, 34)
		b.pressed.connect(func() -> void:
			_edit_shape = i
			_restyle_editor())
		shapes.add_child(b)
		_editor_shapes.append(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var save := Button.new()
	save.text = "Save"
	save.custom_minimum_size = Vector2(100, 36)
	save.pressed.connect(_save_pin)
	row.add_child(save)
	_editor_delete = Button.new()
	_editor_delete.text = "Delete"
	_editor_delete.custom_minimum_size = Vector2(100, 36)
	_editor_delete.pressed.connect(_delete_pin)
	row.add_child(_editor_delete)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(100, 36)
	cancel.pressed.connect(_close_editor)
	row.add_child(cancel)


## `index` an existing mark to change, or -1 for a new one at `world` (x, z).
func _open_editor(index: int, world: Vector2) -> void:
	_editing = index
	if index >= 0:
		var pin: Dictionary = _pins[index]
		_edit_world = Vector2(float(pin["x"]), float(pin["z"]))
		_editor_note.text = String(pin["note"])
		_edit_colour = maxi(PIN_COLOURS.find(pin["color"]), 0)
		_edit_shape = int(pin.get("shape", 0))
		_editor_title.text = "Mark"
	else:
		_edit_world = world
		_editor_note.text = ""
		_editor_title.text = "New mark"
	_editor_delete.visible = index >= 0
	_editor.visible = true
	# The editor is worked with the pointer (or, on a pad, by focus).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_restyle_editor()
	# The note box first: typing (or, on a pad, the on-screen keyboard) at once.
	_editor_note.grab_focus.call_deferred()
	_editor_note.caret_column = _editor_note.text.length()


func _restyle_editor() -> void:
	for i in _editor_swatches.size():
		var b := _editor_swatches[i]
		var sb := (b.get_theme_stylebox("normal") as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.border_color = Color(1, 1, 1) if i == _edit_colour else Color(0, 0, 0, 0.6)
		sb.set_border_width_all(3 if i == _edit_colour else 1)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, sb)
	for i in _editor_shapes.size():
		_editor_shapes[i].button_pressed = i == _edit_shape


func _save_pin() -> void:
	if _editor == null or not _editor.visible:
		return
	var pin := {"x": _edit_world.x, "z": _edit_world.y, "note": _editor_note.text.strip_edges().left(NOTE_MAX),
		"color": PIN_COLOURS[_edit_colour], "shape": _edit_shape, "level": _level}
	if _editing >= 0 and _editing < _pins.size():
		_pins[_editing] = pin
	else:
		_pins.append(pin)
	_close_editor()


func _delete_pin() -> void:
	if _editing >= 0 and _editing < _pins.size():
		_pins.remove_at(_editing)
	_close_editor()


func _close_editor() -> void:
	if _editor == null:
		return
	var was_open := _editor.visible
	_editor.visible = false
	_editing = -1
	_editor_note.release_focus()
	Pad.hide_keyboard()
	if was_open and _full_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _pin_layer != null:
		_pin_layer.queue_redraw()


func editor_open() -> bool:
	return _editor != null and _editor.visible


## The marks, for a save: world x, z, the note, the colour (as html) and shape.
func pins_state() -> Array:
	var out: Array = []
	for pin: Dictionary in _pins:
		out.append({"x": pin["x"], "z": pin["z"], "note": pin["note"], "quick": pin.get("quick", false),
			"color": (pin["color"] as Color).to_html(false), "shape": pin.get("shape", 0),
			"level": String(pin.get("level", "dungeon"))})
	return out


func restore_pins(data: Array) -> void:
	_pins.clear()
	for d in data:
		if d is Dictionary:
			_pins.append({"x": float(d.get("x", 0.0)), "z": float(d.get("z", 0.0)),
				"note": String(d.get("note", "")), "color": Color.html(String(d.get("color", "ee3a2e"))),
				"shape": int(d.get("shape", 0)), "quick": bool(d.get("quick", false)),
				"level": StringName(String(d.get("level", "dungeon")))})
	if _pin_layer != null:
		_pin_layer.queue_redraw()
	if _mini_marks != null:
		_mini_marks.queue_redraw()


func pin_count() -> int:
	return _pins.size()


## The pad on the open map: the right stick zooms about the cursor, and the
## cursor pushed against the panel's edge pans.
func _pad_map(delta: float) -> void:
	if not _full_open or editor_open() or _full_panel == null:
		return
	var zoom := Input.get_axis(&"look_down", &"look_up")
	if absf(zoom) > 0.15:
		_zoom_at(exp(zoom * PAD_ZOOM_RATE * delta), _full_panel.size * 0.5)
	# Left stick (and the d-pad, and W/A/S/D) moves the map under the cursor.
	var pan := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var dpad := Vector2(float(Input.is_joy_button_pressed(_pad_device(), JOY_BUTTON_DPAD_RIGHT))
		- float(Input.is_joy_button_pressed(_pad_device(), JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(_pad_device(), JOY_BUTTON_DPAD_DOWN))
		- float(Input.is_joy_button_pressed(_pad_device(), JOY_BUTTON_DPAD_UP)))
	if dpad != Vector2.ZERO:
		pan = dpad.normalized()
	if pan.length() > 0.12:
		_centre_px += pan * PAD_PAN * delta / _full_display_scale()
		_layout_full_texture()


func _pad_device() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else 0


## --- Reveal ------------------------------------------------------------------

func _cell_for_world(p: Vector3) -> Vector2i:
	return Vector2i(
		int(round((p.x - _built.origin.x) / _built.cell_size)),
		int(round((p.z - _built.origin.z) / _built.cell_size)))


func _update_reveal() -> void:
	var cell := _cell_for_world(_player.global_position)
	if cell == _last_cell:
		return
	_last_cell = cell
	_reveal_from(cell)
	if _revealed_dirty:
		_rebuild_map_image()
		_revealed_dirty = false


func _reveal_cell(pos: Vector2i) -> void:
	if _revealed.has(pos):
		return
	if not _built.cells.has(pos):
		return
	_revealed[pos] = true
	_revealed_dirty = true


func _reveal_room(room: Dictionary) -> void:
	var c: Vector2i = room["centre"]
	var h: int = room["half"]
	for dx in range(-h, h + 1):
		for dy in range(-h, h + 1):
			var p := c + Vector2i(dx, dy)
			if _built.cells.has(p):
				_reveal_cell(p)


## Wooden doors by the cell boundary they stand on. The level's connectivity
## treats a doorway as open, so without this the sightline ran straight
## through a shut door and mapped the corridor behind it.
var _door_edges := {}


func _index_doors() -> void:
	_door_edges.clear()
	var doors = _built.get("doors")
	if doors == null:
		return
	for rec in doors:
		var node: Node = rec.get("node")
		if node == null:
			continue
		_door_edges[_edge_key(rec["cell"], rec["other"])] = node
		if node.has_signal("door_opened") and not node.door_opened.is_connected(_on_door_opened):
			node.door_opened.connect(_on_door_opened)


static func _edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


func _door_shut(a: Vector2i, b: Vector2i) -> bool:
	var node = _door_edges.get(_edge_key(a, b))
	return node != null and is_instance_valid(node) and not node.get("opened")


## Opening a door changes what can be seen from where the player already
## stands, so the sightlines are recast at once rather than on the next step.
func _on_door_opened() -> void:
	_last_cell = Vector2i(-999999, -999999)


## Reveals `at` itself, plus a straight run of cells behind each of its open
## sides -- a sightline down a corridor -- stopping the moment a side is not
## open (a wall) rather than trusting distance alone. Never crosses a side
## that is not open, so a cell behind a wall can never be reached from here.
func _reveal_from(at: Vector2i) -> void:
	var cell = _built.cells.get(at)
	if cell == null:
		return
	_reveal_cell(at)
	if cell.room >= 0 and cell.room < _built.rooms.size():
		_reveal_room(_built.rooms[cell.room])

	for side in [ModuleMaze.N, ModuleMaze.E, ModuleMaze.S, ModuleMaze.W]:
		if not (cell.open & side):
			continue
		var step: Vector2i = ModuleMaze.DIRS[side]
		var cur := at
		for i in SIGHT_RANGE_CELLS:
			var cur_cell = _built.cells.get(cur)
			if cur_cell == null or not (cur_cell.open & side):
				break
			var nxt: Vector2i = cur + step
			if not _built.cells.has(nxt):
				break
			# A shut door is a wall to the eye: nothing past it is mapped until
			# it has been opened.
			if _door_shut(cur, nxt):
				break
			_reveal_cell(nxt)
			var nxt_cell = _built.cells[nxt]
			if nxt_cell.room >= 0 and nxt_cell.room < _built.rooms.size():
				_reveal_room(_built.rooms[nxt_cell.room])
				break
			cur = nxt


## --- Marker / minimap follow --------------------------------------------------

## World-space (x, z) mapped to a continuous (not cell-rounded) pixel position
## in the baked image, margin included.
func _continuous_px(p: Vector3) -> Vector2:
	# +0.5: `Built.to_world(pos)` is a cell's CENTRE, but a cell is painted
	# from its top-left corner at `_cell_origin_px(pos)`. Without the half
	# cell the marker sat 3 m up and left of the player -- on the wall while
	# walking down the middle of a corridor.
	var gx: float = (p.x - _built.origin.x) / _built.cell_size + float(MARGIN_CELLS) + 0.5
	var gy: float = (p.z - _built.origin.z) / _built.cell_size + float(MARGIN_CELLS) + 0.5
	return Vector2(gx * float(PPC), gy * float(PPC))


func _facing_angle() -> float:
	var forward := -_player.global_basis.z
	# The map is north-up and north is -Z; this is the 3D forward vector's
	# (x, z) turned into a 2D-canvas rotation (see explore_map's derivation
	# in the task notes: screen "up" already lines up with world north).
	return atan2(forward.x, -forward.z)


func _update_marker_transforms() -> void:
	if _built == null or not is_instance_valid(_player):
		return
	var angle := _facing_angle()
	# Heading up: the arrow always points up and the map turns under it.
	_mini_spin = angle
	_mini_marker.rotation = 0.0
	_mini_texture_rect.rotation = -angle

	if _atlas != null:
		var px := _continuous_px(_player.global_position)
		var half: float = MINIMAP_SPAN_M * 0.5 / _built.cell_size * float(PPC) * MINI_SPIN_PAD
		_atlas.region = Rect2(px.x - half, px.y - half, half * 2.0, half * 2.0)

	if _mini_marks != null:
		_mini_marks.queue_redraw()
	if not _full_open:
		return
	_full_marker.rotation = angle
	if _img_w <= 0 or _img_h <= 0:
		return
	_full_marker.position = _px_to_panel(_continuous_px(_player.global_position))
	# A player off the zoomed view is not drawn over the panel's edge.
	_full_marker.visible = Rect2(Vector2.ZERO, _full_panel.size).has_point(_full_marker.position)


## --- Baking the revealed map into an image -----------------------------------

func _cell_origin_px(pos: Vector2i) -> Vector2i:
	return Vector2i(
		(pos.x + MARGIN_CELLS) * PPC,
		(pos.y + MARGIN_CELLS) * PPC)


func _rebuild_map_image() -> void:
	var img := Image.create(_img_w, _img_h, false, Image.FORMAT_RGB8)
	img.fill(COL_BG)

	# Rooms (cell.room >= 0, ring and courtyard alike) are painted as one
	# continuous block rather than cell by cell -- the per-cell floor fill
	# left a grid of unfilled corner squares at every internal junction
	# inside a room, which is what read as a "busy grid" instead of a hall.
	var room_ids := {}
	for key in _revealed:
		var cell = _built.cells.get(key)
		if cell == null:
			continue
		if cell.room >= 0 and cell.room < _built.rooms.size():
			room_ids[cell.room] = true
		else:
			_paint_floor(img, cell)
	for room_id in room_ids:
		_paint_room_floor(img, _built.rooms[room_id])

	for key in _revealed:
		var cell = _built.cells.get(key)
		# No per-cell centrelines inside a room -- see above.
		if cell != null and cell.room < 0:
			_paint_centerline(img, cell)
	for key in _revealed:
		var cell = _built.cells.get(key)
		if cell != null:
			_paint_wall_outline(img, cell)
	# No icons (2026-10-10): junctions, rooms, gates and hiding places are no
	# longer drawn -- the player marks the map themselves (`_pins`).
	# Except the sewer's ladders (2026-10-15): the only ways out of it.
	var ladders = _built.get("ladders")
	if ladders != null:
		for at: Vector3 in ladders:
			if not _revealed.has(_cell_for_world(at)):
				continue
			var px := _continuous_px(at)
			img.fill_rect(Rect2i(int(px.x) - 3, int(px.y) - 3, 6, 6), Color(0.0, 0.0, 0.0))
			img.fill_rect(Rect2i(int(px.x) - 2, int(px.y) - 2, 4, 4), Color(0.92, 0.88, 0.7))

	if _map_texture == null:
		_map_texture = ImageTexture.create_from_image(img)
		_atlas = AtlasTexture.new()
		_atlas.atlas = _map_texture
		_atlas.filter_clip = true
		_atlas.region = Rect2(0, 0, _img_w, _img_h)
		_mini_texture_rect.texture = _atlas
		_full_texture_rect.texture = _map_texture
	else:
		_map_texture.set_image(img)


## Black floor fill for the cell's own footprint, plus a bar into every open
## side so joined cells read as one continuous corridor.
func _paint_floor(img: Image, cell) -> void:
	var o := _cell_origin_px(cell.pos)
	var ox := o.x
	var oy := o.y
	var pad := WALL_PAD
	img.fill_rect(Rect2i(ox + pad, oy + pad, PPC - pad * 2, PPC - pad * 2), COL_FLOOR)
	if cell.open & ModuleMaze.N:
		img.fill_rect(Rect2i(ox + pad, oy - pad, PPC - pad * 2, pad * 2 + 1), COL_FLOOR)
	if cell.open & ModuleMaze.S:
		img.fill_rect(Rect2i(ox + pad, oy + PPC - pad, PPC - pad * 2, pad * 2), COL_FLOOR)
	if cell.open & ModuleMaze.W:
		img.fill_rect(Rect2i(ox - pad, oy + pad, pad * 2 + 1, PPC - pad * 2), COL_FLOOR)
	if cell.open & ModuleMaze.E:
		img.fill_rect(Rect2i(ox + PPC - pad, oy + pad, pad * 2, PPC - pad * 2), COL_FLOOR)


## One continuous black floor block for an entire room (ring plus courtyard),
## instead of the per-cell fill `_paint_floor` uses for corridors. Fills the
## whole footprint in a single rect -- so there is no seam at any internal
## cell boundary -- then bridges the wall-thickness inset out to the true
## edge at each of the room's own doorways, matching the bar a corridor cell
## draws on its side of the same opening.
func _paint_room_floor(img: Image, room: Dictionary) -> void:
	var c: Vector2i = room["centre"]
	var h: int = room["half"]
	var pad := WALL_PAD
	var top_left := _cell_origin_px(c - Vector2i(h, h))
	var bottom_right := _cell_origin_px(c + Vector2i(h, h)) + Vector2i(PPC, PPC)
	img.fill_rect(Rect2i(
		top_left.x + pad, top_left.y + pad,
		(bottom_right.x - top_left.x) - pad * 2,
		(bottom_right.y - top_left.y) - pad * 2), COL_FLOOR)

	for way in room["entrances"]:
		var entrance_cell: Vector2i = way["cell"]
		var side: int = way["side"]
		var eo := _cell_origin_px(entrance_cell)
		if side == ModuleMaze.N:
			img.fill_rect(Rect2i(eo.x + pad, top_left.y, PPC - pad * 2, pad + 1), COL_FLOOR)
		elif side == ModuleMaze.S:
			img.fill_rect(Rect2i(eo.x + pad, bottom_right.y - pad - 1, PPC - pad * 2, pad + 1), COL_FLOOR)
		elif side == ModuleMaze.W:
			img.fill_rect(Rect2i(top_left.x, eo.y + pad, pad + 1, PPC - pad * 2), COL_FLOOR)
		elif side == ModuleMaze.E:
			img.fill_rect(Rect2i(bottom_right.x - pad - 1, eo.y + pad, pad + 1, PPC - pad * 2), COL_FLOOR)


## A faint, thin centreline from the cell's middle out to each open side, so
## corridors read with a subtle spine rather than as a bare black band.
func _paint_centerline(img: Image, cell) -> void:
	var o := _cell_origin_px(cell.pos)
	var ox := o.x
	var oy := o.y
	var half := PPC / 2
	var pad := WALL_PAD
	if cell.open & ModuleMaze.N:
		img.fill_rect(Rect2i(ox + half - 1, oy - pad, 2, half + pad), COL_CENTERLINE)
	if cell.open & ModuleMaze.S:
		img.fill_rect(Rect2i(ox + half - 1, oy + half, 2, half + pad), COL_CENTERLINE)
	if cell.open & ModuleMaze.W:
		img.fill_rect(Rect2i(ox - pad, oy + half - 1, half + pad, 2), COL_CENTERLINE)
	if cell.open & ModuleMaze.E:
		img.fill_rect(Rect2i(ox + half, oy + half - 1, half + pad, 2), COL_CENTERLINE)


## A thin amber line at the cell's true boundary on every side that is NOT
## open -- the actual wall -- which is what gives the reference's "black band,
## amber outline" look.
func _paint_wall_outline(img: Image, cell) -> void:
	var o := _cell_origin_px(cell.pos)
	var ox := o.x
	var oy := o.y
	# 2 px, not 1 -- a single-pixel line is exactly what a clean 0.5x
	# downscale (see `_clean_scale()`) can drop every other line of, turning
	# a solid outline dashed. Two survives that.
	var t := 2
	if not (cell.open & ModuleMaze.N):
		img.fill_rect(Rect2i(ox, oy, PPC, t), _wall_colour())
	if not (cell.open & ModuleMaze.S):
		img.fill_rect(Rect2i(ox, oy + PPC - t, PPC, t), _wall_colour())
	if not (cell.open & ModuleMaze.W):
		img.fill_rect(Rect2i(ox, oy, t, PPC), _wall_colour())
	if not (cell.open & ModuleMaze.E):
		img.fill_rect(Rect2i(ox + PPC - t, oy, t, PPC), _wall_colour())


## --- Levels (2026-10-15) ---------------------------------------------------------
##
## The sewer (sewer.gd) is a second map on the same grid: `add_level` registers
## it, and whichever level the player is on is the one charted, drawn and shown,
## on both the full map and the minimap (`_check_level`, by height: below
## LEVEL_SPLIT_Y is the sewer). Each level keeps its own charted cells; marks
## are kept per level. Dying forgets only the DUNGEON's charting since the
## checkpoint (`snapshot` / `restore` read and write it whichever level is up).

const LEVEL_SPLIT_Y := -4.0
const COL_SEWER_WALL := Color(0.46, 0.66, 0.52)
const LEVEL_TITLES := {&"dungeon": "", &"sewer": "SEWERS"}

var _level := &"dungeon"
## Levels not on screen: name -> {"built": ..., "revealed": {...}}.
var _stored := {}
var _level_label: Label = null
var _full_title: Label = null
var _frame_styles: Array[StyleBoxFlat] = []


func add_level(level: StringName, built) -> void:
	_stored[level] = {"built": built, "revealed": {}}


## Every cell of every level charted (the sandbox, sandbox.gd).
func reveal_all() -> void:
	if _built != null:
		for c in _built.cells:
			_revealed[c] = true
		_rebuild_map_image()
		_revealed_dirty = false
	for level in _stored:
		var cells := {}
		for c in _stored[level]["built"].cells:
			cells[c] = true
		_stored[level]["revealed"] = cells


func current_level() -> StringName:
	return _level


func _level_for_player() -> StringName:
	if _stored.has(&"sewer") or _level == &"sewer":
		return &"sewer" if _player.global_position.y < LEVEL_SPLIT_Y else &"dungeon"
	return &"dungeon"


func _check_level() -> void:
	var want := _level_for_player()
	if want != _level:
		_switch_level(want)


func _switch_level(level: StringName) -> void:
	if not _stored.has(level):
		return
	_stored[_level] = {"built": _built, "revealed": _revealed}
	var next: Dictionary = _stored[level]
	_stored.erase(level)
	_level = level
	_built = next["built"]
	_revealed = next["revealed"]
	_index_doors()
	_img_w = (_built.size.x + MARGIN_CELLS * 2) * PPC
	_img_h = (_built.size.y + MARGIN_CELLS * 2) * PPC
	_last_cell = Vector2i(-999999, -999999)
	_rebuild_map_image()
	_revealed_dirty = false
	var title: String = LEVEL_TITLES.get(level, "")
	if _level_label != null:
		_level_label.text = title
		_level_label.visible = title != ""
	if _full_title != null:
		_full_title.text = title if title != "" else "DUNGEON"
	var wall := COL_SEWER_WALL if level == &"sewer" else COL_WALL
	for s in _frame_styles:
		s.border_color = wall
	if _pin_layer != null:
		_pin_layer.queue_redraw()
	if _mini_marks != null:
		_mini_marks.queue_redraw()


## The colour walls are drawn in on the level on screen.
func _wall_colour() -> Color:
	return COL_SEWER_WALL if _level == &"sewer" else COL_WALL


func _pin_on_level(pin: Dictionary) -> bool:
	return StringName(pin.get("level", &"dungeon")) == _level


## The charted cells of every level but the dungeon, for a save.
func levels_state() -> Dictionary:
	var out := {}
	if _level != &"dungeon":
		out[String(_level)] = _revealed.keys()
	for level in _stored:
		if level != &"dungeon":
			out[String(level)] = (_stored[level]["revealed"] as Dictionary).keys()
	return out


func restore_levels(data: Dictionary) -> void:
	for key in data:
		var level := StringName(key)
		var cells := {}
		for c in data[key]:
			cells[c] = true
		if level == _level:
			_revealed = cells
			_rebuild_map_image()
			_last_cell = Vector2i(-999999, -999999)
		elif _stored.has(level):
			_stored[level]["revealed"] = cells
