extends StaticBody3D

## A living root tip (note 176): the end of one of the gold-veined roots grown
## down a wall (ruin_roots.gd), still alive. It hangs off the stone writhing
## slowly; when someone passes within `notice` metres in front of it, it draws
## back, shivering and glowing brighter (the tell, with a parry cue in it), and
## lashes at them. Any blow kills it -- sword, spear, a thrown spear's blast, its
## own lash parried back -- and its glow goes out, it shrivels and greys and
## hangs limp from the wall. When the last living tip grown from a root mesh
## dies, that mesh's gold fades too (`cluster`).
##
## The tip is one tube bent along a cubic Bezier in root_tip.gdshader; this script
## only moves the three control points, each on its own damped spring, so the
## end lags the base and the lash cracks like a whip. Its own frame: x along the
## wall, y up, z out of the wall; the curve starts at the base (the strand's end).
##
## A StaticBody3D on the damageable layer (4) only, so blows find it and nothing
## walks into it. Its origin sits 0.9 m under and 0.35 m out from the base: the
## player's line-of-sight test aims 0.9 m over a body's origin, and that point
## must be clear of the wall.

const Roots := preload("res://scripts/ruin_roots.gd")

enum State { REST, COIL, LASH, RECOVER, DYING, DEAD }

## The base, from this body's origin.
const TIP_AT := Vector3(0.0, 0.9, -0.35)
## The tell: drawn back and shivering this long before it lashes.
const COIL_TIME := 0.5
## From the start of the lash, how long it can still connect.
const LASH_TIME := 0.24
const RECOVER_TIME := 0.75
## Between lashes (random in this range).
const COOLDOWN := Vector2(1.5, 2.6)
## The parry window opens this long before the lash begins, and lasts LISTEN.
const CUE_LEAD := 0.17
const LISTEN := 0.3
## Asleep beyond this from every player (no animation, no checks but this one).
const AWAKE_RANGE := 18.0
## How close the lashing end must pass to the body's axis to land.
const HIT_RADIUS := 0.5

@export var length := 1.45
@export var notice := 2.8
@export var damage := 12.0

## The root mesh it grows from (ruin_dressing.gd); its `life` follows its tips.
var cluster: GeometryInstance3D = null

var _tip: MeshInstance3D
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _state := State.REST
var _t := 0.0
var _cool := 0.0
var _c: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _v: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _goal: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _stiff := Vector3(40.0, 30.0, 22.0)
var _damp := 0.6
var _target := Vector3.ZERO
var _victim: Node3D = null
var _cued := false
var _landed := false
var _glow := 1.0
var _wilt := 0.0
var _phase := 0.0
var _check := 0.0
var _awake := false
var _rng := RandomNumberGenerator.new()


## A tip at `base` (world) on a wall whose face looks along `out`, `r0` thick at
## the base like the strand it grows from.
static func make(base: Vector3, out: Vector3, r0: float, seed_: int) -> StaticBody3D:
	var n: StaticBody3D = load("res://scripts/living_root.gd").new()
	n.name = "LivingRoot"
	var z := Vector3(out.x, 0.0, out.z).normalized()
	var basis := Basis(Vector3.UP.cross(z), Vector3.UP, z)
	n.transform = Transform3D(basis, base - basis * TIP_AT)
	n.set_meta("r0", r0)
	n.set_meta("seed", seed_)
	return n


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group("living_root")
	_rng.seed = int(get_meta("seed", 1))
	_phase = _rng.randf() * 100.0
	length *= _rng.randf_range(0.85, 1.15)
	_cool = _rng.randf_range(0.0, 1.0)
	_tip = MeshInstance3D.new()
	_tip.name = "Tip"
	_tip.mesh = Roots.tip_mesh(snappedf(length, 0.05), float(get_meta("r0", 0.06)))
	_tip.position = TIP_AT
	_tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tip.custom_aabb = AABB(Vector3(-2.5, -2.5, -0.6), Vector3(5.0, 5.0, 3.4))
	_tip.visibility_range_end = 45.0
	add_child(_tip)
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.2
	_capsule.height = 1.0
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	add_child(_shape)
	_rest_goals(0.0)
	for i in 3:
		_c[i] = _goal[i]
	_push()


