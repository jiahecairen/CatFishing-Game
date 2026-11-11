# SIM-001 Phase A 计划 — 多随机种子虚拟时间模拟报告（AUTO-001，只读规划）
固定业务约束：可见桌面 **30 FPS**；自动捕鱼随机上钩等待初始 **20–60 秒**；独立游戏逻辑时钟；约三种鱼可配；鱼篓容量 **10 格仅为候选初值**；满篓不发起新抛竿；一次鱼对应唯一实例 ID；出售按唯一事件/事务 ID 原子扣鱼加币；崩溃重试不重复结算。

- 工单：SIM-001「多随机种子虚拟时间报告」，前置 FSM-001 / ECO-001 / SAVE-001（queue 均 `done`/Accepted），最小验收 **SDD-178；重复交易/满篮新抛竿=0**（`tasks/TASKS.md` 表 + 「SIM-001（平衡统计，不可自行改数值）」段；`tools/auto/queue.json`：status=`ready`、needs_human=false、test_cmd 空待回填；`unfrozen` 记录项目所有者持续执行委托 2026-11-11T20:08Z）。
- 允许文件范围（Phase B 强制）：`tools/sim/**`、`tasks/evidence/SIM-001/**`。本 Phase A 全程只读，唯一写入即本文件；未读未改 `tasks/APPROVALS.md`，无任何 git 写操作，无子 Agent/并行/后台任务。
- 依据：`docs/SDD_v0.1.md` V01-T02/§4 时序/§6 参数表、`docs/DECISION_REGISTER.md` SDD-172/176/177/178、`docs/ACCEPTANCE_TESTS.md` §1「模拟/统计」层与 §4（SDD-178 多种子模拟 + JSON 报告参考格式）、`docs/INTERFACES_AND_DATA.md` §4/§5、`docs/TECH_SPIKE.md`/`docs/HARNESS_LOCAL_SETUP.md`（环境事实）、`docs/DEV_LOG.md`（SAVE/ECO/FSM 既有约定）、项目 Skills `fishing-state-and-save`、`godot-validation`（本会话已加载）。
- **本票铁律：零数值调节。** 20/60 秒、30 FPS、容量 10、鱼价/权重全部按现状读取；任何调节只能出现在报告的「提请用户审核」建议中，由用户批准后才可另票执行（AGENTS.md §6、SDD §6、ACCEPTANCE §4）。

## 1. 目标

1. 新建 headless 经济模拟驱动（纯 GDScript，`extends SceneTree`），**复用**已验收的 `FishingStateMachine` + `DeterministicRng` + `VirtualClock` + `EconomyService`（+ 故障场景的 `AtomicSaveService`），不修改任何既有 `scripts/**` 代码。
2. **≥20 个不同固定种子**（首次取 20 个：`101..120`，写入报告 `seeds` 数组），每种子 × 两场景 × 三档虚拟时长（1h=3600s、4h=14400s、8h=28800s 虚拟秒）：
   - 场景 A「不售直到满篓」：从不售鱼，直到篮满后停止抛竿并统计剩余虚拟时间内的拒绝行为；
   - 场景 B「定期出售循环」：每 1800 虚拟秒（模拟策略常量，非产品数值）把篮内全部鱼按唯一 sale_event_id 出售一次并继续抛竿。
