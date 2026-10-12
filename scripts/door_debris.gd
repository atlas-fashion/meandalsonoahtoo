extends RefCounted

## Breaks a door leaf into pieces that tumble and fall: the leaf's own mesh cut
## into an uneven grid of chunks, each a RigidBody3D with a box the size of its
## chunk. Used by wood_door.gd when a door is kicked in.
##
## The cut is by triangle -- each triangle goes to the chunk its centre is in --
## so a chunk is made of the leaf's own boards, iron and all, with its materials.
## The cuts are worked out once per leaf mesh and grid and cached; every door
## shares the same two leaf meshes, so after the first kick it is instant.
##
## Pieces collide with the floor, the walls and each other, never with the
## player or the enemies: a corridor must not be blocked by its own rubble.

const DEBRIS_LAYER := 1 << 12
## Floor and gates (1), the sight layer (2: walls, shut doors), exact walls (9),
## and other debris.
const DEBRIS_MASK := 1 | 2 | 256 | DEBRIS_LAYER

## The boards' plane in a leaf's mesh, and their thickness with the back that
## build_gate_door.py mirrors on.
const BOARD_PLANE := -0.03
const BOARD_THICK := 0.08

static var _cache := {}

const DISSOLVE := preload("res://shaders/debris_dissolve.gdshader")
## Each piece crumbles to nothing this long after the break, at random.
const CRUMBLE_MIN := 1.0
const CRUMBLE_MAX := 3.0
## How hard a kicked door's pieces are thrown away from the player, m/s.
const LAUNCH_MIN := 10.0
const LAUNCH_MAX := 15.0
const CRUMBLE_TIME := 0.55
static var _dissolve_mats := {}
static var _noise: NoiseTexture2D