## The hanging pose: on down from the strand, curling out from the wall, the
## end hooked a little up. Writhes slowly with `_phase`.
func _rest_goals(writhe: float) -> void:
	var l := length
	var w := _phase
	_goal[0] = Vector3(0.02, -0.28, 0.14) * l + Vector3(sin(w * 0.9), 0.0, cos(w * 0.7)) * 0.03 * writhe
	_goal[1] = Vector3(0.12, -0.55, 0.42) * l + Vector3(sin(w * 1.1), sin(w * 0.6) * 0.5, cos(w * 0.85)) * 0.09 * writhe
	_goal[2] = Vector3(0.04, -0.42, 0.78) * l + Vector3(sin(w * 1.3 + 1.0), sin(w * 0.9) * 0.8, cos(w * 1.05)) * 0.16 * writhe


## Drawn back up the wall and over, away from where it will strike.
func _coil_goals(shiver: float) -> void:
	var l := length
	var f := Vector3(_target.x, 0.0, _target.z)
	f = f.normalized() if f.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
	var s := Vector3(sin(_phase * 41.0), sin(_phase * 37.0), cos(_phase * 43.0)) * 0.025 * shiver
	_goal[0] = f * 0.12 * l + Vector3(0.0, 0.12, 0.08) * l
	_goal[1] = f * 0.02 * l + Vector3(0.0, 0.5, 0.22) * l + s
	_goal[2] = -f * 0.22 * l + Vector3(0.0, 0.42, 0.18) * l + s * 2.0


func _lash_goals() -> void:
	var l := length
	_goal[0] = _target.normalized() * 0.3 * l + Vector3(0.0, 0.06, 0.1) * l
	_goal[1] = _target * 0.62 + Vector3(0.0, 0.22, 0.0) * l
	_goal[2] = _target


## Limp: straight down the wall, close to it.
func _dead_goals() -> void:
	var l := length
	_goal[0] = Vector3(0.02, -0.3, 0.1) * l
	_goal[1] = Vector3(0.05, -0.62, 0.11) * l
	_goal[2] = Vector3(0.02, -0.9, 0.06) * l


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.25
		_awake = _state == State.DYING or _nearest(AWAKE_RANGE) != null
	if not _awake:
		return
	_phase += delta
	_t += delta
	match _state:
		State.REST:
			_rest_goals(1.0)
			_cool -= delta
			if _cool <= 0.0:
				var p := _nearest(notice + 1.2)
				if p != null and _can_reach(p):
					_victim = p
					_target = _aim_at(p)
					_enter(State.COIL)
		State.COIL:
			_coil_goals(clampf(_t / COIL_TIME, 0.2, 1.0))
			_glow = lerpf(1.0, 2.6, clampf(_t / COIL_TIME, 0.0, 1.0))
			# Keeps aiming while it draws back.
			if _victim != null and is_instance_valid(_victim):
				_target = _target.lerp(_aim_at(_victim), clampf(delta * 6.0, 0.0, 1.0))
			if not _cued and _t >= COIL_TIME - CUE_LEAD:
				_cued = true
				if _victim != null and is_instance_valid(_victim) and _victim.has_method("parry_cue"):
					_victim.call("parry_cue", self, LISTEN)
			if _t >= COIL_TIME:
				_enter(State.LASH)
		State.LASH:
			_lash_goals()
			_glow = lerpf(_glow, 1.4, clampf(delta * 8.0, 0.0, 1.0))
			if not _landed and _t > 0.05:
				_try_land()
			if _t >= LASH_TIME:
				_enter(State.RECOVER)
		State.RECOVER:
			_rest_goals(_t / RECOVER_TIME)
			_glow = lerpf(_glow, 1.0, clampf(delta * 4.0, 0.0, 1.0))
			if _t >= RECOVER_TIME:
				_cool = _rng.randf_range(COOLDOWN.x, COOLDOWN.y)
				_enter(State.REST)
		State.DYING:
			_dead_goals()
			_glow = maxf(_glow - delta * 2.2, 0.0)
			_wilt = minf(_wilt + delta / 1.8, 1.0)
			if _t > 3.5:
				_state = State.DEAD
	_springs(delta)
	_push()


