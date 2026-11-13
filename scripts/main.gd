extends Node2D
## Offline calendar prototype: 24 real hours = 30 game days, catch-up on load.
const SafeArea = preload("res://scripts/mobile_safe_area.gd")
const Land = preload("res://scripts/city_land.gd")
const CityGenerator = preload("res://scripts/city_generator.gd")
const BuildingArt = preload("res://scripts/building_art.gd")
const CityDetail075 = preload("res://scripts/city_detail_075.gd")
const CityLife25D = preload("res://scripts/city_life_25d.gd")
const Atmosphere25D = preload("res://scripts/city_atmosphere_25d.gd")
const CompanyState = preload("res://scripts/company_state.gd")
const Calendar = preload("res://scripts/game_calendar.gd")
const MMOPanel = preload("res://scripts/mmo_panel.gd")
const AndroidHUD074 = preload("res://scripts/android_hud_074.gd")
const TycoonPanel077 = preload("res://scripts/tycoon_panel_077.gd")
const SmartCity076 = preload("res://scripts/smart_city_076.gd")
const AndroidPerformance076 = preload("res://scripts/android_performance_076.gd")
const TILE_W := 96.0
const TILE_H := 48.0
const MAP_SIZE := 32
const COLORS := {
	"Жилой дом": Color("#e7cba2"),
	"Магазин": Color("#5e9fb8"),
	"Склад": Color("#b18d64"),
	"Завод": Color("#8595a2"),
	"Офис": Color("#a9bfc9"),
	"Шахта": Color("#b48b57"),
	"Исследовательский центр": Color("#9a91d3"),
	"Автосалон": Color("#62b9c8")
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
var touch_origin := Vector2.ZERO
var touch_start_msec := 0
var last_tap_msec := -10000
var last_tap_position := Vector2.ZERO
var pinch_center := Vector2.ZERO
var pending_zoom_anchor := Vector2.ZERO
var zoom_anchor_valid := false
const TAP_DRAG_THRESHOLD := 12.0
const DOUBLE_TAP_INTERVAL_MS := 320
var info: Label
var city_label: Label
var mmo_panel
var atmosphere: Node2D
var visual_quality := 1
var construction_preview := ""
var visual_detail := 1
var android_hud: CanvasLayer
var tycoon_panel: CanvasLayer
var performance: Node
var target_zoom := 0.8
var camera_debug: Label
const CAMERA_MIN_ZOOM := 0.52
const CAMERA_MAX_ZOOM := 2.0
const CAMERA_ZOOM_RESPONSE := 13.0

func _ready() -> void:
	camera = Camera2D.new()
	camera.position = Vector2(0, 650)
	camera.zoom = Vector2(0.8, 0.8)
	target_zoom = 0.8
	add_child(camera)
	camera.make_current()
	var traffic := CityLife25D.new()
	traffic.name = "CityLife25D"
	add_child(traffic)
	atmosphere = Atmosphere25D.new()
	atmosphere.name = "CityAtmosphere25D"
	add_child(atmosphere)
	_build_ui()
	mmo_panel = MMOPanel.new()
	add_child(mmo_panel)
	tycoon_panel = TycoonPanel077.new()
	add_child(tycoon_panel)
	mmo_panel.client.snapshot_ready.connect(_on_world_snapshot)
	mmo_panel.client.disconnected.connect(_on_world_logout)
	company.load_game()
	var catchup: Dictionary = company.sync_calendar(int(Time.get_unix_time_from_system()))
	_load_city(company.city_index)
	android_hud = AndroidHUD074.new()
	android_hud.name = "AndroidHUD074"
	add_child(android_hud)
	android_hud.attach_legacy()
	performance = AndroidPerformance076.new()
	performance.name = "AndroidPerformance076"
	add_child(performance)
	var debug_layer := CanvasLayer.new()
	debug_layer.name = "CameraDiagnostics"
	add_child(debug_layer)
	camera_debug = Label.new()
	camera_debug.name = "FPSLabel"
	camera_debug.position = Vector2(12, 76)
	camera_debug.add_theme_color_override("font_color", Color("#ffffff"))
	camera_debug.add_theme_color_override("font_shadow_color", Color("#20382c"))
	camera_debug.add_theme_constant_override("shadow_offset_x", 1)
	camera_debug.add_theme_constant_override("shadow_offset_y", 1)
	debug_layer.add_child(camera_debug)
	set_process(true)
	if int(catchup["advanced"]) > 0:
		message_label.text = "Пока вас не было, прошло %d игровых дней" % int(catchup["advanced"])
	day_timer = Timer.new()
	day_timer.wait_time = 30.0
	day_timer.timeout.connect(_sync_calendar)
	add_child(day_timer)
	day_timer.start()

func _load_city(index: int) -> void:
	city_index = posmod(index, CityGenerator.CITIES.size())
	var data: Dictionary = CityGenerator.make_city(city_index)
	cells = data["cells"]
	selected = Vector2i(-1, -1)
	construction_preview = ""
	company.city_index = city_index
	company.save_game()
	city_label.text = "Город: %s (демонстрация)" % data["name"]
	info.text = "Нажмите на участок или здание"
	message_label.text = ""
	_update_actions()
	camera.position = Vector2(0, 700)
	_clamp_camera()
	queue_redraw()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var safe = SafeArea.new()
	safe.name = "MobileSafeArea"
	layer.add_child(safe)
	var content: VBoxContainer = safe.add_panel("CompanyPanel", 390.0, 480.0, false)
	safe.call_deferred("refresh")
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = "BUSINESS EMPIRE ONLINE • ГОРОДСКИЕ КВАРТАЛЫ"
	content.add_child(title)
	city_label = Label.new()
	city_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(city_label)
	money_label = Label.new()
	money_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(money_label)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(info)
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message_label)
	actions = VBoxContainer.new()
	content.add_child(actions)
	var button := Button.new()
	button.custom_minimum_size.y = 48.0
	button.text = "Следующий город"
	button.pressed.connect(func() -> void: _load_city(city_index + 1))
	content.add_child(button)
	var find_plot := Button.new()
	find_plot.text = "Найти свободный участок"
	find_plot.custom_minimum_size.y = 48.0
	find_plot.pressed.connect(_find_free_plot)
	content.add_child(find_plot)
	var find_ore := Button.new()
	find_ore.text = "Найти месторождение"
	find_ore.custom_minimum_size.y = 48.0
	find_ore.pressed.connect(_find_free_plot.bind(true))
	content.add_child(find_ore)
	var visuals := HBoxContainer.new()
	content.add_child(visuals)
	var weather_button := Button.new()
	weather_button.text = "Погода: ясно"
	weather_button.custom_minimum_size.y = 48.0
	weather_button.pressed.connect(func() -> void:
		atmosphere.cycle_weather()
		weather_button.text = ["Погода: ясно", "Погода: дождь", "Погода: снег"][atmosphere.weather]
	)
	visuals.add_child(weather_button)
	var quality_button := Button.new()
	quality_button.text = "Эффекты: средняя"
	quality_button.custom_minimum_size.y = 48.0
	quality_button.pressed.connect(func() -> void:
		visual_quality = (visual_quality + 1) % 3
		atmosphere.set_quality(visual_quality)
		quality_button.text = ["Эффекты: низкая", "Эффекты: средняя", "Эффекты: высокая"][visual_quality]
	)
	visuals.add_child(quality_button)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Карта: перетаскивание • Масштаб: щипок / колесо"
	content.add_child(help)
	var market_content: VBoxContainer = safe.add_panel("EconomyPanel", 455.0, 420.0, true)
	safe.call_deferred("refresh")
	var market_title := Label.new()
	market_title.text = "ЭКОНОМИКА • ЛОКАЛЬНАЯ ДЕМОНСТРАЦИЯ"
	market_content.add_child(market_title)
	economy_label = Label.new()
	economy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	market_content.add_child(economy_label)
	var ship_button := Button.new()
	ship_button.custom_minimum_size.y = 48.0
	ship_button.text = "🚚 Отправить 10 хлеба в следующий город"
	ship_button.pressed.connect(_send_bread)
	market_content.add_child(ship_button)

