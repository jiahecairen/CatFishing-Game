# CORE-001 Phase B 执行报告（AUTO-001 · 第 2 次尝试 · 2026-11-11）

> 本文件覆盖第 1 次尝试的同名报告（其原文仍可在归档会话 `phaseB-1.session.v4.jsonl.zstd` 与 `phaseB-1.out` 中审计）。

- **单 Agent 串行**：本尝试全程单会话串行；未调用子 Agent / 委派 / fork / 并行工作流 / 后台任务。
- 未读取、未修改 `tasks/APPROVALS.md`；未新增任何批准记录。
- 未执行 git commit / merge / push / stash / reset / clean（仅只读 `git status` / `git diff` / `git ls-files` / `git log`）。
- AGENTS.md 已核对遵守；Skills 经 skill 工具实际加载：`godot-validation`、`fishing-state-and-save`（`godot-overlay` 属 UI-001 窗口票，本票不适用）。
- 遵守计划 §9 人工补充 6 条：仅骨架、spike 原样、30 FPS 不声称拖动 60、真实加载+smoke 并确认 `CORE001 SMOKE PASS` 与无 SCRIPT ERROR、`.gdignore` 隔离且不破坏 spike 独立工程结构、人工批准门禁由调度器核对。

## 0. 上次失败（attempt 1）根因诊断 —— 先诊断再修

runner 日志（`tasks/evidence/_runner/runner.log` 2026-11-11T02:38:04）：

```text
CORE-001 test attempt 1 exit=0
CORE-001 attempt 1 失败 test_rc=0 session_rc=0 越界=[('??', 'icon.svg.import', '超出 allowed_files')]
```

**测试本身真实通过**（`test-1.log`：`CORE001 SMOKE PASS`，EXIT=0）。失败原因是**范围检查**判仓库根 `icon.svg.import`（Godot 首次完整项目扫描自动生成的导入缓存工件，untracked、不在 allowed_files、不被 `ignored()` 豁免——`ignored()` 仅豁免 `.pyc`/`__pycache__`/`.godot`）越界。

本尝试用一次性 `/tmp` 拷贝（含真实 `.godot/` 全量缓存）做对照实验（不触碰真实工作树）：

| 实验 | 结果 |
|---|---|
| 删除拷贝的 `icon.svg.import` 后跑 `--headless --path <copy> --script res://tests/unit/test_core001_smoke.gd`（冷缓存） | 退出码 0；**不再生成** `icon.svg.import` |
| 同上但拷贝带**真实项目 `.godot/`**（热缓存，runner test_cmd 的真实场景） | 退出码 0，输出 `CORE001 SMOKE PASS`；**不再生成** `icon.svg.import` |
| 本尝试真实工作树：删除 `icon.svg.import` 后再跑 test_cmd | 退出码 0，PASS，`icon.svg.import` 未重建（见 `phaseB-2-test-run.log`） |

结论：`-s` 测试本身**不会**生成/重建 `icon.svg.import`（三组对照均证）。但随后发现**决定性环境事实**：用户机器当前有 **Godot GUI 编辑器进程正打开本工程**（`pgrep` 实测 PID 27116：`/Applications/Godot.app/Contents/MacOS/Godot /Users/rain/DevGame/Fishing/project.godot`），其文件系统监视器会周期性重扫描——本会话 02:52/02:53 两次实测删除后文件不存在，02:54:42 被编辑器自动重建（`icon.svg.import` 与 `.godot/editor/filesystem_cache10`、`.godot/uid_cache.bin`、`.godot/imported` 的 mtime 同为 02:54:42，取证一致；也解释 attempt 1 中 02:37 删除后 02:38 检查时文件复现）。**只要编辑器保持打开，本会话内任何删除都会在分钟内被撤销**，该项越界在本会话权限内无法永久消除（终止用户进程属越界高危操作，禁止）。

**诊断中发现的第 2 个越界项，本 Agent 无权修复**（attempt 2 的 scope 检查用 runner 自身代码模拟，实测输出）：

