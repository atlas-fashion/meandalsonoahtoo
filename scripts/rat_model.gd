extends RefCounted

## The rat's look (2026-10-18), built from primitives in code (no Tripo): a
## furry body and haunch, a pointed head with pink ears, nose and feet, black
## bead eyes, and a long tail on its own pivot so it can swing. The ROBOT rat
## (the workbench's, rat_control.gd) is the same rat in iron with darker trim,
## a ridge plate down its back, an antenna, and its eyes and back crystal in
## the enforcer's own crystal colour (`enforcer_eye_colour`, read off the
## enforcer model, so the two always match).
##
## Every part of a variant is merged into ONE shared ArrayMesh, built once and
## used by every rat: one vertex-coloured surface, plus the glow on the robot
## (`COLOURS`, `_surface_of`). With the tail, two draw calls a wild rat, three
## a robot one. Faces -Z, origin on the floor under its middle; about 0.3 m
## nose to rump, the tail as long again.
##
##   build(robot) -> Node3D with "Body" (MeshInstance3D) and "Tail" (a pivot
##                   at the rump; swing its rotation.y, droop its rotation.x).

const SCALE := 1.25
## Used if the enforcer model cannot be read.
const CYAN_FALLBACK := Color(0.0, 0.91, 1.0)
const ENFORCER_MODEL := "res://models/enforcer.glb"
## The eyes are a few millimetres across: brighter than the enforcer's rings
## (2.0 x 0.35) or they do not read at all at a rat's size.
const EYE_ENERGY := 2.4
## The tail's pivot, in the unscaled model.
const TAIL_AT := Vector3(0.0, 0.062, 0.125)

static var _bodies := {}
static var _tails := {}
static var _mats := {}
static var _eye_colour = null


static func build(robot: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "RatModel"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _body_mesh(robot)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var pivot := Node3D.new()
	pivot.name = "Tail"
	pivot.position = TAIL_AT * SCALE
	root.add_child(pivot)
	var tail := MeshInstance3D.new()
	tail.name = "TailMesh"
	tail.mesh = _tail_mesh(robot)
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(tail)
	return root


## Every drawn part of a model from `build`, for a visibility range.
static func parts(model: Node3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		out.append(g as GeometryInstance3D)
	return out


## The enforcer's crystal colour -- its eyes' and its beam's (enforcer.gd sets
## CRYSTAL from the same material) -- read once from the model's scene state,
## without instancing it.
static func enforcer_eye_colour() -> Color:
	if _eye_colour != null:
		return _eye_colour
	_eye_colour = CYAN_FALLBACK
	var scene := load(ENFORCER_MODEL) as PackedScene
	if scene != null:
		var state := scene.get_state()
		for n in state.get_node_count():
			for k in state.get_node_property_count(n):
				var found = _crystal_emission(state.get_node_property_value(n, k))
				if found != null:
					_eye_colour = found
					return _eye_colour
	return _eye_colour


static func _crystal_emission(v: Variant) -> Variant:
	if v is StandardMaterial3D:
		var m := v as StandardMaterial3D
		if m.resource_name.contains("Crystal"):
			return m.emission
	elif v is Mesh:
		var mesh := v as Mesh
		for i in mesh.get_surface_count():
			var found = _crystal_emission(mesh.surface_get_material(i))
			if found != null:
				return found
	return null


# --- Materials -----------------------------------------------------------------------

## The colour of each part. Every part but the glowing ones goes into ONE
## vertex-coloured surface per rat (`_surface_of`): measured, a material per
## part (fur, skin, eye; body, trim) was ~80 more draw calls at the
## benchmark's spawn corridor, the depth prepass and the colour pass each
## drawing every surface of the ~10 rats in range.
const COLOURS := {
	# Lighter than a real rat: darker read as a hole in the floor by torchlight.
	&"fur": Color(0.32, 0.25, 0.2),
	&"skin": Color(0.6, 0.4, 0.38),
	&"eye": Color(0.01, 0.01, 0.01),
	&"metal": Color(0.46, 0.47, 0.5),
	&"trim": Color(0.12, 0.12, 0.13),
	&"glow": Color.WHITE,
}


## Which surface (and material) a part goes into: the wild rat's flesh, the
## robot's iron, or the glow.
static func _surface_of(key: StringName) -> StringName:
	match key:
		&"glow":
			return &"glow"
		&"metal", &"trim":
			return &"iron"
	return &"flesh"


static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"flesh":
			m.vertex_color_use_as_albedo = true
			# COLOURS are sRGB, as every colour here is (linear, they came out pale).
			m.vertex_color_is_srgb = true
			m.roughness = 0.9
		&"iron":
			m.vertex_color_use_as_albedo = true
			# COLOURS are sRGB, as every colour here is (linear, they came out pale).
			m.vertex_color_is_srgb = true
			m.metallic = 0.75
			m.roughness = 0.42
		&"glow":
			var c := enforcer_eye_colour()
			m.albedo_color = c
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = EYE_ENERGY
			m.roughness = 0.2
	m.resource_name = "Rat_%s" % key
	_mats[key] = m
	return m


# --- Meshes --------------------------------------------------------------------------

static func _sphere() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _cone(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 8
	c.rings = 1
	return c


static func _body_mesh(robot: bool) -> ArrayMesh:
	if _bodies.has(robot):
		return _bodies[robot]
	var tools := {}
	var coat := &"metal" if robot else &"fur"
	var pink := &"trim" if robot else &"skin"
	var eye := &"glow" if robot else &"eye"
	var ball := _sphere()
	# Body, haunch, head, and the snout tipped a little down.
	_add(tools, coat, ball, _xf(Vector3(0.07, 0.06, 0.12), Vector3(0.0, 0.072, 0.02)))
	_add(tools, coat, ball, _xf(Vector3(0.075, 0.066, 0.075), Vector3(0.0, 0.07, 0.075)))
	_add(tools, coat, ball, _xf(Vector3(0.048, 0.044, 0.065), Vector3(0.0, 0.078, -0.105)))
	_add(tools, coat, _cone(0.008, 0.034, 0.07),
		Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 - 0.15), Vector3(0.0, 0.07, -0.16)))
	_add(tools, pink, ball, _xf(Vector3.ONE * 0.011, Vector3(0.0, 0.064, -0.196)))
	for side: float in [-1.0, 1.0]:
		_add(tools, pink, ball, Transform3D(Basis(Vector3.UP, side * 0.4).scaled(Vector3(0.024, 0.028, 0.007)),
			Vector3(side * 0.03, 0.113, -0.09)))
		_add(tools, eye, ball, _xf(Vector3.ONE * 0.0095, Vector3(side * 0.027, 0.088, -0.128)))
		_add(tools, pink, ball, _xf(Vector3(0.016, 0.008, 0.024), Vector3(side * 0.038, 0.008, -0.07)))
		_add(tools, pink, ball, _xf(Vector3(0.016, 0.008, 0.024), Vector3(side * 0.045, 0.008, 0.08)))
	if robot:
		# A ridge plate down the back, the crystal set into it, the antenna.
		var plate := BoxMesh.new()
		plate.size = Vector3(0.03, 0.012, 0.15)
		_add(tools, &"trim", plate, Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(0.0, 0.128, 0.03)))
		_add(tools, &"glow", ball, _xf(Vector3(0.016, 0.012, 0.022), Vector3(0.0, 0.136, 0.05)))
		_add(tools, &"trim", _cone(0.002, 0.003, 0.06),
			Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0.0, 0.142, -0.07)))
		_add(tools, &"glow", ball, _xf(Vector3.ONE * 0.006, Vector3(0.0, 0.17, -0.06)))
	var mesh := _commit(tools)
	_bodies[robot] = mesh
	return mesh


