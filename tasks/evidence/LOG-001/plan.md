# LOG-001 Phase A 计划 — 本地有限日志 + 错误提示（只读规划）
- 每次捕获、出售、存档异常写结构化有限日志，不记录敏感活动；日志本地保留、轮换，无静默上传。
（上行为 AGENTS.md §4 第 40 行原文逐字引用，作为已读取项目规则的证明。）

- 工单：LOG-001（`tools/auto/queue.json`：status=ready，deps=SAVE-001+UI-001 均 Accepted/in_review，needs_human=false，test_cmd=`python3 -B tests/unit/run_log001_checks.py`）
- 本 Phase A 全程只读；唯一写入 = 本文件。未读、未改 `tasks/APPROVALS.md`；无任何 git 写操作；无子 Agent / 后台任务 / 并行工作流。
- Skills：`.dsh/skills/` 下 3 个项目 Skills 均存在；本票已加载 `fishing-state-and-save`、`godot-validation`（`godot-overlay` 属 GUI spike 专项，与本票 headless 日志范围无直接关系，仅记录已发现）。

## 1. 目标

补全 `scripts/io/event_log.gd`（当前仅 4 行骨架，`class_name EventLog` 已声明且全仓库仅此一处引用）并接入 `scripts/ui/fishing_session.gd`：

1. 在 `user://logs/` 本地生成 JSONL 结构化事件日志（每行一个 JSON 对象，一次事务一条），与存档文件分目录保存。
2. 按 **UTC 日期 + 单文件大小** 双条件轮换；保留文件数与单文件大小都有硬上限（有界保留）。
3. 记录字段白名单，仅允许：`timestamp_utc` / `severity` / `event` / `event_id` / `save_version` / `result` / `error_code` / `elapsed_ms`。绝不写路径、任意原因文本、按键、屏幕内容、其他 App 数据；实现中不出现任何网络 API，不上传。
4. 记录事件：成功捕获、成功售鱼、捕获失败、售鱼失败、存档读取/写入失败、配置校验失败（只记录固定事件和稳定错误码，不记录理由文本）。存档失败可见性复用 UI-001 已实现的 HUD 持久非模态横幅「存档失败：经济已暂停（可重试）」+「重试保存」按钮，本票不改任何 UI 文件。
5. 铁律：**日志任何故障（配置失败、写盘失败、时钟异常、轮换/清理失败）都不得改变经济事务结果**——不改变 `_save_error`/`_input_open`/GameState/EconomyService/FSM 的任何语义，不新增或丢失捕获/售鱼事件。

本票不新增需求：V01-L01 是 SDD_v0.1 已冻结 MUST（2026-11-11 委托审查冻结，REQUIREMENTS_CHANGELOG 已确认）；不改 20–60s、30 FPS、容量 10、价格、售鱼规则、schema、存档格式；无破坏性迁移；不联网。无需人工新批准。

## 2. 要改动的文件（严格 = 工单允许范围，Phase B 按此强制检查）

| 文件 | 改动 |
|---|---|
| `scripts/io/event_log.gd` | 实现 `EventLog`（保持 `class_name EventLog` + `extends RefCounted` 不变） |
| `scripts/ui/fishing_session.gd` | 仅追加日志装配与记录调用；不改已验收函数签名、返回形状与 `status_view()` 的既有键集（HUD/BasketMenu 因此零改动仍兼容） |
| `tests/unit/test_log001_log.gd` | 新建：headless 集成测试（`extends SceneTree`，唯一 PASS 标记 `LOG001 LOG PASS` / FAIL 标记 `LOG001 LOG FAIL`，与既有测试同风格） |
| `tests/unit/run_log001_checks.py` | 新建：Python 标准库隔离运行器（克隆 `run_ui001_checks.py` 模式：临时工程副本 + 隔离 HOME + import 先行 + 逐步门禁） |

