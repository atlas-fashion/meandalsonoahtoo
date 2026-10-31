extends Node3D

## The skeleton's sword (2026-10-10): every ordinary skeleton (enemy.gd with
## `armed`) carries one in its right hand, and the SWORD is what hurts the
## player -- a blow lands only where the blade, swept from where it was last tick
## to where it is now, actually passes through them (`strike`). Step out of its
## path and the swing misses, however close the skeleton is.
##
## The rig has no sword clips, so the right arm is posed in code over the body's
## own clip (the archer's trick): a two-bone reach to a hand target along a curve
## per move, the hand bone turned along the blade. NORMAL is a diagonal cut from
## high on its sword side down across; the charge (SLAM) an overhead chop; LUNGE
## a thrust; SPIN the arm held out while the body turns. Out of a fight the
## blade follows the forearm, carried point forward and down.
##
## The miners carry a pick instead (`kind` &"pick"): the same arm, the same
## swings, a different head on the haft.
##
## Posed only on ticks the rig was actually advanced (`stepped`): the arm is
## blended onto the clip's pose, and re-applied to its own result the blend
## would compound.
##
## PROSTHESES (2026-10-20, prosthetic.gd; note 93): `kind` &"drill" or &"hammer"
## is not held but IS the hand -- the hand bone is
## shrunk to nothing (the rig's clips carry no scale tracks, so it stays so) and
## the tool is strapped to the wrist in an iron cuff, carried along the forearm
## and turned only part way toward the swing (`PROSTHESIS_TURN`). The drill's
## bit spins, fast while it attacks. The sword hand has a rig of its own now
## (sword_skeleton.gd, note 135); sword_skeleton_blade.gd keeps only `strike`.

const BLADE_FROM := 0.1
const BLADE_TO := 1.0
const PICK_TO := 0.82
## The drill's bit and the hammer's head, from the wrist.
const DRILL_TO := 0.62
const HAMMER_TO := 0.86
## How far a prosthesis turns from the forearm toward the swing's blade line.
const PROSTHESIS_TURN := 0.45
const PROSTHESES := [&"drill", &"hammer"]
## The drill's bit, radians a second: idling, and while it attacks.
const BIT_IDLE := 7.0
const BIT_FAST := 46.0
## The player as a capsule: radius, and its axis from the feet.
const BODY_RADIUS := 0.42
const BODY_LOW := 0.25
const BODY_HIGH := 1.55
const SEEN := 45.0

var enemy: CharacterBody3D
var kind := &"sword"
var _sk: Skeleton3D
var _upper := -1
var _fore := -1
var _hand := -1
var _len_upper := 0.3
var _len_fore := 0.3
var _side := 1.0
var _model: MeshInstance3D
## The blade's hilt and tip last tick, world space, for the swept test.
var _prev: Array = []
var _dropped := false
var _placed := false
## The drill's spinning bit, and its spin rate now.
var _bit: MeshInstance3D
var _bit_rate := BIT_IDLE

static var _meshes := {}


func is_prosthesis() -> bool:
	return kind in PROSTHESES


## Hangs a weapon in the right hand of the rig under `e`. Null if there is no
## rig with a right arm.
static func arm(e: CharacterBody3D, weapon := &"sword") -> Node3D:
	var found := e.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var upper := sk.find_bone("upper_arm.R")
	var fore := sk.find_bone("forearm.R")
	var hand := sk.find_bone("hand.R")
	if upper < 0 or fore < 0 or hand < 0:
		return null
	var s: Node3D = load("res://scripts/skeleton_sword.gd").new()
	s.name = String(weapon).capitalize()
	if weapon in PROSTHESES:
		# The tool replaces the hand: the hand (fingers folded in) shrinks into
		# the wrist, inside the cuff.
		sk.set_bone_pose_scale(hand, Vector3.ONE * 0.02)
	s.set("enemy", e)
	s.set("kind", weapon)
	s.set("_sk", sk)
	s.set("_upper", upper)
	s.set("_fore", fore)
	s.set("_hand", hand)
	e.add_child(s)
	return s


