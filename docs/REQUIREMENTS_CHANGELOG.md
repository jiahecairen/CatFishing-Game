# 需求变更与正式冻结记录

## 状态

- 2026-11-10：首次生成 **v0.1 Draft** 实施文档包。依据已知 SDD 决策摘要；**非**已获用户最终批准的正式冻结版。
- 2026-11-10：工具选择修订：旧“默认 Codex”**作废**；主执行器是 **DeepSeek Harness Desktop + 单个本地 Qwen Flash (llama.cpp)**。
- 2026-11-10：保留 175 对 076 的覆盖：可见桌面固定 30 FPS，不采用以前动态可见 FPS 档。
- 2026-11-10：保留 146/147 修订：没有罕见动画收藏、画廊、回放、成就历史功能。
- 2026-11-10：保留 176/177/178：上钩随机 20–60 秒、多随机种子模拟与人工确认经济参数。
- 2026-11-10：保留 164/165/179/180：v0.1 极小技术原型、阶段审批、不把未来内容前移。

## 未决/待核实清单

| ID | 问题 | 对当前开发的处理 |
|---|---|---|
| OPEN-001 | 在**窗口隐藏但进程仍运行**的情况下，已确定“不是完全退出”，但原始 SDD 的详细“有效捕鱼时间是否继续计时”约束未完整恢复 | 仅先开发可注入/可暂停的有效时间机制；正式设置隐藏时行为前请用户一次性裁定。禁止发放正式离线收入 |
| OPEN-002 | 早期 SDD-001～122 的逐条完整源记录、可能存在的旧 SDD/PDF | 如有原档进行一次性 diff；本包不冒充全量核验 |
| OPEN-003 | 本机已有 Godot 工程及 Git 状态、现有个人 Skills 具体名称 | 用户本机 Harness 先只读核查，不能默认覆盖已有内容 |
| OPEN-004 | 售鱼选中/全部出售交互细节、视觉临时基准像素、收竿/抛竿时长 | 技术实现可提出最小方案，涉及用户体验/经济变化先请确认 |
| OPEN-005 | 服务端实际 256K 上下文、65,536 输出上限是否同时受支持，以及标准模式工具兼容性 | 进入编码前跑真实工具调用与内存压力测试，不以 GUI 设置值冒充成功 |

## 冻结前的审查清单

- [ ] 用户查看 `docs/SDD_v0.1.md` MUST/WON'T 并确认边界。
- [ ] 核对本机已有旧文档，按需合并；不存在覆盖未审查 Git 改动。
- [ ] OPEN-001 及影响 v0.1 的其他重大歧义有用户决定或明确推迟。
- [ ] `docs/ARCHITECTURE.md` 与 `docs/INTERFACES_AND_DATA.md` 接口边界被批准。
- [ ] 测试、工单、实际平台与本地 AI 限制已可执行。
- [ ] 由用户写明“批准冻结 v0.1”及日期后将 SDD 状态改为 `Frozen`。

## 未来变更记录模板

```text
Date:
Change ID:
Requestor:
Original SDD / requirement:
Proposed change:
Why:
Scope: v0.1 bugfix / later-version proposal / critical platform issue
Risk and migration:
Tests:
Owner approval (required for scope/economy/save/paid/privacy/platform change):
Changed files / Git commit:
```

**规则**：后续 v0.2+ 的新想法进入提案池，不自动重开 v0.1 的需求冻结。