## The chunks of `mesh` cut `cols` x `rows`: [{mesh, centre, size}], each mesh
## centred on its own chunk so a body can spin about it.
##
## `slant` tilts every cut line by up to that slope (each its own), so the pieces
## come out as uneven splintered shapes rather than a grid of rectangles; with
## `merge_top` the top row is one piece (a pointed leaf's head is too narrow to
## split). Brick doors: 2 x 3, slant 0.55, merged top -> 5 pieces (2026-10-10).
static func pieces_for(mesh: Mesh, cols: int, rows: int, slant := 0.0, merge_top := false) -> Array:
	var key := "%d:%d:%d:%.2f:%s" % [mesh.get_instance_id(), cols, rows, slant, merge_top]
	if _cache.has(key):
		return _cache[key]
	var box := mesh.get_aabb()
	# Uneven cuts, so it reads as split wood rather than a grid. Fixed seed: the
	# same leaf always breaks the same way, and the cache stays valid.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + cols * 31 + rows
	var xs := _cuts(box.position.x, box.size.x, cols, rng)
	var ys := _cuts(box.position.y, box.size.y, rows, rng)
	if slant > 0.0:
		return _slanted(mesh, box, xs, ys, cols, rows, slant, merge_top, rng, key)

	# Every triangle is CLIPPED to each chunk it crosses. The Tripo leaves are
	# made of big triangles -- some run the door's full height -- and sorting
	# whole triangles by their centre gave "chunks" carrying metre-long slivers,
	# which spun into a fan of needle shards. Clipped, a chunk is its own size.
	var polys := {}     # cell -> [[surface, [vertex, ...]], ...]
	var lo := {}
	var hi := {}
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var normals = arr[Mesh.ARRAY_NORMAL]
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		var index = arr[Mesh.ARRAY_INDEX]
		var count: int = (index.size() if index != null else verts.size()) / 3
		for t in count:
			var tri := []
			for k in 3:
				var i: int = index[t * 3 + k] if index != null else t * 3 + k
				tri.append({
					"p": verts[i],
					"n": normals[i] if normals != null else Vector3.BACK,
					"uv": uvs[i] if uvs != null else Vector2.ZERO,
				})
			var bmin: Vector3 = (tri[0]["p"] as Vector3).min(tri[1]["p"]).min(tri[2]["p"])
			var bmax: Vector3 = (tri[0]["p"] as Vector3).max(tri[1]["p"]).max(tri[2]["p"])
			for iy in range(_bucket(ys, bmin.y), _bucket(ys, bmax.y) + 1):
				for ix in range(_bucket(xs, bmin.x), _bucket(xs, bmax.x) + 1):
					var poly := tri
					# The outermost cells reach to infinity, so nothing is lost.
					if ix > 0:
						poly = _clip(poly, 0, float(xs[ix]), true)
					if ix < cols - 1:
						poly = _clip(poly, 0, float(xs[ix + 1]), false)
					if iy > 0:
						poly = _clip(poly, 1, float(ys[iy]), true)
					if iy < rows - 1:
						poly = _clip(poly, 1, float(ys[iy + 1]), false)
					if poly.size() < 3:
						continue
					var cell := iy * cols + ix
					if not polys.has(cell):
						polys[cell] = []
						lo[cell] = Vector3(INF, INF, INF)
						hi[cell] = Vector3(-INF, -INF, -INF)
					polys[cell].append([s, poly])
					for v in poly:
						lo[cell] = (lo[cell] as Vector3).min(v["p"])
						hi[cell] = (hi[cell] as Vector3).max(v["p"])

	# A mesh per chunk, one surface per source surface, centred on the chunk.
	var out := []
	for cell in polys:
		var centre: Vector3 = ((lo[cell] as Vector3) + (hi[cell] as Vector3)) * 0.5
		var tools := {}
		for entry in polys[cell]:
			var s: int = entry[0]
			var poly: Array = entry[1]
			if not tools.has(s):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[s] = st
			for k in range(1, poly.size() - 1):
				for v in [poly[0], poly[k], poly[k + 1]]:
					tools[s].set_normal(v["n"])
					tools[s].set_uv(v["uv"])
					tools[s].add_vertex((v["p"] as Vector3) - centre)
		var piece := ArrayMesh.new()
		for s in tools:
			var st: SurfaceTool = tools[s]
			st.generate_tangents()
			st.set_material(mesh.surface_get_material(s))
			piece = st.commit(piece)
		out.append({"mesh": piece, "centre": centre,
			"size": ((hi[cell] as Vector3) - (lo[cell] as Vector3)).max(Vector3(0.06, 0.06, 0.06))})
	_cache[key] = out
	return out


## Sutherland-Hodgman against one axis-aligned plane: keeps the part of `poly`
## with coordinate `axis` >= `value` (`keep_above`) or <= it, interpolating
## position, normal and UV along any edge it cuts.
static func _clip(poly: Array, axis: int, value: float, keep_above: bool) -> Array:
	var out := []
	var n := poly.size()
	for i in n:
		var a: Dictionary = poly[i]
		var b: Dictionary = poly[(i + 1) % n]
		var pa: float = (a["p"] as Vector3)[axis]
		var pb: float = (b["p"] as Vector3)[axis]
		var a_in := pa >= value if keep_above else pa <= value
		var b_in := pb >= value if keep_above else pb <= value
		if a_in:
			out.append(a)
		if a_in != b_in:
			var t := (value - pa) / (pb - pa)
			out.append({
				"p": (a["p"] as Vector3).lerp(b["p"], t),
				"n": (a["n"] as Vector3).lerp(b["n"], t).normalized(),
				"uv": (a["uv"] as Vector2).lerp(b["uv"], t),
			})
	return out

