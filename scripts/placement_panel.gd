extends PanelContainer
## Presentation adapter for the existing placement controller; no placement rules.
const Style = preload("res://scripts/ui_paper_style.gd")
const NOTES := [
	"Планировка утверждена. Стены имеют другое мнение.",
	"Свободное пространство зарезервировано под важные задачи.",
	"Помещение готово. Порядок использования уточняется."
]
var controller: Node
var buttons: Dictionary = {}
var note: Control
var last_selected := "__initial__"
var was_active := false
var note_index := -1

func setup(source: Node, catalogue_buttons: Dictionary, annotation: Control) -> void:
	controller = source
	buttons = catalogue_buttons
	note = annotation
	get_viewport().size_changed.connect(_layout)
	get_node("Scroll/Column").minimum_size_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	position = Vector2(16, 16)
	var content: Control = get_node("Scroll/Column")
	var natural_height := content.get_combined_minimum_size().y + 18.0
	size = Vector2(330, minf(natural_height, maxf(120, viewport_size.y - 32)))

func _process(_delta: float) -> void:
	if controller == null:
		return
	var active: bool = controller.get("active")
	if active and not was_active:
		note_index = (note_index + 1) % NOTES.size()
		note.call("set_note", NOTES[note_index])
	was_active = active
	var selected: String = controller.get("selected_asset") if active else ""
	if selected != last_selected:
		for id in buttons:
			Style.button(buttons[id], id == selected, "catalogue")
		last_selected = selected
