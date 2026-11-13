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
    business_text = _label(business_panel, "Выберите предприятие", 15)
    business_panel.visible = false
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 16)
    top.add_child(header)
    city_text = _label(header, "ГОРОД", 19)
    money_text = _label(header, "Баланс: ...", 18)
    calendar_text = _label(header, "Дата: ...", 16)
    var nav := HBoxContainer.new()
    nav.alignment = BoxContainer.ALIGNMENT_CENTER
    nav.add_theme_constant_override("separation", 8)
    bottom.add_child(nav)
    _button(nav, "Участки", func(): game._find_free_plot())
    _button(nav, "Постройки", _toggle_local)
    _button(nav, "Рынок", _toggle_local)
    _button(nav, "Города", func(): game._load_city(game.city_index + 1))
    _button(nav, "MMO", _toggle_mmo)
    _button(nav, "Меню", _toggle_local)
    _button(nav, "Детали", _cycle_quality)
    _button(nav, "Бизнес", _toggle_business)
    _button(nav, "Авто FPS", _toggle_auto)
    details_text = _label(details, "Нажмите на участок для информации", 15)
    details.visible = false
    get_viewport().size_changed.connect(_layout)
    call_deferred("_layout")

func _panel(n: String) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.name = n
    var style := StyleBoxFlat.new()
    style.bg_color = Color("#13232de8")
    style.border_color = Color("#557d80")
    style.set_border_width_all(1)
    style.set_corner_radius_all(12)
    style.set_content_margin_all(10)
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
    button.pressed.connect(action)
    parent.add_child(button)

func attach_legacy() -> void:
    var local_safe = game.find_child("MobileSafeArea", true, false)
    if local_safe != null:
        for n in ["CompanyPanel", "EconomyPanel"]:
            var panel: Control = local_safe.get_node(n)
            local_panels.append(panel)
            panel.visible = false
    _set_mmo_visible(false)
    update_values()

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
    var label := "Предприятие: %s" % building
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
    city_text.text = "🏙 " + str(game.city_label.text).replace("Город: ", "").replace(" (демонстрация)", "")
    money_text.text = "Баланс: %d ₽" % int(game.mmo_panel.client.snapshot.get("cash_minor", 0) / 100) if game.mmo_panel.online_active() else "Локально: %d ₽" % game.company.cash
    calendar_text.text = "MMO • день %d" % int(game.mmo_panel.client.snapshot.get("game_day", 0)) if game.mmo_panel.online_active() else str(game.Calendar.label(game.company.day)) + " • 1 мес. / 24 ч"
    if game.selected.x >= 0:
        details.visible = true
        details_text.text = "Участок %d:%d • %s" % [game.selected.x, game.selected.y, game.info.text]
    else:
        details.visible = false
    _layout()

func _layout() -> void:
    if safe == null:
        return
    safe.refresh()
    var w: float = safe.size.x
    var h: float = safe.size.y
    top.position = Vector2.ZERO
    top.size = Vector2(w, 54)
    bottom.position = Vector2(0, maxf(0, h - 70))
    bottom.size = Vector2(w, 70)
    var detail_width := minf(460, w * 0.40)
    details.position = Vector2((w - detail_width) * 0.5, 65)
    details.size = Vector2(detail_width, 54)
    business_panel.position = Vector2(maxf(0, w - 365), 66)
    business_panel.size = Vector2(minf(365, w), minf(180, h * 0.32))