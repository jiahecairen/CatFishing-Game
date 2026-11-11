class_name GameController
extends Node
# UI-001 runtime composition root. The headless CORE smoke path stays side-effect free.

const SessionScript := preload("res://scripts/ui/fishing_session.gd")
const PlatformScript := preload("res://scripts/platform/platform_adapter.gd")
const DesktopScript := preload("res://scripts/platform/desktop_window.gd")

var _session: FishingSession
var _platform: PlatformAdapter
var _desktop: DesktopWindow
var _ui: UIRoot
var _last_tick_msec := 0
var _overlay_minimized_by_user := false
var _hide_transition_in_progress := false
var _restore_borderless := true
var _restore_always_on_top := true

func _notification(what: int) -> void:
	var window := get_window()
	if not is_instance_valid(window) or not _should_restore_after_focus(what,
			_overlay_minimized_by_user, window.mode == Window.MODE_MINIMIZED,
			_hide_transition_in_progress):
		return
	_restore_overlay_after_focus(what == NOTIFICATION_APPLICATION_FOCUS_IN)


func _should_restore_after_focus(what: int, minimized_by_user: bool,
		window_is_minimized: bool, hide_transition_in_progress: bool) -> bool:
	return minimized_by_user and not hide_transition_in_progress and (
			what == NOTIFICATION_APPLICATION_FOCUS_IN
			or (what == NOTIFICATION_WM_WINDOW_FOCUS_IN and not window_is_minimized))


func _restore_overlay_after_focus(restore_minimized_window: bool) -> void:
	if _desktop == null or not _overlay_minimized_by_user:
		return
	var window := get_window()
	if not is_instance_valid(window):
		return
	if window.mode == Window.MODE_MINIMIZED:
		if not restore_minimized_window:
			return
		window.mode = Window.MODE_WINDOWED
	_overlay_minimized_by_user = false
	window.borderless = _restore_borderless
	window.always_on_top = _restore_always_on_top
	_on_window_visibility_changed(true)


func _on_window_focus_entered() -> void:
	var window := get_window()
	if is_instance_valid(window) and _should_restore_after_focus(
			NOTIFICATION_WM_WINDOW_FOCUS_IN, _overlay_minimized_by_user,
			window.mode == Window.MODE_MINIMIZED, _hide_transition_in_progress):
		_restore_overlay_after_focus(false)


func _ready() -> void:
	Engine.max_fps = 30
	if DisplayServer.get_name() == "headless":
		var state := GameState.new()
		print("CORE001 GameController ready: wallet_gold=%d basket=%d basket_capacity=%d" % [
			state.wallet_gold, state.basket.size(), state.basket_capacity])
		return

	_session = SessionScript.new()
	var boot: Dictionary = _session.start()
	_platform = PlatformScript.new()
	_desktop = DesktopScript.new()
	_ui = get_node_or_null("UI") as UIRoot
	if _ui == null:
		push_error("UI001: Main scene is missing the UIRoot node")
		return
	var ui_result := _ui.initialize(_session)
	if ui_result.get("ok") != true:
		push_error("UI001: view initialization failed: " + str(ui_result))
		return
	var viewport := get_viewport()
	viewport.transparent_bg = true
	var window_result := _desktop.initialize(get_window(), _platform, _session)
	if window_result.get("ok") != true:
		push_error("UI001: desktop window setup failed: " + str(window_result))
		return
	if not get_window().focus_entered.is_connected(_on_window_focus_entered):
		get_window().focus_entered.connect(_on_window_focus_entered)
	_ui.boat_pointer_event.connect(_on_boat_pointer_event)
	_ui.sell_requested.connect(_on_sell_requested)
	_ui.sell_all_requested.connect(_on_sell_all_requested)
	_ui.retry_requested.connect(_on_retry_requested)
	_ui.interaction_regions_changed.connect(_refresh_interaction_regions)
	_ui.hide_requested.connect(_hide_overlay)
	_desktop.boat_clicked.connect(_on_boat_clicked)
	_desktop.visibility_changed.connect(_on_window_visibility_changed)
	_refresh_interaction_regions()
	_ui.refresh()
	_last_tick_msec = Time.get_ticks_msec()
	set_process(true)
	if boot.get("ok") == true:
		_maybe_auto_cast()
	_ui.refresh()


func _process(_delta: float) -> void:
	if _session == null or _desktop == null:
		return
	_desktop.poll()
	var now := Time.get_ticks_msec()
	var elapsed := maxf(0.0, float(now - _last_tick_msec) / 1000.0)
	_last_tick_msec = now
	if elapsed > 0.0:
		_session.tick(elapsed)
	_maybe_auto_cast()
	_desktop.apply_fps_target(_session.fps_target())
	_ui.refresh()


func _maybe_auto_cast() -> void:
	if _session == null:
		return
	var view: Dictionary = _session.status_view()
	if view.get("input_open") == true and view.get("save_error") != true \
			and view.get("hidden") != true and view.get("state") == "IDLE" \
			and view.get("basket_full") != true:
		_session.request_cast()


func _on_boat_pointer_event(event: InputEvent) -> void:
	_desktop.handle_boat_input(event)


func _on_boat_clicked() -> void:
	_ui.toggle_basket()
	_refresh_interaction_regions()
	_ui.refresh()


func _on_sell_requested(instance_ids: Array) -> void:
	_ui.set_submitting(true)
	_session.sell_selected(instance_ids)
	_ui.set_submitting(false)
	_ui.refresh()


func _on_sell_all_requested() -> void:
	_ui.set_submitting(true)
	_session.sell_all()
	_ui.set_submitting(false)
	_ui.refresh()


func _on_retry_requested() -> void:
	_session.retry_persist()
	_ui.refresh()


func _hide_overlay() -> void:
	if _session == null:
		return
	var window := get_window()
	if not is_instance_valid(window):
		return
	_hide_transition_in_progress = true
	_overlay_minimized_by_user = true
	_restore_borderless = window.borderless
	_restore_always_on_top = window.always_on_top
	_last_tick_msec = Time.get_ticks_msec()
	_session.hide()
	_ui.refresh()
	set_process(false)
	window.always_on_top = false
	window.borderless = false
	window.mode = Window.MODE_MINIMIZED
	_hide_transition_in_progress = false
	if window.mode != Window.MODE_MINIMIZED:
		_overlay_minimized_by_user = false
		window.borderless = _restore_borderless
		window.always_on_top = _restore_always_on_top
		_on_window_visibility_changed(true)


func _refresh_interaction_regions() -> void:
	if _desktop != null and _ui != null:
		_desktop.update_interaction_regions(_ui.interaction_rects())


func _on_window_visibility_changed(is_visible: bool) -> void:
	if _session == null:
		return
	_last_tick_msec = Time.get_ticks_msec()
	if is_visible:
		_session.show()
		set_process(true)
	else:
		_session.hide()
		_ui.refresh()
		set_process(false)
