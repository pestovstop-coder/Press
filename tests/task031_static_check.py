#!/usr/bin/env python3
"""Source contracts only; Godot rendering, input and visual acceptance are separate."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
style = (root / 'scripts/ui_paper_style.gd').read_text()
ui = (root / 'scripts/ui_shell.gd').read_text()
placement = (root / 'scripts/placement_controller.gd').read_text()
panel = (root / 'scripts/placement_panel.gd').read_text()
card = (root / 'scripts/ui_paper_card.gd').read_text()
for role in ('navigation', 'tab', 'primary', 'secondary', 'compact', 'object', 'dialog', 'catalogue'):
    assert f'"{role}":' in style, role
for state in ('normal', 'hover', 'pressed', 'hover_pressed', 'disabled', 'focus'):
    assert f'add_theme_stylebox_override("{state}",' in style, state
assert 'surface.border_width_left = 3' in style
assert 'surface.border_width_bottom = 3' in style
assert 'Color("b7c9ce") if selected' in style
assert 'align_to_largest_stylebox", 1' in style
for margin, value in (('left', 12), ('right', 12), ('top', 8), ('bottom', 8)):
    assert f's.content_margin_{margin} = {value}' in style
assert 'Style.button(b, selected, "navigation")' in ui
assert 'Style.button(speed_buttons[i], selected, "tab")' in ui
assert 'side.visibility_changed.connect(_sync_nav)' in ui
assert 'b.text = ("▸  " if selected else "")' in ui
assert 'Style.button(buttons[id], id == selected, "catalogue")' in panel
build = placement.split('func _build_panel()', 1)[1].split('\n\nfunc ', 1)[0]
assert 'res://scripts/ui_paper_card.gd' in build
assert 'button.pressed.connect(select_asset.bind(asset_id))' in build
assert 'button.custom_minimum_size = Vector2(0, 64)' in build
assert 'button.mouse_force_pass_scroll_events = true' in build
assert 'tween_property(self, "fold", target, 0.15)' in card
assert 'extends Button' in card and 'position =' not in card and 'size =' not in card
assert 'Vector2(44, 44)' in ui and 'b.custom_minimum_size.y = 46' in ui
print('TASK 031 source contracts passed; no runtime or visual acceptance implied.')
