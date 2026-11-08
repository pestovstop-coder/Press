extends Node3D
## TASK 016: cell-based furniture placement, retaining IDLE / PLACING / MOVING.
enum EditorState { IDLE, PLACING, MOVING }

const CELL_SIZE: float = 0.25
# The editor's 0.5m reference lines denote two-by-two placement cells; they are
# visual plan modules, not the furniture placement increment.
const EDITOR_GRID_STEP: float = CELL_SIZE * 2.0
const GRID_LIFT: float = 0.012
const COLLISION_EPSILON: float = 0.00001
const SURFACE_SNAP_DISTANCE: float = CELL_SIZE
const PLACEMENT_VISUAL_GROUP: StringName = &"placement_visual"
const FOOTPRINT_CELLS: Dictionary = {
	"block": Vector2i(4, 4),
	# 2m × 1m cells contain the 1.6m × 0.8m legacy desk without moving it.
	"office_desk": Vector2i(8, 4),
	# Existing plan reserves 1.6m × 1.4m per workplace; round the full-kit envelope up to cells.
	"employee_workstation": Vector2i(7, 6),
}
const BLOCK_SIZE: Vector3 = Vector3(1.0, 1.0, 1.0)
const DESK: PackedScene = preload("res://assets/models/furniture/desks/office_desk.glb")
const EMPLOYEE_WORKSTATION: PackedScene = preload(
	"res://assets/models/furniture/desks/employee_workstation.glb"
)
var active: bool = false
var quarter_turns: int = 0
var valid_target: bool = false
var placement_diagnostic: String = "IDLE"
var state: EditorState = EditorState.IDLE
var selected_asset: String = ""
var grid: MeshInstance3D
var front_marker: MeshInstance3D
var preview: Node3D
var placed: Node3D
var floor_top: float
var floor_bounds: AABB
var editing: Node3D
var original_transform: Transform3D
var current_footprint_origin: Vector2i = Vector2i.ZERO
var current_footprint_size: Vector2i = Vector2i.ZERO
var current_visual_center: Vector2 = Vector2.ZERO
var last_marker_state: Array = []
var marker_material: StandardMaterial3D
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
	# The visual grid is parented under Floor; render-only overlays aren't obstacles.
	for mesh in _meshes(get_node("../TestRoom")):
		if not existing.is_ancestor_of(mesh) and not mesh.is_in_group(PLACEMENT_VISUAL_GROUP):
			room_occluders.append(mesh)
	_build_panel()
	set_active(false)


func _process(_delta: float) -> void:
	if active and state != EditorState.IDLE:
		var mouse_position: Vector2 = get_viewport().get_mouse_position()
		# Keep the last world-space target while the pointer is over the catalogue.
		if not _over_panel(mouse_position):
			_update_preview(mouse_position)


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
	if not active or asset_id not in ["block", "office_desk", "employee_workstation"]:
		return
	cancel_operation()
	selected_asset = asset_id
	state = EditorState.PLACING
	_new_preview()
	# Start on a real free floor footprint; the next world-space mouse update
	# takes over, while hovering the catalogue preserves this valid preview.
	_initialize_first_valid_preview()


func _instantiate_asset(asset_id: String) -> Node3D:
	match asset_id:
		"block":
			return _make_block(false)
		"office_desk":
			return DESK.instantiate()
		"employee_workstation":
			return EMPLOYEE_WORKSTATION.instantiate()
	return null


func _new_preview() -> void:
	valid_target = false
	preview = _instantiate_asset(selected_asset)
	if preview == null:
		return
	preview.name = "PlacementPreview"
	add_child(preview)
	preview.set_meta("asset_id", selected_asset)
	var bounds: AABB = _object_bounds(preview)
	preview.set_meta("bounds", bounds)
	quarter_turns = 0
	_set_ghost(preview)
	preview.visible = false
	_create_footprint_marker()
	match selected_asset:
		"block":
			status.text = "Блок"
		"office_desk":
			status.text = "Офисный стол"
		"employee_workstation":
			status.text = "Рабочее место сотрудника"


func _discard_preview() -> void:
	_restore_materials()
	if is_instance_valid(preview):
		preview.visible = false
		preview.queue_free()
	_hide_front_marker()


