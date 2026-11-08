#!/usr/bin/env python3
"""Structural checks only; Godot input/rendering requires runtime validation."""
from pathlib import Path
p = Path(__file__).resolve().parents[1]
ui = (p / 'scripts/ui_shell.gd').read_text()
card = (p / 'scripts/ui_paper_card.gd').read_text()
probe = (p / 'tests/task030_pointer_probe.gd').read_text()
assert 'side.visibility_changed.connect(_sync_nav)' in ui
assert ui.count('close.pressed.connect(_close_side)') == 2
assert 'var selected: bool = side.visible and name == current_section' in ui
assert 'b.text = ("▸  " if selected else "")' in ui
assert 'side_layout.add_child(scroll)' in ui and 'side_layout.add_child(context_note)' in ui
assert ui.index('side_layout.add_child(scroll)') < ui.index('side_layout.add_child(context_note)')
assert 'service_note.call("set_note", GENERAL_NOTE)' in ui
assert 'context_note.call("set_note", current_note)' in ui
assert 'PaperCard.new() if paper else Button.new()' in ui
assert 'extends Button' in card and 'tween_property(self, "fold", target, 0.15)' in card
assert 'draw_colored_polygon' in card and 'size =' not in card and 'position =' not in card
for diagnostic in ('mouse_get_position', 'window_get_position', 'get_mouse_position',
                   'get_global_transform_with_canvas', 'gui_get_hovered_control'):
    assert diagnostic in probe
print('TASK 030 structural checks pass; runtime input and visual alignment are not verified.')
