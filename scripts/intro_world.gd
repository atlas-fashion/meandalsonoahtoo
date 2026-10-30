extends Node3D

## The intro's world (note 131): a heavily forested hill far out from the
## dungeon (ORIGIN), with the ruins of Vardia on its crown, a path winding up
## to them, a forest road below for the knight's memory, and a study, off on
## its own, for the years of research.
##
## What is STAND-IN (made in code, to be swapped for Higgsfield models): the
## terrain mesh, every plant (intro_flora.gd), the training posts. What is
## GENERATED and reused: the ruins are the brick kit's arch, walls, pillars and
## slabs (note 27) and the Tripo kit's columns, rocks and fallen blocks; the
## ground and rock textures are the old organic level's.
##
## Built by intro.gd. Everything in local space here; this node sits at ORIGIN.

const Flora := preload("res://scripts/intro_flora.gd")
const BrickLevel := preload("res://scripts/brick_level.gd")

const ORIGIN := Vector3(-2400.0, 0.0, 0.0)
## The terrain: SIZE square, a vertex every STEP, cut into CHUNKS x CHUNKS meshes.
const SIZE := 360.0
const STEP := 2.0
const CHUNKS := 6
## The hill: HILL_H high at the ruins (the origin), falling off over HILL_R.
const HILL_H := 30.0
const HILL_R := 95.0
## The crown kept open round the ruins, and the walkable ring the player is
## held inside (`_build_bounds`).
const CLEAR_R := 21.0
const BOUND_R := 50.0
## The path up (local xz), from the gate down the hill.
const PATH: Array[Vector2] = [Vector2(0, -24), Vector2(4, -34), Vector2(12, -46), Vector2(27, -60),
	Vector2(38, -80), Vector2(29, -104), Vector2(8, -122), Vector2(-15, -142), Vector2(-36, -160)]
const PATH_HALF := 2.2
## The forest road of the knight's memory, and the flat it lies on.
const ROAD: Array[Vector2] = [Vector2(20, 175), Vector2(55, 130), Vector2(95, 112), Vector2(150, 95)]
const KNIGHT_PAD := Vector2(64, 122)
const KNIGHT_PAD_R := 13.0
## The study, off the terrain (its own lights; the sun is off while it is seen).
const STUDY_AT := Vector3(0.0, 40.0, 620.0)

var noise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()

## Lights and environment.
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_dusk: Sky
var sky_night: Sky

## Points the director and the lessons use (local unless named world).
var marks := {}
## Nodes the lessons use.
var inscription: Node3D
var posts: Array[Node3D] = []
var altar: Node3D
var altar_glow: OmniLight3D
var log_body: Node3D
var study_candle: OmniLight3D
var fire_light: OmniLight3D


func build() -> void:
	name = "IntroWorld"
	position = ORIGIN
	rng.seed = 90213
	noise.seed = 4117
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 70.0
	noise.fractal_octaves = 4
	var t0 := Time.get_ticks_msec()
	_build_terrain()
	_build_ruins()
	_build_forest()
	_build_undergrowth()
	_build_knight_set()
	_build_study()
	_build_bounds()
	_build_lights()
	print("[intro] world built in %d ms" % (Time.get_ticks_msec() - t0))


# --- The ground ---------------------------------------------------------------

