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

GOODS = ("grain", "bread", "milk", "flour", "ore", "steel", "parts", "car")
RECIPES = {
    "bread": ("grain", 1, "bread", 2),
    "flour": ("grain", 1, "flour", 2),
    "bakery": ("flour", 1, "bread", 3),
    "steel": ("ore", 2, "steel", 1),
    "parts": ("steel", 1, "parts", 2),
    "car": ("parts", 4, "car", 1),
}
RECIPE_MIN_EQUIPMENT = {"steel": 1, "parts": 2, "car": 3}
INDUSTRIAL_GOODS = ("ore", "steel", "parts", "car")
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
BASE_PRICES = {"grain": 5000, "bread": 15500, "milk": 18000, "flour": 10000, "ore": 12000, "steel": 38000, "parts": 29000, "car": 250000}
SOURCE_PRICES = {"grain": 5000, "milk": 11000}
BUILD_COSTS = {"factory": 80000000, "shop": 35000000, "warehouse": 28000000, "mine": 70000000, "research_center": 60000000, "car_dealership": 50000000}
CAPACITY = {"factory": 120, "shop": 90, "warehouse": 300, "mine": 120, "research_center": 80, "car_dealership": 90}
DEMAND = {
    "ufa": {"bread": 6, "milk": 3, "flour": 2, "car": 1},
    "sterlitamak": {"bread": 4, "milk": 2, "flour": 2, "car": 1},
    "tuymazy": {"bread": 3, "milk": 2, "flour": 1, "car": 1},
    "beloretsk": {"bread": 3, "milk": 1, "flour": 1, "car": 1},
}
SALES_TAX_BPS = 500
STAFF_CAP = {"factory": 20, "shop": 12, "warehouse": 8, "mine": 16, "research_center": 12, "car_dealership": 10}
STAFF_BASE = {"factory": 4, "shop": 3, "warehouse": 2, "mine": 4, "research_center": 3, "car_dealership": 3}
WAGE_MINOR = 750
MAX_PRODUCTION_BATCH = 4

TRANSPORT_CAPACITY = 50
NPC_OWNERS = ("npc", "npc_auto")
NPC_MAX_BUILDINGS = 6
NPC_DECISION_INTERVAL = TICKS_PER_DAY
NPC_BUILD_INTERVAL = TICKS_PER_MONTH
NPC_STRATEGIES = {"npc": "value", "npc_auto": "growth"}
MARKET_WINDOW_DAYS = 30
AUTOMATION_MAX_BUDGET = 5_000_000
AUTOMATION_MAX_EVENTS = 100
# Server-authoritative milestones: rewards are integer kopecks, once per actor.
MISSION_REWARDS_MINOR = {"first_land": 100_000, "first_build": 250_000, "first_delivery": 150_000}



class EconomyError(ValueError):
    """Invalid economic command, not an infrastructure failure."""


def _facility(owner: str, city: str, kind: str, ident: str,
              stock: dict[str, int] | None = None) -> dict:
    return {
        "id": ident, "owner": owner, "city": city, "kind": kind,
        "stock": {good: int((stock or {}).get(good, 0)) for good in GOODS},
        "basis": {good: 0 for good in GOODS}, "capacity": CAPACITY[kind],
        "prices": {good: BASE_PRICES[good] for good in ("bread", "milk", "flour", "car")},
        "reputation": 70 if owner != "npc" else 60,
        "customer_distance_km": 3 if owner != "npc" else 7,
        "auto_buy_limit": 2 if kind == "factory" else 0,
        "workers": STAFF_BASE[kind], "wage_minor": WAGE_MINOR,
        "production_target": 1, "recipe": "bread", "equipment_level": 1,
        "production_last_tick": 0,
        "production_last_units": 0,
        "freight_priority": "standard", "storage_level": 0,
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
        "district_population": {}, "district_investments": {}, "mission_claims": {}, "receipts": {}, "audit": audit, "pending_ledger": [], "finance_history": [],
        "contracts": {}, "next_contract": 1,
        "stats": {"sales": 0, "units_sold": 0, "delivered": 0,
                  "produced": 0, "blocked": 0, "days_closed": 0},
        "last_sales": {}, "month_reports": [],
        "market_daily": [], "market_today": {}, "market_totals": {},
        "automation_rules": {}, "automation_events": [], "automation_spend": {},
        "company_metrics": {owner: {"revenue": 0, "cogs": 0,
                                     "operating_expense": 0, "freight": 0,
                                     "capital_expenditure": 0, "profit": 0}
                            for owner in ("player", "rival", "npc")},
    }
    for good in GOODS:
        audit[good]["initial"] = goods_total(w)[good]
    w["initial_money"] = money_total(w)
    land.ensure_world(w)
    w["npc_decisions"] = []
    w["npc_next_action"] = NPC_DECISION_INTERVAL
    return w


def migrate_industry(w: dict) -> None:
    """In-memory additive migration of 0.7.7 saves; persisted on next atomic commit."""
    w.setdefault("mission_claims", {})
    w.setdefault("district_population", {})
    w.setdefault("district_investments", {})
    if "flour" not in w["audit"]:
        w["audit"]["flour"] = {"initial": 0, "sourced": 0,
                                 "converted_in": 0, "converted_out": 0, "consumed": 0}
    for fac in w["facilities"].values():
        fac["stock"].setdefault("flour", 0)
        fac["basis"].setdefault("flour", 0)
        fac["prices"].setdefault("flour", BASE_PRICES["flour"])
        fac.setdefault("recipe", "bread")
        fac.setdefault("equipment_level", 1)
        fac.setdefault("storage_level", 0)
    for city in CITIES:
        w["suppliers"][city].setdefault("flour", 0)
        for good in INDUSTRIAL_GOODS:
            w["suppliers"][city].setdefault(good, 0)
    for good in INDUSTRIAL_GOODS:
        if good not in w["audit"]:
            w["audit"][good] = {"initial": 0, "sourced": 0,
                                  "converted_in": 0, "converted_out": 0, "consumed": 0}
    for fac in w["facilities"].values():
        for good in INDUSTRIAL_GOODS:
            fac["stock"].setdefault(good, 0)
            fac["basis"].setdefault(good, 0)
        fac["prices"].setdefault("car", BASE_PRICES["car"])
    w.setdefault("contracts", {})
    w.setdefault("next_contract", 1)
    w.setdefault("npc_decisions", [])
    w.setdefault("npc_next_action", NPC_DECISION_INTERVAL)
    w.setdefault("market_daily", [])
    w.setdefault("market_today", {})
    w.setdefault("market_totals", {})
    w.setdefault("automation_rules", {})
    w.setdefault("automation_events", [])
    w.setdefault("automation_spend", {})


