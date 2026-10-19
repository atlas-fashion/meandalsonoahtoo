extends Node3D

## Rats in the player's hands (2026-10-18): a child of the player's head, set up
## by player.gd `_ready` as `player.rats`.
##
## LIVE RATS (a utility quick item, inventory.gd): chosen on the quick wheel
## (player.gd `use_consumable` -> `take_rat`), or just caught with E (rat.gd
## `grab` -> `hold_caught`), one is HELD: the user's rat (rat_look.gd) hung by
## the tip of its tail from a pinch lower right of the view, writhing (its
## Dangle clip) and twisting, swinging and shaking on its tail -- hardest just
## after it is caught. The weapon goes down meanwhile. LMB throws it
## (`throw_held` -> `throw_rat`, from where it hangs, along the view,
## tumbling; rat.gd takes it from there -- it scares what is near where it
## lands and runs off out of sight); RMB, choosing a weapon, drinking or
## anything that takes the hands puts it away (still carried).
##
## THE ROBOT RAT (a utility item on the weapon wheel, built at the workbench
## from a live rat and CRAFT_COST gold crystals): in hand it sits in the palm,
## lower right. The attack key (`deploy`) sets it down a step ahead and the view
## goes to its eyes (robot_rat.gd's camera): the player's movement keys drive
## it, the mouse / right stick turn it, and the attack key again DETONATES it --
## BLAST_DAMAGE to everything within BLAST_RADIUS that stone does not shelter,
## thrown outward (the spear's firepot burst, spear.gd `_blast_visual`). Not
## detonated, it goes off by itself when the FUSE runs out. No cooldown (the
## user, 2026-10-18): another can be set down at once. The blast hurts the
## player too, if they are in it (`_blast_player`).
##
## While driving, `player.remote_view` is on: the body stands where it was,
## takes no input (player.gd), opens no wheel, inventory or map; `hands_busy`
## puts the sword, torch and potion away. The body can still be hit -- the
## overlay says so. Death, a scene or the rat falling out of the world sets it
## off at once.

const RAT_MODEL := preload("res://scripts/rat_model.gd")
const RAT_LOOK := preload("res://scripts/rat_look.gd")
const RAT_SCRIPT := preload("res://scripts/rat.gd")
const ROBOT_SCRIPT := preload("res://scripts/robot_rat.gd")

## Throwing a live rat: along the view, a little up, plus some of the player's
## own run; no faster than one every THROW_EVERY.
const THROW_SPEED := 11.0
const THROW_LIFT := 3.0
const THROW_EVERY := 0.6

## A live rat held: the pinch its tail tip hangs from (head space; it hangs
## down from there into the lower right of the view), how fast it comes up
## into view, and how it moves on its tail -- twisting (yaw, radians), swinging
## (pitch / roll), shaking (fast jitter) -- all doubled while CAUGHT_FIT s of
## just-caught fury wear off.
const PINCH := Vector3(0.22, 0.02, -0.62)
const HOLD_RAISE := 0.22
const HOLD_TWIST := 1.0
const HOLD_SWING := 0.2
const HOLD_SHAKE := 0.06
const CAUGHT_FIT := 1.6
## Holding still, it faces partly toward the player (yaw of the dangling rat).
const HOLD_FACING := 2.4

## The robot rat.
const FUSE := 10.0
const BLAST_DAMAGE := 200.0
const BLAST_RADIUS := 4.0
const BLAST_PUSH := 12.0
const BLAST_STAGGER := 1.0
## The player's capsule, for whether the blast reaches them (scenes/player.tscn).
const PLAYER_RADIUS := 0.4
const PLAYER_HEIGHT := 1.8
## Gold crystals, with one live rat, at the workbench (workbench.gd).
const CRAFT_COST := 1
## Set down this far ahead of the feet (less if stone is nearer).
const PLACE_AHEAD := 1.1
## Fallen this far below where it was set down: lost, so it goes off.
const FALL_LIMIT := 30.0
## In the palm: where (head space), turned side on with its nose in toward the
## middle of the view (from behind, its back crystal was all that read), drawn
## pulled toward the eye as the sword is (player.gd `_draw_sword_on_top`) so it
## never pushes into a wall.
const HELD_AT := Vector3(0.26, -0.22, -0.5)
const HELD_TURN := Vector3(0.0, 1.3, 0.6)
const HELD_SCALE := 0.9

