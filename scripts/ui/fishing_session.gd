class_name FishingSession
extends RefCounted
# UI-001：纯可测运行会话（plan §2/§4/§5.2、review #3/#4/#5）。由 GameController 驱动，向 UI
# 只读发布 status_view()；金币/鱼篓/事务 ID 唯一权威仍是 GameState（ARCHITECTURE §2），本类不
# 另立账本，也不直接改 EconomyService/AtomicSaveService/FishingStateMachine 的已验收语义。
# 不变量：
# - 纯 RefCounted：无 Node/_process、无窗口/DisplayServer 副作用；Engine.max_fps 绝不在本类
#   读写——帧率策略经 fps_target() 计算，由 DesktopWindow/GameController 在运行时落到
#   Engine.max_fps（U-6 要求读取与设置分离）。
# - 启动顺序（plan §2）：先 FishSpeciesCatalog/RuntimeConfig 校验 → 构造 valid_species_by_id →
#   AtomicSaveService.load_save(valid_species_by_id, fresh_seed)；仅当 NO_VALID_SAVE 且
#   main_status 与 backup_status 均 "missing" 才允许新档；损坏/未来版本/配置错误 fail closed，
#   存档原件零改动，绝不静默重置。
# - 经济可见性：金币/鱼变化只在 EconomyService 持久化门（AtomicSaveService._gate）返回
#   true 之后出现在 GameState；PERSIST_FAILED/非 bool 门一律不显示成功（V01-S02/T-UI-01）。
# - checkpoint 契约（SAVE-001 §4.5）：启动/抛竿后、每次 FSM 转换、隐藏/暂停前与恢复后、候选
#   产生/清除后立即 persist_runtime_checkpoint()；WAITING 中最多每 5 有效秒一次，不逐帧写盘。
# - UTC 单次取样：结算时仅一次 Time.get_datetime_string_from_system(true)，校验 19 字符形状
#   后补 Z；失败重试与重启恢复复用 caught_at_utc，绝不二次抽样（SAVE-001 review #7）。
# - 售鱼 ID = Crypto 16 字节随机 nonce 的 hex + 单调计数器，不含设备/用户标识；一个意图只
#   分配一次，PERSIST_FAILED 重试复用同 ID；已成功意图的相同清单在意图层去重为
#   ALREADY_APPLIED（连击不双币，R-U8）。
# - 测试 seam（仅测试使用，生产路径不依赖）：start options 支持 save_dir / catalog_path /
#   runtime_path / rng_seed / manual_settlement；save_fault()、commit_pending_catch() 与只读
#   服务访问器。IO 一律经 AtomicSaveService.configure_dir 显式注入临时目录，绝不触碰真实
#   user://（测试内）。
# - LOG-001 日志接入（仅追加）：start options 新增可选 log_dir（缺省 "user://logs/"，无禁用
#   开关）。EventLog 在配置校验前装配，使 config_invalid / save_load_failed /
#   save_checkpoint_failed 与 catch/sale 成败均可留痕；所有记录点忽略 EventLog 返回值，日志
#   任何故障都不改变 _save_error/_input_open/持久化门/FSM/经济语义，也不改 status_view() 键集
#   （HUD 零改动复用「存档失败」横幅）。永不记录 reason/path/金币数额/鱼种价格/按键/屏幕信息
#   （EventLog 字段白名单从结构上排除）。

const CODE_NOT_READY := "NOT_READY"
const CODE_SAVE_ERROR := "SAVE_ERROR"
const CODE_HIDDEN := "HIDDEN"
const CODE_SALE_IN_FLIGHT := "SALE_IN_FLIGHT"
const CODE_BAD_PAYLOAD := "BAD_PAYLOAD"
const CODE_BAD_INSTANCE_LIST := "BAD_INSTANCE_LIST"
const CODE_NO_PENDING := "NO_PENDING"
const CODE_FRESH_CHECKPOINT_FAILED := "FRESH_CHECKPOINT_FAILED"
const CODE_PENDING_REPLAY_FAILED := "PENDING_REPLAY_FAILED"
const CODE_ALREADY_APPLIED := "ALREADY_APPLIED"
const CODE_PERSIST_FAILED := "PERSIST_FAILED"

const WAITING_CHECKPOINT_INTERVAL_SEC := 5.0  # plan §4.5：WAITING 中 ≤1 次/5 有效秒
const FPS_VISIBLE := 30                        # SDD-175 可见 30 FPS
const FPS_DRAG := 60                           # DECISION 2026-11-11：仅拖动会话 60
const SALE_ID_PREFIX := "sale-"
const RNG_STATE_MAX := 2147483646              # 2^31 - 2 = DeterministicRng.MODULUS - 1

