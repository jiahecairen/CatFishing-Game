class_name AtomicSaveService
extends RefCounted
# SAVE-001：save v2 文档的原子提交 / fail-closed 加载 / 坏档保留 / v1 安全迁移 / 故障注入
# （plan §4.1–§4.5、review 强制条件 #1/#2/#4/#5/#6/#9/#10、INTERFACES §6/§8、SDD V01-S01/S02）。
# 保证边界（如实声明，plan 目标 3 / R-3）：提交点 = 同目录 rename 成功（应用级原子）。
# flush() 只保证 API 级完成，断电级 fsync 与目录元数据/硬件缓存的持久性无法由本票证明。
# 协议（plan §4.2）：0 注入故障→稳定码；1 全量校验 fail-closed 零文件动作；2 固定键序
# JSON.stringify；3 同目录唯一临时文件写→显式错误→flush→回读按 UTF-8 字节数+可解析+
# save_version==2 验证；4 仅当 main 为有效 v1/v2 才原子更新 .bak（坏/缺 main 绝不覆盖好
# .bak）；5 v1 或坏/缺 main 时把原件惰性**复制**（非移动）到唯一 legacy/corrupt 保留名；
# 6 rename 成功才算应用级提交；7 失败路径只清理本次临时文件，绝不删除/移动
# main/.bak/legacy/corrupt 原件。
# 装配协议（plan §4.5，未来 GameController 接线蓝图）：install_into 注入 EconomyService
# 持久化门；_gate 只认布尔 true 且仅在 rename 成功后返回 true；发布顺序「校验→构造 next→
# 写盘→成功才发布」，禁止先发布金币/鱼篓再写盘。RNG/Clock/候选由调用方经本类快照/恢复
# （G-3/G-4：不改 FSM/GameState）。
# 不变量：纯 RefCounted——无 Node/_process/帧计数、不读写 res://、生产默认 user://
# （INTERFACES §8 不落源码树）、测试注入显式临时目录；故障注入默认全关且仅测试使用。

const ValidateScript := preload("res://scripts/save/save_validate.gd")
const FaultsScript := preload("res://scripts/save/save_faults.gd")

const MAIN_NAME := "game_state.json"
const BAK_NAME := "game_state.json.bak"
const TMP_PREFIX := "game_state.tmp."
const BAK_TMP_PREFIX := "game_state.json.bak.tmp."
const LEGACY_PREFIX := "game_state.legacy."
const CORRUPT_PREFIX := "game_state.corrupt."
const DEFAULT_DIR := "user://"

var _installed := false
var _dir := DEFAULT_DIR
var _economy: EconomyService = null
var _state: GameState = null
var _rng: DeterministicRng = null
var _clock: VirtualClock = null
var _fsm: FishingStateMachine = null
var _catalog: Dictionary = {}
var _pending_candidate: Variant = null  # null 或已验证 6 键候选 payload 深拷贝
var _faults = null  # SaveFaults；仅测试武装
var _tmp_seq := 0
var _recovered_from_backup := false
var _last_report: Dictionary = {}


## 测试注入显式存档目录（生产默认 user://，INTERFACES §8）。仅允许 install_into 之前调用。
func configure_dir(directory: String) -> Dictionary:
	if _installed:
		return _result(false, SaveValidate.CODE_ALREADY_INSTALLED, "configure_dir after install_into is refused", {})
	if directory.is_empty():
		return _result(false, SaveValidate.CODE_BAD_PAYLOAD, "directory must be a non-empty path", {})
	_dir = directory if directory.ends_with("/") else directory + "/"
	var dir_error := DirAccess.make_dir_recursive_absolute(_dir)
	if dir_error != OK:
		return _result(false, SaveValidate.CODE_TMP_WRITE_FAILED, "cannot create save directory (%s)" % error_string(dir_error), {})
	return _result(true, "", "", {"dir": _dir})


