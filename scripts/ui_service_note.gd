extends HBoxContainer
## A single quiet service annotation with its own reserved illustration space.
const Style = preload("res://scripts/ui_paper_style.gd")
var text_label: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_constant_override("separation", 8)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	add_child(words)
	var heading := Label.new()
	heading.text = "СЛУЖЕБНОЕ ПРИМЕЧАНИЕ"
	heading.add_theme_font_size_override("font_size", 10)
	heading.add_theme_color_override("font_color", Style.MUTED)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(heading)
	text_label = Label.new()
	text_label.add_theme_font_size_override("font_size", 12)
	text_label.add_theme_color_override("font_color", Style.MUTED)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(text_label)
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(35, 36)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.draw.connect(_draw_cup.bind(mark))
	add_child(mark)

func set_note(value: String) -> void:
	text_label.text = value

func _draw_cup(mark: Control) -> void:
	# Pencil-like cup/ring in its own margin, never over text or buttons.
	var ink := Color(0.42, 0.40, 0.36, 0.42)
	mark.draw_arc(Vector2(17, 20), 12.0, 0.12, 5.9, 28, ink, 1.0, true)
	mark.draw_arc(Vector2(17, 20), 8.0, 0.0, TAU, 24, ink, 1.0, true)
	mark.draw_arc(Vector2(25, 19), 3.0, -1.1, 1.0, 10, ink, 1.0, true)
