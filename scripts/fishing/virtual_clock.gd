class_name VirtualClock
extends RefCounted
# FSM-001：可控虚拟时钟（V01-W03 / SDD-175 / SDD-157 / plan §3）。
# 单调虚拟秒，供 FishingSystem 业务计时；与渲染 FPS（max_fps=30）完全解耦，
# 业务层禁止用 Engine.get_frames_drawn()/_process(delta) 帧计数替代本时钟推进。
# 不变量：纯 RefCounted 数据层；无 Node/_process、不读写 user://、无文件写入；
# 负数/NaN/Inf 拒绝（advance 返回 false 且状态不变），绝不部分推进。

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


static func _is_finite(value: float) -> bool:
	# 纯运算判有限（对齐 CFG-001 先例）：仅有限数使 v - v == 0。
	return value - value == 0.0