const CYAN := Color(0.0, 0.91, 1.0)

## The player (player.gd); untyped, as its own methods are called on it.
var player

var _held: Node3D
var _held_tail: Node3D
var _raise := 0.0
var _rat: CharacterBody3D
var _rat_from := Vector3.ZERO
var _fuse_left := 0.0
var _next_throw := 0.0
var _clock := 0.0
var _hurt_flash := 0.0
var _last_health := 0.0

## A live rat in the hand (`take_rat` / `hold_caught`).
var holding := false
var _live: Node3D
var _live_up := 0.0
var _fit := 0.0
var _hold_t := 0.0

var _overlay: CanvasLayer
var _frame: Control
var _font: Font


func setup(p: CharacterBody3D) -> void:
	player = p
	name = "RatHands"
	_held = RAT_MODEL.build(true)
	_held.name = "HeldRobotRat"
	_held.scale = Vector3.ONE * HELD_SCALE
	_held.visible = false
	add_child(_held)
	_held_tail = _held.get_node("Tail")
	var depth: float = player.get("sword_draw_depth")
	for g in RAT_MODEL.parts(_held):
		var mi := g as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var copy := mi.mesh.surface_get_material(i).duplicate() as BaseMaterial3D
			copy.use_z_clip_scale = true
			copy.z_clip_scale = depth
			mi.set_surface_override_material(i, copy)
	_font = ThemeDB.fallback_font
	if player.has_signal("health_changed"):
		player.connect("health_changed", _on_health_changed)
	_last_health = float(player.get("health"))
	_build_live(depth)
	# Choosing a weapon on the wheel puts a held rat away.
	if player.has_signal("selection_changed"):
		player.connect("selection_changed", func(_slot: int) -> void: put_away())


## The held live rat: placed in world space every frame (top level), its clip
## stepped by hand just before so the tail tip is where it hangs from this
## frame, and drawn pulled toward the eye like the sword.
func _build_live(depth: float) -> void:
	_live = RAT_LOOK.new()
	_live.top_level = true
	_live.visible = false
	add_child(_live)
	var anim: AnimationPlayer = _live.get("anim")
	if anim != null:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_live.call("play", &"Dangle")
	var mi: MeshInstance3D = _live.get("mesh")
	if mi != null:
		for i in mi.mesh.get_surface_count():
			var copy := mi.get_active_material(i).duplicate() as BaseMaterial3D
			copy.use_z_clip_scale = true
			copy.z_clip_scale = depth
			mi.set_surface_override_material(i, copy)


func is_driving() -> bool:
	return _rat != null and is_instance_valid(_rat)




func fuse_left() -> float:
	return _fuse_left if is_driving() else -1.0


## For the HUD's attack icons (player.gd `attack_cooldowns`): one tile, the
## set-down / detonate key; never shaded (no cooldown).
func attack_cooldowns() -> Array:
	return [[&"rat_bomb", 0.0, FUSE, "LMB"]]


## A respawn: nothing in flight, nothing being driven.
func reset() -> void:
	if is_driving():
		_rat.queue_free()
		_end_view()
	_rat = null
	holding = false
	_next_throw = 0.0


func _busy() -> bool:
	return player.get("_dead") == true or player.in_cutscene or player.ui_open or player.is_hidden() \
		or player.get("climbing") == true or player.get("_ghosting") == true or is_driving()


# --- Live rats -----------------------------------------------------------------------

## The quick wheel's live rat: up into the hand, by the tail. Already holding
## one, the wheel throws it. False when the hands are not free.
func take_rat(slot: int) -> bool:
	if player.inventory.id_at(slot) != &"live_rat":
		return false
	if holding:
		return throw_held()
	if _busy() or player.call("is_drinking"):
		return false
	holding = true
	_live_up = 0.0
	_hold_t = 0.0
	return true