```text
(' M', 'tools/auto/queue.json', '超出 allowed_files')
('??', 'icon.svg.import', '超出 allowed_files')   # ← 删除后被常驻编辑器分钟级重建，见下
```

`tools/auto/queue.json` 是**调度器自有**状态文件（runner.py 注释自认 RUNNER_OWNED 含 queue），但其豁免条件为 `untracked and path.startswith(RUNNER_OWNED)`；attempt 1 失败后 runner 自己 `save_q` 写入 `retries=1` 使该**已跟踪**文件呈 ` M`，永远命不中 untracked 豁免。它由 runner 在 attempt 1 会话后弄脏，attempt 2/3 的 scope 检查必然再次判定它越界 → 即使工单代码与测试完全正确也会被冻结。`tools/**` 不在本票允许清单，git commit 亦被禁止，故**唯一残留阻断项在调度器侧，需人工处置**（见 L-0）。

## 1. 改动文件清单

### 工单交付文件（attempt 1 按批准计划新建；本尝试逐一通读核对，**与批准计划 §3/§9 完全一致，零改动**）

| 文件 | 核对结论 |
|---|---|
| `project.godot` | `config_version=5`；`run/main_scene="res://scenes/main.tscn"`、`run/max_fps=30`（SDD-175）、`config/icon="res://icon.svg"`；无窗口透明/穿透设置（UI-001） |
| `icon.svg` | 最小合法占位 SVG（临时素材） |
| `scenes/main.tscn` | format=3；根 `Main`（Node2D）挂 `game_controller.gd`，子节点占位 Label；无业务逻辑 |
| `scripts/core/game_controller.gd` | `_ready` 仅创建 GameState 并打印初始化行 |
| `scripts/core/game_state.gd` | 唯一权威账本纯数据骨架：`save_version=1, revision=0, wallet_gold=0, basket_capacity=10(候选), basket, processed_catch_ids, processed_sale_ids, fishing_checkpoint, desktop_window`；零事务实现 |
| `scripts/core/fishing_system.gd` | 仅 `enum State {IDLE,CASTING,WAITING,HOOKED,REELING,SETTLEMENT,PAUSED}` + 契约注释；无转移实现 |
| `scripts/io/{config_loader,save_service,event_log}.gd`、`scripts/platform/{platform_adapter,desktop_window}.gd`、`scripts/presentation/cat_presenter.gd` | 空骨架 + 契约注释，零实现（CFG/SAVE/LOG/UI-001 分票落实） |
| `tests/spike/.gdignore` | 空文件；位于 spike 工程根**之外**，根工程跳过 `tests/spike/**`，spike 独立工程结构不受影响（人工补充 §5） |
| `tests/unit/test_core001_smoke.gd` | `extends SceneTree`：逐文件 load → 主场景实例化断言（Node2D 名 `Main`）→ GameState 默认值断言 → PASS/`quit(0)`，失败 FAIL+`quit(1)` |

### 本尝试实际写入/删除

| 操作 | 文件 | 性质 |
|---|---|---|
| 删除（临时） | `icon.svg.import`（仓库根） | **引擎生成工件**（非用户内容，attempt 1 测试运行所生成）。本会话两次删除均成功，但**常驻 Godot 编辑器的文件系统监视器于 02:54:42 自动重建**（§0 取证）。会话结束时该文件在树内——非本 Agent 留存改动，而是用户实时进程的环境工件；结束本会话前的 scope 模拟仍判其越界，见 L-0/L-1 |
| 删除 | `tools/auto/__pycache__/runner.cpython-315.pyc` | 本会话用 runner 真实代码做 scope 模拟时由解释器生成的缓存，即时自清 |
| 新建 | `tasks/evidence/CORE-001/report.md`（本文件）、`phaseB-2-test-run.log` | 证据目录，工单允许 |