func _register(
	object: Node3D, asset_id: String, footprint_origin: Variant = null, turns: int = -1
) -> void:
	var bounds: AABB = _object_bounds(object)
	var object_turns: int = turns
	if object_turns < 0:
		object_turns = posmod(roundi(object.rotation.y / (PI / 2.0)), 4)
	var cells: Vector2i = _footprint_cells_for_asset(asset_id, object_turns)
	var bounds_in_floor: AABB = _object_bounds_in_floor(object, bounds)
	var origin: Vector2i
	if typeof(footprint_origin) == TYPE_VECTOR2I:
		origin = footprint_origin
	else:
		origin = _origin_covering_bounds(bounds_in_floor, cells)
	object.set_meta("asset_id", asset_id)
	object.set_meta("bounds", bounds)
	object.set_meta("footprint_cells", cells)
	object.set_meta("footprint_origin_cells", origin)
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
	current_footprint_origin = object.get_meta("footprint_origin_cells")
	current_footprint_size = _footprint_cells_for_asset(selected_asset, quarter_turns)
	var bounds_center: Vector3 = (
		_object_bounds_in_floor(object, object.get_meta("bounds")).get_center()
	)
	current_visual_center = Vector2(bounds_center.x, bounds_center.z)
	_create_footprint_marker()
	_set_placement_diagnostic("INVALID_COORDINATES")


func cancel_operation() -> void:
	if state == EditorState.MOVING:
		_restore_materials()
		editing.global_transform = original_transform
		editing.visible = true
	elif state == EditorState.PLACING:
		_discard_preview()
	_reset_selection()


func _reset_selection() -> void:
	_hide_front_marker()
	state = EditorState.IDLE
	preview = null
	editing = null
	selected_asset = ""
	quarter_turns = 0
	current_footprint_origin = Vector2i.ZERO
	current_footprint_size = Vector2i.ZERO
	current_visual_center = Vector2.ZERO
	last_marker_state.clear()
	valid_target = false
	placement_diagnostic = "IDLE"
	status.text = "Ничего не выбрано"


func _round_cell_index(value: float) -> int:
	# Halfway values consistently round toward +infinity, including negatives.
	return floori(value + 0.5)


func _footprint_cells_for_asset(asset_id: String, turns: int = 0) -> Vector2i:
	var cells: Vector2i = FOOTPRINT_CELLS.get(asset_id, Vector2i.ZERO)
	return Vector2i(cells.y, cells.x) if posmod(turns, 2) == 1 else cells


func _footprint_origin_for_center(center: Vector2, cells: Vector2i) -> Vector2i:
	var half_span := Vector2(cells.x * 0.5, cells.y * 0.5)
	return Vector2i(
		_round_cell_index(center.x / CELL_SIZE - half_span.x),
		_round_cell_index(center.y / CELL_SIZE - half_span.y)
	)


func _footprint_center(origin: Vector2i, cells: Vector2i) -> Vector2:
	return Vector2((origin.x + cells.x * 0.5) * CELL_SIZE, (origin.y + cells.y * 0.5) * CELL_SIZE)


func _footprint_rect(origin: Vector2i, cells: Vector2i) -> Rect2:
	return Rect2(
		Vector2(origin.x * CELL_SIZE, origin.y * CELL_SIZE),
		Vector2(cells.x * CELL_SIZE, cells.y * CELL_SIZE)
	)


func _footprints_overlap(
	first_origin: Vector2i, first_size: Vector2i, second_origin: Vector2i, second_size: Vector2i
) -> bool:
	return (
		first_origin.x < second_origin.x + second_size.x
		and first_origin.x + first_size.x > second_origin.x
		and first_origin.y < second_origin.y + second_size.y
		and first_origin.y + first_size.y > second_origin.y
	)


func _origin_covering_bounds(bounds: AABB, cells: Vector2i) -> Vector2i:
	# Existing hand-placed furniture is registered without being moved. Cell
	# boundaries are integer multiples of CELL_SIZE; include every cell touched
	# by the complete visual AABB.
	var epsilon: float = 0.00001
	var min_x: int = floori(bounds.position.x / CELL_SIZE + epsilon)
	var min_z: int = floori(bounds.position.z / CELL_SIZE + epsilon)
	var max_x: int = ceili(bounds.end.x / CELL_SIZE - epsilon) - 1
	var max_z: int = ceili(bounds.end.z / CELL_SIZE - epsilon) - 1
	if max_x - min_x + 1 > cells.x or max_z - min_z + 1 > cells.y:
		return _footprint_origin_for_center(
			Vector2(
				bounds.position.x + bounds.size.x * 0.5, bounds.position.z + bounds.size.z * 0.5
			),
			cells
		)
	return Vector2i(min_x, min_z)


