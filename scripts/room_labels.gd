extends Node3D
## Static, understated floor typography for the office plan.

const FLOOR_OFFSET: float = 0.004
const TEXT_COLOR := Color(0.22, 0.28, 0.30, 0.46)
const FONT_SIZE: int = 22
const PIXEL_SIZE: float = 0.009

var labels: Array[Label3D] = []


func _ready() -> void:
	_add_floor_label("office_101", "КАБИНЕТ 101", Vector3(-3.0, FLOOR_OFFSET, -1.95))
	_add_floor_label("office_102", "КАБИНЕТ 102", Vector3(3.0, FLOOR_OFFSET, -1.95))
	_add_floor_label("corridor_main", "ОБЩИЙ КОРИДОР", Vector3(0.0, FLOOR_OFFSET, 3.15))


func _add_floor_label(zone_id: String, value: String, world_position: Vector3) -> void:
	var label := Label3D.new()
	label.name = "FloorLabel_" + zone_id
	label.set_meta("zone_id", zone_id)
	label.text = value
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