## Cuts along tilted lines: column cut i is x = xs[i] + kx (y - mid y), row cut
## j is y = ys[j] + ky (x - mid x), each slope its own. Every triangle is clipped
## against every cell (the cells are few), so nothing is lost to the slants.
static func _slanted(mesh: Mesh, box: AABB, xs: Array, ys: Array, cols: int, rows: int,
		slant: float, merge_top: bool, rng: RandomNumberGenerator, key: String) -> Array:
	var mid := box.get_center()
	var vcuts := []   # [normal, d] with normal . p >= d to the right of the cut
	for i in range(1, cols):
		var k := rng.randf_range(-slant, slant)
		vcuts.append([Vector3(1.0, -k, 0.0), float(xs[i]) - k * mid.y])
	var hcuts := []
	for j in range(1, rows):
		var k := rng.randf_range(-slant, slant)
		hcuts.append([Vector3(-k, 1.0, 0.0), float(ys[j]) - k * mid.x])
	var cells := []
	for iy in rows:
		for ix in cols:
			if merge_top and iy == rows - 1 and ix > 0:
				continue
			var planes := []
			var whole_row := merge_top and iy == rows - 1
			if not whole_row and ix > 0:
				planes.append([vcuts[ix - 1][0], vcuts[ix - 1][1], true])
			if not whole_row and ix < cols - 1:
				planes.append([vcuts[ix][0], vcuts[ix][1], false])
			if iy > 0:
				planes.append([hcuts[iy - 1][0], hcuts[iy - 1][1], true])
			if iy < rows - 1:
				planes.append([hcuts[iy][0], hcuts[iy][1], false])
			cells.append(planes)
	var out := []
	for planes in cells:
		var tools := {}
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var polys := []
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var normals = arr[Mesh.ARRAY_NORMAL]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var index = arr[Mesh.ARRAY_INDEX]
			var count: int = (index.size() if index != null else verts.size()) / 3
			for t in count:
				var poly := []
				for kk in 3:
					var i: int = index[t * 3 + kk] if index != null else t * 3 + kk
					poly.append({"p": verts[i], "n": normals[i] if normals != null else Vector3.BACK,
						"uv": uvs[i] if uvs != null else Vector2.ZERO})
				for pl in planes:
					poly = _clip_plane(poly, pl[0], pl[1], pl[2])
					if poly.size() < 3:
						break
				if poly.size() < 3:
					continue
				polys.append([s, poly])
				for v in poly:
					lo = lo.min(v["p"])
					hi = hi.max(v["p"])
		if polys.is_empty():
			continue
		var centre := (lo + hi) * 0.5
		for entry in polys:
			var s: int = entry[0]
			var poly: Array = entry[1]
			if not tools.has(s):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[s] = st
			for kk in range(1, poly.size() - 1):
				for v in [poly[0], poly[kk], poly[kk + 1]]:
					tools[s].set_normal(v["n"])
					tools[s].set_uv(v["uv"])
					tools[s].add_vertex((v["p"] as Vector3) - centre)
		var piece := ArrayMesh.new()
		for s in tools:
			var st: SurfaceTool = tools[s]
			st.generate_tangents()
			st.set_material(mesh.surface_get_material(s))
			piece = st.commit(piece)
		out.append({"mesh": piece, "centre": centre, "size": (hi - lo).max(Vector3(0.06, 0.06, 0.06))})
	_cache[key] = out
	return out


## Sutherland-Hodgman against the plane normal . p = d.
static func _clip_plane(poly: Array, normal: Vector3, d: float, keep_above: bool) -> Array:
	var out := []
	var n := poly.size()
	for i in n:
		var a: Dictionary = poly[i]
		var b: Dictionary = poly[(i + 1) % n]
		var pa: float = normal.dot(a["p"]) - d
		var pb: float = normal.dot(b["p"]) - d
		var a_in := pa >= 0.0 if keep_above else pa <= 0.0
		var b_in := pb >= 0.0 if keep_above else pb <= 0.0
		if a_in:
			out.append(a)
		if a_in != b_in:
			var t := pa / (pa - pb)
			out.append({
				"p": (a["p"] as Vector3).lerp(b["p"], t),
				"n": (a["n"] as Vector3).lerp(b["n"], t).normalized(),
				"uv": (a["uv"] as Vector2).lerp(b["uv"], t),
			})
	return out


