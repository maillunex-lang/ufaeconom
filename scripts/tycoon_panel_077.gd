extends CanvasLayer
## Read-only until authenticated. All mutations go through server commands.
const SafeArea = preload("res://scripts/mobile_safe_area.gd")
var mmo: CanvasLayer
var safe: Control
var panel: Control
var picker: OptionButton
var tabs: TabContainer
var labels: Array[Label] = []
var pages: Array[VBoxContainer] = []
var contract_picker: OptionButton
var offer_good: OptionButton
var offer_quantity: SpinBox
var offer_price: SpinBox
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
var invest_confirm: ConfirmationDialog

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
    for tab in ["Обзор", "Производство", "Персонал", "Продажи", "Логистика", "Финансы", "Контракты", "Конкуренты", "Аналитика рынка", "Экономический советник", "Автоматизация"]:
        var scroll := ScrollContainer.new()
        scroll.name = tab
        tabs.add_child(scroll)
        var page := VBoxContainer.new()
        page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        scroll.add_child(page)
        pages.append(page)
        var label := Label.new()
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        page.add_child(label)
        labels.append(label)
    _action(pages[0], "Инвестировать в инфраструктуру района", _confirm_investment)
    invest_confirm = ConfirmationDialog.new()
    invest_confirm.title = "Инвестиция в инфраструктуру"
    invest_confirm.confirmed.connect(_invest_district)
    panel.add_child(invest_confirm)
    production_target = _spin(pages[1], "Партии за тик (0–4)", 0, 4, 1)
    _action(pages[1], "Установить план", _set_production)
    recipe_picker = OptionButton.new()
    for key in ["bread", "flour", "bakery", "steel", "parts", "car"]:
        recipe_picker.add_item(key)
    pages[1].add_child(recipe_picker)
    _action(pages[1], "Сменить рецепт", _set_recipe)
    _action(pages[1], "Модернизировать оборудование", _upgrade_equipment)
    raw_qty = _spin(pages[1], "Закупить зерно (1–100 ед.)", 1, 100, 1)
    _action(pages[1], "Закупить зерно у поставщика", _buy_grain)
    staff_count = _spin(pages[2], "Работники", 0, 20, 1)
    wage_amount = _spin(pages[2], "Оплата за производственную единицу, коп.", 500, 3000, 50)
    _action(pages[2], "Сохранить персонал", _set_staff)
    goods_picker = OptionButton.new()
    for good in ["bread", "milk", "flour", "car"]:
        goods_picker.add_item(good)
    pages[3].add_child(goods_picker)
    goods_picker.item_selected.connect(func(_i: int) -> void: _refresh_price())
    bread_price = _spin(pages[3], "Цена хлеба, коп.", 10850, 23250, 50)
    _action(pages[3], "Изменить цену", _set_price)
    destination = OptionButton.new()
    pages[4].add_child(destination)
    freight_goods = OptionButton.new()
    for good in ["bread", "milk", "flour", "grain", "ore", "steel", "parts", "car"]:
        freight_goods.add_item(good)
    pages[4].add_child(freight_goods)
    _action(pages[4], "Расширить склад (+100 мест)", _expand_storage)
    freight_qty = _spin(pages[4], "Количество единиц (1–50)", 1, 50, 1)
    _action(pages[4], "Отправить хлеб", _send_shipment)
    offer_good = OptionButton.new()
    for good in ["ore", "steel", "parts", "car", "grain", "flour", "bread"]:
        offer_good.add_item(good)
    pages[6].add_child(offer_good)
    offer_quantity = _spin(pages[6], "Количество по контракту (1–50)", 1, 50, 1)
    offer_price = _spin(pages[6], "Цена за единицу, коп.", 1, 10000000, 100)
    _action(pages[6], "Опубликовать предложение", _offer_contract)
    contract_picker = OptionButton.new()
    pages[6].add_child(contract_picker)
    _action(pages[6], "Принять контракт на выбранный склад", _accept_contract)
    var automation_enable := CheckBox.new()
    automation_enable.name = "AutomationEnabled"
    automation_enable.text = "Включить автоматизацию выбранного предприятия"
    pages[10].add_child(automation_enable)
    var automation_buy := CheckBox.new()
    automation_buy.name = "AutomationBuy"
    automation_buy.text = "Автозакупки сырья (завод)"
    pages[10].add_child(automation_buy)
    var automation_restock := CheckBox.new()
    automation_restock.name = "AutomationRestock"
    automation_restock.text = "Автопополнение из своих заводов (магазин)"
    pages[10].add_child(automation_restock)
    var automation_production := CheckBox.new()
    automation_production.name = "AutomationProduction"
    automation_production.text = "Автоплан производства (завод)"
    pages[10].add_child(automation_production)
    var automation_pricing := CheckBox.new()
    automation_pricing.name = "AutomationPricing"
    automation_pricing.text = "Автоцены по конкурентам (магазин)"
    pages[10].add_child(automation_pricing)
    _spin(pages[10], "Дневной бюджет, коп. (0–5 000 000)", 0, 5000000, 5000).name = "AutomationBudget"
    _spin(pages[10], "Целевой запас (0–300)", 0, 300, 1).name = "AutomationStock"
    _spin(pages[10], "Лимит единиц за закупку (1–100)", 1, 100, 1).name = "AutomationQuantity"
    _spin(pages[10], "План партий (0–4)", 0, 4, 1).name = "AutomationTarget"
    _spin(pages[10], "Снижение цены относительно конкурента, коп.", 0, 1000, 50).name = "AutomationUndercut"
    _action(pages[10], "Сохранить правила на сервере", _save_automation)
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
    var growth: Dictionary = snapshot.get("company_growth", {})
    labels[0].text += "\n\nРАЗВИТИЕ КОМПАНИИ: %d/3 целей" % int(growth.get("completed_goals", 0))
    for goal in growth.get("goals", []):
        var goal_names := {"portfolio": "Портфель предприятий", "diversification": "Разнообразие отраслей", "regional": "Новые города"}
        labels[0].text += "\n%s: %d/%d" % [str(goal_names.get(str(goal.get("id", "")), "")), int(goal.get("current", 0)), int(goal.get("target", 0))]
    var operations: Dictionary = snapshot.get("company_operations", {})
    for diagnostic in operations.get("factory_diagnostics", []):
        if str(diagnostic.get("id", "")) == id:
            labels[0].text += "\n\nПЛАН ПРОИЗВОДСТВА: %d партий, возможный выпуск %d ед." % [
                int(diagnostic.get("planned_batches", 0)), int(diagnostic.get("potential_output", 0))]
            var problems: Array = diagnostic.get("issues", [])
            if not problems.is_empty():
                labels[0].text += "\nПРОВЕРИТЬ: " + ", ".join(problems)
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
    labels[4].text = "Доставка платная. Срок и стоимость рассчитывает сервер.\nСкладские остатки: %s" % str(stock)
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
    var contracts: Array = snapshot.get("contracts", [])
    labels[6].text = "Предложения других компаний и ваши контракты:"
    contract_picker.clear()
    for contract in contracts:
        labels[6].text += "\n%s %s: %d × %d коп. [%s]" % [str(contract.get("id", "")), str(contract.get("good", "")), int(contract.get("quantity", 0)), int(contract.get("price_minor", 0)), str(contract.get("status", ""))]
        if contract.get("status") == "offered" and str(contract.get("seller", "")) != str(snapshot.get("company", "")):
            contract_picker.add_item(str(contract.get("id", "")) + " " + str(contract.get("good", "")))
            contract_picker.set_item_metadata(contract_picker.item_count - 1, str(contract.get("id", "")))
    var rules: Dictionary = snapshot.get("automation_rules", {})
    var rule: Dictionary = rules.get(id, {})
    var controls := {"enabled": "AutomationEnabled", "buy_inputs": "AutomationBuy",
        "restock": "AutomationRestock", "production": "AutomationProduction",
        "pricing": "AutomationPricing"}
    for key in controls:
        var checkbox: CheckBox = pages[10].get_node(str(controls[key]))
        checkbox.button_pressed = bool(rule.get(key, false))
    var numbers := {"daily_budget_minor": "AutomationBudget", "stock_target": "AutomationStock",
        "max_purchase_units": "AutomationQuantity", "production_target": "AutomationTarget",
        "undercut_minor": "AutomationUndercut"}
    for key in numbers:
        var spin: SpinBox = pages[10].get_node(str(numbers[key]))
        spin.value = int(rule.get(key, 1 if key == "max_purchase_units" else 0))
    labels[10].text = "Сервер проверяет бюджет и права. Решения выполняются раз в игровой день."
    for event in snapshot.get("automation_events", []).slice(-12):
        labels[10].text += "\nТик %d • %s: %s" % [
            int(event.get("tick", 0)), str(event.get("action", "")), str(event.get("detail", ""))]
    var intelligence: Dictionary = snapshot.get("economic_intelligence", {})
    var profitability: Dictionary = intelligence.get("profitability", {})
    labels[9].text = "ЭКОНОМИЧЕСКИЙ СОВЕТНИК\nПрогноз: 1 игровой день, среднее продаж за 7 дней.\nЭто оценка, а не гарантия.\n\nФинансовый результат (накопленный): %d коп.\nВыручка: %d коп." % [
        int(profitability.get("profit_minor", 0)), int(profitability.get("revenue_minor", 0))]
    if profitability.get("margin_bps") != null:
        labels[9].text += "\nРентабельность продаж: %.1f%%" % [float(profitability["margin_bps"]) / 100.0]
    var forecasts: Dictionary = intelligence.get("forecasts", {})
    for city in ["ufa", "sterlitamak", "tuymazy", "beloretsk"]:
        var city_forecast: Dictionary = forecasts.get(city, {})
        labels[9].text += "\n\n%s:" % city
        for good in ["bread", "milk", "flour"]:
            var data: Dictionary = city_forecast.get(good, {})
            labels[9].text += "\n%s: ~%d ед./день, неудовлетворённый спрос ~%d" % [
                good, int(data.get("forecast_daily_units", 0)),
                int(data.get("unserved_daily_units_estimate", 0))]
    labels[9].text += "\n\nПЛАН ЗАКУПОК"
    for plan in intelligence.get("procurement_plans", []):
        labels[9].text += "\n%s: %s, нехватка %d, можно купить %d ед. за %d коп." % [
            str(plan.get("facility_id", "")), str(plan.get("good", "")),
            int(plan.get("shortage_units", 0)), int(plan.get("recommended_buy_units", 0)),
            int(plan.get("estimated_cost_minor", 0))]
    labels[9].text += "\n\nРЕКОМЕНДАЦИИ"
    for tip in intelligence.get("recommendations", []):
        labels[9].text += "\n%s: %s %s (%d ед.)" % [
            str(tip.get("facility_id", "")), str(tip.get("kind", "")),
            str(tip.get("good", "")), int(tip.get("units", 0))]
    var market_data: Dictionary = snapshot.get("market_analytics", {})
    labels[8].text = "Рынок: реальные продажи за %d игровых дней (макс. 30)." % int(snapshot.get("market_window_days", 0))
    for city in ["ufa", "sterlitamak", "tuymazy", "beloretsk"]:
        var city_data: Dictionary = market_data.get(city, {})
        labels[8].text += "\n\n%s" % city
        for good in ["bread", "milk", "flour"]:
            var info: Dictionary = city_data.get(good, {})
            labels[8].text += "\n%s: %d ед. | спрос %d/тик" % [
                good, int(info.get("units_sold_30d", 0)), int(info.get("demand_per_tick", 0))]
            var shares: Dictionary = info.get("share_bps", {})
            for company in shares:
                labels[8].text += "\n  %s: %.1f%%" % [str(company), float(shares[company]) / 100.0]
    labels[8].text += "\n\nРАЙОННЫЙ РЫНОК (локация влияет на продажи)"
    for district in snapshot.get("district_demand", []):
        if int(district.get("own", 0)) > 0:
            var infra: Dictionary = district.get("infrastructure", {})
            labels[8].text += "\n%s / %s: жителей ~%d, магазинов %d, заводов %d, спрос хлеба ~%d/тик" % [
                str(district.get("city", "")), str(district.get("district", "")),
                int(district.get("synthetic_population", 0)),
                int(district.get("shops", 0)), int(district.get("factories", 0)),
                int(district.get("estimated_bread_demand_per_tick", 0))]
            labels[8].text += "\n  Жилая застройка %d/5 • изменение населения %+d/мес." % [
                int(district.get("residential_tier", 0)), int(district.get("population_trend", 0))]
            var urban: Dictionary = district.get("urban_metrics", {})
            labels[8].text += "\n  Транспорт %d/100 • загруженность %d/100 • земля ~%d ₽ • профиль %s" % [
                int(urban.get("transport_access", 0)), int(urban.get("traffic_congestion", 0)),
                int(urban.get("indicative_land_value_minor", 0)) / 100,
                str(urban.get("specialization", "mixed"))]
            labels[8].text += "\n  Привлекательность %d/100 • дороги %d • жилые участки %d • инвестиции %d/5" % [
                int(infra.get("attractiveness", 0)), int(infra.get("roads", 0)),
                int(infra.get("housing_tiles", 0)), int(infra.get("investment_level", 0))]
    var competitors: Array = snapshot.get("npc_competitors", [])
    labels[7].text = "NPC-компании работают на сервере.\nОбновление решений: 1 игровой день."
    for competitor in competitors:
        labels[7].text += "\n\n%s • %d предприятий\nКапитал: %d коп.\nДействие: %s" % [
            str(competitor.get("owner", "")) + " [" + str(competitor.get("strategy", "")) + "]", int(competitor.get("facilities", 0)),
            int(competitor.get("cash_minor", 0)), str(competitor.get("latest_action", ""))]
    labels[7].text += "\n\nЦЕНОВЫЕ СРАВНЕНИЯ (только аналитика)"
    for offer in snapshot.get("competition_opportunities", []):
        if str(offer.get("facility_id", "")) == id:
            labels[7].text += "\n%s: наша %d коп. / минимум конкурентов %d коп. / разница %+d коп." % [
                str(offer.get("good", "")), int(offer.get("own_price_minor", 0)),
                int(offer.get("lowest_competitor_minor", 0)), int(offer.get("difference_minor", 0))]
    var activity: Array = snapshot.get("npc_activity", [])
    if not activity.is_empty():
        labels[7].text += "\n\nСОБЫТИЯ РЫНКА"
        for event in activity.slice(maxi(0, activity.size() - 8)):
            labels[7].text += "\nДень %d • %s: %s" % [
                int(int(event.get("tick", 0)) / 12), str(event.get("owner", "")),
                str(event.get("detail", ""))]
    labels[5].text = "Выручка: %d коп.\nСебестоимость: %d коп.\nРасходы: %d коп.\nЛогистика: %d коп.\nПрибыль: %d коп." % [int(metrics.get("revenue", 0)), int(metrics.get("cogs", 0)), int(metrics.get("operating_expense", 0)), int(metrics.get("freight", 0)), int(metrics.get("profit", 0))]
    var history: Array = snapshot.get("finance_history", [])
    for entry in history.slice(maxi(0, history.size() - 5)):
        labels[5].text += "\n%s: %d коп." % [str(entry.get("kind", "")), int(entry.get("amount", 0))]

