extends SceneTree
const Detail = preload("res://scripts/city_detail_075.gd")
func _initialize() -> void:
    var data := {"district_demand":[
        {"city":"ufa","district":"0:0","residential_tier":5,"population_trend":8,"infrastructure":{"investment_level":4}}
    ]}
    assert(Detail.investment_level(data,"ufa",Vector2i(1,1)) == 4)
    assert(Detail.detail_budget(0.5,2) == 0)
    assert(Detail.detail_budget(1.2,2) == 2)
    print("CITY_GROWTH_0856 PASS")
    quit(0)