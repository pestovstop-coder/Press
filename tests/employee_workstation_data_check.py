"""Static validation of the employee_workstation glTF 2.0 export (not Godot import)."""

import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
GLB = ROOT / "assets/models/furniture/desks/employee_workstation.glb"
SOURCE = ROOT / "blender/source/furniture/desks/employee_workstation.blend"
GDIGNORE = ROOT / "blender/.gdignore"
EXPECTED_MIN = (-0.6460371539, -0.0018851726, -0.7608243823)
EXPECTED_MAX = (0.8305609897, 1.4737218618, 0.5536620021)


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
    child_indices = root.get("children", [])
    check(len(child_indices) == 6, "root contains all six component nodes")
    mesh_nodes = [nodes[index] for index in child_indices]
    check(all("mesh" in node for node in mesh_nodes), "all six component nodes reference meshes")
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

    for node in mesh_nodes:
        check("matrix" not in node and "rotation" not in node and "scale" not in node,
              f"{node['name']} uses translation-only transform covered by this bounds check")

    lows = [math.inf, math.inf, math.inf]
    highs = [-math.inf, -math.inf, -math.inf]
    for node in mesh_nodes:
        translation = node.get("translation", (0.0, 0.0, 0.0))
        mesh = document["meshes"][node["mesh"]]
        for primitive in mesh["primitives"]:
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            for axis in range(3):
                lows[axis] = min(lows[axis], accessor["min"][axis] + translation[axis])
                highs[axis] = max(highs[axis], accessor["max"][axis] + translation[axis])
    for actual, expected in zip(lows, EXPECTED_MIN):
        check(math.isclose(actual, expected, abs_tol=1e-6), "aggregate GLB lower bound matches audited value")
    for actual, expected in zip(highs, EXPECTED_MAX):
        check(math.isclose(actual, expected, abs_tol=1e-6), "aggregate GLB upper bound matches audited value")
    dimensions = [highs[i] - lows[i] for i in range(3)]
    for actual, expected in zip(dimensions, (1.4765981436, 1.4756070344, 1.3144863844)):
        check(math.isclose(actual, expected, abs_tol=1e-6), "aggregate dimensions match audited value")
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
    check("assets/models/furniture/desks/employee_workstation.glb" in catalog,
          "asset catalog records the GLB path")
    check(not any("uri" in image for image in document["images"]), "no external image paths are required")
    print("Static GLB validation passed. This does not verify Godot import/runtime.")


if __name__ == "__main__":
    main()
