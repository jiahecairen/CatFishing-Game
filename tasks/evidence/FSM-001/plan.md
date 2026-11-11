# FSM-001 Phase A 计划 — 捕鱼 FSM + 可控 RNG/虚拟时钟（AUTO-001，只读规划）
- `FishingSystem` 作为纯业务状态机可在 headless 环境测试；可视化与业务拆分，禁止用每帧计数做捕鱼等待。

- 工单：FSM-001「捕鱼 FSM、随机时间、可控 RNG/时钟」，前置 CFG-001（done/Accepted，commit `1cc44a1`），最小验收 **T-FSM-01、T-TIME-01/02**，来源 `tasks/TASKS.md`「FSM-001（完整捕鱼时间与随机事件）」段与 `tools/auto/queue.json`（status=ready、needs_human=false、test_cmd 空待回填）。
- 允许文件范围（Phase B 强制）：`scripts/fishing/**`、`tests/**`。本 Phase A 全程只读，唯一写入即本文件。
- 依据：`docs/INTERFACES_AND_DATA.md` §4（FishingSystem 伪接口与不变量）、`docs/ARCHITECTURE.md` §3（FSM 状态表/随机可重放）、`docs/SDD_v0.1.md` V01-F01/F02/W03/T01 与 §4 时序/§6 参数表、`docs/DECISION_REGISTER.md` SDD-143/175/176/177、`docs/ACCEPTANCE_TESTS.md` §2、`docs/REQUIREMENTS_CHANGELOG.md` OPEN-001（**已裁定**：窗口隐藏暂停有效计时并保留 checkpoint，隐藏≠退出≠离线收益）、项目 Skills `fishing-state-and-save`、`godot-validation`。

## 1. 目标

1. 在 `scripts/fishing/` 实现纯业务捕鱼状态机（`IDLE/PAUSED` + `CASTING→WAITING→HOOKED→REELING→SETTLEMENT`），可在 headless 环境测试；状态推进只依赖**注入的虚拟时钟秒数**，绝不按帧计数计时（`Engine.get_frames_drawn()` / `_process(delta)` 禁止参与业务计时）。
2. 注入**确定性 RNG**（纯 GDScript 整数算法）与**虚拟 Clock**：上钩等待每次从配置的 `[bite_wait_min_sec, bite_wait_max_sec]`（当前 20–60 s，**本票禁止改动任何数值**）采样整数秒；同一 (seed, config, 时钟步序列, 动作序列) 逐事件可复现。
3. 非法状态转换显式拒绝并带稳定错误码；`PAUSED` 期间 tick 不产生任何事件/交易候选；满篓（读 GameState 只读）不开始新 `CASTING`；未完成结算（`ack_settlement` 未确认提交）不得进入下一次抛竿；单步跨越多个阈值最多推进一个状态转换、剩余时间结转（INTERFACES §4「安全最多一次推进」）。
4. 新增 headless 单测与本票 runner（Python 标准库），PASS→exit 0 / FAIL→exit 1，并回归 CORE-001 与 CFG-001 既有测试不被新全局类破坏。
5. 本票**只做 FSM + RNG/Clock**：不实现鱼篓扣减/金币/售鱼（ECO-001）、不实现存档写盘（SAVE-001）、不实现日志文件（LOG-001）、不触碰窗口/渲染；仅产出 `snapshot_checkpoint()` 的可序列化字典供 SAVE-001 使用。

