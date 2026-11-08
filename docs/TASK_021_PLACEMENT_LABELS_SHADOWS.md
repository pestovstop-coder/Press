# TASK 021 — placement, room labels and shadow settings

## Placement diagnosis and change

The source-level cause of the generic `OBSTACLE_COLLISION` was the editor grid itself. `_ready()` called `_build_grid()` before collecting meshes recursively from `TestRoom`; the grid is a `MeshInstance3D` child of `Floor`, so it entered `room_occluders`. Its line-mesh AABB spans the floor and sits just above it. Candidate validation correctly skipped the floor node, but not this editor-only overlay; because the grid has no `cutaway_side` metadata, its intersection was reported as `OBSTACLE_COLLISION`. This affected every asset and made the nearest-valid-footprint search find no cells.

The grid and footprint marker are now members of the `placement_visual` group, and obstacle collection excludes that group. The floor remains in `room_occluders` for picking occlusion and is still explicitly skipped by placement collision validation. Wall AABBs, furniture footprints, floor bounds, orientation and generic obstacle checks remain enabled. A regression scenario in `tests/placement_smoke.gd` asserts that the grid is excluded, a real generic obstacle still reports `OBSTACLE_COLLISION`, and removing that obstacle restores the same target.

This diagnosis is established from the code path and scene hierarchy. Godot runtime confirmation is still required to verify input, imported-model transforms, placement and appearance in the actual editor.

## Room wayfinding

The main scene now creates editable `Label3D` plaques for the documented plan IDs `office_101`, `office_102` and `corridor_main`. The small low-profile plaques use a dark backing, light type, a blue accent and a larger room name/number hierarchy. Cabinet markers sit on the corridor side of their documented door thresholds; the corridor marker sits in the shared corridor. Their scene nodes are outside `TestRoom`, so they are not placement obstacles. Their yaw follows the camera while each plaque stays on the floor. This is a simple presentation layer, not room-zone gameplay logic. Legibility at zoom/pitch extremes and appearance alongside wall cutaway still need visual acceptance in Godot.

## Shadows

The main `Sun` now uses `shadow_bias = 1.0` and `shadow_normal_bias = 2.0`, as reported by the user as the minimum combination that removes the main diagonal pattern in their Godot test. That user-run result was not repeated in this environment. The reported residual stair-stepping and small floor/wall-join artifacts remain open.

Directional map size 4096, desktop filter quality 4 (Soft High), orthogonal mode 0, max distance 45 and blur 1.5 are unchanged. The six Omni and two Spot fill lights remain shadowless; only Sun casts shadows. No GDScript overrides Sun bias. Static interpretation of the residual stair-step:

| Factor | What source inspection establishes | Cost / limit |
|---|---|---|
| Shadow-map resolution | Desktop uses 4096 px; mobile override uses 2048 px. Projected texel density can be insufficient at some camera/map coverage. | 8192 would use four times as many texels as 4096², with greater memory and shadow rendering cost; no performance evidence justifies it yet. |
| Filter | Desktop uses Soft High quality 4; mobile uses Soft Low quality 2; Sun blur remains 1.5. | Higher filtering smooths edges but increases sampling cost and can soften contact shadows; it cannot create missing map detail. |
| Shadow mode / distance | Sun uses orthogonal mode 0 with max distance 45. | The remaining edge pattern is not evidence of cascade seams; `max_distance` may not affect orthogonal coverage. Verify behavior in a runtime A/B before tuning. |
| Renderer | `GL Compatibility` is configured. | Its available shadow filtering differs from Forward+/Mobile paths; no source-only check can establish the visible quality limit on the user's GPU. |
| Bias | User reports 1.0 / 2.0 removes the main diagonal pattern; these are set in the scene. | Bias is not an antialiasing control. Raising it further can detach shadows from casters. |

Without controlled same-camera captures, the remaining stair-step cannot be attributed conclusively to map resolution, filtering, coverage or GL Compatibility. Keep current settings until one-parameter A/B captures and frame-time measurements are available.

## Checks and limitations

- `tests/layout_blockout_check.py` checks the authored layout and resource data; it is static, not a renderer test.
- `tests/task021_static_check.py` checks source invariants for the editor-overlay exclusion, label data, and Sun bias values; it does not execute GDScript.
- `tests/placement_smoke.gd` contains runtime regression checks for the grid false-obstacle cause, real generic obstacles, cell placement, furniture, movement and rotation. It could not be run here because `godot`/`godot4` is unavailable.
- No Godot screenshots were captured. The new labels and the reported shadow-bias result have not been visually verified by this environment.

## Manual Godot acceptance steps

1. Open `scenes/main.tscn` in Godot 4.7.2 with GL Compatibility. Use the normal isometric view and capture a baseline screenshot.
2. Press `B`; select the procedural block. Confirm the preview begins green, follows the cursor in the room, and reports `VALID`. Place in an open central cell and in an open corner.
3. Place a block or desk adjacent to a wall without crossing it; then deliberately overlap a wall, floor boundary and another placed item. Check that only the valid targets place and that diagnostics distinguish `WALL_COLLISION`, `OUT_OF_BOUNDS` and `FURNITURE_COLLISION`.
4. Place several items in adjacent free footprints. Rotate the old desk and workstation by 90 degrees; check that the model, footprint and front marker rotate together. Move a placed item to a free cell, then try an occupied cell and cancel.
5. Repeat with the old desk and complete employee workstation. Confirm the workstation chair and desk fit the reserved footprint, and confirm catalog clicks do not place at the UI position.
6. Inspect the three room plaques at zoom 6, 16 and 26; rotate the camera through its allowed yaw and pitch range. Check that each label stays associated with its room, remains readable, does not collide visually with furniture/doors, and is naturally occluded by walls where appropriate.
7. Compare the same camera pose with Sun shadows off and on. With shadows on, verify Bias 1.0 / Normal Bias 2.0, inspect contact detachment, wall/floor joins and edge stair-stepping. Change only one shadow setting per capture; record screenshots and frame-time before considering map/filter changes.
