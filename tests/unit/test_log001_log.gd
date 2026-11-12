extends SceneTree
# LOG-001 headless integration checks for EventLog + FishingSession log wiring (plan §4 L-1..L-8).
# All log/save IO uses explicit temporary dirs; real user:// is never touched.
# PASS marker: "LOG001 LOG PASS" / FAIL marker: "LOG001 LOG FAIL".
const LogScript := preload("res://scripts/io/event_log.gd")
const SessionScript := preload("res://scripts/ui/fishing_session.gd")
const HudScript := preload("res://scripts/ui/fishing_status_hud.gd")
const FishScript := preload("res://scripts/economy/fish_instance.gd")
const SAVE_NAME := "game_state.json"
const FILE_PATTERN := "^event_log-[0-9]{8}-[0-9]{6}\\.jsonl$"
const LINE_KEYS := ["timestamp_utc", "severity", "event", "event_id", "save_version", "result", "error_code", "elapsed_ms"]

var _dirs: Array[String] = []
var _dir_seq := 0


func _initialize() -> void:
	await process_frame  # 与 UI-001 同：先激活场景树，令后续 root.add_child(HUD) 同步执行 _ready
	for step in [_test_line_shape_and_generated_timestamp, _test_rejections_are_zero_write,
			_test_utc_day_rotation, _test_size_rotation_and_bounded_retention, _test_sequence_limit,
			_test_checkpoint_failure_trace_without_economy_change,
			_test_catch_and_sale_events, _test_privacy_surface,
			_test_log_failure_cannot_change_economy]:
		if not step.call():
			_cleanup_dirs()
			return
	_cleanup_dirs()
	print("LOG001 LOG PASS")
	quit(0)


# ---- L-1: whitelist shape, logger-generated timestamp, fixed key order ----
func _test_line_shape_and_generated_timestamp() -> bool:
	var dir := _fresh_dir("shape")
	var log := LogScript.new()
	var cfg: Dictionary = log.configure_dir(dir, {})
	if not _check(cfg.get("ok") == true and String(cfg.get("code", "")) == "OK", "L1 configure_dir ok/OK"):
		return false
	var rec := {"severity": "info", "event": "catch_committed", "event_id": "catch-7-3",
			"save_version": 2, "result": "ok", "error_code": null, "elapsed_ms": 12}
	var res: Dictionary = log.record(rec)
	if not _check(res.get("ok") == true and String(res.get("code", "")) == "", "L1 record ok"):
		return false
	var files := _log_files(dir)
	if not _check(files.size() == 1, "L1 exactly one log file"):
		return false
	var raw := _read_text(dir + String(files[0]))
	var lines := _split_lines(raw)
	if not _check(lines.size() == 1, "L1 exactly one JSONL row"):
		return false
	var parsed: Variant = JSON.parse_string(lines[0])
	if not _check(parsed is Dictionary and (parsed as Dictionary).size() == 8, "L1 row has exactly 8 keys"):
		return false
	var row: Dictionary = parsed
	for key in LINE_KEYS:
		if not row.has(key):
			return _fail("L1 missing whitelist key: " + String(key))
	if not _check(FishScript.timestamp_valid(String(row["timestamp_utc"])), "L1 logger-generated valid UTC"):
		return false
	var cursor := -1
	for key in LINE_KEYS:
		var at := raw.find("\"" + String(key) + "\"")
		if at <= cursor:
			return _fail("L1 fixed key order broken at " + String(key))
		cursor = at
	if not _check(String(row["severity"]) == "info" and String(row["result"]) == "ok"
			and String(row["event_id"]) == "catch-7-3" and row["error_code"] == null, "L1 echoed whitelist values"):
		return false
	var hostile: Dictionary = rec.duplicate(true)
	hostile["timestamp_utc"] = "2020-01-01T00:00:00Z"  # caller-provided timestamp must be refused
	var rejected: Dictionary = log.record(hostile)
	if not _check(rejected.get("ok") == false and String(rejected.get("code", "")) == "BAD_KEYS",
			"L1 caller timestamp refused with BAD_KEYS"):
		return false
	var cold := LogScript.new()
	if not _check((cold.record(rec) as Dictionary).get("ok") == false, "L1 unconfigured logger refuses"):
		return false
	return _check(_split_lines(_read_text(dir + String(files[0]))).size() == 1, "L1 refusals wrote zero rows")


