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
    game.company.save_path = "user://market081_test.json"
    game.company.legacy_save_path = "user://market081_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var panel = game.tycoon_panel
    check(panel.tabs.get_tab_count() >= 9, "market analytics tab missing")
    check(panel.tabs.get_tab_title(8) == "Аналитика рынка", "analytics tab title wrong")
    check(panel.pages.size() >= 9, "scrollable analytics panel missing")
    check(not panel.panel.visible, "unauthenticated panel visible")
    check(game.mmo_panel.client.snapshot.is_empty(), "offline UI must not fabricate market")
    panel.refresh()
    check(game.mmo_panel.client.snapshot.is_empty(), "refresh mutated server snapshot")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("MARKET_STRATEGY_081_UI_TESTS_PASSED")
    quit(1 if failures else 0)