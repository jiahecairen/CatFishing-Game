class_name DeterministicRng
extends RefCounted
# FSM-001：确定性 RNG（INTERFACES §4 / ARCHITECTURE §3「随机可重放」/ plan §3、§6 R-2）。
# Lehmer 最小标准 LCG：state = 48271 * state mod (2^31 - 1)，state ∈ [1, m-1]。
# 纯 GDScript int64 整数乘法（乘积 < 2^47，不依赖回绕/浮点），不用 Godot RandomNumberGenerator，
# 避免引擎版本间算法漂移破坏跨版本逐事件复现（T-TIME-01）。
# 不变量：纯 RefCounted 数据层；无 Node/_process、不读写 user://、无任何文件写入；
# 种子 0/越界显式拒绝（BAD_SEED），绝不静默重置。

const MULTIPLIER := 48271
const MODULUS := 2147483647  # 2^31 - 1（素数）
const ERROR_BAD_SEED := "BAD_SEED"

var _state: int = 1
var _seed: int = 1


## 显式设定种子。seed_value ∈ [1, MODULUS-1]；非法返回 {ok:false, error_code:"BAD_SEED"} 且不改内部状态。
func set_seed(seed_value: int) -> Dictionary:
	if seed_value < 1 or seed_value >= MODULUS:
		return {"ok": false, "error_code": ERROR_BAD_SEED}
	_state = seed_value
	_seed = seed_value
	return {"ok": true, "error_code": ""}


func get_seed() -> int:
	return _seed


## 下一个原始值，∈ [1, MODULUS-1]。
func next_int() -> int:
	_state = (MULTIPLIER * _state) % MODULUS
	return _state


## (0,1) 开区间均匀值：state/m，state ∈ [1,m-1] ⇒ 严格介于 0 与 1。
func next_unit() -> float:
	return float(next_int()) / float(MODULUS)


## [lo, hi] 闭区间均匀整数（含端点）。lo>hi 属调用方错误，返回 lo 不抛异常（纯数据层）。
func next_int_inclusive(lo: int, hi: int) -> int:
	if hi < lo:
		return lo
	var span := hi - lo + 1
	return lo + int(next_int() % span)
