extends Node3D

## An old wooden double door filling a corridor archway. Walk up to it from
## either side and press E (action "interact"): the player kicks it in, in a
## short scene they cannot cancel (`_kick`, below), and the leaves burst into
## pieces. `_open()` still swings it open the old way, for anything that wants
## a door simply opened.
##
## Built by `module_level.place_doors`, which makes the children this drives:
## "LeafL" and "LeafR" (hinged on the jambs) and "Blocker" (the collision).
## Local +Z points one way through the arch, -Z the other.
##
## The blocker starts DISABLED and is armed once the level reports it is built:
## the navmesh is baked before that, and a closed door baked into it would cut
## the corridor in two for the enemies for good, even after it was opened.

@export var reach := 2.4
@export var open_time := 0.7
@export var open_angle := 1.55

## Fired once, the moment the door is opened. The exploration map listens: it
## does not map anything beyond a door until it has been.
signal door_opened

var opened := false
var _near := false
var _side := 1.0
var _player: Node3D = null
var _prompt: Interact.Prompt
var _blocker: CollisionShape3D


func _ready() -> void:
	# Patrols (patrol.gd) route round the shut ones.
	add_to_group(&"wood_doors")
	_prompt = Interact.prompt("E   Kick in", Vector3(0.0, 1.75, 0.0))
	add_child(_prompt)
	var maze := _find_maze()
	if maze != null and maze.has_signal("level_built"):
		maze.level_built.connect(_arm, CONNECT_ONE_SHOT)
	else:
		_arm.call_deferred()


func _find_maze() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_signal("level_built"):
			return node
		node = node.get_parent()
	return null


## Looked up when needed, not in _ready: the builder adds the leaves and the
## blocker AFTER the door has entered the tree, so at _ready they are not there.
func _shape() -> CollisionShape3D:
	if _blocker == null:
		_blocker = get_node_or_null("Blocker/Shape") as CollisionShape3D
	return _blocker


func _arm() -> void:
	if not opened and _shape() != null:
		_blocker.set_deferred("disabled", false)
	_snap_torches.call_deferred()
	if not DEBRIS.warmed:
		var sources := []
		for leaf_name in ["LeafL", "LeafR"]:
			var leaf := get_node_or_null(leaf_name)
			if leaf == null:
				continue
			for child in leaf.get_children():
				var mi := child as MeshInstance3D
				if mi != null and mi.mesh != null and mi.name != "Batten":
					for s in mi.mesh.get_surface_count():
						sources.append(mi.mesh.surface_get_material(s))
					# Cut the pieces now as well: clipping a leaf's triangles in
					# script is the other half of what the break used to stall on.
					var cut := _split_for(leaf_name, mi)
					DEBRIS.pieces_for(mi.mesh, cut[0], cut[1], cut[2], cut[3])
		DEBRIS.warm_up.call_deferred(get_viewport().get_camera_3d(), sources)


## The torches either side of this door (set by module_level as meta
## "torches") are placed from measured figures, but the stone is a generated
## mesh and not every straight's walls stand in the same place. Once the
## level's collision is in the physics space, each one is moved onto the real
## wall: a ray from 0.7 m out in front of it, along the way it faces into the
## stone, and the torch hung TORCH_STANDOFF off whatever that hits.
func _snap_torches() -> void:
	var torches: Array = get_meta("torches", [])
	if torches.is_empty():
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for t in torches:
		var torch := t as Node3D
		if not is_instance_valid(torch):
			continue
		# The torch scene faces -Z out of the wall, so +Z points into it.
		var into := torch.global_basis.z.normalized()
		var from := torch.global_position - into * 0.7
		var ray := PhysicsRayQueryParameters3D.create(from, from + into * 1.6, WALL_MASK)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			torch.global_position = (hit["position"] as Vector3) - into * TORCH_STANDOFF


## Exact wall collision (layer 9) and the sight layer (2), as the player's.
const WALL_MASK := 256 | 2
const TORCH_STANDOFF := 0.12


