---
name: fishing-state-and-save
description: Implement and review deterministic fishing FSM, unique fish inventory, idempotent sale and catch transactions, and crash-safe local persistence for Fishing v0.1.
---

# Fishing FSM & Save — 项目 Skill

**何时使用**：FSM-001、ECO-001、SAVE-001、售鱼、金币、鱼篓、配置、崩溃恢复、存档迁移工单。

0. 必须读 `AGENTS.md`、`docs/SDD_v0.1.md`、`docs/INTERFACES_AND_DATA.md`；禁止引入 v0.2+ 家具、天气、NPC、在线收益或全世界系统。
1. 捕鱼状态序列 `CASTING→WAITING→HOOKED→REELING→SETTLEMENT`；初始随机等待 20–60 秒，使用注入 `RNG`+`Clock`，能固定种子虚拟时间测试。帧率固定 30 FPS，但**计时不能用帧数**。
2. 每条鱼实例有唯一 `instance_id`，每次捕获有唯一 `catch_event_id`；fish species ID 仅表示种类。容量 10 是候选；满篓不能开始新抛竿。
3. 玩家手动出售，不引入自动商店/NPC；唯一 `sale_id` 原子删鱼加金币；重试 same ID 不得重复结算。
4. 所有经济事务先验证、构造新状态、成功持久化后更新 UI；保存失败时保持旧权威状态、暂停不安全操作、报告恢复原因。
5. 版本化存档、备份/原子替换、故障注入；不覆盖损坏原档，不静默格式升级。
6. 未裁定的隐藏窗口有效计时 `OPEN-001` 不允许自行决定成真实离线产鱼；提出用户确认。
7. 提交 tests、退出码、Git diff 与故障恢复证据，不以文字承诺替代测试。