func _selected_district() -> Dictionary:
    var facilities: Dictionary = mmo.client.snapshot.get("facilities", {})
    var facility: Dictionary = facilities.get(_facility_id(), {})
    var plot: Dictionary = facility.get("plot", {})
    if plot.is_empty():
        return {}
    return {"city": str(facility.get("city", "")),
            "district": "%d:%d" % [floori(int(plot.get("x", 0)) / 16.0), floori(int(plot.get("y", 0)) / 16.0)]}

func _confirm_investment() -> void:
    if not mmo.online_active():
        return
    var location := _selected_district()
    if location.is_empty():
        return
    var level := 0
    for district in mmo.client.snapshot.get("district_demand", []):
        if str(district.get("city", "")) == location["city"] and str(district.get("district", "")) == location["district"]:
            level = int(district.get("infrastructure", {}).get("investment_level", 0))
            break
    if level >= 5:
        status.text = "Инфраструктура района улучшена до максимума"
        return
    invest_confirm.dialog_text = "Улучшить район %s / %s до уровня %d/5 за %d ₽?\nСписание подтвердит сервер." % [
        location["city"], location["district"], level + 1, (level + 1) * 20000]
    invest_confirm.popup_centered()

func _invest_district() -> void:
    if not mmo.online_active():
        return
    var location := _selected_district()
    if not location.is_empty():
        mmo.client.send_command("district.invest", location)

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
    var base: int = {"bread": 15500, "milk": 18000, "flour": 10000, "car": 250000}.get(good, 15500)
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
func _offer_contract() -> void:
    if offer_good.selected < 0:
        return
    _send("contract.offer", {"good": offer_good.get_item_text(offer_good.selected),
        "quantity": int(offer_quantity.value), "price_minor": int(offer_price.value)})

func _accept_contract() -> void:
    if not mmo.online_active() or contract_picker.selected < 0 or _facility_id() == "":
        return
    mmo.client.send_command("contract.accept", {
        "contract_id": str(contract_picker.get_item_metadata(contract_picker.selected)),
        "destination_id": _facility_id()})

func _expand_storage() -> void:
    _send("facility.expand_storage", {})
func _save_automation() -> void:
    if not mmo.online_active() or _facility_id() == "":
        return
    var fields := {}
    var flags := {"enabled": "AutomationEnabled", "buy_inputs": "AutomationBuy",
        "restock": "AutomationRestock", "production": "AutomationProduction",
        "pricing": "AutomationPricing"}
    for key in flags:
        fields[key] = (pages[10].get_node(str(flags[key])) as CheckBox).button_pressed
    var limits := {"daily_budget_minor": "AutomationBudget", "stock_target": "AutomationStock",
        "max_purchase_units": "AutomationQuantity", "production_target": "AutomationTarget",
        "undercut_minor": "AutomationUndercut"}
    for key in limits:
        fields[key] = int((pages[10].get_node(str(limits[key])) as SpinBox).value)
    _send("automation.configure", fields)