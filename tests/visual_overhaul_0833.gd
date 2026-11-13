extends SceneTree
const Detail = preload("res://scripts/city_detail_075.gd")
const Building = preload("res://scripts/building_art.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    check(Detail.detail_budget(0.52, 2) == 0, "far zoom must cull details")
    check(Detail.detail_budget(0.8, 0) == 1, "low quality must keep medium LOD")
    check(Detail.detail_budget(1.5, 1) == 1, "balanced quality must cap details")
    check(Detail.detail_budget(1.5, 2) == 2, "high quality near zoom")
    check(Detail.terrain_tint(Vector2i(1, 2), "Дорога") == Color("#58636a"), "road palette")
    check(Detail.terrain_tint(Vector2i(7, 3), "Дерево") == Detail.terrain_tint(Vector2i(7, 3), "Дерево"), "deterministic terrain")
    check(Building.palette("Завод", 0) != Building.palette("Магазин", 0), "distinct building palette")
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://visual0833_test.json"
    game.company.legacy_save_path = "user://visual0833_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    check(game.performance != null, "quality adaptation missing")
    game.performance.apply_quality(0)
    check(game.performance.level == 0, "low quality did not apply")
    game.performance.apply_quality(2)
    check(game.performance.level == 2, "high quality did not apply")
    check(game._visible_tile_rect().size.x >= 0, "visible tile bounds invalid")
    check(game.camera.zoom.x >= game.CAMERA_MIN_ZOOM, "zoom safety")
    game.queue_free()
    await process_frame
    if failures == 0:
        print("VISUAL_OVERHAUL_0833_TESTS_PASSED")
    quit(1 if failures else 0)