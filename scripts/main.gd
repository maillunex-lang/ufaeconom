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
const CityChunkCanvas = preload("res://scripts/city_chunk_canvas_0870.gd")
const CityBackground = preload("res://scripts/city_background_0870.gd")
const CityProfiler = preload("res://scripts/city_profiler_08346.gd")
const ChunkBudget = preload("res://scripts/chunk_budget_08356.gd")
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
# Static terrain metadata cache; dynamic plots, ownership and MMO overlays are never cached.
const TERRAIN_CACHE_LIMIT := 4096
const TERRAIN_CACHE_EVICT := 512
var terrain_cache: Dictionary = {}
var terrain_cache_order: Array[Vector2i] = []
var terrain_cache_evictions := 0
var terrain_cache_hits := 0
var terrain_cache_misses := 0

# Visible static terrain is drawn into persistent per-chunk canvas items.
# Dynamic plots, selection and MMO overlays remain in main._draw().
var static_chunk_nodes: Dictionary = {}
const CHUNKS_PER_FRAME := 2
var pending_chunk_coords: Array[Vector2i] = []
var pending_chunk_budget := 0
var pending_chunk_zoom := 0.8
var chunk_build_count := 0
# Cache only deterministic city layouts, never player-owned plots or economy state.
const CITY_LAYOUT_CACHE_LIMIT := 2
var city_layout_cache: Dictionary = {}
var city_layout_order: Array[int] = []
var city_layout_hits := 0
var city_layout_misses := 0
var visible_render_tiles := 0
var visible_render_buildings := 0
var chunk_sync_elapsed := 0.0
var chunk_sync_requested := true
var last_chunk_camera_position := Vector2.INF
var camera_priority_motion := Vector2.ZERO
var last_chunk_camera_zoom := -1.0
var last_chunk_quality := -1
var last_chunk_visible := Rect2i()

func _clear_chunk_canvases() -> void:
	pending_chunk_coords.clear()
	for node in static_chunk_nodes.values():
		node.queue_free()
	static_chunk_nodes.clear()
	chunk_sync_requested = true
	last_chunk_visible = Rect2i()
	last_chunk_camera_position = Vector2.INF
	camera_priority_motion = Vector2.ZERO

func _sync_chunk_canvases() -> void:
	if camera == null:
		return
	var visible := _visible_tile_rect()
	last_chunk_visible = visible
	last_chunk_camera_position = camera.position
	last_chunk_camera_zoom = camera.zoom.x
	last_chunk_quality = performance.level if performance != null else 1
	var budget := CityDetail075.detail_budget(camera.zoom.x, last_chunk_quality)
	if performance != null and performance.level == 0:
		budget = 0
	var opened: Dictionary = {}
	for key in _active_chunks():
		opened[str(key)] = true
	var wanted: Dictionary = {}
	var missing: Array[Vector2i] = []
	var from_chunk := Vector2i(visible.position.x / Land.CHUNK, visible.position.y / Land.CHUNK)
	var end_chunk := Vector2i((visible.end.x + Land.CHUNK - 1) / Land.CHUNK, (visible.end.y + Land.CHUNK - 1) / Land.CHUNK)
	for cy in range(from_chunk.y, end_chunk.y):
		for cx in range(from_chunk.x, end_chunk.x):
			var key := "%d:%d" % [cx, cy]
			if not opened.has(key):
				continue
			wanted[key] = true
			if not static_chunk_nodes.has(key):
				missing.append(Vector2i(cx, cy))
			else:
				static_chunk_nodes[key].set_detail(budget, camera.zoom.x)
	for key in static_chunk_nodes.keys():
		if not wanted.has(key):
			static_chunk_nodes[key].queue_free()
			static_chunk_nodes.erase(key)
	# Replace outdated requests after camera movement or city switching.
	pending_chunk_coords = ChunkBudget.nearest_first(missing, camera.position, TILE_W, TILE_H, camera_priority_motion)
	pending_chunk_budget = budget
	pending_chunk_zoom = camera.zoom.x

