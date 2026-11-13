extends CanvasLayer
## Read-only until authenticated. All mutations go through server commands.
const SafeArea = preload("res://scripts/mobile_safe_area.gd")
var mmo: CanvasLayer
var safe: Control
var panel: Control
var picker: OptionButton
var tabs: TabContainer
var labels: Array[Label] = []
var staff_count: SpinBox
var wage_amount: SpinBox
var production_target: SpinBox
var raw_qty: SpinBox
var recipe_picker: OptionButton
var goods_picker: OptionButton
var freight_goods: OptionButton
var bread_price: SpinBox
var destination: OptionButton
var freight_qty: SpinBox
var status: Label

func _ready() -> void:
    layer = 19
    mmo = get_parent().mmo_panel
    safe = SafeArea.new()
    add_child(safe)
    var body: VBoxContainer = safe.add_panel("TycoonPanel", 515, 650, false)
    panel = safe.get_node("TycoonPanel")
    panel.visible = false
    var title := Label.new()
    title.text = "🏭 УПРАВЛЕНИЕ КОМПАНИЕЙ"
    body.add_child(title)
    picker = OptionButton.new()
    picker.custom_minimum_size.y = 42
    picker.item_selected.connect(func(_i: int) -> void: refresh())
    body.add_child(picker)
    tabs = TabContainer.new()
    tabs.custom_minimum_size.y = 320
    body.add_child(tabs)
    for tab in ["Обзор", "Производство", "Персонал", "Продажи", "Логистика", "Финансы"]:
        var page := VBoxContainer.new()
        page.name = tab
        tabs.add_child(page)
        var label := Label.new()
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        page.add_child(label)
        labels.append(label)
    production_target = _spin(tabs.get_child(1), "Партии за тик (0–4)", 0, 4, 1)
    _action(tabs.get_child(1), "Установить план", _set_production)
    recipe_picker = OptionButton.new()
    for key in ["bread", "flour", "bakery"]:
        recipe_picker.add_item(key)
    tabs.get_child(1).add_child(recipe_picker)
    _action(tabs.get_child(1), "Сменить рецепт", _set_recipe)
    _action(tabs.get_child(1), "Модернизировать оборудование", _upgrade_equipment)
    raw_qty = _spin(tabs.get_child(1), "Закупить зерно (1–100 ед.)", 1, 100, 1)
    _action(tabs.get_child(1), "Закупить зерно у поставщика", _buy_grain)
    staff_count = _spin(tabs.get_child(2), "Работники", 0, 20, 1)
    wage_amount = _spin(tabs.get_child(2), "Оплата за производственную единицу, коп.", 500, 3000, 50)
    _action(tabs.get_child(2), "Сохранить персонал", _set_staff)
    goods_picker = OptionButton.new()
    for good in ["bread", "milk", "flour"]:
        goods_picker.add_item(good)
    tabs.get_child(3).add_child(goods_picker)
    goods_picker.item_selected.connect(func(_i: int) -> void: _refresh_price())
    bread_price = _spin(tabs.get_child(3), "Цена хлеба, коп.", 10850, 23250, 50)
    _action(tabs.get_child(3), "Изменить цену", _set_price)
    destination = OptionButton.new()
    tabs.get_child(4).add_child(destination)
    freight_goods = OptionButton.new()
    for good in ["bread", "milk", "flour", "grain"]:
        freight_goods.add_item(good)
    tabs.get_child(4).add_child(freight_goods)
    freight_qty = _spin(tabs.get_child(4), "Количество единиц (1–50)", 1, 50, 1)
    _action(tabs.get_child(4), "Отправить хлеб", _send_shipment)
    status = Label.new()
    status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_child(status)
    mmo.client.snapshot_ready.connect(func(_data: Dictionary) -> void: refresh())
    mmo.client.request_failed.connect(func(err: String) -> void: status.text = err)
    mmo.client.command_ready.connect(func(_data: Dictionary) -> void: status.text = "Команда подтверждена сервером")
    mmo.client.disconnected.connect(func() -> void: panel.visible = false)

func _spin(parent: Node, caption: String, min_value: int, max_value: int, step: int) -> SpinBox:
    var label := Label.new()
    label.text = caption
    parent.add_child(label)
    var input := SpinBox.new()
    input.min_value = min_value
    input.max_value = max_value
    input.step = step
    input.custom_minimum_size.y = 40
    parent.add_child(input)
    return input

func _action(parent: Node, title: String, callback: Callable) -> void:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size.y = 44
    button.pressed.connect(callback)
    parent.add_child(button)

func toggle() -> void:
    if not mmo.online_active():
        mmo._on_error("Войдите в MMO для управления компанией")
        return
    panel.visible = not panel.visible
    if panel.visible:
        refresh()

func _facility_id() -> String:
    if picker.item_count == 0 or picker.selected < 0:
        return ""
    return str(picker.get_item_metadata(picker.selected))

