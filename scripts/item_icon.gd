class_name ItemIcon
extends Control

## Draws an inventory item as a small picture, in code, so a new item needs no
## image file: a sword, a green flask, a stack of coins. Scales to whatever size
## the slot gives it. Used by the hotbar, the inventory screen and the drag
## preview, so they cannot drift apart; `paint` lets anything else (the
## inventory's category tabs) draw one onto itself.

var item: StringName = &"":
	set(value):
		item = value
		queue_redraw()
## Multiplies every colour (a quick slot run dry draws its item greyed out).
var tint := Color.WHITE:
	set(value):
		tint = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0 or item == &"":
		return
	paint(self, item, Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s)), tint)


## Draws `id` onto `c`, filling the square `rect`, every colour multiplied by
## `tint`.
static func paint(c: CanvasItem, id: StringName, rect: Rect2, tint := Color.WHITE) -> void:
	var o := rect.position
	var s := minf(rect.size.x, rect.size.y)
	match id:
		&"sword":
			_sword(c, o, s, tint)
		&"spear":
			_spear(c, o, s, tint)
		&"axe":
			_axe(c, o, s, tint)
		&"health_potion":
			_potion(c, o, s, tint)
		&"small_health_potion":
			# The same flask, smaller, standing on the same line.
			_potion(c, o + Vector2(0.15, 0.24) * s, s * 0.7, tint)
		&"coins":
			_coins(c, o, s, tint)
		&"bone_fragment":
			_bone(c, o, s, tint)
		&"skeleton_skull":
			_skull(c, o, s, tint)
		&"live_rat":
			_rat(c, o, s, tint, false)
		&"robot_rat":
			_rat(c, o, s, tint, true)
		&"":
			pass
		&"gold_crystal", &"red_crystal":
			_shard(c, o, s, tint, Inventory.item_color(id))
		&"surgeon_claw":
			_claw(c, o, s, tint)
		_ when Inventory.item_kind(id) == "Relic":
			_shard(c, o, s, tint, Inventory.item_color(id))
		_:
			c.draw_circle(o + Vector2(s, s) * 0.5, s * 0.3, Inventory.item_color(id) * tint)


