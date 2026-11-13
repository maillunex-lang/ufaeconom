extends RefCounted
## Pure visibility policy for decorative actors. Never changes game economy.
static func should_animate(zoom: float, quality: int, visible: bool) -> bool:
    return visible and zoom >= 0.72 and quality > 0

static func actor_budget(quality: int) -> int:
    return 0 if quality <= 0 else 32 if quality == 1 else 48
