extends SceneTree
# UI-001 headless integration checks for FishingSession. All save IO uses explicit temporary dirs.
const SessionScript := preload("res://scripts/ui/fishing_session.gd")
const BasketMenuScript := preload("res://scripts/ui/basket_menu.gd")
const HudScript := preload("res://scripts/ui/fishing_status_hud.gd")
const ControllerScript := preload("res://scripts/core/game_controller.gd")
const DesktopScript := preload("res://scripts/platform/desktop_window.gd")
const SAVE_NAME := "game_state.json"
const UTC := "2026-11-11T00:00:00Z"

class TestPlatform extends "res://scripts/platform/platform_adapter.gd":
	var cursor := Vector2i(100, 100)
	var native_drag := false

	func mouse_position() -> Vector2i:
		return cursor

	func start_native_drag(_window: Window) -> bool:
		return native_drag

	func clamp_window_position(position: Vector2i, _window_size: Vector2i) -> Vector2i:
		return position

	func current_display_hint() -> Variant:
		return 0


class TestSession extends "res://scripts/ui/fishing_session.gd":
	var drag_starts := 0
	var drag_ends := 0
	var geometry_updates: Array = []

	func notify_drag_start() -> void:
		drag_starts += 1

	func notify_drag_end() -> void:
		drag_ends += 1

	func fps_target() -> int:
		return 30

	func update_window_geometry(x: Variant, y: Variant, width: Variant, height: Variant,
			display_hint: Variant = null) -> Dictionary:
		geometry_updates.append([x, y, width, height, display_hint])
		return {"ok": true, "code": ""}


var _dirs: Array[String] = []
var _dir_seq := 0


func _initialize() -> void:
	if not _check(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", false) == true,
			"UI transparency must allow per-pixel alpha"):
		return
	await process_frame
	for step in [_test_basket_selection_survives_new_catch, _test_mouse_passthrough_polygon_winding,
			_test_click_vs_drag_policy,
			_test_hide_control_and_reactivation,
			_test_boot_fail_closed,
			_test_catch_and_crash_recovery, _test_sales_and_price_snapshot,
			_test_save_failure_retry, _test_full_basket_and_fps, _test_hide_and_window_checkpoint]:
		if not step.call():
			_cleanup_dirs()
			return
	_cleanup_dirs()
	print("UI001 UI PASS")
	quit(0)


func _test_basket_selection_survives_new_catch() -> bool:
	var menu = BasketMenuScript.new()
	root.add_child(menu)
	var names := {"river_carp": "江鲤", "silver_perch": "银斑鲈"}
	var first_fish := {"instance_id": "selected-carp", "species_id": "river_carp", "sale_price_at_catch": 8}
	var new_fish := {"instance_id": "new-perch", "species_id": "silver_perch", "sale_price_at_catch": 16}
	menu.update_items([first_fish], names, false)
	var checkbox := menu.get_node_or_null("Rows/FishScroll/FishRows/Fish_selected-carp") as CheckBox
	if not _check(is_instance_valid(checkbox), "U-selection find first fish checkbox"):
		menu.free()
		return false
	checkbox.button_pressed = true
	menu.update_items([first_fish, new_fish], names, false)
	var selected := menu.selected_instance_ids()
	var preserved := _check(selected == ["selected-carp"],
			"U-selection retain selected fish when a new catch refreshes the basket")
	menu.free()
	return preserved


