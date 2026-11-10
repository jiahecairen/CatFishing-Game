# Fishing / 桌面小猫钓鱼 — DeepSeek Harness 实施包

**包版本**：2026-11-10 · Draft for Owner Review  
**预期本机项目目录**：`/Users/rain/DevGame/Fishing`  
**技术栈**：Godot 4.x / GDScript；macOS Apple Silicon 作为 v0.1 主开发、主验收平台  
**Agent**：DeepSeek Harness Desktop（标准预设）+ llama.cpp + **单个**本地 `ggml-org/Qwen3.8-Flash-Next-GGUF:IQ4_NL`；严禁将 Codex 当作默认执行器。

## 先说清楚交付边界

- 这份 ZIP 在 ChatGPT 工作环境中生成，**没有直接写入你的 Mac**，没有读取你本机的真实仓库、工具版本和已安装的个人 Skills。
- 资料依据此前 SDD 访谈中已经明确可恢复的**有效决策**，重点覆盖 SDD-123～180 与高优先级全局约束。**不是**逐行校验过的 SDD-001～180 全量原始转录；不能声称完成了全部历史选择的来源审计。若你有旧版 SDD，请按 `docs/REQUIREMENTS_CHANGELOG.md` 对照补齐，不要自行编造丢失的选择。
- 本文档包属于**审查稿**；SDD-179 要求由用户审核之后才正式冻结 v0.1。开发 AI 不得将“下载了 ZIP”自动视为批准开发或批准重大架构决策。
- `.dsh/skills/` 随包提供 **3 个新建的项目专用 Skills**。用户之前已有的 `~/.agents/skills/` 只能在用户 Mac 上核对是否发现，不能声称已经启用或移动。
- 本包没有替你安装 Godot、配置 Harness、测试透明窗口或实现游戏代码。

## 安全安装（推荐）

1. 先将 ZIP 下载到 Mac 的 `~/Downloads/`，**不要直接覆盖原仓库文件**。
2. 终端列出内容，确认没有意外文件：

   ```bash
   unzip -l ~/Downloads/Fishing_Harness_v0.1_Implementation_Pack.zip
   ```

3. 先备份现有项目或至少查看 Git 状态：

   ```bash
   cd /Users/rain/DevGame/Fishing
   git status --short  # 如果尚未初始化 Git，忽略这一行的报错
   ```

4. 不覆盖现有同名文件，解压：

   ```bash
   unzip -n ~/Downloads/Fishing_Harness_v0.1_Implementation_Pack.zip -d /Users/rain/DevGame/Fishing
   ```

   `-n` 表示跳过已经存在的目标文件；若已有 `AGENTS.md` 或其他同名文件被跳过，请**比较合并**，不要随便删旧文件、也不要用 `-o` 强行覆盖。
5. 在 Finder 按 `Cmd+Shift+G` 可定位项目。隐藏目录 `.dsh` 可用 `Cmd+Shift+.` 显示。
6. 在 Harness 中选择 `/Users/rain/DevGame/Fishing` 作为工作区，保持 **单 Agent 串行**，模型为本地 Flash；先阅读 `AGENTS.md`、`docs/SDD_v0.1.md`、`tasks/TASKS.md`。
7. 先运行 `SPIKE-001` 的只读检查及 macOS 透明窗口探针；提交证据和用户审核后再进入后续工单。

## 目录导航

| 文件 | 作用 |
|---|---|
| `AGENTS.md` | Harness 项目级安全、执行、测试、审批规则；每次任务优先阅读 |
| `docs/SDD_v0.1.md` | v0.1 **唯一待审批的功能范围规范** |
| `docs/ARCHITECTURE.md` | 最小模块划分、状态权威与数据流、Godot 平台抽象 |
| `docs/INTERFACES_AND_DATA.md` | 鱼类配置、存档、结算、计时、事件与不变量 |
| `docs/ACCEPTANCE_TESTS.md` | 自动测试/模拟/人工验收与放行标准 |
| `docs/TECH_SPIKE.md` | macOS 透明/穿透/拖动技术风险验证方案 |
| `docs/PRODUCT_ROADMAP.md` | v0.2+ 冻结边界与已确定的长期玩法（**不前移**） |
| `docs/DECISION_REGISTER.md` | 当前可恢复 SDD 选择及覆盖关系 |
| `docs/REQUIREMENTS_CHANGELOG.md` | 版本变更、未核实项目、正式冻结手续 |
| `docs/HARNESS_LOCAL_SETUP.md` | 本地 llama.cpp / Harness 验证、单模型资源约束 |
| `docs/SKILLS_INTEGRATION.md` | 项目 Skills、用户 Skills 的发现及验证步骤 |
| `tasks/TASKS.md` | 可执行的原子工单、依赖及每一步验收 |
| `tasks/TICKET_TEMPLATE.md` | 后续新工单格式 |
| `schemas/*.json` | v0.1 数据校验契约的 JSON Schema 草案 |
| `examples/*.json` | 示意配置和鱼种；**非已经调优的最终平衡数据** |
| `.dsh/skills/*/SKILL.md` | 可被 Harness 发现的 3 个本项目 Skills |

## 现在给 Harness 的第一条命令

在 Plan Mode 发送：

> 工作区是 `/Users/rain/DevGame/Fishing`。只读检查此工程。先阅读 `AGENTS.md`、`docs/SDD_v0.1.md`、`docs/TECH_SPIKE.md`、`tasks/TASKS.md` 和 `docs/SKILLS_INTEGRATION.md`；检查 Git 状态、Godot 版本、已有文件与可发现的 skills。说明本包与现有工程是否冲突；提交 SPIKE-001 实施计划和可复核命令。此阶段不要修改、删除文件，不要启动子 Agent，不要下载模型，不要扩大 v0.1 范围。若 SDD 中有疑点，请报告，不能自行替用户决策。

**首次真正编码前的门禁**：用户批准范围与技术探针计划；重要风险由人决定。