func _dist_to_line(p: Vector2, line: Array[Vector2]) -> float:
	var best := INF
	for i in line.size() - 1:
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## The raw hill, before the path and the flats are cut into it.
func _raw(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var hill := HILL_H * exp(-pow(r / HILL_R, 2.0))
	var rough := noise.get_noise_2d(x, z) * 9.0 * smoothstep(22.0, 70.0, r)
	var fine := noise.get_noise_2d(x * 3.1 + 100.0, z * 3.1) * 0.6
	# A rim, out past where anyone walks, so the land never ends in view.
	var rim := smoothstep(150.0, 182.0, r) * 26.0
	return hill + rough + fine + rim


## The ground's height at local (x, z): read off the grid once it is built (the
## mesh's own vertices, bilinear between them), worked out before that.
func height(x: float, z: float) -> float:
	if _grid.is_empty():
		return _height_exact(x, z)
	var gx := clampf((x + SIZE * 0.5) / STEP, 0.0, float(_n - 1) - 0.001)
	var gz := clampf((z + SIZE * 0.5) / STEP, 0.0, float(_n - 1) - 0.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - float(ix)
	var fz := gz - float(iz)
	var a := lerpf(_grid[iz * _n + ix], _grid[iz * _n + ix + 1], fx)
	var b := lerpf(_grid[(iz + 1) * _n + ix], _grid[(iz + 1) * _n + ix + 1], fx)
	return lerpf(a, b, fz)


var _grid := PackedFloat32Array()
var _n := 0


func _height_exact(x: float, z: float) -> float:
	var h := _raw(x, z)
	var p := Vector2(x, z)
	# The crown: flattened round the ruins.
	var r := p.length()
	var crown := _raw(0.0, 0.0) - 0.4
	h = lerpf(crown + noise.get_noise_2d(x * 5.0, z * 5.0) * 0.25, h, smoothstep(14.0, 30.0, r))
	# The path: its cross-section levelled to the height along its middle.
	var d := _dist_to_line(p, PATH)
	if d < PATH_HALF + 3.0:
		var on := _nearest_on(p, PATH)
		var mid := _raw(on.x, on.y)
		if on.length() < 30.0:
			mid = lerpf(crown, mid, smoothstep(14.0, 30.0, on.length()))
		h = lerpf(mid - 0.1, h, smoothstep(PATH_HALF - 0.4, PATH_HALF + 3.0, d))
	# The road below, and the flat where the knight lies.
	var dr := _dist_to_line(p, ROAD)
	var pad := p.distance_to(KNIGHT_PAD)
	if dr < 6.0 or pad < KNIGHT_PAD_R + 6.0:
		var flat := _raw(KNIGHT_PAD.x, KNIGHT_PAD.y)
		var k := minf(smoothstep(3.0, 6.0, dr), smoothstep(KNIGHT_PAD_R, KNIGHT_PAD_R + 6.0, pad))
		h = lerpf(flat, h, k)
	return h


func _nearest_on(p: Vector2, line: Array[Vector2]) -> Vector2:
	var best := INF
	var at := line[0]
	for i in line.size() - 1:
		var a: Vector2 = line[i]
		var b: Vector2 = line[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < best:
			best = d
			at = q
	return at


## A point on the ground (local), `up` above it.
func ground(x: float, z: float, up := 0.0) -> Vector3:
	return Vector3(x, height(x, z) + up, z)


func _grid_h(ix: int, iz: int) -> float:
	return _grid[clampi(iz, 0, _n - 1) * _n + clampi(ix, 0, _n - 1)]


func _build_terrain() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/intro_terrain.gdshader")
	mat.set_shader_parameter(&"ground_tex", load("res://textures/ground_albedo.png"))
	mat.set_shader_parameter(&"ground_nrm", load("res://textures/ground_normal.png"))
	mat.set_shader_parameter(&"rock_tex", load("res://textures/rock_albedo.png"))
	var nt := NoiseTexture2D.new()
	nt.seamless = true
	nt.width = 256
	nt.height = 256
	var fn := FastNoiseLite.new()
	fn.seed = 12
	fn.frequency = 0.02
	nt.noise = fn
	mat.set_shader_parameter(&"noise_tex", nt)
	var per := int(SIZE / STEP) / CHUNKS
	var half := SIZE * 0.5
	# The grid, once: heights, then normals and the path / clearing masks.
	_n = int(SIZE / STEP) + 1
	var grid := PackedFloat32Array()
	grid.resize(_n * _n)
	for iz in _n:
		for ix in _n:
			grid[iz * _n + ix] = _height_exact(-half + ix * STEP, -half + iz * STEP)
	_grid = grid
	var normals := PackedVector3Array()
	normals.resize(_n * _n)
	var colours := PackedColorArray()
	colours.resize(_n * _n)
	for iz in _n:
		for ix in _n:
			var dx := _grid_h(ix + 1, iz) - _grid_h(ix - 1, iz)
			var dz := _grid_h(ix, iz + 1) - _grid_h(ix, iz - 1)
			normals[iz * _n + ix] = Vector3(-dx, 2.0 * STEP, -dz).normalized()
			var q := Vector2(-half + ix * STEP, -half + iz * STEP)
			var path := 1.0 - smoothstep(PATH_HALF * 0.5, PATH_HALF + 0.8, minf(_dist_to_line(q, PATH), _dist_to_line(q, ROAD) + 0.6))
			var clear := 1.0 - smoothstep(CLEAR_R - 6.0, CLEAR_R + 4.0, q.length())
			clear = maxf(clear, 1.0 - smoothstep(KNIGHT_PAD_R - 4.0, KNIGHT_PAD_R + 2.0, q.distance_to(KNIGHT_PAD)))
			colours[iz * _n + ix] = Color(path, clear, 0.0)
	var faces := PackedVector3Array()
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1 | 2 | 256
	body.collision_mask = 0
	add_child(body)
	for cz in CHUNKS:
		for cx in CHUNKS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for iz in per:
				for ix in per:
					var gx := cx * per + ix
					var gz := cz * per + iz
					var quad := [Vector2i(gx, gz), Vector2i(gx + 1, gz), Vector2i(gx + 1, gz + 1), Vector2i(gx, gz + 1)]
					# Clockwise from above (Godot's front face, seen from up).
					for k: int in [0, 1, 2, 0, 2, 3]:
						var g: Vector2i = quad[k]
						var i := g.y * _n + g.x
						var q := Vector2(-half + g.x * STEP, -half + g.y * STEP)
						var p := Vector3(q.x, _grid[i], q.y)
						st.set_color(colours[i])
						st.set_normal(normals[i])
						st.set_uv(q / 4.0)
						st.add_vertex(p)
						faces.append(p)
			st.generate_tangents()
			var mi := MeshInstance3D.new()
			mi.name = "Ground_%d_%d" % [cx, cz]
			mi.mesh = st.commit()
			mi.material_override = mat
			add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	# The faces above are wound for the camera; collision wants them either way.
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


# --- The forest --------------------------------------------------------------------

## Kept clear of trees: the crown, the path, the road and the knight's flat.
func _clear_of_trees(p: Vector2, margin := 0.0) -> bool:
	if p.length() < CLEAR_R + margin:
		return false
	if _dist_to_line(p, PATH) < PATH_HALF + 2.5 + margin:
		return false
	if _dist_to_line(p, ROAD) < 4.5 + margin or p.distance_to(KNIGHT_PAD) < KNIGHT_PAD_R + margin:
		return false
	return absf(p.x) < SIZE * 0.5 - 4.0 and absf(p.y) < SIZE * 0.5 - 4.0


## Instances into a MultiMesh per (mesh, chunk), each node at its chunk's middle
## (a visibility range is measured from the node's origin).
func _scatter(mesh: Mesh, xforms: Array, view: float, tints: Array, shadows: bool) -> void:
	var by_chunk := {}
	for i in xforms.size():
		var xf: Transform3D = xforms[i]
		var key := Vector2i(floori(xf.origin.x / 40.0), floori(xf.origin.z / 40.0))
		if not by_chunk.has(key):
			by_chunk[key] = []
		(by_chunk[key] as Array).append(i)
	for key: Vector2i in by_chunk:
		var list: Array = by_chunk[key]
		var centre := Vector3((key.x + 0.5) * 40.0, 0.0, (key.y + 0.5) * 40.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for j in list.size():
			var xf: Transform3D = xforms[list[j]]
			mm.set_instance_transform(j, Transform3D(xf.basis, xf.origin - centre))
			mm.set_instance_custom_data(j, tints[list[j]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = centre
		mmi.visibility_range_end = view
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		add_child(mmi)


func _build_forest() -> void:
	var firs: Array = [[], [], []]
	var fir_tints: Array = [[], [], []]
	var broad: Array = [[], []]
	var broad_tints: Array = [[], []]
	var trunks: Array[Vector3] = []
	var spacing := 6.0
	var n := int(SIZE / spacing)
	var count := 0
	for iz in n:
		for ix in n:
			var p := Vector2(-SIZE * 0.5 + (ix + rng.randf_range(0.15, 0.85)) * spacing,
				-SIZE * 0.5 + (iz + rng.randf_range(0.15, 0.85)) * spacing)
			if not _clear_of_trees(p):
				continue
			# Thicker in places, a glade here and there.
			var dense := noise.get_noise_2d(p.x * 0.7 + 400.0, p.y * 0.7)
			if dense < -0.35 and rng.randf() < 0.7:
				continue
			var at := ground(p.x, p.y, -0.3)
			var lean := Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04))
			var s := rng.randf_range(0.75, 1.25)
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			b = Basis.from_euler(lean) * b
			var xf := Transform3D(b.scaled(Vector3.ONE * s), at)
			var g := rng.randf_range(0.85, 1.12)
			var tint := Color(g * rng.randf_range(0.92, 1.05), g, g * rng.randf_range(0.9, 1.0), 1.0)
			# Broadleaves at the forest's edge round the ruins and on the low ground.
			var broad_odds := 0.18 + 0.5 * (1.0 - smoothstep(CLEAR_R, CLEAR_R + 30.0, p.length())) \
				+ 0.25 * (1.0 - smoothstep(4.0, 22.0, at.y))
			if rng.randf() < broad_odds:
				var v := rng.randi_range(0, 1)
				broad[v].append(xf)
				broad_tints[v].append(tint)
			else:
				var v := rng.randi_range(0, 2)
				firs[v].append(xf)
				fir_tints[v].append(tint)
			trunks.append(at)
			count += 1
	for v in 3:
		_scatter(Flora.fir(v), firs[v], 190.0, fir_tints[v], true)
	for v in 2:
		_scatter(Flora.broadleaf(v), broad[v], 190.0, broad_tints[v], true)
	# Trunks the player can walk into, near where they can walk.
	var body := StaticBody3D.new()
	body.name = "Trunks"
	body.collision_layer = 1 | 2 | 256
	body.collision_mask = 0
	add_child(body)
	var near := 0
	for t in trunks:
		if Vector2(t.x, t.z).length() > BOUND_R + 8.0 and Vector2(t.x, t.z).distance_to(KNIGHT_PAD) > 30.0:
			continue
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4
		cyl.height = 6.0
		cs.shape = cyl
		cs.position = t + Vector3(0, 3.0, 0)
		body.add_child(cs)
		near += 1
	print("[intro] %d trees (%d with trunks to walk into)" % [count, near])


func _build_undergrowth() -> void:
	var ferns: Array = []
	var fern_t: Array = []
	var bushes: Array = []
	var bush_t: Array = []
	var grass: Array = []
	var grass_t: Array = []
	# Ferns and bushes in the forest round the crown and the road.
	for i in 2600:
		var p := Vector2(rng.randf_range(-130, 130), rng.randf_range(-170, 150))
		if not _clear_of_trees(p, -6.0):
			continue
		var at := ground(p.x, p.y, -0.05)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), at)
		var g := rng.randf_range(0.8, 1.1)
		if rng.randf() < 0.72:
			ferns.append(xf)
			fern_t.append(Color(g, g, g * 0.95, 1))
		else:
			bushes.append(xf)
			bush_t.append(Color(g * 0.95, g, g * 0.9, 1))
	# Grass over the crown (not on the paving) and along the edges of the path.
	for i in 2400:
		var p := Vector2(rng.randf_range(-34, 34), rng.randf_range(-48, 34))
		var r := p.length()
		if r > 34.0 or (r < 12.5 and rng.randf() < 0.75):
			continue
		if _dist_to_line(p, PATH) < PATH_HALF * 0.7:
			continue
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)),
			ground(p.x, p.y, -0.04))
		var g := rng.randf_range(0.8, 1.15)
		grass.append(xf)
		grass_t.append(Color(g, g, g * 0.85, 1))
	_scatter(Flora.fern_plant(), ferns, 70.0, fern_t, false)
	_scatter(Flora.bush(), bushes, 90.0, bush_t, false)
	_scatter(Flora.grass_tuft(), grass, 55.0, grass_t, false)
	# Boulders (the Tripo kit's rocks) in the forest and the clearing's edge.
	var rock: PackedScene = load("res://models/kit/rock_pillar.glb")
	for i in 70:
		var p := Vector2(rng.randf_range(-110, 110), rng.randf_range(-150, 130))
		if p.length() < CLEAR_R - 2.0 or _dist_to_line(p, PATH) < PATH_HALF + 1.0:
			continue
		var n: Node3D = rock.instantiate()
		var s := rng.randf_range(0.8, 2.6)
		n.scale = Vector3(s * rng.randf_range(0.9, 1.6), s * rng.randf_range(0.5, 0.9), s * rng.randf_range(0.9, 1.6))
		n.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		n.position = ground(p.x, p.y, -0.35 * s)
		add_child(n)
	print("[intro] %d ferns, %d bushes, %d grass tufts" % [ferns.size(), bushes.size(), grass.size()])