static func _cuts(start: float, length: float, n: int, rng: RandomNumberGenerator) -> Array:
	var cuts := [start]
	for i in range(1, n):
		cuts.append(start + length * (float(i) / float(n) + rng.randf_range(-0.3, 0.3) / float(n)))
	cuts.append(start + length)
	return cuts


static func _bucket(cuts: Array, v: float) -> int:
	for i in range(1, cuts.size() - 1):
		if v < float(cuts[i]):
			return i - 1
	return cuts.size() - 2


## Replaces the leaf drawn by `leaf_mesh` with its chunks, flying along `push`
## (a unit vector), hardest nearest `impact` (world). Returns the bodies.
static func shatter(leaf_mesh: MeshInstance3D, parent: Node3D, push: Vector3, impact: Vector3,
		cols: int, rows: int, slant := 0.0, merge_top := false) -> Array:
	var bodies := []
	var xf := leaf_mesh.global_transform
	# The boards' plane: the old gate's measured one, or (a thick Tripo leaf) the
	# middle of the leaf mesh itself.
	var plane := BOARD_PLANE if slant <= 0.0 else leaf_mesh.mesh.get_aabb().get_center().z
	for p in pieces_for(leaf_mesh.mesh, cols, rows, slant, merge_top):
		var body := RigidBody3D.new()
		body.collision_layer = DEBRIS_LAYER
		body.collision_mask = DEBRIS_MASK
		body.mass = 2.5
		var draw := MeshInstance3D.new()
		draw.name = "Draw"
		draw.mesh = p["mesh"]
		# The crumbling material from the start, so its shader compiles in the
		# impact's slow motion rather than as a hitch a second or two later.
		for s in (p["mesh"] as Mesh).get_surface_count():
			draw.set_surface_override_material(s, _dissolve_for((p["mesh"] as Mesh).surface_get_material(s)))
		draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		draw.visibility_range_end = 40.0
		body.add_child(draw)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var size: Vector3 = p["size"]
		# The box is the BOARD, not the chunk's bounds: those take in the iron
		# bands and the latch, up to 0.47 m deep, and a box that deep stood every
		# chunk up on end like a post. 8 cm, centred on the boards' plane --
		# thin, but not so thin it tunnels through the floor.
		box.size = Vector3(size.x, size.y, BOARD_THICK)
		shape.shape = box
		shape.position = Vector3(0.0, 0.0, plane - (p["centre"] as Vector3).z)
		body.add_child(shape)
		parent.add_child(body)
		body.global_transform = Transform3D(xf.basis, xf * (p["centre"] as Vector3))
		# Nearest the boot flies hardest; the far corners mostly drop.
		var near := clampf(1.4 - body.global_position.distance_to(impact) / 1.6, 0.6, 1.4)
		# Thrown hard down the corridor, away from the boot (2026-10-11: they
		# used to drop within a metre of the door).
		body.linear_velocity = push * randf_range(LAUNCH_MIN, LAUNCH_MAX) * near \
			+ Vector3.UP * randf_range(1.2, 3.4) \
			+ (body.global_position - impact).normalized() * randf_range(0.8, 2.4)
		body.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-5, 5), randf_range(-9, 9))
		bodies.append(body)
	return bodies


