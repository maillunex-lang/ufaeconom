extends Control
## UI-only safe area. The world/camera still fills the entire viewport.
## DisplayServer reports physical screen pixels; Controls use stretched canvas units.
var test_safe_rect := Rect2()
var _poll_elapsed := 0.0
var _panels: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(refresh)
	refresh()

func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed >= 0.25:
		_poll_elapsed = 0.0
		refresh() # Rotation may change the notch side without changing window size.

static func map_safe_rect(view: Rect2, safe_screen: Rect2, window_position: Vector2, viewport_to_window: Transform2D) -> Rect2:
	if safe_screen.size.x <= 0.0 or safe_screen.size.y <= 0.0:
		return view
	var inverse := viewport_to_window.affine_inverse()
	var local_safe := Rect2(safe_screen.position - window_position, safe_screen.size)
	var mapped: Rect2 = inverse * local_safe
	var clipped := view.intersection(mapped)
	return clipped if clipped.has_area() else view

func refresh() -> void:
	var view := get_viewport_rect()
	var usable := view
	if test_safe_rect.has_area():
		usable = view.intersection(test_safe_rect)
	elif OS.has_feature("android") or OS.has_feature("ios"):
		usable = map_safe_rect(view, Rect2(DisplayServer.get_display_safe_area()),
			Vector2(DisplayServer.window_get_position()), get_viewport().get_screen_transform())
	# Round inward: controls must never cross back into a physical cutout.
	var start := usable.position.ceil() + Vector2(16, 16)
	var finish := usable.end.floor() - Vector2(16, 16)
	position = start
	size = (finish - start).max(Vector2.ZERO)
	for item in _panels:
		var panel: Control = item["panel"]
		var right: bool = item["right"]
		var lower: bool = item["lower"]
		var height_limit: float = item["height"]
		var width := minf(float(item["width"]), size.x * 0.46)
		var top := size.y * 0.53 + 8.0 if lower else 0.0
		var available := size.y - top if lower else size.y * 0.53 - 8.0
		if not right:
			available = size.y
		panel.position = Vector2(size.x - width if right else 0.0, top)
		var content: Control = item["content"]
		var needed := maxf(96.0, content.get_combined_minimum_size().y + 8.0)
		panel.size = Vector2(width, minf(needed, minf(height_limit, maxf(0.0, available))))

func add_panel(panel_name: String, panel_width: float, max_height: float, right: bool, lower: bool = false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_panels.append({"panel": panel, "width": panel_width, "height": max_height, "right": right, "lower": lower, "content": content})
	refresh()
	return content
