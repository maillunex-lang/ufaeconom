extends RefCounted
class_name CompanyState

## 0.4 offline company. All money is integer game rubles.
const Economy = preload("res://scripts/economy_simulator.gd")
const START_CASH := 2000000
const LAND_PRICE := 120000
const CONSTRUCTION := {"Магазин": 350000, "Склад": 280000, "Завод": 800000}
const SAVE_PATH := "user://business_empire_04.json"
const LEGACY_SAVE_PATH := "user://business_empire_03.json"
const CITY_COUNT := 4
const MAP_SIZE := 32

var save_path: String = SAVE_PATH
var legacy_save_path: String = LEGACY_SAVE_PATH
var cash: int = START_CASH
var owned: Dictionary = {}
var city_index: int = 0
var day: int = 0
var markets: Dictionary = {}
var last_report: Dictionary = {}
var totals: Dictionary = {"revenue": 0, "expenses": 0, "cashflow": 0, "capital_expenditure": 0}

func reset() -> void:
	cash = START_CASH
	owned.clear()
	city_index = 0
	day = 0
	markets.clear()
	last_report.clear()
	totals = {"revenue": 0, "expenses": 0, "cashflow": 0, "capital_expenditure": 0}

func key(city: int, tile: Vector2i) -> String:
	return "%d:%d:%d" % [city, tile.x, tile.y]

func owns(city: int, tile: Vector2i) -> bool:
	return owned.has(key(city, tile))

func market(city: int) -> Dictionary:
	if city < 0 or city >= CITY_COUNT:
		push_error("Invalid city index in economy: %d" % city)
		return {}
	var id := str(city)
	if not markets.has(id):
		markets[id] = Economy.new_market()
	return markets[id]

func storage_capacity(city: int) -> int:
	return Economy.capacity(self, city)

func buy(city: int, tile: Vector2i, kind: String) -> String:
	if city < 0 or city >= CITY_COUNT or tile.x < 0 or tile.y < 0 or tile.x >= MAP_SIZE or tile.y >= MAP_SIZE:
		return "Некорректные координаты участка"
	if kind != "Свободный участок":
		return "Можно купить только свободный участок"
	if owns(city, tile):
		return "Участок уже принадлежит компании"
	if cash < LAND_PRICE:
		return "Недостаточно средств для покупки"
	cash -= LAND_PRICE
	var city_market := market(city)
	city_market["city_budget"] = int(city_market["city_budget"]) + LAND_PRICE
	totals["capital_expenditure"] = int(totals["capital_expenditure"]) + LAND_PRICE
	owned[key(city, tile)] = {"city": city, "x": tile.x, "y": tile.y, "building": ""}
	save_game()
	return "Участок куплен за %d ₽" % LAND_PRICE

func construct(city: int, tile: Vector2i, kind: String) -> String:
	var id := key(city, tile)
	if not owned.has(id):
		return "Сначала купите участок"
	var property: Dictionary = owned[id]
	if property["building"] != "":
		return "На участке уже построено здание"
	if not CONSTRUCTION.has(kind):
		return "Неизвестный тип предприятия"
	var price: int = CONSTRUCTION[kind]
	if cash < price:
		return "Недостаточно средств для строительства"
	cash -= price
	var city_market := market(city)
	city_market["supplier_cash"] = int(city_market["supplier_cash"]) + price
	totals["capital_expenditure"] = int(totals["capital_expenditure"]) + price
	property["building"] = kind
	owned[id] = property
	save_game()
	return "%s построен за %d ₽" % [kind, price]

func building_at(city: int, tile: Vector2i) -> String:
	var property: Dictionary = owned.get(key(city, tile), {})
	return str(property.get("building", ""))

func advance_day() -> Dictionary:
	return Economy.step(self)

func save_game() -> bool:
	var items: Array = []
	for id in owned:
		items.append(owned[id])
	var data := {
		"version": 2, "cash": cash, "city_index": city_index,
		"day": day, "properties": items, "markets": markets,
		"totals": totals, "last_report": last_report
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Unable to save game: %d" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	return true

func load_game() -> bool:
	var path := save_path
	if not FileAccess.file_exists(path):
		path = legacy_save_path
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return false
	var version := int(parsed.get("version", -1))
	if version != 1 and version != 2:
		return false
	var new_cash := int(parsed.get("cash", -1))
	var new_city := int(parsed.get("city_index", -1))
	var new_day := int(parsed.get("day", 0)) if version == 2 else 0
	var properties: Variant = parsed.get("properties", [])
	if new_cash < 0 or new_city < 0 or new_city >= CITY_COUNT or new_day < 0 or not (properties is Array):
		return false
	var new_owned: Dictionary = {}
	for item in properties:
		if not (item is Dictionary):
			return false
		var city := int(item.get("city", -1))
		var x := int(item.get("x", -1))
		var y := int(item.get("y", -1))
		var building := str(item.get("building", ""))
		if city < 0 or city >= CITY_COUNT or x < 0 or y < 0 or x >= MAP_SIZE or y >= MAP_SIZE:
			return false
		if building != "" and not CONSTRUCTION.has(building):
			return false
		var id := key(city, Vector2i(x, y))
		if new_owned.has(id):
			return false
		new_owned[id] = {"city": city, "x": x, "y": y, "building": building}
	var new_markets: Dictionary = {}
	var new_totals: Dictionary = {"revenue": 0, "expenses": 0, "cashflow": 0, "capital_expenditure": 0}
	var new_report: Dictionary = {}
	if version == 2:
		var market_data: Variant = parsed.get("markets", {})
		var total_data: Variant = parsed.get("totals", {})
		var report_data: Variant = parsed.get("last_report", {})
		if not (market_data is Dictionary) or not (total_data is Dictionary) or not (report_data is Dictionary):
			return false
		for id in market_data:
			if not (str(id) in ["0", "1", "2", "3"]):
				return false
			var input_market: Variant = market_data[id]
			if not (input_market is Dictionary) or not (input_market.get("stock", null) is Dictionary):
				return false
			var stock_input: Dictionary = input_market["stock"]
			var stock: Dictionary = {}
			for good in Economy.GOODS:
				var count := int(stock_input.get(good, -1))
				if count < 0:
					return false
				stock[good] = count
			var wallets: Dictionary = {"stock": stock}
			for name in ["residents_cash", "supplier_cash", "city_budget"]:
				var amount := int(input_market.get(name, -1))
				if amount < 0:
					return false
				wallets[name] = amount
			new_markets[id] = wallets
		for name in new_totals:
			var amount := int(total_data.get(name, 0))
			if amount < 0 and name != "cashflow":
				return false
			new_totals[name] = amount
		new_report = report_data
	# Commit only after the complete save has been validated.
	cash = new_cash
	city_index = new_city
	day = new_day
	owned = new_owned
	markets = new_markets
	totals = new_totals
	last_report = new_report
	return true
