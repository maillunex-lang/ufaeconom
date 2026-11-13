extends SceneTree
## Headless Godot 4.6 checks. Temporary user:// saves must not touch real players.
const Company = preload("res://scripts/company_state.gd")
const Economy = preload("res://scripts/economy_simulator.gd")

func _initialize() -> void:
	_test_shop_factory_and_accounting()
	_test_capacity_and_shortages()
	_test_household_budget()
	_test_legacy_migration()
	call_deferred("_test_main_ui")

func _fresh(label: String) -> RefCounted:
	var c = Company.new()
	c.save_path = "user://economy_04_test_%s.json" % label
	c.legacy_save_path = "user://economy_04_test_%s_v1.json" % label
	c.reset()
	return c

func _add(c: RefCounted, tile: Vector2i, building: String, city: int = 0) -> void:
	assert(c.buy(city, tile, "Свободный участок").begins_with("Участок куплен"))
	assert(c.construct(city, tile, building).contains("построен"))

func _test_shop_factory_and_accounting() -> void:
	var c = _fresh("factory_shop")
	var before: int = Economy.monetary_total(c)
	_add(c, Vector2i(2, 2), "Завод")
	_add(c, Vector2i(2, 3), "Магазин")
	assert(Economy.monetary_total(c) == before, "Money vanished during construction")
	assert(c.cash == 610000)
	var report: Dictionary = c.advance_day()
	assert(report["accounting_ok"])
	assert(Economy.monetary_total(c) == before, "Money vanished after trading")
	assert(report["produced_bread"] == 24)
	assert(report["sold_bread"] == 24)
	assert(report["sold_milk"] == 10)
	assert(report["revenue"] == 24 * 155 + 10 * 180)
	assert(report["expenses"] > 0)
	assert(report["cashflow"] == report["revenue"] - report["expenses"])
	assert(report["profit"] == report["cashflow"], "All daily input/output sold, so cash-flow and profit must coincide")
	assert(report["cogs"] > 0)
	assert(report["operating_expense"] > 0)
	assert(c.cash == 610000 + int(report["cashflow"]))
	assert(c.market(0)["stock"]["Хлеб"] == 0)
	assert(c.market(0)["stock"]["Молоко"] == 0)
	assert(c.market(0)["stock"]["Зерно"] == 0)
	assert(c.totals["capital_expenditure"] == 1390000)
	# Multiple days do not emit or delete money, stock does not exceed capacity.
	for i in range(90):
		var current: Dictionary = c.advance_day()
		assert(current["accounting_ok"])
		assert(Economy.monetary_total(c) == before)
		for city in range(4):
			assert(Economy.stock_total(c.market(city)) <= c.storage_capacity(city))
	assert(c.day == 91)
	assert(c.totals["revenue"] > 0)
	assert(c.totals["expenses"] > 0)
	assert(c.totals["cashflow"] == c.totals["revenue"] - c.totals["expenses"])
	assert(c.totals["profit"] == c.totals["cashflow"])
	var loaded = _fresh("factory_shop")
	assert(loaded.load_game())
	assert(loaded.cash == c.cash)
	assert(loaded.day == c.day)
	assert(loaded.totals == c.totals)
	assert(loaded.market(0) == c.market(0))
	assert(loaded.owned == c.owned)
	print("SCENARIO_FACTORY_SHOP_90_DAYS cash=", c.cash, " cashflow=", c.totals["cashflow"])

