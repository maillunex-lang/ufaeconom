extends RefCounted
class_name MarketDynamics

## 0.5 experimental market: integer prices and paid intercity cargo.
## Not an authoritative MMO economy. Values are gameplay hypotheses.
const BASE_PRICES := {"Зерно": 50, "Хлеб": 155, "Молоко": 180}
const FLOOR_BPS := 7000
const CEILING_BPS := 15000
const MAX_DAILY_CHANGE_BPS := 500
const TRANSIT_DAYS := 2
const SHIPPING_FEE_PER_UNIT := 8

static func new_prices() -> Dictionary:
	return BASE_PRICES.duplicate(true)

static func price(market: Dictionary, good: String) -> int:
	return maxi(1, int(market.get("prices", {}).get(good, BASE_PRICES.get(good, 1))))

static func adjust_price(market: Dictionary, good: String, demand: int, sold: int) -> int:
	if not BASE_PRICES.has(good):
		return 0
	var prices: Dictionary = market.get("prices", {})
	if prices.is_empty():
		prices = new_prices()
		market["prices"] = prices
	var old: int = price(market, good)
	var base: int = int(BASE_PRICES[good])
	var floor_price: int = maxi(1, int(base * FLOOR_BPS / 10000))
	var ceiling_price: int = maxi(floor_price, int(base * CEILING_BPS / 10000))
	# If no trade, do not assume a shortage without a demand signal.
	var change_bps := 0
	if demand > 0 and sold < demand:
		change_bps = MAX_DAILY_CHANGE_BPS
	elif demand > 0 and sold >= demand:
		change_bps = -MAX_DAILY_CHANGE_BPS
	var delta: int = maxi(1, int(old * abs(change_bps) / 10000)) if change_bps != 0 else 0
	var next_price: int = clampi(old + (delta if change_bps > 0 else -delta), floor_price, ceiling_price)
	prices[good] = next_price
	return next_price

static func queue_shipment(company: RefCounted, origin: int, destination: int, good: String, amount: int) -> String:
	if origin < 0 or origin >= 4 or destination < 0 or destination >= 4 or origin == destination:
		return "Некорректный маршрут"
	if amount <= 0 or not BASE_PRICES.has(good):
		return "Некорректный товар или объём"
	var from_market: Dictionary = company.market(origin)
	var from_stock: Dictionary = from_market["stock"]
	if int(from_stock.get(good, 0)) < amount:
		return "Недостаточно товара на складе отправления"
	var to_market: Dictionary = company.market(destination)
	var incoming := 0
	for shipment in company.shipments:
		if int(shipment["destination"]) == destination:
			incoming += int(shipment["amount"])
	if int(to_market["stock"].values().reduce(func(acc, x): return int(acc) + int(x), 0)) + incoming + amount > company.storage_capacity(destination):
		return "Недостаточно места на складе назначения"
	var fee: int = amount * SHIPPING_FEE_PER_UNIT
	if company.cash < fee:
		return "Недостаточно денег на перевозку"
	var old_count: int = int(from_stock[good])
	var costs: Dictionary = from_market["inventory_cost"]
	var cost: int = int(int(costs[good]) * amount / old_count)
	if amount == old_count:
		cost = int(costs[good])
	from_stock[good] = old_count - amount
	costs[good] = int(costs[good]) - cost
	company.cash -= fee
	from_market["supplier_cash"] = int(from_market["supplier_cash"]) + fee
	company.totals["expenses"] = int(company.totals["expenses"]) + fee
	company.totals["cashflow"] = int(company.totals["cashflow"]) - fee
	company.totals["profit"] = int(company.totals["profit"]) - fee
	company.shipments.append({
		"origin": origin, "destination": destination, "good": good,
		"amount": amount, "cost": cost, "arrival_day": company.day + TRANSIT_DAYS
	})
	company.save_game()
	return "Отправлено %d ед. %s, доставка через %d дня" % [amount, good, TRANSIT_DAYS]

static func deliver_shipments(company: RefCounted) -> int:
	var delivered := 0
	var pending: Array = []
	for shipment in company.shipments:
		if int(shipment["arrival_day"]) > company.day:
			pending.append(shipment)
			continue
		var dest: int = int(shipment["destination"])
		var market: Dictionary = company.market(dest)
		var amount: int = int(shipment["amount"])
		# Retain cargo in transit if the destination became full.
		var stock_total := 0
		for value in market["stock"].values():
			stock_total += int(value)
		if stock_total + amount > company.storage_capacity(dest):
			pending.append(shipment)
			continue
		var good: String = str(shipment["good"])
		market["stock"][good] = int(market["stock"][good]) + amount
		market["inventory_cost"][good] = int(market["inventory_cost"][good]) + int(shipment["cost"])
		delivered += amount
	company.shipments = pending
	return delivered
