extends Node3D

## Damp (2026-10-14): wet patches on the floor and water dripping from the vault.
##
## WET PATCHES are decals that touch only the floor slabs (`BrickLevel.WET_LAYER`,
## the decal's `cull_mask`): darker stone, and a much smoother surface that picks
## up the torches as glints -- smoothest in the middle, where water stands. Some
## lie along the foot of a wall, where water running down the brick would
## gather, some out in the corridor, more in the open courts, and one under
## every drip. Their textures are made here once from noise.
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

## Share of corridor cells with a patch (one in four of those gets two).
const PATCH_SHARE := 0.34
## Share of court cells with a patch -- open to the sky, so wetter.
const COURT_PATCH_SHARE := 0.55
## Share of straights with a drip -- far more where a torch hangs, since a drop
## is only ever seen by the light it catches -- and of corners.
const DRIP_SHARE := 0.04
const TORCH_DRIP_SHARE := 0.32
const CORNER_DRIP_SHARE := 0.07
## How far across the corridor a drip may hang: the middle, clear of anything
## standing along the walls (clutter, hiding carts).
const DRIP_ACROSS := 0.75
const DRIP_ALONG := 2.4
const PATCH_RANGE := 34.0
const DRIP_RANGE := 26.0
const CHECK_EVERY := 0.25
## Time between drops from one spot.
const PERIOD_MIN := 1.8
const PERIOD_MAX := 4.6
const GRAVITY := 9.8
const SPLASH := 0.14
## The drop's glint (see _drop).
const DROP_GLINT := Color(0.55, 0.4, 0.26)
const TEXTURE_SIZE := 128
const VARIANTS := 4

static var _textures: Array = []
static var _drop_mesh: Mesh = null

var _drips: Array[GPUParticles3D] = []
var _floor_materials: Array[StandardMaterial3D] = []
var _clock := 0.0
var _on := true


## Lays the patches and drips over the brick level `built`. `blocked` cells get
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
	var patches := Node3D.new()
	patches.name = "WetPatches"
	add_child(patches)
	var drips := Node3D.new()
	drips.name = "Drips"
	add_child(drips)
	var rng := RandomNumberGenerator.new()
	var patch_count := 0
	for key in built.cells:
		var cell = built.cells[key]
		rng.seed = hash(key) ^ 0xda3b
		var centre: Vector3 = built.to_world(cell.pos)
		var basis := Basis(Vector3.UP, -float(cell.turn) * PI * 0.5)
		if cell.court:
			if BrickLevel._in_boss_block(built, cell):
				continue
			if rng.randf() < COURT_PATCH_SHARE:
				for i in rng.randi_range(1, 3):
					var at := centre + Vector3(rng.randf_range(-2.2, 2.2), 0.0, rng.randf_range(-2.2, 2.2))
					_patch(patches, rng, at, rng.randf() * TAU,
						Vector2(rng.randf_range(1.4, 3.4), rng.randf_range(1.2, 2.8)), floor_top)
					patch_count += 1
			continue
		if rng.randf() < PATCH_SHARE:
			for i in (2 if rng.randf() < 0.25 else 1):
				if cell.kind == "straight" and rng.randf() < 0.55:
					# Along the foot of a wall, long way along it.
					var side := -1.0 if rng.randf() < 0.5 else 1.0
					var size := Vector2(rng.randf_range(1.6, 3.2), rng.randf_range(0.7, 1.3))
					var local := Vector3(side * (BrickLevel.WALL_FACE - size.y * 0.32), 0.0,
						rng.randf_range(-2.0, 2.0))
					_patch(patches, rng, centre + basis * local,
						-float(cell.turn) * PI * 0.5 + PI * 0.5 + rng.randf_range(-0.12, 0.12),
						size, floor_top)
				else:
					var local := Vector3(rng.randf_range(-1.1, 1.1), 0.0, rng.randf_range(-1.6, 1.6))
					_patch(patches, rng, centre + basis * local, rng.randf() * TAU,
						Vector2(rng.randf_range(0.9, 2.2), rng.randf_range(0.8, 1.8)), floor_top)
				patch_count += 1
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
			_patch(patches, rng, Vector3(at.x, centre.y, at.z), rng.randf() * TAU,
				Vector2(rng.randf_range(0.55, 1.0), rng.randf_range(0.5, 0.9)), floor_top, true)
			patch_count += 1
	set_meta("patch_count", patch_count)
	set_meta("drip_count", _drips.size())
	print("[damp] %d wet patches, %d drips" % [patch_count, _drips.size()])
	set_enabled(Graphics.damp)


func _patch(holder: Node3D, rng: RandomNumberGenerator, at: Vector3, yaw: float,
		size: Vector2, floor_top: float, pool := false) -> void:
	var tex: Array = _texture(rng.randi_range(0, VARIANTS - 1))
	var d := Decal.new()
	d.size = Vector3(size.x, 0.6, size.y)
	d.texture_albedo = tex[0]
	d.texture_orm = tex[1]
	# Black, mixed in part: darkens the stone without hiding it.
	d.albedo_mix = 0.72 if pool else 0.6
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	d.cull_mask = BrickLevel.WET_LAYER
	d.distance_fade_enabled = true
	d.distance_fade_begin = PATCH_RANGE
	d.distance_fade_length = 8.0
	d.position = at + Vector3(0.0, floor_top, 0.0)
	d.rotation.y = yaw
	holder.add_child(d)


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


## [albedo, orm] for one patch shape: noise inside a soft round falloff. The
## albedo is black with the wetness in its alpha (the decal's mask for both
## textures); the ORM's green is the roughness -- damp at the edges, nearly a
## mirror where water stands in the middle.
static func _texture(variant: int) -> Array:
	if _textures.is_empty():
		for v in VARIANTS:
			_textures.append(_make_texture(v))
	return _textures[variant]


static func _make_texture(variant: int) -> Array:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 7310 + variant * 97
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	var n := TEXTURE_SIZE
	var albedo := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var orm := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var shape := 1.0 - smoothstep(0.25, 1.0, r)
			var wet := shape * 0.95 + noise.get_noise_2d(float(x), float(y)) * 0.85 - 0.28
			var edge := 1.0 - smoothstep(0.78, 0.98, r)
			var mask := smoothstep(0.0, 0.38, wet) * edge
			var pool := smoothstep(0.3, 0.7, wet)
			albedo.set_pixel(x, y, Color(0.0, 0.0, 0.0, mask))
			orm.set_pixel(x, y, Color(1.0, lerpf(0.32, 0.07, pool), 0.0, 1.0))
	albedo.generate_mipmaps()
	orm.generate_mipmaps()
	return [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(orm)]


## Graphics.damp. Off: no patches, no drips, and the floor back to matte.
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