## 2. Phase A 只读实测记录（真实命令与退出码，2026-11-11 本会话）

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 工作树 | `git status --porcelain -b` | 0 | `## main...origin/main`；仅 ` M tasks/evidence/_runner/runner.log` 与 `?? tasks/evidence/_runner/runner.lock`（均为 runner 自有既有状态，非本会话产生）；**无用户未提交代码** |
| 近期历史 | `git log --oneline -8` | 0 | HEAD=`7e726f6 Accept core and config tickets; resume FSM`；CORE-001 `e807f15`、CFG-001 `1283e5e`+`1cc44a1` 证据链完整 |
| Godot 可执行 | `ls -l /Applications/Godot.app/Contents/MacOS/Godot`；`... --version` | 0 | 存在；`4.7.2.stable.official.ed1daf0bf` |
| 目录 | `ls -R scripts tests data tasks/evidence` | 0 | `scripts/{config,core,io,platform,presentation}` 存在，**无 `scripts/fishing/`**（Phase B 新建）；`tasks/evidence/FSM-001/` 已存在且为空 |
| FSM 骨架 | 读 `scripts/core/fishing_system.gd` | 0 | 零实现骨架，仅 `class_name FishingSystem` + State 枚举注释；**`scripts/core/**` 不在本票允许范围**（见 §6 偏差 D-1） |
| 权威状态 | 读 `scripts/core/game_state.gd`、`game_controller.gd` | 0 | GameState 镜像 INTERFACES §3 schema v1；注释声明事务/持久化属 ECO/SAVE-001，本票禁止实现 |
| 配置门禁 | 读 `scripts/config/{config_gate,runtime_config,fish_species_catalog}.gd`、`data/*.json` | 0 | `ConfigGate.can_start_economy` 可直接复用为 FSM 启动门禁；正式配置 30 FPS、20/60 s、容量 10 候选、3 鱼种（60/30/10、8/16/32） |
| 类名占用 | grep `class_name` 全仓 `.gd` | 0 | 12 个全局类；**`FishingSystem` 已被 core 骨架占用**；`FishingStateMachine`/`VirtualClock`/`DeterministicRng` 未被占用 |
| 测试基线 | 读 `tests/unit/test_core001_smoke.gd`、`test_cfg001_config.gd`、`run_cfg001_checks.py`、`fixtures/cfg001/` | 0 | 既有约定：`extends SceneTree`、PASS→quit(0)/FAIL→quit(1)、runner 串行导入+测试+回归、隔离 HOME、拒绝 SCRIPT ERROR |
| 运行器契约 | 读 `tools/auto/queue.json`（FSM-001 条目） | 0 | allowed_files=`scripts/fishing/**`,`tests/**`；test_cmd 为空（调度器将按本计划 §5 回填）；needs_human=false |
| Python | `python3 --version` | 0 | 3.15.2（仅标准库可用；无 `jsonschema`，与 AUDIT-001 记录一致） |
| 忽略规则 | 读 `.gitignore` | 0 | `.godot/`、`*.uid` 被忽略 → headless 运行缓存不污染 git 状态 |
| Skills | 会话技能目录实测 | 0 | `fishing-state-and-save`、`godot-validation` 已加载；`godot-overlay` 存在（GUI 票技能，本票只读加载未用其 GUI 流程） |

## 3. Phase B 要改动的文件（全部为**新增**，严格限于允许范围）

| 文件 | 内容 |
|---|---|
| `scripts/fishing/deterministic_rng.gd` | `class_name DeterministicRng extends RefCounted`：Lehmer 最小标准 LCG（乘数 48271、模 2³¹−1，纯 int64 乘法不依赖 64 位回绕语义）；`set_seed(seed:int)`、`next_int() -> int`、`next_unit() -> float`（(0,1) 开区间）、`next_int_inclusive(lo,hi) -> int` |
| `scripts/fishing/virtual_clock.gd` | `class_name VirtualClock extends RefCounted`：单调虚拟秒；`advance(seconds: float)` 拒绝负数/NaN/Inf（返回 false 且不改状态）、`now() -> float`、`reset()` |
| `scripts/fishing/fishing_state_machine.gd` | `class_name FishingStateMachine extends RefCounted`：完整 FSM 与不变量（§4）；含内存内 `transition_log`（结构化字典数组，供测试断言与 LOG-001 后续复用；**不写任何文件**） |
| `tests/unit/test_fsm001_fsm.gd` | `extends SceneTree` headless 单测：全部通过打印 `FSM001 FSM PASS` 且 `quit(0)`；首个失败打印 `FSM001 FSM FAIL: <step>` 且 `quit(1)`（沿用 CORE/CFG 约定） |
| `tests/unit/run_fsm001_checks.py` | Python 标准库 runner（镜像 `run_cfg001_checks.py`）：串行 step1 导入（`--editor --quit`）、step2 FSM 单测、step3 CORE-001 回归、step4 CFG-001 回归；隔离 HOME 于 `tasks/evidence/FSM-001/` 内临时目录且 finally 删除（CFG-001 同先例）；对项目树零写入 |

