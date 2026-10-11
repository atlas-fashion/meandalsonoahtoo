extends CanvasLayer

## The on-screen keyboard's layer (pad.gd). Being the root's last child, its
## `_input` runs before any screen's; it hands the pad's B / X / Y / Start to the
## keyboard and swallows them, so B deletes a letter instead of closing the
## screen behind it.


func _input(event: InputEvent) -> void:
	if Pad.keyboard_input(event):
		get_viewport().set_input_as_handled()
