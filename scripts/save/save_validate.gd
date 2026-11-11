class_name SaveValidate
extends RefCounted
# SAVE-001：save v2 文档 + v1 legacy 旧形的静态 fail-closed 校验器（plan §4.1/§4.3/§4.4）。
# 单一实现被 AtomicSaveService 的 commit / load / 迁移三条路径复用；JSON Schema 只声明
# 形状，本类是唯一语义执行器（无 jsonschema 依赖，plan R-6）。
# 语义不变量（plan §4.3 全清单）：
# - v2 顶层恰 13 键、v1 顶层恰 9 键（additionalProperties=false 语义）；
# - basket ≤ capacity；鱼恰五键、instance/source ID 唯一且 UTC 合法（FishInstance 复用）；
# - processed ids：非空字符串且唯一；
# - economy_ledger 两侧键集合 == processed ids 集合（与 EconomyService.restore_ledger 同判据）；
#   账本称已出售实例不得仍在篮；篮中每条鱼的 source_event_id ∈ catch 账本且指纹
#   {species_id, caught_at_utc} 逐值一致；
# - wallet_gold 仅按 schema 判非负整数，绝不额外推断「余额>0 ⇒ 必有 sale ID」（review #3）；
# - basket / catch 账本指纹 / pending_candidate 的 species_id 必须 ∈ 调用方（配置门通过后）
#   传入的 valid_species_by_id；
# - pending_candidate.weight_snapshot 必须与同一已验证目录中该鱼种的
#   catch_weight/base_price/rarity 逐值相同（CANDIDATE_CONFIG_MISMATCH）；篮内已有鱼仍以
#   sale_price_at_catch 为权威，不与当前目录价比较；
# - pending_candidate.caught_at_utc 必须通过 FishInstance.timestamp_valid（不把逻辑秒伪装成 UTC）；
# - rng_snapshot/clock_snapshot 形状与值域（另由调用方 restore_state 二次 fail-closed 验证）；
# - pending_candidate != null ⇒ checkpoint.state == "SETTLEMENT" 且 checkpoint.event_id ==
#   candidate.catch_event_id；若该 catch_id 已入账本 ⇒ 指纹 species_id == candidate species_id。
# 不变量：纯静态工具——无实例状态、无文件 IO、无 Node/_process、不读写 user://。

const SAVE_VERSION := 2
const LEGACY_SAVE_VERSION := 1
const SNAPSHOT_VERSION := 1
const RNG_STATE_MAX := 2147483646  # 2^31 - 2 = DeterministicRng.MODULUS - 1
const MAX_INT64_FLOAT_EXCLUSIVE := 9223372036854775808.0
const STATE_NAMES := ["IDLE", "CASTING", "WAITING", "HOOKED", "REELING", "SETTLEMENT", "PAUSED"]

const DOC_KEYS := ["save_version", "revision", "wallet_gold", "basket_capacity", "basket",
		"processed_catch_ids", "processed_sale_ids", "fishing_checkpoint", "desktop_window",
		"economy_ledger", "rng_snapshot", "clock_snapshot", "pending_candidate"]
const V1_DOC_KEYS := ["save_version", "revision", "wallet_gold", "basket_capacity", "basket",
		"processed_catch_ids", "processed_sale_ids", "fishing_checkpoint", "desktop_window"]
const CHECKPOINT_KEYS := ["state", "event_id", "wait_seconds", "elapsed_effective_seconds"]
const WINDOW_KEYS := ["x", "y", "width", "height", "display_hint"]
const LEDGER_KEYS := ["processed_catches", "processed_sales"]
const CATCH_FP_KEYS := ["species_id", "caught_at_utc"]
const RNG_KEYS := ["version", "seed", "state"]
const CLOCK_KEYS := ["version", "now"]
const CANDIDATE_KEYS := ["version", "catch_event_id", "species_id", "weight_snapshot",
		"caught_at_clock", "caught_at_utc"]
const WEIGHT_SNAPSHOT_KEYS := ["catch_weight", "base_price", "rarity"]