func _ready() -> void:
	var a := _sk.get_bone_global_rest(_upper).origin
	var b := _sk.get_bone_global_rest(_fore).origin
	var c := _sk.get_bone_global_rest(_hand).origin
	_len_upper = a.distance_to(b)
	_len_fore = b.distance_to(c)
	_model = MeshInstance3D.new()
	_model.mesh = _mesh(kind)
	_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_model.visibility_range_end = SEEN
	_model.visibility_range_end_margin = 4.0
	add_child(_model)
	if kind == &"drill":
		_bit = MeshInstance3D.new()
		_bit.name = "Bit"
		_bit.mesh = drill_bit_mesh()
		_bit.position = Vector3(0.0, DRILL_BIT_AT, 0.0)
		_bit.visibility_range_end = SEEN
		_bit.visibility_range_end_margin = 4.0
		_model.add_child(_bit)


func reach() -> float:
	match kind:
		&"pick":
			return PICK_TO
		&"drill":
			return DRILL_TO
		&"hammer":
			return HAMMER_TO
	return BLADE_TO


## The hammer's head is wide: the player is struck by it a little further off
## the haft's line than by a blade.
func _strike_radius() -> float:
	return BODY_RADIUS + (0.12 if kind == &"hammer" else 0.0)


# --- Per tick ------------------------------------------------------------------------

## What the skeleton is doing, as enemy.gd tells `update`.
enum Phase { NONE, WINDUP, ATTACK, RECOVER }
enum Move { CUT, CHOP, THRUST, SPIN, SWEEP }


## Called by enemy.gd every physics tick after the rig is advanced: `phase` and
## `move` what it is doing and `p` how far through it (0..1); `stepped` whether
## the rig moved this tick.
func update(stepped: bool, phase: int, move: int, p: float) -> void:
	if _dropped or _sk == null:
		return
	if _bit != null:
		# Spun up through the wind-up, flat out while it attacks.
		var want := BIT_IDLE
		if phase == Phase.WINDUP:
			want = lerpf(BIT_IDLE, BIT_FAST, p)
		elif phase == Phase.ATTACK:
			want = BIT_FAST
		_bit_rate = move_toward(_bit_rate, want, get_physics_process_delta_time() * 120.0)
		_bit.rotation.y = wrapf(_bit.rotation.y + _bit_rate * get_physics_process_delta_time(), 0.0, TAU)
	# A child of the body, so between rig steps it is carried along as it is;
	# only a step of the rig (or a fight, where the rig steps every tick) moves
	# the hand. Far-off skeletons step rarely and cost nearly nothing here.
	if _placed and not stepped and phase == Phase.NONE and enemy.get("hauled_by") == null:
		return
	_placed = true
	var shoulder := _sk.global_transform * _sk.get_bone_global_pose(_upper).origin
	var local_sh := enemy.global_transform.affine_inverse() * shoulder
	_side = 1.0 if local_sh.x >= 0.0 else -1.0
	var key := _key(shoulder, phase, move, p)
	var w: float = key[0]
	if enemy.get("hauled_by") != null:
		_at_belt()
		return
	if stepped and w > 0.001:
		_reach_for(shoulder, key[1], key[2], w)
	var hand := _sk.global_transform * _sk.get_bone_global_pose(_hand).origin
	var elbow := _sk.global_transform * _sk.get_bone_global_pose(_fore).origin
	var fwd := _forward()
	var forearm := (hand - elbow).normalized()
	if is_prosthesis():
		# Strapped to the wrist: along the forearm, bent a little forward at
		# rest and only part way onto the swing's line in a fight.
		var rest := (forearm + fwd * 0.9).normalized()
		var swung := forearm.slerp(key[2], PROSTHESIS_TURN).normalized()
		_place(hand, rest.slerp(swung, w).normalized() if w > 0.0 else rest)
		return
	var carried := (forearm + fwd * 1.1).normalized()
	var dir: Vector3 = carried.slerp(key[2], w).normalized() if w > 0.0 else carried
	_place(hand, dir)


## The weapon's hilt and tip, world space.
func blade() -> Array:
	var y := global_basis.y.normalized()
	return [global_position + y * BLADE_FROM, global_position + y * reach()]


