extends SceneTree
# SAVE-001 headless 存档原子提交/加载/迁移/故障注入单测（plan.md §5 S0–S8、review 强制
# 条件 #1–#10、T-SAVE-01/02/03、V01-S01/S02、INTERFACES §6/§8）。
# 运行：由 tests/unit/run_save001_checks.py 在隔离临时副本内统一调度（禁止直接对主工程跑
# Godot）。约定与 CORE/CFG/FSM/ECO-001 一致：全部通过打印 "SAVE001 SAVE PASS" 且 quit(0)；
# 首个失败打印 "SAVE001 SAVE FAIL: <step>" 且 quit(1)。
# 写盘隔离：全部提交只写 OS.get_temp_dir() 下本测试专属目录（configure_dir 显式注入），
# 绝不触碰真实 user://；每个场景独立新目录，结束统一递归清理。
const SaveScript := preload("res://scripts/save/save_service.gd")
const ValidateScript := preload("res://scripts/save/save_validate.gd")
const FaultsScript := preload("res://scripts/save/save_faults.gd")
const EcoScript := preload("res://scripts/economy/economy_service.gd")
const FishScript := preload("res://scripts/economy/fish_instance.gd")
const FsmScript := preload("res://scripts/fishing/fishing_state_machine.gd")
const RngScript := preload("res://scripts/fishing/deterministic_rng.gd")
const ClockScript := preload("res://scripts/fishing/virtual_clock.gd")
const CatalogScript := preload("res://scripts/config/fish_species_catalog.gd")
const RuntimeScript := preload("res://scripts/config/runtime_config.gd")
const EXAMPLE_V1 := "res://examples/save_v01.json"
var _catalog: Dictionary
var _runtime: Dictionary
var _species: Dictionary = {}
var _dir_seq := 0
var _dirs: Array = []
func _initialize() -> void:
	_catalog = CatalogScript.load_catalog("res://data/fish_species.json")
	_runtime = RuntimeScript.load_config("res://data/runtime_config.json")
	if _catalog.get("ok", false) != true or _runtime.get("ok", false) != true:
		_fail_ret("R0 base configs invalid (CFG-001 validators must pass first)")
		return
	for entry in (_catalog["species"] as Array):
		_species[String((entry as Dictionary)["id"])] = (entry as Dictionary).duplicate(true)
	for step in [_s0, _s1, _s2, _s3, _s4, _s5, _s6, _s7, _s8]:
		if not step.call():
			_cleanup_dirs()
			return
	_cleanup_dirs()
	print("SAVE001 SAVE PASS"); quit(0)
# ---- S0：装配门 + 校验器 fail-closed + 默认文档提交（plan §4.5 / T-SAVE-01 前置）----
func _s0() -> bool:
	var faults = FaultsScript.new()
	if not _check(_faults_all_disarmed(faults)
			and String((faults.set_armed("bogus", true))["code"]) == "BAD_STAGE",
			"S0 faults: unknown stage must be BAD_STAGE; defaults disarmed"):
		return false
	if not _check(not ValidateScript.catalog_valid({}) and not ValidateScript.catalog_valid(null)
			and not ValidateScript.catalog_valid({"x": {"id": "y"}}) and ValidateScript.catalog_valid(_species),
			"S0 catalog_valid gate"):
		return false
	var base_doc := _manual_doc(0)
	for bad in ["not-a-dict", 42, null, base_doc.duplicate(true)]:
		if bad is Dictionary:
			(bad as Dictionary).erase("clock_snapshot")
		if not _check(String((ValidateScript.validate_v2_document(bad, _species) as Dictionary)["code"]) == "BAD_DOC",
				"S0 BAD_DOC fail-closed for type %d" % typeof(bad)):
			return false
	var dir_path := _fresh_dir("s0")
	var raw: AtomicSaveService = SaveScript.new()
	if not _check((raw.configure_dir(dir_path) as Dictionary).get("ok") == true
			and (raw.configure_dir("") as Dictionary)["code"] == "BAD_PAYLOAD", "S0 configure_dir"):
		return false
	if not _check(String((raw.atomic_commit(_manual_doc(1)))["code"]) == "NOT_INSTALLED",
			"S0 commit before install must reject NOT_INSTALLED"):
		return false
	if not _check(String((raw.install_into(null, null, null, null, null, _species))["code"]) == "BAD_INJECTION"
			and String((raw.install_into(EcoScript.new(), GameState.new(), RngScript.new(),
			ClockScript.new(), FsmScript.new(), {}))["code"]) == "BAD_CATALOG",
			"S0 install_into fail-closed (null service / empty catalog)"):
		return false
	var eco: EconomyService = EcoScript.new()
	if eco.initialize(_catalog, _runtime).get("ok") != true:
		return _fail_ret("S0 eco init")
	var rng: DeterministicRng = RngScript.new()
	(rng.set_seed(991) as Dictionary)
	var clock: VirtualClock = ClockScript.new()
	var fsm: FishingStateMachine = FsmScript.new()
	(fsm.initialize(_catalog, _runtime, rng, clock, {}) as Dictionary)
	var state := GameState.new()
	if not _check((raw.install_into(eco, state, rng, clock, fsm, _species) as Dictionary).get("ok") == true,
			"S0 install_into"):
		return false
	var doc: Variant = raw.persist_runtime_checkpoint()
	var main := dir_path + "game_state.json"
	if not _check(doc.get("ok") == true and FileAccess.file_exists(main), "S0 default checkpoint commit"):
		return false
	var written: Variant = JSON.parse_string(_read_text(main))
	if not _check(written is Dictionary and (written as Dictionary).size() == 13
			and int(written["save_version"]) == 2 and int(written["revision"]) == 1
			and int((written["rng_snapshot"] as Dictionary)["seed"]) == 991
			and int(state.save_version) == 2 and int(state.revision) == 1
			and String((state.fishing_checkpoint as Dictionary)["state"]) == "IDLE",
			"S0 disk doc 13 keys/v2/rev1 and published GameState"):
		return false
	var before_bytes := _read_bytes(main)
	if not _check(String((raw.install_into(eco, state, rng, clock, fsm, _species))["code"]) == "ALREADY_INSTALLED",
			"S0 re-install must reject"):
		return false
	var bad_doc := _manual_doc(9); bad_doc["wallet_gold"] = -5
	if not _check(String((raw.atomic_commit(bad_doc))["code"]) == "BAD_DOC" and _read_bytes(main) == before_bytes
			and _files(dir_path) == ["game_state.json"], "S0 BAD_DOC zero file writes"):
		return false
	return _check(String((raw.set_fault_injection("bogus_stage", true))["code"]) == "BAD_STAGE",
			"S0 fault seam rejects unknown stage")
