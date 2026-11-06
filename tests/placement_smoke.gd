extends SceneTree
## godot --headless --path . --script res://tests/placement_smoke.gd
## Real scene and imported GLB. Handler tests, not a visual/GUI acceptance test.
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


func click(controller: Node, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	controller._unhandled_input(event)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var c: Node = scene.get_node("PlacementController")
	var rig: Node3D = scene.get_node("CameraRig")
	var camera: Camera3D = rig.get_node("Camera3D")
	var original_desk: Node3D = scene.get_node("TestRoom/OfficeDesk")
	var camera_before: Transform3D = rig.global_transform
	check(
		not c.active and not c.grid.visible and not c.panel.visible and not c.preview.visible,
		"normal mode hides editor/grid/preview"
	)
	check(c.editable.has(original_desk), "existing room desk is editable")
	key(c, KEY_B)
	check(c.active and c.panel.visible and c.grid.visible, "B opens editor and grid")
	var block_screen: Vector2 = camera.unproject_position(Vector3(2.24, 0, 2.26))
	c._update_preview(block_screen)
	check(
		c.valid_target and c.preview.global_position.is_equal_approx(Vector3(2, 0, 2.5)),
		"block preview follows cursor at 0.5m step on floor"
	)
	click(c, block_screen)
	check(c.placed.get_child_count() == 1, "LMB places block")
	var block: Node3D = c.placed.get_child(0)
	check(block.get_meta("asset_id") == "block", "block asset recorded")
	c.select_asset("office_desk")
	var bounds: AABB = c.preview.get_meta("bounds")
	check(bounds.size.is_equal_approx(Vector3(1.6, 0.75, 0.8)), "desk bounds from imported meshes")
	check(c.ghost_records.size() == 9, "all nine desk meshes are preview ghosts")
	var desk_screen: Vector2 = camera.unproject_position(Vector3(-2, 0, 2))
	c._update_preview(desk_screen)
	click(c, desk_screen)
	check(c.placed.get_child_count() == 2, "LMB places imported desk")
	var desk: Node3D = c.placed.get_child(1)
	check(
		desk.get_meta("asset_id") == "office_desk" and is_zero_approx(desk.position.y),
		"desk asset and origin rest on floor"
	)
	# Exercise actual UI button connection without requiring pointer/window automation.
	var column: Node = c.panel.get_child(0)
	column.get_child(1).emit_signal("pressed")
	check(c.selected_asset == "block", "block UI button selects block")
	column.get_child(2).emit_signal("pressed")
	check(c.selected_asset == "office_desk", "desk UI button selects desk")
	# Per-mesh picking selects the existing desk top rather than empty space between legs.
	var pick_screen: Vector2 = camera.unproject_position(Vector3(0, 0.75, 0))
	check(c.pick_object(pick_screen) == original_desk, "ray picks existing desk top")
	var initial: Transform3D = original_desk.global_transform
	click(c, pick_screen)
	check(
		c.editing == original_desk and c.preview == original_desk,
		"LMB begins moving the original object, not a duplicate"
	)
	var destination: Vector2 = camera.unproject_position(Vector3(1.26, 0, -1.26))
	c._update_preview(destination)
	# R also reprojects using the live cursor; restore our test point afterwards.
	key(c, KEY_R)
	c._update_preview(destination)
	check(
		c.quarter_turns == 1 and is_equal_approx(original_desk.rotation.y, PI / 2),
		"R rotates moved desk by 90 degrees"
	)
	check(
		original_desk.global_position.is_equal_approx(Vector3(1.5, 0, -1.5)),
		"moved desk snaps and stays on floor"
	)
	key(c, KEY_ESCAPE)
	check(
		c.editing == null and c.active and original_desk.global_transform.is_equal_approx(initial),
		"Escape rolls back position/rotation and keeps editor open"
	)
	check(original_desk.visible, "cancelled desk visible")
	for mesh: MeshInstance3D in c._meshes(original_desk):
		check(
			mesh.get_surface_override_material(0) == null,
			"cancel restores imported material, removes ghost override"
		)
	c.begin_move(original_desk)
	c._update_preview(destination)
	key(c, KEY_R)
	c._update_preview(destination)
	click(c, destination)
	check(
		(
			c.editing == null
			and original_desk.visible
			and original_desk.global_position.is_equal_approx(Vector3(1.5, 0, -1.5))
			and is_equal_approx(original_desk.rotation.y, PI / 2)
		),
		"LMB commits moved/rotated desk"
	)
	check(c.placed.get_child_count() == 2, "moving does not create duplicates")
	c.begin_move(block)
	c._update_preview(destination)
	key(c, KEY_B)
	check(
		(
			not c.active
			and c.editing == null
			and block.global_position.is_equal_approx(Vector3(2, 0, 2.5))
		),
		"B exits and rolls back pending block move"
	)
	check(
		not c.preview.visible and not c.panel.visible and not c.grid.visible,
		"exit hides all editor visuals"
	)
	key(c, KEY_B)
	c.select_asset("office_desk")
	c.quarter_turns = 0
	check(not c.target_inside_floor(Vector3(5.5, c.floor_top, 0)), "1.6m desk respects X edge")
	c.quarter_turns = 1
	check(
		c.target_inside_floor(Vector3(5.5, c.floor_top, 0)), "rotated 0.8m depth fits same X edge"
	)
	var count: int = c.placed.get_child_count()
	click(c, c.panel.position + Vector2(5, 5))
	check(c.placed.get_child_count() == count, "panel clicks do not place objects")
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	Input.parse_input_event(middle)
	click(c, camera.unproject_position(Vector3(-3, 0, -2)))
	check(
		c.placed.get_child_count() == count and c.editing == null, "MMB blocks confirmation/picking"
	)
	middle.pressed = false
	Input.parse_input_event(middle)
	key(c, KEY_ESCAPE)
	check(
		not c.active and rig.global_transform.is_equal_approx(camera_before),
		"Escape exits; placement did not move camera"
	)
	print("Placement smoke test failures: ", failures)
	quit(0 if failures == 0 else 1)