func _iso(tile: Vector2) -> Vector2:
	return Vector2((tile.x - tile.y) * TILE_W * 0.5, (tile.x + tile.y) * TILE_H * 0.5)

func _draw() -> void:
	# Fill the visible world outside unlocked city chunks with natural terrain.
	# The backing is one polygon, not thousands of off-map tiles.
	var viewport_size := get_viewport_rect().size
	var inverse := get_canvas_transform().affine_inverse()
	var a: Vector2 = inverse * Vector2.ZERO
	var b: Vector2 = inverse * Vector2(viewport_size.x, 0)
	var c: Vector2 = inverse * viewport_size
	var d: Vector2 = inverse * Vector2(0, viewport_size.y)
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), Color("#729b79"))
	var visible := _visible_tile_rect()
	var far_lod := camera.zoom.x < 0.72
	var plots := _city_plots()
	var opened: Dictionary = {}
	for id in _active_chunks():
		opened[id] = true
	for y in range(visible.position.y, visible.end.y):
		for x in range(visible.position.x, visible.end.x):
			var tile := Vector2i(x, y)
			if not opened.has(Land.chunk_key(tile)):
				continue
			var pos := _iso(Vector2(tile))
			var kind: String = Land.kind_at(city_index, tile)
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
			if not far_lod:
				CityDetail075.draw_ground(self, pos, tile, kind, camera.zoom.x)
			if not far_lod:
				draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("#527b61"), 0.8)
			if road:
				if not far_lod:
					_draw_road(pos, x, y)
			elif kind == "Дерево":
				if not far_lod:
					_draw_tree(pos)
			elif COLORS.has(kind):
				if not far_lod:
					CityDetail075.draw_building_shadow(self, pos, tile, camera.zoom.x)
					_draw_building(pos, kind, tile)
				else:
					draw_rect(Rect2(pos + Vector2(-11, -17), Vector2(22, 22)), COLORS[kind])
			if not far_lod and kind == "Свободный участок" and Land.has_ore(city_index, tile):
				draw_circle(pos, 5.0, Color("#c28147"))
			if plots.has(Land.plot_key(tile)):
				var built: String = _building_at(tile)
				if built != "":
					if far_lod:
						draw_rect(Rect2(pos + Vector2(-12, -20), Vector2(24, 24)), COLORS.get(built, Color("#9db7b5")))
					else:
						CityDetail075.draw_building_shadow(self, pos, tile, camera.zoom.x)
						_draw_building(pos, built, tile)
				if not far_lod:
					draw_circle(pos + Vector2(0, 10), 4, Color("#ffd55b") if _owns_plot(tile) else Color("#eabf9a"))
			if selected == tile and construction_preview != "" and _owns_plot(tile) and _building_at(tile) == "":
				BuildingArt.draw(self, pos, "НИИ" if construction_preview == "Исследовательский центр" else construction_preview, 1, true, CityDetail075.district(tile))
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

