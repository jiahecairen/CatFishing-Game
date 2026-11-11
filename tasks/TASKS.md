# v0.1 原子开发工单 / Backlog

**状态：SPIKE-001 系列 = Accepted（桌面 GUI 验收有记录，多显示器未测）；CORE-001 = Accepted；CFG-001 = Accepted；FSM-001 = Ready；其余状态以 `tools/auto/queue.json` 为准。** 逐票证据见下方工单记录与 `docs/DEV_LOG.md`。**严格串行**，只使用一个本地 Flash。若前置测试失败，不得将依赖工单标记完成。

| ID | 标题 | 前置 | 主要交付 | 最小验收 |
|---|---|---|---|---|
| AUDIT-001 | 只读项目、环境、Skills、旧文档审计 | 无 | 文件清单、Godot/Git 状态、冲突/风险报告 | 真实命令证据；不修改工作树 |
| SPIKE-001 | macOS 透明/穿透/拖动探针 | AUDIT-001 + 人工批准 | 最小隔离窗口场景 + 结果报告 | GUI 实证 + headless 加载；G-001/002 |
| CORE-001 | 最小 Godot 工程/模块及测试入口 | SPIKE-001 | 主场景、分层模块、headless 自动测试基础 | Godot 无语法/导入错误 |
| CFG-001 | 3 鱼种 JSON + 配置校验 | CORE-001 | 配置加载和非法数据拒绝 | T-CONF-01 |
| FSM-001 | 捕鱼 FSM、随机时间、可控 RNG/时钟 | CFG-001 | 20–60s 等待、30 FPS 脱钩的业务状态机 | T-FSM-01、T-TIME-01/02 |
| ECO-001 | 唯一鱼实例/有限鱼篓/出售与金币模型 | FSM-001 | `GameState`、幂等命令、满篮阻断 | T-ECO-01～04（内存测试） |
| SAVE-001 | 原子存档、版本与故障注入 | ECO-001 | SaveService、崩溃恢复、状态提交 | T-SAVE-01～03、ECO 事务集成 |
| UI-001 | 临时猫/船+最小状态/售鱼/拖动 UI | SAVE-001 + SPIKE-001 | 桌面交互、简单鱼篮菜单 | G-001～005 和售鱼流程 |
| LOG-001 | 本地有限日志+错误提示 | SAVE-001 + UI-001 | 结构化事件、轮换、持久化警告 | T-LOG-01、T-UI-01 |
| SIM-001 | 多随机种子虚拟时间报告 | FSM-001 + ECO-001 + SAVE-001 | 1/4/8h 捕获、占比、篮满、价值统计 | SDD-178；重复交易/满篮新抛竿=0 |
| REL-001 | 全部回归+候选8h稳定性+人工验收 | 前述全部 | 测试报告、资源基线、问题清单 | `docs/ACCEPTANCE_TESTS.md` 放行门禁 |

## AUDIT-001（现在执行，只读）

**目标**：检查 `/Users/rain/DevGame/Fishing` 真实工作树、Git diff、是否已有 `project.godot`、Godot 4 版本和 headless、现有 SDD、项目和个人 Skills；比对本包并记录冲突。`Plan Mode` 中不得创建或修改文件。**验收**：清晰打印命令和退出状态，工作树没有由本工单引起的新增改动。

## SPIKE-001（第一张编码票；先获用户批准）

**允许位置**：`tests/spike/overlay/**` 或经审查同等隔离路径。不要覆盖已有场景与 `project.godot`。

**目标**：用 Godot 4 创建透明、无边框、临时船 sprite 的最小窗口；非交互透明处穿透鼠标，船身可点击/拖动；窗口位置可恢复，固定 30 FPS。**验收**：Mac 实际运行成功与失败截图/日志、Godot 命令、Retina/多显示器适配检查、headless 可加载；必须区分 GUI 与 headless 的证据。失败时记录技术阻断并请求替代方案审批。

## FSM-001（完整捕鱼时间与随机事件）

**范围**：`CASTING→WAITING→HOOKED→REELING→SETTLEMENT`，外加安全 `IDLE/PAUSED`；固定种子 RNG；虚拟 `Clock`；初始 20–60s 等待，每次配置采样。**不得**以 30 FPS 的帧数计算等待、不允许未完成结算就进下一次抛竿。**验收**：同一 seed/虚拟时间序列逐事件可复现、非法转换拒绝、暂停不生成额外交易。

## ECO-001 + SAVE-001（不可拆开的核心安全要求）

- 单一 GameState 权威，鱼实例/事件 UUID；10 格是候选容量，满篮暂停下一抛竿。
- 出售由人工通过最小 UI 调用，唯一 sale ID；若相同 ID 被重试，库存和金币绝不重复变化。
- 捕获/售鱼后写入版本化原子存档，**写入成功后**再通知视图已成功。
- 故障注入：临时文件写失败、重命名失败、崩溃、旧版本/损坏存档；保存失败须暂停不安全经济操作，不可删除坏档掩盖。
- 对同时接近结算的捕获与售鱼按单一命令队列串行处理，不允许超容量、双发、丢事件。

