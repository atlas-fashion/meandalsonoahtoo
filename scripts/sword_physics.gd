extends RefCounted

## The sword with weight (note 172): a prototype of a physical layer over the
## captured clips, the way Exanima and Hellish Quart drive their bodies -- the
## animation is the TARGET, not the pose. Owned by first_person_arms.gd.
##
## Each frame the clip (or the sword's own pose) says where the grip should be.
## This carries a simulated sword toward it on two damped springs, in the
## knight's own frame:
## - the hilt, stiff -- the arm carrying it is strong;
## - the blade's turn about the hilt, softer and under-damped -- its mass is out
##   along the blade, so a fast stroke trails a little behind the wrist, swings
##   on past where the clip stops, and settles back (follow-through), all
##   without a frame of it keyed.
## Then the world gets a say:
## - the blade is kept out of the walls: laid against what it meets, the
##   velocity into it turned back (`BOUNCE`), and a hard meeting is a clang
##   (`clang`, read once by the arms);
## - a cut that lands bites: the blade loses part of its swing (`bite`);
## - turning the body leaves a share of the blade's turn behind (`TURN_DRAG`).
## The arm is then bent to hold the sword where this left it (the arms do that),
## so the hand always has it.
##
## `weight` (Graphics.sword_weight, 0..1) scales how loose the springs are; at 0
## the sword is exactly the clip's again.

## (omega rad/s, damping ratio) at full weight; STIFF is the omega at none.
const HILT_SPRING := Vector2(34.0, 0.85)
const BLADE_SPRING := Vector2(17.0, 0.5)
const STIFF := 90.0
## How far the sword may part from the clip: the blade's turn (rad), the hilt (m).
const MAX_LAG := 0.7
const MAX_SLIP := 0.12
## The share of the body's own turn the blade is left behind by, a frame.
const TURN_DRAG := 0.35
## Off a wall: the share of the speed into it that comes back out.
const BOUNCE := 0.3
## The tip's speed into a wall (m/s) that makes a clang.
const CLANG_SPEED := 2.2
## The blade is kept this far off what it meets (m).
const WALL_GAP := 0.03
## A landed cut: the share of the blade's swing it takes out, and the kick back.
const BITE := 0.5
const BITE_KICK := 1.2
## Substep length (s): the springs are stiff.
const STEP := 1.0 / 240.0

var _started := false
## The simulated grip, in the knight's frame (orthonormal, metres): the hilt's
## point and velocity, the grip frame's turn and its angular velocity.
var _p := Vector3.ZERO
var _v := Vector3.ZERO
var _q := Quaternion.IDENTITY
var _w := Vector3.ZERO
var _body_prev := Transform3D.IDENTITY
## A hard meeting with a wall since the arms last asked: the speed (0 none) and
## where (global).
var clang := 0.0
var clang_at := Vector3.ZERO
## Whether the blade lay against something last frame (pressed, not struck).
var _touching := false


func reset() -> void:
	_started = false


## Where the sword is this frame (global grip frame: Z along the blade, X the
## edge), carried toward `target` (global, where the clip has it) for `delta`.
## `body` is the knight's frame (global, orthonormal), `length` the blade from
## the grip to the tip, `world` the physics space, `mask` what stops the blade,
## `exclude` RIDs it passes through, and `anchor` a point the hand reaches out
## from that is never in a wall (the eye).
func step(target: Transform3D, body: Transform3D, delta: float, weight: float, length: float,
		world: PhysicsDirectSpaceState3D, mask: int, exclude: Array[RID], anchor: Vector3) -> Transform3D:
	var to_body := body.affine_inverse()
	var tgt := to_body * target
	var tq := tgt.basis.orthonormalized().get_rotation_quaternion()
	if not _started or delta <= 0.0 or delta > 0.1:
		_started = true
		_p = tgt.origin
		_v = Vector3.ZERO
		_q = tq
		_w = Vector3.ZERO
		_body_prev = body
		return target
	weight = clampf(weight, 0.0, 1.0)
	# The body turned since last frame: a share of the blade's turn stays in
	# the world.
	var turned := (body.basis.inverse() * _body_prev.basis).get_rotation_quaternion()
	_q = (Quaternion.IDENTITY.slerp(turned, TURN_DRAG * weight) * _q).normalized()
	_body_prev = body
	var kp := lerpf(STIFF, HILT_SPRING.x, weight)
	var kr := lerpf(STIFF, BLADE_SPRING.x, weight)
	var zp := HILT_SPRING.y
	var zr := lerpf(1.0, BLADE_SPRING.y, weight)
	var n := clampi(ceili(delta / STEP), 1, 24)
	var dt := delta / float(n)
	for i in n:
		_v += ((tgt.origin - _p) * kp * kp - _v * (2.0 * zp * kp)) * dt
		_p += _v * dt
		_w += (_rot_vec(tq * _q.inverse()) * kr * kr - _w * (2.0 * zr * kr)) * dt
		_q = (_from_vec(_w * dt) * _q).normalized()
	# Never too far from the clip: it is still the stroke.
	var slip := _p - tgt.origin
	if slip.length() > MAX_SLIP:
		_p = tgt.origin + slip.normalized() * MAX_SLIP
		_v *= 0.5
	var lag := tq.angle_to(_q)
	if lag > MAX_LAG:
		_q = tq.slerp(_q, MAX_LAG / lag).normalized()
		_w *= 0.6
	_collide(body, length, world, mask, exclude, anchor)
	return body * Transform3D(Basis(_q), _p)