# 稳定错误码（提交/加载/迁移三路共用；AtomicSaveService 与测试按字面值断言）
const CODE_BAD_DOC := "BAD_DOC"
const CODE_MAIN_CORRUPT := "MAIN_CORRUPT"
const CODE_VERSION_NEWER := "VERSION_NEWER"
const CODE_VERSION_LEGACY_UNSAFE := "VERSION_LEGACY_UNSAFE"
const CODE_NO_VALID_SAVE := "NO_VALID_SAVE"
const CODE_RECOVERED_FROM_BACKUP := "RECOVERED_FROM_BACKUP"
const CODE_MIGRATED_V1 := "MIGRATED_V1"
const CODE_LEDGER_MISMATCH := "LEDGER_MISMATCH"
const CODE_UNKNOWN_SPECIES := "UNKNOWN_SPECIES"
const CODE_CANDIDATE_CONFIG_MISMATCH := "CANDIDATE_CONFIG_MISMATCH"
const CODE_CANDIDATE_LEDGER_MISMATCH := "CANDIDATE_LEDGER_MISMATCH"
const CODE_CANDIDATE_STATE_MISMATCH := "CANDIDATE_STATE_MISMATCH"
const CODE_BAD_TIMESTAMP := "BAD_TIMESTAMP"
const CODE_BAD_CATALOG := "BAD_CATALOG"
const CODE_BAD_FRESH_SEED := "BAD_FRESH_SEED"
const CODE_BAD_INJECTION := "BAD_INJECTION"
const CODE_ALREADY_INSTALLED := "ALREADY_INSTALLED"
const CODE_NOT_INSTALLED := "NOT_INSTALLED"
const CODE_BAD_PAYLOAD := "BAD_PAYLOAD"
const CODE_TMP_WRITE_FAILED := "TMP_WRITE_FAILED"
const CODE_TMP_FLUSH_FAILED := "TMP_FLUSH_FAILED"
const CODE_TMP_VERIFY_FAILED := "TMP_VERIFY_FAILED"
const CODE_BACKUP_FAILED := "BACKUP_FAILED"
const CODE_BACKUP_VERIFY_FAILED := "BACKUP_VERIFY_FAILED"
const CODE_QUARANTINE_FAILED := "QUARANTINE_FAILED"
const CODE_LEGACY_COPY_FAILED := "LEGACY_COPY_FAILED"
const CODE_RENAME_FAILED := "RENAME_FAILED"

const STATUS_MISSING := "missing"
const STATUS_CORRUPT := "corrupt"
const STATUS_V1 := "v1"
const STATUS_V2 := "v2"
const STATUS_NEWER := "newer"


static func _ok() -> Dictionary:
	return {"ok": true, "code": "", "reason": ""}


static func _no(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}


## 已验证 catalog map：species_id -> {id, rarity, catch_weight, base_price, ...}。
static func catalog_valid(catalog: Variant) -> bool:
	if not (catalog is Dictionary):
		return false
	var by_id: Dictionary = catalog
	if by_id.is_empty():
		return false
	for species_id in by_id:
		if not (species_id is String) or String(species_id).is_empty():
			return false
		var entry: Variant = by_id[species_id]
		if not (entry is Dictionary):
			return false
		var e: Dictionary = entry
		if not (e.get("id") is String) or String(e["id"]) != String(species_id):
			return false
		if not (e.get("rarity") is String) or String(e["rarity"]).is_empty():
			return false
		if not _is_positive_finite(e.get("catch_weight")):
			return false
		if not _is_nonneg_int_value(e.get("base_price")):
			return false
	return true


