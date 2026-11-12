# LOG-001 Phase B 执行报告（第 2 次尝试，串行、无子 Agent、无 git 写操作）

日期：2026-11-12 ｜ 计划：`tasks/evidence/LOG-001/plan.md` ｜ 结果：**全部通过（真实退出码 0）**

## 1. 改动文件清单（严格 = 工单允许范围）

| 文件 | 状态 | 本次尝试（第 2 次）的改动 |
|---|---|---|
| `scripts/io/event_log.gd` | 修改（本票交付物） | ① `JSON.stringify(line, "", false)`：Godot `JSON.stringify` 默认按 key 排序，破坏 L-1 固定键序合同；显式 `sort_keys=false` 后输出行按 `LINE_KEYS` 键序落盘。② `configure_dir` 对已存在普通文件占用目录路径时补 `DirAccess.open(normalized) == null ⇒ BAD_DIR` 兜底（Godot `make_dir_recursive_absolute` 对已存在文件返回 OK，属引擎怪癖，fail-closed 修正）。 |
| `scripts/ui/fishing_session.gd` | 修改（第 1 次尝试已接线，本次零改动） | 无新改动；`log_dir` seam、`log_health()`、各记录点与 plan §3.2 一致，经本次全量回归复验。 |
| `tests/unit/test_log001_log.gd` | 新建（本票交付物） | 修复 6 处测试缺陷（见 §3）：L-1 split 语义、L-4 前缀保持断言、L-6/L-7 故障注入时序、L-5/L-8 `status_view()` 的 `gold` 键与 sale-ID nonce 语义、L-8 HUD `_ready` 时序（`await process_frame`，与 UI-001 同法）。 |
| `tests/unit/run_log001_checks.py` | 新建（第 1 次尝试已建，本次零改动） | 无改动；preflight/隔离副本/隔离 HOME/import 先行/LOG+UI+SAVE+CORE 回归合同原样。 |

未触碰：`tasks/APPROVALS.md`（未读未改）、`tasks/TASKS.md`、`docs/**`、`scenes/**`、`project.godot`、`data/**`、`schemas/**`、`examples/**`、`tools/auto/queue.json`、`tasks/evidence/_runner/runner.log`、`tasks/evidence/UI-001/**`（后三者为调度器既有未提交改动，保持原样）。无 `.uid` 手工改动；真实工程路径从未被 Godot 打开（Godot 仅运行于运行器/调试的临时副本，调试副本已删除）。

## 2. 执行命令与真实退出码

| 命令（cwd=/Users/rain/DevGame/Fishing） | 退出码 | 结果 |
|---|---|---|
| `python3 -B tests/unit/run_log001_checks.py`（第 2 次尝试首跑，会话内直跑） | **0** | 末行 `LOG001 RUNNER PASS`，step1～step5 全 PASS |
| `python3 -B tests/unit/run_log001_checks.py > tasks/evidence/LOG-001/test-2.log 2>&1`（同命令复跑存档日志） | **0** | `test-2.log` 末行 `LOG001 RUNNER PASS` |

第 1 次尝试失败记录（既有证据）：`test-1.log` 末行 `EXIT=1`，失败点 `LOG001 LOG FAIL: L1 exactly one JSONL row`。

诊断过程（真实 Godot 运行，均发生在 mktemp 临时副本 + 隔离 HOME 内，非真实工程路径）：`dbg_log001.gd`（L-1 复现）、`dbg_l4.gd`（轮换/恢复字节级快照）、`dbg_l6.gd`（tick 事件流）、`dbg_l8*.gd`（BAD_DIR 与同 seed 对照）、`dbg_dir.gd`（DirAccess 对普通文件的行为实测：`make_dir_recursive_absolute`=OK、`dir_exists_absolute`=false、`DirAccess.open`=null）。每个失败均先以真实输出定位，再最小修复，逐条串行迭代直至 `LOG001 LOG PASS`。

## 3. 第 1 次尝试失败诊断 → 修复链（先诊断后修，未扩大范围）

1. **L-1 直接失败（test-1.log）**：`_split_lines` 用 `text.split("\n", true)` —— Godot 4 第二参是 `allow_empty`，`true`=保留空元素 ⇒ 行尾换行产生尾随 `""`，行数恒为 2。修复：`split("\n", false)`。同时实测发现 `JSON.stringify(dict)` 默认按键排序 ⇒ 源码改 `JSON.stringify(line, "", false)`（L-1 固定键序与 L-7 白名单合同要求）。
2. **L-4**：原断言要求重启追加必须落在同一文件（`begins_with`）；实测（dbg_l4）恢复侧正确地从最大序号文件恢复，该文件已满时按合同切下一个未占用序号并清理最旧文件——同为 append-only。断言改为：重启前后都存在的文件旧字节必须是现内容的前缀 + 追加行是新目录最新文件的末行 + 全部文件 ≤ max_bytes。
3. **L-6/L-7**：自动结算会话在单次 tick 内完成 SETTLEMENT 到达→落账→ack 回 IDLE（跨 tick 可见的 SETTLEMENT 依赖 UI-001 的 `manual_settlement` 开关，本票不开），快照轮询恒不等。改为以 `to_state=="SETTLEMENT"` 转换事件判定；故障注入移到 REELING 之后（cast 时 checkpoint 必须先正常落盘，否则 `_save_error` 先置位冻结 tick —— 引擎既有契约，dbg_l6 实测证实）。
4. **L-5/L-8**：断言误用 `wallet_gold` 键（`status_view()` 实际键为 `gold`，dbg_l8b 实测），且 `processed_sale_ids` 含每会话 Crypto nonce（`_next_sale_id`），跨会话字符串恒不等。修正为比 `gold`/`basket`/`revision`/捕获 ID 逐字段一致；售鱼账本 L-5（无售鱼，等值成立）保持等值、L-8 比数量+非空。
5. **L-8 日志目录被普通文件占用**：Godot 对已存在文件 `make_dir_recursive_absolute` 返回 OK 导致 `log_health().ok=true`（dbg_l8 实测）。源码补 `DirAccess.open == null ⇒ BAD_DIR` fail-closed 兜底，满足 L-8「boot 不受影响 + log_health 仅报 BAD_DIR」。
6. **L-8 HUD 复用断言**：`_initialize` 未先 `await process_frame` 时 `root.add_child(HUD)` 不触发 `_ready()`（与 UI-001 同法修复），横幅/重试按钮断言得以真实执行。

