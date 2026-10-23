extends Node3D

## The surgery's SECOND CLAW, the beam claw (2026-10-23, note 101). The user:
## "Make more than one claw. The other claw should be a beam of blue like the
## enforcer that slows you down, giving the other claw time to catch up to you.
## The player should still be able to dodge the claw, so the beam should stop
## before the claw crashes down to get the player."
##
## It rides the same gantry as the grabbing claw (surgical_table.gd), on a second
## girder along the bridge BEAM_RAIL_Z out from the first -- a double-girder
## crane with a trolley on each -- so it moves with the bridge along the hall and
## on its own along the bridge, and the two trolleys pass each other without
## touching. Its arm telescopes out at an angle, reaching the head over to one
## side of whoever the grabbing claw is after, where it has a clear line down to
## them past the bookshelves (`_choose_spot`).
##
## THE BEAM: while the grabbing claw hunts and is coming up on its next slam
## (`BEAM_LEAD` before it may), the claw charges -- its fingers whiten blue -- and
## fires the enforcer's beam (the same colours, core and glow; player.gd
## `beam_hit`: slowed to `beam_slow`, a little hurt). It holds them in it so the
## other claw can close in, and CUTS OFF the moment that claw begins its slam
## (State.REAR): the slow lingers player.gd BEAM_LINGER (0.35 s), shorter than
## the slam's WIND (0.35 s) -- so they are back at full speed for all of TRACK,
## LOCK and DROP, the window in which the slam can be dodged.
##
## Everything else follows the table: asleep it is drawn up and parked; awake
## it pays out; switched off it falls with the other. Its pieces are the
## Higgsfield claw, segment and ring (models/surgery/) -- no new model -- the
## claw lit blue instead of red.

const Table := preload("res://scripts/surgical_table.gd")
const CLAW_MODEL := preload("res://models/surgery/claw.glb")
const RING_MODEL := preload("res://models/surgery/ring.glb")

## The second girder: this far along +Z from the bridge's middle (room frame).
## The trolleys (ring 3.4 m at TROLLEY_SCALE 0.5 and BEAM_TROLLEY 0.28) clear
## each other passing: 0.85 + 0.48 < 1.4.
const BEAM_RAIL_Z := Table.BEAM_GIRDER_Z
const BEAM_TROLLEY := 0.28
## The arm's root under its trolley; the claw smaller than the grabbing one.
const BEAM_ROOT_Y := 6.5
const BEAM_CLAW_SCALE := 0.72
const CLAW_LEN := 1.55 * BEAM_CLAW_SCALE / Table.CLAW_SCALE
## The head: the wrist this high (its fingertips clear the 3.9 m shelves),
## this far from whoever it is after (two rings of spots), and at most this
## far out from under its rail (the arm's reach along Z).
const WRIST_Y := 5.6
const SPOT_NEAR := 1.4
const SPOT_FAR := 2.4
const REACH_Z := 2.8
## Never this near the grabbing claw's wrist (across the floor), and the head
## always at least SIDE_MARGIN on its own rail's side (+Z) of it -- its arm
## running out along Z from the rail then never crosses the other's.
const KEEP_OFF := 1.4
const SIDE_MARGIN := 1.35
## The head's drive: top speed (m/s) and acceleration.
const HEAD_SPEED := 7.5
const HEAD_ACCEL := 24.0
## The trolley's drive along the bridge.
const TROLLEY_SPEED := 7.0
const TROLLEY_ACCEL := 10.0
## Asleep: parked this far along the bridge, drawn up.
const PARK_X := 3.5
const FOLD_LEN := 0.3

## The beam: it may start this long before the other claw may slam; charges
## CHARGE_TIME; fires at most BEAM_TIME; rests BEAM_REST after. BEAM_DPS a second
## (player.gd `beam_hit` also slows them). Out to BEAM_RANGE.
const BEAM_LEAD := 2.0
const CHARGE_TIME := 0.7
const BEAM_TIME := 3.2
const BEAM_REST := 2.2
const BEAM_DPS := 3.0
const BEAM_RANGE := 14.0
## Its line blocked this long while firing, and it gives up.
const LOST_LINE := 0.5
## Drawn ending this short of the player (as the enforcer's: a beam drawn all
## the way into the eye fills the view).
const SHORT_OF_PLAYER := 0.5
## The enforcer's crystal colours.
const CRYSTAL := Color(0.0, 0.91, 1.0)
const HOT := Color(0.75, 0.97, 1.0)