## v2 文档全量语义校验（plan §4.1 十三键 + §4.3 交叉一致性）。fail-closed。
static func validate_v2_document(doc: Variant, catalog: Variant) -> Dictionary:
	if not catalog_valid(catalog):
		return _no(CODE_BAD_CATALOG, "valid_species_by_id missing or invalid")
	if not (doc is Dictionary):
		return _no(CODE_BAD_DOC, "document is not a dictionary")
	var d: Dictionary = doc
	if not _has_exact_keys(d, DOC_KEYS):
		return _no(CODE_BAD_DOC, "v2 top level must have exactly 13 keys")
	if not _is_integral(d["save_version"]) or int(d["save_version"]) != SAVE_VERSION:
		return _no(CODE_BAD_DOC, "save_version must be int 2")
	var core := _validate_core_fields(d, catalog)
	if core["ok"] != true:
		return core
	var ledger_result := _validate_ledger(d["economy_ledger"], d["basket"],
			d["processed_catch_ids"], d["processed_sale_ids"], catalog)
	if ledger_result["ok"] != true:
		return ledger_result
	var rng_result := _validate_rng(d["rng_snapshot"])
	if rng_result["ok"] != true:
		return rng_result
	var clock_result := _validate_clock(d["clock_snapshot"])
	if clock_result["ok"] != true:
		return clock_result
	var candidate: Variant = d["pending_candidate"]
	if candidate == null:
		return _ok()
	var candidate_result := _validate_candidate(candidate, catalog, d["fishing_checkpoint"],
			d["economy_ledger"])
	return candidate_result


## v1 legacy 文档全量语义校验（同形九键；无 ledger/RNG/Clock/候选载体）。
static func validate_v1_document(doc: Variant, catalog: Variant) -> Dictionary:
	if not catalog_valid(catalog):
		return _no(CODE_BAD_CATALOG, "valid_species_by_id missing or invalid")
	if not (doc is Dictionary):
		return _no(CODE_BAD_DOC, "document is not a dictionary")
	var d: Dictionary = doc
	if not _has_exact_keys(d, V1_DOC_KEYS):
		return _no(CODE_BAD_DOC, "v1 top level must have exactly 9 keys")
	if not _is_integral(d["save_version"]) or int(d["save_version"]) != LEGACY_SAVE_VERSION:
		return _no(CODE_BAD_DOC, "save_version must be int 1")
	var core := _validate_core_fields(d, catalog)
	if core["ok"] != true:
		return core
	# v1 无指纹账本：篮中鱼只要求 source_event_id ∈ processed_catch_ids（可证捕获事件存在）；
	# 指纹逐值对账仅在 v2（有 economy_ledger）时强制。
	for element in (d["basket"] as Array):
		if not (d["processed_catch_ids"] as Array).has(String((element as Dictionary)["source_event_id"])):
			return _no(CODE_LEDGER_MISMATCH, "v1 basket fish has no matching processed catch id")
	return _ok()


## v1 → v2「可证安全」迁移判据（plan §4.4）：全部满足才返回 ""（可迁移）。
## 仅在 validate_v1_document 已通过后调用。
static func v1_migration_reject_reason(doc: Dictionary) -> String:
	if not (doc["processed_catch_ids"] as Array).is_empty():
		return "PROCESSED_CATCH_IDS_NOT_EMPTY"
	if not (doc["processed_sale_ids"] as Array).is_empty():
		return "PROCESSED_SALE_IDS_NOT_EMPTY"
	if not (doc["basket"] as Array).is_empty():
		return "BASKET_NOT_EMPTY"
	if String((doc["fishing_checkpoint"] as Dictionary)["state"]) != "IDLE":
		return "FSM_CYCLE_ACTIVE"
	return ""


## 解析后的磁盘文档（JSON.parse_string 结果）分类：missing 由调用方以文件不存在处理；
## 本函数处理已读出内容：corrupt / v1 / v2 / newer。
static func classify_document(parsed: Variant, catalog: Variant) -> Dictionary:
	if not (parsed is Dictionary):
		return {"status": STATUS_CORRUPT, "reason": "document not parseable as object"}
	var d: Dictionary = parsed
	if not d.has("save_version") or not _is_integral(d["save_version"]):
		return {"status": STATUS_CORRUPT, "reason": "save_version missing or not an integer"}
	var version := int(d["save_version"])
	if version > SAVE_VERSION:
		return {"status": STATUS_NEWER, "reason": "save_version %d is from a newer build" % version}
	if version < LEGACY_SAVE_VERSION:
		return {"status": STATUS_CORRUPT, "reason": "save_version %d below known versions" % version}
	var result := validate_v2_document(d, catalog) if version == SAVE_VERSION \
			else validate_v1_document(d, catalog)
	if result["ok"] != true:
		return {"status": STATUS_CORRUPT,
				"reason": "v%d document failed validation: %s (%s)" % [version, String(result["code"]), String(result["reason"])]}
	return {"status": STATUS_V2 if version == SAVE_VERSION else STATUS_V1, "reason": ""}