3. 统计并输出**机器可读 JSON 报告**（对齐 ACCEPTANCE §4 参考格式）：完整捕鱼周期 `CASTING+WAITING+HOOKED+REELING+SETTLEMENT` 的平均/中位/P10/P90；各 (seed,时长) 篮首次装满时间分布（均值/中位/P10/P90；8h 内始终不满时输出 `first_fill_seconds_p50=null` + 原因说明）；三鱼种捕获数、占比、总价值与每次售出金币；`duplicate_catch_transactions`、`duplicate_sale_transactions`、`casts_started_while_full` 三个硬门禁字段（必须为 0）；故障注入场景「恢复前新增已提交事务数」必须为 0。同时输出中文摘要 `report.md`。
4. 硬断言（任一失败 → 测试 FAIL → runner 退出 1，不得伪造）：
   - 每次 WAITING 的 `wait_seconds` ∈ [20,60]（T-TIME-01）；
   - 同 seed 同策略重放两次，事件序列摘要逐字段一致（确定性）；
   - 满篓后 `request_cast` 一律 `BASKET_FULL` 拒绝、FSM 绝不进入 `CASTING`（`casts_started_while_full == 0`，T-ECO-01）；
   - 每笔已提交 catch/sale 各抽样重试（每种子 ≥2 笔 catch、≥2 笔 sale，各重试至多 100 次）全部返回 `ALREADY_APPLIED`/幂等拒绝且金币、鱼篓零变化（`duplicate_*_transactions == 0`，T-ECO-02/03）；
   - 故障注入（场景 B 附加子场景，1 seed × 8h 虚拟）：武装 `rename`（或 `tmp_write`）注入后事务返回 `PERSIST_FAILED` 且权威状态零变化，解除后同 ID 重试成功——「保存故障期间/恢复前新增已提交事务」计数必须 0（T-SAVE-02 侧翼，SAVE-001 回归同时重跑）。
5. 新建 Python 标准库 runner（镜像 `tests/unit/run_save001_checks.py` 约定）：前置数值锁 → 复制项目到系统临时目录（排除 `.git/.godot/__pycache__/tasks/evidence`）→ 隔离 HOME → 串行 Godot headless 步骤 → 从 stdout 解析 JSON 报告写入 `tasks/evidence/SIM-001/`；主工程从不作为 Godot `--path`/cwd。
6. 明确排除：不改 `scripts/**`、`data/**`、`examples/**`、`schemas/**`、`tests/**`、`tools/auto/**`、`project.godot`、`docs/**`；不做 GUI/8h 真实稳定性（属 REL-001）；不引入第三方依赖（本机无 `jsonschema`，沿用纯标准库校验）；不联网、不装软件。

## 2. Phase A 只读实测记录（真实命令与退出码，2026-11-11 本会话）

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 工作树 | `git status --short` | 0 | 仅 runner 自有既有状态：` M tasks/evidence/_runner/runner.log`、` M tools/auto/queue.json`、`?? tasks/evidence/UI-001/phaseA.out` 等 5 个 UI-001 会话归档与 `?? tasks/evidence/_runner/runner.lock`；**均非本会话产生，无用户未提交代码**；本 Phase A 零改动 |
| 近期历史 | `git log --oneline -15` | 0 | HEAD=`f66f5c7 Tighten overlay mouse hit regions`；UI-001 系列在案；SAVE-001 验收 `7a363df`；FSM/ECO 验收链完整 |
| 分支 | `git branch --show-current` | 0 | `main` |
| 模拟目录 | `ls -la tools/sim` | **1** | **不存在** → Phase B 新建（与允许范围一致） |
| 证据目录 | `ls -la tasks/evidence/SIM-001` | 0 | 存在且为空（调度器已预建）；本计划为其内首个文件 |
| Godot 可执行 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| 队列契约 | `python3 -c "...queue.json..."` | 0 | SIM-001：status=`ready`、deps=[FSM-001,ECO-001,SAVE-001]（均 done）、allowed_files=[`tools/sim/**`,`tasks/evidence/SIM-001/**`]、test_cmd 空（Phase A 不会自动回填；委托审查者复核计划后在启用 Phase B 前登记）、needs_human=false；`frozen` 不存在，`unfrozen` 记录 2026-11-11T20:08Z 持续执行委托；UI-001=`blocked`（不阻断本票，SIM 不依赖 UI） |
| 数值锁基线 | `cat data/runtime_config.json; cat data/fish_species.json` | 0 | `30 FPS / 20–60s / 容量 10 候选`；鱼种 `river_carp 60/8`、`silver_perch 30/16`、`golden_trout 10/32` —— Phase B runner 数值锁即锁这组值 |
| 依赖代码 | 读 `scripts/fishing/{deterministic_rng,virtual_clock,fishing_state_machine}.gd`、`scripts/economy/{economy_service,fish_instance}.gd`、`scripts/core/game_state.gd` | 0 | 全部存在且为已验收实现（非骨架）：LCG 48271/2³¹−1、虚拟秒时钟、FSM 七态 + 内置满篓门禁 + 幂等 ack、经济指纹账本 + 持久化门 + `fish-<catch_id>` 实例 ID |
| 存档接口 | 读 `scripts/save/{save_service,save_faults}.gd` | 0 | `AtomicSaveService.configure_dir/install_into/set_fault_injection/set_pending_candidate/persist_runtime_checkpoint`；故障阶段 `tmp_write/tmp_flush/backup/rename/quarantine/legacy_copy` |
| 配置加载 | 读 `scripts/config/*.gd`、`tests/unit/test_fsm001_fsm.gd` | 0 | `FishSpeciesCatalog.load_catalog("res://data/fish_species.json")`、`RuntimeConfig.load_config(...)` 静态加载；`ConfigGate.can_start_economy` 已由 FSM `initialize` 内联调用（T-CONF-01 门禁复用） |
| runner 约定 | 读 `tests/unit/run_save001_checks.py` 全文 | 0 | 先导入后测试、逐 step 退出码 + 唯一 PASS 标记 + 禁 `SCRIPT ERROR`、隔离 HOME/临时副本/finally 清理、`GODOT_BIN` 可覆盖、TIMEOUT 600s/step |
| Skills | 会话技能目录实测 | 0 | `fishing-state-and-save`、`godot-validation` 已加载并遵守；`godot-overlay` 属 GUI 票，本票不使用 |
| Python | `python3 --version` | 0 | 3.15.2（仅标准库，与 AUDIT-001 一致） |
| 忽略规则 | `grep -n ".godot\|uid" .gitignore` | 0 | `.godot/`、`*.uid` 被忽略 → headless 缓存不污染 git |

