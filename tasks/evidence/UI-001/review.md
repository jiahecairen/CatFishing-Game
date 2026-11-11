# UI-001 Phase A 独立审查

**审查结论：计划达到可进入现有审批流程的条件；本文件本身不代替审批账本记录。** UI-001 仍处于 `awaiting_approval`，`test_cmd` 仍为空，`needs_human=true`。后续批准必须通过 AUTO dashboard/runner 的既有流程，保持审批账本与门禁有效。

## 核对范围

- 对照 `AGENTS.md`、v0.1 SDD、架构/接口/验收文档、SPIKE-001 窗口行为，以及当前 core/platform/presentation/economy/FSM/save/config 脚本和已有回归入口。
- 核实 UI-001 仅依赖 SAVE-001、SPIKE-001；不改经济、FSM、存档、配置、GameState、schema、数据、IO 或审批账本。
- 对照计划的文件清单、队列 `allowed_files`、测试标记与 GUI 验收项目。

## 发现及修订

1. 初稿把实现限制在 `scenes/**`、`scripts/ui/**`、`tests/**`，但又要求主控制器、平台窗口和 Presenter；这与既有骨架归属冲突。计划和队列现已同步增加四个精确骨架文件路径，避免把平台逻辑复制到 UI 层。
2. 项目主设置 `project.godot` 仅在 Mac GUI 证明运行时透明无效时可改，且严格只追加与已验收 SPIKE 相同的六个 `[display]` 设置；路径已列入白名单。
3. 新档识别被收紧为主档和备份都确认为 missing；损坏/未来版本/配置错误一律 fail closed；新档 checkpoint 成功前不开放游戏输入。
4. 补全 pending candidate 重启恢复：安装 SaveService 后重建 FSM success payload 与原 UTC，再 replay、ack、清理 candidate、写 checkpoint；覆盖“经济已提交但 ack 前崩溃”。
5. 售鱼 ID 改为随机 nonce + 计数器，不读取设备 ID；同一交易失败重试复用同 ID。
6. 修正 SPIKE B 的拖动描述：OS 在按下时开始原生拖动；6px 用于松手后的点击分类，不能表述为拖动启动阈值。
7. 测试矩阵加入新档/损坏档/候选恢复/full-screen coexistence；每个 Godot 子进程都需退出码 0、精确一次 PASS、无对应 FAIL、无 `SCRIPT ERROR`，并且导入步骤先完成。
8. 保留 GUI `needs_human=true`；尚未声称 GUI 通过。

原始生成器输出 `phaseA.out` 与压缩会话归档保留在证据目录；其中初稿范围判断已被本计划修订，不能把初稿当作当前实施授权。

## 审批边界

本计划的 Phase B 白名单为：

- `scenes/**`
- `scripts/ui/**`
- `scripts/core/game_controller.gd`
- `scripts/platform/desktop_window.gd`
- `scripts/platform/platform_adapter.gd`
- `scripts/presentation/cat_presenter.gd`
- `project.godot`（仅上文 SC-1 条件）
- `tests/**`

除此之外不允许改动。审批账本不手工修改；Phase B 若获准，必须用现有 dashboard/runner 审批流程记录批准与单行测试命令。当前没有执行 Phase B，也没有启动新的 Godot 进程或运行测试。
