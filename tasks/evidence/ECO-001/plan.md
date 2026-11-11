# ECO-001 Phase A 计划 — 唯一鱼实例 / 有限鱼篓 / 出售与金币（AUTO-001，只读规划）
- 固定业务约束：可见桌面 **30 FPS**；自动捕鱼随机上钩等待初始 **20–60 秒**；独立游戏逻辑时钟；约三种鱼可配；鱼篓容量 **10 格仅为候选初值**；满篓不发起新抛竿；一次鱼对应唯一实例 ID；出售按唯一事件/事务 ID 原子扣鱼加币；崩溃重试不重复结算。

- 工单：ECO-001「唯一鱼实例/有限鱼篓/出售与金币模型」，前置 FSM-001（done/Accepted，commit `9edd9a6`），最小验收 **T-ECO-01～04（内存测试）**，来源 `tasks/TASKS.md`「ECO-001 + SAVE-001（不可拆开的核心安全要求）」段与 `tools/auto/queue.json`（status=ready、needs_human=false、test_cmd 空待回填）。
- 允许文件范围（Phase B 强制）：`scripts/economy/**`、`tests/**`。本 Phase A 全程只读，唯一写入即本文件；未读取 `tasks/APPROVALS.md`；未执行任何 git 写操作。
- 依据：`docs/INTERFACES_AND_DATA.md` §2/§3/§5/§6（鱼实例合同、GameState schema、经济命令、事务失败序列）、`docs/ARCHITECTURE.md` §2/§5（经济所有权、提交顺序）、`docs/SDD_v0.1.md` V01-E01/E02/S01/S02 与 §4 时序/§6 参数表、`docs/DECISION_REGISTER.md` SDD-143/155-156/172/173、`docs/ACCEPTANCE_TESTS.md` §2、`docs/REQUIREMENTS_CHANGELOG.md`（2026-11-11 委托冻结：捕获时价格快照采纳、容量 10 保持候选）、FSM-001 移交项（`tasks/evidence/FSM-001/report.md` R-3：ECO-001 落账复核同 catch/sale ID 重试不重复入篮/加币）、项目 Skills `fishing-state-and-save`、`godot-validation`。

## 1. 目标

1. 在 `scripts/economy/` 实现**纯内存**经济事务层（本票最小验收即"内存测试"）：`commit_catch` 以唯一 `catch_event_id` 生成唯一 `instance_id` 鱼实例并扣容量，`sell_fish` 以唯一 `sale_event_id` 原子删鱼加币；两者幂等——同 ID 重试 `AlreadyApplied`，绝不重复发鱼/加币（SDD-143/172、INTERFACES §5）。
2. `GameState`（`scripts/core/game_state.gd`，本票**不修改**）为金币/鱼篓/事务 ID 唯一权威：经济服务经引用修改其 `wallet_gold / basket / processed_catch_ids / processed_sale_ids / revision`；FSM、UI 只读。满篓（`basket.size() >= basket_capacity`，容量 10 候选值只读）时 `commit_catch` 显式拒绝且 FSM `request_cast` 已有门禁回归复测（T-ECO-01）。
3. 捕获时锁定 `sale_price_at_catch` 价格快照（2026-11-11 委托裁定）；后续目录价格变化不追溯已捕获实例。金币恒为非负整数；所有错误路径（重复/不存在/越权 ID、非法价格、容量冲突）返回稳定错误码且**零副作用**（T-ECO-04）。
4. 预留**持久化门（persistence gate）注入点**：默认内存恒真门；SAVE-001 在自身范围（`scripts/save/**`）注入 SaveService 的原子写盘，实现"先持久化成功、后发布已确认"（INTERFACES §6）。门参数必须是包含完整 next-state 与事务指纹账本的深拷贝；SAVE-001 原子持久化二者。本票**零文件写入、不触碰 `user://`**。
5. 新增 headless GDScript 单测与本票 runner（Python 标准库），PASS→exit 0 / FAIL→exit 1，并回归 CORE-001 / CFG-001 / FSM-001 既有测试不被新全局类破坏。
6. 本票**不做**：存档写盘/备份/故障注入落盘（SAVE-001）、售鱼 UI（UI-001）、日志文件（LOG-001）、多种子模拟报告（SIM-001）、任何经济数值改动。