## 3. Phase B 要改动的文件（全部为**新增**，严格限于允许范围）

| 文件 | 内容 |
|---|---|
| `tools/sim/sim001_economy_sim.gd` | `extends SceneTree` headless 模拟驱动：加载并校验配置 → 对 20 seeds × {A,B} × {1h,4h,8h} 跑事件驱动循环（§4 驱动循环）→ 计算统计 → stdout 打印 `SIM001_REPORT_BEGIN`/`SIM001_REPORT_END` 之间的单个 JSON 文档（§4.5 格式）+ 末行 `SIM001 SIM PASS`（`quit(0)`）或首个失败点 `SIM001 SIM FAIL: <step>`（`quit(1)`）。**自身不写任何文件**（故障子场景只写临时 HOME 内的存档目录，由 `configure_dir` 传入绝对路径） |
| `tools/sim/run_sim001_checks.py` | Python 标准库 runner，镜像 `run_save001_checks.py`：前置数值锁/文件齐全 → 隔离副本 + 隔离 HOME → step1 导入 → step2 模拟 → step3–6 FSM/ECO/SAVE/CORE/CFG 回归 → 解析 JSON 并写 `tasks/evidence/SIM-001/sim_report.json` 与 `tasks/evidence/SIM-001/report.md`（中文摘要，含「提请用户审核参数」段，不改数值）→ 全过 `SIM001 RUNNER PASS` 退出 0，否则退出 1 |
| `tasks/evidence/SIM-001/sim_report.json` | runner 在 Phase B 写出的真实模拟结果（机器可读，非示例；`notes` 标注执行时间/Godot 版本） |
| `tasks/evidence/SIM-001/report.md` | 中文摘要：矩阵统计、硬门禁字段、确定性重放结论、供用户批准的参数建议（仅建议，未改动） |
| `tasks/evidence/SIM-001/plan.md` | 本文件（Phase A 唯一产物） |

明确排除（不改）：`scripts/**`、`data/**`、`examples/**`、`schemas/**`、`tests/**`、`tools/auto/**`（queue `test_cmd` 由调度器按 §5 回填，非本票写入）、`project.godot`、`scenes/**`、`docs/**`、`tasks/TASKS.md`（状态由 AUTO-001 调度器记录）。禁止新增第三方依赖。