func _object_bounds_in_floor(object: Node3D, bounds: AABB) -> AABB:
	var object_to_floor: Transform3D = (
		floor_mesh.global_transform.affine_inverse() * object.global_transform
	)
	return object_to_floor * bounds


func _obstacle_bounds_in_floor(mesh: MeshInstance3D) -> AABB:
	# Camera cutaway changes wall meshes for presentation only. Use their authored
	# boxes for placement so a shortened visual wall never becomes passable.
	var wall_visibility: Node = get_node_or_null("../WallVisibility")
	if wall_visibility != null:
		var originals: Dictionary = wall_visibility.get("originals")
		if originals.has(mesh):
			var original: Dictionary = originals[mesh]
			var size: Vector3 = original["size"]
			var center: Vector3 = original["position"]
			var local_box := AABB(center - size * 0.5, size)
			var parent: Node3D = mesh.get_parent() as Node3D
			var parent_to_floor: Transform3D = (
				floor_mesh.global_transform.affine_inverse() * parent.global_transform
			)
			return parent_to_floor * local_box
	var mesh_to_floor: Transform3D = (
		floor_mesh.global_transform.affine_inverse() * mesh.global_transform
	)
	return mesh_to_floor * mesh.get_aabb()


func _object_mesh_bounds_for_transform(
	object: Node3D, root_transform_in_floor: Transform3D
) -> Array[AABB]:
	var result: Array[AABB] = []
	var root_inverse: Transform3D = object.global_transform.affine_inverse()
	for mesh in _meshes(object):
		var mesh_to_root: Transform3D = root_inverse * mesh.global_transform
		var mesh_bounds_in_root: AABB = mesh_to_root * mesh.get_aabb()
		result.append(root_transform_in_floor * mesh_bounds_in_root)
	return result


func _object_mesh_bounds_in_floor(object: Node3D) -> Array[AABB]:
	var root_to_floor: Transform3D = (
		floor_mesh.global_transform.affine_inverse() * object.global_transform
	)
	return _object_mesh_bounds_for_transform(object, root_to_floor)


func _mesh_bounds_overlap_any(first: Array[AABB], second: Array[AABB]) -> bool:
	for first_bounds in first:
		for second_bounds in second:
			if _aabbs_overlap(first_bounds, second_bounds):
				return true
	return false


func _aabbs_overlap(first: AABB, second: AABB) -> bool:
	# No clearance margin: exact face contact is allowed. Epsilon only absorbs
	# floating-point noise; positive-volume overlap still blocks placement.
	return (
		first.position.x < second.end.x - COLLISION_EPSILON
		and first.end.x > second.position.x + COLLISION_EPSILON
		and first.position.y < second.end.y - COLLISION_EPSILON
		and first.end.y > second.position.y + COLLISION_EPSILON
		and first.position.z < second.end.z - COLLISION_EPSILON
		and first.end.z > second.position.z + COLLISION_EPSILON
	)


func _bounds_inside_floor(bounds: AABB) -> bool:
	return (
		bounds.position.x >= floor_bounds.position.x - COLLISION_EPSILON
		and bounds.end.x <= floor_bounds.end.x + COLLISION_EPSILON
		and bounds.position.z >= floor_bounds.position.z - COLLISION_EPSILON
		and bounds.end.z <= floor_bounds.end.z + COLLISION_EPSILON
	)


func _candidate_invalid_reason(
	cells: Vector2i, visual_bounds: AABB, mesh_bounds: Array[AABB]
) -> String:
	var reason: String = ""
	if cells.x <= 0 or cells.y <= 0:
		reason = "INVALID_FOOTPRINT"
	elif not visual_bounds.position.is_finite() or not visual_bounds.size.is_finite():
		reason = "INVALID_COORDINATES"
	# The cell footprint is a planning envelope/marker, not a physical collider.
	# Actual GLB mesh bounds determine floor clearance and collision.
	elif not _bounds_inside_floor(visual_bounds):
		reason = "OUT_OF_BOUNDS"
	elif mesh_bounds.is_empty():
		reason = "INVALID_COORDINATES"
	if reason.is_empty():
		for object in editable:
			if object == editing:
				continue
			if not object.has_meta("bounds"):
				reason = "INVALID_FOOTPRINT"
				break
			var other_mesh_bounds: Array[AABB] = _object_mesh_bounds_in_floor(object)
			if _mesh_bounds_overlap_any(mesh_bounds, other_mesh_bounds):
				reason = "FURNITURE_COLLISION"
				break
	if reason.is_empty():
		for mesh in room_occluders:
			if mesh == floor_mesh:
				continue
			var obstacle: AABB = _obstacle_bounds_in_floor(mesh)
			for candidate_bounds in mesh_bounds:
				if _aabbs_overlap(candidate_bounds, obstacle):
					reason = (
						"WALL_COLLISION" if mesh.has_meta("cutaway_side") else "OBSTACLE_COLLISION"
					)
					break
			if not reason.is_empty():
				break
	return "VALID" if reason.is_empty() else reason


