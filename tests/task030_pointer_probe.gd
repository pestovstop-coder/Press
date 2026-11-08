extends SceneTree
## Interactive diagnostic, not a synthetic test:
## godot --path . --script tests/task030_pointer_probe.gd
## Click visible button centers and edges; compare output with screen evidence.

class Probe extends Node:
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			call_deferred("_report", event.position, event.global_position,
				DisplayServer.mouse_get_position(), get_viewport().get_mouse_position())

	func _report(event_pos: Vector2, event_global: Vector2, screen_mouse: Vector2i, viewport_mouse: Vector2) -> void:
		var viewport := get_viewport()
		var shell = get_tree().root.get_node("Main/UIShell")
		var hovered := viewport.gui_get_hovered_control()
		print("--- pointer probe ---")
		print("system mouse=", screen_mouse,
			" window pos=", DisplayServer.window_get_position(),
			" window size=", DisplayServer.window_get_size(),
			" window mode=", DisplayServer.window_get_mode(),
			" screen dpi=", DisplayServer.screen_get_dpi())
		print("event viewport=", event_pos, " event global=", event_global,
			" viewport mouse=", viewport_mouse,
			" viewport rect=", viewport.get_visible_rect(),
			" final transform=", viewport.get_final_transform())
		print("HUD canvas transform=", shell.transform,
			" root canvas transform=", shell.root.get_global_transform_with_canvas(),
			" root rect=", shell.root.get_global_rect())
		print("hovered=", hovered.get_path() if hovered else "none")
		if hovered:
			var ancestor: Node = hovered
			while ancestor and not ancestor is CanvasLayer:
				ancestor = ancestor.get_parent()
			if ancestor is CanvasLayer:
				print("hovered CanvasLayer transform=", (ancestor as CanvasLayer).transform)
			var transform: Transform2D = hovered.get_global_transform_with_canvas()
			var local: Vector2 = transform.affine_inverse() * event_pos
			print("hovered rect=", hovered.get_global_rect(), " canvas transform=", transform,
				" click local=", local, " local bounds=", Rect2(Vector2.ZERO, hovered.size),
				" local contains=", Rect2(Vector2.ZERO, hovered.size).has_point(local))

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	root.add_child(load("res://scenes/main.tscn").instantiate())
	root.add_child(Probe.new())
	print("Pointer probe active. Click buttons; close the window to exit.")