## 4. 接口与不变量

### 4.1 复用的既有接口（真实签名，只调用不修改）

```text
FishSpeciesCatalog.load_catalog("res://data/fish_species.json") -> {ok, ...}   # 非法 → ok=false，FSM 拒绝启动（T-CONF-01 复用）
RuntimeConfig.load_config("res://data/runtime_config.json") -> {ok, ...}
DeterministicRng: set_seed(seed:int)->Dictionary; next_int(); next_unit(); next_int_inclusive(lo,hi); snapshot_state/restore_state
VirtualClock: advance(seconds:float)->bool（负数/NaN/Inf 拒绝）; now()->float; reset()
FishingStateMachine:
  initialize(catalog, runtime, rng, clock, recovered_checkpoint:{}, stage_durations:={}) -> {ok, error_code?}
  can_cast(state:GameState)->bool                       # IDLE + basket<size capacity 门禁
  request_cast(state)->{ok, rejected_reason, catch_event_id, wait_seconds}  # 满篓 BASKET_FULL 拒绝且 RNG 不变
  tick_effective(seconds)->Array[Dictionary]            # 单步至多 1 转换，过冲结转（T-TIME-02 步长不变性）
  produce_catch_candidate()->{ok, code, catch_event_id, species_id, weight_snapshot, caught_at_clock}
  ack_settlement(catch_event_id, committed)->{ok, next_state, code}
EconomyService:
  initialize(catalog, runtime)->{ok, code}
  set_persistence_gate(Callable)->{ok, code}            # 场景 A/B 用内存门（恒 true，无文件 IO）
  commit_catch(state, catch_event_id, species_id, caught_at_utc)->{ok, code, instance_id}   # ALREADY_APPLIED 幂等
  sell_fish(state, sale_event_id, instance_ids)->{ok, code, gold_added}
  snapshot_ledger()->{processed_catches, processed_sales}
AtomicSaveService（仅故障子场景）:
  configure_dir(绝对临时目录); install_into(economy,state,rng,clock,fsm,valid_species_by_id)
  set_fault_injection("tmp_write"|"rename"|..., armed); set_pending_candidate/clear_pending_candidate
```

### 4.2 模拟策略常量（**仅测试参数，非产品数值**；SDD §6 明示 cast/reel 时长为技术测试配置，ACCEPTANCE §4 明示种子数为测试建议值）

```text
SEEDS = [101..120]（20 个固定种子，写入报告）
Durations = {1h:3600, 4h:14400, 8h:28800} 虚拟秒；TICK = 1.0 秒固定步长
stage_durations = {casting_sec:1.0, hooked_sec:1.0, reeling_sec:1.0}   # FSM 默认技术值，未改任何配置
SALE_EVERY_SEC(场景B) = 1800；故障子场景：seed=101、场景B、8h，在 3600s 与 7200s 之后分别于下一笔确定会执行的 catch/sale 写盘前武装故障，验证失败后解除并以同一事务 ID 重试
EPOCH_UTC = 2026-01-01T00:00:00Z + int(clock.now()) 秒，纯整数历法格式化（自实现 civil-from-days，
  输出必须匹配 FishInstance.UTC_PATTERN；不用本机时钟/时区，保证跨机确定）
sale_event_id = "sale-<seed>-<seq>"（seq 进程内单调整数；与 FSM 的 "catch-<rng>-<rng>" 命名空间不冲突）
```

### 4.3 每 (seed, scenario) 驱动循环（事件驱动，串行单线程）