# ---- S1：全周期跨崩溃 13 键逐值等价 + 重复加载字节一致（T-SAVE-02）----
func _s1() -> bool:
	var dir_path := _fresh_dir("s1")
	var parts := _services(dir_path, 1234)
	var fsm = parts["fsm"]; var eco = parts["eco"]; var state = parts["state"]; var svc = parts["save"]
	var utc := _utc(9)
	if not _check((fsm.request_cast(state) as Dictionary).get("ok") == true
			and (svc.persist_runtime_checkpoint() as Dictionary).get("ok") == true, "S1 cast + CASTING checkpoint"):
		return false
	fsm.tick_effective(5.0)
	if not _check(String((fsm.snapshot_checkpoint() as Dictionary)["state"]) == "WAITING"
			and (svc.persist_runtime_checkpoint() as Dictionary).get("ok") == true, "S1 WAITING checkpoint commit"):
		return false
	fsm.tick_effective(200.0); fsm.tick_effective(1.0); fsm.tick_effective(1.0)
	var cand: Variant = fsm.produce_catch_candidate()
	if not _check((svc.set_pending_candidate(cand, utc) as Dictionary).get("ok") == true
			and (eco.commit_catch(state, String(cand["catch_event_id"]), String(cand["species_id"]), utc) as Dictionary).get("ok") == true,
			"S1 candidate + catch commit via gate"):
		return false
	if not _check((fsm.ack_settlement(String(cand["catch_event_id"]), true) as Dictionary).get("ok") == true
			and (svc.clear_pending_candidate() as Dictionary).get("ok") == true
			and (svc.persist_runtime_checkpoint() as Dictionary).get("ok") == true,
			"S1 ack + clear + checkpoint commit"):
		return false
	var instance_id := "fish-" + String(cand["catch_event_id"])
	if not _check((eco.sell_fish(state, "sale-s1", [instance_id]) as Dictionary).get("ok") == true,
			"S1 sale via gate"):
		return false
	var main := dir_path + "game_state.json"; var want_bytes := _read_bytes(main)
	# —— 崩溃：全部服务换新实例，仅以磁盘存档重建 ——
	var crash := _crash_services(dir_path, 777)
	if not _check(not crash.is_empty(), "S1 crash setup"):
		return false
	var svc2 = crash["save"]; var eco2 = crash["eco"]
	var res: Variant = svc2.load_save(_species, 777)
	if not _check(res.get("ok") == true and res["state"] != null and String(res["code"]) == "",
			"S1 load_save must adopt validated v2 main: %s" % str(res)):
		return false
	var state2: GameState = res["state"]  # 权威 = load_save 返回的载入副本（plan §4.5）
	if not _check((eco2.restore_ledger(state2, res["ledger"]) as Dictionary).get("ok") == true,
			"S1 restore_ledger after crash"):
		return false
	var rng2 = crash["rng"]; var clock2 = crash["clock"]; var fsm2 = crash["fsm"]
	if not _check((rng2.restore_state(res["rng_snapshot"]) as Dictionary).get("ok") == true
			and (clock2.restore_state(res["clock_snapshot"]) as Dictionary).get("ok") == true
			and (fsm2.initialize(_catalog, _runtime, rng2, clock2,
			(state2.fishing_checkpoint as Dictionary).duplicate(true)) as Dictionary).get("ok") == true,
			"S1 rng/clock/fsm restore from save"):
		return false
	if not _check(_deep_eq(state2.basket, state.basket)
			and _deep_eq(state2.processed_catch_ids, state.processed_catch_ids)
			and _deep_eq(state2.processed_sale_ids, state.processed_sale_ids)
			and int(state2.wallet_gold) == int(state.wallet_gold) and int(state2.wallet_gold) > 0
			and int(state2.revision) == int(state.revision) and int(state2.save_version) == 2
			and _deep_eq(fsm2.snapshot_checkpoint(), fsm.snapshot_checkpoint())
			and _deep_eq(eco2.snapshot_ledger(), eco.snapshot_ledger())
			and _deep_eq(crash["rng"].snapshot_state(), res["rng_snapshot"])
			and _deep_eq(crash["clock"].snapshot_state(), res["clock_snapshot"])
			and res["pending_candidate"] == null,
			"S1 all 13 keys survive crash with identical values (T-SAVE-02)"):
		return false
	var res2: Variant = svc2.load_save(_species, 777)
	if not _check(JSON.stringify((res2["report"] as Dictionary)["document"]).to_utf8_buffer() == want_bytes,
			"S1 repeated load must yield identical JSON bytes"):
		return false
	return _check(not _has_tmp_residue(dir_path), "S1 no temp residue")