func _process(_delta: float) -> void:
	if opened:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var to := _player.global_position - global_position
	# In reach AND looked at: the crosshair has to be on the door.
	_near = Vector2(to.x, to.z).length() <= reach and _aimed_at()
	# Which side the player is on, so the door swings away from them.
	_side = 1.0 if to.dot(global_basis.z) >= 0.0 else -1.0
	_prompt.visible = _near
	# On the player's side of the leaves, not buried in them.
	_prompt.position.z = 0.25 * _side


## Furthest along the view a door can be and still be aimed at.
const AIM_RANGE := 3.6


## True while the centre of the view lies on the door: the view ray crosses
## the plane of the blocker (the box filling the opening) inside its rectangle.
## Geometric rather than a ray cast, so it works before the blocker is armed and
## is not caught by the jambs or the moulding around the leaves.
func _aimed_at() -> bool:
	var shape := _shape()
	var camera := get_viewport().get_camera_3d()
	if shape == null or camera == null or not (shape.shape is BoxShape3D):
		return false
	var half := (shape.shape as BoxShape3D).size * 0.5
	var to_box := shape.global_transform.affine_inverse()
	var from := to_box * camera.global_position
	# A unit world direction, so `t` below is the distance in metres.
	var dir := to_box.basis * -camera.global_basis.z.normalized()
	if absf(dir.z) < 1e-4:
		return false
	var t := -from.z / dir.z
	if t <= 0.0 or t > AIM_RANGE:
		return false
	var at := from + dir * t
	return absf(at.x) <= half.x and absf(at.y) <= half.y


func _unhandled_input(event: InputEvent) -> void:
	if _near and not opened and Interact.pressed(event) and _player != null \
			and not _player.get("in_cutscene"):
		get_viewport().set_input_as_handled()
		_kick()


# --- Kicked in -----------------------------------------------------------------
#
# E does not open the door: it is a short scene the player cannot cancel.
# The player has no body to film from outside, so the camera stays in their
# eyes and does the cinematography -- letterbox bars, the sword put away, a step
# back and a crouch, a rush at the door, the view dipping to show the boot
# going in, a moment of slow motion and shake on impact, and the door bursting
# into pieces (door_debris.gd) that are watched until they have settled.

const WINDUP_DIST := 2.3
const KICK_DIST := 0.9
const TURN_TIME := 0.25
const RUSH_TIME := 0.2
const SLOWMO := 0.3
const SLOWMO_TIME := 0.25
## From the end of the slow motion to control back.
const RETURN_TIME := 0.22
## Enemies this close to the door when it bursts are thrown back and turn on
## the player.
const SHOVE_RADIUS := 3.0
const SHOVE_PUSH := 16.0
const SHOVE_STUN := 0.6
## Where the boot connects, on the door, above the floor.
const IMPACT_HEIGHT := 1.1

const DEBRIS := preload("res://scripts/door_debris.gd")

var _pieces: Array = []
## How many enemies the last kick threw back (for tests).
var shoved := 0


