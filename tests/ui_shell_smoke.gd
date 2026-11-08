extends SceneTree
## Run after importing the project: godot --headless --path . --script tests/ui_shell_smoke.gd

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var ui = scene.get_node("UIShell")
	assert(ui.root.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	for panel in [ui.top, ui.rail, ui.side, ui.bottom]:
		assert(panel.mouse_filter == Control.MOUSE_FILTER_STOP)
		assert(not panel.mouse_force_pass_scroll_events)
	for button in ui.nav_buttons.values() + ui.speed_buttons + [ui.pause_button]:
		assert(button.mouse_filter == Control.MOUSE_FILTER_STOP)
		assert(not button.mouse_force_pass_scroll_events)
	ui._show_section("Документы")
	assert(ui.current_section == "Документы" and ui.side.visible)
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
	ui._process(0.0)
	assert(not ui.root.visible)
	placement.set_active(false)
	ui._process(0.0)
	assert(ui.root.visible)
	print("UI shell smoke passed (not a visual or pointer-interaction test).")
	quit()