不改动（明确排除）：`scripts/core/fishing_system.gd` 等 `scripts/core/**`、`scripts/io/**`、`scripts/config/**`、`data/**`、`examples/**`、`schemas/**`、`scenes/**`、`project.godot`、`docs/**`、`tasks/**`（证据目录由 runner 归档）、`tools/auto/queue.json`（RUNNER_OWNED，test_cmd 由调度器回填，见 §5）。禁止新增第三方依赖。

## 4. 接口与不变量

**FishingStateMachine**（对齐 INTERFACES §4 伪接口；签名可记录为契约，语义与不变量不可擅改）：

```text
initialize(catalog: Dictionary, runtime: Dictionary, rng: DeterministicRng,
           clock: VirtualClock, recovered_checkpoint: Dictionary) -> {ok: bool, error_code: String}
  # catalog/runtime 为 FishSpeciesCatalog/RuntimeConfig 的返回字典；先过 ConfigGate.can_start_economy，
  # 任一非法 → ok=false + 稳定错误码（复用 "catalog:<CODE>" / "runtime:<CODE>" 形态），FSM 停留 IDLE 且拒绝抛竿（T-CONF-01 边界）。
  # recovered_checkpoint 为空字典 = 全新启动；否则按 schema {state, event_id, wait_seconds, elapsed_effective_seconds} 恢复。
can_cast(state: GameState) -> bool
  # 仅当：已合法启动 + 当前 IDLE + state.basket.size() < state.basket_capacity + 无未提交结算事件。
request_cast() -> {ok, catch_event_id? , rejected_reason?}
  # 仅 IDLE 可抛竿；catch_event_id 与 wait_seconds 均从注入 RNG 确定性抽样（可重放）；
  # wait_seconds 为 [ceil(min), floor(max)] 内整数秒，当前即 20–60；进入 CASTING。
tick_effective(seconds: float) -> Array[Dictionary]   # 返回本次产生的转换事件（可能为空）
  # 仅 WAITING/HOOKED/REELING 消耗有效时间；每次调用**至多一个状态转换**，越过阈值后剩余秒数结转到下一调用（INTERFACES §4）；
  # PAUSED/IDLE/SETTLEMENT 期间 tick 不产生任何事件；seconds < 0 / NaN → 拒绝且状态不变。
produce_catch_candidate() -> {catch_event_id, species_id, weight_snapshot, caught_at_clock}
  # 仅 SETTLEMENT 可调；鱼种由注入 RNG 按 catch_weight/sum(catch_weight) 加权确定；
  # 只发出候选事务，绝不修改金币/鱼篓（ARCHITECTURE §2）。
ack_settlement(catch_event_id: String, committed: bool) -> {ok, next_state, code}
  # committed=true 且 ID 匹配当前事件 → IDLE；同 ID 重复 ack → AlreadyApplied（不重复推进/不重发候选）；
  # 不匹配或已结算 → 稳定错误码。committed=false 停留 SETTLEMENT 可安全重试。
pause(reason: String) -> {ok}          # 任意活动态 → PAUSED，记录原因（如 window_hidden，OPEN-001 语义）
resume_if_safe() -> {ok, resumed_from} # 仅 PAUSED；恢复到暂停前的有效计时位置；期间累计 tick 不计入有效时间
snapshot_checkpoint() -> Dictionary    # {state, event_id, wait_seconds, elapsed_effective_seconds}，镜像 GameState schema v1 的 fishing_checkpoint
```

