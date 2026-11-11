class_name EconomyService
extends RefCounted
# ECO-001：经济事务服务（INTERFACES_AND_DATA §5/§6、ARCHITECTURE §2/§5、SDD V01-E01/E02/S01、
# DECISION SDD-143/155-156/172/173、tasks/evidence/ECO-001/plan.md §4 + review.md 强制条件）。
# 不变量（plan §4，全部由 tests/unit/test_eco001_economy.gd 断言）：
# - 纯 RefCounted 数据层：无 Node/_process/_physics_process、无 Engine 帧/时间 API、
#   不读写 user://、无任何文件写入（持久化门只是注入点，本票默认恒真门=纯内存模式）。
# - GameState 是唯一经济权威：本服务经引用一次性提交 wallet_gold / basket /
#   processed_catch_ids / processed_sale_ids / revision；所有命令「先全量校验 → 构造 next
#   值 →（持久化门）→ 一次性发布」，任一失败路径对 GameState 零副作用，绝不乐观加币。
# - 幂等：同 catch_event_id ≤1 条鱼、同 sale_event_id ≤1 次加币，重试返回 ALREADY_APPLIED；
#   同 ID 异参 → CONFLICT_CATCH_PARAMS / CONFLICT_SALE_PARAMS 并记入内存 transaction_log，
#   不以 AlreadyApplied 掩盖不一致请求（INTERFACES §5）。
# - 售鱼清单按 §5 去重计价；实例顺序不影响同一 sale_event_id 的参数指纹（review 条件 2）。
# - wallet_gold 恒为非负整数；金币求和/加法显式判溢出（GOLD_OVERFLOW），绝不绕回为负。
# - basket.size() <= basket_capacity 恒成立（容量 10 候选值只读，本服务绝不改配置值）。
# - 命令同步、单线程、一次一条（同一命令队列串行处理的接口形状）；GameController/UI（后续票）
#   必须仅经本服务变更经济状态，禁止旁路。
# - 命令参数以 Variant 收参：非法类型必须返回 §4 稳定错误码，而非引擎调用错误（plan §4）。

const ERROR_NOT_INITIALIZED := "NOT_INITIALIZED"
const ERROR_NULL_GAME_STATE := "NULL_GAME_STATE"
const ERROR_BAD_STATE := "BAD_STATE"
const ERROR_BAD_EVENT_ID := "BAD_EVENT_ID"
const ERROR_UNKNOWN_SPECIES := "UNKNOWN_SPECIES"
const ERROR_BAD_TIMESTAMP := "BAD_TIMESTAMP"
const ERROR_BASKET_FULL := "BASKET_FULL"
const ERROR_ALREADY_APPLIED := "ALREADY_APPLIED"
const ERROR_CONFLICT_CATCH_PARAMS := "CONFLICT_CATCH_PARAMS"
const ERROR_CONFLICT_SALE_PARAMS := "CONFLICT_SALE_PARAMS"
const ERROR_UNKNOWN_INSTANCE := "UNKNOWN_INSTANCE"
const ERROR_BAD_INSTANCE_LIST := "BAD_INSTANCE_LIST"
const ERROR_BAD_PRICE := "BAD_PRICE"
const ERROR_GOLD_OVERFLOW := "GOLD_OVERFLOW"
const ERROR_PERSIST_FAILED := "PERSIST_FAILED"
const ERROR_BAD_LEDGER := "BAD_LEDGER"  # restore_ledger 专用：坏形状或与 processed ids 不一致

const INT64_MAX := 9223372036854775807  # int64 上界：金币加法显式判溢出，禁止绕回

## 内存内结构化事务日志（成功与拒绝均记录；供测试断言与 LOG-001 后续复用；不写任何文件）。
var transaction_log: Array = []

var _initialized := false
var _catalog_by_id: Dictionary = {}  # species_id -> 目录条目深拷贝（只读快照）
var _catch_ledger: Dictionary = {}  # catch_event_id -> {species_id, caught_at_utc} 参数指纹
var _sale_ledger: Dictionary = {}  # sale_event_id -> 去重升序 instance_id 清单指纹
var _gate: Callable = Callable()
var _gate_set := false  # false = 默认恒真门（内存模式，本票）；true = 已注入持久化门
var _log_seq := 0