1. 新 `GameState` + 新 `DeterministicRng(seed)` + 新 `VirtualClock` + `EconomyService.initialize` +（A/B：内存门恒 true；故障场景：`install_into` 装配）。
2. IDLE 且 `can_cast` → `request_cast`；记录 `wait_seconds` 与周期起点 `clock.now()`。
3. 反复 `tick_effective(1.0)` 直到 SETTLEMENT；`produce_catch_candidate` → `commit_catch(state, id, species, utc_string)` → `ok` 则 `ack_settlement(id,true)` 并记录周期终点、鱼种与价格快照。
4. `commit_catch` 返回 `BASKET_FULL`（理论不应发生，因抛竿门禁在前）→ 记入 `casts_started_while_full` 硬门禁并 FAIL。
5. 场景 A：篮满后仍每 60 虚拟秒尝试一次 `request_cast`（模拟用户持续点击），断言全部 `BASKET_FULL` 且 FSM 停留 IDLE。
6. 场景 B：到 1800s 周期点若篮非空 → `sell_fish` 全篮（唯一 sale id），记录 `gold_added`；断言容量恢复后继续抛竿。
7. 每 (seed, scenario, 时长) 独立运行（1h/4h/8h 互不复用状态；各时长从干净态起跑）。

### 4.4 统计与硬门禁定义（报告字段语义）

- 完整周期 = 同一次结算的 `request_cast` 时刻到 `ack_settlement` 成功时刻的虚拟秒差；聚合 mean/median/p10/p90（对全部周期样本）。
- 首次装满时间 = 场景 A 中第 10 次成功 `commit_catch` 的虚拟时刻；8h 内不满 → 该 seed 该时长 `first_fill_seconds_p50=null` + `never_full_reason:"cycles_exhausted_by_horizon"`。
- `duplicate_catch/sale_transactions`：账本指纹中被**二次实际生效**（金币/鱼篓再变化）的次数；幂等 `ALREADY_APPLIED` 重试不计数。
- `casts_started_while_full`：篮满状态下出现 `IDLE→CASTING` 转换的次数（从 transition_log 断言，必须 0）。
- 故障字段 `fault_transactions_committed_before_recovery`：故障武装期间成功提交的 catch/sale 数（必须 0）。
- 确定性摘要：对重放对比的事件序列逐条取 `(event_id, state 名, species_id, wait_seconds, gold_added)` 拼接哈希（不哈希原始浮点，避免无意义抖动）。

### 4.5 JSON 报告格式（ACCEPTANCE §4 参考格式的真实执行版）

```json
{ "suite": "economy-simulation", "build_id": "unreleased-local", "godot_version": "4.7.2.stable.official.ed1daf0bf",
  "seeds": [101,102,"...20 个"], "virtual_hours": [1,4,8], "scenarios": ["hold_until_full","periodic_sell_1800s"],
  "summary": { "basket_capacity": 10, "bite_wait_min_sec": 20, "bite_wait_max_sec": 60,
    "first_fill_seconds": {"mean": 0, "median": 0, "p10": 0, "p90": 0},
    "cycle_seconds": {"mean": 0, "median": 0, "p10": 0, "p90": 0},
    "species_counts": {}, "species_share": {}, "species_total_value": {}, "gold_per_sale": {"mean": 0},
    "duplicate_catch_transactions": 0, "duplicate_sale_transactions": 0,
    "casts_started_while_full": 0, "fault_transactions_committed_before_recovery": 0,
    "wait_seconds_out_of_range": 0, "deterministic_replay_identical": true },
  "per_run": [{"seed": 101, "scenario": "hold_until_full", "virtual_hours": 1,
    "cycles_completed": 0, "first_fill_seconds": null, "never_full_reason": "cycles_exhausted_by_horizon",
    "species_counts": {}, "species_total_value": {}, "sales": []}],
  "fault_injection": [{"stage": "rename", "armed_at_or_after_seconds": 3600,
    "failed_transaction_id": "...", "failure_code": "PERSIST_FAILED", "same_id_retry_code": "", "state_unchanged": true}],
  "pass": true, "notes": ["SIM001 真实执行结果，非示例；参数未改动，调节建议见 report.md"] }
```

（示例仅示形状；`per_run` 必须恰有 120 条（20 seeds × 2 scenarios × 3 horizons）；Phase B 写出的是真实计算值；`pass` 由硬门禁真实决定，任何门禁失败必须 `pass:false` 且 runner 退出 1。）

## 5. 精确测试命令与预期退出码

Phase A 完成后，委托审查者先记录 Phase B 批准，再在调度器元数据中登记下列 `test_cmd` 并将状态转为 `exec_ready`；AUTO-001 不会自动补全空测试命令。Phase B 本地 Qwen 仍只可改 `tools/sim/**` 与 `tasks/evidence/SIM-001/**`：

