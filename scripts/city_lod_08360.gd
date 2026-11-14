extends RefCounted
## Hysteresis keeps medium zoom from toggling silhouettes each frame.
static func stable(zoom: float, quality: int, previous: int) -> int:
    if quality <= 0:
        return 0
    if previous <= 0:
        if zoom < 0.77:
            return 0
    elif zoom < 0.67:
        return 0
    if quality == 1:
        return 1
    if previous >= 2:
        return 1 if zoom < 0.99 else 2
    return 2 if zoom > 1.11 else 1
