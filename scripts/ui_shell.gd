extends CanvasLayer
## TASK 026: presentation-only data. Nothing here changes the simulation.

const Style = preload("res://scripts/ui_paper_style.gd")
const Note = preload("res://scripts/ui_service_note.gd")
const NOTES := {
	"Офис": ["Рабочий день начался. Причины пока неизвестны.", "Ситуация стабильна. Определение стабильности уточняется."],
	"Сотрудники": ["Штатное расписание утверждено. Штат пока не в курсе.", "Ответственный назначен. Ответственность уточняется."],
	"Редакция": ["Редакция просит комментарий. Руководство просит не комментировать.", "Заголовок утверждён. Содержание на рассмотрении."],
	"Задачи": ["Пять слов согласовывали три рабочих дня.", "Срок уточнён. Срочность остаётся прежней."],
	"Документы": ["Три экземпляра. Четвёртый — на всякий случай.", "Замечаний нет. Просьба учесть замечания."]
}
const PAPER := Color("e9e1d2")
const LIGHT := Color("f5f0e6")
const INK := Color("252a2e")
const NAVY := Color("173b59")
const RED := Color("b7443e")
const MUTED := Color("6c716d")
const LINE := Color("c9c1b2")
const DATA := {
	"Офис": [
		["101", "Кабинет 101", "ПОМЕЩЕНИЕ", "Редакционная зона. Планировка и мебель доступны в режиме расстановки."],
		["102", "Кабинет 102", "ПОМЕЩЕНИЕ", "Рабочее пространство пресс-службы."],
		["01", "Рабочий стол", "ОБЪЕКТ", "Офисный стол в текущей сцене. Выбор здесь демонстрационный."]],
	"Сотрудники": [
		["АК", "Анна Ковалева", "РЕДАКТОР", "Готовит материалы для внутренней повестки."],
		["МС", "Михаил Серов", "КОРРЕСПОНДЕНТ", "Уточняет комментарий производственного отдела."],
		["ЕЛ", "Елена Лазарева", "МОНТАЖЁР", "Собирает видеоматериал о предприятии."]],
	"Редакция": [
		["01", "План публикаций", "В РАБОТЕ", "Три материала в демонстрационном редакционном плане."],
		["02", "Запрос СМИ", "ОЖИДАЕТ", "Комментарий направлен на внутреннее согласование."]],
	"Задачи": [
		["01", "Подготовить релиз", "В РАБОТЕ", "Новость о запуске производственной линии. Срок: сегодня."],
		["02", "Ответить редакции", "ОЖИДАЕТ", "Запрос получен. Ответ ожидает согласования."],
		["03", "Собрать отчёт", "ГОТОВО", "Еженедельный обзор публикаций подготовлен."]],
	"Документы": [
		["РЛ", "Пресс-релиз № 18", "НА СОГЛАСОВАНИИ", "Материал готов к публикации. Не согласован."],
		["СП", "Служебная записка", "С ЗАМЕЧАНИЯМИ", "Правки внесены. Смысл уточняется."],
		["ОТ", "Медиаотчёт", "ГОТОВО", "Обзор упоминаний за прошедшую неделю."]]
}
var root: Control
var top: PanelContainer
var rail: PanelContainer
var side: PanelContainer
var bottom: PanelContainer
var side_content: VBoxContainer
var nav_buttons: Dictionary = {}
var clock_label: Label
var date_label: Label
var pause_button: Button
var speed_buttons: Array[Button] = []
var current_section := "Офис"
var note_indices: Dictionary = {}
var current_note := ""
var paused := false
var speed := 1
var minutes := 9.0 * 60.0
var day := 0
var placement: Node

func _ready() -> void:
	layer = 2
	placement = get_parent().get_node("PlacementController")
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_show_section("Офис")
	_update_clock()

func _process(delta: float) -> void:
	# The existing placement catalogue occupies the top-left; yield the whole HUD
	# while it is open rather than masking or modifying the protected tool.
	root.visible = not placement.active
	if not paused:
		minutes += delta * speed
		while minutes >= 1440.0:
			minutes -= 1440.0
			day += 1
		_update_clock()

