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
    game.company.save_path = "user://tycoon077_test.json"
    game.company.legacy_save_path = "user://tycoon077_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var panel = game.tycoon_panel
    check(panel != null, "missing tycoon UI")
    check(panel.tabs.get_tab_count() >= 6, "missing business tabs")
    check(not panel.panel.visible, "panel should start closed")
    panel.toggle()
    check(not panel.panel.visible, "unauthenticated panel opened")
    check(game.mmo_panel.client.snapshot.is_empty(), "test must not fake server state")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("TYCOON_077_UI_TESTS_PASSED")
    quit(1 if failures else 0)