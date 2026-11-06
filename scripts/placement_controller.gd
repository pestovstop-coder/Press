extends Node3D
## TASK 006: small two-asset editor. No collision/occupancy system or persistence.
const STEP: float = 0.5
const BLOCK_SIZE: Vector3 = Vector3(1.0, 1.0, 1.0)
const GRID_LIFT: float = 0.012
const DESK: PackedScene = preload("res://assets/models/furniture/desks/office_desk.glb")

var active: bool = false
var quarter_turns: int = 0
var valid_target: bool = false
var selected_asset: String = "block"
var grid: MeshInstance3D
var preview: Node3D
var placed: Node3D
var floor_top: float
var floor_bounds: AABB
var editing: Node3D
var original_transform: Transform3D
var editable: Array[Node3D] = []
var ghost_records: Dictionary = {}
var panel: PanelContainer
var status: Label

@onready var floor_mesh: MeshInstance3D = get_node("../TestRoom/Floor")
@onready var camera: Camera3D = get_node("../CameraRig/Camera3D")


func _ready() -> void:
	floor_bounds = floor_mesh.mesh.get_aabb()
	floor_top = floor_bounds.end.y
	_build_grid()
	placed = Node3D.new()
	placed.name = "PlacedObjects"
	add_child(placed)
	var existing: Node3D = get_node("../TestRoom/OfficeDesk")
	_register(existing, "office_desk")
	_build_panel()
	_new_preview()
	set_active(false)


func _process(_delta: float) -> void:
	if active:
		_update_preview(get_viewport().get_mouse_position())


func _input(event: InputEvent) -> void:
	# GUI may swallow a release over the panel. Always end a camera MMB drag,
	# otherwise the unchanged camera's _dragging flag could remain stuck.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
			camera.get_parent()._unhandled_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B:
				set_active(not active)
			KEY_ESCAPE:
				if not active:
					return
				if editing != null:
					cancel_move()
				else:
					set_active(false)
			KEY_R:
				if not active:
					return
				quarter_turns = (quarter_turns + 1) % 4
				preview.rotation.y = quarter_turns * PI / 2.0
				_update_preview(get_viewport().get_mouse_position())
			_:
				return
		get_viewport().set_input_as_handled()
	elif active and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
				click_at(event.position)
			get_viewport().set_input_as_handled()
	# MMB/motion/wheel go to the unchanged camera controller.


func click_at(screen_point: Vector2) -> void:
	if not active or _over_panel(screen_point):
		return
	if editing == null:
		var picked: Node3D = pick_object(screen_point)
		if picked != null:
			begin_move(picked)
			return
	_update_preview(screen_point)
	place_block()


func set_active(enabled: bool) -> void:
	if editing != null:
		cancel_move()
	active = enabled
	grid.visible = enabled
	panel.visible = enabled
	valid_target = false
	preview.visible = false
	if enabled:
		quarter_turns = 0
		preview.rotation.y = 0.0
		_update_preview(get_viewport().get_mouse_position())


func select_asset(asset_id: String) -> void:
	if asset_id not in ["block", "office_desk"]:
		return
	if editing != null:
		cancel_move()
	selected_asset = asset_id
	_discard_preview()
	_new_preview()
	_update_preview(get_viewport().get_mouse_position())


func _new_preview() -> void:
	valid_target = false
	preview = _make_block(false) if selected_asset == "block" else DESK.instantiate()
	preview.name = "PlacementPreview"
	add_child(preview)
	preview.set_meta("asset_id", selected_asset)
	preview.set_meta("bounds", _object_bounds(preview))
	quarter_turns = 0
	_set_ghost(preview)
	preview.visible = false
	status.text = "Блок" if selected_asset == "block" else "Офисный стол"


func _discard_preview() -> void:
	_restore_materials()
	if is_instance_valid(preview):
		preview.visible = false
		preview.queue_free()


func _register(object: Node3D, asset_id: String) -> void:
	object.set_meta("asset_id", asset_id)
	object.set_meta("bounds", _object_bounds(object))
	editable.append(object)