enum Beam { IDLE, CHARGE, FIRE }

var table: CharacterBody3D

var beam: Beam = Beam.IDLE
var _phase_t := 0.0
var _ready_at := 0.0
var _lost_at := -1.0
var _beam_end := Vector3.ZERO
var _beam_on_player := false

## Room frame: the trolley along the bridge and its speed; the wrist, its
## velocity and where it is going; the way the claw points.
var _x := PARK_X
var _xv := 0.0
var _w := Vector3(PARK_X, BEAM_ROOT_Y - FOLD_LEN, BEAM_RAIL_Z)
var _wv := Vector3.ZERO
var _w_goal := Vector3.ZERO
var _aim := Vector3.DOWN
## The head's spot, from their chest (kept relative: they and the bridge move).
var _spot := Vector3.INF
var _next_spot := 0.0
var _fell := false
## When the beam was last on (the table waits BEAM_CLEAR after it to slam).
var last_fired := -INF
## The bridge where it was last tick (the head is carried with it).
var _last_bz := 0.0
## Laid down by a save: put on whatever is under it on the first tick.
var _settle := false

var _ring: Node3D
var _claw: Node3D
var _segs: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _beam_root: Node3D
var _spans: Array[Node3D] = []
var _beam_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _flare: MeshInstance3D
var _beam_light: OmniLight3D


func setup(table_: CharacterBody3D, seg_mesh: Mesh) -> void:
	table = table_
	_ring = RING_MODEL.instantiate()
	_ring.name = "BeamTrolley"
	_ring.top_level = true
	add_child(_ring)
	Table._shadows(_ring)
	for i in Table.SEG_MAX:
		var seg := MeshInstance3D.new()
		seg.name = "BeamArm%d" % i
		seg.mesh = seg_mesh
		seg.top_level = true
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(seg)
		Table.grade(seg)
		_segs.append(seg)
	_claw = Node3D.new()
	_claw.name = "BeamClaw"
	_claw.top_level = true
	add_child(_claw)
	var model: Node3D = CLAW_MODEL.instantiate()
	model.scale = Vector3.ONE * BEAM_CLAW_SCALE
	_claw.add_child(model)
	Table._shadows(model)
	_mats = _own_glow(model)
	# Its own light, cold blue: the way it is seen coming.
	_light = OmniLight3D.new()
	_light.name = "BeamClawLight"
	_light.light_color = CRYSTAL
	_light.omni_range = 4.0
	_light.omni_attenuation = 1.3
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, -0.6, 0.0)
	_claw.add_child(_light)
	var box := Table.ClawHitbox.new()
	box.name = "BeamClawHitbox"
	box.set("table", table)
	box.collision_layer = 4
	box.collision_mask = 0
	box.position = Vector3(0.0, -0.8, 0.0)
	_claw.add_child(box)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.6, 0.8, 0.6)
	shape.shape = b
	box.add_child(shape)
	_build_beam()
	sleep()


## Its own copies of the claw's materials, lit with their own pictures, so its
## blue never touches the grabbing claw's red (surgical_table.gd `glow` shares
## its materials between copies).
func _own_glow(model: Node) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var m := src.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			m.emission = CRYSTAL
			m.emission_texture = src.albedo_texture
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			m.emission_energy_multiplier = 0.0
			mi.set_surface_override_material(i, m)
			out.append(m)
	return out


## The enforcer's beam (enforcer.gd `_build_beam`): an additive core and glow,
## open tubes along -Z, a flare where it lands.
func _build_beam() -> void:
	_beam_root = Node3D.new()
	_beam_root.name = "Beam"
	_beam_root.top_level = true
	_beam_root.visible = false
	add_child(_beam_root)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_color = Color(HOT, 0.95)
	_glow_mat = _beam_mat.duplicate()
	_glow_mat.albedo_color = Color(CRYSTAL, 0.26)
	for spec: Array in [[0.035, 0.012, 6, _beam_mat], [0.11, 0.02, 8, _glow_mat]]:
		var mi := MeshInstance3D.new()
		var tube := CylinderMesh.new()
		tube.top_radius = spec[0]
		tube.bottom_radius = spec[1]
		tube.height = 1.0
		tube.radial_segments = spec[2]
		tube.rings = 1
		tube.cap_top = false
		tube.cap_bottom = false
		mi.mesh = tube
		mi.material_override = spec[3]
		mi.rotation.x = PI * 0.5
		mi.position.z = -0.5
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var holder := Node3D.new()
		holder.add_child(mi)
		_beam_root.add_child(holder)
		_spans.append(holder)
	_flare = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	s.radial_segments = 10
	s.rings = 5
	_flare.mesh = s
	_flare.material_override = _glow_mat
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_root.add_child(_flare)


