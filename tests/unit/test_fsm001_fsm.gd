extends SceneTree
# FSM-001 headless FSM 单测（T-FSM-01、T-TIME-01/02/03 暂停侧、T-CONF-01 交界、V01-F01/F02/W03/T01、
# SDD-143/175/176/177、OPEN-001 裁定、plan §5 覆盖矩阵 F1–F11）。
# 运行：Godot --headless --path <repo> -s res://tests/unit/test_fsm001_fsm.gd
#   （由 tests/unit/run_fsm001_checks.py 统一调度；先跑 --editor --quit 导入以刷新全局类缓存。）
# 约定与 CORE/CFG-001 一致：全部通过打印 "FSM001 FSM PASS" 且 quit(0)；
# 首个失败打印 "FSM001 FSM FAIL: <step>" 且 quit(1)。
# 纯数据层测试：只读 res:// 配置/夹具，不写文件、不触碰 user://、不依赖 Node/帧计数。

const RngScript := preload("res://scripts/fishing/deterministic_rng.gd")
const ClockScript := preload("res://scripts/fishing/virtual_clock.gd")
const FsmScript := preload("res://scripts/fishing/fishing_state_machine.gd")
const CatalogScript := preload("res://scripts/config/fish_species_catalog.gd")
const RuntimeScript := preload("res://scripts/config/runtime_config.gd")

const FIXTURE_DIR := "res://tests/unit/fixtures/cfg001/"
const SPECIES_IDS := ["river_carp", "silver_perch", "golden_trout"]
const WAIT_LO := 20
const WAIT_HI := 60

var _catalog: Dictionary
var _runtime: Dictionary


func _initialize() -> void:
	_catalog = CatalogScript.load_catalog("res://data/fish_species.json")
	_runtime = RuntimeScript.load_config("res://data/runtime_config.json")
	if _catalog.get("ok", false) != true or _runtime.get("ok", false) != true:
		_fail_ret("R0 base configs invalid (must pass CFG-001 validators first)")
		return
	if not _f1():
		return
	if not _f2():
		return
	if not _f3():
		return
	if not _f4():
		return
	if not _f5():
		return
	if not _f6():
		return
	if not _f7():
		return
	if not _f8():
		return
	if not _f9():
		return
	if not _f10():
		return
	if not _f11():
		return
	print("FSM001 FSM PASS")
	quit(0)


# ---- F1：合法完整周期 + transition_log 顺序完整（T-FSM-01 合法侧 / V01-F01）----
func _f1() -> bool:
	var parts := _make(101)
	if parts.is_empty():
		return _fail_ret("F1 setup")
	var fsm: FishingStateMachine = parts[0]
	var rc: Dictionary = fsm.request_cast()
	if rc.get("ok") != true or not String(rc["catch_event_id"]).begins_with("catch-") \
			or not (rc["wait_seconds"] is int) or int(rc["wait_seconds"]) < WAIT_LO \
			or int(rc["wait_seconds"]) > WAIT_HI:
		return _fail_ret("F1 request_cast envelope")
	var e1: Array = fsm.tick_effective(5.0)
	if e1.size() != 1 or e1[0]["to_state"] != "WAITING" or e1[0]["code"] != "":
		return _fail_ret("F1 CASTING->WAITING")
	var e2: Array = fsm.tick_effective(200.0)
	if e2.size() != 1 or e2[0]["to_state"] != "HOOKED":
		return _fail_ret("F1 WAITING->HOOKED (upper bound + margin)")
	var e3: Array = fsm.tick_effective(1.0)
	if e3.size() != 1 or e3[0]["to_state"] != "REELING":
		return _fail_ret("F1 HOOKED->REELING")
	var e4: Array = fsm.tick_effective(1.0)
	if e4.size() != 1 or e4[0]["to_state"] != "SETTLEMENT":
		return _fail_ret("F1 REELING->SETTLEMENT")
	var cand: Dictionary = fsm.produce_catch_candidate()
	if cand.get("ok") != true or not SPECIES_IDS.has(cand["species_id"]) \
			or (cand["weight_snapshot"] as Dictionary).is_empty() \
			or String(cand["catch_event_id"]) != String(rc["catch_event_id"]) \
			or not (cand["caught_at_clock"] is float):
		return _fail_ret("F1 candidate envelope")
	var ack: Dictionary = fsm.ack_settlement(String(cand["catch_event_id"]), true)
	if ack.get("ok") != true or ack["next_state"] != "IDLE" or fsm.get_state() != FsmScript.State.IDLE:
		return _fail_ret("F1 ack->IDLE")
	var order := []
	for entry in fsm.get_transition_log():
		if entry["action"] == "transition":
			order.append("%s->%s" % [entry["from_state"], entry["to_state"]])
	var wanted := ["IDLE->CASTING", "CASTING->WAITING", "WAITING->HOOKED", "HOOKED->REELING", "REELING->SETTLEMENT", "SETTLEMENT->IDLE"]
	if order != wanted:
		return _fail_ret("F1 transition order %s" % [str(order)])
	return true