func _set_placement_diagnostic(reason: String) -> void:
	placement_diagnostic = reason
	if status == null:
		return
	if state == EditorState.MOVING:
		status.text = "Перемещение · " + reason + " · Esc — вернуть"
	elif state == EditorState.PLACING:
		var asset_name: String = selected_asset
		match selected_asset:
			"block":
				asset_name = "Блок"
			"office_desk":
				asset_name = "Офисный стол"
			"employee_workstation":
				asset_name = "Рабочее место сотрудника"
		status.text = asset_name + " · " + reason


func _intervals_near(
	first_min: float, first_max: float, second_min: float, second_max: float, margin: float
) -> bool:
	return first_min <= second_max + margin and second_min <= first_max + margin


func _aabb_contact_axes(first: AABB, second: AABB) -> int:
	var touches_x: bool = (
		(
			absf(first.end.x - second.position.x) <= COLLISION_EPSILON
			or absf(first.position.x - second.end.x) <= COLLISION_EPSILON
		)
		and _intervals_overlap_positive(
			first.position.y, first.end.y, second.position.y, second.end.y
		)
		and _intervals_overlap_positive(
			first.position.z, first.end.z, second.position.z, second.end.z
		)
	)
	var touches_z: bool = (
		(
			absf(first.end.z - second.position.z) <= COLLISION_EPSILON
			or absf(first.position.z - second.end.z) <= COLLISION_EPSILON
		)
		and _intervals_overlap_positive(
			first.position.y, first.end.y, second.position.y, second.end.y
		)
		and _intervals_overlap_positive(
			first.position.x, first.end.x, second.position.x, second.end.x
		)
	)
	return (1 if touches_x else 0) | (2 if touches_z else 0)


func _surface_contact_axes(candidate_bounds: Array[AABB]) -> int:
	var axes: int = 0
	for candidate in candidate_bounds:
		for mesh in room_occluders:
			if mesh != floor_mesh:
				axes |= _aabb_contact_axes(candidate, _obstacle_bounds_in_floor(mesh))
	for object in editable:
		if object == editing:
			continue
		for candidate in candidate_bounds:
			for other in _object_mesh_bounds_in_floor(object):
				axes |= _aabb_contact_axes(candidate, other)
	return int((axes & 1) != 0) + int((axes & 2) != 0)


func _append_snap_target(targets: Array[float], target: float, base: float) -> void:
	if absf(target - base) > SURFACE_SNAP_DISTANCE + COLLISION_EPSILON:
		return
	for existing in targets:
		if absf(existing - target) <= COLLISION_EPSILON:
			return
	targets.append(target)


