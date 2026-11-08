#!/usr/bin/env python3
"""Source-level regressions for TASK 021; not a Godot runtime/visual test."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
controller = (ROOT / "scripts/placement_controller.gd").read_text()
labels = (ROOT / "scripts/room_labels.gd").read_text()
registry = (ROOT / "scripts/room_registry.gd").read_text()
scene = (ROOT / "scenes/main.tscn").read_text()
smoke = (ROOT / "tests/placement_smoke.gd").read_text()


def check(ok: bool, message: str) -> None:
    if not ok:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


check('const CELL_SIZE: float = 0.25' in controller, "placement cell remains 0.25m")
check('const EDITOR_GRID_STEP: float = CELL_SIZE * 2.0' in controller,
      "visual floor lines remain a separate 0.5m reference")
check('const PLACEMENT_VISUAL_GROUP: StringName = &"placement_visual"' in controller,
      "editor overlays have a distinct group")
check('grid.add_to_group(PLACEMENT_VISUAL_GROUP)' in controller,
      "placement grid is explicitly marked as visualization")
check('not mesh.is_in_group(PLACEMENT_VISUAL_GROUP)' in controller,
      "visual overlays are excluded when collecting room obstacles")
check('front_marker.add_to_group(PLACEMENT_VISUAL_GROUP)' in controller,
      "footprint marker is explicitly marked as visualization")
check('mesh == floor_mesh' in controller and '"OBSTACLE_COLLISION"' in controller,
      "floor exemption and real generic obstacle rejection remain")
check('c.room_occluders.has(c.grid)' in smoke and 'OBSTACLE_COLLISION' in smoke,
      "runtime smoke test covers grid exclusion and generic obstacles")

sun = re.search(r'^\[node name="Sun" type="DirectionalLight3D"[^\n]*\](.*?)(?=^\[node )',
                scene, re.M | re.S)
check(sun is not None, "main scene has the expected Sun node")
check(re.search(r'^shadow_bias = 1(?:\.0)?$', sun.group(1), re.M) is not None,
      "Sun shadow bias is 1.0")
check(re.search(r'^shadow_normal_bias = 2(?:\.0)?$', sun.group(1), re.M) is not None,
      "Sun shadow normal bias is 2.0")

shadow_overrides = []
for path in (ROOT / "scripts").rglob("*.gd"):
    text = path.read_text()
    if re.search(r"(?:shadow_bias|shadow_normal_bias)\s*=", text):
        shadow_overrides.append(str(path.relative_to(ROOT)))
check(not shadow_overrides, "no GDScript overrides Sun bias settings")

check('[node name="RoomLabels" type="Node3D" parent="."]' in scene,
      "floor-label component is attached to the main scene")
check('[node name="RoomRegistry" type="Node" parent="."]' in scene,
      "logical room registry is attached to the main scene")
for token, desc in [
    ('"room_101"', "stable room 101 ID is registered"),
    ('"room_102"', "stable room 102 ID is registered"),
    ('"corridor_main"', "stable corridor ID is registered"),
    ('"КАБИНЕТ 101"', "office 101 display name is in the registry"),
    ('"КАБИНЕТ 102"', "office 102 display name is in the registry"),
    ('"ОБЩИЙ КОРИДОР"', "corridor display name is in the registry"),
    ('label.text = room["display_name"]', "floor text is sourced from registry data"),
    ('label.set_meta("room_id", room_id)', "floor labels retain their registered IDs"),
]:
    check(token in registry or token in labels, desc)
for token, desc in [
    ('Vector3(-3.0, FLOOR_OFFSET, -1.95)', "office 101 label sits in its planned aisle"),
    ('Vector3(3.0, FLOOR_OFFSET, -1.95)', "office 102 label sits in its planned aisle"),
    ('Vector3(0.0, FLOOR_OFFSET, 3.15)', "corridor label sits in the shared corridor"),
    ('label.billboard = BaseMaterial3D.BILLBOARD_DISABLED', "floor text is world-static, not billboarded"),
    ('label.no_depth_test = false', "floor text is naturally occluded by furniture"),
    ('label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)', "Label3D lies horizontally on the floor"),
    ('const FLOOR_OFFSET: float = 0.004', "a fixed vertical offset avoids z-fighting"),
    ('const TEXT_COLOR := Color(0.22, 0.28, 0.30, 0.46)', "text remains subdued and translucent"),
]:
    check(token in labels, desc)
check('get_room_by_id", room_id' in labels, "labels resolve display data by logical room ID")
check('camera' not in labels.lower(), "floor labels do not depend on camera orientation")
check('BoxMesh.new()' not in labels and 'PlaqueBacking' not in labels,
      "labels have no plate, backing, border, or 3D decoration")

print("Static checks passed. Godot parsing, placement execution, and visual acceptance are not covered.")
