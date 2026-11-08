extends Node3D
## Static, understated floor typography for the office plan.

const FLOOR_OFFSET: float = 0.004
const TEXT_COLOR := Color(0.22, 0.28, 0.30, 0.46)
const FONT_SIZE: int = 22
const PIXEL_SIZE: float = 0.009
const LABEL_POSITIONS: Array[Vector3] = [
	Vector3(-3.0, FLOOR_OFFSET, -1.95),
	Vector3(3.0, FLOOR_OFFSET, -1.95),
	Vector3(0.0, FLOOR_OFFSET, 3.15),
]

var labels: Array[Label3D] = []
@onready var room_registry: Node = get_node("../RoomRegistry")


func _ready() -> void:
	var room_ids: PackedStringArray = room_registry.call("get_room_ids")
	assert(
		room_ids.size() == LABEL_POSITIONS.size(),
		"Each registered room needs a floor-label position"
	)
	for index in range(room_ids.size()):
		_add_floor_label(room_ids[index], LABEL_POSITIONS[index])


func _add_floor_label(room_id: String, world_position: Vector3) -> void:
	var room: Dictionary = room_registry.call("get_room_by_id", room_id)
	assert(not room.is_empty(), "Floor label references an unknown room ID: " + room_id)

	var label := Label3D.new()
	label.name = "FloorLabel_" + room_id
	label.set_meta("room_id", room_id)
	label.text = room["display_name"]
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL_SIZE
	label.modulate = TEXT_COLOR
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	label.shaded = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = world_position
	label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	add_child(label)
	labels.append(label)
