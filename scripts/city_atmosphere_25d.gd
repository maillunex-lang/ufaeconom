extends Node2D
## Client-side atmospheric effects. Never changes server time or economy.
var city: Node2D
var elapsed := 0.0
var weather := 0 # 0 clear, 1 rain, 2 snow
var quality := 1 # 0 low, 1 balanced, 2 high
var day_cycle_enabled := true
var redraw_clock := 0.0

func _ready() -> void:
    city = get_parent()
    z_index = 8

func _process(delta: float) -> void:
    if day_cycle_enabled:
        elapsed += delta
    redraw_clock += delta
    var period := 0.33 if quality == 0 else 0.16 if quality == 1 else 0.09
    if redraw_clock >= period:
        redraw_clock = 0.0
        queue_redraw()

func _draw() -> void:
    if city.camera == null:
        return
    var bounds: Vector2 = get_viewport_rect().size / city.camera.zoom
    var visible := Rect2(city.camera.position - bounds * 0.5, bounds)
    var phase := fposmod(elapsed / 360.0, 1.0)
    var night := clampf((absf(phase - 0.5) - 0.24) * 3.0, 0.0, 0.50)
    if night > 0.01:
        draw_rect(visible, Color(0.07, 0.13, 0.28, night))
    elif quality >= 1:
        # A very light warm daylight tint; one rectangle, no post-processing pass.
        draw_rect(visible, Color(0.97, 0.78, 0.49, 0.025))
    if weather == 0:
        return
    var count := 18 if quality == 0 else 42 if quality == 1 else 75
    for i in range(count):
        var px := fposmod(float(i * 173) + elapsed * (95.0 if weather == 1 else 24.0), bounds.x)
        var py := fposmod(float(i * 97) + elapsed * (210.0 if weather == 1 else 36.0), bounds.y)
        var p := visible.position + Vector2(px, py)
        if weather == 1:
            draw_line(p, p + Vector2(-3, 11), Color(0.77, 0.86, 1.0, 0.46), 1.0)
        else:
            draw_circle(p, 1.6, Color(0.95, 0.97, 1.0, 0.72))

func cycle_weather() -> void:
    weather = (weather + 1) % 3
    queue_redraw()

func set_quality(value: int) -> void:
    quality = clampi(value, 0, 2)
    queue_redraw()