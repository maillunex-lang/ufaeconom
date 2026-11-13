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
    game.company.save_path = "user://automation083_test.json"
    game.company.legacy_save_path = "user://automation083_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var panel = game.tycoon_panel
    check(panel.tabs.get_tab_count() == 11, "automation tab missing")
    check(panel.tabs.get_tab_title(10) == "Автоматизация", "automation tab title wrong")
    check(panel.pages.size() == 11, "automation page missing")
    check(panel.pages[10].has_node("AutomationBudget"), "budget control missing")
    check(panel.pages[10].has_node("AutomationEnabled"), "opt-in control missing")
    check(not panel.panel.visible, "unauthenticated panel visible")
    check(game.mmo_panel.client.snapshot.is_empty(), "offline UI must not fabricate rules")
    panel.refresh()
    check(game.mmo_panel.client.snapshot.is_empty(), "refresh mutated server snapshot")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("BUSINESS_AUTOMATION_083_UI_TESTS_PASSED")
    quit(1 if failures else 0)