var _booted := false
var _input_open := false
var _save_error := false
var _hidden := false
var _drag_session := false
var _boot_code := ""
var _boot_reason := ""
var _manual_settlement := false

var _state: GameState = null
var _economy: EconomyService = null
var _fsm: FishingStateMachine = null
var _rng: DeterministicRng = null
var _clock: VirtualClock = null
var _save: AtomicSaveService = null
var _catalog: Dictionary = {}
var _runtime: Dictionary = {}
var _species_by_id: Dictionary = {}

# 待结算内存态：{} 或 {catch_event_id, species_id, caught_at_utc, candidate, staged}
var _settlement: Dictionary = {}
# 售鱼意图：{} 或 {sale_id, instance_ids(升序去重), phase: in_flight|done|failed}
var _active_sale: Dictionary = {}
var _sale_counter := 0
var _last_wait_checkpoint_clock := 0.0
# LOG-001 日志装配（仅追加；记录点只读事务结果，绝不回写业务状态）。
var _log: EventLog = null
var _log_config_code := ""  # ""=日志配置成功；否则为 EventLog 稳定失败码（仅经 log_health() 暴露）
var _settlement_start_ms := -1  # 结算起点（Time.get_ticks_msec），供 catch 事件 elapsed_ms


## 装配启动（plan §2）。options（测试 seam）：save_dir / catalog_path / runtime_path /
## rng_seed(int，缺省用 Crypto 随机 nonce 派生) / manual_settlement(bool：tick 到达
## SETTLEMENT 只暂存候选不自动结算，供 U-1R 崩溃恢复矩阵）。
func start(options: Dictionary = {}) -> Dictionary:
	_boot_code = ""
	_boot_reason = ""
	var catalog_path := String(options.get("catalog_path", "res://data/fish_species.json"))
	var runtime_path := String(options.get("runtime_path", "res://data/runtime_config.json"))
	var save_dir := String(options.get("save_dir", "user://"))
	_manual_settlement = bool(options.get("manual_settlement", false))
	var seed_option: Variant = options.get("rng_seed", null)
	if seed_option != null and not (seed_option is int):
		return _boot_fail(CODE_BAD_PAYLOAD, "rng_seed must be an int when supplied")

	# LOG-001：日志门在配置门之前装配，使配置失败也可留痕。装配/配置失败只改变
	# log_health() 的 code，boot 结果与 _input_open 完全不受影响（L-8）。
	var log_dir := String(options.get("log_dir", "user://logs/"))
	_log = EventLog.new()
	var log_config := _log.configure_dir(log_dir)
	_log_config_code = "" if log_config.get("ok") == true else String(log_config.get("code", "NOT_CONFIGURED"))

	# 1) 配置门先过（T-CONF-01）：任一非法 → fail closed，零文件动作。
	_catalog = FishSpeciesCatalog.load_catalog(catalog_path)
	_runtime = RuntimeConfig.load_config(runtime_path)
	if _catalog.get("ok") != true or _runtime.get("ok") != true:
		var reasons := ConfigGate.blocked_reasons(_catalog, _runtime)
		_log_event({"severity": EventLog.SEVERITY_ERROR, "event": EventLog.EVENT_CONFIG_INVALID,
				"result": EventLog.RESULT_ERROR, "error_code": "CONFIG_INVALID"})  # 不记录 reason 文本
		return _boot_fail("CONFIG_INVALID:" + ";".join(reasons), "config validation failed; no writes")

	# 2) valid_species_by_id（id -> 目录条目深拷贝，SaveValidate.catalog_valid 合同形状）。
	_species_by_id = {}
	for element in (_catalog["species"] as Array):
		var entry: Dictionary = (element as Dictionary).duplicate(true)
		_species_by_id[String(entry["id"])] = entry

	# 3) 服务实例与存档目录（测试显式临时目录；生产默认 user://）。
	_rng = DeterministicRng.new()
	_clock = VirtualClock.new()
	_economy = EconomyService.new()
	_fsm = FishingStateMachine.new()
	_save = AtomicSaveService.new()
	var dir_result := _save.configure_dir(save_dir)
	if dir_result.get("ok") != true:
		_log_event({"severity": EventLog.SEVERITY_ERROR, "event": EventLog.EVENT_SAVE_CHECKPOINT_FAILED,
				"result": EventLog.RESULT_ERROR, "error_code": CODE_PERSIST_FAILED})
		return _boot_fail(String(dir_result.get("code", "DIR_FAILED")), String(dir_result.get("reason", "")))

	# 4) fresh_seed：Crypto 随机 nonce 派生的非身份随机值；不读取设备 ID。
	var fresh_seed := int(seed_option) if seed_option != null else _random_fresh_seed()
	var loaded := _save.load_save(_species_by_id, fresh_seed)
	if loaded.get("ok") == true:
		return _boot_existing(loaded)

	# 5) 仅「主+备皆 missing」才是合法新档；其余（MAIN_CORRUPT / VERSION_NEWER /
	#    NO_VALID_SAVE 的坏档组合…）fail closed，原档保留（load_save 本身零写入）。
	var report: Dictionary = loaded.get("report", {})
	var load_code := String(loaded.get("code", ""))
	if load_code == "NO_VALID_SAVE" and String(report.get("main_status", "")) == "missing" \
			and String(report.get("backup_status", "")) == "missing":
		return _boot_fresh(fresh_seed)
	# 不可用/损坏存档（非「主备皆缺的合法新档」）→ save_load_failed；稳定码来自 loader，
	# 不记录 reason/path。合法新档双缺失在上一分支返回，不记失败。
	_log_event({"severity": EventLog.SEVERITY_ERROR, "event": EventLog.EVENT_SAVE_LOAD_FAILED,
			"result": EventLog.RESULT_ERROR,
			"error_code": load_code if not load_code.is_empty() else "SAVE_LOAD_FAILED"})
	return _boot_fail(load_code, String(report.get("reason", "no usable save; originals retained")))