## 装配并注入经济持久化门（plan §4.5）。任一服务为 null → BAD_INJECTION；catalog 非法 →
## BAD_CATALOG；重复装配 → ALREADY_INSTALLED（幂等拒绝，零改动）。
func install_into(economy: EconomyService, state: GameState, rng: DeterministicRng,
		clock: VirtualClock, fsm: FishingStateMachine, valid_species_by_id: Variant) -> Dictionary:
	if _installed:
		return _result(false, SaveValidate.CODE_ALREADY_INSTALLED, "already installed", {})
	if economy == null or state == null or rng == null or clock == null or fsm == null:
		return _result(false, SaveValidate.CODE_BAD_INJECTION, "all five services must be non-null", {})
	if not SaveValidate.catalog_valid(valid_species_by_id):
		return _result(false, SaveValidate.CODE_BAD_CATALOG, "valid_species_by_id must be a non-empty validated map", {})
	var economy_setup: Dictionary = economy.set_persistence_gate(Callable(self, "_gate"))
	if economy_setup.get("ok") != true:
		return _result(false, SaveValidate.CODE_BAD_INJECTION, "persistence gate rejected", {})
	_installed = true
	_economy = economy
	_state = state
	_rng = rng
	_clock = clock
	_fsm = fsm
	_catalog = (valid_species_by_id as Dictionary).duplicate(true)
	if _faults == null:
		_faults = FaultsScript.new()
	return _result(true, "", "", {"dir": _dir})


## 故障注入 seam（仅测试；生产默认全关）。未知阶段 → BAD_STAGE。
func set_fault_injection(stage: String, armed: bool) -> Dictionary:
	if _faults == null:
		_faults = FaultsScript.new()
	var result: Dictionary = _faults.set_armed(stage, armed)
	return _result(result.get("ok") == true, String(result.get("code", "")), "", {"fault": stage, "armed": armed})


## 记录待结算候选（plan §4.5）：仅接受 FSM 成功候选、FSM 处于 SETTLEMENT 且 event 一致；
## 严格校验 UTC 与目录价格/权重/稀有度快照后存深拷贝。失败零改动。
func set_pending_candidate(candidate: Variant, caught_at_utc: Variant) -> Dictionary:
	if not _installed:
		return _result(false, SaveValidate.CODE_NOT_INSTALLED, "install_into first", {})
	if not (candidate is Dictionary):
		return _result(false, SaveValidate.CODE_BAD_PAYLOAD, "candidate must be a dictionary", {})
	var raw: Dictionary = candidate
	if raw.get("ok") != true or String(raw.get("code", "")) != "" \
			or not raw.has("catch_event_id") or not raw.has("species_id") \
			or not raw.has("weight_snapshot") or not raw.has("caught_at_clock"):
		return _result(false, SaveValidate.CODE_BAD_PAYLOAD, "candidate is not a successful FSM payload", {})
	if not FishInstance.timestamp_valid(caught_at_utc):
		return _result(false, SaveValidate.CODE_BAD_TIMESTAMP, "caught_at_utc is not valid UTC seconds", {})
	var checkpoint: Dictionary = _fsm.snapshot_checkpoint()
	if String(checkpoint["state"]) != "SETTLEMENT" or checkpoint["event_id"] != raw["catch_event_id"]:
		return _result(false, SaveValidate.CODE_BAD_PAYLOAD, "FSM is not in SETTLEMENT for this candidate", {})
	var payload := {
		"version": SaveValidate.SNAPSHOT_VERSION,
		"catch_event_id": raw["catch_event_id"],
		"species_id": raw["species_id"],
		"weight_snapshot": (raw["weight_snapshot"] as Dictionary).duplicate(true),
		"caught_at_clock": raw["caught_at_clock"],
		"caught_at_utc": String(caught_at_utc),
	}
	if SaveValidate._validate_candidate(payload, _catalog, checkpoint, _economy.snapshot_ledger()).get("ok") != true:
		return _result(false, SaveValidate.CODE_CANDIDATE_CONFIG_MISMATCH,
				"candidate does not match validated catalog/state", {})
	_pending_candidate = payload
	return _result(true, "", "", {"catch_event_id": String(payload["catch_event_id"])})


## 清除候选（结算 ack 成功后调用）。
func clear_pending_candidate() -> Dictionary:
	var cleared_id := ""
	if _pending_candidate != null:
		cleared_id = String((_pending_candidate as Dictionary)["catch_event_id"])
	_pending_candidate = null
	return _result(true, "", "", {"catch_event_id": cleared_id})


