"""BUSINESS EMPIRE ONLINE 0.6 authoritative economy rules.

All money is integer kopecks; 240 real seconds = one production tick.
This module has no filesystem, network, device clock or third-party dependencies.
City route distances and economic coefficients are *fictional test parameters*.
"""
from __future__ import annotations

import copy
import json

GOODS = ("grain", "bread", "milk")
CITIES = ("ufa", "sterlitamak", "tuymazy", "beloretsk")
TICK_SECONDS = 240
TICKS_PER_DAY = 12
TICKS_PER_MONTH = 360
ROUTE_KM = {
    ("ufa", "sterlitamak"): 135,
    ("ufa", "tuymazy"): 185,
    ("ufa", "beloretsk"): 275,
    ("sterlitamak", "tuymazy"): 310,
    ("sterlitamak", "beloretsk"): 245,
    ("tuymazy", "beloretsk"): 410,
}
BASE_PRICES = {"grain": 5000, "bread": 15500, "milk": 18000}
SOURCE_PRICES = {"grain": 5000, "milk": 11000}
BUILD_COSTS = {"factory": 80000000, "shop": 35000000, "warehouse": 28000000}
CAPACITY = {"factory": 120, "shop": 90, "warehouse": 300}
DEMAND = {
    "ufa": {"bread": 6, "milk": 3},
    "sterlitamak": {"bread": 4, "milk": 2},
    "tuymazy": {"bread": 3, "milk": 2},
    "beloretsk": {"bread": 3, "milk": 1},
}
SALES_TAX_BPS = 500
TRANSPORT_CAPACITY = 50


class EconomyError(ValueError):
    """Invalid economic command, not an infrastructure failure."""


def _facility(owner: str, city: str, kind: str, ident: str,
              stock: dict[str, int] | None = None) -> dict:
    return {
        "id": ident, "owner": owner, "city": city, "kind": kind,
        "stock": {good: int((stock or {}).get(good, 0)) for good in GOODS},
        "basis": {good: 0 for good in GOODS}, "capacity": CAPACITY[kind],
        "prices": {"bread": BASE_PRICES["bread"], "milk": BASE_PRICES["milk"]},
        "reputation": 70 if owner == "player" else 60,
        "customer_distance_km": 3 if owner == "player" else 7,
        "auto_buy_limit": 2 if kind == "factory" else 0,
    }


def new_world(epoch_unix: int = 1800000000) -> dict:
    if epoch_unix <= 0:
        raise EconomyError("epoch must be positive")
    wallets = {"company:player": 200_000_000, "company:rival": 200_000_000,
               "company:npc": 200_000_000}
    suppliers, facilities = {}, {}
    for city in CITIES:
        wallets[f"residents:{city}"] = 20_000_000
        wallets[f"suppliers:{city}"] = 10_000_000
        wallets[f"treasury:{city}"] = 10_000_000
        suppliers[city] = {"grain": 1000, "milk": 400}
    for item in (
        _facility("player", "ufa", "factory", "player-factory", {"grain": 60}),
        _facility("player", "ufa", "shop", "player-shop", {"bread": 30, "milk": 10}),
        _facility("player", "sterlitamak", "shop", "player-sterlitamak", {"bread": 10}),
        _facility("rival", "tuymazy", "shop", "rival-shop", {"bread": 22}),
        _facility("rival", "sterlitamak", "factory", "rival-factory", {"grain": 60}),
        _facility("npc", "ufa", "factory", "npc-factory", {"grain": 60}),
        _facility("npc", "ufa", "shop", "npc-shop", {"bread": 30, "milk": 10}),
        _facility("npc", "sterlitamak", "shop", "npc-sterlitamak", {"bread": 20}),
    ):
        facilities[item["id"]] = item
    facilities["npc-shop"]["prices"]["bread"] = 15000
    audit = {good: {"initial": 0, "sourced": 0, "converted_in": 0,
                    "converted_out": 0, "consumed": 0} for good in GOODS}
    w = {
        "schema": 1, "epoch_unix": epoch_unix, "tick": 0, "revision": 0,
        "wallets": wallets, "suppliers": suppliers, "facilities": facilities,
        "shipments": [], "next_shipment": 1, "next_facility": 1,
        "receipts": {}, "audit": audit, "pending_ledger": [],
        "stats": {"sales": 0, "units_sold": 0, "delivered": 0,
                  "produced": 0, "blocked": 0, "days_closed": 0},
        "last_sales": {}, "month_reports": [],
        "company_metrics": {owner: {"revenue": 0, "cogs": 0,
                                     "operating_expense": 0, "freight": 0,
                                     "capital_expenditure": 0, "profit": 0}
                            for owner in ("player", "rival", "npc")},
    }
    for good in GOODS:
        audit[good]["initial"] = goods_total(w)[good]
    w["initial_money"] = money_total(w)
    return w