## 只读 UI 状态视图（深拷贝，不含任何未提交经济值——GameState 仅在门 true 后发布）。
func status_view() -> Dictionary:
	var basket_view: Array = []
	var gold := 0
	var capacity := 10
	var geometry := {"x": 80, "y": 80, "width": 220, "height": 160, "display_hint": null}
	if _state != null:
		basket_view = (_state.basket as Array).duplicate(true)
		gold = int(_state.wallet_gold)
		capacity = int(_state.basket_capacity)
		geometry = (_state.desktop_window as Dictionary).duplicate(true)
	var state_name := "OFFLINE"
	var checkpoint := {"state": "IDLE", "event_id": null, "wait_seconds": null, "elapsed_effective_seconds": 0.0}
	if _fsm != null:
		state_name = FishingStateMachine.state_name(_fsm.get_state())
		checkpoint = _fsm.snapshot_checkpoint()
	return {
		"booted": _booted, "input_open": _input_open, "save_error": _save_error,
		"hidden": _hidden, "drag_session": _drag_session, "fps_target": fps_target(),
		"gold": gold, "basket": basket_view, "basket_count": basket_view.size(),
		"basket_capacity": capacity, "basket_full": basket_view.size() >= capacity,
		"state": state_name, "checkpoint": checkpoint, "desktop_window": geometry,
		"boot_code": _boot_code, "boot_reason": _boot_reason,
		"settlement_pending": not _settlement.is_empty(),
		"active_sale_id": String(_active_sale.get("sale_id", "")),
		"revision": int(_state.revision) if _state != null else 0,
	}


## 有效时间推进（由 GameController 用 Time.get_ticks_msec() 差值换算成秒后调用；本类内部
## 绝不用帧计数）。隐藏/存档故障/输入未开放时零推进、零 RNG 消耗（T-TIME-03/OPEN-001）。
func tick(seconds: float) -> Array:
	if _fsm == null or not _input_open or _save_error or _hidden:
		return []
	var events: Array = _fsm.tick_effective(seconds)
	if not events.is_empty():
		_persist_checked()  # 契约：每次 FSM 状态转换后立即 checkpoint
	if _fsm.get_state() == FishingStateMachine.State.SETTLEMENT and _settlement.is_empty():
		_begin_settlement()
	if _fsm.get_state() == FishingStateMachine.State.WAITING \
			and _clock.now() - _last_wait_checkpoint_clock >= WAITING_CHECKPOINT_INTERVAL_SEC:
		_last_wait_checkpoint_clock = _clock.now()
		_persist_checked()  # WAITING 有界写盘（≤1 次/5 有效秒，R-U9）
	return events


## 抛竿：存档故障/隐藏/未就绪时以稳定码拒绝；成功后立即 checkpoint（契约）。
func request_cast() -> Dictionary:
	var denied := _deny_if_closed()
	if not denied.is_empty():
		return denied
	var result := _fsm.request_cast(_state)
	if result.get("ok") == true:
		_last_wait_checkpoint_clock = _clock.now()
		var persisted := _persist_checked()
		result["checkpoint_committed"] = persisted.get("ok") == true
	return result


## 结算重试（横幅重试入口/测试）：把内存中未完成的结算推进到完成；仅当全部落账才清错误态。
func settle_retry() -> Dictionary:
	if _settlement.is_empty():
		return {"ok": true, "code": CODE_NO_PENDING}
	return _finish_settlement()