## 4. 测试输出摘要（test-2.log，exit 0）

- `step1-import` exit 0（隔离副本 import 先行，无 SCRIPT ERROR）
- `step2-log001` exit 0，stdout 恰一次 `LOG001 LOG PASS`（L-1…L-8 全断言）
- `step3-ui001` exit 0 `UI001 UI PASS`（UI-001 回归硬门禁）
- `step4-save001` exit 0 `SAVE001 SAVE PASS`（SAVE-001 回归）
- `step5-core001` exit 0 `CORE001 SMOKE PASS`（CORE-001 回归）
- 末行 `LOG001 RUNNER PASS`；preflight（value-lock、class_name 唯一锁、event_log.gd 静态无网络/环境 API 扫描）全过。

## 5. 覆盖的验收条目

- **V01-L01 / queue brief**：JSONL 本地有限日志（`user://logs/`，与存档目录隔离）、UTC 日期 + 单文件字节双条件轮换、`max_bytes≥512 / max_files≥1` 有界保留、字段白名单 8 键封闭枚举、事务 ID 入行、无网络 API（运行器静态扫描）——L-1/L-2/L-3/L-4/L-6。
- **T-LOG-01**：severity/event 封闭枚举；路径/自由文本/未知键零写入拒绝；行内无 `/`、`\`、`~`、空白文本，单行 ≤384 UTF-8 字节；无静默上传 —— L-1/L-2/L-7 + 静态扫描。
- **T-UI-01 / V01-S02**：存档失败留痕（`save_checkpoint_failed`/`PERSIST_FAILED` 行）且横幅+重试复用 UI-001 组件零改动（`SaveErrorBanner`/`SaveRetryButton`/`retry_requested` 实测可见可触发）；日志故障（log_dir 不可用）不触发横幅、不暂停经济、`log_health` 仅报码 —— L-5/L-8。
- **T-TIME-03 / 铁律**：同 seed 故障侧 vs 对照侧 gold/basket/revision/捕获账本逐字段一致，日志不产生新事务 —— L-5/L-8。
- **回归门禁**：UI-001 / SAVE-001 / CORE-001 在同一隔离副本内全量复跑通过（step3/4/5）。

## 6. 遗留风险与说明

- R-LOG-05（计划内）：UI-001 GUI 人工验收项仍 in_review，本票只主张 headless 自动面，不声称任何 GUI 通过。
- L-8 售鱼账本按数量比较是引擎合同使然（sale ID 内嵌每会话 Crypto nonce，跨会话等值无意义）；金额/鱼篓/revision/捕获 ID 仍逐字段一致，隐私与经济不变量强度不降。
- 时钟异常（BAD_CLOCK）与 LINE_TOO_LARGE 路径由源码 fail-closed 计数覆盖，L 矩阵未单独注入真实时钟故障（无法在 headless 稳定注入）；`set_utc_override` seam 仅测试使用。
- `tests/unit/test_log001_log.gd` 无 `.uid` sidecar 属预期：Phase B 不在真实工程启动 Godot 编辑器（CORE-001 证据 R 项约束），sidecar 由用户常驻编辑器/运行器副本 import 生成，不入库。
- `tasks/TASKS.md`/`docs/DEV_LOG.md` 的状态记录属调度器 Git 流程，本票允许文件范围不含二者，未改动。
- 未执行任何 git 写操作/提交；未读 `tasks/APPROVALS.md`；无子 Agent/后台任务；诊断用临时副本已全部删除。

PHASE-B-DONE

## Delegated reviewer follow-up — 2026-11-12

Final review found that a full last sequence (`999999`) could previously advance to a seven-digit filename, which the exact cleanup matcher intentionally ignored. `scripts/io/event_log.gd` now fails closed at that boundary, and `test_log001_log.gd` has an L-4b regression that verifies the existing bytes remain unchanged and no malformed filename is created. `tasks/evidence/LOG-001/test-3.log` records the complete import-first LOG/UI/SAVE/CORE regression, all exit 0 with exact PASS markers and no `SCRIPT ERROR`.

The runner made the original implementation commit `280ce3d`; the delegated review made `fd41f6b` for the boundary fix. Both are present on `origin/main`. The session report's earlier statement that the model made no Git write remains true for the model session; the scheduler committed its passing result automatically. LOG-001 is accepted under the owner's continuing delegation. The report's earlier GUI-pending note is superseded by the later UI-001 acceptance review.
