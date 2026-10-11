extends Node3D

## Something a dead skeleton dropped: it pops out of the body, tumbles to the
## floor, bounces and settles with a soft glint over it so it can be found in
## the dark. With the crosshair on it, E ("interact") takes it: it lifts off,
## flies to the player on a glowing trail -- the bone cages' loot flight -- and
## goes into the inventory as it arrives. If there is no room it says so and
## stays where it is.
##
## Made with `spawn(parent, at, id, count)` on this script; see enemy.gd
## `_grant_drop`.

const SCRIPT_PATH := "res://scripts/item_drop.gd"
const POTION_MODEL := "res://models/potion_held.glb"
const SKULL_MODEL := "res://models/skull_worn_ready.glb"

## Horizontal reach from the player, as a chest's.
const REACH := 2.4
const GRAVITY := 14.0
## What a drop lands on: everything static -- floors and stone (2), the props
## on layer 1 only (the jail's bed and bucket) and on 9 only (the boss's
## throne). Characters and loose bodies on those layers are skipped
## (`_world_ray`), so it never lands on an enemy's head.
const LAND_MASK := 1 | 2 | 256
## A drop resting is re-checked this often: if what it lay on has gone (a
## coffin lid slid open under it) it falls again.
const SUPPORT_CHECK := 0.25
## Last resort: falling this far below where it started, or this long, it is
## put down on the ground under where it was dropped.
const LOST_DROP := 4.0
const LOST_TIME := 4.0
## Speed below which a landing stops it rather than bouncing it.
const SETTLE_SPEED := 1.2
const FLIGHT_TIME := 0.6
const TRAIL_POINTS := 10
const TRAIL_WIDTH := 0.009

var id: StringName = &""
var count := 1

var _visual: Node3D
var _glint: MeshInstance3D
var _prompt: Interact.Prompt
var _player: Node3D
var _near := false
var _velocity := Vector3.ZERO
var _spin := Vector3.ZERO
var _resting := false
## The lowest point of the visual below its origin, so it rests ON the floor.
var _lift := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _clock := 0.0
var _fall_time := 0.0
var _support_timer := 0.0
## The ground under the point it was dropped from: the last-resort fallback.
var _home := Vector3.ZERO
var _home_found := false
var _placed := false
var _escapes := 0

# The flight to the player.
var _flying := false
var _flight := 0.0
var _from := Vector3.ZERO
var _via := Vector3.ZERO
var _trail: Array = []
var _trail_mesh: ImmediateMesh
var _trail_node: MeshInstance3D

static var _meshes := {}


## Drops `count` of `id` at `at` under `parent`, thrown out with a little
## random spread. Returns the drop.
static func spawn(parent: Node, at: Vector3, item: StringName, amount := 1) -> Node3D:
	var drop := Node3D.new()
	drop.set_script(load(SCRIPT_PATH))
	drop.set("id", item)
	drop.set("count", amount)
	drop.name = "Drop_%s" % item
	parent.add_child(drop)
	drop.global_position = at
	return drop


func _ready() -> void:
	_visual = _make_visual(id)
	add_child(_visual)
	_lift = -Interact.drawn_bounds(self).position.y
	_glint = _make_glint(Inventory.item_color(id))
	add_child(_glint)
	_glint.visible = false
	_prompt = Interact.prompt("E   Take", Vector3(0.0, 0.4, 0.0))
	add_child(_prompt)
	_ray.collision_mask = LAND_MASK
	_ray.collide_with_areas = false
	# Only the OUTSIDE of a surface catches it: landing on a back face means it
	# is inside the stone, on the inner side of the shell (measured: drops
	# freed from inside a wall came to rest on ledges in there).
	_ray.hit_back_faces = false
	# The pop: up and out to a random side.
	var a := randf() * TAU
	_velocity = Vector3(cos(a), 0.0, sin(a)) * randf_range(1.2, 2.6) + Vector3(0.0, randf_range(3.2, 4.6), 0.0)
	_spin = Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
	_visual.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)


func _process(delta: float) -> void:
	if not _placed:
		# On the first frame, not in `_ready`: `spawn` adds the drop to the tree
		# BEFORE it sets its position, so in `_ready` it is still at the origin.
		_placed = true
		_escape_solid()
		var ground := _world_ray(global_position, global_position - Vector3(0.0, 40.0, 0.0))
		_home_found = not ground.is_empty()
		if _home_found:
			_home = ground["position"]
	_clock += delta
	if _flying:
		_update_flight(delta)
		return
	if not _resting:
		_fall(delta)
	else:
		# The glint breathes, slowly, so a drop catches the eye without blinking.
		_glint.transparency = 0.35 + 0.25 * sin(_clock * 2.4)
		_support_timer -= delta
		if _support_timer <= 0.0:
			_support_timer = SUPPORT_CHECK
			_check_support()
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var to := _player.global_position - global_position
	_near = _resting and Vector2(to.x, to.z).length() <= REACH \
		and absf(to.y) < 2.0 and Interact.looked_at(self, 3.2, 0.22)
	_prompt.visible = _near


