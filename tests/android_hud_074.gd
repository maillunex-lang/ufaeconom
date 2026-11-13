extends SceneTree
var failures := 0
func check(ok: bool, reason: String) -> void:
    if not ok:
        failures += 1
        push_error(reason)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://hud074_test.json"
    game.company.legacy_save_path = "user://hud074_legacy.json"
    game.company.reset()
    root.add_child(game)
    await process_frame
    var hud = game.android_hud
    check(hud != null, "HUD missing")
    check(not hud.local_open and not hud.mmo_open, "Legacy panels should start closed")
    check(hud.local_panels.size() == 2, "Missing legacy panels")
    for physical in [Vector2i(1280,720),Vector2i(2160,1080),Vector2i(2400,1080),Vector2i(1440,1080)]:
        root.size = physical
        await process_frame
        for right in [false,true]:
            var logical: Vector2 = root.get_visible_rect().size
            var usable := Rect2(0 if right else 50,0,logical.x-50,logical.y-24)
            hud.safe.test_safe_rect = usable
            hud._layout()
            await process_frame
            for panel in [hud.top,hud.bottom,hud.details]:
                check(usable.encloses(panel.get_global_rect()), "HUD outside safe area %s %s" % [physical,panel.name])
        print("HUD074_SAFE_OK ",physical)
    hud._toggle_local()
    check(hud.local_open and hud.local_panels[0].visible, "Company panel cannot open")
    hud._toggle_mmo()
    check(hud.mmo_open and not hud.local_open, "MMO toggle must close local panel")
    hud._toggle_mmo()
    check(not hud.mmo_open, "MMO panel cannot close")
    game._find_free_plot()
    hud.update_values()
    check(hud.city_text.text.length() > 3, "City label empty")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("HUD074_TESTS_PASSED")
    quit(1 if failures else 0)