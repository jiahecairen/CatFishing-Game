extends SceneTree
# ECO-001 headless 经济事务单测（T-ECO-01～04、V01-E01/E02、SDD-143/155-156/172/173、
# 2026-11-11 价格快照裁定、plan.md §5 覆盖矩阵 E0–E11 + review.md 强制条件、
# FSM-001 report 移交 R-3「落账复核同 catch/sale ID 重试不重复入篮/加币」）。
# 运行：由 tests/unit/run_eco001_checks.py 在隔离临时副本内统一调度（禁止直接对主工程跑 Godot）。
# 约定与 CORE/CFG/FSM-001 一致：全部通过打印 "ECO001 ECONOMY PASS" 且 quit(0)；
# 首个失败打印 "ECO001 ECONOMY FAIL: <step>" 且 quit(1)。
# 纯数据层测试：只读 res:// 配置/夹具，不写文件、不触碰 user://、不依赖 Node/帧计数。
const EcoScript := preload("res://scripts/economy/economy_service.gd")
const FishScript := preload("res://scripts/economy/fish_instance.gd")
const FsmScript := preload("res://scripts/fishing/fishing_state_machine.gd")
const RngScript := preload("res://scripts/fishing/deterministic_rng.gd")
const ClockScript := preload("res://scripts/fishing/virtual_clock.gd")
const CatalogScript := preload("res://scripts/config/fish_species_catalog.gd")
const RuntimeScript := preload("res://scripts/config/runtime_config.gd")
const FIXTURE_DIR := "res://tests/unit/fixtures/cfg001/"
const INT64_MAX := 9223372036854775807
var _catalog: Dictionary
var _runtime: Dictionary
var _gate_seen_basket := -1
var _gate_seen_catches := -1
func _initialize() -> void:
	_catalog = CatalogScript.load_catalog("res://data/fish_species.json")
	_runtime = RuntimeScript.load_config("res://data/runtime_config.json")
	if _catalog.get("ok", false) != true or _runtime.get("ok", false) != true:
		_fail_ret("R0 base configs invalid (CFG-001 validators must pass first)")
		return
	for step in [_e0, _e1, _e2, _e3, _e4, _e5, _e6, _e7, _e8, _e9, _e10, _e11]:
		if not step.call():
			return
	print("ECO001 ECONOMY PASS"); quit(0)
# ---- E0：FishInstance 工厂/校验器原语（E4/E6 前置逐字段断言）----
func _e0() -> bool:
	if not _check(not FishScript.validate("not-a-dict"), "E0 non-dict must be invalid"):
		return false
	var fish := FishScript.make("catch-e0", (_catalog["species"] as Array)[0], "2026-11-11T08:30:00Z")
	if not _check(FishScript.validate(fish) and String(fish["instance_id"]) == "fish-catch-e0"
			and String(fish["source_event_id"]) == "catch-e0" and fish.size() == 5
			and int(fish["sale_price_at_catch"]) == 8, "E0 make() envelope / five-key schema / price snapshot"):
		return false
	for bad_time in ["", "2026-11-11T08:30:00", "2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z",
			"2025-02-29T00:00:00Z", "2026-11-11T24:00:00Z", "2026-11-11T08:60:00Z",
			"2026-11-11 08:30:00Z", "2026-11-11T08:30:00+08:00", "not-a-time", 42, null]:
		if not _check(not FishScript.timestamp_valid(bad_time), "E0 invalid UTC accepted: %s" % str(bad_time)):
			return false
	if not _check(FishScript.timestamp_valid("2024-02-29T23:59:59Z"), "E0 leap-day UTC rejected"):
		return false
	if not _check(FishScript.price_valid(0) and FishScript.price_valid(8) and FishScript.price_valid(8.0), "E0 valid price rejected"):
		return false
	for bad_price in [-1, 8.5, "8", null, true, -0.5, 9223372036854775808.0]:
		if not _check(not FishScript.price_valid(bad_price), "E0 invalid price accepted: %s" % str(bad_price)):
			return false
	var bad_price_fish := fish.duplicate(true); bad_price_fish["sale_price_at_catch"] = -5
	var missing := fish.duplicate(true); missing.erase("sale_price_at_catch")
	return _check(FishScript.price_invalid(bad_price_fish) and not FishScript.price_invalid(missing)
			and not FishScript.validate(missing), "E0 BAD_PRICE/BAD_STATE shape distinction")
