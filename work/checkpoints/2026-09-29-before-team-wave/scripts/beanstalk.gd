extends Node3D

## A beanstalk: one greyish-green stalk climbing out of sight, hung with dried
## leaves, bending in the wind.
##
## The whole plant is a single mesh with the stalk and leaf colours baked per
## vertex, so it costs one draw call, and the sway lives in a vertex shader
## rather than in animated nodes. That is not just an optimisation: a hundred
## metres of stalk has to *bend*, and bending it on the CPU would mean cutting
## it into a chain of segments and rotating every one of them each frame.

@export var shader: Shader = null

@export_group("Shape")
@export var height := 110.0
@export var base_radius := 0.34
@export var tip_radius := 0.05
## Full turns the stalk winds as it climbs.
@export var twist_turns := 2.2
## How far it wanders off vertical on the way up, in metres.
@export var lean := 2.4
## Rings up the stalk. Most of them are spent low down, where you see it.
@export var rings := 30
@export var sides := 6

@export_group("Leaves")
@export var leaf_levels := 14
@export var leaves_per_level := 3
@export var leaf_length := 2.3
@export var leaf_width := 0.95
## How far the leaves hang below horizontal. Dried ones droop.
@export var leaf_droop_degrees := 38.0
## Where the lowest leaves start, as a fraction of the way up. Clear of the
## ground, so nothing is buried in the mud at the root.
@export_range(0.0, 1.0) var leaf_bottom := 0.075
## Fraction of the way up where leaves stop. They thin out near the top.
@export_range(0.0, 1.0) var leaf_top := 0.72

@export_group("Colour")
@export var stalk_color := Color(0.325490, 0.372549, 0.286275)
@export var leaf_color := Color(0.403922, 0.388235, 0.274510)
## Leaves are mixed toward this as they age, which varies them tip to root.
@export var dry_color := Color(0.443137, 0.396078, 0.278431)

@export_group("Wind")
@export var sway_amount := 1.15
@export var sway_speed := 0.32
## Set by whoever plants it, so every plant drifts on its own and the level
## still comes out the same for a given maze seed. 0 means roll one.
##
## Not derived from the plant's position: _ready runs on add_child, which is
## before the planter has moved it anywhere, so every stalk would see the
## origin and pick the same number.
@export var wind_seed := 0

@export_group("Collision")
## How far up you cannot walk through it. Above that there is nothing to hit.
@export var collide_height := 16.0

@onready var stalk: MeshInstance3D = $Stalk
@onready var collider: CollisionShape3D = $Trunk/CollisionShape3D

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = wind_seed if wind_seed != 0 else randi()
	stalk.mesh = _build()
	stalk.material_override = _material()

	var shape := CylinderShape3D.new()
	shape.radius = base_radius * 1.15
	shape.height = collide_height
	collider.shape = shape
	collider.position = Vector3(0, collide_height * 0.5, 0)


func _material() -> Material:
	if shader == null:
		# Still visible without the shader, just windless.
		var fallback := StandardMaterial3D.new()
		fallback.vertex_color_use_as_albedo = true
		fallback.roughness = 0.95
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		return fallback

	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("sway_amount", sway_amount)
	material.set_shader_parameter("sway_speed", sway_speed)
	# Its own offset into the wind, so neighbouring plants never move together.
	material.set_shader_parameter("phase", _rng.randf() * TAU)
	material.set_shader_parameter("reference_height", height)
	return material


func _build() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# The centre line, precomputed so the leaves can be hung off exactly the
	# same curve the stalk is built around.
	var centres: Array[Vector3] = []
	var radii: Array[float] = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		# Rings bunched toward the bottom: that is the part anyone stands next
		# to, and the top is a thin line against the sky either way.
		var climb := pow(t, 1.35)
		centres.append(Vector3(
			sin(t * PI * 0.9) * lean,
			climb * height,
			cos(t * PI * 0.65) * lean * 0.6 - lean * 0.6,
		))
		radii.append(lerpf(base_radius, tip_radius, pow(t, 0.55)))

	_build_stalk(tool, centres, radii)
	_build_leaves(tool, centres, radii)
	tool.generate_normals()
	return tool.commit()


