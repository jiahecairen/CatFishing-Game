# DeepSeek Harness Skills 接入与验证

## 1. 实际可发现条件

用户以前的**自定义** Agent 预设包含 `@deepseek-ai/dsh-skill-filesystem` 和 `@deepseek-ai/dsh-tool-skill`，但用户目前切到 Harness **Standard**。不能仅凭旧自定义预设断定标准模式已启用相同插件：**必须在当前 Standard 会话中列出真实技能目录**。

官方文件系统 Skill Provider 的默认发现根（前提是已启用）：

1. `<projectRoot>/.dsh/skills/`
2. `<projectRoot>/.agents/skills/`
3. 配置的额外自定义目录
4. `~/.dsh/skills/`
5. `~/.agents/skills/`（用户以前提到 `/Users/rain/.agents/skills/`）

项目根通常是最近的 `.git` 祖先，无 `.git` 时为当前工作目录。Skill 文件采用 `<root>/<kebab-name>/SKILL.md` 或 `<root>/<kebab-name>.md`，带合法 YAML frontmatter；**不会递归扫描多层嵌套的 `**/SKILL.md`**。

官方文档：https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/skill/skill-filesystem/README.md

## 2. 本 ZIP 新建的 3 个项目 Skills

- `.dsh/skills/godot-overlay/SKILL.md`：桌面窗口透明/穿透/拖动技术探针。
- `.dsh/skills/fishing-state-and-save/SKILL.md`：捕鱼状态机、幂等捕获/售鱼和可靠存档。
- `.dsh/skills/godot-validation/SKILL.md`：Godot 无界面测试、虚拟时间及验收证据。

**重要**：这三个是此包的新项目 Skills，不是对你已有 Skills 的复制或重装；既有用户 Skills 尚未核实。

## 3. 安装后在 Mac 执行只读检查

```bash
cd /Users/rain/DevGame/Fishing
find .dsh/skills -maxdepth 2 -name SKILL.md -print 2>/dev/null
find "$HOME/.agents/skills" -maxdepth 2 -name SKILL.md -print 2>/dev/null
find "$HOME/.dsh/skills" -maxdepth 2 -name SKILL.md -print 2>/dev/null
```

随后在 Harness 的当前工作区、新会话发送：

> 请只读列出**当前会话的 Skill 工具真实发现**的所有技能名称、来源及能否加载。确认是否包含 `godot-overlay`、`fishing-state-and-save`、`godot-validation`，以及 `~/.agents/skills/` 中已有的用户技能。不要执行技能的安装脚本；若没有发现，报告配置缺失，而不是声称已启用。

如果未发现：检查当前项目根、Standard 模式是否挂载 Skill registry + filesystem provider + tool-skill、frontmatter、Skill 目录级数。**不要无授权修改全局 Harness 配置**。

## 4. 使用规则

- 用户现有的任何 Skill 必须实际读取名称和描述；不要猜测已装 Godot/ComfyUI/Git 技能。
- 技能本身是流程说明，不自动赋予命令、文件权限或联网能力。
- 有相同目的时优先复用用户自己的，但以 `AGENTS.md` 和 `SDD_v0.1.md` 为产品范围准则。
- 不自动从网上下载未知 Skill；初期不用正式 AI 生成素材，v0.1 临时 sprite 足够。
- 单模型条件下禁止子 Agent 并行，不因 Skill 中出现 delegation 指令而违反工作区规则。