func _kick() -> void:
	var p := _player as CharacterBody3D
	opened = true
	_near = false
	_prompt.visible = false
	p.begin_cutscene()
	p.set("hands_busy", true)
	var bars := letterbox(self)

	# From the door towards the player, along the arch's axis.
	var out := global_basis.z * _side
	var base := Vector3(global_position.x, p.global_position.y, global_position.z)
	var windup := base + out * _clear_behind(base, out, WINDUP_DIST)
	var strike := base + out * KICK_DIST
	var yaw: float = p.rotation.y + wrapf(atan2(out.x, out.z) - p.rotation.y, -PI, PI)
	var pitch0: float = p.get("_look_pitch")

	# 1. Square up to the door, a step back, weight down.
	var t := _tween()
	t.tween_property(p, "rotation:y", yaw, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(p, "global_position", windup, TURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(p, "_look_pitch", -0.1, TURN_TIME)
	await t.finished

	# 2. The rush. The view opens out and drops to watch the boot come up.
	var leg := _make_leg(p)
	p.set("_dash_view", 1.0)
	t = _tween()
	t.tween_property(p, "global_position", strike, RUSH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(p, "_look_pitch", -0.33, RUSH_TIME)
	# Knee up through the rush, then the leg drives out on the last few frames.
	t.tween_property(leg, "rotation:x", 0.9, RUSH_TIME * 0.65).set_trans(Tween.TRANS_SINE)
	t.chain().tween_property(leg, "rotation:x", LEG_STRIKE, RUSH_TIME * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished

	# 3. Impact.
	_burst(out)
	Engine.time_scale = SLOWMO
	p.set("_land_kick", 1.0)
	p.set("_land_strength", 0.5)
	await _shake(p, yaw, -0.33, SLOWMO_TIME)
	Engine.time_scale = 1.0

	# 4. Straight back to the player: the leg drops, the view lifts and the bars
	# slide off together, and the pieces finish falling with the player already
	# in control. (Waiting for them to settle first held the scene up to 2.4 s.)
	t = _tween()
	t.tween_property(leg, "rotation:x", 0.0, RETURN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(p, "_look_pitch", clampf(pitch0, -0.3, 0.3), RETURN_TIME).set_trans(Tween.TRANS_SINE)
	letterbox_out(bars)
	await t.finished
	leg.queue_free()
	p.set("hands_busy", false)
	p.end_cutscene()


## A loaded game: this door was kicked in. Gone at once -- no scene, no pieces --
## and the map told, as the kick would have.
func restore_opened() -> void:
	opened = true
	_near = false
	_prompt.visible = false
	if _shape() != null:
		_blocker.set_deferred("disabled", true)
	for leaf_name in ["LeafL", "LeafR"]:
		var leaf := get_node_or_null(leaf_name) as Node3D
		if leaf != null:
			leaf.visible = false
	door_opened.emit()


## Real-time tweens: the slow motion must not slow the camera work.
func _tween() -> Tween:
	return create_tween().set_parallel(true).set_ignore_time_scale(true)


## How far the player can step back from the door along `out` before a wall.
func _clear_behind(from: Vector3, out: Vector3, want: float) -> float:
	var eye := from + Vector3(0.0, 1.0, 0.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(eye, eye + out * (want + 0.5), WALL_MASK))
	if hit.is_empty():
		return want
	return clampf(eye.distance_to(hit["position"]) - 0.5, KICK_DIST + 0.3, want)


## How a leaf breaks: [cols, rows, slant, merge top]. The brick kit's single
## Tripo leaf ("Boards") splinters into 5 uneven pieces along slanted cuts; the
## old gate's two leaves split straight across, 2 and 3.
func _split_for(leaf_name: String, mi: MeshInstance3D) -> Array:
	if mi.name == "Boards":
		# 3 x 3 with the pointed head one piece: 7 uneven pieces (was 2 x 3 -> 5).
		return [3, 3, 0.5, true]
	return [1, 2 if leaf_name == "LeafL" else 3, 0.0, false]


## The door gives: the leaves become pieces, the way is open.
func _burst(out: Vector3) -> void:
	if _shape() != null:
		_blocker.set_deferred("disabled", true)
	door_opened.emit()
	var push := -out
	var impact := global_position + Vector3(0.0, IMPACT_HEIGHT, 0.0)
	var effects: bool = Graphics.effects
	# A handful of big pieces -- the door splits, it does not shatter (_split_for).
	for leaf_name in ["LeafL", "LeafR"]:
		var leaf := get_node_or_null(leaf_name) as Node3D
		if leaf == null:
			continue
		for child in leaf.get_children():
			var mi := child as MeshInstance3D
			if mi != null and mi.name != "Batten" and mi.mesh != null:
				var cut := _split_for(leaf_name, mi)
				_pieces.append_array(DEBRIS.shatter(mi, get_parent() as Node3D, push, impact,
					cut[0], cut[1], cut[2], cut[3]))
		leaf.visible = false
	DEBRIS.crumble(_pieces, effects)
	if effects:
		DEBRIS.dust(get_parent() as Node3D, impact, push)
	_shove(impact)


## Everything that can be hurt within SHOVE_RADIUS of the boot (the damageable
## layer, 3) is thrown away from the door and alerted. Not hurt: a door is not
## a weapon. A dormant mimic ignores it, as it ignores knockback -- it is a chest
## until it is opened.
func _shove(impact: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = SHOVE_RADIUS
	query.shape = ball
	query.transform = Transform3D(Basis(), impact)
	query.collision_mask = 4
	query.collide_with_bodies = true
	query.collide_with_areas = false
	if _player != null:
		query.exclude = [(_player as CollisionObject3D).get_rid()]
	var seen := {}
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var body := hit["collider"] as Node3D
		if body == null or seen.has(body) or body == _player:
			continue
		seen[body] = true
		var away := body.global_position - impact
		away.y = 0.0
		if away.length_squared() < 0.0001:
			away = -global_basis.z * _side
		if body.has_method("apply_knockback"):
			body.apply_knockback(away.normalized() * SHOVE_PUSH, SHOVE_STUN)
		if body.has_method("alert"):
			body.alert()
	shoved = seen.size()


## A decaying shake of the view about where it is aimed, in real time.
func _shake(p: Node3D, yaw: float, pitch: float, duration: float) -> void:
	var start := Time.get_ticks_msec()
	while true:
		var k := (Time.get_ticks_msec() - start) / 1000.0 / duration
		if k >= 1.0:
			break
		var amp := 0.035 * (1.0 - k) * (1.0 - k)
		p.rotation.y = yaw + randf_range(-amp, amp)
		p.set("_look_pitch", pitch + randf_range(-amp, amp))
		await get_tree().process_frame
	p.rotation.y = yaw
	p.set("_look_pitch", pitch)


## The kicking leg, built for the scene: hinged at the hip on the player's body
## (not the head, so dipping the view reveals it), hanging straight down out of
## sight at 0 and driving forward to LEG_STRIKE, where the sole meets the door.
const LEG_STRIKE := 1.75
const LEG_LENGTH := 1.0

func _make_leg(p: Node3D) -> Node3D:
	var hip := Node3D.new()
	hip.name = "KickLeg"
	hip.position = Vector3(0.16, 0.95, 0.12)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.12, 0.1, 0.085)
	cloth.roughness = 0.95
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.2, 0.12, 0.065)
	leather.roughness = 0.6
	var sole_mat := StandardMaterial3D.new()
	sole_mat.albedo_color = Color(0.05, 0.04, 0.035)
	sole_mat.roughness = 0.9
	var shin := CapsuleMesh.new()
	shin.radius = 0.075
	shin.height = LEG_LENGTH * 0.92
	shin.material = cloth
	_part(hip, shin, Vector3(0.0, -LEG_LENGTH * 0.46, 0.0))
	# The boot: a shaft round the ankle, the foot with its toe pointing local -Z
	# (up, when the leg is out), and a heavy sole facing along the leg.
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.085
	shaft.bottom_radius = 0.09
	shaft.height = 0.22
	shaft.material = leather
	_part(hip, shaft, Vector3(0.0, -LEG_LENGTH + 0.13, 0.0))
	var foot := BoxMesh.new()
	foot.size = Vector3(0.13, 0.1, 0.3)
	foot.material = leather
	_part(hip, foot, Vector3(0.0, -LEG_LENGTH + 0.02, -0.08))
	var sole := BoxMesh.new()
	sole.size = Vector3(0.14, 0.035, 0.31)
	sole.material = sole_mat
	_part(hip, sole, Vector3(0.0, -LEG_LENGTH - 0.045, -0.08))
	p.add_child(hip)
	return hip


func _part(parent: Node3D, mesh: Mesh, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)


## Black bars top and bottom, sliding in. Driven by their OFFSETS: they are
## anchored full-width, and Godot overrides a size set on such a control.
static func letterbox(from: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 40
	from.get_tree().root.add_child(layer)
	var h: float = from.get_viewport().get_visible_rect().size.y * 0.11
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.name = "Top" if top else "Bottom"
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = 0.0
		bar.offset_bottom = 0.0
		layer.add_child(bar)
		var t := bar.create_tween().set_ignore_time_scale(true)
		t.tween_property(bar, "offset_bottom" if top else "offset_top", h if top else -h, 0.3) \
			.set_trans(Tween.TRANS_SINE)
	return layer


static func letterbox_out(layer: CanvasLayer) -> void:
	var t := layer.create_tween().set_parallel(true).set_ignore_time_scale(true)
	for bar in layer.get_children():
		t.tween_property(bar, "offset_bottom" if bar.name == "Top" else "offset_top", 0.0, 0.3)
	t.chain().tween_callback(layer.queue_free)
