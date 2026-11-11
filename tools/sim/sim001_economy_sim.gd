extends SceneTree
# SIM-001 多随机种子虚拟时间经济模拟驱动（headless，纯 GDScript；由 tools/sim/run_sim001_checks.py
# 在隔离临时副本内调度，禁止直接对主工程跑 Godot）。
# 契约来源：tasks/evidence/SIM-001/plan.md §4/§5 与 review.md、docs/ACCEPTANCE_TESTS.md §1/§4、
# tasks/TASKS.md「SIM-001（平衡统计，不可自行改数值）」、DECISION SDD-172/176/177/178。
# 约定与 CORE/CFG/FSM/ECO/SAVE-001 一致：全部通过打印 "SIM001 SIM PASS" 且 quit(0)；
# 首个失败打印 "SIM001 SIM FAIL: <step>" 且 quit(1)。机器可读 JSON 报告夹在
# SIM001_REPORT_BEGIN / SIM001_REPORT_END 之间的单个 JSON 文档（plan §4.5 真实执行版）。
# 本票铁律（plan §7）：零数值调节——20/60 秒、30 FPS、容量 10、鱼价/权重全部按现状只读加载；
# 任何调节建议只出现在 report.md 的「提请用户审核」段，由用户批准后才可另票执行。
# 复用已验收实现（只调用、绝不修改）：FishingStateMachine + DeterministicRng + VirtualClock +
# EconomyService（场景 A/B：默认恒真内存门，零文件 IO）+ AtomicSaveService（仅故障子场景，
# configure_dir 注入 OS.get_temp_dir() 下的本模拟专属临时目录，绝不触碰真实 user://）。
# 本脚本自身不声明 class_name（plan R-7 零全局类新增），不写任何 res:// 路径。
#
# 模拟策略常量（plan §4.2，仅测试参数，非产品数值；SDD §6 明示 cast/reel 时长为技术测试配置，
# ACCEPTANCE §4 明示种子数为测试建议值）：
#   SEEDS = 101..120（20 个固定种子）；时长 1h/4h/8h = 3600/14400/28800 虚拟秒；TICK = 1.0 s；
#   stage_durations = {casting_sec, hooked_sec, reeling_sec} = FSM 默认技术值 1.0 s（未改配置）；
#   SALE_EVERY_SEC = 1800（场景 B 定期出售周期）；CLICK_EVERY_SEC = 60（场景 A 满篓持续点击）；
#   故障子场景：seed=101、场景 B、8h，在 3600 s 与 7200 s 之后分别于下一笔确定执行的 catch
#   写盘前武装 rename / tmp_write 故障，验证 PERSIST_FAILED + 权威状态零变化后解除并同 ID 重试。
#   EPOCH_UTC = 2026-01-01T00:00:00Z + int(clock.now()) 秒，纯整数历法（civil-from-days）格式化，
#   输出必须匹配 FishInstance.UTC_PATTERN；不用本机时钟/时区，保证跨机确定（plan R-4）。

const RngScript := preload("res://scripts/fishing/deterministic_rng.gd")
const ClockScript := preload("res://scripts/fishing/virtual_clock.gd")
const FsmScript := preload("res://scripts/fishing/fishing_state_machine.gd")
const EcoScript := preload("res://scripts/economy/economy_service.gd")
const FishScript := preload("res://scripts/economy/fish_instance.gd")
const CatalogScript := preload("res://scripts/config/fish_species_catalog.gd")
const RuntimeScript := preload("res://scripts/config/runtime_config.gd")
const SaveScript := preload("res://scripts/save/save_service.gd")

