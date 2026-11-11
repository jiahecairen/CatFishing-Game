class_name VirtualClock
extends RefCounted
# FSM-001：可控虚拟时钟（V01-W03 / SDD-175 / SDD-157 / plan §3）。
# 单调虚拟秒，供 FishingSystem 业务计时；与渲染 FPS（max_fps=30）完全解耦，
# 业务层禁止用 Engine.get_frames_drawn()/_process(delta) 帧计数替代本时钟推进。
# 不变量：纯 RefCounted 数据层；无 Node/_process、不读写 user://、无文件写入；
# 负数/NaN/Inf 拒绝（advance 返回 false 且状态不变），绝不部分推进。

const SNAPSHOT_VERSION := 1
const ERROR_BAD_SNAPSHOT := "BAD_SNAPSHOT"

var _now: float = 0.0


## 推进 seconds 秒。seconds 为负/NaN/Inf → 返回 false 且 now() 不变；0 允许（空推进）。
func advance(seconds: float) -> bool:
	if not _is_finite(seconds) or seconds < 0.0:
		return false
	_now += seconds
	return true


func now() -> float:
	return _now


func reset() -> void:
	_now = 0.0


## fail-closed 时钟快照（review-followup #4：恢复测试须从独立保存值恢复，而非共享对象）。
func snapshot_state() -> Dictionary:
	return {"version": SNAPSHOT_VERSION, "now": _now}


## 从 snapshot_state() 恢复。非字典/缺键/版本不符/now 非数值/负/NaN/Inf/多余键
## → ok=false 且 _now 完全不变（绝不部分恢复）。
func restore_state(snapshot: Variant) -> Dictionary:
	if not (snapshot is Dictionary):
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	var snap: Dictionary = snapshot
	if snap.size() != 2 or not snap.has("version") or not snap.has("now"):
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	if not (snap["version"] is int) or int(snap["version"]) != SNAPSHOT_VERSION:
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	var raw_now: Variant = snap["now"]
	if not _is_numeric(raw_now):
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	var seconds := float(raw_now)
	if not _is_finite(seconds) or seconds < 0.0:
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	_now = seconds
	return {"ok": true, "error_code": ""}


static func _is_finite(value: float) -> bool:
	# 纯运算判有限（对齐 CFG-001 先例）：仅有限数使 v - v == 0。
	return value - value == 0.0


static func _is_numeric(value: Variant) -> bool:
	return value is int or value is float
