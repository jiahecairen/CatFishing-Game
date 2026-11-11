extends Node
# SPIKE-001 能力探针（自动门禁 + GUI 记录共用）。
# 职责：探测 Window 穿透/透明属性存在性与当前生效值、渲染器、显示数；
# headless 下写 res://report/capability.json 后 get_tree().quit()（不依赖 --quit-after/--do-string，R-03）。
# 约束：只读探测，不改业务；不做任何经济/FSM/存档逻辑。

const REPORT_PATH := "res://report/capability.json"

# 只探测已存在于 Window 的属性；缺失的记 unsupported，绝不调用未证实 API。
const WINDOW_PROPERTIES: PackedStringArray = [
	"mouse_passthrough",
	"mouse_passthrough_mode",
	"mouse_passthrough_polygon",
	"transparent",
	"borderless",
	"always_on_top",
	"unfocusable",
	"visible",
]


func _ready() -> void:
	var headless := DisplayServer.get_name() == "headless"
	# SPIKE-001-FIX-002 §9.5 前提检查：实测本构建 ClassDB 无 class_has_property()（T1 真实输出）
	# → 用 Input.get_property_list() 扫描存在性，Input.get 字符串访问取当前值（编译期不依赖属性存在）。
	var accum_supported := false
	var accum_value: Variant = null
	for p in Input.get_property_list():
		if str(p.get("name", "")) == "use_accumulated_input":
			accum_supported = true
			accum_value = Input.get("use_accumulated_input")
			break
	var report := {
		"engine_version": str(Engine.get_version_info().get("string", "unknown")),
		"display_server": DisplayServer.get_name(),
		"headless": headless,
		"rendering_method": str(RenderingServer.get_current_rendering_method()),
		"renderer_note": "headless 下此值可能为 dummy；Metal/Compatibility 实证必须来自 GUI 人工运行",
		"display_count": -1,
		"main_display_safe_area": null,
		"window_properties": {},
		"property_values": {},
		# SPIKE-001-FIX-001：拖动坐标源/原生拖动备选的方法存在性（只探测，不调用未证实 API）。
		"display_server_methods": {
			"mouse_get_position": ClassDB.class_has_method("DisplayServer", "mouse_get_position"),
			"window_start_drag": ClassDB.class_has_method("DisplayServer", "window_start_drag"),
			"get_display_safe_area": ClassDB.class_has_method("DisplayServer", "get_display_safe_area"),
		},
		# SPIKE-001-FIX-002 最小化追加：§3.1 窗口 ID 获取方式 + §9.5 输入积累实验前提（只探测，不改行为）。
		"window_methods": {
			"get_window_id": ClassDB.class_has_method("Window", "get_window_id"),
		},
		"input_properties": {
			"use_accumulated_input": accum_supported,
		},
		"input_accumulated_input_value": accum_value,
		"mouse_get_position_value": null,
		"ts_utc": Time.get_datetime_string_from_system(true, true),
	}
	# 区分“project 设置未生效”与“设置名写错”：记录设置项读取结果（headless 窗口 64×64 属 dummy 行为）。
	report["project_display_settings"] = {
		"display/window/size/viewport_width": _setting("display/window/size/viewport_width"),
		"display/window/size/viewport_height": _setting("display/window/size/viewport_height"),
		"display/window/size/transparent": _setting("display/window/size/transparent"),
		"display/window/size/borderless": _setting("display/window/size/borderless"),
		"display/window/size/always_on_top": _setting("display/window/size/always_on_top"),
	}
	if not headless:
		# 实测：本引擎无静态 DisplayServer.get_display_count() 类调用；先 ClassDB 探测再调用，缺失如实记 unsupported。
		if ClassDB.class_has_method("DisplayServer", "get_display_count"):
			report["display_count"] = DisplayServer.call("get_display_count")
		else:
			report["display_count"] = "unsupported_in_this_build"
		# 实测：本引擎 get_display_safe_area() 为 0 参数（4.7.2 真实签名）。
		var area: Rect2i = DisplayServer.get_display_safe_area()
		report["main_display_safe_area"] = [area.position.x, area.position.y, area.size.x, area.size.y]
		# GUI 下记录真实屏幕光标坐标（headless 返回哨兵值，不记录以免误导）。
		if ClassDB.class_has_method("DisplayServer", "mouse_get_position"):
			var mp: Vector2i = DisplayServer.mouse_get_position()
			report["mouse_get_position_value"] = [mp.x, mp.y]
	var win: Window = get_window()
	var props: Array[Dictionary] = win.get_property_list()
	for prop_name in WINDOW_PROPERTIES:
		var exists := false
		for p in props:
			if str(p.get("name", "")) == prop_name:
				exists = true
				break
		report["window_properties"][prop_name] = exists
		if exists:
			var value: Variant = win.get(prop_name)
			if value is PackedVector2Array:
				var pts: Array = []
				for pt in (value as PackedVector2Array):
					pts.append([pt.x, pt.y])
				report["property_values"][prop_name] = pts
			else:
				report["property_values"][prop_name] = value
	_write_json(REPORT_PATH, report)
	if headless:
		# headless 只证明脚本/场景可无错加载（§6 CI 门禁），不得当成透明/穿透 GUI 通过证据。
		get_tree().quit()


func _setting(key: String) -> Variant:
	return ProjectSettings.get_setting(key) if ProjectSettings.has_setting(key) else null


func _write_json(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SPIKE-001: cannot write %s (err=%d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "  ") + "\n")
	file.close()