# ---- F2：非法转换矩阵（T-FSM-01 拒绝侧 + 未完成结算不进下次抛竿 + 拒绝不消耗 RNG）----
func _f2() -> bool:
	# 未初始化
	var bare: FishingStateMachine = FsmScript.new()
	if bare.get_state() != FsmScript.State.IDLE:
		return _fail_ret("F2 bare FSM must start IDLE")
	if (bare.tick_effective(1.0) as Array).size() != 0:
		return _fail_ret("F2 uninitialized tick must yield 0 events")
	if String(bare.request_cast()["rejected_reason"]) != "NOT_INITIALIZED":
		return _fail_ret("F2 uninitialized request_cast code")
	if bare.can_cast(GameState.new()):
		return _fail_ret("F2 uninitialized can_cast must be false")
	var inject_bad: Dictionary = bare.initialize(_catalog, _runtime, null, null, {})
	if inject_bad["ok"] != false or inject_bad["error_code"] != "BAD_INJECTION":
		return _fail_ret("F2 null injection must be BAD_INJECTION")
	if String(bare.ack_settlement("x", true)["code"]) != "NOT_INITIALIZED":
		return _fail_ret("F2 uninitialized ack code")
	# 活动态拒绝
	var parts := _make(31)
	if parts.is_empty():
		return _fail_ret("F2 setup")
	var fsm: FishingStateMachine = parts[0]
	fsm.request_cast()  # → CASTING
	if (fsm.tick_effective(-1.0) as Array).size() != 0:
		return _fail_ret("F2 negative tick rejected")
	if (fsm.tick_effective(NAN) as Array).size() != 0:
		return _fail_ret("F2 NaN tick rejected")
	if (fsm.tick_effective(INF) as Array).size() != 0:
		return _fail_ret("F2 Inf tick rejected")
	if fsm.get_state() != FsmScript.State.CASTING:
		return _fail_ret("F2 invalid tick must not change state")
	if String(fsm.ack_settlement("nope", true)["code"]) != "BAD_TRANSITION":
		return _fail_ret("F2 ack in CASTING code")
	var e1: Array = fsm.tick_effective(2.0)
	if e1.size() != 1 or e1[0]["to_state"] != "WAITING":
		return _fail_ret("F2 enter WAITING")
	if String(fsm.produce_catch_candidate()["code"]) != "BAD_TRANSITION":
		return _fail_ret("F2 produce in WAITING code")
	if String(fsm.request_cast()["rejected_reason"]) != "BAD_TRANSITION":
		return _fail_ret("F2 cast in WAITING code")
	var p: Dictionary = fsm.pause("window_hidden")
	if p.get("ok") != true or p["paused_from"] != "WAITING":
		return _fail_ret("F2 pause WAITING")
	if String(fsm.request_cast()["rejected_reason"]) != "BAD_TRANSITION":
		return _fail_ret("F2 cast in PAUSED code")
	if p["ok"] != false and fsm.pause("again")["ok"] != false:
		return _fail_ret("F2 double pause")
	if String(fsm.pause("again")["code"]) != "BAD_TRANSITION":
		return _fail_ret("F2 pause in PAUSED code")
	var r: Dictionary = fsm.resume_if_safe()
	if r.get("ok") != true or r["resumed_from"] != "WAITING":
		return _fail_ret("F2 resume WAITING")
	# SETTLEMENT 中：未 ack 拒绝抛竿、空/错 ID、重复候选
	fsm.tick_effective(200.0)  # → HOOKED
	fsm.tick_effective(0.5)    # → REELING
	fsm.tick_effective(0.5)    # → SETTLEMENT
	if fsm.get_state() != FsmScript.State.SETTLEMENT:
		return _fail_ret("F2 enter SETTLEMENT")
	if String(fsm.request_cast()["rejected_reason"]) != "BAD_TRANSITION":
		return _fail_ret("F2 unacked settlement blocks next cast")
	if fsm.produce_catch_candidate()["ok"] != true:
		return _fail_ret("F2 produce in SETTLEMENT")
	if String(fsm.produce_catch_candidate()["code"]) != "CANDIDATE_ALREADY_ISSUED":
		return _fail_ret("F2 duplicate candidate code")
	if String(fsm.ack_settlement("", true)["code"]) != "BAD_EVENT_ID":
		return _fail_ret("F2 empty event id code")
	if String(fsm.ack_settlement("catch-9-9", true)["code"]) != "EVENT_ID_MISMATCH":
		return _fail_ret("F2 mismatched event id code")
	var bad_count := 0
	for entry in fsm.get_transition_log():
		if entry["code"] == "BAD_TRANSITION":
			bad_count += 1
	if bad_count < 6:
		return _fail_ret("F2 expected >=6 recorded BAD_TRANSITION, got %d" % bad_count)
	# 拒绝路径不消耗 RNG：同种子下带拒绝史与干净史的首次抽样必须一致
	var a := _make(41)
	var b := _make(41)
	if a.is_empty() or b.is_empty():
		return _fail_ret("F2 rng-purity setup")
	var fsm_a: FishingStateMachine = a[0]
	var fsm_b: FishingStateMachine = b[0]
	fsm_a.tick_effective(-5.0)
	fsm_a.ack_settlement("ghost", true)
	fsm_a.resume_if_safe()
	fsm_a.produce_catch_candidate()
	var rc_a: Dictionary = fsm_a.request_cast()
	var rc_b: Dictionary = fsm_b.request_cast()
	if int(rc_a["wait_seconds"]) != int(rc_b["wait_seconds"]) \
			or String(rc_a["catch_event_id"]) != String(rc_b["catch_event_id"]):
		return _fail_ret("F2 rejections must not consume RNG")
	return true


