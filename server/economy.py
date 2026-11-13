"""BUSINESS EMPIRE ONLINE 0.6 authoritative economy rules.

All money is integer kopecks; 240 real seconds = one production tick.
This module has no filesystem, network, device clock or third-party dependencies.
City route distances and economic coefficients are *fictional test parameters*.
"""
from __future__ import annotations

import copy
import json
import re
from . import land

GOODS = ("grain", "bread", "milk", "flour")
RECIPES = {"bread": ("grain", 1, "bread", 2), "flour": ("grain", 1, "flour", 2), "bakery": ("flour", 1, "bread", 3)}
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
BASE_PRICES = {"grain": 5000, "bread": 15500, "milk": 18000, "flour": 10000}
SOURCE_PRICES = {"grain": 5000, "milk": 11000}
BUILD_COSTS = {"factory": 80000000, "shop": 35000000, "warehouse": 28000000, "mine": 70000000, "research_center": 60000000, "car_dealership": 50000000}
CAPACITY = {"factory": 120, "shop": 90, "warehouse": 300, "mine": 120, "research_center": 80, "car_dealership": 90}
DEMAND = {
    "ufa": {"bread": 6, "milk": 3, "flour": 2},
    "sterlitamak": {"bread": 4, "milk": 2, "flour": 2},
    "tuymazy": {"bread": 3, "milk": 2, "flour": 1},
    "beloretsk": {"bread": 3, "milk": 1, "flour": 1},
}
SALES_TAX_BPS = 500
STAFF_CAP = {"factory": 20, "shop": 12, "warehouse": 8, "mine": 16, "research_center": 12, "car_dealership": 10}
STAFF_BASE = {"factory": 4, "shop": 3, "warehouse": 2, "mine": 4, "research_center": 3, "car_dealership": 3}
WAGE_MINOR = 750
MAX_PRODUCTION_BATCH = 4

TRANSPORT_CAPACITY = 50


class EconomyError(ValueError):
    """Invalid economic command, not an infrastructure failure."""


def _facility(owner: str, city: str, kind: str, ident: str,
              stock: dict[str, int] | None = None) -> dict:
    return {
        "id": ident, "owner": owner, "city": city, "kind": kind,
        "stock": {good: int((stock or {}).get(good, 0)) for good in GOODS},
        "basis": {good: 0 for good in GOODS}, "capacity": CAPACITY[kind],
        "prices": {good: BASE_PRICES[good] for good in ("bread", "milk", "flour")},
        "reputation": 70 if owner != "npc" else 60,
        "customer_distance_km": 3 if owner != "npc" else 7,
        "auto_buy_limit": 2 if kind == "factory" else 0,
        "workers": STAFF_BASE[kind], "wage_minor": WAGE_MINOR,
        "production_target": 1, "recipe": "bread", "equipment_level": 1,
        "production_last_tick": 0,
        "production_last_units": 0,
        "freight_priority": "standard",
    }


def new_world(epoch_unix: int = 1800000000) -> dict:
    if epoch_unix <= 0:
        raise EconomyError("epoch must be positive")
    wallets = {"company:player": 200_000_000, "company:rival": 200_000_000,
               "company:npc": 200_000_000,
               "treasury:central": 100_000_000_000}
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
        "receipts": {}, "audit": audit, "pending_ledger": [], "finance_history": [],
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
    land.ensure_world(w)
    return w


def migrate_industry(w: dict) -> None:
    """In-memory additive migration of 0.7.7 saves; persisted on next atomic commit."""
    if "flour" not in w["audit"]:
        w["audit"]["flour"] = {"initial": 0, "sourced": 0,
                                 "converted_in": 0, "converted_out": 0, "consumed": 0}
    for fac in w["facilities"].values():
        fac["stock"].setdefault("flour", 0)
        fac["basis"].setdefault("flour", 0)
        fac["prices"].setdefault("flour", BASE_PRICES["flour"])
        fac.setdefault("recipe", "bread")
        fac.setdefault("equipment_level", 1)
    for city in CITIES:
        w["suppliers"][city].setdefault("flour", 0)


