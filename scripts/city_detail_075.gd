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

static func investment_level(snapshot: Dictionary, city: String, tile: Vector2i) -> int:
    if city.is_empty():
        return 0
    var key := "%d:%d" % [floori(float(tile.x) / 16.0), floori(float(tile.y) / 16.0)]
    for district_data in snapshot.get("district_demand", []):
        if str(district_data.get("city", "")) == city and str(district_data.get("district", "")) == key:
            return clampi(int(district_data.get("infrastructure", {}).get("investment_level", 0)), 0, 5)
    return 0


static func draw_investment(canvas: Node2D, pos: Vector2, tile: Vector2i, kind: String, level: int, budget: int) -> void:
    # Purely decorative, deterministic and suppressed at far zoom.
    if budget <= 0 or level <= 0:
        return
    if kind == "Свободный участок" and posmod(tile.x * 13 + tile.y * 7, 9) < level:
        canvas.draw_circle(pos + Vector2(-20, 3), 5.0, Color("#4c9869"))
        canvas.draw_circle(pos + Vector2(-17, -1), 3.0, Color("#81b980"))
        if level >= 3 and budget >= 2:
            canvas.draw_rect(Rect2(pos + Vector2(12, 0), Vector2(12, 3)), Color("#b9c4aa"))
            canvas.draw_circle(pos + Vector2(17, -4), 2.0, Color("#ffe3a3"))
    elif kind == "Дорога" and level >= 2 and posmod(tile.x + tile.y, 7) == 0:
        canvas.draw_circle(pos + Vector2(27, -6), 2.0, Color("#f8d99a"))
        if level >= 4 and budget >= 2:
            canvas.draw_line(pos + Vector2(27, -6), pos + Vector2(27, -20), Color("#6b8580"), 1.5)
            canvas.draw_circle(pos + Vector2(27, -21), 3.0, Color("#ffe6a5"))

static func draw_residential_growth(canvas: Node2D, pos: Vector2, tile: Vector2i, kind: String, tier: int, budget: int) -> void:
    # Decorative infill, not a new owned/constructible building.
    if budget <= 0 or tier <= 0:
        return
    if kind == "Жилой дом" and budget >= 2:
        var height := 5.0 + float(tier) * 2.0
        canvas.draw_rect(Rect2(pos + Vector2(-10, -42 - height), Vector2(20, height)), Color("#c4b9a4"))
        for n in range(tier):
            canvas.draw_rect(Rect2(pos + Vector2(-7 + (n % 3) * 5, -39 - height), Vector2(2, 3)), Color("#f7e0a0"))
    elif kind == "Свободный участок" and tier >= 2 and posmod(tile.x * 19 + tile.y * 23, 23) < tier:
        canvas.draw_rect(Rect2(pos + Vector2(-8, -9), Vector2(16, 10)), Color("#cbbda7"))
        canvas.draw_colored_polygon(PackedVector2Array([
            pos + Vector2(-11, -9), pos + Vector2(0, -18),
            pos + Vector2(11, -9)]), Color("#876d62"))
        if budget >= 2:
            canvas.draw_rect(Rect2(pos + Vector2(-3, -6), Vector2(4, 4)), Color("#f8dda0"))


static func draw_neighborhood_amenities(canvas: Node2D, pos: Vector2, tile: Vector2i, kind: String, tier: int, budget: int) -> void:
    if budget <= 0 or tier <= 0:
        return
    if kind == "Свободный участок" and tier >= 3 and posmod(tile.x * 11 + tile.y * 31, 17) == 0:
        canvas.draw_rect(Rect2(pos + Vector2(-18, 6), Vector2(27, 3)), Color("#b6ad91"))
        canvas.draw_circle(pos + Vector2(-16, 1), 5.0, Color("#4c9361"))
        canvas.draw_circle(pos + Vector2(9, -2), 6.0, Color("#4c9361"))
        if budget >= 2:
            canvas.draw_rect(Rect2(pos + Vector2(-4, 0), Vector2(10, 3)), Color("#8e745b"))
    if kind == "Дорога" and tier >= 4 and posmod(tile.x * 7 + tile.y, 11) == 0:
        canvas.draw_line(pos + Vector2(-26, 1), pos + Vector2(-26, -17), Color("#87958c"), 2.0)
        canvas.draw_circle(pos + Vector2(-26, -18), 3.0, Color("#ffdfa4"))

static func urban_overlay_color(metrics: Dictionary) -> Color:
    var access := clampi(int(metrics.get("transport_access", 0)), 0, 100)
    var congestion := clampi(int(metrics.get("traffic_congestion", 0)), 0, 100)
    if congestion >= 65:
        return Color(0.85, 0.30, 0.22, 0.22)
    if access >= 60:
        return Color(0.20, 0.68, 0.48, 0.16)
    return Color(0.90, 0.72, 0.26, 0.13)


static func draw_urban_overlay(canvas: Node2D, pos: Vector2, tile: Vector2i, metrics: Dictionary, budget: int) -> void:
    if budget <= 0 or metrics.is_empty():
        return
    # Sparse heatmap markers: avoids filling the city with UI colors.
    if posmod(tile.x, 4) != 0 or posmod(tile.y, 4) != 0:
        return
    canvas.draw_colored_polygon(PackedVector2Array([
        pos + Vector2(0, -9), pos + Vector2(16, 0),
        pos + Vector2(0, 9), pos + Vector2(-16, 0)
    ]), urban_overlay_color(metrics))