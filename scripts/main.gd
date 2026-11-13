extends Node2D
## Offline prototype 0.5: deterministic isometric city and daily stock-flow economy.
const CityGenerator = preload("res://scripts/city_generator.gd")
const CompanyState = preload("res://scripts/company_state.gd")
const TILE_W := 96.0
const TILE_H := 48.0
const MAP_SIZE := 32
const COLORS := {
	"Жилой дом": Color("#e7cba2"),
	"Магазин": Color("#5e9fb8"),
	"Склад": Color("#b18d64"),
	"Завод": Color("#8595a2"),
	"Офис": Color("#a9bfc9")
}

var company = CompanyState.new()
var money_label: Label
var economy_label: Label
var day_timer: Timer
var pause_button: Button
var actions: VBoxContainer
var message_label: Label
var camera: Camera2D
var selected := Vector2i(-1, -1)
var city_index := 0
var cells: Dictionary = {}
var touches: Dictionary = {}
var previous_pinch_distance := 0.0
var dragging := false
var moved_since_press := false
var last_mouse := Vector2.ZERO
var info: Label
var city_label: Label

func _ready() -> void:
	camera = Camera2D.new()
	camera.position = Vector2(0, 650)
	camera.zoom = Vector2(0.8, 0.8)
	add_child(camera)
	camera.make_current()
	_build_ui()
	company.load_game()
	_load_city(company.city_index)
	day_timer = Timer.new()
	day_timer.wait_time = 15.0
	day_timer.timeout.connect(_advance_day)
	add_child(day_timer)
	day_timer.start()

func _load_city(index: int) -> void:
	city_index = posmod(index, CityGenerator.CITIES.size())
	var data: Dictionary = CityGenerator.make_city(city_index)
	cells = data["cells"]
	selected = Vector2i(-1, -1)
	company.city_index = city_index
	company.save_game()
	city_label.text = "Город: %s (демонстрация)" % data["name"]
	info.text = "Нажмите на участок или здание"
	message_label.text = ""
	_update_actions()
	camera.position = Vector2(0, 700)
	queue_redraw()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(360, 170)
	layer.add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var title := Label.new()
	title.text = "BUSINESS EMPIRE ONLINE • 0.5"
	content.add_child(title)
	city_label = Label.new()
	content.add_child(city_label)
	money_label = Label.new()
	content.add_child(money_label)
	info = Label.new()
	content.add_child(info)
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message_label)
	actions = VBoxContainer.new()
	content.add_child(actions)
	var button := Button.new()
	button.text = "Следующий город"
	button.pressed.connect(func() -> void: _load_city(city_index + 1))
	content.add_child(button)
	var help := Label.new()
	help.text = "Карта: перетаскивание • Масштаб: щипок / колесо"
	content.add_child(help)
	var market_panel := PanelContainer.new()
	market_panel.position = Vector2(810, 16)
	market_panel.custom_minimum_size = Vector2(455, 250)
	layer.add_child(market_panel)
	var market_content := VBoxContainer.new()
	market_panel.add_child(market_content)
	var market_title := Label.new()
	market_title.text = "ЭКОНОМИКА ХОЛДИНГА • ПРОТОТИП"
	market_content.add_child(market_title)
	economy_label = Label.new()
	economy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	market_content.add_child(economy_label)
	var day_button := Button.new()
	day_button.text = "▶ Следующий игровой день"
	day_button.pressed.connect(_advance_day)
	market_content.add_child(day_button)
	pause_button = Button.new()
	pause_button.text = "⏸ Приостановить время"
	pause_button.pressed.connect(_toggle_timer)
	market_content.add_child(pause_button)
	var ship_button := Button.new()
	ship_button.text = "🚚 Отправить 10 хлеба в следующий город"
	ship_button.pressed.connect(_send_bread)
	market_content.add_child(ship_button)

func _iso(tile: Vector2) -> Vector2:
	return Vector2((tile.x - tile.y) * TILE_W * 0.5, (tile.x + tile.y) * TILE_H * 0.5)