# ---- L-2: invalid records refused with zero file growth ----
func _test_rejections_are_zero_write() -> bool:
	var dir := _fresh_dir("reject")
	var log := LogScript.new()
	if not _check(log.configure_dir(dir, {}).get("ok") == true, "L2 configure"):
		return false
	var base := {"severity": "warn", "event": "sale_failed", "result": "error", "error_code": "PERSIST_FAILED"}
	var bad: Array = []
	var extra: Dictionary = base.duplicate(true)
	extra["reason"] = "basket exploded"  # unknown key
	bad.append(extra)
	var pathy: Dictionary = base.duplicate(true)
	pathy["event"] = "/Users/x"  # path as event text
	bad.append(pathy)
	var sentence: Dictionary = base.duplicate(true)
	sentence["event"] = "catch committed at night"  # free text with whitespace
	bad.append(sentence)
	var event_id: Dictionary = base.duplicate(true)
	event_id["event_id"] = "catch 1/../x"  # whitespace + path fragment
	bad.append(event_id)
	var negative: Dictionary = base.duplicate(true)
	negative["elapsed_ms"] = -5
	bad.append(negative)
	var severity: Dictionary = base.duplicate(true)
	severity["severity"] = "debug"
	bad.append(severity)
	var event: Dictionary = base.duplicate(true)
	event["event"] = "fish_party"
	bad.append(event)
	var version: Dictionary = base.duplicate(true)
	version["save_version"] = "2"  # non-int save_version
	bad.append(version)
	var missing: Dictionary = {"event": "sale_failed"}  # severity omitted → required
	bad.append(missing)
	for rec in bad:
		var res: Dictionary = (rec as Dictionary)
		var result: Dictionary = log.record(res)
		if not _check(result.get("ok") == false, "L2 refused record: " + String(res.get("event", "?"))):
			return false
	var strict := LogScript.new()
	if not _check(String((strict.configure_dir(_fresh_dir("opts1"), {"max_bytes": 100}) as Dictionary).get("code", ""))
			== "BAD_OPTIONS", "L2 max_bytes floor refused"):
		return false
	if not _check(String((strict.configure_dir(_fresh_dir("opts2"), {"max_files": 0}) as Dictionary).get("code", ""))
			== "BAD_OPTIONS", "L2 max_files floor refused"):
		return false
	if not _check(String((strict.configure_dir(_fresh_dir("opts3"), {"upload": 1}) as Dictionary).get("code", ""))
			== "BAD_OPTIONS", "L2 unknown option refused"):
		return false
	if not _check(String((log.configure_dir(_fresh_dir("again"), {}) as Dictionary).get("code", ""))
			== "ALREADY_CONFIGURED", "L2 reconfigure refused after config"):
		return false
	return _check(_log_files(dir).is_empty(), "L2 refusals produced zero log files")


