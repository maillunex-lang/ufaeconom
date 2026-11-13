extends SceneTree
const Smart = preload("res://scripts/smart_city_076.gd")
const Land = preload("res://scripts/city_land.gd")
var errors := 0
func check(ok: bool, msg: String) -> void:
    if not ok:
        errors += 1
        push_error(msg)
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var chunks := {"0:0":true,"1:0":true,"0:1":true,"1:1":true}
    var start := Vector2i(7,7)
    var target := Vector2i(7,11)
    var route := Smart.route(0,start,target,chunks)
    check(route.size() > 1, "road route missing")
    for tile in route:
        check(Land.kind_at(0,tile) == "Дорога", "route leaves road")
    check(Smart.route(0,Vector2i(1000,1000),target,chunks).is_empty(),"route escaped open chunks")
    check(Smart.visual_construction_phase({}) == "unknown","invented phase")
    check(Smart.visual_construction_phase({"construction_state":"frame"}) == "frame","server phase")
    check(Smart.display_metrics({}, "factory").is_empty(),"invented production")
    var snapshot := {"facilities":[{"kind":"factory","production":18,"inventory":7,"profit_minor":12500,"workers":4}]}
    var fields := Smart.display_metrics(snapshot,"factory")
    check(fields.get("production",-1) == 18 and fields.get("profit_minor",-1) == 12500,"metrics missing")
    var game = load("res://scenes/main.tscn").instantiate()
    game.company.save_path = "user://smartcity076_test.json"
    game.company.legacy_save_path = "user://smartcity076_old.json"
    if FileAccess.file_exists(game.company.save_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(game.company.save_path))
    root.add_child(game)
    await process_frame
    check(game.performance != null,"performance controller missing")
    game.performance.apply_quality(0)
    check(game.get_node("CityLife25D").detail_quality == 0,"LOD not applied")
    game.performance.apply_quality(2)
    check(game.atmosphere.quality == 2,"weather LOD not applied")
    game.android_hud._toggle_auto()
    check(not game.performance.auto_enabled,"manual FPS toggle failed")
    game.android_hud._toggle_business()
    check(not game.android_hud.business_panel.visible,"empty selection must hide panel")
    game.queue_free()
    await process_frame
    if errors == 0:
        print("SMART_CITY_076_TESTS_PASSED")
    quit(1 if errors else 0)