func _build_pending_chunks() -> void:
	if pending_chunk_coords.is_empty():
		return
	var count := mini(CHUNKS_PER_FRAME, pending_chunk_coords.size())
	for i in range(count):
		var coords: Vector2i = pending_chunk_coords.pop_front()
		var key := "%d:%d" % [coords.x, coords.y]
		if static_chunk_nodes.has(key):
			continue
		var node = CityChunkCanvas.new()
		node.name = "Terrain_%d_%d" % [coords.x, coords.y]
		add_child(node)
		node.configure(self, coords, pending_chunk_budget, pending_chunk_zoom)
		static_chunk_nodes[key] = node
		chunk_build_count += 1

func _static_tile_data(tile: Vector2i) -> Dictionary:
	if terrain_cache.has(tile):
		terrain_cache_hits += 1
		return terrain_cache[tile]
	terrain_cache_misses += 1
	var kind: String = Land.kind_at(city_index, tile)
	var pos := _iso(Vector2(tile))
	var diamond := PackedVector2Array([
		pos + Vector2(0, -TILE_H * 0.5),
		pos + Vector2(TILE_W * 0.5, 0),
		pos + Vector2(0, TILE_H * 0.5),
		pos + Vector2(-TILE_W * 0.5, 0)
	])
	var outline := PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]])
	var data := {
		"kind": kind,
		"tint": CityDetail075.terrain_tint(tile, kind),
		"ore": kind == "Свободный участок" and Land.has_ore(city_index, tile),
		"pos": pos,
		"diamond": diamond,
		"outline": outline
	}
	if terrain_cache.size() >= TERRAIN_CACHE_LIMIT:
		# Evict a bounded oldest batch instead of clearing every visible tile.
		for i in range(mini(TERRAIN_CACHE_EVICT, terrain_cache_order.size())):
			terrain_cache.erase(terrain_cache_order[i])
			terrain_cache_evictions += 1
		terrain_cache_order = terrain_cache_order.slice(mini(TERRAIN_CACHE_EVICT, terrain_cache_order.size()))
	terrain_cache[tile] = data
	terrain_cache_order.append(tile)
	return data

func _clear_terrain_cache() -> void:
	terrain_cache.clear()
	terrain_cache_order.clear()
	terrain_cache_evictions = 0
	terrain_cache_hits = 0
	terrain_cache_misses = 0

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
var construction_preview_elapsed := 0.0
var show_available_plots := false
var visual_detail := 1
var android_hud: CanvasLayer
var tycoon_panel: CanvasLayer
var performance: Node
var city_profiler: Node
var target_zoom := 0.8
var drag_velocity := Vector2.ZERO
const CAMERA_DRAG_DAMPING := 16.0
var camera_debug: Label
var fps_ui_elapsed := 0.0
var fps_ui_frames := 0
var mouse_press_origin := Vector2.ZERO
var mouse_last_position := Vector2.ZERO
var mouse_drag_active := false
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
	var background = CityBackground.new()
	background.name = "CityBackground"
	add_child(background)
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
	city_profiler = CityProfiler.new()
	city_profiler.name = "CityProfiler08346"
	add_child(city_profiler)
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

func _city_layout(index: int) -> Dictionary:
	var normalized := posmod(index, CityGenerator.CITIES.size())
	if city_layout_cache.has(normalized):
		city_layout_hits += 1
		return city_layout_cache[normalized]
	city_layout_misses += 1
	var layout: Dictionary = CityGenerator.make_city(normalized)
	if city_layout_cache.size() >= CITY_LAYOUT_CACHE_LIMIT:
		city_layout_cache.erase(city_layout_order.pop_front())
	city_layout_cache[normalized] = layout
	city_layout_order.append(normalized)
	return layout

func _clear_city_layout_cache() -> void:
	city_layout_cache.clear()
	city_layout_order.clear()
	city_layout_hits = 0
	city_layout_misses = 0

