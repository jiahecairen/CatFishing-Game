# ECO-001 Phase A 独立审查与批准条件

日期：2026-11-11

## 审查结论

计划与冻结的 v0.1 经济范围一致。Codex 按项目所有者的持续执行委托完成独立审查，并批准 Phase B，范围仅为 `scripts/economy/**` 与 `tests/**`；AUTO-001 可在 `tasks/evidence/ECO-001/**` 留存证据。计划中与接口解释相关的内容已直接修正，Phase B 必须按修订后的 `plan.md` 执行。

## 强制实现条件

1. `GameState` 仍是唯一经济权威，ECO 服务同步构造 next-state，经持久化门成功后才一次性发布。ECO 不改 `GameState` 源码，不写文件、不访问 `user://`、不改配置值、schema、UI 或 SaveService。
2. 售鱼清单中的重复 `instance_id` 按 `INTERFACES_AND_DATA.md` §5 去重后计价；重复提交同一 `sale_event_id` 返回 `ALREADY_APPLIED`；同一 sale ID 使用不同实例集合返回 `CONFLICT_SALE_PARAMS`。实例顺序不影响同一售鱼请求的参数指纹。
3. `sale_price_at_catch` 必须是非负整数；篮内价格损坏时稳定拒绝且零副作用。金币求和/加法不得溢出为负或绕回；返回稳定错误。
4. 持久化门只接收完整 next-state 和指纹账本的深拷贝。只有 Callable 正常返回布尔 `true` 才允许发布；false、非 bool、无效 Callable 或调用错误都按 `PERSIST_FAILED` 拒绝。门对副本的修改不得影响实时 GameState 或账本。
5. `snapshot_ledger()` / `restore_ledger()` 必须可供 SAVE-001 在重启时持久化/恢复，并对坏形状或与 `processed_*_ids` 不一致的数据 fail-closed。ECO 本票不改存档 schema；SAVE-001 计划必须给出原子保存与恢复该 ledger 的落点，不能只恢复 ID 列表而丢失异参冲突检测。
6. FISH 实例使用已批准的 `sale_price_at_catch` 快照；鱼实例只含 schema v1 的五个字段；鱼篓容量 10 只读。`caught_at_utc` 使用有效 UTC 时间戳，不能把 FSM 的虚拟时钟秒直接伪装成 UTC。
7. runner 严格隔离副本、隔离 HOME、串行导入和 ECO/CORE/CFG/FSM 测试；每步要求 exit 0、唯一 PASS、无 FAIL 与 `SCRIPT ERROR`，finally 清理副本。不得在真实工程路径启动 Godot。

## 验收映射

- T-ECO-01：FSM 满篓拒绝、RNG 不变；成功卖鱼后恢复抛竿。
- T-ECO-02/03：同一 catch/sale ID 各重试 100 次，状态和金币至多提交一次。
- T-ECO-04：未知 ID、重复请求、坏价格、非法输入、容量冲突、溢出均有明确错误或明确幂等结果，失败不改状态、金币不为负。
- 增补：同 ID 异参冲突；持久化门失败/错误/污染副本；ledger 跨 EconomyService 实例恢复。
- 前置回归：CORE-001、CFG-001、FSM-001 全部在隔离副本通过。

## 计划实测与阶段状态

AUTO-001 Phase A runner 会话 exit 0，输出 `PHASE-A-DONE`，队列进入 `awaiting_approval`。Qwen 只写 `plan.md`；队列、runner.log 与 runner.lock 的运行时变化由调度器自身产生。Phase B 的主测试命令固定为 `python3 -B tests/unit/run_eco001_checks.py`。