# --- Vardia ------------------------------------------------------------------------

func _brick(piece: String, xf: Transform3D, solid := true) -> MeshInstance3D:
	var mesh := BrickLevel.standalone(piece)
	if mesh == null:
		push_warning("intro: no brick piece " + piece)
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	add_child(mi)
	if solid:
		_solid_box(mi, mesh.get_aabb())
	return mi


func _glb(path: String, xf: Transform3D, solid := true) -> Node3D:
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.transform = xf
	add_child(n)
	if solid:
		var box := AABB()
		var first := true
		for c in n.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			var a: AABB = (n.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			box = a if first else box.merge(a)
			first = false
		_solid_box(n, box)
	return n


## A box of collision round `aabb` (in `node`'s space), on the world layers.
func _solid_box(node: Node3D, aabb: AABB) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 2 | 256
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	cs.shape = box
	cs.position = aabb.get_center()
	body.add_child(cs)
	node.add_child(body)


func _xf(at: Vector3, yaw: float, tilt := Vector3.ZERO, s := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(tilt) * Basis(Vector3.UP, yaw) * Basis.from_scale(s), at)


func _build_ruins() -> void:
	var top := height(0.0, 0.0)
	marks["crown"] = Vector3(0, top, 0)
	# The gate: the brick kit's arch, the path running through it along Z.
	var gate := ground(0, -24, -0.15)
	_brick("arch", _xf(gate, 0.0, Vector3(0.0, 0.0, 0.02)))
	marks["gate"] = gate + Vector3(0, 0, 2.5)
	# Walls run off either side of the gate, broken down here and there.
	for s: float in [-1.0, 1.0]:
		for k in 3:
			var x := s * (6.4 + 5.0 * k)
			var z := -24.0 + 3.0 * k
			var at := ground(x, z, -0.25 - 0.4 * k)
			var yaw := s * 0.32 * k
			if k == 2:
				_brick("wall_top", _xf(at, yaw, Vector3(0.05 * s, 0, 0.08)))
			else:
				_brick("wall", _xf(at, yaw, Vector3(0.02 * s, 0, 0.03 * k)))
	# Paving, half gone: the kit's slabs, sunk, cracked loose, some tipped.
	for iz in range(-5, 6):
		for ix in range(-5, 6):
			var p := Vector2(ix * 3.1, iz * 3.1)
			if p.length() > 15.5 or rng.randf() < 0.22:
				continue
			var tilt := Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05))
			if rng.randf() < 0.12:
				tilt *= 4.0
			_brick("floor", _xf(ground(p.x, p.y, 0.32 + rng.randf_range(-0.06, 0.04)), float(rng.randi_range(0, 3)) * PI * 0.5, tilt), false)
	# The paving's collision: one flat box under the whole of it.
	var pave := StaticBody3D.new()
	pave.collision_layer = 1 | 2 | 256
	var pcs := CollisionShape3D.new()
	var pcyl := CylinderShape3D.new()
	pcyl.radius = 15.0
	pcyl.height = 1.0
	pcs.shape = pcyl
	pcs.position = Vector3(0, top + 0.25 - 0.5, 0)
	pave.add_child(pcs)
	add_child(pave)
	# A ring of columns (Tripo), some whole, some snapped, one fallen.
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		var p := Vector2(cos(a), sin(a)) * 12.5
		if i == 5:
			# Fallen, across the way to the posts.
			_glb("res://models/kit/v2_pillar_ready.glb", _xf(ground(p.x, p.y, 0.7), a + PI * 0.5, Vector3(0, 0, PI * 0.5), Vector3(0.62, 0.8, 0.62)))
			continue
		var tall: float = [1.0, 0.45, 0.8, 0.3, 1.0, 1.0, 0.55, 0.38][i]
		_glb("res://models/kit/v2_pillar_ready.glb", _xf(ground(p.x, p.y, -0.2), rng.randf() * TAU,
			Vector3(rng.randf_range(-0.04, 0.04), 0, rng.randf_range(-0.04, 0.04)), Vector3(0.62, 0.62 * tall, 0.62)))
	# Fallen blocks about the place.
	for i in 9:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * rng.randf_range(6.0, 18.0)
		# Not in the way in (gate to trunk to paving), by the posts, the
		# sentinel or the standing stone.
		if _dist_to_line(p, PATH) < 3.0 or (absf(p.x) < 6.0 and p.y < -6.0) \
				or p.distance_to(Vector2(-9.6, 4.2)) < 5.0 or p.distance_to(Vector2(9.0, 4.0)) < 4.5 \
				or p.distance_to(Vector2(-7.0, -8.0)) < 3.5:
			continue
		var s := rng.randf_range(0.45, 0.8)
		_glb("res://models/kit/ceiling_slab_ready.glb", _xf(ground(p.x, p.y, 0.4 * s), rng.randf() * TAU,
			Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)), Vector3.ONE * s))
	# The altar: the kit's slab on a step, four stumps of pillar round it.
	var dais := ground(0, 3.5, 0.15)
	_brick("floor", _xf(dais, 0.0, Vector3.ZERO, Vector3(1.3, 1.0, 1.3)))
	altar = _brick("morgue_slab", _xf(dais + Vector3(0, 0.08, 0), PI * 0.5))
	marks["altar"] = dais + Vector3(0, 0.95, 0)
	for c: Vector2 in [Vector2(-2.6, 1.6), Vector2(2.6, 1.6), Vector2(-2.6, 5.4), Vector2(2.6, 5.4)]:
		_brick("pillar", _xf(ground(c.x, c.y, 0.2), rng.randf() * TAU, Vector3.ZERO, Vector3(0.8, rng.randf_range(0.35, 0.7), 0.8)))
	altar_glow = OmniLight3D.new()
	altar_glow.light_color = Color(0.35, 0.85, 1.0)
	altar_glow.light_energy = 0.0
	altar_glow.omni_range = 7.0
	altar_glow.position = marks["altar"] + Vector3(0, 0.4, 0)
	add_child(altar_glow)
	# The fallen trunk across the way in (the jump), between two broken walls.
	var lz := -15.0
	log_body = Node3D.new()
	log_body.name = "FallenTrunk"
	log_body.position = ground(0.8, lz, 0.38)
	log_body.rotation = Vector3(0, 0.08, 0)
	add_child(log_body)
	var lm := MeshInstance3D.new()
	lm.mesh = Flora.log_mesh()
	lm.scale = Vector3(1.1, 1.0, 1.0)
	log_body.add_child(lm)
	var lb := StaticBody3D.new()
	lb.collision_layer = 1 | 2 | 256
	var lcs := CollisionShape3D.new()
	var lbox := BoxShape3D.new()
	lbox.size = Vector3(7.0, 0.76, 0.8)
	lcs.shape = lbox
	lb.add_child(lcs)
	log_body.add_child(lb)
	for s: float in [-1.0, 1.0]:
		_brick("wall_top", _xf(ground(s * 5.6, lz, -0.3), PI * 0.5 * s, Vector3.ZERO, Vector3(0.9, 1.0, 1.0)))
	marks["log_z"] = lz
	# The inscription: a fallen block stood on end, words cut in it.
	var ins := ground(-7.0, -8.0, 0.9)
	inscription = Node3D.new()
	inscription.name = "Inscription"
	inscription.position = ins
	inscription.rotation.y = 0.55
	add_child(inscription)
	var slab := _glb("res://models/kit/ceiling_slab_ready.glb", Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(0.7, 0.7, 0.7)), Vector3(0, 0.45, 0)), false)
	slab.reparent(inscription, false)
	_solid_box(inscription, AABB(Vector3(-1.05, -0.9, -0.35), Vector3(2.1, 2.2, 0.7)))
	var runes := Label3D.new()
	runes.text = "ᚡᚨᚱᛞᛁᚨ\n·  ᛟ ᚹᛖᚱᛟ ᛁᛚᛖ  ·"
	runes.font_size = 64
	runes.pixel_size = 0.004
	runes.modulate = Color(0.55, 0.85, 1.0, 0.85)
	runes.outline_size = 0
	runes.position = Vector3(0, 0.55, 0.36)
	runes.shaded = false
	inscription.add_child(runes)
	# Training posts by the west wall.
	for i in 3:
		var at := ground(-10.0 + i * 0.4, 1.0 + i * 3.2)
		posts.append(_post(at))
	marks["posts"] = ground(-7.0, 4.2)
	# The sentinel's plinth, east.
	marks["sentinel"] = ground(9.0, 4.0, 0.0)
	_brick("floor", _xf(ground(9.0, 4.0, 0.1), 0.0, Vector3.ZERO, Vector3(0.8, 0.8, 0.8)), false)
	# The walk up (the last of the journey) and where control is handed over,
	# on the path below the gate, inside the ring.
	marks["walk_from"] = ground(PATH[4].x, PATH[4].y, 0.3)
	marks["walk_mid"] = ground(PATH[3].x, PATH[3].y, 0.3)
	marks["arrive"] = ground(PATH[2].x * 0.6 + PATH[1].x * 0.4, PATH[2].y * 0.6 + PATH[1].y * 0.4, 0.3)
	marks["vista"] = ground(PATH[5].x, PATH[5].y, 4.2)


