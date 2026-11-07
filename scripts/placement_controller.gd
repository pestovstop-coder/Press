extends Node3D
## TASK 008: precise picking and Ctrl-repeat, retaining IDLE / PLACING / MOVING.
enum EditorState { IDLE, PLACING, MOVING }

const STEP: float = 0.5
const BLOCK_SIZE: Vector3 = Vector3(1.0, 1.0, 1.0)
const GRID_LIFT: float = 0.012
const DESK: PackedScene = preload("res://assets/models/furniture/desks/office_desk.glb")

var active: bool = false
var quarter_turns: int = 0
var valid_target: bool = false
var state: EditorState = EditorState.IDLE
var selected_asset: String = ""
var grid: MeshInstance3D
var preview: Node3D
var placed: Node3D
var floor_top: float
var floor_bounds: AABB
var editing: Node3D
var original_transform: Transform3D
var editable: Array[Node3D] = []
var room_occluders: Array[MeshInstance3D] = []
var face_cache: Dictionary = {}
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
	for mesh in _meshes(get_node("../TestRoom")):
		if not existing.is_ancestor_of(mesh):
			room_occluders.append(mesh)
	_build_panel()
	set_active(false)


func _process(_delta: float) -> void:
	if active and state != EditorState.IDLE:
		_update_preview(get_viewport().get_mouse_position())


func _input(event: InputEvent) -> void:
	# Preserve legacy MMB release forwarding; the orbit camera also handles
	# its own releases in _input, including RMB releases over the panel.
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
				if state != EditorState.IDLE:
					cancel_operation()
				else:
					set_active(false)
			KEY_R:
				if not active or state == EditorState.IDLE:
					return
				quarter_turns = (quarter_turns + 1) % 4
				preview.rotation.y = quarter_turns * PI / 2.0
				_update_preview(get_viewport().get_mouse_position())
			_:
				return
		get_viewport().set_input_as_handled()
	elif active and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not camera.get_parent().is_navigating():
				click_at(event.position, event.ctrl_pressed)
			get_viewport().set_input_as_handled()
	# RMB/MMB/motion/wheel are navigation, never placement confirmation.


func click_at(screen_point: Vector2, keep_placing: bool = false) -> void:
	if not active or _over_panel(screen_point):
		return
	if state == EditorState.IDLE:
		var picked: Node3D = pick_object(screen_point)
		if picked != null:
			begin_move(picked)
		return
	_update_preview(screen_point)
	place_block(keep_placing)


func set_active(enabled: bool) -> void:
	cancel_operation()
	active = enabled
	grid.visible = enabled
	panel.visible = enabled


func select_asset(asset_id: String) -> void:
	if not active or asset_id not in ["block", "office_desk"]:
		return
	cancel_operation()
	selected_asset = asset_id
	state = EditorState.PLACING
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
	if not active or state != EditorState.IDLE or object not in editable:
		return
	state = EditorState.MOVING
	editing = object
	valid_target = false
	preview = object
	original_transform = object.global_transform
	selected_asset = str(object.get_meta("asset_id"))
	quarter_turns = posmod(roundi(object.rotation.y / (PI / 2.0)), 4)
	_set_ghost(object)
	status.text = "Перемещение · Esc — вернуть"


func cancel_operation() -> void:
	if state == EditorState.MOVING:
		_restore_materials()
		editing.global_transform = original_transform
		editing.visible = true
	elif state == EditorState.PLACING:
		_discard_preview()
	_reset_selection()


func _reset_selection() -> void:
	state = EditorState.IDLE
	preview = null
	editing = null
	selected_asset = ""
	quarter_turns = 0
	valid_target = false
	status.text = "Ничего не выбрано"


func snapped_floor_point(local_hit: Vector3) -> Vector3:
	return Vector3(snappedf(local_hit.x, STEP), floor_top, snappedf(local_hit.z, STEP))


func target_inside_floor(point: Vector3) -> bool:
	# Only a floor-edge check, no furniture/wall collision or occupancy checks.
	if preview == null:
		return false
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
	if preview == null:
		return
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


func place_block(keep_placing: bool = false) -> void:
	# Retain the original public helper name for the smoke test; handles both assets.
	if not active or state == EditorState.IDLE or not valid_target:
		return
	if state == EditorState.MOVING:
		_restore_materials()
		editing.visible = true
	else:
		var object: Node3D = _make_block(false) if selected_asset == "block" else DESK.instantiate()
		placed.add_child(object)
		object.global_transform = preview.global_transform
		_register(object, selected_asset)
		if keep_placing:
			# Keep only the independent ghost, not the new furniture, active.
			# Its model, position and quarter-turn remain unchanged.
			return
		_discard_preview()
	_reset_selection()


func pick_object(screen_point: Vector2) -> Node3D:
	return _pick_ray(
		camera.project_ray_origin(screen_point), camera.project_ray_normal(screen_point)
	)


func _pick_ray(origin: Vector3, direction: Vector3) -> Node3D:
	var nearest: float = INF
	var result: Node3D
	# No physics bodies/layers/masks exist in this editor. Static room meshes
	# occlude this visual ray without introducing placement collisions.
	for mesh in room_occluders:
		nearest = minf(nearest, _mesh_ray_distance(mesh, origin, direction))
	for object in editable:
		for mesh in _meshes(object):
			var distance: float = _mesh_ray_distance(mesh, origin, direction)
			if distance < nearest:
				nearest = distance
				result = object
	return result


func _mesh_ray_distance(mesh: MeshInstance3D, origin: Vector3, direction: Vector3) -> float:
	if not mesh.is_visible_in_tree() or mesh.mesh == null:
		return INF
	if not face_cache.has(mesh.mesh):
		face_cache[mesh.mesh] = mesh.mesh.get_faces()
	var faces: PackedVector3Array = face_cache[mesh.mesh]
	var local_origin: Vector3 = mesh.to_local(origin)
	var local_direction: Vector3 = mesh.global_basis.inverse() * direction
	var nearest: float = INF
	for index in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(
			local_origin, local_direction, faces[index], faces[index + 1], faces[index + 2]
		)
		# Explicitly accept either winding, including a view from above/below.
		if hit == null:
			hit = Geometry3D.ray_intersects_triangle(
				local_origin, local_direction, faces[index + 2], faces[index + 1], faces[index]
			)
		if hit is Vector3:
			nearest = minf(nearest, origin.distance_to(mesh.to_global(hit)))
	return nearest


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
	# Input positions are viewport coordinates; Control rects are local.
	# Include CanvasLayer transforms rather than comparing unlike coordinate spaces.
	var local_point: Vector2 = panel.get_global_transform_with_canvas().affine_inverse() * point
	return panel.visible and Rect2(Vector2.ZERO, panel.size).has_point(local_point)


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.position = Vector2(16, 16)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(column)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "Расстановка · B — выход"
	column.add_child(title)
	for asset_id in ["block", "office_desk"]:
		var button := Button.new()
		button.text = "Блок 1×1×1 м" if asset_id == "block" else "Офисный стол 1,6×0,8 м"
		# Native Button owns both text and hit-test: no separately offset label/rect.
		button.custom_minimum_size = Vector2(260, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_asset.bind(asset_id))
		column.add_child(button)
	status = Label.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status)
	var help := Label.new()
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.text = "ЛКМ: выбрать / поставить\nCtrl+ЛКМ: поставить ещё\nR: 90° · Esc: отменить / выйти"
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
