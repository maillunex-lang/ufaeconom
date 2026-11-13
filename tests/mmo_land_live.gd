extends SceneTree
const Land=preload("res://scripts/city_land.gd")
var game
var stage := "login"
var tile := Vector2i(-1,-1)
var began := 0

func _initialize() -> void:
	began=Time.get_ticks_msec()
	call_deferred("_run")

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	game.company.save_path="user://city_live_bridge.json"
	game.company.legacy_save_path="user://city_live_missing.json"
	root.add_child(game)
	var client=game.mmo_panel.client
	client.snapshot_ready.connect(_snapshot)
	client.command_ready.connect(_command)
	client.request_failed.connect(_fail)
	client.login_to(OS.get_environment("BE_TEST_URL"),OS.get_environment("BE_TEST_USER"),OS.get_environment("BE_TEST_PASSWORD"))

func _snapshot(data: Dictionary) -> void:
	if stage=="login":
		check(data.has("land"),"Server omitted spatial state")
		var layout: Dictionary=data["land"]["ufa"]
		for y in range(32):
			if Land.code_at(0,Vector2i(31,y))==0 and not layout["plots"].has("31:"+str(y)):
				tile=Vector2i(31,y)
				break
		check(tile.x==31,"No frontier plot")
		game.selected=tile
		stage="buy"
		game._buy_land()
	elif stage=="bought":
		check(game._owns_plot(tile),"UI did not apply server land ownership")
		stage="build"
		game._construct("Автосалон")
	elif stage=="built":
		check(game._building_at(tile)=="Автосалон","UI did not render server building type")
		check(data["land"]["ufa"]["chunks"].has("2:0"),"Server frontier did not expand")
		print("MMO_LAND_LIVE_TESTS_PASSED godot_to_http=1 ownership=1 standalone=1 expansion=1")
		quit(0)

func _command(_result: Dictionary) -> void:
	if stage=="buy": stage="bought"
	elif stage=="build": stage="built"
	else: _fail("Unexpected command phase")

func check(ok: bool, message: String) -> void:
	if not ok: _fail(message)

func _fail(message: String) -> void:
	push_error("MMO_LAND_LIVE_FAILED: "+message)
	quit(1)

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>20000: _fail("timeout")
	return false
