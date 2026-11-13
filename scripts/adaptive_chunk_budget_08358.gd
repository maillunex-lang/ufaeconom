extends RefCounted
## Cosmetic streaming policy. Conservative FPS hysteresis, no gameplay state.
static func capacity(fps: float, previous: int) -> int:
    if not is_finite(fps) or fps <= 0.0:
        return 0
    if fps < 24.0:
        return 0
    if fps < 39.0:
        return 1
    if previous == 0 and fps < 45.0:
        return 1
    if previous == 1 and fps < 48.0:
        return 1
    return 2

static func frame_budget(fps: float, previous: int, frame_index: int) -> int:
    var count := capacity(fps, previous)
    # Under stress, spread expensive canvas construction across frames.
    if count == 1 and frame_index % 2 != 0:
        return 0
    return count
