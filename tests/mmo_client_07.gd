extends SceneTree

const Client = preload("res://scripts/mmo_client.gd")
const MainScene = preload("res://scenes/main.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(Client.allowed_server_url("https://game.example.test"))
	assert(not Client.allowed_server_url("http://public.example.test"))
	assert(not Client.allowed_server_url("https://user:pass@game.example.test"))
	var scene: Node2D = MainScene.instantiate()
	var company: RefCounted = scene.get("company")
	company.save_path = "user://mmo_07_offline_qa.json"
	company.legacy_save_path = "user://mmo_07_offline_qa_legacy.json"
	company.reset()
	get_root().add_child(scene)
	await process_frame
	var panel = scene.get("mmo_panel")
	assert(panel != null)
	assert(panel.client != null)
	assert(not panel.online_active())
	assert(panel.status_label.text.contains("Локальная"))
	assert(scene.get("day_timer") != null)
	assert(scene.get("money_label") != null)
	assert(scene.get("economy_label") != null)
	scene.queue_free()
	print("MMO_CLIENT_07_TESTS_PASSED ui=1 no_hardcoded_token=1 local_demo=1")
	quit(0)
