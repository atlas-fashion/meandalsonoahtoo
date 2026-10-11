extends CharacterBody3D

## THE REMNANT (2026-10-08; first called the Shade): one huge ghost that stalks
## the corridors.
##
## It drifts from one stretch of corridor to the next for as long as the level
## runs, and the player cannot fight it yet -- it is far too strong. Once it
## sees them it HUNTS: it always knows where they are and follows at a little
## over their walking pace, until they shut themselves in a hiding place
## (`scripts/hiding_spot.gd`). Then it loses them, drifts to where it last had
## them, lingers searching, and goes back to its rounds.
##
## A ghost: it floats, follows the navmesh but is not stopped by anything on it
## (doors included), shrugs off knockback, and its blows go through any guard
## (`unblockable`), and for now one blow kills (`one_shot`). The HUD reads
## `hunting` and its distance: torches go ice blue as it closes, and the view
## takes an icy grade and a tremble while it hunts (`hud._update_dread`). Built entirely in code; `maze._spawn_stalker` places
## it, and a death resets it like every other enemy.
##
## Meant to be beaten LATER, when the player is stronger: `max_health` and
## `damage_taken_scale` are the knobs. What it drops is a placeholder
## (`death_drops`, `death_coins`) until there is something worth the fight.

signal died
## Emitted when it starts hunting the player, and when it loses them.
signal hunt_changed(hunting: bool)

const MODEL := preload("res://models/ossuary_skeleton_rigged.glb")
const SHADER := preload("res://shaders/ghost.gdshader")
const ITEM_DROP := preload("res://scripts/item_drop.gd")

@export var display_name := "THE REMNANT"
@export var max_health := 5000.0
## Of every blow that lands, the share it actually takes. With the sword's 20
## a cut, 0.2 makes it ~1,250 cuts: not a fight the player can win yet.
@export_range(0.0, 1.0) var damage_taken_scale := 0.2
@export var model_scale := 1.75
## How far it floats off the floor.
@export var hover := 0.18

@export_group("Moving")
@export var wander_speed := 1.9
## Times the player's walking pace while hunting. 1.35 (was 1.07): it gains
## ~1.5 m every second the player walks, so walking away fails outright; ghost
## mode (2.5x walking for up to 4 s, 5 s to refill) still opens a lead of ~20 m
## a burst, so getting away means using it -- then breaking line of sight or
## hiding.
@export var hunt_speed_ratio := 1.35
@export var acceleration := 9.0
@export var pause_min := 0.6
@export var pause_max := 2.2

@export_group("Senses")
@export var sight_range := 26.0
## Full width of what it sees in front of it, degrees.
@export var sight_cone_degrees := 140.0
## Closer than this it notices the player whichever way it faces.
@export var sense_range := 4.5
@export var eye_height := 2.9
@export_flags_3d_physics var sight_blocking_mask := 2
## Lingering where it lost the player before it goes back to wandering.
@export var search_time := 7.0

@export_group("Strike")
@export var strike_range := 3.0
@export var strike_reach := 3.8
## Half-angle in front of it the swipe covers, degrees.
@export var strike_arc := 75.0
@export var strike_damage := 55.0
## For now, while the player has no weapon upgrades to stand against it: any
## blow that lands kills outright -- ten times the player's whole health, so
## not even ghost mode's 0.2 of a hit survives it. `strike_damage` is what it
## does once this is turned off.
@export var one_shot := true
@export var strike_push := 13.0
@export var windup_time := 0.8
@export var strike_time := 0.4
@export var recover_time := 1.0

@export_group("Death")
## Placeholder reward: item id -> count, dropped where it dies.
@export var death_drops := {&"skeleton_skull": 1}
## Placeholder reward paid straight to the player.
@export var death_coins := 150

## The ghost's blows go through any guard: `player.take_damage` reads this.
var unblockable := true
var health := 0.0
## True while it is hunting the player. Read by the HUD.
var hunting := false
## Driven by a scene (morgue.gd): no AI at all until the world resets.
var scripted := false
## Corridor points it wanders between, handed over by the maze.
var wander_spots: Array[Vector3] = []

enum State { WANDER, PAUSE, HUNT, SEARCH, WINDUP, STRIKE, RECOVER }
var state := State.WANDER