## 2. Phase A 只读实测记录（真实命令与退出码，2026-11-11 本会话）

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 工作树 | `git status --short --branch` | 0 | Phase A 启动前 `52ab254` 工作树干净；运行时看到的 runner.log、活动 runner.lock、队列状态变化属于本次 AUTO-001 调度器，不是 Qwen 改码；Phase A 代理仅新增本计划 |
| 近期历史 | `git log --oneline -15` | 0 | HEAD=`52ab254 Queue ECO-001 for read-only planning`；FSM-001 验收 `9edd9a6`、实现 `8732c8f`+`2d859aa`；证据链完整 |
| Godot 可执行 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| 目录 | `ls -R scripts tests data tasks/evidence` 等 | 0 | `scripts/{config,core,fishing,io,platform,presentation}` 存在；**`scripts/economy/` MISSING**（Phase B 新建，与允许清单一致，零范围偏差）；`tasks/evidence/ECO-001/` 已存在且为空 |
| 权威状态 | 读 `scripts/core/game_state.gd` | 0 | 纯数据镜像 INTERFACES §3 schema v1；注释明示「事务、持久化属 ECO-001/SAVE-001」——本票即该事务层的实现票 |
| FSM 接口 | 读 `scripts/fishing/fishing_state_machine.gd`（490 行全文） | 0 | `request_cast(GameState)` 内置满篓拒绝（`BASKET_FULL`、RNG 不消耗）；`produce_catch_candidate` 返回 `{catch_event_id, species_id, weight_snapshot{catch_weight,base_price,rarity}, caught_at_clock}`；`ack_settlement` 幂等 `AlreadyApplied`；FSM 绝不写 GameState |
| 经济骨架 | grep `class_name` 全仓 `.gd` | 0 | 15 个全局类；**无 economy 相关类**——拟用 `EconomyService`、`FishInstance` 均未占用 |
| 配置/数据 | 读 `data/fish_species.json`、`data/runtime_config.json`、`examples/save_v01.json`、`schemas/game-save.schema.json` | 0 | 3 鱼种 60/30/10、8/16/32；20/60s、30FPS、容量 10 候选；save v1 要求鱼实例 5 键与 processed ids 唯一 |
| 门禁复用 | 读 `scripts/config/config_gate.gd`、`runtime_config.gd`、`fish_species_catalog.gd` | 0 | `ConfigGate.can_start_economy(catalog, runtime)` 可直接复用为经济服务启动门禁（T-CONF-01 交界） |
| 测试基线 | 读 `tests/unit/run_fsm001_checks.py`、`test_fsm001_fsm.gd` 首尾 | 0 | 既有约定：`extends SceneTree`、PASS→quit(0)/FAIL→quit(1)、runner 先复制工程到系统临时目录+隔离 HOME 再跑 Godot、**禁止对主工程直接跑 Godot**、拒绝 SCRIPT ERROR、value-lock（data==examples）Python 复核 |
| 运行器契约 | 读 `tools/auto/queue.json` ECO-001 条目、`tools/auto/README.md` | 0 | allowed_files=`scripts/economy/**`,`tests/**`；test_cmd 空（调度器按 §5 回填）；needs_human=false；批准/解冻均归人工，Agent 不写 APPROVALS/queue |
| Python | `python3 --version` | 0 | 3.15.2（仅标准库；无 jsonschema，与 AUDIT-001 一致） |
| 忽略规则 | 读 `.gitignore` | 0 | `.godot/`、`*.uid` 被忽略；`/save/`、`game_state*.json` 被忽略（存档不落源码树） |
| Skills | 会话技能目录实测 | 0 | `fishing-state-and-save`、`godot-validation` 已加载并遵循 |

## 3. Phase B 要改动的文件（全部为**新增**，严格限于允许范围）

