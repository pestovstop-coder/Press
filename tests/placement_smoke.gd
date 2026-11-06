extends SceneTree
## Run: godot --headless --path . --script res://tests/placement_smoke.gd
## This loads the delivered scene; no mock controller or replacement geometry.
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


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var controller: Node = scene.get_node("PlacementController")
	var rig: Node3D = scene.get_node("CameraRig")
	var camera: Camera3D = rig.get_node("Camera3D")
	check(
		not controller.active and not controller.grid.visible and not controller.preview.visible,
		"normal mode hides grid and preview"
	)
	check(
		controller.floor_bounds.size.is_equal_approx(Vector3(12, 0.2, 10)),
		"bounds derived from original 12 x 10 metre floor"
	)
	key(controller, KEY_B)
	check(controller.active and controller.grid.visible, "B enables placement/grid")
	var camera_before: Transform3D = rig.global_transform
	for point in [Vector3(0.24, 0, 0.26), Vector3(-1.26, 0, 1.24), Vector3(2, 0, -1)]:
		var screen_point: Vector2 = camera.unproject_position(point)
		controller._update_preview(screen_point)
		var expected: Vector3 = controller.floor_mesh.to_global(
			controller.snapped_floor_point(controller.floor_mesh.to_local(point))
		)
		check(
			(
				controller.valid_target
				and controller.preview.global_position.is_equal_approx(expected)
			),
			"mouse ray follows floor and snaps: " + str(point)
		)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = screen_point
		controller._unhandled_input(click)
	check(controller.placed.get_child_count() == 3, "three LMB clicks place three blocks")
	check(rig.global_transform.is_equal_approx(camera_before), "placement does not move camera")
	for block: Node3D in controller.placed.get_children():
		check(is_zero_approx(block.global_position.y), "block base contacts floor at world Y=0")
	key(controller, KEY_R)
	check(
		controller.quarter_turns == 1 and is_equal_approx(controller.preview.rotation.y, PI / 2),
		"R rotates preview by 90 degrees"
	)
	controller.place_block()
	var rotated: Node3D = controller.placed.get_child(3)
	check(is_equal_approx(rotated.rotation.y, PI / 2), "confirmed block retains rotation")
	for i in range(3):
		key(controller, KEY_R)
	check(controller.quarter_turns == 0, "four quarter-turns return to initial orientation")
	check(
		controller.target_inside_floor(Vector3(5.5, controller.floor_top, 4.5)),
		"footprint fits at floor edge"
	)
	check(
		not controller.target_inside_floor(Vector3(6, controller.floor_top, 5)),
		"footprint extending outside floor is rejected"
	)
	controller._update_preview(camera.unproject_position(Vector3(20, 0, 20)))
	check(
		not controller.valid_target and not controller.preview.visible,
		"outside floor hides preview"
	)
	controller.place_block()
	check(controller.placed.get_child_count() == 4, "invalid target does not place")
	key(controller, KEY_ESCAPE)
	check(
		not controller.active and not controller.grid.visible and not controller.preview.visible,
		"Escape exits placement and hides grid/preview"
	)
	controller.place_block()
	check(
		controller.placed.get_child_count() == 4,
		"cancel preserves existing blocks and prevents new ones"
	)
	key(controller, KEY_B)
	check(controller.active and controller.quarter_turns == 0, "placement can be restarted")
	key(controller, KEY_B)
	check(not controller.active, "B toggles placement off")
	print("Placement smoke test failures: ", failures)
	quit(0 if failures == 0 else 1)