func _unhandled_input(event: InputEvent) -> void:
	if not _near or _flying or not Interact.pressed(event):
		return
	if _player == null or _player.get("in_cutscene") or _player.get("ui_open"):
		return
	get_viewport().set_input_as_handled()
	var inventory: Inventory = _player.get("inventory")
	if inventory == null or inventory.room_for(id) < count:
		_prompt.text = "Full"
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if is_instance_valid(_prompt):
				_prompt.text = "E   Take")
		return
	_take_off()


## --- Falling ------------------------------------------------------------------

func _fall(delta: float) -> void:
	_fall_time += delta
	# Never lost: gone far below where it was dropped, or falling far too long
	# (a gap nothing should have), it is put down where it was dropped.
	if _home_found and (global_position.y < _home.y - LOST_DROP or _fall_time > LOST_TIME):
		_settle(_home)
		return
	_velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + _velocity * delta
	# Measured from the bottom of the item, so it lands on its underside.
	var foot := Vector3(0.0, _lift, 0.0)
	var hit := _world_ray(from - foot + Vector3(0.0, 0.05, 0.0), to - foot)
	if not hit.is_empty():
		var normal: Vector3 = hit["normal"]
		var at: Vector3 = hit["position"]
		if normal.y > 0.6:
			to = at + foot
			if absf(_velocity.y) < SETTLE_SPEED * 3.0 and Vector2(_velocity.x, _velocity.z).length() < SETTLE_SPEED * 2.0:
				_settle(at)
				return
			# Bounce: most of the energy goes into the stone.
			_velocity = Vector3(_velocity.x * 0.45, absf(_velocity.y) * 0.32, _velocity.z * 0.45)
			_spin *= 0.5
		else:
			# Off a wall.
			to = at + normal * 0.06 + foot
			_velocity = _velocity.bounce(normal) * 0.4
	global_position = to
	_visual.rotation += _spin * delta


