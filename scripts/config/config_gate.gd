class_name ConfigGate
extends RefCounted
# CFG-001：经济/FSM 启动门禁（T-CONF-01「非法配置阻止经济系统启动」的机器可测形态）。
# 契约：任一配置 ok=false 即拒绝启动；不吞错、不部分放行；拒绝原因可枚举。
# 纯 RefCounted 数据层：无 Node 依赖、无副作用，供 FSM-001 / ECO-001 启动前调用。

const GATE_OK := ""


## catalog / runtime 均为 FishSpeciesCatalog.load_catalog / RuntimeConfig.load_config
## 的返回 Dictionary。任一 ok != true → false（返回 false 时绝不回填默认值）。
static func can_start_economy(catalog: Dictionary, runtime: Dictionary) -> bool:
	return _is_ok(catalog) and _is_ok(runtime)


## 拒绝原因列表（稳定字符串，形如 "catalog:DUP_ID" / "runtime:MIN_GT_MAX"）。
## 放行时返回空数组；供上层写结构化日志/用户提示（INTERFACES §1）。
static func blocked_reasons(catalog: Dictionary, runtime: Dictionary) -> PackedStringArray:
	var reasons := PackedStringArray()
	if not _is_ok(catalog):
		reasons.append("catalog:" + _code(catalog))
	if not _is_ok(runtime):
		reasons.append("runtime:" + _code(runtime))
	return reasons


static func _is_ok(result: Dictionary) -> bool:
	if typeof(result.get("ok", false)) != TYPE_BOOL or not result["ok"]:
		return false
	# ok=true 必须伴随空 error_code；防止半成品结果被放行。
	return String(result.get("error_code", GATE_OK)) == GATE_OK


static func _code(result: Dictionary) -> String:
	var code := String(result.get("error_code", ""))
	if code.is_empty():
		return "UNVERIFIED"
	return code
