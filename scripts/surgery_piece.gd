extends Node3D

## A PIECE the surgery's claw throws (2026-10-25, note 104; surgical_table.gd
## FETCH): one of the gold mechanical arms (the kit's `prosthetic`, a
## Higgsfield piece) fished out of a vat and thrown in an arc at a player. The
## user: "If it hits the player, the player should get knocked down and should
## take 30 damage. It should be parriable, knocking the piece flying away from
## the player's front. If the piece hits the claw, it should knock it back, and
## make it go limp for 4 seconds. The piece ... should also be blockable, for
## reduced damage."
##
## The hit goes through `player.take_damage(DAMAGE, travel, proxy)` like an
## arrow's (arrow.gd): the guard sees it as any blow.
##   * unguarded: DAMAGE, and knocked down (`knock_down`);
##   * BLOCKED: BLOCK_SHARE of it, on their feet; it clangs aside and drops;
##   * PARRIED: nothing, and it flies off the front of the blade, the way they
##     are looking, at PARRY_SPEED (ASSIST draws it onto the claw if it is
##     nearly that way) -- and if it hits the claw, the claw is knocked back
##     and limp (`struck_by_piece`).
## Stone, a vat or the floor stops it: it clatters down and lies there a while.
## The player and the claw are tested as capsules, segment to segment.

const SCALE := 2.4
const DAMAGE := 30.0
const BLOCK_SHARE := 0.3
const GRAVITY := 14.0
## Its flight to where it is thrown takes about this long per metre, within
## FLIGHT.
const PER_M := 0.075
const FLIGHT := Vector2(0.55, 1.15)
const PARRY_SPEED := 24.0
## Parried, it flies on this long before it falls.
const PARRY_FLY := 1.2
const LIFE := 5.0
const REST_LIFE := 6.0
## Stone, the vats (layer 2) and the exact walls.
const WORLD_MASK := 2 | 256
## A body, as a capsule.
const BODY_LOW := 0.2
const BODY_HIGH := 1.6
const BODY_RADIUS := 0.5
## The claw, as a capsule round its wrist-to-fingertips.
const CLAW_RADIUS := 0.85
const KNOCK_PUSH := 7.0
## Parried within this many degrees of the claw, it goes into the claw.
const ASSIST := 22.0

var thrower: Node3D
var velocity := Vector3.ZERO
var reflected := false
## Who parried it (credit; and it never hits them on the way out).
var _by: Node3D = null

var _age := 0.0
var _fly := 0.0
var _rest := -1.0
var _falling := false
var _spin := Vector3.ZERO
var _proxy: Node3D
var _guard_event = null
var _model: Node3D
var _trail: CPUParticles3D


## What the player's guard sees as the attacker: the flash goes 1.3 m over an
## attacker's origin, so this sits 1.3 m under the piece; it takes no shove and
## no reflected damage (the piece itself is what comes back); a block lets
## BLOCK_SHARE through.
class Proxy extends Node3D:
	var block_damage_share := BLOCK_SHARE

	func apply_knockback(_impulse: Vector3, _stun := 0.0) -> void:
		pass

	func take_damage(_amount: float, _from := Vector3.ZERO, _attacker: Node3D = null) -> void:
		pass


## Thrown from `from` to land on `at` (world), by `by` (the table).
static func fire(parent: Node, from: Vector3, at: Vector3, by: Node3D) -> Node3D:
	var p := Node3D.new()
	p.set_script(load("res://scripts/surgery_piece.gd"))
	p.name = "SurgeryPiece"
	parent.add_child(p)
	p.global_position = from
	p.set("thrower", by)
	var d := at - from
	var t := clampf(Vector2(d.x, d.z).length() * PER_M, FLIGHT.x, FLIGHT.y)
	# The arc that arrives at `at` in t: v = d / t + g t / 2 (g down).
	p.set("velocity", d / t + Vector3(0.0, GRAVITY * t * 0.5, 0.0))
	return p


func _ready() -> void:
	top_level = true
	_model = (load("res://scripts/surgery.gd").K["prosthetic"] as PackedScene).instantiate()
	var table_script = load("res://scripts/surgical_table.gd")
	table_script.grade(_model)
	# Glowing a little in its own gold, so it is seen coming in the dark.
	table_script.glow(_model, 0.6)
	add_child(_model)
	_model.scale = Vector3.ONE * SCALE
	_model.position = Vector3(0.0, 0.4, 0.0)
	for g in _model.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_spin = Vector3(randf_range(6.0, 9.0), randf_range(-3.0, 3.0), randf_range(2.0, 4.0))
	_proxy = Proxy.new()
	add_child(_proxy)
	_proxy.top_level = true
	# Drops of oil off it as it flies.
	if Graphics.effects:
		_trail = CPUParticles3D.new()
		_trail.amount = 16
		_trail.lifetime = 0.5
		_trail.local_coords = false
		_trail.direction = Vector3.DOWN
		_trail.spread = 30.0
		_trail.initial_velocity_min = 0.2
		_trail.initial_velocity_max = 0.6
		_trail.gravity = Vector3(0.0, -9.0, 0.0)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.03, 0.03)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_color = Color(1.0, 0.62, 0.28)
		quad.material = m
		_trail.mesh = quad
		add_child(_trail)


