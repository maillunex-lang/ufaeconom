extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        push_error(message)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://three0840_company.json"
    game.company.legacy_save_path = "user://three0840_missing.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var hud = game.android_hud
    hud.missions.save_path = "user://three0840_tutorial.json"
    if FileAccess.file_exists(hud.missions.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(hud.missions.save_path))
    hud.missions.completed.clear()
    hud.missions.experience = 0
    hud._show_tasks()
    check(hud.mission_panel.visible, "missions panel should open")
    check(hud.active_tab == "Задания", "missions tab should be active")
    check(hud.mission_text.text.contains("ОБУЧЕНИЕ"), "missions content missing")
    hud.mission_close.pressed.emit()
    check(not hud.mission_panel.visible, "close mission screen")
    check(hud.active_tab == "Город", "close should restore city tab")
    hud._show_tasks()
    hud._go_to_mission()
    check(not hud.mission_panel.visible, "go to mission should close screen")
    hud._resume()
    var tile = game.Land.free_plot(game.city_index, game._active_chunks(), game._city_plots())
    game.selected = tile
    game._buy_land()
    game._preview_construction("Завод")
    hud.update_construction()
    check(hud.construction_picker.selected >= 0, "selected construction kind missing")
    var before_count: int = hud.construction_picker.item_count
    var before_signature: String = hud.construction_picker_signature
    hud.update_construction()
    check(hud.construction_picker.item_count == before_count, "picker item count changed")
    check(hud.construction_picker_signature == before_signature, "picker rebuilt unnecessarily")
    check(hud.construction_confirm.visible, "confirmation button should appear")
    var before_money: int = game.company.cash
    hud.construction_cancel.pressed.emit()
    check(game.company.cash == before_money, "cancel charged money")
    hud._show_tasks()
    hud.hud_refresh_accum = hud.HUD_REFRESH_SECONDS
    hud._process(0.01)
    check(hud.mission_panel.visible, "mission refresh closed screen")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("THREE_STAGES_0838_0840_TESTS_PASSED")
    quit(1 if failures else 0)