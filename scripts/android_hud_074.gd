extends CanvasLayer
## Android landscape HUD: only client presentation and existing game actions.
const SafeArea = preload("res://scripts/mobile_safe_area.gd")
var game: Node2D
var safe: Control
var top: PanelContainer
var bottom: PanelContainer
var details: PanelContainer
var city_text: Label
var money_text: Label
var calendar_text: Label
var details_text: Label
var local_panels: Array[Control] = []
var local_open := false
var mmo_open := false
var visual_quality := 1
var business_panel: PanelContainer
var business_text: Label
var menu_overlay: PanelContainer
var menu_buttons: VBoxContainer
var menu_open := true
var camera_home: Button
var active_tab := "Город"
var nav_buttons: Dictionary = {}
var nav: HBoxContainer
var menu_backdrop: ColorRect
var menu_scroll: ScrollContainer
var business_close: Button
var business_title: Label
var business_actions: HBoxContainer
var settings_button: Button
var compact_layout := false
var construction_panel: PanelContainer
var construction_title: Label
var construction_status: Label
var construction_cost: Label
var construction_buttons: HBoxContainer
var construction_confirm: Button
var construction_cancel: Button
var construction_buy: Button
var construction_picker: OptionButton
var construction_toggle: Button
const UI_MIN_TOUCH := 48.0

