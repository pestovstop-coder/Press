#!/usr/bin/env python3
"""Source-level UI checks, not a substitute for real Godot interaction."""
from pathlib import Path
p = Path(__file__).resolve().parents[1]
ui = (p / 'scripts/ui_shell.gd').read_text()
style = (p / 'scripts/ui_paper_style.gd').read_text()
note = (p / 'scripts/ui_service_note.gd').read_text()
assert ui.index('add_child(root)') < ui.index('root.set_anchors_and_offsets_preset')
assert 'var bottom_height := 84.0 if not compact else 80.0' in ui
assert 'footer_style.content_margin_top = 4' in ui
assert 'footer.add_child(note_row)' in ui and 'note_row.add_child(service_note)' in ui
assert 'context_note.call("set_note", current_note)' in ui
assert 'service_note.call("set_note", GENERAL_NOTE)' in ui
assert 'func _add_note()' not in ui
assert 'text_label.clip_text = true' in note and 'func set_compact()' in note
assert 'align_to_largest_stylebox", 1' in style
for state in ['normal', 'hover', 'pressed', 'hover_pressed', 'disabled']:
    assert f'add_theme_stylebox_override("{state}", box(' in style
for section in ['РЕЕСТР ДОКУМЕНТОВ', 'РЕДАКЦИОННАЯ ПОВЕСТКА', 'РЕДАКЦИОННОЕ ЗАДАНИЕ']:
    assert section in ui
print('TASK 029 source checks passed; Godot layout and input remain unverified.')
