extends SceneTree
## Runtime GUI geometry checks. Run after import on Godot 4.7.2.

func _initialize() -> void:
	call_deferred("_run")

func _hover(button: Button, local_point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_transform_with_canvas() * local_point
	root.push_input(motion, true)
	assert(root.gui_get_hovered_control() == button)

func _click(button: Button, local_point: Vector2) -> void:
	_hover(button, local_point)
	var point: Vector2 = button.get_global_transform_with_canvas() * local_point
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(event, true)

func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var ui = scene.get_node("UIShell")
	var placement = scene.get_node("PlacementController")
	for viewport_size in [Vector2i(1920, 1080), Vector2i(1366, 768), Vector2i(1280, 720)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		assert(ui.bottom.size.y < (94.0 if viewport_size.x < 1400 else 104.0))
		assert(not ui.bottom.get_global_rect().intersects(ui.rail.get_global_rect()))
		assert(not ui.bottom.get_global_rect().intersects(ui.side.get_global_rect()))
		assert(ui.service_note.get_parent().get_parent().get_parent() == ui.bottom)
		var navigation: Button = ui.nav_buttons["Документы"]
		for point in [Vector2(3, 3), navigation.size / 2.0, navigation.size - Vector2(3, 3)]:
			_click(navigation, point)
			assert(ui.current_section == "Документы")
		await process_frame
		var card: Button = ui.side_content.get_child(2)
		_click(card, Vector2(3, 3))
		assert(ui.side_content.get_child(0) is Button)
		var old_note: String = ui.current_note
		ui._show_section("Документы", false)
		assert(ui.current_note == old_note)
		placement.set_active(true)
		await process_frame
		await process_frame
		var catalogue: Node = placement.panel.get_node("Scroll/Column")
		var item: Button = catalogue.get_child(1)
		for point in [Vector2(3, 3), item.size / 2.0, item.size - Vector2(3, 3)]:
			_click(item, point)
			assert(placement.selected_asset == "block")
		placement.set_active(false)
		await process_frame
	print("TASK 029 GUI geometry smoke passed; visual/physical mouse acceptance still required.")
	quit()