func _test_hide_control_and_reactivation() -> bool:
	var hud = HudScript.new()
	root.add_child(hud)
	var requested := [false]
	hud.hide_requested.connect(func(): requested[0] = true)
	var hide_button := hud.get_node_or_null("HideOverlayButton") as Button
	if not _check(is_instance_valid(hide_button) and hud.hide_button_rect().size.x > 0.0,
			"U-hide overlay control exists inside the interactive region"):
		hud.free()
		return false
	hide_button.pressed.emit()
	if not _check(requested[0], "U-hide overlay button emits a pause-and-hide request"):
		hud.free()
		return false

	hud.free()
	var policy_controller = ControllerScript.new()
	var restores_hidden_window := policy_controller._should_restore_after_focus(
			Node.NOTIFICATION_APPLICATION_FOCUS_IN, true, true, false)
	var restores_window_focus := policy_controller._should_restore_after_focus(
			Node.NOTIFICATION_WM_WINDOW_FOCUS_IN, true, false, false)
	var waits_until_window_is_restored := not policy_controller._should_restore_after_focus(
			Node.NOTIFICATION_WM_WINDOW_FOCUS_IN, true, true, false)
	var ignores_hide_transition := not policy_controller._should_restore_after_focus(
			Node.NOTIFICATION_WM_WINDOW_FOCUS_IN, true, false, true)
	var ignores_focus_out := not policy_controller._should_restore_after_focus(
			Node.NOTIFICATION_APPLICATION_FOCUS_OUT, true, false, false)
	var keeps_visible_window := not policy_controller._should_restore_after_focus(
			Node.NOTIFICATION_APPLICATION_FOCUS_IN, false, false, false)
	policy_controller.free()
	return _check(restores_hidden_window and restores_window_focus and waits_until_window_is_restored
			and ignores_hide_transition and ignores_focus_out and keeps_visible_window,
			"U-hide app focus restores minimized window; window focus waits for OS unminimize")


func _test_mouse_passthrough_polygon_winding() -> bool:
	var window := Window.new()
	window.size = Vector2i(220, 160)
	var platform := TestPlatform.new()
	var regions := [
		Rect2(Vector2(38, 76), Vector2(144, 76)),
		Rect2(Vector2(170, 30), Vector2(40, 31)),
	]
	var applied := platform.apply_mouse_regions(window, regions)
	var polygon := window.mouse_passthrough_polygon
	var correct := applied and not window.mouse_passthrough \
			and polygon.size() >= 4 \
			and _polygon_signed_area(polygon) < 0.0 \
			and Geometry2D.is_point_in_polygon(Vector2(100, 100), polygon) \
			and Geometry2D.is_point_in_polygon(Vector2(190, 45), polygon) \
			and Geometry2D.is_point_in_polygon(Vector2(176, 68), polygon) \
			and not Geometry2D.is_point_in_polygon(Vector2(178, 68), polygon) \
			and not Geometry2D.is_point_in_polygon(Vector2(100, 65), polygon) \
			and not Geometry2D.is_point_in_polygon(Vector2(206, 20), polygon)
	var basket_regions := regions.duplicate()
	basket_regions.append(Rect2(Vector2(6, 52), Vector2(208, 104)))
	var basket_applied := platform.apply_mouse_regions(window, basket_regions)
	var basket_polygon := window.mouse_passthrough_polygon
	correct = correct and basket_applied and not window.mouse_passthrough \
			and _polygon_signed_area(basket_polygon) < 0.0 \
			and Geometry2D.is_point_in_polygon(Vector2(20, 70), basket_polygon) \
			and Geometry2D.is_point_in_polygon(Vector2(100, 100), basket_polygon) \
			and Geometry2D.is_point_in_polygon(Vector2(190, 45), basket_polygon) \
			and not Geometry2D.is_point_in_polygon(Vector2(218, 20), basket_polygon)
	window.free()
	if not _check(correct,
			"U-region keeps controls clickable while gaps and transparent corners pass through"):
		return false

	var diagonal_window := Window.new()
	diagonal_window.size = Vector2i(100, 100)
	var diagonal_applied := platform.apply_mouse_regions(diagonal_window, [
		Rect2(Vector2(10, 10), Vector2(20, 20)),
		Rect2(Vector2(50, 50), Vector2(20, 20)),
	])
	var diagonal_polygon := diagonal_window.mouse_passthrough_polygon
	var diagonal_correct := diagonal_applied and not diagonal_window.mouse_passthrough \
			and Geometry2D.is_point_in_polygon(Vector2(20, 20), diagonal_polygon) \
			and Geometry2D.is_point_in_polygon(Vector2(60, 60), diagonal_polygon) \
			and not Geometry2D.is_point_in_polygon(Vector2(40, 20), diagonal_polygon)
	diagonal_window.free()
	if not _check(diagonal_correct, "U-region joins diagonal controls with a narrow bridge"):
		return false

	var horizontal_window := Window.new()
	horizontal_window.size = Vector2i(100, 100)
	var horizontal_applied := platform.apply_mouse_regions(horizontal_window, [
		Rect2(Vector2(10, 10), Vector2(20, 20)),
		Rect2(Vector2(50, 15), Vector2(20, 10)),
	])
	var horizontal_polygon := horizontal_window.mouse_passthrough_polygon
	var horizontal_correct := horizontal_applied and not horizontal_window.mouse_passthrough \
			and Geometry2D.is_point_in_polygon(Vector2(40, 20), horizontal_polygon) \
			and not Geometry2D.is_point_in_polygon(Vector2(40, 22), horizontal_polygon)
	horizontal_window.free()
	return _check(horizontal_correct, "U-region keeps horizontal bridge narrow so gap passes through")