禁止：改动 `run_ui001_checks.py` 的 DELIVERABLES/class-lock 清单（其 value-lock 原样保留）、`scripts/save/**`、`scripts/economy/**`、`scripts/core/**`、`scripts/ui/fishing_status_hud.gd`、`scenes/**`、`project.godot`、`data/**`、`schemas/**`、`examples/**`、`docs/**`、`tasks/**`（除本证据文件）、任何依赖或网络访问。Phase B 不手改 `.uid` 文件、不在真实工程路径启动 Godot 编辑器（用户常驻编辑器会重建 import sidecar，见 CORE-001 证据 R 项），不做 `git add -A`。

## 3. 接口与不变量

### 3.1 EventLog（scripts/io/event_log.gd）

公开 API（全部返回 `Dictionary`，形状 `{ok: bool, code: String}`）：

- `configure_dir(directory: String = "user://logs/", options: Dictionary = {}) -> Dictionary`
  - 测试注入显式日志目录（与 `AtomicSaveService.configure_dir` 同模式）；生产默认 `"user://logs/"`（INTERFACES §8，不硬编码源码树路径）。对 `user://` 路径先用 `ProjectSettings.globalize_path()` 转成本地目录再创建；成功后不得再次配置。
  - `options`：`max_bytes`（int，默认 262144，下限 512）、`max_files`（int，默认 5，下限 1）。输入必须类型严格正确，未知 option 拒绝。
  - 码：`OK` / `BAD_DIR` / `BAD_OPTIONS` / `ALREADY_CONFIGURED`（首次 `record()` 后拒绝重配）。目录用 `DirAccess.make_dir_recursive_absolute`；失败返回 ok:false，**由调用方忽略**。
- `record(rec: Dictionary) -> Dictionary`
  - 调用方输入仅可包含 7 个键：`severity`、`event`、`event_id`、`save_version`、`result`、`error_code`、`elapsed_ms`；`timestamp_utc` 由 EventLog 自己采样并添加，若调用方传入该键或任何未知键均返回 `BAD_KEYS`。输出行固定含 8 个白名单键。任一违规返回 ok:false + `BAD_KEYS`/`BAD_SEVERITY`/`BAD_EVENT`/`BAD_EVENT_ID`/`BAD_TIMESTAMP`/`BAD_RESULT`/`BAD_CODE`/`BAD_ELAPSED`/`BAD_CLOCK`，**零写入、不落半行**。
  - 校验规则（fail-closed）：`severity` 与 `event` 必填，其余调用方字段可省略并输出为 JSON `null`；timestamp 永远由 logger 生成。
    - `timestamp_utc`：`Time.get_datetime_string_from_system(true)` 每次记录仅取样 1 次，19 字符 + `Z`，复用 `FishInstance.timestamp_valid`（与 SAVE-001 同一判据）；非法 → 丢弃该条并计数（不编造时间）。
    - `severity` ∈ `info|warn|error`；`event` ∈ `catch_committed|catch_failed|sale_committed|sale_failed|save_checkpoint_failed|save_load_failed|config_invalid`（封闭枚举 → 结构上排除自由文本）；`result` ∈ `ok|already_applied|error`。
    - `event_id`：null 或 `^[A-Za-z0-9_-]{1,64}$`（兼容既有 `catch-<int>-<int>` 与 `sale-<hex32>-<int>`；含 `/`、空格、非 ASCII 一律拒绝 → 结构上排除路径与原因文本）。
    - `error_code`：null 或 `^[A-Z][A-Z0-9_]{0,31}$`（只放既有稳定码，如 `PERSIST_FAILED`/`CONFLICT_SALE_PARAMS`/`BASKET_FULL`/`GOLD_OVERFLOW`，不放句子）。
    - `save_version`：null 或非负 int；`elapsed_ms`：null 或非负 int（int64 内）。
    - 未知键 → `BAD_KEYS`。落盘行固定输出全部 8 键（缺省 null），键序固定，机器可解析。
  - 写盘：若文件存在则 `FileAccess.open(path, FileAccess.READ_WRITE)` 并 `seek_end()`，不存在才用 `FileAccess.WRITE` 新建，绝不以截断模式打开已有文件；`store_string(JSON.stringify(line) + "\n")` 后 `flush()` 并检查 `get_error()`。任何 IO 错误 → `{ok:false, code:"IO_FAILED"}` + 计数，**不抛出、不阻断调用方**。
