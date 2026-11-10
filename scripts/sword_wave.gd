extends Node3D
## The heavy slash's wave (note 160): a gold crescent thrown off the sword's Q
## cut that travels slowly straight ahead, level, cutting everything it passes
## through for `damage` -- once each -- until stone stops it or it runs out of
## `reach`. It is the damage of the heavy slash; the blade itself does not bite.
##
## Each physics tick the stretch it crossed is swept with one box (the wave's
## width and height, as long as the step), so nothing is stepped over, and a ray
## down its middle against the level's geometry stops it at the first wall,
## door or vat. Anything hit has to be in sight of the wave (the box can poke
## through a side wall at a corner). Weak points take `strike()`, as from a cut.
##
## Spawned by player.gd `_fire_wave`. Its light and sparks only exist with
## `Graphics.effects`; the wave itself always does, since it is the attack.

const SHADER := preload("res://shaders/sword_wave.gdshader")

## Across and up, metres, at launch; it spreads a little as it goes (`SPREAD`).
const WIDTH := 3.0
const HEIGHT := 1.9
const SPREAD := 0.3
## The crescent: radius of its arc, how far its middle bows ahead of its tips,
## how much of the radius it is thick at the middle, and the arc's half-angle.
const ARC_RADIUS := 1.7
const ARC_BOW := 0.55
const ARC_THICK := 0.42
const ARC_HALF := 1.25
## Fade-in over the first metres; out over the last of the reach, and quickly on a wall.
const FADE_IN := 0.06
const FADE_OUT := 0.18
const WALL_FADE := 0.22

var player: CharacterBody3D
var damage := 80.0
var speed := 7.0
var reach := 30.0
var push := 9.0
var stun := 0.5
var stagger_chance := 1.0
## The cut's diagonal, radians round the direction of travel.
var roll := -0.5

var _dir := Vector3.FORWARD
var _travelled := 0.0
var _age := 0.0
var _dying := -1.0
var _hit := {}
var _mesh: MeshInstance3D
var _light: OmniLight3D
var _sparks: CPUParticles3D

static var _arc_mesh: ArrayMesh
static var _material: ShaderMaterial


## Puts a wave at `from` heading along `dir` (flattened), under `parent`.
static func launch(parent: Node, owner_player: CharacterBody3D, from: Vector3, dir: Vector3, tilt: float,
		hit := -1.0) -> Node3D:
	var w := Node3D.new()
	w.set_script(load("res://scripts/sword_wave.gd"))
	w.name = "SwordWave"
	w.set("player", owner_player)
	w.set("roll", tilt)
	# Before `_start`: it hits whatever is already inside it at once (note 172:
	# set after, a foe within reach took the default 80).
	if hit >= 0.0:
		w.set("damage", hit)
	parent.add_child(w)
	w.call("_start", from, dir)
	return w


func _start(from: Vector3, dir: Vector3) -> void:
	top_level = true
	dir.y = 0.0
	_dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(_dir, Vector3.UP) * Basis(Vector3.FORWARD, roll), from)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = arc_mesh()
	_mesh.material_override = material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.set_instance_shader_parameter(&"fade", 1.0)
	add_child(_mesh)
	if Graphics.effects:
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.72, 0.3)
		_light.light_energy = 0.0
		_light.omni_range = 5.0
		_light.shadow_enabled = false
		add_child(_light)
		_sparks = _make_sparks()
		add_child(_sparks)
	# Anything already inside it as it leaves the blade is hit straight away.
	_sweep(from - _dir * 0.6, from)


func _physics_process(delta: float) -> void:
	_age += delta
	if _dying >= 0.0:
		_dying += delta
		_paint()
		if _dying >= WALL_FADE:
			queue_free()
		return
	var step := speed * delta
	var from := global_position
	var to := from + _dir * step
	# Stone (walls, doors, vats) stops it where it meets it.
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(from, to + _dir * 0.25, int(player.get("geometry_mask")))
	ray.exclude = [player.get_rid()]
	var wall := space.intersect_ray(ray)
	if not wall.is_empty():
		to = (wall["position"] as Vector3) - _dir * 0.25
	_sweep(from, to)
	global_position = to
	_travelled += step
	if not wall.is_empty():
		_die_on_wall()
	elif _travelled >= reach:
		queue_free()
	else:
		_paint()


