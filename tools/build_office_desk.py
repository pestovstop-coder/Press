"""Offline authoring tool for office_desk, not a Godot import/runtime script.

Run with Python 3 + trimesh, numpy, scipy. --preview additionally needs matplotlib.
Coordinates are glTF/Godot: metres, +Y up, +Z front (Blender -Y equivalent).
"""
from pathlib import Path
import argparse
import itertools
import json

import numpy as np
import trimesh
from trimesh.visual.material import PBRMaterial

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/models/furniture/desks/office_desk.glb"
EVIDENCE = ROOT / "evidence/task004"


def chamfered_box(name, size, center, bevel, material):
    """Convex hull of 24 explicit vertices: planar faces, edge/corner chamfers."""
    half = np.array(size) / 2
    points = []
    for axis in range(3):
        for signs in itertools.product((-1, 1), repeat=3):
            p = (half - bevel) * signs
            p[axis] = half[axis] * signs[axis]
            points.append(p)
    mesh = trimesh.convex.convex_hull(np.array(points))
    mesh.apply_translation(center)
    assert mesh.is_watertight and mesh.is_winding_consistent and mesh.volume > 0
    mesh.visual = trimesh.visual.TextureVisuals(material=material)
    mesh.metadata["name"] = name
    return mesh


def build():
    wood = PBRMaterial(name="light_natural_wood", baseColorFactor=[0.72, 0.54, 0.33, 1],
                       metallicFactor=0.0, roughnessFactor=0.72, doubleSided=False)
    metal = PBRMaterial(name="graphite_metal", baseColorFactor=[0.065, 0.078, 0.09, 1],
                        metallicFactor=0.75, roughnessFactor=0.48, doubleSided=False)
    scene = trimesh.Scene(base_frame="office_desk")
    parts = [("office_desk_top", (1.6, 0.04, 0.8), (0, 0.73, 0), 0.005, wood)]
    for x, side in [(-0.69, "left"), (0.69, "right")]:
        for z, end in [(-0.29, "back"), (0.29, "front")]:
            parts.append((f"office_desk_leg_{side}_{end}", (0.045, 0.71, 0.045),
                          (x, 0.355, z), 0.0015, metal))
    for z, end in [(-0.29, "back"), (0.29, "front")]:
        parts.append((f"office_desk_rail_{end}", (1.425, 0.045, 0.035),
                      (0, 0.6775, z), 0.0015, metal))
    for x, side in [(-0.69, "left"), (0.69, "right")]:
        parts.append((f"office_desk_rail_{side}", (0.035, 0.045, 0.625),
                      (x, 0.6775, 0), 0.0015, metal))
    meshes = []
    for name, size, center, bevel, material in parts:
        mesh = chamfered_box(name, size, center, bevel, material)
        meshes.append(mesh)
        # Split vertices to preserve crisp planar normals on bevels in glTF.
        export_mesh = mesh.copy()
        export_mesh.unmerge_vertices()
        _ = export_mesh.vertex_normals
        scene.add_geometry(export_mesh, node_name=name, geom_name=name,
                           parent_node_name="office_desk")
    bounds = np.array([np.min([m.bounds[0] for m in meshes], axis=0),
                       np.max([m.bounds[1] for m in meshes], axis=0)])
    assert np.allclose(bounds, [[-0.8, 0, -0.4], [0.8, 0.75, 0.4]])
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    def buffer_targets(tree):
        children = tree["scenes"][0]["nodes"]
        root_index = len(tree["nodes"])
        tree["nodes"].append({"name": "office_desk", "children": children})
        tree["scenes"][0]["nodes"] = [root_index]
        for mesh in tree["meshes"]:
            for primitive in mesh["primitives"]:
                for accessor in primitive["attributes"].values():
                    view = tree["accessors"][accessor]["bufferView"]
                    tree["bufferViews"][view]["target"] = 34962
                view = tree["accessors"][primitive["indices"]]["bufferView"]
                tree["bufferViews"][view]["target"] = 34963
    OUTPUT.write_bytes(trimesh.exchange.gltf.export_glb(
        scene, include_normals=True, tree_postprocessor=buffer_targets))
    loaded = trimesh.load(OUTPUT, force="scene")
    assert np.allclose(loaded.bounds, bounds, atol=1e-6)
    assert len(loaded.geometry) == 9
    report = {
        "tool": f"Python / trimesh {trimesh.__version__}",
        "method": "Explicit chamfered polygon meshes; no Godot primitives",
        "parts": len(meshes), "triangles": sum(len(m.faces) for m in meshes),
        "bounds_xyz_m": bounds.tolist(), "width_depth_height_m": [1.6, 0.8, 0.75],
        "origin": [0, 0, 0], "up": "+Y", "front": "+Z",
        "closed_parts_outward_winding_positive_volume": True,
        "glb_roundtrip_bounds_and_part_count": "PASS",
        "external_textures_or_buffers": "none", "godot_runtime": "NOT RUN: Godot unavailable",
        "file_bytes": OUTPUT.stat().st_size,
    }
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "geometry_checks.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return meshes


def preview(meshes):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection
    for name, azimuth, elevation in [("front", -60, 24), ("back", 120, 24),
                                     ("left", -150, 18), ("underside", -60, -20)]:
        fig = plt.figure(figsize=(10, 7), facecolor="#e8eaec")
        ax = fig.add_subplot(projection="3d", facecolor="#e8eaec")
        all_triangles, all_colors = [], []
        for i, mesh in enumerate(meshes):
            # Matplotlib Z-up for viewing only, geometry stays glTF Y-up.
            vertices = mesh.vertices[:, [0, 2, 1]]
            triangles = vertices[mesh.faces]
            normals = mesh.face_normals[:, [0, 2, 1]]
            light = np.array([-0.4, -0.5, 0.76])
            shade = 0.65 + 0.35 * np.clip(normals @ light, 0, 1)
            base = np.array([0.78, 0.64, 0.45] if i == 0 else [0.16, 0.18, 0.20])
            colors = np.clip(shade[:, None] * base, 0, 1)
            az, el = np.radians([azimuth, elevation])
            toward_eye = np.array([np.cos(el)*np.cos(az), np.cos(el)*np.sin(az), np.sin(el)])
            visible = normals @ toward_eye > 0
            all_triangles.extend(triangles[visible])
            all_colors.extend(colors[visible])
        ax.add_collection3d(Poly3DCollection(all_triangles, facecolors=all_colors,
                                            edgecolors="none", linewidths=0,
                                            antialiased=False))
        ax.set(xlim=(-0.95, 0.95), ylim=(-0.65, 0.65), zlim=(-0.05, 0.95))
        ax.set_box_aspect((1.9, 1.3, 1.0))
        ax.view_init(elev=elevation, azim=azimuth)
        ax.set_axis_off()
        fig.suptitle("office_desk — offline mesh preview (not Godot)", fontsize=13)
        fig.savefig(EVIDENCE / f"mesh_{name}.png", dpi=130, bbox_inches="tight")
        plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    meshes = build()
    if args.preview:
        preview(meshes)