## The tail: a long taper back from its pivot (along +Z), a little thicker on
## the robot, which is in segments of iron.
static func _tail_mesh(robot: bool) -> ArrayMesh:
	if _tails.has(robot):
		return _tails[robot]
	var tools := {}
	var key := &"trim" if robot else &"skin"
	var length := 0.24
	if robot:
		for k in 4:
			var t := float(k) / 4.0
			var r0 := lerpf(0.012, 0.004, t)
			var r1 := lerpf(0.012, 0.004, t + 0.22)
			_add(tools, key, _cone(r1, r0, length * 0.22),
				Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, length * (t + 0.11))))
	else:
		_add(tools, key, _cone(0.003, 0.011, length),
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, length * 0.5)))
	var mesh := _commit(tools)
	_tails[robot] = mesh
	return mesh


static func _xf(size: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis().scaled(size), at)


## Appends `mesh` (every surface), placed by `xf` in the unscaled model, to the
## arrays for material `key`. By hand rather than SurfaceTool.append_from:
## that carried the normals through the squash of each sphere unchanged, and
## the body shaded in bands like a grub. Here they go through the inverse
## transpose, as a squashed surface's normals must.
static func _add(tools: Dictionary, part: StringName, mesh: Mesh, xf: Transform3D) -> void:
	var key := _surface_of(part)
	var colour: Color = COLOURS[part]
	if not tools.has(key):
		tools[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
			"i": PackedInt32Array()}
	# Packed arrays are values: appended to here and stored back.
	var out_v: PackedVector3Array = tools[key]["v"]
	var out_n: PackedVector3Array = tools[key]["n"]
	var out_c: PackedColorArray = tools[key]["c"]
	var out_i: PackedInt32Array = tools[key]["i"]
	var scaled := Transform3D(Basis().scaled(Vector3.ONE * SCALE), Vector3.ZERO) * xf
	var normal_basis := scaled.basis.inverse().transposed()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := out_v.size()
		for k in verts.size():
			out_v.append(scaled * verts[k])
			out_n.append((normal_basis * normals[k]).normalized())
			out_c.append(colour)
		if indices.is_empty():
			for k in verts.size():
				out_i.append(base + k)
		else:
			for k in indices:
				out_i.append(base + k)
	tools[key] = {"v": out_v, "n": out_n, "c": out_c, "i": out_i}


## One surface per material in `tools`, onto a new mesh.
static func _commit(tools: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key: StringName in tools:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = tools[key]["v"]
		arrays[Mesh.ARRAY_NORMAL] = tools[key]["n"]
		arrays[Mesh.ARRAY_COLOR] = tools[key]["c"]
		arrays[Mesh.ARRAY_INDEX] = tools[key]["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mat(key))
	return mesh
