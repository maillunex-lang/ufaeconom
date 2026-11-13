extends SceneTree
const SafeArea = preload("res://scripts/mobile_safe_area.gd")
var failures := 0

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
		push_error(detail)

func _initialize() -> void:
	check(ProjectSettings.get_setting("display/window/handheld/orientation") == 4, "Android must use sensor landscape")
	check(ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "Viewport must expand without letterboxing")
	# Non-unit scaling and nonzero window origin: physical pixels cannot be used as UI offsets.
	var mapped: Rect2 = SafeArea.map_safe_rect(Rect2(0, 0, 1600, 720),
		Rect2(196, 50, 3104, 1400), Vector2(100, 50), Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2.ZERO))
	check(mapped.is_equal_approx(Rect2(48, 0, 1552, 700)), "Safe rectangle mapping/scale is wrong")
	check(SafeArea.map_safe_rect(Rect2(0, 0, 1280, 720), Rect2(), Vector2.ZERO, Transform2D.IDENTITY) == Rect2(0, 0, 1280, 720), "Empty platform safe area must fall back")
	call_deferred("_run_layouts")

func _run_layouts() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.company.save_path = "user://mobile_layout_test.json"
	game.company.legacy_save_path = "user://mobile_layout_missing_legacy.json"
	game.company.reset()
	root.add_child(game)
	await process_frame
	var safe = game.find_child("MobileSafeArea", true, false)
	var mmo_safe = game.find_child("MMOSafeArea", true, false)
	check(safe != null and mmo_safe != null, "All UI layers must use safe areas")
	for physical in [Vector2i(1280, 720), Vector2i(2160, 1080), Vector2i(2340, 1080), Vector2i(2400, 1080), Vector2i(1440, 1080)]:
		root.size = physical
		await process_frame
		await process_frame
		var logical: Vector2 = root.get_visible_rect().size
		for notch_right in [false, true]:
			var notch := 48.0
			var usable := Rect2(notch if not notch_right else 0.0, 0.0, logical.x - notch, logical.y - 24.0)
			for area in [safe, mmo_safe]:
				area.test_safe_rect = usable
				area.refresh()
			await process_frame
			await process_frame
			for area in [safe, mmo_safe]:
				for child in area.get_children():
					if child is PanelContainer:
						var rect: Rect2 = child.get_global_rect()
						check(usable.encloses(rect), "Panel outside safe area %s %s %s" % [physical, child.name, rect])
			var economy: Control = safe.get_node("EconomyPanel")
			var online: Control = mmo_safe.get_node("MMOPanel")
			check(not economy.get_global_rect().intersects(online.get_global_rect()), "Economy/MMO panels overlap")
		print("MOBILE_LAYOUT_OK physical=", physical, " logical=", logical, " notch=left/right")
	# Long localized content must remain in a vertically scrollable panel.
	game.economy_label.text = "Очень длинное описание финансов и состояния предприятия. ".repeat(120)
	await process_frame
	await process_frame
	var scroll: ScrollContainer = safe.get_node("EconomyPanel").get_child(0)
	check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "Long Russian text must be scrollable")
	game.queue_free()
	await process_frame
	if failures == 0:
		print("MOBILE_LAYOUT_TESTS_PASSED")
	quit(1 if failures > 0 else 0)