| 文件 | 内容 |
|---|---|
| `scripts/economy/fish_instance.gd` | `class_name FishInstance extends RefCounted`：鱼实例静态工厂/校验器——`make(catch_event_id, species_entry, caught_at_utc)` 产出 schema v1 五键字典 `{instance_id, species_id, caught_at_utc, source_event_id, sale_price_at_catch}`；`instance_id = "fish-" + catch_event_id`（每 catch 事件至多结算一条鱼 ⇒ 构造性唯一）；`validate(entry)` 逐字段校验（字符串非空、价格为非负整数、UTC 时间戳格式） |
| `scripts/economy/economy_service.gd` | `class_name EconomyService extends RefCounted`：经济事务服务（§4 接口）；内存内 `transaction_log`（结构化字典数组，供测试断言与 LOG-001 复用，**不写文件**）与请求指纹账本（catch/sale ID → 参数指纹，供同 ID 异参冲突检测）；可注入 `persistence_gate: Callable`（默认恒真） |
| `tests/unit/test_eco001_economy.gd` | `extends SceneTree` headless 单测：全部通过打印 `ECO001 ECONOMY PASS` 且 `quit(0)`；首个失败打印 `ECO001 ECONOMY FAIL: <step>` 且 `quit(1)`（沿用 CORE/CFG/FSM 约定）；覆盖矩阵 E1–E11（§5） |
| `tests/unit/run_eco001_checks.py` | Python 标准库 runner（镜像 `run_fsm001_checks.py`）：预检交付物 + value-lock（`data/` 与 `examples/` 逐值一致，20/60/30/10 与鱼价防误改）→ 复制工程到系统临时目录（排除 `.git/.godot/tasks/evidence/__pycache__`）→ 隔离 HOME → 串行 step1 导入（`--editor --quit`）、step2 ECO 单测、step3 CORE 回归、step4 CFG 回归、step5 FSM 回归；每步判退出码 0 + 必需 PASS 标记 + 无 FAIL 标记/`SCRIPT ERROR`；finally 清理副本与 HOME；真实工程路径绝不作为 Godot `--path/cwd` |

不改动（明确排除）：`scripts/core/**`（GameState 仅被引用修改其字段，源文件不动）、`scripts/fishing/**`、`scripts/config/**`、`scripts/io/**`（SaveService 骨架留给 SAVE-001）、`data/**`、`examples/**`、`schemas/**`（game-save v1 已够用，本票不扩键）、`scenes/**`、`project.godot`、`docs/**`、`tasks/**`（证据目录由 runner 归档）、`tools/auto/queue.json`（RUNNER_OWNED，test_cmd 由调度器回填，见 §5）。禁止新增第三方依赖。

## 4. 接口与不变量

**EconomyService**（对齐 INTERFACES §5 伪接口；签名可记录为契约，语义与不变量不可擅改）：

```text
initialize(catalog: Dictionary, runtime: Dictionary) -> {ok: bool, error_code: String}
  # 先过 ConfigGate.can_start_economy；任一非法 → ok=false + "catalog:<CODE>"/"runtime:<CODE>"，
  # 零副作用、零默认值，且拒绝后全部命令返回 NOT_INITIALIZED（T-CONF-01 经济侧）。
set_persistence_gate(gate: Callable) -> {ok, code}
  # gate(payload: Dictionary) -> bool；默认恒真（内存模式）。SAVE-001 注入 SaveService 原子写盘；
  # gate 返回 false → 本次事务 PERSIST_FAILED 且 GameState 完全不变（INTERFACES §6「保存失败保留旧权威状态」）。
commit_catch(state: GameState, catch_event_id: String, species_id: String, caught_at_utc: String)
    -> {ok, code, instance_id}          # 成功 code=""；AlreadyApplied 时 ok=true、code="ALREADY_APPLIED"、鱼不重复入篮
sell_fish(state: GameState, sale_event_id: String, instance_ids: Array)
    -> {ok, code, gold_added}           # 成功 code=""、gold_added=Σ sale_price_at_catch；AlreadyApplied 时 gold_added=0
snapshot_ledger() -> Dictionary          # {processed_catches: {id: 指纹}, processed_sales: {id: 指纹}}，供测试/SAVE-001 重建
restore_ledger(state: GameState, ledger: Dictionary) -> {ok, code}
  # SAVE-001 从已提交存档恢复；必须 fail-closed 校验形状、指纹与 state.processed_*_ids 一致。
get_transaction_log() -> Array           # 深拷贝内存事务日志（LOG-001 后续复用）
```

