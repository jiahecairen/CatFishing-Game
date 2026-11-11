# FSM-001 Phase B 执行报告 — 捕鱼 FSM + 可控 RNG/虚拟时钟（AUTO-001 执行代理）

- 日期：2026-11-11（本会话）；依据 `tasks/evidence/FSM-001/plan.md`（Phase A 批准计划）执行。
- 环境：Godot `4.7.2.stable.official.ed1daf0bf`（`/Applications/Godot.app/Contents/MacOS/Godot`），Python 3.15.2（仅标准库），macOS Apple Silicon。
- 约束遵守：仅写 `scripts/fishing/**`、`tests/**` 与本证据目录；未读取/修改 `tasks/APPROVALS.md`；未新增批准记录；未调用子 Agent/并行/后台任务；未执行任何 git 写操作（commit/merge/push/stash/reset/clean 均无）；未修改任何数值参数（20/60 s、30 FPS、容量 10、鱼价权重均只读）。

## 1. 改动文件清单（git status 实测：全部为新增，无已跟踪文件被修改）

| 文件 | 类型 | 内容 |
|---|---|---|
| `scripts/fishing/deterministic_rng.gd` | 新增 | `class_name DeterministicRng extends RefCounted`：Lehmer 最小标准 LCG（48271，模 2³¹−1，纯 int64 整数乘法）；`set_seed`（0/越界拒绝 `BAD_SEED`）、`next_int`、`next_unit`（(0,1) 开区间）、`next_int_inclusive`（闭区间整数）。 |
| `scripts/fishing/virtual_clock.gd` | 新增 | `class_name VirtualClock extends RefCounted`：单调虚拟秒；负数/NaN/Inf 拒绝且不部分推进；与渲染 FPS 完全解耦。 |
| `scripts/fishing/fishing_state_machine.gd` | 新增 | `class_name FishingStateMachine extends RefCounted`：`State{IDLE,CASTING,WAITING,HOOKED,REELING,SETTLEMENT,PAUSED}`（镜像 core 骨架枚举名）+ `initialize/can_cast/tick_effective/request_cast/produce_catch_candidate/ack_settlement/pause/resume_if_safe/snapshot_checkpoint` + 内存 `transition_log`；启动先过 `ConfigGate.can_start_economy`；单步至多一个转换、余量结转；拒绝稳定错误码 `NOT_INITIALIZED/BAD_TRANSITION/BAD_TICK/BAD_CHECKPOINT/BAD_INJECTION/BAD_EVENT_ID/EVENT_ID_MISMATCH/CANDIDATE_ALREADY_ISSUED/AlreadyApplied`。 |
| `tests/unit/test_fsm001_fsm.gd` | 新增 | headless 单测 F1–F11（`extends SceneTree`，PASS→quit(0)/FAIL→quit(1)，同 CORE/CFG-001 约定）。 |
| `tests/unit/run_fsm001_checks.py` | 新增 | 标准库 runner：step1 导入 → step2 本票测试 → step3 CORE-001 回归 → step4 CFG-001 回归；隔离 HOME（票内临时目录，结束删除）；拒绝 `SCRIPT ERROR` 标记（实测 Godot `--script` 脚本解析失败时真实退出码可能仍为 0，故必须按标记判失败，不能只看退出码）。 |
| `tasks/evidence/FSM-001/report.md` | 新增 | 本文件（证据目录，允许范围内）。 |

未改：`scripts/core/fishing_system.gd` 等全部既有文件（含骨架）。`.godot/`、`*.uid` 被 gitignore，未污染工作树。`git status --porcelain` 中 ` M tasks/evidence/_runner/runner.log` 与 `?? tasks/evidence/_runner/runner.lock` 为 Phase A §2 已记录的同名 runner 自有既有状态，本会话未触碰、按 R-5 如实记录不恢复。

## 2. 执行命令与真实退出码（本会话实际执行）

