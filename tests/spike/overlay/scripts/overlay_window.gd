extends Node2D
# SPIKE-001 GUI 行为探针：透明/穿透变体、拖动阈值、位置持久化、30FPS 滑窗、自截图。
# 约束：
# - 计时/计时统计一律用 Time.get_ticks_msec()，禁止用帧计数做逻辑计时（FPS 统计本身也是毫秒滑窗）。
# - 只调用 get_property_list() 证实存在的 Window 属性；API 缺失的变体记 unsupported 并如实写报告。
# - 不实现经济/FSM/业务存档；user:// 只写窗口几何（临时探针数据，非 v0.1 正式存档）。
# - 可见时固定 30 FPS（SDD-175）：Engine.max_fps = 30。

const SAVE_PATH := "user://spike_window.json"
const STATE_PATH := "res://report/observed_state.json"
const MATRIX_PATH := "res://report/variant_matrix.json"
const EVIDENCE_DIR := "res://evidence"
const DRAG_THRESHOLD_PX := 6.0
const DEFAULT_POS := Vector2i(120, 120)
const FPS_WINDOW_MS := 1000
const FPS_SAMPLES_KEPT := 120

# Godot 4.3 Window.MousePassthroughMode: DISABLED=0, LOCAL_ONLY=1, LOCAL_AND_PARENT=2
const PASSTHROUGH_DISABLED := 0
const PASSTHROUGH_LOCAL_ONLY := 1

var _win: Window
var _variant := "init"
var _variant_api: Dictionary = {}
var _variant_log: Array = []
var _events: Array = []
var _ship_clicks := 0
var _drag_pending := false
var _dragging := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_win := Vector2i.ZERO
var _fps_window_start_ms := 0
var _fps_window_frames := 0
var _fps_last := 0.0
var _fps_samples: Array = []
var _hidden := false
var _final_report_written := false


func _ready() -> void:
	_win = get_window()
	Engine.max_fps = 30
	_variant_api = {
		"mouse_passthrough": _has_prop("mouse_passthrough"),
		"mouse_passthrough_mode": _has_prop("mouse_passthrough_mode"),
		"mouse_passthrough_polygon": _has_prop("mouse_passthrough_polygon"),
		"transparent": _has_prop("transparent"),
		"borderless": _has_prop("borderless"),
		"always_on_top": _has_prop("always_on_top"),
		"unfocusable": _has_prop("unfocusable"),
	}
	# 运行时兜底：即使 project 设置缺失/未生效，也尝试在代码里置透明与无边框。
	if _variant_api["transparent"]:
		_win.set("transparent", true)
	if _variant_api["borderless"]:
		_win.set("borderless", true)
	if _variant_api["always_on_top"]:
		_win.set("always_on_top", true)
	_restore_position()
	$Ship.gui_input.connect(_on_ship_gui_input)
	_win.visibility_changed.connect(_on_visibility_changed)
	_set_variant("off")
	_update_status()
	_fps_window_start_ms = Time.get_ticks_msec()
	_log_event("ready")


func _process(_delta: float) -> void:
	_fps_window_frames += 1
	var now := Time.get_ticks_msec()
	var elapsed := now - _fps_window_start_ms
	if elapsed >= FPS_WINDOW_MS:
		_fps_last = 1000.0 * float(_fps_window_frames) / float(elapsed)
		_fps_window_frames = 0
		_fps_window_start_ms = now
		_fps_samples.append([now, rounded(_fps_last, 2)])
		if _fps_samples.size() > FPS_SAMPLES_KEPT:
			_fps_samples.pop_front()
		_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_set_variant("full")
		KEY_2:
			_set_variant("polygon")
		KEY_3:
			_set_variant("off")
		KEY_9:
			_take_screenshot()
		KEY_Q, KEY_ESCAPE:
			get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_write_final_reports()


# ---------- 变体切换（键 1/2/3） ----------

func _set_variant(variant: String) -> void:
	var supported := true
	var note := ""
	var enable := (variant != "off")
	if variant == "polygon":
		if not _variant_api.get("mouse_passthrough_polygon", false):
			supported = false
			enable = false
			note = "mouse_passthrough_polygon 属性不存在 → 变体记 unsupported，退回关闭穿透"
	var applied := false
	if _variant_api.get("mouse_passthrough_mode", false):
		_win.set("mouse_passthrough_mode", PASSTHROUGH_LOCAL_ONLY if enable else PASSTHROUGH_DISABLED)
		applied = true
	elif _variant_api.get("mouse_passthrough", false):
		_win.set("mouse_passthrough", enable)
		applied = true
	if _variant_api.get("mouse_passthrough_polygon", false):
		var poly := PackedVector2Array()
		if variant == "polygon" and supported:
			# 顶部状态条区域穿透；船体与其余区域保持可交互（透明视觉 != 输入穿透）。
			var w := float(_win.size.x)
			poly = PackedVector2Array([
				Vector2(0, 0), Vector2(w, 0), Vector2(w, 45), Vector2(0, 45),
			])
		_win.set("mouse_passthrough_polygon", poly)
	_variant = variant
	_variant_log.append({
		"variant": variant,
		"supported": supported,
		"applied": applied,
		"note": note,
		"at_utc": Time.get_datetime_string_from_system(true, true),
		"effective_mouse_passthrough": _win.get("mouse_passthrough") if _variant_api.get("mouse_passthrough", false) else null,
		"effective_mouse_passthrough_mode": _win.get("mouse_passthrough_mode") if _variant_api.get("mouse_passthrough_mode", false) else null,
		"human_observation": "",
	})
	_log_event("variant:" + variant)
	_update_status()
	_write_reports()


