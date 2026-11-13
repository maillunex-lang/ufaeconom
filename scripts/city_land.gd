extends RefCounted
## Layout v1: immutable old core, coordinate-based outer quarters.
const CHUNK := 16
const LIMIT := 16384
const MAX_CHUNKS := 4096
const KINDS := ["Свободный участок", "Дорога", "Дерево", "Жилой дом", "Магазин", "Склад", "Завод", "Офис"]
const CITY_IDS := ["ufa", "sterlitamak", "tuymazy", "beloretsk"]
const SERVER_KINDS := {"Магазин": "shop", "Склад": "warehouse", "Завод": "factory", "Шахта": "mine", "Исследовательский центр": "research_center", "Автосалон": "car_dealership"}
static var _cores: Array = []

static func initial_chunks() -> Array:
	return ["0:0", "1:0", "0:1", "1:1"]

static func plot_key(tile: Vector2i) -> String:
	return "%d:%d" % [tile.x, tile.y]

static func chunk_key(tile: Vector2i) -> String:
	return "%d:%d" % [tile.x / CHUNK, tile.y / CHUNK]

static func is_open(chunks: Array, tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < LIMIT and tile.y < LIMIT and chunks.has(chunk_key(tile))

static func code_at(city: int, tile: Vector2i) -> int:
	if tile.x < 0 or tile.y < 0 or tile.x >= LIMIT or tile.y >= LIMIT:
		return -1
	if tile.x < 32 and tile.y < 32:
		if _cores.is_empty():
			_cores = JSON.parse_string(FileAccess.get_file_as_string("res://data/city_cores_v1.json"))
		return int(_cores[posmod(city, 4)][tile.y * 32 + tile.x])
	if tile.x % 7 == 0 or tile.y % 7 == 0:
		return 1
	var h := posmod((city + 1) * 101 + tile.x * 73856093 + tile.y * 19349663, 2147483647)
	return 2 if h % 10 == 0 else 0

static func kind_at(city: int, tile: Vector2i) -> String:
	var code := code_at(city, tile)
	return KINDS[code] if code >= 0 else "За границей города"

static func has_ore(city: int, tile: Vector2i) -> bool:
	return code_at(city, tile) == 0 and posmod((city + 1) * 101 + tile.x * 73856093 + tile.y * 19349663, 2147483647) % 19 == 0

static func free_plot(city: int, chunks: Array, plots: Dictionary, ore_only: bool = false) -> Vector2i:
	for key in chunks:
		var parts: PackedStringArray = str(key).split(":")
		var origin := Vector2i(int(parts[0]), int(parts[1])) * CHUNK
		for y in range(origin.y, origin.y + CHUNK):
			for x in range(origin.x, origin.x + CHUNK):
				var tile := Vector2i(x, y)
				if code_at(city, tile) == 0 and not plots.has(plot_key(tile)) and (not ore_only or has_ore(city, tile)):
					return tile
	return Vector2i(-1, -1)

static func grow(city: int, chunks: Array, plots: Dictionary, built_tile: Vector2i) -> bool:
	if chunks.size() >= MAX_CHUNKS:
		return false
	var cx := built_tile.x / CHUNK
	var cy := built_tile.y / CHUNK
	var free_count := 0
	var occupied := 0
	for y in range(cy * CHUNK, (cy + 1) * CHUNK):
		for x in range(cx * CHUNK, (cx + 1) * CHUNK):
			var tile := Vector2i(x, y)
			if code_at(city, tile) == 0:
				if not plots.has(plot_key(tile)):
					free_count += 1
				elif str(plots[plot_key(tile)].get("building", "")) != "":
					occupied += 1
	var edge_x := built_tile.x % CHUNK >= CHUNK - 3
	var edge_y := built_tile.y % CHUNK >= CHUNK - 3
	var dense := free_count < 16 or occupied * 5 >= (occupied + free_count) * 3
	var candidates: Array = []
	if edge_x:
		candidates.append(Vector2i(cx + 1, cy))
	if edge_y:
		candidates.append(Vector2i(cx, cy + 1))
	if dense:
		candidates.append_array([Vector2i(cx + 1, cy), Vector2i(cx, cy + 1), Vector2i(cx - 1, cy), Vector2i(cx, cy - 1)])
	for c in candidates:
		if c.x < 0 or c.y < 0 or c.x >= LIMIT / CHUNK or c.y >= LIMIT / CHUNK:
			continue
		var key := plot_key(c)
		if not chunks.has(key):
			chunks.append(key)
			return true
	return false

static func valid_chunks(value: Variant) -> bool:
	if not (value is Array) or value.size() < 4 or value.size() > MAX_CHUNKS:
		return false
	var visited: Dictionary = {}
	for item in value:
		if not (item is String):
			return false
		var parts := str(item).split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return false
		var tile := Vector2i(int(parts[0]), int(parts[1]))
		if tile.x < 0 or tile.y < 0 or tile.x >= LIMIT / CHUNK or tile.y >= LIMIT / CHUNK or plot_key(tile) != item or visited.has(item):
			return false
		visited[item] = true
	for item in initial_chunks():
		if not visited.has(item):
			return false
	# Require a connected territory; canonical save cannot activate isolated islands.
	var reached := {"0:0": true}
	var pending: Array = [Vector2i.ZERO]
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + delta
			var id := plot_key(next)
			if visited.has(id) and not reached.has(id):
				reached[id] = true
				pending.append(next)
	return reached.size() == visited.size()
