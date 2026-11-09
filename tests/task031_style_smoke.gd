extends SceneTree
## Resource/geometry checks, not visual or physical pointer acceptance.
const Style = preload("res://scripts/ui_paper_style.gd")
const Card = preload("res://scripts/ui_paper_card.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for role in ["navigation", "tab", "primary", "secondary", "compact", "object", "dialog", "catalogue"]:
		var button: Button = Card.new() if role == "catalogue" else Button.new()
		root.add_child(button)
		button.position = Vector2(80, 80)
		button.size = Vector2(180, 64)
		var initial_rect := button.get_rect()
		for selected in [false, true]:
			Style.button(button, selected, role)
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var surface: StyleBox = button.get_theme_stylebox(state)
				assert(surface.get_content_margin(SIDE_LEFT) == 12)
				assert(surface.get_content_margin(SIDE_RIGHT) == 12)
				assert(surface.get_content_margin(SIDE_TOP) == 8)
				assert(surface.get_content_margin(SIDE_BOTTOM) == 8)
			assert(button.get_rect() == initial_rect)
			if selected:
				var normal: StyleBoxFlat = button.get_theme_stylebox("normal")
				var hover: StyleBoxFlat = button.get_theme_stylebox("hover")
				assert(normal.bg_color != hover.bg_color)
				assert(normal.get_border_width(SIDE_LEFT) == 3 or normal.get_border_width(SIDE_BOTTOM) == 3)
				assert(hover.get_border_width(SIDE_LEFT) == 3 or hover.get_border_width(SIDE_BOTTOM) == 3)
		button.disabled = true
		assert(button.get_rect() == initial_rect)
		button.queue_free()
	print("TASK 031 style resource smoke passed; visual/physical mouse acceptance still required.")
	quit()
