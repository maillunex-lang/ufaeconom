extends SceneTree
const Company = preload("res://scripts/company_state.gd")
const Dynamics = preload("res://scripts/market_dynamics.gd")

func _initialize() -> void:
	var c = Company.new()
	c.save_path = "user://economy_05_test.json"
	c.legacy_save_path = "user://economy_05_missing.json"
	c.reset()
	var origin: Dictionary = c.market(0)
	var dest: Dictionary = c.market(1)
	assert(Dynamics.price(origin, "Хлеб") == 155)
	var raised := Dynamics.adjust_price(origin, "Хлеб", 30, 0)
	assert(raised > 155)
	var lowered := Dynamics.adjust_price(origin, "Хлеб", 30, 30)
	assert(lowered < raised)
	for i in range(100):
		Dynamics.adjust_price(origin, "Хлеб", 30, 0)
	assert(Dynamics.price(origin, "Хлеб") <= 232)
	for i in range(100):
		Dynamics.adjust_price(origin, "Хлеб", 30, 30)
	assert(Dynamics.price(origin, "Хлеб") >= 108)
	print("SCENARIO_PRICE_BOUNDS_OK")
	origin["stock"]["Хлеб"] = 30
	origin["inventory_cost"]["Хлеб"] = 2700
	var before: int = c.Economy.monetary_total(c)
	assert(c.send_goods(0, 1, "Хлеб", 10).begins_with("Отправлено"))
	assert(c.shipments.size() == 1)
	assert(origin["stock"]["Хлеб"] == 20)
	assert(origin["inventory_cost"]["Хлеб"] == 1800)
	assert(c.cash == c.START_CASH - 80)
	assert(c.Economy.monetary_total(c) == before)
	assert(c.send_goods(0, 1, "Хлеб", 100).contains("Недостаточно товара"))
	assert(c.send_goods(0, 0, "Хлеб", 1).contains("Некорректный маршрут"))
	var loaded = Company.new()
	loaded.save_path = c.save_path
	loaded.legacy_save_path = c.legacy_save_path
	assert(loaded.load_game())
	assert(loaded.shipments.size() == 1)
	assert(loaded.market(0)["stock"]["Хлеб"] == 20)
	assert(Dynamics.price(loaded.market(0), "Хлеб") == Dynamics.price(origin, "Хлеб"))
	var day_one: Dictionary = loaded.advance_day()
	assert(day_one["shipments_delivered"] == 0)
	var day_two: Dictionary = loaded.advance_day()
	assert(day_two["shipments_delivered"] == 10)
	assert(loaded.shipments.is_empty())
	assert(loaded.market(1)["stock"]["Хлеб"] == 10)
	assert(loaded.market(1)["inventory_cost"]["Хлеб"] == 900)
	assert(day_one["accounting_ok"] and day_two["accounting_ok"])
	assert(loaded.Economy.monetary_total(loaded) == before)
	print("SCENARIO_PAID_CARGO_AND_PERSISTENCE_OK")
	print("ECONOMY_05_TESTS_PASSED")
	quit()