| 命令（项目根） | 退出码 | 结果 |
|---|---|---|
| `python3 -B tests/unit/run_fsm001_checks.py`（最终验收） | **0** | `FSM001 RUNNER PASS` |
| └ step1 `Godot --headless --path . --editor --quit` | 0 | 导入 OK，注册 `FishingStateMachine` 全局类，无 SCRIPT ERROR |
| └ step2 `Godot --headless --path . --script res://tests/unit/test_fsm001_fsm.gd` | 0 | `FSM001 FSM PASS` |
| └ step3 `Godot --headless --path . --script res://tests/unit/test_core001_smoke.gd` | 0 | `CORE001 SMOKE PASS`（CORE-001 不回归） |
| └ step4 `Godot --headless --path . --script res://tests/unit/test_cfg001_config.gd` | 0 | `CFG001 CONFIG PASS`（CFG-001 不回归） |
| `git status --porcelain` | 0 | 仅上表新增 + 既有 runner 自有状态；无已跟踪文件改动 |

调试期间的真实失败也如实记录：首轮实现曾因 `_sim_seed` 内 `:=` 类型推断、FSM `var from :=` 解析错误、`%.9g` 不被 GDScript 支持（非法格式符返回原样字符串）、**周期边界丢弃结转余量破坏步长不变性**（F5 首测 0.5/1.0 s 步给出 `at_clock=47.000` 而 2.0 s 步给出 `49.000`）、以及 F6 测试自身误用 `_complete_cycle`（恢复后位于 WAITING 而非 CASTING）而失败（exit 1）；逐项修复后全绿。失败未删改断言、未伪造标记。

## 3. 测试输出摘要（真实 stdout）

```
pre-flight: deliverables present, data==examples (value-identical), fixtures present
[step2-fsm001] exit_code=0
FSM001 sample: min=20 max=60 distinct=41
FSM001 FSM PASS
[step3-core001-regression] exit_code=0
CORE001 SMOKE PASS
[step4-cfg001-regression] exit_code=0
CFG001 CONFIG PASS
FSM001 RUNNER PASS
```

seed=11 千次完整抛竿采样：wait_seconds 全为 [20,60] 整数，min=20、max=60、41 个不同取值（两端点均出现，非钉死，闭区间语义）。

## 4. 实现要点与计划偏差

- 按 plan §4：tick 仅在 CASTING/WAITING/HOOKED/REELING 消耗有效时间；PAUSED/IDLE/SETTLEMENT 零事件零消耗；单步至多一个转换，过冲秒结转到下一调用（含跨周期结转——调试段 F5 证明丢弃结转会破坏步长不变性，故结转跨 IDLE/CASTING 边界保留；事件 `at_clock` = 时钟 − 结转 = 阈值跨越的精确逻辑时刻，0.5/1/2 s 二进制精确步长下逐值相同）。
- catch_event_id（`catch-<r1>-<r2>`）、wait_seconds、鱼种（加权 `next_unit/累积权重`）全部出自注入 RNG；**拒绝路径零 RNG 消耗**（F2 有显式断言）。`AlreadyApplied` 按 plan §4 原文命名。
- 偏差 D-1（计划 §6 已批准）：FSM 实现在允许路径 `scripts/fishing/fishing_state_machine.gd`，`scripts/core/fishing_system.gd` 骨架保留未动。
- 偏差 D-2（新增，实现细节）：CASTING/HOOKED/REELING 占位时长取 FSM 内 `const` 1.0 s（OPEN-004 属表现时长、与经济无关）；未新增配置键——`runtime_config` schema 固定 5 键且 ConfigGate 逐键校验，扩键须用户批准，故不走"可配置"路径。
- 偏差 D-3（新增，实现细节）：checkpoint 恢复对 `PAUSED` 态 checkpoint 显式拒绝 `BAD_CHECKPOINT`（GameState schema 无 paused_from 载体，不猜测恢复）；`IDLE` checkpoint 要求 event_id/wait=null、elapsed=0。

## 5. 覆盖的验收条目（plan §5 矩阵 → 实测）