## 合法启动：先过 ConfigGate.can_start_economy（T-CONF-01 经济交界）。任一非法 →
## ok=false + "catalog:<CODE>"/"runtime:<CODE>"（多项以 ";" 连接），零副作用、零默认值，
## 且拒绝后全部命令返回 NOT_INITIALIZED。成功后仅保存鱼种价格/字段只读快照，不改配置。
func initialize(catalog: Dictionary, runtime: Dictionary) -> Dictionary:
	if not ConfigGate.can_start_economy(catalog, runtime):
		var reasons := ConfigGate.blocked_reasons(catalog, runtime)
		var code := ";".join(reasons)
		if code.is_empty():
			code = "gate:UNVERIFIED"
		return _init_reject(code)
	var by_id: Dictionary = {}
	var raw_species: Variant = catalog["species"]
	# can_start_economy 只保证 species 为非空数组；逐元素防御性校验（fail-closed，零副作用）。
	for element in (raw_species as Array):
		if not (element is Dictionary):
			return _init_reject("catalog:BAD_SHAPE")
		var entry: Dictionary = element
		if not (entry.get("id") is String) or String(entry.get("id")).is_empty():
			return _init_reject("catalog:BAD_SHAPE")
		if not entry.has("base_price") or not FishInstance.price_valid(entry["base_price"]):
			return _init_reject("catalog:BAD_SHAPE")
		by_id[String(entry["id"])] = entry.duplicate(true)
	_catalog_by_id = by_id
	_initialized = true
	_append_log("initialize", "", "", true, {})
	return {"ok": true, "error_code": ""}


## 注入持久化门（INTERFACES §6 注入点；SAVE-001 在此注入 SaveService 原子写盘，
## 实现「先持久化成功、后发布已确认」）。gate(payload: Dictionary) -> bool，
## payload = {"next_state": 完整 next GameState 深拷贝, "ledger": 提交后指纹账本深拷贝}；
## 门只收到副本，对副本的任何修改不影响实时 GameState / 内部账本（review 条件 4）。
## 仅当门正常返回布尔 true 才发布；返回 false、非 bool、或非 true 值一律 PERSIST_FAILED；
## Callable 失效/报错（is_valid()==false，含 null Callable、失效目标）同样 fail-closed
## 判 PERSIST_FAILED 且绝不调用。传入失效 Callable 即安装「永久拒绝门」（安全方向）。
## 默认恒真门 = 纯内存模式；本票零写盘、不触碰 user://。
func set_persistence_gate(gate: Callable) -> Dictionary:
	_gate = gate
	_gate_set = true
	_append_log("set_persistence_gate", "", "", true, {})
	return {"ok": true, "code": ""}