def copy_world(world: dict) -> dict:
    return copy.deepcopy(world)


def route_km(origin: str, destination: str) -> int:
    if origin not in CITIES or destination not in CITIES:
        raise EconomyError("unknown city")
    if origin == destination:
        return 8
    return ROUTE_KM.get((origin, destination),
                        ROUTE_KM.get((destination, origin), 0))


def shipment_fee(distance_km: int, amount: int) -> int:
    if distance_km <= 0 or amount <= 0:
        raise EconomyError("invalid freight")
    return 2000 + distance_km * 12 + amount * distance_km // 3


def eta_ticks(distance_km: int) -> int:
    return max(1, (distance_km + 59) // 60)


def money_total(w: dict) -> int:
    return sum(w["wallets"].values())


def goods_total(w: dict) -> dict[str, int]:
    totals = {g: 0 for g in GOODS}
    for supplier in w["suppliers"].values():
        for good, count in supplier.items():
            totals[good] += count
    for fac in w["facilities"].values():
        for good in GOODS:
            totals[good] += fac["stock"][good]
    for shipment in w["shipments"]:
        totals[shipment["good"]] += shipment["amount"]
    return totals


def audit_world(w: dict) -> bool:
    if any(not isinstance(v, int) or v < 0 for v in w["wallets"].values()):
        return False
    if money_total(w) != w["initial_money"]:
        return False
    for fac in w["facilities"].values():
        if (any(v < 0 for v in fac["stock"].values()) or
                any(v < 0 for v in fac["basis"].values()) or
                sum(fac["stock"].values()) > fac["capacity"]):
            return False
    if any(v < 0 for supplier in w["suppliers"].values() for v in supplier.values()):
        return False
    for shipment in w["shipments"]:
        if shipment["amount"] <= 0 or shipment["basis"] < 0:
            return False
    stock = goods_total(w)
    for good in GOODS:
        a = w["audit"][good]
        expected = (a["initial"] + a["sourced"] + a["converted_out"]
                    - a["converted_in"] - a["consumed"])
        if stock[good] != expected:
            return False
    return True


def _money(w: dict, payer: str, payee: str, amount: int, kind: str,
           ref: str = "") -> None:
    if amount < 0 or w["wallets"][payer] < amount:
        raise EconomyError("insufficient funds")
    if amount == 0:
        return
    w["wallets"][payer] -= amount
    w["wallets"][payee] += amount
    if payer.startswith("company:"):
        owner = payer.split(":", 1)[1]
        metrics = w["company_metrics"][owner]
        if kind == "construction":
            metrics["capital_expenditure"] += amount
        elif kind not in ("inventory.purchase",):
            metrics["operating_expense"] += amount
            metrics["profit"] -= amount
            if kind == "freight":
                metrics["freight"] += amount
    if payee.startswith("company:") and kind == "retail.sale":
        metrics = w["company_metrics"][payee.split(":", 1)[1]]
        metrics["revenue"] += amount
        metrics["profit"] += amount
    w["pending_ledger"].append({
        "tick": w["tick"], "debit": payer, "credit": payee,
        "amount": amount, "kind": kind, "ref": ref,
    })


def _take(fac: dict, good: str, count: int) -> int:
    if count <= 0 or fac["stock"][good] < count:
        raise EconomyError("not enough stock")
    previous = fac["stock"][good]
    cost = (fac["basis"][good] * count // previous)
    if count == previous:
        cost = fac["basis"][good]
    fac["stock"][good] -= count
    fac["basis"][good] -= cost
    return cost


def _put(fac: dict, good: str, count: int, cost: int) -> None:
    if count < 0 or cost < 0 or sum(fac["stock"].values()) + count > fac["capacity"]:
        raise EconomyError("warehouse full")
    fac["stock"][good] += count
    fac["basis"][good] += cost


def _inbound(w: dict, facility_id: str) -> int:
    return sum(s["amount"] for s in w["shipments"]
               if s["to"] == facility_id)


def _buy(w: dict, fac: dict, good: str, count: int) -> int:
    if good not in SOURCE_PRICES or count <= 0:
        return 0
    market = w["suppliers"][fac["city"]]
    affordable = w["wallets"]["company:" + fac["owner"]] // SOURCE_PRICES[good]
    free = fac["capacity"] - sum(fac["stock"].values()) - _inbound(w, fac["id"])
    amount = min(count, market[good], affordable, free)
    if amount <= 0:
        return 0
    cost = amount * SOURCE_PRICES[good]
    _money(w, "company:" + fac["owner"], "suppliers:" + fac["city"],
           cost, "inventory.purchase", fac["id"])
    market[good] -= amount
    _put(fac, good, amount, cost)
    return amount


def _replenish_suppliers(w: dict) -> None:
    for city in CITIES:
        market = w["suppliers"][city]
        # Explicit bounded NPC agricultural production (source of physical goods).
        for good, generated, cap in (("grain", 4, 1500), ("milk", 2, 600)):
            amount = max(0, min(generated, cap - market[good]))
            market[good] += amount
            w["audit"][good]["sourced"] += amount


def _deliver(w: dict) -> None:
    pending = []
    for cargo in w["shipments"]:
        if cargo["eta_tick"] > w["tick"]:
            pending.append(cargo)
            continue
        dest = w["facilities"][cargo["to"]]
        if sum(dest["stock"].values()) + cargo["amount"] > dest["capacity"]:
            cargo["status"] = "waiting_capacity"
            pending.append(cargo)
            continue
        _put(dest, cargo["good"], cargo["amount"], cargo["basis"])
        w["stats"]["delivered"] += cargo["amount"]
    w["shipments"] = pending


def _produce(w: dict) -> None:
    for fac_id in sorted(w["facilities"]):
        fac = w["facilities"][fac_id]
        if fac["kind"] != "factory":
            continue
        if fac["stock"]["grain"] < 1:
            _buy(w, fac, "grain", fac["auto_buy_limit"])
        if (fac["stock"]["grain"] < 1 or
                sum(fac["stock"].values()) + 1 > fac["capacity"] or
                w["wallets"]["company:" + fac["owner"]] < 4000):
            w["stats"]["blocked"] += 1
            continue
        _money(w, "company:" + fac["owner"], "residents:" + fac["city"],
               3000, "wages", fac_id)
        _money(w, "company:" + fac["owner"], "suppliers:" + fac["city"],
               1000, "energy", fac_id)
        consumed_cost = _take(fac, "grain", 1)
        _put(fac, "bread", 2, consumed_cost + 4000)
        w["audit"]["grain"]["converted_in"] += 1
        w["audit"]["bread"]["converted_out"] += 2
        w["stats"]["produced"] += 2


def _local_restock(w: dict) -> None:
    for owner in ("npc", "player", "rival"):
        for city in CITIES:
            factories = sorted((f for f in w["facilities"].values()
                                if f["owner"] == owner and f["city"] == city
                                and f["kind"] == "factory"), key=lambda f: f["id"])
            shops = sorted((f for f in w["facilities"].values()
                            if f["owner"] == owner and f["city"] == city
                            and f["kind"] == "shop"), key=lambda f: f["id"])
            for shop in shops:
                for factory in factories:
                    count = min(2, factory["stock"]["bread"],
                                shop["capacity"] - sum(shop["stock"].values()))
                    if count > 0:
                        basis = _take(factory, "bread", count)
                        _put(shop, "bread", count, basis)


def _retail(w: dict) -> None:
    recent = {}
    for city in CITIES:
        for good in ("bread", "milk"):
            shops = [fac for fac in w["facilities"].values()
                     if fac["kind"] == "shop" and fac["city"] == city
                     and fac["stock"][good] > 0]
            if not shops:
                continue
            shops.sort(key=lambda f: (f["prices"][good] * 100 +
                                      f["customer_distance_km"] * 12 -
                                      f["reputation"] * 2, f["id"]))
            # Price elasticity: expensive goods reduce *aggregate* demand.
            best_price = shops[0]["prices"][good]
            demand = min(DEMAND[city][good] * 2,
                         DEMAND[city][good] * BASE_PRICES[good] // best_price)
            affordable = w["wallets"]["residents:" + city]
            for fac in shops:
                price = fac["prices"][good]
                qty = min(demand, fac["stock"][good], affordable // price)
                if qty <= 0:
                    continue
                cost = _take(fac, good, qty)
                metrics = w["company_metrics"][fac["owner"]]
                metrics["cogs"] += cost
                metrics["profit"] -= cost
                receipt = qty * price
                _money(w, "residents:" + city, "company:" + fac["owner"],
                       receipt, "retail.sale", fac["id"])
                tax = receipt * SALES_TAX_BPS // 10000
                _money(w, "company:" + fac["owner"], "treasury:" + city,
                       tax, "retail.tax", fac["id"])
                w["audit"][good]["consumed"] += qty
                w["stats"]["sales"] += receipt
                w["stats"]["units_sold"] += qty
                recent[fac["id"] + ":" + good] = {"units": qty, "revenue": receipt,
                                                  "cost_basis": cost}
                affordable -= receipt
                demand -= qty
                if demand <= 0:
                    break
    w["last_sales"] = recent


def _close_month(w: dict) -> None:
    # One rent charge per facility, once every 360 production ticks.
    for fac in w["facilities"].values():
        fee = {"factory": 12_000, "shop": 8_000, "warehouse": 4_000}[fac["kind"]]
        owner = "company:" + fac["owner"]
        paid = min(fee, w["wallets"][owner])
        _money(w, owner, "treasury:" + fac["city"], paid, "monthly.rent", fac["id"])
    w["stats"]["days_closed"] += 30
    w["month_reports"].append({"month": w["tick"] // TICKS_PER_MONTH,
                               "sales_minor": w["stats"]["sales"]})
    if len(w["month_reports"]) > 24:
        w["month_reports"] = w["month_reports"][-24:]


def advance(w: dict, ticks: int = 1) -> None:
    if type(ticks) is not int or ticks < 0 or ticks > 360:
        raise EconomyError("invalid tick count")
    for _ in range(ticks):
        w["tick"] += 1
        _replenish_suppliers(w)
        _deliver(w)
        _produce(w)
        _local_restock(w)
        _retail(w)
        if w["tick"] % TICKS_PER_MONTH == 0:
            _close_month(w)
        w["revision"] += 1


def due_ticks(w: dict, server_now_unix: int) -> int:
    if type(server_now_unix) is not int:
        raise EconomyError("server time must be integer unix seconds")
    return max(0, (server_now_unix - w["epoch_unix"]) // TICK_SECONDS - w["tick"])


def apply_command(w: dict, actor: str, command: dict) -> dict:
    if actor not in ("player", "rival"):
        raise EconomyError("unknown actor")
    command_id = command.get("command_id")
    if not isinstance(command_id, str) or not (8 <= len(command_id) <= 120):
        raise EconomyError("invalid command id")
    if any(not (ch.isascii() and (ch.isalnum() or ch in "-_:.")) for ch in command_id):
        raise EconomyError("invalid command id")
    key = actor + ":" + command_id
    fingerprint = json.dumps(command, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    existing = w["receipts"].get(key)
    if existing is not None:
        if existing["fingerprint"] != fingerprint:
            raise EconomyError("command id reused with different payload")
        return copy.deepcopy(existing["result"])
    if type(command.get("expected_revision")) is not int or command["expected_revision"] != w["revision"]:
        raise EconomyError("stale world revision")
    kind = command.get("type")
    fac_id = command.get("facility_id")
    if fac_id is not None and not isinstance(fac_id, str):
        raise EconomyError("invalid facility id")
    fac = w["facilities"].get(fac_id)
    if kind in ("facility.set_price", "facility.buy", "shipment.create"):
        if fac is None or fac["owner"] != actor:
            raise EconomyError("facility not owned")
    if kind == "facility.set_price":
        good = command.get("good")
        price = command.get("price_minor")
        if (fac["kind"] != "shop" or not isinstance(good, str) or good not in ("bread", "milk") or
                type(price) is not int or
                not BASE_PRICES[good] * 7 // 10 <= price <= BASE_PRICES[good] * 3 // 2):
            raise EconomyError("invalid offer")
        fac["prices"][good] = price
        result = {"ok": True, "price_minor": price}
    elif kind == "facility.buy":
        good, quantity = command.get("good"), command.get("quantity")
        if (not isinstance(good, str) or good not in SOURCE_PRICES or type(quantity) is not int or
                not 1 <= quantity <= 100):
            raise EconomyError("invalid purchase")
        capacity_left = fac["capacity"] - sum(fac["stock"].values()) - _inbound(w, fac["id"])
        funds = w["wallets"]["company:" + actor]
        if (w["suppliers"][fac["city"]][good] < quantity or
                capacity_left < quantity or
                funds < SOURCE_PRICES[good] * quantity):
            raise EconomyError("insufficient stock, space or funds")
        bought = _buy(w, fac, good, quantity)
        result = {"ok": True, "quantity": bought}
    elif kind == "shipment.create":
        destination_id = command.get("destination_id")
        if not isinstance(destination_id, str):
            raise EconomyError("invalid destination")
        dst = w["facilities"].get(destination_id)
        good, amount = command.get("good"), command.get("quantity")
        if (dst is None or dst["owner"] != actor or dst["id"] == fac_id or
                not isinstance(good, str) or good not in GOODS or type(amount) is not int or
                not 1 <= amount <= TRANSPORT_CAPACITY):
            raise EconomyError("invalid shipment")
        distance = route_km(fac["city"], dst["city"])
        fee = shipment_fee(distance, amount)
        if (fac["stock"][good] < amount or
                sum(dst["stock"].values()) + _inbound(w, dst["id"]) + amount > dst["capacity"] or
                w["wallets"]["company:" + actor] < fee):
            raise EconomyError("insufficient stock, space or funds")
        _money(w, "company:" + actor, "suppliers:" + fac["city"], fee,
               "freight", fac_id)
        basis = _take(fac, good, amount)
        shipment_id = "s" + str(w["next_shipment"])
        w["next_shipment"] += 1
        w["shipments"].append({
            "id": shipment_id, "owner": actor, "from": fac_id, "to": dst["id"],
            "good": good, "amount": amount, "basis": basis,
            "distance_km": distance, "fee_minor": fee,
            "eta_tick": w["tick"] + eta_ticks(distance), "status": "in_transit",
        })
        result = {"ok": True, "shipment_id": shipment_id,
                  "fee_minor": fee, "eta_tick": w["tick"] + eta_ticks(distance)}
    elif kind == "facility.build":
        city, facility_type = command.get("city"), command.get("kind")
        if not isinstance(city, str) or not isinstance(facility_type, str) or city not in CITIES or facility_type not in BUILD_COSTS:
            raise EconomyError("invalid construction")
        if sum(1 for f in w["facilities"].values()
               if f["owner"] == actor and f["city"] == city) >= 32:
            raise EconomyError("city property cap reached")
        price = BUILD_COSTS[facility_type]
        if w["wallets"]["company:" + actor] < price:
            raise EconomyError("insufficient funds")
        ident = actor + "-built-" + str(w["next_facility"])
        w["next_facility"] += 1
        _money(w, "company:" + actor, "suppliers:" + city,
               price, "construction", ident)
        w["facilities"][ident] = _facility(actor, city, facility_type, ident)
        result = {"ok": True, "facility_id": ident}
    else:
        raise EconomyError("unsupported command")
    w["revision"] += 1
    result["revision"] = w["revision"]
    w["receipts"][key] = {"fingerprint": fingerprint, "result": copy.deepcopy(result)}
    return result


def snapshot(w: dict, actor: str) -> dict:
    if actor not in ("player", "rival"):
        raise EconomyError("unknown actor")
    own = {fid: copy.deepcopy(fac) for fid, fac in w["facilities"].items()
           if fac["owner"] == actor}
    market = {city: {
        "shops": [
            {"id": f["id"], "owner": f["owner"], "bread_price_minor": f["prices"]["bread"],
             "bread_stock": f["stock"]["bread"]}
            for f in sorted(w["facilities"].values(), key=lambda f: f["id"])
            if f["city"] == city and f["kind"] == "shop"
        ],
        "demand_per_tick": DEMAND[city],
    } for city in CITIES}
    return {
        "schema": w["schema"], "tick": w["tick"], "revision": w["revision"],
        "game_day": w["tick"] // TICKS_PER_DAY,
        "game_month": w["tick"] // TICKS_PER_MONTH,
        "ticks_per_game_day": TICKS_PER_DAY,
        "server_epoch_unix": w["epoch_unix"],
        "company": actor, "cash_minor": w["wallets"]["company:" + actor],
        "facilities": own,
        "shipments": copy.deepcopy([s for s in w["shipments"] if s["owner"] == actor]),
        "market": market, "stats": copy.deepcopy(w["stats"]),
        "company_metrics": copy.deepcopy(w["company_metrics"][actor]),
    }