## 「出售所选」：一次用户意图一个 sale ID。相同清单在意图层去重（连击=ALREADY_APPLIED）；
## PERSIST_FAILED 后同 ID 重试；已确定失败（非持久化类）的旧意图允许另开新意图。
func sell_selected(instance_ids: Variant) -> Dictionary:
	var denied := _deny_if_closed()
	if not denied.is_empty():
		return denied
	if not (instance_ids is Array):
		return _sell_denied(CODE_BAD_INSTANCE_LIST)
	var ids: Array = []
	for element in (instance_ids as Array):
		if not (element is String) or String(element).is_empty():
			return _sell_denied(CODE_BAD_INSTANCE_LIST)
		if not ids.has(element):
			ids.append(element)
	if ids.is_empty():
		return _sell_denied(CODE_BAD_INSTANCE_LIST)
	var sorted_ids: Array = ids.duplicate(true)
	sorted_ids.sort()

	if not _active_sale.is_empty():
		var same_intent := _sale_ids_equal(_active_sale, sorted_ids)
		if same_intent and String(_active_sale["phase"]) == "done":
			return {"ok": true, "code": CODE_ALREADY_APPLIED, "gold_added": 0,
					"sale_id": String(_active_sale["sale_id"]), "dedup": "intent"}
		if not same_intent and String(_active_sale["phase"]) == "in_flight":
			return _sell_denied(CODE_SALE_IN_FLIGHT)  # 串行单命令：先完成/重试当前意图
		if not same_intent:
			_active_sale = {}  # 旧意图已终结（failed/done 后换清单），开新意图
	if _active_sale.is_empty():
		_sale_counter += 1
		_active_sale = {"sale_id": _next_sale_id(), "instance_ids": sorted_ids, "phase": "in_flight"}
	var sale_id := String(_active_sale["sale_id"])
	var result := _economy.sell_fish(_state, sale_id, ids)
	_log_sale_result(result, sale_id)  # LOG-001：售鱼事务结果（成功不记金额；失败记稳定码）
	var code := String(result.get("code", ""))
	if result.get("ok") == true:
		_active_sale["phase"] = "done"
	elif code == CODE_PERSIST_FAILED:
		_save_error = true  # 保留 in_flight：重试复用同 ID，金币/鱼绝不显示成功
	else:
		_active_sale["phase"] = "failed"
	result["sale_id"] = sale_id
	return result


## 「出售全部」：清空鱼篓 = 一次意图（一个 sale ID 覆盖全部实例）。
func sell_all() -> Dictionary:
	if _state == null:
		return _sell_denied(CODE_NOT_READY)
	var ids: Array = []
	for element in (_state.basket as Array):
		ids.append(String((element as Dictionary)["instance_id"]))
	return sell_selected(ids)


## 隐藏：pause("hidden") + 立即 checkpoint（落盘为暂停前活动态，schema 4 键）；此后 tick
## 零推进零 RNG。IDLE 无计时可暂停 → pause 记 BAD_TRANSITION 属正常，仍按契约写 checkpoint。
func hide() -> Dictionary:
	if _hidden:
		return {"ok": true, "code": "ALREADY_HIDDEN"}
	_hidden = true
	var paused_from := ""
	if _fsm != null:
		var paused := _fsm.pause("hidden")
		paused_from = String(paused.get("paused_from", ""))
	if _save != null:
		_persist_checked()
	return {"ok": true, "code": "", "paused_from": paused_from}


## 显示：resume_if_safe（仅 PAUSED 有效）+ 立即 checkpoint + 恢复处理。
func show() -> Dictionary:
	if not _hidden:
		return {"ok": true, "code": "ALREADY_SHOWN"}
	_hidden = false
	var resumed_from := ""
	if _fsm != null:
		var resumed := _fsm.resume_if_safe()
		resumed_from = String(resumed.get("resumed_from", ""))
	if _save != null:
		_persist_checked()
	return {"ok": true, "code": "", "resumed_from": resumed_from}


# ---- 帧率策略（读取与设置分离：本类只计算，Engine.max_fps 由窗口层落）----

func notify_drag_start() -> void:
	_drag_session = true


func notify_drag_end() -> void:
	_drag_session = false


## SPIKE B 兜底：原生拖动可能吞 release；轮询左键 mask，松开即结束拖动会话 → 回 30 FPS。
## 返回 true 表示本次轮询结束了一个拖动会话。
func drag_release_poll() -> bool:
	if _drag_session and Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT == 0:
		_drag_session = false
		return true
	return false


func fps_target() -> int:
	return FPS_DRAG if _drag_session else FPS_VISIBLE


# ---- 窗口几何（GameState.desktop_window 是权威；经持久化门后才算已确认）----