## 捕获落账（INTERFACES §5 catch 侧）：校验 catch 事件未处理、species 合法、UTC 时间合法、
## 容量足够 → 生成唯一鱼实例（instance_id="fish-"+catch_event_id，价格目录快照）→
## 经持久化门 → 一次性提交 basket/processed_catch_ids/revision。
## 返回 {ok, code, instance_id}；成功 code=""；同 ID 同参重试 → ok=true、
## code="ALREADY_APPLIED"、鱼不重复入篮（T-ECO-02）。
func commit_catch(state: GameState, catch_event_id: Variant, species_id: Variant, caught_at_utc: Variant) -> Dictionary:
	var reject := _precheck(state, catch_event_id)
	if not reject.is_empty():
		return _commit_result(catch_event_id, reject)
	if not (species_id is String) or not _catalog_by_id.has(String(species_id)):
		return _commit_result(catch_event_id, ERROR_UNKNOWN_SPECIES)
	if not FishInstance.timestamp_valid(caught_at_utc):
		return _commit_result(catch_event_id, ERROR_BAD_TIMESTAMP)
	var catch_id := String(catch_event_id)
	var fingerprint := _catch_fingerprint(String(species_id), String(caught_at_utc))
	# 幂等/冲突先于容量检查：已提交的事务不因后续篮况变化而改变结果（T-ECO-02）。
	if _catch_ledger.has(catch_id) or state.processed_catch_ids.has(catch_id):
		if not _catch_ledger.has(catch_id):
			# state 声称已处理但指纹账本无据可查 → 无法证明同参，fail-closed 按冲突处理。
			return _commit_result(catch_id, ERROR_CONFLICT_CATCH_PARAMS)
		if _catch_fingerprint_equal(_catch_ledger[catch_id], fingerprint):
			return _commit_result(catch_id, ERROR_ALREADY_APPLIED, true, FishInstance.ID_PREFIX + catch_id)
		return _commit_result(catch_id, ERROR_CONFLICT_CATCH_PARAMS)
	if state.basket.size() >= int(state.basket_capacity):
		return _commit_result(catch_id, ERROR_BASKET_FULL)
	var fish := FishInstance.make(catch_id, _catalog_by_id[String(species_id)], String(caught_at_utc))
	if not FishInstance.validate(fish):
		return _commit_result(catch_id, ERROR_BAD_STATE)  # 防御性 fail-closed：make 产出恒合法
	var next_state := _state_snapshot(state)
	next_state["basket"].append(fish.duplicate(true))
	next_state["processed_catch_ids"].append(catch_id)
	next_state["revision"] = int(next_state["revision"]) + 1
	var ledger := snapshot_ledger()
	ledger["processed_catches"][catch_id] = fingerprint.duplicate(true)
	if not _persist({"next_state": next_state, "ledger": ledger}):
		return _commit_result(catch_id, ERROR_PERSIST_FAILED)
	# —— 门成功：一次性发布到唯一权威状态（INTERFACES §6 success 分支）——
	state.basket.append(fish)
	state.processed_catch_ids.append(catch_id)
	state.revision += 1
	_catch_ledger[catch_id] = fingerprint.duplicate(true)
	return _commit_result(catch_id, "", true, String(fish["instance_id"]))


## 售鱼落账（INTERFACES §5 sell 侧）：清单去重计价（重复 ID 只计一次）；指纹为去重升序
## 清单 ⇒ 实例顺序不影响同一 sale_event_id 的参数指纹（review 条件 2）；校验实例存在、
## 价格快照合法、金币加法不溢出 → 经持久化门 → 原子删鱼+加币+记 sale ID（T-ECO-03）。
## 返回 {ok, code, gold_added}；成功 code=""、gold_added=Σ sale_price_at_catch；
## 同 ID 同参重试 → ok=true、code="ALREADY_APPLIED"、gold_added=0，绝不重复加币。
func sell_fish(state: GameState, sale_event_id: Variant, instance_ids: Variant) -> Dictionary:
	var reject := _precheck(state, sale_event_id)
	if not reject.is_empty():
		return _sell_result(sale_event_id, reject)
	if not (instance_ids is Array):
		return _sell_result(sale_event_id, ERROR_BAD_INSTANCE_LIST)
	var raw_ids: Array = instance_ids
	if raw_ids.is_empty():
		return _sell_result(sale_event_id, ERROR_BAD_INSTANCE_LIST)
	var dedup_ids: Array = []
	for element in raw_ids:
		if not (element is String) or String(element).is_empty():
			return _sell_result(sale_event_id, ERROR_BAD_INSTANCE_LIST)
		if not dedup_ids.has(element):
			dedup_ids.append(element)
	var sale_id := String(sale_event_id)
	var fingerprint: Array = dedup_ids.duplicate(true)
	fingerprint.sort()  # 顺序不敏感指纹
	if _sale_ledger.has(sale_id) or state.processed_sale_ids.has(sale_id):
		if not _sale_ledger.has(sale_id):
			return _sell_result(sale_id, ERROR_CONFLICT_SALE_PARAMS)
		if _sale_fingerprint_equal(_sale_ledger[sale_id], fingerprint):
			return _sell_result(sale_id, ERROR_ALREADY_APPLIED, true)
		return _sell_result(sale_id, ERROR_CONFLICT_SALE_PARAMS)
	var gold_added := 0
	for instance_id in dedup_ids:
		var fish := _find_fish(state.basket, String(instance_id))
		if fish.is_empty():
			return _sell_result(sale_id, ERROR_UNKNOWN_INSTANCE)
		var price := int(fish["sale_price_at_catch"])  # 状态校验已保证非负整数值
		if price > INT64_MAX - gold_added:
			return _sell_result(sale_id, ERROR_GOLD_OVERFLOW)
		gold_added += price
	if int(state.wallet_gold) > INT64_MAX - gold_added:
		return _sell_result(sale_id, ERROR_GOLD_OVERFLOW)
	var next_state := _state_snapshot(state)
	next_state["wallet_gold"] = int(state.wallet_gold) + gold_added
	next_state["basket"] = _filter_basket(next_state["basket"], dedup_ids)
	next_state["processed_sale_ids"].append(sale_id)
	next_state["revision"] = int(next_state["revision"]) + 1
	var ledger := snapshot_ledger()
	ledger["processed_sales"][sale_id] = fingerprint.duplicate(true)
	if not _persist({"next_state": next_state, "ledger": ledger}):
		return _sell_result(sale_id, ERROR_PERSIST_FAILED)
	# —— 门成功：原子删鱼 + 加币 + 记已处理 sale ID，恢复鱼篓容量（INTERFACES §5/§6）——
	state.basket = _filter_basket(state.basket, dedup_ids)
	state.wallet_gold += gold_added
	state.processed_sale_ids.append(sale_id)
	state.revision += 1
	_sale_ledger[sale_id] = fingerprint.duplicate(true)
	return _sell_result(sale_id, "", true, "", gold_added)


