class_name DesktopWindow
extends RefCounted
# Owns the window interaction policy; game rules and persisted window state remain in their services.

signal boat_clicked
signal visibility_changed(is_visible: bool)

const DRAG_THRESHOLD_PX := 6.0
const FPS_VISIBLE := 30
const FPS_DRAG := 60

var _window: Window
var _platform: PlatformAdapter
var _session: FishingSession
var _drag_pending := false
var _native_drag_active := false
var _manual_drag_active := false
var _drag_start_cursor := Vector2i.ZERO
var _drag_start_window := Vector2i.ZERO


func initialize(window: Window, platform: PlatformAdapter, session: FishingSession) -> Dictionary:
	if window == null or platform == null or session == null:
		return {"ok": false, "code": "BAD_INJECTION"}
	_window = window
	_platform = platform
	_session = session
	var configured := _platform.configure_window(_window)
	if configured.get("ok") != true:
		return configured
	_restore_geometry()
	if not _window.visibility_changed.is_connected(_on_window_visibility_changed):
		_window.visibility_changed.connect(_on_window_visibility_changed)
	return configured


func update_interaction_regions(rects: Array) -> bool:
	return _platform != null and _platform.apply_mouse_regions(_window, rects)


func handle_boat_input(event: InputEvent) -> void:
	if _window == null or _platform == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag()
		elif _drag_pending:
			_finish_drag()
	elif event is InputEventMouseMotion and _drag_pending and not _native_drag_active:
		_update_manual_drag()


func poll() -> void:
	if _drag_pending and not _platform.left_mouse_down():
		_finish_drag()
	elif _drag_pending and not _native_drag_active:
		_update_manual_drag()


func apply_fps_target(target: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Engine.max_fps = FPS_DRAG if target == FPS_DRAG else FPS_VISIBLE


func _begin_drag() -> void:
	_drag_pending = true
	_native_drag_active = false
	_manual_drag_active = false
	_drag_start_cursor = _platform.mouse_position()
	_drag_start_window = _window.position
	if _platform.start_native_drag(_window):
		_native_drag_active = true
		_session.notify_drag_start()
		apply_fps_target(_session.fps_target())


func _update_manual_drag() -> void:
	if not _drag_pending or _native_drag_active:
		return
	var cursor := _platform.mouse_position()
	if cursor.x < 0 or cursor.y < 0 or _drag_start_cursor.x < 0 or _drag_start_cursor.y < 0:
		return
	var delta := cursor - _drag_start_cursor
	if not _manual_drag_active and Vector2(delta).length() < DRAG_THRESHOLD_PX:
		return
	if not _manual_drag_active:
		_manual_drag_active = true
		_session.notify_drag_start()
		apply_fps_target(_session.fps_target())
	var target := Vector2i(_drag_start_window + delta)
	_window.position = _platform.clamp_window_position(target, _window.size)


func _finish_drag() -> void:
	if not _drag_pending:
		return
	var moved := Vector2(_window.position - _drag_start_window).length()
	var was_drag := _native_drag_active or _manual_drag_active
	_drag_pending = false
	_native_drag_active = false
	_manual_drag_active = false
	_session.notify_drag_end()
	apply_fps_target(_session.fps_target())
	if moved < DRAG_THRESHOLD_PX:
		boat_clicked.emit()
	elif was_drag:
		var position := _window.position
		_session.update_window_geometry(position.x, position.y, _window.size.x, _window.size.y,
				_platform.current_display_hint())


func _restore_geometry() -> void:
	var view := _session.status_view()
	var geometry: Dictionary = view.get("desktop_window", {})
	var saved_size := Vector2i(
		maxi(int(geometry.get("width", PlatformAdapter.OVERLAY_SIZE.x)), 1),
		maxi(int(geometry.get("height", PlatformAdapter.OVERLAY_SIZE.y)), 1),
	)
	_window.size = saved_size
	var saved_position := Vector2i(int(geometry.get("x", 80)), int(geometry.get("y", 80)))
	_window.position = _platform.clamp_window_position(saved_position, saved_size)


func _on_window_visibility_changed() -> void:
	visibility_changed.emit(_window.visible)
