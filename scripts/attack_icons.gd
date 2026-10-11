extends HBoxContainer

## The attack icons (2026-10-10): three rounded squares in a row at the bottom of
## the screen, just left of the health bar -- heavy, mid, regular,
## left to right -- for the weapon in hand, each
## with its key and a drawn glyph. A cooldown is drawn as `ItemSlot.set_cooldown`
## draws one (the old hotbar's look): a dark shade over the share still
## to recharge, draining downward, and the whole seconds left on the long ones.
##
## The numbers come from `player.attack_cooldowns()`, which reads the clocks the
## attacks themselves keep (`_slam_ready_at`, the spear's `_throw_ready_at`,
## `_dash_ready_at`, `_next_stab` ...), none of which a change of weapon touches:
## put the spear away mid-cooldown and take it out again and the shade is where
## it would have been. Hidden while no weapon is in hand.

const TILE := 64.0
const RADIUS := 14
const INK := Color(0.93, 0.88, 0.78)
const INK_DIM := Color(0.74, 0.69, 0.6)
const SHOW_SECONDS_FROM := 1.0
## The row's bottom edge, from the bottom of the screen: level with the foot of
## the health bar (hud.gd HEALTH_BOTTOM).
const BOTTOM := -16.0
## Gap between the row and the health bar to its right.
const GAP := 18.0
const SEPARATION := 10.0

## The keys as a controller labels them (project.godot: light attack RB,
## medium RT, heavy LT). Shown once a pad was the last thing used.
const PAD_KEYS := {"LMB": "RB", "Q": "RT", "F": "LT"}

var player: Node
var _tiles: Array[Dictionary] = []
var _pad := false
var _weapon := &""


func setup(p: Node) -> void:
	player = p
	name = "AttackIcons"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(SEPARATION))
	# Anchored to the bottom centre and set off to the left of the health bar
	# (hud.gd HEALTH_WIDTH).
	var bar_width := 570.0
	var row := TILE * 3.0 + SEPARATION * 2.0
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -bar_width * 0.5 - GAP
	offset_left = offset_right - row
	offset_bottom = BOTTOM
	offset_top = BOTTOM - TILE
	for i in 3:
		_tiles.append(_make_tile())


func _make_tile() -> Dictionary:
	# The tile clips its children to its own rounded shape, so the shade has
	# rounded corners like the tile it covers.
	var tile := Panel.new()
	tile.custom_minimum_size = Vector2(TILE, TILE)
	tile.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.075, 0.09, 0.78)
	bg.set_corner_radius_all(RADIUS)
	bg.anti_aliasing = true
	tile.add_theme_stylebox_override("panel", bg)
	add_child(tile)
	var glyph := Control.new()
	glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(glyph)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.visible = false
	tile.add_child(shade)
	var seconds := _label(20, Color(1.0, 0.92, 0.8))
	seconds.set_anchors_preset(Control.PRESET_FULL_RECT)
	seconds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seconds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seconds.visible = false
	tile.add_child(seconds)
	var key := _label(11, Color(0.85, 0.85, 0.82, 0.9))
	key.position = Vector2(7, 3)
	tile.add_child(key)
	# The rim on top of everything, so the shade does not cover it.
	var rim := Panel.new()
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.set_border_width_all(2)
	edge.set_corner_radius_all(RADIUS)
	edge.anti_aliasing = true
	edge.border_color = Color(0.42, 0.4, 0.38, 0.75)
	rim.add_theme_stylebox_override("panel", edge)
	tile.add_child(rim)
	var t := {"tile": tile, "glyph": glyph, "shade": shade, "seconds": seconds, "key": key,
		"edge": edge, "kind": &"", "ready": true, "flash": 0.0}
	glyph.draw.connect(_draw_glyph.bind(t))
	return t


