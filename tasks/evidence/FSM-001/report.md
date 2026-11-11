# FSM-001 Phase B 执行报告（重开返修轮）— 捕鱼 FSM + 可控 RNG/虚拟时钟（AUTO-001 执行代理）

- 日期：2026-11-11（本会话）。本轮为 `review-followup.md` 重开验收项的返修执行，基线 = HEAD `213fd82`（其前为 `025ff70` 重开 + `9dc9753` 原实现）。本报告**取代**同路径旧版报告（旧文完整保留在 Git 历史 `9dc9753` 中，未删除）。
- 环境：Godot `4.7.2.stable.official.ed1daf0bf`（`/Applications/Godot.app/Contents/MacOS/Godot`），Python 3.15.2（仅标准库），macOS Apple Silicon。
- 约束遵守：本会话仅写 `scripts/fishing/**`、`tests/**` 与本证据目录；未读取/修改 `tasks/APPROVALS.md`；未新增批准记录；未调用子 Agent/委派/fork/并行工作流/后台任务（全部命令前台串行）；未执行任何 git 写操作（commit/merge/push/stash/reset/clean 均无）；未修改经济参数与 schema（20/60 s、30 FPS、容量 10、鱼价权重、`schemas/game-save.schema.json` 均只读）。
- `git status` 中 ` M tasks/evidence/_runner/runner.log` 与 `?? tasks/evidence/_runner/runner.lock` 为 AUTO-001 调度器 runner 自有既有状态（Phase A §2 已记录，本会话开始前即存在），本会话未触碰、如实记录不恢复。

## 1. 改动文件清单（本会话；`git diff --stat` 实测）

| 文件 | 增/删行 | 返修内容（对应 review-followup 重开验收项） |
|---|---|---|
| `scripts/fishing/deterministic_rng.gd` | +34 | #4：`get_state()`；`snapshot_state()`（{version:1, seed, state}）；`restore_state(Variant)` **fail-closed**——非字典/缺键/多键/版本不符/非整数/越界一律 `BAD_SNAPSHOT` 且零副作用。 |
| `scripts/fishing/virtual_clock.gd` | +32 | #4：`snapshot_state()`（{version:1, now}）；`restore_state(Variant)` fail-closed（负/NaN/Inf/非数值/版本/键数校验），拒绝时 `now()` 不变。 |
| `scripts/fishing/fishing_state_machine.gd` | +116/−40 | #1：`request_cast(state: GameState)` **内部门禁**（NOT_INITIALIZED→NULL_GAME_STATE→BAD_TRANSITION→BASKET_FULL 逐级稳定拒绝，全部发生在抽样之前 → RNG 不动、不生成 event ID；`can_cast` 保留为等价只读查询）。#2：`produce_catch_candidate()` 重试**幂等重放**——已签发时返回 `_pending_candidate.duplicate(true)` 深拷贝，payload 逐字段与首次相同（ok=true/code=""），不重复抽样，transition_log 记 `CANDIDATE_REPLAYED`；ack 提交/新抛竿/initialize 时清空 pending。#3：`snapshot_checkpoint()` 在 PAUSED 时落**暂停前状态**（schema 无 paused_from 载体；暂停零有效时间消耗 → 重启走暂停前态安全续跑），wait 仅 WAITING 携带；`initialize()` 交叉校验：PAUSED 拒绝、IDLE 要求 event/wait=null 且 elapsed==0、WAITING 要求 elapsed<wait、其余计时态 wait=null、elapsed 有限≥0，未知状态名/多余键/类型错一律 `BAD_CHECKPOINT`（**未扩改 schema**）。#5：`configure_stage_durations(casting, hooked, reeling)`——三值须全部有限正数否则 `BAD_DURATION` 且不改值；仅 IDLE 可配置（活动态中途 `BAD_TRANSITION`）；默认仍 1 s；不改 runtime_config/数据/schema。#6：无代码项（由测试时间轴承载）。 |
| `tests/unit/test_fsm001_fsm.gd` | +347/−62 | 全部 `request_cast(state)` 调用点更新；F2 新增 null/满篓内部拒绝 + RNG 状态不变 + 候选重放逐字段一致 + 深拷贝独立性（调用方误改返回值不污染内部）；F6 新增 PAUSED 快照必须等于暂停前快照且可被**新 FSM+新 RNG+新 Clock** 恢复；F7 新增 `request_cast` 满篓 BASKET_FULL 内部阻断 + FSM 只读 GameState 经济字段断言；F9 `_sim_seed` 崩溃侧改为**全新 RNG/Clock 从独立快照 restore**（不再共享旧对象）+ 12 例畸形 checkpoint fail-closed 矩阵 + WAITING checkpoint 往返逐字段一致；F12 新增：RNG/Clock 快照跨实例续跑一致 + 23 例 fail-closed 反例矩阵（拒绝且不改内部状态）；F13 新增：默认 1.0 s 精确、非法时长（0/负/NaN/Inf）拒绝不改默认、活动态禁改、自定义 2.0/0.5/0.25 使阈值精确移动且等待仍恒在 [20,60]；F4/F5 `_sim_seed` 时间轴 K 行纳入**鱼种 + 完整候选快照（base_price/catch_weight/rarity）+ 下一事件 ID + 等待值**。 |
| `tasks/evidence/FSM-001/report.md` | 重写 | 本文件（证据目录内，允许范围）。 |