# ---- S2：故障注入矩阵（6 点）+ 失败零残留 + 失败零发布 + 重试成功（plan §4.2/§4.5）----
func _s2() -> bool:
	var dir_path := _fresh_dir("s2a")
	var parts := _services(dir_path, 4242)
	var svc = parts["save"]; var state = parts["state"]; var fsm = parts["fsm"]; var rng = parts["rng"]
	if not _check((svc.atomic_commit(_manual_doc(1)) as Dictionary).get("ok") == true
			and (svc.atomic_commit(_manual_doc(2)) as Dictionary).get("ok") == true, "S2 seed main+backup"):
		return false
	var main := dir_path + "game_state.json"; var bak := dir_path + "game_state.json.bak"
	var main_bytes := _read_bytes(main); var bak_bytes := _read_bytes(bak)
	var codes := {"tmp_write": "TMP_WRITE_FAILED", "tmp_flush": "TMP_FLUSH_FAILED",
			"backup": "BACKUP_FAILED", "rename": "RENAME_FAILED"}
	for stage in ["tmp_write", "tmp_flush", "backup", "rename"]:
		if not _check((svc.set_fault_injection(stage, true) as Dictionary).get("ok") == true, "S2 arm %s" % stage):
			return false
		var state_before := _state_snapshot(state)
		var fsm_before: Variant = fsm.snapshot_checkpoint()
		var rng_before := int(rng.get_state())
		var failed: Variant = svc.persist_runtime_checkpoint()
		if not _check(failed.get("ok") == false and String(failed["code"]) == String(codes[stage]),
				"S2 %s must fail with %s: %s" % [stage, String(codes[stage]), str(failed)]):
			return false
		if not _check(_read_bytes(main) == main_bytes and _read_bytes(bak) == bak_bytes
				and _files(dir_path) == ["game_state.json", "game_state.json.bak"],
				"S2 %s must leave main/.bak bytes + file set unchanged" % stage):
			return false
		if not _check(_deep_eq(state_before, _state_snapshot(state)) and _deep_eq(fsm_before, fsm.snapshot_checkpoint())
				and int(rng.get_state()) == rng_before and int(state.wallet_gold) == 0,
				"S2 %s must publish nothing on failure (state/checkpoint/rng untouched)" % stage):
			return false
		if not _check((svc.set_fault_injection(stage, false) as Dictionary).get("ok") == true
				and (svc.persist_runtime_checkpoint() as Dictionary).get("ok") == true
				and not _has_tmp_residue(dir_path),
				"S2 %s retry after disarm must succeed without residue" % stage):
			return false
		main_bytes = _read_bytes(main); bak_bytes = _read_bytes(bak)
	# quarantine 注入：坏 main + 好 bak（review #9 注入路径）
	var dir_b := _fresh_dir("s2b")
	var parts_b := _services(dir_b, 4242); var svc_b = parts_b["save"]
	if not _check((svc_b.atomic_commit(_manual_doc(1)) as Dictionary).get("ok") == true
			and (svc_b.atomic_commit(_manual_doc(2)) as Dictionary).get("ok") == true, "S2b seed main+backup"):
		return false
	var corrupt_text := "{{{ not json at all !!!"
	_write_text(dir_b + "game_state.json", corrupt_text)
	var corrupt_bytes := _read_bytes(dir_b + "game_state.json")
	var bak_b_bytes := _read_bytes(dir_b + "game_state.json.bak")
	if not _check((svc_b.set_fault_injection("quarantine", true) as Dictionary).get("ok") == true
			and String((svc_b.persist_runtime_checkpoint() as Dictionary)["code"]) == "QUARANTINE_FAILED"
			and _read_bytes(dir_b + "game_state.json") == corrupt_bytes
			and _read_bytes(dir_b + "game_state.json.bak") == bak_b_bytes
			and not _has_tmp_residue(dir_b), "S2b quarantine fault keeps corrupt main + good bak bytes"):
		return false
	var rescue: Variant = svc_b.load_save(_species, 5)
	if not _check(rescue.get("ok") == true and String(rescue["code"]) == "RECOVERED_FROM_BACKUP",
			"S2b .bak must stay loadable while quarantine faulted"):
		return false
	if not _check((svc_b.set_fault_injection("quarantine", false) as Dictionary).get("ok") == true
			and (svc_b.persist_runtime_checkpoint() as Dictionary).get("ok") == true,
			"S2b quarantine retry must succeed"):
		return false
	var quarantined := dir_b + "game_state.corrupt.1.json"
	if not _check(FileAccess.file_exists(quarantined) and _read_bytes(quarantined) == corrupt_bytes
			and _read_bytes(dir_b + "game_state.json") != corrupt_bytes and not _has_tmp_residue(dir_b),
			"S2b successful commit quarantines corrupt original as corrupt.1.json (copy, not move)"):
		return false
	# rename 注入：坏 main + 好 bak —— 两文件都保留、.bak 仍可恢复
	var dir_c := _fresh_dir("s2c")
	var parts_c := _services(dir_c, 4242); var svc_c = parts_c["save"]
	if not _check((svc_c.atomic_commit(_manual_doc(1)) as Dictionary).get("ok") == true
			and (svc_c.atomic_commit(_manual_doc(2)) as Dictionary).get("ok") == true, "S2c seed main+backup"):
		return false
	_write_text(dir_c + "game_state.json", "###broken###")
	var c_main_bytes := _read_bytes(dir_c + "game_state.json"); var c_bak_bytes := _read_bytes(dir_c + "game_state.json.bak")
	if not _check((svc_c.set_fault_injection("rename", true) as Dictionary).get("ok") == true
			and String((svc_c.persist_runtime_checkpoint() as Dictionary)["code"]) == "RENAME_FAILED"
			and _read_bytes(dir_c + "game_state.json") == c_main_bytes
			and _read_bytes(dir_c + "game_state.json.bak") == c_bak_bytes
			and not _has_tmp_residue(dir_c), "S2c rename fault keeps both corrupt main and good .bak"):
		return false
	var rescue_c: Variant = svc_c.load_save(_species, 5)
	return _check(rescue_c.get("ok") == true and String(rescue_c["code"]) == "RECOVERED_FROM_BACKUP",
			"S2c .bak stays recoverable after rename fault")