var _player: Node3D
var _agent: NavigationAgent3D
var _anim: AnimationPlayer
var _meshes: Array[GeometryInstance3D] = []
var _light: OmniLight3D
var _state_until := 0.0
var _goal := Vector3.ZERO
var _last_seen := Vector3.ZERO
var _next_repath := 0.0
var _floor_y := 0.0
var _bob := 0.0
var _anger := 0.0
var _flash := 0.0
var _look_centre := 0.0
var _dying := false
var _struck := false


func _ready() -> void:
	health = max_health
	add_to_group(&"stalker")
	# Hit by the sword and the slam (layer 3); blocks the player (layer 1). Moves
	# by hand along the navmesh, so it needs no mask at all -- nothing stops it.
	collision_layer = 1 | 4
	collision_mask = 0
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 3.1
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, 1.55, 0.0)
	add_child(cs)
	_floor_y = global_position.y - hover

	_agent = NavigationAgent3D.new()
	_agent.radius = 0.4
	_agent.height = 1.8
	_agent.path_desired_distance = 0.9
	_agent.target_desired_distance = 1.2
	_agent.avoidance_enabled = false
	add_child(_agent)

	_build_visual()
	preload("res://scripts/enemy_health_bar.gd").attach(self)
	_pick_wander()


func _build_visual() -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var model: Node3D = MODEL.instantiate()
	model.name = "Model"
	# The skeleton faces +Z as imported; flipped like enemy.tscn's.
	model.scale = Vector3(-model_scale, model_scale, -model_scale)
	model.position = Vector3(0.0, 0.0, 0.0)
	visual.add_child(model)

	var body := ShaderMaterial.new()
	body.shader = SHADER
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.material_override = body
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_meshes.append(mi)

	# A tattered shroud hanging from the shoulders.
	var cloth := ShaderMaterial.new()
	cloth.shader = SHADER
	cloth.set_shader_parameter("flutter", 0.05)
	cloth.set_shader_parameter("body_alpha", 0.2)
	cloth.set_shader_parameter("rim_alpha", 0.55)
	cloth.set_shader_parameter("fade_height", 1.6)
	var shroud := MeshInstance3D.new()
	shroud.name = "Shroud"
	var tube := CylinderMesh.new()
	tube.top_radius = 0.38 * model_scale / 1.75
	tube.bottom_radius = 1.05 * model_scale / 1.75
	tube.height = 2.3 * model_scale / 1.75
	tube.cap_top = false
	tube.cap_bottom = false
	tube.radial_segments = 20
	tube.rings = 10
	shroud.mesh = tube
	shroud.material_override = cloth
	shroud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shroud.position = Vector3(0.0, 0.5 + tube.height * 0.5, 0.0)
	visual.add_child(shroud)
	_meshes.append(shroud)

	# A cold glow where its head is.
	var skeleton := model.find_children("*", "Skeleton3D", true, false)
	if not skeleton.is_empty():
		var sk := skeleton[0] as Skeleton3D
		var head := sk.find_bone("head")
		if head >= 0:
			var attach := BoneAttachment3D.new()
			attach.bone_name = "head"
			sk.add_child(attach)
			var glow := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.45, 0.45)
			glow.mesh = quad
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.no_depth_test = false
			mat.albedo_color = Color(0.7, 0.88, 1.0, 0.9)
			var grad := GradientTexture2D.new()
			grad.fill = GradientTexture2D.FILL_RADIAL
			grad.fill_from = Vector2(0.5, 0.5)
			grad.fill_to = Vector2(1.0, 0.5)
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			grad.gradient = g
			mat.albedo_texture = grad
			glow.material_override = mat
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glow.position = Vector3(0.0, 0.12, 0.0)
			attach.add_child(glow)

	if Graphics.effects:
		_light = OmniLight3D.new()
		_light.light_color = Color(0.62, 0.8, 1.0)
		_light.light_energy = 1.4
		_light.omni_range = 7.0
		_light.shadow_enabled = false
		_light.light_specular = 0.1
		_light.distance_fade_enabled = true
		_light.distance_fade_begin = 32.0
		_light.distance_fade_length = 8.0
		_light.position = Vector3(0.0, 2.2, 0.0)
		add_child(_light)

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0] as AnimationPlayer
	if _anim != null:
		for looping in [&"idle", &"walk", &"run"]:
			if _anim.has_animation(looping):
				_anim.get_animation(looping).loop_mode = Animation.LOOP_LINEAR
		for from in _anim.get_animation_list():
			for to in _anim.get_animation_list():
				if from != to:
					_anim.set_blend_time(from, to, 0.25)
		_play(&"idle")
	_apply_look()


