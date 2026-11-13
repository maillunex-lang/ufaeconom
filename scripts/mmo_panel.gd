extends CanvasLayer
class_name BusinessMMOPanel

## The multiplayer economy is a separate server-owned balance.
## Do not present local CompanyState as synchronized MMO inventory.
const Client = preload("res://scripts/mmo_client.gd")
var client
var status_label: Label
var summary_label: Label
var server_input: LineEdit
var user_input: LineEdit
var password_input: LineEdit

func _ready() -> void:
	client = Client.new()
	add_child(client)
	client.login_ready.connect(_on_login)
	client.snapshot_ready.connect(_on_snapshot)
	client.command_ready.connect(_on_command)
	client.request_failed.connect(_on_error)
	client.disconnected.connect(_on_logout)
	var panel := PanelContainer.new()
	panel.position = Vector2(810, 385)
	panel.custom_minimum_size = Vector2(455, 290)
	add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)
	var heading := Label.new()
	heading.text = "🌐 MMO • СЕРВЕРНАЯ ЭКОНОМИКА 24/7"
	content.add_child(heading)
	server_input = LineEdit.new()
	server_input.placeholder_text = "HTTPS-адрес игрового сервера"
	content.add_child(server_input)
	user_input = LineEdit.new()
	user_input.placeholder_text = "Логин серверной компании"
	content.add_child(user_input)
	password_input = LineEdit.new()
	password_input.placeholder_text = "Пароль"
	password_input.secret = true
	content.add_child(password_input)
	var access := HBoxContainer.new()
	content.add_child(access)
	var enter := Button.new()
	enter.text = "Войти"
	enter.pressed.connect(_login)
	access.add_child(enter)
	var refresh := Button.new()
	refresh.text = "Обновить"
	refresh.pressed.connect(func() -> void: client.fetch_snapshot())
	access.add_child(refresh)
	var leave := Button.new()
	leave.text = "Выйти"
	leave.pressed.connect(func() -> void: client.disconnect_client())
	access.add_child(leave)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Не подключено. Локальная карта работает отдельно."
	content.add_child(status_label)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(summary_label)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	var price := Button.new()
	price.text = "Цена хлеба −5%"
	price.pressed.connect(_reduce_price)
	actions.add_child(price)
	var cargo := Button.new()
	cargo.text = "🚚 Отправить 5 хлеба"
	cargo.pressed.connect(_send_cargo)
	actions.add_child(cargo)

func online_active() -> bool:
	return client != null and client.connected()

func _login() -> void:
	var secret := password_input.text
	password_input.clear()
	client.login_to(server_input.text, user_input.text, secret)

func _on_login(actor: String) -> void:
	status_label.text = "Вход выполнен: %s. Загружаю данные…" % actor

func _on_snapshot(data: Dictionary) -> void:
	var facilities: Dictionary = data.get("facilities", {})
	var stats: Dictionary = data.get("company_metrics", {})
	var shipments: Array = data.get("shipments", [])
	status_label.text = "Игрок: %s | день %d | тик %d | ревизия %d" % [
		str(data.get("company", "")), int(data.get("game_day", 0)),
		int(data.get("tick", 0)), int(data.get("revision", 0))]
	summary_label.text = (
		"Капитал: %d ₽ | предприятий: %d | грузов: %d\n" % [
			int(int(data.get("cash_minor", 0)) / 100),
			facilities.size(), shipments.size()] +
		"Выручка: %d ₽ | прибыль: %+d ₽ | логистика: %d ₽" % [
			int(int(stats.get("revenue", 0)) / 100),
			int(int(stats.get("profit", 0)) / 100),
			int(int(stats.get("freight", 0)) / 100)]
	)

func _on_command(response: Dictionary) -> void:
	status_label.text = "Команда принята. Ревизия: %d" % int(response.get("revision", -1))

func _on_error(message: String) -> void:
	status_label.text = "MMO: " + message

func _on_logout() -> void:
	status_label.text = "Отключено. Серверная экономика продолжает работу."
	summary_label.text = ""

func _reduce_price() -> void:
	if not online_active():
		_on_error("Сначала войдите на сервер")
		return
	var facilities: Dictionary = client.snapshot.get("facilities", {})
	for id in facilities:
		var facility: Dictionary = facilities[id]
		if str(facility.get("kind", "")) == "shop":
			var prices: Dictionary = facility.get("prices", {})
			var old: int = int(prices.get("bread", 15500))
			client.send_command("facility.set_price", {
				"facility_id": str(id), "good": "bread",
				"price_minor": maxi(10850, int(old * 95 / 100))})
			return
	_on_error("У компании нет магазина")

func _send_cargo() -> void:
	if not online_active():
		_on_error("Сначала войдите на сервер")
		return
	var facilities: Dictionary = client.snapshot.get("facilities", {})
	for from_id in facilities:
		var source: Dictionary = facilities[from_id]
		var stock: Dictionary = source.get("stock", {})
		if int(stock.get("bread", 0)) < 5:
			continue
		for to_id in facilities:
			var dest: Dictionary = facilities[to_id]
			if str(from_id) != str(to_id) and str(source.get("city", "")) != str(dest.get("city", "")):
				client.send_command("shipment.create", {
					"facility_id": str(from_id), "destination_id": str(to_id),
					"good": "bread", "quantity": 5})
				return
	_on_error("Нужны два предприятия в разных городах и хотя бы 5 ед. хлеба")
