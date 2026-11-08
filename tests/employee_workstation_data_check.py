"""Static validation of the employee_workstation glTF 2.0 export (not Godot import)."""

import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
GLB = ROOT / "assets/models/furniture/desks/employee_workstation.glb"
SOURCE = ROOT / "blender/source/furniture/desks/employee_workstation.blend"
GDIGNORE = ROOT / "blender/.gdignore"
EXPECTED_MIN = (-0.6318554878, -0.0018851726, -0.7435315251)
EXPECTED_MAX = (0.8661690950, 1.4737218618, 0.6046987148)


def transform_point(node: dict, point: tuple[float, float, float]) -> tuple[float, float, float]:
    if "matrix" in node:
        matrix = node["matrix"]
        x, y, z = point
        return (
            matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12],
            matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13],
            matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14],
        )
    scale = node.get("scale", (1.0, 1.0, 1.0))
    x, y, z = (point[axis] * scale[axis] for axis in range(3))
    qx, qy, qz, qw = node.get("rotation", (0.0, 0.0, 0.0, 1.0))
    tx = 2.0 * (qy * z - qz * y)
    ty = 2.0 * (qz * x - qx * z)
    tz = 2.0 * (qx * y - qy * x)
    rotated = (
        x + qw * tx + qy * tz - qz * ty,
        y + qw * ty + qz * tx - qx * tz,
        z + qw * tz + qx * ty - qy * tx,
    )
    translation = node.get("translation", (0.0, 0.0, 0.0))
    return tuple(rotated[axis] + translation[axis] for axis in range(3))


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print("PASS:", message)


def main() -> None:
    raw = GLB.read_bytes()
    magic, version, declared_size = struct.unpack_from("<4sII", raw, 0)
    check(magic == b"glTF" and version == 2, "GLB has glTF 2.0 header")
    check(declared_size == len(raw), "GLB declared length matches file size")
    offset = 12
    document = None
    binary = None
    while offset < len(raw):
        length, chunk_type = struct.unpack_from("<II", raw, offset)
        data = raw[offset + 8 : offset + 8 + length]
        check(offset + 8 + length <= len(raw), "GLB chunk remains within file")
        if chunk_type == 0x4E4F534A:
            document = json.loads(data.decode("utf-8").rstrip("\x00 "))
        elif chunk_type == 0x004E4942:
            binary = data
        offset += 8 + length
    check(document is not None and binary is not None, "JSON and embedded BIN chunks exist")

    nodes = document["nodes"]
    root_index = document["scenes"][document["scene"]]["nodes"][0]
    root = nodes[root_index]
    check(root.get("name") == "employee_workstation", "scene root is named employee_workstation")
    check("mesh" not in root, "scene root is a transform-only group, not a furniture mesh")
    child_indices = root.get("children", [])
    check(len(child_indices) == 6, "root contains all six component nodes")
    mesh_nodes = [nodes[index] for index in child_indices]
    check(all("mesh" in node for node in mesh_nodes), "all six component nodes reference meshes")
    check(
        {node.get("name") for node in mesh_nodes}
        == {
            "Chair_Office_Base_A",
            "Chair_Office_Bottom",
            "Computer_Old",
            "Computer_Old_Keyboard",
            "Computer_old_mouse",
            "Office_Desk_1",
        },
        "full kit retains chair, desk, computer, keyboard, and mouse components",
    )
    check(len(document.get("meshes", [])) == 6, "six glTF mesh resources are retained separately")
    check(len(document.get("materials", [])) == 7, "seven material resources are present")
    primitive_materials = [
        primitive["material"]
        for mesh in document["meshes"]
        for primitive in mesh["primitives"]
    ]
    check(len(primitive_materials) == 7 and set(primitive_materials) == set(range(7)),
          "all seven material slots are assigned to primitives")
    check(len(document.get("images", [])) == 2, "two embedded images are present")

    # The bounds are relative to the named instance root, as in the placement
    # controller. Include node rotation/scale and transform all eight corners of
    # each accessor AABB (a conservative bound matching Godot's AABB operations).
    lows = [math.inf, math.inf, math.inf]
    highs = [-math.inf, -math.inf, -math.inf]
    for node in mesh_nodes:
        mesh = document["meshes"][node["mesh"]]
        for primitive in mesh["primitives"]:
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            for x in (accessor["min"][0], accessor["max"][0]):
                for y in (accessor["min"][1], accessor["max"][1]):
                    for z in (accessor["min"][2], accessor["max"][2]):
                        point = transform_point(node, (x, y, z))
                        for axis in range(3):
                            lows[axis] = min(lows[axis], point[axis])
                            highs[axis] = max(highs[axis], point[axis])
    for actual, expected in zip(lows, EXPECTED_MIN):
        check(math.isclose(actual, expected, abs_tol=1e-6),
              "aggregate root-relative GLB lower bound includes node transforms")
    for actual, expected in zip(highs, EXPECTED_MAX):
        check(math.isclose(actual, expected, abs_tol=1e-6),
              "aggregate root-relative GLB upper bound includes node transforms")
    dimensions = [highs[i] - lows[i] for i in range(3)]
    for actual, expected in zip(dimensions, (1.4980245829, 1.4756070344, 1.3482302399)):
        check(math.isclose(actual, expected, abs_tol=1e-6),
              "aggregate transformed dimensions match audited full-kit bounds")
    check(dimensions[0] <= 1.6 and dimensions[2] <= 1.4,
          "full workstation kit fits the existing 1.6m by 1.4m workplace envelope")
    check(lows[1] > -0.002 and lows[1] < 0.0, "geometry base is within 2 mm below root origin")

    buffers = document.get("buffers", [])
    check(len(buffers) == 1 and "uri" not in buffers[0], "GLB binary buffer is embedded")
    for image in document["images"]:
        view = document["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        payload = binary[start : start + view["byteLength"]]
        check(image.get("mimeType") == "image/png" and payload.startswith(b"\x89PNG\r\n\x1a\n"),
              f"embedded image {image.get('name')} is a PNG payload")
    check(SOURCE.is_file(), "matching Blender source file exists")
    check(GDIGNORE.is_file(), ".gdignore is present under blender/")
    controller = (ROOT / "scripts/placement_controller.gd").read_text()
    catalog = (ROOT / "docs/ASSET_CATALOG.md").read_text()
    check(
        '"res://assets/models/furniture/desks/employee_workstation.glb"' in controller,
        "placement controller references the in-project GLB resource",
    )
    check(
        '"employee_workstation"' in controller and "Рабочее место сотрудника" in controller,
        "placement controller exposes the requested asset ID and display name",
    )
    check("const CELL_SIZE: float = 0.25" in controller,
          "placement uses a single quarter-meter cell size")
    check('"employee_workstation": Vector2i(7, 6)' in controller,
          "whole workstation kit reserves the rounded 1.6m by 1.4m envelope")
    check('"office_desk": Vector2i(8, 4)' in controller,
          "legacy desk uses an eight-by-four-cell footprint to contain its bounds")
    check("assets/models/furniture/desks/employee_workstation.glb" in catalog,
          "asset catalog records the GLB path")
    check(not any("uri" in image for image in document["images"]), "no external image paths are required")
    print("Static GLB validation passed. This does not verify Godot import/runtime.")


if __name__ == "__main__":
    main()