**稳定错误码**：`NOT_INITIALIZED`、`NULL_GAME_STATE`、`BAD_STATE`（GameState 关键字段/篮元素不满足契约）、`BAD_EVENT_ID`（空/非字符串）、`UNKNOWN_SPECIES`、`BAD_TIMESTAMP`（UTC 时间无效）、`BASKET_FULL`（`basket.size() >= basket_capacity` 时 commit_catch 拒绝）、`ALREADY_APPLIED`、`CONFLICT_CATCH_PARAMS` / `CONFLICT_SALE_PARAMS`（同 ID 异参，INTERFACES §5「不以 AlreadyApplied 掩盖不一致请求」）、`UNKNOWN_INSTANCE`、`BAD_INSTANCE_LIST`（非数组/空数组/含非字符串或空串元素）、`BAD_PRICE`（篮内价格非非负整数）、`GOLD_OVERFLOW`（金币加总溢出）、`PERSIST_FAILED`（注入门失败）。售鱼清单中的重复 instance ID 按 INTERFACES §5 去重后计算；同一 `sale_event_id` 的重复事务按 `ALREADY_APPLIED` 返回，绝不重复加币。

**不变量（Phase B 必守）**：
- 纯 RefCounted 数据层：无 Node/`_process`/`_physics_process`、无 Engine 帧/时间 API、不读写 `user://`、无任何文件写入。
- 单一权威：只有 EconomyService 写 GameState 的 `wallet_gold/basket/processed_*_ids/revision`；FSM/UI 只读（FSM-001 已保证 FSM 侧零写入）。
- 所有命令「先全量校验 → 构造 next 值 →（持久化门）→ 一次性提交」：任一失败路径对 GameState 各字段**零副作用**（E7 深比较断言）；绝不在原状态上乐观加币。门只收到 state 与 ledger 的深拷贝；门返回非 bool/非 true 或调用失败均按 `PERSIST_FAILED` 拒绝，且不得污染原状态。
- 幂等：同 `catch_event_id` 重试 ≤1 条鱼、同 `sale_event_id` 重试 ≤1 次加币（T-ECO-02/03 以 100 次重试断言）；成功提交 `processed_catch_ids`/`processed_sale_ids` 追加唯一 ID，`revision += 1` 单调递增。
- `instance_id` 唯一且确定：`"fish-" + catch_event_id`；`sale_price_at_catch` 在 commit 时从已校验 catalog 的 `base_price` 快照（整数 ≥0），此后目录变化不追溯（E6）。
- `wallet_gold` 恒为非负整数（prices 已校验 ≥0、求和整数、断言不减为负）；金币溢出返回 `GOLD_OVERFLOW`；`basket.size() <= basket_capacity` 恒成立（对齐 game-save schema `$comment`）。
- 串行落账：方法同步、单线程、一次一条命令；GameController/UI（后续票）必须仅经本服务变更经济状态，禁止旁路（TASKS「同一命令队列串行处理」）。
- 经济参数（20/60 s、30 FPS、容量 10、鱼价权重）**只读取不修改**；runner value-lock 复核。
- 新类名 `EconomyService` / `FishInstance` 实测未占用（§2），防止全局类冲突连累回归。

## 5. 精确测试命令与预期退出码

主测试（Phase B 完成后执行；test_cmd 供调度器回填 `tools/auto/queue.json`，本票不自改该文件）：

1. 主入口（建议回填为 queue 的 test_cmd）：
   `python3 -B tests/unit/run_eco001_checks.py`
   预期退出码 **0**，stdout 含 `ECO001 RUNNER PASS`；任一步失败退出 **1** 且含 `ECO001 RUNNER FAIL`。runner 内部：预检交付物 + data==examples 逐值一致 → 隔离副本内串行 5 步，每步退出码 0 + 必需标记 + 无 FAIL 标记/`SCRIPT ERROR`，不伪造退出码。
