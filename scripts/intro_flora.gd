extends RefCounted

## The intro forest's plants (note 131): firs, broadleaves, ferns, bushes, grass
## and fallen logs. STAND-INS: the user's rule (note 98) is that models come from
## Higgsfield, but no generation was available when the intro was built (no
## generation tool on the connector, 7 credits, no TRIPO_API_KEY), and the user
## chose stand-ins made in code to be swapped for Higgsfield models later. Every
## mesh and texture here is built once and cached.
##
## Foliage is alpha-cut cards (shaders/intro_foliage.gdshader) with normals bent
## out from the plant's middle, so a crown lights as a mass, not as flat
## sheets; the textures are painted here into Images (needles, leaves, fern
## fronds, grass blades, bark).

const FOLIAGE_SHADER := preload("res://shaders/intro_foliage.gdshader")

static var _tex := {}
static var _mesh := {}
static var _mat := {}


# --- Painting ------------------------------------------------------------------

## An empty canvas whose clear pixels carry `bleed` (no dark fringe when the
## mipmaps blend the cut-out edge into them).
static func _canvas(w: int, h: int, bleed: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(bleed.r, bleed.g, bleed.b, 0.0))
	return img


## A tapered stroke from `a` (radius r0) to `b` (radius r1), anti-aliased.
static func _stroke(img: Image, a: Vector2, b: Vector2, r0: float, r1: float, col: Color) -> void:
	var r := maxf(r0, r1) + 1.0
	var x0 := clampi(int(floor(minf(a.x, b.x) - r)), 0, img.get_width() - 1)
	var x1 := clampi(int(ceil(maxf(a.x, b.x) + r)), 0, img.get_width() - 1)
	var y0 := clampi(int(floor(minf(a.y, b.y) - r)), 0, img.get_height() - 1)
	var y1 := clampi(int(ceil(maxf(a.y, b.y) + r)), 0, img.get_height() - 1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var cov := clampf(lerpf(r0, r1, t) - d + 0.5, 0.0, 1.0)
			if cov <= 0.0:
				continue
			var src := Color(col.r, col.g, col.b, col.a * cov)
			img.set_pixel(x, y, img.get_pixel(x, y).blend(src))


## A pointed leaf: centre `c`, pointing along `dir`, `length` long, `width` wide.
static func _leaf(img: Image, c: Vector2, dir: Vector2, length: float, width: float, col: Color) -> void:
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var r := length * 0.5 + 1.0
	var x0 := clampi(int(c.x - r), 0, img.get_width() - 1)
	var x1 := clampi(int(c.x + r), 0, img.get_width() - 1)
	var y0 := clampi(int(c.y - r), 0, img.get_height() - 1)
	var y1 := clampi(int(c.y + r), 0, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5) - c
			var u := p.dot(dir) / (length * 0.5)
			if absf(u) >= 1.0:
				continue
			var t := (u + 1.0) * 0.5
			var half := width * 0.5 * pow(sin(PI * t), 0.75)
			var v := p.dot(side)
			var cov := clampf(half - absf(v) + 0.5, 0.0, 1.0)
			if cov <= 0.0:
				continue
			# Darker along the midrib, lighter toward the edge.
			var shade := lerpf(0.82, 1.08, clampf(absf(v) / maxf(half, 0.01), 0.0, 1.0))
			var src := Color(col.r * shade, col.g * shade, col.b * shade, cov)
			img.set_pixel(x, y, img.get_pixel(x, y).blend(src))


static func _texture(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A fir branch seen from above: a stem up the middle (v 1 at the trunk, 0 at
## the tip) and side shoots thick with needles.
static func needles() -> Texture2D:
	if _tex.has(&"needles"):
		return _tex[&"needles"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7301
	var w := 128
	var h := 256
	var img := _canvas(w, h, Color(0.1, 0.2, 0.11))
	var stem_a := Vector2(w * 0.5, h - 4.0)
	var stem_b := Vector2(w * 0.5 + 3.0, 6.0)
	# Side shoots, longest near the trunk.
	var shoots := 11
	for i in shoots:
		var t := (float(i) + 0.5) / float(shoots)
		var at := stem_a.lerp(stem_b, t * 0.94)
		for s: float in [-1.0, 1.0]:
			var reach := (w * 0.46) * (1.0 - t * 0.55) * rng.randf_range(0.8, 1.05)
			var tip := at + Vector2(s * reach, -reach * 0.55)
			var dark := Color(0.07, 0.15, 0.08)
			_stroke(img, at, tip, 1.4, 0.6, dark)
			var n := int(reach / 2.4)
			for k in n:
				var q := float(k) / float(maxi(n, 1))
				var base := at.lerp(tip, q)
				for side: float in [-1.0, 1.0]:
					var ang := Vector2(s, -0.6).normalized().rotated(side * rng.randf_range(0.7, 1.1))
					var nl := rng.randf_range(6.0, 10.0) * (1.0 - q * 0.4)
					var g := rng.randf_range(0.0, 1.0)
					var col := Color(lerpf(0.09, 0.17, g), lerpf(0.19, 0.31, g), lerpf(0.09, 0.15, g))
					_stroke(img, base, base + ang * nl, 0.9, 0.4, col)
	# Needles straight off the stem, and the stem itself.
	for k in 70:
		var t := float(k) / 70.0
		var base := stem_a.lerp(stem_b, t)
		for s: float in [-1.0, 1.0]:
			var ang := Vector2(s, -0.9).normalized().rotated(rng.randf_range(-0.3, 0.3))
			var g := rng.randf()
			_stroke(img, base, base + ang * rng.randf_range(7.0, 12.0) * (1.0 - t * 0.5), 1.0, 0.4,
				Color(lerpf(0.1, 0.2, g), lerpf(0.21, 0.34, g), lerpf(0.1, 0.16, g)))
	_stroke(img, stem_a, stem_b, 2.2, 0.8, Color(0.16, 0.12, 0.08))
	var tex := _texture(img)
	_tex[&"needles"] = tex
	return tex


## A spray of broad leaves (beech / oak-ish), filling the square.
static func leaves() -> Texture2D:
	if _tex.has(&"leaves"):
		return _tex[&"leaves"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410
	var s := 256
	var img := _canvas(s, s, Color(0.2, 0.3, 0.1))
	var c := Vector2(s * 0.5, s * 0.5)
	# Twigs out from the middle, leaves along them.
	for i in 7:
		var ang := TAU * float(i) / 7.0 + rng.randf_range(-0.2, 0.2)
		var dir := Vector2(cos(ang), sin(ang))
		var tip := c + dir * s * rng.randf_range(0.36, 0.46)
		_stroke(img, c, tip, 1.6, 0.7, Color(0.18, 0.13, 0.08))
		for k in 5:
			var q := 0.25 + 0.75 * float(k) / 4.0
			var at := c.lerp(tip, q)
			for side: float in [-1.0, 1.0]:
				var ld := dir.rotated(side * rng.randf_range(0.5, 0.9))
				var length := rng.randf_range(26.0, 38.0)
				var g := rng.randf()
				var col := Color(lerpf(0.2, 0.34, g), lerpf(0.3, 0.46, g), lerpf(0.08, 0.14, g))
				_leaf(img, at + ld * length * 0.45, ld, length, length * 0.45, col)
		_leaf(img, tip + dir * 12.0, dir, 30.0, 13.0, Color(0.3, 0.42, 0.12))
	var tex := _texture(img)
	_tex[&"leaves"] = tex
	return tex


## A fern frond: v 1 at the root, 0 at the tip, pinnae either side.
static func fern() -> Texture2D:
	if _tex.has(&"fern"):
		return _tex[&"fern"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var w := 128
	var h := 256
	var img := _canvas(w, h, Color(0.16, 0.3, 0.1))
	var a := Vector2(w * 0.5, h - 2.0)
	var b := Vector2(w * 0.5, 4.0)
	var n := 22
	for i in n:
		var t := float(i) / float(n)
		var at := a.lerp(b, 0.08 + t * 0.9)
		var reach := w * 0.44 * sin(PI * clampf(0.12 + t * 0.95, 0.0, 1.0))
		for s: float in [-1.0, 1.0]:
			var dir := Vector2(s, -0.35).normalized()
			var g := rng.randf()
			var col := Color(lerpf(0.17, 0.27, g), lerpf(0.32, 0.46, g), lerpf(0.08, 0.13, g))
			# Each pinna a row of little lobes.
			var lobes := maxi(2, int(reach / 5.0))
			for k in lobes:
				var q := float(k) / float(lobes)
				_leaf(img, at + dir * reach * (q + 0.08), dir.rotated(s * 0.5), 9.0 * (1.0 - q * 0.4), 5.0, col)
	_stroke(img, a, b, 1.8, 0.6, Color(0.2, 0.26, 0.1))
	var tex := _texture(img)
	_tex[&"fern"] = tex
	return tex


## Grass blades, rooted along the bottom (v 1).
static func grass() -> Texture2D:
	if _tex.has(&"grass"):
		return _tex[&"grass"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var s := 128
	var img := _canvas(s, s, Color(0.3, 0.38, 0.14))
	for i in 46:
		var x := rng.randf_range(6.0, s - 6.0)
		var top := Vector2(x + rng.randf_range(-18.0, 18.0), rng.randf_range(6.0, 60.0))
		var g := rng.randf()
		var col := Color(lerpf(0.26, 0.48, g), lerpf(0.34, 0.52, g), lerpf(0.1, 0.18, g))
		if rng.randf() < 0.2:
			col = Color(0.55, 0.5, 0.3)
		_stroke(img, Vector2(x, s - 1.0), top, 1.8, 0.4, col)
	var tex := _texture(img)
	_tex[&"grass"] = tex
	return tex


## Bark: deep vertical furrows, as albedo and a normal map.
static func bark() -> Array:
	if _tex.has(&"bark"):
		return _tex[&"bark"]
	var noise := FastNoiseLite.new()
	noise.seed = 302
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	var w := 128
	var h := 256
	var height := PackedFloat32Array()
	height.resize(w * h)
	for y in h:
		for x in w:
			# Stretched up the trunk: furrows, not blotches. Tiles in x.
			var a := TAU * float(x) / float(w)
			var n := noise.get_noise_3d(cos(a) * 2.4, float(y) / float(h) * 3.0, sin(a) * 2.4)
			var furrow := absf(sin(a * 7.0 + n * 3.5))
			height[y * w + x] = clampf(0.55 * furrow + 0.45 * (n * 0.5 + 0.5), 0.0, 1.0)
	var col := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var nrm := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := height[y * w + x]
			col.set_pixel(x, y, Color(0.2 + 0.2 * v, 0.15 + 0.15 * v, 0.11 + 0.1 * v))
			var dx := height[y * w + (x + 1) % w] - height[y * w + (x - 1 + w) % w]
			var dy := height[((y + 1) % h) * w + x] - height[((y - 1 + h) % h) * w + x]
			var n := Vector3(-dx * 2.5, dy * 2.5, 1.0).normalized()
			nrm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	var out := [_texture(col), _texture(nrm)]
	_tex[&"bark"] = out
	return out


# --- Materials -------------------------------------------------------------------

static func foliage_material(which: StringName) -> ShaderMaterial:
	if _mat.has(which):
		return _mat[which]
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	match which:
		&"needles":
			m.set_shader_parameter(&"albedo_tex", needles())
			m.set_shader_parameter(&"tint", Color(0.95, 1.0, 0.95))
			m.set_shader_parameter(&"translucency", 0.35)
			m.set_shader_parameter(&"sway", 0.8)
		&"leaves":
			m.set_shader_parameter(&"albedo_tex", leaves())
			m.set_shader_parameter(&"translucency", 0.7)
			m.set_shader_parameter(&"sway", 1.0)
		&"fern":
			m.set_shader_parameter(&"albedo_tex", fern())
			m.set_shader_parameter(&"translucency", 0.6)
			m.set_shader_parameter(&"sway", 0.6)
		&"grass":
			m.set_shader_parameter(&"albedo_tex", grass())
			m.set_shader_parameter(&"translucency", 0.5)
			m.set_shader_parameter(&"sway", 0.5)
			m.set_shader_parameter(&"cutoff", 0.35)
	_mat[which] = m
	return m


static func bark_material() -> StandardMaterial3D:
	if _mat.has(&"bark"):
		return _mat[&"bark"]
	var t: Array = bark()
	var m := StandardMaterial3D.new()
	m.albedo_texture = t[0]
	m.normal_enabled = true
	m.normal_texture = t[1]
	m.normal_scale = 1.4
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat[&"bark"] = m
	return m


# --- Geometry helpers --------------------------------------------------------------

## A card: corners `a` (root left), `b` (root right), `c` (tip right), `d` (tip
## left); UV v 1 at the root, 0 at the tip. Sway and light at root / tip;
## normals bent out from `centre`.
static func _card(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Vector3,
		sway_root: float, sway_tip: float, light_root: float, light_tip: float, up_bias := 0.5) -> void:
	var pts := [a, b, c, d]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	var sw := [sway_root, sway_root, sway_tip, sway_tip]
	var li := [light_root, light_root, light_tip, light_tip]
	for i: int in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = pts[i]
		var n := (p - centre)
		n.y = maxf(n.y, 0.0)
		n = (n.normalized() + Vector3.UP * up_bias).normalized()
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.set_color(Color(sw[i], li[i], 0.0))
		st.add_vertex(p)


## A tapered tube along `a` -> `b`, `sides` round, its bark tiled `v_per_m`.
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int,
		v_from: float, v_per_m := 0.6) -> float:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var other := axis.cross(side)
	var length := a.distance_to(b)
	var v_to := v_from + length * v_per_m
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var n0 := side * cos(a0) + other * sin(a0)
		var n1 := side * cos(a1) + other * sin(a1)
		var u0 := float(i) / float(sides)
		var u1 := float(i + 1) / float(sides)
		var q := [[a + n0 * ra, n0, Vector2(u0, v_from)], [a + n1 * ra, n1, Vector2(u1, v_from)],
			[b + n1 * rb, n1, Vector2(u1, v_to)], [b + n0 * rb, n0, Vector2(u0, v_to)]]
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(q[k][1])
			st.set_uv(q[k][2])
			st.add_vertex(q[k][0])
	return v_to


static func _commit(trunk: SurfaceTool, foliage: SurfaceTool, foliage_mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if trunk != null:
		trunk.generate_tangents()
		trunk.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, bark_material())
	if foliage != null:
		foliage.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, foliage_mat)
	return mesh


# --- Plants ------------------------------------------------------------------------

## A fir about `height` m tall, variant `seed_`: whorls of drooping branch cards
## (two each, in a shallow V) up a tapering trunk.
static func fir(variant: int) -> ArrayMesh:
	var key := StringName("fir%d" % variant)
	if _mesh.has(key):
		return _mesh[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant
	var height: float = [17.0, 21.0, 14.0][variant % 3]
	var base_r := height * rng.randf_range(0.19, 0.23)
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tr := height * 0.022
	_tube(trunk, Vector3(0, -0.4, 0), Vector3(0, height * 0.35, 0), tr * 1.25, tr, 8, 0.0)
	_tube(trunk, Vector3(0, height * 0.35, 0), Vector3(0, height * 0.97, 0), tr, 0.03, 8, height * 0.35 * 0.6)
	var low := height * 0.18
	var whorls := int(height / 0.75)
	var turn := 0.0
	for k in whorls:
		var t := float(k) / float(whorls - 1)
		var y := lerpf(low, height * 0.98, t)
		var r := base_r * pow(1.0 - t, 0.85) + 0.35
		var count := 7 if t < 0.6 else 5
		turn += 2.39996
		for j in count:
			var ang := turn + TAU * float(j) / float(count) + rng.randf_range(-0.25, 0.25)
			var out := Vector3(cos(ang), 0.0, sin(ang))
			var across := Vector3(-out.z, 0.0, out.x)
			var length := r * rng.randf_range(0.85, 1.1)
			var droop := length * lerpf(0.42, 0.18, t)
			var width := length * 0.62
			var root := Vector3(0.0, y, 0.0) + out * 0.08
			var tip := root + out * length + Vector3(0.0, -droop, 0.0)
			var centre := Vector3(0.0, y - droop * 0.5, 0.0)
			# Two cards rolled up either side of the branch: a shallow V.
			for roll: float in [-0.45, 0.45]:
				var w := (across * cos(roll) + Vector3.UP * sin(roll)) * width * 0.5
				var w_root := w * 0.35
				var light_root := lerpf(0.35, 0.6, t)
				_card(foliage, root - w_root, root + w_root, tip + w, tip - w, centre,
					0.05 + t * 0.2, 0.45 + t * 0.5, light_root, 1.0)
	# The leader.
	var top := Vector3(0, height * 0.97, 0)
	for j in 3:
		var ang := TAU * float(j) / 3.0
		var w := Vector3(cos(ang), 0, sin(ang)) * 0.35
		_card(foliage, top - w + Vector3(0, -1.2, 0), top + w + Vector3(0, -1.2, 0), top + w * 0.2 + Vector3(0, 0.6, 0),
			top - w * 0.2 + Vector3(0, 0.6, 0), top, 0.5, 1.0, 0.8, 1.0, 1.0)
	var mesh := _commit(trunk, foliage, foliage_material(&"needles"))
	_mesh[key] = mesh
	return mesh


## A broadleaf: a trunk splitting into boughs, the crown a mass of leaf clusters.
static func broadleaf(variant: int) -> ArrayMesh:
	var key := StringName("broad%d" % variant)
	if _mesh.has(key):
		return _mesh[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + variant
	var height: float = [13.0, 16.0][variant % 2]
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tr := height * 0.03
	var fork := Vector3(rng.randf_range(-0.3, 0.3), height * 0.42, rng.randf_range(-0.3, 0.3))
	_tube(trunk, Vector3(0, -0.4, 0), fork, tr * 1.3, tr, 9, 0.0)
	var crown := Vector3(fork.x, height * 0.66, fork.z)
	var crown_r := Vector3(height * 0.33, height * 0.27, height * 0.33)
	var bough_ends: Array[Vector3] = []
	for i in 4:
		var ang := TAU * float(i) / 4.0 + rng.randf_range(-0.4, 0.4)
		var end := crown + Vector3(cos(ang) * crown_r.x * 0.62, rng.randf_range(0.0, crown_r.y * 0.5), sin(ang) * crown_r.z * 0.62)
		_tube(trunk, fork, end, tr * 0.65, tr * 0.18, 6, 0.0)
		bough_ends.append(end)
	# Leaf clusters through the crown's volume, denser toward its skin.
	for i in 46:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1))
		if d.length() > 1.0:
			d = d.normalized()
		d = d.normalized() * pow(rng.randf_range(0.35, 1.0), 0.6)
		var at := crown + Vector3(d.x * crown_r.x, d.y * crown_r.y, d.z * crown_r.z)
		var size := rng.randf_range(1.5, 2.4)
		var light := clampf(0.4 + 0.6 * d.length() + d.y * 0.2, 0.3, 1.0)
		for k in 2:
			var a := rng.randf() * PI + float(k) * PI * 0.5
			var u := Vector3(cos(a), rng.randf_range(-0.4, 0.4), sin(a)).normalized() * size * 0.5
			var v := u.cross(Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3))).normalized() * size * 0.5
			_card(foliage, at - u + v, at + u + v, at + u - v, at - u - v, crown, 0.5, 0.9, light, light, 0.3)
	var mesh := _commit(trunk, foliage, foliage_material(&"leaves"))
	_mesh[key] = mesh
	return mesh


## A fern: arched fronds round a crown.
static func fern_plant() -> ArrayMesh:
	if _mesh.has(&"fern"):
		return _mesh[&"fern"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0, 0.25, 0)
	for i in 9:
		var ang := TAU * float(i) / 9.0 + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(ang), 0, sin(ang))
		var across := Vector3(-out.z, 0, out.x)
		var length := rng.randf_range(0.75, 1.1)
		var w := across * 0.17
		var root := out * 0.04
		var mid := out * length * 0.5 + Vector3(0, length * 0.42, 0)
		var tip := out * length + Vector3(0, length * 0.18, 0)
		# Two segments sharing the frond's texture: root half, then tip half.
		_fern_seg(st, root - w * 0.4, root + w * 0.4, mid + w, mid - w, 1.0, 0.5, centre, 0.1, 0.6)
		_fern_seg(st, mid - w, mid + w, tip + w * 0.2, tip - w * 0.2, 0.5, 0.0, centre, 0.6, 1.0)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, foliage_material(&"fern"))
	_mesh[&"fern"] = mesh
	return mesh


static func _fern_seg(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, v0: float, v1: float,
		centre: Vector3, s0: float, s1: float) -> void:
	var pts := [a, b, c, d]
	var uvs := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
	var sw := [s0, s0, s1, s1]
	for i: int in [0, 1, 2, 0, 2, 3]:
		var n := ((pts[i] as Vector3) - centre).normalized() + Vector3.UP
		st.set_normal(n.normalized())
		st.set_uv(uvs[i])
		st.set_color(Color(sw[i], 0.55 + 0.45 * sw[i], 0.0))
		st.add_vertex(pts[i])


## A bush: a low mound of leaf clusters.
static func bush() -> ArrayMesh:
	if _mesh.has(&"bush"):
		return _mesh[&"bush"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0, 0.45, 0)
	for i in 14:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), rng.randf_range(-1, 1)).normalized()
		var at := centre + Vector3(d.x * 0.85, d.y * 0.55 - 0.1, d.z * 0.85)
		var size := rng.randf_range(0.8, 1.2)
		var a := rng.randf() * PI
		var u := Vector3(cos(a), rng.randf_range(-0.3, 0.3), sin(a)).normalized() * size * 0.5
		var v := u.cross(Vector3.UP).cross(u).normalized() * size * -0.5
		_card(st, at - u + v, at + u + v, at + u - v, at - u - v, centre, 0.3, 0.7, 0.5, 1.0, 0.4)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, foliage_material(&"leaves"))
	_mesh[&"bush"] = mesh
	return mesh


