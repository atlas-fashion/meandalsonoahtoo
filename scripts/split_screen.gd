extends Node

## The SPLIT SCREEN of a co-op session (coop.gd; 2026-10-18): the window cut
## down the middle, player 1 on the left, player 2 on the right. A node of
## scenes/main.tscn, after both players and both HUDs; outside co-op it frees
## itself at once and nothing here exists.
##
## Each half is a SubViewport that shares the level's World3D, with:
##   * a camera that takes its player's camera every frame, just before the
##     frame is drawn (`frame_pre_draw` -- the player's head bob, slam shake
##     and sword duck are all settled by then): transform, field of view,
##     near / far, its exposure attributes, and an Environment of its own (a
##     copy of the world's), so one player's dash or wounds grey only their own
##     half (player.gd `_environment`);
##   * that player's HUD (and so their inventory, wheels, map, overlays),
##     moved in from the root. Its 2D canvas is 1280 units wide -- the width
##     every HUD layout was made for -- and as tall as the half's shape asks
##     (`size_2d_override`), so each half shows the whole HUD at a smaller size.
##
## The root viewport stops drawing 3D (`disable_3d`): every pixel of the
## world is drawn once, into one half or the other -- the same number as one
## full screen, which is the cost that matters on this game's hardware
## (CLAUDE.md section 2); the draw calls are doubled, two cameras.
##
## LAYERS. Each player's own first-person pieces (the sword, spear, potion,
## torch in the hand, the robot rat in the palm) are drawn on VIEWMODEL[i] and
## each player's third-person stand-in (coop_avatar.gd) on AVATAR[i]: a half's
## camera draws its own viewmodel and the OTHER player's avatar, never the
## other's viewmodel (pulled to the eye by `use_z_clip_scale`, it would fill
## the wrong screen) nor its own avatar (it would sit inside its head).

const VIEWMODEL := [1 << 16, 1 << 17]
const AVATAR := [1 << 13, 1 << 14]
## The divider between the halves, in pixels of the window.
const DIVIDER := 3
const CANVAS_WIDTH := 1280
## A robot rat's own body (robot_rat.gd SELF_LAYER).
const ROBOT_SELF := 1 << 19

var _layer: CanvasLayer
var _views: Array[Viewport] = []
var _containers: Array[HalfContainer] = []
var _cameras: Array[Camera3D] = []
var _envs: Array[Environment] = []
## Each half's camera mask (`_apply_layers`).
var _masks: Array[int] = []


## A half: it passes on the mouse only when it is its own player's -- player
## 1's real mouse to the left, the pad cursor's made-up one (pad.gd) to the
## right -- so a pointer straying across the middle works nothing in the other
## half. Keys and pads go to both; each screen there asks `Coop.owns`.
class HalfContainer extends SubViewportContainer:
	var index := 0

	func _propagate_input_event(event: InputEvent) -> bool:
		if event is InputEventMouse:
			return Coop.device_player(event) == index
		return true


func _ready() -> void:
	if not Coop.active:
		queue_free()
		return
	name = "SplitScreen"
	Coop.split = self
	# Also after every player has moved each frame (not only before drawing),
	# so whatever reads a half's camera in between sees it where it is.
	process_priority = 1000
	_build.call_deferred()


func _exit_tree() -> void:
	if Coop.split == self:
		Coop.split = null
	var root := get_tree().root if is_inside_tree() else null
	if root != null:
		root.disable_3d = false
	if RenderingServer.frame_pre_draw.is_connected(_follow):
		RenderingServer.frame_pre_draw.disconnect(_follow)
	if _window != null:
		Pad.call("use_viewport", null)
		if root != null:
			root.gui_embed_subwindows = true


func _build() -> void:
	var root := get_tree().root
	_layer = CanvasLayer.new()
	_layer.name = "SplitViews"
	_layer.layer = -1
	add_child(_layer)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(row)
	var world_env := get_tree().get_first_node_in_group(&"world_environment") as WorldEnvironment
	# TWO MONITORS (Coop.two_screens, and another monitor there): player 1's
	# view fills the game's window, player 2's is a window of its own on
	# `Coop.second_screen`.
	var two := Coop.two_screens and DisplayServer.get_screen_count() > 1
	for i in 2:
		var vp: Viewport
		if i == 1 and two:
			vp = _second_window(root)
		else:
			if i == 1:
				var line := ColorRect.new()
				line.color = Color(0.0, 0.0, 0.0)
				line.custom_minimum_size = Vector2(DIVIDER, 0)
				line.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(line)
			var box := HalfContainer.new()
			box.index = i
			box.name = "Half%d" % (i + 1)
			box.stretch = true
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.size_flags_vertical = Control.SIZE_EXPAND_FILL
			box.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(box)
			var sub := SubViewport.new()
			sub.name = "View%d" % (i + 1)
			sub.world_3d = root.world_3d
			sub.handle_input_locally = true
			sub.audio_listener_enable_3d = i == 0
			box.add_child(sub)
			_containers.append(box)
			vp = sub
		var cam := Camera3D.new()
		cam.name = "Eyes%d" % (i + 1)
		vp.add_child(cam)
		cam.current = true
		var env: Environment = null
		if world_env != null and world_env.environment != null:
			env = world_env.environment.duplicate() as Environment
			cam.environment = env
		_views.append(vp)
		_cameras.append(cam)
		_envs.append(env)
	root.disable_3d = true
	_place_huds()
	_apply_layers()
	apply_graphics()
	resized()
	root.size_changed.connect(resized)
	RenderingServer.frame_pre_draw.connect(_follow)
	for p in Coop.all():
		p.call("use_view_environment", _envs[Coop.index_of(p)])
	if _window != null:
		# The pad cursor (player 2's) works in their window.
		Pad.call("use_viewport", _window)
	Graphics.apply_all.call_deferred()