2. runner 各步（在隔离临时副本内，真实工程零接触）：
   - step1 `Godot --headless --path <副本> --editor --quit` → **0**（导入新全局类）
   - step2 `... --script res://tests/unit/test_eco001_economy.gd` → **0** + `ECO001 ECONOMY PASS`（FAIL 时 **1**）
   - step3 `... --script res://tests/unit/test_core001_smoke.gd` → **0** + `CORE001 SMOKE PASS`
   - step4 `... --script res://tests/unit/test_cfg001_config.gd` → **0** + `CFG001 CONFIG PASS`
   - step5 `... --script res://tests/unit/test_fsm001_fsm.gd` → **0** + `FSM001 FSM PASS`
   禁止直接对 `/Users/rain/DevGame/Fishing` 跑 Godot（用户编辑器常驻；FSM-001 先例）。
3. 范围自检：`git status --porcelain` 不要求全树干净；允许本票 `scripts/economy/**`、`tests/**`、`tasks/evidence/ECO-001/**`，以及 runner 的队列快照和 `_runner/runner.log`；必须无其他越界路径。不得恢复或清理已有 queue/log 状态。

**test_eco001_economy.gd 覆盖矩阵**：
- E1 满篓阻断+恢复（T-ECO-01）：FSM+经济联动——9 篓抛竿成功、结算后满 10 → `request_cast` 拒绝 `BASKET_FULL` 且 RNG 不消耗；售 1 条后重新可抛竿。
- E2 catch 幂等（T-ECO-02）：同 `catch_event_id` 重试 100 次 → 恰 1 条鱼入篮、`processed_catch_ids` 恰 1 项、`revision` 恰 +1。
- E3 sale 幂等（T-ECO-03）：同 `sale_event_id` 重试 100 次 → 金币恰 +1 次、被售实例不复活、篮数稳定。
- E4 错误矩阵（T-ECO-04）：售不存在实例 ID；清单重复 ID 去重且只计一次；同 sale ID 重试返回 `ALREADY_APPLIED`；空数组/非字符串元素；非法 species；空/非法 event ID；满篓 commit；负价格/畸形篮元素；金币溢出——各返回 §4 稳定码（重复清单按契约去重）、零状态副作用；全程断言 `wallet_gold >= 0`。
- E5 同 ID 异参冲突：同 catch ID 换 species → `CONFLICT_CATCH_PARAMS`；同 sale ID 换实例清单 → `CONFLICT_SALE_PARAMS`；均不加双币并入 `transaction_log`。
- E6 价格快照：commit 后篡改目录 `base_price` 副本 → 售鱼仍按 `sale_price_at_catch` 加币（2026-11-11 裁定）。
- E7 失败零副作用：对 E4/E5/PERSIST_FAILED 每例深拷贝前后 GameState 逐字段比对（含 basket 元素顺序）。
- E8 FSM↔经济集成（FSM 报告 R-3）：完整周期 → `produce_catch_candidate` → `commit_catch`（payload 逐字段）→ 鱼含 `source_event_id`=候选 event_id、`instance_id="fish-"+id` → `ack_settlement(true)` → IDLE 可再抛竿。
- E9 非法配置拒绝：`res://tests/unit/fixtures/cfg001/min_gt_max.json` 经 RuntimeConfig+ConfigGate → initialize 失败 → commit/sell 全拒（T-CONF-01 经济交界）。
- E10 持久化门失败：注入 false、非 bool、失效/报错 Callable → commit/sell 返回 `PERSIST_FAILED` 且 GameState/ledger 不变；修改 gate 收到的深拷贝不能污染原数据（SAVE-001「写成功才发布」前置形状；本票零写盘）。
- E11 跨实例恢复：新 EconomyService 从同一 GameState + `snapshot_ledger()` 深拷贝 `restore_ledger()` 后，同 ID 同参返回 `ALREADY_APPLIED`、异参返回冲突且零状态副作用；坏 ledger 或与 processed ID 不一致时 fail-closed。

## 6. 风险与回滚