func _polygon_signed_area(polygon: PackedVector2Array) -> float:
	var twice_area := 0.0
	for point_index in range(polygon.size()):
		var current := polygon[point_index]
		var next := polygon[(point_index + 1) % polygon.size()]
		twice_area += current.x * next.y - next.x * current.y
	return twice_area * 0.5


func _test_click_vs_drag_policy() -> bool:
	var click_window := Window.new()
	click_window.position = Vector2i(80, 80)
	click_window.size = Vector2i(220, 160)
	var click_platform := TestPlatform.new()
	var click_session := TestSession.new()
	var click_policy = DesktopScript.new()
	click_policy._window = click_window
	click_policy._platform = click_platform
	click_policy._session = click_session
	var click_count := [0]
	click_policy.boat_clicked.connect(func(): click_count[0] += 1)
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.pressed = false
	click_policy.handle_boat_input(pressed)
	click_policy.handle_boat_input(released)
	var click_emitted: bool = click_count[0] == 1 and click_session.drag_ends == 1
	click_window.free()

	var native_window := Window.new()
	native_window.position = Vector2i(80, 80)
	native_window.size = Vector2i(220, 160)
	var native_platform := TestPlatform.new()
	native_platform.native_drag = true
	var native_session := TestSession.new()
	var native_policy = DesktopScript.new()
	native_policy._window = native_window
	native_policy._platform = native_platform
	native_policy._session = native_session
	var native_click_count := [0]
	native_policy.boat_clicked.connect(func(): native_click_count[0] += 1)
	native_policy.handle_boat_input(pressed)
	var native_drag_started_on_press := native_session.drag_starts == 1
	native_policy.handle_boat_input(released)
	var native_click_emitted: bool = native_drag_started_on_press and native_click_count[0] == 1 \
			and native_session.drag_ends == 1 and native_session.geometry_updates.is_empty()
	native_window.free()

	var drag_window := Window.new()
	drag_window.position = Vector2i(80, 80)
	drag_window.size = Vector2i(220, 160)
	var drag_platform := TestPlatform.new()
	var drag_session := TestSession.new()
	var drag_policy = DesktopScript.new()
	drag_policy._window = drag_window
	drag_policy._platform = drag_platform
	drag_policy._session = drag_session
	var drag_click_count := [0]
	drag_policy.boat_clicked.connect(func(): drag_click_count[0] += 1)
	drag_policy.handle_boat_input(pressed)
	drag_platform.cursor = Vector2i(111, 100)
	var motion := InputEventMouseMotion.new()
	drag_policy.handle_boat_input(motion)
	drag_policy.handle_boat_input(released)
	var drag_recorded: bool = drag_click_count[0] == 0 and drag_session.drag_starts == 1 \
			and drag_session.drag_ends == 1 \
			and drag_session.geometry_updates == [[91, 80, 220, 160, 0]]
	drag_window.free()
	return _check(click_emitted and native_click_emitted and drag_recorded,
			"U-window click emits boat click, native drag starts on press, and movement saves geometry")