## A training post: a trunk sunk in the ground with a crossbar, wrapped in
## rope. STAND-IN (bark cylinders). Hit by every weapon (damageable layer).
func _post(at: Vector3) -> Node3D:
	var post := StaticBody3D.new()
	post.name = "Post"
	post.set_script(load("res://scripts/intro_post.gd"))
	post.position = at
	post.rotation.y = rng.randf() * TAU
	add_child(post)
	return post


# --- The knight's road, and the study ------------------------------------------------

func _build_knight_set() -> void:
	var c := ground(KNIGHT_PAD.x, KNIGHT_PAD.y)
	marks["knight_pad"] = c
	# The tree he sits against: a broadleaf, its trunk where the scene wants it.
	var tree_at := c + Vector3(-3.0, -0.3, 2.0)
	tree_at.y = height(tree_at.x, tree_at.z) - 0.3
	var t := MeshInstance3D.new()
	t.mesh = Flora.broadleaf(1)
	t.position = tree_at
	t.rotation.y = 1.1
	add_child(t)
	marks["knight_tree"] = tree_at
	# His cart on its side in the road, a wheel off.
	var road_at := ground(58, 128, 0.0)
	_brick("cart_body", _xf(road_at + Vector3(0, 0.45, 0), 0.9, Vector3(0, 0, 1.35)), false)
	_brick("cart_wheels", _xf(road_at + Vector3(2.2, 0.3, -1.4), 0.3, Vector3(1.4, 0, 0.2)), false)
	# A fire still burning in the wreck.
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.55, 0.22)
	fire_light.light_energy = 0.0
	fire_light.omni_range = 16.0
	fire_light.shadow_enabled = true
	fire_light.position = road_at + Vector3(0.5, 1.2, 0.6)
	add_child(fire_light)
	marks["fire"] = fire_light.position
	var fire := GPUParticles3D.new()
	fire.name = "Fire"
	fire.amount = 40
	fire.lifetime = 0.9
	fire.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 18.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, 0.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	ramp.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	fire.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.6)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fm.vertex_color_use_as_albedo = true
	fm.albedo_texture = _soft_dot()
	quad.material = fm
	fire.draw_pass_1 = quad
	fire.position = road_at + Vector3(0.5, 0.6, 0.6)
	add_child(fire)
	marks["fire_node"] = fire


