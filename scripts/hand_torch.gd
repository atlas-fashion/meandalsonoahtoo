extends Node3D

## The torch in the left hand (2026-10-10): the wall torch itself
## (scenes/torch.tscn -- its flickering flame card, halo and charred head) on its
## wooden handle, without the wall bracket, held so far down in the bottom-left
## corner that only the head and flame show at the edge of the view.
##
## - It sheds NO light. The wall torches light the corridors and the frame is
##   per-pixel bound on the target card; a light riding at the eye covers every
##   pixel on screen. (The old hand torch's light was removed for that reason.)
## - Placed from the camera's own frustum every frame (`CORNER` in screen
##   fractions), so it hugs the corner whether the window is 16:9 or ultrawide.
## - Small and close (`SCALE`, `DEPTH`): it looks the same size on screen as a
##   full-size torch further out, but stays inside the player's 0.4 m collision
##   capsule, so it never pushes into a wall the player stands against.
## - Put away while hidden in a coffin, dead, or in a scene that takes the hands.

const TORCH := preload("res://scenes/torch.tscn")
## Where the flame sits, as fractions of the half-width and half-height of the
## view (-1, -1 is the bottom-left corner), and how far in front of the eye.
## The base of the flame card sits just below the bottom edge, so the tongues
## of the flame are what shows. On screen the flame is about 0.47 x SCALE /
## DEPTH of the view's height: at 0.3 / 0.17 (first try) it filled 83% of it.
## At x -0.92 it sat behind the HUD's health bars, which start at -0.967; at
## -0.99 it was off the edge altogether. Its tongues rise above the health text.
## (Lowered again once the health bar left this corner, 2026-10-10: unhidden at
## -0.86 the flame stood a quarter of the screen high.)
const CORNER := Vector2(-0.975, -1.15)
const DEPTH := 0.17
const SCALE := 0.11
## The flame card's place on the torch, which goes at the corner point.
const FLAME_AT := Vector3(0.0, 0.37, -0.49)
## Where the flame actually is once the torch has put on the kit torch (torch.gd
## moves it out to the kit torch's head); read after it enters the tree.
var _flame_at := FLAME_AT

var player: Node3D
var _torch: Node3D
var _shown := 1.0
var _sway := Vector2.ZERO
var _last_yaw := 0.0
var _last_pitch := 0.0


func setup(p: Node3D) -> void:
	player = p
	name = "TorchHand"
	_torch = TORCH.instantiate()
	# A hand torch has no bracket and casts no light.
	for part in ["Plate", "Arm", "Ring"]:
		var n := _torch.get_node_or_null(part) as Node3D
		if n != null:
			n.visible = false
	# No embers either: world-space sparks are full size off a torch a tenth of
	# the size, and torch.gd turns them back on with the effects knob -- hidden
	# and paused here, they came back as one frozen glowing block up the left of
	# the view. Removed before the torch enters the tree, so its script never
	# finds them.
	var embers := _torch.get_node_or_null("Embers")
	if embers != null:
		_torch.remove_child(embers)
		embers.free()
	add_child(_torch)
	var flame_node := _torch.get_node_or_null("Flame") as Node3D
	if flame_node != null:
		_flame_at = flame_node.position
	var light := _torch.get_node_or_null("Light") as Light3D
	if light != null:
		light.visible = false
		light.light_energy = 0.0
	# Carried with the camera, so never out of the flicker's range.
	_torch.set("cull_margin", 1.0e9)
	for g in _torch.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if player == null or _torch == null:
		return
	var cam := player.get("camera") as Camera3D
	if cam == null:
		return
	var away: bool = player.call("is_hidden") or player.get("_dead") == true or player.get("hands_busy") == true
	_shown = move_toward(_shown, 0.0 if away else 1.0, delta / 0.3)
	_torch.visible = _shown > 0.01
	if not _torch.visible:
		return
	# A little lag behind the turn of the head, as a held thing has.
	var yaw: float = player.rotation.y
	var pitch: float = player.get("_look_pitch")
	var turn := Vector2(wrapf(yaw - _last_yaw, -PI, PI), pitch - _last_pitch)
	_last_yaw = yaw
	_last_pitch = pitch
	_sway = _sway.lerp(Vector2(clampf(turn.x * 1.6, -0.06, 0.06), clampf(turn.y * 1.6, -0.06, 0.06)),
		1.0 - exp(-10.0 * delta))
	var half_h := tan(deg_to_rad(cam.fov) * 0.5) * DEPTH
	var size := get_viewport().get_visible_rect().size
	var half_w := half_h * (size.x / maxf(size.y, 1.0))
	var at := Vector3((CORNER.x + _sway.x) * half_w, (CORNER.y - _sway.y) * half_h - (1.0 - _shown) * half_h,
		-DEPTH)
	# Leaning in toward the middle of the view, the handle running off the corner.
	var b := Basis(Vector3.FORWARD, -0.35) * Basis(Vector3.RIGHT, 0.15)
	b = b.scaled(Vector3.ONE * SCALE)
	transform = Transform3D(b, at - b * _flame_at)