# ---- S3：版本分类 / 坏档保留 / NO_VALID_SAVE（T-SAVE-03、review #2/#9）----
func _s3() -> bool:
	var dir_path := _fresh_dir("s3")
	var parts := _services(dir_path, 1); var svc = parts["save"]
	var main := dir_path + "game_state.json"
	_write_text(main, JSON.stringify({"save_version": 99, "revision": 0}))
	var newer_bytes := _read_bytes(main)
	var res: Variant = svc.load_save(_species, 3)
	if not _check(res.get("ok") == false and String(res["code"]) == "VERSION_NEWER"
			and _read_bytes(main) == newer_bytes and _files(dir_path) == ["game_state.json"]
			and String((svc.atomic_commit(_manual_doc(1)) as Dictionary)["code"]) == "VERSION_NEWER"
			and _read_bytes(main) == newer_bytes and _files(dir_path) == ["game_state.json"],
			"S3 v99 main: load and commit both refuse VERSION_NEWER with zero writes"):
		return false
	_write_text(main, "@@garbage@@")
	var bad_bytes := _read_bytes(main)
	res = svc.load_save(_species, 3)
	if not _check(res.get("ok") == false and String(res["code"]) == "MAIN_CORRUPT" and _read_bytes(main) == bad_bytes,
			"S3 corrupt main + missing bak -> MAIN_CORRUPT, original retained: %s" % str(res)):
		return false
	_write_text(dir_path + "game_state.json.bak", "@@also broken@@")
	res = svc.load_save(_species, 3)
	if not _check(res.get("ok") == false and String(res["code"]) == "NO_VALID_SAVE"
			and _files(dir_path) == ["game_state.json", "game_state.json.bak"],
			"S3 both unusable -> NO_VALID_SAVE, all originals retained"):
		return false
	# 好 bak + 半写坏 main（T-SAVE-02）：恢复 + 惰隔离字节一致 + 保留到下次成功提交
	var good := _manual_doc(7)
	_write_text(dir_path + "game_state.json.bak", JSON.stringify(good))
	res = svc.load_save(_species, 3)
	if not _check(res.get("ok") == true and String(res["code"]) == "RECOVERED_FROM_BACKUP"
			and String((res["report"] as Dictionary)["main_status"]) == "corrupt"
			and FileAccess.file_exists(main) and _read_bytes(main) == bad_bytes,
			"S3 corrupt+bak -> RECOVERED_FROM_BACKUP with corrupt main retained until next commit"):
		return false
	if not _check((svc.persist_runtime_checkpoint() as Dictionary).get("ok") == true
			and FileAccess.file_exists(dir_path + "game_state.corrupt.1.json")
			and _read_bytes(dir_path + "game_state.corrupt.1.json") == bad_bytes
			and not _has_tmp_residue(dir_path),
			"S3 next successful commit quarantines corrupt original byte-identically"):
		return false
	# 半写 main（截断 JSON）+ 重新放置好 bak：同一恢复路径
	var raw := _read_text(main)
	_write_text(dir_path + "game_state.json.bak", JSON.stringify(good))
	_write_text(main, raw.substr(0, int(raw.length() / 2.0)))
	res = svc.load_save(_species, 3)
	return _check(res.get("ok") == true and String(res["code"]) == "RECOVERED_FROM_BACKUP",
			"S3 truncated main recovers from .bak")
# ---- S4：v1 迁移（examples 安全迁移 / 不安全拒绝零写入 / 坏 v1 归 corrupt）----
func _s4() -> bool:
	var example_text := FileAccess.get_file_as_string(EXAMPLE_V1)
	var example: Variant = JSON.parse_string(example_text)
	if not _check(example is Dictionary and int(example["save_version"]) == 1, "S4 examples/save_v01.json stays v1"):
		return false
	var dir_path := _fresh_dir("s4")
	var parts := _services(dir_path, 1); var svc = parts["save"]
	var main := dir_path + "game_state.json"
	_write_text(main, example_text)
	var v1_bytes := _read_bytes(main)
	var res: Variant = svc.load_save(_species, 7)
	if not _check(res.get("ok") == true and String(res["code"]) == "MIGRATED_V1",
			"S4 safe v1 must migrate: %s" % str(res)):
		return false
	var doc: Variant = (res["report"] as Dictionary)["document"]
	if not _check((doc as Dictionary).size() == 13 and int(doc["wallet_gold"]) == int(example["wallet_gold"])
			and int(doc["revision"]) == int(example["revision"])
			and _deep_eq(doc["desktop_window"], example["desktop_window"])
			and _deep_eq(doc["fishing_checkpoint"], example["fishing_checkpoint"])
			and (doc["basket"] as Array).is_empty() and (doc["processed_catch_ids"] as Array).is_empty()
			and (doc["processed_sale_ids"] as Array).is_empty()
			and _deep_eq(doc["economy_ledger"], {"processed_catches": {}, "processed_sales": {}})
			and _deep_eq(doc["rng_snapshot"], {"version": 1, "seed": 7, "state": 7})
			and _deep_eq(doc["clock_snapshot"], {"version": 1, "now": 0.0})
			and doc["pending_candidate"] == null,
			"S4 migrated doc: 13 keys, empty ledger, fresh rng seed note, clock 0, candidate null"):
		return false
	if not _check(_read_bytes(main) == v1_bytes and _files(dir_path) == ["game_state.json"],
			"S4 migration must be pure in-memory (zero writes until next commit)"):
		return false
	var unsafe_ids: Variant = (example as Dictionary).duplicate(true)
	unsafe_ids["processed_catch_ids"] = ["catch-old"]
	_write_text(main, JSON.stringify(unsafe_ids))
	res = svc.load_save(_species, 7)
	if not _check(res.get("ok") == false and String(res["code"]) == "VERSION_LEGACY_UNSAFE"
			and String((res["report"] as Dictionary)["migration_reason"]) == "PROCESSED_CATCH_IDS_NOT_EMPTY"
			and _files(dir_path) == ["game_state.json"],
			"S4 v1 with processed ids -> VERSION_LEGACY_UNSAFE, original retained"):
		return false
	var unsafe_active: Variant = (example as Dictionary).duplicate(true)
	unsafe_active["fishing_checkpoint"] = {"state": "WAITING", "event_id": "catch-old", "wait_seconds": 30,
			"elapsed_effective_seconds": 3.0}
	_write_text(main, JSON.stringify(unsafe_active))
	res = svc.load_save(_species, 7)
	if not _check(res.get("ok") == false and String(res["code"]) == "VERSION_LEGACY_UNSAFE"
			and String((res["report"] as Dictionary)["migration_reason"]) == "FSM_CYCLE_ACTIVE",
			"S4 v1 with active cycle -> VERSION_LEGACY_UNSAFE (no silent mid-cycle upgrade)"):
		return false
	_write_text(main, JSON.stringify({"save_version": 1, "revision": -2}))
	res = svc.load_save(_species, 7)
	if not _check(res.get("ok") == false and String(res["code"]) == "MAIN_CORRUPT",
			"S4 malformed v1 shape classifies as corrupt, not migration"):
		return false
	# 迁移后首次成功提交才落 v2 + legacy 惰隔离（copy-before-rewrite）
	_write_text(main, example_text)
	res = svc.load_save(_species, 9)
	if not _check(res.get("ok") == true and String(res["code"]) == "MIGRATED_V1"
			and int((res["state"] as GameState).save_version) == 1,
			"S4 migrated state stays save_version 1 until first successful commit"):
		return false
	if not _check((svc.persist_runtime_checkpoint() as Dictionary).get("ok") == true
			and int(svc.export_document()["save_version"]) == 2,
			"S4 first commit after migration writes v2"):
		return false
	return _check(FileAccess.file_exists(dir_path + "game_state.legacy.1.json")
			and _read_bytes(dir_path + "game_state.legacy.1.json") == v1_bytes
			and _read_bytes(dir_path + "game_state.json.bak") == v1_bytes,
			"S4 legacy v1 original archived byte-identically and backed up before rewrite")
