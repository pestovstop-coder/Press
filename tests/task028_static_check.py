#!/usr/bin/env python3
"""Structural checks only: these do not replace Godot GUI/runtime acceptance."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
ui = (root / 'scripts/ui_shell.gd').read_text()
placement = (root / 'scripts/placement_controller.gd').read_text()
panel = (root / 'scripts/placement_panel.gd').read_text()
notes = (root / 'scripts/ui_service_note.gd').read_text()
style = (root / 'scripts/ui_paper_style.gd').read_text()
scene = (root / 'scenes/main.tscn').read_text()

def check(condition, label):
    if not condition:
        raise AssertionError(label)
    print('PASS:', label)

check('res://scripts/ui_shell.gd' in scene, 'main scene connects UI shell')
for source in (ui, placement, panel, notes):
    for path in re.findall(r'preload\("res://([^\"]+)"\)', source):
        check((root / path).is_file(), f'preload exists: {path}')
for name in ('Офис', 'Сотрудники', 'Редакция', 'Задачи', 'Документы'):
    check(f'"{name}": [' in ui, f'UI section and note source: {name}')
check('mouse_force_pass_scroll_events = true' in ui and
      'mouse_force_pass_scroll_events = true' in placement,
      'scrollable buttons forward wheel events')
check('panel.mouse_force_pass_scroll_events = false' in placement and
      'p.mouse_force_pass_scroll_events = false' in ui,
      'outer panels stop wheel propagation')
check('Control.MOUSE_FILTER_IGNORE' in notes, 'decoration ignores pointer input')
check('Vector2(44, 44)' in ui, 'HUD controls have minimum target size')
check('Vector2(0, 64)' in placement, 'catalogue button minimum height')
for code in ('VALID', 'INVALID_FOOTPRINT', 'INVALID_COORDINATES', 'OUT_OF_BOUNDS',
             'FURNITURE_COLLISION', 'WALL_COLLISION', 'OBSTACLE_COLLISION', 'NO_VALID_PLACEMENT'):
    diagnostic = placement.split('func _diagnostic_text(', 1)[1].split('\n\nfunc ', 1)[0]
    check(f'"{code}": return "' in diagnostic, f'localized diagnostic {code}')
for asset in ('block', 'office_desk', 'employee_workstation'):
    check(f'"{asset}"' in placement.split('func _build_panel()', 1)[1],
          f'catalogue retains {asset}')
check('minf(natural_height, maxf(120, viewport_size.y - 32))' in panel,
      'catalogue intended to fit viewport height')
for width, height in ((1920, 1080), (1600, 900), (1366, 768), (1280, 720), (1280, 500)):
    compact = width < 1400
    header = 70 if compact else 78
    match = re.search(r"var bottom_height := ([0-9.]+) if not compact else ([0-9.]+)", ui)
    assert match, "bottom height definition not found"
    bottom = float(match.group(2) if compact else match.group(1))
    rail_y = header + 12
    rail_h = max(80, min(385, height - header - bottom - 36))
    side_h = max(180, height - header - bottom - 36)
    bottom_y = height - bottom - 12
    check(rail_y + rail_h <= bottom_y and rail_y + side_h <= bottom_y,
          f'nominal HUD vertical rectangles do not overlap: {width}x{height}')
print('Static checks only: text minimum sizes, actual geometry and GUI events need Godot.')
