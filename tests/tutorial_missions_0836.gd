extends SceneTree
const Missions = preload("res://scripts/tutorial_missions_0836.gd")
var failures := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failures += 1
        push_error(msg)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var m = Missions.new()
    m.save_path = "user://mission0836_progress.json"
    if FileAccess.file_exists(m.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
    check(m.mark("explore"), "first claim")
    check(not m.mark("explore"), "duplicate reward")
    check(not m.mark("invalid"), "invalid mission")
    check(m.experience == 20, "experience awarded twice")
    var restored = Missions.new()
    restored.save_path = m.save_path
    restored.load_progress()
    check(restored.experience == 20, "persistence failed")
    check(restored.next_step()["id"] == "find", "mission ordering")
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://tutorial0836_company.json"
    game.company.legacy_save_path = "user://tutorial0836_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var hud = game.android_hud
    hud.missions.save_path = "user://tutorial0836_ui.json"
    if FileAccess.file_exists(hud.missions.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(hud.missions.save_path))
    hud.missions.completed.clear()
    hud.missions.experience = 0
    hud._show_tasks()
    check(hud.mission_panel.visible, "mission panel hidden")
    check(hud.active_tab == "Задания", "mission navigation")
    check(hud.mission_text.text.contains("ОБУЧЕНИЕ"), "mission text missing")
    hud._go_to_mission()
    check(not hud.mission_panel.visible, "go to goal did not close")
    game.selected = Vector2i(3,3)
    hud.refresh_missions()
    check(hud.missions.completed.has("explore"), "selection tutorial progress")
    hud._show_tasks()
    hud._go_to_mission()
    check(game.show_available_plots, "highlight action missing")
    check(hud.missions.completed.has("find"), "highlight mission missing")
    hud._show_business()
    check(hud.missions.completed.has("manage"), "business mission missing")
    hud._show_market()
    check(hud.missions.completed.has("market"), "market mission missing")
    check(hud.missions.experience == 100, "wrong tutorial experience")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("TUTORIAL_MISSIONS_0836_TESTS_PASSED")
    quit(1 if failures else 0)