# ---- S5：跨服务崩溃重放（commit 成功未 ack / sale 重试 / BAD_LEDGER 后仍幂等）----
func _s5() -> bool:
	var dir_path := _fresh_dir("s5")
	var parts := _services(dir_path, 8080)
	var fsm = parts["fsm"]; var eco = parts["eco"]; var state = parts["state"]; var svc = parts["save"]
	var utc := _utc(3)
	# 崩溃点 1：eco.commit_catch 经门成功（已 rename），进程在 ack/clear 前崩溃
	var cand := _cycle_to_settlement(fsm, state, svc, utc)
	if not _check(not cand.is_empty(), "S5 catch to settlement"):
		return false
	if not _check((eco.commit_catch(state, String(cand["catch_event_id"]), String(cand["species_id"]), utc) as Dictionary).get("ok") == true,
			"S5 catch committed through gate before crash"):
		return false
	var crash := _crash_services(dir_path, 8080)
	var eco2 = crash["eco"]; var svc2 = crash["save"]; var fsm2 = crash["fsm"]
	var res: Variant = svc2.load_save(_species, 8080)
	if not _check(res.get("ok") == true and res["pending_candidate"] != null
			and int((res["pending_candidate"] as Dictionary)["version"]) == 1,
			"S5 pending_candidate must survive crash window: %s" % str(res)):
		return false
	var state2: GameState = res["state"]  # 权威 = 载入副本（plan §4.5）
	if not _check((eco2.restore_ledger(state2, res["ledger"]) as Dictionary).get("ok") == true
			and (crash["rng"].restore_state(res["rng_snapshot"]) as Dictionary).get("ok") == true
			and (crash["clock"].restore_state(res["clock_snapshot"]) as Dictionary).get("ok") == true
			and (fsm2.initialize(_catalog, _runtime, crash["rng"], crash["clock"],
			(state2.fishing_checkpoint as Dictionary).duplicate(true)) as Dictionary).get("ok") == true
			and String(fsm2.get_event_id()) == String(cand["catch_event_id"]),
			"S5 restart restore chain (SETTLEMENT event replayed, not re-sampled)"):
		return false
	if not _check((svc2.install_into(eco2, state2, crash["rng"], crash["clock"], fsm2, _species) as Dictionary).get("ok") == true,
			"S5 gate must be installed onto the authoritative restored state"):
		return false
	var replay: Variant = eco2.commit_catch(state2, String(cand["catch_event_id"]), String(cand["species_id"]), utc)
	if not _check(replay.get("ok") == true and String(replay["code"]) == "ALREADY_APPLIED"
			and (state2.basket as Array).size() == 1 and int(state2.wallet_gold) == 0,
			"S5 restart commit_catch replay must be ALREADY_APPLIED with exactly 1 fish (no new fish)"):
		return false
	# 崩溃点 2：ack 已提交、clear/persist 未做 → 重启重放后 ack 正常收尾
	if not _check((fsm2.ack_settlement(String(cand["catch_event_id"]), true) as Dictionary).get("ok") == true
			and (svc2.clear_pending_candidate() as Dictionary).get("ok") == true
			and (svc2.persist_runtime_checkpoint() as Dictionary).get("ok") == true,
			"S5 ack + clear + checkpoint after restart"):
		return false
	var instance_id := "fish-" + String(cand["catch_event_id"])
	if not _check((eco2.sell_fish(state2, "sale-s5", [instance_id]) as Dictionary).get("ok") == true,
			"S5 sale committed"):
		return false
	var crash2 := _crash_services(dir_path, 8080)
	var res2: Variant = crash2["save"].load_save(_species, 8080)
	var state3 = res2["state"]
	if not _check(res2.get("ok") == true and (state3.basket as Array).is_empty()
			and (crash2["eco"].restore_ledger(state3, res2["ledger"]) as Dictionary).get("ok") == true,
			"S5 restart sees committed sale (empty basket, gold published)"):
		return false
	var sale_retry: Variant = crash2["eco"].sell_fish(state3, "sale-s5", [instance_id])
	if not _check(sale_retry.get("ok") == true and String(sale_retry["code"]) == "ALREADY_APPLIED"
			and int(sale_retry["gold_added"]) == 0 and int(state3.wallet_gold) == int(res2["state"].wallet_gold),
			"S5 sale replay must be ALREADY_APPLIED with +0 gold"):
		return false
	# 坏账本 fail-closed（BAD_LEDGER），失败后合法账本仍可恢复且幂等保持
	var ledger: Variant = (res2["ledger"] as Dictionary).duplicate(true)
	var bad_unknown: Variant = (res2["ledger"] as Dictionary).duplicate(true)
	(bad_unknown["processed_catches"] as Dictionary)["catch-bogus"] = {"species_id": "river_carp", "caught_at_utc": utc}
	var bad_missing: Variant = (res2["ledger"] as Dictionary).duplicate(true)
	(bad_missing["processed_catches"] as Dictionary).erase(String(cand["catch_event_id"]))
	if not _check(String((crash2["eco"].restore_ledger(state3, bad_unknown) as Dictionary)["code"]) == "BAD_LEDGER"
			and String((crash2["eco"].restore_ledger(state3, bad_missing) as Dictionary)["code"]) == "BAD_LEDGER"
			and (crash2["eco"].restore_ledger(state3, ledger) as Dictionary).get("ok") == true,
			"S5 BAD_LEDGER fail-closed then good restore"):
		return false
	var after: Variant = crash2["eco"].commit_catch(state3, String(cand["catch_event_id"]),
			String(cand["species_id"]), utc)
	return _check(after.get("ok") == true and String(after["code"]) == "ALREADY_APPLIED"
			and (state3.basket as Array).is_empty(),
			"S5 idempotence survives failed restores (fish was sold, stays 0)")
