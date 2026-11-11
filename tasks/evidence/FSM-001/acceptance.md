# FSM-001 独立验收

日期：2026-11-11

## 验收结论

FSM-001 的允许范围交付已完成，按项目所有者的持续执行委托验收为 Accepted。实现由单个本地 Qwen 会话串行完成；Codex 复核了范围、测试、回归证据和已批准的修复条件。

## 覆盖证据

- `python3 -B tools/auto/runner.py selftest`：退出码 0，40 项全过。特别覆盖 runner 对自身写入的 tracked `queue.json` 快照豁免，同时拦截会话篡改；仅当 `icon.svg` 获准时接受对应 `.import`；CORE 冒烟要求先导入、成功标记和无 `SCRIPT ERROR`；自动提交排除预先暂存的越界文件；导入旁车竞态拒绝提交。完整结果见 `tasks/evidence/_runner/auto001-selftest-20261111.txt`。
- `python3 -B tests/unit/run_fsm001_checks.py`：退出码 0；隔离副本中 editor import、FSM、CORE、CFG 四步都退出 0 并包含各自 PASS 标记，未出现 `SCRIPT ERROR`，副本和临时 HOME 已清理。完整日志见 `review-stage-durations.log`。
- `git show --check HEAD`：通过；FSM API 补齐提交为 `2d859aa`，未触碰审批账本、冻结状态、经济数据或存档 schema。

## 已知移交

- SAVE-001 需要持久化 RNG/Clock continuation 与未提交 candidate payload，并完成原子保存和故障注入。
- ECO-001 负责 GameState 上的唯一鱼实例、有限鱼篓、catch/sale 幂等事务。FSM-001 不代替这两张票。
- 人工审批账本不变；历史 `unfrozen` 记录保留。真实队列没有活动 `frozen` 字段或 PAUSE 标记。