## 经济事务以外的完整运行时检查点提交（review 补充 #1、plan §4.5）。
## 从绑定服务构造完整副本（revision+1、save_version 归一 2、fsm 实际 checkpoint），
## 仅 rename 成功后发布 state.revision/fishing_checkpoint/save_version；失败三者零改动。
## 调用契约：启动/抛竿后、每次 FSM 状态转换、隐藏/暂停前及恢复后、候选产生/清除后立即；
## WAITING 中按有效捕鱼时间最多每 5 秒一次，不逐渲染帧写盘（5 秒为恢复精度实现值）。
func persist_runtime_checkpoint() -> Dictionary:
	if not _installed:
		return _result(false, SaveValidate.CODE_NOT_INSTALLED, "install_into first", {})
	var checkpoint: Dictionary = _fsm.snapshot_checkpoint()
	var document := _document_from(_state_snapshot(_state), _economy.snapshot_ledger(), checkpoint)
	document["revision"] = int(_state.revision) + 1
	document["save_version"] = SaveValidate.SAVE_VERSION
	var committed := _commit(document)
	if committed.get("ok") == true:
		_state.revision += 1
		_state.fishing_checkpoint = checkpoint.duplicate(true)
		_state.save_version = SaveValidate.SAVE_VERSION
	return committed


## 全量 v2 文档的原子提交（供测试直接提交合同文档；同 _gate 内部路径）。
func atomic_commit(document: Variant) -> Dictionary:
	return _commit(document)


## 当前绑定服务构成的完整 13 键 v2 文档（与 atomic_commit 成功时会写出的内容同形同序；
## 供测试做「磁盘字节 == export_document().stringify」的字节一致性断言，本身零写入）。
func export_document() -> Dictionary:
	return _float_normalized(_ordered_document(_document_from(_state_snapshot(_state), _economy.snapshot_ledger(),
			_fsm.snapshot_checkpoint())))


## 落盘表示归一化（Godot 4.7.2 实测）：JSON.parse_string 把所有 JSON 数字解析为 float，
## JSON.stringify(float 整数值) 恒为 "x.0" 形态——"2" 形态落盘后回读再 stringify 会变成 "2.0"，
## 字节不再一致；"2.0" 形态则是 parse∘stringify 的稳定不动点。故提交前把全部数字归一为
## float，磁盘文档全数字均为 float 形态 ⇒ 「重复加载逐字节同 JSON」（plan S1）成立；
## 语义校验（SaveValidate._is_integral 双态判据）不受影响。
static func _float_normalized(payload: Variant) -> Variant:
	if payload is Dictionary:
		var out_dict: Dictionary = {}
		for key in payload:
			out_dict[key] = _float_normalized(payload[key])
		return out_dict
	if payload is Array:
		var out_array: Array = []
		for element in payload:
			out_array.append(_float_normalized(element))
		return out_array
	if payload is int:
		return float(payload)
	return payload


## 经济持久化门（INTERFACES §6）：payload = EconomyService 的 {next_state(9 键深拷贝),
## ledger(深拷贝)}。实际 fsm.snapshot_checkpoint() 覆盖到副本（不留陈旧 checkpoint），
## rng/clock/候选取绑定服务当前快照。仅 rename 成功返回 true（先发布金币/鱼篓被禁止）。
func _gate(payload: Variant) -> bool:
	if not _installed or not (payload is Dictionary):
		return false
	var envelope: Dictionary = payload
	if not envelope.has("next_state") or not envelope.has("ledger"):
		return false
	var checkpoint: Dictionary = _fsm.snapshot_checkpoint()
	var document := _document_from(envelope["next_state"], envelope["ledger"], checkpoint)
	document["save_version"] = SaveValidate.SAVE_VERSION
	var committed := _commit(document)
	if committed.get("ok") == true:
		_state.fishing_checkpoint = checkpoint.duplicate(true)
		_state.save_version = SaveValidate.SAVE_VERSION
		return true
	return false