## Just caught with E (rat.gd `grab`, already in the inventory): in the hand at
## once, kicking.
func hold_caught() -> void:
	if _busy():
		return
	holding = true
	_live_up = 0.4
	_fit = CAUGHT_FIT


## Down out of the hand; still carried.
func put_away() -> void:
	holding = false


## LMB with a rat held: thrown from where it hangs.
func throw_held() -> bool:
	var slot: int = player.inventory.find(&"live_rat")
	if slot < 0:
		holding = false
		return false
	var at: Vector3 = _live.global_position if _live.visible else Vector3.INF
	if throw_rat(slot, at):
		holding = false
		# Gone from the hand at once: it is the one flying now.
		_live_up = 0.0
		return true
	return false


## Throws one live rat from slot `slot`, from `from` (where a held one hangs;
## INF: in front of the eye). False (and the rat kept) when the hands are not
## free.
func throw_rat(slot: int, from := Vector3.INF) -> bool:
	if _busy() or _clock < _next_throw or player.inventory.id_at(slot) != &"live_rat":
		return false
	var cam: Camera3D = player.camera
	var fwd := -cam.global_basis.z
	var eye := cam.global_position
	if from == Vector3.INF:
		from = eye + fwd * 0.35 + Vector3(0.0, -0.12, 0.0)
	# Never out through stone right in front of the face.
	var q := PhysicsRayQueryParameters3D.create(eye, from, 2 | 256)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		from = eye
	var rat := CharacterBody3D.new()
	rat.set_script(RAT_SCRIPT)
	player.get_parent().add_child(rat)
	var run: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z) * 0.5
	rat.call("throw", from, fwd * THROW_SPEED + Vector3.UP * THROW_LIFT + run)
	player.inventory.take(slot, 1)
	_next_throw = _clock + THROW_EVERY
	return true


# --- The robot rat -------------------------------------------------------------------

## The attack key with the robot rat in hand: set it down and see through it.
func deploy() -> bool:
	if _busy() or not player.is_on_floor():
		return false
	var slot: int = player.selected_slot
	if player.inventory.id_at(slot) != &"robot_rat":
		return false
	var space := get_world_3d().direct_space_state
	var fwd: Vector3 = -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var waist: Vector3 = player.global_position + Vector3(0.0, 0.4, 0.0)
	var ahead := waist + fwd * PLACE_AHEAD
	var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(waist, ahead, 2 | 256))
	if not wall.is_empty():
		ahead = (wall["position"] as Vector3) - fwd * 0.25
	var at: Vector3 = player.global_position
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3(0.0, -2.0, 0.0), 1 | 256,
		[player.get_rid()]))
	if not down.is_empty():
		at = down["position"]
	player.inventory.take(slot, 1)
	_rat = CharacterBody3D.new()
	_rat.set_script(ROBOT_SCRIPT)
	player.get_parent().add_child(_rat)
	_rat.call("setup", player)
	_rat.global_position = at + Vector3(0.0, 0.02, 0.0)
	_rat.rotation.y = player.rotation.y
	_rat_from = _rat.global_position
	_fuse_left = FUSE
	_begin_view()
	return true


func _begin_view() -> void:
	player.set("remote_view", true)
	player.hands_busy = true
	if player.has_method("_end_block"):
		player.call("_end_block")
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	(_rat.get("camera") as Camera3D).make_current()
	_hurt_flash = 0.0
	_last_health = float(player.get("health"))
	_show_overlay(true)


func _end_view() -> void:
	player.set("remote_view", false)
	player.hands_busy = false
	if player.camera != null:
		player.camera.make_current()
	_show_overlay(false)


## Goes off where it stands: the blast, then the view comes home.
func detonate() -> void:
	if not is_driving():
		return
	var at := _rat.global_position + Vector3(0.0, 0.15, 0.0)
	_blast(at)
	_rat.queue_free()
	_rat = null
	_fuse_left = 0.0
	_end_view()


