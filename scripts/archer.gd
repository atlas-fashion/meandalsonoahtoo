extends "res://scripts/enemy.gd"

## The skeleton archer (2026-10-09): the ordinary skeleton (enemy.gd) with a bow.
## The maze spawns one at the back of some packs (maze.gd `archer_share`), by
## putting this script on an enemy.tscn instance before it enters the tree --
## which is why its numbers are set in `_init` rather than in a scene.
##
## Hunting (`_chase`, enemy.gd's hook):
##   * shoots: draws for DRAW_TIME (the tell -- the bow comes up, the string
##     comes back, the arrowhead brightens), looses an arrow (arrow.gd, 15
##     damage) when it has a clear line, and the next comes 3 to 4.5 s after;
##   * keeps its distance: closer than KEEP_MIN it backs away along the
##     navmesh, but it is slower than the player and corners stop it, so it
##     does not always manage it; further than KEEP_MAX, or with no line, it
##     comes on;
##   * hides behind its fellows: with another skeleton nearby it goes to stand
##     behind it, on the far side from the player. Arrows pass its fellows.
##   * cornered and touched, it falls back on the ordinary swing (a feeble 8).
##
## The arms are posed in code while aiming -- the rig has no bow clips: the left
## arm points along the shot, the right hand draws back to the jaw.

const ARROW := preload("res://scripts/arrow.gd")

const ARROW_DAMAGE := 15.0
const SHOT_MIN := 3.0
const SHOT_MAX_GAP := 4.5
const DRAW_TIME := 0.85
## Seconds after it first notices the player before its first shot.
const FIRST_SHOT := 1.1
## Range it tries to hold, and the furthest it will shoot.
const KEEP_MIN := 8.0
const KEEP_MAX := 17.0
const SHOT_RANGE := 26.0
## How far it looks for a fellow to stand behind, and how far behind it stands.
const COVER_SEARCH := 12.0
const COVER_BEHIND := 1.6
const PLAN_EVERY := 0.45
const WORLD_MASK := 2 | 256

var _drawing := false
var _release_at := 0.0
var _next_shot := -1.0
var _draw := 0.0
var _aim := 0.0
var _aim_point := Vector3.ZERO
var _goal := Vector3.ZERO
var _goal_kind := &"hold"
var _next_plan := 0.0
var _clear := false
var _next_clear := 0.0
var _cover_of: Node3D = null

var _sk: Skeleton3D
var _bones := {}
var _bow: Node3D
var _string_top: MeshInstance3D
var _string_bottom: MeshInstance3D
var _nocked: Node3D
var _nock_mat: StandardMaterial3D
const BOW_HALF := 0.52
const BOW_BEND := 0.17


func _init() -> void:
	# What enemy.tscn sets on the plain skeleton, and the archer's own. A bow,
	# not a sword (enemy.gd `armed`).
	armed = false
	max_health = 60.0
	move_speed = 3.3
	vision_cone_degrees = 140.0
	sight_needs_line_of_sight = true
	sight_memory = 6.0
	wanders = true
	wander_speed = 1.1
	can_slam = false
	can_normal = true
	normal_range = 1.5
	normal_cooldown = 2.5
	attack_damage = 8.0
	tint_albedo = false
	walk_anim_speed = 1.45
	run_anim_speed = 3.56
	run_anim_threshold = 2.4
	display_name = "SKELETON ARCHER"


func is_archer() -> bool:
	return true


func _ready() -> void:
	super()
	name = "Archer"
	var found := find_children("*", "Skeleton3D", true, false)
	_sk = found[0] as Skeleton3D if not found.is_empty() else null
	if _sk != null:
		for b in [&"upper_arm.L", &"forearm.L", &"hand.L", &"upper_arm.R", &"forearm.R", &"hand.R",
				&"head", &"chest", &"spine.02"]:
			_bones[b] = _sk.find_bone(b)
	_build_bow()


# --- Hunting ----------------------------------------------------------------------

