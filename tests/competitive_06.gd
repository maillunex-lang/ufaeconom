extends SceneTree
const Market = preload("res://scripts/competitive_market.gd")
func _initialize() -> void:
	var offers: Array = [
		{"id": "a", "good": "Хлеб", "quantity": 12, "price": 120, "distance": 2, "reputation": 80},
		{"id": "b", "good": "Хлеб", "quantity": 15, "price": 110, "distance": 8, "reputation": 60}
	]
	var buyers: Array = [
		{"id": "resident-1", "good": "Хлеб", "budget": 1200, "demand": 8},
		{"id": "resident-2", "good": "Хлеб", "budget": 500, "demand": 7}
	]
	var result: Dictionary = Market.allocate(offers, buyers)
	assert(result["ok"])
	assert(result["trades"].size() > 0)
	assert(result["trades"][0]["offer_id"] == "b")
	var sold: int = 0
	var money: int = 0
	for trade in result["trades"]:
		sold += int(trade["quantity"])
		money += int(trade["total"])
	assert(sold <= 15)
	assert(money == int(result["spent"]["resident-1"]) + int(result["spent"]["resident-2"]))
	assert(money == int(result["sales"].get("a", 0)) + int(result["sales"].get("b", 0)))
	assert(int(result["spent"]["resident-1"]) <= 1200)
	assert(int(result["spent"]["resident-2"]) <= 500)
	assert(int(result["remaining"]["a"]) >= 0 and int(result["remaining"]["b"]) >= 0)
	assert(Market.allocate(offers, buyers) == result)
	assert(offers[0]["quantity"] == 12)
	assert(not Market.allocate([{"id":"x","good":"Хлеб","quantity":-1,"price":10}],buyers)["ok"])
	print("COMPETITIVE_06_TESTS_PASSED")
	quit(0)