static var _dot: ImageTexture = null


static func _soft_dot() -> ImageTexture:
	if _dot != null:
		return _dot
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			# Faded in the colour too: an additive blend draws the colour whole.
			a *= a
			img.set_pixel(x, y, Color(a, a, a, a))
	_dot = ImageTexture.create_from_image(img)
	return _dot


## The study: a stone room (the brick kit's walls) with a plank floor, a desk
## under a candle, books, maps and the handle. STAND-IN furniture (boxes).
func _build_study() -> void:
	var s := Node3D.new()
	s.name = "Study"
	s.position = STUDY_AT
	add_child(s)
	var planks: Texture2D = load("res://textures/surgery_planks.png")
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = planks
	wood.albedo_color = Color(0.55, 0.42, 0.3)
	wood.uv1_scale = Vector3(2, 2, 2)
	wood.roughness = 0.85
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(7, 6)
	floor_mi.mesh = fp
	floor_mi.material_override = wood
	s.add_child(floor_mi)
	var ceil_mi := MeshInstance3D.new()
	var cp := PlaneMesh.new()
	cp.size = Vector2(7, 6)
	cp.flip_faces = true
	ceil_mi.mesh = cp
	ceil_mi.material_override = wood
	ceil_mi.position.y = 3.4
	s.add_child(ceil_mi)
	# Walls: the kit's wall pieces on all four sides, facing in.
	for w: Array in [[Vector3(0, 0, -3.2), 0.0], [Vector3(0, 0, 3.2), PI], [Vector3(-3.6, 0, 0), PI * 0.5], [Vector3(3.6, 0, 0), -PI * 0.5]]:
		var mi := MeshInstance3D.new()
		mi.mesh = BrickLevel.standalone("wall")
		mi.position = w[0]
		mi.rotation.y = w[1]
		mi.scale = Vector3(1.4, 1.0, 1.0)
		s.add_child(mi)
	# The desk.
	var desk_wood := StandardMaterial3D.new()
	desk_wood.albedo_texture = load("res://textures/wood_door_albedo.png")
	desk_wood.albedo_color = Color(0.5, 0.36, 0.24)
	desk_wood.roughness = 0.7
	var desk_at := Vector3(0.0, 0.0, -1.9)
	_box(s, Vector3(2.0, 0.08, 1.0), desk_at + Vector3(0, 0.8, 0), desk_wood)
	for c: Vector2 in [Vector2(-0.92, -0.42), Vector2(0.92, -0.42), Vector2(-0.92, 0.42), Vector2(0.92, 0.42)]:
		_box(s, Vector3(0.08, 0.8, 0.08), desk_at + Vector3(c.x, 0.4, c.y), desk_wood)
	# Books: stacks on the desk and the floor, in old bindings.
	var bind := [Color(0.35, 0.08, 0.06), Color(0.1, 0.16, 0.24), Color(0.22, 0.17, 0.08), Color(0.12, 0.2, 0.1), Color(0.3, 0.22, 0.12)]
	for stack: Array in [[desk_at + Vector3(-0.7, 0.84, -0.2), 5], [desk_at + Vector3(0.75, 0.84, -0.25), 3],
			[Vector3(-2.6, 0.0, -2.4), 9], [Vector3(-2.2, 0.0, -2.6), 6], [Vector3(2.5, 0.0, -2.5), 11], [Vector3(2.8, 0.0, 1.8), 7]]:
		var at: Vector3 = stack[0]
		for k in int(stack[1]):
			var size := Vector3(rng.randf_range(0.24, 0.34), rng.randf_range(0.04, 0.08), rng.randf_range(0.32, 0.44))
			var m := StandardMaterial3D.new()
			m.albedo_color = bind[rng.randi() % bind.size()] * rng.randf_range(0.8, 1.2)
			m.roughness = 0.75
			var mi := _box(s, size, at + Vector3(rng.randf_range(-0.03, 0.03), size.y * 0.5, rng.randf_range(-0.03, 0.03)), m)
			mi.rotation.y = rng.randf_range(-0.3, 0.3)
			at.y += size.y
	# Papers and the map, with the word and the numbers.
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.72, 0.64, 0.48)
	paper.roughness = 0.9
	for k in 6:
		var mi := _box(s, Vector3(0.21, 0.002, 0.29), desk_at + Vector3(rng.randf_range(-0.6, 0.6), 0.842 + k * 0.001, rng.randf_range(-0.35, 0.35)), paper)
		mi.rotation.y = rng.randf_range(-0.8, 0.8)
	var map_mi := _box(s, Vector3(0.62, 0.002, 0.44), desk_at + Vector3(0.1, 0.848, 0.12), paper)
	map_mi.rotation.y = 0.12
	var writing := Label3D.new()
	writing.text = "VARDIA ?\n\n47° 12' N   —   18° 40' E"
	writing.font_size = 40
	writing.pixel_size = 0.0018
	writing.modulate = Color(0.15, 0.09, 0.05)
	writing.outline_size = 0
	writing.shaded = true
	writing.rotation = Vector3(-PI * 0.5, 0.12, 0)
	writing.position = desk_at + Vector3(0.1, 0.851, 0.12)
	s.add_child(writing)
	marks["study_map"] = s.position + desk_at + Vector3(0.1, 0.85, 0.12)
	marks["study_desk"] = s.position + desk_at + Vector3(0, 0.85, 0)
	marks["study"] = s.position
	# The candle.
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.85, 0.8, 0.66)
	_box(s, Vector3(0.05, 0.16, 0.05), desk_at + Vector3(-0.45, 0.92, 0.25), wax)
	var flame := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.035, 0.07)
	var flm := StandardMaterial3D.new()
	flm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	flm.albedo_texture = _soft_dot()
	flm.albedo_color = Color(1.0, 0.75, 0.35)
	fq.material = flm
	flame.mesh = fq
	flame.position = desk_at + Vector3(-0.45, 1.03, 0.25)
	s.add_child(flame)
	study_candle = OmniLight3D.new()
	study_candle.light_color = Color(1.0, 0.68, 0.35)
	study_candle.light_energy = 0.0
	study_candle.omni_range = 6.0
	study_candle.shadow_enabled = true
	study_candle.position = desk_at + Vector3(-0.45, 1.1, 0.25)
	s.add_child(study_candle)


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