func _ready() -> void:
    layer = 20
    game = get_parent()
    safe = SafeArea.new()
    safe.name = "HUDSafeArea"
    add_child(safe)
    top = _panel("HUDTop")
    bottom = _panel("HUDBottom")
    details = _panel("HUDDetails")
    business_panel = _panel("BusinessDetails")
    var business_box := VBoxContainer.new()
    business_box.add_theme_constant_override("separation", 8)
    business_panel.add_child(business_box)
    var business_header := HBoxContainer.new()
    business_box.add_child(business_header)
    business_title = _label(business_header, "ПРЕДПРИЯТИЕ", 18)
    business_close = Button.new()
    business_close.text = "✕"
    business_close.custom_minimum_size = Vector2(UI_MIN_TOUCH, UI_MIN_TOUCH)
    business_close.pressed.connect(func() -> void: business_panel.visible = false)
    business_header.add_child(business_close)
    business_text = _label(business_box, "Выберите предприятие", 15)
    business_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    business_actions = HBoxContainer.new()
    business_box.add_child(business_actions)
    _button(business_actions, "Управление", func() -> void: game.tycoon_panel.toggle())
    business_panel.visible = false
    construction_panel = _panel("ConstructionCard")
    var construction_box := VBoxContainer.new()
    construction_box.add_theme_constant_override("separation", 8)
    construction_panel.add_child(construction_box)
    construction_title = _label(construction_box, "СТРОИТЕЛЬСТВО", 19)
    construction_status = _label(construction_box, "Выберите свободный участок", 15)
    construction_cost = _label(construction_box, "", 16)
    construction_picker = OptionButton.new()
    construction_picker.custom_minimum_size = Vector2(210, 48)
    construction_picker.item_selected.connect(_on_construction_choice)
    construction_box.add_child(construction_picker)
    construction_buttons = HBoxContainer.new()
    construction_box.add_child(construction_buttons)
    construction_buy = Button.new()
    construction_buy.text = "Купить землю"
    construction_buy.custom_minimum_size = Vector2(105, 48)
    construction_buy.pressed.connect(func() -> void: game._buy_land())
    construction_buttons.add_child(construction_buy)
    construction_confirm = Button.new()
    construction_confirm.text = "Построить"
    construction_confirm.custom_minimum_size = Vector2(105, 48)
    _style_button(construction_confirm, true)
    construction_confirm.pressed.connect(func() -> void: game._confirm_preview())
    construction_buttons.add_child(construction_confirm)
    construction_cancel = Button.new()
    construction_cancel.text = "Отмена"
    construction_cancel.custom_minimum_size = Vector2(90, 48)
    construction_cancel.pressed.connect(func() -> void: game._cancel_preview())
    construction_buttons.add_child(construction_cancel)
    construction_panel.visible = false
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 16)
    top.add_child(header)
    city_text = _label(header, "ГОРОД", 19)
    money_text = _label(header, "Баланс: ...", 18)
    calendar_text = _label(header, "Дата: ...", 16)
    nav = HBoxContainer.new()
    nav.alignment = BoxContainer.ALIGNMENT_CENTER
    nav.add_theme_constant_override("separation", 6)
    bottom.add_child(nav)
    for item in [
        ["Город", _show_city], ["Бизнес", _show_business],
        ["Рынок", _show_market], ["Задания", _show_tasks],
        ["Меню", _show_menu]
    ]:
        var tab := Button.new()
        tab.name = "Tab" + str(item[0])
        tab.text = str(item[0])
        tab.custom_minimum_size = Vector2(96, 52)
        tab.toggle_mode = true
        _style_button(tab, false)
        tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tab.pressed.connect(item[1])
        nav.add_child(tab)
        nav_buttons[str(item[0])] = tab
    camera_home = Button.new()
    camera_home.name = "CameraHome"
    camera_home.text = "⌂"
    camera_home.tooltip_text = "К центру города"
    _style_button(camera_home, false)
    camera_home.custom_minimum_size = Vector2(56, 56)
    safe.add_child(camera_home)
    camera_home.pressed.connect(_center_city)
    construction_toggle = Button.new()
    construction_toggle.name = "PlotHighlight"
    construction_toggle.text = "Участки"
    construction_toggle.custom_minimum_size = Vector2(94, 48)
    _style_button(construction_toggle, false)
    construction_toggle.pressed.connect(_toggle_plot_highlights)
    safe.add_child(construction_toggle)
    menu_backdrop = ColorRect.new()
    menu_backdrop.name = "MenuBackdrop"
    menu_backdrop.color = Color("#07151fc9")
    menu_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
    safe.add_child(menu_backdrop)
    menu_overlay = _panel("MainMenuOverlay")
    menu_scroll = ScrollContainer.new()
    menu_scroll.name = "MenuScroll"
    menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    menu_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    menu_overlay.add_child(menu_scroll)
    var menu_box := VBoxContainer.new()
    menu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    menu_box.add_theme_constant_override("separation", 9)
    menu_scroll.add_child(menu_box)
    var brand := _label(menu_box, "BUSINESS EMPIRE\nONLINE", 32)
    brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var tagline := _label(menu_box, "Управляйте городом. Постройте свою корпорацию.", 16)
    tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    var divider := HSeparator.new()
    menu_box.add_child(divider)
    menu_buttons = VBoxContainer.new()
    menu_buttons.add_theme_constant_override("separation", 10)
    menu_box.add_child(menu_buttons)
    _menu_button("Продолжить игру", _resume)
    _menu_button("В город", _resume)
    _menu_button("Профиль / MMO", _open_profile)
    _menu_button("Настройки", _open_settings)
    _menu_button("Выход", _exit_to_os)
    _update_nav()
    details_text = _label(details, "Нажмите на участок для информации", 15)
    details.visible = false
    get_viewport().size_changed.connect(_layout)
    call_deferred("_layout")

func _panel(n: String) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.name = n
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#102431ef")
    style.border_color = Color("#648b96")
    style.set_border_width_all(1)
    style.set_corner_radius_all(14)
    style.set_content_margin_all(12)
    panel.add_theme_stylebox_override("panel", style)
    safe.add_child(panel)
    return panel

func _label(parent: Node, content: String, font_size: int) -> Label:
    var label := Label.new()
    label.text = content
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", Color("#f1f6ed"))
    label.clip_text = true
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(label)
    return label