func _draw() -> void:
	for y in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			var tile := Vector2i(x, y)
			var pos := _iso(Vector2(tile))
			var kind: String = cells.get(tile, "Свободный участок")
			var road := kind == "Дорога"
			var base := Color("#6e777b") if road else Color("#88b98c")
			if not road and (x + y) % 4 == 0:
				base = Color("#80af83")
			var diamond := PackedVector2Array([
				pos + Vector2(0, -TILE_H * 0.5),
				pos + Vector2(TILE_W * 0.5, 0),
				pos + Vector2(0, TILE_H * 0.5),
				pos + Vector2(-TILE_W * 0.5, 0)
			])
			draw_colored_polygon(diamond, base)
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("#527b61"), 0.8)
			if road:
				_draw_road(pos, x, y)
			elif kind == "Дерево":
				_draw_tree(pos)
			elif COLORS.has(kind):
				_draw_building(pos, kind)
			if company.owns(city_index, tile):
				var built: String = company.building_at(city_index, tile)
				if built != "":
					_draw_building(pos, built)
				draw_circle(pos + Vector2(0, 10), 4, Color("#ffd55b"))
			if selected == tile:
				draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("#ffe175"), 3.0)

func _draw_road(pos: Vector2, x: int, y: int) -> void:
	if x % CityGenerator.ROAD_STEP == 0 and y % CityGenerator.ROAD_STEP != 0:
		draw_line(pos + Vector2(-9, -4), pos + Vector2(9, 4), Color("#e1d9b1"), 1.4)
	elif y % CityGenerator.ROAD_STEP == 0 and x % CityGenerator.ROAD_STEP != 0:
		draw_line(pos + Vector2(9, -4), pos + Vector2(-9, 4), Color("#e1d9b1"), 1.4)

func _draw_tree(pos: Vector2) -> void:
	draw_line(pos, pos + Vector2(0, -24), Color("#72573b"), 5.0)
	draw_circle(pos + Vector2(0, -29), 15, Color("#3e8153"))
	draw_circle(pos + Vector2(-6, -34), 9, Color("#58a46a"))

