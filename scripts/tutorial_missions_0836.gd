extends RefCounted
## Local tutorial only: no economy mutation and no server-side reward claims.
const SAVE_PATH := "user://beo_tutorial_0836.json"
const STEPS := [
    {"id":"explore","title":"Осмотрите город","detail":"Выберите любой доступный участок на карте.","xp":20},
    {"id":"find","title":"Найдите место для бизнеса","detail":"Включите подсветку свободных участков.","xp":20},
    {"id":"land","title":"Купите землю","detail":"Приобретите первый участок компании.","xp":40},
    {"id":"build","title":"Откройте предприятие","detail":"Постройте первое здание на своём участке.","xp":60},
    {"id":"manage","title":"Познакомьтесь с управлением","detail":"Откройте раздел «Бизнес».","xp":30},
    {"id":"market","title":"Изучите рынок","detail":"Откройте раздел «Рынок».","xp":30}
]
var completed: Dictionary = {}
var experience := 0
var save_path := SAVE_PATH

func load_progress() -> void:
    if not FileAccess.file_exists(save_path):
        return
    var file := FileAccess.open(save_path, FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not (parsed is Dictionary):
        return
    if int(parsed.get("version", 0)) != 1:
        return
    var values: Variant = parsed.get("completed", [])
    if not (values is Array):
        return
    completed.clear()
    experience = 0
    for step in STEPS:
        if values.has(step["id"]):
            completed[step["id"]] = true
            experience += int(step["xp"])

func save_progress() -> bool:
    var file := FileAccess.open(save_path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify({"version":1,"completed":completed.keys()}))
    return true

func mark(id: String) -> bool:
    for step in STEPS:
        if step["id"] == id:
            if completed.has(id):
                return false
            completed[id] = true
            experience += int(step["xp"])
            save_progress()
            return true
    return false

func refresh_from_game(game: Node) -> void:
    if game.selected.x >= 0:
        mark("explore")
    if game.show_available_plots:
        mark("find")
    # Local demo ownership is read from the save; online progression is deliberately
    # not inferred from snapshots without an authoritative server mission system.
    if game.mmo_panel.online_active():
        return
    var owned_any := false
    var built_any := false
    for record in game.company.owned.values():
        owned_any = true
        if str(record.get("building","")) != "":
            built_any = true
    if owned_any:
        mark("land")
    if built_any:
        mark("build")

func next_step() -> Dictionary:
    for step in STEPS:
        if not completed.has(step["id"]):
            return step
    return {}

func progress_text() -> String:
    var lines := "ОБУЧЕНИЕ • %d/%d шагов • %d очков опыта\n" % [completed.size(),STEPS.size(),experience]
    for step in STEPS:
        lines += ("✓ " if completed.has(step["id"]) else "○ ") + str(step["title"]) + " • +%d опыта\n" % int(step["xp"])
    var next := next_step()
    if not next.is_empty():
        lines += "\nСледующая цель: " + str(next["detail"])
    else:
        lines += "\nВсе стартовые задания выполнены!"
    lines += "\n\nОчки опыта учебные: не являются игровой валютой и не влияют на MMO."
    return lines