func _button(parent: Node, content: String, action: Callable) -> void:
    var button := Button.new()
    button.text = content
    button.custom_minimum_size = Vector2(110, 48)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _style_button(button, false)
    button.pressed.connect(action)
    parent.add_child(button)

func _toggle_plot_highlights() -> void:
    game.show_available_plots = not game.show_available_plots
    construction_toggle.set_pressed_no_signal(game.show_available_plots)
    game.queue_redraw()


func _on_construction_choice(index: int) -> void:
    if index < 0 or index >= construction_picker.item_count:
        return
    var kind := construction_picker.get_item_text(index)
    game._preview_construction(kind)


func update_construction() -> void:
    if game == null or game.selected.x < 0 or menu_open:
        construction_panel.visible = false
        return
    var tile: Vector2i = game.selected
    var built: String = game._building_at(tile)
    var owned: bool = game._owns_plot(tile)
    var free: bool = game.Land.kind_at(game.city_index, tile) == "Свободный участок"
    var already_claimed: bool = game._city_plots().has(game.Land.plot_key(tile))
    construction_panel.visible = built == "" and (owned or free and not already_claimed)
    if not construction_panel.visible:
        return
    construction_title.text = "МОЙ УЧАСТОК" if owned else "СВОБОДНАЯ ЗЕМЛЯ"
    construction_status.text = "Участок %d:%d • %s" % [tile.x, tile.y, "можно строить" if owned else "доступен для покупки"]
    construction_buy.visible = not owned
    construction_picker.visible = owned
    construction_confirm.visible = owned and game.construction_preview != ""
    construction_cancel.visible = construction_confirm.visible
    construction_picker.clear()
    if owned:
        var chosen := -1
        for kind in game.CompanyState.CONSTRUCTION:
            if kind == "Шахта" and not game.Land.has_ore(game.city_index, tile):
                continue
            construction_picker.add_item(str(kind))
            if str(kind) == game.construction_preview:
                chosen = construction_picker.item_count - 1
        if chosen >= 0:
            construction_picker.select(chosen)
        else:
            construction_picker.select(-1)
    var cost: int = game.CompanyState.LAND_PRICE if not owned else int(game.CompanyState.CONSTRUCTION.get(game.construction_preview, 0))
    construction_cost.text = "Цена участка: %d ₽" % cost if not owned else "Стоимость строительства: %d ₽" % cost if game.construction_preview != "" else "Выберите тип здания"
    var wallet: int = int(game.mmo_panel.client.snapshot.get("cash_minor", 0)) / 100 if game._online_land() else game.company.cash
    construction_buy.disabled = not owned and wallet < cost
    construction_confirm.disabled = owned and (cost > wallet or game.construction_preview == "")


func _menu_button(title: String, action: Callable) -> void:
    var b := Button.new()
    b.text = title
    b.custom_minimum_size = Vector2(200, 54)
    _style_button(b, title == "Продолжить игру")
    b.pressed.connect(action)
    menu_buttons.add_child(b)


func _style_button(button: Button, primary: bool) -> void:
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color("#217c84") if primary else Color("#203d4a")
    normal.border_color = Color("#7bb8b5") if primary else Color("#4c727d")
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(10)
    normal.set_content_margin_all(7)
    var hover := normal.duplicate()
    hover.bg_color = Color("#339ba1") if primary else Color("#315967")
    var pressed := normal.duplicate()
    pressed.bg_color = Color("#145d65") if primary else Color("#2d6c79")
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_stylebox_override("hover_pressed", pressed)
    button.add_theme_color_override("font_color", Color("#f4f8f8"))
    button.add_theme_color_override("font_hover_color", Color("#ffffff"))
    button.add_theme_font_size_override("font_size", 16)


func _set_menu_visible(value: bool) -> void:
    menu_open = value
    menu_overlay.visible = value
    menu_backdrop.visible = value


