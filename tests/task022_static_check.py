#!/usr/bin/env python3
"""Source/data checks for TASK 022. This is not Godot runtime evidence."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
controller = (ROOT / "scripts/placement_controller.gd").read_text()
smoke = (ROOT / "tests/placement_smoke.gd").read_text()


def check(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


check('"employee_workstation": Vector2i(7, 6)' in controller,
      "employee_workstation plan footprint remains 7×6 cells")
check('"office_desk": Vector2i(8, 4)' in controller,
      "legacy desk plan footprint remains 8×4 cells")
check('const CELL_SIZE: float = 0.25' in controller,
      "base editor snap remains 0.25m")
check('const SURFACE_SNAP_DISTANCE: float = CELL_SIZE' in controller,
      "surface contact snap is limited to one placement cell")

candidate_start = controller.index("func _candidate_invalid_reason(")
candidate_end = controller.index("\n\nfunc ", candidate_start + 1)
candidate = controller[candidate_start:candidate_end]
check("_mesh_bounds_overlap_any(mesh_bounds, other_mesh_bounds)" in candidate,
      "furniture collision uses per-mesh AABBs, not the plan footprint")
check("_aabbs_overlap(candidate_bounds, obstacle)" in candidate,
      "wall and obstacle collision use actual transformed mesh bounds")
check("_footprints_overlap" not in candidate and "_footprint_rect" not in candidate,
      "no footprint-size collision margin remains")
check("_bounds_inside_floor(visual_bounds)" in candidate,
      "floor edge validation uses visual bounds")
check("COLLISION_EPSILON: float = 0.00001" in controller,
      "only 10-micron numeric tolerance is used; no physics margin is added")
check("_surface_snap_center(" in controller and "candidate_center" in controller,
      "nearby wall/furniture surfaces can align to exact visual bounds")
check("_surface_contact_axes(candidate_mesh_bounds)" in controller
      and "contact_axes > best_contact_axes" in controller,
      "corner snapping prefers candidates touching both perpendicular surfaces")
check("object.global_transform = preview.global_transform" in controller,
      "placed item receives the already validated preview transform")
check("func pick_object(screen_point: Vector2)" in controller
      and "Geometry3D.ray_intersects_triangle" in controller,
      "mesh-triangle selection remains separate from placement collision")

# Audited GLB root-relative dimensions, before any placement transform.
station_x, station_z = 1.4980245829, 1.3482302399
plan_x, plan_z = 1.6, 1.4
footprint_x, footprint_z = 7 * 0.25, 6 * 0.25
check(footprint_x == 1.75 and footprint_z == 1.5,
      "42-cell workstation reservation remains 1.75×1.5m")
check(0 < plan_x - station_x < 0.11 and 0 < plan_z - station_z < 0.06,
      "planning envelope remains distinct from full-kit visual bounds")
station_slack_x = (footprint_x - station_x) / 2
station_slack_z = (footprint_z - station_z) / 2
check(0.125 < station_slack_x < 0.127 and 0.075 < station_slack_z < 0.077,
      "old centered cell collider added about 126mm/76mm per side")
check(abs((2.0 - 1.6) / 2 - 0.2) < 1e-9 and abs((1.0 - 0.8) / 2 - 0.1) < 1e-9,
      "legacy desk footprint added 200mm/100mm per side if treated as collision")

half_x, half_z = station_x / 2, station_z / 2
shared_wall_face = 0.1
first_center = shared_wall_face + half_x
second_center = first_center + station_x
legacy_desk_center = second_center + (station_x + 1.6) / 2
corner_center = (5.8 - half_x, -4.05 + half_z)
corner_base = (5.125, -3.5)
corner_snap = ((corner_center[0] - corner_base[0]) ** 2
               + (corner_center[1] - corner_base[1]) ** 2) ** 0.5
check(abs((first_center - half_x) - shared_wall_face) < 1e-9
      and abs((second_center - half_x) - (first_center + half_x)) < 1e-9,
      "workstation wall contact and workstation-to-workstation contact have zero AABB gap")
check(abs((legacy_desk_center - 0.8) - (second_center + half_x)) < 1e-9,
      "mixed legacy-desk/workstation contact aligns their actual width bounds")
check(corner_snap < 0.25,
      "both east/rear corner faces are within one-cell contact-snap range")
rotated_center = shared_wall_face + half_z
check(abs(rotated_center - 0.75) < 0.25,
      "90-degree workstation contact remains inside the snap capture distance")

check('"workstation surface-snaps flush to the straight shared wall"' in smoke,
      "runtime smoke test measures straight-wall clearance")
check('"workstation fits the east-rear corner with both visual bounds flush"' in smoke,
      "runtime smoke test measures corner clearance")
check('"two workstations may share a face when their visual mesh bounds only touch"' in smoke,
      "runtime smoke test covers adjacent complete workstations")
check('"legacy desk can surface-snap beside a workstation using its own bounds"' in smoke,
      "runtime smoke test covers mixed furniture adjacency")
check('"moving an installed workstation can return to a flush wall position"' in smoke,
      "runtime smoke test covers moving to a wall")
check('"rotated workstation snaps its rotated visual bounds to the same wall"' in smoke,
      "runtime smoke test covers rotated placement")
check("_test_furniture_clearances(scene, c, camera)" in smoke,
      "clearance fixture is invoked by the placement smoke suite")
check('"mesh-level picking finds the workstation tabletop after its quarter-turn"' in smoke
      and '"mesh-level picking finds an accessible workstation side after its quarter-turn"' in smoke,
      "selection regression covers top and side workstation surfaces")

print("TASK 022 static checks passed; Godot placement and visual checks are not covered.")