func _test_boot_fail_closed() -> bool:
	var fresh_dir := _fresh_dir("boot")
	var session = SessionScript.new()
	var started: Dictionary = session.start({"save_dir": fresh_dir, "rng_seed": 1001})
	if not _check(started.get("ok") == true and started.get("fresh") == true
			and session.status_view().get("input_open") == true
			and FileAccess.file_exists(fresh_dir + SAVE_NAME), "U0 fresh boot must persist before opening input"):
		return false
	var document := _read_json(fresh_dir + SAVE_NAME)
	if not _check(document.get("save_version") == 2 and document.get("revision") == 1
			and document.get("wallet_gold") == 0 and document.get("basket") == [], "U0 initial checkpoint contents"):
		return false
	var resumed = SessionScript.new()
	var existing: Dictionary = resumed.start({"save_dir": fresh_dir, "rng_seed": 1001})
	if not _check(existing.get("ok") == true and existing.get("fresh") != true
			and resumed.status_view().get("input_open") == true, "U0 existing save must load without reset"):
		return false

	var corrupt_dir := _fresh_dir("corrupt")
	var corrupt_path := corrupt_dir + SAVE_NAME
	var corrupt_bytes := "{not-json; preserve exactly"
	if not _write_text(corrupt_path, corrupt_bytes):
		return _fail("U0 create corrupt save")
	var corrupt_session = SessionScript.new()
	var corrupt_result: Dictionary = corrupt_session.start({"save_dir": corrupt_dir, "rng_seed": 1002})
	if not _check(corrupt_result.get("ok") == false and corrupt_session.status_view().get("input_open") == false
			and _read_text(corrupt_path) == corrupt_bytes, "U0 corrupt save must fail closed and remain byte-identical"):
		return false

	var newer_dir := _fresh_dir("newer")
	var newer_path := newer_dir + SAVE_NAME
	var newer_bytes := "{\"save_version\":999}"
	if not _write_text(newer_path, newer_bytes):
		return _fail("U0 create future-version save")
	var newer_session = SessionScript.new()
	var newer_result: Dictionary = newer_session.start({"save_dir": newer_dir, "rng_seed": 1003})
	if not _check(newer_result.get("ok") == false and newer_session.status_view().get("input_open") == false
			and _read_text(newer_path) == newer_bytes, "U0 future save must fail closed and remain unchanged"):
		return false

	var invalid_dir := _fresh_dir("bad-config")
	var invalid_config := invalid_dir + "runtime-invalid.json"
	if not _write_text(invalid_config, "{bad config"):
		return _fail("U0 create invalid config")
	var invalid_session = SessionScript.new()
	var invalid_result: Dictionary = invalid_session.start({"save_dir": invalid_dir + "save/",
			"runtime_path": invalid_config, "rng_seed": 1004})
	return _check(invalid_result.get("ok") == false and invalid_session.status_view().get("input_open") == false
			and not DirAccess.dir_exists_absolute(invalid_dir + "save"),
			"U0 invalid config must fail before creating a save directory")


func _test_catch_and_crash_recovery() -> bool:
	var dir := _fresh_dir("pending-recovery")
	var session = SessionScript.new()
	var boot: Dictionary = session.start({"save_dir": dir, "rng_seed": 4242, "manual_settlement": true})
	if not _check(boot.get("ok") == true, "U1R session boot"):
		return false
	if not _check(_tick_to_settlement(session), "U1R deterministic cycle reaches SETTLEMENT"):
		return false
	var checkpoint: Dictionary = session.fsm().snapshot_checkpoint()
	if not _check(checkpoint.get("state") == "SETTLEMENT" and session.state().basket.is_empty(),
			"U1R candidate is pending and not visible in the basket before commit"):
		return false
	var committed: Dictionary = session.commit_pending_catch()
	if not _check(committed.get("ok") == true and session.state().basket.size() == 1,
			"U1R persist catch while retaining the pending candidate"):
		return false
	var on_disk := _read_json(dir + SAVE_NAME)
	if not _check(on_disk.get("pending_candidate") is Dictionary and on_disk.get("basket", []).size() == 1,
			"U1R crash image contains committed fish and pending candidate"):
		return false

	# Replace every in-memory service by starting a new session from the crash image.
	var recovered = SessionScript.new()
	var recovery: Dictionary = recovered.start({"save_dir": dir, "rng_seed": 4242})
	if not _check(recovery.get("ok") == true and recovered.state().basket.size() == 1
			and recovered.state().processed_catch_ids.size() == 1
			and recovered.save_service().export_document().get("pending_candidate") == null,
			"U1R replay/ack/clear must not duplicate the fish"):
		return false
	var disk_after := _read_json(dir + SAVE_NAME)
	return _check(disk_after.get("pending_candidate") == null
			and disk_after.get("basket", []).size() == 1
			and disk_after.get("processed_catch_ids", []).size() == 1,
			"U1R recovery checkpoint has one fish and no pending candidate")


