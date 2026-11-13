extends SceneTree
const Main = preload("res://scripts/main.gd")
const Policy = preload("res://scripts/chunk_budget_08356.gd")
func _initialize() -> void:
    var items: Array[Vector2i] = [Vector2i(8, 8), Vector2i(0, 0), Vector2i(1, 0)]
    var sorted := Policy.nearest_first(items, Vector2.ZERO, 96.0, 48.0)
    assert(sorted[0] == Vector2i(0, 0))
    assert(items[0] == Vector2i(8, 8))
    var game = Main.new()
    assert(game.CHUNKS_PER_FRAME == 2)
    assert(game.pending_chunk_coords.is_empty())
    game.pending_chunk_coords = sorted
    game._clear_chunk_canvases()
    assert(game.pending_chunk_coords.is_empty())
    game.free()
    print("CHUNK_BUDGET_08356 PASS")
    quit(0)