# --- Bounds ------------------------------------------------------------------------

## A ring of invisible wall at BOUND_R round the ruins: the search is up here.
func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "Bounds"
	body.collision_layer = 1 | 256
	body.collision_mask = 0
	add_child(body)
	var n := 40
	var top := height(0, 0)
	for i in n:
		var a := TAU * (float(i) + 0.5) / float(n)
		var at := Vector3(cos(a) * BOUND_R, top, sin(a) * BOUND_R)
		# A gap where the path comes in (the walk up passes it); `close_path`
		# shuts it behind them.
		if _dist_to_line(Vector2(at.x, at.z), PATH) < 5.0:
			continue
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(TAU * BOUND_R / float(n) + 0.6, 40.0, 1.0)
		cs.shape = box
		cs.position = at
		cs.rotation.y = -a + PI * 0.5
		body.add_child(cs)
	_path_gate = CollisionShape3D.new()
	var gate := BoxShape3D.new()
	gate.size = Vector3(14.0, 40.0, 1.0)
	_path_gate.shape = gate
	var cross := _nearest_on(_on_ring(), PATH)
	_path_gate.position = Vector3(cross.x, top, cross.y)
	_path_gate.rotation.y = -atan2(cross.y, cross.x) + PI * 0.5
	_path_gate.disabled = true
	body.add_child(_path_gate)


