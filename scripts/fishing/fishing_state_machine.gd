class_name FishingStateMachine
extends RefCounted
# FSM-001：纯业务捕鱼状态机（INTERFACES §4、ARCHITECTURE §3、SDD V01-F01/F02/W03/T01、
# DECISION SDD-143/175/176/177、OPEN-001 裁定、tasks/evidence/FSM-001/plan.md §4）。
# 状态：IDLE/PAUSED + CASTING→WAITING→HOOKED→REELING→SETTLEMENT。
# 不变量（plan §4）：
# - 纯 RefCounted 数据层：无 Node/_process/_physics_process、无 Engine.time_scale/
#   get_frames_drawn、不读写 user://、无任何文件写入；计时只用注入 VirtualClock 的有效秒。
# - 每次 tick_effective 至多一个状态转换；越过阈值的剩余秒数结转到下一调用（INTERFACES §4）。
# - PAUSED/IDLE/SETTLEMENT 期间 tick 不产生事件、不消耗有效时间；负数/NaN/Inf tick 拒绝。
# - catch_event_id、wait_seconds、鱼种均由注入 DeterministicRng 抽样：同 seed/配置/时钟步/
#   动作序列 ⇒ 逐事件复现（T-TIME-01/02）。拒绝路径绝不消耗 RNG。
# - 满篓阻断经 can_cast(GameState) 只读判定；本类绝不写 GameState 的 wallet/basket/
#   processed ids（属 ECO-001）；只发候选事务，绝不扣鱼加币（ARCHITECTURE §2）。
# - 经济参数（20/60s、30FPS、容量 10、鱼价权重）只经 ConfigGate/配置读取，本类不修改。
# - 转换白名单外一律拒绝并记稳定错误码 BAD_TRANSITION 入内存 transition_log（不写文件，
#   LOG-001 复用）。

enum State {IDLE, CASTING, WAITING, HOOKED, REELING, SETTLEMENT, PAUSED}

const STATE_NAMES := ["IDLE", "CASTING", "WAITING", "HOOKED", "REELING", "SETTLEMENT", "PAUSED"]

# 稳定错误码（T-FSM-01 拒绝侧可记录、可断言）
const ERROR_NOT_INITIALIZED := "NOT_INITIALIZED"
const ERROR_BAD_TRANSITION := "BAD_TRANSITION"
const ERROR_BAD_TICK := "BAD_TICK"
const ERROR_BAD_CHECKPOINT := "BAD_CHECKPOINT"
const ERROR_BAD_INJECTION := "BAD_INJECTION"
const ERROR_BAD_EVENT_ID := "BAD_EVENT_ID"
const ERROR_EVENT_ID_MISMATCH := "EVENT_ID_MISMATCH"
const ERROR_CANDIDATE_ISSUED := "CANDIDATE_ALREADY_ISSUED"
const ERROR_ALREADY_APPLIED := "AlreadyApplied"  # SDD-143 幂等重试（plan §4 原文命名）

# 占位阶段时长（整数秒；OPEN-004 裁定：表现时长不影响 20–60 s 等待与经济。
# 属实现内常量，不新增配置键——runtime_config schema 固定 5 键，扩键须用户批准）。
const CASTING_SEC := 1.0
const HOOKED_SEC := 1.0
const REELING_SEC := 1.0

## 内存内结构化转换/拒绝日志（供测试断言与 LOG-001 后续复用；不写任何文件）。
var transition_log: Array = []

var _initialized := false
var _catalog: Dictionary = {}
var _runtime: Dictionary = {}
var _config: Dictionary = {}
var _species: Array = []
var _rng: DeterministicRng = null
var _clock: VirtualClock = null
var _state: int = State.IDLE
var _paused_from: int = -1
var _current_event_id := ""
var _last_acked_event_id := ""
var _wait_seconds := 0
var _stage_elapsed := 0.0  # 当前计时阶段已消耗的有效秒数（含上一调用结转的余量）
var _candidate_issued := false
var _log_seq := 0