**转换白名单**（其余一律拒绝 + 错误码 `BAD_TRANSITION` 并记入 transition_log，T-FSM-01）：
`IDLE→CASTING`（经 request_cast 且门禁通过）、`CASTING→WAITING`（自动，抛竿动画占位时长可配置，OPEN-004 裁定：表现时长不影响 20–60 s 等待与经济）、`WAITING→HOOKED`（有效时间到）、`HOOKED→REELING`、`REELING→SETTLEMENT`（各占位时长同上）、`SETTLEMENT→IDLE`（仅 ack_settlement 确认提交）、任意活动态 `→PAUSED`、`PAUSED→(暂停前状态)`。

**不变量（Phase B 必守）**：
- 纯 RefCounted 数据层：无 Node/`_process`/`_physics_process`、无 `Engine.time_scale`/`get_frames_drawn`、不读写 `user://`、无任何文件写入。
- 20–60 s、30 FPS、容量 10、鱼价/权重**只读取不修改**；配置值改动须用户批准（SDD §6），本票任何测试断言锁定现值。
- RNG 为纯 GDScript 整数 LCG，不依赖 Godot `RandomNumberGenerator`（避免引擎版本间算法漂移破坏跨版本复现）；种子相同 ⇒ 事件序列逐字段相同（T-TIME-01）。
- 业务时间与渲染 FPS 解耦：不同 tick 步长（模拟 30/15/120 FPS）但相同虚拟总时长 ⇒ 事件时间轴一致（T-TIME-02）；测试用二进制精确步长（0.5/1/2 s）与整数秒 wait 避免浮点噪声。
- 不产生重复/幽灵事件：单次 tick 至多一次转换；`PAUSED`、满篓、配置非法、未提交结算四类情形下新事件数恒 0。
- FSM 只读 GameState（can_cast 判断容量），**不写** GameState 的 wallet/basket/processed ids（属 ECO-001）。
- 新类名 `FishingStateMachine` / `VirtualClock` / `DeterministicRng` 均避开 12 个已占用 class_name（实测 §2），防止全局类冲突连累回归。

## 5. 精确测试命令与预期退出码

主测试（Phase B 完成后执行；test_cmd 供调度器回填 `tools/auto/queue.json`，本票不自改该文件）：

1. 主入口（建议回填为 queue 的 test_cmd）：
   `python3 -B tests/unit/run_fsm001_checks.py`
   预期退出码 **0**，stdout 含 `FSM001 RUNNER PASS`；任一步失败退出 **1** 且含 `FSM001 RUNNER FAIL`。runner 内部判定：每步退出码 0 + 必需标记 + 无 `SCRIPT ERROR`，不伪造退出码。
2. 单步 FSM 单测：
   `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing --script res://tests/unit/test_fsm001_fsm.gd`
   预期 **0** + `FSM001 FSM PASS`；失败 **1** + `FSM001 FSM FAIL: <step>`。
3. 回归（runner step1/3/4 亦含）：
   `... --headless --path ... --editor --quit`（导入新全局类）→ **0**；
   `... --script res://tests/unit/test_core001_smoke.gd` → **0** + `CORE001 SMOKE PASS`；
   `... --script res://tests/unit/test_cfg001_config.gd` → **0** + `CFG001 CONFIG PASS`。
4. 范围自检：`git status --porcelain`
   预期 **0**，新增行仅 `scripts/fishing/*`（含被忽略的 `*.uid` 不出现）与 `tests/unit/test_fsm001_fsm.gd`、`tests/unit/run_fsm001_checks.py`；`_runner` 两项既有状态不变。