# ---- F3：RNG/Clock 单元 + 千次采样落 20–60 整数秒、非钉死（T-TIME-01）----
func _f3() -> bool:
	var rng: DeterministicRng = RngScript.new()
	if String(rng.set_seed(0)["error_code"]) != "BAD_SEED":
		return _fail_ret("F3 seed 0 must be BAD_SEED")
	if rng.set_seed(-5)["ok"] != false or rng.set_seed(2147483647)["ok"] != false:
		return _fail_ret("F3 out-of-range seed rejected")
	if rng.set_seed(2147483646)["ok"] != true:
		return _fail_ret("F3 max seed accepted")
	var r1: DeterministicRng = RngScript.new()
	var r2: DeterministicRng = RngScript.new()
	r1.set_seed(5)
	r2.set_seed(5)
	for i in 1000:
		var v := r1.next_int()
		if v != r2.next_int() or v < 1 or v >= 2147483647:
			return _fail_ret("F3 next_int determinism/range")
		var u := r1.next_unit()
		if u != r2.next_unit() or u <= 0.0 or u >= 1.0:
			return _fail_ret("F3 next_unit determinism/open-interval")
	var r3: DeterministicRng = RngScript.new()
	r3.set_seed(9)
	for i in 5000:
		var w0 := r3.next_int_inclusive(WAIT_LO, WAIT_HI)
		if w0 < WAIT_LO or w0 > WAIT_HI:
			return _fail_ret("F3 inclusive sampler out of range")
	var clock: VirtualClock = ClockScript.new()
	if clock.advance(-1.0) or clock.advance(NAN) or clock.advance(INF) or clock.now() != 0.0:
		return _fail_ret("F3 clock rejects invalid advance")
	if not clock.advance(2.5) or clock.now() != 2.5 or not clock.advance(0.0):
		return _fail_ret("F3 clock advance valid values")
	clock.reset()
	if clock.now() != 0.0:
		return _fail_ret("F3 clock reset")
	# 1000 次完整抛竿：wait 全为 [20,60] 整数且散布非钉死
	var parts := _make(11)
	if parts.is_empty():
		return _fail_ret("F3 sampling setup")
	var fsm: FishingStateMachine = parts[0]
	var lo := 999999
	var hi := -999999
	var distinct := {}
	for i in 1000:
		var rc: Dictionary = fsm.request_cast()
		if rc.get("ok") != true:
			return _fail_ret("F3 cast #%d" % i)
		var w := int(rc["wait_seconds"])
		if w < WAIT_LO or w > WAIT_HI:
			return _fail_ret("F3 wait %d out of [%d,%d]" % [w, WAIT_LO, WAIT_HI])
		if w < lo:
			lo = w
		if w > hi:
			hi = w
		distinct[w] = true
		var cyc := _complete_cycle(fsm)
		if cyc["ok"] != true:
			return _fail_ret("F3 cycle #%d" % i)
	print("FSM001 sample: min=%d max=%d distinct=%d" % [lo, hi, distinct.size()])
	if distinct.size() < 30 or hi - lo < 30:
		return _fail_ret("F3 samples pinned (distinct=%d span=%d)" % [distinct.size(), hi - lo])
	return true