**未写入（允许清单外，如实声明）**：`tools/auto/queue.json`（调度器自有，本 Agent 未触碰）、`tasks/TASKS.md`、`docs/DEV_LOG.md`（工单最高约束的允许清单优先；AGENTS.md §3 的状态记录由调度器 `commit_success` 自动写入）、`.gitignore`、`tasks/APPROVALS.md`。

## 2. 本尝试真实执行命令与退出码（cwd=仓库根，除注明外）

| # | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 1 | `…Godot --headless --path /Users/rain/DevGame/Fishing --script res://tests/unit/test_core001_smoke.gd`（工单指定命令） | **0** | `CORE001 SMOKE PASS`；stdout/stderr `SCRIPT ERROR` 计数=0 |
| 2 | 同上第二次（删除 `icon.svg.import` 后，模拟 runner attempt-2 序列） | **0** | `CORE001 SMOKE PASS`；`icon.svg.import` 未重建；日志 `phaseB-2-test-run.log` |
| 3 | `/tmp` 拷贝对照实验 ×3（§0：冷/热缓存 `-s` 运行是否重建 `.import`） | 0/0/0 | 均不重建；冷缓存下另见 L-3 现象（`.godot` 缺失时 `-s` 解析 `GameState` 失败但退出码仍为 0） |
| 4 | 用 `tools/auto/runner.py` 真实代码模拟 attempt-2 scope 检查（只读，删除后又运行一次） | 0 | 越界=queue.json（本 Agent 不可修，L-0）+ icon.svg.import（编辑器常驻监视下持续重建，L-1） |
| 5 | `git status --porcelain=v1 --untracked-files=all` / `git diff --stat` / `git ls-files --error-unmatch tools/auto/queue.json` | 0 | 工作树仅剩允许清单内新建文件 + ` M tools/auto/queue.json`（runner 自身所致）；`tests/spike/overlay/**` 含 3 个 report JSON 零改动 |

### 测试输出摘要（命令 #2 原样，完整见 phaseB-2-test-run.log）

```text
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

CORE001 SMOKE PASS
CORE001 GameController ready: wallet_gold=0 basket=0 basket_capacity=10
AGENT_TEST_EXIT=0
```

`SCRIPT ERROR` 计数 = **0**（人工补充 §4）。stderr 有 2 行引擎自身 `ERROR:`（`Failed to open log file for writing: user://logs/godot.log`），系本会话文件沙箱拒写 `~/Library/Application Support/Fishing/` 的环境工件，非工程错误，不影响退出码与断言（真实人工 shell 下不出现）。

## 3. 覆盖的验收条目（均有上表真实证据）

| 来源 | 条目 | 满足方式 |
|---|---|---|
| TASKS.md CORE-001 最小验收 | Godot 无语法/导入错误 | #1/#2 退出码 0 + `CORE001 SMOKE PASS` + 无 SCRIPT ERROR；smoke 逐文件 load 全部骨架与主场景 |
| CORE-001 交付 | 主场景 | `scenes/main.tscn` + `run/main_scene`；attempt 1 已用 `--quit-after 2` 真实加载运行（report 归档），本尝试经 smoke 实例化验证 |
| CORE-001 交付 | 分层模块骨架 | `scripts/{core,io,platform,presentation}/` 按 ARCHITECTURE §7 落位，零实现，契约注释指向后续票 |
| CORE-001 交付 | headless 自动测试基础 | `tests/unit/test_core001_smoke.gd` 真实通过 |
| 人工补充 §1/§3 | 不提前实现 FSM/经济/存档/UI；不声称拖动 60 FPS | 骨架仅 class_name/字段/enum/注释；`run/max_fps=30` 未动批准值 |
| 人工补充 §2 | spike 与 GUI 报告原样 | `git status` 证实 spike 目录零改动（含 3 个 report JSON）；未重跑 spike |
| 人工补充 §4 | 真实加载 + 确认 PASS 字符串 + 无 SCRIPT ERROR | §2 实测 |
| 人工补充 §5 | 不误扫描 spike、不破坏其独立工程 | `tests/spike/.gdignore` 在 spike 工程根之外；测试输出无 spike 相关解析错误 |
| 人工补充 §6 | 保留人工批准门禁 | 批准由调度器核对（`2086cf9`）；本 Agent 未新增批准、未读账本 |
| ACCEPTANCE_TESTS §6 | headless 通过 + 命令/退出码/日志留证 | 本文件 + `phaseB-2-test-run.log` |
| DEV_LOG R-02 | `.gdignore` 隔离 spike | 已落实 |