`tests/unit/run_fsm001_checks.py` 本会话**无改动**——其临时副本隔离（排除 `.git`/`.godot`/`tasks/evidence`/Python 缓存、`--path` 与 cwd 同指副本、HOME/XDG 入临时目录、finally 清理、严格串行 import→FSM→CORE→CFG、逐步查退出码+PASS/FAIL 标记+`SCRIPT ERROR`）已由 `213fd82` 落实，本轮实测复核符合 followup #7。`review-followup.md` #8（OPEN-004 表述）在本报告 §6 R-1 更正。

## 2. 执行命令与真实退出码（本会话实际执行，未伪造）

| 命令（项目根） | 退出码 | 结果 |
|---|---|---|
| `python3 -B tests/unit/run_fsm001_checks.py`（基线，返修前） | **0** | 旧测试集全绿——证明旧断言未覆盖重开验收项（见 review-followup） |
| `python3 -B tests/unit/run_fsm001_checks.py`（返修后第 1 次） | **1** | `FSM001 FSM FAIL: F7 FSM must not mutate GameState economy fields`——F7 测试自身断言排序错误（pop_back 后篮内应剩 9 条而非 10）；修正测试断言，未删断言、未改实现语义 |
| `python3 -B tests/unit/run_fsm001_checks.py`（修正后） | **0** | `FSM001 RUNNER PASS` |
| `python3 -B tests/unit/run_fsm001_checks.py`（最终：K 行纳入完整候选快照后） | **0** | `FSM001 RUNNER PASS`（下表摘要） |
| `git status --porcelain` / `git diff --stat` | 0 / 0 | 仅上表允许路径 4 文件修改 + 既有 runner 自有状态 |

最终一次 runner 完整原始输出已存档为本证据目录 `test-2.log`（含隔离临时目录路径、各步真实退出码与 PASS 标记）。

## 3. 测试输出摘要（最终一次真实 stdout 关键行）

```
FSM-001 source root: /Users/rain/DevGame/Fishing
pre-flight: deliverables present, data==examples (value-identical), fixtures present
isolated project copy: /var/folders/.../T/run_fsm001__ye_sjx9/project
isolated HOME: /var/folders/.../T/run_fsm001__ye_sjx9/home
[step1-import] exit_code=0 → OK（无 SCRIPT ERROR）
[step2-fsm001] exit_code=0
  FSM001 sample: min=20 max=60 distinct=41
  FSM001 FSM PASS
[step3-core001-regression] exit_code=0 → CORE001 SMOKE PASS
[step4-cfg001-regression] exit_code=0 → CFG001 CONFIG PASS
cleaned isolated project and HOME
FSM001 RUNNER PASS
```