## Everything damageable within BLAST_RADIUS that stone does not shelter takes
## BLAST_DAMAGE, whole (the spear's falls off; this is a bomb), and is thrown
## outward, staggered. Returns how many were struck.
func _blast(at: Vector3) -> int:
	var space := get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = BLAST_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = player.hitbox.collision_mask
	q.exclude = [player.get_rid()]
	var seen := {}
	var struck := 0
	for hit in space.intersect_shape(q, 32):
		var body := hit["collider"] as Node3D
		if body == null or seen.has(body):
			continue
		seen[body] = true
		if not body.has_method("take_damage"):
			continue
		var centre := body.global_position + Vector3(0.0, 0.9, 0.0)
		var ray := PhysicsRayQueryParameters3D.create(at, centre, player.geometry_mask)
		ray.exclude = [player.get_rid()]
		var wall := space.intersect_ray(ray)
		if not wall.is_empty() and (wall["position"] as Vector3).distance_to(at) > 0.4:
			continue
		var away := centre - at
		away = away / maxf(away.length(), 0.01)
		body.call("take_damage", BLAST_DAMAGE, away)
		var flat := Vector3(away.x, 0.0, away.z)
		if flat.length_squared() > 0.0001:
			flat = flat.normalized()
		player.knock(body, flat * BLAST_PUSH + Vector3(0.0, 4.0, 0.0), 0.6, BLAST_STAGGER)
		if body.has_method("alert"):
			body.call("alert")
		player.hit_landed.emit(body)
		struck += 1
	_blast_player(at)
	var near: float = player.global_position.distance_to(at)
	player.set("_shake", maxf(float(player.get("_shake")), clampf(1.0 - near / 25.0, 0.15, 0.9)))
	if player.spear != null and player.spear.has_method("_blast_visual"):
		player.spear.call("_blast_visual", at)
	return struck


