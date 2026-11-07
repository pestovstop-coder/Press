"""TASK011.1: static invariants / independent Python geometry-animation MODEL.

Not execution of GDScript, Godot rendering, input or picking.
"""

import itertools
import math
from pathlib import Path
import re
import subprocess

from layout_blockout_check import read_scene, ray_box
from orbit_layout_check import classify, module_sides

ROOT = Path(__file__).resolve().parents[1]
BASE = "d87090f6cace58384b1efc7f485409e6b3d54d09"


def old_file(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)


def parameters():
    return {
        k: float(v)
        for k, v in re.findall(
            r"const (\w+): float = ([\d.]+)",
            (ROOT / "scripts/wall_visibility.gd").read_text(),
        )
    }


def advance(heights, targets, delta):
    c = parameters()
    weight = 1 - math.exp(-c["RESPONSE"] * max(delta, 0))
    result = {}
    for side, height in heights.items():
        goal = c["LOW_HEIGHT"] if targets[side] else c["FULL_HEIGHT"]
        value = height + (goal - height) * weight
        result[side] = goal if abs(value - goal) < c["EPSILON"] else value
    return result


def clip_boxes(boxes, membership, heights):
    result = {"Floor": boxes["Floor"]}
    eps = parameters()["EPSILON"]
    for name, sides in membership.items():
        b = boxes[name]
        top = min(b["high"][1], max(heights[side] for side in sides))
        bottom = b["low"][1]
        if top - bottom <= eps:
            continue
        result[name] = {
            "low": (b["low"][0], bottom, b["low"][2]),
            "high": (b["high"][0], top, b["high"][2]),
            "size": (b["size"][0], top - bottom, b["size"][2]),
            "center": (b["center"][0], (bottom + top) / 2, b["center"][2]),
        }
    return result


def solid(point, boxes):
    return any(
        all(
            lo - 1e-7 <= v <= hi + 1e-7 for v, lo, hi in zip(point, b["low"], b["high"])
        )
        for n, b in boxes.items()
        if n != "Floor"
    )


