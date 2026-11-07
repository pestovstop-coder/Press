"""TASK 010: independent static checks of the authored TSCN, not Godot runtime.

Run from the repository root: python3 tests/layout_blockout_check.py
Optional --preview renders offline diagrams with matplotlib (not Godot lighting).
"""

import argparse
import itertools
import json
import math
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / "scenes/main.tscn"


def vector(text):
    return tuple(float(v.strip()) for v in text.split(","))


def read_scene(text=None):
    text = SCENE.read_text() if text is None else text
    resources = {}
    nodes = {}
    for header, body in re.findall(
        r"^(\[[^\n]+\])\n(.*?)(?=^\[|\Z)", text, re.M | re.S
    ):
        if header.startswith('[sub_resource type="BoxMesh"'):
            name = re.search(r'id="([^"]+)"', header)[1]
            resources[name] = vector(re.search(r"size = Vector3\(([^)]+)\)", body)[1])
        elif header.startswith("[node "):
            name = re.search(r'name="([^"]+)"', header)[1]
            nodes[name] = {"header": header, "body": body}
    boxes = {}
    for name, node in nodes.items():
        mesh = re.search(r'mesh = SubResource\("([^"]+)"\)', node["body"])
        if not mesh:
            continue
        size = resources[mesh[1]]
        center = vector(re.search(r"position = Vector3\(([^)]+)\)", node["body"])[1])
        boxes[name] = {
            "size": size,
            "center": center,
            "low": tuple(c - s / 2 for c, s in zip(center, size)),
            "high": tuple(c + s / 2 for c, s in zip(center, size)),
        }
    return text, nodes, boxes


def ray_box(origin, direction, box):
    near, far = 0.0, math.inf
    for o, d, low, high in zip(origin, direction, box["low"], box["high"]):
        if abs(d) < 1e-9:
            if o < low - 1e-8 or o > high + 1e-8:
                return math.inf
            continue
        a, b = sorted(((low - o) / d, (high - o) / d))
        near, far = max(near, a), min(far, b)
        if near > far + 1e-8:
            return math.inf
    return near if far >= 0 else math.inf


def capacity():
    """Draft planning envelopes ONLY, not scene objects, assets or pathfinding."""
    result = {}
    for room, base in [("Left", -6), ("Right", 0)]:
        zones = []
        for col, x in enumerate((0.45, 3.95)):
            rows = [(-3.95, -2.55), (-1.65, -0.25)]
            if col == 0:
                rows.append((0.15, 1.55))
            for z0, z1 in rows:
                zones.append(("workplace", (base + x, z0, 1.6, z1 - z0)))
        zones.extend(
            [
                ("sofa", (base + 5, -0.15, 0.75, 1.7)),
                ("coffee table", (base + 4.15, 0.3, 0.5, 0.8)),
                ("storage", (base + 2.35, -3.95, 1.2, 0.4)),
            ]
        )
        result[room] = zones
    return result