func _test_sales_and_price_snapshot() -> bool:
	var dir := _fresh_dir("sales")
	var session = SessionScript.new()
	if not _check(session.start({"save_dir": dir, "rng_seed": 5252}).get("ok") == true, "U2 boot"):
		return false
	var first_id := _seed_catch(session, "sale-carp", "river_carp", UTC)
	var second_id := _seed_catch(session, "sale-perch", "silver_perch", "2026-11-11T00:00:01Z")
	if not _check(not first_id.is_empty() and not second_id.is_empty(), "U8 seed two fish through the durable economy gate"):
		return false
	var first_fish := _find_fish(session.state().basket, first_id)
	var second_fish := _find_fish(session.state().basket, second_id)
	if not _check(first_fish.get("sale_price_at_catch") == 8 and second_fish.get("sale_price_at_catch") == 16,
			"U8 captured price snapshots match the validated catalog"):
		return false
	var selected_ids := [first_id, second_id]
	var sold: Dictionary = session.sell_selected(selected_ids)
	if not _check(sold.get("ok") == true and sold.get("gold_added") == 24
			and session.state().wallet_gold == 24 and session.state().basket.is_empty(),
			"U2 sell selected commits both fish and summed snapshot prices"):
		return false
	var replay: Dictionary = session.sell_selected(selected_ids)
	if not _check(replay.get("ok") == true and replay.get("code") == "ALREADY_APPLIED"
			and session.state().wallet_gold == 24, "U2 repeated sale intent cannot pay twice"):
		return false
	var third_id := _seed_catch(session, "sale-all", "golden_trout", "2026-11-11T00:00:02Z")
	var all: Dictionary = session.sell_all()
	return _check(not third_id.is_empty() and all.get("ok") == true and all.get("gold_added") == 32
			and session.state().basket.is_empty() and session.state().wallet_gold == 56,
			"U2 sell all clears the basket and pays the captured snapshot price")


func _test_save_failure_retry() -> bool:
	var dir := _fresh_dir("save-failure")
	var session = SessionScript.new()
	if not _check(session.start({"save_dir": dir, "rng_seed": 6262}).get("ok") == true, "U4 boot"):
		return false
	var fish_id := _seed_catch(session, "failure-sale", "river_carp", UTC)
	if not _check(not fish_id.is_empty(), "U4 seed fish"):
		return false
	var gold_before: int = session.state().wallet_gold
	var count_before: int = session.state().basket.size()
	if not _check(session.save_fault("rename", true).get("ok") == true, "U4 arm rename fault"):
		return false
	var failed: Dictionary = session.sell_selected([fish_id])
	if not _check(failed.get("ok") == false and failed.get("code") == "PERSIST_FAILED"
			and session.status_view().get("save_error") == true
			and session.state().wallet_gold == gold_before and session.state().basket.size() == count_before,
			"U4 failed save leaves wallet/basket unpublished and exposes save-error state"):
		return false
	if not _check(session.request_cast().get("code") == "SAVE_ERROR", "U4 failed persistence pauses new casts"):
		return false
	if not _check(session.save_fault("rename", false).get("ok") == true, "U4 disarm rename fault"):
		return false
	var retried: Dictionary = session.retry_persist()
	return _check(retried.get("ok") == true and session.status_view().get("save_error") == false
			and session.state().wallet_gold == 8 and session.state().basket.is_empty(),
			"U4 retry reuses the sale intent and publishes exactly one sale")


func _test_full_basket_and_fps() -> bool:
	var dir := _fresh_dir("full-basket")
	var session = SessionScript.new()
	if not _check(session.start({"save_dir": dir, "rng_seed": 7272}).get("ok") == true, "U3 boot"):
		return false
	for index in 10:
		var fish_id := _seed_catch(session, "full-%02d" % index, "river_carp",
				"2026-11-11T00:00:%02dZ" % index)
		if fish_id.is_empty():
			return _fail("U3 seed fish %d" % index)
	var rng_before: int = session.rng().get_state()
	var denied: Dictionary = session.request_cast()
	if not _check(denied.get("ok") == false and denied.get("rejected_reason") == "BASKET_FULL"
			and session.rng().get_state() == rng_before and session.status_view().get("basket_full") == true,
			"U3 full basket rejects cast without consuming RNG"):
		return false
	if not _check(session.fps_target() == 30, "U6 visible idle FPS target is 30"):
		return false
	session.notify_drag_start()
	if not _check(session.fps_target() == 60, "U6 active drag FPS target is 60"):
		return false
	session.notify_drag_end()
	return _check(session.fps_target() == 30, "U6 drag end restores 30 FPS")