- 轮换与有界保留（只在 append 时惰性执行，不逐帧、不定时器）：
  - 当前文件 = `event_log-YYYYMMDD-NNNNNN.jsonl`（UTC 日期 8 位数字；当日序号从 `000000` 起，固定宽度，确保字典序等于时间序）。每次启动时从严格匹配的当日文件中恢复最大序号，避免覆盖旧日志；如最大序号文件尚未满则继续追加，否则使用下一个未占用序号；若最大序号已满则失败关闭。
  - 若 `当前文件字节 + 新行 UTF-8 字节数 > max_bytes` → 先切下一个未占用序号再写 ⇒ 任一文件 ≤ `max_bytes`。单行超过上限则拒绝，不创建超限文件。
  - 每次 append 后按文件名降序保留最新 `max_files` 个文件，多余删除；**只删严格匹配 `^event_log-[0-9]{8}-[0-9]{6}\.jsonl$` 形状的文件**——`game_state.json`、`game_state.json.bak` 等存档文件永不成为清理目标（日志写入 `user://logs/`，与存档目录隔离；测试 L-4 仍放入诱饵文件断言清理范围）。
- `health() -> Dictionary`：`{ok, code, lines_written, lines_dropped, io_errors, files_pruned, max_bytes, max_files}` —— 只有计数器，无内容、无路径。
- 测试 seam：`set_utc_override(text: String)`（仅测试固定日期；空串清除；生产路径不调用）。
- 静态不变量：源码不出现 `HTTPClient|HTTPRequest|WebSocketPeer|WebRTCMultiplayerPeer|TCPServer|UDPServer|OS.get_env|OS.execute|OS.read_pipe|URL` 等网络/环境读取 API（运行器 preflight 静态扫描强制）；纯 `RefCounted`，无 Node/_process，不读写 `Engine.max_fps`，不触碰 `user://` 之外的绝对路径配置。

### 3.2 FishingSession 接入（scripts/ui/fishing_session.gd，仅追加）

- `start(options)` 新增**可选测试 seam** `log_dir`（默认 `"user://logs/"`，不提供禁用日志开关）。在配置校验前装配 `EventLog`，使配置失败也可记录；装配/配置失败仅记录 `log_health` 码，**boot 结果与 `input_open` 不受影响**（L-8 断言）。存档读取失败（主档/备份均不可用时）记 `save_load_failed`；合法的新档双缺失不记失败。
- 记录点（调用点全部忽略 EventLog 返回值，永不因其改变状态）：
  - `_finish_settlement` / `_replay_pending_candidate` 的 commit 结果：`ok且code==""` → `catch_committed/info/ok`；`ALREADY_APPLIED` → `catch_committed/warn/already_applied`；其余失败码 → `catch_failed/error/error`（`error_code`=码）。`elapsed_ms` = 结算开始（`_begin_settlement` 记 `Time.get_ticks_msec()` 起点）至 commit 返回的毫秒差。
  - `sell_selected` / `retry_persist` 售鱼结果：成功 → `sale_committed/info/ok`（**不记金币数额**）；失败（含 `PERSIST_FAILED`、`CONFLICT_SALE_PARAMS` 等）→ `sale_failed/error/error`。
  - `_persist_checked`、`_boot_fresh` 首 checkpoint 和存档目录配置失败 → `save_checkpoint_failed/error/error`，`event_id=null`（checkpoint 无事务 ID），`save_version` 取当前 `GameState.save_version`（若有）。配置校验失败 → `config_invalid/error/error`、稳定码 `CONFIG_INVALID`，不记录 parser reason；不可用/损坏存档 → `save_load_failed/error/error`，稳定码来自 loader 返回码、不记录 reason/path。
  - 每次失败事务各记一条（PERSIST_FAILED 重试序列逐条留痕），行数由 max_bytes/max_files 硬界兜底。
