class_name ConfigGate
extends RefCounted
# CFG-001：经济/FSM 启动门禁（T-CONF-01「非法配置阻止经济系统启动」的机器可测形态）。
# 契约：任一配置 ok=false 即拒绝启动；不吞错、不部分放行；拒绝原因可枚举。
# 纯 RefCounted 数据层：无 Node 依赖、无副作用，供 FSM-001 / ECO-001 启动前调用。

## catalog / runtime 均为 FishSpeciesCatalog.load_catalog / RuntimeConfig.load_config
## 的返回 Dictionary。任一 ok != true → false（返回 false 时绝不回填默认值）。
static func can_start_economy(catalog: Dictionary, runtime: Dictionary) -> bool:
	return _is_catalog_ok(catalog) and _is_runtime_ok(runtime)


## 拒绝原因列表（稳定字符串，形如 "catalog:DUP_ID" / "runtime:MIN_GT_MAX"）。
## 放行时返回空数组；供上层写结构化日志/用户提示（INTERFACES §1）。
static func blocked_reasons(catalog: Dictionary, runtime: Dictionary) -> PackedStringArray:
	var reasons := PackedStringArray()
	if not _is_catalog_ok(catalog):
		reasons.append("catalog:" + _code(catalog))
	if not _is_runtime_ok(runtime):
		reasons.append("runtime:" + _code(runtime))
	return reasons


static func _has_success_envelope(result: Dictionary) -> bool:
	if not result.has("ok") or typeof(result["ok"]) != TYPE_BOOL or not result["ok"]:
		return false
	# 成功结果必须显式带空字符串错误码；缺字段不能被 get() 默认成成功。
	if not result.has("error_code") or not (result["error_code"] is String):
		return false
	return String(result["error_code"]).is_empty()


static func _is_catalog_ok(result: Dictionary) -> bool:
	if not _has_success_envelope(result) or not result.has("species"):
		return false
	var species: Variant = result["species"]
	if not (species is Array):
		return false
	var entries: Array = species
	return not entries.is_empty()


static func _is_runtime_ok(result: Dictionary) -> bool:
	if not _has_success_envelope(result) or not result.has("config"):
		return false
	var config: Variant = result["config"]
	if not (config is Dictionary):
		return false
	var values: Dictionary = config
	var required_keys := ["config_version", "visible_fps", "bite_wait_min_sec", "bite_wait_max_sec", "basket_capacity"]
	if values.size() != required_keys.size():
		return false
	for key in required_keys:
		if not values.has(key):
			return false
	return true


static func _code(result: Dictionary) -> String:
	var code := String(result.get("error_code", ""))
	if code.is_empty():
		return "UNVERIFIED"
	return code
