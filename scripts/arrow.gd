extends Node3D

## An archer's arrow (archer.gd, 2026-10-09). Flies straight; stone stops it (it
## sticks there a while); the player's body takes the hit.
##
## The hit goes through `player.take_damage(damage, travel, proxy)`, so the
## guard works on it like any blow: blocked, it is knocked aside and falls;
## PARRIED, it turns round and flies back at the archer who loosed it, homing,
## and hits for the arrow's FULL damage -- not the half every other parry
## returns (the player's own reflect lands on `Proxy`, which takes nothing).
##
## The player and the shooter are tested as capsules (segment to segment), not
## by collision layer: the player's body shares layer 1 with every skeleton, and
## an arrow is meant to pass its archer's fellows -- that is the point of
## hiding behind them.

const SPEED := 26.0
const BACK_SPEED := 30.0
## How hard a parried arrow turns toward its archer, per second.
const HOMING := 9.0
const LIFE := 4.0
const STUCK_LIFE := 6.0
## Stone: the sight layer and the exact walls.
const WORLD_MASK := 2 | 256
## A body, as a capsule: feet + 0.25 to feet + 1.55, this thick.
const BODY_LOW := 0.25
const BODY_HIGH := 1.55
const BODY_RADIUS := 0.42

var damage := 15.0
var shooter: Node3D
var velocity := Vector3.ZERO
var reflected := false

var _age := 0.0
var _stuck := -1.0
var _falling := false
var _proxy: Node3D
var _guard_event = null
var _tip_mat: StandardMaterial3D
var _trail: MeshInstance3D


## What the player's guard sees as the attacker: the guard puts its flash 1.3 m
## above an attacker's origin (it expects feet), so this sits 1.3 m below the
## arrow; and it shrugs off the shove and the half-damage reflect, because the
## arrow itself delivers the full return.
class Proxy extends Node3D:
	func apply_knockback(_impulse: Vector3, _stun := 0.0) -> void:
		pass

	func take_damage(_amount: float, _from := Vector3.ZERO) -> void:
		pass


static func fire(parent: Node, from: Vector3, toward: Vector3, by: Node3D, dmg: float) -> Node3D:
	var a := Node3D.new()
	a.set_script(load("res://scripts/arrow.gd"))
	a.name = "Arrow"
	parent.add_child(a)
	a.global_position = from
	a.set("shooter", by)
	a.set("damage", dmg)
	a.set("velocity", (toward - from).normalized() * SPEED)
	a.call("_point")
	return a


func _ready() -> void:
	top_level = true
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.27, 0.18)
	wood.roughness = 0.9
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = 0.78
	cyl.radial_segments = 5
	cyl.rings = 1
	shaft.mesh = cyl
	shaft.material_override = wood
	shaft.rotation.x = PI * 0.5
	shaft.position.z = 0.39
	add_child(shaft)
	# The head, glowing a little so a shot can be seen coming in the dark.
	_tip_mat = StandardMaterial3D.new()
	_tip_mat.albedo_color = Color(0.3, 0.12, 0.05)
	_tip_mat.emission_enabled = true
	_tip_mat.emission = Color(1.0, 0.45, 0.15)
	_tip_mat.emission_energy_multiplier = 2.5
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.025
	cone.height = 0.09
	cone.radial_segments = 6
	cone.rings = 1
	head.mesh = cone
	head.material_override = _tip_mat
	head.rotation.x = -PI * 0.5
	head.position.z = -0.03
	add_child(head)
	var feather := StandardMaterial3D.new()
	feather.albedo_color = Color(0.55, 0.5, 0.45)
	feather.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 2:
		var vane := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.05, 0.14)
		vane.mesh = q
		vane.material_override = feather
		vane.rotation = Vector3(PI * 0.5, 0.0, PI * 0.5 * float(k))
		vane.position.z = 0.7
		add_child(vane)
	# A faint streak behind it.
	_trail = MeshInstance3D.new()
	var streak := BoxMesh.new()
	streak.size = Vector3(0.012, 0.012, 1.4)
	_trail.mesh = streak
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.albedo_color = Color(1.0, 0.55, 0.25, 0.35)
	_trail.material_override = tm
	_trail.position.z = 1.1
	add_child(_trail)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_proxy = Proxy.new()
	add_child(_proxy)
	_proxy.top_level = true


