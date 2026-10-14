extends Node3D

## Damp (2026-10-14): water dripping from the vault, and the floor's wet sheen.
##
## The wet look of the floor itself -- its gloss and its puddles -- is in the
## floor's own Tripo texture (brick_kit_raw/floor_wet.glb, CLAUDE.md section 41);
## this only switches the floor's specular on so that gloss can show. (The
## decal puddles this file used to lay were removed at the user's request.)
##
## DRIPS hang from the underside of the barrel vault, found by casting a ray up
## through the vault mesh itself, so a bead always sits ON the brick. Each is a
## single-particle GPUParticles3D whose process shader (water_drip.gdshader) runs
## the whole life of one drop: a bead gathers, lets go, falls the measured
## height, splashes flat on the floor and is gone until the next. One node does
## the range checks for all of them: a drip only runs within DRIP_RANGE.
##
## Both ride on `Graphics.damp`; switched off, the floor's specular goes too.

const BrickLevel := preload("res://scripts/brick_level.gd")
const DRIP_SHADER := preload("res://shaders/water_drip.gdshader")

## Share of straights with a drip -- far more where a torch hangs, since a drop
## is only ever seen by the light it catches -- and of corners.
const DRIP_SHARE := 0.04
const TORCH_DRIP_SHARE := 0.32
const CORNER_DRIP_SHARE := 0.07
## How far across the corridor a drip may hang: the middle, clear of anything
## standing along the walls (clutter, hiding carts).
const DRIP_ACROSS := 0.75
const DRIP_ALONG := 2.4
const DRIP_RANGE := 26.0
const CHECK_EVERY := 0.25
## Time between drops from one spot.
const PERIOD_MIN := 1.8
const PERIOD_MAX := 4.6
const GRAVITY := 9.8
const SPLASH := 0.14
## The drop's glint (see _drop).
const DROP_GLINT := Color(0.55, 0.4, 0.26)

static var _drop_mesh: Mesh = null

var _drips: Array[GPUParticles3D] = []
var _floor_materials: Array[StandardMaterial3D] = []
var _clock := 0.0
var _on := true


## Hangs the drips in the brick level `built`. `blocked` cells get
## no drip (doors, hiding carts).
func build(built, blocked: Dictionary) -> void:
	name = "Damp"
	add_to_group("damp")
	var kit: Dictionary = BrickLevel.meshes(1.0)
	var floor_mesh: Mesh = kit.get("floor")
	if floor_mesh == null:
		return
	for s in floor_mesh.get_surface_count():
		var m := floor_mesh.surface_get_material(s) as StandardMaterial3D
		if m != null and not _floor_materials.has(m):
			_floor_materials.append(m)
	# The slabs' top, as measured off the mesh; drops splash a hair above it.
	var floor_top := floor_mesh.get_aabb().end.y
	var vaults := {}
	for v in ["vault_straight", "vault_corner"]:
		var vm: Mesh = kit.get(v)
		if vm != null:
			vaults[v] = vm.generate_triangle_mesh()
	var drips := Node3D.new()
	drips.name = "Drips"
	add_child(drips)
	var rng := RandomNumberGenerator.new()
	for key in built.cells:
		var cell = built.cells[key]
		rng.seed = hash(key) ^ 0xda3b
		var centre: Vector3 = built.to_world(cell.pos)
		var basis := Basis(Vector3.UP, -float(cell.turn) * PI * 0.5)
		if cell.court:
			continue
		# Drips.
		if blocked.has(key) or built.skylights.has(cell.pos):
			continue
		var vault := ""
		var share := 0.0
		match cell.kind:
			"straight":
				vault = "vault_straight"
				share = TORCH_DRIP_SHARE if built.torch_cells.has(key) else DRIP_SHARE
			"corner":
				vault = "vault_corner"
				share = CORNER_DRIP_SHARE
		if vault == "" or not vaults.has(vault) or rng.randf() >= share:
			continue
		var first := Vector3(rng.randf_range(-DRIP_ACROSS, DRIP_ACROSS), 0.0,
			rng.randf_range(-DRIP_ALONG, DRIP_ALONG))
		if cell.kind == "corner":
			first = Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		var points := [first]
		# A crack often weeps in two places close together.
		if rng.randf() < 0.3:
			points.append(first + Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.5, 0.5)))
		for local: Vector3 in points:
			local.x = clampf(local.x, -DRIP_ACROSS, DRIP_ACROSS)
			var hit: Dictionary = (vaults[vault] as TriangleMesh).intersect_ray(
				Vector3(local.x, 1.5, local.z), Vector3.UP)
			if hit.is_empty():
				continue
			var under: Vector3 = hit["position"]
			if under.y < 3.2 or under.y > 5.8:
				continue
			var at := centre + basis * Vector3(under.x, under.y - 0.004, under.z)
			_drip(drips, rng, at, at.y - (centre.y + floor_top) - 0.004)
	set_meta("drip_count", _drips.size())
	print("[damp] %d drips" % _drips.size())
	set_enabled(Graphics.damp)


func _drip(holder: Node3D, rng: RandomNumberGenerator, at: Vector3, fall: float) -> void:
	var period := rng.randf_range(PERIOD_MIN, PERIOD_MAX)
	var drop_time := sqrt(2.0 * fall / GRAVITY)
	var mat := ShaderMaterial.new()
	mat.shader = DRIP_SHADER
	mat.set_shader_parameter("fall", fall)
	mat.set_shader_parameter("hang", maxf(0.3, (period - drop_time - SPLASH) * 0.85))
	mat.set_shader_parameter("splash", SPLASH)
	mat.set_shader_parameter("gravity", GRAVITY)
	mat.set_shader_parameter("phase", rng.randf() * period)
	var p := GPUParticles3D.new()
	p.amount = 1
	p.lifetime = period
	p.local_coords = true

	p.process_material = mat
	p.draw_pass_1 = _drop()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-0.1, -fall - 0.1, -0.1), Vector3(0.2, fall + 0.2, 0.2))
	p.visibility_range_end = DRIP_RANGE
	p.emitting = false
	p.position = at
	holder.add_child(p)
	_drips.append(p)


## The drop: a small bead of firelit water. Lit honestly, a centimetre of clear
## water hanging in unlit air is invisible -- measured: not one pixel of it in
## forty frames of a drip 2.4 m away. A drop is only ever seen by the torch it
## mirrors, so it is drawn as that glint: unshaded, added onto the scene in the
## torches' colour, faint. Drips hang mostly beside torches (TORCH_DRIP_SHARE).
static func _drop() -> Mesh:
	if _drop_mesh != null:
		return _drop_mesh
	var s := SphereMesh.new()
	s.radius = 0.0065
	s.height = 0.013
	s.radial_segments = 8
	s.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = DROP_GLINT
	s.material = m
	_drop_mesh = s
	return s


## Graphics.damp. Off: no drips, and the floor back to matte.
func set_enabled(on: bool) -> void:
	_on = on
	visible = on
	for m in _floor_materials:
		m.specular_mode = (BaseMaterial3D.SPECULAR_SCHLICK_GGX if on
			else BaseMaterial3D.SPECULAR_DISABLED)
	if not on:
		for p in _drips:
			p.emitting = false


func _process(delta: float) -> void:
	if not _on:
		return
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = CHECK_EVERY
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	for p in _drips:
		var near := p.global_position.distance_squared_to(eye) < DRIP_RANGE * DRIP_RANGE
		if p.emitting != near:
			p.emitting = near