# ---- E1：满篓阻断+恢复（T-ECO-01，FSM+经济联动；拒绝不消耗 RNG）----
func _e1() -> bool:
	var parts := _make_fsm(4001)
	var svc: EconomyService = _svc()
	if not _check(not parts.is_empty() and svc != null, "E1 setup"):
		return false
	var fsm = parts[0]; var rng = parts[1]
	var state := GameState.new()
	var seen_ids := {}
	for i in 10:  # 9 篓抛竿成功 + 第 10 次结算后满 10
		var cand := _catch_cycle(svc, fsm, state, _utc(i))
		var instance_id := "" if cand.is_empty() else "fish-" + String(cand["catch_event_id"])
		if not _check(not cand.is_empty() and not seen_ids.has(instance_id)
				and state.basket.size() == i + 1 and state.revision == i + 1, "E1 cycle %d" % i):
			return false
		seen_ids[instance_id] = true
	if not _check(not fsm.can_cast(state), "E1 can_cast must be false at full basket (T-ECO-01)"):
		return false
	var rng_before := int(rng.get_state())
	var rc: Dictionary = fsm.request_cast(state)
	if not _check(rc.get("ok") == false and String(rc["rejected_reason"]) == "BASKET_FULL"
			and String(rc["catch_event_id"]) == "" and int(rng.get_state()) == rng_before,
			"E1 full-basket cast rejected BASKET_FULL without consuming RNG"):
		return false
	var sold_instance := String((state.basket[0] as Dictionary)["instance_id"])
	var expect_gold := int((state.basket[0] as Dictionary)["sale_price_at_catch"])
	var sr: Dictionary = svc.sell_fish(state, "sale-e1", [sold_instance])
	if not _check(sr.get("ok") == true and String(sr["code"]) == ""
			and int(sr["gold_added"]) == expect_gold and state.wallet_gold == expect_gold,
			"E1 sale after full basket failed"):
		return false
	return _check(fsm.can_cast(state) and (fsm.request_cast(state) as Dictionary).get("ok") == true,
			"E1 cast must recover after sale (T-ECO-01)")
# ---- E2：catch 幂等（T-ECO-02：同 catch_event_id 共 100 次 → 恰 1 条鱼）----
func _e2() -> bool:
	var svc: EconomyService = _svc()
	if not _check(svc != null, "E2 setup"):
		return false
	var state := GameState.new()
	var first: Dictionary = svc.commit_catch(state, "catch-e2", "river_carp", _utc(1))
	if not _check(first.get("ok") == true and String(first["code"]) == ""
			and String(first["instance_id"]) == "fish-catch-e2", "E2 first commit envelope"):
		return false
	for i in 99:
		var retry: Dictionary = svc.commit_catch(state, "catch-e2", "river_carp", _utc(1))
		if not _check(retry.get("ok") == true and String(retry["code"]) == "ALREADY_APPLIED"
				and String(retry["instance_id"]) == "fish-catch-e2", "E2 retry %d envelope" % i):
			return false
	return _check(state.basket.size() == 1 and state.processed_catch_ids.size() == 1
			and state.revision == 1 and state.wallet_gold == 0
			and int((state.basket[0] as Dictionary)["sale_price_at_catch"]) == 8,
			"E2 100 retries must yield exactly 1 fish / 1 id / +1 revision")
# ---- E3：sale 幂等（T-ECO-03：同 sale_event_id 共 100 次 → 金币恰 +1 次，实例不复活）----
func _e3() -> bool:
	var svc: EconomyService = _svc()
	if not _check(svc != null, "E3 setup"):
		return false
	var state := GameState.new()
	if not _apply_commit(svc, state, "catch-e3a", "river_carp", _utc(1)):
		return false
	if not _apply_commit(svc, state, "catch-e3b", "silver_perch", _utc(2)):
		return false
	var sold := ["fish-catch-e3a", "fish-catch-e3b"]
	if not _apply_sell(svc, state, "sale-e3", sold, 24):
		return false
	for i in 99:
		var retry_ids: Array = sold.duplicate(true)
		if i % 2 == 1:
			retry_ids.reverse()  # 实例顺序不影响同一 sale ID 的指纹（review 条件 2）
		var retry: Dictionary = svc.sell_fish(state, "sale-e3", retry_ids)
		if not _check(retry.get("ok") == true and String(retry["code"]) == "ALREADY_APPLIED"
				and int(retry["gold_added"]) == 0, "E3 retry %d envelope" % i):
			return false
	return _check(state.wallet_gold == 24 and state.basket.size() == 0
			and state.processed_sale_ids.size() == 1 and state.revision == 3,
			"E3 100 sales must add gold exactly once, no fish revival")
