class_name SaveFaults
extends RefCounted
# SAVE-001：测试专用故障注入登记表（plan §3/§4.2 步骤 0、review 再审查 #10）。
# 六个注入点：tmp_write / tmp_flush / backup / rename / quarantine / legacy_copy。
# 生产默认全关（全部 false）；本类不含任何产品行为，只做「哪个阶段本次要失败」的开关登记，
# 由 AtomicSaveService 在对应阶段查询。纯 RefCounted：无 Node/_process、不读写文件、
# 不触碰 user://；关闭注入后行为与不存在本类完全相同。

const STAGES := ["tmp_write", "tmp_flush", "backup", "rename", "quarantine", "legacy_copy"]
const ERROR_BAD_STAGE := "BAD_STAGE"

var _armed: Dictionary = {}


func _init() -> void:
	for stage in STAGES:
		_armed[stage] = false


## 武装/解除某注入点。未知阶段 → ok=false + BAD_STAGE，零改动。
func set_armed(stage: String, armed: bool) -> Dictionary:
	if not STAGES.has(stage):
		return {"ok": false, "code": ERROR_BAD_STAGE}
	_armed[stage] = armed
	return {"ok": true, "code": ""}


func is_armed(stage: String) -> bool:
	return bool(_armed.get(stage, false))


func disarm_all() -> void:
	for stage in STAGES:
		_armed[stage] = false


## 当前武装中的阶段列表（供测试断言/报告）。
func armed_stages() -> Array:
	var out: Array = []
	for stage in STAGES:
		if is_armed(stage):
			out.append(stage)
	return out