func update_window_geometry(x: Variant, y: Variant, width: Variant, height: Variant, display_hint: Variant = null) -> Dictionary:
	if _save == null or _state == null:
		return {"ok": false, "code": CODE_NOT_READY}
	if not (x is int) or not (y is int) or not (width is int) or not (height is int) \
			or int(x) < 0 or int(y) < 0 or int(width) < 1 or int(height) < 1 \
			or not (display_hint == null or (display_hint is int and int(display_hint) >= 0)):
		return {"ok": false, "code": CODE_BAD_PAYLOAD}
	_state.desktop_window = {"x": int(x), "y": int(y), "width": int(width), "height": int(height),
			"display_hint": display_hint}
	var persisted := _persist_checked()
	persisted["desktop_window"] = (_state.desktop_window as Dictionary).duplicate(true)
	return persisted


# ---- 测试 seam（仅测试；生产不依赖）----

## 存档故障注入直通（阶段名由 SaveFaults 校验：tmp_write/tmp_flush/backup/rename/
## quarantine/legacy_copy）。
func save_fault(stage: String, armed: bool) -> Dictionary:
	if _save == null:
		return {"ok": false, "code": CODE_NOT_READY}
	return _save.set_fault_injection(stage, armed)


## 手动模式测试 seam：仅 commit 当前候选（+checkpoint），保留候选与 SETTLEMENT 态，
## 模拟「事务已落账、ack 前崩溃」的磁盘形状（U-1R 场景 B）。
func commit_pending_catch() -> Dictionary:
	if _settlement.is_empty():
		return {"ok": false, "code": CODE_NO_PENDING}
	return _finish_settlement(true)


## 横幅/调度器重试入口：先推进未完成的结算与售鱼意图，再补一次 checkpoint；
## 仅当所有未完成意图清零才解除保存故障横幅。
func retry_persist() -> Dictionary:
	if _save == null:
		return {"ok": false, "code": CODE_NOT_READY}
	var last: Dictionary = {}
	if not _settlement.is_empty():
		last = _finish_settlement()
	if not _active_sale.is_empty() and String(_active_sale.get("phase", "")) == "in_flight":
		var sale_id := String(_active_sale["sale_id"])
		var ids: Array = (_active_sale["instance_ids"] as Array).duplicate(true)
		var result := _economy.sell_fish(_state, sale_id, ids)  # 同 ID 重试（幂等合同）
		_log_sale_result(result, sale_id)  # LOG-001：重试序列逐条留痕（含再次 PERSIST_FAILED）
		if result.get("ok") == true:
			_active_sale["phase"] = "done"
		elif String(result.get("code", "")) != CODE_PERSIST_FAILED:
			_active_sale["phase"] = "failed"
		last = result
	var persisted := _persist_checked()
	if persisted.get("ok") == true and _settlement.is_empty() \
			and (_active_sale.is_empty() or String(_active_sale["phase"]) != "in_flight"):
		_save_error = false
		_input_open = true  # 新档首 checkpoint 曾因故障未开放输入时，此处补开放
	return persisted


# ---- 只读访问器（测试断言专用；返回值不授权修改权威服务）----

func state() -> GameState:
	return _state


func economy() -> EconomyService:
	return _economy


func fsm() -> FishingStateMachine:
	return _fsm


func rng() -> DeterministicRng:
	return _rng


func clock() -> VirtualClock:
	return _clock


func save_service() -> AtomicSaveService:
	return _save


## LOG-001 只读日志健康度（L-8 断言用）：日志配置失败只反映在此码上，boot/input/经济不受影响。
func log_health() -> Dictionary:
	if _log == null:
		return {"ok": false, "code": "NOT_CONFIGURED", "lines_written": 0, "lines_dropped": 0,
				"io_errors": 0, "files_pruned": 0, "max_bytes": 0, "max_files": 0}
	var health: Dictionary = _log.health()
	if not _log_config_code.is_empty():
		health["ok"] = false
		health["code"] = _log_config_code
	return health


func species_name(species_id: String) -> String:
	var entry: Dictionary = _species_by_id.get(species_id, {})
	return String(entry.get("name_zh", species_id))


func species_names() -> Dictionary:
	var names: Dictionary = {}
	for species_id in _species_by_id:
		names[species_id] = String((_species_by_id[species_id] as Dictionary).get("name_zh", String(species_id)))
	return names


# ---- 内部：启动分支 ----

