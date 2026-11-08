#!/usr/bin/env python3
"""Source-level checks for TASK 025; runtime behavior is covered by room_registry_smoke.gd."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/room_registry.gd").read_text()
labels = (ROOT / "scripts/room_labels.gd").read_text()
scene = (ROOT / "scenes/main.tscn").read_text()
runtime_smoke = (ROOT / "tests/room_registry_smoke.gd").read_text()


def check(ok: bool, message: str) -> None:
    if not ok:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


for token, description in [
    ('const ROOM_101_ID: String = "room_101"', "room 101 has a stable ID"),
    ('const ROOM_102_ID: String = "room_102"', "room 102 has a stable ID"),
    ('const CORRIDOR_MAIN_ID: String = "corridor_main"', "corridor has a stable ID"),
    ('"КАБИНЕТ 101"', "room 101 has a display name"),
    ('"КАБИНЕТ 102"', "room 102 has a display name"),
    ('"ОБЩИЙ КОРИДОР"', "corridor has a display name"),
    ('TYPE_OFFICE', "office type is represented"),
    ('TYPE_CORRIDOR', "corridor type is represented"),
    ('AABB(Vector3(-6.0, 0.0, -4.25), Vector3(6.0, 3.0, 6.0))', "room 101 world AABB is explicit"),
    ('AABB(Vector3(0.0, 0.0, -4.25), Vector3(6.0, 3.0, 6.0))', "room 102 world AABB is explicit"),
    ('AABB(Vector3(-6.0, 0.0, 1.75), Vector3(12.0, 3.0, 2.5))', "corridor world AABB is explicit"),
    ('func get_room_by_id(room_id: String)', "registry supports lookup by ID"),
    ('func get_room_id_at(world_position: Vector3)', "registry supports world-position lookup"),
    ('world_position.x < bounds_end.x', "upper X boundary is exclusive"),
    ('world_position.y < bounds_end.y', "upper Y boundary is exclusive"),
    ('world_position.z < bounds_end.z', "upper Z boundary is exclusive"),
]:
    check(token in registry, description)

check('room_registry.call("get_room_ids")' in labels, "label IDs are enumerated from the registry")
check('label.text = room["display_name"]' in labels, "label text is read from registry data")
check('label.set_meta("room_id", room_id)' in labels, "label ID metadata is read from the same room ID")
check('"room_101"' not in labels and '"room_102"' not in labels,
      "room IDs are not duplicated in the label script")
check('"corridor_main"' not in labels, "corridor ID is not duplicated in the label script")
check('"КАБИНЕТ 101"' not in labels and '"КАБИНЕТ 102"' not in labels,
      "office display names are not duplicated in the label script")
check('"ОБЩИЙ КОРИДОР"' not in labels, "corridor display name is not duplicated in the label script")
check('[node name="RoomRegistry" type="Node" parent="."]' in scene,
      "registry is present in the main scene")
check('registry.call("get_room_id_at", entry[0])' in runtime_smoke,
      "runtime smoke covers interior and shared-boundary classification")
check('room interiors do not overlap with positive volume' in runtime_smoke,
      "runtime smoke checks for overlapping room interiors")
check('floor label text comes from the registry' in runtime_smoke,
      "runtime smoke checks label-to-registry data binding")

print("Room registry static checks passed. These do not execute GDScript.")