var _path_gate: CollisionShape3D


## Where the path crosses the ring (near enough).
func _on_ring() -> Vector2:
	var best := PATH[0]
	var off := INF
	for i in 200:
		var t := float(i) / 199.0 * float(PATH.size() - 1)
		var k := mini(int(t), PATH.size() - 2)
		var q: Vector2 = PATH[k].lerp(PATH[k + 1], t - float(k))
		var d := absf(q.length() - BOUND_R)
		if d < off:
			off = d
			best = q
	return best


## Shuts the way back down the path (once they have arrived).
func close_path() -> void:
	if _path_gate != null:
		_path_gate.disabled = false


# --- Light ---------------------------------------------------------------------------

func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.8, 0.58)
	sun.light_energy = 0.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.light_volumetric_fog_energy = 1.6
	# Low in the west-south-west, through the trees onto the ruins.
	sun.rotation = Vector3(deg_to_rad(-17.0), deg_to_rad(-118.0), 0.0)
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "IntroMoon"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	moon.light_volumetric_fog_energy = 0.6
	moon.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(40.0), 0.0)
	add_child(moon)
	var dusk := ProceduralSkyMaterial.new()
	dusk.sky_top_color = Color(0.24, 0.36, 0.56)
	dusk.sky_horizon_color = Color(0.86, 0.62, 0.42)
	dusk.ground_horizon_color = Color(0.4, 0.32, 0.25)
	dusk.ground_bottom_color = Color(0.1, 0.09, 0.08)
	dusk.sun_angle_max = 18.0
	dusk.sun_curve = 0.08
	sky_dusk = Sky.new()
	sky_dusk.sky_material = dusk
	var night := ProceduralSkyMaterial.new()
	night.sky_top_color = Color(0.015, 0.02, 0.045)
	night.sky_horizon_color = Color(0.05, 0.06, 0.1)
	night.ground_horizon_color = Color(0.03, 0.03, 0.04)
	night.ground_bottom_color = Color(0.01, 0.01, 0.015)
	night.sun_angle_max = 2.0
	sky_night = Sky.new()
	sky_night.sky_material = night


