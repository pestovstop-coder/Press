extends RefCounted
## Shared paper controls and role variants; presentation only.
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

static func button(b: Button, selected: bool = false, role: String = "card") -> void:
	# Preserve the TASK 030 card treatment; other controls use role variants.
	if role != "card":
		_variant_button(b, selected, role)
		return
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
	b.add_theme_stylebox_override("focus", _focus_box())

static func _focus_box() -> StyleBoxFlat:
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = RED
	focus.set_border_width_all(2)
	return focus

# Each role keeps the same explicit content margins in every state. Border
# accents are drawn inside the existing Control, never as extra input surfaces.
static func _variant_button(b: Button, selected: bool, role: String) -> void:
	var normal_bg := LIGHT
	var normal_border := LINE
	var hover_bg := Color("e7dfd0")
	var hover_border := NAVY
	var pressed_bg := Color("d4cabb")
	var accent_side := "bottom"
	match role:
		"navigation":
			normal_bg = PAPER
			hover_bg = Color("ded8cc")
			accent_side = "left"
		"tab":
			normal_bg = PAPER
			hover_bg = LIGHT
		"primary":
			normal_bg = NAVY
			normal_border = NAVY
			hover_bg = Color("28516d")
			pressed_bg = Color("102d44")
		"secondary":
			hover_bg = Color("eae3d6")
		"compact":
			normal_bg = LIGHT
			hover_bg = PAPER
		"object":
			normal_bg = Color("ede6d9")
			hover_bg = Color("dfd7c9")
			accent_side = "left"
		"dialog":
			normal_bg = LIGHT
			hover_bg = Color("e3e9e9")
		"catalogue":
			normal_bg = LIGHT
			hover_bg = Color("e6e0d4")
			accent_side = "left"
		_:
			push_warning("Unknown paper button role: " + role)
	var primary := role == "primary"
	var base_ink := LIGHT if primary else INK
	var active_bg := NAVY if selected else normal_bg
	var active_border := Color("b7c9ce") if selected else normal_border
	var active_ink := LIGHT if selected else base_ink
	var hover_color := Color("28516d") if selected else hover_bg
	var hover_ink := LIGHT if selected or primary else INK
	var pressed_color := Color("102d44") if selected or primary else pressed_bg
	var pressed_ink := LIGHT if selected or primary else INK
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_constant_override("align_to_largest_stylebox", 1)
	b.add_theme_color_override("font_color", active_ink)
	b.add_theme_color_override("font_hover_color", hover_ink)
	b.add_theme_color_override("font_pressed_color", pressed_ink)
	b.add_theme_color_override("font_hover_pressed_color", pressed_ink)
	b.add_theme_color_override("font_focus_color", active_ink)
	b.add_theme_color_override("font_disabled_color", MUTED)
	var normal := box(active_bg, active_border)
	var hover := box(hover_color, Color("b7c9ce") if selected else hover_border)
	var pressed := box(pressed_color, Color("b7c9ce") if selected else (NAVY if primary else LINE))
	var disabled := box(PAPER, LINE)
	# Tabs and catalogue sheets have a quiet lower edge, within the same rect.
	if role in ["tab", "catalogue"]:
		for surface in [normal, hover, pressed, disabled]:
			surface.border_width_bottom = 2
	if selected:
		# Persistent structural accent survives hover, not just a change of colour.
		disabled.border_color = MUTED
		for surface in [normal, hover, pressed, disabled]:
			if accent_side == "left":
				surface.border_width_left = 3
			else:
				surface.border_width_bottom = 3
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", _focus_box())

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