# ---- L-3: UTC day rotation; row date == file date ----
func _test_utc_day_rotation() -> bool:
	var dir := _fresh_dir("daily")
	var log := LogScript.new()
	if not _check(log.configure_dir(dir, {}).get("ok") == true, "L3 configure"):
		return false
	log.set_utc_override("2026-11-11T08:30:00Z")
	log.record({"severity": "info", "event": "catch_committed", "result": "ok"})
	log.set_utc_override("2026-11-12T00:00:01Z")
	log.record({"severity": "info", "event": "sale_committed", "result": "ok"})
	var files := _log_files(dir)
	if not _check(files == ["event_log-20261111-000000.jsonl", "event_log-20261112-000000.jsonl"],
			"L3 one file per UTC day"):
		return false
	var day_a := _split_lines(_read_text(dir + String(files[0])))
	var day_b := _split_lines(_read_text(dir + String(files[1])))
	if not _check(day_a.size() == 1 and day_b.size() == 1, "L3 one row per day"):
		return false
	var row_a: Dictionary = JSON.parse_string(day_a[0])
	var row_b: Dictionary = JSON.parse_string(day_b[0])
	return _check(String(row_a["timestamp_utc"]).begins_with("2026-11-11")
			and String(row_b["timestamp_utc"]).begins_with("2026-11-12"),
			"L3 row date matches file date")


# ---- L-4: size rotation + bounded retention + restart resume + save decoys ----
func _test_size_rotation_and_bounded_retention() -> bool:
	var dir := _fresh_dir("rotate")
	if not _write_text(dir + SAVE_NAME, "{\"save_version\":2,\"decoy\":1}") \
			or not _write_text(dir + SAVE_NAME + ".bak", "{\"save_version\":2,\"decoy\":2}"):
		return _fail("L4 create decoy save files")
	var log := LogScript.new()
	if not _check(log.configure_dir(dir, {"max_bytes": 512, "max_files": 3}).get("ok") == true, "L4 configure"):
		return false
	log.set_utc_override("2026-11-13T05:00:00Z")
	var written := 0
	for index in 30:
		var res: Dictionary = log.record({"severity": "info", "event": "catch_committed",
				"event_id": "catch-%d-%d" % [index, 40 + index], "result": "ok", "elapsed_ms": index})
		if res.get("ok") == true:
			written += 1
	if not _check(written == 30, "L4 all 30 rows accepted (got %d)" % written):
		return false
	var files := _log_files(dir)
	if not _check(not files.is_empty() and files.size() <= 3, "L4 at most max_files files"):
		return false
	for name in files:
		if _file_bytes(dir + String(name)) > 512:
			return _fail("L4 file exceeds max_bytes: " + String(name))
	var kept := _read_lines(dir)
	if not _check(kept.size() < written, "L4 oldest rows pruned by retention bound"):
		return false
	var before_texts := _snapshot_texts(dir)
	var resumed := LogScript.new()
	if not _check(resumed.configure_dir(dir, {"max_bytes": 512, "max_files": 3}).get("ok") == true,
			"L4 reconfigure in fresh instance"):
		return false
	resumed.set_utc_override("2026-11-13T05:00:05Z")
	if not _check(resumed.record({"severity": "warn", "event": "sale_committed", "result": "ok"}).get("ok") == true,
			"L4 append after restart"):
		return false
	var after_files := _log_files(dir)
	# 重启追加只许 append-only：任何重启前后都存在的文件，旧字节必须是现内容的前缀
	# （续写满文件则切下一个未占用序号 —— 两种情况都不得覆盖/截断已有字节）。
	var after_texts := _snapshot_texts(dir)
	for name in before_texts:
		if after_texts.has(name) \
				and not String(after_texts[name]).begins_with(String(before_texts[name])):
			return _fail("L4 restart overwrote existing bytes: " + String(name))
	var newest_now := _read_text(dir + String(after_files[after_files.size() - 1]))
	var tail_rows := _split_lines(newest_now)
	var tail: Dictionary = JSON.parse_string(tail_rows[tail_rows.size() - 1])
	if not _check(String(tail["event"]) == "sale_committed", "L4 appended row is last in newest file"):
		return false
	for name in after_files:
		if _file_bytes(dir + String(name)) > 512:
			return _fail("L4 file exceeds max_bytes after restart: " + String(name))
	if not _check(_read_text(dir + SAVE_NAME) == "{\"save_version\":2,\"decoy\":1}"
			and _read_text(dir + SAVE_NAME + ".bak") == "{\"save_version\":2,\"decoy\":2}",
			"L4 decoy save files never pruned"):
		return false
	var health: Dictionary = log.health()
	return _check(int(health.get("lines_written", -1)) == 30 and int(health.get("files_pruned", 0)) >= 1
			and int(health.get("max_bytes", 0)) == 512 and int(health.get("max_files", 0)) == 3,
			"L4 health counters (no content, no paths)")


