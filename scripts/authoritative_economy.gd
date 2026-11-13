extends RefCounted
class_name AuthoritativeEconomy

## Pure data prototype: server owns UTC clock, tick and command outcomes.
## No Node/Timer/FileAccess, no networking, no client-provided balances.
const Calendar = preload("res://scripts/game_calendar.gd")
const TICK_SECONDS: int = Calendar.REAL_SECONDS_PER_GAME_DAY
const MAX_TICKS_PER_BATCH: int = 90

static func create_world(epoch_unix: int, opening_cash: int = 100000) -> Dictionary:
	return {"epoch_unix": epoch_unix, "tick": 0, "wallets": {"player": opening_cash, "supplier": 0}, "stock": {"player": 0, "supplier": 10000}, "processed": {}, "events": [], "production_per_day": 10, "price_per_unit": 5}

static func due_ticks(world: Dictionary, server_now_unix: int) -> int:
	var epoch: int = int(world.get("epoch_unix", 0))
	if epoch <= 0 or server_now_unix <= epoch:
		return 0
	var target: int = int((server_now_unix - epoch) / TICK_SECONDS)
	return maxi(0, target - int(world.get("tick", 0)))

static func advance(world: Dictionary, server_now_unix: int) -> Dictionary:
	var due: int = due_ticks(world, server_now_unix)
	var processed: int = mini(due, MAX_TICKS_PER_BATCH)
	for i in range(processed):
		var next_tick: int = int(world["tick"]) + 1
		var wallets: Dictionary = world["wallets"]
		var stock: Dictionary = world["stock"]
		var available: int = int(stock["supplier"])
		var requested: int = maxi(0, int(world["production_per_day"]))
		var cost: int = maxi(1, int(world["price_per_unit"]))
		var quantity: int = mini(requested, mini(available, int(int(wallets["player"]) / cost)))
		var transfer: int = quantity * cost
		stock["supplier"] = available - quantity
		stock["player"] = int(stock["player"]) + quantity
		wallets["player"] = int(wallets["player"]) - transfer
		wallets["supplier"] = int(wallets["supplier"]) + transfer
		world["tick"] = next_tick
		world["events"].append({"tick": next_tick, "type": "supply.transfer", "quantity": quantity, "amount": transfer})
	return {"processed": processed, "pending": due - processed, "tick": int(world["tick"])}

static func apply_command(world: Dictionary, command: Dictionary) -> Dictionary:
	var id: String = str(command.get("command_id", ""))
	if id.is_empty():
		return {"ok": false, "error": "missing command_id"}
	var seen: Dictionary = world["processed"]
	if seen.has(id):
		return seen[id].duplicate(true)
	var result: Dictionary = {"ok": false, "error": "invalid command"}
	if int(command.get("expected_tick", -1)) != int(world["tick"]):
		result = {"ok": false, "error": "stale tick"}
	elif str(command.get("type", "")) == "supply.set_daily_limit":
		var limit: int = int(command.get("limit", -1))
		if limit >= 0 and limit <= 1000:
			world["production_per_day"] = limit
			result = {"ok": true, "tick": int(world["tick"]), "daily_limit": limit}
		else:
			result = {"ok": false, "error": "invalid limit"}
	seen[id] = result.duplicate(true)
	return result

static func money_total(world: Dictionary) -> int:
	var total: int = 0
	for amount in world["wallets"].values():
		total += int(amount)
	return total

static func goods_total(world: Dictionary) -> int:
	var total: int = 0
	for quantity in world["stock"].values():
		total += int(quantity)
	return total