seed=11 千次完整抛竿：wait_seconds 全为 [20,60] 整数，min=20、max=60、41 个不同取值（端点均出现，非钉死，闭区间语义）。

## 4. review-followup 重开验收项 → 落实与实测

| 重开验收项 | 用例/实现 | 结果 |
|---|---|---|
| 1 `request_cast(state)` 内部门禁；满篓/空值/非法状态稳定拒绝且 RNG 不变 | FSM 内置四级门禁；F2（NULL_GAME_STATE、BASKET_FULL、`rng.get_state()` 前后相等、状态不变）、F7（BASKET_FULL + 抛竿后 GameState 经济字段逐字段只读断言） | PASS |
| 2 同一结算事件重试返回深拷贝但逐字段相同的候选 payload，不重复抽样 | F2：`cand2 == cand1` 且 RNG 不动；调用方改写 `cand3.weight_snapshot` 后内部 payload 不受污染（重放仍等于 cand1） | PASS |
| 3 PAUSED 快照 schema 可表示、重启安全续跑；checkpoint 交叉校验、畸形拒绝；不扩 schema；SAVE-001 移交项记录 | 快照落暂停前态（F6：PAUSED 中快照==暂停前快照，且可被全新三件套恢复）；F9 12 例畸形矩阵全部 `BAD_CHECKPOINT` 且 FSM 留在未初始化 IDLE；schema 未动；移交项见 §6 R-2 | PASS |
| 4 RNG fail-closed 状态读取/恢复；Clock 可从独立保存值恢复；恢复测试用**新** RNG+新 Clock | RNG/Clock `snapshot_state`/`restore_state`；F9 崩溃侧 `_sim_seed` 用全新 RNG/Clock restore 后与未中断对照组逐事件一致；F12 跨实例续跑一致 + 23 例反例拒绝且不改内部状态 | PASS |
| 5 CASTING/HOOKED/REELING 时长可配置、验证有限正数、默认 1 s、不改配置/经济/schema | `configure_stage_durations()`；F13：默认精确 1.0 s、0/负/NaN/Inf → `BAD_DURATION` 不改默认、活动态禁改、自定义时长后阈值精确移动、等待仍 20–60 | PASS |
| 6 F4/F5 时间轴纳入候选鱼种；0.5/1/2 s 步长逐字段一致（时刻/事件 ID/等待/鱼种/候选快照） | K 行含 caught_at、species、下一 event ID、wait、base_price、catch_weight、rarity；F4 双跑逐值一致+异种子不同；F5 3600 s 内 436 条时间轴（Python 逐行复刻同一 LCG/结转逻辑独立复核该条数），0.5/1/2 s 三组逐值一致 | PASS |
| 7 runner 隔离：临时副本+HOME 入临时目录+finally 清理+严格串行+标记校验+禁止主工程跑 Godot | 最终运行实测：`isolated project copy: /var/folders/.../run_fsm001__ye_sjx9/project`、`isolated HOME: .../home`、`cleaned isolated project and HOME`；主工程从未作为 `--path`/cwd | PASS |
| 8 OPEN-004 表述更正 | 本报告 §6 R-1：以 `docs/REQUIREMENTS_CHANGELOG.md` 为准，OPEN-004 **已裁定**（表现时长可配置且不改等待/经济）；本轮已按其裁定实现可配置时长 | 已更正 |

## 5. 原有计划验收矩阵（plan §5）在返修后仍全部覆盖