# --- States (the table's) ------------------------------------------------------------

## Asleep (or reset): parked along the bridge, drawn up under its trolley.
func sleep() -> void:
	_cancel()
	_fell = false
	_x = PARK_X
	_xv = 0.0
	_w = Vector3(PARK_X, BEAM_ROOT_Y - FOLD_LEN, BEAM_RAIL_Z)
	_wv = Vector3.ZERO
	_aim = Vector3.DOWN
	_spot = Vector3.INF
	_last_bz = float(table.get("_b").y) if table != null else 0.0


## A save with the machine off: lying on the floor under its trolley.
func lie_dead() -> void:
	_cancel()
	_fell = true
	var z: float = table.get("_b").y + BEAM_RAIL_Z
	_w = Vector3(_x, CLAW_LEN * 0.9, z + 0.4)
	_wv = Vector3.ZERO
	_aim = Vector3(0.3, -1.0, 0.2).normalized()
	_settle = true


## The other claw is about to slam: the beam off now.
func cut() -> void:
	_cancel()


func is_firing() -> bool:
	return beam == Beam.FIRE


func _cancel() -> void:
	if beam != Beam.IDLE:
		_ready_at = _now() + BEAM_REST
	beam = Beam.IDLE
	if _beam_root != null:
		_beam_root.visible = false
	if _beam_light != null:
		_beam_light.visible = false


# --- Each tick (called by the table after its own) -------------------------------------

func tick(delta: float) -> void:
	var now := _now()
	var room: Node3D = table.get("room")
	var st: int = table.get("state")
	var b: Vector2 = table.get("_b")
	var rail_z := b.y + BEAM_RAIL_Z
	# The head rides on its arm: carried with the bridge (and, in `_drive_x`,
	# with its trolley); its own drive only reaches it out.
	if not _fell and st != Table.State.DYING:
		_w.z += b.y - _last_bz
	_last_bz = b.y
	var lim: float = float(table.get("rail_x")) - 0.4
	match st:
		Table.State.DORMANT:
			_cancel()
			_drive_x(PARK_X, delta, lim)
			_head_to(Vector3(_x, BEAM_ROOT_Y - FOLD_LEN, rail_z), delta, 3.0)
		Table.State.WAKING:
			_cancel()
			_drive_x(PARK_X, delta, lim)
			var t: float = table.get("_t")
			var k := clampf((t - 1.6) / 1.2, 0.0, 1.0)
			_head_to(Vector3(_x, lerpf(BEAM_ROOT_Y - FOLD_LEN, WRIST_Y, k), rail_z), delta, 2.0)
		Table.State.HUNT, Table.State.REAR:
			_hunt(delta, now, room, st, rail_z, lim)
		Table.State.CARRY, Table.State.STRAP:
			# Something in the other claw: it stands off, watching over the table.
			_cancel()
			_drive_x(clampf(2.6, -lim, lim), delta, lim)
			_head_to(_keep_off(Vector3(_x, WRIST_Y, rail_z - 0.6)), delta, HEAD_SPEED)
			_aim_at((Vector3(0.0, Table.TOP, 0.0) - _w).normalized(), delta, 2.0)
		Table.State.DYING:
			_cancel()
			_fall(delta, room)
		_:
			_cancel()
			if _settle:
				_settle = false
				_settle_on_what_is_under(room)


## Posed every frame, as the other claw is (surgical_table.gd `_process`).
func _process(_delta: float) -> void:
	if table == null or table.get("room") == null:
		return
	_draw(_now(), table.get("room"))