## Swept test against the player for this tick. True if the blade passed
## through them since the last tick.
func strike(player: Node3D) -> bool:
	var now := blade()
	var before: Array = _prev if not _prev.is_empty() else now
	_prev = now
	var a := player.global_position + Vector3(0.0, BODY_LOW, 0.0)
	var b := player.global_position + Vector3(0.0, BODY_HIGH, 0.0)
	for i in 5:
		var t := float(i) / 4.0
		var h: Vector3 = (before[0] as Vector3).lerp(now[0], t)
		var p: Vector3 = (before[1] as Vector3).lerp(now[1], t)
		var pts := Geometry3D.get_closest_points_between_segments(h, p, a, b)
		if (pts[0] as Vector3).distance_to(pts[1]) < _strike_radius():
			return true
	return false


## Forget the last tick's blade (a new swing starts its sweep where it is).
func clear_sweep() -> void:
	_prev = blade()


## Falls out of a dead hand and lies on the floor.
func drop() -> void:
	if _dropped:
		return
	_dropped = true
	# Let go of the body: it falls where it was, not with the corpse.
	var held := global_transform
	top_level = true
	global_transform = held
	var floor_y := enemy.global_position.y + 0.03
	var flat := _forward().rotated(Vector3.UP, randf_range(-1.2, 1.2))
	# Lying flat: the blade along `flat`, its flat face up.
	var y := flat
	var z := Vector3.UP
	var x := y.cross(z).normalized()
	var to := Transform3D(Basis(x, y, z), Vector3(global_position.x, floor_y, global_position.z))
	var t := create_tween()
	t.tween_property(self, "global_transform", to, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


# --- Poses ---------------------------------------------------------------------------

func _forward() -> Vector3:
	var f := -enemy.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 1e-4 else Vector3.FORWARD


## [weight, hand target, blade direction] for what the skeleton is doing now.
func _key(shoulder: Vector3, phase: int, move: int, p: float) -> Array:
	var f := _forward()
	# From the body out to the sword arm's side.
	var r := f.cross(Vector3.UP).normalized()
	if (shoulder - enemy.global_position).dot(r) < 0.0:
		r = -r
	var u := Vector3.UP
	var raised := _raised(move, shoulder, f, r, u)
	match phase:
		Phase.WINDUP:
			return [smoothstep(0.0, 0.45, p), raised[0], raised[1]]
		Phase.ATTACK:
			var at := _swung(move, p, shoulder, f, r, u, raised)
			return [1.0, at[0], at[1]]
		Phase.RECOVER:
			var at := _swung(move, 1.0, shoulder, f, r, u, raised)
			return [1.0 - smoothstep(0.0, 1.0, p), at[0], at[1]]
	return [0.0, shoulder, f]


## The wind-up's end: where the hand is raised to before the move.
func _raised(k: int, s: Vector3, f: Vector3, r: Vector3, u: Vector3) -> Array:
	match k:
		Move.CHOP:
			return [s + u * 0.5 + r * 0.06 - f * 0.05, (u * 0.55 - f * 0.85).normalized()]
		Move.THRUST:
			return [s + r * 0.12 - f * 0.22 - u * 0.08, (f - u * 0.05).normalized()]
		Move.SPIN:
			return [s + r * 0.45 + u * 0.08, (r * 0.6 + f * 0.5).normalized()]
		Move.SWEEP:
			# Drawn far back on its own side at chest height, the blade
			# trailing behind: the whole width of the front to come.
			return [s + r * 0.42 - f * 0.18 - u * 0.04, (r * 0.75 - f * 0.6 + u * 0.08).normalized()]
	return [s + r * 0.22 + u * 0.42 - f * 0.08, (u * 0.75 - f * 0.45 + r * 0.35).normalized()]


## Where the move has carried the hand and blade at `p` (0..1) of the attack.
func _swung(k: int, p: float, s: Vector3, f: Vector3, r: Vector3, u: Vector3, raised: Array) -> Array:
	if k == Move.CHOP:
		var c := clampf(p / 0.4, 0.0, 1.0)
		c = c * c * (3.0 - 2.0 * c)
		var hand := _bezier(raised[0], s + f * 0.45 + u * 0.45, s + f * 0.6 - u * 0.3, c)
		return [hand, _sweep(raised[1], f, (f * 0.8 - u * 0.6).normalized(), c)]
	if k == Move.THRUST:
		var c := clampf(p / 0.25, 0.0, 1.0)
		c = 1.0 - (1.0 - c) * (1.0 - c)
		return [(raised[0] as Vector3).lerp(s + f * 0.62, c), (f - u * 0.05).normalized()]
	if k == Move.SPIN:
		return [s + r * 0.55 + f * 0.15, (r * 0.9 + f * 0.3).normalized()]
	if k == Move.SWEEP:
		# Flat across the front, through the middle fast, held out at the far
		# side at the end.
		var c := clampf(p / 0.6, 0.0, 1.0)
		c = c * c * (3.0 - 2.0 * c)
		var hand := _bezier(raised[0], s + f * 0.68 - u * 0.06, s - r * 0.5 + f * 0.32 - u * 0.1, c)
		return [hand, _sweep(raised[1], (f - u * 0.05).normalized(), (-r * 0.85 + f * 0.4 - u * 0.1).normalized(), c)]
	# The cut: fast through the middle, held at the end.
	var c := clampf(p / 0.75, 0.0, 1.0)
	c = c * c * (3.0 - 2.0 * c)
	var hand := _bezier(raised[0], s + f * 0.75 + u * 0.2 + r * 0.15, s - r * 0.45 - u * 0.38 + f * 0.35, c)
	return [hand, _sweep(raised[1], (f - u * 0.1).normalized(), (f * 0.6 - r * 0.65 - u * 0.45).normalized(), c)]


static func _bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


static func _sweep(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	if t < 0.5:
		return a.slerp(b, t * 2.0).normalized()
	return b.slerp(c, t * 2.0 - 1.0).normalized()


## Two bones reaching for `hand_at`, the elbow down and out, then the hand turned
## along the blade; blended over the clip by `w`.
func _reach_for(shoulder: Vector3, hand_at: Vector3, blade_dir: Vector3, w: float) -> void:
	var to_sk := _sk.global_transform.affine_inverse()
	var s := to_sk * shoulder
	var h := to_sk * hand_at
	var d := h - s
	var dist := clampf(d.length(), absf(_len_upper - _len_fore) + 0.01, (_len_upper + _len_fore) * 0.985)
	var dir := d.normalized() if d.length_squared() > 1e-6 else Vector3.DOWN
	var pole_w := (enemy.global_basis.x * _side * 0.6 + Vector3.DOWN + enemy.global_basis.z * 0.4)
	var pole := (to_sk.basis * pole_w).normalized()
	pole = (pole - dir * pole.dot(dir))
	if pole.length_squared() < 1e-6:
		pole = Vector3.DOWN - dir * dir.y
	pole = pole.normalized()
	var a := (_len_upper * _len_upper - _len_fore * _len_fore + dist * dist) / (2.0 * dist)
	var hgt := sqrt(maxf(_len_upper * _len_upper - a * a, 0.0))
	var elbow := s + dir * a + pole * hgt
	_point(_upper, elbow - s, w)
	var e_now := _sk.get_bone_global_pose(_fore).origin
	_point(_fore, (s + dir * dist) - e_now, w)
	# A prosthesis has no hand to turn (and `_point` would undo its shrinking).
	if not is_prosthesis():
		_point(_hand, (to_sk.basis * blade_dir).normalized(), w)


func _point(bone: int, dir: Vector3, w: float) -> void:
	if dir.length_squared() < 1e-8:
		return
	var pose := _sk.get_bone_global_pose(bone)
	var basis := pose.basis.orthonormalized()
	var turned := Basis(Quaternion(basis.y.normalized(), dir.normalized())) * basis
	pose.basis = basis.slerp(turned.orthonormalized(), w)
	_sk.set_bone_global_pose(bone, pose)


func _place(hand: Vector3, dir: Vector3) -> void:
	var y := dir.normalized()
	var ref := _forward() if absf(y.dot(_forward())) < 0.95 else Vector3.UP
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	transform = enemy.global_transform.affine_inverse() * Transform3D(Basis(x, y, z), hand + y * 0.02)


## Hauling a cart: the sword hangs at the belt, point down and back.
func _at_belt() -> void:
	var f := _forward()
	var r := f.cross(Vector3.UP).normalized()
	if is_prosthesis():
		# It cannot be put away: carried at the wrist, pointed up out of the
		# way of the cart.
		var wrist := _sk.global_transform * _sk.get_bone_global_pose(_hand).origin
		_place(wrist, (Vector3.UP * 0.85 + f * 0.35).normalized())
		return
	var y := (-Vector3.UP * 0.9 - f * 0.45).normalized()
	var x := r
	var z := x.cross(y).normalized()
	transform = enemy.global_transform.affine_inverse() * Transform3D(Basis(x, y, z),
		enemy.global_position + Vector3.UP * 0.95 - r * 0.22 + f * 0.05)


# --- The model -------------------------------------------------------------------

## Along +Y from the grip at the origin, one surface per material, built once.
static func _mesh(weapon: StringName) -> ArrayMesh:
	if _meshes.has(weapon):
		return _meshes[weapon]
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.4, 0.38, 0.35)
	iron.metallic = 0.35
	iron.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.18, 0.16)
	dark.metallic = 0.3
	dark.roughness = 0.6
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.16, 0.1, 0.06)
	leather.roughness = 0.9
	var tools := {}
	var add := func(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(mesh, 0, xf)
	if weapon == &"pick":
		var haft := CylinderMesh.new()
		haft.top_radius = 0.018
		haft.bottom_radius = 0.022
		haft.height = 0.85
		haft.radial_segments = 6
		haft.rings = 1
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.3, 0.21, 0.13)
		wood.roughness = 0.85
		add.call(haft, Transform3D(Basis(), Vector3(0.0, 0.33, 0.0)), wood)
		# The head: two tapering spikes across the top of the haft.
		for s: float in [-1.0, 1.0]:
			var spike := CylinderMesh.new()
			spike.top_radius = 0.004
			spike.bottom_radius = 0.032
			spike.height = 0.26
			spike.radial_segments = 6
			spike.rings = 1
			add.call(spike, Transform3D(Basis(Vector3.BACK, -s * PI * 0.5) * Basis(Vector3.BACK, s * 0.22),
				Vector3(s * 0.13, 0.74, 0.0)), iron)
		var eye := BoxMesh.new()
		eye.size = Vector3(0.07, 0.08, 0.06)
		add.call(eye, Transform3D(Basis(), Vector3(0.0, 0.75, 0.0)), dark)
	elif weapon in PROSTHESES:
		_cuff(add, dark, leather)
		if weapon == &"drill":
			# The motor housing; the bit (`drill_bit_mesh`) is a node of its
			# own so it can spin.
			var housing := CylinderMesh.new()
			housing.top_radius = 0.058
			housing.bottom_radius = 0.05
			housing.height = 0.16
			housing.radial_segments = 8
			housing.rings = 1
			add.call(housing, Transform3D(Basis(), Vector3(0.0, 0.2, 0.0)), iron)
			for k in 3:
				var fin := BoxMesh.new()
				fin.size = Vector3(0.13, 0.012, 0.13)
				add.call(fin, Transform3D(Basis(), Vector3(0.0, 0.15 + 0.035 * float(k), 0.0)), dark)
			var collar := CylinderMesh.new()
			collar.top_radius = 0.03
			collar.bottom_radius = 0.045
			collar.height = 0.04
			collar.radial_segments = 8
			collar.rings = 1
			add.call(collar, Transform3D(Basis(), Vector3(0.0, DRILL_BIT_AT - 0.01, 0.0)), dark)
		else:
			# A short haft out of the cuff and a great block of a head.
			var haft := CylinderMesh.new()
			haft.top_radius = 0.026
			haft.bottom_radius = 0.03
			haft.height = 0.64
			haft.radial_segments = 6
			haft.rings = 1
			add.call(haft, Transform3D(Basis(), Vector3(0.0, 0.44, 0.0)), dark)
			var head := BoxMesh.new()
			head.size = Vector3(0.4, 0.2, 0.2)
			add.call(head, Transform3D(Basis(), Vector3(0.0, HAMMER_TO - 0.06, 0.0)), iron)
			for s: float in [-1.0, 1.0]:
				var face := BoxMesh.new()
				face.size = Vector3(0.05, 0.24, 0.24)
				add.call(face, Transform3D(Basis(), Vector3(s * 0.205, HAMMER_TO - 0.06, 0.0)), dark)
	else:
		# Blade: a flattened, tapering box with a point.
		var blade := CylinderMesh.new()
		blade.top_radius = 0.022
		blade.bottom_radius = 0.034
		blade.height = BLADE_TO - BLADE_FROM - 0.08
		blade.radial_segments = 4
		blade.rings = 1
		var flat := Basis().scaled(Vector3(1.0, 1.0, 0.22))
		add.call(blade, Transform3D(flat, Vector3(0.0, (BLADE_FROM + BLADE_TO - 0.08) * 0.5, 0.0)), iron)
		var point := CylinderMesh.new()
		point.top_radius = 0.0
		point.bottom_radius = 0.022
		point.height = 0.1
		point.radial_segments = 4
		point.rings = 1
		add.call(point, Transform3D(flat, Vector3(0.0, BLADE_TO - 0.04, 0.0)), iron)
		var guard := BoxMesh.new()
		guard.size = Vector3(0.22, 0.03, 0.04)
		add.call(guard, Transform3D(Basis(), Vector3(0.0, 0.08, 0.0)), dark)
		var grip := CylinderMesh.new()
		grip.top_radius = 0.016
		grip.bottom_radius = 0.016
		grip.height = 0.16
		grip.radial_segments = 6
		grip.rings = 1
		add.call(grip, Transform3D(Basis(), Vector3.ZERO), leather)
		var pommel := SphereMesh.new()
		pommel.radius = 0.028
		pommel.height = 0.05
		pommel.radial_segments = 6
		pommel.rings = 3
		add.call(pommel, Transform3D(Basis(), Vector3(0.0, -0.1, 0.0)), dark)
	var am := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.generate_normals()
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	_meshes[weapon] = am
	return am