func _boot_fresh(fresh_seed: int) -> Dictionary:
	_state = GameState.new()
	var seeded := _rng.set_seed(fresh_seed)
	if seeded.get("ok") != true:
		return _boot_fail("rng:" + String(seeded.get("error_code", "BAD_SEED")), "fresh seed rejected")
	var eco_init := _economy.initialize(_catalog, _runtime)
	if eco_init.get("ok") != true:
		return _boot_fail("economy:" + String(eco_init.get("error_code", "UNVERIFIED")), "economy init rejected")
	var fsm_init := _fsm.initialize(_catalog, _runtime, _rng, _clock, {})
	if fsm_init.get("ok") != true:
		return _boot_fail("fsm:" + String(fsm_init.get("error_code", "UNVERIFIED")), "fsm init rejected")
	var installed := _save.install_into(_economy, _state, _rng, _clock, _fsm, _species_by_id)
	if installed.get("ok") != true:
		return _boot_fail("save:" + String(installed.get("code", "BAD_INJECTION")), "persistence gate install failed")
	var restored := _economy.restore_ledger(_state, {"processed_catches": {}, "processed_sales": {}})
	if restored.get("ok") != true:
		return _boot_fail("ledger:" + String(restored.get("code", "BAD_LEDGER")), "empty ledger restore failed")
	# 新档：首次 checkpoint 成功前不开放输入（review #3）。
	var first := _save.persist_runtime_checkpoint()
	if first.get("ok") != true:
		_save_error = true
		_log_event({"severity": EventLog.SEVERITY_ERROR, "event": EventLog.EVENT_SAVE_CHECKPOINT_FAILED,
				"result": EventLog.RESULT_ERROR, "error_code": CODE_PERSIST_FAILED,
				"event_id": null, "save_version": int(_state.save_version)})
		return _boot_fail(CODE_FRESH_CHECKPOINT_FAILED, "fresh checkpoint not durable; input stays closed")
	_booted = true
	_input_open = true
	_boot_code = ""
	return {"ok": true, "code": "", "input_open": true, "save_error": false, "fresh": true,
			"fresh_seed": fresh_seed, "report": _save.get_last_report()}


func _boot_existing(loaded: Dictionary) -> Dictionary:
	_state = loaded["state"]
	# SAVE-001 恢复顺序：先 RNG/Clock，再 Economy/FSM，install 门，再 restore_ledger（plan §2）。
	var rng_restored := _rng.restore_state(loaded["rng_snapshot"])
	if rng_restored.get("ok") != true:
		return _boot_fail("rng:" + String(rng_restored.get("error_code", "BAD_SNAPSHOT")), "rng snapshot invalid")
	var clock_restored := _clock.restore_state(loaded["clock_snapshot"])
	if clock_restored.get("ok") != true:
		return _boot_fail("clock:" + String(clock_restored.get("error_code", "BAD_SNAPSHOT")), "clock snapshot invalid")
	var eco_init := _economy.initialize(_catalog, _runtime)
	if eco_init.get("ok") != true:
		return _boot_fail("economy:" + String(eco_init.get("error_code", "UNVERIFIED")), "economy init rejected")
	var fsm_init := _fsm.initialize(_catalog, _runtime, _rng, _clock, _state.fishing_checkpoint)
	if fsm_init.get("ok") != true:
		return _boot_fail("fsm:" + String(fsm_init.get("error_code", "UNVERIFIED")), "fsm checkpoint restore rejected")
	var installed := _save.install_into(_economy, _state, _rng, _clock, _fsm, _species_by_id)
	if installed.get("ok") != true:
		return _boot_fail("save:" + String(installed.get("code", "BAD_INJECTION")), "persistence gate install failed")
	var restored := _economy.restore_ledger(_state, loaded["ledger"])
	if restored.get("ok") != true:
		return _boot_fail("ledger:" + String(restored.get("code", "BAD_LEDGER")), "ledger restore failed")
	var candidate: Variant = loaded["pending_candidate"]
	if candidate != null:
		var replay := _replay_pending_candidate(candidate as Dictionary)
		if replay.get("ok") != true:
			return _boot_fail(CODE_PENDING_REPLAY_FAILED + ":" + String(replay.get("code", "")),
					"pending candidate replay rejected; originals retained")
	_booted = true
	_input_open = true
	_boot_code = ""
	return {"ok": true, "code": String(loaded.get("code", "")), "input_open": true,
			"save_error": _save_error, "recovered": true, "report": _save.get_last_report()}