func _chase(delta: float, now: float, player: Node3D, flat: Vector3, distance: float, gap: float) -> bool:
	_aim_point = player.global_position + Vector3(0.0, 1.25, 0.0)
	if now >= _next_clear:
		_next_clear = now + 0.15
		_clear = _line_to(player)
	# Touching distance: the ordinary swing.
	if gap <= normal_range + 0.3 and not _drawing:
		_aim = move_toward(_aim, 0.0, delta * 4.0)
		return false
	if _next_shot < 0.0:
		_next_shot = now + FIRST_SHOT

	if _drawing:
		_face(flat)
		_stop(delta)
		_draw = minf(_draw + delta / DRAW_TIME, 1.0)
		if now >= _release_at:
			if _clear:
				_release(now)
			elif now > _release_at + 1.0:
				# Lost the line and never got it back: lower the bow.
				_drawing = false
				_next_shot = now + 0.8
		return true

	# Into cover (or clear of the player) first, unless the shot is well
	# overdue: stopping to draw half way there left it standing in the open.
	var settled := _goal_kind == &"hold" or _goal_kind == &"approach" \
		or Vector2(_goal.x - global_position.x, _goal.z - global_position.z).length() < 1.0
	if _clear and distance <= SHOT_RANGE and now >= _next_shot - DRAW_TIME \
			and (settled or now >= _next_shot + 1.5):
		_drawing = true
		_release_at = now + DRAW_TIME
		_draw = 0.0
		_face(flat)
		_stop(delta)
		return true

	if now >= _next_plan:
		_next_plan = now + PLAN_EVERY
		_plan(player, distance)
	_move_to_goal(delta, now, flat)
	return true


func _release(now: float) -> void:
	_drawing = false
	_draw = 0.0
	_next_shot = now + randf_range(SHOT_MIN, SHOT_MAX_GAP)
	var from := _nocked.global_position if _nocked != null else global_position + Vector3(0.0, 1.4, 0.0)
	ARROW.fire(get_parent(), from, _aim_point, self, ARROW_DAMAGE)


## Where to be: behind a fellow if there is one to hand, otherwise further off
## if too close, nearer if too far or out of sight, else where it stands.
func _plan(player: Node3D, distance: float) -> void:
	_goal = global_position
	_goal_kind = &"hold"
	var cover = _find_cover(player)
	if cover != null:
		_goal = cover
		_goal_kind = &"cover"
		return
	if distance < KEEP_MIN:
		var away = _retreat_point(player, distance)
		if away != null:
			_goal = away
			_goal_kind = &"retreat"
		return
	if distance > KEEP_MAX or not _clear:
		_goal = player.global_position
		_goal_kind = &"approach"


## The nearest place standing behind a fellow skeleton -- on the far side of it
## from the player -- that is not on top of the player.
func _find_cover(player: Node3D) -> Variant:
	var best = null
	var best_d := INF
	_cover_of = null
	var map := get_world_3d().navigation_map
	for node in get_tree().get_nodes_in_group(&"skeletons"):
		var s := node as Node3D
		if s == null or s == self or not is_instance_valid(s) or s.has_method("is_archer") \
				or s.get("_dying") == true or s.get("_dormant") == true:
			continue
		if s.global_position.distance_to(global_position) > COVER_SEARCH:
			continue
		var from_player := s.global_position - player.global_position
		from_player.y = 0.0
		if from_player.length() < 3.0:
			continue
		var c := s.global_position + from_player.normalized() * COVER_BEHIND
		c = NavigationServer3D.map_get_closest_point(map, c)
		var to_player := Vector2(c.x - player.global_position.x, c.z - player.global_position.z).length()
		if to_player < 5.0 or to_player > KEEP_MAX + 3.0:
			continue
		var d := c.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = c
			_cover_of = s
	return best


## Somewhere on the navmesh further from the player, or null if it is cornered.
func _retreat_point(player: Node3D, distance: float) -> Variant:
	var away := global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = global_basis.z
	away = away.normalized()
	var map := get_world_3d().navigation_map
	var best = null
	var best_d := distance + 1.0
	for turn: float in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var dir := away.rotated(Vector3.UP, turn)
		var q := NavigationServer3D.map_get_closest_point(map, global_position + dir * 4.0)
		var d := Vector2(q.x - player.global_position.x, q.z - player.global_position.z).length()
		if d > best_d:
			best_d = d
			best = q
	return best


func _move_to_goal(delta: float, now: float, flat: Vector3) -> void:
	var to := _goal - global_position
	to.y = 0.0
	if _goal_kind == &"hold" or to.length() < 0.6:
		_stop(delta)
		_face(flat)
		return
	var dir := to.normalized()
	if agent != null:
		if now >= _next_repath:
			_next_repath = now + repath_interval
			agent.target_position = _goal
		if not agent.is_navigation_finished():
			var step := agent.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.1:
				dir = step.normalized()
	# Backing off or slipping into cover, it keeps its eyes on the player.
	_face(flat if _clear and _goal_kind != &"approach" else dir)
	var speed := move_speed * (0.85 if _goal_kind == &"retreat" else 1.0)
	velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	_slide()