## 合法启动或从 checkpoint 恢复。catalog/runtime 为 CFG-001 校验器返回信封；
## 先过 ConfigGate.can_start_economy，任一非法 → ok=false + "catalog:<CODE>"/"runtime:<CODE>"。
## recovered_checkpoint == {} 为全新启动；否则按 {state, event_id, wait_seconds,
## elapsed_effective_seconds} 恰 4 键恢复（PAUSED 无 paused_from 载体，拒绝 BAD_CHECKPOINT）。
func initialize(catalog: Dictionary, runtime: Dictionary, rng: DeterministicRng, clock: VirtualClock, recovered_checkpoint: Dictionary) -> Dictionary:
	# —— 先全部校验，后一次性提交：失败路径零副作用 ——
	if rng == null or clock == null:
		return _init_fail(ERROR_BAD_INJECTION)
	if not ConfigGate.can_start_economy(catalog, runtime):
		var reasons := ConfigGate.blocked_reasons(catalog, runtime)
		var code := ";".join(reasons)
		if code.is_empty():
			code = "gate:UNVERIFIED"
		return _init_fail(code)

	var resume_state := State.IDLE
	var resume_event_id := ""
	var resume_wait := 0
	var resume_elapsed := 0.0
	if not recovered_checkpoint.is_empty():
		if recovered_checkpoint.size() != 4 \
				or not recovered_checkpoint.has("state") \
				or not recovered_checkpoint.has("event_id") \
				or not recovered_checkpoint.has("wait_seconds") \
				or not recovered_checkpoint.has("elapsed_effective_seconds"):
			return _init_fail(ERROR_BAD_CHECKPOINT)
		var raw_state: Variant = recovered_checkpoint["state"]
		if not (raw_state is String) or not STATE_NAMES.has(raw_state):
			return _init_fail(ERROR_BAD_CHECKPOINT)
		resume_state = STATE_NAMES.find(String(raw_state))
		if resume_state == State.PAUSED:
			# schema 无 paused_from 载体，无法安全恢复暂停来源 → 显式拒绝，不猜测。
			return _init_fail(ERROR_BAD_CHECKPOINT)
		var raw_elapsed: Variant = recovered_checkpoint["elapsed_effective_seconds"]
		if not _is_numeric(raw_elapsed):
			return _init_fail(ERROR_BAD_CHECKPOINT)
		resume_elapsed = float(raw_elapsed)
		if not _is_finite(resume_elapsed) or resume_elapsed < 0.0:
			return _init_fail(ERROR_BAD_CHECKPOINT)
		var raw_event: Variant = recovered_checkpoint["event_id"]
		var raw_wait: Variant = recovered_checkpoint["wait_seconds"]
		if resume_state == State.IDLE:
			if raw_event != null or raw_wait != null or resume_elapsed != 0.0:
				return _init_fail(ERROR_BAD_CHECKPOINT)
		else:
			if not (raw_event is String) or String(raw_event).is_empty():
				return _init_fail(ERROR_BAD_CHECKPOINT)
			resume_event_id = String(raw_event)
			if resume_state == State.WAITING:
				if not (raw_wait is int) or int(raw_wait) < 0:
					return _init_fail(ERROR_BAD_CHECKPOINT)
				resume_wait = int(raw_wait)
			elif raw_wait != null:
				return _init_fail(ERROR_BAD_CHECKPOINT)

	# —— 提交 ——
	_catalog = catalog.duplicate(true)
	_runtime = runtime.duplicate(true)
	_config = _runtime["config"]
	_species = _catalog["species"]
	_rng = rng
	_clock = clock
	_state = resume_state
	_current_event_id = resume_event_id
	_last_acked_event_id = ""
	_candidate_issued = false
	_paused_from = -1
	_wait_seconds = resume_wait
	_stage_elapsed = resume_elapsed
	_initialized = true
	_append_log("initialize", STATE_NAMES[resume_state], STATE_NAMES[resume_state], "", _current_event_id, {})
	return {"ok": true, "error_code": "", "state": STATE_NAMES[_state]}


## 满篓/未初始化/非 IDLE 时不可抛竿（SDD V01-E01、SDD-172；容量 10 仅候选值，只读）。
func can_cast(state: GameState) -> bool:
	if not _initialized or state == null:
		return false
	if _state != State.IDLE:
		return false
	return state.basket.size() < int(state.basket_capacity)


