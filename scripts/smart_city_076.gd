extends RefCounted
## Bounded, deterministic visual routing. Never simulates workers, inventory or payments.
const Land = preload("res://scripts/city_land.gd")
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

static func road_neighbors(city: int, tile: Vector2i, opened: Dictionary) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for step in DIRECTIONS:
        var next: Vector2i = tile + step
        if opened.has(Land.chunk_key(next)) and Land.kind_at(city, next) == "Дорога":
            result.append(next)
    return result

static func route(city: int, start: Vector2i, target: Vector2i, opened: Dictionary, max_nodes: int = 96) -> Array[Vector2i]:
    if not opened.has(Land.chunk_key(start)) or not opened.has(Land.chunk_key(target)):
        return []
    if Land.kind_at(city, start) != "Дорога" or Land.kind_at(city, target) != "Дорога":
        return []
    var frontier: Array[Vector2i] = [start]
    var previous: Dictionary = {start: start}
    var index := 0
    while index < frontier.size() and index < max_nodes:
        var current := frontier[index]
        index += 1
        if current == target:
            var result: Array[Vector2i] = [target]
            while result[0] != start:
                result.push_front(previous[result[0]])
            return result
        for neighbor in road_neighbors(city, current, opened):
            if not previous.has(neighbor) and frontier.size() < max_nodes:
                previous[neighbor] = current
                frontier.append(neighbor)
    return []

static func visual_construction_phase(record: Dictionary) -> String:
    # Only server-declared state may trigger a construction phase.
    var state := str(record.get("construction_state", ""))
    if state in ["foundation", "frame", "finishing", "completed"]:
        return state
    return "unknown"

static func display_metrics(snapshot: Dictionary, building: String) -> Dictionary:
    # Never infer production or profit from a decorative building type.
    var facilities: Variant = snapshot.get("facilities", [])
    if not (facilities is Array):
        return {}
    for item in facilities:
        if item is Dictionary and str(item.get("kind", "")) == building:
            var fields: Dictionary = {}
            for key in ["production", "inventory", "profit_minor", "workers", "capacity"]:
                if item.has(key):
                    fields[key] = item[key]
            return fields
    return {}