**未覆盖（如实声明，分属后续票，不宣称通过）**：T-CONF-01（CFG-001）、T-FSM-01、T-TIME-01/02（FSM-001）、T-ECO-01～04（ECO-001）、T-SAVE-01～03（SAVE-001）、T-LOG-01（LOG-001）、T-UI-01、G-001～005（UI-001/REL-001）。

## 4. 遗留风险与需人工裁定

| ID | 风险（按优先级） | 需人工处置 |
|---|---|---|
| **L-0** | **阻断项，本 Agent 无权限修复**：`tools/auto/queue.json` 呈 ` M`（runner attempt 1 失败后自身 `save_q(retries=1)` 所致）。runner `scope_violations` 对 RUNNER_OWNED 仅豁免 untracked 情形，已跟踪的自有状态文件被误判越界 → attempt 2/3 的 scope 检查**必然**再次失败并冻结队列，与工单代码质量无关（§0 模拟实测） | 二选一后重跑 phase B：① 修 `tools/auto/runner.py`：对 tracked 的 `tools/auto/`（至少 `tools/auto/queue.json`）同样豁免；② 人工先 commit `queue.json` 的 retry 记录，且此后 runner 在 scope 检查前不得再弄脏它（内部重试循环做不到 → 建议选 ①） |
| L-1 | `icon.svg.import` 在 `-s` 测试下不会生成，但用户机器有**常驻 Godot GUI 编辑器**打开本工程（PID 27116，§0 取证）：本会话删除后分钟内即被编辑器自动重建 → 编辑器打开期间该项越界**反复出现且 Agent 无法处置**（终止用户进程越界且高危） | 人工裁定归属：随本票 commit `.import`（Godot 官方惯例）或加入 `.gitignore`/runner `ignored()` 豁免；或重跑 phase B 前临时关闭该编辑器并配合 L-0 的 runner 修复 |
| L-2 | 沙箱下引擎写不了 `user://logs/`（2 行 ERROR 工件，非 SCRIPT ERROR，不影响退出码） | 真实人工 shell 复跑即消失；无需处置 |
| L-3 | 现 queue 的 `test_cmd` 仅 `-s` 单命令，隐含依赖本机 `.godot/global_script_class_cache.cfg`。实测：缓存缺失时 `-s` 会因 `GameState` 解析失败而**不执行断言但退出码仍为 0**（假通过风险） | 建议 `test_cmd` 采用计划 §5 双段式（先 `--quit-after 2` 完整加载），或在 runner `run_test` 增加 `CORE001 SMOKE PASS` 字符串 + 无 `SCRIPT ERROR` 门禁（与人工补充 §4 一致） |
| L-4 | spike 独立运行能力本票未重验（避免重写已验收 report JSON） | 归 UI-001/REL-001；`.gdignore` 不改变 spike 工程结构 |
| L-5 | `.godot/` 本机缓存已生成 | `.gitignore` 与 runner `ignored()` 均豁免，无版本库污染 |

## 5. 回滚

本票全部交付为新建文件、零改动既有文件。未 commit 时删除 `project.godot`、`icon.svg`、`scenes/`、`scripts/`、`tests/unit/`、`tests/spike/.gdignore` 及 `.godot/` 即完全复原；已 commit 时 `git revert` 单提交（由用户按其 Git 流程执行；本 Agent 未 commit、未 push）。
