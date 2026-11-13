extends Node
class_name BusinessMMOClient

## Android client adapter for the authoritative economy beta.
## Credentials/token exist only in memory; all prices, cash, inventory and ticks
## come from the server. Local CompanyState remains a separate offline demo.
signal login_ready(actor: String)
signal snapshot_ready(data: Dictionary)
signal command_ready(data: Dictionary)
signal request_failed(message: String)
signal disconnected()

var server_url: String = ""
var token: String = ""
var actor: String = ""
var snapshot: Dictionary = {}
var _http: HTTPRequest
var _poll_timer: Timer
var _busy := false
var _operation := ""

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_response)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 15.0
	_poll_timer.timeout.connect(_poll)
	add_child(_poll_timer)
	_poll_timer.start()

static func allowed_server_url(value: String) -> bool:
	var url := value.strip_edges().trim_suffix("/")
	if url.contains("@") or url.contains("#") or url.contains("?"):
		return false
	if url.begins_with("https://") and url.length() > 12:
		return true
	# Loopback-only development. Mobile clients MUST use HTTPS.
	if not OS.has_feature("mobile"):
		return url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")
	return false

func login_to(server: String, username: String, password: String) -> void:
	var clean := server.strip_edges().trim_suffix("/")
	if not allowed_server_url(clean):
		request_failed.emit("Нужен HTTPS-адрес MMO-сервера; HTTP доступен только на локальном ПК")
		return
	if username.strip_edges().is_empty() or password.is_empty():
		request_failed.emit("Укажите логин и пароль серверной компании")
		return
	server_url = clean
	var payload := JSON.stringify({"username": username, "password": password})
	_start("login", "/v1/login", payload)

func connected() -> bool:
	return not token.is_empty()

func fetch_snapshot() -> void:
	if connected():
		_start("snapshot", "/v1/snapshot")

func send_command(kind: String, fields: Dictionary) -> void:
	if not connected():
		request_failed.emit("Сначала войдите на MMO-сервер")
		return
	if snapshot.is_empty():
		request_failed.emit("Сначала дождитесь снимка состояния компании")
		return
	var payload: Dictionary = fields.duplicate(true)
	payload["type"] = kind
	payload["command_id"] = "c" + Crypto.new().generate_random_bytes(16).hex_encode()
	payload["expected_revision"] = int(snapshot.get("revision", -1))
	_start("command", "/v1/command", JSON.stringify(payload))

func disconnect_client() -> void:
	token = ""
	actor = ""
	snapshot.clear()
	disconnected.emit()

func _poll() -> void:
	if connected() and not _busy:
		fetch_snapshot()

func _start(operation: String, endpoint: String, body: String = "") -> void:
	if _http == null or _busy:
		request_failed.emit("Предыдущий запрос ещё выполняется")
		return
	_busy = true
	_operation = operation
	var headers := PackedStringArray(["Accept: application/json"])
	if operation != "login":
		headers.append("Authorization: Bearer " + token)
	var method := HTTPClient.METHOD_GET
	if not body.is_empty():
		headers.append("Content-Type: application/json")
		method = HTTPClient.METHOD_POST
	var err := _http.request(server_url + endpoint, headers, method, body)
	if err != OK:
		_busy = false
		request_failed.emit("Не удалось начать сетевой запрос (%d)" % err)

func _on_response(result: int, response_code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
	var operation := _operation
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("Сервер недоступен (код сети %d)" % result)
		return
	var decoded: Variant = JSON.parse_string(data.get_string_from_utf8())
	if not (decoded is Dictionary):
		request_failed.emit("Сервер вернул некорректный JSON")
		return
	var response: Dictionary = decoded
	if response_code != 200:
		request_failed.emit("Сервер %d: %s" % [response_code, str(response.get("error", "ошибка запроса"))])
		if response_code == 409 and connected():
			call_deferred("fetch_snapshot")
		return
	match operation:
		"login":
			token = str(response.get("token", ""))
			actor = str(response.get("actor", ""))
			if token.is_empty() or actor.is_empty():
				request_failed.emit("Неверный ответ авторизации")
				return
			login_ready.emit(actor)
			call_deferred("fetch_snapshot")
		"snapshot":
			snapshot = response
			snapshot_ready.emit(snapshot)
		"command":
			command_ready.emit(response)
			call_deferred("fetch_snapshot")