def check():
    text, nodes, boxes = read_scene()
    floor = boxes["Floor"]
    assert floor["size"] == (12, 0.2, 8.5)
    assert floor["high"][1] == 0 and len(boxes) == 35
    assert abs(12 * 8.5 - 102) < 1e-8
    print("PASS: one 12 x 8.5m floor, top Y=0, area 102m2; 35 modular meshes")
    walls = {n: b for n, b in boxes.items() if n != "Floor"}
    for name, box in walls.items():
        assert all(s > 0 for s in box["size"]), name
        assert box["low"][1] >= -1e-8, name
        assert box["low"][0] >= -6 - 1e-8 and box["high"][0] <= 6 + 1e-8
        assert box["low"][2] >= -4.25 - 1e-8 and box["high"][2] <= 4.25 + 1e-8
    for (an, a), (bn, b) in itertools.combinations(walls.items(), 2):
        overlap = [
            min(a["high"][i], b["high"][i]) - max(a["low"][i], b["low"][i])
            for i in range(3)
        ]
        assert not all(v > 1e-7 for v in overlap), ("Overlapping volumes", an, bn)
    print(
        "PASS: positive dimensions; all wall/frame volumes fit footprint, no positive-volume overlaps"
    )

    def solid(point):
        return any(
            all(
                lo - 1e-8 <= p <= hi + 1e-8
                for p, lo, hi in zip(point, box["low"], box["high"])
            )
            for box in walls.values()
        )

    # Sample the full structural seams, not just isolated aperture centres.
    for i in range(119):
        x = -5.9 + i * 0.1
        for y in (0.4, 1.5, 2.7):
            rear_open = (
                any(abs(x - c) < 1.15 and abs(x - c) > 0.02 for c in (-3, 3))
                and 0.95 < y < 2.25
            )
            assert solid((x, y, -4.15)) == (not rear_open), ("rear seam", x, y)
            door_open = any(abs(x - c) < 0.56 for c in (-3, 3)) and y < 2.16
            jamb = (
                any(0.56 - 1e-8 <= abs(x - c) <= 0.6 + 1e-8 for c in (-3, 3))
                and y <= 2.2
            )
            expected_front = (y < 0.9 and not door_open) or jamb
            assert solid((x, y, 1.75)) == expected_front, ("front seam", x, y)
    for i in range(61):
        z = -4.2 + i * 0.1
        for x in (-5.9, 0, 5.9):
            assert solid((x, 0.45, z)), ("side/shared low seam", x, z)
            assert solid((x, 1.5, z)) == (z <= -4.05 + 1e-8), (
                "rear return/high cutaway",
                x,
                z,
            )
    print(
        "PASS: structural seams sampled continuously; rear wall closed except windows; low borders continuous, upper cutaway open"
    )
    for side, center in [("Left", -3), ("Right", 3)]:
        # Check every part of the clear door width/height across wall thickness.
        for dx in (-0.54, 0, 0.54):
            for y in (0.1, 1, 2.1):
                origin = (center + dx, y, 2.5)
                assert min(ray_box(origin, (0, 0, -1), b) for b in walls.values()) > 1.5
        # Each side of the central mullion is a real clear window aperture.
        for dx in (-0.55, 0.55):
            for y in (1.05, 1.6, 2.15):
                origin = (center + dx, y, -5)
                assert min(ray_box(origin, (0, 0, 1), b) for b in walls.values()) > 1.2
        # Closed structural wall must exist below the window and above its head.
        for y in (0.5, 2.6):
            assert (
                ray_box(
                    (center, y, -5),
                    (0, 0, 1),
                    boxes[
                        f"Rear{side}BelowWindow" if y < 1 else f"Rear{side}AboveWindow"
                    ],
                )
                < 1
            )
        # Geometric axis only: shadowless spots do NOT physically occlude their fill.
        body = nodes[f"Window{side}Daylight"]["body"]
        origin = vector(re.search(r"position = Vector3\(([^)]+)\)", body)[1])
        pitch, yaw, _ = vector(
            re.search(r"rotation_degrees = Vector3\(([^)]+)\)", body)[1]
        )
        pitch, yaw = math.radians(pitch), math.radians(yaw)
        direction = (
            -math.sin(yaw) * math.cos(pitch),
            math.sin(pitch),
            -math.cos(yaw) * math.cos(pitch),
        )
        distance = -origin[1] / direction[1]
        assert min(ray_box(origin, direction, b) for b in walls.values()) > distance
        landing = tuple(o + d * distance for o, d in zip(origin, direction))
        assert -4.05 < landing[2] < 1.65
        print(
            f"PASS: {side}: door clear 1.12 x 2.16m; 2 window apertures 1.13 x 1.30m; window-fill axis geometrically reaches office floor at {tuple(round(v, 3) for v in landing)}"
        )
    # No obstacles at the open corridor front; walls reach Y=0 or meet supported jamb/sill.
    assert all(b["high"][2] < 2 for b in walls.values())
    for name, box in walls.items():
        y = box["low"][1]
        if y < 1e-7:
            continue
        assert any(
            (
                abs(other["high"][axis] - box["low"][axis]) < 1e-7
                or abs(other["low"][axis] - box["high"][axis]) < 1e-7
            )
            and all(
                min(box["high"][i], other["high"][i])
                - max(box["low"][i], other["low"][i])
                > 1e-7
                for i in range(3)
                if i != axis
            )
            for other_name, other in walls.items()
            if other_name != name
            for axis in range(3)
        ), name

    print(
        "PASS: corridor front open; elevated headers/frames have geometric support, floor/wall baseline continuous"
    )
    for room, zones in capacity().items():
        low, high = (-5.8, -0.1) if room == "Left" else (0.1, 5.8)
        assert sum(kind == "workplace" for kind, _ in zones) == 5
        for kind, (x, z, w, d) in zones:
            assert (
                low <= x
                and x + w <= high + 1e-8
                and z >= -4.05
                and z + d <= 1.65 + 1e-8
            )
        for a, b in itertools.combinations(zones, 2):
            x, z, w, d = a[1]
            xx, zz, ww, dd = b[1]
            assert (
                min(x + w, xx + ww) - max(x, xx) <= 1e-7
                or min(z + d, zz + dd) - max(z, zz) <= 1e-7
            )
        # Reserved entry aisle 1.9m and cross aisle 0.9m, not a navigation guarantee.
        print(
            f"PASS: {room}: 5 planning workplace envelopes 1.6 x 1.4m, sofa/table/storage fit without overlap"
        )
    # Orthographic projection at unchanged isometric angle; all corners fit 16:9.
    points = [
        p for b in boxes.values() for p in itertools.product(*zip(b["low"], b["high"]))
    ]
    for x, y, z in points:
        screen_x = (x - z) / math.sqrt(2)
        screen_y = -(x + z) / math.sqrt(6) + y * math.sqrt(2 / 3)
        assert abs(screen_x) < 16 * (16 / 9) / 2 and abs(screen_y) < 8
    assert "size = 16.0" in nodes["Camera3D"]["body"]
    for path in re.findall(r'path="res://([^"]+)"', text):
        assert (ROOT / path).exists(), path
    assert int(re.search(r"load_steps=(\d+)", text)[1]) == 1 + text.count(
        "[ext_resource "
    ) + text.count("[sub_resource ")
    print(
        "PASS: geometry fits initial 16:9 camera frustum at unchanged isometric angle (not a visibility/occlusion test)"
    )
    print(
        "PASS: resource paths/load_steps; no runtime, lighting or editor acceptance claimed"
    )
    return nodes, boxes


