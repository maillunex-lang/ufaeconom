extends RefCounted
## Wall-clock progress guarantee for cosmetic terrain streaming.
const MAX_WAIT_SECONDS := 1.5
static func allowed(fps: float, capacity: int, frame_index: int, wait_seconds: float) -> int:
    # At most one emergency chunk, regardless of how low FPS becomes.
    if wait_seconds >= MAX_WAIT_SECONDS:
        return 1
    var count := 0
    if fps > 0.0 and is_finite(fps):
        if fps >= 48.0 and capacity >= 2:
            count = 2
        elif fps >= 24.0 and frame_index % 2 == 0:
            count = 1
    return count
