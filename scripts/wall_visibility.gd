extends Node
## TASK 011.1: geometric top clipping of this room's individual BoxMesh modules.
## Heights animate, not visibility of entire walls. Apertures keep world positions.
const HIDE_THRESHOLD: float = 0.12
const SHOW_THRESHOLD: float = 0.04
const SHARED_HIDE: float = 0.18
const SHARED_SHOW: float = 0.10
const LOW_HEIGHT: float = 0.9
const FULL_HEIGHT: float = 3.0
const RESPONSE: float = 8.0
const EPSILON: float = 0.0001

# Legacy name retained: true now means LOWER, not hide the complete wall.
var hidden_sides: Dictionary = {
	"front": false, "rear": false, "west": false, "east": false, "shared": false
}
var heights: Dictionary = {"front": 3.0, "rear": 3.0, "west": 3.0, "east": 3.0, "shared": 3.0}
var modules: Array[MeshInstance3D] = []
var originals: Dictionary = {}
@onready var camera: Camera3D = get_node("../CameraRig/Camera3D")
@onready var placement: Node = get_node("../PlacementController")


func _ready() -> void:
	for child in get_node("../TestRoom").get_children():
		if child is MeshInstance3D and child.has_meta("cutaway_side"):
			var authored: BoxMesh = child.mesh as BoxMesh
			assert(authored != null, "This prototype only clips authored BoxMesh modules")
			assert(child.rotation.is_zero_approx() and child.scale.is_equal_approx(Vector3.ONE))
			modules.append(child)
			originals[child] = {"size": authored.size, "position": child.position}
			# Never mutate a shared resource: each module has independent geometry.
			child.mesh = authored.duplicate() as BoxMesh
	camera.get_parent().connect("view_changed", _sync_from_camera)
	_sync_from_camera()
	_apply_heights()


func _sync_from_camera() -> void:
	update_visibility(camera.global_basis.z)


func _process(delta: float) -> void:
	_sync_from_camera()
	advance_heights(delta)


func _latch(key: String, facing: float, hide_at: float, show_at: float) -> void:
	if facing > hide_at:
		hidden_sides[key] = true
	elif facing < show_at:
		hidden_sides[key] = false


func update_visibility(towards_camera: Vector3) -> void:
	# Only targets change here; a camera signal must never snap current geometry.
	var direction := Vector3(towards_camera.x, 0, towards_camera.z).normalized()
	_latch("front", direction.z, HIDE_THRESHOLD, SHOW_THRESHOLD)
	_latch("rear", -direction.z, HIDE_THRESHOLD, SHOW_THRESHOLD)
	_latch("east", direction.x, HIDE_THRESHOLD, SHOW_THRESHOLD)
	_latch("west", -direction.x, HIDE_THRESHOLD, SHOW_THRESHOLD)
	_latch("shared", absf(direction.x), SHARED_HIDE, SHARED_SHOW)


func advance_heights(delta: float) -> void:
	var weight: float = 1.0 - exp(-RESPONSE * maxf(delta, 0.0))
	# Update all sides before computing junctions: no one-frame stale corners.
	for side in heights:
		var target: float = LOW_HEIGHT if hidden_sides[side] else FULL_HEIGHT
		var height: float = lerpf(float(heights[side]), target, weight)
		if absf(height - target) < EPSILON:
			height = target
		heights[side] = clampf(height, LOW_HEIGHT, FULL_HEIGHT)
	_apply_heights()


func module_height(mesh: MeshInstance3D) -> float:
	var height: float = LOW_HEIGHT
	var sides: String = mesh.get_meta("cutaway_side")
	for side in sides.split("_"):
		height = maxf(height, float(heights[side]))
	return height


func _apply_heights() -> void:
	for mesh in modules:
		var original: Dictionary = originals[mesh]
		var size: Vector3 = original["size"]
		var center: Vector3 = original["position"]
		var bottom: float = center.y - size.y * 0.5
		var top: float = minf(center.y + size.y * 0.5, module_height(mesh))
		# Above-cut headers/frames can vanish, but ground-level walls stay >=0.9m.
		# Never create zero-size meshes or singular transforms, even at a boundary.
		if top - bottom <= EPSILON:
			mesh.visible = false
			continue
		mesh.visible = true
		var clipped_size := Vector3(size.x, top - bottom, size.z)
		var clipped_center := Vector3(center.x, (bottom + top) * 0.5, center.z)
		var box: BoxMesh = mesh.mesh
		if box.size != clipped_size:
			# Picking caches local triangles by resource: invalidate before mutation.
			placement.face_cache.erase(box)
			box.size = clipped_size
		mesh.position = clipped_center