def previews(nodes, boxes):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Rectangle
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    out = ROOT / "evidence/task010"
    out.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(12, 9))
    ax.add_patch(Rectangle((-6, -4.25), 12, 8.5, facecolor="#b7b1a3"))
    colors = {
        "workplace": "#678ea0",
        "sofa": "#84967a",
        "coffee table": "#b99565",
        "storage": "#8e8b87",
    }
    for room, zones in capacity().items():
        for kind, (x, z, w, d) in zones:
            ax.add_patch(
                Rectangle(
                    (x, z),
                    w,
                    d,
                    facecolor=colors[kind],
                    alpha=0.7,
                    edgecolor="#444444",
                    linestyle="--",
                )
            )
            ax.text(x + w / 2, z + d / 2, kind, ha="center", va="center", fontsize=8)
    for name, b in boxes.items():
        if name == "Floor" or b["low"][1] > 2:
            continue
        x, _, z = b["low"]
        w, _, d = b["size"]
        ax.add_patch(
            Rectangle(
                (x, z),
                w,
                d,
                facecolor=(
                    "#505858" if "Window" in name or "Door" in name else "#d4d0c5"
                ),
                edgecolor="#555555",
                linewidth=0.4,
            )
        )
    ax.axhline(1.75, color="#666666", linestyle=":", linewidth=0.7)
    ax.text(-3, -4.55, "Office 1: 6 x 6 m nominal", ha="center")
    ax.text(3, -4.55, "Office 2: 6 x 6 m nominal", ha="center")
    ax.text(0, 3.2, "Shared corridor: 12 x 2.5 m nominal / open front", ha="center")
    ax.set(
        xlim=(-6.5, 6.5),
        ylim=(4.7, -4.9),
        xlabel="World X (metres)",
        ylabel="World Z (metres)",
        aspect="equal",
    )
    ax.set_title(
        "TASK 010 — OFFLINE dimension/capacity plan, NOT Godot\nDashed coloured zones are planning envelopes only, NOT furniture in scene",
        fontsize=12,
    )
    fig.savefig(out / "offline_plan.png", dpi=140, bbox_inches="tight")
    plt.close(fig)
    for filename, az in [("offline_isometric.png", 45), ("offline_reverse.png", -130)]:
        fig = plt.figure(figsize=(12, 9), facecolor="#e5e7e8")
        ax = fig.add_subplot(
            projection="3d", facecolor="#e5e7e8", computed_zorder=False
        )
        polygons = []
        colors_out = []
        floor_polygons, floor_colors = [], []
        for name, b in boxes.items():
            x0, y0, z0 = b["low"]
            x1, y1, z1 = b["high"]
            # Matplotlib Z-up; show actual geometry, no cutaway walls.
            verts = [
                (x0, z0, y0),
                (x1, z0, y0),
                (x1, z1, y0),
                (x0, z1, y0),
                (x0, z0, y1),
                (x1, z0, y1),
                (x1, z1, y1),
                (x0, z1, y1),
            ]
            faces = [
                (0, 1, 2, 3),
                (4, 7, 6, 5),
                (0, 4, 5, 1),
                (1, 5, 6, 2),
                (2, 6, 7, 3),
                (3, 7, 4, 0),
            ]
            base = (
                (0.72, 0.69, 0.64)
                if name == "Floor"
                else (
                    (0.38, 0.4, 0.41)
                    if "Window" in name or "Door" in name
                    else (0.83, 0.815, 0.77)
                )
            )
            for i, face in enumerate(faces):
                target_polys = floor_polygons if name == "Floor" else polygons
                target_colors = floor_colors if name == "Floor" else colors_out
                target_polys.append([verts[j] for j in face])
                target_colors.append(
                    tuple(c * [0.65, 1, 0.8, 0.88, 0.9, 0.85][i] for c in base)
                )
        # All architecture is on/above Y=0 and views are from above. Draw floor
        # behind architecture explicitly: painter sorting a giant floor face by
        # its centroid would incorrectly hide low partitions in this diagram.
        ax.add_collection3d(
            Poly3DCollection(
                floor_polygons,
                facecolors=floor_colors,
                edgecolors="#5f6260",
                linewidths=0.2,
                zorder=0,
            )
        )
        ax.add_collection3d(
            Poly3DCollection(
                polygons,
                facecolors=colors_out,
                edgecolors="#5f6260",
                linewidths=0.2,
                zorder=1,
            )
        )
        ax.set(xlim=(-6.4, 6.4), ylim=(-4.6, 4.6), zlim=(-0.2, 3.3))
        ax.set_box_aspect((12.8, 9.2, 3.5))
        ax.view_init(elev=35.26438968, azim=az)
        ax.set_axis_off()
        fig.suptitle(
            "TASK 010 — OFFLINE geometry diagram, NOT Godot\nNo lighting simulation; existing GLB desk is not drawn in this box-only diagram",
            fontsize=12,
        )
        fig.savefig(out / filename, dpi=140, bbox_inches="tight")
        plt.close(fig)
    print("Wrote offline diagrams, NOT engine screenshots")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    data = check()
    if args.preview:
        previews(*data)