## Player 2's own window, borderless and covering `Coop.second_screen`: a
## real window of the OS (the root stops embedding its subwindows), on the
## level's World3D, its 2D canvas stretched from 1280 x 720 as the game's
## window is. It never takes focus -- the keyboard and the mouse stay with
## player 1 in the game's window. Player 2's controller still reaches it:
## Godot hands events that belong to no window (joypad buttons and sticks,
## actions) to every window -- passing them in by hand as well delivered each
## twice (an inventory opened and shut). The pad cursor's made-up mouse is
## pushed in by pad.gd.
var _window: Window = null


func _second_window(root: Window) -> Window:
	root.gui_embed_subwindows = false
	var screen := clampi(Coop.second_screen, 0, DisplayServer.get_screen_count() - 1)
	var w := Window.new()
	w.name = "Player2Window"
	w.title = "Player 2"
	w.borderless = true
	w.unfocusable = true
	w.transient = false
	w.world_3d = root.world_3d
	w.audio_listener_enable_3d = false
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(1280, 720)
	w.position = DisplayServer.screen_get_position(screen)
	w.size = DisplayServer.screen_get_size(screen)
	add_child(w)
	w.show()
	_window = w
	return w


func two_windows() -> bool:
	return _window != null


## Each HUD, and each explore map (maze.gd makes one a player), into its
## player's half.
func _place_huds() -> void:
	for h in Coop.huds():
		var i := Coop.index_of(h.get("player"))
		if i < 0 or i >= _views.size():
			continue
		h.reparent(_views[i], false)
	for m in get_tree().get_nodes_in_group(&"explore_map"):
		var owner_ = m.get("_player")
		if owner_ == null:
			continue
		var i := Coop.index_of(owner_)
		if i >= 0 and i < _views.size():
			m.reparent(_views[i], false)


## The players' viewmodels and avatars onto their layers, and each camera's
## mask to match.
func _apply_layers() -> void:
	for p in Coop.all():
		var i := Coop.index_of(p)
		p.call("set_view_layers", VIEWMODEL[i], AVATAR[i])
	_masks.clear()
	for i in _cameras.size():
		var mask := (1 << 20) - 1
		mask &= ~VIEWMODEL[1 - i]
		mask &= ~AVATAR[i]
		_cameras[i].cull_mask = mask
		_masks.append(mask)


func resized() -> void:
	for v in _views:
		# Only the halves: a window of its own stretches its canvas itself.
		var vp := v as SubViewport
		if vp == null:
			continue
		var s := vp.size
		if s.x <= 0 or s.y <= 0:
			continue
		vp.size_2d_override = Vector2i(CANVAS_WIDTH, roundi(CANVAS_WIDTH * float(s.y) / float(s.x)))
		vp.size_2d_override_stretch = true


## The graphics settings (graphics_settings.gd `_apply_viewport`) onto both
## halves -- they apply to a viewport, and the root no longer draws.
func apply_graphics() -> void:
	for vp in _views:
		Graphics.call("apply_to_viewport", vp)


## Each half's camera onto its player's, just before the frame is drawn.
func _follow() -> void:
	for p in Coop.all():
		var i := Coop.index_of(p)
		if i >= _cameras.size():
			continue
		var src := p.get("camera") as Camera3D
		if src == null or not src.is_inside_tree():
			continue
		var cam := _cameras[i]
		# The robot rat's eyes (rat_control.gd) take the half while driven.
		var remote = p.get("rats").call("view_camera") if p.get("rats") != null \
			and p.get("rats").has_method("view_camera") else null
		var driving: bool = remote != null and is_instance_valid(remote)
		if driving:
			src = remote
		# Through a robot rat's eyes its own body is left out (robot_rat.gd
		# SELF_LAYER), as its own camera leaves it out.
		if i >= _masks.size():
			continue
		var mask := _masks[i] & ~ROBOT_SELF if driving else _masks[i]
		if cam.cull_mask != mask:
			cam.cull_mask = mask
		cam.global_transform = src.global_transform
		cam.fov = src.fov
		cam.near = src.near
		cam.far = src.far
		cam.h_offset = src.h_offset
		cam.v_offset = src.v_offset
		if src.attributes != null:
			cam.attributes = src.attributes


func view_of(p: Node) -> Viewport:
	var i := Coop.index_of(p)
	return _views[i] if i < _views.size() else null


func camera_of(p: Node) -> Camera3D:
	var i := Coop.index_of(p)
	return _cameras[i] if i < _cameras.size() else null


func cameras() -> Array[Camera3D]:
	return _cameras


func _process(_delta: float) -> void:
	if not _cameras.is_empty():
		_follow()