# ---- L-4b: six-digit sequence exhaustion fails closed ----
func _test_sequence_limit() -> bool:
	var dir := _fresh_dir("sequence-limit")
	var existing_name := "event_log-20261114-999999.jsonl"
	var existing_text := ""
	for index in 512:
		existing_text += "x"
	if not _write_text(dir + existing_name, existing_text):
		return _fail("L4b create full max-sequence file")
	var log := LogScript.new()
	if not _check(log.configure_dir(dir, {"max_bytes": 512, "max_files": 3}).get("ok") == true,
			"L4b configure"):
		return false
	log.set_utc_override("2026-11-14T05:00:00Z")
	var result: Dictionary = log.record({"severity": "info", "event": "catch_committed", "result": "ok"})
	if not _check(result.get("ok") == false and String(result.get("code", "")) == "IO_FAILED",
			"L4b exhausted six-digit sequence refuses append"):
		return false
	if not _check(_log_files(dir) == [existing_name], "L4b no seven-digit filename created"):
		return false
	var health: Dictionary = log.health()
	return _check(int(health.get("lines_written", -1)) == 0 and int(health.get("io_errors", -1)) == 1
			and _read_text(dir + existing_name) == existing_text,
			"L4b fail-closed preserves existing bytes and counts IO error")


# ---- L-5: checkpoint failure leaves a trace; economy identical to same-seed control ----
func _test_checkpoint_failure_trace_without_economy_change() -> bool:
	var fault_dir := _fresh_dir("fault-save")
	var fault_log := _fresh_dir("fault-log")
	var session := SessionScript.new()
	var boot: Dictionary = session.start({"save_dir": fault_dir, "log_dir": fault_log, "rng_seed": 9401})
	if not _check(boot.get("ok") == true and (session.log_health() as Dictionary).get("ok") == true,
			"L5 boot with healthy log"):
		return false
	if not _check(session.save_fault("rename", true).get("ok") == true, "L5 arm rename fault"):
		return false
	var cast: Dictionary = session.request_cast()
	if not _check(cast.get("ok") == true and cast.get("checkpoint_committed") == false
			and session.status_view().get("save_error") == true, "L5 failed checkpoint marks save error"):
		return false
	var lines := _read_lines(fault_log)
	if not _check(_count_rows(lines, "save_checkpoint_failed", "error", "error", "PERSIST_FAILED") >= 1,
			"L5 save_checkpoint_failed/error/error/PERSIST_FAILED row exists"):
		return false
	if not _check(session.save_fault("rename", false).get("ok") == true, "L5 disarm fault"):
		return false
	if not _check(session.retry_persist().get("ok") == true
			and session.status_view().get("save_error") == false, "L5 retry persists after clearing fault"):
		return false
	var control_dir := _fresh_dir("control-save")
	var control_log := _fresh_dir("control-log")
	var control := SessionScript.new()
	if not _check(control.start({"save_dir": control_dir, "log_dir": control_log, "rng_seed": 9401}).get("ok") == true,
			"L5 control boot"):
		return false
	var control_cast: Dictionary = control.request_cast()
	if not _check(String(cast.get("catch_event_id", "")) == String(control_cast.get("catch_event_id", ""))
			and not String(cast.get("catch_event_id", "")).is_empty(), "L5 same seed yields same catch id"):
		return false
	# status_view() 的经济键是 "gold"（无 wallet_gold 键）；sale ID 内含每会话 Crypto nonce，
	# 跨会话字符串恒不等 ⇒ 只比数量与金额/鱼篓/revision/捕获 ID（同 seed 捕获路径逐字段一致）。
	var faulty: Dictionary = session.status_view()
	var clean: Dictionary = control.status_view()
	if not _check(faulty.get("gold") == clean.get("gold") and faulty.get("basket") == clean.get("basket")
			and faulty.get("revision") == clean.get("revision"), "L5 gold/basket/revision match control"):
		return false
	return _check(session.state().processed_catch_ids == control.state().processed_catch_ids
			and session.state().processed_sale_ids == control.state().processed_sale_ids,
			"L5 processed id ledgers match control (logging creates no transactions)")