# ---- F4：同种子逐事件复现；异种子可不同（T-TIME-01）----
func _f4() -> bool:
	var t7a := _sim_seed(7, 1.0, 600.0)
	var t7b := _sim_seed(7, 1.0, 600.0)
	var t13 := _sim_seed(13, 1.0, 600.0)
	if t7a.is_empty() or t7b.is_empty() or t13.is_empty():
		return _fail_ret("F4 simulation setup")
	if t7a != t7b:
		return _fail_ret("F4 same seed diverged")
	if t13 == t7a:
		return _fail_ret("F4 different seeds produced identical stream")
	return true


# ---- F5：0.5/1/2 s 步（120/30/15 FPS 模拟）事件时间轴一致（T-TIME-02）----
func _f5() -> bool:
	var t05 := _sim_seed(23, 0.5, 3600.0)
	var t10 := _sim_seed(23, 1.0, 3600.0)
	var t20 := _sim_seed(23, 2.0, 3600.0)
	if t05.size() < 100 or t10.size() < 100 or t20.size() < 100:
		return _fail_ret("F5 timelines too short (sizes %d/%d/%d)" % [t05.size(), t10.size(), t20.size()])
	if t05 != t10 or t10 != t20:
		var n := mini(mini(t05.size(), t10.size()), t20.size())
		var idx := -1
		for i in n:
			if t05[i] != t10[i] or t10[i] != t20[i]:
				idx = i
				break
		var probe := "" if idx < 0 else ("first-diff@%d: 0.5=[%s] 1.0=[%s] 2.0=[%s]" % [idx, t05[idx], t10[idx], t20[idx]])
		return _fail_ret("F5 step-size invariance broken sizes=%d/%d/%d %s" % [t05.size(), t10.size(), t20.size(), probe])
	return true