# ---- E4：错误矩阵（T-ECO-04：稳定错误码 + 零状态副作用 + wallet_gold ≥ 0）----
func _e4() -> bool:
	var svc: EconomyService = _svc()
	if not _check(svc != null, "E4 setup"):
		return false
	var state := GameState.new()
	if not _apply_commit(svc, state, "catch-e4", "golden_trout", _utc(2)):
		return false
	# A. 售不存在实例 ID → UNKNOWN_INSTANCE（越权 ID）
	if not _reject(svc, true, state, "sale-e4a", ["fish-nope"], null, "UNKNOWN_INSTANCE"):
		return false
	# B. 清单重复 ID 按 §5 去重，只计一次；C. 同 sale ID 重试 → ALREADY_APPLIED、不加双币
	var gold_before := int(state.wallet_gold)
	var dedup: Dictionary = svc.sell_fish(state, "sale-e4b", ["fish-catch-e4", "fish-catch-e4"])
	if not _check(dedup.get("ok") == true and String(dedup["code"]) == ""
			and int(dedup["gold_added"]) == 32 and state.wallet_gold == gold_before + 32,
			"E4 duplicated ids must be deduped and counted once"):
		return false
	var again: Dictionary = svc.sell_fish(state, "sale-e4b", ["fish-catch-e4"])
	if not _check(again.get("ok") == true and String(again["code"]) == "ALREADY_APPLIED"
			and int(again["gold_added"]) == 0 and state.wallet_gold == gold_before + 32,
			"E4 same sale id retry must be ALREADY_APPLIED"):
		return false
	# D. 畸形实例清单：空数组/非字符串元素/空串元素/非数组
	if not (_reject(svc, true, state, "sale-e4d", [], null, "BAD_INSTANCE_LIST")
			and _reject(svc, true, state, "sale-e4d", ["fish-catch-e4", 42], null, "BAD_INSTANCE_LIST")
			and _reject(svc, true, state, "sale-e4d", [""], null, "BAD_INSTANCE_LIST")
			and _reject(svc, true, state, "sale-e4d", "fish-catch-e4", null, "BAD_INSTANCE_LIST")):
		return false
	# E. 非法 species / 空或非法 event ID / 非法 UTC
	if not (_reject(svc, false, state, "catch-e4e", "no_such_fish", _utc(3), "UNKNOWN_SPECIES")
			and _reject(svc, false, state, "catch-e4e", 42, _utc(3), "UNKNOWN_SPECIES")
			and _reject(svc, false, state, "", "river_carp", _utc(3), "BAD_EVENT_ID")
			and _reject(svc, false, state, 42, "river_carp", _utc(3), "BAD_EVENT_ID")
			and _reject(svc, false, state, "catch-e4e", "river_carp", "2026-13-01T00:00:00Z", "BAD_TIMESTAMP")
			and _reject(svc, false, state, "catch-e4e", "river_carp", 12345, "BAD_TIMESTAMP")):
		return false
	# F. 满篓 commit（容量冲突）
	var full := GameState.new()
	for i in 10:
		if not _apply_commit(svc, full, "catch-full-%d" % i, "river_carp", _utc(i + 4)):
			return false
	return _reject(svc, false, full, "catch-full-overflow", "river_carp", _utc(1), "BASKET_FULL") \
			and _e4_tail(svc, state)
## E4 后半：篮内畸形、金币溢出、未初始化/null（拆开避免单函数过长）。
func _e4_tail(svc: EconomyService, state: GameState) -> bool:
	# G. 篮内畸形：坏价格 → BAD_PRICE；畸形元素/重复 instance ID → BAD_STATE
	var neg_price := GameState.new()
	var bad_fish := FishScript.make("catch-neg", (_catalog["species"] as Array)[0], _utc(1))
	bad_fish["sale_price_at_catch"] = -5; neg_price.basket = [bad_fish]
	if not (_reject(svc, false, neg_price, "catch-x", "river_carp", _utc(1), "BAD_PRICE")
			and _reject(svc, true, neg_price, "sale-x", ["fish-catch-neg"], null, "BAD_PRICE")):
		return false
	var malformed := GameState.new(); malformed.basket = [42]
	var dupfish := GameState.new()
	var first_fish := FishScript.make("catch-dup", (_catalog["species"] as Array)[0], _utc(1))
	dupfish.basket = [first_fish, first_fish.duplicate(true)]
	if not (_reject(svc, false, malformed, "catch-x", "river_carp", _utc(1), "BAD_STATE")
			and _reject(svc, true, dupfish, "sale-x", ["fish-catch-dup"], null, "BAD_STATE")):
		return false
	# H. 金币溢出：wallet=INT64_MAX 售 8 金币鱼 → GOLD_OVERFLOW，绝不绕回为负
	var rich := GameState.new()
	if not _apply_commit(svc, rich, "catch-rich", "river_carp", _utc(1)):
		return false
	rich.wallet_gold = INT64_MAX
	if not _reject(svc, true, rich, "sale-rich", ["fish-catch-rich"], null, "GOLD_OVERFLOW"):
		return false
	if not _check(rich.wallet_gold == INT64_MAX and state.wallet_gold >= 0, "E4 gold must never wrap negative"):
		return false
	# I. 未初始化服务 / null GameState
	var bare: EconomyService = EcoScript.new()
	if not (_reject(bare, false, state, "catch-e4i", "river_carp", _utc(1), "NOT_INITIALIZED")
			and _reject(bare, true, state, "sale-e4i", ["fish-catch-e4"], null, "NOT_INITIALIZED")):
		return false
	return _reject(svc, false, null, "catch-e4i", "river_carp", _utc(1), "NULL_GAME_STATE") \
			and _reject(svc, true, null, "sale-e4i", ["fish-catch-e4"], null, "NULL_GAME_STATE")