# ---- L-6: catch/sale commit+failure events ----
func _test_catch_and_sale_events() -> bool:
	var dir := _fresh_dir("events-save")
	var log_dir := _fresh_dir("events-log")
	var session := SessionScript.new()
	if not _check(session.start({"save_dir": dir, "log_dir": log_dir, "rng_seed": 6301}).get("ok") == true, "L6 boot"):
		return false
	var cast: Dictionary = session.request_cast()
	if not _check(cast.get("ok") == true, "L6 cast"):
		return false
	var catch_id := String(cast.get("catch_event_id", ""))
	if not _check(_tick_to_settlement(session), "L6 deterministic cycle reaches SETTLEMENT"):
		return false
	var rows := _find_rows(_read_lines(log_dir), "catch_committed")
	if not _check(rows.size() == 1 and String(rows[0]["severity"]) == "info" and String(rows[0]["result"]) == "ok"
			and String(rows[0]["event_id"]) == catch_id and rows[0]["elapsed_ms"] is float
			and int(rows[0]["elapsed_ms"]) >= 0, "L6 catch_committed/info/ok row with catch id"):
		return false
	if not _check(session.state().basket.size() == 1, "L6 settlement put one fish in the basket"):
		return false
	var fish: Dictionary = session.state().basket[0]
	var price := int(fish["sale_price_at_catch"])
	if not _check(session.save_fault("rename", true).get("ok") == true, "L6 arm rename fault before sale"):
		return false
	var sale: Dictionary = session.sell_all()
	if not _check(sale.get("ok") == false and String(sale.get("code", "")) == "PERSIST_FAILED", "L6 sale PERSIST_FAILED"):
		return false
	var failure_rows := _find_rows(_read_lines(log_dir), "sale_failed")
	if not _check(failure_rows.size() == 1 and String(failure_rows[0]["severity"]) == "error"
			and String(failure_rows[0]["result"]) == "error" and String(failure_rows[0]["error_code"]) == "PERSIST_FAILED"
			and String(failure_rows[0]["event_id"]) == String(sale.get("sale_id", "")),
			"L6 exactly one sale_failed/PERSIST_FAILED row with sale id"):
		return false
	if not _check(session.save_fault("rename", false).get("ok") == true, "L6 disarm fault"):
		return false
	if not _check(session.retry_persist().get("ok") == true, "L6 retry persists the sale"):
		return false
	var sale_rows := _find_rows(_read_lines(log_dir), "sale_committed")
	if not _check(sale_rows.size() == 1 and String(sale_rows[0]["severity"]) == "info"
			and String(sale_rows[0]["result"]) == "ok"
			and String(sale_rows[0]["event_id"]) == String(sale.get("sale_id", ""))
			and (sale_rows[0] as Dictionary).size() == 8, "L6 exactly one sale_committed row without any gold field"):
		return false
	if not _check(session.state().wallet_gold == price and session.state().basket.is_empty(),
			"L6 gold added exactly once after retry (idempotent contract intact)"):
		return false
	# catch_failed: settlement commit refused while the persistence fault is armed, then retried.
	var fault_dir := _fresh_dir("catch-fault-save")
	var fault_log := _fresh_dir("catch-fault-log")
	var faulted := SessionScript.new()
	if not _check(faulted.start({"save_dir": fault_dir, "log_dir": fault_log, "rng_seed": 6302}).get("ok") == true,
			"L6 faulted boot"):
		return false
	if not _check(faulted.request_cast().get("ok") == true, "L6 faulted cast accepted"):
		return false
	if not _check(_tick_to_reeling(faulted), "L6 faulted cycle reaches REELING"):
		return false
	if not _check(faulted.save_fault("rename", true).get("ok") == true,
			"L6 arm fault at REELING so the settlement commit fails"):
		return false
	if not _check(_tick_to_settlement(faulted), "L6 faulted cycle reaches SETTLEMENT"):
		return false
	var failed_rows := _find_rows(_read_lines(fault_log), "catch_failed")
	if not _check(not failed_rows.is_empty() and String(failed_rows[0]["severity"]) == "error"
			and String(failed_rows[0]["result"]) == "error"
			and String(failed_rows[0]["error_code"]) == "PERSIST_FAILED",
			"L6 catch_failed/error/error/PERSIST_FAILED rows exist"):
		return false
	if not _check(faulted.save_fault("rename", false).get("ok") == true, "L6 disarm fault"):
		return false
	if not _check(faulted.retry_persist().get("ok") == true and faulted.state().basket.size() == 1,
			"L6 settlement retry commits exactly one fish"):
		return false
	var retried := _find_rows(_read_lines(fault_log), "catch_committed")
	return _check(retried.size() == 1 and String(retried[0]["result"]) == "ok",
			"L6 retried settlement logs exactly one catch_committed")


