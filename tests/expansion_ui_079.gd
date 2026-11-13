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
    game.company.save_path = "user://expansion079_test.json"
    game.company.legacy_save_path = "user://expansion079_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var panel = game.tycoon_panel
    check(panel.tabs.get_tab_count() >= 7, "industrial contract tab missing")
    check(panel.recipe_picker.item_count == 6, "industrial recipes missing")
    check(panel.freight_goods.item_count == 8, "industrial freight goods missing")
    check(panel.offer_good.item_count >= 4, "contract offer goods missing")
    check(not panel.panel.visible, "unauthenticated panel visible")
    panel._offer_contract()
    check(game.mmo_panel.client.snapshot.is_empty(), "UI modified server state")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("EXPANSION_079_UI_TESTS_PASSED")
    quit(1 if failures else 0)