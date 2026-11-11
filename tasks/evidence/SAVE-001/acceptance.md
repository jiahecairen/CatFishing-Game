# SAVE-001 独立验收

日期：2026-11-11

## 结论

**Accepted（项目所有者委托 Codex 独立验收）**。

验收依据：已批准的 `plan.md` / `review.md`、Phase B `report.md`、`review-followup.md`，以及本次对当前 HEAD 的实际隔离复测。SAVE-001 的正式实现提交为 `034c035`，后续安全修复为 `6f77e5a`。允许范围为 `scripts/save/**`、`schemas/game-save.schema.json`、`examples/save_v01.json`、`tests/**`；实现和修复均在该范围内。

## 本次复测

- `python3 -B tests/unit/run_save001_checks.py`：退出码 0。隔离副本导入成功；SAVE、ECO、CORE、CFG、FSM 五步均退出码 0，并输出各自唯一 PASS 标记；运行结束清理了隔离工程和 HOME。
- `python3 -B tests/unit/run_ui001_checks.py`：退出码 0。隔离副本导入先行；UI、SAVE、ECO、FSM、CORE、CFG 均通过，Godot 每步退出码 0，标记正确，未出现 `SCRIPT ERROR`。
- `python3 -B tools/auto/runner.py selftest`：退出码 0，40/40 检查通过。覆盖 tracked queue 的 runner 所有权与篡改拦截、`tools/auto` 其余文件仍受范围检查、`icon.svg.import` 精确归属、CORE 导入先行与 PASS/脚本错误门禁、白名单提交、并发导入冻结及审批/冻结机制。

## 范围与风险

实现通过同目录临时文件和原子替换保存完整状态；测试覆盖写入、flush、备份、rename、quarantine、legacy-copy 与发布边界，并检查损坏/未来版本、v1 安全迁移、账本幂等及 RNG/Clock/pending-candidate 恢复。回归只在隔离副本和隔离 HOME 内运行。

残余限制：API 故障注入不能证明突然断电时的物理介质持久性；详细限制见 `report.md`。此限制不违反本票验收标准。

## 状态记录

本验收依据项目所有者 2026-11-11 已记录的逐票独立验收委托。没有修改 `tasks/APPROVALS.md`。SAVE-001 转为 `done`；全局队列冻结标志保持原值，UI-001 及其余工单状态不变；未推送远端。
