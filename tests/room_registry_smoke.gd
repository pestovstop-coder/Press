extends SceneTree
## Runtime checks for the first-scene logical room registry.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const EXPECTED_IDS: PackedStringArray = ["room_101", "room_102", "corridor_main"]

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = MAIN_SCENE.instantiate()
	root.add_child(scene)
	await process_frame

	var registry: Node = scene.get_node("RoomRegistry")
	var ids: PackedStringArray = registry.call("get_room_ids")
	_check(ids == EXPECTED_IDS, "all three stable room IDs are registered in deterministic order")

	var unique_ids: Dictionary = {}
	for room_id in ids:
		unique_ids[room_id] = true
	_check(unique_ids.size() == ids.size(), "registered room IDs are unique")

	var expected_names: Dictionary = {
		"room_101": "КАБИНЕТ 101",
		"room_102": "КАБИНЕТ 102",
		"corridor_main": "ОБЩИЙ КОРИДОР",
	}
	var expected_types: Dictionary = {
		"room_101": "office",
		"room_102": "office",
		"corridor_main": "corridor",
	}
	var expected_bounds: Dictionary = {
		"room_101": AABB(Vector3(-6.0, 0.0, -4.25), Vector3(6.0, 3.0, 6.0)),
		"room_102": AABB(Vector3(0.0, 0.0, -4.25), Vector3(6.0, 3.0, 6.0)),
		"corridor_main": AABB(Vector3(-6.0, 0.0, 1.75), Vector3(12.0, 3.0, 2.5)),
	}
	for room_id in ids:
		var room: Dictionary = registry.call("get_room_by_id", room_id)
		_check(room.get("id", "") == room_id, "room lookup by ID returns " + room_id)
		_check(
			room.get("display_name", "") == expected_names[room_id],
			"display name is correct for " + room_id
		)
		_check(
			room.get("type", "") == expected_types[room_id], "room type is correct for " + room_id
		)
		var bounds: AABB = room["bounds"]
		var expected: AABB = expected_bounds[room_id]
		_check(
			(
				bounds.position.is_equal_approx(expected.position)
				and bounds.size.is_equal_approx(expected.size)
			),
			"world-space AABB is correct for " + room_id
		)

	_check(registry.call("get_room_by_id", "missing_room").is_empty(), "unknown ID returns no room")

	var inside_points: Array = [
		[Vector3(-3.0, 1.0, -1.0), "room_101"],
		[Vector3(3.0, 1.0, -1.0), "room_102"],
		[Vector3(0.0, 1.0, 3.0), "corridor_main"],
	]
	for entry in inside_points:
		_check(
			registry.call("get_room_id_at", entry[0]) == entry[1],
			"an interior point is classified as " + entry[1]
		)

	var boundary_points: Array = [
		[Vector3(0.0, 1.0, -1.0), "room_102"],
		[Vector3(-3.0, 1.0, 1.75), "corridor_main"],
		[Vector3(0.0, 1.0, 1.75), "corridor_main"],
		[Vector3(-6.0, 0.0, -4.25), "room_101"],
	]
	for entry in boundary_points:
		_check(
			registry.call("get_room_id_at", entry[0]) == entry[1],
			"shared or inclusive lower boundary has exactly the documented owner: " + entry[1]
		)

	var outside_points: Array = [
		Vector3(7.0, 1.0, 0.0),
		Vector3(0.0, 4.0, 0.0),
		Vector3(0.0, 1.0, 5.0),
		Vector3(6.0, 1.0, 0.0),
		Vector3(0.0, 3.0, 0.0),
		Vector3(0.0, 1.0, 4.25),
	]
	for point in outside_points:
		_check(
			registry.call("get_room_id_at", point).is_empty(),
			"outside point is unassigned: " + str(point)
		)
	_check(
		(
			registry.call("get_room_at_world_position", Vector3(4.0, 1.0, 3.0)).get("id", "")
			== "corridor_main"
		),
		"world-position lookup returns the room record"
	)

	for first_index in range(ids.size()):
		var first: AABB = registry.call("get_room_by_id", ids[first_index])["bounds"]
		for second_index in range(first_index + 1, ids.size()):
			var second: AABB = registry.call("get_room_by_id", ids[second_index])["bounds"]
			var overlap: Vector3 = Vector3(
				minf(first.end.x, second.end.x) - maxf(first.position.x, second.position.x),
				minf(first.end.y, second.end.y) - maxf(first.position.y, second.position.y),
				minf(first.end.z, second.end.z) - maxf(first.position.z, second.position.z)
			)
			_check(
				not (overlap.x > 0.0 and overlap.y > 0.0 and overlap.z > 0.0),
				"room interiors do not overlap with positive volume"
			)

	var labels: Node3D = scene.get_node("RoomLabels")
	_check(
		labels.labels.size() == ids.size(), "one floor label is created for each registered room"
	)
	for room_id in ids:
		var label: Label3D = labels.get_node_or_null("FloorLabel_" + room_id) as Label3D
		var room: Dictionary = registry.call("get_room_by_id", room_id)
		_check(label != null, "floor label uses the stable ID " + room_id)
		if label != null:
			_check(label.get_meta("room_id", "") == room_id, "floor label stores its room ID")
			_check(label.text == room["display_name"], "floor label text comes from the registry")

	scene.queue_free()
	if failures == 0:
		print("Room registry smoke checks passed.")
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
