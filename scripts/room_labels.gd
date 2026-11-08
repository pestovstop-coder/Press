extends Node3D
## Compact floor-mounted room wayfinding plaques for the first office scene.
## Anchors use the documented plan zones; yaw follows the camera without tilting the plaque.

const PLAQUE_DARK := Color(0.035, 0.075, 0.105, 1.0)
const TYPE_LIGHT := Color(0.9, 0.94, 0.96, 1.0)
const ACCENT_BLUE := Color(0.12, 0.48, 0.86, 1.0)
const FLOOR_OFFSET: float = 0.009
const CAMERA_PATH: NodePath = ^"../CameraRig/Camera3D"

var camera: Camera3D
var plaques: Array[Node3D] = []


func _ready() -> void:
	camera = get_node(CAMERA_PATH) as Camera3D
	_add_plaque("office_101", "КАБИНЕТ", "101", Vector3(-3.0, 0.0, 2.15), 1.1, 0.8)
	_add_plaque("office_102", "КАБИНЕТ", "102", Vector3(3.0, 0.0, 2.15), 1.1, 0.8)
	_add_plaque("corridor_main", "ОБЩИЙ", "КОРИДОР", Vector3(0.0, 0.0, 3.35), 1.9, 0.8)
	update_camera_facing()


func _process(_delta: float) -> void:
	update_camera_facing()


func _add_plaque(
	zone_id: String,
	heading: String,
	name_text: String,
	floor_position: Vector3,
	width: float,
	depth: float
) -> void:
	var plaque := Node3D.new()
	plaque.name = "RoomLabel_" + zone_id
	plaque.set_meta("zone_id", zone_id)
	plaque.position = floor_position
	add_child(plaque)
	plaque.add_to_group("placement_visual")
	plaques.append(plaque)

	var backing := MeshInstance3D.new()
	backing.name = "PlaqueBacking"
	backing.add_to_group("placement_visual")
	var backing_mesh := BoxMesh.new()
	backing_mesh.size = Vector3(width, 0.012, depth)
	backing.mesh = backing_mesh
	backing.position.y = FLOOR_OFFSET + 0.006
	backing.material_override = _unshaded_material(PLAQUE_DARK)
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plaque.add_child(backing)

	var accent := MeshInstance3D.new()
	accent.name = "BlueAccent"
	accent.add_to_group("placement_visual")
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = Vector3(0.035, 0.004, depth - 0.12)
	accent.mesh = accent_mesh
	accent.position = Vector3(-width * 0.5 + 0.075, FLOOR_OFFSET + 0.014, 0.0)
	accent.material_override = _unshaded_material(ACCENT_BLUE)
	accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plaque.add_child(accent)

	var title := _make_text(heading, 20, Vector3(0.0, FLOOR_OFFSET + 0.016, -0.17))
	title.name = "RoomType"
	plaque.add_child(title)
	var room_name := _make_text(name_text, 38, Vector3(0.0, FLOOR_OFFSET + 0.016, 0.19))
	room_name.name = "RoomName"
	plaque.add_child(room_name)


func _make_text(value: String, size: int, position_on_plaque: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = size
	label.pixel_size = 0.009
	label.modulate = TYPE_LIGHT
	label.outline_size = 1
	label.outline_modulate = Color(0.01, 0.02, 0.035, 1.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.shaded = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.rotation.x = -PI * 0.5
	label.position = position_on_plaque
	return label


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.roughness = 0.85
	return material


func update_camera_facing() -> void:
	if not is_instance_valid(camera):
		return
	for plaque in plaques:
		var to_camera: Vector3 = camera.global_position - plaque.global_position
		to_camera.y = 0.0
		if to_camera.length_squared() > 0.000001:
			plaque.rotation.y = atan2(to_camera.x, to_camera.z)