# ---- S6：RNG/Clock 恢复 + FSM 从 checkpoint 续跑与参考运行逐事件一致（plan §4.3）----
func _s6() -> bool:
	var dir_path := _fresh_dir("s6")
	var parts := _services(dir_path, 4242)
	var fsm = parts["fsm"]; var state = parts["state"]; var svc = parts["save"]
	var events: Array = []
	if (fsm.request_cast(state) as Dictionary).get("ok") != true:
		return _fail_ret("S6 cast")
	events.append_array(fsm.tick_effective(2.0))  # CASTING(1s)→WAITING，结转 1.0 有效秒
	var cp: Variant = fsm.snapshot_checkpoint()
	if not _check(String(cp["state"]) == "WAITING" and cp["wait_seconds"] != null
			and float(cp["elapsed_effective_seconds"]) == 1.0, "S6 WAITING checkpoint captured"):
		return false
	var main := dir_path + "game_state.json"
	if not _check((svc.persist_runtime_checkpoint() as Dictionary).get("ok") == true, "S6 commit WAITING checkpoint"):
		return false
	var main_bytes := _read_bytes(main)
	var crash := _crash_services(dir_path, 4242)
	var res: Variant = crash["save"].load_save(_species, 4242)
	if not _check(res.get("ok") == true and (crash["rng"].restore_state(res["rng_snapshot"]) as Dictionary).get("ok") == true
			and (crash["clock"].restore_state(res["clock_snapshot"]) as Dictionary).get("ok") == true
			and (crash["fsm"].initialize(_catalog, _runtime, crash["rng"], crash["clock"],
			((res["state"] as GameState).fishing_checkpoint as Dictionary).duplicate(true)) as Dictionary).get("ok") == true,
			"S6 restart restore from committed WAITING checkpoint"):
		return false
	if not _check(_read_bytes(main) == main_bytes and _files(dir_path) == ["game_state.json"],
			"S6 load/restore must perform zero writes"):
		return false
	events.append_array(crash["fsm"].tick_effective(1000.0))
	events.append_array(crash["fsm"].tick_effective(1.0))
	events.append_array(crash["fsm"].tick_effective(1.0))
	var cand_crash: Variant = crash["fsm"].produce_catch_candidate()
	# 参考运行：全新同种子服务镜像崩溃侧的调用序列（cast → tick2.0 →〔崩溃点〕→
	# tick1000 → tick1 → tick1）。FSM tick_effective 每次调用至多推进一步，恢复侧在
	# 崩溃点已带 WAITING elapsed=1.0 结转；参考侧首个 tick(2.0) 产生同一结转与同事件。
	var events_ref: Array = []
	var ref_dir := _fresh_dir("s6ref")
	var ref := _services(ref_dir, 4242)
	var ref_fsm = ref["fsm"]; var ref_state = ref["state"]
	if not _check((ref_fsm.request_cast(ref_state) as Dictionary).get("ok") == true, "S6 reference cast"):
		return false
	events_ref.append_array(ref_fsm.tick_effective(2.0))
	events_ref.append_array(ref_fsm.tick_effective(1000.0))
	events_ref.append_array(ref_fsm.tick_effective(1.0))
	events_ref.append_array(ref_fsm.tick_effective(1.0))
	var cand_ref: Variant = ref_fsm.produce_catch_candidate()
	if not _check(_deep_eq(_event_tuples(events), _event_tuples(events_ref)),
			"S6 restored FSM must reproduce reference event timeline: %s vs %s"
			% [str(_event_tuples(events)), str(_event_tuples(events_ref))]):
		return false
	if not _check(String(cand_crash["catch_event_id"]) == String(cand_ref["catch_event_id"])
			and String(cand_crash["species_id"]) == String(cand_ref["species_id"])
			and float(cand_crash["caught_at_clock"]) == float(cand_ref["caught_at_clock"]),
			"S6 re-fished RNG/Clock produce identical catch event (plan §4.3 RNG/Clock clause)"):
		return false
	var bad_rng: DeterministicRng = RngScript.new()
	var bad_clock: VirtualClock = ClockScript.new()
	return _check(String((bad_rng.restore_state({"version": 1, "seed": 0, "state": 5}) as Dictionary)["error_code"]) == "BAD_SNAPSHOT"
			and String((bad_clock.restore_state({"version": 1, "now": -1.0}) as Dictionary)["error_code"]) == "BAD_SNAPSHOT",
			"S6 rng/clock restore fail-closed on out-of-range snapshot")
