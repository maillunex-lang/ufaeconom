extends RefCounted
## Stateless quality decision; FPS measured over two-second windows.
static func decide(level: int, fps: float, low_windows: int, high_windows: int, cooldown: float) -> int:
    if fps < 15.0 and level > 0:
        return 0
    if cooldown > 0.0:
        return level
    if fps < 27.0 and low_windows >= 2:
        return maxi(0, level - 1)
    if fps > 53.0 and high_windows >= 8:
        return mini(2, level + 1)
    return level