# --- Per frame -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _dying:
		return
	if scripted:
		# A scene is driving it (the morgue): no thinking, just floating there.
		_bob += delta
		_hold(delta)
		return
	var now := _now()
	_bob += delta
	var player := _resolve_player()
	if player == null:
		return
	var hidden: bool = (player.has_method("is_hidden") and player.is_hidden()) or _warded(player)
	var dead: bool = player.get("_dead") == true
	var to_player := player.global_position - global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	var distance := flat.length()

	match state:
		State.WINDUP:
			_face(flat, delta, 10.0)
			_hold(delta)
			if now >= _state_until:
				_strike(player, flat, distance, hidden or dead)
			return
		State.STRIKE:
			_hold(delta)
			if now >= _state_until:
				state = State.RECOVER
				_state_until = now + recover_time
				_play(&"recover", recover_time)
			return
		State.RECOVER:
			_hold(delta)
			if now >= _state_until:
				state = State.HUNT if hunting else State.SEARCH
				if state == State.SEARCH:
					_state_until = now + search_time
			return

	if hunting:
		if hidden or dead:
			# Lost them: drift to where they were and look about.
			_set_hunting(false)
			state = State.SEARCH
			_goal = _last_seen
			# The search starts once it gets there.
			_state_until = now + search_time \
				+ global_position.distance_to(_goal) / (wander_speed * 1.3)
		else:
			_last_seen = player.global_position
			if distance <= strike_range and now >= _state_until and _clear_to(player):
				_begin_windup()
				return
			_travel(player.global_position, _hunt_speed(player), delta)
			return

	# Not hunting: anything it sees, it hunts.
	if not hidden and not dead and _can_see(player, distance):
		_set_hunting(true)
		return

	match state:
		State.SEARCH:
			if _travel(_goal, wander_speed * 1.3, delta):
				_look_about(delta)
			if now >= _state_until:
				_pick_wander()
		State.PAUSE:
			_hold(delta)
			_look_about(delta)
			if now >= _state_until:
				_pick_wander()
		_:
			if _travel(_goal, wander_speed, delta):
				state = State.PAUSE
				_state_until = now + randf_range(pause_min, pause_max)
				_look_centre = rotation.y


func _process(delta: float) -> void:
	var want := 0.0
	if hunting:
		want = 0.55
	if state == State.WINDUP or scripted:
		want = 1.0
	_anger = move_toward(_anger, want, delta * 2.5)
	_flash = maxf(_flash - delta * 4.0, 0.0)
	_apply_look()


func _apply_look() -> void:
	var base := global_position.y - hover
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter(&"base_y", base)
			mi.set_instance_shader_parameter(&"anger", _anger)
			mi.set_instance_shader_parameter(&"flash", _flash)
	if _light != null:
		_light.light_energy = 1.4 + 1.6 * _anger + 2.0 * _flash


# --- Moving ---------------------------------------------------------------------

## Steps along the navmesh toward `goal`. Returns true once there.
func _travel(goal: Vector3, speed: float, delta: float) -> bool:
	var now := _now()
	if now >= _next_repath or _agent.target_position.distance_to(goal) > 1.5:
		_next_repath = now + 0.25
		_agent.target_position = goal
	var flat_gap := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
	var arrived := flat_gap < 1.3 or _agent.is_navigation_finished()
	var desired := Vector3.ZERO
	var next := goal
	if not arrived:
		next = _agent.get_next_path_position()
		var to := next - global_position
		to.y = 0.0
		if to.length() > 0.05:
			desired = to.normalized() * speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	global_position.x += velocity.x * delta
	global_position.z += velocity.z * delta
	_float(next.y if not arrived else _floor_y, delta)
	var flat_v := Vector3(velocity.x, 0.0, velocity.z)
	if flat_v.length() > 0.2:
		_face(flat_v, delta, 6.0)
	_animate_move(flat_v.length())
	return arrived