## SIM-001（平衡统计，不可自行改数值）

- 至少多组固定种子（建议首次 20 组）、虚拟时间模拟 1h、4h、8h，区分不售直到满篮、定期出售循环。
- 统计完整捕鱼周期、鱼篮首次装满时间分布、三鱼种占比及价值、重复事务与篮满后新抛竿次数。输出 JSON + 中文摘要。
- 20–60s、鱼价和容量的调节**必须由用户**批准，不得 Agent 为追求某个虚构 KPI 擅改。

## REL-001（最终放行）

Mac 上连续候选 8 小时运行；记录系统/Godot 版本、内存/CPU/FPS基线、出错事件、恢复行为。自动测试 100% 通过核心用例；用户明确批准后将 v0.1 标记 `Accepted`，才继续 v0.2。

## 工单状态格式

```text
ID: FSM-001
Status: Planned | In Progress | Review | Blocked | Accepted
Owner: Local Flash + DeepSeek Harness (serial)
Scope / Dependencies / Allowed files:
Interface & invariants:
Executed commands + exit codes:
Test result & evidence:
Git diff / commit (if approved):
Risks & unresolved decisions:
Owner approval where required:
```

## 工单状态记录（Harness 实际执行，2026-11-10）

```text
ID: AUDIT-001
Status: Review
Owner: Local Flash + DeepSeek Harness (serial)
Scope / Dependencies / Allowed files: 只读；无依赖；本票零改动。事后经用户额外批准的写入仅 3 处：
  .gitignore（新建）、docs/DEV_LOG.md（新建）、tasks/TASKS.md（本状态段 + 首行状态更新）。
Interface & invariants: 无代码接口；仅核对 schemas/ 与 examples/ 一致性（人工比对一致）。
Executed commands + exit codes: 见 docs/DEV_LOG.md 表格（Godot --version=0 4.7.2.stable.official.ed1daf0bf；
  审计时 git status=128 无仓库；curl 127.0.0.1:9931/health=0 {"status":"ok"}；ps=1 被沙箱拒绝）。
Test result & evidence: 无任何自动化测试被执行（本票不需要）；工作树审计前后均 25 个文件，无 .godot/ 缓存。
  版本控制基线 commit 4d8ed4d，工作树干净，未配置远端、未推送。
Git diff / commit (if approved): 4d8ed4d（baseline 文档包原样入库）+ 本次票证据 commit。
Risks & unresolved decisions: R-01~R-11 全部记录在 docs/DEV_LOG.md；OPEN-001 待用户在 FSM-001 前裁定；
  OPEN-005 部分关闭（服务端 262144 已证实；65536 输出与长上下文稳定性未实测）。
Owner approval where required: 已批准 = git init + baseline + .gitignore；SPIKE-001 落点改为
  tests/spike/overlay/ 独立工程；本机回环只读健康检查；spike 内自动对比渲染器与穿透变体。
```

```text
ID: SPIKE-001
Status: In Progress
Owner: Local Flash + DeepSeek Harness (serial)
Scope / Dependencies / Allowed files: 依赖 AUDIT-001（Review）+ 人工批准（已给）。
  允许新建 tests/spike/overlay/**（含其自身 project.godot，独立工程，根目录不建入口）；
  运行时写 user://spike_window.json。禁止改动既有文档/示例/schema。
Interface & invariants: 仅窗口能力 + 窗口几何持久化；不实现经济、存档业务、FSM 结算逻辑。
  不变量：可见 30 FPS（SDD-175）；逻辑计时禁止依赖帧计数；透明区点击必须落到下方 App。
Executed commands + exit codes: 尚未执行（未写码）。
Test result & evidence: 尚无。G-001/G-002 需 GUI 人工证据；G-003 因本机仅单块内置屏记 NOT RUN。
Risks & unresolved decisions: macOS 26.6 + Godot 4.7.2 + Metal 的透明/穿透能力未验证（R-06）；
  Godot 4.7 无 --do-string，能力矩阵须在脚本内用 get_property_list() 打印。
Owner approval where required: 已批准自动对比 Metal/Compatibility 与穿透变体；
  任何需求级降级（放弃透明或穿透）仍须单独报批。
```

```text
ID: SPIKE-001
Status: In Review（AUTO-001 自动通过测试/范围/批准检查，待人工验收）
Owner: AUTO-001 scheduler + headless Qwen Flash (serial)
Executed commands + exit codes: test_cmd=/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay -> 0; attempt=1
Test result & evidence: tasks/evidence/SPIKE-001/ (会话归档+日志+diff)
Risks & unresolved decisions: 见 tasks/evidence/SPIKE-001/phaseA.out 与 report.md
Recorded by AUTO-001 at 2026-11-10T20:39:45+00:00
```

