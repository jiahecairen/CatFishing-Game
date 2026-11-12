class_name EventLog
extends RefCounted
# LOG-001 实现：捕获 / 出售 / 存档异常的结构化有限本地日志（plan §3.1、SDD V01-L01）。
# 合同：
# - JSONL 追加写（每行一个 JSON 对象，一次事务一条），落 user://logs/ 本地目录，与存档目录
#   隔离；任何 IO 故障 fail-closed 返回稳定码，不抛出、不阻断、绝不改变调用方的经济事务结果。
# - 字段白名单：输入仅允许 severity/event/event_id/save_version/result/error_code/elapsed_ms
#   七个键（调用方提供 timestamp_utc 或任何未知键 → BAD_KEYS 零写入）；timestamp_utc 永远由
#   本类采样一次生成，输出行固定含 8 个白名单键、键序固定，机器可解析。
# - severity/event/result/error_code/event_id 全部封闭枚举或稳定 ID 形状正则，结构上排除自由
#   文本、路径与原因句；本类不记录任何敏感活动，也不含任何网络/环境读取 API。
# - 轮换：文件名 event_log-YYYYMMDD-NNNNNN.jsonl（UTC 日期 + 当日固定宽度序号，字典序==时间
#   序）；UTC 日切换或字节上限触发切换未占用序号；单行超上限拒绝，任一文件 ≤ max_bytes。
#   每次 append 后按文件名降序保留最新 max_files 个，多余删除；只删严格匹配该文件名的文件，
#   存档文件永不成为清理目标。轮换与清理仅在 append 时惰性执行，不逐帧、不定时器。
# 不变量：纯 RefCounted——无 Node/_process、无定时器、不读写 res://、不触网；生产默认目录
# user://logs/（INTERFACES §8 不落源码树）；测试注入显式临时目录，绝不触碰真实 user://。

const DEFAULT_DIR := "user://logs/"
const DEFAULT_MAX_BYTES := 262144
const MIN_MAX_BYTES := 512
const DEFAULT_MAX_FILES := 5
const MIN_MAX_FILES := 1
const FILE_PREFIX := "event_log-"
const FILE_SUFFIX := ".jsonl"

const SEVERITY_INFO := "info"
const SEVERITY_WARN := "warn"
const SEVERITY_ERROR := "error"
const RESULT_OK := "ok"
const RESULT_ALREADY_APPLIED := "already_applied"
const RESULT_ERROR := "error"
const EVENT_CATCH_COMMITTED := "catch_committed"
const EVENT_CATCH_FAILED := "catch_failed"
const EVENT_SALE_COMMITTED := "sale_committed"
const EVENT_SALE_FAILED := "sale_failed"
const EVENT_SAVE_CHECKPOINT_FAILED := "save_checkpoint_failed"
const EVENT_SAVE_LOAD_FAILED := "save_load_failed"
const EVENT_CONFIG_INVALID := "config_invalid"

const CODE_OK := "OK"
const CODE_BAD_DIR := "BAD_DIR"
const CODE_BAD_OPTIONS := "BAD_OPTIONS"
const CODE_ALREADY_CONFIGURED := "ALREADY_CONFIGURED"
const CODE_NOT_CONFIGURED := "NOT_CONFIGURED"
const CODE_BAD_KEYS := "BAD_KEYS"
const CODE_BAD_SEVERITY := "BAD_SEVERITY"
const CODE_BAD_EVENT := "BAD_EVENT"
const CODE_BAD_EVENT_ID := "BAD_EVENT_ID"
const CODE_BAD_TIMESTAMP := "BAD_TIMESTAMP"
const CODE_BAD_RESULT := "BAD_RESULT"
const CODE_BAD_CODE := "BAD_CODE"
const CODE_BAD_ELAPSED := "BAD_ELAPSED"
const CODE_BAD_SAVE_VERSION := "BAD_SAVE_VERSION"
const CODE_BAD_CLOCK := "BAD_CLOCK"
const CODE_IO_FAILED := "IO_FAILED"
const CODE_LINE_TOO_LARGE := "LINE_TOO_LARGE"