## Nose (-Z) along the flight.
func _point() -> void:
	if velocity.length_squared() > 0.0001:
		global_basis = Basis.looking_at(velocity.normalized(), Vector3.UP)


func _physics_process(delta: float) -> void:
	_age += delta
	if _stuck >= 0.0:
		_stuck += delta
		if _stuck > STUCK_LIFE:
			queue_free()
		return
	if _age > LIFE:
		queue_free()
		return
	if _falling:
		velocity += Vector3(0.0, -9.8, 0.0) * delta
	elif reflected and is_instance_valid(shooter) and not shooter.get("_dying"):
		# Back at the archer, turning onto it as it moves.
		var want := (_centre(shooter) - global_position).normalized() * BACK_SPEED
		velocity = velocity.lerp(want, clampf(HOMING * delta, 0.0, 1.0))
	var from := global_position
	var to := from + velocity * delta

	# A player (co-op: either), or (on its way back) the archer.
	for pl in Coop.all():
		var body := pl as Node3D
		if not _falling and not reflected and body.get("_dead") != true and _hits_body(from, to, body):
			global_position = _closest_on(from, to, body)
			_strike_player(body)
			return
	# Credit for a parried arrow goes to whoever is nearest it.
	var player := Coop.nearest(global_position, false) as Node3D
	if reflected and is_instance_valid(shooter) and not shooter.get("_dying") and _hits_body(from, to, shooter):
		shooter.call("take_damage", damage, velocity.normalized())
		var p := player as Node
		if p != null and p.has_signal("hit_landed"):
			p.emit_signal("hit_landed", shooter)
		queue_free()
		return

	# Stone.
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	q.hit_back_faces = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"]
		_point()
		_stuck = 0.0
		_tip_mat.emission_energy_multiplier = 0.4
		_trail.visible = false
		return
	global_position = to
	_point()


func _strike_player(player: Node3D) -> void:
	_proxy.global_position = global_position - Vector3(0.0, 1.3, 0.0)
	_guard_event = null
	var hooked := false
	if player.has_signal("guarded"):
		player.connect("guarded", _on_guarded)
		hooked = true
	player.call("take_damage", damage, velocity.normalized(), _proxy)
	if hooked:
		player.disconnect("guarded", _on_guarded)
	if _guard_event != null and _guard_event[1] == _proxy:
		if _guard_event[0]:
			_turn_back()
		else:
			# Knocked aside by the guard: it spins off and drops.
			_falling = true
			velocity = Vector3(randf_range(-2.0, 2.0), 2.5, randf_range(-2.0, 2.0)) - velocity.normalized() * 2.0
			_trail.visible = false
		return
	# It went home.
	queue_free()


func _on_guarded(parried: bool, attacker: Node3D) -> void:
	_guard_event = [parried, attacker]


## Parried: straight back at whoever loosed it, burning brighter.
func _turn_back() -> void:
	reflected = true
	_age = 0.0
	var at: Vector3 = _centre(shooter) if is_instance_valid(shooter) else global_position - velocity
	velocity = (at - global_position).normalized() * BACK_SPEED
	global_position += velocity.normalized() * 0.5
	_point()
	_tip_mat.emission = Color(0.75, 0.45, 1.0)
	_tip_mat.emission_energy_multiplier = 5.0
	(_trail.material_override as StandardMaterial3D).albedo_color = Color(0.8, 0.55, 1.0, 0.6)


static func _centre(body: Node3D) -> Vector3:
	return body.global_position + Vector3(0.0, (BODY_LOW + BODY_HIGH) * 0.5, 0.0)


func _hits_body(from: Vector3, to: Vector3, body: Node3D) -> bool:
	var a := body.global_position + Vector3(0.0, BODY_LOW, 0.0)
	var b := body.global_position + Vector3(0.0, BODY_HIGH, 0.0)
	var pts := Geometry3D.get_closest_points_between_segments(from, to, a, b)
	return (pts[0] as Vector3).distance_to(pts[1]) < BODY_RADIUS


func _closest_on(from: Vector3, to: Vector3, body: Node3D) -> Vector3:
	var a := body.global_position + Vector3(0.0, BODY_LOW, 0.0)
	var b := body.global_position + Vector3(0.0, BODY_HIGH, 0.0)
	return Geometry3D.get_closest_points_between_segments(from, to, a, b)[0]