- 永不记录：`save_service.get_last_report()` 里的任何 reason/路径字段、boot 失败 reason 文本、金币数值、鱼种价格、按键/鼠标/窗口几何、屏幕或系统信息。
- 不变量保持（UI/SAVE/ECO-001 已验收语义零改动）：持久化门只在 bool true 后发布；`_save_error` 仅由**存档**失败置位（日志失败不置位）；tick/暂停/满篓/FPS/checkpoint 契约不变；`status_view()` 键集不增不减（HUD 零改动即复用横幅：save_error=true → 横幅+重试按钮已存在；重试仍走 `retry_persist()`）。EventLog 不进入 `_deny_if_closed`/tick/FPS/经济任何判定路径。

## 4. 精确测试命令与预期退出码

Phase B 在真实仓库根运行唯一入口（其余 Godot 命令只发生在运行器创建的临时副本内）：

```
python3 -B tests/unit/run_log001_checks.py          # 预期 exit 0，末行 LOG001 RUNNER PASS
```

运行器内部步骤（串行；每步检查退出码、stdout 唯一 PASS、无 FAIL 标记、全输出无 `SCRIPT ERROR`；副本排除 `.git/.godot/tasks/evidence/__pycache__`；HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME 指向临时 HOME；过滤敏感环境变量；finally 清理）：

| 步骤 | 命令（cwd=隔离副本） | 预期退出码 | 唯一 PASS 标记 |
|---|---|---|---|
| step1-import | `Godot --headless --path <copy> --editor --quit` | 0 | （无，仅导入） |
| step2-log001 | `Godot --headless --path <copy> --script res://tests/unit/test_log001_log.gd --quit-after 3600` | 0 | `LOG001 LOG PASS` |
| step3-ui001 | 同上，`--script res://tests/unit/test_ui001_ui.gd` | 0 | `UI001 UI PASS` |
| step4-save001 | 同上，`--script res://tests/unit/test_save001_save.gd` | 0 | `SAVE001 SAVE PASS` |
| step5-core001 | 同上，`--script res://tests/unit/test_core001_smoke.gd` | 0 | `CORE001 SMOKE PASS` |

任一步失败 → 运行器打印 `LOG001 RUNNER FAIL (<step>)` 并 `return 1`（预期 exit 1）。preflight（副本外只读）：交付物存在、UI-001 value-lock 全项、`class_name` 唯一性锁（`EventLog` 恰一处且位于 `scripts/io/event_log.gd`；`FishingSession/AtomicSaveService/SaveValidate/SaveFaults/SaveService` 唯一性与 SaveService 位置不变）、`event_log.gd` 静态无网络/无环境读取扫描。

`test_log001_log.gd` 断言矩阵（全部 IO 用显式临时子目录，绝不触碰真实 `user://`；固定 `rng_seed` + 虚拟时钟步长，逐事件可复现）：