const SEEDS := [101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120]
const HORIZON_SEC := [3600, 14400, 28800]
const HORIZON_HOURS := [1, 4, 8]
const SCENARIO_HOLD := "hold_until_full"
const SCENARIO_SELL := "periodic_sell_1800s"
const TICK := 1.0
const SALE_EVERY_SEC := 1800
const CLICK_EVERY_SEC := 60
const EPOCH_UTC_SECONDS := 1767225600  # 2026-01-01T00:00:00Z（纯整数历法基准，非本机时钟）
const RETRY_SAMPLES := 2  # 每种子每类事务抽样重试笔数（plan：≥2 catch、≥2 sale）
const MAX_RETRY := 100  # 每笔抽样至多重试次数（plan §1.4）
const FAULT_SEED := 101
const FAULT_HORIZON := 28800
const FAULT_STAGES := [["rename", 3600], ["tmp_write", 7200]]

var _catalog: Dictionary = {}
var _runtime: Dictionary = {}
var _config: Dictionary = {}
var _species_by_id: Dictionary = {}
var _dir_seq := 0
var _dirs: Array = []


func _initialize() -> void:
	# —— R0：真实配置只读加载（T-CONF-01 门禁由 FSM/Economy initialize 内联复用）——
	_catalog = CatalogScript.load_catalog("res://data/fish_species.json")
	_runtime = RuntimeScript.load_config("res://data/runtime_config.json")
	if _catalog.get("ok") != true or _runtime.get("ok") != true:
		_fail("R0 base configs invalid (CFG-001 validators must pass first)")
		return
	_config = _runtime["config"]
	for entry in (_catalog["species"] as Array):
		var entry_dict: Dictionary = entry
		_species_by_id[String(entry_dict["id"])] = entry_dict.duplicate(true)
	# 纯整数历法自检（R-4）：输出必须匹配 FishInstance.UTC_PATTERN 且逐值正确
	if _utc_from_epoch(0) != "1970-01-01T00:00:00Z" \
			or _utc_from_epoch(EPOCH_UTC_SECONDS) != "2026-01-01T00:00:00Z" \
			or _utc_from_epoch(EPOCH_UTC_SECONDS + FAULT_HORIZON) != "2026-01-01T08:00:00Z" \
			or FishScript.timestamp_valid(_utc_from_epoch(EPOCH_UTC_SECONDS + 28800)) != true:
		_fail("R0 civil-from-days UTC self-check failed")
		return

	# —— 主矩阵：20 seeds × 2 场景 × {1h,4h,8h}（每格独立干净态起跑，plan §4.3 步骤 7）——
	var counters := {"wait_out": 0, "dup_catch": 0, "dup_sale": 0, "casts_full": 0}
	var per_run: Array = []
	var all_cycles: Array = []
	var first_fills_hold: Array = []
	var species_counts := {}
	var species_value := {}
	var sale_golds: Array = []
	var total_rejects := 0
	for seed_value in SEEDS:
		for scenario in [SCENARIO_HOLD, SCENARIO_SELL]:
			for horizon_index in HORIZON_SEC.size():
				var run := _execute_run(int(seed_value), String(scenario), int(HORIZON_SEC[horizon_index]), false, counters)
				if run.is_empty():
					return  # _fail 已打印 FAIL 并 quit(1)
				per_run.append(run["row"])
				all_cycles.append_array(run["cycle_times"])
				sale_golds.append_array(run["sale_golds"])
				var row := run["row"] as Dictionary
				total_rejects += int(row["full_basket_cast_rejections"])
				if String(row["scenario"]) == SCENARIO_HOLD and row["first_fill_seconds"] != null:
					first_fills_hold.append(int(row["first_fill_seconds"]))
				var row_counts: Dictionary = row["species_counts"]
				var row_value: Dictionary = row["species_total_value"]
				for sid in row_counts:
					species_counts[sid] = int(species_counts.get(sid, 0)) + int(row_counts[sid])
					species_value[sid] = int(species_value.get(sid, 0)) + int(row_value[sid])

	# —— 确定性重放（T-TIME-01）：每 (seed, scenario) 在 1h 独立重放两次，逐字段事件序列一致 ——
	var replay_pairs := 0
	for seed_value in SEEDS:
		for scenario in [SCENARIO_HOLD, SCENARIO_SELL]:
			var first := _execute_run(int(seed_value), String(scenario), 3600, false, counters)
			var second := _execute_run(int(seed_value), String(scenario), 3600, false, counters)
			if first.is_empty() or second.is_empty():
				return
			replay_pairs += 1
			if String(first["canonical"]) != String(second["canonical"]):
				_fail("deterministic replay mismatch seed=%d scenario=%s" % [seed_value, scenario])
				return

	# —— 故障注入子场景（seed=101、场景 B、8h；plan §4.2/§4.4、review 强制条件）——
	var fault := _execute_run(FAULT_SEED, SCENARIO_SELL, FAULT_HORIZON, true, counters)
	if fault.is_empty():
		return
	var fault_committed := int(fault["fault_committed"])
	if fault_committed != 0:
		_fail("fault window committed %d transactions before recovery (must be 0)" % fault_committed)
		return
	var fault_records: Array = fault["fault_records"]
	if fault_records.size() != FAULT_STAGES.size():
		_fail("fault injections executed %d != %d" % [fault_records.size(), FAULT_STAGES.size()])
		return
	# 交叉核对：故障 run（文件 IO 门）与内存 run 101/B/8h 的事务效果一致（门不改变业务语义）
	var twin := {}
	for row in per_run:
		var row_dict := row as Dictionary
		if int(row_dict["seed"]) == FAULT_SEED and String(row_dict["scenario"]) == SCENARIO_SELL \
				and int(row_dict["virtual_hours"]) == 8:
			twin = row_dict
	if twin.is_empty():
		_fail("fault twin row (101, periodic_sell_1800s, 8h) missing")
		return
	if int(fault["cycles"]) != int(twin["cycles_completed"]):
		_fail("fault run cycles %d != memory twin %d" % [int(fault["cycles"]), int(twin["cycles_completed"])])
		return
	var twin_gold := 0
	for sale in (twin["sales"] as Array):
		twin_gold += int((sale as Dictionary)["gold_added"])
	if int(fault["gold_total"]) != twin_gold:
		_fail("fault run gold %d != memory twin %d" % [int(fault["gold_total"]), twin_gold])
		return

	_cleanup_dirs()  # 先清理故障临时目录，再输出报告（R-5：不留残留）

	# —— 汇总与报告（plan §4.4/§4.5）——
	var total_cycles := 0
	var total_catches := 0
	for row in per_run:
		total_cycles += int((row as Dictionary)["cycles_completed"])
	for sid in species_counts:
		total_catches += int(species_counts[sid])
	var share := {}
	for sid in species_counts:
		share[sid] = roundf(float(species_counts[sid]) * 10000.0 / float(total_catches)) / 10000.0
	var gold_mean := 0.0
	if not sale_golds.is_empty():
		var gold_sum := 0
		for gold in sale_golds:
			gold_sum += int(gold)
		gold_mean = roundf(float(gold_sum) * 1000.0 / float(sale_golds.size())) / 1000.0
	var capacity := int(_config["basket_capacity"])
	var wait_lo := int(ceilf(float(_config["bite_wait_min_sec"])))
	var wait_hi := int(floorf(float(_config["bite_wait_max_sec"])))
	var hard_gates_ok := int(counters["wait_out"]) == 0 and int(counters["dup_catch"]) == 0 \
			and int(counters["dup_sale"]) == 0 and int(counters["casts_full"]) == 0 \
			and fault_committed == 0 and replay_pairs == SEEDS.size() * 2
	var report := {
		"suite": "economy-simulation",
		"build_id": "unreleased-local",
		"godot_version": String(Engine.get_version_info().get("string", "")),
		"seeds": SEEDS.duplicate(),
		"virtual_hours": HORIZON_HOURS.duplicate(),
		"scenarios": [SCENARIO_HOLD, SCENARIO_SELL],
		"summary": {
			"basket_capacity": capacity,
			"bite_wait_min_sec": wait_lo,
			"bite_wait_max_sec": wait_hi,
			"runs": per_run.size(),
			"deterministic_replay_pairs": replay_pairs,
			"cycles_completed_total": total_cycles,
			"first_fill_seconds": _stats(first_fills_hold),
			"first_fill_scope": "hold_until_full 场景 60 run；null 表示该时长内从未满篓",
			"cycle_seconds": _stats(all_cycles),
			"species_counts": species_counts,
			"species_share": share,
			"species_total_value": species_value,
			"gold_per_sale": {"mean": gold_mean, "samples": sale_golds.size()},
			"full_basket_cast_rejections": total_rejects,
			"duplicate_catch_transactions": int(counters["dup_catch"]),
			"duplicate_sale_transactions": int(counters["dup_sale"]),
			"casts_started_while_full": int(counters["casts_full"]),
			"fault_transactions_committed_before_recovery": fault_committed,
			"wait_seconds_out_of_range": int(counters["wait_out"]),
			"deterministic_replay_identical": true,
		},
		"per_run": per_run,
		"fault_injection": fault_records,
		"pass": hard_gates_ok,
		"notes": [
			"SIM001 真实执行结果，非示例；产品数值零改动：20/60 秒、30 FPS、容量 10、权重 60/30/10、价格 8/16/32 均按 data/ 现状只读加载",
			"模拟策略常量（20 seeds 101..120、1h/4h/8h、TICK 1.0s、场景 B 周期 1800s、满篓点击 60s、stage 1.0s）均为测试参数，非产品数值；调节建议仅见 report.md 提请用户审核段",
			"场景 A/B 走 EconomyService 默认恒真内存门（零文件 IO）；仅故障子场景经 AtomicSaveService 写 OS.get_temp_dir() 下临时目录且结束时清理，不触碰真实 user://",
		],
	}
	print("SIM001_REPORT_BEGIN")
	print(JSON.stringify(report))
	print("SIM001_REPORT_END")
	print("SIM001 SIM PASS")
	quit(0)