def check():
    text, nodes, boxes = read_scene()
    _, old_nodes, old_boxes = read_scene(old_file("scenes/main.tscn").decode())
    membership = module_sides(nodes)
    assert len(boxes) == 40 and set(membership) == set(boxes) - {"Floor"}
    changed = {"WestWall", "EastWall", "SharedWall"}
    new = {"FrontWestCorner", "FrontSharedCorner", "FrontEastCorner"}
    assert set(boxes) == set(old_boxes) | new
    for n, b in old_boxes.items():
        if n not in changed:
            assert boxes[n] == b, n
    for n in changed:
        assert boxes[n]["size"] == (0.2, 3, 5.7)
        assert math.isclose(boxes[n]["high"][2], 1.65)
    for n, x, side in [
        ("FrontWestCorner", -5.9, "west"),
        ("FrontSharedCorner", 0, "shared"),
        ("FrontEastCorner", 5.9, "east"),
    ]:
        assert boxes[n]["size"] == (0.2, 3, 0.2) and boxes[n]["center"] == (
            x,
            1.5,
            1.75,
        )
        assert membership[n] == ["front", side]
    # Complete rectilinear occupancy at several heights: split modules must not
    # add/remove any physical wall footprint or fill any door/window aperture.
    axes = []
    for axis in (0, 2):
        values = sorted(
            {
                b[bound][axis]
                for group in (boxes, old_boxes)
                for n, b in group.items()
                if n != "Floor"
                for bound in ("low", "high")
            }
        )
        axes.append([(a + b) / 2 for a, b in zip(values, values[1:]) if b - a > 1e-7])
    for x, z, y in itertools.product(*axes, (0.45, 1.5, 2.7)):
        assert solid((x, y, z), boxes) == solid((x, y, z), old_boxes), (x, y, z)
    print(
        "PASS: exact full-height occupancy preserved; 40 modules; 3 front junctions split without overlap or aperture changes"
    )
    for path in (
        "scripts/camera_controller.gd",
        "scripts/placement_controller.gd",
        "project.godot",
        "assets/materials/wall.tres",
        "assets/materials/floor.tres",
        "assets/materials/window_frame.tres",
        "assets/materials/doorway.tres",
        "assets/models/furniture/desks/office_desk.glb",
    ):
        assert (ROOT / path).read_bytes() == old_file(path), path
    for name in old_nodes:
        if "Light3D" in old_nodes[name]["header"]:
            assert nodes[name]["body"].strip() == old_nodes[name]["body"].strip(), name
    env = r'\[sub_resource type="Environment"[^\n]+\]\n(.*?)(?=\[)'
    assert (
        re.search(env, text, re.S)[1]
        == re.search(env, old_file("scenes/main.tscn").decode(), re.S)[1]
    )
    assert "CollisionShape" not in text and "Body3D" not in text
    print(
        "PASS: camera, placement code, assets, renderer, entire lighting/ambient byte-identical; no physics added"
    )
    source = (ROOT / "scripts/wall_visibility.gd").read_text()
    for required in (
        "child.mesh = authored.duplicate() as BoxMesh",
        "placement.face_cache.erase(box)",
        "box.size = clipped_size",
        "top - bottom <= EPSILON",
        "mesh.visible = false",
        "maxf(height, float(heights[side]))",
        "1.0 - exp(-RESPONSE * maxf(delta, 0.0))",
    ):
        assert required in source, required
    assert not re.search(r"(?:mesh|child)\.scale\s*=", source)
    print(
        "PASS: unique geometry, per-module top clipping, zero-height guard, cache invalidation and max-of-current junction rule present in source (not executed)"
    )
    c = parameters()
    heights = {s: 3.0 for s in classify(45)}
    for yaw in (45, 135, 225, 315, 405, 0, 180, 90, 270):
        targets = classify(yaw)
        previous = heights.copy()
        for step in range(90):
            heights = advance(heights, targets, 1 / 60)
            clipped = clip_boxes(boxes, membership, heights)
            for side, h in heights.items():
                assert 0.9 <= h <= 3
                goal = 0.9 if targets[side] else 3
                assert abs(h - goal) <= abs(previous[side] - goal) + 1e-12
                assert (
                    abs(h - previous[side]) < 0.27
                )  # bounded 60fps progress, not a 2.1m snap
            for name, b in clipped.items():
                if name == "Floor":
                    continue
                orig = boxes[name]
                assert b["size"][1] > c["EPSILON"]
                assert b["low"][1] == orig["low"][1]
                for axis in (0, 2):
                    assert (
                        b["low"][axis] == orig["low"][axis]
                        and b["high"][axis] == orig["high"][axis]
                    )
                assert b["high"][1] <= orig["high"][1] + 1e-9
                if orig["low"][1] == 0:
                    assert b["high"][1] >= 0.9 - 1e-9
            for n, sides in membership.items():
                if len(sides) == 2:
                    assert n in clipped
                    assert math.isclose(
                        clipped[n]["high"][1], max(heights[s] for s in sides)
                    )
            # The corridor-facing T intersection stays filled up to the taller
            # adjacent wall at EVERY intermediate frame, not just endpoints.
            join = max(heights["front"], heights["shared"])
            assert solid((0, join - 1e-5, 1.75), clipped)
            for x in (-3, 3):
                assert not solid((x, 0.45, 1.75), clipped)  # door remains open
            for x in (-3.55, 3.55):
                assert not solid((x, 1.6, -4.15), clipped)  # window remains open
            previous = heights.copy()
        assert all(h == (0.9 if targets[s] else 3) for s, h in heights.items())
    # 30/60/120 Hz agreement before tiny terminal snap.
    result = []
    for hz in (30, 60, 120):
        h = dict.fromkeys(heights, 3)
        for _ in range(hz // 2):
            h = advance(h, dict.fromkeys(h, True), 1 / hz)
        result.append(h["front"])
    assert max(result) - min(result) < 1e-12
    assert advance(heights, classify(45), 0) == heights
    print(
        "PASS: offline animation monotonic/bounded, 30/60/120Hz equivalent; all walls retain >=0.9m; front/rear junctions continuous at EVERY sampled frame; apertures unchanged"
    )
    for turn in (0, 90, 180, 270, 360):
        state = classify(45 + turn)
        h = {s: 0.9 if v else 3 for s, v in state.items()}
        clipped = clip_boxes(boxes, membership, h)
        assert (
            "SharedWall" in clipped and "WestWall" in clipped and "EastWall" in clipped
        )
        print(
            f"PASS: offline orbit +{turn}: lowered {[s for s,v in state.items() if v]}; structural bases remain"
        )
    for visible in (False, True):
        state = dict.fromkeys(heights, visible)
        for dx in (-0.001, 0.001) * 50:
            state = classify(math.degrees(math.asin(0.08 + dx)), state)
            assert state["east"] == visible
    # Model the exact two picking situations around a lowered full-length wall.
    low = clip_boxes(boxes, membership, dict.fromkeys(heights, 0.9))
    assert ray_box((-8, 0.45, -1), (1, 0, 0), low["WestWall"]) < 3
    assert not math.isfinite(ray_box((-8, 1.2, -1), (1, 0, 0), low["WestWall"]))
    assert ray_box((-8, 1.2, -1), (1, 0, 0), boxes["WestWall"]) < 3
    assert "DoorLeftHead" not in low and "WindowLeftHead" not in low
    restored = clip_boxes(boxes, membership, dict.fromkeys(heights, 3))
    assert set(restored) == set(boxes)
    for name in boxes:
        for key in ("low", "high", "size", "center"):
            assert all(
                math.isclose(a, b, abs_tol=1e-12)
                for a, b in zip(restored[name][key], boxes[name][key])
            )
    print(
        "PASS: offline low rays blocked / above-cut rays clear / full walls block; upper headers clipped away, full restoration exact; hysteresis stable"
    )
    print(
        "NOT VERIFIED: Godot compilation/input/animation/picking/shadows; TASK008 defects remain OPEN."
    )


def diagram():
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    heights = dict.fromkeys(classify(45), 3.0)
    samples = []
    for frame in range(181):
        time = frame / 60
        samples.append(
            (
                time,
                heights["front"],
                heights["shared"],
                max(heights["front"], heights["shared"]),
            )
        )
        heights = advance(heights, classify(135 if time < 1.1 else 0), 1 / 60)
    fig, ax = plt.subplots(figsize=(11, 5))
    for index, label in (
        (1, "Front"),
        (2, "Shared"),
        (3, "Front/shared junction = max(current)"),
    ):
        ax.plot(
            [s[0] for s in samples],
            [s[index] for s in samples],
            label=label,
            linestyle="--" if index == 3 else "-",
        )
    ax.axvline(1.1, color="#999999", linestyle=":", label="Target direction changes")
    ax.set(
        xlabel="Seconds (60Hz Python model)",
        ylabel="Height above floor, metres",
        ylim=(0.7, 3.2),
    )
    ax.set_title(
        "TASK 011.1 — OFFLINE animation logic, NOT Godot\nContinuous height and junction during target reversal; no lighting/input simulation"
    )
    ax.grid(alpha=0.2)
    ax.legend()
    out = ROOT / "evidence/task011_1/offline_height_transition.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=130, bbox_inches="tight")
    plt.close(fig)
    print("Wrote offline height logic graph, NOT engine evidence")


if __name__ == "__main__":
    import sys

    check()
    if "--diagram" in sys.argv:
        diagram()
