extends Node2D
## Client-side atmospheric effects. Never changes server time or economy.
var city: Node2D
var elapsed := 0.0
var weather := 0 # 0 clear, 1 rain, 2 snow
var quality := 1 # 0 low, 1 balanced, 2 high
var day_cycle_enabled := true
var redraw_clock := 0.0
var last_camera_position := Vector2.INF
var last_camera_zoom := Vector2.ZERO
var last_night_step := -1

func _ready() -> void:
    city = get_parent()
    z_index = 8

func _process(delta: float) -> void:
    if city == null or city.camera == null:
        return
    if day_cycle_enabled:
        elapsed += delta
    redraw_clock += delta
    var phase := fposmod(elapsed / 360.0, 1.0)
    var night_step := int(round(clampf((absf(phase - 0.5) - 0.28) * 2.2, 0.0, 0.22) * 32.0))
    var camera_moved: bool = city.camera.position.distance_squared_to(last_camera_position) > 1.0
    var zoom_changed: bool = not city.camera.zoom.is_equal_approx(last_camera_zoom)
    if weather == 0:
        # Only redraw on camera changes or a visible lighting step.
        if camera_moved or zoom_changed or night_step != last_night_step:
            last_camera_position = city.camera.position
            last_camera_zoom = city.camera.zoom
            last_night_step = night_step
            queue_redraw()
        return
    var period := 0.50 if quality == 0 else 0.25 if quality == 1 else 0.12
    if redraw_clock >= period or camera_moved or zoom_changed:
        redraw_clock = 0.0
        last_camera_position = city.camera.position
        last_camera_zoom = city.camera.zoom
        last_night_step = night_step
        queue_redraw()

func _draw() -> void:
    if city.camera == null:
        return
    var bounds: Vector2 = get_viewport_rect().size / city.camera.zoom
    var visible := Rect2(city.camera.position - bounds * 0.5, bounds)
    var phase := fposmod(elapsed / 360.0, 1.0)
    var night := float(int(round(clampf((absf(phase - 0.5) - 0.28) * 2.2, 0.0, 0.22) * 32.0))) / 32.0
    if night > 0.01:
        draw_rect(visible, Color(0.07, 0.13, 0.28, night))
    # Clear daylight stays unfiltered. Avoid grey/blue full-screen haze.
    if weather == 0:
        return
    var count := 8 if quality == 0 else 24 if quality == 1 else 48
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