## 单个 (seed, scenario, horizon[, save-gated fault run]) 的完整事件驱动 run（plan §4.3）。
## 返回 {row, canonical, cycle_times, sale_golds, cycles, gold_total, fault_committed, fault_records}；
## 任一硬断言失败 → _fail（打印 SIM001 SIM FAIL 并 quit(1)）→ 返回 {}。
## with_save=true 时装配 AtomicSaveService（临时目录），并按 FAULT_STAGES 在阈值后的第一笔
## catch 写盘前武装故障；false 时使用 EconomyService 默认恒真内存门（零 IO）。
func _execute_run(seed_value: int, scenario: String, horizon: int, with_save: bool, counters: Dictionary) -> Dictionary:
	var eco: EconomyService = EcoScript.new()
	if eco.initialize(_catalog, _runtime).get("ok") != true:
		return _fail_ret("E0 eco.initialize rejected (T-CONF-01 gate)")
	var rng: DeterministicRng = RngScript.new()
	if rng.set_seed(seed_value).get("ok") != true:
		return _fail_ret("E0 rng.set_seed(%d)" % seed_value)
	var clock: VirtualClock = ClockScript.new()
	var fsm: FishingStateMachine = FsmScript.new()
	if fsm.initialize(_catalog, _runtime, rng, clock, {},
			{"casting_sec": 1.0, "hooked_sec": 1.0, "reeling_sec": 1.0}).get("ok") != true:
		return _fail_ret("E0 fsm.initialize rejected")
	var state := GameState.new()
	var save: AtomicSaveService = null
	if with_save:
		save = SaveScript.new()
		if save.configure_dir(_fresh_dir("fault")).get("ok") != true:
			return _fail_ret("E0 configure_dir (temp dir)")
		if save.install_into(eco, state, rng, clock, fsm, _species_by_id).get("ok") != true:
			return _fail_ret("E0 install_into")
	var capacity := int(_config["basket_capacity"])
	if int(state.basket_capacity) != capacity:
		return _fail_ret("E0 GameState capacity %d != runtime %d" % [int(state.basket_capacity), capacity])
	var wait_lo := int(ceilf(float(_config["bite_wait_min_sec"])))
	var wait_hi := int(floorf(float(_config["bite_wait_max_sec"])))
	var cycles := 0
	var cycle_start := -1
	var first_fill := -1
	var full_rejects := 0
	var next_click_at := -1
	var next_sale_at := SALE_EVERY_SEC
	var sale_seq := 0
	var fault_stage_next := 0
	var fault_committed := 0
	var gold_total := 0  # 仅累计 sale gold_added（与 twin 行 sales 求和同口径交叉核对）
	var cycle_times: Array = []
	var sale_rows: Array = []
	var sale_golds: Array = []
	var catch_history: Array = []
	var sale_history: Array = []
	var species_counts := {}
	var species_value := {}
	var events: Array = []
	var fault_records: Array = []
	var t := 0
	while t < horizon:
		# 1) 场景 B：1800 虚拟秒周期点出售全篮（模拟策略；唯一 sale id，plan §4.2）
		if scenario == SCENARIO_SELL:
			while next_sale_at <= t:
				if not state.basket.is_empty():
					var ids: Array = []
					for fish in state.basket:
						ids.append(String((fish as Dictionary)["instance_id"]))
					sale_seq += 1
					var sale_id := "sale-%d-%d" % [seed_value, sale_seq]
					var sold: Dictionary = eco.sell_fish(state, sale_id, ids)
					if sold.get("ok") != true or String(sold["code"]) != "":
						return _fail_ret("E1 sale %s unexpected reject: %s" % [sale_id, str(sold)])
					var gold := int(sold["gold_added"])
					gold_total += gold
					sale_rows.append({"at_clock": t, "sale_event_id": sale_id, "fish_count": ids.size(), "gold_added": gold})
					sale_golds.append(gold)
					sale_history.append({"sale_event_id": sale_id, "instance_ids": ids})
					events.append("sell|%s|IDLE||0|%d" % [sale_id, gold])
				next_sale_at += SALE_EVERY_SEC
		# 2) IDLE 行为：未满 → 抛竿；场景 A 满篓 → 每 60 虚拟秒持续点击（模拟用户），
		#    断言一律 BASKET_FULL 且 FSM 停留 IDLE（T-ECO-01，casts_started_while_full 硬门禁）
		if fsm.get_state() == FsmScript.State.IDLE:
			if state.basket.size() >= capacity:
				if scenario == SCENARIO_HOLD and next_click_at >= 0 and t >= next_click_at:
					var rejected: Dictionary = fsm.request_cast(state)
					if rejected.get("ok") == true:
						counters["casts_full"] = int(counters["casts_full"]) + 1
						return _fail_ret("E2 T-ECO-01 cast started while full (seed=%d t=%d)" % [seed_value, t])
					if String(rejected["rejected_reason"]) != "BASKET_FULL" \
							or fsm.get_state() != FsmScript.State.IDLE:
						return _fail_ret("E2 T-ECO-01 full-basket reject not BASKET_FULL/IDLE: %s" % str(rejected))
					full_rejects += 1
					events.append("reject||IDLE||0|0")
					next_click_at = t + CLICK_EVERY_SEC
			else:
				var cast: Dictionary = fsm.request_cast(state)
				if cast.get("ok") != true:
					return _fail_ret("E3 unexpected cast reject: %s" % str(cast))
				var wait := int(cast["wait_seconds"])
				if wait < wait_lo or wait > wait_hi:
					counters["wait_out"] = int(counters["wait_out"]) + 1
					return _fail_ret("E3 T-TIME-01 wait_seconds %d outside [%d,%d]" % [wait, wait_lo, wait_hi])
				cycle_start = t
				events.append("cast|%s|CASTING||%d|0" % [String(cast["catch_event_id"]), wait])
		# 3) 推进 1 虚拟秒：FSM 计时态经 tick_effective（单步至多 1 转换，过冲结转，T-TIME-02）；
		#    IDLE/SETTLEMENT 只推进虚拟时钟本身（tick_effective 在这些状态不消耗有效时间）
		var st: int = fsm.get_state()
		if st == FsmScript.State.CASTING or st == FsmScript.State.WAITING \
				or st == FsmScript.State.HOOKED or st == FsmScript.State.REELING:
			var tick_events: Array = fsm.tick_effective(TICK)
			for ev in tick_events:
				events.append("trans|%s|%s>%s||0|0" % [String((ev as Dictionary)["event_id"]),
						String((ev as Dictionary)["from_state"]), String((ev as Dictionary)["to_state"])])
		elif not clock.advance(TICK):
			return _fail_ret("E4 clock.advance rejected")
		t += 1
		# 4) SETTLEMENT：候选 →（故障武装）→ commit_catch → ack_settlement（幂等契约 SDD-143）
		if fsm.get_state() == FsmScript.State.SETTLEMENT:
			var cand: Dictionary = fsm.produce_catch_candidate()
			if cand.get("ok") != true:
				return _fail_ret("E5 produce_catch_candidate rejected: %s" % str(cand))
			var catch_id := String(cand["catch_event_id"])
			var species_id := String(cand["species_id"])
			if not _species_by_id.has(species_id):
				return _fail_ret("E5 unknown species %s" % species_id)
			var utc := _utc_from_epoch(EPOCH_UTC_SECONDS + t)
			if FishScript.timestamp_valid(utc) != true:
				return _fail_ret("E5 invalid UTC %s" % utc)
			var price := int((cand["weight_snapshot"] as Dictionary)["base_price"])
			if price != int((_species_by_id[species_id] as Dictionary)["base_price"]):
				return _fail_ret("E5 price snapshot mismatch for %s" % species_id)
			var armed_stage := ""
			var digest_before_fault := ""
			if with_save and fault_stage_next < FAULT_STAGES.size() \
					and t > int(FAULT_STAGES[fault_stage_next][1]):
				# review 条件：仅在该笔注定执行的 catch 写盘前一刻武装（此时钟秒即注入点）
				armed_stage = String(FAULT_STAGES[fault_stage_next][0])
				fault_stage_next += 1
				if save.set_fault_injection(armed_stage, true).get("ok") != true:
					return _fail_ret("E5 arm fault %s" % armed_stage)
				digest_before_fault = _authoritative_digest(eco, state, fsm)
			if with_save and save.set_pending_candidate(cand, utc).get("ok") != true:
				return _fail_ret("E5 set_pending_candidate rejected")
			var commit: Dictionary = eco.commit_catch(state, catch_id, species_id, utc)
			if not armed_stage.is_empty():
				# 故障期间：本笔必须 PERSIST_FAILED、权威状态/checkpoint 零变化、FSM 仍 SETTLEMENT
				if commit.get("ok") == true:
					fault_committed += 1
				if String(commit["code"]) != "PERSIST_FAILED":
					return _fail_ret("E5 fault %s must yield PERSIST_FAILED, got %s" % [armed_stage, str(commit)])
				if _authoritative_digest(eco, state, fsm) != digest_before_fault:
					return _fail_ret("E5 fault %s changed authoritative state" % armed_stage)
				if fsm.get_state() != FsmScript.State.SETTLEMENT or fsm.get_event_id() != catch_id:
					return _fail_ret("E5 fault %s advanced FSM/checkpoint" % armed_stage)
				if save.set_fault_injection(armed_stage, false).get("ok") != true:
					return _fail_ret("E5 disarm fault %s" % armed_stage)
				commit = eco.commit_catch(state, catch_id, species_id, utc)  # 解除后同 ID 重试
				fault_records.append({
					"stage": armed_stage,
					"transaction_kind": "catch",
					"armed_at_or_after_seconds": int(FAULT_STAGES[fault_stage_next - 1][1]),
					"armed_at_clock": t,
					"failed_transaction_id": catch_id,
					"failure_code": "PERSIST_FAILED",
					"same_id_retry_code": String(commit["code"]),
					"state_unchanged": true,
				})
			if commit.get("ok") != true or String(commit["code"]) != "":
				return _fail_ret("E5 commit_catch rejected: %s" % str(commit))
			var ack: Dictionary = fsm.ack_settlement(catch_id, true)
			if ack.get("ok") != true or String(ack["next_state"]) != "IDLE":
				return _fail_ret("E5 ack_settlement rejected: %s" % str(ack))
			if with_save and save.clear_pending_candidate().get("ok") != true:
				return _fail_ret("E5 clear_pending_candidate rejected")
			cycles += 1
			cycle_times.append(t - cycle_start)
			species_counts[species_id] = int(species_counts.get(species_id, 0)) + 1
			species_value[species_id] = int(species_value.get(species_id, 0)) + price
			catch_history.append({"catch_event_id": catch_id, "species_id": species_id, "caught_at_utc": utc})
			events.append("catch|%s|SETTLEMENT|%s|0|0" % [catch_id, species_id])
			events.append("ack|%s|IDLE||0|0" % catch_id)
			if first_fill < 0 and state.basket.size() >= capacity:
				first_fill = t
				next_click_at = t + CLICK_EVERY_SEC
	# 5) 幂等抽样重试（T-ECO-02/03 硬门禁）：每 run 抽样前 RETRY_SAMPLES 笔 catch、
	#    RETRY_SAMPLES 笔 sale，各以完全相同参数重试至多 MAX_RETRY 次；必须全部
	#    ALREADY_APPLIED / gold_added==0 且权威状态零变化；任一实际再生效 → duplicate 计数 +1 并 FAIL。
	var digest_before_retries := _authoritative_digest(eco, state, fsm)
	for sample_index in mini(RETRY_SAMPLES, catch_history.size()):
		var catch_entry: Dictionary = catch_history[sample_index]
		for _retry in MAX_RETRY:
			var again: Dictionary = eco.commit_catch(state, catch_entry["catch_event_id"],
					catch_entry["species_id"], catch_entry["caught_at_utc"])
			if again.get("ok") != true or String(again["code"]) != "ALREADY_APPLIED":
				counters["dup_catch"] = int(counters["dup_catch"]) + 1
				return _fail_ret("E6 T-ECO-02 catch retry not ALREADY_APPLIED: %s" % str(again))
		if _authoritative_digest(eco, state, fsm) != digest_before_retries:
			counters["dup_catch"] = int(counters["dup_catch"]) + 1
			return _fail_ret("E6 T-ECO-02 catch retries changed authoritative state")
	for sample_index in mini(RETRY_SAMPLES, sale_history.size()):
		var sale_entry: Dictionary = sale_history[sample_index]
		for _retry in MAX_RETRY:
			var again_sale: Dictionary = eco.sell_fish(state, sale_entry["sale_event_id"], sale_entry["instance_ids"])
			if again_sale.get("ok") != true or String(again_sale["code"]) != "ALREADY_APPLIED" \
					or int(again_sale["gold_added"]) != 0:
				counters["dup_sale"] = int(counters["dup_sale"]) + 1
				return _fail_ret("E6 T-ECO-03 sale retry not ALREADY_APPLIED/zero-gold: %s" % str(again_sale))
		if _authoritative_digest(eco, state, fsm) != digest_before_retries:
			counters["dup_sale"] = int(counters["dup_sale"]) + 1
			return _fail_ret("E6 T-ECO-03 sale retries changed authoritative state")

	var horizon_index := HORIZON_SEC.find(horizon)
	var canonical := ""
	for event_index in events.size():
		if event_index > 0:
			canonical += "\n"
		canonical += String(events[event_index])
	var row := {
		"seed": seed_value,
		"scenario": scenario,
		"virtual_hours": int(HORIZON_HOURS[horizon_index]) if horizon_index >= 0 else 0,
		"cycles_completed": cycles,
		"first_fill_seconds": (first_fill if first_fill >= 0 else null),
		"species_counts": species_counts,
		"species_total_value": species_value,
		"sales": sale_rows,
		"full_basket_cast_rejections": full_rejects,
	}
	if first_fill < 0:
		row["never_full_reason"] = "cycles_exhausted_by_horizon"
	return {
		"row": row,
		"canonical": canonical,
		"cycle_times": cycle_times,
		"sale_golds": sale_golds,
		"cycles": cycles,
		"gold_total": gold_total,
		"fault_committed": fault_committed,
		"fault_records": fault_records,
	}


