"""TASK011 static invariants and Python visibility/orbit MODEL, not Godot execution."""

import itertools
import math
from pathlib import Path
import re
import subprocess

from layout_blockout_check import capacity, ray_box, read_scene

ROOT = Path(__file__).resolve().parents[1]
BASE = "389ab8c602b136d28d3c95815242833e38bc53f5"


def old_file(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)


def constants():
    source = (ROOT / "scripts/wall_visibility.gd").read_text()
    return {
        k: float(v) for k, v in re.findall(r"const (\w+): float = ([\d.]+)", source)
    }


def classify(yaw, previous=None):
    """Explicit offline mirror; source checks below bind thresholds/rule terms."""
    c = constants()
    x, z = math.sin(math.radians(yaw)), math.cos(math.radians(yaw))
    result = dict(
        previous or dict.fromkeys(("front", "rear", "east", "west", "shared"), False)
    )
    for side, facing in (
        ("front", z),
        ("rear", -z),
        ("east", x),
        ("west", -x),
        ("shared", abs(x)),
    ):
        hide, show = (
            (c["SHARED_HIDE"], c["SHARED_SHOW"])
            if side == "shared"
            else (c["HIDE_THRESHOLD"], c["SHOW_THRESHOLD"])
        )
        if facing > hide:
            result[side] = True
        elif facing < show:
            result[side] = False
    return result


def module_sides(nodes):
    return {
        name: re.search(r'metadata/cutaway_side = "([^"]+)"', n["body"])[1].split("_")
        for name, n in nodes.items()
        if "metadata/cutaway_side" in n["body"]
    }


def visible_modules(membership, state):
    return {
        name
        for name, sides in membership.items()
        if not all(state[side] for side in sides)
    }


def canonical(text):
    return re.sub(r"\s+", "", re.sub(r"#[^\n]*", "", text))