# ---- S7：待结算候选生命周期 + UTC 原始形态严格校验（plan §4.1/§4.4、review #5/#7）----
func _s7() -> bool:
	var raw := Time.get_datetime_string_from_system(true)
	var pattern := RegEx.new()
	pattern.compile("^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})$")
	if not _check(pattern.search(raw) != null and not FishScript.timestamp_valid(raw)
			and FishScript.timestamp_valid(raw + "Z"),
			"S7 raw UTC is 19-char no-Z; Z-suffixed form is the valid UTC contract (review #7)"):
		return false
	var utc := raw + "Z"
	var dir_path := _fresh_dir("s7")
	var parts := _services(dir_path, 5150)
	var fsm = parts["fsm"]; var state = parts["state"]; var svc = parts["save"]; var eco = parts["eco"]
	if not _check(String((svc.set_pending_candidate({"ok": true, "code": "", "catch_event_id": "x",
			"species_id": "river_carp", "weight_snapshot": {"catch_weight": 60, "base_price": 8, "rarity": "common"},
			"caught_at_clock": 0.0}, utc))["code"]) == "BAD_PAYLOAD",
			"S7 candidate outside SETTLEMENT must reject BAD_PAYLOAD"):
		return false
	var cand := _cycle_to_settlement(fsm, state, svc, utc)
	if not _check(not cand.is_empty(), "S7 settlement reached"):
		return false
	if not _check(String((svc.set_pending_candidate(cand, raw))["code"]) == "BAD_TIMESTAMP",
			"S7 raw logical-clock-as-UTC timestamp must reject BAD_TIMESTAMP"):
		return false
	if not _check((svc.set_pending_candidate(cand, utc) as Dictionary).get("ok") == true, "S7 candidate stored"):
		return false
	if not _check((eco.commit_catch(state, String(cand["catch_event_id"]), String(cand["species_id"]), utc) as Dictionary).get("ok") == true,
			"S7 catch committed through gate"):
		return false
	var written: Variant = JSON.parse_string(_read_text(dir_path + "game_state.json"))
	var saved_cand: Variant = written["pending_candidate"]
	if not _check(saved_cand is Dictionary and (saved_cand as Dictionary).size() == 6
			and String(saved_cand["catch_event_id"]) == String(cand["catch_event_id"])
			and String(saved_cand["species_id"]) == String(cand["species_id"])
			and String(saved_cand["caught_at_utc"]) == utc
			and float(saved_cand["caught_at_clock"]) == float(cand["caught_at_clock"])
			and String((written["fishing_checkpoint"] as Dictionary)["state"]) == "SETTLEMENT",
			"S7 disk doc carries 6-key candidate + fresh FSM checkpoint (gate overwrite clause, review #5)"):
		return false
	var crash := _crash_services(dir_path, 5150)
	var res: Variant = crash["save"].load_save(_species, 5150)
	if not _check(res.get("ok") == true and _deep_eq(res["pending_candidate"], saved_cand),
			"S7 candidate replay data survives crash byte-equivalently"):
		return false
	var state2: GameState = res["state"]  # 权威 = 载入副本（plan §4.5）
	if not _check((crash["eco"].restore_ledger(state2, res["ledger"]) as Dictionary).get("ok") == true,
			"S7 restore ledger on restart"):
		return false
	var replay: Variant = crash["eco"].commit_catch(state2, String(saved_cand["catch_event_id"]),
			String(saved_cand["species_id"]), String(saved_cand["caught_at_utc"]))
	if not _check(replay.get("ok") == true and String(replay["code"]) == "ALREADY_APPLIED",
			"S7 restart replays stored catch without re-sampling: %s" % str(replay)):
		return false
	if not _check((crash["fsm"].initialize(_catalog, _runtime, crash["rng"], crash["clock"],
			(state2.fishing_checkpoint as Dictionary).duplicate(true)) as Dictionary).get("ok") == true
			and (crash["fsm"].ack_settlement(String(saved_cand["catch_event_id"]), true) as Dictionary).get("ok") == true,
			"S7 FSM restart in SETTLEMENT then ack completes window"):
		return false
	# 篡改目录价快照的候选 / 候选+IDLE checkpoint：提交必须拒绝且零写入
	var dir_b := _fresh_dir("s7b")
	var parts_b := _services(dir_b, 5150)
	var tampered := _manual_doc(1)
	tampered["fishing_checkpoint"] = {"state": "SETTLEMENT", "event_id": "catch-9-9", "wait_seconds": null,
			"elapsed_effective_seconds": 0.5}
	var entry: Variant = _species[_species.keys()[0]]
	tampered["pending_candidate"] = {"version": 1, "catch_event_id": "catch-9-9",
			"species_id": String(entry["id"]),
			"weight_snapshot": {"catch_weight": entry["catch_weight"], "base_price": 999999,
					"rarity": entry["rarity"]}, "caught_at_clock": 0.5, "caught_at_utc": _utc(1)}
	if not _check(String((parts_b["save"].atomic_commit(tampered))["code"]) == "CANDIDATE_CONFIG_MISMATCH",
			"S7 tampered weight_snapshot -> CANDIDATE_CONFIG_MISMATCH"):
		return false
	tampered["fishing_checkpoint"] = {"state": "IDLE", "event_id": null, "wait_seconds": null,
			"elapsed_effective_seconds": 0.0}
	return _check(String((parts_b["save"].atomic_commit(tampered))["code"]) == "CANDIDATE_STATE_MISMATCH"
			and _files(dir_b).is_empty() and not _has_tmp_residue(dir_b)
			and not _has_tmp_residue(dir_path),
			"S7 candidate outside SETTLEMENT checkpoint -> CANDIDATE_STATE_MISMATCH, zero writes")
# ---- S8：经济持久化门契约（只认真布尔 true；发布恰一次）----
func _s8() -> bool:
	var eco_test := EcoScript.new()
	if (eco_test.initialize(_catalog, _runtime) as Dictionary).get("ok") != true:
		return _fail_ret("S8 eco init")
	var gates: Array = [[Callable(self, "_gate_false"), "false"], [Callable(self, "_gate_nonbool"), "non-bool"]]
	for gate_case in gates:
		(eco_test.set_persistence_gate(gate_case[0]) as Dictionary)
		var failed: Variant = eco_test.commit_catch(GameState.new(), "catch-s8", "river_carp", _utc(2))
		if not _check(failed.get("ok") == false and String(failed["code"]) == "PERSIST_FAILED"
				and String(failed["instance_id"]) == "",
				"S8 gate %s must PERSIST_FAILED" % str(gate_case[1])):
			return false
	eco_test.set_persistence_gate(Callable())
	var refused_invalid: Variant = eco_test.commit_catch(GameState.new(), "catch-s8", "river_carp", _utc(2))
	if not _check(refused_invalid.get("ok") == false and String(refused_invalid["code"]) == "PERSIST_FAILED",
			"S8 invalid callable gate must PERSIST_FAILED without being called"):
		return false
	var dir_path := _fresh_dir("s8")
	var parts := _services(dir_path, 6165)
	var fsm = parts["fsm"]; var eco = parts["eco"]; var state2 = parts["state"]; var svc = parts["save"]
	var utc := _utc(4)
	var cand := _cycle_to_settlement(fsm, state2, svc, utc)
	if not _check(not cand.is_empty(), "S8 settlement reached"):
		return false
	(svc.set_fault_injection("rename", true) as Dictionary)
	var rng_before := int(parts["rng"].get_state()); var clock_before := float(parts["clock"].now())
	var fsm_before: Variant = fsm.snapshot_checkpoint(); var state_before := _state_snapshot(state2)
	var refused: Variant = eco.commit_catch(state2, String(cand["catch_event_id"]), String(cand["species_id"]), utc)
	if not _check(refused.get("ok") == false and String(refused["code"]) == "PERSIST_FAILED"
			and not FileAccess.file_exists(dir_path + "game_state.json")
			and not _has_tmp_residue(dir_path) and int(parts["rng"].get_state()) == rng_before
			and float(parts["clock"].now()) == clock_before and _deep_eq(fsm_before, fsm.snapshot_checkpoint())
			and _deep_eq(state_before, _state_snapshot(state2)),
			"S8 rename fault -> gate false -> PERSIST_FAILED, zero side effects incl. rng/clock/fsm"):
		return false
	(svc.set_fault_injection("rename", false) as Dictionary)
	var accepted: Variant = eco.commit_catch(state2, String(cand["catch_event_id"]), String(cand["species_id"]), utc)
	return _check(accepted.get("ok") == true and String(accepted["code"]) == ""
			and (state2.basket as Array).size() == 1 and (state2.processed_catch_ids as Array).size() == 1
			and int(state2.revision) == int(state_before["revision"]) + 1 and int(state2.save_version) == 2
			and String((state2.fishing_checkpoint as Dictionary)["state"]) == "SETTLEMENT",
			"S8 after rename success gate returns true and publishes exactly once")