## The environment's look for a part of the intro, as properties to set.
func profile(which: StringName) -> Dictionary:
	match which:
		&"night":
			return {"sky": sky_night, "background_energy_multiplier": 1.0,
				"ambient_light_source": Environment.AMBIENT_SOURCE_COLOR,
				"ambient_light_color": Color(0.16, 0.2, 0.32), "ambient_light_energy": 1.0,
				"fog_mode": Environment.FOG_MODE_EXPONENTIAL, "fog_light_color": Color(0.03, 0.04, 0.07),
				"fog_light_energy": 1.0, "fog_density": 0.03, "fog_sun_scatter": 0.0, "fog_sky_affect": 0.6,
				"volumetric_fog_density": 0.03, "volumetric_fog_albedo": Color(0.7, 0.75, 0.85),
				"volumetric_fog_anisotropy": 0.4, "volumetric_fog_length": 50.0,
				"volumetric_fog_ambient_inject": 0.1, "volumetric_fog_sky_affect": 0.0,
				"tonemap_exposure": 1.1}
		&"study":
			return {"sky": sky_night, "background_energy_multiplier": 0.0,
				"ambient_light_source": Environment.AMBIENT_SOURCE_COLOR,
				"ambient_light_color": Color(0.1, 0.07, 0.05), "ambient_light_energy": 0.35,
				"fog_mode": Environment.FOG_MODE_EXPONENTIAL, "fog_light_color": Color(0.02, 0.015, 0.01),
				"fog_light_energy": 1.0, "fog_density": 0.01, "fog_sun_scatter": 0.0, "fog_sky_affect": 0.0,
				"volumetric_fog_density": 0.02, "volumetric_fog_albedo": Color(0.9, 0.85, 0.75),
				"volumetric_fog_anisotropy": 0.5, "volumetric_fog_length": 12.0,
				"volumetric_fog_ambient_inject": 0.0, "volumetric_fog_sky_affect": 0.0,
				"tonemap_exposure": 1.0}
	# Dusk on the hill.
	return {"sky": sky_dusk, "background_energy_multiplier": 1.0,
		"ambient_light_source": Environment.AMBIENT_SOURCE_SKY,
		"ambient_light_color": Color(0.5, 0.5, 0.5), "ambient_light_energy": 0.95,
		"fog_mode": Environment.FOG_MODE_EXPONENTIAL, "fog_light_color": Color(0.62, 0.55, 0.47),
		"fog_light_energy": 1.0, "fog_density": 0.0045, "fog_sun_scatter": 0.35, "fog_sky_affect": 0.25,
		"volumetric_fog_density": 0.006, "volumetric_fog_albedo": Color(1.0, 0.95, 0.88),
		"volumetric_fog_anisotropy": 0.65, "volumetric_fog_length": 70.0,
		"volumetric_fog_ambient_inject": 0.12, "volumetric_fog_sky_affect": 0.2,
		"tonemap_exposure": 1.0}


## The lights for a part of the intro.
func set_lights(which: StringName) -> void:
	sun.light_energy = 3.0 if which == &"dusk" else 0.0
	sun.visible = which == &"dusk"
	moon.light_energy = 0.8 if which == &"night" else 0.0
	moon.visible = which == &"night"
	fire_light.light_energy = 3.6 if which == &"night" else 0.0
	(marks["fire_node"] as GPUParticles3D).emitting = which == &"night"
	study_candle.light_energy = 1.4 if which == &"study" else 0.0


## World position of a local mark.
func at(mark: StringName) -> Vector3:
	return to_global(marks[mark])
