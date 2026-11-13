extends SceneTree
const Policy = preload("res://scripts/graphics_policy_08348.gd")
func _initialize() -> void:
    assert(Policy.decide(2, 14.0, 0, 0, 20.0) == 0)
    assert(Policy.decide(2, 24.0, 1, 0, 0.0) == 2)
    assert(Policy.decide(2, 24.0, 2, 0, 0.0) == 1)
    assert(Policy.decide(1, 60.0, 0, 8, 10.0) == 1)
    assert(Policy.decide(1, 60.0, 0, 8, 0.0) == 2)
    assert(Policy.decide(0, 14.0, 3, 0, 0.0) == 0)
    print("GRAPHICS_POLICY_08348 PASS")
    quit(0)
