extends Node3D

## Task 001 — fixed isometric camera rig.
##
## Pan moves the rig on the horizontal (XZ) plane, zoom changes the orthographic
## size of the child Camera3D. The rotation is written once in _ready() and is
## never touched again, so the isometric angle stays stable at any zoom/pan.
##
## Inputs deliberately left free for future object placement:
##   left mouse button, R, Q, E, Space, Escape.
## Pan uses WASD / arrow keys and middle-mouse drag; zoom uses the wheel or +/-.
## Home resets the view. This node reads input via _unhandled_input() so a
## future UI layer can consume events before the camera sees them.

const ISO_PITCH_DEG: float = -35.26438968  # atan(1 / sqrt(2)) — true isometric
const ISO_YAW_DEG: float = 45.0
const INITIAL_SIZE: float = 14.0

@export_range(1.0, 20.0, 0.5) var pan_speed: float = 5.0
@export_range(0.001, 0.1, 0.001) var drag_pan_speed: float = 0.013
@export_range(0.01, 0.5, 0.01) var zoom_step: float = 0.12
@export_range(1.0, 30.0, 0.5) var zoom_smoothing: float = 12.0
@export_range(2.0, 40.0, 0.5) var min_size: float = 6.0   # closest zoom
@export_range(2.0, 40.0, 0.5) var max_size: float = 26.0  # farthest zoom
@export var pan_limit_x: float = 5.0
@export var pan_limit_z: float = 5.0

var _camera: Camera3D
var _target_size: float = INITIAL_SIZE
var _dragging: bool = false
var _right: Vector3 = Vector3.RIGHT
var _forward: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_camera = get_node("Camera3D") as Camera3D

	rotation_degrees = Vector3(ISO_PITCH_DEG, ISO_YAW_DEG, 0.0)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = INITIAL_SIZE
	_camera.near = 0.1
	_camera.far = 200.0
	_target_size = INITIAL_SIZE

	# Keep the limits valid even if exported values are edited by hand.
	if min_size > max_size:
		min_size = max_size
	_target_size = clampf(_target_size, min_size, max_size)
	_update_axes()


## Screen-aligned horizontal axes, derived from the (constant) rig rotation.
func _update_axes() -> void:
	_right = transform.basis.x
	_right.y = 0.0
	_right = _right.normalized()
	_forward = -transform.basis.z
	_forward.y = 0.0
	_forward = _forward.normalized()


func _process(delta: float) -> void:
	# Continuous pan with WASD / arrow keys.
	var h: float = 0.0
	var v: float = 0.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		h += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		h -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v -= 1.0

	# Pan distance scales with zoom so a drag/keystroke moves the same number of
	# screen pixels at any zoom level.
	var zoom_scale: float = _camera.size / INITIAL_SIZE
	if h != 0.0 or v != 0.0:
		var move: Vector3 = (_right * h + _forward * v).normalized()
		position += move * pan_speed * zoom_scale * delta
		_clamp_position()

	# Smoothed zoom, always clamped to the configured limits.
	_camera.size = lerpf(_camera.size, _target_size, clampf(zoom_smoothing * delta, 0.0, 1.0))
	_camera.size = clampf(_camera.size, min_size, max_size)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var zoom_scale: float = _camera.size / INITIAL_SIZE
		var rel: Vector2 = mm.relative
		# Dragging the world: mouse right -> camera left, mouse down -> camera forward.
		position += (-_right * rel.x + _forward * rel.y) * drag_pan_speed * zoom_scale
		_clamp_position()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		match key.keycode:
			KEY_HOME:
				_reset()
				get_viewport().set_input_as_handled()
			KEY_EQUAL, KEY_KP_ADD:
				_zoom(-1)
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom(1)
				get_viewport().set_input_as_handled()


func _zoom(direction: int) -> void:
	# direction -1 = zoom in (smaller size), +1 = zoom out (larger size).
	var factor: float = 1.0 + zoom_step if direction > 0 else 1.0 - zoom_step
	_target_size = clampf(_target_size * factor, min_size, max_size)


func _reset() -> void:
	position = Vector3.ZERO
	_target_size = clampf(INITIAL_SIZE, min_size, max_size)
	_camera.size = _target_size
	_dragging = false


func _clamp_position() -> void:
	position.x = clampf(position.x, -pan_limit_x, pan_limit_x)
	position.z = clampf(position.z, -pan_limit_z, pan_limit_z)
	position.y = 0.0