## A puzzle room's shard: a long crystal standing a little tilted, lit face and
## shaded face, with a glow round it.
static func _shard(c: CanvasItem, o: Vector2, s: float, tint: Color, col: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	c.draw_circle(p.call(0.5, 0.52), s * 0.36, Color(col, 0.14) * tint)
	var top: Vector2 = p.call(0.56, 0.08)
	var bottom: Vector2 = p.call(0.44, 0.94)
	var left: Vector2 = p.call(0.3, 0.46)
	var right: Vector2 = p.call(0.7, 0.54)
	var waist: Vector2 = p.call(0.52, 0.5)
	c.draw_colored_polygon(PackedVector2Array([top, waist, bottom, left]), col.lightened(0.25) * tint)
	c.draw_colored_polygon(PackedVector2Array([top, right, bottom, waist]), col.darkened(0.35) * tint)
	c.draw_polyline(PackedVector2Array([top, right, bottom, left, top]), col.darkened(0.7) * tint, maxf(1.0, s * 0.02))
	c.draw_line(top, waist, Color(1, 1, 1, 0.7) * tint, maxf(1.0, s * 0.015))


## The surgeon's claw (note 111): an iron hub with a red eye at the top, three
## jointed iron fingers hanging from it and curling in, brass knuckles.
static func _claw(c: CanvasItem, o: Vector2, s: float, tint: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var iron := Color(0.5, 0.52, 0.56) * tint
	var iron_dark := Color(0.26, 0.27, 0.3) * tint
	var brass := Color(0.78, 0.6, 0.28) * tint
	var dark := Color(0.1, 0.09, 0.1) * tint
	var w := maxf(1.0, s * 0.018)
	# The three fingers: knuckle -> middle joint -> tip, curling in.
	var fingers := [
		[p.call(0.36, 0.42), p.call(0.22, 0.62), p.call(0.32, 0.86)],
		[p.call(0.5, 0.44), p.call(0.5, 0.68), p.call(0.5, 0.92)],
		[p.call(0.64, 0.42), p.call(0.78, 0.62), p.call(0.68, 0.86)],
	]
	for f: Array in fingers:
		c.draw_polyline(PackedVector2Array(f), dark, s * 0.1)
		c.draw_polyline(PackedVector2Array(f), iron_dark, s * 0.075)
		c.draw_line(f[0], f[1], iron, s * 0.045)
		c.draw_circle(f[1], s * 0.04, brass)
		c.draw_circle(f[0], s * 0.045, brass)
	# The hub: a riveted drum, the arm's stub on top, the red eye on its face.
	c.draw_line(p.call(0.5, 0.08), p.call(0.5, 0.2), iron_dark, s * 0.12)
	var hub := PackedVector2Array([p.call(0.3, 0.2), p.call(0.7, 0.2), p.call(0.74, 0.32),
		p.call(0.66, 0.44), p.call(0.34, 0.44), p.call(0.26, 0.32)])
	c.draw_colored_polygon(hub, iron)
	c.draw_colored_polygon(PackedVector2Array([p.call(0.26, 0.32), p.call(0.74, 0.32), p.call(0.66, 0.44),
		p.call(0.34, 0.44)]), iron_dark)
	var outline := hub.duplicate()
	outline.append(hub[0])
	c.draw_polyline(outline, dark, w)
	c.draw_circle(p.call(0.5, 0.3), s * 0.075, Color(1.0, 0.35, 0.12, 0.35) * tint)
	c.draw_circle(p.call(0.5, 0.3), s * 0.04, Color(1.0, 0.4, 0.15) * tint)
	for x: float in [0.33, 0.67]:
		c.draw_circle(p.call(x, 0.25), s * 0.015, brass)


## Corner to corner, head up and to the right: an ash shaft with leather
## bindings, an iron socket and a leaf-shaped head.
static func _spear(c: CanvasItem, o: Vector2, s: float, tint: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var wood := Color(0.62, 0.46, 0.28) * tint
	var wood_dark := Color(0.38, 0.27, 0.15) * tint
	var iron := Color(0.66, 0.68, 0.72) * tint
	var iron_dark := Color(0.38, 0.4, 0.45) * tint
	var dark := Color(0.12, 0.11, 0.12) * tint
	# The shaft, with a darker underside.
	c.draw_line(p.call(0.12, 0.88), p.call(0.66, 0.34), wood_dark, s * 0.065)
	c.draw_line(p.call(0.11, 0.87), p.call(0.65, 0.33), wood, s * 0.04)
	# Bindings.
	for t: float in [0.08, 0.62, 0.7]:
		var at: Vector2 = p.call(0.12, 0.88).lerp(p.call(0.66, 0.34), t)
		c.draw_line(at + Vector2(-0.035, -0.035) * s, at + Vector2(0.035, 0.035) * s, Color(0.2, 0.12, 0.06) * tint, s * 0.03)
	# Socket and the leaf blade.
	c.draw_line(p.call(0.64, 0.36), p.call(0.71, 0.29), iron_dark, s * 0.06)
	var blade := PackedVector2Array([p.call(0.69, 0.31), p.call(0.70, 0.22), p.call(0.80, 0.14),
		p.call(0.92, 0.08), p.call(0.86, 0.20), p.call(0.78, 0.30)])
	c.draw_colored_polygon(blade, iron)
	c.draw_colored_polygon(PackedVector2Array([p.call(0.70, 0.30), p.call(0.92, 0.08), p.call(0.86, 0.20),
		p.call(0.78, 0.30)]), iron_dark)
	c.draw_line(p.call(0.70, 0.30), p.call(0.91, 0.09), Color(0.95, 0.96, 0.98) * tint, maxf(1.0, s * 0.015))
	var outline := blade.duplicate()
	outline.append(blade[0])
	c.draw_polyline(outline, dark, maxf(1.0, s * 0.018))
	# Butt spike.
	c.draw_line(p.call(0.12, 0.88), p.call(0.07, 0.93), iron_dark, s * 0.045)


## The haft corner to corner, the bearded head up at the top right, its edge
## facing left.
static func _axe(c: CanvasItem, o: Vector2, s: float, tint: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var wood := Color(0.62, 0.46, 0.28) * tint
	var wood_dark := Color(0.38, 0.27, 0.15) * tint
	var iron := Color(0.62, 0.64, 0.68) * tint
	var iron_dark := Color(0.36, 0.38, 0.42) * tint
	var dark := Color(0.12, 0.11, 0.12) * tint
	# The haft, with a darker underside, and the leather grip at the end.
	c.draw_line(p.call(0.22, 0.9), p.call(0.72, 0.16), wood_dark, s * 0.075)
	c.draw_line(p.call(0.21, 0.89), p.call(0.71, 0.15), wood, s * 0.045)
	c.draw_line(p.call(0.22, 0.9), p.call(0.3, 0.78), Color(0.22, 0.13, 0.07) * tint, s * 0.08)
	c.draw_circle(p.call(0.2, 0.92), s * 0.04, iron_dark)
	# The head: a horn up top, the curved edge on the left, a long beard swept
	# back down to the haft.
	var head := PackedVector2Array([p.call(0.7, 0.14), p.call(0.56, 0.1), p.call(0.4, 0.04),
		p.call(0.34, 0.16), p.call(0.32, 0.3), p.call(0.36, 0.44), p.call(0.44, 0.4),
		p.call(0.54, 0.3), p.call(0.66, 0.28), p.call(0.76, 0.24)])
	c.draw_colored_polygon(head, iron)
	c.draw_colored_polygon(PackedVector2Array([p.call(0.56, 0.3), p.call(0.66, 0.28), p.call(0.76, 0.24),
		p.call(0.7, 0.14), p.call(0.56, 0.2)]), iron_dark)
	c.draw_polyline(PackedVector2Array([p.call(0.4, 0.04), p.call(0.34, 0.16), p.call(0.32, 0.3),
		p.call(0.36, 0.44)]), Color(0.95, 0.96, 0.98) * tint, maxf(1.0, s * 0.025))
	var outline := head.duplicate()
	outline.append(head[0])
	c.draw_polyline(outline, dark, maxf(1.0, s * 0.018))


## Points corner to corner, blade up and to the right.
static func _sword(c: CanvasItem, o: Vector2, s: float, tint: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var steel := Color(0.72, 0.74, 0.78) * tint
	var shade := Color(0.46, 0.48, 0.53) * tint
	var edge := Color(0.95, 0.96, 0.98) * tint
	var dark := Color(0.16, 0.16, 0.18) * tint
	# Blade: a long diamond from the guard to the tip -- one half lit, one half
	# in shadow down the fuller -- with a bright edge.
	c.draw_colored_polygon(PackedVector2Array([
		p.call(0.36, 0.56), p.call(0.82, 0.10), p.call(0.88, 0.12),
		p.call(0.90, 0.18), p.call(0.44, 0.64)]), steel)
	c.draw_colored_polygon(PackedVector2Array([
		p.call(0.40, 0.60), p.call(0.86, 0.14), p.call(0.90, 0.18), p.call(0.44, 0.64)]), shade)
	c.draw_line(p.call(0.38, 0.58), p.call(0.84, 0.12), edge, maxf(1.0, s * 0.02))
	c.draw_polyline(PackedVector2Array([
		p.call(0.36, 0.56), p.call(0.82, 0.10), p.call(0.88, 0.12),
		p.call(0.90, 0.18), p.call(0.44, 0.64), p.call(0.36, 0.56)]), dark, maxf(1.0, s * 0.02))
	# Cross-guard, in dull bronze with a lit top edge.
	c.draw_line(p.call(0.24, 0.52), p.call(0.48, 0.76), Color(0.42, 0.32, 0.16) * tint, s * 0.08)
	c.draw_line(p.call(0.25, 0.51), p.call(0.49, 0.75), Color(0.72, 0.58, 0.3) * tint, s * 0.025)
	# Grip, wrapped in leather.
	c.draw_line(p.call(0.37, 0.65), p.call(0.20, 0.82), Color(0.24, 0.15, 0.09) * tint, s * 0.075)
	for k in 3:
		var t := 0.25 + k * 0.25
		var at: Vector2 = p.call(0.37, 0.65).lerp(p.call(0.20, 0.82), t)
		c.draw_line(at + Vector2(-0.03, -0.03) * s, at + Vector2(0.03, 0.03) * s, Color(0.12, 0.07, 0.04) * tint, maxf(1.0, s * 0.015))
	# Pommel.
	c.draw_circle(p.call(0.17, 0.85), s * 0.055, Color(0.5, 0.38, 0.18) * tint)
	c.draw_circle(p.call(0.16, 0.84), s * 0.022, Color(0.85, 0.7, 0.4) * tint)


static func _potion(c: CanvasItem, o: Vector2, s: float, tint: Color) -> void:
	var centre := o + Vector2(0.5, 0.62) * s
	var r := s * 0.27
	var glass := Color(0.7, 0.78, 0.82, 0.5) * tint
	# Neck and cork.
	c.draw_rect(Rect2(o + Vector2(0.42, 0.18) * s, Vector2(0.16, 0.2) * s), glass)
	c.draw_rect(Rect2(o + Vector2(0.4, 0.1) * s, Vector2(0.2, 0.1) * s), Color(0.45, 0.3, 0.17) * tint)
	# The liquid -- the same glowing green as the potion in the hand -- then the
	# glass round it, then a highlight.
	c.draw_circle(centre, r * 1.25, Color(0.2, 1.0, 0.3, 0.12) * tint)
	c.draw_circle(centre, r, Color(0.03, 0.26, 0.08) * tint)
	c.draw_circle(centre + Vector2(0.0, r * 0.12), r * 0.86, Color(0.2, 0.78, 0.28) * tint)
	c.draw_circle(centre + Vector2(r * 0.15, r * 0.3), r * 0.5, Color(0.12, 0.55, 0.18) * tint)
	c.draw_arc(centre, r, 0.0, TAU, 32, glass.lightened(0.2), maxf(1.0, s * 0.03))
	c.draw_circle(centre + Vector2(-r * 0.4, -r * 0.4), r * 0.16, Color(1.0, 1.0, 1.0, 0.65) * tint)


## A splintered bone lying corner to corner: a knuckle at one end, a broken,
## jagged end at the other.
static func _bone(c: CanvasItem, o: Vector2, s: float, tint: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var bone := Color(0.84, 0.79, 0.66) * tint
	var shade := Color(0.6, 0.55, 0.44) * tint
	var dark := Color(0.25, 0.22, 0.17) * tint
	c.draw_line(p.call(0.3, 0.7), p.call(0.72, 0.28), dark, s * 0.15)
	c.draw_line(p.call(0.3, 0.7), p.call(0.72, 0.28), bone, s * 0.11)
	c.draw_line(p.call(0.34, 0.7), p.call(0.72, 0.32), shade, s * 0.035)
	# The knuckle: two knobs.
	for k: Vector2 in [Vector2(0.71, 0.21), Vector2(0.79, 0.29)]:
		c.draw_circle(p.call(k.x, k.y), s * 0.1, dark)
		c.draw_circle(p.call(k.x, k.y), s * 0.08, bone)
	# The broken end.
	c.draw_colored_polygon(PackedVector2Array([
		p.call(0.24, 0.68), p.call(0.31, 0.62), p.call(0.37, 0.69), p.call(0.29, 0.73),
		p.call(0.27, 0.82), p.call(0.22, 0.75)]), bone)
	c.draw_polyline(PackedVector2Array([
		p.call(0.24, 0.68), p.call(0.22, 0.75), p.call(0.27, 0.82), p.call(0.29, 0.73), p.call(0.37, 0.69)]),
		dark, maxf(1.0, s * 0.02))


## A skull, face on: dome, cheekbones, dark sockets and nose, a row of teeth.
static func _skull(c: CanvasItem, o: Vector2, s: float, tint: Color) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var bone := Color(0.88, 0.83, 0.7) * tint
	var shade := Color(0.62, 0.56, 0.44) * tint
	var hole := Color(0.08, 0.06, 0.05) * tint
	c.draw_circle(p.call(0.5, 0.44), s * 0.3, shade)
	c.draw_circle(p.call(0.5, 0.42), s * 0.28, bone)
	c.draw_rect(Rect2(p.call(0.34, 0.56), Vector2(0.32, 0.2) * s), bone)
	c.draw_rect(Rect2(p.call(0.34, 0.72), Vector2(0.32, 0.04) * s), shade)
	for side in [-1.0, 1.0]:
		c.draw_circle(p.call(0.5 + side * 0.12, 0.47), s * 0.08, hole)
	c.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.56), p.call(0.46, 0.64), p.call(0.54, 0.64)]), hole)
	for k in 4:
		var x := 0.38 + k * 0.08
		c.draw_line(p.call(x, 0.68), p.call(x, 0.76), hole, maxf(1.0, s * 0.02))


## A rat side on, nose to the left: a long tail curling up behind, a round ear
## and a bright eye. The robot one is grey iron with riveted plates and an
## enforcer's cyan eye and heart crystal (rat_model.gd).
static func _rat(c: CanvasItem, o: Vector2, s: float, tint: Color, robot: bool) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var body := (Color(0.42, 0.44, 0.47) if robot else Color(0.4, 0.32, 0.26)) * tint
	var shade := (Color(0.24, 0.25, 0.27) if robot else Color(0.24, 0.19, 0.15)) * tint
	var skin := (Color(0.3, 0.31, 0.33) if robot else Color(0.82, 0.56, 0.54)) * tint
	var dark := Color(0.08, 0.07, 0.07) * tint
	var glow := Color(0.0, 0.91, 1.0) * tint
	# The tail, from the rump curling up and back.
	var tail := PackedVector2Array()
	for k in 9:
		var t := float(k) / 8.0
		tail.append(p.call(0.72 + t * 0.2, 0.68 - sin(t * PI * 0.9) * 0.22 - t * 0.05))
	c.draw_polyline(tail, skin, maxf(1.5, s * 0.035), true)
	# Body and haunch, then the head and the snout.
	c.draw_set_transform(p.call(0.56, 0.6), 0.0, Vector2(1.0, 0.68))
	c.draw_circle(Vector2.ZERO, s * 0.22, shade)
	c.draw_circle(Vector2(0.0, -s * 0.02), s * 0.2, body)
	c.draw_set_transform(Vector2.ZERO)
	c.draw_circle(p.call(0.33, 0.56), s * 0.12, body)
	c.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.48), p.call(0.1, 0.6), p.call(0.3, 0.66)]), body)
	c.draw_circle(p.call(0.1, 0.6), s * 0.025, skin)
	# Feet.
	for x: float in [0.34, 0.66]:
		c.draw_line(p.call(x, 0.7), p.call(x - 0.03, 0.75), skin, maxf(1.0, s * 0.035))
	# The ear.
	c.draw_circle(p.call(0.36, 0.42), s * 0.07, shade)
	c.draw_circle(p.call(0.36, 0.43), s * 0.045, skin)
	if robot:
		# Plates and rivets down the back, the heart crystal, the antenna.
		c.draw_line(p.call(0.44, 0.48), p.call(0.72, 0.52), shade, maxf(1.0, s * 0.02))
		for x: float in [0.48, 0.58, 0.68]:
			c.draw_circle(p.call(x, 0.5), s * 0.014, Color(0.7, 0.72, 0.75) * tint)
		c.draw_circle(p.call(0.56, 0.62), s * 0.06, Color(glow, 0.3))
		c.draw_circle(p.call(0.56, 0.62), s * 0.03, glow)
		c.draw_line(p.call(0.4, 0.46), p.call(0.46, 0.3), shade, maxf(1.0, s * 0.02))
		c.draw_circle(p.call(0.46, 0.3), s * 0.025, glow)
		c.draw_circle(p.call(0.24, 0.54), s * 0.05, Color(glow, 0.35))
		c.draw_circle(p.call(0.24, 0.54), s * 0.028, glow)
	else:
		c.draw_circle(p.call(0.24, 0.54), s * 0.026, dark)
		c.draw_circle(p.call(0.235, 0.535), s * 0.009, Color(1, 1, 1, 0.8) * tint)


static func _coins(c: CanvasItem, o: Vector2, s: float, tint: Color) -> void:
	var gold := Color(0.92, 0.7, 0.24) * tint
	var rim := Color(0.5, 0.32, 0.07) * tint
	# A short stack at the back and one coin lying in front.
	for i in 4:
		var at := o + Vector2(0.62, 0.72 - i * 0.09) * s
		c.draw_set_transform(at, 0.0, Vector2(1.0, 0.45))
		c.draw_circle(Vector2.ZERO, s * 0.2, rim)
		c.draw_circle(Vector2(0.0, -s * 0.04), s * 0.19, gold)
	c.draw_set_transform(Vector2.ZERO)
	var front := o + Vector2(0.36, 0.6) * s
	c.draw_circle(front, s * 0.21, rim)
	c.draw_circle(front, s * 0.18, gold)
	c.draw_arc(front, s * 0.12, 0.0, TAU, 24, rim, maxf(1.0, s * 0.02))
	c.draw_circle(front, s * 0.07, gold.lightened(0.2))
	c.draw_circle(front + Vector2(-0.07, -0.07) * s, s * 0.035, Color(1.0, 1.0, 0.9, 0.75) * tint)
