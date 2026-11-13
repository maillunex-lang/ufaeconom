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
    game.company.save_path = "user://living080_test.json"
    game.company.legacy_save_path = "user://living080_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var panel = game.tycoon_panel
    check(panel.tabs.get_tab_count() >= 8, "competitors tab missing")
    check(panel.tabs.get_tab_title(7) == "Конкуренты", "competitors tab title wrong")
    check(panel.pages.size() >= 8, "scrollable pages not present")
    check(not panel.panel.visible, "unauthenticated panel visible")
    check(game.mmo_panel.client.snapshot.is_empty(), "offline UI must not fabricate economy")
    panel.refresh()
    check(game.mmo_panel.client.snapshot.is_empty(), "refresh mutated server snapshot")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("LIVING_BUSINESS_080_UI_TESTS_PASSED")
    quit(1 if failures else 0)