- L-1 白名单形状：合法 7 键输入 → 恰好 1 行；回读 JSON 恰 8 键、timestamp 正则且由 logger 自己生成、severity/result 枚举、键序固定；传入 `timestamp_utc` 必须拒绝。
- L-2 非法拒绝：额外键、event 含 `/Users/x`、小写原因文本、负 elapsed_ms、未知 severity/event、非 int save_version → 全部 ok:false 且文件零字节增长。
- L-3 UTC 日轮换：`set_utc_override` 两天 → 两个文件 `event_log-<YYYYMMDD>-000000.jsonl`；行内日期==文件日期。
- L-4 大小轮换+保留界：max_bytes=512、max_files=3、同日 30 条 → 文件数 ≤3、每文件 ≤512B、最旧被清；重建 EventLog 后追加不得覆盖旧行；诱饵 `game_state.json` 与 `game_state.json.bak` 原样保留。
- L-5 存档失败留痕且不改变经济：固定 seed 装配 `rename` 故障 → `save_checkpoint_failed/error/PERSIST_FAILED` 行存在；清障 `retry_persist` 成功；同 seed 无故障对照会话对比 wallet/basket/processed ids 逐字段一致（日志不产生新事务）。
- L-6 捕获/售鱼成败四事件：tick 至 SETTLEMENT → `catch_committed`（event_id==request_cast 返回的 catch id）；售全部成功 → `sale_committed`（event_id==sale_id，行内无数值金额）；售鱼前装配 rename 故障 → `sale_failed/PERSIST_FAILED` 1 条 + 清障重试后 `sale_committed` 恰 1 条且金币恰加 1 次（幂等合同不变）。
- L-7 隐私静态面：扫描两会话产生的全部行——仅 8 白名单键、无值含 `/`、`user://`、`res://`、`~`、空白原因文本；行长度不超过 384 UTF-8 字节。
- L-8 日志故障零经济影响 + 横幅复用：`log_dir` 指向已存在的普通文件（不可成为目录）→ boot ok:true、`input_open=true`、`save_error=false`；完整捕获+售鱼序列与正常日志对照（同 seed）金币/鱼篓/revision 完全一致；`FishingStatusHUD.update_status({save_error:true})` → 横幅与重试按钮可见、`retry_requested` 信号可发（复用 UI-001 组件，证明未改 HUD 且横幅仍持久非模态）。

## 5. 风险与回滚

| 风险 | 处置 |
|---|---|
| R-LOG-01 改动已验收的 fishing_session.gd 引入回归 | 只追加、不改已验收函数体语义与 `status_view()` 键集；step3 UI001 回归作硬门禁 |
| R-LOG-02 日志 IO 拖慢结算路径 | 事件驱动 append，字段与长度均有硬上限，无逐帧写盘；轮换 O(max_files) |
| R-LOG-03 日志清理触及存档文件 | 日志使用 `user://logs/` 子目录，清理仅匹配 `event_log-YYYYMMDD-NNNNNN.jsonl` 严格形状；L-4 诱饵断言 |
| R-LOG-04 用户常驻 Godot 编辑器重建 import sidecar / 误提交范围外文件 | 只在隔离副本运行 Godot；提交只加白名单文件；禁 `git add -A`；`tasks/evidence/_runner/runner.log` 等既有未跟踪项不触碰 |
| R-LOG-05 UI-001 仍 in_review（GUI 人工项未完） | 本票仅 headless 自动面，不声称任何 GUI 通过；横幅复用为既有已实现代码 |
| R-LOG-06 UTC 时钟异常 | fail-closed 丢弃该条 + `health()` 计数，不编造时间戳 |
| R-LOG-07 PERSIST_FAILED 重试风暴撑爆日志 | 每次失败 1 行但由 max_bytes/max_files 硬界兜底（保留界即最终防线） |
| 回滚 | 单票单提交 `git revert` 即净移除（无 schema/配置/数据迁移需回退）；运行时残留仅 `user://logs/event_log-*.jsonl`（可手工删）与测试临时目录（finally 自动删）；存档文件零依赖故不影响 SAVE-001 恢复 |

## 6. 验收条目映射

| 验收条目 | 覆盖 |
|---|---|
| T-LOG-01（severity/event ID；不收按键/屏幕/其他 App；无自动上传） | L-1、L-2、L-3、L-7 + 运行器静态无网络扫描 |
| T-UI-01（保存失败可见、未持久化不显示已确认收入） | L-5、L-8：横幅+重试复用既有 HUD；日志失败不触发横幅/不暂停经济；发布门不变 |
| SDD V01-L01（本地结构化、事务 ID、大小/时间轮换有界） | L-1～L-4、L-6 |
| SDD V01-S02 / AGENTS §4（保存失败暂停+日志异常留痕、无静默上传） | L-5、L-6、L-8 + 静态扫描 |
| T-TIME-03（不新增捕鱼事件） | L-5/L-8 同 seed 对照逐事件一致 |
| queue brief（JSONL、UTC 日期+大小轮换、字段白名单、经济事务不受日志故障影响、临时副本+隔离 HOME+import 先行+LOG/UI/SAVE/CORE 回归） | §3 全节 + §4 全部步骤 |

