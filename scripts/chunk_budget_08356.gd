extends RefCounted
## Deterministic prioritization, center-first to reduce visible pop-in.
static func nearest_first(chunks: Array[Vector2i], camera_world: Vector2, tile_w: float, tile_h: float, camera_motion: Vector2 = Vector2.ZERO) -> Array[Vector2i]:
    # Motion only affects priority, never the visible set or per-frame budget.
    var lookahead := camera_motion.limit_length(360.0) * 0.65
    var priority_center := camera_world + lookahead
    var ordered := chunks.duplicate()
    ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
        var ca := Vector2(float((a.x - a.y) * 16 + 0) * tile_w * 0.5, float((a.x + a.y) * 16) * tile_h * 0.5)
        var cb := Vector2(float((b.x - b.y) * 16 + 0) * tile_w * 0.5, float((b.x + b.y) * 16) * tile_h * 0.5)
        return ca.distance_squared_to(priority_center) < cb.distance_squared_to(priority_center)
    )
    return ordered