func _surface_snap_center(
	bounds: AABB, cells: Vector2i, turns: int, base_center: Vector2
) -> Vector2:
	var orientation := Basis(Vector3.UP, turns * PI / 2.0)
	var rotated_bounds: AABB = Transform3D(orientation, Vector3.ZERO) * bounds
	var half_x: float = rotated_bounds.size.x * 0.5
	var half_z: float = rotated_bounds.size.z * 0.5
	var base_bounds := AABB(
		Vector3(base_center.x - half_x, floor_top, base_center.y - half_z),
		Vector3(rotated_bounds.size.x, rotated_bounds.size.y, rotated_bounds.size.z)
	)
	var x_targets: Array[float] = [base_center.x]
	var z_targets: Array[float] = [base_center.y]
	for mesh in room_occluders:
		if mesh == floor_mesh:
			continue
		var obstacle: AABB = _obstacle_bounds_in_floor(mesh)
		if not _intervals_near(
			base_bounds.position.y,
			base_bounds.end.y,
			obstacle.position.y,
			obstacle.end.y,
			COLLISION_EPSILON
		):
			continue
		if _intervals_near(
			base_bounds.position.z,
			base_bounds.end.z,
			obstacle.position.z,
			obstacle.end.z,
			SURFACE_SNAP_DISTANCE
		):
			_append_snap_target(x_targets, obstacle.position.x - half_x, base_center.x)
			_append_snap_target(x_targets, obstacle.end.x + half_x, base_center.x)
		if _intervals_near(
			base_bounds.position.x,
			base_bounds.end.x,
			obstacle.position.x,
			obstacle.end.x,
			SURFACE_SNAP_DISTANCE
		):
			_append_snap_target(z_targets, obstacle.position.z - half_z, base_center.y)
			_append_snap_target(z_targets, obstacle.end.z + half_z, base_center.y)
	for object in editable:
		if object == editing:
			continue
		var other_bounds: AABB = _object_bounds_in_floor(object, object.get_meta("bounds"))
		if not _intervals_near(
			base_bounds.position.y,
			base_bounds.end.y,
			other_bounds.position.y,
			other_bounds.end.y,
			COLLISION_EPSILON
		):
			continue
		if _intervals_near(
			base_bounds.position.z,
			base_bounds.end.z,
			other_bounds.position.z,
			other_bounds.end.z,
			SURFACE_SNAP_DISTANCE
		):
			_append_snap_target(x_targets, other_bounds.position.x - half_x, base_center.x)
			_append_snap_target(x_targets, other_bounds.end.x + half_x, base_center.x)
		if _intervals_near(
			base_bounds.position.x,
			base_bounds.end.x,
			other_bounds.position.x,
			other_bounds.end.x,
			SURFACE_SNAP_DISTANCE
		):
			_append_snap_target(z_targets, other_bounds.position.z - half_z, base_center.y)
			_append_snap_target(z_targets, other_bounds.end.z + half_z, base_center.y)

	var found: bool = false
	var best_center: Vector2 = base_center
	var best_contact_axes: int = 0
	var best_distance: float = INF
	for x in x_targets:
		for z in z_targets:
			var candidate_center := Vector2(x, z)
			var offset: Vector2 = candidate_center - base_center
			if offset.length_squared() <= COLLISION_EPSILON * COLLISION_EPSILON:
				continue
			if offset.length_squared() > SURFACE_SNAP_DISTANCE * SURFACE_SNAP_DISTANCE:
				continue
			var origin: Vector2i = _footprint_origin_for_center(candidate_center, cells)
			var transform: Transform3D = _preview_transform_for_footprint(
				bounds, origin, cells, turns, candidate_center
			)
			var candidate_mesh_bounds: Array[AABB] = _object_mesh_bounds_for_transform(
				preview, transform
			)
			if (
				_candidate_invalid_reason(cells, transform * bounds, candidate_mesh_bounds)
				!= "VALID"
			):
				continue
			var contact_axes: int = _surface_contact_axes(candidate_mesh_bounds)
			if contact_axes == 0:
				continue
			var distance: float = offset.length_squared()
			if (
				contact_axes > best_contact_axes
				or (contact_axes == best_contact_axes and distance < best_distance)
			):
				found = true
				best_center = candidate_center
				best_contact_axes = contact_axes
				best_distance = distance
	return best_center if found else base_center


func _find_nearest_valid_origin(cells: Vector2i, bounds: AABB, turns: int) -> Variant:
	if cells.x <= 0 or cells.y <= 0:
		return null
	var orientation := Basis(Vector3.UP, turns * PI / 2.0)
	var rotated_bounds: AABB = Transform3D(orientation, Vector3.ZERO) * bounds
	var min_x: int = ceili(
		(
			(floor_bounds.position.x + rotated_bounds.size.x * 0.5) / CELL_SIZE
			- cells.x * 0.5
			- COLLISION_EPSILON
		)
	)
	var min_z: int = ceili(
		(
			(floor_bounds.position.z + rotated_bounds.size.z * 0.5) / CELL_SIZE
			- cells.y * 0.5
			- COLLISION_EPSILON
		)
	)
	var max_x: int = floori(
		(
			(floor_bounds.end.x - rotated_bounds.size.x * 0.5) / CELL_SIZE
			- cells.x * 0.5
			+ COLLISION_EPSILON
		)
	)
	var max_z: int = floori(
		(
			(floor_bounds.end.z - rotated_bounds.size.z * 0.5) / CELL_SIZE
			- cells.y * 0.5
			+ COLLISION_EPSILON
		)
	)
	var found: bool = false
	var best_origin: Vector2i = Vector2i.ZERO
	var best_distance: float = INF
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var origin := Vector2i(x, z)
			var local_transform: Transform3D = _preview_transform_for_footprint(
				bounds, origin, cells, turns
			)
			var visual_bounds: AABB = local_transform * bounds
			var candidate_mesh_bounds: Array[AABB] = _object_mesh_bounds_for_transform(
				preview, local_transform
			)
			if _candidate_invalid_reason(cells, visual_bounds, candidate_mesh_bounds) != "VALID":
				continue
			var distance: float = _footprint_center(origin, cells).length_squared()
			if distance < best_distance:
				found = true
				best_origin = origin
				best_distance = distance
	return best_origin if found else null