## 权威状态指纹（金币/鱼篓/已处理 ID/revision/账本/checkpoint 的固定键序 JSON 串）。
## 故障与幂等断言的对比对象；Dictionary 键序为插入序，stringify 确定（同 SAVE-001 约定）。
func _authoritative_digest(eco: EconomyService, state: GameState, fsm: FishingStateMachine) -> String:
	return JSON.stringify({
		"wallet_gold": int(state.wallet_gold),
		"basket_size": state.basket.size(),
		"revision": int(state.revision),
		"processed_catch_ids": (state.processed_catch_ids as Array).duplicate(true),
		"processed_sale_ids": (state.processed_sale_ids as Array).duplicate(true),
		"ledger": eco.snapshot_ledger(),
		"checkpoint": fsm.snapshot_checkpoint(),
	})


## 统计族（plan §4.4）：mean 保留 3 位小数；median/p10/p90 用最近秩（ceil(p·n) 第 n 内）。
func _stats(values: Array) -> Dictionary:
	var n := values.size()
	if n == 0:
		return {"mean": null, "median": null, "p10": null, "p90": null}
	var sorted := values.duplicate(true)
	sorted.sort()
	var total := 0
	for value in sorted:
		total += int(value)
	return {
		"mean": roundf(float(total) * 1000.0 / float(n)) / 1000.0,
		"median": int(sorted[_rank(0.5, n)]),
		"p10": int(sorted[_rank(0.1, n)]),
		"p90": int(sorted[_rank(0.9, n)]),
	}