## A ray against everything static it may land on, passing through any
## character or loose body in the way (an enemy, the player, the Remnant).
func _world_ray(from: Vector3, to: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.exclude = []
	var space := get_world_3d().direct_space_state
	for i in 4:
		var hit := space.intersect_ray(_ray)
		if hit.is_empty() or hit["collider"] is StaticBody3D or hit["collider"] is AnimatableBody3D \
				or hit["collider"] is CSGShape3D:
			return hit
		var skip: Array[RID] = _ray.exclude
		skip.append(hit["rid"])
		_ray.exclude = skip
	return {}


## Lying still: if what it rests on has gone from under it, it falls again.
func _check_support() -> void:
	var foot := Vector3(0.0, _lift, 0.0)
	var below := _world_ray(global_position - foot + Vector3(0.0, 0.05, 0.0),
		global_position - foot - Vector3(0.0, 0.08, 0.0))
	if below.is_empty():
		_resting = false
		_glint.visible = false
		_velocity = Vector3.ZERO
		_fall_time = 0.0


## Inside solid at `p`: overlapping a static shape (a box, a convex prop), or
## with the inside of a surface (a back face) found in most directions out of
## it -- the exact walls are open shells, which only the second test sees.
func _is_buried(p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = LAND_MASK
	q.collide_with_areas = false
	var space := get_world_3d().direct_space_state
	for hit in space.intersect_point(q, 8):
		if hit["collider"] is StaticBody3D:
			return true
	var inside := 0
	var probe := PhysicsRayQueryParameters3D.new()
	probe.collision_mask = 2 | 256
	probe.hit_back_faces = true
	for d: Vector3 in [Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		probe.from = p
		probe.to = p + d * 4.0
		var hit := space.intersect_ray(probe)
		if not hit.is_empty() and (hit["normal"] as Vector3).dot(d) > 0.2:
			inside += 1
	# Two is enough: three let a drop stop part way out of a wall's shell.
	return inside >= 2


## Dropped from inside stone or a prop (an enemy dies with its body pushed into
## the wall -- enemies collide with simplified boxes, not the exact stone): it
## is moved out toward the player, who always stands in the open, until it is
## clear, so it can never come to rest inside anything.
func _escape_solid() -> void:
	if not _is_buried(global_position):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var goal := player.global_position + Vector3(0.0, 1.0, 0.0)
	var start := global_position
	var steps := maxi(1, ceili(start.distance_to(goal) / 0.15))
	for i in range(1, steps + 1):
		var p := start.lerp(goal, float(i) / float(steps))
		if not _is_buried(p):
			# A little further out, clear of the surface it just left.
			global_position = p + (goal - start).normalized() * 0.15
			_velocity.x *= 0.3
			_velocity.z *= 0.3
			return
	global_position = goal


## On the floor: lying on its side, still, the glint lit over it.
func _settle(floor_at: Vector3) -> void:
	_resting = true
	_support_timer = SUPPORT_CHECK
	_velocity = Vector3.ZERO
	_visual.rotation = Vector3(0.0, randf() * TAU, 0.0)
	_visual.rotation += _rest_tilt(id)
	# Re-measure: lying down changes how far it reaches below its origin.
	_lift = -_visual_bounds_y()
	global_position = floor_at + Vector3(0.0, _lift + 0.005, 0.0)
	# Come to rest inside something (a ray that starts inside a solid box never
	# sees that box -- a coffin lid sliding aside can close round a drop lying
	# on it): out toward the player, and down again. A few times at most.
	if _escapes < 3 and _is_buried(global_position + Vector3(0.0, 0.02, 0.0)):
		_escapes += 1
		_resting = false
		_escape_solid()
		_fall_time = 0.0
		return
	_glint.visible = true


func _visual_bounds_y() -> float:
	var box := Interact.drawn_bounds(self)
	return box.position.y


## How each kind lies: a potion on its side, a bone flat, a skull upright.
static func _rest_tilt(item: StringName) -> Vector3:
	match item:
		&"health_potion":
			return Vector3(0.0, 0.0, PI * 0.5)
		&"bone_fragment":
			return Vector3(PI * 0.5, 0.0, 0.0)
	return Vector3.ZERO


## --- Taken: the flight to the player --------------------------------------------

func _take_off() -> void:
	_flying = true
	_near = false
	_prompt.visible = false
	_glint.visible = false
	_flight = 0.0
	_from = global_position
	var camera := get_viewport().get_camera_3d()
	var side: Vector3 = camera.global_basis.x if camera else Vector3.RIGHT
	_via = _from + Vector3(0.0, randf_range(0.7, 1.1), 0.0) + side * randf_range(-0.4, 0.4)
	_spin = Vector3(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	_trail_mesh = ImmediateMesh.new()
	_trail_node = MeshInstance3D.new()
	_trail_node.mesh = _trail_mesh
	_trail_node.top_level = true
	_trail_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_node.custom_aabb = AABB(Vector3(-1.0e4, -1.0e4, -1.0e4), Vector3(2.0e4, 2.0e4, 2.0e4))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.35, 1.35, 1.35)
	mat.disable_fog = true
	_trail_node.material_override = mat
	add_child(_trail_node)
	_trail_node.global_transform = Transform3D.IDENTITY


func _update_flight(delta: float) -> void:
	_flight += delta
	var camera := get_viewport().get_camera_3d()
	var eye: Vector3 = camera.global_position if camera else _from + Vector3.UP
	if _visual.visible:
		var k := clampf(_flight / FLIGHT_TIME, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		# Ends below the bottom of the view, as the cage's loot does: it dives
		# out of frame into the player's hands rather than vanishing in view.
		var ahead: Vector3 = -camera.global_basis.z if camera else Vector3.FORWARD
		var down: Vector3 = -camera.global_basis.y if camera else Vector3.DOWN
		var half_fov := deg_to_rad(camera.fov * 0.5) if camera else 0.65
		var target := eye + ahead * 0.5 + down * (0.5 * tan(half_fov) * 1.35)
		var pos := _from.lerp(_via, e).lerp(_via.lerp(target, e), e)
		global_position = pos
		_visual.rotation += _spin * delta
		_visual.scale = Vector3.ONE * lerpf(1.0, 0.6, smoothstep(0.6, 1.0, k))
		_trail.push_front(pos)
		if _trail.size() > TRAIL_POINTS:
			_trail.pop_back()
		if k >= 1.0:
			_visual.visible = false
			_arrive()
	else:
		# Gone; its tail drains after it.
		if not _trail.is_empty():
			_trail.pop_back()
		if not _trail.is_empty():
			_trail.pop_back()
		if _trail.is_empty():
			queue_free()
			return
	_draw_trail(eye)


func _arrive() -> void:
	if is_instance_valid(_player) and _player.has_method("add_item"):
		_player.add_item(id, count)


func _draw_trail(eye: Vector3) -> void:
	_trail_mesh.clear_surfaces()
	if _trail.size() < 2:
		return
	var colour := Inventory.item_color(id).lightened(0.2)
	# Gathered first: a surface begun with no vertices (every segment
	# degenerate) is an error and leaves the mesh stuck mid-surface.
	var verts: Array = []
	for i in _trail.size() - 1:
		var p0: Vector3 = _trail[i]
		var p1: Vector3 = _trail[i + 1]
		var along := p1 - p0
		if along.length_squared() < 1e-8:
			continue
		var side := along.cross(eye - p0).normalized()
		var f0 := 1.0 - float(i) / float(TRAIL_POINTS)
		var f1 := 1.0 - float(i + 1) / float(TRAIL_POINTS)
		var w0 := side * TRAIL_WIDTH * f0
		var w1 := side * TRAIL_WIDTH * f1
		var c0 := Color(colour.r, colour.g, colour.b, f0 * 0.75)
		var c1 := Color(colour.r, colour.g, colour.b, f1 * 0.75)
		verts.append_array([[p0 - w0, c0], [p0 + w0, c0], [p1 + w1, c1], [p0 - w0, c0], [p1 + w1, c1], [p1 - w1, c1]])
	if verts.is_empty():
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in verts:
		_trail_mesh.surface_set_color(v[1])
		_trail_mesh.surface_add_vertex(v[0])
	_trail_mesh.surface_end()


## --- Looks --------------------------------------------------------------------

## What lies on the floor: the potion and the skull are the game's own models
## (the potion in hand, the cage skull), sized down; a bone fragment is built.
func _make_visual(item: StringName) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Visual"
	match item:
		&"health_potion":
			_add_model(holder, POTION_MODEL, 0.22, Vector3.UP)
		&"skeleton_skull":
			_add_model(holder, SKULL_MODEL, 0.2, Vector3.RIGHT)
		&"bone_fragment":
			_add_bone(holder)
		_:
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.08
			sphere.height = 0.16
			ball.mesh = sphere
			# Anything without a model of its own glows in its item colour (a
			# shard: as a gem).
			if Inventory.item_kind(item) == "Relic" or String(item).ends_with("_crystal"):
				sphere.radial_segments = 4
				sphere.rings = 2
				sphere.height = 0.3
			var glow := StandardMaterial3D.new()
			glow.albedo_color = Inventory.item_color(item).darkened(0.6)
			glow.emission_enabled = true
			glow.emission = Inventory.item_color(item)
			glow.emission_energy_multiplier = 2.0
			ball.material_override = glow
			holder.add_child(ball)
	for mi in holder.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder


## The first mesh in `path`, scaled so its extent along `axis` is `size`, and
## centred on the holder.
func _add_model(holder: Node3D, path: String, size: float, axis: Vector3) -> void:
	var mesh: Mesh = _meshes.get(path)
	if mesh == null:
		var packed := load(path) as PackedScene
		if packed == null:
			return
		var scene := packed.instantiate()
		var found := scene.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			mesh = (found[0] as MeshInstance3D).mesh
		scene.free()
		if mesh == null:
			return
		_meshes[path] = mesh
	var box := mesh.get_aabb()
	var extent := absf(box.size.dot(axis))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var sc := size / maxf(extent, 0.001)
	mi.scale = Vector3.ONE * sc
	mi.position = -box.get_center() * sc
	holder.add_child(mi)


## A splintered length of bone: a shaft with a knuckle at one end and a broken,
## jagged end at the other.
func _add_bone(holder: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.75, 0.62)
	mat.roughness = 0.85
	var shaft := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.018
	cap.height = 0.2
	cap.radial_segments = 8
	cap.rings = 2
	cap.material = mat
	shaft.mesh = cap
	holder.add_child(shaft)
	for side in [-1.0, 1.0]:
		var knob := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.026
		ball.height = 0.05
		ball.radial_segments = 8
		ball.rings = 4
		ball.material = mat
		knob.mesh = ball
		knob.position = Vector3(side * 0.016, 0.095, 0.0)
		holder.add_child(knob)
	var broken := MeshInstance3D.new()
	var shard := PrismMesh.new()
	shard.size = Vector3(0.04, 0.05, 0.03)
	shard.material = mat
	broken.mesh = shard
	broken.position = Vector3(0.006, -0.115, 0.0)
	broken.rotation = Vector3(0.0, 0.0, PI)
	holder.add_child(broken)


## A soft additive halo hanging over the drop, in the item's colour.
static func _make_glint(colour: Color) -> MeshInstance3D:
	var glint := MeshInstance3D.new()
	glint.name = "Glint"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.46, 0.46)
	glint.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Fades out where it meets the floor, instead of being cut off in a hard
	# straight line through the halo.
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 0.18
	mat.disable_fog = true
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(colour, 0.55), Color(colour, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	glint.material_override = mat
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glint.position = Vector3(0.0, 0.1, 0.0)
	return glint