```text
python3 -B tools/sim/run_sim001_checks.py            # 预期 exit 0；stdout 恰含一次 SIM001 RUNNER PASS
```

runner 内部（串行，任一步不满足即整票退出 1 并打印 `SIM001 RUNNER FAIL`，不伪造退出码）：

| step | 命令 | 预期退出码 | 附加判定 |
|---|---|---|---|
| pre | 数值锁：`data/*.json`==`examples/*.json` 逐值；20/60/30/10、权重 60/30/10、价格 8/16/32 常量锁；交付文件齐全；`tools/sim/**` 无对 `res://` 写文件的可疑路径 | 0 | 任一偏差 → 前置 FAIL，不进 Godot |
| step1 | `Godot --headless --path <临时副本> --editor --quit` | 0 | 无 `SCRIPT ERROR` |
| step2 | `Godot --headless --path <临时副本> --script res://tools/sim/sim001_economy_sim.gd` | 0 | stdout 恰含一次 `SIM001 SIM PASS`、无 `SIM001 SIM FAIL`、`SIM001_REPORT_BEGIN/END` 间为合法 JSON 且三个硬门禁字段 == 0、`wait_seconds_out_of_range`==0、`deterministic_replay_identical`==true |
| step3 | `... --script res://tests/unit/test_fsm001_fsm.gd`（FSM 回归） | 0 | `FSM001 FSM PASS` 恰一次 |
| step4 | `... --script res://tests/unit/test_eco001_economy.gd`（ECO 回归） | 0 | `ECO001 ECONOMY PASS` 恰一次 |
| step5 | `... --script res://tests/unit/test_save001_save.gd`（SAVE 回归） | 0 | `SAVE001 SAVE PASS` 恰一次 |
| step6 | `... --script res://tests/unit/test_core001_smoke.gd` 与 `test_cfg001_config.gd`（CORE+CFG 回归） | 0 | 两个 PASS 标记各恰一次 |

- 任一步出现 `SCRIPT ERROR` 即判失败（沿用既有 runner 约定）；每步 TIMEOUT 600s（预计全 suite 数分钟：约 40 个 seed×场景组合 + 8h 故障子场景共 ~4.5 万周期，纯内存 LCG 循环，无逐帧渲染）。
- 环境：临时项目副本 + 隔离 HOME（`tempfile.TemporaryDirectory`，finally 清理）；`GODOT_BIN` 环境变量可覆盖引擎路径；主工程从不作为 `--path`/cwd。
- 可选复核（不属 test_cmd）：`python3 -B tools/auto/runner.py selftest` → 0（runner 自有自测，只读复核用）。

## 6. 风险与回滚