const CALLER_KEYS := ["severity", "event", "event_id", "save_version", "result", "error_code", "elapsed_ms"]
const LINE_KEYS := ["timestamp_utc", "severity", "event", "event_id", "save_version", "result", "error_code", "elapsed_ms"]
const SEVERITY_ENUM := [SEVERITY_INFO, SEVERITY_WARN, SEVERITY_ERROR]
const RESULT_ENUM := [RESULT_OK, RESULT_ALREADY_APPLIED, RESULT_ERROR]
const EVENT_ENUM := [EVENT_CATCH_COMMITTED, EVENT_CATCH_FAILED, EVENT_SALE_COMMITTED, EVENT_SALE_FAILED,
		EVENT_SAVE_CHECKPOINT_FAILED, EVENT_SAVE_LOAD_FAILED, EVENT_CONFIG_INVALID]
const EVENT_ID_PATTERN := "^[A-Za-z0-9_-]{1,64}$"
const ERROR_CODE_PATTERN := "^[A-Z][A-Z0-9_]{0,31}$"
const FILE_NAME_PATTERN := "^event_log-([0-9]{8})-([0-9]{6})\\.jsonl$"

var _configured := false
var _dir := ""
var _max_bytes := DEFAULT_MAX_BYTES
var _max_files := DEFAULT_MAX_FILES
var _utc_override := ""  # 仅测试固定日期；空串清除；生产路径不设置
var _cur_date := ""
var _cur_seq := -1
var _cur_size := 0
var _lines_written := 0
var _lines_dropped := 0
var _io_errors := 0
var _files_pruned := 0


## 配置日志目录与上限（plan §3.1）。options：max_bytes（int，默认 262144，下限 512）、
## max_files（int，默认 5，下限 1）；类型严格，未知 option 拒绝。user:// 路径先
## globalize_path 转本地目录再创建。首次 record 后不得重配。码：OK/BAD_DIR/BAD_OPTIONS/
## ALREADY_CONFIGURED；失败由调用方忽略，绝不改变调用方状态。
func configure_dir(directory: String = DEFAULT_DIR, options: Dictionary = {}) -> Dictionary:
	if _configured:
		return _fail(CODE_ALREADY_CONFIGURED)
	if directory.is_empty():
		return _fail(CODE_BAD_DIR)
	var max_bytes := DEFAULT_MAX_BYTES
	var max_files := DEFAULT_MAX_FILES
	for key in options:
		if not _option_keys_valid(key, options[key]):
			return _fail(CODE_BAD_OPTIONS)
	if options.has("max_bytes"):
		max_bytes = int(options["max_bytes"])
		if max_bytes < MIN_MAX_BYTES:
			return _fail(CODE_BAD_OPTIONS)
	if options.has("max_files"):
		max_files = int(options["max_files"])
		if max_files < MIN_MAX_FILES:
			return _fail(CODE_BAD_OPTIONS)
	var localized := directory
	if localized.begins_with("user://"):
		localized = ProjectSettings.globalize_path(localized)
	if localized.is_empty():
		return _fail(CODE_BAD_DIR)
	var normalized := localized if localized.ends_with("/") else localized + "/"
	if DirAccess.make_dir_recursive_absolute(normalized) != OK:
		return _fail(CODE_BAD_DIR)
	# Godot 对「已存在的普通文件」路径 make_dir_recursive_absolute 仍返回 OK；显式开目录
	# 兜底：开不了 ⇒ BAD_DIR（L-8：日志目录被普通文件占用时 fail-closed，零写入）。
	if DirAccess.open(normalized) == null:
		return _fail(CODE_BAD_DIR)
	_dir = normalized
	_max_bytes = max_bytes
	_max_files = max_files
	_configured = true
	return {"ok": true, "code": CODE_OK}


## 测试 seam：固定 UTC 时间戳（仅测试；空串清除；生产路径不调用）。
func set_utc_override(text: String) -> void:
	_utc_override = text