# ---------- 船体拖动（阈值 6px）与点击 ----------

func _on_ship_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_pending = true
			_dragging = false
			_drag_start_mouse = event.global_position
			_drag_start_win = _win.position
		else:
			if _drag_pending and not _dragging:
				# 位移未达阈值 → 判定为点击，不误判为拖动（G-002）。
				_ship_clicks += 1
				_log_event("ship_click")
			if _drag_pending:
				_save_position()
			_drag_pending = false
			_dragging = false
			_update_status()
	elif event is InputEventMouseMotion and _drag_pending:
		var d: Vector2 = event.global_position - _drag_start_mouse
		if not _dragging and d.length() >= DRAG_THRESHOLD_PX:
			_dragging = true
			_log_event("drag_start")
			_update_status()
		if _dragging:
			_win.position = Vector2i(Vector2(_drag_start_win) + d.round())


# ---------- 位置持久化（临时探针几何，非业务存档） ----------

func _save_position() -> void:
	var pos: Vector2i = _win.position
	var size: Vector2i = _win.size
	var data := {
		"x": pos.x, "y": pos.y,
		"width": size.x, "height": size.y,
		"display_hint": null,
		"ts_utc": Time.get_datetime_string_from_system(true, true),
	}
	_write_json(SAVE_PATH, data)
	_log_event("position_saved")


func _restore_position() -> void:
	var pos := DEFAULT_POS
	var src := "default"
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed: Variant = null
		if f != null:
			var j := JSON.new()
			if j.parse(f.get_as_text()) == OK:
				parsed = j.data
		if parsed is Dictionary and parsed.has("x") and parsed.has("y"):
			pos = Vector2i(int(parsed["x"]), int(parsed["y"]))
			src = "saved"
		else:
			_log_event("position_read_failed_fallback_default")
	# 实测：本引擎 get_display_safe_area() 为 0 参数（4.7.2 真实签名，非文档假设）
	var area: Rect2i = DisplayServer.get_display_safe_area()
	if area.size.x >= _win.size.x and area.size.y >= _win.size.y:
		# 边缘/断屏安全回退：把窗口整体 clamp 回主屏安全区。
		pos.x = clampi(pos.x, area.position.x, area.position.x + area.size.x - _win.size.x)
		pos.y = clampi(pos.y, area.position.y, area.position.y + area.size.y - _win.size.y)
	_win.position = pos
	_log_event("position_restored_from_" + src)


# ---------- 隐藏时停止多余帧绘制（G-004；隐藏 ≠ 退出） ----------

func _on_visibility_changed() -> void:
	_hidden = not _win.visible
	set_process(not _hidden)
	_log_event("hidden" if _hidden else "shown")
	_write_reports()


# ---------- 自截图（键 9；只截游戏窗口，不截桌面） ----------

func _take_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(EVIDENCE_DIR)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_log_event("screenshot_failed_no_image")
		return
	var stamp := Time.get_datetime_string_from_system(true, true).replace("-", "").replace(":", "").replace("T", "_")
	var path := EVIDENCE_DIR + "/spike_" + stamp + ".png"
	var err := img.save_png(path)
	_log_event("screenshot_saved:%s:err=%d" % [path, err])
	_write_reports()


# ---------- 报告 ----------

func _write_final_reports() -> void:
	if _final_report_written:
		return
	_final_report_written = true
	_save_position()
	_write_reports()


func _write_reports() -> void:
	var state := {
		"variant": _variant,
		"variant_api": _variant_api,
		"variant_log": _variant_log,
		"events": _events,
		"ship_clicks": _ship_clicks,
		"drag_threshold_px": DRAG_THRESHOLD_PX,
		"window_position": [_win.position.x, _win.position.y],
		"window_size": [_win.size.x, _win.size.y],
		"max_fps": Engine.max_fps,
		"fps_last_window": _fps_last,
		"fps_samples": _fps_samples,
		"hidden": _hidden,
		"headless": DisplayServer.get_name() == "headless",
		"display_server": DisplayServer.get_name(),
		"ts_utc": Time.get_datetime_string_from_system(true, true),
	}
	_write_json(STATE_PATH, state)
	_write_json(MATRIX_PATH, state)


func _update_status() -> void:
	var label := get_node_or_null("Status") as Label
	if label == null:
		return
	var state := "DRAG" if _dragging else ("HOLD" if _drag_pending else "IDLE")
	label.text = "SPIKE-001 variant=%s %s fps=%.1f pos=(%d,%d) clicks=%d\n[1]=全窗穿透 [2]=穿透多边形 [3]=关 [9]=截图 [Q]=退出" % [
		_variant, state, _fps_last, _win.position.x, _win.position.y, _ship_clicks
	]


func _log_event(ev: String) -> void:
	_events.append([Time.get_ticks_msec(), Time.get_datetime_string_from_system(true, true), ev])
	if _events.size() > 2000:
		_events.pop_front()


func _has_prop(prop: StringName) -> bool:
	for p in _win.get_property_list():
		if str(p.get("name", "")) == prop:
			return true
	return false


func _write_json(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SPIKE-001: cannot write %s (err=%d)" % [path, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data, "  ") + "\n")
	f.close()


func rounded(v: float, digits: int) -> float:
	var m := pow(10.0, digits)
	return round(v * m) / m