func _stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	_slide()


## A clear line from its eyes to the player's chest through stone. Its fellows
## do not count: arrows pass them.
func _line_to(player: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 1.45, 0.0),
		player.global_position + Vector3(0.0, 1.25, 0.0), WORLD_MASK)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- The bow and the aiming pose -------------------------------------------------------

func _physics_process(delta: float) -> void:
	super(delta)
	if _dying:
		return
	var aiming := _drawing or (state == State.CHASE and engaged and _clear and _next_shot >= 0.0 \
		and _now() >= _next_shot - DRAW_TIME - 0.6)
	_aim = move_toward(_aim, 1.0 if aiming else 0.0, delta * (5.0 if aiming else 2.5))
	if not _drawing:
		_draw = move_toward(_draw, 0.0, delta * 8.0)
	_pose_arms()
	_place_bow()


func _pose_arms() -> void:
	if _sk == null or _aim <= 0.001 or int(_bones.get(&"upper_arm.L", -1)) < 0:
		return
	var to_skel := _sk.global_transform.affine_inverse()
	var aim_dir := _aim_point - (global_position + Vector3(0.0, 1.4, 0.0))
	if aim_dir.length_squared() < 0.01:
		aim_dir = -global_basis.z
	aim_dir = aim_dir.normalized()
	var side := aim_dir.cross(Vector3.UP).normalized()
	# The bow arm, straight out along the shot.
	_point_bone(_bones[&"upper_arm.L"], to_skel.basis * aim_dir)
	_point_bone(_bones[&"forearm.L"], to_skel.basis * aim_dir)
	# The draw arm: the elbow out and back at shoulder height, the hand drawn to
	# the jaw.
	var shoulder_r := _sk.global_transform * _sk.get_bone_global_pose(_bones[&"upper_arm.R"]).origin
	var head := _sk.global_transform * _sk.get_bone_global_pose(_bones[&"head"]).origin
	var jaw := head + aim_dir * 0.12 - Vector3(0.0, 0.1, 0.0) + side * 0.04
	var elbow_dir := (-aim_dir * 0.7 + side * 0.7).normalized()
	_point_bone(_bones[&"upper_arm.R"], to_skel.basis * elbow_dir)
	var elbow := _sk.global_transform * _sk.get_bone_global_pose(_bones[&"forearm.R"]).origin
	_point_bone(_bones[&"forearm.R"], to_skel.basis * (jaw - elbow))


## Turns a bone, in place, so its length (+Y) runs along `dir` (skeleton space),
## blended by how far the archer is into its aim.
func _point_bone(bone: int, dir: Vector3) -> void:
	if bone < 0 or dir.length_squared() < 1e-6:
		return
	var pose := _sk.get_bone_global_pose(bone)
	var basis := pose.basis.orthonormalized()
	var turned := Basis(Quaternion(basis.y.normalized(), dir.normalized())) * basis
	pose.basis = basis.slerp(turned.orthonormalized(), _aim)
	_sk.set_bone_global_pose(bone, pose)