## Where the drill's bit starts, from the wrist.
const DRILL_BIT_AT := 0.3


## The iron cuff a prosthesis is strapped to the wrist with, around the origin
## (the wrist), and its two leather straps.
static func _cuff(add: Callable, dark: Material, leather: Material) -> void:
	var cuff := CylinderMesh.new()
	cuff.top_radius = 0.05
	cuff.bottom_radius = 0.045
	cuff.height = 0.15
	cuff.radial_segments = 8
	cuff.rings = 1
	add.call(cuff, Transform3D(Basis(), Vector3(0.0, 0.035, 0.0)), dark)
	for y: float in [-0.02, 0.07]:
		var strap := CylinderMesh.new()
		strap.top_radius = 0.054
		strap.bottom_radius = 0.054
		strap.height = 0.022
		strap.radial_segments = 8
		strap.rings = 1
		add.call(strap, Transform3D(Basis(), Vector3(0.0, y, 0.0)), leather)


## The drill's bit along +Y from its base: a fluted cone, built once.
static func drill_bit_mesh() -> ArrayMesh:
	if _meshes.has(&"drill_bit"):
		return _meshes[&"drill_bit"]
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.53, 0.5)
	steel.metallic = 0.6
	steel.roughness = 0.35
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := DRILL_TO - DRILL_BIT_AT
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.04
	cone.height = length
	cone.radial_segments = 8
	cone.rings = 1
	st.append_from(cone, 0, Transform3D(Basis(), Vector3(0.0, length * 0.5, 0.0)))
	# The flutes: thin blades wound round the cone.
	for k in 6:
		var t := (float(k) + 0.5) / 6.0
		var flute := BoxMesh.new()
		flute.size = Vector3(0.012, 0.075, 0.09 * (1.0 - t) + 0.015)
		var turn := Basis(Vector3.UP, float(k) * 1.9) * Basis(Vector3.RIGHT, 0.55)
		st.append_from(flute, 0, Transform3D(turn, Vector3(0.0, length * t, 0.0)))
	st.generate_normals()
	var am := st.commit()
	am.surface_set_material(0, steel)
	_meshes[&"drill_bit"] = am
	return am
