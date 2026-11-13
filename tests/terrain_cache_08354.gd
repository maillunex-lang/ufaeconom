extends SceneTree
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
    var game = Main.new()
    assert(game.TERRAIN_CACHE_LIMIT == 4096)
    for y in range(65):
        for x in range(65):
            game._static_tile_data(Vector2i(x, y))
    assert(game.terrain_cache.size() <= game.TERRAIN_CACHE_LIMIT)
    assert(game.terrain_cache_order.size() == game.terrain_cache.size())
    assert(game.terrain_cache_evictions > 0)
    var tile := Vector2i(64, 64)
    var hits: int = game.terrain_cache_hits
    game._static_tile_data(tile)
    assert(game.terrain_cache_hits == hits + 1)
    game._clear_terrain_cache()
    assert(game.terrain_cache_order.is_empty())
    assert(game.terrain_cache_evictions == 0)
    game.free()
    print("TERRAIN_CACHE_08354 PASS")
    quit(0)