## 从已验证存档加载（plan §4.3/§4.4）。全链 fail-closed、零写入、坏档保留：
## main v2 ⇒ OK；main 坏/缺 ⇒ bak v2（或可安全迁移的 bak v1）⇒ RECOVERED_FROM_BACKUP；
## 皆不可用 ⇒ NO_VALID_SAVE；main v>2 ⇒ VERSION_NEWER；v1 ⇒ MIGRATED_V1（仅内存，
## 下次成功提交才落盘）或 VERSION_LEGACY_UNSAFE。坏 main 的惰性隔离发生在下一次提交。
func load_save(valid_species_by_id: Variant, fresh_seed: int = 1) -> Dictionary:
	if not SaveValidate.catalog_valid(valid_species_by_id):
		return _load_result(false, SaveValidate.CODE_BAD_CATALOG, "valid_species_by_id must be a non-empty validated map", {})
	if fresh_seed < 1 or fresh_seed > SaveValidate.RNG_STATE_MAX:
		return _load_result(false, SaveValidate.CODE_BAD_FRESH_SEED, "fresh_seed must be an int in [1, 2^31-2]", {})
	var catalog: Dictionary = valid_species_by_id
	var main := _read_document(_main_path(), catalog)
	var backup := _read_document(_backup_path(), catalog)
	var main_code := String(main["code"])
	if main_code == SaveValidate.STATUS_NEWER:
		_last_report = {"code": SaveValidate.CODE_VERSION_NEWER, "main_status": String(main["status"]),
				"reason": "save_version from a newer build; refuse to load or overwrite", "writes": false}
		return _load_result(false, SaveValidate.CODE_VERSION_NEWER, String(main["reason"]),
				{"main_status": String(main["status"]), "writes": false})
	if main_code == SaveValidate.STATUS_V2:
		var document: Dictionary = main["document"]
		var state := _state_from_document(document)
		state.save_version = SaveValidate.SAVE_VERSION
		_recovered_from_backup = false
		_last_report = {"code": "OK", "main_status": String(main["status"]), "reason": "", "writes": false}
		var loaded := _load_result(true, "", "", {"main_status": String(main["status"]), "writes": false,
				"document": document.duplicate(true)})
		loaded["state"] = state
		loaded["ledger"] = (document["economy_ledger"] as Dictionary).duplicate(true)
		loaded["rng_snapshot"] = _normalize_json_numbers(document["rng_snapshot"])
		loaded["clock_snapshot"] = _normalize_json_numbers(document["clock_snapshot"])
		loaded["pending_candidate"] = null if document["pending_candidate"] == null \
				else _normalize_json_numbers(document["pending_candidate"])
		return loaded
	# —— main 不可直接用：v1 迁移或备份回退 ——
	if main_code == SaveValidate.STATUS_V1:
		return _migrate_v1(main["document"], "main", fresh_seed, catalog)
	if main_code == SaveValidate.STATUS_CORRUPT or main_code == SaveValidate.STATUS_MISSING:
		if String(backup["code"]) == SaveValidate.STATUS_V2:
			return _load_from_backup(backup["document"], String(main["status"]), String(backup["status"]))
		if String(backup["code"]) == SaveValidate.STATUS_V1:
			var migrated := _migrate_v1(backup["document"], "backup", fresh_seed, catalog)
			if migrated.get("ok") == true:
				migrated["report"]["recovered_from_backup"] = true
				_recovered_from_backup = true
			return migrated
		# 主坏且备**缺失** ⇒ MAIN_CORRUPT（坏原件本身即事实，保留）；其余不可用组合
		# （主缺备缺/主坏备坏/主缺备坏，plan §4.3「主备皆坏/皆缺」）⇒ NO_VALID_SAVE。
		var unusable_code := SaveValidate.CODE_MAIN_CORRUPT \
				if main_code == SaveValidate.STATUS_CORRUPT \
						and String(backup["code"]) == SaveValidate.STATUS_MISSING \
				else SaveValidate.CODE_NO_VALID_SAVE
		return _load_result(false, unusable_code,
				"no usable save; all originals retained",
				{"main_status": String(main["status"]), "backup_status": String(backup["status"]), "writes": false})
	# 理论不可达：classify 只产出上述状态
	return _load_result(false, SaveValidate.CODE_MAIN_CORRUPT, "unclassified main status", {})


func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)


func is_recovered_from_backup() -> bool:
	return _recovered_from_backup


# ---- 内部：提交 ----