func _test_capacity_and_shortages() -> void:
	var c = _fresh("factory_only")
	_add(c, Vector2i(2, 2), "Завод")
	var blocked := false
	for i in range(12):
		var report: Dictionary = c.advance_day()
		assert(report["accounting_ok"])
		if report["blocked"] > 0:
			blocked = true
		assert(Economy.stock_total(c.market(0)) <= c.storage_capacity(0))
	assert(blocked, "Factory should stop when storage is full")
	assert(c.market(0)["stock"]["Хлеб"] == 72)
	assert(c.market(0)["inventory_cost"]["Хлеб"] > 0)
	assert(c.last_report["profit"] == 0, "Unsold goods must be inventory, not booked as immediate loss")
	assert(c.advance_day()["sold_bread"] == 0, "No store, no bread sales")
	_add(c, Vector2i(2, 3), "Склад")
	assert(c.storage_capacity(0) == 320)
	var after: Dictionary = c.advance_day()
	assert(after["produced_bread"] == 24)
	assert(after["accounting_ok"])
	var without_factory = _fresh("shop_only")
	_add(without_factory, Vector2i(2, 2), "Магазин")
	var result: Dictionary = without_factory.advance_day()
	assert(result["sold_bread"] == 0)
	assert(result["sold_milk"] > 0)
	assert(result["accounting_ok"])
	print("SCENARIO_STORAGE_BLOCK_AND_SHOP_ONLY_OK")

func _test_household_budget() -> void:
	var c = _fresh("low_budget")
	_add(c, Vector2i(2, 2), "Магазин")
	var market: Dictionary = c.market(0)
	market["stock"]["Хлеб"] = 20
	market["residents_cash"] = 0
	market["supplier_cash"] = 0
	market["city_budget"] = 0
	var before: int = Economy.monetary_total(c)
	var report: Dictionary = c.advance_day()
	assert(report["sold_bread"] <= 2, "Residents spent beyond their wallet")
	assert(report["accounting_ok"])
	assert(Economy.monetary_total(c) == before)
	c.cash = 0
	var blocked: Dictionary = c.advance_day()
	assert(blocked["sold_bread"] == 0)
	assert(c.cash == 0)
	assert(blocked["accounting_ok"])
	print("SCENARIO_NPC_BUDGET_AND_BANKRUPTCY_OK")

func _test_legacy_migration() -> void:
	var c = _fresh("legacy")
	var file := FileAccess.open(c.legacy_save_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({
		"version": 1, "cash": 1234567, "city_index": 2,
		"properties": [{"city": 2, "x": 4, "y": 5, "building": "Магазин"}]
	}))
	file.close()
	# Deliberately use nonexistent v0.4 path; cannot overwrite a player's v0.3 file.
	c.save_path = "user://economy_04_test_legacy_new_safeguard.json"
	assert(c.load_game())
	assert(c.cash == 1234567)
	assert(c.day == 0)
	assert(c.owns(2, Vector2i(4, 5)))
	assert(c.building_at(2, Vector2i(4, 5)) == "Магазин")
	assert(c.save_game())
	var restored = Company.new()
	restored.save_path = c.save_path
	restored.legacy_save_path = "user://nonexistent_v1_file_economy_test.json"
	assert(restored.load_game())
	assert(restored.owns(2, Vector2i(4, 5)))
	assert(restored.cash == 1234567)
	print("SCENARIO_SAVE_MIGRATION_OK")

func _test_main_ui() -> void:
	var scene: Node2D = load("res://scenes/main.tscn").instantiate()
	var ui_company: RefCounted = scene.get("company")
	ui_company.save_path = "user://economy_04_test_ui.json"
	ui_company.legacy_save_path = "user://economy_04_test_ui_legacy.json"
	ui_company.reset()
	get_root().add_child(scene)
	await process_frame
	if scene.get("economy_label") == null:
		push_error("UI economy label not initialized")
		quit(1)
		return
	scene.call("_advance_day")
	var timer: Timer = scene.get("day_timer")
	if ui_company.day != 1 or not str(scene.get("economy_label").text).contains("День 1") or not str(scene.get("message_label").text).contains("прибыль"):
		push_error("Economy UI day/profit update failed")
		quit(1)
		return
	scene.call("_toggle_timer")
	if not timer.paused:
		push_error("Pause button did not pause simulation")
		quit(1)
		return
	scene.queue_free()
	print("SCENARIO_UI_TIMER_AND_NEXT_DAY_OK")
	print("ECONOMY_04_TESTS_PASSED")
	quit(0)