func _draw_building(pos: Vector2, kind: String, tile: Vector2i) -> void:
	# Procedural visual level does not affect production, land ownership or server state.
	BuildingArt.draw(self, pos, "НИИ" if kind == "Исследовательский центр" else kind, CityDetail075.level(tile, kind), false, CityDetail075.district(tile))
	CityDetail075.draw_business_activity(self, pos, kind, camera.zoom.x)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				moved_since_press = false
				touch_origin = event.position
				touch_start_msec = Time.get_ticks_msec()
			else:
				moved_since_press = true
				previous_pinch_distance = 0.0
		else:
			if touches.size() == 1 and not moved_since_press and event.position.distance_to(touch_origin) < TAP_DRAG_THRESHOLD:
				_handle_tap(event.position)
			touches.erase(event.index)
			previous_pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if event.position.distance_to(touch_origin) > TAP_DRAG_THRESHOLD or touches.size() > 1:
			moved_since_press = true
		if touches.size() == 1 and moved_since_press:
			camera.position -= event.relative / camera.zoom
			_clamp_camera()
		elif touches.size() == 2:
			var values := touches.values()
			var distance: float = (values[0] as Vector2).distance_to(values[1] as Vector2)
			if previous_pinch_distance > 0.0:
				_set_zoom_at(target_zoom * distance / previous_pinch_distance,
					((values[0] as Vector2) + (values[1] as Vector2)) * 0.5)
			previous_pinch_distance = distance
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom_at(target_zoom * 1.12, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom_at(target_zoom / 1.12, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			last_mouse = event.position
			if event.pressed:
				moved_since_press = false
			elif not moved_since_press:
				_handle_tap(event.position)
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(last_mouse) > 2.0:
			moved_since_press = true
		camera.position -= (event.position - last_mouse) / camera.zoom
		_clamp_camera()
		last_mouse = event.position
	queue_redraw()

func _set_zoom(value: float) -> void:
	target_zoom = clampf(value, CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)


func _set_zoom_at(value: float, screen_position: Vector2) -> void:
	var old := target_zoom
	_set_zoom(value)
	if not is_equal_approx(old, target_zoom):
		pending_zoom_anchor = screen_position
		zoom_anchor_valid = true


func _handle_tap(screen_position: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - last_tap_msec <= DOUBLE_TAP_INTERVAL_MS and screen_position.distance_to(last_tap_position) <= 36.0:
		var world := get_canvas_transform().affine_inverse() * screen_position
		camera.position = world
		_clamp_camera()
		last_tap_msec = -10000
	else:
		_select_at(screen_position)
		last_tap_msec = now
		last_tap_position = screen_position


func _center_city() -> void:
	var bounds := _city_world_bounds()
	camera.position = bounds.get_center()
	_clamp_camera()
	_set_zoom(0.8)
	queue_redraw()


func _city_world_bounds() -> Rect2:
	var min_x := 0
	var min_y := 0
	var max_x := MAP_SIZE
	var max_y := MAP_SIZE
	for chunk in _active_chunks():
		var coords := str(chunk).split(":")
		if coords.size() != 2:
			continue
		min_x = mini(min_x, int(coords[0]) * Land.CHUNK)
		min_y = mini(min_y, int(coords[1]) * Land.CHUNK)
		max_x = maxi(max_x, (int(coords[0]) + 1) * Land.CHUNK)
		max_y = maxi(max_y, (int(coords[1]) + 1) * Land.CHUNK)
	var points := [_iso(Vector2(min_x, min_y)), _iso(Vector2(min_x, max_y)),
		_iso(Vector2(max_x, min_y)), _iso(Vector2(max_x, max_y))]
	var low: Vector2 = points[0]
	var high: Vector2 = points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)


func _clamp_camera() -> void:
	if camera == null:
		return
	var bounds := _city_world_bounds().grow(250.0)
	var view := get_viewport_rect().size / maxf(camera.zoom.x, CAMERA_MIN_ZOOM)
	# Always keep the central city visible; expanded chunks enlarge the bounds.
	var lower := bounds.position - view * 0.32
	var upper := bounds.end + view * 0.32
	camera.position = camera.position.clamp(lower, upper)


func _process(delta: float) -> void:
	if camera == null:
		return
	var blend := 1.0 - exp(-CAMERA_ZOOM_RESPONSE * maxf(delta, 0.0))
	var previous := camera.zoom.x
	var next := lerpf(previous, target_zoom, blend)
	if absf(next - target_zoom) < 0.001:
		next = target_zoom
	if absf(previous - next) > 0.0001:
		var before := get_canvas_transform().affine_inverse() * pending_zoom_anchor if zoom_anchor_valid else Vector2.ZERO
		camera.zoom = Vector2(next, next)
		if zoom_anchor_valid:
			var after := get_canvas_transform().affine_inverse() * pending_zoom_anchor
			camera.position += before - after
		_clamp_camera()
		if is_equal_approx(next, target_zoom):
			zoom_anchor_valid = false
		queue_redraw()
	if camera_debug != null:
		camera_debug.text = "FPS %d  |  %.1f ms  |  x%.2f  |  LOD %s" % [
			Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1),
			camera.zoom.x, "дальний" if camera.zoom.x < 0.72 else "обычный"]

func _select_at(screen_position: Vector2) -> void:
	var world: Vector2 = get_canvas_transform().affine_inverse() * screen_position
	var x := world.x / TILE_W + world.y / TILE_H
	var y := world.y / TILE_H - world.x / TILE_W
	var tile := Vector2i(roundi(x), roundi(y))
	if not Land.is_open(_active_chunks(), tile):
		return
	selected = tile
	construction_preview = ""
	var kind: String = Land.kind_at(city_index, tile)
	info.text = "Участок %d:%d • %s%s" % [tile.x, tile.y, kind, " • руда" if Land.has_ore(city_index, tile) else ""]
	message_label.text = ""
	_update_actions()
	queue_redraw()

func _update_actions() -> void:
	if money_label == null or actions == null:
		return
	var wallet: int = int(mmo_panel.client.snapshot.get("cash_minor", 0)) / 100 if _online_land() else company.cash
	money_label.text = "Мой холдинг | %d ₽ | Кварталов: %d" % [wallet, _active_chunks().size()]
	_refresh_economy_ui()
	if android_hud != null:
		android_hud.update_values()
		android_hud.update_business()
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	if selected.x < 0:
		return
	var kind: String = Land.kind_at(city_index, selected)
	if _owns_plot(selected):
		var building := _building_at(selected)
		if building == "":
			for building_type in CompanyState.CONSTRUCTION:
				if building_type == "Шахта" and not Land.has_ore(city_index, selected):
					continue
				_add_action("Выбрать %s (%d ₽)" % [building_type, CompanyState.CONSTRUCTION[building_type]], _preview_construction.bind(building_type))
			if construction_preview != "":
				_add_action("Подтвердить: %s" % construction_preview, _confirm_preview)
				_add_action("Отменить предпросмотр", _cancel_preview)
		else:
			info.text = "Ваш участок %d:%d • %s" % [selected.x, selected.y, building]
			if building in ["Шахта", "Исследовательский центр", "Автосалон"]:
				info.text += " • экономическая цепочка ещё не подключена"
	elif kind == "Свободный участок" and not _city_plots().has(Land.plot_key(selected)):
		_add_action("Купить участок (%d ₽)" % CompanyState.LAND_PRICE, _buy_land)

func _add_action(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size.y = 48.0
	button.text = title
	button.pressed.connect(callback)
	actions.add_child(button)

func _buy_land() -> void:
	if mmo_panel != null and mmo_panel.online_active():
		mmo_panel.client.send_command("land.buy", {"city": Land.CITY_IDS[city_index], "x": selected.x, "y": selected.y})
		return
	var kind: String = Land.kind_at(city_index, selected)
	message_label.text = company.buy(city_index, selected, kind)
	_update_actions()
	queue_redraw()

func _preview_construction(kind: String) -> void:
	if selected.x < 0 or not _owns_plot(selected) or _building_at(selected) != "" or not CompanyState.CONSTRUCTION.has(kind):
		return
	if kind == "Шахта" and not Land.has_ore(city_index, selected):
		return
	construction_preview = kind
	message_label.text = "Предпросмотр: %s • подтверждение не отправлено" % kind
	_update_actions()
	queue_redraw()

func _cancel_preview() -> void:
	construction_preview = ""
	_update_actions()
	queue_redraw()

func _confirm_preview() -> void:
	if construction_preview == "" or selected.x < 0 or not _owns_plot(selected) or _building_at(selected) != "":
		return
	var kind := construction_preview
	construction_preview = ""
	_construct(kind)

func _construct(kind: String) -> void:
	construction_preview = ""
	if mmo_panel != null and mmo_panel.online_active():
		mmo_panel.client.send_command("facility.build", {"city": Land.CITY_IDS[city_index], "kind": Land.SERVER_KINDS[kind], "x": selected.x, "y": selected.y})
		return
	message_label.text = company.construct(city_index, selected, kind)
	_update_actions()
	queue_redraw()

func _sync_calendar() -> void:
	var report: Dictionary = company.sync_calendar(int(Time.get_unix_time_from_system()))
	if int(report["advanced"]) > 0:
		message_label.text = "Прошло %d игровых дней • дата %s" % [int(report["advanced"]), str(report["date"])]
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
	if mmo_panel != null and mmo_panel.online_active():
		message_label.text = "Для серверной логистики используйте панель MMO справа."
		return
	var target := (city_index + 1) % CityGenerator.CITIES.size()
	message_label.text = company.send_goods(city_index, target, "Хлеб", 10)
	_update_actions()

func _toggle_timer() -> void:
	# Only used by legacy offline tests. The live MMO calendar cannot be paused by clients.
	day_timer.paused = not day_timer.paused

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
		"%s • %s | 1 месяц = 24 часа\n" % [city_name, Calendar.label(company.day)] +
		"Следующий игровой день через %d мин.\n" % int(ceili(float(Calendar.remaining_seconds(company.last_tick_unix, int(Time.get_unix_time_from_system()))) / 60.0)) +
		"Запасы: зерно %d • хлеб %d • молоко %d\n" % [int(stock["Зерно"]), int(stock["Хлеб"]), int(stock["Молоко"])] +
		"Склад: %d / %d ед.\n" % [CompanyState.Economy.stock_total(city_market), company.storage_capacity(city_index)] +
		"Спрос жителей: хлеб %d • молоко %d ед./день\n" % [int(daily.get("bread_demand", CompanyState.Economy.CITY_BREAD_DEMAND[city_index])), int(daily.get("milk_demand", CompanyState.Economy.CITY_MILK_DEMAND[city_index]))] +
		"Продано: хлеб %d • молоко %d\n" % [int(daily.get("sold_bread", 0)), int(daily.get("sold_milk", 0))] +
		"Выручка: %d ₽ | Расходы: %d ₽\n" % [int(daily.get("revenue", 0)), int(daily.get("expenses", 0))] +
		"Прибыль (учёт себестоимости): %+d ₽\n" % realized +
		"Денежный поток: %+d ₽\n" % flow +
		"Бюджет покупателей: %d ₽\n" % int(city_market["residents_cash"]) +
		"Поставщики: зерно %d • молоко %d\n" % [int(city_market["supplier_stock"]["Зерно"]), int(city_market["supplier_stock"]["Молоко"])] +
		"Цены: хлеб %d ₽, молоко %d ₽\n" % [CompanyState.Dynamics.price(city_market, "Хлеб"), CompanyState.Dynamics.price(city_market, "Молоко")] +
		"Расчётный баланс, не реальные рыночные цены."
	)


func _online_land() -> bool:
	return mmo_panel != null and mmo_panel.online_active() and mmo_panel.client.snapshot.has("land")

func _active_chunks() -> Array:
	if _online_land():
		return mmo_panel.client.snapshot["land"][Land.CITY_IDS[city_index]]["chunks"]
	return company.chunks(city_index)

func _city_plots() -> Dictionary:
	if _online_land():
		return mmo_panel.client.snapshot["land"][Land.CITY_IDS[city_index]]["plots"]
	return company.plots(city_index)

func _owns_plot(tile: Vector2i) -> bool:
	if _online_land():
		return str(_city_plots().get(Land.plot_key(tile), {}).get("owner", "")) == mmo_panel.client.actor
	return company.owns(city_index, tile)

func _building_at(tile: Vector2i) -> String:
	if _online_land():
		var id := str(_city_plots().get(Land.plot_key(tile), {}).get("building", ""))
		var kind := str(_city_plots().get(Land.plot_key(tile), {}).get("kind", ""))
		for label in Land.SERVER_KINDS:
			if Land.SERVER_KINDS[label] == kind:
				return label
		return ""
	return company.building_at(city_index, tile)

func _find_free_plot(ore_only: bool = false) -> void:
	var tile := Land.free_plot(city_index, _active_chunks(), _city_plots(), ore_only)
	if tile.x < 0:
		message_label.text = "Нет подходящих свободных участков в открытых кварталах"
		return
	selected = tile
	construction_preview = ""
	camera.position = _iso(Vector2(tile))
	info.text = "Участок %d:%d • свободен%s" % [tile.x, tile.y, " • руда" if Land.has_ore(city_index, tile) else ""]
	_update_actions()
	queue_redraw()

func _on_world_snapshot(_data: Dictionary) -> void:
	_update_actions()
	queue_redraw()

func _on_world_logout() -> void:
	_update_actions()
	queue_redraw()

func _visible_tile_rect() -> Rect2i:
	var inverse := get_canvas_transform().affine_inverse()
	var extent := get_viewport_rect().size
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in [Vector2.ZERO, Vector2(extent.x, 0), extent, Vector2(0, extent.y)]:
		var world: Vector2 = inverse * corner
		var tile := Vector2(world.x / TILE_W + world.y / TILE_H, world.y / TILE_H - world.x / TILE_W)
		low = low.min(tile)
		high = high.max(tile)
	# Include tall building tops whose ground tile lies below the viewport.
	var start := Vector2i(maxi(0, floori(low.x) - 5), maxi(0, floori(low.y) - 5))
	var finish := Vector2i(mini(Land.LIMIT, ceili(high.x) + 6), mini(Land.LIMIT, ceili(high.y) + 6))
	return Rect2i(start, (finish - start).max(Vector2i.ZERO))