| 条目 | 用例 | 结果 |
|---|---|---|
| T-FSM-01 合法序列完整 | F1 白名单序列 + transition_log 顺序断言 | PASS |
| T-FSM-01 非法拒绝+稳定错误码+记录 | F2 拒绝矩阵（含新 NULL_GAME_STATE/BASKET_FULL/BAD_DURATION 码）≥6 条 BAD_TRANSITION 记录 | PASS |
| T-TIME-01 同 seed/时钟/配置可复现 | F3 千次采样 + F4 双跑逐事件（含鱼种/快照）一致 + F9 跨实例崩溃恢复一致 | PASS |
| T-TIME-02 帧率无关 | F5 0.5/1/2 s 步 436 条逐值一致；代码零帧计数（无 Engine 调用，`run/max_fps` 不入业务层） | PASS |
| T-TIME-03 暂停侧 | F6 暂停 10000 s 零事件、时钟不推进、checkpoint 不变、可重启、恢复续跑 | PASS |
| 满篓不新开 CASTING（V01-E01/SDD-172） | F7 `request_cast` 内部 BASKET_FULL（容量 10 仅候选断言，GameState 只读） | PASS |
| 未完成结算不进下次抛竿 | F2/F10 未 ack 拒绝；重复 ack=`AlreadyApplied` 仅一次 SETTLEMENT→IDLE | PASS |
| V01-W03/SDD-175 逻辑时钟独立 | VirtualClock 注入；F5/F6 | PASS |
| V01-T01 可控 RNG/可重放 | DeterministicRng+快照恢复+F4/F9/F12 | PASS |
| SDD-143 幂等 | F10 catch_event_id 幂等键 + 候选重放（F2） | PASS |
| T-CONF-01 交界 | F8 夹具复用：`runtime:MIN_GT_MAX`、`catalog:DUP_ID` 拒绝启动 → request_cast=NOT_INITIALIZED | PASS |
| OPEN-001 已裁定（隐藏=暂停≠离线收益） | F6 pause(reason)+安全快照恢复；未接线任何窗口事件 | PASS |
| CORE-001/CFG-001 不回归 | step3/step4 真实 exit 0 + PASS 标记 | PASS |
| 范围门禁 | `git status --porcelain`：仅允许路径 4 文件 + 既有 runner 自有状态 | PASS |

## 6. 遗留风险与移交项

- **R-1（更正，followup #8）**：OPEN-004 为**已裁定**（`docs/REQUIREMENTS_CHANGELOG.md`：「已裁定最小实现：…表现时长可配置且不改钓鱼等待/经济规则」）。旧报告 R-1 误写「待人工裁定」，本报告更正；本轮以 `configure_stage_durations()` 落实可配置（默认 1 s，不新增配置键——runtime_config schema 固定 5 键，扩键须用户批准）。
- **R-2（开放，移交 SAVE-001）**：schema v1 `fishing_checkpoint` 仅 4 字段，不含 RNG 运行状态、Clock 读数与待结算候选。跨崩溃**逐事件重放**需 SAVE-001 在其批准范围内持久化 `DeterministicRng.snapshot_state()`、`VirtualClock.snapshot_state()` 与 pending candidate payload；FSM-001 只提供内存快照，未写任何文件。另：IDLE 态快照按 schema 要求 elapsed=0，崩溃恰发生于 IDLE 结转窗口时重启后事件绝对时刻最多偏移一个 tick 步长（序列/ID 仍确定）。
- **R-3（开放，移交 ECO-001）**：catch_event_id 幂等键、FSM 侧 `AlreadyApplied` 与候选重放已就绪；ECO-001 落账时须复核同一 catch/sale ID 重试不重复入篮、不重复加币。
- **R-4（开放）**：浮点 `>=` 阈值比较在二进制精确步长（0.5/1/2 s，实测逐值一致）下确定；非精确步长（如 0.1 s）理论存在一步抖动（wait 恒整数秒、ID 仍确定）。SIM/ECO 引入任意步长前须复核。
- **R-5（既有事实，runner 已缓解）**：Godot `--script` 脚本解析失败时真实退出码可能仍为 0，判定必须同时禁 `SCRIPT ERROR` 标记；本 runner 已实现，后续票沿用。
- **R-6（契约变更说明）**：`request_cast()` → `request_cast(state: GameState)` 为重开验收项 #1 强制的签名变更，属已批准的返修而非范围扩张；全仓 grep 证实除 FSM 自身与本票测试外无其他调用点（`scripts/core/fishing_system.gd` 仅注释提及契约名，未改动）。
- 未做（按计划有意不实现）：鱼篓扣减/金币/售鱼落账（ECO-001）、存档写盘（SAVE-001）、日志文件（LOG-001）、窗口/渲染与 GUI 手动验收（另票）。