def check():
    _, nodes, boxes = read_scene()
    _, old_nodes, old_boxes = read_scene(old_file("scenes/main.tscn").decode())
    members = module_sides(nodes)
    assert set(members) == set(boxes) - {"Floor"}
    assert len(boxes) == 37
    for name in (
        "WestWall",
        "EastWall",
        "SharedWall",
        "FrontLeftPierA",
        "FrontLeftPierB",
        "FrontRightPierA",
        "FrontRightPierB",
    ):
        assert boxes[name]["low"][1] == 0 and boxes[name]["high"][1] == 3
        for axis in (0, 2):
            assert boxes[name]["low"][axis] == old_boxes[name]["low"][axis]
            assert boxes[name]["high"][axis] == old_boxes[name]["high"][axis]
    for name, box in old_boxes.items():
        if name not in ("WestWall", "EastWall", "SharedWall") and not name.startswith(
            "Front"
        ):
            assert boxes[name] == box, name
    for side in ("Left", "Right"):
        assert boxes[f"Front{side}Lintel"]["low"][1] == 2.2
        for name in members:
            if name.startswith((f"Door{side}", f"Front{side}")):
                assert members[name] == ["front"]
            if name.startswith((f"Window{side}", f"Rear{side}")):
                assert members[name] == ["rear"]
    for yaw in range(0, 360):
        state = classify(yaw)
        visible = visible_modules(members, state)
        if not state["rear"]:
            assert all(
                n in visible for n in members if n.startswith(("Rear", "Window"))
            )
        if not state["west"]:
            assert "RearWestCorner" in visible
        if not state["east"]:
            assert "RearEastCorner" in visible
    print(
        "PASS: full 3m main walls; exact old footprint, floor, rear/windows/frames retained; 36 tagged wall modules including restored door lintels"
    )
    for name in ("OfficeDesk", "Camera3D"):
        assert nodes[name]["body"].strip() == old_nodes[name]["body"].strip()
    for name, n in old_nodes.items():
        if "Light3D" in n["header"]:
            assert nodes[name]["body"].strip() == n["body"].strip(), name
    for path in (
        "project.godot",
        "assets/materials/floor.tres",
        "assets/materials/wall.tres",
        "assets/materials/doorway.tres",
        "assets/materials/window_frame.tres",
        "assets/models/furniture/desks/office_desk.glb",
    ):
        assert (ROOT / path).read_bytes() == old_file(path), path
    scene = (ROOT / "scenes/main.tscn").read_text()
    assert scene.count("shadow_enabled = true") == 1
    assert "CollisionShape" not in scene and "StaticBody" not in scene
    print(
        "PASS: desk, camera projection/local offset, materials, renderer and entire TASK010 lighting unchanged; no physics bodies added"
    )
    controller = (ROOT / "scripts/placement_controller.gd").read_text()
    expected = (
        old_file("scripts/placement_controller.gd")
        .decode()
        .replace(
            "not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)",
            "not camera.get_parent().is_navigating()",
        )
    )
    assert canonical(controller) == canonical(expected)
    assert "not mesh.is_visible_in_tree()" in controller
    print(
        "PASS: placement logic unchanged except navigation-chord input guard; invisible meshes still excluded from cached-triangle picking"
    )
    camera = (ROOT / "scripts/camera_controller.gd").read_text()
    visibility = (ROOT / "scripts/wall_visibility.gd").read_text()
    for term in (
        '_latch("front", direction.z',
        '_latch("rear", -direction.z',
        '_latch("east", direction.x',
        '_latch("west", -direction.x',
        '_latch("shared", absf(direction.x)',
        "mesh.visible = not hidden",
        "hidden = hidden and bool(hidden_sides[part])",
    ):
        assert term in visibility
    assert 'connect("view_changed", _sync_from_camera)' in visibility
    assert "view_changed.emit()" in camera and "func _input" in camera
    assert (
        "MOUSE_BUTTON_RIGHT" in camera
        and "MOUSE_BUTTON_LEFT and is_navigating()" in camera
    )
    for term in (
        "MIN_PITCH: float = -70.0",
        "MAX_PITCH: float = -20.0",
        "wrapf(rotation_degrees.y",
        "clampf(rotation_degrees.x",
        "func _reset",
        "NOTIFICATION_APPLICATION_FOCUS_OUT",
    ):
        assert term in camera
    print(
        "PASS: source input guards, immediate visibility signal, orbit wrapping/clamping and Home reset present (not executed)"
    )
    expected_sets = [
        {"front", "east", "shared"},
        {"rear", "east", "shared"},
        {"rear", "west", "shared"},
        {"front", "west", "shared"},
    ]
    for turn, expected_set in zip((0, 90, 180, 270), expected_sets):
        yaw = 45 + turn
        state = classify(yaw)
        assert {k for k, v in state.items() if v} == expected_set
        visible = visible_modules(members, state)
        direction = (
            math.sin(math.radians(yaw)) / math.sqrt(3 / 2),
            1 / math.sqrt(3),
            math.cos(math.radians(yaw)) / math.sqrt(3 / 2),
        )
        for room, zones in capacity().items():
            count = 0
            for kind, (x, z, w, _) in zones:
                if kind != "workplace":
                    continue
                for u, v in itertools.product((0.1, 0.3, 0.5, 0.7, 0.9), repeat=2):
                    point = (x + w * u, 0.75, z + 0.8 * v)
                    count += not any(
                        math.isfinite(ray_box(point, direction, boxes[n]))
                        for n in visible
                    )
            assert count == 125, (turn, room, count)
        print(
            f"PASS: offline +{turn}deg yaw={yaw % 360}: hidden {sorted(expected_set)}; worktop samples 125/125 clear in EACH room"
        )
    state = classify(45)
    initial = state.copy()
    seen_visible, seen_hidden = set(), set()
    for i in range(1, 1441):
        state = classify(45 + i / 4, state)
        visible = visible_modules(members, state)
        seen_visible |= visible
        seen_hidden |= set(members) - visible
    assert state == initial and seen_visible == seen_hidden == set(members)
    for yaw in (0, 180):
        assert not classify(yaw)["shared"]
    for side, threshold in (("east", 0.08), ("shared", 0.14)):
        for initially_hidden in (False, True):
            state = dict.fromkeys(initial, initially_hidden)
            for perturbation in (-0.001, 0.001) * 50:
                state = classify(
                    math.degrees(math.asin(threshold + perturbation)), state
                )
                assert state[side] == initially_hidden
    for pitch in (-70, -35.26438968, -20):
        for yaw in range(0, 360, 5):
            x = 30 * math.cos(math.radians(pitch)) * math.sin(math.radians(yaw))
            y = -30 * math.sin(math.radians(pitch))
            z = 30 * math.cos(math.radians(pitch)) * math.cos(math.radians(yaw))
            assert y > 10 and math.isclose(x * x + y * y + z * z, 900)
    print(
        "PASS: offline full 360deg cycle restores state; every module can hide AND reappear; hysteresis jitter stable; orbit radius 30m, height >10m at pitch limits"
    )
    print(
        "NOT VERIFIED: engine import/compilation, actual RMB/MMB/GUI/input, visual occlusion/shadows, placement regression. TASK008 defects OPEN."
    )


if __name__ == "__main__":
    check()
