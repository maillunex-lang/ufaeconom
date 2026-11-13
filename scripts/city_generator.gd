extends RefCounted
class_name CityGenerator

## Deterministic prototype. Geographic names are illustrative, not a verified register.
const SIZE := 32
const ROAD_STEP := 7
const TYPES := ["Жилой дом", "Магазин", "Склад", "Завод", "Офис"]
const CITIES := [
	{"name": "Уфа", "seed": 101},
	{"name": "Стерлитамак", "seed": 202},
	{"name": "Туймазы", "seed": 303},
	{"name": "Белорецк", "seed": 404}
]

static func make_city(city_index: int) -> Dictionary:
	var city: Dictionary = CITIES[posmod(city_index, CITIES.size())]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(city["seed"])
	var cells: Dictionary = {}
	for y in range(SIZE):
		for x in range(SIZE):
			var tile := Vector2i(x, y)
			var road := x % ROAD_STEP == 0 or y % ROAD_STEP == 0
			var kind := "Дорога" if road else "Свободный участок"
			if not road:
				var roll := rng.randf()
				if roll < 0.44:
					kind = TYPES[rng.randi_range(0, TYPES.size() - 1)]
				elif roll < 0.58:
					kind = "Дерево"
			cells[tile] = kind
	return {"name": city["name"], "cells": cells, "seed": city["seed"]}