## The sword kept out of the walls. First the hilt: a ray from `anchor` out to
## it, and where that meets a wall the hilt stops just short (a stroke that
## steps the knight forward would put the whole fist in it). Then the blade: a
## ray up it from the hilt; where it meets something, the blade is turned about
## the hilt until its tip lies just off that surface, and its swing into it is
## turned back.
func _collide(body: Transform3D, length: float, world: PhysicsDirectSpaceState3D, mask: int,
		exclude: Array[RID], anchor: Vector3) -> void:
	var was_touching := _touching
	_touching = false
	if world == null or mask == 0 or length <= WALL_GAP:
		return
	var grip := body * _p
	var stop := _wall_ray(world, anchor, grip, mask, exclude)
	if not stop.is_empty():
		var n0: Vector3 = stop["normal"]
		grip = (stop["position"] as Vector3) + n0 * WALL_GAP * 2.0
		_p = body.affine_inverse() * grip
		var n0_b := body.basis.inverse() * n0
		_v -= n0_b * minf(_v.dot(n0_b), 0.0)
		_touching = true
	var dir_b := Basis(_q).z.normalized()
	var dir := body.basis * dir_b
	var hit := _wall_ray(world, grip, grip + dir * length, mask, exclude)
	if hit.is_empty():
		return
	var nrm: Vector3 = hit["normal"]
	if dir.dot(nrm) >= 0.0:
		return
	_touching = true
	# The hilt's height off the surface, and the blade turned so its tip is
	# WALL_GAP off it, keeping the way it lay along the surface.
	var h := (grip - (hit["position"] as Vector3)).dot(nrm)
	var dn := clampf(-(h - WALL_GAP) / length, -1.0, 0.0)
	var along := dir - nrm * dir.dot(nrm)
	if along.length_squared() < 1e-6:
		along = nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT)
	var want := along.normalized() * sqrt(1.0 - dn * dn) + nrm * dn
	var nrm_b := body.basis.inverse() * nrm
	var want_b := body.basis.inverse() * want
	_q = (_arc(dir_b, want_b) * _q).normalized()
	# The tip's speed into the surface, turned back.
	var tip_v := _w.cross(dir_b * length) + _v
	var into := tip_v.dot(nrm_b)
	if into < 0.0:
		# A strike comes back off it; a blade only pressed to it just stops.
		var struck := -into > CLANG_SPEED and not was_touching
		var dv := -nrm_b * into * (1.0 + (BOUNCE if struck else 0.0))
		var new_dir := Basis(_q).z.normalized()
		_w += new_dir.cross(dv) / length
		if struck and -into > clang:
			clang = -into
			clang_at = hit["position"]


## The first wall between `from` and `to`, or {}. Anything that can be cut is
## passed through: a cut bites instead (`bite`).
static func _wall_ray(world: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int,
		exclude: Array[RID]) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(from, to, mask)
	ray.exclude = exclude.duplicate()
	for tries in 4:
		var hit := world.intersect_ray(ray)
		if hit.is_empty():
			return {}
		var c := hit["collider"] as Object
		var cuttable := c != null and (c.has_method("take_damage") or c.has_method("strike") \
			or (c is CollisionObject3D and ((c as CollisionObject3D).collision_layer & 4) != 0))
		if not cuttable:
			return hit
		var ex := ray.exclude
		ex.append(hit["rid"])
		ray.exclude = ex
	return {}


## A landed cut: the blade loses part of its swing and kicks back a little.
func bite() -> void:
	var swing := _w.length()
	if swing < 0.01:
		return
	_w *= 1.0 - BITE
	_w -= _w.normalized() * minf(BITE_KICK, _w.length())


## A turn as a rotation vector (axis * angle, the short way round).
static func _rot_vec(q: Quaternion) -> Vector3:
	if q.w < 0.0:
		q = -q
	var s := sqrt(maxf(1.0 - q.w * q.w, 0.0))
	if s < 1e-6:
		return Vector3(q.x, q.y, q.z) * 2.0
	return Vector3(q.x, q.y, q.z) / s * (2.0 * acos(clampf(q.w, -1.0, 1.0)))


static func _from_vec(v: Vector3) -> Quaternion:
	var a := v.length()
	if a < 1e-9:
		return Quaternion.IDENTITY
	return Quaternion(v / a, a)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var f := from.normalized()
	var t := to.normalized()
	var d := f.dot(t)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.9999:
		var axis := f.cross(Vector3.UP)
		if axis.length_squared() < 1e-4:
			axis = f.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	var c := f.cross(t)
	return Quaternion(c.x, c.y, c.z, 1.0 + d).normalized()
