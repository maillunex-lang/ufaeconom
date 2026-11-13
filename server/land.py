"""Deterministic spatial land v1. All coefficients are prototype assumptions."""
from __future__ import annotations
import json
from pathlib import Path

CHUNK = 16
LIMIT = 16384
MAX_CHUNKS = 4096
LAND_PRICE = 12_000_000  # kopecks
CITIES = ("ufa", "sterlitamak", "tuymazy", "beloretsk")
CORES = json.loads((Path(__file__).resolve().parents[1] / "data/city_cores_v1.json").read_text())


def initial_chunks():
    return ["0:0", "1:0", "0:1", "1:1"]


def key(x, y):
    return f"{x}:{y}"


def is_open(chunks, x, y):
    return (type(x) is int and type(y) is int and 0 <= x < LIMIT and 0 <= y < LIMIT
            and key(x // CHUNK, y // CHUNK) in chunks)


def code_at(city, x, y):
    if not (type(x) is int and type(y) is int and 0 <= x < LIMIT and 0 <= y < LIMIT):
        return -1
    if x < 32 and y < 32:
        return CORES[CITIES.index(city)][y * 32 + x]
    if x % 7 == 0 or y % 7 == 0:
        return 1
    h = ((CITIES.index(city) + 1) * 101 + x * 73856093 + y * 19349663) % 2147483647
    return 2 if h % 10 == 0 else 0


def has_ore(city, x, y):
    return code_at(city, x, y) == 0 and (
        (CITIES.index(city) + 1) * 101 + x * 73856093 + y * 19349663) % 2147483647 % 19 == 0


def free_plot(city, chunks, plots, ore_only=False):
    for chunk in chunks:
        cx, cy = map(int, chunk.split(":"))
        for y in range(cy * CHUNK, (cy + 1) * CHUNK):
            for x in range(cx * CHUNK, (cx + 1) * CHUNK):
                if code_at(city, x, y) == 0 and key(x, y) not in plots and (not ore_only or has_ore(city, x, y)):
                    return x, y
    return None


def grow(city, chunks, plots, x, y):
    if len(chunks) >= MAX_CHUNKS:
        return False
    cx, cy = x // CHUNK, y // CHUNK
    free_count = occupied = 0
    for py in range(cy * CHUNK, (cy + 1) * CHUNK):
        for px in range(cx * CHUNK, (cx + 1) * CHUNK):
            if code_at(city, px, py) == 0:
                plot = plots.get(key(px, py))
                if plot is None:
                    free_count += 1
                elif plot.get("building", ""):
                    occupied += 1
    candidates = []
    if x % CHUNK >= CHUNK - 3:
        candidates.append((cx + 1, cy))
    if y % CHUNK >= CHUNK - 3:
        candidates.append((cx, cy + 1))
    if free_count < 16 or occupied * 5 >= (occupied + free_count) * 3:
        candidates.extend([(cx + 1, cy), (cx, cy + 1), (cx - 1, cy), (cx, cy - 1)])
    for nx, ny in candidates:
        if 0 <= nx < LIMIT // CHUNK and 0 <= ny < LIMIT // CHUNK and key(nx, ny) not in chunks:
            chunks.append(key(nx, ny))
            return True
    return False


def ensure_world(w):
    """Deterministic migration: old facilities get separate existing free parcels.
    No balances/inventories/prices or existing footprints are rewritten.
    """
    if "land" not in w:
        w["land"] = {c: {"chunks": initial_chunks(), "plots": {}} for c in CITIES}
    for fid in sorted(w["facilities"]):
        f = w["facilities"][fid]
        if "plot" in f:
            continue
        city = f["city"]
        layout = w["land"][city]
        location = free_plot(city, layout["chunks"], layout["plots"])
        if location is None:
            raise ValueError("cannot migrate facility: no free parcel")
        x, y = location
        f["plot"] = {"x": x, "y": y}
        layout["plots"][key(x, y)] = {"owner": f["owner"], "building": fid}
        grow(city, layout["chunks"], layout["plots"], x, y)


def audit(w):
    if "land" not in w:
        return True  # Old persisted world, migration occurs before next write.
    try:
        seen = set()
        for city in CITIES:
            layout = w["land"][city]
            chunks, plots = layout["chunks"], layout["plots"]
            if not 4 <= len(chunks) <= MAX_CHUNKS or len(set(chunks)) != len(chunks):
                return False
            if not set(initial_chunks()).issubset(chunks):
                return False
            reached, pending = {"0:0"}, [(0, 0)]
            chunk_set = set(chunks)
            for item in chunks:
                cx, cy = map(int, item.split(":"))
                if key(cx, cy) != item or not (0 <= cx < LIMIT // CHUNK and 0 <= cy < LIMIT // CHUNK):
                    return False
            while pending:
                cx, cy = pending.pop()
                for nx, ny in [(cx+1,cy),(cx-1,cy),(cx,cy+1),(cx,cy-1)]:
                    item = key(nx, ny)
                    if item in chunk_set and item not in reached:
                        reached.add(item)
                        pending.append((nx, ny))
            if reached != chunk_set:
                return False
            for position, p in plots.items():
                x, y = map(int, position.split(":"))
                if key(x,y) != position or not is_open(chunks,x,y) or code_at(city,x,y) != 0:
                    return False
                if "company:" + p["owner"] not in w["wallets"]:
                    return False
                fid = p.get("building", "")
                if fid:
                    f = w["facilities"][fid]
                    if f["owner"] != p["owner"] or f["city"] != city or f.get("plot") != {"x":x,"y":y} or fid in seen:
                        return False
                    if f["kind"] == "mine" and not has_ore(city,x,y):
                        return False
                    seen.add(fid)
        return seen == set(w["facilities"])
    except (KeyError, ValueError, TypeError, AttributeError):
        return False