func _rank(p: float, n: int) -> int:
	var index := int(ceilf(p * float(n))) - 1
	if index < 0:
		index = 0
	if index >= n:
		index = n - 1
	return index


## 纯整数 civil-from-days（Howard Hinnant 算法；本模拟 epoch 非负 ⇒ 整除即 floor）。
## 不读本机时钟/时区（plan R-4）；输出逐字段满足 FishInstance.UTC_PATTERN（R0 已自检）。
static func _utc_from_epoch(epoch_seconds: int) -> String:
	var days := epoch_seconds / 86400
	var second_of_day := epoch_seconds % 86400
	var z := days + 719468
	var era := z / 146097
	var doe := z - era * 146097
	var yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var y := yoe + era * 400
	var doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp := (5 * doy + 2) / 153
	var day := doy - (153 * mp + 2) / 5 + 1
	var month := mp + 3 if mp < 10 else mp - 9
	var year := y + (1 if month <= 2 else 0)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [year, month, day,
			second_of_day / 3600, (second_of_day / 60) % 60, second_of_day % 60]


# ---- 临时存档目录卫生（镜像 tests/unit/test_save001_save.gd 的目录约定，R-5）----

func _fresh_dir(label: String) -> String:
	var base := OS.get_temp_dir().rstrip("/")
	var path := base + "/sim001_%s_%d" % [label, _dir_seq]
	_dir_seq += 1
	if DirAccess.dir_exists_absolute(path):
		_remove_dir(path)
	DirAccess.make_dir_recursive_absolute(path)
	_dirs.append(path)
	return path + "/"


func _cleanup_dirs() -> void:
	for path in _dirs:
		_remove_dir(String(path))
	_dirs.clear()


## Godot 4.7.2 实测：无 remove_recursive；手工 open+list_dir 递归删子项，最后移除空目录本身。
func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			_remove_dir(path + "/" + entry)
		else:
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _fail(step: String) -> void:
	_cleanup_dirs()
	print("SIM001 SIM FAIL: %s" % step)
	quit(1)


func _fail_ret(step: String) -> Dictionary:
	_fail(step)
	return {}