## 待结算候选重启恢复（plan §2、review #4）：校验候选与 SETTLEMENT checkpoint 一致 → 重建
## FSM 成功 payload → 安装门后、重放前 set_pending_candidate 恢复内存态 → commit_catch
## （仅 OK/ALREADY_APPLIED 放行）→ ack → 清候选 → checkpoint。不重抽样、不重加鱼。
func _replay_pending_candidate(candidate: Dictionary) -> Dictionary:
	var checkpoint := _fsm.snapshot_checkpoint()
	if String(checkpoint.get("state", "")) != "SETTLEMENT" \
			or checkpoint.get("event_id") != candidate.get("catch_event_id"):
		return {"ok": false, "code": "PENDING_CANDIDATE_MISMATCH",
				"reason": "loaded candidate does not match SETTLEMENT checkpoint"}
	var caught_at_utc := String(candidate.get("caught_at_utc", ""))
	var payload := {
		"ok": true,
		"code": "",
		"catch_event_id": candidate["catch_event_id"],
		"species_id": candidate["species_id"],
		"weight_snapshot": (candidate["weight_snapshot"] as Dictionary).duplicate(true),
		"caught_at_clock": candidate["caught_at_clock"],
	}
	var staged := _save.set_pending_candidate(payload, caught_at_utc)
	if staged.get("ok") != true:
		return staged
	var commit := _economy.commit_catch(_state, candidate["catch_event_id"],
			candidate["species_id"], caught_at_utc)
	_log_commit_result(commit, String(candidate["catch_event_id"]), null)  # 重启重放无结算起点 → null
	var ok: bool = commit.get("ok") == true \
			and (String(commit.get("code", "")) == "" or String(commit.get("code", "")) == CODE_ALREADY_APPLIED)
	if not ok:
		return commit
	_fsm.ack_settlement(String(candidate["catch_event_id"]), true)
	_save.clear_pending_candidate()
	return _persist_checked()


# ---- 内部：结算 ----

## SETTLEMENT 到达：候选产生 → UTC 仅一次 → set_pending_candidate → checkpoint（候选产生
## 后立即）→（非手动模式）立即结算落账。
func _begin_settlement() -> void:
	_settlement_start_ms = Time.get_ticks_msec()  # LOG-001：elapsed_ms 起点（结算开始）
	var candidate := _fsm.produce_catch_candidate()
	var utc := _sample_utc_once()
	if candidate.get("ok") != true or utc.is_empty():
		_save_error = true
		_settlement = {}
		return
	var staged := _save.set_pending_candidate(candidate, utc)
	_settlement = {
		"catch_event_id": String(candidate["catch_event_id"]),
		"species_id": String(candidate["species_id"]),
		"caught_at_utc": utc,
		"candidate": candidate,
		"staged": staged.get("ok") == true,
	}
	_persist_checked()
	if not _manual_settlement:
		_finish_settlement()


## 结算落账：set_pending → commit_catch → ack → clear → checkpoint。PERSIST_FAILED 保留
## 全部内存态等待重试（同 UTC/同 ID ⇒ 幂等），并进入横幅故障态；成功才清 settlement。
## keep_pending=true（测试 seam，U-1R 场景 B）：commit 成功后停在「已落账未 ack」，且
## 保留候选写盘，模拟 ack 前崩溃磁盘形状。
func _finish_settlement(keep_pending := false) -> Dictionary:
	if _settlement.is_empty():
		return {"ok": true, "code": CODE_NO_PENDING}
	if not bool(_settlement["staged"]):
		var staged := _save.set_pending_candidate(_settlement["candidate"], String(_settlement["caught_at_utc"]))
		if staged.get("ok") != true:
			_save_error = true
			return staged
	var commit := _economy.commit_catch(_state, _settlement["catch_event_id"],
			_settlement["species_id"], _settlement["caught_at_utc"])
	# LOG-001：commit 结果唯一记录点（成功/幂等/失败各一条；失败不改变任何返回形状）。
	_log_commit_result(commit, String(_settlement["catch_event_id"]),
			Time.get_ticks_msec() - _settlement_start_ms if _settlement_start_ms >= 0 else null)
	var ok: bool = commit.get("ok") == true \
			and (String(commit.get("code", "")) == "" or String(commit.get("code", "")) == CODE_ALREADY_APPLIED)
	if not ok:
		if String(commit.get("code", "")) == CODE_PERSIST_FAILED:
			_save_error = true  # 候选/时钟保留：解除故障后 retry_persist/settle_retry 同参重试
		return commit
	if keep_pending:
		var staged_again := _persist_checked()
		commit["checkpoint_committed"] = staged_again.get("ok") == true
		return commit
	_fsm.ack_settlement(String(_settlement["catch_event_id"]), true)
	_save.clear_pending_candidate()
	_settlement = {}
	var persisted := _persist_checked()
	commit["checkpoint_committed"] = persisted.get("ok") == true
	return commit


## UTC 单次取样：19 字符 "YYYY-MM-DDTHH:MM:SS" 形状校验后补 Z；不合法返回 ""（fail closed）。
func _sample_utc_once() -> String:
	var text := Time.get_datetime_string_from_system(true)
	if text.length() != 19:
		return ""
	if not FishInstance.timestamp_valid(text + "Z"):
		return ""
	return text + "Z"


# ---- 内部：杂项 ----