func _commit(document: Variant) -> Dictionary:
	if not _installed:
		return _commit_fail(SaveValidate.CODE_NOT_INSTALLED, "install_into first", SaveValidate.STATUS_MISSING, "validate")
	var main := _read_document(_main_path(), _catalog)
	var main_status := String(main["status"])
	if main_status == SaveValidate.STATUS_NEWER:
		return _commit_fail(SaveValidate.CODE_VERSION_NEWER,
				"existing main save_version is from a newer build; refusing silent overwrite", main_status, "read")
	var validation := SaveValidate.validate_v2_document(document, _catalog)
	if validation.get("ok") != true:
		return _commit_fail(String(validation["code"]), String(validation["reason"]), main_status, "validate")
	if _faults != null and _faults.is_armed("tmp_write"):
		return _commit_fail(SaveValidate.CODE_TMP_WRITE_FAILED, "fault injection: tmp_write", main_status, "tmp_write")
	var json_text := JSON.stringify(_float_normalized(_ordered_document(document)))
	var temp_path := _next_temp_path(TMP_PREFIX)
	var write_error := _write_text(temp_path, json_text)
	if not write_error.is_empty():
		_remove_quietly(temp_path)
		return _commit_fail(SaveValidate.CODE_TMP_WRITE_FAILED, write_error, main_status, "tmp_write")
	if _faults != null and _faults.is_armed("tmp_flush"):
		_remove_quietly(temp_path)
		return _commit_fail(SaveValidate.CODE_TMP_FLUSH_FAILED, "fault injection: tmp_flush", main_status, "tmp_flush")
	var verify_error := _verify_temp(temp_path, json_text)
	if not verify_error.is_empty():
		_remove_quietly(temp_path)
		return _commit_fail(SaveValidate.CODE_TMP_VERIFY_FAILED, verify_error, main_status, "tmp_verify")
	# rename 故障先行检查：本笔注定无法原子提交 ⇒ 后续任何触碰 .bak/legacy/corrupt
	# 保留文件的步骤一律不执行（失败零改动合同，plan S2「失败零残留+失败零发布」）。
	if _faults != null and _faults.is_armed("rename"):
		_remove_quietly(temp_path)
		return _commit_fail(SaveValidate.CODE_RENAME_FAILED, "fault injection: rename", main_status, "rename")
	# 步骤 4：仅当 main 为有效 v1/v2 才原子更新 .bak；坏/缺 main 绝不覆盖好 .bak（review #9）。
	var backup_updated := false
	if main_status == SaveValidate.STATUS_V1 or main_status == SaveValidate.STATUS_V2:
		if _faults != null and _faults.is_armed("backup"):
			_remove_quietly(temp_path)
			return _commit_fail(SaveValidate.CODE_BACKUP_FAILED, "fault injection: backup", main_status, "backup")
		var backup_error := _update_backup(_main_path())
		if not backup_error.is_empty():
			_remove_quietly(temp_path)
			return _commit_fail(SaveValidate.CODE_BACKUP_VERIFY_FAILED, backup_error, main_status, "backup")
		backup_updated = true
	# 步骤 5：v1 或坏/缺 main ⇒ 惰性复制原件到唯一保留名（main 全程留在原位，review #2/#10）。
	var archive_path := ""
	if main_status == SaveValidate.STATUS_V1:
		if _faults != null and _faults.is_armed("legacy_copy"):
			_remove_quietly(temp_path)
			return _commit_fail(SaveValidate.CODE_LEGACY_COPY_FAILED, "fault injection: legacy_copy", main_status, "legacy")
		archive_path = _unique_archive_path(LEGACY_PREFIX)
		var legacy_error := _archive_copy(_main_path(), archive_path)
		if not legacy_error.is_empty():
			DirAccess.remove_absolute(archive_path)  # 仅本次未完成的临时副本，不触碰原件
			_remove_quietly(temp_path)
			return _commit_fail(SaveValidate.CODE_LEGACY_COPY_FAILED, legacy_error, main_status, "legacy")
	elif main_status == SaveValidate.STATUS_CORRUPT:
		if _faults != null and _faults.is_armed("quarantine"):
			_remove_quietly(temp_path)
			return _commit_fail(SaveValidate.CODE_QUARANTINE_FAILED, "fault injection: quarantine", main_status, "quarantine")
		archive_path = _unique_archive_path(CORRUPT_PREFIX)
		var corrupt_error := _archive_copy(_main_path(), archive_path)
		if not corrupt_error.is_empty():
			DirAccess.remove_absolute(archive_path)
			_remove_quietly(temp_path)
			return _commit_fail(SaveValidate.CODE_QUARANTINE_FAILED, corrupt_error, main_status, "quarantine")
	# 步骤 6：原子替换；rename OK 才算应用级提交（步骤 7 失败路径不触碰任何原件）。
	var rename_error := DirAccess.rename_absolute(temp_path, _main_path())
	if rename_error != OK:
		_remove_quietly(temp_path)
		return _commit_fail(SaveValidate.CODE_RENAME_FAILED, "rename failed (%s)" % error_string(rename_error),
				main_status, "rename")
	_recovered_from_backup = false
	return _result(true, "", "", {
			"stage": "commit", "main_status": main_status, "temp": temp_path,
			"archive": archive_path, "backup_updated": backup_updated, "bytes": json_text.to_utf8_buffer().size()})


func _commit_fail(code: String, reason: String, main_status: String, stage: String) -> Dictionary:
	_last_report = {"code": code, "reason": reason, "main_status": main_status, "stage": stage}
	return _result(false, code, reason, {"stage": stage, "main_status": main_status})