## The door's own look, in the crumbling shader: one per source material.
static func _dissolve_for(source: Material) -> Material:
	var key := source.get_instance_id() if source != null else 0
	if _dissolve_mats.has(key):
		return _dissolve_mats[key]
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.frequency = 0.035
		fn.fractal_octaves = 3
		_noise = NoiseTexture2D.new()
		_noise.width = 128
		_noise.height = 128
		_noise.seamless = true
		_noise.noise = fn
	var m := ShaderMaterial.new()
	m.shader = DISSOLVE
	m.set_shader_parameter("noise_tex", _noise)
	var std := source as StandardMaterial3D
	if std != null:
		m.set_shader_parameter("albedo_tex", std.albedo_texture)
		m.set_shader_parameter("albedo_color", std.albedo_color)
		m.set_shader_parameter("roughness", std.roughness)
		if std.normal_enabled and std.normal_texture != null:
			m.set_shader_parameter("has_normal", true)
			m.set_shader_parameter("normal_tex", std.normal_texture)
			m.set_shader_parameter("normal_strength", std.normal_scale)
	_dissolve_mats[key] = m
	return m


## Every piece waits a random 1-3 s, crumbles away with a little dust, and is
## gone. Game time: it runs at whatever speed the world does.
static func crumble(bodies: Array, effects: bool) -> void:
	for b in bodies:
		var body := b as RigidBody3D
		if not is_instance_valid(body):
			continue
		var draw := body.get_node_or_null("Draw") as GeometryInstance3D
		var t := body.create_tween()
		var wait := randf_range(CRUMBLE_MIN, CRUMBLE_MAX)
		body.set_meta("crumble_wait", wait)
		t.tween_interval(wait)
		if effects:
			t.tween_callback(func() -> void:
				dust(body.get_parent() as Node3D, body.global_position, Vector3.UP, 10, 0.6))
		if draw != null:
			t.tween_method(func(v: float) -> void:
				draw.set_instance_shader_parameter("dissolve", v), 0.0, 1.0, CRUMBLE_TIME)
		t.tween_callback(body.queue_free)


## A puff of dust: `amount` soft brown sprites thrown along `direction`.
static func dust(parent: Node3D, at: Vector3, direction: Vector3, amount := 28, size := 1.0) -> void:
	if parent == null:
		return
	var puff := CPUParticles3D.new()
	puff.one_shot = true
	puff.amount = amount
	puff.lifetime = 1.2
	puff.explosiveness = 0.95
	puff.direction = direction
	puff.spread = 70.0
	puff.initial_velocity_min = 0.6 * size
	puff.initial_velocity_max = 2.4 * size
	puff.gravity = Vector3(0, -0.6, 0)
	puff.damping_min = 1.5
	puff.damping_max = 2.5
	puff.scale_amount_min = 0.25 * size
	puff.scale_amount_max = 0.6 * size
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.55))
	g.set_color(1, Color(1, 1, 1, 0.0))
	soft.gradient = g
	mat.albedo_texture = soft
	quad.material = mat
	puff.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(0.35, 0.28, 0.2, 0.8))
	fade.set_color(1, Color(0.3, 0.25, 0.2, 0.0))
	puff.color_ramp = fade
	parent.add_child(puff)
	puff.global_position = at
	puff.emitting = true
	puff.get_tree().create_timer(2.0).timeout.connect(puff.queue_free)

## Compiles the crumbling and dust shaders before they are needed. Their first
## draw stalled the frame the door broke -- measured ~1 s the very first time
## and 101 ms once Godot's shader cache had them -- so a speck of each is drawn
## once, in front of the camera, while the level is still coming up.
static var warmed := false

static func warm_up(camera: Camera3D, sources: Array) -> void:
	if warmed or camera == null or not camera.is_inside_tree():
		return
	warmed = true
	var holder := Node3D.new()
	holder.name = "DebrisWarmUp"
	camera.add_child(holder)
	holder.position = Vector3(0.0, 0.0, -0.5)
	holder.scale = Vector3.ONE * 0.002
	for source in sources:
		var speck := MeshInstance3D.new()
		speck.mesh = QuadMesh.new()
		speck.material_override = _dissolve_for(source)
		speck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(speck)
		speck.set_instance_shader_parameter("dissolve", 0.5)
	dust(holder, holder.global_position, Vector3.UP, 1, 0.01)
	camera.get_tree().create_timer(0.5).timeout.connect(holder.queue_free)