func _update_nav() -> void:
    for key in nav_buttons:
        var b: Button = nav_buttons[key]
        b.set_pressed_no_signal(key == active_tab)
        b.modulate = Color("#ffffff") if key == active_tab else Color("#b4c7d3")


func _close_panels() -> void:
    local_open = false
    mmo_open = false
    for panel in local_panels:
        panel.visible = false
    _set_mmo_visible(false)
    business_panel.visible = false
    construction_panel.visible = false
    if game.tycoon_panel != null and game.tycoon_panel.visible:
        game.tycoon_panel.visible = false


func _show_city() -> void:
    active_tab = "Город"
    _close_panels()
    _update_nav()


func _show_business() -> void:
    active_tab = "Бизнес"
    _close_panels()
    game.tycoon_panel.toggle()
    _update_nav()


func _show_market() -> void:
    active_tab = "Рынок"
    _close_panels()
    if game.mmo_panel.online_active():
        mmo_open = true
        _set_mmo_visible(true)
    else:
        local_open = true
        if local_panels.size() > 1:
            local_panels[1].visible = true
    _update_nav()


func _show_tasks() -> void:
    active_tab = "Задания"
    _close_panels()
    details.visible = true
    details_text.text = "Задания появятся после подключения системы прогрессии."
    _update_nav()


func _show_menu() -> void:
    active_tab = "Меню"
    _close_panels()
    _set_menu_visible(true)
    _update_nav()


func _resume() -> void:
    _set_menu_visible(false)
    active_tab = "Город"
    _update_nav()


func _open_profile() -> void:
    _resume()
    mmo_open = true
    _set_mmo_visible(true)


func _open_settings() -> void:
    _resume()
    _toggle_local()


func _exit_to_os() -> void:
    get_tree().quit()


func _center_city() -> void:
    game._center_city()


func attach_legacy() -> void:
    var local_safe = game.find_child("MobileSafeArea", true, false)
    if local_safe != null:
        for n in ["CompanyPanel", "EconomyPanel"]:
            var panel: Control = local_safe.get_node(n)
            local_panels.append(panel)
            panel.visible = false
    _set_mmo_visible(false)
    update_values()
    _set_menu_visible(true)

func _cycle_quality() -> void:
    visual_quality = (visual_quality + 1) % 3
    game.performance.auto_enabled = false
    game.performance.apply_quality(visual_quality)
    game.message_label.text = ["Детали: экономия", "Детали: баланс", "Детали: максимум"][visual_quality]

func _toggle_auto() -> void:
    game.performance.toggle_auto()
    game.message_label.text = "Авто FPS: включено" if game.performance.auto_enabled else "Авто FPS: выключено"

func _toggle_business() -> void:
    business_panel.visible = not business_panel.visible
    update_business()

func update_business() -> void:
    if game == null or game.selected.x < 0:
        business_panel.visible = false
        return
    var building: String = game._building_at(game.selected)
    if building == "":
        business_text.text = "Выберите построенное предприятие"
        return
    business_title.text = building.to_upper()
    var label := "Участок %d:%d" % [game.selected.x, game.selected.y]
    if game.mmo_panel.online_active():
        var kind := str(game.Land.SERVER_KINDS.get(building, ""))
        var fields: Dictionary = game.SmartCity076.display_metrics(game.mmo_panel.client.snapshot, kind)
        if fields.is_empty():
            label += "\nДанные производства не предоставлены сервером"
        else:
            for key in fields:
                label += "\n%s: %s" % [key, str(fields[key])]
        var land: Dictionary = game._city_plots().get(game.Land.plot_key(game.selected), {})
        var phase: String = game.SmartCity076.visual_construction_phase(land)
        if phase != "unknown":
            label += "\nСтроительство: " + phase
    else:
        label += "\nЛокальная демонстрация. Финансы в разделе Рынок"
    business_text.text = label

func _toggle_local() -> void:
    local_open = not local_open
    for panel in local_panels:
        panel.visible = local_open
    if local_open:
        mmo_open = false
        _set_mmo_visible(false)

