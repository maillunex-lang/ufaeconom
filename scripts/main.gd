extends Node2D
## BUSINESS EMPIRE ONLINE 0.1.0: deterministic offline isometric city prototype.
## No network, player accounts, or AI players yet.

const TILE_W := 96.0
const TILE_H := 48.0
const MAP_SIZE := 24
const SEED := 20261113

var camera: Camera2D
var selected: Vector2i = Vector2i(-1, -1)
var buildings: Dictionary = {}
var touches: Dictionary = {}
var previous_pinch_distance := 0.0
var dragging := false
var last_mouse := Vector2.ZERO
var info: Label

func _ready() -> void:
	_generate_city()
	camera = Camera2D.new()
	camera.position = Vector2(0, 250)
	camera.zoom = Vector2(0.75, 0.75)
	add_child(camera)
	camera.make_current()
	_build_ui()
	queue_redraw()

func _generate_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for y in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			if x % 6 == 0 or y % 6 == 0:
				continue
			var roll := rng.randf()
			if roll < 0.13:
				buildings[Vector2i(x, y)] = "Магазин"
			elif roll < 0.27:
				buildings[Vector2i(x, y)] = "Жилой дом"
			elif roll < 0.33:
				buildings[Vector2i(x, y)] = "Склад"
			elif roll < 0.37:
				buildings[Vector2i(x, y)] = "Завод"

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(380, 105)
	layer.add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var title := Label.new()
	title.text = "BUSINESS EMPIRE ONLINE | Прототип 0.1"
	content.add_child(title)
	info = Label.new()
	info.text = "Башкортостан • демонстрационный город\nНажмите на здание, чтобы узнать его тип"
	content.add_child(info)
	var help := Label.new()
	help.text = "Перемещение: пальцем/мышью | Масштаб: щипок/колесо"
	content.add_child(help)

func _iso(tile: Vector2) -> Vector2:
	return Vector2((tile.x - tile.y) * TILE_W * 0.5, (tile.x + tile.y) * TILE_H * 0.5)

func _draw() -> void:
	for y in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			var cell := Vector2i(x, y)
			var pos := _iso(Vector2(cell))
			var is_road := x % 6 == 0 or y % 6 == 0
			var base := Color("#777d7d") if is_road else Color("#87b88a")
			var diamond := PackedVector2Array([
				pos + Vector2(0, -TILE_H * 0.5),
				pos + Vector2(TILE_W * 0.5, 0),
				pos + Vector2(0, TILE_H * 0.5),
				pos + Vector2(-TILE_W * 0.5, 0)
			])
			draw_colored_polygon(diamond, base)
			draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("#537963"), 1.0)
			if buildings.has(cell):
				_draw_building(pos, buildings[cell])
			if selected == cell:
				draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color.YELLOW, 3.0)

func _draw_building(pos: Vector2, kind: String) -> void:
	var height := 30.0
	var color := Color("#d6c3a1")
	if kind == "Магазин":
		color = Color("#4c91b8")
	elif kind == "Склад":
		color = Color("#b98e60")
	elif kind == "Завод":
		color = Color("#7b8994")
		height = 44.0
	var left := pos + Vector2(-23, -8)
	var right := pos + Vector2(23, -8)
	var front := pos + Vector2(0, 4)
	var top := Vector2(0, -height)
	draw_colored_polygon(PackedVector2Array([left, front, front + top, left + top]), color.darkened(0.24))
	draw_colored_polygon(PackedVector2Array([front, right, right + top, front + top]), color.darkened(0.10))
	draw_colored_polygon(PackedVector2Array([left + top, front + top, right + top, pos + Vector2(0, -height - 24)]), color.lightened(0.24))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				_select_at(event.position)
		else:
			touches.erase(event.index)
			previous_pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
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
				_select_at(event.position)
	elif event is InputEventMouseMotion and dragging:
		camera.position -= (event.position - last_mouse) / camera.zoom
		last_mouse = event.position

func _set_zoom(value: float) -> void:
	var zoom_value: float = clampf(value, 0.35, 2.0)
	camera.zoom = Vector2(zoom_value, zoom_value)

func _select_at(screen_position: Vector2) -> void:
	var world := get_global_mouse_position()
	# Screen touch position must be converted through the active canvas transform.
	world = get_canvas_transform().affine_inverse() * screen_position
	var x := world.x / TILE_W + world.y / TILE_H
	var y := world.y / TILE_H - world.x / TILE_W
	var tile := Vector2i(roundi(x), roundi(y))
	if tile.x < 0 or tile.y < 0 or tile.x >= MAP_SIZE or tile.y >= MAP_SIZE:
		return
	selected = tile
	var kind: String = buildings.get(tile, "Свободный участок")
	info.text = "Участок %d:%d | %s\nЭкономика и владение появятся в следующих версиях" % [tile.x, tile.y, kind]
	queue_redraw()