## 指纹账本深拷贝：{"processed_catches": {catch_id: {species_id, caught_at_utc}},
## "processed_sales": {sale_id: 去重升序 instance_id 清单}}。供测试断言与 SAVE-001 持久化/
## 跨崩溃重建（review 条件 5：不能只恢复 ID 列表而丢失异参冲突检测）。
func snapshot_ledger() -> Dictionary:
	return {
		"processed_catches": _catch_ledger.duplicate(true),
		"processed_sales": _sale_ledger.duplicate(true),
	}


## SAVE-001 从已提交存档恢复账本。fail-closed 校验：恰 2 键、两侧为字典、逐指纹形状合法、
## 键集合与 state.processed_*_ids 完全一致（尺寸相等+子集 ⇒ 集合相等）、已出售实例不得仍在篮中。
## 任一非法 → ok=false + BAD_LEDGER，内部账本零改动；成功后一次性替换并规范化 sale 指纹。
func restore_ledger(state: GameState, ledger: Variant) -> Dictionary:
	if not _initialized:
		_append_log("restore_ledger", "", ERROR_NOT_INITIALIZED, false, {})
		return {"ok": false, "code": ERROR_NOT_INITIALIZED}
	if state == null:
		_append_log("restore_ledger", "", ERROR_NULL_GAME_STATE, false, {})
		return {"ok": false, "code": ERROR_NULL_GAME_STATE}
	var state_code := _validate_state(state)
	if not state_code.is_empty():
		_append_log("restore_ledger", "", state_code, false, {})
		return {"ok": false, "code": state_code}
	var ledger_code := _ledger_reject_code(state, ledger)
	if not ledger_code.is_empty():
		_append_log("restore_ledger", "", ledger_code, false, {})
		return {"ok": false, "code": ledger_code}
	# 全部校验通过才一次性替换内部账本（失败路径已在上方零副作用返回）。
	var ledger_dict: Dictionary = ledger
	_catch_ledger = (ledger_dict["processed_catches"] as Dictionary).duplicate(true)
	_sale_ledger = {}
	var sales: Dictionary = ledger_dict["processed_sales"]
	for sale_id in sales:
		var fingerprint: Array = (sales[sale_id] as Array).duplicate(true)
		fingerprint.sort()
		_sale_ledger[sale_id] = fingerprint
	_append_log("restore_ledger", "", "", true, {})
	return {"ok": true, "code": ""}


## 内存事务日志深拷贝（LOG-001 后续复用；本票不写日志文件）。
func get_transaction_log() -> Array:
	return transaction_log.duplicate(true)


# ---- 内部实现 ----

## 命令前置校验（commit_catch/sell_fish 共用）：稳定错误码或 ""。
func _precheck(state: GameState, event_id: Variant) -> String:
	if not _initialized:
		return ERROR_NOT_INITIALIZED
	if state == null:
		return ERROR_NULL_GAME_STATE
	var state_code := _validate_state(state)
	if not state_code.is_empty():
		return state_code
	if not (event_id is String) or String(event_id).is_empty():
		return ERROR_BAD_EVENT_ID
	return ""