func begin_move(object: Node3D) -> void:
	if not active or editing != null or object not in editable:
		return
	_discard_preview()
	editing = object
	valid_target = false
	preview = object
	original_transform = object.global_transform
	selected_asset = str(object.get_meta("asset_id"))
	quarter_turns = posmod(roundi(object.rotation.y / (PI / 2.0)), 4)
	_set_ghost(object)
	status.text = "Перемещение · Esc — вернуть"


func cancel_move() -> void:
	if editing == null:
		return
	_restore_materials()
	editing.global_transform = original_transform
	editing.visible = true
	editing = null
	preview = null
	_new_preview()
	valid_target = false


func snapped_floor_point(local_hit: Vector3) -> Vector3:
	return Vector3(snappedf(local_hit.x, STEP), floor_top, snappedf(local_hit.z, STEP))


func target_inside_floor(point: Vector3) -> bool:
	# Only a floor-edge check, no furniture/wall collision or occupancy checks.
	var bounds: AABB = preview.get_meta("bounds")
	var rotated: AABB = (
		Transform3D(Basis(Vector3.UP, quarter_turns * PI / 2.0), Vector3.ZERO) * bounds
	)
	return (
		point.x + rotated.position.x >= floor_bounds.position.x
		and point.x + rotated.end.x <= floor_bounds.end.x
		and point.z + rotated.position.z >= floor_bounds.position.z
		and point.z + rotated.end.z <= floor_bounds.end.z
	)


func _update_preview(screen_point: Vector2) -> void:
	valid_target = false
	preview.visible = false
	if not active or _over_panel(screen_point):
		return
	var origin: Vector3 = floor_mesh.to_local(camera.project_ray_origin(screen_point))
	var direction: Vector3 = (
		floor_mesh.global_basis.inverse() * camera.project_ray_normal(screen_point)
	)
	if absf(direction.y) < 0.00001:
		return
	var distance: float = (floor_top - origin.y) / direction.y
	if distance < 0.0:
		return
	var hit: Vector3 = origin + direction * distance
	if (
		hit.x < floor_bounds.position.x
		or hit.x > floor_bounds.end.x
		or hit.z < floor_bounds.position.z
		or hit.z > floor_bounds.end.z
	):
		return
	var point: Vector3 = snapped_floor_point(hit)
	valid_target = target_inside_floor(point)
	preview.visible = valid_target
	var bounds: AABB = preview.get_meta("bounds")
	point.y -= bounds.position.y
	preview.global_position = floor_mesh.to_global(point)


func place_block() -> void:
	# Retain the original public helper name for the smoke test; handles both assets.
	if not active or not valid_target:
		return
	if editing != null:
		_restore_materials()
		editing.visible = true
		editing = null
		preview = null
		_new_preview()
	else:
		var object: Node3D = _make_block(false) if selected_asset == "block" else DESK.instantiate()
		placed.add_child(object)
		object.global_transform = preview.global_transform
		_register(object, selected_asset)


func pick_object(screen_point: Vector2) -> Node3D:
	var origin: Vector3 = camera.project_ray_origin(screen_point)
	var direction: Vector3 = camera.project_ray_normal(screen_point)
	var nearest: float = INF
	var result: Node3D
	for object in editable:
		for mesh in _meshes(object):
			# Ray against each visible mesh AABB, not one solid box around the desk.
			# No physics bodies are created; gaps between legs remain selectable-through.
			var local_origin: Vector3 = mesh.to_local(origin)
			var local_direction: Vector3 = mesh.global_basis.inverse() * direction
			var hit: Variant = mesh.get_aabb().intersects_ray(local_origin, local_direction)
			if hit is Vector3:
				var distance: float = origin.distance_to(mesh.to_global(hit))
				if distance < nearest:
					nearest = distance
					result = object
	return result


