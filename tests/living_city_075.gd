extends SceneTree
const Land = preload("res://scripts/city_land.gd")
const Detail = preload("res://scripts/city_detail_075.gd")
var failed := 0
func check(value: bool, msg: String) -> void:
    if not value:
        failed += 1
        push_error(msg)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    check(Detail.detail_for_zoom(0.4) == 0, "low LOD")
    check(Detail.detail_for_zoom(0.8) == 1, "medium LOD")
    check(Detail.detail_for_zoom(1.5) == 2, "high LOD")
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://livingcity075.json"
    game.company.legacy_save_path = "user://livingcity075_old.json"
    game.company.reset()
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    var hud = game.android_hud
    check(hud != null, "HUD missing")
    var traffic = game.get_node("CityLife25D")
    hud._cycle_quality()
    check(traffic.detail_quality == 2, "high quality not applied")
    hud._cycle_quality()
    check(traffic.detail_quality == 0, "low quality not applied")
    var tile := Land.free_plot(game.city_index, game._active_chunks(), game._city_plots())
    check(tile.x >= 0, "no free plot")
    game.selected = tile
    game._preview_construction("Завод")
    check(game.construction_preview == "", "preview allowed on unowned land")
    var before: int = game.company.cash
    game._buy_land()
    check(game.company.cash == before - game.CompanyState.LAND_PRICE, "land purchase changed")
    before = game.company.cash
    game._preview_construction("Завод")
    check(game.construction_preview == "Завод", "preview not set")
    check(game.company.cash == before, "preview spent money")
    game._cancel_preview()
    check(game.construction_preview == "", "preview not cancelled")
    game._preview_construction("Завод")
    game._confirm_preview()
    check(game.construction_preview == "", "preview remains after confirmation")
    check(game._building_at(tile) == "Завод", "building not constructed")
    check(game.company.cash == before - game.CompanyState.CONSTRUCTION["Завод"], "wrong construction cost")
    game.queue_free()
    await process_frame
    if failed == 0:
        print("LIVING_CITY_075_TESTS_PASSED")
    quit(1 if failed else 0)