func _style(bg: Color, border: Color = LINE, width: int = 1) -> StyleBoxFlat:
	return Style.box(bg, border, width)

func _panel(bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_force_pass_scroll_events = false
	p.add_theme_stylebox_override("panel", _style(bg))
	root.add_child(p)
	return p

func _label(text: String, size: int = 16, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, active: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.mouse_force_pass_scroll_events = false
	b.custom_minimum_size = Vector2(44, 44)
	Style.button(b, active)
	return b

func _column(parent: Node, separation: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	parent.add_child(v)
	return v

func _build() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	top = _panel(LIGHT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	top.add_child(h)
	var brand := _column(h, 0)
	brand.custom_minimum_size.x = 175
	brand.add_child(_label("PRESS OFFICE", 20, NAVY))
	brand.add_child(_label("TYCOON  /  ДЕМО", 11, MUTED))
	var date_box := _column(h, 0)
	date_box.custom_minimum_size.x = 155
	date_label = _label("", 13, MUTED)
	date_box.add_child(date_label)
	clock_label = _label("", 23, INK)
	date_box.add_child(clock_label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	h.add_child(controls)
	pause_button = _button("Ⅱ")
	pause_button.tooltip_text = "Пауза"
	pause_button.pressed.connect(_toggle_pause)
	controls.add_child(pause_button)
	for n in [1, 2, 3]:
		var b := _button("%d×" % n, n == speed)
		b.pressed.connect(_set_speed.bind(n))
		controls.add_child(b)
		speed_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	for metric in [["РЕПУТАЦИЯ", "72 / 100"], ["КОМАНДА", "3 человека"], ["РУКОВОДСТВО", "Доверие 68"]]:
		var box := _column(h, 2)
		box.add_child(_label(metric[0], 11, MUTED))
		box.add_child(_label(metric[1], 16, NAVY))
	rail = _panel(PAPER)
	var rail_scroll := ScrollContainer.new()
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	Style.scrollbar(rail_scroll)
	rail.add_child(rail_scroll)
	var menu := _column(rail_scroll, 6)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_child(_label("НАВИГАЦИЯ  /  01", 11, MUTED))
	for section in DATA.keys():
		var b := _button(section)
		b.mouse_force_pass_scroll_events = true
		b.clip_text = true
		b.custom_minimum_size.y = 46
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_show_section.bind(section))
		menu.add_child(b)
		nav_buttons[section] = b
	menu.add_child(_label("ИНСТРУМЕНТЫ", 11, MUTED))
	var hint := _label("B  ·  Расстановка\nПКМ  ·  Вращение\nКолесо  ·  Масштаб", 13, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(hint)
	side = _panel(LIGHT)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Style.scrollbar(scroll)
	side.add_child(scroll)
	side_content = _column(scroll, 10)
	side_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom = _panel(PAPER)
	var events := HBoxContainer.new()
	events.add_theme_constant_override("separation", 18)
	bottom.add_child(events)
	var heading := _column(events, 2)
	heading.custom_minimum_size.x = 160
	heading.add_child(_label("ЛЕНТА СОБЫТИЙ", 13, NAVY))
	heading.add_child(_label("ДЕМО  /  03 записи", 11, MUTED))
	for event in [["ИНФОРМАЦИЯ", "Редакционный план обновлён", NAVY], ["ВНИМАНИЕ", "Релиз ожидает согласования", RED], ["СИСТЕМА", "Данные носят демонстрационный характер", MUTED]]:
		var e := _column(events, 3)
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.add_child(_label(event[0], 11, event[2]))
		var text := _label(event[1], 14, INK)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.add_child(text)

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := viewport_size.x < 1400
	var header_height := 78.0 if not compact else 70.0
	var rail_width := 188.0 if not compact else 156.0
	var side_width := 320.0 if not compact else 300.0
	var bottom_height := 104.0 if not compact else 94.0
	top.position = Vector2.ZERO
	top.size = Vector2(viewport_size.x, header_height)
	rail.position = Vector2(12, header_height + 12)
	rail.size = Vector2(rail_width, maxf(80, minf(385, viewport_size.y - header_height - bottom_height - 36)))
	side.position = Vector2(viewport_size.x - side_width - 12, header_height + 12)
	side.size = Vector2(side_width, maxf(180, viewport_size.y - header_height - bottom_height - 36))
	bottom.position = Vector2(12, viewport_size.y - bottom_height - 12)
	bottom.size = Vector2(viewport_size.x - 24, bottom_height)

func _clear_side() -> void:
	for child in side_content.get_children():
		side_content.remove_child(child)
		child.queue_free()

func _show_section(section: String, advance_note: bool = true) -> void:
	current_section = section
	if advance_note or current_note.is_empty():
		var index: int = (int(note_indices.get(section, -1)) + 1) % NOTES[section].size()
		note_indices[section] = index
		current_note = NOTES[section][index]
	side.show()
	for name in nav_buttons:
		var b: Button = nav_buttons[name]
		var active: bool = name == section
		b.add_theme_stylebox_override("normal", _style(NAVY if active else LIGHT, NAVY if active else LINE))
		b.add_theme_color_override("font_color", LIGHT if active else INK)
	_clear_side()
	var header := HBoxContainer.new()
	side_content.add_child(header)
	var title := _label(section.to_upper(), 20, NAVY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := _button("×")
	close.pressed.connect(side.hide)
	close.mouse_force_pass_scroll_events = true
	header.add_child(close)
	side_content.add_child(_label("ОБЗОР  /  ДЕМО-ДАННЫЕ", 11, MUTED))
	for item in DATA[section]:
		var card := _button("%s   %s\n        %s" % [item[0], item[1], item[2]])
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.custom_minimum_size.y = 68
		card.mouse_force_pass_scroll_events = true
		card.clip_text = true
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(_show_detail.bind(item))
		side_content.add_child(card)
	var foot := _label("Выберите карточку для подробностей", 12, MUTED)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_content.add_child(foot)
	_add_note()

func _add_note() -> void:
	var note := Note.new()
	note.set_note(current_note)
	side_content.add_child(note)

func _show_detail(item: Array) -> void:
	_clear_side()
	var back := _button("←  К списку")
	back.mouse_force_pass_scroll_events = true
	back.pressed.connect(_show_section.bind(current_section, false))
	side_content.add_child(back)
	side_content.add_child(_label("КАРТОЧКА  /  ДЕМО", 11, MUTED))
	var title := _label(item[1], 21, NAVY)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_content.add_child(title)
	side_content.add_child(_label(item[2], 13, RED if item[2] in ["ОЖИДАЕТ", "С ЗАМЕЧАНИЯМИ", "НА СОГЛАСОВАНИИ"] else NAVY))
	var description := _label(item[3], 15)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_content.add_child(description)
	side_content.add_child(_label("────────────────────", 13, LINE))
	var note := _label("Сведения показаны для примера. Управление и последствия пока не реализованы.", 13, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_content.add_child(note)
	var close := _button("Закрыть панель")
	close.pressed.connect(side.hide)
	close.mouse_force_pass_scroll_events = true
	side_content.add_child(close)
	_add_note()

func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "▶" if paused else "Ⅱ"
	pause_button.tooltip_text = "Продолжить" if paused else "Пауза"

func _set_speed(value: int) -> void:
	speed = value
	for i in range(speed_buttons.size()):
		var selected := i + 1 == speed
		speed_buttons[i].add_theme_stylebox_override("normal", _style(NAVY if selected else LIGHT, NAVY if selected else LINE))
		speed_buttons[i].add_theme_color_override("font_color", LIGHT if selected else INK)

func _update_clock() -> void:
	clock_label.text = "%02d:%02d" % [int(minutes) / 60, int(minutes) % 60]
	var date := Time.get_date_dict_from_unix_time(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 3, "day": 2, "hour": 0, "minute": 0, "second": 0}) + day * 86400)
	date_label.text = "ДЕНЬ %d  /  %02d.%02d.%04d" % [day + 1, date.day, date.month, date.year]
