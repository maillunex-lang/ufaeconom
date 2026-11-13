extends RefCounted
class_name EconomySimulator

## Deterministic, offline cash-and-inventory simulation for the 0.4 prototype.
## All values are WHOLE game rubles and WHOLE goods units.
## Prices and capacities below are UNCALIBRATED design hypotheses.
const Dynamics = preload("res://scripts/market_dynamics.gd")
const GOODS := {
	"Зерно": {"buy": 50},
	"Хлеб": {"sell": 155},
	"Молоко": {"buy": 110, "sell": 180}
}
const BAKERY_GRAIN := 12
const BAKERY_BREAD := 24
const STORE_BREAD_PER_DAY := 24
const STORE_MILK_PER_DAY := 10
const WORKSHOP_WAGES := 600
const WORKSHOP_ENERGY := 300
const WORKSHOP_MAINTENANCE := 80
const STORE_WAGES := 350
const STORE_UTILITIES := 180
const STORE_TRANSPORT := 150
const WAREHOUSE_MAINTENANCE := 100
const SALES_TAX_BPS := 500 # 5%; prototype assumption, not real tax law.
const START_CITY_RESIDENTS := 120000
const START_CITY_SUPPLIERS := 600000
const START_CITY_BUDGET := 2000000
const CITY_BREAD_DEMAND := [30, 22, 18, 15]
const CITY_MILK_DEMAND := [16, 14, 11, 10]
const CITY_GRAIN_SUPPLY := [30, 24, 18, 18]
const CITY_MILK_SUPPLY := [24, 20, 16, 12]
const BASE_CAPACITY := 80
const WAREHOUSE_CAPACITY := 240

static func new_market() -> Dictionary:
	return {
		"stock": {"Зерно": 0, "Хлеб": 0, "Молоко": 0},
		"inventory_cost": {"Зерно": 0, "Хлеб": 0, "Молоко": 0},
		"supplier_stock": {"Зерно": 0, "Молоко": 0},
		"prices": Dynamics.new_prices(),
		"residents_cash": START_CITY_RESIDENTS,
		"supplier_cash": START_CITY_SUPPLIERS,
		"city_budget": START_CITY_BUDGET
	}

static func stock_total(market: Dictionary) -> int:
	var total := 0
	var stock: Dictionary = market["stock"]
	for value in stock.values():
		total += int(value)
	return total

static func capacity(company: RefCounted, city: int) -> int:
	var warehouses := 0
	for property in company.owned.values():
		if int(property.get("city", -1)) == city and property.get("building", "") == "Склад":
			warehouses += 1
	return BASE_CAPACITY + warehouses * WAREHOUSE_CAPACITY

static func monetary_total(company: RefCounted) -> int:
	var total: int = company.cash
	for city in range(4):
		var market: Dictionary = company.market(city)
		total += int(market["residents_cash"]) + int(market["supplier_cash"]) + int(market["city_budget"])
	return total

static func _expense(company: RefCounted, market: Dictionary, stats: Dictionary, city_stats: Dictionary, amount: int, recipient: String, title: String, profit_direct: bool = false) -> bool:
	if amount < 0 or company.cash < amount:
		return false
	company.cash -= amount
	market[recipient] = int(market[recipient]) + amount
	stats["expenses"] = int(stats["expenses"]) + amount
	city_stats["expenses"] = int(city_stats["expenses"]) + amount
	if profit_direct:
		stats["operating_expense"] = int(stats["operating_expense"]) + amount
		city_stats["operating_expense"] = int(city_stats["operating_expense"]) + amount
	var breakdown: Dictionary = stats["expense_breakdown"]
	breakdown[title] = int(breakdown.get(title, 0)) + amount
	return true

static func _procure(company: RefCounted, market: Dictionary, stats: Dictionary, city_stats: Dictionary, good: String, quantity: int) -> bool:
	if quantity <= 0:
		return false
	if stock_total(market) + quantity > capacity(company, int(city_stats["city"])):
		return false
	var supplier_stock: Dictionary = market["supplier_stock"]
	if int(supplier_stock.get(good, 0)) < quantity:
		return false
	var cost: int = int(GOODS[good]["buy"]) * quantity
	if not _expense(company, market, stats, city_stats, cost, "supplier_cash", "Закупка %s" % good.to_lower()):
		return false
	var stock: Dictionary = market["stock"]
	stock[good] = int(stock[good]) + quantity
	supplier_stock[good] = int(supplier_stock[good]) - quantity
	var inventory_cost: Dictionary = market["inventory_cost"]
	inventory_cost[good] = int(inventory_cost[good]) + cost
	city_stats["purchased"] = int(city_stats["purchased"]) + quantity
	return true

