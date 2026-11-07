extends SceneTree
## Godot engine handler/geometry smoke, NOT visual acceptance.
## --headless --path . --script res://tests/height_smoke.gd
const Placement = preload("res://scripts/placement_controller.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, description: String) -> void:
	if ok:
		print("PASS: " + description)
	else:
		push_error("FAIL: " + description)
		failures += 1


func button(which: MouseButton, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = which
	event.pressed = pressed
	return event


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://scenes/main.tscn")
	var shared_resources: Dictionary = {}
	var state: SceneState = packed.get_state()
	for i in range(state.get_node_count()):
		for j in range(state.get_node_property_count(i)):
			if state.get_node_property_name(i, j) == "mesh":
				var value: Variant = state.get_node_property_value(i, j)
				if value is BoxMesh:
					shared_resources[value] = value.size
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var walls: Node = scene.get_node("WallVisibility")
	var rig: Node3D = scene.get_node("CameraRig")
	var cam: Camera3D = rig.get_node("Camera3D")
	var c: Node = scene.get_node("PlacementController")
	var room: Node = scene.get_node("TestRoom")
	var west: MeshInstance3D = room.get_node("WestWall")
	var join: MeshInstance3D = room.get_node("FrontSharedCorner")
	var initial: Transform3D = cam.global_transform
	var unique: Dictionary = {}
	for mesh in walls.modules:
		unique[mesh.mesh] = true
	check(
		walls.modules.size() == 39 and unique.size() == 39,
		"39 independently owned BoxMesh resources"
	)
	for turn in range(5):
		var before: float = walls.heights["front"]
		walls.update_visibility(cam.global_basis.z)
		check(walls.heights["front"] == before, "camera target update does not snap geometry")
		for frame in range(90):
			walls.advance_heights(1.0 / 60.0)
			var valid: bool = true
			for mesh in walls.modules:
				var original: Dictionary = walls.originals[mesh]
				var size: Vector3 = original["size"]
				var center: Vector3 = original["position"]
				var bottom: float = center.y - size.y / 2.0
				var top: float = minf(center.y + size.y / 2.0, walls.module_height(mesh))
				valid = valid and absf(mesh.transform.basis.determinant()) > 0.99
				if top - bottom <= 0.0001:
					valid = valid and not mesh.visible
				else:
					valid = valid and mesh.visible
					valid = (
						valid and is_equal_approx(mesh.position.y - mesh.mesh.size.y / 2.0, bottom)
					)
					valid = valid and is_equal_approx(mesh.position.y + mesh.mesh.size.y / 2.0, top)
					valid = (
						valid
						and is_equal_approx(mesh.mesh.size.x, size.x)
						and is_equal_approx(mesh.mesh.size.z, size.z)
					)
				if absf(bottom) < 0.00001:
					valid = valid and mesh.visible and mesh.mesh.size.y >= 0.89999
			valid = (
				valid
				and is_equal_approx(
					join.position.y + join.mesh.size.y / 2.0,
					maxf(walls.heights["front"], walls.heights["shared"])
				)
			)
			check(
				valid,
				"animated frame has clipped geometry, bases, junction and invertible transforms"
			)
		for side in walls.heights:
			check(
				is_equal_approx(walls.heights[side], 0.9 if walls.hidden_sides[side] else 3.0),
				"settles at target: " + side
			)
		# Actual door/window rays remain clear through their apertures at every view.
		for x: float in [-3.0, 3.0]:
			var door: float = INF
			var window: float = INF
			for mesh in c.room_occluders:
				door = minf(door, c._mesh_ray_distance(mesh, Vector3(x, 1, 2.5), Vector3.FORWARD))
				window = minf(
					window, c._mesh_ray_distance(mesh, Vector3(x - 0.55, 1.6, -5), Vector3.BACK)
				)
			check(door > 1.5 and window > 1.2, "door/window apertures preserved")
		c.set_active(true)
		c.select_asset("block")
		c._update_preview(cam.unproject_position(Vector3(2, 0, 3)))
		check(c.valid_target, "floor placement after camera orbit")
		var count: int = c.placed.get_child_count()
		c.place_block(true)
		check(
			c.placed.get_child_count() == count + 1 and c.state == Placement.EditorState.PLACING,
			"Ctrl-style placement retains independent preview"
		)
		c.cancel_operation()
		var object: Node3D = c.placed.get_child(count)
		var original_transform: Transform3D = object.global_transform
		c.begin_move(object)
		c.cancel_operation()
		check(
			object.global_transform == original_transform and object.visible,
			"move cancellation restores object"
		)
		c.editable.erase(object)
		c.placed.remove_child(object)
		object.queue_free()
		c.set_active(false)
		if turn < 4:
			rig._orbit(Vector2(-360, 0))
	check(cam.global_transform.is_equal_approx(initial), "360 degree orbit returns camera")
	# Fill picking cache at full height, lower wall, verify fresh clipped triangles.
	walls.update_visibility(Vector3(1, 0, 1))
	walls.advance_heights(100)
	check(
		c._mesh_ray_distance(west, Vector3(-8, 1.2, -1), Vector3.RIGHT) < 3, "full west blocks ray"
	)
	check(c.face_cache.has(west.mesh), "full triangle cache populated")
	walls.update_visibility(Vector3(-1, 0, -1))
	walls.advance_heights(100)
	check(not c.face_cache.has(west.mesh), "mutated mesh invalidates cached triangles")
	check(
		is_inf(c._mesh_ray_distance(west, Vector3(-8, 1.2, -1), Vector3.RIGHT)),
		"above lowered wall is pickable"
	)
	check(
		c._mesh_ray_distance(west, Vector3(-8, 0.45, -1), Vector3.RIGHT) < 3,
		"lowered wall base still blocks ray"
	)
	var desk: Node3D = room.get_node("OfficeDesk")
	var origin := Vector3(-8, 2, desk.global_position.z)
	var direction: Vector3 = (desk.global_position + Vector3(0, 0.73, 0) - origin).normalized()
	check(c._pick_ray(origin, direction) == desk, "oblique ray over lowered wall reaches real desk")
	walls.update_visibility(Vector3(1, 0, 1))
	walls.advance_heights(100)
	check(c._pick_ray(origin, direction) == null, "restored wall occludes desk again")
	for resource in shared_resources:
		check(resource.size == shared_resources[resource], "authored shared BoxMesh unchanged")
	# Near-threshold jitter retains target and must not restart/snap the animation.
	walls.update_visibility(Vector3(0, 0, 1))
	for frame in range(100):
		walls.update_visibility(Vector3(0.14 + (0.001 if frame % 2 else -0.001), 0, 1))
		check(not walls.hidden_sides["shared"], "shared hysteresis stable")
		walls.advance_heights(1.0 / 60.0)
	rig._orbit(Vector2(0, 10000))
	check(is_equal_approx(rig.rotation_degrees.x, -70), "steep pitch limit preserved")
	rig._orbit(Vector2(0, -10000))
	check(
		is_equal_approx(rig.rotation_degrees.x, -20) and cam.global_position.y > 10,
		"shallow pitch limit preserved"
	)
	rig._reset()
	check(
		cam.global_transform.is_equal_approx(initial) and is_equal_approx(cam.size, 16),
		"Home/reset preserves camera"
	)
	# Navigation cannot confirm placement even if handler called directly.
	c.set_active(true)
	c.select_asset("block")
	c._update_preview(cam.unproject_position(Vector3(2, 0, 3)))
	var navigation_count: int = c.placed.get_child_count()
	for which in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		rig._unhandled_input(button(which, true))
		c._unhandled_input(button(MOUSE_BUTTON_LEFT, true))
		check(c.placed.get_child_count() == navigation_count, "navigation + LMB cannot place")
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
	scene.queue_free()
	print("TASK011.1 engine smoke failures: ", failures)
	quit(1 if failures else 0)