- **D-1 范围**：零偏差——实现全部落在允许清单 `scripts/economy/**`、`tests/**`；`scripts/economy/` 为新建目录（实测 MISSING）。
- **R-1 GameState 越界风险**：GameState 位于 `scripts/core/**`（不在允许清单）。处置：只经引用改其运行时字段（其骨架注释本就声明事务属 ECO-001），**不修改该源文件**；不新增 GameState 方法。
- **R-2 跨会话 ID 碰撞**：catch 事件 ID 来自 LCG，同种子新会话可重发同 ID。ECO 提供可导出/恢复的指纹账本并随 next-state 一并交给持久化门；SAVE-001 必须原子保存/恢复此账本及 FSM-001 移交的 RNG/Clock 快照与 pending candidate，不能只恢复 `processed_*_ids` 后丢失异参冲突检测。
- **R-3 runner 门禁误报**：headless 可能再生 `.godot/` 缓存或 `icon.svg.import`（CORE/CFG/FSM 已知现象）：如实记录 report，**不得** git restore/commit/杀用户进程，交 runner 豁免逻辑（FSM-001 R-5 先例；Godot 编辑器常驻）。
- **R-4 经济参数误改**：Phase B 不写 `data/`；GDScript 测试 + Python runner 双重 value-lock 锁定 20/60/30/10 与 8/16/32 现值；任何调节须用户批准（SDD §6）。
- **R-5 长输出/上下文风险（OPEN-005）**：交付拆小文件（服务 ≤450 行、测试 ≤600 行、runner ≤200 行），避免单次超长输出截断。
- **回滚**：Phase B 全部为新增未跟踪文件，回滚 = 仅删除 `scripts/economy/`、`tests/unit/test_eco001_economy.gd`、`tests/unit/run_eco001_checks.py`；无已跟踪文件被修改，`git checkout -- .` 不适用；禁止 `git clean -fdx`（会波及 `tasks/evidence/_runner/`）；基线 commit `52ab254` 可逐票 diff。
- **审批判定**：本票不改需求、不改经济数值、不实施存档迁移、不触隐私/网络/付费；`basket_capacity=10` 与 `sale_price_at_catch` 按 2026-11-11 委托冻结裁定原样实施。队列 `needs_human=false`，且项目所有者已委托 Codex 逐票批准本地 v0.1；Phase B 批准限 `scripts/economy/**`、`tests/**`，不含 SaveService/schema/UI。

## 7. 验收条目映射

| 验收条目 | 来源 | Phase B 证据 |
|---|---|---|
| T-ECO-01 满篓后不可新 CASTING；售鱼完成释放格子恢复 | ACCEPTANCE_TESTS §2 | E1 FSM+经济联动断言（含 RNG 不消耗）|
| T-ECO-02 同 catch event ID 重试 100 次，入篮至多 1 条 | 同上 | E2 百次重试计数断言 |
| T-ECO-03 同 sale event ID 重试 100 次，金币至多 +1；实例不重复存在 | 同上 | E3 百次重试 + 篮/币快照断言 |
| T-ECO-04 重复/不存在/越权 ID、负价格、容量冲突明确错误；金币不可负 | 同上 | E4 错误矩阵 + E7 零副作用 + wallet_gold≥0 断言 |
| V01-E01 有限鱼篓、每实例唯一 ID、满篓不新开抛竿 | SDD §2 | E1 + E8 instance_id 唯一/派生断言 |
| V01-E02 按 sale ID 幂等扣鱼加币（非 NPC 商店） | SDD §2 / SDD-172 | E3 + E5（同 ID 异参不掩盖）|
| V01-E01/S01 捕获唯一结算、崩溃重试不重复结算 | SDD / DECISION-143/155-156 | E2/E3/E8 + 持久化门形状 E10 |
| `sale_price_at_catch` 捕获时价格快照 | SDD 2026-11-11 裁定 / INTERFACES §2 | E6 |
| GameState 唯一权威，UI 不另立账本 | SDD 其他明确前提 / ARCHITECTURE §2 | §4 不变量 + E7 深比较 |
| 捕获/出售串行排队、不超容量、不双发、不丢事件 | TASKS ECO-001+SAVE-001 核心安全要求 | §4 同步命令 + E4 BASKET_FULL + E2/E3 |
| 同 ID 异参 → 冲突错误并记录 | INTERFACES §5 | E5 + transaction_log |
| T-CONF-01 交界：非法配置阻止经济启动 | ACCEPTANCE_TESTS §2 | E9 复用 cfg001 夹具 + ConfigGate |
| FSM-001 移交 R-3（落账复核幂等） | FSM-001 report.md | E2/E3/E8 |
| CORE-001 / CFG-001 / FSM-001 不回归 | queue deps / queue note「前置失败不得标记完成」 | §5 step3/4/5 退出码 0 + PASS 标记 |