func _load_city(index: int) -> void:
	var normalized := posmod(index, CityGenerator.CITIES.size())
	# Re-selecting the active city should not recreate its terrain or reset the camera.
	if normalized == city_index and not cells.is_empty():
		return
	city_index = normalized
	_clear_terrain_cache()
	_clear_chunk_canvases()
	var data: Dictionary = _city_layout(city_index)
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
	var draw_started_us := Time.get_ticks_usec()
    # Backing and static ground are separate cached canvas items.
    # Only dynamic city objects are rebuilt in this draw.
	var visible := _visible_tile_rect()
	var detail_budget := CityDetail075.detail_budget(camera.zoom.x, performance.level if performance != null else 1)
	var building_lod := CityDetail075.building_lod(camera.zoom.x, performance.level if performance != null else 1)
	var far_lod := detail_budget == 0
	# At emergency quality avoid per-tile decoration even at close zoom.
	if performance != null and performance.level == 0:
		far_lod = true
		detail_budget = 0
		building_lod = 0
	var plots := _city_plots()
	var active_chunks := _active_chunks()
	visible_render_tiles = 0
	visible_render_buildings = 0
	var invested_levels: Dictionary = {}
	var residential_tiers: Dictionary = {}
	var urban_metrics: Dictionary = {}
	if mmo_panel != null and mmo_panel.online_active():
		for district_data in mmo_panel.client.snapshot.get("district_demand", []):
			if str(district_data.get("city", "")) == Land.CITY_IDS[city_index]:
				var key := str(district_data.get("district", ""))
				invested_levels[key] = clampi(int(district_data.get("infrastructure", {}).get("investment_level", 0)), 0, 5)
				residential_tiers[key] = clampi(int(district_data.get("residential_tier", 0)), 0, 5)
				urban_metrics[key] = district_data.get("urban_metrics", {})
	var opened: Dictionary = {}
	for id in active_chunks:
		opened[id] = true
	for y in range(visible.position.y, visible.end.y):
		for x in range(visible.position.x, visible.end.x):
			var tile := Vector2i(x, y)
			if not opened.has(Land.chunk_key(tile)):
				continue
			visible_render_tiles += 1
			var static_data := _static_tile_data(tile)
			var pos: Vector2 = static_data["pos"]
			var kind: String = static_data["kind"]
			if COLORS.has(kind):
				visible_render_buildings += 1
				_draw_building_lod(pos, kind, tile, building_lod)
			if not far_lod and bool(static_data["ore"]):
				draw_circle(pos, 5.0, Color("#c28147"))
			if not far_lod and not invested_levels.is_empty():
				var district_key := "%d:%d" % [floori(float(x) / 16.0), floori(float(y) / 16.0)]
				CityDetail075.draw_investment(self, pos, tile, kind, int(invested_levels.get(district_key, 0)), detail_budget)
			if not far_lod and not residential_tiers.is_empty():
				var residential_key := "%d:%d" % [floori(float(x) / 16.0), floori(float(y) / 16.0)]
				var tier := int(residential_tiers.get(residential_key, 0))
				CityDetail075.draw_residential_growth(self, pos, tile, kind, tier, detail_budget)
				CityDetail075.draw_neighborhood_amenities(self, pos, tile, kind, tier, detail_budget)
			if not far_lod and not urban_metrics.is_empty():
				var urban_key := "%d:%d" % [floori(float(x) / 16.0), floori(float(y) / 16.0)]
				CityDetail075.draw_urban_overlay(self, pos, tile, urban_metrics.get(urban_key, {}), detail_budget)
			var plot_id := Land.plot_key(tile)
			var plot_exists := plots.has(plot_id)
			if show_available_plots and not far_lod and kind == "Свободный участок" and not plot_exists:
				draw_polyline(static_data["outline"], Color("#66d5ae"), 1.5)
			if plot_exists:
				var built: String = _building_at(tile)
				if built != "":
					_draw_building_lod(pos, built, tile, building_lod)
				if not far_lod:
					draw_circle(pos + Vector2(0, 10), 4, Color("#ffd55b") if _owns_plot(tile) else Color("#eabf9a"))
			if selected == tile and construction_preview != "" and _owns_plot(tile) and _building_at(tile) == "":
				BuildingArt.draw_preview(self, pos, "НИИ" if construction_preview == "Исследовательский центр" else construction_preview, CityDetail075.district(tile), construction_preview_elapsed)
			if selected == tile:
				draw_polyline(static_data["outline"], Color("#ffe175"), 3.0)
	if city_profiler != null:
		city_profiler.record_draw(Time.get_ticks_usec() - draw_started_us)