## Hunting: a spot by whoever the other claw is after with a clear line to them,
## and the beam when the other claw is coming up on its slam.
func _hunt(delta: float, now: float, room: Node3D, st: int, rail_z: float, lim: float) -> void:
	var target := table.get("_target") as Node3D
	if target == null or not is_instance_valid(target) or target.get("_dead") == true:
		_cancel()
		_drive_x(clampf(PARK_X, -lim, lim), delta, lim)
		_head_to(_keep_off(Vector3(_x, WRIST_Y, rail_z)), delta, HEAD_SPEED)
		_aim_at(Vector3.DOWN, delta, 2.0)
		return
	var chest: Vector3 = room.to_local(target.global_position) + Vector3(0.0, 1.05, 0.0)
	if now >= _next_spot or _spot == Vector3.INF:
		_next_spot = now + 0.2
		var at := _choose_spot(room, target, chest, rail_z, lim)
		_spot = at - chest
	var goal := Vector3(chest.x + _spot.x, WRIST_Y, chest.z + _spot.z)
	goal.z = clampf(goal.z, rail_z - REACH_Z, rail_z + REACH_Z)
	goal = _keep_off(goal)
	_drive_x(goal.x, delta, lim)
	_head_to(goal, delta, HEAD_SPEED)
	_aim_at((chest - _muzzle_local()).normalized(), delta, 6.0)
	# The beam: only while the other claw HUNTS -- the moment it begins its slam
	# the beam is off, so the player has their full speed to dodge it.
	if st != Table.State.HUNT:
		_cancel()
		return
	var next_rear: float = table.get("_next_rear")
	match beam:
		Beam.IDLE:
			if now >= _ready_at and next_rear - now <= BEAM_LEAD \
					and _muzzle_local().distance_to(chest) <= BEAM_RANGE \
					and _clear(room, target, room.to_global(_muzzle_local()), target.global_position + Vector3(0.0, 1.05, 0.0)):
				beam = Beam.CHARGE
				_phase_t = now
		Beam.CHARGE:
			if now - _phase_t >= CHARGE_TIME:
				beam = Beam.FIRE
				_phase_t = now
				_lost_at = -1.0
		Beam.FIRE:
			_fire(delta, now, room, target)


## `goal` kept off the other claw as it is now (it moves; the spot was chosen
## up to 0.2 s ago): on the rail's side of it, and out of KEEP_OFF round it.
func _keep_off(goal: Vector3) -> Vector3:
	var grab: Vector3 = table.get("_w")
	var lim: float = float(table.get("rail_x")) - 0.4
	# Never into the far wall; against it, when there is no room on the rail's
	# side of the other claw, it stands aside along the bridge instead.
	var zmax: float = float(table.get("bound")) - 0.3
	goal.z = minf(maxf(goal.z, grab.z + SIDE_MARGIN), zmax)
	var dz := goal.z - grab.z
	if Vector2(goal.x - grab.x, dz).length() < KEEP_OFF:
		var side := signf(goal.x - grab.x) if absf(goal.x - grab.x) > 0.01 else 1.0
		var out := sqrt(maxf(KEEP_OFF * KEEP_OFF - dz * dz, 0.0))
		goal.x = grab.x + side * out
		if absf(goal.x) > lim:
			goal.x = grab.x - side * out
	return goal


## A spot for the head: from two rings round them, the nearest to where it is
## that it can reach from its rail, keeps clear of the other claw and has a clear
## line from its muzzle to their chest. None clear: the nearest it can reach.
func _choose_spot(room: Node3D, target: Node3D, chest: Vector3, rail_z: float, lim: float) -> Vector3:
	var grab: Vector3 = table.get("_w")
	var bound: float = float(table.get("bound")) - 0.3
	var to := target.global_position + Vector3(0.0, 1.05, 0.0)
	var best := Vector3.INF
	var best_d := INF
	var fallback := Vector3.INF
	var fallback_d := INF
	for r: float in [SPOT_NEAR, SPOT_FAR]:
		for i in 8:
			var a := float(i) * TAU / 8.0
			var p := Vector3(chest.x + cos(a) * r, WRIST_Y, chest.z + sin(a) * r)
			if absf(p.x) > lim or absf(p.z) > bound or absf(p.z - rail_z) > REACH_Z:
				continue
			if Vector2(p.x - grab.x, p.z - grab.z).length() < KEEP_OFF:
				continue
			# Its arm runs along Z from its rail out to the head: never across the
			# other claw's arm, so the head stays on its rail's side of it.
			if p.z < grab.z + SIDE_MARGIN:
				continue
			var d := p.distance_to(_w) + r * 0.5
			if d < fallback_d:
				fallback_d = d
				fallback = p
			if d >= best_d:
				continue
			var muzzle := p + (chest - p).normalized() * CLAW_LEN * 0.75
			if _clear(room, target, room.to_global(muzzle), to):
				best_d = d
				best = p
	if best != Vector3.INF:
		return best
	if fallback != Vector3.INF:
		return fallback
	return Vector3(clampf(chest.x + SPOT_NEAR, -lim, lim), WRIST_Y, rail_z)