## Standing still: slows to a stop and keeps floating.
func _hold(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * 1.5 * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * 1.5 * delta)
	global_position.x += velocity.x * delta
	global_position.z += velocity.z * delta
	_float(_floor_y, delta)
	if state == State.PAUSE or state == State.SEARCH:
		_animate_move(Vector2(velocity.x, velocity.z).length())


## Floats `hover` over the floor the path is on, with a slow bob.
func _float(floor_y: float, delta: float) -> void:
	_floor_y = lerpf(_floor_y, floor_y, 1.0 - exp(-4.0 * delta))
	global_position.y = _floor_y + hover + sin(_bob * 1.3) * 0.07


func _face(direction: Vector3, delta: float, rate: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-rate * delta))


func _look_about(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _look_centre + sin(_bob * 0.9) * 1.2, 1.0 - exp(-2.0 * delta))


func _pick_wander() -> void:
	state = State.WANDER
	if wander_spots.is_empty():
		_goal = global_position
		return
	# Somewhere a fair way off, so it roams the map instead of pacing.
	var best := wander_spots[randi() % wander_spots.size()]
	for i in 6:
		var spot := wander_spots[randi() % wander_spots.size()]
		var d := spot.distance_to(global_position)
		if d > 12.0 and d < 45.0:
			best = spot
			break
	_goal = best


func _hunt_speed(player: Node3D) -> float:
	var pace: float = player.get("move_speed") if player.get("move_speed") != null else 4.25
	return pace * hunt_speed_ratio


# --- Senses ---------------------------------------------------------------------

func _can_see(player: Node3D, distance: float) -> bool:
	if distance > sight_range:
		return false
	if distance > sense_range:
		var facing := -global_basis.z
		facing.y = 0.0
		var to := player.global_position - global_position
		to.y = 0.0
		if facing.length_squared() > 0.0001 and to.length_squared() > 0.0001:
			if rad_to_deg(facing.normalized().angle_to(to.normalized())) > sight_cone_degrees * 0.5:
				return false
	return _clear_to(player)


## Nothing solid between its eyes and the player's chest.
func _clear_to(player: Node3D) -> bool:
	var from := global_position + Vector3(0.0, eye_height, 0.0)
	var to := player.global_position + Vector3(0.0, 1.0, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(from, to, sight_blocking_mask)
	ray.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _set_hunting(on: bool) -> void:
	if hunting == on:
		return
	hunting = on
	if on:
		state = State.HUNT
		_state_until = 0.0
		var player := _resolve_player()
		if player != null:
			_last_seen = player.global_position
	hunt_changed.emit(on)


func _resolve_player() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


# --- The strike -----------------------------------------------------------------

func _begin_windup() -> void:
	state = State.WINDUP
	_state_until = _now() + windup_time
	_struck = false
	_play(&"windup", windup_time)


func _strike(player: Node3D, flat: Vector3, distance: float, untouchable: bool) -> void:
	state = State.STRIKE
	_state_until = _now() + strike_time
	_play(&"attack_1" if _anim != null and _anim.has_animation(&"attack_1") else &"slam", strike_time)
	if untouchable or distance > strike_reach:
		return
	var facing := -global_basis.z
	facing.y = 0.0
	if flat.length_squared() > 0.0001 and facing.length_squared() > 0.0001 \
			and rad_to_deg(facing.normalized().angle_to(flat.normalized())) > strike_arc:
		return
	var away := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	if player.has_method("take_damage"):
		var blow := strike_damage
		if one_shot:
			blow = maxf(strike_damage, float(player.get("max_health")) * 10.0)
		player.take_damage(blow, away, self)
	if player.has_method("apply_knockback"):
		player.apply_knockback(away * strike_push + Vector3(0.0, 3.5, 0.0), 0.3)
	if player.get("_shake") != null:
		player.set("_shake", maxf(float(player.get("_shake")), 0.6))
	_struck = true


# --- Scripted: the morgue ------------------------------------------------------
##
## The royal sarcophagus's scene (morgue.gd) takes it over: it is suddenly there
## behind the player, rearing up, and brings its arms down. Its AI stays off
## until the world resets on the player's death and a fresh one is spawned.

## Appears at `at` (floor level) facing `face`, out of nothing: a flash and a
## fade up from invisible.
func scripted_appear(at: Vector3, face: Vector3) -> void:
	scripted = true
	_set_hunting(false)
	# Not PAUSE or SEARCH: `_hold` plays the idle loop every frame in those,
	# which overwrote the windup and the slam the instant they started.
	state = State.STRIKE
	velocity = Vector3.ZERO
	_floor_y = at.y
	global_position = at + Vector3(0.0, hover, 0.0)
	var d := face - global_position
	d.y = 0.0
	if d.length_squared() > 0.0001:
		rotation.y = atan2(-d.x, -d.z)
	_anger = 1.0
	_flash = 1.0
	_play(&"idle")
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.transparency = 1.0
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		for mi in _meshes:
			if is_instance_valid(mi):
				mi.transparency = 1.0 - k
		, 0.0, 1.0, 0.35)