## 9. 委托审查修订与批准

Phase A 初稿审查发现并已修正以下歧义：统一日志名为 `event_log-YYYYMMDD-NNNNNN.jsonl`，并将清理正则统一为 `^event_log-[0-9]{8}-[0-9]{6}\.jsonl$`；输入不接受调用方提供的 timestamp，输出 timestamp 由 logger 生成；跨重启恢复当日最大序号，避免覆盖日志；日志目录改为与存档分离的 `user://logs/`；移除可禁用日志的测试开关；明确 Godot 的追加文件打开顺序和 UTF-8 字节限制。另补入 SDD 配置错误与不可用存档的安全事件记录，均不含 reason/path 原文。

自动审批依据：项目所有者持续执行授权（`docs/REQUIREMENTS_CHANGELOG.md`、`tasks/APPROVALS.md` 既有委托记录，并由本轮明确要求自动审批）。范围严格为队列白名单，不改变冻结的 v0.1 功能/数据/经济约束。审核结果：Phase B 批准，执行前置仍为队列 Phase B 批准哈希核验与全套测试。

## 7. Phase A 只读实测记录（2026-11-12，均在本会话执行）

| 命令 | 退出码 | 事实 |
|---|---|---|
| `find . \( -path ./.git -o -path ./.godot \) -o -type f -print` 全清单 | 0 | 工程含 scripts/io/event_log.gd（4 行骨架）、scripts/ui/fishing_session.gd（611 行）等；`tests/unit/` 已有 CFG/CORE/ECO/FSM/SAVE/UI 六套测试与 5 个 run_*_checks.py |
| `git status --porcelain=v1` | 0 | 仅既有未跟踪证据/`runner.log` 修改/`runner.lock`（非本票造成，保持不动）；tracked 源码干净 |
| `git log --oneline -8` | 0 | HEAD=`ec89eb8` "Queue LOG-001 for delegated planning"；分支 `main`；无远端推送操作 |
| `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| `cat scripts/io/event_log.gd` / `cat scenes/main.tscn` / `cat tools/auto/queue.json` | 0 | EventLog 全仓仅 1 处 class_name 引用（自身文件）；LOG-001 队列条目 allowed_files/test_cmd 与本计划 §2/§4 一致 |
| `grep EventLog`、`grep "catch-%d" FSM`、`grep codes economy` | 0 | catch ID 形状 `catch-<int>-<int>`、sale ID `sale-<hex32>-<int>`、经济稳定错误码清单 → §3.1 校验正则据此确定 |
| `ls -ld tasks/evidence/LOG-001` | 0 | 空目录已存在（调度器创建），本票未 mkdir |
| 文档阅读：AGENTS/SDD/DECISION/ARCHITECTURE/INTERFACES/ACCEPTANCE/TECH_SPIKE/DEV_LOG/HARNESS_LOCAL_SETUP/REQUIREMENTS_CHANGELOG/TASKS(LOG-001 段+队列表) | 0（只读） | `tasks/APPROVALS.md` 未读取、未修改；无 git 写、无安装、无网络 |

## 8. 结束判定

本票 = 已冻结 v0.1 MUST（V01-L01/SDD-174）的实现票：不改需求边界、不改经济参数、不做破坏性存档迁移、不联网、允许文件范围即队列既定保守清单，无需新人工批准 → 正常进入 Phase B（按 §2 范围 + §4 命令执行）。

PHASE-A-DONE