# ---- F6：暂停安全——暂停零事件、时钟不推进、恢复后续跑、checkpoint 形状不变 ----
func _f6() -> bool:
	var parts := _make(17)
	if parts.is_empty():
		return _fail_ret("F6 setup")
	var fsm: FishingStateMachine = parts[0]
	var clock: VirtualClock = parts[2]
	fsm.request_cast()
	var evs: Array = fsm.tick_effective(5.0)
	if evs.size() != 1 or evs[0]["to_state"] != "WAITING":
		return _fail_ret("F6 enter WAITING")
	var cp0 := fsm.snapshot_checkpoint()
	if cp0["state"] != "WAITING" or String(cp0["event_id"]).is_empty() \
			or not (cp0["wait_seconds"] is int) or float(cp0["elapsed_effective_seconds"]) != 4.0:
		return _fail_ret("F6 WAITING checkpoint shape")
	var p: Dictionary = fsm.pause("window_hidden")
	if p.get("ok") != true:
		return _fail_ret("F6 pause")
	if (fsm.tick_effective(10000.0) as Array).size() != 0:
		return _fail_ret("F6 paused tick produced events")
	if fsm.get_state() != FsmScript.State.PAUSED:
		return _fail_ret("F6 still PAUSED after 10000s paused ticks")
	if clock.now() != 5.0:
		return _fail_ret("F6 paused tick consumed effective time")
	if fsm.produce_catch_candidate()["ok"] != false:
		return _fail_ret("F6 no candidate while paused")
	var r: Dictionary = fsm.resume_if_safe()
	if r.get("ok") != true or r["resumed_from"] != "WAITING":
		return _fail_ret("F6 resume")
	if fsm.snapshot_checkpoint() != cp0:
		return _fail_ret("F6 checkpoint moved across pause")
	# 恢复后位于 WAITING（计时位置未动）：直接驱动剩余周期
	var h: Array = fsm.tick_effective(200.0)
	if h.size() != 1 or h[0]["to_state"] != "HOOKED":
		return _fail_ret("F6 resumed WAITING->HOOKED")
	var r2: Array = fsm.tick_effective(1.0)
	if r2.size() != 1 or r2[0]["to_state"] != "REELING":
		return _fail_ret("F6 resumed HOOKED->REELING")
	var s2: Array = fsm.tick_effective(1.0)
	if s2.size() != 1 or s2[0]["to_state"] != "SETTLEMENT":
		return _fail_ret("F6 resumed REELING->SETTLEMENT")
	var cand: Dictionary = fsm.produce_catch_candidate()
	if cand.get("ok") != true:
		return _fail_ret("F6 candidate after resume")
	var ack: Dictionary = fsm.ack_settlement(String(cand["catch_event_id"]), true)
	if ack.get("ok") != true or fsm.get_state() != FsmScript.State.IDLE:
		return _fail_ret("F6 settle after resume")
	return true


# ---- F7：满篓阻断 can_cast（容量 10 仅候选值断言；FSM 只读 GameState）----
func _f7() -> bool:
	var parts := _make(23)
	if parts.is_empty():
		return _fail_ret("F7 setup")
	var fsm: FishingStateMachine = parts[0]
	var st := GameState.new()
	if st.basket_capacity != 10 or not fsm.can_cast(st):
		return _fail_ret("F7 empty basket can_cast")
	for i in 10:
		st.basket.append({"instance_id": "fi-%d" % i})
	if fsm.can_cast(st):
		return _fail_ret("F7 full basket must block cast")
	st.basket.pop_back()
	if not fsm.can_cast(st):
		return _fail_ret("F7 freed slot must allow cast")
	fsm.request_cast()
	if fsm.can_cast(st):
		return _fail_ret("F7 non-IDLE can_cast must be false")
	return true


# ---- F8：非法配置拒绝 FSM 启动（T-CONF-01 交界，复用 CFG-001 夹具）----
func _f8() -> bool:
	var bad_rt: Dictionary = RuntimeScript.load_config(FIXTURE_DIR + "min_gt_max.json")
	if bad_rt.get("ok") != false or bad_rt.get("error_code") != "MIN_GT_MAX":
		return _fail_ret("F8 runtime fixture")
	var fsm: FishingStateMachine = FsmScript.new()
	var init: Dictionary = fsm.initialize(_catalog, bad_rt, RngScript.new(), ClockScript.new(), {})
	if init.get("ok") != false or String(init["error_code"]).find("runtime:MIN_GT_MAX") < 0:
		return _fail_ret("F8 runtime gate code %s" % [str(init.get("error_code", "?"))])
	if fsm.get_state() != FsmScript.State.IDLE:
		return _fail_ret("F8 rejected init must stay IDLE")
	if String(fsm.request_cast()["rejected_reason"]) != "NOT_INITIALIZED":
		return _fail_ret("F8 cast after failed init")
	var bad_cat: Dictionary = CatalogScript.load_catalog(FIXTURE_DIR + "dup_id.json")
	var fsm2: FishingStateMachine = FsmScript.new()
	var init2: Dictionary = fsm2.initialize(bad_cat, _runtime, RngScript.new(), ClockScript.new(), {})
	if init2.get("ok") != false or String(init2["error_code"]) != "catalog:DUP_ID":
		return _fail_ret("F8 catalog gate code %s" % [str(init2.get("error_code", "?"))])
	return true


