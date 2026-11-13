extends Node2D
## Decorative 2.5D traffic only. No economy or server writes.
const Land = preload("res://scripts/city_land.gd")
const Smart = preload("res://scripts/smart_city_076.gd")
const Visibility = preload("res://scripts/dynamic_visibility_08353.gd")
const W := 96.0
const H := 48.0
var city: Node2D
var clock := 0.0
var redraw_clock := 0.0
var detail_quality := 1
var route_cache: Dictionary = {}
var route_cache_city := -1
var route_cache_chunks := ""
var route_cache_limit := 96
var last_drawn_vehicles := 0
var last_drawn_people := 0

func _ready() -> void:
    city = get_parent()
    z_index = 10

func _process(delta: float) -> void:
    if city == null or city.camera == null:
        return
    if not Visibility.should_animate(city.camera.zoom.x, detail_quality, is_visible_in_tree()):
        return
    clock += delta
    redraw_clock += delta
    if redraw_clock >= (0.24 if detail_quality == 0 else 0.12 if detail_quality == 1 else 0.08):
        redraw_clock = 0.0
        queue_redraw()

func _iso(p: Vector2) -> Vector2:
    return Vector2((p.x-p.y)*W*0.5,(p.x+p.y)*H*0.5)

func _draw() -> void:
    if city.camera == null:
        return
    if not Visibility.should_animate(city.camera.zoom.x, detail_quality, is_visible_in_tree()):
        last_drawn_vehicles = 0
        last_drawn_people = 0
        return
    var rect: Rect2i = city._visible_tile_rect()
    if rect.size.x <= 0 or rect.size.y <= 0:
        return
    var chunks: Array = city._active_chunks()
    var chunk_signature := str(chunks)
    if route_cache_city != city.city_index or route_cache_chunks != chunk_signature:
        route_cache.clear()
        route_cache_city = city.city_index
        route_cache_chunks = chunk_signature
    var open: Dictionary = {}
    for key in chunks:
        open[key] = true
    var vehicle_count := 0
    var drawn_routes := 0
    var max_vehicles := Visibility.actor_budget(detail_quality)
    var max_people := Visibility.actor_budget(detail_quality)
    var people_count := 0
    # Only visible road tiles are inspected; route paths are cached by tile.
    last_drawn_vehicles = 0
    last_drawn_people = 0
    for y in range(rect.position.y,rect.end.y):
        for x in range(rect.position.x,rect.end.x):
            var tile := Vector2i(x,y)
            if not open.has(Land.chunk_key(tile)):
                continue
            if Land.kind_at(city.city_index,tile) != "Дорога":
                continue
            var road_x := x % 7 == 0
            var road_y := y % 7 == 0
            if (x*13+y*19) % 11 == 0 and vehicle_count < max_vehicles:
                var phase := fposmod(clock*(0.42+float((x+y)%3)*0.09)+float((x*7+y)%17)*0.31,1.0)
                var next := Vector2(x+phase,y) if road_y else Vector2(x,y+phase)
                var neighbor := Vector2i(x+1,y) if road_y else Vector2i(x,y+1)
                if not open.has(Land.chunk_key(neighbor)) or Land.kind_at(city.city_index,neighbor) != "Дорога":
                    next = Vector2(x,y)
                var pos := _iso(next)
                var direction := Vector2(W*0.5,H*0.5) if road_y else Vector2(-W*0.5,H*0.5)
                var tint := Color("#dfb879") if (x+y)%3==0 else Color("#7cb7cb")
                if detail_quality >= 1:
                    draw_circle(pos + Vector2(0, 2), 5.0, Color(0.1, 0.15, 0.17, 0.25))
                draw_colored_polygon(PackedVector2Array([pos+Vector2(0,-5),pos+Vector2(7,-2),pos+Vector2(7,2),pos+Vector2(0,0)]),tint)
                draw_line(pos,pos+direction.normalized()*7.0,Color("#415668"),2.0)
                vehicle_count += 1
                # A short deterministic street route for visual delivery vans.
                if detail_quality >= 1 and (x + y) % 9 == 0 and drawn_routes < 5:
                    var target := tile + Vector2i(0, 2) if road_x else tile + Vector2i(2, 0)
                    var route_key := "%d:%d:%d:%d" % [x, y, target.x, target.y]
                    if not route_cache.has(route_key):
                        if route_cache.size() >= route_cache_limit:
                            route_cache.clear()
                        route_cache[route_key] = Smart.route(city.city_index, tile, target, open, 24)
                    var route: Array = route_cache[route_key]
                    if route.size() >= 2:
                        var at := fposmod(clock * 0.25 + float((x + y) % 7) * 0.13, float(route.size() - 1))
                        var idx := int(at)
                        var p := _iso(Vector2(route[idx]).lerp(Vector2(route[idx + 1]), at - float(idx)))
                        draw_rect(Rect2(p + Vector2(-5, -5), Vector2(10, 7)), Color("#c4a46e"))
                        drawn_routes += 1
            if (x*17+y*23)%13 == 0 and people_count < max_people:
                var phase2 := fposmod(clock*0.19+float((x+y)%9)*0.21,1.0)
                var neighbor2 := Vector2i(x+1,y) if road_y else Vector2i(x,y+1)
                var can_walk := open.has(Land.chunk_key(neighbor2)) and Land.kind_at(city.city_index,neighbor2) == "Дорога"
                var p := _iso(Vector2(x+phase2,y) if road_y and can_walk else Vector2(x,y+phase2) if can_walk else Vector2(x,y))
                p += Vector2(0,-8)
                draw_circle(p,2.4,Color("#ead4b4"))
                draw_line(p+Vector2(0,2),p+Vector2(0,7),Color("#5b7792"),2.0)
                people_count += 1
    last_drawn_vehicles = vehicle_count
    last_drawn_people = people_count