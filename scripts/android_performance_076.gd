extends Node
## Local FPS adaptation, cosmetic only. No server commands.
signal quality_changed(level: int)
var game: Node2D
var auto_enabled := true
var level := 1
var frames := 0
var elapsed := 0.0
var smoothed_fps := 60.0
var low_samples := 0
var high_samples := 0
var change_cooldown := 0.0

func _ready() -> void:
    game = get_parent()
    set_process(true)

func _process(delta: float) -> void:
    if delta <= 0.0:
        return
    frames += 1
    elapsed += delta
    change_cooldown = maxf(0.0, change_cooldown - delta)
    if elapsed < 2.0:
        return
    smoothed_fps = float(frames) / elapsed
    frames = 0
    elapsed = 0.0
    if not auto_enabled or change_cooldown > 0.0:
        return
    low_samples = low_samples + 1 if smoothed_fps < 27.0 else 0
    high_samples = high_samples + 1 if smoothed_fps > 53.0 else 0
    if low_samples >= 3 and level > 0:
        apply_quality(level - 1)
    elif high_samples >= 8 and level < 2:
        apply_quality(level + 1)

func apply_quality(next_level: int) -> void:
    level = clampi(next_level, 0, 2)
    low_samples = 0
    high_samples = 0
    change_cooldown = 18.0
    game.get_node("CityLife25D").detail_quality = level
    game.atmosphere.set_quality(level)
    game.queue_redraw()
    quality_changed.emit(level)

func toggle_auto() -> void:
    auto_enabled = not auto_enabled
    if auto_enabled:
        low_samples = 0
        high_samples = 0