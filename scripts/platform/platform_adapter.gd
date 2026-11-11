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
	var regions: Array[Rect2] = []
	for value in rects:
		if not (value is Rect2) or value.size.x <= 0.0 or value.size.y <= 0.0:
			continue
		regions.append(value)
	if regions.is_empty():
		_set_fully_passthrough(window)
		return true

	var polygon := _rect_polygon(regions[0])
	for region_index in range(1, regions.size()):
		var region_polygon := _rect_polygon(regions[region_index])
		var merged := Geometry2D.merge_polygons(polygon, region_polygon)
		if merged.size() != 1:
			var nearest_index := 0
			var nearest_distance := _rect_gap_distance_squared(regions[0], regions[region_index])
			for prior_index in range(1, region_index):
				var distance := _rect_gap_distance_squared(regions[prior_index], regions[region_index])
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_index = prior_index
			for connector in _connector_rects(regions[nearest_index], regions[region_index]):
				var bridged := Geometry2D.merge_polygons(polygon, _rect_polygon(connector))
				if bridged.size() != 1:
					push_warning("Could not join desktop overlay mouse regions; making the window fully pass through")
					_set_fully_passthrough(window)
					return false
				polygon = bridged[0]
			merged = Geometry2D.merge_polygons(polygon, region_polygon)
			if merged.size() != 1:
				push_warning("Could not merge desktop overlay mouse regions; making the window fully pass through")
				_set_fully_passthrough(window)
				return false
		polygon = merged[0]

	# Keep the native hit-region winding consistent on macOS. Geometry2D's union
	# winding can differ from the polygon that successfully routed boat clicks.
	if _signed_area(polygon) > 0.0:
		var reversed := PackedVector2Array()
		for point_index in range(polygon.size() - 1, -1, -1):
			reversed.append(polygon[point_index])
		polygon = reversed
	if absf(_signed_area(polygon)) < 0.001:
		push_warning("Desktop overlay mouse region is degenerate; making the window fully pass through")
		_set_fully_passthrough(window)
		return false
	window.set("mouse_passthrough_polygon", polygon)
	return true


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	var end := rect.end
	return PackedVector2Array([
		rect.position, Vector2(end.x, rect.position.y), end, Vector2(rect.position.x, end.y),
	])


func _rect_gap_distance_squared(first: Rect2, second: Rect2) -> float:
	var gap_x := maxf(maxf(first.position.x - second.end.x, second.position.x - first.end.x), 0.0)
	var gap_y := maxf(maxf(first.position.y - second.end.y, second.position.y - first.end.y), 0.0)
	return gap_x * gap_x + gap_y * gap_y


func _connector_rects(first: Rect2, second: Rect2) -> Array[Rect2]:
	var overlap_left := maxf(first.position.x, second.position.x)
	var overlap_right := minf(first.end.x, second.end.x)
	var overlap_top := maxf(first.position.y, second.position.y)
	var overlap_bottom := minf(first.end.y, second.end.y)
	if overlap_right > overlap_left:
		if first.end.y < second.position.y:
			return [Rect2(Vector2(overlap_left, first.end.y),
				Vector2(overlap_right - overlap_left, second.position.y - first.end.y))]
		if second.end.y < first.position.y:
			return [Rect2(Vector2(overlap_left, second.end.y),
				Vector2(overlap_right - overlap_left, first.position.y - second.end.y))]
	if overlap_bottom > overlap_top:
		if first.end.x < second.position.x:
			return [Rect2(Vector2(first.end.x, overlap_top),
				Vector2(second.position.x - first.end.x, overlap_bottom - overlap_top))]
		if second.end.x < first.position.x:
			return [Rect2(Vector2(second.end.x, overlap_top),
				Vector2(first.position.x - second.end.x, overlap_bottom - overlap_top))]

	# Diagonally separated rectangles need a minimal one-pixel L-shaped bridge.
	var first_center := first.get_center()
	var second_center := second.get_center()
	var from_x := first.end.x if first_center.x < second_center.x else first.position.x
	var to_x := second.position.x if first_center.x < second_center.x else second.end.x
	var from_y := first.end.y if first_center.y < second_center.y else first.position.y
	var to_y := second.position.y if first_center.y < second_center.y else second.end.y
	var horizontal := Rect2(Vector2(minf(from_x, to_x) - 0.5, from_y - 0.5),
		Vector2(absf(to_x - from_x) + 1.0, 1.0))
	var vertical := Rect2(Vector2(to_x - 0.5, minf(from_y, to_y) - 0.5),
		Vector2(1.0, absf(to_y - from_y) + 1.0))
	return [horizontal, vertical]


func _signed_area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for point_index in range(polygon.size()):
		var current := polygon[point_index]
		var next := polygon[(point_index + 1) % polygon.size()]
		twice_area += current.x * next.y - next.x * current.y
	return twice_area * 0.5


func _set_fully_passthrough(window: Window) -> void:
	_set_if_supported(window, "mouse_passthrough", true)
	window.set("mouse_passthrough_polygon", PackedVector2Array())


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
