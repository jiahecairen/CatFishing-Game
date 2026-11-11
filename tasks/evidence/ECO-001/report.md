# ECO-001 Phase B 执行报告（AUTO-001 调度）

- 工单：ECO-001 唯一鱼实例/有限鱼篓/出售与金币（T-ECO-01～04、V01-E01/E02、SDD-143/155-156/172/173、2026-11-11 价格快照裁定）
- 引擎：Godot 4.7.2.stable.official（`/Applications/Godot.app/Contents/MacOS/Godot --version` 实测）
- 执行日期：会话内实测；全部结果为真实命令输出，无伪造退出码。

## 1. 修改文件清单（仅允许范围内）

| 文件 | 类型 | 行数（plan 上限） | 说明 |
| --- | --- | --- | --- |
| `scripts/economy/fish_instance.gd` | 新增 | 120（—） | 鱼实例静态工厂/校验器：五键 schema v1、`instance_id = "fish-"+catch_event_id`、UTC 秒级时间戳校验（含闰年）、价格快照判型（BAD_PRICE 与 BAD_STATE 区分） |
| `scripts/economy/economy_service.gd` | 新增 | 435（≤450） | 经济事务服务：`initialize`（复用 ConfigGate 门）、`commit_catch`/`sell_fish`（幂等指纹账本 + 稳定错误码 + 深拷贝持久化门 + 一次性发布）、`snapshot_ledger`/`restore_ledger`（SAVE-001 交界，fail-closed）、`set_persistence_gate`、`get_transaction_log` |
| `tests/unit/test_eco001_economy.gd` | 新增 | 596（≤600） | headless 单测 E0–E11（E0 为 E4/E6 前置的原语断言，属计划矩阵的加严，非范围扩张） |
| `tests/unit/run_eco001_checks.py` | 新增 | 196（≤200） | 单 runner 串行 5 步 + 前置交付/数值锁检查；隔离临时副本 + 隔离 HOME；禁止标记 `SCRIPT ERROR` |

`git status --short` 自查：仅上述 4 个文件为本次改动（`scripts/economy/`、`tests/unit/` 两个新文件）。
`tasks/evidence/_runner/runner.log`、`tasks/evidence/_runner/runner.lock` 为调度器自身工件，本会话未读写；
`tasks/APPROVALS.md` 未读未改；未创建任何批准记录；无子代理/后台任务；无 git 提交类操作。

## 2. 命令与真实退出码

在项目根 `/Users/rain/DevGame/Fishing` 执行 `python3 -B tests/unit/run_eco001_checks.py`：

| 轮次 | 命令 | 真实退出码 | 首个失败点（真实输出） |
| --- | --- | --- | --- |
| 1 | `python3 -B tests/unit/run_eco001_checks.py` | 1 | step2 `ECO001 ECONOMY FAIL: E0 make() envelope / five-key schema / price snapshot` — `FishInstance.UTC_PATTERN` 缺捕获组致 `get_string(1..6)` 全空 → 已修（补 6 个捕获组） |
| 2 | 同上 | 1 | step2 `SCRIPT ERROR: Invalid call. Nonexistent 'String' constructor.`（`economy_service.gd:414`，`String(42)` 在 Godot 4 非法）→ 已修（拒绝路径改 `str()`） |
| 3 | 同上 | 1 | step2 `SCRIPT ERROR: Invalid operands 'int' and 'bool' in operator '=='`（`_persist` 中 `result == true` 收到门返回的 int 1）→ 已修（先 `is bool` 再 `bool(result)`）；同轮暴露测试自身缺陷：E11 误用被污染的深拷贝快照做恢复输入 → 改为完好快照恢复、被污染副本仅用于深拷贝断言 |
| 4（最终） | 同上 | **0** | `ECO001 RUNNER PASS`（全 5 步 OK） |

最终轮 5 个子步骤真实退出码：step1-import=0、step2-eco001=0、step3-core001-regression=0、step4-cfg001-regression=0、step5-fsm001-regression=0；全程无 `SCRIPT ERROR`、无 FAIL 标记。

## 3. 测试输出摘要（最终轮实录）

```
pre-flight: deliverables present, value-lock frozen, fixtures present
[step1-import] exit_code=0            （21 个全局类注册成功，含 EconomyService/FishInstance）
[step2-eco001] exit_code=0            ECO001 ECONOMY PASS
[step3-core001-regression] exit_code=0 CORE001 SMOKE PASS（wallet_gold=0 basket=0 basket_capacity=10）
[step4-cfg001-regression] exit_code=0  CFG001 CONFIG PASS
[step5-fsm001-regression] exit_code=0  FSM001 sample: min=20 max=60 distinct=41 / FSM001 FSM PASS
ECO001 RUNNER PASS   （RUNNER_EXIT=0）
```

测试覆盖（test_eco001_economy.gd，plan §5 矩阵 + review 强制条件）：

