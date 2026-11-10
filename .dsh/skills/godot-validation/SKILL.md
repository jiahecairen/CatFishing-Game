---
name: godot-validation
description: Run reproducible Godot 4 headless, macOS GUI, fault-injection, economy simulations and evidence-based acceptance tests with a single local coding agent.
---

# Godot Validation — 项目 Skill

**何时使用**：任意 `*_TEST`/`SIM-001`/`REL-001`、代码审查、故障注入、性能/8小时稳定性工单。

1. 读 `docs/ACCEPTANCE_TESTS.md`、当前工单、真实 Git diff，确认 Godot 可执行路径/版本；不安装第三方测试插件，除非获批准。
2. Godot **headless** 验证 FSM、配置、存档、测试脚本；桌面透明/穿透、窗口拖动、Retina 必须运行 Mac GUI 进行人工验证。
3. 运行固定种子、可控虚拟时间测试：20–60s、FSM 路径、满篓停止、售鱼恢复、重启恢复、重复 catch/sale IDs 不再增鱼/金币。
4. 故障注入覆盖保存半写、rename/写盘失败、损坏版本/备份恢复；失败测试不能自行删改断言、不能对无效测试造 `pass:true`。
5. 多种子模拟 1/4/8h，输出可机读 JSON 报告，列出完整周期/篮满分布/鱼种及价值分布。平衡改动仅用户批准。
6. 8h 真实持续运行收集 CPU/内存/FPS 趋势，记录机器/版本/开始结束时间/异常。资源阈值由本机实测，不瞎编百分比。
7. 提供执行命令、退出码、可重现日志、改动文件、未解决风险；不触及任何外部个人文件或网络上传。