# ---- E5：同 ID 异参冲突（INTERFACES §5「不以 AlreadyApplied 掩盖」+ 记入 transaction_log）----
func _e5() -> bool:
	var svc: EconomyService = _svc()
	if not _check(svc != null, "E5 setup"):
		return false
	var state := GameState.new()
	if not _apply_commit(svc, state, "catch-e5", "river_carp", _utc(1)):
		return false
	if not (_reject(svc, false, state, "catch-e5", "silver_perch", _utc(1), "CONFLICT_CATCH_PARAMS")
			and _reject(svc, false, state, "catch-e5", "river_carp", _utc(2), "CONFLICT_CATCH_PARAMS")):
		return false
	if not _check(state.basket.size() == 1 and state.revision == 1, "E5 catch conflict must not double-fish"):
		return false
	if not _apply_sell(svc, state, "sale-e5", ["fish-catch-e5"], 8):
		return false
	if not _reject(svc, true, state, "sale-e5", ["fish-e5-other"], null, "CONFLICT_SALE_PARAMS"):
		return false
	if not _check(state.wallet_gold == 8 and state.revision == 2, "E5 sale conflict must not double-gold"):
		return false
	var saw_catch := false; var saw_sale := false
	for entry in svc.get_transaction_log():
		if String(entry["action"]) == "commit_catch" and String(entry["code"]) == "CONFLICT_CATCH_PARAMS":
			saw_catch = true
		if String(entry["action"]) == "sell_fish" and String(entry["code"]) == "CONFLICT_SALE_PARAMS":
			saw_sale = true
	return _check(saw_catch and saw_sale, "E5 conflicts must be recorded in transaction_log")
# ---- E6：捕获时价格快照（2026-11-11 裁定：目录变化不追溯已捕获实例）----
func _e6() -> bool:
	var svc: EconomyService = _svc()
	if not _check(svc != null, "E6 setup"):
		return false
	var state := GameState.new()
	if not _apply_commit(svc, state, "catch-e6", "golden_trout", _utc(1)):
		return false
	var fish: Dictionary = state.basket[0]
	if not _check(int(fish["sale_price_at_catch"]) == 32, "E6 snapshot must equal catalog price at catch"):
		return false
	# 篡改目录价格副本（res:// data/ 只读不改）→ 售鱼仍按快照 32 计，不按 999
	var tampered: Dictionary = _catalog.duplicate(true)
	(tampered["species"] as Array)[2]["base_price"] = 999
	var svc2: EconomyService = _svc_with(tampered, _runtime)
	if not _check(svc2 != null, "E6 tampered-catalog service setup"):
		return false
	var result: Dictionary = svc2.sell_fish(state, "sale-e6", [String(fish["instance_id"])])
	return _check(result.get("ok") == true and int(result["gold_added"]) == 32 and state.wallet_gold == 32,
			"E6 sale must pay sale_price_at_catch snapshot, not tampered catalog price")
# ---- E7：失败零副作用（每类失败逐字段深比较，含篮元素顺序）----
func _e7() -> bool:
	var svc: EconomyService = _svc()
	if not _check(svc != null, "E7 setup"):
		return false
	var state := GameState.new()
	if not _apply_commit(svc, state, "catch-e7", "river_carp", _utc(1)):
		return false
	if not _apply_sell(svc, state, "sale-e7a", ["fish-catch-e7"], 8):
		return false
	if not _apply_commit(svc, state, "catch-e7c", "silver_perch", _utc(2)):
		return false
	if not _check(svc.set_persistence_gate(Callable(self, "_gate_false")).get("ok") == true, "E7 gate install"):
		return false
	# 坏 GameState 在门前即被拒（BAD_STATE）；合法新事务走到门 → PERSIST_FAILED。
	var malformed := GameState.new(); malformed.basket = ["not-a-dict"]
	if not (_reject(svc, true, malformed, "sale-e7", ["fish-x"], null, "BAD_STATE")
			and _reject(svc, false, state, "catch-e7p", "river_carp", _utc(3), "PERSIST_FAILED")
			and _reject(svc, true, state, "sale-e7p", ["fish-catch-e7c"], null, "PERSIST_FAILED")):
		return false
	if not _check(not (svc.snapshot_ledger()["processed_catches"] as Dictionary).has("catch-e7p")
			and not (svc.snapshot_ledger()["processed_sales"] as Dictionary).has("sale-e7p"),
			"E7 rejected tx must not enter ledger"):
		return false
	if not _check(svc.set_persistence_gate(Callable(self, "_gate_true")).get("ok") == true, "E7 recovery gate install"):
		return false
	if not _reject(svc, false, state, "catch-e7", "golden_trout", _utc(1), "CONFLICT_CATCH_PARAMS"):
		return false
	if not _reject(svc, true, state, "sale-e7a", ["fish-other"], null, "CONFLICT_SALE_PARAMS"):
		return false
	var full := GameState.new()
	for i in 10:
		if not _apply_commit(svc, full, "catch-e7f-%d" % i, "silver_perch", _utc(1)):
			return false
	if not _reject(svc, false, full, "catch-e7f-x", "silver_perch", _utc(1), "BASKET_FULL"):
		return false
	return _check(state.wallet_gold == 8 and int(state.revision) == 3 and state.basket.size() == 1
			and int(state.wallet_gold) >= 0, "E7 authoritative state drifted after rejects")