- E1：FSM+经济 10 次完整周期至满篓 10 → `can_cast=false`；满篓 `request_cast` 拒绝 `BASKET_FULL` 且 `rng.get_state()` 不变（拒绝不消耗 RNG）；售 1 条后恢复可抛竿。
- E2：同 `catch_event_id` 共 100 次 commit → 篮恰 1 条、processed ids 恰 1、revision +1、价格快照 8（T-ECO-02/V01-E01）。
- E3：同 `sale_event_id` 共 100 次 sell（含逆序清单）→ 金币恰 +24 一次、实例不复活、revision 不变（T-ECO-03/V01-E02；顺序不敏感指纹）。
- E4：错误矩阵全稳定码 + 每次拒绝前后 GameState 逐字段深比较零副作用 + `wallet_gold ≥ 0`：UNKNOWN_INSTANCE、BAD_INSTANCE_LIST（空/非字符串/空串/非数组）、UNKNOWN_SPECIES、BAD_EVENT_ID、BAD_TIMESTAMP（含非字符串）、BASKET_FULL、BAD_PRICE（五键齐价格坏）vs BAD_STATE（畸形元素/重复 instance ID）、GOLD_OVERFLOW（wallet=INT64_MAX 售 8 金币鱼不绕回）、NOT_INITIALIZED、NULL_GAME_STATE。
- E5：同 ID 异参 → `CONFLICT_CATCH_PARAMS`/`CONFLICT_SALE_PARAMS`（不被 ALREADY_APPLIED 掩盖）且记入 `transaction_log`，零加鱼加币。
- E6：篡改目录 base_price 8/32→999（内存副本）后售鱼仍按捕获时刻快照价 32 计（2026-11-11 裁定）。
- E7：BAD_STATE/PERSIST_FAILED/CONFLICT_*/BASKET_FULL 各类失败逐字段零副作用；被拒事务不进指纹账本；结束后权威态不漂移。
- E8：FSM 候选 payload 逐字段落账（instance_id=`fish-`+事件 ID、source_event_id、species、价格=候选 weight_snapshot.base_price、UTC 原样保留不伪装时钟秒）、ack→IDLE、重抛新事件 ID（FSM-001 移交 R-3）。
- E9：非法配置经 ConfigGate 拒绝并带 `runtime:MIN_GT_MAX` / `catalog:DUP_ID` 前缀码；拒绝后一切命令 NOT_INITIALIZED 零副作用（含 restore_ledger）。
- E10：持久化门注入 false/非 bool/失效 Callable（`is_valid()==false` 不调用）→ PERSIST_FAILED 零副作用；投毒门改深拷贝后返回 true → 发布态/账本不被污染，门确实收到完整 next_state+ledger。
- E11：`snapshot_ledger` 深拷贝；跨实例 `restore_ledger` 后幂等/异参冲突仍成立；坏 ledger（多键、与 processed ids 不符、未知 ID、指纹形状坏、已售实例仍在篮）一律 BAD_LEDGER fail-closed 零副作用。

## 4. 覆盖的验收条目

- T-ECO-01 满篓阻断+恢复：E1（另 FSM-001 回归 step5 保持绿）。
- T-ECO-02 唯一鱼实例/catch 幂等：E2、E5、E8、E11。
- T-ECO-03 售鱼原子加币/sale 幂等：E3、E4-B/C、E5、E11。
- T-ECO-04 异常路径稳定错误码：E0、E4、E7、E9、E10。
- SDD-143/155-156（一鱼一实例、崩溃重试不重复结算）：E2/E3/E11（本票为内存态；落盘崩溃注入归 SAVE-001）。
- SDD-172/173（30FPS、20–60s、容量、鱼价权重数值）：runner 值锁（data==examples + 显式 20/60/30/10、8/16/32、60/30/10），本票零数值改动。
- 2026-11-11 价格快照裁定：E0/E6/E8。
- review.md 强制条件 1–7：GameState 唯一权威（E7/E10 投毒门）、去重+顺序不敏感指纹（E3）、非负整价+溢出（E0/E4-H）、门收深拷贝且仅 bool true 放行（E10）、snapshot/restore fail-closed 为 SAVE-001 预留（E11）、鱼恰五键且 UTC 不伪装时钟秒（E0/E8）、runner 严格隔离 5 步（§2/§3）。

## 5. 执行期发现的真实缺陷与修复（均有实录）

1. `FishInstance.UTC_PATTERN` 缺捕获组 → 时间戳全部误判非法；补捕获组（轮 1 实录）。
2. 拒绝路径 `String(42)` 触发 Godot 4 引擎 call error（违反本 runner 的 SCRIPT ERROR 禁令）→ 改 `str()`（轮 2 实录）。
3. `_persist` 对非 bool 门返回值做 `result == true` 是 Godot 4 非法操作数比较 → 先 `is bool` 再 `bool(result)`（轮 3 实录）。
4. 测试自身缺陷：E11 曾拿被人为污染的快照做恢复输入；修正为完好快照恢复、污染副本仅用于深拷贝断言（轮 3 实录）。

## 6. 残留风险 / 移交事项

- 落盘未做（按计划）：本票仅内存事务 + 持久化门注入点；`set_persistence_gate`/`snapshot_ledger`/`restore_ledger` 已为 SAVE-001 的原子写与崩溃恢复预留契约，SAVE-001 须用真实门替换默认恒真门并补崩溃注入验收。
- UI 未改：金币/鱼篓显示仍归 CORE-001 占位 HUD；本票零 UI 改动。
- 数值未改：容量 10 仍为候选初值（2026-11-11 委托冻结），runner 值锁防误改；任何改动会直接红。
- 时钟源：`caught_at_utc` 由调用方（未来 UI/系统时钟适配层）提供合法 UTC；FSM 虚拟时钟秒不具时间戳语义，E8 已锁定不得伪装。
- 本票为纯数据层 headless 验证，不含 GUI spike（plan R-6 裁定）。
- 偏差：无（4 个文件均在 plan §3 文件计划与行数上限内；E0 为矩阵加严非扩张）。