## The player is not spared (the user, 2026-10-18): within BLAST_RADIUS of
## their body (its capsule, as the enemies' colliders are met by the sphere)
## and not sheltered by stone, they take BLAST_DAMAGE too -- through
## take_damage, so armor and the sandbox's god switch apply -- and are thrown
## back. Returns whether they were caught.
func _blast_player(at: Vector3) -> bool:
	if player.get("_dead") == true:
		return false
	var feet: Vector3 = player.global_position
	var spine := Vector3(feet.x, clampf(at.y, feet.y + PLAYER_RADIUS, feet.y + PLAYER_HEIGHT - PLAYER_RADIUS), feet.z)
	if spine.distance_to(at) - PLAYER_RADIUS > BLAST_RADIUS:
		return false
	var centre := feet + Vector3(0.0, 0.9, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(at, centre, player.geometry_mask)
	ray.exclude = [player.get_rid()]
	var wall := get_world_3d().direct_space_state.intersect_ray(ray)
	if not wall.is_empty() and (wall["position"] as Vector3).distance_to(at) > 0.4:
		return false
	var away := centre - at
	away = away / maxf(away.length(), 0.01)
	player.take_damage(BLAST_DAMAGE, away)
	var flat := Vector3(away.x, 0.0, away.z)
	if flat.length_squared() > 0.0001:
		player.apply_knockback(flat.normalized() * BLAST_PUSH * 0.6 + Vector3(0.0, 3.0, 0.0))
	return true


# --- Each tick -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	if not is_driving():
		if _rat != null:
			# Freed by something else (the level rebuilt): the view comes home.
			_rat = null
			_end_view()
		return
	# Death, a scene, or lost down a hole: it goes off now.
	if player.get("_dead") == true or player.in_cutscene \
			or _rat.global_position.y < _rat_from.y - FALL_LIMIT:
		detonate()
		return
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		detonate()
		return
	var steer := Vector2.ZERO
	if not player.ui_open:
		steer = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		# The right stick turns it, as it turns the player (player.gd `_pad_look`).
		var v := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
		if v != Vector2.ZERO:
			v *= v.length()
			var k: float = float(player.get("pad_look_speed")) * Graphics.mouse_sensitivity * delta
			_rat.call("turn", -v.x * k, -v.y * k * float(player.get("pad_pitch_share")))
	_rat.set("move", steer)
	# Kept still where it was left.
	player.velocity.x = 0.0
	player.velocity.z = 0.0


func _unhandled_input(event: InputEvent) -> void:
	# A live rat held: the attack key throws it, block puts it away, the other
	# attacks do nothing (the weapon is down). This node is under the player's
	# head, so it hears the keys before player.gd does.
	if holding and not is_driving() and not player.ui_open \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.is_action_pressed("attack") and not event.is_echo():
			throw_held()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("block") and not event.is_echo():
			put_away()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("thrust") or event.is_action_pressed("slam"):
			get_viewport().set_input_as_handled()
		return
	if not is_driving() or player.ui_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var k: float = player.call("_look_scale")
		_rat.call("turn", -m.relative.x * k, -m.relative.y * k)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("attack") and not event.is_echo():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			detonate()
		get_viewport().set_input_as_handled()
		return
	# Nothing else the hands do while the eyes are elsewhere.
	for action: StringName in [&"thrust", &"slam", &"block", &"interact", &"jump"]:
		if InputMap.has_action(action) and (event.is_action_pressed(action) or event.is_action_released(action)):
			get_viewport().set_input_as_handled()
			return


func _process(delta: float) -> void:
	if player == null:
		return
	_update_live(delta)
	# The robot rat in the palm while it is the weapon in hand.
	var held: bool = player.held_item() == &"robot_rat" and not player.hands_busy and not is_driving() \
		and not player.is_hidden() and player.get("_dead") != true and not holding
	_raise = move_toward(_raise, 1.0 if held else 0.0, delta / 0.2)
	_held.visible = _raise > 0.01
	if _held.visible:
		var k := _raise * _raise * (3.0 - 2.0 * _raise)
		var at := HELD_AT
		_held.position = (at + Vector3(0.05, -0.45, 0.2)).lerp(at, k)
		_held.rotation = HELD_TURN + Vector3(sin(_clock * 3.1) * 0.02, 0.0, 0.0)
		_held_tail.rotation.y = sin(_clock * 2.3) * 0.35
		_held_tail.rotation.x = 0.5
	_hurt_flash = maxf(_hurt_flash - delta / 1.2, 0.0)
	if _frame != null and _overlay.visible:
		_frame.queue_redraw()


## The held rat: let go if the hands are wanted or it is no longer carried;
## otherwise hung by its tail tip from PINCH -- twisting round on the tail,
## swinging, shaking, writhing (Dangle, faster in a fit) -- and eased up into
## view as it is taken out, down as it is put away.
func _update_live(delta: float) -> void:
	if holding and (_busy() or player.call("is_drinking") or player.hands_busy \
			or player.inventory.count(&"live_rat") <= 0):
		holding = false
	_live_up = move_toward(_live_up, 1.0 if holding else 0.0, delta / HOLD_RAISE)
	_live.visible = _live_up > 0.01
	if not _live.visible:
		return
	_hold_t += delta
	_fit = maxf(_fit - delta, 0.0)
	var fury := 1.0 + clampf(_fit / CAUGHT_FIT, 0.0, 1.0)
	var t := _hold_t
	var anim: AnimationPlayer = _live.get("anim")
	if anim != null:
		anim.speed_scale = 1.0 + 0.8 * (fury - 1.0)
		anim.advance(delta)
	var yaw := HOLD_FACING + HOLD_TWIST * fury * (0.7 * sin(t * 2.3) + 0.3 * sin(t * 5.7 + 1.1))
	var shake := HOLD_SHAKE * fury
	var pitch := HOLD_SWING * sin(t * 3.1) + shake * (sin(t * 31.0) + 0.6 * sin(t * 47.0))
	var roll := HOLD_SWING * 0.8 * sin(t * 2.6 + 1.0) + shake * sin(t * 37.0 + 2.0)
	var head := get_parent() as Node3D
	var up := _live_up * _live_up * (3.0 - 2.0 * _live_up)
	var pinch: Vector3 = head.global_transform * (PINCH + Vector3(0.0, -0.6 * (1.0 - up), 0.0))
	# Turned with the body (not the view's pitch: it hangs plumb), then about
	# the tail, and hung so its tip is at the pinch: the swing pivots about the
	# fingers.
	var basis := Basis(Vector3.UP, (player as Node3D).global_rotation.y) * Basis.from_euler(Vector3(pitch, yaw, roll))
	_live.global_transform = Transform3D(basis, pinch)
	var tip: Vector3 = _live.call("tail_tip")
	_live.global_position += pinch - tip


func _on_health_changed(current: float, _maximum: float) -> void:
	if is_driving() and current < _last_health:
		_hurt_flash = 1.0
	_last_health = current


# --- The view through its eyes -------------------------------------------------------

func _show_overlay(on: bool) -> void:
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.name = "RatEyesOverlay"
		_overlay.layer = 30
		get_tree().root.add_child(_overlay)
		_frame = Control.new()
		_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.draw.connect(_draw_overlay)
		_overlay.add_child(_frame)
	_overlay.visible = on


func _exit_tree() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null


## Corner brackets in the eyes' colour, the fuse counting down along the top
## (red for its last three seconds), the keys along the foot, and a warning
## when the body left behind is struck. Lines and text only: no full-screen
## fill, so it costs nothing on the per-pixel budget.
func _draw_overlay() -> void:
	var size := _frame.size
	var low := _fuse_left <= 3.0
	var pulse := 0.5 + 0.5 * sin(_clock * (14.0 if low else 4.0))
	var col := CYAN.lerp(Color(1.0, 0.25, 0.2), 1.0 if low else 0.0)
	var edge := Color(col, 0.55 + 0.3 * pulse)
	var m := 34.0
	var arm := 70.0
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var p := Vector2(m if corner.x == 0 else size.x - m, m if corner.y == 0 else size.y - m)
		var sx := 1.0 if corner.x == 0 else -1.0
		var sy := 1.0 if corner.y == 0 else -1.0
		_frame.draw_line(p, p + Vector2(arm * sx, 0.0), edge, 3.0, true)
		_frame.draw_line(p, p + Vector2(0.0, arm * sy), edge, 3.0, true)
	# The fuse.
	var bar_w := minf(size.x * 0.36, 520.0)
	var bar := Rect2(Vector2((size.x - bar_w) * 0.5, m + 26.0), Vector2(bar_w, 8.0))
	_frame.draw_rect(bar, Color(0.0, 0.0, 0.0, 0.5))
	var share := clampf(_fuse_left / FUSE, 0.0, 1.0)
	_frame.draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), Color(col, 0.9))
	_frame.draw_rect(bar, Color(col, 0.6), false, 1.5)
	_frame.draw_string(_font, Vector2(bar.position.x, bar.position.y - 8.0), "ROBOT RAT",
		HORIZONTAL_ALIGNMENT_LEFT, bar_w * 0.5, 18, Color(col, 0.9))
	_frame.draw_string(_font, Vector2(bar.position.x + bar_w * 0.5, bar.position.y - 8.0),
		"%.1f s" % maxf(_fuse_left, 0.0), HORIZONTAL_ALIGNMENT_RIGHT, bar_w * 0.5, 18, Color(col, 0.9))
	var keys := "RB  detonate      Left stick  drive" if Input.get_connected_joypads().size() > 0 \
		else "LMB  detonate      WASD  drive      Mouse  turn"
	# Above the health bar and the attack icons, not on them.
	_frame.draw_string(_font, Vector2(0.0, size.y - 130.0), keys, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16,
		Color(CYAN, 0.75))
	if _hurt_flash > 0.0:
		_frame.draw_string(_font, Vector2(0.0, size.y * 0.5 + 60.0), "YOUR BODY IS UNDER ATTACK",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1.0, 0.3, 0.25, _hurt_flash))
