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
    game.company.save_path = "user://ui0832_test.json"
    game.company.legacy_save_path = "user://ui0832_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var hud = game.android_hud
    check(hud.menu_open, "main menu not shown on launch")
    check(hud.menu_overlay.visible, "main menu overlay hidden")
    check(hud.nav_buttons.size() == 5, "expected five navigation tabs")
    check(hud.camera_home != null, "camera home control missing")
    hud._resume()
    check(not hud.menu_overlay.visible, "resume did not close menu")
    hud._show_menu()
    check(hud.menu_overlay.visible, "menu tab did not open menu")
    hud._resume()
    hud._show_city()
    check(hud.active_tab == "Город", "city tab failed")
    game._set_zoom_at(0.6, Vector2(100, 100))
    check(game.zoom_anchor_valid, "zoom anchor not set")
    check(is_equal_approx(game.target_zoom, 0.6), "zoom target incorrect")
    game.camera.position = Vector2(9999, 9999)
    hud._center_city()
    check(game.camera.position.distance_to(game._city_world_bounds().get_center()) < 100, "camera home not centered")
    check(game.get_node_or_null("CameraDiagnostics") != null, "FPS diagnostics missing")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("UI_OVERHAUL_0832_TESTS_PASSED")
    quit(1 if failures else 0)