## 仅 IDLE 可抛竿；catch_event_id 与 wait_seconds 均由注入 RNG 确定性抽样（T-TIME-01）。
## wait_seconds ∈ [ceil(min), floor(max)] 整数秒，当前配置即 20–60；拒绝路径不消耗 RNG。
func request_cast() -> Dictionary:
	if not _initialized:
		_append_log("request_cast", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_NOT_INITIALIZED, "", {})
		return {"ok": false, "rejected_reason": ERROR_NOT_INITIALIZED, "catch_event_id": "", "wait_seconds": 0}
	if _state != State.IDLE:
		_append_log("request_cast", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_BAD_TRANSITION, _current_event_id, {})
		return {"ok": false, "rejected_reason": ERROR_BAD_TRANSITION, "catch_event_id": "", "wait_seconds": 0}
	var lo := int(ceilf(float(_config["bite_wait_min_sec"])))
	var hi := int(floorf(float(_config["bite_wait_max_sec"])))
	var event_id := "catch-%d-%d" % [_rng.next_int(), _rng.next_int()]
	_wait_seconds = _rng.next_int_inclusive(lo, hi)
	_current_event_id = event_id
	_last_acked_event_id = ""
	_candidate_issued = false
	# 注意：不清零 _stage_elapsed——上一周期末尾结转的过冲秒属于本次 CASTING 的有效时间，
	# 丢弃它会让事件时间轴随 tick 步长改变（违反 T-TIME-02 步长不变性）。
	_emit_transition(State.IDLE, State.CASTING)
	return {"ok": true, "rejected_reason": "", "catch_event_id": event_id, "wait_seconds": _wait_seconds}


