# CFG-001 Phase A 审查记录

- 计划范围与队列白名单一致：`data/**`、`scripts/config/**`、`tests/**`；不扩展产品边界，不改 examples、schemas、审批账本之外的规格文件。
- 配置值沿用已批准示例：三种鱼的权重与价格、30 FPS、20–60 秒和候选容量 10 均不调整。
- JSON 解析实现须使用 `JSON.new()` 实例的 `parse(text)` 与 `get_error()`/返回码检查；`JSON.parse_string()` 本身不提供 `parse_error` 属性。畸形 JSON 必须返回稳定错误码，不能只检查返回值后误报。
- 自动测试命令使用 `tests/unit/run_cfg001_checks.py`（仅 Python 标准库）：依次执行 Godot 导入、CFG-001 测试和 CORE-001 回归；捕获各命令退出码，要求 `CFG001 CONFIG PASS`、`CORE001 SMOKE PASS`，拒绝对应 FAIL 标记及任一 `SCRIPT ERROR`。
- 保持鱼种 ID、整数价格、正权重、允许稀有度、运行参数范围和无默认值失败原则；配置失败必须令 `ConfigGate` 拒绝启动。

审查结论：在以上约束下可按委托批准 Phase B。审批人是项目所有者明确委托的 Codex；不替代之后 UI/桌面 GUI 或 8 小时稳定性验收。
