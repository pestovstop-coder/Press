"""TASK 010: source/geometry/light invariants, NOT Godot rendering or picking.

Run from repo root: python3 tests/open_layout_check.py
Requires the TASK 009 base commit locally for an exact architectural comparison.
"""

import itertools
import math
from pathlib import Path
import re
import subprocess

from layout_blockout_check import capacity, ray_box, read_scene

BASE = "6a765c81a68eb70f100a4b95d5aded6bcb4b8d72"
ROOT = Path(__file__).resolve().parents[1]


def old_file(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)


def occupied(point, boxes):
    return any(
        all(lo < p < hi for p, lo, hi in zip(point, box["low"], box["high"]))
        for name, box in boxes.items()
        if name != "Floor"
    )


def visibility(boxes, zones):
    """Reciprocal rays from proposed desk surfaces towards unchanged camera.

    Only architectural BoxMesh occlusion, not GUI, GLB picking or lighting.
    """
    direction = (1 / math.sqrt(3),) * 3
    visible, total = 0, 0
    for kind, (x, z, width, _) in zones:
        if kind != "workplace":
            continue
        for u, v in itertools.product((0.1, 0.3, 0.5, 0.7, 0.9), repeat=2):
            point = (x + width * u, 0.75, z + 0.8 * v)
            nearest = min(
                ray_box(point, direction, box)
                for name, box in boxes.items()
                if name != "Floor"
            )
            visible += not math.isfinite(nearest)
            total += 1
    return visible, total


def check():
    _, old_nodes, old_boxes = read_scene(old_file("scenes/main.tscn").decode())
    text, nodes, boxes = read_scene()
    low_names = ["WestWall", "EastWall", "SharedWall"] + [
        f"Front{side}Pier{letter}"
        for side in ("Left", "Right")
        for letter in ("A", "B")
    ]
    for name in low_names:
        assert boxes[name]["low"][1] == 0 and boxes[name]["high"][1] == 0.9
    for name in ("RearWestCorner", "RearSharedCorner", "RearEastCorner"):
        assert boxes[name]["low"][1] == 0 and boxes[name]["high"][1] == 3
        assert math.isclose(boxes[name]["low"][2], -4.25) and math.isclose(
            boxes[name]["high"][2], -4.05
        )
    for name in old_boxes:
        if name.startswith(("Rear", "Window", "Door")) or name == "Floor":
            assert boxes[name] == old_boxes[name], name
    assert "FrontLeftLintel" not in nodes and "FrontRightLintel" not in nodes
    assert nodes["OfficeDesk"] == old_nodes["OfficeDesk"]
    print(
        "PASS: all seven borders 0.9m; full 3m rear returns; original rear/window/door/floor/desk geometry preserved"
    )
    # Exact rectilinear slice comparison at border height: every cell between
    # the combined old/new X/Z boundaries has the same occupancy.
    boundaries = []
    for axis in (0, 2):
        values = {
            b[k][axis]
            for group in (old_boxes, boxes)
            for n, b in group.items()
            if n != "Floor"
            for k in ("low", "high")
        }
        values = sorted(values)
        boundaries.append(
            [(a + b) / 2 for a, b in zip(values, values[1:]) if b - a > 1e-7]
        )
    for x, z in itertools.product(*boundaries):
        assert occupied((x, 0.45, z), old_boxes) == occupied((x, 0.45, z), boxes), (
            x,
            z,
        )
    print(
        "PASS: exact low-level architectural footprint slice unchanged, including both entrances"
    )
    assert ray_box((-0.5, 0.45, -1), (1, 0, 0), boxes["SharedWall"]) < 1
    assert not math.isfinite(ray_box((-0.5, 1.2, -1), (1, 0, 0), boxes["SharedWall"]))
    print(
        "PASS: low partition still occludes below 0.9m; ray above it is clear (geometry only, not runtime picking)"
    )
    for room, zones in capacity().items():
        old_visible, total = visibility(old_boxes, zones)
        visible, _ = visibility(boxes, zones)
        assert visible > old_visible and visible / total >= 0.8
        print(
            f"PASS: {room}: offline worktop samples visible {old_visible}/{total} -> {visible}/{total} from unchanged camera direction"
        )
    lights = {
        n: v
        for n, v in nodes.items()
        if re.search(r'type="(?:Directional|Omni|Spot)Light3D"', v["header"])
    }
    old_lights = {
        n
        for n, v in old_nodes.items()
        if re.search(r'type="(?:Directional|Omni|Spot)Light3D"', v["header"])
    }
    assert set(lights) == old_lights and len(lights) == 9
    shadow_casters = [
        n for n, v in lights.items() if "shadow_enabled = true" in v["body"]
    ]
    assert shadow_casters == ["Sun"]
    for name, node in lights.items():
        if name != "Sun":
            assert "shadow_enabled = false" in node["body"]
            new_energy = float(re.search(r"light_energy = ([\d.]+)", node["body"])[1])
            old_energy = float(
                re.search(r"light_energy = ([\d.]+)", old_nodes[name]["body"])[1]
            )
            assert new_energy <= old_energy
    print(
        "PASS: exactly one shadow caster (Sun), eight shadowless fills; no new lights, fill energies reduced"
    )
    for path in [
        "scripts/camera_controller.gd",
        "scripts/placement_controller.gd",
        "project.godot",
        "assets/materials/floor.tres",
        "assets/materials/wall.tres",
        "assets/materials/doorway.tres",
        "assets/materials/window_frame.tres",
        "assets/models/furniture/desks/office_desk.glb",
    ]:
        assert (ROOT / path).read_bytes() == old_file(path), path
    for name in ("CameraRig", "Camera3D", "PlacementController"):
        assert nodes[name] == old_nodes[name], name
    print(
        "PASS: camera, controls, placement states/logic, renderer, model and palette byte-identical to base"
    )
    print(
        "NOT VERIFIED: Godot rendering/input, soft/contact shadows, exposure, actual editor picking, known TASK 008 defects"
    )


if __name__ == "__main__":
    check()
