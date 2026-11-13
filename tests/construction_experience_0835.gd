extends SceneTree
const Art = preload("res://scripts/building_art.gd")
const Land = preload("res://scripts/city_land.gd")
var failed := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        failed += 1
        push_error(msg)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    check(Art.preview_stage(0.0) == 0, "survey stage")
    check(Art.preview_stage(0.7) == 1, "foundation stage")
    check(Art.preview_stage(1.4) == 2, "scaffolding stage")
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://construction0835.json"
    game.company.legacy_save_path = "user://construction0835_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var hud = game.android_hud
    hud._resume()
    var tile: Vector2i = Land.free_plot(game.city_index, game._active_chunks(), game._city_plots())
    check(tile.x >= 0, "free plot missing")
    game.selected = tile
    game._update_actions()
    check(hud.construction_panel.visible, "construction card not shown")
    check(hud.construction_buy.visible, "purchase button not shown")
    check(not hud.construction_confirm.visible, "confirmation before preview")
    var before: int = game.company.cash
    hud._toggle_plot_highlights()
    check(game.show_available_plots, "plot highlighting missing")
    game._buy_land()
    check(game.company.cash == before - game.CompanyState.LAND_PRICE, "land purchase changed")
    check(hud.construction_picker.visible, "building selector missing")
    game._preview_construction("Завод")
    check(game.construction_preview == "Завод", "preview not set")
    check(hud.construction_confirm.visible, "confirmation not shown")
    check(game.company.cash == before - game.CompanyState.LAND_PRICE, "preview spent money")
    hud.construction_cancel.pressed.emit()
    check(game.construction_preview == "", "cancel failed")
    game._preview_construction("Завод")
    var money_before_build: int = game.company.cash
    hud.construction_confirm.pressed.emit()
    check(game._building_at(tile) == "Завод", "construction failed")
    check(game.company.cash == money_before_build - game.CompanyState.CONSTRUCTION["Завод"], "construction cost wrong")
    game.queue_free()
    await process_frame
    if failed == 0:
        print("CONSTRUCTION_EXPERIENCE_0835_TESTS_PASSED")
    quit(1 if failed else 0)