func _enter(s: State) -> void:
	_state = s
	_t = 0.0
	match s:
		State.COIL:
			_cued = false
			_stiff = Vector3(70.0, 55.0, 45.0)
			_damp = 0.75
		State.LASH:
			_landed = false
			# The end slower than the base: it trails, then cracks through.
			_stiff = Vector3(1100.0, 700.0, 420.0)
			_damp = 0.5
		State.RECOVER:
			_stiff = Vector3(60.0, 45.0, 32.0)
			_damp = 0.45
		State.REST:
			_stiff = Vector3(40.0, 30.0, 22.0)
			_damp = 0.6
		State.DYING:
			_stiff = Vector3(14.0, 10.0, 7.0)
			_damp = 0.55


## Each control point on its own spring toward its goal.
func _springs(delta: float) -> void:
	var steps := 1 if _state != State.LASH else 3
	var dt := minf(delta, 0.05) / float(steps)
	for _s in steps:
		for i in 3:
			var k := _stiff[i]
			var a := (_goal[i] - _c[i]) * k - _v[i] * (2.0 * _damp * sqrt(k))
			if _state == State.DYING:
				a += Vector3(0.0, -2.5, 0.0)
			_v[i] += a * dt
			_c[i] += _v[i] * dt


func _push() -> void:
	_tip.set_instance_shader_parameter("p1", _c[0])
	_tip.set_instance_shader_parameter("p2", _c[1])
	_tip.set_instance_shader_parameter("p3", _c[2])
	_tip.set_instance_shader_parameter("glow", _glow)
	_tip.set_instance_shader_parameter("wilt", _wilt)
	# The body to hit: from the base to the middle of the curve.
	if not _shape.disabled:
		var a := TIP_AT
		var b := TIP_AT + _bezier(0.6)
		var mid := (a + b) * 0.5
		var along := b - a
		var len_ := along.length()
		_capsule.height = maxf(len_ + _capsule.radius * 2.0, _capsule.radius * 2.0 + 0.01)
		if len_ > 0.01:
			var y := along / len_
			var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
			_shape.transform = Transform3D(Basis(x, y, x.cross(y)), mid)


func _bezier(t: float) -> Vector3:
	var it := 1.0 - t
	return 3.0 * it * it * t * _c[0] + 3.0 * it * t * t * _c[1] + t * t * t * _c[2]


## The nearest player within `range_`, or null. Hidden, dead or in a scene: not seen.
func _nearest(range_: float) -> Node3D:
	var best: Node3D = null
	var best_d := range_ * range_
	for p in Coop.all():
		var body := p as Node3D
		if body == null or not is_instance_valid(body):
			continue
		if body.has_method("is_hidden") and body.call("is_hidden"):
			continue
		if body.get("_dead") == true or body.get("in_cutscene") == true:
			continue
		var d := body.global_position.distance_squared_to(_base_world())
		if d < best_d:
			best_d = d
			best = body
	return best


func _base_world() -> Vector3:
	return global_transform * TIP_AT


## In front of the wall and within reach of its lash.
func _can_reach(p: Node3D) -> bool:
	var to := p.global_position + Vector3(0.0, 1.1, 0.0) - _base_world()
	var local := global_basis.inverse() * to
	if local.z < 0.25:
		return false
	return Vector2(to.x, to.z).length() <= notice


## Where to strike `p` in the tip's own frame: their chest, pulled in to its reach.
func _aim_at(p: Node3D) -> Vector3:
	var chest := p.global_position + Vector3(0.0, 1.15, 0.0)
	var local := global_basis.inverse() * (chest - _base_world())
	var reach := length * 1.08
	if local.length() > reach:
		local = local.normalized() * reach
	local.z = maxf(local.z, 0.25)
	return local