# ---- E8：FSM↔经济集成（FSM-001 R-3：候选 payload 逐字段落账）----
func _e8() -> bool:
	var parts := _make_fsm(4002)
	var svc: EconomyService = _svc()
	if not _check(not parts.is_empty() and svc != null, "E8 setup"):
		return false
	var fsm = parts[0]
	var state := GameState.new()
	var rc: Dictionary = fsm.request_cast(state)
	if not _check(rc.get("ok") == true, "E8 cast"):
		return false
	fsm.tick_effective(5.0); fsm.tick_effective(200.0); fsm.tick_effective(1.0); fsm.tick_effective(1.0)
	var cand: Dictionary = fsm.produce_catch_candidate()
	if not _check(cand.get("ok") == true and int(fsm.get_state()) == int(FsmScript.State.SETTLEMENT)
			and String(cand["catch_event_id"]) == String(rc["catch_event_id"]),
			"E8 candidate at SETTLEMENT with matching event id"):
		return false
	var catch_id := String(cand["catch_event_id"])
	var result: Dictionary = svc.commit_catch(state, catch_id, String(cand["species_id"]), "2026-11-11T16:00:00Z")
	if not _check(result.get("ok") == true and String(result["code"]) == "" and state.basket.size() == 1,
			"E8 commit envelope %s" % str(result)):
		return false
	var fish: Dictionary = state.basket[0]
	if not _check(String(fish["instance_id"]) == "fish-" + catch_id
			and String(fish["source_event_id"]) == catch_id
			and String(fish["species_id"]) == String(cand["species_id"])
			and int(fish["sale_price_at_catch"]) == int((cand["weight_snapshot"] as Dictionary)["base_price"])
			and String(fish["caught_at_utc"]) == "2026-11-11T16:00:00Z"
			and FishScript.validate(fish),
			"E8 committed fish must match candidate payload field-by-field (UTC verbatim)"):
		return false
	var ack: Dictionary = fsm.ack_settlement(catch_id, true)
	var rc2: Dictionary = fsm.request_cast(state)
	return _check(ack.get("ok") == true and String(ack["next_state"]) == "IDLE"
			and rc2.get("ok") == true and String(rc2["catch_event_id"]) != catch_id,
			"E8 ack→IDLE and re-cast must yield a new unique event id")
# ---- E9：非法配置拒绝（T-CONF-01 经济交界：复用 cfg001 夹具 + ConfigGate）----
func _e9() -> bool:
	var bad_runtime: Dictionary = RuntimeScript.load_config(FIXTURE_DIR + "min_gt_max.json")
	var bad_catalog: Dictionary = CatalogScript.load_catalog(FIXTURE_DIR + "dup_id.json")
	if not _check(bad_runtime.get("ok") == false and bad_catalog.get("ok") == false, "E9 cfg001 fixtures must be invalid"):
		return false
	var svc: EconomyService = _svc()
	var live_state := GameState.new()
	if not _check(svc != null, "E9 reinitialize setup") or not _apply_commit(svc, live_state, "catch-e9-live", "river_carp", _utc(1)):
		return false
	var init_runtime: Dictionary = svc.initialize(_catalog, bad_runtime)
	var init_catalog: Dictionary = svc.initialize(bad_catalog, _runtime)
	var init_both: Dictionary = svc.initialize(bad_catalog, bad_runtime)
	if not _check(String(init_runtime["error_code"]) == "runtime:MIN_GT_MAX"
			and String(init_catalog["error_code"]) == "catalog:DUP_ID"
			and String(init_both["error_code"]).contains("catalog:DUP_ID")
			and String(init_both["error_code"]).contains("runtime:MIN_GT_MAX"),
			"E9 gate codes runtime:/catalog: prefixed"):
		return false
	var state := live_state
	if not (_reject(svc, false, state, "catch-e9", "river_carp", _utc(1), "NOT_INITIALIZED")
			and _reject(svc, true, state, "sale-e9", ["fish-x"], null, "NOT_INITIALIZED")):
		return false
	var restore: Dictionary = svc.restore_ledger(state, {"processed_catches": {}, "processed_sales": {}})
	return _check(restore.get("ok") == false and String(restore["code"]) == "NOT_INITIALIZED",
			"E9 restore_ledger must be NOT_INITIALIZED after failed initialize")
