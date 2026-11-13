extends SceneTree
const CityDetail = preload("res://scripts/city_detail_075.gd")
func _initialize() -> void:
    var empty: Dictionary = {}
    assert(CityDetail.investment_level(empty, "ufa", Vector2i(2, 2)) == 0)
    var snapshot := {"district_demand": [
        {"city": "ufa", "district": "0:0", "infrastructure": {"investment_level": 3}},
        {"city": "ufa", "district": "1:0", "infrastructure": {"investment_level": 5}},
        {"city": "tuymazy", "district": "0:0", "infrastructure": {"investment_level": 4}}
    ]}
    assert(CityDetail.investment_level(snapshot, "ufa", Vector2i(2, 2)) == 3)
    assert(CityDetail.investment_level(snapshot, "ufa", Vector2i(18, 2)) == 5)
    assert(CityDetail.investment_level(snapshot, "ufa", Vector2i(2, 18)) == 0)
    assert(CityDetail.investment_level(snapshot, "tuymazy", Vector2i(2, 2)) == 4)
    print("VISUAL_DISTRICT_0855 PASS")
    quit(0)