**test_fsm001_fsm.gd 覆盖矩阵**：
- F1 合法完整周期：启动→抛竿→WAITING 至上限+余量→HOOKED→REELING→SETTLEMENT→候选→ack(true)→IDLE，transition_log 顺序完整（T-FSM-01 合法侧）。
- F2 非法转换矩阵 ≥6 项（IDLE→HOOKED、WAITING→SETTLEMENT、SETTLEMENT 未 ack 即 request_cast、PAUSED 中 request_cast、未启动 tick 生效、重复 SETTLEMENT 进入）→ 全部拒绝 + `BAD_TRANSITION`/稳定码 + 状态不变（T-FSM-01 拒绝侧）。
- F3 采样区间：seed=11 连续 1000 次抛竿，wait_seconds 全为 [20,60] 整数秒且 min<样本min≤样本max<max（防钉死端点）（T-TIME-01）。
- F4 同种子复现：同 (seed, config, 动作, 时钟步) 双跑，含鱼种抽样，事件日志逐字段相等；异种子（13）序列可不同（T-TIME-01）。
- F5 步长不变性：同一 3600 虚拟秒，按 0.5/1.0/2.0 s 步（模拟 120/30/15 FPS）分别 tick，事件时间轴（时刻、类型、event_id、species）完全一致（T-TIME-02）。
- F6 暂停安全：WAITING 中 pause，tick 10000 s → 0 事件、wait 不推进；resume 后按 checkpoint 继续；全程无候选事务（T-TIME-03 暂停侧）。
- F7 满篓阻断：构造 basket 达 capacity 的 GameState → can_cast=false；空篓 → true（容量 10 仅作候选值断言，不改值）。
- F8 非法配置拒绝：`res://tests/unit/fixtures/cfg001/min_gt_max.json` 经 RuntimeConfig+ConfigGate → initialize 失败、request_cast 被拒（T-CONF-01 与 FSM 交界）。
- F9 checkpoint 恢复：WAITING 中 snapshot → 新实例 initialize(checkpoint) → 续跑 → 与未中断跑的事件序列一致（为 SAVE-001 崩溃恢复奠基）。
- F10 结算幂等：同 event_id 二次 ack_settlement → AlreadyApplied，不重复进 IDLE、不重发候选（ECO-001 幂等键的 FSM 侧）。
- F11 大步长安全：WAITING 起点单步 tick 120 s → 恰一个 HOOKED，剩余结转到下一调用，无凭空多发（INTERFACES §4）。

## 6. 风险与回滚

- **D-1 偏差（范围 vs 骨架注释）**：`scripts/core/fishing_system.gd` 骨架注释称「FSM-001 实现」且已占用 `class_name FishingSystem`，但 queue 允许清单仅 `scripts/fishing/**` + `tests/**`。处置：实现落在 `scripts/fishing/fishing_state_machine.gd`（新类 `FishingStateMachine`），**不触碰** core 骨架；ARCHITECTURE §7 自述目录布局为建议、实际命名记录于工单即本文件——与 CFG-001 D-2（ConfigLoader 骨架 vs scripts/config 新类）同先例，属范围裁量而非需求变更，queue `needs_human:false` 一致。core 骨架的转发/删除留待后续票人工处置；如 runner 判违规按流程上报。
- **R-1 全局类冲突**：新类名已实测避开 12 个既有 class_name；step3/4 回归兜底。
- **R-2 RNG 复现性**：不用引擎 RNG；Lehmer LCG（48271 × 状态 < 2³¹·2³¹ < 2⁶³）纯 int64 精确乘法，不依赖回绕/浮点，跨平台跨版本可复现；种子 0 或越界显式拒绝（`BAD_SEED`），不静默重置。
- **R-3 浮点阈值噪声**：wait 采用整数秒 + 二进制精确步长；tick 拒绝 NaN/Inf；比较用 `elapsed >= wait`（整数语义）无 epsilon 需求。
- **R-4 经济参数误改**：测试断言 20/60/30/10 与鱼价权重仍为 `data/`、`examples/` 现值；Phase B 不写 data/。
- **R-5 runner 门禁误报**：headless 运行可能再生 `icon.svg.import`/`.godot/` 缓存（CORE-001/CFG-001 已知现象）：如实记录于 report，**不得** git restore/commit/杀用户进程，交 runner 豁免逻辑。
- **R-6 隐藏窗口语义**：OPEN-001 已裁定（隐藏=暂停+checkpoint，非离线收益）；本票仅实现 pause/resume 抽象与 checkpoint 数据形状，真实隐藏检测属 UI-001，不得在本票提前接线窗口事件。
- **回滚**：Phase B 全部为新增未跟踪文件，回滚 = 仅删除 `scripts/fishing/`、`tests/unit/test_fsm001_fsm.gd`、`tests/unit/run_fsm001_checks.py`；无已跟踪文件被修改，`git checkout -- .` 不适用；基线 commit `7e726f6` 可逐票 diff。禁止 `git clean -fdx`（会波及 `_runner/` 与其他证据目录）。
- 本票不涉及需求变更、经济参数调节、破坏性迁移、隐私/网络功能；OPEN-001 已裁定、queue needs_human=false → **无需额外人工批准**。

