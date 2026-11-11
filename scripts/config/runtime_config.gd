class_name RuntimeConfig
extends RefCounted
# CFG-001：运行配置（data/runtime_config.json）纯数据校验器，可 headless 测试。
# 契约来源：docs/INTERFACES_AND_DATA.md §1、schemas/runtime-config.schema.json、
# docs/DECISION_REGISTER.md SDD-172/175/177、tasks/evidence/CFG-001/plan.md §4。
# 不变量：
# - 纯 RefCounted 数据层：不依赖 Node/场景树，不读写 user://，不产生任何文件写入。
# - 失败路径零默认值：ok=false 时 config 恒为空 Dictionary，绝不回填 20/60/30/10。
# - 20/60 为已批准初值、10 为候选容量：本校验器只锁 30 FPS 与版本，不锁定 10。
# 校验顺序：文件 → JSON → 形状 → 版本 → 逐字段 → min<=max（T-CONF-01）。

const ERROR_FILE_MISSING := "FILE_MISSING"
const ERROR_FILE_OPEN := "FILE_OPEN"
const ERROR_JSON_PARSE := "JSON_PARSE"
const ERROR_BAD_VERSION := "BAD_VERSION"
const ERROR_BAD_SHAPE := "BAD_SHAPE"
const ERROR_BAD_FPS := "BAD_FPS"
const ERROR_BAD_BITE_WAIT := "BAD_BITE_WAIT"
const ERROR_MIN_GT_MAX := "MIN_GT_MAX"
const ERROR_BAD_CAPACITY := "BAD_CAPACITY"

const CONFIG_VERSION := 1
const VISIBLE_FPS := 30 # SDD-175：可见窗口固定 30 FPS（const，对齐 schema）。
const ROOT_KEYS := ["config_version", "visible_fps", "bite_wait_min_sec", "bite_wait_max_sec", "basket_capacity"]
const BITE_WAIT_MIN_LIMIT := 1.0
const BITE_WAIT_MAX_LIMIT := 86400.0 # 对齐 schema maximum: 86400。


## 校验运行配置文件。返回 {ok: bool, error_code: String, config: Dictionary}。
## ok=false 时 config == {}（零默认值），error_code 为上面 ERROR_* 稳定常量之一。
static func load_config(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail(ERROR_FILE_MISSING)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail(ERROR_FILE_OPEN)
	var text := file.get_as_text()
	file = null
	if text.is_empty():
		return _fail(ERROR_JSON_PARSE)
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail(ERROR_JSON_PARSE)
	var root: Variant = json.data
	if not (root is Dictionary):
		return _fail(ERROR_JSON_PARSE)

	if not _has_exact_keys(root, ROOT_KEYS):
		return _fail(ERROR_BAD_SHAPE)
	if not _is_integral(root["config_version"]) or int(root["config_version"]) != CONFIG_VERSION:
		return _fail(ERROR_BAD_VERSION)
	if not _is_integral(root["visible_fps"]) or int(root["visible_fps"]) != VISIBLE_FPS:
		return _fail(ERROR_BAD_FPS)

	var raw_min: Variant = root["bite_wait_min_sec"]
	if not _is_number_in_range(raw_min, BITE_WAIT_MIN_LIMIT, BITE_WAIT_MAX_LIMIT):
		return _fail(ERROR_BAD_BITE_WAIT)
	var raw_max: Variant = root["bite_wait_max_sec"]
	if not _is_number_in_range(raw_max, BITE_WAIT_MIN_LIMIT, BITE_WAIT_MAX_LIMIT):
		return _fail(ERROR_BAD_BITE_WAIT)
	# T-CONF-01：上钩等待 min>max 属非法配置，必须显式拒绝。
	if float(raw_min) > float(raw_max):
		return _fail(ERROR_MIN_GT_MAX)

	if not _is_integral(root["basket_capacity"]) or int(root["basket_capacity"]) < 1:
		return _fail(ERROR_BAD_CAPACITY)

	return {"ok": true, "error_code": "", "config": root.duplicate(true)}


static func _fail(error_code: String) -> Dictionary:
	return {"ok": false, "error_code": error_code, "config": {}}


static func _has_exact_keys(dict: Dictionary, keys: Array) -> bool:
	if dict.size() != keys.size():
		return false
	for key in keys:
		if not dict.has(key):
			return false
	return true


static func _is_finite_float(value: float) -> bool:
	# 纯运算实现（静态函数内不依赖全局数学内建）：仅有限数使 v - v == 0。
	return value - value == 0.0


static func _is_integral(value: Variant) -> bool:
	# Godot JSON 数字可能按 int 或 float 落地，双态判断（plan §6 R-2）。
	if value is int:
		return true
	if value is float:
		var v := float(value)
		return _is_finite_float(v) and float(int(v)) == v
	return false


static func _is_number_in_range(value: Variant, low: float, high: float) -> bool:
	if value is int:
		return float(value) >= low and float(value) <= high
	if value is float:
		var v := float(value)
		return _is_finite_float(v) and v >= low and v <= high
	return false
