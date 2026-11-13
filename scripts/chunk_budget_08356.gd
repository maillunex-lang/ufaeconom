extends RefCounted
## Deterministic prioritization, center-first to reduce visible pop-in.
static func nearest_first(chunks: Array[Vector2i], camera_world: Vector2, tile_w: float, tile_h: float) -> Array[Vector2i]:
    var ordered := chunks.duplicate()
    ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
        var ca := Vector2(float((a.x + a.y) * 16) * tile_w * 0.5, float((a.y - a.x) * 16) * tile_h * 0.5)
        var cb := Vector2(float((b.x + b.y) * 16) * tile_w * 0.5, float((b.y - b.x) * 16) * tile_h * 0.5)
        return ca.distance_squared_to(camera_world) < cb.distance_squared_to(camera_world)
    )
    return ordered
