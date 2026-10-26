extends CanvasLayer

## Spoken lines on the screen (2026-10-25, note 109): the speaker's name and the
## line, typed out a letter at a time (PER_CHAR, or slower), held, faded. Over
## the letterbox (wood_door.gd, layer 40), low in the frame. One at a time:
##   var sub := Subtitles.open(self)
##   await sub.say("THE SURGEON", "Who... are... you...", 0.16)
##   sub.close()

const PER_CHAR := 0.045
## A pause on these, as a voice would.
const PAUSES := {".": 0.35, ",": 0.2, "?": 0.3, "!": 0.3}

var _box: VBoxContainer
var _name: Label
var _line: Label


static func open(from: Node) -> CanvasLayer:
	var s := CanvasLayer.new()
	s.set_script(load("res://scripts/subtitles.gd"))
	s.layer = 41
	from.get_tree().root.add_child(s)
	return s


func _ready() -> void:
	var box := VBoxContainer.new()
	_box = box
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.anchor_left = 0.15
	box.anchor_right = 0.85
	box.anchor_top = 0.78
	box.anchor_bottom = 0.9
	box.offset_left = 0.0
	box.offset_right = 0.0
	box.offset_top = 0.0
	box.offset_bottom = 0.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 18)
	_name.add_theme_color_override("font_color", Color(0.85, 0.55, 0.4))
	box.add_child(_name)
	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_font_size_override("font_size", 30)
	_line.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86))
	_line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_line.add_theme_constant_override("outline_size", 8)
	box.add_child(_line)


## Types `text` out under `speaker`, `per_char` a letter, then holds it `hold` s.
func say(speaker: String, text: String, per_char := PER_CHAR, hold := 1.2) -> void:
	_name.text = speaker
	_line.text = text
	_line.visible_characters = 0
	_box.modulate.a = 1.0
	for i in text.length():
		_line.visible_characters = i + 1
		var wait := per_char + float(PAUSES.get(text[i], 0.0)) * (per_char / PER_CHAR) * 0.5
		await get_tree().create_timer(wait, true, false, true).timeout
	await get_tree().create_timer(hold, true, false, true).timeout


func close() -> void:
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(_box, "modulate:a", 0.0, 0.3)
	t.tween_callback(queue_free)
