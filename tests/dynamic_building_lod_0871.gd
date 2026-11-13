extends SceneTree
const Detail = preload("res://scripts/city_detail_075.gd")
func _initialize() -> void:
    assert(Detail.building_lod(0.5, 2) == 0)
    assert(Detail.building_lod(0.9, 2) == 1)
    assert(Detail.building_lod(1.5, 0) == 0)
    assert(Detail.building_lod(1.5, 1) == 1)
    assert(Detail.building_lod(1.5, 2) == 2)
    print("DYNAMIC_BUILDING_LOD_0871 PASS")
    quit(0)