func _toggle_mmo() -> void:
    mmo_open = not mmo_open
    _set_mmo_visible(mmo_open)
    if mmo_open:
        local_open = false
        for panel in local_panels:
            panel.visible = false

func _set_mmo_visible(value: bool) -> void:
    var panel = game.find_child("MMOPanel", true, false)
    if panel != null:
        panel.visible = value

func update_values() -> void:
    if game == null or game.company == null:
        return
    city_text.text = "▥ " + str(game.city_label.text).replace("Город: ", "").replace(" (демонстрация)", "")
    money_text.text = "Баланс: %d ₽" % int(game.mmo_panel.client.snapshot.get("cash_minor", 0) / 100) if game.mmo_panel.online_active() else "Локально: %d ₽" % game.company.cash
    calendar_text.text = "MMO • день %d" % int(game.mmo_panel.client.snapshot.get("game_day", 0)) if game.mmo_panel.online_active() else str(game.Calendar.label(game.company.day)) + " • 1 мес. / 24 ч"
    if game.selected.x >= 0:
        var building: String = game._building_at(game.selected)
        if building != "" and not menu_open:
            business_panel.visible = true
            update_business()
            details.visible = false
        else:
            business_panel.visible = false
            details.visible = not menu_open
            details_text.text = "Участок %d:%d • %s" % [game.selected.x, game.selected.y, game.info.text]
    else:
        business_panel.visible = false
        details.visible = false
    update_construction()
    _layout()

func _layout() -> void:
    if safe == null:
        return
    safe.refresh()
    var w: float = safe.size.x
    var h: float = safe.size.y
    top.position = Vector2.ZERO
    compact_layout = w < 850 or h < 430
    top.size = Vector2(w, 54 if compact_layout else 58)
    nav.add_theme_constant_override("separation", 2 if compact_layout else 6)
    for key in nav_buttons:
        var tab: Button = nav_buttons[key]
        tab.custom_minimum_size = Vector2(UI_MIN_TOUCH, 48 if compact_layout else 52)
        tab.add_theme_font_size_override("font_size", 13 if compact_layout else 16)
    city_text.add_theme_font_size_override("font_size", 14 if compact_layout else 19)
    money_text.add_theme_font_size_override("font_size", 14 if compact_layout else 18)
    calendar_text.add_theme_font_size_override("font_size", 12 if compact_layout else 16)
    var bottom_height := 58.0 if compact_layout else 76.0
    bottom.position = Vector2(0, maxf(0, h - bottom_height))
    bottom.size = Vector2(w, bottom_height)
    camera_home.position = Vector2(0, maxf(62, h - bottom_height - 62))
    camera_home.size = Vector2(52, 52)
    construction_toggle.position = Vector2(58, maxf(62, h - bottom_height - 60))
    construction_toggle.size = Vector2(94, 48)
    menu_backdrop.position = Vector2.ZERO
    menu_backdrop.size = Vector2(w, h)
    var menu_width := minf(470, w * 0.78)
    var menu_height := minf(490, h * 0.84)
    menu_overlay.position = Vector2((w - menu_width) * 0.5, (h - menu_height) * 0.5)
    menu_overlay.size = Vector2(menu_width, menu_height)
    var detail_width := minf(460, w * 0.60)
    details.position = Vector2((w - detail_width) * 0.5, 65)
    details.size = Vector2(detail_width, 54)
    var card_width := minf(360, w * 0.42)
    business_panel.position = Vector2(maxf(0, w - card_width), 66)
    business_panel.size = Vector2(card_width, minf(240, h * 0.47))
    var construction_width := minf(370, w * 0.48)
    construction_panel.position = Vector2(maxf(0, w - construction_width), 66)
    construction_panel.size = Vector2(construction_width, minf(265, maxf(120, h - bottom_height - 78)))