func _apply_preview_at_origin(
	origin: Vector2i, cells: Vector2i, visual_center: Variant = null
) -> void:
	current_footprint_origin = origin
	current_footprint_size = cells
	if typeof(visual_center) == TYPE_VECTOR2:
		current_visual_center = visual_center
	else:
		current_visual_center = _footprint_center(origin, cells)
	var bounds: AABB = preview.get_meta("bounds")
	var local_transform: Transform3D = _preview_transform_for_footprint(
		bounds,
		current_footprint_origin,
		current_footprint_size,
		quarter_turns,
		current_visual_center
	)
	preview.global_transform = floor_mesh.global_transform * local_transform
	preview.visible = true
	var visual_bounds: AABB = local_transform * bounds
	var mesh_bounds: Array[AABB] = _object_mesh_bounds_for_transform(preview, local_transform)
	placement_diagnostic = _candidate_invalid_reason(
		current_footprint_size, visual_bounds, mesh_bounds
	)
	valid_target = placement_diagnostic == "VALID"
	_set_placement_diagnostic(placement_diagnostic)
	if is_instance_valid(front_marker):
		_update_footprint_marker(current_footprint_origin, current_footprint_size, valid_target)


func _initialize_first_valid_preview() -> void:
	var cells: Vector2i = _footprint_cells_for_asset(selected_asset, quarter_turns)
	var bounds: AABB = preview.get_meta("bounds")
	var origin: Variant = _find_nearest_valid_origin(cells, bounds, quarter_turns)
	if typeof(origin) != TYPE_VECTOR2I:
		valid_target = false
		preview.visible = false
		_set_placement_diagnostic("NO_VALID_PLACEMENT")
		return
	_apply_preview_at_origin(origin, cells)


func snapped_floor_point(local_hit: Vector3) -> Vector3:
	return Vector3(
		_round_cell_index(local_hit.x / CELL_SIZE) * CELL_SIZE,
		floor_top,
		_round_cell_index(local_hit.z / CELL_SIZE) * CELL_SIZE
	)


func target_inside_floor(point: Vector3) -> bool:
	if preview == null:
		return false
	var cells: Vector2i = _footprint_cells_for_asset(selected_asset, quarter_turns)
	var center := Vector2(point.x, point.z)
	var origin: Vector2i = _footprint_origin_for_center(center, cells)
	var transform: Transform3D = _preview_transform_for_footprint(
		preview.get_meta("bounds"), origin, cells, quarter_turns, center
	)
	return _bounds_inside_floor(transform * preview.get_meta("bounds"))


func _preview_transform_for_footprint(
	bounds: AABB, origin: Vector2i, cells: Vector2i, turns: int, visual_center: Variant = null
) -> Transform3D:
	var orientation := Basis(Vector3.UP, turns * PI / 2.0)
	var rotated_bounds: AABB = Transform3D(orientation, Vector3.ZERO) * bounds
	var center: Vector2 = _footprint_center(origin, cells)
	if typeof(visual_center) == TYPE_VECTOR2:
		center = visual_center
	var root_position := Vector3(
		center.x - rotated_bounds.get_center().x,
		floor_top - rotated_bounds.position.y,
		center.y - rotated_bounds.get_center().z
	)
	return Transform3D(orientation, root_position)


