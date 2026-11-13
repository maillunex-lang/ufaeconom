extends SceneTree
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
    var game = Main.new()
    var tile := Vector2i(5, 6)
    var data: Dictionary = game._static_tile_data(tile)
    var diamond: PackedVector2Array = data["diamond"]
    var outline: PackedVector2Array = data["outline"]
    var pos: Vector2 = data["pos"]
    assert(diamond.size() == 4)
    assert(outline.size() == 5)
    assert(outline[0] == outline[4])
    assert(diamond[0] == pos + Vector2(0, -24))
    assert(diamond[1] == pos + Vector2(48, 0))
    assert(game._static_tile_data(tile)["diamond"] == diamond)
    assert(game.terrain_cache_hits == 1)
    game._clear_terrain_cache()
    assert(game.terrain_cache.is_empty())
    game.free()
    print("CITY_GEOMETRY_CACHE_0868 PASS")
    quit(0)