extends Node
## TASK 011: explicit two-office cutaway, not a general building solver.
## Orthographic view direction (not camera position) is independent of panning.
## Hysteresis avoids flicker at edge-on angles. No geometry/collision deletion.
const HIDE_THRESHOLD: float = 0.12
const SHOW_THRESHOLD: float = 0.04
const SHARED_HIDE: float = 0.18
const SHARED_SHOW: float = 0.10

var hidden_sides: Dictionary = {
	"front": false, "rear": false, "west": false, "east": false, "shared": false
}
var modules: Array[MeshInstance3D] = []
@onready var camera: Camera3D = get_node("../CameraRig/Camera3D")


func _ready() -> void:
	for child in get_node("../TestRoom").get_children():
		if child is MeshInstance3D and child.has_meta("cutaway_side"):
			modules.append(child)
	camera.get_parent().connect("view_changed", _sync_from_camera)
	_sync_from_camera()


func _sync_from_camera() -> void:
	update_visibility(camera.global_basis.z)


func _process(_delta: float) -> void:
	update_visibility(camera.global_basis.z)


func _latch(key: String, facing: float, hide_at: float, show_at: float) -> void:
	if facing > hide_at:
		hidden_sides[key] = true
	elif facing < show_at:
		hidden_sides[key] = false


func update_visibility(towards_camera: Vector3) -> void:
	var direction := Vector3(towards_camera.x, 0, towards_camera.z).normalized()
	_latch("front", direction.z, HIDE_THRESHOLD, SHOW_THRESHOLD)
	_latch("rear", -direction.z, HIDE_THRESHOLD, SHOW_THRESHOLD)
	_latch("east", direction.x, HIDE_THRESHOLD, SHOW_THRESHOLD)
	_latch("west", -direction.x, HIDE_THRESHOLD, SHOW_THRESHOLD)
	# Two rooms are inspected together: either broad side of the shared wall
	# masks one office. Keep it only near edge-on, with its own hysteresis.
	_latch("shared", absf(direction.x), SHARED_HIDE, SHARED_SHOW)
	# Corner posts remain if either adjoining wall is visible: no holes in
	# the retained rear wall when the central partition or side is hidden.
	for mesh in modules:
		var side: String = mesh.get_meta("cutaway_side")
		var hidden: bool = true
		for part in side.split("_"):
			hidden = hidden and bool(hidden_sides[part])
		mesh.visible = not hidden