func _persist_checked() -> Dictionary:
	if _save == null:
		return {"ok": false, "code": CODE_NOT_READY}
	var result := _save.persist_runtime_checkpoint()
	if result.get("ok") != true:
		_save_error = true
		# LOG-001：checkpoint 未落盘 → 稳定码 PERSIST_FAILED（事件 ID 为 null：checkpoint 无
		# 事务 ID；save_version 取当前权威；不记录内部 stage/reason/path）。
		_log_event({"severity": EventLog.SEVERITY_ERROR, "event": EventLog.EVENT_SAVE_CHECKPOINT_FAILED,
				"result": EventLog.RESULT_ERROR, "error_code": CODE_PERSIST_FAILED, "event_id": null,
				"save_version": int(_state.save_version) if _state != null else null})
	return result


func _deny_if_closed() -> Dictionary:
	if _save == null or _state == null or _fsm == null:
		return {"ok": false, "code": CODE_NOT_READY}
	if not _input_open:
		return {"ok": false, "code": CODE_NOT_READY}
	if _save_error:
		return {"ok": false, "code": CODE_SAVE_ERROR}
	if _hidden:
		return {"ok": false, "code": CODE_HIDDEN}
	return {}


func _sell_denied(code: String) -> Dictionary:
	return {"ok": false, "code": code, "gold_added": 0, "sale_id": String(_active_sale.get("sale_id", ""))}


func _sale_ids_equal(sale: Dictionary, sorted_ids: Array) -> bool:
	var stored: Array = sale["instance_ids"]
	if stored.size() != sorted_ids.size():
		return false
	for index in stored.size():
		if stored[index] != sorted_ids[index]:
			return false
	return true


## 售鱼 ID：Crypto 16 字节 nonce hex + 单调计数器；无设备/用户标识（review #5）。
func _next_sale_id() -> String:
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s%s-%d" % [SALE_ID_PREFIX, nonce, _sale_counter]


func _random_fresh_seed() -> int:
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	var raw := int(String(nonce).substr(0, 8).hex_to_int())
	return 1 + raw % (RNG_STATE_MAX - 1)


func _boot_fail(code: String, reason: String) -> Dictionary:
	_boot_code = code
	_boot_reason = reason
	_input_open = false
	return {"ok": false, "code": code, "reason": reason, "input_open": false, "save_error": _save_error}


# ---- 内部：LOG-001 日志记录（返回值一律忽略；日志故障绝不改变业务/经济状态）----

## 唯一日志出口：EventLog 校验失败/IO 失败都被静默忽略（fail-closed 由 EventLog 自身计数），
## 不置位 _save_error、不阻断调用方（LOG-001 铁律；L-5/L-8 同 seed 对照断言零影响）。
func _log_event(rec: Dictionary) -> void:
	if _log == null:
		return
	_log.record(rec)


## 捕获 commit 结果记录（_finish_settlement / _replay_pending_candidate 共用）：
## ok+空码 → catch_committed/info/ok；ALREADY_APPLIED → catch_committed/warn/already_applied；
## 其余失败码 → catch_failed/error/error（error_code=稳定码）。
func _log_commit_result(commit: Dictionary, catch_event_id: String, elapsed_ms: Variant) -> void:
	var code := String(commit.get("code", ""))
	if commit.get("ok") == true and code.is_empty():
		_log_event({"severity": EventLog.SEVERITY_INFO, "event": EventLog.EVENT_CATCH_COMMITTED,
				"event_id": catch_event_id, "result": EventLog.RESULT_OK, "elapsed_ms": elapsed_ms})
	elif commit.get("ok") == true and code == CODE_ALREADY_APPLIED:
		_log_event({"severity": EventLog.SEVERITY_WARN, "event": EventLog.EVENT_CATCH_COMMITTED,
				"event_id": catch_event_id, "result": EventLog.RESULT_ALREADY_APPLIED,
				"elapsed_ms": elapsed_ms})
	else:
		_log_event({"severity": EventLog.SEVERITY_ERROR, "event": EventLog.EVENT_CATCH_FAILED,
				"event_id": catch_event_id, "result": EventLog.RESULT_ERROR,
				"error_code": code if not code.is_empty() else "CATCH_FAILED", "elapsed_ms": elapsed_ms})


## 售鱼结果记录（sell_selected / retry_persist 共用）：成功 → sale_committed/info/ok（不记金币
## 数额）；失败（含 PERSIST_FAILED、CONFLICT_SALE_PARAMS 等）→ sale_failed/error/error。
func _log_sale_result(result: Dictionary, sale_id: String) -> void:
	if result.get("ok") == true:
		_log_event({"severity": EventLog.SEVERITY_INFO, "event": EventLog.EVENT_SALE_COMMITTED,
				"event_id": sale_id, "result": EventLog.RESULT_OK})
	else:
		var code := String(result.get("code", ""))
		_log_event({"severity": EventLog.SEVERITY_ERROR, "event": EventLog.EVENT_SALE_FAILED,
				"event_id": sale_id, "result": EventLog.RESULT_ERROR,
				"error_code": code if not code.is_empty() else "SALE_FAILED"})
