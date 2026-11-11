class_name PlatformAdapter
extends RefCounted
# UI-001: narrow platform boundary for the desktop overlay. GUI-only APIs stay out of FishingSession.

const OVERLAY_SIZE := Vector2i(220, 160)


func configure_window(window: Window) -> Dictionary:
	if window == null:
		return {"ok": false, "code": "NULL_WINDOW"}
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "code": "HEADLESS"}
	_set_if_supported(window, "transparent", true)
	_set_if_supported(window, "transparent_bg", true)
	_set_if_supported(window, "borderless", true)
	_set_if_supported(window, "always_on_top", true)
	_set_if_supported(window, "resizable", false)
	_set_if_supported(window, "mouse_passthrough", false)
	window.size = OVERLAY_SIZE
	return {"ok": true, "code": "", "display_server": DisplayServer.get_name(),
		"native_drag": native_drag_supported(),
		"passthrough_polygon": has_property(window, "mouse_passthrough_polygon"),
		"transparent": _property_true(window, "transparent"),
		"borderless": _property_true(window, "borderless"),
		"always_on_top": _property_true(window, "always_on_top")}


func native_drag_supported() -> bool:
	return ClassDB.class_has_method("DisplayServer", "window_start_drag")


func start_native_drag(window: Window) -> bool:
	if window == null or not native_drag_supported():
		return false
	var window_id := 0
	if ClassDB.class_has_method("Window", "get_window_id"):
		window_id = int(window.call("get_window_id"))
	DisplayServer.window_start_drag(window_id)
	return true


func mouse_position() -> Vector2i:
	if ClassDB.class_has_method("DisplayServer", "mouse_get_position"):
		return DisplayServer.mouse_get_position()
	return Vector2i(-1, -1)


func left_mouse_down() -> bool:
	return (Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT) != 0


func safe_area() -> Rect2i:
	if ClassDB.class_has_method("DisplayServer", "get_display_safe_area"):
		return DisplayServer.get_display_safe_area()
	return Rect2i(Vector2i.ZERO, OVERLAY_SIZE)


func current_display_hint() -> Variant:
	if ClassDB.class_has_method("DisplayServer", "window_get_current_screen"):
		var index := int(DisplayServer.window_get_current_screen())
		return index if index >= 0 else null
	return null


func apply_mouse_regions(window: Window, rects: Array) -> bool:
	if window == null:
		return false
	_set_if_supported(window, "mouse_passthrough", false)
	if not has_property(window, "mouse_passthrough_polygon"):
		return false
	var bounds := Rect2()
	var have_bounds := false
	for value in rects:
		if not (value is Rect2) or value.size.x <= 0.0 or value.size.y <= 0.0:
			continue
		bounds = value if not have_bounds else bounds.merge(value)
		have_bounds = true
	if not have_bounds:
		_set_if_supported(window, "mouse_passthrough", true)
		window.set("mouse_passthrough_polygon", PackedVector2Array())
		return true
	var end := bounds.end
	# Keep the native hit-region winding consistent on macOS. The forward winding
	# caused the transparent overlay to pass boat clicks through on Retina displays.
	var polygon := PackedVector2Array([
		bounds.position, Vector2(bounds.position.x, end.y), end, Vector2(end.x, bounds.position.y),
	])
	window.set("mouse_passthrough_polygon", polygon)
	return true


func clamp_window_position(position: Vector2i, window_size: Vector2i) -> Vector2i:
	var area := safe_area()
	if area.size.x < 1 or area.size.y < 1:
		return Vector2i(maxi(position.x, 0), maxi(position.y, 0))
	var max_x := maxi(area.position.x, area.position.x + area.size.x - window_size.x)
	var max_y := maxi(area.position.y, area.position.y + area.size.y - window_size.y)
	return Vector2i(
		clampi(position.x, maxi(0, area.position.x), maxi(maxi(0, area.position.x), max_x)),
		clampi(position.y, maxi(0, area.position.y), maxi(maxi(0, area.position.y), max_y)),
	)


static func has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for descriptor in object.get_property_list():
		if String(descriptor.get("name", "")) == property_name:
			return true
	return false


static func _set_if_supported(object: Object, property_name: String, value: Variant) -> bool:
	if not has_property(object, property_name):
		return false
	object.set(property_name, value)
	return true


static func _property_true(object: Object, property_name: String) -> bool:
	return has_property(object, property_name) and bool(object.get(property_name))