## Rears back over `time` seconds.
func scripted_windup(time: float) -> void:
	_play(&"windup", time)


## Brings it down over `time` seconds.
func scripted_slam(time: float) -> void:
	_play(&"attack_1" if _anim != null and _anim.has_animation(&"attack_1") else &"attack_2", time)
	_flash = 0.6


## Where its head is, for a camera to look at.
func head_point() -> Vector3:
	return global_position + Vector3(0.0, 1.62 * model_scale, 0.0)


## Shut in a sealed room, the player is out of its reach: being trapped in there
## with it would be a death nobody could avoid. (The puzzle rooms sealed; the
## chest rooms that replaced them, dungeon_room.gd, never do, but keep the hook.)
func _warded(player: Node3D) -> bool:
	for room in get_tree().get_nodes_in_group(&"chest_room"):
		if room.call("is_warding", player.global_position):
			return true
	return false


# --- Taking blows ---------------------------------------------------------------

func take_damage(amount: float, _from_direction: Vector3 = Vector3.ZERO) -> void:
	if _dying:
		return
	health = maxf(health - amount * damage_taken_scale, 0.0)
	_flash = 1.0
	# Being struck tells it exactly where you are.
	var player := _resolve_player()
	if player != null and not (player.has_method("is_hidden") and player.is_hidden()):
		_set_hunting(true)
	if health <= 0.0:
		_die()


## Nothing moves it.
func apply_knockback(_impulse: Vector3, _stun_time := 0.0) -> void:
	pass


## Something made a noise at it (a door kicked in nearby): it comes hunting.
func alert() -> void:
	var player := _resolve_player()
	if player != null and not (player.has_method("is_hidden") and player.is_hidden()):
		_set_hunting(true)


func _die() -> void:
	_dying = true
	_set_hunting(false)
	died.emit()
	var parent := get_parent()
	var at := global_position - Vector3(0.0, hover, 0.0)
	for id in death_drops:
		ITEM_DROP.spawn(parent, at + Vector3(0.0, 0.6, 0.0), id, int(death_drops[id]))
	var player := _resolve_player()
	if player != null and death_coins > 0 and player.has_method("add_currency"):
		player.add_currency(death_coins)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("announce"):
		hud.announce("%s IS BANISHED" % display_name, "Its wailing fades from the halls")
	# Flares and thins away.
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		_flash = k
		for mi in _meshes:
			if is_instance_valid(mi):
				mi.transparency = 1.0 - k
		, 1.0, 0.0, 1.6)
	t.tween_callback(queue_free)


# --- Animation ------------------------------------------------------------------

func _animate_move(speed: float) -> void:
	if _anim == null:
		return
	var stride := model_scale / 0.94
	if speed > 2.6 and _anim.has_animation(&"run"):
		_play_loop(&"run", clampf(speed / (3.56 * stride), 0.6, 1.6))
	elif speed > 0.25 and _anim.has_animation(&"walk"):
		_play_loop(&"walk", clampf(speed / (1.45 * stride), 0.5, 1.8))
	else:
		_play_loop(&"idle", 1.0)


func _play_loop(clip: StringName, rate: float) -> void:
	if _anim.current_animation == clip:
		_anim.speed_scale = rate
		return
	_anim.play(clip, -1.0, 1.0)
	_anim.speed_scale = rate


## Plays `clip` stretched to last `duration` (0 = its own length).
func _play(clip: StringName, duration := 0.0) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	var length: float = _anim.get_animation(clip).length
	_anim.speed_scale = 1.0
	_anim.play(clip, -1.0, length / duration if duration > 0.0 and length > 0.0 else 1.0)
	_anim.seek(0.0, true)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
