extends RefCounted
## Shared flat paper controls; presentation only.
const PAPER := Color("e9e1d2")
const LIGHT := Color("f5f0e6")
const INK := Color("252a2e")
const NAVY := Color("173b59")
const RED := Color("b7443e")
const MUTED := Color("6c716d")
const LINE := Color("c9c1b2")

static func box(bg: Color, border: Color = LINE, width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

static func button(b: Button, selected: bool = false) -> void:
	b.add_theme_font_size_override("font_size", 15)
	# Keep text alignment stable across all Button draw states.
	b.add_theme_constant_override("align_to_largest_stylebox", 1)
	b.add_theme_color_override("font_color", LIGHT if selected else INK)
	b.add_theme_color_override("font_hover_color", LIGHT)
	b.add_theme_color_override("font_pressed_color", LIGHT)
	b.add_theme_color_override("font_hover_pressed_color", LIGHT)
	b.add_theme_color_override("font_focus_color", LIGHT if selected else INK)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_stylebox_override("normal", box(NAVY if selected else LIGHT, NAVY if selected else LINE))
	b.add_theme_stylebox_override("hover", box(NAVY, NAVY))
	b.add_theme_stylebox_override("pressed", box(RED, RED))
	b.add_theme_stylebox_override("hover_pressed", box(RED, RED))
	b.add_theme_stylebox_override("disabled", box(PAPER, LINE))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = RED
	focus.set_border_width_all(2)
	b.add_theme_stylebox_override("focus", focus)

static func _scroll_box(color: Color) -> StyleBoxFlat:
	var s := box(color, color, 0)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	return s

static func scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 10
	bar.add_theme_stylebox_override("scroll", _scroll_box(PAPER))
	bar.add_theme_stylebox_override("scroll_focus", _scroll_box(PAPER))
	bar.add_theme_stylebox_override("grabber", _scroll_box(LINE))
	bar.add_theme_stylebox_override("grabber_highlight", _scroll_box(NAVY))
	bar.add_theme_stylebox_override("grabber_pressed", _scroll_box(RED))
