extends SceneTree
var failed := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failed += 1
        push_error(msg)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://ui0834_test.json"
    game.company.legacy_save_path = "user://ui0834_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var hud = game.android_hud
    check(hud.menu_backdrop != null and hud.menu_backdrop.visible, "menu backdrop missing")
    check(hud.menu_scroll != null, "scrollable menu missing")
    check(hud.nav_buttons.size() == 5, "navigation count")
    check(hud.menu_overlay.size.x <= hud.safe.size.x, "menu exceeds safe width")
    check(hud.menu_overlay.size.y <= hud.safe.size.y, "menu exceeds safe height")
    hud._resume()
    check(not hud.menu_backdrop.visible and not hud.menu_overlay.visible, "menu did not close")
    hud._show_menu()
    check(hud.menu_backdrop.visible and hud.menu_overlay.visible, "menu did not reopen")
    hud._resume()
    hud._show_market()
    check(hud.active_tab == "Рынок", "market tab")
    hud._show_city()
    check(hud.active_tab == "Город", "city tab")
    hud._layout()
    check(hud.camera_home.position.x >= 0 and hud.camera_home.position.y >= 0, "home button outside safe area")
    check(hud.business_close != null and hud.business_actions.get_child_count() >= 1, "business card controls missing")
    hud.business_panel.visible = true
    hud.business_close.pressed.emit()
    check(not hud.business_panel.visible, "close card failed")
    game.queue_free()
    await process_frame
    if failed == 0:
        print("UI_POLISH_0834_TESTS_PASSED")
    quit(1 if failed else 0)