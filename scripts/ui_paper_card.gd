extends Button
## Decorative ink is drawn inside the button's own rect; input geometry never changes.
var fold: float = 0.0:
	set(value):
		fold = value
		queue_redraw()
var animation: Tween

func _ready() -> void:
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	button_down.connect(_on_down)
	button_up.connect(_on_up)

func _animate(target: float) -> void:
	if animation and animation.is_valid():
		animation.kill()
	animation = create_tween()
	animation.tween_property(self, "fold", target, 0.15)

func _on_enter() -> void:
	_animate(1.0)

func _on_exit() -> void:
	_animate(0.0)

func _on_down() -> void:
	_animate(0.15)

func _on_up() -> void:
	_animate(1.0 if get_viewport().gui_get_hovered_control() == self else 0.0)

func _draw() -> void:
	# A restrained second-sheet edge and folded corner, inside the hit rectangle.
	var edge := Color("b6ad9d")
	var tip := Color("d9d0bf")
	var lift := 7.0 + fold * 4.0
	draw_line(Vector2(5, size.y - 3), Vector2(size.x - 5, size.y - 3), edge, 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x - lift - 2, 2), Vector2(size.x - 2, 2),
		Vector2(size.x - 2, lift + 2)]), tip)
	draw_line(Vector2(size.x - lift - 2, 2), Vector2(size.x - 2, lift + 2), edge, 1.0)
