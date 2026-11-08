extends SceneTree
## Run after importing the project: godot --headless --path . --script tests/ui_shell_smoke.gd

func _initialize() -> void:
	call_deferred("_run")

func _click_button(button: Button, local_point: Vector2) -> void:
	var point: Vector2 = button.get_global_transform_with_canvas() * local_point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
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
	await process_frame
	var ui = scene.get_node("UIShell")
	assert(ui.root.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	for panel in [ui.top, ui.rail, ui.side, ui.bottom]:
		assert(panel.mouse_filter == Control.MOUSE_FILTER_STOP)
		assert(not panel.mouse_force_pass_scroll_events)
	for button in ui.nav_buttons.values():
		assert(button.mouse_filter == Control.MOUSE_FILTER_STOP)
		assert(button.mouse_force_pass_scroll_events)
	for button in ui.speed_buttons + [ui.pause_button]:
		assert(button.mouse_filter == Control.MOUSE_FILTER_STOP)
		assert(not button.mouse_force_pass_scroll_events)
		assert(button.custom_minimum_size == Vector2(44, 44))
	ui._show_section("Документы")
	var first_note: String = ui.current_note
	ui._show_section("Офис")
	ui._show_section("Документы")
	assert(ui.current_note != first_note)
	var card: Button = ui.side_content.get_child(2)
	assert(card.mouse_force_pass_scroll_events and card.mouse_filter == Control.MOUSE_FILTER_STOP)
	assert(ui.current_section == "Документы" and ui.side.visible)
	await process_frame
	await process_frame
	_click_button(card, card.size / 2.0)
	assert(ui.side_content.get_child(0) is Button) # detail back button
	ui._show_detail(["РЛ", "Пресс-релиз № 18", "НА СОГЛАСОВАНИИ", "Демо"])
	assert(ui.side_content.get_child_count() > 3)
	ui.side.hide()
	ui._show_section("Задачи")
	assert(ui.side.visible and ui.current_section == "Задачи")
	ui._set_speed(3)
	assert(ui.speed == 3)
	ui._toggle_pause()
	assert(ui.paused)
	var before: float = ui.minutes
	ui._process(5.0)
	assert(ui.minutes == before)
	ui._toggle_pause()
	ui._process(5.0)
	assert(is_equal_approx(ui.minutes, before + 15.0))
	ui.minutes = 1439.0
	ui.day = 0
	ui._process(1.0)
	assert(ui.day == 1 and ui.date_label.text.contains("03.03.2026"))
	var placement = scene.get_node("PlacementController")
	placement.set_active(true)
	await process_frame
	assert(not placement.panel.mouse_force_pass_scroll_events)
	var catalogue: Node = placement.panel.get_node("Scroll/Column")
	for i in range(1, 4):
		var item: Button = catalogue.get_child(i)
		assert(item.mouse_force_pass_scroll_events and item.mouse_filter == Control.MOUSE_FILTER_STOP)
	assert(placement._diagnostic_text("FURNITURE_COLLISION") == "Здесь находится мебель")
	ui._process(0.0)
	assert(not ui.root.visible)
	placement.set_active(false)
	ui._process(0.0)
	assert(ui.root.visible)
	print("UI shell smoke passed (not a visual or pointer-interaction test).")
	quit()