# ---- 内部：文档构造 ----

## 固定键序构造 13 键 v2 文档（键序固定 ⇒ 字节确定，可断言）。
func _ordered_document(document: Dictionary) -> Dictionary:
	return {
		"save_version": document["save_version"],
		"revision": document["revision"],
		"wallet_gold": document["wallet_gold"],
		"basket_capacity": document["basket_capacity"],
		"basket": (document["basket"] as Array).duplicate(true),
		"processed_catch_ids": (document["processed_catch_ids"] as Array).duplicate(true),
		"processed_sale_ids": (document["processed_sale_ids"] as Array).duplicate(true),
		"fishing_checkpoint": (document["fishing_checkpoint"] as Dictionary).duplicate(true),
		"desktop_window": (document["desktop_window"] as Dictionary).duplicate(true),
		"economy_ledger": (document["economy_ledger"] as Dictionary).duplicate(true),
		"rng_snapshot": (document["rng_snapshot"] as Dictionary).duplicate(true),
		"clock_snapshot": (document["clock_snapshot"] as Dictionary).duplicate(true),
		"pending_candidate": null if document["pending_candidate"] == null
				else (document["pending_candidate"] as Dictionary).duplicate(true),
	}


func _document_from(next_state: Variant, ledger: Variant, checkpoint: Dictionary) -> Dictionary:
	var state_dict: Dictionary = next_state
	return {
		"save_version": SaveValidate.SAVE_VERSION,
		"revision": int(state_dict["revision"]),
		"wallet_gold": int(state_dict["wallet_gold"]),
			"basket_capacity": int(state_dict["basket_capacity"]),
		"basket": (state_dict["basket"] as Array).duplicate(true),
		"processed_catch_ids": (state_dict["processed_catch_ids"] as Array).duplicate(true),
		"processed_sale_ids": (state_dict["processed_sale_ids"] as Array).duplicate(true),
		"fishing_checkpoint": checkpoint.duplicate(true),
		"desktop_window": (state_dict["desktop_window"] as Dictionary).duplicate(true),
		"economy_ledger": (ledger as Dictionary).duplicate(true),
		"rng_snapshot": _rng.snapshot_state(),
		"clock_snapshot": _clock.snapshot_state(),
		"pending_candidate": null if _pending_candidate == null else (_pending_candidate as Dictionary).duplicate(true),
	}


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


func _state_from_document(document: Dictionary) -> GameState:
	var state := GameState.new()
	state.save_version = int(document["save_version"])
	state.revision = int(document["revision"])
	state.wallet_gold = int(document["wallet_gold"])
	state.basket_capacity = int(document["basket_capacity"])
	state.basket = (_normalize_json_numbers(document["basket"]) as Array)
	state.processed_catch_ids = (document["processed_catch_ids"] as Array).duplicate(true)
	state.processed_sale_ids = (document["processed_sale_ids"] as Array).duplicate(true)
	state.fishing_checkpoint = _normalize_json_numbers(document["fishing_checkpoint"]) as Dictionary
	state.desktop_window = _normalize_json_numbers(document["desktop_window"]) as Dictionary
	return state


## JSON 数字 → 运行时类型归一化（Godot 4.7.2 实测：JSON.parse_string 把一切 JSON 数字解析为
## float，整数 2 也是 float）。磁盘回读的快照交回调用方后，由不在本票范围的
## DeterministicRng/VirtualClock.restore_state 与 FishingStateMachine.initialize（严格 `is int`
## 判 version/seed/state/wait_seconds）做二次 fail-closed 验证——存档层是 JSON 边界，须在此
## 把整数值 float 归一为 int（JSON Schema integer 语义，对齐 FishInstance.price_valid 的
## 「JSON 数字双态」项目判例）；非整数值 float 原样保留（SaveValidate 已先行 fail-closed 拒绝，
## 归一化不新增任何放行面）。仅作用于返回给运行时的 state/snapshot/candidate 负载；
## report.document 保持磁盘解析原形，供逐字节审计断言。
static func _normalize_json_numbers(payload: Variant) -> Variant:
	if payload is Dictionary:
		var out_dict: Dictionary = {}
		for key in payload:
			out_dict[key] = _normalize_json_numbers(payload[key])
		return out_dict
	if payload is Array:
		var out_array: Array = []
		for element in payload:
			out_array.append(_normalize_json_numbers(element))
		return out_array
	if payload is float:
		var value := float(payload)
		if value - value == 0.0 and absf(value) < SaveValidate.MAX_INT64_FLOAT_EXCLUSIVE \
				and float(int(value)) == value:
			return int(value)
	return payload