## 追加一条结构化事件（plan §3.1）。校验 fail-closed：任一违规 ok:false + 稳定码，
## 零写入、不落半行；IO 故障 ok:false + IO_FAILED + 计数。调用方必须忽略返回值且
## 绝不因其改变经济事务（LOG-001 铁律，由 FishingSession 调用点与 L-5/L-8 断言保证）。
func record(rec: Variant) -> Dictionary:
	if not _configured:
		return _fail(CODE_NOT_CONFIGURED)
	if not (rec is Dictionary):
		return _fail(CODE_BAD_KEYS)
	var rec_dict: Dictionary = rec
	for key in rec_dict:
		if not CALLER_KEYS.has(key):
			return _fail(CODE_BAD_KEYS)  # 含调用方自带 timestamp_utc / 任何未知键
	var severity: Variant = rec_dict.get("severity", null)
	if not (severity is String) or not SEVERITY_ENUM.has(severity):
		return _fail(CODE_BAD_SEVERITY)
	var event: Variant = rec_dict.get("event", null)
	if not (event is String) or not EVENT_ENUM.has(event):
		return _fail(CODE_BAD_EVENT)
	var result: Variant = rec_dict.get("result", null)
	if result != null and not (result is String and RESULT_ENUM.has(result)):
		return _fail(CODE_BAD_RESULT)
	var event_id: Variant = rec_dict.get("event_id", null)
	if event_id != null and not (event_id is String and _full_match(event_id, EVENT_ID_PATTERN)):
		return _fail(CODE_BAD_EVENT_ID)
	var error_code: Variant = rec_dict.get("error_code", null)
	if error_code != null and not (error_code is String and _full_match(error_code, ERROR_CODE_PATTERN)):
		return _fail(CODE_BAD_CODE)
	var save_version: Variant = rec_dict.get("save_version", null)
	if not _nullable_int_valid(save_version):
		return _fail(CODE_BAD_SAVE_VERSION)
	var elapsed_ms: Variant = rec_dict.get("elapsed_ms", null)
	if not _nullable_int_valid(elapsed_ms):
		return _fail(CODE_BAD_ELAPSED)
	var timestamp := _sample_utc()
	if timestamp.is_empty():
		_lines_dropped += 1  # 时钟异常 fail-closed 丢弃该条，绝不编造时间（R-LOG-06）
		return _fail(CODE_BAD_CLOCK)
	var line := {
		LINE_KEYS[0]: timestamp,
		LINE_KEYS[1]: severity,
		LINE_KEYS[2]: event,
		LINE_KEYS[3]: event_id,
		LINE_KEYS[4]: save_version,
		LINE_KEYS[5]: result,
		LINE_KEYS[6]: error_code,
		LINE_KEYS[7]: elapsed_ms,
	}
	var text := JSON.stringify(line, "", false) + "\n"  # sort_keys=false ⇒ 固定键序==LINE_KEYS
	var line_bytes := text.to_utf8_buffer().size()
	if line_bytes > _max_bytes:
		_lines_dropped += 1  # 单行超上限：拒绝，不创建超限文件
		return _fail(CODE_LINE_TOO_LARGE)
	if _advance_file(_date_key(timestamp), line_bytes).is_empty():
		_io_errors += 1
		return _fail(CODE_IO_FAILED)
	var write_error := _append_line(_dir + FILE_PREFIX + _cur_date + "-%06d" % _cur_seq + FILE_SUFFIX, text)
	if not write_error.is_empty():
		_io_errors += 1
		return _fail(CODE_IO_FAILED)
	_lines_written += 1
	_cur_size += line_bytes
	_prune()
	return {"ok": true, "code": ""}


## 只读健康度：只有计数器与配置上限，无内容、无路径（plan §3.1）。
func health() -> Dictionary:
	var configured_ok := _configured
	var io_ok := _io_errors == 0
	return {
		"ok": configured_ok and io_ok,
		"code": CODE_NOT_CONFIGURED if not configured_ok else (CODE_IO_FAILED if not io_ok else ""),
		"lines_written": _lines_written,
		"lines_dropped": _lines_dropped,
		"io_errors": _io_errors,
		"files_pruned": _files_pruned,
		"max_bytes": _max_bytes,
		"max_files": _max_files,
	}


# ---- 内部：轮换 / 清理 ----