# ---- E10：持久化门失败/错误/污染副本（review 条件 4；本票零写盘）----
func _e10() -> bool:
	var s1: EconomyService = _svc()
	if not _check(s1 != null, "E10 setup"):
		return false
	var state := GameState.new()
	if not _apply_commit(s1, state, "catch-e10", "river_carp", _utc(1)):  # 默认恒真门
		return false
	if not _check(s1.set_persistence_gate(Callable(self, "_gate_false")).get("ok") == true, "E10 false-gate install"):
		return false
	if not (_reject(s1, false, state, "catch-e10b", "river_carp", _utc(2), "PERSIST_FAILED")
			and _reject(s1, true, state, "sale-e10", ["fish-catch-e10"], null, "PERSIST_FAILED")):
		return false
	if not _check(state.basket.size() == 1 and state.wallet_gold == 0 and state.revision == 1
			and not (s1.snapshot_ledger()["processed_catches"] as Dictionary).has("catch-e10b"),
			"E10 false gate must not commit or enter ledger"):
		return false
	var s2: EconomyService = _svc(); s2.set_persistence_gate(Callable(self, "_gate_nonbool"))
	if not _reject(s2, false, GameState.new(), "catch-e10c", "river_carp", _utc(1), "PERSIST_FAILED"):
		return false
	# 失效/报错 Callable（is_valid()==false）：fail-closed，绝不调用
	var s3: EconomyService = _svc()  # 默认恒真门先落一条鱼，保证 sell 一路走到门
	var state3 := GameState.new()
	if not _apply_commit(s3, state3, "catch-e10d", "river_carp", _utc(1)):
		return false
	s3.set_persistence_gate(Callable())
	if not _reject(s3, false, state3, "catch-e10d2", "river_carp", _utc(2), "PERSIST_FAILED"):
		return false
	s3.set_persistence_gate(Callable(GameState.new(), "definitely_missing_method"))
	if not _reject(s3, true, state3, "sale-e10d", ["fish-catch-e10d"], null, "PERSIST_FAILED"):
		return false
	if not _check(state3.basket.size() == 1 and state3.wallet_gold == 0 and state3.revision == 1,
			"E10 invalid gate must not commit"):
		return false
	# 投毒门：修改收到的深拷贝后返回 true → 发布结果绝不被污染（门只见副本）
	var s4: EconomyService = _svc(); s4.set_persistence_gate(Callable(self, "_gate_poison"))
	var state2 := GameState.new()
	var commit: Dictionary = s4.commit_catch(state2, "catch-e10e", "golden_trout", _utc(1))
	if not _check(commit.get("ok") == true and String(commit["code"]) == ""
			and _gate_seen_basket == 1 and _gate_seen_catches == 1,
			"E10 poison commit ok; gate must see full next_state + pending ledger (basket=%d catches=%d)"
			% [_gate_seen_basket, _gate_seen_catches]):
		return false
	if not _check(state2.basket.size() == 1 and state2.wallet_gold == 0 and state2.revision == 1
			and (s4.snapshot_ledger()["processed_catches"] as Dictionary).has("catch-e10e"),
			"E10 poison gate polluted committed state/ledger (commit)"):
		return false
	var sold: Dictionary = s4.sell_fish(state2, "sale-e10e", ["fish-catch-e10e"])
	return _check(sold.get("ok") == true and int(sold["gold_added"]) == 32
			and state2.wallet_gold == 32 and state2.basket.size() == 0 and _gate_seen_basket == 0,
			"E10 poison gate polluted committed state (sell)")
# ---- E11：跨实例账本恢复（review 条件 5；坏 ledger fail-closed）----
func _e11() -> bool:
	var svc1: EconomyService = _svc()
	if not _check(svc1 != null, "E11 setup"):
		return false
	var state := GameState.new()
	if not _apply_commit(svc1, state, "catch-e11", "river_carp", _utc(1)):
		return false
	if not _apply_sell(svc1, state, "sale-e11", ["fish-catch-e11"], 8):
		return false
	var ledger := svc1.snapshot_ledger()
	(ledger["processed_catches"] as Dictionary).erase("catch-e11")  # 快照必须是深拷贝
	if not _check((svc1.snapshot_ledger()["processed_catches"] as Dictionary).has("catch-e11"),
			"E11 snapshot_ledger must be a deep copy"):
		return false
	ledger = svc1.snapshot_ledger()  # 恢复用完好快照（上面被污染的副本仅证明深拷贝）
	var svc2: EconomyService = _svc()
	if not _check(svc2 != null and svc2.restore_ledger(state, ledger).get("ok") == true,
			"E11 restore of consistent ledger must succeed"):
		return false
	var commit: Dictionary = svc2.commit_catch(state, "catch-e11", "river_carp", _utc(1))
	if not _check(commit.get("ok") == true and String(commit["code"]) == "ALREADY_APPLIED"
			and String(commit["instance_id"]) == "fish-catch-e11", "E11 restored ledger must keep catch idempotence"):
		return false
	if not _reject(svc2, false, state, "catch-e11", "golden_trout", _utc(1), "CONFLICT_CATCH_PARAMS"):
		return false
	var sell: Dictionary = svc2.sell_fish(state, "sale-e11", ["fish-catch-e11"])
	if not _check(sell.get("ok") == true and String(sell["code"]) == "ALREADY_APPLIED"
			and int(sell["gold_added"]) == 0, "E11 restored ledger must keep sale idempotence"):
		return false
	if not _reject(svc2, true, state, "sale-e11", ["fish-x"], null, "CONFLICT_SALE_PARAMS"):
		return false
	if not _check(state.wallet_gold == 8 and int(state.revision) == 2 and state.basket.size() == 0,
			"E11 restored retries must have zero side effects"):
		return false
	return _e11_bad_ledgers(svc1, svc2, state)
