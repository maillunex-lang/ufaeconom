extends Node2D
## Offline prototype 0.2: deterministic cities and layered procedural isometric art.
const CityGenerator = preload("res://scripts/city_generator.gd")
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
	_load_city(0)

func _load_city(index: int) -> void:
	city_index = posmod(index, CityGenerator.CITIES.size())
	var data: Dictionary = CityGenerator.make_city(city_index)
	cells = data["cells"]
	selected = Vector2i(-1, -1)
	city_label.text = "Город: %s (демонстрация)" % data["name"]
	info.text = "Нажмите на участок или здание"
	camera.position = Vector2(0, 700)
	queue_redraw()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(350, 150)
	layer.add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var title := Label.new()
	title.text = "BUSINESS EMPIRE ONLINE • 0.2"
	content.add_child(title)
	city_label = Label.new()
	content.add_child(city_label)
	info = Label.new()
	content.add_child(info)
	var button := Button.new()
	button.text = "Следующий город"
	button.pressed.connect(func() -> void: _load_city(city_index + 1))
	content.add_child(button)
	var help := Label.new()
	help.text = "Карта: перетаскивание • Масштаб: щипок / колесо"
	content.add_child(help)

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
	queue_redraw()