| 条目 | 用例 | 结果 |
|---|---|---|
| T-FSM-01 合法序列完整 | F1 白名单序列 + transition_log 顺序断言 | PASS |
| T-FSM-01 非法转换拒绝+错误码+记录 | F2 拒绝矩阵（未初始化/负/NaN/Inf tick、活动态 ack、WAITING 抛竿、PAUSED 抛竿、重复 pause、空/错 ID ack、重复候选）≥6 条 BAD_TRANSITION 记录 | PASS |
| T-TIME-01 同 seed/时钟/配置可复现 | F3 千次采样 + F4 双跑逐事件一致、异种子不同 + F9 checkpoint 崩溃恢复与未中断跑逐事件一致 | PASS |
| T-TIME-02 帧率无关 | F5 0.5/1/2 s 步（120/30/15 FPS 模拟）436 条事件时间轴逐值一致 + 代码零帧计数（无 Engine 调用） | PASS |
| T-TIME-03 暂停侧 | F6 暂停 10000 s tick 零事件、时钟零推进、无候选事务、checkpoint 不变、恢复续跑 | PASS |
| 满篓不新开 CASTING（SDD-172/V01-E01） | F7 can_cast 容量阻断（10 仅候选断言，GameState 只读） | PASS |
| 未完成结算不进下次抛竿 | F2/F10 SETTLEMENT 未 ack 拒绝 request_cast；重复 ack=AlreadyApplied 且仅一次 SETTLEMENT→IDLE | PASS |
| V01-F02/W03、SDD-175/176/177 | F3/F5/F6 有效时间推进 + 30FPS 不入业务层 + RNG/Clock 注入 | PASS |
| V01-T01 可控 RNG/可重放 | DeterministicRng + VirtualClock + F4/F9 | PASS |
| SDD-143 幂等 | F10（FSM 侧 catch_event_id 幂等键） | PASS |
| T-CONF-01 交界 | F8 复用 cfg001 夹具：`runtime:MIN_GT_MAX`、`catalog:DUP_ID` 拒绝启动，随后 request_cast=NOT_INITIALIZED | PASS |
| OPEN-001 隐藏=暂停≠离线收益 | F6 pause(reason) 模型 + checkpoint 形状；未接线任何窗口事件 | PASS |
| CORE-001 / CFG-001 不回归 | step3/step4 exit 0 + PASS 标记 | PASS |
| 范围门禁 | `git status --porcelain` 仅允许路径新增 | PASS |

## 6. 遗留风险

- **R-1（开放）**：CASTING/HOOKED/REELING 占位时长现为 FSM 内常量 1 s；正式表现时长（含是否入配置）待 **OPEN-004 人工裁定**，不阻断 T-FSM/T-TIME。
- **R-2（已闭合）**：seed 0/越界显式拒绝；整数模运算无浮点噪声；LCG 低位周期由双抽 ID 稀释（ID 仅确定性用途）。
- **R-3（开放）**：浮点 `>=` 阈值比较在二进制精确步长（0.5/1/2 s，测试覆盖）下逐值确定；非精确步长（如 0.1 s）可能有一步抖动，但 wait 恒为整数秒、ID 仍确定，不违反"同种子可复现"。ECO/SIM-001 若引入任意步长须复核。
- **R-4（已缓解）**：runner 以 Python 独立复核 data/==examples/ 逐值一致（20/60/30/10 与鱼价权重防误改）。
- **R-5（已缓解）**：GUI 导入副作用仅 `.godot/`、`*.uid`（gitignore）；runner.log/lock 为 runner 自有既有状态，如实记录不恢复。
- **R-6（开放，移交 ECO-001）**：catch/sale 幂等落账、金币/鱼篓权威写属 ECO-001；本票已提供 catch_event_id 幂等键与 FSM 侧 AlreadyApplied，ECO-001 须复核同一 ID 重试不重复入篮/加币。
- **R-7（新发现，移交 ECO/SAVE-001）**：Godot `--script` 在脚本解析失败时真实退出码可能仍为 0（实测），任何 runner 判定必须同时禁止 `SCRIPT ERROR` 标记，不得只看退出码；本票 runner 已实现，后续票沿用。
- **R-8（新发现，移交 SAVE-001）**：IDLE/SETTLEMENT checkpoint 不携带 tick 内过冲结转秒，崩溃恰发生于 IDLE 且同 tick 内有未结转时间时，恢复后事件绝对时刻最多差一个 tick 步长（事件序列/ID 仍确定）；若 SIM-001 需要跨崩溃绝对时刻逐值一致，需扩展 checkpoint 载体（须人工批准 schema 变更）。
- 未做（按计划有意不实现）：鱼篓扣减/金币/售鱼（ECO-001）、存档写盘（SAVE-001）、日志文件（LOG-001）、窗口/渲染、GUI 手动验收。