## GameState 权威状态契约校验（INTERFACES §3 + game-save schema $comment 语义检查）。
## 返回 ""（合法）| BAD_STATE | BAD_PRICE（篮内价格非非负整数值，plan §4 稳定码区分）。
func _validate_state(state: GameState) -> String:
	if int(state.save_version) < 1 or int(state.revision) < 0 \
			or int(state.wallet_gold) < 0 or int(state.basket_capacity) < 1:
		return ERROR_BAD_STATE
	var basket: Variant = state.basket
	if not (basket is Array) or (basket as Array).size() > int(state.basket_capacity):
		return ERROR_BAD_STATE  # basket.size() <= basket_capacity 恒成立
	var seen_ids: Dictionary = {}
	var seen_sources: Dictionary = {}
	for element in (basket as Array):
		if not (element is Dictionary):
			return ERROR_BAD_STATE
		if FishInstance.price_invalid(element):
			return ERROR_BAD_PRICE  # 五键齐全但价格坏：稳定归 BAD_PRICE（T-ECO-04）
		if not FishInstance.validate(element):
			return ERROR_BAD_STATE
		var entry: Dictionary = element
		var instance_id := String(entry["instance_id"])
		var source_id := String(entry["source_event_id"])
		if seen_ids.has(instance_id) or seen_sources.has(source_id):
			return ERROR_BAD_STATE  # 篮内 instance/source ID 唯一（schema $comment）
		seen_ids[instance_id] = true
		seen_sources[source_id] = true
	for processed_ids in [state.processed_catch_ids, state.processed_sale_ids]:
		var seen_ids_here: Dictionary = {}
		for element in (processed_ids as Array):
			if not (element is String) or String(element).is_empty() or seen_ids_here.has(element):
				return ERROR_BAD_STATE  # processed ids：非空字符串且唯一（uniqueItems）
			seen_ids_here[element] = true
	return ""


func _state_snapshot(state: GameState) -> Dictionary:
	return {
		"save_version": state.save_version,
		"revision": state.revision,
		"wallet_gold": state.wallet_gold,
		"basket_capacity": state.basket_capacity,
		"basket": state.basket.duplicate(true),
		"processed_catch_ids": state.processed_catch_ids.duplicate(true),
		"processed_sale_ids": state.processed_sale_ids.duplicate(true),
		"fishing_checkpoint": state.fishing_checkpoint.duplicate(true),
		"desktop_window": state.desktop_window.duplicate(true),
	}


func _find_fish(basket: Array, instance_id: String) -> Dictionary:
	for element in basket:
		if element is Dictionary and String((element as Dictionary).get("instance_id", "")) == instance_id:
			return element
	return {}


func _filter_basket(basket: Array, sold_ids: Array) -> Array:
	var kept: Array = []
	for element in basket:
		if element is Dictionary and sold_ids.has(String((element as Dictionary).get("instance_id", ""))):
			continue
		kept.append(element)
	return kept


func _catch_fingerprint(species_id: String, caught_at_utc: String) -> Dictionary:
	return {"species_id": species_id, "caught_at_utc": caught_at_utc}


func _catch_fingerprint_equal(stored: Variant, incoming: Dictionary) -> bool:
	if not (stored is Dictionary):
		return false
	var stored_dict: Dictionary = stored
	if stored_dict.size() != 2:
		return false
	return stored_dict.get("species_id") == incoming["species_id"] \
			and stored_dict.get("caught_at_utc") == incoming["caught_at_utc"]


func _sale_fingerprint_equal(stored: Variant, incoming: Array) -> bool:
	if not (stored is Array):
		return false
	var stored_list: Array = stored
	if stored_list.size() != incoming.size():
		return false
	for index in incoming.size():
		if stored_list[index] != incoming[index]:
			return false
	return true


