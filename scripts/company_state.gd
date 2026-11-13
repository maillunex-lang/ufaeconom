extends RefCounted
class_name CompanyState

## Offline sandbox economy: integer rubles, no multiplayer or real payments.
const START_CASH := 2000000
const LAND_PRICE := 120000
const CONSTRUCTION := {"Магазин": 350000, "Склад": 280000, "Завод": 800000}
const SAVE_PATH := "user://business_empire_03.json"
var cash: int = START_CASH
var owned: Dictionary = {}
var city_index: int = 0

func reset() -> void:
	cash = START_CASH
	owned.clear()
	city_index = 0

func key(city: int, tile: Vector2i) -> String:
	return "%d:%d:%d" % [city, tile.x, tile.y]

func owns(city: int, tile: Vector2i) -> bool:
	return owned.has(key(city, tile))

func buy(city: int, tile: Vector2i, kind: String) -> String:
	if kind != "Свободный участок":
		return "Можно купить только свободный участок"
	if owns(city, tile):
		return "Участок уже принадлежит компании"
	if cash < LAND_PRICE:
		return "Недостаточно средств для покупки"
	cash -= LAND_PRICE
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
	property["building"] = kind
	owned[id] = property
	save_game()
	return "%s построен за %d ₽" % [kind, price]

func building_at(city: int, tile: Vector2i) -> String:
	var property: Dictionary = owned.get(key(city, tile), {})
	return str(property.get("building", ""))

func save_game() -> bool:
	var items: Array = []
	for id in owned:
		items.append(owned[id])
	var data := {"version": 1, "cash": cash, "city_index": city_index, "properties": items}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return false
	if int(parsed.get("version", 0)) != 1:
		return false
	var loaded_cash := int(parsed.get("cash", -1))
	var loaded_city := int(parsed.get("city_index", -1))
	var properties: Variant = parsed.get("properties", [])
	if loaded_cash < 0 or loaded_city < 0 or loaded_city >= 4 or not (properties is Array):
		return false
	var next_owned: Dictionary = {}
	for item in properties:
		if not (item is Dictionary):
			return false
		var city := int(item.get("city", -1))
		var x := int(item.get("x", -1))
		var y := int(item.get("y", -1))
		var building := str(item.get("building", ""))
		if city < 0 or city >= 4 or x < 0 or x >= 32 or y < 0 or y >= 32:
			return false
		if building != "" and not CONSTRUCTION.has(building):
			return false
		var tile := Vector2i(x, y)
		next_owned[key(city, tile)] = {"city": city, "x": x, "y": y, "building": building}
	cash = loaded_cash
	city_index = loaded_city
	owned = next_owned
	return true
