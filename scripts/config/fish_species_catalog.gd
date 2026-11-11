class_name FishSpeciesCatalog
extends RefCounted
# CFG-001：鱼种目录（data/fish_species.json）纯数据校验器，可 headless 测试。
# 契约来源：docs/INTERFACES_AND_DATA.md §1、schemas/fish-species.schema.json、
# tasks/evidence/CFG-001/plan.md §4。
# 不变量：
# - 纯 RefCounted 数据层：不依赖 Node/场景树，不读写 user://，不产生任何文件写入。
# - 失败路径零默认值：ok=false 时 species 恒为空数组，绝不回填任何"看起来能跑"的值。
# - 首个失败即返回稳定 error_code，不静默兼容未来版本、不吞错。
# 注意：class_name 避开已被 scripts/io/config_loader.gd 骨架占用的 ConfigLoader。

const ERROR_FILE_MISSING := "FILE_MISSING"
const ERROR_FILE_OPEN := "FILE_OPEN"
const ERROR_JSON_PARSE := "JSON_PARSE"
const ERROR_BAD_VERSION := "BAD_VERSION"
const ERROR_BAD_SHAPE := "BAD_SHAPE"
const ERROR_EMPTY_SPECIES := "EMPTY_SPECIES"
const ERROR_BAD_ID_PATTERN := "BAD_ID_PATTERN"
const ERROR_DUP_ID := "DUP_ID"
const ERROR_BAD_RARITY := "BAD_RARITY"
const ERROR_BAD_WEIGHT := "BAD_WEIGHT"
const ERROR_BAD_PRICE := "BAD_PRICE"
const ERROR_BAD_ASSET := "BAD_ASSET"

const CATALOG_VERSION := 1
const ROOT_KEYS := ["catalog_version", "species"]
const SPECIES_KEYS := ["id", "name_zh", "rarity", "catch_weight", "base_price", "asset_key"]
const RARITIES := ["common", "uncommon", "rare"]
const ID_PATTERN := "^[a-z][a-z0-9_]*$"


## 校验目录文件。返回 {ok: bool, error_code: String, species: Array}。
## ok=false 时 species == []（零默认值），error_code 为上面 ERROR_* 稳定常量之一。
static func load_catalog(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail(ERROR_FILE_MISSING)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail(ERROR_FILE_OPEN)
	var text := file.get_as_text()
	file = null
	if text.is_empty():
		return _fail(ERROR_JSON_PARSE)
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail(ERROR_JSON_PARSE)
	var root: Variant = json.data
	if not (root is Dictionary):
		return _fail(ERROR_JSON_PARSE)

	# 形状：仅允许 catalog_version、species 两键（对齐 schema additionalProperties:false）。
	if not _has_exact_keys(root, ROOT_KEYS):
		return _fail(ERROR_BAD_SHAPE)
	# 版本：必须恰为 1，不静默兼容未来版本。
	if not _is_integral(root["catalog_version"]) or int(root["catalog_version"]) != CATALOG_VERSION:
		return _fail(ERROR_BAD_VERSION)
	var raw_species: Variant = root["species"]
	if not (raw_species is Array):
		return _fail(ERROR_BAD_SHAPE)
	var species: Array = raw_species
	if species.is_empty():
		return _fail(ERROR_EMPTY_SPECIES)

	var id_regex := RegEx.new()
	if id_regex.compile(ID_PATTERN) != OK:
		# 常量模式编译失败属实现内部错误，同样走稳定失败路径，绝不放行。
		return _fail(ERROR_BAD_SHAPE)

	# 第一遍：逐元素字段校验（对齐 schema items 约束）。
	for element in species:
		if not (element is Dictionary):
			return _fail(ERROR_BAD_SHAPE)
		var entry: Dictionary = element
		if not _has_exact_keys(entry, SPECIES_KEYS):
			return _fail(ERROR_BAD_SHAPE)
		var raw_id: Variant = entry["id"]
		if not (raw_id is String) or not _full_id_match(id_regex, raw_id):
			return _fail(ERROR_BAD_ID_PATTERN)
		var raw_name: Variant = entry["name_zh"]
		if not (raw_name is String) or (raw_name as String).is_empty():
			return _fail(ERROR_BAD_SHAPE)
		if not RARITIES.has(entry["rarity"]):
			return _fail(ERROR_BAD_RARITY)
		if not _is_positive_number(entry["catch_weight"]):
			return _fail(ERROR_BAD_WEIGHT)
		if not _is_nonnegative_int(entry["base_price"]):
			return _fail(ERROR_BAD_PRICE)
		var raw_asset: Variant = entry["asset_key"]
		if not (raw_asset is String) or (raw_asset as String).is_empty():
			return _fail(ERROR_BAD_ASSET)

	# 第二遍：ID 去重（schema $comment 明示须由配置加载层显式校验）。
	var seen := {}
	for element in species:
		var sid: String = element["id"]
		if seen.has(sid):
			return _fail(ERROR_DUP_ID)
		seen[sid] = true

	return {"ok": true, "error_code": "", "species": species.duplicate(true)}


static func _fail(error_code: String) -> Dictionary:
	return {"ok": false, "error_code": error_code, "species": []}


static func _has_exact_keys(dict: Dictionary, keys: Array) -> bool:
	if dict.size() != keys.size():
		return false
	for key in keys:
		if not dict.has(key):
			return false
	return true


static func _full_id_match(id_regex: RegEx, value: String) -> bool:
	if value.is_empty():
		return false
	var match_result: RegExMatch = id_regex.search(value)
	return match_result != null and match_result.get_string(0) == value


static func _is_finite_float(value: float) -> bool:
	# 纯运算实现（静态函数内不依赖全局数学内建）：仅有限数使 v - v == 0。
	return value - value == 0.0


static func _is_integral(value: Variant) -> bool:
	# Godot JSON 数字可能按 int 或 float 落地，双态判断（plan §6 R-2）。
	if value is int:
		return true
	if value is float:
		var v := float(value)
		return _is_finite_float(v) and float(int(v)) == v
	return false


static func _is_nonnegative_int(value: Variant) -> bool:
	return _is_integral(value) and float(value) >= 0.0


static func _is_positive_number(value: Variant) -> bool:
	if value is int:
		return int(value) > 0
	if value is float:
		var v := float(value)
		return _is_finite_float(v) and v > 0.0
	return false