## A tuft of grass: three crossed cards, swaying at the top.
static func grass_tuft() -> ArrayMesh:
	if _mesh.has(&"grass"):
		return _mesh[&"grass"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := PI * float(i) / 3.0
		var u := Vector3(cos(a), 0, sin(a)) * 0.32
		var up := Vector3(0, 0.55, 0)
		var pts := [-u, u, u + up, -u + up]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[k])
			var top := 1.0 if k >= 2 else 0.0
			st.set_color(Color(top, 0.6 + 0.4 * top, 0.0))
			st.add_vertex(pts[k])
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, foliage_material(&"grass"))
	_mesh[&"grass"] = mesh
	return mesh


## A fallen trunk, lying along X, `length` m, its butt at -X.
static func log_mesh() -> ArrayMesh:
	if _mesh.has(&"log"):
		return _mesh[&"log"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, Vector3(-3.2, 0, 0), Vector3(3.2, 0.05, 0.1), 0.42, 0.3, 10, 0.0)
	# The broken-off end and the butt, capped.
	for end: Array in [[Vector3(-3.2, 0, 0), 0.42, -1.0], [Vector3(3.2, 0.05, 0.1), 0.3, 1.0]]:
		var c: Vector3 = end[0]
		var r: float = end[1]
		var s: float = end[2]
		for i in 10:
			var a0 := TAU * float(i) / 10.0
			var a1 := TAU * float(i + 1) / 10.0
			var p0 := c + Vector3(0, cos(a0), sin(a0)) * r
			var p1 := c + Vector3(0, cos(a1), sin(a1)) * r
			# Clockwise seen from outside (Godot's front face).
			var tri := [c, p1, p0] if s > 0.0 else [c, p0, p1]
			for p: Vector3 in tri:
				st.set_normal(Vector3(s, 0, 0))
				st.set_uv(Vector2(p.y, p.z) * 0.5)
				st.add_vertex(p)
	st.generate_tangents()
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	_mesh[&"log"] = mesh
	return mesh