def register_company(w: dict, actor: str, city: str = "ufa") -> None:
    """Admin-only onboarding. A finite central development pool funds starters."""
    if (not isinstance(actor, str) or
            re.fullmatch(r"[a-z][a-z0-9_-]{2,24}", actor) is None or
            actor == "npc" or city not in CITIES or
            "company:" + actor in w["wallets"]):
        raise EconomyError("invalid new company")
    opening = 200_000_000
    if w["wallets"]["treasury:central"] < opening:
        raise EconomyError("development fund exhausted")
    w["wallets"]["company:" + actor] = 0
    w["company_metrics"][actor] = {"revenue": 0, "cogs": 0,
                                    "operating_expense": 0, "freight": 0,
                                    "capital_expenditure": 0, "profit": 0}
    _money(w, "treasury:central", "company:" + actor,
           opening, "company.starter_grant", actor)
    for kind in ("factory", "shop"):
        ident = actor + "-" + kind + "-starter"
        _money(w, "company:" + actor, "suppliers:" + city,
               BUILD_COSTS[kind], "construction", ident)
        w["facilities"][ident] = _facility(actor, city, kind, ident)
    land.ensure_world(w)
    w["revision"] += 1


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
    for fac in w["facilities"].values():
        staff = fac.get("workers", STAFF_BASE[fac["kind"]])
        wage = fac.get("wage_minor", WAGE_MINOR)
        target = fac.get("production_target", 1)
        if (fac.get("recipe", "bread") not in RECIPES or
                type(fac.get("equipment_level", 1)) is not int or
                not 1 <= fac.get("equipment_level", 1) <= 3):
            return False
        if (type(staff) is not int or not 0 <= staff <= STAFF_CAP[fac["kind"]] or
                type(wage) is not int or not 500 <= wage <= 3000 or
                type(target) is not int or not 0 <= target <= MAX_PRODUCTION_BATCH):
            return False
    return land.audit(w)


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
        if kind in ("construction", "land.purchase", "equipment.purchase"):
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
    entry = {"tick": w["tick"], "debit": payer, "credit": payee,
             "amount": amount, "kind": kind, "ref": ref}
    w["pending_ledger"].append(entry)
    # Bounded read model, unlike the durable SQLite finance_ledger.
    w.setdefault("finance_history", []).append(entry.copy())
    if len(w["finance_history"]) > 200:
        del w["finance_history"][:-200]


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
        workers = fac.get("workers", STAFF_BASE["factory"])
        wage = fac.get("wage_minor", WAGE_MINOR)
        requested = fac.get("production_target", 1)
        # 4 workers per unit, capped by the player's target and physical stock.
        equipment = fac.get("equipment_level", 1)
        units = min(MAX_PRODUCTION_BATCH, requested, workers // 4)
        recipe = fac.get("recipe", "bread")
        ingredient, input_qty, output_good, output_qty = RECIPES[recipe]
        fac["production_last_tick"] = w["tick"]
        fac["production_last_units"] = 0
        for _ in range(units):
            if ingredient == "grain" and fac["stock"]["grain"] < input_qty:
                _buy(w, fac, "grain", fac["auto_buy_limit"])
            wages = 4 * wage
            energy = 1000 - 200 * (equipment - 1)
            if (fac["stock"][ingredient] < input_qty or
                    sum(fac["stock"].values()) - input_qty + output_qty > fac["capacity"] or
                    w["wallets"]["company:" + fac["owner"]] < wages + energy):
                w["stats"]["blocked"] += 1
                break
            _money(w, "company:" + fac["owner"], "residents:" + fac["city"],
                   wages, "wages", fac_id)
            _money(w, "company:" + fac["owner"], "suppliers:" + fac["city"],
                   energy, "energy", fac_id)
            consumed_cost = _take(fac, ingredient, input_qty)
            _put(fac, output_good, output_qty, consumed_cost + wages + energy)
            w["audit"][ingredient]["converted_in"] += input_qty
            w["audit"][output_good]["converted_out"] += output_qty
            w["stats"]["produced"] += output_qty
            fac["production_last_units"] += output_qty


def _local_restock(w: dict) -> None:
    for owner in sorted({f["owner"] for f in w["facilities"].values()}):
        for city in CITIES:
            factories = sorted((f for f in w["facilities"].values()
                                if f["owner"] == owner and f["city"] == city
                                and f["kind"] == "factory"), key=lambda f: f["id"])
            shops = sorted((f for f in w["facilities"].values()
                            if f["owner"] == owner and f["city"] == city
                            and f["kind"] == "shop"), key=lambda f: f["id"])
            for shop in shops:
                for factory in factories:
                    for good in ("bread", "flour"):
                        count = min(2, factory["stock"][good],
                                    shop["capacity"] - sum(shop["stock"].values()))
                        if count > 0:
                            basis = _take(factory, good, count)
                            _put(shop, good, count, basis)


def _npc_reprice(w: dict) -> None:
    """Bounded 1%-per-day NPC responses to other shops' *public* prices."""
    for fac in w["facilities"].values():
        if fac["owner"] != "npc" or fac["kind"] != "shop":
            continue
        for good in ("bread", "milk", "flour"):
            rivals = [other["prices"][good] for other in w["facilities"].values()
                      if other["city"] == fac["city"] and other["kind"] == "shop"
                      and other["owner"] != "npc" and other["stock"][good] > 0]
            if not rivals:
                continue
            old = fac["prices"][good]
            desired = min(rivals) - 100
            maximum_delta = max(1, old // 100)
            next_price = old + max(-maximum_delta, min(maximum_delta, desired - old))
            fac["prices"][good] = max(BASE_PRICES[good] * 7 // 10,
                                     min(BASE_PRICES[good] * 3 // 2, next_price))


def _retail(w: dict) -> None:
    recent = {}
    for city in CITIES:
        for good in ("bread", "milk", "flour"):
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
        fee = {"factory": 12_000, "shop": 8_000, "warehouse": 4_000,
               "mine": 7_000, "research_center": 9_000, "car_dealership": 6_000}[fac["kind"]]
        owner = "company:" + fac["owner"]
        paid = min(fee, w["wallets"][owner])
        _money(w, owner, "treasury:" + fac["city"], paid, "monthly.rent", fac["id"])
    for fac in w["facilities"].values():
        if fac["kind"] == "factory":
            continue  # Factories pay only for actual production batches.
        salary = fac.get("workers", STAFF_BASE[fac["kind"]]) * fac.get("wage_minor", WAGE_MINOR)
        payer = "company:" + fac["owner"]
        paid = min(salary, w["wallets"][payer])
        _money(w, payer, "residents:" + fac["city"], paid, "wages", fac["id"])
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
        if w["tick"] % TICKS_PER_DAY == 0:
            _npc_reprice(w)
        _retail(w)
        if w["tick"] % TICKS_PER_MONTH == 0:
            _close_month(w)
        w["revision"] += 1


def due_ticks(w: dict, server_now_unix: int) -> int:
    if type(server_now_unix) is not int:
        raise EconomyError("server time must be integer unix seconds")
    return max(0, (server_now_unix - w["epoch_unix"]) // TICK_SECONDS - w["tick"])


def apply_command(w: dict, actor: str, command: dict) -> dict:
    if not isinstance(actor, str) or actor == "npc" or "company:" + actor not in w["wallets"]:
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
    land.ensure_world(w)
    kind = command.get("type")
    fac_id = command.get("facility_id")
    if fac_id is not None and not isinstance(fac_id, str):
        raise EconomyError("invalid facility id")
    fac = w["facilities"].get(fac_id)
    if kind in ("facility.set_price", "facility.buy", "shipment.create", "facility.set_staff", "facility.set_production", "facility.set_recipe", "facility.upgrade_equipment"):
        if fac is None or fac["owner"] != actor:
            raise EconomyError("facility not owned")
    if kind == "facility.set_staff":
        workers, wage = command.get("workers"), command.get("wage_minor")
        if (type(workers) is not int or type(wage) is not int or
                not 0 <= workers <= STAFF_CAP[fac["kind"]] or
                not 500 <= wage <= 3000):
            raise EconomyError("invalid staffing")
        fac["workers"] = workers
        fac["wage_minor"] = wage
        result = {"ok": True, "workers": workers, "wage_minor": wage}
    elif kind == "facility.set_production":
        target = command.get("target")
        if fac["kind"] != "factory" or type(target) is not int or not 0 <= target <= MAX_PRODUCTION_BATCH:
            raise EconomyError("invalid production target")
        fac["production_target"] = target
        result = {"ok": True, "target": target}
    elif kind == "facility.set_recipe":
        recipe = command.get("recipe")
        if fac["kind"] != "factory" or type(recipe) is not str or recipe not in RECIPES:
            raise EconomyError("invalid production recipe")
        fac["recipe"] = recipe
        result = {"ok": True, "recipe": recipe}
    elif kind == "facility.upgrade_equipment":
        level = fac.get("equipment_level", 1)
        cost = level * 2_000_000
        if fac["kind"] != "factory" or level >= 3 or w["wallets"]["company:" + actor] < cost:
            raise EconomyError("equipment upgrade unavailable")
        _money(w, "company:" + actor, "suppliers:" + fac["city"], cost,
               "equipment.purchase", fac_id)
        fac["equipment_level"] = level + 1
        result = {"ok": True, "equipment_level": level + 1, "cost_minor": cost}
    elif kind == "facility.set_price":
        good = command.get("good")
        price = command.get("price_minor")
        if (fac["kind"] != "shop" or not isinstance(good, str) or good not in ("bread", "milk", "flour") or
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
    elif kind == "land.buy":
        city, x, y = command.get("city"), command.get("x"), command.get("y")
        if not isinstance(city, str) or city not in CITIES:
            raise EconomyError("unknown city")
        layout = w["land"][city]
        if not land.is_open(layout["chunks"], x, y) or land.code_at(city, x, y) != 0:
            raise EconomyError("parcel is not available land")
        position = land.key(x, y)
        if position in layout["plots"]:
            raise EconomyError("parcel already owned")
        if w["wallets"]["company:" + actor] < land.LAND_PRICE:
            raise EconomyError("insufficient funds")
        _money(w, "company:" + actor, "treasury:" + city, land.LAND_PRICE, "land.purchase", position)
        layout["plots"][position] = {"owner": actor, "building": ""}
        result = {"ok": True, "x": x, "y": y}
    elif kind == "facility.build":
        city, facility_type = command.get("city"), command.get("kind")
        if not isinstance(city, str) or not isinstance(facility_type, str) or city not in CITIES or facility_type not in BUILD_COSTS:
            raise EconomyError("invalid construction")
        if sum(1 for f in w["facilities"].values()
               if f["owner"] == actor and f["city"] == city) >= 512:
            raise EconomyError("city property cap reached")
        layout = w["land"][city]
        explicit = "x" in command or "y" in command
        if explicit:
            x, y = command.get("x"), command.get("y")
            if not land.is_open(layout["chunks"], x, y):
                raise EconomyError("parcel is outside open territory")
            position = land.key(x, y)
            plot = layout["plots"].get(position)
            if plot is None or plot["owner"] != actor or plot["building"]:
                raise EconomyError("empty owned parcel required")
        else:
            # Compatibility with pre-spatial 0.7 clients: select and buy a real parcel.
            location = land.free_plot(city, layout["chunks"], layout["plots"], facility_type == "mine")
            if location is None:
                raise EconomyError("no free parcel")
            x, y = location
            position = land.key(x, y)
        if facility_type == "mine" and not land.has_ore(city, x, y):
            raise EconomyError("mine requires ore deposit")
        price = BUILD_COSTS[facility_type]
        total = price + (0 if explicit else land.LAND_PRICE)
        if w["wallets"]["company:" + actor] < total:
            raise EconomyError("insufficient funds")
        ident = actor + "-built-" + str(w["next_facility"])
        if not explicit:
            _money(w, "company:" + actor, "treasury:" + city, land.LAND_PRICE, "land.purchase", position)
            layout["plots"][position] = {"owner": actor, "building": ""}
        w["next_facility"] += 1
        _money(w, "company:" + actor, "suppliers:" + city, price, "construction", ident)
        facility = _facility(actor, city, facility_type, ident)
        facility["plot"] = {"x": x, "y": y}
        w["facilities"][ident] = facility
        layout["plots"][position]["building"] = ident
        expanded = land.grow(city, layout["chunks"], layout["plots"], x, y)
        result = {"ok": True, "facility_id": ident, "x": x, "y": y, "expanded": expanded}
    else:
        raise EconomyError("unsupported command")
    w["revision"] += 1
    result["revision"] = w["revision"]
    w["receipts"][key] = {"fingerprint": fingerprint, "result": copy.deepcopy(result)}
    return result


def snapshot(w: dict, actor: str) -> dict:
    if (not isinstance(actor, str) or actor == "npc" or
            "company:" + actor not in w["wallets"]):
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
    public_land = copy.deepcopy(w.get("land", {}))
    for layout in public_land.values():
        for plot in layout["plots"].values():
            plot["kind"] = w["facilities"].get(plot.get("building", ""), {}).get("kind", "")
    return {
        "schema": w["schema"], "tick": w["tick"], "revision": w["revision"],
        "game_day": w["tick"] // TICKS_PER_DAY,
        "game_month": w["tick"] // TICKS_PER_MONTH,
        "ticks_per_game_day": TICKS_PER_DAY,
        "server_epoch_unix": w["epoch_unix"],
        "company": actor, "cash_minor": w["wallets"]["company:" + actor],
        "facilities": own,
        "land": public_land,
        "shipments": copy.deepcopy([s for s in w["shipments"] if s["owner"] == actor]),
        "market": market, "stats": copy.deepcopy(w["stats"]),
        "company_metrics": copy.deepcopy(w["company_metrics"][actor]),
        "finance_history": [
            copy.deepcopy(entry) for entry in w.get("finance_history", [])[-100:]
            if entry["debit"] == "company:" + actor or entry["credit"] == "company:" + actor
        ],
        "staff_limits": STAFF_CAP.copy(),
        "recipes": {name: {"input": data[0], "input_qty": data[1],
                            "output": data[2], "output_qty": data[3]}
                    for name, data in RECIPES.items()},
    }