# ---- 内部：九键公共形状（v1/v2 同形同义）----

static func _validate_core_fields(d: Dictionary, catalog: Dictionary) -> Dictionary:
	if not _is_nonneg_int_value(d["revision"]):
		return _no(CODE_BAD_DOC, "revision must be a non-negative integer")
	if not _is_nonneg_int_value(d["wallet_gold"]):
		return _no(CODE_BAD_DOC, "wallet_gold must be a non-negative integer")
	if not _is_positive_int_value(d["basket_capacity"]):
		return _no(CODE_BAD_DOC, "basket_capacity must be a positive integer")
	var ids_result := _validate_id_array(d["processed_catch_ids"], "processed_catch_ids")
	if not ids_result:
		return _no(CODE_BAD_DOC, "processed_catch_ids must be unique non-empty strings")
	ids_result = _validate_id_array(d["processed_sale_ids"], "processed_sale_ids")
	if not ids_result:
		return _no(CODE_BAD_DOC, "processed_sale_ids must be unique non-empty strings")
	var basket_result := _validate_basket(d["basket"], catalog)
	if basket_result["ok"] != true:
		return basket_result
	if not _validate_checkpoint(d["fishing_checkpoint"]):
		return _no(CODE_BAD_DOC, "fishing_checkpoint malformed (state enum / event / wait / elapsed)")
	if not _validate_window(d["desktop_window"]):
		return _no(CODE_BAD_DOC, "desktop_window malformed (five integer-able keys)")
	return _ok()


static func _validate_basket(basket: Variant, catalog: Dictionary) -> Dictionary:
	if not (basket is Array):
		return _no(CODE_BAD_DOC, "basket must be an array")
	var items: Array = basket
	for element in items:
		if not (element is Dictionary) or not _has_exact_keys(element, FishInstance.SCHEMA_KEYS):
			return _no(CODE_BAD_DOC, "basket fish must have exactly five schema keys")
		var fish: Dictionary = element
		for key in ["instance_id", "species_id", "source_event_id"]:
			if not (fish[key] is String) or String(fish[key]).is_empty():
				return _no(CODE_BAD_DOC, "basket fish %s must be a non-empty string" % key)
		if not FishInstance.timestamp_valid(fish["caught_at_utc"]):
			return _no(CODE_BAD_DOC, "basket fish caught_at_utc is not valid UTC seconds")
		if not FishInstance.price_valid(fish["sale_price_at_catch"]):
			return _no(CODE_BAD_DOC, "basket fish sale_price_at_catch must be a non-negative integer")
		# 篮内鱼种必须属于已验证目录；价格以鱼自身 sale_price_at_catch 为权威（不与目录比）。
		if not catalog.has(String(fish["species_id"])):
			return _no(CODE_UNKNOWN_SPECIES, "basket fish species not in validated catalog")
	var seen_instance: Dictionary = {}
	var seen_source: Dictionary = {}
	for element in items:
		var fish_item: Dictionary = element
		var instance_id := String(fish_item["instance_id"])
		var source_id := String(fish_item["source_event_id"])
		if seen_instance.has(instance_id) or seen_source.has(source_id):
			return _no(CODE_BAD_DOC, "basket instance_id/source_event_id must be unique")
		seen_instance[instance_id] = true
		seen_source[source_id] = true
	return _ok()