## Everything in the box from `a` to `b`, not yet hit and in the wave's sight.
func _sweep(a: Vector3, b: Vector3) -> void:
	if player == null or not is_instance_valid(player):
		return
	var grow := _grow()
	var length := maxf(a.distance_to(b), 0.05) + 0.4
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH * grow, HEIGHT * grow, length)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis.looking_at(_dir, Vector3.UP), (a + b) * 0.5)
	q.collision_mask = (player.get("hitbox") as Area3D).collision_mask
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [player.get_rid()]
	var space := get_world_3d().direct_space_state
	for hit in space.intersect_shape(q, 32):
		var body := hit["collider"] as Node3D
		if body == null or _hit.has(body) or not is_instance_valid(body):
			continue
		if body.has_method("swat"):
			continue
		# Not through stone: the box is wider than the wave's ray.
		var los := PhysicsRayQueryParameters3D.create(b, body.global_position + Vector3(0.0, 0.9, 0.0),
			int(player.get("geometry_mask")))
		los.exclude = [player.get_rid()]
		if not space.intersect_ray(los).is_empty():
			continue
		_hit[body] = true
		player.emit_signal(&"hit_landed", body)
		if body.has_method("strike"):
			body.call("strike", _dir)
			continue
		if body.has_method("take_damage"):
			body.call("take_damage", damage, _dir)
		player.call("knock", body, _dir * push + Vector3(0.0, 2.0, 0.0), stun, stagger_chance)
		if body.has_method("alert"):
			body.call("alert")


## 1 at launch, `1 + SPREAD` at the end of its reach.
func _grow() -> float:
	return 1.0 + SPREAD * clampf(_travelled / maxf(reach, 0.01), 0.0, 1.0)


func _paint() -> void:
	var k := _travelled / maxf(reach, 0.01)
	var on := smoothstep(0.0, FADE_IN, k) * (1.0 - smoothstep(1.0 - FADE_OUT, 1.0, k))
	if _dying >= 0.0:
		on *= 1.0 - clampf(_dying / WALL_FADE, 0.0, 1.0)
	# A gentle shimmer of its brightness, and it swells as it spreads.
	on *= 0.9 + 0.1 * sin(_age * 31.0)
	_mesh.set_instance_shader_parameter(&"fade", 1.0 - on)
	var g := _grow()
	_mesh.scale = Vector3(g, g, 1.0 + (g - 1.0) * 0.5)
	if _light != null:
		_light.light_energy = 2.6 * on
	if _sparks != null:
		_sparks.emitting = _dying < 0.0 and on > 0.2


## Struck stone: a flare of sparks against it, and gone.
func _die_on_wall() -> void:
	_dying = 0.0
	_paint()
	if not Graphics.effects:
		return
	var burst := _make_sparks()
	burst.one_shot = true
	burst.amount = 40
	burst.explosiveness = 0.95
	burst.direction = -_dir
	burst.spread = 70.0
	burst.initial_velocity_min = 2.5
	burst.initial_velocity_max = 6.0
	burst.emission_box_extents = Vector3(WIDTH * 0.45, HEIGHT * 0.35, 0.05)
	get_parent().add_child(burst)
	burst.global_transform = Transform3D(Basis.looking_at(_dir, Vector3.UP), global_position)
	burst.emitting = true
	get_tree().create_timer(1.2).timeout.connect(burst.queue_free)


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.55
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(WIDTH * 0.4, HEIGHT * 0.3, 0.1)
	p.direction = Vector3(0.0, 0.0, 1.0)
	p.spread = 35.0
	p.gravity = Vector3(0.0, -2.5, 0.0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	p.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.75, 0.3)
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	var ramp := Gradient.new()
	ramp.set_color(0, Color(2.0, 1.6, 0.8))
	ramp.set_color(1, Color(0.0, 0.0, 0.0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## The crescent, built once: a ribbon round an arc in the plane across the way
## it travels (x across, y up), its middle bowed forward (-z), thick in the
## middle and thinning to points. UV.x runs tip to tip, UV.y front edge to back.
static func arc_mesh() -> ArrayMesh:
	if _arc_mesh != null:
		return _arc_mesh
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var n := 40
	for i in n + 1:
		var u := float(i) / float(n)
		var a := lerpf(-ARC_HALF, ARC_HALF, u)
		var thick := ARC_RADIUS * ARC_THICK * pow(cos(a / ARC_HALF * PI * 0.5), 0.8)
		var bow := ARC_BOW * cos(a / ARC_HALF * PI * 0.5)
		# The arc's centre sits below the middle, so the crescent spans HEIGHT.
		var outer := Vector3(sin(a) * ARC_RADIUS, cos(a) * ARC_RADIUS - ARC_RADIUS * 0.72, -bow)
		var inner_r := ARC_RADIUS - thick
		var inner := Vector3(sin(a) * inner_r, cos(a) * inner_r - ARC_RADIUS * 0.72, -bow + thick * 0.6)
		verts.append(outer)
		verts.append(inner)
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		if i < n:
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_arc_mesh = ArrayMesh.new()
	_arc_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_arc_mesh.custom_aabb = AABB(Vector3(-2.5, -2.0, -2.0), Vector3(5.0, 4.0, 4.0))
	return _arc_mesh


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material