# ---- 共享辅助 ----
func _utc(index: int) -> String:
	return "2026-11-11T%02d:00:00Z" % (index % 24)
func _manual_doc(revision: int) -> Dictionary:
	return {
		"save_version": 2, "revision": revision, "wallet_gold": 0, "basket_capacity": 10,
		"basket": [], "processed_catch_ids": [], "processed_sale_ids": [],
		"fishing_checkpoint": {"state": "IDLE", "event_id": null, "wait_seconds": null,
				"elapsed_effective_seconds": 0.0},
		"desktop_window": {"x": 80, "y": 80, "width": 220, "height": 160, "display_hint": null},
		"economy_ledger": {"processed_catches": {}, "processed_sales": {}},
		"rng_snapshot": {"version": 1, "seed": 1234, "state": 1234},
		"clock_snapshot": {"version": 1, "now": 0.0},
		"pending_candidate": null,
	}
## 在 dir_path 装配全套服务（eco/rng/clock/fsm 全新，save 注入目录并 install）。空 = 失败。
func _services(dir_path: String, seed_value: int) -> Dictionary:
	var eco: EconomyService = EcoScript.new()
	if eco.initialize(_catalog, _runtime).get("ok") != true:
		return {}
	var rng: DeterministicRng = RngScript.new()
	if rng.set_seed(seed_value).get("ok") != true:
		return {}
	var clock: VirtualClock = ClockScript.new()
	var fsm: FishingStateMachine = FsmScript.new()
	if fsm.initialize(_catalog, _runtime, rng, clock, {}).get("ok") != true:
		return {}
	var state := GameState.new()
	var svc: AtomicSaveService = SaveScript.new()
	if svc.configure_dir(dir_path).get("ok") != true:
		return {}
	if svc.install_into(eco, state, rng, clock, fsm, _species).get("ok") != true:
		return {}
	return {"eco": eco, "state": state, "rng": rng, "clock": clock, "fsm": fsm, "save": svc}
## 崩溃重建（plan §4.5 装配蓝图）：eco/rng/clock/fsm 全新、save 仅 configure_dir 未装配。
## 不自动加载也不预装配——调用方显式 load_save，再用**载入出的权威 state** 完成
## restore_ledger / rng/clock restore_state / fsm.initialize(checkpoint) 后才 install_into；
## 把门装到默认 GameState 上属装配协议漂移（load 返回的才是权威副本）。
func _crash_services(dir_path: String, seed_value: int) -> Dictionary:
	var eco: EconomyService = EcoScript.new()
	if eco.initialize(_catalog, _runtime).get("ok") != true:
		return {}
	var rng: DeterministicRng = RngScript.new()
	if rng.set_seed(seed_value).get("ok") != true:
		return {}
	var clock: VirtualClock = ClockScript.new()
	var fsm: FishingStateMachine = FsmScript.new()
	var svc: AtomicSaveService = SaveScript.new()
	if svc.configure_dir(dir_path).get("ok") != true:
		return {}
	return {"eco": eco, "rng": rng, "clock": clock, "fsm": fsm, "save": svc}
## request_cast → ticks → produce candidate + set_pending_candidate；不做 eco 落账。
func _cycle_to_settlement(fsm, state: GameState, svc, utc: String) -> Dictionary:
	if (fsm.request_cast(state) as Dictionary).get("ok") != true:
		return {}
	fsm.tick_effective(5.0); fsm.tick_effective(200.0); fsm.tick_effective(1.0); fsm.tick_effective(1.0)
	var cand: Variant = fsm.produce_catch_candidate()
	if cand.get("ok") != true:
		return {}
	if (svc.set_pending_candidate(cand, utc) as Dictionary).get("ok") != true:
		return {}
	return cand
func _event_tuples(events: Array) -> Array:
	var out: Array = []
	for element in events:
		out.append([String(element["from_state"]), String(element["to_state"]),
				float(element["at_clock"]), String(element["event_id"])])
	return out
func _faults_all_disarmed(faults) -> bool:
	for stage in FaultsScript.STAGES:
		if faults.is_armed(stage):
			return false
	return faults.armed_stages().is_empty()
func _fresh_dir(label: String) -> String:
	var base := OS.get_temp_dir().rstrip("/")
	var path := base + "/save001_%s_%d" % [label, _dir_seq]
	_dir_seq += 1
	if DirAccess.dir_exists_absolute(path):
		_remove_dir(path)
	DirAccess.make_dir_recursive_absolute(path)
	_dirs.append(path)
	return path + "/"
func _cleanup_dirs() -> void:
	for path in _dirs:
		_remove_dir(path)
	_dirs.clear()
## Godot 4.7.2 实测：静态 DirAccess.remove_absolute 可删文件/空目录，但非空目录返回 FAILED
## 且不存在 remove_recursive。手工 open+list_dir 递归删子项，最后移除已空目录本身。
func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	var child_failed := false
	while entry != "":
		if dir.current_is_dir():
			_remove_dir(path + "/" + entry)
		elif dir.remove(entry) != OK:
			child_failed = true
		entry = dir.get_next()
	dir.list_dir_end()
	var remove_error: int = DirAccess.remove_absolute(path)
	if (child_failed or remove_error != OK) and DirAccess.dir_exists_absolute(path):
		push_warning("SAVE001 cleanup failed for %s: %s" % [path, error_string(remove_error)])
func _files(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
func _has_tmp_residue(dir_path: String) -> bool:
	for name in _files(dir_path):
		if String(name).contains(".tmp."):
			return true
	return false
func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	return text
func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes
func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
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
# ---- 注入测试门（仅 S8 内存门用例；不写任何文件）----
func _gate_false(_payload: Dictionary) -> bool:
	return false
func _gate_nonbool(_payload: Dictionary) -> Variant:
	return 1
## 断言门：真值放行；首个失败打印稳定 FAIL 标记并 quit(1)（不伪造退出码）。
func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	return _fail_ret(message)
func _fail_ret(msg: String) -> bool:
	print("SAVE001 SAVE FAIL: " + msg); quit(1)
	return false