func _update_preview(screen_point: Vector2) -> void:
	if preview == null:
		return
	if not active:
		valid_target = false
		preview.visible = false
		_set_placement_diagnostic("INVALID_COORDINATES")
		return
	# The catalogue click is not a world-space placement request. Preserve the
	# last candidate until the pointer returns to the room instead of rejecting it.
	if _over_panel(screen_point):
		if current_footprint_size.x > 0 and current_footprint_size.y > 0:
			var anchor: Vector2 = current_visual_center
			var rotated_cells: Vector2i = _footprint_cells_for_asset(selected_asset, quarter_turns)
			_apply_preview_at_origin(
				_footprint_origin_for_center(anchor, rotated_cells), rotated_cells, anchor
			)
		return
	valid_target = false
	preview.visible = false
	if is_instance_valid(front_marker):
		front_marker.visible = false
	_set_placement_diagnostic("INVALID_COORDINATES")
	var ray_origin: Vector3 = floor_mesh.to_local(camera.project_ray_origin(screen_point))
	var direction: Vector3 = (
		floor_mesh.global_basis.inverse() * camera.project_ray_normal(screen_point)
	)
	if not ray_origin.is_finite() or not direction.is_finite() or absf(direction.y) < 0.00001:
		return
	var distance: float = (floor_top - ray_origin.y) / direction.y
	if distance < 0.0:
		return
	var hit: Vector3 = ray_origin + direction * distance
	if not hit.is_finite():
		return
	var cells: Vector2i = _footprint_cells_for_asset(selected_asset, quarter_turns)
	var origin: Vector2i = _footprint_origin_for_center(Vector2(hit.x, hit.z), cells)
	var base_center: Vector2 = _footprint_center(origin, cells)
	var bounds: AABB = preview.get_meta("bounds")
	var visual_center: Vector2 = _surface_snap_center(bounds, cells, quarter_turns, base_center)
	origin = _footprint_origin_for_center(visual_center, cells)
	_apply_preview_at_origin(origin, cells, visual_center)


func place_block(keep_placing: bool = false) -> void:
	# Retain the original public helper name for the smoke test; handles both assets.
	if not active or state == EditorState.IDLE or not valid_target:
		return
	if state == EditorState.MOVING:
		_restore_materials()
		editing.set_meta("footprint_origin_cells", current_footprint_origin)
		editing.set_meta("footprint_cells", current_footprint_size)
		editing.visible = true
	else:
		var object: Node3D = _instantiate_asset(selected_asset)
		if object == null:
			return
		placed.add_child(object)
		object.global_transform = preview.global_transform
		_register(object, selected_asset, current_footprint_origin, quarter_turns)
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
	# occlude this visual ray; placement uses separate cell/AABB checks.
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


func _create_footprint_marker() -> void:
	_hide_front_marker()
	if selected_asset not in FOOTPRINT_CELLS:
		return
	marker_material = _material(Color(0.12, 0.92, 0.38, 1.0))
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	front_marker = MeshInstance3D.new()
	front_marker.name = "PlacementFootprintMarker"
	front_marker.add_to_group(PLACEMENT_VISUAL_GROUP)
	front_marker.mesh = ImmediateMesh.new()
	front_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	front_marker.visible = false
	floor_mesh.add_child(front_marker)
	last_marker_state.clear()