# ---- F9：WAITING 中崩溃 → checkpoint 恢复 → 与未中断跑逐事件一致 ----
func _f9() -> bool:
	var timeline_full := _sim_seed(19, 1.0, 600.0, 5.0, true)
	var timeline_crash := _sim_seed(19, 1.0, 600.0, 5.0, false)
	if timeline_full.is_empty() or timeline_crash.is_empty():
		return _fail_ret("F9 setup")
	if timeline_full != timeline_crash:
		return _fail_ret("F9 recovered stream differs")
	return true


# ---- F10：结算幂等（SDD-143）----
func _f10() -> bool:
	var parts := _make(43)
	if parts.is_empty():
		return _fail_ret("F10 setup")
	var fsm: FishingStateMachine = parts[0]
	var rc: Dictionary = fsm.request_cast()
	var event_id := String(rc["catch_event_id"])
	fsm.tick_effective(5.0)   # → WAITING
	fsm.tick_effective(200.0) # → HOOKED
	fsm.tick_effective(0.5)   # → REELING
	fsm.tick_effective(0.5)   # → SETTLEMENT
	if fsm.get_state() != FsmScript.State.SETTLEMENT:
		return _fail_ret("F10 enter SETTLEMENT")
	if (fsm.produce_catch_candidate() as Dictionary).get("ok") != true:
		return _fail_ret("F10 first candidate")
	var ack_uncommitted: Dictionary = fsm.ack_settlement(event_id, false)
	if ack_uncommitted.get("ok") != true or ack_uncommitted["next_state"] != "SETTLEMENT" \
			or fsm.get_state() != FsmScript.State.SETTLEMENT:
		return _fail_ret("F10 uncommitted ack keeps SETTLEMENT")
	var ack_ok: Dictionary = fsm.ack_settlement(event_id, true)
	if ack_ok.get("ok") != true or ack_ok["next_state"] != "IDLE":
		return _fail_ret("F10 committed ack -> IDLE")
	var ack_dup: Dictionary = fsm.ack_settlement(event_id, true)
	if ack_dup.get("ok") != false or ack_dup["code"] != "AlreadyApplied" \
			or fsm.get_state() != FsmScript.State.IDLE:
		return _fail_ret("F10 duplicate ack must be AlreadyApplied")
	if fsm.produce_catch_candidate()["ok"] != false:
		return _fail_ret("F10 no candidate resend after settlement")
	var settled := 0
	for entry in fsm.get_transition_log():
		if entry["action"] == "transition" and entry["from_state"] == "SETTLEMENT" \
				and entry["to_state"] == "IDLE" and entry["event_id"] == event_id:
			settled += 1
	if settled != 1:
		return _fail_ret("F10 expected exactly one SETTLEMENT->IDLE, got %d" % settled)
	var next_cast: Dictionary = fsm.request_cast()
	if next_cast.get("ok") != true or String(next_cast["catch_event_id"]) == event_id:
		return _fail_ret("F10 next cycle after AlreadyApplied")
	return true


# ---- F11：大步长安全——单步跨多阈值至多一个转换、余量结转 ----
func _f11() -> bool:
	var parts := _make(47)
	if parts.is_empty():
		return _fail_ret("F11 setup")
	var fsm: FishingStateMachine = parts[0]
	fsm.request_cast()
	var e1: Array = fsm.tick_effective(1.0)
	if e1.size() != 1 or e1[0]["to_state"] != "WAITING":
		return _fail_ret("F11 enter WAITING")
	var e2: Array = fsm.tick_effective(120.0)
	if e2.size() != 1 or e2[0]["to_state"] != "HOOKED":
		return _fail_ret("F11 120s step yields exactly one HOOKED, got %d" % e2.size())
	var e3: Array = fsm.tick_effective(0.5)
	if e3.size() != 1 or e3[0]["to_state"] != "REELING":
		return _fail_ret("F11 carry-over must advance exactly one more state")
	var e4: Array = fsm.tick_effective(0.5)
	if e4.size() != 1 or e4[0]["to_state"] != "SETTLEMENT":
		return _fail_ret("F11 carry-over third state")
	if (fsm.tick_effective(0.5) as Array).size() != 0:
		return _fail_ret("F11 SETTLEMENT must not phantom-tick")
	return true