def register_company(w: dict, actor: str, city: str = "ufa") -> None:
    """Admin-only onboarding. A finite central development pool funds starters."""
    if (not isinstance(actor, str) or
            re.fullmatch(r"[a-z][a-z0-9_-]{2,24}", actor) is None or
            actor in NPC_OWNERS or city not in CITIES or
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
    for contract in w.get("contracts", {}).values():
        if (contract["seller"] == contract["buyer"] and contract["buyer"] or
                contract["good"] not in GOODS or type(contract["quantity"]) is not int or
                contract["quantity"] < 1 or type(contract["price_minor"]) is not int or
                contract["price_minor"] < 1 or
                contract["status"] not in ("offered", "in_transit", "delivered")):
            return False
        if contract["status"] == "in_transit" and w["wallets"].get("escrow:" + contract["id"], -1) != contract["quantity"] * contract["price_minor"]:
            return False
    stock = goods_total(w)
    for good in GOODS:
        a = w["audit"][good]
        expected = (a["initial"] + a["sourced"] + a["converted_out"]
                    - a["converted_in"] - a["consumed"])
        if stock[good] != expected:
            return False
    if (type(w.get("market_daily", [])) is not list or
            len(w.get("market_daily", [])) > MARKET_WINDOW_DAYS or
            type(w.get("market_today", {})) is not dict or
            type(w.get("market_totals", {})) is not dict):
        return False
    for record in w.get("market_daily", []):
        if (type(record) is not dict or
                any(type(v) is not int or v < 0 for v in record.values())):
            return False
    if any(type(v) is not int or v < 0 for v in w.get("market_today", {}).values()):
        return False
    if (type(w.get("npc_next_action", NPC_DECISION_INTERVAL)) is not int or
            w.get("npc_next_action", NPC_DECISION_INTERVAL) < 1 or
            len(w.get("npc_decisions", [])) > 80):
        return False
    for fac in w["facilities"].values():
        staff = fac.get("workers", STAFF_BASE[fac["kind"]])
        wage = fac.get("wage_minor", WAGE_MINOR)
        target = fac.get("production_target", 1)
        if (type(fac.get("storage_level", 0)) is not int or
                not 0 <= fac.get("storage_level", 0) <= 5 or
                (fac["kind"] == "warehouse" and
                 fac["capacity"] != CAPACITY["warehouse"] + fac.get("storage_level", 0) * 100) or
                fac.get("recipe", "bread") not in RECIPES or
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
        elif kind not in ("inventory.purchase", "contract.escrow") :
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
        if "contract_id" in cargo:
            contract = w["contracts"][cargo["contract_id"]]
            amount_minor = contract["quantity"] * contract["price_minor"]
            _money(w, "escrow:" + contract["id"], "company:" + contract["seller"],
                   amount_minor, "contract.settlement", contract["id"])
            # Payment is income, goods basis is recognized at settlement.
            metrics = w["company_metrics"][contract["seller"]]
            metrics["revenue"] += amount_minor
            metrics["cogs"] += cargo["seller_basis"]
            metrics["profit"] += amount_minor - cargo["seller_basis"]
            contract["status"] = "delivered"
        w["stats"]["delivered"] += cargo["amount"]
    w["shipments"] = pending


def _produce(w: dict) -> None:
    for fac_id in sorted(w["facilities"]):
        fac = w["facilities"][fac_id]
        if fac["kind"] == "mine":
            # Ore deposits are tied to a built mine, not free global supplier stock.
            if fac.get("plot") and fac["stock"]["ore"] < fac["capacity"]:
                amount = min(2, fac["capacity"] - sum(fac["stock"].values()))
                wage_cost = fac.get("wage_minor", WAGE_MINOR) * 2
                payer = "company:" + fac["owner"]
                if amount > 0 and fac.get("workers", 0) >= 2 and w["wallets"][payer] >= wage_cost:
                    _money(w, payer, "residents:" + fac["city"], wage_cost, "wages", fac_id)
                    _put(fac, "ore", amount, wage_cost)
                    w["audit"]["ore"]["sourced"] += amount
            continue
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
        if equipment < RECIPE_MIN_EQUIPMENT.get(recipe, 1):
            fac["production_last_units"] = 0
            continue
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


def _district_retail_score(fac: dict, competitors: list[dict]) -> int:
    """Deterministic integer spatial preference, without changing total city demand.

    Shop proximity to the city center and competing shops on the same 16x16
    parcel chunk affect the order in which residents choose available shops.
    """
    plot = fac.get("plot") or {"x": 16, "y": 16}
    x, y = int(plot["x"]), int(plot["y"])
    center_distance = x + y
    same_district = sum(1 for other in competitors
                        if other["id"] != fac["id"]
                        and int((other.get("plot") or {}).get("x", 16)) // 16 == x // 16
                        and int((other.get("plot") or {}).get("y", 16)) // 16 == y // 16)
    return center_distance * 9 + same_district * 120


def _district_population(city: str, district: tuple[int, int], w: dict | None = None) -> int:
    """Persistent synthetic population; old saves use a deterministic baseline."""
    x, y = district
    baseline = max(10, 1000 - 80 * (abs(x) + abs(y)))
    if w is None:
        return baseline
    return int(w.get("district_population", {}).get(city, {}).get(f"{x}:{y}", baseline))


def _district_infrastructure(w: dict, city: str, district: tuple[int, int]) -> dict:
    """Existing map roads, residential tiles and businesses form attractiveness."""
    cx, cy = district
    roads = housing = 0
    # Sample 16x16 map chunk, no procedural map mutation.
    for y in range(cy * 16, cy * 16 + 16):
        for x in range(cx * 16, cx * 16 + 16):
            tile = land.code_at(city, x, y)
            roads += tile == 1
            housing += tile == 2
    local = [f for f in w["facilities"].values()
             if f["city"] == city and isinstance(f.get("plot"), dict)
             and int(f["plot"]["x"]) // 16 == cx and int(f["plot"]["y"]) // 16 == cy]
    services = sum(f["kind"] in ("shop", "research_center") for f in local)
    industry = sum(f["kind"] in ("factory", "mine") for f in local)
    jobs = sum(int(f.get("workers", 0)) for f in local)
    upgrades = int(w.get("district_investments", {}).get(city, {}).get(f"{cx}:{cy}", 0))
    score = max(0, min(100, 30 + upgrades * 5 + min(25, roads // 3)
                       + min(20, housing * 2) + services * 7
                       + min(20, jobs // 2) - industry * 8))
    return {"roads": roads, "housing_tiles": housing, "investment_level": upgrades, "services": services,
            "industry": industry, "jobs": jobs, "attractiveness": score}


def _district_urban_metrics(w: dict, city: str, district: tuple[int, int],
                            infrastructure: dict | None = None) -> dict:
    """Read-only integer planning indicators; no new taxes or land transactions."""
    infra = infrastructure if infrastructure is not None else _district_infrastructure(w, city, district)
    residents = _district_population(city, district, w)
    roads = infra["roads"]
    workers = infra["jobs"]
    shops = infra["services"]
    industry = infra["industry"]
    # 0..100: synthetic accessibility and congestion proxies, not live routing.
    access = max(0, min(100, 25 + roads // 2 + infra["investment_level"] * 6
                        - (abs(district[0]) + abs(district[1])) * 5))
    congestion = max(0, min(100, (residents // 40 + workers * 2 + shops * 5 +
                                  industry * 8) * 10 // max(10, roads + 10)))
    land_value_minor = land.LAND_PRICE * (
        100 + infra["attractiveness"] // 2 + access // 3
        - congestion // 5) // 100
    if industry >= shops + 2:
        specialization = "industrial"
    elif shops >= industry + 2:
        specialization = "commercial"
    elif infra["housing_tiles"] >= 15:
        specialization = "residential"
    else:
        specialization = "mixed"
    return {"transport_access": access, "traffic_congestion": congestion,
            "indicative_land_value_minor": max(land.LAND_PRICE // 2, land_value_minor),
            "specialization": specialization}


def _update_district_population(w: dict) -> None:
    """Monthly bounded migration based on nearby jobs and local infrastructure."""
    populations = w.setdefault("district_population", {})
    for city in CITIES:
        shops = [f for f in w["facilities"].values() if f["city"] == city and f["kind"] == "shop"]
        weights = _district_sales_weights(city, shops, w)
        city_pop = populations.setdefault(city, {})
        for (x, y), previous in sorted(weights.items()):
            infra = _district_infrastructure(w, city, (x, y))
            # Infrastructure changes migration, never instant population.
            delta = max(-8, min(8, (infra["attractiveness"] - 50) // 8))
            city_pop[f"{x}:{y}"] = max(10, min(5000, previous + delta))


def _district_sales_weights(city: str, shops: list[dict], w: dict | None = None) -> dict[tuple[int, int], int]:
    """Synthetic population weights; include neighboring residential districts."""
    districts = {(0, 0), (1, 0), (0, 1), (1, 1)}
    districts.update((int(f["plot"]["x"]) // 16, int(f["plot"]["y"]) // 16)
                     for f in shops if isinstance(f.get("plot"), dict))
    return {d: _district_population(city, d, w) for d in sorted(districts)}


def _allocate_district_demand(total: int, weights: dict[tuple[int, int], int]) -> dict[tuple[int, int], int]:
    """Largest-remainder allocation, exact integer sum and stable tie-breaking."""
    denominator = sum(weights.values())
    if denominator <= 0:
        return {}
    quotas = {key: divmod(total * weight, denominator) for key, weight in weights.items()}
    allocations = {key: value[0] for key, value in quotas.items()}
    remainder = total - sum(allocations.values())
    ranked = sorted(quotas, key=lambda key: (-quotas[key][1], key))
    for key in ranked[:remainder]:
        allocations[key] += 1
    return allocations


def _district_shop_rank(fac: dict, district: tuple[int, int], good: str, urban: dict | None = None) -> tuple:
    plot = fac.get("plot") or {"x": 0, "y": 0}
    distance = abs(int(plot["x"]) // 16 - district[0]) + abs(int(plot["y"]) // 16 - district[1])
    # Distance affects effective price; a cheaper shop can still win remotely.
    transport_penalty = 0
    if urban is not None:
        # Congestion makes distant shopping less attractive; better access reduces friction.
        transport_penalty = distance * max(0, urban["traffic_congestion"] - urban["transport_access"]) // 10
    effective_price = int(fac["prices"][good]) * (100 + distance * 8 + transport_penalty)
    return (effective_price, int(fac["customer_distance_km"]), -int(fac["reputation"]), fac["id"])


def _retail(w: dict) -> None:
    recent = {}
    urban_cache = {}
    for city in CITIES:
        for good in ("bread", "milk", "flour"):
            shops = [fac for fac in w["facilities"].values()
                     if fac["kind"] == "shop" and fac["city"] == city
                     and fac["stock"][good] > 0]
            if not shops:
                continue
            best_price = min(fac["prices"][good] for fac in shops)
            demand = min(DEMAND[city][good] * 2,
                         DEMAND[city][good] * BASE_PRICES[good] // best_price)
            weights = _district_sales_weights(city, shops, w)
            allocations = _allocate_district_demand(demand, weights)
            affordable = w["wallets"]["residents:" + city]
            for district, district_demand in allocations.items():
                cache_key = (city, district)
                if cache_key not in urban_cache:
                    urban_cache[cache_key] = _district_urban_metrics(w, city, district)
                urban = urban_cache[cache_key]
                for fac in sorted(shops, key=lambda f: _district_shop_rank(f, district, good, urban)):
                    price = fac["prices"][good]
                    qty = min(district_demand, fac["stock"][good], affordable // price)
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
                    market_key = city + ":" + good + ":" + fac["owner"]
                    w["market_today"][market_key] = w["market_today"].get(market_key, 0) + qty
                    sale_key = fac["id"] + ":" + good
                    current = recent.setdefault(sale_key, {"units": 0, "revenue": 0, "cost_basis": 0})
                    current["units"] += qty
                    current["revenue"] += receipt
                    current["cost_basis"] += cost
                    affordable -= receipt
                    district_demand -= qty
                    if district_demand <= 0:
                        break
    w["last_sales"] = recent

def _close_month(w: dict) -> None:
    _update_district_population(w)
    # One rent charge per facility, once every 360 production ticks.
    for fac in w["facilities"].values():
        fee = {"factory": 12_000, "shop": 8_000, "warehouse": 4_000,
               "mine": 7_000, "research_center": 9_000, "car_dealership": 6_000}[fac["kind"]]
        owner = "company:" + fac["owner"]
        paid = min(fee, w["wallets"][owner])
        _money(w, owner, "treasury:" + fac["city"], paid, "monthly.rent", fac["id"])
    for fac in w["facilities"].values():
        if fac["kind"] in ("factory", "mine"):
            continue  # Production and extraction pay per batch.
        salary = fac.get("workers", STAFF_BASE[fac["kind"]]) * fac.get("wage_minor", WAGE_MINOR)
        payer = "company:" + fac["owner"]
        paid = min(salary, w["wallets"][payer])
        _money(w, payer, "residents:" + fac["city"], paid, "wages", fac["id"])
    w["stats"]["days_closed"] += 30
    w["month_reports"].append({"month": w["tick"] // TICKS_PER_MONTH,
                               "sales_minor": w["stats"]["sales"]})
    if len(w["month_reports"]) > 24:
        w["month_reports"] = w["month_reports"][-24:]


def _automation_event(w: dict, owner: str, facility_id: str, action: str,
                      detail: str) -> None:
    history = w.setdefault("automation_events", [])
    history.append({"tick": w["tick"], "owner": owner, "facility_id": facility_id,
                    "action": action, "detail": detail})
    del history[:-AUTOMATION_MAX_EVENTS]


def _automation_tick(w: dict) -> None:
    """Bounded, opt-in, deterministic server-side rules, evaluated once daily."""
    if w["tick"] % TICKS_PER_DAY:
        return
    day = w["tick"] // TICKS_PER_DAY
    spend = w.setdefault("automation_spend", {})
    spend.clear()
    for facility_id, rule in sorted(w.get("automation_rules", {}).items()):
        fac = w["facilities"].get(facility_id)
        if not fac or not rule.get("enabled") or fac["owner"] in NPC_OWNERS:
            continue
        owner = fac["owner"]
        cap = rule["daily_budget_minor"]
        spent = spend.get(facility_id, 0)
        if fac["kind"] == "factory":
            if rule["production"]:
                fac["production_target"] = rule["production_target"]
                _automation_event(w, owner, facility_id, "production",
                                  str(rule["production_target"]))
            if rule["buy_inputs"]:
                recipe = RECIPES[fac.get("recipe", "bread")]
                raw, per_batch = recipe[0], recipe[1]
                if raw in SOURCE_PRICES:
                    target = rule["stock_target"]
                    shortage = max(0, target - fac["stock"][raw])
                    remaining = max(0, cap - spent)
                    qty = min(shortage, rule["max_purchase_units"],
                              remaining // SOURCE_PRICES[raw])
                    if qty:
                        amount = _buy(w, fac, raw, qty)
                        if amount:
                            cost = amount * SOURCE_PRICES[raw]
                            spend[facility_id] = spent + cost
                            _automation_event(w, owner, facility_id, "buy",
                                              raw + ":" + str(amount) + ":" + str(cost))
        elif fac["kind"] == "shop":
            if rule["restock"]:
                for good in ("bread", "flour"):
                    shortage = max(0, rule["stock_target"] - fac["stock"][good])
                    for source in sorted(w["facilities"].values(), key=lambda x: x["id"]):
                        if not shortage:
                            break
                        if (source["owner"] != owner or source["kind"] != "factory"
                                or source["city"] != fac["city"]):
                            continue
                        free = fac["capacity"] - sum(fac["stock"].values()) - _inbound(w, fac["id"])
                        qty = min(shortage, rule["max_purchase_units"], free, source["stock"][good])
                        if qty > 0:
                            basis = _take(source, good, qty)
                            _put(fac, good, qty, basis)
                            shortage -= qty
                            _automation_event(w, owner, facility_id, "restock",
                                              good + ":" + str(qty) + ":" + source["id"])
            if rule["pricing"]:
                for good in ("bread", "milk", "flour"):
                    rivals = sorted(other["prices"][good] for other in w["facilities"].values()
                                    if other["city"] == fac["city"] and other["kind"] == "shop"
                                    and other["owner"] != owner and other["stock"][good] > 0)
                    if not rivals:
                        continue
                    target = rivals[0] - rule["undercut_minor"]
                    floor = BASE_PRICES[good] * 7 // 10
                    ceiling = BASE_PRICES[good] * 3 // 2
                    target = max(floor, min(ceiling, target))
                    old = fac["prices"][good]
                    max_step = max(1, old // 100)
                    price = old + max(-max_step, min(max_step, target - old))
                    if price != old:
                        fac["prices"][good] = price
                        _automation_event(w, owner, facility_id, "price",
                                          good + ":" + str(price))


def advance(w: dict, ticks: int = 1) -> None:
    if type(ticks) is not int or ticks < 0 or ticks > 360:
        raise EconomyError("invalid tick count")
    for _ in range(ticks):
        w["tick"] += 1
        _replenish_suppliers(w)
        _deliver(w)
        _automation_tick(w)
        _produce(w)
        _local_restock(w)
        if w["tick"] >= w.get("npc_next_action", NPC_DECISION_INTERVAL):
            _npc_decide(w)
            w["npc_next_action"] = w["tick"] + NPC_DECISION_INTERVAL
        _retail(w)
        if w["tick"] % TICKS_PER_DAY == 0:
            _market_close_day(w)
        if w["tick"] % TICKS_PER_MONTH == 0:
            _close_month(w)
        w["revision"] += 1


def due_ticks(w: dict, server_now_unix: int) -> int:
    if type(server_now_unix) is not int:
        raise EconomyError("server time must be integer unix seconds")
    return max(0, (server_now_unix - w["epoch_unix"]) // TICK_SECONDS - w["tick"])


def _accept_contract(w: dict, actor: str, ident: str, destination_id: str) -> dict:
    contract = w["contracts"].get(ident) if type(ident) is str else None
    dest = w["facilities"].get(destination_id) if type(destination_id) is str else None
    if (contract is None or contract["status"] != "offered" or
            contract["seller"] == actor or dest is None or dest["owner"] != actor):
        raise EconomyError("invalid contract acceptance")
    source = w["facilities"].get(contract["from"])
    if source is None or source["owner"] != contract["seller"]:
        raise EconomyError("seller facility unavailable")
    quantity, good = contract["quantity"], contract["good"]
    total = quantity * contract["price_minor"]
    fee = shipment_fee(route_km(source["city"], dest["city"]), quantity)
    if (source["stock"][good] < quantity or
            sum(dest["stock"].values()) + _inbound(w, dest["id"]) + quantity > dest["capacity"] or
            w["wallets"]["company:" + actor] < total + fee):
        raise EconomyError("insufficient contract resources")
    escrow = "escrow:" + ident
    w["wallets"][escrow] = 0
    _money(w, "company:" + actor, escrow, total, "contract.escrow", ident)
    _money(w, "company:" + actor, "suppliers:" + source["city"], fee, "freight", ident)
    basis = _take(source, good, quantity)
    eta = w["tick"] + eta_ticks(route_km(source["city"], dest["city"]))
    w["shipments"].append({"id": "s" + str(w["next_shipment"]), "owner": actor,
        "from": source["id"], "to": dest["id"], "good": good,
        "amount": quantity, "basis": total, "seller_basis": basis, "eta_tick": eta,
        "contract_id": ident, "status": "in_transit"})
    w["next_shipment"] += 1
    contract.update({"buyer": actor, "to": dest["id"], "status": "in_transit", "eta_tick": eta})
    return {"ok": True, "contract_id": ident, "eta_tick": eta, "fee_minor": fee}


def _market_close_day(w: dict) -> None:
    daily = w.setdefault("market_daily", [])
    daily.append(w.get("market_today", {}))
    del daily[:-MARKET_WINDOW_DAYS]
    w["market_today"] = {}
    totals = {}
    for day in daily:
        for key, units in day.items():
            totals[key] = totals.get(key, 0) + units
    w["market_totals"] = totals


def market_report(w: dict) -> dict:
    """Public actual units sold in rolling 30 days, never fabricated demand."""
    totals = w.get("market_totals", {})
    report = {}
    for city in CITIES:
        report[city] = {}
        for good in ("bread", "milk", "flour"):
            by_owner = {}
            for key, units in totals.items():
                if key.startswith(city + ":" + good + ":"):
                    owner = key[len(city + ":" + good + ":"):]
                    by_owner[owner] = by_owner.get(owner, 0) + units
            total = sum(by_owner.values())
            report[city][good] = {
                "demand_per_tick": DEMAND[city][good],
                "units_sold_30d": total,
                "share_bps": {owner: units * 10000 // total for owner, units
                              in sorted(by_owner.items())} if total else {},
                "active_shops": sum(1 for f in w["facilities"].values()
                                    if f["city"] == city and f["kind"] == "shop"),
            }
    return report


def economic_intelligence(w: dict, actor: str) -> dict:
    """Read-only, integer-only decision support; forecasts are estimates."""
    if not isinstance(actor, str) or actor in NPC_OWNERS or "company:" + actor not in w["wallets"]:
        raise EconomyError("unknown actor")
    days = w.get("market_daily", [])[-7:]
    observed_days = len(days)
    forecasts = {}
    for city in CITIES:
        forecasts[city] = {}
        for good in ("bread", "milk", "flour"):
            history = [sum(units for key, units in day.items()
                           if key.startswith(city + ":" + good + ":"))
                       for day in days]
            # Smoothed recent average. Zero observations is explicitly low confidence.
            forecast = (sum(history) + observed_days // 2) // observed_days if observed_days else 0
            theoretical = DEMAND[city][good] * TICKS_PER_DAY
            forecasts[city][good] = {
                "forecast_daily_units": forecast,
                "observed_days": observed_days,
                "theoretical_daily_demand": theoretical,
                "unserved_daily_units_estimate": max(0, theoretical - forecast),
                "confidence": "limited" if observed_days < 7 else "observed",
            }
    metrics = w["company_metrics"][actor]
    revenue = metrics["revenue"]
    profit = metrics["profit"]
    profitability = {
        "revenue_minor": revenue, "profit_minor": profit,
        "cogs_minor": metrics["cogs"],
        "operating_expense_minor": metrics["operating_expense"],
        "freight_minor": metrics["freight"],
        "margin_bps": profit * 10000 // revenue if revenue else None,
        "basis": "cumulative",
    }
    plans = []
    recommendations = []
    owned = sorted((f for f in w["facilities"].values() if f["owner"] == actor),
                   key=lambda f: f["id"])
    for fac in owned:
        city = fac["city"]
        free = max(0, fac["capacity"] - sum(fac["stock"].values()) - _inbound(w, fac["id"]))
        if fac["kind"] == "factory":
            recipe = RECIPES[fac.get("recipe", "bread")]
            raw, raw_per_batch = recipe[0], recipe[1]
            required = min(MAX_PRODUCTION_BATCH, fac.get("production_target", 1)) * raw_per_batch * TICKS_PER_DAY
            on_hand = fac["stock"][raw]
            shortage = max(0, required - on_hand)
            qty = 0
            if raw in SOURCE_PRICES:
                qty = min(shortage, free, w["suppliers"][city][raw],
                          w["wallets"]["company:" + actor] // SOURCE_PRICES[raw], 100)
            plans.append({"facility_id": fac["id"], "city": city, "good": raw,
                          "stock_units": on_hand, "target_units": required,
                          "shortage_units": shortage, "recommended_buy_units": qty,
                          "estimated_cost_minor": qty * SOURCE_PRICES.get(raw, 0),
                          "purchase_available": raw in SOURCE_PRICES})
            if shortage:
                recommendations.append({"facility_id": fac["id"], "kind": "input_shortage",
                                        "good": raw, "units": shortage})
        elif fac["kind"] == "shop":
            for good in ("bread", "milk", "flour"):
                expected = forecasts[city][good]["forecast_daily_units"]
                if not observed_days:
                    expected = DEMAND[city][good] * TICKS_PER_DAY
                shortage = max(0, expected - fac["stock"][good])
                if shortage:
                    recommendations.append({"facility_id": fac["id"], "kind": "stockout_risk",
                                            "good": good, "units": shortage})
    if revenue > 0 and profit < 0:
        recommendations.append({"facility_id": "", "kind": "negative_margin",
                                "good": "", "units": 0})
    return {"forecast_horizon_days": 1, "forecast_method": "observed_7d_average",
            "forecasts": forecasts, "profitability": profitability,
            "procurement_plans": plans, "recommendations": recommendations[:30]}


def _npc_event(w: dict, owner: str, action: str, detail: str) -> None:
    events = w.setdefault("npc_decisions", [])
    events.append({"tick": w["tick"], "owner": owner, "action": action, "detail": detail})
    del events[:-80]


def _npc_build(w: dict, owner: str, city: str, kind: str) -> bool:
    owned = [f for f in w["facilities"].values() if f["owner"] == owner]
    if len(owned) >= NPC_MAX_BUILDINGS:
        return False
    layout = w["land"][city]
    position = land.free_plot(city, layout["chunks"], layout["plots"], kind == "mine")
    price = BUILD_COSTS[kind] + land.LAND_PRICE
    if position is None or w["wallets"]["company:" + owner] < price + 20_000_000:
        return False
    x, y = position
    key = land.key(x, y)
    ident = owner + "-autobuilt-" + str(w["next_facility"])
    _money(w, "company:" + owner, "treasury:" + city, land.LAND_PRICE,
           "land.purchase", key)
    _money(w, "company:" + owner, "suppliers:" + city, BUILD_COSTS[kind],
           "construction", ident)
    w["next_facility"] += 1
    layout["plots"][key] = {"owner": owner, "building": ident}
    fac = _facility(owner, city, kind, ident)
    fac["plot"] = {"x": x, "y": y}
    w["facilities"][ident] = fac
    land.grow(city, layout["chunks"], layout["plots"], x, y)
    _npc_event(w, owner, "construction", kind + ":" + city)
    return True


def _npc_decide(w: dict) -> None:
    """Bounded deterministic decisions, authoritative server only, no LLM."""
    if "company:npc_auto" not in w["wallets"]:
        # Finite subsidy from treasury, not money creation.
        w["wallets"]["company:npc_auto"] = 0
        w["company_metrics"]["npc_auto"] = {"revenue": 0, "cogs": 0,
            "operating_expense": 0, "freight": 0, "capital_expenditure": 0,
            "profit": 0}
        _money(w, "treasury:central", "company:npc_auto",
               260_000_000, "company.starter_grant", "npc_auto")
        _npc_event(w, "npc_auto", "entry", "new competitor")
    for owner in NPC_OWNERS:
        own = sorted((f for f in w["facilities"].values() if f["owner"] == owner),
                     key=lambda f: f["id"])
        if not own and owner == "npc_auto":
            _npc_build(w, owner, "tuymazy", "factory")
            _npc_build(w, owner, "tuymazy", "shop")
            own = sorted((f for f in w["facilities"].values() if f["owner"] == owner),
                         key=lambda f: f["id"])
        for fac in own:
            if fac["kind"] == "factory":
                if fac["stock"]["grain"] < 8:
                    amount = _buy(w, fac, "grain", 12)
                    if amount:
                        _npc_event(w, owner, "purchase", str(amount) + " grain")
                fac["production_target"] = min(2, MAX_PRODUCTION_BATCH)
                fac["workers"] = 8
            if fac["kind"] == "shop":
                strategy = NPC_STRATEGIES[owner]
                for good in ("bread", "milk", "flour"):
                    rivals = [f["prices"][good] for f in w["facilities"].values()
                              if f["city"] == fac["city"] and f["kind"] == "shop"
                              and f["owner"] != owner and f["stock"][good] > 0]
                    if not rivals:
                        continue
                    # Value NPC undercuts; growth NPC targets the median competitor.
                    target = (min(rivals) - 100 if strategy == "value"
                              else sorted(rivals)[len(rivals) // 2])
                    floor = BASE_PRICES[good] * 7 // 10
                    ceiling = BASE_PRICES[good] * 3 // 2
                    old = fac["prices"][good]
                    step = max(1, old // 100)
                    new_price = max(floor, min(ceiling,
                        old + max(-step, min(step, target - old))))
                    if new_price != old:
                        fac["prices"][good] = new_price
                        _npc_event(w, owner, "reprice", fac["city"] + ":" + good)
        # NPC may buy only competitively priced real player offers.
        dest = next((f for f in own if f["kind"] in ("factory", "shop", "warehouse")), None)
        if dest:
            for contract in sorted(w["contracts"].values(), key=lambda c: c["id"]):
                if (contract["status"] != "offered" or
                        contract["seller"] in NPC_OWNERS or
                        contract["good"] not in ("grain", "flour", "bread") or
                        contract["price_minor"] > BASE_PRICES[contract["good"]]):
                    continue
                try:
                    _accept_contract(w, owner, contract["id"], dest["id"])
                except EconomyError:
                    continue
                _npc_event(w, owner, "contract.buy", contract["id"])
                break
        # NPC offers small real stock lots; bounded open offers.
        open_offers = [c for c in w["contracts"].values()
                       if c["seller"] == owner and c["status"] == "offered"]
        if len(open_offers) < 2:
            source = next((f for f in own if f["stock"]["bread"] >= 4), None)
            if source:
                ident = "c" + str(w["next_contract"])
                w["next_contract"] += 1
                w["contracts"][ident] = {"id": ident, "seller": owner, "buyer": "",
                    "from": source["id"], "to": "", "good": "bread",
                    "quantity": 4, "price_minor": BASE_PRICES["bread"],
                    "status": "offered"}
                _npc_event(w, owner, "contract.offer", ident)
        # Invest in the city with the largest observed unmet demand.
        # No construction when the budget, plot or building cap is exhausted.
        if w["tick"] % NPC_BUILD_INTERVAL == 0 and len(own) < NPC_MAX_BUILDINGS:
            strategy = NPC_STRATEGIES[owner]
            report = market_report(w)
            ranked = []
            for city in CITIES:
                own_shops = sum(f["kind"] == "shop" and f["city"] == city for f in own)
                own_factories = sum(f["kind"] == "factory" and f["city"] == city for f in own)
                observed = report[city]["bread"]["units_sold_30d"]
                days = max(1, len(w["market_daily"]))
                potential = DEMAND[city]["bread"] * TICKS_PER_DAY * days
                gap = max(0, potential - observed)
                if strategy == "value":
                    score = gap - own_shops * 40
                else:
                    score = potential + gap - own_shops * 60
                ranked.append((-score, city, own_shops, own_factories))
            for _, city, shops, factories in sorted(ranked):
                kind = "factory" if factories < shops else "shop"
                if _npc_build(w, owner, city, kind):
                    _npc_event(w, owner, "expansion.strategy", strategy + ":" + city)
                    break


def apply_command(w: dict, actor: str, command: dict) -> dict:
    if not isinstance(actor, str) or actor in NPC_OWNERS or "company:" + actor not in w["wallets"]:
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
    if kind in ("automation.configure", "facility.set_price", "facility.buy", "shipment.create", "facility.set_staff", "facility.set_production", "facility.set_recipe", "facility.upgrade_equipment", "contract.offer", "facility.expand_storage"):
        if fac is None or fac["owner"] != actor:
            raise EconomyError("facility not owned")
    if kind == "district.invest":
        city = command.get("city")
        district = command.get("district")
        if (type(city) is not str or city not in CITIES or
                type(district) is not str or not district.count(":") == 1):
            raise EconomyError("invalid district")
        parts = district.split(":")
        if any(not p.isascii() or not p.isdecimal() for p in parts):
            raise EconomyError("invalid district")
        x, y = map(int, parts)
        if (x > 1023 or y > 1023 or f"{x}:{y}" != district or
                district not in w["land"][city]["chunks"]):
            raise EconomyError("district unavailable")
        if not any(f["owner"] == actor and f["city"] == city
                   and isinstance(f.get("plot"), dict)
                   and int(f["plot"]["x"]) // 16 == x
                   and int(f["plot"]["y"]) // 16 == y
                   for f in w["facilities"].values()):
            raise EconomyError("no owned facility in district")
        levels = w.setdefault("district_investments", {}).setdefault(city, {})
        level = int(levels.get(district, 0))
        cost = (level + 1) * 2_000_000
        if level >= 5 or w["wallets"]["company:" + actor] < cost:
            raise EconomyError("investment unavailable")
        _money(w, "company:" + actor, "treasury:" + city, cost,
               "district.infrastructure_investment", district)
        levels[district] = level + 1
        result = {"ok": True, "city": city, "district": district,
                  "level": level + 1, "cost_minor": cost}
    elif kind == "mission.claim":
        mission = command.get("mission")
        if not isinstance(mission, str) or mission not in MISSION_REWARDS_MINOR:
            raise EconomyError("unknown mission")
        claims = w.setdefault("mission_claims", {}).setdefault(actor, [])
        if mission in claims:
            raise EconomyError("mission already claimed")
        owned_plots = [p for layout in w["land"].values() for p in layout["plots"].values()
                       if p["owner"] == actor]
        eligible = {
            "first_land": bool(owned_plots),
            "first_build": any(p.get("building") for p in owned_plots),
            "first_delivery": any(s.get("owner") == actor and s.get("status") == "delivered"
                                  for s in w["shipments"]),
        }
        if not eligible[mission]:
            raise EconomyError("mission not completed")
        reward = MISSION_REWARDS_MINOR[mission]
        _money(w, "treasury:central", "company:" + actor, reward, "mission.reward", mission)
        claims.append(mission)
        result = {"ok": True, "mission": mission, "reward_minor": reward}
    elif kind == "automation.configure":
        fields = ("enabled", "buy_inputs", "restock", "production", "pricing")
        if any(type(command.get(k)) is not bool for k in fields):
            raise EconomyError("invalid automation flags")
        integers = ("daily_budget_minor", "stock_target", "max_purchase_units",
                    "production_target", "undercut_minor")
        if any(type(command.get(k)) is not int for k in integers):
            raise EconomyError("invalid automation limits")
        budget, target, quantity, production, undercut = (command[k] for k in integers)
        if (not 0 <= budget <= AUTOMATION_MAX_BUDGET or
                not 0 <= target <= 300 or not 1 <= quantity <= 100 or
                not 0 <= production <= MAX_PRODUCTION_BATCH or
                not 0 <= undercut <= 1000):
            raise EconomyError("automation limits out of range")
        if ((fac["kind"] != "factory" and (command["buy_inputs"] or command["production"])) or
                (fac["kind"] != "shop" and (command["restock"] or command["pricing"]))):
            raise EconomyError("automation not supported for facility")
        rule = {k: command[k] for k in fields + integers}
        w.setdefault("automation_rules", {})[fac_id] = rule
        _automation_event(w, actor, fac_id, "configure",
                          "enabled" if rule["enabled"] else "disabled")
        result = {"ok": True, "rule": copy.deepcopy(rule)}
    elif kind == "facility.set_staff":
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
    elif kind == "facility.expand_storage":
        level = fac.get("storage_level", 0)
        cost = (level + 1) * 5_000_000
        if fac["kind"] != "warehouse" or level >= 5 or w["wallets"]["company:" + actor] < cost:
            raise EconomyError("warehouse expansion unavailable")
        _money(w, "company:" + actor, "suppliers:" + fac["city"], cost,
               "equipment.purchase", fac_id)
        fac["storage_level"] = level + 1
        fac["capacity"] += 100
        result = {"ok": True, "capacity": fac["capacity"], "cost_minor": cost}
    elif kind == "contract.offer":
        good, quantity, price = command.get("good"), command.get("quantity"), command.get("price_minor")
        if (type(good) is not str or good not in GOODS or
                type(quantity) is not int or not 1 <= quantity <= TRANSPORT_CAPACITY or
                type(price) is not int or not 1 <= price <= 10_000_000 or
                sum(1 for c in w["contracts"].values() if c["seller"] == actor and c["status"] == "offered") >= 20):
            raise EconomyError("invalid contract offer")
        ident = "c" + str(w["next_contract"])
        w["next_contract"] += 1
        w["contracts"][ident] = {"id": ident, "seller": actor, "buyer": "",
            "from": fac_id, "to": "", "good": good, "quantity": quantity,
            "price_minor": price, "status": "offered"}
        result = {"ok": True, "contract_id": ident}
    elif kind == "contract.accept":
        result = _accept_contract(w, actor, command.get("contract_id"),
                                  command.get("destination_id"))
    elif kind == "facility.set_price":
        good = command.get("good")
        price = command.get("price_minor")
        if (fac["kind"] != "shop" or not isinstance(good, str) or good not in ("bread", "milk", "flour", "car") or
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


def mission_status(w: dict, actor: str) -> list[dict]:
    land.ensure_world(w)
    plots = [p for layout in w["land"].values() for p in layout["plots"].values()
             if p["owner"] == actor]
    eligible = {
        "first_land": bool(plots),
        "first_build": any(p.get("building") for p in plots),
        "first_delivery": any(s.get("owner") == actor and s.get("status") == "delivered"
                              for s in w["shipments"]),
    }
    claimed = w.get("mission_claims", {}).get(actor, [])
    return [{"id": name, "completed": eligible[name], "claimed": name in claimed,
             "reward_minor": reward}
            for name, reward in MISSION_REWARDS_MINOR.items()]


def company_operations(w: dict, actor: str) -> dict:
    """Read-only, deterministic operating guidance from authoritative state."""
    own = [f for f in w["facilities"].values() if f["owner"] == actor]
    factories = []
    for f in sorted(own, key=lambda item: item["id"]):
        if f["kind"] != "factory":
            continue
        recipe = RECIPES.get(f.get("recipe", "bread"), RECIPES["bread"])
        input_good, input_units, output_good, output_units = recipe
        workers = int(f.get("workers", 0))
        target = int(f.get("production_target", 0))
        equipment = int(f.get("equipment_level", 1))
        needed_equipment = RECIPE_MIN_EQUIPMENT.get(f.get("recipe", "bread"), 1)
        stock = int(f["stock"].get(input_good, 0))
        batches = min(target, stock // input_units)
        reasons = []
        if workers <= 0:
            reasons.append("no_staff")
        if target <= 0:
            reasons.append("paused")
        if equipment < needed_equipment:
            reasons.append("equipment")
        if target > 0 and stock < target * input_units:
            reasons.append("raw_shortage")
        factories.append({
            "id": f["id"], "city": f["city"], "recipe": f.get("recipe", "bread"),
            "input_good": input_good, "output_good": output_good,
            "planned_batches": target, "input_stock": stock,
            "required_input": target * input_units,
            "potential_output": batches * output_units if not reasons else 0,
            "issues": reasons,
        })
    return {"factory_diagnostics": factories, "facility_count": len(own)}


def competition_opportunities(w: dict, actor: str) -> list[dict]:
    """Compare a company's shop prices with visible competitors, never mutate pricing."""
    offers = []
    for fac in sorted(w["facilities"].values(), key=lambda f: f["id"]):
        if fac["owner"] != actor or fac["kind"] != "shop":
            continue
        for good in ("bread", "milk", "flour", "car"):
            peers = [int(other["prices"][good]) for other in w["facilities"].values()
                     if other["city"] == fac["city"] and other["kind"] == "shop"
                     and other["owner"] != actor and good in other["prices"]
                     and other["stock"].get(good, 0) > 0]
            if not peers:
                continue
            own_price = int(fac["prices"][good])
            competitor_min = min(peers)
            offers.append({"facility_id": fac["id"], "good": good,
                           "own_price_minor": own_price,
                           "lowest_competitor_minor": competitor_min,
                           "difference_minor": own_price - competitor_min,
                           "competitor_count": len(peers)})
    return offers


def district_demand(w: dict, actor: str) -> list[dict]:
    """Spatial market indicators; competition and proximity affect retail allocation."""
    land.ensure_world(w)
    result = []
    for city in CITIES:
        districts = {}
        for fac in w["facilities"].values():
            if fac["city"] != city or "plot" not in fac:
                continue
            x, y = int(fac["plot"]["x"]), int(fac["plot"]["y"])
            key = f"{x // 16}:{y // 16}"
            data = districts.setdefault(key, {"shops": 0, "factories": 0, "own": 0})
            if fac["kind"] == "shop":
                data["shops"] += 1
            if fac["kind"] == "factory":
                data["factories"] += 1
            if fac["owner"] == actor:
                data["own"] += 1
        for district, data in sorted(districts.items()):
            result.append({"city": city, "district": district, **data,
                           "estimated_bread_demand_per_tick": _allocate_district_demand(
                               DEMAND[city]["bread"],
                               _district_sales_weights(city, [f for f in w["facilities"].values()
                                                               if f["city"] == city and f["kind"] == "shop"], w)
                           ).get(tuple(map(int, district.split(":"))), 0),
                           "synthetic_population": _district_population(
                               city, tuple(map(int, district.split(":"))), w),
                           "infrastructure": _district_infrastructure(
                               w, city, tuple(map(int, district.split(":")))),
                           "urban_metrics": _district_urban_metrics(
                               w, city, tuple(map(int, district.split(":")))),
                           "residential_tier": min(5, _district_population(
                               city, tuple(map(int, district.split(":"))), w) // 750),
                           "population_trend": max(-8, min(8, (
                               _district_infrastructure(w, city, tuple(map(int, district.split(":"))))["attractiveness"] - 50) // 8)),
                           "competition_level": "high" if data["shops"] >= 3 else
                                                "medium" if data["shops"] >= 2 else "low"})
    return result


def company_growth(w: dict, actor: str) -> dict:
    """Read-only strategic company milestones, no currency rewards or client authority."""
    owned = [f for f in w["facilities"].values() if f["owner"] == actor]
    kinds = sorted({f["kind"] for f in owned})
    cities = sorted({f["city"] for f in owned})
    completed = sum((len(owned) >= 3, len(kinds) >= 2, len(cities) >= 2))
    return {"facility_count": len(owned), "facility_kinds": kinds,
            "operating_cities": cities, "completed_goals": completed,
            "goals": [
                {"id": "portfolio", "target": 3, "current": min(3, len(owned))},
                {"id": "diversification", "target": 2, "current": min(2, len(kinds))},
                {"id": "regional", "target": 2, "current": min(2, len(cities))},
            ]}


def snapshot(w: dict, actor: str) -> dict:
    if (not isinstance(actor, str) or actor in NPC_OWNERS or
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
        "missions": mission_status(w, actor),
        "facilities": own,
        "land": public_land,
        "shipments": copy.deepcopy([s for s in w["shipments"] if s["owner"] == actor]),
        "market": market, "market_analytics": market_report(w),
        "market_window_days": len(w.get("market_daily", [])),
        "economic_intelligence": economic_intelligence(w, actor),
        "company_operations": company_operations(w, actor),
        "competition_opportunities": competition_opportunities(w, actor),
        "district_demand": district_demand(w, actor),
        "company_growth": company_growth(w, actor),
        "automation_rules": {fid: copy.deepcopy(rule) for fid, rule in
            w.get("automation_rules", {}).items() if fid in own},
        "automation_events": copy.deepcopy([ev for ev in
            w.get("automation_events", []) if ev["owner"] == actor][-30:]),
        "automation_spend": {fid: value for fid, value in
            w.get("automation_spend", {}).items() if fid in own},
        "stats": copy.deepcopy(w["stats"]),
        "npc_competitors": [{"owner": owner, "strategy": NPC_STRATEGIES[owner],
            "facilities": sum(1 for f in w["facilities"].values() if f["owner"] == owner),
            "cash_minor": w["wallets"].get("company:" + owner, 0),
            "latest_action": next((ev["action"] + ": " + ev["detail"]
                for ev in reversed(w.get("npc_decisions", [])) if ev["owner"] == owner), "")}
            for owner in NPC_OWNERS if "company:" + owner in w["wallets"]],
        "npc_activity": copy.deepcopy(w.get("npc_decisions", [])[-12:]),
        "company_metrics": copy.deepcopy(w["company_metrics"][actor]),
        "finance_history": [
            copy.deepcopy(entry) for entry in w.get("finance_history", [])[-100:]
            if entry["debit"] == "company:" + actor or entry["credit"] == "company:" + actor
        ],
        "staff_limits": STAFF_CAP.copy(),
        "contracts": copy.deepcopy([c for c in w.get("contracts", {}).values()
            if c["status"] == "offered" or c["seller"] == actor or c["buyer"] == actor]),
        "recipes": {name: {"input": data[0], "input_qty": data[1],
                            "output": data[2], "output_qty": data[3]}
                    for name, data in RECIPES.items()},
    }