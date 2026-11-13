extends SceneTree
const Watchdog = preload("res://scripts/chunk_queue_watchdog_08359.gd")
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
    assert(Watchdog.allowed(60.0, 2, 0, 0.0) == 2)
    assert(Watchdog.allowed(32.0, 1, 0, 0.0) == 1)
    assert(Watchdog.allowed(32.0, 1, 1, 0.0) == 0)
    assert(Watchdog.allowed(10.0, 0, 0, 1.0) == 0)
    assert(Watchdog.allowed(10.0, 0, 1, 1.5) == 1)
    assert(Watchdog.allowed(0.0, 0, 1, 2.0) == 1)
    assert(Watchdog.allowed(10.0, 0, 1, 2.0) <= 1)
    var game = Main.new()
    assert(game.pending_chunk_wait_seconds == 0.0)
    game.pending_chunk_wait_seconds = 5.0
    game._clear_chunk_canvases()
    assert(game.pending_chunk_wait_seconds == 0.0)
    game.free()
    print("CHUNK_QUEUE_WATCHDOG_08359 PASS")
    quit(0)