## 定位当前可写文件：UTC 日切换（或首次）时从严格匹配的当日文件中恢复最大序号，避免覆盖
## 旧日志；当前文件字节 + 新行字节 > max_bytes 时切换到下一个未占用序号（最大序号已满即
## 停止写入满文件 ⇒ 任一文件 ≤ max_bytes）。失败（目录不可开）返回 ""。
func _advance_file(date8: String, line_bytes: int) -> String:
	if date8 != _cur_date or _cur_seq < 0:
		var restored := _max_existing_seq(date8)
		_cur_date = date8
		_cur_seq = restored if restored >= 0 else 0
		_cur_size = 0
	var path := _dir + FILE_PREFIX + _cur_date + "-%06d" % _cur_seq + FILE_SUFFIX
	var size := _size_of(path)
	while size >= 0 and size + line_bytes > _max_bytes:
		_cur_seq += 1
		path = _dir + FILE_PREFIX + _cur_date + "-%06d" % _cur_seq + FILE_SUFFIX
		size = _size_of(path)
	_cur_size = size if size >= 0 else 0
	return path


func _max_existing_seq(date8: String) -> int:
	var dir := DirAccess.open(_dir)
	if dir == null:
		return -1
	var max_seq := -1
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and _matches_file_shape(entry, date8):
			var seq := entry.substr(FILE_PREFIX.length() + 9, 6).to_int()
			if seq > max_seq:
				max_seq = seq
		entry = dir.get_next()
	dir.list_dir_end()
	return max_seq


func _matches_file_shape(entry: String, date8: String) -> bool:
	if not _full_match(entry, FILE_NAME_PATTERN):
		return false
	return entry.substr(FILE_PREFIX.length(), 8) == date8


## "YYYY-MM-DDTHH:MM:SSZ" → 8 位 UTC 日期键 "YYYYMMDD"（文件名字典序==时间序）。
func _date_key(timestamp: String) -> String:
	return timestamp.substr(0, 4) + timestamp.substr(5, 2) + timestamp.substr(8, 2)


## 有界保留：按文件名降序（固定宽度 ⇒ 字典序==时间序）保留最新 max_files 个，多余删除；
## 只删严格匹配 event_log 文件名形状的文件，存档文件永不成为清理目标（R-LOG-03）。
func _prune() -> void:
	var dir := DirAccess.open(_dir)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and _full_match(entry, FILE_NAME_PATTERN):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	if names.size() <= _max_files:
		return
	names.sort_custom(func(a, b): return String(a) > String(b))
	for index in range(_max_files, names.size()):
		if DirAccess.remove_absolute(_dir + names[index]) == OK:
			_files_pruned += 1


# ---- 内部：文件 / 时钟 / 校验原语 ----

## 追加写：存在则 READ_WRITE + seek_end（绝不以截断模式打开已有文件）；不存在才 WRITE 新建。
func _append_line(path: String, text: String) -> String:
	var exists := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return "open failed (%s)" % error_string(FileAccess.get_open_error())
	if exists:
		file.seek_end()
	file.store_string(text)
	file.flush()  # Godot 4 的 flush() 返回 void，错误经 get_error() 报告
	var io_error := file.get_error()
	file.close()
	return "" if io_error == OK else "write failed (%s)" % error_string(io_error)


func _size_of(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var length := file.get_length()
	file.close()
	return length


## UTC 仅采样一次（19 字符 + Z，SAVE-001 同判据 FishInstance.timestamp_valid）；非法
## 返回 ""，由调用方丢弃该条，不编造时间。
func _sample_utc() -> String:
	if not _utc_override.is_empty():
		return _utc_override if FishInstance.timestamp_valid(_utc_override) else ""
	var text := Time.get_datetime_string_from_system(true)
	if text.length() != 19 or not FishInstance.timestamp_valid(text + "Z"):
		return ""
	return text + "Z"


func _nullable_int_valid(value: Variant) -> bool:
	if value == null:
		return true
	return value is int and int(value) >= 0


func _option_keys_valid(key: Variant, value: Variant) -> bool:
	if not (key is String) or not (value is int):
		return false
	return String(key) == "max_bytes" or String(key) == "max_files"


func _full_match(text: Variant, pattern: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	var match_result: RegExMatch = regex.search(String(text))
	return match_result != null and match_result.get_string(0) == String(text)


func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}