static func _validate_checkpoint(checkpoint: Variant) -> bool:
	if not (checkpoint is Dictionary) or not _has_exact_keys(checkpoint, CHECKPOINT_KEYS):
		return false
	var c: Dictionary = checkpoint
	if not (c["state"] is String) or not STATE_NAMES.has(String(c["state"])):
		return false
	if c["event_id"] != null and (not (c["event_id"] is String) or String(c["event_id"]).is_empty()):
		return false
	if c["wait_seconds"] != null and (not _is_numeric(c["wait_seconds"]) or float(c["wait_seconds"]) < 0.0
			or not _is_finite(float(c["wait_seconds"]))):
		return false
	return _is_numeric(c["elapsed_effective_seconds"]) \
			and float(c["elapsed_effective_seconds"]) >= 0.0 \
			and _is_finite(float(c["elapsed_effective_seconds"]))


static func _validate_window(window: Variant) -> bool:
	if not (window is Dictionary) or not _has_exact_keys(window, WINDOW_KEYS):
		return false
	var w: Dictionary = window
	if not _is_integral(w["x"]) or not _is_integral(w["y"]):
		return false
	if not _is_positive_int_value(w["width"]) or not _is_positive_int_value(w["height"]):
		return false
	if w["display_hint"] == null:
		return true
	return _is_nonneg_int_value(w["display_hint"])


# ---- 内部：v2 新增四键 ----

static func _validate_ledger(ledger: Variant, basket: Variant, processed_catches: Variant,
		processed_sales: Variant, catalog: Dictionary) -> Dictionary:
	if not (ledger is Dictionary) or not _has_exact_keys(ledger, LEDGER_KEYS):
		return _no(CODE_BAD_DOC, "economy_ledger must have exactly 2 keys")
	var l: Dictionary = ledger
	if not (l["processed_catches"] is Dictionary) or not (l["processed_sales"] is Dictionary):
		return _no(CODE_BAD_DOC, "economy_ledger sides must be dictionaries")
	if not (basket is Array) or not (processed_catches is Array) or not (processed_sales is Array):
		return _no(CODE_BAD_DOC, "basket/processed id arrays malformed")
	var catch_map: Dictionary = l["processed_catches"]
	var sale_map: Dictionary = l["processed_sales"]
	var catch_ids: Array = processed_catches
	var sale_ids: Array = processed_sales
	var fish_items: Array = basket
	if catch_map.size() != catch_ids.size() or sale_map.size() != sale_ids.size():
		return _no(CODE_LEDGER_MISMATCH, "ledger side sizes differ from processed id arrays")
	for catch_id in catch_map:
		if not (catch_id is String) or String(catch_id).is_empty() or not catch_ids.has(catch_id):
			return _no(CODE_LEDGER_MISMATCH, "catch ledger key not in processed_catch_ids")
		var fp: Variant = catch_map[catch_id]
		if not (fp is Dictionary) or not _has_exact_keys(fp, CATCH_FP_KEYS):
			return _no(CODE_LEDGER_MISMATCH, "catch fingerprint must have exactly 2 keys")
		var fpd: Dictionary = fp
		if not (fpd["species_id"] is String) or String(fpd["species_id"]).is_empty():
			return _no(CODE_LEDGER_MISMATCH, "catch fingerprint species_id invalid")
		if not catalog.has(String(fpd["species_id"])):
			return _no(CODE_UNKNOWN_SPECIES, "catch ledger species not in validated catalog")
		if not FishInstance.timestamp_valid(fpd["caught_at_utc"]):
			return _no(CODE_LEDGER_MISMATCH, "catch fingerprint caught_at_utc not valid UTC")
	for sale_id in sale_map:
		if not (sale_id is String) or String(sale_id).is_empty() or not sale_ids.has(sale_id):
			return _no(CODE_LEDGER_MISMATCH, "sale ledger key not in processed_sale_ids")
		var instances: Variant = sale_map[sale_id]
		if not (instances is Array) or (instances as Array).is_empty():
			return _no(CODE_LEDGER_MISMATCH, "sale fingerprint must be a non-empty array")
		var seen: Dictionary = {}
		for instance_id in (instances as Array):
			if not (instance_id is String) or String(instance_id).is_empty() or seen.has(instance_id):
				return _no(CODE_LEDGER_MISMATCH, "sale fingerprint ids invalid")
			seen[instance_id] = true
			for element in fish_items:
				if String((element as Dictionary)["instance_id"]) == String(instance_id):
					return _no(CODE_LEDGER_MISMATCH, "sold instance still present in basket")
	# 篮中每条鱼：source_event_id 必须在 catch 账本，且指纹与鱼实例逐值一致（捕获指纹可证）。
	for element in fish_items:
		var fish: Dictionary = element
		var source_id := String(fish["source_event_id"])
		if not catch_map.has(source_id):
			return _no(CODE_LEDGER_MISMATCH, "basket fish source_event_id missing from catch ledger")
		var fp: Dictionary = catch_map[source_id]
		if String(fp["species_id"]) != String(fish["species_id"]) \
				or String(fp["caught_at_utc"]) != String(fish["caught_at_utc"]):
			return _no(CODE_LEDGER_MISMATCH, "basket fish does not match its catch fingerprint")
	return _ok()