func _meshes(object: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if object is MeshInstance3D and object.mesh != null:
		result.append(object)
	for child in object.get_children():
		result.append_array(_meshes(child))
	return result


func _object_bounds(object: Node3D) -> AABB:
	var bounds := AABB()
	var first: bool = true
	for mesh in _meshes(object):
		var relative: Transform3D = object.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = relative * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _set_ghost(object: Node3D) -> void:
	for mesh in _meshes(object):
		var surfaces: Array[Material] = []
		for index in range(mesh.mesh.get_surface_count()):
			surfaces.append(mesh.get_surface_override_material(index))
		ghost_records[mesh] = [mesh.material_override, surfaces, mesh.cast_shadow]
		# Duplicate active materials: never mutate the imported GLB/shared resources.
		var materials: Array[Material] = []
		for index in range(mesh.mesh.get_surface_count()):
			materials.append(mesh.get_active_material(index))
		mesh.material_override = null
		for index in range(materials.size()):
			var material: StandardMaterial3D
			if materials[index] is StandardMaterial3D:
				material = materials[index].duplicate() as StandardMaterial3D
			else:
				material = StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 0.38
			mesh.set_surface_override_material(index, material)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _restore_materials() -> void:
	for mesh: MeshInstance3D in ghost_records:
		var saved: Array = ghost_records[mesh]
		mesh.material_override = saved[0]
		for index in range(saved[1].size()):
			mesh.set_surface_override_material(index, saved[1][index])
		mesh.cast_shadow = saved[2]
	ghost_records.clear()


func _over_panel(point: Vector2) -> bool:
	return panel.visible and panel.get_global_rect().has_point(point)


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(16, 16)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "Расстановка · B — выход"
	column.add_child(title)
	for asset_id in ["block", "office_desk"]:
		var button := Button.new()
		button.text = "Блок 1×1×1 м" if asset_id == "block" else "Офисный стол 1,6×0,8 м"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_asset.bind(asset_id))
		column.add_child(button)
	status = Label.new()
	column.add_child(status)
	var help := Label.new()
	help.text = "ЛКМ: выбрать / поставить\nR: 90° · Esc: отменить / выйти"
	column.add_child(help)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _make_block(ghost: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Preview" if ghost else "Block"
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = BLOCK_SIZE
	body.mesh = box
	body.position.y = BLOCK_SIZE.y * 0.5
	body.material_override = _material(
		Color(0.25, 0.72, 0.85, 0.38) if ghost else Color(0.48, 0.61, 0.68)
	)
	if ghost:
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	# Small top stripe on +Z identifies the front of an otherwise square block.
	var front := MeshInstance3D.new()
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.55, 0.006, 0.09)
	front.mesh = stripe
	front.position = Vector3(0.0, BLOCK_SIZE.y + 0.003, 0.35)
	front.material_override = _material(Color(0.95, 0.66, 0.22, 0.5 if ghost else 1.0))
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(front)
	return root


func _build_grid() -> void:
	var lines := ImmediateMesh.new()
	var material := _material(Color(0.34, 0.43, 0.47, 0.42))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var low: Vector3 = floor_bounds.position
	var high: Vector3 = floor_bounds.end
	var y: float = floor_top + GRID_LIFT
	for i in range(int(ceilf(low.x / STEP)), int(floorf(high.x / STEP)) + 1):
		var x: float = i * STEP
		lines.surface_add_vertex(Vector3(x, y, low.z))
		lines.surface_add_vertex(Vector3(x, y, high.z))
	for i in range(int(ceilf(low.z / STEP)), int(floorf(high.z / STEP)) + 1):
		var z: float = i * STEP
		lines.surface_add_vertex(Vector3(low.x, y, z))
		lines.surface_add_vertex(Vector3(high.x, y, z))
	lines.surface_end()
	grid = MeshInstance3D.new()
	grid.name = "PlacementGrid"
	grid.mesh = lines
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Parent to the floor so mesh bounds, offset and grid share a coordinate system.
	floor_mesh.add_child(grid)
