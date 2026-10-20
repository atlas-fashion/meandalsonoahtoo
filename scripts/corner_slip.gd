extends RefCounted

## Walking bodies slip round corners instead of sticking on them (2026-10-20,
## docs/notes/92-no-sticking-to-corners.md).
##
## The brick kit's stone steps out of the wall line at every archway and
## junction: an arch leg 0.21 m proud of the wall face, a junction pillar 0.35
## m. A body walking along a wall and leaning into it (as anyone steering by
## hand does) meets that step square on in the crease, and move_and_slide has
## nothing left to slide along -- it stops dead. A path cutting a junction
## corner stops the same way on a pillar's corner.
##
## `slide(body)` is move_and_slide, then: if the body made almost none of the
## headway it asked for, it works out the way it is really trying to go (along
## any wall it was leaning on), finds what blocks THAT, and looks sideways --
## a few offsets each way, up to the widest SIDE_STEPS -- for the nearest spot
## from which the way on is clear, and steps toward it at walking pace. A short
## step frees a crease or a corner; a whole wall is wider than SIDE_STEPS, so
## walking straight into one still just stops. Another walker in the way is a
## crowd, not a corner, and is left alone.

## Below this fraction of the asked-for speed made good along its heading, the
## body counts as stuck.
const STUCK := 0.35
## Sideways offsets tried, nearest first. The largest is the widest step a
## body will slip round: a pillar's 0.35 m plus some.
const SIDE_STEPS: Array[float] = [0.06, 0.12, 0.2, 0.3, 0.42, 0.55]
## Probes are lifted off the floor, so resting on it never reads as blocked.
const LIFT := 0.08
## A wall met at least this square (normal against the way) is what stopped
## the body; anything shallower is a wall it can slide along.
const SQUARE := -0.6


static func slide(body: CharacterBody3D) -> void:
	var want := Vector3(body.velocity.x, 0.0, body.velocity.z)
	body.move_and_slide()
	var speed := want.length()
	if speed < 0.5:
		return
	var fwd := want / speed
	var real := body.get_real_velocity()
	if real.x * fwd.x + real.z * fwd.z > speed * STUCK:
		return
	# The way on: the heading, turned along each wall it was leaning on as it
	# moved -- and below, along each it glances off -- until something stands
	# square across it (or nothing does).
	var way := fwd
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		if c.get_collider() is CharacterBody3D:
			return
		var wn := c.get_normal()
		wn.y = 0.0
		if wn.length_squared() < 0.01:
			continue
		wn = wn.normalized()
		var into := way.dot(wn)
		if into < 0.0 and into > SQUARE:
			way -= wn * into
	if way.length() < 0.2:
		return
	way = way.normalized()
	var delta := body.get_physics_process_delta_time()
	var step := speed * delta
	var reach := maxf(step * 2.0, 0.15)
	var from := body.global_transform
	from.origin.y += LIFT
	var hit := KinematicCollision3D.new()
	var blocked := false
	var clear := false
	for _i in 3:
		if not body.test_move(from, way * reach, hit):
			clear = true
			break
		if hit.get_collider() is CharacterBody3D:
			return
		var n := hit.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.01:
			return
		n = n.normalized()
		if n.dot(way) <= SQUARE:
			blocked = true
			break
		way -= n * way.dot(n)
		if way.length() < 0.2:
			return
		way = way.normalized()
	if clear:
		# Nothing in the way off the floor, yet move_and_slide stood still: a
		# capsule pressed onto a pillar's edge can sink a hair into the floor
		# and jam there (measured: every move reports the floor, travel 0).
		# Walk on from the lifted spot; floor snap and gravity set it down.
		body.global_position = from.origin + way * step
		return
	if not blocked:
		return
	var side := Vector3(-way.z, 0.0, way.x)
	for off: float in SIDE_STEPS:
		for s: float in [1.0, -1.0]:
			var shift := side * (s * off)
			if body.test_move(from, shift):
				continue
			var there := from
			there.origin += shift
			if body.test_move(there, way * reach):
				continue
			body.global_position += side * (s * minf(off, step))
			return
