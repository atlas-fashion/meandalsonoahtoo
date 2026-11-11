extends MultiMeshInstance3D

## Beetles crawling the dungeon's walls and floors (note 177): dark glossy
## cockroach-sized things in nests on the root-grown walls and round the dead,
## crawling over the brick and across the floor at the wall's foot in short
## bursts, stopping to feel about, and scattering from anyone who comes close.
##
## One MultiMesh for every beetle in the level (`MAX` drawn at once): only the
## nests within `AWAKE` metres of the camera move and draw; the rest are left
## where they were and cost nothing. Each nest is a wall, and its beetles live in
## a 2D field over it: u along the wall, v its height -- and v below zero is the
## floor in front of it, -v metres out -- so one walk carries a beetle down the
## brick and away over the flags. On the wall it sits on the stone's real face
## (the wall's relief, ruin_roots.gd).

const AWAKE := 16.0
const MAX := 220
const SPEED := 0.22
const SCATTER := 1.1
const FLEE_RANGE := 1.7
## How far out over the floor a nest's beetles roam.
const FLOOR_OUT := 0.9

var _nests: Array = []
var _bugs: Array = []
var _relief = null
var _rng := RandomNumberGenerator.new()


func setup(relief, seed_: int) -> void:
	_relief = relief
	_rng.seed = seed_
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _beetle_mesh()
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	# Drawn anywhere: the instances are placed in world space round the camera.
	custom_aabb = AABB(Vector3(-4000, -100, -4000), Vector3(8000, 200, 8000))


## A nest of `n` beetles on the wall at `xf` (its face's foot, +Z out of it),
## between `u0` and `u1` along it.
func add_nest(xf: Transform3D, n: int, u0 := -2.3, u1 := 2.3) -> void:
	var nest := {"xf": xf, "u0": u0, "u1": u1, "bugs": []}
	for i in n:
		var b := {
			"u": _rng.randf_range(u0, u1), "v": _rng.randf_range(-0.6, 2.6),
			"dir": _rng.randf() * TAU, "wait": _rng.randf_range(0.0, 2.0),
			"go": 0.0, "scale": _rng.randf_range(0.7, 1.25), "phase": _rng.randf() * 10.0,
		}
		nest["bugs"].append(b)
	_nests.append(nest)


func nest_count() -> int:
	return _nests.size()


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or multimesh == null:
		return
	var eye := cam.global_position
	var players: Array = []
	for p in Coop.all():
		if is_instance_valid(p):
			players.append((p as Node3D).global_position)
	var shown := 0
	for nest in _nests:
		var xf: Transform3D = nest["xf"]
		if xf.origin.distance_squared_to(eye) > AWAKE * AWAKE:
			continue
		var inv := xf.affine_inverse()
		var near_local: Array = []
		for p in players:
			var l: Vector3 = inv * p
			near_local.append(Vector2(l.x, -maxf(l.z, 0.0)))
		for b in nest["bugs"]:
			if shown >= MAX:
				break
			_step(b, nest, near_local, delta)
			multimesh.set_instance_transform(shown, xf * _local_xf(b))
			shown += 1
	multimesh.visible_instance_count = shown


## One beetle's walk: bursts and stops, a wander in its heading, away from
## anyone close, kept inside its field.
func _step(b: Dictionary, nest: Dictionary, near: Array, delta: float) -> void:
	var u: float = b["u"]
	var v: float = b["v"]
	var fleeing := false
	for p in near:
		var pp: Vector2 = p
		# A player's place in this field: along the wall, and how far out.
		var me := Vector2(u, minf(v, 0.0))
		var away := me - pp
		if away.length() < FLEE_RANGE:
			fleeing = true
			b["dir"] = atan2(away.y + 0.6, away.x)
			b["wait"] = 0.0
			b["go"] = 0.8
	var wait: float = b["wait"]
	if wait > 0.0 and not fleeing:
		b["wait"] = wait - delta
		b["phase"] = float(b["phase"]) + delta * 0.3
		return
	var go: float = b["go"] - delta
	if go <= 0.0 and not fleeing:
		b["wait"] = _rng.randf_range(0.3, 2.5)
		b["go"] = _rng.randf_range(0.4, 2.2)
		b["dir"] = float(b["dir"]) + _rng.randf_range(-1.2, 1.2)
		return
	b["go"] = go
	b["phase"] = float(b["phase"]) + delta * 9.0
	var dir: float = b["dir"] + sin(float(b["phase"]) * 0.7) * 0.4 * delta
	var speed := SCATTER if fleeing else SPEED
	u += cos(dir) * speed * delta
	v += sin(dir) * speed * delta
	var u0: float = nest["u0"]
	var u1: float = nest["u1"]
	if u < u0 or u > u1:
		u = clampf(u, u0, u1)
		dir = PI - dir
	if v > 3.0 or v < -FLOOR_OUT:
		v = clampf(v, -FLOOR_OUT, 3.0)
		dir = -dir
	b["u"] = u
	b["v"] = v
	b["dir"] = dir


## Its transform in the wall's frame: on the brick (facing out of it) or on the
## floor in front of it (facing up), turned to its heading.
func _local_xf(b: Dictionary) -> Transform3D:
	var u: float = b["u"]
	var v: float = b["v"]
	var dir: float = b["dir"]
	var s: float = b["scale"]
	var head := Vector2(cos(dir), sin(dir))
	if v >= 0.0:
		var z := 0.0
		if _relief != null:
			var r: float = _relief.outer(u, v, 0.02)
			z = r if r > -1.0e8 else 0.0
		# Up out of the wall (+Z), forward along the heading in the wall's plane.
		var fwd := Vector3(head.x, head.y, 0.0)
		var up := Vector3(0.0, 0.0, 1.0)
		var side := up.cross(fwd)
		return Transform3D(Basis(side, up, fwd).scaled(Vector3.ONE * s), Vector3(u, v, z + 0.006))
	var fwd2 := Vector3(head.x, 0.0, -head.y).normalized()
	var side2 := Vector3.UP.cross(fwd2)
	return Transform3D(Basis(side2, Vector3.UP, fwd2).scaled(Vector3.ONE * s), Vector3(u, 0.004, -v))


## A beetle about 5 cm long: a glossy shell split down the back, a head, six
## bent legs. Local +Z is its front, +Y its back.
static var _mesh: ArrayMesh = null


static func _beetle_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shell := SphereMesh.new()
	shell.radius = 0.5
	shell.height = 1.0
	shell.radial_segments = 10
	shell.rings = 6
	st.append_from(shell, 0, Transform3D(Basis.from_scale(Vector3(0.026, 0.014, 0.05)), Vector3(0.0, 0.009, -0.004)))
	st.append_from(shell, 0, Transform3D(Basis.from_scale(Vector3(0.016, 0.01, 0.014)), Vector3(0.0, 0.007, 0.026)))
	var leg := BoxMesh.new()
	leg.size = Vector3(1.0, 1.0, 1.0)
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var z := 0.014 - float(k) * 0.016
			var splay := (float(k) - 1.0) * 0.5
			var b := Basis(Vector3.UP, side * (PI * 0.5 + splay)) * Basis(Vector3.RIGHT, 0.5)
			st.append_from(leg, 0, Transform3D(b * Basis.from_scale(Vector3(0.002, 0.002, 0.03)), Vector3(side * 0.018, 0.005, z)))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.055, 0.03)
	mat.roughness = 0.28
	mat.metallic_specular = 0.7
	_mesh = st.commit()
	_mesh.surface_set_material(0, mat)
	return _mesh