## 7. 验收条目映射

| 验收条目 | 来源 | Phase B 证据 |
|---|---|---|
| T-FSM-01 合法状态顺序完整 | ACCEPTANCE_TESTS §2 | F1 transition_log 完整周期断言 |
| T-FSM-01 非法转换拒绝并可记录 | 同上 | F2 ≥6 反例 + 稳定错误码 + transition_log |
| T-TIME-01 等待落 20–60s 配置区间 | 同上 | F3 千次采样区间断言（区间读自配置） |
| T-TIME-01 同 seed/时钟/配置可复现 | 同上 | F4 双跑逐事件比对（含鱼种抽样） |
| T-TIME-02 30/15/120 FPS 不改变事件时间轴 | 同上 | F5 步长不变性测试（逻辑时间相同） |
| 暂停不生成额外交易 | TASKS.md FSM-001 验收段 | F6 暂停 10000 s 零事件 + checkpoint 续跑 |
| 满篓不新开 CASTING | SDD V01-E01 / SDD-172 | F7 can_cast 容量阻断（容量 10 仅候选值断言） |
| 未完成结算不进下次抛竿 | TASKS.md FSM-001 范围 | F2/F10：SETTLEMENT 未 ack 拒绝 request_cast；重复 ack=AlreadyApplied |
| V01-F01 FSM 序列 | SDD §2 | F1 白名单序列 CASTING→…→SETTLEMENT（ARCHITECTURE §3 状态表） |
| V01-F02 20–60s 按有效时间推进、独立于帧数 | SDD / SDD-177 | F3 + F5；代码零帧计数（不变量 §4，AGENTS §4 规则行） |
| V01-W03 / SDD-175 逻辑时钟独立 | SDD / DECISION | F5；`project.godot run/max_fps=30` 不在业务层引用 |
| V01-T01 可控时钟/固定种子/可重放序列 | SDD §2 / SDD-157 | DeterministicRng + VirtualClock + F4/F9 复现与 checkpoint 恢复 |
| SDD-143 事件 ID 幂等 | DECISION | F10 catch_event_id 幂等键（FSM 侧） |
| T-CONF-01 交界：非法配置拒绝 FSM 启动 | ACCEPTANCE_TESTS §2 | F8 复用 cfg001 夹具 + ConfigGate |
| OPEN-001 隐藏=暂停非离线收益 | REQUIREMENTS_CHANGELOG | F6 pause(reason) 模型 + checkpoint 形状；不接线任何窗口事件（R-6） |
| CORE-001 / CFG-001 不回归 | queue deps | §5 命令 3 退出码 0 + PASS 标记 |
