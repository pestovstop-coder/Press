extends SceneTree
## godot --headless --path . --script res://tests/placement_smoke.gd
## Real scene and imported GLB. Handler tests, not a visual/GUI acceptance test.
const Placement = preload("res://scripts/placement_controller.gd")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		push_error("FAIL: " + description)
		failures += 1


func key(controller: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	controller._unhandled_input(event)


func click(controller: Node, position: Vector2, ctrl: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	event.ctrl_pressed = ctrl
	controller._unhandled_input(event)


func check_idle(c: Node, description: String) -> void:
	check(
		(
			c.state == Placement.EditorState.IDLE
			and c.preview == null
			and c.editing == null
			and c.selected_asset == ""
			and not c.valid_target
			and c.ghost_records.is_empty()
		),
		description
	)


func materials_snapshot(c: Node, object: Node3D) -> Array:
	var result: Array = []
	for mesh: MeshInstance3D in c._meshes(object):
		var surfaces: Array = []
		for index in range(mesh.mesh.get_surface_count()):
			surfaces.append(mesh.get_surface_override_material(index))
		result.append([mesh.material_override, surfaces, mesh.cast_shadow])
	return result


func _test_cell_helpers(c: Node) -> void:
	check(is_equal_approx(Placement.CELL_SIZE, 0.25), "placement has one 0.25m cell size")
	check(
		(
			c._footprint_cells_for_asset("block") == Vector2i(4, 4)
			and c._footprint_cells_for_asset("office_desk") == Vector2i(8, 4)
			and c._footprint_cells_for_asset("employee_workstation") == Vector2i(7, 6)
		),
		"asset footprints use integer cells, including the full workstation kit"
	)
	check(
		c._footprint_cells_for_asset("office_desk", 1) == Vector2i(4, 8),
		"quarter-turn swaps a rectangular footprint"
	)
	check(
		(
			c._round_cell_index(2.49) == 2
			and c._round_cell_index(2.5) == 3
			and c._round_cell_index(-2.49) == -2
			and c._round_cell_index(-2.5) == -2
			and c._round_cell_index(-2.51) == -3
		),
		"negative snapping is deterministic, including exact half-cell ties"
	)
	check(
		c.snapped_floor_point(Vector3(-0.125, 0, -0.125)).is_equal_approx(
			Vector3(0, c.floor_top, 0)
		),
		"negative half-cell coordinates snap deterministically toward positive values"
	)
	check(
		(
			c._footprints_overlap(Vector2i(0, 0), Vector2i(2, 2), Vector2i(1, 1), Vector2i(2, 2))
			and not c._footprints_overlap(
				Vector2i(0, 0), Vector2i(2, 2), Vector2i(2, 0), Vector2i(2, 2)
			)
		),
		"integer-cell overlap rejects shared cells but allows edge-adjacent items"
	)
	check(
		c._footprint_rect(Vector2i(0, 0), Vector2i(2, 2)).is_equal_approx(
			Rect2(Vector2.ZERO, Vector2(0.5, 0.5))
		),
		"cell rectangles use quarter-meter boundaries from the floor origin"
	)
	var existing_desk: Node3D = c.editable[0]
	var desk_bounds: AABB = c._object_bounds_in_floor(
		existing_desk, existing_desk.get_meta("bounds")
	)
	var desk_origin: Vector2i = existing_desk.get_meta("footprint_origin_cells")
	var desk_cells: Vector2i = existing_desk.get_meta("footprint_cells")
	var desk_rect: Rect2 = c._footprint_rect(desk_origin, desk_cells)
	check(
		(
			desk_bounds.position.x >= desk_rect.position.x
			and desk_bounds.end.x <= desk_rect.end.x
			and desk_bounds.position.z >= desk_rect.position.y
			and desk_bounds.end.z <= desk_rect.end.y
		),
		"registered legacy desk cells contain its full visual bounds"
	)


func _test_cell_placement(c: Node, camera: Camera3D) -> void:
	c.set_active(true)
	c.select_asset("block")
	check(
		(
			c.grid.is_in_group(Placement.PLACEMENT_VISUAL_GROUP)
			and not c.room_occluders.has(c.grid)
			and c.room_occluders.has(c.floor_mesh)
		),
		"editor grid is not an obstacle, while floor remains available for ray occlusion"
	)
	check(
		(
			c.valid_target
			and c.placement_diagnostic == "VALID"
			and c.front_marker.visible
			and c.front_marker.get_meta("allowed")
		),
		"block selection starts with a free valid footprint and matching green marker"
	)
	var obstacle := MeshInstance3D.new()
	obstacle.name = "SmokeTestObstacle"
	var obstacle_mesh := BoxMesh.new()
	obstacle_mesh.size = Vector3(0.4, 1.0, 0.4)
	obstacle.mesh = obstacle_mesh
	c.add_child(obstacle)
	obstacle.global_position = Vector3(2.25, 0.5, 2.75)
	c.room_occluders.append(obstacle)
	var obstacle_target: Vector2 = camera.unproject_position(Vector3(2.24, 0, 2.76))
	var before: int = c.placed.get_child_count()
	c.click_at(obstacle_target)
	check(
		c.placed.get_child_count() == before and c.placement_diagnostic == "OBSTACLE_COLLISION",
		"real non-wall obstacle blocks confirmation with a specific reason"
	)
	c.room_occluders.erase(obstacle)
	obstacle.queue_free()
	c.click_at(obstacle_target)
	check(
		c.placed.get_child_count() == before + 1,
		"removing the diagnostic obstacle allows the same free placement target"
	)
	var temporary_placement: Node3D = c.placed.get_child(before)
	c.editable.erase(temporary_placement)
	c.placed.remove_child(temporary_placement)
	temporary_placement.free()
	c.select_asset("block")
	before = c.placed.get_child_count()
	var checks: Array = [
		[Vector3(2.24, 0, 2.76), true, "VALID", "free cells inside the room are allowed"],
		[
			Vector3(-3, 0, 1.75),
			true,
			"VALID",
			"an overhead doorway header does not block shorter furniture",
		],
		[
			Vector3(-4.75, 0, -3.55),
			false,
			"FURNITURE_COLLISION",
			"furniture footprint overlap is rejected",
		],
		[Vector3(-5.5, 0, -1.2), false, "WALL_COLLISION", "authored wall overlap is rejected"],
		[
			Vector3(5.9, 0, 3.9),
			false,
			"OUT_OF_BOUNDS",
			"cells extending past the floor boundary are rejected",
		],
	]
	for entry in checks:
		var point: Vector2 = camera.unproject_position(entry[0])
		c._update_preview(point)
		check(c.valid_target == entry[1] and c.preview.visible, entry[3])
		check(c.placement_diagnostic == entry[2], "placement reports " + entry[2])
		check(
			(
				c.front_marker.get_meta("footprint_origin_cells") == c.current_footprint_origin
				and c.front_marker.get_meta("footprint_cells") == c.current_footprint_size
				and c.front_marker.get_meta("allowed") == entry[1]
			),
			"preview marker matches the tested footprint and validity"
		)
		var footprint_rect: Rect2 = c._footprint_rect(
			c.current_footprint_origin, c.current_footprint_size
		)
		var vertices: PackedVector3Array = c.front_marker.mesh.surface_get_arrays(0)[
			Mesh.ARRAY_VERTEX
		]
		check(
			(
				vertices[0].x == footprint_rect.position.x
				and vertices[0].z == footprint_rect.position.y
				and vertices[1].x == footprint_rect.position.x
				and vertices[1].z == footprint_rect.end.y
			),
			"marker border coordinates equal the collision/floor-test rectangle"
		)
		if not entry[1]:
			click(c, point)
			check(c.placed.get_child_count() == before, "invalid cell target cannot be confirmed")
	key(c, KEY_ESCAPE)
	check_idle(c, "cell placement checks leave no preview behind")
	c.set_active(false)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var c: Node = scene.get_node("PlacementController")
	var rig: Node3D = scene.get_node("CameraRig")
	var camera: Camera3D = rig.get_node("Camera3D")
	var original_desk: Node3D = scene.get_node("TestRoom/OfficeDesk")
	_test_layout(c, scene)
	_test_room_labels(scene, rig, camera, c)
	_test_cell_helpers(c)
	await _test_cell_placement(c, camera)
	var camera_before: Transform3D = rig.global_transform
	check(
		c.floor_bounds.size.is_equal_approx(Vector3(12, 0.2, 8.5)),
		"grid derives new continuous floor bounds"
	)
	check(is_equal_approx(camera.size, 16.0), "new layout uses wider initial camera size")
	var initial: Transform3D = original_desk.global_transform
	var initial_materials: Array = materials_snapshot(c, original_desk)
	var empty: Vector2 = camera.unproject_position(Vector3(3, 0, 2))
	check_idle(c, "closed editor has no selection or ghost")
	check(not c.active and not c.grid.visible and not c.panel.visible, "normal mode hides UI/grid")
	c.select_asset("block")
	check_idle(c, "panel API cannot start placement outside build mode")
	key(c, KEY_B)
	check(c.active and c.panel.visible and c.grid.visible, "B opens editor/grid")
	check_idle(c, "B enters idle, no automatic cube")
	key(c, KEY_R)
	c._process(0.016)
	click(c, empty)
	check_idle(c, "R, process and empty click are safe without preview")
	check(c.placed.get_child_count() == 0, "idle empty click creates nothing")
	var column: Node = c.panel.get_child(0)
	column.get_child(1).emit_signal("pressed")
	check(
		(
			c.state == Placement.EditorState.PLACING
			and c.selected_asset == "block"
			and c.preview != null
		),
		"block button starts preview only"
	)
	check(c.placed.get_child_count() == 0, "button does not create placed furniture")
	var block_screen: Vector2 = camera.unproject_position(Vector3(2.24, 0, 2.76))
	c._update_preview(block_screen)
	check(
		(
			c.valid_target
			and c.preview.visible
			and c.preview.global_position.is_equal_approx(Vector3(2.25, 0, 2.75))
		),
		"block snaps to floor"
	)
	var old_preview: Node3D = c.preview
	click(c, block_screen)
	check(c.placed.get_child_count() == 1, "LMB places one block")
	check_idle(c, "block placement returns idle with no preview")
	check(
		not old_preview.visible and old_preview.is_queued_for_deletion(),
		"old ghost hidden and freed"
	)
	var block: Node3D = c.placed.get_child(0)
	click(c, empty)
	check(c.placed.get_child_count() == 1, "additional empty click does not place second block")
	column.get_child(1).emit_signal("pressed")
	click(c, camera.unproject_position(Vector3(-3, 0, 2)))
	check(c.placed.get_child_count() == 2, "second block requires explicit button press")
	check_idle(c, "second block also leaves idle")
	column.get_child(2).emit_signal("pressed")
	check(
		c.state == Placement.EditorState.PLACING and c.selected_asset == "office_desk",
		"desk button starts new-object operation"
	)
	check(
		(
			c.valid_target
			and c.placement_diagnostic == "VALID"
			and c.front_marker.visible
			and c.front_marker.get_meta("allowed")
		),
		"desk selection starts with a free footprint and matching green marker"
	)
	var bounds: AABB = c.preview.get_meta("bounds")
	check(
		bounds.size.is_equal_approx(Vector3(1.6, 0.75, 0.8)), "desk bounds from imported geometry"
	)
	check(c.ghost_records.size() == 9, "desk preview ghosts all meshes")
	key(c, KEY_R)
	var desk_screen: Vector2 = camera.unproject_position(Vector3(-4.5, 0, -1.5))
	c._update_preview(desk_screen)
	check(
		(
			c.front_marker.visible
			and c.current_footprint_size == Vector2i(4, 8)
			and c.front_marker.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 76
		),
		"rotated desk marker shows its 4×8 quarter-meter cells and front arrows"
	)
	click(c, desk_screen)
	check(c.placed.get_child_count() == 3, "desk placed once")
	var desk: Node3D = c.placed.get_child(2)
	check(
		is_zero_approx(desk.position.y) and is_equal_approx(desk.rotation.y, PI / 2),
		"new desk retains rotation and rests on floor"
	)
	check_idle(c, "desk placement returns idle")
	click(c, empty)
	check(c.placed.get_child_count() == 3, "desk is not repeatedly created")
	# Start moves by actual ray picking, both existing and newly placed furniture.
	var desk_pick: Vector2 = camera.unproject_position(desk.to_global(Vector3(0, 0.75, 0)))
	click(c, desk_pick)
	check(
		c.state == Placement.EditorState.MOVING and c.editing == desk,
		"click on placed desk starts move"
	)
	key(c, KEY_ESCAPE)
	check_idle(c, "cancel new desk move returns idle")
	var pick_screen: Vector2 = camera.unproject_position(
		original_desk.to_global(Vector3(0, 0.75, 0))
	)
	check(c.pick_object(pick_screen) == original_desk, "ray picks original room desk")
	click(c, pick_screen)
	check(
		c.state == Placement.EditorState.MOVING and c.preview == original_desk,
		"idle click starts moving original instance"
	)
	key(c, KEY_R)
	var destination: Vector2 = camera.unproject_position(Vector3(1.26, 0, -1.26))
	c._update_preview(destination)
	var moved_transform: Transform3D = (
		c.floor_mesh.global_transform
		* c._preview_transform_for_footprint(
			original_desk.get_meta("bounds"),
			c.current_footprint_origin,
			c.current_footprint_size,
			c.quarter_turns
		)
	)
	check(
		original_desk.global_transform.is_equal_approx(moved_transform),
		"move snaps the complete rotated footprint to quarter-meter cells"
	)
	key(c, KEY_ESCAPE)
	check_idle(c, "Escape after move returns idle, not new-object preview")
	check(
		(
			c.active
			and original_desk.visible
			and original_desk.global_transform.is_equal_approx(initial)
		),
		"Escape restores original transform and stays in build mode"
	)
	check(
		materials_snapshot(c, original_desk) == initial_materials,
		"Escape restores exact materials/shadows"
	)
	click(c, pick_screen)
	key(c, KEY_R)
	c._update_preview(destination)
	click(c, destination)
	check_idle(c, "move confirmation returns idle")
	check(
		original_desk.visible and original_desk.global_transform.is_equal_approx(moved_transform),
		"confirmed desk retains its cell-aligned destination transform"
	)
	check(
		materials_snapshot(c, original_desk) == initial_materials,
		"commit restores materials/shadows"
	)
	click(c, empty)
	check(
		c.placed.get_child_count() == 3 and c.editable.size() == 4,
		"move and subsequent click do not duplicate furniture"
	)
	# Placement cancellation, switching operations, invalid targets, and mode exit.
	c.select_asset("block")
	key(c, KEY_ESCAPE)
	check_idle(c, "Escape cancels placement")
	check(c.active and c.panel.visible and c.grid.visible, "cancel placement keeps build mode open")
	c.begin_move(block)
	var block_initial: Transform3D = block.global_transform
	c._update_preview(destination)
	c.select_asset("office_desk")
	check(
		block.global_transform.is_equal_approx(block_initial) and block.visible,
		"panel selection rolls back pending move"
	)
	check(
		c.state == Placement.EditorState.PLACING and c.selected_asset == "office_desk",
		"panel exclusively starts a new-object operation"
	)
	var count: int = c.placed.get_child_count()
	click(c, c.panel.position + Vector2(5, 5))
	check(c.placed.get_child_count() == count, "panel click never confirms")
	click(c, camera.unproject_position(Vector3(20, 0, 20)))
	check(
		c.state == Placement.EditorState.PLACING and not c.valid_target,
		"outside floor does not confirm installation"
	)
	key(c, KEY_B)
	check_idle(c, "B cancels placement and exits")
	check(not c.active and not c.grid.visible and not c.panel.visible, "exit hides grid/panel")
	key(c, KEY_B)
	check_idle(c, "re-enter has no previous selection")
	c.begin_move(block)
	c._update_preview(camera.unproject_position(Vector3(20, 0, 20)))
	key(c, KEY_B)
	check(
		block.visible and block.global_transform.is_equal_approx(block_initial),
		"exit restores even a hidden invalid move"
	)
	check_idle(c, "exit from move leaves no ghost")
	key(c, KEY_B)
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	Input.parse_input_event(middle)
	click(c, camera.unproject_position(original_desk.to_global(Vector3(0, 0.75, 0))))
	check_idle(c, "MMB blocks picking in idle")
	c.select_asset("block")
	click(c, empty)
	check(
		c.placed.get_child_count() == count and c.state == Placement.EditorState.PLACING,
		"MMB blocks confirmation during placement"
	)
	middle.pressed = false
	Input.parse_input_event(middle)
	key(c, KEY_ESCAPE)
	check_idle(c, "cancel after MMB returns idle")
	key(c, KEY_ESCAPE)
	check(
		not c.active and rig.global_transform.is_equal_approx(camera_before),
		"idle Escape exits; editing has not moved camera"
	)
	await _test_task008(c, original_desk, camera)
	await _test_employee_workstation(c, camera)
	print("Placement smoke test failures: ", failures)
	quit(0 if failures == 0 else 1)


func gui_click(button: Button, local_point: Vector2) -> void:
	# Actual Viewport GUI routing, not signal emission or manual rectangle dispatch.
	var point: Vector2 = button.get_global_transform_with_canvas() * local_point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)


func _test_task008(c: Node, desk: Node3D, camera: Camera3D) -> void:
	c.set_active(true)
	await process_frame
	await process_frame
	var column: Node = c.panel.get_child(0)
	var block_button: Button = column.get_child(1)
	var desk_button: Button = column.get_child(2)
	var count: int = c.placed.get_child_count()
	gui_click(block_button, block_button.size / 2.0)
	check(
		c.selected_asset == "block" and c.state == Placement.EditorState.PLACING,
		"GUI click directly on centered button text selects block"
	)
	check(c.placed.get_child_count() == count, "GUI click does not place furniture")
	key(c, KEY_ESCAPE)
	gui_click(desk_button, Vector2(8, desk_button.size.y / 2.0))
	check(c.selected_asset == "office_desk", "GUI click in button padding selects desk")
	key(c, KEY_ESCAPE)
	for point in [
		Vector2(6, 6),
		desk_button.size - Vector2(6, 6),
		Vector2(desk_button.size.x - 6, 6),
		Vector2(6, desk_button.size.y - 6)
	]:
		gui_click(desk_button, point)
		check(
			c.selected_asset == "office_desk", "GUI hit covers entire visible button, not only text"
		)
		key(c, KEY_ESCAPE)
	# CanvasLayer offset/scale and smaller viewport must share drawing/hit coordinates.
	var layer: CanvasLayer = c.panel.get_parent()
	var saved_transform: Transform2D = layer.transform
	layer.transform = Transform2D(0, Vector2(24, 12)).scaled_local(Vector2(1.25, 1.25))
	root.size = Vector2i(960, 540)
	await process_frame
	gui_click(desk_button, desk_button.size / 2.0)
	check(
		c.selected_asset == "office_desk", "GUI text hit works with canvas offset/scale and resize"
	)
	var panel_point: Vector2 = (
		desk_button.get_global_transform_with_canvas() * (desk_button.size / 2.0)
	)
	check(c._over_panel(panel_point), "panel guard uses viewport-to-local transform")
	key(c, KEY_ESCAPE)
	layer.transform = saved_transform
	root.size = Vector2i(1280, 720)
	await process_frame
	# Selection independent of face/camera direction, plus real wall occlusion.
	var top: Vector3 = desk.to_global(Vector3(0, 3, 0))
	check(
		c._pick_ray(top, desk.global_basis * Vector3.DOWN) == desk,
		"exact ray from above selects tabletop"
	)
	check(
		(
			c._pick_ray(desk.to_global(Vector3(1.5, 0.73, 0)), desk.global_basis * Vector3.LEFT)
			== desk
		),
		"exact ray from side selects tabletop edge"
	)
	check(
		c._pick_ray(desk.to_global(Vector3(0, -0.01, 0)), desk.global_basis * Vector3.UP) == null,
		"floor occludes furniture when ray starts below floor"
	)
	check(
		c._pick_ray(Vector3(-8, 0.73, desk.global_position.z), Vector3.RIGHT) == null,
		"west wall blocks selection through wall"
	)
	check(
		(
			c._pick_ray(desk.to_global(Vector3(0, 0.3, 2)), desk.global_basis * Vector3.FORWARD)
			!= desk
		),
		"ray through empty leg gap does not select neighboring triangles"
	)
	c.select_asset("office_desk")
	var ghost: Node3D = c.preview
	var new_desks: Array[Node3D] = []
	var desk_targets: Array[Vector3] = [Vector3(3, 0, -3), Vector3(3, 0, 0), Vector3(4.5, 0, 3)]
	for index in range(3):
		if index == 1:
			key(c, KEY_R)
		var turns: int = c.quarter_turns
		var point: Vector2 = camera.unproject_position(desk_targets[index])
		click(c, point, true)
		check(c.placed.get_child_count() == count + index + 1, "Ctrl click adds independent desk")
		var object: Node3D = c.placed.get_child(count + index)
		new_desks.append(object)
		check(
			(
				object != ghost
				and c.editing == null
				and c.preview == ghost
				and c.state == Placement.EditorState.PLACING
				and c.selected_asset == "office_desk"
			),
			"Ctrl keeps only independent preview active, not placed desk"
		)
		check(
			c.quarter_turns == turns and is_equal_approx(object.rotation.y, turns * PI / 2),
			"Ctrl preserves rotation including R between placements"
		)
		check(
			materials_snapshot(c, object) == materials_snapshot(c, desk),
			"Ctrl placed desk has original materials and shadows"
		)
	check(
		new_desks[0] != new_desks[1] and new_desks[1] != new_desks[2],
		"three distinct desk instances"
	)
	key(c, KEY_ESCAPE)
	check_idle(c, "Esc cancels only repeat preview")
	check(c.active and c.placed.get_child_count() == count + 3, "Esc preserves all Ctrl placements")
	c.select_asset("office_desk")
	click(c, camera.unproject_position(Vector3(-4, 0, 3)))
	check_idle(c, "ordinary LMB still places one desk and removes preview")
	var move: Node3D = new_desks[0]
	var initial: Transform3D = move.global_transform
	var materials: Array = materials_snapshot(c, move)
	var total: int = c.placed.get_child_count()
	c.begin_move(move)
	key(c, KEY_R)
	c._update_preview(camera.unproject_position(Vector3(-1.5, 0, -1.5)))
	key(c, KEY_ESCAPE)
	check(
		move.global_transform.is_equal_approx(initial) and materials_snapshot(c, move) == materials,
		"move cancellation after Ctrl placement restores transform/materials/shadows"
	)
	c.begin_move(move)
	var move_target: Vector2 = camera.unproject_position(Vector3(-1.5, 0, -1.5))
	c._update_preview(move_target)
	var expected_move: Transform3D = move.global_transform
	click(c, move_target, true)
	check_idle(c, "Ctrl confirm in MOVING returns idle, never starts repeat placement")
	check(
		(
			c.placed.get_child_count() == total
			and move.global_transform.is_equal_approx(expected_move)
		),
		"Ctrl MOVING confirms the cell-aligned transform without cloning furniture"
	)
	key(c, KEY_ESCAPE)


func _test_employee_workstation(c: Node, camera: Camera3D) -> void:
	c.set_active(true)
	await process_frame
	var column: Node = c.panel.get_child(0)
	var workstation_button: Button = column.get_child(3)
	var before_count: int = c.placed.get_child_count()
	var packed: PackedScene = (
		load("res://assets/models/furniture/desks/employee_workstation.glb") as PackedScene
	)
	var pristine: Node3D = packed.instantiate()
	var source_materials: Array = materials_snapshot(c, pristine)
	pristine.free()
	gui_click(workstation_button, workstation_button.size / 2.0)
	check(
		c.selected_asset == "employee_workstation" and c.state == Placement.EditorState.PLACING,
		"workstation catalogue button starts placement preview"
	)
	check(
		(
			c.status.text.begins_with("Рабочее место сотрудника")
			and c.placement_diagnostic == "VALID"
			and c.valid_target
			and c.front_marker.visible
			and c.front_marker.get_meta("allowed")
		),
		"workstation selection starts with a valid preview and matching green marker"
	)
	var preview: Node3D = c.preview
	var bounds: AABB = preview.get_meta("bounds")
	check(
		bounds.size.distance_to(Vector3(1.4980, 1.4756, 1.3482)) < 0.0001,
		"workstation bounds include the rotated chair base and complete kit"
	)
	var meshes: Array[MeshInstance3D] = c._meshes(preview)
	var surface_total: int = 0
	for mesh in meshes:
		surface_total += mesh.mesh.get_surface_count()
	check(
		meshes.size() == 6 and surface_total == 7,
		"preview retains all six meshes and seven surfaces"
	)
	check(
		c.ghost_records.size() == 6,
		"ghost overrides are per preview mesh, not shared source resources"
	)
	var target: Vector2 = camera.unproject_position(Vector3(-2.0, 0, -3.0))
	c._update_preview(target)
	check(c.valid_target and preview.visible, "full-size workstation preview fits the floor grid")
	var workstation_cells: Vector2i = c.current_footprint_size
	var workstation_rect: Rect2 = c._footprint_rect(c.current_footprint_origin, workstation_cells)
	var workstation_bounds: AABB = c._object_bounds_in_floor(preview, bounds)
	check(
		(
			workstation_bounds.position.x >= workstation_rect.position.x
			and workstation_bounds.end.x <= workstation_rect.end.x
			and workstation_bounds.position.z >= workstation_rect.position.y
			and workstation_bounds.end.z <= workstation_rect.end.y
		),
		"complete chair-and-desk bounds fit inside the functional cell envelope"
	)
	check(
		(
			is_instance_valid(c.front_marker)
			and c.front_marker.visible
			and c.front_marker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		),
		"front marker appears over valid preview and never casts a shadow"
	)
	var arrays: Array = c.front_marker.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check(
		c.current_footprint_size == Vector2i(7, 6) and vertices.size() == 72,
		"workstation marker outlines all 42 occupied cells and seven front arrows"
	)
	var lowest_z: float = INF
	var highest_z: float = -INF
	for vertex in vertices:
		lowest_z = minf(lowest_z, vertex.z)
		highest_z = maxf(highest_z, vertex.z)
	check(highest_z > lowest_z, "front arrows point along local +Z")
	check(
		(
			vertices[0].x == workstation_rect.position.x
			and vertices[0].z == workstation_rect.position.y
			and vertices[1].x == workstation_rect.position.x
			and vertices[1].z == workstation_rect.end.y
		),
		"workstation marker borders equal the full functional footprint rectangle"
	)
	check(
		(
			c.front_marker.global_transform.is_equal_approx(c.floor_mesh.global_transform)
			and c.front_marker.get_meta("footprint_origin_cells") == c.current_footprint_origin
		),
		"marker occupies the same floor-aligned cells as the preview"
	)
	key(c, KEY_R)
	c._update_preview(target)
	check(
		(
			c.quarter_turns == 1
			and c.current_footprint_size == Vector2i(6, 7)
			and c.front_marker.get_meta("front_direction") == Vector2i(1, 0)
		),
		"front arrows and footprint direction rotate 90 degrees with the model"
	)
	var moved_target: Vector2 = camera.unproject_position(Vector3(-1.5, 0, -3.0))
	c._update_preview(moved_target)
	check(
		(
			c.front_marker.get_meta("footprint_origin_cells") == c.current_footprint_origin
			and c.front_marker.global_transform.is_equal_approx(c.floor_mesh.global_transform)
		),
		"marker follows mouse movement by updating the exact occupied cell origin"
	)
	click(c, moved_target)
	check(
		c.placed.get_child_count() == before_count + 1 and c.state == Placement.EditorState.IDLE,
		"LMB places one independent employee workstation"
	)
	check(
		c.front_marker == null or not c.front_marker.visible,
		"front marker disappears after placement"
	)
	var placed: Node3D = c.placed.get_child(before_count)
	check(
		placed.get_meta("asset_id") == "employee_workstation" and c.editable.has(placed),
		"placed workstation is registered for picking and moving"
	)
	var world_bounds: AABB = placed.global_transform * placed.get_meta("bounds")
	check(
		absf(world_bounds.position.y) < 0.003,
		"placed workstation bounds rest on floor without scale compensation"
	)
	check(
		materials_snapshot(c, placed) == source_materials,
		"installed GLB keeps its source materials; ghost overrides stayed on preview only"
	)
	var monitor_point: Vector3 = placed.to_global(Vector3(-0.23, 1.46, -0.56))
	var picked: Node3D = c._pick_ray(monitor_point + Vector3.UP * 2.0, Vector3.DOWN)
	check(picked == placed, "mesh-level picking finds the new workstation")
	var saved_transform: Transform3D = placed.global_transform
	c.begin_move(placed)
	c._update_preview(target)
	check(
		c.state == Placement.EditorState.MOVING and c.front_marker.visible,
		"moving a placed workstation shows the front marker"
	)
	check(
		(
			c.front_marker.get_meta("footprint_origin_cells") == c.current_footprint_origin
			and c.front_marker.get_meta("footprint_cells") == c.current_footprint_size
			and c.front_marker.global_transform.is_equal_approx(c.floor_mesh.global_transform)
		),
		"move marker matches the moving model's occupied cell rectangle"
	)
	key(c, KEY_ESCAPE)
	check(
		(
			placed.global_transform.is_equal_approx(saved_transform)
			and materials_snapshot(c, placed) == source_materials
			and (c.front_marker == null or not c.front_marker.visible)
		),
		"cancelled move restores transform/materials and hides marker"
	)
	c.begin_move(placed)
	c._update_preview(target)
	click(c, target)
	check(
		(
			c.placed.get_child_count() == before_count + 1
			and c.editable.has(placed)
			and c.state == Placement.EditorState.IDLE
		),
		"confirmed move reuses the placed workstation without cloning"
	)
	c.select_asset("employee_workstation")
	c._update_preview(target)
	check(
		c.front_marker.visible and not c.valid_target and not c.front_marker.get_meta("allowed"),
		"overlapping workstation preview shows its invalid red footprint before cancellation"
	)
	key(c, KEY_ESCAPE)
	check(
		c.front_marker == null or not c.front_marker.visible,
		"Escape cancellation removes the placement marker"
	)
	c.set_active(false)
	check(
		not c.grid.visible and (c.front_marker == null or not c.front_marker.visible),
		"leaving placement mode hides grid and marker"
	)


func _test_room_labels(scene: Node, rig: Node3D, camera: Camera3D, c: Node) -> void:
	var labels: Node3D = scene.get_node("RoomLabels")
	check(labels.plaques.size() == 3, "first scene has three zone wayfinding plaques")
	var expected: Array = [
		["office_101", "КАБИНЕТ", "101", Vector3(-3, 0, 2.15)],
		["office_102", "КАБИНЕТ", "102", Vector3(3, 0, 2.15)],
		["corridor_main", "ОБЩИЙ", "КОРИДОР", Vector3(0, 0, 3.35)],
	]
	for entry in expected:
		var plaque: Node3D = labels.get_node("RoomLabel_" + entry[0])
		check(
			plaque.get_meta("zone_id") == entry[0] and plaque.position.is_equal_approx(entry[3]),
			"plaque is anchored to the documented zone " + entry[0]
		)
		var room_type: Label3D = plaque.get_node("RoomType") as Label3D
		var room_name: Label3D = plaque.get_node("RoomName") as Label3D
		check(
			room_type.text == entry[1] and room_name.text == entry[2],
			"plaque text is editable and hierarchical for " + entry[0]
		)
		check(
			not c.room_occluders.has(plaque.get_node("PlaqueBacking")),
			"wayfinding plaque does not enter furniture obstacle checks"
		)
	var original_yaw: float = rig.rotation.y
	var first_plaque: Node3D = labels.plaques[0]
	rig.rotation.y += PI * 0.5
	labels.update_camera_facing()
	var to_camera: Vector3 = camera.global_position - first_plaque.global_position
	to_camera.y = 0.0
	check(
		is_equal_approx(first_plaque.rotation.y, atan2(to_camera.x, to_camera.z)),
		"floor plaque remains camera-aligned through yaw changes"
	)
	rig.rotation.y = original_yaw
	labels.update_camera_facing()


func _test_layout(c: Node, scene: Node) -> void:
	var partition: MeshInstance3D = scene.get_node("TestRoom/SharedWall")
	var walls: Node = scene.get_node("WallVisibility")
	check(walls.originals[partition]["size"].y == 3.0, "TASK 011.1 authored partition is 3m")
	walls.update_visibility(Vector3(1, 0, 1))
	walls.advance_heights(100.0)
	check(
		is_inf(c._mesh_ray_distance(partition, Vector3(-0.5, 1.2, -1), Vector3.RIGHT)),
		"TASK 011 lowered partition does not occlude picking above cut"
	)
	walls.update_visibility(Vector3(0, 0, 1))
	walls.advance_heights(100.0)
	check(
		c._mesh_ray_distance(partition, Vector3(-0.5, 1.2, -1), Vector3.RIGHT) < 1.0,
		"TASK 011 restored full partition still occludes picking"
	)
	walls.update_visibility(Vector3(1, 0, 1))
	walls.advance_heights(100.0)
	for corner in ["RearWestCorner", "RearSharedCorner", "RearEastCorner"]:
		check(
			c.room_occluders.has(scene.get_node("TestRoom/" + corner)),
			"TASK 011 rear return included in room occluders"
		)
	for name in ["SharedWall", "WestWall", "DoorLeftHead", "WindowRightMullion"]:
		check(
			c.room_occluders.has(scene.get_node("TestRoom/" + name)),
			"new room architecture participates in existing picking occlusion: " + name
		)
	for center: float in [-3.0, 3.0]:
		var door_distance: float = INF
		var window_distance: float = INF
		for mesh: MeshInstance3D in c.room_occluders:
			door_distance = minf(
				door_distance, c._mesh_ray_distance(mesh, Vector3(center, 1, 2.5), Vector3.FORWARD)
			)
			window_distance = minf(
				window_distance,
				c._mesh_ray_distance(mesh, Vector3(center - 0.55, 1.6, -5), Vector3.BACK)
			)
		check(door_distance > 2.0, "ray enters office through real door opening")
		check(window_distance > 1.2, "ray enters office through real window opening")
