extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://camera0831_test.json"
    game.company.legacy_save_path = "user://camera0831_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    check(game.camera_debug != null, "FPS diagnostics missing")
    check(game.get_node_or_null("CameraDiagnostics") != null, "diagnostics canvas missing")
    game._set_zoom(0.1)
    check(is_equal_approx(game.target_zoom, game.CAMERA_MIN_ZOOM), "minimum zoom not clamped")
    for frame in range(45):
        await process_frame
    check(game.camera.zoom.x >= game.CAMERA_MIN_ZOOM - 0.001, "zoom under minimum")
    check(game.camera.zoom.x < 0.72, "far LOD not entered")
    check(game.camera_debug.text.contains("FPS"), "FPS label missing")
    game.camera.position = Vector2(999999, -999999)
    game._clamp_camera()
    var bounds: Rect2 = game._city_world_bounds().grow(250)
    var view: Vector2 = game.get_viewport_rect().size / game.camera.zoom.x
    check(game.camera.position.x <= bounds.end.x + view.x * 0.32 + 1, "camera x escaped")
    check(game.camera.position.y >= bounds.position.y - view.y * 0.32 - 1, "camera y escaped")
    game._set_zoom(100.0)
    check(is_equal_approx(game.target_zoom, game.CAMERA_MAX_ZOOM), "maximum zoom not clamped")
    check(game._visible_tile_rect().size.x >= 0, "visible tile rect invalid")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("CAMERA_PERFORMANCE_0831_TESTS_PASSED")
    quit(1 if failures else 0)