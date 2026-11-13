extends Node2D
## Single green backing behind the cached terrain and dynamic city objects.
func _ready() -> void:
    z_index = -2
    queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2(-2000000, -2000000), Vector2(4000000, 4000000)), Color("#789a78"))