```text
ID: SPIKE-001-FIX-001
Status: In Review（AUTO-001 自动通过测试/范围/批准检查，待人工验收）
Owner: AUTO-001 scheduler + headless Qwen Flash (serial)
Executed commands + exit codes: test_cmd=/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay -> 0; attempt=1
Test result & evidence: tasks/evidence/SPIKE-001-FIX-001/ (会话归档+日志+diff)
Risks & unresolved decisions: 见 tasks/evidence/SPIKE-001-FIX-001/phaseA.out 与 report.md
Recorded by AUTO-001 at 2026-11-10T22:32:17+00:00
```

```text
ID: SPIKE-001-FIX-002
Status: In Review（AUTO-001 自动通过测试/范围/批准检查，待人工验收）
Owner: AUTO-001 scheduler + headless Qwen Flash (serial)
Executed commands + exit codes: test_cmd=/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay -> 0; attempt=1
Test result & evidence: tasks/evidence/SPIKE-001-FIX-002/ (会话归档+日志+diff)
Risks & unresolved decisions: 见 tasks/evidence/SPIKE-001-FIX-002/phaseA.out 与 report.md
Recorded by AUTO-001 at 2026-11-11T00:11:48+00:00
```

```text
ID: CORE-001
Status: In Review（AUTO-001 自动通过测试/范围/批准检查，待人工验收）
Owner: AUTO-001 scheduler + headless Qwen Flash (serial)
Executed commands + exit codes: test_cmd=/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing --script res://tests/unit/test_core001_smoke.gd -> 0; attempt=1
Test result & evidence: tasks/evidence/CORE-001/ (会话归档+日志+diff)
Risks & unresolved decisions: 见 tasks/evidence/CORE-001/phaseA.out 与 report.md
Recorded by AUTO-001 at 2026-11-11T04:27:42+00:00
```

```text
ID: CFG-001
Status: In Review（AUTO-001 自动通过测试/范围/批准检查，待人工验收）
Owner: AUTO-001 scheduler + headless Qwen Flash (serial)
Executed commands + exit codes: test_cmd=python3 -B tests/unit/run_cfg001_checks.py -> 0; attempt=1
Test result & evidence: tasks/evidence/CFG-001/ (会话归档+日志+diff)
Risks & unresolved decisions: 见 tasks/evidence/CFG-001/phaseA.out 与 report.md
Recorded by AUTO-001 at 2026-11-11T05:00:58+00:00
```

```text
ID: CORE-001
Status: Accepted（项目所有者委托 Codex 验收）
Owner: Codex delegated reviewer
Scope / Dependencies / Allowed files: SPIKE-001；project.godot, icon.svg(+合法导入旁车), scenes/**, scripts/**, tests/**。
Interface & invariants: 最小正式 Godot 工程/模块；不改产品参数。
Executed commands + exit codes: CORE smoke 既有真实运行=0；本轮隔离副本复跑 `python3 -B tests/unit/run_cfg001_checks.py`，step1 导入=0，step2 CFG=0，step3 CORE=0。
Test result & evidence: `CORE001 SMOKE PASS`；完整票证据见 `tasks/evidence/CORE-001/`。
Git diff / commit: `e807f15`；runner 安全门禁修复 `ba21ff0`；无范围外文件。
Risks & unresolved decisions: GUI 桌面行为属于 SPIKE/UI 验收；本票 headless 入口通过。
Owner approval: 2026-11-11 持续执行委托。
```

```text
ID: CFG-001
Status: Accepted（项目所有者委托 Codex 验收）
Owner: Codex delegated reviewer
Scope / Dependencies / Allowed files: CORE-001；data/**, scripts/config/**, tests/**。
Interface & invariants: data 与 examples 值一致；20–60s、30 FPS、鱼种价格/权重未调整。
Executed commands + exit codes: 隔离副本 `python3 -B tests/unit/run_cfg001_checks.py` -> 0；编辑器导入、CFG 测试、CORE 回归逐步退出码均为 0。
Test result & evidence: `CFG001 RUNNER PASS`、`CFG001 CONFIG PASS`、`CORE001 SMOKE PASS`；`P4` 启动门禁反例测试通过。
Git diff / commit: `1283e5e`, `1cc44a1`；审查记录见 `tasks/evidence/CFG-001/postcommit-review.md`。
Risks & unresolved decisions: 篮容量 10 仍是候选初值，不作为已批准平衡结论。
Owner approval: 2026-11-11 持续执行委托。
```


```text
ID: FSM-001
Status: Phase A reviewed; Phase B approved under project-owner delegation
Owner: Local Qwen Flash (single serial session) + Codex reviewer
Scope / Dependencies / Allowed files: CFG-001 Accepted; scripts/fishing/**, tests/**.
Interface & invariants: See tasks/evidence/FSM-001/plan.md and review.md; no economy/save/UI implementation.
Executed commands + exit codes: Phase A runner session exit 0; model gate PASS.
Test result & evidence: Phase A plan and independent review are committed before Phase B.
Git diff / commit: recorded in current progress commit.
Risks & unresolved decisions: SAVE-001 must persist deterministic RNG continuation and pending-candidate payload; schema update belongs to its reviewed scope.
Owner approval: `tasks/APPROVALS.md`, Codex delegated Phase B approval, 2026-11-11.
```
