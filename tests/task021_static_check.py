#!/usr/bin/env python3
"""Source-level regressions for TASK 021; not a Godot runtime/visual test."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
controller = (ROOT / "scripts/placement_controller.gd").read_text()
labels = (ROOT / "scripts/room_labels.gd").read_text()
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
      "room label component is attached to the main scene")
for token, desc in [
    ('"office_101"', "office 101 plaque anchor"),
    ('"office_102"', "office 102 plaque anchor"),
    ('"corridor_main"', "shared corridor plaque anchor"),
    ('Vector3(-3.0, 0.0, 2.15)', "office 101 marker is at its documented entrance"),
    ('Vector3(3.0, 0.0, 2.15)', "office 102 marker is at its documented entrance"),
    ('Vector3(0.0, 0.0, 3.35)', "corridor marker is within the shared corridor"),
    ('"КАБИНЕТ", "101"', "editable office 101 label text"),
    ('"КАБИНЕТ", "102"', "editable office 102 label text"),
    ('"ОБЩИЙ", "КОРИДОР"', "editable corridor label text"),
    ('plaque.rotation.y = atan2(to_camera.x, to_camera.z)', "plaque yaw follows camera"),
]:
    check(token in labels, desc)

print("Static checks passed. Godot parsing, placement execution, and visual acceptance are not covered.")