static func _validate_rng(snapshot: Variant) -> Dictionary:
	if not (snapshot is Dictionary) or not _has_exact_keys(snapshot, RNG_KEYS):
		return _no(CODE_BAD_DOC, "rng_snapshot must have exactly 3 keys")
	var s: Dictionary = snapshot
	if not _is_integral(s["version"]) or int(s["version"]) != SNAPSHOT_VERSION:
		return _no(CODE_BAD_DOC, "rng_snapshot.version must be int 1")
	if not _is_integral(s["seed"]) or int(s["seed"]) < 1 or int(s["seed"]) > RNG_STATE_MAX:
		return _no(CODE_BAD_DOC, "rng_snapshot.seed out of Lehmer range")
	if not _is_integral(s["state"]) or int(s["state"]) < 1 or int(s["state"]) > RNG_STATE_MAX:
		return _no(CODE_BAD_DOC, "rng_snapshot.state out of Lehmer range")
	return _ok()


static func _validate_clock(snapshot: Variant) -> Dictionary:
	if not (snapshot is Dictionary) or not _has_exact_keys(snapshot, CLOCK_KEYS):
		return _no(CODE_BAD_DOC, "clock_snapshot must have exactly 2 keys")
	var s: Dictionary = snapshot
	if not _is_integral(s["version"]) or int(s["version"]) != SNAPSHOT_VERSION:
		return _no(CODE_BAD_DOC, "clock_snapshot.version must be int 1")
	if not _is_numeric(s["now"]) or not _is_finite(float(s["now"])) or float(s["now"]) < 0.0:
		return _no(CODE_BAD_DOC, "clock_snapshot.now must be a finite number >= 0")
	return _ok()