## 仅 CASTING/WAITING/HOOKED/REELING 消耗有效时间；每次调用至多一个状态转换，
## 越过阈值的剩余秒数结转下一调用（INTERFACES §4「安全最多一次推进」）。
## IDLE/SETTLEMENT/PAUSED 不产生事件、不推进时钟；seconds < 0 / NaN / Inf → 拒绝且状态不变。
func tick_effective(seconds: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _is_finite(seconds) or seconds < 0.0:
		_append_log("tick_effective", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_BAD_TICK, _current_event_id, {"seconds": seconds})
		return out
	if not _initialized:
		_append_log("tick_effective", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_NOT_INITIALIZED, "", {"seconds": seconds})
		return out
	if _state != State.CASTING and _state != State.WAITING \
			and _state != State.HOOKED and _state != State.REELING:
		return out  # IDLE / SETTLEMENT / PAUSED：零事件、零有效时间消耗（T-TIME-03 暂停侧）
	_clock.advance(seconds)
	_stage_elapsed += seconds
	if _stage_elapsed >= _stage_duration():
		_stage_elapsed -= _stage_duration()
		out.append(_emit_transition(_state, _next_timing_state(_state)))
	return out


## 仅 SETTLEMENT 可调；鱼种由注入 RNG 按 catch_weight/sum 加权确定（可重放）。
## 只发出候选事务，绝不修改金币/鱼篓（ARCHITECTURE §2）。重复签发 → CANDIDATE_ALREADY_ISSUED。
func produce_catch_candidate() -> Dictionary:
	if not _initialized:
		_append_log("produce_catch_candidate", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_NOT_INITIALIZED, "", {})
		return {"ok": false, "code": ERROR_NOT_INITIALIZED}
	if _state != State.SETTLEMENT:
		_append_log("produce_catch_candidate", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_BAD_TRANSITION, _current_event_id, {})
		return {"ok": false, "code": ERROR_BAD_TRANSITION}
	if _candidate_issued:
		_append_log("produce_catch_candidate", "SETTLEMENT", "SETTLEMENT", ERROR_CANDIDATE_ISSUED, _current_event_id, {})
		return {"ok": false, "code": ERROR_CANDIDATE_ISSUED}
	var total_weight := 0.0
	for entry in _species:
		total_weight += float(entry["catch_weight"])
	var unit := _rng.next_unit()
	var chosen: Dictionary = _species[_species.size() - 1]
	var acc := 0.0
	for entry in _species:
		acc += float(entry["catch_weight"]) / total_weight
		if unit < acc:
			chosen = entry
			break
	_candidate_issued = true
	_append_log("produce_catch_candidate", "SETTLEMENT", "SETTLEMENT", "", _current_event_id, {"species_id": String(chosen["id"])})
	return {
		"ok": true,
		"code": "",
		"catch_event_id": _current_event_id,
		"species_id": String(chosen["id"]),
		"weight_snapshot": {
			"catch_weight": chosen["catch_weight"],
			"base_price": chosen["base_price"],
			"rarity": chosen["rarity"],
		},
		"caught_at_clock": _logical_time(),
	}


## 结算幂等提交（SDD-143）：committed=true 且 ID 匹配当前事件 → SETTLEMENT→IDLE；
## 同 ID 重复 ack → AlreadyApplied（不重复推进、不重发候选）；committed=false 停留可安全重试。
func ack_settlement(catch_event_id: String, committed: bool) -> Dictionary:
	if not _initialized:
		_append_log("ack_settlement", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_NOT_INITIALIZED, catch_event_id, {})
		return {"ok": false, "next_state": STATE_NAMES[_state], "code": ERROR_NOT_INITIALIZED}
	if _state == State.SETTLEMENT:
		if catch_event_id.is_empty():
			_append_log("ack_settlement", "SETTLEMENT", "SETTLEMENT", ERROR_BAD_EVENT_ID, catch_event_id, {})
			return {"ok": false, "next_state": "SETTLEMENT", "code": ERROR_BAD_EVENT_ID}
		if catch_event_id != _current_event_id:
			_append_log("ack_settlement", "SETTLEMENT", "SETTLEMENT", ERROR_EVENT_ID_MISMATCH, catch_event_id, {})
			return {"ok": false, "next_state": "SETTLEMENT", "code": ERROR_EVENT_ID_MISMATCH}
		if not committed:
			_append_log("ack_settlement", "SETTLEMENT", "SETTLEMENT", "NOT_COMMITTED", catch_event_id, {})
			return {"ok": true, "next_state": "SETTLEMENT", "code": ""}
		var event_id := _current_event_id
		_last_acked_event_id = event_id
		_emit_transition(State.SETTLEMENT, State.IDLE)
		_current_event_id = ""
		_candidate_issued = false
		_wait_seconds = 0
		# _stage_elapsed 保留结转余量（见 request_cast 注释）。
		return {"ok": true, "next_state": "IDLE", "code": ""}
	# 非 SETTLEMENT：若该 ID 恰为上一笔已提交结算 → 幂等重试；否则非法转换。
	if not catch_event_id.is_empty() and catch_event_id == _last_acked_event_id:
		_append_log("ack_settlement", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_ALREADY_APPLIED, catch_event_id, {})
		return {"ok": false, "next_state": STATE_NAMES[_state], "code": ERROR_ALREADY_APPLIED}
	_append_log("ack_settlement", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_BAD_TRANSITION, catch_event_id, {})
	return {"ok": false, "next_state": STATE_NAMES[_state], "code": ERROR_BAD_TRANSITION}


## 任意活动态（CASTING..SETTLEMENT）→ PAUSED，记录原因（OPEN-001：隐藏=暂停，非离线收益）。
func pause(reason: String) -> Dictionary:
	if not _initialized:
		_append_log("pause", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_NOT_INITIALIZED, "", {"reason": reason})
		return {"ok": false, "code": ERROR_NOT_INITIALIZED, "paused_from": ""}
	if _state == State.IDLE or _state == State.PAUSED:
		_append_log("pause", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_BAD_TRANSITION, _current_event_id, {"reason": reason})
		return {"ok": false, "code": ERROR_BAD_TRANSITION, "paused_from": ""}
	var from: String = STATE_NAMES[_state]
	_paused_from = _state
	_state = State.PAUSED
	_append_log("pause", from, "PAUSED", "", _current_event_id, {"reason": reason})
	return {"ok": true, "code": "", "paused_from": from}


## 仅 PAUSED 可恢复；暂停期间 tick 从未消耗有效时间（tick_effective 零推进），
## 恢复即回到暂停前的计时位置（_stage_elapsed 原样保留）。
func resume_if_safe() -> Dictionary:
	if not _initialized:
		_append_log("resume_if_safe", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_NOT_INITIALIZED, "", {})
		return {"ok": false, "resumed_from": "", "code": ERROR_NOT_INITIALIZED}
	if _state != State.PAUSED:
		_append_log("resume_if_safe", STATE_NAMES[_state], STATE_NAMES[_state], ERROR_BAD_TRANSITION, _current_event_id, {})
		return {"ok": false, "resumed_from": "", "code": ERROR_BAD_TRANSITION}
	var from: String = STATE_NAMES[_paused_from]
	_state = _paused_from
	_paused_from = -1
	_append_log("resume_if_safe", "PAUSED", from, "", _current_event_id, {})
	return {"ok": true, "resumed_from": from, "code": ""}


## 可序列化检查点，镜像 GameState schema v1 的 fishing_checkpoint（供 SAVE-001 使用）。
func snapshot_checkpoint() -> Dictionary:
	var in_cycle := _state == State.CASTING or _state == State.WAITING \
			or _state == State.HOOKED or _state == State.REELING or _state == State.SETTLEMENT
	return {
		"state": STATE_NAMES[_state],
		"event_id": _current_event_id if in_cycle else null,
		"wait_seconds": _wait_seconds if in_cycle else null,
		"elapsed_effective_seconds": _stage_elapsed if in_cycle else 0.0,
	}


func get_state() -> int:
	return _state


func get_event_id() -> String:
	return _current_event_id


## 当前有效业务时刻（虚拟秒）；IDLE/SETTLEMENT/PAUSED 期间冻结（不消耗有效时间）。
func current_effective_time() -> float:
	return _logical_time()


func get_transition_log() -> Array:
	return transition_log.duplicate(true)


static func state_name(state: int) -> String:
	if state >= 0 and state < STATE_NAMES.size():
		return STATE_NAMES[state]
	return "UNKNOWN"


# ---- 内部实现 ----

func _stage_duration() -> float:
	match _state:
		State.CASTING:
			return CASTING_SEC
		State.WAITING:
			return float(_wait_seconds)
		State.HOOKED:
			return HOOKED_SEC
		State.REELING:
			return REELING_SEC
	return INF  # 理论不可达：调用点已限定计时态


func _next_timing_state(state: int) -> int:
	match state:
		State.CASTING:
			return State.WAITING
		State.WAITING:
			return State.HOOKED
		State.HOOKED:
			return State.REELING
	return State.SETTLEMENT  # REELING → SETTLEMENT


func _logical_time() -> float:
	if _clock == null:
		return 0.0
	# 结转余量 = 本次 tick 越过阈值的过冲量；时刻 = 时钟 - 余量 = 阈值跨越的精确逻辑时刻，
	# 保证 0.5/1/2 s 等二进制精确步长下事件时间轴逐值相同（T-TIME-02）。
	return _clock.now() - _stage_elapsed


func _emit_transition(from: int, to: int) -> Dictionary:
	_state = to
	var event := {
		"kind": "transition",
		"action": "transition",
		"from_state": STATE_NAMES[from],
		"to_state": STATE_NAMES[to],
		"at_clock": _logical_time(),
		"event_id": _current_event_id,
		"code": "",
	}
	_append_log("transition", STATE_NAMES[from], STATE_NAMES[to], "", _current_event_id, {})
	return event


func _init_fail(code: String) -> Dictionary:
	# 失败零副作用：不提交配置/时钟/RNG，FSM 停留当前态（新实例即 IDLE），拒绝后续抛竿。
	return {"ok": false, "error_code": code, "state": STATE_NAMES[_state]}


func _append_log(action: String, from_state: String, to_state: String, code: String, event_id: String, extra: Dictionary) -> void:
	var entry := {
		"seq": _log_seq,
		"action": action,
		"from_state": from_state,
		"to_state": to_state,
		"at_clock": _logical_time(),
		"event_id": event_id,
		"code": code,
	}
	var keys := extra.keys()
	keys.sort()
	for key in keys:
		entry[key] = extra[key]
	_log_seq += 1
	transition_log.append(entry)


static func _is_numeric(value: Variant) -> bool:
	return value is int or value is float


static func _is_finite(value: float) -> bool:
	# 纯运算判有限（对齐 CFG-001 先例）：仅有限数使 v - v == 0。
	return value - value == 0.0
