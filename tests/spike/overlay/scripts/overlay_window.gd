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
const DRAG_SAMPLE_CAP := 400

# SPIKE-001-FIX-001 修正 A（人工审核为准）：Window.mouse_passthrough_polygon 的真实语义 =
# 多边形内部接收鼠标事件，多边形外部鼠标穿透；mouse_passthrough=true 时多边形设置无效。
# 本构建（4.7.2）实测无 mouse_passthrough_mode 属性，变体一律只用 mouse_passthrough(bool) +
# mouse_passthrough_polygon 表达；禁止反向凹多边形（全窗减船体）。

var _win: Window
var _variant := "init"
var _variant_api: Dictionary = {}
var _variant_log: Array = []
var _events: Array = []
var _ship_clicks := 0
var _drag_pending := false
var _dragging := false
# SPIKE-001-FIX-001 修正 B：拖动基准 = 按下瞬间的屏幕绝对坐标（不随窗口移动）+ 窗口起始位置。
# 禁止用 event.global_position 计算窗口位移（窗口一动即被反方向污染 → 往复抖动）。
var _drag_start_cursor := Vector2i.ZERO
var _drag_start_win := Vector2i.ZERO
var _mouse_pos_supported := false
var _drag_unsupported_logged := false
var _drag_samples: Array = []
var _drag_sample_count := 0
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
	_mouse_pos_supported = ClassDB.class_has_method("DisplayServer", "mouse_get_position")
	_variant_api["displayserver_mouse_get_position"] = _mouse_pos_supported
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
	# SPIKE-001-FIX-001：启动默认 = polygon 生产语义（透明区穿透 + 船体可交互）。
	_set_variant("polygon")
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
	# SPIKE-001-FIX-001 修正 A（人工审核为准，覆盖原计划 §1-A 的"polygon 内为穿透区"错误说法）：
	#   full    : mouse_passthrough=true  + polygon=空数组（整窗穿透，对照组）
	#   polygon : mouse_passthrough=false + polygon=Ship 实际可交互矩形（生产语义，启动默认）
	#             → 多边形内（船体）接收鼠标事件，多边形外（透明区）穿透
	#   off     : mouse_passthrough=false + polygon=空数组（整窗拦截，对照组）
	# 禁止"全窗口减去船体"的反向凹多边形。
	var supported := true
	var note := ""
	var enable := (variant == "full")
	var poly := PackedVector2Array()
	if variant == "polygon":
		if not _variant_api.get("mouse_passthrough_polygon", false):
			supported = false
			note = "mouse_passthrough_polygon 属性不存在 → 变体记 unsupported，退回整窗拦截"
		else:
			var ship := get_node_or_null("Ship") as Control
			if ship == null:
				supported = false
				note = "Ship 节点缺失 → 变体记 unsupported，退回整窗拦截"
			else:
				var r := ship.get_global_rect()
				poly = PackedVector2Array([
					r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y),
				])
	var applied := false
	if _variant_api.get("mouse_passthrough", false):
		# 本构建实测无 mouse_passthrough_mode 属性，仅用布尔 + 多边形表达（修正 A）；
		# 布尔为 true 时多边形无效，故仅 full 置 true。
		_win.set("mouse_passthrough", enable)
		applied = true
	else:
		note = (note + "; " if note != "" else "") + "mouse_passthrough 属性不存在 → 无法应用穿透变体"
	if _variant_api.get("mouse_passthrough_polygon", false):
		# full/off 显式清空多边形，避免旧多边形残留（godot-overlay §3）。
		_win.set("mouse_passthrough_polygon", poly)
	var poly_points: Array = []
	for pt in poly:
		poly_points.append([pt.x, pt.y])
	_variant = variant
	_variant_log.append({
		"variant": variant,
		"supported": supported,
		"applied": applied,
		"note": note,
		"at_utc": Time.get_datetime_string_from_system(true, true),
		"effective_mouse_passthrough": _win.get("mouse_passthrough") if _variant_api.get("mouse_passthrough", false) else null,
		"effective_mouse_passthrough_polygon": poly_points,
		"effective_mouse_passthrough_polygon_point_count": poly_points.size(),
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
			_drag_unsupported_logged = false
			# 修正 B：只在按下瞬间冻结一次屏幕绝对坐标与窗口位置作为拖动基准。
			if _mouse_pos_supported:
				_drag_start_cursor = DisplayServer.mouse_get_position()
			_drag_start_win = _win.position
			_drag_samples = []
			_drag_sample_count = 0
		else:
			if _drag_pending and not _dragging:
				# 位移未达阈值 → 判定为点击，不误判为拖动（G-002a）。
				_ship_clicks += 1
				_log_event("ship_click")
			if _drag_pending and _dragging:
				_log_event("drag_end:samples=%d" % _drag_sample_count)
			if _drag_pending:
				_save_position()
				_write_reports()
			_drag_pending = false
			_dragging = false
			_update_status()
	elif event is InputEventMouseMotion and _drag_pending:
		# 修正 B：位移 = 当前屏幕坐标 − 按下时屏幕坐标；坐标源不随窗口移动，无自我反馈 → 无抖动。
		# 禁止 event.global_position 计算位移；禁止 Input.capture_mouse（非 Godot 4 API）。
		if not _mouse_pos_supported:
			# 探测→unsupported→如实记录（R-03）：不猜测缺失 API，也不降级为 global_position 位移。
			if not _drag_unsupported_logged:
				_drag_unsupported_logged = true
				_log_event("drag_unsupported:DisplayServer.mouse_get_position")
			return
		var cur := DisplayServer.mouse_get_position()
		var d := Vector2(cur - _drag_start_cursor)
		if not _dragging and d.length() >= DRAG_THRESHOLD_PX:
			_dragging = true
			_log_event("drag_start")
			_update_status()
		if _dragging:
			# 每事件基于冻结基准一次性取整，避免 ±1px 抖振；G-001d 轨迹样本供人工核对。
			var target := (Vector2(_drag_start_win) + d).round()
			_win.position = Vector2i(int(target.x), int(target.y))
			_drag_sample_count += 1
			if _drag_samples.size() < DRAG_SAMPLE_CAP:
				_drag_samples.append([Time.get_ticks_msec(), d.x, d.y])


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
		"mouse_get_position_supported": _mouse_pos_supported,
		"last_drag_sample_count": _drag_sample_count,
		"last_drag_samples": _drag_samples,
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
	label.text = "SPIKE-001 variant=%s %s fps=%.1f pos=(%d,%d) clicks=%d\n[1]=整窗穿透 [2]=船体多边形(默认) [3]=全拦截 [9]=截图 [Q]=退出" % [
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
