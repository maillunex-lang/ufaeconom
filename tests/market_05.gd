extends SceneTree
const Company = preload("res://scripts/company_state.gd")
const Dynamics = preload("res://scripts/market_dynamics.gd")
const Economy = preload("res://scripts/economy_simulator.gd")
func _initialize() -> void:
	var c = Company.new()
	c.save_path = "user://market_05_test.json"
	c.legacy_save_path = "user://market_05_missing.json"
	c.reset()
	for city in range(4):
		c.market(city)
	var money: int = Economy.monetary_total(c)
	var m: Dictionary = c.market(0)
	var start: int = Dynamics.price(m, "Хлеб")
	assert(Dynamics.adjust_price(m, "Хлеб", 30, 0) > start)
	for i in range(100):
		Dynamics.adjust_price(m, "Хлеб", 30, 0)
	assert(Dynamics.price(m, "Хлеб") <= 232)
	for i in range(100):
		Dynamics.adjust_price(m, "Хлеб", 30, 30)
	assert(Dynamics.price(m, "Хлеб") >= 108)
	m["stock"]["Хлеб"] = 30
	m["inventory_cost"]["Хлеб"] = 3000
	assert(c.send_goods(0, 0, "Хлеб", 5) == "Некорректный маршрут")
	assert(c.send_goods(0, 1, "Хлеб", 31) == "Недостаточно товара на складе отправления")
	var cash_before: int = c.cash
	assert(c.send_goods(0, 1, "Хлеб", 20).begins_with("Отправлено"))
	assert(c.cash == cash_before - 160)
	assert(Economy.monetary_total(c) == money)
	assert(int(m["stock"]["Хлеб"]) == 10)
	assert(int(m["inventory_cost"]["Хлеб"]) == 1000)
	assert(c.shipments.size() == 1)
	assert(c.load_game())
	assert(c.shipments.size() == 1)
	assert(c.advance_day()["shipments_delivered"] == 0)
	assert(c.advance_day()["shipments_delivered"] == 20)
	assert(c.shipments.is_empty())
	assert(int(c.market(1)["stock"]["Хлеб"]) == 20)
	assert(int(c.market(1)["inventory_cost"]["Хлеб"]) == 2000)
	assert(Economy.monetary_total(c) == money)
	print("MARKET_05_TESTS_PASSED")
	quit(0)