# ---- L-7: privacy static surface over every produced row ----
func _test_privacy_surface() -> bool:
	var dir := _fresh_dir("privacy-save")
	var log_dir := _fresh_dir("privacy-log")
	var session := SessionScript.new()
	if not _check(session.start({"save_dir": dir, "log_dir": log_dir, "rng_seed": 7007}).get("ok") == true, "L7 boot"):
		return false
	var fault_dir := _fresh_dir("privacy-fault-save")
	var fault_log := _fresh_dir("privacy-fault-log")
	var faulted := SessionScript.new()
	if not _check(faulted.start({"save_dir": fault_dir, "log_dir": fault_log, "rng_seed": 7008}).get("ok") == true,
			"L7 faulted boot"):
		return false
	if not _check(session.request_cast().get("ok") == true and _tick_to_settlement(session), "L7 catch"):
		return false
	if not _check(faulted.request_cast().get("ok") == true and _tick_to_reeling(faulted),
			"L7 faulted cast + reach REELING"):
		return false
	if not _check(faulted.save_fault("rename", true).get("ok") == true
			and _tick_to_settlement(faulted), "L7 faulted catch reaches SETTLEMENT with fault armed"):
		return false
	if not _check(session.sell_all().get("ok") == true, "L7 sale"):
		return false
	if not _check(faulted.save_fault("rename", false).get("ok") == true and faulted.retry_persist().get("ok") == true,
			"L7 faulted retry"):
		return false
	var lines: Array = _read_lines(log_dir) + _read_lines(fault_log)
	if not _check(lines.size() >= 3, "L7 both sessions produced rows"):
		return false
	for raw in lines:
		var text := String(raw)
		if text.contains("/") or text.contains("\\") or text.contains("~") or text.contains(" "):
			return _fail("L7 row contains path/user-home/whitespace text: " + text)
		if text.to_utf8_buffer().size() > 384:
			return _fail("L7 row exceeds 384 UTF-8 bytes")
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			return _fail("L7 row is not one JSON object")
		var row: Dictionary = parsed
		if row.size() != LINE_KEYS.size():
			return _fail("L7 row must contain exactly the 8 whitelist keys")
		for key in LINE_KEYS:
			if not row.has(key):
				return _fail("L7 row missing whitelist key: " + String(key))
	return true