func _test_hide_and_window_checkpoint() -> bool:
	var dir := _fresh_dir("hide-window")
	var session = SessionScript.new()
	if not _check(session.start({"save_dir": dir, "rng_seed": 8282}).get("ok") == true, "U5/U7 boot"):
		return false
	if not _check(session.request_cast().get("ok") == true, "U5 cast"):
		return false
	session.tick(0.5)
	var clock_before: Dictionary = session.clock().snapshot_state()
	var hidden: Dictionary = session.hide()
	var hidden_doc := _read_json(dir + SAVE_NAME)
	if not _check(hidden.get("ok") == true and hidden_doc.get("fishing_checkpoint", {}).get("state") == "CASTING"
			and hidden_doc.get("fishing_checkpoint", {}).get("elapsed_effective_seconds") == 0.5,
			"U5 hide persists the pre-pause checkpoint state"):
		return false
	session.tick(30.0)
	if not _check(session.clock().snapshot_state() == clock_before and session.fsm().snapshot_checkpoint().get("state") == "CASTING",
			"U5 hidden session consumes no effective time"):
		return false
	if not _check(session.show().get("ok") == true, "U5 show resumes safely"):
		return false
	session.tick(0.5)
	if not _check(session.fsm().snapshot_checkpoint().get("state") == "WAITING", "U5 resumed casting continues"):
		return false
	var geometry: Dictionary = session.update_window_geometry(123, 234, 220, 160, 1)
	if not _check(geometry.get("ok") == true, "U7 valid geometry checkpoint"):
		return false
	var invalid: Dictionary = session.update_window_geometry(-1, 234, 220, 160)
	if not _check(invalid.get("ok") == false and session.status_view().get("desktop_window", {}).get("x") == 123,
			"U7 invalid geometry is rejected without changing the last committed value"):
		return false
	var recovered = SessionScript.new()
	if not _check(recovered.start({"save_dir": dir, "rng_seed": 8282}).get("ok") == true,
			"U7 reload geometry checkpoint"):
		return false
	return _check(recovered.status_view().get("desktop_window") == {
			"x": 123, "y": 234, "width": 220, "height": 160, "display_hint": 1},
			"U7 geometry survives reload field-for-field")


func _tick_to_settlement(session) -> bool:
	if session.request_cast().get("ok") != true:
		return false
	for _step in 8:
		if session.fsm().snapshot_checkpoint().get("state") == "SETTLEMENT":
			return true
		session.tick(120.0)
	return session.fsm().snapshot_checkpoint().get("state") == "SETTLEMENT"


func _seed_catch(session, event_id: String, species_id: String, caught_at_utc: String) -> String:
	var result: Dictionary = session.economy().commit_catch(session.state(), event_id, species_id, caught_at_utc)
	if result.get("ok") != true:
		print("UI001 test seed catch failed: " + str(result))
		return ""
	return String(result.get("instance_id", ""))


func _find_fish(basket: Array, instance_id: String) -> Dictionary:
	for fish in basket:
		if fish is Dictionary and String(fish.get("instance_id", "")) == instance_id:
			return fish
	return {}


func _fresh_dir(label: String) -> String:
	var base := OS.get_temp_dir().trim_suffix("/")
	var path := base + "/ui001_%s_%d_%d" % [label, Time.get_ticks_usec(), _dir_seq]
	_dir_seq += 1
	DirAccess.make_dir_recursive_absolute(path)
	_dirs.append(path)
	return path + "/"


func _cleanup_dirs() -> void:
	for path in _dirs:
		_remove_dir_recursive(path)
	_dirs.clear()


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path.path_join(entry)
		if dir.current_is_dir():
			_remove_dir_recursive(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	return file.get_error() == OK


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	return parsed if parsed is Dictionary else {}


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	return _fail(message)


func _fail(message: String) -> bool:
	print("UI001 UI FAIL: " + message)
	quit(1)
	return false