func _build_stalk(tool: SurfaceTool, centres: Array[Vector3], radii: Array[float]) -> void:
	for i in rings:
		var t0 := float(i) / float(rings)
		var t1 := float(i + 1) / float(rings)
		for s in sides:
			var a0 := float(s) / float(sides) * TAU
			var a1 := float(s + 1) / float(sides) * TAU
			# The twist is what makes it read as a climbing vine rather than a
			# pole: each ring is rotated a little further round than the last.
			var w0 := t0 * twist_turns * TAU
			var w1 := t1 * twist_turns * TAU

			var p00 := _on_ring(centres[i], radii[i], a0 + w0)
			var p01 := _on_ring(centres[i], radii[i], a1 + w0)
			var p10 := _on_ring(centres[i + 1], radii[i + 1], a0 + w1)
			var p11 := _on_ring(centres[i + 1], radii[i + 1], a1 + w1)

			# Faint banding up the stalk, so its length is readable.
			var shade := 0.88 + 0.12 * sin(t0 * 40.0)
			var colour := Color(
				stalk_color.r * shade, stalk_color.g * shade, stalk_color.b * shade)
			_quad(tool, p00, p01, p11, p10, colour)


func _build_leaves(tool: SurfaceTool, centres: Array[Vector3], radii: Array[float]) -> void:
	for level in leaf_levels:
		var t: float = lerpf(leaf_bottom, leaf_top, float(level) / float(maxi(leaf_levels - 1, 1)))
		var index := int(t * float(rings))
		index = clampi(index, 0, rings)
		var centre := centres[index]
		var radius := radii[index]

		for n in leaves_per_level:
			# Offset each level so the leaves spiral rather than stack in rows.
			var around := (float(n) / float(leaves_per_level)) * TAU \
				+ float(level) * 0.9 + t * twist_turns * TAU
			var outward := Vector3(cos(around), 0.0, sin(around))
			var droop := deg_to_rad(leaf_droop_degrees) * _rng.randf_range(0.75, 1.3)
			# Shorter and more shrivelled the higher up they are.
			var length := leaf_length * lerpf(1.15, 0.5, t) * _rng.randf_range(0.8, 1.15)
			var width := leaf_width * lerpf(1.1, 0.55, t) * _rng.randf_range(0.8, 1.2)

			var root := centre + outward * radius * 0.85
			# Flatten the droop rather than let a low leaf hang through the
			# floor. A clamp, not just careful tuning of leaf_bottom, because
			# the length and droop are both rolled and either can go long.
			var reach_down := maxf(root.y - 0.2, 0.0)
			if length * sin(droop) > reach_down:
				droop = asin(clampf(reach_down / maxf(length, 0.001), 0.0, 1.0))
			var along := (outward * cos(droop) - Vector3.UP * sin(droop)).normalized()
			var across := outward.cross(Vector3.UP).normalized()

			var tip := root + along * length
			var mid := root + along * (length * 0.42)
			var left := mid + across * (width * 0.5)
			var right := mid - across * (width * 0.5)

			# Drier toward the tip, the way an old leaf goes.
			var near := leaf_color.lerp(dry_color, _rng.randf_range(0.0, 0.45))
			var far := leaf_color.lerp(dry_color, _rng.randf_range(0.55, 1.0))
			_triangle(tool, root, left, tip, near, near, far)
			_triangle(tool, root, tip, right, near, far, near)


func _on_ring(centre: Vector3, radius: float, angle: float) -> Vector3:
	return centre + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _quad(
	tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color
) -> void:
	_triangle(tool, a, b, c, colour, colour, colour)
	_triangle(tool, a, c, d, colour, colour, colour)


func _triangle(
	tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
	ca: Color, cb: Color, cc: Color
) -> void:
	tool.set_color(ca)
	tool.add_vertex(a)
	tool.set_color(cb)
	tool.add_vertex(b)
	tool.set_color(cc)
	tool.add_vertex(c)
