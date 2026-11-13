extends SceneTree
const Policy = preload("res://scripts/chunk_budget_08356.gd")
const Main = preload("res://scripts/main.gd")
func _initialize() -> void:
    var candidates: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0)]
    var still := Policy.nearest_first(candidates, Vector2.ZERO, 96.0, 48.0)
    assert(still.size() == 2)
    var right := Policy.nearest_first(candidates, Vector2.ZERO, 96.0, 48.0, Vector2(350, 0))
    var left := Policy.nearest_first(candidates, Vector2.ZERO, 96.0, 48.0, Vector2(-350, 0))
    assert(right[0] == Vector2i(1, 0))
    assert(left[0] == Vector2i(-1, 0))
    assert(candidates[0] == Vector2i(-1, 0))
    var game = Main.new()
    assert(game.CHUNKS_PER_FRAME == 2)
    game.free()
    print("CHUNK_PRIORITY_08357 PASS")
    quit(0)
