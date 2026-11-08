extends Node
## Static logical room records for the first scene.
## Bounds are authored in world X/Y/Z coordinates, independently of meshes/labels.

const ROOM_101_ID: String = "room_101"
const ROOM_102_ID: String = "room_102"
const CORRIDOR_MAIN_ID: String = "corridor_main"

const TYPE_OFFICE: String = "office"
const TYPE_CORRIDOR: String = "corridor"

var _rooms: Dictionary = {}


func _init() -> void:
	_rooms = {
		ROOM_101_ID:
		_make_room(
			ROOM_101_ID,
			"КАБИНЕТ 101",
			TYPE_OFFICE,
			AABB(Vector3(-6.0, 0.0, -4.25), Vector3(6.0, 3.0, 6.0))
		),
		ROOM_102_ID:
		_make_room(
			ROOM_102_ID,
			"КАБИНЕТ 102",
			TYPE_OFFICE,
			AABB(Vector3(0.0, 0.0, -4.25), Vector3(6.0, 3.0, 6.0))
		),
		CORRIDOR_MAIN_ID:
		_make_room(
			CORRIDOR_MAIN_ID,
			"ОБЩИЙ КОРИДОР",
			TYPE_CORRIDOR,
			AABB(Vector3(-6.0, 0.0, 1.75), Vector3(12.0, 3.0, 2.5))
		),
	}


func _make_room(
	room_id: String, display_name: String, room_type: String, bounds: AABB
) -> Dictionary:
	return {
		"id": room_id,
		"display_name": display_name,
		"type": room_type,
		"bounds": bounds,
	}


func get_room_ids() -> PackedStringArray:
	return PackedStringArray([ROOM_101_ID, ROOM_102_ID, CORRIDOR_MAIN_ID])


func get_room_by_id(room_id: String) -> Dictionary:
	var room: Dictionary = _rooms.get(room_id, {})
	return room.duplicate(true)


func get_room_id_at(world_position: Vector3) -> String:
	for room_id: String in get_room_ids():
		var room: Dictionary = _rooms[room_id]
		var bounds: AABB = room["bounds"]
		if _contains_world_point(bounds, world_position):
			return room_id
	return ""


func get_room_at_world_position(world_position: Vector3) -> Dictionary:
	return get_room_by_id(get_room_id_at(world_position))


func _contains_world_point(bounds: AABB, world_position: Vector3) -> bool:
	# Half-open bounds make shared edges deterministic: X=0 belongs to room_102;
	# Z=1.75 belongs to corridor_main. Lower bounds are inclusive, upper exclusive.
	var bounds_end: Vector3 = bounds.end
	return (
		world_position.x >= bounds.position.x
		and world_position.x < bounds_end.x
		and world_position.y >= bounds.position.y
		and world_position.y < bounds_end.y
		and world_position.z >= bounds.position.z
		and world_position.z < bounds_end.z
	)