| # | 风险 | 处置 / 回滚 |
|---|---|---|
| R-1 | 误改数值即污染已冻结参数 | runner 前置数值锁（R-4 同款）：`data==examples` 逐值 + 常量锁 20/60/30/10 + 60/30/10 + 8/16/32，任何漂移 → 前置 FAIL；本票全部改动为 `tools/sim/**` + 证据目录**新增**，回滚 = 删除 `tools/sim/` 与 `tasks/evidence/SIM-001/`（Phase B 新增文件），基线 = Phase B 前的 commit，`git revert`/`git checkout <baseline> -- tools/sim` 均可整体恢复 |
| R-2 | 模拟写成 1s×8h 大循环拖慢 CI | 事件驱动 + 单步 1s 也仅 ~1.9×10⁶ 次纯整数 tick（GDScript 秒级）；仍超 600s/step 则判 FAIL 并记入报告，不放宽断言；必要时仅减小 TICK 步数（不改变事件语义），不改任何业务数值 |
| R-3 | 浮点累计导致跨机不可复现 | 事件字段取整（`int(clock.now())`、整数秒 wait、整数金币）；重放对比用逐字段哈希而非原始 float 位型；LCG 为纯 int 数学（FSM-001 已验收跨步确定性） |
| R-4 | UTC 字符串格式化依赖本机时区/引擎版本差异 | 模拟内自实现纯整数历法（civil-from-days），格式必须匹配 `FishInstance.UTC_PATTERN`，并在确定性重放中断言一致；不读系统时钟 |
| R-5 | 故障子场景写盘污染真实存档 | `AtomicSaveService.configure_dir` 指向临时副本内绝对临时目录 + 隔离 HOME；runner finally 清理；主工程 `user://` 与 `~/Library/Application Support/Godot` 不触碰（AUDIT-001 已核实无路径冲突） |
| R-6 | 报告被误读成「已批准调节」 | report.md 固定段落声明：参数**未改动**，统计仅构成建议输入，须用户批准后才可另票调节（AGENTS.md §6） |
| R-7 | 新全局类名冲突 | 模拟脚本不声明 `class_name`（`extends SceneTree` 脚本 + preload 引用），零全局类新增；runner 前置检查 `scripts/**` 类名计数不变 |
| R-8 | UI-001 仍 blocked 造成误解 | 本票不依赖 UI-001（deps 仅 FSM/ECO/SAVE，均 done）；runner 不含 UI 回归、不启动 GUI；UI-001 的 GUI 阻塞原样保留 |
| 回滚总述 | 任一失败 | 不改测试断言造假（AGENTS.md/godot-validation §4）；失败日志、退出码、`sim_report.json`（`pass:false`）如实归档 `tasks/evidence/SIM-001/`，交 AUTO-001 重试或人工审查；整票回滚仅删本票新增文件 |

## 7. 验收条目映射

| 验收条目 | 本票覆盖方式 | 证据 |
|---|---|---|
| SDD-178 / SDD V01-T02（多种子 1h/4h/8h，周期/满篓分布/鱼种占比与价值） | step2 模拟 20 seeds × 2 场景 × 3 时长；§4.4 统计族 | `tasks/evidence/SIM-001/sim_report.json` + `report.md` |
| 工单最小验收「重复交易/满篮新抛竿=0」 | `duplicate_catch/sale_transactions==0`、`casts_started_while_full==0` 硬门禁 | 同上 + runner stdout |
| T-TIME-01（wait ∈ [20,60]、同 seed 可复现） | step2 断言 + 确定性重放对比 | `sim_report.json.summary.wait_seconds_out_of_range=0`、`deterministic_replay_identical=true` |
| T-TIME-02（步长/渲染无关） | 固定 1.0s 虚拟步长 + FSM 既有单步单转换契约；step3 FSM 回归复跑 | step2/step3 退出码 0 |
| T-ECO-01（满篓停抛、售后可续） | 场景 A 满篓拒绝矩阵 + 场景 B 售出恢复抛竿 | step2 报告 |
| T-ECO-02/03（catch/sale ID 重试 ≤1 次生效） | 每种子抽样重试至多 100 次，断言 `ALREADY_APPLIED` 且状态零变化 | step2 报告 + step4 ECO 回归 |
| T-SAVE-02 侧翼（保存故障不产生半提交/新事务） | 故障子场景（`tmp_write`/`rename` 武装→`PERSIST_FAILED`→解除重试）+ step5 SAVE 回归 | `fault_transactions_committed_before_recovery=0` |
| T-CONF-01 边界（非法配置阻断经济） | 模拟经 `FishingStateMachine.initialize` 内联 `ConfigGate` 加载真实配置；runner 前置数值锁 | 前置检查输出 |
| ACCEPTANCE §4「参数调整提交用户审核」 | report.md「提请用户审核」建议段；本票零数值改动 | `report.md` |
| 「数值调节必须人工批准」（工单摘要/AGENTS §6） | 数值锁使任何调节令 runner 红；建议仅成文不改值 | 前置数值锁 + report.md |

## 8. 判定

- 本票为纯统计/模拟票：不调节数值、不破坏存档、不改变需求边界、无 GUI/网络/安装动作；允许范围与 queue 契约一致；前置依赖全部 Accepted。无需 Phase A 即转人工的决策点（参数调节属报告之后的用户批准事项，不由本票实施）。

PHASE-A-DONE