## The lash's end against the body it was aimed at: from the curve's middle to
## its end, against the player's upright axis.
func _try_land() -> void:
	if _victim == null or not is_instance_valid(_victim):
		return
	var xf := global_transform * Transform3D(Basis(), TIP_AT)
	var a := xf * _bezier(0.55)
	var b := xf * _c[2]
	var feet := _victim.global_position
	var pts := Geometry3D.get_closest_points_between_segments(a, b,
		feet + Vector3(0.0, 0.35, 0.0), feet + Vector3(0.0, 1.75, 0.0))
	if (pts[0] as Vector3).distance_to(pts[1]) > HIT_RADIUS:
		return
	_landed = true
	var blow := feet - _base_world()
	blow.y = 0.0
	blow = blow.normalized() if blow.length_squared() > 0.0001 else -global_basis.z
	if _victim.has_method("take_damage"):
		_victim.call("take_damage", damage, blow, self)


## A parried or blocked lash, a door's shove: thrown back off what it hit.
func apply_knockback(impulse: Vector3, _stun := 0.0) -> void:
	if _state == State.DYING or _state == State.DEAD:
		return
	var local := global_basis.inverse() * impulse
	for i in 3:
		_v[i] += local.normalized() * (2.0 + float(i) * 2.5)
	if _state == State.LASH or _state == State.COIL:
		_enter(State.RECOVER)


## Any blow kills it.
func take_damage(_amount: float, from_direction := Vector3.ZERO, _attacker: Node = null) -> void:
	if _state == State.DYING or _state == State.DEAD:
		return
	# Thrown off by the blow first, so it falls the way it was struck.
	var local := global_basis.inverse() * from_direction
	for i in 3:
		_v[i] += local * (3.0 + float(i) * 3.0)
	_enter(State.DYING)
	_glow = 3.2
	_awake = true
	_shape.set_deferred("disabled", true)
	remove_from_group("living_root")
	_burst()
	if cluster != null and is_instance_valid(cluster):
		var alive := int(cluster.get_meta("alive", 1)) - 1
		cluster.set_meta("alive", alive)
		if alive <= 0:
			var c := cluster
			var tw := c.create_tween()
			tw.tween_method(func(v: float) -> void:
				if is_instance_valid(c):
					c.set_instance_shader_parameter("life", v)
					c.set_instance_shader_parameter("rot", (1.0 - v) * 0.35), 1.0, 0.0, 2.8)


func is_alive() -> bool:
	return _state != State.DYING and _state != State.DEAD


## Its gold going out: a puff of motes off it, and bark chips (with effects).
func _burst() -> void:
	var gfx := get_node_or_null("/root/Graphics")
	if gfx != null and not bool(gfx.get("effects")):
		return
	var at := global_transform * (TIP_AT + _bezier(0.5))
	var motes := CPUParticles3D.new()
	motes.one_shot = true
	motes.emitting = false
	motes.amount = 26
	motes.lifetime = 1.4
	motes.explosiveness = 0.85
	motes.lifetime_randomness = 0.5
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.35
	motes.direction = Vector3.UP
	motes.spread = 180.0
	motes.initial_velocity_min = 0.3
	motes.initial_velocity_max = 1.4
	motes.gravity = Vector3(0.0, 0.25, 0.0)
	motes.damping_min = 0.8
	motes.damping_max = 1.6
	motes.scale_amount_min = 0.4
	motes.scale_amount_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 0.55, 0.15, 0.0))
	motes.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(2.2, 1.5, 0.6)
	quad.material = m
	motes.mesh = quad
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent := get_parent()
	parent.add_child(motes)
	motes.global_position = at
	motes.restart()
	get_tree().create_timer(2.0).timeout.connect(motes.queue_free)
	var chips := CPUParticles3D.new()
	chips.one_shot = true
	chips.emitting = false
	chips.amount = 14
	chips.lifetime = 1.0
	chips.explosiveness = 1.0
	chips.direction = Vector3.UP
	chips.spread = 75.0
	chips.initial_velocity_min = 1.5
	chips.initial_velocity_max = 3.5
	chips.gravity = Vector3(0.0, -12.0, 0.0)
	chips.angular_velocity_min = -540.0
	chips.angular_velocity_max = 540.0
	chips.scale_amount_min = 0.5
	chips.scale_amount_max = 1.2
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.012, 0.02)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.16, 0.12, 0.09)
	bm.roughness = 0.9
	box.material = bm
	chips.mesh = box
	parent.add_child(chips)
	chips.global_position = at
	chips.restart()
	get_tree().create_timer(1.6).timeout.connect(chips.queue_free)