func _build_bow() -> void:
	_bow = Node3D.new()
	_bow.name = "Bow"
	add_child(_bow)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.19, 0.12)
	wood.roughness = 0.85
	var horn := StandardMaterial3D.new()
	horn.albedo_color = Color(0.62, 0.58, 0.5)
	horn.roughness = 0.8
	# The limbs: an arc from tip to tip, the grip furthest forward (-Z) and the
	# tips bending back toward the archer.
	var steps := 10
	for k in steps:
		var a := lerpf(-1.0, 1.0, (float(k) + 0.5) / float(steps))
		var a0 := lerpf(-1.0, 1.0, float(k) / float(steps))
		var a1 := lerpf(-1.0, 1.0, float(k + 1) / float(steps))
		var p0 := Vector3(0.0, a0 * BOW_HALF, BOW_BEND * a0 * a0)
		var p1 := Vector3(0.0, a1 * BOW_HALF, BOW_BEND * a1 * a1)
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		var thick := 0.035 - 0.015 * absf(a)
		box.size = Vector3(thick, p0.distance_to(p1) + 0.01, thick * 1.3)
		seg.mesh = box
		seg.material_override = wood
		seg.position = (p0 + p1) * 0.5
		# A turn of a about X takes +Y to (0, cos a, sin a): along the arc.
		seg.rotation.x = atan2(p1.z - p0.z, p1.y - p0.y)
		_bow.add_child(seg)
	for s: float in [-1.0, 1.0]:
		var tip := MeshInstance3D.new()
		var cap := BoxMesh.new()
		cap.size = Vector3(0.03, 0.06, 0.03)
		tip.mesh = cap
		tip.material_override = horn
		tip.position = Vector3(0.0, s * BOW_HALF, BOW_BEND)
		_bow.add_child(tip)
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.75, 0.72, 0.65)
	_string_top = _thin(string_mat)
	_string_bottom = _thin(string_mat)
	_bow.add_child(_string_top)
	_bow.add_child(_string_bottom)
	# The arrow on the string, shown while drawing.
	_nocked = Node3D.new()
	_bow.add_child(_nocked)
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = 0.78
	cyl.radial_segments = 5
	shaft.mesh = cyl
	shaft.material_override = wood
	shaft.rotation.x = PI * 0.5
	shaft.position.z = 0.39
	_nocked.add_child(shaft)
	_nock_mat = StandardMaterial3D.new()
	_nock_mat.albedo_color = Color(0.3, 0.12, 0.05)
	_nock_mat.emission_enabled = true
	_nock_mat.emission = Color(1.0, 0.45, 0.15)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.025
	cone.height = 0.09
	cone.radial_segments = 6
	head.mesh = cone
	head.material_override = _nock_mat
	head.rotation.x = -PI * 0.5
	head.position.z = -0.03
	_nocked.add_child(head)
	# A quiver on its back, so it is known for an archer before it draws.
	var quiver := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.07
	tube.bottom_radius = 0.06
	tube.height = 0.55
	quiver.mesh = tube
	quiver.material_override = wood
	quiver.position = Vector3(0.12, 1.3, 0.18)
	quiver.rotation = Vector3(0.25, 0.0, 0.35)
	add_child(quiver)
	for k in 4:
		var fletch := _thin(horn)
		fletch.scale = Vector3(1.6, 0.16, 1.6)
		fletch.position = quiver.position + Vector3(0.07 + 0.012 * float(k), 0.3, 0.1 + 0.015 * float(k - 2))
		fletch.rotation = quiver.rotation
		add_child(fletch)
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent() == _bow or mi.get_parent() == _nocked or mi.get_parent() == self:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _thin(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
	cyl.height = 1.0
	cyl.radial_segments = 4
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = mat
	return mi


## The bow in the left hand: pointing along the shot while aiming, held low and
## forward otherwise; the string pulled back by `_draw`.
func _place_bow() -> void:
	if _bow == null:
		return
	var grip := global_position + Vector3(0.0, 1.0, 0.0) - global_basis.z * 0.3
	var hand := int(_bones.get(&"hand.L", -1))
	if _sk != null and hand >= 0:
		grip = _sk.global_transform * _sk.get_bone_global_pose(hand).origin
	var forward := -global_basis.z
	var aim_dir := (_aim_point - grip).normalized() if _aim_point != Vector3.ZERO else forward
	var rest_dir := (forward + Vector3(0.0, -1.2, 0.0)).normalized()
	var dir := rest_dir.slerp(aim_dir, _aim).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else forward
	_bow.global_transform = Transform3D(Basis.looking_at(dir, up), grip)
	# The string: from each tip to the nock, which the draw pulls back.
	var nock := Vector3(0.0, 0.0, BOW_BEND + _draw * 0.42)
	_span(_string_top, Vector3(0.0, BOW_HALF, BOW_BEND), nock)
	_span(_string_bottom, Vector3(0.0, -BOW_HALF, BOW_BEND), nock)
	_nocked.visible = _drawing or _draw > 0.05
	# Its origin is the arrowhead: the shaft runs 0.78 m back to the nock.
	_nocked.position = nock - Vector3(0.0, 0.0, 0.78)
	_nock_mat.emission_energy_multiplier = 0.8 + 4.0 * _draw


func _span(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var y := d / length
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	# Stretched along its own length (the basis's Y column), not the bow's Y.
	mi.transform = Transform3D(Basis(x, y * length, x.cross(y)), (a + b) * 0.5)


## Staggered mid-draw: the arrow is lost, and the draw starts again from the
## beginning once it has recovered.
func _on_staggered() -> void:
	if _drawing:
		_drawing = false
		_next_shot = maxf(_next_shot, _now() + 0.6)


## Scared off by a thrown rat (enemy.gd `scare`): the arrow is lost, as when
## staggered.
func _on_scared() -> void:
	_on_staggered()


func _die() -> void:
	_drawing = false
	super()
