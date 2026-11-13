extends SceneTree
const Atmosphere = preload("res://scripts/city_atmosphere_25d.gd")
const Traffic = preload("res://scripts/city_life_25d.gd")
func _initialize() -> void:
    var a = Atmosphere.new()
    assert(a.weather == 0)
    assert(a.last_night_step == -1)
    a.set_quality(0)
    assert(a.quality == 0)
    a.cycle_weather()
    assert(a.weather == 1)
    var t = Traffic.new()
    t.detail_quality = 0
    assert(t.detail_quality == 0)
    a.free()
    t.free()
    print("RENDER_THROTTLE_0866 PASS")
    quit(0)