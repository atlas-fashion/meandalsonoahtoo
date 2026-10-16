extends Node3D

## A gob of radioactive goo spat by a sewer lizard (sewer_lizard.gd, 2026-10-16).
## Lobbed: it is thrown on a ballistic arc that lands on where the player will be
## (`fire` leads them by their velocity), falls under GRAVITY, glows, and drips.
## Stone stops it in a splash; the player's body takes the hit through
## `player.take_damage(damage, travel, proxy)`, so the guard works on it like any
## blow -- a block lets a tenth through, a parry none -- and a guarded gob just
## bursts. The proxy (arrow.gd's) takes the parry's shove and reflect: spit is not
## something you can bat back.
##
## The player is tested as a capsule, segment to segment, as arrow.gd does: the
## player shares layer 1 with everything.

const ARROW := preload("res://scripts/arrow.gd")
const GRAVITY := 9.0
const LIFE := 3.0
const WORLD_MASK := 2 | 256
const BODY_LOW := 0.2
const BODY_HIGH := 1.6
const BODY_RADIUS := 0.4
## Its glow: the sewer's radioactive green, hotter than the moss.
const GOO := Color(0.55, 1.0, 0.18)
const RADIUS := 0.085

var damage := 5.0
var shooter: Node3D
var velocity := Vector3.ZERO

var _age := 0.0
var _proxy: Node3D
var _light: OmniLight3D

static var _mesh: SphereMesh
static var _mat: StandardMaterial3D
static var _drop_mesh: QuadMesh


## A gob from `from`, timed to come down on `target` (a point, led already) after
## a flight of `flight` seconds.
static func fire(parent: Node, from: Vector3, target: Vector3, by: Node3D, dmg: float, flight: float) -> Node3D:
	var g := Node3D.new()
	g.set_script(load("res://scripts/goo.gd"))
	g.name = "Goo"
	parent.add_child(g)
	g.global_position = from
	g.set("shooter", by)
	g.set("damage", dmg)
	var t := maxf(flight, 0.15)
	g.set("velocity", (target - from) / t + Vector3(0.0, 0.5 * GRAVITY * t, 0.0))
	return g


static func _shared() -> void:
	if _mesh != null:
		return
	_mesh = SphereMesh.new()
	_mesh.radius = RADIUS
	_mesh.height = RADIUS * 2.0
	_mesh.radial_segments = 12
	_mesh.rings = 6
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = GOO * 2.6
	_mat.disable_receive_shadows = true
	_drop_mesh = QuadMesh.new()
	_drop_mesh.size = Vector2(0.03, 0.03)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = GOO * 2.0
	_drop_mesh.material = dm


func _ready() -> void:
	_shared()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var effects: bool = get_node_or_null("/root/Graphics") == null or bool(get_node("/root/Graphics").get("effects"))
	if effects:
		_light = OmniLight3D.new()
		_light.light_color = GOO
		_light.light_energy = 0.7
		_light.omni_range = 2.2
		_light.shadow_enabled = false
		_light.light_cull_mask = (1 << 15) | 1
		add_child(_light)
		var trail := _drops(5, 0.35)
		trail.emitting = true
		trail.one_shot = false
		trail.explosiveness = 0.0
		add_child(trail)
	_proxy = ARROW.Proxy.new()
	_proxy.name = "GooProxy"
	add_child(_proxy)
	_proxy.position = Vector3(0.0, -1.3, 0.0)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFE:
		queue_free()
		return
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	# Stone.
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	# The player.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and _meets(player, from, hit.get("position", to)):
		var dir := velocity.normalized()
		player.call("take_damage", damage, dir, _proxy)
		_splash(global_position, -dir)
		return
	if not hit.is_empty():
		_splash(hit.position, hit.normal)
		return
	global_position = to


func _meets(body: Node3D, a: Vector3, b: Vector3) -> bool:
	var base := body.global_position
	var p := Geometry3D.get_closest_points_between_segments(a, b,
		base + Vector3(0.0, BODY_LOW, 0.0), base + Vector3(0.0, BODY_HIGH, 0.0))
	return (p[0] as Vector3).distance_to(p[1]) <= BODY_RADIUS + RADIUS


func _splash(at: Vector3, normal: Vector3) -> void:
	var parent := get_parent()
	if parent != null:
		var burst := _drops(14, 0.55)
		burst.one_shot = true
		burst.explosiveness = 1.0
		burst.direction = normal
		burst.spread = 75.0
		burst.initial_velocity_min = 1.0
		burst.initial_velocity_max = 3.2
		parent.add_child(burst)
		burst.global_position = at + normal * 0.03
		burst.emitting = true
		get_tree().create_timer(1.2).timeout.connect(burst.queue_free)
		if _light != null:
			var flash := OmniLight3D.new()
			flash.light_color = GOO
			flash.light_energy = 1.4
			flash.omni_range = 2.6
			flash.shadow_enabled = false
			flash.light_cull_mask = (1 << 15) | 1
			parent.add_child(flash)
			flash.global_position = at + normal * 0.2
			var t := flash.create_tween()
			t.tween_property(flash, "light_energy", 0.0, 0.35)
			t.tween_callback(flash.queue_free)
	queue_free()


func _drops(n: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.mesh = _drop_mesh
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
