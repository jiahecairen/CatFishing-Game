extends SceneTree
# CFG-001 headless 配置校验单测（T-CONF-01 + V01-F01/W03 + SDD-172/175/177）。
# 运行：Godot --headless --path <repo> -s res://tests/unit/test_cfg001_config.gd
#   （由 tests/unit/run_cfg001_checks.py 统一调度；先跑 --editor --quit 导入以刷新全局类缓存。）
# 约定与 CORE-001 冒烟一致：全部通过打印 "CFG001 CONFIG PASS" 且 quit(0)；
# 首个失败打印 "CFG001 CONFIG FAIL: <step>" 且 quit(1)。
# 纯数据层测试：只读 res:// 文件，不写文件、不触碰 user://、不依赖 Node。

const Catalog := preload("res://scripts/config/fish_species_catalog.gd")
const Runtime := preload("res://scripts/config/runtime_config.gd")
const Gate := preload("res://scripts/config/config_gate.gd")

const FIXTURE_DIR := "res://tests/unit/fixtures/cfg001/"

# [文件名, 期望 error_code]；runtime 夹具见 _is_runtime_fixture()。
const CATALOG_FIXTURES := [
	["dup_id.json", "DUP_ID"],
	["zero_weight.json", "BAD_WEIGHT"],
	["neg_weight.json", "BAD_WEIGHT"],
	["neg_price.json", "BAD_PRICE"],
	["bad_id.json", "BAD_ID_PATTERN"],
	["bad_rarity.json", "BAD_RARITY"],
	["missing_field.json", "BAD_SHAPE"],
	["bad_version.json", "BAD_VERSION"],
	["invalid_json.json", "JSON_PARSE"],
	["empty_species.json", "EMPTY_SPECIES"],
]
const RUNTIME_FIXTURES := [
	["min_gt_max.json", "MIN_GT_MAX"],
	["fps_not_30.json", "BAD_FPS"],
]


func _initialize() -> void:
	# ---- 正例 P1：正式鱼种目录合法、恰 3 种、与 examples 逐值一致 ----
	var catalog: Dictionary = Catalog.load_catalog("res://data/fish_species.json")
	if catalog.get("ok", false) != true:
		_fail("P1 catalog ok (code=%s)" % catalog.get("error_code", "?"))
		return
	var species: Array = catalog["species"]
	if species.size() != 3:
		_fail("P1 species must be exactly 3 (V01-F01), got %d" % species.size())
		return
	if _ids_of(species) != ["river_carp", "silver_perch", "golden_trout"]:
		_fail("P1 species ids/order")
		return
	var example_catalog: Variant = _parse_json("res://examples/fish_species.json")
	if example_catalog == null or example_catalog["species"] != species:
		_fail("P1 data/ vs examples/ species not value-identical (R-4)")
		return

	# ---- 正例 P2：正式运行配置合法、逐值=示例、30FPS/20-60s/容量10候选 ----
	var runtime: Dictionary = Runtime.load_config("res://data/runtime_config.json")
	if runtime.get("ok", false) != true:
		_fail("P2 runtime ok (code=%s)" % runtime.get("error_code", "?"))
		return
	var config: Dictionary = runtime["config"]
	var example_runtime: Variant = _parse_json("res://examples/runtime_config.json")
	if example_runtime == null or example_runtime != config:
		_fail("P2 data/ vs examples/ runtime not value-identical (R-4)")
		return
	if int(config["visible_fps"]) != 30 or int(config["bite_wait_min_sec"]) != 20 \
			or int(config["bite_wait_max_sec"]) != 60 or int(config["basket_capacity"]) != 10 \
			or int(config["config_version"]) != 1:
		_fail("P2 runtime literal values 1/30/20/60/10 mismatch")
		return

	# ---- 正例 P3：合法配置放行经济启动，无拒绝原因 ----
	if not Gate.can_start_economy(catalog, runtime):
		_fail("P3 gate must allow valid configs")
		return
	if Gate.blocked_reasons(catalog, runtime).size() != 0:
		_fail("P3 gate blocked_reasons must be empty for valid configs")
		return

	# ---- 反例 N1：全部 catalog 夹具 → ok=false、error_code 精确、零默认值、gate 拒绝 ----
	for row in CATALOG_FIXTURES:
		var path: String = FIXTURE_DIR + String(row[0])
		var bad: Dictionary = Catalog.load_catalog(path)
		if bad.get("ok", true) != false:
			_fail("N1 %s must be rejected" % row[0])
			return
		if bad.get("error_code", "") != row[1]:
			_fail("N1 %s error_code=%s expected=%s" % [row[0], bad.get("error_code", "?"), row[1]])
			return
		if not (bad["species"] is Array) or not (bad["species"] as Array).is_empty():
			_fail("N1 %s must return empty species (no silent defaults)" % row[0])
			return
		if Gate.can_start_economy(bad, runtime):
			_fail("N1 gate must block economy on %s" % row[0])
			return
		if Gate.blocked_reasons(bad, runtime).size() != 1:
			_fail("N1 gate reasons for %s" % row[0])
			return

	# ---- 反例 N2：runtime 夹具 → ok=false、error_code 精确、零默认值、gate 拒绝 ----
	for row in RUNTIME_FIXTURES:
		var path: String = FIXTURE_DIR + String(row[0])
		var bad: Dictionary = Runtime.load_config(path)
		if bad.get("ok", true) != false:
			_fail("N2 %s must be rejected" % row[0])
			return
		if bad.get("error_code", "") != row[1]:
			_fail("N2 %s error_code=%s expected=%s" % [row[0], bad.get("error_code", "?"), row[1]])
			return
		if not (bad["config"] is Dictionary) or not (bad["config"] as Dictionary).is_empty():
			_fail("N2 %s must return empty config (no silent defaults)" % row[0])
			return
		if Gate.can_start_economy(catalog, bad):
			_fail("N2 gate must block economy on %s" % row[0])
			return
		if Gate.blocked_reasons(catalog, bad).size() != 1:
			_fail("N2 gate reasons for %s" % row[0])
			return

	# ---- 反例 N3：文件缺失 → FILE_MISSING（明确失败路径，非崩溃、非默认值） ----
	var missing: Dictionary = Catalog.load_catalog("res://data/no_such_species_cfg001.json")
	if missing.get("ok", true) != false or missing.get("error_code", "") != "FILE_MISSING":
		_fail("N3 catalog missing file must be FILE_MISSING")
		return
	var missing_rt: Dictionary = Runtime.load_config("res://data/no_such_runtime_cfg001.json")
	if missing_rt.get("ok", true) != false or missing_rt.get("error_code", "") != "FILE_MISSING":
		_fail("N3 runtime missing file must be FILE_MISSING")
		return
	if Gate.can_start_economy(missing, missing_rt):
		_fail("N3 gate must block economy on missing configs")
		return

	print("CFG001 CONFIG PASS")
	quit(0)


func _ids_of(species: Array) -> Array:
	var ids := []
	for entry in species:
		ids.append(entry["id"])
	return ids


func _parse_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	if not (json.data is Dictionary):
		return null
	return json.data


func _fail(step: String) -> void:
	print("CFG001 CONFIG FAIL: " + step)
	quit(1)
