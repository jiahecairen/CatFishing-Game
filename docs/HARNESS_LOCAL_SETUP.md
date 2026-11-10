# 本地执行环境 — DeepSeek Harness + llama.cpp + 单个 Qwen Flash

## 1. 当前环境（需在用户 Mac 实测）

- macOS / M4 Max / 128GB 统一内存；DeepSeek Harness Desktop **Standard** 预设，而不是 Codex。
- llama.cpp GUI 中加载的本地模型：`ggml-org/Qwen3.8-Flash-Next-GGUF:IQ4_NL`。
- 用户截图出现的 API URL `http://127.0.0.1:9931/v1`；端口可能变化，以当前 `/v1/models` 返回值和 llama.cpp UI 为准。
- Harness 模型配置目标：256K 上下文、单次最大输出 65536；**不要假定实际生效**。用户曾看到实际会话上下文约 131K，须核对服务和 Harness adapter。
- **只用一个大型模型和一个串行 Agent**；不要启动子 Agent、fork、并行工作流、第二个模型。

## 2. 只读命令

```bash
curl -s http://127.0.0.1:9931/health
curl -s http://127.0.0.1:9931/v1/models
command -v godot || command -v godot4 || true
[ -x /Applications/Godot.app/Contents/MacOS/Godot ] && /Applications/Godot.app/Contents/MacOS/Godot --version
cd /Users/rain/DevGame/Fishing
pwd
ls -la
git status --short 2>/dev/null || true
```

以上不更改文件。若端口不一致先从 llama.cpp 当前界面确认。不要在尚未备份/审查的工作区运行 `rm`、强制 `git reset`、`git clean` 等破坏性命令。

## 3. Harness 配置核对

| 项目 | 目标 |
|---|---|
| 协议 | OpenAI Chat Completions（服务端须真支持 tools） |
| Base URL | 实际 llama.cpp 地址，如 `http://127.0.0.1:9931/v1` |
| Model ID | `/v1/models` 返回的**精确 ID** |
| Context | 当前填写 256K；必须与实际模型服务及有效会话一致 |
| Maximum Output | 当前填写 65536；不能超出剩余上下文容量 |
| Tool use | 必须实测文件操作/终端操作，不以聊天成功代替 |
| Parallelism | 单 Agent 串行；服务端建议单推理槽 |

旧自定义 Agent 预设含并行插件及 compaction 配置；用户目前改成标准模式，无需为本包恢复旧预设。压缩摘要 `maxTokens` 与主模型回答的 65536 是两个不同的参数。

## 4. 开发前的最小链路测试

1. 普通中文短问题、无工具调用：验证模型 API 通。
2. 在本项目明确授权的测试子目录创建一个非敏感文件，读取、核对内容；文件真实存在才算调用成功。
3. 实际运行一次 Godot `--headless` 项目加载、检查退出码；不能假报已运行。
4. 在 macOS 活动监视器查看内存压力/交换空间；单一大模型也可能占用超 100GB 的运行内存。
5. 检查 Harness 当前有效上下文是否确实为 256K；若仍显示 131K，先修 adapter/context 配置，再执行长工单。

## 5. 上下文策略

- 用 Git 文件、开发日志、原子任务保持长期状态，而不是依赖 256K 对话不丢记忆。
- 每张票只读取必要模块、SDD 小节；单任务结束后让 Agent 输出实际文件更改与测试证据。
- 遇到 `context compaction failed`，检查 adapter 的有效上下文与预留 completion token，**不要**把摘要 maxTokens 设为 256K。
- `generation thread died` 时先停止重试、检查内存，必要时降低并发/活跃上下文，不能同时自动加载另一个大型模型。
- 网络、收费云模型、插件安装，都需要用户批准，不可自动切换外部服务。