# ---- 内部：v1 迁移（plan §4.4，无静默丢失）----

func _migrate_v1(document: Dictionary, source: String, fresh_seed: int, catalog: Dictionary) -> Dictionary:
	var reason := SaveValidate.v1_migration_reject_reason(document)
	if not reason.is_empty():
		_last_report = {"code": SaveValidate.CODE_VERSION_LEGACY_UNSAFE, "main_status": "legacy:" + source,
				"reason": "v1 cannot be proven safe to migrate: " + reason, "writes": false}
		return _load_result(false, SaveValidate.CODE_VERSION_LEGACY_UNSAFE,
				"v1 cannot be proven safe to migrate: " + reason,
				{"main_status": "legacy:" + source, "migration_reason": reason, "writes": false})
	var migrated := _ordered_document({
		"save_version": SaveValidate.SAVE_VERSION,
		"revision": int(document["revision"]),
		"wallet_gold": int(document["wallet_gold"]),
		"basket_capacity": int(document["basket_capacity"]),
		"basket": [],
		"processed_catch_ids": [],
		"processed_sale_ids": [],
		"fishing_checkpoint": (document["fishing_checkpoint"] as Dictionary).duplicate(true),
		"desktop_window": (document["desktop_window"] as Dictionary).duplicate(true),
		"economy_ledger": {"processed_catches": {}, "processed_sales": {}},
		"rng_snapshot": {"version": SaveValidate.SNAPSHOT_VERSION, "seed": fresh_seed, "state": fresh_seed},
		"clock_snapshot": {"version": SaveValidate.SNAPSHOT_VERSION, "now": 0.0},
		"pending_candidate": null,
	})
	if SaveValidate.validate_v2_document(migrated, catalog).get("ok") != true:
		return _load_result(false, SaveValidate.CODE_MAIN_CORRUPT, "migrated v2 document failed validation", {})
	_last_report = {"code": SaveValidate.CODE_MIGRATED_V1, "main_status": "legacy:" + source,
			"reason": "pure shape upgrade; rng seed freshly created (no historical continuity claim)", "writes": false}
	var state := _state_from_document(document)  # v1 九键原样；save_version 保持 1 直到首次成功提交
	var migrated_result := _load_result(true, SaveValidate.CODE_MIGRATED_V1,
			"pure shape upgrade; fresh rng seed, no historical continuity claim", {
			"main_status": "legacy:" + source, "writes": false, "fresh_seed": fresh_seed,
			"document": migrated})
	migrated_result["state"] = state
	migrated_result["ledger"] = (migrated["economy_ledger"] as Dictionary).duplicate(true)
	migrated_result["rng_snapshot"] = (migrated["rng_snapshot"] as Dictionary).duplicate(true)
	migrated_result["clock_snapshot"] = (migrated["clock_snapshot"] as Dictionary).duplicate(true)
	migrated_result["pending_candidate"] = null
	return migrated_result


func _load_from_backup(document: Dictionary, _main_status: String, backup_status: String) -> Dictionary:
	var state := _state_from_document(document)
	state.save_version = SaveValidate.SAVE_VERSION
	_recovered_from_backup = true
	_last_report = {"code": SaveValidate.CODE_RECOVERED_FROM_BACKUP, "main_status": _main_status,
			"reason": "main unusable; adopted validated backup; corrupt main retained until next successful commit",
			"writes": false}
	var recovered := _load_result(true, SaveValidate.CODE_RECOVERED_FROM_BACKUP,
			"main unusable; adopted validated backup; corrupt main retained until next successful commit", {
			"main_status": _main_status, "backup_status": backup_status, "writes": false,
			"document": document.duplicate(true)})
	recovered["state"] = state
	recovered["ledger"] = (document["economy_ledger"] as Dictionary).duplicate(true)
	recovered["rng_snapshot"] = _normalize_json_numbers(document["rng_snapshot"])
	recovered["clock_snapshot"] = _normalize_json_numbers(document["clock_snapshot"])
	recovered["pending_candidate"] = null if document["pending_candidate"] == null \
			else _normalize_json_numbers(document["pending_candidate"])
	return recovered


# ---- 内部：文件原语（全部显式错误检查）----

func _main_path() -> String:
	return _dir + MAIN_NAME


func _backup_path() -> String:
	return _dir + BAK_NAME