static func _sell(company: RefCounted, market: Dictionary, stats: Dictionary, city_stats: Dictionary, good: String, requested: int) -> int:
	if requested <= 0:
		return 0
	var stock: Dictionary = market["stock"]
	var price: int = Dynamics.price(market, good)
	var affordable: int = int(int(market["residents_cash"]) / price)
	var sold: int = mini(requested, mini(int(stock[good]), affordable))
	if sold <= 0:
		return 0
	var receipt := sold * price
	var inventory_cost: Dictionary = market["inventory_cost"]
	var old_quantity: int = int(stock[good])
	var cogs: int = int(int(inventory_cost[good]) * sold / old_quantity)
	if sold == old_quantity:
		cogs = int(inventory_cost[good])
	inventory_cost[good] = int(inventory_cost[good]) - cogs
	stats["cogs"] = int(stats["cogs"]) + cogs
	city_stats["cogs"] = int(city_stats["cogs"]) + cogs
	stock[good] = old_quantity - sold
	market["residents_cash"] = int(market["residents_cash"]) - receipt
	company.cash += receipt
	stats["revenue"] = int(stats["revenue"]) + receipt
	city_stats["revenue"] = int(city_stats["revenue"]) + receipt
	var tax: int = int(receipt * SALES_TAX_BPS / 10000)
	if tax > 0:
		_expense(company, market, stats, city_stats, tax, "city_budget", "Налог с продаж", true)
	return sold

static func _npc_supply(market: Dictionary, city: int) -> void:
	## Fictional local agriculture: goods enter a bounded NPC supplier pool.
	## This is a goods source, NEVER a currency source.
	var stock: Dictionary = market["supplier_stock"]
	stock["Зерно"] = mini(int(stock["Зерно"]) + CITY_GRAIN_SUPPLY[city], CITY_GRAIN_SUPPLY[city] * 4)
	stock["Молоко"] = mini(int(stock["Молоко"]) + CITY_MILK_SUPPLY[city], CITY_MILK_SUPPLY[city] * 4)

static func _npc_income(market: Dictionary) -> void:
	## Transfers from finite city treasury and local suppliers, not minted cash.
	var from_city: int = mini(int(market["city_budget"]), 2500)
	var from_suppliers: int = mini(int(market["supplier_cash"]), 3500)
	market["city_budget"] = int(market["city_budget"]) - from_city
	market["supplier_cash"] = int(market["supplier_cash"]) - from_suppliers
	market["residents_cash"] = int(market["residents_cash"]) + from_city + from_suppliers

