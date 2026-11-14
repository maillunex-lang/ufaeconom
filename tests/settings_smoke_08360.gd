extends SceneTree
func _initialize() -> void:
    call_deferred("_check")
func _check() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    await process_frame
    var hud = scene.android_hud
    hud._open_settings()
    assert(hud.settings_open)
    assert(hud.settings_panel.visible)
    assert(not hud.top.visible)
    assert(hud.settings_panel.position.x >= 0)
    assert(hud.settings_panel.position.y >= 0)
    assert(hud.settings_panel.position.x + hud.settings_panel.size.x <= hud.safe.size.x + 1)
    assert(hud.settings_panel.position.y + hud.settings_panel.size.y <= hud.safe.size.y + 1)
    hud._close_settings()
    assert(not hud.settings_open)
    assert(hud.top.visible)
    scene.queue_free()
    print("SETTINGS_SMOKE_08360 PASS")
    quit(0)