func _draw_building(pos: Vector2, kind: String) -> void:
	var height := 30.0
	if kind == "Завод" or kind == "Офис":
		height = 48.0
	var color: Color = COLORS[kind]
	var left := pos + Vector2(-24, -8)
	var right := pos + Vector2(24, -8)
	var front := pos + Vector2(0, 5)
	var top := Vector2(0, -height)
	draw_colored_polygon(PackedVector2Array([left, front, front + top, left + top]), color.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([front, right, right + top, front + top]), color.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([left + top, front + top, right + top, pos + Vector2(0, -height - 21)]), color.lightened(0.25))
	draw_rect(Rect2(pos + Vector2(-13, -height + 4), Vector2(7, 10)), Color("#d6ecf0"))
	draw_rect(Rect2(pos + Vector2(8, -height + 4), Vector2(7, 10)), Color("#d6ecf0"))
	if kind == "Завод":
		draw_rect(Rect2(pos + Vector2(-17, -height - 29), Vector2(8, 22)), Color("#aab0b4"))
		draw_rect(Rect2(pos + Vector2(-17, -height - 29), Vector2(8, 4)), Color("#d58d65"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				moved_since_press = false
		else:
			if touches.size() == 1 and not moved_since_press:
				_select_at(event.position)
			touches.erase(event.index)
			previous_pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		moved_since_press = true
		if touches.size() == 1:
			camera.position -= event.relative / camera.zoom
		elif touches.size() == 2:
			var values := touches.values()
			var distance: float = (values[0] as Vector2).distance_to(values[1] as Vector2)
			if previous_pinch_distance > 0.0:
				_set_zoom(camera.zoom.x * distance / previous_pinch_distance)
			previous_pinch_distance = distance
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(camera.zoom.x * 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(camera.zoom.x / 1.12)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			last_mouse = event.position
			if event.pressed:
				moved_since_press = false
			elif not moved_since_press:
				_select_at(event.position)
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(last_mouse) > 2.0:
			moved_since_press = true
		camera.position -= (event.position - last_mouse) / camera.zoom
		last_mouse = event.position

func _set_zoom(value: float) -> void:
	var z := clampf(value, 0.35, 2.0)
	camera.zoom = Vector2(z, z)

func _select_at(screen_position: Vector2) -> void:
	var world: Vector2 = get_canvas_transform().affine_inverse() * screen_position
	var x := world.x / TILE_W + world.y / TILE_H
	var y := world.y / TILE_H - world.x / TILE_W
	var tile := Vector2i(roundi(x), roundi(y))
	if tile.x < 0 or tile.y < 0 or tile.x >= MAP_SIZE or tile.y >= MAP_SIZE:
		return
	selected = tile
	var kind: String = cells.get(tile, "Свободный участок")
	info.text = "Участок %d:%d • %s" % [tile.x, tile.y, kind]
	message_label.text = ""
	_update_actions()
	queue_redraw()

func _update_actions() -> void:
	if money_label == null or actions == null:
		return
	money_label.text = "Мой холдинг | %d ₽ | Участков: %d" % [company.cash, company.owned.size()]
	_refresh_economy_ui()
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	if selected.x < 0:
		return
	var kind: String = cells.get(selected, "Свободный участок")
	if company.owns(city_index, selected):
		var building := company.building_at(city_index, selected)
		if building == "":
			for building_type in ["Магазин", "Склад", "Завод"]:
				_add_action("Построить %s (%d ₽)" % [building_type, CompanyState.CONSTRUCTION[building_type]], _construct.bind(building_type))
		else:
			info.text = "Ваш участок %d:%d • %s" % [selected.x, selected.y, building]
	elif kind == "Свободный участок":
		_add_action("Купить участок (%d ₽)" % CompanyState.LAND_PRICE, _buy_land)

func _add_action(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	actions.add_child(button)

func _buy_land() -> void:
	var kind: String = cells.get(selected, "Свободный участок")
	message_label.text = company.buy(city_index, selected, kind)
	_update_actions()
	queue_redraw()

func _construct(kind: String) -> void:
	message_label.text = company.construct(city_index, selected, kind)
	_update_actions()
	queue_redraw()

func _advance_day() -> void:
	var report: Dictionary = company.advance_day()
	var cashflow: int = int(report.get("cashflow", 0))
	message_label.text = "День %d: выручка %d ₽, прибыль %+d ₽, денежный поток %+d ₽" % [
		int(report["day"]), int(report["revenue"]), int(report["profit"]), cashflow
	]
	_update_actions()
	queue_redraw()

func _send_bread() -> void:
	var target := (city_index + 1) % CityGenerator.CITIES.size()
	message_label.text = company.send_goods(city_index, target, "Хлеб", 10)
	_update_actions()

func _toggle_timer() -> void:
	day_timer.paused = not day_timer.paused
	pause_button.text = "▶ Возобновить время" if day_timer.paused else "⏸ Приостановить время"

func _refresh_economy_ui() -> void:
	if economy_label == null:
		return
	var city_market: Dictionary = company.market(city_index)
	var stock: Dictionary = city_market["stock"]
	var daily: Dictionary = company.last_report.get("cities", {}).get(str(city_index), {})
	var realized: int = int(daily.get("profit", 0))
	var flow: int = int(daily.get("revenue", 0)) - int(daily.get("expenses", 0))
	var city_name: String = CityGenerator.CITIES[city_index]["name"]
	economy_label.text = (
		"%s • День %d (авто: 15 секунд)\n" % [city_name, company.day] +
		"Запасы: зерно %d • хлеб %d • молоко %d\n" % [int(stock["Зерно"]), int(stock["Хлеб"]), int(stock["Молоко"])] +
		"Склад: %d / %d ед.\n" % [CompanyState.Economy.stock_total(city_market), company.storage_capacity(city_index)] +
		"Спрос жителей: хлеб %d • молоко %d ед./день\n" % [int(daily.get("bread_demand", CompanyState.Economy.CITY_BREAD_DEMAND[city_index])), int(daily.get("milk_demand", CompanyState.Economy.CITY_MILK_DEMAND[city_index]))] +
		"Продано: хлеб %d • молоко %d\n" % [int(daily.get("sold_bread", 0)), int(daily.get("sold_milk", 0))] +
		"Выручка: %d ₽ | Расходы: %d ₽\n" % [int(daily.get("revenue", 0)), int(daily.get("expenses", 0))] +
		"Прибыль (учёт себестоимости): %+d ₽\n" % realized +
		"Денежный поток: %+d ₽\n" % flow +
		"Бюджет покупателей: %d ₽\n" % int(city_market["residents_cash"]) +
		"Поставщики: зерно %d • молоко %d\n" % [int(city_market["supplier_stock"]["Зерно"]), int(city_market["supplier_stock"]["Молоко"])] +
		"Цены: хлеб 155 ₽, молоко 180 ₽\n" +
		"Расчётный баланс, не реальные рыночные цены."
	)