## Nothing solid between `from` and `to` (world) but the target.
func _clear(room: Node3D, target: Node3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	if target is CollisionObject3D:
		q.exclude = [(target as CollisionObject3D).get_rid()]
	var hit := room.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty()


func _fire(delta: float, now: float, room: Node3D, target: Node3D) -> void:
	var from := room.to_global(_muzzle_local())
	var chest := target.global_position + Vector3(0.0, 1.05, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, chest, 1)
	if target is CollisionObject3D:
		q.exclude = [(target as CollisionObject3D).get_rid()]
	var hit := room.get_world_3d().direct_space_state.intersect_ray(q)
	last_fired = now
	if hit.is_empty():
		_lost_at = -1.0
		_beam_end = chest
		_beam_on_player = true
		if target.has_method("beam_hit"):
			target.call("beam_hit", BEAM_DPS, delta, (chest - from).normalized())
	else:
		# Into a shelf: it burns there, and gives up if it stays blocked.
		_beam_end = hit.position
		_beam_on_player = false
		if _lost_at < 0.0:
			_lost_at = now
	if now - _phase_t >= BEAM_TIME or (_lost_at >= 0.0 and now - _lost_at > LOST_LINE):
		_cancel()


## Switched off: the hoist slack, the head drops and crashes into the floor.
func _fall(delta: float, room: Node3D) -> void:
	_drive_x(_x + _xv * 0.3, delta, float(table.get("rail_x")) - 0.4)
	if _fell:
		return
	_wv.y -= 14.0 * delta
	_wv.x *= 0.98
	_wv.z *= 0.98
	_w += _wv * delta
	_aim = _aim.lerp(Vector3(0.3, -1.0, 0.2).normalized(), clampf(delta * 3.0, 0.0, 1.0)).normalized()
	# It comes down on whatever is under it -- the floor, or a bookcase's top.
	var under := _under(room)
	if _w.y <= under + CLAW_LEN * 0.9:
		_w.y = under + CLAW_LEN * 0.9
		_wv = Vector3.ZERO
		_fell = true
		table.call("_impact_fx", room.to_global(Vector3(_w.x, under, _w.z)), 0.6)


## The height (room frame) of whatever solid is under the head: the floor, or
## a bookcase's top.
func _under(room: Node3D) -> float:
	var from := room.to_global(Vector3(_w.x, maxf(_w.y, 5.0), _w.z))
	var q := PhysicsRayQueryParameters3D.create(from, room.to_global(Vector3(_w.x, -1.0, _w.z)), 1)
	var hit := room.get_world_3d().direct_space_state.intersect_ray(q)
	return 0.0 if hit.is_empty() else room.to_local(hit.position).y


func _settle_on_what_is_under(room: Node3D) -> void:
	_w.y = _under(room) + CLAW_LEN * 0.9


# --- Motion ----------------------------------------------------------------------------

func _drive_x(goal: float, delta: float, lim: float) -> void:
	goal = clampf(goal, -lim, lim)
	var d := goal - _x
	var want := signf(d) * minf(TROLLEY_SPEED, sqrt(2.0 * TROLLEY_ACCEL * absf(d)))
	_xv = move_toward(_xv, want, TROLLEY_ACCEL * delta)
	_x += _xv * delta
	if not _fell and int(table.get("state")) != Table.State.DYING:
		_w.x += _xv * delta


## The head toward `goal` at up to `speed`, braking to arrive.
func _head_to(goal: Vector3, delta: float, speed: float) -> void:
	_w_goal = goal
	var d := goal - _w
	var dist := d.length()
	var want := Vector3.ZERO
	if dist > 0.001:
		want = d / dist * minf(speed, sqrt(2.0 * HEAD_ACCEL * dist))
	_wv = _wv.move_toward(want, HEAD_ACCEL * delta)
	_w += _wv * delta


func _aim_at(dir: Vector3, delta: float, rate: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	_aim = _aim.slerp(dir.normalized(), clampf(delta * rate, 0.0, 1.0)).normalized() \
		if absf(_aim.dot(dir.normalized())) < 0.9999 else dir.normalized()


func _muzzle_local() -> Vector3:
	return _w + _aim * CLAW_LEN * 0.75


# --- Drawing -------------------------------------------------------------------------

func _draw(now: float, room: Node3D) -> void:
	var rt := room.global_transform
	var b: Vector2 = table.get("_b")
	var rail_z := b.y + BEAM_RAIL_Z
	_ring.global_transform = rt * Transform3D(Basis().scaled(Vector3.ONE * BEAM_TROLLEY),
		Vector3(_x, Table.TROLLEY_TOP, rail_z))
	# The claw: its -Y along the aim.
	var y := -_aim
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var shiver := 0.04 * sin(now * 57.0) if beam != Beam.IDLE else 0.0
	_claw.global_transform = rt * Transform3D(Basis(x, y, z) * Basis(Vector3.UP, shiver), _w)
	# The arm: root to wrist, telescoped.
	var root := Vector3(_x, BEAM_ROOT_Y + 0.2, rail_z)
	var total := root.distance_to(_w)
	var n := clampi(ceili(total / Table.SEG_LEN), 1, Table.SEG_MAX)
	for i in Table.SEG_MAX:
		var seg := _segs[i]
		if i >= n or total < 0.05:
			seg.visible = false
			continue
		seg.visible = true
		var a := root.lerp(_w, float(i) / float(n))
		var c := root.lerp(_w, float(i + 1) / float(n))
		var d := c - a
		var len_ := d.length()
		var sy := d / len_
		var sref := Vector3.UP if absf(sy.y) < 0.95 else Vector3.RIGHT
		var sx := sref.cross(sy).normalized()
		var sz := sx.cross(sy).normalized()
		seg.global_transform = rt * Transform3D(Basis(sx * 2.0, sy * (len_ * 1.08), sz * 2.0), (a + c) * 0.5)
	# Its glow: an ember with the power, white-blue while it charges and fires.
	var power: float = table.get("_power")
	var charge := 0.0
	if beam == Beam.CHARGE:
		charge = clampf((now - _phase_t) / CHARGE_TIME, 0.0, 1.0)
	elif beam == Beam.FIRE:
		charge = 1.0
	for m in _mats:
		m.emission = CRYSTAL.lerp(HOT, charge)
		m.emission_energy_multiplier = 0.25 * power + 1.6 * charge * (0.85 + 0.15 * sin(now * 40.0))
	_light.light_energy = (0.8 * power + 2.0 * charge)
	_light.visible = power > 0.03
	_draw_beam(now, rt)


func _draw_beam(now: float, rt: Transform3D) -> void:
	var on := beam == Beam.FIRE
	_beam_root.visible = on
	if not on:
		if _beam_light != null:
			_beam_light.visible = false
		return
	var from := rt * _muzzle_local()
	var length := maxf(from.distance_to(_beam_end), 0.05)
	var dir := (_beam_end - from) / length
	if _beam_on_player:
		length = maxf(length - SHORT_OF_PLAYER, 0.1)
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	_beam_root.global_transform = Transform3D(Basis.looking_at(dir, up), from)
	var grow := clampf((now - _phase_t) / 0.12, 0.0, 1.0)
	var width := (1.0 + 0.18 * sin(now * 61.0) + 0.1 * sin(now * 23.0)) * lerpf(0.3, 1.0, grow)
	for holder in _spans:
		holder.scale = Vector3(width, width, length)
	_flare.visible = not _beam_on_player
	_flare.position = Vector3(0.0, 0.0, -length)
	_flare.scale = Vector3.ONE * 0.9 * width
	if Graphics.effects:
		if _beam_light == null:
			_beam_light = OmniLight3D.new()
			_beam_light.light_color = CRYSTAL
			_beam_light.light_energy = 2.2
			_beam_light.omni_range = 4.5
			_beam_light.shadow_enabled = false
			_beam_light.top_level = true
			add_child(_beam_light)
		_beam_light.visible = true
		_beam_light.global_position = _beam_end - dir * 0.4
	elif _beam_light != null:
		_beam_light.visible = false


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
