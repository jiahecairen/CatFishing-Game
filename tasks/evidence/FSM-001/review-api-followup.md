# FSM-001 API 复核补记

日期：2026-11-11

## 发现与修正

队列中已批准的 FSM-001 brief 明确要求由可选 `stage_durations` 参数配置表现时长。原返修只提供 `configure_stage_durations()`，虽然可在 IDLE 调整，但没有满足该接口约定。

`FishingStateMachine.initialize()` 现在接受可选末参 `stage_durations: Dictionary = {}`，支持 `casting_sec`、`hooked_sec`、`reeling_sec`。缺省项为 1 秒；未知键、非数值、非有限数或非正数返回 `BAD_DURATION`，在所有校验通过前不会提交 FSM 初始化状态或配置。既有 IDLE setter 保留。

F13 现覆盖初始化参数的三阶段自定义值、0/NaN/Inf/未知键拒绝，及默认/既有 setter 行为。没有修改 `runtime_config`、经济参数或 schema。

## 实际回归

执行：`python3 -B tests/unit/run_fsm001_checks.py`

- 退出码：0；最终标记：`FSM001 RUNNER PASS`
- Godot：`4.7.2.stable.official.ed1daf0bf`
- 串行隔离副本步骤：editor import、FSM、CORE、CFG 均退出码 0；分别包含要求的 PASS 标记，无 `SCRIPT ERROR`。
- 副本路径与隔离 HOME：见 `review-stage-durations.log`；测试结束已清理。
- `git diff --check`：通过。

本次只改 `scripts/fishing/**`、`tests/**` 与本证据目录；没有改队列、审批账本或冻结状态，没有推送远端。AUTO-001 自测另覆盖 tracked queue 的 runner 快照豁免与队列篡改拦截、图标 `.import` 精确归属、导入错误拒绝、白名单提交和并发导入竞态，结果全绿。
