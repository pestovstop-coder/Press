extends Node3D
## TASK 002 / Stage 1 only. World units are metres; placement uses floor-local XZ.
## Blender front -Y maps to Godot +Z (Blender +Z maps to Godot +Y).
const STEP: float = 0.5
const BLOCK_SIZE: Vector3 = Vector3(1.0, 1.0, 1.0)
const GRID_LIFT: float = 0.012

var active: bool = false
var quarter_turns: int = 0
var valid_target: bool = false
var grid: MeshInstance3D
var preview: Node3D
var placed: Node3D
var floor_top: float
var floor_bounds: AABB

@onready var floor_mesh: MeshInstance3D = get_node("../TestRoom/Floor")
@onready var camera: Camera3D = get_node("../CameraRig/Camera3D")


func _ready() -> void:
	floor_bounds = floor_mesh.mesh.get_aabb()
	floor_top = floor_bounds.end.y
	_build_grid()
	preview = _make_block(true)
	add_child(preview)
	placed = Node3D.new()
	placed.name = "PlacedBlocks"
	add_child(placed)
	set_active(false)


func _process(_delta: float) -> void:
	# Reproject every frame, including when the camera pans/zooms without mouse motion.
	if active:
		_update_preview(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B:
				set_active(not active)
			KEY_ESCAPE:
				if not active:
					return
				set_active(false)
			KEY_R:
				if not active:
					return
				quarter_turns = (quarter_turns + 1) % 4
				preview.rotation.y = quarter_turns * PI / 2.0
			_:
				return
		get_viewport().set_input_as_handled()
	elif active and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_update_preview(event.position)
				# MMB remains camera-only: do not confirm while panning.
				if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
					place_block()
			get_viewport().set_input_as_handled()
	# Motion is not consumed: the camera only pans with MMB, never with LMB.


func set_active(enabled: bool) -> void:
	active = enabled
	grid.visible = enabled
	valid_target = false
	preview.visible = false
	if enabled:
		quarter_turns = 0
		preview.rotation.y = 0.0
		_update_preview(get_viewport().get_mouse_position())


func snapped_floor_point(local_hit: Vector3) -> Vector3:
	return Vector3(snappedf(local_hit.x, STEP), floor_top, snappedf(local_hit.z, STEP))


func target_inside_floor(point: Vector3) -> bool:
	var half: Vector3 = BLOCK_SIZE * 0.5
	return (
		point.x - half.x >= floor_bounds.position.x
		and point.x + half.x <= floor_bounds.end.x
		and point.z - half.z >= floor_bounds.position.z
		and point.z + half.z <= floor_bounds.end.z
	)


func _update_preview(screen_point: Vector2) -> void:
	var origin: Vector3 = floor_mesh.to_local(camera.project_ray_origin(screen_point))
	var direction: Vector3 = (
		floor_mesh.global_basis.inverse() * camera.project_ray_normal(screen_point)
	)
	valid_target = false
	preview.visible = false
	if absf(direction.y) < 0.00001:
		return
	var distance: float = (floor_top - origin.y) / direction.y
	if distance < 0.0:
		return
	var hit: Vector3 = origin + direction * distance
	# Do not snap a point outside the physical floor back into the room.
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
	preview.global_position = floor_mesh.to_global(point)


func place_block() -> void:
	if not active or not valid_target:
		return
	var block: Node3D = _make_block(false)
	placed.add_child(block)
	block.global_transform = preview.global_transform


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
