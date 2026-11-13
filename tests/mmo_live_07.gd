extends SceneTree

const Client = preload("res://scripts/mmo_client.gd")
var client
var stage := "init"
var start_msec := 0
var desired_price := 0

func _initialize() -> void:
	start_msec = Time.get_ticks_msec()
	call_deferred("_run")

func _run() -> void:
	var url := OS.get_environment("BE_TEST_URL")
	var username := OS.get_environment("BE_TEST_USER")
	var password := OS.get_environment("BE_TEST_PASSWORD")
	if url.is_empty() or username.is_empty() or password.is_empty():
		print("MMO_LIVE_07_SKIPPED missing test-only environment")
		quit(2)
		return
	client = Client.new()
	get_root().add_child(client)
	client.login_ready.connect(_on_login)
	client.snapshot_ready.connect(_on_snapshot)
	client.command_ready.connect(_on_command)
	client.request_failed.connect(_on_failure)
	stage = "login"
	client.login_to(url, username, password)

func _on_login(actor: String) -> void:
	if stage != "login" or actor != "player":
		_fail("unexpected actor or phase")
		return
	stage = "initial_snapshot"

func _on_snapshot(data: Dictionary) -> void:
	if stage == "initial_snapshot":
		if str(data.get("company", "")) != "player":
			_fail("wrong company")
			return
		if not data.get("facilities", {}).has("player-shop"):
			_fail("missing company-owned shop")
			return
		var shop: Dictionary = data["facilities"]["player-shop"]
		desired_price = int(shop["prices"]["bread"]) - 100
		stage = "command"
		client.send_command("facility.set_price", {
			"facility_id": "player-shop", "good": "bread",
			"price_minor": desired_price})
	elif stage == "after_command":
		var shops: Dictionary = data.get("facilities", {})
		if int(shops["player-shop"]["prices"]["bread"]) != desired_price:
			_fail("server did not apply offer change")
			return
		print("MMO_LIVE_07_TESTS_PASSED auth=1 snapshot=1 command=1 replay_snapshot=1")
		quit(0)

func _on_command(result: Dictionary) -> void:
	if stage != "command" or not bool(result.get("ok", false)):
		_fail("server rejected valid command")
		return
	stage = "after_command"

func _on_failure(message: String) -> void:
	_fail(message)

func _fail(reason: String) -> void:
	push_error("MMO_LIVE_07_FAILED: " + reason)
	quit(1)

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - start_msec > 15000:
		_fail("timeout")
	return false