func _update_footprint_marker(origin: Vector2i, cells: Vector2i, allowed: bool) -> void:
	front_marker.set_meta("footprint_origin_cells", origin)
	front_marker.set_meta("footprint_cells", cells)
	front_marker.set_meta("allowed", allowed)
	var state_key: Array = [origin, cells, quarter_turns, allowed]
	if state_key == last_marker_state:
		front_marker.visible = true
		return
	last_marker_state = state_key
	marker_material.albedo_color = (
		Color(0.12, 0.92, 0.38, 1.0) if allowed else Color(1.0, 0.18, 0.14, 1.0)
	)
	var mesh: ImmediateMesh = front_marker.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, marker_material)
	var low_x: float = origin.x * CELL_SIZE
	var low_z: float = origin.y * CELL_SIZE
	var high_x: float = low_x + cells.x * CELL_SIZE
	var high_z: float = low_z + cells.y * CELL_SIZE
	var marker_y: float = floor_top + GRID_LIFT + 0.004
	# Every quarter-meter occupied cell is shown; the 0.5m room lines remain
	# only a separate two-cell plan-module reference.
	for column in range(cells.x + 1):
		var x: float = low_x + column * CELL_SIZE
		mesh.surface_add_vertex(Vector3(x, marker_y, low_z))
		mesh.surface_add_vertex(Vector3(x, marker_y, high_z))
	for row in range(cells.y + 1):
		var z: float = low_z + row * CELL_SIZE
		mesh.surface_add_vertex(Vector3(low_x, marker_y, z))
		mesh.surface_add_vertex(Vector3(high_x, marker_y, z))
	var direction: Vector2
	var arrow_count: int
	match posmod(quarter_turns, 4):
		0:
			direction = Vector2(0, 1)
			arrow_count = cells.x
			for i in range(arrow_count):
				_draw_front_arrow(
					mesh,
					Vector2(
						(origin.x + i + 0.5) * CELL_SIZE, (origin.y + cells.y - 0.5) * CELL_SIZE
					),
					direction,
					marker_y
				)
		1:
			direction = Vector2(1, 0)
			arrow_count = cells.y
			for i in range(arrow_count):
				_draw_front_arrow(
					mesh,
					Vector2(
						(origin.x + cells.x - 0.5) * CELL_SIZE, (origin.y + i + 0.5) * CELL_SIZE
					),
					direction,
					marker_y
				)
		2:
			direction = Vector2(0, -1)
			arrow_count = cells.x
			for i in range(arrow_count):
				_draw_front_arrow(
					mesh,
					Vector2((origin.x + i + 0.5) * CELL_SIZE, (origin.y + 0.5) * CELL_SIZE),
					direction,
					marker_y
				)
		_:
			direction = Vector2(-1, 0)
			arrow_count = cells.y
			for i in range(arrow_count):
				_draw_front_arrow(
					mesh,
					Vector2((origin.x + 0.5) * CELL_SIZE, (origin.y + i + 0.5) * CELL_SIZE),
					direction,
					marker_y
				)
	front_marker.set_meta("front_direction", Vector2i(roundi(direction.x), roundi(direction.y)))
	mesh.surface_end()
	front_marker.visible = true


func _draw_front_arrow(mesh: ImmediateMesh, center: Vector2, direction: Vector2, y: float) -> void:
	var tip: Vector2 = center + direction * CELL_SIZE * 0.38
	var back: Vector2 = tip - direction * CELL_SIZE * 0.22
	var side: Vector2 = Vector2(-direction.y, direction.x) * CELL_SIZE * 0.12
	mesh.surface_add_vertex(Vector3(center.x, y, center.y))
	mesh.surface_add_vertex(Vector3(tip.x, y, tip.y))
	mesh.surface_add_vertex(Vector3(tip.x, y, tip.y))
	mesh.surface_add_vertex(Vector3(back.x + side.x, y, back.y + side.y))
	mesh.surface_add_vertex(Vector3(tip.x, y, tip.y))
	mesh.surface_add_vertex(Vector3(back.x - side.x, y, back.y - side.y))


func _hide_front_marker() -> void:
	if is_instance_valid(front_marker):
		front_marker.visible = false
		if front_marker.get_parent() == floor_mesh:
			floor_mesh.remove_child(front_marker)
		front_marker.queue_free()
	front_marker = null
	marker_material = null
	last_marker_state.clear()


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
	for asset_id in ["block", "office_desk", "employee_workstation"]:
		var button := Button.new()
		match asset_id:
			"block":
				button.text = "Блок 1×1×1 м"
			"office_desk":
				button.text = "Офисный стол 1,6×0,8 м"
			"employee_workstation":
				button.text = "Рабочее место сотрудника"
		# Native Button owns both text and hit-test: no separately offset label/rect.
		button.custom_minimum_size = Vector2(280, 44)
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
	for i in range(
		int(ceilf(low.x / EDITOR_GRID_STEP)), int(floorf(high.x / EDITOR_GRID_STEP)) + 1
	):
		var x: float = i * EDITOR_GRID_STEP
		lines.surface_add_vertex(Vector3(x, y, low.z))
		lines.surface_add_vertex(Vector3(x, y, high.z))
	for i in range(
		int(ceilf(low.z / EDITOR_GRID_STEP)), int(floorf(high.z / EDITOR_GRID_STEP)) + 1
	):
		var z: float = i * EDITOR_GRID_STEP
		lines.surface_add_vertex(Vector3(low.x, y, z))
		lines.surface_add_vertex(Vector3(high.x, y, z))
	lines.surface_end()
	grid = MeshInstance3D.new()
	grid.name = "PlacementGrid"
	grid.add_to_group(PLACEMENT_VISUAL_GROUP)
	grid.mesh = lines
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Parent to the floor so mesh bounds, offset and grid share a coordinate system.
	floor_mesh.add_child(grid)
