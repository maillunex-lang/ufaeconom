extends RefCounted
class_name CompetitiveMarket

## Deterministic prototype for future server-authoritative market clearing.
## Prices, wallets and quantities are whole integer game units. No Godot scene access.
## Does not mutate offers or buyers; caller must apply returned trades atomically.
static func allocate(offers: Array, buyers: Array) -> Dictionary:
	var remaining: Dictionary = {}
	var spent: Dictionary = {}
	var trades: Array = []
	var sales: Dictionary = {}
	for offer in offers:
		var id: String = str(offer.get("id", ""))
		var quantity: int = int(offer.get("quantity", 0))
		var price: int = int(offer.get("price", 0))
		if id.is_empty() or remaining.has(id) or quantity < 0 or price <= 0:
			return {"ok": false, "reason": "invalid offer"}
		remaining[id] = quantity
	for buyer in buyers:
		var id: String = str(buyer.get("id", ""))
		var budget: int = int(buyer.get("budget", 0))
		var demand: int = int(buyer.get("demand", 0))
		if id.is_empty() or spent.has(id) or budget < 0 or demand < 0:
			return {"ok": false, "reason": "invalid buyer"}
		spent[id] = 0
		var candidates: Array = []
		for offer in offers:
			if str(offer.get("good", "")) != str(buyer.get("good", "")):
				continue
			var distance: int = int(offer.get("distance", 0))
			var reputation: int = int(offer.get("reputation", 50))
			if distance < 0 or reputation < 0 or reputation > 100:
				return {"ok": false, "reason": "invalid market score"}
			var score: int = int(offer["price"]) * 100 + distance * 12 - reputation * 2
			candidates.append({"offer": offer, "score": score})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["score"]) == int(b["score"]):
				return str(a["offer"]["id"]) < str(b["offer"]["id"])
			return int(a["score"]) < int(b["score"])
		)
		var budget_left: int = budget
		for candidate in candidates:
			if demand <= 0:
				break
			var offer: Dictionary = candidate["offer"]
			var offer_id: String = str(offer["id"])
			var price: int = int(offer["price"])
			var quantity: int = mini(demand, mini(int(remaining[offer_id]), int(budget_left / price)))
			if quantity <= 0:
				continue
			var total: int = quantity * price
			remaining[offer_id] = int(remaining[offer_id]) - quantity
			budget_left -= total
			demand -= quantity
			spent[id] = int(spent[id]) + total
			sales[offer_id] = int(sales.get(offer_id, 0)) + total
			trades.append({"buyer_id": id, "offer_id": offer_id, "good": str(offer["good"]), "quantity": quantity, "price": price, "total": total})
	return {"ok": true, "trades": trades, "remaining": remaining, "spent": spent, "sales": sales}