func _physics_process(delta: float) -> void:
	_age += delta
	if _rest >= 0.0:
		_rest += delta
		if _rest > REST_LIFE:
			queue_free()
		return
	if _age > LIFE:
		queue_free()
		return
	if reflected and not _falling:
		_fly += delta
		if _fly > PARRY_FLY:
			_falling = true
	if not reflected or _falling:
		velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	rotation += _spin * delta

	# A player (co-op: either) -- not on its way back.
	if not reflected and not _falling:
		for pl in Coop.all():
			var body := pl as Node3D
			if body.get("_dead") != true and _hits_body(from, to, body):
				global_position = _closest_on(from, to, body)
				_strike_player(body)
				return
	# Turned back: the claw.
	if reflected and not _falling and is_instance_valid(thrower) and thrower.has_method("claw_segment") \
			and not bool(thrower.call("is_depowered")):
		var seg: Array = thrower.call("claw_segment")
		var pts := Geometry3D.get_closest_points_between_segments(from, to, seg[0], seg[1])
		if (pts[0] as Vector3).distance_to(pts[1]) < CLAW_RADIUS:
			global_position = pts[0]
			thrower.call("struck_by_piece", global_position, velocity.normalized())
			if _by != null and is_instance_valid(_by) and _by.has_signal("hit_landed"):
				_by.emit_signal("hit_landed", thrower)
			_clang(Color(0.75, 0.45, 1.0), 26)
			_drop()
			return

	# Stone, a vat, the floor.
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	q.hit_back_faces = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = hit["position"] + (hit["normal"] as Vector3) * 0.08
		var n: Vector3 = hit["normal"]
		if n.y > 0.6 and velocity.length() < 5.0:
			_settle()
			return
		# A clatter: off it, slower, and falling.
		_clang(Color(1.0, 0.75, 0.4), 8)
		velocity = velocity.bounce(n) * 0.35
		_falling = true
		reflected = false
		return
	global_position = to


func _strike_player(player: Node3D) -> void:
	_proxy.global_position = global_position - Vector3(0.0, 1.3, 0.0)
	_guard_event = null
	var hooked := false
	if player.has_signal("guarded"):
		player.connect("guarded", _on_guarded)
		hooked = true
	var dir := velocity
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else -player.global_basis.z
	player.call("take_damage", DAMAGE, dir, _proxy)
	if hooked:
		player.disconnect("guarded", _on_guarded)
	if _guard_event != null and _guard_event[1] == _proxy:
		if _guard_event[0]:
			_turn_back(player)
		else:
			# Blocked: it clangs off the blade and drops.
			_clang(Color(1.0, 0.75, 0.4), 10)
			velocity = Vector3(randf_range(-2.0, 2.0), 3.0, randf_range(-2.0, 2.0)) - dir * 2.5
			_falling = true
		return
	# It landed: they go down.
	if player.has_method("knock_down") and player.get("_dead") != true:
		player.call("knock_down", dir, KNOCK_PUSH)
	velocity = -dir * 1.5 + Vector3(0.0, 2.0, 0.0)
	_falling = true


func _on_guarded(parried: bool, attacker: Node3D) -> void:
	_guard_event = [parried, attacker]


## Parried: away off the front of the blade -- straight ahead of them, flat --
## burning purple.
func _turn_back(player: Node3D) -> void:
	reflected = true
	_by = player
	_fly = 0.0
	_age = 0.0
	# Where they are looking (the claw hangs 4-5 m up: look up at it and it goes
	# there), drawn the last little way onto the claw if it is that near the
	# line (ASSIST).
	var cam: Camera3D = Coop.camera(player) if Coop.camera(player) != null else player.get("camera")
	var ahead := -cam.global_basis.z if cam != null else -player.global_basis.z
	ahead = ahead.normalized()
	if is_instance_valid(thrower) and thrower.has_method("claw_segment"):
		var seg: Array = thrower.call("claw_segment")
		var mid: Vector3 = ((seg[0] as Vector3) + (seg[1] as Vector3)) * 0.5
		var to := (mid - global_position).normalized()
		if ahead.angle_to(to) < deg_to_rad(ASSIST):
			ahead = to
	velocity = ahead * PARRY_SPEED
	global_position += ahead * 0.6
	_spin *= 2.0
	if _trail != null:
		(_trail.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = Color(0.75, 0.45, 1.0)
	_clang(Color(0.75, 0.45, 1.0), 18)


## Down on the floor where it lies.
func _settle() -> void:
	_rest = 0.0
	velocity = Vector3.ZERO
	rotation = Vector3(0.0, rotation.y, PI * 0.5)
	if _trail != null:
		_trail.emitting = false
	_clang(Color(1.0, 0.7, 0.35), 6)


func _drop() -> void:
	_falling = true
	reflected = false
	velocity = Vector3(randf_range(-1.5, 1.5), 1.0, randf_range(-1.5, 1.5))


func _clang(colour: Color, amount: int) -> void:
	if is_instance_valid(thrower) and thrower.has_method("_sparks"):
		thrower.call("_sparks", global_position, colour, amount)


func _hits_body(from: Vector3, to: Vector3, body: Node3D) -> bool:
	var a := body.global_position + Vector3(0.0, BODY_LOW, 0.0)
	var b := body.global_position + Vector3(0.0, BODY_HIGH, 0.0)
	var pts := Geometry3D.get_closest_points_between_segments(from, to, a, b)
	return (pts[0] as Vector3).distance_to(pts[1]) < BODY_RADIUS


func _closest_on(from: Vector3, to: Vector3, body: Node3D) -> Vector3:
	var a := body.global_position + Vector3(0.0, BODY_LOW, 0.0)
	var b := body.global_position + Vector3(0.0, BODY_HIGH, 0.0)
	return Geometry3D.get_closest_points_between_segments(from, to, a, b)[0]
