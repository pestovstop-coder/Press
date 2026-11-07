extends SceneTree
## Run with Godot after import: --headless --path . --script res://tests/orbit_smoke.gd
## Actual scene handler tests; not a substitute for visual/manual acceptance.
const Placement = preload("res://scripts/placement_controller.gd")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + description)
	else:
		print("PASS: " + description)


func button(which: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = which
	event.pressed = pressed
	return event


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var rig: Node3D = scene.get_node("CameraRig")
	var cam: Camera3D = rig.get_node("Camera3D")
	var walls: Node = scene.get_node("WallVisibility")
	var c: Node = scene.get_node("PlacementController")
	var room: Node = scene.get_node("TestRoom")
	var desk: Node3D = room.get_node("OfficeDesk")
	var transforms: Dictionary = {}
	for mesh in walls.modules:
		transforms[mesh] = mesh.transform
	check(walls.modules.size() == 36, "all 36 wall/frame modules registered")
	var expected := [
		["front", "east", "shared"],
		["rear", "east", "shared"],
		["rear", "west", "shared"],
		["front", "west", "shared"]
	]
	var initial: Transform3D = cam.global_transform
	for index in range(4):
		for side in walls.hidden_sides:
			check(
				walls.hidden_sides[side] == (side in expected[index]), "quarter-turn side: " + side
			)
		check(
			is_equal_approx(cam.global_position.distance_to(rig.global_position), 30),
			"orbit radius"
		)
		check(
			(
				(-cam.global_basis.z).dot((rig.global_position - cam.global_position).normalized())
				> 0.999
			),
			"camera looks at focus, not rotating in place"
		)
		for mesh in walls.modules:
			check(mesh.transform == transforms[mesh], "wall transform unchanged: " + mesh.name)
		# Place a block, rotate a desk preview and Ctrl-repeat at each angle.
		c.set_active(true)
		c.select_asset("block")
		c._update_preview(cam.unproject_position(Vector3(2, 0, 3)))
		check(c.valid_target, "floor targeting after orbit")
		c.place_block(true)
		check(c.state == Placement.EditorState.PLACING, "Ctrl-style placing retained")
		var placed: Node3D = c.placed.get_child(c.placed.get_child_count() - 1)
		c.cancel_operation()
		c.select_asset("office_desk")
		var turn := InputEventKey.new()
		turn.keycode = KEY_R
		turn.pressed = true
		c._unhandled_input(turn)
		check(c.quarter_turns == 1, "R still rotates desk preview")
		c.cancel_operation()
		c.begin_move(placed)
		c.cancel_operation()
		check(
			placed.visible and placed.position.is_equal_approx(Vector3(2, 0, 3)),
			"move cancellation restores block"
		)
		c.editable.erase(placed)
		placed.queue_free()
		c.set_active(false)
		rig._orbit(Vector2(-360, 0))
		await process_frame
	check(cam.global_transform.is_equal_approx(initial), "full circle returns camera and walls")
	var seen_visible: Dictionary = {}
	var seen_hidden: Dictionary = {}
	for step in range(180):
		rig._orbit(Vector2(-8, 0))
		for mesh in walls.modules:
			if mesh.visible:
				seen_visible[mesh] = true
			else:
				seen_hidden[mesh] = true
	check(
		seen_visible.size() == 36 and seen_hidden.size() == 36,
		"all modules hide and reappear during continuous full circle"
	)
	check(cam.global_transform.is_equal_approx(initial), "continuous circle returns camera")
	# Hidden wall ray must reach furniture; visible wall must stop it.
	var west: MeshInstance3D = room.get_node("WestWall")
	var origin := Vector3(-8, 0.73, desk.global_position.z)
	check(c._pick_ray(origin, Vector3.RIGHT) == null, "visible west blocks furniture ray")
	rig._orbit(Vector2(-720, 0))
	check(not west.visible, "west hidden after half-turn")
	check(
		is_inf(c._mesh_ray_distance(west, origin, Vector3.RIGHT)),
		"hidden wall excluded from triangle ray"
	)
	check(c._pick_ray(origin, Vector3.RIGHT) == desk, "ray through hidden west reaches actual desk")
	# Navigation cannot confirm placement even if handler called directly.
	c.set_active(true)
	c.select_asset("block")
	c._update_preview(cam.unproject_position(Vector3(2, 0, 3)))
	var count: int = c.placed.get_child_count()
	for which in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		rig._unhandled_input(button(which, true))
		c._unhandled_input(button(MOUSE_BUTTON_LEFT, true))
		check(c.placed.get_child_count() == count, "navigation + LMB cannot place")
		rig._input(button(which, false))
		check(not rig.is_navigating(), "release clears navigation even over GUI")
	c.cancel_operation()
	c.set_active(false)
	rig._reset()
	rig._orbit(Vector2(0, 10000))
	check(is_equal_approx(rig.rotation_degrees.x, -70), "steep pitch clamp")
	rig._orbit(Vector2(0, -10000))
	check(
		is_equal_approx(rig.rotation_degrees.x, -20) and cam.global_position.y > 10,
		"shallow pitch stays above floor"
	)
	rig._unhandled_input(button(MOUSE_BUTTON_WHEEL_UP, true))
	rig._process(0.1)
	check(cam.size < 16, "wheel zoom in")
	rig._unhandled_input(button(MOUSE_BUTTON_WHEEL_DOWN, true))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 20)
	rig._unhandled_input(button(MOUSE_BUTTON_MIDDLE, true))
	rig._unhandled_input(motion)
	check(
		not rig.position.is_zero_approx() and is_zero_approx(rig.position.y),
		"MMB pans focus on floor"
	)
	rig._input(button(MOUSE_BUTTON_MIDDLE, false))
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = true
		var before: Vector3 = rig.position
		Input.parse_input_event(event)
		await create_timer(0.03).timeout
		event.pressed = false
		Input.parse_input_event(event)
		check(not rig.position.is_equal_approx(before), "keyboard pan " + str(code))
	var home := InputEventKey.new()
	home.keycode = KEY_HOME
	home.pressed = true
	rig._unhandled_input(home)
	check(
		(
			rig.position.is_zero_approx()
			and cam.global_transform.is_equal_approx(initial)
			and is_equal_approx(cam.size, 16)
		),
		"Home resets focus, angles and zoom"
	)
	# Return near edge-on, including tiny repeated jitter: central wall reappears.
	walls.update_visibility(Vector3(0, 0, 1))
	check(room.get_node("SharedWall").visible, "edge-on shared wall restored")
	for index in range(100):
		walls.update_visibility(Vector3(0.14 + (0.001 if index % 2 else -0.001), 0, 1))
		check(room.get_node("SharedWall").visible, "shared hysteresis stable")
	scene.queue_free()
	print("TASK011 handler smoke failures: ", failures)
	quit(1 if failures else 0)
