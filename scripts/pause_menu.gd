extends CanvasLayer

## Escape brings this up. Runs with PROCESS_MODE_ALWAYS so it still gets input
## while the rest of the tree is frozen.
##
## Resume, Save game, Settings, Exit to title and Quit to desktop. Leaving does
## not save by itself: it asks -- Save and leave, Leave without saving, Cancel --
## and says how long ago the last save was. The settings page is the shared
## SettingsPanel, the same one the title screen shows.

var _root_panel: Control
var _leave_panel: Control
var _leave_text: Label
var _leave_to_desktop := false
var _settings: SettingsPanel
var _status: Label
var _save_button: Button
var _resume_button: Button
var _leave_first: Button
var _was_captured := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	_build()
	visible = false


## "pause" (Escape, or Start on a pad) opens and closes it; while it is up,
## "ui_cancel" (Escape, or B) steps back too. B alone does not pause the game.
## In `_input`, not `_unhandled_input`: with a button focused (for the pad) the
## GUI takes "ui_cancel" first, and Escape / B stopped closing the menu.
func _input(event: InputEvent) -> void:
	var opening := event.is_action_pressed("pause")
	var backing := visible and event.is_action_pressed("ui_cancel")
	if not opening and not backing:
		return
	get_viewport().set_input_as_handled()
	if not visible:
		_open()
	elif _settings.visible or _leave_panel.visible:
		_show_page(false)
	else:
		_close()


func _open() -> void:
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""
	# Nothing to save to when the game was started without a slot (a harness,
	# the benchmark, --skip-title).
	_save_button.disabled = Saves.slot < 0
	_save_button.tooltip_text = "" if Saves.slot >= 0 else "This game was started without a save slot."
	_show_page(false)
	_settings.sync()


func _close() -> void:
	visible = false
	get_tree().paused = false
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_page(settings: bool) -> void:
	_root_panel.visible = not settings
	_settings.visible = settings
	_leave_panel.visible = false
	# A pad needs something focused to move from.
	if not settings and _resume_button != null:
		_resume_button.grab_focus.call_deferred()


func _save() -> void:
	var why: String = Saves.save_now("manual")
	if why == "":
		_status.text = "Saved to slot %d." % (Saves.slot + 1)
		_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6))
	else:
		_status.text = why
		_status.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))


## Leaving never saves by itself: with a slot, the player is asked first.
func _exit_to_title() -> void:
	_ask_leave(false)


func _quit() -> void:
	_ask_leave(true)


func _ask_leave(to_desktop: bool) -> void:
	_leave_to_desktop = to_desktop
	if Saves.slot < 0:
		_leave(false)
		return
	_leave_text.text = "Your last save was %s ago.\nAnything since then will be lost if you leave without saving." \
		% Saves.clock(Saves.since_saved)
	_root_panel.visible = false
	_leave_panel.visible = true
	_leave_first.grab_focus.call_deferred()


func _leave(save_first: bool) -> void:
	if save_first:
		var why: String = Saves.save_now("manual")
		if why != "":
			_leave_text.text = why + "\nYou can still leave without saving."
			return
	visible = false
	if _leave_to_desktop:
		get_tree().quit()
	else:
		Saves.exit_to_title()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ColorRect blocks the mouse by default, which is exactly what a modal wants.
	add_child(dim)

	_root_panel = CenterContainer.new()
	_root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_panel)
	var menu := SettingsPanel.panel_box(_root_panel)
	menu.add_child(SettingsPanel.title_label("PAUSED"))
	menu.add_child(SettingsPanel.spacer(10))
	_resume_button = SettingsPanel.menu_button("Resume", _close)
	menu.add_child(_resume_button)
	_save_button = SettingsPanel.menu_button("Save game", _save)
	menu.add_child(_save_button)
	menu.add_child(SettingsPanel.menu_button("Settings", func() -> void: _show_page(true)))
	menu.add_child(SettingsPanel.menu_button("Exit to title", _exit_to_title))
	menu.add_child(SettingsPanel.menu_button("Quit to desktop", _quit))
	_status = SettingsPanel.dim_label("")
	_status.add_theme_font_size_override("font_size", 14)
	menu.add_child(_status)
	menu.add_child(SettingsPanel.dim_label("Esc / Start closes this menu   ·   the game also saves itself every minute"))

	_leave_panel = CenterContainer.new()
	_leave_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_leave_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_leave_panel)
	var ask := SettingsPanel.panel_box(_leave_panel, 420)
	ask.add_child(SettingsPanel.title_label("LEAVE?"))
	_leave_text = SettingsPanel.dim_label("")
	_leave_text.add_theme_font_size_override("font_size", 15)
	_leave_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ask.add_child(_leave_text)
	ask.add_child(SettingsPanel.spacer(6))
	_leave_first = SettingsPanel.menu_button("Save and leave", func() -> void: _leave(true))
	ask.add_child(_leave_first)
	ask.add_child(SettingsPanel.menu_button("Leave without saving", func() -> void: _leave(false)))
	ask.add_child(SettingsPanel.menu_button("Cancel", func() -> void: _show_page(false)))
	_leave_panel.visible = false

	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.back_pressed.connect(func() -> void: _show_page(false))
	_settings.add_button("Resume", _close)
	_settings.visible = false
