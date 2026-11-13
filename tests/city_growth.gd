extends SceneTree
const Land = preload("res://scripts/city_land.gd")
const Company = preload("res://scripts/company_state.gd")
const Generator = preload("res://scripts/city_generator.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	for city in range(4):
		var old: Dictionary = Generator.make_city(city)["cells"]
		for tile in old:
			check(Land.kind_at(city, tile) == old[tile], "Frozen core changed")
	var samples: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain_parity_v1.json"))
	for sample in samples:
		var tile := Vector2i(int(sample[1]),int(sample[2]))
		check(Land.code_at(int(sample[0]),tile)==int(sample[3]) and Land.has_ore(int(sample[0]),tile)==bool(sample[4]), "Python/Godot terrain mismatch")
	var chunks := Land.initial_chunks()
	var plots := {}
	var frontier := Vector2i(31, 1)
	check(Land.grow(0, chunks, plots, frontier), "Eastern frontier must expand")
	check(chunks.has("2:0"), "Missing adjacent east quarter")
	check(not Land.grow(0, chunks, plots, frontier), "Repeated frontier must not reveal unrelated land")
	check(Land.code_at(0, Vector2i(34, 2)) == 0, "Outer chunk fixture")
	check(Land.has_ore(0, Vector2i(9, 5)), "Ore parity fixture")
	check(not Land.is_open(chunks, Vector2i(999, 999)), "Unopened land must be inaccessible")
	check(not Land.valid_chunks(["0:0", "1:0", "0:1", "1:1", "12:12"]), "Isolated chunks must be rejected")
	# Dense occupied quarter has a growth fallback even away from its edge.
	var dense := {}
	for y in range(16):
		for x in range(16):
			var tile := Vector2i(x, y)
			if Land.code_at(0, tile) == 0:
				dense[Land.plot_key(tile)] = {"building": "Завод"}
	var dense_chunks: Array = ["0:0","0:1","1:1","2:1"]
	# Test the same density rule at the east core quarter whose right neighbour is unopened.
	dense.clear()
	for y in range(16):
		for x in range(16,32):
			if Land.code_at(0,Vector2i(x,y)) == 0:
				dense[Land.plot_key(Vector2i(x,y))] = {"building":"Завод"}
	check(Land.grow(0, Land.initial_chunks(), dense, Vector2i(17,1)), "Dense quarter must expose another adjacent quarter")
	var c = Company.new()
	c.save_path = "user://city_growth_test.json"
	c.legacy_save_path = "user://city_growth_missing_legacy.json"
	c.reset()
	# Rich fixture, without altering production balances or a real save.
	c.cash = 20000000
	var tile := Vector2i(-1,-1)
	for y in range(1,31):
		var candidate := Vector2i(31,y)
		if Land.code_at(0,candidate) == 0:
			tile = candidate
			break
	check(tile.x >= 0, "No core edge fixture")
	check(c.buy(0,tile,"Свободный участок").begins_with("Участок куплен"),"Core purchase")
	check(c.construct(0,tile,"Завод").contains("построен"),"Factory construction")
	check(c.chunks(0).has("2:0"),"Actual construction did not expand")
	var outer: Vector2i = Land.free_plot(0,c.chunks(0),c.plots(0))
	for y in range(16):
		var p := Vector2i(33,y)
		if Land.code_at(0,p)==0:
			outer=p
			break
	check(outer.x >= 32,"New plot fixture")
	check(c.buy(0,outer,"Свободный участок").begins_with("Участок куплен"),"Purchase beyond old limit")
	check(c.construct(0,outer,"Автосалон").contains("построен"),"Standalone car dealership")
	var ore: Vector2i = Land.free_plot(0,c.chunks(0),c.plots(0),true)
	check(ore.x >= 0,"No ore plot")
	c.buy(0,ore,"Свободный участок")
	check(c.construct(0,ore,"Шахта").contains("построен"),"Mine on ore")
	var ordinary := Land.free_plot(0,c.chunks(0),c.plots(0))
	while Land.has_ore(0,ordinary):
		c.buy(0,ordinary,"Свободный участок")
		ordinary=Land.free_plot(0,c.chunks(0),c.plots(0))
	c.buy(0,ordinary,"Свободный участок")
	var before: int=c.cash
	check(c.construct(0,ordinary,"Шахта").contains("месторождением"),"Mine without ore")
	check(c.cash==before,"Invalid mine spent money")
	check(c.construct(0,ordinary,"Исследовательский центр").contains("построен"),"Standalone research center")
	var copy = Company.new()
	copy.save_path=c.save_path
	copy.legacy_save_path=c.legacy_save_path
	check(copy.load_game(),"Expanded save failed")
	check(copy.owned==c.owned and copy.cash==c.cash and copy.chunks(0)==c.chunks(0),"Expanded save changed assets")
	print("CITY_GROWTH_DOMAIN_CHECKS_DONE quarters=",c.chunks(0).size())
	call_deferred("_test_scene")

func _test_scene() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.company.save_path="user://city_growth_scene_test.json"
	game.company.legacy_save_path="user://city_growth_scene_missing.json"
	root.add_child(game)
	await process_frame
	game._find_free_plot()
	check(game.selected.x>=0,"Find free plot UI")
	game._find_free_plot(true)
	check(Land.has_ore(game.city_index,game.selected),"Find ore UI")
	var rect: Rect2i=game._visible_tile_rect()
	check(rect.get_area()<25000,"Visible draw bound is too large at default zoom")
	game.queue_free()
	await process_frame
	if not failed:
		print("CITY_GROWTH_TESTS_PASSED core4096=unchanged expansion=1 save=1 mine=1 ui=1")
	quit(1 if failed else 0)
