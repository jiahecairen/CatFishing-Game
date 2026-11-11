# FSM-001 Phase A 独立审查

审查结论：计划范围与产品目标基本相符，可在下列接口/验证约束写入本票批准后进入 Phase B。不得借本票修改经济参数、存档 schema 或窗口/UI。

## 必须落实的审查条件

1. **满篓由状态机拒绝**：`request_cast` 必须接收当前 `GameState`（或等效只读容量快照），内部执行与 `can_cast` 一致的容量/状态校验；满篓时拒绝且不消耗 RNG、不生成 event ID。不能只依赖调用方先调用 `can_cast`。
2. **逻辑时间精确且步长无关**：只把有效秒数推进到实际阈值，事件时间记为阈值时间；过量步长保留为 backlog，并在下一次推进前先消费 backlog。暂停/IDLE/SETTLEMENT 不推进有效时钟。抛竿/上钩/收竿等无业务时长阶段不得偷偷按渲染帧耗时；本票不新增平衡参数。F5 必须比较 0.5/1/2 秒不同步长下的完整事件时间轴，包含连续捕鱼周期，而非只比较事件数量。
3. **随机和候选可重放**：为 RNG 提供可验证的状态读取/恢复接口；给定同 seed/checkpoint 可复现后续抽样。相同 catch event ID 的 `produce_catch_candidate` 重试必须返回完全相同的 species/价格相关快照，不能重复消耗 RNG 后变成不同 payload。checkpoint 至少验证当前事件、等待和已耗有效时间的一致性；畸形/未知状态必须 fail-closed。现有 `schemas/game-save.schema.json` 将 `fishing_checkpoint` 限为四个字段，本票不得改 schema；在报告中明确列出 SAVE-001 必须持久化的 RNG/待结算 payload 扩展，留给 SAVE-001 按其批准范围显式处理。
4. **导入和测试与主 GUI 隔离**：当前主工程 Godot GUI 仍在运行。`run_fsm001_checks.py` 必须把必要的项目文件复制到系统临时目录，在副本上串行执行 Godot editor import、FSM、CORE、CFG 测试；临时副本与 HOME 均须 finally 清理。不得对 `/Users/rain/DevGame/Fishing` 并发启动 Godot 导入，也不得终止用户 GUI。每步须检查退出码、唯一必需 PASS 标记、禁止 FAIL 标记和 `SCRIPT ERROR`。
5. **实现兼容性**：保持本票 allowed_files=`scripts/fishing/**`,`tests/**`。不修改 `scripts/core/**`、配置、数据、存档 schema 或经济代码。参考 CFG-001 实测，避免在 GDScript static 函数中调用本机 Godot 4.7.2 无法解析的 `fract()`/`is_finite()`。

## 已复核

- `plan.md` 第二行按提示原样引用 AGENTS.md 的纯 FSM 规则。
- Lehmer LCG 的乘法上界低于有符号 64 位上限；20–60 秒和 30 FPS 配置未要求改动。
- 新 class_name 不与当前 12 个全局类冲突；`scripts/core/fishing_system.gd` 是占位骨架且不在本票允许范围，继续采用独立 `scripts/fishing/` 路径是范围内做法。
- Phase A 的唯一代码外产物为本证据目录；当前队列无 `frozen` 字段，本审查未调用解冻命令。

## 审查命令

- `cat tasks/evidence/FSM-001/plan.md`：0
- `cat scripts/core/game_state.gd schemas/game-save.schema.json docs/ARCHITECTURE.md`：0
- `git status --short`：Phase A 新增仅在 `tasks/evidence/FSM-001/**`，队列/runner 日志为 runner 自有状态

审查决定：按以上条件自动批准 FSM-001 Phase B；不扩张产品范围。