static func _validate_candidate(candidate: Variant, catalog: Dictionary, checkpoint: Variant,
		ledger: Variant) -> Dictionary:
	if not (candidate is Dictionary) or not _has_exact_keys(candidate, CANDIDATE_KEYS):
		return _no(CODE_CANDIDATE_LEDGER_MISMATCH, "pending_candidate must be null or exactly 6 keys")
	var c: Dictionary = candidate
	if not _is_integral(c["version"]) or int(c["version"]) != SNAPSHOT_VERSION:
		return _no(CODE_CANDIDATE_LEDGER_MISMATCH, "pending_candidate.version must be int 1")
	if not (c["catch_event_id"] is String) or String(c["catch_event_id"]).is_empty():
		return _no(CODE_CANDIDATE_LEDGER_MISMATCH, "pending_candidate.catch_event_id invalid")
	if not (c["species_id"] is String) or not catalog.has(String(c["species_id"])):
		return _no(CODE_UNKNOWN_SPECIES, "pending_candidate species not in validated catalog")
	if not _is_numeric(c["caught_at_clock"]) or not _is_finite(float(c["caught_at_clock"])) \
			or float(c["caught_at_clock"]) < 0.0:
		return _no(CODE_CANDIDATE_LEDGER_MISMATCH, "pending_candidate.caught_at_clock invalid")
	if not FishInstance.timestamp_valid(c["caught_at_utc"]):
		return _no(CODE_BAD_TIMESTAMP, "pending_candidate.caught_at_utc is not valid UTC seconds")
	# 候选存在 ⇒ FSM 必在 SETTLEMENT 且 event 一致（plan §4.3）。生命周期位置先于目录
	# 指纹比对：checkpoint 不在 SETTLEMENT 的候选属协议错位，与价格篡改分开归类。
	if not (checkpoint is Dictionary):
		return _no(CODE_CANDIDATE_STATE_MISMATCH, "fishing_checkpoint malformed with candidate present")
	var cp: Dictionary = checkpoint
	if String(cp["state"]) != "SETTLEMENT" or cp["event_id"] != c["catch_event_id"]:
		return _no(CODE_CANDIDATE_STATE_MISMATCH,
				"pending_candidate requires SETTLEMENT checkpoint with matching event_id")
	var snapshot: Variant = c["weight_snapshot"]
	if not (snapshot is Dictionary) or not _has_exact_keys(snapshot, WEIGHT_SNAPSHOT_KEYS):
		return _no(CODE_CANDIDATE_CONFIG_MISMATCH, "pending_candidate.weight_snapshot malformed")
	var s: Dictionary = snapshot
	if not _is_positive_finite(s["catch_weight"]) or not _is_nonneg_int_value(s["base_price"]) \
			or not (s["rarity"] is String) or String(s["rarity"]).is_empty():
		return _no(CODE_CANDIDATE_CONFIG_MISMATCH, "pending_candidate.weight_snapshot values invalid")
	var entry: Dictionary = catalog[String(c["species_id"])]
	if float(s["catch_weight"]) != float(entry["catch_weight"]) \
			or float(s["base_price"]) != float(entry["base_price"]) \
			or String(s["rarity"]) != String(entry["rarity"]):
		return _no(CODE_CANDIDATE_CONFIG_MISMATCH,
				"pending_candidate catalog snapshot differs from validated catalog")
	# 已提交未 ack 的合法窗口：账本指纹 fish 种必须与候选一致（重启后 ALREADY_APPLIED 不放新鱼）。
	if ledger is Dictionary and (ledger as Dictionary).has("processed_catches"):
		var catch_map: Dictionary = (ledger as Dictionary)["processed_catches"]
		if catch_map.has(String(c["catch_event_id"])):
			var fp: Variant = catch_map[String(c["catch_event_id"])]
			if not (fp is Dictionary) or String((fp as Dictionary)["species_id"]) != String(c["species_id"]):
				return _no(CODE_CANDIDATE_LEDGER_MISMATCH,
						"committed catch fingerprint species differs from pending candidate")
	return _ok()


# ---- 通用原语 ----

static func _has_exact_keys(dict: Dictionary, keys: Array) -> bool:
	if dict.size() != keys.size():
		return false
	for key in keys:
		if not dict.has(key):
			return false
	return true


static func _validate_id_array(raw: Variant, _label: String) -> bool:
	if not (raw is Array):
		return false
	var seen: Dictionary = {}
	for element in (raw as Array):
		if not (element is String) or String(element).is_empty() or seen.has(element):
			return false
		seen[element] = true
	return true


static func _is_numeric(value: Variant) -> bool:
	return value is int or value is float


static func _is_finite(value: float) -> bool:
	# 纯运算判有限（对齐 CFG/ECO/FSM 先例）：仅有限数使 v - v == 0。
	return value - value == 0.0


## JSON Schema integer 语义的统一判据。实测（Godot 4.7.2）：JSON.parse_string 把所有 JSON
## 数字（含 2 这类整数值）解析为 float，故磁盘回读文档的整数键必须以本原语判定，不得用 `is int`。
static func _is_integral(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var v := float(value)
		if not _is_finite(v) or absf(v) >= MAX_INT64_FLOAT_EXCLUSIVE:
			return false
		return float(int(v)) == v
	return false


static func _is_nonneg_int_value(value: Variant) -> bool:
	if not _is_integral(value):
		return false
	return float(value) >= 0.0


static func _is_positive_int_value(value: Variant) -> bool:
	if not _is_integral(value):
		return false
	return float(value) >= 1.0


static func _is_positive_finite(value: Variant) -> bool:
	if not _is_numeric(value):
		return false
	var v := float(value)
	return _is_finite(v) and v > 0.0
