# 可以直接复制给 DeepSeek Harness 的任务提示词

## A. 第一次接收文档（Plan Mode / 只读）

> 当前 Godot 工程工作区为 `/Users/rain/DevGame/Fishing`。你是 DeepSeek Harness Standard 模式下唯一的本地 Qwen Flash 开发 Agent。禁止子 Agent、并行模型、收费云 API、外部下载。先完整阅读 `AGENTS.md`、`README_FIRST.md`、`docs/SDD_v0.1.md`、`docs/REQUIREMENTS_CHANGELOG.md`、`docs/TECH_SPIKE.md`、`docs/ARCHITECTURE.md`、`docs/INTERFACES_AND_DATA.md`、`docs/ACCEPTANCE_TESTS.md`、`tasks/TASKS.md`。当前只执行 `AUDIT-001`：实际只读检查本机项目目录、Godot/Git/模型 API 与 Skills，确认旧文件冲突、缺少的条件和技术风险，提交可以人工批准的计划。不要创建、修改或删除文件，不要认定本包已经由用户正式冻结。提供执行命令和证据。

## B. 验证 Skills（只读）

> 使用当前会话实际存在的 Skill 工具，列出可发现的技能名称/来源/读取情况，重点确认 `godot-overlay`、`fishing-state-and-save`、`godot-validation` 与我自己的 `~/.agents/skills/`。若工具没启用请报告，不要凭路径就声称 Skills 已激活；不要执行外部安装代码。

## C. 第一张开发票（先完成 A 审计且用户批准之后）

> 依据 `AGENTS.md`、`docs/TECH_SPIKE.md` 和 `tasks/TASKS.md` 的 `SPIKE-001` 执行 Godot macOS 透明悬浮窗口技术探针。先确认用户批准的文件范围、Git diff 和 Godot 版本，再实现最小透明船图层、透明区域鼠标穿透、拖动及 30 FPS。真实 GUI 验证不能由 headless 代替。报告实测结果、失败项、命令、日志、窗口截图和未解决问题；未获批准前不得修改 v0.1 产品边界或启动后续剧情/猫咪创建模块。

## D. 每张工单的完成复核

> 请仅根据实际仓库 diff、Godot 测试运行结果及具体日志，审查当前工单满足了哪些 `docs/ACCEPTANCE_TESTS.md` 断言。对每个条目标注 PASS/FAIL/NOT RUN 和原因；列出潜在重复结算/存档风险，给出最小修复任务。不得修改测试以掩盖 Bug，不得无证据声称通过，不得推送 Git 远端。
