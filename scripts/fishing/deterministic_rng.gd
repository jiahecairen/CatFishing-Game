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
const SNAPSHOT_VERSION := 1
const ERROR_BAD_SEED := "BAD_SEED"
const ERROR_BAD_SNAPSHOT := "BAD_SNAPSHOT"

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


## 当前运行状态（1..MODULUS-1）。供测试断言「拒绝路径不消耗 RNG」：拒绝前后读数必相等。
func get_state() -> int:
	return _state


## fail-closed 运行状态快照（review-followup #4 / review §3「可验证的状态读取/恢复」）。
## 与 checkpoint 四字段解耦：这是 RNG 续跑载体，SAVE-001 须自行持久化（见 report 移交项）。
func snapshot_state() -> Dictionary:
	return {"version": SNAPSHOT_VERSION, "seed": _seed, "state": _state}


## 从 snapshot_state() 结果恢复。任一非法（非字典 / 缺键 / 版本不符 / seed 或 state 越界 /
## 非整数 / 有多余键）→ ok=false 且完全不改内部状态（绝不部分恢复、绝不静默重置）。
func restore_state(snapshot: Variant) -> Dictionary:
	if not (snapshot is Dictionary):
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	var snap: Dictionary = snapshot
	if snap.size() != 3 or not snap.has("version") or not snap.has("seed") or not snap.has("state"):
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	if not (snap["version"] is int) or int(snap["version"]) != SNAPSHOT_VERSION:
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	var raw_seed: Variant = snap["seed"]
	var raw_state: Variant = snap["state"]
	if not (raw_seed is int) or not (raw_state is int):
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	if raw_seed < 1 or raw_seed >= MODULUS or raw_state < 1 or raw_state >= MODULUS:
		return {"ok": false, "error_code": ERROR_BAD_SNAPSHOT}
	_seed = int(raw_seed)
	_state = int(raw_state)
	return {"ok": true, "error_code": ""}