# ---- 共享辅助 ----

## 新建合法启动的 (fsm, rng, clock)；失败返回空数组。
func _make(seed_value: int) -> Array:
	var rng: DeterministicRng = RngScript.new()
	var clock: VirtualClock = ClockScript.new()
	if rng.set_seed(seed_value).get("ok") != true:
		return []
	var fsm: FishingStateMachine = FsmScript.new()
	if fsm.initialize(_catalog, _runtime, rng, clock, {}).get("ok") != true:
		return []
	return [fsm, rng, clock]


## 完整周期：WAITING 上限+余量 → HOOKED → REELING → SETTLEMENT → 候选 → ack(true) → IDLE。
func _complete_cycle(fsm: FishingStateMachine) -> Dictionary:
	var e1: Array = fsm.tick_effective(5.0)
	var e2: Array = fsm.tick_effective(200.0)
	var e3: Array = fsm.tick_effective(1.0)
	var e4: Array = fsm.tick_effective(1.0)
	if e1.size() != 1 or e1[0]["to_state"] != "WAITING" \
			or e2.size() != 1 or e2[0]["to_state"] != "HOOKED" \
			or e3.size() != 1 or e3[0]["to_state"] != "REELING" \
			or e4.size() != 1 or e4[0]["to_state"] != "SETTLEMENT":
		return {"ok": false}
	var cand: Dictionary = fsm.produce_catch_candidate()
	if cand.get("ok") != true:
		return {"ok": false}
	var ack: Dictionary = fsm.ack_settlement(String(cand["catch_event_id"]), true)
	if ack.get("ok") != true or ack["next_state"] != "IDLE" \
			or fsm.get_state() != FsmScript.State.IDLE:
		return {"ok": false}
	return {"ok": true, "event_id": String(cand["catch_event_id"]), "species_id": String(cand["species_id"])}


## 从新实例开始按固定步长模拟 total 虚拟秒，返回可逐字段比对的事件时间轴。
## crash_at >= 0 时在逻辑时刻 crash_at 处（WAITING 中）snapshot 并换新 FSM 恢复（F9）。
func _sim_seed(seed_value: int, step: float, total: float, crash_at := -1.0, control := true) -> Array:
	var parts := _make(seed_value)
	if parts.is_empty():
		return []
	var fsm = parts[0]
	var rng = parts[1]
	var clock = parts[2]
	var rc: Dictionary = fsm.request_cast()
	if rc.get("ok") != true:
		return []
	var timeline: Array = []
	var t := 0.0
	var crashed := false
	while t < total:
		if crash_at >= 0.0 and not crashed and t >= crash_at:
			var cp: Dictionary = fsm.snapshot_checkpoint()
			if control:
				if cp["state"] != "WAITING":
					return []  # 对照组必须真的在 WAITING 中崩溃，否则测试无效
				crashed = true  # 对照组不重建，仅确认崩溃时刻状态有效
			else:
				var revived: FishingStateMachine = FsmScript.new()
				if revived.initialize(_catalog, _runtime, rng, clock, cp).get("ok") != true:
					return []
				fsm = revived
				crashed = true
		var evs: Array = fsm.tick_effective(step)
		t += step
		for e in evs:
			timeline.append("T|%s|%s|%.3f|%s" % [e["from_state"], e["to_state"], float(e["at_clock"]), String(e["event_id"])])
		if fsm.get_state() == FsmScript.State.SETTLEMENT:
			var cand: Dictionary = fsm.produce_catch_candidate()
			if cand.get("ok") != true:
				return []
			var ack: Dictionary = fsm.ack_settlement(String(cand["catch_event_id"]), true)
			if ack.get("ok") != true:
				return []
			var nxt: Dictionary = fsm.request_cast()
			if nxt.get("ok") != true:
				return []
			timeline.append("K|%.3f|%s|%d" % [float(cand["caught_at_clock"]), String(nxt["catch_event_id"]), int(nxt["wait_seconds"])])
	return timeline


func _fail_ret(msg: String) -> bool:
	print("FSM001 FSM FAIL: " + msg)
	quit(1)
	return false
