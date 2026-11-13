extends RefCounted
## Pure visual metadata: never writes ownership or economy.
static func district(tile: Vector2i) -> int:
    return posmod(tile.x / 7 + tile.y / 7, 3)

static func level(tile: Vector2i, kind: String) -> int:
    if kind in ["Завод", "Офис", "Жилой дом"]:
        return 1 + posmod(tile.x * 13 + tile.y * 7, 3)
    return 1

static func detail_for_zoom(zoom: float) -> int:
    return 0 if zoom < 0.55 else 1 if zoom < 1.05 else 2

static func terrain_tint(tile: Vector2i, kind: String) -> Color:
    if kind == "Дорога":
        return Color("#58636a")
    var seed := posmod(tile.x * 37 + tile.y * 73 + tile.x * tile.y * 3, 11)
    return [Color("#7f9f79"), Color("#86a780"), Color("#789b76"), Color("#8ca981")][seed % 4]


static func detail_budget(zoom: float, quality: int) -> int:
    if zoom < 0.72:
        return 0
    if quality <= 0:
        return 1
    return 2 if zoom >= 1.05 and quality >= 2 else 1


static func draw_ground(canvas: Node2D, pos: Vector2, tile: Vector2i, kind: String, zoom: float) -> void:
    var detail := detail_for_zoom(zoom)
    if kind == "Дорога":
        if detail >= 1:
            var edge := Color("#a5b2ae")
            canvas.draw_line(pos + Vector2(-45, -2), pos + Vector2(-3, 19), edge, 2.0)
            canvas.draw_line(pos + Vector2(3, 19), pos + Vector2(45, -2), edge, 2.0)
        if detail >= 2 and posmod(tile.x + tile.y, 3) == 0:
            canvas.draw_circle(pos + Vector2(29, -9), 2.0, Color("#e6dfbc"))
            canvas.draw_line(pos + Vector2(-31,-8),pos + Vector2(-20,-3),Color("#a9b3b1"),1.0)
    elif kind == "Дерево":
        if detail >= 1:
            canvas.draw_circle(pos + Vector2(22, 6), 5, Color("#477c58"))
            canvas.draw_circle(pos + Vector2(-18, 7), 4, Color("#649568"))
    elif kind == "Свободный участок":
        if detail >= 1 and posmod(tile.x * 5 + tile.y * 3, 11) == 0:
            canvas.draw_circle(pos + Vector2(14, 2), 3.0, Color("#a6c184"))
        if detail >= 2 and posmod(tile.x + tile.y, 13) == 0:
            canvas.draw_line(pos + Vector2(-15, 7), pos + Vector2(-12, 3), Color("#608c5b"), 2.0)

static func draw_building_shadow(canvas: Node2D, pos: Vector2, tile: Vector2i, zoom: float) -> void:
    if detail_for_zoom(zoom) == 0:
        return
    canvas.draw_colored_polygon(PackedVector2Array([
        pos + Vector2(-20, 6), pos + Vector2(18, 13),
        pos + Vector2(35, 6), pos + Vector2(-2, -2)
    ]), Color(0.12, 0.21, 0.19, 0.21))

static func draw_business_activity(canvas: Node2D, pos: Vector2, kind: String, zoom: float) -> void:
    # Ambient business signs only: never implies server-side production status.
    if detail_for_zoom(zoom) < 2:
        return
    if kind == "Магазин":
        canvas.draw_rect(Rect2(pos + Vector2(-19, -6), Vector2(8, 3)), Color("#ffd27d"))
    elif kind == "Завод":
        canvas.draw_circle(pos + Vector2(16, -47), 3.0, Color("#d5e0e5"))
    elif kind == "Автосалон":
        canvas.draw_rect(Rect2(pos + Vector2(-18, 8), Vector2(17, 4)), Color("#5c8796"))
    elif kind == "Склад":
        canvas.draw_rect(Rect2(pos + Vector2(18, 3), Vector2(9, 6)), Color("#cda77b"))