static func step(company: RefCounted) -> Dictionary:
	## City-wide wallets are initialized before the accounting snapshot.
	for city in range(4):
		company.market(city)
	var before := monetary_total(company)
	company.day += 1
	var shipments_delivered: int = Dynamics.deliver_shipments(company)
	var stats := {
		"day": company.day, "revenue": 0, "expenses": 0, "shipments_delivered": shipments_delivered,
		"cogs": 0, "operating_expense": 0, "profit": 0,
		"produced_bread": 0, "sold_bread": 0, "sold_milk": 0,
		"unmet_bread": 0, "unmet_milk": 0, "blocked": 0,
		"expense_breakdown": {}, "cities": {}
	}
	for city in range(4):
		var market: Dictionary = company.market(city)
		_npc_supply(market, city)
		_npc_income(market)
		var stock: Dictionary = market["stock"]
		var shops := 0
		var factories := 0
		var warehouses := 0
		for property in company.owned.values():
			if int(property.get("city", -1)) != city:
				continue
			match str(property.get("building", "")):
				"Магазин": shops += 1
				"Завод": factories += 1
				"Склад": warehouses += 1
		var fluctuation := posmod(company.day + city * 3, 5) - 2
		var bread_demand: int = maxi(0, CITY_BREAD_DEMAND[city] + fluctuation)
		var milk_demand: int = maxi(0, CITY_MILK_DEMAND[city] + fluctuation)
		var result := {
			"city": city, "shops": shops, "factories": factories, "warehouses": warehouses,
			"bread_demand": bread_demand, "milk_demand": milk_demand,
			"produced_bread": 0, "sold_bread": 0, "sold_milk": 0,
			"purchased": 0, "revenue": 0, "expenses": 0,
			"cogs": 0, "operating_expense": 0, "profit": 0, "blocked": 0
		}
		# Paid storage maintenance is a transfer to local suppliers.
		for w in range(warehouses):
			if not _expense(company, market, stats, result, WAREHOUSE_MAINTENANCE, "supplier_cash", "Содержание склада", true):
				result["blocked"] = int(result["blocked"]) + 1
		# One bakery batch per factory per day.
		for f in range(factories):
			# A factory cannot produce beyond total shared-city storage capacity.
			if stock_total(market) - mini(int(stock["Зерно"]), BAKERY_GRAIN) + BAKERY_BREAD > capacity(company, city):
				result["blocked"] = int(result["blocked"]) + 1
				continue
			var missing_grain: int = maxi(0, BAKERY_GRAIN - int(stock["Зерно"]))
			if missing_grain > 0 and not _procure(company, market, stats, result, "Зерно", missing_grain):
				result["blocked"] = int(result["blocked"]) + 1
				continue
			if company.cash < WORKSHOP_WAGES + WORKSHOP_ENERGY + WORKSHOP_MAINTENANCE:
				result["blocked"] = int(result["blocked"]) + 1
				continue
			_expense(company, market, stats, result, WORKSHOP_WAGES, "residents_cash", "Зарплата завода")
			_expense(company, market, stats, result, WORKSHOP_ENERGY, "supplier_cash", "Энергия завода")
			_expense(company, market, stats, result, WORKSHOP_MAINTENANCE, "supplier_cash", "Содержание завода")
			var costs: Dictionary = market["inventory_cost"]
			var grain_quantity: int = int(stock["Зерно"])
			var used_cost: int = int(int(costs["Зерно"]) * BAKERY_GRAIN / grain_quantity)
			if BAKERY_GRAIN == grain_quantity:
				used_cost = int(costs["Зерно"])
			costs["Зерно"] = int(costs["Зерно"]) - used_cost
			costs["Хлеб"] = int(costs["Хлеб"]) + used_cost + WORKSHOP_WAGES + WORKSHOP_ENERGY + WORKSHOP_MAINTENANCE
			stock["Зерно"] = grain_quantity - BAKERY_GRAIN
			stock["Хлеб"] = int(stock["Хлеб"]) + BAKERY_BREAD
			result["produced_bread"] = int(result["produced_bread"]) + BAKERY_BREAD
		# Shops consume their actual running budgets; stores with no cash cannot sell.
		var open_shops := 0
		for shop in range(shops):
			if company.cash < STORE_WAGES + STORE_UTILITIES + STORE_TRANSPORT:
				result["blocked"] = int(result["blocked"]) + 1
				continue
			_expense(company, market, stats, result, STORE_WAGES, "residents_cash", "Зарплата магазина", true)
			_expense(company, market, stats, result, STORE_UTILITIES, "supplier_cash", "Коммунальные услуги", true)
			_expense(company, market, stats, result, STORE_TRANSPORT, "supplier_cash", "Доставка", true)
			open_shops += 1
		if open_shops > 0:
			var milk_needed: int = maxi(0, mini(milk_demand, open_shops * STORE_MILK_PER_DAY) - int(stock["Молоко"]))
			if milk_needed > 0:
				_procure(company, market, stats, result, "Молоко", milk_needed)
			var bread_requested: int = mini(bread_demand, open_shops * STORE_BREAD_PER_DAY)
			var milk_requested: int = mini(milk_demand, open_shops * STORE_MILK_PER_DAY)
			result["sold_bread"] = _sell(company, market, stats, result, "Хлеб", bread_requested)
			result["sold_milk"] = _sell(company, market, stats, result, "Молоко", milk_requested)
		Dynamics.adjust_price(market, "Хлеб", bread_demand, int(result["sold_bread"]))
		Dynamics.adjust_price(market, "Молоко", milk_demand, int(result["sold_milk"]))
		result["profit"] = int(result["revenue"]) - int(result["cogs"]) - int(result["operating_expense"])
		stats["produced_bread"] = int(stats["produced_bread"]) + int(result["produced_bread"])
		stats["sold_bread"] = int(stats["sold_bread"]) + int(result["sold_bread"])
		stats["sold_milk"] = int(stats["sold_milk"]) + int(result["sold_milk"])
		stats["unmet_bread"] = int(stats["unmet_bread"]) + bread_demand - int(result["sold_bread"])
		stats["unmet_milk"] = int(stats["unmet_milk"]) + milk_demand - int(result["sold_milk"])
		stats["blocked"] = int(stats["blocked"]) + int(result["blocked"])
		stats["cities"][str(city)] = result
	stats["cashflow"] = int(stats["revenue"]) - int(stats["expenses"])
	stats["profit"] = int(stats["revenue"]) - int(stats["cogs"]) - int(stats["operating_expense"])
	var after := monetary_total(company)
	stats["accounting_ok"] = before == after
	if not stats["accounting_ok"]:
		push_error("Economy cash conservation violated: %d versus %d" % [before, after])
	company.last_report = stats
	company.totals["revenue"] = int(company.totals["revenue"]) + int(stats["revenue"])
	company.totals["expenses"] = int(company.totals["expenses"]) + int(stats["expenses"])
	company.totals["cashflow"] = int(company.totals["cashflow"]) + int(stats["cashflow"])
	company.totals["profit"] = int(company.totals.get("profit", 0)) + int(stats["profit"])
	company.save_game()
	return stats
