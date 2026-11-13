extends Node2D
## Cached draw commands for a static 16x16 district. No plots or MMO data.
const Land = preload("res://scripts/city_land.gd")
const CityDetail = preload("res://scripts/city_detail_075.gd")
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