## E11 后半：坏 ledger fail-closed（多键 / 与 processed ids 不一致 / 未知 ID / 指纹形状坏 / 已售指向在篮鱼）。
func _e11_bad_ledgers(svc1: EconomyService, svc2: EconomyService, state: GameState) -> bool:
	var bad_extra: Dictionary = svc1.snapshot_ledger()
	bad_extra["extra"] = 1
	var bad_unknown: Dictionary = svc1.snapshot_ledger()
	(bad_unknown["processed_catches"] as Dictionary)["catch-bogus"] = \
			{"species_id": "river_carp", "caught_at_utc": _utc(1)}
	var bad_shape: Dictionary = svc1.snapshot_ledger()
	(bad_shape["processed_catches"] as Dictionary)["catch-e11"] = {"species_id": "river_carp"}
	if not (_reject_restore(svc2, state, bad_extra, "BAD_LEDGER")
			and _reject_restore(svc2, state, {"processed_catches": {}, "processed_sales": {}}, "BAD_LEDGER")
			and _reject_restore(svc2, state, bad_unknown, "BAD_LEDGER")
			and _reject_restore(svc2, state, bad_shape, "BAD_LEDGER")):
		return false
	var svc3: EconomyService = _svc()
	var state3 := GameState.new()
	if not _apply_commit(svc3, state3, "catch-e11z", "river_carp", _utc(1)):
		return false
	state3.processed_sale_ids.append("sale-e11z")  # 账本称已出售，但实例仍在篮中 → 不一致
	var bad_revived: Dictionary = svc3.snapshot_ledger()
	(bad_revived["processed_sales"] as Dictionary)["sale-e11z"] = ["fish-catch-e11z"]
	if not _reject_restore(svc3, state3, bad_revived, "BAD_LEDGER"):
		return false
	if not _check(svc2.restore_ledger(state, svc1.snapshot_ledger()).get("ok") == true,
			"E11 restore after failed attempts must still succeed"):
		return false
	var again: Dictionary = svc2.commit_catch(state, "catch-e11", "river_carp", _utc(1))
	return _check(again.get("ok") == true and String(again["code"]) == "ALREADY_APPLIED",
			"E11 idempotence must survive failed restores")
# ---- 共享辅助 ----
func _utc(index: int) -> String:
	return "2026-11-11T%02d:00:00Z" % (index % 24)
func _svc() -> EconomyService:
	return _svc_with(_catalog, _runtime)
func _svc_with(catalog: Dictionary, runtime: Dictionary) -> EconomyService:
	var svc: EconomyService = EcoScript.new()
	if svc.initialize(catalog, runtime).get("ok") != true:
		return null
	return svc
func _make_fsm(seed_value: int) -> Array:
	var rng: DeterministicRng = RngScript.new()
	var clock: VirtualClock = ClockScript.new()
	if rng.set_seed(seed_value).get("ok") != true:
		return []
	var fsm: FishingStateMachine = FsmScript.new()
	if fsm.initialize(_catalog, _runtime, rng, clock, {}).get("ok") != true:
		return []
	return [fsm, rng, clock]
## 完整周期 + 落账：request_cast → ticks → candidate → commit_catch → ack(true) → IDLE。
func _catch_cycle(svc: EconomyService, fsm, state: GameState, utc: String) -> Dictionary:
	var rc: Dictionary = fsm.request_cast(state)
	if rc.get("ok") != true:
		return {}
	fsm.tick_effective(5.0); fsm.tick_effective(200.0); fsm.tick_effective(1.0); fsm.tick_effective(1.0)
	var cand: Dictionary = fsm.produce_catch_candidate()
	if cand.get("ok") != true:
		return {}
	var commit: Dictionary = svc.commit_catch(state, String(cand["catch_event_id"]), String(cand["species_id"]), utc)
	if commit.get("ok") != true or String(commit["code"]) != "":
		return {}
	var ack: Dictionary = fsm.ack_settlement(String(cand["catch_event_id"]), true)
	if ack.get("ok") != true or String(ack["next_state"]) != "IDLE":
		return {}
	return cand
