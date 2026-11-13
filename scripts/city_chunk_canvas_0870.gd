extends Node2D
## Cached draw commands for a static 16x16 district. No plots or MMO data.
const Land = preload("res://scripts/city_land.gd")
const CityDetail = preload("res://scripts/city_detail_075.gd")
const CityGenerator = preload("res://scripts/city_generator.gd")
var city: Node2D
var chunk: Vector2i
var budget := 0
var zoom := 0.8

func configure(owner: Node2D, coords: Vector2i, detail: int, camera_zoom: float) -> void:
    city = owner
    chunk = coords
    budget = detail
    zoom = camera_zoom
    z_index = -1
    queue_redraw()

func set_detail(detail: int, camera_zoom: float) -> void:
    if budget != detail or (budget > 1 and absf(zoom - camera_zoom) > 0.12):
        budget = detail
        zoom = camera_zoom
        queue_redraw()

func _draw() -> void:
    if city == null:
        return
    for y in range(chunk.y * Land.CHUNK, (chunk.y + 1) * Land.CHUNK):
        for x in range(chunk.x * Land.CHUNK, (chunk.x + 1) * Land.CHUNK):
            var tile := Vector2i(x, y)
            var data: Dictionary = city._static_tile_data(tile)
            draw_colored_polygon(data["diamond"], data["tint"])
            if budget > 0:
                CityDetail.draw_ground(self, data["pos"], tile, data["kind"], zoom if budget > 1 else 0.8)
            if budget > 1:
                draw_polyline(data["outline"], Color("#527b61"), 0.8)
            # Roads and trees are immutable world decoration. Cache their draw
            # commands together with the ground, never in the dynamic layer.
            if data["kind"] == "Дорога":
                _draw_road(data["pos"], x, y)
            elif data["kind"] == "Дерево":
                _draw_tree(data["pos"], tile)

func _draw_road(pos: Vector2, x: int, y: int) -> void:
    if budget <= 0:
        return
    var step: int = CityGenerator.ROAD_STEP
    if x % step != 0 and y % step != 0:
        return
    if x % step == 0 and y % step != 0:
        draw_line(pos + Vector2(-19, -9), pos + Vector2(19, 9), Color("#a3b0ae"), 2.0)
        if budget > 1 and y % 3 == 0:
            draw_line(pos + Vector2(-6, -3), pos + Vector2(6, 3), Color("#d8cfac"), 1.4)
    elif y % step == 0 and x % step != 0:
        draw_line(pos + Vector2(19, -9), pos + Vector2(-19, 9), Color("#a3b0ae"), 2.0)
        if budget > 1 and x % 3 == 0:
            draw_line(pos + Vector2(6, -3), pos + Vector2(-6, 3), Color("#d8cfac"), 1.4)
    elif budget > 1:
        for offset in [-8.0, 0.0, 8.0]:
            draw_line(pos + Vector2(offset - 7, -6), pos + Vector2(offset + 7, 0), Color("#b7c0bb"), 2.0)


func _draw_tree(pos: Vector2, tile: Vector2i) -> void:
    if budget <= 0:
        return
    var variant := posmod(tile.x * 17 + tile.y * 29, 5)
    var crown := 12.0 + float(variant)
    if budget > 1:
        draw_colored_polygon(PackedVector2Array([
            pos + Vector2(-crown, 2), pos + Vector2(0, 6),
            pos + Vector2(crown + 7, 4), pos + Vector2(5, -1)
        ]), Color(0.12, 0.24, 0.18, 0.22))
        draw_line(pos, pos + Vector2(0, -23), Color("#695b48"), 4.0)
    draw_circle(pos + Vector2(0, -27), crown, Color("#365f49"))
    if budget > 1:
        draw_circle(pos + Vector2(-5, -32), crown * 0.75, Color("#4e8261"))
        draw_circle(pos + Vector2(4, -36), crown * 0.45, Color("#6c9a70"))