func _next_temp_path(prefix: String) -> String:
	_tmp_seq += 1
	return _dir + prefix + "%d_%d.json" % [OS.get_process_id(), _tmp_seq]


func _unique_archive_path(prefix: String) -> String:
	var index := 1
	while FileAccess.file_exists(_dir + prefix + "%d.json" % index):
		index += 1
	return _dir + prefix + "%d.json" % index


func _read_document(path: String, catalog: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"code": SaveValidate.STATUS_MISSING, "status": SaveValidate.STATUS_MISSING, "document": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"code": SaveValidate.STATUS_CORRUPT, "status": SaveValidate.STATUS_CORRUPT,
				"reason": "cannot open (%s)" % error_string(FileAccess.get_open_error())}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	var classification: Dictionary = SaveValidate.classify_document(parsed, catalog)
	return {"code": String(classification["status"]), "status": String(classification["status"]),
			"reason": String(classification.get("reason", "")),
			"document": parsed if parsed is Dictionary else {}}


func _write_text(path: String, text: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "cannot open temp for write (%s)" % error_string(FileAccess.get_open_error())
	file.store_string(text)
	var write_error := file.get_error()
	file.flush()  # Godot 4 的 FileAccess.flush() 返回 void，错误经 get_error() 报告
	var flush_error := file.get_error()
	file.close()
	if write_error != OK:
		return "store_string failed (%s)" % error_string(write_error)
	if flush_error != OK:
		return "flush failed (%s)" % error_string(flush_error)
	return ""


## 临时文件回读验证：可解析、save_version==2、UTF-8 字节数一致（不能用字符数代替）。
func _verify_temp(path: String, expected_text: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "cannot reopen temp (%s)" % error_string(FileAccess.get_open_error())
	var length := file.get_length()
	var text := file.get_as_text()
	file.close()
	if length != expected_text.to_utf8_buffer().size():
		return "temp byte length %d != expected UTF-8 byte length %d" % [length, expected_text.to_utf8_buffer().size()]
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return "temp is not parseable as a JSON object"
	if int(parsed["save_version"]) != SaveValidate.SAVE_VERSION:
		return "temp save_version is not 2"
	return ""


## 从已验证 main 原子更新 .bak：复制到唯一备份临时名 → 逐字节验证 → rename。
func _update_backup(main_path: String) -> String:
	var backup_temp := _next_temp_path(BAK_TMP_PREFIX)
	var copy_error := DirAccess.copy_absolute(main_path, backup_temp)
	if copy_error != OK:
		_remove_quietly(backup_temp)
		return "backup copy failed (%s)" % error_string(copy_error)
	var main_bytes := _read_bytes(main_path)
	var temp_bytes := _read_bytes(backup_temp)
	if main_bytes != temp_bytes:
		_remove_quietly(backup_temp)
		return "backup temp bytes differ from main"
	var rename_error := DirAccess.rename_absolute(backup_temp, _backup_path())
	if rename_error != OK:
		_remove_quietly(backup_temp)
		return "backup rename failed (%s)" % error_string(rename_error)
	return ""


## 坏档/旧版原件惰性隔离：唯一临时副本 → 逐字节验证 → rename 到保留名。原件不动。
func _archive_copy(source: String, target: String) -> String:
	var archive_temp := _next_temp_path(TMP_PREFIX)
	var copy_error := DirAccess.copy_absolute(source, archive_temp)
	if copy_error != OK:
		return "archive copy failed (%s)" % error_string(copy_error)
	if _read_bytes(source) != _read_bytes(archive_temp):
		return "archive temp bytes differ from original"
	var rename_error := DirAccess.rename_absolute(archive_temp, target)
	if rename_error != OK:
		return "archive rename failed (%s)" % error_string(rename_error)
	return ""


func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes


func _remove_quietly(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ---- 内部：信封 ----

func _result(ok_flag: bool, code: String, reason: String, extra: Dictionary) -> Dictionary:
	_last_report = {"code": code, "reason": reason}
	for key in extra:
		_last_report[key] = extra[key]
	var out := {"ok": ok_flag, "code": code, "reason": reason, "report": _last_report.duplicate(true)}
	return out


func _load_result(ok_flag: bool, code: String, reason: String, extra: Dictionary) -> Dictionary:
	var out := _result(ok_flag, code, reason, extra)
	if not out.has("state"):
		out["state"] = null
		out["ledger"] = null
		out["rng_snapshot"] = null
		out["clock_snapshot"] = null
		out["pending_candidate"] = null
	return out