# ---- L-8: broken logging cannot change boot/economy; UI-001 banner reused unchanged ----
func _test_log_failure_cannot_change_economy() -> bool:
	var blocker_dir := _fresh_dir("blocked")
	var blocker := blocker_dir + "blocked_log"  # an existing plain file can never become a directory
	if not _write_text(blocker, "not-a-directory"):
		return _fail("L8 create blocker file")
	var blocked_save := _fresh_dir("blocked-save")
	var session := SessionScript.new()
	var boot: Dictionary = session.start({"save_dir": blocked_save, "log_dir": blocker, "rng_seed": 8100})
	if not _check(boot.get("ok") == true and boot.get("fresh") == true, "L8 boot ok with unusable log dir"):
		return false
	var view: Dictionary = session.status_view()
	if not _check(view.get("input_open") == true and view.get("save_error") == false,
			"L8 broken log never opens the save-error banner state"):
		return false
	var health: Dictionary = session.log_health()
	if not _check(health.get("ok") == false and String(health.get("code", "")) == "BAD_DIR",
			"L8 log_health reports the config failure code only"):
		return false
	var cast: Dictionary = session.request_cast()
	if not _check(cast.get("ok") == true and cast.get("checkpoint_committed") == true, "L8 cast checkpoint durable"):
		return false
	if not _check(_tick_to_settlement(session), "L8 blocked-log session reaches SETTLEMENT"):
		return false
	var sale: Dictionary = session.sell_all()
	if not _check(sale.get("ok") == true, "L8 blocked-log sale persists normally"):
		return false
	var control_save := _fresh_dir("blocked-control-save")
	var control_log := _fresh_dir("blocked-control-log")
	var control := SessionScript.new()
	if not _check(control.start({"save_dir": control_save, "log_dir": control_log, "rng_seed": 8100}).get("ok") == true,
			"L8 control boot"):
		return false
	var control_cast: Dictionary = control.request_cast()
	if not _check(_tick_to_settlement(control) and control.sell_all().get("ok") == true, "L8 control sequence"):
		return false
	var blocked: Dictionary = session.status_view()
	var clean: Dictionary = control.status_view()
	# sale ID 内含每会话 Crypto nonce（_next_sale_id），跨会话字符串恒不等 ⇒ 账本比数量；
	# 金额/鱼篓/revision/捕获 ID 必须逐字段一致（日志故障零经济影响，V01-L01/T-TIME-03）。
	if not _check(blocked.get("gold") == clean.get("gold") and blocked.get("basket") == clean.get("basket")
			and blocked.get("revision") == clean.get("revision")
			and session.state().processed_catch_ids == control.state().processed_catch_ids
			and session.state().processed_sale_ids.size() == control.state().processed_sale_ids.size()
			and not session.state().processed_sale_ids.is_empty(),
			"L8 economy equals same-seed healthy-log control exactly"):
		return false
	if not _check(_read_text(blocker) == "not-a-directory" and _log_files(blocker_dir).is_empty()
			and not _read_lines(control_log).is_empty(), "L8 broken log wrote nothing; healthy log wrote rows"):
		return false
	# UI-001 组件零改动复用：save_error=true → 持久非模态横幅 + 重试按钮 + retry_requested 信号。
	var hud := HudScript.new()
	root.add_child(hud)
	var requested := [false]
	hud.retry_requested.connect(func(): requested[0] = true)
	hud.update_status({"gold": 0, "basket_count": 1, "basket_capacity": 10, "state": "IDLE",
			"basket_full": false, "save_error": true, "input_open": true, "boot_code": ""})
	var banner := hud.get_node_or_null("SaveErrorBanner") as Label
	var retry := hud.get_node_or_null("SaveRetryButton") as Button
	if not _check(is_instance_valid(banner) and is_instance_valid(retry) and banner.visible and retry.visible
			and String(banner.text) == "存档失败：经济已暂停（可重试）",
			"L8 persistent non-modal save-failure banner and retry entry visible"):
		hud.free()
		return false
	retry.pressed.emit()
	var wired := _check(requested[0] == true, "L8 retry_requested signal still wired to the reused banner")
	hud.free()
	return wired