func _draw_building_lod(pos: Vector2, kind: String, tile: Vector2i, lod: int) -> void:
	var tint: Color = COLORS.get(kind, Color("#9db7b5"))
	if lod == 0:
		draw_rect(Rect2(pos + Vector2(-12, -20), Vector2(24, 24)), tint)
	elif lod == 1:
		CityDetail075.draw_building_silhouette(self, pos, kind, tint)
	else:
		CityDetail075.draw_building_shadow(self, pos, tile, camera.zoom.x)
		_draw_building(pos, kind, tile)

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
			drag_velocity = -event.relative / camera.zoom
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
				mouse_press_origin = event.position
				mouse_drag_active = false
				moved_since_press = false
			elif not mouse_drag_active:
				_handle_tap(event.position)
	elif event is InputEventMouseMotion and dragging:
		if not mouse_drag_active and event.position.distance_to(mouse_press_origin) >= TAP_DRAG_THRESHOLD:
			mouse_drag_active = true
			moved_since_press = true
		if mouse_drag_active:
			var step: Vector2 = -(event.position - last_mouse) / camera.zoom
			camera.position += step
			drag_velocity = step
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
	# Damp leftover gesture movement without moving the camera after release.
	drag_velocity = drag_velocity.lerp(Vector2.ZERO, 1.0 - exp(-CAMERA_DRAG_DAMPING * maxf(delta, 0.0)))
	# Use displacement since last sync, not just the previous frame.
	# This survives throttled synchronization without accumulating old movement.
	if last_chunk_camera_position.is_finite():
		camera_priority_motion = (camera.position - last_chunk_camera_position).limit_length(360.0)
	else:
		camera_priority_motion = Vector2.ZERO
	chunk_sync_elapsed += delta
	# Update immediately when the camera enters a new tile range, zoom changes,
	# or Android quality switches. Avoid blank terrain while panning quickly.
	var quality: int = performance.level if performance != null else 1
	var camera_changed := camera.position.distance_squared_to(last_chunk_camera_position) > 256.0
	var zoom_changed := absf(camera.zoom.x - last_chunk_camera_zoom) > 0.005
	if chunk_sync_requested or quality != last_chunk_quality or zoom_changed or (camera_changed and _visible_tile_rect() != last_chunk_visible) or chunk_sync_elapsed >= 0.50:
		chunk_sync_elapsed = 0.0
		chunk_sync_requested = false
		_sync_chunk_canvases()
	_build_pending_chunks()
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
	if construction_preview != "" and construction_preview_elapsed < 1.5:
		construction_preview_elapsed += delta
		queue_redraw()
	fps_ui_elapsed += delta
	fps_ui_frames += 1
	if camera_debug != null and (fps_ui_elapsed >= 0.5 or fps_ui_frames >= 30):
		fps_ui_elapsed = 0.0
		fps_ui_frames = 0
		city_profiler.sample(Engine.get_frames_per_second(), static_chunk_nodes.size(), _active_chunks().size(), _city_plots().size(), get_node("CityLife25D").get_child_count())
		var rolling: Dictionary = city_profiler.summary()
		camera_debug.text = "FPS %d (ср. %.0f) | %.1f ms | x%.2f | LOD %s | кварталы %d | здания %d" % [
			Engine.get_frames_per_second(), float(rolling.get("avg_fps", 0.0)), 1000.0 / maxf(Engine.get_frames_per_second(), 1),
			camera.zoom.x, "дальний" if camera.zoom.x < 0.72 else "обычный", static_chunk_nodes.size(), visible_render_buildings]

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
	construction_preview_elapsed = 0.0
	message_label.text = "Предпросмотр: %s • подтверждение не отправлено" % kind
	_update_actions()
	queue_redraw()

func _cancel_preview() -> void:
	construction_preview = ""
	construction_preview_elapsed = 0.0
	_update_actions()
	queue_redraw()

func _confirm_preview() -> void:
	if construction_preview == "" or selected.x < 0 or not _owns_plot(selected) or _building_at(selected) != "":
		return
	var kind := construction_preview
	construction_preview = ""
	construction_preview_elapsed = 0.0
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
	chunk_sync_requested = true
	_update_actions()
	queue_redraw()

func _on_world_logout() -> void:
	chunk_sync_requested = true
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