func _label(size_px: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Which labels to show: whatever was used last, a pad or the keyboard and mouse.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad = false


func _process(delta: float) -> void:
	if player == null or not player.has_method("attack_cooldowns"):
		return
	var list: Array = player.call("attack_cooldowns")
	visible = not list.is_empty() and player.get("_dead") != true
	if not visible:
		return
	for i in _tiles.size():
		var t: Dictionary = _tiles[i]
		var entry: Array = list[i]
		var kind: StringName = entry[0]
		if t["kind"] != kind:
			t["kind"] = kind
			(t["glyph"] as Control).queue_redraw()
		(t["key"] as Label).text = PAD_KEYS.get(String(entry[3]), "") if _pad else String(entry[3])
		var left: float = entry[1]
		var total: float = entry[2]
		_show(t, left, total, delta)


## `left` seconds still to wait of `total`; -1 = not usable at all just now (the
## spear in flight): full shade, no number.
func _show(t: Dictionary, left: float, total: float, delta: float) -> void:
	var tile: Panel = t["tile"]
	var shade: ColorRect = t["shade"]
	var seconds: Label = t["seconds"]
	var share := 1.0 if left < 0.0 else (left / maxf(total, left) if left > 0.0 else 0.0)
	var on := share > 0.001
	shade.visible = on
	if on:
		var h := tile.size.y * clampf(share, 0.0, 1.0)
		shade.position = Vector2(0.0, tile.size.y - h)
		shade.size = Vector2(tile.size.x, h)
	var count := on and left > 0.0 and total >= SHOW_SECONDS_FROM
	seconds.visible = count
	if count:
		seconds.text = str(ceili(left))
	# A flash of the rim the moment a long cooldown comes back.
	var done := not on
	if done and not t["ready"] and total >= SHOW_SECONDS_FROM:
		t["flash"] = 1.0
	t["ready"] = done
	t["flash"] = maxf(float(t["flash"]) - delta / 0.45, 0.0)
	var edge: StyleBoxFlat = t["edge"]
	var base := Color(0.62, 0.56, 0.44, 0.85) if done else Color(0.36, 0.34, 0.32, 0.75)
	edge.border_color = base.lerp(Color(1.0, 0.86, 0.5, 1.0), float(t["flash"]))
	edge.set_border_width_all(2 if t["flash"] <= 0.0 else 3)
	(t["glyph"] as Control).modulate = Color.WHITE if done else Color(0.75, 0.75, 0.75)


# --- Glyphs ------------------------------------------------------------------------

func _draw_glyph(t: Dictionary) -> void:
	var g: Control = t["glyph"]
	var c := g.size * 0.5 + Vector2(0.0, 3.0)
	var s := g.size.x * 0.34
	match t["kind"]:
		&"slash":
			_blade(g, c + Vector2(-s * 0.55, s * 0.6), c + Vector2(s * 0.75, -s * 0.8), 3.0)
			g.draw_arc(c + Vector2(-s * 0.3, s * 0.2), s * 1.05, -PI * 0.15, PI * 0.55, 18, INK_DIM, 2.0, true)
		&"spin":
			g.draw_arc(c, s * 0.95, -PI * 0.2, PI * 1.45, 28, INK, 3.0, true)
			var tip := c + Vector2(cos(-PI * 0.2), sin(-PI * 0.2)) * s * 0.95
			g.draw_colored_polygon(PackedVector2Array([tip + Vector2(-2, -9), tip + Vector2(8, 2),
				tip + Vector2(-7, 6)]), INK)
			_blade(g, c + Vector2(-s * 0.35, s * 0.35), c + Vector2(s * 0.35, -s * 0.35), 2.0)
		&"slam":
			_blade(g, c + Vector2(0.0, -s * 1.15), c + Vector2(0.0, s * 0.55), 3.0)
			for k in 5:
				var a := PI + PI * (float(k) + 0.5) / 5.0
				var d := Vector2(cos(a), -sin(a) * 0.5)
				g.draw_line(c + Vector2(0, s * 0.8) + d * s * 0.45, c + Vector2(0, s * 0.8) + d * s * 0.95, INK_DIM, 2.0, true)
			g.draw_line(c + Vector2(-s * 1.0, s * 0.85), c + Vector2(s * 1.0, s * 0.85), INK, 2.0, true)
		&"stab":
			_spear(g, c + Vector2(-s * 1.1, 0.0), c + Vector2(s * 1.0, 0.0))
			for k in 2:
				var y := (float(k) - 0.5) * s * 0.7
				g.draw_line(c + Vector2(s * 0.55, y), c + Vector2(s * 1.15, y * 1.4), INK_DIM, 2.0, true)
		&"dash":
			_spear(g, c + Vector2(-s * 0.6, 0.0), c + Vector2(s * 1.15, 0.0))
			for k in 3:
				var y := (float(k) - 1.0) * s * 0.45
				g.draw_line(c + Vector2(-s * 1.2, y + 1), c + Vector2(-s * 0.7, y + 1), INK_DIM, 2.0, true)
		&"throw":
			var a := c + Vector2(-s * 0.95, s * 0.75)
			var b := c + Vector2(s * 0.45, -s * 0.45)
			_spear(g, a, b)
			var burst := c + Vector2(s * 0.8, -s * 0.8)
			for k in 8:
				var ang := TAU * float(k) / 8.0
				var r0 := s * 0.18
				var r1 := s * (0.42 if k % 2 == 0 else 0.3)
				g.draw_line(burst + Vector2(cos(ang), sin(ang)) * r0, burst + Vector2(cos(ang), sin(ang)) * r1,
					Color(1.0, 0.7, 0.35), 2.0, true)


## A sword from `hilt` to `tip`: blade, crossguard, grip.
func _blade(g: Control, hilt: Vector2, tip: Vector2, width: float) -> void:
	var dir := (tip - hilt).normalized()
	var side := Vector2(-dir.y, dir.x)
	var guard := hilt + dir * 7.0
	g.draw_colored_polygon(PackedVector2Array([guard + side * width, tip, guard - side * width]), INK)
	g.draw_line(guard + side * 7.0, guard - side * 7.0, INK, 3.0, true)
	g.draw_line(hilt - dir * 2.0, guard, Color(0.66, 0.5, 0.32), 3.0, true)


## A spear from `butt` to `tip`: shaft and leaf head.
func _spear(g: Control, butt: Vector2, tip: Vector2) -> void:
	var dir := (tip - butt).normalized()
	var side := Vector2(-dir.y, dir.x)
	var neck := tip - dir * 11.0
	g.draw_line(butt, neck, Color(0.7, 0.55, 0.36), 2.5, true)
	g.draw_colored_polygon(PackedVector2Array([neck + side * 4.0, tip, neck - side * 4.0, neck - dir * 3.0]), INK)
