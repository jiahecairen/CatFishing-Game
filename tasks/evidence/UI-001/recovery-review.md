# UI-001 恢复核查记录

日期：2026-11-11
工作树：`/Users/rain/DevGame/Fishing`
用途：在恢复 UI-001 前记录可复核的失败原因和当前工程状态。

## 核查结论

1. 正式场景仍是 CORE-001 占位界面。`scenes/main.tscn` 只有 `Main` 和 `PlaceholderLabel`；`scripts/core/game_controller.gd` 的 `_ready()` 只创建 `GameState` 并打印初始化信息。它没有实例化 `FishingSession`、HUD、鱼篓或猫船视图。这解释了运行窗口只有灰色背景和一行很小的占位文字。
2. 四个已提交的 `scripts/ui/` 脚本还未接入场景和主控制器；Phase B 交付物仍缺 `tests/unit/run_ui001_checks.py` 和 `tests/unit/test_ui001_ui.gd`。
3. 原队列命令 `python3 -B tests/unit/run_ui001_checks.py` 指向不存在的文件。三次历史测试日志记录为找不到该入口、退出码 2，因此即使模型会话成功结束，验收也必定失败。
4. Qwen 历史服务日志显示一个请求累计处理约 109,045 个 token 后连接被客户端关闭；结合 AUTO-001 每次最多 30 分钟、失败后重复同一大上下文的行为，足以解释此前反复超时。当前本地模型路由可加载 Qwen；短请求验证了模型服务可用。后续应拆成短步骤，并在代码完成前补齐隔离测试入口。
5. 对当前源码副本运行 Godot 4.7.2 `--headless --editor --quit` 导入预检，退出码 0，未发现 `SCRIPT ERROR`。此预检使用临时工程副本和临时 HOME；未在真实工程上启动 Godot、未改用户存档或编辑器缓存。

## 当前安全状态

- UI-001 仍为 `blocked`，全局队列冻结字段保留。
- Phase B 已批准记录和白名单未改。
- 本次没有清理或改写任何既有未跟踪会话档案；没有改动队列、审批账本或远端。
- 本记录只证明故障原因和导入预检，不代表 UI 已完成或通过验收。

## 恢复所需工作

- 补齐 UI-001 的隔离测试入口：先导入，再逐步执行 Godot 测试，检查退出码、唯一 PASS/FAIL 标记和 `SCRIPT ERROR`。
- 完成 GameController、平台窗口适配、猫船占位视图以及主场景接线。
- 在冻结机制允许的流程中恢复工单，执行完整自动测试；之后完成 Mac GUI 验收并如实记录未测项。
