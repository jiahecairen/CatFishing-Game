# FSM-001 后续独立复核与重开记录

日期：2026-11-11。复核对象为 `9dc9753` 中的 FSM-001 实现和随票测试。此记录补充原 `review.md`，不覆盖历史报告。

## 复核结论

当前实现尚不满足原 Phase A 审查的强制条件，FSM-001 保持未验收并重开修正。原 runner 输出中的 PASS 仅说明旧测试通过；`test-1.log` 显示所有 Godot 命令均使用 `--path /Users/rain/DevGame/Fishing`，因此与当时运行中的主编辑器并发，不构成满足隔离要求的证据。

## 已确认缺口

1. `FishingStateMachine.request_cast()` 无 GameState 参数；满篮检查仅存在于独立 `can_cast()`，调用方漏调时仍能消耗 RNG 并抛竿。
2. `produce_catch_candidate()` 第二次调用返回 `CANDIDATE_ALREADY_ISSUED`，没有按同一 catch event ID 返回原 payload。
3. `snapshot_checkpoint()` 会把运行态 `PAUSED` 写入四字段 checkpoint，而 `initialize()` 明确拒绝恢复 `PAUSED`；隐藏后重启不能安全恢复。
4. `DeterministicRng` 只有 seed 读写，没有运行状态快照/恢复；旧 F9 将同一个 RNG 与 Clock 对象交给新 FSM，不是跨实例恢复验证。
5. `CASTING/HOOKED/REELING` 时长仍是固定 `1.0` 常量；`OPEN-004` 已裁定表现时长可配置。
6. 旧 F4/F5 时间轴未纳入候选鱼种；F5 必须逐字段核对跨多个完整捕鱼周期的阈值时刻、事件 ID、等待值和鱼种。
7. `run_fsm001_checks.py` 直接在主工程做 editor import 与脚本测试，且在主工程 `tasks/evidence` 下创建 HOME 临时目录；这不满足当前 GUI 并发隔离和项目树零写入要求。
8. 旧报告将 OPEN-004 写为等待人工裁定，与 `docs/REQUIREMENTS_CHANGELOG.md` 的已裁定记录不一致。

## 重开后的必做验收

- `request_cast(state)` 内部执行初始化、状态、空值与容量校验；满篮/空值/非法状态路径稳定拒绝且 RNG 状态不变。
- RNG 提供 fail-closed 的状态读取/恢复；虚拟时钟可在测试恢复路径中从独立保存值恢复。新实例恢复测试必须使用新 RNG 和新 Clock。
- 同一 settlement event 重复请求返回深拷贝但逐字段相同的候选 payload，不重复抽样；未提交结算仍可安全重试。
- PAUSED 快照采用现有 schema 可表示且重启后安全续跑的语义；checkpoint 状态字段、event ID、等待值、有效 elapsed 必须交叉校验，未知/畸形数据拒绝。不得扩展或修改 schema；在报告记录 SAVE-001 需持久化 RNG/Clock continuation 与 pending candidate 的数据。
- CASTING/HOOKED/REELING 时长可通过 FSM 可选参数设置，验证有限正数；默认值仍为 1 秒，不修改 runtime config、经济数值或 schema。
- F4/F5 纳入候选 species 与完整周期事件时间轴；0.5/1/2 秒步长的事件时刻、事件 ID、等待值、species 与候选快照逐字段一致。
- Python runner 必须先把工程复制到系统临时目录，排除 `.git`、`.godot`、`tasks/evidence` 和 Python 缓存；所有 Godot 命令 `--path` 与工作目录都指向同一副本。HOME/XDG 状态放在临时目录，副本与 HOME 必须在 `finally` 清理。严格串行执行 import、FSM、CORE、CFG；每步检查退出码、PASS/FAIL 标记及 `SCRIPT ERROR`。禁止直接在主工程运行 Godot。
- 修改范围仍为 `scripts/fishing/**`、`tests/**`；不得修改 `GameState`、配置数据、经济代码、schema 或 UI。

原 `tasks/APPROVALS.md` 已对该票 Phase B 和相同文件范围给出委托批准；本次为落实原 review 条件的返修，不扩大批准范围。
