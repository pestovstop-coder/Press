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
	var block_screen: Vector2 = camera.unproject_position(Vector3(2.24, 0, 2.26))
	c._update_preview(block_screen)
	check(
		(
			c.valid_target
			and c.preview.visible
			and c.preview.global_position.is_equal_approx(Vector3(2, 0, 2.5))
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
	var bounds: AABB = c.preview.get_meta("bounds")
	check(
		bounds.size.is_equal_approx(Vector3(1.6, 0.75, 0.8)), "desk bounds from imported geometry"
	)
	check(c.ghost_records.size() == 9, "desk preview ghosts all meshes")
	key(c, KEY_R)
	var desk_screen: Vector2 = camera.unproject_position(Vector3(-4.5, 0, -1.5))
	c._update_preview(desk_screen)
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
	check(
		(
			original_desk.global_position.is_equal_approx(Vector3(1.5, 0, -1.5))
			and is_equal_approx(original_desk.rotation.y, PI / 2)
		),
		"move snaps and rotates"
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
		(
			original_desk.visible
			and original_desk.global_position.is_equal_approx(Vector3(1.5, 0, -1.5))
			and is_equal_approx(original_desk.rotation.y, PI / 2)
		),
		"confirmed desk remains at destination"
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
	for index in range(3):
		if index == 1:
			key(c, KEY_R)
		var turns: int = c.quarter_turns
		var point: Vector2 = camera.unproject_position(Vector3(3, 0, -3 + index * 3))
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
	c._update_preview(camera.unproject_position(Vector3(2, 0, -3)))
	key(c, KEY_ESCAPE)
	check(
		move.global_transform.is_equal_approx(initial) and materials_snapshot(c, move) == materials,
		"move cancellation after Ctrl placement restores transform/materials/shadows"
	)
	c.begin_move(move)
	click(c, camera.unproject_position(Vector3(2, 0, -3)), true)
	check_idle(c, "Ctrl confirm in MOVING returns idle, never starts repeat placement")
	check(
		(
			c.placed.get_child_count() == total
			and move.global_position.is_equal_approx(Vector3(2, 0, -3))
		),
		"Ctrl MOVING confirms without cloning furniture"
	)
	key(c, KEY_ESCAPE)


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