## ledger 账本 fail-closed 校验（restore_ledger）：返回 "" 或 BAD_LEDGER。
func _ledger_reject_code(state: GameState, ledger: Variant) -> String:
	if not (ledger is Dictionary):
		return ERROR_BAD_LEDGER
	var ledger_dict: Dictionary = ledger
	if ledger_dict.size() != 2 or not ledger_dict.has("processed_catches") \
			or not ledger_dict.has("processed_sales"):
		return ERROR_BAD_LEDGER
	var catches: Variant = ledger_dict["processed_catches"]
	var sales: Variant = ledger_dict["processed_sales"]
	if not (catches is Dictionary) or not (sales is Dictionary):
		return ERROR_BAD_LEDGER
	var catch_dict: Dictionary = catches
	var sale_dict: Dictionary = sales
	if catch_dict.size() != (state.processed_catch_ids as Array).size() \
			or sale_dict.size() != (state.processed_sale_ids as Array).size():
		return ERROR_BAD_LEDGER  # 与权威 processed ids 尺寸不符 → 必不一致
	for catch_id in catch_dict:
		if not (catch_id is String) or String(catch_id).is_empty() \
				or not (state.processed_catch_ids as Array).has(catch_id):
			return ERROR_BAD_LEDGER
		var catch_entry: Variant = catch_dict[catch_id]
		if not (catch_entry is Dictionary):
			return ERROR_BAD_LEDGER
		var entry: Dictionary = catch_entry
		if entry.size() != 2 or not (entry.get("species_id") is String) \
				or String(entry.get("species_id")).is_empty() \
				or not FishInstance.timestamp_valid(entry.get("caught_at_utc")):
			return ERROR_BAD_LEDGER
	for sale_id in sale_dict:
		if not (sale_id is String) or String(sale_id).is_empty() \
				or not (state.processed_sale_ids as Array).has(sale_id):
			return ERROR_BAD_LEDGER
		var sale_entry: Variant = sale_dict[sale_id]
		if not (sale_entry is Array) or (sale_entry as Array).is_empty():
			return ERROR_BAD_LEDGER
		var seen: Dictionary = {}
		for instance_id in (sale_entry as Array):
			if not (instance_id is String) or String(instance_id).is_empty() or seen.has(instance_id):
				return ERROR_BAD_LEDGER
			seen[instance_id] = true
			if not _find_fish(state.basket, String(instance_id)).is_empty():
				return ERROR_BAD_LEDGER  # 账本称已出售但实例仍在篮中：权威状态不一致
	return ""


## 持久化门调用（INTERFACES §6）：默认恒真门；门失效/报错/非 bool/非 true 一律拒绝。
## 门只收到 next_state 与 ledger 的深拷贝；门返回布尔 true 是唯一放行条件。
func _persist(payload: Dictionary) -> bool:
	if not _gate_set:
		return true  # 默认恒真门（内存模式，本票）
	if not _gate.is_valid():
		return false  # 失效/报错 Callable：不调用，直接 fail-closed
	var result: Variant = _gate.call(payload)
	if not (result is bool):
		return false  # 非 bool 返回：拒绝（Godot4 中 int==true 是非法比较，须先判类型）
	return bool(result)  # 仅布尔 true 放行


func _init_reject(code: String) -> Dictionary:
	# 初始化失败零副作用：不提交目录/不置位，后续命令恒 NOT_INITIALIZED。
	_append_log("initialize", "", code, false, {})
	return {"ok": false, "error_code": code}


func _commit_result(catch_event_id: Variant, code: String, ok_flag := false,
		instance_id := "") -> Dictionary:
	# str() 而非 String()：拒绝路径的 catch_event_id 可能为任意 Variant（如 int），
	# Godot 4 无 String(int) 构造，直接 String(42) 会触发引擎 call error。
	_append_log("commit_catch", str(catch_event_id), code, ok_flag, {"instance_id": instance_id})
	return {"ok": ok_flag, "code": code, "instance_id": instance_id}


func _sell_result(sale_event_id: Variant, code: String, ok_flag := false,
		_instance_id := "", gold_added := 0) -> Dictionary:
	_append_log("sell_fish", str(sale_event_id), code, ok_flag, {"gold_added": gold_added})
	return {"ok": ok_flag, "code": code, "gold_added": gold_added}


func _append_log(action: String, event_id: String, code: String, ok_flag: bool, extra: Dictionary) -> void:
	var entry := {"seq": _log_seq, "action": action, "event_id": event_id, "code": code, "ok": ok_flag}
	var keys := extra.keys()
	keys.sort()
	for key in keys:
		entry[key] = extra[key]
	_log_seq += 1
	transaction_log.append(entry)