# ---- shared helpers ----

## 自动结算会话在单次 tick 内完成 SETTLEMENT 到达 + 落账 + ack 回 IDLE（UI-001 的跨 tick
## SETTLEMENT 依赖 manual_settlement 测试开关，本票不开启），故以 to_state==SETTLEMENT 的
## 转换事件判定「周期到达 SETTLEMENT 并执行了结算路径」。
func _tick_to_settlement(session) -> bool:
	for _step in 8:
		var events: Array = session.tick(120.0)
		for event in events:
			if String((event as Dictionary).get("to_state", "")) == "SETTLEMENT":
				return true
	return false


## REELING 在 tick 之间可观测（每 tick 至多一步转换）。故障注入必须晚于 REELING 到达：
## cast 时 checkpoint 需正常落盘，否则 _save_error 先置位会冻结 tick 推进（引擎既有契约）。
func _tick_to_reeling(session) -> bool:
	for _step in 8:
		session.tick(120.0)
		if session.fsm().snapshot_checkpoint().get("state") == "REELING":
			return true
	return false


func _log_files(dir: String) -> Array:
	var names: Array = []
	var listing := DirAccess.open(dir)
	if listing == null:
		return names
	listing.list_dir_begin()
	var entry := listing.get_next()
	while entry != "":
		if not listing.current_is_dir() and _full_match(entry, FILE_PATTERN):
			names.append(entry)
		entry = listing.get_next()
	listing.list_dir_end()
	names.sort()  # fixed width ⇒ lexicographic == chronological
	return names


func _snapshot_texts(dir: String) -> Dictionary:
	var texts := {}
	for name in _log_files(dir):
		texts[String(name)] = _read_text(dir + String(name))
	return texts


func _read_lines(dir: String) -> Array:
	var rows: Array = []
	for name in _log_files(dir):
		for line in _split_lines(_read_text(dir + String(name))):
			rows.append(line)
	return rows


func _find_rows(lines: Array, event: String) -> Array:
	var rows: Array = []
	for raw in lines:
		var parsed: Variant = JSON.parse_string(String(raw))
		if parsed is Dictionary and String((parsed as Dictionary).get("event", "")) == event:
			rows.append(parsed)
	return rows


func _count_rows(lines: Array, event: String, severity: String, result: String, error_code: String) -> int:
	var count := 0
	for row in _find_rows(lines, event):
		if String((row as Dictionary).get("severity", "")) == severity \
				and String((row as Dictionary).get("result", "")) == result \
				and String((row as Dictionary).get("error_code", "")) == error_code:
			count += 1
	return count


func _split_lines(text: String) -> Array:
	return text.split("\n", false)  # Godot 4: allow_empty=false ⇒ 行尾换行不产生空元素


func _file_bytes(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length


func _full_match(text: String, pattern: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	var match_result: RegExMatch = regex.search(text)
	return match_result != null and match_result.get_string(0) == text


func _fresh_dir(label: String) -> String:
	var base := OS.get_temp_dir().trim_suffix("/")
	var path := base + "/log001_%s_%d_%d" % [label, Time.get_ticks_usec(), _dir_seq]
	_dir_seq += 1
	DirAccess.make_dir_recursive_absolute(path)
	_dirs.append(path)
	return path + "/"


func _cleanup_dirs() -> void:
	for path in _dirs:
		_remove_dir_recursive(path)
	_dirs.clear()


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path.path_join(entry)
		if dir.current_is_dir():
			_remove_dir_recursive(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	return file.get_error() == OK


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	return _fail(message)


func _fail(message: String) -> bool:
	print("LOG001 LOG FAIL: " + message)
	quit(1)
	return false
