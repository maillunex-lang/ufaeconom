extends SceneTree
var failures := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failures += 1
        push_error(msg)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://qa0837_company.json"
    game.company.legacy_save_path = "user://qa0837_missing.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var hud = game.android_hud
    for dimensions in [Vector2i(1280,720), Vector2i(960,540), Vector2i(800,480), Vector2i(720,420)]:
        root.size = dimensions
        await process_frame
        hud.safe.test_safe_rect = Rect2(48, 16, dimensions.x - 96, dimensions.y - 32)
        hud._layout()
        await process_frame
        var safe_rect: Rect2 = hud.safe.get_global_rect()
        for panel in [hud.top,hud.bottom,hud.menu_overlay,hud.mission_panel,hud.business_panel,hud.construction_panel]:
            check(safe_rect.encloses(panel.get_global_rect()), "panel outside safe area: %s %s safe=%s panel=%s" % [dimensions, panel.name, safe_rect, panel.get_global_rect()])
        check(hud.camera_home.get_global_rect().intersection(hud.bottom.get_global_rect()).get_area() == 0, "home overlaps nav")
        check(hud.construction_toggle.get_global_rect().intersection(hud.bottom.get_global_rect()).get_area() == 0, "plot button overlaps nav")
        hud._resume()
        hud._show_tasks()
        check(hud.mission_panel.visible, "missions panel missing")
        check(not hud.construction_panel.visible and not hud.business_panel.visible, "cards overlap missions")
        check(hud.mission_panel.get_global_rect().intersection(hud.bottom.get_global_rect()).get_area() == 0, "missions overlap nav")
        hud._show_city()
    var before: Vector2 = game.camera.position
    game._unhandled_input(InputEventMouseButton.new())
    var down := InputEventMouseButton.new()
    down.button_index = MOUSE_BUTTON_LEFT
    down.pressed = true
    down.position = Vector2(220,220)
    game._unhandled_input(down)
    var tiny := InputEventMouseMotion.new()
    tiny.position = Vector2(224,222)
    game._unhandled_input(tiny)
    check(game.camera.position.is_equal_approx(before), "mouse jitter moved camera")
    var drag := InputEventMouseMotion.new()
    drag.position = Vector2(260,245)
    game._unhandled_input(drag)
    check(game.mouse_drag_active, "mouse drag threshold ignored")
    var up := InputEventMouseButton.new()
    up.button_index = MOUSE_BUTTON_LEFT
    up.position = Vector2(260,245)
    game._unhandled_input(up)
    check(not game.dragging, "mouse drag not released")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("ANDROID_UX_QA_0837_TESTS_PASSED")
    quit(1 if failures else 0)