func refresh() -> void:
    if not is_instance_valid(picker) or not mmo.online_active():
        return
    var snapshot: Dictionary = mmo.client.snapshot
    var facilities: Dictionary = snapshot.get("facilities", {})
    var selected_id := _facility_id()
    picker.clear()
    for id in facilities:
        var f: Dictionary = facilities[id]
        picker.add_item("%s • %s" % [str(id), str(f.get("city", ""))])
        picker.set_item_metadata(picker.item_count - 1, str(id))
        if str(id) == selected_id:
            picker.select(picker.item_count - 1)
    if picker.item_count > 0 and picker.selected < 0:
        picker.select(0)
    var id := _facility_id()
    if id == "" or not facilities.has(id):
        for label in labels:
            label.text = "Нет предприятий"
        return
    var f: Dictionary = facilities[id]
    var stock: Dictionary = f.get("stock", {})
    var metrics: Dictionary = snapshot.get("company_metrics", {})
    labels[0].text = "%s • %s\nЗапасы: %s\nЁмкость: %d\nРепутация: %d" % [str(f.get("kind", "")), str(f.get("city", "")), str(stock), int(f.get("capacity", 0)), int(f.get("reputation", 0))]
    labels[1].text = "Последний выпуск: %d ед.\nТик: %d\nРецепт: %s\nОборудование: уровень %d\nЗерно: %d | Мука: %d" % [int(f.get("production_last_units", 0)), int(f.get("production_last_tick", 0)), str(f.get("recipe", "bread")), int(f.get("equipment_level", 1)), int(stock.get("grain", 0)), int(stock.get("flour", 0))]
    for i in range(recipe_picker.item_count):
        if recipe_picker.get_item_text(i) == str(f.get("recipe", "bread")):
            recipe_picker.select(i)
    production_target.value = int(f.get("production_target", 1))
    labels[2].text = "Штат: %d\nТекущая оплата: %d коп." % [int(f.get("workers", 0)), int(f.get("wage_minor", 750))]
    staff_count.max_value = int(snapshot.get("staff_limits", {}).get(str(f.get("kind", "")), 20))
    staff_count.value = int(f.get("workers", 0))
    wage_amount.value = int(f.get("wage_minor", 750))
    labels[3].text = "Рыночная цена зависит от спроса и конкурентов.\nТекущие цены: %s" % str(f.get("prices", {}))
    _refresh_price()
    labels[4].text = "Доставка платная. Срок и стоимость рассчитывает сервер."
    var old_dst := ""
    if destination.item_count > 0 and destination.selected >= 0:
        old_dst = str(destination.get_item_metadata(destination.selected))
    destination.clear()
    for other in facilities:
        if str(other) != id:
            destination.add_item(str(other))
            destination.set_item_metadata(destination.item_count - 1, str(other))
            if str(other) == old_dst:
                destination.select(destination.item_count - 1)
    if destination.item_count > 0 and destination.selected < 0:
        destination.select(0)
    labels[5].text = "Выручка: %d коп.\nСебестоимость: %d коп.\nРасходы: %d коп.\nЛогистика: %d коп.\nПрибыль: %d коп." % [int(metrics.get("revenue", 0)), int(metrics.get("cogs", 0)), int(metrics.get("operating_expense", 0)), int(metrics.get("freight", 0)), int(metrics.get("profit", 0))]
    var history: Array = snapshot.get("finance_history", [])
    for entry in history.slice(maxi(0, history.size() - 5)):
        labels[5].text += "\n%s: %d коп." % [str(entry.get("kind", "")), int(entry.get("amount", 0))]

func _send(kind: String, fields: Dictionary) -> void:
    if not mmo.online_active() or _facility_id() == "":
        return
    fields["facility_id"] = _facility_id()
    mmo.client.send_command(kind, fields)

func _set_production() -> void:
    _send("facility.set_production", {"target": int(production_target.value)})

func _set_recipe() -> void:
    _send("facility.set_recipe", {"recipe": recipe_picker.get_item_text(recipe_picker.selected)})

func _upgrade_equipment() -> void:
    _send("facility.upgrade_equipment", {})

func _buy_grain() -> void:
    _send("facility.buy", {"good": "grain", "quantity": int(raw_qty.value)})

func _set_staff() -> void:
    _send("facility.set_staff", {"workers": int(staff_count.value), "wage_minor": int(wage_amount.value)})

func _refresh_price() -> void:
    if goods_picker.selected < 0 or bread_price == null or picker.selected < 0:
        return
    var good := goods_picker.get_item_text(goods_picker.selected)
    var base: int = {"bread": 15500, "milk": 18000, "flour": 10000}.get(good, 15500)
    bread_price.min_value = int(base * 7 / 10)
    bread_price.max_value = int(base * 3 / 2)
    var facility: Dictionary = mmo.client.snapshot.get("facilities", {}).get(_facility_id(), {})
    bread_price.value = int(facility.get("prices", {}).get(good, base))

func _set_price() -> void:
    _send("facility.set_price", {"good": goods_picker.get_item_text(goods_picker.selected), "price_minor": int(bread_price.value)})

func _send_shipment() -> void:
    if destination.selected < 0:
        return
    _send("shipment.create", {"destination_id": str(destination.get_item_metadata(destination.selected)), "good": freight_goods.get_item_text(freight_goods.selected), "quantity": int(freight_qty.value)})