func _apply_commit(svc: EconomyService, state: GameState, catch_id: String,
		species_id: String, utc: String) -> bool:
	var result: Dictionary = svc.commit_catch(state, catch_id, species_id, utc)
	if result.get("ok") != true or String(result["code"]) != "":
		return _fail_ret("apply commit %s -> %s" % [catch_id, str(result)])
	return true
func _apply_sell(svc: EconomyService, state: GameState, sale_id: String,
		instance_ids: Array, want_gold: int) -> bool:
	var result: Dictionary = svc.sell_fish(state, sale_id, instance_ids)
	if result.get("ok") != true or String(result["code"]) != "" or int(result["gold_added"]) != want_gold:
		return _fail_ret("apply sell %s -> %s" % [sale_id, str(result)])
	return true
## 拒绝断言：ok=false、稳定码、commit→空 instance_id / sell→gold_added=0、
## 前后 GameState 逐字段深比较（含篮元素顺序）、金币非负（零副作用）。
func _reject(svc: EconomyService, sell: bool, state: GameState, event_id: Variant,
		arg: Variant, utc: Variant, want: String) -> bool:
	var before := {} if state == null else _state_snapshot(state)
	var result: Dictionary = svc.sell_fish(state, event_id, arg) if sell else svc.commit_catch(state, event_id, arg, utc)
	if result.get("ok") != false:
		return _fail_ret("reject %s expected reject, got %s" % [str(event_id), str(result)])
	if String(result["code"]) != want:
		return _fail_ret("reject %s code=%s want=%s" % [str(event_id), str(result["code"]), want])
	var envelope_ok := int(result["gold_added"]) == 0 if sell else String(result["instance_id"]) == ""
	if not envelope_ok:
		return _fail_ret("reject %s envelope must stay empty" % str(event_id))
	if state != null and (not _deep_eq(before, _state_snapshot(state)) or int(state.wallet_gold) < 0):
		return _fail_ret("reject %s mutated GameState (zero side effect violated)" % str(event_id))
	return true
func _reject_restore(svc: EconomyService, state: GameState, ledger: Variant, want: String) -> bool:
	var before := _state_snapshot(state)
	var result: Dictionary = svc.restore_ledger(state, ledger)
	if result.get("ok") != false or String(result["code"]) != want:
		return _fail_ret("restore expected %s, got %s" % [want, str(result)])
	if not _deep_eq(before, _state_snapshot(state)):
		return _fail_ret("failed restore mutated GameState")
	return true
func _state_snapshot(state: GameState) -> Dictionary:
	return {
		"save_version": state.save_version, "revision": state.revision,
		"wallet_gold": state.wallet_gold, "basket_capacity": state.basket_capacity,
		"basket": state.basket.duplicate(true),
		"processed_catch_ids": state.processed_catch_ids.duplicate(true),
		"processed_sale_ids": state.processed_sale_ids.duplicate(true),
		"fishing_checkpoint": state.fishing_checkpoint.duplicate(true),
		"desktop_window": state.desktop_window.duplicate(true),
	}
func _check(condition: bool, msg: String) -> bool:
	return true if condition else _fail_ret(msg)
## 递归深比较（逐字段断言；容器逐元素/逐键，标量用 ==）。
func _deep_eq(a: Variant, b: Variant) -> bool:
	if (a is Array) and (b is Array):
		var list_a: Array = a
		var list_b: Array = b
		if list_a.size() != list_b.size():
			return false
		for index in list_a.size():
			if not _deep_eq(list_a[index], list_b[index]):
				return false
		return true
	if (a is Dictionary) and (b is Dictionary):
		var dict_a: Dictionary = a
		var dict_b: Dictionary = b
		if dict_a.size() != dict_b.size():
			return false
		for key in dict_a:
			if not dict_b.has(key) or not _deep_eq(dict_a[key], dict_b[key]):
				return false
		return true
	if (a is Array) != (b is Array) or (a is Dictionary) != (b is Dictionary):
		return false
	return a == b
# ---- 注入测试门（仅存在于内存测试；不写任何文件）----
func _gate_false(_payload: Dictionary) -> bool:
	return false
func _gate_true(_payload: Dictionary) -> bool:
	return true
func _gate_nonbool(_payload: Dictionary) -> Variant:
	return 1  # 非 bool：必须按 PERSIST_FAILED 拒绝
func _gate_poison(payload: Dictionary) -> bool:
	var next_state: Dictionary = payload["next_state"]
	var ledger: Dictionary = payload["ledger"]
	_gate_seen_basket = (next_state["basket"] as Array).size()
	_gate_seen_catches = (ledger["processed_catches"] as Dictionary).size()
	next_state["basket"].clear()
	next_state["wallet_gold"] = 777777
	next_state["processed_catch_ids"].clear()
	next_state["processed_sale_ids"].clear()
	next_state["revision"] = -999
	(ledger["processed_catches"] as Dictionary).clear()
	(ledger["processed_sales"] as Dictionary).clear()
	return true
func _fail_ret(msg: String) -> bool:
	print("ECO001 ECONOMY FAIL: " + msg); quit(1)
	return false
