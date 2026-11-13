extends SceneTree
const Detail = preload("res://scripts/city_detail_075.gd")
func _initialize() -> void:
    var good := Detail.urban_overlay_color({"transport_access":90,"traffic_congestion":10})
    var bad := Detail.urban_overlay_color({"transport_access":20,"traffic_congestion":90})
    assert(good != bad)
    assert(Detail.detail_budget(0.5,2) == 0)
    print("URBAN_ANALYTICS_0861 PASS")
    quit(0)