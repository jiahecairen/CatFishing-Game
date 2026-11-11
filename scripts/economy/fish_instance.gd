class_name FishInstance
extends RefCounted
# ECO-001：鱼实例静态工厂/校验器（INTERFACES_AND_DATA §2、schemas/game-save.schema.json
# basket.items 五键、2026-11-11 委托裁定 sale_price_at_catch 快照、tasks/evidence/ECO-001/plan.md §3/§4）。
# 合同：
# - make() 产出恰为 schema v1 五键 {instance_id, species_id, caught_at_utc, source_event_id,
#   sale_price_at_catch}，不扩键。
# - instance_id = "fish-" + catch_event_id：每次 catch 事件至多结算 1 条鱼由 EconomyService
#   幂等指纹账本保证 ⇒ instance_id 构造性唯一且跨崩溃可复现（SDD-143/155-156）。
# - sale_price_at_catch 为捕获时刻目录 base_price 的整数快照（≥0），此后目录变化不追溯。
# - caught_at_utc 必须是合法 UTC 秒级时间戳 "YYYY-MM-DDTHH:MM:SSZ"；FSM 虚拟时钟秒不是
#   UTC，绝不把时钟秒伪装成时间戳（ECO-001 review 强制条件 6）。
# 不变量：纯 RefCounted 静态工具——无实例状态、无 Node/_process、不读写 user://、无文件写入。

const SCHEMA_KEYS := ["instance_id", "species_id", "caught_at_utc", "source_event_id", "sale_price_at_catch"]
const ID_PREFIX := "fish-"
const UTC_PATTERN := "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})Z$"
const MAX_INT64_FLOAT_EXCLUSIVE := 9223372036854775808.0


## 由已校验的 catch 事件与目录条目构造鱼实例字典（五键，schema v1）。
## species_entry 已由 FishSpeciesCatalog 校验：id 非空字符串、base_price 为非负整数值。
static func make(catch_event_id: String, species_entry: Dictionary, caught_at_utc: String) -> Dictionary:
	return {
		"instance_id": ID_PREFIX + catch_event_id,
		"species_id": String(species_entry["id"]),
		"caught_at_utc": caught_at_utc,
		"source_event_id": catch_event_id,
		"sale_price_at_catch": int(species_entry["base_price"]),
	}


## 逐字段严格校验（对齐 schema basket.items + $comment 语义检查）。
## 仅当 entry 为恰五键字典、字符串字段非空、时间戳合法、价格为非负整数值时返回 true。
static func validate(entry: Variant) -> bool:
	if not (entry is Dictionary):
		return false
	var e: Dictionary = entry
	if not _has_exact_keys(e, SCHEMA_KEYS):
		return false
	for key in ["instance_id", "species_id", "source_event_id"]:
		if not (e[key] is String) or String(e[key]).is_empty():
			return false
	if not timestamp_valid(e["caught_at_utc"]):
		return false
	return price_valid(e["sale_price_at_catch"])


## UTC 时间戳判合法：秒级 ISO-8601 带 Z 后缀 + 逐字段范围 + 闰年天数校验（fail-closed）。
static func timestamp_valid(value: Variant) -> bool:
	if not (value is String):
		return false
	var text := String(value)
	var utc_regex := RegEx.new()
	if utc_regex.compile(UTC_PATTERN) != OK:
		return false
	var match_result: RegExMatch = utc_regex.search(text)
	if match_result == null or match_result.get_string(0) != text:
		return false
	var year := match_result.get_string(1).to_int()
	var month := match_result.get_string(2).to_int()
	var day := match_result.get_string(3).to_int()
	var hour := match_result.get_string(4).to_int()
	var minute := match_result.get_string(5).to_int()
	var second := match_result.get_string(6).to_int()
	if month < 1 or month > 12:
		return false
	if day < 1 or day > _days_in_month(year, month):
		return false
	return hour <= 23 and minute <= 59 and second <= 59


## 价格判合法：非负整数。int 直接判；float 仅接受有限整数值
## （对齐 CFG-001 JSON 数字双态判例；EconomyService 落盘前恒用 int() 规范化为 int）。
static func price_valid(value: Variant) -> bool:
	if value is int:
		return int(value) >= 0
	if value is float:
		var v := float(value)
		if v - v != 0.0 or v < 0.0 or v >= MAX_INT64_FLOAT_EXCLUSIVE:
			return false
		return float(int(v)) == v
	return false


## 篮元素价格专项判坏（区分稳定码 BAD_PRICE 与 BAD_STATE，plan §4）：
## 仅当元素恰为五键、其余字段全部合法、唯价格非非负整数值时为 true；其余畸形归 BAD_STATE。
static func price_invalid(entry: Variant) -> bool:
	if not (entry is Dictionary):
		return false
	var e: Dictionary = entry
	if not _has_exact_keys(e, SCHEMA_KEYS):
		return false
	for key in ["instance_id", "species_id", "source_event_id"]:
		if not (e[key] is String) or String(e[key]).is_empty():
			return false
	if not timestamp_valid(e["caught_at_utc"]):
		return false
	return not price_valid(e["sale_price_at_catch"])


static func _days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
				return 29
			return 28
	return 0


static func _has_exact_keys(dict: Dictionary, keys: Array) -> bool:
	if dict.size() != keys.size():
		return false
	for key in keys:
		if not dict.has(key):
			return false
	return true
